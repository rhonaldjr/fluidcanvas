import 'package:inkpad/domain/models/models.dart';

/// Points emitted per curve segment. Higher is smoother and costlier.
const int kSmoothingSamples = 4;

/// Incremental quadratic-midpoint smoothing of a stroke.
///
/// Each interior input point becomes the control point of a quadratic Bézier
/// running between the midpoints of its neighbouring segments. Consecutive
/// segments therefore share an endpoint, so the curve is continuous.
///
/// Chosen over Catmull-Rom because every emitted point is a *convex
/// combination* of three inputs: the curve can never overshoot the input's
/// bounding box, and interpolated pressure stays within 0..1 without clamping.
/// Catmull-Rom passes through its inputs but overshoots around sharp corners.
///
/// Feed points as they arrive; each [add] returns only the newly emitted
/// points, so the caller appends rather than recomputing. Call [finish] on
/// pointer-up to emit the final input point, which is otherwise still pending.
class StrokeSmoother {
  StrokeSmoother({this.samplesPerSegment = kSmoothingSamples})
    : assert(samplesPerSegment >= 1, 'need at least one sample per segment');

  final int samplesPerSegment;

  /// The two most recent input points.
  StrokePoint? _previous;
  StrokePoint? _beforePrevious;

  int _inputCount = 0;
  bool _emittedFirstSegment = false;
  bool _finished = false;

  /// How many points have been fed in.
  int get inputCount => _inputCount;

  /// Feeds one input point, returning the points to append to the output.
  ///
  /// The first input is emitted immediately. The second emits nothing: a
  /// segment needs three points to have a control point. From the third on,
  /// each input completes one curve segment.
  List<StrokePoint> add(StrokePoint point) {
    assert(!_finished, 'cannot add to a finished smoother');
    _inputCount++;

    if (_previous == null) {
      _previous = point;
      return [point];
    }

    if (_beforePrevious == null) {
      _beforePrevious = _previous;
      _previous = point;
      return const [];
    }

    final start = _midpoint(_beforePrevious!, _previous!);
    final control = _previous!;
    final end = _midpoint(_previous!, point);

    final emitted = <StrokePoint>[];
    // The very first segment must also emit its start; later segments begin
    // where the previous one ended, so emitting it again would duplicate.
    if (!_emittedFirstSegment) {
      emitted.add(start);
      _emittedFirstSegment = true;
    }
    for (var i = 1; i <= samplesPerSegment; i++) {
      emitted.add(_quadratic(start, control, end, i / samplesPerSegment));
    }

    _beforePrevious = _previous;
    _previous = point;
    return emitted;
  }

  /// Emits the final input point, which no segment has reached yet.
  ///
  /// Returns nothing for a stroke of fewer than two points, whose only point
  /// [add] already emitted.
  List<StrokePoint> finish() {
    assert(!_finished, 'finish may only be called once');
    _finished = true;
    if (_inputCount < 2) return const [];
    return [_previous!];
  }
}

/// Smooths a complete stroke. Equivalent to feeding every point to a
/// [StrokeSmoother] and calling `finish`.
///
/// For `n >= 3` inputs and `s` samples the output holds `3 + s * (n - 2)`
/// points; for `n <= 2` it returns the input unchanged.
List<StrokePoint> smoothStroke(
  List<StrokePoint> points, {
  int samplesPerSegment = kSmoothingSamples,
}) {
  final smoother = StrokeSmoother(samplesPerSegment: samplesPerSegment);
  final out = <StrokePoint>[];
  for (final point in points) {
    out.addAll(smoother.add(point));
  }
  return out..addAll(smoother.finish());
}

StrokePoint _midpoint(StrokePoint a, StrokePoint b) => StrokePoint(
  x: (a.x + b.x) / 2,
  y: (a.y + b.y) / 2,
  pressure: (a.pressure + b.pressure) / 2,
);

/// A point on the quadratic Bézier through [start] and [end] with control
/// [control], at parameter [t] in 0..1.
///
/// The three weights are non-negative and sum to 1, which is what keeps the
/// result inside the triangle of its inputs — and pressure inside 0..1.
StrokePoint _quadratic(
  StrokePoint start,
  StrokePoint control,
  StrokePoint end,
  double t,
) {
  final u = 1 - t;
  final w0 = u * u;
  final w1 = 2 * u * t;
  final w2 = t * t;

  return StrokePoint(
    x: w0 * start.x + w1 * control.x + w2 * end.x,
    y: w0 * start.y + w1 * control.y + w2 * end.y,
    // Clamped only against floating-point drift; the weights guarantee 0..1.
    pressure: (w0 * start.pressure + w1 * control.pressure + w2 * end.pressure)
        .clamp(0.0, 1.0),
  );
}
