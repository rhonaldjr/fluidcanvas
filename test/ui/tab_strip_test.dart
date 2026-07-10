import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inkpad/state/state.dart';
import 'package:inkpad/ui/ui.dart';

import '../support/fake_file_service.dart';
import '../support/test_container.dart';

Future<ProviderContainer> pumpShell(
  WidgetTester tester, {
  FakeFileService? files,
}) async {
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

void main() {
  group('12.1 the strip', () {
    testWidgets('is hidden when a single document is open', (tester) async {
      await pumpShell(tester);
      expect(find.byKey(const Key('tab-strip')), findsNothing);
    });

    testWidgets('two sessions render two tabs', (tester) async {
      final container = await pumpShell(tester);
      container.read(sessionsProvider.notifier).openBlankSession();
      await tester.pump();

      expect(find.byKey(const Key('tab-strip')), findsOneWidget);
      expect(find.text('Untitled 1'), findsOneWidget);
      expect(find.text('Untitled 2'), findsOneWidget);
    });

    testWidgets('clicking the inactive tab switches the canvas', (
      tester,
    ) async {
      final container = await pumpShell(tester);
      container.read(sessionsProvider.notifier).openBlankSession();
      await tester.pump();
      final first = state(container).sessions.first.id;

      await tester.tap(find.text('Untitled 1'));
      await tester.pump();

      expect(state(container).activeSessionId, first);
    });

    testWidgets('the + button opens an empty tab and focuses it', (
      tester,
    ) async {
      final container = await pumpShell(tester);
      container.read(sessionsProvider.notifier).openBlankSession();
      await tester.pump();

      await tester.tap(find.byKey(const Key('tab-new')));
      await tester.pump();

      expect(state(container).sessionCount, 3);
      expect(state(container).activeSession.title, 'Untitled 3');
      expect(state(container).activeSession.document.isEmpty, isTrue);
    });

    testWidgets('a dirty session shows a dot, a clean one does not', (
      tester,
    ) async {
      final container = await pumpShell(tester);
      container.read(sessionsProvider.notifier).openBlankSession();
      await tester.pump();
      expect(find.byKey(const Key('tab-dirty')), findsNothing);

      container.read(sessionsProvider.notifier).resizeCanvas(700, 500);
      await tester.pump();

      expect(find.byKey(const Key('tab-dirty')), findsOneWidget);
    });

    testWidgets('the close button closes a clean tab without asking', (
      tester,
    ) async {
      final container = await pumpShell(tester);
      container.read(sessionsProvider.notifier).openBlankSession();
      await tester.pump();

      await tester.tap(find.byTooltip('Close Untitled 2'));
      await tester.pumpAndSettle();

      expect(state(container).sessionCount, 1);
      expect(find.byKey(const Key('save-prompt')), findsNothing);
    });
  });

  group('12.3 width and overflow', () {
    test('tabs share the strip until they hit the minimum', () {
      expect(tabWidth(1000, 2), kTabMaxWidth);
      expect(tabWidth(600, 4), 150);
      // Past this the strip scrolls rather than shrinking tabs to slivers.
      expect(tabWidth(600, 20), kTabMinWidth);
    });

    test('a strip with no tabs still reports a sane width', () {
      expect(tabWidth(600, 0), kTabMaxWidth);
    });

    testWidgets('many tabs scroll rather than overflowing the strip', (
      tester,
    ) async {
      final container = await pumpShell(tester);
      final sessions = container.read(sessionsProvider.notifier);
      for (var i = 0; i < 20; i++) {
        sessions.openBlankSession();
      }
      await tester.pump();

      // No RenderFlex overflow was thrown, and the strip is scrollable.
      expect(tester.takeException(), isNull);
      expect(
        find.descendant(
          of: find.byKey(const Key('tab-strip')),
          matching: find.byType(Scrollable),
        ),
        findsOneWidget,
      );
    });

    testWidgets('middle-clicking a tab closes it', (tester) async {
      final container = await pumpShell(tester);
      container.read(sessionsProvider.notifier).openBlankSession();
      await tester.pump();

      final tab = tester.getCenter(find.text('Untitled 1'));
      final gesture = await tester.startGesture(
        tab,
        buttons: kMiddleMouseButton,
      );
      await gesture.up();
      await tester.pumpAndSettle();

      expect(state(container).sessionCount, 1);
      expect(state(container).activeSession.title, 'Untitled 2');
    });
  });
}
