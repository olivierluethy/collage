import 'package:flutter_test/flutter_test.dart';

import 'package:collage/services/occasion_service.dart';

const _svc = OccasionService();
const _regions = ['CH', 'DE', 'US', 'GB', 'IN'];

Occasion _occ(String id) => OccasionService.byId(id)!;

DateTime? _date(String id, int year, String region) => _occ(id).dateIn(year, region);

/// Ids of occurrences between [from] and [to] in [region], in date order.
List<String> _ids(DateTime from, DateTime to, String region, {List<Birthday> birthdays = const []}) =>
    [for (final o in _svc.occurrences(from: from, to: to, region: region, birthdays: birthdays)) o.id];

void main() {
  group('normalizeRegion', () {
    test('upper-cases and trims', () {
      expect(OccasionService.normalizeRegion('ch'), 'CH');
      expect(OccasionService.normalizeRegion(' de '), 'DE');
    });
    test('UK maps to GB', () {
      expect(OccasionService.normalizeRegion('UK'), 'GB');
      expect(OccasionService.normalizeRegion('uk'), 'GB');
    });
    test('null, empty and malformed codes become empty', () {
      expect(OccasionService.normalizeRegion(null), '');
      expect(OccasionService.normalizeRegion(''), '');
      expect(OccasionService.normalizeRegion('USA'), '');
      expect(OccasionService.normalizeRegion('U1'), '');
      expect(OccasionService.normalizeRegion('419'), '');
    });
    test('knownRegions is sorted and contains the sample regions', () {
      final known = OccasionService.knownRegions;
      expect(known, [...known]..sort());
      expect(known, containsAll(_regions));
    });
  });

  group('helpers', () {
    test('nthWeekday / lastWeekday', () {
      expect(nthWeekday(2026, 11, DateTime.thursday, 4), DateTime(2026, 11, 26));
      expect(nthWeekday(2026, 5, DateTime.sunday, 2), DateTime(2026, 5, 10));
      // Month starting on the requested weekday.
      expect(nthWeekday(2026, 11, DateTime.sunday, 1), DateTime(2026, 11, 1));
      expect(lastWeekday(2026, 5, DateTime.sunday), DateTime(2026, 5, 31));
      expect(lastWeekday(2026, 10, DateTime.saturday), DateTime(2026, 10, 31));
    });
    test('western Easter', () {
      expect(westernEaster(2025), DateTime(2025, 4, 20));
      expect(westernEaster(2026), DateTime(2026, 4, 5));
      expect(westernEaster(2027), DateTime(2027, 3, 28));
      expect(westernEaster(2028), DateTime(2028, 4, 16));
    });
    test('orthodox Easter and its validity range', () {
      expect(orthodoxEaster(2025), DateTime(2025, 4, 20));
      expect(orthodoxEaster(2026), DateTime(2026, 4, 12));
      expect(orthodoxEaster(2027), DateTime(2027, 5, 2));
      expect(orthodoxEaster(1899), isNull);
      expect(orthodoxEaster(2100), isNull);
    });
    test('daysBetween counts calendar days and ignores the time', () {
      expect(daysBetween(DateTime(2026, 11, 3, 23, 59), DateTime(2026, 11, 4)), 1);
      expect(daysBetween(DateTime(2026, 11, 3), DateTime(2026, 10, 31, 12)), -3);
      // Across the EU DST change (25 Oct 2026).
      expect(daysBetween(DateTime(2026, 10, 24), DateTime(2026, 10, 26)), 2);
    });
  });

  group('Easter-based dates', () {
    for (final r in ['CH', 'DE', 'US', 'GB']) {
      test('Easter in $r', () {
        expect(_date('easter', 2026, r), DateTime(2026, 4, 5));
        expect(_date('easter', 2027, r), DateTime(2027, 3, 28));
      });
    }
    test('Easter is not listed in IN', () {
      expect(_date('easter', 2026, 'IN'), isNull);
    });
    test('Orthodox regions get Orthodox Easter', () {
      expect(_date('easter', 2026, 'GR'), DateTime(2026, 4, 12));
    });
    test('GB Mothering Sunday is three weeks before Easter', () {
      expect(_date('mothers_day', 2026, 'GB'), DateTime(2026, 3, 15));
      expect(_date('mothers_day', 2027, 'GB'), DateTime(2027, 3, 7));
    });
    test('DE Vatertag is Ascension Day (Easter + 39)', () {
      expect(_date('fathers_day', 2026, 'DE'), DateTime(2026, 5, 14));
      expect(_date('fathers_day', 2027, 'DE'), DateTime(2027, 5, 6));
      expect(_date('fathers_day', 2026, 'DE')!.weekday, DateTime.thursday);
    });
  });

  group("Mother's / Father's Day per region", () {
    test("second Sunday of May in US, CH, DE, IN", () {
      for (final r in ['US', 'CH', 'DE', 'IN']) {
        expect(_date('mothers_day', 2026, r), DateTime(2026, 5, 10), reason: r);
        expect(_date('mothers_day', 2027, r), DateTime(2027, 5, 9), reason: r);
      }
    });
    test('GB differs from US', () {
      expect(_date('mothers_day', 2026, 'GB'), isNot(_date('mothers_day', 2026, 'US')));
    });
    test("Father's Day: third Sunday of June in US, GB, IN", () {
      for (final r in ['US', 'GB', 'IN']) {
        expect(_date('fathers_day', 2026, r), DateTime(2026, 6, 21), reason: r);
        expect(_date('fathers_day', 2027, r), DateTime(2027, 6, 20), reason: r);
      }
    });
    test("Father's Day CH: first Sunday of June", () {
      expect(_date('fathers_day', 2026, 'CH'), DateTime(2026, 6, 7));
      expect(_date('fathers_day', 2027, 'CH'), DateTime(2027, 6, 6));
    });
  });

  group('national days', () {
    test('as defined by the catalog', () {
      expect(_date('national_day', 2026, 'CH'), DateTime(2026, 8, 1));
      expect(_date('national_day', 2026, 'DE'), DateTime(2026, 10, 3));
      expect(_date('national_day', 2026, 'US'), DateTime(2026, 7, 4));
      expect(_date('national_day', 2026, 'IN'), DateTime(2026, 8, 15));
      expect(_date('national_day', 2026, 'GB'), isNull);
    });
    test('IN lists only Independence Day, not Republic Day (26 Jan)', () {
      final jan = _svc.occurrences(from: DateTime(2027, 1, 20), to: DateTime(2027, 1, 31), region: 'IN');
      expect(jan.where((o) => o.id == 'national_day'), isEmpty);
    });
    test("NL King's Day moves to 26 April when 27 April is a Sunday", () {
      expect(_date('national_day', 2025, 'NL'), DateTime(2025, 4, 26)); // 27 Apr 2025 = Sun
      expect(_date('national_day', 2026, 'NL'), DateTime(2026, 4, 27));
    });
  });

  group('other occasions', () {
    test('US Thanksgiving is the 4th Thursday of November', () {
      expect(_date('thanksgiving', 2026, 'US'), DateTime(2026, 11, 26));
      expect(_date('thanksgiving', 2027, 'US'), DateTime(2027, 11, 25));
      expect(_date('thanksgiving', 2026, 'CA'), DateTime(2026, 10, 12));
      for (final r in ['CH', 'DE', 'GB', 'IN']) {
        expect(_date('thanksgiving', 2026, r), isNull, reason: r);
      }
    });
    test('Diwali in IN from the fixed table, never outside it', () {
      expect(_date('diwali', 2025, 'IN'), DateTime(2025, 10, 20));
      expect(_date('diwali', 2026, 'IN'), DateTime(2026, 11, 8));
      expect(_date('diwali', 2027, 'IN'), DateTime(2027, 10, 29));
      expect(_date('diwali', 2024, 'IN'), isNull);
      expect(_date('diwali', 2031, 'IN'), isNull);
      for (final r in ['CH', 'DE', 'US', 'GB']) {
        expect(_date('diwali', 2026, r), isNull, reason: r);
      }
    });
    test('Christmas on 25 Dec in all five sample regions', () {
      for (final r in _regions) {
        expect(_date('christmas', 2026, r), DateTime(2026, 12, 25), reason: r);
      }
      expect(_date('christmas', 2026, 'RU'), DateTime(2026, 1, 7));
    });
    test("Valentine's Day 14 Feb in all five sample regions", () {
      for (final r in _regions) {
        expect(_date('valentines', 2026, r), DateTime(2026, 2, 14), reason: r);
      }
    });
    test('New Year is global, even for an unknown region', () {
      expect(_date('new_year', 2027, ''), DateTime(2027, 1, 1));
      expect(_ids(DateTime(2026, 1, 1), DateTime(2026, 12, 31), ''), ['new_year']);
    });
    test('byId knows birthdays and returns null for unknown ids', () {
      expect(OccasionService.byId('birthday'), same(OccasionService.birthdayOccasion));
      expect(OccasionService.byId('nope'), isNull);
    });
  });

  group('Halloween', () {
    test('customary in US and GB', () {
      for (final r in ['US', 'GB']) {
        final h = _occ('halloween');
        expect(h.dateIn(2026, r), DateTime(2026, 10, 31));
        expect(h.isOptionalIn(r), isFalse, reason: r);
      }
    });
    test('optional in CH and DE', () {
      for (final r in ['CH', 'DE']) {
        final h = _occ('halloween');
        expect(h.dateIn(2026, r), DateTime(2026, 10, 31));
        expect(h.isOptionalIn(r), isTrue, reason: r);
      }
    });
    test('not observed in IN', () {
      expect(_date('halloween', 2026, 'IN'), isNull);
    });
    test('occurrences carry the optional flag', () {
      OccasionDate h(String r) => _svc
          .occurrences(from: DateTime(2026, 10, 31), to: DateTime(2026, 10, 31), region: r)
          .singleWhere((o) => o.id == 'halloween');
      expect(h('US').optional, isFalse);
      expect(h('GB').optional, isFalse);
      expect(h('DE').optional, isTrue);
      expect(h('CH').optional, isTrue);
    });
  });

  group('suggestions around 31 Oct and 3 Nov 2026', () {
    List<String> active(DateTime now, String r, {List<Birthday> b = const []}) =>
        [for (final o in _svc.active(now, r, birthdays: b)) o.id];

    test('on 31 Oct: Halloween in US/GB/DE/CH, Diwali (8 days away) in IN', () {
      final oct31 = DateTime(2026, 10, 31, 9);
      expect(active(oct31, 'US'), ['halloween']);
      expect(active(oct31, 'GB'), ['halloween']);
      expect(active(oct31, 'DE'), ['halloween']);
      expect(active(oct31, 'CH'), ['halloween']);
      expect(active(oct31, 'IN'), ['diwali']);
    });
    test('Halloween stays one day after (1 Nov) and is gone on 2 Nov', () {
      expect(active(DateTime(2026, 11, 1), 'US'), ['halloween']);
      expect(active(DateTime(2026, 11, 2), 'US'), isEmpty);
    });
    test('a birthday on the same day ranks before an (optional) holiday', () {
      final b = Birthday(id: 'b1', name: 'Ana', month: 10, day: 31);
      final list = _svc.active(DateTime(2026, 10, 31), 'DE', birthdays: [b]);
      expect(list.first.birthday, b);
      expect(list.last.id, 'halloween');
      expect(list.last.optional, isTrue);
    });
    test('on 3 Nov: Halloween passed; only IN has an active suggestion (Diwali)', () {
      final nov3 = DateTime(2026, 11, 3, 12);
      for (final r in ['US', 'GB', 'DE', 'CH']) {
        expect(active(nov3, r), isEmpty, reason: r);
      }
      final inList = _svc.active(nov3, 'IN');
      expect(inList.map((o) => o.id), ['diwali']);
      expect(inList.single.daysFrom(nov3), 5);
    });
    test('US Thanksgiving becomes active 14 days ahead (12 Nov 2026)', () {
      expect(active(DateTime(2026, 11, 11), 'US'), isEmpty);
      expect(active(DateTime(2026, 11, 12), 'US'), ['thanksgiving']);
    });
    test('upcoming from 3 Nov to the end of the year, per region', () {
      final from = DateTime(2026, 11, 3);
      final to = DateTime(2026, 12, 31);
      expect(_ids(from, to, 'US'), ['thanksgiving', 'christmas']);
      expect(_ids(from, to, 'IN'), ['diwali', 'christmas']);
      expect(_ids(from, to, 'GB'), ['christmas']);
      expect(_ids(from, to, 'DE'), ['christmas']);
      expect(_ids(from, to, 'CH'), ['christmas']);
      final us = _svc.occurrences(from: from, to: to, region: 'US');
      expect(us.first.date, DateTime(2026, 11, 26));
    });
  });

  group('OccasionDate.key', () {
    test('occasion key pads month and day', () {
      final h = _svc
          .occurrences(from: DateTime(2026, 10, 31), to: DateTime(2026, 10, 31), region: 'US')
          .single;
      expect(h.key, 'halloween@2026-10-31');
      final ny = _svc.occurrences(from: DateTime(2027, 1, 1), to: DateTime(2027, 1, 1), region: 'CH').single;
      expect(ny.key, 'new_year@2027-01-01');
    });
    test('birthday key names the person', () {
      final b = Birthday(id: 'abc', name: 'Ana', month: 11, day: 6);
      final o = _svc
          .occurrences(from: DateTime(2026, 11, 6), to: DateTime(2026, 11, 6), region: 'CH', birthdays: [b])
          .single;
      expect(o.key, 'birthday:abc@2026-11-06');
      expect(o.id, 'birthday');
    });
  });

  group('Birthday', () {
    test('29 Feb falls on 28 Feb in common years, 29 Feb in leap years', () {
      const b = Birthday(id: 'l', name: 'Leap', month: 2, day: 29);
      expect(b.dateIn(2026), DateTime(2026, 2, 28));
      expect(b.dateIn(2027), DateTime(2027, 2, 28));
      expect(b.dateIn(2028), DateTime(2028, 2, 29));
      expect(b.dateIn(2100), DateTime(2100, 2, 28)); // not a leap year
      expect(b.dateIn(2000), DateTime(2000, 2, 29));
    });
    test('29 Feb birthday appears once on 28 Feb 2027', () {
      const b = Birthday(id: 'l', name: 'Leap', month: 2, day: 29);
      final list = _svc.occurrences(
          from: DateTime(2027, 2, 27), to: DateTime(2027, 3, 2), region: 'CH', birthdays: [b]);
      expect(list.where((o) => o.birthday != null).map((o) => o.date), [DateTime(2027, 2, 28)]);
    });
    test('json round trip and validation', () {
      const b = Birthday(id: 'x', name: 'Bo', month: 3, day: 14, year: 1990, fromContacts: true);
      final back = Birthday.fromJson(b.toJson())!;
      expect([back.id, back.name, back.month, back.day, back.year, back.fromContacts],
          ['x', 'Bo', 3, 14, 1990, true]);
      expect(Birthday.fromJson({'id': 'x', 'name': 'Bo', 'm': 13, 'd': 1}), isNull);
      expect(Birthday.fromJson({'id': 'x', 'name': 'Bo', 'm': 1, 'd': 0}), isNull);
      expect(Birthday.fromJson({'id': 'x', 'm': 1, 'd': 1}), isNull);
      expect(Birthday.fromJson({'id': 'x', 'name': 'Bo', 'm': 1, 'd': 1})!.fromContacts, isFalse);
    });
  });

  group('occurrences(from, to)', () {
    test('bounds are inclusive calendar days, time of day ignored', () {
      expect(_ids(DateTime(2026, 12, 25), DateTime(2026, 12, 25), 'CH'), ['christmas']);
      expect(_ids(DateTime(2026, 12, 25, 23, 59), DateTime(2026, 12, 25, 0, 1), 'CH'), ['christmas']);
      expect(_ids(DateTime(2026, 12, 26), DateTime(2026, 12, 31), 'CH'), isEmpty);
      expect(_ids(DateTime(2026, 12, 1), DateTime(2026, 12, 24), 'CH'), isEmpty);
    });
    test('spans a year boundary and includes birthdays, sorted by date', () {
      final b1 = Birthday(id: 'a', name: 'A', month: 12, day: 22);
      final b2 = Birthday(id: 'b', name: 'B', month: 1, day: 2);
      final out = _svc.occurrences(
        from: DateTime(2026, 12, 20),
        to: DateTime(2027, 1, 3),
        region: 'DE',
        birthdays: [b2, b1],
      );
      expect(out.map((o) => o.key), [
        'birthday:a@2026-12-22',
        'christmas@2026-12-25',
        'new_year@2027-01-01',
        'birthday:b@2027-01-02',
      ]);
    });
    test('birthdays outside the range are left out', () {
      final b = Birthday(id: 'a', name: 'A', month: 6, day: 1);
      expect(_ids(DateTime(2026, 11, 3), DateTime(2026, 12, 31), 'CH', birthdays: [b]), ['christmas']);
    });
    test('region is normalised', () {
      expect(_ids(DateTime(2026, 10, 31), DateTime(2026, 10, 31), 'uk'), ['halloween']);
    });
  });
}
