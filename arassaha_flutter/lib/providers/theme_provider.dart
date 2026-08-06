import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// SharedPreferences anahtarı — MainActivity.kt bu AYNI dosyayı/anahtarı okuyup
/// splash ekranının açık/koyu modunu buna göre seçiyor (bkz. android/app/src/
/// main/kotlin/.../MainActivity.kt). Burada değiştirilirse orada da güncellenmeli.
const String kThemeModePrefsKey = 'theme_mode';

/// Uygulamanın açık/koyu/sistem tema durumunu yönetir. İlk açılışta (kayıtlı
/// tercih yokken) her zaman AÇIK moddadır; kullanıcı bu tercihi değiştirdiğinde
/// (Dashboard'daki güneş/ay ikonu YA DA Ayarlar ekranındaki üç seçenekli
/// seçim — Modül 17) kalıcı olarak saklanır (SharedPreferences) — bir sonraki
/// açılışta uygulama bu tercihi kullanır.
///
/// BİLİNEN SINIRLAMA: native splash ekranı (bkz. android/.../MainActivity.kt)
/// yalnızca kayıtlı değerin TAM OLARAK "dark" olup olmadığına bakar — "system"
/// seçiliyken cihazın GERÇEK anlık parlaklık durumunu native tarafta ayrıca
/// okumak (Configuration.uiMode) gereksiz bir karmaşıklık katardığı için splash
/// bu durumda her zaman açık modda gösterilir; uygulamanın kendisi açıldığı
/// anda (MaterialApp.themeMode: ThemeMode.system) doğru temaya geçer — bu yüzden
/// en kötü ihtimalle yalnızca çok kısa bir splash anında yanlış tema görülebilir.
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
    } else if (saved == 'system') {
      _mode = ThemeMode.system;
    } else {
      _mode = ThemeMode.light;
    }
    // Kayıt yoksa (ilk açılış) varsayılan olan ThemeMode.light korunur.
  }

  /// Dashboard'daki hızlı güneş/ay ikonu — yalnızca açık/koyu arasında
  /// geçiş yapar (sistem modundayken tıklanırsa doğrudan koyu moda geçer).
  Future<void> toggle() async {
    await setMode(isDark ? ThemeMode.light : ThemeMode.dark);
  }

  /// Ayarlar ekranındaki üç seçenekli (Açık / Koyu / Cihaza Göre) seçimden
  /// çağrılır.
  Future<void> setMode(ThemeMode mode) async {
    _mode = mode;
    notifyListeners();

    final prefs = await SharedPreferences.getInstance();
    final value = switch (mode) {
      ThemeMode.dark => 'dark',
      ThemeMode.system => 'system',
      ThemeMode.light => 'light',
    };
    await prefs.setString(kThemeModePrefsKey, value);
  }
}
