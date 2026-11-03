import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../models/layout_template.dart';
import '../../theme/palette.dart';
import '../../theme/tokens.dart';
import '../../theme/typography.dart';
import '../../widgets/curved_edges.dart';
import 'editor_controller.dart';

/// One-tap edge looks. Each sets the two Bézier control points and the
/// zigzag teeth of an edge; the amber points on the canvas fine-tune it.
enum EdgePreset { straight, curve, wave, zigzag, curvyZigzag }

EdgeShape applyEdgePreset(EdgeShape s, EdgePreset p) => switch (p) {
      EdgePreset.straight => s.copyWith(c1: const Offset(1 / 3, 0), c2: const Offset(2 / 3, 0), zigAmp: 0, zigCount: 0),
      EdgePreset.curve => s.copyWith(c1: const Offset(1 / 3, 0.2), c2: const Offset(2 / 3, 0.2), zigAmp: 0, zigCount: 0),
      EdgePreset.wave => s.copyWith(c1: const Offset(1 / 3, 0.22), c2: const Offset(2 / 3, -0.22), zigAmp: 0, zigCount: 0),
      EdgePreset.zigzag => s.copyWith(c1: const Offset(1 / 3, 0), c2: const Offset(2 / 3, 0), zigAmp: 0.025, zigCount: 10),
      EdgePreset.curvyZigzag => s.copyWith(c1: const Offset(1 / 3, 0.2), c2: const Offset(2 / 3, 0.2), zigAmp: 0.025, zigCount: 10),
    };

EdgePreset? presetOf(EdgeShape s) {
  for (final p in EdgePreset.values) {
    final t = applyEdgePreset(s, p);
    if ((t.c1 - s.c1).distance < 1e-3 &&
        (t.c2 - s.c2).distance < 1e-3 &&
        (t.zigAmp - s.zigAmp).abs() < 1e-3 &&
        t.zigCount == s.zigCount) {
      return p;
    }
  }
  return null;
}

/// Shape the cuts between photos: pick an edge (tap its dot on the canvas, or
/// step through them here), choose a look, then drag the amber points or use
/// the sliders. Everything is one undo step per gesture.
class EdgePanel extends StatefulWidget {
  const EdgePanel({super.key, required this.c, required this.onDone});
  final EditorController c;
  final VoidCallback onDone;

  @override
  State<EdgePanel> createState() => _EdgePanelState();
}

class _EdgePanelState extends State<EdgePanel> {
  bool _all = false;

  void _step(int dir) {
    final keys = <String>[];
    for (final e in widget.c.sharedEdges) {
      if (!keys.contains(e.key)) keys.add(e.key);
    }
    if (keys.isEmpty) return;
    final i = keys.indexOf(widget.c.selectedEdgeKey ?? '');
    final next = (i < 0 ? 0 : i + dir) % keys.length;
    widget.c.selectEdge(keys[next < 0 ? next + keys.length : next]);
  }

  /// Step through the cuts without hitting the small dots on the canvas.
  /// Bent cuts appear once per piece but are one cut, so steps go by key.
  Widget _stepper(BuildContext context, List<SharedEdge> edges, String? key) {
    final l = context.l10n;
    final keys = <String>[];
    for (final e in edges) {
      if (!keys.contains(e.key)) keys.add(e.key);
    }
    final index = keys.indexOf(key ?? '');
    final angle = key == null ? null : widget.c.cutAngle(key);
    return Row(
      children: [
        IconButton(
          tooltip: l.t('edgePrevious'),
          onPressed: () => _step(-1),
          icon: const Icon(Icons.chevron_left_rounded),
        ),
        Expanded(
          child: Text(
            key == null || index < 0
                ? l.t('edgeTapHint')
                : [
                    l.a('cutOf', {'n': '${index + 1}', 'total': '${keys.length}'}),
                    if (angle != null) l.a('cutAngle', {'deg': angle.toStringAsFixed(0)}),
                  ].join('   '),
            textAlign: TextAlign.center,
            style: context.text.caption.copyWith(color: context.colors.textMid),
          ),
        ),
        IconButton(
          tooltip: l.t('edgeNext'),
          onPressed: () => _step(1),
          icon: const Icon(Icons.chevron_right_rounded),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.c;
    final l = context.l10n;
    return AnimatedBuilder(
      animation: c,
      builder: (context, _) {
        final edges = c.sharedEdges;
        final key = c.selectedEdgeKey;
        if (edges.isEmpty) {
          return Padding(
            padding: const EdgeInsets.all(Space.lg),
            child: Text(l.t('edgeNone'), style: context.text.bodyMd.copyWith(color: context.colors.textMid)),
          );
        }
        final modeBar = Padding(
          padding: const EdgeInsets.only(bottom: Space.xs),
          child: SegmentedButton<CutMode>(
            segments: [
              ButtonSegment(value: CutMode.points, icon: const Icon(Icons.polyline_rounded, size: 18), label: Text(l.t('cutModePoints'))),
              ButtonSegment(value: CutMode.curves, icon: const Icon(Icons.gesture_rounded, size: 18), label: Text(l.t('cutModeCurves'))),
            ],
            selected: {c.cutMode},
            onSelectionChanged: (s) => c.setCutMode(s.first),
            showSelectedIcon: false,
            style: const ButtonStyle(visualDensity: VisualDensity.compact),
          ),
        );
        if (c.cutMode == CutMode.points) {
          return _PointsBody(c: c, modeBar: modeBar, stepper: _stepper(context, edges, key), onDone: widget.onDone);
        }
        final shape = key == null ? null : c.edgeShape(key);
        final current = shape == null ? null : presetOf(shape);
        final bend = shape == null ? 0.0 : (shape.c1.dy.abs() > shape.c2.dy.abs() ? shape.c1.dy : shape.c2.dy);
        final wave = shape != null && shape.c1.dy * shape.c2.dy < 0;

        void update(EdgeShape Function(EdgeShape s) fn) {
          if (key == null) return;
          c.setEdgeShape(key, fn, all: _all);
        }

        final presets = <(EdgePreset, IconData, String)>[
          (EdgePreset.straight, Icons.horizontal_rule_rounded, l.t('edgeStraight')),
          (EdgePreset.curve, Icons.panorama_fish_eye_rounded, l.t('edgeCurve')),
          (EdgePreset.wave, Icons.waves_rounded, l.t('edgeWave')),
          (EdgePreset.zigzag, Icons.show_chart_rounded, l.t('edgeZigzag')),
          (EdgePreset.curvyZigzag, Icons.ssid_chart_rounded, l.t('edgeCurvyZigzag')),
        ];

        return ListView(
          padding: const EdgeInsets.fromLTRB(Space.lg, Space.sm, Space.lg, Space.lg),
          children: [
            modeBar,
            // Which edge: step through them without hitting the small dots.
            _stepper(context, edges, key),
            const SizedBox(height: Space.xs),
            SizedBox(
              height: 64,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: presets.length,
                separatorBuilder: (_, __) => const SizedBox(width: Space.sm),
                itemBuilder: (context, i) {
                  final (p, icon, label) = presets[i];
                  final sel = current == p;
                  return Semantics(
                    button: true,
                    selected: sel,
                    child: InkWell(
                      onTap: key == null ? null : () => update((s) => applyEdgePreset(s, p)),
                      borderRadius: BorderRadius.circular(Radii.control),
                      child: Container(
                        width: 76,
                        decoration: BoxDecoration(
                          color: sel ? context.colors.amberTint : context.colors.surfaceInput,
                          borderRadius: BorderRadius.circular(Radii.control),
                          border: Border.all(color: sel ? context.colors.amber : Colors.transparent),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(icon, size: 20, color: sel ? context.colors.amber : context.colors.textMid),
                            const SizedBox(height: 2),
                            Text(label,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: context.text.caption.copyWith(
                                    color: sel ? context.colors.amber : context.colors.textMid)),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            if (shape != null) ...[
              _Labeled(
                label: l.t('edgeBend'),
                child: Slider(
                  value: bend.clamp(-0.5, 0.5),
                  min: -0.5,
                  max: 0.5,
                  onChanged: (v) => update((s) => s.copyWith(
                        c1: Offset(s.c1.dx, v),
                        c2: Offset(s.c2.dx, wave ? -v : v),
                      )),
                ),
              ),
              _Labeled(
                label: l.t('edgeTeethHeight'),
                child: Slider(
                  value: shape.zigAmp.clamp(0, 0.08),
                  max: 0.08,
                  onChanged: (v) => update((s) => s.copyWith(zigAmp: v, zigCount: s.zigCount == 0 ? 10 : s.zigCount)),
                ),
              ),
              _Labeled(
                label: l.a('edgeTeethCount', {'n': '${shape.zigCount}'}),
                child: Slider(
                  value: shape.zigCount.toDouble().clamp(0, 40),
                  max: 40,
                  divisions: 40,
                  onChanged: (v) => update((s) => s.copyWith(
                        zigCount: v.round(),
                        zigAmp: s.zigAmp == 0 && v > 0 ? 0.025 : s.zigAmp,
                      )),
                ),
              ),
            ],
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(l.t('edgeApplyAll'), style: context.text.bodyMd),
              value: _all,
              onChanged: (v) => setState(() => _all = v),
            ),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: c.project.layout.edges.isEmpty ? null : c.straightenAllEdges,
                    icon: const Icon(Icons.straighten_rounded, size: 18),
                    label: Text(l.t('edgeStraightenAll')),
                  ),
                ),
                const SizedBox(width: Space.sm),
                Expanded(
                  child: FilledButton(onPressed: widget.onDone, child: Text(l.t('done'))),
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}

class _Labeled extends StatelessWidget {
  const _Labeled({required this.label, required this.child});
  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 104,
          child: Text(label, style: context.text.caption.copyWith(color: context.colors.textMid)),
        ),
        Expanded(child: child),
      ],
    );
  }
}

/// Points mode: the canvas handles do the work; the panel names the selected
/// cut, turns it into an editable zigzag or straightens it, removes the
/// selected point, and nudges it precisely (keyboard / accessibility).
class _PointsBody extends StatefulWidget {
  const _PointsBody({required this.c, required this.modeBar, required this.stepper, required this.onDone});
  final EditorController c;
  final Widget modeBar;
  final Widget stepper;
  final VoidCallback onDone;

  @override
  State<_PointsBody> createState() => _PointsBodyState();
}

class _PointsBodyState extends State<_PointsBody> {
  int _teeth = 4;
  double _depth = 0.06;

  @override
  Widget build(BuildContext context) {
    final c = widget.c;
    final l = context.l10n;
    final key = c.selectedEdgeKey;
    final v = c.selectedVertex;
    const step = 0.01;
    Widget nudge(IconData icon, String tip, Offset d) => IconButton(
          tooltip: tip,
          visualDensity: VisualDensity.compact,
          onPressed: v == null ? null : () => c.nudgeSelectedVertex(d),
          icon: Icon(icon),
        );
    return ListView(
      padding: const EdgeInsets.fromLTRB(Space.lg, Space.sm, Space.lg, Space.lg),
      children: [
        widget.modeBar,
        widget.stepper,
        Text(
          l.t('cutHint'),
          textAlign: TextAlign.center,
          style: context.text.caption.copyWith(color: context.colors.textLo),
        ),
        const SizedBox(height: Space.sm),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: key == null ? null : () => c.zigzagCut(key, teeth: _teeth, amplitude: _depth),
                icon: const Icon(Icons.show_chart_rounded, size: 18),
                label: Text(l.t('cutZigzag'), maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
            ),
            const SizedBox(width: Space.sm),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: key == null ? null : () => c.straightenCut(key),
                icon: const Icon(Icons.horizontal_rule_rounded, size: 18),
                label: Text(l.t('cutStraighten'), maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
            ),
          ],
        ),
        _Labeled(
          label: l.a('cutTeeth', {'n': '$_teeth'}),
          child: Slider(
            value: _teeth.toDouble(),
            min: 1,
            max: 10,
            divisions: 9,
            onChanged: key == null
                ? null
                : (x) {
                    setState(() => _teeth = x.round());
                    c.zigzagCut(key, teeth: _teeth, amplitude: _depth);
                  },
          ),
        ),
        _Labeled(
          label: l.t('cutDepth'),
          child: Slider(
            value: _depth,
            min: 0.01,
            max: 0.2,
            onChanged: key == null
                ? null
                : (x) {
                    setState(() => _depth = x);
                    c.zigzagCut(key, teeth: _teeth, amplitude: _depth);
                  },
          ),
        ),
        // The selected point: nudge it precisely, or remove it.
        Row(
          children: [
            nudge(Icons.arrow_back_rounded, l.t('cutNudgeLeft'), const Offset(-step, 0)),
            nudge(Icons.arrow_upward_rounded, l.t('cutNudgeUp'), const Offset(0, -step)),
            nudge(Icons.arrow_downward_rounded, l.t('cutNudgeDown'), const Offset(0, step)),
            nudge(Icons.arrow_forward_rounded, l.t('cutNudgeRight'), const Offset(step, 0)),
            const Spacer(),
            TextButton.icon(
              onPressed: v != null && v.removable ? c.removeSelectedVertex : null,
              icon: const Icon(Icons.remove_circle_outline_rounded, size: 18),
              label: Text(l.t('cutRemovePoint')),
            ),
          ],
        ),
        const SizedBox(height: Space.xs),
        FilledButton(onPressed: widget.onDone, child: Text(l.t('done'))),
      ],
    );
  }
}
