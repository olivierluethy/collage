import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../models/layout_template.dart';
import '../../theme/palette.dart';
import '../../theme/tokens.dart';
import '../../theme/typography.dart';
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
    final edges = widget.c.sharedEdges;
    if (edges.isEmpty) return;
    final i = edges.indexWhere((e) => e.key == widget.c.selectedEdgeKey);
    final next = (i < 0 ? 0 : i + dir) % edges.length;
    widget.c.selectEdge(edges[next < 0 ? next + edges.length : next].key);
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
        final shape = key == null ? null : c.edgeShape(key);
        final index = edges.indexWhere((e) => e.key == key);
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
            // Which edge: step through them without hitting the small dots.
            Row(
              children: [
                IconButton(
                  tooltip: l.t('edgePrevious'),
                  onPressed: () => _step(-1),
                  icon: const Icon(Icons.chevron_left_rounded),
                ),
                Expanded(
                  child: Text(
                    key == null
                        ? l.t('edgeTapHint')
                        : l.a('edgeOf', {'n': '${index + 1}', 'total': '${edges.length}'}),
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
            ),
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
