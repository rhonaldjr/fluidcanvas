import 'package:flutter/material.dart';

/// One row of the reference: what to press, and what it does.
typedef ShortcutRow = ({String keys, String action});

/// Everything [kAppShortcuts] binds, grouped as a user thinks of them.
///
/// Written out rather than derived from the shortcut map: `SingleActivator`
/// knows it is Ctrl+Z, not that Ctrl+Z is "Undo", and a generated list would
/// read like a keymap dump.
const Map<String, List<ShortcutRow>> kShortcutReference = {
  'Tools': [
    (keys: 'V', action: 'Select'),
    (keys: 'B', action: 'Pen'),
    (keys: 'E', action: 'Eraser'),
    (keys: 'R', action: 'Rectangle'),
    (keys: 'O', action: 'Ellipse'),
    (keys: 'L', action: 'Line'),
    (keys: 'A', action: 'Arrow'),
    (keys: 'D', action: 'Diamond'),
    (keys: 'T', action: 'Text'),
    (keys: 'C', action: 'Connector'),
    (keys: '[  ]', action: 'Brush thinner / thicker'),
  ],
  'Edit': [
    (keys: 'Ctrl+Z', action: 'Undo'),
    (keys: 'Ctrl+Shift+Z', action: 'Redo'),
    (keys: 'Ctrl+A', action: 'Select all'),
    (keys: 'Esc', action: 'Deselect'),
    (keys: 'Delete', action: 'Delete the selection'),
    (keys: 'Ctrl+D', action: 'Duplicate the selection'),
    (keys: 'Arrows', action: 'Nudge by 1px (Shift: 10px)'),
    (keys: 'Ctrl+]  Ctrl+[', action: 'Bring forward / send back'),
    (keys: 'Ctrl+B / I / U', action: 'Bold, italic, underline'),
    (keys: 'Ctrl+G', action: 'Group the selection'),
    (keys: 'Ctrl+Shift+G', action: 'Ungroup'),
    (keys: 'Alt+drag', action: 'Move without snapping'),
  ],
  'View': [
    (keys: 'Ctrl+scroll', action: 'Zoom about the cursor'),
    (keys: 'Ctrl+=  Ctrl+-', action: 'Zoom in / out'),
    (keys: 'Ctrl+0', action: 'Fit the page to the window'),
    (keys: 'Space+drag', action: 'Pan'),
    (keys: 'Middle-drag', action: 'Pan'),
  ],
  'File and tabs': [
    (keys: 'Ctrl+N', action: 'New document'),
    (keys: 'Ctrl+O', action: 'Open'),
    (keys: 'Ctrl+S', action: 'Save'),
    (keys: 'Ctrl+Shift+S', action: 'Save As'),
    (keys: 'Ctrl+T', action: 'New tab'),
    (keys: 'Ctrl+W', action: 'Close tab'),
    (keys: 'Ctrl+Tab', action: 'Next tab (Shift: previous)'),
    (keys: 'Ctrl+1…8', action: 'Go to the nth tab'),
    (keys: 'Ctrl+9', action: 'Go to the last tab'),
  ],
};

Future<void> showShortcutsDialog(BuildContext context) => showDialog<void>(
  context: context,
  builder: (context) => const ShortcutsDialog(),
);

/// Help → Keyboard Shortcuts.
class ShortcutsDialog extends StatelessWidget {
  const ShortcutsDialog({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AlertDialog(
      key: const Key('shortcuts-dialog'),
      title: const Text('Keyboard shortcuts'),
      content: SizedBox(
        width: 520,
        height: 460,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final group in kShortcutReference.entries) ...[
                Padding(
                  padding: const EdgeInsets.only(top: 12, bottom: 6),
                  child: Text(group.key, style: theme.textTheme.titleSmall),
                ),
                for (final row in group.value)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 160,
                          child: Text(
                            row.keys,
                            style: theme.textTheme.bodySmall?.copyWith(
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        Expanded(
                          child: Text(
                            row.action,
                            style: theme.textTheme.bodySmall,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        FilledButton(
          key: const Key('shortcuts-close'),
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    );
  }
}
