import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inkpad/engine/stabilizer.dart';
import 'package:inkpad/state/state.dart';

void main() {
  late ProviderContainer container;
  setUp(() => container = ProviderContainer.test());

  test('is off by default', () {
    expect(container.read(stabilizerStrengthProvider), 0);
  });

  test('set updates the strength', () {
    container.read(stabilizerStrengthProvider.notifier).set(6);
    expect(container.read(stabilizerStrengthProvider), 6);
  });

  test('clamps rather than throwing', () {
    final n = container.read(stabilizerStrengthProvider.notifier)..set(99);
    expect(container.read(stabilizerStrengthProvider), kMaxStabilizerStrength);
    n.set(-4);
    expect(container.read(stabilizerStrengthProvider), 0);
  });
}
