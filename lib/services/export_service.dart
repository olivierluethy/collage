import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// Captures the collage canvas (wrapped in a RepaintBoundary) to a high-res
/// PNG for saving/sharing.
class ExportService {
  const ExportService();

  /// Render the boundary behind [key] to PNG bytes. [targetWidth] controls the
  /// output resolution; the pixel ratio is derived from the on-screen size.
  Future<Uint8List?> capture(GlobalKey key, {double targetWidth = 2048}) async {
    final ctx = key.currentContext;
    if (ctx == null) return null;
    final boundary = ctx.findRenderObject() as RenderRepaintBoundary?;
    if (boundary == null) return null;

    final logicalWidth = boundary.size.width;
    final ratio = logicalWidth == 0 ? 3.0 : (targetWidth / logicalWidth);
    final image = await boundary.toImage(pixelRatio: ratio.clamp(1.0, 6.0));
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    return data?.buffer.asUint8List();
  }
}
