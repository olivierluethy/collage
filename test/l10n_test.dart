import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:collage/l10n/app_localizations.dart';

/// Collects `{placeholder}` names used in [value].
Set<String> _placeholders(String value) =>
    RegExp(r'\{(\w+)\}').allMatches(value).map((m) => m.group(1)!).toSet();

void main() {
  group('localization coverage', () {
    final en = AppLocalizations.maps['en']!;

    test('every supported language has a locale map', () {
      for (final lang in AppLocalizations.languages) {
        expect(AppLocalizations.maps.containsKey(lang.code), isTrue,
            reason: 'no map for ${lang.code}');
      }
      expect(AppLocalizations.maps.length, AppLocalizations.languages.length);
      expect(AppLocalizations.supportedLocales.length,
          AppLocalizations.languages.length);
    });

    test('every locale has exactly the English key set', () {
      final enKeys = en.keys.toSet();
      AppLocalizations.maps.forEach((code, map) {
        expect(map.keys.toSet(), enKeys,
            reason: 'locale "$code" key set differs from English');
      });
    });

    test('placeholders match English in every locale', () {
      AppLocalizations.maps.forEach((code, map) {
        map.forEach((key, value) {
          expect(_placeholders(value), _placeholders(en[key]!),
              reason: 'placeholders differ for "$code"/"$key"');
        });
      });
    });

    test('no translation is empty', () {
      AppLocalizations.maps.forEach((code, map) {
        map.forEach((key, value) {
          expect(value.trim().isNotEmpty, isTrue,
              reason: 'empty value for "$code"/"$key"');
        });
      });
    });

    test('known key resolves; an unknown key trips the debug assertion', () {
      final l = AppLocalizations(const Locale('en'));
      expect(l.t('save'), 'Save');
      // Unknown keys assert in debug (they fall back to the key only in release).
      expect(() => l.t('definitelyNotAKey'), throwsAssertionError);
    });

    test('a translated locale differs from English for a sample key', () {
      expect(AppLocalizations(const Locale('ru')).t('save'), isNot('Save'));
    });
  });
}
