import 'package:flutter/foundation.dart';

/// Where an exported file actually went. Each one is something the OS lets
/// us write to and find again; there are no made-up file paths.
enum ExportTarget {
  /// The phone's photo gallery (Android: Pictures/Collage, iOS: Photos).
  gallery,

  /// Android's Download/Collage folder (MediaStore), used for PDFs.
  downloads,

  /// A folder the user chose with the system folder picker (Android).
  folder,

  /// A place picked for this one file in the system "Save as" dialog.
  picked,

  /// The app's own Documents folder, shown in Files › On My iPhone › Collage.
  appFiles;

  static ExportTarget parse(String? s) =>
      ExportTarget.values.firstWhere((t) => t.name == s, orElse: () => gallery);
}

/// The default destination setting.
enum ExportDestinationMode {
  /// Gallery for pictures and videos, a visible documents folder for PDFs.
  system,

  /// Every export goes to a folder the user picked (Android only).
  folder,

  /// The system "Save as" dialog opens for every export.
  ask;

  static ExportDestinationMode parse(String? s) =>
      ExportDestinationMode.values.firstWhere((m) => m.name == s, orElse: () => system);
}

/// Whether an exported file can still be reached.
enum ExportAvailability { checking, available, missing, noAccess, unknown }

/// One finished export, kept in the export history so it can be found,
/// opened and shared again — and linked back to its collage.
@immutable
class ExportRecord {
  const ExportRecord({
    required this.id,
    required this.projectId,
    required this.projectTitle,
    required this.createdAt,
    required this.format,
    required this.fileName,
    required this.target,
    required this.locationLabel,
    required this.ref,
    required this.mimeType,
    this.count = 1,
    this.thumbPath,
    this.byteSize = 0,
  });

  final String id;
  final String projectId;

  /// Title at export time (the collage may be renamed or deleted later).
  final String projectTitle;
  final DateTime createdAt;

  /// [ExportFormat] name: png, jpg, gif, pdf, mp4.
  final String format;
  final String fileName;
  final ExportTarget target;

  /// Human-readable place, e.g. "Pictures/Collage" or "Google Drive/Prints".
  final String locationLabel;

  /// How to find the file again: a gallery asset id, a content:// URI or
  /// (iOS app files only) a file path.
  final String ref;
  final String mimeType;

  /// Number of files saved together (carousel slides, grid tiles).
  final int count;

  /// Small preview kept by the app, so the history shows even when the file
  /// itself is gone.
  final String? thumbPath;
  final int byteSize;

  ExportRecord copyWith({String? projectTitle}) => ExportRecord(
        id: id,
        projectId: projectId,
        projectTitle: projectTitle ?? this.projectTitle,
        createdAt: createdAt,
        format: format,
        fileName: fileName,
        target: target,
        locationLabel: locationLabel,
        ref: ref,
        mimeType: mimeType,
        count: count,
        thumbPath: thumbPath,
        byteSize: byteSize,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'projectId': projectId,
        'projectTitle': projectTitle,
        'createdAt': createdAt.millisecondsSinceEpoch,
        'format': format,
        'fileName': fileName,
        'target': target.name,
        'locationLabel': locationLabel,
        'ref': ref,
        'mimeType': mimeType,
        'count': count,
        if (thumbPath != null) 'thumbPath': thumbPath,
        'byteSize': byteSize,
      };

  static ExportRecord? fromJson(Map<String, dynamic> j) {
    final id = j['id'];
    final ref = j['ref'];
    if (id is! String || ref is! String) return null;
    return ExportRecord(
      id: id,
      projectId: j['projectId'] as String? ?? '',
      projectTitle: j['projectTitle'] as String? ?? '',
      createdAt: DateTime.fromMillisecondsSinceEpoch((j['createdAt'] as num?)?.toInt() ?? 0),
      format: j['format'] as String? ?? 'png',
      fileName: j['fileName'] as String? ?? '',
      target: ExportTarget.parse(j['target'] as String?),
      locationLabel: j['locationLabel'] as String? ?? '',
      ref: ref,
      mimeType: j['mimeType'] as String? ?? 'application/octet-stream',
      count: (j['count'] as num?)?.toInt() ?? 1,
      thumbPath: j['thumbPath'] as String?,
      byteSize: (j['byteSize'] as num?)?.toInt() ?? 0,
    );
  }
}

/// A file name built from the collage title and the time, safe on every file
/// system: "Summer in Bern 2026-11-03 14.12.png". Never empty.
String exportFileName(String title, DateTime at, String extension, {String? suffix}) {
  var base = title
      .replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1F]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  // Leading dots hide files on some systems.
  base = base.replaceFirst(RegExp(r'^\.+'), '').trim();
  if (base.length > 60) base = base.substring(0, 60).trim();
  if (base.isEmpty) base = 'Collage';
  String two(int v) => v.toString().padLeft(2, '0');
  final stamp = '${at.year}-${two(at.month)}-${two(at.day)} ${two(at.hour)}.${two(at.minute)}';
  return '$base $stamp${suffix == null ? '' : ' $suffix'}.$extension';
}

/// [name], or "name (2).ext", "name (3).ext", … — the first that is not in
/// [taken] (compared case-insensitively). Exports never overwrite a file.
String uniqueFileName(String name, Set<String> taken) {
  final lower = {for (final t in taken) t.toLowerCase()};
  if (!lower.contains(name.toLowerCase())) return name;
  final dot = name.lastIndexOf('.');
  final base = dot > 0 ? name.substring(0, dot) : name;
  final ext = dot > 0 ? name.substring(dot) : '';
  var i = 2;
  while (lower.contains('$base ($i)$ext'.toLowerCase())) {
    i++;
  }
  return '$base ($i)$ext';
}
