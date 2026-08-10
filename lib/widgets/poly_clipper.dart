import 'package:flutter/widgets.dart';

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

Offset _normalize(Offset v) {
  final d = v.distance;
  return d == 0 ? v : v / d;
}

Offset? _intersect(Offset p1, Offset d1, Offset p2, Offset d2) {
  final denom = d1.dx * d2.dy - d1.dy * d2.dx;
  if (denom.abs() < 1e-9) return null; // parallel
  final diff = p2 - p1;
  final t = (diff.dx * d2.dy - diff.dy * d2.dx) / denom;
  return p1 + d1 * t;
}

/// Inset a convex polygon inward by [d] along each edge's inward normal, so
/// adjacent cells leave an even gap of `2*d`. Returns the input unchanged for
/// degenerate cases. Works reliably for the convex cells our templates use.
List<Offset> insetConvexPolygon(List<Offset> pts, double d) {
  final n = pts.length;
  if (n < 3 || d <= 0) return pts;
  final c = polygonCentroid(pts);

  // Each edge shifted inward: keep a point on it and its direction.
  final shiftedPoints = <Offset>[];
  final dirs = <Offset>[];
  for (var i = 0; i < n; i++) {
    final a = pts[i];
    final b = pts[(i + 1) % n];
    final dir = _normalize(b - a);
    var nrm = Offset(-dir.dy, dir.dx);
    final mid = (a + b) / 2;
    if (nrm.dx * (c.dx - mid.dx) + nrm.dy * (c.dy - mid.dy) < 0) {
      nrm = -nrm; // ensure it points inward (toward the centroid)
    }
    shiftedPoints.add(a + nrm * d);
    dirs.add(dir);
  }

  // Each output vertex is where the two shifted edges meeting there cross.
  final out = <Offset>[];
  for (var i = 0; i < n; i++) {
    final prev = (i - 1 + n) % n;
    final p = _intersect(shiftedPoints[prev], dirs[prev], shiftedPoints[i], dirs[i]);
    out.add(p ?? pts[i]);
  }
  return out;
}

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
  });
  final List<Offset> points;
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
    canvas.drawPath(polygonPath(points), paint);
  }

  @override
  bool shouldRepaint(PolygonBorderPainter old) =>
      old.points != points || old.color != color || old.strokeWidth != strokeWidth;
}
