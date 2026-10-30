import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:collage/features/info/info_screen.dart';
import 'package:collage/l10n/app_localizations.dart';
import 'package:collage/services/prefs_service.dart';
import 'package:collage/state/providers.dart';
import 'package:collage/theme/app_theme.dart';

Future<PrefsService> _pump(WidgetTester tester) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await PrefsService.create();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [prefsProvider.overrideWithValue(prefs)],
      child: MaterialApp(
        theme: AppTheme.dark,
        locale: const Locale('en'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: const Scaffold(body: MoreTab()),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return prefs;
}

void main() {
  testWidgets('Info screen lists all sections', (tester) async {
    await _pump(tester);
    expect(find.text('Information'), findsOneWidget);
    expect(find.text('About'), findsOneWidget);
    expect(find.text('Language'), findsOneWidget);
    expect(find.text('Theme'), findsOneWidget);
    expect(find.text('Privacy Policy'), findsOneWidget);
    expect(find.text('Terms of Service'), findsOneWidget);
  });

  testWidgets('choosing a theme persists it', (tester) async {
    final prefs = await _pump(tester);
    expect(prefs.themeModeName, isNull);

    await tester.tap(find.text('Theme'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Light'));
    await tester.pumpAndSettle();

    expect(prefs.themeModeName, 'light');
  });

  testWidgets('choosing a language persists it', (tester) async {
    final prefs = await _pump(tester);
    expect(prefs.localeCode, isNull);

    await tester.tap(find.text('Language'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('中文'));
    await tester.pumpAndSettle();

    expect(prefs.localeCode, 'zh');
  });

  testWidgets('About opens and shows the app name', (tester) async {
    await _pump(tester);
    await tester.tap(find.text('About'));
    await tester.pumpAndSettle();
    expect(find.text('Collage'), findsOneWidget);
  });
}
