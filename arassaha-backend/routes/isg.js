// İSG (İş Sağlığı ve Güvenliği) Bildirimi modülüne ait tüm endpoint'ler (Modül 5).
//
// Diğer modüllerin aksine burada fotoğraf VE konum ikisi de baştan itibaren
// gerçektir: fotoğraf gerçekten diske yazılır (bkz. work_orders/:id/photos ile
// aynı desen), lat/lng ise Flutter tarafında cihazın gerçek GPS'inden
// (geolocator) okunur ve zorunlu alan olarak buraya gelir.
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const express = require('express');
const multer = require('multer');
const db = require('../database');
const { requireRole } = require('../middleware/auth');
const validateImageContent = require('../middleware/validateImageContent');
const { createNotification } = require('../utils/notify');
const { classifyImageForDamage } = require('../utils/damageDetection');

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
// multipart/form-data — alanlar: description, category, lat, lng,
// location_name (opsiyonel), photo (dosya, zorunlu).
// reported_by_user_id istemciden ALINMAZ: bildiren kişi her zaman zaten giriş
// yapmış kullanıcıdır (req.user.id, verifyToken tarafından JWT'den doldurulur)
// — bu sayede kullanıcı kendi adına değil başkası adına bildirim giremez ve
// Flutter formunda tekrar "bildiren kişi" seçtirmeye gerek kalmaz.
router.post('/', (req, res) => {
  upload.single('photo')(req, res, (uploadErr) => {
    if (uploadErr) {
      return res.status(400).json({ error: uploadErr.message || 'Fotoğraf yüklenirken bir hata oluştu.' });
    }

    if (!req.file) {
      return res.status(400).json({ error: 'photo alanı (fotoğraf dosyası) zorunludur.' });
    }

    // Dosya İÇERİĞİ (magic number) doğrulaması — mimetype/uzantı YALNIZCA
    // istemcinin beyanıdır, sahtelenebilir (bkz. middleware/validateImageContent.js).
    validateImageContent(req, res, async () => {
      try {
        const { description, category, lat, lng } = req.body;
        const location_name = req.body.location_name || null;
        const reported_by_user_id = req.user.id;
        const latNum = Number(lat);
        const lngNum = Number(lng);

        if (!description || typeof description !== 'string' || !description.trim()) {
          return res.status(400).json({ error: 'description alanı zorunludur.' });
        }
        if (!category || !VALID_CATEGORIES.includes(category)) {
          return res.status(400).json({
            error: `Geçersiz category değeri. Geçerli değerler: ${VALID_CATEGORIES.join(', ')}`,
          });
        }
        // '' (boş string) Number()'da 0'a düşer — bu, gerçek (0,0) koordinatıyla
        // AYIRT EDİLEMEZ bir yanlış-pozitif üretirdi (form alanı boş bırakılmış
        // ama sanki geçerli bir GPS konumu gönderilmiş gibi kabul edilirdi).
        // Bu yüzden boş/eksik değer NaN kontrolünden ÖNCE ayrıca reddedilir.
        if (lat === undefined || lat === null || lat === '' || lng === undefined || lng === null || lng === '' || Number.isNaN(latNum) || Number.isNaN(lngNum)) {
          return res.status(400).json({ error: 'lat ve lng alanları zorunludur (gerçek GPS konumu).' });
        }

        const photo_path = `/uploads/isg/${req.file.filename}`;
        const created_at = new Date().toISOString();

        // Görüntü Tabanlı Hasar Tespiti (Modül 15) — fotoğraf diske YAZILDIKTAN
        // hemen sonra, ama INSERT'ten ÖNCE çağrılır (sonuç tek bir INSERT'e
        // gömülsün diye, ayrı bir UPDATE gerekmesin). classifyImageForDamage
        // ASLA fırlatmaz — ML servisi kapalıysa cv_* alanları null döner, bu
        // İSG bildiriminin oluşturulmasını hiçbir şekilde engellemez/geciktirmez
        // (yalnızca ~15 sn'lik bir zaman aşımı sınırı içinde bekler).
        const photoBuffer = fs.readFileSync(req.file.path);
        const { cv_is_damaged, cv_damage_probability } = await classifyImageForDamage(
          photoBuffer,
          req.file.originalname,
          req.file.mimetype
        );

        const info = db
          .prepare(
            `INSERT INTO isg_reports
               (reported_by_user_id, description, category, photo_path, location_name, lat, lng, status, reviewer_note, created_at, reviewed_at, cv_is_damaged, cv_damage_probability)
             VALUES
               (@reported_by_user_id, @description, @category, @photo_path, @location_name, @lat, @lng, 'bekliyor', NULL, @created_at, NULL, @cv_is_damaged, @cv_damage_probability)`
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
            cv_is_damaged,
            cv_damage_probability,
          });

        const created = db.prepare(`${SELECT_ISG_WITH_USER} WHERE r.id = ?`).get(info.lastInsertRowid);
        res.status(201).json(mapIsgRow(created));
      } catch (err) {
        console.error(err);
        res.status(500).json({ error: 'İSG bildirimi oluşturulurken bir hata oluştu.' });
      }
    });
  });
});

// PATCH /api/isg-reports/:id/status — yalnızca dispeçer/yönetici. Bir
// bildirimi incelemek/kapatmak yönetimsel bir karar; bildiren teknisyenin
// kendisi kendi bildirimini "incelendi"/"cozuldu" yapamaz (bkz.
// routes/workOrders.js'teki requireRole desenleriyle AYNI ayrım: POST /
// (bildirim oluşturma) teknisyene açık kalır, bkz. yukarısı).
// Body: { "status": "incelendi", "reviewer_note": "..." (opsiyonel) }
router.patch('/:id/status', requireRole('dispecer', 'yonetici'), (req, res) => {
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

    const existing = db.prepare('SELECT * FROM isg_reports WHERE id = ?').get(id);
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

    // Bildirim Sistemi (Modül 6) — bildiren kullanıcıya durum güncellemesini bildir.
    if (status === 'incelendi' || status === 'cozuldu') {
      createNotification(
        existing.reported_by_user_id,
        `İSG bildiriminiz "${status}" olarak güncellendi`,
        'isg_report',
        id
      );
    }

    res.json(mapIsgRow(updated));
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'İSG bildirimi durumu güncellenirken bir hata oluştu.' });
  }
});

// PATCH /api/isg-reports/:id/verify-damage — yalnızca dispeçer/yönetici.
//
// TEST-20: Gerçek Saha Fotoğraflarından Geri Bildirim Döngüsü — bir yönetici
// bildirimi incelerken (mevcut "İncelendi/Çözüldü" akışının YANINDA, EK bir
// iş yükü değil), fotoğrafta GERÇEKTE hasar olup olmadığını işaretler. Bu,
// modelin KENDİ tahmininden (cv_is_damaged) TAMAMEN BAĞIMSIZ bir alandır —
// ikisi arasındaki fark, GET /api/ml/damage-model-performance'ın modelin
// gerçek sahada ne kadar isabetli olduğunu ölçmesini sağlar. Body:
// { "actual_damage": true|false } — bir insanın GERÇEKTE gördüğü, modelin
// tahmini DEĞİL.
router.patch('/:id/verify-damage', requireRole('dispecer', 'yonetici'), (req, res) => {
  try {
    const id = Number(req.params.id);
    if (!Number.isInteger(id)) {
      return res.status(400).json({ error: 'Geçersiz bildirim id değeri.' });
    }

    const { actual_damage } = req.body;
    if (typeof actual_damage !== 'boolean') {
      return res.status(400).json({ error: 'actual_damage alanı (true/false) zorunludur.' });
    }

    const existing = db.prepare('SELECT id FROM isg_reports WHERE id = ?').get(id);
    if (!existing) {
      return res.status(404).json({ error: 'İSG bildirimi bulunamadı.' });
    }

    db.prepare('UPDATE isg_reports SET human_verified_damage = ? WHERE id = ?').run(actual_damage ? 1 : 0, id);

    const updated = db.prepare(`${SELECT_ISG_WITH_USER} WHERE r.id = ?`).get(id);
    res.json(mapIsgRow(updated));
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'Hasar doğrulaması kaydedilirken bir hata oluştu.' });
  }
});

module.exports = router;
// AI Asistan (Modül 16) — bkz. routes/workOrders.js'teki aynı desen.
module.exports.VALID_CATEGORIES = VALID_CATEGORIES;
module.exports.VALID_STATUSES = VALID_STATUSES;
