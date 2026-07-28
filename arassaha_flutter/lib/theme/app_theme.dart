import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Uygulamanın tüm görsel dili tek yerden yönetilir: renkler, tipografi,
/// köşe yuvarlaklığı, kart/rozet stilleri. Yeni bir ekran eklerken renkleri
/// asla sabit kodlama — her zaman `Theme.of(context).colorScheme` üzerinden
/// çek ki açık/koyu mod otomatik uyum sağlasın.
class AppTheme {
  AppTheme._();

  // Aras EDAŞ marka rengi (logo lacivert) baz alınarak türetilmiş M3 renk
  // token seti. Açık tema değerleri doğrudan tasarımda verilen paletle birebir.
  static const Color _lightPrimary = Color(0xFF00294F);
  static const Color _lightPrimaryContainer = Color(0xFF173F6B);
  static const Color _lightOnPrimaryContainer = Color(0xFFD4E3FF);
  static const Color _lightSecondary = Color(0xFF006E2E);
  static const Color _lightSecondaryContainer = Color(0xFF8CFA9F);
  static const Color _lightOnSecondaryContainer = Color(0xFF007432);
  static const Color _lightTertiary = Color(0xFF7A4200);
  static const Color _lightTertiaryContainer = Color(0xFF613200);
  static const Color _lightOnTertiaryContainer = Color(0xFFED9546);
  static const Color _lightError = Color(0xFFBA1A1A);
  static const Color _lightErrorContainer = Color(0xFFFFDAD6);
  static const Color _lightOnErrorContainer = Color(0xFF93000A);
  static const Color _lightSurface = Color(0xFFF8F9FB);
  static const Color _lightOnSurface = Color(0xFF191C1E);
  static const Color _lightOnSurfaceVariant = Color(0xFF43474F);
  static const Color _lightOutline = Color(0xFF737780);
  static const Color _lightOutlineVariant = Color(0xFFC3C6D0);
  static const Color _lightSurfaceContainerLowest = Color(0xFFFFFFFF);
  static const Color _lightSurfaceContainerLow = Color(0xFFF2F4F6);
  static const Color _lightSurfaceContainer = Color(0xFFECEEF0);
  static const Color _lightSurfaceContainerHigh = Color(0xFFE6E8EA);
  static const Color _lightSurfaceContainerHighest = Color(0xFFE0E3E5);
  static const Color _lightInverseSurface = Color(0xFF2D3133);
  static const Color _lightOnInverseSurface = Color(0xFFEFF1F3);
  static const Color _lightInversePrimary = Color(0xFFA6C9FD);

  // Statü/öncelik gibi anlam taşıyan sabit vurgu renkleri (marka paletinde
  // karşılığı olmayan iki ek ton). Bunlar tema değişse de aynı kalır.
  static const Color accentOrange = Color(0xFFFF9800);
  static const Color accentPurple = Color(0xFF7C4DFF);

  static ColorScheme get lightColorScheme => const ColorScheme(
        brightness: Brightness.light,
        primary: _lightPrimary,
        onPrimary: Colors.white,
        primaryContainer: _lightPrimaryContainer,
        onPrimaryContainer: _lightOnPrimaryContainer,
        secondary: _lightSecondary,
        onSecondary: Colors.white,
        secondaryContainer: _lightSecondaryContainer,
        onSecondaryContainer: _lightOnSecondaryContainer,
        tertiary: _lightTertiary,
        onTertiary: Colors.white,
        tertiaryContainer: _lightTertiaryContainer,
        onTertiaryContainer: _lightOnTertiaryContainer,
        error: _lightError,
        onError: Colors.white,
        errorContainer: _lightErrorContainer,
        onErrorContainer: _lightOnErrorContainer,
        surface: _lightSurface,
        onSurface: _lightOnSurface,
        surfaceContainerLowest: _lightSurfaceContainerLowest,
        surfaceContainerLow: _lightSurfaceContainerLow,
        surfaceContainer: _lightSurfaceContainer,
        surfaceContainerHigh: _lightSurfaceContainerHigh,
        surfaceContainerHighest: _lightSurfaceContainerHighest,
        onSurfaceVariant: _lightOnSurfaceVariant,
        outline: _lightOutline,
        outlineVariant: _lightOutlineVariant,
        shadow: Colors.black,
        scrim: Colors.black,
        inverseSurface: _lightInverseSurface,
        onInverseSurface: _lightOnInverseSurface,
        inversePrimary: _lightInversePrimary,
        surfaceTint: _lightPrimary,
      );

  // Koyu tema: açık temanın "inverse"/"fixed" token'larından türetildi
  // (M3'ün standart yaklaşımı) — ayrı bir palet icat etmek yerine aynı marka
  // renklerinin koyu zemine uyarlanmış hâli.
  static ColorScheme get darkColorScheme => const ColorScheme(
        brightness: Brightness.dark,
        primary: _lightInversePrimary,
        onPrimary: Color(0xFF001C39),
        primaryContainer: Color(0xFF224874),
        onPrimaryContainer: _lightOnPrimaryContainer,
        secondary: Color(0xFF70DD85),
        onSecondary: Color(0xFF002109),
        secondaryContainer: Color(0xFF005321),
        onSecondaryContainer: _lightSecondaryContainer,
        tertiary: Color(0xFFFFB77D),
        onTertiary: Color(0xFF2F1500),
        tertiaryContainer: Color(0xFF6E3900),
        onTertiaryContainer: Color(0xFFFFDCC3),
        error: Color(0xFFFFB4AB),
        onError: Color(0xFF690005),
        errorContainer: Color(0xFF93000A),
        onErrorContainer: _lightErrorContainer,
        surface: _lightInverseSurface,
        onSurface: _lightOnInverseSurface,
        surfaceContainerLowest: Color(0xFF0A0C0D),
        surfaceContainerLow: Color(0xFF191C1E),
        surfaceContainer: Color(0xFF1D2022),
        surfaceContainerHigh: Color(0xFF282B2D),
        surfaceContainerHighest: Color(0xFF333638),
        onSurfaceVariant: _lightOutlineVariant,
        outline: Color(0xFF8D9199),
        outlineVariant: _lightOnSurfaceVariant,
        shadow: Colors.black,
        scrim: Colors.black,
        inverseSurface: _lightSurfaceContainerHighest,
        onInverseSurface: _lightOnSurface,
        inversePrimary: _lightPrimary,
        surfaceTint: _lightInversePrimary,
      );

  static TextTheme _textTheme(ColorScheme scheme) {
    // Başlıklar: Plus Jakarta Sans / Gövde metni: Work Sans — tasarımda
    // verilen font eşleşmesi.
    final base = TextTheme(
      headlineLarge: GoogleFonts.plusJakartaSans(fontSize: 32, height: 40 / 32, letterSpacing: -0.02, fontWeight: FontWeight.w700),
      headlineMedium: GoogleFonts.plusJakartaSans(fontSize: 24, height: 32 / 24, fontWeight: FontWeight.w700),
      headlineSmall: GoogleFonts.plusJakartaSans(fontSize: 20, height: 28 / 20, fontWeight: FontWeight.w600),
      titleMedium: GoogleFonts.plusJakartaSans(fontSize: 16, height: 24 / 16, fontWeight: FontWeight.w700),
      bodyLarge: GoogleFonts.workSans(fontSize: 18, height: 28 / 18, fontWeight: FontWeight.w400),
      bodyMedium: GoogleFonts.workSans(fontSize: 16, height: 24 / 16, fontWeight: FontWeight.w400),
      bodySmall: GoogleFonts.workSans(fontSize: 13, height: 18 / 13, fontWeight: FontWeight.w400),
      labelLarge: GoogleFonts.workSans(fontSize: 14, height: 20 / 14, letterSpacing: 0.1, fontWeight: FontWeight.w600),
      labelSmall: GoogleFonts.workSans(fontSize: 12, height: 16 / 12, fontWeight: FontWeight.w600),
    );
    return base.apply(bodyColor: scheme.onSurface, displayColor: scheme.onSurface);
  }

  static ThemeData light() => _build(lightColorScheme);
  static ThemeData dark() => _build(darkColorScheme);

  static ThemeData _build(ColorScheme scheme) {
    return ThemeData(
      colorScheme: scheme,
      useMaterial3: true,
      brightness: scheme.brightness,
      scaffoldBackgroundColor: scheme.surface,
      textTheme: _textTheme(scheme),
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface.withValues(alpha: 0.92),
        surfaceTintColor: Colors.transparent,
        foregroundColor: scheme.primary,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: GoogleFonts.plusJakartaSans(
          fontSize: 22,
          fontWeight: FontWeight.w700,
          color: scheme.primary,
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: scheme.surfaceContainerLowest,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.4)),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: scheme.surfaceContainerHigh,
        labelStyle: GoogleFonts.workSans(fontWeight: FontWeight.w600, fontSize: 14),
        selectedColor: scheme.primary,
        shape: const StadiumBorder(),
        side: BorderSide.none,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: scheme.primary,
          foregroundColor: scheme.onPrimary,
          elevation: 2,
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle: GoogleFonts.workSans(fontWeight: FontWeight.w700, fontSize: 15),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: scheme.secondary,
          side: BorderSide(color: scheme.secondary, width: 2),
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle: GoogleFonts.workSans(fontWeight: FontWeight.w700, fontSize: 15),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: scheme.secondary,
        foregroundColor: scheme.onSecondary,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainerLowest,
        hintStyle: GoogleFonts.workSans(color: scheme.outline),
        contentPadding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: scheme.primary, width: 1.5),
        ),
      ),
      dividerTheme: DividerThemeData(color: scheme.outlineVariant.withValues(alpha: 0.5), space: 1),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: scheme.surfaceContainer,
        indicatorColor: scheme.secondaryContainer,
        elevation: 4,
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return GoogleFonts.workSans(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: selected ? scheme.onSecondaryContainer : scheme.onSurfaceVariant,
          );
        }),
      ),
    );
  }
}
