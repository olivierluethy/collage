import 'package:flutter/material.dart';

import '../models/layout_template.dart';
import '../theme/tokens.dart';
import 'poly_clipper.dart';

/// Draws a tiny illustration of a layout's slots so the user can see, at a
/// glance, what each option does (the "little picture" the notes asked for).
class LayoutMiniature extends StatelessWidget {
  const LayoutMiniature({
    super.key,
    required this.template,
    this.gap = 3,
    this.slotColor = AppColors.surfaceInput,
    this.strokeColor = AppColors.textLo,
  });

  final LayoutTemplate template;
  final double gap;
  final Color slotColor;
  final Color strokeColor;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _MiniPainter(template, gap, slotColor, strokeColor),
      size: Size.infinite,
    );
  }
}

class _MiniPainter extends CustomPainter {
  _MiniPainter(this.template, this.gap, this.slotColor, this.strokeColor);
  final LayoutTemplate template;
  final double gap;
  final Color slotColor;
  final Color strokeColor;

  @override
  void paint(Canvas canvas, Size size) {
    final fill = Paint()..color = slotColor;
    final stroke = Paint()
      ..color = strokeColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    if (template.slots.isEmpty) {
      // Freeform: dashed frame with a plus.
      final rect = Offset.zero & size;
      canvas.drawRect(rect.deflate(1), fill);
      final c = size.center(Offset.zero);
      canvas.drawLine(Offset(c.dx - 6, c.dy), Offset(c.dx + 6, c.dy), stroke);
      canvas.drawLine(Offset(c.dx, c.dy - 6), Offset(c.dx, c.dy + 6), stroke);
      return;
    }

    for (final slot in template.slots) {
      if (slot.isPolygon) {
        final pts = [
          for (final p in slot.points!)
            Offset(p.dx * size.width, p.dy * size.height),
        ];
        final inset = insetConvexPolygon(pts, gap / 2);
        final path = polygonPath(inset);
        canvas.drawPath(path, fill);
        canvas.drawPath(path, stroke);
        continue;
      }
      final r = Rect.fromLTRB(
        slot.rect.left * size.width,
        slot.rect.top * size.height,
        slot.rect.right * size.width,
        slot.rect.bottom * size.height,
      ).deflate(gap / 2);
      final rr = RRect.fromRectAndRadius(r, const Radius.circular(2));
      canvas.drawRRect(rr, fill);
      canvas.drawRRect(rr, stroke);
    }
  }

  @override
  bool shouldRepaint(_MiniPainter old) => old.template != template;
}
