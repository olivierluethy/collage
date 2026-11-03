import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:collage/features/editor/canvas_zoom.dart';
import 'package:collage/l10n/app_localizations.dart';
import 'package:collage/theme/app_theme.dart';

class _Host extends StatefulWidget {
  const _Host({required this.onDrag});
  final ValueChanged<Offset> onDrag;

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  bool enabled = true;

  @override
  Widget build(BuildContext context) => MaterialApp(
        theme: AppTheme.dark,
        locale: const Locale('en'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 300,
              height: 300,
              child: ZoomableCanvas(
                enabled: enabled,
                child: Stack(
                  children: [
                    const Positioned.fill(child: ColoredBox(color: Colors.blue)),
                    Positioned(
                      left: 130,
                      top: 130,
                      child: GestureDetector(
                        key: const Key('handle'),
                        // Like the editor's edge handles.
                        behavior: HitTestBehavior.opaque,
                        onPanUpdate: (d) => widget.onDrag(d.delta),
                        child: const ZoomInvariant(
                          child: SizedBox(width: 40, height: 40, child: ColoredBox(color: Colors.amber)),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
}

ZoomableCanvasState _state(WidgetTester t) => t.state(find.byType(ZoomableCanvas));

void main() {
  testWidgets('buttons zoom in, out and back to the whole canvas', (tester) async {
    await tester.pumpWidget(_Host(onDrag: (_) {}));
    await tester.pumpAndSettle();
    expect(_state(tester).scale, 1);
    expect(find.byTooltip('Show whole canvas'), findsNothing);

    await tester.tap(find.byTooltip('Zoom in'));
    await tester.pump();
    expect(_state(tester).scale, closeTo(1.5, 1e-9));
    // Zoomed around the centre: the centre stays put.
    expect(_state(tester).offset.dx, closeTo(-75, 1e-6));

    for (var i = 0; i < 6; i++) {
      await tester.tap(find.byTooltip('Zoom in'));
      await tester.pump();
    }
    expect(_state(tester).scale, ZoomableCanvas.maxScale);

    await tester.tap(find.byTooltip('Show whole canvas'));
    await tester.pump();
    expect(_state(tester).scale, 1);
    expect(_state(tester).offset, Offset.zero);
  });

  testWidgets('two fingers pinch-zoom; the content never leaves the frame', (tester) async {
    await tester.pumpWidget(_Host(onDrag: (_) {}));
    await tester.pumpAndSettle();
    final centre = tester.getCenter(find.byType(ZoomableCanvas));

    final a = await tester.startGesture(centre - const Offset(40, 0), pointer: 1);
    final b = await tester.startGesture(centre + const Offset(40, 0), pointer: 2);
    await a.moveTo(centre - const Offset(80, 0));
    await b.moveTo(centre + const Offset(80, 0));
    await tester.pump();
    expect(_state(tester).scale, closeTo(2, 1e-6));

    // Panning far right is clamped at the left edge of the content.
    await a.moveBy(const Offset(400, 0));
    await b.moveBy(const Offset(400, 0));
    await tester.pump();
    expect(_state(tester).offset.dx, 0);

    // Pinching in past 1x stops at the whole canvas.
    await a.moveTo(centre - const Offset(5, 0));
    await b.moveTo(centre + const Offset(5, 0));
    await tester.pump();
    expect(_state(tester).scale, 1);
    expect(_state(tester).offset, Offset.zero);
    await a.up();
    await b.up();
  });

  testWidgets('a one-finger drag still reaches the handle, in canvas units', (tester) async {
    final drags = <Offset>[];
    await tester.pumpWidget(_Host(onDrag: drags.add));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Zoom in'));
    await tester.pump();
    await tester.tap(find.byTooltip('Zoom in'));
    await tester.pump(); // 2.25x

    await tester.drag(find.byKey(const Key('handle')), const Offset(90, 0), touchSlopX: 0);
    await tester.pump();
    expect(_state(tester).scale, closeTo(2.25, 1e-9), reason: 'one finger never zooms');
    final total = drags.fold<Offset>(Offset.zero, (s, d) => s + d);
    // 90 screen px at 2.25x is 40 canvas px.
    expect(total.dx, closeTo(40, 0.5));
  });

  testWidgets('disabling snaps back and hides the buttons', (tester) async {
    await tester.pumpWidget(_Host(onDrag: (_) {}));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Zoom in'));
    await tester.pump();

    final host = tester.state<_HostState>(find.byType(_Host));
    host.setState(() => host.enabled = false);
    await tester.pump();
    expect(_state(tester).scale, 1);
    expect(find.byTooltip('Zoom in'), findsNothing);
  });
}
