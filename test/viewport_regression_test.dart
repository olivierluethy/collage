import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:collage/features/editor/editor_controller.dart';
import 'package:collage/features/editor/editor_screen.dart';
import 'package:collage/features/info/info_screen.dart';
import 'package:collage/features/templates/templates_tab.dart';
import 'package:collage/l10n/app_localizations.dart';
import 'package:collage/models/collage_project.dart';
import 'package:collage/models/layout_template.dart';
import 'package:collage/services/prefs_service.dart';
import 'package:collage/state/providers.dart';
import 'package:collage/theme/app_theme.dart';

/// Phone sizes in logical pixels: iPhone SE (1st gen), a 360 dp Android and
/// a large phone. Every screen here must lay out without overflow on each,
/// at normal and enlarged text. Overflow is reported as a test failure by the
/// framework, so pumping is the assertion; the explicit checks below just
/// make the intent visible.
const _sizes = {'320x568': Size(320, 568), '360x640': Size(360, 640), '430x932': Size(430, 932)};
const _textScales = [1.0, 1.3];

/// German and Russian have some of the longest labels.
const _locales = ['en', 'de', 'ru'];

Future<void> _pump(WidgetTester tester, Size size, double textScale, String lang, Widget home) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await PrefsService.create();
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ProviderScope(
    overrides: [prefsProvider.overrideWithValue(prefs)],
    child: MaterialApp(
      theme: AppTheme.dark,
      locale: Locale(lang),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: home,
    ),
  ));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

CollageProject _project() => CollageProject(
      id: 'p1',
      title: 'Test',
      createdAt: 0,
      updatedAt: 0,
      ratioLabel: '1:1',
      layout: const LayoutTemplate(
        id: 'two',
        name: 'Two',
        family: LayoutFamily.grid,
        slots: [
          LayoutSlot(id: 's1', rect: Rect.fromLTWH(0, 0, 0.5, 1)),
          LayoutSlot(id: 's2', rect: Rect.fromLTWH(0.5, 0, 0.5, 1)),
        ],
      ),
      fills: {'s1': SlotFill(assetId: 'a1')},
      elements: const [],
      border: BorderSettings(),
      background: BackgroundSettings(),
    );

void main() {
  for (final MapEntry(key: name, value: size) in _sizes.entries) {
    for (final scale in _textScales) {
      for (final lang in _locales) {
        final tag = '$name @${scale}x $lang';

        testWidgets('Templates tab and its Filters sheet fit — $tag', (tester) async {
          await _pump(tester, size, scale, lang, const Scaffold(body: TemplatesTab()));
          expect(tester.takeException(), isNull);
          await tester.tap(find.byIcon(Icons.tune_rounded));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 400));
          expect(tester.takeException(), isNull);
        });

        testWidgets('More tab fits — $tag', (tester) async {
          await _pump(tester, size, scale, lang, const Scaffold(body: MoreTab()));
          expect(tester.takeException(), isNull);
        });

        testWidgets('photo context bar fits, filled and empty — $tag', (tester) async {
          final c = EditorController(project: _project(), pool: const ['a1']);
          await _pump(
            tester,
            size,
            scale,
            lang,
            Scaffold(
              body: Align(
                alignment: Alignment.bottomCenter,
                child: SlotContextBar(
                  controller: c,
                  onReplace: (_) {},
                  onEdit: (_) {},
                  onFilter: (_) {},
                  onVideo: (_) {},
                  onRemove: (_) {},
                ),
              ),
            ),
          );
          c.selectSlot('s1');
          await tester.pump();
          expect(tester.takeException(), isNull);
          c.selectSlot('s2');
          await tester.pump();
          expect(tester.takeException(), isNull);
        });
      }
    }
  }
}
