import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../l10n/app_localizations.dart';
import '../state/occasions.dart' show ReminderFrequency;
import 'occasion_copy.dart';
import 'occasion_service.dart';

/// A day with photos from the same date in earlier years ("photo memory").
@immutable
class MemoryDate {
  const MemoryDate({required this.date, required this.yearsAgo, required this.photos});

  /// The upcoming local calendar day the memory falls on.
  final DateTime date;

  /// How many years ago the most recent of those photos were taken.
  final int yearsAgo;
  final int photos;
}

/// One local notification to schedule: an occasion/birthday or a memory.
@immutable
class PlannedReminder {
  const PlannedReminder({required this.id, required this.fireAt, this.occasion, this.memory})
      : assert(occasion != null || memory != null);

  final int id;

  /// Local wall-clock time.
  final DateTime fireAt;
  final OccasionDate? occasion;
  final MemoryDate? memory;

  DateTime get day => occasion?.date ?? memory!.date;
}

/// Decides when reminders fire. Pure, so the rules are easy to reason about:
///
/// * occasions are announced 3 days ahead, birthdays 2 days ahead (or as soon
///   as possible when that has passed, never after the day itself);
/// * the preferred time is 10:00; inside quiet hours it moves to their end;
/// * at most [ReminderFrequency.max] reminders in any rolling window of
///   [ReminderFrequency.windowDays] days — nearer occasions win; all
///   categories (occasions, birthdays, memories) share that limit;
/// * photo memories are announced on the day itself, never ahead.
class ReminderPlanner {
  ReminderPlanner._();

  static const preferredMinutes = 10 * 60;
  static const maxScheduled = 8;

  static List<PlannedReminder> plan({
    required DateTime now,
    required List<OccasionDate> upcoming,
    List<MemoryDate> memories = const [],
    required ReminderFrequency frequency,
    required int quietStart,
    required int quietEnd,
  }) {
    final today = DateTime(now.year, now.month, now.day);
    final candidates = <PlannedReminder>[];
    DateTime? fireFor(DateTime date, int lead) {
      var day = DateTime(date.year, date.month, date.day - lead);
      if (day.isBefore(today)) day = today;
      var at = _at(day, _allowedMinute(preferredMinutes, quietStart, quietEnd));
      if (!at.isAfter(now.add(const Duration(minutes: 15)))) {
        day = DateTime(day.year, day.month, day.day + 1);
        at = _at(day, _allowedMinute(preferredMinutes, quietStart, quietEnd));
      }
      if (daysBetween(day, date) < 0) return null; // would arrive after the day
      return at;
    }

    for (final o in upcoming) {
      final at = fireFor(o.date, o.birthday != null ? 2 : 3);
      if (at != null) candidates.add(PlannedReminder(id: 0, fireAt: at, occasion: o));
    }
    for (final m in memories) {
      final at = fireFor(m.date, 0);
      if (at != null) candidates.add(PlannedReminder(id: 0, fireAt: at, memory: m));
    }
    candidates.sort((a, b) => a.fireAt.compareTo(b.fireAt));

    final kept = <PlannedReminder>[];
    for (final c in candidates) {
      final windowStart = c.fireAt.subtract(Duration(days: frequency.windowDays));
      final inWindow = kept.where((k) => k.fireAt.isAfter(windowStart)).length;
      if (inWindow >= frequency.max) continue;
      kept.add(PlannedReminder(id: 7100 + kept.length, fireAt: c.fireAt, occasion: c.occasion, memory: c.memory));
      if (kept.length >= maxScheduled) break;
    }
    return kept;
  }

  static DateTime _at(DateTime day, int minute) =>
      DateTime(day.year, day.month, day.day, minute ~/ 60, minute % 60);

  /// [minute] if it is outside quiet hours, else the end of quiet hours.
  static int _allowedMinute(int minute, int quietStart, int quietEnd) =>
      inQuietHours(minute, quietStart, quietEnd) ? quietEnd : minute;

  /// True when [minute] (after midnight) falls in quiet hours. Equal start and
  /// end mean no quiet hours.
  static bool inQuietHours(int minute, int start, int end) {
    if (start == end) return false;
    return start < end ? (minute >= start && minute < end) : (minute >= start || minute < end);
  }
}

/// Local notifications for occasion and birthday reminders. Nothing here runs
/// until the user turns Reminders on: the plugin is initialised lazily, the
/// OS permission is only requested from the Reminders screen, and turning
/// reminders off cancels everything that was scheduled.
class ReminderService {
  ReminderService();

  final _plugin = FlutterLocalNotificationsPlugin();
  bool _ready = false;
  Future<void> _queue = Future.value();

  static const _channelId = 'occasion_reminders';
  static const _exportChannelId = 'export_done';
  static const exportNotificationId = 7000;

  Future<void> _init() async {
    if (_ready) return;
    tzdata.initializeTimeZones();
    try {
      final info = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(info.identifier));
    } catch (_) {
      // Unknown zone: tz.local stays UTC; times may be off by the UTC offset.
    }
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('ic_stat_collage'),
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
      ),
    );
    _ready = true;
  }

  /// Asks the OS for permission to post notifications. True when granted.
  Future<bool> requestPermission() async {
    try {
      await _init();
      final android = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      if (android != null) return await android.requestNotificationsPermission() ?? false;
      final ios = _plugin.resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin>();
      if (ios != null) {
        return await ios.requestPermissions(alert: true, sound: true, badge: false) ?? false;
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  /// Whether notifications may currently be shown (without prompting).
  Future<bool> hasPermission() async {
    try {
      await _init();
      final android = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      if (android != null) return await android.areNotificationsEnabled() ?? false;
      final ios = _plugin.resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin>();
      if (ios != null) return (await ios.checkPermissions())?.isEnabled ?? false;
      return false;
    } catch (_) {
      return false;
    }
  }

  /// Cancels every scheduled reminder.
  Future<void> cancelAll() => _serial(() async {
        await _init();
        await _plugin.cancelAll();
      });

  /// Replaces the scheduled reminders with [plan]. Does nothing (and never
  /// prompts) when the OS permission is missing.
  Future<void> schedule(List<PlannedReminder> plan, AppLocalizations l) => _serial(() async {
        if (!await hasPermission()) return;
        await _plugin.cancelAll();
        final details = NotificationDetails(
          android: AndroidNotificationDetails(
            _channelId,
            l.t('remChannelName'),
            channelDescription: l.t('remChannelDescription'),
            importance: Importance.defaultImportance,
            priority: Priority.defaultPriority,
          ),
          iOS: const DarwinNotificationDetails(),
        );
        for (final r in plan) {
          final when = tz.TZDateTime(
            tz.local,
            r.fireAt.year,
            r.fireAt.month,
            r.fireAt.day,
            r.fireAt.hour,
            r.fireAt.minute,
          );
          final fireDay = DateTime(r.fireAt.year, r.fireAt.month, r.fireAt.day);
          final o = r.occasion;
          final m = r.memory;
          await _plugin.zonedSchedule(
            id: r.id,
            scheduledDate: when,
            notificationDetails: details,
            androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
            title: o != null
                ? occasionHeadline(l, o, fireDay)
                : (m!.yearsAgo == 1
                    ? l.t('remMemoryTitleOne')
                    : l.a('remMemoryTitle', {'years': '${m.yearsAgo}'})),
            body: o != null ? l.t('remBody') : l.t('remMemoryBody'),
            payload: o?.id ?? 'memory',
          );
        }
      });

  /// Says right away that an export finished and where it was saved. Only
  /// used when the user turned this on; never prompts for permission.
  Future<void> showExportDone(AppLocalizations l, {required String fileName, required String place}) =>
      _serial(() async {
        if (!await hasPermission()) return;
        await _plugin.show(
          id: exportNotificationId,
          title: l.t('expNotifTitle'),
          body: l.a('expNotifBody', {'file': fileName, 'place': place}),
          notificationDetails: NotificationDetails(
            android: AndroidNotificationDetails(
              _exportChannelId,
              l.t('expNotifChannel'),
              channelDescription: l.t('expNotifChannelHint'),
              importance: Importance.low,
              priority: Priority.low,
            ),
            iOS: const DarwinNotificationDetails(presentSound: false),
          ),
          payload: 'export',
        );
      });

  /// Runs [job] after any previous one, so rapid setting changes never
  /// interleave cancel and schedule calls.
  Future<void> _serial(Future<void> Function() job) {
    final next = _queue.then((_) => job()).catchError((Object _) {});
    _queue = next;
    return next;
  }
}
