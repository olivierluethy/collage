import 'dart:io';

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../../models/export_record.dart';
import '../../state/exports.dart';
import '../../state/providers.dart';
import '../../theme/palette.dart';
import '../../theme/tokens.dart';
import '../../theme/typography.dart';
import '../../widgets/ui.dart';
import '../flow.dart';
import 'export_place.dart';

/// Recent exports: every picture, video or PDF saved from the app, with where
/// it went and quick ways to open, find and share it again. With [projectId]
/// it lists the exports of one collage.
class ExportHistoryScreen extends ConsumerWidget {
  const ExportHistoryScreen({super.key, this.projectId, this.projectTitle});
  final String? projectId;
  final String? projectTitle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final c = context.colors;
    final async = ref.watch(exportHistoryProvider);
    final all = async.valueOrNull ?? const <ExportRecord>[];
    final list = projectId == null ? all : [for (final r in all) if (r.projectId == projectId) r];

    return Scaffold(
      appBar: AppBar(
        title: Text(projectTitle == null ? l.t('expHistoryTitle') : l.a('expHistoryOf', {'title': projectTitle!})),
        actions: [
          if (list.isNotEmpty)
            IconButton(
              tooltip: l.t('expClearList'),
              icon: const Icon(Icons.playlist_remove_rounded),
              onPressed: () async {
                final ok = await confirmDestructive(
                  context,
                  title: l.t('expClearList'),
                  message: l.t('expClearListBody'),
                  confirmLabel: l.t('expClearListConfirm'),
                  cancelLabel: l.t('cancel'),
                );
                if (!ok) return;
                final n = ref.read(exportHistoryProvider.notifier);
                if (projectId == null) {
                  await n.clear();
                } else {
                  await n.forget({for (final r in list) r.id});
                }
              },
            ),
        ],
      ),
      body: async.isLoading && all.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : list.isEmpty
              ? EmptyState(
                  icon: Icons.download_done_rounded,
                  title: l.t('expHistoryEmpty'),
                  message: l.t('expHistoryEmptyHint'),
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(Space.lg, Space.sm, Space.lg, Space.xxl),
                  itemCount: list.length + 1,
                  separatorBuilder: (_, i) => i == 0 ? const SizedBox(height: Space.sm) : Divider(height: 1, color: c.line),
                  itemBuilder: (context, i) {
                    if (i == 0) {
                      return Text(l.t('expHistoryIntro'), style: context.text.bodyMd.copyWith(color: c.textMid));
                    }
                    return ExportTile(record: list[i - 1], showTitle: projectId == null);
                  },
                ),
    );
  }
}

/// One export: preview, name, format, place, time and whether the file is
/// still there. Tapping opens its actions.
class ExportTile extends ConsumerWidget {
  const ExportTile({super.key, required this.record, this.showTitle = true, this.dense = false});
  final ExportRecord record;
  final bool showTitle;
  final bool dense;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final c = context.colors;
    final avail = ref.watch(exportAvailabilityProvider(record)).valueOrNull ?? ExportAvailability.checking;
    final gone = avail == ExportAvailability.missing || avail == ExportAvailability.noAccess;
    final place = exportPlaceLabel(l, record.target, record.locationLabel);
    final title = showTitle ? record.projectTitle : record.fileName;
    final format = record.format.toUpperCase();
    final when = exportWhen(context, record.createdAt);
    final status = switch (avail) {
      ExportAvailability.missing => l.t('expStatusMissing'),
      ExportAvailability.noAccess => l.t('expStatusNoAccess'),
      _ => null,
    };

    return MergeSemantics(
      child: InkWell(
        borderRadius: BorderRadius.circular(Radii.card),
        onTap: () => showExportActions(context, ref, record),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: Sizes.touchTarget),
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: dense ? Space.sm : Space.md),
            child: Row(
              children: [
                _Thumb(record: record, size: dense ? 48 : 64, faded: gone),
                const SizedBox(width: Space.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title.isEmpty ? record.fileName : title,
                          style: context.text.bodyLg, maxLines: 1, overflow: TextOverflow.ellipsis),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Icon(exportPlaceIcon(record.target), size: 14, color: gone ? c.textLo : c.amber),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              place,
                              style: context.text.caption.copyWith(color: gone ? c.textLo : c.amber),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        [
                          format,
                          if (record.count > 1) l.a('expFiles', {'count': '${record.count}'}),
                          when,
                        ].join(', '),
                        style: context.text.caption.copyWith(color: c.textMid),
                      ),
                      if (status != null) ...[
                        const SizedBox(height: 2),
                        Text(status, style: context.text.caption.copyWith(color: c.danger)),
                      ],
                    ],
                  ),
                ),
                Icon(Icons.more_vert_rounded, color: c.textLo, semanticLabel: l.t('moreActions')),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Thumb extends StatelessWidget {
  const _Thumb({required this.record, required this.size, required this.faded});
  final ExportRecord record;
  final double size;
  final bool faded;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final p = record.thumbPath;
    Widget child;
    if (p != null && File(p).existsSync()) {
      child = Image.file(File(p), fit: BoxFit.cover, cacheWidth: (size * 3).round());
    } else {
      child = Icon(
        record.format == 'pdf'
            ? Icons.picture_as_pdf_outlined
            : record.format == 'mp4'
                ? Icons.movie_outlined
                : Icons.image_outlined,
        color: c.textMid,
      );
    }
    return ExcludeSemantics(
      child: Opacity(
        opacity: faded ? 0.45 : 1,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(Radii.control),
          child: Container(width: size, height: size, color: c.surfaceHigh, alignment: Alignment.center, child: child),
        ),
      ),
    );
  }
}

/// What can be done with one export, as a sheet. Actions the platform can't
/// do are left out, and a short note says why.
Future<void> showExportActions(BuildContext context, WidgetRef ref, ExportRecord r) async {
  final l = context.l10n;
  final svc = ref.read(exportDestinationServiceProvider);
  final avail = await ref.read(exportAvailabilityProvider(r).future);
  if (!context.mounted) return;
  final gone = avail == ExportAvailability.missing || avail == ExportAvailability.noAccess;
  final place = exportPlaceLabel(l, r.target, r.locationLabel);

  final action = await showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (sheet) {
      final c = sheet.colors;
      Widget tile(String id, IconData icon, String label, {String? sub, bool danger = false}) => ListTile(
            minTileHeight: Sizes.touchTarget,
            leading: Icon(icon, color: danger ? c.danger : null),
            title: Text(label, style: danger ? TextStyle(color: c.danger) : null),
            subtitle: sub == null ? null : Text(sub),
            onTap: () => Navigator.pop(sheet, id),
          );
      return SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(Space.xl, 0, Space.xl, Space.xs),
                child: Text(r.fileName, style: sheet.text.titleMd, maxLines: 2, overflow: TextOverflow.ellipsis),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(Space.xl, 0, Space.xl, Space.sm),
                child: Text(
                  gone
                      ? (avail == ExportAvailability.noAccess ? l.t('expGoneNoAccess') : l.a('expGoneMissing', {'place': place}))
                      : l.a('expSavedIn', {'place': place}),
                  style: sheet.text.bodyMd.copyWith(color: gone ? c.danger : c.textMid),
                ),
              ),
              if (!gone && svc.canOpen(r)) tile('open', Icons.open_in_new_rounded, l.t('expOpen')),
              if (!gone && svc.canShowLocation(r))
                tile('show', Icons.folder_open_rounded,
                    r.target == ExportTarget.gallery ? l.t('expShowGallery') : l.t('expShowFolder')),
              if (!gone && svc.canShare(r)) tile('share', Icons.ios_share_rounded, l.t('share')),
              if (!svc.canOpen(r) || (r.target == ExportTarget.picked && !svc.canReopenPicked))
                Padding(
                  padding: const EdgeInsets.fromLTRB(Space.xl, Space.xs, Space.xl, Space.sm),
                  child: Text(l.t('expPickedIosNote'), style: sheet.text.caption.copyWith(color: c.textLo)),
                ),
              tile('again', Icons.replay_rounded, l.t('expExportAgain'), sub: l.t('expExportAgainHint')),
              tile('forget', Icons.playlist_remove_rounded, l.t('expForget'), sub: l.t('expForgetHint')),
            ],
          ),
        ),
      );
    },
  );
  if (action == null || !context.mounted) return;
  final messenger = ScaffoldMessenger.of(context);
  switch (action) {
    case 'open':
      if (!await svc.open(r)) showAppSnackOn(messenger, l.t('expCantOpen'), kind: SnackKind.error);
    case 'show':
      if (!await svc.showLocation(r)) {
        showAppSnackOn(messenger, l.a('expCantShowFolder', {'place': place}), kind: SnackKind.error);
      }
    case 'share':
      if (!await svc.share(r, text: l.t('madeWithCollage'))) {
        showAppSnackOn(messenger, l.t('expCantShare'), kind: SnackKind.error);
      }
    case 'again':
      final drafts = ref.read(draftsProvider).valueOrNull ?? const [];
      final project = drafts.firstWhereOrNull((p) => p.id == r.projectId);
      if (project == null) {
        showAppSnackOn(messenger, l.t('expCollageGone'), kind: SnackKind.error);
      } else {
        await openCollage(context, ref, project);
      }
    case 'forget':
      await ref.read(exportHistoryProvider.notifier).forget({r.id});
      showAppSnackOn(messenger, l.t('expForgotten'), kind: SnackKind.success);
  }
}
