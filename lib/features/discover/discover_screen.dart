import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../l10n/app_localizations.dart';
import '../../services/library_index_service.dart';
import '../../services/moments_service.dart';
import '../../services/permission_service.dart';
import '../../state/library_index.dart';
import '../../state/occasions.dart';
import '../../state/providers.dart';
import '../../theme/palette.dart';
import '../../theme/tokens.dart';
import '../../theme/typography.dart';
import '../../widgets/photo_image.dart';
import '../../widgets/ui.dart';
import '../flow.dart';
import 'discover_common.dart';

/// Discover: unused days worth a collage, place + date moments, and the whole
/// library browsable by date (year → month → day), built on a local index so
/// it stays fast with tens of thousands of photos.
class DiscoverTab extends ConsumerStatefulWidget {
  const DiscoverTab({super.key});

  @override
  ConsumerState<DiscoverTab> createState() => _DiscoverTabState();
}

class _DiscoverTabState extends ConsumerState<DiscoverTab> with WidgetsBindingObserver {
  bool _visible = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // The tab lives in the home IndexedStack: only index while it is shown.
    final visible = TickerMode.valuesOf(context).enabled;
    if (visible && !_visible) _refresh();
    _visible = visible;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _visible) _refresh(force: true);
  }

  void _refresh({bool force = false}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.read(libraryIndexProvider.notifier).ensureFresh(force: force);
    });
  }

  Future<void> _grant() async {
    final ok = await ensureGalleryAccess(context, ref);
    if (!mounted) return;
    if (ok) {
      ref.invalidate(momentsProvider);
      await ref.read(libraryIndexProvider.notifier).ensureFresh(force: true);
    }
  }

  Future<void> _manageSelection() async {
    await ref.read(permissionServiceProvider).presentLimited();
    if (!mounted) return;
    ref.invalidate(momentsProvider);
    await ref.read(libraryIndexProvider.notifier).ensureFresh(force: true);
  }

  Future<void> _jumpToDate(LibraryIndex index) async {
    final first = index.firstDay;
    final last = index.lastDay;
    if (first == null || last == null) return;
    final picked = await showDatePicker(
      context: context,
      initialDate: last,
      firstDate: first,
      lastDate: last,
      helpText: context.l10n.t('discoverJumpToDate'),
    );
    if (picked == null || !mounted) return;
    final nearest = index.nearestDay(picked);
    if (nearest == null) return;
    if (nearest != dayKeyOf(picked)) {
      showAppSnack(
        context,
        context.l10n.a('discoverNearestDay', {
          'date': DateFormat.yMMMMd(dateLocale(context)).format(picked),
          'nearest': dayTitle(context, nearest),
        }),
      );
    }
    await openDay(context, nearest);
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final st = ref.watch(libraryIndexProvider);
    final access = st.access;

    if (access == null) return const Center(child: CircularProgressIndicator());
    if (!access.usable) {
      return EmptyState(
        icon: Icons.explore_outlined,
        title: l.t('discoverTitle'),
        message: l.t('discoverMessage'),
        action: PrimaryButton(
          label: l.t('turnOnPhotos'),
          icon: Icons.photo_library_rounded,
          expand: false,
          onPressed: _grant,
        ),
      );
    }

    final limited = access == GalleryAccess.limited;
    final index = st.index;
    final banners = <Widget>[
      if (limited)
        DiscoverBanner(
          icon: Icons.photo_library_outlined,
          text: l.t('discoverLimitedBanner'),
          actionLabel: l.t('discoverManageSelection'),
          onAction: _manageSelection,
        ),
      if (st.indexing && index != null)
        DiscoverBanner(
          icon: Icons.sync_rounded,
          text: l.a('discoverIndexing', {
            'done': formatCount(context, st.done),
            'total': formatCount(context, st.total),
          }),
          showProgress: true,
          progress: st.progress,
        ),
    ];

    Widget body;
    if (index == null) {
      body = st.error != null && !st.indexing
          ? EmptyState(
              icon: Icons.error_outline_rounded,
              title: l.t('discoverIndexFailed'),
              message: l.t('loadFailedMessage'),
              action: PrimaryButton(
                label: l.t('tryAgain'),
                icon: Icons.refresh_rounded,
                expand: false,
                onPressed: () =>
                    ref.read(libraryIndexProvider.notifier).ensureFresh(force: true),
              ),
            )
          : _FirstIndexing(done: st.done, total: st.total, progress: st.progress);
    } else if (index.isEmpty) {
      body = EmptyState(
        icon: Icons.no_photography_outlined,
        title: l.t('discoverEmptyTitle'),
        message: l.t(limited ? 'discoverLimitedEmptyMessage' : 'discoverEmptyMessage'),
        action: limited
            ? PrimaryButton(
                label: l.t('discoverManageSelection'),
                icon: Icons.add_photo_alternate_outlined,
                expand: false,
                onPressed: _manageSelection,
              )
            : null,
      );
    } else {
      body = RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(momentsProvider);
          await ref.read(libraryIndexProvider.notifier).ensureFresh(force: true);
        },
        child: CustomScrollView(
          slivers: [
            const SliverToBoxAdapter(child: _Suggestions()),
            const SliverToBoxAdapter(child: _Moments()),
            SliverToBoxAdapter(
              child: _BrowseByDate(index: index, onJump: () => _jumpToDate(index)),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 96)), // clear the FAB
          ],
        ),
      );
    }

    return Column(
      children: [
        ...banners,
        Expanded(child: body),
      ],
    );
  }
}

/// First run: no cache yet, the library is being read.
class _FirstIndexing extends StatelessWidget {
  const _FirstIndexing({required this.done, required this.total, required this.progress});
  final int done;
  final int total;
  final double? progress;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(Space.xl),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 320),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(context.l10n.t('discoverIndexingTitle'),
                  style: context.text.titleMd, textAlign: TextAlign.center),
              const SizedBox(height: Space.lg),
              ClipRRect(
                borderRadius: BorderRadius.circular(Radii.pill),
                child: LinearProgressIndicator(
                  value: progress,
                  minHeight: 4,
                  backgroundColor: c.surfaceInput,
                ),
              ),
              const SizedBox(height: Space.sm),
              if (total > 0)
                Text(
                  context.l10n.a('discoverIndexing', {
                    'done': formatCount(context, done),
                    'total': formatCount(context, total),
                  }),
                  style: context.text.caption.copyWith(color: c.textLo),
                  textAlign: TextAlign.center,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---- Suggestions -------------------------------------------------------------

/// "Ready for a collage": a few unused days, each dismissable.
class _Suggestions extends ConsumerWidget {
  const _Suggestions();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Personalised suggestions can be turned off in Settings.
    if (!ref.watch(occasionPrefsProvider.select((p) => p.discoverSuggestions))) {
      return const SizedBox.shrink();
    }
    final list = ref.watch(discoverSuggestionsProvider);
    if (list.isEmpty) return const SizedBox.shrink();
    final l = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(l.t('discoverSuggestionsTitle')),
        Padding(
          padding: const EdgeInsets.fromLTRB(Space.lg, 0, Space.lg, Space.md),
          child: Text(l.t('discoverSuggestionsHint'),
              style: context.text.bodyMd.copyWith(color: context.colors.textMid)),
        ),
        for (final s in list) _SuggestionCard(suggestion: s),
      ],
    );
  }
}

class _SuggestionCard extends ConsumerWidget {
  const _SuggestionCard({required this.suggestion});
  final DaySuggestion suggestion;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final l = context.l10n;
    final index = ref.watch(libraryIndexDataProvider);
    if (index == null) return const SizedBox.shrink();
    final ids = index.idsForDay(suggestion.day);
    final preview = spreadPick(ids, max: 4);
    final title = dayTitle(context, suggestion.day);
    final eyebrow = suggestion.onThisDay
        ? l.a('discoverOnThisDay', {'year': '${dayOfKey(suggestion.day).year}'})
        : null;

    void dismiss() {
      final messenger = ScaffoldMessenger.of(context);
      ref.read(dismissedDaysProvider.notifier).dismiss(suggestion.day);
      showAppSnackOn(
        messenger,
        l.t('discoverSuggestionHidden'),
        actionLabel: l.t('undo'),
        onAction: () => ref.read(dismissedDaysProvider.notifier).restore(suggestion.day),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.lg, 0, Space.lg, Space.md),
      child: Material(
        color: c.surface,
        borderRadius: BorderRadius.circular(Radii.card),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => openDay(context, suggestion.day),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(Radii.card),
              border: Border.all(color: c.line),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  height: 96,
                  child: Row(
                    children: [
                      for (final id in preview)
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.all(1),
                            child: PhotoImage(assetId: id),
                          ),
                        ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(Space.md, Space.sm, Space.xs, Space.sm),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (eyebrow != null)
                              Text(eyebrow,
                                  style: context.text.caption.copyWith(color: c.amber)),
                            Text(title,
                                style: context.text.titleMd,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis),
                            Text(photosLabel(context, suggestion.count),
                                style: context.text.caption.copyWith(color: c.textLo)),
                          ],
                        ),
                      ),
                      TextButton(
                        onPressed: () => openPhotosAsCollage(
                            context, ref, spreadPick(ids), title: title),
                        style: TextButton.styleFrom(
                          minimumSize: const Size(Sizes.touchTarget, Sizes.touchTarget),
                        ),
                        child: Text(l.t('discoverMakeCollage')),
                      ),
                      IconButton(
                        tooltip: l.t('discoverHideSuggestion'),
                        onPressed: dismiss,
                        icon: Icon(Icons.close_rounded, color: c.textLo),
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
}

// ---- Moments (place + date) --------------------------------------------------

/// The existing place-and-day moments, as a quiet horizontal strip.
class _Moments extends ConsumerWidget {
  const _Moments();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final list = ref.watch(momentsProvider).valueOrNull ?? const <Moment>[];
    if (list.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(context.l10n.t('discoverMomentsTitle')),
        SizedBox(
          height: 176,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: Space.lg),
            itemCount: list.length,
            separatorBuilder: (_, _) => const SizedBox(width: Space.md),
            itemBuilder: (_, i) => _MomentCard(moment: list[i]),
          ),
        ),
      ],
    );
  }
}

class _MomentCard extends ConsumerWidget {
  const _MomentCard({required this.moment});
  final Moment moment;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final date = DateFormat.yMMMd(dateLocale(context)).format(moment.when);
    return SizedBox(
      width: 240,
      child: Material(
        color: c.surface,
        borderRadius: BorderRadius.circular(Radii.card),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => openPhotosAsCollage(context, ref, moment.assetIds, title: moment.title),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(Radii.card),
              border: Border.all(color: c.line),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  height: 100,
                  child: Row(
                    children: [
                      for (final id in moment.assetIds.take(3))
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.all(1),
                            child: PhotoImage(assetId: id),
                          ),
                        ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(Space.md),
                  child: Row(
                    children: [
                      Icon(Icons.place_rounded, color: c.amber, size: 18),
                      const SizedBox(width: Space.sm),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(moment.title,
                                style: context.text.labelLg,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis),
                            Text(
                              context.l10n.a('momentSubtitle', {
                                'subtitle': date,
                                'count': '${moment.assetIds.length}',
                              }),
                              style: context.text.caption.copyWith(color: c.textLo),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
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
}

// ---- Browse by date ----------------------------------------------------------

class _BrowseByDate extends ConsumerWidget {
  const _BrowseByDate({required this.index, required this.onJump});
  final LibraryIndex index;
  final VoidCallback onJump;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final c = context.colors;
    final years = index.years; // O(years)
    final chosen = ref.watch(discoverYearProvider);
    final year = years.any((y) => y.$1 == chosen)
        ? chosen!
        : (years.isEmpty ? null : years.first.$1);
    final used = ref.watch(usedPerDayProvider);
    final usedMonths = <int, int>{}; // month → used photos, for [year]
    if (year != null) {
      used.forEach((day, n) {
        if (day ~/ 10000 == year) {
          final m = (day ~/ 100) % 100;
          usedMonths[m] = (usedMonths[m] ?? 0) + n;
        }
      });
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          l.t('discoverBrowseTitle'),
          trailing: TextButton.icon(
            onPressed: index.dayKeys.isEmpty ? null : onJump,
            style: TextButton.styleFrom(
              minimumSize: const Size(Sizes.touchTarget, Sizes.touchTarget),
            ),
            icon: const Icon(Icons.event_rounded, size: 18),
            label: Text(l.t('discoverJumpToDate')),
          ),
        ),
        SizedBox(
          height: Sizes.touchTarget,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: Space.lg),
            children: [
              for (final (y, n) in years)
                Padding(
                  padding: const EdgeInsets.only(right: Space.sm),
                  child: _YearChip(
                    label: '$y',
                    count: n,
                    selected: y == year,
                    onTap: () => ref.read(discoverYearProvider.notifier).state = y,
                  ),
                ),
              if (index.undated.isNotEmpty)
                _YearChip(
                  label: l.t('discoverUndated'),
                  count: index.undated.length,
                  selected: false,
                  onTap: () => openDay(context, kUndatedDay),
                ),
            ],
          ),
        ),
        if (year != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.lg, Space.md, Space.lg, 0),
            child: GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 4,
                mainAxisSpacing: Space.sm,
                crossAxisSpacing: Space.sm,
                mainAxisExtent: 64,
              ),
              itemCount: 12,
              itemBuilder: (context, i) {
                final count = index.monthCount(year, i + 1);
                final usedN = usedMonths[i + 1] ?? 0;
                final has = count > 0;
                return Semantics(
                  button: has,
                  enabled: has,
                  excludeSemantics: true,
                  label: [
                    monthTitle(context, year, i + 1),
                    photosLabel(context, count),
                    if (usedN > 0) usedLabel(context, usedN),
                  ].join(', '),
                  child: Material(
                    color: has ? c.surfaceHigh : Colors.transparent,
                    borderRadius: BorderRadius.circular(Radii.control),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(Radii.control),
                      onTap: has ? () => openMonth(context, year, i + 1) : null,
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(Radii.control),
                          border: Border.all(color: has ? c.line : c.surfaceHigh),
                        ),
                        child: Stack(
                          children: [
                            Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(monthName(context, i + 1, short: true),
                                      style: context.text.labelMd.copyWith(
                                          color: has ? c.textHi : c.textDisabled)),
                                  const SizedBox(height: 2),
                                  Text(has ? formatCount(context, count) : '–',
                                      style: context.text.spec.copyWith(
                                          fontSize: 11,
                                          color: has ? c.textMid : c.textDisabled)),
                                ],
                              ),
                            ),
                            if (usedN > 0)
                              const Positioned(top: 6, right: 6, child: UsedDot()),
                          ],
                        ),
                      ),
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

class _YearChip extends StatelessWidget {
  const _YearChip({
    required this.label,
    required this.count,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final int count;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      button: true,
      selected: selected,
      excludeSemantics: true,
      label: '$label, ${photosLabel(context, count)}',
      child: Material(
        color: selected ? c.amberTint : c.surfaceInput,
        borderRadius: BorderRadius.circular(Radii.pill),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(Radii.pill),
          child: Container(
            constraints: const BoxConstraints(minHeight: Sizes.touchTarget),
            padding: const EdgeInsets.symmetric(horizontal: Space.lg),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(Radii.pill),
              border: selected ? Border.all(color: c.amber) : null,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(label,
                    style: context.text.labelMd
                        .copyWith(color: selected ? c.amber : c.textMid)),
                const SizedBox(width: Space.sm),
                Text(formatCount(context, count),
                    style: context.text.spec.copyWith(
                        fontSize: 11, color: selected ? c.amber : c.textLo)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
