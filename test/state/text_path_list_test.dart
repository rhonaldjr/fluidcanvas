import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inkpad/domain/commands/commands.dart';
import 'package:inkpad/domain/models/models.dart';
import 'package:inkpad/state/state.dart';

Shape rect(String id) => Shape(
  id: id,
  type: ShapeType.rectangle,
  x: 0,
  y: 0,
  w: 100,
  h: 60,
  strokeColorRGBA: 0xFF,
  strokeWidth: 2,
);

TextElement text(String id) =>
    TextElement(id: id, x: 0, y: 0, w: 100, h: 40, runs: const [TextRun('hi')]);

void main() {
  late ProviderContainer container;
  late SessionsNotifier sessions;

  setUp(() {
    container = ProviderContainer.test();
    sessions = container.read(sessionsProvider.notifier);
  });

  void add(CanvasElement e) => sessions.run(
    AddElementCommand(
      layerId: sessions.state.activeSession.activeLayerId,
      element: e,
    ),
  );

  TextElement textOf(String id) =>
      container.read(activeDocumentProvider).findElement(id)!.element
          as TextElement;

  group('list style', () {
    test('setTextListStyle sets it, undoably', () {
      final before = text('t');
      add(before);
      sessions.setTextListStyle(before, ListStyle.bullet);
      expect(textOf('t').listStyle, ListStyle.bullet);

      sessions.undo();
      expect(textOf('t').listStyle, ListStyle.none);
    });

    test('setting the same style twice pushes nothing', () {
      add(text('t'));
      final depth = sessions.state.activeSession.commands.undoStack.length;
      sessions.setTextListStyle(textOf('t'), ListStyle.none);
      expect(sessions.state.activeSession.commands.undoStack.length, depth);
    });
  });

  group('toggleTextOnPath', () {
    test('binds a text to a selected shape', () {
      add(rect('r'));
      add(text('t'));
      sessions.setSelection({'t', 'r'});

      sessions.toggleTextOnPath();

      expect(textOf('t').pathElementId, 'r');
      expect(textOf('t').isOnPath, isTrue);
    });

    test('a second toggle detaches it', () {
      add(rect('r'));
      add(text('t'));
      sessions.setSelection({'t', 'r'});
      sessions.toggleTextOnPath();

      sessions.setSelection({'t'});
      sessions.toggleTextOnPath();
      expect(textOf('t').isOnPath, isFalse);
    });

    test('binding is undoable', () {
      add(rect('r'));
      add(text('t'));
      sessions.setSelection({'t', 'r'});
      sessions.toggleTextOnPath();

      sessions.undo();
      expect(textOf('t').isOnPath, isFalse);
    });

    test('does nothing without a bindable second element', () {
      add(text('t'));
      sessions.setSelection({'t'});
      final depth = sessions.state.activeSession.commands.undoStack.length;

      sessions.toggleTextOnPath();
      expect(sessions.state.activeSession.commands.undoStack.length, depth);
    });

    test('does nothing when two texts are selected', () {
      add(text('a'));
      add(text('b'));
      sessions.setSelection({'a', 'b'});
      final depth = sessions.state.activeSession.commands.undoStack.length;

      sessions.toggleTextOnPath();
      expect(sessions.state.activeSession.commands.undoStack.length, depth);
    });

    test('a group cannot be a path target', () {
      add(rect('a'));
      add(rect('b'));
      sessions.setSelection({'a', 'b'});
      sessions.groupSelection();
      final groupId = container
          .read(activeDocumentProvider)
          .layers
          .first
          .elements
          .whereType<Group>()
          .single
          .id;

      add(text('t'));
      sessions.setSelection({'t', groupId});
      final depth = sessions.state.activeSession.commands.undoStack.length;

      sessions.toggleTextOnPath();
      expect(
        sessions.state.activeSession.commands.undoStack.length,
        depth,
        reason: 'a group has no single outline',
      );
    });
  });
}
