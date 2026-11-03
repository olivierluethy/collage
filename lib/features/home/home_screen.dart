import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../../theme/typography.dart';
import '../discover/discover_screen.dart';
import '../flow.dart';
import '../info/info_screen.dart';
import '../library/library_state.dart';
import '../library/library_view.dart';
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

  void _newCollage() =>
      showNewCollageSheet(context, ref, onBrowseTemplates: () => setState(() => _index = 1));

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final title = switch (_index) {
      1 => l.t('tabTemplates'),
      2 => l.t('homeDiscover'),
      3 => l.t('tabMore'),
      _ => l.t('homeCollages'),
    };
    // Selection mode in My Collages swaps the app bar and the bottom bar; back
    // leaves selection mode instead of the app.
    final selecting = _index == 0 && ref.watch(librarySelectionProvider) != null;
    return PopScope(
      canPop: !selecting,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && selecting) ref.stopSelecting();
      },
      child: Scaffold(
        appBar: selecting
            ? const LibrarySelectionAppBar()
            : AppBar(title: Text(title, style: context.text.displayMd), centerTitle: false),
        floatingActionButton: !selecting && (_index == 0 || _index == 2)
            ? FloatingActionButton.extended(
                onPressed: _newCollage,
                icon: const Icon(Icons.add_rounded),
                label: Text(l.t('newCollage')),
              )
            : null,
        bottomNavigationBar: selecting
            ? const LibrarySelectionBar()
            : NavigationBar(
                selectedIndex: _index,
                onDestinationSelected: (i) => setState(() => _index = i),
                destinations: [
                  NavigationDestination(
                    icon: const Icon(Icons.photo_library_outlined),
                    selectedIcon: const Icon(Icons.photo_library_rounded),
                    label: l.t('tabCollages'),
                  ),
                  NavigationDestination(
                    icon: const Icon(Icons.dashboard_customize_outlined),
                    selectedIcon: const Icon(Icons.dashboard_customize_rounded),
                    label: l.t('tabTemplates'),
                  ),
                  NavigationDestination(
                    icon: const Icon(Icons.explore_outlined),
                    selectedIcon: const Icon(Icons.explore_rounded),
                    label: l.t('tabDiscover'),
                  ),
                  NavigationDestination(
                    icon: const Icon(Icons.menu_rounded),
                    selectedIcon: const Icon(Icons.menu_open_rounded),
                    label: l.t('tabMore'),
                  ),
                ],
              ),
        body: IndexedStack(
          index: _index,
          children: [
            LibraryView(
              onCreate: () => startNewCollage(context, ref),
              onBrowseTemplates: () => setState(() => _index = 1),
            ),
            const TemplatesTab(),
            const DiscoverTab(),
            const MoreTab(),
          ],
        ),
      ),
    );
  }
}
