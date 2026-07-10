# CLAUDE.md

Guidance for Claude Code when working in this repository.

## Project Overview

**InkPad** (working name) is a cross-platform desktop sketching and light diagramming application. Users draw freehand strokes with a mouse or pressure-sensitive stylus, place predefined shapes (rectangle, ellipse, line, arrow, diamond) that stay resizable, type rich text into resizable boxes, organize work into layers, and save to a proprietary `.skd` file format.

Strokes, shapes, text, connectors and groups are peers: all are `CanvasElement`s, all live in a single ordered list per layer (bottom to top), and all share one selection/transform system. Shapes are **parametric** — resizing a rectangle changes its width and height, it never resamples pixels. A shape can be drawn **rough**: seeded jitter over the parametric outline, a pure function of `(seed, geometry)`, so it wobbles the same way on every machine and every repaint. Hit-testing always uses the parametric outline, never the wobble.

A **connector** joins two endpoints, each either a free point or **bound** to a sibling. A bound endpoint is derived, never stored — moving a shape needs no command that touches the connector, and undo stays exact. A **group** is an ordered, nestable list of children that transforms as one rigid body and hit-tests as one element.

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
    models/                 #   CanvasElement, Stroke, StrokePoint, Shape, TextElement, Connector, Group, Layer, SkdDocument, Brush
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
    rough.dart              #   seeded hand-drawn jitter for shapes
    snapping.dart           #   pure snap math: candidates in, delta + guides out
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
- **The canvas follows the window** — for a **bounded** document. Resizing the window resizes the document and scales every element with it, uniformly, through a `ResizeCanvasCommand` — never by stretching, which would shear rotated shapes. Zoom is the opposite: a `ViewTransform` on the `DocumentSession` that never touches the document, is never a command, and never marks it dirty. A document opened from a `.skd` keeps its stored size instead. An **infinite** document (`CanvasMode.infinite`) has no page: it ignores the stored size, never resizes to the window, drops the page border, and you pan/zoom over an unbounded plane. Infinite documents bypass the layer-image cache (which is a fixed `width × height`) and repaint their elements live through `InfiniteCanvasPainter`; export and thumbnails derive their bounds from the content, not a page.
- `CanvasElement` is a sealed type. Adding a variant means updating the codec, the renderer, and hit-testing — the compiler will tell you where via exhaustive switches. Never add an element variant without a codec round-trip test.
- Element order within `Layer.elements` is z-order, bottom to top. Do not infer z-order from anything else.

## .skd File Format (v3)

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
  "formatVersion": 3,
  "appVersion": "0.1.0",
  "createdUtc": "2026-07-09T12:00:00Z",
  "modifiedUtc": "2026-07-09T12:30:00Z"
}
```

### document.json
```json
{
  "canvas": { "width": 1920, "height": 1080, "background": "#FFFFFF",
              "mode": "infinite" },   // omitted when bounded (the default)
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
Layer order in the array = bottom to top. `canvas.mode` is `"infinite"` for an unbounded document and **omitted** for a bounded one, so older files and re-saved bounded documents are byte-for-byte unchanged; a missing or unknown value reads as bounded.

### Element binary format (`element_codec.dart`)
Little-endian. All floats are IEEE 754 float32. Element order in the blob = z-order within the layer, bottom to top.

Element `id`s are **not** persisted; they are regenerated on load. Nothing in the format may reference an element by id.

```
File header:
  magic        u32   0x534B4431 ("SKD1")
  elementCount u32

Per element:
  elementType  u8    (0 = stroke, 1 = shape, 2 = text, 3 = connector, 4 = group)
  reserved     u8[3] (write zeros; readers must ignore)
  body               (layout depends on elementType, below)

Stroke body (elementType 0):
  colorRGBA    u32
  baseWidth    f32
  toolId       u8    (0 = pen, 1 = eraser, 2 = pencil, 3 = airbrush, 4 = texture;
                     unknown values render as the pen, never rejected)
  reserved     u8[3] (write zeros; readers must ignore)
  pointCount   u32
  points       pointCount × { x f32, y f32, pressure f32 }

Shape body (elementType 1):
  shapeType    u8    (0 = rectangle, 1 = ellipse, 2 = line, 3 = arrow, 4 = diamond)
  strokeStyle  u8    (0 = solid, 1 = dashed, 2 = dotted)
  renderStyle  u8    (0 = precise, 1 = rough)   [v2; v1 wrote zero here]
  reserved     u8[1] (write zeros; readers must ignore)
  x            f32
  y            f32
  w            f32   (always >= 0; writers normalize)
  h            f32   (always >= 0; writers normalize)
  rotation     f32   (radians, clockwise, about the rect center)
  strokeColorRGBA u32
  fillColorRGBA   u32 (alpha 0 = unfilled)
  strokeWidth  f32
  seed         u32   (seeds the jitter of renderStyle 1; 0 when precise)

Text body (elementType 2):
  x            f32
  y            f32
  w            f32   (box width; text wraps to it)
  h            f32   (box height; text shrinks to fit it)
  rotation     f32   (radians, clockwise, about the box center)
  fontSize     f32   (a maximum: the rendered size is fontSize * fitScale)
  colorRGBA    u32
  align        u8    (0 = left, 1 = center, 2 = right)
  listStyle    u8    (0 = none, 1 = bullet, 2 = numbered)   [v3]
  textFlags    u8    (bit 0 = a path-binding index follows the runs)  [v3]
  reserved     u8[1] (write zeros; readers must ignore)
  familyLen    u32
  family       familyLen × u8   (UTF-8; empty means the platform default)
  runCount     u32
  runs         runCount × {
                 styleFlags u8    (bit 0 bold, 1 italic, 2 underline,
                                   3 has fontSize, 4 has colorRGBA)
                 reserved   u8[3] (write zeros; readers must ignore)
                 [if bit 3] fontSize f32   [v3]
                 [if bit 4] colorRGBA u32  [v3]
                 textLen    u32
                 text       textLen × u8   (UTF-8)
               }
  [if textFlags bit 0] pathIndex u32   [v3] index of the sibling whose outline
                 the glyphs flow along, like a connector end; 0xFFFFFFFF or an
                 index that names nothing reads as unbound. Resolved in a second
                 pass, so the text may sit below the element it binds to.
```

Connector body (elementType 3):
  strokeStyle  u8    (0 = solid, 1 = dashed, 2 = dotted)
  startArrow   u8    (0 or 1)
  endArrow     u8    (0 or 1)
  reserved     u8[1] (write zeros; readers must ignore)
  strokeColorRGBA u32
  strokeWidth  f32
  start              (endpoint, below)
  end                (endpoint, below)

Connector endpoint:
  kind         u8    (0 = free, 1 = bound)
  reserved     u8[3] (write zeros; readers must ignore)
  x            f32   (free only; writers zero it when bound)
  y            f32   (free only; writers zero it when bound)
  boundIndex   u32   (bound only; 0xFFFFFFFF when free)

Group body (elementType 4):
  childCount   u32   (>= 2)
  children     childCount × (elementType u8 + reserved u8[3] + body)

The element's text is the concatenation of its runs, so styled ranges cannot
overlap. Writers emit no empty runs and merge adjacent runs with equal styling;
readers should tolerate a file that does neither. The rendered font size is
`fontSize * fitScale`, and `fitScale` is recomputed on load — it is never
stored, so it can never disagree with the text. A run may **override** the
element's font size and colour (v3, marked by styleFlags bits 3 and 4); the
bits are self-describing, so a v3 reader parses a v1/v2 run — whose bits are
zero — with no extra fields, and a per-run size rides the shrink-to-fit scale
like the element's own.

A connector's `boundIndex` is an index into **its own container's** element list — the layer's elements, or the group's children — because element ids are not persisted and nothing in the format may reference one. Element order is z-order, which makes the index stable. A bound endpoint stores no coordinates: where it lands is *derived* from the element it points at, so a connector can never go stale. A binding that names nothing, names itself, or names another connector is read as a free end rather than rejected — a connector in the wrong place beats refusing to open the drawing.

**Format rules:**
- Readers must reject files whose `formatVersion` is greater than they support, with a clear error. A v1 reader therefore refuses a v2 file cleanly, instead of choking on `elementType` 3 or 4.
- Readers must reject an unknown `elementType` rather than attempting to skip it — element bodies are variable-length, so an unknown type makes the rest of the blob unparseable.
- Never break v1 compatibility. Additive changes only; anything structural bumps `formatVersion`.
- Round-trip tests are mandatory: every format change needs a write→read→compare test in `test/format/`.
- Keep a golden sample file in `test/fixtures/` for each format version; readers must always be able to open all of them. `v1_golden.skd` and `v2_golden.skd` exist; `tool/make_v2_fixture.dart` regenerates the latter, which is a deliberate act, not a build step.

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
- Composite finished layers into cached `ui.Image`s (`Picture.toImageSync`); only the active stroke repaints live.
- **Text glyphs do not render into an offscreen buffer on the real renderer** — this bites in *two* places, and `flutter test`'s offscreen rasterizer is blind to both (it *does* capture text), so no unit test catches it. Paths (strokes, shapes) survive an offscreen; only `drawParagraph` comes out blank.
  1. **`Picture.toImageSync`** (the layer cache): so a layer holding any text (directly or inside a group — see `layerHasText`) is painted **live** by `LayerStackPainter`, `InfiniteCanvasPainter` and the layer-panel thumbnail, never through the cache. Only text-free layers use the cached image.
  2. **`saveLayer`** (the per-layer composite for opacity/eraser isolation): text drawn *inside* a `saveLayer` is also blank. So a text layer only opens a `saveLayer` when it truly needs one (`textLayerNeedsIsolation`: sub-1 opacity, or an eraser) and then draws its **text on top of** the isolated content, not within it. A full-opacity, eraser-free text layer draws straight onto the canvas. This is the whole reason the shared `elementHasText` / `layerHasText` / `textLayerNeedsIsolation` helpers exist.

  Rule of thumb: **never let `drawParagraph` run inside `toImageSync` or `saveLayer`.** The isolation decision is unit-tested (`text_layer_live_test.dart`), but the glyph-blanking itself can only be seen by building and running the real GTK app.
- Stroke smoothing runs incrementally on the input stream, not as a post-pass over the whole stroke.