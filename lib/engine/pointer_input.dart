import 'dart:ui' show Offset;

import 'package:inkpad/domain/models/models.dart';

/// Maps a device's raw pressure onto the 0..1 that [StrokePoint] expects.
///
/// A mouse reports `min == max == 1.0`, meaning "no pressure information"; it
/// draws at full width. A stylus reports a real range, which we rescale.
/// Out-of-range and non-finite readings are clamped rather than trusted —
/// [StrokePoint] asserts on them, and a misbehaving driver should not crash the
/// app in debug.
double normalizePressure({
  required double pressure,
  required double min,
  required double max,
}) {
  if (!pressure.isFinite || max <= min) return 1.0;
  return ((pressure - min) / (max - min)).clamp(0.0, 1.0);
}

/// Converts a position local to the page widget into document space.
///
/// [scale] is the page's screen size divided by its document size. Phase 12
/// replaces this with the session's full pan/zoom transform.
StrokePoint documentPoint({
  required Offset local,
  required double scale,
  required double pressure,
}) {
  assert(scale > 0, 'cannot map into document space at zero scale');
  return StrokePoint(
    x: local.dx / scale,
    y: local.dy / scale,
    pressure: pressure,
  );
}
