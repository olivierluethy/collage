import 'canvas_element.dart';
import 'collage_project.dart';
import 'layout_template.dart';

/// The second level of the Templates browser: the style / occasion a set of
/// ready-made designs is built around. The first level is the photo count.
enum TemplateStyle {
  minimal,
  birthday,
  love,
  travel,
  party,
  family,
  summer,
  winter,
  social,
  aesthetic,
}

/// A ready-made, publishable collage design: a layout, a border and background
/// look, and decorative text / stickers / shapes — with no photos assigned.
///
/// Tapping a template opens the editor with empty slots so the user drops their
/// own photos in; [toProject] turns it into a normal, editable [CollageProject].
class CollageTemplate {
  const CollageTemplate({
    required this.id,
    required this.name,
    required this.style,
    required this.photoCount,
    required this.ratioLabel,
    required this.layout,
    required this.border,
    required this.background,
    required this.elements,
    this.tags = const [],
  });

  final String id;
  final String name;
  final TemplateStyle style;

  /// How many photos the layout is designed for (1..9).
  final int photoCount;

  /// Canvas ratio label (see [CanvasRatio]); e.g. '1:1', '4:5', '9:16'.
  final String ratioLabel;

  final LayoutTemplate layout;
  final BorderSettings border;
  final BackgroundSettings background;

  /// Decorative overlay (text, stickers, shapes) that sits above the photos.
  final List<CanvasElement> elements;

  final List<String> tags;

  int get slotCount => layout.slots.length;
  CanvasRatio get ratio => CanvasRatio.byLabel(ratioLabel);

  /// A fresh, independent, editable project from this template. Decorative
  /// elements are cloned so editing the collage never mutates the shared
  /// catalog entries.
  CollageProject toProject({
    required String id,
    required int now,
    String? title,
  }) =>
      CollageProject(
        id: id,
        title: title ?? name,
        createdAt: now,
        updatedAt: now,
        ratioLabel: ratioLabel,
        layout: layout,
        fills: {},
        elements: [for (final e in elements) e.clone()],
        border: border.clone(),
        background: background.clone(),
      );
}
