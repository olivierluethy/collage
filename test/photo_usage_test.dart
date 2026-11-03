import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:collage/models/collage_project.dart';
import 'package:collage/models/layout_template.dart';
import 'package:collage/services/photo_usage.dart';
import 'package:collage/state/providers.dart';

CollageProject _collage(String id, List<String> assets, {int updatedAt = 0, List<String> videos = const []}) {
  final n = assets.length + videos.length;
  final slots = [
    for (var i = 0; i < n; i++) LayoutSlot(id: 's$i', rect: Rect.fromLTWH(i / n, 0, 1 / n, 1)),
  ];
  return CollageProject(
    id: id,
    title: id,
    createdAt: 0,
    updatedAt: updatedAt,
    ratioLabel: '1:1',
    layout: LayoutTemplate(id: 'g', name: 'g', family: LayoutFamily.grid, slots: slots),
    fills: {
      for (var i = 0; i < assets.length; i++) 's$i': SlotFill(assetId: assets[i]),
      for (var i = 0; i < videos.length; i++) 's${assets.length + i}': SlotFill(assetId: videos[i], isVideo: true),
    },
    elements: [],
    border: BorderSettings(),
    background: BackgroundSettings(),
  );
}

class _FakeDrafts extends DraftsNotifier {
  _FakeDrafts(this.items);
  final List<CollageProject> items;
  @override
  Future<List<CollageProject>> build() async => items;
}

class _FakeTrash extends TrashNotifier {
  _FakeTrash(this.items);
  final List<(CollageProject, int)> items;
  @override
  Future<List<(CollageProject, int)>> build() async => items;
}

void main() {
  group('PhotoUsageIndex', () {
    final c1 = _collage('c1', ['a', 'b'], updatedAt: 100);
    final c2 = _collage('c2', ['b', 'c'], updatedAt: 300);
    final c3 = _collage('c3', ['b'], updatedAt: 200);
    final index = PhotoUsageIndex([c1, c2, c3]);

    test('empty index uses nothing', () {
      expect(PhotoUsageIndex.empty.usedAssets, isEmpty);
      expect(PhotoUsageIndex.empty.isUsed('a'), isFalse);
      expect(PhotoUsageIndex.empty.collagesUsing('a'), isEmpty);
    });

    test('isUsed and usedAssets cover every asset in any collage', () {
      expect(index.usedAssets, {'a', 'b', 'c'});
      expect(index.isUsed('a'), isTrue);
      expect(index.isUsed('z'), isFalse);
    });

    test('usage count per asset across collages, newest first', () {
      expect(index.collagesUsing('a').map((p) => p.id), ['c1']);
      expect(index.collagesUsing('b').map((p) => p.id), ['c2', 'c3', 'c1']);
      expect(index.collagesUsing('c').map((p) => p.id), ['c2']);
      expect(index.collagesUsing('z'), isEmpty);
    });

    test('a photo used twice in one collage counts that collage once', () {
      final dup = _collage('d', ['a', 'a', 'a', 'b']);
      final i = PhotoUsageIndex([dup, c2]);
      expect(i.collagesUsing('a').map((p) => p.id), ['d']);
      expect(i.collagesUsing('b').map((p) => p.id), ['c2', 'd']);
    });

    test('a collage with no photos contributes nothing', () {
      final i = PhotoUsageIndex([_collage('e', const [])]);
      expect(i.usedAssets, isEmpty);
    });

    test('videos placed in a cell count as used assets too', () {
      final i = PhotoUsageIndex([_collage('v', ['a'], videos: ['vid'])]);
      expect(i.isUsed('vid'), isTrue);
    });

    group('sameSet', () {
      test('matches collages with exactly the same photos, order ignored, newest first', () {
        final x = _collage('x', ['b', 'a'], updatedAt: 500);
        final i = PhotoUsageIndex([c1, c2, x]);
        expect(i.sameSet({'a', 'b'}).map((p) => p.id), ['x', 'c1']);
      });

      test('a subset or superset is not the same set', () {
        expect(index.sameSet({'a'}), isEmpty);
        expect(index.sameSet({'a', 'b', 'c'}), isEmpty);
      });

      test('duplicates inside a collage do not stop a match', () {
        final i = PhotoUsageIndex([_collage('d', ['a', 'b', 'a'])]);
        expect(i.sameSet({'a', 'b'}).map((p) => p.id), ['d']);
      });

      test('skips the collage being edited and never matches an empty set', () {
        expect(index.sameSet({'a', 'b'}, excludeId: 'c1'), isEmpty);
        expect(PhotoUsageIndex([_collage('e', const [])]).sameSet(const {}), isEmpty);
      });
    });
  });

  group('photoUsageProvider', () {
    test('is empty while the library is still loading', () {
      final container = ProviderContainer(overrides: [
        draftsProvider.overrideWith(() => _FakeDrafts([_collage('c1', ['a'])])),
      ]);
      addTearDown(container.dispose);
      expect(container.read(photoUsageProvider).usedAssets, isEmpty);
    });

    test('counts library collages only; trashed collages do not count', () async {
      final live = _collage('live', ['a', 'b']);
      final trashed = _collage('trashed', ['b', 't']);
      final container = ProviderContainer(overrides: [
        draftsProvider.overrideWith(() => _FakeDrafts([live])),
        trashProvider.overrideWith(() => _FakeTrash([(trashed, 0)])),
      ]);
      addTearDown(container.dispose);
      await container.read(draftsProvider.future);
      await container.read(trashProvider.future);

      final usage = container.read(photoUsageProvider);
      expect(usage.usedAssets, {'a', 'b'});
      expect(usage.isUsed('t'), isFalse);
      expect(usage.collagesUsing('b').map((p) => p.id), ['live']);
    });
  });
}
