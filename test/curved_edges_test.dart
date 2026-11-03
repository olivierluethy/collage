import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';

import 'package:collage/models/layout_template.dart';
import 'package:collage/widgets/curved_edges.dart';

LayoutSlot _rectPoly(String id, double l, double t, double r, double b) =>
    LayoutSlot.poly(id, [Offset(l, t), Offset(r, t), Offset(r, b), Offset(l, b)]);

List<Offset> _scaled(List<Offset> pts, double s) => [for (final p in pts) p * s];

/// Points sampled evenly along a path's (single) contour.
List<Offset> _samples(Path path, int n) {
  final m = path.computeMetrics().first;
  return [
    for (var i = 0; i <= n; i++) m.getTangentForOffset(m.length * i / n)!.position,
  ];
}

Matcher _closeTo(Offset o, [double eps = 1e-3]) => predicate<Offset>(
      (v) => (v - o).distance <= eps,
      'within $eps of $o',
    );

void expectRectClose(Rect actual, Rect expected, [double eps = 1e-6]) {
  expect(actual.left, closeTo(expected.left, eps));
  expect(actual.top, closeTo(expected.top, eps));
  expect(actual.right, closeTo(expected.right, eps));
  expect(actual.bottom, closeTo(expected.bottom, eps));
}

void main() {
  // Two halves of a square, side by side, sharing the vertical edge x = 0.5.
  final left = _rectPoly('L', 0, 0, 0.5, 1);
  final right = _rectPoly('R', 0.5, 0, 1, 1);
  final pair = [left, right];

  group('canonical direction and edge-local coordinates', () {
    test('canonicalBefore is antisymmetric for distinct points', () {
      const pts = [Offset(0, 0), Offset(0.5, 0), Offset(0.5, 1), Offset(1, 0.3)];
      for (final a in pts) {
        for (final b in pts) {
          if (a == b) continue;
          expect(canonicalBefore(a, b), isNot(canonicalBefore(b, a)), reason: '$a vs $b');
        }
      }
      // smaller x first, then smaller y
      expect(canonicalBefore(const Offset(0.2, 0.9), const Offset(0.4, 0.1)), isTrue);
      expect(canonicalBefore(const Offset(0.5, 0), const Offset(0.5, 1)), isTrue);
    });

    test('edgeLocal inverts edgePoint', () {
      const p = Offset(10, 20), q = Offset(70, -5);
      for (final uv in const [Offset(0, 0), Offset(1, 0), Offset(0.3, 0.2), Offset(0.8, -0.4)]) {
        expect(edgeLocal(p, q, edgePoint(p, q, uv)), _closeTo(uv, 1e-9));
      }
      expect(edgePoint(p, q, Offset.zero), p);
      expect(edgePoint(p, q, const Offset(1, 0)), _closeTo(q, 1e-9));
    });

    test('edgeLocal of a degenerate edge is zero', () {
      expect(edgeLocal(const Offset(1, 1), const Offset(1, 1), const Offset(5, 5)), Offset.zero);
    });

    test('edgeMidpoint: straight edge is the chord midpoint, symmetric curve bulges 3/4 of v', () {
      const p = Offset(0, 0), q = Offset(100, 0);
      expect(edgeMidpoint(p, q, null), const Offset(50, 0));
      expect(edgeMidpoint(p, q, const EdgeShape(a: 'a', b: 'b')), const Offset(50, 0));
      const s = EdgeShape(a: 'a', b: 'b', c1: Offset(1 / 3, 0.2), c2: Offset(2 / 3, 0.2));
      // left normal of +x is +y
      expect(edgeMidpoint(p, q, s), _closeTo(const Offset(50, 15), 1e-9));
    });
  });

  group('findSharedEdges', () {
    test('two neighbouring cells share exactly one edge, in canonical direction', () {
      final edges = findSharedEdges(pair);
      expect(edges, hasLength(1));
      final e = edges.single;
      expect(e.a, 'L');
      expect(e.b, 'R');
      expect(e.key, EdgeShape.keyFor('R', 'L'));
      expect(e.p, const Offset(0.5, 0));
      expect(e.q, const Offset(0.5, 1));
      expect(canonicalBefore(e.p, e.q), isTrue);
    });

    test('the result does not depend on slot order', () {
      final a = findSharedEdges(pair).single;
      final b = findSharedEdges(pair.reversed.toList()).single;
      expect(b.key, a.key);
      expect(b.p, a.p);
      expect(b.q, a.q);
    });

    test('plain rectangle slots (no points) are ignored', () {
      const rects = [
        LayoutSlot(id: 'L', rect: Rect.fromLTWH(0, 0, 0.5, 1)),
        LayoutSlot(id: 'R', rect: Rect.fromLTWH(0.5, 0, 0.5, 1)),
      ];
      expect(findSharedEdges(rects), isEmpty);
    });

    test('cells that only touch at a corner share no edge', () {
      final a = _rectPoly('a', 0, 0, 0.5, 0.5);
      final b = _rectPoly('b', 0.5, 0.5, 1, 1);
      expect(findSharedEdges([a, b]), isEmpty);
    });

    test('a T-junction is not a shared edge until polygonized', () {
      final slots = [
        _rectPoly('L', 0, 0, 0.5, 1),
        _rectPoly('RT', 0.5, 0, 1, 0.5),
        _rectPoly('RB', 0.5, 0.5, 1, 1),
      ];
      final raw = findSharedEdges(slots);
      expect(raw.map((e) => e.key), [EdgeShape.keyFor('RT', 'RB')]);
    });
  });

  group('polygonizeSlots', () {
    test('rectangles become four-point polygons with the same ids and bounds', () {
      const rects = [
        LayoutSlot(id: 'L', rect: Rect.fromLTWH(0, 0, 0.5, 1)),
        LayoutSlot(id: 'R', rect: Rect.fromLTWH(0.5, 0, 0.5, 1)),
      ];
      final out = polygonizeSlots(rects);
      expect(out.map((s) => s.id), ['L', 'R']);
      for (var i = 0; i < out.length; i++) {
        expect(out[i].isPolygon, isTrue);
        expect(out[i].points, hasLength(4));
        expectRectClose(out[i].rect, rects[i].rect);
      }
      expect(findSharedEdges(out), hasLength(1));
    });

    test('corner-to-corner neighbours get no extra vertices', () {
      final out = polygonizeSlots(pair);
      expect(out[0].points, left.points);
      expect(out[1].points, right.points);
    });

    test('a T-junction vertex is inserted into the long edge', () {
      final slots = [
        _rectPoly('L', 0, 0, 0.5, 1),
        _rectPoly('RT', 0.5, 0, 1, 0.5),
        _rectPoly('RB', 0.5, 0.5, 1, 1),
      ];
      final out = polygonizeSlots(slots);
      expect(out[0].points, const [
        Offset(0, 0),
        Offset(0.5, 0),
        Offset(0.5, 0.5),
        Offset(0.5, 1),
        Offset(0, 1),
      ]);
      // the short cells are already exact
      expect(out[1].points, hasLength(4));
      expect(out[2].points, hasLength(4));

      final keys = findSharedEdges(out).map((e) => e.key).toSet();
      expect(keys, {
        EdgeShape.keyFor('L', 'RT'),
        EdgeShape.keyFor('L', 'RB'),
        EdgeShape.keyFor('RT', 'RB'),
      });
    });

    test('several T-junction vertices on one edge are inserted in edge order', () {
      final slots = [
        _rectPoly('L', 0, 0, 0.5, 1),
        _rectPoly('R1', 0.5, 0, 1, 1 / 3),
        _rectPoly('R2', 0.5, 1 / 3, 1, 2 / 3),
        _rectPoly('R3', 0.5, 2 / 3, 1, 1),
      ];
      final l = polygonizeSlots(slots).first.points!;
      // L walks clockwise: (0.5,0) → (0.5,1) on its right edge.
      expect(l, hasLength(6));
      expect(l[1], const Offset(0.5, 0));
      expect(l[2], _closeTo(const Offset(0.5, 1 / 3), 1e-9));
      expect(l[3], _closeTo(const Offset(0.5, 2 / 3), 1e-9));
      expect(l[4], const Offset(0.5, 1));
      expect(findSharedEdges(polygonizeSlots(slots)), hasLength(5));
    });

    test('a vertex off the edge line is not inserted', () {
      final slots = [
        _rectPoly('L', 0, 0, 0.5, 1),
        _rectPoly('X', 0.6, 0.4, 0.9, 0.6), // floats beside, not touching
      ];
      expect(polygonizeSlots(slots).first.points, hasLength(4));
    });
  });

  group('curvedEdgesOf', () {
    const bend = EdgeShape(a: 'L', b: 'R', c1: Offset(1 / 3, 0.2), c2: Offset(2 / 3, 0.2));

    test('both cells pick up the shared edge, with opposite directions', () {
      final shapes = {bend.key: bend};
      final l = curvedEdgesOf(left, pair, shapes);
      final r = curvedEdgesOf(right, pair, shapes);
      // L: edge 1 is (0.5,0)→(0.5,1), canonical. R: edge 3 is (0.5,1)→(0.5,0), reversed.
      expect(l.keys, [1]);
      expect(l[1]!.$2, isFalse);
      expect(r.keys, [3]);
      expect(r[3]!.$2, isTrue);
      expect(identical(l[1]!.$1, r[3]!.$1), isTrue);
    });

    test('straight shapes, no shapes and non-polygon slots yield nothing', () {
      const straight = EdgeShape(a: 'L', b: 'R');
      expect(curvedEdgesOf(left, pair, {straight.key: straight}), isEmpty);
      expect(curvedEdgesOf(left, pair, const {}), isEmpty);
      const rect = LayoutSlot(id: 'L', rect: Rect.fromLTWH(0, 0, 0.5, 1));
      expect(curvedEdgesOf(rect, [rect, right], {bend.key: bend}), isEmpty);
    });

    test('a zigzag with zero amplitude counts as straight', () {
      const flat = EdgeShape(a: 'L', b: 'R', zigCount: 6);
      expect(flat.isStraight, isTrue);
      expect(curvedEdgesOf(left, pair, {flat.key: flat}), isEmpty);
    });
  });

  group('appendShapedEdge — both sides draw the same edge', () {
    const p = Offset(50, 0), q = Offset(50, 100);
    final shapes = <String, EdgeShape>{
      'curve': const EdgeShape(a: 'a', b: 'b', c1: Offset(0.25, 0.3), c2: Offset(0.8, -0.1)),
      'wave': const EdgeShape(a: 'a', b: 'b', c1: Offset(1 / 3, 0.25), c2: Offset(2 / 3, -0.25)),
      'zigzag': const EdgeShape(a: 'a', b: 'b', zigAmp: 0.05, zigCount: 7),
      'curved zigzag': const EdgeShape(
          a: 'a', b: 'b', c1: Offset(1 / 3, 0.15), c2: Offset(2 / 3, 0.15), zigAmp: 0.03, zigCount: 4),
    };

    for (final MapEntry(key: name, value: shape) in shapes.entries) {
      test('$name: forward and reversed traces coincide', () {
        final fwd = Path()..moveTo(p.dx, p.dy);
        appendShapedEdge(fwd, p, q, shape, false);
        final rev = Path()..moveTo(q.dx, q.dy);
        appendShapedEdge(rev, q, p, shape, true);

        final mf = fwd.computeMetrics().single;
        final mr = rev.computeMetrics().single;
        expect(mr.length, closeTo(mf.length, 1e-3));

        const n = 64;
        final a = _samples(fwd, n);
        final b = _samples(rev, n).reversed.toList();
        for (var i = 0; i <= n; i++) {
          expect(b[i], _closeTo(a[i], 0.05), reason: 'sample $i');
        }
        // ends exactly at the target
        expect(a.first, _closeTo(p));
        expect(a.last, _closeTo(q));
        expect(_samples(rev, n).last, _closeTo(p));
      });
    }

    test('a straight shape draws a straight line', () {
      final path = Path()..moveTo(p.dx, p.dy);
      appendShapedEdge(path, p, q, const EdgeShape(a: 'a', b: 'b'), false);
      expect(path.computeMetrics().single.length, closeTo(100, 1e-3));
      for (final s in _samples(path, 20)) {
        expect(s.dx, closeTo(50, 1e-6));
      }
    });

    test('zigzag teeth reach exactly zigAmp × length on the left normal', () {
      const s = EdgeShape(a: 'a', b: 'b', zigAmp: 0.05, zigCount: 5);
      final path = Path()..moveTo(p.dx, p.dy);
      appendShapedEdge(path, p, q, s, false);
      final b = path.getBounds();
      // left normal of +y is -x
      expect(b.left, closeTo(45, 1e-6));
      expect(b.right, closeTo(50, 1e-6));
      expect(b.top, closeTo(0, 1e-6));
      expect(b.bottom, closeTo(100, 1e-6));
    });
  });

  group('shapedCellPath', () {
    const scale = 100.0;
    final lPoly = _scaled(left.points!, scale);
    final rPoly = _scaled(right.points!, scale);
    const canvas = Rect.fromLTWH(0, 0, scale, scale);

    test('no curved edges gives the plain polygon', () {
      final path = shapedCellPath(lPoly, const {});
      expectRectClose(path.getBounds(), const Rect.fromLTWH(0, 0, 50, 100));
      expect(path.contains(const Offset(25, 50)), isTrue);
      expect(path.contains(const Offset(75, 50)), isFalse);
    });

    test('an empty polygon gives an empty path', () {
      expect(shapedCellPath(const [], const {}).getBounds(), Rect.zero);
    });

    test('zero-amplitude shape passed explicitly still yields the rectangle', () {
      const flat = EdgeShape(a: 'L', b: 'R');
      final path = shapedCellPath(lPoly, {1: (flat, false)});
      expectRectClose(path.getBounds(), const Rect.fromLTWH(0, 0, 50, 100));
    });

    final cases = <String, EdgeShape>{
      'curve': const EdgeShape(a: 'L', b: 'R', c1: Offset(1 / 3, 0.2), c2: Offset(2 / 3, 0.2)),
      'wave': const EdgeShape(a: 'L', b: 'R', c1: Offset(1 / 3, 0.3), c2: Offset(2 / 3, -0.3)),
      'zigzag': const EdgeShape(a: 'L', b: 'R', zigAmp: 0.04, zigCount: 8),
    };

    for (final MapEntry(key: name, value: shape) in cases.entries) {
      group(name, () {
        late Path lp, rp;
        setUp(() {
          final shapes = {shape.key: shape};
          lp = shapedCellPath(lPoly, curvedEdgesOf(left, pair, shapes));
          rp = shapedCellPath(rPoly, curvedEdgesOf(right, pair, shapes));
        });

        test('cells meet with no gap and no overlap', () {
          // Probe a grid that straddles the shared edge, away from the
          // boundary itself (where contains() is ambiguous).
          var probed = 0;
          for (var y = 1.5; y < 100; y += 3) {
            for (var x = 20.25; x < 80; x += 1.5) {
              final pt = Offset(x, y);
              final inL = lp.contains(pt), inR = rp.contains(pt);
              expect(inL && inR, isFalse, reason: 'overlap at $pt');
              expect(inL || inR, isTrue, reason: 'gap at $pt');
              probed++;
            }
          }
          expect(probed, greaterThan(1000));
        });

        test('paths stay inside the canvas and the outer edges stay straight', () {
          for (final path in [lp, rp]) {
            final b = path.getBounds();
            expect(canvas.inflate(1e-6).contains(b.topLeft), isTrue);
            expect(canvas.inflate(1e-6).contains(b.bottomRight), isTrue);
          }
          // The untouched outer edges are exactly on the canvas border.
          expectRectClose(
              Rect.fromLTRB(lp.getBounds().left, lp.getBounds().top, 0, lp.getBounds().bottom),
              const Rect.fromLTRB(0, 0, 0, 100));
          expect(rp.getBounds().right, closeTo(100, 1e-6));
          // The bend changes the shared edge only: the cells cover the canvas.
          final union = lp.getBounds().expandToInclude(rp.getBounds());
          expectRectClose(union, canvas);
        });

        test('each path is one closed contour', () {
          for (final path in [lp, rp]) {
            final ms = path.computeMetrics().toList();
            expect(ms, hasLength(1));
            expect(ms.single.isClosed, isTrue);
          }
        });
      });
    }

    test('a symmetric curve gives mirror-symmetric cell areas', () {
      const s = EdgeShape(a: 'L', b: 'R', c1: Offset(1 / 3, 0.2), c2: Offset(2 / 3, 0.2));
      final lp = shapedCellPath(lPoly, curvedEdgesOf(left, pair, {s.key: s}));
      // Mirrored about y = 50, containment must match.
      for (var y = 1.5; y < 50; y += 2.5) {
        for (var x = 1.25; x < 50; x += 2.5) {
          expect(lp.contains(Offset(x, y)), lp.contains(Offset(x, 100 - y)), reason: '($x,$y)');
        }
      }
      // Positive v bends into the left cell (left normal of the canonical
      // downward edge is -x): the edge midpoint moves left by
      // 0.75 × 0.2 × 100 = 15, to x = 35.
      expect(lp.contains(const Offset(34, 50)), isTrue);
      expect(lp.contains(const Offset(36, 50)), isFalse);
    });

    test('safeBounds is never empty', () {
      final line = Path()
        ..moveTo(10, 10)
        ..lineTo(10, 10);
      final b = safeBounds(line);
      expect(b.width, greaterThanOrEqualTo(1));
      expect(b.height, greaterThanOrEqualTo(1));
      final r = safeBounds(shapedCellPath(lPoly, const {}));
      expectRectClose(r, const Rect.fromLTWH(0, 0, 50, 100));
    });
  });
}
