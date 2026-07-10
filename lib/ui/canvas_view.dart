import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:inkpad/domain/models/models.dart';
import 'package:inkpad/engine/pointer_input.dart';
import 'package:inkpad/engine/renderer/document_painter.dart';
import 'package:inkpad/engine/renderer/stroke_painter.dart';
import 'package:inkpad/engine/smoothing.dart';
import 'package:inkpad/engine/thinning.dart';
import 'package:inkpad/state/state.dart';
import 'package:uuid/uuid.dart';

/// Gap between the page and the edge of the viewport, in screen pixels.
const double kViewportMargin = 32;

/// The gray backdrop with the white document page centered on it.
///
/// The page is scaled to fit the viewport, never magnified past 100%. Phase 12
/// replaces this fixed fit-to-viewport scale with a per-session pan/zoom
/// transform.
class CanvasView extends ConsumerWidget {
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
  Widget build(BuildContext context, WidgetRef ref) {
    final document = ref.watch(activeDocumentProvider);

    return ColoredBox(
      color: const Color(0xFF6E6E6E),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final scale = fitScale(
            viewport: constraints.biggest,
            documentWidth: document.canvasWidth,
            documentHeight: document.canvasHeight,
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
                    ? CustomPaint(
                        // Committed elements paint beneath the live stroke.
                        painter: DocumentPainter(
                          document: document,
                          scale: scale,
                        ),
                        child: StrokeCapture(scale: scale),
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

/// Collects raw [StrokePoint]s from pointer events over the page, paints the
/// stroke as it is drawn, and commits it to the active layer on pointer-up.
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
    _lastRawPoint = point;
    _stroke.begin(_smoother!.add(point).single);
  }

  void _onPointerMove(PointerMoveEvent event) {
    if (event.pointer != _activePointer) return;
    _feed(_pointFrom(event));
  }

  void _onPointerUp(PointerUpEvent event) {
    if (event.pointer != _activePointer) return;
    _feed(_pointFrom(event));
    for (final point in _smoother!.finish()) {
      _stroke.extend(point);
    }
    _commitStroke();
    _endStroke();
  }

  /// Thins [point] against the last raw input, then feeds what survives to the
  /// smoother, appending whatever it emits.
  void _feed(StrokePoint point) {
    if (!isFarEnough(_lastRawPoint!, point)) return;
    _lastRawPoint = point;
    for (final smoothed in _smoother!.add(point)) {
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

    ref
        .read(sessionsProvider.notifier)
        .addElementToActiveLayer(
          Stroke(
            id: const Uuid().v4(),
            colorRGBA: kDefaultStrokeColorRGBA,
            baseWidth: kDefaultStrokeWidth,
            points: points,
          ),
        );
  }

  void _endStroke() {
    _stroke.clear();
    _activePointer = null;
    _smoother = null;
    _lastRawPoint = null;
  }

  @override
  Widget build(BuildContext context) {
    final points = ref.watch(currentStrokeProvider);

    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: _onPointerDown,
      onPointerMove: _onPointerMove,
      onPointerUp: _onPointerUp,
      onPointerCancel: _onPointerCancel,
      child: RepaintBoundary(
        child: CustomPaint(
          size: Size.infinite,
          painter: InProgressStrokePainter(points: points, scale: widget.scale),
        ),
      ),
    );
  }
}
