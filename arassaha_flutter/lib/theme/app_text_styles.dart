import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Tipografi ölçeği: başlıklar Manrope, gövde metni Inter, veri/kod alanları
/// (koordinat, seri no, tarih-saat) JetBrains Mono. Bkz. DESIGN_SYSTEM.md A.2.
class AppTextStyles {
  AppTextStyles._();

  static TextStyle displayLarge({required Color color}) => GoogleFonts.manrope(
        fontSize: 32,
        height: 40 / 32,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.3,
        color: color,
      );

  static TextStyle headingMedium({required Color color}) => GoogleFonts.manrope(
        fontSize: 20,
        height: 28 / 20,
        fontWeight: FontWeight.w600,
        color: color,
      );

  static TextStyle bodyMedium({required Color color}) => GoogleFonts.inter(
        fontSize: 14,
        height: 20 / 14,
        fontWeight: FontWeight.w400,
        color: color,
      );

  static TextStyle caption({required Color color}) => GoogleFonts.inter(
        fontSize: 12,
        height: 16 / 12,
        fontWeight: FontWeight.w400,
        color: color,
      );

  static TextStyle dataMono({required Color color}) => GoogleFonts.jetBrainsMono(
        fontSize: 13,
        height: 18 / 13,
        fontWeight: FontWeight.w500,
        color: color,
      );
}
