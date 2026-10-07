import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/canvas_element.dart';
import '../../models/collage_project.dart';
import '../../state/providers.dart';
import '../../theme/text_styles.dart';
import '../../theme/tokens.dart';
import '../picker/photo_picker_screen.dart';
import '../result/result_screen.dart';
import 'collage_canvas.dart';
import 'editor_controller.dart';
import 'editor_panels.dart';

enum _Panel { none, layout, borders, background, filter, stickers, shapes, text, emoji, gif, replace }

class EditorScreen extends ConsumerStatefulWidget {
  const EditorScreen({super.key, required this.project, required this.pool});
  final CollageProject project;
  final List<String> pool;

  @override
  ConsumerState<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends ConsumerState<EditorScreen> {
  late final EditorController _c;
  final _boundaryKey = GlobalKey();
  bool _saving = false;

  /// While true the canvas renders without any editing chrome (badges, chips,
  /// element handles) so the captured PNG contains only the artwork.
  bool _exporting = false;

  _Panel _panel = _Panel.none;
  String? _editingTextId;
  String? _replaceSlotId;

  @override
  void initState() {
    super.initState();
    _c = EditorController(project: widget.project, pool: widget.pool);
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeCoach());
  }

  Future<void> _maybeCoach() async {
    final prefs = ref.read(prefsProvider);
    if (prefs.coachSeen('editor_slots')) return;
    await prefs.setCoachSeen('editor_slots');
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      duration: const Duration(seconds: 7),
      content: const Text('Tap any photo to Replace, Swap or Clear it. Or drag one '
          'photo onto another to swap them.'),
      action: SnackBarAction(label: 'Got it', onPressed: () {}),
    ));
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  // ---- panel management ----------------------------------------------------
  void _cleanupPanel() {
    if (_panel == _Panel.text && _editingTextId != null) {
      final e = _c.selectedElement;
      if (e is TextElement && e.text.trim().isEmpty) _c.deleteElement(e.id);
      _editingTextId = null;
    }
    if (_panel == _Panel.replace) {
      _c.cancelReplace();
      _replaceSlotId = null;
    }
  }

  void _closePanel() {
    setState(() {
      _cleanupPanel();
      _panel = _Panel.none;
    });
  }

  void _openPanel(_Panel p) {
    setState(() {
      _cleanupPanel();
      _panel = p;
    });
  }

  void _openText() {
    final el = _c.addText('Your text', color: 0xFFF5EFE7);
    setState(() {
      _cleanupPanel();
      _editingTextId = el.id;
      _panel = _Panel.text;
    });
  }

  void _openReplace(String slotId) {
    _c.startReplace(slotId);
    setState(() {
      _cleanupPanel();
      _replaceSlotId = slotId;
      _panel = _Panel.replace;
    });
  }

  Future<void> _addPhotos() async {
    final picked = await Navigator.of(context).push<List<String>>(
      MaterialPageRoute(builder: (_) => const PhotoPickerScreen(maxImages: 9)),
    );
    if (picked == null) return;
    final freeform = _c.project.layout.slots.isEmpty;
    for (final id in picked) {
      _c.addToPool(id);
      if (freeform) {
        final asset = await ref.read(galleryServiceProvider).byId(id);
        _c.addImageElement(id, asset == null ? 1.0 : ref.read(galleryServiceProvider).aspectOf(asset));
      }
    }
    if (!freeform) _c.autofill();
  }

  Future<void> _save() async {
    _closePanel();
    _c.clearSelection();
    // Render a clean, non-interactive frame so no edit badges, action chips or
    // selection handles are captured into the exported PNG.
    setState(() {
      _saving = true;
      _exporting = true;
    });
    try {
      await Future.delayed(Motion.fast);
      final export = ref.read(exportServiceProvider);
      final png = await export.capture(_boundaryKey, targetWidth: 2048);
      final thumb = await export.capture(_boundaryKey, targetWidth: 500);
      if (png == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not render the collage. Try again.')));
        }
        return;
      }
      await ref.read(draftServiceProvider).save(_c.project, thumbnail: thumb);
      await ref.read(draftsProvider.notifier).reload();
      if (!mounted) return;
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => ResultScreen(project: _c.project, png: png)));
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
          _exporting = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        leading: const BackButton(),
        title: const Text('Editor'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: Space.sm),
            child: FilledButton.icon(
              onPressed: _saving ? null : _save,
              icon: _saving
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.onAmber))
                  : const Icon(Icons.save_alt_rounded, size: 18),
              label: const Text('Save'),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          // Canvas — always visible, shrinks to fit the space above any panel.
          Expanded(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(Space.md),
                child: AspectRatio(
                  aspectRatio: _c.project.ratio.value,
                  child: RepaintBoundary(
                    key: _boundaryKey,
                    child: CollageCanvas(
                      controller: _c,
                      interactive: !_exporting,
                      onRequestReplace: _openReplace,
                    ),
                  ),
                ),
              ),
            ),
          ),
          _ContextBar(controller: _c, onEditText: (e) {
            setState(() { _editingTextId = e.id; _panel = _Panel.text; });
          }),
          if (_panel != _Panel.none) _panelHost(context),
          _ToolRail(active: _panel, onTool: _onTool, onPhotos: _addPhotos),
        ],
      ),
    );
  }

  void _onTool(_Panel p) {
    if (p == _Panel.text) { _openText(); return; }
    _openPanel(p);
  }

  Widget _panelHost(BuildContext context) {
    final h = MediaQuery.of(context).size.height;
    final (title, body, height) = switch (_panel) {
      _Panel.layout => ('Layout', LayoutPanel(c: _c), 340.0),
      _Panel.borders => ('Borders & spacing', BordersPanel(c: _c), 280.0),
      _Panel.background => ('Background', BackgroundPanel(c: _c), 270.0),
      _Panel.filter => ('Filter', FilterPanel(c: _c), 360.0),
      _Panel.stickers => ('Stickers', StickersPanel(c: _c, onAdded: _closePanel), (h * 0.44).clamp(320, 460)),
      _Panel.shapes => ('Shapes', ShapesPanel(c: _c, onAdded: _closePanel), (h * 0.42).clamp(300, 440)),
      _Panel.text => ('Text', TextPanel(c: _c, elementId: _editingTextId ?? ''), 260.0),
      _Panel.emoji => ('Emoji', EmojiPanel(c: _c, onAdded: _closePanel), (h * 0.44).clamp(320, 460)),
      _Panel.gif => ('GIFs', GiphyPanel(c: _c, giphy: ref.read(giphyServiceProvider), onAdded: _closePanel), (h * 0.46).clamp(340, 480)),
      _Panel.replace => ('Choose a photo', ReplacePanel(c: _c, slotId: _replaceSlotId ?? '', onDone: _closePanel), (h * 0.46).clamp(340, 480)),
      _Panel.none => ('', const SizedBox.shrink(), 0.0),
    };

    return Container(
      height: height + 46,
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.line)),
        boxShadow: Shadows.e2,
      ),
      child: Column(
        children: [
          SizedBox(
            height: 46,
            child: Row(
              children: [
                const SizedBox(width: Space.lg),
                Text(title, style: AppText.titleMd),
                const Spacer(),
                IconButton(onPressed: _closePanel, icon: const Icon(Icons.keyboard_arrow_down_rounded), color: AppColors.textMid),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(child: body),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Contextual element bar
// ---------------------------------------------------------------------------

class _ContextBar extends StatelessWidget {
  const _ContextBar({required this.controller, required this.onEditText});
  final EditorController controller;
  final void Function(TextElement e) onEditText;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final el = controller.selectedElement;
        if (el == null) return const SizedBox.shrink();
        return Container(
          color: AppColors.surface,
          padding: const EdgeInsets.symmetric(horizontal: Space.sm, vertical: 4),
          child: LayoutBuilder(
            // Floats the actions evenly when they fit, and scrolls instead of
            // overflowing once a free photo adds its Flip buttons.
            builder: (context, constraints) => SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: ConstrainedBox(
                constraints: BoxConstraints(minWidth: constraints.maxWidth),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    if (el is TextElement)
                      _CtxBtn(icon: Icons.edit_rounded, label: 'Edit', onTap: () => onEditText(el)),
                    if (el is ImageElement) ...[
                      _CtxBtn(icon: Icons.flip_rounded, label: 'Flip H', onTap: () => controller.flipElement(el.id, horizontal: true)),
                      _CtxBtn(icon: Icons.flip_rounded, turns: 1, label: 'Flip V', onTap: () => controller.flipElement(el.id, vertical: true)),
                    ],
                    _CtxBtn(icon: Icons.flip_to_front_rounded, label: 'Forward', onTap: () => controller.bringForward(el.id)),
                    _CtxBtn(icon: Icons.flip_to_back_rounded, label: 'Back', onTap: () => controller.sendBackward(el.id)),
                    _CtxBtn(icon: Icons.restart_alt_rounded, label: 'Straighten', onTap: () => controller.updateTransform(el.id, rotation: 0)),
                    _CtxBtn(icon: Icons.delete_outline_rounded, label: 'Delete', color: AppColors.danger, onTap: () => controller.deleteElement(el.id)),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _CtxBtn extends StatelessWidget {
  const _CtxBtn({required this.icon, required this.label, required this.onTap, this.color, this.turns = 0});
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? color;
  final int turns; // quarter-turns applied to [icon] (1 → vertical mirror)

  @override
  Widget build(BuildContext context) {
    final c = color ?? AppColors.textMid;
    Widget iconWidget = Icon(icon, color: c, size: 22);
    if (turns != 0) iconWidget = RotatedBox(quarterTurns: turns, child: iconWidget);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(Radii.control),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: Space.sm, vertical: Space.sm),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            iconWidget,
            const SizedBox(height: 2),
            Text(label, style: AppText.caption.copyWith(color: c)),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Bottom tool rail (labels never overlap)
// ---------------------------------------------------------------------------

class _ToolRail extends StatelessWidget {
  const _ToolRail({required this.active, required this.onTool, required this.onPhotos});
  final _Panel active;
  final void Function(_Panel) onTool;
  final VoidCallback onPhotos;

  @override
  Widget build(BuildContext context) {
    final tools = <(_Panel, IconData, String)>[
      (_Panel.layout, Icons.grid_view_rounded, 'Layout'),
      (_Panel.none, Icons.add_photo_alternate_outlined, 'Photos'),
      (_Panel.borders, Icons.border_outer_rounded, 'Borders'),
      (_Panel.background, Icons.gradient_rounded, 'Background'),
      (_Panel.filter, Icons.tune_rounded, 'Filter'),
      (_Panel.stickers, Icons.emoji_emotions_outlined, 'Stickers'),
      (_Panel.shapes, Icons.category_outlined, 'Shapes'),
      (_Panel.text, Icons.title_rounded, 'Text'),
      (_Panel.emoji, Icons.tag_faces_rounded, 'Emoji'),
      (_Panel.gif, Icons.gif_box_outlined, 'GIF'),
    ];
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.line)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 74,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: Space.xs),
            itemCount: tools.length,
            itemBuilder: (_, i) {
              final (panel, icon, label) = tools[i];
              final isActive = panel != _Panel.none && panel == active;
              final color = isActive ? AppColors.amber : AppColors.textMid;
              return InkWell(
                onTap: () => label == 'Photos' ? onPhotos() : onTool(panel),
                borderRadius: BorderRadius.circular(Radii.control),
                child: Container(
                  width: 78,
                  alignment: Alignment.center,
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(icon, color: color, size: 24),
                      const SizedBox(height: 6),
                      SizedBox(
                        width: 72,
                        child: Text(
                          label,
                          maxLines: 1,
                          softWrap: false,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: AppText.labelMd.copyWith(color: color),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
