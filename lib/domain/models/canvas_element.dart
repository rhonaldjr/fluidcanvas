import 'dart:math' as math;

import 'package:inkpad/domain/models/bounds.dart';
import 'package:inkpad/domain/models/stroke_point.dart';

// Dart requires every subtype of a sealed class to live in the same library,
// which is what makes `switch` over CanvasElement exhaustive. Parts inherit
// these imports; they cannot declare their own.
part 'shape.dart';
part 'text_element.dart';
part 'stroke.dart';

/// Anything that can live in a `Layer`: a freehand [Stroke], a parametric
/// [Shape], or a [TextElement]. Elements are immutable; mutate by producing a
/// copy.
///
/// This type is **sealed**. Adding a variant means updating the codec, the
/// renderer, and hit-testing — the compiler will point at every switch that
/// needs a new case.
sealed class CanvasElement {
  const CanvasElement({required this.id});

  /// Unique within a document. Not persisted: `.skd` regenerates ids on load,
  /// so nothing in the file format may reference an element by id.
  final String id;

  /// The tight box around this element's geometry, or `null` when it has none
  /// (a stroke with no points).
  ///
  /// Ignores stroke width — this is where the geometry is, not where the ink
  /// lands. Callers that care about painted extent should [Bounds.inflate] by
  /// half the stroke width.
  Bounds? get bounds;

  /// A copy scaled uniformly by [factor] about ([originX], [originY]).
  ///
  /// Uniform only: a non-uniform scale has no correct meaning for a rotated
  /// shape, which it would shear rather than resize. Stroke and outline widths
  /// scale too, so the element keeps its proportions.
  CanvasElement scaled(double factor, {double originX = 0, double originY = 0});

  /// A copy moved by ([dx], [dy]) in document space.
  CanvasElement translated(double dx, double dy);

  /// A copy rotated by [radians] clockwise about ([originX], [originY]).
  ///
  /// A [Shape] stores its angle, so it rotates in place. A [Stroke] has no
  /// angle to store, so its points are rotated instead.
  CanvasElement rotated(
    double radians, {
    required double originX,
    required double originY,
  });
}
