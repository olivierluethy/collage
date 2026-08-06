import 'package:flutter/material.dart';

import 'text_styles.dart';
import 'tokens.dart';

/// Dark-only Material 3 theme built from the Darkroom tokens.
///
/// There is intentionally NO light theme (see docs/STYLEGUIDE.md).
class AppTheme {
  AppTheme._();

  static ThemeData get dark {
    const scheme = ColorScheme.dark(
      brightness: Brightness.dark,
      primary: AppColors.amber,
      onPrimary: AppColors.onAmber,
      primaryContainer: AppColors.amberPressed,
      onPrimaryContainer: AppColors.onAmber,
      secondary: AppColors.amberBright,
      onSecondary: AppColors.onAmber,
      surface: AppColors.surface,
      onSurface: AppColors.textHi,
      surfaceContainerHighest: AppColors.surfaceHigh,
      surfaceContainerHigh: AppColors.surfaceHigh,
      surfaceContainer: AppColors.surface,
      onSurfaceVariant: AppColors.textMid,
      error: AppColors.danger,
      onError: AppColors.onDanger,
      outline: AppColors.line,
      outlineVariant: AppColors.lineStrong,
      scrim: AppColors.scrim,
    );

    final base = ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: scheme,
      scaffoldBackgroundColor: AppColors.ink,
      canvasColor: AppColors.ink,
      splashColor: AppColors.amberTint,
      highlightColor: AppColors.pressLight,
      dividerColor: AppColors.line,
    );

    return base.copyWith(
      textTheme: base.textTheme.copyWith(
        displayLarge: AppText.displayLg,
        displayMedium: AppText.displayMd,
        headlineMedium: AppText.displayMd,
        titleLarge: AppText.titleLg,
        titleMedium: AppText.titleMd,
        bodyLarge: AppText.bodyLg,
        bodyMedium: AppText.bodyMd,
        labelLarge: AppText.labelLg,
        labelMedium: AppText.labelMd,
        labelSmall: AppText.caption,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: AppColors.ink,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: AppText.titleLg,
        iconTheme: const IconThemeData(color: AppColors.textHi),
      ),
      dividerTheme: const DividerThemeData(
        color: AppColors.line,
        thickness: 1,
        space: 1,
      ),
      iconTheme: const IconThemeData(color: AppColors.textMid),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.amber,
          foregroundColor: AppColors.onAmber,
          disabledBackgroundColor: AppColors.surfaceHigh,
          disabledForegroundColor: AppColors.textDisabled,
          minimumSize: const Size(0, Sizes.primaryButtonHeight),
          padding: const EdgeInsets.symmetric(horizontal: Space.xl),
          elevation: 0,
          textStyle: AppText.labelLg,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(Radii.control),
          ),
        ).copyWith(
          overlayColor: WidgetStateProperty.all(AppColors.amberTint),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.amber,
          foregroundColor: AppColors.onAmber,
          minimumSize: const Size(0, Sizes.primaryButtonHeight),
          textStyle: AppText.labelLg,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(Radii.control),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.textHi,
          backgroundColor: AppColors.surfaceHigh,
          minimumSize: const Size(0, Sizes.primaryButtonHeight),
          textStyle: AppText.labelLg,
          side: const BorderSide(color: AppColors.line),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(Radii.control),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.textMid,
          textStyle: AppText.labelLg,
          minimumSize: const Size(0, Sizes.touchTarget),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(Radii.control),
          ),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: AppColors.textMid,
          minimumSize: const Size(Sizes.touchTarget, Sizes.touchTarget),
        ),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: AppColors.amber,
        foregroundColor: AppColors.onAmber,
        extendedTextStyle: TextStyle(
          fontWeight: FontWeight.w600,
          fontSize: 15,
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: AppColors.surfaceInput,
        selectedColor: AppColors.amberTint,
        labelStyle: AppText.labelMd,
        side: BorderSide.none,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Radii.chip),
        ),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        modalBackgroundColor: AppColors.surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(Radii.sheetTop)),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: AppColors.surfaceHigh,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: AppText.titleMd,
        contentTextStyle: AppText.bodyMd,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Radii.sheet),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: AppColors.surfaceHigh,
        contentTextStyle: AppText.bodyMd.copyWith(color: AppColors.textHi),
        actionTextColor: AppColors.amber,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Radii.control),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surfaceInput,
        hintStyle: AppText.bodyMd.copyWith(color: AppColors.textLo),
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
          borderSide: const BorderSide(color: AppColors.line),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(Radii.control),
          borderSide: const BorderSide(color: AppColors.amber, width: 2),
        ),
      ),
      sliderTheme: const SliderThemeData(
        activeTrackColor: AppColors.amber,
        inactiveTrackColor: AppColors.surfaceInput,
        thumbColor: AppColors.amber,
        overlayColor: AppColors.amberTint,
        trackHeight: 3,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected)
              ? AppColors.onAmber
              : AppColors.textMid,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected)
              ? AppColors.amber
              : AppColors.surfaceInput,
        ),
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: AppColors.amber,
        unselectedLabelColor: AppColors.textMid,
        labelStyle: AppText.labelMd,
        unselectedLabelStyle: AppText.labelMd,
        indicatorColor: AppColors.amber,
        dividerColor: AppColors.line,
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: AppColors.surfaceHigh,
          borderRadius: BorderRadius.circular(Radii.control),
          border: Border.all(color: AppColors.amber, width: 1),
        ),
        textStyle: AppText.caption.copyWith(color: AppColors.textHi),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: AppColors.amber,
      ),
    );
  }
}
