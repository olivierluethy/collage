import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../l10n/app_localizations.dart';
import '../../theme/palette.dart';
import '../../theme/tokens.dart';

/// Zoom and pan of the whole canvas for precise work (shaping edges with a
/// stylus or finger). Two fingers pinch and pan, a trackpad pinches, and
/// Ctrl/⌘ + mouse wheel zooms; buttons do the same without any gesture.
///
/// Gestures are read with a raw [Listener], so they never enter the gesture
/// arena: one-finger drags still reach the handles below, untouched. The
/// zoom only transforms what's shown — the child keeps its layout size, so
/// a RepaintBoundary inside still exports at 1:1.
class ZoomableCanvas extends StatefulWidget {
  const ZoomableCanvas({super.key, required this.enabled, required this.child});

  /// Zoom is allowed. Turning it off snaps back to the whole canvas.
  final bool enabled;
  final Widget child;

  static const double maxScale = 4;

  @override
  State<ZoomableCanvas> createState() => ZoomableCanvasState();
}

@visibleForTesting
class ZoomableCanvasState extends State<ZoomableCanvas> {
  double _scale = 1;
  Offset _offset = Offset.zero; // translation in viewport pixels
  Size _size = Size.zero;

  // Active touch pointers (local positions) and the pinch's starting state.
  final _pointers = <int, Offset>{};
  double? _startDistance;
  late Offset _startFocal;
  late double _startScale;
  late Offset _startOffset;

  double get scale => _scale;
  Offset get offset => _offset;

  @override
  void didUpdateWidget(ZoomableCanvas oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.enabled && !widget.enabled) reset();
  }

  void reset() {
    if (_scale == 1 && _offset == Offset.zero) return;
    setState(() {
      _scale = 1;
      _offset = Offset.zero;
    });
  }

  /// Keeps the content covering the viewport (no empty margins).
  Offset _clampOffset(Offset o, double s) => Offset(
        o.dx.clamp(_size.width * (1 - s), 0.0),
        o.dy.clamp(_size.height * (1 - s), 0.0),
      );

  /// Zooms to [s] keeping the content under [focal] (viewport px) still, then
  /// moves by [pan].
  void _zoomAround({
    required double s,
    required Offset focal,
    required double fromScale,
    required Offset fromOffset,
    Offset pan = Offset.zero,
  }) {
    final ns = s.clamp(1.0, ZoomableCanvas.maxScale);
    final content = (focal - fromOffset) / fromScale; // point in child coords
    final o = _clampOffset(focal + pan - content * ns, ns);
    if (ns == _scale && o == _offset) return;
    setState(() {
      _scale = ns;
      _offset = o;
    });
  }

  /// Button / keyboard zoom around the viewport centre.
  void zoomBy(double factor) => _zoomAround(
        s: _scale * factor,
        focal: _size.center(Offset.zero),
        fromScale: _scale,
        fromOffset: _offset,
      );

  void _restartPinch() {
    if (_pointers.length < 2) {
      _startDistance = null;
      return;
    }
    final pts = _pointers.values.take(2).toList();
    _startDistance = math.max((pts[0] - pts[1]).distance, 1);
    _startFocal = (pts[0] + pts[1]) / 2;
    _startScale = _scale;
    _startOffset = _offset;
  }

  void _down(PointerDownEvent e) {
    if (!widget.enabled || e.kind == PointerDeviceKind.mouse) return;
    _pointers[e.pointer] = e.localPosition;
    _restartPinch();
  }

  void _move(PointerMoveEvent e) {
    if (!_pointers.containsKey(e.pointer)) return;
    _pointers[e.pointer] = e.localPosition;
    final d0 = _startDistance;
    if (d0 == null || _pointers.length < 2) return;
    final pts = _pointers.values.take(2).toList();
    final focal = (pts[0] + pts[1]) / 2;
    _zoomAround(
      s: _startScale * (pts[0] - pts[1]).distance / d0,
      focal: _startFocal,
      fromScale: _startScale,
      fromOffset: _startOffset,
      pan: focal - _startFocal,
    );
  }

  void _up(PointerEvent e) {
    if (_pointers.remove(e.pointer) != null) _restartPinch();
  }

  void _panZoomStart(PointerPanZoomStartEvent e) {
    if (!widget.enabled) return;
    _startFocal = e.localPosition;
    _startScale = _scale;
    _startOffset = _offset;
  }

  void _panZoomUpdate(PointerPanZoomUpdateEvent e) {
    if (!widget.enabled) return;
    _zoomAround(
      s: _startScale * e.scale,
      focal: _startFocal,
      fromScale: _startScale,
      fromOffset: _startOffset,
      pan: _startScale * e.scale > 1 ? e.pan : Offset.zero,
    );
  }

  void _signal(PointerSignalEvent e) {
    if (!widget.enabled || e is! PointerScrollEvent) return;
    final keys = HardwareKeyboard.instance;
    if (!keys.isControlPressed && !keys.isMetaPressed) return;
    GestureBinding.instance.pointerSignalResolver.register(e, (_) {
      _zoomAround(
        s: _scale * math.exp(-e.scrollDelta.dy / 300),
        focal: e.localPosition,
        fromScale: _scale,
        fromOffset: _offset,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, box) {
      final size = box.biggest;
      if (size != _size) {
        _size = size;
        _offset = _clampOffset(_offset, _scale);
      }
      final matrix = Matrix4.identity()
        ..translateByDouble(_offset.dx, _offset.dy, 0, 1)
        ..scaleByDouble(_scale, _scale, 1, 1);
      return Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: Listener(
              behavior: HitTestBehavior.translucent,
              onPointerDown: _down,
              onPointerMove: _move,
              onPointerUp: _up,
              onPointerCancel: _up,
              onPointerPanZoomStart: _panZoomStart,
              onPointerPanZoomUpdate: _panZoomUpdate,
              onPointerSignal: _signal,
              child: ClipRect(
                child: Transform(
                  transform: matrix,
                  child: CanvasZoom(scale: _scale, child: widget.child),
                ),
              ),
            ),
          ),
          if (widget.enabled)
            PositionedDirectional(
              top: Space.xs,
              end: Space.xs,
              child: _ZoomButtons(
                scale: _scale,
                onIn: () => zoomBy(1.5),
                onOut: () => zoomBy(1 / 1.5),
                onReset: reset,
              ),
            ),
        ],
      );
    });
  }
}

/// The current canvas zoom, for widgets that keep a constant on-screen size.
class CanvasZoom extends InheritedWidget {
  const CanvasZoom({super.key, required this.scale, required super.child});
  final double scale;

  static double of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<CanvasZoom>()?.scale ?? 1;

  @override
  bool updateShouldNotify(CanvasZoom old) => old.scale != scale;
}

/// Undoes the canvas zoom around its own centre, so a handle keeps its
/// on-screen size (and 44 dp touch target) however far the canvas is zoomed.
class ZoomInvariant extends StatelessWidget {
  const ZoomInvariant({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final s = CanvasZoom.of(context);
    return s == 1 ? child : Transform.scale(scale: 1 / s, child: child);
  }
}

class _ZoomButtons extends StatelessWidget {
  const _ZoomButtons({required this.scale, required this.onIn, required this.onOut, required this.onReset});
  final double scale;
  final VoidCallback onIn;
  final VoidCallback onOut;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final c = context.colors;
    Widget btn(IconData icon, String tip, VoidCallback? onTap) => IconButton(
          tooltip: tip,
          onPressed: onTap,
          icon: Icon(icon, size: 20),
          color: c.textHi,
          disabledColor: c.textLo,
        );
    return Material(
      color: c.surface.withValues(alpha: 0.92),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radii.control),
        side: BorderSide(color: c.line),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          btn(Icons.zoom_out_rounded, l.t('zoomOut'), scale > 1 ? onOut : null),
          btn(Icons.zoom_in_rounded, l.t('zoomIn'), scale < ZoomableCanvas.maxScale ? onIn : null),
          if (scale > 1) btn(Icons.fit_screen_rounded, l.t('zoomFit'), onReset),
        ],
      ),
    );
  }
}
