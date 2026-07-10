import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inkpad/domain/models/models.dart';
import 'package:inkpad/state/state.dart';
import 'package:inkpad/ui/ui.dart';

const _pageKey = Key('canvas-page');

Future<ProviderContainer> pumpShell(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(1100, 800));
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

DocumentSession session(ProviderContainer c) => c.read(activeSessionProvider);
List<CanvasElement> elements(ProviderContainer c) =>
    c.read(activeDocumentProvider).layers.expand((l) => l.elements).toList();

/// Drags on the page, in page-local pixels.
Future<void> dragOnPage(
  WidgetTester tester,
  Offset from,
  Offset to, {
  int steps = 6,
}) async {
  final origin = tester.getRect(find.byKey(_pageKey)).topLeft;
  final gesture = await tester.startGesture(origin + from);
  for (var i = 1; i <= steps; i++) {
    await gesture.moveTo(origin + from + (to - from) * (i / steps));
    await tester.pump();
  }
  await gesture.up();
  await tester.pump();
}

Future<void> tapOnPage(WidgetTester tester, Offset at) async {
  final origin = tester.getRect(find.byKey(_pageKey)).topLeft;
  await tester.tapAt(origin + at);
  await tester.pump();
}

Future<void> withKey(
  LogicalKeyboardKey key,
  Future<void> Function() body,
) async {
  await simulateKeyDownEvent(key);
  await body();
  await simulateKeyUpEvent(key);
}

/// Creates a rectangle from (40,40) to (140,100) and selects the select tool.
Future<Shape> makeRect(WidgetTester tester, ProviderContainer c) async {
  c.read(toolProvider.notifier).select(Tool.rectangle);
  await tester.pump();
  await dragOnPage(tester, const Offset(40, 40), const Offset(140, 100));
  c.read(toolProvider.notifier).select(Tool.select);
  await tester.pump();
  return elements(c).whereType<Shape>().single;
}

void main() {
  group('9.1 drag to create', () {
    testWidgets('a drag with the rectangle tool adds exactly one shape', (
      tester,
    ) async {
      final container = await pumpShell(tester);
      final shape = await makeRect(tester, container);

      expect(elements(container), hasLength(1));
      expect(shape.type, ShapeType.rectangle);
      expect(shape.w, closeTo(100, 1));
      expect(shape.h, closeTo(60, 1));
    });

    testWidgets('the committed shape is normalized', (tester) async {
      final container = await pumpShell(tester);
      container.read(toolProvider.notifier).select(Tool.ellipse);
      await tester.pump();

      // Drag up and to the left.
      await dragOnPage(tester, const Offset(200, 200), const Offset(100, 120));

      final shape = elements(container).single as Shape;
      expect(shape.w, greaterThan(0));
      expect(shape.h, greaterThan(0));
      expect(shape.x, closeTo(100, 1));
    });

    testWidgets('shift constrains to a square', (tester) async {
      final container = await pumpShell(tester);
      container.read(toolProvider.notifier).select(Tool.rectangle);
      await tester.pump();

      await withKey(LogicalKeyboardKey.shiftLeft, () async {
        await dragOnPage(tester, const Offset(40, 40), const Offset(200, 90));
      });

      final shape = elements(container).single as Shape;
      expect(shape.w, closeTo(shape.h, 0.01));
    });

    testWidgets('alt draws from the centre', (tester) async {
      final container = await pumpShell(tester);
      container.read(toolProvider.notifier).select(Tool.rectangle);
      await tester.pump();

      await withKey(LogicalKeyboardKey.altLeft, () async {
        await dragOnPage(
          tester,
          const Offset(150, 150),
          const Offset(200, 190),
        );
      });

      final shape = elements(container).single as Shape;
      expect(shape.x + shape.w / 2, closeTo(150, 1));
      expect(shape.y + shape.h / 2, closeTo(150, 1));
    });

    testWidgets('a click without a drag creates nothing', (tester) async {
      final container = await pumpShell(tester);
      container.read(toolProvider.notifier).select(Tool.diamond);
      await tester.pump();

      await tapOnPage(tester, const Offset(100, 100));
      expect(elements(container), isEmpty);
    });

    testWidgets('creating a shape is undoable', (tester) async {
      final container = await pumpShell(tester);
      await makeRect(tester, container);
      container.read(sessionsProvider.notifier).undo();
      await tester.pump();
      expect(elements(container), isEmpty);
    });
  });

  group('9.3 selection', () {
    testWidgets('clicking a shape selects it', (tester) async {
      final container = await pumpShell(tester);
      await makeRect(tester, container);

      // Its outline, not its hollow middle.
      await tapOnPage(tester, const Offset(40, 70));
      expect(session(container).selection, hasLength(1));
    });

    testWidgets('clicking empty canvas clears the selection', (tester) async {
      final container = await pumpShell(tester);
      await makeRect(tester, container);
      await tapOnPage(tester, const Offset(40, 70));
      expect(session(container).selection, isNotEmpty);

      await tapOnPage(tester, const Offset(400, 400));
      expect(session(container).selection, isEmpty);
    });

    testWidgets('a marquee selects what it wholly contains', (tester) async {
      final container = await pumpShell(tester);
      await makeRect(tester, container);

      await dragOnPage(tester, const Offset(20, 20), const Offset(300, 300));
      expect(session(container).selection, hasLength(1));
    });

    testWidgets('a marquee that only clips a shape selects nothing', (
      tester,
    ) async {
      final container = await pumpShell(tester);
      await makeRect(tester, container);

      await dragOnPage(tester, const Offset(20, 20), const Offset(80, 80));
      expect(session(container).selection, isEmpty);
    });

    testWidgets('selecting is not undoable', (tester) async {
      final container = await pumpShell(tester);
      await makeRect(tester, container);
      final depth = session(container).commands.undoStack.length;

      await tapOnPage(tester, const Offset(40, 70));
      expect(session(container).commands.undoStack, hasLength(depth));
    });

    testWidgets('Ctrl+A selects everything, Escape clears', (tester) async {
      final container = await pumpShell(tester);
      await makeRect(tester, container);

      await withKey(LogicalKeyboardKey.controlLeft, () async {
        await simulateKeyDownEvent(LogicalKeyboardKey.keyA);
        await simulateKeyUpEvent(LogicalKeyboardKey.keyA);
      });
      await tester.pump();
      expect(session(container).selection, hasLength(1));

      await simulateKeyDownEvent(LogicalKeyboardKey.escape);
      await simulateKeyUpEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(session(container).selection, isEmpty);
    });
  });

  group('9.4 move', () {
    testWidgets('dragging inside the selection moves it', (tester) async {
      final container = await pumpShell(tester);
      final before = await makeRect(tester, container);
      container.read(sessionsProvider.notifier).setSelection({before.id});
      await tester.pump();

      // Grab the outline away from every handle: (90, 40) is the top-middle
      // handle itself, so aim between it and the corner.
      await dragOnPage(tester, const Offset(65, 40), const Offset(105, 70));

      final after = elements(container).single as Shape;
      expect(after.x, closeTo(before.x + 40, 2));
      expect(after.y, closeTo(before.y + 30, 2));
      expect(after.w, closeTo(before.w, 0.01));
    });

    testWidgets('arrow keys nudge, Shift+arrow nudges further', (tester) async {
      final container = await pumpShell(tester);
      final before = await makeRect(tester, container);
      container.read(sessionsProvider.notifier).setSelection({before.id});
      await tester.pump();

      await simulateKeyDownEvent(LogicalKeyboardKey.arrowRight);
      await simulateKeyUpEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      expect(
        (elements(container).single as Shape).x,
        closeTo(before.x + 1, 1e-6),
      );

      await withKey(LogicalKeyboardKey.shiftLeft, () async {
        await simulateKeyDownEvent(LogicalKeyboardKey.arrowRight);
        await simulateKeyUpEvent(LogicalKeyboardKey.arrowRight);
      });
      await tester.pump();
      expect(
        (elements(container).single as Shape).x,
        closeTo(before.x + 11, 1e-6),
      );
    });

    testWidgets('a move drag is one undo step', (tester) async {
      final container = await pumpShell(tester);
      final before = await makeRect(tester, container);
      container.read(sessionsProvider.notifier).setSelection({before.id});
      await tester.pump();

      // From the shape's outline, clear of every handle. An unfilled rectangle
      // is only hit along its stroke, and a handle would start a resize.
      await dragOnPage(
        tester,
        const Offset(65, 40),
        const Offset(125, 40),
        steps: 10,
      );

      final session = container.read(activeSessionProvider);
      expect(session.commands.undoStack, hasLength(2)); // create, then move
      expect(
        (elements(container).single as Shape).x,
        closeTo(before.x + 60, 1),
      );

      container.read(sessionsProvider.notifier).undo();
      await tester.pump();
      expect((elements(container).single as Shape).x, closeTo(before.x, 0.01));
    });
  });

  group('9.5 / 9.6 resize and rotate', () {
    testWidgets('dragging a corner handle scales the shape', (tester) async {
      final container = await pumpShell(tester);
      final before = await makeRect(tester, container);
      container.read(sessionsProvider.notifier).setSelection({before.id});
      await tester.pump();

      // The bottom-right handle sits on (140, 100) in page coords.
      await dragOnPage(tester, const Offset(140, 100), const Offset(240, 160));

      final after = elements(container).single as Shape;
      expect(after.w, greaterThan(before.w));
      // Uniform: the aspect ratio survives.
      expect(after.w / after.h, closeTo(before.w / before.h, 1e-6));
      // The opposite corner stayed pinned.
      expect(after.x, closeTo(before.x, 1));
      expect(after.y, closeTo(before.y, 1));
    });

    testWidgets('resizing scales the stroke width too', (tester) async {
      final container = await pumpShell(tester);
      final before = await makeRect(tester, container);
      container.read(sessionsProvider.notifier).setSelection({before.id});
      await tester.pump();

      await dragOnPage(tester, const Offset(140, 100), const Offset(240, 160));
      final after = elements(container).single as Shape;
      expect(after.strokeWidth, greaterThan(before.strokeWidth));
    });

    testWidgets('dragging the rotate handle turns the shape', (tester) async {
      final container = await pumpShell(tester);
      final before = await makeRect(tester, container);
      container.read(sessionsProvider.notifier).setSelection({before.id});
      await tester.pump();

      // The rotate handle floats above the top edge's centre (90, 40).
      await dragOnPage(tester, const Offset(90, 12), const Offset(150, 40));

      final after = elements(container).single as Shape;
      expect(after.rotation, isNot(0));
      expect(after.w, closeTo(before.w, 0.01));
    });

    testWidgets('undo restores the exact geometry after a resize', (
      tester,
    ) async {
      final container = await pumpShell(tester);
      final before = await makeRect(tester, container);
      container.read(sessionsProvider.notifier).setSelection({before.id});
      await tester.pump();

      await dragOnPage(
        tester,
        const Offset(140, 100),
        const Offset(240, 160),
        steps: 12,
      );

      // Every frame pushed a command, so peel them all off.
      final sessions = container.read(sessionsProvider.notifier);
      while (session(container).canUndo) {
        sessions.undo();
      }
      await tester.pump();
      expect(elements(container), isEmpty);
    });
  });

  group('9.8 delete, duplicate, z-order', () {
    testWidgets('Delete removes the selection, undo brings it back', (
      tester,
    ) async {
      final container = await pumpShell(tester);
      final shape = await makeRect(tester, container);
      container.read(sessionsProvider.notifier).setSelection({shape.id});
      await tester.pump();

      await simulateKeyDownEvent(LogicalKeyboardKey.delete);
      await simulateKeyUpEvent(LogicalKeyboardKey.delete);
      await tester.pump();
      expect(elements(container), isEmpty);
      expect(session(container).selection, isEmpty);

      container.read(sessionsProvider.notifier).undo();
      await tester.pump();
      expect(elements(container), hasLength(1));
    });

    testWidgets('Ctrl+D duplicates, offset, and selects the copy', (
      tester,
    ) async {
      final container = await pumpShell(tester);
      final shape = await makeRect(tester, container);
      container.read(sessionsProvider.notifier).setSelection({shape.id});
      await tester.pump();

      await withKey(LogicalKeyboardKey.controlLeft, () async {
        await simulateKeyDownEvent(LogicalKeyboardKey.keyD);
        await simulateKeyUpEvent(LogicalKeyboardKey.keyD);
      });
      await tester.pump();

      final all = elements(container).cast<Shape>();
      expect(all, hasLength(2));
      expect(all[1].x, closeTo(all[0].x + 10, 1e-6));
      expect(session(container).selection, {all[1].id});
    });

    testWidgets('z-order moves the selected element within its layer', (
      tester,
    ) async {
      final container = await pumpShell(tester);
      final first = await makeRect(tester, container);

      container.read(toolProvider.notifier).select(Tool.ellipse);
      await tester.pump();
      await dragOnPage(tester, const Offset(200, 200), const Offset(280, 260));
      container.read(toolProvider.notifier).select(Tool.select);
      await tester.pump();

      expect(elements(container).map((e) => e.id).first, first.id);

      container.read(sessionsProvider.notifier)
        ..setSelection({first.id})
        ..reorderSelected(forward: true);
      await tester.pump();

      expect(elements(container).map((e) => e.id).last, first.id);

      container.read(sessionsProvider.notifier).undo();
      await tester.pump();
      expect(elements(container).map((e) => e.id).first, first.id);
    });

    testWidgets('deleting a selected element clears it from the selection', (
      tester,
    ) async {
      final container = await pumpShell(tester);
      final shape = await makeRect(tester, container);
      container.read(sessionsProvider.notifier)
        ..setSelection({shape.id})
        ..deleteSelection();
      await tester.pump();

      expect(session(container).selection, isEmpty);
    });
  });
}
