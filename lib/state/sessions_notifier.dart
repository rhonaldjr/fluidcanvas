import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:inkpad/domain/commands/commands.dart';
import 'package:inkpad/domain/models/models.dart';
import 'package:inkpad/state/document_session.dart';
import 'package:uuid/uuid.dart';

/// Every open document, plus which one is in front.
///
/// [sessions] is ordered left-to-right as the tab strip shows them, so this is
/// a list rather than a map. It is never empty: closing the last tab leaves a
/// fresh blank one.
class SessionsState {
  SessionsState({
    required List<DocumentSession> sessions,
    required this.activeSessionId,
  }) : assert(sessions.isNotEmpty, 'there is always at least one session'),
       assert(
         sessions.any((s) => s.id == activeSessionId),
         'activeSessionId must name an open session',
       ),
       assert(
         sessions.map((s) => s.id).toSet().length == sessions.length,
         'session ids must be unique',
       ),
       sessions = List.unmodifiable(sessions);

  final List<DocumentSession> sessions;
  final String activeSessionId;

  int get sessionCount => sessions.length;

  DocumentSession get activeSession =>
      sessions[indexOfSession(activeSessionId)];

  /// Index of [id] in [sessions], or `-1` when absent.
  int indexOfSession(String id) => sessions.indexWhere((s) => s.id == id);

  /// The session with [id], or `null` when absent.
  DocumentSession? sessionById(String id) {
    final index = indexOfSession(id);
    return index == -1 ? null : sessions[index];
  }

  SessionsState copyWith({
    List<DocumentSession>? sessions,
    String? activeSessionId,
  }) => SessionsState(
    sessions: sessions ?? this.sessions,
    activeSessionId: activeSessionId ?? this.activeSessionId,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SessionsState &&
          activeSessionId == other.activeSessionId &&
          _sessionsEqual(sessions, other.sessions);

  @override
  int get hashCode => Object.hash(activeSessionId, Object.hashAll(sessions));

  @override
  String toString() =>
      'SessionsState(${sessions.length} sessions, active: $activeSessionId)';
}

bool _sessionsEqual(List<DocumentSession> a, List<DocumentSession> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// Owns the open documents. The one place tabs are created and destroyed.
class SessionsNotifier extends Notifier<SessionsState> {
  @override
  SessionsState build() {
    final session = DocumentSession.blank();
    return SessionsState(sessions: [session], activeSessionId: session.id);
  }

  /// Opens [document] in a new session, makes it active, and returns its id.
  String openSession(SkdDocument document, {String? id}) {
    final session = DocumentSession.from(document, id: id);
    state = SessionsState(
      sessions: [...state.sessions, session],
      activeSessionId: session.id,
    );
    return session.id;
  }

  /// Opens a blank document in a new session and returns its id.
  String openBlankSession({String? id}) =>
      openSession(SkdDocument.newDefault(), id: id);

  /// Closes the session with [id].
  ///
  /// Closing the active session focuses the tab that slid into its place, or
  /// the one before it when the last tab was closed. Closing the only session
  /// leaves a fresh blank one rather than an empty window.
  ///
  /// Throws [ArgumentError] when no such session is open.
  void closeSession(String id) {
    final index = state.indexOfSession(id);
    if (index == -1) {
      throw ArgumentError.value(id, 'id', 'no such session');
    }

    if (state.sessionCount == 1) {
      final session = DocumentSession.blank();
      state = SessionsState(sessions: [session], activeSessionId: session.id);
      return;
    }

    final remaining = [...state.sessions]..removeAt(index);
    final wasActive = state.activeSessionId == id;
    final nextActive = wasActive
        ? remaining[index.clamp(0, remaining.length - 1)].id
        : state.activeSessionId;

    state = SessionsState(sessions: remaining, activeSessionId: nextActive);
  }

  /// Brings the session with [id] to the front.
  ///
  /// Throws [ArgumentError] when no such session is open.
  void setActiveSession(String id) {
    if (state.indexOfSession(id) == -1) {
      throw ArgumentError.value(id, 'id', 'no such session');
    }
    state = state.copyWith(activeSessionId: id);
  }

  /// Replaces the active session with [session]. Its id must not change.
  void _updateActive(DocumentSession session) {
    assert(
      session.id == state.activeSessionId,
      'a session update must not change its id',
    );
    final next = [...state.sessions];
    next[state.indexOfSession(session.id)] = session;
    state = state.copyWith(sessions: next);
  }

  /// Runs [command] against the active session, recording it for undo.
  void run(Command command) => _updateActive(state.activeSession.run(command));

  /// Undoes the active session's most recent command.
  void undo() => _updateActive(state.activeSession.undo());

  /// Redoes the active session's most recently undone command.
  void redo() => _updateActive(state.activeSession.redo());

  /// Marks the active session as saved.
  void markSaved() => _updateActive(state.activeSession.markSaved());

  /// Adds [element] on top of the active layer of the active session, as an
  /// undoable command.
  void addElementToActiveLayer(CanvasElement element) => run(
    AddElementCommand(
      layerId: state.activeSession.activeLayerId,
      element: element,
    ),
  );

  /// Makes [layerId] the active layer of the active session.
  ///
  /// Selecting a layer is a view concern, not a document change, so it is not
  /// undoable.
  void setActiveLayer(String layerId) =>
      _updateActive(state.activeSession.withActiveLayer(layerId));

  /// Adds an empty layer directly above the active one and selects it.
  void addLayer({String? id, String? name}) {
    final session = state.activeSession;
    final index = session.document.indexOfLayer(session.activeLayerId) + 1;
    final layer = Layer(
      id: id ?? const Uuid().v4(),
      name: name ?? 'Layer ${session.document.layerCount + 1}',
    );

    run(AddLayerCommand(layer: layer, index: index));
    setActiveLayer(layer.id);
  }

  /// Deletes [layerId]. A document always keeps at least one layer, so deleting
  /// the last one is refused.
  void deleteLayer(String layerId) {
    final document = state.activeSession.document;
    if (document.layerCount == 1) {
      throw StateError('cannot delete the only layer');
    }
    final index = document.indexOfLayer(layerId);
    if (index == -1) {
      throw ArgumentError.value(layerId, 'layerId', 'no such layer');
    }
    run(DeleteLayerCommand(layer: document.layers[index], index: index));
  }

  void renameLayer(String layerId, String name) {
    final layer = _requireLayer(layerId);
    if (layer.name == name) return;
    run(
      RenameLayerCommand(layerId: layerId, oldName: layer.name, newName: name),
    );
  }

  void setLayerOpacity(String layerId, double opacity) {
    final layer = _requireLayer(layerId);
    if (layer.opacity == opacity) return;
    run(
      SetLayerOpacityCommand(
        layerId: layerId,
        oldOpacity: layer.opacity,
        newOpacity: opacity,
      ),
    );
  }

  void toggleLayerVisibility(String layerId) {
    final layer = _requireLayer(layerId);
    run(SetLayerVisibilityCommand(layerId: layerId, visible: !layer.visible));
  }

  /// Moves a layer within the stack. Indices count from the bottom and address
  /// the resulting list.
  void reorderLayers(int oldIndex, int newIndex) {
    if (oldIndex == newIndex) return;
    run(ReorderLayerCommand(oldIndex: oldIndex, newIndex: newIndex));
  }

  Layer _requireLayer(String layerId) {
    final layer = state.activeSession.document.layerById(layerId);
    if (layer == null) {
      throw ArgumentError.value(layerId, 'layerId', 'no such layer');
    }
    return layer;
  }

  /// Swaps the active session's document wholesale, as Open and undo do.
  void replaceActiveDocument(SkdDocument document) =>
      _updateActive(state.activeSession.withDocument(document));
}

/// Every open document. Watch this for the tab strip.
final sessionsProvider = NotifierProvider<SessionsNotifier, SessionsState>(
  SessionsNotifier.new,
);

/// The session in front. Watch this instead of digging into [sessionsProvider].
final activeSessionProvider = Provider<DocumentSession>(
  (ref) => ref.watch(sessionsProvider).activeSession,
);

/// The active session's document. The canvas watches this.
final activeDocumentProvider = Provider<SkdDocument>(
  (ref) => ref.watch(activeSessionProvider).document,
);
