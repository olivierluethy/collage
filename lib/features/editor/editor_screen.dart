import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../config.dart';
import '../../l10n/app_localizations.dart';
import '../../models/canvas_element.dart';
import '../../models/collage_project.dart';
import '../../services/export_service.dart';
import '../../state/providers.dart';
import '../../theme/palette.dart';
import '../../theme/tokens.dart';
import '../../theme/typography.dart';
import '../../widgets/sharpened.dart';
import '../flow.dart';
import '../picker/photo_picker_screen.dart';
import '../picker/video_picker_screen.dart';
import '../result/result_screen.dart';
import 'collage_canvas.dart';
import 'editor_controller.dart';
import 'editor_panels.dart';
import 'export_sheet.dart';

enum _Panel { none, layout, borders, background, filter, stickers, shapes, text, emoji, gif, layers, crop, photoStyle, draw, replace }

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
  String? _cropElementId;
  String? _styleSlotId;

  @override
  void initState() {
    super.initState();
    _c = EditorController(project: widget.project, pool: widget.pool);
    Sharpened.warmUp();
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeCoach());
  }

  Future<void> _maybeCoach() async {
    final prefs = ref.read(prefsProvider);
    if (prefs.coachSeen('editor_slots')) return;
    await prefs.setCoachSeen('editor_slots');
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      duration: const Duration(seconds: 7),
      content: Text(context.l10n.t('coachEditorSlots')),
      action: SnackBarAction(label: context.l10n.t('gotIt'), onPressed: () {}),
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
    // Leaving the draw tool keeps what was drawn as one movable element.
    if (_panel == _Panel.draw && _c.drawing) _c.finishDrawing(_canvasSize());
  }

  /// The canvas's current on-screen size (zero before first layout).
  Size _canvasSize() {
    final box = _boundaryKey.currentContext?.findRenderObject() as RenderBox?;
    return box?.size ?? Size.zero;
  }

  void _openStyle(String slotId) {
    setState(() {
      _cleanupPanel();
      _styleSlotId = slotId;
      _panel = _Panel.photoStyle;
    });
  }

  Future<void> _pickVideo(String slotId) async {
    _closePanel();
    final id = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const VideoPickerScreen()),
    );
    if (id != null) _c.setSlotVideo(slotId, id);
  }

  void _openDraw() {
    setState(() {
      _cleanupPanel();
      _c.startDrawing();
      _panel = _Panel.draw;
    });
  }

  /// Save the current design (without photos) as one of the user's templates.
  Future<void> _saveAsTemplate() async {
    _closePanel();
    _c.clearSelection();
    final ctrl = TextEditingController(text: _c.project.title);
    final name = await showDialog<String>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: Text(context.l10n.t('saveAsTemplate')),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          maxLength: 60,
          decoration: InputDecoration(hintText: context.l10n.t('templateName')),
          onSubmitted: (v) => Navigator.pop(dialog, v),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialog), child: Text(context.l10n.t('cancel'))),
          TextButton(onPressed: () => Navigator.pop(dialog, ctrl.text), child: Text(context.l10n.t('save'))),
        ],
      ),
    );
    ctrl.dispose();
    final n = name?.trim();
    if (n == null || n.isEmpty || !mounted) return;
    setState(() => _exporting = true);
    try {
      await Future.delayed(Motion.fast);
      final thumb = await ref.read(exportServiceProvider).capture(_boundaryKey, targetWidth: 500);
      await ref.read(userTemplateServiceProvider).saveFrom(
            _c.project,
            id: const Uuid().v4(),
            name: n,
            thumbnail: thumb,
          );
      await ref.read(userTemplatesProvider.notifier).reload();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.l10n.t('templateSaved'))));
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
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
    final el = _c.addText(context.l10n.t('defaultText'), color: 0xFFF5EFE7);
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
    // Templates open straight into the editor with no photos, so ask for gallery
    // access here the first time the user reaches for the Photos tool.
    if (!await ensureGalleryAccess(context, ref)) return;
    if (!mounted) return;
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

  ExportOptions _lastExportOptions() {
    final prefs = ref.read(prefsProvider);
    return ExportOptions(
      format: ExportFormat.values.asNameMap()[prefs.exportFormatName] ?? ExportFormat.png,
      size: ExportSize.values.asNameMap()[prefs.exportSizeName] ?? ExportSize.standard,
    );
  }

  Future<void> _save() async {
    _closePanel();
    _c.clearSelection();
    final options = await showExportSheet(
      context,
      _lastExportOptions(),
      allowGif: _c.project.elements.any((e) => e is GifElement),
      allowVideo: _c.project.fills.values.any((f) => f.isVideo),
    );
    if (options == null || !mounted) return;
    await ref.read(prefsProvider).setExportChoice(format: options.format.name, size: options.size.name);
    if (!mounted) return;
    // Render a clean, non-interactive frame so no edit badges, action chips or
    // selection handles are captured into the exported PNG.
    setState(() {
      _saving = true;
      _exporting = true;
    });
    try {
      await Future.delayed(Motion.fast);
      final export = ref.read(exportServiceProvider);
      final ratio = _c.project.ratio;
      final result = await export.captureAs(
        _boundaryKey,
        options,
        a4Page: ratio.isPrint,
        landscape: ratio == CanvasRatio.a4Landscape,
      );
      final thumb = await export.capture(_boundaryKey, targetWidth: 500);
      if (result == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(context.l10n.t('couldNotRender'))));
        }
        return;
      }
      await ref.read(draftServiceProvider).save(_c.project, thumbnail: thumb);
      // Keep a full-size still for photo books.
      if (result.format == ExportFormat.png || result.format == ExportFormat.jpg) {
        await ref.read(draftServiceProvider).saveRender(_c.project.id, result.bytes, result.format.extension);
      } else if (result.format == ExportFormat.pdf) {
        await ref.read(draftServiceProvider).saveRender(_c.project.id, result.preview, 'png');
      }
      await ref.read(draftsProvider.notifier).reload();
      if (!mounted) return;
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => ResultScreen(project: _c.project, result: result)));
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
        title: Text(context.l10n.t('editorTitle')),
        actions: [
          AnimatedBuilder(
            animation: _c,
            builder: (context, _) => Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: context.l10n.t('undo'),
                  onPressed: _c.canUndo && !_saving ? _undo : null,
                  icon: const Icon(Icons.undo_rounded),
                ),
                IconButton(
                  tooltip: context.l10n.t('redo'),
                  onPressed: _c.canRedo && !_saving ? _redo : null,
                  icon: const Icon(Icons.redo_rounded),
                ),
              ],
            ),
          ),
          PopupMenuButton<String>(
            enabled: !_saving,
            onSelected: (v) {
              if (v == 'template') _saveAsTemplate();
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'template',
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.bookmark_add_outlined),
                  title: Text(context.l10n.t('saveAsTemplate')),
                ),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(right: Space.sm),
            child: FilledButton.icon(
              onPressed: _saving ? null : _save,
              icon: _saving
                  ? SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: context.colors.onAmber))
                  : const Icon(Icons.save_alt_rounded, size: 18),
              label: Text(context.l10n.t('save')),
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
                      onRequestStyle: _openStyle,
                      onRequestVideo: _pickVideo,
                    ),
                  ),
                ),
              ),
            ),
          ),
          _ContextBar(
            controller: _c,
            onEditText: (e) {
              setState(() { _editingTextId = e.id; _panel = _Panel.text; });
            },
            onCrop: (e) {
              setState(() {
                _cleanupPanel();
                _cropElementId = e.id;
                _panel = _Panel.crop;
              });
            },
          ),
          if (_panel != _Panel.none) _panelHost(context),
          _ToolRail(active: _panel, onTool: _onTool, onPhotos: _addPhotos),
        ],
      ),
    );
  }

  /// Undo/redo close any open panel first: a panel may hold state (the text
  /// being typed, a replace preview) that the restored snapshot doesn't have.
  void _undo() {
    _closePanel();
    _c.undo();
  }

  void _redo() {
    _closePanel();
    _c.redo();
  }

  void _onTool(_Panel p) {
    if (p == _Panel.text) { _openText(); return; }
    if (p == _Panel.draw) { _openDraw(); return; }
    _openPanel(p);
  }

  Widget _panelHost(BuildContext context) {
    final h = MediaQuery.of(context).size.height;
    final (title, body, height) = switch (_panel) {
      _Panel.layout => (context.l10n.t('panelLayout'), LayoutPanel(c: _c), 340.0),
      _Panel.borders => (context.l10n.t('panelBorders'), BordersPanel(c: _c), 280.0),
      _Panel.background => (context.l10n.t('panelBackground'), BackgroundPanel(c: _c), 330.0),
      _Panel.filter => (context.l10n.t('panelFilter'), FilterPanel(c: _c), 360.0),
      _Panel.stickers => (context.l10n.t('panelStickers'), StickersPanel(c: _c, onAdded: _closePanel), (h * 0.44).clamp(320, 460)),
      _Panel.shapes => (context.l10n.t('panelShapes'), ShapesPanel(c: _c, onAdded: _closePanel), (h * 0.42).clamp(300, 440)),
      _Panel.text => (context.l10n.t('panelText'), TextPanel(c: _c, elementId: _editingTextId ?? ''), (h * 0.46).clamp(340, 460)),
      _Panel.emoji => (context.l10n.t('panelEmoji'), EmojiPanel(c: _c, onAdded: _closePanel), (h * 0.44).clamp(320, 460)),
      // Only reachable when a Giphy key is configured (see _ToolRail).
      _Panel.gif => (context.l10n.t('panelGif'), GiphyPanel(c: _c, giphy: ref.read(giphyServiceProvider), onAdded: _closePanel), (h * 0.46).clamp(340, 480)),
      _Panel.layers => (context.l10n.t('panelLayers'), LayersPanel(c: _c), (h * 0.40).clamp(280, 420)),
      _Panel.crop => (context.l10n.t('panelCrop'), CropPanel(c: _c, elementId: _cropElementId ?? ''), 290.0),
      _Panel.photoStyle => (
          context.l10n.t('panelPhotoStyle'),
          PhotoStylePanel(c: _c, slotId: _styleSlotId ?? '', onCutout: _closePanel),
          (h * 0.5).clamp(360, 500),
        ),
      _Panel.draw => (context.l10n.t('panelDraw'), DrawPanel(c: _c, onDone: _closePanel), 250.0),
      _Panel.replace => (context.l10n.t('panelChoosePhoto'), ReplacePanel(c: _c, slotId: _replaceSlotId ?? '', onDone: _closePanel), (h * 0.46).clamp(340, 480)),
      _Panel.none => ('', const SizedBox.shrink(), 0.0),
    };

    return Container(
      height: height + 46,
      decoration: BoxDecoration(
        color: context.colors.surface,
        border: Border(top: BorderSide(color: context.colors.line)),
        boxShadow: Shadows.e2,
      ),
      child: Column(
        children: [
          SizedBox(
            height: 46,
            child: Row(
              children: [
                const SizedBox(width: Space.lg),
                Text(title, style: context.text.titleMd),
                const Spacer(),
                IconButton(onPressed: _closePanel, icon: const Icon(Icons.keyboard_arrow_down_rounded), color: context.colors.textMid),
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
  const _ContextBar({required this.controller, required this.onEditText, required this.onCrop});
  final EditorController controller;
  final void Function(TextElement e) onEditText;
  final void Function(ImageElement e) onCrop;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final el = controller.selectedElement;
        if (el == null) return const SizedBox.shrink();
        return Container(
          color: context.colors.surface,
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
                      _CtxBtn(icon: Icons.edit_rounded, label: context.l10n.t('ctxEdit'), onTap: () => onEditText(el)),
                    if (el is ImageElement) ...[
                      _CtxBtn(icon: Icons.crop_rounded, label: context.l10n.t('ctxCrop'), onTap: () => onCrop(el)),
                      _CtxBtn(icon: Icons.flip_rounded, label: context.l10n.t('ctxFlipH'), onTap: () => controller.flipElement(el.id, horizontal: true)),
                      _CtxBtn(icon: Icons.flip_rounded, turns: 1, label: context.l10n.t('ctxFlipV'), onTap: () => controller.flipElement(el.id, vertical: true)),
                    ],
                    _CtxBtn(icon: Icons.copy_rounded, label: context.l10n.t('ctxDuplicate'), onTap: () => controller.duplicateElement(el.id)),
                    _CtxBtn(icon: Icons.flip_to_front_rounded, label: context.l10n.t('ctxForward'), onTap: () => controller.bringForward(el.id)),
                    _CtxBtn(icon: Icons.flip_to_back_rounded, label: context.l10n.t('ctxBack'), onTap: () => controller.sendBackward(el.id)),
                    _CtxBtn(icon: Icons.restart_alt_rounded, label: context.l10n.t('ctxStraighten'), onTap: () => controller.updateTransform(el.id, rotation: 0)),
                    _CtxBtn(icon: Icons.delete_outline_rounded, label: context.l10n.t('ctxDelete'), color: context.colors.danger, onTap: () => controller.deleteElement(el.id)),
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
    final c = color ?? context.colors.textMid;
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
            Text(label, style: context.text.caption.copyWith(color: c)),
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
      (_Panel.layout, Icons.grid_view_rounded, context.l10n.t('toolLayout')),
      (_Panel.none, Icons.add_photo_alternate_outlined, context.l10n.t('toolPhotos')),
      (_Panel.borders, Icons.border_outer_rounded, context.l10n.t('toolBorders')),
      (_Panel.background, Icons.gradient_rounded, context.l10n.t('toolBackground')),
      (_Panel.filter, Icons.tune_rounded, context.l10n.t('toolFilter')),
      (_Panel.stickers, Icons.emoji_emotions_outlined, context.l10n.t('toolStickers')),
      (_Panel.shapes, Icons.category_outlined, context.l10n.t('toolShapes')),
      (_Panel.text, Icons.title_rounded, context.l10n.t('toolText')),
      (_Panel.emoji, Icons.tag_faces_rounded, context.l10n.t('toolEmoji')),
      // GIF search needs a Giphy key; without one the tool is simply absent.
      if (Config.hasGiphy) (_Panel.gif, Icons.gif_box_outlined, context.l10n.t('toolGif')),
      (_Panel.draw, Icons.brush_rounded, context.l10n.t('toolDraw')),
      (_Panel.layers, Icons.layers_outlined, context.l10n.t('toolLayers')),
    ];
    return Container(
      decoration: BoxDecoration(
        color: context.colors.surface,
        border: Border(top: BorderSide(color: context.colors.line)),
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
              final color = isActive ? context.colors.amber : context.colors.textMid;
              return InkWell(
                onTap: () => panel == _Panel.none ? onPhotos() : onTool(panel),
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
                          style: context.text.labelMd.copyWith(color: color),
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
