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
        id: 'one',
        name: 'One',
        family: LayoutFamily.grid,
        slots: [LayoutSlot(id: 's1', rect: Rect.fromLTWH(0, 0, 1, 1))],
      ),
      fills: {'s1': SlotFill(assetId: 'a1')},
      elements: [
        ImageElement(id: 'img', cx: 0.5, cy: 0.5, assetId: 'a1'),
        EmojiElement(id: 'em', cx: 0.5, cy: 0.5, emoji: '🙂'),
      ],
      border: BorderSettings(),
      background: BackgroundSettings(),
    );

void main() {
  group('SlotFill flip', () {
    test('defaults to unflipped and omits flags from JSON', () {
      final json = SlotFill(assetId: 'a1').toJson();
      expect(json.containsKey('flipX'), isFalse);
      expect(json.containsKey('flipY'), isFalse);
    });

    test('survives a JSON round-trip', () {
      final fill = SlotFill(assetId: 'a1', flipX: true, flipY: true);
      final back = SlotFill.fromJson(fill.toJson());
      expect(back.flipX, isTrue);
      expect(back.flipY, isTrue);
      expect(back.isFlipped, isTrue);
    });

    test('clone preserves the flip', () {
      final c = SlotFill(assetId: 'a1', flipX: true).clone();
      expect(c.flipX, isTrue);
      expect(c.flipY, isFalse);
    });
  });

  group('ImageElement flip', () {
    test('defaults to unflipped and omits flags from JSON', () {
      final json = ImageElement(id: 'i', cx: 0.5, cy: 0.5, assetId: 'a1').toJson();
      expect(json.containsKey('flipX'), isFalse);
      expect(json.containsKey('flipY'), isFalse);
    });

    test('survives a JSON round-trip through CanvasElement.fromJson', () {
      final el = ImageElement(id: 'i', cx: 0.5, cy: 0.5, assetId: 'a1', flipY: true);
      final back = CanvasElement.fromJson(el.toJson()) as ImageElement;
      expect(back.flipX, isFalse);
      expect(back.flipY, isTrue);
    });
  });

  group('EditorController flip', () {
    test('toggleSlot flips each axis independently', () {
      final c = EditorController(project: _project(), pool: const ['a1', 'a2']);
      final f = c.fillFor('s1')!;

      c.flipSlot('s1', horizontal: true);
      expect(f.flipX, isTrue);
      expect(f.flipY, isFalse);

      c.flipSlot('s1', vertical: true);
      expect(f.flipX, isTrue);
      expect(f.flipY, isTrue);

      c.flipSlot('s1', horizontal: true);
      expect(f.flipX, isFalse);
      expect(f.flipY, isTrue);
    });

    test('flipElement affects photo elements only', () {
      final c = EditorController(project: _project(), pool: const ['a1']);
      c.flipElement('img', horizontal: true);
      expect((c.project.elements.firstWhere((e) => e.id == 'img') as ImageElement).flipX, isTrue);

      // A non-photo element ignores the same call without throwing.
      c.flipElement('em', horizontal: true);
      expect((c.project.elements.firstWhere((e) => e.id == 'em')).type, ElementType.emoji);
    });
  });
}
