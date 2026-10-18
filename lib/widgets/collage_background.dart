import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/collage_project.dart';
import '../theme/palette.dart';
import 'pattern_painter.dart';
import 'photo_image.dart';

/// Draws the collage background: a solid colour, gradient, bundled pattern or a
/// user-chosen photo. Shared by the editor canvas and the template thumbnails so
/// both render a background identically.
class CollageBackground extends StatelessWidget {
  const CollageBackground({super.key, required this.bg});

  final BackgroundSettings bg;

  @override
  Widget build(BuildContext context) {
    switch (bg.kind) {
      case BackgroundKind.solid:
        return ColoredBox(color: bg.color);
      case BackgroundKind.gradient:
        return DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [bg.gradientStart, bg.gradientEnd],
              begin: Alignment(math.cos(bg.gradientAngle), math.sin(bg.gradientAngle)),
              end: Alignment(-math.cos(bg.gradientAngle), -math.sin(bg.gradientAngle)),
            ),
          ),
        );
      case BackgroundKind.pattern:
        return PatternBackground(
          patternKey: bg.patternKey,
          color: bg.patternColor,
          background: bg.patternBg,
        );
      case BackgroundKind.image:
        if (bg.imageAssetId == null) {
          return ColoredBox(color: context.colors.inkCanvas);
        }
        return Stack(
          fit: StackFit.expand,
          children: [
            PhotoImage(assetId: bg.imageAssetId!, full: true, fit: BoxFit.cover),
            if (bg.imageDim > 0)
              ColoredBox(color: Colors.black.withValues(alpha: bg.imageDim)),
          ],
        );
    }
  }
}
