/// A single sampled point along a freehand stroke, in document space.
///
/// [pressure] is normalized to 0..1. Mice report no pressure, so the pointer
/// layer substitutes 1.0; it is also what clamps out-of-range device values,
/// which is why this type may assert on them.
class StrokePoint {
  const StrokePoint({required this.x, required this.y, this.pressure = 1.0})
    : assert(pressure >= 0.0 && pressure <= 1.0, 'pressure must be in 0..1');

  final double x;
  final double y;
  final double pressure;

  StrokePoint copyWith({double? x, double? y, double? pressure}) => StrokePoint(
    x: x ?? this.x,
    y: y ?? this.y,
    pressure: pressure ?? this.pressure,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is StrokePoint &&
          x == other.x &&
          y == other.y &&
          pressure == other.pressure;

  @override
  int get hashCode => Object.hash(x, y, pressure);

  @override
  String toString() => 'StrokePoint($x, $y, p: $pressure)';
}
