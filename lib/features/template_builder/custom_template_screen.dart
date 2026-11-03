import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../models/collage_project.dart';
import '../../models/layout_template.dart';
import '../../models/partition_geometry.dart';
import '../../widgets/curved_edges.dart';
import '../../theme/palette.dart';
import '../../theme/tokens.dart';
import '../../theme/typography.dart';
import '../../widgets/layout_miniature.dart';
import '../../widgets/ui.dart';

/// How the cuts of a hand-made layout start out. Every style produces real,
/// editable cut points or curves, so the result can be fine-tuned on the
/// canvas (Layout › Edges) afterwards.
enum CutStyle { straight, slanted, zigzag, wave }

/// A "make your own layout" builder: choose columns and rows, optionally
/// feature the first cell, and pick how the cuts run — with a live preview
/// in the collage's own canvas shape.
class CustomTemplateScreen extends StatefulWidget {
  const CustomTemplateScreen({super.key, required this.count, this.ratio = CanvasRatio.square});
  final int count;

  /// The collage's canvas shape, so the preview shows the real proportions.
  final CanvasRatio ratio;

  @override
  State<CustomTemplateScreen> createState() => _CustomTemplateScreenState();
}

class _CustomTemplateScreenState extends State<CustomTemplateScreen> {
  int _cols = 2;
  int _rows = 2;
  bool _feature = false;
  CutStyle _style = CutStyle.straight;
  CanvasRatio get _ratio => widget.ratio;

  LayoutTemplate _build() {
    final slots = <LayoutSlot>[];
    LayoutSlot s(String id, double l, double t, double r, double b) =>
        LayoutSlot(id: id, rect: Rect.fromLTRB(l, t, r, b));

    if (_feature) {
      // Big cell on the left spanning full height, the rest as a grid on the right.
      slots.add(s('s0', 0, 0, 0.55, 1));
      final rc = _rows;
      var i = 1;
      for (var r = 0; r < rc; r++) {
        slots.add(s('s$i', 0.55, r / rc, 1, (r + 1) / rc));
        i++;
      }
    } else {
      var i = 0;
      for (var r = 0; r < _rows; r++) {
        for (var c = 0; c < _cols; c++) {
          slots.add(s('s$i', c / _cols, r / _rows, (c + 1) / _cols, (r + 1) / _rows));
          i++;
        }
      }
    }
    return applyCutStyle(
      LayoutTemplate(
        id: 'custom-${DateTime.now().millisecondsSinceEpoch}',
        name: 'Custom',
        family: LayoutFamily.grid,
        custom: true,
        slots: slots,
      ),
      _style,
    );
  }

  @override
  Widget build(BuildContext context) {
    final template = _build();
    return Scaffold(
      appBar: AppBar(
        leading: const BackButton(),
        title: Text(context.l10n.t('makeYourOwn')),
      ),
      body: Column(
        children: [
          Expanded(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(Space.xl),
                child: AspectRatio(
                  aspectRatio: _ratio.value,
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: context.colors.surface,
                      borderRadius: BorderRadius.circular(Radii.card),
                      border: Border.all(color: context.colors.line),
                    ),
                    child: LayoutMiniature(template: template, gap: 6),
                  ),
                ),
              ),
            ),
          ),
          SpecChip(
              context.l10n.a('slotsCount',
                  {'count': '${template.slotCount}', 'ratio': _ratio.label}),
              active: true),
          const SizedBox(height: Space.md),
          SwitchListTile(
            value: _feature,
            onChanged: (v) => setState(() => _feature = v),
            title: Text(context.l10n.t('featureFirst'), style: context.text.bodyLg),
            subtitle: Text(context.l10n.t('oneBigLeft'), style: context.text.caption),
            activeThumbColor: context.colors.onAmber,
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Space.xl, vertical: Space.xs),
            child: Row(
              children: [
                Expanded(child: Text(context.l10n.t('cutStyle'), style: context.text.bodyLg)),
                SegmentedButton<CutStyle>(
                  segments: [
                    ButtonSegment(value: CutStyle.straight, icon: const Icon(Icons.crop_square_rounded, size: 18), tooltip: context.l10n.t('cutStyleStraight')),
                    ButtonSegment(value: CutStyle.slanted, icon: const Icon(Icons.signal_cellular_null_rounded, size: 18), tooltip: context.l10n.t('cutStyleSlanted')),
                    ButtonSegment(value: CutStyle.zigzag, icon: const Icon(Icons.show_chart_rounded, size: 18), tooltip: context.l10n.t('cutStyleZigzag')),
                    ButtonSegment(value: CutStyle.wave, icon: const Icon(Icons.waves_rounded, size: 18), tooltip: context.l10n.t('cutStyleWave')),
                  ],
                  selected: {_style},
                  onSelectionChanged: (v) => setState(() => _style = v.first),
                  showSelectedIcon: false,
                  style: const ButtonStyle(visualDensity: VisualDensity.compact),
                ),
              ],
            ),
          ),
          if (_style != CutStyle.straight)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Space.xl),
              child: Text(context.l10n.t('cutStyleHint'), style: context.text.caption.copyWith(color: context.colors.textLo)),
            ),
          if (!_feature)
            _Stepper(
              label: context.l10n.t('columns'),
              value: _cols,
              min: 1,
              max: 4,
              onChanged: (v) => setState(() => _cols = v),
            ),
          _Stepper(
            label: _feature ? context.l10n.t('photosOnRight') : context.l10n.t('rows'),
            value: _rows,
            min: 1,
            max: 5,
            onChanged: (v) => setState(() => _rows = v),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(Space.lg),
              child: PrimaryButton(
                label: context.l10n.t('useThisTemplate'),
                icon: Icons.check_rounded,
                onPressed: () => Navigator.of(context).pop(_build()),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Stepper extends StatelessWidget {
  const _Stepper({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
  });
  final String label;
  final int value;
  final int min;
  final int max;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Space.xl, vertical: 4),
      child: Row(
        children: [
          Expanded(child: Text(label, style: context.text.bodyLg)),
          IconButton.filledTonal(
            onPressed: value > min ? () => onChanged(value - 1) : null,
            icon: const Icon(Icons.remove),
          ),
          SizedBox(
            width: 40,
            child: Text('$value', style: context.text.titleMd, textAlign: TextAlign.center),
          ),
          IconButton.filledTonal(
            onPressed: value < max ? () => onChanged(value + 1) : null,
            icon: const Icon(Icons.add),
          ),
        ],
      ),
    );
  }
}

/// [t] with its cuts restyled. Straight returns it unchanged; the others
/// turn the grid into polygons and reshape every cut with the same
/// operations the canvas editor uses, so nothing here is a special case.
LayoutTemplate applyCutStyle(LayoutTemplate t, CutStyle style) {
  if (style == CutStyle.straight || t.slots.length < 2) return t;
  var cells = polygonizeSlots(t.slots);
  var edges = const <EdgeShape>[];
  switch (style) {
    case CutStyle.straight:
      break;
    case CutStyle.slanted:
      // Lean every cut that meets the border: points on the top/left border
      // slide one way, those on the bottom/right the other.
      const slant = 0.07;
      for (final v in PartitionGeometry.vertices(cells)) {
        if (!v.onBorder || v.isCorner) continue;
        final p = v.at;
        final target = p.dy < 0.01
            ? p + const Offset(slant, 0)
            : p.dy > 0.99
                ? p - const Offset(slant, 0)
                : p.dx < 0.01
                    ? p - const Offset(0, slant)
                    : p + const Offset(0, slant);
        final r = PartitionGeometry.moveVertex(cells, p, target);
        if (r != null) cells = r.cells;
      }
    case CutStyle.zigzag:
      for (final e in findSharedEdges(cells)) {
        final next = PartitionGeometry.zigzag(cells, a: e.a, b: e.b, p: e.p, q: e.q, teeth: 3, amplitude: 0.07);
        if (next != null) cells = next;
      }
    case CutStyle.wave:
      edges = [
        for (final e in findSharedEdges(cells))
          EdgeShape(a: e.a, b: e.b, c1: const Offset(1 / 3, 0.18), c2: const Offset(2 / 3, -0.18)),
      ];
  }
  // A cut split into pieces may share one key; keep one shape per key.
  final byKey = <String, EdgeShape>{for (final e in edges) e.key: e};
  return LayoutTemplate(
    id: t.id,
    name: t.name,
    family: LayoutFamily.diagonal,
    custom: true,
    slots: cells,
    edges: byKey.values.toList(),
  );
}
