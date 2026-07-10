import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show SystemNavigator;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:inkpad/domain/models/models.dart';
import 'package:inkpad/engine/export_png.dart';
import 'package:inkpad/format/format.dart';
import 'package:inkpad/state/state.dart';
import 'package:path/path.dart' as p;
import 'package:inkpad/ui/export_dialog.dart';
import 'package:inkpad/ui/new_document_dialog.dart';

/// What the user chose when asked about an unsaved document.
enum SavePrompt { save, discard, cancel }

/// Saves the active session, asking for a path when it has none.
///
/// Returns whether the document is now on disk: `false` when the user cancels
/// the picker or the write fails, so a caller closing a tab knows not to.
Future<bool> saveActiveSession(
  BuildContext context,
  WidgetRef ref, {
  bool saveAs = false,
}) async {
  final notifier = ref.read(sessionsProvider.notifier);
  final session = ref.read(sessionsProvider).activeSession;
  final files = ref.read(fileServiceProvider);

  var path = session.filePath;
  if (saveAs || path == null) {
    path = await files.pickSavePath(suggestedName: '${session.title}.skd');
    if (path == null) return false;
  }

  try {
    await files.write(path, session.document);
  } on Object catch (error) {
    if (context.mounted) {
      await _showError(context, 'Could not save ${session.title}', '$error');
    }
    return false;
  }

  // The document may have changed while the bytes were being written. Record
  // where it lives either way, but only call it clean if what we wrote is
  // still what is on screen.
  final now = ref.read(sessionsProvider).sessionById(session.id);
  final unchanged = now != null && identical(now.document, session.document);
  notifier.setFilePath(session.id, path, markClean: unchanged);

  await ref.read(recentFilesProvider.notifier).add(path);
  // A saved document has no crash to recover from.
  await ref.read(autosaveProvider).discard(session);
  return true;
}

/// Opens each chosen `.skd` in its own tab.
///
/// A file already open is focused rather than opened twice: two tabs over one
/// path would each think they owned it, and the second save would silently
/// discard the first.
Future<void> openSessionsFromPicker(BuildContext context, WidgetRef ref) async {
  final paths = await ref.read(fileServiceProvider).pickOpenPaths();
  for (final path in paths) {
    if (!context.mounted) return;
    await openSessionFromPath(context, ref, path);
  }
}

/// Opens [path] in a new tab, or focuses the tab that already holds it.
///
/// Returns whether a document is now on screen for that path.
Future<bool> openSessionFromPath(
  BuildContext context,
  WidgetRef ref,
  String path,
) async {
  final notifier = ref.read(sessionsProvider.notifier);

  final already = notifier.sessionForPath(path);
  if (already != null) {
    notifier.setActiveSession(already.id);
    return true;
  }

  final files = ref.read(fileServiceProvider);

  // A sidecar newer than the file itself means the app died with unsaved work.
  var readFrom = path;
  final sidecar = await ref.read(autosaveProvider).recoveryFor(path);
  if (sidecar != null) {
    if (!context.mounted) return false;
    if (await _promptRecovery(context, path)) readFrom = sidecar;
  }

  final SkdFile opened;
  try {
    opened = await files.read(readFrom);
  } on SkdFormatException catch (error) {
    // A file we cannot parse is not a file we should remember.
    await ref.read(recentFilesProvider.notifier).remove(path);
    if (context.mounted) {
      await _showError(context, 'Could not open this file', error.reason);
    }
    return false;
  } on Object catch (error) {
    await ref.read(recentFilesProvider.notifier).remove(path);
    if (context.mounted) {
      await _showError(context, 'Could not open this file', '$error');
    }
    return false;
  }

  // Recovered work belongs to the real file, and has not been saved into it.
  final id = notifier.openSession(opened.document, filePath: path);
  if (readFrom != path) notifier.markRecovered(id);

  await ref.read(recentFilesProvider.notifier).add(path);
  return true;
}

/// Offers the newer autosave sidecar found beside [path].
Future<bool> _promptRecovery(BuildContext context, String path) async {
  final recover = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      key: const Key('recover-prompt'),
      title: const Text('Recover unsaved changes?'),
      content: Text(
        'InkPad has autosaved changes to ${p.basename(path)} that are newer '
        'than the file itself. This usually means it closed unexpectedly.',
      ),
      actions: [
        TextButton(
          key: const Key('recover-discard'),
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Open the saved file'),
        ),
        FilledButton(
          key: const Key('recover-accept'),
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Recover'),
        ),
      ],
    ),
  );
  // Dismissing offers nothing, so open what was actually saved.
  return recover ?? false;
}

/// File → New: asks for a canvas size, then opens a tab holding it.
///
/// The dialog opens on the stored defaults from Preferences (15.3).
Future<void> newSession(BuildContext context, WidgetRef ref) async {
  final prefs = ref.read(preferencesProvider).value ?? const Preferences();
  final choice = await showNewDocumentDialog(
    context,
    defaults: (
      width: prefs.canvasWidth,
      height: prefs.canvasHeight,
      fitToWindow: prefs.fitNewToWindow,
      infinite: false,
    ),
  );
  if (choice == null) return;

  ref
      .read(sessionsProvider.notifier)
      .openSession(
        SkdDocument.newDefault(
          canvasWidth: choice.width,
          canvasHeight: choice.height,
          canvasMode: choice.infinite
              ? CanvasMode.infinite
              : CanvasMode.bounded,
        ),
        fitToWindow: choice.fitToWindow,
      );
}

/// File → Export → PNG: flattens the active document and writes it.
///
/// The exported file is not the document: exporting never gives the session a
/// `filePath`, never marks it clean, and never appears in Open Recent.
Future<bool> exportActiveSessionPng(BuildContext context, WidgetRef ref) async {
  final session = ref.read(sessionsProvider).activeSession;
  final document = session.document;

  final choice = await showExportDialog(
    context,
    documentWidth: document.canvasWidth,
    documentHeight: document.canvasHeight,
  );
  if (choice == null) return false;

  final files = ref.read(fileServiceProvider);
  if (!context.mounted) return false;
  final path = await files.pickExportPath(
    suggestedName: '${p.basenameWithoutExtension(session.title)}.png',
  );
  if (path == null) return false;

  try {
    final bytes = await renderDocumentPng(
      document,
      scale: choice.scale,
      transparentBackground: choice.transparent,
    );
    await files.writeBytes(path, bytes);
  } on Object catch (error) {
    if (context.mounted) {
      await _showError(context, 'Could not export the PNG', '$error');
    }
    return false;
  }
  return true;
}

/// Closes a tab, offering to save it first when it holds unsaved work.
///
/// The session is brought to the front before it is asked about: a dialog
/// naming a document the user cannot see is a dialog they cannot answer.
Future<void> closeSessionInteractively(
  BuildContext context,
  WidgetRef ref, {
  required String sessionId,
}) async {
  final notifier = ref.read(sessionsProvider.notifier);
  final session = ref.read(sessionsProvider).sessionById(sessionId);
  if (session == null) return;

  if (session.isDirty) {
    notifier.setActiveSession(sessionId);
    final choice = await promptSave(context, session.title);
    if (choice == SavePrompt.cancel) return;
    if (choice == SavePrompt.save) {
      if (!context.mounted) return;
      if (!await saveActiveSession(context, ref)) return;
    }
  }

  // The picker may have taken a while; the tab could be gone already.
  if (ref.read(sessionsProvider).sessionById(sessionId) == null) return;
  await ref.read(autosaveProvider).discard(session);
  notifier.closeSession(sessionId);
}

/// Reviews unsaved work and quits the app when the user allows it.
///
/// The window-close button (through `PopScope`), File → Quit, and Ctrl/Cmd+Q
/// all route through here, so none can bypass the save prompt. Returns whether
/// the quit went ahead — useful to a test, since `SystemNavigator.pop` has no
/// host under `flutter_test` and is a no-op there.
Future<bool> attemptQuit(BuildContext context, WidgetRef ref) async {
  if (!await confirmQuit(context, ref)) return false;
  await SystemNavigator.pop();
  return true;
}

/// Offers to save every dirty session before the window closes.
///
/// Returns whether quitting may proceed. Each dirty document is reviewed on
/// its own — a single "discard everything" button would be one misclick away
/// from losing an afternoon's work in three tabs at once.
Future<bool> confirmQuit(BuildContext context, WidgetRef ref) async {
  final notifier = ref.read(sessionsProvider.notifier);
  final dirty = [
    for (final session in ref.read(sessionsProvider).sessions)
      if (session.isDirty) session.id,
  ];

  for (final id in dirty) {
    final session = ref.read(sessionsProvider).sessionById(id);
    if (session == null || !session.isDirty) continue;

    notifier.setActiveSession(id);
    if (!context.mounted) return false;
    final choice = await promptSave(context, session.title);
    if (choice == SavePrompt.cancel) return false;
    if (choice == SavePrompt.save) {
      if (!context.mounted) return false;
      if (!await saveActiveSession(context, ref)) return false;
    }
  }
  return true;
}

/// Asks whether to save [title] before it is closed.
Future<SavePrompt> promptSave(BuildContext context, String title) async {
  final choice = await showDialog<SavePrompt>(
    context: context,
    builder: (context) => AlertDialog(
      key: const Key('save-prompt'),
      title: Text('Save changes to $title?'),
      content: const Text('Your changes will be lost if you don\'t save them.'),
      actions: [
        TextButton(
          key: const Key('save-prompt-discard'),
          onPressed: () => Navigator.pop(context, SavePrompt.discard),
          child: const Text("Don't save"),
        ),
        TextButton(
          key: const Key('save-prompt-cancel'),
          onPressed: () => Navigator.pop(context, SavePrompt.cancel),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const Key('save-prompt-save'),
          onPressed: () => Navigator.pop(context, SavePrompt.save),
          child: const Text('Save'),
        ),
      ],
    ),
  );
  // Dismissing the dialog is not consent to lose the document.
  return choice ?? SavePrompt.cancel;
}

Future<void> _showError(BuildContext context, String title, String detail) =>
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        key: const Key('file-error'),
        title: Text(title),
        content: Text(detail),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
