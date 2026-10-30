import 'dart:isolate';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:image/image.dart' as img;

/// File format of an exported collage.
enum ExportFormat {
  png('png', 'image/png'),
  jpg('jpg', 'image/jpeg'),

  /// Animated: only offered when the collage contains GIF stickers.
  gif('gif', 'image/gif');

  const ExportFormat(this.extension, this.mimeType);
  final String extension;
  final String mimeType;
}

/// Output width choices offered on Save, from a light share-size up to print.
enum ExportSize {
  small(1080),
  standard(2048),
  large(4096);

  const ExportSize(this.width);
  final double width;
}

/// What the user picked in the export sheet.
class ExportOptions {
  const ExportOptions({
    this.format = ExportFormat.png,
    this.size = ExportSize.standard,
    this.jpgQuality = 92,
  });

  final ExportFormat format;
  final ExportSize size;
  final int jpgQuality; // 1..100, JPG only

  ExportOptions copyWith({ExportFormat? format, ExportSize? size, int? jpgQuality}) =>
      ExportOptions(
        format: format ?? this.format,
        size: size ?? this.size,
        jpgQuality: jpgQuality ?? this.jpgQuality,
      );
}

/// Encoded image bytes plus the format they are in.
class ExportResult {
  const ExportResult(this.bytes, this.format);
  final Uint8List bytes;
  final ExportFormat format;
}

/// Captures the collage canvas (wrapped in a RepaintBoundary) to a high-res
/// PNG or JPG for saving/sharing.
class ExportService {
  const ExportService();

  /// Render the boundary behind [key] to PNG bytes. [targetWidth] controls the
  /// output resolution; the pixel ratio is derived from the on-screen size.
  Future<Uint8List?> capture(GlobalKey key, {double targetWidth = 2048}) async {
    final image = await _render(key, targetWidth);
    if (image == null) return null;
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    return data?.buffer.asUint8List();
  }

  /// Render the boundary behind [key] in the chosen format and size. JPG is
  /// encoded off the UI isolate; it has no alpha, so transparent pixels are
  /// flattened onto white.
  Future<ExportResult?> captureAs(GlobalKey key, ExportOptions options) async {
    if (options.format == ExportFormat.gif) return _captureGif(key, options.size.width);
    if (options.format == ExportFormat.png) {
      final png = await capture(key, targetWidth: options.size.width);
      return png == null ? null : ExportResult(png, ExportFormat.png);
    }
    final image = await _render(key, options.size.width);
    if (image == null) return null;
    final w = image.width;
    final h = image.height;
    final data = await image.toByteData(format: ui.ImageByteFormat.rawStraightRgba);
    image.dispose();
    if (data == null) return null;
    final rgba = data.buffer.asUint8List();
    final quality = options.jpgQuality.clamp(1, 100).toInt();
    final jpg = await Isolate.run(() => encodeJpg(rgba, w, h, quality));
    return ExportResult(jpg, ExportFormat.jpg);
  }

  /// Animated GIFs: frames sampled from the live canvas, so GIF stickers keep
  /// moving. Width is capped (GIFs get large fast) and the palette is 256
  /// colours, so photos lose some detail compared with PNG/JPG.
  static const gifMaxWidth = 720.0;
  static const gifFrames = 24;
  static const gifFrameDelay = Duration(milliseconds: 100);

  Future<ExportResult?> _captureGif(GlobalKey key, double targetWidth) async {
    final width = targetWidth < gifMaxWidth ? targetWidth : gifMaxWidth;
    final frames = <Uint8List>[];
    var w = 0, h = 0;
    for (var i = 0; i < gifFrames; i++) {
      if (i > 0) await Future.delayed(gifFrameDelay);
      final image = await _render(key, width);
      if (image == null) return null;
      w = image.width;
      h = image.height;
      final data = await image.toByteData(format: ui.ImageByteFormat.rawStraightRgba);
      image.dispose();
      if (data == null) return null;
      frames.add(data.buffer.asUint8List());
    }
    final delay = gifFrameDelay.inMilliseconds ~/ 10;
    final gif = await Isolate.run(() => encodeGif(frames, w, h, delay));
    return gif == null ? null : ExportResult(gif, ExportFormat.gif);
  }

  Future<ui.Image?> _render(GlobalKey key, double targetWidth) async {
    final ctx = key.currentContext;
    if (ctx == null) return null;
    final boundary = ctx.findRenderObject() as RenderRepaintBoundary?;
    if (boundary == null) return null;

    final logicalWidth = boundary.size.width;
    final ratio = logicalWidth == 0 ? 3.0 : (targetWidth / logicalWidth);
    return boundary.toImage(pixelRatio: ratio.clamp(1.0, 12.0));
  }
}

/// Encode straight RGBA pixels as a JPG, compositing any transparency onto
/// white. Top-level so it can run in a background isolate.
Uint8List encodeJpg(Uint8List rgba, int width, int height, int quality) {
  final src = img.Image.fromBytes(
    width: width,
    height: height,
    bytes: rgba.buffer,
    numChannels: 4,
    order: img.ChannelOrder.rgba,
  );
  final flat = img.Image(width: width, height: height)
    ..clear(img.ColorRgb8(255, 255, 255));
  img.compositeImage(flat, src);
  return img.encodeJpg(flat, quality: quality);
}

/// Encode RGBA frames (all [width]×[height]) as a looping GIF; [delay] is per
/// frame in 1/100 s. Top-level so it can run in a background isolate.
Uint8List? encodeGif(List<Uint8List> frames, int width, int height, int delay) {
  final enc = img.GifEncoder(delay: delay, repeat: 0, samplingFactor: 20);
  for (final f in frames) {
    final frame = img.Image.fromBytes(
      width: width,
      height: height,
      bytes: f.buffer,
      numChannels: 4,
      order: img.ChannelOrder.rgba,
    );
    enc.addFrame(frame.convert(numChannels: 3));
  }
  return enc.finish();
}

/// Cut a wide image into [slides] equal side-by-side pieces (an Instagram
/// carousel), re-encoded in [format]. Top-level for a background isolate.
List<Uint8List> splitCarousel(Uint8List bytes, int slides, ExportFormat format) {
  final src = img.decodeImage(bytes);
  if (src == null || slides < 2) return [bytes];
  final w = src.width ~/ slides;
  return [
    for (var i = 0; i < slides; i++)
      () {
        final piece = img.copyCrop(src, x: i * w, y: 0, width: w, height: src.height);
        return format == ExportFormat.png ? img.encodePng(piece) : img.encodeJpg(piece, quality: 92);
      }(),
  ];
}
