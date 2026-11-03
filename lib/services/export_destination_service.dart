import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/export_record.dart';
import 'export_service.dart';
import 'gallery_service.dart';

/// Why an export could not be saved. Each one has its own message and next
/// step in the UI; the exported image itself is never thrown away.
enum ExportFailure {
  /// The user closed the picker or Save-as dialog.
  cancelled,

  /// The chosen folder is gone or the app's access to it was removed.
  folderUnavailable,

  /// The device is full.
  noSpace,

  /// The gallery refused (usually: no permission to add photos).
  galleryDenied,

  /// Anything else.
  failed,
}

class ExportSaveException implements Exception {
  const ExportSaveException(this.reason, [this.detail]);
  final ExportFailure reason;
  final String? detail;

  @override
  String toString() => 'ExportSaveException($reason${detail == null ? '' : ': $detail'})';
}

/// The current default destination (from settings).
@immutable
class ExportDestination {
  const ExportDestination({
    this.mode = ExportDestinationMode.system,
    this.folderUri,
    this.folderLabel,
  });

  final ExportDestinationMode mode;

  /// Picked folder (Android, mode == folder): a persisted tree URI.
  final String? folderUri;

  /// Readable name of that folder, e.g. "Internal storage/Pictures/Prints".
  final String? folderLabel;

  bool get hasFolder => folderUri != null && folderUri!.isNotEmpty;
}

/// A folder chosen with the system folder picker.
@immutable
class PickedFolder {
  const PickedFolder(this.uri, this.label);
  final String uri;
  final String label;
}

/// A file written by the platform: its handle, final name and readable place.
@immutable
class SavedFile {
  const SavedFile({required this.ref, required this.name, required this.label, required this.target});
  final String ref;
  final String name;
  final String label;
  final ExportTarget target;
}

/// Saves exported bytes where the user wants them and finds them again.
///
/// What is possible depends on the platform, and this class never pretends
/// otherwise:
///
/// * Android: gallery (Pictures/Collage), Download/Collage, any folder picked
///   with the system folder picker (device, SD card, Drive, …), or Save as.
/// * iOS: Photos, the app's Documents folder (visible in the Files app) or
///   Save as via the document picker. Folders can't be remembered, and a file
///   saved with Save as can't be reopened by the app later.
class ExportDestinationService {
  ExportDestinationService(this._gallery);

  final GalleryService _gallery;
  static const _channel = MethodChannel('collage/files');

  /// Sub-folder of the iOS Documents directory for exports.
  static const appFilesFolder = 'Exports';

  bool get _android => !kIsWeb && Platform.isAndroid;
  bool get _ios => !kIsWeb && Platform.isIOS;

  /// A folder can be chosen once and used for every export.
  bool get canPickFolder => _android;

  /// A file saved via Save as can be found again by the app.
  bool get canReopenPicked => _android;

  // ---- folder setting --------------------------------------------------------

  /// Opens the system folder picker. Null when cancelled.
  Future<PickedFolder?> pickFolder() async {
    if (!_android) return null;
    try {
      final r = await _channel.invokeMapMethod<String, dynamic>('pickFolder');
      if (r == null) return null;
      return PickedFolder(r['uri'] as String, r['label'] as String? ?? '');
    } on PlatformException {
      return null;
    }
  }

  /// Gives up the persisted access to a folder that is no longer used.
  Future<void> releaseFolder(String uri) async {
    if (!_android) return;
    try {
      await _channel.invokeMethod('releaseFolder', {'uri': uri});
    } on PlatformException {
      // Already gone.
    }
  }

  /// Whether a remembered folder can still be written to.
  Future<bool> folderUsable(String uri) async {
    if (!_android) return false;
    try {
      return await _channel.invokeMethod<String>('folderStatus', {'uri': uri}) == 'ok';
    } on PlatformException {
      return false;
    }
  }

  // ---- saving ----------------------------------------------------------------

  /// Where [format] goes when the destination is "recommended".
  ExportTarget systemTargetFor(ExportFormat format) {
    if (format.isImage || format == ExportFormat.mp4) return ExportTarget.gallery;
    return _android ? ExportTarget.downloads : ExportTarget.appFiles;
  }

  /// The target [dest] resolves to for [format] (before anything is written).
  ExportTarget targetFor(ExportDestination dest, ExportFormat format) => switch (dest.mode) {
        ExportDestinationMode.system => systemTargetFor(format),
        ExportDestinationMode.folder => dest.hasFolder && _android ? ExportTarget.folder : systemTargetFor(format),
        ExportDestinationMode.ask => ExportTarget.picked,
      };

  /// Writes [bytes] as [fileName] to [target]. Throws [ExportSaveException].
  Future<SavedFile> save({
    required Uint8List bytes,
    required ExportFormat format,
    required String fileName,
    required ExportTarget target,
    String? folderUri,
    String? folderLabel,
  }) async {
    try {
      switch (target) {
        case ExportTarget.gallery:
          return await _saveGallery(bytes, format, fileName);
        case ExportTarget.downloads:
          if (!_android) return await _saveAppFiles(bytes, fileName);
          return await _native('saveToDownloads', bytes, format, fileName, ExportTarget.downloads);
        case ExportTarget.folder:
          if (folderUri == null || !_android) throw const ExportSaveException(ExportFailure.folderUnavailable);
          return await _native('writeToFolder', bytes, format, fileName, ExportTarget.folder, tree: folderUri);
        case ExportTarget.picked:
          return await _savePicked(bytes, format, fileName);
        case ExportTarget.appFiles:
          return await _saveAppFiles(bytes, fileName);
      }
    } on ExportSaveException {
      rethrow;
    } on PlatformException catch (e) {
      throw ExportSaveException(switch (e.code) {
        'revoked' => ExportFailure.folderUnavailable,
        'no_space' => ExportFailure.noSpace,
        _ => ExportFailure.failed,
      }, e.message);
    } on FileSystemException catch (e) {
      final noSpace = e.osError?.errorCode == 28 || (e.osError?.message.contains('space') ?? false);
      throw ExportSaveException(noSpace ? ExportFailure.noSpace : ExportFailure.failed, e.message);
    } catch (e) {
      throw ExportSaveException(ExportFailure.failed, '$e');
    }
  }

  Future<SavedFile> _saveGallery(Uint8List bytes, ExportFormat format, String fileName) async {
    final asset = format == ExportFormat.mp4
        ? await _gallery.saveVideo(bytes, filename: fileName)
        : await _gallery.saveImage(bytes, filename: fileName);
    if (asset == null) throw const ExportSaveException(ExportFailure.galleryDenied);
    final label = _android
        ? (format == ExportFormat.mp4 ? GalleryService.videoAlbumPath : GalleryService.albumPath)
        : '';
    return SavedFile(ref: asset.id, name: asset.title ?? fileName, label: label, target: ExportTarget.gallery);
  }

  Future<SavedFile> _native(
    String method,
    Uint8List bytes,
    ExportFormat format,
    String fileName,
    ExportTarget target, {
    String? tree,
  }) async {
    final r = await _channel.invokeMapMethod<String, dynamic>(method, {
      'tree': ?tree,
      'name': fileName,
      'mime': format.mimeType,
      'bytes': bytes,
    });
    if (r == null) throw const ExportSaveException(ExportFailure.cancelled);
    return SavedFile(
      ref: r['uri'] as String,
      name: (r['name'] as String?)?.isNotEmpty == true ? r['name'] as String : fileName,
      label: r['label'] as String? ?? '',
      target: target,
    );
  }

  Future<SavedFile> _savePicked(Uint8List bytes, ExportFormat format, String fileName) async {
    if (_android) return _native('createDocument', bytes, format, fileName, ExportTarget.picked);
    final uri = await FilePicker.saveFile(fileName: fileName, bytes: bytes, mimeType: format.mimeType);
    if (uri == null) throw const ExportSaveException(ExportFailure.cancelled);
    final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
    final name = segments.isEmpty ? fileName : Uri.decodeComponent(segments.last);
    final parent = segments.length < 2 ? '' : Uri.decodeComponent(segments[segments.length - 2]);
    return SavedFile(ref: uri.toString(), name: name, label: parent, target: ExportTarget.picked);
  }

  Future<Directory> _appFilesDir() async {
    final dir = Directory('${(await getApplicationDocumentsDirectory()).path}/$appFilesFolder');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  Future<SavedFile> _saveAppFiles(Uint8List bytes, String fileName) async {
    final dir = await _appFilesDir();
    final taken = <String>{};
    await for (final e in dir.list()) {
      taken.add(e.path.split(Platform.pathSeparator).last);
    }
    final name = uniqueFileName(fileName, taken);
    final file = File('${dir.path}/$name');
    // Exclusive create: never overwrites, even in a race.
    await file.create(exclusive: true);
    try {
      await file.writeAsBytes(bytes, flush: true);
    } catch (_) {
      if (await file.exists()) await file.delete();
      rethrow;
    }
    return SavedFile(ref: file.path, name: name, label: appFilesFolder, target: ExportTarget.appFiles);
  }

  // ---- finding it again --------------------------------------------------------

  /// Whether the file behind [r] is still there. Never prompts.
  Future<ExportAvailability> check(ExportRecord r) async {
    try {
      switch (r.target) {
        case ExportTarget.gallery:
          final a = await AssetEntity.fromId(r.ref);
          return a == null ? ExportAvailability.missing : ExportAvailability.available;
        case ExportTarget.appFiles:
          return await File(r.ref).exists() ? ExportAvailability.available : ExportAvailability.missing;
        case ExportTarget.downloads:
        case ExportTarget.folder:
        case ExportTarget.picked:
          if (!_android) return ExportAvailability.unknown;
          final s = await _channel.invokeMethod<String>('status', {'uri': r.ref});
          return switch (s) {
            'ok' => ExportAvailability.available,
            'noaccess' => ExportAvailability.noAccess,
            _ => ExportAvailability.missing,
          };
      }
    } catch (_) {
      return ExportAvailability.unknown;
    }
  }

  /// The content URI of a gallery asset on Android.
  String _galleryUri(ExportRecord r) => r.format == 'mp4'
      ? 'content://media/external/video/media/${r.ref}'
      : 'content://media/external/images/media/${r.ref}';

  /// Whether this file can be opened in another app from here.
  bool canOpen(ExportRecord r) =>
      _android || r.target == ExportTarget.appFiles || r.target == ExportTarget.gallery;

  /// Opens the file in the app the system picks. False when that isn't
  /// possible (no app, or the file is out of reach).
  Future<bool> open(ExportRecord r) async {
    try {
      if (_android) {
        final uri = r.target == ExportTarget.gallery ? _galleryUri(r) : r.ref;
        return await _channel.invokeMethod<bool>('open', {'uri': uri, 'mime': r.mimeType}) ?? false;
      }
      if (_ios) {
        if (r.target == ExportTarget.appFiles) {
          return await launchUrl(Uri.parse('shareddocuments://${r.ref}'));
        }
        if (r.target == ExportTarget.gallery) return await launchUrl(Uri.parse('photos-redirect://'));
      }
    } catch (_) {}
    return false;
  }

  /// Whether the folder holding the file can be shown in another app.
  bool canShowLocation(ExportRecord r) {
    if (_android) return r.target != ExportTarget.picked;
    if (_ios) return r.target == ExportTarget.appFiles || r.target == ExportTarget.gallery;
    return false;
  }

  /// Opens the gallery, Downloads or the picked folder in the system app.
  Future<bool> showLocation(ExportRecord r) async {
    try {
      if (_android) {
        final kind = switch (r.target) {
          ExportTarget.gallery => 'gallery',
          ExportTarget.downloads => 'downloads',
          ExportTarget.folder => 'folder',
          _ => null,
        };
        if (kind == null) return false;
        return await _channel.invokeMethod<bool>('showLocation', {'kind': kind, 'uri': ?folderOf(r)}) ?? false;
      }
      if (_ios) {
        if (r.target == ExportTarget.appFiles) {
          return await launchUrl(Uri.parse('shareddocuments://${File(r.ref).parent.path}'));
        }
        if (r.target == ExportTarget.gallery) return await launchUrl(Uri.parse('photos-redirect://'));
      }
    } catch (_) {}
    return false;
  }

  /// The picked folder a record was written to (Android tree URI), if known.
  /// Document URIs from a tree carry it before "/document/".
  String? folderOf(ExportRecord r) {
    if (r.target != ExportTarget.folder) return null;
    final i = r.ref.indexOf('/document/');
    return i > 0 ? r.ref.substring(0, i) : r.ref;
  }

  /// Whether the saved file itself can be shared again.
  bool canShare(ExportRecord r) =>
      _android || r.target == ExportTarget.appFiles || r.target == ExportTarget.gallery;

  /// Shares the saved file. False when it can't be reached.
  Future<bool> share(ExportRecord r, {String? text}) async {
    try {
      if (_android) {
        final uri = r.target == ExportTarget.gallery ? _galleryUri(r) : r.ref;
        return await _channel.invokeMethod<bool>('share', {'uri': uri, 'mime': r.mimeType, 'text': ?text}) ?? false;
      }
      String? path;
      if (r.target == ExportTarget.appFiles) path = r.ref;
      if (r.target == ExportTarget.gallery) path = (await (await AssetEntity.fromId(r.ref))?.file)?.path;
      if (path == null || !await File(path).exists()) return false;
      await SharePlus.instance.share(
        ShareParams(files: [XFile(path, mimeType: r.mimeType)], text: text),
      );
      return true;
    } catch (_) {
      return false;
    }
  }
}
