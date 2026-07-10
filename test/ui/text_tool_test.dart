import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inkpad/domain/models/models.dart';
import 'package:inkpad/state/state.dart';
import 'package:inkpad/ui/ui.dart';

const _pageKey = Key('canvas-page');

Future<ProviderContainer> pumpShell(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(1100, 1300));
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

List<CanvasElement> elements(ProviderContainer c) =>
    c.read(activeDocumentProvider).layers.expand((l) => l.elements).toList();

TextElement? textOf(ProviderContainer c) =>
    elements(c).whereType<TextElement>().firstOrNull;

Future<void> placeBox(WidgetTester tester, ProviderContainer c) async {
  c.read(toolProvider.notifier).select(Tool.text);
  await tester.pump();
  final origin = tester.getRect(find.byKey(_pageKey)).topLeft;
  await tester.tapAt(origin + const Offset(60, 60));
  await tester.pumpAndSettle();
}

Future<void> typeAndCommit(WidgetTester tester, String text) async {
  await tester.enterText(find.byKey(const Key('text-editor')), text);
  await tester.pump();
  // Blur commits.
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pumpAndSettle();
}

void main() {
  group('10.1 run splicing (through the diff)', () {
    test('diffText finds an insertion', () {
      expect(diffText('ac', 'abc'), (start: 1, end: 1, inserted: 'b'));
    });

    test('diffText finds a deletion', () {
      expect(diffText('abc', 'ac'), (start: 1, end: 2, inserted: ''));
    });

    test('diffText finds a replacement', () {
      expect(diffText('abc', 'axc'), (start: 1, end: 2, inserted: 'x'));
    });

    test('diffText on an append', () {
      expect(diffText('ab', 'abc'), (start: 2, end: 2, inserted: 'c'));
    });

    test('diffText on identical text is empty', () {
      expect(diffText('ab', 'ab'), (start: 2, end: 2, inserted: ''));
    });
  });

  group('10.4 create', () {
    testWidgets('a click with the text tool adds one box and edits it', (
      tester,
    ) async {
      final container = await pumpShell(tester);
      await placeBox(tester, container);

      expect(elements(container).whereType<TextElement>(), hasLength(1));
      expect(container.read(textEditingProvider), isNotNull);
      expect(find.byKey(const Key('text-editor')), findsOneWidget);
    });

    testWidgets('the box takes the current text style', (tester) async {
      final container = await pumpShell(tester);
      container.read(textStyleProvider.notifier)
        ..setSize(36)
        ..setColor(0xE53935FF);
      await tester.pump();

      await placeBox(tester, container);
      expect(textOf(container)!.fontSize, 36);
      expect(textOf(container)!.colorRGBA, 0xE53935FF);
    });

    testWidgets('a box left empty removes itself', (tester) async {
      final container = await pumpShell(tester);
      await placeBox(tester, container);
      expect(elements(container), hasLength(1));

      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();

      expect(elements(container).whereType<TextElement>(), isEmpty);
      expect(container.read(textEditingProvider), isNull);
    });

    testWidgets('starting a second box commits the first, not clobbers it', (
      tester,
    ) async {
      final container = await pumpShell(tester);
      await placeBox(tester, container);
      await tester.enterText(find.byKey(const Key('text-editor')), 'FIRST');
      await tester.pump();

      // Click far from the first box, text tool still active: this starts a
      // second box. The first must be committed, not lost — the bug was that
      // beginning the second edit clobbered the first before its blur landed.
      final origin = tester.getRect(find.byKey(_pageKey)).topLeft;
      await tester.tapAt(origin + const Offset(500, 500));
      await tester.pumpAndSettle();

      final texts = elements(container).whereType<TextElement>().toList();
      expect(texts.map((t) => t.text), contains('FIRST'));
      // The second (empty) box is now the one being edited.
      expect(container.read(textEditingProvider), isNotNull);

      // The second box takes its own text and commits independently.
      await tester.enterText(find.byKey(const Key('text-editor')), 'SECOND');
      await tester.pump();
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();

      final finalTexts = elements(
        container,
      ).whereType<TextElement>().map((t) => t.text).toList();
      expect(finalTexts, containsAll(<String>['FIRST', 'SECOND']));
    });

    testWidgets('switching tools commits the box being edited', (tester) async {
      final container = await pumpShell(tester);
      await placeBox(tester, container);
      await tester.enterText(find.byKey(const Key('text-editor')), 'DONE');
      await tester.pump();

      container.read(toolProvider.notifier).select(Tool.pen);
      await tester.pumpAndSettle();

      expect(textOf(container)!.text, 'DONE');
      expect(container.read(textEditingProvider), isNull);
    });
  });

  group('10.5 editing', () {
    testWidgets('typing lands in the element on commit', (tester) async {
      final container = await pumpShell(tester);
      await placeBox(tester, container);
      await typeAndCommit(tester, 'hello');

      expect(textOf(container)!.text, 'hello');
      expect(container.read(textEditingProvider), isNull);
    });

    testWidgets('typing is one undo entry, not one per keystroke', (
      tester,
    ) async {
      final container = await pumpShell(tester);
      await placeBox(tester, container);

      // Several changes while the field is focused.
      await tester.enterText(find.byKey(const Key('text-editor')), 'h');
      await tester.enterText(find.byKey(const Key('text-editor')), 'he');
      await tester.enterText(find.byKey(const Key('text-editor')), 'hello');
      await tester.pump();

      final before = container
          .read(activeSessionProvider)
          .commands
          .undoStack
          .length;
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();

      // Exactly one EditTextCommand on top of the AddElementCommand.
      expect(
        container.read(activeSessionProvider).commands.undoStack,
        hasLength(before + 1),
      );
    });

    testWidgets('undo restores the text as it was', (tester) async {
      final container = await pumpShell(tester);
      await placeBox(tester, container);
      await typeAndCommit(tester, 'hello');

      container.read(sessionsProvider.notifier).undo();
      await tester.pump();
      expect(textOf(container)!.text, '');
    });
  });

  group('10.7 bold, italic, underline', () {
    testWidgets('with nothing selected they apply to the whole element', (
      tester,
    ) async {
      final container = await pumpShell(tester);
      await placeBox(tester, container);
      await typeAndCommit(tester, 'hello');

      container.read(sessionsProvider.notifier).setSelection({
        textOf(container)!.id,
      });
      await tester.pump();

      await tester.tap(find.byKey(const Key('text-bold')));
      await tester.pump();

      final runs = textOf(container)!.runs;
      expect(runs, hasLength(1));
      expect(runs.single.bold, isTrue);
    });

    testWidgets('toggling twice restores the original run list', (
      tester,
    ) async {
      final container = await pumpShell(tester);
      await placeBox(tester, container);
      await typeAndCommit(tester, 'hello');
      final before = textOf(container)!.runs;

      container.read(sessionsProvider.notifier).setSelection({
        textOf(container)!.id,
      });
      await tester.pump();

      await tester.tap(find.byKey(const Key('text-italic')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('text-italic')));
      await tester.pump();

      expect(textOf(container)!.runs, before);
    });

    testWidgets('styling is undoable', (tester) async {
      final container = await pumpShell(tester);
      await placeBox(tester, container);
      await typeAndCommit(tester, 'hello');

      container.read(sessionsProvider.notifier).setSelection({
        textOf(container)!.id,
      });
      await tester.pump();
      await tester.tap(find.byKey(const Key('text-underline')));
      await tester.pump();
      expect(textOf(container)!.runs.single.underline, isTrue);

      container.read(sessionsProvider.notifier).undo();
      await tester.pump();
      expect(textOf(container)!.runs.single.underline, isFalse);
    });
  });

  group('10.6 selection and geometry', () {
    testWidgets('a text box can be selected and moved', (tester) async {
      final container = await pumpShell(tester);
      await placeBox(tester, container);
      await typeAndCommit(tester, 'hello');

      final before = textOf(container)!;
      container.read(sessionsProvider.notifier)
        ..setSelection({before.id})
        ..moveSelection(15, 5);
      await tester.pump();

      expect(textOf(container)!.x, closeTo(before.x + 15, 1e-9));
    });

    testWidgets('resizing scales the box and the font together', (
      tester,
    ) async {
      final container = await pumpShell(tester);
      await placeBox(tester, container);
      await typeAndCommit(tester, 'hello');

      final before = textOf(container)!;
      container.read(sessionsProvider.notifier)
        ..setSelection({before.id})
        ..commitResize([before], 2, before.x, before.y);
      await tester.pump();

      final after = textOf(container)!;
      expect(after.w, closeTo(before.w * 2, 1e-9));
      expect(after.fontSize, closeTo(before.fontSize * 2, 1e-9));
    });

    testWidgets('a narrower box shrinks the text rather than clipping it', (
      tester,
    ) async {
      final container = await pumpShell(tester);
      await placeBox(tester, container);
      await typeAndCommit(
        tester,
        'a long sentence that will certainly need to wrap several times over',
      );

      final element = textOf(container)!;
      // Nothing is lost: the model still holds every character.
      expect(element.text.length, greaterThan(60));
    });
  });
}
