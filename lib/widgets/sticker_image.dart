import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// Renders a sticker from either a bundled asset path (`assets/stickers/...`)
/// or a remote URL. SVG sources go through [SvgPicture]; anything else is
/// treated as a raster image (png / webp / jpg / gif). Used by both the
/// Stickers panel and the collage canvas so a sticker looks the same wherever
/// it appears.
class StickerImage extends StatelessWidget {
  const StickerImage({super.key, required this.source, this.fit = BoxFit.contain});

  /// Asset path, http(s) URL, or an absolute file path (cut-outs the user
  /// made, stored in the app's documents directory).
  final String source;
  final BoxFit fit;

  static bool isRemote(String source) =>
      source.startsWith('http://') || source.startsWith('https://');

  static bool isFile(String source) => source.startsWith('/');

  static bool isSvg(String source) =>
      source.toLowerCase().split('?').first.endsWith('.svg');

  @override
  Widget build(BuildContext context) {
    if (isFile(source)) {
      return Image.file(File(source), fit: fit, gaplessPlayback: true);
    }
    if (isRemote(source)) {
      return isSvg(source)
          ? SvgPicture.network(source, fit: fit)
          : Image.network(source, fit: fit, gaplessPlayback: true);
    }
    return isSvg(source)
        ? SvgPicture.asset(source, fit: fit)
        : Image.asset(source, fit: fit);
  }
}
