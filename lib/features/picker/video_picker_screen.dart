import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';

import '../../l10n/app_localizations.dart';
import '../../theme/palette.dart';
import '../../theme/tokens.dart';
import '../../theme/typography.dart';
import '../../widgets/photo_image.dart';

/// Pick one video from the gallery (newest first). Pops with its asset id.
class VideoPickerScreen extends StatefulWidget {
  const VideoPickerScreen({super.key});

  @override
  State<VideoPickerScreen> createState() => _VideoPickerScreenState();
}

class _VideoPickerScreenState extends State<VideoPickerScreen> {
  List<AssetEntity>? _videos;
  bool _denied = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final perm = await PhotoManager.requestPermissionExtend(
      requestOption: const PermissionRequestOption(
        androidPermission: AndroidPermission(type: RequestType.video, mediaLocation: false),
      ),
    );
    if (!perm.hasAccess) {
      if (mounted) setState(() => _denied = true);
      return;
    }
    final paths = await PhotoManager.getAssetPathList(type: RequestType.video, onlyAll: true);
    final videos = paths.isEmpty ? <AssetEntity>[] : await paths.first.getAssetListPaged(page: 0, size: 120);
    if (mounted) setState(() => _videos = videos);
  }

  static String _duration(int seconds) =>
      '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final videos = _videos;
    return Scaffold(
      appBar: AppBar(title: Text(context.l10n.t('chooseVideo'))),
      body: _denied
          ? Center(child: Text(context.l10n.t('videoAccessDenied'), style: context.text.bodyMd))
          : videos == null
              ? const Center(child: CircularProgressIndicator())
              : videos.isEmpty
                  ? Center(child: Text(context.l10n.t('noVideos'), style: context.text.bodyMd))
                  : GridView.builder(
                      padding: const EdgeInsets.all(Space.sm),
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 3,
                        mainAxisSpacing: 4,
                        crossAxisSpacing: 4,
                      ),
                      itemCount: videos.length,
                      itemBuilder: (_, i) {
                        final v = videos[i];
                        return GestureDetector(
                          onTap: () => Navigator.of(context).pop(v.id),
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              PhotoImage(assetId: v.id, fit: BoxFit.cover),
                              Positioned(
                                right: 4,
                                bottom: 4,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: Colors.black.withValues(alpha: 0.6),
                                    borderRadius: BorderRadius.circular(Radii.pill),
                                  ),
                                  child: Text(
                                    _duration(v.duration),
                                    style: context.text.caption.copyWith(color: Colors.white),
                                  ),
                                ),
                              ),
                              Center(child: Icon(Icons.play_circle_outline_rounded, color: context.colors.onAmber.withValues(alpha: 0.9))),
                            ],
                          ),
                        );
                      },
                    ),
    );
  }
}
