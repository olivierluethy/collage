import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/collage_project.dart';
import '../flow.dart';
import 'photo_picker_screen.dart';

/// What changed between two photo selections.
@immutable
class PhotoSelectionDiff {
  const PhotoSelectionDiff({required this.added, required this.removed});

  /// Ids in the new selection that weren't there before, in their new order.
  final List<String> added;

  /// Ids that were in the old selection and are gone now, in their old order.
  final List<String> removed;

  /// True when photos were added or removed (a pure reorder is not a change).
  bool get hasChanges => added.isNotEmpty || removed.isNotEmpty;
}

/// Compare two ordered selections of asset ids.
PhotoSelectionDiff diffSelection(List<String> before, List<String> after) {
  final b = before.toSet();
  final a = after.toSet();
  return PhotoSelectionDiff(
    added: [for (final id in after.toSet()) if (!b.contains(id)) id],
    removed: [for (final id in before.toSet()) if (!a.contains(id)) id],
  );
}

/// Choose the photos for a collage: makes sure the app may read the gallery,
/// then opens the picker with [current] already selected (in order) and
/// returns the full, ordered final selection — or null when the user backs
/// out (or leaves for another collage via "Open it").
///
/// [collageId] is the collage being edited: it's left out of the "already
/// used" badges and the duplicate hint. [placed] are the photos currently in
/// the collage's slots (defaults to [current]); deselecting one shows a note
/// that it will be taken out. A call with no [current] and no [collageId] is
/// a brand-new collage: the picker starts at 0 and says "Create collage".
Future<List<String>?> pickCollagePhotos(
  BuildContext context,
  WidgetRef ref, {
  List<String> current = const [],
  String? collageId,
  int max = 9,
  Set<String>? placed,
}) async {
  if (!await ensureGalleryAccess(context, ref)) return null;
  if (!context.mounted) return null;

  CollageProject? openInstead;
  final picked = await Navigator.of(context).push<List<String>>(
    MaterialPageRoute(
      builder: (_) => PhotoPickerScreen(
        maxImages: max,
        newCollage: current.isEmpty && collageId == null,
        initialSelection: current,
        placed: placed,
        collageId: collageId,
        onOpenCollage: (p) => openInstead = p,
      ),
    ),
  );

  final other = openInstead;
  if (other != null) {
    if (context.mounted) await openCollage(context, ref, other);
    return null;
  }
  return picked;
}
