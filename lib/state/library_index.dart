import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/library_index_service.dart';
import '../services/permission_service.dart';
import 'providers.dart';

final libraryIndexServiceProvider = Provider((_) => const LibraryIndexService());

/// Where the library index stands: the access level, the (possibly stale)
/// index being shown, and progress of a running (re)build.
class LibraryIndexState {
  const LibraryIndexState({
    this.access,
    this.index,
    this.indexing = false,
    this.done = 0,
    this.total = 0,
    this.error,
  });

  /// Null until the first permission check finished.
  final GalleryAccess? access;

  /// The index to show — may be a stale cache while [indexing] refreshes it.
  final LibraryIndex? index;
  final bool indexing;
  final int done;
  final int total;
  final Object? error;

  double? get progress => total <= 0 ? null : (done / total).clamp(0.0, 1.0);

  LibraryIndexState copy({
    GalleryAccess? access,
    LibraryIndex? index,
    bool clearIndex = false,
    bool? indexing,
    int? done,
    int? total,
    Object? error,
  }) =>
      LibraryIndexState(
        access: access ?? this.access,
        index: clearIndex ? null : (index ?? this.index),
        indexing: indexing ?? this.indexing,
        done: done ?? this.done,
        total: total ?? this.total,
        error: error,
      );
}

/// Keeps the [LibraryIndex] current. Stale-while-revalidate: a cached index is
/// shown at once, then checked against the library (two cheap calls) and, if
/// it changed, refreshed incrementally or rebuilt in the background.
class LibraryIndexNotifier extends Notifier<LibraryIndexState> {
  bool _running = false;
  DateTime? _checkedAt;

  /// Don't re-check the library more often than this on tab switches.
  static const _recheckAfter = Duration(seconds: 30);

  @override
  LibraryIndexState build() => const LibraryIndexState();

  /// Load the cache (if not yet loaded) and refresh it when the library
  /// changed. Cheap to call often: throttled and never runs twice at once.
  Future<void> ensureFresh({bool force = false}) async {
    if (_running) return;
    final now = DateTime.now();
    if (!force &&
        state.index != null &&
        _checkedAt != null &&
        now.difference(_checkedAt!) < _recheckAfter) {
      return;
    }
    _running = true;
    final svc = ref.read(libraryIndexServiceProvider);
    try {
      final access = await ref.read(permissionServiceProvider).current();
      if (!access.usable) {
        state = LibraryIndexState(access: access);
        return;
      }
      final limited = access == GalleryAccess.limited;
      var index = state.index ?? await svc.loadCache();
      // Going from full to limited access: the old index lists photos the app
      // can no longer read, so don't show it.
      if (index != null && limited && !index.limited) index = null;
      state = state.copy(access: access, index: index, clearIndex: index == null);

      final fp = await svc.fingerprint();
      if (index != null &&
          index.count == fp.count &&
          index.maxModified == fp.maxModified &&
          index.limited == limited) {
        _checkedAt = DateTime.now();
        return;
      }
      if (fp.count == 0) {
        state = state.copy(index: LibraryIndex.empty, indexing: false);
        await svc.clearCache();
        _checkedAt = DateTime.now();
        return;
      }

      state = state.copy(indexing: true, done: 0, total: fp.count);
      void progress(int done, int total) =>
          state = state.copy(indexing: true, done: done, total: total);
      LibraryIndex? next;
      if (index != null) {
        next = await svc.update(index, count: fp.count, limited: limited, onProgress: progress);
      }
      next ??= await svc.build(limited: limited, onProgress: progress);
      state = state.copy(index: next, indexing: false, done: 0, total: 0);
      _checkedAt = DateTime.now();
    } catch (e) {
      state = state.copy(indexing: false, error: e);
    } finally {
      _running = false;
    }
  }
}

final libraryIndexProvider =
    NotifierProvider<LibraryIndexNotifier, LibraryIndexState>(LibraryIndexNotifier.new);

/// The current index, or null while none is available.
final libraryIndexDataProvider =
    Provider<LibraryIndex?>((ref) => ref.watch(libraryIndexProvider.select((s) => s.index)));

/// Photos already in collages, counted per capture day (`yyyymmdd` key).
/// O(used photos), not O(library).
final usedPerDayProvider = Provider<Map<int, int>>((ref) {
  final index = ref.watch(libraryIndexDataProvider);
  final usage = ref.watch(photoUsageProvider);
  if (index == null) return const {};
  final out = <int, int>{};
  for (final id in usage.usedAssets) {
    final day = index.dayOf(id);
    if (day != null) out[day] = (out[day] ?? 0) + 1;
  }
  return out;
});

/// Discover suggestions the user hid (persisted).
class DismissedDaysNotifier extends Notifier<Set<int>> {
  @override
  Set<int> build() => ref.read(prefsProvider).discoverDismissedDays;

  Future<void> dismiss(int day) => _set({...state, day});
  Future<void> restore(int day) => _set({...state}..remove(day));

  Future<void> _set(Set<int> days) async {
    state = days;
    await ref.read(prefsProvider).setDiscoverDismissedDays(days);
  }
}

final dismissedDaysProvider =
    NotifierProvider<DismissedDaysNotifier, Set<int>>(DismissedDaysNotifier.new);

/// A day worth turning into a collage: enough photos, none used yet.
class DaySuggestion {
  const DaySuggestion({required this.day, required this.count, required this.onThisDay});
  final int day;
  final int count;

  /// Same calendar day as today, in an earlier year.
  final bool onThisDay;
}

/// A short list of unused days: "on this day" from earlier years first, then
/// the most recent days. O(days with photos), never O(photos).
final discoverSuggestionsProvider = Provider<List<DaySuggestion>>((ref) {
  const maxSuggestions = 4;
  const maxOnThisDay = 2;
  const minPhotos = 4;
  final index = ref.watch(libraryIndexDataProvider);
  if (index == null || index.dayKeys.isEmpty) return const [];
  final used = ref.watch(usedPerDayProvider);
  final dismissed = ref.watch(dismissedDaysProvider);
  final today = DateTime.now();

  bool fits(int day) =>
      index.dayCount(day) >= minPhotos && !used.containsKey(day) && !dismissed.contains(day);

  final out = <DaySuggestion>[];
  for (var y = today.year - 1; y >= today.year - 30 && out.length < maxOnThisDay; y--) {
    final key = y * 10000 + today.month * 100 + today.day;
    if (fits(key)) out.add(DaySuggestion(day: key, count: index.dayCount(key), onThisDay: true));
  }
  final picked = {for (final s in out) s.day};
  for (var i = index.dayKeys.length - 1; i >= 0 && out.length < maxSuggestions; i--) {
    final key = index.dayKeys[i];
    if (picked.contains(key) || !fits(key)) continue;
    out.add(DaySuggestion(day: key, count: index.dayCount(key), onThisDay: false));
  }
  return out;
});
