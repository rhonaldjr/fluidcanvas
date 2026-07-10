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
          (Tool.pencil, Icons.draw, 'Pencil'),
          (Tool.airbrush, Icons.blur_on, 'Airbrush'),
          (Tool.texture, Icons.grain, 'Texture'),
          (Tool.eraser, Icons.cleaning_services, 'Eraser'),
          (Tool.rectangle, Icons.crop_square, 'Rectangle'),
          (Tool.ellipse, Icons.circle_outlined, 'Ellipse'),
          (Tool.line, Icons.remove, 'Line'),
          (Tool.arrow, Icons.arrow_forward, 'Arrow'),
          (Tool.diamond, Icons.change_history, 'Diamond'),
          (Tool.text, Icons.title, 'Text'),
          (Tool.connector, Icons.timeline, 'Connector'),
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
        IconButton(
          key: const Key('shape-rough'),
          tooltip: style.renderStyle == ShapeRenderStyle.rough
              ? 'Draw shapes precisely'
              : 'Draw shapes by hand',
          isSelected: style.renderStyle == ShapeRenderStyle.rough,
          iconSize: 18,
          icon: const Icon(Icons.gesture),
          onPressed: () {
            final next = style.renderStyle == ShapeRenderStyle.rough
                ? ShapeRenderStyle.precise
                : ShapeRenderStyle.rough;
            ref.read(shapeStyleProvider.notifier).setRenderStyle(next);
            sessions.styleSelection(renderStyle: next);
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
        _ListStyleButtons(selected: selectedText),
        _TextPathButton(selected: selectedText),
        _FontFamilyPicker(selected: selectedText),
        if (selectedText != null &&
            !ref.watch(fontAvailabilityProvider)(selectedText.fontFamily))
          _MissingFontNotice(family: selectedText.fontFamily),
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
              if (size == null || size <= 0) return;
              ref.read(textStyleProvider.notifier).setSize(size);
              applyTextRunStyle(
                ref,
                // A sub-range selected in the editor gets a per-run override;
                // a box merely selected has its base size changed.
                rangeRuns: (e, start, end) =>
                    e.runsWithFontSize(start, end, size),
                wholeElement: (e) => ref
                    .read(sessionsProvider.notifier)
                    .styleTextElement(e, fontSize: size),
              );
            },
          ),
        ),
        const SizedBox(height: 4),
        _TextColorButton(selected: selectedText),
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

/// Applies a text style change to the selected range when a box is being
/// edited, or to the whole element when one is merely selected.
///
/// [rangeRuns] builds the runs for an in-editor selection; it coalesces into
/// the running edit through `setRuns`, like the B/I/U buttons. [wholeElement]
/// runs for a selected-but-not-editing box, where size and colour change the
/// element's own defaults rather than laying a per-run override over every
/// character.
void applyTextRunStyle(
  WidgetRef ref, {
  required List<TextRun> Function(TextElement element, int start, int end)
  rangeRuns,
  required void Function(TextElement element) wholeElement,
}) {
  final editing = ref.read(textEditingProvider);
  if (editing != null) {
    final found = ref
        .read(activeDocumentProvider)
        .findElement(editing.elementId);
    var element = found?.element as TextElement?;
    if (element == null) return;
    element = element.copyWith(runs: editing.runs);
    final start = editing.hasSelection ? editing.selectionStart : 0;
    final end = editing.hasSelection ? editing.selectionEnd : element.length;
    if (end <= start) return;
    ref
        .read(textEditingProvider.notifier)
        .setRuns(rangeRuns(element, start, end));
    return;
  }
  final element = ref
      .read(activeSessionProvider)
      .selectedElements
      .whereType<TextElement>()
      .firstOrNull;
  if (element != null) wholeElement(element);
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

/// Chooses the family for new text, and restyles the selected box.
///
/// Only families the system can actually render are listed. The current family
/// is always listed even when it is missing, so the picker can show what the
/// file asked for rather than silently reading as the default.
class _FontFamilyPicker extends ConsumerWidget {
  const _FontFamilyPicker({required this.selected});

  final TextElement? selected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current =
        selected?.fontFamily ?? ref.watch(textStyleProvider).fontFamily;
    final installed = ref.watch(systemFontsProvider).value ?? const [];
    final families = <String>{'', ...installed, current}.toList();

    return SizedBox(
      width: 68,
      child: DropdownButton<String>(
        key: const Key('text-family'),
        value: current,
        isExpanded: true,
        isDense: true,
        underline: const SizedBox.shrink(),
        style: Theme.of(context).textTheme.labelSmall,
        items: [
          for (final family in families)
            DropdownMenuItem(
              value: family,
              child: Text(
                family.isEmpty ? 'System' : family,
                overflow: TextOverflow.ellipsis,
              ),
            ),
        ],
        onChanged: (family) {
          if (family == null) return;
          ref.read(textStyleProvider.notifier).setFamily(family);
          final element = selected;
          if (element != null) {
            ref
                .read(sessionsProvider.notifier)
                .styleTextElement(element, fontFamily: family);
          }
        },
      ),
    );
  }
}

/// Says out loud that a file named a font this machine does not have.
///
/// Without it the text renders in the default face and nothing explains why —
/// the box would just look wrong on one machine and right on another.
class _MissingFontNotice extends StatelessWidget {
  const _MissingFontNotice({required this.family});

  final String family;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Tooltip(
      message: '"$family" is not installed. Showing the default font instead.',
      child: SizedBox(
        key: const Key('text-font-missing'),
        width: 68,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.warning_amber, size: 12, color: theme.colorScheme.error),
            const SizedBox(width: 2),
            Flexible(
              child: Text(
                'missing',
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The text colour, picked with the same HSV dialog as the brush (task 4.3).
class _TextColorButton extends ConsumerWidget {
  const _TextColorButton({required this.selected});

  final TextElement? selected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rgba = selected?.colorRGBA ?? ref.watch(textStyleProvider).colorRGBA;

    return Tooltip(
      message: 'Text colour',
      child: InkWell(
        key: const Key('text-color'),
        onTap: () async {
          final picked = await showColorPickerDialog(
            context,
            initialRGBA: rgba,
          );
          if (picked == null) return;
          ref.read(textStyleProvider.notifier).setColor(picked);
          ref.read(recentColorsProvider.notifier).add(picked);
          applyTextRunStyle(
            ref,
            rangeRuns: (e, start, end) => e.runsWithColor(start, end, picked),
            wholeElement: (e) => ref
                .read(sessionsProvider.notifier)
                .styleTextElement(e, colorRGBA: picked),
          );
        },
        child: Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            color: colorFromRGBA(rgba),
            shape: BoxShape.circle,
            border: Border.all(color: Theme.of(context).dividerColor),
          ),
        ),
      ),
    );
  }
}

/// Bullet and numbered-list toggles for the selected text box.
class _ListStyleButtons extends ConsumerWidget {
  const _ListStyleButtons({required this.selected});

  final TextElement? selected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = selected?.listStyle ?? ListStyle.none;

    return Wrap(
      alignment: WrapAlignment.center,
      children: [
        for (final (key, icon, style) in [
          ('list-bullet', Icons.format_list_bulleted, ListStyle.bullet),
          ('list-numbered', Icons.format_list_numbered, ListStyle.numbered),
        ])
          IconButton(
            key: Key('text-$key'),
            iconSize: 16,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints.tightFor(width: 22, height: 22),
            isSelected: current == style,
            icon: Icon(icon),
            onPressed: () {
              final element = selected;
              if (element == null) return;
              // Clicking the active style turns the list back off.
              final next = current == style ? ListStyle.none : style;
              ref
                  .read(sessionsProvider.notifier)
                  .setTextListStyle(element, next);
            },
          ),
      ],
    );
  }
}

/// Flows the selected text along a selected sibling's outline, or detaches it.
///
/// Enabled only when the action would do something: one text box plus one
/// element with an outline, or a text box already on a path.
class _TextPathButton extends ConsumerWidget {
  const _TextPathButton({required this.selected});

  final TextElement? selected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final onPath = selected?.isOnPath ?? false;
    return IconButton(
      key: const Key('text-on-path'),
      iconSize: 16,
      tooltip: onPath
          ? 'Detach from path'
          : 'Flow along a selected shape or line',
      isSelected: onPath,
      icon: const Icon(Icons.text_rotation_none),
      onPressed: () => ref.read(sessionsProvider.notifier).toggleTextOnPath(),
    );
  }
}
