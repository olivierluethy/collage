import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/template_catalog.dart';
import '../../l10n/app_localizations.dart';
import '../../models/collage_project.dart';
import '../../models/collage_template.dart';
import '../../state/occasions.dart';
import '../../state/providers.dart';
import '../../theme/palette.dart';
import '../../theme/tokens.dart';
import '../../theme/typography.dart';
import '../../widgets/ui.dart';
import '../flow.dart';
import 'occasion_card.dart';
import 'template_search.dart';
import 'template_tile.dart';

/// The Templates browser. A search field and category chips on top; while
/// nothing narrows the list, rows for an upcoming occasion, recently used,
/// favourites, "for you" and the user's own templates come first. Count and
/// shape filters live one tap down in a sheet. Tapping a template opens the
/// editor with its styling applied and empty slots for the user's photos.
class TemplatesTab extends ConsumerStatefulWidget {
  const TemplatesTab({super.key});

  @override
  ConsumerState<TemplatesTab> createState() => _TemplatesTabState();
}

class _TemplatesTabState extends ConsumerState<TemplatesTab> {
  final _search = TextEditingController();
  TemplateQuery _q = const TemplateQuery();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _set(TemplateQuery q) => setState(() => _q = q);

  void _clearAll() {
    _search.clear();
    _set(const TemplateQuery());
  }

  void _open(CollageTemplate t) => openTemplate(context, ref, t);

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final favourites = ref.watch(favouriteTemplatesProvider);
    final favSet = favourites.toSet();
    final collages = ref.watch(draftsProvider).valueOrNull ?? const <CollageProject>[];
    final mine = ref.watch(userTemplatesProvider).valueOrNull ?? const <CollageProject>[];
    final index = TemplateSearchIndex.of(l);
    final results = searchTemplates(_q, index: index, favourites: favSet);
    final browsing = _q.isBrowsing;

    final recent = browsing ? recentTemplates(collages) : const <CollageTemplate>[];
    final favTemplates = browsing
        ? [for (final id in favourites.reversed) ?TemplateCatalog.byId(id)]
        : const <CollageTemplate>[];
    final (forCount, forYou) = browsing
        ? recommendedTemplates(collages, exclude: {...recent.map((t) => t.id), ...favSet})
        : (null, const <CollageTemplate>[]);

    return LayoutBuilder(
      builder: (context, box) => CustomScrollView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        slivers: [
          SliverToBoxAdapter(child: _searchBar(context)),
          if (browsing) const SliverToBoxAdapter(child: OccasionCard()),
          if (recent.isNotEmpty)
            SliverToBoxAdapter(
              child: TemplateRow(title: l.t('tplRecent'), templates: recent, onOpen: _open),
            ),
          if (favTemplates.isNotEmpty)
            SliverToBoxAdapter(
              child: TemplateRow(title: l.t('tplFavourites'), templates: favTemplates, onOpen: _open),
            ),
          if (forYou.isNotEmpty)
            SliverToBoxAdapter(
              child: TemplateRow(
                title: l.t('tplForYou'),
                hint: l.a('tplForYouHint', {'count': '$forCount'}),
                templates: forYou,
                onOpen: _open,
              ),
            ),
          if (browsing && mine.isNotEmpty)
            SliverToBoxAdapter(child: _MyTemplatesRow(templates: mine)),
          SliverToBoxAdapter(child: _categories(context, favSet.isNotEmpty)),
          SliverToBoxAdapter(child: _resultLine(context, results.length)),
          if (results.isEmpty)
            SliverToBoxAdapter(child: _empty(context))
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(Space.lg, Space.sm, Space.lg, Space.xxl),
              sliver: SliverGrid.builder(
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: templateGridColumns(box.maxWidth),
                  mainAxisSpacing: Space.sm,
                  crossAxisSpacing: Space.sm,
                  childAspectRatio: 0.7,
                ),
                itemCount: results.length,
                itemBuilder: (_, i) => TemplateTile(
                  template: results[i],
                  onTap: () => _open(results[i]),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _searchBar(BuildContext context) {
    final l = context.l10n;
    final c = context.colors;
    final n = _q.filterCount;
    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.lg, Space.sm, Space.lg, 0),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _search,
              textInputAction: TextInputAction.search,
              onChanged: (v) => _set(_q.copyWith(text: v)),
              decoration: InputDecoration(
                hintText: l.t('tplSearchHint'),
                prefixIcon: Icon(Icons.search_rounded, color: c.textLo),
                suffixIcon: _q.text.isEmpty
                    ? null
                    : IconButton(
                        tooltip: l.t('tplClearSearch'),
                        icon: const Icon(Icons.close_rounded),
                        color: c.textMid,
                        onPressed: () {
                          _search.clear();
                          _set(_q.copyWith(text: ''));
                        },
                      ),
              ),
            ),
          ),
          const SizedBox(width: Space.sm),
          Badge(
            isLabelVisible: n > 0,
            label: Text('$n'),
            backgroundColor: c.amber,
            textColor: c.onAmber,
            child: IconButton.filledTonal(
              tooltip: l.t('tplFilters'),
              constraints: const BoxConstraints.tightFor(width: Sizes.touchTarget, height: Sizes.touchTarget),
              style: IconButton.styleFrom(
                backgroundColor: n > 0 ? c.amberTint : c.surfaceInput,
                foregroundColor: n > 0 ? c.amber : c.textMid,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.control)),
              ),
              icon: const Icon(Icons.tune_rounded),
              onPressed: _openFilters,
            ),
          ),
        ],
      ),
    );
  }

  Widget _categories(BuildContext context, bool hasFavourites) {
    final l = context.l10n;
    final chips = [
      for (final cat in TemplateCategory.chips)
        if (cat != TemplateCategory.favourites || hasFavourites || _q.category == cat) cat,
    ];
    return Padding(
      padding: const EdgeInsets.only(top: Space.md),
      child: SizedBox(
        height: Sizes.touchTarget,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: Space.lg),
          itemCount: chips.length,
          separatorBuilder: (_, __) => const SizedBox(width: Space.sm),
          itemBuilder: (_, i) => _Chip(
            label: chips[i].label(l),
            icon: chips[i] == TemplateCategory.favourites ? Icons.star_rounded : null,
            selected: _q.category == chips[i],
            onTap: () => _set(_q.copyWith(category: chips[i])),
          ),
        ),
      ),
    );
  }

  Widget _resultLine(BuildContext context, int count) {
    final l = context.l10n;
    final narrowed = !_q.isBrowsing;
    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.lg, Space.sm, Space.sm, 0),
      child: Row(
        children: [
          SpecChip(l.a('tplCount', {'count': '$count'})),
          if (_q.count != null) ...[
            const SizedBox(width: Space.xs),
            SpecChip(l.a('templatePhotoCount', {'count': '${_q.count}'}), active: true),
          ],
          if (_q.ratio != null) ...[
            const SizedBox(width: Space.xs),
            SpecChip(_q.ratio!, active: true),
          ],
          const Spacer(),
          if (narrowed)
            TextButton(onPressed: _clearAll, child: Text(l.t('tplClearFilters'))),
        ],
      ),
    );
  }

  Widget _empty(BuildContext context) {
    final l = context.l10n;
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.all(Space.xl),
      child: Column(
        children: [
          Icon(Icons.search_off_rounded, size: 40, color: c.textLo),
          const SizedBox(height: Space.md),
          Text(l.t('tplNoMatch'), style: context.text.titleMd, textAlign: TextAlign.center),
          const SizedBox(height: Space.xs),
          Text(l.t('tplNoMatchHint'),
              style: context.text.bodyMd.copyWith(color: c.textMid), textAlign: TextAlign.center),
          const SizedBox(height: Space.lg),
          OutlinedButton(onPressed: _clearAll, child: Text(l.t('tplClearFilters'))),
        ],
      ),
    );
  }

  Future<void> _openFilters() async {
    final result = await showModalBottomSheet<TemplateQuery>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => _FilterSheet(initial: _q),
    );
    if (result != null) _set(result);
  }
}

/// Photo count and canvas shape, chosen in a sheet so the tab stays calm.
class _FilterSheet extends StatefulWidget {
  const _FilterSheet({required this.initial});
  final TemplateQuery initial;

  @override
  State<_FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends State<_FilterSheet> {
  late TemplateQuery _q = widget.initial;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(Space.xl, 0, Space.xl, Space.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l.t('tplFilters'), style: context.text.titleMd),
            const SizedBox(height: Space.lg),
            Text(l.t('templatesPhotos'), style: context.text.labelMd.copyWith(color: context.colors.textMid)),
            const SizedBox(height: Space.sm),
            Wrap(
              spacing: Space.sm,
              runSpacing: Space.sm,
              children: [
                _Chip(
                  label: l.t('tplAny'),
                  selected: _q.count == null,
                  onTap: () => setState(() => _q = _q.copyWith(clearCount: true)),
                ),
                for (final n in TemplateCatalog.counts)
                  _Chip(
                    label: '$n',
                    spec: true,
                    selected: _q.count == n,
                    semanticsLabel: l.a('templatePhotoCount', {'count': '$n'}),
                    onTap: () => setState(() => _q = _q.copyWith(count: n)),
                  ),
              ],
            ),
            const SizedBox(height: Space.xl),
            Text(l.t('tplShape'), style: context.text.labelMd.copyWith(color: context.colors.textMid)),
            const SizedBox(height: Space.sm),
            Wrap(
              spacing: Space.sm,
              runSpacing: Space.sm,
              children: [
                _Chip(
                  label: l.t('tplAny'),
                  selected: _q.ratio == null,
                  onTap: () => setState(() => _q = _q.copyWith(clearRatio: true)),
                ),
                for (final r in templateRatios)
                  _Chip(
                    label: '${l.t(ratioKey(r))}  $r',
                    selected: _q.ratio == r,
                    onTap: () => setState(() => _q = _q.copyWith(ratio: r)),
                  ),
              ],
            ),
            const SizedBox(height: Space.xl),
            Row(
              children: [
                TextButton(
                  onPressed: () => setState(() => _q = _q.copyWith(clearCount: true, clearRatio: true)),
                  child: Text(l.t('tplReset')),
                ),
                const Spacer(),
                PrimaryButton(
                  expand: false,
                  label: l.t('tplShowResults'),
                  onPressed: () => Navigator.pop(context, _q),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// A 48dp-tall chip in the house style: `surfaceInput` + `textMid`, selected
/// `amberTint` + `amber`.
class _Chip extends StatelessWidget {
  const _Chip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.icon,
    this.spec = false,
    this.semanticsLabel,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final IconData? icon;
  final bool spec;
  final String? semanticsLabel;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final fg = selected ? c.amber : c.textMid;
    final style = (spec ? context.text.spec : context.text.labelMd).copyWith(color: fg);
    return Semantics(
      button: true,
      selected: selected,
      label: semanticsLabel ?? label,
      excludeSemantics: true,
      onTap: onTap,
      child: Material(
        color: selected ? c.amberTint : c.surfaceInput,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Radii.chip),
          side: BorderSide(color: selected ? c.amber : Colors.transparent),
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(Radii.chip),
          child: Container(
            constraints: const BoxConstraints(minHeight: Sizes.touchTarget, minWidth: Sizes.touchTarget),
            padding: const EdgeInsets.symmetric(horizontal: Space.md),
            alignment: Alignment.center,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[Icon(icon, size: 16, color: fg), const SizedBox(width: Space.xs)],
                Text(label, style: style),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The user's own templates. Tap to start a collage from one, long-press to
/// delete it.
class _MyTemplatesRow extends StatelessWidget {
  const _MyTemplatesRow({required this.templates});
  final List<CollageProject> templates;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(context.l10n.t('myTemplates')),
        SizedBox(
          height: 112,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: Space.lg),
            itemCount: templates.length,
            separatorBuilder: (_, __) => const SizedBox(width: Space.sm),
            itemBuilder: (_, i) => _UserTemplateTile(template: templates[i]),
          ),
        ),
      ],
    );
  }
}

class _UserTemplateTile extends ConsumerWidget {
  const _UserTemplateTile({required this.template});
  final CollageProject template;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final thumb = template.thumbnailPath;
    return Semantics(
      button: true,
      label: template.title,
      onLongPressHint: context.l10n.t('deleteTemplate'),
      excludeSemantics: true,
      onTap: () => openUserTemplate(context, ref, template),
      onLongPress: () => _confirmDelete(context, ref),
      child: GestureDetector(
        onTap: () => openUserTemplate(context, ref, template),
        onLongPress: () => _confirmDelete(context, ref),
        child: SizedBox(
          width: 84,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(Radii.control),
                  child: thumb != null && File(thumb).existsSync()
                      ? Image.file(File(thumb), fit: BoxFit.cover)
                      : ColoredBox(
                          color: context.colors.surfaceInput,
                          child: Icon(Icons.bookmark_outline_rounded, color: context.colors.textLo),
                        ),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                template.title,
                style: context.text.caption,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final ok = await confirmDestructive(
      context,
      title: context.l10n.t('deleteTemplateTitle'),
      confirmLabel: context.l10n.t('deleteTemplate'),
      cancelLabel: context.l10n.t('cancel'),
    );
    if (ok) await ref.read(userTemplatesProvider.notifier).remove(template.id);
  }
}
