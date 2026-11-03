import 'dart:math' as math;

import 'canvas_element.dart';

/// What happens to a collage when its canvas shape (aspect ratio) changes.
///
/// Everything in a collage is stored resolution-independent, so a shape
/// switch never has to rewrite most of it. The explicit rules are:
///
/// * **Partitions** (layout cells, their cuts, control points, curves and
///   zigzags) are normalised to the content area (0..1 on each axis) and are
///   therefore stretched with the canvas: a diagonal from corner to corner
///   stays corner to corner, a cut at 40% stays at 40%. Edge shapes live in
///   edge-local coordinates and follow their edge.
/// * **Photos inside cells** keep their pan as an alignment (-1..1) and their
///   zoom; the cover fit is recomputed for the new cell, so no cell is ever
///   left uncovered and the framed subject stays in view.
/// * **Layers** (free photos, shapes, text, stickers, drawings) keep their
///   centre as a canvas fraction, their rotation, crop, mask, order, lock and
///   visibility. They are never stretched: their size is kept relative to
///   the canvas's geometric-mean side √(W·H), so a sticker neither balloons
///   on a 3:1 carousel nor shrinks to a dot on a 9:16 story.
///
/// The size rule is exactly reversible: Square → Carousel → Square restores
/// every scale to the last bit, so trying shapes never degrades a layout.
class AspectAdapt {
  AspectAdapt._();

  /// Factor applied to an element's scale when the canvas aspect (w / h)
  /// goes from [from] to [to].
  ///
  /// Element width in pixels is `naturalWidthFrac · W · scale`. Keeping it a
  /// constant fraction of √(W·H) = W / √a means `scale' = scale · √(a / a')`.
  static double scaleFactor(double from, double to) {
    if (from <= 0 || to <= 0 || from == to) return 1;
    return math.sqrt(from / to);
  }

  /// Apply the layer rule to [elements] in place.
  static void elements(List<CanvasElement> elements, double from, double to) {
    final k = scaleFactor(from, to);
    if (k == 1) return;
    for (final e in elements) {
      e.scale *= k;
    }
  }
}
