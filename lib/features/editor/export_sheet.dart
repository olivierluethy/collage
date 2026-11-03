import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../../models/export_record.dart';
import '../../services/export_service.dart';
import '../../state/exports.dart';
import '../../theme/palette.dart';
import '../../theme/tokens.dart';
import '../../theme/typography.dart';
import '../../widgets/ui.dart';
import '../exports/export_place.dart';

/// Ask how to export: format (PNG / JPG, or animated GIF when [allowGif])
/// and output width, both pre-set to the last choice so most people just tap
/// the button. The place the file will be saved is shown right above the
/// button and can be changed from here. Resolves to null if dismissed.
Future<ExportOptions?> showExportSheet(
  BuildContext context,
  ExportOptions initial, {
  bool allowGif = false,
  bool allowVideo = false,
}) {
  return showModalBottomSheet<ExportOptions>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
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

class _ExportSheet extends ConsumerStatefulWidget {
  const _ExportSheet({required this.initial, required this.allowGif, required this.allowVideo});
  final ExportOptions initial;
  final bool allowGif;
  final bool allowVideo;

  @override
  ConsumerState<_ExportSheet> createState() => _ExportSheetState();
}

class _ExportSheetState extends ConsumerState<_ExportSheet> {
  late ExportOptions _o = widget.initial;

  String _sizeLabel(BuildContext context, ExportSize s) => switch (s) {
        ExportSize.small => context.l10n.t('exportSizeSmall'),
        ExportSize.standard => context.l10n.t('exportSizeStandard'),
        ExportSize.large => context.l10n.t('exportSizeLarge'),
      };

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final c = context.colors;
    final dest = ref.watch(exportDestinationProvider);
    final svc = ref.read(exportDestinationServiceProvider);
    final folderLost = dest.mode == ExportDestinationMode.folder &&
        ref.watch(folderUsableProvider).valueOrNull == false;
    return SafeArea(
      child: SingleChildScrollView(
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
            const SizedBox(height: Space.lg),
            // Where the file will go, visible before saving — not hidden in
            // Settings. Tapping it changes the default destination.
            Material(
              color: c.surfaceHigh,
              borderRadius: BorderRadius.circular(Radii.control),
              child: InkWell(
                borderRadius: BorderRadius.circular(Radii.control),
                onTap: () => showDestinationSheet(context, ref),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: Sizes.touchTarget),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: Space.md, vertical: Space.sm),
                    child: Row(
                      children: [
                        Icon(
                          folderLost ? Icons.error_outline_rounded : exportPlaceIcon(svc.targetFor(dest, _o.format)),
                          size: 20,
                          color: folderLost ? c.danger : c.amber,
                        ),
                        const SizedBox(width: Space.md),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(l.t('expSavesTo'), style: context.text.caption.copyWith(color: c.textMid)),
                              Text(destinationFor(l, dest, svc, _o.format), style: context.text.bodyMd),
                              if (folderLost)
                                Text(l.t('expFolderLostShort'),
                                    style: context.text.caption.copyWith(color: c.danger)),
                            ],
                          ),
                        ),
                        Text(l.t('expChange'), style: context.text.labelMd.copyWith(color: c.amber)),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: Space.md),
            // Says what happens and where.
            PrimaryButton(
              onPressed: () => Navigator.of(context).pop(_o),
              icon: _o.format == ExportFormat.pdf ? Icons.picture_as_pdf_outlined : Icons.download_rounded,
              label: saveButtonLabel(l, dest, svc, _o.format),
            ),
          ],
        ),
      ),
    );
  }
}
