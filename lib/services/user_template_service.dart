import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

import '../models/canvas_element.dart';
import '../models/collage_project.dart';

/// The user's own templates: a collage's design (layout, ratio, borders,
/// background, text, stickers) saved without its photos, ready to fill with
/// new ones. Stored next to the drafts as JSON plus a preview thumbnail.
class UserTemplateService {
  const UserTemplateService({this.baseDir});

  /// Defaults to the app documents directory; tests pass a temp directory.
  final Future<Directory> Function()? baseDir;

  Future<Directory> _dir() async {
    final base = await (baseDir ?? getApplicationDocumentsDirectory)();
    final dir = Directory('${base.path}/user_templates');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  /// Save [project]'s design as a template named [name]. Photos are dropped:
  /// slot fills, free photos and a photo background (which falls back to a
  /// solid colour).
  Future<CollageProject> saveFrom(
    CollageProject project, {
    required String id,
    required String name,
    Uint8List? thumbnail,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final j = project.toJson()
      ..['id'] = id
      ..['title'] = name
      ..['createdAt'] = now
      ..['updatedAt'] = now
      ..['fills'] = <String, dynamic>{}
      ..['thumbnailPath'] = null;
    final template = CollageProject.fromJson(j);
    template.elements.removeWhere((e) => e is ImageElement);
    if (template.background.kind == BackgroundKind.image) {
      template.background
        ..kind = BackgroundKind.solid
        ..imageAssetId = null;
    }
    final dir = await _dir();
    if (thumbnail != null) {
      final t = File('${dir.path}/$id.png');
      await t.writeAsBytes(thumbnail);
      template.thumbnailPath = t.path;
    }
    await File('${dir.path}/$id.json').writeAsString(jsonEncode(template.toJson()));
    return template;
  }

  /// Saved templates, newest first.
  Future<List<CollageProject>> list() async {
    final dir = await _dir();
    final out = <CollageProject>[];
    for (final f in dir.listSync().whereType<File>().where((f) => f.path.endsWith('.json'))) {
      try {
        out.add(CollageProject.fromJson(jsonDecode(await f.readAsString()) as Map<String, dynamic>));
      } catch (_) {
        // Skip unreadable templates.
      }
    }
    out.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return out;
  }

  Future<void> delete(String id) async {
    final dir = await _dir();
    for (final f in [File('${dir.path}/$id.json'), File('${dir.path}/$id.png')]) {
      if (await f.exists()) await f.delete();
    }
  }

  /// A fresh, editable collage built from [template].
  static CollageProject instantiate(CollageProject template, {required String id}) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final j = template.toJson()
      ..['id'] = id
      ..['createdAt'] = now
      ..['updatedAt'] = now
      ..['thumbnailPath'] = null;
    return CollageProject.fromJson(j);
  }
}
