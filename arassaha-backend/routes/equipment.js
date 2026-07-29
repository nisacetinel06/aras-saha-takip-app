// Ekipman / Envanter (QR Kod) modülüne ait tüm endpoint'ler (Modül 4).
//
// ÖNEMLİ: `equipment` tablosundaki install_date/last_maintenance_date gibi
// alanlar bilinçli olarak buradadır — ileride eklenecek Arıza Risk Tahmini
// (Makine Öğrenmesi) modülü bu alanları (ve equipment_id üzerinden sayılacak
// geçmiş iş emri adedini) doğrudan girdi/feature olarak kullanacaktır.
// Bkz. database.js'teki şema yorumu ve ARCHITECTURE.md.
const express = require('express');
const db = require('../database');

const router = express.Router();

const VALID_TYPES = ['trafo', 'direk', 'kesici', 'sayac'];
const VALID_STATUSES = ['aktif', 'bakimda', 'devre_disi'];

// GET /api/equipment?type=trafo&status=aktif
router.get('/', (req, res) => {
  try {
    const { type, status } = req.query;

    if (type && !VALID_TYPES.includes(type)) {
      return res.status(400).json({
        error: `Geçersiz type değeri. Geçerli değerler: ${VALID_TYPES.join(', ')}`,
      });
    }
    if (status && !VALID_STATUSES.includes(status)) {
      return res.status(400).json({
        error: `Geçersiz status değeri. Geçerli değerler: ${VALID_STATUSES.join(', ')}`,
      });
    }

    const conditions = [];
    const params = [];
    if (type) {
      conditions.push('equipment_type = ?');
      params.push(type);
    }
    if (status) {
      conditions.push('status = ?');
      params.push(status);
    }
    const whereClause = conditions.length ? `WHERE ${conditions.join(' AND ')}` : '';

    const rows = db.prepare(`SELECT * FROM equipment ${whereClause} ORDER BY install_date DESC`).all(...params);
    res.json(rows);
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'Ekipmanlar listelenirken bir hata oluştu.' });
  }
});

// GET /api/equipment/qr/:qrCode
// Ana sorgulama yöntemi: QR tarama ya da manuel kod girişiyle çağrılır.
// Eşleşme yoksa 404 + Flutter tarafında doğrudan gösterilebilecek net bir mesaj döner.
router.get('/qr/:qrCode', (req, res) => {
  try {
    const { qrCode } = req.params;
    const row = db.prepare('SELECT * FROM equipment WHERE qr_code = ?').get(qrCode);

    if (!row) {
      return res.status(404).json({ error: 'Bu QR koda ait ekipman bulunamadı.' });
    }

    res.json(row);
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'Ekipman aranırken bir hata oluştu.' });
  }
});

// GET /api/equipment/:id — harita/liste üzerinden gelindiğinde kullanılır.
router.get('/:id', (req, res) => {
  try {
    const id = Number(req.params.id);
    if (!Number.isInteger(id)) {
      return res.status(400).json({ error: 'Geçersiz ekipman id değeri.' });
    }

    const row = db.prepare('SELECT * FROM equipment WHERE id = ?').get(id);
    if (!row) {
      return res.status(404).json({ error: 'Ekipman bulunamadı.' });
    }

    res.json(row);
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'Ekipman detayı alınırken bir hata oluştu.' });
  }
});

// GET /api/equipment/:id/history
// Bu ekipmana bağlı geçmiş iş emirlerini (arıza kayıtlarını) work_orders
// tablosundan JOIN ile getirir.
router.get('/:id/history', (req, res) => {
  try {
    const id = Number(req.params.id);
    if (!Number.isInteger(id)) {
      return res.status(400).json({ error: 'Geçersiz ekipman id değeri.' });
    }

    const equipment = db.prepare('SELECT id FROM equipment WHERE id = ?').get(id);
    if (!equipment) {
      return res.status(404).json({ error: 'Ekipman bulunamadı.' });
    }

    const history = db
      .prepare(
        `SELECT id, title, status, priority, created_at, updated_at
         FROM work_orders
         WHERE equipment_id = ?
         ORDER BY created_at DESC`
      )
      .all(id);

    res.json(history);
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'Ekipman geçmişi alınırken bir hata oluştu.' });
  }
});

module.exports = router;
