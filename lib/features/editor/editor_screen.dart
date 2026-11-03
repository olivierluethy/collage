import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
import '../picker/photo_picker_screen.dart';
import '../picker/picker_flow.dart';
import '../picker/video_picker_screen.dart';
import '../result/result_screen.dart';
import 'collage_canvas.dart';
import 'editor_controller.dart';
import 'edge_panel.dart';
import 'editor_panels.dart';
import 'export_sheet.dart';

enum _Panel { none, layout, borders, background, filter, add, stickers, shapes, text, emoji, gif, layers, crop, photoStyle, draw, replace, edges, photoLayer }

/// The three panels grouped under the "Style" tool, in segment order.
const _stylePanels = [_Panel.borders, _Panel.background, _Panel.filter];

/// The panels reached from the "Add" grid; each shows a back arrow to it.
const _addPanels = [_Panel.text, _Panel.stickers, _Panel.emoji, _Panel.shapes, _Panel.gif, _Panel.draw];

/// Pseudo-panel of the Add grid: pick a photo and add it as its own layer.
const _addPhotoLayer = _Panel.photoLayer;

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
  final _trashKey = GlobalKey();
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
  String? _photoLayerId;

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
    _keysNode.dispose();
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
    if (_panel == _Panel.edges && _c.edgeEditing) _c.endEdgeEditing();
    if (_panel == _Panel.photoLayer) {
      if (_c.adjustingImageId != null) _c.setAdjustingImage(null);
      if (_c.editingMaskId != null) _c.setEditingMask(null);
    }
  }

  /// Open shape & photo controls for a photo layer.
  void _openPhotoLayer(String id) {
    setState(() {
      _cleanupPanel();
      _photoLayerId = id;
      _panel = _Panel.photoLayer;
    });
  }

  /// Pick one photo from the gallery: (asset id, aspect) or null.
  Future<(String, double)?> _pickOnePhoto() async {
    final picked = await Navigator.of(context).push<List<String>>(
      MaterialPageRoute(builder: (_) => const PhotoPickerScreen(maxImages: 1)),
    );
    if (picked == null || picked.isEmpty) return null;
    final gallery = ref.read(galleryServiceProvider);
    final asset = await gallery.byId(picked.first);
    return (picked.first, asset == null ? 1.0 : gallery.aspectOf(asset));
  }

  /// Add: a photo as its own layer over the collage, then straight to its
  /// shape controls (star, oval, …).
  Future<void> _addPhotoLayerFlow() async {
    _closePanel();
    final p = await _pickOnePhoto();
    if (p == null || !mounted) return;
    _c.addPhotoLayer(p.$1, p.$2);
    final id = _c.selectedElementId;
    if (id != null) _openPhotoLayer(id);
  }

  Future<void> _chooseLayerPhoto(String id) async {
    final p = await _pickOnePhoto();
    if (p == null || !mounted) return;
    _c.setLayerPhoto(id, p.$1, p.$2);
  }

  void _openEdges() {
    setState(() {
      _cleanupPanel();
      _c.startEdgeEditing();
      _panel = _Panel.edges;
    });
  }

  // ---- delete with undo ----------------------------------------------------
  /// Whether a finger at [global] is over the trash target.
  bool _isOverTrash(Offset global) => _globalRect(_trashKey)?.inflate(12).contains(global) ?? false;

  /// A short snackbar with an Undo action — every delete in the editor can be
  /// taken back.
  void _undoSnack(String message) {
    showAppSnack(
      context,
      message,
      actionLabel: context.l10n.t('undo'),
      onAction: _undo,
      duration: const Duration(seconds: 4),
    );
  }

  void _deleteElement(String id) {
    HapticFeedback.mediumImpact();
    _c.deleteElement(id);
    _undoSnack(context.l10n.t('elementDeleted'));
  }

  void _removeSlotPhoto(String slotId) {
    if (_c.fillFor(slotId) == null) return;
    HapticFeedback.mediumImpact();
    _c.clearSlot(slotId);
    _undoSnack(context.l10n.t('photoRemoved'));
  }

  /// The pencil on a photo: select it and open its photo controls.
  void _editSlot(String slotId) {
    HapticFeedback.selectionClick();
    _c.selectSlot(slotId);
    _openStyle(slotId);
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
    // Back to the editor's own keys once a panel (and its text field) is gone.
    if (mounted && !_keysNode.hasFocus) _keysNode.requestFocus();
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

  /// The Photos tool: the picker opens with this collage's photos already
  /// selected (with the right count), and the result replaces the selection —
  /// removed photos leave their slots, new ones fill empty slots, every other
  /// edit stays. One undo step, confirmed with a snackbar.
  Future<void> _addPhotos() async {
    _closePanel();
    final before = _c.selectedPhotos;
    final picked = await pickCollagePhotos(
      context,
      ref,
      current: before,
      collageId: _c.project.id,
      placed: _c.project.assetIds,
    );
    if (picked == null || !mounted) return;
    final diff = diffSelection(before, picked);
    if (!diff.hasChanges) return;
    _c.applyPhotoSelection(picked);
    if (_c.project.layout.slots.isEmpty) {
      // Freeform: each new photo becomes a movable element.
      final gallery = ref.read(galleryServiceProvider);
      for (final id in diff.added) {
        final asset = await gallery.byId(id);
        _c.addImageElement(id, asset == null ? 1.0 : gallery.aspectOf(asset));
      }
    }
    if (!mounted) return;
    final l = context.l10n;
    final parts = [
      if (diff.added.isNotEmpty) l.a('photosAdded', {'n': '${diff.added.length}'}),
      if (diff.removed.isNotEmpty) l.a('photosRemovedCount', {'n': '${diff.removed.length}'}),
    ];
    _undoSnack(parts.join(' · '));
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
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => ResultScreen(project: _c.project, result: result, thumbnail: thumb),
      ));
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
          _exporting = false;
        });
      }
    }
  }

  // ---- keyboard ---------------------------------------------------------------
  final _keysNode = FocusNode(debugLabel: 'editor-keys');

  static const _keyMap = <ShortcutActivator, _KeyIntent>{
    SingleActivator(LogicalKeyboardKey.keyZ, meta: true): _KeyIntent('undo'),
    SingleActivator(LogicalKeyboardKey.keyZ, control: true): _KeyIntent('undo'),
    SingleActivator(LogicalKeyboardKey.keyZ, meta: true, shift: true): _KeyIntent('redo'),
    SingleActivator(LogicalKeyboardKey.keyZ, control: true, shift: true): _KeyIntent('redo'),
    SingleActivator(LogicalKeyboardKey.keyY, control: true): _KeyIntent('redo'),
    SingleActivator(LogicalKeyboardKey.delete): _KeyIntent('delete'),
    SingleActivator(LogicalKeyboardKey.backspace): _KeyIntent('delete'),
    SingleActivator(LogicalKeyboardKey.keyD, meta: true): _KeyIntent('duplicate'),
    SingleActivator(LogicalKeyboardKey.keyD, control: true): _KeyIntent('duplicate'),
    SingleActivator(LogicalKeyboardKey.bracketRight): _KeyIntent('forward'),
    SingleActivator(LogicalKeyboardKey.bracketLeft): _KeyIntent('backward'),
    SingleActivator(LogicalKeyboardKey.keyL, meta: true): _KeyIntent('lock'),
    SingleActivator(LogicalKeyboardKey.keyL, control: true): _KeyIntent('lock'),
    SingleActivator(LogicalKeyboardKey.escape): _KeyIntent('escape'),
    SingleActivator(LogicalKeyboardKey.arrowLeft): _KeyIntent('left'),
    SingleActivator(LogicalKeyboardKey.arrowRight): _KeyIntent('right'),
    SingleActivator(LogicalKeyboardKey.arrowUp): _KeyIntent('up'),
    SingleActivator(LogicalKeyboardKey.arrowDown): _KeyIntent('down'),
    SingleActivator(LogicalKeyboardKey.arrowLeft, shift: true): _KeyIntent('left', big: true),
    SingleActivator(LogicalKeyboardKey.arrowRight, shift: true): _KeyIntent('right', big: true),
    SingleActivator(LogicalKeyboardKey.arrowUp, shift: true): _KeyIntent('up', big: true),
    SingleActivator(LogicalKeyboardKey.arrowDown, shift: true): _KeyIntent('down', big: true),
  };

  void _onKey(_KeyIntent k) {
    if (_saving) return;
    final el = _c.selectedElement;
    final step = k.big ? 0.05 : 0.01;
    final delta = switch (k.id) {
      'left' => Offset(-step, 0),
      'right' => Offset(step, 0),
      'up' => Offset(0, -step),
      'down' => Offset(0, step),
      _ => null,
    };
    if (delta != null) {
      if (_c.edgeEditing && _c.selectedVertex != null) {
        _c.nudgeSelectedVertex(delta);
      } else if (el is ImageElement && _c.adjustingImageId == el.id) {
        _c.setImageFraming(el.id, panX: el.panX - delta.dx * 4, panY: el.panY - delta.dy * 4);
      } else if (el != null) {
        _c.updateTransform(el.id, cx: el.cx + delta.dx, cy: el.cy + delta.dy);
      }
      return;
    }
    switch (k.id) {
      case 'undo':
        if (_c.canUndo) _undo();
      case 'redo':
        if (_c.canRedo) _redo();
      case 'delete':
        if (el != null) {
          _deleteElement(el.id);
        } else if (_c.edgeEditing) {
          _c.removeSelectedVertex();
        } else if (_c.selectedSlotId != null) {
          _removeSlotPhoto(_c.selectedSlotId!);
        }
      case 'duplicate':
        if (el != null) _c.duplicateElement(el.id);
      case 'forward':
        if (el != null) _c.stepLayer(el.id, 1);
      case 'backward':
        if (el != null) _c.stepLayer(el.id, -1);
      case 'lock':
        if (el != null) _c.setLocked(el.id, !el.locked);
      case 'escape':
        if (_panel != _Panel.none) {
          _closePanel();
        } else {
          _c.clearSelection();
        }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Shortcuts(
      shortcuts: _keyMap,
      child: Actions(
        actions: {_KeyIntent: _EditorKeyAction(_onKey)},
        child: Focus(
          focusNode: _keysNode,
          autofocus: true,
          child: _buildScaffold(context),
        ),
      ),
    );
  }

  Widget _buildScaffold(BuildContext context) {
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
      body: Stack(
        children: [
      Column(
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
                      onEditSlot: _editSlot,
                      onElementTrashed: _deleteElement,
                      isOverTrash: _isOverTrash,
                    ),
                  ),
                ),
              ),
            ),
          ),
          // Contextual actions for what is selected — only while no tool
          // panel is open, so the canvas keeps its room.
          if (_panel == _Panel.none) ...[
            _ContextBar(
              controller: _c,
              onEditText: (e) {
                setState(() { _editingTextId = e.id; _panel = _Panel.text; });
              },
              onShape: (e) => _openPhotoLayer(e.id),
              onDelete: (e) => _deleteElement(e.id),
            ),
            _SlotBar(
              controller: _c,
              onReplace: _openReplace,
              onEdit: _openStyle,
              onFilter: (_) => _openPanel(_Panel.filter),
              onVideo: _pickVideo,
              onRemove: _removeSlotPhoto,
            ),
          ],
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
          // Drag-to-delete: an obvious target slides up while something is
          // being dragged; releasing over it deletes (with Undo).
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.only(bottom: Space.md),
                child: Center(
                  child: _TrashTarget(
                    key: _trashKey,
                    controller: _c,
                    onSlotDropped: _removeSlotPhoto,
                  ),
                ),
              ),
            ),
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
    if (p == _addPhotoLayer) { _addPhotoLayerFlow(); return; }
    if (p == _Panel.text) { _openText(); return; }
    if (p == _Panel.draw) { _openDraw(); return; }
    _openPanel(p);
  }

  Widget _panelHost(BuildContext context) {
    final h = MediaQuery.of(context).size.height;
    final (title, body, height) = switch (_panel) {
      _Panel.layout => (context.l10n.t('panelLayout'), LayoutPanel(c: _c, onShapeEdges: _openEdges), 340.0),
      _Panel.edges => (context.l10n.t('edgeShapeTitle'), EdgePanel(c: _c, onDone: _closePanel), 330.0),
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
      _Panel.photoLayer => (
          context.l10n.t('panelPhotoLayer'),
          PhotoLayerPanel(
            c: _c,
            elementId: _photoLayerId ?? '',
            onCrop: () => setState(() {
              _cleanupPanel();
              _cropElementId = _photoLayerId;
              _panel = _Panel.crop;
            }),
            onChoosePhoto: () => _chooseLayerPhoto(_photoLayerId ?? ''),
          ),
          (h * 0.46).clamp(340, 460),
        ),
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
    // Never let a panel take more than ~42% of the screen: on a small phone the
    // collage must stay visible while it is being styled. Panels scroll inside.
    final maxBody = (h * 0.42 - 46).clamp(170.0, 400.0);
    final bodyH = math.min(isStyle ? 300.0 : height, maxBody);
    return Container(
      height: bodyH + 46,
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
                  const SizedBox(width: Space.md),
                // Style: its three sections are the header itself — compact
                // tabs instead of a title plus a second row of segments.
                Expanded(
                  child: isStyle
                      ? _StyleTabs(
                          active: _panel,
                          onSelect: _openPanel,
                        )
                      : Text(title, style: context.text.titleMd, maxLines: 1, overflow: TextOverflow.ellipsis),
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
          Expanded(child: body),
        ],
      ),
    );
  }
}

/// The Style tool's sections (Borders · Background · Filters) as one row of
/// compact tabs in the panel header.
class _StyleTabs extends StatelessWidget {
  const _StyleTabs({required this.active, required this.onSelect});
  final _Panel active;
  final void Function(_Panel) onSelect;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final tabs = <(_Panel, IconData, String)>[
      (_Panel.borders, Icons.border_outer_rounded, l.t('toolBorders')),
      (_Panel.background, Icons.gradient_rounded, l.t('toolBackground')),
      (_Panel.filter, Icons.tune_rounded, l.t('toolFilter')),
    ];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final (panel, icon, label) in tabs)
            Padding(
              padding: const EdgeInsets.only(right: Space.xs),
              child: Semantics(
                selected: panel == active,
                button: true,
                child: InkWell(
                  onTap: () => onSelect(panel),
                  borderRadius: BorderRadius.circular(Radii.pill),
                  child: AnimatedContainer(
                    duration: Motion.fast,
                    constraints: const BoxConstraints(minHeight: 36),
                    padding: const EdgeInsets.symmetric(horizontal: Space.md),
                    decoration: BoxDecoration(
                      color: panel == active ? context.colors.amberTint : null,
                      borderRadius: BorderRadius.circular(Radii.pill),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(icon, size: 18, color: panel == active ? context.colors.amber : context.colors.textMid),
                        const SizedBox(width: 6),
                        Text(
                          label,
                          style: context.text.labelMd.copyWith(
                            color: panel == active ? context.colors.amber : context.colors.textMid,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
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
      (_addPhotoLayer, Icons.add_photo_alternate_outlined, l.t('toolPhotoLayer')),
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
  const _ContextBar({
    required this.controller,
    required this.onEditText,
    required this.onShape,
    required this.onDelete,
  });
  final EditorController controller;
  final void Function(TextElement e) onEditText;
  final void Function(ImageElement e) onShape;
  final void Function(CanvasElement e) onDelete;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final el = controller.selectedElement;
        if (el == null || controller.draggingElementId != null) return const SizedBox.shrink();
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
                Expanded(child: _CtxBtn(icon: Icons.interests_outlined, label: context.l10n.t('ctxShape'), onTap: () => onShape(el))),
              Expanded(child: _CtxBtn(icon: Icons.copy_rounded, label: context.l10n.t('ctxDuplicate'), onTap: () => controller.duplicateElement(el.id))),
              Expanded(child: _CtxBtn(icon: Icons.more_horiz_rounded, label: context.l10n.t('ctxMore'), onTap: () => _more(context, el))),
              Expanded(
                child: _CtxBtn(
                  icon: Icons.delete_outline_rounded,
                  label: context.l10n.t('ctxDelete'),
                  color: context.colors.danger,
                  onTap: () => onDelete(el),
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
      (Icons.arrow_upward_rounded, 0, l.t('ctxForwardOne'), () => c.stepLayer(el.id, 1)),
      (Icons.arrow_downward_rounded, 0, l.t('ctxBackOne'), () => c.stepLayer(el.id, -1)),
      (Icons.flip_to_back_rounded, 0, l.t('ctxBack'), () => c.sendBackward(el.id)),
      (el.locked ? Icons.lock_open_rounded : Icons.lock_rounded, 0, l.t(el.locked ? 'layerUnlock' : 'layerLock'), () => c.setLocked(el.id, !el.locked)),
      (Icons.visibility_off_outlined, 0, l.t('layerHide'), () => c.setHidden(el.id, true)),
      (Icons.restart_alt_rounded, 0, l.t('ctxStraighten'), () => c.updateTransform(el.id, rotation: 0)),
    ];
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheet) => SafeArea(
        child: SingleChildScrollView(
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

// ---------------------------------------------------------------------------
// Selected photo: what can be done with it
// ---------------------------------------------------------------------------

/// The contextual bar for a selected photo cell. It says what a drag does
/// right now (move the photo inside its frame) and lists everything that can
/// be done with this photo — replacing the tiny chips that used to float on
/// the photo itself.
class _SlotBar extends StatelessWidget {
  const _SlotBar({
    required this.controller,
    required this.onReplace,
    required this.onEdit,
    required this.onFilter,
    required this.onVideo,
    required this.onRemove,
  });
  final EditorController controller;
  final void Function(String slotId) onReplace;
  final void Function(String slotId) onEdit;
  final void Function(String slotId) onFilter;
  final void Function(String slotId) onVideo;
  final void Function(String slotId) onRemove;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final c = controller;
        final id = c.selectedSlotId;
        if (id == null || c.edgeEditing || c.replaceSlotId != null || c.dragSourceSlot != null) {
          return const SizedBox.shrink();
        }
        final l = context.l10n;
        final fill = c.fillFor(id);
        final swapping = c.swapSource != null;
        final hint = swapping
            ? l.t('swapHint')
            : fill != null
                ? l.t('framingHint')
                : l.t('emptySlotHint');
        return Container(
          decoration: BoxDecoration(
            color: context.colors.surface,
            border: Border(top: BorderSide(color: context.colors.line)),
          ),
          padding: const EdgeInsets.fromLTRB(Space.sm, Space.xs, Space.sm, 2),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Semantics(
                liveRegion: true,
                child: Row(
                  children: [
                    const SizedBox(width: Space.sm),
                    Icon(swapping ? Icons.swap_horiz_rounded : Icons.pan_tool_alt_outlined,
                        size: 16, color: swapping ? context.colors.amber : context.colors.textLo),
                    const SizedBox(width: Space.sm),
                    Expanded(
                      child: Text(
                        hint,
                        style: context.text.caption.copyWith(color: context.colors.textMid),
                      ),
                    ),
                    if (swapping)
                      TextButton(onPressed: c.cancelSwapMode, child: Text(l.t('cancel'))),
                  ],
                ),
              ),
              Row(
                children: fill == null
                    ? [
                        Expanded(child: _CtxBtn(icon: Icons.photo_library_outlined, label: l.t('chipChoose'), onTap: () => onReplace(id))),
                        Expanded(child: _CtxBtn(icon: Icons.videocam_outlined, label: l.t('chipVideo'), onTap: () => onVideo(id))),
                      ]
                    : [
                        Expanded(child: _CtxBtn(icon: Icons.photo_library_outlined, label: l.t('chipReplace'), onTap: () => onReplace(id))),
                        Expanded(child: _CtxBtn(icon: Icons.edit_rounded, label: l.t('ctxEdit'), onTap: () => onEdit(id))),
                        Expanded(child: _CtxBtn(icon: Icons.tune_rounded, label: l.t('toolFilter'), onTap: () => onFilter(id))),
                        Expanded(child: _CtxBtn(icon: Icons.more_horiz_rounded, label: l.t('ctxMore'), onTap: () => _more(context, id))),
                        Expanded(
                          child: _CtxBtn(
                            icon: Icons.delete_outline_rounded,
                            label: l.t('ctxRemove'),
                            color: context.colors.danger,
                            onTap: () => onRemove(id),
                          ),
                        ),
                      ],
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _more(BuildContext context, String id) async {
    final l = context.l10n;
    final c = controller;
    final items = <(IconData, int, String, VoidCallback)>[
      (Icons.swap_horiz_rounded, 0, l.t('swapWithAnother'), () => c.startSwapMode(id)),
      (Icons.flip_rounded, 0, l.t('chipFlipH'), () => c.flipSlot(id, horizontal: true)),
      (Icons.flip_rounded, 1, l.t('chipFlipV'), () => c.flipSlot(id, vertical: true)),
      (Icons.rotate_90_degrees_cw_rounded, 0, l.t('chipRotate'), () => c.rotateSlotQuarter(id)),
      (Icons.center_focus_strong_outlined, 0, l.t('resetFraming'), () => c.resetSlotTransform(id)),
      (Icons.videocam_outlined, 0, l.t('chipVideo'), () => onVideo(id)),
    ];
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheet) => SafeArea(
        child: SingleChildScrollView(
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
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Drag-to-delete target
// ---------------------------------------------------------------------------

/// Slides up from the bottom while a photo or an element is being dragged.
/// Elements report the finger position themselves (see the canvas); slot
/// photos are [Draggable]s and land here as a [DragTarget]. It grows and
/// turns red under the finger, so a release that deletes is never a surprise.
class _TrashTarget extends StatelessWidget {
  const _TrashTarget({super.key, required this.controller, required this.onSlotDropped});
  final EditorController controller;
  final void Function(String slotId) onSlotDropped;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final c = controller;
        final show = c.showTrash;
        final over = show && c.overTrash;
        final l = context.l10n;
        return DragTarget<String>(
          onWillAcceptWithDetails: (_) => c.dragSourceSlot != null,
          onMove: (_) {
            if (!c.overTrash) {
              HapticFeedback.selectionClick();
              c.setOverTrash(true);
            }
          },
          onLeave: (_) => c.setOverTrash(false),
          onAcceptWithDetails: (d) {
            c.endSlotDrag();
            onSlotDropped(d.data);
          },
          builder: (context, _, __) => IgnorePointer(
            ignoring: !show,
            child: AnimatedSlide(
              offset: show ? Offset.zero : const Offset(0, 1.6),
              duration: Motion.base,
              curve: Motion.emphasized,
              child: AnimatedOpacity(
                opacity: show ? 1 : 0,
                duration: Motion.fast,
                child: AnimatedScale(
                  scale: over ? 1.12 : 1,
                  duration: Motion.fast,
                  child: Semantics(
                    label: l.t(over ? 'releaseToDelete' : 'dragHereToDelete'),
                    child: AnimatedContainer(
                      duration: Motion.fast,
                      height: 64,
                      padding: const EdgeInsets.symmetric(horizontal: Space.xl),
                      decoration: BoxDecoration(
                        color: over ? context.colors.danger : context.colors.surfaceHigh,
                        borderRadius: BorderRadius.circular(Radii.pill),
                        border: Border.all(color: context.colors.danger, width: 2),
                        boxShadow: Shadows.e3,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            over ? Icons.delete_forever_rounded : Icons.delete_outline_rounded,
                            color: over ? context.colors.onDanger : context.colors.danger,
                            size: 28,
                          ),
                          const SizedBox(width: Space.sm),
                          Text(
                            l.t(over ? 'releaseToDelete' : 'dragHereToDelete'),
                            style: context.text.labelLg.copyWith(
                              color: over ? context.colors.onDanger : context.colors.textHi,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// A keyboard command of the editor (see `_keyMap`).
class _KeyIntent extends Intent {
  const _KeyIntent(this.id, {this.big = false});
  final String id;

  /// Shift held: nudge in bigger steps.
  final bool big;
}

/// Runs editor key commands — but stands aside while a text field has focus,
/// so Backspace deletes a letter, not the selected layer.
class _EditorKeyAction extends Action<_KeyIntent> {
  _EditorKeyAction(this.onKey);
  final void Function(_KeyIntent) onKey;

  @override
  bool isEnabled(_KeyIntent intent) {
    final ctx = FocusManager.instance.primaryFocus?.context;
    if (ctx == null) return true;
    return ctx.widget is! EditableText && ctx.findAncestorWidgetOfExactType<EditableText>() == null;
  }

  @override
  Object? invoke(_KeyIntent intent) {
    onKey(intent);
    return null;
  }
}
