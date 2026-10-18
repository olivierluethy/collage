import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../data/layout_templates.dart';
import '../models/collage_project.dart';
import '../models/collage_template.dart';
import '../models/layout_template.dart';
import '../services/permission_service.dart';
import '../state/providers.dart';
import 'editor/editor_screen.dart';
import 'layout/layout_picker_screen.dart';
import 'permission/permission_screen.dart';
import 'picker/photo_picker_screen.dart';

/// The result of the layout picker: which template and canvas ratio.
class LayoutChoice {
  const LayoutChoice(this.template, this.ratioLabel);
  final LayoutTemplate template;
  final String ratioLabel;
}

/// Ensures gallery access, prompting the guided permission flow if needed.
Future<bool> ensureGalleryAccess(BuildContext context, WidgetRef ref) async {
  final perm = ref.read(permissionServiceProvider);
  final current = await perm.current();
  if (current.usable) return true;
  if (!context.mounted) return false;
  final granted = await Navigator.of(context).push<bool>(
        MaterialPageRoute(builder: (_) => const PermissionScreen()),
      ) ??
      false;
  return granted;
}

/// Full "New collage" flow: permission → pick photos → choose layout → editor.
Future<void> startNewCollage(BuildContext context, WidgetRef ref) async {
  if (!await ensureGalleryAccess(context, ref)) return;
  if (!context.mounted) return;

  final picked = await Navigator.of(context).push<List<String>>(
    MaterialPageRoute(builder: (_) => const PhotoPickerScreen(maxImages: 9)),
  );
  if (picked == null || picked.isEmpty || !context.mounted) return;

  final choice = await Navigator.of(context).push<LayoutChoice>(
    MaterialPageRoute(builder: (_) => LayoutPickerScreen(count: picked.length)),
  );
  if (choice == null || !context.mounted) return;

  final now = DateTime.now().millisecondsSinceEpoch;
  final project = CollageProject(
    id: const Uuid().v4(),
    title: 'Collage',
    createdAt: now,
    updatedAt: now,
    ratioLabel: choice.ratioLabel,
    layout: choice.template,
    fills: {},
    elements: [],
    border: BorderSettings(),
    background: BackgroundSettings(),
  );

  await Navigator.of(context).push(
    MaterialPageRoute(builder: (_) => EditorScreen(project: project, pool: picked)),
  );
  await ref.read(draftsProvider.notifier).reload();
}

/// Open a set of photos directly as a new, editable collage with a sensible
/// auto-layout (used by Discover moments and AI suggestions).
Future<void> openPhotosAsCollage(
  BuildContext context,
  WidgetRef ref,
  List<String> assetIds, {
  String title = 'Collage',
}) async {
  final pool = assetIds.take(9).toList();
  if (pool.isEmpty) return;
  final layout = LayoutTemplates.forCount(pool.length.clamp(1, 9)).first;
  final now = DateTime.now().millisecondsSinceEpoch;
  final project = CollageProject(
    id: const Uuid().v4(),
    title: title,
    createdAt: now,
    updatedAt: now,
    ratioLabel: CanvasRatio.square.label,
    layout: layout,
    fills: {},
    elements: [],
    border: BorderSettings(),
    background: BackgroundSettings(),
  );
  await Navigator.of(context).push(
    MaterialPageRoute(builder: (_) => EditorScreen(project: project, pool: pool)),
  );
  if (context.mounted) await ref.read(draftsProvider.notifier).reload();
}

/// Re-open a saved collage for editing.
Future<void> openCollage(BuildContext context, WidgetRef ref, CollageProject project) async {
  final pool = <String>{
    ...project.fills.values.map((f) => f.assetId),
  }.toList();
  await Navigator.of(context).push(
    MaterialPageRoute(builder: (_) => EditorScreen(project: project, pool: pool)),
  );
  if (context.mounted) await ref.read(draftsProvider.notifier).reload();
}

/// Open a ready-made template in the editor with empty slots: the styling,
/// background, text and stickers are applied, and the user drops their own
/// photos into the slots. No gallery permission is needed up front — the
/// editor asks for it when the user picks photos.
Future<void> openTemplate(
  BuildContext context,
  WidgetRef ref,
  CollageTemplate template,
) async {
  final project = template.toProject(
    id: const Uuid().v4(),
    now: DateTime.now().millisecondsSinceEpoch,
  );
  await Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => EditorScreen(project: project, pool: const []),
    ),
  );
  if (context.mounted) await ref.read(draftsProvider.notifier).reload();
}
