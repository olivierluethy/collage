import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../l10n/app_localizations.dart';
import '../../l10n/plural.dart';
import '../../models/collage_project.dart';
import '../../state/providers.dart';
import '../../theme/palette.dart';
import '../../theme/tokens.dart';
import '../../theme/typography.dart';
import '../../widgets/meta_date.dart';
import '../../widgets/mini_collage.dart';
import '../../widgets/ui.dart';
import 'collage_card.dart';
import 'library_actions.dart';
import 'library_query.dart';
import 'library_sheets.dart';
import 'library_state.dart';

/// The My Collages tab: search, filters, sort, an optional activity strip and
/// a month-grouped, virtualised grid with sticky month headers, a jump-to
/// picker and multi-select.
class LibraryView extends ConsumerStatefulWidget {
  const LibraryView({super.key, required this.onCreate, required this.onBrowseTemplates});
  final VoidCallback onCreate;
  final VoidCallback onBrowseTemplates;

  @override
  ConsumerState<LibraryView> createState() => _LibraryViewState();
}

/// Grid geometry for one width, shared by the slivers and the jump maths.
class _Metrics {
  _Metrics(this.cols, this.tileExtent, this.headerExtent);
  final int cols;
  final double tileExtent;
  final double headerExtent;
}

class _LibraryViewState extends ConsumerState<LibraryView> {
  final _search = TextEditingController();
  final _scroll = ScrollController();
  final _topKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _search.text = ref.read(libraryQueryProvider).text;
  }

  @override
  void dispose() {
    _search.dispose();
    _scroll.dispose();
    super.dispose();
  }

  LibraryQuery get _q => ref.read(libraryQueryProvider);
  void _setQuery(LibraryQuery q) {
    ref.read(libraryQueryProvider.notifier).state = q;
    if (_search.text != q.text) _search.text = q.text;
  }

  _Metrics _metrics(double width) {
    final ts = MediaQuery.textScalerOf(context);
    final cols = width < 560
        ? 2
        : width < 840
        ? 3
        : width < 1100
        ? 4
        : 5;
    final tileW = (width - 2 * Space.lg - (cols - 1) * Space.md) / cols;
    // Info block under the preview: padding, title, ratio chip, two date lines.
    final info =
        Space.sm +
        Space.md +
        ts.scale(15) * 1.25 +
        Space.xs +
        math.max(ts.scale(13) * 1.1 + 8, 24) +
        Space.xs +
        ts.scale(12) * 1.45 * 2 +
        4;
    final header = math.max(Sizes.touchTarget, ts.scale(18) * 1.3 + 20);
    return _Metrics(cols, tileW * 0.8 + info, header);
  }

  double _sectionExtent(_Metrics m, int items, {required bool header}) {
    final rows = (items / m.cols).ceil();
    return (header ? m.headerExtent : Space.sm) +
        rows * m.tileExtent +
        math.max(0, rows - 1) * Space.md +
        Space.lg;
  }

  Future<void> _jump(List<MonthSection> sections, _Metrics m) async {
    final picked = await showJumpToMonth(
      context,
      months: [for (final s in sections) (s.month, s.items.length)],
      current: _currentMonth(sections, m),
    );
    if (picked == null || !mounted || !_scroll.hasClients) return;
    final top = (_topKey.currentContext?.findRenderObject() as RenderBox?)?.size.height ?? 0;
    var offset = top;
    for (final s in sections) {
      if (s.month == picked) break;
      offset += _sectionExtent(m, s.items.length, header: true);
    }
    final target = math.min(offset, _scroll.position.maxScrollExtent);
    if (MediaQuery.disableAnimationsOf(context)) {
      _scroll.jumpTo(target);
    } else {
      await _scroll.animateTo(target, duration: Motion.slow, curve: Motion.standard);
    }
  }

  /// The month whose header is pinned right now, for the jump sheet.
  DateTime? _currentMonth(List<MonthSection> sections, _Metrics m) {
    if (!_scroll.hasClients || sections.isEmpty) return null;
    final top = (_topKey.currentContext?.findRenderObject() as RenderBox?)?.size.height ?? 0;
    var at = top;
    for (final s in sections) {
      at += _sectionExtent(m, s.items.length, header: true);
      if (at > _scroll.offset) return s.month;
    }
    return sections.last.month;
  }

  Future<void> _openFilters(List<CollageProject> all) async {
    final q = await showLibraryFilterSheet(context, all: all, query: _q);
    if (q != null) _setQuery(q);
  }

  Future<void> _trashShown(List<CollageProject> shown) async {
    final l = context.l10n;
    final period = _q.period;
    await confirmMoveToTrash(context, ref, [
      for (final p in shown) p.id,
    ], note: period == null ? null : l.a('libCreatedIn', {'period': periodLabel(context, period)}));
  }

  @override
  Widget build(BuildContext context) {
    final drafts = ref.watch(draftsProvider);
    final l = context.l10n;
    return drafts.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => EmptyState(
        icon: Icons.error_outline_rounded,
        title: l.t('loadFailedTitle'),
        message: l.t('loadFailedMessage'),
        action: PrimaryButton(
          label: l.t('tryAgain'),
          icon: Icons.refresh_rounded,
          expand: false,
          onPressed: () => ref.read(draftsProvider.notifier).reload(),
        ),
      ),
      data: (all) {
        if (all.isEmpty) {
          return EmptyState(
            icon: Icons.photo_library_outlined,
            art: const MiniCollage(size: 168),
            title: l.t('noCollagesTitle'),
            message: l.t('noCollagesMessage'),
            action: PrimaryButton(
              label: l.t('createFirstCollage'),
              icon: Icons.add_rounded,
              expand: false,
              onPressed: widget.onCreate,
            ),
            secondary: TextButton(onPressed: widget.onBrowseTemplates, child: Text(l.t('browseTemplates'))),
          );
        }
        return _buildLibrary(context, all);
      },
    );
  }

  Widget _buildLibrary(BuildContext context, List<CollageProject> all) {
    final l = context.l10n;
    final q = ref.watch(libraryQueryProvider);
    final selection = ref.watch(librarySelectionProvider);
    final selecting = selection != null;
    final shown = applyLibraryQuery(all, q, l);
    final sections = groupByMonth(shown, q.sort);
    final headers = q.sort != LibrarySort.title;
    // Keep the start screen calm when there's little to manage: search, filter
    // and sort only earn their place once the library is big enough to need
    // them (or a query is already active, so it always stays reachable).
    final showControls = all.length > 8 || q.hasFilters || q.text.isNotEmpty;

    return Column(
      children: [
        if (showControls)
          _SearchRow(
            controller: _search,
            query: q,
            onText: (t) => ref.read(libraryQueryProvider.notifier).state = _q.copyWith(text: t),
            onClear: () => _setQuery(_q.copyWith(text: '')),
            onFilters: () => _openFilters(all),
            onSort: (s) => _setQuery(_q.copyWith(sort: s)),
          ),
        Expanded(
          child: LayoutBuilder(
            builder: (context, box) {
              final m = _metrics(box.maxWidth);
              return RefreshIndicator(
                onRefresh: () => ref.read(draftsProvider.notifier).reload(),
                child: Scrollbar(
                  controller: _scroll,
                  interactive: true,
                  child: CustomScrollView(
                    controller: _scroll,
                    slivers: [
                      SliverToBoxAdapter(
                        child: Column(
                          key: _topKey,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (q.chipCount > 0) _ActiveFilters(query: q, onChanged: _setQuery),
                            _ResultsRow(
                              count: shown.length,
                              canJump: headers && sections.length > 1,
                              canSelect: shown.isNotEmpty && !selecting,
                              canTrashShown: q.hasFilters && shown.isNotEmpty,
                              onJump: () => _jump(sections, m),
                              onSelect: () => ref.startSelecting(),
                              onTrashShown: () => _trashShown(shown),
                            ),
                            const SizedBox(height: Space.sm),
                          ],
                        ),
                      ),
                      if (shown.isEmpty)
                        SliverFillRemaining(
                          hasScrollBody: false,
                          child: _NoMatches(onClear: () => _setQuery(LibraryQuery(sort: q.sort))),
                        ),
                      for (final s in sections)
                        SliverMainAxisGroup(
                          slivers: [
                            if (headers)
                              SliverPersistentHeader(
                                pinned: true,
                                delegate: _MonthHeader(
                                  extent: m.headerExtent,
                                  month: s.month,
                                  count: s.items.length,
                                  onTap: sections.length > 1 ? () => _jump(sections, m) : null,
                                ),
                              ),
                            SliverPadding(
                              padding: EdgeInsets.fromLTRB(
                                Space.lg,
                                headers ? 0 : Space.sm,
                                Space.lg,
                                Space.lg,
                              ),
                              sliver: SliverGrid(
                                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: m.cols,
                                  mainAxisSpacing: Space.md,
                                  crossAxisSpacing: Space.md,
                                  mainAxisExtent: m.tileExtent,
                                ),
                                delegate: SliverChildBuilderDelegate(
                                  (_, i) {
                                    final p = s.items[i];
                                    return LibraryCollageCard(
                                      key: ValueKey(p.id),
                                      project: p,
                                      stampMillis: shownStamp(p, q.sort),
                                      selecting: selecting,
                                      selected: selection?.contains(p.id) ?? false,
                                    );
                                  },
                                  childCount: s.items.length,
                                  findChildIndexCallback: (key) {
                                    final id = (key as ValueKey<String>).value;
                                    final i = s.items.indexWhere((p) => p.id == id);
                                    return i < 0 ? null : i;
                                  },
                                ),
                              ),
                            ),
                          ],
                        ),
                      // Room at the bottom so the FAB never covers the last row.
                      const SliverToBoxAdapter(child: SizedBox(height: 96)),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _SearchRow extends StatelessWidget {
  const _SearchRow({
    required this.controller,
    required this.query,
    required this.onText,
    required this.onClear,
    required this.onFilters,
    required this.onSort,
  });

  final TextEditingController controller;
  final LibraryQuery query;
  final ValueChanged<String> onText;
  final VoidCallback onClear;
  final VoidCallback onFilters;
  final ValueChanged<LibrarySort> onSort;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final c = context.colors;
    final sorts = {
      LibrarySort.newest: l.t('libSortNewest'),
      LibrarySort.oldest: l.t('libSortOldest'),
      LibrarySort.edited: l.t('libSortEdited'),
      LibrarySort.title: l.t('libSortTitle'),
    };
    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.lg, Space.sm, Space.sm, Space.xs),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              onChanged: onText,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: l.t('libSearchHint'),
                isDense: true,
                prefixIcon: Icon(Icons.search_rounded, color: c.textLo),
                suffixIcon: ValueListenableBuilder(
                  valueListenable: controller,
                  builder: (_, v, __) => v.text.isEmpty
                      ? const SizedBox.shrink()
                      : IconButton(
                          tooltip: l.t('libClearSearch'),
                          icon: const Icon(Icons.close_rounded),
                          onPressed: onClear,
                        ),
                ),
              ),
            ),
          ),
          const SizedBox(width: Space.xs),
          IconButton(
            tooltip: query.chipCount == 0 ? l.t('libFilters') : '${l.t('libFilters')} (${query.chipCount})',
            onPressed: onFilters,
            icon: Badge(
              isLabelVisible: query.chipCount > 0,
              backgroundColor: c.amber,
              textColor: c.onAmber,
              label: Text('${query.chipCount}'),
              child: Icon(Icons.tune_rounded, color: query.chipCount > 0 ? c.amber : c.textMid),
            ),
          ),
          PopupMenuButton<LibrarySort>(
            tooltip: '${l.t('libSort')}: ${sorts[query.sort]}',
            icon: Icon(Icons.swap_vert_rounded, color: c.textMid),
            initialValue: query.sort,
            onSelected: onSort,
            itemBuilder: (_) => [
              for (final e in sorts.entries)
                CheckedPopupMenuItem(value: e.key, checked: e.key == query.sort, child: Text(e.value)),
            ],
          ),
        ],
      ),
    );
  }
}

/// The active filters as removable chips.
class _ActiveFilters extends StatelessWidget {
  const _ActiveFilters({required this.query, required this.onChanged});
  final LibraryQuery query;
  final ValueChanged<LibraryQuery> onChanged;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final chips = <(String, IconData, LibraryQuery)>[
      if (query.period != null)
        (periodLabel(context, query.period!), Icons.event_rounded, query.copyWith(period: null)),
      if (query.style != null)
        (
          templateStyleLabel(l, query.style!),
          Icons.dashboard_customize_outlined,
          query.copyWith(style: null),
        ),
      if (query.occasion != null)
        (occasionLabel(l, query.occasion!), Icons.celebration_outlined, query.copyWith(occasion: null)),
      if (query.ratio != null) (query.ratio!, Icons.aspect_ratio_rounded, query.copyWith(ratio: null)),
      if (query.hasVideo) (l.t('libHasVideo'), Icons.videocam_outlined, query.copyWith(hasVideo: false)),
    ];
    return SizedBox(
      height: 56,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: Space.lg, vertical: Space.xs),
        children: [
          for (final (label, icon, without) in chips) ...[
            InputChip(
              avatar: Icon(icon, size: 18),
              label: Text(label),
              onPressed: () => onChanged(without),
              onDeleted: () => onChanged(without),
              deleteButtonTooltipMessage: l.a('libRemoveFilter', {'name': label}),
            ),
            const SizedBox(width: Space.sm),
          ],
          if (chips.length > 1)
            TextButton(onPressed: () => onChanged(query.clearedFilters()), child: Text(l.t('libClearAll'))),
        ],
      ),
    );
  }
}

class _ResultsRow extends StatelessWidget {
  const _ResultsRow({
    required this.count,
    required this.canJump,
    required this.canSelect,
    required this.canTrashShown,
    required this.onJump,
    required this.onSelect,
    required this.onTrashShown,
  });

  final int count;
  final bool canJump;
  final bool canSelect;
  final bool canTrashShown;
  final VoidCallback onJump;
  final VoidCallback onSelect;
  final VoidCallback onTrashShown;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.lg, 0, Space.xs, 0),
      child: Row(
        children: [
          Expanded(
            child: Semantics(
              liveRegion: true,
              child: Text(l.p('libCount', count), style: context.text.labelMd.copyWith(color: c.textMid)),
            ),
          ),
          if (canJump)
            TextButton.icon(
              onPressed: onJump,
              icon: const Icon(Icons.calendar_month_rounded, size: 18),
              label: Text(l.t('libJumpTo')),
            ),
          if (canSelect)
            TextButton.icon(
              onPressed: onSelect,
              icon: const Icon(Icons.check_circle_outline_rounded, size: 18),
              label: Text(l.t('libSelect')),
            ),
          if (canTrashShown)
            PopupMenuButton<int>(
              tooltip: l.t('moreActions'),
              icon: Icon(Icons.more_vert_rounded, color: c.textMid),
              onSelected: (_) => onTrashShown(),
              itemBuilder: (_) => [
                PopupMenuItem(
                  value: 0,
                  child: Row(
                    children: [
                      Icon(Icons.delete_outline_rounded, color: c.danger),
                      const SizedBox(width: Space.md),
                      Flexible(
                        child: Text(l.a('libTrashShown', {'n': '$count'}), style: TextStyle(color: c.danger)),
                      ),
                    ],
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class _NoMatches extends StatelessWidget {
  const _NoMatches({required this.onClear});
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.all(Space.xl),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.search_off_rounded, size: 40, color: c.textLo),
          const SizedBox(height: Space.md),
          Text(l.t('libNoMatchesTitle'), style: context.text.titleMd, textAlign: TextAlign.center),
          const SizedBox(height: Space.sm),
          Text(
            l.t('libNoMatchesMessage'),
            style: context.text.bodyMd.copyWith(color: c.textMid),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: Space.lg),
          TextButton(onPressed: onClear, child: Text(l.t('libClearFilters'))),
        ],
      ),
    );
  }
}

/// Sticky month header: "November 2026 · 12". Tapping it opens the jump-to
/// picker.
class _MonthHeader extends SliverPersistentHeaderDelegate {
  _MonthHeader({required this.extent, required this.month, required this.count, required this.onTap});

  final double extent;
  final DateTime month;
  final int count;
  final VoidCallback? onTap;

  @override
  double get minExtent => extent;
  @override
  double get maxExtent => extent;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    final l = context.l10n;
    final c = context.colors;
    String label;
    try {
      label = DateFormat.yMMMM(dateLocaleOf(context)).format(month);
    } catch (_) {
      label = DateFormat.yMMMM('en').format(month);
    }
    // The sliver hands its child loose constraints: fill the whole extent,
    // or the header paints less than it reserves (an invalid geometry that
    // asserts in debug and leaves a see-through strip in release).
    return SizedBox.expand(
      child: Material(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: Semantics(
        header: true,
        button: onTap != null,
        label: l.a('libMonthHeader', {'period': label, 'count': l.p('libCount', count)}),
        hint: onTap == null ? null : l.t('libJumpTitle'),
        excludeSemantics: true,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: Space.lg),
            child: Row(
              children: [
                Flexible(
                  child: Text(
                    label,
                    style: context.text.titleMd,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: Space.sm),
                SpecChip('$count'),
                const Spacer(),
                if (onTap != null) Icon(Icons.unfold_more_rounded, size: 20, color: c.textLo),
              ],
            ),
          ),
        ),
      ),
      ),
    );
  }

  @override
  bool shouldRebuild(_MonthHeader old) =>
      old.extent != extent ||
      old.month != month ||
      old.count != count ||
      (old.onTap == null) != (onTap == null);
}

/// App bar shown in selection mode: Cancel, "3 selected" and a menu with the
/// explicit "Select all collages (312)".
class LibrarySelectionAppBar extends ConsumerWidget implements PreferredSizeWidget {
  const LibrarySelectionAppBar({super.key});

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final n = liveSelection(ref).length;
    final total = allCollages(ref).length;
    return AppBar(
      leading: IconButton(
        tooltip: l.t('cancel'),
        icon: const Icon(Icons.close_rounded),
        onPressed: ref.stopSelecting,
      ),
      title: Semantics(liveRegion: true, child: Text(l.a('libSelectedCount', {'n': '$n'}))),
      actions: [
        PopupMenuButton<String>(
          tooltip: l.t('moreActions'),
          onSelected: (v) {
            if (v == 'all') {
              ref.selectIds(allCollages(ref).map((p) => p.id));
            } else {
              ref.selectIds(const []);
            }
          },
          itemBuilder: (_) => [
            PopupMenuItem(value: 'all', child: Text(l.a('libSelectAllCollages', {'n': '$total'}))),
            PopupMenuItem(value: 'none', enabled: n > 0, child: Text(l.t('libClearSelection'))),
          ],
        ),
      ],
    );
  }
}

/// Bottom bar shown in selection mode: "Select all 24 shown" and "Move to
/// trash" (confirmed with the exact count).
class LibrarySelectionBar extends ConsumerWidget {
  const LibrarySelectionBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final c = context.colors;
    final shown = visibleCollages(ref, l);
    final sel = liveSelection(ref);
    final allShownSelected = shown.isNotEmpty && shown.every((p) => sel.contains(p.id));
    return Material(
      color: c.surface,
      child: SafeArea(
        top: false,
        child: Container(
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: c.line)),
          ),
          padding: const EdgeInsets.fromLTRB(Space.lg, Space.md, Space.lg, Space.md),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: shown.isEmpty || allShownSelected
                      ? null
                      : () => ref.selectIds({...sel, ...shown.map((p) => p.id)}),
                  style: OutlinedButton.styleFrom(minimumSize: const Size(0, Sizes.touchTarget)),
                  child: Text(
                    l.a('libSelectAllShown', {'n': '${shown.length}'}),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
              const SizedBox(width: Space.md),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: sel.isEmpty ? null : () => confirmMoveToTrash(context, ref, sel.toList()),
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size(0, Sizes.touchTarget),
                    backgroundColor: c.danger,
                    foregroundColor: c.onDanger,
                  ),
                  icon: const Icon(Icons.delete_outline_rounded),
                  label: Text(l.t('moveToTrash'), textAlign: TextAlign.center),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
