// Arıza Risk Tahmini (Modül 9).
//
// Bu route, ekipman verisini SQLite'tan okuyup ayrı bir Python (FastAPI) ML
// servisine (varsayılan http://localhost:8000, bkz. arassaha-ml/) HTTP ile
// gönderir, dönen risk skorunu equipment_risk_scores tablosuna yazar/okur.
// İki katman birbirine yalnızca HTTP üzerinden bağlıdır — Node bu servisi
// import etmez, ayrı bir process olarak çalışır ve bağımsız başlatılıp
// durdurulabilir.
//
// DÜRÜSTLÜK NOTU: Skorları üreten model, gerçek arıza kaydı olmadığı için
// SENTETİK (kural tabanlı üretilmiş) bir veri setiyle eğitildi (bkz.
// arassaha-ml/generate_training_data.py, arassaha-ml/README.md). Model
// eğitimi/servis/entegrasyon süreci gerçektir; veri sentetiktir. Gerçek
// üretimde model, ArasSaha'nın gerçek work_orders/equipment geçmişiyle
// yeniden eğitilir; bu route'ta hiçbir değişiklik gerekmez.
const express = require('express');
const db = require('../database');
const { requireRole } = require('../middleware/auth');
const { createNotification } = require('../utils/notify');
const { asyncHandler } = require('../utils/asyncHandler');

const router = express.Router();

// Python servisinin adresi — Railway gibi bir ortamda Node ve Python ayrı
// servisler olarak deploy edilirse bu, ortam değişkeniyle geçersiz kılınır.
const ML_SERVICE_URL = process.env.ML_SERVICE_URL || 'http://localhost:8000';

function calculateAgeYears(installDate) {
  if (!installDate) return 5; // kurulum tarihi bilinmiyorsa makul bir varsayılan
  const days = (Date.now() - new Date(installDate).getTime()) / (1000 * 60 * 60 * 24);
  return Math.max(0, days / 365.25);
}

// asOfDate: testlerin "şu an"ı sabit bir referans tarihle enjekte edebilmesi
// için eklendi (bkz. test/unit/riskDateCalculation.test.js) — varsayılanı
// (new Date()) verilmezse gerçek çağrı yerleri (buildFeatures, routes/maintenance.js)
// hep bugünün tarihini kullanmaya devam eder, davranış değişmez.
function calculateMonthsSinceMaintenance(lastMaintenanceDate, installDate, asOfDate = new Date()) {
  // Hiç bakım kaydı yoksa referans olarak kurulum tarihi kullanılır — o
  // tarihten bu yana da bakım görmemiş demektir.
  const reference = lastMaintenanceDate || installDate;
  if (!reference) return 12;
  const referenceTime = new Date(reference).getTime();
  // reference sayısal olarak ayrıştırılamayan bir tarihse (bozuk veri), sessizce
  // NaN üretip risk modeline sızmasındansa burada açıkça durur — equipment.last_maintenance_date/
  // install_date şu an her zaman kod tarafından (new Date().toISOString() veya
  // seed.js) üretildiğinden gerçek akışta TETİKLENMEZ (bkz. routes/workOrders.js
  // last_maintenance_date güncellemesi), yalnızca bir savunma hattı.
  if (Number.isNaN(referenceTime)) {
    throw new TypeError(`calculateMonthsSinceMaintenance: geçersiz tarih değeri: ${reference}`);
  }
  const days = (asOfDate.getTime() - referenceTime) / (1000 * 60 * 60 * 24);
  return Math.max(0, days / 30.44);
}

function countPastFaults(equipmentId) {
  const row = db.prepare('SELECT COUNT(*) AS c FROM work_orders WHERE equipment_id = ?').get(equipmentId);
  return row.c;
}

// avg_load_factor için gerçek telemetri/SCADA verisi yok (bu bir staj
// prototipi, bkz. ARCHITECTURE.md Bölüm 10). ÖNCEDEN her hesaplamada
// Math.random() ile üretiliyordu — bu, hiçbir gerçek durum değişmese bile
// aynı ekipmanın skorunun her yeniden hesaplamada rastgele oynamasına ve
// eşiğe yakın ekipmanların "yüksek" seviyeye anlamsızca girip çıkmasına
// (dolayısıyla gereksiz/yanıltıcı tekrar bildirimlere) yol açıyordu.
//
// Bunun yerine ekipman TİPİNE göre SABİT, deterministik bir tipik yük
// faktörü kullanılır (elektrik mühendisliği açısından makul bir varsayım:
// trafo ve kesici sürekli daha yüksek elektriksel yük altında çalışır,
// direk/sayaç görece daha az yüklüdür — bkz. arassaha-ml/generate_training_data.py
// TYPE_BASE_RISK ile aynı mantık). Aynı ekipman için her hesaplamada TAM
// OLARAK aynı değeri döner; skordaki tek gerçek değişken artık gerçekten
// değişen veriler (yaş, son bakımdan geçen süre, geçmiş arıza sayısı) olur.
// Gerçek üretimde bu, sayaç/SCADA verisinden hesaplanmış gerçek bir ortalama
// yük faktörüyle değiştirilir; model/servis mimarisinde değişiklik gerekmez.
const TYPICAL_LOAD_FACTOR = {
  trafo: 0.75,
  kesici: 0.7,
  direk: 0.6,
  sayac: 0.55,
};

function typicalLoadFactor(equipmentType) {
  return TYPICAL_LOAD_FACTOR[equipmentType] ?? 0.65;
}

function buildFeatures(equipment) {
  return {
    equipment_age_years: Math.round(calculateAgeYears(equipment.install_date) * 100) / 100,
    months_since_maintenance:
      Math.round(calculateMonthsSinceMaintenance(equipment.last_maintenance_date, equipment.install_date) * 10) / 10,
    past_fault_count: countPastFaults(equipment.id),
    equipment_type: equipment.equipment_type,
    avg_load_factor: typicalLoadFactor(equipment.equipment_type),
  };
}

async function callMlService(features) {
  const response = await fetch(`${ML_SERVICE_URL}/predict`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(features),
  });

  if (!response.ok) {
    const text = await response.text().catch(() => '');
    throw new Error(`ML servisi hata döndü (HTTP ${response.status}): ${text}`);
  }

  return response.json();
}

const upsertRiskScore = db.prepare(`
  INSERT INTO equipment_risk_scores (equipment_id, risk_score, risk_level, computed_at)
  VALUES (@equipment_id, @risk_score, @risk_level, @computed_at)
  ON CONFLICT(equipment_id) DO UPDATE SET
    risk_score = excluded.risk_score,
    risk_level = excluded.risk_level,
    computed_at = excluded.computed_at
`);

// TEST-19: Gerçek Geri Bildirim Döngüsü (bkz. database.js risk_prediction_outcomes,
// README.md "Gerçek Geri Bildirim Döngüsü"). equipment_risk_scores'un aksine
// bu tabloya YENİ bir satır EKLENİR (geçmiş biriktirir) — amaç, "o anda
// verilen tahmin sonradan doğru çıktı mı" sorusunu zamanla takip etmek.
const insertPredictionOutcome = db.prepare(`
  INSERT INTO risk_prediction_outcomes (equipment_id, predicted_risk_score, predicted_at)
  VALUES (@equipment_id, @predicted_risk_score, @predicted_at)
`);

const findRecentUnresolvedPrediction = db.prepare(`
  SELECT id FROM risk_prediction_outcomes
  WHERE equipment_id = ? AND actual_fault_occurred IS NULL AND predicted_at > datetime('now', '-1 day')
  LIMIT 1
`);

// server.js her başlangıçta VE yönetici "yeniden hesapla" butonuna her
// bastığında refreshAllRiskScores()'u çağırır — bu koruma olmasa, aynı gün
// içindeki her tetikleme aynı ekipman için YENİ bir "sonuçlanmamış tahmin"
// satırı açar ve GET /api/ml/risk-model-performance istatistiklerinin
// paydası anlamsızca şişerdi. Son 24 saat içinde zaten sonuçlanmamış bir
// kayıt varsa yeni bir satır AÇILMAZ — o günün "resmi" tahmini olarak
// mevcut satır kalır.
function recordPredictionOutcome(equipmentId, riskScore, predictedAt) {
  if (findRecentUnresolvedPrediction.get(equipmentId)) return;

  insertPredictionOutcome.run({
    equipment_id: equipmentId,
    predicted_risk_score: riskScore,
    predicted_at: predictedAt,
  });
}

// POST /api/workorders (routes/workOrders.js) tarafından çağrılır: yeni bir
// arıza iş emri belirli bir equipment_id'ye bağlıysa, o ekipman için son 90
// gün içinde SONUÇLANMAMIŞ (actual_fault_occurred IS NULL) bir risk tahmini
// var mı kontrol edilir — varsa "arızalandı" (1) olarak işaretlenir.
// TAMAMEN OTOMATİK: kimse elle bir şey işaretlemez, sistem "yüksek risk
// dediğimiz ekipman gerçekten arızalandı mı" sorusunu kendi kendine takip
// eder. Birden fazla sonuçlanmamış tahmin birikmiş olsa bile (24 saatlik
// korumaya rağmen farklı günlerde tekrar tekrar hesaplanmışsa) yalnızca EN
// SON tahmin eşleştirilir; daha eskiler jobs/riskOutcomeExpiry.js tarafından
// (90 gün dolunca) ayrıca "arızalanmadı" olarak kapatılır.
function recordFaultOutcomeIfPredicted(equipmentId, workOrderId) {
  const recentPrediction = db
    .prepare(
      `SELECT * FROM risk_prediction_outcomes
       WHERE equipment_id = ? AND actual_fault_occurred IS NULL AND predicted_at > datetime('now', '-90 days')
       ORDER BY predicted_at DESC LIMIT 1`
    )
    .get(equipmentId);

  if (!recentPrediction) return null;

  db.prepare(
    'UPDATE risk_prediction_outcomes SET actual_fault_occurred = 1, fault_work_order_id = ?, outcome_recorded_at = ? WHERE id = ?'
  ).run(workOrderId, new Date().toISOString(), recentPrediction.id);

  return recentPrediction.id;
}

// Bildirim Sistemi (Modül 6) — bir ekipmanın riski İLK KEZ 'yuksek' seviyeye
// geçtiğinde tüm yöneticilere bildirim gönderir. "İlk kez" şartı (eski değer
// zaten 'yuksek' değilse) kasıtlıdır: aksi halde her yeniden hesaplamada
// (örn. günlük otomatik refresh) aynı ekipman için tekrar tekrar bildirim
// gider ve bildirim listesi anlamsızca şişer.
function notifyManagersIfRiskBecameHigh(equipment, oldRiskLevel, newRiskLevel) {
  if (oldRiskLevel === 'yuksek' || newRiskLevel !== 'yuksek') return;

  const managers = db.prepare("SELECT id FROM users WHERE role = 'yonetici' AND is_active = 1").all();
  for (const manager of managers) {
    createNotification(
      manager.id,
      `${equipment.qr_code} (${equipment.location_name}) için arıza riski YÜKSEK seviyeye çıktı`,
      'equipment',
      equipment.id
    );
  }
}

async function computeAndSaveRisk(equipment) {
  const features = buildFeatures(equipment);
  const prediction = await callMlService(features);
  const computed_at = new Date().toISOString();

  const previous = db.prepare('SELECT risk_level FROM equipment_risk_scores WHERE equipment_id = ?').get(equipment.id);

  upsertRiskScore.run({
    equipment_id: equipment.id,
    risk_score: prediction.risk_score,
    risk_level: prediction.risk_level,
    computed_at,
  });

  recordPredictionOutcome(equipment.id, prediction.risk_score, computed_at);

  notifyManagersIfRiskBecameHigh(equipment, previous?.risk_level, prediction.risk_level);

  return { equipment_id: equipment.id, risk_score: prediction.risk_score, risk_level: prediction.risk_level, computed_at };
}

// Tüm ekipmanlar için risk skorunu yeniden hesaplar. Tek tek her ekipmanın
// hatası kendi try/catch'i içinde yutulur — ML servisi tamamen kapalıysa bile
// bu fonksiyon exception FIRLATMAZ, yalnızca `failed` sayısını raporlar. Bu,
// hem POST /refresh-risk-scores endpoint'i hem de server.js'teki başlangıç
// çağrısı tarafından ortak kullanılır.
async function refreshAllRiskScores() {
  const equipmentList = db.prepare('SELECT * FROM equipment').all();
  const updated = [];
  const errors = [];

  for (const equipment of equipmentList) {
    try {
      updated.push(await computeAndSaveRisk(equipment));
    } catch (err) {
      errors.push({ equipment_id: equipment.id, error: err.message });
    }
  }

  return { updated: updated.length, failed: errors.length, errors };
}

// POST /api/ml/refresh-risk-scores
// Tüm ekipmanların risk skorunu yeniden hesaplatan bakım/yönetim aksiyonu —
// yalnızca yönetici tetikleyebilir.
router.post('/ml/refresh-risk-scores', requireRole('yonetici'), asyncHandler(async (req, res) => {
  const result = await refreshAllRiskScores();

  if (result.updated === 0 && result.failed > 0) {
    // ML servisi büyük ihtimalle kapalı — uygulamanın çökmemesi/isteğin
    // hata fırlatmaması için nazikçe 200 + boş sonuçla dönüyoruz.
    return res.status(200).json({
      ...result,
      message: 'ML servisine ulaşılamadı, risk skorları güncellenemedi. Python servisinin (uvicorn) çalıştığından emin olun.',
    });
  }

  res.json(result);
}));

// GET /api/equipment/:id/risk
// Önce equipment_risk_scores tablosundan okur; hiç hesaplanmamışsa ML
// servisine anlık istek atıp sonucu hem kaydeder hem döner.
router.get('/equipment/:id/risk', asyncHandler(async (req, res) => {
  try {
    const id = Number(req.params.id);
    if (!Number.isInteger(id)) {
      return res.status(400).json({ error: 'Geçersiz ekipman id değeri.' });
    }

    const equipment = db.prepare('SELECT * FROM equipment WHERE id = ?').get(id);
    if (!equipment) {
      return res.status(404).json({ error: 'Ekipman bulunamadı.' });
    }

    const existing = db.prepare('SELECT * FROM equipment_risk_scores WHERE equipment_id = ?').get(id);
    if (existing) {
      return res.json(existing);
    }

    const computed = await computeAndSaveRisk(equipment);
    res.json(computed);
  } catch (err) {
    console.error(err);
    res.status(503).json({
      error: 'Risk skoru hesaplanamadı (ML servisine ulaşılamıyor olabilir).',
    });
  }
}));

// GET /api/dashboard/risky-equipment?limit=5&il=Erzurum
// Risk skoruna göre azalan sırayla en riskli ekipmanları döner. Bu bir
// yönetim raporu olduğu için yalnızca yönetici erişebilir.
// `il` opsiyoneldir — verilmezse eski davranış (tüm iller) birebir korunur;
// verilirse yalnızca o ildeki ekipmanlarla sınırlanır (materials.js'teki
// `category`/workOrders.js'teki `status` opsiyonel filtreleriyle AYNI desen).
router.get('/dashboard/risky-equipment', requireRole('yonetici'), (req, res) => {
  try {
    const { il } = req.query;
    const limit = Math.min(Math.max(Number(req.query.limit) || 5, 1), 10);

    const whereClause = il ? 'WHERE e.il = ?' : '';
    const params = il ? [il, limit] : [limit];

    const rows = db
      .prepare(
        `SELECT e.id, e.qr_code, e.equipment_type, e.location_name, e.il, e.status,
                r.risk_score, r.risk_level, r.computed_at
         FROM equipment_risk_scores r
         JOIN equipment e ON e.id = r.equipment_id
         ${whereClause}
         ORDER BY r.risk_score DESC
         LIMIT ?`
      )
      .all(...params);
    res.json(rows);
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'Riskli ekipman listesi alınırken bir hata oluştu.' });
  }
});

// GET /api/ml/risk-model-performance — yalnızca yönetici.
//
// TEST-19: Gerçek Geri Bildirim Döngüsü'nün "dürüst metrik" ayağı. Modelin
// arassaha-ml/models/model_metadata.json'daki test_accuracy/test_f1 gibi
// sayıları SENTETİK test setinde ölçülmüştür (bkz. o dosyanın DÜRÜSTLÜK
// NOTU) — bu endpoint bunun yerine risk_prediction_outcomes'ta GERÇEKTEN
// biriken tahmin/sonuç çiftlerinden hesaplanan, iyimser OLMAYAN bir özet
// döner. Bucket'lar predicted_risk_score'tan türetilir (arassaha-ml/app.py
// risk_level_for ile AYNI eşikler: <=33 dusuk, 34-66 orta, >66 yuksek) —
// "belirsiz" (düşük model güveni) düzeyi, yalnızca skordan geri
// hesaplanamadığı için (bkz. app.py'deki confidence tabanlı ayrı mantık) bu
// özete dahil DEĞİLDİR; bu bilinen/kabul edilmiş bir basitleştirmedir.
const MIN_RESOLVED_FOR_RELIABLE_SUMMARY = 20;

function riskBucketForScore(score) {
  if (score <= 33) return 'dusuk';
  if (score <= 66) return 'orta';
  return 'yuksek';
}

router.get('/ml/risk-model-performance', requireRole('yonetici'), (req, res) => {
  try {
    const totalPredictions = db.prepare('SELECT COUNT(*) AS c FROM risk_prediction_outcomes').get().c;
    const resolvedRows = db
      .prepare(
        `SELECT predicted_risk_score, actual_fault_occurred
         FROM risk_prediction_outcomes
         WHERE actual_fault_occurred IS NOT NULL`
      )
      .all();

    const buckets = {
      dusuk: { total: 0, faulted: 0, not_faulted: 0 },
      orta: { total: 0, faulted: 0, not_faulted: 0 },
      yuksek: { total: 0, faulted: 0, not_faulted: 0 },
    };
    for (const row of resolvedRows) {
      const bucket = buckets[riskBucketForScore(row.predicted_risk_score)];
      bucket.total += 1;
      if (row.actual_fault_occurred === 1) bucket.faulted += 1;
      else bucket.not_faulted += 1;
    }

    const rate = (numerator, denominator) => (denominator > 0 ? Math.round((numerator / denominator) * 1000) / 10 : null);

    const resolvedCount = resolvedRows.length;
    const hasEnoughData = resolvedCount >= MIN_RESOLVED_FOR_RELIABLE_SUMMARY;

    res.json({
      total_predictions: totalPredictions,
      resolved_predictions: resolvedCount,
      pending_predictions: totalPredictions - resolvedCount,
      has_enough_data: hasEnoughData,
      min_required_for_reliable_summary: MIN_RESOLVED_FOR_RELIABLE_SUMMARY,
      // "Yüksek risk dediğimiz ekipmanların %X'i GERÇEKTEN arızalandı"
      high_risk: {
        total: buckets.yuksek.total,
        faulted: buckets.yuksek.faulted,
        fault_rate_percent: rate(buckets.yuksek.faulted, buckets.yuksek.total),
      },
      medium_risk: {
        total: buckets.orta.total,
        faulted: buckets.orta.faulted,
        fault_rate_percent: rate(buckets.orta.faulted, buckets.orta.total),
      },
      // "Düşük risk dediğimiz ekipmanların %Y'si arızalanmadı"
      low_risk: {
        total: buckets.dusuk.total,
        not_faulted: buckets.dusuk.not_faulted,
        no_fault_rate_percent: rate(buckets.dusuk.not_faulted, buckets.dusuk.total),
      },
    });
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'Model performans özeti alınırken bir hata oluştu.' });
  }
});

// GET /api/ml/damage-model-performance — yalnızca yönetici.
//
// TEST-20: Görüntü Tabanlı Hasar Tespiti (Modül 15) için GET
// /api/ml/risk-model-performance (yukarısı) ile AYNI ilke — burada BU
// dosyanın konusu (Modül 9, risk) DEĞİL, ama Modül 9/11'in "gerçek dünya
// performansı" meta-endpoint'leri zaten bu router'da toplandığı için (bkz.
// yukarıdaki risk-model-performance) aynı yerde tutuldu. Modelin cv_is_damaged
// tahmini ile insanın human_verified_damage doğrulamasının (bkz. routes/isg.js
// PATCH /:id/verify-damage) ne sıklıkla UYUŞTUĞUNU hesaplar — "model saha
// fotoğraflarında %X oranında doğru tahmin yaptı" gibi dürüst bir özet,
// arassaha-ml/models/damage_model_metadata.json'daki Kaggle test seti
// metriklerinden BAĞIMSIZ. Yalnızca hem model tahmini (cv_is_damaged IS NOT
// NULL — model belirsiz kalmadıysa) hem de insan doğrulaması
// (human_verified_damage IS NOT NULL) olan kayıtlar sayılır.
const MIN_VERIFIED_FOR_RELIABLE_SUMMARY = 20;

router.get('/ml/damage-model-performance', requireRole('yonetici'), (req, res) => {
  try {
    const rows = db
      .prepare(
        `SELECT cv_is_damaged, human_verified_damage FROM isg_reports
         WHERE cv_is_damaged IS NOT NULL AND human_verified_damage IS NOT NULL`
      )
      .all();

    const totalVerified = db
      .prepare('SELECT COUNT(*) AS c FROM isg_reports WHERE human_verified_damage IS NOT NULL')
      .get().c;
    const agreementCount = rows.filter((r) => r.cv_is_damaged === r.human_verified_damage).length;
    const comparableCount = rows.length;
    const hasEnoughData = comparableCount >= MIN_VERIFIED_FOR_RELIABLE_SUMMARY;

    res.json({
      total_verified: totalVerified,
      comparable_predictions: comparableCount,
      agreement_count: agreementCount,
      agreement_rate_percent:
        comparableCount > 0 ? Math.round((agreementCount / comparableCount) * 1000) / 10 : null,
      has_enough_data: hasEnoughData,
      min_required_for_reliable_summary: MIN_VERIFIED_FOR_RELIABLE_SUMMARY,
    });
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'Model performans özeti alınırken bir hata oluştu.' });
  }
});

module.exports = router;
module.exports.refreshAllRiskScores = refreshAllRiskScores;
module.exports.recordFaultOutcomeIfPredicted = recordFaultOutcomeIfPredicted;
// Modül 12 (Kestirimci Bakım Planlama) öneri gerekçesi metninde ("son
// bakımdan bu yana X ay geçmiş") AYNI hesaplamayı tekrar yazmak yerine
// burada zaten var olanı yeniden kullanır — bkz. routes/maintenance.js.
module.exports.calculateMonthsSinceMaintenance = calculateMonthsSinceMaintenance;
