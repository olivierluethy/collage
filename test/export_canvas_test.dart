import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:collage/features/editor/collage_canvas.dart';
import 'package:collage/features/editor/editor_controller.dart';
import 'package:collage/features/editor/editor_screen.dart';
import 'package:collage/l10n/app_localizations.dart';
import 'package:collage/models/collage_project.dart';
import 'package:collage/models/layout_template.dart';
import 'package:collage/theme/app_theme.dart';

CollageProject _project() => CollageProject(
      id: 'p1',
      title: 'Test',
      createdAt: 0,
      updatedAt: 0,
      ratioLabel: '1:1',
      layout: const LayoutTemplate(
        id: 'one',
        name: 'One',
        family: LayoutFamily.grid,
        slots: [LayoutSlot(id: 's1', rect: Rect.fromLTWH(0, 0, 1, 1))],
      ),
      fills: {'s1': SlotFill(assetId: 'a1')},
      elements: const [],
      border: BorderSettings(),
      background: BackgroundSettings(),
    );

Widget _host(EditorController c, {required bool interactive}) => MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 300,
            height: 300,
            child: CollageCanvas(controller: c, interactive: interactive),
          ),
        ),
      ),
    );

void main() {
  testWidgets('export canvas omits all editing chrome', (tester) async {
    final c = EditorController(project: _project(), pool: const ['a1']);
    await tester.pumpWidget(_host(c, interactive: false));
    await tester.pump();

    expect(find.byIcon(Icons.edit_rounded), findsNothing);
    expect(find.text('Replace'), findsNothing);
    expect(find.text('Swap'), findsNothing);
    expect(find.text('Flip H'), findsNothing);
    expect(find.text('Clear'), findsNothing);
  });

  testWidgets('interactive canvas shows the edit badge; tapping it edits the slot', (tester) async {
    final c = EditorController(project: _project(), pool: const ['a1']);
    final edited = <String>[];
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 300,
            height: 300,
            child: CollageCanvas(controller: c, interactive: true, onEditSlot: edited.add),
          ),
        ),
      ),
    ));
    await tester.pump();

    // The small persistent pencil badge; no floating chips on the photo.
    expect(find.byIcon(Icons.edit_rounded), findsOneWidget);
    expect(find.text('Replace'), findsNothing);

    await tester.tap(find.byIcon(Icons.edit_rounded));
    await tester.pump();
    expect(edited, ['s1']);

    // Selecting the photo still adds no chips to the canvas itself: the
    // actions live in the editor's context bar (see below).
    c.selectSlot('s1');
    await tester.pump();
    expect(find.text('Replace'), findsNothing);
    expect(find.text('Flip H'), findsNothing);
  });

  group('SlotContextBar', () {
    Future<Map<String, List<String>>> pumpBar(WidgetTester tester, EditorController c) async {
      final calls = <String, List<String>>{
        'replace': [], 'edit': [], 'filter': [], 'video': [], 'remove': [],
      };
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.dark,
        locale: const Locale('en'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: Scaffold(
          body: Align(
            alignment: Alignment.bottomCenter,
            child: SlotContextBar(
              controller: c,
              onReplace: calls['replace']!.add,
              onEdit: calls['edit']!.add,
              onFilter: calls['filter']!.add,
              onVideo: calls['video']!.add,
              onRemove: calls['remove']!.add,
            ),
          ),
        ),
      ));
      await tester.pump();
      return calls;
    }

    testWidgets('is hidden until a photo is selected, then lists its actions', (tester) async {
      final c = EditorController(project: _project(), pool: const ['a1']);
      final calls = await pumpBar(tester, c);

      expect(find.text('Replace'), findsNothing);

      c.selectSlot('s1');
      await tester.pump();
      for (final label in ['Replace', 'Edit', 'Filter', 'More', 'Remove']) {
        expect(find.text(label), findsOneWidget, reason: label);
      }
      expect(find.text('Drag to move the photo in its frame, pinch to zoom'), findsOneWidget);

      await tester.tap(find.text('Replace'));
      await tester.tap(find.text('Edit'));
      await tester.tap(find.text('Filter'));
      await tester.tap(find.text('Remove'));
      await tester.pump();
      expect(calls['replace'], ['s1']);
      expect(calls['edit'], ['s1']);
      expect(calls['filter'], ['s1']);
      expect(calls['remove'], ['s1']);
    });

    testWidgets('More holds swap, flip, rotate and reset; Flip H mirrors the photo', (tester) async {
      final c = EditorController(project: _project(), pool: const ['a1']);
      await pumpBar(tester, c);
      c.selectSlot('s1');
      await tester.pump();

      await tester.tap(find.text('More'));
      await tester.pumpAndSettle();
      for (final label in ['Swap with another photo', 'Flip H', 'Flip V']) {
        expect(find.text(label), findsOneWidget, reason: label);
      }

      await tester.tap(find.text('Flip H'));
      await tester.pumpAndSettle();
      expect(c.fillFor('s1')!.flipX, isTrue);
      expect(find.text('Flip V'), findsNothing, reason: 'sheet closes after an action');
    });

    testWidgets('swap mode shows its hint and can be cancelled', (tester) async {
      final c = EditorController(project: _project(), pool: const ['a1']);
      await pumpBar(tester, c);
      c.startSwapMode('s1');
      await tester.pump();

      expect(find.text('Cancel'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pump();
      expect(c.swapSource, isNull);
    });

    testWidgets('an empty slot offers Choose and Video only', (tester) async {
      final project = _project()..fills.clear();
      final c = EditorController(project: project, pool: const []);
      final calls = await pumpBar(tester, c);
      c.selectSlot('s1');
      await tester.pump();

      expect(find.text('Choose'), findsOneWidget);
      expect(find.text('Video'), findsOneWidget);
      expect(find.text('Remove'), findsNothing);
      expect(find.text('This frame is empty'), findsOneWidget);

      await tester.tap(find.text('Video'));
      await tester.pump();
      expect(calls['video'], ['s1']);
    });
  });
}
