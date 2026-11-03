import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:collage/features/editor/editor_controller.dart';
import 'package:collage/features/picker/picker_flow.dart';
import 'package:collage/models/canvas_element.dart';
import 'package:collage/models/collage_project.dart';
import 'package:collage/models/layout_template.dart';

LayoutTemplate _grid(int n) => LayoutTemplate(
      id: 'g$n',
      name: 'Grid $n',
      family: LayoutFamily.grid,
      slots: [
        for (var i = 0; i < n; i++)
          LayoutSlot(id: 's${i + 1}', rect: Rect.fromLTWH(i / n, 0, 1 / n, 1)),
      ],
    );

CollageProject _project({
  int slots = 3,
  Map<String, SlotFill>? fills,
  List<CanvasElement>? elements,
  LayoutTemplate? layout,
}) =>
    CollageProject(
      id: 'p1',
      title: 'Test',
      createdAt: 0,
      updatedAt: 0,
      ratioLabel: '1:1',
      layout: layout ?? _grid(slots),
      fills: fills ?? {},
      elements: elements ?? [],
      border: BorderSettings(),
      background: BackgroundSettings(),
    );

/// A three-slot collage with a1..a3 placed, s2 framed and filtered.
EditorController _filled() {
  final c = EditorController(
    project: _project(fills: {
      's1': SlotFill(assetId: 'a1'),
      's2': SlotFill(assetId: 'a2', zoom: 1.8, offsetX: 0.4, offsetY: -0.2, rotation: 0.3, flipX: true),
      's3': SlotFill(assetId: 'a3'),
    }),
    pool: const ['a1', 'a2', 'a3'],
  );
  return c;
}

void main() {
  group('diffSelection', () {
    test('identical selections have no changes', () {
      final d = diffSelection(['a', 'b'], ['a', 'b']);
      expect(d.added, isEmpty);
      expect(d.removed, isEmpty);
      expect(d.hasChanges, isFalse);
    });

    test('a pure reorder is not a change', () {
      expect(diffSelection(['a', 'b', 'c'], ['c', 'a', 'b']).hasChanges, isFalse);
    });

    test('added keeps the new order, removed keeps the old order', () {
      final d = diffSelection(['a', 'b', 'c', 'd'], ['e', 'c', 'f', 'a']);
      expect(d.added, ['e', 'f']);
      expect(d.removed, ['b', 'd']);
      expect(d.hasChanges, isTrue);
    });

    test('from nothing (new collage) everything is added', () {
      final d = diffSelection(const [], ['x', 'y']);
      expect(d.added, ['x', 'y']);
      expect(d.removed, isEmpty);
    });

    test('clearing the selection removes everything', () {
      final d = diffSelection(['x', 'y'], const []);
      expect(d.added, isEmpty);
      expect(d.removed, ['x', 'y']);
    });

    test('duplicate ids are reported once', () {
      final d = diffSelection(['a', 'a', 'b'], ['b', 'c', 'c']);
      expect(d.added, ['c']);
      expect(d.removed, ['a']);
    });
  });

  group('selectedPhotos (what the Photos tool reopens with)', () {
    test('a new, empty collage starts at 0', () {
      final c = EditorController(project: _project(), pool: const []);
      expect(c.selectedPhotos, isEmpty);
      c.dispose();
    });

    test('reopens with the placed photos in slot order, then unplaced picks', () {
      final c = EditorController(
        project: _project(slots: 2, fills: {
          's2': SlotFill(assetId: 'a1'),
          's1': SlotFill(assetId: 'a2'),
        }),
        pool: const ['a1', 'a2', 'a3', 'a4'],
      );
      expect(c.selectedPhotos, ['a2', 'a1', 'a3', 'a4']);
      expect(c.selectedPhotos, hasLength(4));
      c.dispose();
    });

    test('a photo placed twice is counted once', () {
      final c = EditorController(
        project: _project(slots: 2, fills: {
          's1': SlotFill(assetId: 'a1'),
          's2': SlotFill(assetId: 'a1'),
        }),
        pool: const ['a1'],
      );
      expect(c.selectedPhotos, ['a1']);
      c.dispose();
    });

    test('videos are not part of the photo selection', () {
      final c = EditorController(
        project: _project(slots: 2, fills: {
          's1': SlotFill(assetId: 'a1'),
          's2': SlotFill(assetId: 'v1', isVideo: true),
        }),
        pool: const ['a1'],
      );
      expect(c.selectedPhotos, ['a1']);
      c.dispose();
    });

    test('free-floating photos are included, placeholders are not', () {
      final c = EditorController(
        project: _project(slots: 1, fills: {'s1': SlotFill(assetId: 'a1')}, elements: [
          ImageElement(id: 'e1', cx: 0.5, cy: 0.5, assetId: 'f1'),
          ImageElement(id: 'e2', cx: 0.5, cy: 0.5, assetId: ''),
        ]),
        pool: const ['a1'],
      );
      expect(c.selectedPhotos, ['a1', 'f1']);
      c.dispose();
    });
  });

  group('applyPhotoSelection', () {
    test('unchanged selection changes nothing', () {
      final c = _filled();
      c.applyPhotoSelection(['a1', 'a2', 'a3']);
      expect(c.fillFor('s1')!.assetId, 'a1');
      expect(c.fillFor('s2')!.assetId, 'a2');
      expect(c.fillFor('s3')!.assetId, 'a3');
      expect(c.canUndo, isFalse);
      c.dispose();
    });

    test('removing a placed photo empties only its slot', () {
      final c = _filled();
      c.applyPhotoSelection(['a2', 'a3']);
      expect(c.fillFor('s1'), isNull);
      expect(c.fillFor('s3')!.assetId, 'a3');
      final s2 = c.fillFor('s2')!;
      expect(s2.assetId, 'a2');
      expect(s2.zoom, 1.8);
      expect(s2.offsetX, 0.4);
      expect(s2.offsetY, -0.2);
      expect(s2.rotation, 0.3);
      expect(s2.flipX, isTrue);
      expect(c.pool, ['a2', 'a3']);
      expect(c.selectedPhotos, ['a2', 'a3']);
      c.dispose();
    });

    test('removing a photo placed in two slots empties both', () {
      final c = EditorController(
        project: _project(fills: {
          's1': SlotFill(assetId: 'a1'),
          's2': SlotFill(assetId: 'a1'),
          's3': SlotFill(assetId: 'a3'),
        }),
        pool: const ['a1', 'a3'],
      );
      c.applyPhotoSelection(['a3']);
      expect(c.fillFor('s1'), isNull);
      expect(c.fillFor('s2'), isNull);
      expect(c.fillFor('s3')!.assetId, 'a3');
      c.dispose();
    });

    test('added photos fill empty slots in selection order, keeping existing ones', () {
      final c = EditorController(
        project: _project(slots: 4, fills: {'s2': SlotFill(assetId: 'a1', zoom: 2)}),
        pool: const ['a1'],
      );
      c.applyPhotoSelection(['a1', 'b1', 'b2']);
      expect(c.fillFor('s1')!.assetId, 'b1');
      expect(c.fillFor('s2')!.assetId, 'a1');
      expect(c.fillFor('s2')!.zoom, 2);
      expect(c.fillFor('s3')!.assetId, 'b2');
      expect(c.fillFor('s4'), isNull);
      c.dispose();
    });

    test('remove one and add one: the new photo takes the freed slot', () {
      final c = _filled();
      c.applyPhotoSelection(['a2', 'a3', 'b1']);
      expect(c.fillFor('s1')!.assetId, 'b1');
      expect(c.fillFor('s2')!.zoom, 1.8);
      expect(c.fillFor('s3')!.assetId, 'a3');
      c.dispose();
    });

    test('more photos than slots: the extras stay selected in the pool', () {
      final c = EditorController(project: _project(slots: 2), pool: const []);
      c.applyPhotoSelection(['x1', 'x2', 'x3', 'x4']);
      expect(c.fillFor('s1')!.assetId, 'x1');
      expect(c.fillFor('s2')!.assetId, 'x2');
      expect(c.unusedPoolAssets, ['x3', 'x4']);
      expect(c.selectedPhotos, ['x1', 'x2', 'x3', 'x4']);
      c.dispose();
    });

    test('video fills are never removed by a photo selection', () {
      final c = EditorController(
        project: _project(slots: 2, fills: {
          's1': SlotFill(assetId: 'a1'),
          's2': SlotFill(assetId: 'v1', isVideo: true),
        }),
        pool: const ['a1'],
      );
      c.applyPhotoSelection(const []);
      expect(c.fillFor('s1'), isNull);
      expect(c.fillFor('s2')!.assetId, 'v1');
      c.dispose();
    });

    test('deselected free photos are removed, placeholders stay', () {
      final c = EditorController(
        project: _project(slots: 1, fills: {'s1': SlotFill(assetId: 'a1')}, elements: [
          ImageElement(id: 'e1', cx: 0.5, cy: 0.5, assetId: 'f1'),
          ImageElement(id: 'e2', cx: 0.5, cy: 0.5, assetId: 'f2'),
        ]),
        pool: const ['a1'],
      );
      c.applyPhotoSelection(['a1', 'f2']);
      final ids = [for (final e in c.project.elements) (e as ImageElement).assetId];
      expect(ids, ['f2']);
      c.dispose();
    });

    test('clears the slot selection when the selected slot was emptied', () {
      final c = _filled();
      c.selectSlot('s1');
      c.applyPhotoSelection(['a2', 'a3']);
      expect(c.selectedSlotId, isNull);
      c.selectSlot('s2');
      c.applyPhotoSelection(['a2']);
      expect(c.selectedSlotId, 's2');
      c.dispose();
    });

    test('freeform (no slots): removed photos go, pool follows the selection', () {
      final c = EditorController(
        project: _project(
          layout: const LayoutTemplate(id: 'free', name: 'Free', family: LayoutFamily.freeform, slots: []),
          elements: [ImageElement(id: 'e1', cx: 0.5, cy: 0.5, assetId: 'f1')],
        ),
        pool: const ['f1'],
      );
      c.applyPhotoSelection(['n1']);
      expect(c.project.elements, isEmpty);
      expect(c.pool, ['n1']);
      expect(c.canUndo, isTrue);
      c.dispose();
    });
  });

  group('undo after applyPhotoSelection', () {
    test('one undo step restores every slot and its framing', () {
      final c = _filled();
      c.applyPhotoSelection(['a2', 'b1', 'b2']);
      expect(c.canUndo, isTrue);
      c.undo();
      expect(c.fillFor('s1')!.assetId, 'a1');
      expect(c.fillFor('s2')!.assetId, 'a2');
      expect(c.fillFor('s2')!.zoom, 1.8);
      expect(c.fillFor('s3')!.assetId, 'a3');
      expect(c.canUndo, isFalse);
      c.redo();
      expect(c.fillFor('s1')!.assetId, 'b1');
      expect(c.fillFor('s3')!.assetId, 'b2');
      c.dispose();
    });

    test(
      'after undo the Photos tool reopens with the pre-change selection',
      () {
        final c = _filled();
        final before = c.selectedPhotos;
        c.applyPhotoSelection(['a2', 'a3', 'b1']);
        c.undo();
        expect(c.selectedPhotos, before);
        c.redo();
        expect(c.selectedPhotos, containsAll(['a2', 'a3', 'b1']));
        expect(c.selectedPhotos, isNot(contains('a1')));
        c.dispose();
      },
    );
  });
}
