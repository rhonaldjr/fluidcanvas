part of 'canvas_element.dart';

/// The five predefined shapes.
///
/// [value] is the `u8` written to the `.skd` element blob. These numbers are
/// part of the file format: never reassign one, only append.
enum ShapeType {
  rectangle(0),
  ellipse(1),
  line(2),
  arrow(3),
  diamond(4);

  const ShapeType(this.value);

  final int value;

  /// Throws [ArgumentError] on an unknown value; the codec turns that into a
  /// format exception rather than silently guessing a shape.
  static ShapeType fromValue(int value) => values.firstWhere(
    (type) => type.value == value,
    orElse: () =>
        throw ArgumentError.value(value, 'value', 'unknown ShapeType'),
  );
}

/// How a shape's outline is drawn. [value] is the `u8` in the element blob.
enum StrokeStyle {
  solid(0),
  dashed(1),
  dotted(2);

  const StrokeStyle(this.value);

  final int value;

  static StrokeStyle fromValue(int value) => values.firstWhere(
    (style) => style.value == value,
    orElse: () =>
        throw ArgumentError.value(value, 'value', 'unknown StrokeStyle'),
  );
}

/// A parametric shape. Resizing changes [w] and [h]; it never resamples pixels.
///
/// [w] and [h] may be negative while a drag-to-create or a resize is in flight
/// — dragging left from the anchor produces a negative width. Call
/// [normalized] to fold that sign back into [x] and [y]. The `.skd` writer only
/// ever persists normalized shapes.
class Shape extends CanvasElement {
  const Shape({
    required super.id,
    required this.type,
    required this.x,
    required this.y,
    required this.w,
    required this.h,
    required this.strokeColorRGBA,
    required this.strokeWidth,
    this.rotation = 0,
    this.fillColorRGBA = 0,
    this.strokeStyle = StrokeStyle.solid,
  }) : assert(strokeWidth > 0, 'strokeWidth must be positive');

  final ShapeType type;

  /// Top-left corner of the unrotated box, in document space.
  final double x;
  final double y;

  /// Extents of the unrotated box. May be negative mid-drag; see [normalized].
  final double w;
  final double h;

  /// Radians, clockwise, about the box's center.
  final double rotation;

  /// Packed 0xRRGGBBAA.
  final int strokeColorRGBA;

  /// Packed 0xRRGGBBAA. An alpha of 0 means unfilled — see [isFilled].
  final int fillColorRGBA;

  final double strokeWidth;
  final StrokeStyle strokeStyle;

  /// Whether the shape paints an interior. Hit-testing uses this to decide
  /// between testing the filled region and testing the outline.
  bool get isFilled => (fillColorRGBA & 0xFF) != 0;

  bool get isRotated => rotation != 0;

  /// Center of the box, unaffected by the sign of [w] and [h].
  double get centerX => x + w / 2;
  double get centerY => y + h / 2;

  /// An equivalent shape with non-negative [w] and [h], the sign folded into
  /// [x] and [y]. The center, and therefore the rotation, is unchanged.
  Shape normalized() {
    if (w >= 0 && h >= 0) return this;
    return copyWith(
      x: w < 0 ? x + w : x,
      y: h < 0 ? y + h : y,
      w: w.abs(),
      h: h.abs(),
    );
  }

  /// The axis-aligned box around the shape, accounting for [rotation].
  ///
  /// For a rotated shape this is larger than `w` × `h`: it is the box around
  /// the four rotated corners. Ignores [strokeWidth], like every
  /// [CanvasElement.bounds].
  @override
  Bounds get bounds {
    final rect = normalized();

    if (!isRotated) {
      return Bounds(
        left: rect.x,
        top: rect.y,
        right: rect.x + rect.w,
        bottom: rect.y + rect.h,
      );
    }

    final cos = math.cos(rotation);
    final sin = math.sin(rotation);
    final cx = rect.centerX;
    final cy = rect.centerY;

    var left = double.infinity;
    var top = double.infinity;
    var right = double.negativeInfinity;
    var bottom = double.negativeInfinity;

    for (final (px, py) in [
      (rect.x, rect.y),
      (rect.x + rect.w, rect.y),
      (rect.x + rect.w, rect.y + rect.h),
      (rect.x, rect.y + rect.h),
    ]) {
      final dx = px - cx;
      final dy = py - cy;
      final rx = cx + dx * cos - dy * sin;
      final ry = cy + dx * sin + dy * cos;

      if (rx < left) left = rx;
      if (rx > right) right = rx;
      if (ry < top) top = ry;
      if (ry > bottom) bottom = ry;
    }

    return Bounds(left: left, top: top, right: right, bottom: bottom);
  }

  Shape copyWith({
    String? id,
    ShapeType? type,
    double? x,
    double? y,
    double? w,
    double? h,
    double? rotation,
    int? strokeColorRGBA,
    int? fillColorRGBA,
    double? strokeWidth,
    StrokeStyle? strokeStyle,
  }) => Shape(
    id: id ?? this.id,
    type: type ?? this.type,
    x: x ?? this.x,
    y: y ?? this.y,
    w: w ?? this.w,
    h: h ?? this.h,
    rotation: rotation ?? this.rotation,
    strokeColorRGBA: strokeColorRGBA ?? this.strokeColorRGBA,
    fillColorRGBA: fillColorRGBA ?? this.fillColorRGBA,
    strokeWidth: strokeWidth ?? this.strokeWidth,
    strokeStyle: strokeStyle ?? this.strokeStyle,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Shape &&
          id == other.id &&
          type == other.type &&
          x == other.x &&
          y == other.y &&
          w == other.w &&
          h == other.h &&
          rotation == other.rotation &&
          strokeColorRGBA == other.strokeColorRGBA &&
          fillColorRGBA == other.fillColorRGBA &&
          strokeWidth == other.strokeWidth &&
          strokeStyle == other.strokeStyle;

  @override
  int get hashCode => Object.hash(
    id,
    type,
    x,
    y,
    w,
    h,
    rotation,
    strokeColorRGBA,
    fillColorRGBA,
    strokeWidth,
    strokeStyle,
  );

  @override
  String toString() =>
      'Shape($id, ${type.name}, $x,$y ${w}x$h, rot: $rotation)';
}
