import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inkpad/domain/models/models.dart';
import 'package:inkpad/state/state.dart';
import 'package:inkpad/ui/ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fake_file_service.dart';
import '../support/test_container.dart';

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
  setUp(() {
    files = FakeFileService();
    SharedPreferences.setMockInitialValues({});
  });

  group('12.2 tab shortcuts', () {
    testWidgets('Ctrl+T opens a tab', (tester) async {
      final container = await pumpShell(tester);
      await press(tester, LogicalKeyboardKey.keyT);

      expect(state(container).sessionCount, 2);
      expect(state(container).activeSession.title, 'Untitled 2');
    });

    testWidgets('Ctrl+W closes the active tab', (tester) async {
      final container = await pumpShell(tester);
      await press(tester, LogicalKeyboardKey.keyT);
      await press(tester, LogicalKeyboardKey.keyW);

      expect(state(container).sessionCount, 1);
      expect(state(container).activeSession.title, 'Untitled 1');
    });

    testWidgets('Ctrl+W on a dirty tab asks before closing', (tester) async {
      final container = await pumpShell(tester);
      await press(tester, LogicalKeyboardKey.keyT);
      container.read(sessionsProvider.notifier).resizeCanvas(700, 500);
      await tester.pump();

      await press(tester, LogicalKeyboardKey.keyW);

      expect(find.byKey(const Key('save-prompt')), findsOneWidget);
      expect(state(container).sessionCount, 2);

      await tester.tap(find.byKey(const Key('save-prompt-discard')));
      await tester.pumpAndSettle();
      expect(state(container).sessionCount, 1);
    });

    testWidgets('Ctrl+W on the last tab leaves one fresh empty session', (
      tester,
    ) async {
      final container = await pumpShell(tester);
      await press(tester, LogicalKeyboardKey.keyW);

      expect(state(container).sessionCount, 1);
      expect(state(container).activeSession.title, 'Untitled 2');
    });

    testWidgets('Ctrl+Tab and Ctrl+Shift+Tab cycle', (tester) async {
      final container = await pumpShell(tester);
      await press(tester, LogicalKeyboardKey.keyT);
      await press(tester, LogicalKeyboardKey.keyT);

      await press(tester, LogicalKeyboardKey.tab);
      expect(state(container).activeSession.title, 'Untitled 1');

      await press(tester, LogicalKeyboardKey.tab, shift: true);
      expect(state(container).activeSession.title, 'Untitled 3');
    });

    testWidgets('Ctrl+2 jumps to the second tab', (tester) async {
      final container = await pumpShell(tester);
      await press(tester, LogicalKeyboardKey.keyT);
      await press(tester, LogicalKeyboardKey.keyT);

      await press(tester, LogicalKeyboardKey.digit2);
      expect(state(container).activeSession.title, 'Untitled 2');
    });

    testWidgets('Ctrl+9 jumps to the last tab, not the ninth', (tester) async {
      final container = await pumpShell(tester);
      await press(tester, LogicalKeyboardKey.keyT);
      await press(tester, LogicalKeyboardKey.keyT);
      await press(tester, LogicalKeyboardKey.digit1);

      await press(tester, LogicalKeyboardKey.digit9);
      expect(state(container).activeSession.title, 'Untitled 3');
    });

    testWidgets('Ctrl+5 with three tabs open does nothing', (tester) async {
      final container = await pumpShell(tester);
      await press(tester, LogicalKeyboardKey.keyT);

      await press(tester, LogicalKeyboardKey.digit5);
      expect(state(container).activeSession.title, 'Untitled 2');
    });
  });

  group('13.1 file shortcuts', () {
    testWidgets('Ctrl+S saves', (tester) async {
      final container = await pumpShell(tester);
      files.savePath = '/docs/a.skd';
      container.read(sessionsProvider.notifier)
        ..setFitToWindow(false)
        ..resizeCanvas(800, 600);
      await tester.pump();

      await press(tester, LogicalKeyboardKey.keyS);

      expect(files.files.keys, contains('/docs/a.skd'));
      expect(state(container).activeSession.isDirty, isFalse);
    });

    testWidgets('Ctrl+Shift+S is Save As', (tester) async {
      final container = await pumpShell(tester);
      files.savePath = '/docs/a.skd';
      container.read(sessionsProvider.notifier)
        ..setFitToWindow(false)
        ..resizeCanvas(800, 600);
      await tester.pump();
      await press(tester, LogicalKeyboardKey.keyS);

      files.savePath = '/docs/b.skd';
      await press(tester, LogicalKeyboardKey.keyS, shift: true);

      expect(files.saveCalls, 2);
      expect(state(container).activeSession.title, 'b.skd');
    });

    testWidgets('Ctrl+O opens', (tester) async {
      final container = await pumpShell(tester);
      files
        ..seed('/docs/a.skd', SkdDocument.newDefault())
        ..openPaths = ['/docs/a.skd'];

      await press(tester, LogicalKeyboardKey.keyO);

      expect(state(container).sessionCount, 2);
      expect(state(container).activeSession.title, 'a.skd');
    });

    testWidgets('Ctrl+N asks for a canvas size', (tester) async {
      await pumpShell(tester);
      await press(tester, LogicalKeyboardKey.keyN);

      expect(find.byKey(const Key('new-document')), findsOneWidget);
      await tester.tap(find.byKey(const Key('new-doc-cancel')));
      await tester.pumpAndSettle();
    });
  });

  group('13.5 recovery on open', () {
    testWidgets('a newer sidecar is offered, and Recover loads it dirty', (
      tester,
    ) async {
      final container = await pumpShell(tester);
      files
        ..seed(
          '/docs/a.skd',
          SkdDocument.newDefault(canvasWidth: 640),
          at: DateTime.utc(2026),
        )
        ..seed(
          '/docs/a.skd.autosave',
          SkdDocument.newDefault(canvasWidth: 1234),
          at: DateTime.utc(2026, 6),
        )
        ..openPaths = ['/docs/a.skd'];

      await press(tester, LogicalKeyboardKey.keyO);
      expect(find.byKey(const Key('recover-prompt')), findsOneWidget);

      await tester.tap(find.byKey(const Key('recover-accept')));
      await tester.pumpAndSettle();

      final session = state(container).activeSession;
      expect(session.document.canvasWidth, 1234);
      expect(session.filePath, '/docs/a.skd', reason: 'it owns the real file');
      expect(session.isDirty, isTrue, reason: 'it was never written there');
    });

    testWidgets('declining opens the saved file, clean', (tester) async {
      final container = await pumpShell(tester);
      files
        ..seed(
          '/docs/a.skd',
          SkdDocument.newDefault(canvasWidth: 640),
          at: DateTime.utc(2026),
        )
        ..seed(
          '/docs/a.skd.autosave',
          SkdDocument.newDefault(canvasWidth: 1234),
          at: DateTime.utc(2026, 6),
        )
        ..openPaths = ['/docs/a.skd'];

      await press(tester, LogicalKeyboardKey.keyO);
      await tester.tap(find.byKey(const Key('recover-discard')));
      await tester.pumpAndSettle();

      final session = state(container).activeSession;
      expect(session.document.canvasWidth, 640);
      expect(session.isDirty, isFalse);
    });

    testWidgets('an older sidecar is never mentioned', (tester) async {
      await pumpShell(tester);
      files
        ..seed(
          '/docs/a.skd',
          SkdDocument.newDefault(),
          at: DateTime.utc(2026, 6),
        )
        ..seed(
          '/docs/a.skd.autosave',
          SkdDocument.newDefault(),
          at: DateTime.utc(2026),
        )
        ..openPaths = ['/docs/a.skd'];

      await press(tester, LogicalKeyboardKey.keyO);
      expect(find.byKey(const Key('recover-prompt')), findsNothing);
    });

    testWidgets('saving a recovered document deletes its sidecar', (
      tester,
    ) async {
      final container = await pumpShell(tester);
      files
        ..seed(
          '/docs/a.skd',
          SkdDocument.newDefault(canvasWidth: 640),
          at: DateTime.utc(2026),
        )
        ..seed(
          '/docs/a.skd.autosave',
          SkdDocument.newDefault(canvasWidth: 1234),
          at: DateTime.utc(2026, 6),
        )
        ..openPaths = ['/docs/a.skd'];

      await press(tester, LogicalKeyboardKey.keyO);
      await tester.tap(find.byKey(const Key('recover-accept')));
      await tester.pumpAndSettle();

      await press(tester, LogicalKeyboardKey.keyS);

      expect(files.files.containsKey('/docs/a.skd.autosave'), isFalse);
      expect(state(container).activeSession.isDirty, isFalse);
    });
  });
}
