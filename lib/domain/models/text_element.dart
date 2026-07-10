part of 'canvas_element.dart';

/// Horizontal alignment of a text box's lines.
///
/// [value] is the `u8` in the `.skd` element blob; never reassign one.
enum TextAlignment {
  left(0),
  center(1),
  right(2);

  const TextAlignment(this.value);

  final int value;

  static TextAlignment fromValue(int value) => values.firstWhere(
    (a) => a.value == value,
    orElse: () =>
        throw ArgumentError.value(value, 'value', 'unknown TextAlignment'),
  );
}

/// A styled run of characters. A [TextElement]'s text is the concatenation of
/// its runs, so styled ranges can never overlap.
class TextRun {
  const TextRun(
    this.text, {
    this.bold = false,
    this.italic = false,
    this.underline = false,
  });

  /// Rebuilds a run from the `styleFlags` byte in the element blob.
  factory TextRun.fromFlags(String text, int flags) => TextRun(
    text,
    bold: flags & 0x1 != 0,
    italic: flags & 0x2 != 0,
    underline: flags & 0x4 != 0,
  );

  final String text;
  final bool bold;
  final bool italic;
  final bool underline;

  /// The `styleFlags` byte: bit 0 bold, bit 1 italic, bit 2 underline.
  int get styleFlags =>
      (bold ? 0x1 : 0) | (italic ? 0x2 : 0) | (underline ? 0x4 : 0);

  bool get isPlain => !bold && !italic && !underline;

  /// Whether [other] carries the same styling, so the two can be merged.
  bool sameStyleAs(TextRun other) => styleFlags == other.styleFlags;

  TextRun copyWith({String? text, bool? bold, bool? italic, bool? underline}) =>
      TextRun(
        text ?? this.text,
        bold: bold ?? this.bold,
        italic: italic ?? this.italic,
        underline: underline ?? this.underline,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TextRun && text == other.text && styleFlags == other.styleFlags;

  @override
  int get hashCode => Object.hash(text, styleFlags);

  @override
  String toString() => 'TextRun("$text", flags: $styleFlags)';
}

/// A text box with rich runs.
///
/// The box has a fixed size and the text **shrinks to fit** it: [fontSize] is a
/// maximum, and the renderer picks the largest scale at which the wrapped text
/// fits. That scale is derived at layout time, never stored, so it can never
/// disagree with the text.
///
/// [fontFamily] names a *system* font. Opened where that family is missing, the
/// text falls back to the platform default and rewraps with different glyphs —
/// so rendering is not reproducible across machines, and no test may assert
/// text pixels.
class TextElement extends CanvasElement {
  TextElement({
    required super.id,
    required this.x,
    required this.y,
    required this.w,
    required this.h,
    required List<TextRun> runs,
    this.rotation = 0,
    this.fontFamily = '',
    this.fontSize = 24,
    this.colorRGBA = 0x1B1B1FFF,
    this.align = TextAlignment.left,
  }) : assert(w > 0 && h > 0, 'a text box must have a positive size'),
       assert(fontSize > 0, 'fontSize must be positive'),
       runs = normalizeRuns(runs);

  /// A box holding one plain run.
  factory TextElement.plain({
    required String id,
    required double x,
    required double y,
    required double w,
    required double h,
    String text = '',
    double fontSize = 24,
    String fontFamily = '',
    int colorRGBA = 0x1B1B1FFF,
    TextAlignment align = TextAlignment.left,
  }) => TextElement(
    id: id,
    x: x,
    y: y,
    w: w,
    h: h,
    fontSize: fontSize,
    fontFamily: fontFamily,
    colorRGBA: colorRGBA,
    align: align,
    runs: [TextRun(text)],
  );

  /// Top-left of the unrotated box.
  final double x;
  final double y;

  /// Box size. Text wraps to [w] and shrinks to fit [h].
  final double w;
  final double h;

  /// Radians, clockwise, about the box's centre.
  final double rotation;

  /// A system font family. Empty means the platform default.
  final String fontFamily;

  /// The *largest* size the text is drawn at, before shrink-to-fit.
  final double fontSize;

  /// Packed 0xRRGGBBAA.
  final int colorRGBA;

  final TextAlignment align;

  /// Never empty: an empty element holds one empty run.
  final List<TextRun> runs;

  /// The whole text, which is the runs joined.
  String get text => runs.map((r) => r.text).join();

  int get length => text.length;

  bool get isEmpty => text.isEmpty;

  bool get isRotated => rotation != 0;

  double get centerX => x + w / 2;
  double get centerY => y + h / 2;

  /// Drops empty runs and merges neighbours with equal styling.
  ///
  /// This is what makes styling reversible: bolding a range and un-bolding it
  /// yields the run list you started with, not three runs that merely render
  /// the same.
  static List<TextRun> normalizeRuns(List<TextRun> runs) {
    final merged = <TextRun>[];
    for (final run in runs) {
      if (run.text.isEmpty) continue;
      if (merged.isNotEmpty && merged.last.sameStyleAs(run)) {
        merged.last = merged.last.copyWith(text: merged.last.text + run.text);
      } else {
        merged.add(run);
      }
    }
    if (merged.isEmpty) merged.add(const TextRun(''));
    return List.unmodifiable(merged);
  }

  /// The runs with `[start, end)` restyled.
  ///
  /// A range inside one run splits it into up to three. Adjacent runs that end
  /// up matching are merged again by [normalizeRuns].
  List<TextRun> runsWithStyle(
    int start,
    int end, {
    bool? bold,
    bool? italic,
    bool? underline,
  }) {
    if (end <= start) return runs;
    final out = <TextRun>[];
    var offset = 0;

    for (final run in runs) {
      final runStart = offset;
      final runEnd = offset + run.text.length;
      offset = runEnd;

      if (runEnd <= start || runStart >= end) {
        out.add(run);
        continue;
      }

      final from = math.max(start, runStart) - runStart;
      final to = math.min(end, runEnd) - runStart;

      if (from > 0) out.add(run.copyWith(text: run.text.substring(0, from)));
      out.add(
        run.copyWith(
          text: run.text.substring(from, to),
          bold: bold ?? run.bold,
          italic: italic ?? run.italic,
          underline: underline ?? run.underline,
        ),
      );
      if (to < run.text.length) {
        out.add(run.copyWith(text: run.text.substring(to)));
      }
    }
    return normalizeRuns(out);
  }

  /// Whether every character in `[start, end)` already carries [flag].
  ///
  /// A toggle turns the range *off* only when all of it is on, which is what
  /// makes bolding a partly-bold selection bold the whole thing first.
  bool rangeHasStyle(int start, int end, bool Function(TextRun) flag) {
    if (end <= start) return false;
    var offset = 0;
    for (final run in runs) {
      final runStart = offset;
      final runEnd = offset + run.text.length;
      offset = runEnd;
      if (runEnd <= start || runStart >= end) continue;
      if (!flag(run)) return false;
    }
    return true;
  }

  /// The runs with `[start, end)` replaced by [inserted], which inherits the
  /// styling of the character before it.
  List<TextRun> runsWithReplacement(int start, int end, String inserted) {
    final out = <TextRun>[];
    var offset = 0;
    TextRun? styleSource;

    for (final run in runs) {
      final runStart = offset;
      final runEnd = offset + run.text.length;
      offset = runEnd;

      final keepHead = math.max(0, math.min(start, runEnd) - runStart);
      final keepTailFrom = math.max(
        0,
        math.min(runEnd, math.max(end, runStart)) - runStart,
      );

      if (keepHead > 0) {
        out.add(run.copyWith(text: run.text.substring(0, keepHead)));
        if (runStart + keepHead == start) styleSource = run;
      }
      if (runStart <= start && start <= runEnd) styleSource ??= run;
      if (keepTailFrom < run.text.length && runEnd > end) {
        out.add(run.copyWith(text: run.text.substring(keepTailFrom)));
      }
    }

    if (inserted.isNotEmpty) {
      final style = styleSource ?? runs.first;
      // Insert at the right place: rebuild by offset.
      return normalizeRuns(_spliceInserted(out, start, inserted, style));
    }
    return normalizeRuns(out);
  }

  List<TextRun> _spliceInserted(
    List<TextRun> kept,
    int at,
    String inserted,
    TextRun style,
  ) {
    final out = <TextRun>[];
    var offset = 0;
    var placed = false;
    for (final run in kept) {
      if (!placed && offset == at) {
        out.add(style.copyWith(text: inserted));
        placed = true;
      }
      out.add(run);
      offset += run.text.length;
    }
    if (!placed) out.add(style.copyWith(text: inserted));
    return out;
  }

  /// The axis-aligned box around the element, accounting for [rotation].
  @override
  Bounds get bounds {
    if (!isRotated) {
      return Bounds(left: x, top: y, right: x + w, bottom: y + h);
    }
    final cos = math.cos(rotation);
    final sin = math.sin(rotation);
    var left = double.infinity;
    var top = double.infinity;
    var right = double.negativeInfinity;
    var bottom = double.negativeInfinity;

    for (final (px, py) in [(x, y), (x + w, y), (x + w, y + h), (x, y + h)]) {
      final dx = px - centerX;
      final dy = py - centerY;
      final rx = centerX + dx * cos - dy * sin;
      final ry = centerY + dx * sin + dy * cos;
      if (rx < left) left = rx;
      if (rx > right) right = rx;
      if (ry < top) top = ry;
      if (ry > bottom) bottom = ry;
    }
    return Bounds(left: left, top: top, right: right, bottom: bottom);
  }

  /// Scaling grows the box **and** the font, so the text keeps its apparent
  /// size relative to the box and never rewraps differently.
  @override
  TextElement scaled(double factor, {double originX = 0, double originY = 0}) {
    assert(factor > 0, 'scale factor must be positive');
    return copyWith(
      x: originX + (x - originX) * factor,
      y: originY + (y - originY) * factor,
      w: w * factor,
      h: h * factor,
      fontSize: fontSize * factor,
    );
  }

  @override
  TextElement translated(double dx, double dy) =>
      copyWith(x: x + dx, y: y + dy);

  @override
  TextElement rotated(
    double radians, {
    required double originX,
    required double originY,
  }) {
    final cos = math.cos(radians);
    final sin = math.sin(radians);
    final cx = centerX;
    final cy = centerY;
    final rx = originX + (cx - originX) * cos - (cy - originY) * sin;
    final ry = originY + (cx - originX) * sin + (cy - originY) * cos;
    return copyWith(
      x: x + (rx - cx),
      y: y + (ry - cy),
      rotation: rotation + radians,
    );
  }

  TextElement copyWith({
    String? id,
    double? x,
    double? y,
    double? w,
    double? h,
    double? rotation,
    String? fontFamily,
    double? fontSize,
    int? colorRGBA,
    TextAlignment? align,
    List<TextRun>? runs,
  }) => TextElement(
    id: id ?? this.id,
    x: x ?? this.x,
    y: y ?? this.y,
    w: w ?? this.w,
    h: h ?? this.h,
    rotation: rotation ?? this.rotation,
    fontFamily: fontFamily ?? this.fontFamily,
    fontSize: fontSize ?? this.fontSize,
    colorRGBA: colorRGBA ?? this.colorRGBA,
    align: align ?? this.align,
    runs: runs ?? this.runs,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TextElement &&
          id == other.id &&
          x == other.x &&
          y == other.y &&
          w == other.w &&
          h == other.h &&
          rotation == other.rotation &&
          fontFamily == other.fontFamily &&
          fontSize == other.fontSize &&
          colorRGBA == other.colorRGBA &&
          align == other.align &&
          _runsEqual(runs, other.runs);

  @override
  int get hashCode => Object.hash(
    id,
    x,
    y,
    w,
    h,
    rotation,
    fontFamily,
    fontSize,
    colorRGBA,
    align,
    Object.hashAll(runs),
  );

  @override
  String toString() =>
      'TextElement($id, "${text.length > 20 ? '${text.substring(0, 20)}…' : text}")';
}

bool _runsEqual(List<TextRun> a, List<TextRun> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
