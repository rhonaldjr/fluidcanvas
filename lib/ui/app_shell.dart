import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:inkpad/state/state.dart';
import 'package:inkpad/ui/app_menu_bar.dart';
import 'package:inkpad/ui/canvas_view.dart';
import 'package:inkpad/ui/file_actions.dart';
import 'package:inkpad/ui/layer_panel.dart';
import 'package:inkpad/ui/status_bar.dart';
import 'package:inkpad/ui/tab_strip.dart';
import 'package:inkpad/ui/toolbar_strip.dart';

/// Top-level window layout: menu bar across the top, then the tab strip, then
/// the tool strip down the left with the canvas and layer panel beside it.
class AppShell extends ConsumerWidget {
  const AppShell({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sessions = ref.read(sessionsProvider.notifier);

    // Shortcuts live above the shell so they fire wherever focus sits, and
    // `autofocus` gives the canvas focus at startup so the first Ctrl+Z works
    // without clicking anything first.
    return Shortcuts(
      shortcuts: kUndoRedoShortcuts,
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
