import 'dart:ui';

/// One rectangular hole in a grid layout, expressed as a normalised rect
/// (0..1) inside the collage content area. Slots keep the same relative shape
/// on any canvas size or aspect ratio.
class LayoutSlot {
  const LayoutSlot({required this.id, required this.rect});

  final String id;
  final Rect rect; // left, top, right, bottom in 0..1

  Map<String, dynamic> toJson() => {
        'id': id,
        'l': rect.left,
        't': rect.top,
        'r': rect.right,
        'b': rect.bottom,
      };

  factory LayoutSlot.fromJson(Map<String, dynamic> j) => LayoutSlot(
        id: j['id'] as String,
        rect: Rect.fromLTRB(
          (j['l'] as num).toDouble(),
          (j['t'] as num).toDouble(),
          (j['r'] as num).toDouble(),
          (j['b'] as num).toDouble(),
        ),
      );
}

enum LayoutFamily { rows, columns, grid, featured, freeform }

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
