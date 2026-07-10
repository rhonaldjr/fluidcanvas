import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Narrowest and widest brush the width slider offers, in document pixels.
const double kMinBrushWidth = 1;
const double kMaxBrushWidth = 64;

/// Default brush colour: near-black. Packed 0xRRGGBBAA.
const int kDefaultBrushColorRGBA = 0x1B1B1FFF;

/// The eight colours always on the toolbar. Packed 0xRRGGBBAA.
const List<int> kSwatchColors = [
  kDefaultBrushColorRGBA, // near-black
  0xFFFFFFFF, // white
  0xE53935FF, // red
  0xFB8C00FF, // orange
  0xFDD835FF, // yellow
  0x43A047FF, // green
  0x1E88E5FF, // blue
  0x8E24AAFF, // purple
];

/// The brush new strokes are drawn with.
///
/// Deliberately **global**, not per-[DocumentSession]: switching tabs must not
/// change which brush you are holding. See the roadmap preamble.
class Brush {
  const Brush({this.colorRGBA = kDefaultBrushColorRGBA, this.baseWidth = 4})
    : assert(
        baseWidth >= kMinBrushWidth && baseWidth <= kMaxBrushWidth,
        'baseWidth must be within the slider range',
      );

  /// Packed 0xRRGGBBAA, as the models and `.skd` store colour.
  final int colorRGBA;

  /// Width at full pressure, in document pixels.
  final double baseWidth;

  Brush copyWith({int? colorRGBA, double? baseWidth}) => Brush(
    colorRGBA: colorRGBA ?? this.colorRGBA,
    baseWidth: baseWidth ?? this.baseWidth,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Brush &&
          colorRGBA == other.colorRGBA &&
          baseWidth == other.baseWidth;

  @override
  int get hashCode => Object.hash(colorRGBA, baseWidth);

  @override
  String toString() =>
      'Brush(0x${colorRGBA.toRadixString(16).padLeft(8, '0')}, $baseWidth)';
}

class BrushNotifier extends Notifier<Brush> {
  @override
  Brush build() => const Brush();

  /// Clamps into the slider's range rather than asserting: a width nudged by a
  /// keyboard shortcut (task 15.2) should stop at the end, not crash.
  void setWidth(double width) => state = state.copyWith(
    baseWidth: width.clamp(kMinBrushWidth, kMaxBrushWidth),
  );

  void setColor(int colorRGBA) => state = state.copyWith(colorRGBA: colorRGBA);
}

final brushProvider = NotifierProvider<BrushNotifier, Brush>(BrushNotifier.new);
