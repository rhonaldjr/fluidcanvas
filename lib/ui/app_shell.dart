import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:inkpad/state/state.dart';
import 'package:inkpad/ui/app_menu_bar.dart';
import 'package:inkpad/ui/canvas_view.dart';
import 'package:inkpad/ui/file_actions.dart';
import 'package:inkpad/ui/layer_panel.dart';
import 'package:inkpad/ui/status_bar.dart';
import 'package:inkpad/ui/shortcuts_dialog.dart';
import 'package:inkpad/ui/tab_strip.dart';
import 'package:inkpad/ui/toolbar_strip.dart';

/// Top-level window layout: menu bar across the top, then the tab strip, then
/// the tool strip down the left with the canvas and layer panel beside it.
class AppShell extends ConsumerWidget {
  const AppShell({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sessions = ref.read(sessionsProvider.notifier);
    // A text box under the cursor owns the keyboard. Without this, typing
    // "bold" would swap tools four times and never reach the box.
    final typing = ref.watch(textEditingProvider) != null;

    // Shortcuts live above the shell so they fire wherever focus sits, and
    // `autofocus` gives the canvas focus at startup so the first Ctrl+Z works
    // without clicking anything first.
    return Shortcuts(
      shortcuts: typing ? const <ShortcutActivator, Intent>{} : kAppShortcuts,
      child: Actions(
        actions: {
          UndoIntent: CallbackAction<UndoIntent>(
            onInvoke: (_) => sessions.undo(),
          ),
          RedoIntent: CallbackAction<RedoIntent>(
            onInvoke: (_) => sessions.redo(),
          ),
          DeleteSelectionIntent: CallbackAction<DeleteSelectionIntent>(
            onInvoke: (_) => sessions.deleteSelection(),
          ),
          DuplicateSelectionIntent: CallbackAction<DuplicateSelectionIntent>(
            onInvoke: (_) => sessions.duplicateSelection(),
          ),
          SelectAllIntent: CallbackAction<SelectAllIntent>(
            onInvoke: (_) => sessions.selectAll(),
          ),
          DeselectIntent: CallbackAction<DeselectIntent>(
            onInvoke: (_) => sessions.clearSelection(),
          ),
          NudgeIntent: CallbackAction<NudgeIntent>(
            onInvoke: (intent) => sessions.moveSelection(intent.dx, intent.dy),
          ),
          ReorderSelectionIntent: CallbackAction<ReorderSelectionIntent>(
            onInvoke: (intent) => sessions.reorderSelected(
              forward: intent.forward,
              toEnd: intent.toEnd,
            ),
          ),

          GroupIntent: CallbackAction<GroupIntent>(
            onInvoke: (intent) => intent.group
                ? sessions.groupSelection()
                : sessions.ungroupSelection(),
          ),
          SelectToolIntent: CallbackAction<SelectToolIntent>(
            onInvoke: (intent) =>
                ref.read(toolProvider.notifier).select(intent.tool),
          ),
          BrushWidthIntent: CallbackAction<BrushWidthIntent>(
            onInvoke: (intent) => ref
                .read(brushProvider.notifier)
                .setWidth(ref.read(brushProvider).baseWidth + intent.delta),
          ),
          ShowShortcutsIntent: CallbackAction<ShowShortcutsIntent>(
            onInvoke: (_) => showShortcutsDialog(context),
          ),
          ZoomIntent: CallbackAction<ZoomIntent>(
            onInvoke: (intent) => zoomActiveBy(ref, intent.factor),
          ),
          ResetViewIntent: CallbackAction<ResetViewIntent>(
            onInvoke: (_) => sessions.resetView(),
          ),

          NewTabIntent: CallbackAction<NewTabIntent>(
            onInvoke: (_) => sessions.openBlankSession(),
          ),
          CloseTabIntent: CallbackAction<CloseTabIntent>(
            onInvoke: (_) => closeSessionInteractively(
              context,
              ref,
              sessionId: ref.read(sessionsProvider).activeSessionId,
            ),
          ),
          CycleTabIntent: CallbackAction<CycleTabIntent>(
            onInvoke: (intent) => sessions.cycleSession(intent.delta),
          ),
          GoToTabIntent: CallbackAction<GoToTabIntent>(
            onInvoke: (intent) => intent.last
                ? sessions.activateLast()
                : sessions.activateAt(intent.index),
          ),
          NewDocumentIntent: CallbackAction<NewDocumentIntent>(
            onInvoke: (_) => newSession(context, ref),
          ),
          OpenDocumentIntent: CallbackAction<OpenDocumentIntent>(
            onInvoke: (_) => openSessionsFromPicker(context, ref),
          ),
          SaveDocumentIntent: CallbackAction<SaveDocumentIntent>(
            onInvoke: (intent) =>
                saveActiveSession(context, ref, saveAs: intent.saveAs),
          ),
          ExportIntent: CallbackAction<ExportIntent>(
            onInvoke: (_) => exportActiveSessionPng(context, ref),
          ),
          QuitIntent: CallbackAction<QuitIntent>(
            onInvoke: (_) => attemptQuit(context, ref),
          ),
        },
        child: Focus(
          autofocus: true,
          child: Scaffold(
            body: Column(
              children: [
                const AppMenuBar(),
                const TabStrip(),
                Expanded(
                  child: Row(
                    // Without stretch the strip shrink-wraps its content and
                    // floats vertically centred, leaving the scaffold showing
                    // above it.
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: const [
                      ToolbarStrip(),
                      Expanded(child: CanvasView()),
                      LayerPanel(),
                    ],
                  ),
                ),
                Consumer(
                  builder: (context, ref, _) =>
                      StatusBar(scale: ref.watch(pageScaleProvider)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
