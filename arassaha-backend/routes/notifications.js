// Bildirim Sistemi (Modül 6) — bkz. utils/notify.js (oluşturma) ve
// ARCHITECTURE.md (genel mimari: event-driven kayıt + Flutter tarafında
// polling + yerel bildirim).
//
// Tüm endpoint'ler yalnızca req.user.id'ye ait bildirimleri döner/günceller —
// bir kullanıcı başka birinin bildirimini asla göremez/okuyamaz (server.js'te
// zaten verifyToken ile korunuyor, burada ayrıca WHERE user_id = ? ile de
// zorunlu kılınıyor).
const express = require('express');
const db = require('../database');

const router = express.Router();

// GET /api/notifications?unread_only=true
router.get('/', (req, res) => {
  try {
    const unreadOnly = req.query.unread_only === 'true';
    const rows = unreadOnly
      ? db
          .prepare('SELECT * FROM notifications WHERE user_id = ? AND is_read = 0 ORDER BY created_at DESC')
          .all(req.user.id)
      : db
          .prepare('SELECT * FROM notifications WHERE user_id = ? ORDER BY created_at DESC')
          .all(req.user.id);

    res.json(rows.map((row) => ({ ...row, is_read: Boolean(row.is_read) })));
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'Bildirimler listelenirken bir hata oluştu.' });
  }
});

// GET /api/notifications/unread-count
// Polling için hafif bir endpoint — tam listeyi çekmeye gerek yok, Flutter
// tarafı her 30 saniyede bir yalnızca bu sayıyı sorgular.
router.get('/unread-count', (req, res) => {
  try {
    const row = db
      .prepare('SELECT COUNT(*) AS count FROM notifications WHERE user_id = ? AND is_read = 0')
      .get(req.user.id);
    res.json({ count: row.count });
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'Okunmamış bildirim sayısı alınırken bir hata oluştu.' });
  }
});

// PATCH /api/notifications/:id/read
router.patch('/:id/read', (req, res) => {
  try {
    const id = Number(req.params.id);
    if (!Number.isInteger(id)) {
      return res.status(400).json({ error: 'Geçersiz bildirim id değeri.' });
    }

    const existing = db.prepare('SELECT * FROM notifications WHERE id = ? AND user_id = ?').get(id, req.user.id);
    if (!existing) {
      return res.status(404).json({ error: 'Bildirim bulunamadı.' });
    }

    db.prepare('UPDATE notifications SET is_read = 1 WHERE id = ?').run(id);

    const updated = db.prepare('SELECT * FROM notifications WHERE id = ?').get(id);
    res.json({ ...updated, is_read: Boolean(updated.is_read) });
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'Bildirim okundu olarak işaretlenirken bir hata oluştu.' });
  }
});

// PATCH /api/notifications/mark-all-read
router.patch('/mark-all-read', (req, res) => {
  try {
    db.prepare('UPDATE notifications SET is_read = 1 WHERE user_id = ? AND is_read = 0').run(req.user.id);
    res.json({ success: true });
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'Bildirimler okundu olarak işaretlenirken bir hata oluştu.' });
  }
});

module.exports = router;
