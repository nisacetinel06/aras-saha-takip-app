// Bildirim Sistemi (Modül 6) — ortak bildirim oluşturma fonksiyonu.
//
// `notifications` tablosuna bir kayıt düşer (Flutter tarafı bunu Bildirimler
// ekranında ve periyodik polling ile GET /api/notifications/unread-count
// üzerinden okur, bkz. ARCHITECTURE.md) VE ayrıca kullanıcının kayıtlı bir
// FCM token'ı varsa gerçek bir push bildirimi gönderir (bkz.
// services/pushNotificationService.js). Polling BİLEREK KALDIRILMADI —
// push bildirimi başarısız olursa (token yok, cihaz kapalı, teslimat sorunu)
// kullanıcı uygulamayı açtığında hâlâ unread-count ile eksik kalan
// bildirimleri yakalar; iki sistem çelişkili değil, tamamlayıcıdır.
//
// TÜM tetikleyici noktalar (iş emri atama, İSG bildirimi inceleme, ekipman
// risk yükselişi, düşük stok, SOS bildirimi, yönetici mesajı — bkz.
// routes/workOrders.js, isg.js, risk.js, anomaly.js, materials.js,
// maintenance.js, sosAlerts.js, managerMessages.js) bu TEK fonksiyonu
// çağırır; push bildirimi bu yüzden hiçbirine AYRI AYRI dokunulmadan
// eklendi.
const db = require('../database');
const { sendPushNotification } = require('../services/pushNotificationService');

const insertNotification = db.prepare(`
  INSERT INTO notifications (user_id, message, related_type, related_id, is_read, created_at)
  VALUES (@user_id, @message, @related_type, @related_id, 0, @created_at)
`);

const getFcmToken = db.prepare('SELECT fcm_token FROM users WHERE id = ?');

/**
 * @param {number} userId - Bildirimin gideceği kullanıcı (users.id).
 * @param {string} message - Kullanıcıya gösterilecek Türkçe mesaj.
 * @param {'work_order'|'isg_report'|'equipment'|'material'|'manager_message'|'sos_alert'} relatedType - İlgili kaydın türü.
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

  // Push gönderimi kasıtlı olarak `await` EDİLMEZ (sendPushNotification
  // kendi try/catch'i içinde hatasını zaten yutar/loglar, bkz. o dosya) —
  // createNotification'ı çağıran TÜM route handler'lar senkron çalışıyor
  // (better-sqlite3), bu fonksiyonu async yapıp her çağrı noktasını
  // değiştirmek gereksiz bir kapsam genişlemesi olurdu.
  const user = getFcmToken.get(userId);
  if (user && user.fcm_token) {
    const title = relatedType === 'sos_alert' ? '🚨 ACİL DURUM' : 'ArasSaha';
    sendPushNotification(user.fcm_token, title, message, {
      type: relatedType,
      related_id: String(relatedId),
    });
  }
}

module.exports = { createNotification };
