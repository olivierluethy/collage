import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;

import 'package:path_provider/path_provider.dart';
import 'package:photo_manager/photo_manager.dart';

/// Day key for photos without any usable date ("Undated").
const int kUndatedDay = 0;

/// `yyyymmdd` key of a local calendar day. Ordering of keys matches
/// chronological ordering, so sorted key lists can be binary-searched.
int dayKeyOf(DateTime d) => d.year * 10000 + d.month * 100 + d.day;

/// The local midnight of a [dayKeyOf] key.
DateTime dayOfKey(int key) => DateTime(key ~/ 10000, (key ~/ 100) % 100, key % 100);

/// `yyyymm` key of a month.
int monthKeyOf(int year, int month) => year * 100 + month;

/// A lightweight, query-ready index of every image in the library: asset id +
/// capture time (seconds), bucketed by year / month / day.
///
/// Built off the UI isolate (see [LibraryIndex.fromEntries]); all queries are
/// O(1) map lookups or O(log days) binary searches, except where noted.
class LibraryIndex {
  LibraryIndex._({
    required this.ids,
    required this.times,
    required this.undated,
    required this.count,
    required this.maxModified,
    required this.limited,
  }) {
    _derive();
  }

  /// Dated asset ids, ascending by capture time.
  final List<String> ids;

  /// Capture time in seconds since epoch, parallel to [ids].
  final List<int> times;

  /// Assets with no capture and no modified date.
  final List<String> undated;

  /// Library count when this index was built (change detection).
  final int count;

  /// Newest modified-date (seconds) seen when built (change detection).
  final int maxModified;

  /// Built under limited ("selected photos") access.
  final bool limited;

  final _dayStart = <int, int>{};
  final _dayCount = <int, int>{};
  final _monthCount = <int, int>{};
  final _yearCount = <int, int>{};
  final _dayOfId = <String, int>{};

  /// Every day key with photos, ascending (no [kUndatedDay]).
  final dayKeys = <int>[];

  /// Every month key with photos, ascending.
  final monthKeys = <int>[];

  static final empty = LibraryIndex._(
    ids: const [],
    times: const [],
    undated: const [],
    count: 0,
    maxModified: 0,
    limited: false,
  );

  int get total => ids.length + undated.length;
  bool get isEmpty => total == 0;

  /// O(n): one pass over the sorted entries. Runs inside the build isolate.
  void _derive() {
    var prev = -1;
    for (var i = 0; i < ids.length; i++) {
      final d = DateTime.fromMillisecondsSinceEpoch(times[i] * 1000);
      final key = dayKeyOf(d);
      if (key != prev) {
        _dayStart[key] = i;
        dayKeys.add(key);
        final mk = monthKeyOf(d.year, d.month);
        if (monthKeys.isEmpty || monthKeys.last != mk) monthKeys.add(mk);
        prev = key;
      }
      _dayCount[key] = (_dayCount[key] ?? 0) + 1;
      final mk = monthKeyOf(d.year, d.month);
      _monthCount[mk] = (_monthCount[mk] ?? 0) + 1;
      _yearCount[d.year] = (_yearCount[d.year] ?? 0) + 1;
      _dayOfId[ids[i]] = key;
    }
    for (final id in undated) {
      _dayOfId[id] = kUndatedDay;
    }
  }

  /// Sorts raw entries and builds the derived buckets. O(n log n); call it via
  /// `Isolate.run` so the UI isolate never pays for it.
  static LibraryIndex fromEntries(
    Map<String, int> entries, {
    required int count,
    required int maxModified,
    required bool limited,
  }) {
    final dated = <MapEntry<String, int>>[];
    final undated = <String>[];
    for (final e in entries.entries) {
      if (e.value > 0) {
        dated.add(e);
      } else {
        undated.add(e.key);
      }
    }
    dated.sort((a, b) {
      final c = a.value.compareTo(b.value);
      return c != 0 ? c : a.key.compareTo(b.key);
    });
    return LibraryIndex._(
      ids: [for (final e in dated) e.key],
      times: [for (final e in dated) e.value],
      undated: undated,
      count: count,
      maxModified: maxModified,
      limited: limited,
    );
  }

  /// Raw `id → capture seconds` entries (for incremental merges). O(n).
  Map<String, int> toEntries() => {
        for (var i = 0; i < ids.length; i++) ids[i]: times[i],
        for (final id in undated) id: 0,
      };

  // ---- Queries -----------------------------------------------------------

  /// Years with photos and their counts, newest first.
  List<(int year, int count)> get years {
    final ys = _yearCount.keys.toList()..sort((a, b) => b.compareTo(a));
    return [for (final y in ys) (y, _yearCount[y]!)];
  }

  int yearCount(int year) => _yearCount[year] ?? 0;

  /// Photo count per month of [year] (index 0 = January).
  List<int> monthCounts(int year) =>
      [for (var m = 1; m <= 12; m++) _monthCount[monthKeyOf(year, m)] ?? 0];

  int monthCount(int year, int month) => _monthCount[monthKeyOf(year, month)] ?? 0;

  /// Photo count per day of the month (only days with photos).
  Map<int, int> dayCounts(int year, int month) {
    final out = <int, int>{};
    final base = year * 10000 + month * 100;
    for (var d = 1; d <= 31; d++) {
      final c = _dayCount[base + d];
      if (c != null) out[d] = c;
    }
    return out;
  }

  int dayCount(int key) => key == kUndatedDay ? undated.length : (_dayCount[key] ?? 0);

  /// Asset ids taken on [key], in capture order (oldest first).
  List<String> idsForDay(int key) {
    if (key == kUndatedDay) return undated;
    final start = _dayStart[key];
    if (start == null) return const [];
    return ids.sublist(start, start + _dayCount[key]!);
  }

  /// The day an asset was taken on, or null when it is not in the index.
  int? dayOf(String assetId) => _dayOfId[assetId];

  DateTime? get firstDay => dayKeys.isEmpty ? null : dayOfKey(dayKeys.first);
  DateTime? get lastDay => dayKeys.isEmpty ? null : dayOfKey(dayKeys.last);

  /// The day with photos closest to [day] (itself when it has photos).
  int? nearestDay(DateTime day) {
    if (dayKeys.isEmpty) return null;
    final key = dayKeyOf(day);
    final i = _lowerBound(dayKeys, key);
    if (i < dayKeys.length && dayKeys[i] == key) return key;
    final after = i < dayKeys.length ? dayKeys[i] : null;
    final before = i > 0 ? dayKeys[i - 1] : null;
    if (after == null) return before;
    if (before == null) return after;
    final target = DateTime(day.year, day.month, day.day);
    final da = dayOfKey(after).difference(target).inHours.abs();
    final db = target.difference(dayOfKey(before)).inHours.abs();
    return db <= da ? before : after;
  }

  /// The next (`dir > 0`) or previous day with photos, or null.
  int? adjacentDay(int key, int dir) => _adjacent(dayKeys, key, dir);

  /// The next (`dir > 0`) or previous month key with photos, or null.
  int? adjacentMonth(int monthKey, int dir) => _adjacent(monthKeys, monthKey, dir);

  static int? _adjacent(List<int> keys, int key, int dir) {
    if (keys.isEmpty) return null;
    final i = _lowerBound(keys, key);
    if (dir > 0) {
      final j = (i < keys.length && keys[i] == key) ? i + 1 : i;
      return j < keys.length ? keys[j] : null;
    }
    return i > 0 ? keys[i - 1] : null;
  }

  static int _lowerBound(List<int> list, int value) {
    var lo = 0, hi = list.length;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (list[mid] < value) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    return lo;
  }

  // ---- Cache format --------------------------------------------------------
  //
  // Line 1: `collage-index\t<version>\t<count>\t<maxModified>\t<limited 0|1>`
  // Then one `<id>\t<seconds>` line per asset. Plain text keeps it compact
  // (~45 bytes per photo on iOS) and fast to split. O(n) both ways.

  static const _magic = 'collage-index';
  static const _version = 1;

  String encode() {
    final b = StringBuffer()
      ..writeln('$_magic\t$_version\t$count\t$maxModified\t${limited ? 1 : 0}');
    for (var i = 0; i < ids.length; i++) {
      b
        ..write(ids[i])
        ..write('\t')
        ..writeln(times[i]);
    }
    for (final id in undated) {
      b.writeln('$id\t0');
    }
    return b.toString();
  }

  /// Parses [encode]'s output; null when the file is from another version or
  /// damaged. Expects lines already sorted (as written), so no re-sort.
  static LibraryIndex? decode(String raw) {
    final lines = raw.split('\n');
    if (lines.isEmpty) return null;
    final head = lines.first.split('\t');
    if (head.length < 5 || head[0] != _magic || head[1] != '$_version') return null;
    final ids = <String>[];
    final times = <int>[];
    final undated = <String>[];
    for (var i = 1; i < lines.length; i++) {
      final line = lines[i];
      if (line.isEmpty) continue;
      final tab = line.lastIndexOf('\t');
      if (tab <= 0) return null;
      final t = int.tryParse(line.substring(tab + 1));
      if (t == null) return null;
      final id = line.substring(0, tab);
      if (t > 0) {
        ids.add(id);
        times.add(t);
      } else {
        undated.add(id);
      }
    }
    return LibraryIndex._(
      ids: ids,
      times: times,
      undated: undated,
      count: int.tryParse(head[2]) ?? -1,
      maxModified: int.tryParse(head[3]) ?? -1,
      limited: head[4] == '1',
    );
  }
}

/// Builds, caches and refreshes the [LibraryIndex].
///
/// Platform calls (photo_manager) stay on the UI isolate but are paged in
/// chunks of [chunk] with a yield in between, so the UI keeps drawing; all
/// sorting, bucketing and (de)serialising runs in a background isolate.
class LibraryIndexService {
  const LibraryIndexService();

  static const chunk = 500;
  static const _fileName = 'library_index_v1.txt';

  static FilterOptionGroup _filter(OrderOptionType order) => FilterOptionGroup(
        imageOption: const FilterOption(
          needTitle: false,
          sizeConstraint: SizeConstraint(ignoreSize: true),
        ),
        orders: [OrderOption(type: order, asc: false)],
      );

  Future<String> _path() async =>
      '${(await getApplicationSupportDirectory()).path}/$_fileName';

  /// The cached index, or null when there is none (or it is unreadable).
  Future<LibraryIndex?> loadCache() async {
    try {
      final path = await _path();
      return await Isolate.run(() {
        final f = File(path);
        if (!f.existsSync()) return null;
        return LibraryIndex.decode(f.readAsStringSync());
      });
    } catch (_) {
      return null;
    }
  }

  Future<void> _save(LibraryIndex index) async {
    try {
      final path = await _path();
      await Isolate.run(() {
        final tmp = File('$path.tmp')..writeAsStringSync(index.encode(), flush: true);
        tmp.renameSync(path);
      });
    } catch (_) {
      // A missing cache only costs a rebuild next time.
    }
  }

  Future<void> clearCache() async {
    try {
      final f = File(await _path());
      if (await f.exists()) await f.delete();
    } catch (_) {}
  }

  /// Library size and newest modified date — two cheap platform calls used
  /// to decide whether the cache is still current.
  Future<({int count, int maxModified})> fingerprint() async {
    final filter = _filter(OrderOptionType.updateDate);
    final count = await PhotoManager.getAssetCount(type: RequestType.image, filterOption: filter);
    if (count == 0) return (count: 0, maxModified: 0);
    final newest = await PhotoManager.getAssetListRange(
      start: 0,
      end: 1,
      type: RequestType.image,
      filterOption: filter,
    );
    return (
      count: count,
      maxModified: newest.isEmpty ? 0 : (newest.first.modifiedDateSecond ?? 0),
    );
  }

  // Isolate entry points are static so their closures capture only their
  // (sendable) arguments — never a progress callback or a Riverpod ref.
  static Future<LibraryIndex> _sortInIsolate(
          Map<String, int> entries, int count, int maxMod, bool limited) =>
      Isolate.run(() => LibraryIndex.fromEntries(entries,
          count: count, maxModified: maxMod, limited: limited));

  static Future<LibraryIndex> _mergeInIsolate(LibraryIndex old,
          Map<String, int> changed, int count, int maxMod, bool limited) =>
      Isolate.run(() => LibraryIndex.fromEntries(old.toEntries()..addAll(changed),
          count: count, maxModified: maxMod, limited: limited));

  /// Capture time with fallbacks: create date → modified date → 0 (undated).
  static int _timeOf(AssetEntity a) {
    final c = a.createDateSecond ?? 0;
    if (c > 0) return c;
    final m = a.modifiedDateSecond ?? 0;
    return m > 0 ? m : 0;
  }

  /// Full rebuild: pages through every image. O(n) platform work, reported
  /// through [onProgress] after each chunk.
  Future<LibraryIndex> build({
    required bool limited,
    void Function(int done, int total)? onProgress,
  }) async {
    final filter = _filter(OrderOptionType.createDate);
    final total = await PhotoManager.getAssetCount(type: RequestType.image, filterOption: filter);
    final entries = <String, int>{};
    var maxMod = 0;
    onProgress?.call(0, total);
    for (var start = 0; start < total; start += chunk) {
      final end = math.min(start + chunk, total);
      final page = await PhotoManager.getAssetListRange(
        start: start,
        end: end,
        type: RequestType.image,
        filterOption: filter,
      );
      for (final a in page) {
        entries[a.id] = _timeOf(a);
        final m = a.modifiedDateSecond ?? 0;
        if (m > maxMod) maxMod = m;
      }
      onProgress?.call(end, total);
      // Yield a frame between chunks so scrolling and animations stay smooth.
      await Future<void>.delayed(const Duration(milliseconds: 1));
      if (page.isEmpty) break;
    }
    final index = await _sortInIsolate(entries, total, maxMod, limited);
    await _save(index);
    return index;
  }

  /// Incremental refresh: reads only assets modified since [old] was built
  /// (newest-modified first) and merges them in. Returns null when the result
  /// cannot be trusted — e.g. photos were deleted — so the caller rebuilds.
  Future<LibraryIndex?> update(
    LibraryIndex old, {
    required int count,
    required bool limited,
    void Function(int done, int total)? onProgress,
  }) async {
    if (old.maxModified <= 0 || old.limited != limited) return null;
    final filter = _filter(OrderOptionType.updateDate);
    final changed = <String, int>{};
    var maxMod = old.maxModified;
    var reachedOld = false;
    for (var start = 0; start < count && !reachedOld; start += chunk) {
      final page = await PhotoManager.getAssetListRange(
        start: start,
        end: math.min(start + chunk, count),
        type: RequestType.image,
        filterOption: filter,
      );
      if (page.isEmpty) break;
      for (final a in page) {
        final m = a.modifiedDateSecond ?? 0;
        // Strictly older than the last build: everything after is known.
        if (m < old.maxModified) {
          reachedOld = true;
          break;
        }
        changed[a.id] = _timeOf(a);
        if (m > maxMod) maxMod = m;
      }
      onProgress?.call(math.min(start + chunk, count), count);
      await Future<void>.delayed(const Duration(milliseconds: 1));
      // More than half the library changed: a clean rebuild is cheaper.
      if (changed.length > count ~/ 2 && count > chunk) return null;
    }
    final merged = await _mergeInIsolate(old, changed, count, maxMod, limited);
    // Deleted photos are still in the merge — fall back to a full rebuild.
    if (merged.total != count) return null;
    await _save(merged);
    return merged;
  }
}
