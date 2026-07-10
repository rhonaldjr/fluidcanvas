import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inkpad/app/app.dart';
import 'package:inkpad/domain/models/models.dart';
import 'package:inkpad/state/state.dart';

DocumentSession blank() => DocumentSession.blank(id: 's');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('13.1 the window title', () {
    test('names the untitled document', () {
      expect(windowTitleFor(blank()), 'Untitled 1 — InkPad');
    });

    test('names the file once it has one', () {
      final saved = blank().withFilePath('/docs/sketch.skd');
      expect(windowTitleFor(saved), 'sketch.skd — InkPad');
    });

    test('an unsaved document is starred', () {
      final dirty = blank().withDocument(
        SkdDocument.newDefault(canvasWidth: 800),
      );
      expect(dirty.isDirty, isFalse, reason: 'withDocument is not a command');

      final edited = blank().markUnsaved();
      expect(windowTitleFor(edited), '*Untitled 1 — InkPad');
    });

    test('saving takes the star away', () {
      final saved = blank().markUnsaved().withFilePath('/a/b.skd').markSaved();
      expect(windowTitleFor(saved), 'b.skd — InkPad');
    });
  });

  group('13.1 the platform channel', () {
    late List<MethodCall> calls;

    setUp(() {
      calls = [];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(kWindowChannel, (call) async {
            calls.add(call);
            return null;
          });
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(kWindowChannel, null);
    });

    test('setTitle reaches the host', () async {
      await const WindowTitle().set('sketch.skd — InkPad');

      expect(calls.single.method, 'setTitle');
      expect(calls.single.arguments, 'sketch.skd — InkPad');
    });

    test('a platform with no handler is not an error', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(kWindowChannel, null);

      // macOS until Phase 16, and every widget test.
      await expectLater(const WindowTitle().set('x'), completes);
    });
  });
}
