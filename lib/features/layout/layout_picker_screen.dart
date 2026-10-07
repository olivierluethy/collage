import 'package:flutter/material.dart';

import '../../data/layout_templates.dart';
import '../../l10n/app_localizations.dart';
import '../../models/collage_project.dart';
import '../../models/layout_template.dart';
import '../../theme/palette.dart';
import '../../theme/tokens.dart';
import '../../theme/typography.dart';
import '../../widgets/layout_miniature.dart';
import '../../widgets/ui.dart';
import '../flow.dart';
import '../template_builder/custom_template_screen.dart';

/// Choose a canvas aspect ratio (with the numbers shown) and a layout,
/// illustrated with little previews.
class LayoutPickerScreen extends StatefulWidget {
  const LayoutPickerScreen({super.key, required this.count});
  final int count;

  @override
  State<LayoutPickerScreen> createState() => _LayoutPickerScreenState();
}

class _LayoutPickerScreenState extends State<LayoutPickerScreen> {
  CanvasRatio _ratio = CanvasRatio.portrait;
  late List<LayoutTemplate> _templates;
  LayoutTemplate? _selected;
  LayoutTemplate? _custom;

  @override
  void initState() {
    super.initState();
    _templates = LayoutTemplates.forCount(widget.count);
    _selected = _templates.first;
  }

  Future<void> _makeCustom() async {
    final t = await Navigator.of(context).push<LayoutTemplate>(
      MaterialPageRoute(builder: (_) => CustomTemplateScreen(count: widget.count)),
    );
    if (t != null && mounted) {
      setState(() {
        _custom = t;
        _selected = t;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final options = [
      ..._templates,
      if (_custom != null) _custom!,
      LayoutTemplates.freeform,
    ];

    return Scaffold(
      appBar: AppBar(
        leading: const BackButton(),
        title: Text(context.l10n.t('pickLayout')),
      ),
      body: Column(
        children: [
          SectionHeader(context.l10n.t('canvasShape')),
          SizedBox(
            height: 44,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: Space.lg),
              itemCount: CanvasRatio.all.length,
              separatorBuilder: (_, __) => const SizedBox(width: Space.sm),
              itemBuilder: (_, i) {
                final r = CanvasRatio.all[i];
                final sel = r.label == _ratio.label;
                return GestureDetector(
                  onTap: () => setState(() => _ratio = r),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: Space.md),
                    decoration: BoxDecoration(
                      color: sel ? context.colors.amberTint : context.colors.surfaceInput,
                      borderRadius: BorderRadius.circular(Radii.chip),
                    ),
                    child: Row(
                      children: [
                        Text(r.name,
                            style: context.text.labelMd.copyWith(
                                color: sel ? context.colors.amber : context.colors.textMid)),
                        const SizedBox(width: 6),
                        Text(r.label,
                            style: context.text.spec.copyWith(
                                color: sel ? context.colors.amber : context.colors.textLo)),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          SectionHeader(context.l10n.t('layoutSection')),
          Expanded(
            child: GridView.builder(
              padding: const EdgeInsets.symmetric(horizontal: Space.lg),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                mainAxisSpacing: Space.md,
                crossAxisSpacing: Space.md,
                childAspectRatio: 0.72,
              ),
              itemCount: options.length + 1,
              itemBuilder: (_, i) {
                if (i == options.length) {
                  return _CustomTile(onTap: _makeCustom);
                }
                final t = options[i];
                final sel = _selected?.id == t.id;
                return _LayoutTile(
                  template: t,
                  ratio: _ratio,
                  selected: sel,
                  onTap: () => setState(() => _selected = t),
                );
              },
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(Space.lg),
              child: PrimaryButton(
                label: context.l10n.t('useThisLayout'),
                icon: Icons.check_rounded,
                onPressed: _selected == null
                    ? null
                    : () => Navigator.of(context)
                        .pop(LayoutChoice(_selected!, _ratio.label)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LayoutTile extends StatelessWidget {
  const _LayoutTile({
    required this.template,
    required this.ratio,
    required this.selected,
    required this.onTap,
  });
  final LayoutTemplate template;
  final CanvasRatio ratio;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: context.colors.surface,
                borderRadius: BorderRadius.circular(Radii.card),
                border: Border.all(
                  color: selected ? context.colors.amber : context.colors.line,
                  width: selected ? 2 : 1,
                ),
              ),
              child: Center(
                child: AspectRatio(
                  aspectRatio: ratio.value,
                  child: LayoutMiniature(template: template),
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(_layoutName(context, template),
              style: context.text.caption.copyWith(
                  color: selected ? context.colors.amber : context.colors.textMid),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center),
        ],
      ),
    );
  }
}

class _CustomTile extends StatelessWidget {
  const _CustomTile({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: context.colors.surface,
                borderRadius: BorderRadius.circular(Radii.card),
                border: Border.all(color: context.colors.line),
              ),
              child: Center(
                child: Icon(Icons.add_rounded, color: context.colors.amber, size: 28),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(context.l10n.t('custom'),
              style: context.text.caption, textAlign: TextAlign.center),
        ],
      ),
    );
  }
}

/// The visible name for a layout template: its l10n string when we have a key
/// for the id, else the template's own English name.
String _layoutName(BuildContext context, LayoutTemplate t) {
  final key = _layoutKey(t.id) ?? (t.custom ? 'custom' : null);
  return key == null ? t.name : context.l10n.t(key);
}

/// Maps a curated layout id to its l10n key (see `locales/en.dart`).
String? _layoutKey(String id) => switch (id) {
      'one' => 'layoutSingle',
      'freeform' => 'layoutFreeform',
      '2-rows' => 'layoutStacked',
      '2-cols' => 'layoutSideBySide',
      '2-split-v' => 'layoutBigLeft',
      '2-split-h' => 'layoutBigTop',
      '2-angled' => 'layoutAngled',
      '2-corner' => 'layoutDiagonal',
      '3-cols' => 'layoutThreeColumns',
      '3-rows' => 'layoutThreeRows',
      '3-feat-left' => 'layoutBigLeftTwoRight',
      '3-feat-top' => 'layoutBigTopTwoBelow',
      '3-slanted' => 'layoutSlantedTrio',
      '4-grid' => 'layoutGrid2x2',
      '4-cols' => 'layoutFourColumns',
      '4-rows' => 'layoutFourRows',
      '4-feat' => 'layoutBigLeftThreeRight',
      '4-x' => 'layoutPinwheel',
      '4-slanted' => 'layoutSlantedFour',
      '5-feat-left' => 'layoutBigLeftFourRight',
      '5-top1-bottom4' => 'layoutOneUpFourDown',
      '5-left1-right4' => 'layoutOneLeftFourRight',
      '6-grid-3x2' => 'layoutGrid3x2',
      '6-grid-2x3' => 'layoutGrid2x3',
      '6-feat' => 'layoutBigTopFiveBelow',
      '7-feat' => 'layoutBigLeftSixRight',
      '7-top3-bottom4' => 'layoutThreeUpFourDown',
      '8-grid-4x2' => 'layoutGrid4x2',
      '8-grid-2x4' => 'layoutGrid2x4',
      '9-grid' => 'layoutGrid3x3',
      _ => null,
    };
