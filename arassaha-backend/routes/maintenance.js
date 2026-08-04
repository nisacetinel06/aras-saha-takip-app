// Kestirimci Bakım Planlama (Modül 12).
//
// ÖNEMLİ AYRIM (sunumda vurgulanmalı): Bu dosya bir Makine Öğrenmesi modeli
// İÇERMEZ, yeni bir model de EĞİTMEZ. Modül 9'un (routes/risk.js) ürettiği ve
// equipment_risk_scores tablosuna yazdığı risk_score, burada SABİT eşiklerle
// (67 ve 34) bir bakım önerisine çevrilir — yani bu, ML çıktısını tüketen bir
// İŞ KURALI / OTOMASYON katmanıdır. "ML" olan tek yer Modül 9'daki Python
// servisidir; bu router yalnızca o servisin sonucunu okur.
//
// Akış: risk_score (Modül 9) → urgency_level + recommended_date (bu dosya,
// kural tabanlı) → dispeçer/yönetici onayı → gerçek work_orders kaydı
// (source_type='onleyici_bakim' ile Modül 1/7 sistemine işlenir).
const express = require('express');
const db = require('../database');
const { requireRole } = require('../middleware/auth');
const { createNotification } = require('../utils/notify');
const { calculateMonthsSinceMaintenance } = require('./risk');

const router = express.Router();

const VALID_STATUSES = ['onerildi', 'planlandi', 'tamamlandi', 'reddedildi'];
const VALID_URGENCY_LEVELS = ['yuksek', 'orta', 'dusuk'];
const VALID_PRIORITIES = ['acil', 'normal', 'dusuk'];

// Kural tablosu (İş Mantığı — ML DEĞİL): risk_score bu eşiklerden hangisine
// düşüyorsa o satırın aciliyeti/önerilen tarihi kullanılır. Modül 9'daki
// arassaha-ml/app.py:risk_level_for ile AYNI eşikler (<=33 dusuk, <=66 orta,
// >66 yuksek) kasıtlı olarak birebir korunmuştur — iki modül farklı sınırlar
// kullanırsa aynı ekipman için "risk YÜKSEK ama bakım önerisi ORTA aciliyette"
// gibi kafa karıştırıcı bir tutarsızlık ortaya çıkardı.
const URGENCY_RULES = [
  { minScore: 67, level: 'yuksek', daysAhead: 7 },
  { minScore: 34, level: 'orta', daysAhead: 30 },
];

// score < 34 (düşük risk) için kasıtlı olarak hiçbir kural eşleşmez — bu
// ekipmanlar için öneri ÜRETİLMEZ (bkz. deriveUrgencyRule kullanım yerleri).
function deriveUrgencyRule(riskScore) {
  return URGENCY_RULES.find((rule) => riskScore >= rule.minScore) || null;
}

function addDaysIso(days) {
  const date = new Date(Date.now() + days * 24 * 60 * 60 * 1000);
  return date.toISOString().slice(0, 10);
}

// Modül 9'un zaten hesapladığı özelliği (months_since_maintenance) tekrar
// hesaplamak yerine risk.js'ten yeniden kullanır — bkz. routes/risk.js
// module.exports.calculateMonthsSinceMaintenance.
function buildReason(equipment, riskScore) {
  const months = Math.round(calculateMonthsSinceMaintenance(equipment.last_maintenance_date, equipment.install_date));
  return `Risk skoru ${riskScore}, son bakımdan bu yana ${months} ay geçmiş`;
}

const SELECT_RECOMMENDATION_WITH_EQUIPMENT = `
  SELECT
    mr.*,
    e.qr_code AS equipment_qr_code,
    e.equipment_type AS equipment_type,
    e.location_name AS equipment_location_name,
    e.il AS equipment_il,
    e.ilce AS equipment_ilce,
    e.mahalle AS equipment_mahalle,
    e.lat AS equipment_lat,
    e.lng AS equipment_lng,
    e.status AS equipment_status
  FROM maintenance_recommendations mr
  JOIN equipment e ON e.id = mr.equipment_id
`;

function mapRecommendationRow(row) {
  const {
    equipment_qr_code,
    equipment_type,
    equipment_location_name,
    equipment_il,
    equipment_ilce,
    equipment_mahalle,
    equipment_lat,
    equipment_lng,
    equipment_status,
    ...recommendation
  } = row;
  return {
    ...recommendation,
    equipment: {
      id: recommendation.equipment_id,
      qr_code: equipment_qr_code,
      equipment_type,
      location_name: equipment_location_name,
      il: equipment_il,
      ilce: equipment_ilce,
      mahalle: equipment_mahalle,
      lat: equipment_lat,
      lng: equipment_lng,
      status: equipment_status,
    },
  };
}

// POST /api/maintenance/refresh-recommendations — yalnızca yönetici.
// Modül 9'un güncel risk skorlarını okuyup kural tabanlı önerileri
// yeniden hesaplar/oluşturur. ÇOĞALTMA KORUMASI (kritik davranış, canlıda en
// çok karşılaşılabilecek hata türü): aynı ekipman için zaten bekleyen
// ('onerildi') bir öneri varsa YENİ satır AÇILMAZ, yalnızca risk_score_at_creation
// ve reason güncellenir. urgency_level/recommended_date BİLEREK dokunulmaz —
// bunlar önerinin İLK oluşturulduğu andaki "taahhüt edilmiş" plandır; dispeçer
// zaten bu öneriyi incelemekteyken aciliyet/tarihin her refresh'te sessizce
// kayması kafa karıştırıcı olurdu. status='planlandi'/'tamamlandi' olan
// önerilere ise HİÇ dokunulmaz (zaten bir iş emrine dönüşmüş ya da bitmiş).
router.post('/refresh-recommendations', requireRole('yonetici'), (req, res) => {
  try {
    const riskRows = db
      .prepare(
        `SELECT e.*, r.risk_score AS risk_score
         FROM equipment_risk_scores r
         JOIN equipment e ON e.id = r.equipment_id`
      )
      .all();

    let created = 0;
    let updated = 0;
    let skipped = 0;

    for (const equipment of riskRows) {
      const rule = deriveUrgencyRule(equipment.risk_score);
      if (!rule) {
        skipped++; // düşük risk — öneri üretilmez
        continue;
      }

      const reason = buildReason(equipment, equipment.risk_score);
      const existing = db
        .prepare('SELECT * FROM maintenance_recommendations WHERE equipment_id = ? ORDER BY created_at DESC LIMIT 1')
        .get(equipment.id);

      if (existing && existing.status === 'onerildi') {
        db.prepare('UPDATE maintenance_recommendations SET risk_score_at_creation = ?, reason = ? WHERE id = ?').run(
          equipment.risk_score,
          reason,
          existing.id
        );
        updated++;
        continue;
      }

      if (existing && (existing.status === 'planlandi' || existing.status === 'tamamlandi')) {
        skipped++;
        continue;
      }

      // existing yok, ya da tek geçmişi 'reddedildi' — risk hâlâ eşik
      // üzerindeyse yeni bir öneri açılır (bir yönetimsel ret, riski sonsuza
      // dek görünmez kılmaz).
      db.prepare(
        `INSERT INTO maintenance_recommendations
           (equipment_id, risk_score_at_creation, urgency_level, recommended_date, reason, status, created_at)
         VALUES (@equipment_id, @risk_score_at_creation, @urgency_level, @recommended_date, @reason, 'onerildi', @created_at)`
      ).run({
        equipment_id: equipment.id,
        risk_score_at_creation: equipment.risk_score,
        urgency_level: rule.level,
        recommended_date: addDaysIso(rule.daysAhead),
        reason,
        created_at: new Date().toISOString(),
      });
      created++;
    }

    res.json({ created, updated, skipped });
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'Bakım önerileri yeniden hesaplanırken bir hata oluştu.' });
  }
});

// GET /api/maintenance/recommendations?status=&urgency= — giriş yapmış herkes.
router.get('/recommendations', (req, res) => {
  try {
    const { status, urgency } = req.query;

    if (status && !VALID_STATUSES.includes(status)) {
      return res.status(400).json({ error: `Geçersiz status değeri. Geçerli değerler: ${VALID_STATUSES.join(', ')}` });
    }
    if (urgency && !VALID_URGENCY_LEVELS.includes(urgency)) {
      return res
        .status(400)
        .json({ error: `Geçersiz urgency değeri. Geçerli değerler: ${VALID_URGENCY_LEVELS.join(', ')}` });
    }

    const conditions = [];
    const params = [];
    if (status) {
      conditions.push('mr.status = ?');
      params.push(status);
    }
    if (urgency) {
      conditions.push('mr.urgency_level = ?');
      params.push(urgency);
    }
    const whereClause = conditions.length ? `WHERE ${conditions.join(' AND ')}` : '';

    const rows = db
      .prepare(
        `${SELECT_RECOMMENDATION_WITH_EQUIPMENT}
         ${whereClause}
         ORDER BY CASE mr.urgency_level WHEN 'yuksek' THEN 0 WHEN 'orta' THEN 1 ELSE 2 END, mr.recommended_date ASC`
      )
      .all(...params);

    res.json(rows.map(mapRecommendationRow));
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'Bakım önerileri listelenirken bir hata oluştu.' });
  }
});

// GET /api/maintenance/recommendations/:id — giriş yapmış herkes.
router.get('/recommendations/:id', (req, res) => {
  try {
    const id = Number(req.params.id);
    if (!Number.isInteger(id)) {
      return res.status(400).json({ error: 'Geçersiz öneri id değeri.' });
    }

    const row = db.prepare(`${SELECT_RECOMMENDATION_WITH_EQUIPMENT} WHERE mr.id = ?`).get(id);
    if (!row) {
      return res.status(404).json({ error: 'Bakım önerisi bulunamadı.' });
    }

    res.json(mapRecommendationRow(row));
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'Bakım önerisi alınırken bir hata oluştu.' });
  }
});

// POST /api/maintenance/recommendations/:id/create-work-order — dispeçer/yönetici.
// Body: { assigned_user_id?, priority? }
// Öneriyi gerçek bir iş emrine dönüştürür. Konum (il/ilce/mahalle/location_name/
// lat/lng) HER ZAMAN ekipman kaydından türetilir — work_orders.js POST /
// endpoint'indeki "konum tek kaynaktan gelir" ilkesiyle birebir aynı yaklaşım.
router.post('/recommendations/:id/create-work-order', requireRole('dispecer', 'yonetici'), (req, res) => {
  try {
    const id = Number(req.params.id);
    if (!Number.isInteger(id)) {
      return res.status(400).json({ error: 'Geçersiz öneri id değeri.' });
    }

    const recommendation = db.prepare('SELECT * FROM maintenance_recommendations WHERE id = ?').get(id);
    if (!recommendation) {
      return res.status(404).json({ error: 'Bakım önerisi bulunamadı.' });
    }
    if (recommendation.status !== 'onerildi') {
      return res.status(400).json({
        error: 'Bu öneri zaten bir iş emrine dönüştürülmüş, tamamlanmış ya da reddedilmiş; tekrar işlenemez.',
      });
    }

    const equipment = db.prepare('SELECT * FROM equipment WHERE id = ?').get(recommendation.equipment_id);
    if (!equipment) {
      return res.status(404).json({ error: 'Önerinin bağlı olduğu ekipman bulunamadı.' });
    }

    let assignedUserId = null;
    if (req.body.assigned_user_id !== undefined && req.body.assigned_user_id !== null) {
      assignedUserId = Number(req.body.assigned_user_id);
      if (!Number.isInteger(assignedUserId)) {
        return res.status(400).json({ error: 'Geçersiz assigned_user_id değeri.' });
      }
      const assignedUser = db
        .prepare('SELECT id, role, supervisor_id, is_active FROM users WHERE id = ?')
        .get(assignedUserId);
      if (!assignedUser || assignedUser.role !== 'teknisyen') {
        return res.status(400).json({ error: 'assigned_user_id geçerli bir teknisyene ait olmalı.' });
      }
      if (!assignedUser.is_active) {
        return res.status(400).json({ error: 'assigned_user_id pasif bir teknisyene ait olamaz.' });
      }
      if (req.user.role === 'dispecer' && assignedUser.supervisor_id !== req.user.id) {
        return res.status(403).json({ error: 'assigned_user_id sizin ekibinizdeki bir teknisyene ait olmalı.' });
      }
    }

    let priority = req.body.priority;
    if (priority !== undefined && priority !== null) {
      if (!VALID_PRIORITIES.includes(priority)) {
        return res
          .status(400)
          .json({ error: `Geçersiz priority değeri. Geçerli değerler: ${VALID_PRIORITIES.join(', ')}` });
      }
    } else {
      // urgency_level'dan türet: yuksek -> acil, orta -> normal.
      priority = recommendation.urgency_level === 'yuksek' ? 'acil' : 'normal';
    }

    const title = `Önleyici Bakım - ${equipment.qr_code}`;
    const description = `Kestirimci bakım planlaması önerisi: ${recommendation.reason}`;
    const now = new Date().toISOString();

    const info = db
      .prepare(
        `INSERT INTO work_orders
           (title, description, status, priority, il, ilce, mahalle, location_name, lat, lng,
            assigned_user_id, equipment_id, source_type, source_recommendation_id, created_at, updated_at)
         VALUES
           (@title, @description, 'acik', @priority, @il, @ilce, @mahalle, @location_name, @lat, @lng,
            @assigned_user_id, @equipment_id, 'onleyici_bakim', @source_recommendation_id, @created_at, @updated_at)`
      )
      .run({
        title,
        description,
        priority,
        // Konum, İSTEMCİDEN DEĞİL doğrudan equipment kaydından (bkz. workOrders.js POST /).
        il: equipment.il,
        ilce: equipment.ilce,
        mahalle: equipment.mahalle,
        location_name: equipment.location_name,
        lat: equipment.lat,
        lng: equipment.lng,
        assigned_user_id: assignedUserId,
        equipment_id: equipment.id,
        source_recommendation_id: recommendation.id,
        created_at: now,
        updated_at: now,
      });

    const workOrderId = info.lastInsertRowid;

    db.prepare("UPDATE maintenance_recommendations SET related_work_order_id = ?, status = 'planlandi' WHERE id = ?").run(
      workOrderId,
      recommendation.id
    );

    // Bildirim Sistemi (Modül 6) — atanan teknisyene, arıza iş emri
    // atamasıyla AYNI createNotification fonksiyonu üzerinden bildir.
    if (assignedUserId) {
      createNotification(assignedUserId, `Size yeni bir önleyici bakım iş emri atandı: "${title}"`, 'work_order', workOrderId);
    }

    const createdWorkOrder = db
      .prepare(
        `SELECT wo.*, u.id AS assigned_user_id_join, u.name AS assigned_user_name, u.role AS assigned_user_role
         FROM work_orders wo
         LEFT JOIN users u ON u.id = wo.assigned_user_id
         WHERE wo.id = ?`
      )
      .get(workOrderId);

    const { assigned_user_id_join, assigned_user_name, assigned_user_role, ...workOrder } = createdWorkOrder;

    res.status(201).json({
      work_order: {
        ...workOrder,
        assigned_user: assigned_user_id_join
          ? { id: assigned_user_id_join, name: assigned_user_name, role: assigned_user_role }
          : null,
      },
      recommendation_id: recommendation.id,
    });
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'Önleyici iş emri oluşturulurken bir hata oluştu.' });
  }
});

// PATCH /api/maintenance/recommendations/:id/dismiss — dispeçer/yönetici.
// Yalnızca 'onerildi' durumundaki bir öneri reddedilebilir (zaten iş emrine
// dönüşmüş/tamamlanmış bir öneri geriye alınamaz).
router.patch('/recommendations/:id/dismiss', requireRole('dispecer', 'yonetici'), (req, res) => {
  try {
    const id = Number(req.params.id);
    if (!Number.isInteger(id)) {
      return res.status(400).json({ error: 'Geçersiz öneri id değeri.' });
    }

    const existing = db.prepare('SELECT * FROM maintenance_recommendations WHERE id = ?').get(id);
    if (!existing) {
      return res.status(404).json({ error: 'Bakım önerisi bulunamadı.' });
    }
    if (existing.status !== 'onerildi') {
      return res.status(400).json({ error: 'Yalnızca bekleyen (onerildi) öneriler reddedilebilir.' });
    }

    db.prepare("UPDATE maintenance_recommendations SET status = 'reddedildi' WHERE id = ?").run(id);

    const updated = db.prepare(`${SELECT_RECOMMENDATION_WITH_EQUIPMENT} WHERE mr.id = ?`).get(id);
    res.json(mapRecommendationRow(updated));
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'Bakım önerisi reddedilirken bir hata oluştu.' });
  }
});

module.exports = router;
