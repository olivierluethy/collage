import 'package:flutter/material.dart';

import '../theme/text_styles.dart';
import '../theme/tokens.dart';

/// Monospace "spec chip" — the signature element for aspect ratios, pixel
/// dimensions and counters (e.g. 4:5, 2048×2048, 3/9).
class SpecChip extends StatelessWidget {
  const SpecChip(this.text, {super.key, this.active = false, this.icon});
  final String text;
  final bool active;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final color = active ? AppColors.amber : AppColors.textMid;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: Space.sm, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.surfaceHigh,
        borderRadius: BorderRadius.circular(Radii.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 13, color: color),
            const SizedBox(width: 4),
          ],
          Text(text, style: AppText.spec.copyWith(color: color)),
        ],
      ),
    );
  }
}

/// Primary amber action button with an always-visible label.
class PrimaryButton extends StatelessWidget {
  const PrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.expand = true,
    this.busy = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool expand;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final child = busy
        ? const SizedBox(
            height: 22,
            width: 22,
            child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.onAmber),
          )
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[Icon(icon, size: 20), const SizedBox(width: Space.sm)],
              Text(label),
            ],
          );
    final btn = ElevatedButton(
      onPressed: busy ? null : onPressed,
      child: child,
    );
    return expand ? SizedBox(width: double.infinity, child: btn) : btn;
  }
}

/// Section eyebrow used above groups of controls.
class SectionHeader extends StatelessWidget {
  const SectionHeader(this.title, {super.key, this.trailing});
  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.lg, Space.lg, Space.lg, Space.sm),
      child: Row(
        children: [
          Expanded(child: Text(title.toUpperCase(), style: AppText.overline)),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

/// Standard bottom-sheet scaffold with grab handle and title.
class SheetScaffold extends StatelessWidget {
  const SheetScaffold({super.key, required this.title, required this.child, this.height});
  final String title;
  final Widget child;
  final double? height;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: height ?? MediaQuery.of(context).size.height * 0.6,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: Space.md),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.line,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(Space.xl, Space.md, Space.xl, Space.sm),
              child: Row(
                children: [
                  Text(title, style: AppText.titleMd),
                  const Spacer(),
                  IconButton(
                    onPressed: () => Navigator.of(context).maybePop(),
                    icon: const Icon(Icons.close),
                    color: AppColors.textMid,
                  ),
                ],
              ),
            ),
            Flexible(child: child),
          ],
        ),
      ),
    );
  }
}

/// Friendly empty-state block — an invitation to act.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.action,
  });
  final IconData icon;
  final String title;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(Space.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 56, color: AppColors.textLo),
            const SizedBox(height: Space.lg),
            Text(title, style: AppText.displayMd, textAlign: TextAlign.center),
            const SizedBox(height: Space.sm),
            Text(message, style: AppText.bodyMd, textAlign: TextAlign.center),
            if (action != null) ...[const SizedBox(height: Space.xl), action!],
          ],
        ),
      ),
    );
  }
}

/// A labelled slider row for the border/spacing controls.
class LabeledSlider extends StatelessWidget {
  const LabeledSlider({
    super.key,
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    this.suffix = '',
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;
  final String suffix;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Space.lg),
      child: Row(
        children: [
          SizedBox(width: 84, child: Text(label, style: AppText.bodyMd)),
          Expanded(
            child: Slider(
              value: value.clamp(min, max),
              min: min,
              max: max,
              onChanged: onChanged,
            ),
          ),
          SizedBox(
            width: 44,
            child: Text('${value.round()}$suffix',
                style: AppText.spec, textAlign: TextAlign.right),
          ),
        ],
      ),
    );
  }
}

/// A row of colour swatches with a selected ring.
class SwatchRow extends StatelessWidget {
  const SwatchRow({
    super.key,
    required this.colors,
    required this.selected,
    required this.onPick,
  });
  final List<Color> colors;
  final Color selected;
  final ValueChanged<Color> onPick;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: Space.lg),
        itemCount: colors.length,
        separatorBuilder: (_, __) => const SizedBox(width: Space.sm),
        itemBuilder: (_, i) {
          final c = colors[i];
          final isSel = c.toARGB32() == selected.toARGB32();
          return GestureDetector(
            onTap: () => onPick(c),
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: c,
                shape: BoxShape.circle,
                border: Border.all(
                  color: isSel ? AppColors.amber : AppColors.line,
                  width: isSel ? 2.5 : 1,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
