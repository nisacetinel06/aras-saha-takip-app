// İSG (İş Sağlığı ve Güvenliği) Bildirimi modülüne ait tüm endpoint'ler (Modül 5).
//
// Diğer modüllerin aksine burada fotoğraf VE konum ikisi de baştan itibaren
// gerçektir: fotoğraf gerçekten diske yazılır (bkz. work_orders/:id/photos ile
// aynı desen), lat/lng ise Flutter tarafında cihazın gerçek GPS'inden
// (geolocator) okunur ve zorunlu alan olarak buraya gelir.
const path = require('path');
const crypto = require('crypto');
const express = require('express');
const multer = require('multer');
const db = require('../database');

const router = express.Router();

const VALID_CATEGORIES = ['ekipman_arizasi', 'tehlikeli_durum', 'is_kazasi_riski', 'diger'];
const VALID_STATUSES = ['bekliyor', 'incelendi', 'cozuldu'];

const ISG_UPLOADS_DIR = path.join(__dirname, '..', 'uploads', 'isg');

// Dosyalar gerçekten uploads/isg/ klasörüne yazılır ve server.js tarafından
// /uploads statik yolu üzerinden servis edilir. Dosya adı, istemcinin
// gönderdiği orijinal isme değil (path traversal / çakışma riski) rastgele
// bir isme dayanır — work_orders/:id/photos ile aynı, kanıtlanmış desen.
const storage = multer.diskStorage({
  destination: (req, file, cb) => cb(null, ISG_UPLOADS_DIR),
  filename: (req, file, cb) => {
    const ext = path.extname(file.originalname) || '.jpg';
    const uniqueName = `${Date.now()}-${crypto.randomBytes(8).toString('hex')}${ext}`;
    cb(null, uniqueName);
  },
});

const upload = multer({
  storage,
  limits: { fileSize: 5 * 1024 * 1024 }, // 5 MB
  fileFilter: (req, file, cb) => {
    const allowed = ['image/jpeg', 'image/png'];
    if (!allowed.includes(file.mimetype)) {
      return cb(new Error('Yalnızca .jpg, .jpeg veya .png uzantılı resim dosyaları yüklenebilir.'));
    }
    cb(null, true);
  },
});

// İSG bildirimi satırlarına bildiren kullanıcının ad/rol bilgisini gömen
// ortak SELECT (work_orders'daki assigned_user deseniyle aynı).
const SELECT_ISG_WITH_USER = `
  SELECT
    r.*,
    u.id AS reported_by_id_join,
    u.name AS reported_by_name,
    u.role AS reported_by_role
  FROM isg_reports r
  LEFT JOIN users u ON u.id = r.reported_by_user_id
`;

function mapIsgRow(row) {
  const { reported_by_id_join, reported_by_name, reported_by_role, ...report } = row;
  return {
    ...report,
    reported_by: reported_by_id_join
      ? { id: reported_by_id_join, name: reported_by_name, role: reported_by_role }
      : null,
  };
}

// GET /api/isg-reports?status=bekliyor
router.get('/', (req, res) => {
  try {
    const { status } = req.query;

    if (status && !VALID_STATUSES.includes(status)) {
      return res.status(400).json({
        error: `Geçersiz status değeri. Geçerli değerler: ${VALID_STATUSES.join(', ')}`,
      });
    }

    const rows = status
      ? db.prepare(`${SELECT_ISG_WITH_USER} WHERE r.status = ? ORDER BY r.created_at DESC`).all(status)
      : db.prepare(`${SELECT_ISG_WITH_USER} ORDER BY r.created_at DESC`).all();

    res.json(rows.map(mapIsgRow));
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'İSG bildirimleri listelenirken bir hata oluştu.' });
  }
});

// GET /api/isg-reports/:id
router.get('/:id', (req, res) => {
  try {
    const id = Number(req.params.id);
    if (!Number.isInteger(id)) {
      return res.status(400).json({ error: 'Geçersiz bildirim id değeri.' });
    }

    const row = db.prepare(`${SELECT_ISG_WITH_USER} WHERE r.id = ?`).get(id);
    if (!row) {
      return res.status(404).json({ error: 'İSG bildirimi bulunamadı.' });
    }

    res.json(mapIsgRow(row));
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'İSG bildirimi detayı alınırken bir hata oluştu.' });
  }
});

// POST /api/isg-reports
// multipart/form-data — alanlar: reported_by_user_id, description, category,
// lat, lng, location_name (opsiyonel), photo (dosya, zorunlu).
router.post('/', (req, res) => {
  upload.single('photo')(req, res, (uploadErr) => {
    if (uploadErr) {
      return res.status(400).json({ error: uploadErr.message || 'Fotoğraf yüklenirken bir hata oluştu.' });
    }

    try {
      if (!req.file) {
        return res.status(400).json({ error: 'photo alanı (fotoğraf dosyası) zorunludur.' });
      }

      const { description, category, lat, lng } = req.body;
      const location_name = req.body.location_name || null;
      const reported_by_user_id = Number(req.body.reported_by_user_id);
      const latNum = Number(lat);
      const lngNum = Number(lng);

      if (!description || !description.trim()) {
        return res.status(400).json({ error: 'description alanı zorunludur.' });
      }
      if (!category || !VALID_CATEGORIES.includes(category)) {
        return res.status(400).json({
          error: `Geçersiz category değeri. Geçerli değerler: ${VALID_CATEGORIES.join(', ')}`,
        });
      }
      if (!Number.isInteger(reported_by_user_id)) {
        return res.status(400).json({ error: 'reported_by_user_id alanı zorunludur.' });
      }
      if (Number.isNaN(latNum) || Number.isNaN(lngNum)) {
        return res.status(400).json({ error: 'lat ve lng alanları zorunludur (gerçek GPS konumu).' });
      }

      const user = db.prepare('SELECT id FROM users WHERE id = ?').get(reported_by_user_id);
      if (!user) {
        return res.status(400).json({ error: 'reported_by_user_id geçerli bir kullanıcıya ait değil.' });
      }

      const photo_path = `/uploads/isg/${req.file.filename}`;
      const created_at = new Date().toISOString();

      const info = db
        .prepare(
          `INSERT INTO isg_reports
             (reported_by_user_id, description, category, photo_path, location_name, lat, lng, status, reviewer_note, created_at, reviewed_at)
           VALUES
             (@reported_by_user_id, @description, @category, @photo_path, @location_name, @lat, @lng, 'bekliyor', NULL, @created_at, NULL)`
        )
        .run({
          reported_by_user_id,
          description: description.trim(),
          category,
          photo_path,
          location_name,
          lat: latNum,
          lng: lngNum,
          created_at,
        });

      const created = db.prepare(`${SELECT_ISG_WITH_USER} WHERE r.id = ?`).get(info.lastInsertRowid);
      res.status(201).json(mapIsgRow(created));
    } catch (err) {
      console.error(err);
      res.status(500).json({ error: 'İSG bildirimi oluşturulurken bir hata oluştu.' });
    }
  });
});

// PATCH /api/isg-reports/:id/status
// Body: { "status": "incelendi", "reviewer_note": "..." (opsiyonel) }
router.patch('/:id/status', (req, res) => {
  try {
    const id = Number(req.params.id);
    if (!Number.isInteger(id)) {
      return res.status(400).json({ error: 'Geçersiz bildirim id değeri.' });
    }

    const { status, reviewer_note } = req.body;
    if (!status || !VALID_STATUSES.includes(status)) {
      return res.status(400).json({
        error: `Geçersiz status değeri. Geçerli değerler: ${VALID_STATUSES.join(', ')}`,
      });
    }

    const existing = db.prepare('SELECT id FROM isg_reports WHERE id = ?').get(id);
    if (!existing) {
      return res.status(404).json({ error: 'İSG bildirimi bulunamadı.' });
    }

    // 'bekliyor' dışına her geçişte inceleme zamanı damgalanır — bir yönetici
    // bu bildirime gerçekten baktığının kaydı.
    const reviewed_at = status === 'bekliyor' ? null : new Date().toISOString();

    db.prepare(
      'UPDATE isg_reports SET status = ?, reviewer_note = ?, reviewed_at = ? WHERE id = ?'
    ).run(status, reviewer_note || null, reviewed_at, id);

    const updated = db.prepare(`${SELECT_ISG_WITH_USER} WHERE r.id = ?`).get(id);
    res.json(mapIsgRow(updated));
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'İSG bildirimi durumu güncellenirken bir hata oluştu.' });
  }
});

module.exports = router;
