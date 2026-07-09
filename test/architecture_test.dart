import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// CLAUDE.md: `domain/` and `format/` must stay free of Flutter imports so they
/// are unit-testable without a widget harness.
void main() {
  final flutterImport = RegExp(
    r'''^\s*import\s+['"](package:flutter/|package:flutter_riverpod/|dart:ui)''',
    multiLine: true,
  );

  for (final dir in const ['lib/domain', 'lib/format']) {
    test('$dir has no Flutter imports', () {
      final offenders = <String>[];
      for (final entity in Directory(dir).listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        if (flutterImport.hasMatch(entity.readAsStringSync())) {
          offenders.add(entity.path);
        }
      }
      expect(offenders, isEmpty);
    });
  }

  test('every lib/ subpackage has a barrel file', () {
    const barrels = [
      'lib/app/app.dart',
      'lib/domain/models/models.dart',
      'lib/domain/commands/commands.dart',
      'lib/format/format.dart',
      'lib/engine/engine.dart',
      'lib/engine/renderer/renderer.dart',
      'lib/ui/ui.dart',
      'lib/state/state.dart',
    ];
    for (final barrel in barrels) {
      expect(File(barrel).existsSync(), isTrue, reason: 'missing $barrel');
    }
  });
}
