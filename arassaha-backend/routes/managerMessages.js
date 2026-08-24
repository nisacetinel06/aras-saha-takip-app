// Yöneticiden Çalışana Duyuru/Mesaj Sistemi.
//
// TEK YÖNLÜ yayın: yalnızca yönetici mesaj oluşturup bir/birden çok çalışana
// gönderir; çalışan SADECE okur, okundu zamanı işaretlenir, cevap YAZAMAZ.
// Önceki iki-yönlü "sohbet" tasarımından (conversations/conversation_participants)
// KASITLI olarak farklı — bkz. database.js manager_messages/manager_message_recipients
// tablo yorumları. Teknisyen/dispeçer için mesaj OLUŞTURMA endpoint'i YOK.
const express = require('express');
const db = require('../database');
const { requireRole } = require('../middleware/auth');
const { createNotification } = require('../utils/notify');

const router = express.Router();

// GET /api/manager-messages — giriş yapmış herkes, KENDİSİNİN ALICI OLDUĞU
// mesajları listeler. Sorgu zaten `WHERE mmr.recipient_user_id = ?` ile doğal
// bir sahiplik filtresi taşıyor (bkz. routes/notifications.js AYNI desen,
// SEC-02 IDOR dersiyle tutarlı) — bir kullanıcı asla kendisine gönderilmemiş
// bir mesajı bu endpoint'ten göremez.
router.get('/', (req, res) => {
  try {
    const rows = db
      .prepare(
        `
        SELECT mm.id, mm.title, mm.content, mm.created_at, mmr.read_at,
               u.name AS sender_name, u.role AS sender_role
        FROM manager_message_recipients mmr
        JOIN manager_messages mm ON mm.id = mmr.message_id
        JOIN users u ON u.id = mm.sender_user_id
        WHERE mmr.recipient_user_id = ?
        ORDER BY mm.created_at DESC
      `
      )
      .all(req.user.id);

    res.json(rows.map((row) => ({ ...row, is_read: row.read_at !== null })));
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'Mesajlar listelenirken bir hata oluştu.' });
  }
});

// GET /api/manager-messages/sent — yalnızca yönetici, KENDİ gönderdiği
// mesajları, her biri için toplam/okunmuş alıcı sayısıyla listeler. Başka bir
// yöneticinin gönderdiği mesajlar burada GÖRÜNMEZ (sender_user_id = ? filtresi).
router.get('/sent', requireRole('yonetici'), (req, res) => {
  try {
    const rows = db
      .prepare(
        `
        SELECT
          mm.id, mm.title, mm.content, mm.created_at,
          COUNT(mmr.id) AS recipient_count,
          SUM(CASE WHEN mmr.read_at IS NOT NULL THEN 1 ELSE 0 END) AS read_count
        FROM manager_messages mm
        LEFT JOIN manager_message_recipients mmr ON mmr.message_id = mm.id
        WHERE mm.sender_user_id = ?
        GROUP BY mm.id
        ORDER BY mm.created_at DESC
      `
      )
      .all(req.user.id);

    res.json(
      rows.map((row) => ({
        ...row,
        recipient_count: Number(row.recipient_count),
        read_count: Number(row.read_count),
      }))
    );
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'Gönderilen mesajlar listelenirken bir hata oluştu.' });
  }
});

// GET /api/manager-messages/:id/read-status — SADECE o mesajı gönderen
// yönetici. requireRole('yonetici') rol katmanını kapatır; mesaj SAHİPLİĞİ
// ayrıca aşağıda kontrol edilir — bir yönetici BAŞKA bir yöneticinin
// mesajının okundu takibini göremez. 404 ile (var olmayan bir kayıt gibi)
// reddedilir — SEC-02 IDOR dersiyle tutarlı, kaydın varlığını bile açık etmeyen yaklaşım.
router.get('/:id/read-status', requireRole('yonetici'), (req, res) => {
  try {
    const id = Number(req.params.id);
    if (!Number.isInteger(id)) {
      return res.status(400).json({ error: 'Geçersiz mesaj id değeri.' });
    }

    const message = db.prepare('SELECT * FROM manager_messages WHERE id = ?').get(id);
    if (!message || message.sender_user_id !== req.user.id) {
      return res.status(404).json({ error: 'Mesaj bulunamadı.' });
    }

    const recipients = db
      .prepare(
        `
        SELECT mmr.recipient_user_id, u.name, u.role, mmr.read_at
        FROM manager_message_recipients mmr
        JOIN users u ON u.id = mmr.recipient_user_id
        WHERE mmr.message_id = ?
        ORDER BY (mmr.read_at IS NULL) DESC, u.name
      `
      )
      .all(id);

    res.json({
      id: message.id,
      title: message.title,
      content: message.content,
      created_at: message.created_at,
      recipients,
    });
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'Okundu bilgisi alınırken bir hata oluştu.' });
  }
});

// POST /api/manager-messages — SADECE yönetici (KRİTİK — yazma yetkisi
// burada dışında hiçbir yerde yok: teknisyen/dispeçer için mesaj oluşturma
// endpoint'i BİLEREK yok, bu özellik tek yönlü).
// Body: { title?, content, recipient_user_ids: number[] }
router.post('/', requireRole('yonetici'), (req, res) => {
  try {
    const { title, content, recipient_user_ids } = req.body;

    if (!content || typeof content !== 'string' || !content.trim()) {
      return res.status(400).json({ error: 'content alanı zorunludur.' });
    }
    if (!Array.isArray(recipient_user_ids) || recipient_user_ids.length === 0) {
      return res.status(400).json({ error: 'En az bir alıcı seçilmelidir.' });
    }

    const uniqueRecipientIds = [...new Set(recipient_user_ids.map(Number))];
    if (uniqueRecipientIds.some((id) => !Number.isInteger(id))) {
      return res.status(400).json({ error: 'Geçersiz alıcı id değeri.' });
    }

    // Alıcıların GERÇEKTEN var olan, aktif kullanıcılar olduğu doğrulanır —
    // aksi halde recipient_user_id FOREIGN KEY hatasıyla 500'e düşerdi ya da
    // (daha kötüsü) pasif/silinmiş bir kullanıcıya sessizce "gönderilmiş" gibi
    // görünürdü.
    const placeholders = uniqueRecipientIds.map(() => '?').join(', ');
    const existingRecipients = db
      .prepare(`SELECT id FROM users WHERE id IN (${placeholders}) AND is_active = 1`)
      .all(...uniqueRecipientIds);
    if (existingRecipients.length !== uniqueRecipientIds.length) {
      return res.status(400).json({ error: 'Alıcılardan biri veya birden fazlası geçerli/aktif bir kullanıcı değil.' });
    }

    const created_at = new Date().toISOString();
    const trimmedTitle = title && String(title).trim() ? String(title).trim() : null;
    const trimmedContent = content.trim();

    const info = db
      .prepare('INSERT INTO manager_messages (sender_user_id, title, content, created_at) VALUES (?, ?, ?, ?)')
      .run(req.user.id, trimmedTitle, trimmedContent, created_at);
    const messageId = info.lastInsertRowid;

    const insertRecipient = db.prepare(
      'INSERT INTO manager_message_recipients (message_id, recipient_user_id, read_at) VALUES (?, ?, NULL)'
    );
    for (const recipientId of uniqueRecipientIds) {
      insertRecipient.run(messageId, recipientId);
      // Bildirim Sistemi (Modül 6) — yeniden kullanılıyor, yeni bir bildirim
      // altyapısı KURULMUYOR (bkz. utils/notify.js).
      createNotification(
        recipientId,
        `Yöneticinizden yeni bir mesaj: ${trimmedTitle || trimmedContent.substring(0, 40)}`,
        'manager_message',
        messageId
      );
    }

    res.status(201).json({ id: messageId, recipient_count: uniqueRecipientIds.length });
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'Mesaj gönderilirken bir hata oluştu.' });
  }
});

// PATCH /api/manager-messages/:id/read — SADECE o mesajın alıcısı olan
// kullanıcı. Sahiplik SQL sorgusunun kendisinde (message_id + recipient_user_id
// eşleşmesi) doğrulanır — recipient satırı yoksa (bu kullanıcı bu mesajın
// alıcısı değilse) 404 döner, bkz. PROMPT'taki örnek AYNI desen.
router.patch('/:id/read', (req, res) => {
  try {
    const id = Number(req.params.id);
    if (!Number.isInteger(id)) {
      return res.status(400).json({ error: 'Geçersiz mesaj id değeri.' });
    }

    const recipient = db
      .prepare('SELECT * FROM manager_message_recipients WHERE message_id = ? AND recipient_user_id = ?')
      .get(id, req.user.id);
    if (!recipient) {
      return res.status(404).json({ error: 'Mesaj bulunamadı.' });
    }

    // Zaten okunmuşsa read_at'i EZMEZ — ilk okuma zamanı korunur (yönetici
    // "gerçekten ne zaman okudu"yu görsün diye).
    if (!recipient.read_at) {
      db.prepare('UPDATE manager_message_recipients SET read_at = ? WHERE id = ?').run(
        new Date().toISOString(),
        recipient.id
      );
    }

    res.json({ success: true });
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'Mesaj okundu olarak işaretlenirken bir hata oluştu.' });
  }
});

module.exports = router;
