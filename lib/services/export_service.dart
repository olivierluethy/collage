import 'dart:isolate';
import 'dart:ui' as ui;

import 'dart:io';

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

/// File format of an exported collage.
enum ExportFormat {
  png('png', 'image/png'),
  jpg('jpg', 'image/jpeg'),

  /// Animated: only offered when the collage contains GIF stickers.
  gif('gif', 'image/gif'),

  /// Printable document; A4 collages get an exact A4 page.
  pdf('pdf', 'application/pdf'),

  /// Video: only offered when the collage contains video cells.
  mp4('mp4', 'video/mp4');

  /// Formats a phone gallery can hold as a picture.
  bool get isImage => this == png || this == jpg || this == gif;

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

/// Encoded bytes plus the format they are in. PDF and MP4 carry a PNG
/// [preview] for the result screen; for images the bytes are the preview.
class ExportResult {
  const ExportResult(this.bytes, this.format, {this.previewBytes});
  final Uint8List bytes;
  final ExportFormat format;
  final Uint8List? previewBytes;

  Uint8List get preview => previewBytes ?? bytes;
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
  /// [a4Page] puts a PDF onto an exact A4 sheet (portrait or [landscape]);
  /// otherwise the page takes the collage's own proportions.
  Future<ExportResult?> captureAs(
    GlobalKey key,
    ExportOptions options, {
    bool a4Page = false,
    bool landscape = false,
  }) async {
    if (options.format == ExportFormat.gif) return _captureGif(key, options.size.width);
    if (options.format == ExportFormat.mp4) return _captureVideo(key, options.size.width);
    if (options.format == ExportFormat.pdf) {
      final png = await capture(key, targetWidth: options.size.width);
      if (png == null) return null;
      final doc = await Isolate.run(() => buildPdf([png], a4: a4Page, landscape: landscape));
      return ExportResult(doc, ExportFormat.pdf, previewBytes: png);
    }
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

  /// Video collages: frames sampled from the live canvas while its video
  /// cells play, encoded to H.264 by the platform (see VideoEncoder.kt).
  static const videoMaxWidth = 1080.0;
  static const videoSeconds = 6;
  static const videoFps = 15;
  static const _encoder = MethodChannel('collage/video_encoder');

  Future<ExportResult?> _captureVideo(GlobalKey key, double targetWidth) async {
    final width = targetWidth < videoMaxWidth ? targetWidth : videoMaxWidth;
    final first = await _render(key, width);
    if (first == null) return null;
    // Encoders want sizes in multiples of 16.
    final w = first.width ~/ 16 * 16;
    final h = first.height ~/ 16 * 16;
    final previewData = await first.toByteData(format: ui.ImageByteFormat.png);
    first.dispose();
    final path = '${(await getTemporaryDirectory()).path}/collage_${DateTime.now().millisecondsSinceEpoch}.mp4';
    await _encoder.invokeMethod('start', {'path': path, 'width': w, 'height': h, 'fps': videoFps});
    final frameTime = Duration(microseconds: 1000000 ~/ videoFps);
    final clock = Stopwatch()..start();
    try {
      for (var i = 0; i < videoSeconds * videoFps; i++) {
        final due = frameTime * i;
        if (clock.elapsed < due) await Future.delayed(due - clock.elapsed);
        final image = await _render(key, width);
        if (image == null) break;
        final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
        final iw = image.width;
        image.dispose();
        if (data == null) break;
        await _encoder.invokeMethod('frame', {'rgba': cropRgba(data.buffer.asUint8List(), iw, w, h)});
      }
    } finally {
      await _encoder.invokeMethod('finish');
    }
    final file = File(path);
    if (!await file.exists()) return null;
    return ExportResult(await file.readAsBytes(), ExportFormat.mp4, previewBytes: previewData?.buffer.asUint8List());
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

/// The top-left [w]×[h] pixels of an RGBA image that is [srcWidth] wide.
Uint8List cropRgba(Uint8List rgba, int srcWidth, int w, int h) {
  if (srcWidth == w && rgba.length == w * h * 4) return rgba;
  final out = Uint8List(w * h * 4);
  for (var y = 0; y < h; y++) {
    out.setRange(y * w * 4, (y + 1) * w * 4, rgba, y * srcWidth * 4);
  }
  return out;
}

/// Cut an image into a [rows]×[cols] grid for an Instagram profile, returned
/// in posting order: Instagram shows the newest post top-left, so the
/// bottom-right tile has to be posted first.
List<Uint8List> splitGrid(Uint8List bytes, int rows, int cols, ExportFormat format) {
  final src = img.decodeImage(bytes);
  if (src == null || rows * cols < 2) return [bytes];
  final w = src.width ~/ cols, h = src.height ~/ rows;
  final tiles = <Uint8List>[];
  for (var r = rows - 1; r >= 0; r--) {
    for (var c = cols - 1; c >= 0; c--) {
      final piece = img.copyCrop(src, x: c * w, y: r * h, width: w, height: h);
      tiles.add(format == ExportFormat.png ? img.encodePng(piece) : img.encodeJpg(piece, quality: 92));
    }
  }
  return tiles;
}

/// A PDF with one page per image (PNG or JPG bytes). With [a4], each page is
/// an A4 sheet (landscape if asked) with the image fitted onto it; otherwise
/// each page takes its image's proportions at A4 width.
Future<Uint8List> buildPdf(List<Uint8List> images, {bool a4 = false, bool landscape = false}) async {
  final doc = pw.Document();
  for (final bytes in images) {
    final image = pw.MemoryImage(bytes);
    final ratio = (image.width ?? 1) / (image.height ?? 1);
    final format = a4
        ? (landscape ? PdfPageFormat.a4.landscape : PdfPageFormat.a4)
        : PdfPageFormat(PdfPageFormat.a4.width, PdfPageFormat.a4.width / ratio);
    doc.addPage(pw.Page(
      pageFormat: format,
      margin: pw.EdgeInsets.zero,
      build: (_) => pw.Center(child: pw.Image(image, fit: pw.BoxFit.contain)),
    ));
  }
  return doc.save();
}
