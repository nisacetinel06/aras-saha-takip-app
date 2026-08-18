// Kayıp-Kaçak / Anormal Tüketim Tespiti (Modül 11).
//
// risk.js (Modül 9) ile AYNI mimari: sayaçların ham aylık tüketim verisini
// (meter_consumption) SQLite'tan okuyup özellik (feature) çıkarır, ayrı bir
// Python (FastAPI) ML servisine (varsayılan http://localhost:8000, bkz.
// arassaha-ml/) HTTP ile gönderir, dönen anomali skorunu
// meter_anomaly_scores tablosuna yazar/okur. İki katman birbirine yalnızca
// HTTP üzerinden bağlıdır.
//
// DÜRÜSTLÜK NOTU: Skorları üreten IsolationForest modeli, ArasSaha'nın
// henüz gerçek bir AMI/akıllı sayaç okuma sistemi olmadığı için SENTETİK
// (kural tabanlı üretilmiş) bir tüketim geçmişiyle eğitildi (bkz.
// arassaha-ml/generate_consumption_data.py, arassaha-ml/README.md). Model
// eğitimi/servis/entegrasyon süreci gerçektir; veri sentetiktir.
const express = require('express');
const db = require('../database');
const { requireRole } = require('../middleware/auth');
const { createNotification } = require('../utils/notify');
const { asyncHandler } = require('../utils/asyncHandler');

const router = express.Router();

const ML_SERVICE_URL = process.env.ML_SERVICE_URL || 'http://localhost:8000';

// arassaha-ml/consumption_feature_utils.py'deki ZERO_CONSUMPTION_THRESHOLD_KWH
// ile BİREBİR aynı olmalı — bu iki taraf ayrı dillerde (JS/Python) bağımsız
// olarak aynı formülü uygular (bkz. risk.js buildFeatures ile aynı desen).
const ZERO_CONSUMPTION_THRESHOLD_KWH = 5.0;

function round(value, decimals) {
  const factor = 10 ** decimals;
  return Math.round(value * factor) / factor;
}

// Bir sayacın kronolojik (en eskiden en yeniye) sıradaki aylık tüketim
// değerlerinden, arassaha-ml/consumption_feature_utils.py ile AYNI 7
// özelliği hesaplar.
function buildFeatures(monthlyValues) {
  const n = monthlyValues.length;
  const mean = monthlyValues.reduce((sum, v) => sum + v, 0) / n;
  const variance = monthlyValues.reduce((sum, v) => sum + (v - mean) ** 2, 0) / n;
  const std = Math.sqrt(variance);

  const last3 = monthlyValues.slice(-3);
  const first9 = monthlyValues.slice(0, n - 3);
  const last3Avg = last3.reduce((sum, v) => sum + v, 0) / last3.length;
  const first9Avg = first9.reduce((sum, v) => sum + v, 0) / first9.length;
  const dropRatio = first9Avg === 0 ? 0 : (first9Avg - last3Avg) / first9Avg;

  let maxChange = 0;
  for (let i = 1; i < n; i++) {
    maxChange = Math.max(maxChange, Math.abs(monthlyValues[i] - monthlyValues[i - 1]));
  }

  const zeroMonthsCount = monthlyValues.filter((v) => v < ZERO_CONSUMPTION_THRESHOLD_KWH).length;

  return {
    mean_consumption: round(mean, 2),
    std_consumption: round(std, 2),
    last_3_month_avg: round(last3Avg, 2),
    first_9_month_avg: round(first9Avg, 2),
    drop_ratio: round(dropRatio, 4),
    max_month_to_month_change: round(maxChange, 2),
    zero_months_count: zeroMonthsCount,
  };
}

function getMonthlyConsumption(equipmentId) {
  return db
    .prepare('SELECT year_month, consumption_kwh FROM meter_consumption WHERE equipment_id = ? ORDER BY year_month ASC')
    .all(equipmentId);
}

async function callMlService(features) {
  const response = await fetch(`${ML_SERVICE_URL}/detect-anomaly`, {
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

const upsertAnomalyScore = db.prepare(`
  INSERT INTO meter_anomaly_scores (equipment_id, anomaly_score, is_suspicious, detected_reason, computed_at)
  VALUES (@equipment_id, @anomaly_score, @is_suspicious, @detected_reason, @computed_at)
  ON CONFLICT(equipment_id) DO UPDATE SET
    anomaly_score = excluded.anomaly_score,
    is_suspicious = excluded.is_suspicious,
    detected_reason = excluded.detected_reason,
    computed_at = excluded.computed_at
`);

// Bildirim Sistemi (Modül 6) — equipment_risk_scores'daki
// notifyManagersIfRiskBecameHigh (bkz. routes/risk.js) ile AYNI desen: bir
// sayaç İLK KEZ şüpheli (is_suspicious=1) duruma geçtiğinde tüm yöneticilere
// bildirim gönderir. "İlk kez" şartı kasıtlıdır — aksi halde her yeniden
// hesaplamada (örn. günlük otomatik refresh) aynı sayaç için tekrar tekrar
// bildirim gider ve bildirim listesi anlamsızca şişer.
function notifyManagersIfBecameSuspicious(equipment, wasSuspicious, isSuspicious, detectedReason) {
  if (wasSuspicious || !isSuspicious) return;

  const managers = db.prepare("SELECT id FROM users WHERE role = 'yonetici' AND is_active = 1").all();
  for (const manager of managers) {
    createNotification(
      manager.id,
      `${equipment.qr_code} için şüpheli tüketim tespit edildi: ${detectedReason}`,
      'equipment',
      equipment.id
    );
  }
}

async function computeAndSaveAnomaly(equipment) {
  const monthly = getMonthlyConsumption(equipment.id);
  if (monthly.length < 12) {
    throw new Error(
      `Sayaç için yeterli tüketim geçmişi yok (${monthly.length}/12 ay). Önce arassaha-ml/generate_consumption_data.py çalıştırılmalı.`
    );
  }

  const features = buildFeatures(monthly.map((row) => row.consumption_kwh));
  const prediction = await callMlService(features);
  const computed_at = new Date().toISOString();

  const previous = db.prepare('SELECT is_suspicious FROM meter_anomaly_scores WHERE equipment_id = ?').get(equipment.id);

  upsertAnomalyScore.run({
    equipment_id: equipment.id,
    anomaly_score: prediction.anomaly_score,
    is_suspicious: prediction.is_suspicious ? 1 : 0,
    detected_reason: prediction.detected_reason ?? null,
    computed_at,
  });

  notifyManagersIfBecameSuspicious(
    equipment,
    previous?.is_suspicious === 1,
    prediction.is_suspicious,
    prediction.detected_reason
  );

  return {
    equipment_id: equipment.id,
    anomaly_score: prediction.anomaly_score,
    is_suspicious: prediction.is_suspicious,
    detected_reason: prediction.detected_reason ?? null,
    computed_at,
  };
}

// Tüm sayaçlar için anomali skorunu yeniden hesaplar. risk.js'teki
// refreshAllRiskScores ile AYNI desen: tek tek her sayacın hatası kendi
// try/catch'i içinde yutulur — ML servisi tamamen kapalıysa bile bu fonksiyon
// exception FIRLATMAZ, yalnızca `failed` sayısını raporlar.
async function refreshAllAnomalyScores() {
  const meters = db.prepare("SELECT * FROM equipment WHERE equipment_type = 'sayac'").all();
  const updated = [];
  const errors = [];

  for (const meter of meters) {
    try {
      updated.push(await computeAndSaveAnomaly(meter));
    } catch (err) {
      errors.push({ equipment_id: meter.id, error: err.message });
    }
  }

  return { updated: updated.length, failed: errors.length, errors };
}

// POST /api/ml/refresh-anomaly-scores
// Tüm sayaçların anomali skorunu yeniden hesaplatan bakım/yönetim aksiyonu —
// yalnızca yönetici tetikleyebilir.
router.post('/ml/refresh-anomaly-scores', requireRole('yonetici'), asyncHandler(async (req, res) => {
  const result = await refreshAllAnomalyScores();

  if (result.updated === 0 && result.failed > 0) {
    return res.status(200).json({
      ...result,
      message: 'ML servisine ulaşılamadı veya tüketim verisi eksik, anomali skorları güncellenemedi.',
    });
  }

  res.json(result);
}));

// GET /api/meters/suspicious
// is_suspicious=1 olan sayaçları, anomaly_score'a göre azalan sırada,
// ekipman bilgileriyle JOIN edip döner. Giriş yapmış herkes erişebilir
// (Modül 9'daki dashboard/risky-equipment'in aksine yalnızca yönetici DEĞİL
// — bkz. PROMPT #5 yetki tablosu).
router.get('/meters/suspicious', (req, res) => {
  try {
    const rows = db
      .prepare(
        `SELECT e.id, e.qr_code, e.equipment_type, e.location_name, e.status,
                a.anomaly_score, a.is_suspicious, a.detected_reason, a.computed_at
         FROM meter_anomaly_scores a
         JOIN equipment e ON e.id = a.equipment_id
         WHERE a.is_suspicious = 1
         ORDER BY a.anomaly_score DESC`
      )
      .all();
    res.json(rows);
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'Şüpheli sayaç listesi alınırken bir hata oluştu.' });
  }
});

// GET /api/equipment/:id/anomaly
// Önce meter_anomaly_scores tablosundan okur; hiç hesaplanmamışsa ML
// servisine anlık istek atıp sonucu hem kaydeder hem döner. Yalnızca
// equipment_type='sayac' olan ekipmanlar için anlamlıdır.
router.get('/equipment/:id/anomaly', asyncHandler(async (req, res) => {
  try {
    const id = Number(req.params.id);
    if (!Number.isInteger(id)) {
      return res.status(400).json({ error: 'Geçersiz ekipman id değeri.' });
    }

    const equipment = db.prepare('SELECT * FROM equipment WHERE id = ?').get(id);
    if (!equipment) {
      return res.status(404).json({ error: 'Ekipman bulunamadı.' });
    }
    if (equipment.equipment_type !== 'sayac') {
      return res.status(400).json({ error: 'Tüketim analizi yalnızca sayaç tipi ekipmanlar için yapılabilir.' });
    }

    const existing = db.prepare('SELECT * FROM meter_anomaly_scores WHERE equipment_id = ?').get(id);
    if (existing) {
      return res.json(existing);
    }

    const computed = await computeAndSaveAnomaly(equipment);
    res.json(computed);
  } catch (err) {
    console.error(err);
    res.status(503).json({
      error: 'Anomali skoru hesaplanamadı (ML servisine ulaşılamıyor ya da tüketim verisi eksik olabilir).',
    });
  }
}));

// GET /api/equipment/:id/consumption
// Ekipman Detayı ekranındaki tüketim grafiği (fl_chart) için son 12 aylık
// ham tüketim geçmişini döner. PROMPT'un Node endpoint tablosunda ayrıca
// listelenmedi, ama Modül 11'in 7b maddesindeki ("son 12 aylık tüketimi
// çizgi/çubuk grafikle göster") gereksinimi karşılamak için gerekli.
router.get('/equipment/:id/consumption', (req, res) => {
  try {
    const id = Number(req.params.id);
    if (!Number.isInteger(id)) {
      return res.status(400).json({ error: 'Geçersiz ekipman id değeri.' });
    }

    const equipment = db.prepare('SELECT id, equipment_type FROM equipment WHERE id = ?').get(id);
    if (!equipment) {
      return res.status(404).json({ error: 'Ekipman bulunamadı.' });
    }
    if (equipment.equipment_type !== 'sayac') {
      return res.status(400).json({ error: 'Tüketim geçmişi yalnızca sayaç tipi ekipmanlar için tutulur.' });
    }

    res.json(getMonthlyConsumption(id));
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'Tüketim geçmişi alınırken bir hata oluştu.' });
  }
});

module.exports = router;
module.exports.refreshAllAnomalyScores = refreshAllAnomalyScores;
