import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import '../main.dart' show rootNavigatorKey;
import '../screens/notifications/notifications_screen.dart';
import '../screens/sos/sos_alerts_screen.dart';
import 'api_service.dart';
import 'local_notification_service.dart';

/// Uygulama TAMAMEN KAPALIYKEN/arka plandayken gelen mesajlar için — Android
/// tarafından ayrı bir izole (isolate) içinde çağrılır, bu yüzden üst seviye
/// (top-level) bir fonksiyon ve `@pragma('vm:entry-point')` ZORUNLUDUR (aksi
/// halde release build'de tree-shaking bu fonksiyonu silebilir, bkz. main.dart
/// FirebaseMessaging.onBackgroundMessage kayıt noktası). Genelde burada ekstra
/// bir şey yapmaya gerek yok — bir `notification` alanı taşıyan mesajlar için
/// Android sistemi bildirimi zaten OTOMATİK gösterir (bkz.
/// services/pushNotificationService.js `notification: { title, body }`).
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {}

/// Push Bildirim (FCM) Servisi — bkz. backend services/pushNotificationService.js,
/// utils/notify.js. Polling + yerel bildirim (bkz. LocalNotificationService,
/// NotificationProvider) YEDEK katman olarak KALDI; bu servis uygulama arka
/// plandayken/kapalıyken de ANINDA bildirim teslimini sağlar.
class PushNotificationService {
  PushNotificationService._();
  static final PushNotificationService instance = PushNotificationService._();

  final ApiService _apiService = ApiService();
  bool _initialized = false;

  /// MainShell.initState'ten çağrılır (bkz. LocalNotificationService.requestPermission
  /// ile AYNI çağrı noktası/desen) — yalnızca kimlik doğrulanmış kullanıcı
  /// gördüğü için burada, login sonrası anlamına gelir.
  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    await FirebaseMessaging.instance.requestPermission();

    final token = await FirebaseMessaging.instance.getToken();
    if (token != null) {
      await _registerToken(token);
    }
    // Token nadiren yenilenir (örn. uygulama verisi silinirse) — yenilendiğinde
    // backend'deki kaydın da güncellenmesi gerekir, aksi halde push sessizce
    // eski/geçersiz bir token'a gönderilmeye devam eder.
    FirebaseMessaging.instance.onTokenRefresh.listen(_registerToken);

    // Uygulama ÖN PLANDAYKEN gelen mesajlar: Android bir `notification`
    // payload'ı için sistemi bildirimini yalnızca arka planda/kapalıyken
    // OTOMATİK gösterir — ön plandayken elle göstermemiz gerekir (bkz.
    // LocalNotificationService.showNotification, SOS için AYRI kanal/ses).
    FirebaseMessaging.onMessage.listen(_showForegroundNotification);

    // Kullanıcı bir bildirime dokunup uygulamayı AÇTIĞINDA (arka plandan).
    FirebaseMessaging.onMessageOpenedApp.listen(_handleNotificationTap);

    // Uygulama TAMAMEN KAPALIYKEN bir bildirime dokunarak açıldıysa —
    // onMessageOpenedApp bu durumu YAKALAMAZ (henüz dinlemiyor olurdu),
    // bu yüzden ayrıca kontrol edilir.
    final initialMessage = await FirebaseMessaging.instance
        .getInitialMessage();
    if (initialMessage != null) {
      _handleNotificationTap(initialMessage);
    }
  }

  Future<void> _registerToken(String token) async {
    try {
      await _apiService.registerFcmToken(token);
    } catch (e) {
      // Kayıt başarısız olsa bile (ağ hatası vb.) uygulama çalışmaya devam
      // eder — polling/yerel bildirim yedek katmanı hâlâ çalışır (bkz. sınıf
      // başı dokümantasyonu).
      debugPrint('FCM token kaydedilemedi: $e');
    }
  }

  /// AuthProvider.logout() tarafından çağrılır — çıkış yapan bir cihaza
  /// artık bildirim gitmemesi için backend'deki kayıtlı token temizlenir.
  Future<void> clearRegisteredToken() async {
    try {
      await _apiService.registerFcmToken(null);
    } catch (e) {
      debugPrint('FCM token temizlenemedi: $e');
    }
  }

  void _showForegroundNotification(RemoteMessage message) {
    final notification = message.notification;
    if (notification == null) return;

    final isSosAlert = message.data['type'] == 'sos_alert';
    LocalNotificationService.instance.showNotification(
      notification.title ?? 'ArasSaha',
      notification.body ?? '',
      isUrgent: isSosAlert,
    );
  }

  /// SOS bildirimleri doğrudan SOS Uyarıları ekranına, diğer TÜM türler
  /// Bildirimler ekranına yönlendirilir (bkz.
  /// screens/notifications/notifications_screen.dart._openNotification —
  /// oradaki tam yönlendirme mantığı — okundu işaretleme, yönetici mesajı
  /// arama vb. — BuildContext/provider'lara bağımlı olduğu için burada
  /// KASITLI olarak tekrarlanmadı; kullanıcı zaten o ekrandan ilgili
  /// bildirime dokunarak devam edebilir).
  void _handleNotificationTap(RemoteMessage message) {
    final navigator = rootNavigatorKey.currentState;
    if (navigator == null) return;

    final isSosAlert = message.data['type'] == 'sos_alert';
    navigator.push(
      MaterialPageRoute(
        builder: (_) =>
            isSosAlert ? const SosAlertsScreen() : const NotificationsScreen(),
      ),
    );
  }
}
