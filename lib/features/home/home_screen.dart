import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/collage_project.dart';
import '../../state/providers.dart';
import '../../theme/text_styles.dart';
import '../../theme/tokens.dart';
import '../../widgets/meta_date.dart';
import '../../widgets/ui.dart';
import '../ai/ai_screen.dart';
import '../discover/discover_screen.dart';
import '../flow.dart';

/// Home base with two tabs: My Collages (the re-editable library) and Discover
/// (location + date collage suggestions).
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_index == 0 ? 'My collages' : 'Discover', style: AppText.displayMd),
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
      floatingActionButton: _index == 0
          ? FloatingActionButton.extended(
              onPressed: () => startNewCollage(context, ref),
              icon: const Icon(Icons.add_rounded),
              label: const Text('New collage'),
            )
          : null,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.photo_library_outlined), selectedIcon: Icon(Icons.photo_library_rounded), label: 'Collages'),
          NavigationDestination(icon: Icon(Icons.explore_outlined), selectedIcon: Icon(Icons.explore_rounded), label: 'Discover'),
        ],
      ),
      body: IndexedStack(
        index: _index,
        children: const [_CollagesView(), DiscoverTab()],
      ),
    );
  }
}

/// The saved-collages library.
class _CollagesView extends ConsumerWidget {
  const _CollagesView();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final drafts = ref.watch(draftsProvider);
    return drafts.when(
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
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(project.title,
                            style: AppText.labelLg, maxLines: 1, overflow: TextOverflow.ellipsis),
                      ),
                      SpecChip(project.ratioLabel),
                    ],
                  ),
                  const SizedBox(height: 2),
                  MetaDate(epochMillis: project.createdAt),
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
