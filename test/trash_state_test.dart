import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:collage/models/collage_project.dart';
import 'package:collage/models/layout_template.dart';
import 'package:collage/services/draft_service.dart';
import 'package:collage/state/providers.dart';

// Gaps not covered by draft_service_test.dart: bulk moves with exact counts,
// bulk restore (Undo), the provider layer (DraftsNotifier / TrashNotifier) and
// the trashDays boundary.

CollageProject _project(String id, {int createdAt = 1000, int updatedAt = 1000, String title = 'Trip'}) => CollageProject(
      id: id,
      title: title,
      createdAt: createdAt,
      updatedAt: updatedAt,
      ratioLabel: '4:5',
      layout: const LayoutTemplate(
        id: 'one',
        name: 'One',
        family: LayoutFamily.grid,
        slots: [LayoutSlot(id: 's1', rect: Rect.fromLTWH(0, 0, 1, 1))],
      ),
      fills: {'s1': SlotFill(assetId: 'a-$id')},
      elements: [],
      border: BorderSettings(),
      background: BackgroundSettings(),
    );

/// Counts draft service calls so tests can assert one bulk call, not N.
class _CountingDraftService extends DraftService {
  _CountingDraftService(Directory dir) : super(baseDir: () async => dir);
  int listCalls = 0, deleteManyCalls = 0, restoreManyCalls = 0, listTrashCalls = 0;

  @override
  Future<List<CollageProject>> list() {
    listCalls++;
    return super.list();
  }

  @override
  Future<void> deleteMany(Iterable<String> ids) {
    deleteManyCalls++;
    return super.deleteMany(ids);
  }

  @override
  Future<void> restoreMany(Iterable<String> ids) {
    restoreManyCalls++;
    return super.restoreMany(ids);
  }

  @override
  Future<List<(CollageProject, int)>> listTrash() {
    listTrashCalls++;
    return super.listTrash();
  }
}

Future<void> _setDeletedAt(Directory tmp, String id, DateTime when) async {
  final f = File('${tmp.path}/collages_trash/$id.json');
  final map = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
  map['deletedAt'] = when.millisecondsSinceEpoch;
  await f.writeAsString(jsonEncode(map));
}

void main() {
  late Directory tmp;
  late _CountingDraftService drafts;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('collage_trash_');
    drafts = _CountingDraftService(tmp);
  });

  tearDown(() async {
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  Future<void> seed(int n, {bool thumbs = false}) async {
    for (var i = 0; i < n; i++) {
      await drafts.save(_project('c$i', updatedAt: 1000 + i),
          thumbnail: thumbs ? Uint8List.fromList([i]) : null);
    }
  }

  group('DraftService bulk trash', () {
    test('deleteMany moves exactly the given collages, thumbnails included', () async {
      await seed(5, thumbs: true);
      await drafts.deleteMany(['c1', 'c3', 'c4']);
      expect((await drafts.list()).map((p) => p.id).toSet(), {'c0', 'c2'});
      final trash = await drafts.listTrash();
      expect(trash.length, 3);
      expect(trash.map((e) => e.$1.id).toSet(), {'c1', 'c3', 'c4'});
      for (final id in ['c1', 'c3', 'c4']) {
        expect(await File('${tmp.path}/collages/$id.png').exists(), isFalse);
        expect(await File('${tmp.path}/collages_trash/$id.png').exists(), isTrue);
      }
      // The trashed JSON points at the moved thumbnail.
      final c1 = trash.firstWhere((e) => e.$1.id == 'c1').$1;
      expect(c1.thumbnailPath, endsWith('collages_trash/c1.png'));
    });

    test('deleteMany ignores duplicates and unknown ids', () async {
      await seed(3);
      await drafts.deleteMany(['c0', 'c0', 'ghost', 'c2']);
      expect((await drafts.list()).map((p) => p.id), ['c1']);
      expect((await drafts.listTrash()).length, 2);
    });

    test('deleteMany with nothing is a no-op', () async {
      await seed(2);
      await drafts.deleteMany(const []);
      expect((await drafts.list()).length, 2);
      expect(await drafts.listTrash(), isEmpty);
    });

    test('restoreMany brings back exactly those collages with their data and thumbnails', () async {
      await seed(4, thumbs: true);
      await drafts.deleteMany(['c0', 'c1', 'c2']);
      await drafts.restoreMany(['c0', 'c2']);
      expect((await drafts.list()).map((p) => p.id).toSet(), {'c0', 'c2', 'c3'});
      expect((await drafts.listTrash()).map((e) => e.$1.id), ['c1']);
      final c2 = (await drafts.load('c2'))!;
      expect(c2.title, 'Trip');
      expect(c2.createdAt, 1000);
      expect(c2.thumbnailPath, endsWith('collages/c2.png'));
      expect(await File(c2.thumbnailPath!).readAsBytes(), [2]);
      // No deletedAt leaks back into the library JSON.
      final raw = jsonDecode(await File('${tmp.path}/collages/c2.json').readAsString()) as Map;
      expect(raw.containsKey('deletedAt'), isFalse);
    });

    test('restoreMany of ids no longer in the trash is a no-op', () async {
      await seed(1);
      await drafts.restoreMany(['ghost', 'c0']);
      expect((await drafts.list()).map((p) => p.id), ['c0']);
    });

    test('listTrash is most recently deleted first', () async {
      await seed(3);
      await drafts.deleteMany(['c0', 'c1', 'c2']);
      final now = DateTime.now();
      await _setDeletedAt(tmp, 'c0', now.subtract(const Duration(hours: 1)));
      await _setDeletedAt(tmp, 'c1', now.subtract(const Duration(days: 2)));
      await _setDeletedAt(tmp, 'c2', now.subtract(const Duration(minutes: 1)));
      expect((await drafts.listTrash()).map((e) => e.$1.id), ['c2', 'c0', 'c1']);
    });

    test('trashDays boundary: kept just inside the window, purged just outside', () async {
      await seed(3);
      await drafts.deleteMany(['c0', 'c1', 'c2']);
      final now = DateTime.now();
      await _setDeletedAt(tmp, 'c0', now.subtract(const Duration(days: DraftService.trashDays - 1)));
      await _setDeletedAt(tmp, 'c1', now.subtract(const Duration(days: DraftService.trashDays, minutes: -5)));
      await _setDeletedAt(tmp, 'c2', now.subtract(const Duration(days: DraftService.trashDays, minutes: 5)));
      expect((await drafts.listTrash()).map((e) => e.$1.id).toSet(), {'c0', 'c1'});
      expect(await File('${tmp.path}/collages_trash/c2.json').exists(), isFalse);
      // A pruned collage can no longer be restored.
      await drafts.restore('c2');
      expect((await drafts.list()).map((p) => p.id), isNot(contains('c2')));
    });

    test('a trashed entry without deletedAt is treated as expired', () async {
      await seed(1);
      await drafts.delete('c0');
      final f = File('${tmp.path}/collages_trash/c0.json');
      final map = jsonDecode(await f.readAsString()) as Map<String, dynamic>..remove('deletedAt');
      await f.writeAsString(jsonEncode(map));
      expect(await drafts.listTrash(), isEmpty);
    });

    test('the full-size render survives the trash and is removed by deleteForever', () async {
      await seed(1);
      await drafts.saveRender('c0', Uint8List.fromList([9]), 'jpg');
      await drafts.delete('c0');
      expect(await File('${tmp.path}/collages/c0.render.jpg').exists(), isTrue);
      await drafts.restore('c0');
      expect(await drafts.renderOf('c0'), [9],
          reason: 'restore() purges the trash entry; the render must not be lost with it');
    });

    test('deleteForever removes the trashed render', () async {
      await seed(1);
      await drafts.saveRender('c0', Uint8List.fromList([9]), 'png');
      await drafts.delete('c0');
      await drafts.deleteForever('c0');
      expect(await File('${tmp.path}/collages/c0.render.png').exists(), isFalse);
      expect(await drafts.listTrash(), isEmpty);
    });
  });

  group('DraftsNotifier / TrashNotifier', () {
    late ProviderContainer c;

    setUp(() {
      c = ProviderContainer(overrides: [draftServiceProvider.overrideWithValue(drafts)]);
    });

    tearDown(() => c.dispose());

    List<String> libIds() => [for (final p in c.read(draftsProvider).requireValue) p.id];

    test('removeMany updates the list in memory with exactly N removed, one bulk call, no re-read', () async {
      await seed(6);
      await c.read(draftsProvider.future);
      expect(libIds().length, 6);
      final before = drafts.listCalls;

      await c.read(draftsProvider.notifier).removeMany(['c1', 'c2', 'c5']);
      expect(libIds(), ['c4', 'c3', 'c0']); // remaining order kept
      expect(drafts.deleteManyCalls, 1);
      expect(drafts.listCalls, before, reason: 'removeMany must not re-read every draft');

      final trash = await c.read(trashProvider.future);
      expect(trash.length, 3);
      expect(trash.map((e) => e.$1.id).toSet(), {'c1', 'c2', 'c5'});
    });

    test('removeMany invalidates a trash list that was already loaded', () async {
      await seed(3);
      await c.read(draftsProvider.future);
      expect(await c.read(trashProvider.future), isEmpty);
      await c.read(draftsProvider.notifier).removeMany(['c0', 'c1']);
      expect((await c.read(trashProvider.future)).length, 2);
    });

    test('removeMany with an empty set does nothing', () async {
      await seed(2);
      await c.read(draftsProvider.future);
      await c.read(draftsProvider.notifier).removeMany(const []);
      expect(drafts.deleteManyCalls, 0);
      expect(libIds().length, 2);
    });

    test('removeMany before the library loaded falls back to a reload', () async {
      await seed(3);
      final sub = c.listen(draftsProvider, (_, __) {});
      addTearDown(sub.close);
      // Not awaited: state is still AsyncLoading.
      await c.read(draftsProvider.notifier).removeMany(['c0']);
      final ids = (await c.read(draftsProvider.future)).map((p) => p.id).toSet();
      expect(ids, {'c1', 'c2'});
    });

    test('removeMany with duplicate / unknown ids removes only real collages', () async {
      await seed(3);
      await c.read(draftsProvider.future);
      await c.read(draftsProvider.notifier).removeMany(['c0', 'c0', 'ghost']);
      expect(libIds().toSet(), {'c1', 'c2'});
      expect((await c.read(trashProvider.future)).length, 1);
    });

    test('restoreMany (Undo) restores exactly the moved collages and reloads both lists', () async {
      await seed(5);
      await c.read(draftsProvider.future);
      await c.read(draftsProvider.notifier).removeMany(['c0']);
      final moved = ['c1', 'c3', 'c4'];
      await c.read(draftsProvider.notifier).removeMany(moved);
      expect(libIds().toSet(), {'c2'});
      expect((await c.read(trashProvider.future)).length, 4);

      await c.read(trashProvider.notifier).restoreMany(moved);
      expect(drafts.restoreManyCalls, 1);
      expect(libIds().toSet(), {'c1', 'c2', 'c3', 'c4'});
      expect(c.read(trashProvider).requireValue.map((e) => e.$1.id), ['c0'],
          reason: 'the earlier, separately trashed collage stays in the trash');
    });

    test('single remove + restore round-trip through the providers', () async {
      await seed(2);
      await c.read(draftsProvider.future);
      await c.read(draftsProvider.notifier).remove('c0');
      expect(libIds(), ['c1']);
      await c.read(trashProvider.future);
      await c.read(trashProvider.notifier).restore('c0');
      expect(libIds().toSet(), {'c0', 'c1'});
      expect(c.read(trashProvider).requireValue, isEmpty);
    });

    test('empty() clears the trash; deleteForever drops one entry', () async {
      await seed(3);
      await c.read(draftsProvider.future);
      await c.read(draftsProvider.notifier).removeMany(['c0', 'c1', 'c2']);
      await c.read(trashProvider.future);
      await c.read(trashProvider.notifier).deleteForever('c1');
      expect(c.read(trashProvider).requireValue.length, 2);
      await c.read(trashProvider.notifier).empty();
      expect(c.read(trashProvider).requireValue, isEmpty);
      expect(libIds(), isEmpty);
    });
  });
}
