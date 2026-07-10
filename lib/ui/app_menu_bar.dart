import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:inkpad/engine/view_transform.dart';
import 'package:path/path.dart' as p;
import 'package:inkpad/state/state.dart';
import 'package:inkpad/ui/file_actions.dart';
import 'package:inkpad/ui/preferences_dialog.dart';
import 'package:inkpad/ui/shortcuts_dialog.dart';

/// Undo the active session's most recent command.
class UndoIntent extends Intent {
  const UndoIntent();
}

/// Redo the active session's most recently undone command.
class RedoIntent extends Intent {
  const RedoIntent();
}

/// Delete the selection.
class DeleteSelectionIntent extends Intent {
  const DeleteSelectionIntent();
}

/// Duplicate the selection, offset a little.
class DuplicateSelectionIntent extends Intent {
  const DuplicateSelectionIntent();
}

/// Select every element on every visible layer.
class SelectAllIntent extends Intent {
  const SelectAllIntent();
}

/// Drop the selection.
class DeselectIntent extends Intent {
  const DeselectIntent();
}

/// Nudge the selection by one document pixel, or ten with Shift.
class NudgeIntent extends Intent {
  const NudgeIntent(this.dx, this.dy);

  final double dx;
  final double dy;
}

/// Open a new tab. Ctrl/Cmd+T.
class NewTabIntent extends Intent {
  const NewTabIntent();
}

/// Close the active tab. Ctrl/Cmd+W.
class CloseTabIntent extends Intent {
  const CloseTabIntent();
}

/// Step [delta] tabs to the right, wrapping. Ctrl+Tab, Ctrl+Shift+Tab.
class CycleTabIntent extends Intent {
  const CycleTabIntent(this.delta);

  final int delta;
}

/// Jump to the nth tab. Ctrl/Cmd+1..8; 9 means "the last one".
class GoToTabIntent extends Intent {
  const GoToTabIntent(this.index, {this.last = false});

  final int index;
  final bool last;
}

/// Group the selection, or ungroup the selected groups.
class GroupIntent extends Intent {
  const GroupIntent({required this.group});

  final bool group;
}

/// Pick a tool by its letter: V, B, E, R, O, L, A, D.
class SelectToolIntent extends Intent {
  const SelectToolIntent(this.tool);

  final Tool tool;
}

/// Nudge the brush width one step: `[` thinner, `]` thicker.
class BrushWidthIntent extends Intent {
  const BrushWidthIntent(this.delta);

  final double delta;
}

/// Show the keyboard shortcuts reference.
class ShowShortcutsIntent extends Intent {
  const ShowShortcutsIntent();
}

/// Zoom the active document in or out about the viewport centre.
class ZoomIntent extends Intent {
  const ZoomIntent(this.factor);

  final double factor;
}

/// Put the whole page back in the viewport. Ctrl/Cmd+0.
class ResetViewIntent extends Intent {
  const ResetViewIntent();
}

/// File → New. Ctrl/Cmd+N.
class NewDocumentIntent extends Intent {
  const NewDocumentIntent();
}

/// File → Open. Ctrl/Cmd+O.
class OpenDocumentIntent extends Intent {
  const OpenDocumentIntent();
}

/// File → Save, and Save As with Shift.
class SaveDocumentIntent extends Intent {
  const SaveDocumentIntent({this.saveAs = false});

  final bool saveAs;
}

/// Move the selected element within its layer's z-order.
class ReorderSelectionIntent extends Intent {
  const ReorderSelectionIntent({required this.forward, this.toEnd = false});

  final bool forward;
  final bool toEnd;
}

/// Every keyboard shortcut the app binds. The Help dialog documents them.
///
/// Control and Meta are both bound rather than switched on the platform: a
/// Linux user on an Apple keyboard, and the widget tests, both work either way,
/// and neither combination means anything else here.
const Map<ShortcutActivator, Intent> kAppShortcuts = {
  SingleActivator(LogicalKeyboardKey.keyZ, control: true): UndoIntent(),
  SingleActivator(LogicalKeyboardKey.keyZ, meta: true): UndoIntent(),
  SingleActivator(LogicalKeyboardKey.keyZ, control: true, shift: true):
      RedoIntent(),
  SingleActivator(LogicalKeyboardKey.keyZ, meta: true, shift: true):
      RedoIntent(),
  // Windows' second redo binding.
  SingleActivator(LogicalKeyboardKey.keyY, control: true): RedoIntent(),

  SingleActivator(LogicalKeyboardKey.delete): DeleteSelectionIntent(),
  SingleActivator(LogicalKeyboardKey.backspace): DeleteSelectionIntent(),
  SingleActivator(LogicalKeyboardKey.escape): DeselectIntent(),
  SingleActivator(LogicalKeyboardKey.keyD, control: true):
      DuplicateSelectionIntent(),
  SingleActivator(LogicalKeyboardKey.keyD, meta: true):
      DuplicateSelectionIntent(),
  SingleActivator(LogicalKeyboardKey.keyA, control: true): SelectAllIntent(),
  SingleActivator(LogicalKeyboardKey.keyA, meta: true): SelectAllIntent(),

  SingleActivator(LogicalKeyboardKey.arrowLeft): NudgeIntent(-1, 0),
  SingleActivator(LogicalKeyboardKey.arrowRight): NudgeIntent(1, 0),
  SingleActivator(LogicalKeyboardKey.arrowUp): NudgeIntent(0, -1),
  SingleActivator(LogicalKeyboardKey.arrowDown): NudgeIntent(0, 1),
  SingleActivator(LogicalKeyboardKey.arrowLeft, shift: true): NudgeIntent(
    -10,
    0,
  ),
  SingleActivator(LogicalKeyboardKey.arrowRight, shift: true): NudgeIntent(
    10,
    0,
  ),
  SingleActivator(LogicalKeyboardKey.arrowUp, shift: true): NudgeIntent(0, -10),
  SingleActivator(LogicalKeyboardKey.arrowDown, shift: true): NudgeIntent(
    0,
    10,
  ),

  SingleActivator(LogicalKeyboardKey.keyT, control: true): NewTabIntent(),
  SingleActivator(LogicalKeyboardKey.keyT, meta: true): NewTabIntent(),
  SingleActivator(LogicalKeyboardKey.keyW, control: true): CloseTabIntent(),
  SingleActivator(LogicalKeyboardKey.keyW, meta: true): CloseTabIntent(),
  SingleActivator(LogicalKeyboardKey.tab, control: true): CycleTabIntent(1),
  SingleActivator(LogicalKeyboardKey.tab, control: true, shift: true):
      CycleTabIntent(-1),

  SingleActivator(LogicalKeyboardKey.digit1, control: true): GoToTabIntent(0),
  SingleActivator(LogicalKeyboardKey.digit2, control: true): GoToTabIntent(1),
  SingleActivator(LogicalKeyboardKey.digit3, control: true): GoToTabIntent(2),
  SingleActivator(LogicalKeyboardKey.digit4, control: true): GoToTabIntent(3),
  SingleActivator(LogicalKeyboardKey.digit5, control: true): GoToTabIntent(4),
  SingleActivator(LogicalKeyboardKey.digit6, control: true): GoToTabIntent(5),
  SingleActivator(LogicalKeyboardKey.digit7, control: true): GoToTabIntent(6),
  SingleActivator(LogicalKeyboardKey.digit8, control: true): GoToTabIntent(7),
  // Ctrl+9 is "the last tab" everywhere else, however many there are.
  SingleActivator(LogicalKeyboardKey.digit9, control: true): GoToTabIntent(
    8,
    last: true,
  ),
  SingleActivator(LogicalKeyboardKey.digit1, meta: true): GoToTabIntent(0),
  SingleActivator(LogicalKeyboardKey.digit2, meta: true): GoToTabIntent(1),
  SingleActivator(LogicalKeyboardKey.digit3, meta: true): GoToTabIntent(2),
  SingleActivator(LogicalKeyboardKey.digit4, meta: true): GoToTabIntent(3),
  SingleActivator(LogicalKeyboardKey.digit5, meta: true): GoToTabIntent(4),
  SingleActivator(LogicalKeyboardKey.digit6, meta: true): GoToTabIntent(5),
  SingleActivator(LogicalKeyboardKey.digit7, meta: true): GoToTabIntent(6),
  SingleActivator(LogicalKeyboardKey.digit8, meta: true): GoToTabIntent(7),
  SingleActivator(LogicalKeyboardKey.digit9, meta: true): GoToTabIntent(
    8,
    last: true,
  ),

  // Single letters pick a tool. They are suppressed while a text box is being
  // edited — see [AppShell] — or typing "bold" would swap tools four times.
  SingleActivator(LogicalKeyboardKey.keyV): SelectToolIntent(Tool.select),
  SingleActivator(LogicalKeyboardKey.keyB): SelectToolIntent(Tool.pen),
  SingleActivator(LogicalKeyboardKey.keyE): SelectToolIntent(Tool.eraser),
  SingleActivator(LogicalKeyboardKey.keyR): SelectToolIntent(Tool.rectangle),
  SingleActivator(LogicalKeyboardKey.keyO): SelectToolIntent(Tool.ellipse),
  SingleActivator(LogicalKeyboardKey.keyL): SelectToolIntent(Tool.line),
  SingleActivator(LogicalKeyboardKey.keyA): SelectToolIntent(Tool.arrow),
  SingleActivator(LogicalKeyboardKey.keyD): SelectToolIntent(Tool.diamond),
  SingleActivator(LogicalKeyboardKey.keyT): SelectToolIntent(Tool.text),

  SingleActivator(LogicalKeyboardKey.keyC): SelectToolIntent(Tool.connector),

  SingleActivator(LogicalKeyboardKey.keyG, control: true): GroupIntent(
    group: true,
  ),
  SingleActivator(LogicalKeyboardKey.keyG, meta: true): GroupIntent(
    group: true,
  ),
  SingleActivator(LogicalKeyboardKey.keyG, control: true, shift: true):
      GroupIntent(group: false),
  SingleActivator(LogicalKeyboardKey.keyG, meta: true, shift: true):
      GroupIntent(group: false),

  SingleActivator(LogicalKeyboardKey.bracketLeft): BrushWidthIntent(-1),
  SingleActivator(LogicalKeyboardKey.bracketRight): BrushWidthIntent(1),

  SingleActivator(LogicalKeyboardKey.f1): ShowShortcutsIntent(),
  SingleActivator(LogicalKeyboardKey.slash, control: true, shift: true):
      ShowShortcutsIntent(),

  SingleActivator(LogicalKeyboardKey.digit0, control: true): ResetViewIntent(),
  SingleActivator(LogicalKeyboardKey.digit0, meta: true): ResetViewIntent(),
  // Both the shifted and unshifted key: nobody presses Ctrl+Shift to zoom in.
  SingleActivator(LogicalKeyboardKey.equal, control: true): ZoomIntent(
    kZoomStep,
  ),
  SingleActivator(LogicalKeyboardKey.add, control: true): ZoomIntent(kZoomStep),
  SingleActivator(LogicalKeyboardKey.equal, meta: true): ZoomIntent(kZoomStep),
  SingleActivator(LogicalKeyboardKey.minus, control: true): ZoomIntent(
    1 / kZoomStep,
  ),
  SingleActivator(LogicalKeyboardKey.minus, meta: true): ZoomIntent(
    1 / kZoomStep,
  ),

  SingleActivator(LogicalKeyboardKey.keyN, control: true): NewDocumentIntent(),
  SingleActivator(LogicalKeyboardKey.keyN, meta: true): NewDocumentIntent(),
  SingleActivator(LogicalKeyboardKey.keyO, control: true): OpenDocumentIntent(),
  SingleActivator(LogicalKeyboardKey.keyO, meta: true): OpenDocumentIntent(),
  SingleActivator(LogicalKeyboardKey.keyS, control: true): SaveDocumentIntent(),
  SingleActivator(LogicalKeyboardKey.keyS, meta: true): SaveDocumentIntent(),
  SingleActivator(LogicalKeyboardKey.keyS, control: true, shift: true):
      SaveDocumentIntent(saveAs: true),
  SingleActivator(LogicalKeyboardKey.keyS, meta: true, shift: true):
      SaveDocumentIntent(saveAs: true),

  SingleActivator(LogicalKeyboardKey.bracketRight, control: true):
      ReorderSelectionIntent(forward: true),
  SingleActivator(LogicalKeyboardKey.bracketLeft, control: true):
      ReorderSelectionIntent(forward: false),
  SingleActivator(LogicalKeyboardKey.bracketRight, control: true, shift: true):
      ReorderSelectionIntent(forward: true, toEnd: true),
  SingleActivator(LogicalKeyboardKey.bracketLeft, control: true, shift: true):
      ReorderSelectionIntent(forward: false, toEnd: true),
};

/// The File/Edit menu bar.
///
/// Export PNG is still disabled: task 15.1 wires it up.
class AppMenuBar extends ConsumerWidget {
  const AppMenuBar({super.key});

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
                MenuItemButton(
                  key: const Key('menu-new'),
                  shortcut: const SingleActivator(
                    LogicalKeyboardKey.keyN,
                    control: true,
                  ),
                  onPressed: () => newSession(context, ref),
                  child: const Text('New'),
                ),
                MenuItemButton(
                  key: const Key('menu-open'),
                  shortcut: const SingleActivator(
                    LogicalKeyboardKey.keyO,
                    control: true,
                  ),
                  onPressed: () => openSessionsFromPicker(context, ref),
                  child: const Text('Open…'),
                ),
                _RecentFilesMenu(host: context, hostRef: ref),
                MenuItemButton(
                  key: const Key('menu-save'),
                  shortcut: const SingleActivator(
                    LogicalKeyboardKey.keyS,
                    control: true,
                  ),
                  onPressed: () => saveActiveSession(context, ref),
                  child: const Text('Save'),
                ),
                MenuItemButton(
                  key: const Key('menu-save-as'),
                  shortcut: const SingleActivator(
                    LogicalKeyboardKey.keyS,
                    control: true,
                    shift: true,
                  ),
                  onPressed: () =>
                      saveActiveSession(context, ref, saveAs: true),
                  child: const Text('Save As…'),
                ),
                MenuItemButton(
                  key: const Key('menu-export'),
                  onPressed: () => exportActiveSessionPng(context, ref),
                  child: const Text('Export PNG…'),
                ),
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
                MenuItemButton(
                  key: const Key('menu-preferences'),
                  onPressed: () => showPreferencesDialog(context),
                  child: const Text('Preferences…'),
                ),
              ],
              child: const Text('Edit'),
            ),
            SubmenuButton(
              menuChildren: [
                MenuItemButton(
                  key: const Key('menu-shortcuts'),
                  shortcut: const SingleActivator(LogicalKeyboardKey.f1),
                  onPressed: () => showShortcutsDialog(context),
                  child: const Text('Keyboard Shortcuts'),
                ),
              ],
              child: const Text('Help'),
            ),
          ],
        ),
      ),
    );
  }
}

/// File → Open Recent. Says so when the list is empty or still loading.
///
/// Opening a file outlives this menu: choosing an item pops the menu, which
/// disposes this widget's element, and a disposed `WidgetRef` throws the
/// moment the `await` inside [openSessionFromPath] resumes. So the callbacks
/// use the menu bar's own `ref` and `context`, which stay mounted; this
/// widget's `ref` is only for watching the list.
class _RecentFilesMenu extends ConsumerWidget {
  const _RecentFilesMenu({required this.host, required this.hostRef});

  final BuildContext host;
  final WidgetRef hostRef;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recent = ref.watch(recentFilesProvider).value ?? const <String>[];

    return SubmenuButton(
      key: const Key('menu-recent'),
      menuChildren: [
        if (recent.isEmpty)
          const MenuItemButton(onPressed: null, child: Text('No recent files'))
        else
          for (final path in recent)
            MenuItemButton(
              key: Key('recent-$path'),
              onPressed: () => openSessionFromPath(host, hostRef, path),
              // The full path in a tooltip; the basename is what identifies it.
              child: Tooltip(message: path, child: Text(p.basename(path))),
            ),
      ],
      child: const Text('Open Recent'),
    );
  }
}
