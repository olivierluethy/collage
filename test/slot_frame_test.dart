import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:collage/features/editor/collage_canvas.dart';
import 'package:collage/features/editor/editor_controller.dart';
import 'package:collage/models/collage_project.dart';
import 'package:collage/models/layout_template.dart';

/// A single full-canvas slot holding a 2:1 photo, so a square cell leaves
/// horizontal (and no vertical) slack to pan within.
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
      fills: {'s1': SlotFill(assetId: 'a1', imgAspect: 2.0)},
      elements: const [],
      border: BorderSettings(),
      background: BackgroundSettings(),
    );

Widget _host(EditorController c, {bool interactive = true}) => MaterialApp(
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
  group('SlotFill framing model', () {
    test('a fresh fill is centred and unzoomed', () {
      final f = SlotFill(assetId: 'a1');
      expect(f.offsetX, 0);
      expect(f.offsetY, 0);
      expect(f.zoom, 1);
    });

    test('pan/zoom survives a JSON round-trip', () {
      final f = SlotFill(assetId: 'a1', offsetX: 0.3, offsetY: -0.4, zoom: 2.5);
      final back = SlotFill.fromJson(f.toJson());
      expect(back.offsetX, 0.3);
      expect(back.offsetY, -0.4);
      expect(back.zoom, 2.5);
    });

    test('clone preserves the framing', () {
      final f = SlotFill(assetId: 'a1', offsetX: 0.3, zoom: 2.5).clone();
      expect(f.offsetX, 0.3);
      expect(f.zoom, 2.5);
    });
  });

  group('EditorController framing', () {
    test('setSlotTransform clamps pan to ±1 and zoom to 1..4', () {
      final c = EditorController(project: _project(), pool: const ['a1']);
      c.setSlotTransform('s1', offX: 5, offY: -5, zoom: 99);
      final f = c.fillFor('s1')!;
      expect(f.offsetX, 1);
      expect(f.offsetY, -1);
      expect(f.zoom, 4);

      c.setSlotTransform('s1', zoom: 0.1);
      expect(c.fillFor('s1')!.zoom, 1);
    });

    test('resetSlotTransform recentres the photo', () {
      final c = EditorController(project: _project(), pool: const ['a1']);
      c.setSlotTransform('s1', offX: 0.7, offY: -0.2, zoom: 3);
      c.resetSlotTransform('s1');
      final f = c.fillFor('s1')!;
      expect(f.offsetX, 0);
      expect(f.offsetY, 0);
      expect(f.zoom, 1);
    });
  });

  group('slot framing gestures', () {
    testWidgets('dragging a selected slot pans the photo', (tester) async {
      final c = EditorController(project: _project(), pool: const ['a1']);
      await tester.pumpWidget(_host(c));
      await tester.pump();

      c.selectSlot('s1');
      await tester.pump();

      // Drag right: the photo follows the finger, revealing its left side, so
      // the horizontal alignment moves toward -1.
      await tester.drag(find.byType(CollageCanvas), const Offset(60, 0));
      await tester.pump();

      expect(c.fillFor('s1')!.offsetX, lessThan(0));
      expect(c.fillFor('s1')!.offsetY, 0,
          reason: 'a 2:1 photo in a square cell has no vertical slack to pan');

      // Let the double-tap recogniser's pending timer elapse.
      await tester.pump(const Duration(seconds: 1));
    });

    testWidgets('dragging an unselected slot does not frame it', (tester) async {
      final c = EditorController(project: _project(), pool: const ['a1']);
      await tester.pumpWidget(_host(c));
      await tester.pump();

      await tester.drag(find.byType(CollageCanvas), const Offset(60, 0));
      await tester.pump();

      // Unselected slots drag-to-swap, not frame.
      expect(c.fillFor('s1')!.offsetX, 0);
    });

    testWidgets('pinching a selected slot zooms the photo', (tester) async {
      final c = EditorController(project: _project(), pool: const ['a1']);
      await tester.pumpWidget(_host(c));
      await tester.pump();

      c.selectSlot('s1');
      await tester.pump();

      final center = tester.getCenter(find.byType(CollageCanvas));
      final left = await tester.startGesture(center - const Offset(20, 0));
      final right = await tester.startGesture(center + const Offset(20, 0));

      await left.moveBy(const Offset(-40, 0));
      await right.moveBy(const Offset(40, 0));
      await tester.pump();

      await left.up();
      await right.up();
      await tester.pump();

      expect(c.fillFor('s1')!.zoom, greaterThan(1));

      // Let the double-tap recogniser's pending timer elapse.
      await tester.pump(const Duration(seconds: 1));
    });

    testWidgets('framing is disabled while a replace preview is open',
        (tester) async {
      final c = EditorController(project: _project(), pool: const ['a1', 'a2']);
      await tester.pumpWidget(_host(c));
      await tester.pump();

      c.startReplace('s1');
      await tester.pump();

      await tester.drag(find.byType(CollageCanvas), const Offset(60, 0));
      await tester.pump();

      // The visible photo is a candidate, so a drag must not edit the original.
      expect(c.fillFor('s1')!.offsetX, 0);
    });

    testWidgets('the export render ignores framing gestures', (tester) async {
      final c = EditorController(project: _project(), pool: const ['a1']);
      c.selectSlot('s1');
      await tester.pumpWidget(_host(c, interactive: false));
      await tester.pump();

      await tester.drag(find.byType(CollageCanvas), const Offset(60, 0));
      await tester.pump();

      expect(c.fillFor('s1')!.offsetX, 0);
      expect(c.fillFor('s1')!.zoom, 1);
    });
  });
}
