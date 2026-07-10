import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inkpad/engine/view_transform.dart';
import 'package:inkpad/state/state.dart';
import 'package:inkpad/ui/ui.dart';

import '../support/fake_file_service.dart';
import '../support/test_container.dart';

const _pageKey = Key('canvas-page');
const _navKey = Key('canvas-navigation');

late FakeFileService files;

Future<ProviderContainer> pumpShell(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(1200, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final container = testContainer(files: files);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: AppShell()),
    ),
  );
  await tester.pump();
  return container;
}

SessionsState state(ProviderContainer c) => c.read(sessionsProvider);
ViewTransform view(ProviderContainer c) => c.read(activeSessionProvider).view;

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

/// A wheel signal at [at] inside the navigation layer, with [buttons] held.
Future<void> wheel(WidgetTester tester, Offset at, double dy) async {
  final origin = tester.getTopLeft(find.byKey(_navKey));
  await tester.sendEventToBinding(
    PointerScrollEvent(position: origin + at, scrollDelta: Offset(0, dy)),
  );
  await tester.pump();
}

void freeze(ProviderContainer c) =>
    c.read(sessionsProvider.notifier).setFitToWindow(false);

void main() {
  setUp(() => files = FakeFileService());

  group('18.1 middle-mouse scroll to zoom', () {
    testWidgets('a wheel with the middle button held zooms', (tester) async {
      final container = await pumpShell(tester);
      freeze(container);
      await tester.pump();

      // Press the middle button, then turn the wheel — no drag.
      final at = const Offset(300, 300);
      final origin = tester.getTopLeft(find.byKey(_navKey));
      final gesture = await tester.startGesture(
        origin + at,
        buttons: kMiddleMouseButton,
      );
      await wheel(tester, at, -50);

      expect(view(container).fitted, isFalse);
      expect(view(container).zoom, greaterThan(1));

      await gesture.up();
      await tester.pumpAndSettle();
    });

    testWidgets('a plain wheel still pans, not zooms', (tester) async {
      final container = await pumpShell(tester);
      freeze(container);
      await tester.pump();

      await wheel(tester, const Offset(300, 300), 40);

      expect(view(container).zoom, 1);
      expect(view(container).panY, -40);
    });

    testWidgets('a middle-drag still pans and does not zoom', (tester) async {
      final container = await pumpShell(tester);
      freeze(container);
      await tester.pump();

      final page = tester.getCenter(find.byKey(_pageKey));
      final gesture = await tester.startGesture(
        page,
        buttons: kMiddleMouseButton,
      );
      await gesture.moveBy(const Offset(40, 25));
      await gesture.up();
      await tester.pumpAndSettle();

      expect(view(container).zoom, 1, reason: 'a drag never zooms');
      expect(view(container).panX, 40);
    });

    testWidgets('middle-wheel-zoom leaves the document untouched', (
      tester,
    ) async {
      final container = await pumpShell(tester);
      freeze(container);
      await tester.pump();
      final before = container.read(activeDocumentProvider);

      final at = const Offset(300, 300);
      final origin = tester.getTopLeft(find.byKey(_navKey));
      final gesture = await tester.startGesture(
        origin + at,
        buttons: kMiddleMouseButton,
      );
      await wheel(tester, at, -50);
      await gesture.up();
      await tester.pumpAndSettle();

      expect(container.read(activeDocumentProvider), same(before));
      expect(container.read(activeSessionProvider).canUndo, isFalse);
    });

    testWidgets('releasing the middle button stops the wheel zooming', (
      tester,
    ) async {
      final container = await pumpShell(tester);
      freeze(container);
      await tester.pump();

      final at = const Offset(300, 300);
      final origin = tester.getTopLeft(find.byKey(_navKey));
      final gesture = await tester.startGesture(
        origin + at,
        buttons: kMiddleMouseButton,
      );
      await gesture.up();
      await tester.pump();

      // Now a wheel with no button reported pans.
      await wheel(tester, at, 40);
      expect(view(container).zoom, 1);
      expect(view(container).panY, -40);
    });
  });

  group('18.2 export shortcut', () {
    testWidgets('Ctrl+E opens the export dialog', (tester) async {
      await pumpShell(tester);
      await press(tester, LogicalKeyboardKey.keyE);
      expect(find.byKey(const Key('export-dialog')), findsOneWidget);
      await tester.tap(find.byKey(const Key('export-cancel')));
      await tester.pumpAndSettle();
    });

    testWidgets('the menu item shows the accelerator', (tester) async {
      await pumpShell(tester);
      await tester.tap(find.text('File'));
      await tester.pumpAndSettle();
      final item = tester.widget<MenuItemButton>(
        find.byKey(const Key('menu-export')),
      );
      expect(item.shortcut, isNotNull);
      expect(item.onPressed, isNotNull);
    });

    testWidgets('Ctrl+E does nothing while a text box is being edited', (
      tester,
    ) async {
      final container = await pumpShell(tester);
      container.read(toolProvider.notifier).select(Tool.text);
      await tester.pump();
      final origin = tester.getRect(find.byKey(_pageKey)).topLeft;
      await tester.tapAt(origin + const Offset(80, 80));
      await tester.pumpAndSettle();
      expect(container.read(textEditingProvider), isNotNull);

      await press(tester, LogicalKeyboardKey.keyE);
      expect(find.byKey(const Key('export-dialog')), findsNothing);
    });
  });

  group('18.3 quit', () {
    testWidgets('the File menu has a Quit item with the accelerator', (
      tester,
    ) async {
      await pumpShell(tester);
      await tester.tap(find.text('File'));
      await tester.pumpAndSettle();
      final quit = tester.widget<MenuItemButton>(
        find.byKey(const Key('menu-quit')),
      );
      expect(quit.onPressed, isNotNull);
      expect(quit.shortcut, isNotNull);
    });

    testWidgets('Ctrl+Q with a dirty tab prompts, and Cancel stays running', (
      tester,
    ) async {
      final container = await pumpShell(tester);
      container.read(sessionsProvider.notifier)
        ..setFitToWindow(false)
        ..resizeCanvas(700, 500);
      await tester.pump();
      expect(container.read(activeSessionProvider).isDirty, isTrue);

      await press(tester, LogicalKeyboardKey.keyQ);
      expect(find.byKey(const Key('save-prompt')), findsOneWidget);

      await tester.tap(find.byKey(const Key('save-prompt-cancel')));
      await tester.pumpAndSettle();
      // Still running: the shell is present and the doc is unchanged.
      expect(find.byType(AppShell), findsOneWidget);
      expect(container.read(activeSessionProvider).isDirty, isTrue);
    });

    testWidgets('a clean document quits without a prompt', (tester) async {
      await pumpShell(tester);
      // SystemNavigator.pop has no host in tests; attemptQuit tolerates it.
      await press(tester, LogicalKeyboardKey.keyQ);
      expect(find.byKey(const Key('save-prompt')), findsNothing);
    });

    testWidgets('the menu Quit on a dirty tab prompts too', (tester) async {
      final container = await pumpShell(tester);
      container.read(sessionsProvider.notifier)
        ..setFitToWindow(false)
        ..resizeCanvas(700, 500);
      await tester.pump();

      await tester.tap(find.text('File'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('menu-quit')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('save-prompt')), findsOneWidget);
      await tester.tap(find.byKey(const Key('save-prompt-cancel')));
      await tester.pumpAndSettle();
    });
  });
}
