import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../../state/settings.dart';
import '../../theme/palette.dart';

/// The language currently in effect: the user's choice, else the device's.
String activeLanguageCode(BuildContext context, WidgetRef ref) =>
    ref.watch(settingsProvider).locale?.languageCode ??
    Localizations.localeOf(context).languageCode;

/// The endonym for [code] ("Deutsch"), or null for an unknown code.
String? languageName(String code) {
  for (final lang in AppLocalizations.languages) {
    if (lang.code == code) return lang.name;
  }
  return null;
}

/// Language picker sheet, shared by onboarding and the More tab.
Future<void> showLanguagePicker(BuildContext context, WidgetRef ref) async {
  final activeCode = ref.read(settingsProvider).locale?.languageCode ??
      Localizations.localeOf(context).languageCode;
  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (sheetContext) => SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(sheetContext).size.height * 0.7),
        child: ListView(
          shrinkWrap: true,
          children: [
            for (final lang in AppLocalizations.languages)
              ListTile(
                title: Text(lang.name),
                trailing: lang.code == activeCode
                    ? Icon(Icons.check_rounded, color: sheetContext.colors.amber)
                    : null,
                onTap: () {
                  ref.read(settingsProvider.notifier).setLocale(Locale(lang.code));
                  Navigator.of(sheetContext).pop();
                },
              ),
          ],
        ),
      ),
    ),
  );
}

/// Theme picker sheet: follow the system, light or dark.
Future<void> showThemePicker(BuildContext context, WidgetRef ref) async {
  final l = context.l10n;
  final current = ref.read(settingsProvider).themeMode;
  final options = <(ThemeMode, String, IconData)>[
    (ThemeMode.system, l.t('themeSystem'), Icons.brightness_auto_rounded),
    (ThemeMode.light, l.t('themeLight'), Icons.light_mode_outlined),
    (ThemeMode.dark, l.t('themeDark'), Icons.dark_mode_outlined),
  ];
  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final (mode, label, icon) in options)
            ListTile(
              leading: Icon(icon),
              title: Text(label),
              trailing: mode == current
                  ? Icon(Icons.check_rounded, color: sheetContext.colors.amber)
                  : null,
              onTap: () {
                ref.read(settingsProvider.notifier).setThemeMode(mode);
                Navigator.of(sheetContext).pop();
              },
            ),
        ],
      ),
    ),
  );
}

/// Human label of the current theme mode.
String themeLabel(BuildContext context, ThemeMode mode) => switch (mode) {
      ThemeMode.light => context.l10n.t('themeLight'),
      ThemeMode.dark => context.l10n.t('themeDark'),
      ThemeMode.system => context.l10n.t('themeSystem'),
    };
