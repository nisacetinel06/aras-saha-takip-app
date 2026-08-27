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
// istisnasıdır — yalnızca gerçek bir acil durum bildirimine bağlı olarak
// ("ilgili teknisyeni doğrudan aramak" ihtiyacı için). GET / artık teknisyene
// de açık olsa da (bkz. aşağıdaki handler), teknisyen bu alanları YALNIZCA
// KENDİ bildirimlerinde (dolayısıyla kendi adı/telefonunda) görür — başka bir
// kullanıcının telefon numarasına ASLA erişemez; dispeçer/yönetici ise zaten
// üst düzey erişimiyle TÜM bildirimlerdeki bu alanları görür.
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

  // Sık tekrarlanan SOS FARKINDALIĞI — ENGELLEME DEĞİL. Aynı kullanıcıdan
  // son 10 dakikada (bu bildirim DAHİL) 5'ten fazla SOS geldiyse yalnızca
  // is_frequent_pattern=1 işaretlenir ve dispeçer/yöneticiye giden bildirim
  // mesajına bir uyarı notu eklenir — bildirim HER ZAMAN, koşulsuz olarak
  // gönderilir. Gerçek bir acil durumda kullanıcı art arda birkaç kez SOS
  // göndermek zorunda kalabilir (ilk bildirim onaylanmadı, durum kötüleşti
  // vb.); bunu bir rate limit ile reddetmek hayati bir özellikte YANLIŞ
  // taraf olurdu (bkz. database.js sos_alerts is_frequent_pattern migrasyon
  // yorumu, login rate limit'in BİLEREK AKSİ).
  // ISO 8601 string'ler ('...T...Z') SQLite'ın datetime('now', ...) çıktısıyla
  // ('YYYY-MM-DD HH:MM:SS', boşluklu) DOĞRUDAN string karşılaştırılamaz — 'T'
  // karakteri (0x54) boşluktan (0x20) BÜYÜK olduğu için `created_at >
  // datetime('now', '-10 minutes')` her zaman true dönerdi (aynı gün içindeki
  // TÜM kayıtlar "son 10 dakika" sayılırdı, saat farkı hiç etkilemezdi).
  // Bunun yerine eşik de aynı ISO formatında hesaplanıp string-string
  // karşılaştırılır.
  const tenMinutesAgoIso = new Date(Date.now() - 10 * 60 * 1000).toISOString();
  const recentCount = db
    .prepare(`SELECT COUNT(*) AS count FROM sos_alerts WHERE triggered_by_user_id = ? AND created_at > ?`)
    .get(req.user.id, tenMinutesAgoIso).count;
  const isFrequentPattern = recentCount > 5;
  if (isFrequentPattern) {
    db.prepare('UPDATE sos_alerts SET is_frequent_pattern = 1 WHERE id = ?').run(result.lastInsertRowid);
  }

  // Bildirim Sistemi (Modül 6'nın altyapısı) — yeniden kullanılıyor, yeni bir
  // bildirim altyapısı KURULMUYOR (bkz. utils/notify.js). TÜM aktif
  // dispeçer/yönetici'ye anında bildirim oluşturulur.
  const reporter = db.prepare('SELECT name FROM users WHERE id = ?').get(req.user.id);
  const managers = db
    .prepare(`SELECT id FROM users WHERE role IN ('dispecer', 'yonetici') AND is_active = 1`)
    .all();
  const alertMessage = isFrequentPattern
    ? `🚨 ACİL DURUM: ${reporter ? reporter.name : 'Bir çalışan'} yardım istiyor! ⚠️ Bu kullanıcıdan son 10 dakikada birden fazla SOS bildirimi geldi`
    : `🚨 ACİL DURUM: ${reporter ? reporter.name : 'Bir çalışan'} yardım istiyor!`;
  for (const manager of managers) {
    createNotification(manager.id, alertMessage, 'sos_alert', result.lastInsertRowid);
  }

  res.status(201).json({ id: result.lastInsertRowid, created_at, is_frequent_pattern: isFrequentPattern });
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

// GET /api/sos-alerts — giriş yapmış HERKES, ama görünürlük role göre ayrılır:
// teknisyen SADECE KENDİ gönderdiği bildirimleri görür (gönderdiği SOS'un
// dispeçer/yönetici tarafından görülüp görülmediğini/onaylanıp onaylanmadığını
// takip edebilsin diye), dispeçer/yönetici TÜM bildirimleri görür (önceki
// davranış korunur). Modül 1'deki iş emri görünürlük deseniyle (routes/
// workOrders.js GET / — teknisyen yalnızca kendi işlerini görür) BİREBİR
// TUTARLI, bkz. SEC-02 IDOR dersi. Veri seti küçük olduğu için aktif/kapatıldı
// ayrımı istemci tarafında filtrelenir (bkz. screens/map/map_screen.dart AYNI
// "küçük veri seti -> istemci tarafı filtre" ilkesi).
router.get('/', (req, res) => {
  try {
    const isOwnView = req.user.role === 'teknisyen';
    const rows = isOwnView
      ? db
          .prepare(
            `SELECT ${LIST_FIELDS} FROM sos_alerts sa
             JOIN users u ON u.id = sa.triggered_by_user_id
             WHERE sa.triggered_by_user_id = ?
             ORDER BY sa.created_at DESC
             LIMIT 200`
          )
          .all(req.user.id)
      : db
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
