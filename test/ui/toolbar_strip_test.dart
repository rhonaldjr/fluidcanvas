import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inkpad/engine/stabilizer.dart';
import 'package:inkpad/state/state.dart';
import 'package:inkpad/ui/ui.dart';

Future<ProviderContainer> pumpToolbar(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(400, 1400));
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

Finder swatchFor(int rgba) =>
    find.byKey(Key('swatch-${rgba.toRadixString(16)}'));

void main() {
  testWidgets('renders all eight swatches and the width slider', (
    tester,
  ) async {
    await pumpToolbar(tester);

    expect(find.byType(ColorSwatch_), findsNWidgets(8));
    expect(find.byKey(const Key('brush-width-slider')), findsOneWidget);
    for (final color in kSwatchColors) {
      expect(swatchFor(color), findsOneWidget);
    }
  });

  testWidgets('tapping a swatch sets the brush colour', (tester) async {
    final container = await pumpToolbar(tester);
    expect(container.read(brushProvider).colorRGBA, kDefaultBrushColorRGBA);

    await tester.tap(swatchFor(0xE53935FF));
    await tester.pump();

    expect(container.read(brushProvider).colorRGBA, 0xE53935FF);
  });

  testWidgets('the selected swatch is marked selected', (tester) async {
    final container = await pumpToolbar(tester);
    container.read(brushProvider.notifier).setColor(0x1E88E5FF);
    await tester.pump();

    final selected = tester.widget<ColorSwatch_>(swatchFor(0x1E88E5FF));
    final other = tester.widget<ColorSwatch_>(swatchFor(0xE53935FF));
    expect(selected.selected, isTrue);
    expect(other.selected, isFalse);
  });

  testWidgets('the slider spans exactly the brush width range', (tester) async {
    await pumpToolbar(tester);
    final slider = tester.widget<Slider>(
      find.byKey(const Key('brush-width-slider')),
    );
    expect(slider.min, kMinBrushWidth);
    expect(slider.max, kMaxBrushWidth);
    expect(slider.value, 4);
  });

  testWidgets('dragging the slider changes the brush width', (tester) async {
    final container = await pumpToolbar(tester);
    final before = container.read(brushProvider).baseWidth;

    // The slider is rotated a quarter turn, so drag along the strip's height.
    await tester.drag(
      find.byKey(const Key('brush-width-slider')),
      const Offset(0, -60),
    );
    await tester.pump();

    expect(container.read(brushProvider).baseWidth, greaterThan(before));
  });

  testWidgets('the width label follows the brush', (tester) async {
    final container = await pumpToolbar(tester);
    container.read(brushProvider.notifier).setWidth(37);
    await tester.pump();

    expect(find.text('37'), findsOneWidget);
  });

  testWidgets('the preview dot takes the brush colour and never overflows', (
    tester,
  ) async {
    final container = await pumpToolbar(tester);
    container.read(brushProvider.notifier)
      ..setColor(0x43A047FF)
      ..setWidth(kMaxBrushWidth);
    await tester.pump();

    final preview = tester.getSize(find.byKey(const Key('brush-preview')));
    // Clamped so a 64px brush still fits a 76px strip.
    expect(preview.width, lessThanOrEqualTo(32));
    expect(tester.takeException(), isNull);
  });

  testWidgets('the pen is selected by default', (tester) async {
    final container = await pumpToolbar(tester);
    expect(container.read(toolProvider), Tool.pen);
    expect(find.byKey(const Key('tool-pen')), findsOneWidget);
    expect(find.byKey(const Key('tool-eraser')), findsOneWidget);
  });

  testWidgets('tapping the eraser selects it', (tester) async {
    final container = await pumpToolbar(tester);

    await tester.tap(find.byKey(const Key('tool-eraser')));
    await tester.pump();

    expect(container.read(toolProvider), Tool.eraser);

    await tester.tap(find.byKey(const Key('tool-pen')));
    await tester.pump();
    expect(container.read(toolProvider), Tool.pen);
  });

  testWidgets('the selected tool button is marked selected', (tester) async {
    final container = await pumpToolbar(tester);
    container.read(toolProvider.notifier).select(Tool.eraser);
    await tester.pump();

    final eraser = tester.widget<IconButton>(
      find.byKey(const Key('tool-eraser')),
    );
    final pen = tester.widget<IconButton>(find.byKey(const Key('tool-pen')));
    expect(eraser.isSelected, isTrue);
    expect(pen.isSelected, isFalse);
  });

  testWidgets('the stabilizer is off by default and reads "off"', (
    tester,
  ) async {
    final container = await pumpToolbar(tester);
    expect(container.read(stabilizerStrengthProvider), 0);
    expect(find.text('off'), findsOneWidget);
  });

  testWidgets('the stabilizer slider is stepped 0..10', (tester) async {
    await pumpToolbar(tester);
    final slider = tester.widget<Slider>(
      find.byKey(const Key('stabilizer-slider')),
    );
    expect(slider.min, 0);
    expect(slider.max, kMaxStabilizerStrength.toDouble());
    expect(slider.divisions, kMaxStabilizerStrength);
  });

  testWidgets('raising the stabilizer shows its strength', (tester) async {
    final container = await pumpToolbar(tester);
    container.read(stabilizerStrengthProvider.notifier).set(7);
    await tester.pump();

    expect(find.text('7'), findsOneWidget);
    expect(find.text('off'), findsNothing);
  });
}
