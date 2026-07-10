import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inkpad/domain/commands/commands.dart';
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
DocumentSession active(ProviderContainer c) => state(c).activeSession;

/// Makes the active document dirty in a way that survives a round trip.
///
/// Fit-to-window is turned off first, or the shell's LayoutBuilder resizes the
/// canvas straight back to the viewport and the assertion is about 828, not 800.
void scribble(ProviderContainer c) {
  c.read(sessionsProvider.notifier)
    ..setFitToWindow(false)
    ..resizeCanvas(800, 600);
}

Future<void> openFileMenu(WidgetTester tester) async {
  await tester.tap(find.text('File'));
  await tester.pumpAndSettle();
}

Future<void> tapMenu(WidgetTester tester, String key) async {
  await openFileMenu(tester);
  await tester.tap(find.byKey(Key(key)));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    files = FakeFileService();
    SharedPreferences.setMockInitialValues({});
  });

  group('13.1 save', () {
    testWidgets('Save on an untitled document asks where', (tester) async {
      final container = await pumpShell(tester);
      files.savePath = '/docs/sketch.skd';
      scribble(container);

      await tapMenu(tester, 'menu-save');

      expect(files.saveCalls, 1);
      expect(files.suggestedNames.single, 'Untitled 1.skd');
      expect(files.files.keys, contains('/docs/sketch.skd'));
    });

    testWidgets('saving retitles the tab and cleans the document', (
      tester,
    ) async {
      final container = await pumpShell(tester);
      files.savePath = '/docs/sketch.skd';
      scribble(container);
      expect(active(container).isDirty, isTrue);

      await tapMenu(tester, 'menu-save');

      expect(active(container).title, 'sketch.skd');
      expect(active(container).isDirty, isFalse);
      expect(active(container).filePath, '/docs/sketch.skd');
    });

    testWidgets('a second Save overwrites silently', (tester) async {
      final container = await pumpShell(tester);
      files.savePath = '/docs/sketch.skd';
      scribble(container);
      await tapMenu(tester, 'menu-save');

      scribble(container);
      await tapMenu(tester, 'menu-save');

      expect(files.saveCalls, 1, reason: 'the picker is not asked twice');
      expect(active(container).isDirty, isFalse);
    });

    testWidgets('Save As asks again even when the document has a path', (
      tester,
    ) async {
      final container = await pumpShell(tester);
      files.savePath = '/docs/one.skd';
      scribble(container);
      await tapMenu(tester, 'menu-save');

      files.savePath = '/docs/two.skd';
      await tapMenu(tester, 'menu-save-as');

      expect(files.saveCalls, 2);
      expect(active(container).title, 'two.skd');
      expect(files.files.keys, containsAll(['/docs/one.skd', '/docs/two.skd']));
    });

    testWidgets('cancelling the picker writes nothing and stays dirty', (
      tester,
    ) async {
      final container = await pumpShell(tester);
      files.savePath = null;
      scribble(container);

      await tapMenu(tester, 'menu-save');

      expect(files.files, isEmpty);
      expect(active(container).isDirty, isTrue);
      expect(active(container).isUntitled, isTrue);
    });

    testWidgets('a failed write says so and leaves the document dirty', (
      tester,
    ) async {
      final container = await pumpShell(tester);
      files.savePath = '/readonly/sketch.skd';
      files.writeError = const FileSystemException('read-only volume');
      scribble(container);

      await tapMenu(tester, 'menu-save');

      expect(find.byKey(const Key('file-error')), findsOneWidget);
      expect(active(container).isDirty, isTrue);
      expect(active(container).isUntitled, isTrue);
    });

    testWidgets('what is written reads back as the same document', (
      tester,
    ) async {
      final container = await pumpShell(tester);
      files.savePath = '/docs/sketch.skd';
      scribble(container);
      await tapMenu(tester, 'menu-save');

      final reread = await files.read('/docs/sketch.skd');
      expect(reread.document.canvasWidth, 800);
      expect(reread.document.canvasHeight, 600);
    });
  });

  group('13.2 open', () {
    testWidgets('opens into a new tab, leaving the current one alone', (
      tester,
    ) async {
      final container = await pumpShell(tester);
      final before = active(container).id;
      files
        ..seed('/docs/a.skd', SkdDocument.newDefault(canvasWidth: 640))
        ..openPaths = ['/docs/a.skd'];

      await tapMenu(tester, 'menu-open');

      expect(state(container).sessionCount, 2);
      expect(state(container).sessions.first.id, before);
      expect(active(container).title, 'a.skd');
      expect(active(container).document.canvasWidth, 640);
    });

    testWidgets('an opened document keeps its stored canvas size', (
      tester,
    ) async {
      final container = await pumpShell(tester);
      files
        ..seed('/docs/a.skd', SkdDocument.newDefault(canvasWidth: 640))
        ..openPaths = ['/docs/a.skd'];

      await tapMenu(tester, 'menu-open');

      // Fit-to-window off, or the window would silently rescale a drawing
      // someone saved at a chosen size.
      expect(active(container).fitToWindow, isFalse);
      expect(active(container).document.canvasWidth, 640);
    });

    testWidgets('opening a file already open focuses its tab', (tester) async {
      final container = await pumpShell(tester);
      files
        ..seed('/docs/a.skd', SkdDocument.newDefault())
        ..openPaths = ['/docs/a.skd'];

      await tapMenu(tester, 'menu-open');
      final opened = active(container).id;
      container.read(sessionsProvider.notifier).activateAt(0);

      await tapMenu(tester, 'menu-open');

      expect(state(container).sessionCount, 2, reason: 'no duplicate tab');
      expect(state(container).activeSessionId, opened);
    });

    testWidgets('a corrupt file shows an error and opens no tab', (
      tester,
    ) async {
      final container = await pumpShell(tester);
      files
        ..seedCorrupt('/docs/bad.skd')
        ..openPaths = ['/docs/bad.skd'];

      await tapMenu(tester, 'menu-open');

      expect(find.byKey(const Key('file-error')), findsOneWidget);
      expect(state(container).sessionCount, 1);
    });

    testWidgets('opening two files opens two tabs', (tester) async {
      final container = await pumpShell(tester);
      files
        ..seed('/docs/a.skd', SkdDocument.newDefault())
        ..seed('/docs/b.skd', SkdDocument.newDefault())
        ..openPaths = ['/docs/a.skd', '/docs/b.skd'];

      await tapMenu(tester, 'menu-open');

      expect(state(container).sessionCount, 3);
      expect(active(container).title, 'b.skd');
    });

    testWidgets('cancelling the picker opens nothing', (tester) async {
      final container = await pumpShell(tester);
      files.openPaths = [];

      await tapMenu(tester, 'menu-open');

      expect(state(container).sessionCount, 1);
    });
  });

  group('13.3 new', () {
    testWidgets('New opens a tab at the chosen size', (tester) async {
      final container = await pumpShell(tester);

      await tapMenu(tester, 'menu-new');
      expect(find.byKey(const Key('new-document')), findsOneWidget);

      await tester.tap(find.byKey(const Key('new-doc-fit')));
      await tester.pump();
      await tester.enterText(find.byKey(const Key('new-doc-width')), '900');
      await tester.enterText(find.byKey(const Key('new-doc-height')), '700');
      await tester.tap(find.byKey(const Key('new-doc-create')));
      await tester.pumpAndSettle();

      expect(state(container).sessionCount, 2);
      expect(active(container).document.canvasWidth, 900);
      expect(active(container).document.canvasHeight, 700);
      expect(active(container).fitToWindow, isFalse);
    });

    testWidgets('a preset fills the size fields', (tester) async {
      final container = await pumpShell(tester);

      await tapMenu(tester, 'menu-new');
      await tester.tap(find.byKey(const Key('new-doc-fit')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('preset-4K')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('new-doc-create')));
      await tester.pumpAndSettle();

      expect(active(container).document.canvasWidth, 3840);
      expect(active(container).document.canvasHeight, 2160);
    });

    testWidgets('fit-to-window stays on by default', (tester) async {
      final container = await pumpShell(tester);

      await tapMenu(tester, 'menu-new');
      await tester.tap(find.byKey(const Key('new-doc-create')));
      await tester.pumpAndSettle();

      expect(active(container).fitToWindow, isTrue);
    });

    testWidgets('cancelling opens no tab', (tester) async {
      final container = await pumpShell(tester);

      await tapMenu(tester, 'menu-new');
      await tester.tap(find.byKey(const Key('new-doc-cancel')));
      await tester.pumpAndSettle();

      expect(state(container).sessionCount, 1);
    });

    testWidgets('an absurd size is clamped rather than opened', (tester) async {
      final container = await pumpShell(tester);

      await tapMenu(tester, 'menu-new');
      await tester.tap(find.byKey(const Key('new-doc-fit')));
      await tester.pump();
      await tester.enterText(find.byKey(const Key('new-doc-width')), '99999');
      await tester.enterText(find.byKey(const Key('new-doc-height')), '1');
      await tester.tap(find.byKey(const Key('new-doc-create')));
      await tester.pumpAndSettle();

      expect(active(container).document.canvasWidth, kMaxCanvasWidth);
      expect(active(container).document.canvasHeight, kMinCanvasHeight);
    });
  });

  group('13.3 closing a dirty tab', () {
    testWidgets('prompts, and Save writes before closing', (tester) async {
      final container = await pumpShell(tester);
      container.read(sessionsProvider.notifier).openBlankSession();
      scribble(container);
      files.savePath = '/docs/two.skd';
      await tester.pump();

      await tester.tap(find.byTooltip('Close Untitled 2'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('save-prompt')), findsOneWidget);

      await tester.tap(find.byKey(const Key('save-prompt-save')));
      await tester.pumpAndSettle();

      expect(files.files.keys, contains('/docs/two.skd'));
      expect(state(container).sessionCount, 1);
    });

    testWidgets("Don't save closes it and writes nothing", (tester) async {
      final container = await pumpShell(tester);
      container.read(sessionsProvider.notifier).openBlankSession();
      scribble(container);
      await tester.pump();

      await tester.tap(find.byTooltip('Close Untitled 2'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('save-prompt-discard')));
      await tester.pumpAndSettle();

      expect(files.files, isEmpty);
      expect(state(container).sessionCount, 1);
    });

    testWidgets('Cancel keeps the tab and its changes', (tester) async {
      final container = await pumpShell(tester);
      container.read(sessionsProvider.notifier).openBlankSession();
      scribble(container);
      await tester.pump();

      await tester.tap(find.byTooltip('Close Untitled 2'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('save-prompt-cancel')));
      await tester.pumpAndSettle();

      expect(state(container).sessionCount, 2);
      expect(active(container).isDirty, isTrue);
    });

    testWidgets('cancelling the save picker keeps the tab open', (
      tester,
    ) async {
      final container = await pumpShell(tester);
      container.read(sessionsProvider.notifier).openBlankSession();
      scribble(container);
      files.savePath = null;
      await tester.pump();

      await tester.tap(find.byTooltip('Close Untitled 2'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('save-prompt-save')));
      await tester.pumpAndSettle();

      expect(state(container).sessionCount, 2, reason: 'nothing was saved');
    });

    testWidgets('a background dirty tab is brought forward before it is asked '
        'about', (tester) async {
      final container = await pumpShell(tester);
      final first = active(container).id;
      scribble(container); // Untitled 1 is dirty
      container.read(sessionsProvider.notifier).openBlankSession();
      await tester.pump();

      await tester.tap(find.byTooltip('Close Untitled 1'));
      await tester.pumpAndSettle();

      expect(state(container).activeSessionId, first);
      expect(find.text('Save changes to Untitled 1?'), findsOneWidget);
      await tester.tap(find.byKey(const Key('save-prompt-cancel')));
      await tester.pumpAndSettle();
    });
  });

  group('13.4 recent files', () {
    testWidgets('saving and opening add to the list, newest first', (
      tester,
    ) async {
      final container = await pumpShell(tester);
      files
        ..seed('/docs/a.skd', SkdDocument.newDefault())
        ..openPaths = ['/docs/a.skd'];
      await tapMenu(tester, 'menu-open');

      // Back to the untitled tab: Save on the opened one would overwrite it
      // in place and never reach the picker.
      container.read(sessionsProvider.notifier).activateAt(0);
      await tester.pump();
      files.savePath = '/docs/b.skd';
      scribble(container);
      await tapMenu(tester, 'menu-save');
      await tester.pumpAndSettle();

      expect(container.read(recentFilesProvider).value, [
        '/docs/b.skd',
        '/docs/a.skd',
      ]);
    });

    testWidgets('the same file is not listed twice', (tester) async {
      final container = await pumpShell(tester);
      final recent = container.read(recentFilesProvider.notifier);
      await recent.add('/docs/a.skd');
      await recent.add('/docs/b.skd');
      await recent.add('/docs/a.skd');

      expect(container.read(recentFilesProvider).value, [
        '/docs/a.skd',
        '/docs/b.skd',
      ]);
    });

    testWidgets('the list is capped', (tester) async {
      final container = await pumpShell(tester);
      final recent = container.read(recentFilesProvider.notifier);
      for (var i = 0; i < kMaxRecentFiles + 4; i++) {
        await recent.add('/docs/$i.skd');
      }

      final list = container.read(recentFilesProvider).value!;
      expect(list, hasLength(kMaxRecentFiles));
      expect(list.first, '/docs/${kMaxRecentFiles + 3}.skd');
    });

    testWidgets('a file that will not open is forgotten', (tester) async {
      final container = await pumpShell(tester);
      final recent = container.read(recentFilesProvider.notifier);
      await recent.add('/docs/gone.skd');

      files.openPaths = ['/docs/gone.skd'];
      await tapMenu(tester, 'menu-open');

      expect(container.read(recentFilesProvider).value, isEmpty);
    });

    testWidgets('missing files are pruned when the list loads', (tester) async {
      SharedPreferences.setMockInitialValues({
        kRecentFilesKey: ['/docs/here.skd', '/docs/gone.skd'],
      });
      files.seed('/docs/here.skd', SkdDocument.newDefault());
      final container = await pumpShell(tester);

      final list = await container.read(recentFilesProvider.future);
      expect(list, ['/docs/here.skd']);
    });

    testWidgets('the menu lists them by base name and opens one', (
      tester,
    ) async {
      final container = await pumpShell(tester);
      files.seed('/docs/a.skd', SkdDocument.newDefault());
      await container.read(recentFilesProvider.notifier).add('/docs/a.skd');
      await tester.pumpAndSettle();

      await openFileMenu(tester);
      await tester.tap(find.byKey(const Key('menu-recent')));
      await tester.pumpAndSettle();
      expect(find.text('a.skd'), findsOneWidget);

      await tester.tap(find.byKey(const Key('recent-/docs/a.skd')));
      await tester.pumpAndSettle();

      expect(state(container).sessionCount, 2);
      expect(active(container).title, 'a.skd');
    });

    testWidgets('an empty list says so rather than offering nothing', (
      tester,
    ) async {
      await pumpShell(tester);
      await openFileMenu(tester);
      await tester.tap(find.byKey(const Key('menu-recent')));
      await tester.pumpAndSettle();

      expect(find.text('No recent files'), findsOneWidget);
    });
  });
}
