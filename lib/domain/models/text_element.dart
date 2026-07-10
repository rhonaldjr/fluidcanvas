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

/// Whether a text box's lines carry list markers. [value] is the `u8` written
/// into the first byte the v1 spec reserved in the text body, so a reader that
/// has never heard of lists sees zero — [none] — and lays the text out plainly.
enum ListStyle {
  none(0),
  bullet(1),
  numbered(2);

  const ListStyle(this.value);

  final int value;

  static ListStyle fromValue(int value) => values.firstWhere(
    (s) => s.value == value,
    // A future style read by this build falls back to plain text rather than
    // refusing the file; unlike an unknown elementType, it costs nothing.
    orElse: () => ListStyle.none,
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
    this.fontSize,
    this.colorRGBA,
  }) : assert(
         fontSize == null || fontSize > 0,
         'a run fontSize override must be positive',
       );

  /// Rebuilds a run from the `styleFlags` byte in the element blob.
  ///
  /// Only the boolean flags come from the byte. Per-run [fontSize] and
  /// [colorRGBA] are separate fields the codec reads when bits 3/4 are set.
  factory TextRun.fromFlags(
    String text,
    int flags, {
    double? fontSize,
    int? colorRGBA,
  }) => TextRun(
    text,
    bold: flags & 0x1 != 0,
    italic: flags & 0x2 != 0,
    underline: flags & 0x4 != 0,
    fontSize: fontSize,
    colorRGBA: colorRGBA,
  );

  final String text;
  final bool bold;
  final bool italic;
  final bool underline;

  /// A size for this run alone, or null to inherit the element's font size.
  final double? fontSize;

  /// A colour for this run alone, or null to inherit the element's colour.
  final int? colorRGBA;

  /// The `styleFlags` byte: bit 0 bold, 1 italic, 2 underline, 3 has a font
  /// size, 4 has a colour. The bits mark *presence*; the sizes and colours
  /// themselves are separate fields, so this byte alone never distinguishes
  /// two runs of different size.
  int get styleFlags =>
      (bold ? 0x1 : 0) |
      (italic ? 0x2 : 0) |
      (underline ? 0x4 : 0) |
      (fontSize != null ? 0x8 : 0) |
      (colorRGBA != null ? 0x10 : 0);

  bool get isPlain =>
      !bold && !italic && !underline && fontSize == null && colorRGBA == null;

  /// Whether [other] carries the same styling, so the two can be merged.
  ///
  /// Compares the actual sizes and colours, not just the flag bits: two runs
  /// that both override the size but to different values must never merge.
  bool sameStyleAs(TextRun other) =>
      bold == other.bold &&
      italic == other.italic &&
      underline == other.underline &&
      fontSize == other.fontSize &&
      colorRGBA == other.colorRGBA;

  TextRun copyWith({
    String? text,
    bool? bold,
    bool? italic,
    bool? underline,
    double? fontSize,
    int? colorRGBA,
    bool clearFontSize = false,
    bool clearColor = false,
  }) => TextRun(
    text ?? this.text,
    bold: bold ?? this.bold,
    italic: italic ?? this.italic,
    underline: underline ?? this.underline,
    fontSize: clearFontSize ? null : (fontSize ?? this.fontSize),
    colorRGBA: clearColor ? null : (colorRGBA ?? this.colorRGBA),
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TextRun &&
          text == other.text &&
          bold == other.bold &&
          italic == other.italic &&
          underline == other.underline &&
          fontSize == other.fontSize &&
          colorRGBA == other.colorRGBA;

  @override
  int get hashCode =>
      Object.hash(text, bold, italic, underline, fontSize, colorRGBA);

  @override
  String toString() =>
      'TextRun("$text", flags: $styleFlags, size: $fontSize, color: $colorRGBA)';
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
    this.listStyle = ListStyle.none,
    this.pathElementId,
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

  /// Whether the box's lines are a bulleted or numbered list.
  final ListStyle listStyle;

  /// A sibling whose outline this text flows along, or null to wrap in its own
  /// box. A runtime handle: ids are not persisted, so the codec stores the
  /// sibling's **index**, resolved after the whole container is read — the same
  /// way a [Connector] binds. Bound text ignores its own box for layout.
  final String? pathElementId;

  bool get isOnPath => pathElementId != null;

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

  /// The runs with each run overlapping `[start, end)` passed through
  /// [restyle], splitting a straddled run into up to three pieces.
  ///
  /// The one place range styling splits runs. Adjacent runs that end up
  /// matching are merged again by [normalizeRuns], which is what makes every
  /// range operation reversible.
  List<TextRun> restyleRange(
    int start,
    int end,
    TextRun Function(TextRun) restyle,
  ) {
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
      out.add(restyle(run.copyWith(text: run.text.substring(from, to))));
      if (to < run.text.length) {
        out.add(run.copyWith(text: run.text.substring(to)));
      }
    }
    return normalizeRuns(out);
  }

  /// The runs with `[start, end)` given the bold/italic/underline overrides.
  List<TextRun> runsWithStyle(
    int start,
    int end, {
    bool? bold,
    bool? italic,
    bool? underline,
  }) => restyleRange(
    start,
    end,
    (run) => run.copyWith(
      bold: bold ?? run.bold,
      italic: italic ?? run.italic,
      underline: underline ?? run.underline,
    ),
  );

  /// The runs with `[start, end)` set to [fontSize], or cleared to inherit the
  /// element's size when [fontSize] is null.
  List<TextRun> runsWithFontSize(int start, int end, double? fontSize) =>
      restyleRange(
        start,
        end,
        (run) => fontSize == null
            ? run.copyWith(clearFontSize: true)
            : run.copyWith(fontSize: fontSize),
      );

  /// The runs with `[start, end)` set to [colorRGBA], or cleared to inherit the
  /// element's colour when [colorRGBA] is null.
  List<TextRun> runsWithColor(int start, int end, int? colorRGBA) =>
      restyleRange(
        start,
        end,
        (run) => colorRGBA == null
            ? run.copyWith(clearColor: true)
            : run.copyWith(colorRGBA: colorRGBA),
      );

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
      // Per-run size overrides scale with the box too, or a corner-resize
      // would grow the base font while leaving the overridden runs behind.
      runs: [
        for (final run in runs)
          run.fontSize == null
              ? run
              : run.copyWith(fontSize: run.fontSize! * factor),
      ],
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
    ListStyle? listStyle,
    String? pathElementId,
    bool clearPath = false,
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
    listStyle: listStyle ?? this.listStyle,
    pathElementId: clearPath ? null : (pathElementId ?? this.pathElementId),
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
          listStyle == other.listStyle &&
          pathElementId == other.pathElementId &&
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
    listStyle,
    pathElementId,
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
