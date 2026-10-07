import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:collage/features/editor/collage_canvas.dart';
import 'package:collage/features/editor/editor_controller.dart';
import 'package:collage/models/collage_project.dart';
import 'package:collage/models/layout_template.dart';

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
  testWidgets('slot photo survives the interactive -> export toggle',
      (tester) async {
    final c = EditorController(project: _project(), pool: const ['a1']);
    await tester.pumpWidget(_host(c, interactive: true));
    await tester.pump();

    final before = tester.element(find.byType(ClipRRect).first);

    await tester.pumpWidget(_host(c, interactive: false));
    await tester.pump();

    final after = tester.element(find.byType(ClipRRect).first);
    expect(identical(before, after), isTrue,
        reason: 'switching to the export render must not rebuild the photo, or '
            'its decoded frame is lost and it can come out blank');
  });

  testWidgets('slot photo survives selecting and clearing the slot',
      (tester) async {
    final c = EditorController(project: _project(), pool: const ['a1']);
    await tester.pumpWidget(_host(c, interactive: true));
    await tester.pump();

    final unselected = tester.element(find.byType(ClipRRect).first);

    c.selectSlot('s1');
    await tester.pump();
    final selected = tester.element(find.byType(ClipRRect).first);
    expect(identical(unselected, selected), isTrue,
        reason: 'the selection ring / chips must not rebuild the photo');

    c.clearSelection();
    await tester.pump();
    final cleared = tester.element(find.byType(ClipRRect).first);
    expect(identical(selected, cleared), isTrue,
        reason: 'clearing the selection (as Save does) must not rebuild the photo');
  });
}
