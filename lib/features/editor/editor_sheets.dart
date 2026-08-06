import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../data/fonts.dart';
import '../../data/palette.dart';
import '../../data/shape_catalog.dart';
import '../../data/sticker_catalog.dart';
import '../../models/canvas_element.dart';
import '../../models/collage_project.dart';
import '../../services/giphy_service.dart';
import '../../theme/text_styles.dart';
import '../../theme/tokens.dart';
import '../../widgets/pattern_painter.dart';
import '../../widgets/photo_image.dart';
import '../../widgets/ui.dart';
import '../picker/photo_picker_screen.dart';
import 'editor_controller.dart';

Future<T?> _sheet<T>(BuildContext context, Widget child) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.surface,
    builder: (_) => child,
  );
}

// --------------------------------------------------------------------- borders
void showBordersSheet(BuildContext context, EditorController c) {
  _sheet(context, StatefulBuilder(builder: (context, setState) {
    void up(void Function(BorderSettings b) fn) {
      c.updateBorder(fn);
      setState(() {});
    }

    final b = c.border;
    return SheetScaffold(
      title: 'Borders & spacing',
      height: MediaQuery.of(context).size.height * 0.62,
      child: ListView(
        children: [
          LabeledSlider(label: 'Gap', value: b.gap, min: 0, max: 40, onChanged: (v) => up((x) => x.gap = v)),
          LabeledSlider(label: 'Margin', value: b.margin, min: 0, max: 60, onChanged: (v) => up((x) => x.margin = v)),
          LabeledSlider(label: 'Corners', value: b.radius, min: 0, max: 48, onChanged: (v) => up((x) => x.radius = v)),
          LabeledSlider(label: 'Border', value: b.thickness, min: 0, max: 20, onChanged: (v) => up((x) => x.thickness = v)),
          const SectionHeader('Border colour'),
          SwatchRow(colors: Palette.swatches, selected: b.color, onPick: (col) => up((x) => x.color = col)),
          const SizedBox(height: Space.lg),
        ],
      ),
    );
  }));
}

// ------------------------------------------------------------------ background
void showBackgroundSheet(BuildContext context, EditorController c) {
  _sheet(context, StatefulBuilder(builder: (context, setState) {
    void up(void Function(BackgroundSettings b) fn) {
      c.updateBackground(fn);
      setState(() {});
    }

    final bg = c.background;
    Widget body;
    switch (bg.kind) {
      case BackgroundKind.solid:
        body = SwatchRow(colors: Palette.swatches, selected: bg.color, onPick: (col) => up((x) => x.color = col));
      case BackgroundKind.gradient:
        body = SizedBox(
          height: 60,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: Space.lg),
            itemCount: Palette.gradients.length,
            separatorBuilder: (_, __) => const SizedBox(width: Space.sm),
            itemBuilder: (_, i) {
              final g = Palette.gradients[i];
              return GestureDetector(
                onTap: () => up((x) {
                  x.gradientStart = g.$1;
                  x.gradientEnd = g.$2;
                }),
                child: Container(
                  width: 60,
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
          children: [
            SizedBox(
              height: 60,
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
                      width: 60,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(Radii.control),
                        border: Border.all(color: sel ? AppColors.amber : AppColors.line, width: sel ? 2 : 1),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: PatternBackground(patternKey: key, color: bg.patternColor, background: bg.patternBg, tile: 18),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: Space.md),
            SwatchRow(colors: Palette.swatches, selected: bg.patternColor, onPick: (col) => up((x) => x.patternColor = col)),
          ],
        );
      case BackgroundKind.image:
        body = Column(
          children: [
            PrimaryButton(
              label: 'Choose a background photo',
              icon: Icons.image_outlined,
              onPressed: () async {
                final picked = await Navigator.of(context).push<List<String>>(
                  MaterialPageRoute(builder: (_) => const PhotoPickerScreen(maxImages: 1)),
                );
                if (picked != null && picked.isNotEmpty) up((x) => x.imageAssetId = picked.first);
              },
            ),
            LabeledSlider(label: 'Darken', value: bg.imageDim * 100, min: 0, max: 70, suffix: '%', onChanged: (v) => up((x) => x.imageDim = v / 100)),
          ],
        );
    }

    return SheetScaffold(
      title: 'Background',
      height: MediaQuery.of(context).size.height * 0.55,
      child: Column(
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
            ),
          ),
          const SizedBox(height: Space.lg),
          body,
          const SizedBox(height: Space.lg),
        ],
      ),
    );
  }));
}

// --------------------------------------------------------------------- stickers
void showStickersSheet(BuildContext context, EditorController c) {
  _sheet(context, DefaultTabController(
    length: StickerCatalog.categories.length,
    child: SheetScaffold(
      title: 'Stickers',
      height: MediaQuery.of(context).size.height * 0.6,
      child: Column(
        children: [
          TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: StickerCatalog.categories.map((c) => Tab(text: c.label)).toList(),
          ),
          Expanded(
            child: TabBarView(
              children: StickerCatalog.categories.map((cat) {
                return GridView.builder(
                  padding: const EdgeInsets.all(Space.lg),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 4,
                    mainAxisSpacing: Space.md,
                    crossAxisSpacing: Space.md,
                  ),
                  itemCount: cat.assetPaths.length,
                  itemBuilder: (_, i) {
                    final path = cat.assetPaths[i];
                    return GestureDetector(
                      onTap: () {
                        c.addSticker(path);
                        Navigator.of(context).pop();
                      },
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: AppColors.surfaceHigh,
                          borderRadius: BorderRadius.circular(Radii.control),
                        ),
                        child: _StickerPreview(path),
                      ),
                    );
                  },
                );
              }).toList(),
            ),
          ),
        ],
      ),
    ),
  ));
}

// ----------------------------------------------------------------------- shapes
void showShapesSheet(BuildContext context, EditorController c) {
  var color = Palette.swatches[3];
  _sheet(context, StatefulBuilder(builder: (context, setState) {
    return SheetScaffold(
      title: 'Shapes',
      height: MediaQuery.of(context).size.height * 0.55,
      child: Column(
        children: [
          SwatchRow(colors: Palette.swatches, selected: color, onPick: (col) => setState(() => color = col)),
          const SizedBox(height: Space.md),
          Expanded(
            child: GridView.builder(
              padding: const EdgeInsets.all(Space.lg),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 4,
                mainAxisSpacing: Space.md,
                crossAxisSpacing: Space.md,
              ),
              itemCount: ShapeCatalog.kinds.length,
              itemBuilder: (_, i) {
                final kind = ShapeCatalog.kinds[i].$1;
                return GestureDetector(
                  onTap: () {
                    c.addShape(kind, fill: color.toARGB32());
                    Navigator.of(context).pop();
                  },
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceHigh,
                      borderRadius: BorderRadius.circular(Radii.control),
                    ),
                    child: CustomPaint(painter: ShapePainter(kind: kind, fill: color)),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }));
}

// ------------------------------------------------------------------------- text
void showTextSheet(BuildContext context, EditorController c, {TextElement? edit}) {
  final ctrl = TextEditingController(text: edit?.text ?? '');
  var font = edit?.fontKey ?? 'inter';
  var color = edit?.color ?? Palette.swatches[0];
  var bold = edit?.bold ?? false;
  var align = edit?.align ?? TextAlignH.center;

  _sheet(context, StatefulBuilder(builder: (context, setState) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SheetScaffold(
        title: edit == null ? 'Add text' : 'Edit text',
        height: MediaQuery.of(context).size.height * 0.7,
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: Space.lg),
          children: [
            TextField(
              controller: ctrl,
              autofocus: true,
              maxLines: 2,
              style: AppFonts.style(font, fontSize: 22, color: color, bold: bold),
              decoration: const InputDecoration(hintText: 'Type your text'),
            ),
            const SizedBox(height: Space.md),
            Row(
              children: [
                IconButton(
                  isSelected: bold,
                  onPressed: () => setState(() => bold = !bold),
                  icon: const Icon(Icons.format_bold),
                ),
                IconButton(
                  isSelected: align == TextAlignH.left,
                  onPressed: () => setState(() => align = TextAlignH.left),
                  icon: const Icon(Icons.format_align_left),
                ),
                IconButton(
                  isSelected: align == TextAlignH.center,
                  onPressed: () => setState(() => align = TextAlignH.center),
                  icon: const Icon(Icons.format_align_center),
                ),
                IconButton(
                  isSelected: align == TextAlignH.right,
                  onPressed: () => setState(() => align = TextAlignH.right),
                  icon: const Icon(Icons.format_align_right),
                ),
              ],
            ),
            SizedBox(
              height: 40,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: AppFonts.choices.length,
                separatorBuilder: (_, __) => const SizedBox(width: Space.sm),
                itemBuilder: (_, i) {
                  final f = AppFonts.choices[i];
                  final sel = f.$1 == font;
                  return GestureDetector(
                    onTap: () => setState(() => font = f.$1),
                    child: Container(
                      alignment: Alignment.center,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        color: sel ? AppColors.amberTint : AppColors.surfaceInput,
                        borderRadius: BorderRadius.circular(Radii.chip),
                      ),
                      child: Text(f.$2,
                          style: AppFonts.style(f.$1, fontSize: 15,
                              color: sel ? AppColors.amber : AppColors.textMid)),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: Space.md),
            SwatchRow(colors: Palette.swatches, selected: color, onPick: (col) => setState(() => color = col)),
            const SizedBox(height: Space.lg),
            PrimaryButton(
              label: 'Done',
              icon: Icons.check_rounded,
              onPressed: () {
                final text = ctrl.text.trim();
                if (text.isEmpty) {
                  Navigator.of(context).pop();
                  return;
                }
                if (edit == null) {
                  c.addText(text, color: color.toARGB32());
                  c.mutateSelected((e) {
                    if (e is TextElement) {
                      e.fontKey = font;
                      e.bold = bold;
                      e.align = align;
                    }
                  });
                } else {
                  edit.text = text;
                  edit.fontKey = font;
                  edit.color = color;
                  edit.bold = bold;
                  edit.align = align;
                  c.mutateSelected((_) {});
                }
                Navigator.of(context).pop();
              },
            ),
            const SizedBox(height: Space.lg),
          ],
        ),
      ),
    );
  }));
}

// ------------------------------------------------------------------------ emoji
void showEmojiSheet(BuildContext context, EditorController c) {
  _sheet(context, SheetScaffold(
    title: 'Emoji',
    height: MediaQuery.of(context).size.height * 0.55,
    child: SizedBox(
      height: MediaQuery.of(context).size.height * 0.42,
      child: EmojiPicker(
        onEmojiSelected: (category, emoji) {
          c.addEmoji(emoji.emoji);
          Navigator.of(context).pop();
        },
        config: const Config(
          emojiViewConfig: EmojiViewConfig(backgroundColor: AppColors.surface),
          categoryViewConfig: CategoryViewConfig(
            backgroundColor: AppColors.surface,
            iconColorSelected: AppColors.amber,
            indicatorColor: AppColors.amber,
          ),
          bottomActionBarConfig: BottomActionBarConfig(enabled: false),
        ),
      ),
    ),
  ));
}

// ------------------------------------------------------------------------- gifs
void showGiphySheet(BuildContext context, EditorController c, GiphyService giphy) {
  _sheet(context, _GiphySheet(controller: c, giphy: giphy));
}

class _GiphySheet extends StatefulWidget {
  const _GiphySheet({required this.controller, required this.giphy});
  final EditorController controller;
  final GiphyService giphy;

  @override
  State<_GiphySheet> createState() => _GiphySheetState();
}

class _GiphySheetState extends State<_GiphySheet> {
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
      if (mounted) setState(() { _loading = false; _error = 'GIF search needs a Giphy API key. See the README to add one — everything else works without it.'; });
    } catch (e) {
      if (mounted) setState(() { _loading = false; _error = 'Could not load GIFs. Check your connection.'; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return SheetScaffold(
      title: 'GIFs',
      height: MediaQuery.of(context).size.height * 0.7,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Space.lg),
            child: TextField(
              onSubmitted: _load,
              decoration: const InputDecoration(
                hintText: 'Search GIFs',
                prefixIcon: Icon(Icons.search),
              ),
            ),
          ),
          const SizedBox(height: Space.md),
          Expanded(
            child: _error != null
                ? EmptyState(icon: Icons.gif_box_outlined, title: 'GIFs unavailable', message: _error!)
                : _loading
                    ? const Center(child: CircularProgressIndicator())
                    : GridView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: Space.lg),
                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 3,
                          mainAxisSpacing: Space.sm,
                          crossAxisSpacing: Space.sm,
                        ),
                        itemCount: _items.length,
                        itemBuilder: (_, i) {
                          final g = _items[i];
                          return GestureDetector(
                            onTap: () {
                              widget.controller.addGif(g.url, g.aspect);
                              Navigator.of(context).pop();
                            },
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: Image.network(g.previewUrl, fit: BoxFit.cover),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------------ slot actions
void showSlotActionsSheet(BuildContext context, EditorController c, String slotId) {
  final hasPhoto = c.fillFor(slotId) != null;
  _sheet(context, SheetScaffold(
    title: hasPhoto ? 'This photo' : 'Empty slot',
    height: MediaQuery.of(context).size.height * 0.4,
    child: ListView(
      children: [
        ListTile(
          leading: const Icon(Icons.photo_library_outlined, color: AppColors.amber),
          title: Text(hasPhoto ? 'Replace photo' : 'Choose photo', style: AppText.bodyLg),
          subtitle: Text('Pick which of your photos goes here', style: AppText.caption),
          onTap: () {
            Navigator.of(context).pop();
            _showPoolChooser(context, c, slotId);
          },
        ),
        if (hasPhoto)
          ListTile(
            leading: const Icon(Icons.open_with_rounded, color: AppColors.amber),
            title: Text('Move & zoom', style: AppText.bodyLg),
            subtitle: Text('Reposition the photo inside its slot', style: AppText.caption),
            onTap: () {
              Navigator.of(context).pop();
              _showSlotAdjust(context, c, slotId);
            },
          ),
        if (hasPhoto)
          ListTile(
            leading: const Icon(Icons.delete_outline_rounded, color: AppColors.danger),
            title: Text('Clear slot', style: AppText.bodyLg),
            onTap: () {
              c.clearSlot(slotId);
              Navigator.of(context).pop();
            },
          ),
        Padding(
          padding: const EdgeInsets.all(Space.lg),
          child: Text('Tip: press and hold a photo, then drag it onto another to swap them.',
              style: AppText.caption, textAlign: TextAlign.center),
        ),
      ],
    ),
  ));
}

void _showPoolChooser(BuildContext context, EditorController c, String slotId) {
  final pool = c.pool;
  _sheet(context, SheetScaffold(
    title: 'Choose a photo',
    height: MediaQuery.of(context).size.height * 0.6,
    child: Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: Space.lg),
          child: OutlinedButton.icon(
            onPressed: () async {
              final picked = await Navigator.of(context).push<List<String>>(
                MaterialPageRoute(builder: (_) => const PhotoPickerScreen(maxImages: 1)),
              );
              if (picked != null && picked.isNotEmpty) {
                c.addToPool(picked.first);
                c.assignSlot(slotId, picked.first);
                if (context.mounted) Navigator.of(context).pop();
              }
            },
            icon: const Icon(Icons.add_photo_alternate_outlined),
            label: const Text('Add another photo'),
          ),
        ),
        const SizedBox(height: Space.md),
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.symmetric(horizontal: Space.lg),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              mainAxisSpacing: Space.sm,
              crossAxisSpacing: Space.sm,
            ),
            itemCount: pool.length,
            itemBuilder: (_, i) {
              final id = pool[i];
              return GestureDetector(
                onTap: () {
                  c.assignSlot(slotId, id);
                  Navigator.of(context).pop();
                },
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: PhotoImage(assetId: id, fit: BoxFit.cover),
                ),
              );
            },
          ),
        ),
      ],
    ),
  ));
}

void _showSlotAdjust(BuildContext context, EditorController c, String slotId) {
  final fill = c.fillFor(slotId);
  if (fill == null) return;
  _sheet(context, StatefulBuilder(builder: (context, setState) {
    return SheetScaffold(
      title: 'Move & zoom',
      height: MediaQuery.of(context).size.height * 0.62,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(Space.lg),
            child: AspectRatio(
              aspectRatio: 1,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(Radii.card),
                child: GestureDetector(
                  onPanUpdate: (d) {
                    c.setSlotTransform(slotId,
                        offX: fill.offsetX - d.delta.dx / 120,
                        offY: fill.offsetY - d.delta.dy / 120);
                    setState(() {});
                  },
                  child: Transform.scale(
                    scale: fill.zoom,
                    child: PhotoImage(
                      assetId: fill.assetId,
                      full: true,
                      fit: BoxFit.cover,
                      alignment: Alignment(fill.offsetX, fill.offsetY),
                    ),
                  ),
                ),
              ),
            ),
          ),
          LabeledSlider(
            label: 'Zoom',
            value: fill.zoom * 25,
            min: 25,
            max: 100,
            suffix: '%',
            onChanged: (v) {
              c.setSlotTransform(slotId, zoom: v / 25);
              setState(() {});
            },
          ),
          Text('Drag the photo to reposition it.', style: AppText.caption),
          const SizedBox(height: Space.lg),
        ],
      ),
    );
  }));
}

class _StickerPreview extends StatelessWidget {
  const _StickerPreview(this.path);
  final String path;
  @override
  Widget build(BuildContext context) {
    return SvgPicture.asset(path, fit: BoxFit.contain);
  }
}
