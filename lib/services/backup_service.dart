import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive_io.dart';
import 'package:path_provider/path_provider.dart';
import 'package:photo_manager/photo_manager.dart';

import '../models/canvas_element.dart';
import '../models/collage_project.dart';
import 'draft_service.dart';

/// What a restore brought back.
class RestoreSummary {
  const RestoreSummary({required this.collages, required this.photos});
  final int collages;
  final int photos; // photos that had to be re-added to the gallery
}

class BackupFormatException implements Exception {
  const BackupFormatException();
}

/// Backs up every saved collage to a single .zip the user can keep anywhere
/// (Google Drive, a computer, …) and restores it on this or another phone.
///
/// The archive holds each collage's JSON and thumbnail plus the original
/// photos it uses, because gallery ids differ between devices. On restore,
/// photos still present in the gallery are reused; missing ones are saved
/// back to the gallery and the collages are rewritten to the new ids.
class BackupService {
  const BackupService(this.drafts);

  final DraftService drafts;

  static const _format = 1;

  /// Write a backup archive to a temporary file and return it.
  Future<File> create() async {
    final projects = await drafts.list();
    final tmp = await getTemporaryDirectory();
    final stamp = DateTime.now().toIso8601String().substring(0, 10);
    final path = '${tmp.path}/collage-backup-$stamp.zip';
    final zip = ZipFileEncoder()..create(path);

    final photoNames = <String, String>{}; // assetId -> file name in archive
    for (final p in projects) {
      for (final id in _assetIds(p)) {
        if (photoNames.containsKey(id)) continue;
        final asset = await AssetEntity.fromId(id);
        final file = await asset?.originFile;
        if (file == null) continue;
        final ext = file.path.contains('.') ? file.path.split('.').last.toLowerCase() : 'jpg';
        final name = 'photos/${photoNames.length}.$ext';
        await zip.addFile(file, name);
        photoNames[id] = name;
      }
      zip.addArchiveFile(ArchiveFile.string('collages/${p.id}.json', jsonEncode(p.toJson())));
      final thumb = p.thumbnailPath == null ? null : File(p.thumbnailPath!);
      if (thumb != null && await thumb.exists()) {
        await zip.addFile(thumb, 'collages/${p.id}.png');
      }
    }
    zip.addArchiveFile(ArchiveFile.string(
      'manifest.json',
      jsonEncode({
        'format': _format,
        'created': DateTime.now().millisecondsSinceEpoch,
        'photos': photoNames,
      }),
    ));
    await zip.close();
    return File(path);
  }

  /// Restore every collage from a backup archive's [bytes]. Existing collages
  /// with the same id are overwritten by the backed-up version.
  Future<RestoreSummary> restore(Uint8List bytes) async {
    final archive = ZipDecoder().decodeBytes(bytes);
    final manifestFile = archive.findFile('manifest.json');
    if (manifestFile == null) throw const BackupFormatException();
    final manifest = jsonDecode(utf8.decode(manifestFile.content)) as Map<String, dynamic>;
    if ((manifest['format'] as num?)?.toInt() != _format) throw const BackupFormatException();
    final photos = (manifest['photos'] as Map<String, dynamic>).cast<String, String>();

    // Map every backed-up photo to an id that exists on this device.
    final remap = <String, String>{};
    var readded = 0;
    for (final MapEntry(key: oldId, value: name) in photos.entries) {
      if (await AssetEntity.fromId(oldId) != null) {
        remap[oldId] = oldId;
        continue;
      }
      final f = archive.findFile(name);
      if (f == null) continue;
      try {
        final saved = await PhotoManager.editor.saveImage(
          f.content,
          filename: 'collage_restored_${name.split('/').last}',
        );
        remap[oldId] = saved.id;
        readded++;
      } catch (_) {
        // Leave this photo's slots empty rather than failing the restore.
      }
    }

    var restored = 0;
    for (final f in archive.files) {
      if (!f.isFile || !f.name.startsWith('collages/') || !f.name.endsWith('.json')) continue;
      try {
        final map = jsonDecode(utf8.decode(f.content)) as Map<String, dynamic>;
        final project = CollageProject.fromJson(map)..thumbnailPath = null;
        _remapAssets(project, remap);
        final thumb = archive.findFile(f.name.replaceAll('.json', '.png'));
        await drafts.save(project, thumbnail: thumb?.content);
        restored++;
      } catch (_) {
        // Skip a damaged entry; restore the rest.
      }
    }
    return RestoreSummary(collages: restored, photos: readded);
  }

  /// Every gallery photo a collage refers to.
  static Set<String> _assetIds(CollageProject p) => {
        ...p.fills.values.map((f) => f.assetId),
        for (final e in p.elements)
          if (e is ImageElement) e.assetId,
        if (p.background.imageAssetId != null) p.background.imageAssetId!,
      };

  static void _remapAssets(CollageProject p, Map<String, String> remap) {
    for (final f in p.fills.values) {
      f.assetId = remap[f.assetId] ?? f.assetId;
    }
    p.elements = [
      for (final e in p.elements)
        if (e is ImageElement && remap.containsKey(e.assetId))
          CanvasElement.fromJson(e.toJson()..['assetId'] = remap[e.assetId])
        else
          e,
    ];
    final bg = p.background.imageAssetId;
    if (bg != null) p.background.imageAssetId = remap[bg] ?? bg;
  }
}
