import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import '../config.dart';
import '../data/fonts.dart';
import '../models/remote_catalog.dart';
import 'prefs_service.dart';

/// Loads the optional remote font and sticker catalogs and registers any extra
/// fonts so text can use them.
///
/// The catalogs are plain JSON served from a URL supplied at build time (see
/// [Config.fontCatalogUrl] / [Config.stickerCatalogUrl]). Results are cached in
/// [PrefsService] so the app has them offline after the first successful fetch,
/// and everything degrades to the bundled sets when a URL is unset or the
/// network is unavailable — the app never depends on this working.
class CatalogService {
  CatalogService(this._prefs);
  final PrefsService _prefs;

  static const _timeout = Duration(seconds: 8);

  RemoteCatalogs? _cache;

  /// The catalogs, fetched once and memoised for the session.
  Future<RemoteCatalogs> load() async {
    if (_cache != null) return _cache!;

    final cached = _fromPrefs();
    if (!Config.hasRemoteFonts && !Config.hasRemoteStickers) {
      _register(cached);
      return _cache = cached;
    }

    try {
      final fresh = await _fetch();
      final result = fresh.isEmpty ? cached : fresh;
      _register(result);
      return _cache = result;
    } catch (_) {
      // Offline or a bad payload: keep whatever we cached last time.
      _register(cached);
      return _cache = cached;
    }
  }

  Future<RemoteCatalogs> _fetch() async {
    final fonts = <RemoteFont>[];
    final categories = <RemoteStickerCategory>[];

    if (Config.hasRemoteFonts) {
      final j = await _getJson(Config.fontCatalogUrl);
      fonts.addAll(((j['fonts'] as List?) ?? const [])
          .map((e) => RemoteFont.fromJson(e as Map<String, dynamic>)));
    }
    if (Config.hasRemoteStickers) {
      final j = await _getJson(Config.stickerCatalogUrl);
      categories.addAll(((j['categories'] as List?) ?? const [])
          .map((e) => RemoteStickerCategory.fromJson(e as Map<String, dynamic>)));
    }

    await _prefs.setCatalogCache(
      fonts: jsonEncode(fonts.map((f) => f.toJson()).toList()),
      stickers: jsonEncode(categories.map((c) => c.toJson()).toList()),
    );
    return RemoteCatalogs(fonts: fonts, stickerCategories: categories);
  }

  Future<Map<String, dynamic>> _getJson(String url) async {
    final res = await http.get(Uri.parse(url)).timeout(_timeout);
    if (res.statusCode != 200) {
      throw Exception('Catalog request failed (${res.statusCode}).');
    }
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  RemoteCatalogs _fromPrefs() {
    List<T> parse<T>(String? raw, T Function(Map<String, dynamic>) fromJson) {
      if (raw == null || raw.isEmpty) return const [];
      try {
        return (jsonDecode(raw) as List)
            .map((e) => fromJson(e as Map<String, dynamic>))
            .toList();
      } catch (_) {
        return const [];
      }
    }

    return RemoteCatalogs(
      fonts: parse(_prefs.catalogFontsJson, RemoteFont.fromJson),
      stickerCategories:
          parse(_prefs.catalogStickersJson, RemoteStickerCategory.fromJson),
    );
  }

  /// Make the fonts known to [AppFonts] and load any font-file URLs.
  Future<void> _register(RemoteCatalogs catalogs) async {
    AppFonts.registerRemote(catalogs.fonts);
    for (final f in catalogs.fonts) {
      final url = f.url;
      if (url == null) continue;
      await _loadFontFile(f.family, url);
    }
  }

  /// Download a font file and register it with the engine under [family] so a
  /// plain `TextStyle(fontFamily: family)` renders with it.
  Future<void> _loadFontFile(String family, String url) async {
    try {
      final res = await http.get(Uri.parse(url)).timeout(_timeout);
      if (res.statusCode != 200 || res.bodyBytes.isEmpty) return;
      final loader = FontLoader(family)
        ..addFont(Future.value(ByteData.sublistView(res.bodyBytes)));
      await loader.load();
    } catch (_) {
      // A missing/broken font URL just leaves the family unresolved; Flutter
      // falls back to the default font. Never fatal.
    }
  }
}
