part of 'canvas_element.dart';

/// Several elements treated as one: selected together, moved as a rigid body,
/// deleted together.
///
/// Nestable. [children] are in z-order, bottom to top, exactly as a layer's
/// elements are — a group is a layer's worth of elements that happens to sit
/// inside one slot of another list.
///
/// A group has no style of its own. It has no fill, no stroke and no rotation
/// field: rotating a group rotates each child about the group's centre, so the
/// children carry the angle. That keeps `Group` a container rather than a
/// second, parallel notion of a shape.
class Group extends CanvasElement {
  Group({required super.id, required List<CanvasElement> children})
    : children = List.unmodifiable(children),
      assert(children.length >= 2, 'a group of fewer than two is not a group');

  /// Bottom to top, like [Layer.elements].
  final List<CanvasElement> children;

  /// Every element inside, at any depth, in z-order. Groups themselves are not
  /// included — only what they hold.
  List<CanvasElement> get leaves => [
    for (final child in children)
      if (child is Group) ...child.leaves else child,
  ];

  /// Ids of this group and everything under it.
  Set<String> get idsWithin => {
    id,
    for (final child in children)
      ...switch (child) {
        Group() => child.idsWithin,
        _ => {child.id},
      },
  };

  /// The union of the children's boxes. `null` only when no child has one,
  /// which takes a group of empty strokes.
  @override
  Bounds? get bounds {
    Bounds? result;
    for (final child in children) {
      final box = child.bounds;
      if (box == null) continue;
      result = result == null ? box : result.union(box);
    }
    return result;
  }

  @override
  Group scaled(double factor, {double originX = 0, double originY = 0}) =>
      copyWith(
        children: [
          for (final child in children)
            child.scaled(factor, originX: originX, originY: originY),
        ],
      );

  @override
  Group translated(double dx, double dy) => copyWith(
    children: [for (final child in children) child.translated(dx, dy)],
  );

  /// Every child turns about the *group's* origin, so the group turns as one
  /// rigid body rather than each child spinning in place.
  @override
  Group rotated(
    double radians, {
    required double originX,
    required double originY,
  }) => copyWith(
    children: [
      for (final child in children)
        child.rotated(radians, originX: originX, originY: originY),
    ],
  );

  Group copyWith({String? id, List<CanvasElement>? children}) =>
      Group(id: id ?? this.id, children: children ?? this.children);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Group &&
          id == other.id &&
          _sameChildren(children, other.children);

  @override
  int get hashCode => Object.hash(id, Object.hashAll(children));

  @override
  String toString() => 'Group($id, ${children.length} children)';
}

bool _sameChildren(List<CanvasElement> a, List<CanvasElement> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
