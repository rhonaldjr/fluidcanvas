import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inkpad/state/state.dart';

void main() {
  late ProviderContainer container;

  setUp(() => container = ProviderContainer.test());

  Brush read() => container.read(brushProvider);
  BrushNotifier notifier() => container.read(brushProvider.notifier);

  group('Brush', () {
    test('defaults to near-black at 4px', () {
      expect(read().colorRGBA, kDefaultBrushColorRGBA);
      expect(read().baseWidth, 4);
    });

    test('rejects a width outside the slider range', () {
      expect(() => Brush(baseWidth: 0), throwsA(isA<AssertionError>()));
      expect(() => Brush(baseWidth: 65), throwsA(isA<AssertionError>()));
    });

    test('copyWith replaces only the named field', () {
      const brush = Brush(colorRGBA: 0xFF0000FF, baseWidth: 10);
      expect(brush.copyWith(baseWidth: 20).colorRGBA, 0xFF0000FF);
      expect(brush.copyWith(colorRGBA: 0x00FF00FF).baseWidth, 10);
    });

    test('value equality', () {
      expect(const Brush(baseWidth: 8), const Brush(baseWidth: 8));
      expect(
        const Brush(baseWidth: 8).hashCode,
        const Brush(baseWidth: 8).hashCode,
      );
      expect(const Brush(baseWidth: 8), isNot(const Brush(baseWidth: 9)));
    });
  });

  group('swatches', () {
    test('there are exactly eight', () {
      expect(kSwatchColors, hasLength(8));
    });

    test('all are opaque and distinct', () {
      expect(kSwatchColors.toSet(), hasLength(8));
      for (final color in kSwatchColors) {
        expect(color & 0xFF, 0xFF, reason: 'swatch must be fully opaque');
      }
    });

    test('the default brush colour is the first swatch', () {
      expect(kSwatchColors.first, kDefaultBrushColorRGBA);
    });
  });

  group('BrushNotifier', () {
    test('setWidth updates the width', () {
      notifier().setWidth(20);
      expect(read().baseWidth, 20);
    });

    test('setWidth clamps rather than throwing', () {
      // A keyboard nudge past the end should stop, not crash.
      notifier().setWidth(1000);
      expect(read().baseWidth, kMaxBrushWidth);

      notifier().setWidth(-5);
      expect(read().baseWidth, kMinBrushWidth);
    });

    test('setColor updates the colour and leaves the width alone', () {
      notifier()
        ..setWidth(30)
        ..setColor(0xE53935FF);

      expect(read().colorRGBA, 0xE53935FF);
      expect(read().baseWidth, 30);
    });

    test('publishes a new value so watchers rebuild', () {
      final before = read();
      notifier().setWidth(9);
      expect(read(), isNot(before));
    });
  });
}
