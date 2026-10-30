import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

import '../models/collage_project.dart';

/// Persists collages to the app's documents directory so they appear in
/// "My Collages" and can be re-opened and edited later.
class DraftService {
  const DraftService({this.baseDir});

  /// Where the `collages/` folder lives. Defaults to the app documents
  /// directory; tests pass a temporary directory instead.
  final Future<Directory> Function()? baseDir;

  Future<Directory> _dir() async {
    final base = await (baseDir ?? getApplicationDocumentsDirectory)();
    final dir = Directory('${base.path}/collages');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  Future<File> _jsonFile(String id) async => File('${(await _dir()).path}/$id.json');
  Future<File> _thumbFile(String id) async => File('${(await _dir()).path}/$id.png');

  /// Save the project JSON and, if provided, a preview thumbnail.
  Future<void> save(CollageProject project, {Uint8List? thumbnail}) async {
    if (thumbnail != null) {
      final t = await _thumbFile(project.id);
      await t.writeAsBytes(thumbnail);
      project.thumbnailPath = t.path;
    }
    final f = await _jsonFile(project.id);
    await f.writeAsString(jsonEncode(project.toJson()));
  }

  Future<List<CollageProject>> list() async {
    final dir = await _dir();
    final files = dir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.json'))
        .toList();
    final projects = <CollageProject>[];
    for (final f in files) {
      try {
        final map = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
        final project = CollageProject.fromJson(map);
        // Backfill migration: a pre-v1.2 draft with no stored createdAt comes
        // back as 0. Use the JSON file's own timestamp (when the collage was
        // last written) so it still shows a sensible date, and persist it so
        // the migration only runs once.
        final schema = (map['schema'] as num?)?.toInt() ?? 1;
        if (project.createdAt == 0 || schema < collageSchemaVersion) {
          final stamp = _fileStamp(f);
          if (project.createdAt == 0) project.createdAt = stamp;
          if (project.updatedAt == 0) project.updatedAt = stamp;
          await save(project); // re-writes with the current schema version
        }
        projects.add(project);
      } catch (_) {
        // Skip corrupt drafts rather than crashing the library.
      }
    }
    projects.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return projects;
  }

  /// The file's last-modified time in epoch millis, used to backfill a missing
  /// createdAt for pre-v1.2 drafts. Falls back to "now" if unavailable.
  int _fileStamp(File f) {
    try {
      return f.lastModifiedSync().millisecondsSinceEpoch;
    } catch (_) {
      return DateTime.now().millisecondsSinceEpoch;
    }
  }

  Future<CollageProject?> load(String id) async {
    final f = await _jsonFile(id);
    if (!await f.exists()) return null;
    return CollageProject.fromJson(
      jsonDecode(await f.readAsString()) as Map<String, dynamic>,
    );
  }

  /// Rename a saved collage in place.
  Future<void> rename(String id, String title) async {
    final p = await load(id);
    if (p == null) return;
    p.title = title;
    p.updatedAt = DateTime.now().millisecondsSinceEpoch;
    await save(p);
  }

  /// Copy a saved collage (JSON and thumbnail) under [newId] and [title].
  /// Returns the copy, or null if the original is gone.
  Future<CollageProject?> duplicate(String id, {required String newId, required String title}) async {
    final f = await _jsonFile(id);
    if (!await f.exists()) return null;
    final j = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
    final now = DateTime.now().millisecondsSinceEpoch;
    j
      ..['id'] = newId
      ..['title'] = title
      ..['createdAt'] = now
      ..['updatedAt'] = now
      ..['thumbnailPath'] = null;
    final copy = CollageProject.fromJson(j);
    final thumb = await _thumbFile(id);
    final bytes = await thumb.exists() ? await thumb.readAsBytes() : null;
    await save(copy, thumbnail: bytes);
    return copy;
  }

  // ---- full-size renders (for photo books) --------------------------------
  /// Keep the last full-size export of a collage (PNG or JPG), so photo books
  /// can print it without re-rendering.
  Future<void> saveRender(String id, Uint8List bytes, String ext) async {
    final dir = await _dir();
    for (final old in ['png', 'jpg']) {
      final f = File('${dir.path}/$id.render.$old');
      if (await f.exists()) await f.delete();
    }
    await File('${dir.path}/$id.render.$ext').writeAsBytes(bytes);
  }

  /// The saved full-size render of a collage, else its thumbnail, else null.
  Future<Uint8List?> renderOf(String id) async {
    final dir = await _dir();
    for (final name in ['$id.render.png', '$id.render.jpg', '$id.png']) {
      final f = File('${dir.path}/$name');
      if (await f.exists()) return f.readAsBytes();
    }
    return null;
  }

  // ---- trash ----------------------------------------------------------------
  /// How long a deleted collage stays restorable.
  static const trashDays = 30;

  Future<Directory> _trashDir() async {
    final base = await (baseDir ?? getApplicationDocumentsDirectory)();
    final dir = Directory('${base.path}/collages_trash');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  /// Move a collage to the trash. It can be restored for [trashDays] days.
  Future<void> delete(String id) async {
    final j = await _jsonFile(id);
    final t = await _thumbFile(id);
    if (!await j.exists()) {
      if (await t.exists()) await t.delete();
      return;
    }
    final trash = await _trashDir();
    final map = jsonDecode(await j.readAsString()) as Map<String, dynamic>;
    map['deletedAt'] = DateTime.now().millisecondsSinceEpoch;
    if (await t.exists()) {
      final moved = await t.rename('${trash.path}/$id.png');
      map['thumbnailPath'] = moved.path;
    }
    await File('${trash.path}/$id.json').writeAsString(jsonEncode(map));
    await j.delete();
  }

  /// Trashed collages, most recently deleted first, each with its deletion
  /// time. Anything older than [trashDays] is purged on the way.
  Future<List<(CollageProject, int)>> listTrash() async {
    final trash = await _trashDir();
    final cutoff = DateTime.now()
        .subtract(const Duration(days: trashDays))
        .millisecondsSinceEpoch;
    final out = <(CollageProject, int)>[];
    for (final f in trash.listSync().whereType<File>().where((f) => f.path.endsWith('.json'))) {
      try {
        final map = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
        final deletedAt = (map['deletedAt'] as num?)?.toInt() ?? 0;
        final project = CollageProject.fromJson(map);
        if (deletedAt < cutoff) {
          await _purge(project.id);
          continue;
        }
        out.add((project, deletedAt));
      } catch (_) {
        // Skip unreadable entries.
      }
    }
    out.sort((a, b) => b.$2.compareTo(a.$2));
    return out;
  }

  /// Put a trashed collage back into "My Collages".
  Future<void> restore(String id) async {
    final trash = await _trashDir();
    final j = File('${trash.path}/$id.json');
    if (!await j.exists()) return;
    final map = jsonDecode(await j.readAsString()) as Map<String, dynamic>..remove('deletedAt');
    final project = CollageProject.fromJson(map);
    final t = File('${trash.path}/$id.png');
    final thumb = await t.exists() ? await t.readAsBytes() : null;
    project.thumbnailPath = null;
    await save(project, thumbnail: thumb);
    await _purge(id);
  }

  /// Delete a trashed collage for good.
  Future<void> deleteForever(String id) => _purge(id);

  Future<void> emptyTrash() async {
    final trash = await _trashDir();
    for (final f in trash.listSync().whereType<File>().where((f) => f.path.endsWith('.json'))) {
      final id = f.uri.pathSegments.last.replaceAll('.json', '');
      await _purge(id);
    }
    if (await trash.exists()) await trash.delete(recursive: true);
  }

  Future<void> _purge(String id) async {
    final trash = await _trashDir();
    final dir = await _dir();
    for (final f in [
      File('${trash.path}/$id.json'),
      File('${trash.path}/$id.png'),
      // The full-size render stays beside the drafts until the collage is gone.
      File('${dir.path}/$id.render.png'),
      File('${dir.path}/$id.render.jpg'),
    ]) {
      if (await f.exists()) await f.delete();
    }
  }
}
