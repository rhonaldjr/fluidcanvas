/// Pure geometry for a `Connector`: where a bound end lands.
///
/// Lives in `domain/`, not `engine/`: the commands that group and delete
/// elements need it, and `domain/` may not depend on `engine/`. It touches no
/// Flutter type — a connector's endpoints are two numbers, not a `ui.Path`.
library;

import 'dart:math' as math;

import 'package:inkpad/domain/models/bounds.dart';
import 'package:inkpad/domain/models/canvas_element.dart';

/// Gap between a connector's tip and the box it points at, in document pixels.
///
/// Without it the arrowhead is buried in the shape's outline.
const double kConnectorGap = 4;

/// A connector's two endpoints, resolved against the elements it binds to.
typedef ResolvedConnector = ({double x1, double y1, double x2, double y2});

/// The elements a connector may bind to: the container's own list.
///
/// Connectors bind to *siblings* — the top-level elements of the layer or group
/// they live in. Anything else would need the file format to reference an
/// element across containers, and ids are not persisted.
Map<String, Bounds> anchorBoxes(List<CanvasElement> siblings) => {
  for (final element in siblings)
    if (element is! Connector)
      if (element.bounds != null) element.id: element.bounds!,
};

/// Where [connector]'s ends land, given its siblings.
///
/// A bound end sits where the line between the two anchors crosses the bound
/// element's box, pushed out by [kConnectorGap]. So the connector always points
/// *at* the shape and stops at its edge, from whatever direction it approaches.
///
/// A binding that names no sibling — the element was deleted, or left behind by
/// a grouping — falls back to that element's last known centre if we have one,
/// and otherwise to the other end's position, which draws nothing rather than
/// throwing.
ResolvedConnector resolveConnector(
  Connector connector,
  List<CanvasElement> siblings,
) {
  final boxes = anchorBoxes(siblings);

  final startBox = _boxFor(connector.start, boxes);
  final endBox = _boxFor(connector.end, boxes);

  // Each end aims at the other's centre. A bound end's centre is its box's; a
  // free end is its own point.
  final startCentre = _centre(connector.start, startBox);
  final endCentre = _centre(connector.end, endBox);

  final dx = endCentre.$1 - startCentre.$1;
  final dy = endCentre.$2 - startCentre.$2;
  final length = math.sqrt(dx * dx + dy * dy);

  // The two anchors sit on top of each other: there is no direction to leave in.
  if (length < 1e-9) {
    return (
      x1: startCentre.$1,
      y1: startCentre.$2,
      x2: endCentre.$1,
      y2: endCentre.$2,
    );
  }

  final ux = dx / length;
  final uy = dy / length;

  // How far along the line each box's wall is, from its own end.
  final tStart = startBox == null
      ? 0.0
      : _exitDistance(startBox, startCentre, ux, uy);
  final tEnd = endBox == null
      ? 0.0
      : _exitDistance(endBox, endCentre, -ux, -uy);

  // The gap is shared, not applied twice. Two boxes a hair apart would
  // otherwise push their tips past each other and draw the arrow backwards.
  final free = length - tStart - tEnd;
  final gap = free <= 0 ? 0.0 : math.min(kConnectorGap, free / 2);

  // A free end is exactly where the user put it: only a bound end stands off
  // from the box it points at.
  final startReach = startBox == null ? 0.0 : math.min(tStart + gap, length);
  final endReach = endBox == null ? 0.0 : math.min(tEnd + gap, length);

  return (
    x1: startCentre.$1 + ux * startReach,
    y1: startCentre.$2 + uy * startReach,
    x2: endCentre.$1 - ux * endReach,
    y2: endCentre.$2 - uy * endReach,
  );
}

/// The bounds a connector end is bound to, or `null` when it is free or its
/// element has gone.
Bounds? _boxFor(ConnectorEnd end, Map<String, Bounds> boxes) =>
    end.isBound ? boxes[end.elementId] : null;

(double, double) _centre(ConnectorEnd end, Bounds? box) {
  if (box != null) return (box.centerX, box.centerY);
  // A free end, or a binding whose element is gone: draw it where it says.
  return (end.x ?? 0, end.y ?? 0);
}

/// How far a ray from [from] along the unit vector ([ux], [uy]) travels before
/// it leaves [box].
///
/// A slab clip rather than a per-edge intersection: the smallest `t` at which
/// the ray crosses a wall on either axis. It handles all four sides, the
/// corners, and an axis-aligned direction without special cases.
double _exitDistance(Bounds box, (double, double) from, double ux, double uy) {
  final tx = ux == 0
      ? double.infinity
      : ((ux > 0 ? box.right : box.left) - from.$1) / ux;
  final ty = uy == 0
      ? double.infinity
      : ((uy > 0 ? box.bottom : box.top) - from.$2) / uy;

  final t = math.min(tx, ty);
  // The centre is outside its own box only if the box is inverted.
  return t.isFinite && t > 0 ? t : 0;
}

/// The box a connector occupies once resolved. Used for selection and marquees.
Bounds connectorBounds(Connector connector, List<CanvasElement> siblings) {
  final r = resolveConnector(connector, siblings);
  return Bounds(
    left: math.min(r.x1, r.x2),
    top: math.min(r.y1, r.y2),
    right: math.max(r.x1, r.x2),
    bottom: math.max(r.y1, r.y2),
  );
}

/// [connector] with any binding to an element **not** in [keep] frozen where it
/// currently sits.
///
/// This is what deleting a bound shape does, and what grouping does to a
/// connector that reaches outside the new group: the end stops following and
/// stays where it was, rather than the connector losing an endpoint entirely.
Connector freezeBindingsOutside(
  Connector connector,
  Set<String> keep,
  List<CanvasElement> siblings,
) {
  if (!connector.isBound) return connector;

  final resolved = resolveConnector(connector, siblings);
  var next = connector;

  if (connector.start.isBound && !keep.contains(connector.start.elementId)) {
    next = next.copyWith(start: ConnectorEnd.free(resolved.x1, resolved.y1));
  }
  if (connector.end.isBound && !keep.contains(connector.end.elementId)) {
    next = next.copyWith(end: ConnectorEnd.free(resolved.x2, resolved.y2));
  }
  return next;
}
