import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../l10n/app_localizations.dart';
import '../../models/collage_project.dart';
import '../../services/export_service.dart';
import '../../state/providers.dart';
import '../../theme/palette.dart';
import '../../theme/tokens.dart';
import '../../theme/typography.dart';
import '../../widgets/meta_date.dart';
import '../../widgets/ui.dart';

/// Shown right after Save: a clear preview of the finished collage with obvious
/// Save-to-gallery, Share and keep-editing actions.
class ResultScreen extends ConsumerStatefulWidget {
  const ResultScreen({super.key, required this.project, required this.result});
  final CollageProject project;
  final ExportResult result;

  Uint8List get bytes => result.bytes;

  @override
  ConsumerState<ResultScreen> createState() => _ResultScreenState();
}

class _ResultScreenState extends ConsumerState<ResultScreen> {
  bool _saved = false;
  bool _busy = false;

  Future<void> _saveToGallery() async {
    final format = widget.result.format;
    // A PDF can't live in the gallery: hand it to the share sheet, where
    // "Save to Files" / Drive are offered.
    if (format == ExportFormat.pdf) return _share();
    setState(() => _busy = true);
    final gallery = ref.read(galleryServiceProvider);
    final filename = 'collage_${DateTime.now().millisecondsSinceEpoch}.${format.extension}';
    final asset = format == ExportFormat.mp4
        ? await gallery.saveVideo(widget.bytes, filename: filename)
        : await gallery.saveImage(widget.bytes, filename: filename);
    setState(() {
      _busy = false;
      _saved = asset != null;
    });
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(asset != null
          ? context.l10n.t('savedToGallery')
          : context.l10n.t('couldNotSave')),
    ));
  }

  Future<void> _share() async {
    final l = context.l10n;
    final dir = await getTemporaryDirectory();
    final format = widget.result.format;
    final file = File('${dir.path}/collage_share.${format.extension}');
    await file.writeAsBytes(widget.bytes);
    await SharePlus.instance.share(
      ShareParams(files: [XFile(file.path, mimeType: format.mimeType)], text: l.t('madeWithCollage')),
    );
  }

  bool get _isStill =>
      widget.result.format == ExportFormat.png || widget.result.format == ExportFormat.jpg;

  /// Number of square slides this collage splits into (1 = no carousel).
  int get _slides => _isStill ? widget.project.ratio.carouselSlides : 1;

  /// Rows of a 3-wide Instagram profile grid that fit this collage (0 = none).
  int get _gridRows {
    if (!_isStill || _slides > 1) return 0;
    final rows = (3 / widget.project.ratio.value).round();
    return rows >= 2 && rows <= 5 ? rows : 0;
  }

  /// Cut the export into a 3-wide profile grid and save the tiles in the
  /// order they have to be posted.
  Future<void> _grid() async {
    final l = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      final bytes = widget.bytes;
      final rows = _gridRows;
      final format = widget.result.format;
      final tiles = await Isolate.run(() => splitGrid(bytes, rows, 3, format));
      final stamp = DateTime.now().millisecondsSinceEpoch;
      var ok = 0;
      for (var i = 0; i < tiles.length; i++) {
        final a = await ref.read(galleryServiceProvider).saveImage(
              tiles[i],
              filename: 'collage_${stamp}_post${i + 1}.${format.extension}',
            );
        if (a != null) ok++;
      }
      messenger.showSnackBar(SnackBar(
        duration: const Duration(seconds: 6),
        content: Text(ok == tiles.length ? l.a('gridSaved', {'count': '$ok'}) : l.t('couldNotSave')),
      ));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Cut the export into its carousel slides, then save them to the gallery
  /// in posting order, or share them all at once.
  Future<void> _carousel({required bool share}) async {
    final l = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      final bytes = widget.bytes;
      final slides = _slides;
      final format = widget.result.format;
      final pieces = await Isolate.run(() => splitCarousel(bytes, slides, format));
      if (share) {
        final dir = await getTemporaryDirectory();
        final files = <XFile>[];
        for (var i = 0; i < pieces.length; i++) {
          final f = File('${dir.path}/collage_slide_${i + 1}.${format.extension}');
          await f.writeAsBytes(pieces[i]);
          files.add(XFile(f.path, mimeType: format.mimeType));
        }
        await SharePlus.instance.share(ShareParams(files: files, text: l.t('madeWithCollage')));
      } else {
        final stamp = DateTime.now().millisecondsSinceEpoch;
        var ok = 0;
        for (var i = 0; i < pieces.length; i++) {
          final a = await ref.read(galleryServiceProvider).saveImage(
                pieces[i],
                filename: 'collage_${stamp}_${i + 1}.${format.extension}',
              );
          if (a != null) ok++;
        }
        messenger.showSnackBar(SnackBar(
          content: Text(ok == pieces.length ? l.a('carouselSaved', {'count': '$ok'}) : l.t('couldNotSave')),
        ));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: const CloseButton(),
        title: Text(context.l10n.t('yourCollage')),
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
                    child: Image.memory(widget.result.preview, fit: BoxFit.contain),
                  ),
                ),
              ),
            ),
          ),
          Center(child: MetaDate(epochMillis: widget.project.createdAt, icon: Icons.schedule_rounded)),
          const SizedBox(height: Space.sm),
          if (_saved)
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.check_circle_rounded, color: context.colors.success, size: 18),
                const SizedBox(width: 6),
                Text(context.l10n.t('savedToGallery'),
                    style: context.text.bodyMd.copyWith(color: context.colors.success)),
              ],
            ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(Space.lg),
              child: Column(
                children: [
                  PrimaryButton(
                    label: _saved
                        ? context.l10n.t('saved')
                        : widget.result.format == ExportFormat.pdf
                            ? context.l10n.t('savePdf')
                            : context.l10n.t('saveToGallery'),
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
                          label: Text(context.l10n.t('share')),
                        ),
                      ),
                      const SizedBox(width: Space.sm),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => Navigator.of(context).pop(),
                          icon: const Icon(Icons.edit_rounded, size: 18),
                          label: Text(context.l10n.t('keepEditing')),
                        ),
                      ),
                    ],
                  ),
                  if (_gridRows > 0) ...[
                    const SizedBox(height: Space.sm),
                    OutlinedButton.icon(
                      onPressed: _busy ? null : _grid,
                      icon: const Icon(Icons.grid_on_rounded, size: 18),
                      label: Text(context.l10n.a('gridSave', {'rows': '$_gridRows'})),
                    ),
                  ],
                  if (_slides > 1) ...[
                    const SizedBox(height: Space.sm),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _busy ? null : () => _carousel(share: false),
                            icon: const Icon(Icons.view_carousel_outlined, size: 18),
                            label: Text(context.l10n.a('carouselSave', {'count': '$_slides'})),
                          ),
                        ),
                        const SizedBox(width: Space.sm),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _busy ? null : () => _carousel(share: true),
                            icon: const Icon(Icons.ios_share_rounded, size: 18),
                            label: Text(context.l10n.t('carouselShare')),
                          ),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: Space.sm),
                  TextButton(
                    onPressed: () => Navigator.of(context).popUntil((r) => r.isFirst),
                    child: Text(context.l10n.t('done')),
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
