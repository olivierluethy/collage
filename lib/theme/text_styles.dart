import 'package:flutter/widgets.dart';
import 'package:google_fonts/google_fonts.dart';

import 'tokens.dart';

/// Typography from docs/STYLEGUIDE.md.
///
/// Three roles: Fraunces (display), Inter (UI/body), JetBrains Mono (specs).
class AppText {
  AppText._();

  // Display — Fraunces (warm editorial serif), used with restraint.
  static TextStyle get displayLg => GoogleFonts.fraunces(
        fontSize: 34,
        height: 1.15,
        letterSpacing: -0.5,
        fontWeight: FontWeight.w600,
        color: AppColors.textHi,
      );

  static TextStyle get displayMd => GoogleFonts.fraunces(
        fontSize: 26,
        height: 1.20,
        letterSpacing: -0.3,
        fontWeight: FontWeight.w600,
        color: AppColors.textHi,
      );

  // Titles / body / labels — Inter (max legibility).
  static TextStyle get titleLg => GoogleFonts.inter(
        fontSize: 22,
        height: 1.25,
        fontWeight: FontWeight.w600,
        color: AppColors.textHi,
      );

  static TextStyle get titleMd => GoogleFonts.inter(
        fontSize: 18,
        height: 1.30,
        fontWeight: FontWeight.w600,
        color: AppColors.textHi,
      );

  static TextStyle get bodyLg => GoogleFonts.inter(
        fontSize: 16,
        height: 1.50,
        fontWeight: FontWeight.w400,
        color: AppColors.textHi,
      );

  static TextStyle get bodyMd => GoogleFonts.inter(
        fontSize: 14,
        height: 1.45,
        fontWeight: FontWeight.w400,
        color: AppColors.textMid,
      );

  static TextStyle get labelLg => GoogleFonts.inter(
        fontSize: 15,
        height: 1.20,
        letterSpacing: 0.1,
        fontWeight: FontWeight.w600,
        color: AppColors.textHi,
      );

  static TextStyle get labelMd => GoogleFonts.inter(
        fontSize: 13,
        height: 1.20,
        letterSpacing: 0.3,
        fontWeight: FontWeight.w600,
        color: AppColors.textMid,
      );

  static TextStyle get caption => GoogleFonts.inter(
        fontSize: 12,
        height: 1.40,
        letterSpacing: 0.2,
        fontWeight: FontWeight.w500,
        color: AppColors.textLo,
      );

  static TextStyle get overline => GoogleFonts.inter(
        fontSize: 11,
        height: 1.20,
        letterSpacing: 1.2,
        fontWeight: FontWeight.w700,
        color: AppColors.textLo,
      );

  // Spec / numeric — JetBrains Mono for ratios, dims, counters.
  static TextStyle get spec => GoogleFonts.jetBrainsMono(
        fontSize: 13,
        height: 1.10,
        letterSpacing: 0.5,
        fontWeight: FontWeight.w500,
        color: AppColors.textMid,
      );
}
