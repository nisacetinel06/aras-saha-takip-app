import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'app_colors.dart';
import 'app_spacing.dart';
import 'app_text_styles.dart';

/// Uygulamanın tüm görsel dili tek yerden yönetilir: renkler (app_colors.dart),
/// tipografi (app_text_styles.dart), köşe yuvarlaklığı (app_spacing.dart),
/// kart/buton/rozet stilleri. Yeni bir ekran eklerken renkleri asla sabit
/// kodlama — her zaman `Theme.of(context).colorScheme` üzerinden çek ki
/// açık/koyu mod otomatik uyum sağlasın. Bkz. DESIGN_SYSTEM.md.
class AppTheme {
  AppTheme._();

  static ColorScheme get lightColorScheme => const ColorScheme(
        brightness: Brightness.light,
        primary: AppColors.lightPrimary,
        onPrimary: Colors.white,
        primaryContainer: Color(0xFFD4E3FF),
        onPrimaryContainer: AppColors.lightPrimary,
        secondary: AppColors.lightSuccess,
        onSecondary: Colors.white,
        secondaryContainer: Color(0xFFC8F0D6),
        onSecondaryContainer: Color(0xFF0F3F26),
        tertiary: AppColors.lightWarning,
        onTertiary: Colors.white,
        tertiaryContainer: Color(0xFFFFE1B8),
        onTertiaryContainer: Color(0xFF7A4B00),
        error: AppColors.lightDanger,
        onError: Colors.white,
        errorContainer: Color(0xFFFFDAD6),
        onErrorContainer: Color(0xFF93000A),
        surface: AppColors.lightBackground,
        onSurface: AppColors.lightTextPrimary,
        surfaceContainerLowest: AppColors.lightSurface,
        surfaceContainerLow: Color(0xFFF2F4F6),
        surfaceContainer: Color(0xFFECEEF0),
        surfaceContainerHigh: Color(0xFFE6E8EA),
        surfaceContainerHighest: Color(0xFFE0E3E5),
        onSurfaceVariant: AppColors.lightTextSecondary,
        outline: Color(0xFF9CA3AF),
        outlineVariant: Color(0xFFD1D5DB),
        shadow: Colors.black,
        scrim: Colors.black,
        inverseSurface: Color(0xFF2D3133),
        onInverseSurface: Color(0xFFEFF1F3),
        inversePrimary: AppColors.darkPrimary,
        surfaceTint: AppColors.lightPrimary,
      );

  static ColorScheme get darkColorScheme => const ColorScheme(
        brightness: Brightness.dark,
        primary: AppColors.darkPrimary,
        onPrimary: Color(0xFF001C39),
        primaryContainer: Color(0xFF224874),
        onPrimaryContainer: Color(0xFFD4E3FF),
        secondary: AppColors.darkSuccess,
        onSecondary: Color(0xFF00210F),
        secondaryContainer: Color(0xFF0F5133),
        onSecondaryContainer: Color(0xFFC8F0D6),
        tertiary: AppColors.darkWarning,
        onTertiary: Color(0xFF3A2500),
        tertiaryContainer: Color(0xFF5C4300),
        onTertiaryContainer: Color(0xFFFFE1B8),
        error: AppColors.darkDanger,
        onError: Color(0xFF690005),
        errorContainer: Color(0xFF93000A),
        onErrorContainer: Color(0xFFFFDAD6),
        surface: AppColors.darkBackground,
        onSurface: AppColors.darkTextPrimary,
        surfaceContainerLowest: Color(0xFF0A0C0D),
        surfaceContainerLow: Color(0xFF191C1E),
        surfaceContainer: AppColors.darkSurface,
        surfaceContainerHigh: Color(0xFF282B2D),
        surfaceContainerHighest: Color(0xFF333638),
        onSurfaceVariant: AppColors.darkTextSecondary,
        outline: Color(0xFF8D9199),
        outlineVariant: Color(0xFF43474F),
        shadow: Colors.black,
        scrim: Colors.black,
        inverseSurface: Color(0xFFE0E3E5),
        onInverseSurface: AppColors.lightTextPrimary,
        inversePrimary: AppColors.lightPrimary,
        surfaceTint: AppColors.darkPrimary,
      );

  static TextTheme _textTheme(ColorScheme scheme) {
    final base = TextTheme(
      headlineLarge: AppTextStyles.displayLarge(color: scheme.onSurface),
      headlineMedium: GoogleFonts.manrope(fontSize: 24, height: 32 / 24, fontWeight: FontWeight.w700, color: scheme.onSurface),
      headlineSmall: AppTextStyles.headingMedium(color: scheme.onSurface),
      titleMedium: GoogleFonts.manrope(fontSize: 16, height: 24 / 16, fontWeight: FontWeight.w700, color: scheme.onSurface),
      bodyLarge: GoogleFonts.inter(fontSize: 16, height: 24 / 16, fontWeight: FontWeight.w400, color: scheme.onSurface),
      bodyMedium: AppTextStyles.bodyMedium(color: scheme.onSurface),
      bodySmall: AppTextStyles.caption(color: scheme.onSurfaceVariant),
      labelLarge: GoogleFonts.inter(fontSize: 14, height: 20 / 14, letterSpacing: 0.1, fontWeight: FontWeight.w600, color: scheme.onSurface),
      labelSmall: GoogleFonts.inter(fontSize: 12, height: 16 / 12, fontWeight: FontWeight.w600, color: scheme.onSurface),
    );
    return base;
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
        backgroundColor: scheme.surface.withValues(alpha: 0.96),
        surfaceTintColor: Colors.transparent,
        foregroundColor: scheme.onSurface,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: GoogleFonts.manrope(
          fontSize: 20,
          fontWeight: FontWeight.w700,
          color: scheme.onSurface,
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: scheme.surfaceContainerLowest,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.card),
          side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.4)),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: scheme.surfaceContainerHigh,
        labelStyle: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 13),
        selectedColor: scheme.primary,
        shape: const StadiumBorder(),
        side: BorderSide.none,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm + 4, vertical: AppSpacing.sm),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: scheme.primary,
          foregroundColor: scheme.onPrimary,
          elevation: 1,
          minimumSize: const Size(0, 48),
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm + 6, horizontal: AppSpacing.md),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.button)),
          textStyle: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 15),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: scheme.primary,
          minimumSize: const Size(0, 48),
          side: BorderSide(color: scheme.primary, width: 1.5),
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm + 6, horizontal: AppSpacing.md),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.button)),
          textStyle: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 15),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: scheme.primary,
          minimumSize: const Size(0, 48),
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
          textStyle: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 15),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: scheme.tertiary,
        foregroundColor: scheme.onTertiary,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainerLowest,
        hintStyle: GoogleFonts.inter(color: scheme.outline),
        contentPadding: const EdgeInsets.symmetric(vertical: AppSpacing.sm + 6, horizontal: AppSpacing.md),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.button),
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.button),
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.button),
          borderSide: BorderSide(color: scheme.primary, width: 1.5),
        ),
      ),
      dividerTheme: DividerThemeData(color: scheme.outlineVariant.withValues(alpha: 0.6), space: 1),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: scheme.surfaceContainer,
        indicatorColor: scheme.primaryContainer,
        elevation: 4,
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return GoogleFonts.inter(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: selected ? scheme.primary : scheme.onSurfaceVariant,
          );
        }),
      ),
    );
  }
}
