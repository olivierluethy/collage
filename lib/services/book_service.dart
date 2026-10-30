import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// A photo book: an ordered list of saved collages, one per page.
class PhotoBook {
  PhotoBook({
    required this.id,
    required this.title,
    required this.collageIds,
    required this.updatedAt,
  });

  final String id;
  String title;
  List<String> collageIds;
  int updatedAt;

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'pages': collageIds,
        'updatedAt': updatedAt,
      };

  factory PhotoBook.fromJson(Map<String, dynamic> j) => PhotoBook(
        id: j['id'] as String,
        title: j['title'] as String,
        collageIds: (j['pages'] as List).cast<String>(),
        updatedAt: (j['updatedAt'] as num?)?.toInt() ?? 0,
      );
}

/// Stores photo books as JSON next to the drafts.
class BookService {
  const BookService({this.baseDir});

  /// Defaults to the app documents directory; tests pass a temp directory.
  final Future<Directory> Function()? baseDir;

  Future<Directory> _dir() async {
    final base = await (baseDir ?? getApplicationDocumentsDirectory)();
    final dir = Directory('${base.path}/books');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  Future<List<PhotoBook>> list() async {
    final dir = await _dir();
    final out = <PhotoBook>[];
    for (final f in dir.listSync().whereType<File>().where((f) => f.path.endsWith('.json'))) {
      try {
        out.add(PhotoBook.fromJson(jsonDecode(await f.readAsString()) as Map<String, dynamic>));
      } catch (_) {
        // Skip unreadable books.
      }
    }
    out.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return out;
  }

  Future<void> save(PhotoBook book) async {
    book.updatedAt = DateTime.now().millisecondsSinceEpoch;
    final dir = await _dir();
    await File('${dir.path}/${book.id}.json').writeAsString(jsonEncode(book.toJson()));
  }

  Future<void> delete(String id) async {
    final f = File('${(await _dir()).path}/$id.json');
    if (await f.exists()) await f.delete();
  }
}
