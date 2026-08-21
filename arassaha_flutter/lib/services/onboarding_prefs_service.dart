import 'package:shared_preferences/shared_preferences.dart';

const _kHasSeenHomeTourKey = 'has_seen_onboarding';
const _kHasSeenRiskBadgeHintKey = 'has_seen_risk_badge_hint';
const _kHasSeenQrScannerHintKey = 'has_seen_qr_scanner_hint';

/// Onboarding Turu ve bağlamsal ilk-karşılaşma ipuçları (Modül 4 QR tarama,
/// Modül 9 risk rozeti) için "bu kullanıcı bunu daha önce gördü mü"
/// bayrakları.
///
/// BİLİNÇLİ olarak [SharedPreferences] kullanır, `flutter_secure_storage`
/// DEĞİL: JWT token (bkz. services/secure_storage_service.dart) hassas bir
/// kimlik bilgisi olduğu için şifreli depolamaya taşınmıştı, ama bu bayraklar
/// yalnızca bir UI tercihi — hangi ipucunun gösterildiği bilgisi sızsa bile
/// hiçbir güvenlik/gizlilik riski doğurmaz. "Her ayarı güvenli depolamaya
/// taşı" genellemesi burada YANLIŞ olurdu: hassas olmayan veriyi gereksiz
/// yere şifreli depolamaya taşımak yalnızca karmaşıklık ekler, güvenlik
/// kazandırmaz.
class OnboardingPrefsService {
  OnboardingPrefsService._();

  static Future<bool> hasSeenHomeTour() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_kHasSeenHomeTourKey) ?? false;
  }

  static Future<void> setHasSeenHomeTour(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kHasSeenHomeTourKey, value);
  }

  static Future<bool> hasSeenRiskBadgeHint() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_kHasSeenRiskBadgeHintKey) ?? false;
  }

  static Future<void> setHasSeenRiskBadgeHint() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kHasSeenRiskBadgeHintKey, true);
  }

  static Future<bool> hasSeenQrScannerHint() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_kHasSeenQrScannerHintKey) ?? false;
  }

  static Future<void> setHasSeenQrScannerHint() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kHasSeenQrScannerHintKey, true);
  }
}
