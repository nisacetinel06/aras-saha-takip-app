import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Bildirim Sistemi (Modül 6) — cihazda GERÇEK bir OS bildirimi göstermek için
/// flutter_local_notifications kullanır.
///
/// NEDEN FCM (Firebase Cloud Messaging) DEĞİL: Bir staj projesi kapsamında
/// gerçek bir sunucu-push altyapısı kurmak (Firebase projesi açma, sunucu
/// anahtarı/service account yönetimi, native platform entegrasyonu) işin
/// asıl amacına (bildirim akışının uçtan uca çalıştığını göstermek) oranla
/// gereksiz bir karmaşıklık katardı. Bunun yerine NotificationProvider,
/// backend'i periyodik olarak (30 sn) yoklar (polling) ve okunmamış sayıda
/// artış tespit ederse bu servis üzerinden cihazda gerçek bir bildirim
/// gösterir — kullanıcı deneyimi (bildirim çubuğunda gerçek bir bildirim
/// görmek) FCM ile aynıdır, yalnızca sunucudan cihaza itme (push) yerine
/// cihazın kendi kendine sorması (pull) esasına dayanır.
class LocalNotificationService {
  LocalNotificationService._();
  static final LocalNotificationService instance = LocalNotificationService._();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _initialized = false;
  bool _permissionRequestInFlight = false;

  static const _channelId = 'arassaha_notifications';
  static const _channelName = 'ArasSaha Bildirimleri';
  static const _channelDescription =
      'İş emri, İSG bildirimi ve ekipman risk güncellemeleri.';

  Future<void> initialize() async {
    if (_initialized) return;

    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const initSettings = InitializationSettings(android: androidInit);
    await _plugin.initialize(settings: initSettings);

    // Android 8+ bildirimleri kanal bazlı gruplar — kanal önceden
    // oluşturulmazsa ilk show() çağrısında varsayılan (düşük öncelikli) bir
    // kanal otomatik türetilir; burada açıkça yüksek önemde bir kanal
    // tanımlıyoruz ki bildirim çubuğunda gerçekten öne çıksın.
    const channel = AndroidNotificationChannel(
      _channelId,
      _channelName,
      description: _channelDescription,
      importance: Importance.high,
    );
    await _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(channel);

    _initialized = true;
  }

  /// Android 13+ (API 33) itibarıyla bildirim gösterebilmek için çalışma
  /// zamanında kullanıcıdan ayrıca izin istenmesi gerekir (POST_NOTIFICATIONS).
  /// Reddedilirse yerel bildirim sessizce gösterilmez; uygulama Bildirimler
  /// ekranından tam listeyi göstermeye devam eder, bu yüzden kritik bir hata
  /// değildir.
  Future<void> requestPermission() async {
    // MainShell her mount olduğunda (örn. çıkış yapıp tekrar giriş) bunu
    // çağırır — önceki istek native tarafta hâlâ çözülüyorsa, plugin
    // PlatformException(permissionRequestInProgress) fırlatır. Bu koruma
    // olmadan bu istisna hiçbir yerde yakalanmıyordu (initState içinde
    // try/catch yok).
    if (_permissionRequestInFlight) return;
    _permissionRequestInFlight = true;
    try {
      await _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.requestNotificationsPermission();
    } finally {
      _permissionRequestInFlight = false;
    }
  }

  Future<void> showNotification(String title, String body) async {
    if (!_initialized) await initialize();

    const androidDetails = AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: _channelDescription,
      importance: Importance.high,
      priority: Priority.high,
    );
    const details = NotificationDetails(android: androidDetails);

    try {
      // id olarak epoch milisaniyesi kullanılır — art arda gelen bildirimler
      // birbirinin üzerine yazmasın (aynı id verilirse önceki bildirim
      // güncellenir/kaybolur) diye her çağrı benzersiz bir id üretir.
      await _plugin.show(
        id: DateTime.now().millisecondsSinceEpoch.remainder(100000),
        title: title,
        body: body,
        notificationDetails: details,
      );
    } catch (e) {
      // Bildirim gösterilemezse (izin yok, platform desteklemiyor vb.)
      // uygulamanın çökmesine gerek yok — kullanıcı Bildirimler ekranından
      // yine de tam listeyi görebilir.
      debugPrint('Yerel bildirim gösterilemedi: $e');
    }
  }
}
