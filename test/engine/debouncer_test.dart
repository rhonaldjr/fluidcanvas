import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inkpad/engine/debouncer.dart';

void main() {
  test('runs the action after the quiet period', () {
    fakeAsync((async) {
      var runs = 0;
      Debouncer(duration: const Duration(milliseconds: 100))(() => runs++);

      async.elapse(const Duration(milliseconds: 99));
      expect(runs, 0);
      async.elapse(const Duration(milliseconds: 2));
      expect(runs, 1);
    });
  });

  test('a burst of calls runs the action once', () {
    fakeAsync((async) {
      var runs = 0;
      final debouncer = Debouncer(duration: const Duration(milliseconds: 100));

      // As a window drag would: one call per frame.
      for (var i = 0; i < 30; i++) {
        debouncer(() => runs++);
        async.elapse(const Duration(milliseconds: 16));
      }
      expect(runs, 0);

      async.elapse(const Duration(milliseconds: 100));
      expect(runs, 1);
    });
  });

  test('the last action wins', () {
    fakeAsync((async) {
      var value = 0;
      final debouncer = Debouncer(duration: const Duration(milliseconds: 50));
      debouncer(() => value = 1);
      debouncer(() => value = 2);
      async.elapse(const Duration(milliseconds: 60));
      expect(value, 2);
    });
  });

  test('cancel drops the pending action', () {
    fakeAsync((async) {
      var runs = 0;
      Debouncer(duration: const Duration(milliseconds: 50))
        ..call(() => runs++)
        ..cancel();
      async.elapse(const Duration(milliseconds: 100));
      expect(runs, 0);
    });
  });

  test('isPending reports whether an action is waiting', () {
    fakeAsync((async) {
      final debouncer = Debouncer(duration: const Duration(milliseconds: 50));
      expect(debouncer.isPending, isFalse);

      debouncer(() {});
      expect(debouncer.isPending, isTrue);

      async.elapse(const Duration(milliseconds: 60));
      expect(debouncer.isPending, isFalse);
    });
  });

  test('dispose cancels', () {
    fakeAsync((async) {
      var runs = 0;
      Debouncer(duration: const Duration(milliseconds: 50))
        ..call(() => runs++)
        ..dispose();
      async.elapse(const Duration(milliseconds: 100));
      expect(runs, 0);
    });
  });
}
