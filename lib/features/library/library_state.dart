import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../../models/collage_project.dart';
import '../../state/providers.dart';
import 'library_query.dart';

/// Search, filters and sort of the My Collages tab.
final libraryQueryProvider = StateProvider<LibraryQuery>((_) => const LibraryQuery());

/// Ids picked in selection mode; null when not selecting.
final librarySelectionProvider = StateProvider<Set<String>?>((_) => null);

/// Every saved collage (empty while loading).
List<CollageProject> allCollages(WidgetRef ref) => ref.watch(draftsProvider).valueOrNull ?? const [];

/// The collages the current search and filters show, in list order.
List<CollageProject> visibleCollages(WidgetRef ref, AppLocalizations l) =>
    applyLibraryQuery(allCollages(ref), ref.watch(libraryQueryProvider), l);

/// The current selection, limited to collages that still exist.
Set<String> liveSelection(WidgetRef ref) {
  final sel = ref.watch(librarySelectionProvider);
  if (sel == null || sel.isEmpty) return const {};
  final ids = {for (final p in allCollages(ref)) p.id};
  return sel.intersection(ids);
}

extension LibrarySelection on WidgetRef {
  bool get selecting => read(librarySelectionProvider) != null;

  void startSelecting([String? firstId]) =>
      read(librarySelectionProvider.notifier).state = {if (firstId != null) firstId};

  void stopSelecting() => read(librarySelectionProvider.notifier).state = null;

  void toggleSelected(String id) {
    final cur = {...?read(librarySelectionProvider)};
    if (!cur.remove(id)) cur.add(id);
    read(librarySelectionProvider.notifier).state = cur;
  }

  void selectIds(Iterable<String> ids) => read(librarySelectionProvider.notifier).state = ids.toSet();
}
