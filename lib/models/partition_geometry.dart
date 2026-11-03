import 'dart:math' as math;
import 'dart:ui';

import 'layout_template.dart';

/// Editable partitions: the cells of a layout tile the content area
/// (normalised 0..1) without gaps or overlaps, and the user reshapes them by
/// moving, adding and removing the points where cuts meet.
///
/// The model stays the one layouts already use — every cell is a polygon of
/// shared vertices — so presets, saved collages, edge curves and the export
/// keep working unchanged. Every operation here is pure: it takes the cells
/// (already polygonised, see `polygonizeSlots`) and returns new cells, or
/// null when the result would be invalid. "Invalid" means a cell would be
/// flipped, self-intersecting or vanishingly small, or two cells would
/// cross — exactly the cracks, overlaps and broken geometry the editor must
/// never produce.
///
/// Topology rules for a point being moved:
/// * an interior point moves freely (kept inside the canvas);
/// * a point on the canvas border slides along that border;
/// * a canvas corner shared by several cells is split when pulled along one
///   border: the cell lying along the *other* border keeps the corner, so the
///   corner stays covered and the cut's endpoint becomes freely adjustable.
///   Sliding it back onto the corner merges it again.
class PartitionGeometry {
  PartitionGeometry._();

  /// Two points closer than this (layout fractions) are the same vertex.
  static const eps = 0.004;

  /// Smallest cell area allowed, as a fraction of the content area.
  static const minArea = 0.002;

  static bool near(Offset a, Offset b) => (a - b).distance <= eps;

  // -------------------------------------------------------------------------
  // Basic polygon predicates
  // -------------------------------------------------------------------------

  static double signedArea(List<Offset> pts) {
    var a = 0.0;
    for (var i = 0; i < pts.length; i++) {
      final p = pts[i], q = pts[(i + 1) % pts.length];
      a += p.dx * q.dy - q.dx * p.dy;
    }
    return a / 2;
  }

  static double _cross(Offset o, Offset a, Offset b) =>
      (a.dx - o.dx) * (b.dy - o.dy) - (a.dy - o.dy) * (b.dx - o.dx);

  /// True when segments a–b and c–d cross at a single point strictly inside
  /// both. Touching at endpoints and collinear overlap (a shared edge) are
  /// not crossings.
  static bool segmentsCross(Offset a, Offset b, Offset c, Offset d) {
    const t = 1e-9;
    final d1 = _cross(c, d, a), d2 = _cross(c, d, b);
    final d3 = _cross(a, b, c), d4 = _cross(a, b, d);
    return ((d1 > t && d2 < -t) || (d1 < -t && d2 > t)) &&
        ((d3 > t && d4 < -t) || (d3 < -t && d4 > t));
  }

  /// A polygon whose non-adjacent edges never cross.
  static bool isSimple(List<Offset> pts) {
    final n = pts.length;
    if (n < 3) return false;
    for (var i = 0; i < n; i++) {
      final a = pts[i], b = pts[(i + 1) % n];
      for (var j = i + 2; j < n; j++) {
        if (i == 0 && j == n - 1) continue; // adjacent through the wrap
        final c = pts[j], d = pts[(j + 1) % n];
        if (segmentsCross(a, b, c, d)) return false;
      }
    }
    return true;
  }

  static bool isConvex(List<Offset> pts) {
    var sign = 0;
    for (var i = 0; i < pts.length; i++) {
      final c = _cross(pts[i], pts[(i + 1) % pts.length], pts[(i + 2) % pts.length]);
      if (c.abs() < 1e-9) continue;
      final s = c > 0 ? 1 : -1;
      if (sign == 0) sign = s;
      if (s != sign) return false;
    }
    return true;
  }

  /// Drop consecutive duplicate vertices (and a duplicate closing vertex).
  static List<Offset> dedupe(List<Offset> pts) {
    final out = <Offset>[];
    for (final p in pts) {
      if (out.isEmpty || (out.last - p).distance > 1e-4) out.add(p);
    }
    while (out.length > 1 && (out.first - out.last).distance <= 1e-4) {
      out.removeLast();
    }
    return out;
  }

  // -------------------------------------------------------------------------
  // Inset (the gap between cells)
  // -------------------------------------------------------------------------

  /// Inset a simple polygon (convex or not) by [d] along each edge's inward
  /// normal, mitred at the corners, so neighbouring cells leave an even gap
  /// of `2·d`. The inward side comes from the winding, not the centroid, so
  /// concave cells (made by dragging cut points) inset correctly. Very sharp
  /// corners are clamped so the miter never shoots across the cell.
  static List<Offset> inset(List<Offset> pts, double d) {
    final n = pts.length;
    if (n < 3 || d <= 0) return pts;
    final area = signedArea(pts);
    if (area.abs() < 1e-12) return pts;
    // In y-down screen space a positive signed area winds clockwise; the
    // inward normal of edge (dx, dy) is then (-dy, dx).
    final s = area > 0 ? 1.0 : -1.0;
    final normals = <Offset>[];
    final dirs = <Offset>[];
    for (var i = 0; i < n; i++) {
      final e = pts[(i + 1) % n] - pts[i];
      final len = e.distance;
      final dir = len == 0 ? Offset.zero : e / len;
      dirs.add(dir);
      normals.add(Offset(-dir.dy, dir.dx) * s);
    }
    final maxMiter = d * 4;
    final out = <Offset>[];
    for (var i = 0; i < n; i++) {
      final prev = (i - 1 + n) % n;
      final p0 = pts[i] + normals[prev] * d;
      final p1 = pts[i] + normals[i] * d;
      final hit = _intersect(p0, dirs[prev], p1, dirs[i]);
      if (hit == null) {
        out.add(p1); // collinear junction: shift with the edge
        continue;
      }
      final miter = hit - pts[i];
      if (miter.distance > maxMiter) {
        out.add(pts[i] + miter / miter.distance * maxMiter);
      } else {
        out.add(hit);
      }
    }
    return out;
  }

  static Offset? _intersect(Offset p1, Offset d1, Offset p2, Offset d2) {
    final denom = d1.dx * d2.dy - d1.dy * d2.dx;
    if (denom.abs() < 1e-9) return null;
    final diff = p2 - p1;
    final t = (diff.dx * d2.dy - diff.dy * d2.dx) / denom;
    return p1 + d1 * t;
  }

  // -------------------------------------------------------------------------
  // Partition vertices
  // -------------------------------------------------------------------------

  static bool _onLeft(Offset p) => p.dx < eps;
  static bool _onRight(Offset p) => p.dx > 1 - eps;
  static bool _onTop(Offset p) => p.dy < eps;
  static bool _onBottom(Offset p) => p.dy > 1 - eps;
  static bool _onVertical(Offset p) => _onLeft(p) || _onRight(p);
  static bool _onHorizontal(Offset p) => _onTop(p) || _onBottom(p);
  static bool isCorner(Offset p) => _onVertical(p) && _onHorizontal(p);
  static bool onBorder(Offset p) => _onVertical(p) || _onHorizontal(p);

  /// Every point shared by two or more cells — the points the user can grab
  /// to reshape the cuts. Sorted top-to-bottom, left-to-right so focus order
  /// (screen readers, keyboard) is stable.
  static List<PartitionVertex> vertices(List<LayoutSlot> cells) {
    final found = <PartitionVertex>[];
    for (final c in cells) {
      if (!c.isPolygon) continue;
      for (final p in c.points!) {
        final i = found.indexWhere((v) => near(v.at, p));
        if (i < 0) {
          found.add(PartitionVertex(p, {c.id}));
        } else {
          found[i].cells.add(c.id);
        }
      }
    }
    final out = [for (final v in found) if (v.cells.length >= 2) v];
    for (final v in out) {
      v.removable = _removable(cells, v.at);
    }
    out.sort((a, b) {
      final dy = a.at.dy - b.at.dy;
      if (dy.abs() > eps) return dy < 0 ? -1 : 1;
      return a.at.dx.compareTo(b.at.dx);
    });
    return out;
  }

  static int _indexOf(List<Offset> pts, Offset v) {
    for (var i = 0; i < pts.length; i++) {
      if (near(pts[i], v)) return i;
    }
    return -1;
  }

  /// A point can be removed when it merely bends one cut: exactly two cells
  /// share it, and in both its neighbours are the same two points. Removing
  /// it then straightens that piece of the cut for both cells alike.
  static bool _removable(List<LayoutSlot> cells, Offset v) {
    final owners = [for (final c in cells) if (c.isPolygon && _indexOf(c.points!, v) >= 0) c];
    if (owners.length != 2) return false;
    Set<Offset>? pair;
    for (final c in owners) {
      final pts = c.points!;
      if (pts.length <= 3) return false;
      final i = _indexOf(pts, v);
      final a = pts[(i - 1 + pts.length) % pts.length];
      final b = pts[(i + 1) % pts.length];
      if (pair == null) {
        pair = {a, b};
      } else {
        final ok = (pair.any((x) => near(x, a)) && pair.any((x) => near(x, b)));
        if (!ok) return false;
      }
    }
    return true;
  }

  // -------------------------------------------------------------------------
  // Operations
  // -------------------------------------------------------------------------

  /// [cells] with the shared point [vertex] moved towards [target] under the
  /// topology rules above, plus where the point ended up; null when nothing
  /// would change or the result would be invalid.
  static ({List<LayoutSlot> cells, Offset at})? moveVertex(List<LayoutSlot> cells, Offset vertex, Offset target) {
    Offset moved;
    // Per cell: how to rewrite it. Replace the vertex, or keep the corner and
    // add the moved point before / after it.
    final corner = isCorner(vertex);
    var alongHorizontal = false; // corner split: sliding along a top/bottom border
    if (corner) {
      final dx = (target.dx - vertex.dx).abs(), dy = (target.dy - vertex.dy).abs();
      if (dx < 1e-4 && dy < 1e-4) return null;
      alongHorizontal = dx >= dy;
      moved = alongHorizontal
          ? Offset(target.dx.clamp(0.0, 1.0), vertex.dy)
          : Offset(vertex.dx, target.dy.clamp(0.0, 1.0));
    } else if (_onHorizontal(vertex)) {
      moved = Offset(target.dx.clamp(0.0, 1.0), vertex.dy);
    } else if (_onVertical(vertex)) {
      moved = Offset(vertex.dx, target.dy.clamp(0.0, 1.0));
    } else {
      moved = Offset(target.dx.clamp(0.01, 0.99), target.dy.clamp(0.01, 0.99));
    }
    // A border point pulled onto a corner merges with it.
    for (final c in const [Offset(0, 0), Offset(1, 0), Offset(1, 1), Offset(0, 1)]) {
      if ((moved - c).distance < eps * 2) moved = c;
    }
    if ((moved - vertex).distance < 1e-5) return null;

    final out = <LayoutSlot>[];
    final changed = <int>[];
    for (final cell in cells) {
      final pts = cell.points;
      final i = pts == null ? -1 : _indexOf(pts, vertex);
      if (pts == null || i < 0) {
        out.add(cell);
        continue;
      }
      final next = List<Offset>.of(pts);
      if (corner) {
        // The other border (the one we are NOT sliding along).
        bool alongOther(Offset n) => alongHorizontal
            ? (n.dx - vertex.dx).abs() < eps
            : (n.dy - vertex.dy).abs() < eps;
        final prev = pts[(i - 1 + pts.length) % pts.length];
        final nxt = pts[(i + 1) % pts.length];
        final pOther = alongOther(prev), nOther = alongOther(nxt);
        if (pOther && nOther) {
          out.add(cell);
          continue;
        } else if (nOther) {
          next.insert(i, moved); // moved point, then the kept corner
        } else if (pOther) {
          next.insert(i + 1, moved); // kept corner, then the moved point
        } else {
          next[i] = moved;
        }
      } else {
        next[i] = moved;
      }
      changed.add(out.length);
      out.add(LayoutSlot.poly(cell.id, dedupe(next)));
    }
    if (changed.isEmpty) return null;
    return _valid(cells, out, changed) ? (cells: out, at: moved) : null;
  }

  /// Insert a new point into the cut [p]–[q] shared by cells [a] and [b], at
  /// [at] (projected onto the cut when null: its midpoint).
  static List<LayoutSlot>? insertVertex(
    List<LayoutSlot> cells, {
    required String a,
    required String b,
    required Offset p,
    required Offset q,
    Offset? at,
  }) {
    final point = at ?? (p + q) / 2;
    return _insertAlong(cells, a, b, p, q, [point]);
  }

  /// Insert [points] (ordered from [p] towards [q]) into the edge p–q of
  /// cells [a] and [b], in the right order for each cell's winding.
  static List<LayoutSlot>? _insertAlong(
      List<LayoutSlot> cells, String a, String b, Offset p, Offset q, List<Offset> points) {
    final out = <LayoutSlot>[];
    final changed = <int>[];
    for (final cell in cells) {
      final pts = cell.points;
      if ((cell.id != a && cell.id != b) || pts == null) {
        out.add(cell);
        continue;
      }
      var done = false;
      final next = <Offset>[];
      for (var i = 0; i < pts.length; i++) {
        final u = pts[i], v = pts[(i + 1) % pts.length];
        next.add(u);
        if (done) continue;
        if (near(u, p) && near(v, q)) {
          next.addAll(points);
          done = true;
        } else if (near(u, q) && near(v, p)) {
          next.addAll(points.reversed);
          done = true;
        }
      }
      if (!done) return null;
      changed.add(out.length);
      out.add(LayoutSlot.poly(cell.id, next));
    }
    if (changed.length != 2) return null;
    return _valid(cells, out, changed) ? out : null;
  }

  /// Remove the shared point [vertex] (only when [PartitionVertex.removable]).
  static List<LayoutSlot>? removeVertex(List<LayoutSlot> cells, Offset vertex) {
    if (!_removable(cells, vertex)) return null;
    final out = <LayoutSlot>[];
    final changed = <int>[];
    for (final cell in cells) {
      final pts = cell.points;
      final i = pts == null ? -1 : _indexOf(pts, vertex);
      if (pts == null || i < 0) {
        out.add(cell);
        continue;
      }
      changed.add(out.length);
      out.add(LayoutSlot.poly(cell.id, List.of(pts)..removeAt(i)));
    }
    return _valid(cells, out, changed) ? out : null;
  }

  /// Turn the straight cut [p]–[q] between [a] and [b] into an editable
  /// zigzag of [teeth] teeth whose points sit [amplitude] (fraction of the
  /// cut length) either side of it. Each point can then be moved on its own.
  static List<LayoutSlot>? zigzag(
    List<LayoutSlot> cells, {
    required String a,
    required String b,
    required Offset p,
    required Offset q,
    int teeth = 4,
    double amplitude = 0.06,
  }) {
    final e = q - p;
    final len = e.distance;
    if (len < 0.02 || teeth < 1) return null;
    final normal = Offset(-e.dy, e.dx) / len;
    final steps = teeth * 2;
    final points = <Offset>[
      for (var k = 1; k < steps; k++)
        p + e * (k / steps) + (k.isOdd ? normal * (amplitude * len * ((k ~/ 2).isEven ? 1 : -1)) : Offset.zero),
    ];
    return _insertAlong(cells, a, b, p, q, points);
  }

  /// Remove every removable point on the cut between cells [a] and [b], so
  /// a zigzag (or any bent cut) becomes one straight line again.
  static List<LayoutSlot> straightenCut(List<LayoutSlot> cells, String a, String b) {
    var cur = cells;
    for (var guard = 0; guard < 200; guard++) {
      final va = [for (final c in cur) if (c.id == a) ...?c.points];
      Offset? hit;
      for (final v in va) {
        final owners = [for (final c in cur) if (c.isPolygon && _indexOf(c.points!, v) >= 0) c.id];
        if (owners.length == 2 && owners.contains(b) && _removable(cur, v)) {
          hit = v;
          break;
        }
      }
      if (hit == null) break;
      final next = removeVertex(cur, hit);
      if (next == null) break;
      cur = next;
    }
    return cur;
  }

  /// Snap a point being dragged to the thirds/quarters/half of the canvas and
  /// to the coordinates of other partition points, within [threshold].
  /// Returns the snapped point and the guide lines that caught it.
  static (Offset, double?, double?) snap(Offset p, Iterable<Offset> others, {double threshold = 0.015}) {
    final xs = <double>[0.25, 1 / 3, 0.5, 2 / 3, 0.75];
    final ys = <double>[0.25, 1 / 3, 0.5, 2 / 3, 0.75];
    for (final o in others) {
      xs.add(o.dx);
      ys.add(o.dy);
    }
    double? best(double v, List<double> ts) {
      double? hit;
      var d = threshold;
      for (final t in ts) {
        final dd = (v - t).abs();
        if (dd <= d) {
          d = dd;
          hit = t;
        }
      }
      return hit;
    }

    final sx = best(p.dx, xs), sy = best(p.dy, ys);
    return (Offset(sx ?? p.dx, sy ?? p.dy), sx, sy);
  }

  /// Angle in degrees (0..180) of the cut p–q in canvas pixels for a canvas
  /// of [aspect] (w / h) — shown while dragging so a diagonal can be set
  /// precisely.
  static double angleDegrees(Offset p, Offset q, double aspect) {
    final v = Offset((q.dx - p.dx) * aspect, q.dy - p.dy);
    var deg = math.atan2(v.dy, v.dx) * 180 / math.pi;
    if (deg < 0) deg += 180;
    return deg % 180;
  }

  /// Whether [after] is a valid partition given it was derived from the
  /// valid [before] by changing the cells at [changed].
  static bool _valid(List<LayoutSlot> before, List<LayoutSlot> after, List<int> changed) {
    for (final i in changed) {
      final pts = after[i].points!;
      if (pts.length < 3) return false;
      if (pts.any((p) => p.dx < -1e-6 || p.dx > 1 + 1e-6 || p.dy < -1e-6 || p.dy > 1 + 1e-6)) return false;
      final a1 = signedArea(pts);
      if (a1.abs() < minArea) return false;
      final orig = before.firstWhere((c) => c.id == after[i].id);
      final a0 = signedArea(orig.isPolygon ? orig.points! : [orig.rect.topLeft, orig.rect.topRight, orig.rect.bottomRight, orig.rect.bottomLeft]);
      if (a0.sign != a1.sign) return false;
      if (!isSimple(pts)) return false;
    }
    // No changed cell may cross any other cell.
    for (final i in changed) {
      final pa = after[i].points!;
      for (var j = 0; j < after.length; j++) {
        if (j == i || !after[j].isPolygon) continue;
        final pb = after[j].points!;
        for (var x = 0; x < pa.length; x++) {
          final a = pa[x], b = pa[(x + 1) % pa.length];
          for (var y = 0; y < pb.length; y++) {
            if (segmentsCross(a, b, pb[y], pb[(y + 1) % pb.length])) return false;
          }
        }
      }
    }
    // The cells must still tile the canvas: their areas sum to the whole.
    var total = 0.0;
    for (final c in after) {
      if (c.isPolygon) {
        total += signedArea(c.points!).abs();
      } else {
        total += c.rect.width * c.rect.height;
      }
    }
    var was = 0.0;
    for (final c in before) {
      if (c.isPolygon) {
        was += signedArea(c.points!).abs();
      } else {
        was += c.rect.width * c.rect.height;
      }
    }
    return (total - was).abs() < 1e-3;
  }
}

/// A point shared by two or more cells.
class PartitionVertex {
  PartitionVertex(this.at, this.cells);
  final Offset at;
  final Set<String> cells;

  /// Whether removing it keeps a valid partition (it only bends one cut).
  bool removable = false;

  bool get onBorder => PartitionGeometry.onBorder(at);
  bool get isCorner => PartitionGeometry.isCorner(at);

  /// Stable identity while the point is not moved.
  String get key => '${(at.dx * 1000).round()}:${(at.dy * 1000).round()}';
}
