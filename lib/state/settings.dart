import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'providers.dart';

/// App-wide preferences the Information screen edits: theme mode and language.
@immutable
class Settings {
  const Settings({required this.themeMode, required this.locale});
  final ThemeMode themeMode;
  final Locale? locale; // null = follow the device

  Settings copyWith({ThemeMode? themeMode, Locale? locale, bool clearLocale = false}) =>
      Settings(
        themeMode: themeMode ?? this.themeMode,
        locale: clearLocale ? null : (locale ?? this.locale),
      );
}

class SettingsNotifier extends Notifier<Settings> {
  @override
  Settings build() {
    final p = ref.read(prefsProvider);
    return Settings(
      themeMode: _parseTheme(p.themeModeName),
      locale: _parseLocale(p.localeCode),
    );
  }

  void setThemeMode(ThemeMode mode) {
    ref.read(prefsProvider).setThemeModeName(mode.name);
    state = state.copyWith(themeMode: mode);
  }

  /// [locale] == null follows the device language.
  void setLocale(Locale? locale) {
    ref.read(prefsProvider).setLocaleCode(locale?.languageCode);
    state = locale == null
        ? state.copyWith(clearLocale: true)
        : state.copyWith(locale: locale);
  }

  static ThemeMode _parseTheme(String? name) => switch (name) {
        'light' => ThemeMode.light,
        'dark' => ThemeMode.dark,
        _ => ThemeMode.system,
      };

  static Locale? _parseLocale(String? code) =>
      (code == null || code.isEmpty) ? null : Locale(code);
}

final settingsProvider =
    NotifierProvider<SettingsNotifier, Settings>(SettingsNotifier.new);
