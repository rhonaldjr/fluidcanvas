import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:inkpad/state/state.dart';

/// Undo the active session's most recent command.
class UndoIntent extends Intent {
  const UndoIntent();
}

/// Redo the active session's most recently undone command.
class RedoIntent extends Intent {
  const RedoIntent();
}

/// Keyboard shortcuts for undo and redo.
///
/// Control and Meta are both bound rather than switched on the platform: a
/// Linux user on an Apple keyboard, and the widget tests, both work either way,
/// and neither combination means anything else here.
const Map<ShortcutActivator, Intent> kUndoRedoShortcuts = {
  SingleActivator(LogicalKeyboardKey.keyZ, control: true): UndoIntent(),
  SingleActivator(LogicalKeyboardKey.keyZ, meta: true): UndoIntent(),
  SingleActivator(LogicalKeyboardKey.keyZ, control: true, shift: true):
      RedoIntent(),
  SingleActivator(LogicalKeyboardKey.keyZ, meta: true, shift: true):
      RedoIntent(),
  // Windows' second redo binding.
  SingleActivator(LogicalKeyboardKey.keyY, control: true): RedoIntent(),
};

/// The File/Edit menu bar.
///
/// File items are still disabled: Phase 11 wires them up.
class AppMenuBar extends ConsumerWidget {
  const AppMenuBar({super.key});

  static const _fileItems = ['New', 'Open…', 'Save', 'Save As…', 'Export PNG…'];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final session = ref.watch(activeSessionProvider);

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        border: Border(bottom: BorderSide(color: theme.dividerColor)),
      ),
      // MenuBar centers its children and paints its own surface; neither is
      // wanted here.
      child: Align(
        alignment: Alignment.centerLeft,
        child: MenuBar(
          style: const MenuStyle(
            elevation: WidgetStatePropertyAll(0),
            backgroundColor: WidgetStatePropertyAll(Colors.transparent),
            surfaceTintColor: WidgetStatePropertyAll(Colors.transparent),
            shape: WidgetStatePropertyAll(RoundedRectangleBorder()),
            padding: WidgetStatePropertyAll(
              EdgeInsets.symmetric(horizontal: 4),
            ),
          ),
          children: [
            SubmenuButton(
              menuChildren: [
                for (final item in _fileItems)
                  // Null onPressed renders the item disabled.
                  MenuItemButton(onPressed: null, child: Text(item)),
              ],
              child: const Text('File'),
            ),
            SubmenuButton(
              menuChildren: [
                MenuItemButton(
                  key: const Key('menu-undo'),
                  shortcut: const SingleActivator(
                    LogicalKeyboardKey.keyZ,
                    control: true,
                  ),
                  onPressed: session.canUndo
                      ? () => ref.read(sessionsProvider.notifier).undo()
                      : null,
                  child: Text(
                    session.canUndo
                        ? 'Undo ${session.commands.nextUndo.label}'
                        : 'Undo',
                  ),
                ),
                MenuItemButton(
                  key: const Key('menu-redo'),
                  shortcut: const SingleActivator(
                    LogicalKeyboardKey.keyZ,
                    control: true,
                    shift: true,
                  ),
                  onPressed: session.canRedo
                      ? () => ref.read(sessionsProvider.notifier).redo()
                      : null,
                  child: Text(
                    session.canRedo
                        ? 'Redo ${session.commands.nextRedo.label}'
                        : 'Redo',
                  ),
                ),
              ],
              child: const Text('Edit'),
            ),
          ],
        ),
      ),
    );
  }
}
