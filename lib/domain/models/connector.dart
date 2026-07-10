part of 'canvas_element.dart';

/// One end of a [Connector]: a fixed point, or a binding to a sibling element.
///
/// A bound endpoint stores **no coordinates**. Where it lands is derived from
/// the element it points at, every time it is drawn — so a connector can never
/// go stale. Moving, resizing or rotating a bound shape needs no command that
/// touches the connector, and undo stays exact.
///
/// [elementId] is a runtime handle. Ids are not persisted, so the codec writes
/// the bound element's **index within its container** instead; element order is
/// z-order, which is stable.
class ConnectorEnd {
  const ConnectorEnd.free(double this.x, double this.y) : elementId = null;

  const ConnectorEnd.bound(String this.elementId) : x = null, y = null;

  /// Set for a free end, null for a bound one.
  final double? x;
  final double? y;

  /// Set for a bound end, null for a free one.
  final String? elementId;

  bool get isBound => elementId != null;

  ConnectorEnd translated(double dx, double dy) =>
      isBound ? this : ConnectorEnd.free(x! + dx, y! + dy);

  ConnectorEnd scaled(double factor, double originX, double originY) => isBound
      ? this
      : ConnectorEnd.free(
          originX + (x! - originX) * factor,
          originY + (y! - originY) * factor,
        );

  ConnectorEnd rotated(double radians, double originX, double originY) {
    if (isBound) return this;
    final cos = math.cos(radians);
    final sin = math.sin(radians);
    final dx = x! - originX;
    final dy = y! - originY;
    return ConnectorEnd.free(
      originX + dx * cos - dy * sin,
      originY + dx * sin + dy * cos,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ConnectorEnd &&
          x == other.x &&
          y == other.y &&
          elementId == other.elementId;

  @override
  int get hashCode => Object.hash(x, y, elementId);

  @override
  String toString() =>
      isBound ? 'ConnectorEnd.bound($elementId)' : 'ConnectorEnd.free($x, $y)';
}

/// A line joining two points, either of which may follow an element.
///
/// Deliberately not a [Shape]: a shape is a box with an angle, a connector is
/// two endpoints. Giving it a `w`/`h` would mean answering what a negative
/// width means for an end that is bound to something else.
class Connector extends CanvasElement {
  const Connector({
    required super.id,
    required this.start,
    required this.end,
    required this.strokeColorRGBA,
    required this.strokeWidth,
    this.strokeStyle = StrokeStyle.solid,
    this.endArrow = true,
    this.startArrow = false,
  }) : assert(strokeWidth > 0, 'strokeWidth must be positive');

  final ConnectorEnd start;
  final ConnectorEnd end;

  final int strokeColorRGBA;
  final double strokeWidth;
  final StrokeStyle strokeStyle;

  /// Arrowheads. The end usually has one; the start usually does not.
  final bool startArrow;
  final bool endArrow;

  bool get isBound => start.isBound || end.isBound;

  /// The ids this connector follows.
  Set<String> get boundIds => {?start.elementId, ?end.elementId};

  /// The box around its **free** ends only.
  ///
  /// `null` when either end is bound: where that end lands depends on an
  /// element this object cannot see. Callers holding the container use
  /// `resolveConnector` from `engine/connector_routing.dart` instead — which is
  /// why selection, hit-testing and rendering all take the sibling list.
  @override
  Bounds? get bounds {
    if (isBound) return null;
    return Bounds(
      left: math.min(start.x!, end.x!),
      top: math.min(start.y!, end.y!),
      right: math.max(start.x!, end.x!),
      bottom: math.max(start.y!, end.y!),
    );
  }

  /// Only free ends move. A bound end follows its element — which the caller is
  /// probably moving too, and if it is not, the connector stretches. That is
  /// what a connector is for.
  @override
  Connector scaled(double factor, {double originX = 0, double originY = 0}) =>
      copyWith(
        start: start.scaled(factor, originX, originY),
        end: end.scaled(factor, originX, originY),
        strokeWidth: strokeWidth * factor,
      );

  @override
  Connector translated(double dx, double dy) =>
      copyWith(start: start.translated(dx, dy), end: end.translated(dx, dy));

  @override
  Connector rotated(
    double radians, {
    required double originX,
    required double originY,
  }) => copyWith(
    start: start.rotated(radians, originX, originY),
    end: end.rotated(radians, originX, originY),
  );

  Connector copyWith({
    String? id,
    ConnectorEnd? start,
    ConnectorEnd? end,
    int? strokeColorRGBA,
    double? strokeWidth,
    StrokeStyle? strokeStyle,
    bool? startArrow,
    bool? endArrow,
  }) => Connector(
    id: id ?? this.id,
    start: start ?? this.start,
    end: end ?? this.end,
    strokeColorRGBA: strokeColorRGBA ?? this.strokeColorRGBA,
    strokeWidth: strokeWidth ?? this.strokeWidth,
    strokeStyle: strokeStyle ?? this.strokeStyle,
    startArrow: startArrow ?? this.startArrow,
    endArrow: endArrow ?? this.endArrow,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Connector &&
          id == other.id &&
          start == other.start &&
          end == other.end &&
          strokeColorRGBA == other.strokeColorRGBA &&
          strokeWidth == other.strokeWidth &&
          strokeStyle == other.strokeStyle &&
          startArrow == other.startArrow &&
          endArrow == other.endArrow;

  @override
  int get hashCode => Object.hash(
    id,
    start,
    end,
    strokeColorRGBA,
    strokeWidth,
    strokeStyle,
    startArrow,
    endArrow,
  );

  @override
  String toString() => 'Connector($id, $start -> $end)';
}
