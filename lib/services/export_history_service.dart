import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';

import '../models/export_record.dart';

/// Keeps the list of finished exports on disk: `exports/history.json` plus a
/// small JPEG preview per entry. Only the app's own bookkeeping lives here;
/// the exported files themselves stay wherever they were saved.
class ExportHistoryService {
  ExportHistoryService({Future<Directory> Function()? root}) : _root = root ?? getApplicationSupportDirectory;

  final Future<Directory> Function() _root;

  /// Oldest entries are dropped beyond this.
  static const maxEntries = 100;
  static const thumbWidth = 240;

  Future<Directory> _dir() async {
    final d = Directory('${(await _root()).path}/exports');
    if (!await d.exists()) await d.create(recursive: true);
    return d;
  }

  Future<File> _file() async => File('${(await _dir()).path}/history.json');

  /// Newest first. A damaged file reads as an empty history.
  Future<List<ExportRecord>> list() async {
    try {
      final f = await _file();
      if (!await f.exists()) return const [];
      final raw = jsonDecode(await f.readAsString());
      if (raw is! List) return const [];
      final out = <ExportRecord>[
        for (final e in raw)
          if (e is Map<String, dynamic>)
            if (ExportRecord.fromJson(e) case final ExportRecord r) r,
      ];
      out.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return out;
    } catch (_) {
      return const [];
    }
  }

  Future<void> _write(List<ExportRecord> records) async {
    final f = await _file();
    final tmp = File('${f.path}.tmp');
    await tmp.writeAsString(jsonEncode([for (final r in records) r.toJson()]), flush: true);
    await tmp.rename(f.path);
  }

  /// Stores a small preview for [id] from PNG/JPG [bytes]; returns its path.
  Future<String?> saveThumb(String id, Uint8List bytes) async {
    try {
      final jpg = await Isolate.run(() {
        final src = img.decodeImage(bytes);
        if (src == null) return null;
        final small = src.width > thumbWidth ? img.copyResize(src, width: thumbWidth) : src;
        return img.encodeJpg(small, quality: 80);
      });
      if (jpg == null) return null;
      final f = File('${(await _dir()).path}/$id.jpg');
      await f.writeAsBytes(jpg, flush: true);
      return f.path;
    } catch (_) {
      return null;
    }
  }

  /// Adds [r] at the top and trims the list. Returns the new list.
  Future<List<ExportRecord>> add(ExportRecord r) async {
    final all = [r, ...await list()];
    final keep = all.take(maxEntries).toList();
    for (final gone in all.skip(maxEntries)) {
      await _deleteThumb(gone);
    }
    await _write(keep);
    return keep;
  }

  /// Forgets [ids] (the exported files themselves are not touched).
  Future<List<ExportRecord>> remove(Set<String> ids) async {
    final all = await list();
    final keep = <ExportRecord>[];
    for (final r in all) {
      if (ids.contains(r.id)) {
        await _deleteThumb(r);
      } else {
        keep.add(r);
      }
    }
    await _write(keep);
    return keep;
  }

  Future<void> clear() async {
    for (final r in await list()) {
      await _deleteThumb(r);
    }
    await _write(const []);
  }

  Future<void> _deleteThumb(ExportRecord r) async {
    final p = r.thumbPath;
    if (p == null) return;
    try {
      final f = File(p);
      if (await f.exists()) await f.delete();
    } catch (_) {}
  }
}
