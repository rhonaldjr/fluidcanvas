import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:inkpad/domain/models/models.dart';

/// The shape being dragged out right now, or `null` between drags.
///
/// Transient UI state, like `currentStroke`: it is a real [Shape] so it paints
/// through exactly the code that will paint it once committed.
class CurrentShapeNotifier extends Notifier<Shape?> {
  @override
  Shape? build() => null;

  void set(Shape? shape) => state = shape;
  void clear() => state = null;
}

final currentShapeProvider = NotifierProvider<CurrentShapeNotifier, Shape?>(
  CurrentShapeNotifier.new,
);
