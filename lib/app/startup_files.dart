import 'package:inkpad/state/file_service.dart';
import 'package:path/path.dart' as p;

/// The `.skd` paths named on the command line.
///
/// The OS passes a double-clicked document as `argv[1]` once the association
/// from task 13.6 is registered. Anything that is not a `.skd` is ignored
/// rather than opened and rejected — flags belong to the engine, not to us.
List<String> skdPathsIn(List<String> args) => [
  for (final arg in args)
    if (!arg.startsWith('-') &&
        p.extension(arg).toLowerCase() == '.$kSkdExtension')
      arg,
];
