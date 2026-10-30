import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:collage/models/collage_project.dart';
import 'package:collage/models/layout_template.dart';
import 'package:collage/services/draft_service.dart';

CollageProject _project(String id, {int updatedAt = 1}) => CollageProject(
      id: id,
      title: 'Trip',
      createdAt: 1,
      updatedAt: updatedAt,
      ratioLabel: '4:5',
      layout: const LayoutTemplate(
        id: 'one',
        name: 'One',
        family: LayoutFamily.grid,
        slots: [LayoutSlot(id: 's1', rect: Rect.fromLTWH(0, 0, 1, 1))],
      ),
      fills: {'s1': SlotFill(assetId: 'a1', rotation: 0.2)},
      elements: [],
      border: BorderSettings(),
      background: BackgroundSettings(),
    );

void main() {
  late Directory tmp;
  late DraftService drafts;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('collage_drafts_');
    drafts = DraftService(baseDir: () async => tmp);
  });

  tearDown(() async {
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  test('save then load round-trips the project', () async {
    await drafts.save(_project('a'));
    final back = await drafts.load('a');
    expect(back, isNotNull);
    expect(back!.title, 'Trip');
    expect(back.ratioLabel, '4:5');
    expect(back.fills['s1']!.rotation, 0.2);
  });

  test('list returns newest first and skips corrupt files', () async {
    await drafts.save(_project('old', updatedAt: 10));
    await drafts.save(_project('new', updatedAt: 20));
    await File('${tmp.path}/collages/broken.json').writeAsString('{not json');
    final list = await drafts.list();
    expect(list.map((p) => p.id), ['new', 'old']);
  });

  test('rename changes only the title', () async {
    await drafts.save(_project('a'));
    await drafts.rename('a', 'Summer');
    final back = await drafts.load('a');
    expect(back!.title, 'Summer');
    expect(back.ratioLabel, '4:5');
  });

  test('duplicate copies the project and its thumbnail under a new id', () async {
    await drafts.save(_project('a'), thumbnail: Uint8List.fromList([1, 2, 3]));
    final copy = await drafts.duplicate('a', newId: 'b', title: 'Trip copy');
    expect(copy, isNotNull);
    expect(copy!.id, 'b');
    expect(copy.title, 'Trip copy');
    expect(copy.thumbnailPath, endsWith('b.png'));
    expect(await File(copy.thumbnailPath!).readAsBytes(), [1, 2, 3]);
    expect((await drafts.list()).map((p) => p.id).toSet(), {'a', 'b'});
  });

  test('duplicate of a missing collage returns null', () async {
    expect(await drafts.duplicate('nope', newId: 'x', title: 'x'), isNull);
  });

  test('delete removes the JSON and the thumbnail', () async {
    await drafts.save(_project('a'), thumbnail: Uint8List.fromList([1]));
    await drafts.delete('a');
    expect(await drafts.load('a'), isNull);
    expect(await File('${tmp.path}/collages/a.png').exists(), isFalse);
  });
}
