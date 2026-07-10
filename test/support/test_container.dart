import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:inkpad/state/state.dart';

import 'fake_file_service.dart';

/// A container whose disk, dialogs and scratch directory are all fake.
///
/// The scratch directory must be overridden even when autosave is not under
/// test: the real one asks `path_provider`, and that channel never answers in
/// a widget test, so anything awaiting it hangs rather than failing.
ProviderContainer testContainer({
  FakeFileService? files,
  String scratch = '/scratch',
}) {
  final service = files ?? FakeFileService();
  return ProviderContainer.test(
    overrides: [
      fileServiceProvider.overrideWithValue(service),
      autosaveProvider.overrideWithValue(
        Autosave(files: service, scratchDirectory: () async => scratch),
      ),
    ],
  );
}
