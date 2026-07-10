import 'dart:collection';

import 'package:inkpad/domain/commands/command.dart';

/// How many commands one session remembers. Older ones fall off the bottom and
/// can never be undone.
const int kMaxUndoDepth = 200;

/// Sentinel [CommandStack.savedDepth] meaning "the saved state is no longer
/// reachable by undoing" — the history that led to it has been discarded.
const int _unreachable = -1;

/// The undo and redo history of one [DocumentSession].
///
/// Immutable: every operation returns a new stack. The document itself is not
/// held here; the caller applies or reverts the command it is handed.
///
/// One stack per session, never one globally: undo in one tab must not reach
/// into another.
class CommandStack {
  CommandStack({
    List<Command> undoStack = const [],
    List<Command> redoStack = const [],
    this.savedDepth = 0,
  }) : assert(undoStack.length <= kMaxUndoDepth, 'undo stack overflowed'),
       undoStack = UnmodifiableListView(List.of(undoStack)),
       redoStack = UnmodifiableListView(List.of(redoStack));

  /// Oldest first; [undoStack] `.last` is the next command to undo.
  final List<Command> undoStack;

  /// [redoStack] `.last` is the next command to redo.
  final List<Command> redoStack;

  /// The undo depth at the last save, or [_unreachable].
  final int savedDepth;

  bool get canUndo => undoStack.isNotEmpty;
  bool get canRedo => redoStack.isNotEmpty;

  /// Whether anything has changed since the last save.
  ///
  /// Undoing back to the saved state makes the document clean again, which is
  /// why this compares depths rather than latching a boolean.
  bool get isDirty => savedDepth != undoStack.length;

  Command get nextUndo => undoStack.last;
  Command get nextRedo => redoStack.last;

  /// Records [command] as done, discarding any redo history.
  CommandStack push(Command command) {
    final next = [...undoStack, command];

    // The saved state sat further forward than we are now, so the commands that
    // reached it have just been thrown away with the redo stack.
    var saved = savedDepth > undoStack.length ? _unreachable : savedDepth;

    if (next.length > kMaxUndoDepth) {
      next.removeAt(0);
      // The dropped command can never be undone, so a save that predates it is
      // out of reach too.
      saved = saved <= 0 ? _unreachable : saved - 1;
    }

    return CommandStack(undoStack: next, savedDepth: saved);
  }

  /// Moves the newest command onto the redo stack. The caller reverts it.
  CommandStack undo() {
    if (!canUndo) return this;
    return CommandStack(
      undoStack: undoStack.sublist(0, undoStack.length - 1),
      redoStack: [...redoStack, undoStack.last],
      savedDepth: savedDepth,
    );
  }

  /// Moves the newest redo command back. The caller re-applies it.
  CommandStack redo() {
    if (!canRedo) return this;
    return CommandStack(
      undoStack: [...undoStack, redoStack.last],
      redoStack: redoStack.sublist(0, redoStack.length - 1),
      savedDepth: savedDepth,
    );
  }

  /// Marks the current state as the saved one, clearing [isDirty].
  CommandStack markSaved() => CommandStack(
    undoStack: undoStack,
    redoStack: redoStack,
    savedDepth: undoStack.length,
  );

  /// Marks the current state as *not* the saved one, without inventing a
  /// command to undo.
  ///
  /// A document recovered from an autosave sidecar is in exactly this state:
  /// nothing was done to it in this session, yet what is on screen has never
  /// been written to its file.
  CommandStack markUnsaved() => CommandStack(
    undoStack: undoStack,
    redoStack: redoStack,
    savedDepth: _unreachable,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CommandStack &&
          savedDepth == other.savedDepth &&
          _sameCommands(undoStack, other.undoStack) &&
          _sameCommands(redoStack, other.redoStack);

  @override
  int get hashCode => Object.hash(
    savedDepth,
    Object.hashAll(undoStack),
    Object.hashAll(redoStack),
  );

  @override
  String toString() =>
      'CommandStack(undo: ${undoStack.length}, redo: ${redoStack.length}, '
      'dirty: $isDirty)';
}

bool _sameCommands(List<Command> a, List<Command> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (!identical(a[i], b[i])) return false;
  }
  return true;
}
