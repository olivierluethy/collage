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
import '../../widgets/mini_collage.dart';
import '../discover/discover_screen.dart';
import '../flow.dart';
import '../info/backup_actions.dart';
import '../info/info_screen.dart';
import '../templates/templates_tab.dart';
import 'new_collage_sheet.dart';

/// Home base with four tabs: My Collages (the re-editable library), Templates
/// (ready-made designs), Discover (location + date collage suggestions) and
/// More (photo books, trash, backup, settings, about). The app bar carries only
/// the title; every new collage starts from the one "New collage" button.
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key, this.startCreating = false});

  /// Open the new-collage flow straight away (from onboarding's "Pick photos").
  final bool startCreating;

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  int _index = 0;

  @override
  void initState() {
    super.initState();
    if (widget.startCreating) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) startNewCollage(context, ref);
      });
    }
  }

  void _newCollage() => showNewCollageSheet(
        context,
        ref,
        onBrowseTemplates: () => setState(() => _index = 1),
      );

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final title = switch (_index) {
      1 => l.t('tabTemplates'),
      2 => l.t('homeDiscover'),
      3 => l.t('tabMore'),
      _ => l.t('homeCollages'),
    };
    return Scaffold(
      appBar: AppBar(
        title: Text(title, style: context.text.displayMd),
        centerTitle: false,
      ),
      floatingActionButton: _index == 0 || _index == 2
          ? FloatingActionButton.extended(
              onPressed: _newCollage,
              icon: const Icon(Icons.add_rounded),
              label: Text(l.t('newCollage')),
            )
          : null,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: [
          NavigationDestination(
              icon: const Icon(Icons.photo_library_outlined),
              selectedIcon: const Icon(Icons.photo_library_rounded),
              label: l.t('tabCollages')),
          NavigationDestination(
              icon: const Icon(Icons.dashboard_customize_outlined),
              selectedIcon: const Icon(Icons.dashboard_customize_rounded),
              label: l.t('tabTemplates')),
          NavigationDestination(
              icon: const Icon(Icons.explore_outlined),
              selectedIcon: const Icon(Icons.explore_rounded),
              label: l.t('tabDiscover')),
          NavigationDestination(
              icon: const Icon(Icons.menu_rounded),
              selectedIcon: const Icon(Icons.menu_open_rounded),
              label: l.t('tabMore')),
        ],
      ),
      body: IndexedStack(
        index: _index,
        children: [
          _CollagesView(
            onCreate: () => startNewCollage(context, ref),
            onBrowseTemplates: () => setState(() => _index = 1),
          ),
          const TemplatesTab(),
          const DiscoverTab(),
          const MoreTab(),
        ],
      ),
    );
  }
}

/// The saved-collages library.
class _CollagesView extends ConsumerWidget {
  const _CollagesView({required this.onCreate, required this.onBrowseTemplates});
  final VoidCallback onCreate;
  final VoidCallback onBrowseTemplates;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final drafts = ref.watch(draftsProvider);
    return drafts.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => EmptyState(
              icon: Icons.error_outline_rounded,
              title: context.l10n.t('loadFailedTitle'),
              message: context.l10n.t('loadFailedMessage'),
              action: PrimaryButton(
                label: context.l10n.t('tryAgain'),
                icon: Icons.refresh_rounded,
                expand: false,
                onPressed: () => ref.read(draftsProvider.notifier).reload(),
              ),
            ),
        data: (list) {
          if (list.isEmpty) {
            return EmptyState(
              icon: Icons.photo_library_outlined,
              art: const MiniCollage(size: 168),
              title: context.l10n.t('noCollagesTitle'),
              message: context.l10n.t('noCollagesMessage'),
              action: PrimaryButton(
                label: context.l10n.t('createFirstCollage'),
                icon: Icons.add_rounded,
                expand: false,
                onPressed: onCreate,
              ),
              secondary: TextButton(
                onPressed: onBrowseTemplates,
                child: Text(context.l10n.t('browseTemplates')),
              ),
            );
          }
          return RefreshIndicator(
            onRefresh: () => ref.read(draftsProvider.notifier).reload(),
            child: GridView.builder(
              // Room at the bottom so the FAB never covers the last row.
              padding: const EdgeInsets.fromLTRB(Space.lg, Space.sm, Space.lg, 96),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                mainAxisSpacing: Space.md,
                crossAxisSpacing: Space.md,
                childAspectRatio: 0.82,
              ),
              itemCount: list.length,
              itemBuilder: (_, i) => _CollageCard(project: list[i]),
            ),
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
    return Semantics(
      button: true,
      label: project.title,
      child: Material(
        color: context.colors.surface,
        borderRadius: BorderRadius.circular(Radii.card),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => openCollage(context, ref, project),
          onLongPress: () => _showActions(context, ref),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(Radii.card),
              border: Border.all(color: context.colors.line),
            ),
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
                  padding: const EdgeInsets.fromLTRB(Space.md, Space.sm, 0, Space.sm),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(project.title,
                                style: context.text.labelLg, maxLines: 1, overflow: TextOverflow.ellipsis),
                            const SizedBox(height: 2),
                            Row(
                              children: [
                                SpecChip(project.ratioLabel),
                                const SizedBox(width: Space.xs),
                                Flexible(child: MetaDate(epochMillis: project.updatedAt)),
                              ],
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: context.l10n.t('moreActions'),
                        icon: const Icon(Icons.more_vert_rounded),
                        color: context.colors.textMid,
                        onPressed: () => _showActions(context, ref),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Card menu (⋯ or long-press): open, rename, duplicate, send or delete.
  Future<void> _showActions(BuildContext context, WidgetRef ref) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (sheet) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(Space.xl, 0, Space.xl, Space.sm),
              child: Text(project.title,
                  style: context.text.titleMd, maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
            ListTile(
              leading: const Icon(Icons.edit_rounded),
              title: Text(context.l10n.t('ctxEdit')),
              onTap: () => Navigator.pop(sheet, 'open'),
            ),
            ListTile(
              leading: const Icon(Icons.drive_file_rename_outline_rounded),
              title: Text(context.l10n.t('renameCollage')),
              onTap: () => Navigator.pop(sheet, 'rename'),
            ),
            ListTile(
              leading: const Icon(Icons.copy_rounded),
              title: Text(context.l10n.t('duplicateCollage')),
              onTap: () => Navigator.pop(sheet, 'duplicate'),
            ),
            ListTile(
              leading: const Icon(Icons.people_outline_rounded),
              title: Text(context.l10n.t('shareForEditing')),
              onTap: () => Navigator.pop(sheet, 'collab'),
            ),
            ListTile(
              leading: Icon(Icons.delete_outline_rounded, color: context.colors.danger),
              title: Text(context.l10n.t('moveToTrash'), style: TextStyle(color: context.colors.danger)),
              onTap: () => Navigator.pop(sheet, 'delete'),
            ),
          ],
        ),
      ),
    );
    if (!context.mounted) return;
    switch (action) {
      case 'open':
        await openCollage(context, ref, project);
      case 'rename':
        await _rename(context, ref);
      case 'duplicate':
        await ref.read(draftsProvider.notifier).duplicate(
              project.id,
              title: context.l10n.a('copyOfTitle', {'title': project.title}),
            );
      case 'collab':
        await shareCollageForEditing(context, ref, project.id);
      case 'delete':
        await _moveToTrash(context, ref);
    }
  }

  Future<void> _rename(BuildContext context, WidgetRef ref) async {
    final ctrl = TextEditingController(text: project.title);
    final title = await showDialog<String>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: Text(context.l10n.t('renameCollage')),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          maxLength: 60,
          textInputAction: TextInputAction.done,
          onSubmitted: (v) => Navigator.pop(dialog, v),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialog),
              child: Text(context.l10n.t('cancel'))),
          TextButton(
              onPressed: () => Navigator.pop(dialog, ctrl.text),
              child: Text(context.l10n.t('save'))),
        ],
      ),
    );
    ctrl.dispose();
    final t = title?.trim();
    if (t == null || t.isEmpty || t == project.title) return;
    await ref.read(draftsProvider.notifier).rename(project.id, t);
  }

  /// Deleting only moves the collage to the trash, so there's no "are you
  /// sure?" — the snackbar's Undo restores it on the spot.
  Future<void> _moveToTrash(BuildContext context, WidgetRef ref) async {
    final l = context.l10n;
    final notifier = ref.read(trashProvider.notifier);
    await ref.read(draftsProvider.notifier).remove(project.id);
    if (!context.mounted) return;
    showAppSnack(
      context,
      l.t('movedToTrash'),
      kind: SnackKind.success,
      actionLabel: l.t('undo'),
      onAction: () => notifier.restore(project.id),
    );
  }
}
