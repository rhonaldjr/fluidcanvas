import 'dart:async';

/// Runs the last action given to it, once the calls stop coming.
///
/// A window drag emits a resize per frame. Without this, each frame would push
/// a `ResizeCanvasCommand` and one drag would fill the undo stack.
class Debouncer {
  Debouncer({this.duration = const Duration(milliseconds: 250)});

  final Duration duration;

  Timer? _timer;

  /// Whether an action is waiting to fire.
  bool get isPending => _timer?.isActive ?? false;

  /// Schedules [action], replacing anything already waiting.
  void call(void Function() action) {
    _timer?.cancel();
    _timer = Timer(duration, action);
  }

  /// Drops the pending action without running it.
  void cancel() {
    _timer?.cancel();
    _timer = null;
  }

  void dispose() => cancel();
}
