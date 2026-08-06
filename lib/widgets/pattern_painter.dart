import 'package:flutter/widgets.dart';

/// Draws the bundled background patterns programmatically (no asset files):
/// dots, grid, stripes, chevron, hearts, triangles, confetti, crosses.
class PatternPainter extends CustomPainter {
  PatternPainter({
    required this.patternKey,
    required this.color,
    required this.background,
    this.tile = 44,
  });

  final String patternKey;
  final Color color;
  final Color background;
  final double tile;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = background);
    final p = Paint()
      ..color = color
      ..style = PaintingStyle.fill
      ..strokeWidth = 2
      ..isAntiAlias = true;
    final line = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    switch (patternKey) {
      case 'grid':
        for (double x = 0; x <= size.width; x += tile) {
          canvas.drawLine(Offset(x, 0), Offset(x, size.height), line);
        }
        for (double y = 0; y <= size.height; y += tile) {
          canvas.drawLine(Offset(0, y), Offset(size.width, y), line);
        }
        break;
      case 'stripes':
        final sp = Paint()
          ..color = color
          ..strokeWidth = tile * 0.4;
        for (double x = -size.height; x < size.width; x += tile) {
          canvas.drawLine(
              Offset(x, 0), Offset(x + size.height, size.height), sp);
        }
        break;
      case 'chevron':
        for (double y = 0; y < size.height + tile; y += tile) {
          final path = Path();
          for (double x = 0; x < size.width + tile; x += tile) {
            path.moveTo(x, y);
            path.lineTo(x + tile / 2, y - tile / 2);
            path.lineTo(x + tile, y);
          }
          canvas.drawPath(path, line);
        }
        break;
      case 'hearts':
        _stamp(canvas, size, (c, o) => _heart(c, o, tile * 0.32, p));
        break;
      case 'triangles':
        _stamp(canvas, size, (c, o) {
          final path = Path()
            ..moveTo(o.dx, o.dy + tile * 0.28)
            ..lineTo(o.dx + tile * 0.28, o.dy - tile * 0.28)
            ..lineTo(o.dx - tile * 0.28, o.dy - tile * 0.28)
            ..close();
          c.drawPath(path, p);
        });
        break;
      case 'confetti':
        var i = 0;
        _stamp(canvas, size, (c, o) {
          c.save();
          c.translate(o.dx, o.dy);
          c.rotate((i % 4) * 0.5);
          c.drawRRect(
            RRect.fromRectAndRadius(
                Rect.fromCenter(center: Offset.zero, width: tile * 0.5, height: tile * 0.18),
                const Radius.circular(2)),
            p,
          );
          c.restore();
          i++;
        });
        break;
      case 'crosses':
        _stamp(canvas, size, (c, o) {
          final r = tile * 0.18;
          c.drawLine(Offset(o.dx - r, o.dy), Offset(o.dx + r, o.dy), line);
          c.drawLine(Offset(o.dx, o.dy - r), Offset(o.dx, o.dy + r), line);
        });
        break;
      case 'dots':
      default:
        _stamp(canvas, size,
            (c, o) => c.drawCircle(o, tile * 0.14, p));
        break;
    }
  }

  void _stamp(Canvas canvas, Size size, void Function(Canvas, Offset) draw) {
    var row = 0;
    for (double y = tile / 2; y < size.height + tile; y += tile) {
      final xOff = row.isOdd ? tile / 2 : 0.0;
      for (double x = tile / 2 + xOff; x < size.width + tile; x += tile) {
        draw(canvas, Offset(x, y));
      }
      row++;
    }
  }

  void _heart(Canvas canvas, Offset o, double s, Paint p) {
    final path = Path();
    path.moveTo(o.dx, o.dy + s * 0.5);
    path.cubicTo(o.dx - s, o.dy - s * 0.4, o.dx - s * 0.5, o.dy - s,
        o.dx, o.dy - s * 0.3);
    path.cubicTo(o.dx + s * 0.5, o.dy - s, o.dx + s, o.dy - s * 0.4,
        o.dx, o.dy + s * 0.5);
    canvas.drawPath(path, p);
  }

  @override
  bool shouldRepaint(PatternPainter old) =>
      old.patternKey != patternKey ||
      old.color != color ||
      old.background != background ||
      old.tile != tile;
}

/// Convenience widget that fills its box with a pattern.
class PatternBackground extends StatelessWidget {
  const PatternBackground({
    super.key,
    required this.patternKey,
    required this.color,
    required this.background,
    this.tile = 44,
  });

  final String patternKey;
  final Color color;
  final Color background;
  final double tile;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: PatternPainter(
        patternKey: patternKey,
        color: color,
        background: background,
        tile: tile,
      ),
      size: Size.infinite,
    );
  }
}
