import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../data/fonts.dart';
import '../../data/shape_catalog.dart';
import '../../l10n/app_localizations.dart';
import '../../models/canvas_element.dart';
import '../../models/collage_project.dart';
import '../../theme/palette.dart';
import '../../theme/tokens.dart';
import '../../theme/typography.dart';
import '../../widgets/pattern_painter.dart';
import '../../widgets/photo_image.dart';
import '../../widgets/poly_clipper.dart';
import 'editor_controller.dart';

/// Renders and (optionally) edits the whole collage: background, the grid of
/// photo slots, and the freeform overlay elements. Used interactively in the
/// editor and non-interactively (wrapped in a RepaintBoundary) for export.
class CollageCanvas extends StatelessWidget {
  const CollageCanvas({
    super.key,
    required this.controller,
    this.interactive = true,
    this.onRequestReplace,
  });

  final EditorController controller;
  final bool interactive;

  /// Ask the host to open the replace picker for a slot (with live preview).
  final void Function(String slotId)? onRequestReplace;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    return AnimatedBuilder(
      animation: c,
      builder: (context, _) {
        return LayoutBuilder(
          builder: (context, constraints) {
            final size = Size(constraints.maxWidth, constraints.maxHeight);
            final elements = [...c.project.elements]..sort((a, b) => a.z.compareTo(b.z));
            return ClipRect(
              child: Stack(
                children: [
                  Positioned.fill(child: _Background(bg: c.background)),
                  // Tap-outside to deselect. Kept in the tree (inert on export)
                  // so slot/element children never shift position and get
                  // rebuilt — which would drop their decoded photo frames.
                  Positioned.fill(
                    child: GestureDetector(
                      behavior: HitTestBehavior.translucent,
                      onTap: interactive ? c.clearSelection : null,
                    ),
                  ),
                  ..._slots(c, size),
                  for (final e in elements)
                    _ElementView(
                      key: ValueKey(e.id),
                      controller: c,
                      element: e,
                      canvas: size,
                      interactive: interactive,
                    ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  List<Widget> _slots(EditorController c, Size size) {
    final slots = c.project.layout.slots;
    if (slots.isEmpty) return const [];
    final unit = size.width / 1000;
    final margin = c.border.margin * unit;
    final gap = c.border.gap * unit;
    final radius = c.border.radius * unit;
    final thickness = c.border.thickness * unit;

    final content = Rect.fromLTWH(
      margin,
      margin,
      (size.width - 2 * margin).clamp(0, size.width),
      (size.height - 2 * margin).clamp(0, size.height),
    );

    Offset toPx(Offset n) => Offset(
          content.left + n.dx * content.width,
          content.top + n.dy * content.height,
        );

    return slots.map((slot) {
      if (slot.isPolygon) {
        // Map the normalised polygon into content pixels, inset for the gap,
        // then position at its bounding box with local (box-relative) points.
        var poly = slot.points!.map(toPx).toList();
        poly = insetConvexPolygon(poly, gap / 2);
        final b = _boundsOf(poly);
        final local = [for (final p in poly) p - b.topLeft];
        return Positioned(
          left: b.left,
          top: b.top,
          width: b.width.clamp(0, size.width),
          height: b.height.clamp(0, size.height),
          child: _PolySlotView(
            controller: c,
            slotId: slot.id,
            polygon: local,
            thickness: thickness,
            borderColor: c.border.color,
            interactive: interactive,
            onRequestReplace: onRequestReplace,
          ),
        );
      }
      var r = Rect.fromLTRB(
        content.left + slot.rect.left * content.width,
        content.top + slot.rect.top * content.height,
        content.left + slot.rect.right * content.width,
        content.top + slot.rect.bottom * content.height,
      );
      r = r.deflate(gap / 2);
      return Positioned(
        left: r.left,
        top: r.top,
        width: r.width.clamp(0, size.width),
        height: r.height.clamp(0, size.height),
        child: _SlotView(
          controller: c,
          slotId: slot.id,
          radius: radius,
          thickness: thickness,
          borderColor: c.border.color,
          interactive: interactive,
          onRequestReplace: onRequestReplace,
        ),
      );
    }).toList();
  }

  static Rect _boundsOf(List<Offset> pts) {
    var minX = double.infinity, minY = double.infinity;
    var maxX = -double.infinity, maxY = -double.infinity;
    for (final p in pts) {
      if (p.dx < minX) minX = p.dx;
      if (p.dy < minY) minY = p.dy;
      if (p.dx > maxX) maxX = p.dx;
      if (p.dy > maxY) maxY = p.dy;
    }
    return Rect.fromLTRB(minX, minY, maxX, maxY);
  }
}

/// Builds a slot photo, cover-fitted, with its per-cell colour filter baked in
/// via [ColorFiltered]. Because the editor and the export use the exact same
/// widget, the saved image matches the screen. Identity filters skip the
/// wrapper entirely for performance, and a non-flipped photo skips the mirror
/// transform for the same reason.
Widget filteredPhoto(
  SlotFill fill, {
  Alignment alignment = Alignment.center,
  BoxFit fit = BoxFit.cover,
}) {
  Widget photo = PhotoImage(
    assetId: fill.assetId,
    full: true,
    fit: fit,
    alignment: alignment,
  );
  if (!fill.filter.isIdentity) {
    photo = ColorFiltered(
      colorFilter: ColorFilter.matrix(fill.filter.matrix()),
      child: photo,
    );
  }
  if (fill.isFlipped) {
    photo = Transform.scale(
      scaleX: fill.flipX ? -1 : 1,
      scaleY: fill.flipY ? -1 : 1,
      child: photo,
    );
  }
  return photo;
}

class _Background extends StatelessWidget {
  const _Background({required this.bg});
  final BackgroundSettings bg;

  @override
  Widget build(BuildContext context) {
    switch (bg.kind) {
      case BackgroundKind.solid:
        return ColoredBox(color: bg.color);
      case BackgroundKind.gradient:
        return DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [bg.gradientStart, bg.gradientEnd],
              begin: Alignment(math.cos(bg.gradientAngle), math.sin(bg.gradientAngle)),
              end: Alignment(-math.cos(bg.gradientAngle), -math.sin(bg.gradientAngle)),
            ),
          ),
        );
      case BackgroundKind.pattern:
        return PatternBackground(
          patternKey: bg.patternKey,
          color: bg.patternColor,
          background: bg.patternBg,
        );
      case BackgroundKind.image:
        if (bg.imageAssetId == null) return ColoredBox(color: context.colors.inkCanvas);
        return Stack(
          fit: StackFit.expand,
          children: [
            PhotoImage(assetId: bg.imageAssetId!, full: true, fit: BoxFit.cover),
            if (bg.imageDim > 0) ColoredBox(color: Colors.black.withValues(alpha: bg.imageDim)),
          ],
        );
    }
  }
}

/// Touch framing for one slot photo: tap selects, drag repositions, pinch
/// zooms, double-tap recentres. It only mutates [SlotFill]'s pan/zoom, which the
/// export renders through the exact same widget — so what you frame is what gets
/// saved. Live only while the slot is selected ([enabled]); the wrapper itself
/// is always in the tree so selecting a slot never rebuilds the photo.
class _SlotFrameGesture extends StatefulWidget {
  const _SlotFrameGesture({
    required this.controller,
    required this.slotId,
    required this.interactive,
    required this.enabled,
    required this.child,
  });

  final EditorController controller;
  final String slotId;
  final bool interactive;

  /// Whether pan/zoom is live: the slot is selected and holds a photo.
  final bool enabled;
  final Widget child;

  @override
  State<_SlotFrameGesture> createState() => _SlotFrameGestureState();
}

class _SlotFrameGestureState extends State<_SlotFrameGesture> {
  double _baseZoom = 1;
  double _baseOffX = 0;
  double _baseOffY = 0;
  Offset _pan = Offset.zero; // accumulated finger travel, in cell pixels

  void _onStart(ScaleStartDetails d) {
    final f = widget.controller.fillFor(widget.slotId);
    if (f == null) return;
    _baseZoom = f.zoom;
    _baseOffX = f.offsetX;
    _baseOffY = f.offsetY;
    _pan = Offset.zero;
  }

  void _onUpdate(ScaleUpdateDetails d, Size cell) {
    final c = widget.controller;
    final f = c.fillFor(widget.slotId);
    if (f == null || cell.isEmpty) return;
    _pan += d.focalPointDelta;
    final zoom = (_baseZoom * d.scale).clamp(1.0, 4.0);
    final (ow, oh) = _coverOverflow(cell, f.imgAspect);
    // Map finger travel onto the photo's available slack: dragging keeps the
    // photo under the finger, and a scale-independent 2/(zoom·overflow) keeps
    // the feel the same at any zoom. An axis with no slack simply doesn't pan.
    final offX = ow > 0.5 ? _baseOffX - 2 * _pan.dx / (zoom * ow) : _baseOffX;
    final offY = oh > 0.5 ? _baseOffY - 2 * _pan.dy / (zoom * oh) : _baseOffY;
    c.setSlotTransform(widget.slotId, offX: offX, offY: offY, zoom: zoom);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final cell = constraints.biggest;
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.interactive
              ? () {
                  if (widget.controller.completeSwapIfActive(widget.slotId)) return;
                  widget.controller.selectSlot(widget.slotId);
                }
              : null,
          onDoubleTap: widget.enabled
              ? () => widget.controller.resetSlotTransform(widget.slotId)
              : null,
          onScaleStart: widget.enabled ? _onStart : null,
          onScaleUpdate: widget.enabled ? (d) => _onUpdate(d, cell) : null,
          child: widget.child,
        );
      },
    );
  }
}

/// The un-zoomed overflow of a `BoxFit.cover` photo (of aspect [aspect]) beyond
/// [cell], per axis. One axis is always zero — the photo already fits there.
(double, double) _coverOverflow(Size cell, double aspect) {
  if (cell.isEmpty) return (0, 0);
  final a = aspect > 0 ? aspect : cell.aspectRatio;
  if (a >= cell.aspectRatio) return (cell.height * a - cell.width, 0);
  return (0, cell.width / a - cell.height);
}

class _SlotView extends StatelessWidget {
  const _SlotView({
    required this.controller,
    required this.slotId,
    required this.radius,
    required this.thickness,
    required this.borderColor,
    required this.interactive,
    this.onRequestReplace,
  });

  final EditorController controller;
  final String slotId;
  final double radius;
  final double thickness;
  final Color borderColor;
  final bool interactive;
  final void Function(String slotId)? onRequestReplace;

  @override
  Widget build(BuildContext context) {
    // effectiveFill honours any live drag-swap or replace preview.
    final fill = controller.effectiveFill(slotId);
    final realFill = controller.fillFor(slotId);
    final selected = controller.selectedSlotId == slotId;
    final swapTarget = controller.swapSource != null && controller.swapSource != slotId;
    final br = BorderRadius.circular(radius);

    Widget content = fill != null
        ? ClipRRect(
            borderRadius: br,
            child: Transform.scale(
              scale: fill.zoom,
              child: filteredPhoto(
                fill,
                alignment: Alignment(fill.offsetX, fill.offsetY),
              ),
            ),
          )
        : DottedSlot(radius: radius);

    // From here to the returned widget the ancestor chain of the photo is kept
    // identical in the editor and during export. Export merely makes the
    // handlers inert and drops the overlay siblings; it must never wrap the
    // photo in a different tree, or the photo widgets would be rebuilt, lose
    // their already-decoded frame, and come out blank in the saved PNG.
    Widget core = Container(
      decoration: BoxDecoration(
        borderRadius: br,
        border: thickness > 0 ? Border.all(color: borderColor, width: thickness) : null,
      ),
      child: content,
    );

    // Tap selects; once selected, drag repositions and pinch zooms the photo
    // (see [_SlotFrameGesture]). The wrapper is always present so selecting a
    // slot never changes the photo's ancestors.
    core = _SlotFrameGesture(
      controller: controller,
      slotId: slotId,
      interactive: interactive,
      // No framing while a replace preview is up — the visible photo is the
      // candidate, so a pan would silently edit the hidden original.
      enabled: interactive &&
          selected &&
          realFill != null &&
          controller.replaceSlotId == null,
      child: core,
    );

    // A filled slot can be dragged with an immediate (non-long-press) drag.
    if (realFill != null) {
      core = Draggable<String>(
        data: slotId,
        // While selected, dragging frames the photo instead of swapping, so the
        // swap drag is suspended (the Swap chip + tap still work).
        maxSimultaneousDrags: interactive && !selected ? null : 0,
        onDragStarted: interactive ? () => controller.startSlotDrag(slotId) : null,
        onDragEnd: interactive ? (_) => controller.endSlotDrag() : null,
        onDraggableCanceled: interactive ? (_, __) => controller.endSlotDrag() : null,
        feedback: Opacity(
          opacity: 0.9,
          child: SizedBox(
            width: 110,
            height: 110,
            child: ClipRRect(
              borderRadius: br,
              child: PhotoImage(assetId: realFill.assetId, full: true, fit: BoxFit.cover),
            ),
          ),
        ),
        childWhenDragging: Opacity(opacity: 0.25, child: core),
        child: core,
      );
    }

    // Selected / swap-target highlight — always wrapped (an empty decoration
    // when idle) so the photo below keeps its place in the widget tree.
    core = Container(
      decoration: selected || swapTarget
          ? BoxDecoration(
              borderRadius: br,
              border: Border.all(
                color: swapTarget ? context.colors.amberBright : context.colors.amber,
                width: swapTarget ? 3 : 2,
              ),
              boxShadow: selected ? Shadows.focusGlow : null,
            )
          : const BoxDecoration(),
      child: core,
    );

    // Drop target for drag-to-swap, with live preview via updateSlotDragOver.
    final dropTarget = DragTarget<String>(
      onWillAcceptWithDetails: interactive ? (d) => d.data != slotId : null,
      onMove: interactive ? (_) => controller.updateSlotDragOver(slotId) : null,
      onLeave: interactive
          ? (_) {
              if (controller.dragOverSlot == slotId) controller.updateSlotDragOver(null);
            }
          : null,
      onAcceptWithDetails: interactive
          ? (d) {
              controller.swapSlots(d.data, slotId);
              controller.endSlotDrag();
            }
          : null,
      builder: (context, candidate, rejected) => core,
    );

    // Chrome (edit badge, action chips) rides above the photo as siblings, so
    // adding or removing it never touches the photo subtree.
    final overlays = <Widget>[
      // A subtle, persistent edit badge signals every filled slot is tappable.
      if (interactive && realFill != null && !selected)
        Positioned(
          right: 4,
          bottom: 4,
          child: Container(
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.45),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.edit_rounded, size: 12, color: Colors.white),
          ),
        ),
      // Inline action chips on the selected slot.
      if (interactive && selected)
        Positioned(
          top: 4,
          left: 0,
          right: 0,
          child: Center(
            child: FittedBox(
              child: _SlotChips(
                hasPhoto: realFill != null,
                onReplace: () => onRequestReplace?.call(slotId),
                onSwap: () => controller.startSwapMode(slotId),
                onFlipH: () => controller.flipSlot(slotId, horizontal: true),
                onFlipV: () => controller.flipSlot(slotId, vertical: true),
                onClear: () => controller.clearSlot(slotId),
              ),
            ),
          ),
        ),
    ];

    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned.fill(child: dropTarget),
        ...overlays,
      ],
    );
  }
}

/// The Replace / Swap / Flip / Clear chips shown on a selected slot.
class _SlotChips extends StatelessWidget {
  const _SlotChips({
    required this.hasPhoto,
    required this.onReplace,
    required this.onSwap,
    required this.onFlipH,
    required this.onFlipV,
    required this.onClear,
  });
  final bool hasPhoto;
  final VoidCallback onReplace;
  final VoidCallback onSwap;
  final VoidCallback onFlipH;
  final VoidCallback onFlipV;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(Radii.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _Chip(
              icon: Icons.photo_library_rounded,
              label: hasPhoto ? context.l10n.t('chipReplace') : context.l10n.t('chipChoose'),
              onTap: onReplace),
          if (hasPhoto)
            _Chip(icon: Icons.swap_horiz_rounded, label: context.l10n.t('chipSwap'), onTap: onSwap),
          if (hasPhoto)
            _Chip(icon: Icons.flip_rounded, label: context.l10n.t('chipFlipH'), onTap: onFlipH),
          if (hasPhoto)
            _Chip(icon: Icons.flip_rounded, label: context.l10n.t('chipFlipV'), onTap: onFlipV, iconTurns: 1),
          if (hasPhoto)
            _Chip(icon: Icons.close_rounded, label: context.l10n.t('chipClear'), onTap: onClear, danger: true),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.icon,
    required this.label,
    required this.onTap,
    this.danger = false,
    this.iconTurns = 0,
  });
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool danger;
  final int iconTurns; // quarter-turns applied to [icon] (1 → vertical mirror)

  @override
  Widget build(BuildContext context) {
    final c = danger ? context.colors.danger : context.colors.amber;
    Widget iconWidget = Icon(icon, size: 13, color: c);
    if (iconTurns != 0) iconWidget = RotatedBox(quarterTurns: iconTurns, child: iconWidget);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 2),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          color: context.colors.surface,
          borderRadius: BorderRadius.circular(Radii.pill),
          border: Border.all(color: c),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            iconWidget,
            const SizedBox(width: 4),
            Text(label, style: context.text.labelMd.copyWith(color: c)),
          ],
        ),
      ),
    );
  }
}

/// Empty-slot placeholder: dashed frame + plus, inviting a photo.
class DottedSlot extends StatelessWidget {
  const DottedSlot({super.key, required this.radius});
  final double radius;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: context.colors.surfaceInput,
        borderRadius: BorderRadius.circular(radius),
      ),
      child: Center(
        child: Icon(Icons.add_photo_alternate_outlined, color: context.colors.textLo, size: 28),
      ),
    );
  }
}

/// A polygon (diagonal / mosaic) photo cell. Mirrors [_SlotView]'s interaction
/// but clips to an arbitrary convex polygon. The [ClipPath] gates hit-testing,
/// so taps in the bounding-box corners fall through to the cell behind — which
/// is what lets overlapping diagonal cells select the right photo. The border,
/// selection ring, edit badge and action chips are unclipped overlays anchored
/// to the polygon centroid so they stay visible on narrow triangular cells.
class _PolySlotView extends StatelessWidget {
  const _PolySlotView({
    required this.controller,
    required this.slotId,
    required this.polygon,
    required this.thickness,
    required this.borderColor,
    required this.interactive,
    this.onRequestReplace,
  });

  final EditorController controller;
  final String slotId;
  final List<Offset> polygon; // local (box-relative) pixels
  final double thickness;
  final Color borderColor;
  final bool interactive;
  final void Function(String slotId)? onRequestReplace;

  Widget _innerVisual(BuildContext context, SlotFill? fill) {
    if (fill == null) {
      return ColoredBox(
        color: context.colors.surfaceInput,
        child: Center(
          child: Icon(Icons.add_photo_alternate_outlined,
              color: context.colors.textLo, size: 26),
        ),
      );
    }
    return SizedBox.expand(
      child: Transform.scale(
        scale: fill.zoom,
        child: filteredPhoto(fill, alignment: Alignment(fill.offsetX, fill.offsetY)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final fill = controller.effectiveFill(slotId);
    final realFill = controller.fillFor(slotId);
    final selected = controller.selectedSlotId == slotId;
    final swapTarget = controller.swapSource != null && controller.swapSource != slotId;
    final centroid = polygonCentroid(polygon);
    final clipper = PolygonClipper(polygon);

    final visual = _innerVisual(context, fill);

    // The photo sits under the same DragTarget / gesture chain in both the
    // editor and export; export only makes the handlers inert (see _SlotView),
    // so the cell's photo is never rebuilt and never loses its decoded frame.
    final core = ClipPath(
      clipper: clipper,
      child: DragTarget<String>(
        onWillAcceptWithDetails: interactive ? (d) => d.data != slotId : null,
        onMove: interactive ? (_) => controller.updateSlotDragOver(slotId) : null,
        onLeave: interactive
            ? (_) {
                if (controller.dragOverSlot == slotId) controller.updateSlotDragOver(null);
              }
            : null,
        onAcceptWithDetails: interactive
            ? (d) {
                controller.swapSlots(d.data, slotId);
                controller.endSlotDrag();
              }
            : null,
        builder: (context, candidate, rejected) {
          final child = _SlotFrameGesture(
            controller: controller,
            slotId: slotId,
            interactive: interactive,
            // No framing while a replace preview is up (see _SlotView).
            enabled: interactive &&
                selected &&
                realFill != null &&
                controller.replaceSlotId == null,
            child: visual,
          );
          if (realFill == null) return child;
          return Draggable<String>(
            data: slotId,
            // Selected cell: drag frames the photo, so suspend the swap drag.
            maxSimultaneousDrags: interactive && !selected ? null : 0,
            onDragStarted: interactive ? () => controller.startSlotDrag(slotId) : null,
            onDragEnd: interactive ? (_) => controller.endSlotDrag() : null,
            onDraggableCanceled: interactive ? (_, __) => controller.endSlotDrag() : null,
            feedback: Opacity(
              opacity: 0.9,
              child: SizedBox(
                width: 110,
                height: 110,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: PhotoImage(assetId: realFill.assetId, full: true, fit: BoxFit.cover),
                ),
              ),
            ),
            childWhenDragging: Opacity(opacity: 0.25, child: visual),
            child: child,
          );
        },
      ),
    );

    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned.fill(child: core),
        // Border stroke along the polygon edges.
        if (thickness > 0)
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(
                painter: PolygonBorderPainter(
                    points: polygon, color: borderColor, strokeWidth: thickness),
              ),
            ),
          ),
        // Selection / swap-target highlight (amber edge).
        if (interactive && (selected || swapTarget))
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(
                painter: PolygonBorderPainter(
                  points: polygon,
                  color: swapTarget ? context.colors.amberBright : context.colors.amber,
                  strokeWidth: swapTarget ? 3 : 2.5,
                ),
              ),
            ),
          ),
        // Persistent edit badge on a filled, unselected cell.
        if (interactive && realFill != null && !selected)
          Positioned(
            left: centroid.dx,
            top: centroid.dy,
            child: FractionalTranslation(
              translation: const Offset(-0.5, -0.5),
              child: Container(
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.45),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.edit_rounded, size: 12, color: Colors.white),
              ),
            ),
          ),
        // Inline action chips on the selected cell.
        if (interactive && selected)
          Positioned(
            left: centroid.dx,
            top: centroid.dy,
            child: FractionalTranslation(
              translation: const Offset(-0.5, -0.5),
              child: FittedBox(
                child: _SlotChips(
                  hasPhoto: realFill != null,
                  onReplace: () => onRequestReplace?.call(slotId),
                  onSwap: () => controller.startSwapMode(slotId),
                  onFlipH: () => controller.flipSlot(slotId, horizontal: true),
                  onFlipV: () => controller.flipSlot(slotId, vertical: true),
                  onClear: () => controller.clearSlot(slotId),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Overlay elements
// ---------------------------------------------------------------------------

class _ElementView extends StatefulWidget {
  const _ElementView({
    super.key,
    required this.controller,
    required this.element,
    required this.canvas,
    required this.interactive,
  });

  final EditorController controller;
  final CanvasElement element;
  final Size canvas;
  final bool interactive;

  @override
  State<_ElementView> createState() => _ElementViewState();
}

class _ElementViewState extends State<_ElementView> {
  final _boxKey = GlobalKey();
  double _baseScale = 1;
  double _baseRotation = 0;
  double _handleBaseScale = 1;
  double _handleBaseRotation = 0;
  double _handleBaseAngle = 0;
  double _handleBaseDist = 1;

  Offset _center() {
    final rb = _boxKey.currentContext?.findRenderObject() as RenderBox?;
    if (rb == null) return Offset.zero;
    return rb.localToGlobal(rb.size.center(Offset.zero));
  }

  @override
  Widget build(BuildContext context) {
    final e = widget.element;
    final c = widget.controller;
    final W = widget.canvas.width;
    final H = widget.canvas.height;
    final selected = c.selectedElementId == e.id;

    final child = _content(e, W);

    // The gesture wrapper and highlight container are always present (handlers
    // just go inert while exporting) so the element — a photo in particular —
    // keeps the same ancestors and never loses its decoded frame (see _SlotView).
    final gestured = GestureDetector(
      behavior: HitTestBehavior.deferToChild,
      onTap: widget.interactive ? () => c.selectElement(e.id) : null,
      onScaleStart: widget.interactive
          ? (_) {
              _baseScale = e.scale;
              _baseRotation = e.rotation;
              c.selectElement(e.id);
            }
          : null,
      onScaleUpdate: widget.interactive
          ? (d) {
              c.updateTransform(
                e.id,
                cx: e.cx + d.focalPointDelta.dx / W,
                cy: e.cy + d.focalPointDelta.dy / H,
                scale: d.pointerCount >= 2 ? _baseScale * d.scale : null,
                rotation: d.pointerCount >= 2 ? _baseRotation + d.rotation : null,
              );
            }
          : null,
      child: child,
    );

    final boxed = Container(
      key: _boxKey,
      decoration: selected
          ? BoxDecoration(
              border: Border.all(color: context.colors.amber, width: 1.5),
              boxShadow: Shadows.focusGlow,
            )
          : const BoxDecoration(),
      child: gestured,
    );

    final showHandles = widget.interactive && selected;

    return Positioned(
      left: e.cx * W,
      top: e.cy * H,
      child: FractionalTranslation(
        translation: const Offset(-0.5, -0.5),
        child: Transform.rotate(
          angle: e.rotation,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              boxed,
              if (showHandles) ...[
                // Delete handle (top-left, danger)
                Positioned(
                  left: -12,
                  top: -12,
                  child: _Handle(
                    icon: Icons.close_rounded,
                    color: context.colors.danger,
                    iconColor: context.colors.onDanger,
                    onTap: () => c.deleteElement(e.id),
                  ),
                ),
                // Scale + rotate handle (bottom-right)
                Positioned(
                  right: -12,
                  bottom: -12,
                  child: GestureDetector(
                    onPanStart: (details) {
                      final center = _center();
                      final v = details.globalPosition - center;
                      _handleBaseScale = e.scale;
                      _handleBaseRotation = e.rotation;
                      _handleBaseAngle = v.direction;
                      _handleBaseDist = v.distance == 0 ? 1 : v.distance;
                    },
                    onPanUpdate: (details) {
                      final center = _center();
                      final v = details.globalPosition - center;
                      final scale = _handleBaseScale * (v.distance / _handleBaseDist);
                      final rot = _handleBaseRotation + (v.direction - _handleBaseAngle);
                      c.updateTransform(e.id, scale: scale, rotation: rot);
                    },
                    child: _Handle(
                      icon: Icons.open_in_full_rounded,
                      color: context.colors.surface,
                      iconColor: context.colors.amber,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _content(CanvasElement e, double canvasW) {
    switch (e) {
      case StickerElement s:
        final w = s.naturalWidthFrac * canvasW * s.scale;
        return SizedBox(
          width: w,
          height: w,
          child: SvgPicture.asset(s.assetPath, fit: BoxFit.contain),
        );
      case ShapeElement s:
        final w = s.naturalWidthFrac * canvasW * s.scale;
        return SizedBox(
          width: w,
          height: w,
          child: CustomPaint(
            painter: ShapePainter(
              kind: s.shapeKind,
              fill: s.fill,
              stroke: s.stroke,
              strokeWidth: s.strokeWidth,
            ),
          ),
        );
      case EmojiElement em:
        final fs = 0.18 * canvasW * em.scale;
        return Text(em.emoji, style: TextStyle(fontSize: fs));
      case GifElement g:
        final w = g.naturalWidthFrac * canvasW * g.scale;
        return SizedBox(
          width: w,
          height: w / g.aspectRatio,
          child: Image.network(g.url, fit: BoxFit.contain, gaplessPlayback: true),
        );
      case ImageElement im:
        final w = im.naturalWidthFrac * canvasW * im.scale;
        Widget photo = SizedBox(
          width: w,
          height: w / im.aspectRatio,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: PhotoImage(assetId: im.assetId, full: true, fit: BoxFit.cover),
          ),
        );
        if (im.flipX || im.flipY) {
          photo = Transform.scale(
            scaleX: im.flipX ? -1 : 1,
            scaleY: im.flipY ? -1 : 1,
            child: photo,
          );
        }
        return photo;
      case TextElement t:
        final fs = 0.09 * canvasW * t.scale;
        return Container(
          constraints: BoxConstraints(maxWidth: canvasW * 0.9),
          color: t.background,
          padding: t.background != null ? const EdgeInsets.symmetric(horizontal: 8, vertical: 4) : null,
          child: Text(
            t.text,
            textAlign: switch (t.align) {
              TextAlignH.left => TextAlign.left,
              TextAlignH.center => TextAlign.center,
              TextAlignH.right => TextAlign.right,
            },
            style: AppFonts.style(t.fontKey, fontSize: fs, color: t.color, bold: t.bold, italic: t.italic),
          ),
        );
    }
  }
}

class _Handle extends StatelessWidget {
  const _Handle({
    required this.icon,
    required this.color,
    required this.iconColor,
    this.onTap,
  });
  final IconData icon;
  final Color color;
  final Color iconColor;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: Sizes.handle,
        height: Sizes.handle,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(color: context.colors.amber, width: 1.5),
        ),
        child: Icon(icon, size: 14, color: iconColor),
      ),
    );
  }
}
