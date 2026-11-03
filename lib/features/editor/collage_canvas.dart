import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/fonts.dart';
import '../../data/shape_catalog.dart';
import '../../l10n/app_localizations.dart';
import '../../models/canvas_element.dart';
import '../../models/collage_project.dart';
import '../../models/layout_template.dart';
import '../../theme/palette.dart';
import '../../theme/tokens.dart';
import '../../widgets/collage_background.dart';
import '../../widgets/curved_edges.dart';
import '../../widgets/drawing_painter.dart';
import '../../widgets/photo_image.dart';
import '../../widgets/photo_layer.dart';
import '../../widgets/poly_clipper.dart';
import '../../widgets/sharpened.dart';
import '../../widgets/sticker_image.dart';
import '../../widgets/video_slot.dart';
import 'cut_editor.dart';
import 'editor_controller.dart';
import 'slot_splits.dart';

/// Renders and (optionally) edits the whole collage: background, the grid of
/// photo slots, and the freeform overlay elements. Used interactively in the
/// editor and non-interactively (wrapped in a RepaintBoundary) for export.
class CollageCanvas extends StatelessWidget {
  const CollageCanvas({
    super.key,
    required this.controller,
    this.interactive = true,
    this.onEditSlot,
    this.onElementTrashed,
    this.isOverTrash,
  });

  final EditorController controller;
  final bool interactive;

  /// The edit (pencil) badge on a photo was tapped: show its controls.
  final void Function(String slotId)? onEditSlot;

  /// An overlay element was dragged onto the trash target and released.
  final void Function(String elementId)? onElementTrashed;

  /// Whether a global finger position is over the host's trash target.
  final bool Function(Offset globalPosition)? isOverTrash;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    return AnimatedBuilder(
      animation: c,
      builder: (context, _) {
        return LayoutBuilder(
          builder: (context, constraints) {
            final size = Size(constraints.maxWidth, constraints.maxHeight);
            final elements = [...c.project.elements]..sort((a, b) => a.z.compareTo(b.z));
            return ClipRect(
              child: Stack(
                children: [
                  Positioned.fill(child: CollageBackground(bg: c.background)),
                  // Tap-outside to deselect. Kept in the tree (inert on export)
                  // so slot/element children never shift position and get
                  // rebuilt — which would drop their decoded photo frames.
                  Positioned.fill(
                    child: GestureDetector(
                      behavior: HitTestBehavior.translucent,
                      onTap: interactive ? c.clearSelection : null,
                    ),
                  ),
                  ..._slots(c, size),
                  for (final e in elements)
                    if (!e.hidden)
                    _ElementView(
                      key: ValueKey(e.id),
                      controller: c,
                      element: e,
                      canvas: size,
                      // Elements step aside while edges are being shaped.
                      interactive: interactive && !c.edgeEditing && !e.locked,
                      onTrashed: onElementTrashed,
                      isOverTrash: isOverTrash,
                    ),
                  // Alignment guides while a dragged element is snapped.
                  if (interactive && (c.guideX != null || c.guideY != null))
                    Positioned.fill(
                      child: IgnorePointer(
                        child: CustomPaint(
                          painter: _GuidePainter(
                            x: c.guideX,
                            y: c.guideY,
                            color: context.colors.amber,
                          ),
                        ),
                      ),
                    ),
                  // Drag handles on the edges between cells, to resize them.
                  if (interactive && !c.drawing && !c.edgeEditing && c.selectedElementId == null)
                    ..._splitHandles(context, c, size),
                  // Edge shaping: a handle on every shared edge, plus the
                  // Bézier control points of the selected one.
                  if (interactive && c.edgeEditing)
                    Positioned.fill(
                      child: c.cutMode == CutMode.points
                          ? CutPointEditor(controller: c, content: _content(c, size))
                          : _EdgeEditor(controller: c, content: _content(c, size)),
                    ),
                  // Draw mode: a full-canvas layer that captures strokes.
                  if (interactive && c.drawing)
                    Positioned.fill(child: _DrawLayer(controller: c, canvas: size)),
                ],
              ),
            );
          },
        );
      },
    );
  }

  List<Widget> _slots(EditorController c, Size size) {
    final slots = c.project.layout.slots;
    if (slots.isEmpty) return const [];
    final unit = size.width / 1000;
    final margin = c.border.margin * unit;
    final gap = c.border.gap * unit;
    final radius = c.border.radius * unit;
    final thickness = c.border.thickness * unit;

    final content = Rect.fromLTWH(
      margin,
      margin,
      (size.width - 2 * margin).clamp(0, size.width),
      (size.height - 2 * margin).clamp(0, size.height),
    );

    Offset toPx(Offset n) => Offset(
          content.left + n.dx * content.width,
          content.top + n.dy * content.height,
        );

    return slots.map((slot) {
      if (slot.isPolygon) {
        // Map the normalised polygon into content pixels, inset for the gap,
        // shape any curved / zigzag edges, then position the cell at the
        // outline's bounds with a local (box-relative) path.
        var poly = slot.points!.map(toPx).toList();
        poly = insetConvexPolygon(poly, gap / 2);
        final curved = c.curvedEdgesFor(slot);
        final outline = curved.isEmpty ? polygonPath(poly) : shapedCellPath(poly, curved);
        final b = curved.isEmpty ? _boundsOf(poly) : safeBounds(outline);
        final local = [for (final p in poly) p - b.topLeft];
        return Positioned(
          key: ValueKey('slot:${slot.id}'),
          left: b.left,
          top: b.top,
          width: b.width.clamp(0, size.width),
          height: b.height.clamp(0, size.height),
          // Each cell rasters on its own layer, so moving a cut or an overlay
          // repaints only what changed. Present in export too (same tree).
          child: RepaintBoundary(
            child: _PolySlotView(
              controller: c,
              slotId: slot.id,
              unit: unit,
              polygon: local,
              outline: curved.isEmpty ? null : outline.shift(-b.topLeft),
              thickness: thickness,
              borderColor: c.border.color,
              interactive: interactive && !c.edgeEditing,
              onEditSlot: onEditSlot,
            ),
          ),
        );
      }
      var r = Rect.fromLTRB(
        content.left + slot.rect.left * content.width,
        content.top + slot.rect.top * content.height,
        content.left + slot.rect.right * content.width,
        content.top + slot.rect.bottom * content.height,
      );
      r = r.deflate(gap / 2);
      return Positioned(
        key: ValueKey('slot:${slot.id}'),
        left: r.left,
        top: r.top,
        width: r.width.clamp(0, size.width),
        height: r.height.clamp(0, size.height),
        child: RepaintBoundary(
          child: _SlotView(
            controller: c,
            slotId: slot.id,
            unit: unit,
            radius: radius,
            thickness: thickness,
            borderColor: c.border.color,
            interactive: interactive && !c.edgeEditing,
            onEditSlot: onEditSlot,
          ),
        ),
      );
    }).toList();
  }

  /// The content area (canvas minus the outer margin), in canvas pixels.
  static Rect _content(EditorController c, Size size) {
    final margin = c.border.margin * size.width / 1000;
    return Rect.fromLTWH(
      margin,
      margin,
      (size.width - 2 * margin).clamp(0, size.width),
      (size.height - 2 * margin).clamp(0, size.height),
    );
  }

  List<Widget> _splitHandles(BuildContext context, EditorController c, Size size) {
    final margin = c.border.margin * size.width / 1000;
    final content = Rect.fromLTWH(
      margin,
      margin,
      (size.width - 2 * margin).clamp(0, size.width),
      (size.height - 2 * margin).clamp(0, size.height),
    );
    return [
      for (final sp in c.splits)
        _SplitHandle(
          key: ValueKey('${sp.axis.name}:${(sp.before.toList()..sort()).join(',')}|${(sp.after.toList()..sort()).join(',')}'),
          controller: c,
          split: sp,
          content: content,
        ),
      // Bent cuts (several pieces between the same cells) are reshaped by
      // their points in the cut editor; a pill per piece would only clutter.
      for (final sp in c.polySplits)
        if (c.polySplits.where((o) => o.slots.length == sp.slots.length && o.slots.containsAll(sp.slots)).length == 1)
        _PolySplitHandle(
          key: ValueKey('poly:${(sp.slots.toList()..sort()).join(',')}'),
          controller: c,
          split: sp,
          content: content,
        ),
    ];
  }

  static Rect _boundsOf(List<Offset> pts) {
    var minX = double.infinity, minY = double.infinity;
    var maxX = -double.infinity, maxY = -double.infinity;
    for (final p in pts) {
      if (p.dx < minX) minX = p.dx;
      if (p.dy < minY) minY = p.dy;
      if (p.dx > maxX) maxX = p.dx;
      if (p.dy > maxY) maxY = p.dy;
    }
    return Rect.fromLTRB(minX, minY, maxX, maxY);
  }
}

/// Builds a slot photo, cover-fitted, with its per-cell colour filter baked in
/// via [ColorFiltered]. Because the editor and the export use the exact same
/// widget, the saved image matches the screen. Identity filters skip the
/// wrapper entirely for performance, and a non-flipped photo skips the mirror
/// transform for the same reason.
Widget filteredPhoto(
  SlotFill fill, {
  Alignment alignment = Alignment.center,
  BoxFit fit = BoxFit.cover,
}) {
  Widget photo = fill.isVideo
      ? VideoSlot(assetId: fill.assetId, fit: fit, alignment: alignment)
      : PhotoImage(
          assetId: fill.assetId,
          full: true,
          fit: fit,
          alignment: alignment,
        );
  if (!fill.filter.isColorIdentity) {
    photo = ColorFiltered(
      colorFilter: ColorFilter.matrix(fill.filter.matrix()),
      child: photo,
    );
  }
  if (fill.filter.sharpen > 0) {
    photo = Sharpened(amount: fill.filter.sharpen, child: photo);
  }
  if (fill.isFlipped) {
    photo = Transform.scale(
      scaleX: fill.flipX ? -1 : 1,
      scaleY: fill.flipY ? -1 : 1,
      child: photo,
    );
  }
  return photo;
}

/// Tilts a cover-fitted slot photo by [rotation] and enlarges it just enough
/// that the rotated photo still covers every corner of the cell. The wrapper is
/// always built (even at 0°) so the photo's ancestors never change.
class _RotatedCover extends StatelessWidget {
  const _RotatedCover({required this.rotation, required this.child});
  final double rotation;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final h = constraints.maxHeight;
        var s = 1.0;
        if (rotation != 0 && w > 0 && h > 0 && w.isFinite && h.isFinite) {
          final c = math.cos(rotation).abs();
          final sn = math.sin(rotation).abs();
          s = math.max((w * c + h * sn) / w, (w * sn + h * c) / h);
        }
        return Transform.rotate(
          angle: rotation,
          child: Transform.scale(scale: s, child: child),
        );
      },
    );
  }
}

/// A small pill on a cell edge; dragging it moves the edge and resizes the
/// cells on both sides.
class _SplitHandle extends StatefulWidget {
  const _SplitHandle({super.key, required this.controller, required this.split, required this.content});
  final EditorController controller;
  final SlotSplit split;
  final Rect content; // the layout area in canvas pixels

  @override
  State<_SplitHandle> createState() => _SplitHandleState();
}

class _SplitHandleState extends State<_SplitHandle> {
  SlotSplit? _active; // the split as it was when the drag started
  double _travel = 0; // layout fractions moved so far

  @override
  Widget build(BuildContext context) {
    final sp = widget.split;
    final r = widget.content;
    final vertical = sp.axis == Axis.vertical;
    final mid = (sp.start + sp.end) / 2;
    final center = vertical
        ? Offset(r.left + sp.pos * r.width, r.top + mid * r.height)
        : Offset(r.left + mid * r.width, r.top + sp.pos * r.height);
    const long = 30.0, short = 12.0, hit = 36.0;
    return Positioned(
      left: center.dx - hit / 2,
      top: center.dy - hit / 2,
      width: hit,
      height: hit,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanStart: (_) {
          _active = sp;
          _travel = 0;
        },
        onPanUpdate: (d) {
          final a = _active;
          if (a == null) return;
          _travel += vertical ? d.delta.dx / r.width : d.delta.dy / r.height;
          widget.controller.moveSplitTo(a, a.pos + _travel);
        },
        onPanEnd: (_) => _active = null,
        child: Center(
          child: Container(
            width: vertical ? short : long,
            height: vertical ? long : short,
            decoration: BoxDecoration(
              color: context.colors.amber,
              borderRadius: BorderRadius.circular(Radii.pill),
              border: Border.all(color: Colors.white, width: 1.5),
              boxShadow: Shadows.e2,
            ),
          ),
        ),
      ),
    );
  }
}

/// Drag handle on a shared edge between polygon cells. It sits at the edge's
/// midpoint, turned along the edge, and shifts the edge along its normal.
class _PolySplitHandle extends StatefulWidget {
  const _PolySplitHandle({super.key, required this.controller, required this.split, required this.content});
  final EditorController controller;
  final PolySplit split;
  final Rect content; // the layout area in canvas pixels

  @override
  State<_PolySplitHandle> createState() => _PolySplitHandleState();
}

class _PolySplitHandleState extends State<_PolySplitHandle> {
  PolySplit? _active; // the edge as it was when the drag started
  List<LayoutSlot> _startSlots = const [];
  double _travel = 0; // layout fractions along the edge normal

  @override
  Widget build(BuildContext context) {
    final sp = widget.split;
    final r = widget.content;
    Offset px(Offset f) => Offset(r.left + f.dx * r.width, r.top + f.dy * r.height);
    final a = px(sp.p), b = px(sp.q);
    final mid = (a + b) / 2;
    final angle = (b - a).direction;
    const hit = 36.0;
    return Positioned(
      left: mid.dx - hit / 2,
      top: mid.dy - hit / 2,
      width: hit,
      height: hit,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanStart: (_) {
          _active = sp;
          _startSlots = widget.controller.project.layout.slots;
          _travel = 0;
        },
        onPanUpdate: (d) {
          final s = _active;
          if (s == null || r.isEmpty) return;
          final n = s.normal;
          _travel += d.delta.dx / r.width * n.dx + d.delta.dy / r.height * n.dy;
          widget.controller.movePolySplitBy(_startSlots, s, _travel);
        },
        onPanEnd: (_) => _active = null,
        child: Center(
          child: Transform.rotate(
            angle: angle,
            child: Container(
              width: 30,
              height: 12,
              decoration: BoxDecoration(
                color: context.colors.amber,
                borderRadius: BorderRadius.circular(Radii.pill),
                border: Border.all(color: Colors.white, width: 1.5),
                boxShadow: Shadows.e2,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Captures finger strokes in draw mode and shows them live. Points are kept
/// as canvas fractions so they map onto any render size.
class _DrawLayer extends StatelessWidget {
  const _DrawLayer({required this.controller, required this.canvas});
  final EditorController controller;
  final Size canvas;

  Offset _frac(Offset local) => Offset(local.dx / canvas.width, local.dy / canvas.height);

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onPanStart: (d) => controller.beginStroke(_frac(d.localPosition)),
      onPanUpdate: (d) => controller.extendStroke(_frac(d.localPosition)),
      child: CustomPaint(
        size: Size.infinite,
        painter: DrawingPainter(controller.draftStrokes),
      ),
    );
  }
}

/// The drop shadow under a cell with "shadow" switched on, scaled to the
/// canvas so the export matches the screen.
List<BoxShadow> _cellShadow(double unit) => [
      BoxShadow(
        color: Colors.black.withValues(alpha: 0.45),
        blurRadius: 18 * unit,
        offset: Offset(0, 6 * unit),
      ),
    ];

/// Clips a slot photo: rounded rectangle by default, a [ShapeCatalog] shape
/// centred in the cell when [mask] is set, or ragged torn-paper edges.
class _SlotClipper extends CustomClipper<Path> {
  _SlotClipper({required this.radius, required this.mask, required this.torn, required this.seed});
  final double radius;
  final String mask;
  final bool torn;
  final int seed;

  @override
  Path getClip(Size size) {
    if (mask != 'none') {
      final side = math.min(size.width, size.height) * 0.96;
      final shape = ShapeCatalog.pathFor(mask, Size(side, side));
      return shape.shift(Offset((size.width - side) / 2, (size.height - side) / 2));
    }
    if (torn) return _tornPath(size, seed);
    return Path()..addRRect(RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(radius)));
  }

  /// A deterministic jagged outline: small random bites along every edge.
  static Path _tornPath(Size s, int seed) {
    final rnd = math.Random(seed);
    final depth = math.min(s.width, s.height) * 0.025;
    final step = math.max(6.0, math.min(s.width, s.height) / 28);
    double j() => rnd.nextDouble() * depth;
    final p = Path()..moveTo(j(), j());
    for (var x = step; x < s.width; x += step) {
      p.lineTo(x, j());
    }
    for (var y = step; y < s.height; y += step) {
      p.lineTo(s.width - j(), y);
    }
    for (var x = s.width - step; x > 0; x -= step) {
      p.lineTo(x, s.height - j());
    }
    for (var y = s.height - step; y > 0; y -= step) {
      p.lineTo(j(), y);
    }
    return p..close();
  }

  @override
  bool shouldReclip(_SlotClipper old) =>
      old.radius != radius || old.mask != mask || old.torn != torn || old.seed != seed;
}

/// Two translucent strips of tape over a cell's top corners.
class _Tape extends StatelessWidget {
  const _Tape({required this.unit});
  final double unit;

  @override
  Widget build(BuildContext context) {
    final w = 90 * unit, h = 26 * unit;
    Widget strip(double angle) => Transform.rotate(
          angle: angle,
          child: Container(
            width: w,
            height: h,
            decoration: BoxDecoration(
              color: const Color(0xFFF3E7C9).withValues(alpha: 0.82),
              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.15), blurRadius: 3 * unit)],
            ),
          ),
        );
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned(left: -w * 0.25, top: -h * 0.1, child: strip(-0.7)),
        Positioned(right: -w * 0.25, top: -h * 0.1, child: strip(0.7)),
      ],
    );
  }
}

/// Darkened cell edges: a radial gradient from clear to black.
class _Vignette extends StatelessWidget {
  const _Vignette({required this.strength});
  final double strength; // 0..1

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: RadialGradient(
            radius: 0.9,
            colors: [Colors.transparent, Colors.black.withValues(alpha: 0.75 * strength)],
            stops: const [0.5, 1.0],
          ),
        ),
      ),
    );
  }
}

/// Shadow under a polygon cell, plus the Polaroid card when [cardColor] is
/// set; paints nothing when neither is on.
class _PolyShadowPainter extends CustomPainter {
  _PolyShadowPainter({required this.points, required this.elevation, this.cardColor, this.outline});
  final List<Offset> points;
  final Path? outline;
  final double elevation;
  final Color? cardColor;

  @override
  void paint(Canvas canvas, Size size) {
    if (points.length < 3) return;
    final path = outline ?? (Path()..addPolygon(points, true));
    if (elevation > 0) canvas.drawShadow(path, Colors.black, elevation, false);
    if (cardColor != null) canvas.drawPath(path, Paint()..color = cardColor!);
  }

  @override
  bool shouldRepaint(_PolyShadowPainter old) =>
      old.elevation != elevation || old.points != points || old.cardColor != cardColor || old.outline != outline;
}

/// Clips a polygon cell's photo: the polygon itself, a shape mask centred in
/// it (and cut to the polygon), ragged torn-paper edges, or the polygon inset
/// by [inset] for the Polaroid card.
class _PolyCellClipper extends CustomClipper<Path> {
  _PolyCellClipper({
    required this.points,
    this.outline,
    required this.mask,
    required this.torn,
    required this.inset,
    required this.seed,
  });
  final List<Offset> points;
  final Path? outline; // curved / zigzag cell outline, if any
  final String mask;
  final bool torn;
  final double inset;
  final int seed;

  @override
  Path getClip(Size size) {
    final poly = outline ?? polygonPath(points);
    if (mask != 'none') {
      final c = polygonCentroid(points);
      final side = math.min(size.width, size.height) * 0.85;
      final shape = ShapeCatalog.pathFor(mask, Size(side, side)).shift(c - Offset(side / 2, side / 2));
      return Path.combine(PathOperation.intersect, poly, shape);
    }
    if (torn) return _tornPolygon(points, seed, math.min(size.width, size.height));
    if (inset > 0 && outline == null) return polygonPath(insetConvexPolygon(points, inset));
    return poly;
  }

  /// The polygon's outline with small random bites taken towards its centre.
  static Path _tornPolygon(List<Offset> pts, int seed, double extent) {
    final rnd = math.Random(seed);
    final c = polygonCentroid(pts);
    final depth = extent * 0.025;
    final step = math.max(6.0, extent / 28);
    Offset bite(Offset p) {
      final toCentre = c - p;
      final len = toCentre.distance;
      return len == 0 ? p : p + toCentre / len * (rnd.nextDouble() * depth);
    }

    final path = Path();
    for (var i = 0; i < pts.length; i++) {
      final a = pts[i], b = pts[(i + 1) % pts.length];
      final n = math.max(1, ((b - a).distance / step).floor());
      for (var k = 0; k < n; k++) {
        final p = bite(Offset.lerp(a, b, k / n)!);
        if (i == 0 && k == 0) {
          path.moveTo(p.dx, p.dy);
        } else {
          path.lineTo(p.dx, p.dy);
        }
      }
    }
    return path..close();
  }

  @override
  bool shouldReclip(_PolyCellClipper old) =>
      old.points != points ||
      old.outline != outline ||
      old.mask != mask ||
      old.torn != torn ||
      old.inset != inset ||
      old.seed != seed;
}

/// Two strips of tape over the two top-most corners of a polygon cell.
class _PolyTape extends StatelessWidget {
  const _PolyTape({required this.points, required this.unit});
  final List<Offset> points;
  final double unit;

  @override
  Widget build(BuildContext context) {
    final top = [...points]..sort((a, b) => a.dy.compareTo(b.dy));
    final corners = top.take(2).toList()..sort((a, b) => a.dx.compareTo(b.dx));
    final w = 90 * unit, h = 26 * unit;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        for (var i = 0; i < corners.length; i++)
          Positioned(
            left: corners[i].dx - w / 2,
            top: corners[i].dy - h / 2,
            child: Transform.rotate(
              angle: i == 0 ? -0.7 : 0.7,
              child: Container(
                width: w,
                height: h,
                decoration: BoxDecoration(
                  color: const Color(0xFFF3E7C9).withValues(alpha: 0.82),
                  boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.15), blurRadius: 3 * unit)],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Edge shaping on the canvas: a dot on the middle of every edge shared by two
/// cells (tap to pick it) and, for the picked edge, its two Bézier control
/// points, each draggable by finger or stylus with a 44dp target. Control
/// points snap back to a straight line near it and to the thirds along it.
class _EdgeEditor extends StatefulWidget {
  const _EdgeEditor({required this.controller, required this.content});
  final EditorController controller;
  final Rect content;

  @override
  State<_EdgeEditor> createState() => _EdgeEditorState();
}

class _EdgeEditorState extends State<_EdgeEditor> {
  Offset _px(Offset n) => Offset(
        widget.content.left + n.dx * widget.content.width,
        widget.content.top + n.dy * widget.content.height,
      );

  void _drag(SharedEdge edge, bool first, Offset global) {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null) return;
    final local = box.globalToLocal(global);
    final p = _px(edge.p), q = _px(edge.q);
    var uv = edgeLocal(p, q, local);
    var u = uv.dx.clamp(0.05, 0.95);
    var v = uv.dy.clamp(-0.5, 0.5);
    if (v.abs() < 0.02) v = 0; // snap to straight
    for (final t in const [1 / 3, 2 / 3]) {
      if ((u - t).abs() < 0.02) u = t;
    }
    uv = Offset(u, v);
    widget.controller.setEdgeShape(edge.key, (s) => first ? s.copyWith(c1: uv) : s.copyWith(c2: uv));
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final edges = c.sharedEdges;
    final shapes = c.project.layout.edgeMap;
    SharedEdge? selected;
    for (final e in edges) {
      if (e.key == c.selectedEdgeKey) selected = e;
    }
    const hit = 44.0;
    final l = context.l10n;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned.fill(
          child: IgnorePointer(
            child: CustomPaint(
              painter: _EdgeGuidePainter(
                edges: [
                  for (final e in edges) (_px(e.p), _px(e.q), shapes[e.key], e.key == c.selectedEdgeKey),
                ],
                accent: context.colors.amber,
                quiet: Colors.white.withValues(alpha: 0.7),
              ),
            ),
          ),
        ),
        for (final e in edges)
          if (e.key != c.selectedEdgeKey)
            Positioned(
              left: edgeMidpoint(_px(e.p), _px(e.q), shapes[e.key]).dx - hit / 2,
              top: edgeMidpoint(_px(e.p), _px(e.q), shapes[e.key]).dy - hit / 2,
              child: Semantics(
                button: true,
                label: l.t('edgeSelect'),
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    HapticFeedback.selectionClick();
                    c.selectEdge(e.key);
                  },
                  child: SizedBox(
                    width: hit,
                    height: hit,
                    child: Center(
                      child: Container(
                        width: 18,
                        height: 18,
                        decoration: BoxDecoration(
                          color: context.colors.surface,
                          shape: BoxShape.circle,
                          border: Border.all(color: context.colors.amber, width: 2),
                          boxShadow: Shadows.e1,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        if (selected != null)
          for (final first in const [true, false])
            Builder(builder: (context) {
              final edge = selected!;
              final shape = c.edgeShape(edge.key);
              final at = edgePoint(_px(edge.p), _px(edge.q), first ? shape.c1 : shape.c2);
              return Positioned(
                left: at.dx - hit / 2,
                top: at.dy - hit / 2,
                child: Semantics(
                  label: l.t(first ? 'edgeControl1' : 'edgeControl2'),
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onPanStart: (_) => HapticFeedback.selectionClick(),
                    onPanUpdate: (d) => _drag(edge, first, d.globalPosition),
                    child: SizedBox(
                      width: hit,
                      height: hit,
                      child: Center(
                        child: Container(
                          width: 24,
                          height: 24,
                          decoration: BoxDecoration(
                            color: context.colors.amber,
                            shape: BoxShape.circle,
                            border: Border.all(color: context.colors.onAmber, width: 2),
                            boxShadow: Shadows.focusGlow,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              );
            }),
      ],
    );
  }
}

/// Draws every shareable edge as a thin line, and the selected one in amber
/// with its Bézier control arms.
class _EdgeGuidePainter extends CustomPainter {
  _EdgeGuidePainter({required this.edges, required this.accent, required this.quiet});
  final List<(Offset, Offset, EdgeShape?, bool)> edges;
  final Color accent;
  final Color quiet;

  @override
  void paint(Canvas canvas, Size size) {
    for (final (p, q, shape, selected) in edges) {
      final path = Path()..moveTo(p.dx, p.dy);
      if (shape == null || shape.isStraight) {
        path.lineTo(q.dx, q.dy);
      } else {
        appendShapedEdge(path, p, q, shape, false);
      }
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = selected ? 2.5 : 1.2
        ..color = selected ? accent : quiet;
      canvas.drawPath(path, paint);
      if (selected) {
        final s = shape ?? const EdgeShape(a: '', b: '');
        final arm = Paint()
          ..strokeWidth = 1
          ..color = accent.withValues(alpha: 0.8);
        canvas.drawLine(p, edgePoint(p, q, s.c1), arm);
        canvas.drawLine(q, edgePoint(p, q, s.c2), arm);
      }
    }
  }

  @override
  bool shouldRepaint(_EdgeGuidePainter old) => true;
}

/// Thin guide lines at the canvas fractions an element is snapped to.
class _GuidePainter extends CustomPainter {
  _GuidePainter({required this.x, required this.y, required this.color});
  final double? x;
  final double? y;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = color
      ..strokeWidth = 1;
    if (x != null) canvas.drawLine(Offset(x! * size.width, 0), Offset(x! * size.width, size.height), p);
    if (y != null) canvas.drawLine(Offset(0, y! * size.height), Offset(size.width, y! * size.height), p);
  }

  @override
  bool shouldRepaint(_GuidePainter old) => old.x != x || old.y != y || old.color != color;
}

/// Touch framing for one slot photo: tap selects, drag repositions, pinch
/// zooms, double-tap recentres. It only mutates [SlotFill]'s pan/zoom, which the
/// export renders through the exact same widget — so what you frame is what gets
/// saved. Live only while the slot is selected ([enabled]); the wrapper itself
/// is always in the tree so selecting a slot never rebuilds the photo.
class _SlotFrameGesture extends StatefulWidget {
  const _SlotFrameGesture({
    required this.controller,
    required this.slotId,
    required this.interactive,
    required this.enabled,
    required this.child,
  });

  final EditorController controller;
  final String slotId;
  final bool interactive;

  /// Whether pan/zoom is live: the slot is selected and holds a photo.
  final bool enabled;
  final Widget child;

  @override
  State<_SlotFrameGesture> createState() => _SlotFrameGestureState();
}

class _SlotFrameGestureState extends State<_SlotFrameGesture> {
  double _baseZoom = 1;
  double _baseOffX = 0;
  double _baseOffY = 0;
  double _baseRotation = 0;
  Offset _pan = Offset.zero; // accumulated finger travel, in cell pixels

  void _onStart(ScaleStartDetails d) {
    final f = widget.controller.fillFor(widget.slotId);
    if (f == null) return;
    _baseZoom = f.zoom;
    _baseOffX = f.offsetX;
    _baseOffY = f.offsetY;
    _baseRotation = f.rotation;
    _pan = Offset.zero;
  }

  void _onUpdate(ScaleUpdateDetails d, Size cell) {
    final c = widget.controller;
    final f = c.fillFor(widget.slotId);
    if (f == null || cell.isEmpty) return;
    // Two-finger twist tilts the photo inside its cell.
    if (d.pointerCount >= 2) c.setSlotRotation(widget.slotId, _baseRotation + d.rotation);
    // Pan in the photo's own (rotated) frame so it stays under the finger.
    final r = -f.rotation;
    final delta = d.focalPointDelta;
    _pan += Offset(
      delta.dx * math.cos(r) - delta.dy * math.sin(r),
      delta.dx * math.sin(r) + delta.dy * math.cos(r),
    );
    final zoom = (_baseZoom * d.scale).clamp(1.0, 4.0);
    final (ow, oh) = _coverOverflow(cell, f.imgAspect);
    // Map finger travel onto the photo's available slack: dragging keeps the
    // photo under the finger, and a scale-independent 2/(zoom·overflow) keeps
    // the feel the same at any zoom. An axis with no slack simply doesn't pan.
    final offX = ow > 0.5 ? _baseOffX - 2 * _pan.dx / (zoom * ow) : _baseOffX;
    final offY = oh > 0.5 ? _baseOffY - 2 * _pan.dy / (zoom * oh) : _baseOffY;
    c.setSlotTransform(widget.slotId, offX: offX, offY: offY, zoom: zoom);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final cell = constraints.biggest;
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.interactive
              ? () {
                  if (widget.controller.completeSwapIfActive(widget.slotId)) return;
                  widget.controller.selectSlot(widget.slotId);
                }
              : null,
          onDoubleTap: widget.enabled
              ? () => widget.controller.resetSlotTransform(widget.slotId)
              : null,
          onScaleStart: widget.enabled ? _onStart : null,
          onScaleUpdate: widget.enabled ? (d) => _onUpdate(d, cell) : null,
          child: widget.child,
        );
      },
    );
  }
}

/// The un-zoomed overflow of a `BoxFit.cover` photo (of aspect [aspect]) beyond
/// [cell], per axis. One axis is always zero — the photo already fits there.
(double, double) _coverOverflow(Size cell, double aspect) {
  if (cell.isEmpty) return (0, 0);
  final a = aspect > 0 ? aspect : cell.aspectRatio;
  if (a >= cell.aspectRatio) return (cell.height * a - cell.width, 0);
  return (0, cell.width / a - cell.height);
}

class _SlotView extends StatelessWidget {
  const _SlotView({
    required this.controller,
    required this.slotId,
    required this.unit,
    required this.radius,
    required this.thickness,
    required this.borderColor,
    required this.interactive,
    this.onEditSlot,
  });

  final EditorController controller;
  final String slotId;
  final double unit; // canvas pixels per 1/1000 of canvas width
  final double radius;
  final double thickness;
  final Color borderColor;
  final bool interactive;
  final void Function(String slotId)? onEditSlot;

  @override
  Widget build(BuildContext context) {
    // effectiveFill honours any live drag-swap or replace preview.
    final fill = controller.effectiveFill(slotId);
    final realFill = controller.fillFor(slotId);
    final selected = controller.selectedSlotId == slotId;
    final swapTarget = controller.swapSource != null && controller.swapSource != slotId;
    final br = BorderRadius.circular(radius);

    // Polaroid: the photo sits on a card with a deeper bottom edge. The card
    // container is always built so the photo keeps its ancestors.
    final polaroid = fill != null && fill.frameStyle == FrameStyle.polaroid;
    final card = math.max(fill?.frameWidth ?? 0.0, 10.0) * unit;
    Widget content = fill != null
        ? Container(
            color: polaroid ? (fill.frameWidth > 0 ? fill.frameColor : const Color(0xFFFDFBF7)) : null,
            padding: polaroid ? EdgeInsets.fromLTRB(card, card, card, card * 3.2) : EdgeInsets.zero,
            child: ClipPath(
            clipper: _SlotClipper(
              radius: radius,
              mask: fill.mask,
              torn: fill.frameStyle == FrameStyle.torn,
              seed: slotId.hashCode,
            ),
            child: Stack(
              fit: StackFit.expand,
              children: [
                _RotatedCover(
                  rotation: fill.rotation,
                  child: Transform.scale(
                    scale: fill.zoom,
                    child: filteredPhoto(
                      fill,
                      alignment: Alignment(fill.offsetX, fill.offsetY),
                    ),
                  ),
                ),
                // Overlays come after the photo so toggling them never moves it.
                if (fill.filter.vignette > 0) _Vignette(strength: fill.filter.vignette),
              ],
            ),
          ),
          )
        : DottedSlot(radius: radius);

    // From here to the returned widget the ancestor chain of the photo is kept
    // identical in the editor and during export. Export merely makes the
    // handlers inert and drops the overlay siblings; it must never wrap the
    // photo in a different tree, or the photo widgets would be rebuilt, lose
    // their already-decoded frame, and come out blank in the saved PNG.
    // The frame line belongs to the plain style; polaroid uses it as card colour.
    final frame = fill != null && fill.frameStyle == FrameStyle.plain && fill.mask == 'none'
        ? fill.frameWidth * unit
        : 0.0;
    Widget core = Container(
      decoration: BoxDecoration(
        borderRadius: br,
        border: thickness > 0 ? Border.all(color: borderColor, width: thickness) : null,
        boxShadow: fill != null && fill.shadow ? _cellShadow(unit) : null,
      ),
      // This photo's own frame, drawn over its edges.
      foregroundDecoration: frame > 0
          ? BoxDecoration(
              borderRadius: br,
              border: Border.all(color: fill!.frameColor, width: frame),
            )
          : null,
      child: content,
    );

    // Tap selects; once selected, drag repositions and pinch zooms the photo
    // (see [_SlotFrameGesture]). The wrapper is always present so selecting a
    // slot never changes the photo's ancestors.
    core = _SlotFrameGesture(
      controller: controller,
      slotId: slotId,
      interactive: interactive,
      // No framing while a replace preview is up — the visible photo is the
      // candidate, so a pan would silently edit the hidden original.
      enabled: interactive &&
          selected &&
          realFill != null &&
          controller.replaceSlotId == null,
      child: core,
    );

    // A filled slot can be dragged with an immediate (non-long-press) drag.
    if (realFill != null) {
      core = Draggable<String>(
        data: slotId,
        // While selected, dragging frames the photo instead of swapping, so the
        // swap drag is suspended (the Swap chip + tap still work).
        maxSimultaneousDrags: interactive && !selected ? null : 0,
        onDragStarted: interactive ? () => controller.startSlotDrag(slotId) : null,
        onDragEnd: interactive ? (_) => controller.endSlotDrag() : null,
        onDraggableCanceled: interactive ? (_, __) => controller.endSlotDrag() : null,
        feedback: Opacity(
          opacity: 0.9,
          child: SizedBox(
            width: 110,
            height: 110,
            child: ClipRRect(
              borderRadius: br,
              child: PhotoImage(assetId: realFill.assetId, full: !realFill.isVideo, fit: BoxFit.cover),
            ),
          ),
        ),
        childWhenDragging: Opacity(opacity: 0.25, child: core),
        child: core,
      );
    }

    // Selected / swap-target highlight — always wrapped (an empty decoration
    // when idle) so the photo below keeps its place in the widget tree.
    core = Container(
      decoration: selected || swapTarget
          ? BoxDecoration(
              borderRadius: br,
              border: Border.all(
                color: swapTarget ? context.colors.amberBright : context.colors.amber,
                width: swapTarget ? 3 : 2,
              ),
              boxShadow: selected ? Shadows.focusGlow : null,
            )
          : const BoxDecoration(),
      child: core,
    );

    // Drop target for drag-to-swap, with live preview via updateSlotDragOver.
    final dropTarget = DragTarget<String>(
      onWillAcceptWithDetails: interactive ? (d) => d.data != slotId : null,
      onMove: interactive ? (_) => controller.updateSlotDragOver(slotId) : null,
      onLeave: interactive
          ? (_) {
              if (controller.dragOverSlot == slotId) controller.updateSlotDragOver(null);
            }
          : null,
      onAcceptWithDetails: interactive
          ? (d) {
              controller.swapSlots(d.data, slotId);
              controller.endSlotDrag();
            }
          : null,
      builder: (context, candidate, rejected) => core,
    );

    // Chrome (the edit badge) rides above the photo as a sibling, so adding or
    // removing it never touches the photo subtree. The selected photo's
    // actions live in the editor's bottom context bar, not on the photo.
    final overlays = <Widget>[
      if (interactive && realFill != null && !selected && controller.dragSourceSlot == null)
        Positioned(
          right: 0,
          bottom: 0,
          child: _EditBadge(onTap: () => onEditSlot?.call(slotId)),
        ),
    ];

    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned.fill(child: dropTarget),
        // Scrapbook tape across the top corners (rendered in export too).
        if (fill != null && fill.frameStyle == FrameStyle.tape)
          Positioned.fill(child: IgnorePointer(child: _Tape(unit: unit))),
        ...overlays,
      ],
    );
  }
}

/// The pencil on a filled, unselected photo. It is a real button (a 44dp
/// target around a small visual) that selects the photo and opens its
/// controls — before, it was a decoration that swallowed the tap.
class _EditBadge extends StatelessWidget {
  const _EditBadge({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: context.l10n.t('editPhoto'),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: SizedBox(
          width: 44,
          height: 44,
          child: Align(
            alignment: Alignment.bottomRight,
            child: Container(
              margin: const EdgeInsets.all(4),
              width: 26,
              height: 26,
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.5),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white.withValues(alpha: 0.6)),
              ),
              child: const Icon(Icons.edit_rounded, size: 14, color: Colors.white),
            ),
          ),
        ),
      ),
    );
  }
}

/// Empty-slot placeholder: dashed frame + plus, inviting a photo.
class DottedSlot extends StatelessWidget {
  const DottedSlot({super.key, required this.radius});
  final double radius;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: context.colors.surfaceInput,
        borderRadius: BorderRadius.circular(radius),
      ),
      child: Center(
        child: Icon(Icons.add_photo_alternate_outlined, color: context.colors.textLo, size: 28),
      ),
    );
  }
}

/// A polygon (diagonal / mosaic) photo cell. Mirrors [_SlotView]'s interaction
/// but clips to an arbitrary convex polygon. The [ClipPath] gates hit-testing,
/// so taps in the bounding-box corners fall through to the cell behind — which
/// is what lets overlapping diagonal cells select the right photo. The border,
/// selection ring, edit badge and action chips are unclipped overlays anchored
/// to the polygon centroid so they stay visible on narrow triangular cells.
class _PolySlotView extends StatelessWidget {
  const _PolySlotView({
    required this.controller,
    required this.slotId,
    required this.unit,
    required this.polygon,
    required this.thickness,
    required this.borderColor,
    required this.interactive,
    this.outline,
    this.onEditSlot,
  });

  final EditorController controller;
  final String slotId;
  final List<Offset> polygon; // local (box-relative) pixels
  final double unit; // canvas pixels per 1/1000 of canvas width
  final double thickness;
  final Color borderColor;
  final bool interactive;

  /// The cell outline when some of its edges are curved or zigzagged (local
  /// pixels); null for a plain polygon.
  final Path? outline;
  final void Function(String slotId)? onEditSlot;

  Widget _innerVisual(BuildContext context, SlotFill? fill) {
    if (fill == null) {
      return ColoredBox(
        color: context.colors.surfaceInput,
        child: Center(
          child: Icon(Icons.add_photo_alternate_outlined,
              color: context.colors.textLo, size: 26),
        ),
      );
    }
    return Stack(
      fit: StackFit.expand,
      children: [
        _RotatedCover(
          rotation: fill.rotation,
          child: Transform.scale(
            scale: fill.zoom,
            child: filteredPhoto(fill, alignment: Alignment(fill.offsetX, fill.offsetY)),
          ),
        ),
        if (fill.filter.vignette > 0) _Vignette(strength: fill.filter.vignette),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final fill = controller.effectiveFill(slotId);
    final realFill = controller.fillFor(slotId);
    final selected = controller.selectedSlotId == slotId;
    final swapTarget = controller.swapSource != null && controller.swapSource != slotId;
    final centroid = polygonCentroid(polygon);
    final polaroid = fill != null && fill.frameStyle == FrameStyle.polaroid;
    final card = polaroid ? math.max(fill.frameWidth, 10.0) * unit : 0.0;
    final clipper = _PolyCellClipper(
      points: polygon,
      outline: outline,
      mask: fill?.mask ?? 'none',
      torn: fill != null && fill.frameStyle == FrameStyle.torn,
      inset: card,
      seed: slotId.hashCode,
    );

    final visual = _innerVisual(context, fill);

    // The photo sits under the same DragTarget / gesture chain in both the
    // editor and export; export only makes the handlers inert (see _SlotView),
    // so the cell's photo is never rebuilt and never loses its decoded frame.
    final core = ClipPath(
      clipper: clipper,
      child: DragTarget<String>(
        onWillAcceptWithDetails: interactive ? (d) => d.data != slotId : null,
        onMove: interactive ? (_) => controller.updateSlotDragOver(slotId) : null,
        onLeave: interactive
            ? (_) {
                if (controller.dragOverSlot == slotId) controller.updateSlotDragOver(null);
              }
            : null,
        onAcceptWithDetails: interactive
            ? (d) {
                controller.swapSlots(d.data, slotId);
                controller.endSlotDrag();
              }
            : null,
        builder: (context, candidate, rejected) {
          final child = _SlotFrameGesture(
            controller: controller,
            slotId: slotId,
            interactive: interactive,
            // No framing while a replace preview is up (see _SlotView).
            enabled: interactive &&
                selected &&
                realFill != null &&
                controller.replaceSlotId == null,
            child: visual,
          );
          if (realFill == null) return child;
          return Draggable<String>(
            data: slotId,
            // Selected cell: drag frames the photo, so suspend the swap drag.
            maxSimultaneousDrags: interactive && !selected ? null : 0,
            onDragStarted: interactive ? () => controller.startSlotDrag(slotId) : null,
            onDragEnd: interactive ? (_) => controller.endSlotDrag() : null,
            onDraggableCanceled: interactive ? (_, __) => controller.endSlotDrag() : null,
            feedback: Opacity(
              opacity: 0.9,
              child: SizedBox(
                width: 110,
                height: 110,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: PhotoImage(assetId: realFill.assetId, full: !realFill.isVideo, fit: BoxFit.cover),
                ),
              ),
            ),
            childWhenDragging: Opacity(opacity: 0.25, child: visual),
            child: child,
          );
        },
      ),
    );

    // The frame line belongs to the plain style without a shape mask.
    final frame = fill != null && fill.frameStyle == FrameStyle.plain && fill.mask == 'none'
        ? fill.frameWidth * unit
        : 0.0;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        // Drop shadow under the cell. Always present (painting nothing when
        // off) so the photo below keeps its position among the children.
        Positioned.fill(
          child: IgnorePointer(
            child: CustomPaint(
              painter: _PolyShadowPainter(
                points: polygon,
                outline: outline,
                elevation: fill != null && fill.shadow ? 10 * unit : 0,
                // Polaroid: the card shows around the inset photo.
                cardColor: polaroid ? (fill.frameWidth > 0 ? fill.frameColor : const Color(0xFFFDFBF7)) : null,
              ),
            ),
          ),
        ),
        Positioned.fill(child: core),
        // Scrapbook tape over the cell's top-most corners.
        if (fill != null && fill.frameStyle == FrameStyle.tape)
          Positioned.fill(child: IgnorePointer(child: _PolyTape(points: polygon, unit: unit))),
        // This photo's own frame.
        if (frame > 0)
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(
                painter: PolygonBorderPainter(
                    points: polygon, outline: outline, color: fill!.frameColor, strokeWidth: frame),
              ),
            ),
          ),
        // Border stroke along the polygon edges.
        if (thickness > 0)
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(
                painter: PolygonBorderPainter(
                    points: polygon, outline: outline, color: borderColor, strokeWidth: thickness),
              ),
            ),
          ),
        // Selection / swap-target highlight (amber edge).
        if (interactive && (selected || swapTarget))
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(
                painter: PolygonBorderPainter(
                  points: polygon,
                  outline: outline,
                  color: swapTarget ? context.colors.amberBright : context.colors.amber,
                  strokeWidth: swapTarget ? 3 : 2.5,
                ),
              ),
            ),
          ),
        // Edit badge on a filled, unselected cell (a real button).
        if (interactive && realFill != null && !selected && controller.dragSourceSlot == null)
          Positioned(
            left: centroid.dx,
            top: centroid.dy,
            child: FractionalTranslation(
              translation: const Offset(-0.5, -0.5),
              child: _EditBadge(onTap: () => onEditSlot?.call(slotId)),
            ),
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Overlay elements
// ---------------------------------------------------------------------------

class _ElementView extends StatefulWidget {
  const _ElementView({
    super.key,
    required this.controller,
    required this.element,
    required this.canvas,
    required this.interactive,
    this.onTrashed,
    this.isOverTrash,
  });

  final EditorController controller;
  final CanvasElement element;
  final Size canvas;
  final bool interactive;
  final void Function(String id)? onTrashed;
  final bool Function(Offset globalPosition)? isOverTrash;

  @override
  State<_ElementView> createState() => _ElementViewState();
}

class _ElementViewState extends State<_ElementView> {
  final _boxKey = GlobalKey();
  double _baseScale = 1;
  double _baseRotation = 0;
  // Unsnapped finger position, so a snapped element can be pulled free again.
  double _rawCx = 0;
  double _rawCy = 0;
  double _handleBaseScale = 1;
  double _handleBaseRotation = 0;
  double _handleBaseAngle = 0;
  double _handleBaseDist = 1;
  // Adjust photo (image inside the frame).
  double _basePanX = 0;
  double _basePanY = 0;
  double _baseZoom = 1;
  Offset _imgTravel = Offset.zero;
  // Frame side handles.
  double _sideBaseScale = 1;
  double _sideBaseAspect = 1;
  double _sideTravel = 0;

  Offset _center() {
    final rb = _boxKey.currentContext?.findRenderObject() as RenderBox?;
    if (rb == null) return Offset.zero;
    return rb.localToGlobal(rb.size.center(Offset.zero));
  }

  @override
  Widget build(BuildContext context) {
    final e = widget.element;
    final c = widget.controller;
    final W = widget.canvas.width;
    final H = widget.canvas.height;
    final selected = c.selectedElementId == e.id;

    final child = _content(e, W);
    final dragging = c.draggingElementId == e.id;
    final doomed = dragging && c.overTrash;

    // The gesture wrapper and highlight container are always present (handlers
    // just go inert while exporting) so the element — a photo in particular —
    // keeps the same ancestors and never loses its decoded frame (see _SlotView).
    //
    // The hit area is the element's whole box plus a transparent margin
    // ([_hitPad]), and it is opaque: a touch on a text's padding, between its
    // letters or just beside a thin sticker selects that element and never
    // falls through to the photo underneath.
    final gestured = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.interactive ? () => c.selectElement(e.id) : null,
      onDoubleTap: widget.interactive && e is ImageElement && !e.isPlaceholder
          ? () {
              HapticFeedback.selectionClick();
              c.selectElement(e.id);
              c.setAdjustingImage(c.adjustingImageId == e.id ? null : e.id);
            }
          : null,
      onScaleStart: widget.interactive
          ? (_) {
              _baseScale = e.scale;
              _baseRotation = e.rotation;
              _rawCx = e.cx;
              _rawCy = e.cy;
              if (e is ImageElement) {
                _basePanX = e.panX;
                _basePanY = e.panY;
                _baseZoom = e.zoom;
                _imgTravel = Offset.zero;
              }
              c.selectElement(e.id);
            }
          : null,
      onScaleUpdate: widget.interactive
          ? (d) {
              // Adjust photo: the image moves inside a frame that stays put.
              if (e is ImageElement && c.adjustingImageId == e.id) {
                final r = -e.rotation;
                final fd = d.focalPointDelta;
                _imgTravel += Offset(fd.dx * math.cos(r) - fd.dy * math.sin(r), fd.dx * math.sin(r) + fd.dy * math.cos(r));
                final zoom = d.pointerCount >= 2 ? (_baseZoom * d.scale).clamp(1.0, ImageElement.maxZoom) : e.zoom;
                final probe = e.clone()..zoom = zoom;
                final o = PhotoLayerGeometry.of(probe, e.naturalWidthFrac * W * e.scale).overflow;
                c.setImageFraming(
                  e.id,
                  panX: o.width > 0.5 ? _basePanX - 2 * _imgTravel.dx / o.width : e.panX,
                  panY: o.height > 0.5 ? _basePanY - 2 * _imgTravel.dy / o.height : e.panY,
                  zoom: zoom,
                );
                return;
              }
              _rawCx += d.focalPointDelta.dx / W;
              _rawCy += d.focalPointDelta.dy / H;
              final (cx, cy) = c.snapPosition(e.id, _rawCx, _rawCy);
              c.updateTransform(
                e.id,
                cx: cx,
                cy: cy,
                scale: d.pointerCount >= 2 ? _baseScale * d.scale : null,
                rotation: d.pointerCount >= 2 ? _baseRotation + d.rotation : null,
              );
              // A one-finger move reveals the trash; two fingers transform.
              if (d.pointerCount == 1 && d.focalPointDelta.distance > 0) {
                c.beginElementDrag(e.id);
                final over = widget.isOverTrash?.call(d.focalPoint) ?? false;
                if (over != c.overTrash) {
                  HapticFeedback.selectionClick();
                  c.setOverTrash(over);
                }
              }
            }
          : null,
      onScaleEnd: widget.interactive
          ? (_) {
              if (e is ImageElement && c.adjustingImageId == e.id) return;
              c.clearGuides();
              if (c.endElementDrag()) widget.onTrashed?.call(e.id);
            }
          : null,
      child: Padding(padding: const EdgeInsets.all(_hitPad), child: child),
    );

    final adjusting = e is ImageElement && c.adjustingImageId == e.id;
    final boxed = Container(
      key: _boxKey,
      decoration: selected && !dragging
          ? BoxDecoration(
              border: Border.all(
                color: adjusting ? context.colors.amberBright : context.colors.amber,
                width: adjusting ? 2.5 : 1.5,
              ),
              boxShadow: adjusting ? null : Shadows.focusGlow,
            )
          : const BoxDecoration(),
      child: gestured,
    );

    final showHandles = widget.interactive && selected && !dragging;
    const h = _handleHit / 2;
    final frameHandles = showHandles && e is ImageElement && !adjusting && c.editingMaskId != e.id;
    final maskHandles = showHandles && e is ImageElement && c.editingMaskId == e.id && e.maskPoints != null;

    return Positioned(
      left: e.cx * W,
      top: e.cy * H,
      // Locked layers let touches through to what lies below. Always in
      // the tree so locking never rebuilds the layer.
      child: IgnorePointer(
        ignoring: e.locked,
        child: FractionalTranslation(
        translation: const Offset(-0.5, -0.5),
        child: Transform.rotate(
          angle: e.rotation,
          child: AnimatedOpacity(
            // Over the trash the element fades and shrinks: "release to delete".
            opacity: doomed ? 0.45 : 1,
            duration: Motion.fast,
            child: AnimatedScale(
              scale: doomed ? 0.7 : 1,
              duration: Motion.fast,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  boxed,
                  if (showHandles) ...[
                    // Delete handle (top-left, danger). Dragging to the trash
                    // and the Delete action in the bar do the same, so this
                    // is a shortcut, not the only way.
                    Positioned(
                      left: _hitPad - h,
                      top: _hitPad - h,
                      child: _Handle(
                        icon: Icons.close_rounded,
                        color: context.colors.danger,
                        iconColor: context.colors.onDanger,
                        semantics: context.l10n.t('ctxDelete'),
                        onTap: () => widget.onTrashed?.call(e.id),
                      ),
                    ),
                    // Scale + rotate handle (bottom-right)
                    Positioned(
                      right: _hitPad - h,
                      bottom: _hitPad - h,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onPanStart: (details) {
                          final center = _center();
                          final v = details.globalPosition - center;
                          _handleBaseScale = e.scale;
                          _handleBaseRotation = e.rotation;
                          _handleBaseAngle = v.direction;
                          _handleBaseDist = v.distance == 0 ? 1 : v.distance;
                        },
                        onPanUpdate: (details) {
                          final center = _center();
                          final v = details.globalPosition - center;
                          final scale = _handleBaseScale * (v.distance / _handleBaseDist);
                          var rot = _handleBaseRotation + (v.direction - _handleBaseAngle);
                          // Snap to straight / right angles within ~4°.
                          const snap = 0.07;
                          final quarter = (rot / (math.pi / 2)).roundToDouble() * (math.pi / 2);
                          if ((rot - quarter).abs() < snap) rot = quarter;
                          c.updateTransform(e.id, scale: scale, rotation: rot);
                        },
                        child: _Handle(
                          icon: Icons.open_in_full_rounded,
                          color: context.colors.surface,
                          iconColor: context.colors.amber,
                          semantics: context.l10n.t('resizeRotate'),
                        ),
                      ),
                    ),
                    // Frame sides: stretch the frame (a circle into an oval)
                    // without distorting the photo inside it.
                    if (frameHandles) ...[
                      Positioned(
                        right: _hitPad - h,
                        top: 0,
                        bottom: 0,
                        child: Center(child: _sideHandle(context, c, e, horizontal: true)),
                      ),
                      Positioned(
                        bottom: _hitPad - h,
                        left: 0,
                        right: 0,
                        child: Center(child: _sideHandle(context, c, e, horizontal: false)),
                      ),
                    ],
                    if (maskHandles) ..._maskHandles(context, c, e, W),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
      ),
    );
  }

  /// A small pill on the right or bottom side of a photo frame; dragging it
  /// changes the frame's proportions along that axis only.
  Widget _sideHandle(BuildContext context, EditorController c, ImageElement e, {required bool horizontal}) {
    return Semantics(
      label: context.l10n.t(horizontal ? 'frameWidthHandle' : 'frameHeightHandle'),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanStart: (_) {
          _sideBaseScale = e.scale;
          _sideBaseAspect = e.aspectRatio;
          _sideTravel = 0;
        },
        onPanUpdate: (d) {
          // Into the frame's own (rotated) axes.
          final r = -e.rotation;
          final local = Offset(d.delta.dx * math.cos(r) - d.delta.dy * math.sin(r), d.delta.dx * math.sin(r) + d.delta.dy * math.cos(r));
          _sideTravel += horizontal ? local.dx : local.dy;
          final w0 = e.naturalWidthFrac * widget.canvas.width * _sideBaseScale;
          final h0 = w0 / _sideBaseAspect;
          if (horizontal) {
            // The frame grows from its centre: both sides move.
            final w1 = math.max(24.0, w0 + 2 * _sideTravel);
            c.setFrameAspect(e.id, w1 / h0, scale: _sideBaseScale * w1 / w0);
          } else {
            final h1 = math.max(24.0, h0 + 2 * _sideTravel);
            c.setFrameAspect(e.id, w0 / h1);
          }
        },
        child: SizedBox(
          width: _handleHit,
          height: _handleHit,
          child: Center(
            child: Container(
              width: horizontal ? 10 : 26,
              height: horizontal ? 26 : 10,
              decoration: BoxDecoration(
                color: context.colors.surface,
                borderRadius: BorderRadius.circular(Radii.pill),
                border: Border.all(color: context.colors.amber, width: 1.5),
                boxShadow: Shadows.e1,
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Point handles of a custom mask, laid out in the frame's own space (this
  /// Stack is already rotated with the element), plus a "+" between points.
  List<Widget> _maskHandles(BuildContext context, EditorController c, ImageElement e, double canvasW) {
    final pts = e.maskPoints!;
    final g = PhotoLayerGeometry.of(e, e.naturalWidthFrac * canvasW * e.scale);
    Offset at(Offset p) => Offset(_hitPad + p.dx * g.frame.width, _hitPad + p.dy * g.frame.height);
    Offset? frac(Offset global) {
      final box = _boxKey.currentContext?.findRenderObject() as RenderBox?;
      if (box == null) return null;
      final l = box.globalToLocal(global) - const Offset(_hitPad, _hitPad);
      return Offset(l.dx / g.frame.width, l.dy / g.frame.height);
    }

    const hit = 36.0;
    final l10n = context.l10n;
    return [
      for (var i = 0; i < pts.length; i++)
        if ((at(pts[i]) - at(pts[(i + 1) % pts.length])).distance > 40)
          Positioned(
            left: (at(pts[i]) + at(pts[(i + 1) % pts.length])).dx / 2 - hit / 2,
            top: (at(pts[i]) + at(pts[(i + 1) % pts.length])).dy / 2 - hit / 2,
            child: Semantics(
              button: true,
              label: l10n.t('cutAddPoint'),
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => c.insertMaskPoint(e.id, i),
                child: SizedBox(
                  width: hit,
                  height: hit,
                  child: Center(
                    child: Container(
                      width: 14,
                      height: 14,
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.35),
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white.withValues(alpha: 0.8)),
                      ),
                      child: const Icon(Icons.add_rounded, size: 10, color: Colors.white),
                    ),
                  ),
                ),
              ),
            ),
          ),
      for (var i = 0; i < pts.length; i++)
        Positioned(
          left: at(pts[i]).dx - hit / 2,
          top: at(pts[i]).dy - hit / 2,
          child: Semantics(
            label: l10n.a('cutPointOf', {'n': '${i + 1}', 'total': '${pts.length}'}),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onLongPress: pts.length > 3
                  ? () {
                      HapticFeedback.mediumImpact();
                      c.removeMaskPoint(e.id, i);
                    }
                  : null,
              onPanUpdate: (d) {
                final f = frac(d.globalPosition);
                if (f != null) c.moveMaskPoint(e.id, i, f);
              },
              child: SizedBox(
                width: hit,
                height: hit,
                child: Center(
                  child: Container(
                    width: 16,
                    height: 16,
                    decoration: BoxDecoration(
                      color: context.colors.amber,
                      shape: BoxShape.circle,
                      border: Border.all(color: context.colors.onAmber, width: 2),
                      boxShadow: Shadows.e1,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
    ];
  }

  /// Transparent touch margin around every element (canvas pixels).
  static const double _hitPad = 12;

  /// Touch size of the corner handles.
  static const double _handleHit = 44;

  Widget _content(CanvasElement e, double canvasW) {
    switch (e) {
      case StickerElement s:
        final w = s.naturalWidthFrac * canvasW * s.scale;
        return SizedBox(
          width: w,
          height: w,
          child: StickerImage(source: s.assetPath),
        );
      case ShapeElement s:
        final w = s.naturalWidthFrac * canvasW * s.scale;
        return SizedBox(
          width: w,
          height: w,
          child: CustomPaint(
            painter: ShapePainter(
              kind: s.shapeKind,
              fill: s.fill,
              stroke: s.stroke,
              strokeWidth: s.strokeWidth,
            ),
          ),
        );
      case EmojiElement em:
        final fs = 0.18 * canvasW * em.scale;
        return Text(em.emoji, style: TextStyle(fontSize: fs));
      case GifElement g:
        final w = g.naturalWidthFrac * canvasW * g.scale;
        return SizedBox(
          width: w,
          height: w / g.aspectRatio,
          child: Image.network(g.url, fit: BoxFit.contain, gaplessPlayback: true),
        );
      case ImageElement im:
        return PhotoLayerView(element: im, width: im.naturalWidthFrac * canvasW * im.scale, unit: canvasW / 1000);
      case DrawingElement d:
        final w = d.naturalWidthFrac * canvasW * d.scale;
        return SizedBox(
          width: w,
          height: w / d.aspectRatio,
          child: CustomPaint(painter: DrawingPainter(d.strokes)),
        );
      case TextElement t:
        final fs = 0.09 * canvasW * t.scale;
        final align = switch (t.align) {
          TextAlignH.left => TextAlign.left,
          TextAlignH.center => TextAlign.center,
          TextAlignH.right => TextAlign.right,
        };
        final base = AppFonts.style(t.fontKey, fontSize: fs, color: t.color, bold: t.bold, italic: t.italic)
            .copyWith(letterSpacing: t.letterSpacing / 100 * fs);
        final shadows = t.shadow
            ? [
                Shadow(
                  color: Colors.black.withValues(alpha: 0.55),
                  blurRadius: fs * 0.12,
                  offset: Offset(0, fs * 0.04),
                ),
              ]
            : null;
        // An outline is a stroked copy of the same text laid under the fill.
        final stroke = t.outline != null && t.outlineWidth > 0
            ? base.copyWith(
                foreground: Paint()
                  ..style = PaintingStyle.stroke
                  ..strokeJoin = StrokeJoin.round
                  ..strokeWidth = t.outlineWidth / 1000 * canvasW * t.scale * 2
                  ..color = t.outline!,
              )
            : null;
        Widget text;
        if (t.curve != 0) {
          text = _CurvedText(
            text: t.text,
            style: base.copyWith(shadows: shadows),
            strokeStyle: stroke,
            gradientEnd: t.gradientEnd,
            curve: t.curve,
          );
        } else {
          final grad = t.gradientEnd;
          text = Stack(
            children: [
              if (stroke != null) Text(t.text, textAlign: align, style: stroke),
              // With a gradient the shadow gets its own layer, so the mask
              // below tints only the letters, not their shadow.
              if (grad != null && shadows != null)
                Text(t.text, textAlign: align, style: base.copyWith(color: Colors.transparent, shadows: shadows)),
              if (grad != null)
                ShaderMask(
                  blendMode: BlendMode.srcIn,
                  shaderCallback: (r) => LinearGradient(colors: [t.color, grad]).createShader(r),
                  child: Text(t.text, textAlign: align, style: base),
                )
              else
                Text(t.text, textAlign: align, style: base.copyWith(shadows: shadows)),
            ],
          );
        }
        return Container(
          constraints: BoxConstraints(maxWidth: canvasW * 0.9),
          color: t.background,
          padding: t.background != null ? const EdgeInsets.symmetric(horizontal: 8, vertical: 4) : null,
          child: text,
        );
    }
  }
}

/// Text set along a circular arc. [curve] in -1..1 bends it up to half a
/// circle (positive arches up, negative sags down). Each glyph is laid out on
/// its own; a gradient is applied as a per-glyph colour from left to right.
class _CurvedText extends StatelessWidget {
  const _CurvedText({
    required this.text,
    required this.style,
    required this.curve,
    this.strokeStyle,
    this.gradientEnd,
  });

  final String text;
  final TextStyle style;
  final TextStyle? strokeStyle;
  final Color? gradientEnd;
  final double curve;

  @override
  Widget build(BuildContext context) {
    final layout = _CurvedLayout.compute(text, style, curve);
    return SizedBox(
      width: layout.size.width,
      height: layout.size.height,
      child: CustomPaint(
        painter: _CurvedTextPainter(
          layout: layout,
          style: style,
          strokeStyle: strokeStyle,
          gradientEnd: gradientEnd,
        ),
      ),
    );
  }
}

/// Glyph positions on the arc, shared by sizing and painting.
class _CurvedLayout {
  _CurvedLayout(this.glyphs, this.size);

  final List<({String char, Offset at, double angle, double t})> glyphs;
  final Size size;

  static _CurvedLayout compute(String text, TextStyle style, double curve) {
    final chars = text.replaceAll('\n', ' ').characters.toList();
    final advances = <double>[];
    var lineH = (style.fontSize ?? 14) * 1.2;
    var ascent = lineH * 0.8;
    for (final ch in chars) {
      final tp = TextPainter(text: TextSpan(text: ch, style: style), textDirection: TextDirection.ltr)..layout();
      advances.add(tp.width);
      lineH = math.max(lineH, tp.height);
      ascent = math.max(ascent, tp.computeDistanceToActualBaseline(TextBaseline.alphabetic));
    }
    final total = advances.fold(0.0, (a, b) => a + b);
    final theta = (curve.clamp(-1.0, 1.0) * math.pi).abs();
    if (chars.isEmpty || total == 0 || theta < 0.01) {
      var x = 0.0;
      final glyphs = [
        for (var i = 0; i < chars.length; i++)
          (char: chars[i], at: Offset((x += advances[i]) - advances[i] / 2, ascent), angle: 0.0, t: total == 0 ? 0.0 : (x - advances[i] / 2) / total),
      ];
      return _CurvedLayout(glyphs, Size(math.max(total, 1.0), lineH));
    }
    final r = total / theta;
    final sag = r * (1 - math.cos(theta / 2));
    final width = 2 * r * math.sin(theta / 2) + lineH;
    final height = lineH + sag;
    final cx = width / 2;
    final up = curve > 0;
    // Arching up: circle centre below the text; sagging: above it.
    final cy = up ? ascent + r : ascent + sag - r;
    final glyphs = <({String char, Offset at, double angle, double t})>[];
    var s = 0.0;
    for (var i = 0; i < chars.length; i++) {
      final mid = s + advances[i] / 2;
      s += advances[i];
      final phi = -theta / 2 + mid / r;
      final at = up
          ? Offset(cx + r * math.sin(phi), cy - r * math.cos(phi))
          : Offset(cx + r * math.sin(phi), cy + r * math.cos(phi));
      glyphs.add((char: chars[i], at: at, angle: up ? phi : -phi, t: mid / total));
    }
    return _CurvedLayout(glyphs, Size(width, height));
  }
}

class _CurvedTextPainter extends CustomPainter {
  _CurvedTextPainter({
    required this.layout,
    required this.style,
    this.strokeStyle,
    this.gradientEnd,
  });

  final _CurvedLayout layout;
  final TextStyle style;
  final TextStyle? strokeStyle;
  final Color? gradientEnd;

  void _glyph(Canvas canvas, String ch, Offset at, double angle, TextStyle st) {
    final tp = TextPainter(text: TextSpan(text: ch, style: st), textDirection: TextDirection.ltr)..layout();
    final base = tp.computeDistanceToActualBaseline(TextBaseline.alphabetic);
    canvas.save();
    canvas.translate(at.dx, at.dy);
    canvas.rotate(angle);
    tp.paint(canvas, Offset(-tp.width / 2, -base));
    canvas.restore();
  }

  @override
  void paint(Canvas canvas, Size size) {
    for (final g in layout.glyphs) {
      if (strokeStyle != null) _glyph(canvas, g.char, g.at, g.angle, strokeStyle!);
    }
    for (final g in layout.glyphs) {
      final end = gradientEnd;
      final st = end == null ? style : style.copyWith(color: Color.lerp(style.color, end, g.t));
      _glyph(canvas, g.char, g.at, g.angle, st);
    }
  }

  @override
  bool shouldRepaint(_CurvedTextPainter old) => true;
}

class _Handle extends StatelessWidget {
  const _Handle({
    required this.icon,
    required this.color,
    required this.iconColor,
    this.onTap,
    this.semantics,
  });
  final IconData icon;
  final Color color;
  final Color iconColor;
  final VoidCallback? onTap;
  final String? semantics;

  /// A 44dp touch target around a visible 28dp handle — big enough for a
  /// fingertip, precise enough for a stylus.
  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: onTap != null,
      label: semantics,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: SizedBox(
          width: _ElementViewState._handleHit,
          height: _ElementViewState._handleHit,
          child: Center(
            child: Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
                border: Border.all(color: context.colors.amber, width: 1.5),
                boxShadow: Shadows.e1,
              ),
              child: Icon(icon, size: 16, color: iconColor),
            ),
          ),
        ),
      ),
    );
  }
}
