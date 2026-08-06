import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/collage_project.dart';
import '../../state/providers.dart';
import '../../theme/text_styles.dart';
import '../../theme/tokens.dart';
import '../../widgets/ui.dart';
import '../ai/ai_screen.dart';
import '../flow.dart';

/// "My Collages" library — the home base. Every finished collage lands here and
/// can be re-opened and edited.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final drafts = ref.watch(draftsProvider);
    return Scaffold(
      appBar: AppBar(
        title: Text('Collage', style: AppText.displayMd),
        actions: [
          IconButton(
            tooltip: 'AI auto-collage',
            icon: const Icon(Icons.auto_awesome_rounded),
            color: AppColors.amber,
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const AiScreen()),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => startNewCollage(context, ref),
        icon: const Icon(Icons.add_rounded),
        label: const Text('New collage'),
      ),
      body: drafts.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('$e', style: AppText.bodyMd)),
        data: (list) {
          if (list.isEmpty) {
            return EmptyState(
              icon: Icons.photo_library_outlined,
              title: 'No collages yet',
              message: 'Make your first collage — pick photos, choose a layout, '
                  'and decide exactly where each photo goes.',
              action: PrimaryButton(
                label: 'New collage',
                icon: Icons.add_rounded,
                expand: false,
                onPressed: () => startNewCollage(context, ref),
              ),
            );
          }
          return GridView.builder(
            padding: const EdgeInsets.all(Space.lg),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisSpacing: Space.md,
              crossAxisSpacing: Space.md,
            ),
            itemCount: list.length,
            itemBuilder: (_, i) => _CollageCard(project: list[i]),
          );
        },
      ),
    );
  }
}

class _CollageCard extends ConsumerWidget {
  const _CollageCard({required this.project});
  final CollageProject project;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return GestureDetector(
      onTap: () => openCollage(context, ref, project),
      onLongPress: () => _confirmDelete(context, ref),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(Radii.card),
          border: Border.all(color: AppColors.line),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: project.thumbnailPath != null && File(project.thumbnailPath!).existsSync()
                  ? Image.file(File(project.thumbnailPath!), fit: BoxFit.cover)
                  : const ColoredBox(
                      color: AppColors.surfaceInput,
                      child: Icon(Icons.image_outlined, color: AppColors.textLo),
                    ),
            ),
            Padding(
              padding: const EdgeInsets.all(Space.sm),
              child: Row(
                children: [
                  Expanded(
                    child: Text(project.title,
                        style: AppText.labelLg, maxLines: 1, overflow: TextOverflow.ellipsis),
                  ),
                  SpecChip(project.ratioLabel),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete this collage?'),
        content: const Text('This removes it from My Collages. Photos already '
            'saved to your gallery are not affected.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete', style: TextStyle(color: AppColors.danger)),
          ),
        ],
      ),
    );
    if (ok == true) {
      await ref.read(draftsProvider.notifier).remove(project.id);
    }
  }
}
