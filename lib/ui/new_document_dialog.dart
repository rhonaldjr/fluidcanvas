import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:inkpad/domain/commands/commands.dart';

/// The canvas a new document starts with.
typedef NewDocumentChoice = ({int width, int height, bool fitToWindow});

/// Named canvas sizes, plus the fit-to-window default.
class CanvasPreset {
  const CanvasPreset(this.name, this.width, this.height);

  final String name;
  final int width;
  final int height;

  @override
  String toString() => '$name ($width × $height)';
}

const List<CanvasPreset> kCanvasPresets = [
  CanvasPreset('HD', 1920, 1080),
  CanvasPreset('4K', 3840, 2160),
  CanvasPreset('Square', 1080, 1080),
  CanvasPreset('A4 at 150dpi', 1240, 1754),
  CanvasPreset('A4 landscape', 1754, 1240),
];

/// Asks for the new document's canvas size. `null` when cancelled.
///
/// [defaults] seeds the fields — task 15.3's stored preference, or the
/// built-in default when none has been saved.
Future<NewDocumentChoice?> showNewDocumentDialog(
  BuildContext context, {
  NewDocumentChoice defaults = (width: 1920, height: 1080, fitToWindow: true),
}) => showDialog<NewDocumentChoice>(
  context: context,
  builder: (context) => NewDocumentDialog(defaults: defaults),
);

class NewDocumentDialog extends StatefulWidget {
  const NewDocumentDialog({
    this.defaults = (width: 1920, height: 1080, fitToWindow: true),
    super.key,
  });

  final NewDocumentChoice defaults;

  @override
  State<NewDocumentDialog> createState() => _NewDocumentDialogState();
}

class _NewDocumentDialogState extends State<NewDocumentDialog> {
  /// On by default: a new document that tracks the window is what every
  /// previous phase produced, and 8.5 keeps that the default.
  late bool _fitToWindow = widget.defaults.fitToWindow;

  late final _width = TextEditingController(text: '${widget.defaults.width}');
  late final _height = TextEditingController(text: '${widget.defaults.height}');

  @override
  void dispose() {
    _width.dispose();
    _height.dispose();
    super.dispose();
  }

  /// The typed size, clamped to what a canvas may be. Falsy input keeps the
  /// preset rather than opening a 0×0 document.
  NewDocumentChoice get _choice => (
    width: (int.tryParse(_width.text) ?? kMinCanvasWidth).clamp(
      kMinCanvasWidth,
      kMaxCanvasWidth,
    ),
    height: (int.tryParse(_height.text) ?? kMinCanvasHeight).clamp(
      kMinCanvasHeight,
      kMaxCanvasHeight,
    ),
    fitToWindow: _fitToWindow,
  );

  void _usePreset(CanvasPreset preset) => setState(() {
    _width.text = '${preset.width}';
    _height.text = '${preset.height}';
  });

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      key: const Key('new-document'),
      title: const Text('New document'),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 8,
              children: [
                for (final preset in kCanvasPresets)
                  ActionChip(
                    key: Key('preset-${preset.name}'),
                    label: Text(preset.name),
                    onPressed: () => _usePreset(preset),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(child: _sizeField('Width', _width, 'new-doc-width')),
                const SizedBox(width: 12),
                Expanded(
                  child: _sizeField('Height', _height, 'new-doc-height'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            CheckboxListTile(
              key: const Key('new-doc-fit'),
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              value: _fitToWindow,
              onChanged: (value) =>
                  setState(() => _fitToWindow = value ?? false),
              title: const Text('Fit canvas to window'),
              subtitle: const Text(
                'The canvas follows the window, scaling what you have drawn.',
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          key: const Key('new-doc-cancel'),
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const Key('new-doc-create'),
          onPressed: () => Navigator.pop(context, _choice),
          child: const Text('Create'),
        ),
      ],
    );
  }

  Widget _sizeField(
    String label,
    TextEditingController controller,
    String id,
  ) => TextField(
    key: Key(id),
    controller: controller,
    enabled: !_fitToWindow,
    keyboardType: TextInputType.number,
    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
    decoration: InputDecoration(
      labelText: label,
      isDense: true,
      border: const OutlineInputBorder(),
      helperText: _fitToWindow ? 'Set by the window' : null,
    ),
  );
}
