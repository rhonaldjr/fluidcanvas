import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inkpad/domain/models/models.dart';
import 'package:inkpad/state/state.dart';

void main() {
  late ProviderContainer container;
  late SessionsNotifier sessions;

  setUp(() {
    container = ProviderContainer.test();
    sessions = container.read(sessionsProvider.notifier);
  });

  SessionsState get() => container.read(sessionsProvider);
  List<String> titles() => [for (final s in get().sessions) s.title];
  String activeTitle() => get().activeSession.title;

  group('12.1 titles', () {
    test('the first document is Untitled 1', () {
      expect(titles(), ['Untitled 1']);
    });

    test('each new document takes the next number', () {
      sessions
        ..openBlankSession()
        ..openBlankSession();
      expect(titles(), ['Untitled 1', 'Untitled 2', 'Untitled 3']);
    });

    test('closing a tab does not renumber the others', () {
      sessions
        ..openBlankSession()
        ..openBlankSession();
      final second = get().sessions[1].id;

      sessions.closeSession(second);

      // Untitled 3 stays Untitled 3: a title must not change under the pointer.
      expect(titles(), ['Untitled 1', 'Untitled 3']);
    });

    test('a session opened from a file is titled after it', () {
      sessions.openSession(
        SkdDocument.newDefault(),
        filePath: '/tmp/sketch.skd',
      );
      expect(activeTitle(), 'sketch.skd');
      expect(get().activeSession.isUntitled, isFalse);
    });

    test('a file-backed session does not consume an Untitled number', () {
      sessions
        ..openSession(SkdDocument.newDefault(), filePath: '/tmp/a.skd')
        ..openBlankSession();
      expect(titles(), ['Untitled 1', 'a.skd', 'Untitled 2']);
    });

    test(
      'an opened file keeps its stored canvas, so fit-to-window starts off',
      () {
        sessions.openSession(SkdDocument.newDefault(), filePath: '/tmp/a.skd');
        expect(get().activeSession.fitToWindow, isFalse);
      },
    );

    test('a new blank document tracks the window', () {
      expect(get().activeSession.fitToWindow, isTrue);
    });
  });

  group('12.2 lifecycle', () {
    test('a new tab is focused', () {
      final id = sessions.openBlankSession();
      expect(get().activeSessionId, id);
    });

    test('closing the active tab focuses the one that slid into its place', () {
      sessions
        ..openBlankSession()
        ..openBlankSession();
      final second = get().sessions[1].id;
      final third = get().sessions[2].id;

      sessions
        ..setActiveSession(second)
        ..closeSession(second);

      expect(get().activeSessionId, third);
    });

    test('closing the last tab focuses the one before it', () {
      sessions.openBlankSession();
      final first = get().sessions.first.id;
      final second = get().sessions[1].id;

      sessions.closeSession(second);
      expect(get().activeSessionId, first);
    });

    test('closing an inactive tab leaves the focus alone', () {
      sessions.openBlankSession();
      final first = get().sessions.first.id;
      final active = get().activeSessionId;

      sessions.closeSession(first);
      expect(get().activeSessionId, active);
    });

    test('closing the only tab leaves one fresh empty session', () {
      final only = get().sessions.single.id;
      sessions.closeSession(only);

      expect(get().sessionCount, 1);
      expect(get().sessions.single.id, isNot(only));
      expect(activeTitle(), 'Untitled 2');
    });

    test('closing an unknown session throws', () {
      expect(() => sessions.closeSession('nope'), throwsArgumentError);
    });
  });

  group('12.2 cycling and jumping', () {
    setUp(() {
      sessions
        ..openBlankSession()
        ..openBlankSession();
      sessions.activateAt(0);
    });

    test('Ctrl+Tab steps right', () {
      sessions.cycleSession(1);
      expect(activeTitle(), 'Untitled 2');
    });

    test('Ctrl+Tab wraps at the end', () {
      sessions
        ..activateAt(2)
        ..cycleSession(1);
      expect(activeTitle(), 'Untitled 1');
    });

    test('Ctrl+Shift+Tab wraps backwards off the first tab', () {
      sessions.cycleSession(-1);
      expect(activeTitle(), 'Untitled 3');
    });

    test('cycling one open tab does nothing', () {
      final lone = ProviderContainer.test();
      addTearDown(lone.dispose);
      lone.read(sessionsProvider.notifier).cycleSession(1);
      expect(lone.read(sessionsProvider).sessionCount, 1);
    });

    test('Ctrl+N jumps to the nth tab', () {
      sessions.activateAt(1);
      expect(activeTitle(), 'Untitled 2');
    });

    test('a jump past the end is ignored, not an error', () {
      sessions.activateAt(7);
      expect(activeTitle(), 'Untitled 1');
    });

    test('Ctrl+9 means the last tab, however many there are', () {
      sessions.activateLast();
      expect(activeTitle(), 'Untitled 3');
    });
  });

  group('12.3 reorder', () {
    setUp(() {
      sessions
        ..openBlankSession()
        ..openBlankSession();
    });

    test('dragging a tab right moves it', () {
      sessions.moveSession(0, 2);
      expect(titles(), ['Untitled 2', 'Untitled 3', 'Untitled 1']);
    });

    test('dragging a tab left moves it', () {
      sessions.moveSession(2, 0);
      expect(titles(), ['Untitled 3', 'Untitled 1', 'Untitled 2']);
    });

    test('reordering keeps the same document in front', () {
      sessions.activateAt(0);
      final active = get().activeSessionId;
      sessions.moveSession(0, 2);

      expect(get().activeSessionId, active);
      expect(activeTitle(), 'Untitled 1');
    });

    test('moving a tab onto itself is a no-op', () {
      sessions.moveSession(1, 1);
      expect(titles(), ['Untitled 1', 'Untitled 2', 'Untitled 3']);
    });

    test('an out-of-range move throws rather than corrupting the strip', () {
      expect(() => sessions.moveSession(0, 9), throwsRangeError);
      expect(() => sessions.moveSession(-1, 0), throwsRangeError);
    });
  });

  group('13.1 file paths', () {
    test('saving names the session and cleans it', () {
      final doc = get().activeSession.document;
      sessions.resizeCanvas(800, 600); // something to be dirty about
      expect(get().activeSession.isDirty, isTrue);

      sessions.setFilePath(get().activeSessionId, '/tmp/one.skd');

      expect(activeTitle(), 'one.skd');
      expect(get().activeSession.isDirty, isFalse);
      expect(get().activeSession.document, isNot(doc));
    });

    test('a document changed mid-write is named but stays dirty', () {
      sessions
        ..resizeCanvas(800, 600)
        ..setFilePath(get().activeSessionId, '/tmp/one.skd', markClean: false);

      expect(activeTitle(), 'one.skd');
      expect(get().activeSession.isDirty, isTrue);
    });

    test('sessionForPath finds an open document by its path', () {
      sessions.openSession(SkdDocument.newDefault(), filePath: '/tmp/a.skd');
      expect(sessions.sessionForPath('/tmp/a.skd')?.title, 'a.skd');
      expect(sessions.sessionForPath('/tmp/b.skd'), isNull);
    });

    test('setFilePath on a background tab leaves the active one alone', () {
      final first = get().sessions.first.id;
      sessions.openBlankSession();
      final active = get().activeSessionId;

      sessions.setFilePath(first, '/tmp/bg.skd');

      expect(get().activeSessionId, active);
      expect(get().sessions.first.title, 'bg.skd');
    });
  });
}
