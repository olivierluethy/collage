import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'features/home/home_screen.dart';
import 'features/onboarding/onboarding_screen.dart';
import 'l10n/app_localizations.dart';
import 'state/providers.dart';
import 'state/settings.dart';
import 'theme/app_theme.dart';

class CollageApp extends ConsumerWidget {
  const CollageApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prefs = ref.watch(prefsProvider);
    final settings = ref.watch(settingsProvider);
    // Kick off the optional remote font / sticker catalogs. The bundled sets
    // work without it, so the (possibly pending) result is only used to know
    // when to rebuild once extra fonts arrive.
    ref.watch(remoteCatalogsProvider);
    return MaterialApp(
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
