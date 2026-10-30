import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/palette.dart';
import '../theme/tokens.dart';
import '../theme/typography.dart';

/// One stop on a [showCoachTour]: what to point at and what to say about it.
class CoachStep {
  const CoachStep({required this.target, required this.title, required this.body});

  /// The on-screen (global) rect to spotlight, resolved when the step shows so
  /// it follows the current layout. Null → no spotlight, bubble centred.
  final Rect? Function() target;
  final String title;
  final String body;
}

/// Labels for the tour's buttons, passed in so the widget stays l10n-agnostic.
class CoachLabels {
  const CoachLabels({required this.next, required this.done, required this.skip, required this.stepOf});
  final String next;
  final String done;
  final String skip;

  /// "{page} of {count}" style formatter for the step counter.
  final String Function(int step, int count) stepOf;
}

/// The styleguide coach-mark as a short guided tour: the rest of the screen
/// dims to `ink @72%`, the target sits in a lit cut-out with the amber
/// safelight ring, and a `surfaceHigh` bubble with an amber hairline explains
/// it. Tapping anywhere advances; "Skip" ends the tour. Completes when done.
Future<void> showCoachTour(
  BuildContext context, {
  required List<CoachStep> steps,
  required CoachLabels labels,
}) async {
  if (steps.isEmpty) return;
  // A transparent route rather than a bare overlay entry, so the system back
  // gesture closes the tour instead of leaving it stranded on screen.
  await Navigator.of(context, rootNavigator: true).push(PageRouteBuilder<void>(
    opaque: false,
    barrierDismissible: false,
    transitionDuration: Duration.zero,
    reverseTransitionDuration: Duration.zero,
    pageBuilder: (routeContext, _, __) => _CoachTour(
      steps: steps,
      labels: labels,
      onFinish: () => Navigator.of(routeContext).pop(),
    ),
  ));
}

class _CoachTour extends StatefulWidget {
  const _CoachTour({required this.steps, required this.labels, required this.onFinish});
  final List<CoachStep> steps;
  final CoachLabels labels;
  final VoidCallback onFinish;

  @override
  State<_CoachTour> createState() => _CoachTourState();
}

class _CoachTourState extends State<_CoachTour> with SingleTickerProviderStateMixin {
  int _i = 0;
  late final AnimationController _fade = AnimationController(vsync: this, duration: Motion.base);

  @override
  void initState() {
    super.initState();
    _fade.forward();
  }

  @override
  void dispose() {
    _fade.dispose();
    super.dispose();
  }

  bool get _last => _i == widget.steps.length - 1;

  Future<void> _advance() async {
    if (_last) {
      await _fade.reverse();
      widget.onFinish();
    } else {
      setState(() => _i++);
    }
  }

  Future<void> _skip() async {
    await _fade.reverse();
    widget.onFinish();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final step = widget.steps[_i];
    final size = MediaQuery.of(context).size;
    final raw = step.target();
    final hole = raw?.inflate(6);
    final still = MediaQuery.of(context).disableAnimations;

    // Bubble goes on whichever side of the target has more room.
    const bubbleMax = 360.0;
    final bubbleW = math.min(bubbleMax, size.width - Space.lg * 2);
    final below = hole == null || hole.center.dy < size.height / 2;
    final left = hole == null
        ? (size.width - bubbleW) / 2
        : (hole.center.dx - bubbleW / 2).clamp(Space.lg, size.width - bubbleW - Space.lg);

    return FadeTransition(
      opacity: still ? const AlwaysStoppedAnimation(1) : _fade,
      child: Material(
        type: MaterialType.transparency,
        child: Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _advance,
                child: CustomPaint(painter: _SpotlightPainter(hole: hole, scrim: c.ink.withValues(alpha: 0.72))),
              ),
            ),
            if (hole != null)
              Positioned.fromRect(
                rect: hole,
                child: IgnorePointer(
                  child: AnimatedContainer(
                    duration: still ? Duration.zero : Motion.slow,
                    curve: Motion.standard,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(Radii.card),
                      border: Border.all(color: c.amber, width: 2),
                      boxShadow: [BoxShadow(color: c.amberGlow, blurRadius: 20)],
                    ),
                  ),
                ),
              ),
            Positioned(
              left: left,
              width: bubbleW,
              top: below ? (hole == null ? size.height * 0.35 : hole.bottom + Space.md) : null,
              bottom: below ? null : size.height - hole.top + Space.md,
              child: _Bubble(
                step: step,
                counter: widget.labels.stepOf(_i + 1, widget.steps.length),
                primary: _last ? widget.labels.done : widget.labels.next,
                skip: _last ? null : widget.labels.skip,
                onPrimary: _advance,
                onSkip: _skip,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({
    required this.step,
    required this.counter,
    required this.primary,
    required this.skip,
    required this.onPrimary,
    required this.onSkip,
  });
  final CoachStep step;
  final String counter;
  final String primary;
  final String? skip;
  final VoidCallback onPrimary;
  final VoidCallback onSkip;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.fromLTRB(Space.lg, Space.lg, Space.sm, Space.sm),
        decoration: BoxDecoration(
          color: c.surfaceHigh,
          borderRadius: BorderRadius.circular(Radii.card),
          border: Border.all(color: c.amber),
          boxShadow: Shadows.e3,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.only(right: Space.sm),
              child: Row(
                children: [
                  Expanded(child: Text(step.title, style: context.text.titleMd)),
                  Text(counter, style: context.text.spec.copyWith(color: c.textLo)),
                ],
              ),
            ),
            const SizedBox(height: Space.xs),
            Padding(
              padding: const EdgeInsets.only(right: Space.sm),
              child: Text(step.body, style: context.text.bodyMd.copyWith(color: c.textMid)),
            ),
            const SizedBox(height: Space.sm),
            Row(
              children: [
                if (skip != null) TextButton(onPressed: onSkip, child: Text(skip!)),
                const Spacer(),
                TextButton(onPressed: onPrimary, child: Text(primary)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Dims everything except a rounded cut-out around the target.
class _SpotlightPainter extends CustomPainter {
  _SpotlightPainter({required this.hole, required this.scrim});
  final Rect? hole;
  final Color scrim;

  @override
  void paint(Canvas canvas, Size size) {
    final full = Path()..addRect(Offset.zero & size);
    final path = hole == null
        ? full
        : Path.combine(
            PathOperation.difference,
            full,
            Path()..addRRect(RRect.fromRectAndRadius(hole!, const Radius.circular(Radii.card))),
          );
    canvas.drawPath(path, Paint()..color = scrim);
  }

  @override
  bool shouldRepaint(_SpotlightPainter old) => old.hole != hole || old.scrim != scrim;
}
