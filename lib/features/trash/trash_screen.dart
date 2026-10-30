import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../../models/collage_project.dart';
import '../../services/draft_service.dart';
import '../../state/providers.dart';
import '../../theme/palette.dart';
import '../../theme/tokens.dart';
import '../../theme/typography.dart';
import '../../widgets/ui.dart';

/// Deleted collages, restorable for [DraftService.trashDays] days.
class TrashScreen extends ConsumerWidget {
  const TrashScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final trash = ref.watch(trashProvider);
    final items = trash.valueOrNull ?? const [];
    return Scaffold(
      appBar: AppBar(
        title: Text(context.l10n.t('trashTitle')),
        actions: [
          if (items.isNotEmpty)
            TextButton(
              onPressed: () => _confirmEmpty(context, ref),
              child: Text(context.l10n.t('emptyTrash'), style: TextStyle(color: context.colors.danger)),
            ),
        ],
      ),
      body: trash.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => EmptyState(
              icon: Icons.error_outline_rounded,
              title: context.l10n.t('loadFailedTitle'),
              message: context.l10n.t('loadFailedMessage'),
            ),
        data: (list) {
          if (list.isEmpty) {
            return EmptyState(
              icon: Icons.delete_outline_rounded,
              title: context.l10n.t('trashEmptyTitle'),
              message: context.l10n.a('trashEmptyMessage', {'days': '${DraftService.trashDays}'}),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.only(bottom: Space.xl),
            itemCount: list.length + 1,
            separatorBuilder: (_, i) => i == 0 ? const SizedBox.shrink() : const Divider(height: 1),
            itemBuilder: (_, i) {
              if (i == 0) {
                return Padding(
                  padding: const EdgeInsets.fromLTRB(Space.lg, Space.md, Space.lg, Space.sm),
                  child: Text(
                    context.l10n.a('trashExplainer', {'days': '${DraftService.trashDays}'}),
                    style: context.text.bodyMd.copyWith(color: context.colors.textMid),
                  ),
                );
              }
              final (project, deletedAt) = list[i - 1];
              return _TrashTile(project: project, deletedAt: deletedAt);
            },
          );
        },
      ),
    );
  }

  Future<void> _confirmEmpty(BuildContext context, WidgetRef ref) async {
    final l = context.l10n;
    final ok = await confirmDestructive(
      context,
      title: l.t('emptyTrashTitle'),
      message: l.t('emptyTrashMessage'),
      confirmLabel: l.t('emptyTrash'),
      cancelLabel: l.t('cancel'),
    );
    if (ok) await ref.read(trashProvider.notifier).empty();
  }
}

class _TrashTile extends ConsumerWidget {
  const _TrashTile({required this.project, required this.deletedAt});
  final CollageProject project;
  final int deletedAt;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final left = DraftService.trashDays -
        DateTime.now().difference(DateTime.fromMillisecondsSinceEpoch(deletedAt)).inDays;
    final thumb = project.thumbnailPath;
    return ListTile(
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(Radii.control),
        child: SizedBox(
          width: 52,
          height: 52,
          child: thumb != null && File(thumb).existsSync()
              ? Image.file(File(thumb), fit: BoxFit.cover)
              : ColoredBox(color: context.colors.surfaceInput),
        ),
      ),
      title: Text(project.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(context.l10n.a('trashDaysLeft', {'days': '${left.clamp(0, DraftService.trashDays)}'})),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextButton.icon(
            icon: const Icon(Icons.restore_rounded, size: 18),
            label: Text(context.l10n.t('restore')),
            onPressed: () async {
              final l = context.l10n;
              await ref.read(trashProvider.notifier).restore(project.id);
              if (context.mounted) showAppSnack(context, l.t('restored'), kind: SnackKind.success);
            },
          ),
          IconButton(
            tooltip: context.l10n.t('deleteForever'),
            icon: Icon(Icons.delete_forever_rounded, color: context.colors.danger),
            onPressed: () async {
              final l = context.l10n;
              final ok = await confirmDestructive(
                context,
                title: l.t('deleteForeverTitle'),
                message: l.t('deleteForeverMessage'),
                confirmLabel: l.t('deleteForever'),
                cancelLabel: l.t('cancel'),
              );
              if (ok) await ref.read(trashProvider.notifier).deleteForever(project.id);
            },
          ),
        ],
      ),
    );
  }
}
