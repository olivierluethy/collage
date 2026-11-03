import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:collage/features/library/library_query.dart';
import 'package:collage/l10n/app_localizations.dart';
import 'package:collage/models/collage_project.dart';
import 'package:collage/models/layout_template.dart';
import 'package:collage/widgets/meta_date.dart';

int _ms(int y, int m, int d, [int h = 12, int min = 0]) => DateTime(y, m, d, h, min).millisecondsSinceEpoch;

CollageProject _p(
  String id, {
  String title = 'Collage',
  int? created,
  int? updated,
  String ratio = '1:1',
  String? templateId,
  String? occasionId,
  bool video = false,
}) {
  final c = created ?? _ms(2026, 1, 1);
  return CollageProject(
    id: id,
    title: title,
    createdAt: c,
    updatedAt: updated ?? c,
    ratioLabel: ratio,
    layout: const LayoutTemplate(
      id: 'one',
      name: 'One',
      family: LayoutFamily.grid,
      slots: [LayoutSlot(id: 's1', rect: Rect.fromLTWH(0, 0, 1, 1))],
    ),
    fills: {'s1': SlotFill(assetId: 'a-$id', isVideo: video)},
    elements: [],
    border: BorderSettings(),
    background: BackgroundSettings(),
    templateId: templateId,
    occasionId: occasionId,
  );
}

List<String> _ids(List<CollageProject> l) => [for (final p in l) p.id];

void main() {
  final l = AppLocalizations(const Locale('en'));

  setUpAll(() async {
    await initializeDateFormatting('de');
    await initializeDateFormatting('en');
  });

  group('DatePeriod', () {
    test('day is half-open [midnight, next midnight)', () {
      final p = DatePeriod.day(DateTime(2026, 3, 14, 18, 30));
      expect(p.start, DateTime(2026, 3, 14));
      expect(p.end, DateTime(2026, 3, 15));
      expect(p.contains(DateTime(2026, 3, 14).millisecondsSinceEpoch), isTrue);
      expect(p.contains(DateTime(2026, 3, 14, 23, 59, 59, 999).millisecondsSinceEpoch), isTrue);
      expect(p.contains(DateTime(2026, 3, 15).millisecondsSinceEpoch), isFalse);
      expect(p.contains(DateTime(2026, 3, 13, 23, 59, 59, 999).millisecondsSinceEpoch), isFalse);
    });

    test('day rolls over Dec 31 into the next year and handles leap day', () {
      final nye = DatePeriod.day(DateTime(2025, 12, 31));
      expect(nye.end, DateTime(2026, 1, 1));
      final leap = DatePeriod.day(DateTime(2024, 2, 29));
      expect(leap.end, DateTime(2024, 3, 1));
    });

    test('hour covers exactly one hour, also at 23:00', () {
      final p = DatePeriod.hour(DateTime(2026, 12, 31, 23, 45));
      expect(p.start, DateTime(2026, 12, 31, 23));
      expect(p.end, DateTime(2027, 1, 1));
      expect(p.unit, PeriodUnit.hour);
    });

    test('week starts on Monday by default and on the given weekday otherwise', () {
      // 2026-11-04 is a Wednesday.
      final mon = DatePeriod.week(DateTime(2026, 11, 4, 9));
      expect(mon.start, DateTime(2026, 11, 2));
      expect(mon.end, DateTime(2026, 11, 9));
      final sun = DatePeriod.week(DateTime(2026, 11, 4), firstWeekday: DateTime.sunday);
      expect(sun.start, DateTime(2026, 11, 1));
      // A Monday is the first day of its own (Monday) week.
      expect(DatePeriod.week(DateTime(2026, 11, 2)).start, DateTime(2026, 11, 2));
      // Across a year boundary: Thu 1 Jan 2026 belongs to the week of Mon 29 Dec 2025.
      expect(DatePeriod.week(DateTime(2026, 1, 1)).start, DateTime(2025, 12, 29));
    });

    test('month and year, including December', () {
      final dec = DatePeriod.month(2026, 12);
      expect(dec.start, DateTime(2026, 12));
      expect(dec.end, DateTime(2027, 1));
      final feb = DatePeriod.month(2024, 2);
      expect(feb.contains(_ms(2024, 2, 29, 23)), isTrue);
      expect(feb.contains(_ms(2024, 3, 1, 0)), isFalse);
      final y = DatePeriod.year(2026);
      expect(y.contains(DateTime(2026).millisecondsSinceEpoch), isTrue);
      expect(y.contains(DateTime(2027).millisecondsSinceEpoch), isFalse);
    });

    test('range makes the inclusive end day exclusive and asRange reverses it', () {
      final r = DateTimeRange(start: DateTime(2026, 3, 1, 15), end: DateTime(2026, 4, 14, 8));
      final p = DatePeriod.range(r);
      expect(p.start, DateTime(2026, 3, 1));
      expect(p.end, DateTime(2026, 4, 15));
      expect(p.unit, PeriodUnit.custom);
      expect(p.contains(_ms(2026, 4, 14, 23, 59)), isTrue);
      expect(p.asRange.start, DateTime(2026, 3, 1));
      expect(p.asRange.end, DateTime(2026, 4, 14));
    });

    test('equality and hashCode', () {
      expect(DatePeriod.day(DateTime(2026, 1, 2, 3)), DatePeriod.day(DateTime(2026, 1, 2, 22)));
      expect(DatePeriod.day(DateTime(2026, 1, 2)).hashCode, DatePeriod.day(DateTime(2026, 1, 2, 5)).hashCode);
      // Same span, different unit.
      expect(DatePeriod.day(DateTime(2026, 1, 2)) == DatePeriod(DateTime(2026, 1, 2), DateTime(2026, 1, 3), PeriodUnit.custom),
          isFalse);
    });

    test('labels in English', () {
      expect(DatePeriod.day(DateTime(2026, 11, 3)).label(l, 'en'), 'Nov 3, 2026');
      expect(DatePeriod.month(2026, 11).label(l, 'en'), 'November 2026');
      expect(DatePeriod.year(2026).label(l, 'en'), '2026');
      expect(DatePeriod.week(DateTime(2026, 11, 4)).label(l, 'en'), 'Week of Nov 2, 2026');
      expect(DatePeriod.hour(DateTime(2026, 11, 3, 14, 20)).label(l, 'en'), 'Nov 3, 2026, 14:00–15:00');
      final custom = DatePeriod.range(DateTimeRange(start: DateTime(2026, 3, 1), end: DateTime(2026, 4, 14)));
      expect(custom.label(l, 'en'), 'Mar 1, 2026 – Apr 14, 2026');
    });

    test('label in German and fallback for an unknown locale', () {
      final de = AppLocalizations(const Locale('de'));
      expect(DatePeriod.month(2026, 3).label(de, 'de'), 'März 2026');
      // Unknown locale data falls back to English instead of throwing.
      expect(DatePeriod.year(2026).label(l, 'xx_YY'), '2026');
      expect(DatePeriod.month(2026, 11).label(l, 'xx_YY'), 'November 2026');
    });
  });

  group('LibraryQuery', () {
    test('defaults have no filters', () {
      const q = LibraryQuery();
      expect(q.hasFilters, isFalse);
      expect(q.chipCount, 0);
      expect(q.sort, LibrarySort.newest);
    });

    test('whitespace-only text is not a filter and is not a chip', () {
      const q = LibraryQuery(text: '   ');
      expect(q.hasFilters, isFalse);
      expect(const LibraryQuery(text: 'x').hasFilters, isTrue);
      expect(const LibraryQuery(text: 'x').chipCount, 0);
    });

    test('chipCount counts each non-text filter once', () {
      final q = LibraryQuery(
        text: 'abc',
        period: DatePeriod.year(2026),
        style: 'travel',
        occasion: 'halloween',
        ratio: '4:5',
        hasVideo: true,
      );
      expect(q.chipCount, 5);
      expect(q.hasFilters, isTrue);
    });

    test('copyWith keeps unspecified fields and can clear nullable ones with null', () {
      final q = LibraryQuery(text: 'a', period: DatePeriod.year(2026), style: 'travel', ratio: '1:1');
      final same = q.copyWith();
      expect(same, q);
      final cleared = q.copyWith(period: null, style: null);
      expect(cleared.period, isNull);
      expect(cleared.style, isNull);
      expect(cleared.ratio, '1:1');
      expect(cleared.text, 'a');
      expect(q.copyWith(sort: LibrarySort.title).sort, LibrarySort.title);
    });

    test('clearedFilters keeps text and sort only', () {
      final q = LibraryQuery(
        text: 'x',
        sort: LibrarySort.oldest,
        period: DatePeriod.year(2026),
        style: 'love',
        occasion: 'birthday',
        ratio: '9:16',
        hasVideo: true,
      );
      expect(q.clearedFilters(), const LibraryQuery(text: 'x', sort: LibrarySort.oldest));
    });

    test('equality and hashCode', () {
      expect(const LibraryQuery(text: 'a'), const LibraryQuery(text: 'a'));
      expect(const LibraryQuery(text: 'a').hashCode, const LibraryQuery(text: 'a').hashCode);
      expect(const LibraryQuery(text: 'a') == const LibraryQuery(text: 'b'), isFalse);
    });
  });

  group('metadata helpers', () {
    test('templateStyleKey', () {
      expect(templateStyleKey(_p('a')), isNull);
      expect(templateStyleKey(_p('a', templateId: '')), isNull);
      expect(templateStyleKey(_p('a', templateId: 'birthday-4-1:1-a')), 'birthday');
      expect(templateStyleKey(_p('a', templateId: 'travel')), 'travel');
      expect(templateStyleKey(_p('a', templateId: '3f2a-uuid-of-mine')), ownTemplateKey);
    });

    test('templateStyleLabel', () {
      expect(templateStyleLabel(l, 'birthday'), 'Birthday');
      expect(templateStyleLabel(l, ownTemplateKey), 'My template');
      // Unknown style key: humanized.
      expect(templateStyleLabel(l, 'retro_wave'), 'Retro wave');
    });

    test('occasionLabel uses the calendar, then humanizes', () {
      expect(occasionLabel(l, 'birthday'), 'Birthday');
      expect(occasionLabel(l, 'halloween'), 'Halloween');
      expect(occasionLabel(l, 'some_custom_day'), 'Some custom day');
    });

    test('hasVideo', () {
      expect(hasVideo(_p('a')), isFalse);
      expect(hasVideo(_p('a', video: true)), isTrue);
    });
  });

  group('applyLibraryQuery', () {
    final all = [
      _p('trip', title: 'Rome Trip', created: _ms(2026, 3, 10), updated: _ms(2026, 6, 1), templateId: 'travel-4-1:1-a', ratio: '4:5'),
      _p('bday', title: 'Mia turns 5', created: _ms(2026, 5, 20), updated: _ms(2026, 5, 21), templateId: 'birthday-3-1:1-b', occasionId: 'birthday'),
      _p('halo', title: 'Spooky', created: _ms(2025, 10, 31), updated: _ms(2026, 7, 1), occasionId: 'halloween', video: true),
      _p('mine', title: 'apple pie', created: _ms(2026, 1, 5), updated: _ms(2026, 1, 5), templateId: 'my-own-uuid'),
      _p('plain', title: 'Zebra', created: _ms(2024, 2, 29), updated: _ms(2024, 2, 29), ratio: '9:16'),
    ];

    test('no query returns everything newest first', () {
      expect(_ids(applyLibraryQuery(all, const LibraryQuery(), l)), ['bday', 'trip', 'mine', 'halo', 'plain']);
    });

    test('sort oldest / edited / title', () {
      expect(_ids(applyLibraryQuery(all, const LibraryQuery(sort: LibrarySort.oldest), l)),
          ['plain', 'halo', 'mine', 'trip', 'bday']);
      expect(_ids(applyLibraryQuery(all, const LibraryQuery(sort: LibrarySort.edited), l)),
          ['halo', 'trip', 'bday', 'mine', 'plain']);
      // Case-insensitive: "apple pie" before "Mia" before "Rome".
      expect(_ids(applyLibraryQuery(all, const LibraryQuery(sort: LibrarySort.title), l)),
          ['mine', 'bday', 'trip', 'halo', 'plain']);
    });

    test('does not mutate the input list', () {
      final before = _ids(all);
      applyLibraryQuery(all, const LibraryQuery(sort: LibrarySort.title), l);
      expect(_ids(all), before);
    });

    test('text search matches title case-insensitively and trims', () {
      expect(_ids(applyLibraryQuery(all, const LibraryQuery(text: '  ROME '), l)), ['trip']);
      expect(_ids(applyLibraryQuery(all, const LibraryQuery(text: 'pie'), l)), ['mine']);
      expect(applyLibraryQuery(all, const LibraryQuery(text: 'nothing-like-this'), l), isEmpty);
    });

    test('text search also matches template style and occasion names', () {
      // "travel" only appears as the style label of 'trip'.
      expect(_ids(applyLibraryQuery(all, const LibraryQuery(text: 'travel'), l)), ['trip']);
      // "birthday": style label and occasion of 'bday'.
      expect(_ids(applyLibraryQuery(all, const LibraryQuery(text: 'birthday'), l)), ['bday']);
      expect(_ids(applyLibraryQuery(all, const LibraryQuery(text: 'hallo'), l)), ['halo']);
      expect(_ids(applyLibraryQuery(all, const LibraryQuery(text: 'my template'), l)), ['mine']);
    });

    test('text search uses localized names', () {
      final de = AppLocalizations(const Locale('de'));
      final travelDe = templateStyleLabel(de, 'travel').toLowerCase();
      expect(_ids(applyLibraryQuery(all, LibraryQuery(text: travelDe), de)), contains('trip'));
    });

    test('style filter, including own templates', () {
      expect(_ids(applyLibraryQuery(all, const LibraryQuery(style: 'travel'), l)), ['trip']);
      expect(_ids(applyLibraryQuery(all, const LibraryQuery(style: ownTemplateKey), l)), ['mine']);
    });

    test('occasion, ratio and video filters', () {
      expect(_ids(applyLibraryQuery(all, const LibraryQuery(occasion: 'halloween'), l)), ['halo']);
      expect(_ids(applyLibraryQuery(all, const LibraryQuery(ratio: '9:16'), l)), ['plain']);
      expect(_ids(applyLibraryQuery(all, const LibraryQuery(hasVideo: true), l)), ['halo']);
    });

    test('period filter on createdAt, and ignorePeriod skips it', () {
      final q = LibraryQuery(period: DatePeriod.year(2026));
      expect(_ids(applyLibraryQuery(all, q, l)), ['bday', 'trip', 'mine']);
      expect(applyLibraryQuery(all, q, l, ignorePeriod: true).length, all.length);
      final leap = LibraryQuery(period: DatePeriod.day(DateTime(2024, 2, 29)));
      expect(_ids(applyLibraryQuery(all, leap, l)), ['plain']);
      // Halloween 2025 is outside the 2026 period even though it was edited in 2026.
      expect(_ids(applyLibraryQuery(all, LibraryQuery(period: DatePeriod.month(2025, 10)), l)), ['halo']);
    });

    test('filters combine with AND', () {
      final q = LibraryQuery(period: DatePeriod.year(2026), text: 'i');
      // 2026: bday ("Mia"), trip ("Rome Trip"), mine ("apple pie") all contain "i".
      expect(_ids(applyLibraryQuery(all, q, l)), ['bday', 'trip', 'mine']);
      expect(_ids(applyLibraryQuery(all, q.copyWith(ratio: '4:5'), l)), ['trip']);
      expect(applyLibraryQuery(all, q.copyWith(hasVideo: true), l), isEmpty);
    });

    test('empty library', () {
      expect(applyLibraryQuery(const [], const LibraryQuery(text: 'x'), l), isEmpty);
      expect(groupByMonth(const [], LibrarySort.newest), isEmpty);
      expect(monthsWithCollages(const []), isEmpty);
      expect(countBy(const [], (p) => p.ratioLabel), isEmpty);
    });

    test('groupByMonth splits by shown month, by updatedAt under "edited"', () {
      final newest = applyLibraryQuery(all, const LibraryQuery(), l);
      final g = groupByMonth(newest, LibrarySort.newest);
      expect([for (final s in g) s.month],
          [DateTime(2026, 5), DateTime(2026, 3), DateTime(2026, 1), DateTime(2025, 10), DateTime(2024, 2)]);
      expect(g.fold<int>(0, (n, s) => n + s.items.length), all.length);

      final edited = applyLibraryQuery(all, const LibraryQuery(sort: LibrarySort.edited), l);
      final ge = groupByMonth(edited, LibrarySort.edited);
      expect(ge.first.month, DateTime(2026, 7));
      expect(_ids(ge.first.items), ['halo']);

      final title = groupByMonth(applyLibraryQuery(all, const LibraryQuery(sort: LibrarySort.title), l), LibrarySort.title);
      expect(title, hasLength(1));
      expect(title.single.items, hasLength(all.length));
    });

    test('groupByMonth keeps two collages from the same month together', () {
      final two = [_p('a', created: _ms(2026, 4, 30, 23, 59)), _p('b', created: _ms(2026, 4, 1, 0, 1))];
      final g = groupByMonth(two, LibrarySort.newest);
      expect(g, hasLength(1));
      expect(_ids(g.single.items), ['a', 'b']);
    });

    test('shownStamp', () {
      final p = all.first;
      expect(shownStamp(p, LibrarySort.edited), p.updatedAt);
      for (final s in [LibrarySort.newest, LibrarySort.oldest, LibrarySort.title]) {
        expect(shownStamp(p, s), p.createdAt);
      }
    });

    test('countBy sorts by descending count and skips null keys', () {
      final c = countBy(all, (p) => p.ratioLabel);
      expect(c.first, ('1:1', 3));
      expect(c.map((e) => e.$2).reduce((a, b) => a + b), all.length);
      final occ = countBy(all, (p) => p.occasionId);
      expect(occ.map((e) => e.$2).reduce((a, b) => a + b), 2);
    });

    test('monthsWithCollages counts by creation month, newest first', () {
      final more = [...all, _p('x', created: _ms(2026, 5, 1, 0, 0))];
      final m = monthsWithCollages(more);
      expect(m.first, (DateTime(2026, 5), 2));
      expect(m.last, (DateTime(2024, 2), 1));
      expect(m.length, 5);
    });
  });

  group('date formatting helpers (meta_date.dart)', () {
    final t = _ms(2026, 11, 3, 14, 5);

    test('formatCollageDate short and with time', () {
      expect(formatCollageDate(t, localeName: 'en', withTime: false), 'Nov 3, 2026');
      expect(formatCollageDate(t, localeName: 'en'), 'Nov 3, 2026 · 14:05');
      expect(formatCollageDate(t, localeName: 'de', withTime: false), '3. Nov. 2026');
    });

    test('formatCollageDateLong is unabbreviated', () {
      expect(formatCollageDateLong(t, localeName: 'en'), 'Tuesday, November 3, 2026, 14:05');
      expect(formatCollageDateLong(t, localeName: 'de'), 'Dienstag, 3. November 2026, 14:05');
    });

    test('non-positive timestamps format as empty', () {
      expect(formatCollageDate(0), '');
      expect(formatCollageDate(-5), '');
      expect(formatCollageDateLong(0), '');
    });

    test('an unknown locale falls back to English', () {
      expect(formatCollageDate(t, localeName: 'xx_YY', withTime: false), 'Nov 3, 2026');
    });

    test('relativeDayLabel', () {
      final now = DateTime(2026, 11, 3, 0, 5);
      expect(relativeDayLabel(l, DateTime(2026, 11, 3, 23), now: now), 'Today');
      expect(relativeDayLabel(l, DateTime(2026, 11, 2, 23, 59), now: now), 'Yesterday');
      expect(relativeDayLabel(l, DateTime(2026, 10, 31), now: now), '3 days ago');
      expect(relativeDayLabel(l, DateTime(2026, 10, 27), now: now), '1 week ago');
      expect(relativeDayLabel(l, DateTime(2026, 10, 6), now: now), '4 weeks ago');
      expect(relativeDayLabel(l, DateTime(2026, 9, 29), now: now), isNull);
      expect(relativeDayLabel(l, DateTime(2026, 11, 4), now: now), isNull);
      // Across New Year and a leap day.
      expect(relativeDayLabel(l, DateTime(2025, 12, 31), now: DateTime(2026, 1, 1)), 'Yesterday');
      expect(relativeDayLabel(l, DateTime(2024, 2, 28), now: DateTime(2024, 3, 1)), '2 days ago');
    });
  });
}
