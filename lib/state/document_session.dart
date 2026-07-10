import 'package:inkpad/domain/commands/commands.dart';
import 'package:inkpad/domain/models/models.dart';
import 'package:uuid/uuid.dart';

/// Everything belonging to one open document — one tab.
///
/// There is no global "current document": resolve it from the active session.
/// Later phases widen this bag with the command stack (6.1), selection (8.3),
/// viewport transform (12.1), and file path plus dirty flag (11.1, 11.3).
///
/// What deliberately does *not* live here: the active tool, brush settings, and
/// recent colors. Those are global, so switching tabs never changes the brush
/// you are holding.
class DocumentSession {
  DocumentSession({
    required this.id,
    required this.document,
    required this.activeLayerId,
    CommandStack? commands,
  }) : commands = commands ?? CommandStack(),
       assert(
         document.indexOfLayer(activeLayerId) != -1,
         'activeLayerId must name a layer in the document',
       );

  /// A session over [document], with its topmost layer active.
  ///
  /// [id] is generated when omitted; pass one to keep a test deterministic.
  factory DocumentSession.from(SkdDocument document, {String? id}) =>
      DocumentSession(
        id: id ?? const Uuid().v4(),
        document: document,
        activeLayerId: document.layers.last.id,
      );

  /// This session's undo/redo history. One stack per open document.

  /// A session over a blank default document.
  factory DocumentSession.blank({String? id, String? layerId}) =>
      DocumentSession.from(SkdDocument.newDefault(layerId: layerId), id: id);

  final String id;
  final SkdDocument document;
  final CommandStack commands;

  /// The layer new elements are added to. Always names a layer in [document].
  final String activeLayerId;

  Layer get activeLayer => document.layerById(activeLayerId)!;

  /// Whether anything has changed since this document was last saved.
  bool get isDirty => commands.isDirty;

  bool get canUndo => commands.canUndo;
  bool get canRedo => commands.canRedo;

  /// Runs [command], recording it so it can be undone.
  DocumentSession run(Command command) =>
      _withDocumentAndStack(command.apply(document), commands.push(command));

  /// Takes back the most recent command. A no-op when there is nothing to undo.
  DocumentSession undo() {
    if (!commands.canUndo) return this;
    final command = commands.nextUndo;
    return _withDocumentAndStack(command.revert(document), commands.undo());
  }

  /// Re-applies the most recently undone command.
  DocumentSession redo() {
    if (!commands.canRedo) return this;
    final command = commands.nextRedo;
    return _withDocumentAndStack(command.apply(document), commands.redo());
  }

  /// Marks the current state as saved, clearing [isDirty].
  DocumentSession markSaved() =>
      _withDocumentAndStack(document, commands.markSaved());

  DocumentSession _withDocumentAndStack(
    SkdDocument document,
    CommandStack commands,
  ) => DocumentSession(
    id: id,
    document: document,
    // A command may have removed the active layer; fall back to the top one.
    activeLayerId: document.indexOfLayer(activeLayerId) != -1
        ? activeLayerId
        : document.layers.last.id,
    commands: commands,
  );

  /// A copy holding [document] instead.
  ///
  /// Keeps the active layer when it survives; otherwise falls back to the
  /// topmost layer, since a document always has at least one.
  DocumentSession withDocument(SkdDocument document) => DocumentSession(
    id: id,
    document: document,
    activeLayerId: document.indexOfLayer(activeLayerId) != -1
        ? activeLayerId
        : document.layers.last.id,
    commands: commands,
  );

  /// A copy with [layerId] active.
  ///
  /// Throws [ArgumentError] when no such layer exists.
  DocumentSession withActiveLayer(String layerId) {
    if (document.indexOfLayer(layerId) == -1) {
      throw ArgumentError.value(layerId, 'layerId', 'no such layer');
    }
    return DocumentSession(
      id: id,
      document: document,
      activeLayerId: layerId,
      commands: commands,
    );
  }

  /// A copy with [element] added on top of the active layer.
  ///
  /// From Phase 6 onward, UI code reaches this through `AddElementCommand`
  /// rather than calling it directly, so the change can be undone.
  DocumentSession addElementToActiveLayer(CanvasElement element) =>
      withDocument(document.replaceLayer(activeLayer.addElement(element)));

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DocumentSession &&
          id == other.id &&
          document == other.document &&
          activeLayerId == other.activeLayerId &&
          commands == other.commands;

  @override
  int get hashCode => Object.hash(id, document, activeLayerId, commands);

  @override
  String toString() =>
      'DocumentSession($id, activeLayer: $activeLayerId, $document)';
}
