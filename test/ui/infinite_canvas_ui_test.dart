import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inkpad/domain/models/models.dart';
import 'package:inkpad/state/state.dart';
import 'package:inkpad/ui/ui.dart';

import '../support/test_container.dart';

const _pageKey = Key('canvas-page');

Future<ProviderContainer> pumpInfinite(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(1000, 800));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  final container = testContainer();
  // Replace the single default session with an infinite one.
  container
      .read(sessionsProvider.notifier)
      .openSession(
        SkdDocument.newDefault(canvasMode: CanvasMode.infinite),
        id: 'inf',
      );
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: AppShell()),
    ),
  );
  await tester.pump();
  return container;
}

List<CanvasElement> elements(ProviderContainer c) =>
    c.read(activeDocumentProvider).layers.expand((l) => l.elements).toList();

void main() {
  testWidgets('the active document is the infinite one', (tester) async {
    final container = await pumpInfinite(tester);
    expect(container.read(activeDocumentProvider).isInfinite, isTrue);
  });

  testWidgets('the canvas fills the viewport, with no fixed page', (
    tester,
  ) async {
    await pumpInfinite(tester);
    final page = tester.getSize(find.byKey(_pageKey));
    // The page is the whole canvas area (viewport minus tool strip and panel),
    // not a 1920x1080 document rendered small.
    expect(page.width, greaterThan(500));
    expect(page.height, greaterThan(500));
  });

  testWidgets('a stroke at the viewport centre lands near document origin', (
    tester,
  ) async {
    final container = await pumpInfinite(tester);
    container.read(toolProvider.notifier).select(Tool.pen);
    await tester.pump();

    // Document (0, 0) sits at the centre of the canvas box on an infinite page.
    final centre = tester.getCenter(find.byKey(_pageKey));
    final gesture = await tester.startGesture(centre);
    await gesture.moveBy(const Offset(40, 0));
    await gesture.moveBy(const Offset(0, 40));
    await gesture.up();
    await tester.pumpAndSettle();

    final stroke = elements(container).single as Stroke;
    // The first point is at the centre, i.e. near document (0, 0).
    expect(stroke.points.first.x, closeTo(0, 2));
    expect(stroke.points.first.y, closeTo(0, 2));
    // And it extends the way the drag went.
    expect(stroke.bounds!.width, closeTo(40, 4));
  });

  testWidgets('resizing the window does not resize an infinite document', (
    tester,
  ) async {
    final container = await pumpInfinite(tester);
    final before = container.read(activeDocumentProvider);

    await tester.binding.setSurfaceSize(const Size(1400, 1100));
    await tester.pump(kResizeDebounce);
    await tester.pump();

    // The document is untouched: no ResizeCanvasCommand, same canvas size.
    expect(
      container.read(activeDocumentProvider).canvasWidth,
      before.canvasWidth,
    );
    expect(container.read(activeSessionProvider).canUndo, isFalse);
  });

  testWidgets('drawing far from the origin works after panning', (
    tester,
  ) async {
    final container = await pumpInfinite(tester);
    container.read(toolProvider.notifier).select(Tool.pen);
    // Pan so document space shifts under the pointer.
    container.read(sessionsProvider.notifier).panBy(100, 60);
    await tester.pump();

    final centre = tester.getCenter(find.byKey(_pageKey));
    final gesture = await tester.startGesture(centre);
    await gesture.moveBy(const Offset(20, 0));
    await gesture.up();
    await tester.pumpAndSettle();

    // The pan moved doc origin off centre, so a stroke at the centre is at
    // negative document coordinates — the plane really is unbounded.
    final stroke = elements(container).single as Stroke;
    expect(stroke.points.first.x, lessThan(0));
  });

  group('the infinite backdrop is the paper, not a gray desk', () {
    Color backdrop(WidgetTester tester) {
      final box = tester.widget<ColoredBox>(
        find
            .descendant(
              of: find.byType(CanvasView),
              matching: find.byType(ColoredBox),
            )
            .first,
      );
      return box.color;
    }

    testWidgets('an infinite canvas fills white (the document background)', (
      tester,
    ) async {
      await pumpInfinite(tester);
      expect(backdrop(tester), const Color(0xFFFFFFFF));
    });

    testWidgets('a bounded canvas keeps its gray desk', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1000, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final container = testContainer();
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: AppShell()),
        ),
      );
      await tester.pump();
      expect(backdrop(tester), const Color(0xFF6E6E6E));
    });
  });
}
