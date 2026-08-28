// TEST-20: Gerçek Saha Fotoğraflarından Geri Bildirim Döngüsü (Modül 15
// uzantısı) — bkz. database.js isg_reports.human_verified_damage,
// routes/isg.js PATCH /:id/verify-damage, routes/risk.js
// GET /api/ml/damage-model-performance.
const { describe, it, beforeEach } = require('node:test');
const assert = require('node:assert');
const request = require('supertest');
const app = require('../../server');
const db = require('../../database');
const { resetTestDatabase, seedMinimalTestData } = require('../helpers/testDb');
const { getTestToken } = require('../helpers/authHelper');

function insertIsgReport(userId, { cvIsDamaged = null, humanVerifiedDamage = null } = {}) {
  const now = new Date().toISOString();
  return db
    .prepare(
      `INSERT INTO isg_reports
         (reported_by_user_id, description, category, lat, lng, status, created_at, cv_is_damaged, human_verified_damage)
       VALUES (?, 'Test bildirimi', 'tehlikeli_durum', 39.9086, 41.2769, 'bekliyor', ?, ?, ?)`
    )
    .run(userId, now, cvIsDamaged, humanVerifiedDamage).lastInsertRowid;
}

function getIsgReport(id) {
  return db.prepare('SELECT * FROM isg_reports WHERE id = ?').get(id);
}

describe('PATCH /api/isg-reports/:id/verify-damage', () => {
  let seeded;
  let dispatcherToken;
  let technicianToken;
  let isgReportId;

  beforeEach(() => {
    resetTestDatabase();
    seeded = seedMinimalTestData();
    dispatcherToken = getTestToken('dispecer');
    technicianToken = getTestToken('teknisyen');
    isgReportId = insertIsgReport(seeded.users.teknisyenId, { cvIsDamaged: 1 });
  });

  it('dispeçer "hasarlı" (true) olarak işaretleyince human_verified_damage=1 olur', async () => {
    const response = await request(app)
      .patch(`/api/isg-reports/${isgReportId}/verify-damage`)
      .set('Authorization', `Bearer ${dispatcherToken}`)
      .send({ actual_damage: true });

    assert.strictEqual(response.status, 200);
    assert.strictEqual(getIsgReport(isgReportId).human_verified_damage, 1);
  });

  it('dispeçer "hasarsız" (false) olarak işaretleyince human_verified_damage=0 olur (NULL DEĞİL)', async () => {
    const response = await request(app)
      .patch(`/api/isg-reports/${isgReportId}/verify-damage`)
      .set('Authorization', `Bearer ${dispatcherToken}`)
      .send({ actual_damage: false });

    assert.strictEqual(response.status, 200);
    assert.strictEqual(getIsgReport(isgReportId).human_verified_damage, 0);
  });

  it('teknisyen (dispeçer/yönetici DEĞİL) doğrulama yapamaz — 403', async () => {
    const response = await request(app)
      .patch(`/api/isg-reports/${isgReportId}/verify-damage`)
      .set('Authorization', `Bearer ${technicianToken}`)
      .send({ actual_damage: true });

    assert.strictEqual(response.status, 403);
    assert.strictEqual(getIsgReport(isgReportId).human_verified_damage, null);
  });

  it('token olmadan 401 döner', async () => {
    const response = await request(app)
      .patch(`/api/isg-reports/${isgReportId}/verify-damage`)
      .send({ actual_damage: true });
    assert.strictEqual(response.status, 401);
  });

  it('actual_damage eksik/yanlış tipte gönderilirse 400 döner (500 ASLA)', async () => {
    const responses = await Promise.all(
      [{}, { actual_damage: 'evet' }, { actual_damage: 1 }, { actual_damage: null }].map((body) =>
        request(app)
          .patch(`/api/isg-reports/${isgReportId}/verify-damage`)
          .set('Authorization', `Bearer ${dispatcherToken}`)
          .send(body)
      )
    );
    for (const response of responses) {
      assert.strictEqual(response.status, 400, JSON.stringify(response.body));
    }
  });

  it('var olmayan bir bildirim id\'si için 404 döner', async () => {
    const response = await request(app)
      .patch('/api/isg-reports/999999/verify-damage')
      .set('Authorization', `Bearer ${dispatcherToken}`)
      .send({ actual_damage: true });
    assert.strictEqual(response.status, 404);
  });
});

describe('GET /api/ml/damage-model-performance', () => {
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
    const noAuth = await request(app).get('/api/ml/damage-model-performance');
    assert.strictEqual(noAuth.status, 401);

    const wrongRole = await request(app)
      .get('/api/ml/damage-model-performance')
      .set('Authorization', `Bearer ${technicianToken}`);
    assert.strictEqual(wrongRole.status, 403);
  });

  it('[AZ VERİ] 20 karşılaştırılabilir kayıttan AZ varsa has_enough_data=false döner', async () => {
    insertIsgReport(seeded.users.teknisyenId, { cvIsDamaged: 1, humanVerifiedDamage: 1 });
    insertIsgReport(seeded.users.teknisyenId, { cvIsDamaged: 0, humanVerifiedDamage: 0 });

    const response = await request(app)
      .get('/api/ml/damage-model-performance')
      .set('Authorization', `Bearer ${managerToken}`);

    assert.strictEqual(response.status, 200);
    assert.strictEqual(response.body.comparable_predictions, 2);
    assert.strictEqual(response.body.has_enough_data, false);
    assert.strictEqual(response.body.min_required_for_reliable_summary, 20);
  });

  it('uyuşma oranını (cv_is_damaged vs human_verified_damage) doğru hesaplar', async () => {
    // 3 uyuşan (model doğru bildi), 1 uyuşmayan (model yanıldı) = %75 uyuşma
    insertIsgReport(seeded.users.teknisyenId, { cvIsDamaged: 1, humanVerifiedDamage: 1 });
    insertIsgReport(seeded.users.teknisyenId, { cvIsDamaged: 0, humanVerifiedDamage: 0 });
    insertIsgReport(seeded.users.teknisyenId, { cvIsDamaged: 1, humanVerifiedDamage: 1 });
    insertIsgReport(seeded.users.teknisyenId, { cvIsDamaged: 1, humanVerifiedDamage: 0 }); // model yanıldı

    // Yalnızca insan doğrulaması var, model BELİRSİZ kaldı (cv_is_damaged NULL)
    // -> karşılaştırılabilir SAYILMAMALI.
    insertIsgReport(seeded.users.teknisyenId, { cvIsDamaged: null, humanVerifiedDamage: 1 });

    // Yalnızca model tahmini var, insan henüz doğrulamadı -> karşılaştırılabilir SAYILMAMALI.
    insertIsgReport(seeded.users.teknisyenId, { cvIsDamaged: 1, humanVerifiedDamage: null });

    const response = await request(app)
      .get('/api/ml/damage-model-performance')
      .set('Authorization', `Bearer ${managerToken}`);

    assert.strictEqual(response.status, 200);
    assert.strictEqual(response.body.comparable_predictions, 4);
    assert.strictEqual(response.body.agreement_count, 3);
    assert.strictEqual(response.body.agreement_rate_percent, 75);
    assert.strictEqual(response.body.total_verified, 5, 'human_verified_damage dolu olan TÜM kayıtlar (model belirsiz olsa bile)');
  });
});
