import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/palette.dart';
import '../theme/tokens.dart';

/// A small, drawn collage — three "prints" on a lightbox — used as the
/// illustration for onboarding and empty states, so the app shows what it
/// makes instead of describing it. No image assets: each print is a warm
/// gradient with a simple motif.
///
/// With [swap] the two right-hand prints trade places on a loop, the one
/// gesture that sets the app apart (you decide what goes where). Under
/// reduced motion the swap is skipped and the collage stays still.
class MiniCollage extends StatefulWidget {
  const MiniCollage({super.key, this.swap = false, this.size = 220});

  final bool swap;
  final double size;

  @override
  State<MiniCollage> createState() => _MiniCollageState();
}

/// Print tones stand in for the user's photos (sunset, sea, meadow). They are
/// illustration content, not UI chrome, so they live here rather than in the
/// palette.
const _prints = <(List<Color>, IconData)>[
  ([Color(0xFFFFB454), Color(0xFFD9653B)], Icons.wb_twilight_rounded),
  ([Color(0xFF6FB2FF), Color(0xFF2F5F9E)], Icons.sailing_rounded),
  ([Color(0xFF8BD39A), Color(0xFF3E7D52)], Icons.local_florist_rounded),
];

class _MiniCollageState extends State<MiniCollage> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 3600),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final still = MediaQuery.of(context).disableAnimations;
    if (widget.swap && !still) {
      if (!_ctrl.isAnimating) _ctrl.repeat();
    } else {
      _ctrl.stop();
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  /// 0 → prints in place, 1 → swapped. Holds, lifts, crosses, settles, holds.
  double _swapT(double v) {
    double ease(double x) => Motion.standard.transform(x.clamp(0.0, 1.0));
    if (v < 0.30) return 0;
    if (v < 0.50) return ease((v - 0.30) / 0.20);
    if (v < 0.80) return 1;
    return 1 - ease((v - 0.80) / 0.20);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final s = widget.size;
    const gap = 6.0;
    const pad = 10.0;
    final inner = s - pad * 2;
    final colW = (inner - gap) / 2;
    final cellH = (inner - gap) / 2;
    final left = Rect.fromLTWH(pad, pad, colW, inner);
    final topRight = Rect.fromLTWH(pad + colW + gap, pad, colW, cellH);
    final bottomRight = Rect.fromLTWH(pad + colW + gap, pad + cellH + gap, colW, cellH);

    return ExcludeSemantics(
      child: SizedBox(
        width: s,
        height: s,
        child: AnimatedBuilder(
          animation: _ctrl,
          builder: (context, _) {
            final t = widget.swap ? _swapT(_ctrl.value) : 0.0;
            // A lift (scale + glow) peaks mid-swap so the motion reads as "picked up".
            final lift = math.sin(t * math.pi);
            final a = Rect.lerp(topRight, bottomRight, t)!;
            final b = Rect.lerp(bottomRight, topRight, t)!;
            return Container(
              decoration: BoxDecoration(
                color: c.surface,
                borderRadius: BorderRadius.circular(Radii.sheet),
                border: Border.all(color: c.line),
                boxShadow: Shadows.e3,
              ),
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  _place(left, _Print(_prints[0])),
                  _place(b, _Print(_prints[2])),
                  _place(a, _Print(_prints[1], lifted: lift), scale: 1 + 0.06 * lift),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _place(Rect r, Widget child, {double scale = 1}) => Positioned.fromRect(
        rect: r,
        child: Transform.scale(scale: scale, child: child),
      );
}

class _Print extends StatelessWidget {
  const _Print(this.print, {this.lifted = 0});
  final (List<Color>, IconData) print;
  final double lifted;

  @override
  Widget build(BuildContext context) {
    final (colors, icon) = print;
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(Radii.slotDefault),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: colors,
        ),
        border: lifted > 0.01 ? Border.all(color: context.colors.amber, width: 1.5) : null,
        boxShadow: lifted > 0.01
            ? [BoxShadow(color: context.colors.amberGlow.withValues(alpha: 0.32 * lifted), blurRadius: 20)]
            : null,
      ),
      alignment: Alignment.center,
      child: LayoutBuilder(
        builder: (context, box) => Icon(
          icon,
          size: math.min(box.maxWidth, box.maxHeight) * 0.38,
          color: Colors.white.withValues(alpha: 0.55),
        ),
      ),
    );
  }
}
