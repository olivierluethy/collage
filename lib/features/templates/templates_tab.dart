import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/template_catalog.dart';
import '../../l10n/app_localizations.dart';
import '../../models/collage_project.dart';
import '../../models/collage_template.dart';
import '../../state/providers.dart';
import '../../theme/palette.dart';
import '../../theme/tokens.dart';
import '../../theme/typography.dart';
import '../../widgets/template_thumbnail.dart';
import '../../widgets/ui.dart';
import '../flow.dart';

/// The Templates browser: a two-level filter — photo count, then style — over
/// the ready-made designs, each shown as a live preview. Tapping one opens the
/// editor with its styling applied and empty slots for the user's photos.
class TemplatesTab extends ConsumerStatefulWidget {
  const TemplatesTab({super.key});

  @override
  ConsumerState<TemplatesTab> createState() => _TemplatesTabState();
}

class _TemplatesTabState extends ConsumerState<TemplatesTab> {
  int _count = 2;
  TemplateStyle? _style;

  @override
  Widget build(BuildContext context) {
    final templates = TemplateCatalog.forBucket(_count, _style);
    final mine = ref.watch(userTemplatesProvider).valueOrNull ?? const [];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (mine.isNotEmpty) ...[
          SectionHeader(context.l10n.t('myTemplates')),
          SizedBox(
            height: 112,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: Space.lg),
              itemCount: mine.length,
              separatorBuilder: (_, __) => const SizedBox(width: Space.sm),
              itemBuilder: (_, i) => _UserTemplateTile(template: mine[i]),
            ),
          ),
        ],
        SectionHeader(context.l10n.t('templatesPhotos')),
        _ChipRow(
          children: [
            for (final n in TemplateCatalog.counts)
              _FilterChip(
                label: '$n',
                selected: _count == n,
                onTap: () => setState(() => _count = n),
              ),
          ],
        ),
        SectionHeader(context.l10n.t('templatesStyle')),
        _ChipRow(
          children: [
            _FilterChip(
              label: context.l10n.t('templatesAll'),
              selected: _style == null,
              onTap: () => setState(() => _style = null),
            ),
            for (final s in TemplateCatalog.styles)
              _FilterChip(
                label: context.l10n.t(_styleKey(s)),
                selected: _style == s,
                onTap: () => setState(() => _style = s),
              ),
          ],
        ),
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.all(Space.lg),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              mainAxisSpacing: Space.md,
              crossAxisSpacing: Space.md,
              childAspectRatio: 0.66,
            ),
            itemCount: templates.length,
            itemBuilder: (_, i) => _TemplateTile(template: templates[i]),
          ),
        ),
      ],
    );
  }
}

class _TemplateTile extends ConsumerWidget {
  const _TemplateTile({required this.template});
  final CollageTemplate template;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return GestureDetector(
      onTap: () => openTemplate(context, ref, template),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(5),
              decoration: BoxDecoration(
                color: context.colors.surface,
                borderRadius: BorderRadius.circular(Radii.card),
                border: Border.all(color: context.colors.line),
              ),
              child: Center(
                child: AspectRatio(
                  aspectRatio: template.ratio.value,
                  child: TemplateThumbnail(template: template),
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            context.l10n.a('templatePhotoCount', {'count': '${template.photoCount}'}),
            style: context.text.caption,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

/// One of the user's own templates. Tap to start a collage from it,
/// long-press to delete it.
class _UserTemplateTile extends ConsumerWidget {
  const _UserTemplateTile({required this.template});
  final CollageProject template;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final thumb = template.thumbnailPath;
    return GestureDetector(
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
    );
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: Text(context.l10n.t('deleteTemplateTitle')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialog, false), child: Text(context.l10n.t('cancel'))),
          TextButton(
            onPressed: () => Navigator.pop(dialog, true),
            child: Text(context.l10n.t('delete'), style: TextStyle(color: context.colors.danger)),
          ),
        ],
      ),
    );
    if (ok == true) await ref.read(userTemplatesProvider.notifier).remove(template.id);
  }
}

class _ChipRow extends StatelessWidget {
  const _ChipRow({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: Space.lg),
        itemCount: children.length,
        separatorBuilder: (_, __) => const SizedBox(width: Space.sm),
        itemBuilder: (_, i) => children[i],
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({required this.label, required this.selected, required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: Space.md),
        decoration: BoxDecoration(
          color: selected ? context.colors.amberTint : context.colors.surfaceInput,
          borderRadius: BorderRadius.circular(Radii.chip),
          border: Border.all(
            color: selected ? context.colors.amber : Colors.transparent,
          ),
        ),
        child: Text(
          label,
          style: context.text.labelMd.copyWith(
            color: selected ? context.colors.amber : context.colors.textMid,
          ),
        ),
      ),
    );
  }
}

/// Maps a template style to its l10n key (see `locales/en.dart`).
String _styleKey(TemplateStyle s) => switch (s) {
      TemplateStyle.minimal => 'styleMinimal',
      TemplateStyle.birthday => 'styleBirthday',
      TemplateStyle.love => 'styleLove',
      TemplateStyle.travel => 'styleTravel',
      TemplateStyle.party => 'styleParty',
      TemplateStyle.family => 'styleFamily',
      TemplateStyle.summer => 'styleSummer',
      TemplateStyle.winter => 'styleWinter',
      TemplateStyle.social => 'styleSocial',
      TemplateStyle.aesthetic => 'styleAesthetic',
    };
