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

const router = express.Router();

// Python servisinin adresi — Railway gibi bir ortamda Node ve Python ayrı
// servisler olarak deploy edilirse bu, ortam değişkeniyle geçersiz kılınır.
const ML_SERVICE_URL = process.env.ML_SERVICE_URL || 'http://localhost:8000';

function calculateAgeYears(installDate) {
  if (!installDate) return 5; // kurulum tarihi bilinmiyorsa makul bir varsayılan
  const days = (Date.now() - new Date(installDate).getTime()) / (1000 * 60 * 60 * 24);
  return Math.max(0, days / 365.25);
}

function calculateMonthsSinceMaintenance(lastMaintenanceDate, installDate) {
  // Hiç bakım kaydı yoksa referans olarak kurulum tarihi kullanılır — o
  // tarihten bu yana da bakım görmemiş demektir.
  const reference = lastMaintenanceDate || installDate;
  if (!reference) return 12;
  const days = (Date.now() - new Date(reference).getTime()) / (1000 * 60 * 60 * 24);
  return Math.max(0, days / 30.44);
}

function countPastFaults(equipmentId) {
  const row = db.prepare('SELECT COUNT(*) AS c FROM work_orders WHERE equipment_id = ?').get(equipmentId);
  return row.c;
}

// avg_load_factor için gerçek telemetri/SCADA verisi yok (bu bir staj
// prototipi, bkz. ARCHITECTURE.md Bölüm 10); gerçekçi bir aralıkta (0.5-1.1)
// rastgele üretilir. Gerçek üretimde bu, sayaç/SCADA verisinden hesaplanmış
// gerçek bir ortalama yük faktörü olurdu.
function randomLoadFactor() {
  return Math.round((0.5 + Math.random() * 0.6) * 1000) / 1000;
}

function buildFeatures(equipment) {
  return {
    equipment_age_years: Math.round(calculateAgeYears(equipment.install_date) * 100) / 100,
    months_since_maintenance:
      Math.round(calculateMonthsSinceMaintenance(equipment.last_maintenance_date, equipment.install_date) * 10) / 10,
    past_fault_count: countPastFaults(equipment.id),
    equipment_type: equipment.equipment_type,
    avg_load_factor: randomLoadFactor(),
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

async function computeAndSaveRisk(equipment) {
  const features = buildFeatures(equipment);
  const prediction = await callMlService(features);
  const computed_at = new Date().toISOString();

  upsertRiskScore.run({
    equipment_id: equipment.id,
    risk_score: prediction.risk_score,
    risk_level: prediction.risk_level,
    computed_at,
  });

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
router.post('/ml/refresh-risk-scores', async (req, res) => {
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
});

// GET /api/equipment/:id/risk
// Önce equipment_risk_scores tablosundan okur; hiç hesaplanmamışsa ML
// servisine anlık istek atıp sonucu hem kaydeder hem döner.
router.get('/equipment/:id/risk', async (req, res) => {
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
});

// GET /api/dashboard/risky-equipment?limit=5
// Risk skoruna göre azalan sırayla en riskli ekipmanları döner.
router.get('/dashboard/risky-equipment', (req, res) => {
  try {
    const limit = Math.min(Math.max(Number(req.query.limit) || 5, 1), 10);
    const rows = db
      .prepare(
        `SELECT e.id, e.qr_code, e.equipment_type, e.location_name, e.status,
                r.risk_score, r.risk_level, r.computed_at
         FROM equipment_risk_scores r
         JOIN equipment e ON e.id = r.equipment_id
         ORDER BY r.risk_score DESC
         LIMIT ?`
      )
      .all(limit);
    res.json(rows);
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'Riskli ekipman listesi alınırken bir hata oluştu.' });
  }
});

module.exports = router;
module.exports.refreshAllRiskScores = refreshAllRiskScores;
