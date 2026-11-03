import 'dart:ui' show Locale, PlatformDispatcher;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/app_localizations.dart';
import '../services/reminder_service.dart';
import 'library_index.dart';
import 'occasions.dart';
import 'providers.dart';
import 'settings.dart';

final reminderServiceProvider = Provider((_) => ReminderService());

/// Upcoming days (next [days]) with at least [minPhotos] photos from the same
/// date in earlier years that aren't in a collage yet and weren't hidden in
/// Discover. Read from the on-device photo index; nothing leaves the phone.
final upcomingMemoriesProvider = Provider<List<MemoryDate>>((ref) {
  const days = 30;
  const minPhotos = 6;
  final index = ref.watch(libraryIndexDataProvider);
  if (index == null || index.dayKeys.isEmpty) return const [];
  final used = ref.watch(usedPerDayProvider);
  final dismissed = ref.watch(dismissedDaysProvider);
  final now = DateTime.now();
  final out = <MemoryDate>[];
  for (var i = 0; i < days; i++) {
    final d = DateTime(now.year, now.month, now.day + i);
    var photos = 0;
    int? nearest;
    for (var y = d.year - 1; y >= d.year - 30; y--) {
      final key = y * 10000 + d.month * 100 + d.day;
      if (used.containsKey(key) || dismissed.contains(key)) continue;
      final n = index.dayCount(key);
      if (n == 0) continue;
      photos += n;
      nearest ??= d.year - y;
    }
    if (photos >= minPhotos && nearest != null) {
      out.add(MemoryDate(date: d, yearsAgo: nearest, photos: photos));
    }
  }
  return out;
});

/// Keeps scheduled reminders in step with the settings, birthdays, region and
/// library. Watched once at the app root. While reminders are off it does
/// nothing at all — no plugin set-up, no permission check.
final reminderSyncProvider = Provider<void>((ref) {
  final p = ref.watch(occasionPrefsProvider);
  if (!p.remindersOn || (!p.remindOccasions && !p.remindBirthdays && !p.remindMemories)) {
    if (p.remindersOn) ref.read(reminderServiceProvider).cancelAll();
    return;
  }
  final region = ref.watch(occasionRegionProvider);
  final birthdays = ref.watch(birthdaysProvider);
  final collages = ref.watch(draftsProvider).valueOrNull;
  if (collages == null) return; // library still loading; runs again when ready
  final code = ref.watch(settingsProvider).locale?.languageCode ??
      PlatformDispatcher.instance.locale.languageCode;

  final now = DateTime.now();
  final upcoming = ref
      .read(occasionServiceProvider)
      .occurrences(
        from: now,
        to: now.add(const Duration(days: 60)),
        region: region,
        birthdays: p.remindBirthdays ? birthdays : const [],
      )
      .where((o) =>
          !o.optional && // "also celebrated" occasions stay in-app only
          (o.birthday != null || p.remindOccasions) &&
          !madeForOccasion(collages, o))
      .toList();

  final memories = p.remindMemories ? ref.watch(upcomingMemoriesProvider) : const <MemoryDate>[];

  final plan = ReminderPlanner.plan(
    now: now,
    upcoming: upcoming,
    memories: memories,
    frequency: p.frequency,
    quietStart: p.quietStart,
    quietEnd: p.quietEnd,
  );
  ref.read(reminderServiceProvider).schedule(plan, AppLocalizations(Locale(code)));
});
