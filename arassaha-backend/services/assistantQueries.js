// AI Asistan / Sohbet Arayüzü (Modül 16) — güvenli, önceden yazılmış,
// PARAMETRELİ sorgu fonksiyonları.
//
// Bu dosya, assistantService.parseUserIntent'in ürettiği (ve zaten
// assistantIntents.js şemasına göre doğrulanmış) { intent, filters }
// nesnesini alıp GERÇEK veritabanı sonucunu döner. LLM'in kendisi asla bir
// SQL string'i üretmez/görmez — yalnızca burada tanımlı sabit sorgular
// çalışır (bkz. assistantIntents.js başındaki "KRİTİK MİMARİ KARAR" notu).
//
// RBAC (Kritik): Her fonksiyon `user` (req.user: {id, role}) parametresini
// alır ve Modül 7'deki AYNI görünürlük kurallarını uygular — dashboard.js
// (visibilityClause) ve routes/risk.js / routes/materials.js / routes/isg.js
// gibi ilgili endpoint'lerdeki kısıtlamalarla BİREBİR aynı mantık burada da
// tekrarlanır. Asistanın, bu kuralları atlayan bir "arka kapı" olmaması
// hayati önemde — örn. bir teknisyen "kaç açık arıza var?" diye sorduğunda
// yalnızca KENDİSİNE atanan işler sayılır, dispeçer/yöneticinin gördüğü tüm
// veri değil.
const db = require('../database');

class AssistantForbiddenError extends Error {}

// dashboard.js'teki visibilityClause ile AYNI mantık (bkz. o dosyadaki not) —
// work_orders alias'ı burada 'wo' olduğu için yalnızca kolon öneki farklı.
function workOrderVisibility(user) {
  if (user.role === 'teknisyen') {
    return { clause: 'wo.assigned_user_id = ?', params: [user.id] };
  }
  if (user.role === 'dispecer') {
    return {
      clause: 'wo.assigned_user_id IN (SELECT id FROM users WHERE supervisor_id = ?)',
      params: [user.id],
    };
  }
  return { clause: null, params: [] };
}

// GET /api/workorders ve dashboard.js ile AYNI filtre isimlerini kabul eder,
// ayrıca (mevcut endpoint'lerde olmayan) il/ilce/equipment_type/tarih aralığı
// filtrelerini de destekler — bu yüzden var olan route handler'ı (Express
// req/res'e bağlı bir closure, saf bir fonksiyon değil) ÇAĞIRMAK yerine aynı
// SELECT/visibility desenini burada yeniden kurar.
function countWorkOrders(user, filters) {
  const conditions = [];
  const params = [];

  if (filters.il) {
    conditions.push('wo.il = ?');
    params.push(filters.il);
  }
  if (filters.ilce) {
    conditions.push('wo.ilce = ?');
    params.push(filters.ilce);
  }
  if (filters.status) {
    conditions.push('wo.status = ?');
    params.push(filters.status);
  }
  if (filters.priority) {
    conditions.push('wo.priority = ?');
    params.push(filters.priority);
  }
  if (filters.equipment_type) {
    conditions.push('e.equipment_type = ?');
    params.push(filters.equipment_type);
  }
  if (filters.date_from) {
    conditions.push('wo.created_at >= ?');
    params.push(filters.date_from);
  }
  if (filters.date_to) {
    conditions.push('wo.created_at <= ?');
    params.push(`${filters.date_to}T23:59:59.999Z`);
  }

  const visibility = workOrderVisibility(user);
  if (visibility.clause) {
    conditions.push(visibility.clause);
    params.push(...visibility.params);
  }

  const whereClause = conditions.length ? `WHERE ${conditions.join(' AND ')}` : '';
  const row = db
    .prepare(
      `SELECT COUNT(*) AS count
       FROM work_orders wo
       LEFT JOIN equipment e ON e.id = wo.equipment_id
       ${whereClause}`
    )
    .get(...params);

  return { count: row.count };
}

// countWorkOrders ile AYNI filtre/RBAC deseni, ama SADECE sayı değil gerçek
// kayıtları (başlık, açıklama, konum, öncelik) döner — "acil iş emirlerini
// içerikleriyle listele" gibi sorular count_work_orders ile cevaplanamaz.
function listWorkOrders(user, filters) {
  const conditions = [];
  const params = [];

  if (filters.il) {
    conditions.push('wo.il = ?');
    params.push(filters.il);
  }
  if (filters.ilce) {
    conditions.push('wo.ilce = ?');
    params.push(filters.ilce);
  }
  if (filters.status) {
    conditions.push('wo.status = ?');
    params.push(filters.status);
  }
  if (filters.priority) {
    conditions.push('wo.priority = ?');
    params.push(filters.priority);
  }
  if (filters.equipment_type) {
    conditions.push('e.equipment_type = ?');
    params.push(filters.equipment_type);
  }

  const visibility = workOrderVisibility(user);
  if (visibility.clause) {
    conditions.push(visibility.clause);
    params.push(...visibility.params);
  }

  const whereClause = conditions.length ? `WHERE ${conditions.join(' AND ')}` : '';
  const limit = filters.limit ?? 8;

  const rows = db
    .prepare(
      `SELECT wo.id, wo.title, wo.description, wo.status, wo.priority, wo.il, wo.ilce,
              wo.location_name, wo.created_at, e.equipment_type
       FROM work_orders wo
       LEFT JOIN equipment e ON e.id = wo.equipment_id
       ${whereClause}
       ORDER BY wo.created_at DESC
       LIMIT ?`
    )
    .all(...params, limit);

  return { items: rows };
}

// routes/risk.js GET /dashboard/risky-equipment ile AYNI kısıtlama: yalnızca
// yönetici. Asistan bu "arka kapı" olamaz — teknisyen/dispeçer sorarsa
// AssistantForbiddenError fırlatılır, routes/assistant.js bunu YAKALAR ve
// LLM'e formatAnswer için tekrar sormadan (gereksiz maliyet) sabit bir
// "yetkiniz yok" yanıtı döner.
function listHighRiskEquipment(user, filters) {
  if (user.role !== 'yonetici') {
    throw new AssistantForbiddenError('En riskli ekipmanlar listesi yalnızca yöneticiye açıktır.');
  }

  const conditions = [];
  const params = [];
  if (filters.il) {
    conditions.push('e.il = ?');
    params.push(filters.il);
  }
  const whereClause = conditions.length ? `WHERE ${conditions.join(' AND ')}` : '';
  const limit = filters.limit ?? 5;

  const rows = db
    .prepare(
      `SELECT e.id, e.qr_code, e.equipment_type, e.il, e.location_name, r.risk_score, r.risk_level
       FROM equipment_risk_scores r
       JOIN equipment e ON e.id = r.equipment_id
       ${whereClause}
       ORDER BY r.risk_score DESC
       LIMIT ?`
    )
    .all(...params, limit);

  return { items: rows };
}

// routes/anomaly.js GET /meters/suspicious ile AYNI: giriş yapmış herkes
// erişebilir, rol bazlı bir kısıtlama yok.
function listSuspiciousMeters(user, filters) {
  const conditions = ['a.is_suspicious = 1'];
  const params = [];
  if (filters.il) {
    conditions.push('e.il = ?');
    params.push(filters.il);
  }
  const limit = filters.limit ?? 10;

  const rows = db
    .prepare(
      `SELECT e.id, e.qr_code, e.il, e.location_name, a.anomaly_score, a.detected_reason
       FROM meter_anomaly_scores a
       JOIN equipment e ON e.id = a.equipment_id
       WHERE ${conditions.join(' AND ')}
       ORDER BY a.anomaly_score DESC
       LIMIT ?`
    )
    .all(...params, limit);

  return { items: rows };
}

// routes/isg.js GET / ile AYNI: rol bazlı bir kısıtlama yok, tüm roller tüm
// bildirimleri görebilir (bkz. ARCHITECTURE.md Bölüm 8 — İSG Bildirim
// Listesi tüm rollere açık).
function countIsgReports(user, filters) {
  const conditions = [];
  const params = [];
  if (filters.status) {
    conditions.push('status = ?');
    params.push(filters.status);
  }
  if (filters.category) {
    conditions.push('category = ?');
    params.push(filters.category);
  }
  const whereClause = conditions.length ? `WHERE ${conditions.join(' AND ')}` : '';

  const row = db.prepare(`SELECT COUNT(*) AS count FROM isg_reports ${whereClause}`).get(...params);
  return { count: row.count };
}

// routes/materials.js GET /dashboard/low-stock-materials ile AYNI: giriş
// yapmış herkes erişebilir, ayrıca (mevcut endpoint'te olmayan) category
// filtresini destekler.
function listLowStockMaterials(user, filters) {
  const conditions = ['stock_quantity <= min_stock_threshold'];
  const params = [];
  if (filters.category) {
    conditions.push('category = ?');
    params.push(filters.category);
  }

  const rows = db
    .prepare(
      `SELECT id, name, category, unit, stock_quantity, min_stock_threshold
       FROM materials
       WHERE ${conditions.join(' AND ')}
       ORDER BY (stock_quantity - min_stock_threshold) ASC
       LIMIT 10`
    )
    .all(...params);

  return { items: rows };
}

// routes/equipment.js GET /qr/:qrCode ile AYNI: giriş yapmış herkes erişebilir.
function equipmentLookup(user, filters) {
  const row = db
    .prepare(
      `SELECT e.id, e.qr_code, e.equipment_type, e.il, e.location_name, e.status,
              r.risk_score, r.risk_level
       FROM equipment e
       LEFT JOIN equipment_risk_scores r ON r.equipment_id = e.id
       WHERE e.qr_code = ?`
    )
    .get(filters.qr_code);

  return { item: row ?? null };
}

const QUERY_FUNCTIONS = {
  count_work_orders: countWorkOrders,
  list_work_orders: listWorkOrders,
  list_high_risk_equipment: listHighRiskEquipment,
  list_suspicious_meters: listSuspiciousMeters,
  count_isg_reports: countIsgReports,
  list_low_stock_materials: listLowStockMaterials,
  equipment_lookup: equipmentLookup,
};

module.exports = { QUERY_FUNCTIONS, AssistantForbiddenError };
