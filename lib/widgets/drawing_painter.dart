import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../models/canvas_element.dart';

/// Paints freehand strokes whose points are normalised to the painted box
/// (0..1 per axis) and whose widths are a fraction of the box width. Shared by
/// the canvas, template thumbnails and the live drawing overlay.
class DrawingPainter extends CustomPainter {
  DrawingPainter(this.strokes);

  final List<DrawStroke> strokes;

  @override
  void paint(Canvas canvas, Size size) {
    for (final s in strokes) {
      if (s.points.isEmpty) continue;
      final paint = Paint()
        ..color = s.color
        ..strokeWidth = (s.width * size.width).clamp(0.5, double.infinity)
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke;
      final pts = [for (final p in s.points) Offset(p.dx * size.width, p.dy * size.height)];
      if (pts.length == 1) {
        canvas.drawPoints(ui.PointMode.points, pts, paint);
        continue;
      }
      // Smooth through midpoints so fast strokes don't look jagged.
      final path = Path()..moveTo(pts.first.dx, pts.first.dy);
      for (var i = 1; i < pts.length - 1; i++) {
        final mid = Offset((pts[i].dx + pts[i + 1].dx) / 2, (pts[i].dy + pts[i + 1].dy) / 2);
        path.quadraticBezierTo(pts[i].dx, pts[i].dy, mid.dx, mid.dy);
      }
      path.lineTo(pts.last.dx, pts.last.dy);
      canvas.drawPath(path, paint);
    }
  }

  // Strokes are rebuilt as new lists while drawing, so identity is enough.
  @override
  bool shouldRepaint(DrawingPainter old) => true;
}
