part of 'canvas_element.dart';

/// Tool that drew a stroke. Stored as a `u8` in the `.skd` element blob, so the
/// numeric values are part of the file format and must never be reassigned.
abstract final class ToolId {
  static const int pen = 0;
  static const int eraser = 1;
}

/// A freehand stroke: an ordered run of pressure-sampled points.
class Stroke extends CanvasElement {
  Stroke({
    required super.id,
    required this.colorRGBA,
    required this.baseWidth,
    this.toolId = ToolId.pen,
    List<StrokePoint> points = const [],
  }) : assert(baseWidth > 0, 'baseWidth must be positive'),
       points = List.unmodifiable(points);

  /// Packed 0xRRGGBBAA, matching the `u32` in the `.skd` element blob.
  final int colorRGBA;

  /// Width in document pixels at full pressure.
  final double baseWidth;

  /// One of [ToolId].
  final int toolId;

  /// In document space, in the order they were sampled. Unmodifiable.
  final List<StrokePoint> points;

  bool get isEraser => toolId == ToolId.eraser;

  @override
  Bounds? get bounds {
    if (points.isEmpty) return null;

    var left = points.first.x;
    var right = left;
    var top = points.first.y;
    var bottom = top;

    for (final point in points.skip(1)) {
      if (point.x < left) left = point.x;
      if (point.x > right) right = point.x;
      if (point.y < top) top = point.y;
      if (point.y > bottom) bottom = point.y;
    }

    return Bounds(left: left, top: top, right: right, bottom: bottom);
  }

  Stroke copyWith({
    String? id,
    int? colorRGBA,
    double? baseWidth,
    int? toolId,
    List<StrokePoint>? points,
  }) => Stroke(
    id: id ?? this.id,
    colorRGBA: colorRGBA ?? this.colorRGBA,
    baseWidth: baseWidth ?? this.baseWidth,
    toolId: toolId ?? this.toolId,
    points: points ?? this.points,
  );

  /// A copy with [point] appended.
  ///
  /// Copies the whole point list, so this is O(n). Fine for committed strokes;
  /// the in-progress stroke accumulates through `engine/stroke_builder.dart`
  /// instead, which appends in place and only materializes a [Stroke] on
  /// pointer-up.
  Stroke addPoint(StrokePoint point) => copyWith(points: [...points, point]);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Stroke &&
          id == other.id &&
          colorRGBA == other.colorRGBA &&
          baseWidth == other.baseWidth &&
          toolId == other.toolId &&
          _pointsEqual(points, other.points);

  @override
  int get hashCode =>
      Object.hash(id, colorRGBA, baseWidth, toolId, Object.hashAll(points));

  @override
  String toString() =>
      'Stroke($id, toolId: $toolId, width: $baseWidth, points: ${points.length})';
}

bool _pointsEqual(List<StrokePoint> a, List<StrokePoint> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
