import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'package:collage/features/editor/editor_controller.dart';
import 'package:collage/features/editor/slot_splits.dart';
import 'package:collage/models/collage_project.dart';
import 'package:collage/models/layout_template.dart';
import 'package:collage/services/book_service.dart';
import 'package:collage/services/export_service.dart';
import 'package:collage/services/vision_service.dart';

/// Left column A spanning the height; right side split into B (top) and C.
const _slots = [
  LayoutSlot(id: 'A', rect: Rect.fromLTRB(0, 0, 0.5, 1)),
  LayoutSlot(id: 'B', rect: Rect.fromLTRB(0.5, 0, 1, 0.5)),
  LayoutSlot(id: 'C', rect: Rect.fromLTRB(0.5, 0.5, 1, 1)),
];

CollageProject _project() => CollageProject(
      id: 'p',
      title: 'T',
      createdAt: 0,
      updatedAt: 0,
      ratioLabel: '1:1',
      layout: const LayoutTemplate(id: 'l', name: 'L', family: LayoutFamily.grid, slots: _slots),
      fills: {'A': SlotFill(assetId: 'a'), 'B': SlotFill(assetId: 'b'), 'C': SlotFill(assetId: 'c')},
      elements: [],
      border: BorderSettings(),
      background: BackgroundSettings(),
    );

void main() {
  group('slot splits', () {
    test('finds one vertical and one horizontal split', () {
      final splits = findSplits(_slots);
      expect(splits, hasLength(2));
      final v = splits.firstWhere((s) => s.axis == Axis.vertical);
      expect(v.pos, 0.5);
      expect(v.before, {'A'});
      expect(v.after, {'B', 'C'});
      final h = splits.firstWhere((s) => s.axis == Axis.horizontal);
      expect(h.before, {'B'});
      expect(h.after, {'C'});
      expect(h.start, 0.5);
      expect(h.end, 1);
    });

    test('moving a split resizes both sides and clamps to the minimum', () {
      final v = findSplits(_slots).firstWhere((s) => s.axis == Axis.vertical);
      final moved = moveSplit(_slots, v, 0.7);
      expect(moved.firstWhere((s) => s.id == 'A').rect.right, closeTo(0.7, 1e-9));
      expect(moved.firstWhere((s) => s.id == 'B').rect.left, closeTo(0.7, 1e-9));
      expect(moved.firstWhere((s) => s.id == 'C').rect.left, closeTo(0.7, 1e-9));

      final clamped = moveSplit(_slots, v, 0.99);
      expect(clamped.firstWhere((s) => s.id == 'B').rect.width, closeTo(0.08, 1e-9));
    });

    test('separate rows with the same split line stay independent', () {
      const rows = [
        LayoutSlot(id: 'A', rect: Rect.fromLTRB(0, 0, 0.5, 0.5)),
        LayoutSlot(id: 'B', rect: Rect.fromLTRB(0.5, 0, 1, 0.5)),
        LayoutSlot(id: 'C', rect: Rect.fromLTRB(0, 0.5, 0.5, 1)),
        LayoutSlot(id: 'D', rect: Rect.fromLTRB(0.5, 0.5, 1, 1)),
      ];
      final vertical = findSplits(rows).where((s) => s.axis == Axis.vertical).toList();
      expect(vertical, hasLength(2));
    });

    test('polygon layouts have no splits', () {
      final poly = [LayoutSlot.poly('P', const [Offset(0, 0), Offset(1, 0), Offset(0, 1)])];
      expect(findSplits(poly), isEmpty);
    });

    test('the controller saves a moved split as a custom layout', () {
      final c = EditorController(project: _project(), pool: const ['a', 'b', 'c']);
      final v = c.splits.firstWhere((s) => s.axis == Axis.vertical);
      c.moveSplitTo(v, 0.3);
      expect(c.project.layout.custom, isTrue);
      expect(c.project.layout.slots.firstWhere((s) => s.id == 'A').rect.right, closeTo(0.3, 1e-9));
      c.undo();
      expect(c.project.layout.slots.firstWhere((s) => s.id == 'A').rect.right, 0.5);
      c.dispose();
    });
  });

  group('polygon splits', () {
    // A diagonal split: left cell (0,0)-(0.6,0)-(0.4,1)-(0,1), right cell the rest.
    final diag = [
      LayoutSlot.poly('L', const [Offset(0, 0), Offset(0.6, 0), Offset(0.4, 1), Offset(0, 1)]),
      LayoutSlot.poly('R', const [Offset(0.6, 0), Offset(1, 0), Offset(1, 1), Offset(0.4, 1)]),
    ];

    test('finds the shared diagonal edge only', () {
      final splits = findPolySplits(diag);
      expect(splits, hasLength(1));
      expect(splits.single.slots, {'L', 'R'});
      expect(findSplits(diag), isEmpty);
    });

    test('shifting the edge slides its ends along the borders', () {
      final sp = findPolySplits(diag).single;
      final moved = movePolySplit(diag, sp, 0.1 * (sp.normal.dx.sign))!;
      final l = moved.firstWhere((s) => s.id == 'L').points!;
      // Both ends stay on the top and bottom borders and move by the same x.
      expect(l[1].dy, 0);
      expect(l[2].dy, 1);
      expect(l[1].dx - 0.6, closeTo(l[2].dx - 0.4, 1e-9));
      expect(l[1].dx, isNot(closeTo(0.6, 1e-6)));
      // The neighbour moved with it.
      final r = moved.firstWhere((s) => s.id == 'R').points!;
      expect(r[0], l[1]);
      expect(r[3], l[2]);
    });

    test('a move that would collapse a cell is rejected', () {
      final sp = findPolySplits(diag).single;
      expect(movePolySplit(diag, sp, 5), isNull);
      expect(movePolySplit(diag, sp, -5), isNull);
    });
  });

  group('face framing', () {
    test('pans a wide photo towards a face on the right', () {
      // Square cell, 2:1 photo: half the width is visible.
      final pan = panForFocus(const Offset(0.9, 0.5), 1, 2);
      expect(pan.dx, 1); // as far right as it goes
      expect(pan.dy, 0); // no vertical slack
    });

    test('a centred face needs no pan', () {
      final pan = panForFocus(const Offset(0.5, 0.5), 1, 2);
      expect(pan.dx, closeTo(0, 1e-9));
    });

    test('the controller applies the pan to the slot', () {
      final c = EditorController(project: _project(), pool: const ['a', 'b', 'c']);
      // Slot A is 0.5 × 1 of a square canvas: cell aspect 0.5; photo 1:1.
      c.frameOnFocus('A', const Offset(0.25, 0.5), 1);
      expect(c.fillFor('A')!.offsetX, closeTo(-1, 1e-9));
      c.dispose();
    });
  });

  group('model', () {
    test('mask, frame style and video flag survive JSON', () {
      final back = SlotFill.fromJson(
        SlotFill(assetId: 'v', mask: 'heart', frameStyle: FrameStyle.polaroid, isVideo: true).toJson(),
      );
      expect(back.mask, 'heart');
      expect(back.frameStyle, FrameStyle.polaroid);
      expect(back.isVideo, isTrue);
      final plain = SlotFill(assetId: 'p').toJson();
      expect(plain.containsKey('mask'), isFalse);
      expect(plain.containsKey('video'), isFalse);
    });

    test('A4 ratios are print canvases', () {
      expect(CanvasRatio.a4.isPrint, isTrue);
      expect(CanvasRatio.a4Landscape.isPrint, isTrue);
      expect(CanvasRatio.square.isPrint, isFalse);
      expect(CanvasRatio.byLabel('A4'), CanvasRatio.a4);
    });
  });

  group('export helpers', () {
    test('splitGrid returns tiles in posting order', () {
      final src = img.Image(width: 300, height: 300);
      // Mark the bottom-right tile so we can find it first.
      img.fillRect(src, x1: 200, y1: 200, x2: 299, y2: 299, color: img.ColorRgb8(255, 0, 0));
      final tiles = splitGrid(img.encodePng(src), 3, 3, ExportFormat.png);
      expect(tiles, hasLength(9));
      final first = img.decodePng(tiles.first)!;
      expect(first.width, 100);
      expect(first.getPixel(50, 50).r, 255);
    });

    test('cropRgba keeps the top-left rows', () {
      final rgba = Uint8List.fromList(List.generate(4 * 3 * 2, (i) => i)); // 3×2
      final out = cropRgba(rgba, 3, 2, 2);
      expect(out.length, 2 * 2 * 4);
      expect(out.sublist(0, 8), rgba.sublist(0, 8));
      expect(out.sublist(8, 16), rgba.sublist(12, 20));
    });

    test('buildPdf makes a PDF with one page per image', () async {
      final png = img.encodePng(img.Image(width: 20, height: 10));
      final pdf = await buildPdf([png, png], a4: true);
      expect(String.fromCharCodes(pdf.sublist(0, 4)), '%PDF');
    });
  });

  group('photo books', () {
    late Directory tmp;
    late BookService books;

    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('collage_books_');
      books = BookService(baseDir: () async => tmp);
    });

    tearDown(() async {
      if (await tmp.exists()) await tmp.delete(recursive: true);
    });

    test('save, list and delete keep page order', () async {
      await books.save(PhotoBook(id: 'b1', title: 'Summer', collageIds: ['c2', 'c1'], updatedAt: 0));
      final list = await books.list();
      expect(list.single.title, 'Summer');
      expect(list.single.collageIds, ['c2', 'c1']);
      await books.delete('b1');
      expect(await books.list(), isEmpty);
    });
  });
}
