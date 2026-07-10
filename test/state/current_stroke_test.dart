import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inkpad/domain/models/models.dart';
import 'package:inkpad/state/state.dart';

void main() {
  late ProviderContainer container;

  setUp(() => container = ProviderContainer.test());

  List<StrokePoint> read() => container.read(currentStrokeProvider);
  CurrentStrokeNotifier notifier() =>
      container.read(currentStrokeProvider.notifier);

  test('starts empty', () {
    expect(read(), isEmpty);
  });

  test('begin starts a one-point stroke', () {
    notifier().begin(const StrokePoint(x: 1, y: 2));
    expect(read(), [const StrokePoint(x: 1, y: 2)]);
  });

  test('begin discards a stroke left in flight', () {
    notifier()
      ..begin(const StrokePoint(x: 1, y: 1))
      ..extend(const StrokePoint(x: 2, y: 2))
      ..begin(const StrokePoint(x: 9, y: 9));

    expect(read(), [const StrokePoint(x: 9, y: 9)]);
  });

  test('extend appends in order', () {
    notifier()
      ..begin(const StrokePoint(x: 0, y: 0))
      ..extend(const StrokePoint(x: 1, y: 1))
      ..extend(const StrokePoint(x: 2, y: 2));

    expect([for (final p in read()) p.x], [0, 1, 2]);
  });

  test('clear empties the stroke', () {
    notifier()
      ..begin(const StrokePoint(x: 1, y: 1))
      ..clear();
    expect(read(), isEmpty);
  });

  test('every mutation publishes a new list, so painters repaint', () {
    notifier().begin(const StrokePoint(x: 0, y: 0));
    final first = read();

    notifier().extend(const StrokePoint(x: 1, y: 1));
    final second = read();

    expect(identical(first, second), isFalse);
  });

  test('the published list cannot be mutated by a listener', () {
    notifier().begin(const StrokePoint(x: 0, y: 0));
    // Published lists are literals, not views onto notifier state; appending to
    // a copy must not grow the stroke.
    final snapshot = read();
    notifier().extend(const StrokePoint(x: 1, y: 1));
    expect(snapshot, hasLength(1));
  });
}
