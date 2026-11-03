import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../../models/collage_project.dart';
import '../../state/exports.dart';
import '../../theme/palette.dart';
import '../../theme/tokens.dart';
import '../../theme/typography.dart';
import '../../widgets/meta_date.dart';
import '../../widgets/ui.dart';
import '../exports/export_history_screen.dart';
import '../flow.dart';
import '../info/backup_actions.dart';
import 'library_actions.dart';
import 'library_query.dart';
import 'library_state.dart';

/// The saved preview of a collage, or a quiet placeholder.
class CollageThumb extends StatelessWidget {
  const CollageThumb({super.key, required this.project, this.fit = BoxFit.cover, this.cacheWidth});
  final CollageProject project;
  final BoxFit fit;
  final int? cacheWidth;

  @override
  Widget build(BuildContext context) {
    final path = project.thumbnailPath;
    if (path != null && File(path).existsSync()) {
      return Image.file(
        File(path),
        fit: fit,
        cacheWidth: cacheWidth,
        gaplessPlayback: true,
        errorBuilder: (_, __, ___) => _placeholder(context),
      );
    }
    return _placeholder(context);
  }

  Widget _placeholder(BuildContext context) => ColoredBox(
    color: context.colors.surfaceInput,
    child: Center(child: Icon(Icons.image_outlined, color: context.colors.textLo)),
  );
}

/// A collage in the My Collages grid: preview, title, ratio and a date that
/// never truncates. Tap opens it (or toggles it in selection mode),
/// long-press starts selecting, and the visible ⋯ button opens every action.
class LibraryCollageCard extends ConsumerWidget {
  const LibraryCollageCard({
    super.key,
    required this.project,
    required this.stampMillis,
    required this.selecting,
    required this.selected,
  });

  final CollageProject project;

  /// The date shown on the card (created, or last edited when sorting by it).
  final int stampMillis;
  final bool selecting;
  final bool selected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final l = context.l10n;
    final video = hasVideo(project);
    final dateLong = formatCollageDateLong(stampMillis, localeName: dateLocaleOf(context));
    final dpr = MediaQuery.devicePixelRatioOf(context);

    void tap() => selecting ? ref.toggleSelected(project.id) : openCollage(context, ref, project);
    void longPress() => selecting ? ref.toggleSelected(project.id) : ref.startSelecting(project.id);

    final card = Material(
      color: c.surface,
      borderRadius: BorderRadius.circular(Radii.card),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: tap,
        onLongPress: longPress,
        child: AnimatedContainer(
          duration: MediaQuery.disableAnimationsOf(context) ? Duration.zero : Motion.fast,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(Radii.card),
            border: Border.all(color: selected ? c.amber : c.line, width: selected ? 2 : 1),
          ),
          child: ExcludeSemantics(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: LayoutBuilder(
                    builder: (_, box) => CollageThumb(
                      project: project,
                      cacheWidth: box.maxWidth.isFinite ? (box.maxWidth * dpr).round() : null,
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(Space.md, Space.sm, Space.md, Space.md),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        project.title,
                        style: context.text.labelLg,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: Space.xs),
                      Row(
                        children: [
                          SpecChip(project.ratioLabel),
                          if (video) ...[
                            const SizedBox(width: Space.xs),
                            Icon(Icons.videocam_outlined, size: 16, color: c.textMid),
                          ],
                        ],
                      ),
                      const SizedBox(height: Space.xs),
                      MetaDate(epochMillis: stampMillis, showRelative: true),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    return FocusTraversalGroup(
      child: Stack(
        children: [
          Positioned.fill(
            child: Semantics(
              container: true,
              button: true,
              selected: selecting ? selected : null,
              label: l.a('libCardSemantics', {'title': project.title, 'date': dateLong}),
              hint: selecting ? null : l.t('libCardHint'),
              child: card,
            ),
          ),
          if (selecting)
            PositionedDirectional(
              top: Space.sm,
              start: Space.sm,
              child: IgnorePointer(child: _SelectMark(selected: selected)),
            )
          else
            PositionedDirectional(
              top: 0,
              end: 0,
              child: IconButton(
                tooltip: l.t('moreActions'),
                onPressed: () => showCollageMenu(context, ref, project),
                icon: Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(color: c.surface.withValues(alpha: 0.85), shape: BoxShape.circle),
                  child: Icon(Icons.more_horiz_rounded, size: 20, color: c.textHi),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _SelectMark extends StatelessWidget {
  const _SelectMark({required this.selected});
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      width: 28,
      height: 28,
      decoration: BoxDecoration(
        color: selected ? c.amber : c.surface.withValues(alpha: 0.85),
        shape: BoxShape.circle,
        border: Border.all(color: selected ? c.amber : c.lineStrong, width: 1.5),
      ),
      child: selected ? Icon(Icons.check_rounded, size: 18, color: c.onAmber) : null,
    );
  }
}

/// Everything you can do with one collage.
enum CollageAction { details, edit, share, exports, rename, duplicate, sendForEditing, select, trash }

/// The ⋯ menu of a card.
Future<void> showCollageMenu(BuildContext context, WidgetRef ref, CollageProject project) async {
  final l = context.l10n;
  final c = context.colors;
  final action = await showModalBottomSheet<CollageAction>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (sheet) {
      Widget tile(CollageAction a, IconData icon, String label, {bool danger = false}) => ListTile(
        leading: Icon(icon, color: danger ? c.danger : null),
        title: Text(label, style: danger ? TextStyle(color: c.danger) : null),
        onTap: () => Navigator.pop(sheet, a),
      );
      return SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(Space.xl, 0, Space.xl, Space.sm),
                child: Text(
                  project.title,
                  style: context.text.titleMd,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              tile(CollageAction.details, Icons.info_outline_rounded, l.t('libDetails')),
              tile(CollageAction.edit, Icons.edit_rounded, l.t('ctxEdit')),
              tile(CollageAction.share, Icons.ios_share_rounded, l.t('share')),
              tile(CollageAction.exports, Icons.history_rounded, l.t('expOfCollage')),
              tile(CollageAction.rename, Icons.drive_file_rename_outline_rounded, l.t('renameCollage')),
              tile(CollageAction.duplicate, Icons.copy_rounded, l.t('duplicateCollage')),
              tile(CollageAction.sendForEditing, Icons.people_outline_rounded, l.t('shareForEditing')),
              tile(CollageAction.select, Icons.check_circle_outline_rounded, l.t('libSelect')),
              tile(CollageAction.trash, Icons.delete_outline_rounded, l.t('moveToTrash'), danger: true),
            ],
          ),
        ),
      );
    },
  );
  if (action == null || !context.mounted) return;
  await runCollageAction(context, ref, project, action);
}

Future<void> runCollageAction(
  BuildContext context,
  WidgetRef ref,
  CollageProject project,
  CollageAction action,
) async {
  switch (action) {
    case CollageAction.details:
      await showCollageDetails(context, ref, project);
    case CollageAction.edit:
      await openCollage(context, ref, project);
    case CollageAction.share:
      await shareCollageImage(context, ref, project);
    case CollageAction.exports:
      await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => ExportHistoryScreen(projectId: project.id, projectTitle: project.title),
      ));
    case CollageAction.rename:
      await renameCollage(context, ref, project);
    case CollageAction.duplicate:
      await duplicateCollage(context, ref, project);
    case CollageAction.sendForEditing:
      await shareCollageForEditing(context, ref, project.id);
    case CollageAction.select:
      ref.startSelecting(project.id);
    case CollageAction.trash:
      await moveOneToTrash(context, ref, project);
  }
}

/// A large preview of a collage with its full dates, template, photo count
/// and the main actions.
Future<void> showCollageDetails(BuildContext context, WidgetRef ref, CollageProject project) async {
  final action = await showModalBottomSheet<CollageAction>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (sheet) => _DetailsSheet(project: project),
  );
  if (action == null || !context.mounted) return;
  await runCollageAction(context, ref, project, action);
}

class _DetailsSheet extends ConsumerWidget {
  const _DetailsSheet({required this.project});
  final CollageProject project;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final exports = ref.watch(exportsOfProjectProvider(project.id));
    final l = context.l10n;
    final c = context.colors;
    final locale = dateLocaleOf(context);
    final size = MediaQuery.sizeOf(context);
    final style = templateStyleKey(project);
    final photos = project.fills.values.where((f) => !f.isVideo).map((f) => f.assetId).toSet().length;
    final videos = project.fills.values.where((f) => f.isVideo).map((f) => f.assetId).toSet().length;

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: size.height * 0.9),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(Space.xl, 0, Space.xl, Space.xl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              ConstrainedBox(
                constraints: BoxConstraints(maxHeight: size.height * 0.4),
                child: Center(
                  child: AspectRatio(
                    aspectRatio: project.ratio.value,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(Radii.card),
                      child: Semantics(
                        image: true,
                        label: project.title,
                        child: CollageThumb(project: project, fit: BoxFit.contain),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: Space.lg),
              Text(project.title, style: context.text.titleLg),
              const SizedBox(height: Space.sm),
              Wrap(
                spacing: Space.sm,
                runSpacing: Space.sm,
                children: [
                  SpecChip(project.ratioLabel),
                  SpecChip('$photos', icon: Icons.photo_outlined),
                  if (videos > 0) SpecChip('$videos', icon: Icons.videocam_outlined),
                ],
              ),
              const SizedBox(height: Space.lg),
              _InfoRow(
                icon: Icons.event_rounded,
                label: l.t('libCreated'),
                value: formatCollageDateLong(project.createdAt, localeName: locale),
              ),
              _InfoRow(
                icon: Icons.edit_calendar_outlined,
                label: l.t('libEdited'),
                value: formatCollageDateLong(project.updatedAt, localeName: locale),
              ),
              _InfoRow(
                icon: Icons.dashboard_customize_outlined,
                label: l.t('libTemplate'),
                value: style == null ? l.t('libNoTemplate') : templateStyleLabel(l, style),
              ),
              if (project.occasionId != null)
                _InfoRow(
                  icon: Icons.celebration_outlined,
                  label: l.t('libOccasion'),
                  value: occasionLabel(l, project.occasionId!),
                ),
              _InfoRow(
                icon: Icons.photo_library_outlined,
                label: l.t('libPhotos'),
                value: videos > 0 ? '$photos · ${l.t('libVideos')}: $videos' : '$photos',
              ),
              // Where this collage's exports went, so they can be found again.
              const SizedBox(height: Space.md),
              Semantics(
                header: true,
                child: Text(
                  exports.isEmpty ? l.t('expOfCollage') : l.a('expOfCollageCount', {'count': '${exports.length}'}),
                  style: context.text.labelMd.copyWith(color: c.textMid),
                ),
              ),
              if (exports.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: Space.xs),
                  child: Text(l.t('expOfCollageNone'), style: context.text.caption.copyWith(color: c.textLo)),
                )
              else ...[
                for (final r in exports.take(3)) ExportTile(record: r, showTitle: false, dense: true),
                if (exports.length > 3)
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: TextButton(
                      onPressed: () => Navigator.pop(context, CollageAction.exports),
                      child: Text(l.a('expShowAll', {'count': '${exports.length}'})),
                    ),
                  ),
              ],
              const SizedBox(height: Space.xl),
              PrimaryButton(
                label: l.t('ctxEdit'),
                icon: Icons.edit_rounded,
                onPressed: () => Navigator.pop(context, CollageAction.edit),
              ),
              const SizedBox(height: Space.md),
              Row(
                children: [
                  _SheetAction(
                    icon: Icons.ios_share_rounded,
                    label: l.t('share'),
                    onTap: () => Navigator.pop(context, CollageAction.share),
                  ),
                  _SheetAction(
                    icon: Icons.copy_rounded,
                    label: l.t('duplicateCollage'),
                    onTap: () => Navigator.pop(context, CollageAction.duplicate),
                  ),
                  _SheetAction(
                    icon: Icons.drive_file_rename_outline_rounded,
                    label: l.t('renameCollage'),
                    onTap: () => Navigator.pop(context, CollageAction.rename),
                  ),
                  _SheetAction(
                    icon: Icons.delete_outline_rounded,
                    label: l.t('delete'),
                    color: c.danger,
                    semanticsLabel: l.t('moveToTrash'),
                    onTap: () => Navigator.pop(context, CollageAction.trash),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.icon, required this.label, required this.value});
  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return MergeSemantics(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: Space.sm),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 20, color: c.textLo),
            const SizedBox(width: Space.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: context.text.caption.copyWith(color: c.textLo)),
                  const SizedBox(height: 2),
                  Text(value, style: context.text.bodyMd.copyWith(color: c.textHi)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SheetAction extends StatelessWidget {
  const _SheetAction({
    required this.icon,
    required this.label,
    required this.onTap,
    this.color,
    this.semanticsLabel,
  });
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? color;
  final String? semanticsLabel;

  @override
  Widget build(BuildContext context) {
    final fg = color ?? context.colors.textHi;
    return Expanded(
      child: Semantics(
        button: true,
        label: semanticsLabel ?? label,
        excludeSemantics: true,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(Radii.control),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 64),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: Space.sm, horizontal: Space.xs),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, color: fg),
                  const SizedBox(height: Space.xs),
                  Text(
                    label,
                    textAlign: TextAlign.center,
                    style: context.text.labelMd.copyWith(color: fg),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
