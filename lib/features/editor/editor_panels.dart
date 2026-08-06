import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../data/fonts.dart';
import '../../data/layout_templates.dart';
import '../../data/palette.dart';
import '../../data/shape_catalog.dart';
import '../../data/sticker_catalog.dart';
import '../../models/canvas_element.dart';
import '../../models/collage_project.dart';
import '../../models/layout_template.dart';
import '../../services/giphy_service.dart';
import '../../theme/text_styles.dart';
import '../../theme/tokens.dart';
import '../../widgets/layout_miniature.dart';
import '../../widgets/pattern_painter.dart';
import '../../widgets/photo_image.dart';
import '../../widgets/ui.dart';
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
            LabeledSlider(label: 'Gap', value: b.gap, min: 0, max: 40, onChanged: (v) => c.updateBorder((x) => x.gap = v)),
            LabeledSlider(label: 'Margin', value: b.margin, min: 0, max: 60, onChanged: (v) => c.updateBorder((x) => x.margin = v)),
            LabeledSlider(label: 'Corners', value: b.radius, min: 0, max: 48, onChanged: (v) => c.updateBorder((x) => x.radius = v)),
            LabeledSlider(label: 'Border', value: b.thickness, min: 0, max: 20, onChanged: (v) => c.updateBorder((x) => x.thickness = v)),
            const SectionHeader('Border colour'),
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
                        border: Border.all(color: AppColors.line),
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
                            border: Border.all(color: sel ? AppColors.amber : AppColors.line, width: sel ? 2 : 1),
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
                    label: Text(bg.imageAssetId == null ? 'Choose a background photo' : 'Change background photo'),
                  ),
                ),
                LabeledSlider(label: 'Darken', value: bg.imageDim * 100, min: 0, max: 70, suffix: '%', onChanged: (v) => up((x) => x.imageDim = v / 100)),
              ],
            );
        }

        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Space.lg),
              child: SegmentedButton<BackgroundKind>(
                segments: const [
                  ButtonSegment(value: BackgroundKind.solid, label: Text('Colour')),
                  ButtonSegment(value: BackgroundKind.gradient, label: Text('Gradient')),
                  ButtonSegment(value: BackgroundKind.pattern, label: Text('Pattern')),
                  ButtonSegment(value: BackgroundKind.image, label: Text('Photo')),
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
            const SectionHeader('Canvas shape'),
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
                        color: sel ? AppColors.amberTint : AppColors.surfaceInput,
                        borderRadius: BorderRadius.circular(Radii.chip),
                      ),
                      child: Text(r.label, style: AppText.spec.copyWith(color: sel ? AppColors.amber : AppColors.textMid)),
                    ),
                  );
                },
              ),
            ),
            const SectionHeader('Arrangement'),
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
                        color: AppColors.surfaceHigh,
                        borderRadius: BorderRadius.circular(Radii.control),
                        border: Border.all(color: sel ? AppColors.amber : AppColors.line, width: sel ? 2 : 1),
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

class StickersPanel extends StatelessWidget {
  const StickersPanel({super.key, required this.c, required this.onAdded});
  final EditorController c;
  final VoidCallback onAdded;

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: StickerCatalog.categories.length,
      child: Column(
        children: [
          TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: StickerCatalog.categories.map((cat) => Tab(text: cat.label)).toList(),
          ),
          Expanded(
            child: TabBarView(
              children: StickerCatalog.categories.map((cat) {
                return GridView.builder(
                  padding: const EdgeInsets.all(Space.md),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 5,
                    mainAxisSpacing: Space.sm,
                    crossAxisSpacing: Space.sm,
                  ),
                  itemCount: cat.assetPaths.length,
                  itemBuilder: (_, i) {
                    final path = cat.assetPaths[i];
                    return GestureDetector(
                      onTap: () { c.addSticker(path); onAdded(); },
                      child: Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(color: AppColors.surfaceHigh, borderRadius: BorderRadius.circular(Radii.control)),
                        child: SvgPicture.asset(path, fit: BoxFit.contain),
                      ),
                    );
                  },
                );
              }).toList(),
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
                  decoration: BoxDecoration(color: AppColors.surfaceHigh, borderRadius: BorderRadius.circular(Radii.control)),
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
      config: const Config(
        emojiViewConfig: EmojiViewConfig(backgroundColor: AppColors.surface),
        categoryViewConfig: CategoryViewConfig(
          backgroundColor: AppColors.surface,
          iconColorSelected: AppColors.amber,
          indicatorColor: AppColors.amber,
        ),
        bottomActionBarConfig: BottomActionBarConfig(enabled: false),
      ),
    );
  }
}

/// Live text editor: mutates the given text element as the user types/styles it.
class TextPanel extends StatefulWidget {
  const TextPanel({super.key, required this.c, required this.elementId});
  final EditorController c;
  final String elementId;
  @override
  State<TextPanel> createState() => _TextPanelState();
}

class _TextPanelState extends State<TextPanel> {
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

  @override
  Widget build(BuildContext context) {
    final e = _el;
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: Space.lg),
      children: [
        TextField(
          controller: _text,
          autofocus: true,
          maxLines: 2,
          onChanged: (v) => _mut((x) => x.text = v),
          decoration: const InputDecoration(hintText: 'Type your text'),
        ),
        const SizedBox(height: Space.sm),
        Row(
          children: [
            IconButton(isSelected: e?.bold ?? false, onPressed: () => _mut((x) => x.bold = !x.bold), icon: const Icon(Icons.format_bold)),
            IconButton(isSelected: e?.align == TextAlignH.left, onPressed: () => _mut((x) => x.align = TextAlignH.left), icon: const Icon(Icons.format_align_left)),
            IconButton(isSelected: e?.align == TextAlignH.center, onPressed: () => _mut((x) => x.align = TextAlignH.center), icon: const Icon(Icons.format_align_center)),
            IconButton(isSelected: e?.align == TextAlignH.right, onPressed: () => _mut((x) => x.align = TextAlignH.right), icon: const Icon(Icons.format_align_right)),
          ],
        ),
        SizedBox(
          height: 38,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: AppFonts.choices.length,
            separatorBuilder: (_, __) => const SizedBox(width: Space.sm),
            itemBuilder: (_, i) {
              final f = AppFonts.choices[i];
              final sel = f.$1 == e?.fontKey;
              return GestureDetector(
                onTap: () => _mut((x) => x.fontKey = f.$1),
                child: Container(
                  alignment: Alignment.center,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(color: sel ? AppColors.amberTint : AppColors.surfaceInput, borderRadius: BorderRadius.circular(Radii.chip)),
                  child: Text(f.$2, style: AppFonts.style(f.$1, fontSize: 15, color: sel ? AppColors.amber : AppColors.textMid)),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: Space.sm),
        SwatchRow(colors: Palette.swatches, selected: e?.color ?? Palette.swatches[0], onPick: (col) => _mut((x) => x.color = col)),
      ],
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
      if (mounted) setState(() { _loading = false; _error = 'GIF search needs a Giphy API key (see the README). Everything else works without it.'; });
    } catch (_) {
      if (mounted) setState(() { _loading = false; _error = 'Could not load GIFs. Check your connection.'; });
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
            decoration: const InputDecoration(hintText: 'Search GIFs', prefixIcon: Icon(Icons.search)),
          ),
        ),
        const SizedBox(height: Space.sm),
        Expanded(
          child: _error != null
              ? Center(child: Padding(padding: const EdgeInsets.all(Space.lg), child: Text(_error!, style: AppText.bodyMd, textAlign: TextAlign.center)))
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
class ReplacePanel extends StatelessWidget {
  const ReplacePanel({super.key, required this.c, required this.slotId, required this.onDone});
  final EditorController c;
  final String slotId;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
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
                      style: AppText.caption,
                    ),
                  ),
                  TextButton(
                    onPressed: () async {
                      final picked = await Navigator.of(context).push<List<String>>(
                        MaterialPageRoute(builder: (_) => const PhotoPickerScreen(maxImages: 1)),
                      );
                      if (picked != null && picked.isNotEmpty) {
                        c.addToPool(picked.first);
                        c.previewReplace(picked.first);
                      }
                    },
                    child: const Text('Add photo'),
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
                        border: Border.all(color: sel ? AppColors.amber : Colors.transparent, width: 3),
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
                        child: const Text('Cancel'),
                      ),
                    ),
                    const SizedBox(width: Space.sm),
                    Expanded(
                      child: PrimaryButton(
                        label: 'Use this photo',
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
