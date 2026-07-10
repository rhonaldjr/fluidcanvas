import 'dart:math' as math;

import 'package:inkpad/domain/commands/command.dart';
import 'package:inkpad/domain/models/models.dart';

/// Smallest canvas the app will resize down to, in document pixels.
///
/// A window collapsed to nothing must not scale a drawing to nothing with it.
const int kMinCanvasWidth = 320;
const int kMinCanvasHeight = 200;

/// Resizes the canvas and scales every element with it.
///
/// Scaling is **uniform**, by `min(newW/oldW, newH/oldH)` about the old canvas
/// centre, and the result is recentred on the new canvas. A window whose aspect
/// ratio differs from the document's therefore gains blank canvas on its long
/// axis rather than stretching the drawing.
///
/// [oldLayers] is captured before the resize. `revert` restores it verbatim
/// instead of scaling back by `1 / factor`, so undo is exact rather than
/// accumulating floating-point drift over repeated resizes. Elements are
/// immutable and shared by reference, so holding the old list costs almost
/// nothing. `apply` recomputes from that same list, so redo is repeatable.
class ResizeCanvasCommand extends Command {
  ResizeCanvasCommand({
    required this.oldWidth,
    required this.oldHeight,
    required this.newWidth,
    required this.newHeight,
    required List<Layer> oldLayers,
  }) : assert(oldWidth > 0 && oldHeight > 0, 'old canvas must be positive'),
       assert(newWidth > 0 && newHeight > 0, 'new canvas must be positive'),
       oldLayers = List.unmodifiable(oldLayers);

  final int oldWidth;
  final int oldHeight;
  final int newWidth;
  final int newHeight;

  /// The layers as they were before the resize.
  final List<Layer> oldLayers;

  /// The uniform factor every element is scaled by.
  double get factor => math.min(newWidth / oldWidth, newHeight / oldHeight);

  @override
  String get label => 'Resize Canvas';

  @override
  SkdDocument apply(SkdDocument document) {
    final scale = factor;

    // Scale about the old centre, then shift that centre onto the new one.
    final oldCentreX = oldWidth / 2;
    final oldCentreY = oldHeight / 2;
    final dx = newWidth / 2 - oldCentreX;
    final dy = newHeight / 2 - oldCentreY;

    return document.copyWith(
      canvasWidth: newWidth,
      canvasHeight: newHeight,
      layers: [
        for (final layer in oldLayers)
          layer.copyWith(
            elements: [
              for (final element in layer.elements)
                element
                    .scaled(scale, originX: oldCentreX, originY: oldCentreY)
                    .translated(dx, dy),
            ],
          ),
      ],
    );
  }

  @override
  SkdDocument revert(SkdDocument document) => document.copyWith(
    canvasWidth: oldWidth,
    canvasHeight: oldHeight,
    layers: oldLayers,
  );
}
