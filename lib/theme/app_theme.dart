import 'package:flutter/material.dart';

import 'palette.dart';
import 'tokens.dart';
import 'typography.dart';

/// Material 3 themes built from the design tokens (docs/STYLEGUIDE.md).
///
/// `AppTheme.dark` is the warm "Darkroom" theme; `AppTheme.light` is the warm
/// "lightbox" counterpart. Both share one builder so they stay in lockstep.
class AppTheme {
  AppTheme._();

  static ThemeData get dark => _build(AppPalette.dark, Brightness.dark);

  static ThemeData get light => _build(AppPalette.light, Brightness.light);

  static ThemeData _build(AppPalette p, Brightness brightness) {
    final t = AppTypography.from(p);
    final scheme = ColorScheme(
      brightness: brightness,
      primary: p.amber,
      onPrimary: p.onAmber,
      primaryContainer: p.amberPressed,
      onPrimaryContainer: p.onAmber,
      secondary: p.amberBright,
      onSecondary: p.onAmber,
      surface: p.surface,
      onSurface: p.textHi,
      surfaceContainerHighest: p.surfaceHigh,
      surfaceContainerHigh: p.surfaceHigh,
      surfaceContainer: p.surface,
      onSurfaceVariant: p.textMid,
      error: p.danger,
      onError: p.onDanger,
      outline: p.line,
      outlineVariant: p.lineStrong,
      scrim: p.scrim,
    );

    final base = ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: p.ink,
      canvasColor: p.ink,
      splashColor: p.amberTint,
      highlightColor: p.pressLight,
      dividerColor: p.line,
      extensions: [p, t],
    );

    return base.copyWith(
      textTheme: base.textTheme.copyWith(
        displayLarge: t.displayLg,
        displayMedium: t.displayMd,
        headlineMedium: t.displayMd,
        titleLarge: t.titleLg,
        titleMedium: t.titleMd,
        bodyLarge: t.bodyLg,
        bodyMedium: t.bodyMd,
        labelLarge: t.labelLg,
        labelMedium: t.labelMd,
        labelSmall: t.caption,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: p.ink,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: t.titleLg,
        iconTheme: IconThemeData(color: p.textHi),
      ),
      dividerTheme: DividerThemeData(
        color: p.line,
        thickness: 1,
        space: 1,
      ),
      iconTheme: IconThemeData(color: p.textMid),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: p.amber,
          foregroundColor: p.onAmber,
          disabledBackgroundColor: p.surfaceHigh,
          disabledForegroundColor: p.textDisabled,
          minimumSize: const Size(0, Sizes.primaryButtonHeight),
          padding: const EdgeInsets.symmetric(horizontal: Space.xl),
          elevation: 0,
          textStyle: t.labelLg,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(Radii.control),
          ),
        ).copyWith(
          overlayColor: WidgetStateProperty.all(p.amberTint),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: p.amber,
          foregroundColor: p.onAmber,
          minimumSize: const Size(0, Sizes.primaryButtonHeight),
          textStyle: t.labelLg,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(Radii.control),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: p.textHi,
          backgroundColor: p.surfaceHigh,
          minimumSize: const Size(0, Sizes.primaryButtonHeight),
          textStyle: t.labelLg,
          side: BorderSide(color: p.line),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(Radii.control),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: p.textMid,
          textStyle: t.labelLg,
          minimumSize: const Size(0, Sizes.touchTarget),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(Radii.control),
          ),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: p.textMid,
          minimumSize: const Size(Sizes.touchTarget, Sizes.touchTarget),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: p.amber,
        foregroundColor: p.onAmber,
        extendedTextStyle: const TextStyle(
          fontWeight: FontWeight.w600,
          fontSize: 15,
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: p.surfaceInput,
        selectedColor: p.amberTint,
        labelStyle: t.labelMd,
        side: BorderSide.none,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Radii.chip),
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: p.surface,
        surfaceTintColor: Colors.transparent,
        modalBackgroundColor: p.surface,
        elevation: 0,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(Radii.sheetTop)),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: p.surfaceHigh,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: t.titleMd,
        contentTextStyle: t.bodyMd,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Radii.sheet),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: p.surfaceHigh,
        contentTextStyle: t.bodyMd.copyWith(color: p.textHi),
        actionTextColor: p.amber,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Radii.control),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: p.surfaceInput,
        hintStyle: t.bodyMd.copyWith(color: p.textLo),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: Space.lg,
          vertical: Space.md,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(Radii.control),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(Radii.control),
          borderSide: BorderSide(color: p.line),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(Radii.control),
          borderSide: BorderSide(color: p.amber, width: 2),
        ),
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: p.amber,
        inactiveTrackColor: p.surfaceInput,
        thumbColor: p.amber,
        overlayColor: p.amberTint,
        trackHeight: 3,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? p.onAmber : p.textMid,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? p.amber : p.surfaceInput,
        ),
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: p.amber,
        unselectedLabelColor: p.textMid,
        labelStyle: t.labelMd,
        unselectedLabelStyle: t.labelMd,
        indicatorColor: p.amber,
        dividerColor: p.line,
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: p.surfaceHigh,
          borderRadius: BorderRadius.circular(Radii.control),
          border: Border.all(color: p.amber, width: 1),
        ),
        textStyle: t.caption.copyWith(color: p.textHi),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(color: p.amber),
    );
  }
}
