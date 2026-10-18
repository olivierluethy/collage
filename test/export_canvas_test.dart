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

  testWidgets('interactive canvas shows the badge, then chips when selected',
      (tester) async {
    final c = EditorController(project: _project(), pool: const ['a1']);
    await tester.pumpWidget(_host(c, interactive: true));
    await tester.pump();

    // Filled but unselected: only the small persistent edit badge.
    expect(find.byIcon(Icons.edit_rounded), findsOneWidget);
    expect(find.text('Replace'), findsNothing);

    c.selectSlot('s1');
    await tester.pump();

    // Selected: the Replace / Swap / Flip / Clear chips appear.
    expect(find.text('Replace'), findsOneWidget);
    expect(find.text('Swap'), findsOneWidget);
    expect(find.text('Flip H'), findsOneWidget);
    expect(find.text('Clear'), findsOneWidget);
  });
}
