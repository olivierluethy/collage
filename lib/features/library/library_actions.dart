import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../l10n/app_localizations.dart';
import '../../l10n/plural.dart';
import '../../models/collage_project.dart';
import '../../services/draft_service.dart';
import '../../state/providers.dart';
import '../../widgets/ui.dart';
import 'library_state.dart';

/// Move several collages to the trash after a confirmation that names the
/// exact count, then offer Undo that restores exactly those collages.
///
/// [note] is an extra line for the dialog (e.g. the date range being cleared).
/// Returns true when they were moved.
Future<bool> confirmMoveToTrash(BuildContext context, WidgetRef ref, List<String> ids, {String? note}) async {
  if (ids.isEmpty) return false;
  final l = context.l10n;
  final n = ids.length;
  final restoreNote = l.a('libTrashNote', {'days': '${DraftService.trashDays}'});
  final ok = await confirmDestructive(
    context,
    title: l.p('libTrashTitle', n),
    message: note == null ? restoreNote : '$note\n\n$restoreNote',
    confirmLabel: l.t('moveToTrash'),
    cancelLabel: l.t('cancel'),
  );
  if (!ok || !context.mounted) return false;
  final messenger = ScaffoldMessenger.of(context);
  final drafts = ref.read(draftsProvider.notifier);
  final trash = ref.read(trashProvider.notifier);
  final moved = List<String>.of(ids);
  await drafts.removeMany(moved);
  ref.stopSelecting();
  showAppSnackOn(
    messenger,
    l.p('libMovedMany', n),
    kind: SnackKind.success,
    actionLabel: l.t('undo'),
    onAction: () => trash.restoreMany(moved),
  );
  return true;
}

/// Move one collage to the trash. Not confirmed: the snackbar's Undo restores
/// it on the spot.
Future<void> moveOneToTrash(BuildContext context, WidgetRef ref, CollageProject project) async {
  final l = context.l10n;
  final messenger = ScaffoldMessenger.of(context);
  final trash = ref.read(trashProvider.notifier);
  await ref.read(draftsProvider.notifier).remove(project.id);
  showAppSnackOn(
    messenger,
    l.t('movedToTrash'),
    kind: SnackKind.success,
    actionLabel: l.t('undo'),
    onAction: () => trash.restore(project.id),
  );
}

/// Ask for a new title and rename the collage.
Future<void> renameCollage(BuildContext context, WidgetRef ref, CollageProject project) async {
  final l = context.l10n;
  final ctrl = TextEditingController(text: project.title);
  final title = await showDialog<String>(
    context: context,
    builder: (dialog) => AlertDialog(
      title: Text(l.t('renameCollage')),
      content: TextField(
        controller: ctrl,
        autofocus: true,
        maxLength: 60,
        textInputAction: TextInputAction.done,
        onSubmitted: (v) => Navigator.pop(dialog, v),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(dialog), child: Text(l.t('cancel'))),
        TextButton(onPressed: () => Navigator.pop(dialog, ctrl.text), child: Text(l.t('save'))),
      ],
    ),
  );
  ctrl.dispose();
  final t = title?.trim();
  if (t == null || t.isEmpty || t == project.title) return;
  await ref.read(draftsProvider.notifier).rename(project.id, t);
}

Future<void> duplicateCollage(BuildContext context, WidgetRef ref, CollageProject project) => ref
    .read(draftsProvider.notifier)
    .duplicate(project.id, title: context.l10n.a('copyOfTitle', {'title': project.title}));

/// Share the collage as a picture: its last full-size export when there is
/// one, else its preview thumbnail.
Future<void> shareCollageImage(BuildContext context, WidgetRef ref, CollageProject project) async {
  final l = context.l10n;
  final messenger = ScaffoldMessenger.of(context);
  try {
    final bytes = await ref.read(draftServiceProvider).renderOf(project.id);
    if (bytes == null || bytes.isEmpty) throw StateError('no image');
    // PNG files start with 0x89 'P'; anything else saved here is a JPEG.
    final png = bytes.length > 1 && bytes[0] == 0x89 && bytes[1] == 0x50;
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/collage_share.${png ? 'png' : 'jpg'}');
    await file.writeAsBytes(bytes);
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path, mimeType: png ? 'image/png' : 'image/jpeg')],
        text: l.t('madeWithCollage'),
      ),
    );
  } catch (_) {
    showAppSnackOn(messenger, l.t('libShareFailed'), kind: SnackKind.error);
  }
}
