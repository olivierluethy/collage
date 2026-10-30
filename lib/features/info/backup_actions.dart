import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../l10n/app_localizations.dart';
import '../../services/backup_service.dart';
import '../../state/providers.dart';

/// Run [work] behind a modal progress dialog that can't be dismissed.
Future<T> _withProgress<T>(BuildContext context, String label, Future<T> Function() work) async {
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => PopScope(
      canPop: false,
      child: AlertDialog(
        content: Row(
          children: [
            const CircularProgressIndicator(),
            const SizedBox(width: 20),
            Expanded(child: Text(label)),
          ],
        ),
      ),
    ),
  );
  try {
    return await work();
  } finally {
    if (context.mounted) Navigator.of(context, rootNavigator: true).pop();
  }
}

/// Pack every collage (with its photos) into a .zip and hand it to the share
/// sheet, so the user can keep it in Drive, mail it to themselves, etc.
Future<void> createBackup(BuildContext context, WidgetRef ref) async {
  final l = context.l10n;
  final messenger = ScaffoldMessenger.of(context);
  try {
    final file = await _withProgress(
      context,
      l.t('backupCreating'),
      () => ref.read(backupServiceProvider).create(),
    );
    await SharePlus.instance.share(ShareParams(
      files: [XFile(file.path, mimeType: 'application/zip')],
      text: l.t('backupShareText'),
    ));
  } catch (_) {
    messenger.showSnackBar(SnackBar(content: Text(l.t('backupFailed'))));
  }
}

/// Send one collage (with its photos) as a ".collage" file, so someone else
/// can import, edit and send it back.
Future<void> shareCollageForEditing(BuildContext context, WidgetRef ref, String id) async {
  final l = context.l10n;
  final messenger = ScaffoldMessenger.of(context);
  try {
    final file = await _withProgress(
      context,
      l.t('backupCreating'),
      () => ref.read(backupServiceProvider).create(onlyId: id),
    );
    await SharePlus.instance.share(ShareParams(
      files: [XFile(file.path, mimeType: 'application/zip')],
      text: l.t('shareForEditingText'),
    ));
  } catch (_) {
    messenger.showSnackBar(SnackBar(content: Text(l.t('backupFailed'))));
  }
}

/// Let the user pick a backup .zip or a shared .collage file and import it.
Future<void> restoreBackup(BuildContext context, WidgetRef ref) async {
  final l = context.l10n;
  final messenger = ScaffoldMessenger.of(context);
  // Any file type: Android often can't map ".collage" to a MIME type filter.
  final picked = await FilePicker.pickFile(type: FileType.any);
  if (picked == null || !context.mounted) return;
  try {
    final summary = await _withProgress(context, l.t('backupRestoring'), () async {
      final bytes = await picked.readAsBytes();
      return ref.read(backupServiceProvider).restore(bytes);
    });
    await ref.read(draftsProvider.notifier).reload();
    messenger.showSnackBar(SnackBar(
      content: Text(l.a('backupRestored', {
        'count': '${summary.collages}',
        'photos': '${summary.photos}',
      })),
    ));
  } on BackupFormatException {
    messenger.showSnackBar(SnackBar(content: Text(l.t('backupInvalid'))));
  } catch (_) {
    messenger.showSnackBar(SnackBar(content: Text(l.t('backupFailed'))));
  }
}
