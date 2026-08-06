import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'features/home/home_screen.dart';
import 'features/onboarding/onboarding_screen.dart';
import 'state/providers.dart';
import 'theme/app_theme.dart';

class CollageApp extends ConsumerWidget {
  const CollageApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prefs = ref.watch(prefsProvider);
    return MaterialApp(
      title: 'Collage',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.dark,
      theme: AppTheme.dark,
      darkTheme: AppTheme.dark,
      home: prefs.onboardingDone ? const HomeScreen() : const OnboardingScreen(),
    );
  }
}
