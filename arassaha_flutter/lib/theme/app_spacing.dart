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

/// C1 (responsive grid): ızgara sütun sayısını EKRAN GENİŞLİĞİNE göre
/// hesaplar — sabit `crossAxisCount: 2` gibi değerler yerine kullanılır.
/// Telefon (320-599dp) 2 sütun, tablet (600-899dp) 3 sütun, geniş tablet/
/// katlanabilir (900dp+) 4 sütun. `LayoutBuilder`'ın verdiği `constraints.maxWidth`
/// ile çağrılır (bkz. home_screen.dart modül ızgarası, isg_report_form_screen.dart
/// kategori ızgarası, work_order_detail_screen.dart fotoğraf ızgarası).
int responsiveGridColumns(double maxWidth, {int minColumns = 2}) {
  if (maxWidth >= 900) return minColumns + 2;
  if (maxWidth >= 600) return minColumns + 1;
  return minColumns;
}
