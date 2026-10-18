/// Remote, user-supplied catalogs loaded from a URL at runtime — one for extra
/// fonts and one for extra stickers. Nothing is hard-coded: the build supplies
/// the URLs (see [Config.fontCatalogUrl] / [Config.stickerCatalogUrl]) and the
/// app degrades gracefully to the bundled sets when a URL is empty or the fetch
/// fails.
library;

/// An extra font offered in the text panel. Either a Google Fonts family name
/// ([googleFont]) or a direct TrueType/OpenType file ([url]).
class RemoteFont {
  const RemoteFont({
    required this.key,
    required this.family,
    this.googleFont,
    this.url,
  });

  /// Stable id stored in a project's `TextElement.fontKey`.
  final String key;

  /// Family shown in the picker and used to render.
  final String family;

  /// Google Fonts family name (case-sensitive), when sourced from Google.
  final String? googleFont;

  /// Direct font file URL, when sourced elsewhere.
  final String? url;

  Map<String, dynamic> toJson() => {
        'key': key,
        'family': family,
        if (googleFont != null) 'googleFont': googleFont,
        if (url != null) 'url': url,
      };

  factory RemoteFont.fromJson(Map<String, dynamic> j) => RemoteFont(
        key: (j['key'] ?? j['family']) as String,
        family: j['family'] as String,
        googleFont: j['googleFont'] as String?,
        url: j['url'] as String?,
      );
}

/// One remote sticker image (svg / png / webp / gif), referenced by URL.
class RemoteSticker {
  const RemoteSticker({required this.name, required this.url});

  final String name;
  final String url;

  Map<String, dynamic> toJson() => {'name': name, 'url': url};

  factory RemoteSticker.fromJson(Map<String, dynamic> j) => RemoteSticker(
        name: (j['name'] ?? '') as String,
        url: j['url'] as String,
      );
}

/// A remote sticker category (its own tab in the Stickers panel).
class RemoteStickerCategory {
  const RemoteStickerCategory({
    required this.id,
    required this.label,
    required this.stickers,
  });

  final String id;
  final String label;
  final List<RemoteSticker> stickers;

  Map<String, dynamic> toJson() => {
        'id': id,
        'label': label,
        'stickers': stickers.map((s) => s.toJson()).toList(),
      };

  factory RemoteStickerCategory.fromJson(Map<String, dynamic> j) =>
      RemoteStickerCategory(
        id: (j['id'] ?? j['label']) as String,
        label: j['label'] as String,
        stickers: ((j['stickers'] as List?) ?? const [])
            .map((e) => RemoteSticker.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

/// Everything fetched from the remote catalogs in one pass.
class RemoteCatalogs {
  const RemoteCatalogs({this.fonts = const [], this.stickerCategories = const []});

  final List<RemoteFont> fonts;
  final List<RemoteStickerCategory> stickerCategories;

  bool get isEmpty => fonts.isEmpty && stickerCategories.isEmpty;

  static const empty = RemoteCatalogs();

  Map<String, dynamic> toJson() => {
        'fonts': fonts.map((f) => f.toJson()).toList(),
        'categories': stickerCategories.map((c) => c.toJson()).toList(),
      };

  factory RemoteCatalogs.fromJson(Map<String, dynamic> j) => RemoteCatalogs(
        fonts: ((j['fonts'] as List?) ?? const [])
            .map((e) => RemoteFont.fromJson(e as Map<String, dynamic>))
            .toList(),
        stickerCategories: ((j['categories'] as List?) ?? const [])
            .map((e) => RemoteStickerCategory.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}
