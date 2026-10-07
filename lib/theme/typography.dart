import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'palette.dart';

/// Typography from docs/STYLEGUIDE.md, provided as a [ThemeExtension] so the
/// styles pick up the live palette colours. Read them with `context.text`.
///
/// Three roles: Fraunces (display), Inter (UI/body), JetBrains Mono (specs).
class AppTypography extends ThemeExtension<AppTypography> {
  AppTypography._({
    required this.displayLg,
    required this.displayMd,
    required this.titleLg,
    required this.titleMd,
    required this.bodyLg,
    required this.bodyMd,
    required this.labelLg,
    required this.labelMd,
    required this.caption,
    required this.overline,
    required this.spec,
  });

  factory AppTypography.from(AppPalette p) => AppTypography._(
        displayLg: GoogleFonts.fraunces(
          fontSize: 34,
          height: 1.15,
          letterSpacing: -0.5,
          fontWeight: FontWeight.w600,
          color: p.textHi,
        ),
        displayMd: GoogleFonts.fraunces(
          fontSize: 26,
          height: 1.20,
          letterSpacing: -0.3,
          fontWeight: FontWeight.w600,
          color: p.textHi,
        ),
        titleLg: GoogleFonts.inter(
          fontSize: 22,
          height: 1.25,
          fontWeight: FontWeight.w600,
          color: p.textHi,
        ),
        titleMd: GoogleFonts.inter(
          fontSize: 18,
          height: 1.30,
          fontWeight: FontWeight.w600,
          color: p.textHi,
        ),
        bodyLg: GoogleFonts.inter(
          fontSize: 16,
          height: 1.50,
          fontWeight: FontWeight.w400,
          color: p.textHi,
        ),
        bodyMd: GoogleFonts.inter(
          fontSize: 14,
          height: 1.45,
          fontWeight: FontWeight.w400,
          color: p.textMid,
        ),
        labelLg: GoogleFonts.inter(
          fontSize: 15,
          height: 1.20,
          letterSpacing: 0.1,
          fontWeight: FontWeight.w600,
          color: p.textHi,
        ),
        labelMd: GoogleFonts.inter(
          fontSize: 13,
          height: 1.20,
          letterSpacing: 0.3,
          fontWeight: FontWeight.w600,
          color: p.textMid,
        ),
        caption: GoogleFonts.inter(
          fontSize: 12,
          height: 1.40,
          letterSpacing: 0.2,
          fontWeight: FontWeight.w500,
          color: p.textLo,
        ),
        overline: GoogleFonts.inter(
          fontSize: 11,
          height: 1.20,
          letterSpacing: 1.2,
          fontWeight: FontWeight.w700,
          color: p.textLo,
        ),
        // Spec / numeric — JetBrains Mono for ratios, dims, counters.
        spec: GoogleFonts.jetBrainsMono(
          fontSize: 13,
          height: 1.10,
          letterSpacing: 0.5,
          fontWeight: FontWeight.w500,
          color: p.textMid,
        ),
      );

  final TextStyle displayLg;
  final TextStyle displayMd;
  final TextStyle titleLg;
  final TextStyle titleMd;
  final TextStyle bodyLg;
  final TextStyle bodyMd;
  final TextStyle labelLg;
  final TextStyle labelMd;
  final TextStyle caption;
  final TextStyle overline;
  final TextStyle spec;

  @override
  AppTypography copyWith({
    TextStyle? displayLg,
    TextStyle? displayMd,
    TextStyle? titleLg,
    TextStyle? titleMd,
    TextStyle? bodyLg,
    TextStyle? bodyMd,
    TextStyle? labelLg,
    TextStyle? labelMd,
    TextStyle? caption,
    TextStyle? overline,
    TextStyle? spec,
  }) {
    return AppTypography._(
      displayLg: displayLg ?? this.displayLg,
      displayMd: displayMd ?? this.displayMd,
      titleLg: titleLg ?? this.titleLg,
      titleMd: titleMd ?? this.titleMd,
      bodyLg: bodyLg ?? this.bodyLg,
      bodyMd: bodyMd ?? this.bodyMd,
      labelLg: labelLg ?? this.labelLg,
      labelMd: labelMd ?? this.labelMd,
      caption: caption ?? this.caption,
      overline: overline ?? this.overline,
      spec: spec ?? this.spec,
    );
  }

  @override
  AppTypography lerp(ThemeExtension<AppTypography>? other, double t) {
    if (other is! AppTypography) return this;
    return AppTypography._(
      displayLg: TextStyle.lerp(displayLg, other.displayLg, t)!,
      displayMd: TextStyle.lerp(displayMd, other.displayMd, t)!,
      titleLg: TextStyle.lerp(titleLg, other.titleLg, t)!,
      titleMd: TextStyle.lerp(titleMd, other.titleMd, t)!,
      bodyLg: TextStyle.lerp(bodyLg, other.bodyLg, t)!,
      bodyMd: TextStyle.lerp(bodyMd, other.bodyMd, t)!,
      labelLg: TextStyle.lerp(labelLg, other.labelLg, t)!,
      labelMd: TextStyle.lerp(labelMd, other.labelMd, t)!,
      caption: TextStyle.lerp(caption, other.caption, t)!,
      overline: TextStyle.lerp(overline, other.overline, t)!,
      spec: TextStyle.lerp(spec, other.spec, t)!,
    );
  }
}

/// Read the live typography: `context.text.bodyMd`. Falls back to the dark
/// typography when no [AppTypography] extension is installed.
extension TypographyContext on BuildContext {
  AppTypography get text =>
      Theme.of(this).extension<AppTypography>() ??
      AppTypography.from(AppPalette.dark);
}
