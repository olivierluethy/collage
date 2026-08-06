import 'package:flutter/material.dart';

import '../../data/layout_templates.dart';
import '../../models/collage_project.dart';
import '../../models/layout_template.dart';
import '../../theme/text_styles.dart';
import '../../theme/tokens.dart';
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
        title: const Text('Pick a layout'),
      ),
      body: Column(
        children: [
          const SectionHeader('Canvas shape'),
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
                      color: sel ? AppColors.amberTint : AppColors.surfaceInput,
                      borderRadius: BorderRadius.circular(Radii.chip),
                    ),
                    child: Row(
                      children: [
                        Text(r.name,
                            style: AppText.labelMd.copyWith(
                                color: sel ? AppColors.amber : AppColors.textMid)),
                        const SizedBox(width: 6),
                        Text(r.label,
                            style: AppText.spec.copyWith(
                                color: sel ? AppColors.amber : AppColors.textLo)),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          const SectionHeader('Layout'),
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
                label: 'Use this layout',
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
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(Radii.card),
                border: Border.all(
                  color: selected ? AppColors.amber : AppColors.line,
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
          Text(template.name,
              style: AppText.caption.copyWith(
                  color: selected ? AppColors.amber : AppColors.textMid),
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
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(Radii.card),
                border: Border.all(color: AppColors.line),
              ),
              child: const Center(
                child: Icon(Icons.add_rounded, color: AppColors.amber, size: 28),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text('Custom',
              style: AppText.caption, textAlign: TextAlign.center),
        ],
      ),
    );
  }
}
