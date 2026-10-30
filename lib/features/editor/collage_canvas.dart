import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../data/fonts.dart';
import '../../data/shape_catalog.dart';
import '../../l10n/app_localizations.dart';
import '../../models/canvas_element.dart';
import '../../models/collage_project.dart';
import '../../models/layout_template.dart';
import '../../theme/palette.dart';
import '../../theme/tokens.dart';
import '../../theme/typography.dart';
import '../../widgets/collage_background.dart';
import '../../widgets/drawing_painter.dart';
import '../../widgets/photo_image.dart';
import '../../widgets/poly_clipper.dart';
import '../../widgets/sharpened.dart';
import '../../widgets/sticker_image.dart';
import '../../widgets/video_slot.dart';
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
    this.onRequestReplace,
    this.onRequestStyle,
    this.onRequestVideo,
  });

  final EditorController controller;
  final bool interactive;

  /// Ask the host to open the replace picker for a slot (with live preview).
  final void Function(String slotId)? onRequestReplace;

  /// Ask the host to open the frame/shadow panel for a slot.
  final void Function(String slotId)? onRequestStyle;

  /// Ask the host to pick a video for a slot.
  final void Function(String slotId)? onRequestVideo;

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
                    _ElementView(
                      key: ValueKey(e.id),
                      controller: c,
                      element: e,
                      canvas: size,
                      interactive: interactive,
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
                  if (interactive && !c.drawing && c.selectedElementId == null)
                    ..._splitHandles(context, c, size),
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
        // then position at its bounding box with local (box-relative) points.
        var poly = slot.points!.map(toPx).toList();
        poly = insetConvexPolygon(poly, gap / 2);
        final b = _boundsOf(poly);
        final local = [for (final p in poly) p - b.topLeft];
        return Positioned(
          left: b.left,
          top: b.top,
          width: b.width.clamp(0, size.width),
          height: b.height.clamp(0, size.height),
          child: _PolySlotView(
            controller: c,
            slotId: slot.id,
            unit: unit,
            polygon: local,
            thickness: thickness,
            borderColor: c.border.color,
            interactive: interactive,
            onRequestReplace: onRequestReplace,
            onRequestStyle: onRequestStyle,
            onRequestVideo: onRequestVideo,
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
        left: r.left,
        top: r.top,
        width: r.width.clamp(0, size.width),
        height: r.height.clamp(0, size.height),
        child: _SlotView(
          controller: c,
          slotId: slot.id,
          unit: unit,
          radius: radius,
          thickness: thickness,
          borderColor: c.border.color,
          interactive: interactive,
          onRequestReplace: onRequestReplace,
          onRequestStyle: onRequestStyle,
          onRequestVideo: onRequestVideo,
        ),
      );
    }).toList();
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
      for (final sp in c.polySplits)
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
  _PolyShadowPainter({required this.points, required this.elevation, this.cardColor});
  final List<Offset> points;
  final double elevation;
  final Color? cardColor;

  @override
  void paint(Canvas canvas, Size size) {
    if (points.length < 3) return;
    final path = Path()..addPolygon(points, true);
    if (elevation > 0) canvas.drawShadow(path, Colors.black, elevation, false);
    if (cardColor != null) canvas.drawPath(path, Paint()..color = cardColor!);
  }

  @override
  bool shouldRepaint(_PolyShadowPainter old) =>
      old.elevation != elevation || old.points != points || old.cardColor != cardColor;
}

/// Clips a polygon cell's photo: the polygon itself, a shape mask centred in
/// it (and cut to the polygon), ragged torn-paper edges, or the polygon inset
/// by [inset] for the Polaroid card.
class _PolyCellClipper extends CustomClipper<Path> {
  _PolyCellClipper({
    required this.points,
    required this.mask,
    required this.torn,
    required this.inset,
    required this.seed,
  });
  final List<Offset> points;
  final String mask;
  final bool torn;
  final double inset;
  final int seed;

  @override
  Path getClip(Size size) {
    final poly = polygonPath(points);
    if (mask != 'none') {
      final c = polygonCentroid(points);
      final side = math.min(size.width, size.height) * 0.85;
      final shape = ShapeCatalog.pathFor(mask, Size(side, side)).shift(c - Offset(side / 2, side / 2));
      return Path.combine(PathOperation.intersect, poly, shape);
    }
    if (torn) return _tornPolygon(points, seed, math.min(size.width, size.height));
    if (inset > 0) return polygonPath(insetConvexPolygon(points, inset));
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
      old.points != points || old.mask != mask || old.torn != torn || old.inset != inset || old.seed != seed;
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
    this.onRequestReplace,
    this.onRequestStyle,
    this.onRequestVideo,
  });

  final EditorController controller;
  final String slotId;
  final double unit; // canvas pixels per 1/1000 of canvas width
  final double radius;
  final double thickness;
  final Color borderColor;
  final bool interactive;
  final void Function(String slotId)? onRequestReplace;
  final void Function(String slotId)? onRequestStyle;
  final void Function(String slotId)? onRequestVideo;

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

    // Chrome (edit badge, action chips) rides above the photo as siblings, so
    // adding or removing it never touches the photo subtree.
    final overlays = <Widget>[
      // A subtle, persistent edit badge signals every filled slot is tappable.
      if (interactive && realFill != null && !selected)
        Positioned(
          right: 4,
          bottom: 4,
          child: Container(
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.45),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.edit_rounded, size: 12, color: Colors.white),
          ),
        ),
      // Inline action chips on the selected slot.
      if (interactive && selected)
        Positioned(
          top: 4,
          left: 0,
          right: 0,
          child: Center(
            child: FittedBox(
              child: _SlotChips(
                hasPhoto: realFill != null,
                onReplace: () => onRequestReplace?.call(slotId),
                onSwap: () => controller.startSwapMode(slotId),
                onFlipH: () => controller.flipSlot(slotId, horizontal: true),
                onFlipV: () => controller.flipSlot(slotId, vertical: true),
                onRotate: () => controller.rotateSlotQuarter(slotId),
                onStyle: () => onRequestStyle?.call(slotId),
                onVideo: () => onRequestVideo?.call(slotId),
                onClear: () => controller.clearSlot(slotId),
              ),
            ),
          ),
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

/// The Replace / Swap / Flip / Clear chips shown on a selected slot.
class _SlotChips extends StatelessWidget {
  const _SlotChips({
    required this.hasPhoto,
    required this.onReplace,
    required this.onSwap,
    required this.onFlipH,
    required this.onFlipV,
    required this.onRotate,
    required this.onStyle,
    required this.onVideo,
    required this.onClear,
  });
  final bool hasPhoto;
  final VoidCallback onReplace;
  final VoidCallback onSwap;
  final VoidCallback onFlipH;
  final VoidCallback onFlipV;
  final VoidCallback onRotate;
  final VoidCallback onStyle;
  final VoidCallback onVideo;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(Radii.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _Chip(
              icon: Icons.photo_library_rounded,
              label: hasPhoto ? context.l10n.t('chipReplace') : context.l10n.t('chipChoose'),
              onTap: onReplace),
          _Chip(icon: Icons.videocam_outlined, label: context.l10n.t('chipVideo'), onTap: onVideo),
          if (hasPhoto)
            _Chip(icon: Icons.swap_horiz_rounded, label: context.l10n.t('chipSwap'), onTap: onSwap),
          if (hasPhoto)
            _Chip(icon: Icons.flip_rounded, label: context.l10n.t('chipFlipH'), onTap: onFlipH),
          if (hasPhoto)
            _Chip(icon: Icons.flip_rounded, label: context.l10n.t('chipFlipV'), onTap: onFlipV, iconTurns: 1),
          if (hasPhoto)
            _Chip(icon: Icons.rotate_90_degrees_cw_rounded, label: context.l10n.t('chipRotate'), onTap: onRotate),
          if (hasPhoto)
            _Chip(icon: Icons.filter_frames_rounded, label: context.l10n.t('chipStyle'), onTap: onStyle),
          if (hasPhoto)
            _Chip(icon: Icons.close_rounded, label: context.l10n.t('chipClear'), onTap: onClear, danger: true),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.icon,
    required this.label,
    required this.onTap,
    this.danger = false,
    this.iconTurns = 0,
  });
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool danger;
  final int iconTurns; // quarter-turns applied to [icon] (1 → vertical mirror)

  @override
  Widget build(BuildContext context) {
    final c = danger ? context.colors.danger : context.colors.amber;
    Widget iconWidget = Icon(icon, size: 13, color: c);
    if (iconTurns != 0) iconWidget = RotatedBox(quarterTurns: iconTurns, child: iconWidget);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 2),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          color: context.colors.surface,
          borderRadius: BorderRadius.circular(Radii.pill),
          border: Border.all(color: c),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            iconWidget,
            const SizedBox(width: 4),
            Text(label, style: context.text.labelMd.copyWith(color: c)),
          ],
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
    this.onRequestReplace,
    this.onRequestStyle,
    this.onRequestVideo,
  });

  final EditorController controller;
  final String slotId;
  final List<Offset> polygon; // local (box-relative) pixels
  final double unit; // canvas pixels per 1/1000 of canvas width
  final double thickness;
  final Color borderColor;
  final bool interactive;
  final void Function(String slotId)? onRequestReplace;
  final void Function(String slotId)? onRequestStyle;
  final void Function(String slotId)? onRequestVideo;

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
                    points: polygon, color: fill!.frameColor, strokeWidth: frame),
              ),
            ),
          ),
        // Border stroke along the polygon edges.
        if (thickness > 0)
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(
                painter: PolygonBorderPainter(
                    points: polygon, color: borderColor, strokeWidth: thickness),
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
                  color: swapTarget ? context.colors.amberBright : context.colors.amber,
                  strokeWidth: swapTarget ? 3 : 2.5,
                ),
              ),
            ),
          ),
        // Persistent edit badge on a filled, unselected cell.
        if (interactive && realFill != null && !selected)
          Positioned(
            left: centroid.dx,
            top: centroid.dy,
            child: FractionalTranslation(
              translation: const Offset(-0.5, -0.5),
              child: Container(
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.45),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.edit_rounded, size: 12, color: Colors.white),
              ),
            ),
          ),
        // Inline action chips on the selected cell.
        if (interactive && selected)
          Positioned(
            left: centroid.dx,
            top: centroid.dy,
            child: FractionalTranslation(
              translation: const Offset(-0.5, -0.5),
              child: FittedBox(
                child: _SlotChips(
                  hasPhoto: realFill != null,
                  onReplace: () => onRequestReplace?.call(slotId),
                  onSwap: () => controller.startSwapMode(slotId),
                  onFlipH: () => controller.flipSlot(slotId, horizontal: true),
                  onFlipV: () => controller.flipSlot(slotId, vertical: true),
                  onRotate: () => controller.rotateSlotQuarter(slotId),
                  onStyle: () => onRequestStyle?.call(slotId),
                  onVideo: () => onRequestVideo?.call(slotId),
                  onClear: () => controller.clearSlot(slotId),
                ),
              ),
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
  });

  final EditorController controller;
  final CanvasElement element;
  final Size canvas;
  final bool interactive;

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

    // The gesture wrapper and highlight container are always present (handlers
    // just go inert while exporting) so the element — a photo in particular —
    // keeps the same ancestors and never loses its decoded frame (see _SlotView).
    final gestured = GestureDetector(
      behavior: HitTestBehavior.deferToChild,
      onTap: widget.interactive ? () => c.selectElement(e.id) : null,
      onScaleStart: widget.interactive
          ? (_) {
              _baseScale = e.scale;
              _baseRotation = e.rotation;
              _rawCx = e.cx;
              _rawCy = e.cy;
              c.selectElement(e.id);
            }
          : null,
      onScaleUpdate: widget.interactive
          ? (d) {
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
            }
          : null,
      onScaleEnd: widget.interactive ? (_) => c.clearGuides() : null,
      child: child,
    );

    final boxed = Container(
      key: _boxKey,
      decoration: selected
          ? BoxDecoration(
              border: Border.all(color: context.colors.amber, width: 1.5),
              boxShadow: Shadows.focusGlow,
            )
          : const BoxDecoration(),
      child: gestured,
    );

    final showHandles = widget.interactive && selected;

    return Positioned(
      left: e.cx * W,
      top: e.cy * H,
      child: FractionalTranslation(
        translation: const Offset(-0.5, -0.5),
        child: Transform.rotate(
          angle: e.rotation,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              boxed,
              if (showHandles) ...[
                // Delete handle (top-left, danger)
                Positioned(
                  left: -12,
                  top: -12,
                  child: _Handle(
                    icon: Icons.close_rounded,
                    color: context.colors.danger,
                    iconColor: context.colors.onDanger,
                    onTap: () => c.deleteElement(e.id),
                  ),
                ),
                // Scale + rotate handle (bottom-right)
                Positioned(
                  right: -12,
                  bottom: -12,
                  child: GestureDetector(
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
                      final rot = _handleBaseRotation + (v.direction - _handleBaseAngle);
                      c.updateTransform(e.id, scale: scale, rotation: rot);
                    },
                    child: _Handle(
                      icon: Icons.open_in_full_rounded,
                      color: context.colors.surface,
                      iconColor: context.colors.amber,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

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
        final w = im.naturalWidthFrac * canvasW * im.scale;
        // The full photo is laid out larger than the box and shifted so only
        // the cropped window shows. Built the same way when uncropped so the
        // photo keeps its ancestors when a crop is added.
        final fw = w / (1 - im.cropL - im.cropR);
        final fh = fw / im.imgAspect;
        Widget photo = SizedBox(
          width: w,
          height: w / im.aspectRatio,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: Stack(
              clipBehavior: Clip.hardEdge,
              children: [
                Positioned(
                  left: -im.cropL * fw,
                  top: -im.cropT * fh,
                  width: fw,
                  height: fh,
                  child: PhotoImage(assetId: im.assetId, full: true, fit: BoxFit.cover),
                ),
              ],
            ),
          ),
        );
        if (im.flipX || im.flipY) {
          photo = Transform.scale(
            scaleX: im.flipX ? -1 : 1,
            scaleY: im.flipY ? -1 : 1,
            child: photo,
          );
        }
        return photo;
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
  });
  final IconData icon;
  final Color color;
  final Color iconColor;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: Sizes.handle,
        height: Sizes.handle,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(color: context.colors.amber, width: 1.5),
        ),
        child: Icon(icon, size: 14, color: iconColor),
      ),
    );
  }
}
