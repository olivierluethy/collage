import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:collage/models/collage_project.dart';
import 'package:collage/models/layout_template.dart';
import 'package:collage/services/library_index_service.dart';
import 'package:collage/services/permission_service.dart';
import 'package:collage/services/photo_usage.dart';
import 'package:collage/services/prefs_service.dart';
import 'package:collage/state/library_index.dart';
import 'package:collage/state/providers.dart';

/// Local wall-clock time as capture seconds (what photo_manager reports).
int _s(int y, int m, int d, [int h = 12, int min = 0, int sec = 0]) =>
    DateTime(y, m, d, h, min, sec).millisecondsSinceEpoch ~/ 1000;

LibraryIndex _index(Map<String, int> entries, {int? count, int maxModified = 100, bool limited = false}) =>
    LibraryIndex.fromEntries(entries, count: count ?? entries.length, maxModified: maxModified, limited: limited);

CollageProject _collage(String id, List<String> assets) => CollageProject(
      id: id,
      title: id,
      createdAt: 1,
      updatedAt: 1,
      ratioLabel: '1:1',
      layout: const LayoutTemplate(
        id: 'one',
        name: 'One',
        family: LayoutFamily.grid,
        slots: [LayoutSlot(id: 's1', rect: Rect.fromLTWH(0, 0, 1, 1))],
      ),
      fills: {for (var i = 0; i < assets.length; i++) 's$i': SlotFill(assetId: assets[i])},
      elements: [],
      border: BorderSettings(),
      background: BackgroundSettings(),
    );

// ---- fakes for LibraryIndexNotifier ------------------------------------------

class _FakePermissions extends PermissionService {
  _FakePermissions(this.access);
  GalleryAccess access;
  @override
  Future<GalleryAccess> current() async => access;
}

class _FakeIndexService extends LibraryIndexService {
  _FakeIndexService({this.cache, required this.fp, this.built, this.updated});

  LibraryIndex? cache;
  ({int count, int maxModified}) fp;
  LibraryIndex? built;
  LibraryIndex? updated;
  Object? throwOnFingerprint;

  int loadCalls = 0, fpCalls = 0, buildCalls = 0, updateCalls = 0, clearCalls = 0;
  bool? builtLimited;

  @override
  Future<LibraryIndex?> loadCache() async {
    loadCalls++;
    return cache;
  }

  @override
  Future<void> clearCache() async => clearCalls++;

  @override
  Future<({int count, int maxModified})> fingerprint() async {
    fpCalls++;
    if (throwOnFingerprint != null) throw throwOnFingerprint!;
    return fp;
  }

  @override
  Future<LibraryIndex> build({required bool limited, void Function(int done, int total)? onProgress}) async {
    buildCalls++;
    builtLimited = limited;
    onProgress?.call(fp.count, fp.count);
    return built!;
  }

  @override
  Future<LibraryIndex?> update(LibraryIndex old,
      {required int count, required bool limited, void Function(int done, int total)? onProgress}) async {
    updateCalls++;
    return updated;
  }
}

ProviderContainer _container(_FakeIndexService svc, _FakePermissions perms) {
  final c = ProviderContainer(overrides: [
    libraryIndexServiceProvider.overrideWithValue(svc),
    permissionServiceProvider.overrideWithValue(perms),
  ]);
  addTearDown(c.dispose);
  return c;
}

void main() {
  group('day / month keys', () {
    test('dayKeyOf is yyyymmdd and dayOfKey inverts it', () {
      expect(dayKeyOf(DateTime(2026, 11, 3, 23, 59)), 20261103);
      expect(dayKeyOf(DateTime(2024, 2, 29)), 20240229);
      expect(dayKeyOf(DateTime(1999, 12, 31)), 19991231);
      expect(dayOfKey(20240229), DateTime(2024, 2, 29));
      expect(dayOfKey(20261231), DateTime(2026, 12, 31));
      for (final d in [DateTime(2026, 1, 1), DateTime(2025, 12, 31), DateTime(2024, 2, 29), DateTime(2000, 10, 9)]) {
        expect(dayOfKey(dayKeyOf(d)), d);
      }
    });

    test('key order matches chronological order across month/year boundaries', () {
      final days = [DateTime(2025, 12, 31), DateTime(2026, 1, 1), DateTime(2026, 1, 31), DateTime(2026, 2, 1), DateTime(2026, 10, 1)];
      final keys = days.map(dayKeyOf).toList();
      expect(keys, [...keys]..sort());
      expect(monthKeyOf(2025, 12) < monthKeyOf(2026, 1), isTrue);
      expect(monthKeyOf(2026, 12), 202612);
    });
  });

  group('LibraryIndex bucketing', () {
    final entries = {
      'nye-late': _s(2025, 12, 31, 23, 59, 59),
      'ny-early': _s(2026, 1, 1, 0, 0, 1),
      'ny-noon': _s(2026, 1, 1, 12),
      'leap': _s(2024, 2, 29, 8),
      'mar1': _s(2024, 3, 1, 0, 0),
      'jan15': _s(2026, 1, 15),
      'u1': 0,
      'u2': 0,
    };
    final idx = _index(entries, count: 8);

    test('totals and undated', () {
      expect(idx.total, 8);
      expect(idx.isEmpty, isFalse);
      expect(idx.ids.length, 6);
      expect(idx.undated.toSet(), {'u1', 'u2'});
      expect(idx.dayCount(kUndatedDay), 2);
      expect(idx.idsForDay(kUndatedDay).toSet(), {'u1', 'u2'});
      expect(idx.dayOf('u1'), kUndatedDay);
    });

    test('ids are sorted by capture time', () {
      expect(idx.ids, ['leap', 'mar1', 'nye-late', 'ny-early', 'ny-noon', 'jan15']);
      for (var i = 1; i < idx.times.length; i++) {
        expect(idx.times[i] >= idx.times[i - 1], isTrue);
      }
    });

    test('Dec 31 23:59:59 and Jan 1 00:00:01 land on different local days and years', () {
      expect(idx.dayOf('nye-late'), 20251231);
      expect(idx.dayOf('ny-early'), 20260101);
      expect(idx.dayCount(20251231), 1);
      expect(idx.dayCount(20260101), 2);
      expect(idx.yearCount(2025), 1);
      expect(idx.yearCount(2026), 3);
      expect(idx.monthCount(2025, 12), 1);
      expect(idx.monthCount(2026, 1), 3);
    });

    test('leap day and the day after', () {
      expect(idx.dayOf('leap'), 20240229);
      expect(idx.dayOf('mar1'), 20240301);
      expect(idx.dayCounts(2024, 2), {29: 1});
      expect(idx.dayCounts(2024, 3), {1: 1});
      expect(idx.monthCounts(2024), [0, 1, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0]);
    });

    test('years newest first with counts; counts sum to dated total', () {
      expect(idx.years, [(2026, 3), (2025, 1), (2024, 2)]);
      expect(idx.years.fold<int>(0, (n, y) => n + y.$2), idx.ids.length);
      expect(idx.yearCount(1990), 0);
    });

    test('dayCounts, monthCounts and dayKeys / monthKeys', () {
      expect(idx.dayCounts(2026, 1), {1: 2, 15: 1});
      expect(idx.dayCounts(2026, 2), isEmpty);
      expect(idx.monthCounts(2026)[0], 3);
      expect(idx.dayKeys, [20240229, 20240301, 20251231, 20260101, 20260115]);
      expect(idx.monthKeys, [202402, 202403, 202512, 202601]);
      expect(idx.firstDay, DateTime(2024, 2, 29));
      expect(idx.lastDay, DateTime(2026, 1, 15));
    });

    test('idsForDay returns the day in capture order, empty for unknown days', () {
      expect(idx.idsForDay(20260101), ['ny-early', 'ny-noon']);
      expect(idx.idsForDay(20260102), isEmpty);
      expect(idx.dayOf('nope'), isNull);
    });

    test('photos with the same second are ordered by id', () {
      final t = _s(2026, 5, 5);
      final i = _index({'b': t, 'a': t, 'c': t});
      expect(i.idsForDay(20260505), ['a', 'b', 'c']);
    });

    test('local-day handling: a UTC instant is bucketed by its local calendar day', () {
      final utc = DateTime.utc(2026, 1, 1, 0, 30);
      final i = _index({'x': utc.millisecondsSinceEpoch ~/ 1000});
      expect(i.dayOf('x'), dayKeyOf(utc.toLocal()));
    });

    test('negative capture seconds are treated as undated', () {
      final i = _index({'old': -100, 'new': _s(2026, 1, 1)});
      expect(i.undated, ['old']);
      expect(i.ids, ['new']);
    });
  });

  group('navigation', () {
    final idx = _index({
      'a': _s(2026, 1, 1),
      'b': _s(2026, 1, 3),
      'c': _s(2026, 3, 10),
    });

    test('nearestDay: exact, between (tie goes to the earlier day), before first, after last', () {
      expect(idx.nearestDay(DateTime(2026, 1, 3, 18)), 20260103);
      expect(idx.nearestDay(DateTime(2026, 1, 2)), 20260101);
      expect(idx.nearestDay(DateTime(2026, 3, 9)), 20260310);
      expect(idx.nearestDay(DateTime(2025, 6, 1)), 20260101);
      expect(idx.nearestDay(DateTime(2027, 6, 1)), 20260310);
    });

    test('adjacentDay / adjacentMonth', () {
      expect(idx.adjacentDay(20260101, 1), 20260103);
      expect(idx.adjacentDay(20260101, -1), isNull);
      expect(idx.adjacentDay(20260310, 1), isNull);
      expect(idx.adjacentDay(20260202, 1), 20260310); // key without photos
      expect(idx.adjacentDay(20260202, -1), 20260103);
      expect(idx.adjacentMonth(202601, 1), 202603);
      expect(idx.adjacentMonth(202603, -1), 202601);
      expect(idx.adjacentMonth(202602, -1), 202601);
    });
  });

  group('empty library', () {
    test('LibraryIndex.empty and fromEntries({}) answer every query safely', () {
      for (final idx in [LibraryIndex.empty, _index(const {})]) {
        expect(idx.isEmpty, isTrue);
        expect(idx.total, 0);
        expect(idx.years, isEmpty);
        expect(idx.monthCounts(2026), List.filled(12, 0));
        expect(idx.dayCounts(2026, 1), isEmpty);
        expect(idx.dayCount(20260101), 0);
        expect(idx.dayCount(kUndatedDay), 0);
        expect(idx.idsForDay(20260101), isEmpty);
        expect(idx.firstDay, isNull);
        expect(idx.lastDay, isNull);
        expect(idx.nearestDay(DateTime(2026)), isNull);
        expect(idx.adjacentDay(20260101, 1), isNull);
        expect(idx.adjacentMonth(202601, -1), isNull);
      }
    });

    test('only undated photos', () {
      final idx = _index({'u': 0});
      expect(idx.isEmpty, isFalse);
      expect(idx.dayKeys, isEmpty);
      expect(idx.firstDay, isNull);
      expect(idx.dayCount(kUndatedDay), 1);
    });
  });

  group('cache format', () {
    test('encode / decode round-trips ids, times, undated and header', () {
      final idx = _index({
        'a': _s(2025, 12, 31, 23, 59),
        'b': _s(2026, 1, 1, 0, 1),
        'ABC/def-123_L0_001': _s(2024, 2, 29),
        'u': 0,
      }, count: 4, maxModified: 1234567, limited: true);
      final back = LibraryIndex.decode(idx.encode())!;
      expect(back.ids, idx.ids);
      expect(back.times, idx.times);
      expect(back.undated, idx.undated);
      expect(back.count, 4);
      expect(back.maxModified, 1234567);
      expect(back.limited, isTrue);
      expect(back.dayKeys, idx.dayKeys);
      expect(back.years, idx.years);
      expect(back.toEntries(), idx.toEntries());
    });

    test('empty index round-trips', () {
      final back = LibraryIndex.decode(LibraryIndex.empty.encode())!;
      expect(back.isEmpty, isTrue);
      expect(back.count, 0);
      expect(back.limited, isFalse);
    });

    test('an id containing a tab survives (last tab separates the time)', () {
      final idx = _index({'we\tird': _s(2026, 1, 1)});
      expect(LibraryIndex.decode(idx.encode())!.ids, ['we\tird']);
    });

    test('header format', () {
      final head = _index({'a': 5}, count: 1, maxModified: 9).encode().split('\n').first;
      expect(head, 'collage-index\t1\t1\t9\t0');
    });

    test('rejects other versions, foreign files and damaged lines', () {
      expect(LibraryIndex.decode(''), isNull);
      expect(LibraryIndex.decode('hello'), isNull);
      expect(LibraryIndex.decode('collage-index\t2\t0\t0\t0\n'), isNull);
      expect(LibraryIndex.decode('other\t1\t0\t0\t0\n'), isNull);
      expect(LibraryIndex.decode('collage-index\t1\t1\t0\t0\nno-tab-here\n'), isNull);
      expect(LibraryIndex.decode('collage-index\t1\t1\t0\t0\nid\tNaN\n'), isNull);
      expect(LibraryIndex.decode('collage-index\t1\t1\t0\t0\n\t5\n'), isNull);
    });

    test('a non-numeric count in the header decodes as -1 (forces a refresh)', () {
      final back = LibraryIndex.decode('collage-index\t1\tx\ty\t0\n')!;
      expect(back.count, -1);
      expect(back.maxModified, -1);
    });

    test('toEntries + fromEntries (incremental merge) re-sorts', () {
      final old = _index({'a': _s(2026, 1, 2), 'b': _s(2026, 1, 3)});
      final merged = _index(old.toEntries()..addAll({'a': _s(2026, 1, 4), 'c': _s(2026, 1, 1)}));
      expect(merged.ids, ['c', 'b', 'a']);
      expect(merged.total, 3);
    });
  });

  group('LibraryIndexState', () {
    test('progress', () {
      expect(const LibraryIndexState().progress, isNull);
      expect(const LibraryIndexState(done: 5, total: 10).progress, 0.5);
      expect(const LibraryIndexState(done: 15, total: 10).progress, 1.0);
    });

    test('copy keeps fields, clearIndex drops the index and error is reset', () {
      final s = LibraryIndexState(access: GalleryAccess.granted, index: LibraryIndex.empty, error: 'x');
      final c = s.copy(indexing: true);
      expect(c.access, GalleryAccess.granted);
      expect(c.index, same(LibraryIndex.empty));
      expect(c.indexing, isTrue);
      expect(c.error, isNull);
      expect(s.copy(clearIndex: true).index, isNull);
    });
  });

  group('LibraryIndexNotifier.ensureFresh (fake service)', () {
    final cached = _index({'a': _s(2026, 1, 1)}, count: 1, maxModified: 50);
    final fresh = _index({'a': _s(2026, 1, 1), 'b': _s(2026, 1, 2)}, count: 2, maxModified: 60);

    test('denied access shows no index and never touches the library', () async {
      final svc = _FakeIndexService(cache: cached, fp: (count: 1, maxModified: 50));
      final c = _container(svc, _FakePermissions(GalleryAccess.denied));
      await c.read(libraryIndexProvider.notifier).ensureFresh();
      expect(c.read(libraryIndexProvider).access, GalleryAccess.denied);
      expect(c.read(libraryIndexDataProvider), isNull);
      expect(svc.fpCalls, 0);
    });

    test('a current cache is used without rebuilding, and re-checks are throttled', () async {
      final svc = _FakeIndexService(cache: cached, fp: (count: 1, maxModified: 50));
      final c = _container(svc, _FakePermissions(GalleryAccess.granted));
      final n = c.read(libraryIndexProvider.notifier);
      await n.ensureFresh();
      expect(c.read(libraryIndexDataProvider), same(cached));
      expect(svc.buildCalls + svc.updateCalls, 0);
      await n.ensureFresh();
      expect(svc.fpCalls, 1, reason: 'second call within 30 s is throttled');
      await n.ensureFresh(force: true);
      expect(svc.fpCalls, 2);
    });

    test('a stale cache is updated incrementally', () async {
      final svc = _FakeIndexService(cache: cached, fp: (count: 2, maxModified: 60), updated: fresh);
      final c = _container(svc, _FakePermissions(GalleryAccess.granted));
      await c.read(libraryIndexProvider.notifier).ensureFresh();
      expect(svc.updateCalls, 1);
      expect(svc.buildCalls, 0);
      final s = c.read(libraryIndexProvider);
      expect(s.index, same(fresh));
      expect(s.indexing, isFalse);
      expect(s.total, 0);
    });

    test('falls back to a full build when the update cannot be trusted', () async {
      final svc = _FakeIndexService(cache: cached, fp: (count: 2, maxModified: 60), updated: null, built: fresh);
      final c = _container(svc, _FakePermissions(GalleryAccess.granted));
      await c.read(libraryIndexProvider.notifier).ensureFresh();
      expect(svc.updateCalls, 1);
      expect(svc.buildCalls, 1);
      expect(c.read(libraryIndexDataProvider), same(fresh));
    });

    test('limited access drops a full-access cache and builds a limited index', () async {
      final svc = _FakeIndexService(cache: cached, fp: (count: 1, maxModified: 50), built: fresh);
      final c = _container(svc, _FakePermissions(GalleryAccess.limited));
      await c.read(libraryIndexProvider.notifier).ensureFresh();
      expect(svc.updateCalls, 0);
      expect(svc.buildCalls, 1);
      expect(svc.builtLimited, isTrue);
    });

    test('an empty library yields LibraryIndex.empty and clears the cache', () async {
      final svc = _FakeIndexService(cache: cached, fp: (count: 0, maxModified: 0));
      final c = _container(svc, _FakePermissions(GalleryAccess.granted));
      await c.read(libraryIndexProvider.notifier).ensureFresh();
      expect(c.read(libraryIndexDataProvider)!.isEmpty, isTrue);
      expect(svc.clearCalls, 1);
    });

    test('a platform error is kept in state and indexing stops', () async {
      final svc = _FakeIndexService(cache: cached, fp: (count: 1, maxModified: 50))..throwOnFingerprint = StateError('boom');
      final c = _container(svc, _FakePermissions(GalleryAccess.granted));
      final n = c.read(libraryIndexProvider.notifier);
      await n.ensureFresh();
      final s = c.read(libraryIndexProvider);
      expect(s.error, isA<StateError>());
      expect(s.indexing, isFalse);
      // Not stuck in "running": a retry reaches the service again.
      svc.throwOnFingerprint = null;
      await n.ensureFresh(force: true);
      expect(svc.fpCalls, 2);
      expect(c.read(libraryIndexProvider).error, isNull);
    });
  });

  group('usedPerDay and discover suggestions', () {
    late PrefsService prefs;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      prefs = await PrefsService.create();
    });

    ProviderContainer make(LibraryIndex idx, List<CollageProject> collages) {
      final c = ProviderContainer(overrides: [
        prefsProvider.overrideWithValue(prefs),
        libraryIndexDataProvider.overrideWithValue(idx),
        photoUsageProvider.overrideWithValue(PhotoUsageIndex(collages)),
      ]);
      addTearDown(c.dispose);
      return c;
    }

    test('usedPerDayProvider counts used photos per capture day', () {
      final idx = _index({'a': _s(2026, 1, 1), 'b': _s(2026, 1, 1, 13), 'c': _s(2026, 1, 2), 'u': 0});
      final c = make(idx, [
        _collage('x', ['a', 'b']),
        _collage('y', ['b', 'c', 'u', 'not-in-index']),
      ]);
      // 'b' is in two collages but counted once (distinct used assets).
      expect(c.read(usedPerDayProvider), {20260101: 2, 20260102: 1, kUndatedDay: 1});
    });

    test('suggestions: on-this-day first (max 2), then most recent; used and dismissed days skipped', () async {
      final now = DateTime.now();
      Map<String, int> day(String p, DateTime d, int n) => {for (var i = 0; i < n; i++) '$p$i': _s(d.year, d.month, d.day, 10, i)};
      // Avoid Feb 29 edge cases on the "on this day" probes.
      final m = now.month, d = now.day;
      final entries = <String, int>{
        ...day('y1-', DateTime(now.year - 1, m, d), 5),
        ...day('y2-', DateTime(now.year - 2, m, d), 4),
        ...day('y3-', DateTime(now.year - 3, m, d), 6),
        ...day('few-', DateTime(now.year - 4, m, d), 3), // too few photos
        ...day('r1-', DateTime(2000, 1, 10), 4),
        ...day('r2-', DateTime(2000, 1, 11), 4),
        ...day('r3-', DateTime(2000, 1, 12), 4),
      };
      if (m == 2 && d == 29) return; // years without Feb 29 would not match.
      final idx = _index(entries);
      final c = make(idx, [_collage('used', ['r3-0'])]);
      var s = c.read(discoverSuggestionsProvider);
      expect(s.map((e) => e.onThisDay), [true, true, false, false]);
      expect(s[0].day, dayKeyOf(DateTime(now.year - 1, m, d)));
      expect(s[0].count, 5);
      expect(s[1].day, dayKeyOf(DateTime(now.year - 2, m, d)));
      // Most recent day with photos first; the earlier "on this day" picks are
      // not repeated, r3 is used.
      expect(s[2].day, dayKeyOf(DateTime(now.year - 3, m, d)));
      expect(s[3].day, 20000111);

      await c.read(dismissedDaysProvider.notifier).dismiss(dayKeyOf(DateTime(now.year - 1, m, d)));
      s = c.read(discoverSuggestionsProvider);
      expect(s.first.day, dayKeyOf(DateTime(now.year - 2, m, d)));
      expect(s.where((e) => e.onThisDay).length, 2); // y2 and y3
      expect(prefs.discoverDismissedDays, {dayKeyOf(DateTime(now.year - 1, m, d))});
    });

    test('no suggestions for an empty index', () {
      final c = make(LibraryIndex.empty, const []);
      expect(c.read(discoverSuggestionsProvider), isEmpty);
    });
  });
}
