import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../../models/collage_project.dart';
import '../../state/providers.dart';
import '../../theme/palette.dart';
import '../../theme/tokens.dart';
import '../../theme/typography.dart';
import '../../widgets/meta_date.dart';
import '../../widgets/ui.dart';
import '../ai/ai_screen.dart';
import '../discover/discover_screen.dart';
import '../flow.dart';
import '../info/info_screen.dart';

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
        title: Text(_index == 0 ? context.l10n.t('homeCollages') : context.l10n.t('homeDiscover'),
            style: context.text.displayMd),
        actions: [
          IconButton(
            tooltip: context.l10n.t('aiAutoCollage'),
            icon: const Icon(Icons.auto_awesome_rounded),
            color: context.colors.amber,
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const AiScreen()),
            ),
          ),
          IconButton(
            tooltip: context.l10n.t('infoTitle'),
            icon: const Icon(Icons.info_outline_rounded),
            color: context.colors.textMid,
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const InfoScreen()),
            ),
          ),
        ],
      ),
      floatingActionButton: _index == 0
          ? FloatingActionButton.extended(
              onPressed: () => startNewCollage(context, ref),
              icon: const Icon(Icons.add_rounded),
              label: Text(context.l10n.t('newCollage')),
            )
          : null,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: [
          NavigationDestination(
              icon: const Icon(Icons.photo_library_outlined),
              selectedIcon: const Icon(Icons.photo_library_rounded),
              label: context.l10n.t('tabCollages')),
          NavigationDestination(
              icon: const Icon(Icons.explore_outlined),
              selectedIcon: const Icon(Icons.explore_rounded),
              label: context.l10n.t('tabDiscover')),
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
        error: (e, _) => Center(child: Text('$e', style: context.text.bodyMd)),
        data: (list) {
          if (list.isEmpty) {
            return EmptyState(
              icon: Icons.photo_library_outlined,
              title: context.l10n.t('noCollagesTitle'),
              message: context.l10n.t('noCollagesMessage'),
              action: PrimaryButton(
                label: context.l10n.t('newCollage'),
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
          color: context.colors.surface,
          borderRadius: BorderRadius.circular(Radii.card),
          border: Border.all(color: context.colors.line),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: project.thumbnailPath != null && File(project.thumbnailPath!).existsSync()
                  ? Image.file(File(project.thumbnailPath!), fit: BoxFit.cover)
                  : ColoredBox(
                      color: context.colors.surfaceInput,
                      child: Icon(Icons.image_outlined, color: context.colors.textLo),
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
                            style: context.text.labelLg, maxLines: 1, overflow: TextOverflow.ellipsis),
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
        title: Text(context.l10n.t('deleteCollageTitle')),
        content: Text(context.l10n.t('deleteCollageMessage')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(context.l10n.t('cancel'))),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(context.l10n.t('delete'), style: TextStyle(color: context.colors.danger)),
          ),
        ],
      ),
    );
    if (ok == true) {
      await ref.read(draftsProvider.notifier).remove(project.id);
    }
  }
}
