import 'package:flutter_test/flutter_test.dart';
import 'package:inkpad/domain/commands/commands.dart';
import 'package:inkpad/domain/models/models.dart';

/// A command that renames the document's only layer, so apply/revert are
/// observable without dragging the real commands in.
class _Rename extends Command {
  const _Rename(this.to, this.from);

  final String to;
  final String from;

  @override
  String get label => 'Rename';

  @override
  SkdDocument apply(SkdDocument d) =>
      d.replaceLayer(d.layers.single.copyWith(name: to));

  @override
  SkdDocument revert(SkdDocument d) =>
      d.replaceLayer(d.layers.single.copyWith(name: from));
}

Command cmd(String to) => _Rename(to, 'before');

void main() {
  group('empty stack', () {
    final stack = CommandStack();

    test('cannot undo or redo', () {
      expect(stack.canUndo, isFalse);
      expect(stack.canRedo, isFalse);
    });

    test('is clean', () {
      expect(stack.isDirty, isFalse);
    });

    test('undo and redo are no-ops', () {
      expect(stack.undo(), stack);
      expect(stack.redo(), stack);
    });
  });

  group('push', () {
    test('makes the stack undoable and dirty', () {
      final stack = CommandStack().push(cmd('a'));
      expect(stack.canUndo, isTrue);
      expect(stack.canRedo, isFalse);
      expect(stack.isDirty, isTrue);
    });

    test('nextUndo is the newest command', () {
      final second = cmd('b');
      final stack = CommandStack().push(cmd('a')).push(second);
      expect(identical(stack.nextUndo, second), isTrue);
    });

    test('clears the redo stack', () {
      final stack = CommandStack().push(cmd('a')).undo().push(cmd('b'));
      expect(stack.canRedo, isFalse);
      expect(stack.undoStack, hasLength(1));
    });

    test('does not mutate the original', () {
      final stack = CommandStack();
      stack.push(cmd('a'));
      expect(stack.canUndo, isFalse);
    });

    test('stacks are unmodifiable', () {
      final stack = CommandStack().push(cmd('a'));
      expect(() => stack.undoStack.add(cmd('b')), throwsUnsupportedError);
    });
  });

  group('undo and redo', () {
    test('undo moves the command onto the redo stack', () {
      final stack = CommandStack().push(cmd('a')).undo();
      expect(stack.canUndo, isFalse);
      expect(stack.canRedo, isTrue);
    });

    test('redo moves it back', () {
      final stack = CommandStack().push(cmd('a')).undo().redo();
      expect(stack.canUndo, isTrue);
      expect(stack.canRedo, isFalse);
    });

    test('order is preserved through undo and redo', () {
      final a = cmd('a');
      final b = cmd('b');
      var stack = CommandStack().push(a).push(b);

      expect(identical(stack.nextUndo, b), isTrue);
      stack = stack.undo();
      expect(identical(stack.nextUndo, a), isTrue);
      expect(identical(stack.nextRedo, b), isTrue);

      stack = stack.undo();
      expect(stack.canUndo, isFalse);
      // The redo stack replays newest-last.
      expect(identical(stack.nextRedo, a), isTrue);
    });
  });

  group('depth cap', () {
    test('holds at most kMaxUndoDepth commands', () {
      var stack = CommandStack();
      for (var i = 0; i < kMaxUndoDepth + 50; i++) {
        stack = stack.push(cmd('$i'));
      }
      expect(stack.undoStack, hasLength(kMaxUndoDepth));
    });

    test('drops the oldest command, keeping the newest', () {
      var stack = CommandStack();
      final newest = cmd('newest');
      for (var i = 0; i < kMaxUndoDepth; i++) {
        stack = stack.push(cmd('$i'));
      }
      stack = stack.push(newest);
      expect(identical(stack.nextUndo, newest), isTrue);
      expect(stack.undoStack, hasLength(kMaxUndoDepth));
    });
  });

  group('dirty tracking', () {
    test('markSaved clears dirty', () {
      final stack = CommandStack().push(cmd('a')).markSaved();
      expect(stack.isDirty, isFalse);
    });

    test('a command after saving makes it dirty again', () {
      final stack = CommandStack().push(cmd('a')).markSaved().push(cmd('b'));
      expect(stack.isDirty, isTrue);
    });

    test('undoing back to the saved state makes it clean again', () {
      // A boolean flag would stay latched here; comparing depths does not.
      final stack = CommandStack()
          .push(cmd('a'))
          .markSaved()
          .push(cmd('b'))
          .undo();
      expect(stack.isDirty, isFalse);
    });

    test('redoing forward from the saved state makes it dirty', () {
      final stack = CommandStack()
          .push(cmd('a'))
          .markSaved()
          .push(cmd('b'))
          .undo()
          .redo();
      expect(stack.isDirty, isTrue);
    });

    test('undoing past the saved state is dirty', () {
      final stack = CommandStack().push(cmd('a')).markSaved().undo();
      expect(stack.isDirty, isTrue);
    });

    test(
      'a new branch makes the saved state unreachable, so it stays dirty',
      () {
        // Save, undo past it, then do something else: the commands that reached
        // the saved state are gone with the redo stack.
        final stack = CommandStack()
            .push(cmd('a'))
            .markSaved()
            .undo()
            .push(cmd('different'));
        expect(stack.isDirty, isTrue);

        // Undoing the new command must not accidentally look "saved".
        expect(stack.undo().isDirty, isTrue);
      },
    );

    test(
      'the saved state survives the command that reached it falling off',
      () {
        // Save after one command, then push exactly enough to drop that one
        // command. Its effect is now baked in permanently, so an empty undo
        // stack *is* the saved state.
        var stack = CommandStack().push(cmd('first')).markSaved();
        for (var i = 0; i < kMaxUndoDepth; i++) {
          stack = stack.push(cmd('$i'));
        }
        expect(stack.undoStack, hasLength(kMaxUndoDepth));

        for (var i = 0; i < kMaxUndoDepth; i++) {
          stack = stack.undo();
        }
        expect(stack.isDirty, isFalse);
      },
    );

    test('a saved state older than the retained window is unreachable', () {
      // One more push drops a command from *after* the save, so no amount of
      // undoing can return to it.
      var stack = CommandStack().push(cmd('first')).markSaved();
      for (var i = 0; i < kMaxUndoDepth + 1; i++) {
        stack = stack.push(cmd('$i'));
      }
      for (var i = 0; i < kMaxUndoDepth; i++) {
        stack = stack.undo();
      }
      expect(stack.canUndo, isFalse);
      expect(stack.isDirty, isTrue);
    });
  });

  group('value equality', () {
    test('same commands and saved depth are equal', () {
      final a = cmd('a');
      expect(CommandStack().push(a), CommandStack().push(a));
      expect(CommandStack().push(a).hashCode, CommandStack().push(a).hashCode);
    });

    test('different history is unequal', () {
      expect(CommandStack().push(cmd('a')), isNot(CommandStack()));
    });
  });
}
