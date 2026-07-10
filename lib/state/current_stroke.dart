import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:inkpad/domain/models/models.dart';

/// The points of the stroke being drawn right now, in document space.
///
/// Empty when no pointer is down. This is transient UI state, not document
/// state: it is deliberately global rather than per-session, because only one
/// pointer draws at a time and the stroke belongs to whichever tab is in front.
/// Task 3.3 commits it into the active layer on pointer-up.
class CurrentStrokeNotifier extends Notifier<List<StrokePoint>> {
  @override
  List<StrokePoint> build() => const [];

  /// Starts a stroke at [point], discarding anything in flight.
  void begin(StrokePoint point) => state = [point];

  /// Appends [point] to the stroke.
  ///
  /// Publishes a new list every time: Riverpod compares by identity, so
  /// mutating in place would not repaint.
  void extend(StrokePoint point) => state = [...state, point];

  /// Drops the stroke without committing it.
  void clear() => state = const [];
}

final currentStrokeProvider =
    NotifierProvider<CurrentStrokeNotifier, List<StrokePoint>>(
      CurrentStrokeNotifier.new,
    );
