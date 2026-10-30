import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:video_player/video_player.dart';

import '../theme/palette.dart';

/// Plays a gallery video muted and looped, cover-fitted like a slot photo.
class VideoSlot extends StatefulWidget {
  const VideoSlot({
    super.key,
    required this.assetId,
    this.fit = BoxFit.cover,
    this.alignment = Alignment.center,
  });

  final String assetId;
  final BoxFit fit;
  final Alignment alignment;

  @override
  State<VideoSlot> createState() => _VideoSlotState();
}

class _VideoSlotState extends State<VideoSlot> {
  VideoPlayerController? _video;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(VideoSlot old) {
    super.didUpdateWidget(old);
    if (old.assetId != widget.assetId) {
      _video?.dispose();
      _video = null;
      _load();
    }
  }

  Future<void> _load() async {
    final id = widget.assetId;
    final asset = await AssetEntity.fromId(id);
    final file = await asset?.file;
    if (file == null || !mounted || id != widget.assetId) return;
    final v = VideoPlayerController.file(file);
    try {
      await v.initialize();
      await v.setLooping(true);
      await v.setVolume(0);
      await v.play();
    } catch (_) {
      await v.dispose();
      return;
    }
    if (!mounted || id != widget.assetId) {
      await v.dispose();
      return;
    }
    setState(() => _video = v);
  }

  @override
  void dispose() {
    _video?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final v = _video;
    if (v == null || !v.value.isInitialized) {
      return ColoredBox(
        color: context.colors.surfaceInput,
        child: const Center(
          child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
        ),
      );
    }
    return ClipRect(
      child: FittedBox(
        fit: widget.fit,
        alignment: widget.alignment,
        child: SizedBox(
          width: v.value.size.width,
          height: v.value.size.height,
          child: VideoPlayer(v),
        ),
      ),
    );
  }
}
