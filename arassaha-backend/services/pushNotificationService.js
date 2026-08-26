// Push Bildirim (FCM) Servisi — bkz. utils/notify.js (TEK çağrı noktası),
// services/local_notification_service.dart / push_notification_service.dart
// (Flutter tarafı). Modül 6'da BİLİNÇLİ olarak ertelenen gerçek push
// altyapısı burada kuruluyor; polling + yerel bildirim KALDIRILMADI, yedek
// katman olarak duruyor (bkz. utils/notify.js dosya başı notu).
// firebase-admin v14+ modüler API kullanır (`require('firebase-admin')`
// yalnızca initializeApp/cert taşır, messaging AYRI bir alt modüldür) — eski
// `admin.credential.cert()` / `admin.messaging()` deseni bu sürümde ÇALIŞMAZ.
const { initializeApp, cert } = require('firebase-admin/app');
const { getMessaging } = require('firebase-admin/messaging');
const fs = require('fs');
const path = require('path');

// Railway gibi git tabanlı deploy'larda firebase-service-account.json
// .gitignore'da olduğu için repoya HİÇ gitmez (bkz. JWT_SECRET ile AYNI
// gizli-bilgi ilkesi) — bu yüzden production'da servis hesabı JSON'unun
// TAMAMI FIREBASE_SERVICE_ACCOUNT_JSON ortam değişkeninden okunur (Railway
// panelinden elle eklenmesi gerekir). Yerel geliştirmede ise doğrudan
// dosyadan okunur.
let serviceAccount = null;
const serviceAccountPath = path.join(__dirname, '../firebase-service-account.json');
try {
  if (process.env.FIREBASE_SERVICE_ACCOUNT_JSON) {
    serviceAccount = JSON.parse(process.env.FIREBASE_SERVICE_ACCOUNT_JSON);
  } else if (fs.existsSync(serviceAccountPath)) {
    serviceAccount = require(serviceAccountPath);
  }
} catch (err) {
  console.error('[PUSH BİLDİRİM] Servis hesabı okunamadı:', err.message);
}

// ML servisi kapalıyken sunucunun başlamasını ENGELLEMEYEN desenle AYNI
// (bkz. server.js risk/anomaly skor yenileme try/catch'leri) — Firebase
// kimlik bilgisi eksikse/hatalıysa push bildirimleri sessizce devre dışı
// kalır, polling/yerel bildirim yedek katmanı çalışmaya devam eder.
let messaging = null;
if (serviceAccount) {
  try {
    const app = initializeApp({ credential: cert(serviceAccount) });
    messaging = getMessaging(app);
  } catch (err) {
    console.error('[PUSH BİLDİRİM] Firebase Admin SDK başlatılamadı:', err.message);
  }
} else {
  console.warn(
    '[PUSH BİLDİRİM] Firebase servis hesabı bulunamadı — push bildirimleri devre dışı, ' +
      'yalnızca polling/yerel bildirim yedek katmanı çalışacak.'
  );
}

// Android bildirim kanalları — bkz. lib/services/local_notification_service.dart
// (_channelId/_sosChannelId AYNEN buradaki değerlerle eşleşmeli, aksi halde
// uygulama arka plandayken/kapalıyken gelen bildirim ya kanalsız/varsayılan
// düşer ya da hiç kanal eşleşmediği için gösterilmeyebilir).
const DEFAULT_CHANNEL_ID = 'arassaha_notifications';
const SOS_CHANNEL_ID = 'arassaha_sos_alerts';

/**
 * @param {string|null|undefined} fcmToken - users.fcm_token (kayıtlı cihaz yoksa null).
 * @param {string} title - Bildirim başlığı.
 * @param {string} body - Bildirim gövdesi (Türkçe mesaj).
 * @param {Record<string,string>} data - Ek bilgi, örn. { type, related_id } —
 *   Flutter tarafında dokununca doğru ekrana yönlendirmek için (bkz.
 *   push_notification_service.dart).
 */
async function sendPushNotification(fcmToken, title, body, data = {}) {
  if (!messaging || !fcmToken) return;

  const isSosAlert = data.type === 'sos_alert';

  try {
    await messaging.send({
      token: fcmToken,
      notification: { title, body },
      data,
      android: {
        // Arka planda/uygulama kapalıyken bile anında teslim için.
        priority: 'high',
        notification: {
          channelId: isSosAlert ? SOS_CHANNEL_ID : DEFAULT_CHANNEL_ID,
        },
      },
    });
  } catch (err) {
    // Token geçersizse (kullanıcı uygulamayı kaldırmış, cihaz değiştirmiş
    // vb.) bunu logla ama isteği ASLA çökertme — bildirimi tetikleyen asıl
    // işlem (iş emri atama, SOS vb.) push bildiriminden bağımsız başarılı
    // sayılmalı.
    console.error('[PUSH BİLDİRİM HATASI]', err.message);
  }
}

module.exports = { sendPushNotification };
