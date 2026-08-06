import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../models/collage_project.dart';
import '../../state/providers.dart';
import '../../theme/text_styles.dart';
import '../../theme/tokens.dart';
import '../../widgets/ui.dart';

/// Shown right after Save: a clear preview of the finished collage with obvious
/// Save-to-gallery, Share and keep-editing actions.
class ResultScreen extends ConsumerStatefulWidget {
  const ResultScreen({super.key, required this.project, required this.png});
  final CollageProject project;
  final Uint8List png;

  @override
  ConsumerState<ResultScreen> createState() => _ResultScreenState();
}

class _ResultScreenState extends ConsumerState<ResultScreen> {
  bool _saved = false;
  bool _busy = false;

  Future<void> _saveToGallery() async {
    setState(() => _busy = true);
    final asset = await ref.read(galleryServiceProvider).savePng(
          widget.png,
          filename: 'collage_${DateTime.now().millisecondsSinceEpoch}.png',
        );
    setState(() {
      _busy = false;
      _saved = asset != null;
    });
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(asset != null
          ? 'Saved to your gallery.'
          : 'Could not save — check photo permissions.'),
    ));
  }

  Future<void> _share() async {
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/collage_share.png');
    await file.writeAsBytes(widget.png);
    await SharePlus.instance.share(
      ShareParams(files: [XFile(file.path)], text: 'Made with Collage'),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: const CloseButton(),
        title: const Text('Your collage'),
      ),
      body: Column(
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(Space.xl),
              child: Center(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(Radii.card),
                    boxShadow: Shadows.e3,
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(Radii.card),
                    child: Image.memory(widget.png, fit: BoxFit.contain),
                  ),
                ),
              ),
            ),
          ),
          if (_saved)
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.check_circle_rounded, color: AppColors.success, size: 18),
                const SizedBox(width: 6),
                Text('Saved to your gallery', style: AppText.bodyMd.copyWith(color: AppColors.success)),
              ],
            ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(Space.lg),
              child: Column(
                children: [
                  PrimaryButton(
                    label: _saved ? 'Saved' : 'Save to gallery',
                    icon: _saved ? Icons.check_rounded : Icons.download_rounded,
                    busy: _busy,
                    onPressed: _saved ? null : _saveToGallery,
                  ),
                  const SizedBox(height: Space.sm),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _share,
                          icon: const Icon(Icons.ios_share_rounded, size: 18),
                          label: const Text('Share'),
                        ),
                      ),
                      const SizedBox(width: Space.sm),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => Navigator.of(context).pop(),
                          icon: const Icon(Icons.edit_rounded, size: 18),
                          label: const Text('Keep editing'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: Space.sm),
                  TextButton(
                    onPressed: () => Navigator.of(context).popUntil((r) => r.isFirst),
                    child: const Text('Done'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
