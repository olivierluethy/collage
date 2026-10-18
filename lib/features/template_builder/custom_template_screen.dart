import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../models/collage_project.dart';
import '../../models/layout_template.dart';
import '../../theme/palette.dart';
import '../../theme/tokens.dart';
import '../../theme/typography.dart';
import '../../widgets/layout_miniature.dart';
import '../../widgets/ui.dart';

/// A simple "make your own layout" builder: choose columns and rows, and
/// optionally feature the first cell, with a live preview.
class CustomTemplateScreen extends StatefulWidget {
  const CustomTemplateScreen({super.key, required this.count});
  final int count;

  @override
  State<CustomTemplateScreen> createState() => _CustomTemplateScreenState();
}

class _CustomTemplateScreenState extends State<CustomTemplateScreen> {
  int _cols = 2;
  int _rows = 2;
  bool _feature = false;
  final CanvasRatio _ratio = CanvasRatio.square;

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
    return LayoutTemplate(
      id: 'custom-${DateTime.now().millisecondsSinceEpoch}',
      name: 'Custom',
      family: LayoutFamily.grid,
      custom: true,
      slots: slots,
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
