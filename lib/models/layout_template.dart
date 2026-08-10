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

enum LayoutFamily { rows, columns, grid, featured, freeform, diagonal }

/// A curated collage layout: a named set of slots for a given photo count.
class LayoutTemplate {
  const LayoutTemplate({
    required this.id,
    required this.name,
    required this.family,
    required this.slots,
    this.custom = false,
  });

  final String id;
  final String name;
  final LayoutFamily family;
  final List<LayoutSlot> slots;
  final bool custom;

  int get slotCount => slots.length;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'family': family.name,
        'custom': custom,
        'slots': slots.map((s) => s.toJson()).toList(),
      };

  factory LayoutTemplate.fromJson(Map<String, dynamic> j) => LayoutTemplate(
        id: j['id'] as String,
        name: j['name'] as String,
        family: LayoutFamily.values.byName(j['family'] as String),
        custom: j['custom'] as bool? ?? false,
        slots: (j['slots'] as List)
            .map((e) => LayoutSlot.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}
