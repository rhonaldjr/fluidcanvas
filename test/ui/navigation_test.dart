import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inkpad/domain/commands/commands.dart';
import 'package:inkpad/domain/models/models.dart';
import 'package:inkpad/engine/view_transform.dart';
import 'package:inkpad/state/state.dart';
import 'package:inkpad/ui/ui.dart';

import '../support/test_container.dart';

const _pageKey = Key('canvas-page');
const _navKey = Key('canvas-navigation');

Future<ProviderContainer> pumpShell(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(1200, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  final container = testContainer();
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: AppShell()),
    ),
  );
  await tester.pump();
  return container;
}

DocumentSession session(ProviderContainer c) => c.read(activeSessionProvider);
ViewTransform view(ProviderContainer c) => session(c).view;
List<CanvasElement> elements(ProviderContainer c) =>
    c.read(activeDocumentProvider).layers.expand((l) => l.elements).toList();

/// Freezes the canvas size, so fit-to-window cannot resize the document while
/// a navigation gesture is being tested.
void freezeCanvas(ProviderContainer c) =>
    c.read(sessionsProvider.notifier).setFitToWindow(false);

/// Freezes the canvas at [w] x [h] document pixels.
///
/// Zoomed in far enough the page is larger than the viewport and its corner is
/// off-screen, where nothing can be tapped. A canvas sized so the whole page
/// still fits is what lets a test aim at a document coordinate.
void setCanvas(ProviderContainer c, int w, int h) {
  c.read(sessionsProvider.notifier)
    ..setFitToWindow(false)
    ..resizeCanvas(w, h);
}

/// Sends a scroll at [at] inside the canvas, optionally with Ctrl held.
Future<void> scrollAt(
  WidgetTester tester,
  Offset at,
  Offset delta, {
  bool ctrl = false,
}) async {
  if (ctrl) await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  final origin = tester.getTopLeft(find.byKey(_navKey));
  await tester.sendEventToBinding(
    PointerScrollEvent(position: origin + at, scrollDelta: delta),
  );
  await tester.pump();
  if (ctrl) await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
}

void main() {
  group('14.1 zoom', () {
    testWidgets('a new document fits its viewport', (tester) async {
      final container = await pumpShell(tester);
      expect(view(container).fitted, isTrue);
      expect(container.read(pageScaleProvider), 1);
    });

    testWidgets('Ctrl+scroll up zooms in, about the cursor', (tester) async {
      final container = await pumpShell(tester);
      freezeCanvas(container);
      await tester.pump();

      await scrollAt(
        tester,
        const Offset(300, 300),
        const Offset(0, -50),
        ctrl: true,
      );

      expect(view(container).fitted, isFalse);
      expect(view(container).zoom, greaterThan(1));
      expect(container.read(pageScaleProvider), greaterThan(1));
    });

    testWidgets('Ctrl+scroll down zooms out', (tester) async {
      final container = await pumpShell(tester);
      freezeCanvas(container);
      await tester.pump();

      await scrollAt(
        tester,
        const Offset(300, 300),
        const Offset(0, 50),
        ctrl: true,
      );

      expect(view(container).zoom, lessThan(1));
    });

    testWidgets('zoom stops at 800% and at 10%', (tester) async {
      final container = await pumpShell(tester);
      freezeCanvas(container);
      await tester.pump();

      for (var i = 0; i < 60; i++) {
        await scrollAt(
          tester,
          const Offset(300, 300),
          const Offset(0, -50),
          ctrl: true,
        );
      }
      expect(view(container).zoom, kMaxZoom);

      for (var i = 0; i < 120; i++) {
        await scrollAt(
          tester,
          const Offset(300, 300),
          const Offset(0, 50),
          ctrl: true,
        );
      }
      expect(view(container).zoom, kMinZoom);
    });

    testWidgets('a plain scroll pans instead of zooming', (tester) async {
      final container = await pumpShell(tester);
      freezeCanvas(container);
      await tester.pump();

      await scrollAt(tester, const Offset(300, 300), const Offset(0, 40));

      expect(view(container).zoom, 1);
      expect(view(container).panY, -40);
    });

    testWidgets('Ctrl+0 puts the whole page back', (tester) async {
      final container = await pumpShell(tester);
      freezeCanvas(container);
      await tester.pump();
      await scrollAt(
        tester,
        const Offset(200, 200),
        const Offset(0, -50),
        ctrl: true,
      );
      expect(view(container).fitted, isFalse);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.digit0);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();

      expect(view(container), ViewTransform.initial);
    });

    testWidgets('Ctrl+= and Ctrl+- zoom about the centre', (tester) async {
      final container = await pumpShell(tester);
      freezeCanvas(container);
      await tester.pump();

      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.equal);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();

      expect(view(container).zoom, closeTo(kZoomStep, 1e-9));
      expect(view(container).panX, closeTo(0, 1e-6), reason: 'stays centred');

      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.minus);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();

      expect(view(container).zoom, closeTo(1, 1e-9));
    });

    testWidgets('the status bar shows the zoom, and clicking it resets', (
      tester,
    ) async {
      final container = await pumpShell(tester);
      freezeCanvas(container);
      await tester.pump();
      await scrollAt(
        tester,
        const Offset(300, 300),
        const Offset(0, -50),
        ctrl: true,
      );
      await tester.pump();
      expect(find.text('110%'), findsOneWidget);

      await tester.tap(find.byKey(const Key('status-scale')));
      await tester.pumpAndSettle();

      expect(view(container).fitted, isTrue);
      expect(find.text('100%'), findsOneWidget);
    });

    testWidgets('zoom never touches the document, nor the undo stack', (
      tester,
    ) async {
      final container = await pumpShell(tester);
      freezeCanvas(container);
      await tester.pump();
      final before = container.read(activeDocumentProvider);

      await scrollAt(
        tester,
        const Offset(300, 300),
        const Offset(0, -50),
        ctrl: true,
      );

      expect(container.read(activeDocumentProvider), same(before));
      expect(session(container).canUndo, isFalse);
      expect(session(container).isDirty, isFalse);
    });

    testWidgets('each tab keeps its own zoom and scroll', (tester) async {
      final container = await pumpShell(tester);
      final sessions = container.read(sessionsProvider.notifier);
      freezeCanvas(container);
      await tester.pump();

      await scrollAt(
        tester,
        const Offset(300, 300),
        const Offset(0, -50),
        ctrl: true,
      );
      final zoomed = view(container);
      expect(zoomed.fitted, isFalse);

      sessions.openBlankSession();
      await tester.pump();
      expect(view(container), ViewTransform.initial, reason: 'a fresh view');

      sessions.activateAt(0);
      await tester.pump();
      expect(view(container), zoomed);
    });
  });

  group('14.1 drawing and hit-testing at every zoom', () {
    testWidgets('a stroke drawn at 800% lands where the pointer was', (
      tester,
    ) async {
      final container = await pumpShell(tester);
      // The smallest canvas is 320 x 200, so at 8x the page is always larger
      // than the viewport and its corner is off-screen. Aim at a point that is
      // on screen, and derive the document coordinate it must map to.
      setCanvas(container, kMinCanvasWidth, kMinCanvasHeight);
      container
          .read(sessionsProvider.notifier)
          .setView(const ViewTransform(zoom: 8, fitted: false));
      await tester.pump();
      expect(container.read(pageScaleProvider), 8);

      final page = tester.getRect(find.byKey(_pageKey));
      final at = tester.getCenter(find.byKey(_navKey));
      final expected = (at - page.topLeft) / 8;

      final gesture = await tester.startGesture(at);
      await gesture.moveBy(const Offset(80, 0));
      await gesture.up();
      await tester.pumpAndSettle();

      final stroke = elements(container).single as Stroke;
      expect(stroke.points.first.x, closeTo(expected.dx, 0.5));
      expect(stroke.points.first.y, closeTo(expected.dy, 0.5));
      // 80 screen pixels at 8x is 10 document pixels.
      expect(stroke.bounds!.width, closeTo(10, 1));
    });

    testWidgets('a stroke drawn at 10% lands where the pointer was', (
      tester,
    ) async {
      final container = await pumpShell(tester);
      freezeCanvas(container);
      container
          .read(sessionsProvider.notifier)
          .setView(const ViewTransform(zoom: 0.1, fitted: false));
      await tester.pump();

      final page = tester.getRect(find.byKey(_pageKey));
      final gesture = await tester.startGesture(
        page.topLeft + const Offset(10, 10),
      );
      await gesture.moveBy(const Offset(20, 0));
      await gesture.up();
      await tester.pumpAndSettle();

      final stroke = elements(container).single as Stroke;
      expect(stroke.points.first.x, closeTo(100, 5));
      expect(stroke.bounds!.width, closeTo(200, 20));
    });

    testWidgets('a shape is selected by clicking it at 400%', (tester) async {
      final container = await pumpShell(tester);
      setCanvas(container, 200, 150);
      final sessions = container.read(sessionsProvider.notifier);
      sessions.run(
        AddElementCommand(
          layerId: session(container).activeLayer.id,
          element: const Shape(
            id: 'r',
            type: ShapeType.rectangle,
            x: 20,
            y: 20,
            w: 60,
            h: 40,
            strokeColorRGBA: 0xFF000000,
            strokeWidth: 2,
          ),
        ),
      );
      sessions.setView(const ViewTransform(zoom: 4, fitted: false));
      container.read(toolProvider.notifier).select(Tool.select);
      await tester.pump();

      // The rectangle's top edge, in screen pixels: (20,20) doc * 4.
      final page = tester.getRect(find.byKey(_pageKey));
      await tester.tapAt(page.topLeft + const Offset(200, 80));
      await tester.pumpAndSettle();

      expect(session(container).selection, {'r'});
    });

    testWidgets('the same shape is selected at 10%', (tester) async {
      final container = await pumpShell(tester);
      setCanvas(container, 2000, 1600);
      final sessions = container.read(sessionsProvider.notifier);
      sessions.run(
        AddElementCommand(
          layerId: session(container).activeLayer.id,
          element: const Shape(
            id: 'r',
            type: ShapeType.rectangle,
            x: 200,
            y: 200,
            w: 600,
            h: 400,
            strokeColorRGBA: 0xFF000000,
            strokeWidth: 2,
          ),
        ),
      );
      sessions.setView(const ViewTransform(zoom: 0.1, fitted: false));
      container.read(toolProvider.notifier).select(Tool.select);
      await tester.pump();

      // The left edge at (200, 400) doc is (20, 40) on screen.
      final page = tester.getRect(find.byKey(_pageKey));
      await tester.tapAt(page.topLeft + const Offset(20, 40));
      await tester.pumpAndSettle();

      expect(session(container).selection, {'r'});
    });

    testWidgets('drawing still works after panning the page', (tester) async {
      final container = await pumpShell(tester);
      freezeCanvas(container);
      container.read(sessionsProvider.notifier).panBy(120, -60);
      await tester.pump();

      final page = tester.getRect(find.byKey(_pageKey));
      final gesture = await tester.startGesture(
        page.topLeft + const Offset(50, 50),
      );
      await gesture.moveBy(const Offset(30, 0));
      await gesture.up();
      await tester.pumpAndSettle();

      final stroke = elements(container).single as Stroke;
      expect(stroke.points.first.x, closeTo(50, 1));
      expect(stroke.points.first.y, closeTo(50, 1));
    });
  });

  group('14.2 pan', () {
    testWidgets('a middle-drag pans the page and draws nothing', (
      tester,
    ) async {
      final container = await pumpShell(tester);
      freezeCanvas(container);
      await tester.pump();

      final page = tester.getCenter(find.byKey(_pageKey));
      final gesture = await tester.startGesture(
        page,
        buttons: kMiddleMouseButton,
      );
      await gesture.moveBy(const Offset(40, 25));
      await gesture.up();
      await tester.pumpAndSettle();

      expect(view(container).panX, 40);
      expect(view(container).panY, 25);
      expect(elements(container), isEmpty);
    });

    testWidgets('a space-drag pans and leaves no stroke behind', (
      tester,
    ) async {
      final container = await pumpShell(tester);
      freezeCanvas(container);
      await tester.pump();

      await tester.sendKeyDownEvent(LogicalKeyboardKey.space);
      final page = tester.getCenter(find.byKey(_pageKey));
      final gesture = await tester.startGesture(page);
      await gesture.moveBy(const Offset(-30, 15));
      await gesture.up();
      await tester.pumpAndSettle();
      await tester.sendKeyUpEvent(LogicalKeyboardKey.space);

      expect(view(container).panX, -30);
      expect(elements(container), isEmpty);
    });

    testWidgets('without space, a left-drag draws as it always did', (
      tester,
    ) async {
      final container = await pumpShell(tester);
      freezeCanvas(container);
      await tester.pump();

      final page = tester.getCenter(find.byKey(_pageKey));
      final gesture = await tester.startGesture(page);
      await gesture.moveBy(const Offset(-30, 15));
      await gesture.up();
      await tester.pumpAndSettle();

      expect(view(container).isPanned, isFalse);
      expect(elements(container), hasLength(1));
    });

    testWidgets('the cursor becomes a hand while space is held', (
      tester,
    ) async {
      await pumpShell(tester);

      final region = tester.widget<MouseRegion>(
        find
            .ancestor(
              of: find.byKey(_navKey),
              matching: find.byType(MouseRegion),
            )
            .first,
      );
      expect(region.cursor, MouseCursor.defer);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.space);
      await tester.pump();

      final held = tester.widget<MouseRegion>(
        find
            .ancestor(
              of: find.byKey(_navKey),
              matching: find.byType(MouseRegion),
            )
            .first,
      );
      expect(held.cursor, SystemMouseCursors.grab);

      await tester.sendKeyUpEvent(LogicalKeyboardKey.space);
      await tester.pump();
    });

    testWidgets('panning is not undoable and does not dirty the document', (
      tester,
    ) async {
      final container = await pumpShell(tester);
      freezeCanvas(container);
      await tester.pump();

      container.read(sessionsProvider.notifier).panBy(10, 10);
      await tester.pump();

      expect(session(container).isDirty, isFalse);
      expect(session(container).canUndo, isFalse);
    });
  });

  group('14.3 trackpad gestures', () {
    Future<void> panZoom(
      WidgetTester tester, {
      Offset pan = Offset.zero,
      double scale = 1,
    }) async {
      final origin = tester.getTopLeft(find.byKey(_navKey));
      const device = 7;
      final at = origin + const Offset(300, 300);
      await tester.sendEventToBinding(
        PointerPanZoomStartEvent(pointer: device, position: at),
      );
      await tester.pump();
      await tester.sendEventToBinding(
        PointerPanZoomUpdateEvent(
          pointer: device,
          position: at,
          pan: pan,
          panDelta: pan,
          scale: scale,
        ),
      );
      await tester.pump();
      await tester.sendEventToBinding(
        PointerPanZoomEndEvent(pointer: device, position: at),
      );
      await tester.pump();
    }

    testWidgets('two-finger scroll pans', (tester) async {
      final container = await pumpShell(tester);
      freezeCanvas(container);
      await tester.pump();

      await panZoom(tester, pan: const Offset(25, -15));

      expect(view(container).panX, 25);
      expect(view(container).panY, -15);
    });

    testWidgets('a pinch zooms', (tester) async {
      final container = await pumpShell(tester);
      freezeCanvas(container);
      await tester.pump();

      await panZoom(tester, scale: 2);

      expect(view(container).zoom, closeTo(2, 1e-9));
      expect(view(container).fitted, isFalse);
    });

    testWidgets('a pinch that does not scale only pans', (tester) async {
      final container = await pumpShell(tester);
      freezeCanvas(container);
      await tester.pump();

      await panZoom(tester, pan: const Offset(10, 0));

      expect(view(container).zoom, 1);
      expect(view(container).panX, 10);
    });
  });
}
