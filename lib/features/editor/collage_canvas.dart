import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../data/fonts.dart';
import '../../data/shape_catalog.dart';
import '../../models/canvas_element.dart';
import '../../models/collage_project.dart';
import '../../theme/text_styles.dart';
import '../../theme/tokens.dart';
import '../../widgets/pattern_painter.dart';
import '../../widgets/photo_image.dart';
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
                  if (interactive)
                    Positioned.fill(
                      child: GestureDetector(
                        behavior: HitTestBehavior.translucent,
                        onTap: c.clearSelection,
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

    return slots.map((slot) {
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
        if (bg.imageAssetId == null) return const ColoredBox(color: AppColors.inkCanvas);
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
              child: PhotoImage(
                assetId: fill.assetId,
                full: true,
                fit: BoxFit.cover,
                alignment: Alignment(fill.offsetX, fill.offsetY),
              ),
            ),
          )
        : DottedSlot(radius: radius);

    Widget box = Container(
      decoration: BoxDecoration(
        borderRadius: br,
        border: thickness > 0 ? Border.all(color: borderColor, width: thickness) : null,
      ),
      child: content,
    );

    if (!interactive) return box;

    // A subtle, persistent edit badge signals every filled slot is tappable.
    if (realFill != null && !selected) {
      box = Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(child: box),
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
        ],
      );
    }

    // Selected / swap-target highlight.
    if (selected || swapTarget) {
      box = Container(
        decoration: BoxDecoration(
          borderRadius: br,
          border: Border.all(
            color: swapTarget ? AppColors.amberBright : AppColors.amber,
            width: swapTarget ? 3 : 2,
          ),
          boxShadow: selected ? Shadows.focusGlow : null,
        ),
        child: box,
      );
    }

    // Drop target for drag-to-swap, with live preview via updateSlotDragOver.
    Widget interactiveBox = DragTarget<String>(
      onWillAcceptWithDetails: (d) => d.data != slotId,
      onMove: (_) => controller.updateSlotDragOver(slotId),
      onLeave: (_) {
        if (controller.dragOverSlot == slotId) controller.updateSlotDragOver(null);
      },
      onAcceptWithDetails: (d) {
        controller.swapSlots(d.data, slotId);
        controller.endSlotDrag();
      },
      builder: (context, candidate, rejected) {
        final child = GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            if (controller.completeSwapIfActive(slotId)) return;
            controller.selectSlot(slotId);
          },
          child: box,
        );
        // A filled slot can be dragged with an immediate (non-long-press) drag.
        if (realFill == null) return child;
        return Draggable<String>(
          data: slotId,
          onDragStarted: () => controller.startSlotDrag(slotId),
          onDragEnd: (_) => controller.endSlotDrag(),
          onDraggableCanceled: (_, __) => controller.endSlotDrag(),
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
          childWhenDragging: Opacity(opacity: 0.25, child: box),
          child: child,
        );
      },
    );

    // Inline action chips on the selected slot.
    if (selected) {
      interactiveBox = Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(child: interactiveBox),
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
                  onClear: () => controller.clearSlot(slotId),
                ),
              ),
            ),
          ),
        ],
      );
    }

    return interactiveBox;
  }
}

/// The Replace / Swap / Clear chips shown on a selected slot.
class _SlotChips extends StatelessWidget {
  const _SlotChips({
    required this.hasPhoto,
    required this.onReplace,
    required this.onSwap,
    required this.onClear,
  });
  final bool hasPhoto;
  final VoidCallback onReplace;
  final VoidCallback onSwap;
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
          _Chip(icon: Icons.photo_library_rounded, label: hasPhoto ? 'Replace' : 'Choose', onTap: onReplace),
          if (hasPhoto) _Chip(icon: Icons.swap_horiz_rounded, label: 'Swap', onTap: onSwap),
          if (hasPhoto) _Chip(icon: Icons.close_rounded, label: 'Clear', onTap: onClear, danger: true),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.icon, required this.label, required this.onTap, this.danger = false});
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final c = danger ? AppColors.danger : AppColors.amber;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 2),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(Radii.pill),
          border: Border.all(color: c),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: c),
            const SizedBox(width: 4),
            Text(label, style: AppText.labelMd.copyWith(color: c)),
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
        color: AppColors.surfaceInput,
        borderRadius: BorderRadius.circular(radius),
      ),
      child: const Center(
        child: Icon(Icons.add_photo_alternate_outlined, color: AppColors.textLo, size: 28),
      ),
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

    Widget gestured = child;
    if (widget.interactive) {
      gestured = GestureDetector(
        behavior: HitTestBehavior.deferToChild,
        onTap: () => c.selectElement(e.id),
        onScaleStart: (_) {
          _baseScale = e.scale;
          _baseRotation = e.rotation;
          c.selectElement(e.id);
        },
        onScaleUpdate: (d) {
          c.updateTransform(
            e.id,
            cx: e.cx + d.focalPointDelta.dx / W,
            cy: e.cy + d.focalPointDelta.dy / H,
            scale: d.pointerCount >= 2 ? _baseScale * d.scale : null,
            rotation: d.pointerCount >= 2 ? _baseRotation + d.rotation : null,
          );
        },
        child: child,
      );
    }

    Widget boxed = Container(
      key: _boxKey,
      decoration: selected
          ? BoxDecoration(
              border: Border.all(color: AppColors.amber, width: 1.5),
              boxShadow: Shadows.focusGlow,
            )
          : null,
      child: gestured,
    );

    if (selected && widget.interactive) {
      boxed = Stack(
        clipBehavior: Clip.none,
        children: [
          boxed,
          // Delete handle (top-left, danger)
          Positioned(
            left: -12,
            top: -12,
            child: _Handle(
              icon: Icons.close_rounded,
              color: AppColors.danger,
              iconColor: AppColors.onDanger,
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
              child: const _Handle(
                icon: Icons.open_in_full_rounded,
                color: AppColors.surface,
                iconColor: AppColors.amber,
              ),
            ),
          ),
        ],
      );
    }

    return Positioned(
      left: e.cx * W,
      top: e.cy * H,
      child: FractionalTranslation(
        translation: const Offset(-0.5, -0.5),
        child: Transform.rotate(angle: e.rotation, child: boxed),
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
        return SizedBox(
          width: w,
          height: w / im.aspectRatio,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: PhotoImage(assetId: im.assetId, full: true, fit: BoxFit.cover),
          ),
        );
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
          border: Border.all(color: AppColors.amber, width: 1.5),
        ),
        child: Icon(icon, size: 14, color: iconColor),
      ),
    );
  }
}
