import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:uuid/uuid.dart';

import '../../data/fonts.dart';
import '../../data/layout_templates.dart';
import '../../data/palette.dart';
import '../../data/shape_catalog.dart';
import '../../data/sticker_catalog.dart';
import '../../l10n/app_localizations.dart';
import '../../models/canvas_element.dart';
import '../../models/collage_project.dart';
import '../../models/layout_template.dart';
import '../../models/photo_filter.dart';
import '../../config.dart' as app;
import '../../services/ai_collage_service.dart';
import '../../services/giphy_service.dart';
import '../../services/stamp_service.dart';
import '../../services/vision_service.dart';
import '../../state/providers.dart';
import '../../theme/palette.dart';
import '../../theme/tokens.dart';
import '../../theme/typography.dart';
import '../../widgets/layout_miniature.dart';
import '../../widgets/pattern_painter.dart';
import '../../widgets/photo_image.dart';
import '../../widgets/sticker_image.dart';
import '../../widgets/ui.dart';
import '../flow.dart';
import '../picker/photo_picker_screen.dart';
import 'editor_controller.dart';

/// Inline modifier/picker panels. Every one changes the collage LIVE while the
/// canvas stays fully visible above (the editor hosts these below a shrinking
/// canvas — no panel ever covers the collage).

class BordersPanel extends StatelessWidget {
  const BordersPanel({super.key, required this.c});
  final EditorController c;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: c,
      builder: (context, _) {
        final b = c.border;
        return ListView(
          padding: const EdgeInsets.only(bottom: Space.md),
          children: [
            LabeledSlider(label: context.l10n.t('gap'), value: b.gap, min: 0, max: 40, onChanged: (v) => c.updateBorder((x) => x.gap = v)),
            LabeledSlider(label: context.l10n.t('margin'), value: b.margin, min: 0, max: 60, onChanged: (v) => c.updateBorder((x) => x.margin = v)),
            LabeledSlider(label: context.l10n.t('corners'), value: b.radius, min: 0, max: 48, onChanged: (v) => c.updateBorder((x) => x.radius = v)),
            LabeledSlider(label: context.l10n.t('border'), value: b.thickness, min: 0, max: 20, onChanged: (v) => c.updateBorder((x) => x.thickness = v)),
            SectionHeader(context.l10n.t('borderColour')),
            SwatchRow(colors: Palette.swatches, selected: b.color, onPick: (col) => c.updateBorder((x) => x.color = col)),
          ],
        );
      },
    );
  }
}

class BackgroundPanel extends StatelessWidget {
  const BackgroundPanel({super.key, required this.c});
  final EditorController c;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: c,
      builder: (context, _) {
        final bg = c.background;
        void up(void Function(BackgroundSettings b) fn) => c.updateBackground(fn);

        Widget body;
        switch (bg.kind) {
          case BackgroundKind.solid:
            body = SwatchRow(colors: Palette.swatches, selected: bg.color, onPick: (col) => up((x) => x.color = col));
          case BackgroundKind.gradient:
            body = SizedBox(
              height: 56,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: Space.lg),
                itemCount: Palette.gradients.length,
                separatorBuilder: (_, __) => const SizedBox(width: Space.sm),
                itemBuilder: (_, i) {
                  final g = Palette.gradients[i];
                  return GestureDetector(
                    onTap: () => up((x) { x.gradientStart = g.$1; x.gradientEnd = g.$2; }),
                    child: Container(
                      width: 56,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(colors: [g.$1, g.$2]),
                        borderRadius: BorderRadius.circular(Radii.control),
                        border: Border.all(color: context.colors.line),
                      ),
                    ),
                  );
                },
              ),
            );
          case BackgroundKind.pattern:
            body = Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  height: 56,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: Space.lg),
                    itemCount: Palette.patterns.length,
                    separatorBuilder: (_, __) => const SizedBox(width: Space.sm),
                    itemBuilder: (_, i) {
                      final key = Palette.patterns[i];
                      final sel = bg.patternKey == key;
                      return GestureDetector(
                        onTap: () => up((x) => x.patternKey = key),
                        child: Container(
                          width: 56,
                          clipBehavior: Clip.antiAlias,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(Radii.control),
                            border: Border.all(color: sel ? context.colors.amber : context.colors.line, width: sel ? 2 : 1),
                          ),
                          child: PatternBackground(patternKey: key, color: bg.patternColor, background: bg.patternBg, tile: 16),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: Space.sm),
                SwatchRow(colors: Palette.swatches, selected: bg.patternColor, onPick: (col) => up((x) => x.patternColor = col)),
              ],
            );
          case BackgroundKind.image:
            body = Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: Space.lg),
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      final picked = await Navigator.of(context).push<List<String>>(
                        MaterialPageRoute(builder: (_) => const PhotoPickerScreen(maxImages: 1)),
                      );
                      if (picked != null && picked.isNotEmpty) up((x) => x.imageAssetId = picked.first);
                    },
                    icon: const Icon(Icons.image_outlined),
                    label: Text(bg.imageAssetId == null
                        ? context.l10n.t('chooseBgPhoto')
                        : context.l10n.t('changeBgPhoto')),
                  ),
                ),
                LabeledSlider(label: context.l10n.t('darken'), value: bg.imageDim * 100, min: 0, max: 70, suffix: '%', onChanged: (v) => up((x) => x.imageDim = v / 100)),
                LabeledSlider(label: context.l10n.t('blur'), value: bg.imageBlur, min: 0, max: 30, onChanged: (v) => up((x) => x.imageBlur = v)),
              ],
            );
        }

        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Space.lg),
              child: SegmentedButton<BackgroundKind>(
                segments: [
                  ButtonSegment(value: BackgroundKind.solid, label: Text(context.l10n.t('colour'))),
                  ButtonSegment(value: BackgroundKind.gradient, label: Text(context.l10n.t('gradient'))),
                  ButtonSegment(value: BackgroundKind.pattern, label: Text(context.l10n.t('pattern'))),
                  ButtonSegment(value: BackgroundKind.image, label: Text(context.l10n.t('photo'))),
                ],
                selected: {bg.kind},
                onSelectionChanged: (s) => up((x) => x.kind = s.first),
                showSelectedIcon: false,
                style: const ButtonStyle(visualDensity: VisualDensity.compact),
              ),
            ),
            const SizedBox(height: Space.md),
            body,
          ],
        );
      },
    );
  }
}

/// Scope for the filter panel: the whole collage, or just the selected cell.
enum FilterScope { whole, cell }

/// Live photo-filter panel. Two scopes: apply a preset + adjustments to every
/// cell, or to only the tapped cell. Everything updates the collage live and is
/// baked into the export by the shared render path.
class FilterPanel extends StatefulWidget {
  const FilterPanel({super.key, required this.c});
  final EditorController c;

  @override
  State<FilterPanel> createState() => _FilterPanelState();
}

class _FilterPanelState extends State<FilterPanel> {
  FilterScope _scope = FilterScope.whole;

  /// Working filter for the "Whole collage" scope. In cell scope we edit the
  /// selected slot's filter directly.
  final PhotoFilter _whole = PhotoFilter();

  EditorController get c => widget.c;

  /// The filter currently being edited given the scope + selection.
  PhotoFilter? get _target {
    if (_scope == FilterScope.whole) return _whole;
    final id = c.selectedSlotId;
    if (id == null) return null;
    return c.fillFor(id)?.filter;
  }

  /// A photo to preview presets on: the selected cell's, else the first filled.
  String? get _sampleAsset {
    if (_scope == FilterScope.cell && c.selectedSlotId != null) {
      final f = c.fillFor(c.selectedSlotId!);
      if (f != null) return f.assetId;
    }
    for (final f in c.project.fills.values) {
      return f.assetId;
    }
    return null;
  }

  void _commit() {
    if (_scope == FilterScope.whole) {
      c.applyFilterToAll(_whole);
    } else {
      final id = c.selectedSlotId;
      if (id != null) c.updateSlotFilter(id, (_) {});
    }
    setState(() {});
  }

  void _setPreset(FilterPreset p) {
    final t = _target;
    if (t == null) return;
    t.preset = p;
    _commit();
  }

  void _setAdjust(void Function(PhotoFilter f) fn) {
    final t = _target;
    if (t == null) return;
    fn(t);
    _commit();
  }

  void _reset() {
    final t = _target;
    if (t == null) return;
    t.resetAdjustments();
    t.preset = FilterPreset.none;
    _commit();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: c,
      builder: (context, _) {
        final target = _target;
        final sample = _sampleAsset;
        // Scrolls, so the growing list of adjustments never overflows.
        return ListView(
          padding: EdgeInsets.zero,
          children: [
            // Scope toggle + reset.
            Padding(
              padding: const EdgeInsets.fromLTRB(Space.lg, Space.sm, Space.lg, 0),
              child: Row(
                children: [
                  Expanded(
                    child: SegmentedButton<FilterScope>(
                      segments: [
                        ButtonSegment(value: FilterScope.whole, label: Text(context.l10n.t('wholeCollage'))),
                        ButtonSegment(value: FilterScope.cell, label: Text(context.l10n.t('thisPhoto'))),
                      ],
                      selected: {_scope},
                      onSelectionChanged: (s) => setState(() => _scope = s.first),
                      showSelectedIcon: false,
                      style: const ButtonStyle(visualDensity: VisualDensity.compact),
                    ),
                  ),
                  TextButton(
                    onPressed: target == null ? null : _reset,
                    child: Text(context.l10n.t('reset')),
                  ),
                ],
              ),
            ),
            if (_scope == FilterScope.cell && c.selectedSlotId == null)
              Padding(
                padding: const EdgeInsets.fromLTRB(Space.lg, Space.md, Space.lg, 0),
                child: Text(
                  context.l10n.t('tapPhotoToFilter'),
                  style: context.text.caption,
                ),
              )
            else ...[
              // Preset strip.
              SectionHeader(context.l10n.t('look')),
              SizedBox(
                height: 74,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: Space.lg),
                  itemCount: FilterPreset.values.length,
                  separatorBuilder: (_, __) => const SizedBox(width: Space.sm),
                  itemBuilder: (_, i) {
                    final p = FilterPreset.values[i];
                    return _PresetChip(
                      preset: p,
                      sampleAsset: sample,
                      selected: target?.preset == p,
                      onTap: () => _setPreset(p),
                    );
                  },
                ),
              ),
              SectionHeader(context.l10n.t('adjust')),
              _AdjustSlider(label: context.l10n.t('brightness'), value: target?.brightness ?? 0, onChanged: (v) => _setAdjust((f) => f.brightness = v)),
              _AdjustSlider(label: context.l10n.t('contrast'), value: target?.contrast ?? 0, onChanged: (v) => _setAdjust((f) => f.contrast = v)),
              _AdjustSlider(label: context.l10n.t('warmth'), value: target?.warmth ?? 0, onChanged: (v) => _setAdjust((f) => f.warmth = v)),
              _AdjustSlider(label: context.l10n.t('saturation'), value: target?.saturation ?? 0, onChanged: (v) => _setAdjust((f) => f.saturation = v)),
              LabeledSlider(
                label: context.l10n.t('vignette'),
                value: (target?.vignette ?? 0) * 100,
                min: 0,
                max: 100,
                suffix: '%',
                onChanged: (v) => _setAdjust((f) => f.vignette = v / 100),
              ),
              LabeledSlider(
                label: context.l10n.t('sharpen'),
                value: (target?.sharpen ?? 0) * 100,
                min: 0,
                max: 100,
                suffix: '%',
                onChanged: (v) => _setAdjust((f) => f.sharpen = v / 100),
              ),
              const SizedBox(height: Space.md),
            ],
          ],
        );
      },
    );
  }
}

/// A signed −100..100 adjustment slider mapping to the filter's −1..1 range.
class _AdjustSlider extends StatelessWidget {
  const _AdjustSlider({required this.label, required this.value, required this.onChanged});
  final String label;
  final double value; // −1..1
  final ValueChanged<double> onChanged; // emits −1..1

  @override
  Widget build(BuildContext context) {
    final shown = (value * 100).round();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Space.lg),
      child: Row(
        children: [
          SizedBox(width: 84, child: Text(label, style: context.text.bodyMd)),
          Expanded(
            child: Slider(
              value: value.clamp(-1, 1),
              min: -1,
              max: 1,
              onChanged: onChanged,
            ),
          ),
          SizedBox(
            width: 44,
            child: Text(shown > 0 ? '+$shown' : '$shown',
                style: context.text.spec, textAlign: TextAlign.right),
          ),
        ],
      ),
    );
  }
}

/// A 56×56 live preview of one preset applied to a sample photo.
class _PresetChip extends StatelessWidget {
  const _PresetChip({
    required this.preset,
    required this.sampleAsset,
    required this.selected,
    required this.onTap,
  });
  final FilterPreset preset;
  final String? sampleAsset;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final labelColor = selected ? context.colors.amber : context.colors.textMid;
    Widget swatch;
    if (sampleAsset == null) {
      swatch = ColoredBox(color: context.colors.surfaceInput);
    } else {
      final f = PhotoFilter(preset: preset);
      Widget img = PhotoImage(assetId: sampleAsset!, fit: BoxFit.cover);
      if (!f.isColorIdentity) {
        img = ColorFiltered(colorFilter: ColorFilter.matrix(f.matrix()), child: img);
      }
      swatch = img;
    }
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 52,
            height: 52,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(Radii.control),
              border: Border.all(
                color: selected ? context.colors.amber : context.colors.line,
                width: selected ? 2 : 1,
              ),
            ),
            child: swatch,
          ),
          const SizedBox(height: 4),
          Text(context.l10n.t(_presetKey(preset)), style: context.text.caption.copyWith(color: labelColor)),
        ],
      ),
    );
  }
}

class LayoutPanel extends StatelessWidget {
  const LayoutPanel({super.key, required this.c});
  final EditorController c;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: c,
      builder: (context, _) {
        final count = c.pool.length.clamp(1, 9);
        final options = [...LayoutTemplates.forCount(count), LayoutTemplates.freeform];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SectionHeader(context.l10n.t('canvasShape')),
            SizedBox(
              height: 38,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: Space.lg),
                itemCount: CanvasRatio.all.length,
                separatorBuilder: (_, __) => const SizedBox(width: Space.sm),
                itemBuilder: (_, i) {
                  final r = CanvasRatio.all[i];
                  final sel = r.label == c.project.ratioLabel;
                  return GestureDetector(
                    onTap: () => c.setRatioLabel(r.label),
                    child: Container(
                      alignment: Alignment.center,
                      padding: const EdgeInsets.symmetric(horizontal: Space.md),
                      decoration: BoxDecoration(
                        color: sel ? context.colors.amberTint : context.colors.surfaceInput,
                        borderRadius: BorderRadius.circular(Radii.chip),
                      ),
                      child: Text(r.label, style: context.text.spec.copyWith(color: sel ? context.colors.amber : context.colors.textMid)),
                    ),
                  );
                },
              ),
            ),
            SectionHeader(context.l10n.t('arrangement')),
            Expanded(
              child: GridView.builder(
                padding: const EdgeInsets.symmetric(horizontal: Space.lg),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 5,
                  mainAxisSpacing: Space.sm,
                  crossAxisSpacing: Space.sm,
                  childAspectRatio: 0.9,
                ),
                itemCount: options.length,
                itemBuilder: (_, i) {
                  final t = options[i];
                  final sel = c.project.layout.id == t.id;
                  return GestureDetector(
                    onTap: () => c.setLayout(t),
                    child: Container(
                      padding: const EdgeInsets.all(5),
                      decoration: BoxDecoration(
                        color: context.colors.surfaceHigh,
                        borderRadius: BorderRadius.circular(Radii.control),
                        border: Border.all(color: sel ? context.colors.amber : context.colors.line, width: sel ? 2 : 1),
                      ),
                      child: _MiniAspect(template: t, ratio: c.project.ratio.value),
                    ),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}

class _MiniAspect extends StatelessWidget {
  const _MiniAspect({required this.template, required this.ratio});
  final LayoutTemplate template;
  final double ratio;
  @override
  Widget build(BuildContext context) {
    return AspectRatio(aspectRatio: ratio, child: LayoutMiniature(template: template));
  }
}

class StickersPanel extends ConsumerWidget {
  const StickersPanel({super.key, required this.c, required this.onAdded});
  final EditorController c;
  final VoidCallback onAdded;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Rebuild when the remote sticker catalog arrives.
    ref.watch(remoteCatalogsProvider);
    final tabs = <(String, List<String>)>[
      for (final cat in StickerCatalog.categories)
        (context.l10n.t(_stickerKey(cat.dir)), cat.assetPaths),
      for (final cat in StickerCatalog.remoteCategories)
        (cat.label, [for (final s in cat.stickers) s.url]),
    ];
    return DefaultTabController(
      length: tabs.length,
      child: Column(
        children: [
          TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: [for (final t in tabs) Tab(text: t.$1)],
          ),
          Expanded(
            child: TabBarView(
              children: [
                for (final t in tabs)
                  GridView.builder(
                    padding: const EdgeInsets.all(Space.md),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 5,
                      mainAxisSpacing: Space.sm,
                      crossAxisSpacing: Space.sm,
                    ),
                    itemCount: t.$2.length,
                    itemBuilder: (_, i) {
                      final source = t.$2[i];
                      return GestureDetector(
                        onTap: () { c.addSticker(source); onAdded(); },
                        child: Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(color: context.colors.surfaceHigh, borderRadius: BorderRadius.circular(Radii.control)),
                          child: StickerImage(source: source),
                        ),
                      );
                    },
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class ShapesPanel extends StatefulWidget {
  const ShapesPanel({super.key, required this.c, required this.onAdded});
  final EditorController c;
  final VoidCallback onAdded;
  @override
  State<ShapesPanel> createState() => _ShapesPanelState();
}

class _ShapesPanelState extends State<ShapesPanel> {
  Color _color = Palette.swatches[3];
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SwatchRow(colors: Palette.swatches, selected: _color, onPick: (c) => setState(() => _color = c)),
        const SizedBox(height: Space.sm),
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.all(Space.md),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 5,
              mainAxisSpacing: Space.sm,
              crossAxisSpacing: Space.sm,
            ),
            itemCount: ShapeCatalog.kinds.length,
            itemBuilder: (_, i) {
              final kind = ShapeCatalog.kinds[i].$1;
              return GestureDetector(
                onTap: () { widget.c.addShape(kind, fill: _color.toARGB32()); widget.onAdded(); },
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(color: context.colors.surfaceHigh, borderRadius: BorderRadius.circular(Radii.control)),
                  child: CustomPaint(painter: ShapePainter(kind: kind, fill: _color)),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class EmojiPanel extends StatelessWidget {
  const EmojiPanel({super.key, required this.c, required this.onAdded});
  final EditorController c;
  final VoidCallback onAdded;
  @override
  Widget build(BuildContext context) {
    return EmojiPicker(
      onEmojiSelected: (category, emoji) { c.addEmoji(emoji.emoji); onAdded(); },
      config: Config(
        emojiViewConfig: EmojiViewConfig(backgroundColor: context.colors.surface),
        categoryViewConfig: CategoryViewConfig(
          backgroundColor: context.colors.surface,
          iconColorSelected: context.colors.amber,
          indicatorColor: context.colors.amber,
        ),
        bottomActionBarConfig: const BottomActionBarConfig(enabled: false),
      ),
    );
  }
}

/// Live text editor: mutates the given text element as the user types/styles it.
class TextPanel extends ConsumerStatefulWidget {
  const TextPanel({super.key, required this.c, required this.elementId});
  final EditorController c;
  final String elementId;
  @override
  ConsumerState<TextPanel> createState() => _TextPanelState();
}

class _TextPanelState extends ConsumerState<TextPanel> {
  late final TextEditingController _text;
  TextElement? get _el {
    final e = widget.c.selectedElement;
    return e is TextElement && e.id == widget.elementId ? e : null;
  }

  @override
  void initState() {
    super.initState();
    _text = TextEditingController(text: _el?.text ?? '');
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _mut(void Function(TextElement e) fn) {
    final e = _el;
    if (e == null) return;
    widget.c.mutateSelected((x) { if (x is TextElement) fn(x); });
    setState(() {});
  }

  bool _busy = false;

  void _setText(String t) {
    _text.text = t;
    _mut((x) => x.text = t);
  }

  List<String> get _photoIds =>
      [for (final f in widget.c.project.fills.values) if (!f.isVideo) f.assetId];

  /// Fill the text with the photos' place and date.
  Future<void> _dateStamp() async {
    final messenger = ScaffoldMessenger.of(context);
    final l = context.l10n;
    final locale = Localizations.localeOf(context).toString();
    setState(() => _busy = true);
    try {
      final stamp = await const StampService().dateAndPlace(_photoIds, localeName: locale);
      if (stamp == null) {
        messenger.showSnackBar(SnackBar(content: Text(l.t('noPhotoInfo'))));
      } else {
        _setText(stamp);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Ask Claude for three title ideas and let the user pick one.
  Future<void> _aiTitle() async {
    final messenger = ScaffoldMessenger.of(context);
    final l = context.l10n;
    final code = Localizations.localeOf(context).languageCode;
    final language = _languageNames[code] ?? 'English';
    setState(() => _busy = true);
    List<String> titles;
    try {
      final inputs = await AiCollageService.buildInputs(_photoIds.take(9).toList());
      titles = await ref.read(aiServiceProvider).suggestTitles(inputs, language: language);
    } catch (_) {
      titles = const [];
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    if (!mounted) return;
    if (titles.isEmpty) {
      messenger.showSnackBar(SnackBar(content: Text(l.t('aiTitlesFailed'))));
      return;
    }
    final pick = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (sheet) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final t in titles)
              ListTile(
                leading: const Icon(Icons.auto_awesome_rounded),
                title: Text(t),
                onTap: () => Navigator.pop(sheet, t),
              ),
          ],
        ),
      ),
    );
    if (pick != null) _setText(pick);
  }

  /// English names of the app's languages, for the AI prompt.
  static const _languageNames = {
    'en': 'English', 'zh': 'Simplified Chinese', 'hi': 'Hindi', 'es': 'Spanish',
    'ar': 'Arabic', 'bn': 'Bengali', 'fr': 'French', 'ru': 'Russian',
    'pt': 'Portuguese', 'id': 'Indonesian', 'de': 'German', 'ja': 'Japanese',
    'tr': 'Turkish', 'it': 'Italian', 'ko': 'Korean',
  };

  @override
  Widget build(BuildContext context) {
    // Rebuild when the remote font catalog arrives so extra fonts appear.
    ref.watch(remoteCatalogsProvider);
    final fonts = AppFonts.allChoices;
    final e = _el;
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: Space.lg),
      children: [
        TextField(
          controller: _text,
          autofocus: true,
          maxLines: 2,
          onChanged: (v) => _mut((x) => x.text = v),
          decoration: InputDecoration(hintText: context.l10n.t('typeYourText')),
        ),
        if (_busy) const LinearProgressIndicator(minHeight: 2),
        Wrap(
          spacing: Space.sm,
          children: [
            TextButton.icon(
              onPressed: _busy || _photoIds.isEmpty ? null : _dateStamp,
              icon: const Icon(Icons.place_outlined, size: 18),
              label: Text(context.l10n.t('insertDatePlace')),
            ),
            if (app.Config.hasAi)
              TextButton.icon(
                onPressed: _busy || _photoIds.isEmpty ? null : _aiTitle,
                icon: const Icon(Icons.auto_awesome_rounded, size: 18),
                label: Text(context.l10n.t('aiTitleSuggest')),
              ),
          ],
        ),
        const SizedBox(height: Space.sm),
        Row(
          children: [
            IconButton(isSelected: e?.bold ?? false, onPressed: () => _mut((x) => x.bold = !x.bold), icon: const Icon(Icons.format_bold)),
            IconButton(isSelected: e?.italic ?? false, onPressed: () => _mut((x) => x.italic = !x.italic), icon: const Icon(Icons.format_italic)),
            IconButton(
              isSelected: e?.shadow ?? false,
              tooltip: context.l10n.t('textShadow'),
              onPressed: () => _mut((x) => x.shadow = !x.shadow),
              icon: const Icon(Icons.blur_on_rounded),
            ),
            IconButton(isSelected: e?.align == TextAlignH.left, onPressed: () => _mut((x) => x.align = TextAlignH.left), icon: const Icon(Icons.format_align_left)),
            IconButton(isSelected: e?.align == TextAlignH.center, onPressed: () => _mut((x) => x.align = TextAlignH.center), icon: const Icon(Icons.format_align_center)),
            IconButton(isSelected: e?.align == TextAlignH.right, onPressed: () => _mut((x) => x.align = TextAlignH.right), icon: const Icon(Icons.format_align_right)),
          ],
        ),
        SizedBox(
          height: 38,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: fonts.length,
            separatorBuilder: (_, __) => const SizedBox(width: Space.sm),
            itemBuilder: (_, i) {
              final f = fonts[i];
              final sel = f.$1 == e?.fontKey;
              return GestureDetector(
                onTap: () => _mut((x) => x.fontKey = f.$1),
                child: Container(
                  alignment: Alignment.center,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(color: sel ? context.colors.amberTint : context.colors.surfaceInput, borderRadius: BorderRadius.circular(Radii.chip)),
                  child: Text(f.$2, style: AppFonts.style(f.$1, fontSize: 15, color: sel ? context.colors.amber : context.colors.textMid)),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: Space.sm),
        SwatchRow(colors: Palette.swatches, selected: e?.color ?? Palette.swatches[0], onPick: (col) => _mut((x) => x.color = col)),
        LabeledSlider(
          label: context.l10n.t('letterSpacing'),
          value: e?.letterSpacing ?? 0,
          min: -2,
          max: 20,
          onChanged: (v) => _mut((x) => x.letterSpacing = v),
        ),
        LabeledSlider(
          label: context.l10n.t('textCurve'),
          value: (e?.curve ?? 0) * 100,
          min: -100,
          max: 100,
          onChanged: (v) => _mut((x) => x.curve = v.abs() < 3 ? 0 : v / 100),
        ),
        Row(
          children: [
            Expanded(child: SectionHeader(context.l10n.t('textGradient'))),
            Switch(
              value: e?.gradientEnd != null,
              onChanged: (on) => _mut((x) => x.gradientEnd = on ? const Color(0xFFF59E2E) : null),
            ),
          ],
        ),
        if (e?.gradientEnd != null)
          SwatchRow(
            colors: Palette.swatches,
            selected: e!.gradientEnd!,
            onPick: (col) => _mut((x) => x.gradientEnd = col),
          ),
        LabeledSlider(
          label: context.l10n.t('textOutline'),
          value: e?.outlineWidth ?? 0,
          min: 0,
          max: 12,
          onChanged: (v) => _mut((x) {
            x.outlineWidth = v;
            x.outline ??= const Color(0xFF131110);
          }),
        ),
        SectionHeader(context.l10n.t('outlineColour')),
        SwatchRow(
          colors: Palette.swatches,
          selected: e?.outline ?? const Color(0xFF131110),
          onPick: (col) => _mut((x) {
            x.outline = col;
            if (x.outlineWidth == 0) x.outlineWidth = 3;
          }),
        ),
        const SizedBox(height: Space.md),
      ],
    );
  }
}

/// Every free element, front-most first. Drag to restack, tap to select.
class LayersPanel extends StatelessWidget {
  const LayersPanel({super.key, required this.c});
  final EditorController c;

  String _label(BuildContext context, CanvasElement e) => switch (e) {
        TextElement t => t.text.trim().isEmpty ? context.l10n.t('layerText') : t.text.trim(),
        StickerElement _ => context.l10n.t('layerSticker'),
        ShapeElement _ => context.l10n.t('layerShape'),
        EmojiElement em => em.emoji,
        GifElement _ => context.l10n.t('layerGif'),
        ImageElement _ => context.l10n.t('layerPhoto'),
        DrawingElement _ => context.l10n.t('layerDrawing'),
      };

  IconData _icon(CanvasElement e) => switch (e) {
        TextElement _ => Icons.title_rounded,
        StickerElement _ => Icons.emoji_emotions_outlined,
        ShapeElement _ => Icons.category_outlined,
        EmojiElement _ => Icons.tag_faces_rounded,
        GifElement _ => Icons.gif_box_outlined,
        ImageElement _ => Icons.photo_outlined,
        DrawingElement _ => Icons.brush_rounded,
      };

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: c,
      builder: (context, _) {
        final layers = c.layers;
        if (layers.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(Space.lg),
              child: Text(context.l10n.t('layersEmpty'), style: context.text.bodyMd, textAlign: TextAlign.center),
            ),
          );
        }
        return ReorderableListView.builder(
          buildDefaultDragHandles: false,
          padding: const EdgeInsets.symmetric(vertical: Space.xs),
          itemCount: layers.length,
          onReorderItem: c.reorderLayer,
          itemBuilder: (context, i) {
            final e = layers[i];
            final sel = c.selectedElementId == e.id;
            return ListTile(
              key: ValueKey(e.id),
              dense: true,
              selected: sel,
              selectedColor: context.colors.amber,
              leading: Icon(_icon(e)),
              title: Text(_label(context, e), maxLines: 1, overflow: TextOverflow.ellipsis),
              onTap: () => c.selectElement(e.id),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: context.l10n.t('ctxDuplicate'),
                    icon: const Icon(Icons.copy_rounded, size: 20),
                    onPressed: () => c.duplicateElement(e.id),
                  ),
                  IconButton(
                    tooltip: context.l10n.t('ctxDelete'),
                    icon: Icon(Icons.delete_outline_rounded, size: 20, color: context.colors.danger),
                    onPressed: () => c.deleteElement(e.id),
                  ),
                  ReorderableDragStartListener(
                    index: i,
                    child: const Padding(
                      padding: EdgeInsets.all(Space.sm),
                      child: Icon(Icons.drag_handle_rounded),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

/// Trim a free photo from each edge, live.
class CropPanel extends StatelessWidget {
  const CropPanel({super.key, required this.c, required this.elementId});
  final EditorController c;
  final String elementId;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: c,
      builder: (context, _) {
        ImageElement? im;
        for (final e in c.project.elements) {
          if (e.id == elementId && e is ImageElement) im = e;
        }
        if (im == null) return const SizedBox.shrink();
        const max = ImageElement.maxCrop * 100;
        return ListView(
          padding: const EdgeInsets.only(bottom: Space.md),
          children: [
            LabeledSlider(label: context.l10n.t('cropLeft'), value: im.cropL * 100, min: 0, max: max, suffix: '%', onChanged: (v) => c.setCrop(elementId, l: v / 100)),
            LabeledSlider(label: context.l10n.t('cropRight'), value: im.cropR * 100, min: 0, max: max, suffix: '%', onChanged: (v) => c.setCrop(elementId, r: v / 100)),
            LabeledSlider(label: context.l10n.t('cropTop'), value: im.cropT * 100, min: 0, max: max, suffix: '%', onChanged: (v) => c.setCrop(elementId, t: v / 100)),
            LabeledSlider(label: context.l10n.t('cropBottom'), value: im.cropB * 100, min: 0, max: max, suffix: '%', onChanged: (v) => c.setCrop(elementId, b: v / 100)),
            Center(
              child: TextButton.icon(
                onPressed: im.isCropped ? () => c.resetCrop(elementId) : null,
                icon: const Icon(Icons.restart_alt_rounded),
                label: Text(context.l10n.t('reset')),
              ),
            ),
          ],
        );
      },
    );
  }
}

class GiphyPanel extends StatefulWidget {
  const GiphyPanel({super.key, required this.c, required this.giphy, required this.onAdded});
  final EditorController c;
  final GiphyService giphy;
  final VoidCallback onAdded;
  @override
  State<GiphyPanel> createState() => _GiphyPanelState();
}

class _GiphyPanelState extends State<GiphyPanel> {
  List<GifItem> _items = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load('');
  }

  Future<void> _load(String q) async {
    setState(() => _loading = true);
    try {
      final r = q.isEmpty ? await widget.giphy.trending() : await widget.giphy.search(q);
      if (mounted) setState(() { _items = r; _loading = false; _error = null; });
    } on GiphyUnavailable {
      if (mounted) setState(() { _loading = false; _error = context.l10n.t('gifNeedsKey'); });
    } catch (_) {
      if (mounted) setState(() { _loading = false; _error = context.l10n.t('gifLoadFailed'); });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: Space.lg),
          child: TextField(
            onSubmitted: _load,
            decoration: InputDecoration(
                hintText: context.l10n.t('searchGifs'),
                prefixIcon: const Icon(Icons.search)),
          ),
        ),
        const SizedBox(height: Space.sm),
        Expanded(
          child: _error != null
              ? Center(child: Padding(padding: const EdgeInsets.all(Space.lg), child: Text(_error!, style: context.text.bodyMd, textAlign: TextAlign.center)))
              : _loading
                  ? const Center(child: CircularProgressIndicator())
                  : GridView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: Space.lg),
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, mainAxisSpacing: Space.sm, crossAxisSpacing: Space.sm),
                      itemCount: _items.length,
                      itemBuilder: (_, i) {
                        final g = _items[i];
                        return GestureDetector(
                          onTap: () { widget.c.addGif(g.url, g.aspect); widget.onAdded(); },
                          child: ClipRRect(borderRadius: BorderRadius.circular(8), child: Image.network(g.previewUrl, fit: BoxFit.cover)),
                        );
                      },
                    ),
        ),
      ],
    );
  }
}

/// Replace/choose a slot's photo with a LIVE in-place preview: tapping a
/// candidate previews it in the collage above; Use it commits.
class ReplacePanel extends ConsumerWidget {
  const ReplacePanel({super.key, required this.c, required this.slotId, required this.onDone});
  final EditorController c;
  final String slotId;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AnimatedBuilder(
      animation: c,
      builder: (context, _) {
        final pool = c.pool;
        final candidate = c.replaceCandidate;
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(Space.lg, 0, Space.lg, Space.sm),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      candidate == null ? 'Tap a photo to preview it here' : 'Preview shown above — use it?',
                      style: context.text.caption,
                    ),
                  ),
                  TextButton(
                    onPressed: () async {
                      // A template opened with an empty pool reaches here before
                      // gallery access was granted, so ensure it first.
                      if (!await ensureGalleryAccess(context, ref)) return;
                      if (!context.mounted) return;
                      final picked = await Navigator.of(context).push<List<String>>(
                        MaterialPageRoute(builder: (_) => const PhotoPickerScreen(maxImages: 1)),
                      );
                      if (picked != null && picked.isNotEmpty) {
                        c.addToPool(picked.first);
                        c.previewReplace(picked.first);
                      }
                    },
                    child: Text(context.l10n.t('addPhoto')),
                  ),
                ],
              ),
            ),
            Expanded(
              child: GridView.builder(
                padding: const EdgeInsets.symmetric(horizontal: Space.lg),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 4, mainAxisSpacing: Space.sm, crossAxisSpacing: Space.sm),
                itemCount: pool.length,
                itemBuilder: (_, i) {
                  final id = pool[i];
                  final sel = candidate == id;
                  return GestureDetector(
                    onTap: () => c.previewReplace(id),
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: sel ? context.colors.amber : Colors.transparent, width: 3),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: PhotoImage(assetId: id, fit: BoxFit.cover),
                    ),
                  );
                },
              ),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.all(Space.md),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () { c.cancelReplace(); onDone(); },
                        child: Text(context.l10n.t('cancel')),
                      ),
                    ),
                    const SizedBox(width: Space.sm),
                    Expanded(
                      child: PrimaryButton(
                        label: context.l10n.t('useThisPhoto'),
                        icon: Icons.check_rounded,
                        onPressed: candidate == null ? null : () { c.commitReplace(); onDone(); },
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Maps a sticker category's directory id to its l10n key (see `locales/en.dart`).
String _stickerKey(String id) => switch (id) {
      'tape' => 'stickerTape',
      'love' => 'stickerLove',
      'notes' => 'stickerNotes',
      'birthday' => 'stickerBirthday',
      'paint' => 'stickerPaint',
      'frame' => 'stickerFrame',
      'christmas' => 'stickerChristmas',
      'newyear' => 'stickerNewYear',
      'winter' => 'stickerWinter',
      _ => 'stickerTape',
    };

/// Maps a filter preset to its l10n key (see `locales/en.dart`).
String _presetKey(FilterPreset p) => switch (p) {
      FilterPreset.none => 'filterOriginal',
      FilterPreset.auto => 'filterAuto',
      FilterPreset.grayscale => 'filterMono',
      FilterPreset.sepia => 'filterSepia',
      FilterPreset.vintage => 'filterVintage',
      FilterPreset.cool => 'filterCool',
      FilterPreset.highContrast => 'filterPunch',
      FilterPreset.fade => 'filterFade',
    };

/// One slot photo's own look: shape, frame style, frame colour and shadow,
/// plus on-device helpers to frame faces and cut the subject out.
class PhotoStylePanel extends StatefulWidget {
  const PhotoStylePanel({super.key, required this.c, required this.slotId, required this.onCutout});
  final EditorController c;
  final String slotId;

  /// Called after a cut-out sticker was added (the host closes the panel).
  final VoidCallback onCutout;

  @override
  State<PhotoStylePanel> createState() => _PhotoStylePanelState();
}

class _PhotoStylePanelState extends State<PhotoStylePanel> {
  static const _masks = ['none', 'circle', 'heart', 'star', 'hexagon', 'diamond', 'rounded'];
  bool _busy = false;

  EditorController get c => widget.c;

  Future<void> _frameFaces({required bool all}) async {
    final messenger = ScaffoldMessenger.of(context);
    final l = context.l10n;
    setState(() => _busy = true);
    var found = 0;
    try {
      final ids = all ? c.project.fills.keys.toList() : [widget.slotId];
      for (final id in ids) {
        final f = c.fillFor(id);
        if (f == null || f.isVideo) continue;
        final focus = await const VisionService().faceFocus(f.assetId);
        if (focus == null) continue;
        final asset = await AssetEntity.fromId(f.assetId);
        if (asset == null || asset.orientatedHeight == 0) continue;
        c.frameOnFocus(id, focus, asset.orientatedWidth / asset.orientatedHeight);
        found++;
      }
    } catch (_) {
      // Detection unavailable: fall through to the "no faces" message.
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    messenger.showSnackBar(SnackBar(
      content: Text(found > 0 ? l.a('facesFramed', {'count': '$found'}) : l.t('noFacesFound')),
    ));
  }

  Future<void> _cutout() async {
    final f = c.fillFor(widget.slotId);
    if (f == null || f.isVideo) return;
    final messenger = ScaffoldMessenger.of(context);
    final l = context.l10n;
    setState(() => _busy = true);
    String? path;
    try {
      path = await const VisionService().cutout(f.assetId, id: const Uuid().v4());
    } catch (_) {
      path = null;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    if (path == null) {
      messenger.showSnackBar(SnackBar(content: Text(l.t('cutoutFailed'))));
      return;
    }
    c.addCutout(path);
    widget.onCutout();
  }

  String _maskLabel(BuildContext context, String m) => switch (m) {
        'none' => context.l10n.t('maskNone'),
        'circle' => context.l10n.t('maskCircle'),
        'heart' => context.l10n.t('maskHeart'),
        'star' => context.l10n.t('maskStar'),
        'hexagon' => context.l10n.t('maskHexagon'),
        'diamond' => context.l10n.t('maskDiamond'),
        _ => context.l10n.t('maskRounded'),
      };

  String _styleLabel(BuildContext context, FrameStyle s) => switch (s) {
        FrameStyle.plain => context.l10n.t('frameStylePlain'),
        FrameStyle.polaroid => context.l10n.t('frameStylePolaroid'),
        FrameStyle.tape => context.l10n.t('frameStyleTape'),
        FrameStyle.torn => context.l10n.t('frameStyleTorn'),
      };

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: c,
      builder: (context, _) {
        final f = c.fillFor(widget.slotId);
        if (f == null) return const SizedBox.shrink();
        void up(void Function(SlotFill x) fn) => c.updateSlotStyle(widget.slotId, fn);
        return ListView(
          padding: const EdgeInsets.only(bottom: Space.md),
          children: [
            if (_busy) const LinearProgressIndicator(minHeight: 2),
            SectionHeader(context.l10n.t('photoShape')),
            _ChoiceRow(
              children: [
                for (final m in _masks)
                  ChoiceChip(
                    label: Text(_maskLabel(context, m)),
                    selected: f.mask == m,
                    onSelected: (_) => up((x) => x.mask = m),
                  ),
              ],
            ),
            SectionHeader(context.l10n.t('frameStyle')),
            _ChoiceRow(
              children: [
                for (final st in FrameStyle.values)
                  ChoiceChip(
                    label: Text(_styleLabel(context, st)),
                    selected: f.frameStyle == st,
                    onSelected: (_) => up((x) => x.frameStyle = st),
                  ),
              ],
            ),
            LabeledSlider(
              label: context.l10n.t('photoFrame'),
              value: f.frameWidth,
              min: 0,
              max: 30,
              onChanged: (v) => up((x) => x.frameWidth = v),
            ),
            SectionHeader(context.l10n.t('frameColour')),
            SwatchRow(
              colors: Palette.swatches,
              selected: f.frameColor,
              onPick: (col) => up((x) {
                x.frameColor = col;
                if (x.frameWidth == 0) x.frameWidth = 8;
              }),
            ),
            SwitchListTile(
              title: Text(context.l10n.t('photoShadow')),
              value: f.shadow,
              onChanged: (on) => up((x) => x.shadow = on),
            ),
            if (!f.isVideo) ...[
              SectionHeader(context.l10n.t('smartTools')),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: Space.lg),
                child: Wrap(
                  spacing: Space.sm,
                  runSpacing: Space.sm,
                  children: [
                    OutlinedButton.icon(
                      onPressed: _busy ? null : () => _frameFaces(all: false),
                      icon: const Icon(Icons.face_retouching_natural_rounded, size: 18),
                      label: Text(context.l10n.t('frameFaces')),
                    ),
                    OutlinedButton.icon(
                      onPressed: _busy ? null : () => _frameFaces(all: true),
                      icon: const Icon(Icons.groups_rounded, size: 18),
                      label: Text(context.l10n.t('frameFacesAll')),
                    ),
                    OutlinedButton.icon(
                      onPressed: _busy ? null : _cutout,
                      icon: const Icon(Icons.content_cut_rounded, size: 18),
                      label: Text(context.l10n.t('cutoutSubject')),
                    ),
                  ],
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}

/// A horizontally scrolling row of chips.
class _ChoiceRow extends StatelessWidget {
  const _ChoiceRow({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
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

/// Freehand drawing controls. While open, the canvas captures strokes; Done
/// turns them into one movable element.
class DrawPanel extends StatelessWidget {
  const DrawPanel({super.key, required this.c, required this.onDone});
  final EditorController c;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: c,
      builder: (context, _) {
        return ListView(
          padding: const EdgeInsets.only(bottom: Space.md),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(Space.lg, Space.sm, Space.lg, 0),
              child: Text(context.l10n.t('drawHint'), style: context.text.caption),
            ),
            SwatchRow(
              colors: Palette.swatches,
              selected: c.drawColor,
              onPick: (col) => c.setDrawStyle(color: col),
            ),
            LabeledSlider(
              label: context.l10n.t('brushSize'),
              value: c.drawWidth * 1000,
              min: 2,
              max: 60,
              onChanged: (v) => c.setDrawStyle(width: v / 1000),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Space.lg),
              child: Row(
                children: [
                  TextButton.icon(
                    onPressed: c.draftStrokes.isEmpty ? null : c.undoStroke,
                    icon: const Icon(Icons.undo_rounded),
                    label: Text(context.l10n.t('undoStroke')),
                  ),
                  const Spacer(),
                  FilledButton(
                    onPressed: onDone,
                    child: Text(context.l10n.t('done')),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}
