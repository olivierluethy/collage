import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:share_plus/share_plus.dart';

import '../../l10n/app_localizations.dart';
import '../../models/collage_project.dart';
import '../../models/export_record.dart';
import '../../services/export_destination_service.dart';
import '../../services/export_service.dart';
import '../../state/exports.dart';
import '../../state/occasions.dart';
import '../../state/reminders.dart';
import '../../theme/palette.dart';
import '../../theme/tokens.dart';
import '../../theme/typography.dart';
import '../../widgets/ui.dart';
import '../exports/export_history_screen.dart';
import '../exports/export_place.dart';

/// Shown right after Save: the export is written to the chosen destination
/// as this opens, and the screen then says exactly what was saved and where
/// — file name, format and place — with ways to open, find and share it.
/// Sharing is a separate action that sends a copy and saves nothing.
class ResultScreen extends ConsumerStatefulWidget {
  const ResultScreen({super.key, required this.project, required this.result, this.thumbnail});
  final CollageProject project;
  final ExportResult result;

  /// Small PNG of the collage for the export history.
  final Uint8List? thumbnail;

  Uint8List get bytes => result.bytes;

  @override
  ConsumerState<ResultScreen> createState() => _ResultScreenState();
}

enum _Phase { saving, saved, failed }

class _ResultScreenState extends ConsumerState<ResultScreen> {
  _Phase _phase = _Phase.saving;
  ExportRecord? _record;
  ExportFailure? _failure;
  ExportTarget? _failedTarget;
  bool _busy = false;

  ExportDestinationService get _svc => ref.read(exportDestinationServiceProvider);

  @override
  void initState() {
    super.initState();
    // The user already chose Save — don't ask twice.
    WidgetsBinding.instance.addPostFrameCallback((_) => _save());
  }

  /// Saves to [target], or to the default destination.
  Future<void> _save({ExportTarget? target}) async {
    setState(() {
      _phase = _Phase.saving;
      _failure = null;
    });
    final format = widget.result.format;
    try {
      final r = await ref.read(exportHistoryProvider.notifier).saveAndRecord(
            bytes: widget.bytes,
            format: format,
            projectId: widget.project.id,
            projectTitle: widget.project.title,
            thumbnail: widget.thumbnail ?? (format.isImage ? null : widget.result.previewBytes),
            target: target,
          );
      if (!mounted) return;
      setState(() {
        _record = r;
        _phase = _Phase.saved;
      });
      _notifyIfAway(r);
    } on ExportSaveException catch (e) {
      if (!mounted) return;
      setState(() {
        _failure = e.reason;
        _failedTarget = target ?? _svc.targetFor(ref.read(exportDestinationProvider), format);
        // A cancelled picker after an earlier save keeps showing that save.
        _phase = _record != null && e.reason == ExportFailure.cancelled ? _Phase.saved : _Phase.failed;
      });
      if (_record != null && e.reason != ExportFailure.cancelled) {
        showAppSnack(context, exportFailureText(context.l10n, e.reason), kind: SnackKind.error);
      }
    }
  }

  /// A long export (video) can finish while the app is in the background;
  /// when the user opted in, a notification says where it went.
  void _notifyIfAway(ExportRecord r) {
    final state = WidgetsBinding.instance.lifecycleState;
    if (state == null || state == AppLifecycleState.resumed) return;
    if (!ref.read(occasionPrefsProvider).notifyExports) return;
    final l = context.l10n;
    ref.read(reminderServiceProvider).showExportDone(
          l,
          fileName: r.fileName,
          place: exportPlaceLabel(l, r.target, r.locationLabel),
        );
  }

  Future<void> _share() async {
    final l = context.l10n;
    final dir = await getTemporaryDirectory();
    final format = widget.result.format;
    final file = File('${dir.path}/${exportFileName(widget.project.title, DateTime.now(), format.extension)}');
    await file.writeAsBytes(widget.bytes);
    await SharePlus.instance.share(
      ShareParams(files: [XFile(file.path, mimeType: format.mimeType)], text: l.t('madeWithCollage')),
    );
  }

  Future<void> _chooseFolderAndSave() async {
    final ok = await ref.read(exportDestinationProvider.notifier).chooseFolder();
    if (ok && mounted) await _save(target: ExportTarget.folder);
  }

  /// "Save another copy": the same export to another place, once.
  Future<void> _saveCopy() async {
    final l = context.l10n;
    final d = ref.read(exportDestinationProvider);
    final format = widget.result.format;
    final system = _svc.systemTargetFor(format);
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (sheet) {
        final c = sheet.colors;
        Widget tile(String id, IconData icon, String title, String sub) => ListTile(
              minTileHeight: Sizes.touchTarget,
              leading: Icon(icon, color: c.textMid),
              title: Text(title),
              subtitle: Text(sub),
              onTap: () => Navigator.pop(sheet, id),
            );
        return SafeArea(
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(Space.xl, 0, Space.xl, Space.sm),
                  child: Text(l.t('expSaveCopy'), style: sheet.text.titleMd),
                ),
                tile('system', exportPlaceIcon(system), l.t('expDestSystem'),
                    destinationFor(l, const ExportDestination(), _svc, format)),
                if (_svc.canPickFolder && d.hasFolder)
                  tile('folder', Icons.folder_outlined, l.t('expDestFolder'), destinationSummary(l, d)),
                if (_svc.canPickFolder)
                  tile('pick', Icons.drive_folder_upload_outlined, l.t('expChooseFolder'), l.t('expChooseFolderHint')),
                tile('ask', Icons.save_as_outlined, l.t('expSaveAs'), l.t('expSaveAsHint')),
              ],
            ),
          ),
        );
      },
    );
    if (!mounted || choice == null) return;
    switch (choice) {
      case 'system':
        await _save(target: system);
      case 'folder':
        await _save(target: ExportTarget.folder);
      case 'pick':
        await _chooseFolderAndSave();
      case 'ask':
        await _save(target: ExportTarget.picked);
    }
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

  /// Where split pieces go: the picked folder when that is the default, else
  /// the gallery (a Save-as dialog per slide would be tiring).
  ExportTarget get _piecesTarget {
    final d = ref.read(exportDestinationProvider);
    return d.mode == ExportDestinationMode.folder && d.hasFolder ? ExportTarget.folder : ExportTarget.gallery;
  }

  /// Saves [pieces] (posting order) and records them as one export.
  Future<void> _savePieces(List<Uint8List> pieces, String kind, String successKey) async {
    final l = context.l10n;
    final format = widget.result.format;
    final d = ref.read(exportDestinationProvider);
    final target = _piecesTarget;
    final now = DateTime.now();
    SavedFile? first;
    var ok = 0;
    ExportFailure? failure;
    for (var i = 0; i < pieces.length; i++) {
      try {
        final s = await _svc.save(
          bytes: pieces[i],
          format: format,
          fileName: exportFileName(widget.project.title, now, format.extension, suffix: '$kind ${i + 1}'),
          target: target,
          folderUri: d.folderUri,
          folderLabel: d.folderLabel,
        );
        first ??= s;
        ok++;
      } on ExportSaveException catch (e) {
        failure = e.reason;
        break;
      }
    }
    if (first != null) {
      await ref.read(exportHistoryProvider.notifier).record(
            saved: first,
            format: format,
            projectId: widget.project.id,
            projectTitle: widget.project.title,
            thumbnail: widget.thumbnail,
            count: ok,
            at: now,
          );
    }
    if (!mounted) return;
    if (ok == pieces.length && first != null) {
      showAppSnack(
        context,
        '${l.a(successKey, {'count': '$ok'})}\n${exportPlaceLabel(l, first.target, first.label)}',
        kind: SnackKind.success,
        duration: const Duration(seconds: 6),
      );
    } else {
      showAppSnack(context, exportFailureText(l, failure ?? ExportFailure.failed), kind: SnackKind.error);
    }
  }

  Future<void> _grid() async {
    setState(() => _busy = true);
    try {
      final bytes = widget.bytes;
      final rows = _gridRows;
      final format = widget.result.format;
      final tiles = await Isolate.run(() => splitGrid(bytes, rows, 3, format));
      await _savePieces(tiles, 'post', 'gridSaved');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Cut the export into its carousel slides, then save them in posting
  /// order, or share them all at once.
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
        await _savePieces(pieces, 'slide', 'carouselSaved');
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
        actions: [
          IconButton(
            tooltip: l.t('expHistoryTitle'),
            icon: const Icon(Icons.history_rounded),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => ExportHistoryScreen(projectId: widget.project.id, projectTitle: widget.project.title),
            )),
          ),
        ],
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
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Space.lg),
            child: _SaveCard(
              phase: _phase,
              record: _record,
              failure: _failure,
              failedTarget: _failedTarget,
              format: widget.result.format,
              folderLabel: ref.watch(exportDestinationProvider).folderLabel,
              svc: _svc,
              onRetry: () => _save(target: _failedTarget),
              onSystem: () => _save(target: _svc.systemTargetFor(widget.result.format)),
              onSaveAs: () => _save(target: ExportTarget.picked),
              onChooseFolder: _chooseFolderAndSave,
              onSaveCopy: _saveCopy,
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(Space.lg, Space.md, Space.lg, Space.sm),
              child: Column(
                children: [
                  PrimaryButton(
                    label: l.t('share'),
                    icon: Icons.ios_share_rounded,
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

/// Where the export is: saving, saved (name, format, place and what can be
/// done with it), or not saved with the next step that fixes it.
class _SaveCard extends ConsumerWidget {
  const _SaveCard({
    required this.phase,
    required this.record,
    required this.failure,
    required this.failedTarget,
    required this.format,
    required this.folderLabel,
    required this.svc,
    required this.onRetry,
    required this.onSystem,
    required this.onSaveAs,
    required this.onChooseFolder,
    required this.onSaveCopy,
  });

  final _Phase phase;
  final ExportRecord? record;
  final ExportFailure? failure;
  final ExportTarget? failedTarget;
  final ExportFormat format;
  final String? folderLabel;
  final ExportDestinationService svc;
  final VoidCallback onRetry;
  final VoidCallback onSystem;
  final VoidCallback onSaveAs;
  final VoidCallback onChooseFolder;
  final VoidCallback onSaveCopy;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final c = context.colors;
    final Widget body;

    switch (phase) {
      case _Phase.saving:
        body = Row(
          children: [
            SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: c.amber)),
            const SizedBox(width: Space.md),
            Expanded(child: Text(l.t('expSaving'), style: context.text.bodyMd.copyWith(color: c.textMid))),
          ],
        );
      case _Phase.saved:
        final r = record!;
        final place = exportPlaceLabel(l, r.target, r.locationLabel);
        body = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.check_circle_rounded, color: c.success, size: 20),
                const SizedBox(width: Space.sm),
                Expanded(child: Text(l.t('expSaved'), style: context.text.labelLg.copyWith(color: c.success))),
                SpecChip(r.format.toUpperCase()),
              ],
            ),
            const SizedBox(height: Space.sm),
            Text(r.fileName, style: context.text.bodyMd, maxLines: 2, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 2),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Icon(exportPlaceIcon(r.target), size: 16, color: c.amber),
                ),
                const SizedBox(width: 6),
                Expanded(child: Text(place, style: context.text.bodyMd.copyWith(color: c.amber))),
              ],
            ),
            if (r.target == ExportTarget.picked && !svc.canReopenPicked) ...[
              const SizedBox(height: Space.xs),
              Text(l.t('expPickedIosNote'), style: context.text.caption.copyWith(color: c.textLo)),
            ],
            const SizedBox(height: Space.sm),
            Wrap(
              spacing: Space.xs,
              runSpacing: 0,
              children: [
                if (svc.canOpen(r))
                  _Action(
                    icon: Icons.open_in_new_rounded,
                    label: l.t('expOpen'),
                    onTap: () async {
                      final messenger = ScaffoldMessenger.of(context);
                      if (!await svc.open(r)) showAppSnackOn(messenger, l.t('expCantOpen'), kind: SnackKind.error);
                    },
                  ),
                if (svc.canShowLocation(r))
                  _Action(
                    icon: Icons.folder_open_rounded,
                    label: r.target == ExportTarget.gallery ? l.t('expShowGallery') : l.t('expShowFolder'),
                    onTap: () async {
                      final messenger = ScaffoldMessenger.of(context);
                      if (!await svc.showLocation(r)) {
                        showAppSnackOn(messenger, l.a('expCantShowFolder', {'place': place}), kind: SnackKind.error);
                      }
                    },
                  ),
                _Action(icon: Icons.add_to_photos_outlined, label: l.t('expSaveCopy'), onTap: onSaveCopy),
              ],
            ),
          ],
        );
      case _Phase.failed:
        final f = failure ?? ExportFailure.failed;
        final actions = <Widget>[
          switch (f) {
            ExportFailure.folderUnavailable =>
              _Action(icon: Icons.drive_folder_upload_outlined, label: l.t('expChooseFolderAgain'), onTap: onChooseFolder),
            ExportFailure.galleryDenied =>
              _Action(icon: Icons.settings_outlined, label: l.t('expOpenSettings'), onTap: () => openAppSettings()),
            _ => _Action(icon: Icons.refresh_rounded, label: l.t('tryAgain'), onTap: onRetry),
          },
          if (failedTarget != svc.systemTargetFor(format))
            _Action(icon: Icons.verified_outlined, label: l.t('expSaveRecommended'), onTap: onSystem)
          else if (failedTarget != ExportTarget.picked)
            _Action(icon: Icons.save_as_outlined, label: l.t('expSaveAs'), onTap: onSaveAs),
        ];
        final cancelled = f == ExportFailure.cancelled;
        body = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(cancelled ? Icons.info_outline_rounded : Icons.error_outline_rounded,
                    color: cancelled ? c.info : c.danger, size: 20),
                const SizedBox(width: Space.sm),
                Expanded(
                  child: Text(
                    exportFailureText(l, f, folder: folderLabel),
                    style: context.text.bodyMd.copyWith(color: cancelled ? c.textHi : c.danger),
                  ),
                ),
              ],
            ),
            const SizedBox(height: Space.xs),
            Text(l.t('expWorkKept'), style: context.text.caption.copyWith(color: c.textMid)),
            const SizedBox(height: Space.xs),
            Wrap(spacing: Space.xs, children: actions),
          ],
        );
    }

    return Semantics(
      liveRegion: true,
      container: true,
      child: AnimatedSize(
        duration: Motion.fast,
        alignment: Alignment.topCenter,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(Space.lg, Space.md, Space.lg, Space.sm),
          decoration: BoxDecoration(
            color: c.surface,
            borderRadius: BorderRadius.circular(Radii.card),
            border: Border.all(color: phase == _Phase.failed && failure != ExportFailure.cancelled ? c.danger : c.line),
          ),
          child: body,
        ),
      ),
    );
  }
}

class _Action extends StatelessWidget {
  const _Action({required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => TextButton.icon(
        style: TextButton.styleFrom(minimumSize: const Size(0, Sizes.touchTarget)),
        onPressed: onTap,
        icon: Icon(icon, size: 18),
        label: Text(label),
      );
}
