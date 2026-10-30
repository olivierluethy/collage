import 'dart:io';
import 'dart:typed_data';

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
import '../../widgets/coach_tour.dart';
import '../../widgets/sharpened.dart';
import '../../widgets/ui.dart';
import '../flow.dart';
import '../picker/photo_picker_screen.dart';
import '../picker/video_picker_screen.dart';
import '../result/result_screen.dart';
import 'collage_canvas.dart';
import 'editor_controller.dart';
import 'editor_panels.dart';
import 'export_sheet.dart';

enum _Panel { none, layout, borders, background, filter, add, stickers, shapes, text, emoji, gif, layers, crop, photoStyle, draw, replace }

/// The three panels grouped under the "Style" tool, in segment order.
const _stylePanels = [_Panel.borders, _Panel.background, _Panel.filter];

/// The panels reached from the "Add" grid; each shows a back arrow to it.
const _addPanels = [_Panel.text, _Panel.stickers, _Panel.emoji, _Panel.shapes, _Panel.gif, _Panel.draw];

class EditorScreen extends ConsumerStatefulWidget {
  const EditorScreen({super.key, required this.project, required this.pool});
  final CollageProject project;
  final List<String> pool;

  @override
  ConsumerState<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends ConsumerState<EditorScreen> with WidgetsBindingObserver {
  late final EditorController _c;
  final _boundaryKey = GlobalKey();
  final _layoutToolKey = GlobalKey();
  bool _saving = false;

  /// Whether this collage has never been saved (a new or template project).
  late final bool _isNew;

  /// Something changed since the last draft save.
  bool _changed = true;
  bool _leaving = false;

  /// The Style tab last used, so the Style tool reopens where the user was.
  _Panel _styleTab = _Panel.borders;

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
    _c.addListener(_markChanged);
    _isNew = !(ref.read(draftsProvider).valueOrNull?.any((p) => p.id == widget.project.id) ?? false);
    WidgetsBinding.instance.addObserver(this);
    Sharpened.warmUp();
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeTour());
  }

  void _markChanged() => _changed = true;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Going to the background is the last chance to keep the work if the
    // system later kills the app.
    if (state == AppLifecycleState.paused) _autosave(withThumbnail: false);
  }

  /// First visit: a three-step tour (photo slot → swapping & gestures →
  /// Layout tool). Replayable from the ⋯ menu.
  Future<void> _maybeTour({bool force = false}) async {
    final prefs = ref.read(prefsProvider);
    if (!force && prefs.coachSeen('editor_tour')) return;
    await prefs.setCoachSeen('editor_tour');
    // Let the canvas settle (sheet animations, first frame of photos).
    await Future.delayed(Motion.slow);
    if (!mounted) return;
    _closePanel();
    _c.clearSelection();
    final l = context.l10n;
    final hasSlots = _c.project.layout.slots.isNotEmpty;
    await showCoachTour(
      context,
      labels: CoachLabels(
        next: l.t('next'),
        done: l.t('gotIt'),
        skip: l.t('skip'),
        stepOf: (i, n) => '$i/$n',
      ),
      steps: [
        CoachStep(
          target: hasSlots ? _largestSlotRect : _canvasRect,
          title: l.t('tourSlotTitle'),
          body: l.t(hasSlots ? 'tourSlotBody' : 'tourFreeBody'),
        ),
        if (hasSlots)
          CoachStep(
            target: _largestSlotRect,
            title: l.t('tourSwapTitle'),
            body: l.t('tourSwapBody'),
          ),
        CoachStep(
          target: () => _globalRect(_layoutToolKey),
          title: l.t('tourLayoutTitle'),
          body: l.t('tourLayoutBody'),
        ),
      ],
    );
  }

  Rect? _globalRect(GlobalKey key) {
    final box = key.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return null;
    return box.localToGlobal(Offset.zero) & box.size;
  }

  Rect? _canvasRect() => _globalRect(_boundaryKey);

  /// The biggest photo slot on screen — the easiest one to point at.
  Rect? _largestSlotRect() {
    final canvas = _canvasRect();
    final slots = _c.project.layout.slots;
    if (canvas == null || slots.isEmpty) return canvas;
    final s = slots.reduce((a, b) => a.rect.width * a.rect.height >= b.rect.width * b.rect.height ? a : b);
    return Rect.fromLTRB(
      canvas.left + s.rect.left * canvas.width,
      canvas.top + s.rect.top * canvas.height,
      canvas.left + s.rect.right * canvas.width,
      canvas.top + s.rect.bottom * canvas.height,
    ).deflate(4);
  }

  /// Keep the collage as a draft so leaving the editor never loses work. A new
  /// collage is kept once it has photos; any collage once it has been edited.
  Future<void> _autosave({bool withThumbnail = true}) async {
    final p = _c.project;
    final worthKeeping = _c.canUndo || (_isNew && p.fills.isNotEmpty);
    if (!_changed || !worthKeeping || _saving) return;
    final drafts = ref.read(draftServiceProvider);
    final notifier = ref.read(draftsProvider.notifier);
    Uint8List? thumb;
    if (withThumbnail && mounted) {
      _c.clearSelection();
      setState(() => _exporting = true);
      try {
        await Future.delayed(Motion.fast);
        thumb = await ref.read(exportServiceProvider).capture(_boundaryKey, targetWidth: 500);
      } catch (_) {
        thumb = null;
      } finally {
        if (mounted) setState(() => _exporting = false);
      }
    }
    // A save without a thumbnail (app paused) still owes one on leaving.
    if (thumb != null) _changed = false;
    await drafts.save(p, thumbnail: thumb);
    _evictThumbnail();
    await notifier.reload();
  }

  /// The library shows thumbnails with [Image.file], which caches by path;
  /// drop the old picture so the card shows the collage as it is now.
  void _evictThumbnail() {
    final path = _c.project.thumbnailPath;
    if (path != null) FileImage(File(path)).evict();
  }

  /// Back: save the draft, then leave. A brief toast confirms it was kept.
  Future<void> _leave() async {
    if (_leaving || _saving) return;
    _leaving = true;
    _closePanel();
    final hadChanges = _changed && (_c.canUndo || (_isNew && _c.project.fills.isNotEmpty));
    final messenger = ScaffoldMessenger.of(context);
    final savedLabel = context.l10n.t('draftSaved');
    try {
      await _autosave();
    } finally {
      _leaving = false;
    }
    if (!mounted) return;
    Navigator.of(context).pop();
    if (hadChanges) {
      showAppSnackOn(messenger, savedLabel, kind: SnackKind.success, duration: const Duration(seconds: 2));
    }
  }

  Future<void> _rename() async {
    final ctrl = TextEditingController(text: _c.project.title);
    final name = await showDialog<String>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: Text(context.l10n.t('renameCollage')),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          maxLength: 60,
          textInputAction: TextInputAction.done,
          onSubmitted: (v) => Navigator.pop(dialog, v),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialog), child: Text(context.l10n.t('cancel'))),
          TextButton(onPressed: () => Navigator.pop(dialog, ctrl.text), child: Text(context.l10n.t('save'))),
        ],
      ),
    );
    ctrl.dispose();
    final t = name?.trim();
    if (t == null || t.isEmpty || t == _c.project.title) return;
    _c.setTitle(t);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _c.removeListener(_markChanged);
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
      if (mounted) showAppSnack(context, context.l10n.t('templateSaved'), kind: SnackKind.success);
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
      if (_stylePanels.contains(p)) _styleTab = p;
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
        if (mounted) showAppSnack(context, context.l10n.t('couldNotRender'), kind: SnackKind.error);
        return;
      }
      await ref.read(draftServiceProvider).save(_c.project, thumbnail: thumb);
      // Keep a full-size still for photo books.
      if (result.format == ExportFormat.png || result.format == ExportFormat.jpg) {
        await ref.read(draftServiceProvider).saveRender(_c.project.id, result.bytes, result.format.extension);
      } else if (result.format == ExportFormat.pdf) {
        await ref.read(draftServiceProvider).saveRender(_c.project.id, result.preview, 'png');
      }
      _changed = false;
      _evictThumbnail();
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
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _leave();
      },
      child: Scaffold(
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        leading: BackButton(onPressed: _saving ? null : _leave),
        titleSpacing: 0,
        title: AnimatedBuilder(
          animation: _c,
          builder: (context, _) => Tooltip(
            message: context.l10n.t('renameCollage'),
            child: InkWell(
              onTap: _saving ? null : _rename,
              borderRadius: BorderRadius.circular(Radii.control),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: Space.sm, vertical: Space.sm),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(_c.project.title,
                          maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.titleMd),
                    ),
                    const SizedBox(width: Space.xs),
                    Icon(Icons.edit_outlined, size: 16, color: context.colors.textLo),
                  ],
                ),
              ),
            ),
          ),
        ),
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
            tooltip: context.l10n.t('moreActions'),
            onSelected: (v) {
              if (v == 'template') _saveAsTemplate();
              if (v == 'tour') _maybeTour(force: true);
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
              PopupMenuItem(
                value: 'tour',
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.lightbulb_outline_rounded),
                  title: Text(context.l10n.t('showTour')),
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
                  : const Icon(Icons.check_rounded, size: 18),
              label: Text(context.l10n.t('finish')),
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
          _ToolRail(
            active: _panel,
            layoutKey: _layoutToolKey,
            onLayout: () => _togglePanel(_Panel.layout),
            onStyle: () => _togglePanel(_styleTab),
            onAdd: () => _togglePanel(_Panel.add),
            onLayers: () => _togglePanel(_Panel.layers),
            onPhotos: _addPhotos,
          ),
        ],
      ),
    ),
    );
  }

  /// A rail tool opens its panel, or closes it when it's already showing.
  void _togglePanel(_Panel p) {
    final group = _stylePanels.contains(p)
        ? _stylePanels
        : p == _Panel.add
            ? [_Panel.add, ..._addPanels]
            : [p];
    if (group.contains(_panel)) {
      _closePanel();
    } else {
      _openPanel(p);
    }
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
      _Panel.layout => (context.l10n.t('panelLayout'), LayoutPanel(c: _c), 360.0),
      _Panel.add => (context.l10n.t('toolAdd'), _AddGrid(onPick: _onTool), 236.0),
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

    final isStyle = _stylePanels.contains(_panel);
    final fromAdd = _addPanels.contains(_panel);
    // The Style panels share one header: a segmented switch between them.
    const segH = 52.0;
    final bodyH = isStyle ? 360.0 : height;
    return Container(
      height: bodyH + 46 + (isStyle ? segH : 0),
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
                if (fromAdd)
                  IconButton(
                    tooltip: context.l10n.t('back'),
                    onPressed: () => _openPanel(_Panel.add),
                    icon: const Icon(Icons.arrow_back_rounded),
                    color: context.colors.textMid,
                  )
                else
                  const SizedBox(width: Space.lg),
                Expanded(
                  child: Text(isStyle ? context.l10n.t('toolStyle') : title,
                      style: context.text.titleMd, maxLines: 1, overflow: TextOverflow.ellipsis),
                ),
                IconButton(
                  tooltip: context.l10n.t('closePanel'),
                  onPressed: _closePanel,
                  icon: const Icon(Icons.keyboard_arrow_down_rounded),
                  color: context.colors.textMid,
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          if (isStyle)
            SizedBox(
              height: segH,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(Space.lg, Space.sm, Space.lg, 0),
                child: SegmentedButton<_Panel>(
                  showSelectedIcon: false,
                  segments: [
                    ButtonSegment(value: _Panel.borders, label: Text(context.l10n.t('toolBorders')), icon: const Icon(Icons.border_outer_rounded, size: 18)),
                    ButtonSegment(value: _Panel.background, label: Text(context.l10n.t('toolBackground')), icon: const Icon(Icons.gradient_rounded, size: 18)),
                    ButtonSegment(value: _Panel.filter, label: Text(context.l10n.t('toolFilter')), icon: const Icon(Icons.tune_rounded, size: 18)),
                  ],
                  selected: {_panel},
                  onSelectionChanged: (v) => _openPanel(v.first),
                ),
              ),
            ),
          Expanded(child: body),
        ],
      ),
    );
  }
}

/// The "Add" tool: everything that can be placed on the collage, as one grid
/// of big labelled tiles instead of six separate rail entries.
class _AddGrid extends StatelessWidget {
  const _AddGrid({required this.onPick});
  final void Function(_Panel) onPick;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final items = <(_Panel, IconData, String)>[
      (_Panel.text, Icons.title_rounded, l.t('toolText')),
      (_Panel.stickers, Icons.emoji_emotions_outlined, l.t('toolStickers')),
      (_Panel.emoji, Icons.tag_faces_rounded, l.t('toolEmoji')),
      (_Panel.shapes, Icons.category_outlined, l.t('toolShapes')),
      // GIF search needs a Giphy key; without one the tile is simply absent.
      if (Config.hasGiphy) (_Panel.gif, Icons.gif_box_outlined, l.t('toolGif')),
      (_Panel.draw, Icons.brush_rounded, l.t('toolDraw')),
    ];
    return GridView.count(
      crossAxisCount: 3,
      padding: const EdgeInsets.all(Space.lg),
      mainAxisSpacing: Space.sm,
      crossAxisSpacing: Space.sm,
      childAspectRatio: 1.45,
      physics: const NeverScrollableScrollPhysics(),
      children: [
        for (final (panel, icon, label) in items)
          Material(
            color: context.colors.surfaceHigh,
            borderRadius: BorderRadius.circular(Radii.card),
            child: InkWell(
              borderRadius: BorderRadius.circular(Radii.card),
              onTap: () => onPick(panel),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, size: 26, color: context.colors.textHi),
                  const SizedBox(height: Space.xs),
                  Text(label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.text.labelMd.copyWith(color: context.colors.textMid)),
                ],
              ),
            ),
          ),
      ],
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
        // At most four actions: the one that edits this kind of element, the
        // two everyone needs, and "More" for the rest — never a scrolling row.
        return Container(
          decoration: BoxDecoration(
            color: context.colors.surface,
            border: Border(top: BorderSide(color: context.colors.line)),
          ),
          padding: const EdgeInsets.symmetric(horizontal: Space.sm, vertical: 4),
          child: Row(
            children: [
              if (el is TextElement)
                Expanded(child: _CtxBtn(icon: Icons.edit_rounded, label: context.l10n.t('ctxEdit'), onTap: () => onEditText(el))),
              if (el is ImageElement)
                Expanded(child: _CtxBtn(icon: Icons.crop_rounded, label: context.l10n.t('ctxCrop'), onTap: () => onCrop(el))),
              Expanded(child: _CtxBtn(icon: Icons.copy_rounded, label: context.l10n.t('ctxDuplicate'), onTap: () => controller.duplicateElement(el.id))),
              Expanded(child: _CtxBtn(icon: Icons.more_horiz_rounded, label: context.l10n.t('ctxMore'), onTap: () => _more(context, el))),
              Expanded(
                child: _CtxBtn(
                  icon: Icons.delete_outline_rounded,
                  label: context.l10n.t('ctxDelete'),
                  color: context.colors.danger,
                  onTap: () => controller.deleteElement(el.id),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  /// The less frequent element actions, in one sheet.
  Future<void> _more(BuildContext context, CanvasElement el) async {
    final l = context.l10n;
    final c = controller;
    final items = <(IconData, int, String, VoidCallback)>[
      if (el is ImageElement) ...[
        (Icons.flip_rounded, 0, l.t('ctxFlipH'), () => c.flipElement(el.id, horizontal: true)),
        (Icons.flip_rounded, 1, l.t('ctxFlipV'), () => c.flipElement(el.id, vertical: true)),
      ],
      (Icons.flip_to_front_rounded, 0, l.t('ctxForward'), () => c.bringForward(el.id)),
      (Icons.flip_to_back_rounded, 0, l.t('ctxBack'), () => c.sendBackward(el.id)),
      (Icons.restart_alt_rounded, 0, l.t('ctxStraighten'), () => c.updateTransform(el.id, rotation: 0)),
    ];
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheet) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final (icon, turns, label, action) in items)
              ListTile(
                leading: RotatedBox(quarterTurns: turns, child: Icon(icon)),
                title: Text(label),
                onTap: () {
                  Navigator.pop(sheet);
                  action();
                },
              ),
          ],
        ),
      ),
    );
  }
}

class _CtxBtn extends StatelessWidget {
  const _CtxBtn({required this.icon, required this.label, required this.onTap, this.color});
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = color ?? context.colors.textMid;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(Radii.control),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: Sizes.touchTarget),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: Space.xs, vertical: Space.sm),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: c, size: 22),
              const SizedBox(height: 2),
              Text(label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.text.caption.copyWith(color: c)),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Bottom tool rail (labels never overlap)
// ---------------------------------------------------------------------------

class _ToolRail extends StatelessWidget {
  const _ToolRail({
    required this.active,
    required this.layoutKey,
    required this.onLayout,
    required this.onStyle,
    required this.onAdd,
    required this.onLayers,
    required this.onPhotos,
  });
  final _Panel active;
  final GlobalKey layoutKey;
  final VoidCallback onLayout;
  final VoidCallback onStyle;
  final VoidCallback onAdd;
  final VoidCallback onLayers;
  final VoidCallback onPhotos;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    // Five tools, always all on screen: what's in the collage (Photos), how
    // it's arranged (Layout), how it looks (Style), what's on top (Add) and
    // the stack of it all (Layers).
    final tools = <(Key?, IconData, String, bool, VoidCallback)>[
      (null, Icons.add_photo_alternate_outlined, l.t('toolPhotos'), false, onPhotos),
      (layoutKey, Icons.grid_view_rounded, l.t('toolLayout'), active == _Panel.layout, onLayout),
      (null, Icons.palette_outlined, l.t('toolStyle'), _stylePanels.contains(active), onStyle),
      (null, Icons.add_circle_outline_rounded, l.t('toolAdd'), active == _Panel.add || _addPanels.contains(active), onAdd),
      (null, Icons.layers_outlined, l.t('toolLayers'), active == _Panel.layers, onLayers),
    ];
    return Container(
      decoration: BoxDecoration(
        color: context.colors.surface,
        border: Border(top: BorderSide(color: context.colors.line)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 72,
          child: Row(
            children: [
              for (final (key, icon, label, isActive, onTap) in tools)
                Expanded(
                  child: Padding(
                    key: key,
                    padding: const EdgeInsets.symmetric(horizontal: 2, vertical: Space.xs),
                    child: Semantics(
                      selected: isActive,
                      button: true,
                      child: InkWell(
                        onTap: onTap,
                        borderRadius: BorderRadius.circular(Radii.control),
                        child: AnimatedContainer(
                          duration: Motion.fast,
                          decoration: BoxDecoration(
                            color: isActive ? context.colors.amberTint : null,
                            borderRadius: BorderRadius.circular(Radii.control),
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(icon, color: isActive ? context.colors.amber : context.colors.textMid, size: 24),
                              const SizedBox(height: 4),
                              Text(
                                label,
                                maxLines: 1,
                                softWrap: false,
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.center,
                                style: context.text.labelMd.copyWith(
                                    color: isActive ? context.colors.amber : context.colors.textMid),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
