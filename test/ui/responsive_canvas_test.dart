import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inkpad/domain/commands/commands.dart';
import 'package:inkpad/domain/models/models.dart';
import 'package:inkpad/state/state.dart';
import 'package:inkpad/ui/ui.dart';

Future<ProviderContainer> pumpCanvas(
  WidgetTester tester, {
  Size size = const Size(1000, 700),
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
  await tester.pump();
  return container;
}

SkdDocument docOf(ProviderContainer c) => c.read(activeDocumentProvider);

Future<void> resizeWindow(WidgetTester tester, Size size) async {
  await tester.binding.setSurfaceSize(size);
  await tester.pump();
}

Future<void> drawStroke(WidgetTester tester) async {
  final page = tester.getCenter(find.byKey(const Key('canvas-page')));
  final gesture = await tester.startGesture(page);
  await gesture.moveBy(const Offset(30, 20));
  await gesture.moveBy(const Offset(30, -20));
  await gesture.up();
  await tester.pump();
}

void main() {
  group('canvasSizeForViewport', () {
    test('leaves a margin on every side', () {
      expect(canvasSizeForViewport(const Size(1000, 700)), (
        width: 1000 - 64,
        height: 700 - 64,
      ));
    });

    test('never drops below the minimum', () {
      final tiny = canvasSizeForViewport(const Size(10, 10));
      expect(tiny.width, kMinCanvasWidth);
      expect(tiny.height, kMinCanvasHeight);
    });

    test('floors rather than rounding, so the page always fits', () {
      expect(canvasSizeForViewport(const Size(1000.9, 700.9)).width, 936);
    });
  });

  group('8.3 the canvas follows the window', () {
    testWidgets('a new document adopts the window size immediately', (
      tester,
    ) async {
      final container = await pumpCanvas(tester);
      final expected = canvasSizeForViewport(const Size(1000, 700));

      expect(docOf(container).canvasWidth, expected.width);
      expect(docOf(container).canvasHeight, expected.height);
    });

    testWidgets('the page is then drawn at 1:1', (tester) async {
      final container = await pumpCanvas(tester);
      final page = tester.getSize(find.byKey(const Key('canvas-page')));
      expect(page.width, docOf(container).canvasWidth.toDouble());
    });

    testWidgets('growing the window scales the strokes with it', (
      tester,
    ) async {
      final container = await pumpCanvas(tester, size: const Size(600, 500));
      await drawStroke(tester);

      final before =
          (container.read(activeSessionProvider).activeLayer.elements.single
              as Stroke);
      final oldCanvas = docOf(container);
      final widthBefore = before.baseWidth;
      final spanBefore = before.bounds!.width;

      await resizeWindow(tester, const Size(1200, 1000));
      await tester.pump(kResizeDebounce);
      await tester.pump();

      final newCanvas = docOf(container);
      // The 32px margins mean the window doubling does not double the canvas,
      // so derive the factor rather than assuming 2.
      final factor = [
        newCanvas.canvasWidth / oldCanvas.canvasWidth,
        newCanvas.canvasHeight / oldCanvas.canvasHeight,
      ].reduce((a, b) => a < b ? a : b);
      expect(factor, greaterThan(2.0));

      final after =
          (container.read(activeSessionProvider).activeLayer.elements.single
              as Stroke);
      expect(after.baseWidth, closeTo(widthBefore * factor, 1e-6));
      expect(after.bounds!.width, closeTo(spanBefore * factor, 1e-6));
    });

    testWidgets('a wider window adds blank canvas rather than stretching', (
      tester,
    ) async {
      final container = await pumpCanvas(tester, size: const Size(600, 600));
      await drawStroke(tester);
      final before =
          (container.read(activeSessionProvider).activeLayer.elements.single
              as Stroke);
      final aspectBefore = before.bounds!.width / before.bounds!.height;

      await resizeWindow(tester, const Size(1200, 600));
      await tester.pump(kResizeDebounce);
      await tester.pump();

      final after =
          (container.read(activeSessionProvider).activeLayer.elements.single
              as Stroke);
      // Uniform scale: the drawing keeps its shape, and its size (factor 1).
      expect(
        after.bounds!.width / after.bounds!.height,
        closeTo(aspectBefore, 1e-6),
      );
      expect(after.baseWidth, closeTo(before.baseWidth, 1e-6));
      expect(docOf(container).canvasWidth, 1200 - 64);
    });

    testWidgets('a collapsed window cannot shrink the canvas to nothing', (
      tester,
    ) async {
      final container = await pumpCanvas(tester);
      await resizeWindow(tester, const Size(50, 50));
      await tester.pump(kResizeDebounce);
      await tester.pump();

      expect(
        docOf(container).canvasWidth,
        greaterThanOrEqualTo(kMinCanvasWidth),
      );
      expect(
        docOf(container).canvasHeight,
        greaterThanOrEqualTo(kMinCanvasHeight),
      );
    });
  });

  group('8.4 resizes are coalesced and not undoable', () {
    testWidgets('the first fit leaves nothing on the undo stack', (
      tester,
    ) async {
      final container = await pumpCanvas(tester);
      expect(container.read(activeSessionProvider).canUndo, isFalse);
    });

    testWidgets('a window drag leaves the undo stack alone', (tester) async {
      final container = await pumpCanvas(tester);
      await drawStroke(tester);
      expect(
        container.read(activeSessionProvider).commands.undoStack,
        hasLength(1),
      );

      // One resize per frame, as a drag would.
      for (var w = 1000.0; w < 1200; w += 20) {
        await resizeWindow(tester, Size(w, 700));
      }
      await tester.pump(kResizeDebounce);
      await tester.pump();

      // The canvas followed, but undo still steps back to before the stroke,
      // not through a hundred resizes.
      expect(docOf(container).canvasWidth, greaterThan(1000 - 64));
      expect(
        container.read(activeSessionProvider).commands.undoStack,
        hasLength(1),
      );
    });

    testWidgets('mid-drag the document is untouched', (tester) async {
      final container = await pumpCanvas(tester);
      final before = docOf(container).canvasWidth;

      await resizeWindow(tester, const Size(1400, 700));
      // Before the debounce fires.
      await tester.pump(const Duration(milliseconds: 50));
      expect(docOf(container).canvasWidth, before);

      await tester.pump(kResizeDebounce);
      await tester.pump();
      expect(docOf(container).canvasWidth, greaterThan(before));
    });

    testWidgets('an explicit resizeCanvas is undoable', (tester) async {
      final container = await pumpCanvas(tester);
      container.read(sessionsProvider.notifier).resizeCanvas(800, 600);
      await tester.pump();

      expect(docOf(container).canvasWidth, 800);
      expect(container.read(activeSessionProvider).canUndo, isTrue);
    });
  });

  group('8.5 fit-to-window toggle', () {
    testWidgets('is on by default', (tester) async {
      final container = await pumpCanvas(tester);
      expect(container.read(activeSessionProvider).fitToWindow, isTrue);
    });

    testWidgets('turning it off freezes the canvas size', (tester) async {
      final container = await pumpCanvas(tester);
      final frozen = docOf(container).canvasWidth;

      container.read(sessionsProvider.notifier).setFitToWindow(false);
      await tester.pump();

      await resizeWindow(tester, const Size(1600, 900));
      await tester.pump(kResizeDebounce);
      await tester.pump();

      expect(docOf(container).canvasWidth, frozen);
    });

    testWidgets('with it off the page still scales to fit the viewport', (
      tester,
    ) async {
      final container = await pumpCanvas(tester);
      container.read(sessionsProvider.notifier).setFitToWindow(false);
      await tester.pump();

      await resizeWindow(tester, const Size(500, 400));
      await tester.pump(kResizeDebounce);
      await tester.pump();

      final page = tester.getSize(find.byKey(const Key('canvas-page')));
      expect(page.width, lessThan(docOf(container).canvasWidth));
      expect(page.width, lessThanOrEqualTo(500));
    });

    testWidgets('the preference is per session', (tester) async {
      final container = await pumpCanvas(tester);
      container.read(sessionsProvider.notifier)
        ..setFitToWindow(false)
        ..openBlankSession(id: 'second');
      await tester.pump();

      expect(container.read(activeSessionProvider).fitToWindow, isTrue);
    });
  });
}
