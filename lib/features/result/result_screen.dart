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
import '../../widgets/ui.dart';

/// Shown right after "Save to gallery": the collage is already being saved
/// when this opens, so the screen confirms it and leads with the next likely
/// step — sharing. Instagram-specific exports sit in their own group.
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
  bool _failed = false;

  bool get _isPdf => widget.result.format == ExportFormat.pdf;

  @override
  void initState() {
    super.initState();
    // The user already chose "Save to gallery" — don't ask twice.
    if (!_isPdf) WidgetsBinding.instance.addPostFrameCallback((_) => _saveToGallery());
  }

  Future<void> _saveToGallery() async {
    final format = widget.result.format;
    // A PDF can't live in the gallery: hand it to the share sheet, where
    // "Save to Files" / Drive are offered.
    if (format == ExportFormat.pdf) return _share();
    setState(() {
      _busy = true;
      _failed = false;
    });
    final gallery = ref.read(galleryServiceProvider);
    final filename = 'collage_${DateTime.now().millisecondsSinceEpoch}.${format.extension}';
    final asset = format == ExportFormat.mp4
        ? await gallery.saveVideo(widget.bytes, filename: filename)
        : await gallery.saveImage(widget.bytes, filename: filename);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _saved = asset != null;
      _failed = asset == null;
    });
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
      if (mounted) {
        showAppSnack(
          context,
          ok == tiles.length ? l.a('gridSaved', {'count': '$ok'}) : l.t('couldNotSave'),
          kind: ok == tiles.length ? SnackKind.success : SnackKind.error,
          duration: const Duration(seconds: 6),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Cut the export into its carousel slides, then save them to the gallery
  /// in posting order, or share them all at once.
  Future<void> _carousel({required bool share}) async {
    final l = context.l10n;
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
        if (mounted) {
          showAppSnack(
            context,
            ok == pieces.length ? l.a('carouselSaved', {'count': '$ok'}) : l.t('couldNotSave'),
            kind: ok == pieces.length ? SnackKind.success : SnackKind.error,
          );
        }
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final c = context.colors;
    final instagram = _gridRows > 0 || _slides > 1;
    return Scaffold(
      appBar: AppBar(
        leading: CloseButton(onPressed: () => Navigator.of(context).popUntil((r) => r.isFirst)),
        title: Text(l.t('yourCollage')),
      ),
      body: Column(
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(Space.xl, Space.lg, Space.xl, Space.md),
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
          _StatusLine(
            saving: _busy && !_saved,
            saved: _saved,
            failed: _failed,
            pdf: _isPdf,
            onRetry: _saveToGallery,
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(Space.lg, Space.md, Space.lg, Space.sm),
              child: Column(
                children: [
                  PrimaryButton(
                    label: _isPdf ? l.t('savePdf') : l.t('share'),
                    icon: _isPdf ? Icons.picture_as_pdf_outlined : Icons.ios_share_rounded,
                    onPressed: _share,
                  ),
                  const SizedBox(height: Space.sm),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => Navigator.of(context).pop(),
                          icon: const Icon(Icons.edit_rounded, size: 18),
                          label: Text(l.t('keepEditing')),
                        ),
                      ),
                      const SizedBox(width: Space.sm),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => Navigator.of(context).popUntil((r) => r.isFirst),
                          icon: const Icon(Icons.check_rounded, size: 18),
                          label: Text(l.t('done')),
                        ),
                      ),
                    ],
                  ),
                  if (instagram) ...[
                    const SizedBox(height: Space.sm),
                    Theme(
                      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                      child: ExpansionTile(
                        tilePadding: const EdgeInsets.symmetric(horizontal: Space.sm),
                        leading: Icon(Icons.grid_on_rounded, color: c.textMid),
                        title: Text(l.t('forInstagram'), style: context.text.labelLg),
                        subtitle: Text(
                          _slides > 1
                              ? l.a('carouselSave', {'count': '$_slides'})
                              : l.a('gridSave', {'rows': '$_gridRows'}),
                          style: context.text.caption.copyWith(color: c.textMid),
                        ),
                        childrenPadding: const EdgeInsets.only(bottom: Space.sm),
                        children: [
                          if (_gridRows > 0)
                            SizedBox(
                              width: double.infinity,
                              child: OutlinedButton.icon(
                                onPressed: _busy ? null : _grid,
                                icon: const Icon(Icons.grid_on_rounded, size: 18),
                                label: Text(l.a('gridSave', {'rows': '$_gridRows'})),
                              ),
                            ),
                          if (_slides > 1)
                            Row(
                              children: [
                                Expanded(
                                  child: OutlinedButton.icon(
                                    onPressed: _busy ? null : () => _carousel(share: false),
                                    icon: const Icon(Icons.view_carousel_outlined, size: 18),
                                    label: Text(l.a('carouselSave', {'count': '$_slides'})),
                                  ),
                                ),
                                const SizedBox(width: Space.sm),
                                Expanded(
                                  child: OutlinedButton.icon(
                                    onPressed: _busy ? null : () => _carousel(share: true),
                                    icon: const Icon(Icons.ios_share_rounded, size: 18),
                                    label: Text(l.t('carouselShare')),
                                  ),
                                ),
                              ],
                            ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// One line under the preview saying where the collage is: saving, saved, or
/// not saved (with a way to try again). PDFs aren't saved to the gallery, so
/// they get a hint about where to keep them instead.
class _StatusLine extends StatelessWidget {
  const _StatusLine({
    required this.saving,
    required this.saved,
    required this.failed,
    required this.pdf,
    required this.onRetry,
  });
  final bool saving;
  final bool saved;
  final bool failed;
  final bool pdf;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final l = context.l10n;
    final Widget child;
    if (pdf) {
      child = _row(context, Icons.info_outline_rounded, c.info, l.t('pdfHint'));
    } else if (saved) {
      child = _row(context, Icons.check_circle_rounded, c.success, l.t('savedToGallery'));
    } else if (failed) {
      child = Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.error_outline_rounded, color: c.danger, size: 18),
          const SizedBox(width: 6),
          Flexible(child: Text(l.t('couldNotSave'), style: context.text.bodyMd.copyWith(color: c.danger))),
          TextButton(onPressed: onRetry, child: Text(l.t('tryAgain'))),
        ],
      );
    } else {
      child = Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: c.amber)),
          const SizedBox(width: Space.sm),
          Text(l.t('savingToGallery'), style: context.text.bodyMd.copyWith(color: c.textMid)),
        ],
      );
    }
    return Semantics(
      liveRegion: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: Space.lg),
        child: SizedBox(height: Sizes.touchTarget, child: Center(child: child)),
      ),
    );
  }

  Widget _row(BuildContext context, IconData icon, Color color, String text) => Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 6),
          Flexible(child: Text(text, style: context.text.bodyMd.copyWith(color: color))),
        ],
      );
}
