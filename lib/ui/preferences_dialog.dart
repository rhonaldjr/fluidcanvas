import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:inkpad/domain/commands/commands.dart';
import 'package:inkpad/domain/models/models.dart';
import 'package:inkpad/engine/renderer/layer_cache.dart' show colorFromRGBA;
import 'package:inkpad/state/state.dart';
import 'package:inkpad/ui/color_picker_dialog.dart';

Future<void> showPreferencesDialog(BuildContext context) => showDialog<void>(
  context: context,
  builder: (context) => const PreferencesDialog(),
);

/// Edit → Preferences. Everything here is a default for *new* work.
///
/// Nothing is written until Save, so a slider dragged and then cancelled leaves
/// the stored settings alone.
class PreferencesDialog extends ConsumerStatefulWidget {
  const PreferencesDialog({super.key});

  @override
  ConsumerState<PreferencesDialog> createState() => _PreferencesDialogState();
}

class _PreferencesDialogState extends ConsumerState<PreferencesDialog> {
  Preferences? _draft;

  Preferences get _prefs =>
      _draft ?? ref.read(preferencesProvider).value ?? const Preferences();

  void _edit(Preferences next) => setState(() => _draft = next);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final prefs = _prefs;

    return AlertDialog(
      key: const Key('preferences-dialog'),
      title: const Text('Preferences'),
      content: SizedBox(
        width: 520,
        height: 520,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _section(theme, 'New documents'),
              Row(
                children: [
                  Expanded(
                    child: _intField(
                      key: 'pref-canvas-width',
                      label: 'Width',
                      value: prefs.canvasWidth,
                      onChanged: (v) => _edit(prefs.copyWith(canvasWidth: v)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _intField(
                      key: 'pref-canvas-height',
                      label: 'Height',
                      value: prefs.canvasHeight,
                      onChanged: (v) => _edit(prefs.copyWith(canvasHeight: v)),
                    ),
                  ),
                ],
              ),
              CheckboxListTile(
                key: const Key('pref-fit'),
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                value: prefs.fitNewToWindow,
                onChanged: (v) =>
                    _edit(prefs.copyWith(fitNewToWindow: v ?? false)),
                title: const Text('Fit new documents to the window'),
              ),

              _section(theme, 'Autosave'),
              Row(
                children: [
                  Expanded(
                    child: Slider(
                      key: const Key('pref-autosave'),
                      min: kMinAutosaveMinutes.toDouble(),
                      max: kMaxAutosaveMinutes.toDouble(),
                      divisions: kMaxAutosaveMinutes,
                      value: prefs.autosaveMinutes.toDouble(),
                      label: '${prefs.autosaveMinutes} min',
                      onChanged: (v) =>
                          _edit(prefs.copyWith(autosaveMinutes: v.round())),
                    ),
                  ),
                  SizedBox(
                    width: 84,
                    child: Text(
                      key: const Key('pref-autosave-label'),
                      prefs.autosaveEnabled
                          ? 'every ${prefs.autosaveMinutes} min'
                          : 'off',
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                ],
              ),

              _section(theme, 'Default brush'),
              Row(
                children: [
                  _colorButton(
                    'pref-brush-color',
                    prefs.brush.colorRGBA,
                    (rgba) => _edit(
                      prefs.copyWith(
                        brush: prefs.brush.copyWith(colorRGBA: rgba),
                      ),
                    ),
                  ),
                  Expanded(
                    child: Slider(
                      key: const Key('pref-brush-width'),
                      min: kMinBrushWidth,
                      max: kMaxBrushWidth,
                      value: prefs.brush.baseWidth,
                      label: '${prefs.brush.baseWidth.round()} px',
                      onChanged: (v) => _edit(
                        prefs.copyWith(
                          brush: prefs.brush.copyWith(baseWidth: v),
                        ),
                      ),
                    ),
                  ),
                ],
              ),

              _section(theme, 'Default shape style'),
              Row(
                children: [
                  _colorButton(
                    'pref-shape-color',
                    prefs.shapeStyle.strokeColorRGBA,
                    (rgba) => _edit(
                      prefs.copyWith(
                        shapeStyle: prefs.shapeStyle.copyWith(
                          strokeColorRGBA: rgba,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  SegmentedButton<StrokeStyle>(
                    key: const Key('pref-shape-style'),
                    segments: const [
                      ButtonSegment(
                        value: StrokeStyle.solid,
                        label: Text('Solid'),
                      ),
                      ButtonSegment(
                        value: StrokeStyle.dashed,
                        label: Text('Dashed'),
                      ),
                      ButtonSegment(
                        value: StrokeStyle.dotted,
                        label: Text('Dotted'),
                      ),
                    ],
                    selected: {prefs.shapeStyle.strokeStyle},
                    onSelectionChanged: (values) => _edit(
                      prefs.copyWith(
                        shapeStyle: prefs.shapeStyle.copyWith(
                          strokeStyle: values.single,
                        ),
                      ),
                    ),
                  ),
                ],
              ),

              _section(theme, 'Theme'),
              SegmentedButton<ThemeMode>(
                key: const Key('pref-theme'),
                segments: const [
                  ButtonSegment(value: ThemeMode.system, label: Text('System')),
                  ButtonSegment(value: ThemeMode.light, label: Text('Light')),
                  ButtonSegment(value: ThemeMode.dark, label: Text('Dark')),
                ],
                selected: {prefs.themeMode},
                onSelectionChanged: (values) =>
                    _edit(prefs.copyWith(themeMode: values.single)),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          key: const Key('pref-reset'),
          onPressed: () async {
            await ref.read(preferencesProvider.notifier).reset();
            if (context.mounted) Navigator.pop(context);
          },
          child: const Text('Restore defaults'),
        ),
        TextButton(
          key: const Key('pref-cancel'),
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const Key('pref-save'),
          onPressed: () async {
            await ref.read(preferencesProvider.notifier).save(_prefs);
            if (context.mounted) Navigator.pop(context);
          },
          child: const Text('Save'),
        ),
      ],
    );
  }

  Widget _section(ThemeData theme, String title) => Padding(
    padding: const EdgeInsets.only(top: 16, bottom: 6),
    child: Text(title, style: theme.textTheme.titleSmall),
  );

  Widget _intField({
    required String key,
    required String label,
    required int value,
    required ValueChanged<int> onChanged,
  }) => TextFormField(
    key: Key(key),
    initialValue: '$value',
    decoration: InputDecoration(
      labelText: label,
      isDense: true,
      border: const OutlineInputBorder(),
    ),
    keyboardType: TextInputType.number,
    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
    onChanged: (text) {
      final parsed = int.tryParse(text);
      if (parsed == null) return;
      onChanged(parsed.clamp(kMinCanvasWidth, kMaxCanvasWidth));
    },
  );

  Widget _colorButton(String key, int rgba, ValueChanged<int> onPicked) =>
      InkWell(
        key: Key(key),
        onTap: () async {
          final picked = await showColorPickerDialog(
            context,
            initialRGBA: rgba,
          );
          if (picked != null) onPicked(picked);
        },
        child: Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: colorFromRGBA(rgba),
            shape: BoxShape.circle,
            border: Border.all(color: Theme.of(context).dividerColor),
          ),
        ),
      );
}
