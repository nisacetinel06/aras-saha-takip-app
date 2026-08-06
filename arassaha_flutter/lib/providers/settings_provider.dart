import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart';

const String _kNotificationsEnabledKey = 'settings_notifications_enabled';

/// Ayarlar ve Çevrimdışı Mod (Modül 17) — Ayarlar ekranındaki tercihlerden
/// tema DIŞINDAKİLERİ yönetir (tema zaten kendi [ThemeProvider]'ında —
/// tek gerçek kaynak ilkesiyle burada TEKRARLANMAZ). Şu an tek tercih
/// "bildirimler açık/kapalı"dır; hem bellekte (state) hem SharedPreferences'ta
/// (kalıcı) tutulur — ThemeProvider ile AYNI desen.
class SettingsProvider extends ChangeNotifier {
  bool _notificationsEnabled = true;

  bool get notificationsEnabled => _notificationsEnabled;

  /// main() içinde runApp'ten önce çağrılır; kayıtlı tercih varsa yükler.
  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _notificationsEnabled = prefs.getBool(_kNotificationsEnabledKey) ?? true;
  }

  /// Bildirim polling'ini bizzat başlatıp durdurmaz — bu, çağıran tarafın
  /// (MainShell/SettingsScreen) [NotificationProvider.startPolling]/
  /// [NotificationProvider.stopPolling] ile ayrıca yapması gereken bir iş;
  /// bu sınıf yalnızca TERCİHİ saklar, iki provider'ı birbirine bağımlı
  /// hale getirmemek için.
  Future<void> setNotificationsEnabled(bool value) async {
    _notificationsEnabled = value;
    notifyListeners();

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kNotificationsEnabledKey, value);
  }
}
