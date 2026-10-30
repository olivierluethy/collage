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
