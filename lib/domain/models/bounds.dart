/// An axis-aligned rectangle in document space.
///
/// `domain/` stays free of Flutter imports, so this stands in for `ui.Rect`.
/// Coordinates are logical pixels at 100% zoom; y grows downward.
class Bounds {
  const Bounds({
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
  }) : assert(left <= right, 'left must not exceed right'),
       assert(top <= bottom, 'top must not exceed bottom');

  /// A zero-size rectangle at a single point.
  const Bounds.point(double x, double y)
    : left = x,
      top = y,
      right = x,
      bottom = y;

  factory Bounds.fromLTWH(
    double left,
    double top,
    double width,
    double height,
  ) {
    assert(width >= 0, 'width must not be negative');
    assert(height >= 0, 'height must not be negative');
    return Bounds(
      left: left,
      top: top,
      right: left + width,
      bottom: top + height,
    );
  }

  final double left;
  final double top;
  final double right;
  final double bottom;

  double get width => right - left;
  double get height => bottom - top;
  double get centerX => left + width / 2;
  double get centerY => top + height / 2;

  /// True when the rectangle encloses no area — a point, or a zero-width line.
  bool get isDegenerate => width == 0 || height == 0;

  /// The smallest rectangle containing both `this` and [other].
  /// This box moved by ([dx], [dy]).
  Bounds translated(double dx, double dy) => Bounds(
    left: left + dx,
    top: top + dy,
    right: right + dx,
    bottom: bottom + dy,
  );

  Bounds union(Bounds other) => Bounds(
    left: left < other.left ? left : other.left,
    top: top < other.top ? top : other.top,
    right: right > other.right ? right : other.right,
    bottom: bottom > other.bottom ? bottom : other.bottom,
  );

  /// Grown by [amount] on every side. Renderers use this to account for stroke
  /// width, which [Bounds] itself knows nothing about.
  Bounds inflate(double amount) => Bounds(
    left: left - amount,
    top: top - amount,
    right: right + amount,
    bottom: bottom + amount,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Bounds &&
          left == other.left &&
          top == other.top &&
          right == other.right &&
          bottom == other.bottom;

  @override
  int get hashCode => Object.hash(left, top, right, bottom);

  @override
  String toString() => 'Bounds($left, $top, $right, $bottom)';
}
