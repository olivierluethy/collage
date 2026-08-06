import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

import '../models/collage_project.dart';

/// Persists collages to the app's documents directory so they appear in
/// "My Collages" and can be re-opened and edited later.
class DraftService {
  const DraftService();

  Future<Directory> _dir() async {
    final base = await getApplicationDocumentsDirectory();
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
        projects.add(CollageProject.fromJson(map));
      } catch (_) {
        // Skip corrupt drafts rather than crashing the library.
      }
    }
    projects.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return projects;
  }

  Future<CollageProject?> load(String id) async {
    final f = await _jsonFile(id);
    if (!await f.exists()) return null;
    return CollageProject.fromJson(
      jsonDecode(await f.readAsString()) as Map<String, dynamic>,
    );
  }

  Future<void> delete(String id) async {
    final j = await _jsonFile(id);
    final t = await _thumbFile(id);
    if (await j.exists()) await j.delete();
    if (await t.exists()) await t.delete();
  }
}
