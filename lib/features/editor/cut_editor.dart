import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';

import '../../l10n/app_localizations.dart';
import '../../models/layout_template.dart';
import '../../theme/palette.dart';
import '../../theme/tokens.dart';
import '../../widgets/curved_edges.dart';
import 'editor_controller.dart';

/// Direct manipulation of the cuts between photos: every point where cuts
/// meet is a handle, and a quiet "+" in the middle of each cut adds a point.
///
/// The handle's shape says how it moves, so no hint text is needed:
/// * circle — an inner point, moves freely;
/// * rounded square — sits on the canvas border and slides along it;
/// * diamond — a canvas corner; pulling it along a border splits it off, so
///   a corner-to-corner diagonal gets a movable endpoint.
///
/// Tap selects (the panel then offers remove / zigzag / straighten),
/// long-press removes a bend point, drag moves with snapping to halves,
/// thirds and other points. Every gesture is one undo step.
class CutPointEditor extends StatefulWidget {
  const CutPointEditor({super.key, required this.controller, required this.content});
  final EditorController controller;

  /// The layout area in canvas pixels (canvas minus the outer margin).
  final Rect content;

  @override
  State<CutPointEditor> createState() => _CutPointEditorState();
}

class _CutPointEditorState extends State<CutPointEditor> {
  Offset _px(Offset n) => Offset(
        widget.content.left + n.dx * widget.content.width,
        widget.content.top + n.dy * widget.content.height,
      );

  Offset _frac(Offset local) => Offset(
        (local.dx - widget.content.left) / widget.content.width,
        (local.dy - widget.content.top) / widget.content.height,
      );

  Offset? _toLocal(Offset global) {
    final box = context.findRenderObject() as RenderBox?;
    return box?.globalToLocal(global);
  }

  /// Rejected drags (a position that would break a cell) give one light tick
  /// per refusal streak, so the user feels the boundary without a message.
  bool _blocked = false;

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    if (widget.content.isEmpty) return const SizedBox.shrink();
    final l = context.l10n;
    final edges = c.sharedEdges;
    final shapes = c.project.layout.edgeMap;
    final vertices = c.partitionVertices;
    const hit = 44.0;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        // Cuts and snap guides.
        Positioned.fill(
          child: IgnorePointer(
            child: CustomPaint(
              painter: _CutPainter(
                cuts: [
                  for (final e in edges) (_px(e.p), _px(e.q), shapes[e.key], e.key == c.selectedEdgeKey),
                ],
                guideX: c.cutGuideX == null ? null : _px(Offset(c.cutGuideX!, 0)).dx,
                guideY: c.cutGuideY == null ? null : _px(Offset(0, c.cutGuideY!)).dy,
                content: widget.content,
                accent: context.colors.amber,
                quiet: Colors.white.withValues(alpha: 0.75),
              ),
            ),
          ),
        ),
        // "+" in the middle of every cut long enough to take another point.
        for (final e in edges)
          if ((_px(e.p) - _px(e.q)).distance > 64)
            Builder(builder: (context) {
              final mid = (_px(e.p) + _px(e.q)) / 2;
              return Positioned(
                left: mid.dx - hit / 2,
                top: mid.dy - hit / 2,
                child: Semantics(
                  button: true,
                  label: l.t('cutAddPoint'),
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () {
                      HapticFeedback.selectionClick();
                      c.insertCutPoint(e);
                    },
                    child: SizedBox(
                      width: hit,
                      height: hit,
                      child: Center(
                        child: Container(
                          width: 16,
                          height: 16,
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.35),
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white.withValues(alpha: 0.8), width: 1),
                          ),
                          child: const Icon(Icons.add_rounded, size: 12, color: Colors.white),
                        ),
                      ),
                    ),
                  ),
                ),
              );
            }),
        // The points themselves.
        for (var i = 0; i < vertices.length; i++)
          Builder(builder: (context) {
            final v = vertices[i];
            final at = _px(v.at);
            final selected = v.key == c.selectedVertexKey;
            final kind = v.isCorner
                ? _HandleKind.corner
                : v.onBorder
                    ? _HandleKind.border
                    : _HandleKind.inner;
            return Positioned(
              key: ValueKey('cut-pt-$i'),
              left: at.dx - hit / 2,
              top: at.dy - hit / 2,
              child: Semantics(
                label: l.a('cutPointOf', {'n': '${i + 1}', 'total': '${vertices.length}'}),
                hint: l.t(switch (kind) {
                  _HandleKind.corner => 'cutCornerHint',
                  _HandleKind.border => 'cutBorderHint',
                  _HandleKind.inner => 'cutInnerHint',
                }),
                selected: selected,
                button: true,
                onTap: () => c.selectVertex(v.key),
                customSemanticsActions: {
                  CustomSemanticsAction(label: l.t('cutNudgeLeft')): () => c.nudgeSelectedVertexOr(v, const Offset(-0.01, 0)),
                  CustomSemanticsAction(label: l.t('cutNudgeRight')): () => c.nudgeSelectedVertexOr(v, const Offset(0.01, 0)),
                  CustomSemanticsAction(label: l.t('cutNudgeUp')): () => c.nudgeSelectedVertexOr(v, const Offset(0, -0.01)),
                  CustomSemanticsAction(label: l.t('cutNudgeDown')): () => c.nudgeSelectedVertexOr(v, const Offset(0, 0.01)),
                  if (v.removable)
                    CustomSemanticsAction(label: l.t('cutRemovePoint')): () {
                      c.selectVertex(v.key);
                      c.removeSelectedVertex();
                    },
                },
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    HapticFeedback.selectionClick();
                    c.selectVertex(v.key);
                  },
                  onLongPress: v.removable
                      ? () {
                          HapticFeedback.mediumImpact();
                          c.selectVertex(v.key);
                          c.removeSelectedVertex();
                        }
                      : null,
                  onPanStart: (_) {
                    HapticFeedback.selectionClick();
                    _blocked = false;
                    c.beginVertexDrag(v);
                  },
                  onPanUpdate: (d) {
                    final local = _toLocal(d.globalPosition);
                    if (local == null) return;
                    final ok = c.dragVertexTo(_frac(local));
                    if (!ok && !_blocked) HapticFeedback.lightImpact();
                    _blocked = !ok;
                  },
                  onPanEnd: (_) => c.endVertexDrag(),
                  onPanCancel: c.endVertexDrag,
                  child: SizedBox(
                    width: hit,
                    height: hit,
                    child: Center(child: _PointHandle(kind: kind, selected: selected)),
                  ),
                ),
              ),
            );
          }),
      ],
    );
  }
}

enum _HandleKind { inner, border, corner }

class _PointHandle extends StatelessWidget {
  const _PointHandle({required this.kind, required this.selected});
  final _HandleKind kind;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final size = selected ? 22.0 : 17.0;
    final fill = selected ? context.colors.amber : context.colors.surface;
    final border = Border.all(color: selected ? context.colors.onAmber : context.colors.amber, width: 2);
    final shadow = selected ? Shadows.focusGlow : Shadows.e1;
    final box = switch (kind) {
      _HandleKind.inner => BoxDecoration(color: fill, shape: BoxShape.circle, border: border, boxShadow: shadow),
      _ => BoxDecoration(color: fill, borderRadius: BorderRadius.circular(4), border: border, boxShadow: shadow),
    };
    final handle = AnimatedContainer(duration: Motion.fast, width: size, height: size, decoration: box);
    return kind == _HandleKind.corner ? Transform.rotate(angle: math.pi / 4, child: handle) : handle;
  }
}

/// Every cut as a thin line (the selected one in amber) plus snap guides
/// across the content area.
class _CutPainter extends CustomPainter {
  _CutPainter({
    required this.cuts,
    required this.guideX,
    required this.guideY,
    required this.content,
    required this.accent,
    required this.quiet,
  });

  final List<(Offset, Offset, EdgeShape?, bool)> cuts;
  final double? guideX;
  final double? guideY;
  final Rect content;
  final Color accent;
  final Color quiet;

  @override
  void paint(Canvas canvas, Size size) {
    for (final (p, q, shape, selected) in cuts) {
      final path = Path()..moveTo(p.dx, p.dy);
      if (shape == null || shape.isStraight) {
        path.lineTo(q.dx, q.dy);
      } else {
        appendShapedEdge(path, p, q, shape, false);
      }
      // A dark underlay keeps the line visible over light photos.
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = selected ? 4.5 : 3
          ..color = Colors.black.withValues(alpha: 0.25),
      );
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = selected ? 2.5 : 1.2
          ..color = selected ? accent : quiet,
      );
    }
    final guide = Paint()
      ..color = accent.withValues(alpha: 0.85)
      ..strokeWidth = 1;
    if (guideX != null) canvas.drawLine(Offset(guideX!, content.top), Offset(guideX!, content.bottom), guide);
    if (guideY != null) canvas.drawLine(Offset(content.left, guideY!), Offset(content.right, guideY!), guide);
  }

  @override
  bool shouldRepaint(_CutPainter old) => true;
}
