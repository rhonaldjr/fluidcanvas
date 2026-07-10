import 'package:inkpad/domain/commands/commands.dart';
import 'package:inkpad/domain/models/models.dart';
import 'package:uuid/uuid.dart';

/// Everything belonging to one open document — one tab.
///
/// There is no global "current document": resolve it from the active session.
/// Later phases widen this bag with selection (9.3), the viewport transform
/// (14.1), and the file path plus dirty flag (13.1, 13.3).
///
/// What deliberately does *not* live here: the active tool, brush settings, and
/// recent colors. Those are global, so switching tabs never changes the brush
/// you are holding.
class DocumentSession {
  DocumentSession({
    required this.id,
    required this.document,
    required this.activeLayerId,
    this.fitToWindow = true,
    Set<String> selection = const {},
    CommandStack? commands,
  }) : selection = Set.unmodifiable(selection),
       commands = commands ?? CommandStack(),
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

  /// Whether the document's canvas tracks the window.
  ///
  /// On for a new document. Off for one opened from a `.skd`, which keeps the
  /// canvas size it was saved with — resizing the window must not silently
  /// rescale a drawing someone saved at a chosen size.
  final bool fitToWindow;

  /// Ids of the selected elements. Per session, so each tab remembers what it
  /// had selected.
  final Set<String> selection;

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
    fitToWindow: fitToWindow,
    // A command may have deleted a selected element.
    selection: {
      for (final id in selection)
        if (document.findElement(id) != null) id,
    },
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
    fitToWindow: fitToWindow,
    // Anything the swap removed cannot stay selected.
    selection: {
      for (final id in selection)
        if (document.findElement(id) != null) id,
    },
    commands: commands,
  );

  /// A copy with the given elements selected.
  DocumentSession withSelection(Set<String> ids) => DocumentSession(
    id: id,
    document: document,
    activeLayerId: activeLayerId,
    fitToWindow: fitToWindow,
    selection: ids,
    commands: commands,
  );

  /// The selected elements, bottom-first within each layer.
  List<CanvasElement> get selectedElements => [
    for (final layer in document.layers)
      for (final element in layer.elements)
        if (selection.contains(element.id)) element,
  ];

  /// The box around everything selected, or `null` when nothing is.
  Bounds? get selectionBounds {
    Bounds? result;
    for (final element in selectedElements) {
      final b = element.bounds;
      if (b == null) continue;
      result = result == null ? b : result.union(b);
    }
    return result;
  }

  /// A copy with the fit-to-window preference flipped.
  DocumentSession withFitToWindow(bool value) => DocumentSession(
    id: id,
    document: document,
    activeLayerId: activeLayerId,
    fitToWindow: value,
    selection: selection,
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
      fitToWindow: fitToWindow,
      selection: selection,
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
          fitToWindow == other.fitToWindow &&
          _sameSelection(selection, other.selection) &&
          commands == other.commands;

  @override
  int get hashCode => Object.hash(
    id,
    document,
    activeLayerId,
    fitToWindow,
    Object.hashAllUnordered(selection),
    commands,
  );

  @override
  String toString() =>
      'DocumentSession($id, activeLayer: $activeLayerId, $document)';
}

bool _sameSelection(Set<String> a, Set<String> b) =>
    a.length == b.length && a.containsAll(b);
