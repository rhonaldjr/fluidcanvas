import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:inkpad/domain/models/models.dart';
import 'package:inkpad/domain/commands/commands.dart'
    show kMinCanvasHeight, kMinCanvasWidth;
import 'package:inkpad/engine/debouncer.dart';
import 'package:inkpad/engine/pointer_input.dart';
import 'package:inkpad/engine/renderer/layer_stack_painter.dart';
import 'package:inkpad/engine/hit_test.dart';
import 'package:inkpad/engine/shape_drag.dart';
import 'package:inkpad/engine/smoothing.dart';
import 'package:inkpad/engine/stabilizer.dart';
import 'package:inkpad/engine/thinning.dart';
import 'package:inkpad/state/state.dart';
import 'package:inkpad/ui/selection_overlay.dart';
import 'package:inkpad/ui/text_box_editor.dart';
import 'package:uuid/uuid.dart';

/// Gap between the page and the edge of the viewport, in screen pixels.
const double kViewportMargin = 32;

/// How long the window must be still before the canvas resize is committed.
const Duration kResizeDebounce = Duration(milliseconds: 250);

/// The canvas size that fits [viewport], leaving [kViewportMargin] on every
/// side and never dropping below the minimum.
///
/// A window collapsed to nothing would otherwise scale the drawing to nothing
/// with it.
({int width, int height}) canvasSizeForViewport(Size viewport) => (
  width: math.max(
    kMinCanvasWidth,
    (viewport.width - kViewportMargin * 2).floor(),
  ),
  height: math.max(
    kMinCanvasHeight,
    (viewport.height - kViewportMargin * 2).floor(),
  ),
);

/// Id given to the stroke while it is still under the pointer. It never reaches
/// the document: [_StrokeCaptureState] mints a fresh id when committing.
const String kLiveStrokeId = 'live';

/// The gray backdrop with the white document page centered on it.
///
/// The page is scaled to fit the viewport, never magnified past 100%. Task 8.3
/// makes the document itself follow the window; Phase 14 then replaces this
/// fixed scale with a per-session pan/zoom transform.
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
  /// A window drag emits a resize per frame; act once the drag stops.
  final Debouncer _resizeDebouncer = Debouncer(duration: kResizeDebounce);

  /// Whether the document has already adopted a window size.
  ///
  /// Only the very first fit is immediate. Testing "the document is still
  /// empty" instead would make *every* resize of a blank document immediate,
  /// and the debounce would never engage.
  bool _didInitialFit = false;

  @override
  void dispose() {
    _resizeDebouncer.dispose();
    super.dispose();
  }

  /// Makes the document's canvas follow the viewport.
  ///
  /// The very first fit — an untouched document adopting the window it opened
  /// in — happens on the next frame, so the canvas is right immediately. Later
  /// fits are debounced: a window drag emits a resize per frame, and the page
  /// keeps drawing through the fit-to-viewport transform until the drag stops.
  void _scheduleResize(Size viewport) {
    final target = canvasSizeForViewport(viewport);
    final session = ref.read(activeSessionProvider);
    final document = session.document;
    if (document.canvasWidth == target.width &&
        document.canvasHeight == target.height) {
      _resizeDebouncer.cancel();
      return;
    }

    if (!_didInitialFit && document.isEmpty && !session.canUndo) {
      _didInitialFit = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _fit(target));
    } else {
      _resizeDebouncer(() => _fit(target));
    }
  }

  void _fit(({int width, int height}) target) {
    if (!mounted) return;
    if (!ref.read(activeSessionProvider).fitToWindow) return;
    ref
        .read(sessionsProvider.notifier)
        .fitCanvasToWindow(target.width, target.height);
  }

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

    final liveShape = ref.watch(currentShapeProvider);

    // The live stroke is a real Stroke so it paints through exactly the code
    // that will paint it once committed — including the eraser's blend mode.
    final liveStroke = points.isEmpty || !tool.drawsStroke
        ? null
        : Stroke(
            id: kLiveStrokeId,
            colorRGBA: brush.colorRGBA,
            baseWidth: brush.baseWidth,
            toolId: tool.strokeToolId!,
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
          if (session.fitToWindow && constraints.biggest.isFinite) {
            _scheduleResize(constraints.biggest);
          }

          final scale = CanvasView.fitScale(
            viewport: constraints.biggest,
            documentWidth: document.canvasWidth,
            documentHeight: document.canvasHeight,
          );
          // The status bar reads this rather than digging into the tree.
          WidgetsBinding.instance.addPostFrameCallback(
            (_) => ref.read(pageScaleProvider.notifier).set(scale),
          );

          LayerStackPainter painterFor(
            List<Layer> layers,
            String label, {
            Stroke? live,
            Shape? shape,
          }) => LayerStackPainter(
            layers: layers,
            documentWidth: document.canvasWidth,
            documentHeight: document.canvasHeight,
            scale: scale,
            cache: cache,
            liveStroke: live,
            liveShape: shape,
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
                        clipBehavior: Clip.none,
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
                                shape: liveShape,
                              ),
                            ),
                          ),
                          RepaintBoundary(
                            child: CustomPaint(
                              painter: painterFor(above, 'above'),
                            ),
                          ),
                          RepaintBoundary(
                            child: CustomPaint(
                              painter: SelectionOverlayPainter(
                                box: session.selection.isEmpty
                                    ? null
                                    : session.selectionBounds,
                                marquee: ref.watch(marqueeProvider),
                                scale: scale,
                                color: Theme.of(context).colorScheme.primary,
                              ),
                            ),
                          ),
                          StrokeCapture(scale: scale),
                          TextBoxEditor(scale: scale),
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

  /// Where a shape drag started. Null unless a shape tool is dragging.
  StrokePoint? _shapeAnchor;

  /// Where a select-tool drag started, in document space.
  Offset? _selectAnchor;

  /// What the select drag is doing: nothing yet, a marquee, a move, or a
  /// handle drag.
  _SelectGesture _gesture = _SelectGesture.none;

  /// The handle being dragged, and the geometry captured when the drag began.
  ///
  /// Every frame transforms *these* rather than the live document, so the drag
  /// stays one continuous transform and one undo entry.
  Handle? _handle;
  Bounds? _boxAtDragStart;
  List<CanvasElement> _elementsAtDragStart = const [];

  /// The transform the drag has reached so far.
  double _dragFactor = 1;
  double _dragRotation = 0;
  Offset _dragOffset = Offset.zero;

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

  Tool get _tool => ref.read(toolProvider);

  void _onPointerDown(PointerDownEvent event) {
    if (_activePointer != null) return;
    _activePointer = event.pointer;
    final point = _pointFrom(event);

    if (_tool.drawsText) {
      _createTextBox(point);
      return;
    }
    if (_tool == Tool.select) {
      _beginSelect(point);
      return;
    }
    if (_tool.drawsShape) {
      _shapeAnchor = point;
      return;
    }
    if (!_tool.drawsStroke) return;

    _smoother = StrokeSmoother();
    _stabilizer = Stabilizer(strength: ref.read(stabilizerStrengthProvider));
    _lastRawPoint = point;
    _stroke.begin(_smoother!.add(_stabilizer!.process(point)!).single);
  }

  void _onPointerMove(PointerMoveEvent event) {
    if (event.pointer != _activePointer) return;
    if (_gesture != _SelectGesture.none) {
      _updateSelect(_pointFrom(event));
      return;
    }
    if (_shapeAnchor != null) {
      _updateLiveShape(_pointFrom(event));
      return;
    }
    if (!_tool.drawsStroke) return;
    _feed(_pointFrom(event));
  }

  void _onPointerUp(PointerUpEvent event) {
    if (event.pointer != _activePointer) return;

    if (_tool == Tool.select) {
      _endSelect(_pointFrom(event));
      _endStroke();
      return;
    }
    if (_shapeAnchor != null) {
      _updateLiveShape(_pointFrom(event));
      _commitShape();
      _endStroke();
      return;
    }
    if (!_tool.drawsStroke) {
      _endStroke();
      return;
    }

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

  /// Rebuilds the shape preview from the anchor to [current].
  ///
  /// Shift constrains to a square, circle or 45-degree line; Alt draws out from
  /// the anchor as the centre.
  void _updateLiveShape(StrokePoint current) {
    final style = ref.read(shapeStyleProvider);
    final keys = HardwareKeyboard.instance;

    ref
        .read(currentShapeProvider.notifier)
        .set(
          shapeFromDrag(
            id: kLiveStrokeId,
            type: _tool.shapeType!,
            anchor: _shapeAnchor!,
            current: current,
            strokeColorRGBA: style.strokeColorRGBA,
            fillColorRGBA: style.fillColorRGBA,
            strokeWidth: style.strokeWidth,
            strokeStyle: style.strokeStyle,
            square: keys.isShiftPressed,
            fromCenter: keys.isAltPressed,
          ),
        );
  }

  // -------------------------------------------------------------------
  // Select tool
  // -------------------------------------------------------------------

  SessionsNotifier get _sessions => ref.read(sessionsProvider.notifier);

  void _beginSelect(StrokePoint point) {
    final session = ref.read(activeSessionProvider);
    final at = Offset(point.x, point.y);
    _selectAnchor = at;
    _dragFactor = 1;
    _dragRotation = 0;
    _dragOffset = Offset.zero;

    // A handle wins over whatever sits under it.
    final box = session.selectionBounds;
    if (box != null) {
      final handle = handleAt(box, at.dx, at.dy, widget.scale);
      if (handle != null) {
        _handle = handle;
        _boxAtDragStart = box;
        _elementsAtDragStart = session.selectedElements;
        _gesture = handle == Handle.rotate
            ? _SelectGesture.rotate
            : _SelectGesture.resize;
        return;
      }
    }

    final hit = topmostElementAt(session.document.layers, at.dx, at.dy);
    if (hit == null) {
      if (!HardwareKeyboard.instance.isShiftPressed) _sessions.clearSelection();
      _gesture = _SelectGesture.marquee;
      ref.read(marqueeProvider.notifier).set(Bounds.point(at.dx, at.dy));
      return;
    }

    if (HardwareKeyboard.instance.isShiftPressed) {
      _sessions.toggleSelected(hit.id);
    } else if (!session.selection.contains(hit.id)) {
      _sessions.setSelection({hit.id});
    }
    _elementsAtDragStart = ref.read(activeSessionProvider).selectedElements;
    _gesture = _SelectGesture.move;
  }

  void _updateSelect(StrokePoint point) {
    final at = Offset(point.x, point.y);
    final from = _selectAnchor!;

    switch (_gesture) {
      case _SelectGesture.none:
        return;

      case _SelectGesture.marquee:
        ref.read(marqueeProvider.notifier).set(_boundsBetween(from, at));

      case _SelectGesture.move:
        _dragOffset = at - from;
        _preview((e) => e.translated(_dragOffset.dx, _dragOffset.dy));

      case _SelectGesture.resize:
        final anchor = anchorFor(_handle!, _boxAtDragStart!);
        _dragFactor = resizeFactor(anchor: anchor, start: from, current: at);
        _preview(
          (e) => e.scaled(_dragFactor, originX: anchor.dx, originY: anchor.dy),
        );

      case _SelectGesture.rotate:
        final centre = _dragCentre;
        var wanted = (at - centre).direction - (from - centre).direction;
        if (HardwareKeyboard.instance.isShiftPressed) {
          const step = math.pi / 12; // 15 degrees
          wanted = (wanted / step).roundToDouble() * step;
        }
        _dragRotation = wanted;
        _preview(
          (e) =>
              e.rotated(_dragRotation, originX: centre.dx, originY: centre.dy),
        );
    }
  }

  Offset get _dragCentre =>
      Offset(_boxAtDragStart!.centerX, _boxAtDragStart!.centerY);

  /// Redraws the drag from the geometry captured when it started.
  ///
  /// Never from the current document: compounding a transform frame by frame
  /// accumulates float error, and undoing one frame of it is meaningless.
  void _preview(CanvasElement Function(CanvasElement) transform) {
    if (_elementsAtDragStart.isEmpty) return;
    _sessions.previewElements([
      for (final element in _elementsAtDragStart) transform(element),
    ]);
  }

  void _endSelect(StrokePoint point) {
    // One command for the whole gesture, built from the captured geometry.
    switch (_gesture) {
      case _SelectGesture.move:
        _sessions.commitMove(
          _elementsAtDragStart,
          _dragOffset.dx,
          _dragOffset.dy,
        );
      case _SelectGesture.resize:
        final anchor = anchorFor(_handle!, _boxAtDragStart!);
        _sessions.commitResize(
          _elementsAtDragStart,
          _dragFactor,
          anchor.dx,
          anchor.dy,
        );
      case _SelectGesture.rotate:
        final centre = _dragCentre;
        _sessions.commitRotate(
          _elementsAtDragStart,
          _dragRotation,
          centre.dx,
          centre.dy,
        );
      case _SelectGesture.marquee:
      case _SelectGesture.none:
        break;
    }

    if (_gesture == _SelectGesture.marquee) {
      final marquee = _boundsBetween(_selectAnchor!, Offset(point.x, point.y));
      final layers = ref.read(activeDocumentProvider).layers;
      final inside = elementsWithin(layers, marquee);
      if (inside.isNotEmpty) {
        _sessions.setSelection({
          ...ref.read(activeSessionProvider).selection,
          for (final e in inside) e.id,
        });
      }
    }
    ref.read(marqueeProvider.notifier).clear();
    _gesture = _SelectGesture.none;
    _handle = null;
    _boxAtDragStart = null;
    _elementsAtDragStart = const [];
    _selectAnchor = null;
  }

  static Bounds _boundsBetween(Offset a, Offset b) => Bounds(
    left: math.min(a.dx, b.dx),
    top: math.min(a.dy, b.dy),
    right: math.max(a.dx, b.dx),
    bottom: math.max(a.dy, b.dy),
  );

  /// Default size of a text box placed with a click, in document pixels.
  static const Size _defaultTextBox = Size(260, 60);

  void _createTextBox(StrokePoint at) {
    final style = ref.read(textStyleProvider);
    final element = TextElement.plain(
      id: const Uuid().v4(),
      x: at.x,
      y: at.y,
      w: _defaultTextBox.width,
      h: _defaultTextBox.height,
      fontFamily: style.fontFamily,
      fontSize: style.fontSize,
      colorRGBA: style.colorRGBA,
    );

    ref.read(sessionsProvider.notifier).addElementToActiveLayer(element);
    ref.read(textEditingProvider.notifier).begin(element);
    // Typing a box then leaving it empty removes it again, so a mis-click
    // leaves nothing behind.
    _activePointer = null;
  }

  void _commitShape() {
    final shape = ref.read(currentShapeProvider);
    if (shape == null) return;

    final box = shape.normalized();
    // A click with a shape tool, or a drag of a few pixels, is a mis-click.
    if (box.w < 1 && box.h < 1) return;

    ref
        .read(sessionsProvider.notifier)
        .addElementToActiveLayer(box.copyWith(id: const Uuid().v4()));
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
    // A cancelled drag is abandoned, never committed.
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
            toolId: ref.read(toolProvider).strokeToolId!,
            points: points,
          ),
        );
  }

  void _endStroke() {
    _stroke.clear();
    ref.read(currentShapeProvider.notifier).clear();
    _gesture = _SelectGesture.none;
    _handle = null;
    _selectAnchor = null;
    _activePointer = null;
    _shapeAnchor = null;
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

/// What a select-tool drag is doing.
enum _SelectGesture { none, marquee, move, resize, rotate }
