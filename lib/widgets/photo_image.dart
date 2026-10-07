import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';

import '../theme/palette.dart';

/// Renders a device photo by its photo_manager asset id, caching bytes in
/// memory so the same photo doesn't reload on every rebuild.
class PhotoImage extends StatefulWidget {
  const PhotoImage({
    super.key,
    required this.assetId,
    this.full = false,
    this.fit = BoxFit.cover,
    this.thumbPx = 400,
    this.alignment = Alignment.center,
  });

  final String assetId;
  final bool full;
  final BoxFit fit;
  final int thumbPx;
  final Alignment alignment;

  static final Map<String, Uint8List> _thumbCache = {};
  static final Map<String, Uint8List> _fullCache = {};

  /// Best-available bytes for export/AI without building a widget.
  static Future<Uint8List?> bytes(String assetId, {bool full = false, int thumbPx = 400}) async {
    final cache = full ? _fullCache : _thumbCache;
    if (cache.containsKey(assetId)) return cache[assetId];
    final asset = await AssetEntity.fromId(assetId);
    if (asset == null) return null;
    final data = full
        ? await asset.originBytes
        : await asset.thumbnailDataWithSize(ThumbnailSize.square(thumbPx));
    if (data != null) cache[assetId] = data;
    return data;
  }

  @override
  State<PhotoImage> createState() => _PhotoImageState();
}

class _PhotoImageState extends State<PhotoImage> {
  Uint8List? _bytes;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(PhotoImage old) {
    super.didUpdateWidget(old);
    if (old.assetId != widget.assetId || old.full != widget.full) _load();
  }

  Future<void> _load() async {
    final data = await PhotoImage.bytes(widget.assetId,
        full: widget.full, thumbPx: widget.thumbPx);
    if (mounted) setState(() => _bytes = data);
  }

  @override
  Widget build(BuildContext context) {
    if (_bytes == null) {
      return ColoredBox(
        color: context.colors.surfaceInput,
        child: const Center(
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }
    return Image.memory(
      _bytes!,
      fit: widget.fit,
      alignment: widget.alignment,
      gaplessPlayback: true,
    );
  }
}
