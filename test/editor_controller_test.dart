import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:collage/features/editor/editor_controller.dart';
import 'package:collage/models/canvas_element.dart';
import 'package:collage/models/collage_project.dart';
import 'package:collage/models/layout_template.dart';

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
      fills: {'s1': SlotFill(assetId: 'a1'), 's2': SlotFill(assetId: 'a2')},
      elements: [],
      border: BorderSettings(),
      background: BackgroundSettings(),
    );

/// Wait until a burst of edits has settled into one undo step.
Future<void> _settle() => Future.delayed(const Duration(milliseconds: 450));

void main() {
  group('undo / redo', () {
    test('a fresh editor has nothing to undo or redo', () {
      final c = EditorController(project: _project(), pool: const ['a1', 'a2']);
      expect(c.canUndo, isFalse);
      expect(c.canRedo, isFalse);
      c.dispose();
    });

    test('undo reverts a swap and redo re-applies it', () async {
      final c = EditorController(project: _project(), pool: const ['a1', 'a2']);
      c.swapSlots('s1', 's2');
      expect(c.fillFor('s1')!.assetId, 'a2');
      expect(c.canUndo, isTrue);

      c.undo();
      expect(c.fillFor('s1')!.assetId, 'a1');
      expect(c.canRedo, isTrue);

      c.redo();
      expect(c.fillFor('s1')!.assetId, 'a2');
      c.dispose();
    });

    test('a continuous gesture becomes a single undo step', () async {
      final c = EditorController(project: _project(), pool: const ['a1', 'a2']);
      for (var i = 1; i <= 10; i++) {
        c.setSlotTransform('s1', zoom: 1 + i / 10);
      }
      await _settle();
      expect(c.fillFor('s1')!.zoom, 2);

      c.undo();
      expect(c.fillFor('s1')!.zoom, 1);
      expect(c.canUndo, isFalse);
      c.dispose();
    });

    test('separate edits are separate steps, and a new edit clears redo', () async {
      final c = EditorController(project: _project(), pool: const ['a1', 'a2']);
      c.updateBorder((b) => b.gap = 20);
      await _settle();
      c.updateBorder((b) => b.margin = 30);
      await _settle();

      c.undo();
      expect(c.border.margin, 12);
      expect(c.border.gap, 20);
      expect(c.canRedo, isTrue);

      c.updateBorder((b) => b.radius = 0);
      await _settle();
      expect(c.canRedo, isFalse);
      c.dispose();
    });

    test('undo drops a selection that no longer exists', () {
      final c = EditorController(project: _project(), pool: const ['a1', 'a2']);
      c.addEmoji('🙂');
      expect(c.selectedElementId, isNotNull);
      c.undo();
      expect(c.project.elements, isEmpty);
      expect(c.selectedElementId, isNull);
      c.dispose();
    });
  });

  group('slot rotation', () {
    test('quarter turns accumulate and wrap into -π..π', () {
      final c = EditorController(project: _project(), pool: const ['a1', 'a2']);
      c.rotateSlotQuarter('s1');
      expect(c.fillFor('s1')!.rotation, closeTo(1.5708, 1e-3));
      c.rotateSlotQuarter('s1');
      c.rotateSlotQuarter('s1');
      expect(c.fillFor('s1')!.rotation, closeTo(-1.5708, 1e-3));
      c.dispose();
    });

    test('recentring also resets rotation', () {
      final c = EditorController(project: _project(), pool: const ['a1', 'a2']);
      c.setSlotRotation('s1', 0.3);
      c.resetSlotTransform('s1');
      expect(c.fillFor('s1')!.rotation, 0);
      c.dispose();
    });

    test('rotation survives a JSON round-trip and is omitted at 0', () {
      expect(SlotFill(assetId: 'a').toJson().containsKey('rotation'), isFalse);
      final back = SlotFill.fromJson(SlotFill(assetId: 'a', rotation: 0.5).toJson());
      expect(back.rotation, 0.5);
    });
  });

  group('crop', () {
    test('crop insets are clamped and change the aspect ratio', () {
      final c = EditorController(project: _project(), pool: const ['a1', 'a2']);
      c.addImageElement('a1', 1.0);
      final id = c.selectedElementId!;
      c.setCrop(id, l: 0.25, r: 0.9);
      final im = c.project.elements.single as ImageElement;
      expect(im.cropL, 0.25);
      expect(im.cropR, ImageElement.maxCrop);
      expect(im.aspectRatio, closeTo(1 - 0.25 - ImageElement.maxCrop, 1e-9));
      c.resetCrop(id);
      expect(im.isCropped, isFalse);
      c.dispose();
    });

    test('crop survives a JSON round-trip', () {
      final im = ImageElement(id: 'i', cx: 0.5, cy: 0.5, assetId: 'a', cropT: 0.1, cropB: 0.2);
      final back = CanvasElement.fromJson(im.toJson()) as ImageElement;
      expect(back.cropT, 0.1);
      expect(back.cropB, 0.2);
      expect(back.cropL, 0);
    });
  });

  group('layers', () {
    test('layers are listed front-most first and reorder renumbers z', () {
      final c = EditorController(project: _project(), pool: const ['a1', 'a2']);
      c.addEmoji('1');
      c.addEmoji('2');
      c.addEmoji('3');
      expect(c.layers.map((e) => (e as EmojiElement).emoji), ['3', '2', '1']);

      // Drag the front-most layer to the bottom of the list.
      c.reorderLayer(0, 2);
      expect(c.layers.map((e) => (e as EmojiElement).emoji), ['2', '1', '3']);
      c.dispose();
    });

    test('duplicate adds an offset copy on top and selects it', () {
      final c = EditorController(project: _project(), pool: const ['a1', 'a2']);
      final t = c.addText('Hi', color: 0xFFFFFFFF);
      c.duplicateElement(t.id);
      expect(c.project.elements, hasLength(2));
      final copy = c.layers.first as TextElement;
      expect(copy.id, isNot(t.id));
      expect(copy.text, 'Hi');
      expect(copy.cx, greaterThan(t.cx));
      expect(c.selectedElementId, copy.id);
      c.dispose();
    });
  });

  group('snapping', () {
    test('snaps to the canvas centre within the threshold and publishes guides', () {
      final c = EditorController(project: _project(), pool: const ['a1', 'a2']);
      final (x, y) = c.snapPosition('none', 0.505, 0.2);
      expect(x, 0.5);
      expect(y, 0.2);
      expect(c.guideX, 0.5);
      expect(c.guideY, isNull);
      c.clearGuides();
      expect(c.guideX, isNull);
      c.dispose();
    });
  });

  group('text style', () {
    test('outline, shadow and spacing survive a JSON round-trip', () {
      final t = TextElement(
        id: 't',
        cx: 0.5,
        cy: 0.5,
        text: 'x',
        color: const Color(0xFFFFFFFF),
        outline: const Color(0xFF000000),
        outlineWidth: 4,
        shadow: true,
        letterSpacing: 6,
      );
      final back = CanvasElement.fromJson(t.toJson()) as TextElement;
      expect(back.outline, const Color(0xFF000000));
      expect(back.outlineWidth, 4);
      expect(back.shadow, isTrue);
      expect(back.letterSpacing, 6);
    });
  });
}
