import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:inkpad/state/document_session.dart';
import 'package:inkpad/state/file_service.dart';
import 'package:inkpad/state/sessions_notifier.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// How often every dirty session is written to its sidecar.
const Duration kAutosaveInterval = Duration(minutes: 3);

/// The suffix an autosave sidecar carries.
const String kAutosaveSuffix = '.autosave';

/// Where an unsaved document's sidecar goes.
///
/// Injected rather than called directly so a test can name a directory: the
/// real one asks `path_provider`, whose method channel has no host in
/// `flutter_test` and never replies, hanging whatever awaited it.
typedef ScratchDirectory = Future<String> Function();

/// Writes each dirty document to a sidecar so a crash costs minutes, not work.
///
/// A saved document's sidecar sits beside it (`sketch.skd.autosave`); an
/// `Untitled` one has nowhere to sit, so it goes to a scratch directory keyed
/// by session id — the id, not the title, because titles collide across runs.
class Autosave {
  Autosave({required this.files, required this.scratchDirectory});

  final FileService files;
  final ScratchDirectory scratchDirectory;

  /// The sidecar path for [session].
  Future<String> pathFor(DocumentSession session) async {
    final path = session.filePath;
    if (path != null) return '$path$kAutosaveSuffix';
    return p.join(
      await scratchDirectory(),
      '${session.id}.skd$kAutosaveSuffix',
    );
  }

  /// Writes a sidecar for every dirty session. Returns the paths written.
  ///
  /// A failure on one session must not stop the others: a full disk on the
  /// volume holding one document is no reason to lose the other two.
  Future<List<String>> saveDirtySessions(SessionsState state) async {
    final written = <String>[];
    for (final session in state.sessions) {
      if (!session.isDirty) continue;
      try {
        final path = await pathFor(session);
        await files.write(path, session.document);
        written.add(path);
      } on Object {
        continue;
      }
    }
    return written;
  }

  /// Deletes [session]'s sidecar. Called when it is saved for real, or closed.
  ///
  /// Best effort, and deliberately silent: removing a crash-recovery file is
  /// housekeeping. If the scratch directory cannot even be resolved, that must
  /// not stop the tab from closing or the save from being reported as done.
  Future<void> discard(DocumentSession session) async {
    try {
      await files.delete(await pathFor(session));
    } on Object {
      return;
    }
  }

  /// The sidecar for [path] when it holds newer work than [path] itself.
  ///
  /// `null` when there is no sidecar, or when the real file is at least as new
  /// — that means the last manual save won, and recovery would step backwards.
  Future<String?> recoveryFor(String path) async {
    final sidecar = '$path$kAutosaveSuffix';
    final sidecarAt = await files.modifiedAt(sidecar);
    if (sidecarAt == null) return null;
    final fileAt = await files.modifiedAt(path);
    if (fileAt == null) return sidecar;
    return sidecarAt.isAfter(fileAt) ? sidecar : null;
  }
}

/// The directory unsaved documents autosave into.
Future<String> defaultScratchDirectory() async {
  final support = await getApplicationSupportDirectory();
  final dir = Directory(p.join(support.path, 'autosave'));
  await dir.create(recursive: true);
  return dir.path;
}

final autosaveProvider = Provider<Autosave>(
  (ref) => Autosave(
    files: ref.watch(fileServiceProvider),
    scratchDirectory: defaultScratchDirectory,
  ),
);

/// Runs [Autosave.saveDirtySessions] on a timer for as long as it is mounted.
///
/// Deliberately not started by `AppShell`: a widget test that pumps the shell
/// would then leave a three-minute timer pending and fail on it.
class AutosaveTicker {
  AutosaveTicker(this.ref, {this.interval = kAutosaveInterval});

  final Ref ref;
  final Duration interval;
  Timer? _timer;

  void start() {
    _timer?.cancel();
    _timer = Timer.periodic(interval, (_) => tick());
  }

  Future<void> tick() =>
      ref.read(autosaveProvider).saveDirtySessions(ref.read(sessionsProvider));

  void stop() {
    _timer?.cancel();
    _timer = null;
  }
}

final autosaveTickerProvider = Provider<AutosaveTicker>((ref) {
  final ticker = AutosaveTicker(ref);
  ref.onDispose(ticker.stop);
  return ticker;
});
