import 'package:flutter_test/flutter_test.dart';

import 'package:collage/services/occasion_service.dart';
import 'package:collage/services/reminder_service.dart';
import 'package:collage/state/occasions.dart' show ReminderFrequency;

const _svc = OccasionService();

/// A plain (non-birthday) occurrence of Christmas' occasion on [d].
OccasionDate _occ(DateTime d, {String id = 'christmas'}) =>
    OccasionDate(occasion: OccasionService.byId(id)!, date: d);

OccasionDate _bday(DateTime d, {String id = 'b1'}) => OccasionDate(
      occasion: OccasionService.birthdayOccasion,
      date: d,
      birthday: Birthday(id: id, name: 'Ana', month: d.month, day: d.day),
    );

List<PlannedReminder> _plan({
  required DateTime now,
  List<OccasionDate> upcoming = const [],
  List<MemoryDate> memories = const [],
  ReminderFrequency frequency = ReminderFrequency.weekly2,
  int quietStart = 21 * 60,
  int quietEnd = 9 * 60,
}) =>
    ReminderPlanner.plan(
      now: now,
      upcoming: upcoming,
      memories: memories,
      frequency: frequency,
      quietStart: quietStart,
      quietEnd: quietEnd,
    );

void main() {
  final now = DateTime(2026, 11, 3, 8);

  group('lead times and time of day', () {
    test('occasions fire 3 days ahead at 10:00', () {
      final p = _plan(now: now, upcoming: [_occ(DateTime(2026, 11, 26))]);
      expect(p.single.fireAt, DateTime(2026, 11, 23, 10));
      expect(p.single.day, DateTime(2026, 11, 26));
    });
    test('birthdays fire 2 days ahead at 10:00', () {
      final p = _plan(now: now, upcoming: [_bday(DateTime(2026, 11, 20))]);
      expect(p.single.fireAt, DateTime(2026, 11, 18, 10));
    });
    test('lead day already passed: today at 10:00', () {
      final p = _plan(now: DateTime(2026, 11, 24, 8), upcoming: [_occ(DateTime(2026, 11, 26))]);
      expect(p.single.fireAt, DateTime(2026, 11, 24, 10));
    });
    test('today 10:00 is less than 15 min away: next day', () {
      final p = _plan(now: DateTime(2026, 11, 24, 9, 50), upcoming: [_occ(DateTime(2026, 11, 26))]);
      expect(p.single.fireAt, DateTime(2026, 11, 25, 10));
    });
    test('occasion today, still before 10:00: fires today', () {
      final p = _plan(now: DateTime(2026, 11, 26, 8), upcoming: [_occ(DateTime(2026, 11, 26))]);
      expect(p.single.fireAt, DateTime(2026, 11, 26, 10));
    });
    test('never after the day itself', () {
      expect(_plan(now: DateTime(2026, 11, 26, 12), upcoming: [_occ(DateTime(2026, 11, 26))]), isEmpty);
      expect(_plan(now: DateTime(2026, 11, 26, 9, 50), upcoming: [_occ(DateTime(2026, 11, 26))]), isEmpty);
      expect(_plan(now: DateTime(2026, 11, 27, 8), upcoming: [_occ(DateTime(2026, 11, 26))]), isEmpty);
    });
    test('every fire time is on or before its day', () {
      final upcoming = _svc.occurrences(
        from: now,
        to: DateTime(2027, 3, 1),
        region: 'US',
        birthdays: [const Birthday(id: 'x', name: 'X', month: 11, day: 4)],
      );
      final p = _plan(now: now, upcoming: upcoming, frequency: ReminderFrequency.weekly2);
      expect(p, isNotEmpty);
      for (final r in p) {
        expect(daysBetween(r.fireAt, r.day), greaterThanOrEqualTo(0));
        expect(r.fireAt.isAfter(now), isTrue);
      }
    });
  });

  group('quiet hours', () {
    test('default 21:00–09:00 leaves 10:00 alone', () {
      final p = _plan(now: now, upcoming: [_occ(DateTime(2026, 11, 26))]);
      expect(p.single.fireAt.hour, 10);
    });
    test('10:00 inside a same-day span moves to its end', () {
      final p = _plan(
          now: now, upcoming: [_occ(DateTime(2026, 11, 26))], quietStart: 9 * 60, quietEnd: 11 * 60 + 30);
      expect(p.single.fireAt, DateTime(2026, 11, 23, 11, 30));
    });
    test('10:00 inside a span crossing midnight moves to its end', () {
      final p = _plan(
          now: now, upcoming: [_occ(DateTime(2026, 11, 26))], quietStart: 22 * 60, quietEnd: 12 * 60);
      expect(p.single.fireAt, DateTime(2026, 11, 23, 12));
    });
    test('the end of quiet hours is exclusive', () {
      final p = _plan(
          now: now, upcoming: [_occ(DateTime(2026, 11, 26))], quietStart: 21 * 60, quietEnd: 10 * 60);
      expect(p.single.fireAt, DateTime(2026, 11, 23, 10));
    });
    test('equal start and end mean no quiet hours', () {
      final p = _plan(
          now: now, upcoming: [_occ(DateTime(2026, 11, 26))], quietStart: 10 * 60, quietEnd: 10 * 60);
      expect(p.single.fireAt, DateTime(2026, 11, 23, 10));
    });
    test('quiet end later today still counts against "never after the day"', () {
      // Occasion today, now 12:00, quiet hours until 13:00 → 13:00 today is fine.
      final p = _plan(
        now: DateTime(2026, 11, 26, 12),
        upcoming: [_occ(DateTime(2026, 11, 26))],
        quietStart: 22 * 60,
        quietEnd: 13 * 60,
      );
      expect(p.single.fireAt, DateTime(2026, 11, 26, 13));
    });
    test('inQuietHours', () {
      expect(ReminderPlanner.inQuietHours(22 * 60, 21 * 60, 9 * 60), isTrue);
      expect(ReminderPlanner.inQuietHours(3 * 60, 21 * 60, 9 * 60), isTrue);
      expect(ReminderPlanner.inQuietHours(9 * 60, 21 * 60, 9 * 60), isFalse);
      expect(ReminderPlanner.inQuietHours(21 * 60, 21 * 60, 9 * 60), isTrue);
      expect(ReminderPlanner.inQuietHours(12 * 60, 21 * 60, 9 * 60), isFalse);
      expect(ReminderPlanner.inQuietHours(10 * 60, 9 * 60, 17 * 60), isTrue);
      expect(ReminderPlanner.inQuietHours(17 * 60, 9 * 60, 17 * 60), isFalse);
      expect(ReminderPlanner.inQuietHours(5 * 60, 7 * 60, 7 * 60), isFalse);
    });
  });

  group('frequency limits', () {
    // Fire days: 10, 11, 12, 20 Nov (occasions three days later).
    final four = [
      _occ(DateTime(2026, 11, 23), id: 'thanksgiving'),
      _occ(DateTime(2026, 11, 13), id: 'halloween'),
      _occ(DateTime(2026, 11, 14), id: 'diwali'),
      _occ(DateTime(2026, 11, 15), id: 'new_year'),
    ];
    List<DateTime> days(List<PlannedReminder> p) => [for (final r in p) r.fireAt];

    test('weekly1: at most one in any 7 days, nearer wins', () {
      final p = _plan(now: now, upcoming: four, frequency: ReminderFrequency.weekly1);
      expect(days(p), [DateTime(2026, 11, 10, 10), DateTime(2026, 11, 20, 10)]);
      expect(p.first.occasion!.id, 'halloween');
    });
    test('weekly2: at most two in any 7 days', () {
      final p = _plan(now: now, upcoming: four, frequency: ReminderFrequency.weekly2);
      expect(days(p), [
        DateTime(2026, 11, 10, 10),
        DateTime(2026, 11, 11, 10),
        DateTime(2026, 11, 20, 10),
      ]);
    });
    test('monthly1: at most one in any 30 days', () {
      final p = _plan(
        now: now,
        upcoming: [
          _occ(DateTime(2026, 11, 13)),
          _occ(DateTime(2026, 12, 8)), // fires 5 Dec, 25 days later → dropped
          _occ(DateTime(2026, 12, 18)), // fires 15 Dec, 35 days later → kept
        ],
        frequency: ReminderFrequency.monthly1,
      );
      expect(days(p), [DateTime(2026, 11, 10, 10), DateTime(2026, 12, 15, 10)]);
    });
    test('weekly1: exactly seven days apart is allowed', () {
      final p = _plan(
        now: now,
        upcoming: [_occ(DateTime(2026, 11, 13)), _occ(DateTime(2026, 11, 20))],
        frequency: ReminderFrequency.weekly1,
      );
      expect(p, hasLength(2));
    });
    test('never more than maxScheduled, ids start at 7100', () {
      final many = [for (var i = 0; i < 20; i++) _occ(DateTime(2026, 11, 13 + i * 7))];
      final p = _plan(now: now, upcoming: many, frequency: ReminderFrequency.weekly2);
      expect(p, hasLength(ReminderPlanner.maxScheduled));
      expect(ReminderPlanner.maxScheduled, 8);
      expect([for (final r in p) r.id], [for (var i = 0; i < 8; i++) 7100 + i]);
      expect(p.first.fireAt, DateTime(2026, 11, 10, 10));
    });
    test('ids are contiguous even when candidates are dropped', () {
      final p = _plan(now: now, upcoming: four, frequency: ReminderFrequency.weekly1);
      expect([for (final r in p) r.id], [7100, 7101]);
    });
  });

  group('memories', () {
    MemoryDate mem(DateTime d) => MemoryDate(date: d, yearsAgo: 2, photos: 9);

    test('announced on the day itself at 10:00', () {
      final p = _plan(now: now, memories: [mem(DateTime(2026, 11, 20))]);
      expect(p.single.fireAt, DateTime(2026, 11, 20, 10));
      expect(p.single.memory, isNotNull);
      expect(p.single.occasion, isNull);
    });
    test('a memory today after 10:00 is skipped', () {
      expect(_plan(now: DateTime(2026, 11, 20, 11), memories: [mem(DateTime(2026, 11, 20))]), isEmpty);
    });
    test('memories share the frequency limit with occasions', () {
      final p = _plan(
        now: now,
        upcoming: [_occ(DateTime(2026, 11, 23))], // fires 20 Nov
        memories: [mem(DateTime(2026, 11, 21))],
        frequency: ReminderFrequency.weekly1,
      );
      expect(p.single.occasion, isNotNull);
    });
  });

  group('payloads', () {
    final b1 = const Birthday(id: 'b1', name: 'Ana', month: 11, day: 6);
    final b2 = const Birthday(id: 'b2', name: 'Bo', month: 11, day: 6);
    final candidates = _svc.occurrences(
      from: DateTime(2026, 10, 1),
      to: DateTime(2027, 12, 31),
      region: 'US',
      birthdays: [b1, b2],
    );

    test('occasionPayload is occ:<key>', () {
      final h = candidates.firstWhere((o) => o.id == 'halloween');
      expect(ReminderService.occasionPayload(h), 'occ:halloween@2026-10-31');
      final b = candidates.firstWhere((o) => o.birthday?.id == 'b2');
      expect(ReminderService.occasionPayload(b), 'occ:birthday:b2@2026-11-06');
    });
    test('occ: payload resolves the exact occurrence', () {
      for (final o in candidates) {
        expect(ReminderService.matchOccasionPayload(ReminderService.occasionPayload(o), candidates), same(o));
      }
      final m = ReminderService.matchOccasionPayload('occ:christmas@2027-12-25', candidates)!;
      expect(m.date, DateTime(2027, 12, 25));
    });
    test('occ: payload resolves a specific birthday', () {
      final m = ReminderService.matchOccasionPayload('occ:birthday:b2@2026-11-06', candidates)!;
      expect(m.birthday!.id, 'b2');
      expect(m.birthday!.name, 'Bo');
    });
    test('legacy bare id resolves to the first non-birthday candidate', () {
      final m = ReminderService.matchOccasionPayload('christmas', candidates)!;
      expect(m.key, 'christmas@2026-12-25');
      expect(ReminderService.matchOccasionPayload('birthday', candidates), isNull);
    });
    test('export / memory payloads give null', () {
      expect(ReminderService.matchOccasionPayload(ReminderService.exportPayload, candidates), isNull);
      expect(ReminderService.matchOccasionPayload(ReminderService.memoryPayload, candidates), isNull);
      expect(ReminderService.exportPayload, 'export');
      expect(ReminderService.memoryPayload, 'memory');
    });
    test('unknown keys and ids give null', () {
      expect(ReminderService.matchOccasionPayload('occ:birthday:gone@2026-11-06', candidates), isNull);
      expect(ReminderService.matchOccasionPayload('occ:christmas@2030-12-25', candidates), isNull);
      expect(ReminderService.matchOccasionPayload('occ:', candidates), isNull);
      expect(ReminderService.matchOccasionPayload('nope', candidates), isNull);
      expect(ReminderService.matchOccasionPayload('', candidates), isNull);
      expect(ReminderService.matchOccasionPayload('occ:halloween@2026-10-31', const []), isNull);
    });
  });

  test('weekly window counts calendar days across a DST change', () {
    // Europe moves to summer time on 29 Mar 2026. Reminders on 22 and 29 Mar
    // at 10:00 are exactly one week apart and must both be kept with weekly1
    // (in a non-DST time zone this simply passes).
    final p = _plan(
      now: DateTime(2026, 3, 18, 8),
      upcoming: [_occ(DateTime(2026, 3, 25)), _occ(DateTime(2026, 4, 1), id: 'halloween')],
      frequency: ReminderFrequency.weekly1,
    );
    expect(p.map((r) => r.fireAt), [DateTime(2026, 3, 22, 10), DateTime(2026, 3, 29, 10)]);
  });
}
