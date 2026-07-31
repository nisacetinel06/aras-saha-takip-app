// Bildirim Sistemi (Modül 6) — ortak bildirim oluşturma fonksiyonu.
//
// Gerçek bir push (FCM vb.) altyapısı BİLİNÇLİ olarak kurulmadı: bu, bir staj
// projesi kapsamında gereksiz karmaşıklık (Firebase projesi açma, sunucu
// anahtarı yönetimi, native platform entegrasyonu) katardı. Bunun yerine bu
// fonksiyon yalnızca `notifications` tablosuna bir kayıt düşer; Flutter
// tarafı bunu periyodik olarak (30 sn) GET /api/notifications/unread-count
// ile yoklar (polling) ve artış tespit ederse flutter_local_notifications
// ile cihazda gerçek bir OS bildirimi gösterir (bkz. ARCHITECTURE.md).
//
// Üç tetikleyici nokta bu fonksiyonu çağırır: iş emri atama (routes/workOrders.js),
// İSG bildirimi inceleme (routes/isg.js) ve ekipman riskinin yükselmesi (routes/risk.js).
const db = require('../database');

const insertNotification = db.prepare(`
  INSERT INTO notifications (user_id, message, related_type, related_id, is_read, created_at)
  VALUES (@user_id, @message, @related_type, @related_id, 0, @created_at)
`);

/**
 * @param {number} userId - Bildirimin gideceği kullanıcı (users.id).
 * @param {string} message - Kullanıcıya gösterilecek Türkçe mesaj.
 * @param {'work_order'|'isg_report'|'equipment'} relatedType - İlgili kaydın türü.
 * @param {number} relatedId - İlgili kaydın id'si.
 */
function createNotification(userId, message, relatedType, relatedId) {
  insertNotification.run({
    user_id: userId,
    message,
    related_type: relatedType,
    related_id: relatedId,
    created_at: new Date().toISOString(),
  });
}

module.exports = { createNotification };
