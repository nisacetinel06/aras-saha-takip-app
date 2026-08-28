// TEST-19: Gerçek Geri Bildirim Döngüsü (Modül 9 uzantısı) — bkz.
// database.js risk_prediction_outcomes, routes/risk.js, jobs/riskOutcomeExpiry.js.
//
// TEST İZOLASYONU NOTU: routes/risk.js'teki computeAndSaveRisk() ayrı bir
// Python (FastAPI) ML servisine GERÇEK bir HTTP isteği atar (bkz.
// callMlService) — bu servis test ortamında ayağa kaldırılmaz (diğer hiçbir
// test dosyası da kaldırmıyor, arassaha-ml bu repodaki testlerin kapsamı
// DIŞINDA ayrı bir Python projesidir). Bu yüzden "bir ekipman için risk
// tahmini yap" adımı, computeAndSaveRisk'in YAPACAĞI ŞEYİ (risk_prediction_outcomes'a
// bir satır eklemek) doğrudan simüle eder — sınır (ML servisiyle HTTP), test
// edilen asıl mantığın (otomatik sonuç eşleştirme + 90 gün süre dolumu +
// performans özeti) DIŞINDadır.
const { describe, it, beforeEach } = require('node:test');
const assert = require('node:assert');
const request = require('supertest');
const app = require('../../server');
const db = require('../../database');
const { resetTestDatabase, seedMinimalTestData } = require('../helpers/testDb');
const { getTestToken } = require('../helpers/authHelper');
const { expireStalePredictions, OUTCOME_EXPIRY_DAYS } = require('../../jobs/riskOutcomeExpiry');

function insertPrediction(equipmentId, riskScore, predictedAt) {
  return db
    .prepare(
      `INSERT INTO risk_prediction_outcomes (equipment_id, predicted_risk_score, predicted_at)
       VALUES (?, ?, ?)`
    )
    .run(equipmentId, riskScore, predictedAt).lastInsertRowid;
}

function getPrediction(id) {
  return db.prepare('SELECT * FROM risk_prediction_outcomes WHERE id = ?').get(id);
}

function daysAgoIso(days) {
  return new Date(Date.now() - days * 24 * 60 * 60 * 1000).toISOString();
}

describe('Gerçek Geri Bildirim Döngüsü — risk_prediction_outcomes', () => {
  let seeded;
  let dispatcherToken;
  let managerToken;

  beforeEach(() => {
    resetTestDatabase();
    seeded = seedMinimalTestData();
    dispatcherToken = getTestToken('dispecer');
    managerToken = getTestToken('yonetici');
  });

  it('[UÇTAN UCA] arıza iş emri oluşturulunca, aynı ekipman için sonuçlanmamış tahmin OTOMATİK "arızalandı" olarak işaretlenir', async () => {
    const predictionId = insertPrediction(seeded.equipmentId, 78, daysAgoIso(3));

    const response = await request(app)
      .post('/api/workorders')
      .set('Authorization', `Bearer ${dispatcherToken}`)
      .send({
        title: 'Trafo arızası',
        priority: 'acil',
        assigned_user_id: seeded.users.teknisyenId,
        equipment_id: seeded.equipmentId,
      });
    assert.strictEqual(response.status, 201);

    const prediction = getPrediction(predictionId);
    assert.strictEqual(prediction.actual_fault_occurred, 1, 'kimse elle işaretlemedi, sistem otomatik eşleştirmeli');
    assert.strictEqual(prediction.fault_work_order_id, response.body.id);
    assert.ok(prediction.outcome_recorded_at, 'outcome_recorded_at doldurulmalı');
  });

  it('90 günden ESKİ bir tahmin, yeni arıza iş emriyle EŞLEŞTİRİLMEZ (pencere dışı)', async () => {
    const predictionId = insertPrediction(seeded.equipmentId, 78, daysAgoIso(120));

    await request(app)
      .post('/api/workorders')
      .set('Authorization', `Bearer ${dispatcherToken}`)
      .send({
        title: 'Trafo arızası',
        priority: 'acil',
        assigned_user_id: seeded.users.teknisyenId,
        equipment_id: seeded.equipmentId,
      });

    const prediction = getPrediction(predictionId);
    assert.strictEqual(prediction.actual_fault_occurred, null, '90 gün penceresinin dışındaki tahmin eşleşmemeli');
  });

  it('BAŞKA bir ekipmana ait tahmin, bu ekipman için açılan arızayla EŞLEŞTİRİLMEZ', async () => {
    const otherEquipmentId = db
      .prepare(
        `INSERT INTO equipment (qr_code, equipment_type, il, ilce, mahalle, location_name, lat, lng, status, created_at)
         VALUES ('TEST-OTHER', 'direk', 'Erzurum', 'Yakutiye', 'Merkez', 'x', 39.9, 41.2, 'aktif', ?)`
      )
      .run(new Date().toISOString()).lastInsertRowid;

    const predictionId = insertPrediction(otherEquipmentId, 90, daysAgoIso(1));

    await request(app)
      .post('/api/workorders')
      .set('Authorization', `Bearer ${dispatcherToken}`)
      .send({
        title: 'Trafo arızası',
        priority: 'acil',
        assigned_user_id: seeded.users.teknisyenId,
        equipment_id: seeded.equipmentId,
      });

    const prediction = getPrediction(predictionId);
    assert.strictEqual(prediction.actual_fault_occurred, null, 'başka ekipmanın tahminine dokunulmamalı');
  });

  it('hiç tahmin YOKKEN arıza iş emri oluşturmak hataya düşmemeli (201 döner)', async () => {
    const response = await request(app)
      .post('/api/workorders')
      .set('Authorization', `Bearer ${dispatcherToken}`)
      .send({
        title: 'Tahminsiz ekipman arızası',
        priority: 'normal',
        assigned_user_id: seeded.users.teknisyenId,
        equipment_id: seeded.equipmentId,
      });
    assert.strictEqual(response.status, 201);
  });
});

describe('jobs/riskOutcomeExpiry.js — 90 gün sonra "arızalanmadı" işaretleme', () => {
  let seeded;

  beforeEach(() => {
    resetTestDatabase();
    seeded = seedMinimalTestData();
  });

  it(`${OUTCOME_EXPIRY_DAYS} günden eski, sonuçlanmamış tahminler dryRun:false ile 0 (arızalanmadı) yapılır`, () => {
    const stalePredictionId = insertPrediction(seeded.equipmentId, 45, daysAgoIso(OUTCOME_EXPIRY_DAYS + 1));
    const freshPredictionId = insertPrediction(seeded.equipmentId, 45, daysAgoIso(5));

    const expired = expireStalePredictions({ dryRun: false });

    assert.strictEqual(expired.length, 1);
    assert.strictEqual(expired[0].id, stalePredictionId);

    assert.strictEqual(getPrediction(stalePredictionId).actual_fault_occurred, 0);
    assert.ok(getPrediction(stalePredictionId).outcome_recorded_at);
    assert.strictEqual(getPrediction(freshPredictionId).actual_fault_occurred, null, 'henüz 90 günü doldurmamış kayda dokunulmamalı');
  });

  it('dryRun:true (varsayılan) HİÇBİR ŞEYİ değiştirmez, yalnızca listeler', () => {
    const stalePredictionId = insertPrediction(seeded.equipmentId, 45, daysAgoIso(OUTCOME_EXPIRY_DAYS + 10));

    const preview = expireStalePredictions();

    assert.strictEqual(preview.length, 1);
    assert.strictEqual(getPrediction(stalePredictionId).actual_fault_occurred, null, 'dryRun modunda DB değişmemeli');
  });

  it('actual_fault_occurred=1 (zaten arızalanmış) kayıtlar süresi dolsa bile tekrar değiştirilmez', () => {
    const resolvedId = insertPrediction(seeded.equipmentId, 90, daysAgoIso(OUTCOME_EXPIRY_DAYS + 30));
    db.prepare('UPDATE risk_prediction_outcomes SET actual_fault_occurred = 1, outcome_recorded_at = ? WHERE id = ?')
      .run(daysAgoIso(1), resolvedId);

    const expired = expireStalePredictions({ dryRun: false });

    assert.strictEqual(expired.length, 0, 'zaten sonuçlanmış kayıt tekrar taranmamalı');
    assert.strictEqual(getPrediction(resolvedId).actual_fault_occurred, 1);
  });
});

describe('GET /api/ml/risk-model-performance', () => {
  let seeded;
  let managerToken;
  let technicianToken;

  beforeEach(() => {
    resetTestDatabase();
    seeded = seedMinimalTestData();
    managerToken = getTestToken('yonetici');
    technicianToken = getTestToken('teknisyen');
  });

  it('token olmadan 401, yönetici olmayan rol için 403 döner', async () => {
    const noAuth = await request(app).get('/api/ml/risk-model-performance');
    assert.strictEqual(noAuth.status, 401);

    const wrongRole = await request(app)
      .get('/api/ml/risk-model-performance')
      .set('Authorization', `Bearer ${technicianToken}`);
    assert.strictEqual(wrongRole.status, 403);
  });

  it('[AZ VERİ] 20 sonuçlanmış tahminden AZ varsa has_enough_data=false döner', async () => {
    for (let i = 0; i < 5; i++) {
      const id = insertPrediction(seeded.equipmentId, 80, daysAgoIso(10));
      db.prepare('UPDATE risk_prediction_outcomes SET actual_fault_occurred = 1, outcome_recorded_at = ? WHERE id = ?')
        .run(daysAgoIso(1), id);
    }

    const response = await request(app)
      .get('/api/ml/risk-model-performance')
      .set('Authorization', `Bearer ${managerToken}`);

    assert.strictEqual(response.status, 200);
    assert.strictEqual(response.body.resolved_predictions, 5);
    assert.strictEqual(response.body.has_enough_data, false);
    assert.strictEqual(response.body.min_required_for_reliable_summary, 20);
  });

  it('doğruluk oranlarını risk_score bucket\'ına göre doğru hesaplar (yüksek->arızalandı, düşük->arızalanmadı)', async () => {
    // 4 "yüksek" (skor>66) tahmin: 3'ü arızalandı, 1'i arızalanmadı -> %75 isabet
    const highScores = [70, 75, 80, 90];
    const highOutcomes = [1, 1, 1, 0];
    highScores.forEach((score, i) => {
      const id = insertPrediction(seeded.equipmentId, score, daysAgoIso(10));
      db.prepare('UPDATE risk_prediction_outcomes SET actual_fault_occurred = ?, outcome_recorded_at = ? WHERE id = ?')
        .run(highOutcomes[i], daysAgoIso(1), id);
    });

    // 4 "düşük" (skor<=33) tahmin: hepsi arızalanmadı -> %100 isabet
    for (let i = 0; i < 4; i++) {
      const id = insertPrediction(seeded.equipmentId, 20, daysAgoIso(10));
      db.prepare('UPDATE risk_prediction_outcomes SET actual_fault_occurred = 0, outcome_recorded_at = ? WHERE id = ?')
        .run(daysAgoIso(1), id);
    }

    // Sonuçlanmamış (beklemede) bir kayıt — resolved sayacına dahil OLMAMALI
    insertPrediction(seeded.equipmentId, 50, daysAgoIso(1));

    const response = await request(app)
      .get('/api/ml/risk-model-performance')
      .set('Authorization', `Bearer ${managerToken}`);

    assert.strictEqual(response.status, 200);
    assert.strictEqual(response.body.resolved_predictions, 8);
    assert.strictEqual(response.body.pending_predictions, 1);
    assert.strictEqual(response.body.high_risk.total, 4);
    assert.strictEqual(response.body.high_risk.faulted, 3);
    assert.strictEqual(response.body.high_risk.fault_rate_percent, 75);
    assert.strictEqual(response.body.low_risk.total, 4);
    assert.strictEqual(response.body.low_risk.not_faulted, 4);
    assert.strictEqual(response.body.low_risk.no_fault_rate_percent, 100);
  });
});
