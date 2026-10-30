import 'dart:convert';
import 'dart:ui' show Color, Offset, Size;

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../../models/canvas_element.dart';
import '../../models/collage_project.dart';
import '../../models/layout_template.dart';
import '../../models/photo_filter.dart';

/// Holds the collage being edited plus selection state, and exposes every
/// mutation the editor UI performs. A plain [ChangeNotifier] so the canvas and
/// tool sheets rebuild on change without a global store.
class EditorController extends ChangeNotifier {
  EditorController({required this.project, required List<String> pool})
      : _pool = List.of(pool) {
    if (project.fills.isEmpty && project.layout.slots.isNotEmpty) autofill();
    // The opening state is the floor of the history, not an undoable step.
    _committed = _snapshot();
    _latest = _committed;
    _lastTouch = null;
  }

  // --- undo / redo -----------------------------------------------------------
  /// Snapshot history. Every mutation goes through [_touch], which records the
  /// resulting state. A burst of updates (a drag, a pinch, a slider) becomes
  /// ONE undo step: it is committed when the next edit arrives after a pause
  /// of at least [_settle], or when the user undoes/redoes. No timer, so
  /// nothing is left pending when the editor closes.
  static const _settle = Duration(milliseconds: 350);
  static const _maxHistory = 60;

  final List<String> _undo = [];
  final List<String> _redo = [];
  // Both start empty: the constructor's autofill already records, and the
  // real opening state is set once construction is done.
  String _committed = ''; // last state on the history stack
  String _latest = ''; // state after the most recent edit
  DateTime? _lastTouch;

  bool get canUndo => _undo.isNotEmpty || _hasPendingChange;
  bool get canRedo => _redo.isNotEmpty && !_hasPendingChange;

  bool get _hasPendingChange => _latest != _committed;

  /// The editable state as JSON, without bookkeeping fields that change on
  /// every touch (so an unchanged collage compares equal).
  String _snapshot() {
    final j = project.toJson()
      ..remove('updatedAt')
      ..remove('thumbnailPath');
    return jsonEncode(j);
  }

  /// Called after every mutation: closes the previous burst if this edit
  /// comes after a pause, then remembers the new state.
  void _record() {
    final now = DateTime.now();
    final last = _lastTouch;
    if (last == null || now.difference(last) >= _settle) _commit();
    _lastTouch = now;
    _latest = _snapshot();
  }

  /// Push the pending burst (if it changed anything) onto the history.
  void _commit() {
    if (_latest == _committed) return;
    _undo.add(_committed);
    if (_undo.length > _maxHistory) _undo.removeAt(0);
    _redo.clear();
    _committed = _latest;
  }

  void undo() {
    _commit();
    if (_undo.isEmpty) return;
    _redo.add(_committed);
    _restore(_undo.removeLast());
  }

  void redo() {
    _commit();
    if (_redo.isEmpty) return;
    _undo.add(_committed);
    _restore(_redo.removeLast());
  }

  void _restore(String snapshot) {
    _committed = snapshot;
    _latest = snapshot;
    _lastTouch = null;
    final p = CollageProject.fromJson(jsonDecode(snapshot) as Map<String, dynamic>);
    project
      ..title = p.title
      ..ratioLabel = p.ratioLabel
      ..layout = p.layout
      ..fills = p.fills
      ..elements = p.elements
      ..border = p.border
      ..background = p.background
      ..updatedAt = DateTime.now().millisecondsSinceEpoch;
    // Drop transient state that may point at things the snapshot lacks.
    swapSource = null;
    replaceSlotId = null;
    replaceCandidate = null;
    guideX = null;
    guideY = null;
    if (selectedElementId != null && !project.elements.any((e) => e.id == selectedElementId)) {
      selectedElementId = null;
    }
    if (selectedSlotId != null && !project.layout.slots.any((s) => s.id == selectedSlotId)) {
      selectedSlotId = null;
    }
    notifyListeners();
  }

  // --- alignment guides (transient) ------------------------------------------
  /// Canvas fractions where a dragged element is currently snapped, drawn as
  /// guide lines by the canvas. Null when not snapped on that axis.
  double? guideX;
  double? guideY;

  /// Snap distance, as a fraction of the canvas side.
  static const snapThreshold = 0.015;

  /// Snap a free element's centre to the canvas centre/thirds or to another
  /// element's centre, and publish the matching guides.
  (double, double) snapPosition(String id, double cx, double cy) {
    final xs = <double>[0.5, 1 / 3, 2 / 3];
    final ys = <double>[0.5, 1 / 3, 2 / 3];
    for (final e in project.elements) {
      if (e.id == id) continue;
      xs.add(e.cx);
      ys.add(e.cy);
    }
    double? best(double v, List<double> targets) {
      double? hit;
      var bestD = snapThreshold;
      for (final t in targets) {
        final d = (v - t).abs();
        if (d <= bestD) {
          bestD = d;
          hit = t;
        }
      }
      return hit;
    }

    final sx = best(cx, xs);
    final sy = best(cy, ys);
    if (sx != guideX || sy != guideY) {
      guideX = sx;
      guideY = sy;
    }
    return (sx ?? cx, sy ?? cy);
  }

  void clearGuides() {
    if (guideX == null && guideY == null) return;
    guideX = null;
    guideY = null;
    notifyListeners();
  }

  final CollageProject project;

  /// The photos the user picked, available to fill slots / add as elements.
  final List<String> _pool;
  List<String> get pool => List.unmodifiable(_pool);

  final _uuid = const Uuid();

  String? selectedElementId;
  String? selectedSlotId;

  // --- transient preview state (never persisted) ---------------------------
  /// Slot currently being dragged, and the slot it is hovering over, so both
  /// can show the pending swap live before the finger is lifted.
  String? dragSourceSlot;
  String? dragOverSlot;

  /// Tap-to-swap mode: the first slot the user chose; the next slot tapped
  /// swaps with it.
  String? swapSource;

  /// Live replace preview: the slot being replaced and the candidate photo the
  /// user is previewing before committing.
  String? replaceSlotId;
  String? replaceCandidate;

  bool get hasSelection => selectedElementId != null || selectedSlotId != null;

  // --- drag-to-swap preview ------------------------------------------------
  void startSlotDrag(String id) {
    dragSourceSlot = id;
    notifyListeners();
  }

  void updateSlotDragOver(String? id) {
    if (dragOverSlot == id) return;
    dragOverSlot = id;
    notifyListeners();
  }

  void endSlotDrag() {
    dragSourceSlot = null;
    dragOverSlot = null;
    notifyListeners();
  }

  // --- tap-to-swap mode ----------------------------------------------------
  void startSwapMode(String id) {
    swapSource = id;
    selectSlot(id);
  }

  void cancelSwapMode() {
    swapSource = null;
    notifyListeners();
  }

  /// Returns true if the tap completed a swap.
  bool completeSwapIfActive(String target) {
    if (swapSource == null) return false;
    final src = swapSource!;
    swapSource = null;
    if (src != target) swapSlots(src, target);
    return true;
  }

  // --- live replace --------------------------------------------------------
  void startReplace(String slotId) {
    replaceSlotId = slotId;
    replaceCandidate = null;
    selectSlot(slotId);
  }

  void previewReplace(String assetId) {
    replaceCandidate = assetId;
    notifyListeners();
  }

  void commitReplace() {
    if (replaceSlotId != null && replaceCandidate != null) {
      addToPool(replaceCandidate!);
      assignSlot(replaceSlotId!, replaceCandidate!);
    }
    replaceSlotId = null;
    replaceCandidate = null;
    notifyListeners();
  }

  void cancelReplace() {
    replaceSlotId = null;
    replaceCandidate = null;
    notifyListeners();
  }

  /// The photo (with its pan/zoom) a slot should render right now, accounting
  /// for any live drag-swap or replace preview.
  SlotFill? effectiveFill(String slotId) {
    if (slotId == replaceSlotId && replaceCandidate != null) {
      return SlotFill(assetId: replaceCandidate!);
    }
    if (dragSourceSlot != null && dragOverSlot != null && dragSourceSlot != dragOverSlot) {
      if (slotId == dragOverSlot) return fillFor(dragSourceSlot!);
      if (slotId == dragSourceSlot) return fillFor(dragOverSlot!);
    }
    return fillFor(slotId);
  }

  void _touch() {
    project.updatedAt = DateTime.now().millisecondsSinceEpoch;
    _record();
    notifyListeners();
  }

  // ---- selection ----------------------------------------------------------
  void selectElement(String? id) {
    selectedElementId = id;
    selectedSlotId = null;
    notifyListeners();
  }

  void selectSlot(String? id) {
    selectedSlotId = id;
    selectedElementId = null;
    notifyListeners();
  }

  void clearSelection() {
    selectedElementId = null;
    selectedSlotId = null;
    swapSource = null;
    if (replaceSlotId != null) cancelReplace();
    notifyListeners();
  }

  // ---- slots --------------------------------------------------------------
  /// Fill slots from the pool in order (autofill default). Keeps existing
  /// assignments where a slot already has one.
  void autofill() {
    final used = project.fills.values.map((f) => f.assetId).toSet();
    final available = _pool.where((id) => !used.contains(id)).toList();
    var i = 0;
    for (final slot in project.layout.slots) {
      if (project.fills.containsKey(slot.id)) continue;
      if (i >= available.length) break;
      project.fills[slot.id] = SlotFill(assetId: available[i]);
      i++;
    }
    _touch();
  }

  SlotFill? fillFor(String slotId) => project.fills[slotId];

  void assignSlot(String slotId, String assetId) {
    // Keep the cell's existing filter when its photo is replaced, so a styled
    // slot keeps its look.
    final prev = project.fills[slotId];
    project.fills[slotId] =
        SlotFill(assetId: assetId, filter: prev?.filter.clone());
    _touch();
  }

  // ---- per-cell filters ---------------------------------------------------
  /// Mutate the filter on a single slot (the "This photo" scope).
  void updateSlotFilter(String slotId, void Function(PhotoFilter f) fn) {
    final f = project.fills[slotId];
    if (f == null) return;
    fn(f.filter);
    _touch();
  }

  /// Apply one filter to every filled cell (the "Whole collage" scope). Each
  /// cell gets its own clone, so any cell remains individually re-editable
  /// afterwards.
  void applyFilterToAll(PhotoFilter template) {
    for (final f in project.fills.values) {
      final c = template.clone();
      f.filter
        ..preset = c.preset
        ..brightness = c.brightness
        ..contrast = c.contrast
        ..saturation = c.saturation
        ..warmth = c.warmth
        ..vignette = c.vignette
        ..sharpen = c.sharpen;
    }
    _touch();
  }

  // ---- per-cell frame & shadow -----------------------------------------------
  /// Change one slot photo's own look (frame width/colour, shadow).
  void updateSlotStyle(String slotId, void Function(SlotFill f) fn) {
    final f = project.fills[slotId];
    if (f == null) return;
    fn(f);
    _touch();
  }

  void clearSlot(String slotId) {
    project.fills.remove(slotId);
    _touch();
  }

  /// Swap the photos (and their in-slot pan/zoom) between two slots — the core
  /// "you decide which photo goes where" gesture.
  void swapSlots(String a, String b) {
    if (a == b) return;
    final fa = project.fills[a];
    final fb = project.fills[b];
    if (fb == null) {
      project.fills.remove(a);
    } else {
      project.fills[a] = fb;
    }
    if (fa == null) {
      project.fills.remove(b);
    } else {
      project.fills[b] = fa;
    }
    _touch();
  }

  void setSlotTransform(String slotId, {double? offX, double? offY, double? zoom}) {
    final f = project.fills[slotId];
    if (f == null) return;
    if (offX != null) f.offsetX = offX.clamp(-1, 1);
    if (offY != null) f.offsetY = offY.clamp(-1, 1);
    if (zoom != null) f.zoom = zoom.clamp(1, 4);
    _touch();
  }

  /// Recentre a slot's photo: default pan and no zoom. The escape hatch for the
  /// "I over-dragged and want the whole photo back" case (double-tap a cell).
  void resetSlotTransform(String slotId) {
    final f = project.fills[slotId];
    if (f == null) return;
    if (f.offsetX == 0 && f.offsetY == 0 && f.zoom == 1 && f.rotation == 0) return;
    f.offsetX = 0;
    f.offsetY = 0;
    f.zoom = 1;
    f.rotation = 0;
    _touch();
  }

  /// Tilt a slot photo by [radians] (kept in -π..π). The canvas enlarges the
  /// photo so the cell stays covered at any angle.
  void setSlotRotation(String slotId, double radians) {
    final f = project.fills[slotId];
    if (f == null) return;
    const pi = 3.141592653589793;
    var r = radians % (2 * pi);
    if (r > pi) r -= 2 * pi;
    f.rotation = r;
    _touch();
  }

  /// Turn a slot photo by a quarter turn clockwise.
  void rotateSlotQuarter(String slotId) {
    final f = project.fills[slotId];
    if (f == null) return;
    setSlotRotation(slotId, f.rotation + 3.141592653589793 / 2);
  }

  // ---- crop (free photos) ---------------------------------------------------
  /// Set the crop insets of a free photo; each edge is clamped so at least
  /// 10% of the photo always remains visible on both axes.
  void setCrop(String id, {double? l, double? t, double? r, double? b}) {
    for (final e in project.elements) {
      if (e.id != id || e is! ImageElement) continue;
      const m = ImageElement.maxCrop;
      if (l != null) e.cropL = l.clamp(0, m);
      if (t != null) e.cropT = t.clamp(0, m);
      if (r != null) e.cropR = r.clamp(0, m);
      if (b != null) e.cropB = b.clamp(0, m);
      _touch();
      return;
    }
  }

  void resetCrop(String id) => setCrop(id, l: 0, t: 0, r: 0, b: 0);

  /// Mirror a slot photo across its horizontal and/or vertical axis. Each flag
  /// toggles independently, so the two buttons can be combined (or reversed).
  void flipSlot(String slotId, {bool horizontal = false, bool vertical = false}) {
    final f = project.fills[slotId];
    if (f == null || (!horizontal && !vertical)) return;
    if (horizontal) f.flipX = !f.flipX;
    if (vertical) f.flipY = !f.flipY;
    _touch();
  }

  /// Mirror a free-floating photo element ([ImageElement]); non-photo elements
  /// are unaffected.
  void flipElement(String id, {bool horizontal = false, bool vertical = false}) {
    for (final e in project.elements) {
      if (e.id != id) continue;
      if (e is ImageElement && (horizontal || vertical)) {
        if (horizontal) e.flipX = !e.flipX;
        if (vertical) e.flipY = !e.flipY;
        _touch();
      }
      return;
    }
  }

  /// Assets from the pool not currently placed in any slot.
  List<String> get unusedPoolAssets {
    final used = project.fills.values.map((f) => f.assetId).toSet();
    return _pool.where((id) => !used.contains(id)).toList();
  }

  void addToPool(String assetId) {
    if (!_pool.contains(assetId)) _pool.add(assetId);
    notifyListeners();
  }

  // ---- layout / ratio -----------------------------------------------------
  void setLayout(LayoutTemplate template) {
    // Preserve assignments by slot order where possible.
    final oldFills = project.layout.slots
        .map((s) => project.fills[s.id])
        .toList();
    project.layout = template;
    project.fills = {};
    for (var i = 0; i < template.slots.length && i < oldFills.length; i++) {
      final f = oldFills[i];
      if (f != null) project.fills[template.slots[i].id] = f;
    }
    autofill();
  }

  void setRatioLabel(String label) {
    project.ratioLabel = label;
    _touch();
  }

  // ---- elements -----------------------------------------------------------
  int get _nextZ =>
      project.elements.isEmpty ? 0 : project.elements.map((e) => e.z).reduce((a, b) => a > b ? a : b) + 1;

  CanvasElement? get selectedElement {
    if (selectedElementId == null) return null;
    for (final e in project.elements) {
      if (e.id == selectedElementId) return e;
    }
    return null;
  }

  void _add(CanvasElement e) {
    project.elements.add(e);
    selectElement(e.id);
    _touch();
  }

  void addSticker(String assetPath) => _add(StickerElement(
        id: _uuid.v4(),
        cx: 0.5,
        cy: 0.5,
        assetPath: assetPath,
        z: _nextZ,
      ));

  void addShape(String kind, {required int fill}) => _add(ShapeElement(
        id: _uuid.v4(),
        cx: 0.5,
        cy: 0.5,
        shapeKind: kind,
        fill: Color(fill),
        z: _nextZ,
      ));

  void addEmoji(String emoji) => _add(EmojiElement(
        id: _uuid.v4(),
        cx: 0.5,
        cy: 0.5,
        emoji: emoji,
        z: _nextZ,
      ));

  void addGif(String url, double aspect) => _add(GifElement(
        id: _uuid.v4(),
        cx: 0.5,
        cy: 0.5,
        url: url,
        gifAspect: aspect,
        z: _nextZ,
      ));

  void addImageElement(String assetId, double aspect) => _add(ImageElement(
        id: _uuid.v4(),
        cx: 0.5,
        cy: 0.5,
        assetId: assetId,
        imgAspect: aspect,
        z: _nextZ,
      ));

  TextElement addText(String text, {required int color}) {
    final el = TextElement(
      id: _uuid.v4(),
      cx: 0.5,
      cy: 0.5,
      text: text,
      color: Color(color),
      z: _nextZ,
    );
    _add(el);
    return el;
  }

  void updateTransform(String id, {double? cx, double? cy, double? scale, double? rotation}) {
    for (final e in project.elements) {
      if (e.id != id) continue;
      if (cx != null) e.cx = cx.clamp(-0.1, 1.1);
      if (cy != null) e.cy = cy.clamp(-0.1, 1.1);
      if (scale != null) e.scale = scale.clamp(0.15, 6);
      if (rotation != null) e.rotation = rotation;
      _touch();
      return;
    }
  }

  void mutateSelected(void Function(CanvasElement e) fn) {
    final e = selectedElement;
    if (e == null) return;
    fn(e);
    _touch();
  }

  void bringForward(String id) {
    for (final e in project.elements) {
      if (e.id == id) e.z = _nextZ;
    }
    _touch();
  }

  void sendBackward(String id) {
    final minZ = project.elements.map((e) => e.z).fold(0, (a, b) => a < b ? a : b);
    for (final e in project.elements) {
      if (e.id == id) e.z = minZ - 1;
    }
    _touch();
  }

  void deleteElement(String id) {
    project.elements.removeWhere((e) => e.id == id);
    if (selectedElementId == id) selectedElementId = null;
    _touch();
  }

  /// Elements front-most first — the order the layers panel lists them in.
  List<CanvasElement> get layers =>
      [...project.elements]..sort((a, b) => b.z.compareTo(a.z));

  /// Move the layer at [oldIndex] to [newIndex] (indices into [layers]; the
  /// final position, as ReorderableListView.onReorderItem reports it) and
  /// renumber z so the list order is the stacking order.
  void reorderLayer(int oldIndex, int newIndex) {
    final list = layers;
    if (oldIndex < 0 || oldIndex >= list.length) return;
    final moved = list.removeAt(oldIndex);
    list.insert(newIndex.clamp(0, list.length), moved);
    for (var i = 0; i < list.length; i++) {
      list[i].z = list.length - 1 - i;
    }
    _touch();
  }

  /// Copy an element, slightly offset, and select the copy.
  void duplicateElement(String id) {
    for (final e in project.elements) {
      if (e.id != id) continue;
      final j = e.toJson()
        ..['id'] = _uuid.v4()
        ..['cx'] = (e.cx + 0.04).clamp(-0.1, 1.1)
        ..['cy'] = (e.cy + 0.04).clamp(-0.1, 1.1)
        ..['z'] = _nextZ;
      _add(CanvasElement.fromJson(j));
      return;
    }
  }

  // ---- freehand drawing -----------------------------------------------------
  /// True while the draw tool is open: the canvas captures strokes instead of
  /// moving things.
  bool drawing = false;

  /// Strokes drawn in this session, in canvas fractions (points 0..1, width
  /// as a fraction of canvas width). Turned into one [DrawingElement] on done.
  final List<DrawStroke> draftStrokes = [];

  Color drawColor = const Color(0xFFF5EFE7);
  double drawWidth = 0.012; // fraction of canvas width

  void startDrawing() {
    drawing = true;
    draftStrokes.clear();
    clearSelection();
  }

  void setDrawStyle({Color? color, double? width}) {
    if (color != null) drawColor = color;
    if (width != null) drawWidth = width;
    notifyListeners();
  }

  void beginStroke(Offset at) {
    draftStrokes.add(DrawStroke(points: [at], color: drawColor, width: drawWidth));
    notifyListeners();
  }

  void extendStroke(Offset at) {
    if (draftStrokes.isEmpty) return;
    draftStrokes.last.points.add(at);
    notifyListeners();
  }

  void undoStroke() {
    if (draftStrokes.isEmpty) return;
    draftStrokes.removeLast();
    notifyListeners();
  }

  /// Leave draw mode, keeping the strokes as one movable element. [canvas] is
  /// the canvas size in pixels, needed to fit the drawing's own box.
  void finishDrawing(Size canvas) {
    drawing = false;
    if (draftStrokes.isEmpty || canvas.isEmpty) {
      draftStrokes.clear();
      notifyListeners();
      return;
    }
    final w = canvas.width, h = canvas.height;
    var minX = double.infinity, minY = double.infinity;
    var maxX = -double.infinity, maxY = -double.infinity;
    var pad = 0.0;
    for (final s in draftStrokes) {
      final half = s.width * w / 2;
      if (half > pad) pad = half;
      for (final p in s.points) {
        if (p.dx * w < minX) minX = p.dx * w;
        if (p.dy * h < minY) minY = p.dy * h;
        if (p.dx * w > maxX) maxX = p.dx * w;
        if (p.dy * h > maxY) maxY = p.dy * h;
      }
    }
    minX -= pad;
    minY -= pad;
    maxX += pad;
    maxY += pad;
    final bw = (maxX - minX).clamp(1.0, double.infinity);
    final bh = (maxY - minY).clamp(1.0, double.infinity);
    final strokes = [
      for (final s in draftStrokes)
        DrawStroke(
          color: s.color,
          width: s.width * w / bw,
          points: [for (final p in s.points) Offset((p.dx * w - minX) / bw, (p.dy * h - minY) / bh)],
        ),
    ];
    draftStrokes.clear();
    _add(DrawingElement(
      id: _uuid.v4(),
      cx: (minX + bw / 2) / w,
      cy: (minY + bh / 2) / h,
      strokes: strokes,
      widthFrac: bw / w,
      boxAspect: bw / bh,
      z: _nextZ,
    ));
  }

  void cancelDrawing() {
    drawing = false;
    draftStrokes.clear();
    notifyListeners();
  }

  // ---- borders / background ----------------------------------------------
  BorderSettings get border => project.border;
  BackgroundSettings get background => project.background;

  void updateBorder(void Function(BorderSettings b) fn) {
    fn(project.border);
    _touch();
  }

  void updateBackground(void Function(BackgroundSettings b) fn) {
    fn(project.background);
    _touch();
  }
}
