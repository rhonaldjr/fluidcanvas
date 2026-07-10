/// Anything wrong with a `.skd` file.
///
/// Readers throw only this. A corrupt archive, a truncated blob, a version from
/// the future — all arrive here with a reason the UI can show.
class SkdFormatException implements Exception {
  const SkdFormatException(this.reason);

  final String reason;

  @override
  String toString() => 'SkdFormatException: $reason';
}
