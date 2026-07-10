import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inkpad/domain/commands/commands.dart';
import 'package:inkpad/domain/models/models.dart';
import 'package:inkpad/state/state.dart';

TextElement text(String s) => TextElement(
  id: 't',
  x: 0,
  y: 0,
  w: 200,
  h: 80,
  fontSize: 24,
  runs: [TextRun(s)],
);

void main() {
  late ProviderContainer container;
  late SessionsNotifier sessions;

  setUp(() {
    container = ProviderContainer.test();
    sessions = container.read(sessionsProvider.notifier);
  });

  void place(TextElement element) => sessions.run(
    AddElementCommand(
      layerId: sessions.state.activeSession.activeLayerId,
      element: element,
    ),
  );

  TextElement only() => container
      .read(activeDocumentProvider)
      .layers
      .expand((l) => l.elements)
      .whereType<TextElement>()
      .single;

  group('styleTextRangeFontSize', () {
    test('sets a per-run size on the range, undoably', () {
      final before = text('abcdef');
      place(before);

      sessions.styleTextRangeFontSize(before, 2, 4, 40);

      final after = only();
      expect(after.runs.map((r) => r.text), ['ab', 'cd', 'ef']);
      expect(after.runs[1].fontSize, 40);

      sessions.undo();
      expect(only(), before);
    });

    test('null clears the override on the range', () {
      final before = TextElement(
        id: 't',
        x: 0,
        y: 0,
        w: 200,
        h: 80,
        runs: const [TextRun('abcdef', fontSize: 40)],
      );
      place(before);

      sessions.styleTextRangeFontSize(before, 0, 6, null);
      expect(only().runs.single.fontSize, isNull);
    });

    test('an empty range does nothing', () {
      final before = text('abc');
      place(before);
      final depth = sessions.state.activeSession.commands.undoStack.length;

      sessions.styleTextRangeFontSize(before, 2, 2, 40);
      expect(
        sessions.state.activeSession.commands.undoStack.length,
        depth,
        reason: 'no command pushed',
      );
    });
  });

  group('styleTextRangeColor', () {
    test('sets a per-run colour on the range, undoably', () {
      final before = text('abcdef');
      place(before);

      sessions.styleTextRangeColor(before, 0, 3, 0xFF0000FF);

      final after = only();
      expect(after.runs.first.colorRGBA, 0xFF0000FF);
      expect(after.runs.last.colorRGBA, isNull);

      sessions.undo();
      expect(only(), before);
    });
  });
}
