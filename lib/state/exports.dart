import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../models/export_record.dart';
import '../services/export_destination_service.dart';
import '../services/export_history_service.dart';
import '../services/export_service.dart';
import '../services/prefs_service.dart';
import 'providers.dart';

final exportDestinationServiceProvider =
    Provider((ref) => ExportDestinationService(ref.read(galleryServiceProvider)));

final exportHistoryServiceProvider = Provider((_) => ExportHistoryService());

/// The default export destination, persisted. "Recommended" until the user
/// changes it.
class ExportDestinationNotifier extends Notifier<ExportDestination> {
  PrefsService get _p => ref.read(prefsProvider);

  @override
  ExportDestination build() {
    final p = _p;
    var mode = ExportDestinationMode.parse(p.getString(PrefsService.kExportDestination));
    final uri = p.getString(PrefsService.kExportFolderUri);
    final canFolder = ref.read(exportDestinationServiceProvider).canPickFolder;
    // A folder setting carried over to a device that can't use it (or one
    // that lost its folder) falls back to the recommended place.
    if (mode == ExportDestinationMode.folder && (uri == null || !canFolder)) {
      mode = ExportDestinationMode.system;
    }
    return ExportDestination(
      mode: mode,
      folderUri: uri,
      folderLabel: p.getString(PrefsService.kExportFolderLabel),
    );
  }

  Future<void> setMode(ExportDestinationMode mode) async {
    if (mode == ExportDestinationMode.folder && !state.hasFolder) return;
    await _p.setStringOrRemove(PrefsService.kExportDestination, mode.name);
    state = ExportDestination(mode: mode, folderUri: state.folderUri, folderLabel: state.folderLabel);
  }

  /// Opens the system folder picker and, when a folder is chosen, makes it
  /// the default. Returns false when cancelled.
  Future<bool> chooseFolder() async {
    final svc = ref.read(exportDestinationServiceProvider);
    final picked = await svc.pickFolder();
    if (picked == null) return false;
    final old = state.folderUri;
    if (old != null && old != picked.uri) await svc.releaseFolder(old);
    await _p.setStringOrRemove(PrefsService.kExportFolderUri, picked.uri);
    await _p.setStringOrRemove(PrefsService.kExportFolderLabel, picked.label);
    await _p.setStringOrRemove(PrefsService.kExportDestination, ExportDestinationMode.folder.name);
    state = ExportDestination(
      mode: ExportDestinationMode.folder,
      folderUri: picked.uri,
      folderLabel: picked.label,
    );
    return true;
  }

  /// Back to the recommended place, forgetting the picked folder.
  Future<void> reset() async {
    final old = state.folderUri;
    if (old != null) await ref.read(exportDestinationServiceProvider).releaseFolder(old);
    await _p.setStringOrRemove(PrefsService.kExportFolderUri, null);
    await _p.setStringOrRemove(PrefsService.kExportFolderLabel, null);
    await _p.setStringOrRemove(PrefsService.kExportDestination, null);
    state = const ExportDestination();
  }
}

final exportDestinationProvider =
    NotifierProvider<ExportDestinationNotifier, ExportDestination>(ExportDestinationNotifier.new);

/// Every finished export, newest first.
class ExportHistoryNotifier extends AsyncNotifier<List<ExportRecord>> {
  ExportHistoryService get _svc => ref.read(exportHistoryServiceProvider);

  @override
  Future<List<ExportRecord>> build() => _svc.list();

  /// Writes [bytes] to [target] (or the default destination), then adds the
  /// export to the history. Throws [ExportSaveException]; nothing is recorded
  /// for a failed or cancelled save.
  Future<ExportRecord> saveAndRecord({
    required Uint8List bytes,
    required ExportFormat format,
    required String projectId,
    required String projectTitle,
    Uint8List? thumbnail,
    ExportTarget? target,
    String? fileSuffix,
    int count = 1,
  }) async {
    final dest = ref.read(exportDestinationProvider);
    final svc = ref.read(exportDestinationServiceProvider);
    final to = target ?? svc.targetFor(dest, format);
    final now = DateTime.now();
    final saved = await svc.save(
      bytes: bytes,
      format: format,
      fileName: exportFileName(projectTitle, now, format.extension, suffix: fileSuffix),
      target: to,
      folderUri: dest.folderUri,
      folderLabel: dest.folderLabel,
    );
    return record(
      saved: saved,
      format: format,
      projectId: projectId,
      projectTitle: projectTitle,
      thumbnail: thumbnail ?? (format.isImage && format != ExportFormat.gif ? bytes : null),
      byteSize: bytes.length,
      count: count,
      at: now,
    );
  }

  /// Adds an already written file to the history.
  Future<ExportRecord> record({
    required SavedFile saved,
    required ExportFormat format,
    required String projectId,
    required String projectTitle,
    Uint8List? thumbnail,
    int byteSize = 0,
    int count = 1,
    DateTime? at,
  }) async {
    final id = const Uuid().v4();
    final thumbPath = thumbnail == null ? null : await _svc.saveThumb(id, thumbnail);
    final r = ExportRecord(
      id: id,
      projectId: projectId,
      projectTitle: projectTitle,
      createdAt: at ?? DateTime.now(),
      format: format.name,
      fileName: saved.name,
      target: saved.target,
      locationLabel: saved.label,
      ref: saved.ref,
      mimeType: format.mimeType,
      count: count,
      thumbPath: thumbPath,
      byteSize: byteSize,
    );
    state = AsyncData(await _svc.add(r));
    return r;
  }

  /// Removes entries from the list; the files stay where they are.
  Future<void> forget(Set<String> ids) async {
    state = AsyncData(await _svc.remove(ids));
  }

  Future<void> clear() async {
    await _svc.clear();
    state = const AsyncData([]);
  }
}

final exportHistoryProvider =
    AsyncNotifierProvider<ExportHistoryNotifier, List<ExportRecord>>(ExportHistoryNotifier.new);

/// The exports of one collage, newest first.
final exportsOfProjectProvider = Provider.family<List<ExportRecord>, String>((ref, projectId) {
  final all = ref.watch(exportHistoryProvider).valueOrNull ?? const [];
  return [for (final r in all) if (r.projectId == projectId) r];
});

/// Whether one export's file is still reachable. autoDispose: re-checked
/// whenever it is shown again (files can be moved or deleted meanwhile).
final exportAvailabilityProvider =
    FutureProvider.autoDispose.family<ExportAvailability, ExportRecord>((ref, r) {
  return ref.read(exportDestinationServiceProvider).check(r);
});

/// Whether the chosen folder can still be written to (null: no folder).
/// autoDispose, so it is checked again each time a screen shows it — access
/// can be removed in system settings, or the folder deleted, at any time.
final folderUsableProvider = FutureProvider.autoDispose<bool?>((ref) async {
  final d = ref.watch(exportDestinationProvider);
  if (!d.hasFolder) return null;
  return ref.read(exportDestinationServiceProvider).folderUsable(d.folderUri!);
});
