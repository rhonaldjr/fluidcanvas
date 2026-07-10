import 'dart:io';

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

void dirty(ProviderContainer c) {
  c.read(sessionsProvider.notifier)
    ..setFitToWindow(false)
    ..resizeCanvas(800, 600);
}

void main() {
  setUp(() {
    files = FakeFileService();
    SharedPreferences.setMockInitialValues({});
  });

  group('closing a dirty tab', () {
    testWidgets('a titled tab auto-saves silently, no prompt', (tester) async {
      final container = await pumpShell(tester);
      final sessions = container.read(sessionsProvider.notifier);
      // A second, already-saved tab.
      sessions.openSession(SkdDocument.newDefault(), filePath: '/docs/a.skd');
      dirty(container);
      expect(state(container).activeSession.filePath, '/docs/a.skd');
      await tester.pump();

      await tester.tap(find.byTooltip('Close a.skd'));
      await tester.pumpAndSettle();

      // No prompt; the pending changes were written to the known file.
      expect(find.byKey(const Key('save-prompt')), findsNothing);
      expect(files.files.containsKey('/docs/a.skd'), isTrue);
      expect(state(container).sessionCount, 1);
    });

    testWidgets('the auto-saved file holds the latest document', (
      tester,
    ) async {
      final container = await pumpShell(tester);
      container
          .read(sessionsProvider.notifier)
          .openSession(SkdDocument.newDefault(), filePath: '/docs/a.skd');
      dirty(container);
      await tester.pump();

      await tester.tap(find.byTooltip('Close a.skd'));
      await tester.pumpAndSettle();

      final reread = await files.read('/docs/a.skd');
      expect(reread.document.canvasWidth, 800);
    });

    testWidgets('an untitled tab still prompts', (tester) async {
      final container = await pumpShell(tester);
      container.read(sessionsProvider.notifier).openBlankSession();
      dirty(container);
      await tester.pump();

      await tester.tap(find.byTooltip('Close Untitled 2'));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('save-prompt')), findsOneWidget);
      await tester.tap(find.byKey(const Key('save-prompt-discard')));
      await tester.pumpAndSettle();
      expect(state(container).sessionCount, 1);
    });

    testWidgets('a clean titled tab closes without saving again', (
      tester,
    ) async {
      final container = await pumpShell(tester);
      container
          .read(sessionsProvider.notifier)
          .openSession(SkdDocument.newDefault(), filePath: '/docs/a.skd');
      await tester.pump();
      // Not dirty: nothing to write.

      await tester.tap(find.byTooltip('Close a.skd'));
      await tester.pumpAndSettle();

      expect(files.files.containsKey('/docs/a.skd'), isFalse);
      expect(state(container).sessionCount, 1);
    });

    testWidgets('a failed auto-save keeps the tab open', (tester) async {
      final container = await pumpShell(tester);
      container
          .read(sessionsProvider.notifier)
          .openSession(SkdDocument.newDefault(), filePath: '/docs/a.skd');
      dirty(container);
      files.writeError = const FileSystemException('read-only');
      await tester.pump();

      await tester.tap(find.byTooltip('Close a.skd'));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('file-error')), findsOneWidget);
      expect(
        state(container).sessionCount,
        2,
        reason: 'the tab is still there',
      );
    });
  });

  group('quitting (via Ctrl+Q)', () {
    Future<void> quit(WidgetTester tester) async {
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyQ);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
    }

    testWidgets('a dirty titled document is auto-saved, no prompt', (
      tester,
    ) async {
      final container = await pumpShell(tester);
      container
          .read(sessionsProvider.notifier)
          .openSession(SkdDocument.newDefault(), filePath: '/docs/a.skd');
      dirty(container);
      await tester.pump();

      await quit(tester);

      expect(find.byKey(const Key('save-prompt')), findsNothing);
      expect(files.files.containsKey('/docs/a.skd'), isTrue);
    });

    testWidgets('a dirty untitled document prompts, and Cancel stays running', (
      tester,
    ) async {
      final container = await pumpShell(tester);
      dirty(container);
      await tester.pump();

      await quit(tester);
      expect(find.byKey(const Key('save-prompt')), findsOneWidget);

      await tester.tap(find.byKey(const Key('save-prompt-cancel')));
      await tester.pumpAndSettle();
      expect(find.byType(AppShell), findsOneWidget);
    });
  });
}
