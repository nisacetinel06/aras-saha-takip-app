import 'package:flutter/foundation.dart';

/// Ayarlar ekranındaki (Modül 17) "Turu Tekrar Göster" butonunun Ana Sayfa
/// Turu'nu (bkz. main_shell.dart) yeniden tetikleyebilmesi için ince bir
/// köprü. `settings_screen.dart`'ın `main_shell.dart`'ı DOĞRUDAN import
/// etmesini (screens/settings -> screens/main_shell -> screens/profile ->
/// screens/settings döngüsel import'u) önlemek için statik bir geri çağırım
/// saklar — MainShell kendini `initState`'te kaydeder, `dispose`'ta siler.
class HomeTourController {
  HomeTourController._();

  static VoidCallback? _restartHandler;

  static void registerRestartHandler(VoidCallback handler) {
    _restartHandler = handler;
  }

  static void unregisterRestartHandler(VoidCallback handler) {
    if (identical(_restartHandler, handler)) _restartHandler = null;
  }

  /// MainShell şu an mount değilse (kuramsal olarak imkansız — bu, kullanıcı
  /// giriş yapmışken her zaman ekranda olan kalıcı kabuk) sessizce hiçbir
  /// şey yapmaz.
  static void requestRestart() => _restartHandler?.call();
}
