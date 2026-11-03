import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../../models/collage_template.dart';
import '../../state/occasions.dart';
import '../../theme/palette.dart';
import '../../theme/tokens.dart';
import '../../theme/typography.dart';
import '../../widgets/template_thumbnail.dart';
import '../../widgets/ui.dart';
import 'template_search.dart';

/// A compact template preview: the live thumbnail on a `surface` card, a quiet
/// spec line (photo count · shape) and a star to keep it as a favourite.
/// Long-press stars it too. One semantics node describes the whole tile.
class TemplateTile extends ConsumerWidget {
  const TemplateTile({super.key, required this.template, required this.onTap, this.showSpec = true});

  final CollageTemplate template;
  final VoidCallback onTap;

  /// The count · ratio line under the preview (off in tight horizontal rows).
  final bool showSpec;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final c = context.colors;
    final fav = ref.watch(favouriteTemplatesProvider.select((f) => f.contains(template.id)));
    final name = templateDisplayName(l, template);
    final count = l.a('templatePhotoCount', {'count': '${template.photoCount}'});
    final ratio = l.t(ratioKey(template.ratioLabel));

    return Semantics(
      button: true,
      label: '$name, $count, $ratio${fav ? ', ${l.t('tplFavourite')}' : ''}',
      hint: l.t('tplOpenHint'),
      onLongPressHint: fav ? l.t('tplUnstar') : l.t('tplStar'),
      excludeSemantics: true,
      onTap: onTap,
      onLongPress: () => toggleFavourite(context, ref, template),
      child: Material(
        color: c.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Radii.card),
          side: BorderSide(color: c.line),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          onLongPress: () => toggleFavourite(context, ref, template),
          child: Padding(
            padding: const EdgeInsets.all(Space.xs),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Positioned.fill(
                        child: Center(
                          child: AspectRatio(
                            aspectRatio: template.ratio.value,
                            child: TemplateThumbnail(template: template, radius: Radii.chip),
                          ),
                        ),
                      ),
                      Positioned(
                        top: -Space.xs,
                        right: -Space.xs,
                        child: _StarButton(template: template, active: fav),
                      ),
                    ],
                  ),
                ),
                if (showSpec)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(Space.xs, Space.xs, Space.xs, 0),
                    child: Row(
                      children: [
                        Icon(Icons.photo_outlined, size: 13, color: c.textLo),
                        const SizedBox(width: 2),
                        Text('${template.photoCount}', style: context.text.spec.copyWith(color: c.textMid)),
                        const Spacer(),
                        Text(template.ratioLabel, style: context.text.spec.copyWith(color: c.textLo)),
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

/// The 48dp star in a tile's corner; a small scrim keeps it legible on any
/// template background.
class _StarButton extends ConsumerWidget {
  const _StarButton({required this.template, required this.active});
  final CollageTemplate template;
  final bool active;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    return SizedBox(
      width: Sizes.touchTarget,
      height: Sizes.touchTarget,
      child: InkResponse(
        onTap: () => toggleFavourite(context, ref, template),
        radius: 20,
        child: Center(
          child: Container(
            width: 26,
            height: 26,
            decoration: BoxDecoration(
              color: c.scrim,
              shape: BoxShape.circle,
            ),
            child: Icon(
              active ? Icons.star_rounded : Icons.star_outline_rounded,
              size: 17,
              color: active ? c.amber : Colors.white,
            ),
          ),
        ),
      ),
    );
  }
}

/// Stars or un-stars [t] and confirms it with a snackbar.
void toggleFavourite(BuildContext context, WidgetRef ref, CollageTemplate t) {
  final added = ref.read(favouriteTemplatesProvider.notifier).toggle(t.id);
  showAppSnack(
    context,
    context.l10n.t(added ? 'tplStarred' : 'tplUnstarred'),
    kind: added ? SnackKind.success : SnackKind.info,
  );
}

/// A titled horizontal row of compact tiles (Recent, Favourites, For you).
class TemplateRow extends StatelessWidget {
  const TemplateRow({
    super.key,
    required this.title,
    required this.templates,
    required this.onOpen,
    this.hint,
  });

  final String title;
  final String? hint;
  final List<CollageTemplate> templates;
  final void Function(CollageTemplate) onOpen;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(title),
        if (hint != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.lg, 0, Space.lg, Space.sm),
            child: Text(hint!, style: context.text.caption.copyWith(color: context.colors.textLo)),
          ),
        SizedBox(
          height: 128,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: Space.lg),
            itemCount: templates.length,
            separatorBuilder: (_, __) => const SizedBox(width: Space.sm),
            itemBuilder: (_, i) => SizedBox(
              width: 92,
              child: TemplateTile(
                template: templates[i],
                showSpec: false,
                onTap: () => onOpen(templates[i]),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Grid columns for a width: 2 on very narrow phones, 3 on phones from
/// 360dp, more on tablets.
int templateGridColumns(double width) {
  if (width < 360) return 2;
  if (width < 600) return 3;
  return (width / 150).floor().clamp(4, 8);
}
