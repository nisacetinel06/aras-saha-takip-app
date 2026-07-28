import 'dart:ui';
import 'package:flutter/material.dart';

/// Uygulamanın açık/koyu tema durumunu yönetir. Varsayılan olarak cihazın
/// sistem ayarını takip eder (ThemeMode.system); kullanıcı Dashboard'daki
/// güneş/ay ikonuyla manuel olarak açık/koyu arasında sabitleyebilir.
/// Kalıcı saklama yapılmaz (prototip kapsamında yeterli); uygulama yeniden
/// açıldığında sistem ayarına döner.
class ThemeProvider extends ChangeNotifier {
  ThemeMode _mode = ThemeMode.system;

  ThemeMode get mode => _mode;

  /// Sistem modundayken gerçek görünen parlaklığı da hesaba katar.
  bool get isDark {
    if (_mode == ThemeMode.system) {
      return PlatformDispatcher.instance.platformBrightness == Brightness.dark;
    }
    return _mode == ThemeMode.dark;
  }

  void toggle() {
    _mode = isDark ? ThemeMode.light : ThemeMode.dark;
    notifyListeners();
  }
}
