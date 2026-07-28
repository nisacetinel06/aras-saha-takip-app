// İş Emri / Arıza Yönetimi modülüne ait tüm endpoint'ler.
const path = require('path');
const crypto = require('crypto');
const express = require('express');
const multer = require('multer');
const db = require('../database');

const router = express.Router();

const VALID_STATUSES = ['acik', 'yolda', 'sahada', 'cozuldu'];

const UPLOADS_DIR = path.join(__dirname, '..', 'uploads');

// Fotoğraflar gerçekten bu klasöre yazılır ve server.js tarafından
// /uploads/<dosya> statik yolu üzerinden servis edilir (bkz. ARCHITECTURE.md Bölüm 11.2).
const storage = multer.diskStorage({
  destination: (req, file, cb) => cb(null, UPLOADS_DIR),
  filename: (req, file, cb) => {
    const ext = path.extname(file.originalname) || '.jpg';
    const uniqueName = `${Date.now()}-${crypto.randomBytes(8).toString('hex')}${ext}`;
    cb(null, uniqueName);
  },
});

const upload = multer({
  storage,
  limits: { fileSize: 10 * 1024 * 1024 },
  fileFilter: (req, file, cb) => {
    if (!file.mimetype.startsWith('image/')) {
      return cb(new Error('Yalnızca resim dosyaları yüklenebilir.'));
    }
    cb(null, true);
  },
});

// İş emri satırlarına atanan kullanıcının ad/rol bilgisini gömen ortak SELECT.
const SELECT_WORK_ORDER_WITH_USER = `
  SELECT
    wo.*,
    u.id AS assigned_user_id_join,
    u.name AS assigned_user_name,
    u.role AS assigned_user_role
  FROM work_orders wo
  LEFT JOIN users u ON u.id = wo.assigned_user_id
`;

function mapWorkOrderRow(row) {
  const { assigned_user_id_join, assigned_user_name, assigned_user_role, ...workOrder } = row;
  return {
    ...workOrder,
    assigned_user: assigned_user_id_join
      ? { id: assigned_user_id_join, name: assigned_user_name, role: assigned_user_role }
      : null,
  };
}

// GET /api/workorders?status=acik
// Tüm iş emirlerini listeler, opsiyonel status filtresi destekler.
router.get('/', (req, res) => {
  try {
    const { status } = req.query;

    if (status && !VALID_STATUSES.includes(status)) {
      return res.status(400).json({
        error: `Geçersiz status değeri. Geçerli değerler: ${VALID_STATUSES.join(', ')}`,
      });
    }

    let rows;
    if (status) {
      rows = db
        .prepare(`${SELECT_WORK_ORDER_WITH_USER} WHERE wo.status = ? ORDER BY wo.created_at DESC`)
        .all(status);
    } else {
      rows = db.prepare(`${SELECT_WORK_ORDER_WITH_USER} ORDER BY wo.created_at DESC`).all();
    }

    res.json(rows.map(mapWorkOrderRow));
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'İş emirleri listelenirken bir hata oluştu.' });
  }
});

// GET /api/workorders/map?status=acik
// Harita ekranı için hafif alan seti döner: id, title, status, priority, lat, lng.
// (Bu route, ":id" route'undan ÖNCE tanımlanmalı; aksi halde Express "map" değerini
// bir id parametresi sanıp o route'a düşer.)
// lat/lng değeri olmayan kayıtlar haritada gösterilemeyeceği için sonuca dahil edilmez.
router.get('/map', (req, res) => {
  try {
    const { status } = req.query;

    if (status && !VALID_STATUSES.includes(status)) {
      return res.status(400).json({
        error: `Geçersiz status değeri. Geçerli değerler: ${VALID_STATUSES.join(', ')}`,
      });
    }

    const baseQuery = 'SELECT id, title, status, priority, lat, lng FROM work_orders WHERE lat IS NOT NULL AND lng IS NOT NULL';
    const rows = status
      ? db.prepare(`${baseQuery} AND status = ? ORDER BY id`).all(status)
      : db.prepare(`${baseQuery} ORDER BY id`).all();

    res.json(rows);
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'Harita verileri alınırken bir hata oluştu.' });
  }
});

// GET /api/workorders/:id
// Tek bir iş emrinin detayını, atanan kişi ve ilişkili fotoğraflarıyla birlikte döner.
// Bu endpoint hangi kullanıcı/cihazdan çağrılırsa çağrılsın aynı kalıcı veriyi döner
// (örn. saha amiri kendi ekranından açtığında teknisyenin eklediği fotoğrafı görür).
router.get('/:id', (req, res) => {
  try {
    const id = Number(req.params.id);
    if (!Number.isInteger(id)) {
      return res.status(400).json({ error: 'Geçersiz iş emri id değeri.' });
    }

    const row = db.prepare(`${SELECT_WORK_ORDER_WITH_USER} WHERE wo.id = ?`).get(id);
    if (!row) {
      return res.status(404).json({ error: 'İş emri bulunamadı.' });
    }

    const photos = db
      .prepare('SELECT * FROM work_order_photos WHERE work_order_id = ? ORDER BY created_at DESC')
      .all(id);

    res.json({ ...mapWorkOrderRow(row), photos });
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'İş emri detayı alınırken bir hata oluştu.' });
  }
});

// PATCH /api/workorders/:id/status
// Body: { "status": "yolda" }
router.patch('/:id/status', (req, res) => {
  try {
    const id = Number(req.params.id);
    if (!Number.isInteger(id)) {
      return res.status(400).json({ error: 'Geçersiz iş emri id değeri.' });
    }

    const { status } = req.body;
    if (!status || !VALID_STATUSES.includes(status)) {
      return res.status(400).json({
        error: `Geçersiz status değeri. Geçerli değerler: ${VALID_STATUSES.join(', ')}`,
      });
    }

    const existing = db.prepare('SELECT id FROM work_orders WHERE id = ?').get(id);
    if (!existing) {
      return res.status(404).json({ error: 'İş emri bulunamadı.' });
    }

    const updatedAt = new Date().toISOString();
    db.prepare('UPDATE work_orders SET status = ?, updated_at = ? WHERE id = ?').run(status, updatedAt, id);

    const updated = db.prepare(`${SELECT_WORK_ORDER_WITH_USER} WHERE wo.id = ?`).get(id);
    res.json(mapWorkOrderRow(updated));
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'İş emri durumu güncellenirken bir hata oluştu.' });
  }
});

// POST /api/workorders/:id/photos
// multipart/form-data, dosya alanı adı: "photo"
// Dosya gerçekten backend'in diskindeki uploads/ klasörüne yazılır ve
// work_order_photos.photo_path alanına /uploads/<dosya> statik URL'i kaydedilir.
// Böylece başka bir cihazdan bağlanan kullanıcı (örn. saha amiri) bu fotoğrafı
// GET /api/workorders/:id üzerinden gerçekten görüntüleyebilir.
router.post('/:id/photos', (req, res) => {
  upload.single('photo')(req, res, (err) => {
    if (err) {
      return res.status(400).json({ error: err.message || 'Fotoğraf yüklenirken bir hata oluştu.' });
    }

    try {
      const id = Number(req.params.id);
      if (!Number.isInteger(id)) {
        return res.status(400).json({ error: 'Geçersiz iş emri id değeri.' });
      }

      if (!req.file) {
        return res.status(400).json({ error: 'photo alanı (dosya) zorunludur.' });
      }

      const workOrder = db.prepare('SELECT id FROM work_orders WHERE id = ?').get(id);
      if (!workOrder) {
        return res.status(404).json({ error: 'İş emri bulunamadı.' });
      }

      const photoPath = `/uploads/${req.file.filename}`;
      const createdAt = new Date().toISOString();
      const info = db
        .prepare('INSERT INTO work_order_photos (work_order_id, photo_path, created_at) VALUES (?, ?, ?)')
        .run(id, photoPath, createdAt);

      const photo = db.prepare('SELECT * FROM work_order_photos WHERE id = ?').get(info.lastInsertRowid);
      res.status(201).json(photo);
    } catch (innerErr) {
      console.error(innerErr);
      res.status(500).json({ error: 'Fotoğraf eklenirken bir hata oluştu.' });
    }
  });
});

module.exports = router;
