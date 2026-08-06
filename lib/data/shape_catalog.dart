import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// Vector shapes the user can insert, colour, resize and rotate.
///
/// Each shape is generated as a [Path] scaled to fill the given [Size], so it
/// stays crisp at any scale. [ShapePainter] draws one with a fill and an
/// optional stroke.
class ShapeCatalog {
  ShapeCatalog._();

  /// Kinds shown in the shapes picker, with a friendly label.
  static const List<(String, String)> kinds = [
    ('circle', 'Circle'),
    ('square', 'Square'),
    ('rounded', 'Rounded'),
    ('triangle', 'Triangle'),
    ('diamond', 'Diamond'),
    ('star', 'Star'),
    ('heart', 'Heart'),
    ('arrow', 'Arrow'),
    ('bubble', 'Speech'),
    ('hexagon', 'Hexagon'),
    ('pentagon', 'Pentagon'),
    ('cross', 'Plus'),
  ];

  static Path pathFor(String kind, Size s) {
    final w = s.width, h = s.height;
    switch (kind) {
      case 'square':
        return Path()..addRect(Rect.fromLTWH(0, 0, w, h));
      case 'rounded':
        return Path()
          ..addRRect(RRect.fromRectAndRadius(
              Rect.fromLTWH(0, 0, w, h), Radius.circular(w * 0.18)));
      case 'circle':
        return Path()..addOval(Rect.fromLTWH(0, 0, w, h));
      case 'triangle':
        return Path()
          ..moveTo(w / 2, 0)
          ..lineTo(w, h)
          ..lineTo(0, h)
          ..close();
      case 'diamond':
        return Path()
          ..moveTo(w / 2, 0)
          ..lineTo(w, h / 2)
          ..lineTo(w / 2, h)
          ..lineTo(0, h / 2)
          ..close();
      case 'star':
        return _star(w, h, 5);
      case 'heart':
        return _heart(w, h);
      case 'arrow':
        return _arrow(w, h);
      case 'bubble':
        return _bubble(w, h);
      case 'hexagon':
        return _polygon(w, h, 6, -math.pi / 2);
      case 'pentagon':
        return _polygon(w, h, 5, -math.pi / 2);
      case 'cross':
        return _cross(w, h);
      default:
        return Path()..addOval(Rect.fromLTWH(0, 0, w, h));
    }
  }

  static Path _polygon(double w, double h, int sides, double startAngle) {
    final path = Path();
    final cx = w / 2, cy = h / 2, rx = w / 2, ry = h / 2;
    for (var i = 0; i < sides; i++) {
      final a = startAngle + i * 2 * math.pi / sides;
      final x = cx + rx * math.cos(a);
      final y = cy + ry * math.sin(a);
      i == 0 ? path.moveTo(x, y) : path.lineTo(x, y);
    }
    return path..close();
  }

  static Path _star(double w, double h, int points) {
    final path = Path();
    final cx = w / 2, cy = h / 2;
    final outerR = w / 2, innerR = w / 4.4;
    for (var i = 0; i < points * 2; i++) {
      final r = i.isEven ? outerR : innerR;
      final a = -math.pi / 2 + i * math.pi / points;
      final x = cx + r * math.cos(a);
      final y = cy + r * math.sin(a);
      i == 0 ? path.moveTo(x, y) : path.lineTo(x, y);
    }
    return path..close();
  }

  static Path _heart(double w, double h) {
    final path = Path();
    path.moveTo(w * 0.5, h * 0.32);
    path.cubicTo(w * 0.5, h * 0.10, w * 0.10, h * 0.02, w * 0.06, h * 0.34);
    path.cubicTo(w * 0.02, h * 0.60, w * 0.36, h * 0.78, w * 0.5, h * 0.94);
    path.cubicTo(w * 0.64, h * 0.78, w * 0.98, h * 0.60, w * 0.94, h * 0.34);
    path.cubicTo(w * 0.90, h * 0.02, w * 0.5, h * 0.10, w * 0.5, h * 0.32);
    return path..close();
  }

  static Path _arrow(double w, double h) {
    return Path()
      ..moveTo(0, h * 0.32)
      ..lineTo(w * 0.6, h * 0.32)
      ..lineTo(w * 0.6, h * 0.12)
      ..lineTo(w, h * 0.5)
      ..lineTo(w * 0.6, h * 0.88)
      ..lineTo(w * 0.6, h * 0.68)
      ..lineTo(0, h * 0.68)
      ..close();
  }

  static Path _bubble(double w, double h) {
    final bodyH = h * 0.78;
    final path = Path()
      ..addRRect(RRect.fromRectAndRadius(
          Rect.fromLTWH(0, 0, w, bodyH), Radius.circular(w * 0.16)));
    final tail = Path()
      ..moveTo(w * 0.22, bodyH - 1)
      ..lineTo(w * 0.18, h)
      ..lineTo(w * 0.42, bodyH - 1)
      ..close();
    return Path.combine(PathOperation.union, path, tail);
  }

  static Path _cross(double w, double h) {
    final t = w * 0.34; // arm thickness
    final cx = (w - t) / 2, cy = (h - t) / 2;
    final v = Path()..addRect(Rect.fromLTWH(cx, 0, t, h));
    final hor = Path()..addRect(Rect.fromLTWH(0, cy, w, t));
    return Path.combine(PathOperation.union, v, hor);
  }
}

/// Paints a [ShapeCatalog] shape with a fill and optional stroke.
class ShapePainter extends CustomPainter {
  ShapePainter({
    required this.kind,
    required this.fill,
    this.stroke,
    this.strokeWidth = 0,
  });

  final String kind;
  final Color fill;
  final Color? stroke;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final inset = strokeWidth / 2;
    final path = ShapeCatalog.pathFor(
      kind,
      Size(size.width - strokeWidth, size.height - strokeWidth),
    ).shift(Offset(inset, inset));
    canvas.drawPath(path, Paint()..color = fill..style = PaintingStyle.fill);
    if (stroke != null && strokeWidth > 0) {
      canvas.drawPath(
        path,
        Paint()
          ..color = stroke!
          ..style = PaintingStyle.stroke
          ..strokeJoin = StrokeJoin.round
          ..strokeWidth = strokeWidth,
      );
    }
  }

  @override
  bool shouldRepaint(ShapePainter old) =>
      old.kind != kind ||
      old.fill != fill ||
      old.stroke != stroke ||
      old.strokeWidth != strokeWidth;
}
