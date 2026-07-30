// İş Emri / Arıza Yönetimi modülüne ait tüm endpoint'ler.
const path = require('path');
const crypto = require('crypto');
const express = require('express');
const multer = require('multer');
const db = require('../database');
const { requireRole } = require('../middleware/auth');

const router = express.Router();

const VALID_STATUSES = ['acik', 'yolda', 'sahada', 'cozuldu'];
const VALID_PRIORITIES = ['acil', 'normal', 'dusuk'];

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

// İş emri satırlarına atanan kullanıcının ad/rol bilgisini ve (varsa) bağlı
// ekipmanın QR kodunu gömen ortak SELECT. `equipment_id` iş emri Modül 4'e
// gerçek bir FK ile bağlıdır (bkz. database.js); ekranda gösterilen
// `equipment_ref` ise bu FK üzerinden JOIN edilen ekipmanın qr_code'udur.
const SELECT_WORK_ORDER_WITH_USER = `
  SELECT
    wo.*,
    u.id AS assigned_user_id_join,
    u.name AS assigned_user_name,
    u.role AS assigned_user_role,
    e.qr_code AS equipment_qr_code
  FROM work_orders wo
  LEFT JOIN users u ON u.id = wo.assigned_user_id
  LEFT JOIN equipment e ON e.id = wo.equipment_id
`;

function mapWorkOrderRow(row) {
  const { assigned_user_id_join, assigned_user_name, assigned_user_role, equipment_qr_code, ...workOrder } = row;
  return {
    ...workOrder,
    assigned_user: assigned_user_id_join
      ? { id: assigned_user_id_join, name: assigned_user_name, role: assigned_user_role }
      : null,
    // Modül 4 (Ekipman) ile geriye dönük uyumluluk: Flutter tarafı bu alanı
    // QR kodu göstermek için okur; `equipment_id` ise Ekipman Detayı'na
    // gitmek için ayrıca üstte (workOrder spread'i içinde) yer alır.
    equipment_ref: equipment_qr_code || '',
  };
}

// GET /api/workorders?status=acik
// Tüm iş emirlerini listeler, opsiyonel status filtresi destekler.
// Teknisyen rolündeki kullanıcılar yalnızca kendine atanan işleri görür —
// bu filtre burada, backend'de zorunlu kılınır (Flutter tarafı ekstra bir şey
// göndermez, token'daki role/id üzerinden otomatik uygulanır).
router.get('/', (req, res) => {
  try {
    const { status } = req.query;

    if (status && !VALID_STATUSES.includes(status)) {
      return res.status(400).json({
        error: `Geçersiz status değeri. Geçerli değerler: ${VALID_STATUSES.join(', ')}`,
      });
    }

    const conditions = [];
    const params = [];
    if (status) {
      conditions.push('wo.status = ?');
      params.push(status);
    }
    if (req.user.role === 'teknisyen') {
      conditions.push('wo.assigned_user_id = ?');
      params.push(req.user.id);
    }
    const whereClause = conditions.length ? `WHERE ${conditions.join(' AND ')}` : '';

    const rows = db
      .prepare(`${SELECT_WORK_ORDER_WITH_USER} ${whereClause} ORDER BY wo.created_at DESC`)
      .all(...params);

    res.json(rows.map(mapWorkOrderRow));
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'İş emirleri listelenirken bir hata oluştu.' });
  }
});

// POST /api/workorders
// Yeni iş emri oluşturur (yalnızca dispeçer/yönetici — bkz. requireRole).
// Body: { title, description, priority, location_name, lat, lng, assigned_user_id, equipment_id? }
// Oluşturulan kaydın status'ü her zaman 'acik'tir.
router.post('/', requireRole('dispecer', 'yonetici'), (req, res) => {
  try {
    const { title, description, priority, location_name, assigned_user_id, equipment_id } = req.body;
    const lat = Number(req.body.lat);
    const lng = Number(req.body.lng);
    const assignedUserId = Number(assigned_user_id);
    const equipmentId = equipment_id != null && equipment_id !== '' ? Number(equipment_id) : null;

    if (!title || !title.trim()) {
      return res.status(400).json({ error: 'title alanı zorunludur.' });
    }
    if (!priority || !VALID_PRIORITIES.includes(priority)) {
      return res.status(400).json({
        error: `Geçersiz priority değeri. Geçerli değerler: ${VALID_PRIORITIES.join(', ')}`,
      });
    }
    if (!location_name || !location_name.trim()) {
      return res.status(400).json({ error: 'location_name alanı zorunludur.' });
    }
    if (Number.isNaN(lat) || Number.isNaN(lng)) {
      return res.status(400).json({ error: 'lat ve lng alanları zorunludur.' });
    }
    if (!Number.isInteger(assignedUserId)) {
      return res.status(400).json({ error: 'assigned_user_id alanı zorunludur.' });
    }

    const assignedUser = db.prepare('SELECT id, role FROM users WHERE id = ?').get(assignedUserId);
    if (!assignedUser || assignedUser.role !== 'teknisyen') {
      return res.status(400).json({ error: 'assigned_user_id geçerli bir teknisyene ait olmalı.' });
    }

    if (equipmentId != null) {
      const equipment = db.prepare('SELECT id FROM equipment WHERE id = ?').get(equipmentId);
      if (!equipment) {
        return res.status(400).json({ error: 'equipment_id geçerli bir ekipmana ait değil.' });
      }
    }

    const now = new Date().toISOString();
    const info = db
      .prepare(
        `INSERT INTO work_orders
           (title, description, status, priority, location_name, lat, lng, assigned_user_id, equipment_id, created_at, updated_at)
         VALUES
           (@title, @description, 'acik', @priority, @location_name, @lat, @lng, @assigned_user_id, @equipment_id, @created_at, @updated_at)`
      )
      .run({
        title: title.trim(),
        description: description ? description.trim() : '',
        priority,
        location_name: location_name.trim(),
        lat,
        lng,
        assigned_user_id: assignedUserId,
        equipment_id: equipmentId,
        created_at: now,
        updated_at: now,
      });

    const created = db.prepare(`${SELECT_WORK_ORDER_WITH_USER} WHERE wo.id = ?`).get(info.lastInsertRowid);
    res.status(201).json(mapWorkOrderRow(created));
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'İş emri oluşturulurken bir hata oluştu.' });
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

    // equipment_id dahil edilir ki harita bilgi balonunda (varsa) "Ekipman
    // Detayını Gör" bağlantısı gösterilebilsin (bkz. map_screen.dart).
    const baseQuery = 'SELECT id, title, status, priority, lat, lng, equipment_id FROM work_orders WHERE lat IS NOT NULL AND lng IS NOT NULL';
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
