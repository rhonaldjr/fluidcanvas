import 'package:flutter/material.dart';
import 'package:inkpad/engine/export_png.dart';

/// What File → Export → PNG was asked for.
typedef ExportChoice = ({int scale, bool transparent});

/// Asks for the export scale and background. `null` when cancelled.
Future<ExportChoice?> showExportDialog(
  BuildContext context, {
  required int documentWidth,
  required int documentHeight,
}) => showDialog<ExportChoice>(
  context: context,
  builder: (context) => ExportDialog(
    documentWidth: documentWidth,
    documentHeight: documentHeight,
  ),
);

class ExportDialog extends StatefulWidget {
  const ExportDialog({
    required this.documentWidth,
    required this.documentHeight,
    super.key,
  });

  final int documentWidth;
  final int documentHeight;

  @override
  State<ExportDialog> createState() => _ExportDialogState();
}

class _ExportDialogState extends State<ExportDialog> {
  int _scale = 1;
  bool _transparent = false;

  /// Whether this scale would ask for a surface no machine will give us.
  bool _tooLarge(int scale) =>
      widget.documentWidth * scale > kMaxExportEdge ||
      widget.documentHeight * scale > kMaxExportEdge;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AlertDialog(
      key: const Key('export-dialog'),
      title: const Text('Export PNG'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Scale', style: theme.textTheme.labelLarge),
          const SizedBox(height: 8),
          SegmentedButton<int>(
            key: const Key('export-scale'),
            segments: [
              for (final scale in kExportScales)
                ButtonSegment(
                  value: scale,
                  label: Text('${scale}x'),
                  enabled: !_tooLarge(scale),
                ),
            ],
            selected: {_scale},
            onSelectionChanged: (values) =>
                setState(() => _scale = values.single),
          ),
          const SizedBox(height: 8),
          Text(
            key: const Key('export-size'),
            '${widget.documentWidth * _scale} × '
            '${widget.documentHeight * _scale} pixels',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          CheckboxListTile(
            key: const Key('export-transparent'),
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            value: _transparent,
            onChanged: (value) => setState(() => _transparent = value ?? false),
            title: const Text('Transparent background'),
            subtitle: const Text('Skip the document\'s background fill.'),
          ),
        ],
      ),
      actions: [
        TextButton(
          key: const Key('export-cancel'),
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const Key('export-confirm'),
          onPressed: () => Navigator.pop(context, (
            scale: _scale,
            transparent: _transparent,
          )),
          child: const Text('Export'),
        ),
      ],
    );
  }
}
