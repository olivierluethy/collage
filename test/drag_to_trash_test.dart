import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:collage/features/editor/collage_canvas.dart';
import 'package:collage/features/editor/editor_controller.dart';
import 'package:collage/l10n/app_localizations.dart';
import 'package:collage/models/canvas_element.dart';
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
      // A caption right over the middle of the photo.
      elements: [TextElement(id: 't1', cx: 0.5, cy: 0.5, text: 'Hello', color: Colors.white, z: 1)],
      border: BorderSettings(),
      background: BackgroundSettings(),
    );

/// Canvas at the top of the screen; anything below y = 400 counts as the
/// trash target.
Future<List<String>> _pump(WidgetTester tester, EditorController c) async {
  final trashed = <String>[];
  await tester.pumpWidget(MaterialApp(
    theme: AppTheme.dark,
    locale: const Locale('en'),
    supportedLocales: AppLocalizations.supportedLocales,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    home: Scaffold(
      body: Align(
        alignment: Alignment.topCenter,
        child: SizedBox(
          width: 300,
          height: 300,
          child: CollageCanvas(
            controller: c,
            onElementTrashed: trashed.add,
            isOverTrash: (g) => g.dy > 400,
          ),
        ),
      ),
    ),
  ));
  await _settle(tester);
  return trashed;
}

/// The photo placeholder animates while the (absent) gallery loads, so
/// pumpAndSettle would never return: pump a fixed span instead.
Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  testWidgets('tapping text over a photo selects the text, not the photo', (tester) async {
    final c = EditorController(project: _project(), pool: const ['a1']);
    await _pump(tester, c);

    await tester.tap(find.text('Hello'));
    await tester.pump();
    expect(c.selectedElementId, 't1');
    expect(c.selectedSlotId, isNull);
  });

  testWidgets('every corner of the text takes the tap, not just the bottom-right', (tester) async {
    final c = EditorController(project: _project(), pool: const ['a1']);
    await _pump(tester, c);
    final r = tester.getRect(find.text('Hello'));
    for (final p in [r.topLeft + const Offset(3, 3), r.topRight + const Offset(-3, 3), r.bottomLeft + const Offset(3, -3)]) {
      c.clearSelection();
      await tester.tapAt(p);
      await tester.pump(const Duration(milliseconds: 300));
      expect(c.selectedElementId, 't1', reason: 'tap at $p');
      expect(c.selectedSlotId, isNull, reason: 'tap at $p fell through to the photo');
    }
  });

  testWidgets('dragging text onto the trash deletes it; Undo brings it back', (tester) async {
    final c = EditorController(project: _project(), pool: const ['a1']);
    final trashed = await _pump(tester, c);

    final g = await tester.startGesture(tester.getCenter(find.text('Hello')));
    await g.moveBy(const Offset(0, 40));
    await tester.pump();
    expect(c.showTrash, isTrue, reason: 'the trash appears while dragging');
    expect(c.overTrash, isFalse);

    await g.moveBy(const Offset(0, 300));
    await tester.pump();
    expect(c.overTrash, isTrue);
    await g.up();
    await tester.pump();

    expect(trashed, ['t1']);
    expect(c.showTrash, isFalse);

    // The editor answers the drop with deleteElement + an Undo snack.
    c.deleteElement('t1');
    await tester.pump();
    expect(find.text('Hello'), findsNothing);

    c.undo();
    await _settle(tester);
    expect(find.text('Hello'), findsOneWidget);
    expect(c.project.elements.single.id, 't1');
  });

  testWidgets('releasing away from the trash keeps the element', (tester) async {
    final c = EditorController(project: _project(), pool: const ['a1']);
    final trashed = await _pump(tester, c);

    final g = await tester.startGesture(tester.getCenter(find.text('Hello')));
    await g.moveBy(const Offset(0, 40));
    await g.moveBy(const Offset(0, 300)); // over the trash…
    await tester.pump();
    await g.moveBy(const Offset(0, -300)); // …and back out
    await tester.pump();
    await g.up();
    await tester.pump();

    await _settle(tester); // let the controller's snapshot timer run
    expect(trashed, isEmpty);
    expect(c.project.elements, hasLength(1));
  });

  testWidgets('the selected element has a Delete handle reachable without dragging', (tester) async {
    final c = EditorController(project: _project(), pool: const ['a1']);
    final trashed = await _pump(tester, c);

    c.selectElement('t1');
    await _settle(tester);
    final handle = find.bySemanticsLabel('Delete');
    expect(handle, findsOneWidget);
    await tester.tap(handle);
    await tester.pump();
    expect(trashed, ['t1']);
  });
}
