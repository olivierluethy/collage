import 'dart:ui' show Color;

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../../models/canvas_element.dart';
import '../../models/collage_project.dart';
import '../../models/layout_template.dart';

/// Holds the collage being edited plus selection state, and exposes every
/// mutation the editor UI performs. A plain [ChangeNotifier] so the canvas and
/// tool sheets rebuild on change without a global store.
class EditorController extends ChangeNotifier {
  EditorController({required this.project, required List<String> pool})
      : _pool = List.of(pool) {
    if (project.fills.isEmpty && project.layout.slots.isNotEmpty) autofill();
  }

  final CollageProject project;

  /// The photos the user picked, available to fill slots / add as elements.
  final List<String> _pool;
  List<String> get pool => List.unmodifiable(_pool);

  final _uuid = const Uuid();

  String? selectedElementId;
  String? selectedSlotId;

  bool get hasSelection => selectedElementId != null || selectedSlotId != null;

  void _touch() {
    project.updatedAt = DateTime.now().millisecondsSinceEpoch;
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
    project.fills[slotId] = SlotFill(assetId: assetId);
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
