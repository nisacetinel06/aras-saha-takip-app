import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// SharedPreferences anahtarı — MainActivity.kt bu AYNI dosyayı/anahtarı okuyup
/// splash ekranının açık/koyu modunu buna göre seçiyor (bkz. android/app/src/
/// main/kotlin/.../MainActivity.kt). Burada değiştirilirse orada da güncellenmeli.
const String kThemeModePrefsKey = 'theme_mode';

/// Uygulamanın açık/koyu tema durumunu yönetir. İlk açılışta (kayıtlı tercih
/// yokken) her zaman AÇIK moddadır; kullanıcı Dashboard'daki güneş/ay
/// ikonuyla değiştirdiğinde tercih kalıcı olarak saklanır (SharedPreferences)
/// — bir sonraki açılışta hem uygulama hem native splash ekranı bu tercihi
/// kullanır.
class ThemeProvider extends ChangeNotifier {
  ThemeMode _mode = ThemeMode.light;

  ThemeMode get mode => _mode;
  bool get isDark => _mode == ThemeMode.dark;

  /// main() içinde runApp'ten önce çağrılır; kayıtlı tercih varsa yükler.
  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(kThemeModePrefsKey);
    if (saved == 'dark') {
      _mode = ThemeMode.dark;
    } else if (saved == 'light') {
      _mode = ThemeMode.light;
    }
    // Kayıt yoksa (ilk açılış) varsayılan olan ThemeMode.light korunur.
  }

  Future<void> toggle() async {
    _mode = isDark ? ThemeMode.light : ThemeMode.dark;
    notifyListeners();

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(kThemeModePrefsKey, isDark ? 'dark' : 'light');
  }
}
