import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:inkpad/domain/models/models.dart';

/// Fully transparent: the shape is unfilled.
const int kNoFill = 0x00000000;

/// The look new shapes are drawn with. Global, like the brush.
class ShapeStyle {
  const ShapeStyle({
    this.strokeColorRGBA = 0x1B1B1FFF,
    this.fillColorRGBA = kNoFill,
    this.strokeWidth = 3,
    this.strokeStyle = StrokeStyle.solid,
    this.renderStyle = ShapeRenderStyle.precise,
  }) : assert(strokeWidth > 0, 'strokeWidth must be positive');

  final int strokeColorRGBA;
  final int fillColorRGBA;
  final double strokeWidth;
  final StrokeStyle strokeStyle;

  /// Precise, or the hand-drawn look of task 17.1.
  final ShapeRenderStyle renderStyle;

  bool get isFilled => (fillColorRGBA & 0xFF) != 0;

  ShapeStyle copyWith({
    int? strokeColorRGBA,
    int? fillColorRGBA,
    double? strokeWidth,
    StrokeStyle? strokeStyle,
    ShapeRenderStyle? renderStyle,
  }) => ShapeStyle(
    strokeColorRGBA: strokeColorRGBA ?? this.strokeColorRGBA,
    fillColorRGBA: fillColorRGBA ?? this.fillColorRGBA,
    strokeWidth: strokeWidth ?? this.strokeWidth,
    strokeStyle: strokeStyle ?? this.strokeStyle,
    renderStyle: renderStyle ?? this.renderStyle,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ShapeStyle &&
          strokeColorRGBA == other.strokeColorRGBA &&
          fillColorRGBA == other.fillColorRGBA &&
          strokeWidth == other.strokeWidth &&
          strokeStyle == other.strokeStyle &&
          renderStyle == other.renderStyle;

  @override
  int get hashCode => Object.hash(
    strokeColorRGBA,
    fillColorRGBA,
    strokeWidth,
    strokeStyle,
    renderStyle,
  );
}

class ShapeStyleNotifier extends Notifier<ShapeStyle> {
  @override
  ShapeStyle build() => const ShapeStyle();

  void setStrokeColor(int rgba) =>
      state = state.copyWith(strokeColorRGBA: rgba);
  void setFillColor(int rgba) => state = state.copyWith(fillColorRGBA: rgba);
  void setStrokeWidth(double w) =>
      state = state.copyWith(strokeWidth: w.clamp(1, 64));
  void setStrokeStyle(StrokeStyle s) => state = state.copyWith(strokeStyle: s);
  void setRenderStyle(ShapeRenderStyle s) =>
      state = state.copyWith(renderStyle: s);

  /// Replaces the whole style — what Preferences applies when it loads.
  void set(ShapeStyle style) => state = style;
}

final shapeStyleProvider = NotifierProvider<ShapeStyleNotifier, ShapeStyle>(
  ShapeStyleNotifier.new,
);
