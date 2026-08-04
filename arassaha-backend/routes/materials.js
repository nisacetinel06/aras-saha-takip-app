// Malzeme / Yedek Parça Stok Takibi (Modül 13).
//
// Bu router, risk.js/anomaly.js/nlp.js ile AYNI sebeple '/api' kökünde mount
// edilir (bkz. server.js): tek bir ortak önek yerine üç farklı önekte
// ('materials/...', 'workorders/:workOrderId/materials...',
// 'dashboard/low-stock-materials') tam yol tanımlıyor.
//
// RBAC ÖZETİ (karıştırmamak için burada tek yerde):
//   - Görüntüleme (GET *)                         → giriş yapmış HERKES
//   - Malzeme kullanımı KAYDETME (POST .../materials) → giriş yapmış HERKES
//     (teknisyen DAHİL — sahada malzemeyi fiilen kullanan o kişidir)
//   - Kullanım kaydı SİLME (DELETE .../materials/:usageId) → dispeçer/yönetici
//   - Yeni malzeme TİPİ ekleme/güncelleme/restock → yalnızca yönetici
const express = require('express');
const db = require('../database');
const { requireRole } = require('../middleware/auth');
const { createNotification } = require('../utils/notify');

const router = express.Router();

const VALID_CATEGORIES = ['kablo', 'sigorta', 'izolator', 'konnektor', 'diger'];
const VALID_UNITS = ['adet', 'metre', 'kg'];
const VALID_EQUIPMENT_TYPES = ['trafo', 'direk', 'kesici', 'sayac'];

// Ekipman/Ekipman-Bakım modüllerindeki (Modül 4/12) arama sonucu sınırı ile
// AYNI değer — typeahead sonuçlarının performanslı kalması için.
const SEARCH_RESULT_LIMIT = 20;

function parseCompatibleTypes(csv) {
  if (!csv) return [];
  return csv.split(',').map((t) => t.trim()).filter(Boolean);
}

function validateCompatibleTypes(list) {
  return Array.isArray(list) && list.length > 0 && list.every((t) => VALID_EQUIPMENT_TYPES.includes(t));
}

function mapMaterialRow(row) {
  return {
    ...row,
    compatible_equipment_types: parseCompatibleTypes(row.compatible_equipment_types),
  };
}

function logStockMovement({ materialId, movementType, quantity, workOrderId, performedByUserId }) {
  db.prepare(
    `INSERT INTO material_stock_movements
       (material_id, movement_type, quantity, related_work_order_id, performed_by_user_id, created_at)
     VALUES (?, ?, ?, ?, ?, ?)`
  ).run(materialId, movementType, quantity, workOrderId ?? null, performedByUserId, new Date().toISOString());
}

// GET /api/materials?category=&low_stock=true&search=
router.get('/materials', (req, res) => {
  try {
    const { category, low_stock, search } = req.query;

    if (category && !VALID_CATEGORIES.includes(category)) {
      return res.status(400).json({ error: `Geçersiz category değeri. Geçerli değerler: ${VALID_CATEGORIES.join(', ')}` });
    }

    const conditions = [];
    const params = [];
    if (category) {
      conditions.push('category = ?');
      params.push(category);
    }
    if (low_stock === 'true' || low_stock === '1') {
      conditions.push('stock_quantity <= min_stock_threshold');
    }
    if (search && search.trim()) {
      conditions.push('name LIKE ?');
      params.push(`%${search.trim()}%`);
    }
    const whereClause = conditions.length ? `WHERE ${conditions.join(' AND ')}` : '';
    // search: typeahead senaryosu — Modül 4/12'deki desenle aynı, sonuç sayısı sınırlanır.
    const limitClause = search && search.trim() ? 'LIMIT ?' : '';
    if (limitClause) params.push(SEARCH_RESULT_LIMIT);

    const rows = db.prepare(`SELECT * FROM materials ${whereClause} ORDER BY name ${limitClause}`).all(...params);
    res.json(rows.map(mapMaterialRow));
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'Malzemeler listelenirken bir hata oluştu.' });
  }
});

// GET /api/materials/:id — detay + kullanım geçmişi (hangi iş emrinde, ne
// zaman, kim tarafından ne kadar kullanıldığı).
router.get('/materials/:id', (req, res) => {
  try {
    const id = Number(req.params.id);
    if (!Number.isInteger(id)) {
      return res.status(400).json({ error: 'Geçersiz malzeme id değeri.' });
    }

    const material = db.prepare('SELECT * FROM materials WHERE id = ?').get(id);
    if (!material) {
      return res.status(404).json({ error: 'Malzeme bulunamadı.' });
    }

    const usageHistory = db
      .prepare(
        `SELECT
           wom.id, wom.work_order_id, wom.quantity_used, wom.created_at,
           wo.title AS work_order_title,
           u.id AS recorded_by_id, u.name AS recorded_by_name
         FROM work_order_materials wom
         JOIN work_orders wo ON wo.id = wom.work_order_id
         JOIN users u ON u.id = wom.recorded_by_user_id
         WHERE wom.material_id = ?
         ORDER BY wom.created_at DESC`
      )
      .all(id);

    // Cihaz Yönetimi/Kullanıcı Yönetimi'ndeki "işlem geçmişi" deseniyle AYNI:
    // hem kullanım hem ikmal/iade hareketleri TEK bir kronolojik listede.
    const stockMovements = db
      .prepare(
        `SELECT sm.*, u.name AS performed_by_name
         FROM material_stock_movements sm
         JOIN users u ON u.id = sm.performed_by_user_id
         WHERE sm.material_id = ?
         ORDER BY sm.created_at DESC`
      )
      .all(id);

    res.json({ ...mapMaterialRow(material), usage_history: usageHistory, stock_movements: stockMovements });
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'Malzeme detayı alınırken bir hata oluştu.' });
  }
});

// POST /api/materials — yalnızca yönetici. Yeni bir malzeme TİPİ tanımlar.
router.post('/materials', requireRole('yonetici'), (req, res) => {
  try {
    const { name, category, unit, min_stock_threshold, compatible_equipment_types, unit_cost } = req.body;
    const initialStock = Number(req.body.stock_quantity ?? 0);
    const minThreshold = Number(min_stock_threshold ?? 0);

    if (!name || !String(name).trim()) {
      return res.status(400).json({ error: 'name alanı zorunludur.' });
    }
    if (!category || !VALID_CATEGORIES.includes(category)) {
      return res.status(400).json({ error: `Geçersiz category değeri. Geçerli değerler: ${VALID_CATEGORIES.join(', ')}` });
    }
    if (!unit || !VALID_UNITS.includes(unit)) {
      return res.status(400).json({ error: `Geçersiz unit değeri. Geçerli değerler: ${VALID_UNITS.join(', ')}` });
    }
    if (!Number.isFinite(initialStock) || initialStock < 0) {
      return res.status(400).json({ error: 'stock_quantity negatif olamaz.' });
    }
    if (!Number.isFinite(minThreshold) || minThreshold < 0) {
      return res.status(400).json({ error: 'min_stock_threshold negatif olamaz.' });
    }
    if (!validateCompatibleTypes(compatible_equipment_types)) {
      return res.status(400).json({
        error: `compatible_equipment_types en az bir geçerli ekipman tipi içermeli. Geçerli değerler: ${VALID_EQUIPMENT_TYPES.join(', ')}`,
      });
    }

    const info = db
      .prepare(
        `INSERT INTO materials
           (name, category, unit, stock_quantity, min_stock_threshold, compatible_equipment_types, unit_cost, created_at)
         VALUES (@name, @category, @unit, @stock_quantity, @min_stock_threshold, @compatible_equipment_types, @unit_cost, @created_at)`
      )
      .run({
        name: String(name).trim(),
        category,
        unit,
        stock_quantity: initialStock,
        min_stock_threshold: minThreshold,
        compatible_equipment_types: compatible_equipment_types.join(','),
        unit_cost: unit_cost != null ? Number(unit_cost) : null,
        created_at: new Date().toISOString(),
      });

    const created = db.prepare('SELECT * FROM materials WHERE id = ?').get(info.lastInsertRowid);
    res.status(201).json(mapMaterialRow(created));
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'Malzeme oluşturulurken bir hata oluştu.' });
  }
});

// PATCH /api/materials/:id — yalnızca yönetici. Yalnızca TANIM alanları
// (isim/kategori/birim/eşik/uyumlu tipler/birim maliyet) değişir — stok
// miktarı BURADAN asla değiştirilmez, kasıtlı olarak (bkz. POST /:id/restock);
// stok her zaman ya bir kullanım ya da bir ikmal HAREKETİ üzerinden değişmeli
// ki material_stock_movements her zaman stok değişikliklerinin TAM geçmişi olsun.
router.patch('/materials/:id', requireRole('yonetici'), (req, res) => {
  try {
    const id = Number(req.params.id);
    if (!Number.isInteger(id)) {
      return res.status(400).json({ error: 'Geçersiz malzeme id değeri.' });
    }

    const existing = db.prepare('SELECT id FROM materials WHERE id = ?').get(id);
    if (!existing) {
      return res.status(404).json({ error: 'Malzeme bulunamadı.' });
    }

    const { name, category, unit, min_stock_threshold, compatible_equipment_types, unit_cost } = req.body;

    if (category !== undefined && !VALID_CATEGORIES.includes(category)) {
      return res.status(400).json({ error: `Geçersiz category değeri. Geçerli değerler: ${VALID_CATEGORIES.join(', ')}` });
    }
    if (unit !== undefined && !VALID_UNITS.includes(unit)) {
      return res.status(400).json({ error: `Geçersiz unit değeri. Geçerli değerler: ${VALID_UNITS.join(', ')}` });
    }
    if (compatible_equipment_types !== undefined && !validateCompatibleTypes(compatible_equipment_types)) {
      return res.status(400).json({
        error: `compatible_equipment_types en az bir geçerli ekipman tipi içermeli. Geçerli değerler: ${VALID_EQUIPMENT_TYPES.join(', ')}`,
      });
    }

    const fields = [];
    const params = [];
    if (name !== undefined) {
      fields.push('name = ?');
      params.push(String(name).trim());
    }
    if (category !== undefined) {
      fields.push('category = ?');
      params.push(category);
    }
    if (unit !== undefined) {
      fields.push('unit = ?');
      params.push(unit);
    }
    if (min_stock_threshold !== undefined) {
      fields.push('min_stock_threshold = ?');
      params.push(Number(min_stock_threshold));
    }
    if (compatible_equipment_types !== undefined) {
      fields.push('compatible_equipment_types = ?');
      params.push(compatible_equipment_types.join(','));
    }
    if (unit_cost !== undefined) {
      fields.push('unit_cost = ?');
      params.push(unit_cost != null ? Number(unit_cost) : null);
    }

    if (fields.length > 0) {
      params.push(id);
      db.prepare(`UPDATE materials SET ${fields.join(', ')} WHERE id = ?`).run(...params);
    }

    const updated = db.prepare('SELECT * FROM materials WHERE id = ?').get(id);
    res.json(mapMaterialRow(updated));
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'Malzeme güncellenirken bir hata oluştu.' });
  }
});

// POST /api/materials/:id/restock — yalnızca yönetici. Stok girişi/ikmali.
// Body: { quantity_added }
router.post('/materials/:id/restock', requireRole('yonetici'), (req, res) => {
  try {
    const id = Number(req.params.id);
    if (!Number.isInteger(id)) {
      return res.status(400).json({ error: 'Geçersiz malzeme id değeri.' });
    }

    const material = db.prepare('SELECT * FROM materials WHERE id = ?').get(id);
    if (!material) {
      return res.status(404).json({ error: 'Malzeme bulunamadı.' });
    }

    const quantityAdded = Number(req.body.quantity_added);
    if (!Number.isFinite(quantityAdded) || quantityAdded <= 0) {
      return res.status(400).json({ error: 'quantity_added pozitif bir sayı olmalıdır.' });
    }

    db.exec('BEGIN');
    try {
      db.prepare('UPDATE materials SET stock_quantity = stock_quantity + ? WHERE id = ?').run(quantityAdded, id);
      logStockMovement({
        materialId: id,
        movementType: 'ikmal',
        quantity: quantityAdded,
        workOrderId: null,
        performedByUserId: req.user.id,
      });
      db.exec('COMMIT');
    } catch (txErr) {
      db.exec('ROLLBACK');
      throw txErr;
    }

    const updated = db.prepare('SELECT * FROM materials WHERE id = ?').get(id);
    res.json(mapMaterialRow(updated));
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'Stok ikmali yapılırken bir hata oluştu.' });
  }
});

// GET /api/workorders/:workOrderId/materials — bir iş emrinde kullanılan
// malzemeleri listeler (giriş yapmış herkes).
router.get('/workorders/:workOrderId/materials', (req, res) => {
  try {
    const workOrderId = Number(req.params.workOrderId);
    if (!Number.isInteger(workOrderId)) {
      return res.status(400).json({ error: 'Geçersiz iş emri id değeri.' });
    }

    const rows = db
      .prepare(
        `SELECT
           wom.id, wom.work_order_id, wom.material_id, wom.quantity_used, wom.created_at,
           m.name AS material_name, m.unit AS material_unit, m.category AS material_category,
           u.id AS recorded_by_id, u.name AS recorded_by_name
         FROM work_order_materials wom
         JOIN materials m ON m.id = wom.material_id
         JOIN users u ON u.id = wom.recorded_by_user_id
         WHERE wom.work_order_id = ?
         ORDER BY wom.created_at DESC`
      )
      .all(workOrderId);

    res.json(
      rows.map((row) => ({
        id: row.id,
        work_order_id: row.work_order_id,
        quantity_used: row.quantity_used,
        created_at: row.created_at,
        material: { id: row.material_id, name: row.material_name, unit: row.material_unit, category: row.material_category },
        recorded_by: { id: row.recorded_by_id, name: row.recorded_by_name },
      }))
    );
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'İş emrinde kullanılan malzemeler listelenirken bir hata oluştu.' });
  }
});

// Bir malzemenin stoğu İLK KEZ eşiğin altına indiyse (önceki durum eşiğin
// üstündeyse) tüm yöneticilere bildirim gönderir — Modül 9/12'deki
// "notifyManagersIfRiskBecameHigh" ile AYNI "yalnızca ilk geçişte bildir"
// deseni, aksi halde aynı malzeme eşiğin altındayken her yeni kullanımda
// tekrar tekrar bildirim gider ve liste anlamsızca şişer.
function notifyManagersIfStockBecameCritical(material, previousQuantity, newQuantity) {
  const wasAboveThreshold = previousQuantity > material.min_stock_threshold;
  const isNowAtOrBelowThreshold = newQuantity <= material.min_stock_threshold;
  if (!wasAboveThreshold || !isNowAtOrBelowThreshold) return;

  const managers = db.prepare("SELECT id FROM users WHERE role = 'yonetici' AND is_active = 1").all();
  for (const manager of managers) {
    createNotification(
      manager.id,
      `${material.name} stoğu kritik seviyeye düştü (${newQuantity} ${material.unit} kaldı)`,
      'material',
      material.id
    );
  }
}

// POST /api/workorders/:workOrderId/materials — giriş yapmış HERKES
// (teknisyen dahil — sahada malzemeyi kullanan kişi odur).
// Body: { material_id, quantity_used }
//
// KRİTİK İŞ KURALI: work_order_materials kaydı + materials.stock_quantity
// düşüşü + material_stock_movements kaydı TEK BİR TRANSACTION içinde yapılır
// — biri başarısız olursa hiçbiri kalıcı olmaz (yarım kalmış/tutarsız stok
// durumu asla oluşmaz). Stok asla negatife düşmez: yetersizse transaction
// hiç BAŞLAMADAN 400 ile reddedilir.
router.post('/workorders/:workOrderId/materials', (req, res) => {
  try {
    const workOrderId = Number(req.params.workOrderId);
    if (!Number.isInteger(workOrderId)) {
      return res.status(400).json({ error: 'Geçersiz iş emri id değeri.' });
    }

    const workOrder = db.prepare('SELECT id FROM work_orders WHERE id = ?').get(workOrderId);
    if (!workOrder) {
      return res.status(404).json({ error: 'İş emri bulunamadı.' });
    }

    const materialId = Number(req.body.material_id);
    const quantityUsed = Number(req.body.quantity_used);
    if (!Number.isInteger(materialId)) {
      return res.status(400).json({ error: 'material_id alanı zorunludur.' });
    }
    if (!Number.isFinite(quantityUsed) || quantityUsed <= 0) {
      return res.status(400).json({ error: 'quantity_used pozitif bir sayı olmalıdır.' });
    }

    const material = db.prepare('SELECT * FROM materials WHERE id = ?').get(materialId);
    if (!material) {
      return res.status(404).json({ error: 'Malzeme bulunamadı.' });
    }

    // Stok kontrolü transaction'dan ÖNCE yapılır — yetersizse hiçbir yazma
    // işlemi başlamaz, stok asla negatife düşmez.
    if (quantityUsed > material.stock_quantity) {
      return res.status(400).json({
        error: `Yetersiz stok: mevcut ${material.stock_quantity} ${material.unit}, istenen ${quantityUsed} ${material.unit}`,
      });
    }

    const now = new Date().toISOString();
    const previousQuantity = material.stock_quantity;
    const newQuantity = previousQuantity - quantityUsed;

    let usageId;
    db.exec('BEGIN');
    try {
      const info = db
        .prepare(
          `INSERT INTO work_order_materials (work_order_id, material_id, quantity_used, recorded_by_user_id, created_at)
           VALUES (?, ?, ?, ?, ?)`
        )
        .run(workOrderId, materialId, quantityUsed, req.user.id, now);
      usageId = info.lastInsertRowid;

      db.prepare('UPDATE materials SET stock_quantity = ? WHERE id = ?').run(newQuantity, materialId);

      logStockMovement({
        materialId,
        movementType: 'kullanim',
        quantity: -quantityUsed,
        workOrderId,
        performedByUserId: req.user.id,
      });

      db.exec('COMMIT');
    } catch (txErr) {
      db.exec('ROLLBACK');
      throw txErr;
    }

    // Bildirim Sistemi (Modül 6) — transaction başarıyla COMMIT olduktan
    // SONRA gönderilir; aksi halde rollback olan bir işlem için yanlışlıkla
    // bildirim gitmiş olurdu.
    notifyManagersIfStockBecameCritical(material, previousQuantity, newQuantity);

    const usage = db
      .prepare(
        `SELECT wom.id, wom.work_order_id, wom.material_id, wom.quantity_used, wom.created_at,
                u.id AS recorded_by_id, u.name AS recorded_by_name
         FROM work_order_materials wom
         JOIN users u ON u.id = wom.recorded_by_user_id
         WHERE wom.id = ?`
      )
      .get(usageId);

    res.status(201).json({
      id: usage.id,
      work_order_id: usage.work_order_id,
      quantity_used: usage.quantity_used,
      created_at: usage.created_at,
      material: mapMaterialRow(db.prepare('SELECT * FROM materials WHERE id = ?').get(materialId)),
      recorded_by: { id: usage.recorded_by_id, name: usage.recorded_by_name },
    });
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'Malzeme kullanımı kaydedilirken bir hata oluştu.' });
  }
});

// DELETE /api/workorders/:workOrderId/materials/:usageId — dispeçer/yönetici.
// Yanlış girilen bir kullanım kaydını siler VE düşülen stoğu GERİ EKLER.
// Teknisyen bu endpoint'e erişemez (kasıtlı — yanlışlıkla/kötü niyetli stok
// iadesi ile veri kaybını önlemek için, bkz. dosya başındaki RBAC özeti).
router.delete('/workorders/:workOrderId/materials/:usageId', requireRole('dispecer', 'yonetici'), (req, res) => {
  try {
    const workOrderId = Number(req.params.workOrderId);
    const usageId = Number(req.params.usageId);
    if (!Number.isInteger(workOrderId) || !Number.isInteger(usageId)) {
      return res.status(400).json({ error: 'Geçersiz id değeri.' });
    }

    const usage = db
      .prepare('SELECT * FROM work_order_materials WHERE id = ? AND work_order_id = ?')
      .get(usageId, workOrderId);
    if (!usage) {
      return res.status(404).json({ error: 'Malzeme kullanım kaydı bulunamadı.' });
    }

    db.exec('BEGIN');
    try {
      db.prepare('DELETE FROM work_order_materials WHERE id = ?').run(usageId);
      db.prepare('UPDATE materials SET stock_quantity = stock_quantity + ? WHERE id = ?').run(
        usage.quantity_used,
        usage.material_id
      );
      // 'iade': ne saf bir 'kullanim' (stok azaltmıyor) ne saf bir 'ikmal'
      // (gerçek bir depo girişi değil, hatalı bir kaydın geri alınması) —
      // stok hareketi geçmişinde bu ayrımın kaybolmaması için üçüncü, ayrı
      // bir hareket tipi olarak kaydedilir (bkz. Flutter tarafı hareket
      // etiketleri, material_detail_screen.dart).
      logStockMovement({
        materialId: usage.material_id,
        movementType: 'iade',
        quantity: usage.quantity_used,
        workOrderId,
        performedByUserId: req.user.id,
      });
      db.exec('COMMIT');
    } catch (txErr) {
      db.exec('ROLLBACK');
      throw txErr;
    }

    res.json({ success: true });
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'Malzeme kullanım kaydı silinirken bir hata oluştu.' });
  }
});

// GET /api/dashboard/low-stock-materials — giriş yapmış herkes. Dashboard
// widget'ı için kritik stoktaki malzemeleri döner (en kritik/en az kalan önce).
router.get('/dashboard/low-stock-materials', (req, res) => {
  try {
    const limit = Math.min(Math.max(Number(req.query.limit) || 5, 1), 20);
    const rows = db
      .prepare(
        `SELECT * FROM materials
         WHERE stock_quantity <= min_stock_threshold
         ORDER BY (stock_quantity - min_stock_threshold) ASC
         LIMIT ?`
      )
      .all(limit);
    res.json(rows.map(mapMaterialRow));
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'Kritik stoktaki malzemeler alınırken bir hata oluştu.' });
  }
});

module.exports = router;
