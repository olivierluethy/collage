import 'package:flutter_test/flutter_test.dart';

import 'package:collage/data/template_catalog.dart';
import 'package:collage/models/canvas_element.dart';
import 'package:collage/models/collage_project.dart';
import 'package:collage/models/collage_template.dart';

void main() {
  final all = TemplateCatalog.all();

  group('template catalog', () {
    test('generates about a thousand templates', () {
      expect(TemplateCatalog.total, greaterThanOrEqualTo(900));
      expect(TemplateCatalog.total, lessThanOrEqualTo(1200));
    });

    test('ids are unique', () {
      final ids = all.map((t) => t.id).toSet();
      expect(ids.length, all.length);
    });

    test('every template has a layout with exactly its photo count', () {
      for (final t in all) {
        expect(t.slotCount, t.photoCount, reason: '${t.id} slot count');
        expect(t.layout.slots, isNotEmpty, reason: '${t.id} has no slots');
      }
    });

    test('every template uses a known canvas ratio', () {
      final labels = CanvasRatio.all.map((r) => r.label).toSet();
      for (final t in all) {
        expect(labels.contains(t.ratioLabel), isTrue, reason: '${t.id} ratio');
      }
    });

    test('every template carries decorative text', () {
      for (final t in all) {
        expect(t.elements.whereType<TextElement>(), isNotEmpty,
            reason: '${t.id} has no text');
      }
    });

    test('decorations stay on (or just off) the canvas', () {
      for (final t in all) {
        for (final e in t.elements) {
          expect(e.cx, inInclusiveRange(-0.1, 1.1));
          expect(e.cy, inInclusiveRange(-0.1, 1.1));
          expect(e.scale, greaterThan(0));
        }
      }
    });

    test('each photo-count × style bucket is populated', () {
      for (final n in TemplateCatalog.counts) {
        for (final s in TemplateCatalog.styles) {
          final bucket = TemplateCatalog.forBucket(n, s);
          expect(bucket, isNotEmpty, reason: '$n / ${s.name} is empty');
          for (final t in bucket) {
            expect(t.photoCount, n);
            expect(t.style, s);
          }
        }
      }
    });

    test('filtering by style only returns that style', () {
      final bucket = TemplateCatalog.forBucket(2, TemplateStyle.birthday);
      expect(bucket, isNotEmpty);
      expect(bucket.every((t) => t.style == TemplateStyle.birthday), isTrue);
    });

    test('the catalog is built once and cached', () {
      expect(identical(TemplateCatalog.all(), all), isTrue);
    });
  });
}
