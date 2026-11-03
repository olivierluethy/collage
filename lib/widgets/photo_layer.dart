import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../data/shape_catalog.dart';
import '../models/canvas_element.dart';
import '../theme/palette.dart';
import 'photo_image.dart';

/// Where the photo of an [ImageElement] sits inside its frame of [width]
/// pixels: the frame's height, the visible (cropped) region's size, and the
/// full photo's rect relative to the frame.
///
/// The cropped region cover-fills the frame, is scaled by `zoom`, and its
/// slack beyond the frame is distributed by the pan alignment (-1 = flush
/// left/top, 1 = flush right/bottom). For a plain photo layer (no own frame
/// aspect, zoom 1) the region equals the frame — exactly the old crop.
class PhotoLayerGeometry {
  PhotoLayerGeometry._(this.frame, this.region, this.photo);

  final Size frame;
  final Size region;
  final Rect photo;

  /// How far the region overflows the frame on each axis (pan slack).
  Size get overflow => Size(region.width - frame.width, region.height - frame.height);

  factory PhotoLayerGeometry.of(ImageElement im, double width) {
    final w = width;
    final h = w / im.aspectRatio;
    final ca = im.croppedAspect;
    var rw = w, rh = h;
    if (ca > w / h) {
      rh = h;
      rw = h * ca;
    } else {
      rw = w;
      rh = w / ca;
    }
    rw *= im.zoom;
    rh *= im.zoom;
    final fw = rw / (1 - im.cropL - im.cropR);
    final fh = rh / (1 - im.cropT - im.cropB);
    final left = -(rw - w) * (im.panX + 1) / 2 - im.cropL * fw;
    final top = -(rh - h) * (im.panY + 1) / 2 - im.cropT * fh;
    return PhotoLayerGeometry._(Size(w, h), Size(rw, rh), Rect.fromLTWH(left, top, fw, fh));
  }
}

/// The clip outline of a photo layer's frame: its mask shape, its custom
/// points, or a softly rounded rectangle (the look of earlier versions).
Path photoLayerMask(ImageElement im, Size size) {
  if (im.mask == 'custom' && im.maskPoints != null && im.maskPoints!.length >= 3) {
    return ShapeCatalog.pointsPath(im.maskPoints!, size);
  }
  if (im.mask != 'none') return ShapeCatalog.pathFor(im.mask, size);
  return Path()..addRRect(RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(6)));
}

/// Renders a photo layer at [width] pixels. Shared by the editor and the
/// export (same widget, same tree), so the saved collage matches the screen.
class PhotoLayerView extends StatelessWidget {
  const PhotoLayerView({super.key, required this.element, required this.width, required this.unit});
  final ImageElement element;
  final double width;

  /// Canvas pixels per 1/1000 of the canvas width (for the contour).
  final double unit;

  @override
  Widget build(BuildContext context) {
    final im = element;
    final g = PhotoLayerGeometry.of(im, width);
    Widget photo = im.isPlaceholder
        ? ColoredBox(
            color: context.colors.surfaceInput,
            child: Center(
              child: Icon(Icons.add_photo_alternate_outlined,
                  color: context.colors.textLo, size: math.min(g.frame.shortestSide * 0.3, 32)),
            ),
          )
        : Stack(
            clipBehavior: Clip.hardEdge,
            children: [
              Positioned(
                left: g.photo.left,
                top: g.photo.top,
                width: g.photo.width,
                height: g.photo.height,
                child: PhotoImage(assetId: im.assetId, full: true, fit: BoxFit.cover),
              ),
            ],
          );
    // The wrapper is always built so the photo keeps its ancestors when a
    // flip is toggled; only the photo mirrors, never the frame's shape.
    photo = Transform.scale(scaleX: im.flipX ? -1 : 1, scaleY: im.flipY ? -1 : 1, child: photo);
    final outline = im.outlineWidth * unit;
    return SizedBox(
      width: g.frame.width,
      height: g.frame.height,
      child: CustomPaint(
        painter: _ShapeShadowPainter(mask: im, elevation: im.shadow ? 10 * unit : 0),
        foregroundPainter: outline > 0 ? _OutlinePainter(mask: im, color: im.outlineColor, width: outline) : null,
        child: ClipPath(clipper: _MaskClipper(im), child: photo),
      ),
    );
  }
}

class _MaskClipper extends CustomClipper<Path> {
  _MaskClipper(ImageElement im)
      : mask = im.mask,
        points = im.maskPoints == null ? null : List.unmodifiable(im.maskPoints!),
        _im = im;
  final String mask;
  final List<Offset>? points;
  final ImageElement _im;

  @override
  Path getClip(Size size) => photoLayerMask(_im, size);

  @override
  bool shouldReclip(_MaskClipper old) => old.mask != mask || !_samePoints(old.points, points);
}

bool _samePoints(List<Offset>? a, List<Offset>? b) {
  if (identical(a, b)) return true;
  if (a == null || b == null || a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

class _OutlinePainter extends CustomPainter {
  _OutlinePainter({required this.mask, required this.color, required this.width});
  final ImageElement mask;
  final Color color;
  final double width;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawPath(
      photoLayerMask(mask, size),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeJoin = StrokeJoin.round
        ..strokeWidth = width
        ..color = color,
    );
  }

  @override
  bool shouldRepaint(_OutlinePainter old) => true;
}

class _ShapeShadowPainter extends CustomPainter {
  _ShapeShadowPainter({required this.mask, required this.elevation});
  final ImageElement mask;
  final double elevation;

  @override
  void paint(Canvas canvas, Size size) {
    if (elevation <= 0) return;
    canvas.drawShadow(photoLayerMask(mask, size), Colors.black, elevation, false);
  }

  @override
  bool shouldRepaint(_ShapeShadowPainter old) => true;
}
