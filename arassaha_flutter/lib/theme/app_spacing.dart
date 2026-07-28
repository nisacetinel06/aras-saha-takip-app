/// Uygulama genelinde padding/margin değerleri bu ölçekten seçilir —
/// rastgele sayılar (17, 23 gibi) kullanılmaz. Bkz. DESIGN_SYSTEM.md Bölüm A.3.
class AppSpacing {
  AppSpacing._();

  static const double xs = 4;
  static const double sm = 8;
  static const double md = 16;
  static const double lg = 24;
  static const double xl = 32;
}

/// Köşe yuvarlaklığı standardı: kartlar 12, butonlar 10, chip/rozetler 8,
/// tam yuvarlak (FAB gibi) 999.
class AppRadius {
  AppRadius._();

  static const double card = 12;
  static const double button = 10;
  static const double chip = 8;
  static const double pill = 999;
}
