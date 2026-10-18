import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:collage/services/prefs_service.dart';
import 'package:collage/state/providers.dart';
import 'package:collage/state/settings.dart';

void main() {
  late PrefsService prefs;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await PrefsService.create();
  });

  ProviderContainer container() {
    final c = ProviderContainer(overrides: [prefsProvider.overrideWithValue(prefs)]);
    addTearDown(c.dispose);
    return c;
  }

  test('defaults to system theme and device language', () {
    final c = container();
    final s = c.read(settingsProvider);
    expect(s.themeMode, ThemeMode.system);
    expect(s.locale, isNull);
  });

  test('theme mode is persisted and published', () {
    final c = container();
    c.read(settingsProvider.notifier).setThemeMode(ThemeMode.light);
    expect(c.read(settingsProvider).themeMode, ThemeMode.light);
    expect(prefs.themeModeName, 'light');
  });

  test('language is persisted and published', () {
    final c = container();
    c.read(settingsProvider.notifier).setLocale(const Locale('ru'));
    expect(c.read(settingsProvider).locale, const Locale('ru'));
    expect(prefs.localeCode, 'ru');

    c.read(settingsProvider.notifier).setLocale(null);
    expect(c.read(settingsProvider).locale, isNull);
    expect(prefs.localeCode, isNull);
  });

  test('persisted values are restored on a fresh container', () async {
    final c1 = container();
    c1.read(settingsProvider.notifier).setThemeMode(ThemeMode.dark);
    c1.read(settingsProvider.notifier).setLocale(const Locale('de'));

    final c2 = container();
    final s = c2.read(settingsProvider);
    expect(s.themeMode, ThemeMode.dark);
    expect(s.locale, const Locale('de'));
  });
}
