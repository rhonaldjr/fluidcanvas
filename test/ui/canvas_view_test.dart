import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inkpad/domain/models/models.dart';
import 'package:inkpad/engine/renderer/layer_stack_painter.dart';
import 'package:inkpad/engine/smoothing.dart';
import 'package:inkpad/state/state.dart';
import 'package:inkpad/ui/ui.dart';

const _pageKey = Key('canvas-page');

/// Pumps the canvas over a container the test can read state from.
Future<ProviderContainer> pumpCanvas(
  WidgetTester tester, {
  Size size = const Size(1280, 720),
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));

  final container = ProviderContainer.test();
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: Scaffold(body: CanvasView())),
    ),
  );
  return container;
}

SkdDocument documentOf(ProviderContainer c) => c.read(activeDocumentProvider);

Layer activeLayerOf(ProviderContainer c) =>
    c.read(activeSessionProvider).activeLayer;

/// The painter for the active layer — the only one that carries the live
/// stroke, and the only one that repaints while drawing.
LayerStackPainter painterOf(WidgetTester tester) {
  final painters = tester
      .widgetList<CustomPaint>(find.byType(CustomPaint))
      .map((p) => p.painter)
      .whereType<LayerStackPainter>()
      .where((p) => p.debugLabel == 'active');
  return painters.single;
}

/// Points of the stroke currently under the pointer, as the painter sees them.
List<StrokePoint> livePointsOf(WidgetTester tester) =>
    painterOf(tester).liveStroke?.points ?? const [];

void main() {
  group('fitScale', () {
    test('fits the page inside the viewport with a margin on each side', () {
      // 1920 wide page in a 1984 wide viewport: 64px of margin leaves exactly
      // 1920, so scale is 1.
      expect(
        CanvasView.fitScale(
          viewport: const Size(1984, 2000),
          documentWidth: 1920,
          documentHeight: 1080,
        ),
        1.0,
      );
    });

    test('never magnifies past 100%', () {
      expect(
        CanvasView.fitScale(
          viewport: const Size(9999, 9999),
          documentWidth: 1920,
          documentHeight: 1080,
        ),
        1.0,
      );
    });

    test('is limited by the tighter axis', () {
      expect(
        CanvasView.fitScale(
          viewport: const Size(9999, 604),
          documentWidth: 1920,
          documentHeight: 1080,
        ),
        closeTo(540 / 1080, 1e-9),
      );
    });

    test('collapses to zero rather than going negative', () {
      expect(
        CanvasView.fitScale(
          viewport: const Size(10, 10),
          documentWidth: 1920,
          documentHeight: 1080,
        ),
        0.0,
      );
    });

    test('an unbounded viewport yields zero, not infinity', () {
      expect(
        CanvasView.fitScale(
          viewport: const Size(double.infinity, double.infinity),
          documentWidth: 1920,
          documentHeight: 1080,
        ),
        0.0,
      );
    });
  });

  group('in-progress rendering', () {
    testWidgets('the painter starts with no points', (tester) async {
      await pumpCanvas(tester);
      expect(livePointsOf(tester), isEmpty);
    });

    testWidgets('points accumulate on the painter while dragging', (
      tester,
    ) async {
      await pumpCanvas(tester);
      final page = tester.getCenter(find.byKey(_pageKey));

      final gesture = await tester.startGesture(page);
      await tester.pump();
      expect(livePointsOf(tester), hasLength(1));

      // The second raw point emits nothing: a curve segment needs three points
      // before it has a control point.
      await gesture.moveBy(const Offset(10, 0));
      await tester.pump();
      expect(livePointsOf(tester), hasLength(1));

      // The third completes the first segment: its start plus the samples.
      await gesture.moveBy(const Offset(10, 0));
      await tester.pump();
      expect(livePointsOf(tester), hasLength(1 + 1 + kSmoothingSamples));

      // Each further point emits exactly one segment.
      await gesture.moveBy(const Offset(10, 0));
      await tester.pump();
      expect(livePointsOf(tester), hasLength(1 + 1 + 2 * kSmoothingSamples));

      await gesture.up();
      await tester.pump();
    });

    testWidgets('the in-progress stroke is cleared on pointer-up', (
      tester,
    ) async {
      await pumpCanvas(tester);
      final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(_pageKey)),
      );
      await gesture.moveBy(const Offset(10, 10));
      await gesture.up();
      await tester.pump();

      expect(livePointsOf(tester), isEmpty);
    });

    testWidgets('painted points are in document space, not screen space', (
      tester,
    ) async {
      await pumpCanvas(tester);
      final pageRect = tester.getRect(find.byKey(_pageKey));

      final gesture = await tester.startGesture(pageRect.topLeft);
      await tester.pump();
      final first = livePointsOf(tester).single;
      expect(first.x, closeTo(0, 0.01));
      expect(first.y, closeTo(0, 0.01));

      // Three raw points, so the smoother has emitted a segment. Every point
      // stays inside the document, nowhere near screen coordinates.
      await gesture.moveTo(pageRect.center);
      await gesture.moveTo(pageRect.bottomRight - const Offset(1, 1));
      await tester.pump();

      for (final p in livePointsOf(tester)) {
        expect(p.x, inInclusiveRange(0, 1920));
        expect(p.y, inInclusiveRange(0, 1080));
      }
      expect(livePointsOf(tester).last.x, greaterThan(500));

      await gesture.up();
      await tester.pump();
    });

    testWidgets('the painter is scaled to match the page', (tester) async {
      await pumpCanvas(tester);
      final pageWidth = tester.getSize(find.byKey(_pageKey)).width;
      expect(painterOf(tester).scale, closeTo(pageWidth / 1920, 1e-9));
    });

    testWidgets('no capture layer exists when the page collapses to zero', (
      tester,
    ) async {
      await pumpCanvas(tester, size: const Size(40, 40));
      expect(find.byType(StrokeCapture), findsNothing);
    });
  });

  group('committing a stroke', () {
    testWidgets('a drag adds one stroke with more than one point', (
      tester,
    ) async {
      final container = await pumpCanvas(tester);
      expect(documentOf(container).elementCount, 0);

      final page = tester.getCenter(find.byKey(_pageKey));
      final gesture = await tester.startGesture(page);
      await gesture.moveBy(const Offset(20, 0));
      await gesture.moveBy(const Offset(20, 20));
      await gesture.up();
      await tester.pump();

      final layer = activeLayerOf(container);
      expect(layer.elementCount, 1);

      final stroke = layer.elements.single as Stroke;
      expect(stroke.points.length, greaterThan(1));
      expect(stroke.baseWidth, const Brush().baseWidth);
      expect(stroke.colorRGBA, kDefaultBrushColorRGBA);
      expect(stroke.toolId, ToolId.pen);
    });

    testWidgets('a committed stroke takes the current brush', (tester) async {
      final container = await pumpCanvas(tester);
      container.read(brushProvider.notifier)
        ..setColor(0x1E88E5FF)
        ..setWidth(23);
      await tester.pump();

      final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(_pageKey)),
      );
      await gesture.moveBy(const Offset(20, 20));
      await gesture.up();
      await tester.pump();

      final stroke = activeLayerOf(container).elements.single as Stroke;
      expect(stroke.colorRGBA, 0x1E88E5FF);
      expect(stroke.baseWidth, 23);
    });

    testWidgets('the eraser tool commits an eraser stroke', (tester) async {
      final container = await pumpCanvas(tester);
      container.read(toolProvider.notifier).select(Tool.eraser);
      await tester.pump();

      final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(_pageKey)),
      );
      await gesture.moveBy(const Offset(20, 20));
      await gesture.up();
      await tester.pump();

      final stroke = activeLayerOf(container).elements.single as Stroke;
      expect(stroke.toolId, ToolId.eraser);
      expect(stroke.isEraser, isTrue);
    });

    testWidgets('the live stroke carries the active tool', (tester) async {
      final container = await pumpCanvas(tester);
      container.read(toolProvider.notifier).select(Tool.eraser);
      await tester.pump();

      final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(_pageKey)),
      );
      await tester.pump();

      expect(painterOf(tester).liveStroke!.isEraser, isTrue);
      expect(
        painterOf(tester).layers.single.id,
        container.read(activeSessionProvider).activeLayerId,
      );

      await gesture.up();
      await tester.pump();
    });

    testWidgets('the live stroke previews the current brush', (tester) async {
      final container = await pumpCanvas(tester);
      container.read(brushProvider.notifier).setWidth(31);
      await tester.pump();

      final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(_pageKey)),
      );
      await tester.pump();

      expect(painterOf(tester).liveStroke!.baseWidth, 31);

      await gesture.up();
      await tester.pump();
    });

    testWidgets('the committed stroke holds document-space points', (
      tester,
    ) async {
      final container = await pumpCanvas(tester);
      final pageRect = tester.getRect(find.byKey(_pageKey));

      final gesture = await tester.startGesture(pageRect.topLeft);
      await gesture.moveTo(pageRect.center);
      await gesture.up();
      await tester.pump();

      final stroke = activeLayerOf(container).elements.single as Stroke;
      expect(stroke.points.first.x, closeTo(0, 0.01));
      expect(stroke.points.last.x, closeTo(960, 0.5));
      expect(stroke.points.last.y, closeTo(540, 0.5));
    });

    testWidgets('each drag commits its own stroke', (tester) async {
      final container = await pumpCanvas(tester);
      final page = tester.getCenter(find.byKey(_pageKey));

      for (var i = 0; i < 3; i++) {
        final gesture = await tester.startGesture(page + Offset(i * 5, 0));
        await gesture.moveBy(const Offset(10, 10));
        await gesture.up();
        await tester.pump();
      }

      expect(activeLayerOf(container).elementCount, 3);
    });

    testWidgets('committed strokes get distinct ids', (tester) async {
      final container = await pumpCanvas(tester);
      final page = tester.getCenter(find.byKey(_pageKey));

      for (var i = 0; i < 2; i++) {
        final gesture = await tester.startGesture(page);
        await gesture.moveBy(const Offset(10, 0));
        await gesture.up();
        await tester.pump();
      }

      final ids = {for (final e in activeLayerOf(container).elements) e.id};
      expect(ids, hasLength(2));
    });

    testWidgets('a tap commits a single-point stroke', (tester) async {
      final container = await pumpCanvas(tester);
      await tester.tapAt(tester.getCenter(find.byKey(_pageKey)));
      await tester.pump();

      final stroke = activeLayerOf(container).elements.single as Stroke;
      // The pointer-up sample coincides with the down sample and is thinned
      // away, leaving one point — which still paints as a dot.
      expect(stroke.points, hasLength(1));
    });

    testWidgets('sub-threshold jitter does not accumulate points', (
      tester,
    ) async {
      final container = await pumpCanvas(tester);
      final page = tester.getCenter(find.byKey(_pageKey));

      final gesture = await tester.startGesture(page);
      // The page is drawn at ~0.61 scale, so each 0.2px screen step is ~0.33
      // document px — well under the 1.5px floor. Only every fifth step or so
      // survives.
      const rawSamples = 20;
      for (var i = 0; i < rawSamples; i++) {
        await gesture.moveBy(const Offset(0.2, 0));
        await tester.pump();
      }
      await gesture.up();
      await tester.pump();

      final stroke = activeLayerOf(container).elements.single as Stroke;
      expect(stroke.points.length, greaterThan(1));

      // Roughly one raw point in five survives thinning; each surviving point
      // then contributes kSmoothingSamples interpolated points. Without
      // thinning all 20 samples would survive, giving 3 + 4*19 = 79 points.
      const unthinned = 3 + kSmoothingSamples * (rawSamples + 1 - 2);
      expect(stroke.points.length, lessThan(unthinned ~/ 3));
    });

    testWidgets('a strong stabilizer suppresses tremor into fewer points', (
      tester,
    ) async {
      final container = await pumpCanvas(tester);
      final page = tester.getCenter(find.byKey(_pageKey));

      Future<int> drawTremor() async {
        final gesture = await tester.startGesture(page);
        for (var i = 0; i < 24; i++) {
          await gesture.moveBy(Offset(3, i.isEven ? 3 : -3));
          await tester.pump();
        }
        await gesture.up();
        await tester.pump();
        return (activeLayerOf(container).elements.last as Stroke).points.length;
      }

      final unstabilized = await drawTremor();

      container.read(stabilizerStrengthProvider.notifier).set(10);
      await tester.pump();
      final stabilized = await drawTremor();

      expect(stabilized, lessThan(unstabilized));
    });

    testWidgets('a stabilized stroke still ends under the cursor', (
      tester,
    ) async {
      final container = await pumpCanvas(tester);
      container.read(stabilizerStrengthProvider.notifier).set(8);
      await tester.pump();

      final pageRect = tester.getRect(find.byKey(_pageKey));
      final gesture = await tester.startGesture(pageRect.topLeft);
      await gesture.moveTo(pageRect.center);
      await gesture.up();
      await tester.pump();

      // finish() snaps the anchor to the cursor, so the last point is the
      // release position rather than a string's length behind it.
      final stroke = activeLayerOf(container).elements.single as Stroke;
      expect(stroke.points.last.x, closeTo(960, 1));
      expect(stroke.points.last.y, closeTo(540, 1));
    });

    testWidgets('a cancelled stroke commits nothing', (tester) async {
      final container = await pumpCanvas(tester);

      final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(_pageKey)),
      );
      await gesture.moveBy(const Offset(10, 10));
      await gesture.cancel();
      await tester.pump();

      expect(documentOf(container).elementCount, 0);
      expect(livePointsOf(tester), isEmpty);
    });

    testWidgets('a stroke lands on the active layer, not the topmost', (
      tester,
    ) async {
      final container = await pumpCanvas(tester);
      final notifier = container.read(sessionsProvider.notifier)
        ..openSession(
          SkdDocument(
            canvasWidth: 1920,
            canvasHeight: 1080,
            layers: [
              Layer(id: 'lo', name: 'Lo'),
              Layer(id: 'hi', name: 'Hi'),
            ],
          ),
        )
        ..setActiveLayer('lo');
      await tester.pump();

      final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(_pageKey)),
      );
      await gesture.moveBy(const Offset(10, 10));
      await gesture.up();
      await tester.pump();

      final doc = documentOf(container);
      expect(doc.layerById('lo')!.elementCount, 1);
      expect(doc.layerById('hi')!.elementCount, 0);
      expect(notifier, isNotNull);
    });

    testWidgets('a second pointer does not commit a second stroke', (
      tester,
    ) async {
      final container = await pumpCanvas(tester);
      final page = tester.getCenter(find.byKey(_pageKey));

      final first = await tester.startGesture(page, pointer: 1);
      final second = await tester.startGesture(
        page + const Offset(20, 20),
        pointer: 2,
      );
      await second.moveBy(const Offset(50, 50));
      await first.moveBy(const Offset(5, 0));
      await second.up();
      await first.up();
      await tester.pump();

      expect(activeLayerOf(container).elementCount, 1);
    });

    testWidgets('committed strokes stay drawn after the pointer lifts', (
      tester,
    ) async {
      final container = await pumpCanvas(tester);

      final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(_pageKey)),
      );
      await gesture.moveBy(const Offset(30, 30));
      await gesture.up();
      await tester.pump();

      // The live stroke is gone, but the document keeps it.
      expect(livePointsOf(tester), isEmpty);
      expect(activeLayerOf(container).elementCount, 1);
    });
  });

  group('incremental repainting', () {
    /// Puts a layer below and above the active one, so all three boundaries
    /// exist and can be watched independently.
    Future<ProviderContainer> pumpThreeLayers(WidgetTester tester) async {
      final container = await pumpCanvas(tester);
      container.read(sessionsProvider.notifier)
        ..openSession(
          SkdDocument(
            canvasWidth: 1920,
            canvasHeight: 1080,
            layers: [
              Layer(id: 'bottom', name: 'bottom'),
              Layer(id: 'middle', name: 'middle'),
              Layer(id: 'top', name: 'top'),
            ],
          ),
        )
        ..setActiveLayer('middle');
      await tester.pump();
      return container;
    }

    testWidgets('the stack is split into three repaint boundaries', (
      tester,
    ) async {
      await pumpThreeLayers(tester);

      final labels = tester
          .widgetList<CustomPaint>(find.byType(CustomPaint))
          .map((p) => p.painter)
          .whereType<LayerStackPainter>()
          .map((p) => p.debugLabel)
          .toSet();

      expect(labels, containsAll(['below', 'active', 'above']));
    });

    testWidgets('the active slice holds only the active layer', (tester) async {
      await pumpThreeLayers(tester);
      expect(painterOf(tester).layers.single.id, 'middle');
    });

    testWidgets('only the active layer repaints while drawing', (tester) async {
      await pumpThreeLayers(tester);
      final page = tester.getCenter(find.byKey(_pageKey));

      LayerStackPainter.resetPaintCounts();

      final gesture = await tester.startGesture(page);
      for (var i = 0; i < 12; i++) {
        await gesture.moveBy(const Offset(14, 6));
        await tester.pump();
      }

      final counts = LayerStackPainter.paintCounts;
      expect(
        counts['active'],
        greaterThan(1),
        reason: 'the live stroke must repaint its own layer',
      );
      expect(
        counts['below'] ?? 0,
        lessThanOrEqualTo(1),
        reason: 'layers beneath the stroke must not re-rasterize',
      );
      expect(counts['above'] ?? 0, lessThanOrEqualTo(1));

      await gesture.up();
      await tester.pump();
    });

    testWidgets('a committed stroke does not repaint the other slices', (
      tester,
    ) async {
      await pumpThreeLayers(tester);
      final page = tester.getCenter(find.byKey(_pageKey));

      final warmUp = await tester.startGesture(page);
      await warmUp.moveBy(const Offset(20, 20));
      await warmUp.up();
      await tester.pump();

      LayerStackPainter.resetPaintCounts();

      final gesture = await tester.startGesture(page + const Offset(0, 40));
      await gesture.moveBy(const Offset(20, 20));
      await gesture.up();
      await tester.pump();

      expect(LayerStackPainter.paintCounts['below'] ?? 0, 0);
      expect(LayerStackPainter.paintCounts['above'] ?? 0, 0);
    });

    testWidgets('the live stroke paints into the active slice, not on top', (
      tester,
    ) async {
      await pumpThreeLayers(tester);

      final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(_pageKey)),
      );
      await tester.pump();

      final all = tester
          .widgetList<CustomPaint>(find.byType(CustomPaint))
          .map((p) => p.painter)
          .whereType<LayerStackPainter>();

      for (final painter in all) {
        if (painter.debugLabel == 'active') {
          expect(painter.liveStroke, isNotNull);
        } else {
          expect(painter.liveStroke, isNull);
        }
      }

      await gesture.up();
      await tester.pump();
    });
  });
}
