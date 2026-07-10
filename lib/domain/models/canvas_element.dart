import 'dart:math' as math;

import 'package:inkpad/domain/models/bounds.dart';
import 'package:inkpad/domain/models/stroke_point.dart';

// Dart requires every subtype of a sealed class to live in the same library,
// which is what makes `switch` over CanvasElement exhaustive. Parts inherit
// these imports; they cannot declare their own.
part 'shape.dart';
part 'stroke.dart';

/// Anything that can live in a `Layer`: a freehand [Stroke] or a parametric
/// [Shape]. Elements are immutable; mutate by producing a copy.
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
}
