import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:inkpad/engine/stabilizer.dart';

/// How strongly to stabilize input, 0..10. Off by default.
///
/// Global, like the brush and the tool.
class StabilizerStrengthNotifier extends Notifier<int> {
  @override
  int build() => 0;

  /// Clamps rather than asserting: a slider or shortcut should stop at the end.
  void set(int strength) => state = strength.clamp(0, kMaxStabilizerStrength);
}

final stabilizerStrengthProvider =
    NotifierProvider<StabilizerStrengthNotifier, int>(
      StabilizerStrengthNotifier.new,
    );
