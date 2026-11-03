import 'dart:ui';

/// One hole in a layout. A slot is normally a rectangle (normalised 0..1 in the
/// collage content area), but may instead be an arbitrary convex polygon via
/// [points] — this is how diagonal / mosaic templates are expressed. When
/// [points] is set, [rect] is its bounding box (used for ordering, pan/zoom and
/// backward compatibility). Rectangular slots keep [points] null and render
/// exactly as before, so straight grids never regress.
class LayoutSlot {
  const LayoutSlot({required this.id, required this.rect, this.points});

  /// Build a polygon slot from normalised vertices; [rect] is derived as their
  /// bounding box.
  factory LayoutSlot.poly(String id, List<Offset> points) {
    var minX = double.infinity, minY = double.infinity;
    var maxX = -double.infinity, maxY = -double.infinity;
    for (final p in points) {
      if (p.dx < minX) minX = p.dx;
      if (p.dy < minY) minY = p.dy;
      if (p.dx > maxX) maxX = p.dx;
      if (p.dy > maxY) maxY = p.dy;
    }
    return LayoutSlot(
      id: id,
      rect: Rect.fromLTRB(minX, minY, maxX, maxY),
      points: points,
    );
  }

  final String id;
  final Rect rect; // bounding box in 0..1
  final List<Offset>? points; // optional convex polygon in 0..1; null => rect

  bool get isPolygon => points != null && points!.length >= 3;

  Map<String, dynamic> toJson() => {
        'id': id,
        'l': rect.left,
        't': rect.top,
        'r': rect.right,
        'b': rect.bottom,
        if (points != null)
          'pts': points!.map((p) => [p.dx, p.dy]).toList(),
      };

  factory LayoutSlot.fromJson(Map<String, dynamic> j) => LayoutSlot(
        id: j['id'] as String,
        rect: Rect.fromLTRB(
          (j['l'] as num).toDouble(),
          (j['t'] as num).toDouble(),
          (j['r'] as num).toDouble(),
          (j['b'] as num).toDouble(),
        ),
        points: (j['pts'] as List?)
            ?.map((e) => Offset(
                  ((e as List)[0] as num).toDouble(),
                  (e[1] as num).toDouble(),
                ))
            .toList(),
      );
}

/// The shape of one interior edge shared by two polygon cells, so the cut
/// between them can be curved, waved or zigzagged instead of straight.
///
/// The edge is identified by the two cells it separates ([a] < [b], slot
/// ids), so it keeps its shape when the edge is dragged. Its geometry lives in
/// edge-local coordinates of the *canonical* direction P→Q (P is the endpoint
/// with the smaller x, then smaller y): `u` runs along the edge (0 at P, 1 at
/// Q) and `v` is the offset along the edge's left normal, as a fraction of the
/// edge length. Both cells derive the same curve from it, so they always meet.
class EdgeShape {
  const EdgeShape({
    required this.a,
    required this.b,
    this.c1 = const Offset(1 / 3, 0),
    this.c2 = const Offset(2 / 3, 0),
    this.zigAmp = 0,
    this.zigCount = 0,
  });

  final String a;
  final String b;

  /// Cubic Bézier control points (u, v), edge-local.
  final Offset c1;
  final Offset c2;

  /// Zigzag teeth laid along the (possibly curved) edge: height as a fraction
  /// of the edge length (0 = none) and number of teeth.
  final double zigAmp;
  final int zigCount;

  /// Sorted "a|b" key of the two cells.
  String get key => keyFor(a, b);

  static String keyFor(String x, String y) =>
      x.compareTo(y) <= 0 ? '$x|$y' : '$y|$x';

  bool get isCurved => c1.dy.abs() > 1e-4 || c2.dy.abs() > 1e-4;
  bool get hasZigzag => zigAmp > 1e-4 && zigCount > 0;
  bool get isStraight => !isCurved && !hasZigzag;

  EdgeShape copyWith({Offset? c1, Offset? c2, double? zigAmp, int? zigCount}) => EdgeShape(
        a: a,
        b: b,
        c1: c1 ?? this.c1,
        c2: c2 ?? this.c2,
        zigAmp: zigAmp ?? this.zigAmp,
        zigCount: zigCount ?? this.zigCount,
      );

  Map<String, dynamic> toJson() => {
        'a': a,
        'b': b,
        'c1': [c1.dx, c1.dy],
        'c2': [c2.dx, c2.dy],
        if (hasZigzag) 'za': zigAmp,
        if (hasZigzag) 'zn': zigCount,
      };

  factory EdgeShape.fromJson(Map<String, dynamic> j) {
    Offset o(Object? v, Offset fallback) {
      if (v is! List || v.length < 2) return fallback;
      return Offset((v[0] as num).toDouble(), (v[1] as num).toDouble());
    }

    return EdgeShape(
      a: j['a'] as String,
      b: j['b'] as String,
      c1: o(j['c1'], const Offset(1 / 3, 0)),
      c2: o(j['c2'], const Offset(2 / 3, 0)),
      zigAmp: (j['za'] as num?)?.toDouble() ?? 0,
      zigCount: (j['zn'] as num?)?.toInt() ?? 0,
    );
  }
}

enum LayoutFamily { rows, columns, grid, featured, freeform, diagonal }

/// A curated collage layout: a named set of slots for a given photo count.
class LayoutTemplate {
  const LayoutTemplate({
    required this.id,
    required this.name,
    required this.family,
    required this.slots,
    this.custom = false,
    this.edges = const [],
  });

  final String id;
  final String name;
  final LayoutFamily family;
  final List<LayoutSlot> slots;
  final bool custom;

  /// Curved / zigzag shapes of interior polygon edges (straight when absent).
  final List<EdgeShape> edges;

  /// [edges] keyed by [EdgeShape.key].
  Map<String, EdgeShape> get edgeMap => {for (final e in edges) e.key: e};

  int get slotCount => slots.length;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'family': family.name,
        'custom': custom,
        'slots': slots.map((s) => s.toJson()).toList(),
        if (edges.any((e) => !e.isStraight))
          'edges': [for (final e in edges) if (!e.isStraight) e.toJson()],
      };

  factory LayoutTemplate.fromJson(Map<String, dynamic> j) => LayoutTemplate(
        id: j['id'] as String,
        name: j['name'] as String,
        family: LayoutFamily.values.byName(j['family'] as String),
        custom: j['custom'] as bool? ?? false,
        slots: (j['slots'] as List)
            .map((e) => LayoutSlot.fromJson(e as Map<String, dynamic>))
            .toList(),
        edges: [
          for (final e in (j['edges'] as List?) ?? const [])
            EdgeShape.fromJson(e as Map<String, dynamic>),
        ],
      );
}
