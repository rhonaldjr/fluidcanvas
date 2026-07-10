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
  }) : assert(
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

  /// A session over a blank default document.
  factory DocumentSession.blank({String? id, String? layerId}) =>
      DocumentSession.from(SkdDocument.newDefault(layerId: layerId), id: id);

  final String id;
  final SkdDocument document;

  /// The layer new elements are added to. Always names a layer in [document].
  final String activeLayerId;

  Layer get activeLayer => document.layerById(activeLayerId)!;

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
  );

  /// A copy with [layerId] active.
  ///
  /// Throws [ArgumentError] when no such layer exists.
  DocumentSession withActiveLayer(String layerId) {
    if (document.indexOfLayer(layerId) == -1) {
      throw ArgumentError.value(layerId, 'layerId', 'no such layer');
    }
    return DocumentSession(id: id, document: document, activeLayerId: layerId);
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
          activeLayerId == other.activeLayerId;

  @override
  int get hashCode => Object.hash(id, document, activeLayerId);

  @override
  String toString() =>
      'DocumentSession($id, activeLayer: $activeLayerId, $document)';
}
