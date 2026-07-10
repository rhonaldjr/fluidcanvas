import 'package:inkpad/format/skd_exception.dart';

/// The only format version this build writes.
const int kSkdFormatVersion = 1;

/// The `mimetype` entry's contents — the first, uncompressed entry in the ZIP.
const String kSkdMimeType = 'application/x-skd';

/// `manifest.json`.
class SkdManifest {
  const SkdManifest({
    required this.appVersion,
    required this.createdUtc,
    required this.modifiedUtc,
    this.formatVersion = kSkdFormatVersion,
  });

  factory SkdManifest.fromJson(Map<String, dynamic> json) {
    final format = json['format'];
    if (format != 'skd') {
      throw SkdFormatException('not a .skd manifest (format: $format)');
    }

    final version = json['formatVersion'];
    if (version is! int) {
      throw const SkdFormatException('manifest has no formatVersion');
    }
    if (version > kSkdFormatVersion) {
      throw SkdFormatException(
        'this file was written by a newer version of InkPad '
        '(format $version; this build reads up to $kSkdFormatVersion)',
      );
    }

    return SkdManifest(
      formatVersion: version,
      appVersion: json['appVersion'] as String? ?? '',
      createdUtc: _parseTime(json['createdUtc'], 'createdUtc'),
      modifiedUtc: _parseTime(json['modifiedUtc'], 'modifiedUtc'),
    );
  }

  final int formatVersion;
  final String appVersion;
  final DateTime createdUtc;
  final DateTime modifiedUtc;

  Map<String, dynamic> toJson() => {
    'format': 'skd',
    'formatVersion': formatVersion,
    'appVersion': appVersion,
    'createdUtc': createdUtc.toUtc().toIso8601String(),
    'modifiedUtc': modifiedUtc.toUtc().toIso8601String(),
  };

  static DateTime _parseTime(Object? value, String field) {
    if (value is! String) throw SkdFormatException('manifest has no $field');
    final parsed = DateTime.tryParse(value);
    if (parsed == null) {
      throw SkdFormatException('manifest $field is not a date');
    }
    return parsed.toUtc();
  }
}
