import 'package:flutter/material.dart';

import '../theme/palette.dart';
import '../theme/tokens.dart';
import '../theme/typography.dart';

/// Monospace "spec chip" — the signature element for aspect ratios, pixel
/// dimensions and counters (e.g. 4:5, 2048×2048, 3/9).
class SpecChip extends StatelessWidget {
  const SpecChip(this.text, {super.key, this.active = false, this.icon});
  final String text;
  final bool active;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final color = active ? context.colors.amber : context.colors.textMid;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: Space.sm, vertical: 4),
      decoration: BoxDecoration(
        color: context.colors.surfaceHigh,
        borderRadius: BorderRadius.circular(Radii.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 13, color: color),
            const SizedBox(width: 4),
          ],
          Text(text, style: context.text.spec.copyWith(color: color)),
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
        ? SizedBox(
            height: 22,
            width: 22,
            child: CircularProgressIndicator(strokeWidth: 2, color: context.colors.onAmber),
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
          Expanded(child: Text(title.toUpperCase(), style: context.text.overline)),
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
                color: context.colors.line,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(Space.xl, Space.md, Space.xl, Space.sm),
              child: Row(
                children: [
                  Text(title, style: context.text.titleMd),
                  const Spacer(),
                  IconButton(
                    onPressed: () => Navigator.of(context).maybePop(),
                    icon: const Icon(Icons.close),
                    color: context.colors.textMid,
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
    this.secondary,
    this.art,
  });
  final IconData icon;
  final String title;
  final String message;
  final Widget? action;

  /// Optional second, quieter way forward (e.g. "Browse templates").
  final Widget? secondary;

  /// Optional illustration shown instead of [icon].
  final Widget? art;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(Space.xl),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              art ??
                  Container(
                    width: 88,
                    height: 88,
                    decoration: BoxDecoration(
                      color: context.colors.surfaceHigh,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(icon, size: 40, color: context.colors.textMid),
                  ),
              const SizedBox(height: Space.xl),
              Text(title, style: context.text.displayMd, textAlign: TextAlign.center),
              const SizedBox(height: Space.sm),
              Text(message,
                  style: context.text.bodyLg.copyWith(color: context.colors.textMid),
                  textAlign: TextAlign.center),
              if (action != null) ...[const SizedBox(height: Space.xl), action!],
              if (secondary != null) ...[const SizedBox(height: Space.sm), secondary!],
            ],
          ),
        ),
      ),
    );
  }
}

/// What a snackbar reports; picks its leading status icon.
enum SnackKind { info, success, error }

/// The house snackbar: a leading status icon, one line of plain text and at
/// most one amber action (e.g. "Undo"). Replaces any snackbar already showing.
void showAppSnack(
  BuildContext context,
  String message, {
  SnackKind kind = SnackKind.info,
  String? actionLabel,
  VoidCallback? onAction,
  Duration? duration,
}) =>
    showAppSnackOn(
      ScaffoldMessenger.of(context),
      message,
      kind: kind,
      actionLabel: actionLabel,
      onAction: onAction,
      duration: duration,
    );

/// [showAppSnack] on a messenger captured before an `await`, for when the
/// widget that started the work may be gone by the time it finishes.
void showAppSnackOn(
  ScaffoldMessengerState messenger,
  String message, {
  SnackKind kind = SnackKind.info,
  String? actionLabel,
  VoidCallback? onAction,
  Duration? duration,
}) {
  final c = messenger.context.colors;
  final (icon, color) = switch (kind) {
    SnackKind.success => (Icons.check_circle_rounded, c.success),
    SnackKind.error => (Icons.error_outline_rounded, c.danger),
    SnackKind.info => (Icons.info_outline_rounded, c.info),
  };
  messenger
    ..clearSnackBars()
    ..showSnackBar(SnackBar(
      duration: duration ?? (actionLabel != null ? const Duration(seconds: 6) : const Duration(seconds: 4)),
      content: Row(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: Space.md),
          Expanded(child: Text(message)),
        ],
      ),
      action: actionLabel == null
          ? null
          : SnackBarAction(label: actionLabel, onPressed: onAction ?? () {}),
    ));
}

/// Confirm an action that can't be undone. The confirm button names the action
/// ("Delete forever", "Empty trash") in the danger colour — never just "OK".
Future<bool> confirmDestructive(
  BuildContext context, {
  required String title,
  String? message,
  required String confirmLabel,
  required String cancelLabel,
}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (dialog) => AlertDialog(
      title: Text(title),
      content: message == null ? null : Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialog, false),
          child: Text(cancelLabel),
        ),
        TextButton(
          onPressed: () => Navigator.pop(dialog, true),
          child: Text(confirmLabel, style: TextStyle(color: dialog.colors.danger)),
        ),
      ],
    ),
  );
  return ok ?? false;
}

/// A large, tappable choice card used in action sheets (e.g. "New collage"):
/// icon, title and one line explaining what happens. [primary] lifts it with
/// the amber tint so the main path reads first.
class ActionCard extends StatelessWidget {
  const ActionCard({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.primary = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Material(
      color: primary ? c.amberTint : c.surfaceHigh,
      borderRadius: BorderRadius.circular(Radii.card),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(Radii.card),
        child: Container(
          constraints: const BoxConstraints(minHeight: 72),
          padding: const EdgeInsets.symmetric(horizontal: Space.lg, vertical: Space.md),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(Radii.card),
            border: Border.all(color: primary ? c.amber : c.line, width: primary ? 1.5 : 1),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: primary ? c.amber : c.surfaceInput,
                  borderRadius: BorderRadius.circular(Radii.control),
                ),
                child: Icon(icon, color: primary ? c.onAmber : c.textHi, size: 22),
              ),
              const SizedBox(width: Space.lg),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(title, style: context.text.labelLg.copyWith(color: c.textHi)),
                    const SizedBox(height: 2),
                    Text(subtitle, style: context.text.bodyMd.copyWith(color: c.textMid)),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: c.textLo),
            ],
          ),
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
          SizedBox(width: 84, child: Text(label, style: context.text.bodyMd)),
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
                style: context.text.spec, textAlign: TextAlign.right),
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
                  color: isSel ? context.colors.amber : context.colors.line,
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
