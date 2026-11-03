import 'package:flutter_test/flutter_test.dart';

import 'package:collage/l10n/app_localizations.dart';
import 'package:collage/l10n/locales/de.dart' as de_locale;
import 'package:collage/l10n/locales/en.dart' as en_locale;
import 'package:collage/l10n/strings/arrange.dart';
import 'package:collage/l10n/strings/discover.dart';
import 'package:collage/l10n/strings/editor.dart';
import 'package:collage/l10n/strings/export.dart';
import 'package:collage/l10n/strings/library.dart';
import 'package:collage/l10n/strings/picker.dart';
import 'package:collage/l10n/strings/templates.dart';

/// One feature-area string set and where it lives, so failures point at the
/// source file instead of the merged map that l10n_test.dart checks.
class _Area {
  const _Area(this.file, this.name, this.map);
  final String file;
  final String name;
  final Map<String, Map<String, String>> map;
  String get where => 'lib/l10n/strings/$file ($name)';
}

const _areas = [
  _Area('arrange.dart', 'arrangeStrings', arrangeStrings),
  _Area('discover.dart', 'discoverStrings', discoverStrings),
  _Area('editor.dart', 'editorStrings', editorStrings),
  _Area('export.dart', 'exportStrings', exportStrings),
  _Area('library.dart', 'libraryStrings', libraryStrings),
  _Area('picker.dart', 'pickerStrings', pickerStrings),
  _Area('templates.dart', 'templatesStrings', templatesStrings),
];

Set<String> _placeholders(String v) => RegExp(r'\{(\w+)\}').allMatches(v).map((m) => m.group(1)!).toSet();

String _list(Iterable<String> s) => (s.toList()..sort()).join(', ');

void main() {
  final codes = {for (final l in AppLocalizations.languages) l.code};

  test('the language list has no duplicate codes', () {
    expect(codes.length, AppLocalizations.languages.length);
  });

  for (final area in _areas) {
    group(area.where, () {
      test('has exactly the supported language codes', () {
        final have = area.map.keys.toSet();
        final missing = codes.difference(have);
        final extra = have.difference(codes);
        expect(missing.isEmpty && extra.isEmpty, isTrue,
            reason: '${area.where}: missing languages [${_list(missing)}], '
                'unexpected languages [${_list(extra)}]');
      });

      test('every language has exactly the English key set', () {
        final en = area.map['en']!.keys.toSet();
        final problems = <String>[];
        area.map.forEach((code, m) {
          final keys = m.keys.toSet();
          final missing = en.difference(keys);
          final extra = keys.difference(en);
          if (missing.isNotEmpty) problems.add('$code is missing [${_list(missing)}]');
          if (extra.isNotEmpty) problems.add('$code has extra [${_list(extra)}]');
        });
        expect(problems, isEmpty, reason: '${area.where}:\n  ${problems.join('\n  ')}');
      });

      test('placeholders match English per key and language', () {
        final en = area.map['en']!;
        final problems = <String>[];
        area.map.forEach((code, m) {
          m.forEach((key, value) {
            final want = en[key];
            if (want == null) return; // reported by the key-set test
            final a = _placeholders(value), b = _placeholders(want);
            if (a.length != b.length || !a.containsAll(b)) {
              problems.add('$code/$key has {${_list(a)}}, English has {${_list(b)}}');
            }
          });
        });
        expect(problems, isEmpty, reason: '${area.where}:\n  ${problems.join('\n  ')}');
      });

      test('no value is empty', () {
        final problems = <String>[
          for (final e in area.map.entries)
            for (final kv in e.value.entries)
              if (kv.value.trim().isEmpty) '${e.key}/${kv.key}',
        ];
        expect(problems, isEmpty, reason: '${area.where}: empty values ${problems.join(', ')}');
      });

      test('German uses Swiss spelling (no ß)', () {
        final bad = [
          for (final kv in (area.map['de'] ?? const {}).entries)
            if (kv.value.contains('ß')) '${kv.key}: "${kv.value}"',
        ];
        expect(bad, isEmpty, reason: '${area.where} de:\n  ${bad.join('\n  ')}');
      });
    });
  }

  test('lib/l10n/locales/de.dart uses Swiss spelling (no ß)', () {
    final bad = [
      for (final kv in de_locale.de.entries)
        if (kv.value.contains('ß')) '${kv.key}: "${kv.value}"',
    ];
    expect(bad, isEmpty, reason: 'lib/l10n/locales/de.dart:\n  ${bad.join('\n  ')}');
  });

  test('no key is defined in two strings maps, or in a strings map and locales/en.dart', () {
    // AppLocalizations.maps spreads base + areas in order, so a duplicate key
    // would silently let the later map win. None is intentional today.
    final owner = <String, String>{for (final k in en_locale.en.keys) k: 'lib/l10n/locales/en.dart'};
    final clashes = <String>[];
    for (final area in _areas) {
      for (final k in area.map['en']!.keys) {
        final prev = owner[k];
        if (prev != null) {
          clashes.add('"$k" in ${area.where} and $prev');
        } else {
          owner[k] = area.where;
        }
      }
    }
    expect(clashes, isEmpty, reason: clashes.join('\n'));
  });

  test('no key clashes in any language either (catches keys only added outside English)', () {
    final clashes = <String>[];
    for (final code in codes) {
      final base = AppLocalizations.maps.containsKey(code) ? null : 'no merged map';
      if (base != null) {
        clashes.add('$code: $base');
        continue;
      }
      final seen = <String, String>{};
      for (final area in _areas) {
        for (final k in (area.map[code] ?? const {}).keys) {
          final prev = seen[k];
          if (prev != null) clashes.add('$code/"$k" in ${area.where} and $prev');
          seen[k] = area.where;
        }
      }
    }
    expect(clashes, isEmpty, reason: clashes.join('\n'));
  });

  test('the merged map carries every area value unchanged (no shadowing)', () {
    final problems = <String>[];
    for (final area in _areas) {
      area.map.forEach((code, m) {
        final merged = AppLocalizations.maps[code];
        if (merged == null) return;
        m.forEach((k, v) {
          if (merged[k] != v) problems.add('$code/$k from ${area.where} is shadowed');
        });
      });
    }
    expect(problems, isEmpty, reason: problems.join('\n'));
  });
}
