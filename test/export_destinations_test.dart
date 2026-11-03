import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:collage/models/export_record.dart';
import 'package:collage/services/export_destination_service.dart';
import 'package:collage/services/export_history_service.dart';
import 'package:collage/services/export_service.dart';
import 'package:collage/services/gallery_service.dart';
import 'package:collage/services/prefs_service.dart';
import 'package:collage/services/reminder_service.dart';
import 'package:collage/state/exports.dart';
import 'package:collage/state/occasions.dart';
import 'package:collage/state/providers.dart';

ExportRecord _record(String id, {String project = 'p1', DateTime? at, String? thumb}) => ExportRecord(
      id: id,
      projectId: project,
      projectTitle: 'Summer',
      createdAt: at ?? DateTime(2026, 11, 3, 14, 12),
      format: 'png',
      fileName: 'Summer 2026-11-03 14.12.png',
      target: ExportTarget.folder,
      locationLabel: 'Internal storage/Pictures/Prints',
      ref: 'content://com.android.externalstorage.documents/tree/primary%3APictures/document/x',
      mimeType: 'image/png',
      thumbPath: thumb,
      byteSize: 1234,
    );

void main() {
  group('file names', () {
    test('built from title and time, safe for every file system', () {
      final at = DateTime(2026, 11, 3, 9, 5);
      expect(exportFileName('Summer in Bern', at, 'png'), 'Summer in Bern 2026-11-03 09.05.png');
      expect(exportFileName('a/b:c*?"<>|', at, 'jpg'), 'a b c 2026-11-03 09.05.jpg');
      expect(exportFileName('   ', at, 'pdf'), 'Collage 2026-11-03 09.05.pdf');
      expect(exportFileName('...hidden', at, 'png'), 'hidden 2026-11-03 09.05.png');
      expect(exportFileName('Trip', at, 'png', suffix: 'slide 2'), 'Trip 2026-11-03 09.05 slide 2.png');
      expect(exportFileName('x' * 200, at, 'png').length, lessThan(90));
    });

    test('collisions get a number instead of overwriting', () {
      expect(uniqueFileName('a.png', {}), 'a.png');
      expect(uniqueFileName('a.png', {'a.png'}), 'a (2).png');
      expect(uniqueFileName('a.png', {'A.PNG', 'a (2).png'}), 'a (3).png');
      expect(uniqueFileName('noext', {'noext'}), 'noext (2)');
    });
  });

  group('export record', () {
    test('survives a JSON round trip', () {
      final r = _record('1', thumb: '/t/1.jpg');
      final back = ExportRecord.fromJson(r.toJson())!;
      expect(back.id, r.id);
      expect(back.projectId, r.projectId);
      expect(back.createdAt, r.createdAt);
      expect(back.target, ExportTarget.folder);
      expect(back.locationLabel, r.locationLabel);
      expect(back.ref, r.ref);
      expect(back.thumbPath, '/t/1.jpg');
      expect(back.byteSize, 1234);
    });

    test('broken entries are skipped, unknown targets fall back', () {
      expect(ExportRecord.fromJson({'ref': 'x'}), isNull);
      expect(ExportRecord.fromJson({'id': '1', 'ref': 'x', 'target': '??'})!.target, ExportTarget.gallery);
    });
  });

  group('export history', () {
    late Directory dir;
    late ExportHistoryService svc;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('exports_test');
      svc = ExportHistoryService(root: () async => dir);
    });
    tearDown(() => dir.delete(recursive: true));

    test('is empty at first and keeps entries newest first', () async {
      expect(await svc.list(), isEmpty);
      await svc.add(_record('old', at: DateTime(2026, 1, 1)));
      await svc.add(_record('new', at: DateTime(2026, 6, 1)));
      final list = await svc.list();
      expect(list.map((r) => r.id), ['new', 'old']);
    });

    test('persists across instances (app restarts)', () async {
      await svc.add(_record('a'));
      final again = ExportHistoryService(root: () async => dir);
      expect((await again.list()).single.id, 'a');
    });

    test('forget and clear only touch the list and previews', () async {
      final thumb = File('${dir.path}/thumb.jpg')..writeAsBytesSync([1, 2, 3]);
      await svc.add(_record('a', thumb: thumb.path));
      await svc.add(_record('b'));
      await svc.remove({'a'});
      expect((await svc.list()).map((r) => r.id), ['b']);
      expect(thumb.existsSync(), isFalse);
      await svc.clear();
      expect(await svc.list(), isEmpty);
    });

    test('is capped, dropping the oldest', () async {
      for (var i = 0; i < ExportHistoryService.maxEntries + 5; i++) {
        await svc.add(_record('$i', at: DateTime(2026, 1, 1).add(Duration(minutes: i))));
      }
      final list = await svc.list();
      expect(list.length, ExportHistoryService.maxEntries);
      expect(list.first.id, '${ExportHistoryService.maxEntries + 4}');
    });

    test('a damaged file reads as empty instead of failing', () async {
      await svc.add(_record('a'));
      File('${dir.path}/exports/history.json').writeAsStringSync('{not json');
      expect(await svc.list(), isEmpty);
    });
  });

  group('destination settings', () {
    late PrefsService prefs;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      prefs = await PrefsService.create();
    });

    ProviderContainer container() {
      final c = ProviderContainer(overrides: [prefsProvider.overrideWithValue(prefs)]);
      addTearDown(c.dispose);
      return c;
    }

    test('defaults to the recommended place', () {
      final d = container().read(exportDestinationProvider);
      expect(d.mode, ExportDestinationMode.system);
      expect(d.hasFolder, isFalse);
    });

    test('"ask every time" is persisted across restarts', () async {
      final c1 = container();
      await c1.read(exportDestinationProvider.notifier).setMode(ExportDestinationMode.ask);
      expect(prefs.getString(PrefsService.kExportDestination), 'ask');
      expect(container().read(exportDestinationProvider).mode, ExportDestinationMode.ask);
    });

    test('folder mode without a usable folder falls back to recommended', () async {
      SharedPreferences.setMockInitialValues({PrefsService.kExportDestination: 'folder'});
      prefs = await PrefsService.create();
      expect(container().read(exportDestinationProvider).mode, ExportDestinationMode.system);
    });

    test('folder mode cannot be chosen before a folder is picked', () async {
      final c = container();
      await c.read(exportDestinationProvider.notifier).setMode(ExportDestinationMode.folder);
      expect(c.read(exportDestinationProvider).mode, ExportDestinationMode.system);
    });

    test('reset forgets the folder', () async {
      SharedPreferences.setMockInitialValues({
        PrefsService.kExportDestination: 'ask',
        PrefsService.kExportFolderUri: 'content://tree/x',
        PrefsService.kExportFolderLabel: 'Drive/Prints',
      });
      prefs = await PrefsService.create();
      final c = container();
      await c.read(exportDestinationProvider.notifier).reset();
      expect(c.read(exportDestinationProvider).hasFolder, isFalse);
      expect(prefs.getString(PrefsService.kExportFolderUri), isNull);
      expect(prefs.getString(PrefsService.kExportDestination), isNull);
    });
  });

  group('routing', () {
    final svc = ExportDestinationService(const GalleryService());

    test('pictures and videos go to the gallery by default', () {
      const d = ExportDestination();
      expect(svc.targetFor(d, ExportFormat.png), ExportTarget.gallery);
      expect(svc.targetFor(d, ExportFormat.mp4), ExportTarget.gallery);
    });

    test('PDFs go to a visible documents place, never the gallery', () {
      expect(svc.targetFor(const ExportDestination(), ExportFormat.pdf), isNot(ExportTarget.gallery));
    });

    test('"ask" always opens the save dialog', () {
      const d = ExportDestination(mode: ExportDestinationMode.ask);
      for (final f in ExportFormat.values) {
        expect(svc.targetFor(d, f), ExportTarget.picked);
      }
    });

    test('a folder setting without a folder never writes to a made-up place', () {
      const d = ExportDestination(mode: ExportDestinationMode.folder);
      expect(svc.targetFor(d, ExportFormat.png), ExportTarget.gallery);
    });

    test('the tree of a folder export is recovered from its document URI', () {
      final r = _record('1');
      expect(svc.folderOf(r), 'content://com.android.externalstorage.documents/tree/primary%3APictures');
    });
  });

  group('notification preferences', () {
    late PrefsService prefs;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      prefs = await PrefsService.create();
    });

    test('every proactive notification is off by default; in-app suggestions on', () {
      final c = ProviderContainer(overrides: [prefsProvider.overrideWithValue(prefs)]);
      addTearDown(c.dispose);
      final p = c.read(occasionPrefsProvider);
      expect(p.remindersOn, isFalse);
      expect(p.remindMemories, isFalse);
      expect(p.notifyExports, isFalse);
      expect(p.discoverSuggestions, isTrue);
    });

    test('new switches are persisted', () {
      final c = ProviderContainer(overrides: [prefsProvider.overrideWithValue(prefs)]);
      addTearDown(c.dispose);
      c.read(occasionPrefsProvider.notifier)
        ..setRemindMemories(true)
        ..setNotifyExports(true)
        ..setDiscoverSuggestions(false);
      final c2 = ProviderContainer(overrides: [prefsProvider.overrideWithValue(prefs)]);
      addTearDown(c2.dispose);
      final p = c2.read(occasionPrefsProvider);
      expect(p.remindMemories, isTrue);
      expect(p.notifyExports, isTrue);
      expect(p.discoverSuggestions, isFalse);
    });
  });

  group('memory reminders', () {
    test('fire on the day itself, outside quiet hours', () {
      final now = DateTime(2026, 11, 3, 8);
      final plan = ReminderPlanner.plan(
        now: now,
        upcoming: const [],
        memories: [MemoryDate(date: DateTime(2026, 11, 5), yearsAgo: 2, photos: 9)],
        frequency: ReminderFrequency.weekly2,
        quietStart: 21 * 60,
        quietEnd: 11 * 60,
      );
      expect(plan.single.memory, isNotNull);
      expect(plan.single.fireAt, DateTime(2026, 11, 5, 11));
    });

    test('share the frequency limit with everything else', () {
      final now = DateTime(2026, 11, 3, 8);
      final plan = ReminderPlanner.plan(
        now: now,
        upcoming: const [],
        memories: [
          for (var d = 4; d < 10; d++) MemoryDate(date: DateTime(2026, 11, d), yearsAgo: 1, photos: 10),
        ],
        frequency: ReminderFrequency.weekly1,
        quietStart: 22 * 60,
        quietEnd: 7 * 60,
      );
      expect(plan.length, 1);
    });
  });
}
