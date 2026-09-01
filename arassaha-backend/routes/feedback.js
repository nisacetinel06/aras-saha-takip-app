// Öneri / Şikayet Kutusu (Modül 17) — İSG Bildirimi (Modül 5, bkz. routes/isg.js)
// ile BİREBİR AYNI temel desen: multer diskStorage + middleware/validateImageContent
// güvenli dosya doğrulaması, "bildiren kişi" istemciden ALINMAZ (req.user.id).
// İki gerçek fark:
//   1) Fotoğraf OPSİYONEL (İSG'de zorunluydu) — bkz. POST / altındaki not.
//   2) Anonim Gönderim: is_anonymous=1 olan kayıtlarda backend GERÇEK
//      submitted_by_user_id'yi veritabanında saklamaya devam eder (kötüye
//      kullanımı önlemek/hesap verebilirlik için — tamamen izsiz DEĞİL) ama
//      response'ta bu bilgiyi HERKESTEN (yöneticiden dahi) gizler — bkz.
//      mapFeedbackRow. Ayrıca GET /'in görünürlük filtresi ve GET /:id'nin
//      sahiplik kontrolü SEC-02 IDOR dersiyle tutarlı uygulanır (bkz.
//      routes/sosAlerts.js GET / ve utils/workOrderAccess.js AYNI ilke).
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const express = require('express');
const multer = require('multer');
const db = require('../database');
const { requireRole } = require('../middleware/auth');
const validateImageContent = require('../middleware/validateImageContent');
const { createNotification } = require('../utils/notify');

const router = express.Router();

const VALID_CATEGORIES = ['oneri', 'sikayet', 'diger'];
const VALID_STATUSES = ['bekliyor', 'incelendi', 'kapatildi'];

const FEEDBACK_UPLOADS_DIR = path.join(__dirname, '..', 'uploads', 'feedback');

// isg.js'teki storage/upload tanımıyla AYNI desen — yalnızca hedef klasör
// farklı (kendi alt klasörüne yazılır, bkz. server.js mkdirSync ve
// routes/uploads.js whitelist).
const storage = multer.diskStorage({
  destination: (req, file, cb) => cb(null, FEEDBACK_UPLOADS_DIR),
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

// submitted_by/reviewed_by kullanıcı bilgisini gömen ortak SELECT — isg.js'teki
// SELECT_ISG_WITH_USER ile aynı JOIN deseni, iki kullanıcıya (gönderen +
// inceleyen) genişletildi.
const SELECT_FEEDBACK_WITH_USERS = `
  SELECT
    f.*,
    su.id AS submitted_by_id_join,
    su.name AS submitted_by_name,
    su.role AS submitted_by_role,
    ru.id AS reviewed_by_id_join,
    ru.name AS reviewed_by_name,
    ru.role AS reviewed_by_role
  FROM feedback_items f
  LEFT JOIN users su ON su.id = f.submitted_by_user_id
  LEFT JOIN users ru ON ru.id = f.reviewed_by_user_id
`;

// Anonim Gönderim dengesi — bkz. dosya başı notu: `submitted_by_user_id` HAM
// hâliyle response'a ASLA yansımaz (yalnızca DB'de, hesap verebilirlik için
// tutulur); istemci her zaman ya dolu bir `submitted_by` nesnesi ya da
// (anonimse) `null` görür.
function mapFeedbackRow(row) {
  const {
    submitted_by_user_id,
    submitted_by_id_join,
    submitted_by_name,
    submitted_by_role,
    reviewed_by_user_id,
    reviewed_by_id_join,
    reviewed_by_name,
    reviewed_by_role,
    is_anonymous,
    ...rest
  } = row;

  return {
    ...rest,
    is_anonymous: !!is_anonymous,
    submitted_by: is_anonymous
      ? null
      : submitted_by_id_join
        ? { id: submitted_by_id_join, name: submitted_by_name, role: submitted_by_role }
        : null,
    reviewed_by: reviewed_by_id_join
      ? { id: reviewed_by_id_join, name: reviewed_by_name, role: reviewed_by_role }
      : null,
  };
}

// GET /api/feedback?status=bekliyor — teknisyen/dispeçer SADECE KENDİ
// gönderdiklerini görür, yönetici HEPSİNİ görür. Modül 1'deki iş emri
// görünürlük deseniyle (routes/workOrders.js) aynı ilke, SEC-02 IDOR dersiyle
// tutarlı (bkz. routes/sosAlerts.js GET / AYNI yorum).
router.get('/', (req, res) => {
  try {
    const { status } = req.query;
    if (status && !VALID_STATUSES.includes(status)) {
      return res.status(400).json({
        error: `Geçersiz status değeri. Geçerli değerler: ${VALID_STATUSES.join(', ')}`,
      });
    }

    const isOwnView = req.user.role !== 'yonetici';
    const whereClauses = [];
    const params = [];
    if (isOwnView) {
      whereClauses.push('f.submitted_by_user_id = ?');
      params.push(req.user.id);
    }
    if (status) {
      whereClauses.push('f.status = ?');
      params.push(status);
    }
    const whereSql = whereClauses.length ? `WHERE ${whereClauses.join(' AND ')}` : '';

    const rows = db
      .prepare(`${SELECT_FEEDBACK_WITH_USERS} ${whereSql} ORDER BY f.created_at DESC`)
      .all(...params);

    res.json(rows.map(mapFeedbackRow));
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'Öneri/şikayet bildirimleri listelenirken bir hata oluştu.' });
  }
});

// GET /api/feedback/:id — sahiplik kontrolü: kendi kaydı veya yönetici.
// SEC-02: sahip olmayan bir kullanıcı 403 DEĞİL 404 alır — kaydın VARLIĞINI
// bile açık etmemek için (ID enumeration'a karşı savunma, bkz.
// utils/workOrderAccess.js dosya başı notu AYNI ilke).
router.get('/:id', (req, res) => {
  try {
    const id = Number(req.params.id);
    if (!Number.isInteger(id)) {
      return res.status(400).json({ error: 'Geçersiz bildirim id değeri.' });
    }

    const row = db.prepare(`${SELECT_FEEDBACK_WITH_USERS} WHERE f.id = ?`).get(id);
    if (!row) {
      return res.status(404).json({ error: 'Bildirim bulunamadı.' });
    }

    const isOwner = row.submitted_by_user_id === req.user.id;
    const isYonetici = req.user.role === 'yonetici';
    if (!isOwner && !isYonetici) {
      return res.status(404).json({ error: 'Bildirim bulunamadı.' });
    }

    res.json(mapFeedbackRow(row));
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'Bildirim detayı alınırken bir hata oluştu.' });
  }
});

// POST /api/feedback — giriş yapmış HERKES. multipart/form-data — alanlar:
// description, category, is_anonymous (opsiyonel, 'true'/'false'), photo
// (dosya, OPSİYONEL — İSG'nin aksine zorunlu değil). submitted_by_user_id
// istemciden ALINMAZ (bkz. routes/isg.js AYNI mass-assignment savunması).
router.post('/', (req, res) => {
  upload.single('photo')(req, res, (uploadErr) => {
    if (uploadErr) {
      return res.status(400).json({ error: uploadErr.message || 'Fotoğraf yüklenirken bir hata oluştu.' });
    }

    const createFeedbackItem = (photo_path) => {
      try {
        const { description, category } = req.body;
        const is_anonymous = req.body.is_anonymous === 'true' || req.body.is_anonymous === true;
        const submitted_by_user_id = req.user.id;

        if (!description || typeof description !== 'string' || !description.trim()) {
          return res.status(400).json({ error: 'description alanı zorunludur.' });
        }
        if (!category || !VALID_CATEGORIES.includes(category)) {
          return res.status(400).json({
            error: `Geçersiz category değeri. Geçerli değerler: ${VALID_CATEGORIES.join(', ')}`,
          });
        }

        const created_at = new Date().toISOString();

        const info = db
          .prepare(
            `INSERT INTO feedback_items
               (submitted_by_user_id, category, description, photo_path, is_anonymous, status, reviewer_note, reviewed_by_user_id, created_at, reviewed_at)
             VALUES
               (@submitted_by_user_id, @category, @description, @photo_path, @is_anonymous, 'bekliyor', NULL, NULL, @created_at, NULL)`
          )
          .run({
            submitted_by_user_id,
            category,
            description: description.trim(),
            photo_path,
            is_anonymous: is_anonymous ? 1 : 0,
            created_at,
          });

        const created = db.prepare(`${SELECT_FEEDBACK_WITH_USERS} WHERE f.id = ?`).get(info.lastInsertRowid);
        res.status(201).json(mapFeedbackRow(created));
      } catch (err) {
        console.error(err);
        res.status(500).json({ error: 'Bildirim oluşturulurken bir hata oluştu.' });
      }
    };

    // Fotoğraf yoksa (opsiyonel alan boş bırakılmış) doğrudan devam edilir —
    // İSG'nin aksine `req.file` zorunlu değildir.
    if (!req.file) {
      return createFeedbackItem(null);
    }

    // Dosya İÇERİĞİ (magic number) doğrulaması — bkz. routes/isg.js AYNI katman.
    validateImageContent(req, res, () => {
      const photo_path = `/uploads/feedback/${req.file.filename}`;
      createFeedbackItem(photo_path);
    });
  });
});

// PATCH /api/feedback/:id/status — yalnızca dispeçer/yönetici. Bir bildirimi
// incelemek/kapatmak yönetimsel bir karar; bildiren kişinin kendisi kendi
// bildirimini "incelendi"/"kapatildi" yapamaz (bkz. routes/isg.js AYNI ayrım).
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

    const existing = db.prepare('SELECT * FROM feedback_items WHERE id = ?').get(id);
    if (!existing) {
      return res.status(404).json({ error: 'Bildirim bulunamadı.' });
    }

    // 'bekliyor' dışına her geçişte inceleyen kişi + zaman damgalanır — bkz.
    // routes/isg.js reviewed_at ile AYNI ilke, burada AYRICA reviewed_by_user_id
    // (isg_reports'ta olmayan yeni bir alan) da kaydedilir.
    const reviewed_at = status === 'bekliyor' ? null : new Date().toISOString();
    const reviewed_by_user_id = status === 'bekliyor' ? null : req.user.id;

    db.prepare(
      'UPDATE feedback_items SET status = ?, reviewer_note = ?, reviewed_by_user_id = ?, reviewed_at = ? WHERE id = ?'
    ).run(status, reviewer_note || null, reviewed_by_user_id, reviewed_at, id);

    const updated = db.prepare(`${SELECT_FEEDBACK_WITH_USERS} WHERE f.id = ?`).get(id);

    // Bildirim Sistemi (Modül 6) — bildiren kullanıcıya durum güncellemesini
    // bildir. Anonim bir bildirimde bile bu bildirim GÖNDERİLİR: bildirim
    // sistemi backend'in gerçekte bildiği submitted_by_user_id'yi kullanır
    // (bkz. dosya başı "izsiz DEĞİL" notu) — anonimlik yalnızca yöneticiye
    // gösterilen response'ta uygulanır, bildiren kişinin KENDİ bildirim
    // kutusu bu ayrımdan etkilenmez.
    if (status === 'incelendi' || status === 'kapatildi') {
      createNotification(
        existing.submitted_by_user_id,
        `Öneri/şikayet bildiriminiz "${status}" olarak güncellendi`,
        'feedback_item',
        id
      );
    }

    res.json(mapFeedbackRow(updated));
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'Bildirim durumu güncellenirken bir hata oluştu.' });
  }
});

module.exports = router;
module.exports.VALID_CATEGORIES = VALID_CATEGORIES;
module.exports.VALID_STATUSES = VALID_STATUSES;
