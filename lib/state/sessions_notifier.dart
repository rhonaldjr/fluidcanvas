import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:inkpad/domain/commands/commands.dart';
import 'package:inkpad/engine/text_on_path.dart';
import 'package:inkpad/domain/models/models.dart';
import 'package:inkpad/engine/view_transform.dart';
import 'package:inkpad/state/document_session.dart';
import 'package:inkpad/state/text_editing.dart';
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
  /// Counts every untitled document this run has produced, so `Untitled 2`
  /// stays `Untitled 2` after `Untitled 1` is closed.
  int _untitledCount = 0;

  @override
  SessionsState build() {
    final session = DocumentSession.blank(untitledIndex: ++_untitledCount);
    return SessionsState(sessions: [session], activeSessionId: session.id);
  }

  /// Opens [document] in a new session, makes it active, and returns its id.
  ///
  /// A session with a [filePath] takes its title from the file and starts with
  /// fit-to-window off; one without gets the next `Untitled N`.
  String openSession(
    SkdDocument document, {
    String? id,
    String? filePath,
    bool? fitToWindow,
  }) {
    final session = DocumentSession.from(
      document,
      id: id,
      filePath: filePath,
      fitToWindow: fitToWindow,
      untitledIndex: filePath == null ? ++_untitledCount : 0,
    );
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
      final session = DocumentSession.blank(untitledIndex: ++_untitledCount);
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

  /// Focuses the session [delta] tabs away, wrapping at either end.
  void cycleSession(int delta) {
    final count = state.sessionCount;
    if (count < 2) return;
    final at = state.indexOfSession(state.activeSessionId);
    // Dart's % on a negative left operand still returns a non-negative result.
    activateAt((at + delta) % count);
  }

  /// Focuses the tab at [index]. Out-of-range indices are ignored, so
  /// Ctrl+7 with three tabs open does nothing rather than throwing.
  void activateAt(int index) {
    if (index < 0 || index >= state.sessionCount) return;
    state = state.copyWith(activeSessionId: state.sessions[index].id);
  }

  /// Focuses the last tab, wherever it is. What Ctrl+9 means everywhere else.
  void activateLast() => activateAt(state.sessionCount - 1);

  /// Moves the tab at [from] so it sits at [to], keeping the same session
  /// active however the strip is rearranged.
  void moveSession(int from, int to) {
    final sessions = [...state.sessions];
    if (from < 0 || from >= sessions.length) {
      throw RangeError.index(from, sessions, 'from');
    }
    if (to < 0 || to >= sessions.length) {
      throw RangeError.index(to, sessions, 'to');
    }
    if (from == to) return;
    sessions.insert(to, sessions.removeAt(from));
    state = state.copyWith(sessions: sessions);
  }

  /// The open session already showing [path], or `null`.
  DocumentSession? sessionForPath(String path) {
    for (final session in state.sessions) {
      if (session.filePath == path) return session;
    }
    return null;
  }

  /// Records that the session with [id] now lives at [path].
  ///
  /// [markClean] is false when the document changed while it was being
  /// written: it now has a home, but what is on screen is not what is on disk.
  void setFilePath(String id, String path, {bool markClean = true}) {
    final session = state.sessionById(id);
    if (session == null) return;
    final moved = session.withFilePath(path);
    _replaceSession(markClean ? moved.markSaved() : moved);
  }

  /// Marks a just-opened session as holding recovered work.
  ///
  /// It has a file path, but what is on screen came from the autosave sidecar
  /// and has never been written into that file — so it must count as dirty.
  void markRecovered(String id) {
    final session = state.sessionById(id);
    if (session == null || session.isDirty) return;
    _replaceSession(session.markUnsaved());
  }

  /// Swaps in a new value for a session that is already open, active or not.
  void _replaceSession(DocumentSession session) {
    final index = state.indexOfSession(session.id);
    if (index == -1) return;
    final next = [...state.sessions];
    next[index] = session;
    state = state.copyWith(sessions: next);
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

  /// Replaces the active session's view transform. Never a command: zooming
  /// to 800% and back must leave the document — and the undo stack — alone.
  void setView(ViewTransform view) =>
      _updateActive(state.activeSession.withView(view));

  /// Drags the page by [dx], [dy] screen pixels.
  void panBy(double dx, double dy) =>
      setView(state.activeSession.view.pannedBy(dx, dy));

  /// Puts the whole page back in the viewport, centred. Ctrl+0.
  void resetView() => setView(ViewTransform.initial);

  /// Turns the active session's fit-to-window preference on or off.
  ///
  /// A view preference, not a document change, so it is not undoable.
  void setFitToWindow(bool value) =>
      _updateActive(state.activeSession.withFitToWindow(value));

  /// Resizes the active session's canvas as an undoable command.
  ///
  /// For a resize the *user* asked for. The window-follow path uses
  /// [fitCanvasToWindow] instead.
  void resizeCanvas(int width, int height) {
    final command = _resizeCommand(width, height);
    if (command != null) run(command);
  }

  /// Resizes the canvas to follow the window, **without** an undo entry.
  ///
  /// Deliberately not a command. Undoing a window-driven resize would shrink
  /// the document back while the window stayed put, the layout would notice the
  /// mismatch and resize it again, and undo would fight the window forever.
  /// Like zoom, this is the view adapting; unlike zoom, it must rewrite the
  /// document, because the canvas size *is* document state.
  void fitCanvasToWindow(int width, int height) {
    final command = _resizeCommand(width, height);
    if (command == null) return;
    final session = state.activeSession;
    _updateActive(session.withDocument(command.apply(session.document)));
  }

  /// `null` when the canvas already has that size, which is what stops the
  /// widget's layout pass from resizing forever.
  ResizeCanvasCommand? _resizeCommand(int width, int height) {
    final document = state.activeSession.document;
    if (document.canvasWidth == width && document.canvasHeight == height) {
      return null;
    }
    return ResizeCanvasCommand(
      oldWidth: document.canvasWidth,
      oldHeight: document.canvasHeight,
      newWidth: width,
      newHeight: height,
      oldLayers: document.layers,
    );
  }

  // ---------------------------------------------------------------------
  // Selection
  // ---------------------------------------------------------------------

  /// Replaces the selection. Not undoable: selecting is a view concern.
  void setSelection(Set<String> ids) =>
      _updateActive(state.activeSession.withSelection(ids));

  void clearSelection() => setSelection(const {});

  /// Adds [id] to the selection, or removes it if already there.
  void toggleSelected(String id) {
    final next = {...state.activeSession.selection};
    if (!next.remove(id)) next.add(id);
    setSelection(next);
  }

  void selectAll() => setSelection({
    for (final layer in state.activeSession.document.layers)
      if (layer.visible)
        for (final element in layer.elements) element.id,
  });

  /// Shows [elements] in place of their originals, **without** an undo entry.
  ///
  /// A drag calls this once per frame and pushes a single command when the
  /// pointer lifts. Pushing per frame would bury the undo stack under a
  /// hundred entries for one gesture.
  void previewElements(List<CanvasElement> elements) {
    if (elements.isEmpty) return;
    final session = state.activeSession;
    _updateActive(
      session.withDocument(replaceElements(session.document, elements)),
    );
  }

  /// Commits a drag as one undo entry, from the geometry captured when it
  /// began. The document already shows the result, so `apply` is a no-op in
  /// effect — but the command holds the `before` state that undo needs.
  void commitMove(List<CanvasElement> before, double dx, double dy) {
    if (before.isEmpty || (dx == 0 && dy == 0)) return;
    run(MoveElementsCommand(before: before, dx: dx, dy: dy));
  }

  void commitResize(
    List<CanvasElement> before,
    double factor,
    double originX,
    double originY,
  ) {
    if (before.isEmpty || factor == 1) return;
    run(
      ResizeElementsCommand(
        before: before,
        factor: factor,
        originX: originX,
        originY: originY,
      ),
    );
  }

  /// Commits a side-handle drag: the box changed, the style did not.
  void commitResizeBox(CanvasElement before, Bounds box) {
    if (box.width <= 0 || box.height <= 0) return;
    // A drag that ended where it began: nothing to undo.
    if (before.bounds == box) return;
    run(ResizeBoxCommand(before: [before], box: box));
  }

  void commitRotate(
    List<CanvasElement> before,
    double radians,
    double originX,
    double originY,
  ) {
    if (before.isEmpty || radians == 0) return;
    run(
      RotateElementsCommand(
        before: before,
        radians: radians,
        originX: originX,
        originY: originY,
      ),
    );
  }

  /// Moves the selection by ([dx], [dy]).
  void moveSelection(double dx, double dy) {
    final before = state.activeSession.selectedElements;
    if (before.isEmpty || (dx == 0 && dy == 0)) return;
    run(MoveElementsCommand(before: before, dx: dx, dy: dy));
  }

  /// Scales the selection about an anchor.
  void resizeSelection(double factor, double originX, double originY) {
    final before = state.activeSession.selectedElements;
    if (before.isEmpty || factor == 1) return;
    run(
      ResizeElementsCommand(
        before: before,
        factor: factor,
        originX: originX,
        originY: originY,
      ),
    );
  }

  /// Rotates the selection about a point.
  void rotateSelection(double radians, double originX, double originY) {
    final before = state.activeSession.selectedElements;
    if (before.isEmpty || radians == 0) return;
    run(
      RotateElementsCommand(
        before: before,
        radians: radians,
        originX: originX,
        originY: originY,
      ),
    );
  }

  /// Restyles the selected shapes. Strokes in the selection are untouched.
  void styleSelection({
    int? strokeColorRGBA,
    int? fillColorRGBA,
    double? strokeWidth,
    StrokeStyle? strokeStyle,
    ShapeRenderStyle? renderStyle,
  }) {
    final before = state.activeSession.selectedElements
        .whereType<Shape>()
        .toList();
    if (before.isEmpty) return;
    run(
      StyleElementsCommand(
        before: before,
        strokeColorRGBA: strokeColorRGBA,
        fillColorRGBA: fillColorRGBA,
        strokeWidth: strokeWidth,
        strokeStyle: strokeStyle,
        renderStyle: renderStyle,
      ),
    );
  }

  /// Deletes everything selected, and clears the selection.
  void deleteSelection() {
    final session = state.activeSession;
    if (session.selection.isEmpty) return;

    final removed = <({String layerId, int index, CanvasElement element})>[];
    final frozenBefore = <CanvasElement>[];
    final frozenAfter = <CanvasElement>[];

    for (final layer in session.document.layers) {
      for (var i = 0; i < layer.elements.length; i++) {
        final element = layer.elements[i];
        if (session.selection.contains(element.id)) {
          removed.add((layerId: layer.id, index: i, element: element));
          continue;
        }
        // A surviving connector bound to something being deleted stops
        // following it, and stays where it currently is.
        if (element is Connector &&
            element.boundIds.any(session.selection.contains)) {
          final survivors = element.boundIds.difference(session.selection);
          frozenBefore.add(element);
          frozenAfter.add(
            freezeBindingsOutside(element, survivors, layer.elements),
          );
        }
      }
    }

    run(
      DeleteElementsCommand(
        removed: removed,
        frozenBefore: frozenBefore,
        frozenAfter: frozenAfter,
      ),
    );
    clearSelection();
  }

  /// Wraps the selection into a group, and selects it. Ctrl+G.
  ///
  /// Everything must live on one layer: a group spanning layers would have no
  /// z-position, and no answer to which layer's opacity applies to it.
  void groupSelection() {
    final session = state.activeSession;
    final ids = session.selection;
    if (ids.length < 2) return;

    final layers = [
      for (final layer in session.document.layers)
        if (layer.elements.any((e) => ids.contains(e.id))) layer,
    ];
    if (layers.length != 1) return;

    final layer = layers.single;
    final present = {
      for (final element in layer.elements)
        if (ids.contains(element.id)) element.id,
    };
    if (present.length < 2) return;

    final groupId = const Uuid().v4();
    run(
      GroupElementsCommand(
        layerId: layer.id,
        groupId: groupId,
        memberIds: present,
      ),
    );
    setSelection({groupId});
  }

  /// Splices the selected groups' children back into their layer. Ctrl+Shift+G.
  ///
  /// Anything selected that is not a group is left alone and stays selected.
  void ungroupSelection() {
    final session = state.activeSession;
    final freed = <String>{};

    for (final layer in session.document.layers) {
      for (final element in layer.elements) {
        if (element is! Group || !session.selection.contains(element.id)) {
          continue;
        }
        run(UngroupElementsCommand(layerId: layer.id, groupId: element.id));
        freed.addAll(element.children.map((child) => child.id));
      }
    }
    if (freed.isEmpty) return;

    setSelection({
      ...session.selection.where(
        (id) => state.activeSession.document.findElement(id) != null,
      ),
      ...freed,
    });
  }

  /// Copies the selection, offset by ([dx], [dy]), and selects the copies.
  ///
  /// The copies land on the active layer, whichever layers the originals came
  /// from — a duplicate you cannot see would be a bad surprise.
  void duplicateSelection({double dx = 10, double dy = 10}) {
    final session = state.activeSession;
    final originals = session.selectedElements;
    if (originals.isEmpty) return;

    const uuid = Uuid();
    // Fresh ids for the whole selection at once: a copied connector must bind
    // to the copied shape beside it, not to the original it was drawn against.
    final copies = withFreshIdsAll([
      for (final element in originals) element.translated(dx, dy),
    ], uuid.v4);

    run(
      DuplicateElementsCommand(layerId: session.activeLayerId, copies: copies),
    );
    setSelection({for (final copy in copies) copy.id});
  }

  /// Moves the single selected element within its layer's z-order.
  ///
  /// `toEnd` sends it all the way to the front or the back.
  void reorderSelected({required bool forward, bool toEnd = false}) {
    final session = state.activeSession;
    if (session.selection.length != 1) return;

    final id = session.selection.single;
    final found = session.document.findElement(id);
    if (found == null) return;

    final layer = found.layer;
    final index = layer.indexOfElement(id);
    final last = layer.elementCount - 1;
    final target = toEnd
        ? (forward ? last : 0)
        : (forward ? index + 1 : index - 1);
    if (target < 0 || target > last || target == index) return;

    run(
      ReorderElementCommand(
        layerId: layer.id,
        oldIndex: index,
        newIndex: target,
      ),
    );
  }

  // ---------------------------------------------------------------------
  // Text
  // ---------------------------------------------------------------------

  /// Commits an editing session's runs as one undo entry.
  ///
  /// Typing pushes nothing; the whole session collapses into a single command
  /// when the box loses focus, so undo steps back an edit rather than a
  /// keystroke.
  void commitTextEdit(TextElement before, List<TextRun> after) {
    if (TextElement.normalizeRuns(after) == before.runs) return;
    run(EditTextCommand(before: before, after: after));
  }

  /// Writes the in-progress text edit into the document and ends the session.
  ///
  /// A box typed into becomes an [EditTextCommand]; a box left empty is a
  /// mis-click and is removed. A no-op when nothing is being edited.
  ///
  /// This exists so any *new* interaction — clicking elsewhere on the canvas,
  /// switching tools, starting another text box — can flush the pending edit
  /// **synchronously, first**. Relying on the editor's focus-loss alone loses
  /// the text: starting a second box replaces the editing session before the
  /// first field's blur is delivered, so the blur then commits the wrong (new,
  /// empty) box and the typed text is dropped.
  void flushTextEdit() {
    final editing = ref.read(textEditingProvider);
    if (editing == null) return;
    if (editing.text.isEmpty) {
      setSelection({editing.elementId});
      deleteSelection();
    } else {
      commitTextEdit(editing.original, editing.runs);
    }
    ref.read(textEditingProvider.notifier).end();
  }

  /// Applies bold/italic/underline to a range of a text element.
  void styleTextRange(
    TextElement before,
    int start,
    int end, {
    bool? bold,
    bool? italic,
    bool? underline,
  }) {
    if (end <= start) return;
    run(
      StyleTextRunsCommand(
        before: before,
        start: start,
        end: end,
        bold: bold,
        italic: italic,
        underline: underline,
      ),
    );
  }

  /// Sets (or clears, when null) the font size of a text range.
  void styleTextRangeFontSize(
    TextElement before,
    int start,
    int end,
    double? fontSize,
  ) {
    if (end <= start) return;
    run(
      StyleTextRunsCommand(
        before: before,
        start: start,
        end: end,
        fontSize: fontSize,
        setFontSize: true,
      ),
    );
  }

  /// Sets (or clears, when null) the colour of a text range.
  void styleTextRangeColor(
    TextElement before,
    int start,
    int end,
    int? colorRGBA,
  ) {
    if (end <= start) return;
    run(
      StyleTextRunsCommand(
        before: before,
        start: start,
        end: end,
        colorRGBA: colorRGBA,
        setColor: true,
      ),
    );
  }

  /// Sets the whole selected text element's list style.
  void setTextListStyle(TextElement before, ListStyle style) {
    if (before.listStyle == style) return;
    run(StyleTextElementCommand(before: before, listStyle: style));
  }

  /// Flows the selected text along a selected sibling, or detaches it.
  ///
  /// Binds when the selection is one text element plus one element with a
  /// resolvable outline (a shape, connector or stroke) on the same layer;
  /// unbinds when the only text selected is already on a path. Anything else
  /// does nothing.
  void toggleTextOnPath() {
    final session = state.activeSession;
    final selected = session.selectedElements;
    final texts = selected.whereType<TextElement>().toList();
    if (texts.length != 1) return;
    final text = texts.single;

    if (text.isOnPath) {
      run(BindTextToPathCommand(before: text, pathElementId: null));
      return;
    }

    // The other selected element must have an outline and share the layer.
    final layer = session.document.findElement(text.id)?.layer;
    if (layer == null) return;
    final targets = [
      for (final element in selected)
        if (element.id != text.id &&
            layer.elements.any((e) => e.id == element.id) &&
            outlinePathFor(element, layer.elements) != null)
          element,
    ];
    if (targets.length != 1) return;

    run(BindTextToPathCommand(before: text, pathElementId: targets.single.id));
  }

  /// Changes a text element's family, size, colour, or alignment.
  void styleTextElement(
    TextElement before, {
    String? fontFamily,
    double? fontSize,
    int? colorRGBA,
    TextAlignment? align,
  }) => run(
    StyleTextElementCommand(
      before: before,
      fontFamily: fontFamily,
      fontSize: fontSize,
      colorRGBA: colorRGBA,
      align: align,
    ),
  );

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
