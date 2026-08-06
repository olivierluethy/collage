import 'package:flutter/widgets.dart';

/// Design tokens — the machine-readable half of docs/STYLEGUIDE.md.
///
/// Never hardcode a hex, size or duration in a widget. Reference a token here
/// (or the [ThemeData] built from it) so the whole app stays one product.
class AppColors {
  AppColors._();

  // Base & surfaces (warm-neutral "Darkroom")
  static const ink = Color(0xFF131110);
  static const inkCanvas = Color(0xFF1A1714);
  static const surface = Color(0xFF211D19);
  static const surfaceHigh = Color(0xFF2A2521);
  static const surfaceInput = Color(0xFF332D28);
  static const line = Color(0xFF3D362F);
  static const lineStrong = Color(0xFF4E463D);

  // Text & icons
  static const textHi = Color(0xFFF5EFE7);
  static const textMid = Color(0xFFB6AB9D);
  static const textLo = Color(0xFF8A7F71);
  static const textDisabled = Color(0xFF5E564C);

  // Brand accent — Safelight amber
  static const amber = Color(0xFFFFB454);
  static const amberPressed = Color(0xFFF59E2E);
  static const amberBright = Color(0xFFFFC97A);
  static const onAmber = Color(0xFF2A1B08);
  static const amberTint = Color(0x1FFFB454); // 12%
  static const amberGlow = Color(0x52FFB454); // 32%

  // Semantic
  static const success = Color(0xFF6FD08C);
  static const danger = Color(0xFFFF6B5E);
  static const onDanger = Color(0xFF2A0E0B);
  static const info = Color(0xFF6FB2FF);
  static const warning = Color(0xFFE7B84B);

  // Common overlays
  static const scrim = Color(0xB8131110); // ink @72% for coach-mark spotlight
  static const pressLight = Color(0x14FFFFFF); // white @8%
}

/// Spacing scale (dp, base-4).
class Space {
  Space._();
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;
  static const double xxxl = 48;
  static const double huge = 64;

  /// Standard screen gutter.
  static const double gutter = lg;
}

/// Corner radii.
class Radii {
  Radii._();
  static const double chip = 6;
  static const double control = 10;
  static const double card = 14;
  static const double sheet = 20;
  static const double sheetTop = 28;
  static const double pill = 999;

  /// Default photo-slot radius (user-adjustable 0–48 in Borders).
  static const double slotDefault = 8;
}

/// Elevation shadows (subtle on dark; focus uses the amber glow instead).
class Shadows {
  Shadows._();
  static const List<BoxShadow> e1 = [
    BoxShadow(color: Color(0x66000000), blurRadius: 2, offset: Offset(0, 1)),
  ];
  static const List<BoxShadow> e2 = [
    BoxShadow(color: Color(0x80000000), blurRadius: 32, offset: Offset(0, -8)),
  ];
  static const List<BoxShadow> e3 = [
    BoxShadow(color: Color(0x8C000000), blurRadius: 32, offset: Offset(0, 12)),
  ];

  /// Signature "safelight" glow around the selected element / focused field.
  static const List<BoxShadow> focusGlow = [
    BoxShadow(color: AppColors.amberGlow, blurRadius: 20, spreadRadius: 0),
  ];
}

/// Motion durations & curves.
class Motion {
  Motion._();
  static const Duration fast = Duration(milliseconds: 120);
  static const Duration base = Duration(milliseconds: 200);
  static const Duration slow = Duration(milliseconds: 320);
  static const Duration sheet = Duration(milliseconds: 280);

  static const Curve standard = Cubic(0.2, 0, 0, 1);
  static const Curve emphasized = Cubic(0.05, 0.7, 0.1, 1);
}

/// Minimum touch/sizing constants.
class Sizes {
  Sizes._();
  static const double touchTarget = 48;
  static const double primaryButtonHeight = 56;
  static const double handle = 22; // canvas selection handle diameter
}
