import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:collage/features/templates/templates_tab.dart';
import 'package:collage/l10n/app_localizations.dart';
import 'package:collage/theme/app_theme.dart';

Widget _host() => ProviderScope(
      child: MaterialApp(
        theme: AppTheme.dark,
        locale: const Locale('en'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: const Scaffold(body: TemplatesTab()),
      ),
    );

void main() {
  testWidgets('shows the photo-count and style filters plus tiles',
      (tester) async {
    await tester.pumpWidget(_host());
    await tester.pumpAndSettle();

    expect(find.text('PHOTOS'), findsOneWidget);
    expect(find.text('STYLE'), findsOneWidget);
    expect(find.text('All'), findsOneWidget);
    expect(find.text('Minimal'), findsOneWidget);
    // Default bucket is 2 photos, so the tiles are labelled "2 photos".
    expect(find.text('2 photos'), findsWidgets);
  });

  testWidgets('changing the photo count refilters the grid', (tester) async {
    await tester.pumpWidget(_host());
    await tester.pumpAndSettle();

    await tester.tap(find.text('4'));
    await tester.pumpAndSettle();

    expect(find.text('4 photos'), findsWidgets);
    expect(find.text('2 photos'), findsNothing);
  });

  testWidgets('choosing a style keeps the grid populated', (tester) async {
    await tester.pumpWidget(_host());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Birthday'));
    await tester.pumpAndSettle();

    expect(find.text('2 photos'), findsWidgets);
  });
}
