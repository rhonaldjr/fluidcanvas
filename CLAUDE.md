# CLAUDE.md

Guidance for Claude Code when working in this repository.

## Project Overview

**InkPad** (working name) is a cross-platform desktop sketching and light diagramming application. Users draw freehand strokes with a mouse or pressure-sensitive stylus, place predefined shapes (rectangle, ellipse, line, arrow, diamond) that stay resizable, type rich text into resizable boxes, organize work into layers, and save to a proprietary `.skd` file format.

Strokes, shapes and text are peers: all are `CanvasElement`s, all live in a single ordered list per layer (bottom to top), and all share one selection/transform system. Shapes are **parametric** — resizing a rectangle changes its width and height, it never resamples pixels.

**Text** uses system fonts and stores the family name, so a file opened without that family rewraps with different glyphs. Rendering is therefore *not* reproducible across machines: never assert text pixels in a test. A text box has a fixed size and the text shrinks to fit it (down to 25%, then overflows); the fit scale is always derived from the layout, never stored. A **corner** handle scales a box and its `fontSize` together; a **side** handle changes one axis of the box alone, so the text rewraps at the same size. Flutter cannot enumerate or query installed fonts: `engine/system_fonts.dart` asks fontconfig and detects a missing family by *measuring* it against a family that certainly does not exist.

The app is **multi-document**: several documents are open at once, each in its own tab, each with its own file path, dirty flag, undo stack, selection and canvas.

Anything that touches the disk or opens a native dialog goes through the `FileService` seam in `state/file_service.dart`, so tests never open a GTK file chooser or write to the developer's home directory. Two traps live here: a `WidgetRef` from a widget that a menu pop disposes throws the moment an `await` resumes (use the menu bar's `ref`), and `path_provider`'s channel never answers under `flutter_test` — awaiting it **hangs** rather than failing, which is why the autosave scratch directory is injected.

- **Stack:** Flutter (Dart) targeting Windows, macOS, and Linux desktop
- **Rendering:** Flutter `CustomPainter` / `Canvas` (Skia-backed)
- **File format:** `.skd` — ZIP container with JSON manifest + binary stroke data (spec below)
- **State management:** Riverpod
- **No web or mobile targets.** Do not add responsive/mobile layouts.

## Commands

```bash
flutter run -d windows|macos|linux   # run the app
flutter test                          # run all tests
flutter test test/format/            # run file-format tests only
flutter analyze                       # lint / static analysis
dart format lib test                  # format code
flutter build windows|macos|linux    # release build
```

Always run `flutter analyze` and `flutter test` before considering a task done.

## Architecture

```
lib/
  main.dart                 # app entry, window setup
  app/                      # top-level widget, theming, routing
  domain/                   # pure Dart, NO Flutter imports
    models/                 #   CanvasElement, Stroke, StrokePoint, Shape, TextElement, Layer, SkdDocument, Brush
    commands/               #   undo/redo command objects
  format/                   # .skd read/write, pure Dart, NO Flutter imports
    skd_writer.dart
    skd_reader.dart
    element_codec.dart      #   binary encode/decode of element blobs
    manifest.dart
  engine/                   # drawing engine
    stroke_builder.dart     #   pointer events -> smoothed stroke
    smoothing.dart
    hit_test.dart           #   pure element hit-testing
    text_layout.dart        #   paragraph layout + shrink-to-fit
    system_fonts.dart       #   enumerate installed families; detect a missing one
    shape_paths.dart        #   pure (ShapeType, Rect) -> ui.Path
    renderer/               #   CustomPainter implementations, layer compositing
  ui/                       # widgets: canvas view, tab strip, selection overlay, toolbars, panels, dialogs
    file_actions.dart       #   Save/Open/New/close+quit prompts, shared by menu and shortcuts
  state/                    # Riverpod providers/notifiers
    session.dart            #   DocumentSession: one open document + its own state
    file_service.dart       #   the only door to the disk and to native dialogs
    autosave.dart           #   3-minute sidecars; recovery on open
test/                       # mirrors lib/ structure
```

**Rules:**
- `domain/` and `format/` must stay free of Flutter imports so they are unit-testable without a widget harness.
- All mutations to the document go through command objects in `domain/commands/` (enables undo/redo). Never mutate `SkdDocument` directly from UI code.
- **There is no "the" document.** Everything scoped to one open document — the `SkdDocument`, its command stack, its selection, its viewport transform, its file path, its dirty flag — lives on a `DocumentSession`, keyed by session id. Resolve it from the active session; never introduce a global singleton for any of these. What *is* global: the active tool, brush settings, and recent colors, so switching tabs doesn't change the brush you're holding.
- Coordinates in the document model are in **document space** (logical pixels at 100% zoom). The canvas widget owns the document↔screen transform. Hit-testing and transform math run in document space; only the selection overlay's handle *sizes* are in screen space.
- **The canvas follows the window.** Resizing the window resizes the document and scales every element with it, uniformly, through a `ResizeCanvasCommand` — never by stretching, which would shear rotated shapes. Zoom (Phase 14) is the opposite: a view transform that never touches the document. A document opened from a `.skd` keeps its stored size instead.
- `CanvasElement` is a sealed type. Adding a variant means updating the codec, the renderer, and hit-testing — the compiler will tell you where via exhaustive switches. Never add an element variant without a codec round-trip test.
- Element order within `Layer.elements` is z-order, bottom to top. Do not infer z-order from anything else.

## .skd File Format (v1)

A `.skd` file is a standard ZIP archive:

```
mimetype                    # plain text: "application/x-skd" (stored, not compressed, first entry)
manifest.json               # format info
document.json               # document structure
elements/<layer-uuid>.bin   # binary element data (strokes, shapes, text), one file per layer
thumbnail.png               # 256px-max preview
```

### manifest.json
```json
{
  "format": "skd",
  "formatVersion": 1,
  "appVersion": "0.1.0",
  "createdUtc": "2026-07-09T12:00:00Z",
  "modifiedUtc": "2026-07-09T12:30:00Z"
}
```

### document.json
```json
{
  "canvas": { "width": 1920, "height": 1080, "background": "#FFFFFF" },
  "layers": [
    {
      "id": "uuid-v4",
      "name": "Layer 1",
      "visible": true,
      "opacity": 1.0,
      "blendMode": "normal",
      "elementFile": "elements/<uuid>.bin"
    }
  ]
}
```
Layer order in the array = bottom to top.

### Element binary format (`element_codec.dart`)
Little-endian. All floats are IEEE 754 float32. Element order in the blob = z-order within the layer, bottom to top.

Element `id`s are **not** persisted; they are regenerated on load. Nothing in the format may reference an element by id.

```
File header:
  magic        u32   0x534B4431 ("SKD1")
  elementCount u32

Per element:
  elementType  u8    (0 = stroke, 1 = shape, 2 = text)
  reserved     u8[3] (write zeros; readers must ignore)
  body               (layout depends on elementType, below)

Stroke body (elementType 0):
  colorRGBA    u32
  baseWidth    f32
  toolId       u8    (0 = pen, 1 = eraser)
  reserved     u8[3] (write zeros; readers must ignore)
  pointCount   u32
  points       pointCount × { x f32, y f32, pressure f32 }

Shape body (elementType 1):
  shapeType    u8    (0 = rectangle, 1 = ellipse, 2 = line, 3 = arrow, 4 = diamond)
  strokeStyle  u8    (0 = solid, 1 = dashed, 2 = dotted)
  reserved     u8[2] (write zeros; readers must ignore)
  x            f32
  y            f32
  w            f32   (always >= 0; writers normalize)
  h            f32   (always >= 0; writers normalize)
  rotation     f32   (radians, clockwise, about the rect center)
  strokeColorRGBA u32
  fillColorRGBA   u32 (alpha 0 = unfilled)
  strokeWidth  f32
  seed         u32   (reserved for future rough/hand-drawn rendering; write 0)

Text body (elementType 2):
  x            f32
  y            f32
  w            f32   (box width; text wraps to it)
  h            f32   (box height; text shrinks to fit it)
  rotation     f32   (radians, clockwise, about the box center)
  fontSize     f32   (a maximum: the rendered size is fontSize * fitScale)
  colorRGBA    u32
  align        u8    (0 = left, 1 = center, 2 = right)
  reserved     u8[3] (write zeros; readers must ignore)
  familyLen    u32
  family       familyLen × u8   (UTF-8; empty means the platform default)
  runCount     u32
  runs         runCount × {
                 styleFlags u8    (bit 0 bold, bit 1 italic, bit 2 underline)
                 reserved   u8[3] (write zeros; readers must ignore)
                 textLen    u32
                 text       textLen × u8   (UTF-8)
               }
```

The element's text is the concatenation of its runs, so styled ranges cannot
overlap. Writers emit no empty runs and merge adjacent runs with equal styling;
readers should tolerate a file that does neither. The rendered font size is
`fontSize * fitScale`, and `fitScale` is recomputed on load — it is never
stored, so it can never disagree with the text.

**Format rules:**
- Readers must reject files whose `formatVersion` is greater than they support, with a clear error.
- Readers must reject an unknown `elementType` rather than attempting to skip it — element bodies are variable-length, so an unknown type makes the rest of the blob unparseable.
- Never break v1 compatibility. Additive changes only; anything structural bumps `formatVersion`.
- Round-trip tests are mandatory: every format change needs a write→read→compare test in `test/format/`.
- Keep a golden sample file in `test/fixtures/` for each format version; readers must always be able to open all of them.

## Coding Conventions

- Dart 3, null-safe, `flutter_lints` defaults.
- Prefer immutable models (`final` fields, `copyWith`). Document mutations happen only via commands.
- One feature per PR/commit; conventional commit messages (`feat:`, `fix:`, `test:`, `refactor:`).
- Every task in ROADMAP.md is scoped to be completed (with tests) in a single session. Do not bundle multiple roadmap tasks unless asked.
- When completing a roadmap task, check it off in ROADMAP.md as part of the same change.

## Testing

- `domain/`, `format/`, `engine/smoothing`, `engine/hit_test`, `engine/shape_paths`: plain Dart unit tests, high coverage expected.
- Format tests must include: round-trip equality (for strokes, every shape type, and text with mixed runs and non-ASCII), corrupt-file rejection, unknown-future-version rejection, unknown-`elementType` rejection, and golden-fixture loading. Never assert rendered text pixels — the fonts are the user's.
- Transform math (resize, rotate) must be unit-tested per handle, including dragging a handle past its anchor so width/height flip sign.
- UI: widget tests for critical interactions (drawing a stroke registers points; dragging the rectangle tool adds a shape; undo restores state). Don't chase pixel-perfect golden images for the canvas.

## Performance Notes

- Target: no visible lag while drawing at 120Hz input. Build the in-progress stroke incrementally; never repaint all layers per pointer event.
- Composite finished layers into cached `ui.Image`s (`Picture.toImage`); only the active stroke repaints live.
- Stroke smoothing runs incrementally on the input stream, not as a post-pass over the whole stroke.