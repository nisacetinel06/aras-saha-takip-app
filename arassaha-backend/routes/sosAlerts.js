// Acil Durum / SOS Bildirimi Modülü.
//
// Sahada çalışan bir teknisyenin TEK dokunuşla mevcut konumunu ve bir acil
// durum bildirimini dispeçer/yöneticilere göndermesi içindir. Diğer
// modüllerin AKSİNE burada HIZ birincil önceliktir: POST / kasıtlı olarak
// minimal tutulur, hiçbir gereksiz doğrulama/adım eklenmez (bkz. database.js
// sos_alerts tablo yorumu).
const express = require('express');
const db = require('../database');
const { requireRole } = require('../middleware/auth');
const { createNotification } = require('../utils/notify');

const router = express.Router();

// SOS Uyarıları ekranının (Flutter) TEK bir listeleme isteğiyle "kimden, ne
// zaman, konum, telefon" bilgisini birlikte alabilmesi için triggered_by
// kullanıcısının ad+telefonu JOIN ile eklenir. Bu, routes/users.js'teki genel
// PICKER_FIELDS'in (telefon İÇERMEYEN) BİLİNÇLİ DIŞINDA, dar bir güvenlik
// istisnasıdır — yalnızca requireRole ile zaten üst düzey erişimi olan
// dispeçer/yönetici görür, ve yalnızca gerçek bir acil durum bildirimine
// bağlı olarak ("ilgili teknisyeni doğrudan aramak" ihtiyacı için).
const LIST_FIELDS = `
  sa.id, sa.lat, sa.lng, sa.note, sa.status, sa.created_at,
  sa.acknowledged_by_user_id, sa.acknowledged_at,
  sa.closed_by_user_id, sa.closed_note, sa.closed_at,
  sa.triggered_by_user_id, u.name AS triggered_by_name, u.phone AS triggered_by_phone
`;

// POST /api/sos-alerts — giriş yapmış HERKES. Body: { lat, lng } (ikisi de
// zorunlu, number). BİLİNÇLİ OLARAK MİNİMAL: not/başka hiçbir alan istenmez,
// requireRole YOK (her rol acil durum bildirebilmeli) — isteğin en hızlı
// şekilde işlenmesi amaçlanır.
router.post('/', (req, res) => {
  const { lat, lng } = req.body;
  if (typeof lat !== 'number' || typeof lng !== 'number') {
    return res.status(400).json({ error: 'Konum bilgisi (lat, lng) gerekli.' });
  }

  const created_at = new Date().toISOString();
  const result = db
    .prepare(
      `INSERT INTO sos_alerts (triggered_by_user_id, lat, lng, status, created_at)
       VALUES (?, ?, ?, 'aktif', ?)`
    )
    .run(req.user.id, lat, lng, created_at);

  // Bildirim Sistemi (Modül 6'nın altyapısı) — yeniden kullanılıyor, yeni bir
  // bildirim altyapısı KURULMUYOR (bkz. utils/notify.js). TÜM aktif
  // dispeçer/yönetici'ye anında bildirim oluşturulur.
  const reporter = db.prepare('SELECT name FROM users WHERE id = ?').get(req.user.id);
  const managers = db
    .prepare(`SELECT id FROM users WHERE role IN ('dispecer', 'yonetici') AND is_active = 1`)
    .all();
  for (const manager of managers) {
    createNotification(
      manager.id,
      `🚨 ACİL DURUM: ${reporter ? reporter.name : 'Bir çalışan'} yardım istiyor!`,
      'sos_alert',
      result.lastInsertRowid
    );
  }

  res.status(201).json({ id: result.lastInsertRowid, created_at });
});

// PATCH /api/sos-alerts/:id/note — SADECE bildirimi oluşturan kullanıcı,
// sonradan opsiyonel bir not ekler. Hız için ilk bildirimden BİLEREK AYRI bir
// endpoint. Sahiplik SQL sorgusunun kendisinde kontrol edilir — bu kullanıcı
// bildirimin sahibi değilse 404 döner (bkz. routes/managerMessages.js AYNI
// SEC-02 IDOR deseni, kaydın varlığını bile açık etmez).
router.patch('/:id/note', (req, res) => {
  try {
    const id = Number(req.params.id);
    if (!Number.isInteger(id)) {
      return res.status(400).json({ error: 'Geçersiz bildirim id değeri.' });
    }

    const { note } = req.body;
    if (typeof note !== 'string' || !note.trim()) {
      return res.status(400).json({ error: 'note alanı zorunludur.' });
    }

    const alert = db
      .prepare('SELECT id FROM sos_alerts WHERE id = ? AND triggered_by_user_id = ?')
      .get(id, req.user.id);
    if (!alert) {
      return res.status(404).json({ error: 'Bildirim bulunamadı.' });
    }

    db.prepare('UPDATE sos_alerts SET note = ? WHERE id = ?').run(note.trim(), id);
    res.json({ success: true });
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'Not eklenirken bir hata oluştu.' });
  }
});

// GET /api/sos-alerts — SADECE dispeçer/yönetici. Tüm bildirimleri (en
// yeniden en eskiye) listeler; veri seti küçük olduğu için aktif/kapatıldı
// ayrımı istemci tarafında filtrelenir (bkz. screens/map/map_screen.dart
// AYNI "küçük veri seti -> istemci tarafı filtre" ilkesi).
router.get('/', requireRole('dispecer', 'yonetici'), (req, res) => {
  try {
    const rows = db
      .prepare(
        `SELECT ${LIST_FIELDS} FROM sos_alerts sa
         JOIN users u ON u.id = sa.triggered_by_user_id
         ORDER BY sa.created_at DESC
         LIMIT 200`
      )
      .all();
    res.json(rows);
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'SOS bildirimleri listelenirken bir hata oluştu.' });
  }
});

// PATCH /api/sos-alerts/:id/acknowledge — SADECE dispeçer/yönetici.
// "Gördüm, ilgileniyorum" işaretlemesi — durumu 'onaylandi' yapar.
router.patch('/:id/acknowledge', requireRole('dispecer', 'yonetici'), (req, res) => {
  try {
    const id = Number(req.params.id);
    if (!Number.isInteger(id)) {
      return res.status(400).json({ error: 'Geçersiz bildirim id değeri.' });
    }

    const alert = db.prepare('SELECT id FROM sos_alerts WHERE id = ?').get(id);
    if (!alert) {
      return res.status(404).json({ error: 'Bildirim bulunamadı.' });
    }

    db.prepare(
      `UPDATE sos_alerts SET status = 'onaylandi', acknowledged_by_user_id = ?, acknowledged_at = ? WHERE id = ?`
    ).run(req.user.id, new Date().toISOString(), id);

    res.json({ success: true });
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'Bildirim onaylanırken bir hata oluştu.' });
  }
});

// PATCH /api/sos-alerts/:id/close — SADECE dispeçer/yönetici. Body: { closed_note? }
router.patch('/:id/close', requireRole('dispecer', 'yonetici'), (req, res) => {
  try {
    const id = Number(req.params.id);
    if (!Number.isInteger(id)) {
      return res.status(400).json({ error: 'Geçersiz bildirim id değeri.' });
    }

    const alert = db.prepare('SELECT id FROM sos_alerts WHERE id = ?').get(id);
    if (!alert) {
      return res.status(404).json({ error: 'Bildirim bulunamadı.' });
    }

    const { closed_note } = req.body;
    db.prepare(
      `UPDATE sos_alerts SET status = 'kapatildi', closed_by_user_id = ?, closed_note = ?, closed_at = ? WHERE id = ?`
    ).run(
      req.user.id,
      closed_note && String(closed_note).trim() ? String(closed_note).trim() : null,
      new Date().toISOString(),
      id
    );

    res.json({ success: true });
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'Bildirim kapatılırken bir hata oluştu.' });
  }
});

module.exports = router;
