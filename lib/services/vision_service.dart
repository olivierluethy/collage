import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';
import 'dart:ui' show Offset;

import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:google_mlkit_subject_segmentation/google_mlkit_subject_segmentation.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import 'package:photo_manager/photo_manager.dart';

/// On-device image understanding (Google ML Kit, no network): finds faces to
/// frame photos around, and cuts the main subject out of a photo.
class VisionService {
  const VisionService();

  /// Centre of all faces in the photo as a fraction (0..1) of its upright
  /// width/height, or null when there are no faces.
  Future<Offset?> faceFocus(String assetId) async {
    final asset = await AssetEntity.fromId(assetId);
    final file = await asset?.file;
    if (asset == null || file == null) return null;
    final detector = FaceDetector(options: FaceDetectorOptions(minFaceSize: 0.05));
    try {
      final faces = await detector.processImage(InputImage.fromFilePath(file.path));
      if (faces.isEmpty) return null;
      var l = double.infinity, t = double.infinity;
      var r = -double.infinity, b = -double.infinity;
      for (final f in faces) {
        final box = f.boundingBox;
        if (box.left < l) l = box.left;
        if (box.top < t) t = box.top;
        if (box.right > r) r = box.right;
        if (box.bottom > b) b = box.bottom;
      }
      final w = asset.orientatedWidth.toDouble();
      final h = asset.orientatedHeight.toDouble();
      if (w <= 0 || h <= 0) return null;
      return Offset(((l + r) / 2 / w).clamp(0.0, 1.0), ((t + b) / 2 / h).clamp(0.0, 1.0));
    } finally {
      await detector.close();
    }
  }

  /// Cut the main subject out of a photo and save it as a transparent PNG,
  /// trimmed to the subject. Returns the file path, or null when nothing
  /// was found.
  Future<String?> cutout(String assetId, {required String id}) async {
    final asset = await AssetEntity.fromId(assetId);
    final file = await asset?.file;
    if (file == null) return null;
    final segmenter = SubjectSegmenter(
      options: SubjectSegmenterOptions(
        enableForegroundBitmap: true,
        enableForegroundConfidenceMask: false,
        enableMultipleSubjects: SubjectResultOptions(
          enableConfidenceMask: false,
          enableSubjectBitmap: false,
        ),
      ),
    );
    try {
      final result = await segmenter.processImage(InputImage.fromFilePath(file.path));
      final png = result.foregroundBitmap;
      if (png == null) return null;
      final trimmed = await Isolate.run(() => trimTransparent(png));
      if (trimmed == null) return null;
      final dir = Directory('${(await getApplicationDocumentsDirectory()).path}/cutouts');
      if (!await dir.exists()) await dir.create(recursive: true);
      final out = File('${dir.path}/$id.png');
      await out.writeAsBytes(trimmed);
      return out.path;
    } finally {
      await segmenter.close();
    }
  }
}

/// Crop a PNG to its non-transparent pixels (plus a small margin). Returns
/// null for a fully transparent image. Top-level for a background isolate.
Uint8List? trimTransparent(Uint8List png) {
  final src = img.decodePng(png);
  if (src == null) return null;
  var l = src.width, t = src.height, r = -1, b = -1;
  for (final p in src) {
    if (p.a > 8) {
      if (p.x < l) l = p.x;
      if (p.y < t) t = p.y;
      if (p.x > r) r = p.x;
      if (p.y > b) b = p.y;
    }
  }
  if (r < l || b < t) return null;
  const m = 4;
  l = (l - m).clamp(0, src.width - 1).toInt();
  t = (t - m).clamp(0, src.height - 1).toInt();
  r = (r + m).clamp(0, src.width - 1).toInt();
  b = (b + m).clamp(0, src.height - 1).toInt();
  return img.encodePng(img.copyCrop(src, x: l, y: t, width: r - l + 1, height: b - t + 1));
}

/// The pan offset (-1..1, as [SlotFill.offsetX]/[offsetY]) that brings
/// [focus] (0..1 of the photo) as close to the centre of a cover-fitted cell
/// as the photo allows. [cellAspect] and [imgAspect] are width / height.
Offset panForFocus(Offset focus, double cellAspect, double imgAspect) {
  double axis(double f, double visible) {
    if (visible >= 1) return 0; // no slack on this axis
    final left = (f - visible / 2).clamp(0.0, 1 - visible);
    return (left / (1 - visible)) * 2 - 1;
  }

  // Fraction of the photo visible on each axis under BoxFit.cover.
  final visW = imgAspect > cellAspect ? cellAspect / imgAspect : 1.0;
  final visH = imgAspect > cellAspect ? 1.0 : imgAspect / cellAspect;
  return Offset(axis(focus.dx, visW), axis(focus.dy, visH));
}
