import 'dart:ui';

import 'package:flutter/painting.dart' show Axis;

import '../../models/layout_template.dart';

/// A shared edge between neighbouring rectangular slots that the user can drag
/// to resize them: a vertical line at x = [pos] (for [Axis.vertical]) or a
/// horizontal line at y = [pos], spanning [start]..[end] on the other axis.
/// [before] are the slots left of / above the line, [after] those right of /
/// below it. All values are layout fractions (0..1).
class SlotSplit {
  const SlotSplit({
    required this.axis,
    required this.pos,
    required this.start,
    required this.end,
    required this.before,
    required this.after,
  });

  final Axis axis;
  final double pos;
  final double start;
  final double end;
  final Set<String> before;
  final Set<String> after;
}

const _eps = 0.002;

/// Every draggable edge in [slots]. Slots that touch the same line and chain
/// together through overlaps form one split; separate segments on the same
/// line stay independent. Layouts with polygon slots have no splits.
List<SlotSplit> findSplits(List<LayoutSlot> slots) {
  if (slots.any((s) => s.isPolygon)) return const [];
  return [..._find(slots, Axis.vertical), ..._find(slots, Axis.horizontal)];
}

List<SlotSplit> _find(List<LayoutSlot> slots, Axis axis) {
  final v = axis == Axis.vertical;
  double lo(Rect r) => v ? r.left : r.top; // along the moving axis
  double hi(Rect r) => v ? r.right : r.bottom;
  double a0(Rect r) => v ? r.top : r.left; // along the line
  double a1(Rect r) => v ? r.bottom : r.right;

  // Pairs (a ends where b starts) that overlap along the line.
  final pairs = <(LayoutSlot, LayoutSlot)>[];
  for (final a in slots) {
    for (final b in slots) {
      if (identical(a, b)) continue;
      if ((hi(a.rect) - lo(b.rect)).abs() > _eps) continue;
      if (hi(a.rect) < _eps || hi(a.rect) > 1 - _eps) continue; // outer edge
      final overlap = (a1(a.rect) < a1(b.rect) ? a1(a.rect) : a1(b.rect)) -
          (a0(a.rect) > a0(b.rect) ? a0(a.rect) : a0(b.rect));
      if (overlap > _eps) pairs.add((a, b));
    }
  }

  // Union pairs that share a slot on the same line into one split.
  final parent = List<int>.generate(pairs.length, (i) => i);
  int root(int i) => parent[i] == i ? i : (parent[i] = root(parent[i]));
  for (var i = 0; i < pairs.length; i++) {
    for (var j = i + 1; j < pairs.length; j++) {
      final (ai, bi) = pairs[i];
      final (aj, bj) = pairs[j];
      final sameLine = (hi(ai.rect) - hi(aj.rect)).abs() <= _eps;
      if (sameLine && (ai.id == aj.id || bi.id == bj.id)) parent[root(i)] = root(j);
    }
  }

  final groups = <int, List<(LayoutSlot, LayoutSlot)>>{};
  for (var i = 0; i < pairs.length; i++) {
    groups.putIfAbsent(root(i), () => []).add(pairs[i]);
  }
  return [
    for (final g in groups.values)
      SlotSplit(
        axis: axis,
        pos: hi(g.first.$1.rect),
        start: g.map((p) => [a0(p.$1.rect), a0(p.$2.rect)]).expand((x) => x).reduce((x, y) => x < y ? x : y),
        end: g.map((p) => [a1(p.$1.rect), a1(p.$2.rect)]).expand((x) => x).reduce((x, y) => x > y ? x : y),
        before: {for (final p in g) p.$1.id},
        after: {for (final p in g) p.$2.id},
      ),
  ];
}

/// [slots] with [split] moved to [pos], clamped so no slot on either side gets
/// smaller than [minSize].
List<LayoutSlot> moveSplit(List<LayoutSlot> slots, SlotSplit split, double pos, {double minSize = 0.08}) {
  final v = split.axis == Axis.vertical;
  var minPos = 0.0, maxPos = 1.0;
  for (final s in slots) {
    if (split.before.contains(s.id)) {
      final start = v ? s.rect.left : s.rect.top;
      if (start + minSize > minPos) minPos = start + minSize;
    }
    if (split.after.contains(s.id)) {
      final end = v ? s.rect.right : s.rect.bottom;
      if (end - minSize < maxPos) maxPos = end - minSize;
    }
  }
  if (minPos > maxPos) return slots;
  final p = pos.clamp(minPos, maxPos);
  return [
    for (final s in slots)
      if (split.before.contains(s.id))
        LayoutSlot(
          id: s.id,
          rect: v
              ? Rect.fromLTRB(s.rect.left, s.rect.top, p, s.rect.bottom)
              : Rect.fromLTRB(s.rect.left, s.rect.top, s.rect.right, p),
        )
      else if (split.after.contains(s.id))
        LayoutSlot(
          id: s.id,
          rect: v
              ? Rect.fromLTRB(p, s.rect.top, s.rect.right, s.rect.bottom)
              : Rect.fromLTRB(s.rect.left, p, s.rect.right, s.rect.bottom),
        )
      else
        s,
  ];
}

// ---------------------------------------------------------------------------
// Polygon (diagonal / mosaic) layouts
// ---------------------------------------------------------------------------

/// A shared edge [p]–[q] between polygon cells (layout fractions). Dragging
/// shifts the edge along its normal; endpoints on the outer border slide
/// along it, inner endpoints move for every cell that shares them.
class PolySplit {
  const PolySplit({required this.p, required this.q, required this.slots});
  final Offset p;
  final Offset q;
  final Set<String> slots;

  /// Unit normal of the edge, in layout fractions.
  Offset get normal {
    final d = q - p;
    final len = d.distance;
    return len == 0 ? Offset.zero : Offset(-d.dy / len, d.dx / len);
  }
}

/// Corners of a slot as a polygon (rectangles become four points).
List<Offset> slotPoints(LayoutSlot s) => s.isPolygon
    ? s.points!
    : [s.rect.topLeft, s.rect.topRight, s.rect.bottomRight, s.rect.bottomLeft];

bool _near(Offset a, Offset b) => (a - b).distance <= _eps * 2;

bool _onSameBorder(Offset a, Offset b) =>
    (a.dx < _eps && b.dx < _eps) ||
    (a.dx > 1 - _eps && b.dx > 1 - _eps) ||
    (a.dy < _eps && b.dy < _eps) ||
    (a.dy > 1 - _eps && b.dy > 1 - _eps);

/// Every interior edge shared by two or more cells. Only for layouts that
/// contain polygon cells; rectangular grids use [findSplits].
List<PolySplit> findPolySplits(List<LayoutSlot> slots) {
  if (!slots.any((s) => s.isPolygon)) return const [];
  final found = <PolySplit>[];
  for (final s in slots) {
    final pts = slotPoints(s);
    for (var i = 0; i < pts.length; i++) {
      final a = pts[i], b = pts[(i + 1) % pts.length];
      if (_onSameBorder(a, b) || (a - b).distance < 0.02) continue;
      final existing = found.indexWhere(
          (e) => (_near(e.p, a) && _near(e.q, b)) || (_near(e.p, b) && _near(e.q, a)));
      if (existing >= 0) {
        found[existing] = PolySplit(p: found[existing].p, q: found[existing].q, slots: {...found[existing].slots, s.id});
      } else {
        found.add(PolySplit(p: a, q: b, slots: {s.id}));
      }
    }
  }
  return [for (final e in found) if (e.slots.length >= 2) e];
}

/// Where [pt] ends up when its edge shifts by [d] along [n]: corners stay,
/// border points slide along their border, inner points move with the edge.
Offset _slide(Offset pt, Offset n, double d) {
  final onX = pt.dx < _eps || pt.dx > 1 - _eps; // on the left/right border
  final onY = pt.dy < _eps || pt.dy > 1 - _eps; // on the top/bottom border
  if (onX && onY) return pt;
  final c = n.dx * pt.dx + n.dy * pt.dy + d; // shifted line: n·x = c
  if (onY) {
    if (n.dx.abs() < 1e-6) return pt;
    return Offset(((c - n.dy * pt.dy) / n.dx).clamp(0.0, 1.0), pt.dy);
  }
  if (onX) {
    if (n.dy.abs() < 1e-6) return pt;
    return Offset(pt.dx, ((c - n.dx * pt.dx) / n.dy).clamp(0.0, 1.0));
  }
  return pt + n * d;
}

double _signedArea(List<Offset> pts) {
  var a = 0.0;
  for (var i = 0; i < pts.length; i++) {
    final p = pts[i], q = pts[(i + 1) % pts.length];
    a += p.dx * q.dy - q.dx * p.dy;
  }
  return a / 2;
}

bool _convex(List<Offset> pts) {
  var sign = 0;
  for (var i = 0; i < pts.length; i++) {
    final a = pts[i], b = pts[(i + 1) % pts.length], c = pts[(i + 2) % pts.length];
    final cross = (b.dx - a.dx) * (c.dy - b.dy) - (b.dy - a.dy) * (c.dx - b.dx);
    if (cross.abs() < 1e-9) continue;
    final s = cross > 0 ? 1 : -1;
    if (sign == 0) sign = s;
    if (s != sign) return false;
  }
  return true;
}

/// [slots] with [split] shifted by [d] along its normal, or null when that
/// would leave a cell too small, concave, flipped or outside the layout.
List<LayoutSlot>? movePolySplit(List<LayoutSlot> slots, PolySplit split, double d, {double minArea = 0.01}) {
  final n = split.normal;
  if (n == Offset.zero) return null;
  final p2 = _slide(split.p, n, d);
  final q2 = _slide(split.q, n, d);
  final out = <LayoutSlot>[];
  for (final s in slots) {
    final pts = slotPoints(s);
    var changed = false;
    final moved = <Offset>[];
    for (final pt in pts) {
      if (_near(pt, split.p)) {
        moved.add(p2);
        changed = true;
      } else if (_near(pt, split.q)) {
        moved.add(q2);
        changed = true;
      } else {
        moved.add(pt);
      }
    }
    if (!changed) {
      out.add(s);
      continue;
    }
    final before = _signedArea(pts);
    final after = _signedArea(moved);
    final inside = moved.every((m) => m.dx >= -_eps && m.dx <= 1 + _eps && m.dy >= -_eps && m.dy <= 1 + _eps);
    if (!inside || after.abs() < minArea || before.sign != after.sign || !_convex(moved)) return null;
    out.add(LayoutSlot.poly(s.id, moved));
  }
  return out;
}
