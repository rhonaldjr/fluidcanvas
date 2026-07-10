import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inkpad/state/state.dart';
import 'package:inkpad/ui/ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fake_file_service.dart';
import '../support/test_container.dart';

late FakeFileService files;

Future<ProviderContainer> pumpShell(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(1300, 1000));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  final container = testContainer(files: files);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: AppShell()),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

Future<void> tapMenu(WidgetTester tester, String menu, String key) async {
  await tester.tap(find.text(menu));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(Key(key)));
  await tester.pumpAndSettle();
}

/// Confirms the export dialog and lets the rasterizer finish.
///
/// `Picture.toImage` needs the real event loop: under `pump()` alone its future
/// never completes, so the write — and any error dialog — never happens.
///
/// Waits for [done] rather than a fixed delay: how long the rasterizer takes
/// depends on the machine and on what else the suite is doing, and a sleep long
/// enough today is a flaky test tomorrow.
Future<void> confirmExport(WidgetTester tester, {bool Function()? done}) async {
  await tester.tap(find.byKey(const Key('export-confirm')));
  await tester.pump();

  for (var i = 0; i < 100; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pumpAndSettle();
    if (done == null || done()) return;
  }
  fail('the export never finished');
}

Future<void> pressKey(
  WidgetTester tester,
  LogicalKeyboardKey key, {
  bool ctrl = false,
}) async {
  if (ctrl) await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  await tester.sendKeyEvent(key);
  if (ctrl) await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    files = FakeFileService();
    SharedPreferences.setMockInitialValues({});
  });

  group('15.1 Export PNG', () {
    testWidgets('exports at the chosen scale', (tester) async {
      final container = await pumpShell(tester);
      files.exportPath = '/out/sketch.png';

      await tapMenu(tester, 'File', 'menu-export');
      expect(find.byKey(const Key('export-dialog')), findsOneWidget);

      await tester.tap(find.text('2x'));
      await tester.pumpAndSettle();
      await confirmExport(tester, done: () => files.files.isNotEmpty);

      expect(files.exportCalls, 1);
      expect(files.suggestedNames.single, 'Untitled 1.png');
      final bytes = files.files['/out/sketch.png']!;
      expect(bytes.sublist(0, 4), [0x89, 0x50, 0x4E, 0x47]);
      expect(container.read(activeSessionProvider).isUntitled, isTrue);
    });

    testWidgets('the dialog shows the pixel size and follows the scale', (
      tester,
    ) async {
      final container = await pumpShell(tester);
      final document = container.read(activeDocumentProvider);

      await tapMenu(tester, 'File', 'menu-export');
      expect(
        find.text('${document.canvasWidth} × ${document.canvasHeight} pixels'),
        findsOneWidget,
      );

      await tester.tap(find.text('4x'));
      await tester.pumpAndSettle();
      expect(
        find.text(
          '${document.canvasWidth * 4} × ${document.canvasHeight * 4} pixels',
        ),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const Key('export-cancel')));
      await tester.pumpAndSettle();
    });

    testWidgets('exporting never gives the document a file path', (
      tester,
    ) async {
      final container = await pumpShell(tester);
      files.exportPath = '/out/a.png';

      await tapMenu(tester, 'File', 'menu-export');
      await confirmExport(tester, done: () => files.files.isNotEmpty);

      final session = container.read(activeSessionProvider);
      expect(session.filePath, isNull, reason: 'a PNG is not the document');
      expect(session.title, 'Untitled 1');
      expect(container.read(recentFilesProvider).value ?? [], isEmpty);
    });

    testWidgets('cancelling the dialog writes nothing', (tester) async {
      await pumpShell(tester);

      await tapMenu(tester, 'File', 'menu-export');
      await tester.tap(find.byKey(const Key('export-cancel')));
      await tester.pumpAndSettle();

      expect(files.exportCalls, 0);
      expect(files.files, isEmpty);
    });

    testWidgets('cancelling the path picker writes nothing', (tester) async {
      await pumpShell(tester);
      files.exportPath = null;

      await tapMenu(tester, 'File', 'menu-export');
      await confirmExport(tester);

      expect(files.exportCalls, 1);
      expect(files.files, isEmpty);
    });

    testWidgets('a failed write says so', (tester) async {
      await pumpShell(tester);
      files
        ..exportPath = '/out/a.png'
        ..writeError = const FileSystemException('read-only');

      await tapMenu(tester, 'File', 'menu-export');
      await confirmExport(
        tester,
        done: () => find.byKey(const Key('file-error')).evaluate().isNotEmpty,
      );

      expect(find.byKey(const Key('file-error')), findsOneWidget);
    });

    testWidgets('a scale too large to render is offered disabled', (
      tester,
    ) async {
      final container = await pumpShell(tester);
      container.read(sessionsProvider.notifier)
        ..setFitToWindow(false)
        ..resizeCanvas(8000, 8000);
      await tester.pumpAndSettle();

      await tapMenu(tester, 'File', 'menu-export');

      final segments = tester
          .widget<SegmentedButton<int>>(find.byKey(const Key('export-scale')))
          .segments;
      expect(segments.firstWhere((s) => s.value == 1).enabled, isTrue);
      // 8000 x 4 is 32000, past kMaxExportEdge.
      expect(segments.firstWhere((s) => s.value == 4).enabled, isFalse);

      await tester.tap(find.byKey(const Key('export-cancel')));
      await tester.pumpAndSettle();
    });
  });

  group('15.2 tool shortcuts', () {
    testWidgets('each letter picks its tool', (tester) async {
      final container = await pumpShell(tester);

      final bindings = {
        LogicalKeyboardKey.keyV: Tool.select,
        LogicalKeyboardKey.keyB: Tool.pen,
        LogicalKeyboardKey.keyE: Tool.eraser,
        LogicalKeyboardKey.keyR: Tool.rectangle,
        LogicalKeyboardKey.keyO: Tool.ellipse,
        LogicalKeyboardKey.keyL: Tool.line,
        LogicalKeyboardKey.keyA: Tool.arrow,
        LogicalKeyboardKey.keyD: Tool.diamond,
        LogicalKeyboardKey.keyT: Tool.text,
      };

      for (final entry in bindings.entries) {
        await pressKey(tester, entry.key);
        expect(
          container.read(toolProvider),
          entry.value,
          reason: entry.key.keyLabel,
        );
      }
    });

    testWidgets('the modified letters still mean what they meant', (
      tester,
    ) async {
      final container = await pumpShell(tester);
      container.read(toolProvider.notifier).select(Tool.pen);

      // Ctrl+A is Select All, not the arrow tool. Ctrl+T is a new tab.
      await pressKey(tester, LogicalKeyboardKey.keyA, ctrl: true);
      expect(container.read(toolProvider), Tool.pen);

      await pressKey(tester, LogicalKeyboardKey.keyT, ctrl: true);
      expect(container.read(toolProvider), Tool.pen);
      expect(container.read(sessionsProvider).sessionCount, 2);
    });

    testWidgets('[ and ] step the brush width, and stop at the ends', (
      tester,
    ) async {
      final container = await pumpShell(tester);
      final before = container.read(brushProvider).baseWidth;

      await pressKey(tester, LogicalKeyboardKey.bracketRight);
      expect(container.read(brushProvider).baseWidth, before + 1);

      await pressKey(tester, LogicalKeyboardKey.bracketLeft);
      expect(container.read(brushProvider).baseWidth, before);

      for (var i = 0; i < 80; i++) {
        await pressKey(tester, LogicalKeyboardKey.bracketLeft);
      }
      expect(container.read(brushProvider).baseWidth, kMinBrushWidth);
    });

    testWidgets('typing in a text box does not swap tools', (tester) async {
      final container = await pumpShell(tester);
      container.read(toolProvider.notifier).select(Tool.text);
      await tester.pump();

      final origin = tester
          .getRect(find.byKey(const Key('canvas-page')))
          .topLeft;
      await tester.tapAt(origin + const Offset(60, 60));
      await tester.pumpAndSettle();
      expect(container.read(textEditingProvider), isNotNull);

      // "bold" would otherwise pick pen, ellipse, line, diamond.
      await pressKey(tester, LogicalKeyboardKey.keyB);
      await pressKey(tester, LogicalKeyboardKey.keyO);
      await pressKey(tester, LogicalKeyboardKey.keyL);
      await pressKey(tester, LogicalKeyboardKey.keyD);

      expect(container.read(toolProvider), Tool.text);
    });

    testWidgets('the Help menu shows the reference, F1 too', (tester) async {
      await pumpShell(tester);

      await tapMenu(tester, 'Help', 'menu-shortcuts');
      expect(find.byKey(const Key('shortcuts-dialog')), findsOneWidget);
      expect(find.text('Undo'), findsOneWidget);
      expect(find.text('Pan'), findsWidgets);

      await tester.tap(find.byKey(const Key('shortcuts-close')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('shortcuts-dialog')), findsNothing);

      await pressKey(tester, LogicalKeyboardKey.f1);
      expect(find.byKey(const Key('shortcuts-dialog')), findsOneWidget);
    });

    test('the reference names every group, and no group is empty', () {
      expect(kShortcutReference.keys, [
        'Tools',
        'Edit',
        'View',
        'File and tabs',
      ]);
      for (final rows in kShortcutReference.values) {
        expect(rows, isNotEmpty);
        for (final row in rows) {
          expect(row.keys, isNotEmpty);
          expect(row.action, isNotEmpty);
        }
      }
    });
  });

  group('15.3 preferences', () {
    testWidgets('open, change the theme, save, and it sticks', (tester) async {
      final container = await pumpShell(tester);

      await tapMenu(tester, 'Edit', 'menu-preferences');
      expect(find.byKey(const Key('preferences-dialog')), findsOneWidget);

      await tester.tap(find.text('Dark'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('pref-save')));
      await tester.pumpAndSettle();

      expect(container.read(themeModeProvider), ThemeMode.dark);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt(PrefKeys.themeMode), ThemeMode.dark.index);
    });

    testWidgets('cancelling writes nothing', (tester) async {
      final container = await pumpShell(tester);

      await tapMenu(tester, 'Edit', 'menu-preferences');
      await tester.tap(find.text('Dark'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('pref-cancel')));
      await tester.pumpAndSettle();

      expect(container.read(themeModeProvider), ThemeMode.system);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt(PrefKeys.themeMode), isNull);
    });

    testWidgets('the default brush is applied to the toolbar on save', (
      tester,
    ) async {
      final container = await pumpShell(tester);

      await tapMenu(tester, 'Edit', 'menu-preferences');
      await tester.drag(
        find.byKey(const Key('pref-brush-width')),
        const Offset(200, 0),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('pref-save')));
      await tester.pumpAndSettle();

      expect(container.read(brushProvider).baseWidth, greaterThan(4));
    });

    testWidgets('the default canvas size seeds File → New', (tester) async {
      final container = await pumpShell(tester);
      await container
          .read(preferencesProvider.notifier)
          .save(const Preferences(canvasWidth: 640, canvasHeight: 480));
      await tester.pumpAndSettle();

      await tapMenu(tester, 'File', 'menu-new');

      final width = tester.widget<TextField>(
        find.byKey(const Key('new-doc-width')),
      );
      expect(width.controller!.text, '640');

      await tester.tap(find.byKey(const Key('new-doc-cancel')));
      await tester.pumpAndSettle();
    });

    testWidgets('autosave can be switched off entirely', (tester) async {
      final container = await pumpShell(tester);
      await container
          .read(preferencesProvider.notifier)
          .save(const Preferences(autosaveMinutes: 0));
      await tester.pumpAndSettle();

      final prefs = container.read(preferencesProvider).value!;
      expect(prefs.autosaveEnabled, isFalse);
      expect(container.read(autosaveTickerProvider).effectiveInterval, isNull);
    });

    testWidgets('an interval of 5 minutes is what the ticker uses', (
      tester,
    ) async {
      final container = await pumpShell(tester);
      await container
          .read(preferencesProvider.notifier)
          .save(const Preferences(autosaveMinutes: 5));
      await tester.pumpAndSettle();

      expect(
        container.read(autosaveTickerProvider).effectiveInterval,
        const Duration(minutes: 5),
      );
    });

    testWidgets('Restore defaults forgets everything stored', (tester) async {
      final container = await pumpShell(tester);
      await container
          .read(preferencesProvider.notifier)
          .save(const Preferences(themeMode: ThemeMode.dark, canvasWidth: 640));
      await tester.pumpAndSettle();

      await tapMenu(tester, 'Edit', 'menu-preferences');
      await tester.tap(find.byKey(const Key('pref-reset')));
      await tester.pumpAndSettle();

      expect(container.read(themeModeProvider), ThemeMode.system);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt(PrefKeys.canvasWidth), isNull);
    });
  });

  group('15.3 stored values are not trusted blindly', () {
    testWidgets('an out-of-range brush width is clamped, not applied', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({
        PrefKeys.brushWidth: 9999.0,
        PrefKeys.autosaveMinutes: -5,
      });
      final container = await pumpShell(tester);

      final prefs = await container.read(preferencesProvider.future);
      expect(prefs.brush.baseWidth, kMaxBrushWidth);
      expect(prefs.autosaveMinutes, kMinAutosaveMinutes);
    });

    testWidgets('an enum index no build has falls back', (tester) async {
      SharedPreferences.setMockInitialValues({PrefKeys.themeMode: 99});
      final container = await pumpShell(tester);

      final prefs = await container.read(preferencesProvider.future);
      expect(prefs.themeMode, ThemeMode.system);
    });
  });
}
