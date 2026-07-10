import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inkpad/domain/commands/commands.dart';
import 'package:inkpad/domain/models/models.dart';
import 'package:inkpad/state/state.dart';
import 'package:inkpad/ui/selection_overlay.dart';
import 'package:inkpad/ui/ui.dart';

const _pageKey = Key('canvas-page');

Future<ProviderContainer> pumpShell(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(1100, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final container = ProviderContainer.test();
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: AppShell()),
    ),
  );
  await tester.pump();
  return container;
}

AddElementCommand addTo(ProviderContainer c, CanvasElement element) =>
    AddElementCommand(
      layerId: c.read(activeSessionProvider).activeLayer.id,
      element: element,
    );

/// Adds [element] to the document and selects it, bypassing the pointer.
void place(ProviderContainer c, CanvasElement element) {
  c.read(toolProvider.notifier).select(Tool.select);
  final sessions = c.read(sessionsProvider.notifier)
    ..run(addTo(c, element))
    ..setSelection({element.id});
  expect(sessions.state.activeSession.selection, {element.id});
}

T only<T extends CanvasElement>(ProviderContainer c) => c
    .read(activeDocumentProvider)
    .layers
    .expand((l) => l.elements)
    .whereType<T>()
    .single;

/// Drags the handle sitting at [handle] on the selection box by [by].
Future<void> dragHandle(
  WidgetTester tester,
  ProviderContainer c,
  Handle handle,
  Offset by,
) async {
  final origin = tester.getRect(find.byKey(_pageKey)).topLeft;
  final box = c.read(activeSessionProvider).selectionBounds!;
  final at = handlePosition(handle, box, c.read(pageScaleProvider));
  final gesture = await tester.startGesture(origin + at);
  // Several frames, as a real drag would deliver.
  for (var i = 1; i <= 4; i++) {
    await gesture.moveTo(origin + at + by * (i / 4));
    await tester.pump();
  }
  await gesture.up();
  await tester.pumpAndSettle();
}

TextElement textAt({double w = 200, double h = 80, double rotation = 0}) =>
    TextElement.plain(
      id: 't',
      x: 100,
      y: 100,
      w: w,
      h: h,
      text: 'the quick brown fox jumps over the lazy dog',
    ).copyWith(fontSize: 20, rotation: rotation);

void main() {
  setUp(() => TestWidgetsFlutterBinding.ensureInitialized());

  group('10.6 resizeBox geometry', () {
    const box = Bounds(left: 100, top: 100, right: 300, bottom: 180);

    test('the right handle moves only the right edge', () {
      final next = resizeBox(box, Handle.right, const Offset(400, 999));
      expect(next, const Bounds(left: 100, top: 100, right: 400, bottom: 180));
    });

    test('the left handle moves only the left edge', () {
      final next = resizeBox(box, Handle.left, const Offset(40, 0));
      expect(next, const Bounds(left: 40, top: 100, right: 300, bottom: 180));
    });

    test('the bottom handle moves only the bottom edge', () {
      final next = resizeBox(box, Handle.bottom, const Offset(0, 500));
      expect(next, const Bounds(left: 100, top: 100, right: 300, bottom: 500));
    });

    test('an edge cannot be dragged through its opposite', () {
      final next = resizeBox(box, Handle.right, const Offset(-500, 0));
      expect(next.left, 100);
      expect(next.width, kMinBoxSize);
    });

    test('a corner is left to the uniform scale path', () {
      expect(resizeBox(box, Handle.topLeft, const Offset(0, 0)), box);
    });
  });

  group('10.6 canResizeBox', () {
    test('an unrotated text box and shape qualify', () {
      expect(canResizeBox(textAt()), isTrue);
      expect(
        canResizeBox(
          const Shape(
            id: 's',
            type: ShapeType.rectangle,
            x: 0,
            y: 0,
            w: 10,
            h: 10,
            strokeColorRGBA: 0,
            strokeWidth: 1,
          ),
        ),
        isTrue,
      );
    });

    test('a rotated element does not: its bounds are only a hull', () {
      expect(canResizeBox(textAt(rotation: 0.4)), isFalse);
    });

    test('a stroke has no box', () {
      expect(
        canResizeBox(Stroke(id: 's', colorRGBA: 0, baseWidth: 1)),
        isFalse,
      );
      expect(
        () => elementWithBox(
          Stroke(id: 's', colorRGBA: 0, baseWidth: 1),
          const Bounds(left: 0, top: 0, right: 1, bottom: 1),
        ),
        throwsArgumentError,
      );
    });
  });

  group('10.6 elementWithBox keeps the style', () {
    test('a text element keeps its font size, so the text rewraps', () {
      final wide = elementWithBox(
        textAt(),
        const Bounds(left: 100, top: 100, right: 500, bottom: 180),
      );
      expect((wide as TextElement).fontSize, 20);
      expect(wide.w, 400);
      expect(wide.h, 80);
    });

    test('a corner scale magnifies the font instead', () {
      final bigger = textAt().scaled(2, originX: 100, originY: 100);
      expect(bigger.fontSize, 40);
      expect(bigger.w, 400);
    });

    test('a shape keeps its stroke width', () {
      const shape = Shape(
        id: 's',
        type: ShapeType.rectangle,
        x: 0,
        y: 0,
        w: 10,
        h: 10,
        strokeColorRGBA: 0,
        strokeWidth: 3,
      );
      final wide = elementWithBox(
        shape,
        const Bounds(left: 0, top: 0, right: 40, bottom: 10),
      );
      expect((wide as Shape).strokeWidth, 3);
      expect(wide.w, 40);
      expect(wide.h, 10);
    });
  });

  group('10.6 dragging a side handle', () {
    testWidgets('widens the text box without magnifying the text', (
      tester,
    ) async {
      final container = await pumpShell(tester);
      place(container, textAt());
      await tester.pump();

      await dragHandle(tester, container, Handle.right, const Offset(120, 0));

      final after = only<TextElement>(container);
      expect(after.w, closeTo(320, 1));
      expect(after.h, 80, reason: 'the other axis is untouched');
      expect(after.fontSize, 20, reason: 'the text rewraps, it does not grow');
      expect(after.x, 100);
    });

    testWidgets('a corner handle still scales the font', (tester) async {
      final container = await pumpShell(tester);
      place(container, textAt());
      await tester.pump();

      await dragHandle(
        tester,
        container,
        Handle.bottomRight,
        const Offset(100, 40),
      );

      final after = only<TextElement>(container);
      expect(after.fontSize, greaterThan(20));
    });

    testWidgets('the whole drag is one undo entry, and undo is exact', (
      tester,
    ) async {
      final container = await pumpShell(tester);
      final before = textAt();
      place(container, before);
      await tester.pump();

      await dragHandle(tester, container, Handle.bottom, const Offset(0, 60));
      expect(only<TextElement>(container).h, closeTo(140, 1));

      final session = container.read(activeSessionProvider);
      expect(session.commands.undoStack, hasLength(2)); // add + resize

      container.read(sessionsProvider.notifier).undo();
      await tester.pump();
      expect(only<TextElement>(container), before);
    });

    testWidgets('a rotated box falls back to a uniform scale', (tester) async {
      final container = await pumpShell(tester);
      place(container, textAt(rotation: 0.4));
      await tester.pump();

      await dragHandle(tester, container, Handle.right, const Offset(80, 0));

      final after = only<TextElement>(container);
      expect(after.fontSize, greaterThan(20));
    });

    testWidgets('a side handle over a multi-selection scales uniformly', (
      tester,
    ) async {
      final container = await pumpShell(tester);
      container.read(toolProvider.notifier).select(Tool.select);
      final sessions = container.read(sessionsProvider.notifier)
        ..run(addTo(container, textAt()))
        ..run(
          addTo(
            container,
            const Shape(
              id: 's',
              type: ShapeType.rectangle,
              x: 400,
              y: 100,
              w: 60,
              h: 60,
              strokeColorRGBA: 0xFF000000,
              strokeWidth: 2,
            ),
          ),
        )
        ..setSelection({'t', 's'});
      await tester.pump();

      await dragHandle(tester, container, Handle.right, const Offset(60, 0));

      // Uniform: the font came along for the ride.
      expect(only<TextElement>(container).fontSize, greaterThan(20));
      expect(sessions.state.activeSession.canUndo, isTrue);
    });
  });
}
