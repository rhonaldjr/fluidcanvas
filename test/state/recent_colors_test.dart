import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inkpad/state/state.dart';

void main() {
  late ProviderContainer container;

  setUp(() => container = ProviderContainer.test());

  List<int> read() => container.read(recentColorsProvider);
  RecentColorsNotifier notifier() =>
      container.read(recentColorsProvider.notifier);

  test('starts empty', () {
    expect(read(), isEmpty);
  });

  test('the newest colour comes first', () {
    notifier()
      ..add(0x111111FF)
      ..add(0x222222FF);
    expect(read(), [0x222222FF, 0x111111FF]);
  });

  test('re-picking a colour promotes it rather than duplicating it', () {
    notifier()
      ..add(0x111111FF)
      ..add(0x222222FF)
      ..add(0x111111FF);

    expect(read(), [0x111111FF, 0x222222FF]);
    expect(read().toSet(), hasLength(2));
  });

  test('caps at eight, dropping the oldest', () {
    for (var i = 0; i < 12; i++) {
      notifier().add(i << 8 | 0xFF);
    }

    expect(read(), hasLength(kMaxRecentColors));
    // Newest first: 11, 10, ... 4. The first four are gone.
    expect(read().first, 11 << 8 | 0xFF);
    expect(read().last, 4 << 8 | 0xFF);
    expect(read(), isNot(contains(0 << 8 | 0xFF)));
  });

  test('promoting an old colour rescues it from being dropped', () {
    for (var i = 0; i < 8; i++) {
      notifier().add(i << 8 | 0xFF);
    }
    // 0 is oldest and about to fall off; re-pick it.
    notifier()
      ..add(0 << 8 | 0xFF)
      ..add(99 << 8 | 0xFF);

    expect(read(), contains(0 << 8 | 0xFF));
    expect(read(), hasLength(kMaxRecentColors));
  });

  test('the published list is unmodifiable', () {
    notifier().add(0x111111FF);
    expect(() => read().add(0x222222FF), throwsUnsupportedError);
  });

  test('clear empties the list', () {
    notifier()
      ..add(0x111111FF)
      ..clear();
    expect(read(), isEmpty);
  });
}
