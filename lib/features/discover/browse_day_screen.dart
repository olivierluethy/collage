import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../l10n/app_localizations.dart';
import '../../models/collage_project.dart';
import '../../services/library_index_service.dart';
import '../../services/photo_usage.dart';
import '../../state/library_index.dart';
import '../../state/providers.dart';
import '../../theme/palette.dart';
import '../../theme/tokens.dart';
import '../../theme/typography.dart';
import '../../widgets/photo_image.dart';
import '../../widgets/ui.dart';
import '../flow.dart';
import 'discover_common.dart';

/// Every photo taken on one day, in a virtualized grid. Pick up to nine and
/// turn them into a collage; photos already in collages carry a small marker
/// and can be hidden.
class BrowseDayScreen extends ConsumerStatefulWidget {
  const BrowseDayScreen({super.key, required this.day, this.fromMonth = false});

  /// `yyyymmdd` key, or [kUndatedDay].
  final int day;

  /// Opened from the month calendar (the month breadcrumb then pops).
  final bool fromMonth;

  @override
  ConsumerState<BrowseDayScreen> createState() => _BrowseDayScreenState();
}

class _BrowseDayScreenState extends ConsumerState<BrowseDayScreen> {
  late int _day = widget.day;
  final _selected = <String>[]; // tap order = collage order
  bool _hideUsed = false;
  final _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _goToDay(int? day) {
    if (day == null) return;
    setState(() {
      _day = day;
      _selected.clear();
    });
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  void _toggle(String id) {
    if (!_selected.contains(id) && _selected.length >= kMaxCollagePhotos) {
      showAppSnack(context,
          context.l10n.a('discoverMaxReached', {'max': '$kMaxCollagePhotos'}));
      return;
    }
    setState(() {
      if (!_selected.remove(id)) _selected.add(id);
    });
  }

  Future<void> _make(List<String> ids) async {
    if (ids.isEmpty) return;
    await openPhotosAsCollage(context, ref, ids, title: dayTitle(context, _day));
    if (mounted) setState(_selected.clear);
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final index = ref.watch(libraryIndexDataProvider);
    final usage = ref.watch(photoUsageProvider);
    if (index == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    // O(photos of this day) — never the whole library.
    final all = index.idsForDay(_day);
    final usedIds = {for (final id in all) if (usage.isUsed(id)) id};
    final visible = _hideUsed ? [for (final id in all) if (!usedIds.contains(id)) id] : all;
    final collages = _collagesFor(usedIds, usage);

    final undated = _day == kUndatedDay;
    final date = undated ? null : dayOfKey(_day);
    final loc = dateLocale(context);

    final List<String>? toMake = _selected.isNotEmpty
        ? List.of(_selected)
        : (visible.isNotEmpty && visible.length <= kMaxCollagePhotos ? visible : null);
    final makeLabel = toMake != null
        ? l.a('discoverMakeCollageWith', {'count': '${toMake.length}'})
        : l.a('discoverSelectUpTo', {'max': '$kMaxCollagePhotos'});

    return Scaffold(
      appBar: AppBar(
        title: Text(dayTitle(context, _day)),
        actions: [
          if (_selected.isNotEmpty)
            IconButton(
              tooltip: l.t('discoverClearSelection'),
              onPressed: () => setState(_selected.clear),
              icon: const Icon(Icons.deselect_rounded),
            ),
        ],
      ),
      bottomNavigationBar: CrumbBar(
        prevLabel: l.t('discoverPrevDay'),
        nextLabel: l.t('discoverNextDay'),
        onPrev: undated || index.adjacentDay(_day, -1) == null
            ? null
            : () => _goToDay(index.adjacentDay(_day, -1)),
        onNext: undated || index.adjacentDay(_day, 1) == null
            ? null
            : () => _goToDay(index.adjacentDay(_day, 1)),
        crumbs: undated
            ? [Crumb(l.t('discoverUndated'))]
            : [
                Crumb('${date!.year}', onTap: () => backToYear(context, ref, date.year)),
                Crumb(monthName(context, date.month),
                    onTap: () => dayToMonth(context, _day, fromMonth: widget.fromMonth)),
                Crumb(DateFormat.d(loc).format(date)),
              ],
        top: Row(
          children: [
            SpecChip('${_selected.length}/$kMaxCollagePhotos', active: _selected.isNotEmpty),
            const SizedBox(width: Space.md),
            Expanded(
              child: PrimaryButton(
                label: makeLabel,
                icon: Icons.auto_awesome_mosaic_rounded,
                onPressed: toMake == null ? null : () => _make(toMake),
              ),
            ),
          ],
        ),
      ),
      body: CustomScrollView(
        controller: _scroll,
        slivers: [
          SliverToBoxAdapter(
            child: _DayHeader(
              day: _day,
              total: all.length,
              used: usedIds.length,
              collages: collages,
              hideUsed: _hideUsed,
              onHideUsed: usedIds.isEmpty ? null : (v) => setState(() => _hideUsed = v),
            ),
          ),
          if (visible.isEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(Space.xl),
                child: Text(
                  all.isEmpty ? l.t('discoverDayEmpty') : l.t('discoverAllHidden'),
                  textAlign: TextAlign.center,
                  style: context.text.bodyMd.copyWith(color: context.colors.textMid),
                ),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(2, 0, 2, Space.lg),
              // Builder delegate: only the tiles on screen are ever built.
              sliver: SliverGrid(
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 140,
                  mainAxisSpacing: 2,
                  crossAxisSpacing: 2,
                ),
                delegate: SliverChildBuilderDelegate(
                  (context, i) {
                    final id = visible[i];
                    final order = _selected.indexOf(id);
                    return _PhotoTile(
                      key: ValueKey(id),
                      assetId: id,
                      position: i + 1,
                      total: visible.length,
                      order: order < 0 ? null : order + 1,
                      used: usedIds.contains(id),
                      onTap: () => _toggle(id),
                    );
                  },
                  childCount: visible.length,
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// Collages that use any photo of this day, newest first.
  List<CollageProject> _collagesFor(Set<String> usedIds, PhotoUsageIndex usage) {
    final byId = <String, CollageProject>{};
    for (final id in usedIds) {
      for (final p in usage.collagesUsing(id)) {
        byId[p.id] = p;
      }
    }
    return byId.values.toList()..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }
}

class _DayHeader extends ConsumerWidget {
  const _DayHeader({
    required this.day,
    required this.total,
    required this.used,
    required this.collages,
    required this.hideUsed,
    required this.onHideUsed,
  });

  final int day;
  final int total;
  final int used;
  final List<CollageProject> collages;
  final bool hideUsed;
  final ValueChanged<bool>? onHideUsed;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final l = context.l10n;
    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.lg, Space.md, Space.lg, Space.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // The browsing axis: when the photos were taken.
          Row(
            children: [
              Icon(Icons.photo_camera_outlined, size: 13, color: c.textLo),
              const SizedBox(width: Space.xs),
              Expanded(
                child: Text(
                  day == kUndatedDay
                      ? l.t('discoverUndatedHint')
                      : l.a('discoverTakenOn', {'date': dayTitleLong(context, day)}),
                  style: context.text.caption.copyWith(color: c.textLo),
                ),
              ),
              SpecChip(photosLabel(context, total)),
            ],
          ),
          if (collages.isNotEmpty) ...[
            const SizedBox(height: Space.lg),
            Text(l.t('discoverCollagesFromDay'),
                style: context.text.labelMd.copyWith(color: c.textMid)),
            const SizedBox(height: Space.sm),
            for (final p in collages) _CollageRow(project: p),
          ],
          if (used > 0) ...[
            const SizedBox(height: Space.md),
            Row(
              children: [
                const UsedDot(),
                const SizedBox(width: Space.sm),
                Expanded(
                  child: Text(usedLabel(context, used),
                      style: context.text.caption.copyWith(color: c.textLo)),
                ),
              ],
            ),
            const SizedBox(height: Space.sm),
            FilterChip(
              label: Text(l.t('discoverHideUsed')),
              selected: hideUsed,
              onSelected: onHideUsed,
              materialTapTargetSize: MaterialTapTargetSize.padded,
            ),
          ],
        ],
      ),
    );
  }
}

/// A collage made from this day's photos. Its date is when the *collage* was
/// made — deliberately labelled so it never reads as the photos' date.
class _CollageRow extends ConsumerWidget {
  const _CollageRow({required this.project});
  final CollageProject project;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final made = DateFormat.yMMMd(dateLocale(context))
        .format(DateTime.fromMillisecondsSinceEpoch(project.createdAt));
    final cover = project.assetIds.isEmpty ? null : project.assetIds.first;
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.sm),
      child: Material(
        color: c.surfaceHigh,
        borderRadius: BorderRadius.circular(Radii.control),
        child: InkWell(
          borderRadius: BorderRadius.circular(Radii.control),
          onTap: () => openCollage(context, ref, project),
          child: Container(
            constraints: const BoxConstraints(minHeight: 56),
            padding: const EdgeInsets.all(Space.sm),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(Radii.control),
              border: Border.all(color: c.line),
            ),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(Radii.chip),
                  child: SizedBox(
                    width: 40,
                    height: 40,
                    child: cover == null
                        ? ColoredBox(color: c.surfaceInput)
                        : PhotoImage(assetId: cover),
                  ),
                ),
                const SizedBox(width: Space.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(project.title,
                          style: context.text.labelLg.copyWith(color: c.textHi),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                      Row(
                        children: [
                          Icon(Icons.event_rounded, size: 13, color: c.textLo),
                          const SizedBox(width: Space.xs),
                          Flexible(
                            child: Text(
                              context.l10n.a('discoverCollageMadeOn', {'date': made}),
                              style: context.text.caption.copyWith(color: c.textLo),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right_rounded, color: c.textLo),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PhotoTile extends StatelessWidget {
  const _PhotoTile({
    super.key,
    required this.assetId,
    required this.position,
    required this.total,
    required this.order,
    required this.used,
    required this.onTap,
  });

  final String assetId;
  final int position;
  final int total;
  final int? order; // 1-based selection order, null when not selected
  final bool used;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final l = context.l10n;
    final selected = order != null;
    final label = [
      l.a('discoverPhotoLabel', {'n': '$position', 'total': '$total'}),
      if (selected) l.t('discoverStateSelected'),
      if (used) l.t('discoverStateInCollage'),
    ].join(', ');
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      excludeSemantics: true,
      child: GestureDetector(
        onTap: onTap,
        child: Stack(
          fit: StackFit.expand,
          children: [
            PhotoImage(assetId: assetId),
            if (selected)
              DecoratedBox(
                decoration: BoxDecoration(
                  color: c.amberTint,
                  border: Border.all(color: c.amber, width: 3),
                ),
              ),
            Positioned(
              top: Space.xs,
              right: Space.xs,
              child: Container(
                width: 24,
                height: 24,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: selected ? c.amber : Colors.black38,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white70, width: 1),
                ),
                child: selected
                    ? Text('$order', style: context.text.spec.copyWith(color: c.onAmber, fontSize: 12))
                    : null,
              ),
            ),
            if (used)
              Positioned(
                left: Space.xs,
                bottom: Space.xs,
                child: Container(
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.6),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.collections_rounded, size: 12, color: Colors.white),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
