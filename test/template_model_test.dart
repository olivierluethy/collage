import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:collage/data/template_catalog.dart';
import 'package:collage/models/canvas_element.dart';
import 'package:collage/models/collage_project.dart';
import 'package:collage/models/collage_template.dart';

void main() {
  group('CollageTemplate.toProject', () {
    test('carries ratio, layout, border and background across', () {
      final t = TemplateCatalog.forBucket(4, TemplateStyle.birthday).first;
      final p = t.toProject(id: 'p1', now: 123);

      expect(p.ratioLabel, t.ratioLabel);
      expect(p.layout.id, t.layout.id);
      expect(p.layout.slots.isNotEmpty, isTrue);
      expect(p.fills, isEmpty);
      expect(p.background.kind, t.background.kind);
      expect(p.border.gap, t.border.gap);
      expect(p.createdAt, 123);
      expect(p.updatedAt, 123);
    });

    test('clones decorations so editing a project never mutates the catalog',
        () {
      final t = TemplateCatalog.forBucket(3, TemplateStyle.social).first;
      final originalText = (t.elements.firstWhere((e) => e is TextElement) as TextElement).text;

      final p = t.toProject(id: 'p1', now: 1);
      (p.elements.firstWhere((e) => e is TextElement) as TextElement).text = 'edited';

      expect(
        (t.elements.firstWhere((e) => e is TextElement) as TextElement).text,
        originalText,
      );
    });

    test('project survives a JSON round-trip with its decorations', () {
      final t = TemplateCatalog.forBucket(6, TemplateStyle.winter).last;
      final p = t.toProject(id: 'p1', now: 1);

      final back = CollageProject.fromJson(
        jsonDecode(jsonEncode(p.toJson())) as Map<String, dynamic>,
      );

      expect(back.id, 'p1');
      expect(back.ratioLabel, t.ratioLabel);
      expect(back.elements.length, p.elements.length);
      expect(back.layout.slots.length, t.photoCount);
      expect(back.background.kind, t.background.kind);
    });
  });
}
