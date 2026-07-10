import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inkpad/domain/models/models.dart';
import 'package:inkpad/state/state.dart';
import 'package:inkpad/ui/ui.dart';

const _pageKey = Key('canvas-page');

Future<ProviderContainer> pumpShell(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(1000, 700));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  final container = ProviderContainer.test();
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: AppShell()),
    ),
  );
  return container;
}

Future<void> drawStroke(WidgetTester tester, {Offset at = Offset.zero}) async {
  final page = tester.getCenter(find.byKey(_pageKey)) + at;
  final gesture = await tester.startGesture(page);
  await gesture.moveBy(const Offset(20, 10));
  await gesture.moveBy(const Offset(20, -10));
  await gesture.up();
  await tester.pump();
}

int elementCount(ProviderContainer c) =>
    c.read(activeDocumentProvider).elementCount;

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
  await tester.pump();
}

Future<void> openEditMenu(WidgetTester tester) async {
  await tester.tap(find.text('Edit'));
  await tester.pumpAndSettle();
}

void main() {
  group('Edit menu', () {
    testWidgets('undo and redo start disabled', (tester) async {
      await pumpShell(tester);
      await openEditMenu(tester);

      final undo = tester.widget<MenuItemButton>(
        find.byKey(const Key('menu-undo')),
      );
      final redo = tester.widget<MenuItemButton>(
        find.byKey(const Key('menu-redo')),
      );
      expect(undo.onPressed, isNull);
      expect(redo.onPressed, isNull);
    });

    testWidgets('undo enables after drawing, and names the command', (
      tester,
    ) async {
      await pumpShell(tester);
      await drawStroke(tester);
      await openEditMenu(tester);

      final undo = tester.widget<MenuItemButton>(
        find.byKey(const Key('menu-undo')),
      );
      expect(undo.onPressed, isNotNull);
      expect(find.text('Undo Draw'), findsOneWidget);
    });

    testWidgets('choosing Undo removes the stroke and enables Redo', (
      tester,
    ) async {
      final container = await pumpShell(tester);
      await drawStroke(tester);
      expect(elementCount(container), 1);

      await openEditMenu(tester);
      await tester.tap(find.byKey(const Key('menu-undo')));
      await tester.pumpAndSettle();

      expect(elementCount(container), 0);

      await openEditMenu(tester);
      final redo = tester.widget<MenuItemButton>(
        find.byKey(const Key('menu-redo')),
      );
      expect(redo.onPressed, isNotNull);
      expect(find.text('Redo Draw'), findsOneWidget);
    });

    testWidgets('choosing Redo puts the stroke back', (tester) async {
      final container = await pumpShell(tester);
      await drawStroke(tester);

      await openEditMenu(tester);
      await tester.tap(find.byKey(const Key('menu-undo')));
      await tester.pumpAndSettle();

      await openEditMenu(tester);
      await tester.tap(find.byKey(const Key('menu-redo')));
      await tester.pumpAndSettle();

      expect(elementCount(container), 1);
    });
  });

  group('keyboard shortcuts', () {
    testWidgets('Ctrl+Z undoes', (tester) async {
      final container = await pumpShell(tester);
      await drawStroke(tester);
      expect(elementCount(container), 1);

      await press(tester, LogicalKeyboardKey.keyZ);
      expect(elementCount(container), 0);
    });

    testWidgets('Ctrl+Shift+Z redoes', (tester) async {
      final container = await pumpShell(tester);
      await drawStroke(tester);
      await press(tester, LogicalKeyboardKey.keyZ);
      expect(elementCount(container), 0);

      await press(tester, LogicalKeyboardKey.keyZ, shift: true);
      expect(elementCount(container), 1);
    });

    testWidgets('Ctrl+Y also redoes, as on Windows', (tester) async {
      final container = await pumpShell(tester);
      await drawStroke(tester);
      await press(tester, LogicalKeyboardKey.keyZ);

      await press(tester, LogicalKeyboardKey.keyY);
      expect(elementCount(container), 1);
    });

    testWidgets('Ctrl+Z with nothing to undo is harmless', (tester) async {
      final container = await pumpShell(tester);
      await press(tester, LogicalKeyboardKey.keyZ);
      expect(elementCount(container), 0);
      expect(tester.takeException(), isNull);
    });

    testWidgets('undo peels strokes off newest first', (tester) async {
      final container = await pumpShell(tester);
      await drawStroke(tester, at: const Offset(-60, 0));
      await drawStroke(tester, at: const Offset(60, 0));
      expect(elementCount(container), 2);

      await press(tester, LogicalKeyboardKey.keyZ);
      expect(elementCount(container), 1);
      await press(tester, LogicalKeyboardKey.keyZ);
      expect(elementCount(container), 0);
      await press(tester, LogicalKeyboardKey.keyZ);
      expect(elementCount(container), 0);
    });

    testWidgets('drawing after an undo clears the redo history', (
      tester,
    ) async {
      final container = await pumpShell(tester);
      await drawStroke(tester);
      await press(tester, LogicalKeyboardKey.keyZ);

      await drawStroke(tester, at: const Offset(0, 60));
      expect(container.read(activeSessionProvider).canRedo, isFalse);

      await press(tester, LogicalKeyboardKey.keyZ, shift: true);
      expect(elementCount(container), 1);
    });

    testWidgets('an undone stroke really disappears from the layer', (
      tester,
    ) async {
      final container = await pumpShell(tester);
      await drawStroke(tester);

      final stroke =
          container.read(activeSessionProvider).activeLayer.elements.single
              as Stroke;
      expect(stroke.points.length, greaterThan(1));

      await press(tester, LogicalKeyboardKey.keyZ);
      expect(container.read(activeSessionProvider).activeLayer.isEmpty, isTrue);
    });

    testWidgets('the session is dirty after drawing and clean after undo', (
      tester,
    ) async {
      final container = await pumpShell(tester);
      expect(container.read(activeSessionProvider).isDirty, isFalse);

      await drawStroke(tester);
      expect(container.read(activeSessionProvider).isDirty, isTrue);

      await press(tester, LogicalKeyboardKey.keyZ);
      expect(container.read(activeSessionProvider).isDirty, isFalse);
    });
  });
}
