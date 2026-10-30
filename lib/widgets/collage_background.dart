import 'dart:math' as math;
import 'dart:ui' as ui;

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
        return LayoutBuilder(
          builder: (context, constraints) {
            // Blur scales with the canvas so the export matches the screen.
            final sigma = bg.imageBlur * constraints.maxWidth / 1000;
            return Stack(
              fit: StackFit.expand,
              children: [
                ClipRect(
                  child: ImageFiltered(
                    // A zero-sigma blur is a no-op, so the wrapper can stay in
                    // the tree and the photo keeps its decoded frame.
                    imageFilter: ui.ImageFilter.blur(sigmaX: sigma, sigmaY: sigma, tileMode: TileMode.decal),
                    child: Transform.scale(
                      // Overscan a little so blurred edges don't fade to clear.
                      scale: sigma > 0 ? 1.08 : 1.0,
                      child: PhotoImage(assetId: bg.imageAssetId!, full: true, fit: BoxFit.cover),
                    ),
                  ),
                ),
                if (bg.imageDim > 0)
                  ColoredBox(color: Colors.black.withValues(alpha: bg.imageDim)),
              ],
            );
          },
        );
    }
  }
}
