import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../models/collage_project.dart';
import '../services/occasion_service.dart';
import '../services/prefs_service.dart';
import 'providers.dart';

/// How often reminders may arrive at most.
enum ReminderFrequency {
  weekly1(7, 1),
  weekly2(7, 2),
  monthly1(30, 1);

  const ReminderFrequency(this.windowDays, this.max);

  /// At most [max] reminders in any [windowDays]-day span.
  final int windowDays;
  final int max;

  static ReminderFrequency parse(String? s) =>
      ReminderFrequency.values.firstWhere((f) => f.name == s, orElse: () => weekly1);
}

/// Templates / occasions / reminders preferences. Every default is the
/// quiet one: suggestions are in-app only, reminders and contacts are off.
@immutable
class OccasionPrefs {
  const OccasionPrefs({
    this.suggestions = true,
    this.region,
    this.contactsConnected = false,
    this.remindersOn = false,
    this.remindOccasions = true,
    this.remindBirthdays = true,
    this.frequency = ReminderFrequency.weekly1,
    this.quietStart = 21 * 60,
    this.quietEnd = 9 * 60,
  });

  /// Show the occasion card in the Templates tab and New collage sheet.
  final bool suggestions;

  /// Chosen region (ISO country code); null = follow the device.
  final String? region;

  /// Birthdays were imported from the address book.
  final bool contactsConnected;

  /// Master switch for local notifications (off by default).
  final bool remindersOn;
  final bool remindOccasions;
  final bool remindBirthdays;
  final ReminderFrequency frequency;

  /// Quiet hours as minutes after midnight, local time ([quietStart] may be
  /// later than [quietEnd]: the span then crosses midnight).
  final int quietStart;
  final int quietEnd;

  OccasionPrefs copyWith({
    bool? suggestions,
    String? region,
    bool clearRegion = false,
    bool? contactsConnected,
    bool? remindersOn,
    bool? remindOccasions,
    bool? remindBirthdays,
    ReminderFrequency? frequency,
    int? quietStart,
    int? quietEnd,
  }) =>
      OccasionPrefs(
        suggestions: suggestions ?? this.suggestions,
        region: clearRegion ? null : (region ?? this.region),
        contactsConnected: contactsConnected ?? this.contactsConnected,
        remindersOn: remindersOn ?? this.remindersOn,
        remindOccasions: remindOccasions ?? this.remindOccasions,
        remindBirthdays: remindBirthdays ?? this.remindBirthdays,
        frequency: frequency ?? this.frequency,
        quietStart: quietStart ?? this.quietStart,
        quietEnd: quietEnd ?? this.quietEnd,
      );
}

class OccasionPrefsNotifier extends Notifier<OccasionPrefs> {
  PrefsService get _p => ref.read(prefsProvider);

  @override
  OccasionPrefs build() {
    final p = _p;
    const d = OccasionPrefs();
    return OccasionPrefs(
      suggestions: p.getBool(PrefsService.kOccasionSuggestions) ?? d.suggestions,
      region: p.getString(PrefsService.kOccasionRegion),
      contactsConnected: p.getBool(PrefsService.kContactsConnected) ?? false,
      remindersOn: p.getBool(PrefsService.kRemindersOn) ?? false,
      remindOccasions: p.getBool(PrefsService.kRemindOccasions) ?? d.remindOccasions,
      remindBirthdays: p.getBool(PrefsService.kRemindBirthdays) ?? d.remindBirthdays,
      frequency: ReminderFrequency.parse(p.getString(PrefsService.kReminderFrequency)),
      quietStart: p.getInt(PrefsService.kQuietStart) ?? d.quietStart,
      quietEnd: p.getInt(PrefsService.kQuietEnd) ?? d.quietEnd,
    );
  }

  void setSuggestions(bool v) {
    _p.setBool(PrefsService.kOccasionSuggestions, v);
    state = state.copyWith(suggestions: v);
  }

  /// [code] == null follows the device region.
  void setRegion(String? code) {
    _p.setStringOrRemove(PrefsService.kOccasionRegion, code);
    state = code == null ? state.copyWith(clearRegion: true) : state.copyWith(region: code);
  }

  void setContactsConnected(bool v) {
    _p.setBool(PrefsService.kContactsConnected, v);
    state = state.copyWith(contactsConnected: v);
  }

  void setRemindersOn(bool v) {
    _p.setBool(PrefsService.kRemindersOn, v);
    state = state.copyWith(remindersOn: v);
  }

  void setRemindOccasions(bool v) {
    _p.setBool(PrefsService.kRemindOccasions, v);
    state = state.copyWith(remindOccasions: v);
  }

  void setRemindBirthdays(bool v) {
    _p.setBool(PrefsService.kRemindBirthdays, v);
    state = state.copyWith(remindBirthdays: v);
  }

  void setFrequency(ReminderFrequency f) {
    _p.setStringOrRemove(PrefsService.kReminderFrequency, f.name);
    state = state.copyWith(frequency: f);
  }

  void setQuietHours({int? start, int? end}) {
    if (start != null) _p.setInt(PrefsService.kQuietStart, start);
    if (end != null) _p.setInt(PrefsService.kQuietEnd, end);
    state = state.copyWith(quietStart: start, quietEnd: end);
  }
}

final occasionPrefsProvider =
    NotifierProvider<OccasionPrefsNotifier, OccasionPrefs>(OccasionPrefsNotifier.new);

/// The device's region (country code of its locale), or '' when unknown.
String deviceRegion() =>
    OccasionService.normalizeRegion(PlatformDispatcher.instance.locale.countryCode);

/// The region occasions are computed for: the user's choice, else the device.
final occasionRegionProvider = Provider<String>((ref) {
  final chosen = ref.watch(occasionPrefsProvider.select((p) => p.region));
  return OccasionService.normalizeRegion(chosen ?? deviceRegion());
});

final occasionServiceProvider = Provider((_) => const OccasionService());

/// "Now", injectable for previews.
final clockProvider = Provider<DateTime Function()>((_) => DateTime.now);

// --- favourites ---------------------------------------------------------------

/// Ids of starred catalog templates, most recently starred last.
class FavouriteTemplatesNotifier extends Notifier<List<String>> {
  @override
  List<String> build() =>
      ref.read(prefsProvider).getStringList(PrefsService.kTemplateFavourites) ?? const [];

  bool isFavourite(String id) => state.contains(id);

  /// Stars or un-stars [id]; returns true when it is now a favourite.
  bool toggle(String id) {
    final next = [...state];
    final added = !next.remove(id);
    if (added) next.add(id);
    state = next;
    ref.read(prefsProvider).setStringList(PrefsService.kTemplateFavourites, next);
    return added;
  }
}

final favouriteTemplatesProvider =
    NotifierProvider<FavouriteTemplatesNotifier, List<String>>(FavouriteTemplatesNotifier.new);

// --- birthdays ----------------------------------------------------------------

/// Birthdays kept on this device only: typed in by the user, or imported from
/// contacts (name + day only) after an explicit opt-in.
class BirthdaysNotifier extends Notifier<List<Birthday>> {
  @override
  List<Birthday> build() {
    final raw = ref.read(prefsProvider).getString(PrefsService.kBirthdays);
    if (raw == null || raw.isEmpty) return const [];
    try {
      final list = jsonDecode(raw) as List;
      return _sorted([
        for (final e in list)
          if (e is Map<String, dynamic>) ?Birthday.fromJson(e),
      ]);
    } catch (_) {
      return const [];
    }
  }

  void _save(List<Birthday> list) {
    state = _sorted(list);
    ref.read(prefsProvider).setStringOrRemove(
          PrefsService.kBirthdays,
          list.isEmpty ? null : jsonEncode([for (final b in list) b.toJson()]),
        );
  }

  static List<Birthday> _sorted(List<Birthday> l) => [...l]
    ..sort((a, b) {
      final c = (a.month * 32 + a.day).compareTo(b.month * 32 + b.day);
      return c != 0 ? c : a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });

  void add({required String name, required int month, required int day, int? year}) =>
      _save([
        ...state,
        Birthday(id: const Uuid().v4(), name: name, month: month, day: day, year: year),
      ]);

  void update(Birthday b) => _save([for (final x in state) x.id == b.id ? b : x]);

  void remove(String id) => _save([for (final x in state) if (x.id != id) x]);

  /// Replaces previously imported entries with [imported]; manual entries stay.
  /// Returns how many were imported.
  int replaceImported(List<Birthday> imported) {
    _save([
      for (final x in state) if (!x.fromContacts) x,
      ...imported,
    ]);
    return imported.length;
  }

  /// Deletes every entry that came from contacts.
  void removeImported() => _save([for (final x in state) if (!x.fromContacts) x]);
}

final birthdaysProvider =
    NotifierProvider<BirthdaysNotifier, List<Birthday>>(BirthdaysNotifier.new);

// --- suggestions --------------------------------------------------------------

/// Occurrences the user closed. Old keys are pruned on load.
class DismissedOccasionsNotifier extends Notifier<Set<String>> {
  @override
  Set<String> build() {
    final list = ref.read(prefsProvider).getStringList(PrefsService.kOccasionDismissed) ?? [];
    final cutoff = DateTime.now().subtract(const Duration(days: 60));
    final keep = <String>{
      for (final k in list)
        if (_dateOf(k)?.isAfter(cutoff) ?? false) k,
    };
    if (keep.length != list.length) {
      ref.read(prefsProvider).setStringList(PrefsService.kOccasionDismissed, keep.toList());
    }
    return keep;
  }

  static DateTime? _dateOf(String key) {
    final at = key.lastIndexOf('@');
    return at < 0 ? null : DateTime.tryParse(key.substring(at + 1));
  }

  void dismiss(String key) {
    state = {...state, key};
    ref.read(prefsProvider).setStringList(PrefsService.kOccasionDismissed, state.toList());
  }
}

final dismissedOccasionsProvider =
    NotifierProvider<DismissedOccasionsNotifier, Set<String>>(DismissedOccasionsNotifier.new);

/// What the occasion card shows.
@immutable
class OccasionSuggestion {
  const OccasionSuggestion({required this.date, required this.madeAlready});

  final OccasionDate date;

  /// The user already started a collage for this occasion this season, so the
  /// card offers "another one" instead of a first one.
  final bool madeAlready;

  Occasion get occasion => date.occasion;
}

/// True when [collages] hold one made for [o] in the run-up to (or on) it.
bool madeForOccasion(List<CollageProject> collages, OccasionDate o) {
  final from = DateTime(o.date.year, o.date.month, o.date.day - 45);
  final to = DateTime(o.date.year, o.date.month, o.date.day + o.occasion.daysAfter + 1);
  for (final c in collages) {
    if (c.occasionId != o.id) continue;
    final at = DateTime.fromMillisecondsSinceEpoch(c.createdAt);
    if (!at.isBefore(from) && at.isBefore(to)) return true;
  }
  return false;
}

/// Every occurrence in its suggestion window right now (birthdays included),
/// best first, regardless of dismissals or the suggestions switch.
final activeOccasionsProvider = Provider<List<OccasionDate>>((ref) {
  final region = ref.watch(occasionRegionProvider);
  final birthdays = ref.watch(birthdaysProvider);
  final now = ref.watch(clockProvider)();
  return ref.watch(occasionServiceProvider).active(now, region, birthdays: birthdays);
});

/// The single occasion card to show, or null. Respects the Settings switch and
/// the user's dismissals; never more than one card at a time.
final occasionSuggestionProvider = Provider<OccasionSuggestion?>((ref) {
  if (!ref.watch(occasionPrefsProvider.select((p) => p.suggestions))) return null;
  final dismissed = ref.watch(dismissedOccasionsProvider);
  final collages = ref.watch(draftsProvider).valueOrNull ?? const <CollageProject>[];
  for (final o in ref.watch(activeOccasionsProvider)) {
    if (dismissed.contains(o.key)) continue;
    return OccasionSuggestion(date: o, madeAlready: madeForOccasion(collages, o));
  }
  return null;
});
