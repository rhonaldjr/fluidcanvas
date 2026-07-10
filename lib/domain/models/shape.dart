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

/// How a shape's outline is rendered. [value] is written into the first byte
/// the v1 spec reserved in the shape body, so a v1 reader ignores it and draws
/// the shape precisely — the drawing is still all there, just not wobbly.
enum ShapeRenderStyle {
  precise(0),
  rough(1);

  const ShapeRenderStyle(this.value);

  final int value;

  static ShapeRenderStyle fromValue(int value) => values.firstWhere(
    (style) => style.value == value,
    // A future style read by this build: draw it precisely rather than refuse
    // the file. Unlike an unknown elementType, this costs nothing to skip.
    orElse: () => ShapeRenderStyle.precise,
  );
}

/// A stable 32-bit hash of [id], used to seed a shape that becomes rough after
/// it was created.
///
/// Not `String.hashCode`: that is only stable within one run, and a redo must
/// reproduce exactly what the apply produced. FNV-1a is stable everywhere.
int seedFromId(String id) {
  var hash = 0x811C9DC5;
  for (final unit in id.codeUnits) {
    hash = (hash ^ unit) * 0x01000193;
    hash &= 0xFFFFFFFF;
  }
  return hash;
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
    this.renderStyle = ShapeRenderStyle.precise,
    this.seed = 0,
  }) : assert(strokeWidth > 0, 'strokeWidth must be positive'),
       assert(seed >= 0 && seed <= 0xFFFFFFFF, 'seed is a u32');

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

  /// Precise, or hand-drawn with seeded jitter.
  final ShapeRenderStyle renderStyle;

  /// Seeds the jitter of [ShapeRenderStyle.rough]. Meaningless when precise.
  ///
  /// Stored so a shape wobbles the same way on every machine and every
  /// repaint. Fixed at creation, and carried through every transform: resizing
  /// a rough rectangle must not reshuffle its strokes.
  final int seed;

  bool get isRough => renderStyle == ShapeRenderStyle.rough;

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

  /// Scaling leaves [rotation] alone: a uniform scale commutes with rotation,
  /// so the shape keeps its angle and simply grows about the origin.
  @override
  Shape scaled(double factor, {double originX = 0, double originY = 0}) {
    assert(factor > 0, 'scale factor must be positive');
    return copyWith(
      x: originX + (x - originX) * factor,
      y: originY + (y - originY) * factor,
      w: w * factor,
      h: h * factor,
      strokeWidth: strokeWidth * factor,
    );
  }

  @override
  Shape translated(double dx, double dy) => copyWith(x: x + dx, y: y + dy);

  /// The box's centre orbits the origin while the shape's own angle advances,
  /// so a rotated group turns as one rigid body.
  @override
  Shape rotated(
    double radians, {
    required double originX,
    required double originY,
  }) {
    final cos = math.cos(radians);
    final sin = math.sin(radians);
    final cx = centerX;
    final cy = centerY;
    final rx = originX + (cx - originX) * cos - (cy - originY) * sin;
    final ry = originY + (cx - originX) * sin + (cy - originY) * cos;

    return copyWith(
      x: x + (rx - cx),
      y: y + (ry - cy),
      rotation: rotation + radians,
    );
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
    ShapeRenderStyle? renderStyle,
    int? seed,
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
    renderStyle: renderStyle ?? this.renderStyle,
    seed: seed ?? this.seed,
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
          strokeStyle == other.strokeStyle &&
          renderStyle == other.renderStyle &&
          seed == other.seed;

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
    renderStyle,
    seed,
  );

  @override
  String toString() =>
      'Shape($id, ${type.name}, $x,$y ${w}x$h, rot: $rotation)';
}
