import 'dart:async';
import 'api_service.dart';

/// Basit Kullanım Analitiği (UX standardizasyonu turu, bölüm E).
///
/// AYRIM: Bu, ücretli/harici bir davranış analizi aracının (Hotjar, Firebase
/// Analytics vb.) YERİNE geçen kasıtlı olarak BASİT bir alternatif — ısı
/// haritası/oturum kaydı DEĞİLDİR, yalnızca backend'deki `usage_logs`
/// tablosuna "hangi ekran, hangi buton" bilgisini düşüren ince bir katman.
///
/// TÜM çağrılar "fire and forget"tir: sonucu beklenmez (`unawaited`), hata
/// olursa SESSİZCE yutulur (`catchError`). Bir analitik logunun başarısız
/// olması (örn. backend o an kapalıysa) uygulamanın asıl işlevini
/// ETKİLEMEMELİDİR — kullanıcı hiçbir hata görmemeli, akış hiç yavaşlamamalı.
class AnalyticsService {
  AnalyticsService._();

  static final ApiService _api = ApiService();

  /// AppButton'ın primary varyantı tıklandığında OTOMATİK olarak hangi
  /// ekranda olduğumuzu bilebilmesi için (bkz. widgets/app_button.dart) —
  /// context threading yapmadan, merkezi/mutable bir "şu an hangi
  /// ekrandayız" işaretçisi. Her ekran `initState`'te [logScreenView]
  /// çağırdığında bu değer güncellenir.
  static String? _currentScreen;
  static String get currentScreen => _currentScreen ?? 'unknown';

  static void logScreenView(String screenName) {
    _currentScreen = screenName;
    _send(eventType: 'screen_view', screenName: screenName);
  }

  static void logButtonTap(String screenName, String elementName) {
    _send(
      eventType: 'button_tap',
      screenName: screenName,
      elementName: elementName,
    );
  }

  static void _send({
    required String eventType,
    required String screenName,
    String? elementName,
  }) {
    unawaited(
      _api
          .logAnalyticsEvent(
            eventType: eventType,
            screenName: screenName,
            elementName: elementName,
          )
          .catchError((_) {}),
    );
  }
}
