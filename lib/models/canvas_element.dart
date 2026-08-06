import 'dart:ui';

/// Everything that can live on the freeform layer above the collage grid:
/// stickers, shapes, text, emoji, GIFs and free-floating photos.
///
/// Geometry is resolution-independent so it survives save/restore and any
/// screen size: [cx]/[cy] are the element centre as a fraction (0..1) of the
/// canvas, [scale] multiplies the element's natural size, [rotation] is in
/// radians. [z] is the stacking order (higher = in front).
enum ElementType { sticker, shape, text, emoji, gif, image }

int _colorToInt(Color c) => c.toARGB32();
Color _colorFromInt(int v) => Color(v);

sealed class CanvasElement {
  CanvasElement({
    required this.id,
    required this.cx,
    required this.cy,
    this.scale = 1.0,
    this.rotation = 0.0,
    this.z = 0,
  });

  final String id;
  double cx;
  double cy;
  double scale;
  double rotation;
  int z;

  ElementType get type;

  /// Natural width of the element as a fraction of canvas width, before
  /// [scale]. Used so a freshly added element has a sensible default size.
  double get naturalWidthFrac;

  /// Natural aspect ratio (width / height) of the element's content.
  double get aspectRatio;

  CanvasElement clone();

  Map<String, dynamic> baseJson() => {
        'id': id,
        'type': type.name,
        'cx': cx,
        'cy': cy,
        'scale': scale,
        'rotation': rotation,
        'z': z,
      };

  Map<String, dynamic> toJson();

  static CanvasElement fromJson(Map<String, dynamic> j) {
    final type = ElementType.values.byName(j['type'] as String);
    return switch (type) {
      ElementType.sticker => StickerElement.fromJson(j),
      ElementType.shape => ShapeElement.fromJson(j),
      ElementType.text => TextElement.fromJson(j),
      ElementType.emoji => EmojiElement.fromJson(j),
      ElementType.gif => GifElement.fromJson(j),
      ElementType.image => ImageElement.fromJson(j),
    };
  }
}

/// A bundled SVG sticker (asset path under assets/stickers/...).
class StickerElement extends CanvasElement {
  StickerElement({
    required super.id,
    required super.cx,
    required super.cy,
    required this.assetPath,
    super.scale,
    super.rotation,
    super.z,
  });

  final String assetPath;

  @override
  ElementType get type => ElementType.sticker;
  @override
  double get naturalWidthFrac => 0.30;
  @override
  double get aspectRatio => 1.0;

  @override
  StickerElement clone() => StickerElement(
        id: id,
        cx: cx,
        cy: cy,
        assetPath: assetPath,
        scale: scale,
        rotation: rotation,
        z: z,
      );

  @override
  Map<String, dynamic> toJson() => {...baseJson(), 'assetPath': assetPath};

  factory StickerElement.fromJson(Map<String, dynamic> j) => StickerElement(
        id: j['id'] as String,
        cx: (j['cx'] as num).toDouble(),
        cy: (j['cy'] as num).toDouble(),
        assetPath: j['assetPath'] as String,
        scale: (j['scale'] as num).toDouble(),
        rotation: (j['rotation'] as num).toDouble(),
        z: j['z'] as int,
      );
}

/// A colourable vector shape (see [shapeKind]).
class ShapeElement extends CanvasElement {
  ShapeElement({
    required super.id,
    required super.cx,
    required super.cy,
    required this.shapeKind,
    required this.fill,
    this.stroke,
    this.strokeWidth = 0,
    super.scale,
    super.rotation,
    super.z,
  });

  /// Key into [ShapeCatalog]; e.g. 'circle', 'star', 'heart'.
  final String shapeKind;
  Color fill;
  Color? stroke;
  double strokeWidth;

  @override
  ElementType get type => ElementType.shape;
  @override
  double get naturalWidthFrac => 0.30;
  @override
  double get aspectRatio => 1.0;

  @override
  ShapeElement clone() => ShapeElement(
        id: id,
        cx: cx,
        cy: cy,
        shapeKind: shapeKind,
        fill: fill,
        stroke: stroke,
        strokeWidth: strokeWidth,
        scale: scale,
        rotation: rotation,
        z: z,
      );

  @override
  Map<String, dynamic> toJson() => {
        ...baseJson(),
        'shapeKind': shapeKind,
        'fill': _colorToInt(fill),
        'stroke': stroke == null ? null : _colorToInt(stroke!),
        'strokeWidth': strokeWidth,
      };

  factory ShapeElement.fromJson(Map<String, dynamic> j) => ShapeElement(
        id: j['id'] as String,
        cx: (j['cx'] as num).toDouble(),
        cy: (j['cy'] as num).toDouble(),
        shapeKind: j['shapeKind'] as String,
        fill: _colorFromInt(j['fill'] as int),
        stroke: j['stroke'] == null ? null : _colorFromInt(j['stroke'] as int),
        strokeWidth: (j['strokeWidth'] as num).toDouble(),
        scale: (j['scale'] as num).toDouble(),
        rotation: (j['rotation'] as num).toDouble(),
        z: j['z'] as int,
      );
}

enum TextAlignH { left, center, right }

/// An editable text element.
class TextElement extends CanvasElement {
  TextElement({
    required super.id,
    required super.cx,
    required super.cy,
    required this.text,
    required this.color,
    this.fontKey = 'inter',
    this.bold = false,
    this.italic = false,
    this.align = TextAlignH.center,
    this.background,
    super.scale,
    super.rotation,
    super.z,
  });

  String text;
  Color color;

  /// Key into the app's curated font list (see TextTool).
  String fontKey;
  bool bold;
  bool italic;
  TextAlignH align;
  Color? background;

  @override
  ElementType get type => ElementType.text;
  @override
  double get naturalWidthFrac => 0.6;
  @override
  double get aspectRatio => 3.0; // wide by default; box grows with content

  @override
  TextElement clone() => TextElement(
        id: id,
        cx: cx,
        cy: cy,
        text: text,
        color: color,
        fontKey: fontKey,
        bold: bold,
        italic: italic,
        align: align,
        background: background,
        scale: scale,
        rotation: rotation,
        z: z,
      );

  @override
  Map<String, dynamic> toJson() => {
        ...baseJson(),
        'text': text,
        'color': _colorToInt(color),
        'fontKey': fontKey,
        'bold': bold,
        'italic': italic,
        'align': align.name,
        'background': background == null ? null : _colorToInt(background!),
      };

  factory TextElement.fromJson(Map<String, dynamic> j) => TextElement(
        id: j['id'] as String,
        cx: (j['cx'] as num).toDouble(),
        cy: (j['cy'] as num).toDouble(),
        text: j['text'] as String,
        color: _colorFromInt(j['color'] as int),
        fontKey: j['fontKey'] as String? ?? 'inter',
        bold: j['bold'] as bool? ?? false,
        italic: j['italic'] as bool? ?? false,
        align: TextAlignH.values.byName(j['align'] as String? ?? 'center'),
        background:
            j['background'] == null ? null : _colorFromInt(j['background'] as int),
        scale: (j['scale'] as num).toDouble(),
        rotation: (j['rotation'] as num).toDouble(),
        z: j['z'] as int,
      );
}

/// A native emoji rendered by the OS font.
class EmojiElement extends CanvasElement {
  EmojiElement({
    required super.id,
    required super.cx,
    required super.cy,
    required this.emoji,
    super.scale,
    super.rotation,
    super.z,
  });

  final String emoji;

  @override
  ElementType get type => ElementType.emoji;
  @override
  double get naturalWidthFrac => 0.18;
  @override
  double get aspectRatio => 1.0;

  @override
  EmojiElement clone() => EmojiElement(
        id: id,
        cx: cx,
        cy: cy,
        emoji: emoji,
        scale: scale,
        rotation: rotation,
        z: z,
      );

  @override
  Map<String, dynamic> toJson() => {...baseJson(), 'emoji': emoji};

  factory EmojiElement.fromJson(Map<String, dynamic> j) => EmojiElement(
        id: j['id'] as String,
        cx: (j['cx'] as num).toDouble(),
        cy: (j['cy'] as num).toDouble(),
        emoji: j['emoji'] as String,
        scale: (j['scale'] as num).toDouble(),
        rotation: (j['rotation'] as num).toDouble(),
        z: j['z'] as int,
      );
}

/// An animated GIF from Giphy (loaded from a network URL).
class GifElement extends CanvasElement {
  GifElement({
    required super.id,
    required super.cx,
    required super.cy,
    required this.url,
    required this.gifAspect,
    super.scale,
    super.rotation,
    super.z,
  });

  final String url;
  final double gifAspect;

  @override
  ElementType get type => ElementType.gif;
  @override
  double get naturalWidthFrac => 0.4;
  @override
  double get aspectRatio => gifAspect;

  @override
  GifElement clone() => GifElement(
        id: id,
        cx: cx,
        cy: cy,
        url: url,
        gifAspect: gifAspect,
        scale: scale,
        rotation: rotation,
        z: z,
      );

  @override
  Map<String, dynamic> toJson() =>
      {...baseJson(), 'url': url, 'gifAspect': gifAspect};

  factory GifElement.fromJson(Map<String, dynamic> j) => GifElement(
        id: j['id'] as String,
        cx: (j['cx'] as num).toDouble(),
        cy: (j['cy'] as num).toDouble(),
        url: j['url'] as String,
        gifAspect: (j['gifAspect'] as num).toDouble(),
        scale: (j['scale'] as num).toDouble(),
        rotation: (j['rotation'] as num).toDouble(),
        z: j['z'] as int,
      );
}

/// A free-floating photo (freeform collages / extra photos on top of a grid).
/// [assetId] is the photo_manager AssetEntity id, resolved to a file at render.
class ImageElement extends CanvasElement {
  ImageElement({
    required super.id,
    required super.cx,
    required super.cy,
    required this.assetId,
    this.imgAspect = 1.0,
    super.scale,
    super.rotation,
    super.z,
  });

  final String assetId;
  double imgAspect;

  @override
  ElementType get type => ElementType.image;
  @override
  double get naturalWidthFrac => 0.45;
  @override
  double get aspectRatio => imgAspect;

  @override
  ImageElement clone() => ImageElement(
        id: id,
        cx: cx,
        cy: cy,
        assetId: assetId,
        imgAspect: imgAspect,
        scale: scale,
        rotation: rotation,
        z: z,
      );

  @override
  Map<String, dynamic> toJson() =>
      {...baseJson(), 'assetId': assetId, 'imgAspect': imgAspect};

  factory ImageElement.fromJson(Map<String, dynamic> j) => ImageElement(
        id: j['id'] as String,
        cx: (j['cx'] as num).toDouble(),
        cy: (j['cy'] as num).toDouble(),
        assetId: j['assetId'] as String,
        imgAspect: (j['imgAspect'] as num?)?.toDouble() ?? 1.0,
        scale: (j['scale'] as num).toDouble(),
        rotation: (j['rotation'] as num).toDouble(),
        z: j['z'] as int,
      );
}
