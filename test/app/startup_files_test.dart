import 'package:flutter_test/flutter_test.dart';
import 'package:inkpad/app/app.dart';

void main() {
  group('13.6 files from the command line', () {
    test('a .skd passed as argv[1] is opened', () {
      expect(skdPathsIn(['/docs/a.skd']), ['/docs/a.skd']);
    });

    test('several are opened in order', () {
      expect(skdPathsIn(['/a.skd', '/b.skd']), ['/a.skd', '/b.skd']);
    });

    test('the extension is matched case-insensitively', () {
      expect(skdPathsIn(['/A.SKD']), ['/A.SKD']);
    });

    test('no arguments means no files', () {
      expect(skdPathsIn([]), isEmpty);
    });

    test('engine flags are left to the engine', () {
      expect(skdPathsIn(['--enable-dart-profiling', '--observe']), isEmpty);
    });

    test('a file of another type is ignored, not opened and rejected', () {
      expect(skdPathsIn(['/notes.txt', '/a.skd']), ['/a.skd']);
    });

    test('an extensionless argument is ignored', () {
      expect(skdPathsIn(['inkpad']), isEmpty);
    });
  });
}
