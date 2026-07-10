import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inkpad/domain/models/models.dart';
import 'package:inkpad/state/state.dart';

Stroke strokeAt(String id, double x, double y) => Stroke(
  id: id,
  colorRGBA: 0xFF0000FF,
  baseWidth: 2,
  points: [StrokePoint(x: x, y: y)],
);

void main() {
  late ProviderContainer container;

  setUp(() => container = ProviderContainer.test());

  SessionsState read() => container.read(sessionsProvider);
  SessionsNotifier notifier() => container.read(sessionsProvider.notifier);
  List<String> sessionIds() => [for (final s in read().sessions) s.id];

  group('bootstrapping', () {
    test('starts with exactly one blank session, active', () {
      final state = read();
      expect(state.sessionCount, 1);
      expect(state.activeSessionId, state.sessions.single.id);
      expect(state.activeSession.document.isEmpty, isTrue);
      expect(state.activeSession.document.canvasWidth, 1920);
    });

    test('activeSessionProvider resolves the front session', () {
      expect(container.read(activeSessionProvider).id, read().activeSessionId);
    });

    test('activeDocumentProvider resolves the front document', () {
      expect(
        container.read(activeDocumentProvider),
        read().activeSession.document,
      );
    });
  });

  group('openSession', () {
    test('appends a session, makes it active, and returns its id', () {
      final first = read().activeSessionId;
      final id = notifier().openSession(SkdDocument.newDefault(), id: 'b');

      expect(id, 'b');
      expect(sessionIds(), [first, 'b']);
      expect(read().activeSessionId, 'b');
    });

    test('opens the given document, topmost layer active', () {
      notifier().openSession(
        SkdDocument(
          canvasWidth: 800,
          canvasHeight: 600,
          layers: [
            Layer(id: 'lo', name: 'Lo'),
            Layer(id: 'hi', name: 'Hi'),
          ],
        ),
        id: 'b',
      );

      final session = read().activeSession;
      expect(session.document.canvasWidth, 800);
      expect(session.activeLayerId, 'hi');
    });

    test('openBlankSession adds an empty default document', () {
      notifier().openBlankSession(id: 'b');
      expect(read().activeSession.document.isEmpty, isTrue);
      expect(read().sessionCount, 2);
    });
  });

  group('setActiveSession', () {
    test('brings a session to the front without reordering tabs', () {
      final first = read().activeSessionId;
      notifier().openBlankSession(id: 'b');

      notifier().setActiveSession(first);

      expect(read().activeSessionId, first);
      expect(sessionIds(), [first, 'b']);
    });

    test('throws for an unknown session', () {
      expect(() => notifier().setActiveSession('nope'), throwsArgumentError);
    });
  });

  group('sessions are independent', () {
    test('adding to one document leaves the other untouched', () {
      final first = read().activeSessionId;
      notifier().openBlankSession(id: 'b');

      // 'b' is active; draw into it.
      notifier().addElementToActiveLayer(strokeAt('s1', 0, 0));

      expect(read().sessionById('b')!.document.elementCount, 1);
      expect(read().sessionById(first)!.document.elementCount, 0);
    });

    test('each session keeps its own active layer', () {
      final first = read().activeSessionId;
      notifier().openSession(
        SkdDocument(
          canvasWidth: 100,
          canvasHeight: 100,
          layers: [
            Layer(id: 'lo', name: 'Lo'),
            Layer(id: 'hi', name: 'Hi'),
          ],
        ),
        id: 'b',
      );
      notifier().setActiveLayer('lo');

      expect(read().sessionById('b')!.activeLayerId, 'lo');

      notifier().setActiveSession(first);
      expect(read().activeSession.activeLayerId, isNot('lo'));
    });

    test('switching tabs preserves what each document holds', () {
      final first = read().activeSessionId;
      notifier().addElementToActiveLayer(strokeAt('in-first', 0, 0));

      notifier().openBlankSession(id: 'b');
      notifier().addElementToActiveLayer(strokeAt('in-b', 0, 0));

      notifier().setActiveSession(first);
      expect(read().activeSession.document.findElement('in-first'), isNotNull);
      expect(read().activeSession.document.findElement('in-b'), isNull);
    });
  });

  group('addElementToActiveLayer', () {
    test('targets the active session and its active layer', () {
      notifier().addElementToActiveLayer(strokeAt('s1', 1, 2));

      final layer = read().activeSession.activeLayer;
      expect(layer.elementCount, 1);
      expect(layer.elements.single.id, 's1');
    });

    test('leaves the session id and active layer alone', () {
      final before = read().activeSession;
      notifier().addElementToActiveLayer(strokeAt('s1', 0, 0));
      final after = read().activeSession;

      expect(after.id, before.id);
      expect(after.activeLayerId, before.activeLayerId);
    });

    test('the state object changes identity, so watchers rebuild', () {
      final before = read();
      notifier().addElementToActiveLayer(strokeAt('s1', 0, 0));
      expect(identical(read(), before), isFalse);
      expect(read(), isNot(before));
    });
  });

  group('replaceActiveDocument', () {
    test('swaps the document, keeping the session id', () {
      final id = read().activeSessionId;
      notifier().replaceActiveDocument(
        SkdDocument.newDefault(canvasWidth: 640, layerId: 'x'),
      );

      expect(read().activeSessionId, id);
      expect(read().activeSession.document.canvasWidth, 640);
      expect(read().activeSession.activeLayerId, 'x');
    });
  });

  group('closeSession', () {
    test('closing the last session leaves a fresh blank one', () {
      final id = read().activeSessionId;
      notifier().addElementToActiveLayer(strokeAt('s1', 0, 0));

      notifier().closeSession(id);

      final state = read();
      expect(state.sessionCount, 1);
      expect(state.activeSessionId, isNot(id));
      expect(state.activeSession.document.isEmpty, isTrue);
    });

    test('closing an inactive session leaves the active one in front', () {
      final first = read().activeSessionId;
      notifier().openBlankSession(id: 'b');
      notifier().openBlankSession(id: 'c');
      // 'c' is active.

      notifier().closeSession(first);

      expect(sessionIds(), ['b', 'c']);
      expect(read().activeSessionId, 'c');
    });

    test(
      'closing the active session focuses the tab that slides into place',
      () {
        final first = read().activeSessionId;
        notifier().openBlankSession(id: 'b');
        notifier().openBlankSession(id: 'c');
        notifier().setActiveSession('b');

        notifier().closeSession('b');

        expect(sessionIds(), [first, 'c']);
        expect(read().activeSessionId, 'c');
      },
    );

    test('closing the active last tab focuses the one before it', () {
      final first = read().activeSessionId;
      notifier().openBlankSession(id: 'b');
      // 'b' is active and last.

      notifier().closeSession('b');

      expect(sessionIds(), [first]);
      expect(read().activeSessionId, first);
    });

    test('throws for an unknown session', () {
      expect(() => notifier().closeSession('nope'), throwsArgumentError);
    });

    test('closing down to one, then closing again, still leaves a session', () {
      notifier().openBlankSession(id: 'b');
      notifier().closeSession('b');
      expect(read().sessionCount, 1);

      notifier().closeSession(read().activeSessionId);
      expect(read().sessionCount, 1);
      expect(read().activeSession.document.isEmpty, isTrue);
    });
  });

  group('SessionsState invariants', () {
    test('rejects an empty session list', () {
      expect(
        () => SessionsState(sessions: const [], activeSessionId: 'a'),
        throwsA(isA<AssertionError>()),
      );
    });

    test('rejects an activeSessionId naming no open session', () {
      expect(
        () => SessionsState(
          sessions: [DocumentSession.blank(id: 'a')],
          activeSessionId: 'b',
        ),
        throwsA(isA<AssertionError>()),
      );
    });

    test('rejects duplicate session ids', () {
      expect(
        () => SessionsState(
          sessions: [
            DocumentSession.blank(id: 'a'),
            DocumentSession.blank(id: 'a'),
          ],
          activeSessionId: 'a',
        ),
        throwsA(isA<AssertionError>()),
      );
    });

    test('sessions are unmodifiable', () {
      expect(
        () => read().sessions.add(DocumentSession.blank()),
        throwsUnsupportedError,
      );
    });
  });
}
