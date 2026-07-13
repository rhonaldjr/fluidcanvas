import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:inkpad/domain/models/models.dart';
import 'package:inkpad/engine/system_fonts.dart';

/// The text box being edited, if any.
///
/// Transient UI state, like the live stroke. Held globally rather than on the
/// session because only one box is ever being typed into.
class TextEditingSession {
  const TextEditingSession({
    required this.elementId,
    required this.original,
    required this.runs,
    this.selectionStart = 0,
    this.selectionEnd = 0,
  });

  final String elementId;

  /// The element as it was when editing began, so one undo entry covers the
  /// whole session rather than one per keystroke.
  final TextElement original;

  /// The runs as they stand right now, uncommitted.
  final List<TextRun> runs;

  final int selectionStart;
  final int selectionEnd;

  String get text => runs.map((r) => r.text).join();
  bool get hasSelection => selectionEnd > selectionStart;

  TextEditingSession copyWith({
    List<TextRun>? runs,
    int? selectionStart,
    int? selectionEnd,
  }) => TextEditingSession(
    elementId: elementId,
    original: original,
    runs: runs ?? this.runs,
    selectionStart: selectionStart ?? this.selectionStart,
    selectionEnd: selectionEnd ?? this.selectionEnd,
  );
}

class TextEditingNotifier extends Notifier<TextEditingSession?> {
  @override
  TextEditingSession? build() => null;

  void begin(TextElement element) => state = TextEditingSession(
    elementId: element.id,
    original: element,
    runs: element.runs,
    selectionStart: element.length,
    selectionEnd: element.length,
  );

  void setRuns(List<TextRun> runs) => state = state?.copyWith(runs: runs);

  void setSelection(int start, int end) =>
      state = state?.copyWith(selectionStart: start, selectionEnd: end);

  void end() => state = null;
}

final textEditingProvider =
    NotifierProvider<TextEditingNotifier, TextEditingSession?>(
      TextEditingNotifier.new,
    );

/// Style new text boxes are created with. Global, like the brush.
class TextStyleSettings {
  const TextStyleSettings({
    this.fontFamily = kDefaultFontFamily,
    this.fontSize = 24,
    this.colorRGBA = 0x1B1B1FFF,
  }) : assert(fontSize > 0, 'fontSize must be positive');

  final String fontFamily;
  final double fontSize;
  final int colorRGBA;

  TextStyleSettings copyWith({
    String? fontFamily,
    double? fontSize,
    int? colorRGBA,
  }) => TextStyleSettings(
    fontFamily: fontFamily ?? this.fontFamily,
    fontSize: fontSize ?? this.fontSize,
    colorRGBA: colorRGBA ?? this.colorRGBA,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TextStyleSettings &&
          fontFamily == other.fontFamily &&
          fontSize == other.fontSize &&
          colorRGBA == other.colorRGBA;

  @override
  int get hashCode => Object.hash(fontFamily, fontSize, colorRGBA);
}

class TextStyleNotifier extends Notifier<TextStyleSettings> {
  @override
  TextStyleSettings build() => const TextStyleSettings();

  void setFamily(String family) => state = state.copyWith(fontFamily: family);
  void setSize(double size) =>
      state = state.copyWith(fontSize: size.clamp(6, 200));
  void setColor(int rgba) => state = state.copyWith(colorRGBA: rgba);
}

final textStyleProvider =
    NotifierProvider<TextStyleNotifier, TextStyleSettings>(
      TextStyleNotifier.new,
    );
