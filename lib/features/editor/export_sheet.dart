import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../services/export_service.dart';
import '../../theme/tokens.dart';
import '../../theme/typography.dart';

/// Ask how to export: format (PNG / JPG, or animated GIF when [allowGif])
/// and output width. Resolves to null if the user dismisses the sheet.
Future<ExportOptions?> showExportSheet(
  BuildContext context,
  ExportOptions initial, {
  bool allowGif = false,
}) {
  return showModalBottomSheet<ExportOptions>(
    context: context,
    showDragHandle: true,
    builder: (_) => _ExportSheet(
      // A remembered GIF choice doesn't apply to a collage without GIFs.
      initial: !allowGif && initial.format == ExportFormat.gif
          ? initial.copyWith(format: ExportFormat.png)
          : initial,
      allowGif: allowGif,
    ),
  );
}

class _ExportSheet extends StatefulWidget {
  const _ExportSheet({required this.initial, required this.allowGif});
  final ExportOptions initial;
  final bool allowGif;

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
            const SizedBox(height: Space.lg),
            FilledButton.icon(
              onPressed: () => Navigator.of(context).pop(_o),
              icon: const Icon(Icons.save_alt_rounded, size: 18),
              label: Text(l.t('save')),
            ),
          ],
        ),
      ),
    );
  }
}
