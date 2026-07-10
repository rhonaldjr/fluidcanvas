import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inkpad/engine/renderer/document_painter.dart';
import 'package:inkpad/state/state.dart';
import 'package:inkpad/ui/ui.dart';

void main() {
  group('rgbaFromColor', () {
    test('round-trips through colorFromRGBA', () {
      for (final rgba in [
        0x000000FF,
        0xFFFFFFFF,
        0x1B1B1FFF,
        0xE53935FF,
        0x1E88E5FF,
        0x12345678,
      ]) {
        expect(rgbaFromColor(colorFromRGBA(rgba)), rgba, reason: '0x$rgba');
      }
    });

    test('packs channels in RRGGBBAA order, not ARGB', () {
      // Opaque pure red.
      expect(rgbaFromColor(const Color(0xFFFF0000)), 0xFF0000FF);
      // Opaque pure blue: blue is the third byte, not the first.
      expect(rgbaFromColor(const Color(0xFF0000FF)), 0x0000FFFF);
    });

    test('carries alpha in the low byte', () {
      expect(rgbaFromColor(const Color(0x00FF0000)) & 0xFF, 0x00);
      expect(rgbaFromColor(const Color(0xFFFF0000)) & 0xFF, 0xFF);
    });
  });

  group('dialog', () {
    Future<ProviderContainer> pumpToolbar(WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(600, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final container = ProviderContainer.test();
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: Scaffold(
              body: Row(
                children: [
                  ToolbarStrip(),
                  Expanded(child: SizedBox()),
                ],
              ),
            ),
          ),
        ),
      );
      return container;
    }

    testWidgets('the custom-colour button opens the picker', (tester) async {
      await pumpToolbar(tester);
      expect(find.byType(ColorPickerDialog), findsNothing);

      await tester.tap(find.byKey(const Key('custom-color-button')));
      await tester.pumpAndSettle();

      expect(find.byType(ColorPickerDialog), findsOneWidget);
      expect(find.byKey(const Key('sv-square')), findsOneWidget);
      expect(find.byKey(const Key('hue-slider')), findsOneWidget);
    });

    testWidgets('the picker opens on the current brush colour', (tester) async {
      final container = await pumpToolbar(tester);
      container.read(brushProvider.notifier).setColor(0xE53935FF);
      await tester.pump();

      await tester.tap(find.byKey(const Key('custom-color-button')));
      await tester.pumpAndSettle();

      final dialog = tester.widget<ColorPickerDialog>(
        find.byType(ColorPickerDialog),
      );
      expect(dialog.initialRGBA, 0xE53935FF);
    });

    testWidgets('cancelling changes nothing', (tester) async {
      final container = await pumpToolbar(tester);

      await tester.tap(find.byKey(const Key('custom-color-button')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(container.read(brushProvider).colorRGBA, kDefaultBrushColorRGBA);
      expect(container.read(recentColorsProvider), isEmpty);
    });

    testWidgets('selecting sets the brush colour and records it as recent', (
      tester,
    ) async {
      final container = await pumpToolbar(tester);

      await tester.tap(find.byKey(const Key('custom-color-button')));
      await tester.pumpAndSettle();

      // Drag to a saturated point in the square, then confirm.
      final square = tester.getRect(find.byKey(const Key('sv-square')));
      await tester.tapAt(square.centerRight - const Offset(4, 0));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('color-picker-ok')));
      await tester.pumpAndSettle();

      final picked = container.read(brushProvider).colorRGBA;
      expect(picked, isNot(kDefaultBrushColorRGBA));
      expect(container.read(recentColorsProvider), [picked]);
    });

    testWidgets('the recent row appears only once a colour is picked', (
      tester,
    ) async {
      final container = await pumpToolbar(tester);
      expect(find.byType(RecentColorsRow), findsOneWidget);
      expect(find.byKey(const Key('recent-e53935ff')), findsNothing);

      container.read(recentColorsProvider.notifier).add(0xE53935FF);
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('recent-e53935ff')), findsOneWidget);
    });

    testWidgets('tapping a recent colour re-selects it', (tester) async {
      final container = await pumpToolbar(tester);
      container.read(recentColorsProvider.notifier).add(0x8E24AAFF);
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('recent-8e24aaff')));
      await tester.pump();

      expect(container.read(brushProvider).colorRGBA, 0x8E24AAFF);
    });

    testWidgets('the hue slider changes the preview', (tester) async {
      await pumpToolbar(tester);
      await tester.tap(find.byKey(const Key('custom-color-button')));
      await tester.pumpAndSettle();

      Color previewColor() {
        final box = tester.widget<Container>(
          find.byKey(const Key('color-preview')),
        );
        return (box.decoration! as BoxDecoration).color!;
      }

      final before = previewColor();
      await tester.drag(
        find.byKey(const Key('hue-slider')),
        const Offset(60, 0),
      );
      await tester.pumpAndSettle();

      expect(previewColor(), isNot(before));
    });
  });
}
