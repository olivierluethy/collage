import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../services/export_service.dart';
import '../../theme/tokens.dart';
import '../../theme/typography.dart';
import '../../widgets/ui.dart';

/// Ask how to export: format (PNG / JPG, or animated GIF when [allowGif])
/// and output width, both pre-set to the last choice so most people just tap
/// the button. Resolves to null if the user dismisses the sheet.
Future<ExportOptions?> showExportSheet(
  BuildContext context,
  ExportOptions initial, {
  bool allowGif = false,
  bool allowVideo = false,
}) {
  return showModalBottomSheet<ExportOptions>(
    context: context,
    showDragHandle: true,
    builder: (_) => _ExportSheet(
      // A remembered GIF choice doesn't apply to a collage without GIFs.
      initial: (!allowGif && initial.format == ExportFormat.gif) ||
              (!allowVideo && initial.format == ExportFormat.mp4)
          ? initial.copyWith(format: ExportFormat.png)
          : initial,
      allowGif: allowGif,
      allowVideo: allowVideo,
    ),
  );
}

class _ExportSheet extends StatefulWidget {
  const _ExportSheet({required this.initial, required this.allowGif, required this.allowVideo});
  final ExportOptions initial;
  final bool allowGif;
  final bool allowVideo;

  @override
  State<_ExportSheet> createState() => _ExportSheetState();
}

class _ExportSheetState extends State<_ExportSheet> {
  late ExportOptions _o = widget.initial;

  String _sizeLabel(BuildContext context, ExportSize s) => switch (s) {
        ExportSize.small => context.l10n.t('exportSizeSmall'),
        ExportSize.standard => context.l10n.t('exportSizeStandard'),
        ExportSize.large => context.l10n.t('exportSizeLarge'),
      };

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(Space.lg, 0, Space.lg, Space.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(l.t('exportTitle'), style: context.text.titleMd),
            const SizedBox(height: Space.md),
            Text(l.t('exportFormat'), style: context.text.labelMd),
            const SizedBox(height: Space.xs),
            SegmentedButton<ExportFormat>(
              segments: [
                ButtonSegment(value: ExportFormat.png, label: const Text('PNG'), tooltip: l.t('exportPngHint')),
                ButtonSegment(value: ExportFormat.jpg, label: const Text('JPG'), tooltip: l.t('exportJpgHint')),
                if (widget.allowGif)
                  ButtonSegment(value: ExportFormat.gif, label: const Text('GIF'), tooltip: l.t('exportGifHint')),
                if (widget.allowVideo)
                  ButtonSegment(value: ExportFormat.mp4, label: const Text('MP4'), tooltip: l.t('exportMp4Hint')),
                ButtonSegment(value: ExportFormat.pdf, label: const Text('PDF'), tooltip: l.t('exportPdfHint')),
              ],
              selected: {_o.format},
              onSelectionChanged: (s) => setState(() => _o = _o.copyWith(format: s.first)),
            ),
            const SizedBox(height: Space.xs),
            Text(
              switch (_o.format) {
                ExportFormat.png => l.t('exportPngHint'),
                ExportFormat.jpg => l.t('exportJpgHint'),
                ExportFormat.gif => l.t('exportGifHint'),
                ExportFormat.pdf => l.t('exportPdfHint'),
                ExportFormat.mp4 => l.t('exportMp4Hint'),
              },
              style: context.text.caption,
            ),
            const SizedBox(height: Space.md),
            Text(l.t('exportSize'), style: context.text.labelMd),
            const SizedBox(height: Space.xs),
            SegmentedButton<ExportSize>(
              segments: [
                for (final s in ExportSize.values)
                  ButtonSegment(value: s, label: Text('${_sizeLabel(context, s)}\n${s.width.toInt()} px', textAlign: TextAlign.center)),
              ],
              selected: {_o.size},
              onSelectionChanged: (s) => setState(() => _o = _o.copyWith(size: s.first)),
            ),
            const SizedBox(height: Space.xs),
            Text(
              switch (_o.size) {
                ExportSize.small => l.t('exportSizeSmallHint'),
                ExportSize.standard => l.t('exportSizeStandardHint'),
                ExportSize.large => l.t('exportSizeLargeHint'),
              },
              style: context.text.caption,
            ),
            const SizedBox(height: Space.xl),
            // Says what happens: images and videos go straight to the gallery;
            // a PDF is created and then offered to save or share.
            PrimaryButton(
              onPressed: () => Navigator.of(context).pop(_o),
              icon: _o.format == ExportFormat.pdf ? Icons.picture_as_pdf_outlined : Icons.download_rounded,
              label: _o.format == ExportFormat.pdf ? l.t('createPdf') : l.t('saveToGallery'),
            ),
          ],
        ),
      ),
    );
  }
}
