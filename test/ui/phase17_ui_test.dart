import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inkpad/domain/commands/commands.dart';
import 'package:inkpad/domain/models/models.dart';
import 'package:inkpad/state/state.dart';
import 'package:inkpad/ui/ui.dart';

import '../support/test_container.dart';

const _pageKey = Key('canvas-page');

Future<ProviderContainer> pumpShell(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(1300, 1000));
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
List<CanvasElement> elements(ProviderContainer c) =>
    c.read(activeDocumentProvider).layers.expand((l) => l.elements).toList();

/// Adds [element] to the active layer.
void add(ProviderContainer c, CanvasElement element) => c
    .read(sessionsProvider.notifier)
    .run(
      AddElementCommand(layerId: session(c).activeLayerId, element: element),
    );

Shape shapeAt(String id, double x, double y) => Shape(
  id: id,
  type: ShapeType.rectangle,
  x: x,
  y: y,
  w: 80,
  h: 60,
  strokeColorRGBA: 0xFF000000,
  strokeWidth: 2,
);

/// Scrolls the toolbar strip until [key] is on screen, then taps it.
///
/// The strip is a `SingleChildScrollView`; the rough toggle sits below the fold
/// at this window size, where a tap would hit the canvas behind it.
Future<void> tapInStrip(WidgetTester tester, String key) async {
  final finder = find.byKey(Key(key));
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> press(
  WidgetTester tester,
  LogicalKeyboardKey key, {
  bool shift = false,
}) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  if (shift) await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
  await tester.sendKeyEvent(key);
  if (shift) await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  await tester.pumpAndSettle();
}

void main() {
  group('17.1 rough shapes through the toolbar', () {
    testWidgets('the toggle switches the style of new shapes', (tester) async {
      final container = await pumpShell(tester);
      container.read(toolProvider.notifier).select(Tool.rectangle);
      await tester.pump();

      await tapInStrip(tester, 'shape-rough');

      expect(
        container.read(shapeStyleProvider).renderStyle,
        ShapeRenderStyle.rough,
      );
    });

    testWidgets('a shape drawn while rough carries a non-zero seed', (
      tester,
    ) async {
      final container = await pumpShell(tester);
      container
          .read(shapeStyleProvider.notifier)
          .setRenderStyle(ShapeRenderStyle.rough);
      container.read(toolProvider.notifier).select(Tool.rectangle);
      await tester.pump();

      final origin = tester.getRect(find.byKey(_pageKey)).topLeft;
      final gesture = await tester.startGesture(origin + const Offset(40, 40));
      await gesture.moveBy(const Offset(120, 90));
      await gesture.up();
      await tester.pumpAndSettle();

      final shape = elements(container).single as Shape;
      expect(shape.isRough, isTrue);
      expect(shape.seed, isNot(0), reason: 'or every shape wobbles alike');
    });

    testWidgets('toggling a selected shape to rough gives it a seed, and undo '
        'is exact', (tester) async {
      final container = await pumpShell(tester);
      final before = shapeAt('s', 40, 40);
      add(container, before);
      container.read(sessionsProvider.notifier).setSelection({'s'});
      container.read(toolProvider.notifier).select(Tool.select);
      await tester.pump();

      await tapInStrip(tester, 'shape-rough');

      final after = elements(container).single as Shape;
      expect(after.isRough, isTrue);
      expect(after.seed, seedFromId('s'), reason: 'derived, not random');

      container.read(sessionsProvider.notifier).undo();
      await tester.pump();
      expect(elements(container).single, before);
    });
  });

  group('17.2 snapping while dragging', () {
    testWidgets('a moved shape lands on its neighbour\'s edge', (tester) async {
      final container = await pumpShell(tester);
      add(container, shapeAt('a', 100, 100));
      // Three pixels shy of aligning its left edge with a's.
      add(container, shapeAt('b', 103, 300));
      container.read(sessionsProvider.notifier).setSelection({'b'});
      container.read(toolProvider.notifier).select(Tool.select);
      await tester.pump();

      final origin = tester.getRect(find.byKey(_pageKey)).topLeft;
      // On b's top edge but clear of every handle: the mid-edge handle sits at
      // x=143, and grabbing it would start a resize instead of a move.
      final gesture = await tester.startGesture(
        origin + const Offset(122, 300),
      );
      await gesture.moveBy(const Offset(1, 0));
      await gesture.up();
      await tester.pumpAndSettle();

      final b = elements(container).firstWhere((e) => e.id == 'b') as Shape;
      expect(b.x, closeTo(100, 0.001), reason: 'snapped onto a\'s left edge');
    });

    testWidgets('Alt suspends the snap', (tester) async {
      final container = await pumpShell(tester);
      add(container, shapeAt('a', 100, 100));
      add(container, shapeAt('b', 103, 300));
      container.read(sessionsProvider.notifier).setSelection({'b'});
      container.read(toolProvider.notifier).select(Tool.select);
      await tester.pump();

      await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
      final origin = tester.getRect(find.byKey(_pageKey)).topLeft;
      // On b's top edge but clear of every handle: the mid-edge handle sits at
      // x=143, and grabbing it would start a resize instead of a move.
      final gesture = await tester.startGesture(
        origin + const Offset(122, 300),
      );
      await gesture.moveBy(const Offset(1, 0));
      await gesture.up();
      await tester.pumpAndSettle();
      await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);

      final b = elements(container).firstWhere((e) => e.id == 'b') as Shape;
      expect(b.x, closeTo(104, 0.001), reason: 'moved by exactly the drag');
    });

    testWidgets('guides appear during the drag and are gone after it', (
      tester,
    ) async {
      final container = await pumpShell(tester);
      add(container, shapeAt('a', 100, 100));
      add(container, shapeAt('b', 103, 300));
      container.read(sessionsProvider.notifier).setSelection({'b'});
      container.read(toolProvider.notifier).select(Tool.select);
      await tester.pump();

      final origin = tester.getRect(find.byKey(_pageKey)).topLeft;
      // On b's top edge but clear of every handle: the mid-edge handle sits at
      // x=143, and grabbing it would start a resize instead of a move.
      final gesture = await tester.startGesture(
        origin + const Offset(122, 300),
      );
      await gesture.moveBy(const Offset(1, 0));
      await tester.pump();
      expect(container.read(snapGuidesProvider), isNotEmpty);

      await gesture.up();
      await tester.pumpAndSettle();
      expect(container.read(snapGuidesProvider), isEmpty);
    });

    testWidgets('the grid toggle turns snapping to it on', (tester) async {
      final container = await pumpShell(tester);
      expect(container.read(snapSettingsProvider).showGrid, isFalse);

      await tester.tap(find.byKey(const Key('snap-grid')));
      await tester.pump();

      final settings = container.read(snapSettingsProvider);
      expect(settings.showGrid, isTrue);
      expect(settings.snapToGrid, isTrue, reason: 'a grid you cannot land on');
    });

    testWidgets('snapping to elements can be switched off', (tester) async {
      final container = await pumpShell(tester);
      await tester.tap(find.byKey(const Key('snap-elements')));
      await tester.pump();

      expect(container.read(snapSettingsProvider).snapToElements, isFalse);
      expect(container.read(snapSettingsProvider).anySnapping, isFalse);
    });
  });

  group('17.3 group and ungroup', () {
    testWidgets('Ctrl+G groups the selection and selects the group', (
      tester,
    ) async {
      final container = await pumpShell(tester);
      add(container, shapeAt('a', 40, 40));
      add(container, shapeAt('b', 200, 40));
      container.read(sessionsProvider.notifier).setSelection({'a', 'b'});
      await tester.pump();

      await press(tester, LogicalKeyboardKey.keyG);

      final only = elements(container).single;
      expect(only, isA<Group>());
      expect(session(container).selection, {only.id});
    });

    testWidgets('Ctrl+Shift+G ungroups and selects the children', (
      tester,
    ) async {
      final container = await pumpShell(tester);
      add(container, shapeAt('a', 40, 40));
      add(container, shapeAt('b', 200, 40));
      container.read(sessionsProvider.notifier).setSelection({'a', 'b'});
      await tester.pump();
      await press(tester, LogicalKeyboardKey.keyG);

      await press(tester, LogicalKeyboardKey.keyG, shift: true);

      expect(elements(container).map((e) => e.id), ['a', 'b']);
      expect(session(container).selection, {'a', 'b'});
    });

    testWidgets('grouping fewer than two elements does nothing', (
      tester,
    ) async {
      final container = await pumpShell(tester);
      add(container, shapeAt('a', 40, 40));
      container.read(sessionsProvider.notifier).setSelection({'a'});
      await tester.pump();

      await press(tester, LogicalKeyboardKey.keyG);

      expect(elements(container).single, isA<Shape>());
      expect(session(container).commands.undoStack, hasLength(1));
    });

    testWidgets('a group moves as one, and undo restores both children', (
      tester,
    ) async {
      final container = await pumpShell(tester);
      add(container, shapeAt('a', 40, 40));
      add(container, shapeAt('b', 200, 40));
      final sessions = container.read(sessionsProvider.notifier)
        ..setSelection({'a', 'b'})
        ..groupSelection();
      await tester.pump();

      sessions.moveSelection(10, 5);
      await tester.pump();

      final group = elements(container).single as Group;
      expect((group.children.first as Shape).x, 50);
      expect((group.children.last as Shape).x, 210);

      sessions.undo();
      await tester.pump();
      final back = elements(container).single as Group;
      expect((back.children.first as Shape).x, 40);
    });

    testWidgets('clicking any child selects the group, not the child', (
      tester,
    ) async {
      final container = await pumpShell(tester);
      add(container, shapeAt('a', 40, 40));
      add(container, shapeAt('b', 200, 40));
      container.read(sessionsProvider.notifier)
        ..setSelection({'a', 'b'})
        ..groupSelection();
      container.read(toolProvider.notifier).select(Tool.select);
      await tester.pump();

      final groupId = elements(container).single.id;
      final origin = tester.getRect(find.byKey(_pageKey)).topLeft;
      // On a's top edge.
      await tester.tapAt(origin + const Offset(60, 40));
      await tester.pumpAndSettle();

      expect(session(container).selection, {groupId});
    });
  });

  group('17.4 drawing a connector', () {
    testWidgets('a drag between two shapes binds both ends', (tester) async {
      final container = await pumpShell(tester);
      add(container, shapeAt('a', 40, 40));
      add(container, shapeAt('b', 300, 40));
      container.read(toolProvider.notifier).select(Tool.connector);
      await tester.pump();

      final origin = tester.getRect(find.byKey(_pageKey)).topLeft;
      // From inside a's outline to inside b's.
      final gesture = await tester.startGesture(origin + const Offset(60, 40));
      await gesture.moveTo(origin + const Offset(320, 40));
      await gesture.up();
      await tester.pumpAndSettle();

      final connector = elements(container).whereType<Connector>().single;
      expect(connector.start, const ConnectorEnd.bound('a'));
      expect(connector.end, const ConnectorEnd.bound('b'));
    });

    testWidgets('a drag over empty canvas leaves both ends free', (
      tester,
    ) async {
      final container = await pumpShell(tester);
      container.read(toolProvider.notifier).select(Tool.connector);
      await tester.pump();

      final origin = tester.getRect(find.byKey(_pageKey)).topLeft;
      final gesture = await tester.startGesture(
        origin + const Offset(500, 400),
      );
      await gesture.moveTo(origin + const Offset(600, 450));
      await gesture.up();
      await tester.pumpAndSettle();

      final connector = elements(container).whereType<Connector>().single;
      expect(connector.isBound, isFalse);
      expect(connector.start.x, closeTo(500, 1));
    });

    testWidgets('a tap draws nothing', (tester) async {
      final container = await pumpShell(tester);
      container.read(toolProvider.notifier).select(Tool.connector);
      await tester.pump();

      final origin = tester.getRect(find.byKey(_pageKey)).topLeft;
      await tester.tapAt(origin + const Offset(500, 400));
      await tester.pumpAndSettle();

      expect(elements(container), isEmpty);
    });

    testWidgets('a shape joined to itself is refused', (tester) async {
      final container = await pumpShell(tester);
      add(container, shapeAt('a', 40, 40));
      container.read(toolProvider.notifier).select(Tool.connector);
      await tester.pump();

      // Both ends squarely on a's outline: top edge to bottom edge.
      final origin = tester.getRect(find.byKey(_pageKey)).topLeft;
      final gesture = await tester.startGesture(origin + const Offset(60, 40));
      await gesture.moveTo(origin + const Offset(60, 100));
      await gesture.up();
      await tester.pumpAndSettle();

      expect(elements(container).whereType<Connector>(), isEmpty);
    });

    testWidgets('the connector follows the shape it is bound to', (
      tester,
    ) async {
      final container = await pumpShell(tester);
      add(container, shapeAt('a', 40, 40));
      add(container, shapeAt('b', 300, 40));
      add(
        container,
        Connector(
          id: 'c',
          start: const ConnectorEnd.bound('a'),
          end: const ConnectorEnd.bound('b'),
          strokeColorRGBA: 0xFF000000,
          strokeWidth: 2,
        ),
      );
      await tester.pump();

      final siblings = elements(container);
      final before = resolveConnector(siblings.last as Connector, siblings);

      container.read(sessionsProvider.notifier)
        ..setSelection({'b'})
        ..moveSelection(0, 200);
      await tester.pump();

      final after = elements(container);
      final line = resolveConnector(after.last as Connector, after);

      expect(line.y2, greaterThan(before.y2));
      // The connector itself was never rewritten: no command touched it.
      expect(after.last, siblings.last);
      expect(session(container).commands.undoStack, hasLength(4));
    });

    testWidgets('deleting a bound shape freezes the end, and undo rebinds it', (
      tester,
    ) async {
      final container = await pumpShell(tester);
      add(container, shapeAt('a', 40, 40));
      add(container, shapeAt('b', 300, 40));
      add(
        container,
        Connector(
          id: 'c',
          start: const ConnectorEnd.bound('a'),
          end: const ConnectorEnd.bound('b'),
          strokeColorRGBA: 0xFF000000,
          strokeWidth: 2,
        ),
      );
      await tester.pump();

      final sessions = container.read(sessionsProvider.notifier)
        ..setSelection({'b'})
        ..deleteSelection();
      await tester.pump();

      final frozen = elements(container).whereType<Connector>().single;
      expect(frozen.start, const ConnectorEnd.bound('a'));
      expect(frozen.end.isBound, isFalse, reason: 'b is gone');
      expect(frozen.end.x, isNotNull);

      sessions.undo();
      await tester.pump();

      final rebound = elements(container).whereType<Connector>().single;
      expect(rebound.end, const ConnectorEnd.bound('b'));
    });
  });
}
