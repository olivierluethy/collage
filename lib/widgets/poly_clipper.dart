import 'package:flutter/widgets.dart';

import '../models/partition_geometry.dart';

/// Geometry helpers for polygon (non-rectangular) collage cells.
///
/// A cell is a convex polygon in some coordinate space (normalised 0..1 in a
/// template, or pixels once placed). These helpers build its clip [Path], inset
/// it inward for the border gap, and stroke its edges — shared by the live
/// canvas and the little layout miniatures so previews match the result.

/// The centroid (average vertex) of a polygon.
Offset polygonCentroid(List<Offset> pts) {
  var x = 0.0, y = 0.0;
  for (final p in pts) {
    x += p.dx;
    y += p.dy;
  }
  return Offset(x / pts.length, y / pts.length);
}

/// A closed [Path] through the polygon vertices.
Path polygonPath(List<Offset> pts) {
  final path = Path();
  if (pts.isEmpty) return path;
  path.moveTo(pts.first.dx, pts.first.dy);
  for (var i = 1; i < pts.length; i++) {
    path.lineTo(pts[i].dx, pts[i].dy);
  }
  path.close();
  return path;
}

/// Inset a cell polygon inward by [d] along each edge's inward normal, so
/// adjacent cells leave an even gap of `2*d`. Works for convex cells and for
/// the concave ones produced by dragging cut points (the inward side comes
/// from the winding; see [PartitionGeometry.inset]). Returns the input
/// unchanged for degenerate cases.
List<Offset> insetConvexPolygon(List<Offset> pts, double d) => PartitionGeometry.inset(pts, d);

/// Clips a child to a polygon given in the child's local pixel coordinates.
/// Because `ClipPath` also clips pointer hit-testing, taps in the bounding-box
/// corners fall through to the cell behind — which is what makes overlapping
/// diagonal cells select correctly.
class PolygonClipper extends CustomClipper<Path> {
  const PolygonClipper(this.points);
  final List<Offset> points;

  @override
  Path getClip(Size size) => polygonPath(points);

  @override
  bool shouldReclip(PolygonClipper old) => old.points != points;
}

/// Strokes a polygon's edges — the cell divider/border line.
class PolygonBorderPainter extends CustomPainter {
  const PolygonBorderPainter({
    required this.points,
    required this.color,
    required this.strokeWidth,
    this.outline,
  });
  final List<Offset> points;

  /// A curved / zigzag outline to stroke instead of the straight polygon.
  final Path? outline;
  final Color color;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    if (strokeWidth <= 0 || points.length < 3) return;
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(outline ?? polygonPath(points), paint);
  }

  @override
  bool shouldRepaint(PolygonBorderPainter old) =>
      old.points != points || old.outline != outline || old.color != color || old.strokeWidth != strokeWidth;
}
