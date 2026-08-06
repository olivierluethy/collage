import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config.dart';

class GifItem {
  const GifItem({
    required this.id,
    required this.url,
    required this.previewUrl,
    required this.aspect,
  });

  final String id;
  final String url; // animated gif
  final String previewUrl; // small still/looping preview for the grid
  final double aspect; // width / height

  factory GifItem.fromGiphy(Map<String, dynamic> j) {
    final images = j['images'] as Map<String, dynamic>;
    final full = images['downsized'] ?? images['original'];
    final prev = images['fixed_width'] ?? images['preview_gif'] ?? full;
    double dim(Map m, String k) => double.tryParse('${m[k]}') ?? 1;
    final w = dim(full as Map, 'width');
    final h = dim(full, 'height');
    return GifItem(
      id: j['id'] as String,
      url: full['url'] as String,
      previewUrl: (prev as Map)['url'] as String,
      aspect: h == 0 ? 1 : w / h,
    );
  }
}

/// Thrown when the Giphy key is missing so the UI can show a clear message.
class GiphyUnavailable implements Exception {
  const GiphyUnavailable();
}

/// GIF search + trending via the Giphy REST API. Degrades gracefully when no
/// API key is supplied.
class GiphyService {
  const GiphyService();

  static const _base = 'https://api.giphy.com/v1/gifs';

  bool get available => Config.hasGiphy;

  Future<List<GifItem>> trending({int limit = 30}) async {
    if (!available) throw const GiphyUnavailable();
    final uri = Uri.parse('$_base/trending?api_key=${Config.giphyApiKey}&limit=$limit&rating=pg');
    return _fetch(uri);
  }

  Future<List<GifItem>> search(String query, {int limit = 30}) async {
    if (!available) throw const GiphyUnavailable();
    if (query.trim().isEmpty) return trending(limit: limit);
    final uri = Uri.parse(
        '$_base/search?api_key=${Config.giphyApiKey}&q=${Uri.encodeQueryComponent(query)}&limit=$limit&rating=pg');
    return _fetch(uri);
  }

  Future<List<GifItem>> _fetch(Uri uri) async {
    final res = await http.get(uri);
    if (res.statusCode != 200) {
      throw Exception('Giphy request failed (${res.statusCode}).');
    }
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    final list = (data['data'] as List).cast<Map<String, dynamic>>();
    return list.map(GifItem.fromGiphy).toList();
  }
}
