import 'dart:math' as math;
import 'dart:ui';

import '../models/layout_template.dart';

/// Curved, waved and zigzag cuts between polygon cells.
///
/// This builds on the polygon geometry of diagonal / mosaic layouts rather
/// than introducing a second geometry system: a cell is still a convex polygon
/// (its straight "skeleton", which dragging edges, insetting for the gap and
/// the layout miniatures keep using), and every interior edge shared by
/// exactly two cells may carry an [EdgeShape] that bends it. Both cells draw
/// the same bent edge from the shared shape, so they always meet.

const _eps = 0.004;

bool _near(Offset a, Offset b) => (a - b).distance <= _eps;

/// True when [a] comes before [b] in the canonical edge direction (smaller x,
/// then smaller y) — the same answer for both cells sharing the edge.
bool canonicalBefore(Offset a, Offset b) =>
    (a.dx - b.dx).abs() > 1e-4 ? a.dx < b.dx : a.dy < b.dy;

/// An interior edge shared by exactly two polygon cells, in layout fractions,
/// with [p]→[q] in canonical direction.
class SharedEdge {
  const SharedEdge({required this.a, required this.b, required this.p, required this.q});
  final String a;
  final String b;
  final Offset p;
  final Offset q;

  String get key => EdgeShape.keyFor(a, b);
}

List<Offset> _pointsOf(LayoutSlot s) => s.isPolygon
    ? s.points!
    : [s.rect.topLeft, s.rect.topRight, s.rect.bottomRight, s.rect.bottomLeft];

/// Every edge whose two endpoints are shared by two polygon cells.
List<SharedEdge> findSharedEdges(List<LayoutSlot> slots) {
  final polys = [for (final s in slots) if (s.isPolygon) s];
  final out = <SharedEdge>[];
  for (var i = 0; i < polys.length; i++) {
    final pa = polys[i].points!;
    for (var j = i + 1; j < polys.length; j++) {
      final pb = polys[j].points!;
      for (var x = 0; x < pa.length; x++) {
        final a0 = pa[x], a1 = pa[(x + 1) % pa.length];
        if ((a1 - a0).distance < 0.02) continue;
        var hit = false;
        for (var y = 0; y < pb.length && !hit; y++) {
          final b0 = pb[y], b1 = pb[(y + 1) % pb.length];
          if ((_near(a0, b0) && _near(a1, b1)) || (_near(a0, b1) && _near(a1, b0))) hit = true;
        }
        if (!hit) continue;
        final ids = [polys[i].id, polys[j].id]..sort();
        final forward = canonicalBefore(a0, a1);
        out.add(SharedEdge(a: ids[0], b: ids[1], p: forward ? a0 : a1, q: forward ? a1 : a0));
      }
    }
  }
  return out;
}

/// For one cell: which of its edges (by index i, from point i to i+1) carry a
/// non-straight shape, and whether that edge runs against the canonical
/// direction.
Map<int, (EdgeShape, bool)> curvedEdgesOf(LayoutSlot slot, List<LayoutSlot> slots, Map<String, EdgeShape> shapes) {
  if (shapes.isEmpty || !slot.isPolygon) return const {};
  final pts = slot.points!;
  final out = <int, (EdgeShape, bool)>{};
  for (final other in slots) {
    if (other.id == slot.id || !other.isPolygon) continue;
    final shape = shapes[EdgeShape.keyFor(slot.id, other.id)];
    if (shape == null || shape.isStraight) continue;
    final op = other.points!;
    for (var i = 0; i < pts.length; i++) {
      final a = pts[i], b = pts[(i + 1) % pts.length];
      for (var k = 0; k < op.length; k++) {
        final c = op[k], d = op[(k + 1) % op.length];
        if ((_near(a, c) && _near(b, d)) || (_near(a, d) && _near(b, c))) {
          out[i] = (shape, !canonicalBefore(a, b));
        }
      }
    }
  }
  return out;
}

/// A point on the edge P→Q from edge-local (u along, v along the left normal,
/// both as fractions of the edge length).
Offset edgePoint(Offset p, Offset q, Offset uv) {
  final e = q - p;
  final n = Offset(-e.dy, e.dx);
  return p + e * uv.dx + n * uv.dy;
}

/// Edge-local (u, v) of [point] relative to P→Q.
Offset edgeLocal(Offset p, Offset q, Offset point) {
  final e = q - p;
  final len2 = e.dx * e.dx + e.dy * e.dy;
  if (len2 == 0) return Offset.zero;
  final d = point - p;
  final n = Offset(-e.dy, e.dx);
  return Offset((d.dx * e.dx + d.dy * e.dy) / len2, (d.dx * n.dx + d.dy * n.dy) / len2);
}

Offset _bezier(Offset p0, Offset p1, Offset p2, Offset p3, double t) {
  final mt = 1 - t;
  return p0 * (mt * mt * mt) + p1 * (3 * mt * mt * t) + p2 * (3 * mt * t * t) + p3 * (t * t * t);
}

Offset _bezierTangent(Offset p0, Offset p1, Offset p2, Offset p3, double t) {
  final mt = 1 - t;
  return (p1 - p0) * (3 * mt * mt) + (p2 - p1) * (6 * mt * t) + (p3 - p2) * (3 * t * t);
}

/// The point at the middle of the shaped edge P→Q (ignoring zigzag teeth) —
/// where the edge's selection handle sits.
Offset edgeMidpoint(Offset p, Offset q, EdgeShape? shape) {
  if (shape == null || !shape.isCurved) return (p + q) / 2;
  return _bezier(p, edgePoint(p, q, shape.c1), edgePoint(p, q, shape.c2), q, 0.5);
}

/// Points of the shaped edge from canonical P to Q (P excluded), for the
/// zigzag case; plain curves are drawn as true cubics in [appendShapedEdge].
List<Offset> _zigzagPoints(Offset p, Offset q, EdgeShape s) {
  final c1 = edgePoint(p, q, s.c1);
  final c2 = edgePoint(p, q, s.c2);
  final len = (q - p).distance;
  final n = s.zigCount.clamp(1, 60);
  final amp = s.zigAmp * len;
  final steps = 2 * n;
  final out = <Offset>[];
  for (var k = 1; k <= steps; k++) {
    final t = k / steps;
    var pt = _bezier(p, c1, c2, q, t);
    if (k.isOdd) {
      final tan = _bezierTangent(p, c1, c2, q, t);
      final d = tan.distance;
      if (d > 0) pt += Offset(-tan.dy / d, tan.dx / d) * amp;
    }
    out.add(pt);
  }
  return out;
}

/// Append the edge from [from] to [to] (the path's current point is [from])
/// shaped by [shape]; [reversed] tells that [from]→[to] runs against the
/// canonical direction.
void appendShapedEdge(Path path, Offset from, Offset to, EdgeShape shape, bool reversed) {
  final p = reversed ? to : from;
  final q = reversed ? from : to;
  if (!shape.hasZigzag) {
    final c1 = edgePoint(p, q, shape.c1);
    final c2 = edgePoint(p, q, shape.c2);
    if (reversed) {
      path.cubicTo(c2.dx, c2.dy, c1.dx, c1.dy, to.dx, to.dy);
    } else {
      path.cubicTo(c1.dx, c1.dy, c2.dx, c2.dy, to.dx, to.dy);
    }
    return;
  }
  var pts = _zigzagPoints(p, q, shape);
  if (reversed) {
    // Walk Q→P: drop Q itself (the current point) and end on P.
    pts = [...pts.reversed.skip(1), p];
  }
  for (final pt in pts) {
    path.lineTo(pt.dx, pt.dy);
  }
}

/// The closed outline of a cell whose (already inset, pixel) polygon is
/// [poly], with the edges in [curved] (by index) shaped.
Path shapedCellPath(List<Offset> poly, Map<int, (EdgeShape, bool)> curved) {
  final path = Path();
  if (poly.isEmpty) return path;
  path.moveTo(poly.first.dx, poly.first.dy);
  for (var i = 0; i < poly.length; i++) {
    final a = poly[i], b = poly[(i + 1) % poly.length];
    final c = curved[i];
    if (c == null) {
      path.lineTo(b.dx, b.dy);
    } else {
      appendShapedEdge(path, a, b, c.$1, c.$2);
    }
  }
  return path..close();
}

/// [slots] as polygons, with every vertex of a neighbour that lies inside one
/// of a cell's edges (a T-junction) inserted into that edge. Afterwards every
/// interior boundary between two cells is one exact shared edge, so each can
/// be shaped on its own. Rectangles become four-point polygons.
List<LayoutSlot> polygonizeSlots(List<LayoutSlot> slots) {
  final polys = [for (final s in slots) _pointsOf(s)];
  final vertices = <Offset>[];
  for (final p in polys) {
    for (final v in p) {
      if (!vertices.any((w) => _near(v, w))) vertices.add(v);
    }
  }
  final out = <LayoutSlot>[];
  for (var si = 0; si < slots.length; si++) {
    final pts = polys[si];
    final next = <Offset>[];
    for (var i = 0; i < pts.length; i++) {
      final a = pts[i], b = pts[(i + 1) % pts.length];
      next.add(a);
      final e = b - a;
      final len2 = e.dx * e.dx + e.dy * e.dy;
      if (len2 == 0) continue;
      final inner = <(double, Offset)>[];
      for (final v in vertices) {
        if (_near(v, a) || _near(v, b)) continue;
        final t = ((v - a).dx * e.dx + (v - a).dy * e.dy) / len2;
        if (t <= 0.001 || t >= 0.999) continue;
        final proj = a + e * t;
        if ((proj - v).distance <= _eps) inner.add((t, v));
      }
      inner.sort((x, y) => x.$1.compareTo(y.$1));
      next.addAll([for (final (_, v) in inner) v]);
    }
    out.add(LayoutSlot.poly(slots[si].id, next));
  }
  return out;
}

/// Bounds of a path, never empty.
Rect safeBounds(Path path) {
  final b = path.getBounds();
  return Rect.fromLTWH(b.left, b.top, math.max(b.width, 1), math.max(b.height, 1));
}
