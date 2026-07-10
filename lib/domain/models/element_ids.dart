import 'package:inkpad/domain/models/canvas_element.dart';

/// [element] with a fresh id, and fresh ids for everything inside it.
///
/// Duplicating a group must not reuse its children's ids — a document with two
/// elements sharing an id has no answer to "which one did you click". And a
/// connector inside the copy must bind to the *copy* of the shape it joined,
/// not to the original, or dragging the duplicate would drag a line anchored to
/// something else.
///
/// [newId] mints one id per call; pass a deterministic one in tests.
CanvasElement withFreshIds(CanvasElement element, String Function() newId) =>
    withFreshIdsAll([element], newId).single;

/// [elements] with fresh ids throughout, rebound **as a set**.
///
/// Duplicating a shape together with the connector that joins it rebinds the
/// copied connector onto the copied shape. A connector copied *without* its
/// shape keeps pointing at the original, which is still there.
List<CanvasElement> withFreshIdsAll(
  List<CanvasElement> elements,
  String Function() newId,
) {
  final remap = <String, String>{};
  final freshened = [
    for (final element in elements) _freshen(element, newId, remap),
  ];
  return _rebindAll(freshened, remap);
}

CanvasElement _freshen(
  CanvasElement element,
  String Function() newId,
  Map<String, String> remap,
) {
  final id = newId();
  remap[element.id] = id;

  return switch (element) {
    Stroke() => element.copyWith(id: id),
    Shape() => element.copyWith(id: id),
    TextElement() => element.copyWith(id: id),
    Connector() => element.copyWith(id: id),
    // Children keep their own bindings; `withFreshIdsAll` rebinds the whole
    // tree once every id inside it is known.
    Group() => element.copyWith(
      id: id,
      children: [
        for (final child in element.children) _freshen(child, newId, remap),
      ],
    ),
  };
}

/// Points every connector in [elements] at the new ids in [remap].
///
/// A binding to something outside [remap] — a shape that was not copied — is
/// left alone: it still names a real element in the document.
List<CanvasElement> _rebindAll(
  List<CanvasElement> elements,
  Map<String, String> remap,
) => [for (final element in elements) rebindConnector(element, remap)];

/// [element] with its connector bindings mapped through [remap].
CanvasElement rebindConnector(
  CanvasElement element,
  Map<String, String> remap,
) => switch (element) {
  Connector() => element.copyWith(
    start: _rebindEnd(element.start, remap),
    end: _rebindEnd(element.end, remap),
  ),
  Group() => element.copyWith(
    children: [
      for (final child in element.children) rebindConnector(child, remap),
    ],
  ),
  Stroke() || Shape() || TextElement() => element,
};

ConnectorEnd _rebindEnd(ConnectorEnd end, Map<String, String> remap) {
  final to = end.isBound ? remap[end.elementId] : null;
  return to == null ? end : ConnectorEnd.bound(to);
}
