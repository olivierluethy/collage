import 'dart:ui';

import 'canvas_element.dart';
import 'layout_template.dart';

int _c(Color c) => c.toARGB32();
Color _uc(int v) => Color(v);

/// A canvas aspect ratio the user can pick, with the spec label they asked to
/// see (e.g. "4:5", "16:9").
class CanvasRatio {
  const CanvasRatio(this.label, this.w, this.h, this.name);
  final String label; // shown in the mono spec chip, e.g. "4:5"
  final double w;
  final double h;
  final String name; // friendly, e.g. "Portrait"

  double get value => w / h;

  static const square = CanvasRatio('1:1', 1, 1, 'Square');
  static const portrait = CanvasRatio('4:5', 4, 5, 'Portrait');
  static const story = CanvasRatio('9:16', 9, 16, 'Story');
  static const landscape = CanvasRatio('3:2', 3, 2, 'Landscape');
  static const wide = CanvasRatio('16:9', 16, 9, 'Wide');
  static const classic = CanvasRatio('4:3', 4, 3, 'Classic');
  static const tall = CanvasRatio('2:3', 2, 3, 'Tall');

  static const all = [square, portrait, story, landscape, wide, classic, tall];

  static CanvasRatio byLabel(String label) =>
      all.firstWhere((r) => r.label == label, orElse: () => square);
}

/// How a single picked photo sits inside its grid slot: which photo, and its
/// pan/zoom so the user can push the image around within the slot.
class SlotFill {
  SlotFill({
    required this.assetId,
    this.offsetX = 0,
    this.offsetY = 0,
    this.zoom = 1.0,
    this.imgAspect = 1.0,
  });

  String assetId;
  double offsetX; // -1..1 pan within slot
  double offsetY;
  double zoom; // >= 1
  double imgAspect;

  SlotFill clone() => SlotFill(
        assetId: assetId,
        offsetX: offsetX,
        offsetY: offsetY,
        zoom: zoom,
        imgAspect: imgAspect,
      );

  Map<String, dynamic> toJson() => {
        'assetId': assetId,
        'offsetX': offsetX,
        'offsetY': offsetY,
        'zoom': zoom,
        'imgAspect': imgAspect,
      };

  factory SlotFill.fromJson(Map<String, dynamic> j) => SlotFill(
        assetId: j['assetId'] as String,
        offsetX: (j['offsetX'] as num?)?.toDouble() ?? 0,
        offsetY: (j['offsetY'] as num?)?.toDouble() ?? 0,
        zoom: (j['zoom'] as num?)?.toDouble() ?? 1.0,
        imgAspect: (j['imgAspect'] as num?)?.toDouble() ?? 1.0,
      );
}

/// Live border & spacing controls, in "canvas units per 1000" so they scale
/// with the rendered size. All are user-adjustable sliders.
class BorderSettings {
  BorderSettings({
    this.gap = 8,
    this.margin = 12,
    this.radius = 8,
    this.thickness = 0,
    this.color = const Color(0xFFF5EFE7),
  });

  double gap; // 0..40 between slots
  double margin; // 0..60 outer margin
  double radius; // 0..48 slot corner radius
  double thickness; // 0..20 slot border stroke
  Color color; // border + gap colour

  BorderSettings clone() => BorderSettings(
        gap: gap,
        margin: margin,
        radius: radius,
        thickness: thickness,
        color: color,
      );

  Map<String, dynamic> toJson() => {
        'gap': gap,
        'margin': margin,
        'radius': radius,
        'thickness': thickness,
        'color': _c(color),
      };

  factory BorderSettings.fromJson(Map<String, dynamic> j) => BorderSettings(
        gap: (j['gap'] as num).toDouble(),
        margin: (j['margin'] as num).toDouble(),
        radius: (j['radius'] as num).toDouble(),
        thickness: (j['thickness'] as num).toDouble(),
        color: _uc(j['color'] as int),
      );
}

enum BackgroundKind { solid, gradient, pattern, image }

/// The collage background: a solid colour, a gradient, a bundled pattern, or a
/// user-chosen photo.
class BackgroundSettings {
  BackgroundSettings({
    this.kind = BackgroundKind.solid,
    this.color = const Color(0xFF1A1714),
    this.gradientStart = const Color(0xFFFFB454),
    this.gradientEnd = const Color(0xFFF59E2E),
    this.gradientAngle = 0.785, // ~45°
    this.patternKey = 'dots',
    this.patternColor = const Color(0xFF3D362F),
    this.patternBg = const Color(0xFF1A1714),
    this.imageAssetId,
    this.imageDim = 0.0,
  });

  BackgroundKind kind;
  Color color;
  Color gradientStart;
  Color gradientEnd;
  double gradientAngle;
  String patternKey;
  Color patternColor;
  Color patternBg;
  String? imageAssetId;
  double imageDim; // 0..0.7 darken overlay

  BackgroundSettings clone() => BackgroundSettings(
        kind: kind,
        color: color,
        gradientStart: gradientStart,
        gradientEnd: gradientEnd,
        gradientAngle: gradientAngle,
        patternKey: patternKey,
        patternColor: patternColor,
        patternBg: patternBg,
        imageAssetId: imageAssetId,
        imageDim: imageDim,
      );

  Map<String, dynamic> toJson() => {
        'kind': kind.name,
        'color': _c(color),
        'gradientStart': _c(gradientStart),
        'gradientEnd': _c(gradientEnd),
        'gradientAngle': gradientAngle,
        'patternKey': patternKey,
        'patternColor': _c(patternColor),
        'patternBg': _c(patternBg),
        'imageAssetId': imageAssetId,
        'imageDim': imageDim,
      };

  factory BackgroundSettings.fromJson(Map<String, dynamic> j) =>
      BackgroundSettings(
        kind: BackgroundKind.values.byName(j['kind'] as String),
        color: _uc(j['color'] as int),
        gradientStart: _uc(j['gradientStart'] as int),
        gradientEnd: _uc(j['gradientEnd'] as int),
        gradientAngle: (j['gradientAngle'] as num).toDouble(),
        patternKey: j['patternKey'] as String,
        patternColor: _uc(j['patternColor'] as int),
        patternBg: _uc(j['patternBg'] as int),
        imageAssetId: j['imageAssetId'] as String?,
        imageDim: (j['imageDim'] as num?)?.toDouble() ?? 0.0,
      );
}

/// A complete, saveable & re-editable collage.
class CollageProject {
  CollageProject({
    required this.id,
    required this.title,
    required this.createdAt,
    required this.updatedAt,
    required this.ratioLabel,
    required this.layout,
    required this.fills,
    required this.elements,
    required this.border,
    required this.background,
    this.thumbnailPath,
  });

  final String id;
  String title;
  final int createdAt;
  int updatedAt;
  String ratioLabel;
  LayoutTemplate layout;
  Map<String, SlotFill> fills; // slotId -> fill
  List<CanvasElement> elements;
  BorderSettings border;
  BackgroundSettings background;
  String? thumbnailPath;

  CanvasRatio get ratio => CanvasRatio.byLabel(ratioLabel);

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'createdAt': createdAt,
        'updatedAt': updatedAt,
        'ratioLabel': ratioLabel,
        'layout': layout.toJson(),
        'fills': fills.map((k, v) => MapEntry(k, v.toJson())),
        'elements': elements.map((e) => e.toJson()).toList(),
        'border': border.toJson(),
        'background': background.toJson(),
        'thumbnailPath': thumbnailPath,
      };

  factory CollageProject.fromJson(Map<String, dynamic> j) => CollageProject(
        id: j['id'] as String,
        title: j['title'] as String,
        createdAt: j['createdAt'] as int,
        updatedAt: j['updatedAt'] as int,
        ratioLabel: j['ratioLabel'] as String,
        layout: LayoutTemplate.fromJson(j['layout'] as Map<String, dynamic>),
        fills: (j['fills'] as Map<String, dynamic>).map(
          (k, v) => MapEntry(k, SlotFill.fromJson(v as Map<String, dynamic>)),
        ),
        elements: (j['elements'] as List)
            .map((e) => CanvasElement.fromJson(e as Map<String, dynamic>))
            .toList(),
        border: BorderSettings.fromJson(j['border'] as Map<String, dynamic>),
        background:
            BackgroundSettings.fromJson(j['background'] as Map<String, dynamic>),
        thumbnailPath: j['thumbnailPath'] as String?,
      );
}
