import 'package:flutter/material.dart';

/// The app's colour palette, provided as a [ThemeExtension] so every widget can
/// read the live colours with `context.colors` and rebuild automatically when
/// the theme (dark ⇄ light) changes.
///
/// [AppPalette.dark] is the original "Darkroom" palette; [AppPalette.light] is
/// its warm "lightbox" counterpart. Field names match the old `AppColors`
/// constants so call sites read the same (`context.colors.ink`, etc.).
@immutable
class AppPalette extends ThemeExtension<AppPalette> {
  const AppPalette({
    required this.ink,
    required this.inkCanvas,
    required this.surface,
    required this.surfaceHigh,
    required this.surfaceInput,
    required this.line,
    required this.lineStrong,
    required this.textHi,
    required this.textMid,
    required this.textLo,
    required this.textDisabled,
    required this.amber,
    required this.amberPressed,
    required this.amberBright,
    required this.onAmber,
    required this.amberTint,
    required this.amberGlow,
    required this.success,
    required this.danger,
    required this.onDanger,
    required this.info,
    required this.warning,
    required this.scrim,
    required this.pressLight,
  });

  final Color ink;
  final Color inkCanvas;
  final Color surface;
  final Color surfaceHigh;
  final Color surfaceInput;
  final Color line;
  final Color lineStrong;
  final Color textHi;
  final Color textMid;
  final Color textLo;
  final Color textDisabled;
  final Color amber;
  final Color amberPressed;
  final Color amberBright;
  final Color onAmber;
  final Color amberTint;
  final Color amberGlow;
  final Color success;
  final Color danger;
  final Color onDanger;
  final Color info;
  final Color warning;
  final Color scrim;
  final Color pressLight;

  /// Warm near-black "Darkroom" chrome — the product's original look.
  static const dark = AppPalette(
    ink: Color(0xFF131110),
    inkCanvas: Color(0xFF1A1714),
    surface: Color(0xFF211D19),
    surfaceHigh: Color(0xFF2A2521),
    surfaceInput: Color(0xFF332D28),
    line: Color(0xFF3D362F),
    lineStrong: Color(0xFF4E463D),
    textHi: Color(0xFFF5EFE7),
    textMid: Color(0xFFB6AB9D),
    textLo: Color(0xFF8A7F71),
    textDisabled: Color(0xFF5E564C),
    amber: Color(0xFFFFB454),
    amberPressed: Color(0xFFF59E2E),
    amberBright: Color(0xFFFFC97A),
    onAmber: Color(0xFF2A1B08),
    amberTint: Color(0x1FFFB454),
    amberGlow: Color(0x52FFB454),
    success: Color(0xFF6FD08C),
    danger: Color(0xFFFF6B5E),
    onDanger: Color(0xFF2A0E0B),
    info: Color(0xFF6FB2FF),
    warning: Color(0xFFE7B84B),
    scrim: Color(0xB8131110),
    pressLight: Color(0x14FFFFFF),
  );

  /// Warm off-white "lightbox" paper — same amber safelight, daylight surfaces.
  static const light = AppPalette(
    ink: Color(0xFFF7F3ED),
    inkCanvas: Color(0xFFEDE6DC),
    surface: Color(0xFFFFFFFF),
    surfaceHigh: Color(0xFFF1EAE0),
    surfaceInput: Color(0xFFE8DFD3),
    line: Color(0xFFDCD1C2),
    lineStrong: Color(0xFFC4B6A3),
    textHi: Color(0xFF221C15),
    textMid: Color(0xFF6A6155),
    textLo: Color(0xFF8A8174),
    textDisabled: Color(0xFFB4AA9C),
    amber: Color(0xFFE08A1E),
    amberPressed: Color(0xFFC97812),
    amberBright: Color(0xFFF0AE4E),
    onAmber: Color(0xFF2A1B08),
    amberTint: Color(0x24E08A1E),
    amberGlow: Color(0x59E08A1E),
    success: Color(0xFF2E9B57),
    danger: Color(0xFFD63B2F),
    onDanger: Color(0xFFFFFFFF),
    info: Color(0xFF2F6FD0),
    warning: Color(0xFFB07C0A),
    scrim: Color(0xB3201C16),
    pressLight: Color(0x14000000),
  );

  @override
  AppPalette copyWith({
    Color? ink,
    Color? inkCanvas,
    Color? surface,
    Color? surfaceHigh,
    Color? surfaceInput,
    Color? line,
    Color? lineStrong,
    Color? textHi,
    Color? textMid,
    Color? textLo,
    Color? textDisabled,
    Color? amber,
    Color? amberPressed,
    Color? amberBright,
    Color? onAmber,
    Color? amberTint,
    Color? amberGlow,
    Color? success,
    Color? danger,
    Color? onDanger,
    Color? info,
    Color? warning,
    Color? scrim,
    Color? pressLight,
  }) {
    return AppPalette(
      ink: ink ?? this.ink,
      inkCanvas: inkCanvas ?? this.inkCanvas,
      surface: surface ?? this.surface,
      surfaceHigh: surfaceHigh ?? this.surfaceHigh,
      surfaceInput: surfaceInput ?? this.surfaceInput,
      line: line ?? this.line,
      lineStrong: lineStrong ?? this.lineStrong,
      textHi: textHi ?? this.textHi,
      textMid: textMid ?? this.textMid,
      textLo: textLo ?? this.textLo,
      textDisabled: textDisabled ?? this.textDisabled,
      amber: amber ?? this.amber,
      amberPressed: amberPressed ?? this.amberPressed,
      amberBright: amberBright ?? this.amberBright,
      onAmber: onAmber ?? this.onAmber,
      amberTint: amberTint ?? this.amberTint,
      amberGlow: amberGlow ?? this.amberGlow,
      success: success ?? this.success,
      danger: danger ?? this.danger,
      onDanger: onDanger ?? this.onDanger,
      info: info ?? this.info,
      warning: warning ?? this.warning,
      scrim: scrim ?? this.scrim,
      pressLight: pressLight ?? this.pressLight,
    );
  }

  @override
  AppPalette lerp(ThemeExtension<AppPalette>? other, double t) {
    if (other is! AppPalette) return this;
    Color c(Color a, Color b) => Color.lerp(a, b, t)!;
    return AppPalette(
      ink: c(ink, other.ink),
      inkCanvas: c(inkCanvas, other.inkCanvas),
      surface: c(surface, other.surface),
      surfaceHigh: c(surfaceHigh, other.surfaceHigh),
      surfaceInput: c(surfaceInput, other.surfaceInput),
      line: c(line, other.line),
      lineStrong: c(lineStrong, other.lineStrong),
      textHi: c(textHi, other.textHi),
      textMid: c(textMid, other.textMid),
      textLo: c(textLo, other.textLo),
      textDisabled: c(textDisabled, other.textDisabled),
      amber: c(amber, other.amber),
      amberPressed: c(amberPressed, other.amberPressed),
      amberBright: c(amberBright, other.amberBright),
      onAmber: c(onAmber, other.onAmber),
      amberTint: c(amberTint, other.amberTint),
      amberGlow: c(amberGlow, other.amberGlow),
      success: c(success, other.success),
      danger: c(danger, other.danger),
      onDanger: c(onDanger, other.onDanger),
      info: c(info, other.info),
      warning: c(warning, other.warning),
      scrim: c(scrim, other.scrim),
      pressLight: c(pressLight, other.pressLight),
    );
  }
}

/// Read the live palette: `context.colors.amber`. Falls back to the dark
/// palette when no [AppPalette] extension is installed (e.g. a bare
/// `MaterialApp` in a test).
extension PaletteContext on BuildContext {
  AppPalette get colors =>
      Theme.of(this).extension<AppPalette>() ?? AppPalette.dark;
}
