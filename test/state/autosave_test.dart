import 'dart:typed_data';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inkpad/domain/models/models.dart';
import 'package:inkpad/format/format.dart';
import 'package:inkpad/state/state.dart';

import '../support/fake_file_service.dart';

void main() {
  late FakeFileService files;
  late Autosave autosave;
  late ProviderContainer container;
  late SessionsNotifier sessions;

  setUp(() {
    files = FakeFileService();
    autosave = Autosave(files: files, scratchDirectory: () async => '/scratch');
    container = ProviderContainer.test(
      overrides: [
        fileServiceProvider.overrideWithValue(files),
        autosaveProvider.overrideWithValue(autosave),
      ],
    );
    sessions = container.read(sessionsProvider.notifier);
  });

  SessionsState state() => container.read(sessionsProvider);

  void dirty() => sessions
    ..setFitToWindow(false)
    ..resizeCanvas(800, 600);

  group('13.5 sidecar paths', () {
    test('a saved document autosaves beside itself', () async {
      sessions.openSession(SkdDocument.newDefault(), filePath: '/docs/a.skd');
      final path = await autosave.pathFor(state().activeSession);
      expect(path, '/docs/a.skd.autosave');
    });

    test('an untitled document autosaves to the scratch directory, keyed by '
        'session id', () async {
      final session = state().activeSession;
      final path = await autosave.pathFor(session);
      expect(path, '/scratch/${session.id}.skd.autosave');
    });

    test('two untitled documents do not share a sidecar', () async {
      sessions.openBlankSession();
      final paths = [
        for (final session in state().sessions) await autosave.pathFor(session),
      ];
      expect(paths.toSet(), hasLength(2));
    });
  });

  group('13.5 writing', () {
    test('only dirty sessions are written', () async {
      sessions.openBlankSession(); // clean
      sessions.activateAt(0);
      dirty();

      final written = await autosave.saveDirtySessions(state());

      expect(written, hasLength(1));
      expect(files.files.keys.single, endsWith('.skd.autosave'));
    });

    test('a clean document writes nothing at all', () async {
      final written = await autosave.saveDirtySessions(state());
      expect(written, isEmpty);
      expect(files.files, isEmpty);
    });

    test('the sidecar holds the document, and reads back', () async {
      dirty();
      final written = await autosave.saveDirtySessions(state());

      final recovered = await files.read(written.single);
      expect(recovered.document.canvasWidth, 800);
    });

    test('one session failing does not stop the others', () async {
      dirty();
      sessions.openBlankSession();
      dirty();
      expect(state().sessions.every((s) => s.isDirty), isTrue);

      // Fail the first write, then let the rest through.
      var first = true;
      final flaky = _FlakyFileService(files, () {
        if (!first) return null;
        first = false;
        return StateError('disk full');
      });
      final autosaveFlaky = Autosave(
        files: flaky,
        scratchDirectory: () async => '/scratch',
      );

      final written = await autosaveFlaky.saveDirtySessions(state());
      expect(written, hasLength(1), reason: 'the second session still saved');
    });

    test('discarding removes the sidecar', () async {
      dirty();
      await autosave.saveDirtySessions(state());
      expect(files.files, isNotEmpty);

      await autosave.discard(state().activeSession);
      expect(files.files, isEmpty);
    });

    test('discarding a session that never autosaved is harmless', () async {
      await autosave.discard(state().activeSession);
      expect(files.files, isEmpty);
    });
  });

  group('13.5 recovery', () {
    test('a newer sidecar is offered', () async {
      files
        ..seed('/docs/a.skd', SkdDocument.newDefault(), at: DateTime.utc(2026))
        ..seed(
          '/docs/a.skd.autosave',
          SkdDocument.newDefault(),
          at: DateTime.utc(2026, 1, 2),
        );

      expect(await autosave.recoveryFor('/docs/a.skd'), '/docs/a.skd.autosave');
    });

    test('an older sidecar is not: the last manual save won', () async {
      files
        ..seed(
          '/docs/a.skd',
          SkdDocument.newDefault(),
          at: DateTime.utc(2026, 1, 2),
        )
        ..seed(
          '/docs/a.skd.autosave',
          SkdDocument.newDefault(),
          at: DateTime.utc(2026),
        );

      expect(await autosave.recoveryFor('/docs/a.skd'), isNull);
    });

    test('no sidecar means nothing to recover', () async {
      files.seed('/docs/a.skd', SkdDocument.newDefault());
      expect(await autosave.recoveryFor('/docs/a.skd'), isNull);
    });

    test('a sidecar whose document is gone is still offered', () async {
      files.seed('/docs/a.skd.autosave', SkdDocument.newDefault());
      expect(await autosave.recoveryFor('/docs/a.skd'), '/docs/a.skd.autosave');
    });
  });

  group('13.5 the ticker', () {
    test('a tick writes the dirty sessions', () async {
      dirty();
      await container.read(autosaveTickerProvider).tick();
      expect(files.files, hasLength(1));
    });

    test('it fires on the interval, and stops when stopped', () {
      fakeAsync((async) {
        dirty();
        final ticker = AutosaveTicker(
          container.read(_refProvider),
          interval: const Duration(minutes: 3),
        )..start();

        async
          ..elapse(const Duration(minutes: 7))
          ..flushMicrotasks();
        expect(
          files.files,
          hasLength(1),
          reason: 'the same sidecar, rewritten',
        );

        ticker.stop();
        files.files.clear();
        async
          ..elapse(const Duration(minutes: 10))
          ..flushMicrotasks();
        expect(files.files, isEmpty, reason: 'a stopped ticker writes nothing');
      });
    });
  });
}

/// Hands out the container's own [Ref] so [AutosaveTicker] can be built
/// directly in a test.
final _refProvider = Provider<Ref>((ref) => ref);

/// Wraps a [FakeFileService], failing whichever writes [failure] says to.
class _FlakyFileService implements FileService {
  _FlakyFileService(this.inner, this.failure);

  final FakeFileService inner;
  final Object? Function() failure;

  @override
  Future<void> write(String path, SkdDocument document) async {
    final error = failure();
    if (error != null) throw error;
    return inner.write(path, document);
  }

  @override
  Future<void> delete(String path) => inner.delete(path);

  @override
  Future<bool> exists(String path) => inner.exists(path);

  @override
  Future<DateTime?> modifiedAt(String path) => inner.modifiedAt(path);

  @override
  Future<List<String>> pickOpenPaths() => inner.pickOpenPaths();

  @override
  Future<String?> pickExportPath({required String suggestedName}) =>
      inner.pickExportPath(suggestedName: suggestedName);

  @override
  Future<void> writeBytes(String path, Uint8List bytes) =>
      inner.writeBytes(path, bytes);

  @override
  Future<String?> pickSavePath({required String suggestedName}) =>
      inner.pickSavePath(suggestedName: suggestedName);

  @override
  Future<SkdFile> read(String path) => inner.read(path);
}
