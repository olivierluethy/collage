import 'dart:ui';

import '../models/layout_template.dart';

/// Curated collage layouts, grouped by photo count (2–9) plus a freeform one.
///
/// Every slot rect is normalised (0..1) inside the collage content area, so a
/// layout looks right on any canvas aspect ratio. The picker shows these as
/// little illustrations so the user sees exactly what each does.
class LayoutTemplates {
  LayoutTemplates._();

  static LayoutSlot _s(String id, double l, double t, double r, double b) =>
      LayoutSlot(id: id, rect: Rect.fromLTRB(l, t, r, b));

  /// A simple cols×rows grid, row-major.
  static List<LayoutSlot> _grid(int cols, int rows) {
    final slots = <LayoutSlot>[];
    var i = 0;
    for (var r = 0; r < rows; r++) {
      for (var c = 0; c < cols; c++) {
        slots.add(_s('s$i', c / cols, r / rows, (c + 1) / cols, (r + 1) / rows));
        i++;
      }
    }
    return slots;
  }

  static LayoutTemplate _t(
    String id,
    String name,
    LayoutFamily fam,
    List<LayoutSlot> slots,
  ) =>
      LayoutTemplate(id: id, name: name, family: fam, slots: slots);

  /// The freeform "no grid" layout — a blank canvas you drop photos onto.
  static final LayoutTemplate freeform =
      _t('freeform', 'Freeform', LayoutFamily.freeform, const []);

  /// All curated layouts for a given photo count (2..9). Falls back to a
  /// best-fit grid for counts outside the curated range.
  static List<LayoutTemplate> forCount(int n) {
    switch (n) {
      case 1:
        return [_t('one', 'Single', LayoutFamily.grid, _grid(1, 1))];
      case 2:
        return [
          _t('2-rows', 'Stacked', LayoutFamily.rows, _grid(1, 2)),
          _t('2-cols', 'Side by side', LayoutFamily.columns, _grid(2, 1)),
          _t('2-split-v', 'Big left', LayoutFamily.featured, [
            _s('s0', 0, 0, 0.62, 1),
            _s('s1', 0.62, 0, 1, 1),
          ]),
          _t('2-split-h', 'Big top', LayoutFamily.featured, [
            _s('s0', 0, 0, 1, 0.62),
            _s('s1', 0, 0.62, 1, 1),
          ]),
        ];
      case 3:
        return [
          _t('3-cols', 'Three columns', LayoutFamily.columns, _grid(3, 1)),
          _t('3-rows', 'Three rows', LayoutFamily.rows, _grid(1, 3)),
          _t('3-feat-left', 'Big left, two right', LayoutFamily.featured, [
            _s('s0', 0, 0, 0.6, 1),
            _s('s1', 0.6, 0, 1, 0.5),
            _s('s2', 0.6, 0.5, 1, 1),
          ]),
          _t('3-feat-top', 'Big top, two below', LayoutFamily.featured, [
            _s('s0', 0, 0, 1, 0.6),
            _s('s1', 0, 0.6, 0.5, 1),
            _s('s2', 0.5, 0.6, 1, 1),
          ]),
        ];
      case 4:
        return [
          _t('4-grid', 'Grid 2×2', LayoutFamily.grid, _grid(2, 2)),
          _t('4-cols', 'Four columns', LayoutFamily.columns, _grid(4, 1)),
          _t('4-rows', 'Four rows', LayoutFamily.rows, _grid(1, 4)),
          _t('4-feat', 'Big left, three right', LayoutFamily.featured, [
            _s('s0', 0, 0, 0.58, 1),
            _s('s1', 0.58, 0, 1, 1 / 3),
            _s('s2', 0.58, 1 / 3, 1, 2 / 3),
            _s('s3', 0.58, 2 / 3, 1, 1),
          ]),
        ];
      case 5:
        return [
          _t('5-feat-left', 'Big left, four right', LayoutFamily.featured, [
            _s('s0', 0, 0, 0.56, 1),
            ..._remap(_offsetGridInBox(_grid(2, 2), 0.56, 0, 1, 1), 1),
          ]),
          _t('5-top1-bottom4', 'One up, four down', LayoutFamily.featured, [
            _s('s0', 0, 0, 1, 0.5),
            _s('s1', 0, 0.5, 0.25, 1),
            _s('s2', 0.25, 0.5, 0.5, 1),
            _s('s3', 0.5, 0.5, 0.75, 1),
            _s('s4', 0.75, 0.5, 1, 1),
          ]),
          _t('5-left1-right4', 'One left, four right', LayoutFamily.featured, [
            _s('s0', 0, 0, 0.5, 1),
            _s('s1', 0.5, 0, 1, 0.25),
            _s('s2', 0.5, 0.25, 1, 0.5),
            _s('s3', 0.5, 0.5, 1, 0.75),
            _s('s4', 0.5, 0.75, 1, 1),
          ]),
        ];
      case 6:
        return [
          _t('6-grid-3x2', 'Grid 3×2', LayoutFamily.grid, _grid(3, 2)),
          _t('6-grid-2x3', 'Grid 2×3', LayoutFamily.grid, _grid(2, 3)),
          _t('6-feat', 'Big top, five below', LayoutFamily.featured, [
            _s('s0', 0, 0, 1, 0.5),
            ..._remap(_offsetGridInBox(_grid(5, 1), 0, 0.5, 1, 1), 1),
          ]),
        ];
      case 7:
        return [
          _t('7-feat', 'Big left, six right', LayoutFamily.featured, [
            _s('s0', 0, 0, 0.5, 1),
            ..._remap(_offsetGridInBox(_grid(2, 3), 0.5, 0, 1, 1), 1),
          ]),
          _t('7-top3-bottom4', 'Three up, four down', LayoutFamily.featured, [
            ..._remap(_offsetGridInBox(_grid(3, 1), 0, 0, 1, 0.5), 0),
            ..._remap(_offsetGridInBox(_grid(4, 1), 0, 0.5, 1, 1), 3),
          ]),
        ];
      case 8:
        return [
          _t('8-grid-4x2', 'Grid 4×2', LayoutFamily.grid, _grid(4, 2)),
          _t('8-grid-2x4', 'Grid 2×4', LayoutFamily.grid, _grid(2, 4)),
        ];
      case 9:
        return [
          _t('9-grid', 'Grid 3×3', LayoutFamily.grid, _grid(3, 3)),
        ];
      default:
        // Best-fit square-ish grid for anything else.
        final cols = (n <= 3) ? n : (n / 2).ceil();
        final rows = (n / cols).ceil();
        return [_t('$n-grid', 'Grid $cols×$rows', LayoutFamily.grid, _grid(cols, rows))];
    }
  }

  static List<LayoutSlot> _offsetGridInBox(
      List<LayoutSlot> slots, double l, double t, double r, double b) {
    final w = r - l, h = b - t;
    return slots
        .map((s) => LayoutSlot(
              id: s.id,
              rect: Rect.fromLTRB(
                l + s.rect.left * w,
                t + s.rect.top * h,
                l + s.rect.right * w,
                t + s.rect.bottom * h,
              ),
            ))
        .toList();
  }

  /// Re-index slot ids starting from [start] so featured layouts stay unique.
  static List<LayoutSlot> _remap(List<LayoutSlot> slots, int start) {
    var i = start;
    return slots
        .map((s) => LayoutSlot(id: 's${i++}', rect: s.rect))
        .toList();
  }
}
