import 'package:flutter/material.dart';

import '../data/fonts.dart';
import '../data/shape_catalog.dart';
import '../models/canvas_element.dart';
import '../models/collage_project.dart';
import '../models/collage_template.dart';
import 'collage_background.dart';
import 'drawing_painter.dart';
import 'layout_miniature.dart';
import 'sticker_image.dart';

/// A small, non-interactive preview of a [CollageTemplate]: its background, the
/// empty photo slots and the decorative text / stickers / shapes, laid out
/// exactly like the canvas so the tile matches what you get in the editor.
class TemplateThumbnail extends StatelessWidget {
  const TemplateThumbnail({super.key, required this.template, this.radius = 8});

  final CollageTemplate template;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final bg = template.background;
    final light = _dominant(bg).computeLuminance() > 0.5;
    final slotFill = light ? Colors.black.withValues(alpha: 0.10) : Colors.white.withValues(alpha: 0.22);
    final slotStroke = light ? Colors.black.withValues(alpha: 0.22) : Colors.white.withValues(alpha: 0.38);

    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final w = constraints.maxWidth;
          final h = constraints.maxHeight;
          final margin = (template.border.margin / 1000) * w;
          final elements = [...template.elements]..sort((a, b) => a.z.compareTo(b.z));
          return Stack(
            children: [
              Positioned.fill(child: CollageBackground(bg: bg)),
              Positioned.fill(
                child: Padding(
                  padding: EdgeInsets.all(margin),
                  child: LayoutMiniature(
                    template: template.layout,
                    gap: 3,
                    slotColor: slotFill,
                    strokeColor: slotStroke,
                  ),
                ),
              ),
              for (final e in elements)
                _element(context, e, w, h),
            ],
          );
        },
      ),
    );
  }

  Widget _element(BuildContext context, CanvasElement e, double w, double h) {
    Widget child;
    switch (e) {
      case StickerElement s:
        final size = s.naturalWidthFrac * w * s.scale;
        child = SizedBox(width: size, height: size, child: StickerImage(source: s.assetPath));
      case ShapeElement s:
        final size = s.naturalWidthFrac * w * s.scale;
        child = SizedBox(
          width: size,
          height: size,
          child: CustomPaint(
            painter: ShapePainter(kind: s.shapeKind, fill: s.fill, stroke: s.stroke, strokeWidth: s.strokeWidth),
          ),
        );
      case EmojiElement em:
        final fs = 0.18 * w * em.scale;
        child = Text(em.emoji, style: TextStyle(fontSize: fs), textAlign: TextAlign.center);
      case GifElement g:
        final size = g.naturalWidthFrac * w * g.scale;
        child = SizedBox(
          width: size,
          height: size / g.aspectRatio,
          child: Image.network(g.url, fit: BoxFit.contain, gaplessPlayback: true),
        );
      case ImageElement im:
        final size = im.naturalWidthFrac * w * im.scale;
        child = SizedBox(
          width: size,
          height: size / im.aspectRatio,
          child: ColoredBox(color: Colors.white.withValues(alpha: 0.2)),
        );
      case DrawingElement d:
        final size = d.naturalWidthFrac * w * d.scale;
        child = SizedBox(
          width: size,
          height: size / d.aspectRatio,
          child: CustomPaint(painter: DrawingPainter(d.strokes)),
        );
      case TextElement t:
        final fs = 0.09 * w * t.scale;
        child = SizedBox(
          width: w * 0.9,
          child: Text(
            t.text,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppFonts.style(t.fontKey, fontSize: fs, color: t.color, bold: t.bold, italic: t.italic),
          ),
        );
    }

    return Positioned(
      left: e.cx * w,
      top: e.cy * h,
      child: FractionalTranslation(
        translation: const Offset(-0.5, -0.5),
        child: Transform.rotate(angle: e.rotation, child: child),
      ),
    );
  }

  static Color _dominant(BackgroundSettings bg) => switch (bg.kind) {
        BackgroundKind.solid => bg.color,
        BackgroundKind.gradient => bg.gradientStart,
        BackgroundKind.pattern => bg.patternBg,
        BackgroundKind.image => const Color(0xFF1A1714),
      };
}
