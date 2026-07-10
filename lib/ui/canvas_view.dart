import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:inkpad/domain/models/models.dart';
import 'package:inkpad/engine/pointer_input.dart';
import 'package:inkpad/engine/renderer/layer_stack_painter.dart';
import 'package:inkpad/engine/smoothing.dart';
import 'package:inkpad/engine/stabilizer.dart';
import 'package:inkpad/engine/thinning.dart';
import 'package:inkpad/state/state.dart';
import 'package:uuid/uuid.dart';

/// Gap between the page and the edge of the viewport, in screen pixels.
const double kViewportMargin = 32;

/// Id given to the stroke while it is still under the pointer. It never reaches
/// the document: [_StrokeCaptureState] mints a fresh id when committing.
const String kLiveStrokeId = 'live';

/// The gray backdrop with the white document page centered on it.
///
/// The page is scaled to fit the viewport, never magnified past 100%. Phase 12
/// replaces this fixed fit-to-viewport scale with a per-session pan/zoom
/// transform.
class CanvasView extends ConsumerStatefulWidget {
  const CanvasView({super.key});

  /// Page scale that fits a [documentWidth] x [documentHeight] page inside
  /// [viewport], leaving [kViewportMargin] on every side. Never magnifies past
  /// 100%; returns 0 when the viewport cannot fit anything.
  static double fitScale({
    required Size viewport,
    required int documentWidth,
    required int documentHeight,
  }) {
    final availableWidth = math.max(0.0, viewport.width - kViewportMargin * 2);
    final availableHeight = math.max(
      0.0,
      viewport.height - kViewportMargin * 2,
    );

    final fit = math.min(
      availableWidth / documentWidth,
      availableHeight / documentHeight,
    );
    // Guard against a zero-sized or unbounded viewport.
    return fit.isFinite ? fit.clamp(0.0, 1.0) : 0.0;
  }

  @override
  ConsumerState<CanvasView> createState() => _CanvasViewState();
}

class _CanvasViewState extends ConsumerState<CanvasView> {
  @override
  Widget build(BuildContext context) {
    // Shared with the layer panel's thumbnails; owned by the provider.
    final cache = ref.watch(layerCacheProvider);
    final session = ref.watch(activeSessionProvider);
    final document = session.document;
    final points = ref.watch(currentStrokeProvider);
    final brush = ref.watch(brushProvider);
    final tool = ref.watch(toolProvider);

    // A layer removed from the document must not keep holding its image.
    cache.retainOnly([for (final layer in document.layers) layer.id]);

    // The live stroke is a real Stroke so it paints through exactly the code
    // that will paint it once committed — including the eraser's blend mode.
    final liveStroke = points.isEmpty
        ? null
        : Stroke(
            id: kLiveStrokeId,
            colorRGBA: brush.colorRGBA,
            baseWidth: brush.baseWidth,
            toolId: tool.toolId,
            points: points,
          );

    // Split the stack so only the active layer repaints while drawing.
    final activeIndex = document.indexOfLayer(session.activeLayerId);
    final below = document.layers.sublist(0, activeIndex);
    final active = document.layers.sublist(activeIndex, activeIndex + 1);
    final above = document.layers.sublist(activeIndex + 1);

    return ColoredBox(
      color: const Color(0xFF6E6E6E),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final scale = CanvasView.fitScale(
            viewport: constraints.biggest,
            documentWidth: document.canvasWidth,
            documentHeight: document.canvasHeight,
          );

          LayerStackPainter painterFor(
            List<Layer> layers,
            String label, {
            Stroke? live,
          }) => LayerStackPainter(
            layers: layers,
            documentWidth: document.canvasWidth,
            documentHeight: document.canvasHeight,
            scale: scale,
            cache: cache,
            liveStroke: live,
            debugLabel: label,
          );

          return Center(
            child: SizedBox(
              key: const Key('canvas-page'),
              width: document.canvasWidth * scale,
              height: document.canvasHeight * scale,
              child: DecoratedBox(
                decoration: const BoxDecoration(
                  color: Colors.white,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black26,
                      blurRadius: 8,
                      spreadRadius: 1,
                    ),
                  ],
                ),
                // A zero-size page cannot map screen pixels into document
                // space, so there is nothing to draw or capture.
                child: scale > 0
                    ? Stack(
                        fit: StackFit.expand,
                        children: [
                          RepaintBoundary(
                            child: CustomPaint(
                              painter: painterFor(below, 'below'),
                            ),
                          ),
                          RepaintBoundary(
                            child: CustomPaint(
                              painter: painterFor(
                                active,
                                'active',
                                live: liveStroke,
                              ),
                            ),
                          ),
                          RepaintBoundary(
                            child: CustomPaint(
                              painter: painterFor(above, 'above'),
                            ),
                          ),
                          StrokeCapture(scale: scale),
                        ],
                      )
                    : null,
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Collects raw [StrokePoint]s from pointer events over the page and commits
/// them to the active layer on pointer-up.
///
/// From task 6.2 the commit is routed through `AddElementCommand` so it can be
/// undone; today it mutates the session directly.
class StrokeCapture extends ConsumerStatefulWidget {
  const StrokeCapture({required this.scale, super.key});

  /// Page screen size divided by document size.
  final double scale;

  @override
  ConsumerState<StrokeCapture> createState() => _StrokeCaptureState();
}

class _StrokeCaptureState extends ConsumerState<StrokeCapture> {
  /// The pointer currently drawing. A second finger or a second button while a
  /// stroke is in flight is ignored rather than interleaved into it.
  int? _activePointer;

  /// Smooths the raw input as it streams in, never as a post-pass.
  StrokeSmoother? _smoother;

  /// Decides which raw points survive, before the smoother interpolates
  /// between them. Rebuilt per stroke so a mid-stroke strength change cannot
  /// jerk the anchor.
  Stabilizer? _stabilizer;

  /// The last point fed to the smoother. Thinning measures against the raw
  /// input, not the smoothed output, whose interpolated points are deliberately
  /// closer together than the threshold.
  StrokePoint? _lastRawPoint;

  CurrentStrokeNotifier get _stroke => ref.read(currentStrokeProvider.notifier);

  StrokePoint _pointFrom(PointerEvent event) => documentPoint(
    local: event.localPosition,
    scale: widget.scale,
    pressure: normalizePressure(
      pressure: event.pressure,
      min: event.pressureMin,
      max: event.pressureMax,
    ),
  );

  void _onPointerDown(PointerDownEvent event) {
    if (_activePointer != null) return;
    _activePointer = event.pointer;

    final point = _pointFrom(event);
    _smoother = StrokeSmoother();
    _stabilizer = Stabilizer(strength: ref.read(stabilizerStrengthProvider));
    _lastRawPoint = point;
    _stroke.begin(_smoother!.add(_stabilizer!.process(point)!).single);
  }

  void _onPointerMove(PointerMoveEvent event) {
    if (event.pointer != _activePointer) return;
    _feed(_pointFrom(event));
  }

  void _onPointerUp(PointerUpEvent event) {
    if (event.pointer != _activePointer) return;
    _feed(_pointFrom(event));

    // Let the anchor catch up to the cursor before closing the stroke.
    final tail = _stabilizer!.finish();
    if (tail != null) {
      for (final smoothed in _smoother!.add(tail)) {
        _stroke.extend(smoothed);
      }
    }
    for (final point in _smoother!.finish()) {
      _stroke.extend(point);
    }
    _commitStroke();
    _endStroke();
  }

  /// Thins [point] against the last raw input, stabilizes what survives, then
  /// feeds that to the smoother and appends whatever it emits.
  void _feed(StrokePoint point) {
    if (!isFarEnough(_lastRawPoint!, point)) return;
    _lastRawPoint = point;

    final stabilized = _stabilizer!.process(point);
    if (stabilized == null) return;

    for (final smoothed in _smoother!.add(stabilized)) {
      _stroke.extend(smoothed);
    }
  }

  void _onPointerCancel(PointerCancelEvent event) {
    if (event.pointer != _activePointer) return;
    // A cancelled stroke is abandoned, never committed.
    _endStroke();
  }

  void _commitStroke() {
    final points = ref.read(currentStrokeProvider);
    if (points.isEmpty) return;

    final brush = ref.read(brushProvider);
    ref
        .read(sessionsProvider.notifier)
        .addElementToActiveLayer(
          Stroke(
            id: const Uuid().v4(),
            colorRGBA: brush.colorRGBA,
            baseWidth: brush.baseWidth,
            toolId: ref.read(toolProvider).toolId,
            points: points,
          ),
        );
  }

  void _endStroke() {
    _stroke.clear();
    _activePointer = null;
    _smoother = null;
    _stabilizer = null;
    _lastRawPoint = null;
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: _onPointerDown,
      onPointerMove: _onPointerMove,
      onPointerUp: _onPointerUp,
      onPointerCancel: _onPointerCancel,
      child: const SizedBox.expand(),
    );
  }
}
