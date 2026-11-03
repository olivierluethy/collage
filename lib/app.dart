import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'features/exports/export_history_screen.dart';
import 'features/home/home_screen.dart';
import 'features/templates/occasion_card.dart';
import 'features/onboarding/onboarding_screen.dart';
import 'l10n/app_localizations.dart';
import 'state/providers.dart';
import 'services/occasion_service.dart';
import 'services/reminder_service.dart';
import 'state/occasions.dart';
import 'state/reminders.dart';
import 'state/settings.dart';
import 'theme/app_theme.dart';

/// Root navigator, so a tapped notification can open a screen.
final appNavigatorKey = GlobalKey<NavigatorState>();

class CollageApp extends ConsumerStatefulWidget {
  const CollageApp({super.key});

  @override
  ConsumerState<CollageApp> createState() => _CollageAppState();
}

class _CollageAppState extends ConsumerState<CollageApp> {
  StreamSubscription<String>? _taps;

  @override
  void initState() {
    super.initState();
    // Only when some notification is on: otherwise the notification plugin
    // isn't touched at all.
    final p = ref.read(occasionPrefsProvider);
    if (p.notifyExports || p.remindersOn) _listenToTaps();
  }

  Future<void> _listenToTaps() async {
    if (_taps != null) return;
    final svc = ref.read(reminderServiceProvider);
    _taps = svc.taps.listen(_openFor);
    final launched = await svc.launchPayload();
    if (launched != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _openFor(launched));
    }
  }

  /// "Collage saved" opens Recent exports, where the file can be opened,
  /// found or shared. An occasion or birthday reminder opens that
  /// occasion's templates. Memories (and anything unknown) just open the app.
  void _openFor(String payload) {
    final nav = appNavigatorKey.currentState;
    if (nav == null) return;
    if (payload == ReminderService.exportPayload) {
      nav.push(MaterialPageRoute(builder: (_) => const ExportHistoryScreen()));
      return;
    }
    final occasion = _occasionFor(payload);
    if (occasion != null) {
      nav.push(MaterialPageRoute(builder: (_) => OccasionTemplatesScreen(occasion: occasion)));
    }
  }

  /// Reminders arrive a few days ahead and may be tapped late, so look a
  /// little back as well as ahead.
  OccasionDate? _occasionFor(String payload) {
    final now = DateTime.now();
    final candidates = ref.read(occasionServiceProvider).occurrences(
          from: now.subtract(const Duration(days: 14)),
          to: now.add(const Duration(days: 60)),
          region: ref.read(occasionRegionProvider),
          birthdays: ref.read(birthdaysProvider),
        );
    // Bare ids from older versions: prefer the next occurrence over a past one.
    final today = DateTime(now.year, now.month, now.day);
    candidates.sort((a, b) {
      final ap = a.date.isBefore(today), bp = b.date.isBefore(today);
      if (ap != bp) return ap ? 1 : -1;
      return a.date.compareTo(b.date);
    });
    return ReminderService.matchOccasionPayload(payload, candidates);
  }

  @override
  void dispose() {
    _taps?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Turned on during this session: start listening now.
    ref.listen<bool>(
      occasionPrefsProvider.select((p) => p.notifyExports || p.remindersOn),
      (_, on) {
        if (on && _taps == null) _listenToTaps();
      },
    );
    final prefs = ref.watch(prefsProvider);
    final settings = ref.watch(settingsProvider);
    // Kick off the optional remote font / sticker catalogs. The bundled sets
    // work without it, so the (possibly pending) result is only used to know
    // when to rebuild once extra fonts arrive.
    ref.watch(remoteCatalogsProvider);
    // Re-plans occasion / birthday reminders; inert while reminders are off.
    ref.watch(reminderSyncProvider);
    return MaterialApp(
      navigatorKey: appNavigatorKey,
      title: 'Collage',
      debugShowCheckedModeBanner: false,
      themeMode: settings.themeMode,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      locale: settings.locale,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      home: prefs.onboardingDone ? const HomeScreen() : const OnboardingScreen(),
    );
  }
}
