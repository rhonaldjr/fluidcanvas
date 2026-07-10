import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:inkpad/domain/models/models.dart';

/// The rubber-band rectangle being dragged, in document space, or `null`.
class MarqueeNotifier extends Notifier<Bounds?> {
  @override
  Bounds? build() => null;

  void set(Bounds? value) => state = value;
  void clear() => state = null;
}

final marqueeProvider = NotifierProvider<MarqueeNotifier, Bounds?>(
  MarqueeNotifier.new,
);
