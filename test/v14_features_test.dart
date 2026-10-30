import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'package:collage/features/editor/editor_controller.dart';
import 'package:collage/models/canvas_element.dart';
import 'package:collage/models/collage_project.dart';
import 'package:collage/models/layout_template.dart';
import 'package:collage/models/photo_filter.dart';
import 'package:collage/services/export_service.dart';
import 'package:collage/services/user_template_service.dart';

CollageProject _project() => CollageProject(
      id: 'p1',
      title: 'Trip',
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
        ImageElement(id: 'img', cx: 0.5, cy: 0.5, assetId: 'a2'),
        EmojiElement(id: 'em', cx: 0.5, cy: 0.5, emoji: '🙂'),
      ],
      border: BorderSettings(),
      background: BackgroundSettings(kind: BackgroundKind.image, imageAssetId: 'a3', imageBlur: 8),
    );

void main() {
  group('model round-trips', () {
    test('slot frame, shadow and vignette survive JSON', () {
      final f = SlotFill(
        assetId: 'a',
        frameWidth: 6,
        frameColor: const Color(0xFF112233),
        shadow: true,
        filter: PhotoFilter(vignette: 0.4),
      );
      final back = SlotFill.fromJson(f.toJson());
      expect(back.frameWidth, 6);
      expect(back.frameColor, const Color(0xFF112233));
      expect(back.shadow, isTrue);
      expect(back.filter.vignette, 0.4);
      expect(back.filter.isIdentity, isFalse);
      expect(back.filter.isColorIdentity, isTrue);
    });

    test('sharpen survives JSON and needs no colour matrix', () {
      final back = PhotoFilter.fromJson(PhotoFilter(sharpen: 0.6).toJson());
      expect(back.sharpen, 0.6);
      expect(back.isIdentity, isFalse);
      expect(back.isColorIdentity, isTrue);
      back.resetAdjustments();
      expect(back.isIdentity, isTrue);
    });

    test('background blur survives JSON', () {
      final back = BackgroundSettings.fromJson(BackgroundSettings(imageBlur: 12).toJson());
      expect(back.imageBlur, 12);
    });

    test('curved gradient text survives JSON', () {
      final t = TextElement(
        id: 't',
        cx: 0.5,
        cy: 0.5,
        text: 'Hi',
        color: const Color(0xFFFFFFFF),
        curve: -0.5,
        gradientEnd: const Color(0xFFFF0000),
      );
      final back = CanvasElement.fromJson(t.toJson()) as TextElement;
      expect(back.curve, -0.5);
      expect(back.gradientEnd, const Color(0xFFFF0000));
    });

    test('drawing survives JSON', () {
      final d = DrawingElement(
        id: 'd',
        cx: 0.4,
        cy: 0.6,
        widthFrac: 0.3,
        boxAspect: 2,
        strokes: [
          DrawStroke(points: const [Offset(0, 0), Offset(0.5, 1)], color: const Color(0xFF00FF00), width: 0.05),
        ],
      );
      final back = CanvasElement.fromJson(d.toJson()) as DrawingElement;
      expect(back.widthFrac, 0.3);
      expect(back.aspectRatio, 2);
      expect(back.strokes.single.points, const [Offset(0, 0), Offset(0.5, 1)]);
      expect(back.strokes.single.color, const Color(0xFF00FF00));
    });
  });

  group('carousel', () {
    test('only whole-number wide ratios split into slides', () {
      expect(CanvasRatio.carousel2.carouselSlides, 2);
      expect(CanvasRatio.carousel3.carouselSlides, 3);
      expect(CanvasRatio.wide.carouselSlides, 1);
      expect(CanvasRatio.square.carouselSlides, 1);
    });

    test('splitCarousel cuts an image into equal slides', () {
      final src = img.Image(width: 300, height: 100);
      final pieces = splitCarousel(img.encodePng(src), 3, ExportFormat.png);
      expect(pieces, hasLength(3));
      for (final p in pieces) {
        final d = img.decodePng(p)!;
        expect(d.width, 100);
        expect(d.height, 100);
      }
    });
  });

  group('drawing mode', () {
    test('finished strokes become one element fitted to their bounds', () {
      final c = EditorController(project: _project(), pool: const ['a1']);
      final before = c.project.elements.length;
      c.startDrawing();
      c.setDrawStyle(width: 0.01);
      c.beginStroke(const Offset(0.2, 0.2));
      c.extendStroke(const Offset(0.4, 0.3));
      c.finishDrawing(const Size(1000, 1000));
      expect(c.drawing, isFalse);
      expect(c.draftStrokes, isEmpty);
      expect(c.project.elements.length, before + 1);
      final d = c.project.elements.last as DrawingElement;
      expect(d.cx, closeTo(0.3, 1e-9));
      expect(d.cy, closeTo(0.25, 1e-9));
      // Box is the stroke bounds plus half the brush width on every side.
      expect(d.widthFrac, closeTo(0.21, 1e-9));
      expect(c.selectedElementId, d.id);
      c.dispose();
    });

    test('finishing without strokes adds nothing', () {
      final c = EditorController(project: _project(), pool: const ['a1']);
      final before = c.project.elements.length;
      c.startDrawing();
      c.finishDrawing(const Size(1000, 1000));
      expect(c.project.elements.length, before);
      c.dispose();
    });
  });

  group('user templates', () {
    late Directory tmp;
    late UserTemplateService templates;

    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('collage_templates_');
      templates = UserTemplateService(baseDir: () async => tmp);
    });

    tearDown(() async {
      if (await tmp.exists()) await tmp.delete(recursive: true);
    });

    test('saving drops photos but keeps the design', () async {
      final t = await templates.saveFrom(
        _project(),
        id: 't1',
        name: 'Summer',
        thumbnail: Uint8List.fromList([1, 2]),
      );
      expect(t.title, 'Summer');
      expect(t.fills, isEmpty);
      expect(t.elements.whereType<ImageElement>(), isEmpty);
      expect(t.elements.whereType<EmojiElement>(), hasLength(1));
      expect(t.background.kind, BackgroundKind.solid);
      expect(t.background.imageAssetId, isNull);

      final listed = await templates.list();
      expect(listed.single.id, 't1');
      expect(await File(listed.single.thumbnailPath!).readAsBytes(), [1, 2]);
    });

    test('instantiate makes a fresh project and delete removes the template', () async {
      final t = await templates.saveFrom(_project(), id: 't1', name: 'Summer');
      final p = UserTemplateService.instantiate(t, id: 'new');
      expect(p.id, 'new');
      expect(p.title, 'Summer');
      expect(p.thumbnailPath, isNull);

      await templates.delete('t1');
      expect(await templates.list(), isEmpty);
    });
  });
}
