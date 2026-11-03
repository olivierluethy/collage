import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';

import '../l10n/app_localizations.dart';
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

  // Least-recently-used caches (a LinkedHashMap keeps insertion order; a hit
  // is moved to the end). Bounded, so scrolling through thousands of photos
  // in Discover or the picker can't grow memory without limit. Widgets keep
  // their own bytes, so eviction never blanks a photo on screen.
  static final Map<String, Uint8List> _thumbCache = {};
  static final Map<String, Uint8List> _fullCache = {};
  static const _maxThumbs = 600;
  static const _maxFull = 24;

  /// Longest side, in pixels, a full-size photo is decoded at (the largest
  /// export width).
  static const maxDecodePx = 4096;

  /// Asset ids that no longer resolve (deleted, or outside limited access).
  static final Set<String> _missing = {};

  /// Whether [assetId] was looked up and could not be found.
  static bool isMissing(String assetId) => _missing.contains(assetId);

  static Uint8List? _hit(Map<String, Uint8List> cache, String id) {
    final v = cache.remove(id);
    if (v != null) cache[id] = v;
    return v;
  }

  static void _put(Map<String, Uint8List> cache, String id, Uint8List v, int max) {
    cache.remove(id);
    cache[id] = v;
    while (cache.length > max) {
      cache.remove(cache.keys.first);
    }
  }

  /// Best-available bytes for export/AI without building a widget. Null when
  /// the photo is gone from the library (see [isMissing]).
  static Future<Uint8List?> bytes(String assetId, {bool full = false, int thumbPx = 400}) async {
    final cache = full ? _fullCache : _thumbCache;
    final cached = _hit(cache, assetId);
    if (cached != null) return cached;
    final asset = await AssetEntity.fromId(assetId);
    if (asset == null) {
      _missing.add(assetId);
      return null;
    }
    _missing.remove(assetId);
    final data = full
        ? await asset.originBytes
        : await asset.thumbnailDataWithSize(ThumbnailSize.square(thumbPx));
    if (data != null) _put(cache, assetId, data, full ? _maxFull : _maxThumbs);
    return data;
  }

  @override
  State<PhotoImage> createState() => _PhotoImageState();
}

class _PhotoImageState extends State<PhotoImage> {
  Uint8List? _bytes;
  bool _missing = false;

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
    if (!mounted) return;
    setState(() {
      _bytes = data;
      _missing = data == null && PhotoImage.isMissing(widget.assetId);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_bytes == null && _missing) {
      // The photo was deleted or renamed away: say so instead of spinning.
      return Semantics(
        label: context.l10n.t('photoMissing'),
        child: ColoredBox(
          color: context.colors.surfaceInput,
          child: Center(
            child: Icon(Icons.broken_image_outlined, color: context.colors.textLo, size: 28),
          ),
        ),
      );
    }
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
    // Originals are decoded no larger than [maxDecodePx] on their long side.
    // A 48 MP camera photo otherwise becomes a ~190 MB texture per cell, and
    // every relayout (switching the canvas shape, dragging a cut) re-rasters
    // those — the stutter users saw. The cap is at the largest export width,
    // so saved collages look exactly as before.
    final ImageProvider provider = widget.full
        ? ResizeImage(
            MemoryImage(_bytes!),
            width: PhotoImage.maxDecodePx,
            height: PhotoImage.maxDecodePx,
            policy: ResizeImagePolicy.fit,
            allowUpscaling: false,
          )
        : MemoryImage(_bytes!);
    return Image(
      image: provider,
      fit: widget.fit,
      alignment: widget.alignment,
      gaplessPlayback: true,
    );
  }
}
