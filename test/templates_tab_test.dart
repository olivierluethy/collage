import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:collage/data/template_catalog.dart';
import 'package:collage/features/templates/templates_tab.dart';
import 'package:collage/l10n/app_localizations.dart';
import 'package:collage/models/collage_template.dart';
import 'package:collage/services/prefs_service.dart';
import 'package:collage/state/providers.dart';
import 'package:collage/theme/app_theme.dart';

Future<void> _pump(WidgetTester tester, {Map<String, Object> prefs = const {}}) async {
  SharedPreferences.setMockInitialValues(prefs);
  final service = await PrefsService.create();
  tester.view.physicalSize = const Size(400, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [prefsProvider.overrideWithValue(service)],
      child: MaterialApp(
        theme: AppTheme.dark,
        locale: const Locale('en'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: const Scaffold(body: TemplatesTab()),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// The horizontal category chip strip (the TextField has its own horizontal
/// Scrollable, so match the ListView rather than any horizontal Scrollable).
Finder get _chipStrip => find.byWidgetPredicate(
      (w) => w is ListView && w.scrollDirection == Axis.horizontal,
    );

Future<void> _showChip(WidgetTester tester, String label) async {
  for (var i = 0; i < 20 && find.text(label).evaluate().isEmpty; i++) {
    await tester.drag(_chipStrip.first, const Offset(-150, 0));
    await tester.pumpAndSettle();
  }
  await tester.ensureVisible(find.text(label).first);
  await tester.pumpAndSettle();
}

int _count(bool Function(CollageTemplate t) test) => TemplateCatalog.all().where(test).length;

void main() {
  testWidgets('browse view shows search, category chips and the full count', (tester) async {
    await _pump(tester);

    expect(find.byType(TextField), findsOneWidget);
    expect(find.byTooltip('Filters'), findsOneWidget);
    for (final chip in ['All', 'Invitations', 'Holidays', 'Minimal', 'Birthday']) {
      await _showChip(tester, chip);
      expect(find.text(chip), findsWidgets, reason: chip);
    }
    // No favourites yet, so that chip is hidden.
    expect(find.text('Favourites'), findsNothing);
    expect(find.text('${TemplateCatalog.all().length} templates'), findsOneWidget);
    expect(find.text('Clear filters'), findsNothing);
  });

  testWidgets('the Filters sheet narrows by photo count', (tester) async {
    await _pump(tester);

    await tester.tap(find.byTooltip('Filters'));
    await tester.pumpAndSettle();
    expect(find.text('Shape'), findsOneWidget);

    await tester.ensureVisible(find.bySemanticsLabel('4 photos'));
    await tester.tap(find.bySemanticsLabel('4 photos'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Show templates'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Show templates'));
    await tester.pumpAndSettle();

    final n = _count((t) => t.photoCount == 4);
    expect(n, greaterThan(0));
    expect(find.text('$n templates'), findsOneWidget);
    // The active filter is spelled out next to the count, and can be cleared.
    expect(find.text('Clear filters'), findsOneWidget);

    await tester.tap(find.text('Clear filters'));
    await tester.pumpAndSettle();
    expect(find.text('${TemplateCatalog.all().length} templates'), findsOneWidget);
  });

  testWidgets('a style chip filters the grid to that style', (tester) async {
    await _pump(tester);

    await _showChip(tester, 'Birthday');
    await tester.tap(find.text('Birthday').first);
    await tester.pumpAndSettle();

    final n = _count((t) => t.style == TemplateStyle.birthday);
    expect(n, greaterThan(0));
    expect(find.text('$n templates'), findsOneWidget);
  });

  testWidgets('searching shows the no-match state and clears back', (tester) async {
    await _pump(tester);

    await tester.enterText(find.byType(TextField), 'zzzqqq');
    await tester.pumpAndSettle();
    expect(find.text('No templates match'), findsOneWidget);

    await tester.tap(find.byTooltip('Clear search'));
    await tester.pumpAndSettle();
    expect(find.text('No templates match'), findsNothing);
    expect(find.text('${TemplateCatalog.all().length} templates'), findsOneWidget);
  });
}
