import 'package:inkpad/domain/models/models.dart';

/// One undoable change to a document.
///
/// Commands are immutable and **pure**: [apply] and [revert] return a new
/// document and touch nothing else. A command carries whatever it needs to go
/// in both directions — deleting a layer, for instance, remembers the layer and
/// where it sat, because `revert` has no other way to put it back.
///
/// [apply] must be repeatable: redo calls it again on the same document it
/// first saw, since pushing a new command clears the redo stack.
abstract class Command {
  const Command();

  /// The document with this change made.
  SkdDocument apply(SkdDocument document);

  /// The document with this change taken back out.
  ///
  /// `revert(apply(doc))` must equal `doc`.
  SkdDocument revert(SkdDocument document);

  /// Shown in the Edit menu, e.g. "Undo Draw Stroke".
  String get label;
}
