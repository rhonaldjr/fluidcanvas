import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:inkpad/domain/models/models.dart';
import 'package:inkpad/engine/text_layout.dart';
import 'package:inkpad/state/state.dart';

/// The character range `[start, end)` that [before] and [after] differ over,
/// and what replaced it.
///
/// Found by matching the common prefix and suffix. A `TextField` reports only
/// the new value, so this is how run styling survives an edit: the replacement
/// inherits the styling of the character it follows.
({int start, int end, String inserted}) diffText(String before, String after) {
  var prefix = 0;
  final maxPrefix = before.length < after.length ? before.length : after.length;
  while (prefix < maxPrefix && before[prefix] == after[prefix]) {
    prefix++;
  }

  var suffix = 0;
  while (suffix < maxPrefix - prefix &&
      before[before.length - 1 - suffix] == after[after.length - 1 - suffix]) {
    suffix++;
  }

  return (
    start: prefix,
    end: before.length - suffix,
    inserted: after.substring(prefix, after.length - suffix),
  );
}

/// Renders the element's runs inside the field, so styling is visible while
/// typing rather than only after committing.
class _RunsController extends TextEditingController {
  _RunsController({required this.element, required List<TextRun> runs})
    : super(text: runs.map((r) => r.text).join());

  TextElement element;
  List<TextRun> runs = const [];

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final color = Color.fromARGB(
      element.colorRGBA & 0xFF,
      (element.colorRGBA >> 24) & 0xFF,
      (element.colorRGBA >> 16) & 0xFF,
      (element.colorRGBA >> 8) & 0xFF,
    );
    return TextSpan(
      children: [
        for (final run in runs)
          TextSpan(
            text: run.text,
            style: runStyle(
              run,
              fontSize: style?.fontSize ?? element.fontSize,
              fontFamily: element.fontFamily,
              color: color,
            ),
          ),
      ],
    );
  }
}

/// An in-place editor floating over the text box being edited.
///
/// A `TextField` rather than a hand-rolled caret: it brings IME, arrow keys,
/// Home/End, click-to-place and drag-to-select with it, all of which task 10.5
/// asks for and none of which is interesting to reimplement.
class TextBoxEditor extends ConsumerStatefulWidget {
  const TextBoxEditor({
    required this.scale,
    this.origin = Offset.zero,
    super.key,
  });

  /// Page screen size divided by document size.
  final double scale;

  /// Where document (0, 0) sits in the canvas box; the pan offset on an
  /// infinite canvas, zero on a bounded page.
  final Offset origin;

  @override
  ConsumerState<TextBoxEditor> createState() => _TextBoxEditorState();
}

class _TextBoxEditorState extends ConsumerState<TextBoxEditor> {
  _RunsController? _controller;
  final FocusNode _focus = FocusNode();
  String? _editingId;

  /// Bumped every time a *different* box takes over the editor. A focus loss
  /// captures this; if it has moved by the time the deferred commit runs, the
  /// blur was a box→box handover, not the user leaving. See [_onFocusChange].
  int _editGeneration = 0;

  @override
  void dispose() {
    _controller?.dispose();
    _focus.dispose();
    super.dispose();
  }

  /// Commits on a genuine focus loss, but not on a transient one.
  ///
  /// Starting a *second* text box swaps the field's controller, which drops
  /// focus for an instant before the new box's post-frame `requestFocus`
  /// restores it. Committing on that blink would delete the freshly-created
  /// (still empty) box before a key is typed. So the commit is deferred to the
  /// end of the frame and skipped if, by then, another box has taken over
  /// (the generation moved) or focus has come back.
  void _onFocusChange(bool hasFocus) {
    if (hasFocus) return;
    final generation = _editGeneration;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _focus.hasFocus || _editGeneration != generation) return;
      _commit();
    });
  }

  void _onChanged(String value) {
    final editing = ref.read(textEditingProvider);
    final controller = _controller;
    if (editing == null || controller == null) return;

    final diff = diffText(editing.text, value);
    final runs = TextElement(
      id: editing.elementId,
      x: 0,
      y: 0,
      w: 1,
      h: 1,
      runs: editing.runs,
    ).runsWithReplacement(diff.start, diff.end, diff.inserted);

    controller.runs = runs;
    ref.read(textEditingProvider.notifier).setRuns(runs);
  }

  void _onSelectionChanged() {
    final selection = _controller?.selection;
    if (selection == null || !selection.isValid) return;
    ref
        .read(textEditingProvider.notifier)
        .setSelection(selection.start, selection.end);
  }

  /// Commits the session as one undo entry, and removes a box left empty.
  ///
  /// Delegates to the notifier so the focus-loss path here and the
  /// click-elsewhere path in the canvas share one commit implementation.
  void _commit() => ref.read(sessionsProvider.notifier).flushTextEdit();

  @override
  Widget build(BuildContext context) {
    // Switching tools while a box is open commits it — the same as clicking
    // away. Without this the field simply keeps focus and the edit lingers
    // uncommitted until something else flushes it.
    ref.listen(toolProvider, (previous, next) {
      if (previous != next) _commit();
    });

    final editing = ref.watch(textEditingProvider);
    if (editing == null) {
      _editingId = null;
      return const SizedBox.shrink();
    }

    final found = ref
        .watch(activeDocumentProvider)
        .findElement(editing.elementId);
    if (found == null || found.element is! TextElement) {
      return const SizedBox.shrink();
    }
    final element = found.element as TextElement;

    if (_editingId != editing.elementId) {
      _editingId = editing.elementId;
      _editGeneration++;
      _controller?.dispose();
      _controller = _RunsController(element: element, runs: editing.runs)
        ..runs = editing.runs
        ..selection = TextSelection.collapsed(offset: editing.text.length)
        ..addListener(_onSelectionChanged);
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _focus.requestFocus(),
      );
    }
    _controller!
      ..element = element
      ..runs = editing.runs;

    final scale = widget.scale;
    final layout = layoutText(element.copyWith(runs: editing.runs));

    return Positioned(
      left: element.x * scale,
      top: element.y * scale,
      width: element.w * scale,
      height: element.h * scale,
      child: Transform.rotate(
        angle: element.rotation,
        child: Focus(
          onFocusChange: _onFocusChange,
          child: TextField(
            key: const Key('text-editor'),
            controller: _controller,
            focusNode: _focus,
            maxLines: null,
            expands: true,
            textAlign: flutterAlign(element.align),
            textAlignVertical: TextAlignVertical.top,
            cursorWidth: 1.5,
            style: TextStyle(fontSize: element.fontSize * layout.fitScale),
            decoration: const InputDecoration(
              isDense: true,
              border: InputBorder.none,
              contentPadding: EdgeInsets.zero,
            ),
            onChanged: _onChanged,
            onEditingComplete: _commit,
          ),
        ),
      ),
    );
  }
}
