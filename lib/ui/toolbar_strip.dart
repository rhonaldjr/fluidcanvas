import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:inkpad/engine/renderer/document_painter.dart';
import 'package:inkpad/engine/stabilizer.dart';
import 'package:inkpad/domain/models/models.dart';
import 'package:inkpad/state/state.dart';
import 'package:inkpad/ui/color_picker_dialog.dart';

/// Width of the left tool strip, in screen pixels.
const double kToolbarStripWidth = 76;

/// The left tool strip: brush width and colour.
///
/// Task 9.1 adds the shape tools here.
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
              ShapeStyleControls(),
              TextStyleControls(),
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
          (Tool.select, Icons.near_me_outlined, 'Select'),
          (Tool.pen, Icons.edit, 'Pen'),
          (Tool.eraser, Icons.cleaning_services, 'Eraser'),
          (Tool.rectangle, Icons.crop_square, 'Rectangle'),
          (Tool.ellipse, Icons.circle_outlined, 'Ellipse'),
          (Tool.line, Icons.remove, 'Line'),
          (Tool.arrow, Icons.arrow_forward, 'Arrow'),
          (Tool.diamond, Icons.change_history, 'Diamond'),
          (Tool.text, Icons.title, 'Text'),
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

/// Stroke width, fill, and dash style for shapes.
///
/// Shown when a shape tool is active or shapes are selected. Changing a control
/// restyles the selection when there is one, and always updates the defaults
/// new shapes are drawn with.
class ShapeStyleControls extends ConsumerWidget {
  const ShapeStyleControls({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tool = ref.watch(toolProvider);
    final selectedShapes = ref
        .watch(activeSessionProvider)
        .selectedElements
        .whereType<Shape>()
        .isNotEmpty;
    if (!tool.drawsShape && !selectedShapes) return const SizedBox.shrink();

    final style = ref.watch(shapeStyleProvider);
    final sessions = ref.read(sessionsProvider.notifier);
    final theme = Theme.of(context);

    return Column(
      key: const Key('shape-style'),
      children: [
        Text('Shape', style: theme.textTheme.labelSmall),
        IconButton(
          key: const Key('shape-fill'),
          tooltip: style.isFilled ? 'Remove fill' : 'Fill with brush colour',
          isSelected: style.isFilled,
          icon: Icon(
            style.isFilled ? Icons.format_color_reset : Icons.format_color_fill,
          ),
          onPressed: () {
            final fill = style.isFilled
                ? kNoFill
                : ref.read(brushProvider).colorRGBA;
            ref.read(shapeStyleProvider.notifier).setFillColor(fill);
            sessions.styleSelection(fillColorRGBA: fill);
          },
        ),
        for (final (value, icon, label) in [
          (StrokeStyle.solid, Icons.horizontal_rule, 'Solid'),
          (StrokeStyle.dashed, Icons.more_horiz, 'Dashed'),
          (StrokeStyle.dotted, Icons.more_vert, 'Dotted'),
        ])
          IconButton(
            key: Key('shape-style-${value.name}'),
            tooltip: label,
            isSelected: style.strokeStyle == value,
            iconSize: 18,
            icon: Icon(icon),
            onPressed: () {
              ref.read(shapeStyleProvider.notifier).setStrokeStyle(value);
              sessions.styleSelection(strokeStyle: value);
            },
          ),
        SizedBox(
          height: 100,
          child: RotatedBox(
            quarterTurns: 3,
            child: Slider(
              key: const Key('shape-stroke-width'),
              min: 1,
              max: 32,
              value: style.strokeWidth.clamp(1, 32),
              onChanged: (v) =>
                  ref.read(shapeStyleProvider.notifier).setStrokeWidth(v),
              onChangeEnd: (v) => sessions.styleSelection(strokeWidth: v),
            ),
          ),
        ),
      ],
    );
  }
}

/// Font size and bold/italic/underline for text.
///
/// The B/I/U buttons apply to the selected characters when a range is
/// selected, and to the whole element otherwise.
class TextStyleControls extends ConsumerWidget {
  const TextStyleControls({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tool = ref.watch(toolProvider);
    final editing = ref.watch(textEditingProvider);
    final selectedText = ref
        .watch(activeSessionProvider)
        .selectedElements
        .whereType<TextElement>()
        .firstOrNull;

    if (!tool.drawsText && editing == null && selectedText == null) {
      return const SizedBox.shrink();
    }

    final theme = Theme.of(context);
    final style = ref.watch(textStyleProvider);

    return Column(
      key: const Key('text-style'),
      children: [
        Text('Text', style: theme.textTheme.labelSmall),
        // A Row overflows the 76px strip; let the buttons wrap onto a second
        // line instead.
        Wrap(
          alignment: WrapAlignment.center,
          children: [
            for (final (key, icon, apply) in [
              ('bold', Icons.format_bold, _Attr.bold),
              ('italic', Icons.format_italic, _Attr.italic),
              ('underline', Icons.format_underlined, _Attr.underline),
            ])
              IconButton(
                key: Key('text-$key'),
                iconSize: 16,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints.tightFor(
                  width: 22,
                  height: 22,
                ),
                icon: Icon(icon),
                onPressed: () => _toggle(ref, apply),
              ),
          ],
        ),
        SizedBox(
          width: 56,
          child: TextField(
            key: const Key('text-size'),
            decoration: const InputDecoration(isDense: true, labelText: 'size'),
            controller: TextEditingController(
              text: '${style.fontSize.round()}',
            ),
            keyboardType: TextInputType.number,
            onSubmitted: (value) {
              final size = double.tryParse(value);
              if (size == null) return;
              ref.read(textStyleProvider.notifier).setSize(size);
              final element = ref
                  .read(activeSessionProvider)
                  .selectedElements
                  .whereType<TextElement>()
                  .firstOrNull;
              if (element != null) {
                ref
                    .read(sessionsProvider.notifier)
                    .styleTextElement(element, fontSize: size);
              }
            },
          ),
        ),
      ],
    );
  }

  /// Applies to the selected characters, or the whole element when nothing is
  /// selected. Toggling turns a range *on* unless every character already has
  /// it — so bolding a half-bold selection bolds all of it first.
  void _toggle(WidgetRef ref, _Attr attr) {
    final sessions = ref.read(sessionsProvider.notifier);
    final editing = ref.read(textEditingProvider);

    TextElement? element;
    var start = 0;
    var end = 0;

    if (editing != null) {
      final found = ref
          .read(activeDocumentProvider)
          .findElement(editing.elementId);
      element = found?.element as TextElement?;
      if (element == null) return;
      element = element.copyWith(runs: editing.runs);
      start = editing.hasSelection ? editing.selectionStart : 0;
      end = editing.hasSelection ? editing.selectionEnd : element.length;
    } else {
      element = ref
          .read(activeSessionProvider)
          .selectedElements
          .whereType<TextElement>()
          .firstOrNull;
      if (element == null) return;
      end = element.length;
    }
    if (end <= start) return;

    final on = !element.rangeHasStyle(start, end, attr.read);
    final runs = element.runsWithStyle(
      start,
      end,
      bold: attr == _Attr.bold ? on : null,
      italic: attr == _Attr.italic ? on : null,
      underline: attr == _Attr.underline ? on : null,
    );

    if (editing != null) {
      ref.read(textEditingProvider.notifier).setRuns(runs);
    } else {
      sessions.commitTextEdit(element, runs);
    }
  }
}

enum _Attr {
  bold,
  italic,
  underline;

  bool read(TextRun run) => switch (this) {
    _Attr.bold => run.bold,
    _Attr.italic => run.italic,
    _Attr.underline => run.underline,
  };
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
