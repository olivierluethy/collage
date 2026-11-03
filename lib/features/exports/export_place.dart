import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../../models/export_record.dart';
import '../../services/export_destination_service.dart';
import '../../services/export_service.dart';
import '../../state/exports.dart';
import '../../theme/palette.dart';
import '../../theme/tokens.dart';
import '../../theme/typography.dart';
import '../../widgets/ui.dart';

bool get _ios => !kIsWeb && Platform.isIOS;

/// "Pictures/Collage" → "Pictures › Collage": reads as a place, not a path.
String _crumbs(String path) => path.split('/').where((s) => s.isNotEmpty).join(' › ');

/// Where a saved file is, in words people recognise: "Gallery › Pictures ›
/// Collage", "Files › Download › Collage", "Google Drive › Prints", …
String exportPlaceLabel(AppLocalizations l, ExportTarget target, String label) => switch (target) {
      ExportTarget.gallery => label.isEmpty
          ? l.t('expPlacePhotos')
          : l.a('expPlaceGallery', {'path': _crumbs(label)}),
      ExportTarget.downloads => l.a('expPlaceFiles', {'path': _crumbs(label)}),
      ExportTarget.folder => label.isEmpty ? l.t('expPlaceFolder') : _crumbs(label),
      ExportTarget.picked => label.isEmpty ? l.t('expPlacePicked') : _crumbs(label),
      ExportTarget.appFiles => l.t('expPlaceAppFiles'),
    };

/// Icon for a place.
IconData exportPlaceIcon(ExportTarget t) => switch (t) {
      ExportTarget.gallery => Icons.photo_library_outlined,
      ExportTarget.downloads => Icons.download_rounded,
      ExportTarget.folder => Icons.folder_outlined,
      ExportTarget.picked => Icons.save_as_outlined,
      ExportTarget.appFiles => Icons.folder_outlined,
    };

/// The default destination in one line, for settings rows and the Save sheet.
String destinationSummary(AppLocalizations l, ExportDestination d) => switch (d.mode) {
      ExportDestinationMode.system => _ios ? l.t('expDestSystemSummaryIos') : l.t('expDestSystemSummary'),
      ExportDestinationMode.folder =>
        d.folderLabel?.isNotEmpty == true ? _crumbs(d.folderLabel!) : l.t('expPlaceFolder'),
      ExportDestinationMode.ask => l.t('expDestAsk'),
    };

/// Where *this* export will go, for the Save sheet ("Gallery › Pictures ›
/// Collage", "Files › Download › Collage", "Ask where to save").
String destinationFor(AppLocalizations l, ExportDestination d, ExportDestinationService svc, ExportFormat f) {
  final target = svc.targetFor(d, f);
  return switch (target) {
    ExportTarget.gallery => _ios ? l.t('expPlacePhotos') : exportPlaceLabel(l, target, 'Pictures/Collage'),
    ExportTarget.downloads => exportPlaceLabel(l, target, 'Download/Collage'),
    ExportTarget.folder => destinationSummary(l, d),
    ExportTarget.picked => l.t('expDestAsk'),
    ExportTarget.appFiles => l.t('expPlaceAppFiles'),
  };
}

/// Button label that says what Save will do for [f].
String saveButtonLabel(AppLocalizations l, ExportDestination d, ExportDestinationService svc, ExportFormat f) =>
    switch (svc.targetFor(d, f)) {
      ExportTarget.gallery => l.t('saveToGallery'),
      ExportTarget.downloads => l.t('expSaveToDownloads'),
      ExportTarget.folder => l.t('expSaveToFolder'),
      ExportTarget.picked => l.t('expSaveAs'),
      ExportTarget.appFiles => l.t('expSaveToFiles'),
    };

/// Bottom sheet to change the default destination. Shared by Settings and
/// the Save sheet, so the choice is the same thing wherever it is made.
Future<void> showDestinationSheet(BuildContext context, WidgetRef ref) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (_) => const SafeArea(child: SingleChildScrollView(child: DestinationChooser(padded: true))),
  );
}

/// The three destination choices with plain explanations. Used in a sheet
/// and on the Saving & export screen.
class DestinationChooser extends ConsumerStatefulWidget {
  const DestinationChooser({super.key, this.padded = false});
  final bool padded;

  @override
  ConsumerState<DestinationChooser> createState() => _DestinationChooserState();
}

class _DestinationChooserState extends ConsumerState<DestinationChooser> {
  bool _busy = false;

  Future<void> _chooseFolder() async {
    final l = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    final ok = await ref.read(exportDestinationProvider.notifier).chooseFolder();
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) {
      final d = ref.read(exportDestinationProvider);
      showAppSnackOn(messenger, l.a('expFolderSet', {'folder': destinationSummary(l, d)}), kind: SnackKind.success);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final c = context.colors;
    final d = ref.watch(exportDestinationProvider);
    final svc = ref.read(exportDestinationServiceProvider);
    final notifier = ref.read(exportDestinationProvider.notifier);
    final folderLost = ref.watch(folderUsableProvider).valueOrNull == false;

    Widget option({
      required ExportDestinationMode mode,
      required IconData icon,
      required String title,
      required String body,
      Widget? extra,
      VoidCallback? onTap,
    }) {
      final selected = d.mode == mode;
      return Semantics(
        selected: selected,
        inMutuallyExclusiveGroup: true,
        button: true,
        child: InkWell(
          onTap: _busy ? null : (onTap ?? () => notifier.setMode(mode)),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: Space.lg, vertical: Space.md),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Icon(icon, color: selected ? c.amber : c.textMid),
                ),
                const SizedBox(width: Space.lg),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: context.text.bodyLg),
                      const SizedBox(height: 2),
                      Text(body, style: context.text.caption.copyWith(color: c.textMid)),
                      ?extra,
                    ],
                  ),
                ),
                const SizedBox(width: Space.sm),
                ExcludeSemantics(
                  child: Icon(
                    selected ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded,
                    color: selected ? c.amber : c.textLo,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final folderExtra = !svc.canPickFolder
        ? null
        : Padding(
            padding: const EdgeInsets.only(top: Space.sm),
            child: Wrap(
              spacing: Space.sm,
              runSpacing: Space.xs,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (d.hasFolder)
                  Text(
                    destinationSummary(
                      l,
                      ExportDestination(
                        mode: ExportDestinationMode.folder,
                        folderUri: d.folderUri,
                        folderLabel: d.folderLabel,
                      ),
                    ),
                    style: context.text.labelMd.copyWith(
                      color: d.mode == ExportDestinationMode.folder ? c.amber : c.textMid,
                    ),
                  ),
                if (folderLost)
                  Semantics(
                    liveRegion: true,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.error_outline_rounded, size: 16, color: c.danger),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(l.t('expFolderLost'), style: context.text.caption.copyWith(color: c.danger)),
                        ),
                      ],
                    ),
                  ),
                TextButton.icon(
                  onPressed: _busy ? null : _chooseFolder,
                  icon: const Icon(Icons.drive_folder_upload_outlined, size: 18),
                  label: Text(folderLost
                      ? l.t('expChooseFolderAgain')
                      : d.hasFolder
                          ? l.t('expChangeFolder')
                          : l.t('expChooseFolder')),
                ),
              ],
            ),
          );

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.padded) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.xl, 0, Space.xl, Space.xs),
            child: Text(l.t('expDestTitle'), style: context.text.titleMd),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.xl, 0, Space.xl, Space.sm),
            child: Text(l.t('expDestIntro'), style: context.text.bodyMd.copyWith(color: c.textMid)),
          ),
        ],
        option(
          mode: ExportDestinationMode.system,
          icon: Icons.verified_outlined,
          title: l.t('expDestSystem'),
          body: _ios ? l.t('expDestSystemHintIos') : l.t('expDestSystemHint'),
        ),
        if (svc.canPickFolder)
          option(
            mode: ExportDestinationMode.folder,
            icon: Icons.folder_outlined,
            title: l.t('expDestFolder'),
            body: l.t('expDestFolderHint'),
            extra: folderExtra,
            onTap: d.hasFolder ? null : _chooseFolder,
          ),
        option(
          mode: ExportDestinationMode.ask,
          icon: Icons.save_as_outlined,
          title: l.t('expDestAsk'),
          body: _ios ? l.t('expDestAskHintIos') : l.t('expDestAskHint'),
        ),
        if (_ios)
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.xl, Space.sm, Space.xl, Space.md),
            child: Text(l.t('expIosFolderNote'), style: context.text.caption.copyWith(color: c.textLo)),
          ),
        if (d.mode == ExportDestinationMode.folder || d.hasFolder)
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: Space.md),
              child: TextButton.icon(
                onPressed: _busy
                    ? null
                    : () async {
                        await notifier.reset();
                        if (context.mounted) showAppSnack(context, l.t('expDestResetDone'), kind: SnackKind.success);
                      },
                icon: const Icon(Icons.restart_alt_rounded, size: 18),
                label: Text(l.t('expDestReset')),
              ),
            ),
          ),
        const SizedBox(height: Space.sm),
      ],
    );
  }
}

/// Short "x min ago"/date line for an export.
String exportWhen(BuildContext context, DateTime at) {
  final loc = MaterialLocalizations.of(context);
  final now = DateTime.now();
  final time = loc.formatTimeOfDay(TimeOfDay.fromDateTime(at),
      alwaysUse24HourFormat: MediaQuery.of(context).alwaysUse24HourFormat);
  final sameDay = now.year == at.year && now.month == at.month && now.day == at.day;
  if (sameDay) return context.l10n.a('expToday', {'time': time});
  return '${loc.formatMediumDate(at)}, $time';
}

/// A message for a failed save, in the interface's voice: what happened and
/// what to do.
String exportFailureText(AppLocalizations l, ExportFailure f, {String? folder}) => switch (f) {
      ExportFailure.cancelled => l.t('expFailCancelled'),
      ExportFailure.folderUnavailable => l.a('expFailFolder', {'folder': folder ?? l.t('expPlaceFolder')}),
      ExportFailure.noSpace => l.t('expFailNoSpace'),
      ExportFailure.galleryDenied => l.t('expFailGallery'),
      ExportFailure.failed => l.t('expFailGeneric'),
    };
