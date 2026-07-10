import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:inkpad/engine/renderer/document_painter.dart';
import 'package:inkpad/engine/stabilizer.dart';
import 'package:inkpad/state/state.dart';
import 'package:inkpad/ui/color_picker_dialog.dart';

/// Width of the left tool strip, in screen pixels.
const double kToolbarStripWidth = 76;

/// The left tool strip: brush width and colour.
///
/// Task 8.1 adds the shape tools here.
class ToolbarStrip extends StatelessWidget {
  const ToolbarStrip({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      key: const Key('toolbar-strip'),
      width: kToolbarStripWidth,
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        border: Border(right: BorderSide(color: theme.dividerColor)),
      ),
      child: const SingleChildScrollView(
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 12),
          child: Column(
            children: [
              ToolSelector(),
              SizedBox(height: 12),
              BrushWidthControl(),
              SizedBox(height: 16),
              ColorSwatches(),
              SizedBox(height: 12),
              CustomColorButton(),
              RecentColorsRow(),
              SizedBox(height: 12),
              StabilizerControl(),
            ],
          ),
        ),
      ),
    );
  }
}

/// Pen / eraser toggle.
class ToolSelector extends ConsumerWidget {
  const ToolSelector({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tool = ref.watch(toolProvider);

    return Column(
      children: [
        for (final (value, icon, label) in [
          (Tool.pen, Icons.edit, 'Pen'),
          (Tool.eraser, Icons.cleaning_services, 'Eraser'),
        ])
          IconButton(
            key: Key('tool-${value.name}'),
            tooltip: label,
            isSelected: tool == value,
            icon: Icon(icon),
            selectedIcon: Icon(
              icon,
              color: Theme.of(context).colorScheme.primary,
            ),
            style: IconButton.styleFrom(
              backgroundColor: tool == value
                  ? Theme.of(context).colorScheme.primaryContainer
                  : null,
            ),
            onPressed: () => ref.read(toolProvider.notifier).select(value),
          ),
      ],
    );
  }
}

/// Brush width, 1..64 document pixels, with a live preview dot.
class BrushWidthControl extends ConsumerWidget {
  const BrushWidthControl({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final width = ref.watch(brushProvider).baseWidth;

    return Column(
      children: [
        // The preview never grows past the strip, so a 64px brush still fits.
        SizedBox(
          height: 34,
          child: Center(
            child: Container(
              key: const Key('brush-preview'),
              width: width.clamp(kMinBrushWidth, 32),
              height: width.clamp(kMinBrushWidth, 32),
              decoration: BoxDecoration(
                color: colorFromRGBA(ref.watch(brushProvider).colorRGBA),
                shape: BoxShape.circle,
                border: Border.all(color: Theme.of(context).dividerColor),
              ),
            ),
          ),
        ),
        SizedBox(
          height: 160,
          // A vertical slider: the strip is tall and narrow.
          child: RotatedBox(
            quarterTurns: 3,
            child: Slider(
              key: const Key('brush-width-slider'),
              min: kMinBrushWidth,
              max: kMaxBrushWidth,
              value: width,
              onChanged: (value) =>
                  ref.read(brushProvider.notifier).setWidth(value),
            ),
          ),
        ),
        Text('${width.round()}', style: Theme.of(context).textTheme.labelSmall),
      ],
    );
  }
}

/// The eight fixed colours, two per row.
class ColorSwatches extends ConsumerWidget {
  const ColorSwatches({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(brushProvider).colorRGBA;

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      alignment: WrapAlignment.center,
      children: [
        for (final color in kSwatchColors)
          ColorSwatch_(
            key: Key('swatch-${color.toRadixString(16)}'),
            colorRGBA: color,
            selected: color == selected,
            onTap: () => ref.read(brushProvider.notifier).setColor(color),
          ),
      ],
    );
  }
}

/// Input stabilization strength, 0 (off) to 10.
class StabilizerControl extends ConsumerWidget {
  const StabilizerControl({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strength = ref.watch(stabilizerStrengthProvider);
    final theme = Theme.of(context);

    return Column(
      children: [
        Text('Stab.', style: theme.textTheme.labelSmall),
        SizedBox(
          height: 120,
          child: RotatedBox(
            quarterTurns: 3,
            child: Slider(
              key: const Key('stabilizer-slider'),
              max: kMaxStabilizerStrength.toDouble(),
              divisions: kMaxStabilizerStrength,
              value: strength.toDouble(),
              onChanged: (value) => ref
                  .read(stabilizerStrengthProvider.notifier)
                  .set(value.round()),
            ),
          ),
        ),
        Text(
          strength == 0 ? 'off' : '$strength',
          style: theme.textTheme.labelSmall,
        ),
      ],
    );
  }
}

/// Opens the HSV picker. The picked colour becomes the brush colour and joins
/// the recent-colours row.
class CustomColorButton extends ConsumerWidget {
  const CustomColorButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return IconButton(
      key: const Key('custom-color-button'),
      tooltip: 'Custom colour',
      icon: const Icon(Icons.colorize),
      onPressed: () async {
        final picked = await showColorPickerDialog(
          context,
          initialRGBA: ref.read(brushProvider).colorRGBA,
        );
        if (picked == null) return;
        ref.read(brushProvider.notifier).setColor(picked);
        ref.read(recentColorsProvider.notifier).add(picked);
      },
    );
  }
}

/// The colours picked from the dialog, most recent first. Hidden when empty.
class RecentColorsRow extends ConsumerWidget {
  const RecentColorsRow({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recent = ref.watch(recentColorsProvider);
    if (recent.isEmpty) return const SizedBox.shrink();

    final selected = ref.watch(brushProvider).colorRGBA;
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        alignment: WrapAlignment.center,
        children: [
          for (final color in recent)
            ColorSwatch_(
              key: Key('recent-${color.toRadixString(16)}'),
              colorRGBA: color,
              selected: color == selected,
              onTap: () => ref.read(brushProvider.notifier).setColor(color),
            ),
        ],
      ),
    );
  }
}

/// One tappable colour square.
// ignore: camel_case_types — `ColorSwatch` is taken by Flutter.
class ColorSwatch_ extends StatelessWidget {
  const ColorSwatch_({
    required this.colorRGBA,
    required this.selected,
    required this.onTap,
    super.key,
  });

  final int colorRGBA;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      selected: selected,
      button: true,
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            color: colorFromRGBA(colorRGBA),
            shape: BoxShape.circle,
            border: Border.all(
              color: selected ? theme.colorScheme.primary : theme.dividerColor,
              width: selected ? 3 : 1,
            ),
          ),
        ),
      ),
    );
  }
}
