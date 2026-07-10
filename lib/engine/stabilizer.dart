import 'package:inkpad/domain/models/models.dart';
import 'package:inkpad/engine/thinning.dart';

/// Strongest stabilization the toolbar offers.
const int kMaxStabilizerStrength = 10;

/// Document pixels of lag added per unit of strength.
const double kStabilizerRadiusPerUnit = 4;

/// A pull-string stabilizer: the pen drags an anchor behind it on a taut
/// string of length `strength * kStabilizerRadiusPerUnit`.
///
/// Movement inside that radius is slack and emits nothing, which is what kills
/// hand tremor. Movement beyond it drags the anchor along, always leaving it
/// exactly `radius` behind the cursor. Strength 0 disables the effect entirely
/// and passes every point straight through.
///
/// Distinct from smoothing: the smoother interpolates *between* the points it
/// is given, while this decides *which* points exist at all. Stabilization runs
/// first.
class Stabilizer {
  Stabilizer({this.strength = 0})
    : assert(
        strength >= 0 && strength <= kMaxStabilizerStrength,
        'strength must be in 0..$kMaxStabilizerStrength',
      );

  final int strength;

  /// Length of the string, in document pixels.
  double get radius => strength * kStabilizerRadiusPerUnit;

  bool get isEnabled => strength > 0;

  StrokePoint? _anchor;
  StrokePoint? _lastRaw;

  /// Feeds one raw point, returning the stabilized point to draw, or `null`
  /// when the movement was slack.
  StrokePoint? process(StrokePoint raw) {
    _lastRaw = raw;
    if (!isEnabled) return raw;

    final anchor = _anchor;
    if (anchor == null) {
      _anchor = raw;
      return raw;
    }

    final distance = distanceBetween(anchor, raw);
    if (distance <= radius) return null;

    // Drag the anchor along the string until it sits `radius` behind the pen.
    final t = (distance - radius) / distance;
    final next = StrokePoint(
      x: anchor.x + (raw.x - anchor.x) * t,
      y: anchor.y + (raw.y - anchor.y) * t,
      pressure: raw.pressure,
    );
    _anchor = next;
    return next;
  }

  /// The point to append on pointer-up, so the stroke ends under the cursor
  /// rather than a string's length behind it. `null` when nothing is pending.
  StrokePoint? finish() {
    if (!isEnabled) return null;
    final raw = _lastRaw;
    final anchor = _anchor;
    if (raw == null || anchor == null) return null;
    if (distanceBetween(anchor, raw) == 0) return null;
    _anchor = raw;
    return raw;
  }
}

/// Runs a whole stroke through a [Stabilizer]. Equivalent to feeding each point
/// to [Stabilizer.process] and appending [Stabilizer.finish].
List<StrokePoint> stabilizePoints(
  List<StrokePoint> points, {
  int strength = 0,
}) {
  final stabilizer = Stabilizer(strength: strength);
  final out = <StrokePoint>[];
  for (final point in points) {
    final stabilized = stabilizer.process(point);
    if (stabilized != null) out.add(stabilized);
  }
  final tail = stabilizer.finish();
  if (tail != null) out.add(tail);
  return out;
}
