import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:collage/features/info/reminders_screen.dart';
import 'package:collage/l10n/app_localizations.dart';
import 'package:collage/models/collage_project.dart';
import 'package:collage/services/occasion_service.dart';
import 'package:collage/services/prefs_service.dart';
import 'package:collage/services/reminder_service.dart';
import 'package:collage/state/occasions.dart';
import 'package:collage/state/providers.dart';
import 'package:collage/state/reminders.dart';
import 'package:collage/theme/app_theme.dart';

/// Records what the app asks of the notification layer; never touches the
/// plugin.
class _FakeReminders extends ReminderService {
  final calls = <String>[];
  final plans = <List<PlannedReminder>>[];
  bool grant = true;

  @override
  Future<void> cancelAll() async => calls.add('cancelAll');

  @override
  Future<void> schedule(List<PlannedReminder> plan, AppLocalizations l) async {
    calls.add('schedule');
    plans.add(plan);
  }

  @override
  Future<bool> hasPermission() async {
    calls.add('hasPermission');
    return grant;
  }

  @override
  Future<bool> requestPermission() async {
    calls.add('requestPermission');
    return grant;
  }

  @override
  Future<String?> launchPayload() async => null;
}

class _NoDrafts extends DraftsNotifier {
  @override
  Future<List<CollageProject>> build() async => const [];
}

Future<PrefsService> _prefs([Map<String, Object> values = const {}]) async {
  SharedPreferences.setMockInitialValues(values);
  return PrefsService.create();
}

ProviderContainer _container(PrefsService prefs, _FakeReminders fake) {
  final c = ProviderContainer(overrides: [
    prefsProvider.overrideWithValue(prefs),
    reminderServiceProvider.overrideWithValue(fake),
    draftsProvider.overrideWith(_NoDrafts.new),
    occasionRegionProvider.overrideWithValue('US'),
  ]);
  addTearDown(c.dispose);
  return c;
}

Future<void> _settle() async {
  for (var i = 0; i < 5; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

String _birthdaysJson(List<Birthday> list) => jsonEncode([for (final b in list) b.toJson()]);

const _manual = Birthday(id: 'm', name: 'Manual', month: 3, day: 1);
const _imported1 = Birthday(id: 'c1', name: 'Contact One', month: 4, day: 2, fromContacts: true);
const _imported2 = Birthday(id: 'c2', name: 'Contact Two', month: 5, day: 3, fromContacts: true);

void main() {
  group('defaults are the quiet ones', () {
    test('OccasionPrefs()', () {
      const p = OccasionPrefs();
      expect(p.remindersOn, isFalse);
      expect(p.contactsConnected, isFalse);
      expect(p.remindMemories, isFalse);
      expect(p.notifyExports, isFalse);
      expect(p.region, isNull);
      expect(p.suggestions, isTrue); // in-app only
      expect(p.frequency, ReminderFrequency.weekly1);
      expect(p.quietStart, 21 * 60);
      expect(p.quietEnd, 9 * 60);
    });

    test('notifier on empty prefs equals the defaults', () async {
      final c = _container(await _prefs(), _FakeReminders());
      final p = c.read(occasionPrefsProvider);
      expect(p.remindersOn, isFalse);
      expect(p.contactsConnected, isFalse);
      expect(p.remindMemories, isFalse);
      expect(p.notifyExports, isFalse);
      expect(p.frequency, ReminderFrequency.weekly1);
      expect(c.read(birthdaysProvider), isEmpty);
    });

    test('ReminderFrequency.parse falls back to weekly1', () {
      expect(ReminderFrequency.parse(null), ReminderFrequency.weekly1);
      expect(ReminderFrequency.parse('bogus'), ReminderFrequency.weekly1);
      expect(ReminderFrequency.parse('monthly1'), ReminderFrequency.monthly1);
    });

    test('switches persist', () async {
      final prefs = await _prefs();
      final c = _container(prefs, _FakeReminders());
      c.read(occasionPrefsProvider.notifier)
        ..setRemindersOn(true)
        ..setContactsConnected(true)
        ..setFrequency(ReminderFrequency.monthly1);
      expect(prefs.getBool(PrefsService.kRemindersOn), isTrue);
      expect(prefs.getBool(PrefsService.kContactsConnected), isTrue);
      final again = _container(prefs, _FakeReminders()).read(occasionPrefsProvider);
      expect(again.remindersOn, isTrue);
      expect(again.contactsConnected, isTrue);
      expect(again.frequency, ReminderFrequency.monthly1);
    });
  });

  group('disconnecting contacts', () {
    test('removeImported keeps manual entries only, and persists', () async {
      final prefs = await _prefs({
        PrefsService.kBirthdays: _birthdaysJson([_imported1, _manual, _imported2]),
        PrefsService.kContactsConnected: true,
      });
      final c = _container(prefs, _FakeReminders());
      expect(c.read(birthdaysProvider).map((b) => b.id), ['m', 'c1', 'c2']);

      c.read(birthdaysProvider.notifier).removeImported();
      c.read(occasionPrefsProvider.notifier).setContactsConnected(false);

      expect(c.read(birthdaysProvider).map((b) => b.id), ['m']);
      final stored = jsonDecode(prefs.getString(PrefsService.kBirthdays)!) as List;
      expect(stored.map((e) => (e as Map)['id']), ['m']);
      expect(prefs.getBool(PrefsService.kContactsConnected), isFalse);
    });

    test('removeImported with only imported entries clears the key', () async {
      final prefs = await _prefs({
        PrefsService.kBirthdays: _birthdaysJson([_imported1, _imported2]),
      });
      final c = _container(prefs, _FakeReminders());
      c.read(birthdaysProvider.notifier).removeImported();
      expect(c.read(birthdaysProvider), isEmpty);
      expect(prefs.getString(PrefsService.kBirthdays), isNull);
    });

    test('replaceImported swaps imported entries, manual ones stay', () async {
      final prefs = await _prefs({
        PrefsService.kBirthdays: _birthdaysJson([_imported1, _manual]),
      });
      final c = _container(prefs, _FakeReminders());
      final n = c.read(birthdaysProvider.notifier).replaceImported([_imported2]);
      expect(n, 1);
      expect(c.read(birthdaysProvider).map((b) => b.id), ['m', 'c2']);
    });
  });

  group('reminderSyncProvider', () {
    test('reminders off (default): no plugin call at all', () async {
      final fake = _FakeReminders();
      final c = _container(
        await _prefs({PrefsService.kBirthdays: _birthdaysJson([_manual])}),
        fake,
      );
      c.listen(reminderSyncProvider, (_, _) {});
      await c.read(draftsProvider.future);
      await _settle();
      expect(fake.calls, isEmpty);
    });

    test('reminders on: schedules a plan', () async {
      final fake = _FakeReminders();
      final c = _container(await _prefs({PrefsService.kRemindersOn: true}), fake);
      c.listen(reminderSyncProvider, (_, _) {});
      await c.read(draftsProvider.future);
      await _settle();
      expect(fake.calls, contains('schedule'));
      expect(fake.calls, isNot(contains('cancelAll')));
    });

    test('turning reminders off afterwards never schedules again', () async {
      final fake = _FakeReminders();
      final c = _container(await _prefs({PrefsService.kRemindersOn: true}), fake);
      c.listen(reminderSyncProvider, (_, _) {});
      await c.read(draftsProvider.future);
      await _settle();
      final before = fake.calls.where((x) => x == 'schedule').length;
      expect(before, greaterThan(0));

      c.read(occasionPrefsProvider.notifier).setRemindersOn(false);
      await _settle();
      // A later change that would normally reschedule.
      c.read(occasionPrefsProvider.notifier).setFrequency(ReminderFrequency.weekly2);
      await _settle();
      expect(fake.calls.where((x) => x == 'schedule').length, before);
    });

    test('master on but every category off: cancels, never schedules', () async {
      final fake = _FakeReminders();
      final c = _container(
        await _prefs({
          PrefsService.kRemindersOn: true,
          PrefsService.kRemindOccasions: false,
          PrefsService.kRemindBirthdays: false,
          PrefsService.kRemindMemories: false,
        }),
        fake,
      );
      c.listen(reminderSyncProvider, (_, _) {});
      await c.read(draftsProvider.future);
      await _settle();
      expect(fake.calls, ['cancelAll']);
    });

    test('birthdays switch on (default): plan includes a birthday soon', () async {
      final soon = DateTime.now().add(const Duration(days: 3));
      final b = Birthday(id: 'soon', name: 'Soon', month: soon.month, day: soon.day);
      final fake = _FakeReminders();
      final c = _container(
        await _prefs({
          PrefsService.kRemindersOn: true,
          PrefsService.kRemindOccasions: false,
          PrefsService.kBirthdays: _birthdaysJson([b]),
        }),
        fake,
      );
      c.listen(reminderSyncProvider, (_, _) {});
      await c.read(draftsProvider.future);
      await _settle();
      expect(fake.plans.last.map((r) => r.occasion?.birthday?.id), ['soon']);
    });

    test('birthdays switch off: plan has no birthday reminders', () async {
      final soon = DateTime.now().add(const Duration(days: 5));
      final b = Birthday(id: 'soon', name: 'Soon', month: soon.month, day: soon.day);
      final fake = _FakeReminders();
      final c = _container(
        await _prefs({
          PrefsService.kRemindersOn: true,
          PrefsService.kRemindBirthdays: false,
          PrefsService.kBirthdays: _birthdaysJson([b]),
        }),
        fake,
      );
      c.listen(reminderSyncProvider, (_, _) {});
      await c.read(draftsProvider.future);
      await _settle();
      expect(fake.plans, isNotEmpty);
      for (final r in fake.plans.last) {
        expect(r.occasion?.birthday, isNull);
      }
    });
  });

  group('Reminders screen master switch', () {
    Future<(_FakeReminders, PrefsService)> pump(WidgetTester tester, {required bool on}) async {
      final prefs = await _prefs({if (on) PrefsService.kRemindersOn: true});
      final fake = _FakeReminders();
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(ProviderScope(
        overrides: [
          prefsProvider.overrideWithValue(prefs),
          reminderServiceProvider.overrideWithValue(fake),
          draftsProvider.overrideWith(_NoDrafts.new),
        ],
        child: MaterialApp(
          theme: AppTheme.dark,
          locale: const Locale('en'),
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          home: const RemindersScreen(),
        ),
      ));
      await tester.pumpAndSettle();
      return (fake, prefs);
    }

    testWidgets('opening the screen with reminders off asks for nothing', (tester) async {
      final (fake, _) = await pump(tester, on: false);
      expect(fake.calls, isEmpty);
    });

    testWidgets('turning it off cancels everything and never schedules', (tester) async {
      final (fake, prefs) = await pump(tester, on: true);
      await tester.tap(find.byType(Switch).first);
      await tester.pumpAndSettle();
      expect(prefs.getBool(PrefsService.kRemindersOn), isFalse);
      expect(fake.calls, contains('cancelAll'));
      expect(fake.calls, isNot(contains('schedule')));
    });

    testWidgets('turning it on asks for permission first', (tester) async {
      final (fake, prefs) = await pump(tester, on: false);
      fake.grant = false;
      await tester.tap(find.byType(Switch).first);
      await tester.pumpAndSettle();
      expect(fake.calls, ['requestPermission']);
      expect(prefs.getBool(PrefsService.kRemindersOn), isNot(isTrue));
    });
  });
}
