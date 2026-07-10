import 'package:inkpad/domain/models/bounds.dart';
import 'package:inkpad/domain/models/canvas_element.dart';

/// Whether dragging a *side* handle can change [element]'s box on one axis.
///
/// Only boxed elements qualify, and only while unrotated: a rotated element's
/// [CanvasElement.bounds] is its axis-aligned hull, so dragging that hull's
/// edge says nothing about which of the element's own sides should move.
/// A stroke has no box at all — widening one would have to resample its points
/// and leave its width undefined — so a side handle falls back to a uniform
/// scale for anything this rejects.
bool canResizeBox(CanvasElement element) => switch (element) {
  Stroke() => false,
  Shape(rotation: final rotation) => rotation == 0,
  TextElement(rotation: final rotation) => rotation == 0,
  // A connector has endpoints, not a box; a group has children whose own boxes
  // are what would have to change, and one axis of a group is not one axis of
  // each child. Both fall back to the uniform scale.
  Connector() || Group() => false,
};

/// [element] moved and sized to fill [box], with its *style* untouched.
///
/// This is the difference between a side handle and a corner one. A corner
/// scales the element, and a text element's `fontSize` scales with it, so the
/// text magnifies. A side handle only changes the box, so the same type
/// rewraps into the new width — which is what task 10.6 asks for.
///
/// Throws if [canResizeBox] is false for [element].
CanvasElement elementWithBox(CanvasElement element, Bounds box) =>
    switch (element) {
      Stroke() => throw ArgumentError('a stroke has no box to resize'),
      Connector() => throw ArgumentError('a connector has no box to resize'),
      Group() => throw ArgumentError('a group resizes through its children'),
      Shape() => element.copyWith(
        x: box.left,
        y: box.top,
        w: box.width,
        h: box.height,
      ),
      TextElement() => element.copyWith(
        x: box.left,
        y: box.top,
        w: box.width,
        h: box.height,
      ),
    };
