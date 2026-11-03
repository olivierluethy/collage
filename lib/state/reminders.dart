import 'dart:ui' show Locale, PlatformDispatcher;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/app_localizations.dart';
import '../services/reminder_service.dart';
import 'occasions.dart';
import 'providers.dart';
import 'settings.dart';

final reminderServiceProvider = Provider((_) => ReminderService());

/// Keeps scheduled reminders in step with the settings, birthdays, region and
/// library. Watched once at the app root. While reminders are off it does
/// nothing at all — no plugin set-up, no permission check.
final reminderSyncProvider = Provider<void>((ref) {
  final p = ref.watch(occasionPrefsProvider);
  if (!p.remindersOn || (!p.remindOccasions && !p.remindBirthdays)) {
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

  final plan = ReminderPlanner.plan(
    now: now,
    upcoming: upcoming,
    frequency: p.frequency,
    quietStart: p.quietStart,
    quietEnd: p.quietEnd,
  );
  ref.read(reminderServiceProvider).schedule(plan, AppLocalizations(Locale(code)));
});
