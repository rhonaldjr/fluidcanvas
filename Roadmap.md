# InkPad Roadmap

Tasks are ordered and sized so each one is a single Claude Code session: "implement task X.Y". Each task includes its tests. Don't start a task until everything it depends on is checked off. Check tasks off here as they're completed.

InkPad is both a freehand sketching tool and a light diagramming tool: strokes and parametric shapes are peers. Both are `CanvasElement`s, live in the same ordered list inside a layer, and share one selection/transform system.

**InkPad is multi-document.** Several documents are open at once, each in its own tab. The tab *UI* is deliberately deferred to Phase 12, but the *state* is multi-document from task 2.5 onward, because that is the part that cannot be retrofitted cheaply. Everything belonging to one open document — the `SkdDocument`, its command stack, its selection, its viewport transform, its file path, its dirty flag — lives in a `DocumentSession` keyed by session id. Never reach for "the" document; always resolve it from the active session.

What is **per-session**: document, undo/redo history, selection, zoom/pan, file path, dirty flag. What stays **global**: the active tool, brush settings, and recent colors — switching tabs must not change which brush you are holding.

---

## Phase 0 — Project Skeleton

- [x] **0.1 Init project.** Create Flutter project with desktop targets enabled (windows/macos/linux), remove mobile/web folders, add `flutter_lints`, `riverpod`, `archive`, `uuid`, `path_provider` to pubspec. App runs showing an empty window titled "InkPad".
- [x] **0.2 Folder structure.** Create the `lib/` layout from CLAUDE.md (`app/`, `domain/models/`, `domain/commands/`, `format/`, `engine/`, `ui/`, `state/`) with placeholder barrel files, and a mirrored `test/` tree. `flutter analyze` passes.
- [x] **0.3 App shell.** Basic window layout: menu bar area (File/Edit placeholders, no actions yet), left toolbar strip (empty), central canvas area with a solid white 1920×1080 "page" centered on a gray background. No interactivity.
- [x] **0.4 Continuous integration.** `.github/workflows/ci.yml`: on every push, run `flutter analyze`, `dart format --set-exit-if-changed`, and `flutter test` on an Ubuntu runner. Pin the Flutter version. Add a status badge to the README. No branch protection — single-branch, single-developer for now.

## Phase 1 — Open Source & Linux Distribution

InkPad ships as a public GitHub repository. For now the only supported platform is **Linux (AppImage, x86_64)**, developed and tested on Debian-based systems. macOS builds are deferred to Phase 16. The `windows/` target stays in the tree and builds locally, but no official Windows binaries are published.

This phase runs early on purpose: the release pipeline is easier to get right against a trivial app, and every later phase then lands with working CI and a proven path to a downloadable binary. Artifacts produced here are pre-alpha — they open an empty window and nothing more.

- [x] **1.1 Repository hygiene.** `LICENSE` (MIT), `CONTRIBUTING.md` (build steps, the analyze/test bar, conventional commits), `CODE_OF_CONDUCT.md`, GitHub issue and pull-request templates, and a `CHANGELOG.md` seeded with the first release.
- [x] **1.2 Linux AppImage.** Workflow job on the oldest supported Ubuntu runner (its glibc sets the floor for which distros can run the output). `flutter build linux --release` → assemble an AppDir with a `.desktop` file and the app icon at every hicolor size → package with `linuxdeploy` plus `linuxdeploy-plugin-gtk` (Flutter's embedder is a GTK app; the plugin bundles the pixbuf loaders and GIO modules plain linuxdeploy misses), then pack with `appimagetool` so the root `.DirIcon` is the 256px PNG rather than whichever size linuxdeploy picks → `InkPad-x86_64.AppImage`. Smoke-test the artifact in CI under `xvfb`: it launches and is still running ten seconds later. Task 13.6 later extends the `.desktop` file with the `.skd` MIME association.
- [x] **1.3 Linux release workflow.** On a `v*` tag: build the AppImage from 1.2, publish a GitHub Release, attach the AppImage, and generate a `SHA256SUMS` file. Release notes drawn from `CHANGELOG.md`. Mark pre-1.0 releases as pre-release. Phase 15 extends this workflow with the macOS artifacts.

## Phase 2 — Core Domain Models

- [x] **2.1 CanvasElement + Stroke models.** Sealed `CanvasElement {id}` with an abstract `bounds` getter. Immutable `StrokePoint {x, y, pressure}` and `Stroke extends CanvasElement {colorRGBA, baseWidth, toolId, points}` with `copyWith`, equality, and unit tests (including `bounds` of a zero- and one-point stroke).
- [x] **2.2 Shape model.** `ShapeType {rectangle, ellipse, line, arrow, diamond}`, `StrokeStyle {solid, dashed, dotted}`, and `Shape extends CanvasElement {type, x, y, w, h, rotation, strokeColorRGBA, fillColorRGBA, strokeWidth, strokeStyle}`. `fillColorRGBA` with alpha 0 means unfilled. Includes `normalized()` (folds negative `w`/`h` into `x`/`y`) and rotation-aware `bounds`. `copyWith`, equality, unit tests.
- [x] **2.3 Layer model.** Immutable `Layer {id, name, visible, opacity, blendMode, elements}` where `elements` is an ordered `List<CanvasElement>`, bottom to top. Add/remove/replace/reorder-element copy helpers. Unit tests.
- [x] **2.4 SkdDocument model.** `SkdDocument {canvasWidth, canvasHeight, backgroundRGBA, layers}` with helpers: `newDefault()` (one empty layer), layer lookup by id, replace-layer, and `findElement(id)` returning the owning layer plus the element. A document always holds at least one layer, and layer ids are unique. Unit tests.
- [x] **2.5 Session state provider.** `DocumentSession {id, document, activeLayerId}` — the per-open-document state bag that later phases extend with the command stack (6.1), selection (9.3), viewport (14.1), and file path + dirty flag (13.1, 13.3). A `SessionsNotifier` holds an ordered `sessions` list (tab order) plus `activeSessionId`, with `openSession(SkdDocument)`, `closeSession(id)`, and `setActiveSession(id)`. An `activeSessionProvider` resolves the current one; document mutations like `addElementToActiveLayer(CanvasElement)` act on it. Bootstrapping creates exactly one session from `SkdDocument.newDefault()`. Unit tests via `ProviderContainer`: two sessions stay independent, closing the active one selects a neighbour, closing the last one leaves a fresh empty session.

## Phase 3 — Draw a Line on Screen

- [x] **3.1 Pointer capture.** Canvas widget wraps the page in a `Listener`; on pointer down/move/up, collect raw `StrokePoint`s (use `event.pressure`, default 1.0 for mouse) converted into document space. For now, just `debugPrint` the point count on pointer-up.
- [x] **3.2 In-progress stroke rendering.** `CustomPainter` that renders a list of points as a stroked polyline with round caps/joins at fixed width and color. Live repaint while dragging via a `currentStroke` provider.
- [x] **3.3 Commit stroke on pointer-up.** On pointer-up, finalize the in-progress stroke into the active layer via `addElementToActiveLayer`; clear `currentStroke`. Committed elements render too (naive full repaint is fine for now). Widget test: simulate a drag, assert the active layer gained a `Stroke` with >1 points.
- [x] **3.4 Input thinning.** Drop incoming points closer than a minimum distance (e.g. 1.5px in document space) to the previous point. Unit tests on the thinning function.
- [x] **3.5 Stroke smoothing.** Pure-Dart incremental quadratic-midpoint smoothing in `engine/smoothing.dart`, applied to the in-progress stroke as points stream in. Chosen over Catmull-Rom because every emitted point is a convex combination of its inputs, so the curve cannot overshoot the input bounds. Unit tests: smoothed output has expected point counts and stays within bounds of input.

## Phase 4 — Brush Feel

- [x] **4.1 Pressure → width.** Render each stroke as a filled variable-width path: width = `baseWidth * lerp(minFactor, 1.0, pressure)`. Unit test the width function; visual check for the path.
- [x] **4.2 Brush settings state.** `Brush {colorRGBA, baseWidth}` provider; new strokes read from it. Simple toolbar controls: width slider (1–64) and 8 hardcoded color swatches.
- [x] **4.3 Color picker dialog.** Tapping a "custom color" swatch opens an HSV picker dialog; picked color becomes the brush color and is added to a recent-colors row (max 8, most recent first). The same picker is reused for shape stroke/fill in 9.7.
- [x] **4.4 Eraser tool.** Tool enum gains `{pen, eraser}` + toolbar toggle. Eraser strokes have `toolId=1` and render with `BlendMode.clear` within their layer. Rendering per layer must use `saveLayer` so erasing only affects that layer. Note: the eraser clears the layer's raster, so it erases shapes in that layer too — it is not a shape-delete.
- [x] **4.5 Stroke stabilization option.** Optional pull-string stabilizer with strength 0–10, off by default, selectable in toolbar. The pen drags an anchor on a taut string; movement inside the radius is slack, which is what kills tremor. Runs before smoothing: it decides *which* points exist, the smoother interpolates between them. Unit tests on the stabilizer function.

## Phase 5 — Performance Pass

- [x] **5.1 Layer caching.** Composite each layer's committed elements into a cached `ui.Image`; invalidate a layer's cache only when its elements change (keyed on the identity of `Layer.elements`, which `copyWith` preserves, so a rename or opacity nudge is a cache hit). Layer opacity is applied on composite, never baked into the image. Committing a stroke *appends*, so the cache extends the existing image with the new element rather than re-rasterizing the layer — a commit into a 500-stroke layer costs ~6ms instead of ~860ms. Undo, reorder and delete fall back to a full render.
- [x] **5.2 Incremental in-progress painting.** The layer stack is split into three `RepaintBoundary`s — below the active layer, the active layer, above it — and only the active one carries the live stroke, so only it repaints while drawing. The live stroke still composites *inside* its layer, which is what keeps the eraser correct. A pointer event costs one image blit plus one path (~9µs with 500 strokes committed) instead of re-rasterizing the document. Verified by paint counters in a widget test, and by `debugRepaintRainbowEnabled`.

## Phase 6 — Undo / Redo

- [x] **6.1 Command infrastructure.** `Command` interface (`apply(doc)`, `revert(doc)`), `CommandStack` with undo/redo stacks (cap 200). **One stack per `DocumentSession`**, not one globally — undo in one tab must never touch another. The session also exposes a `dirty` flag derived from whether any command has run since the last save. Unit tests, including that two sessions' stacks are independent.
- [x] **6.2 AddElementCommand.** Route stroke commit (pen and eraser) through it; Phase 9 reuses the same command for shapes. Tests: undo removes the element, redo restores it, new action clears redo stack.
- [x] **6.3 Undo/redo UI.** Edit-menu items + Ctrl/Cmd+Z, Ctrl/Cmd+Shift+Z (and Ctrl+Y on Windows) via `Shortcuts`/`Actions`. Buttons disable when stacks are empty.

## Phase 7 — Layers

- [x] **7.1 Layer panel UI.** Right-side panel listing layers top-to-bottom, showing name, visibility eye toggle, and active-layer highlight. Clicking selects the active layer.
- [x] **7.2 Add/delete layer commands.** `AddLayerCommand`, `DeleteLayerCommand` (deleting the last layer is disallowed). Panel buttons + tests including undo behavior.
- [x] **7.3 Reorder layers.** Drag-to-reorder in the panel via `ReorderableListView`, as `ReorderLayerCommand`. Tests.
- [x] **7.4 Layer opacity + rename.** Opacity slider per layer, committed as one command on release rather than one per pixel of the drag, and rename via double-click on the layer's name. Both as commands. Tests.
- [x] **7.5 Layer thumbnails.** 48px live thumbnail per layer in the panel, drawn straight from the shared layer cache image. No throttle needed: a thumbnail is a scaled blit of an image that already exists, and that image only changes when the layer's elements do.

## Phase 8 — Responsive Canvas

The document is not a fixed page: **its canvas follows the window, and the drawing scales with it.** Resizing the window wider makes every stroke bigger, keeping the composition you drew.

Scaling is always **uniform**. A window whose aspect ratio differs from the document's would otherwise stretch circles into ellipses and shear rotated shapes. Widening the window therefore adds blank canvas on the long axis rather than distorting what is already drawn.

This changes the document, but a window-driven resize is deliberately **not** undoable: undo would shrink the canvas while the window stayed put, and the layout would immediately resize it back. `ResizeCanvasCommand` exists and is undoable for resizes the user explicitly asks for.

- [x] **8.1 Element scaling.** `CanvasElement.scaled(factor, {originX, originY})` on the sealed type: `Stroke` scales its points and `baseWidth`, `Shape` scales `x`/`y`/`w`/`h` and `strokeWidth` while leaving `rotation` alone. Uniform factor only — a non-uniform one has no correct meaning for a rotated shape. Unit tests: bounds scale by the factor, pressure and rotation survive, a scale about a point leaves that point fixed, and `scaled(s)` then `scaled(1/s)` returns to within float tolerance. This is also the geometry task 9.5 needs for resize handles.
- [x] **8.2 ResizeCanvasCommand.** Captures the old canvas size *and the old layer list* — element references, so it is cheap — then `apply` scales every element by `min(newW/oldW, newH/oldH)` about the canvas centre and recentres the result. `revert` restores the captured layers verbatim rather than dividing by the factor, so undo is exact instead of accumulating float drift. `apply` recomputes from the captured layers, so redo is repeatable. Tests: undo is lossless, redo is idempotent, an empty document resizes, a degenerate size is refused.
- [x] **8.3 Canvas follows the window.** The active session's canvas size tracks the canvas viewport in logical pixels, clamped to a minimum (e.g. 320×200) so a collapsed window cannot destroy a drawing. The page is drawn at 1:1, so `CanvasView.fitScale` collapses to the identity until Phase 14 introduces zoom. Widget test: growing the window scales the strokes and leaves their relative positions intact.
- [x] **8.4 Coalesced resizes.** A window drag emits a resize per frame; debounce (~250ms after the last) and apply the resize once. **Window-driven resizes are not undoable.** Making them commands deadlocks: undo shrinks the document while the window stays put, the layout sees the mismatch and resizes it again, and undo fights the window forever. Like zoom, this is the view adapting — it just happens to rewrite document state. `ResizeCanvasCommand` remains, and *is* undoable, for a resize the user asks for (13.3's canvas-size dialog). The drag previews through the view transform, never by rewriting the document per frame. Unit tests on the debouncer; widget tests that a drag adds nothing to the undo stack and that an explicit resize does.
- [x] **8.5 Fit-to-window toggle + status bar.** A per-session preference, on by default. Off means the document keeps the canvas size it was created or opened with, and the page merely scales to fit the viewport — the behaviour of Phases 0–7, and what you want after opening a `.skd` at a fixed size. Status bar shows the canvas size and the on-screen scale.

## Phase 9 — Shapes & Selection

Shapes are parametric and stay editable forever: resizing a rectangle changes its `w`/`h`, it never resamples pixels. Selection, move, rotate, delete, duplicate and z-order operate on **any** `CanvasElement`; only resize/rotate behave differently per type (shapes adjust their parameters, strokes transform their point list).

- [x] **9.1 Shape tool + drag-to-create.** Tool enum grows to `{select, pen, eraser, rectangle, ellipse, line, arrow, diamond}` with toolbar buttons. Dragging on the canvas creates a shape from the drag rect; Shift constrains to square/circle/45° line, Alt draws from the center. Live preview while dragging; on pointer-up commit via `AddElementCommand`. Widget test: a drag with the rectangle tool adds exactly one `Shape` to the active layer.
- [x] **9.2 Shape rendering.** Pure function `(ShapeType, Rect) → ui.Path` for all five types (arrow = shaft + head sized relative to `strokeWidth`; diamond = 4-point polygon). Painter fills then strokes, honoring `strokeStyle` (solid/dashed/dotted) and `rotation`. Unit tests on path bounds and segment counts per type.
- [x] **9.3 Hit-testing + selection state.** Pure `hitTest(element, point, tolerance)`: shapes test their filled region when filled and their stroked outline otherwise, applying the inverse rotation first; strokes test distance to any segment. Phase 10 adds the text case, which tests the box. Selection is a `Set<String>` of element ids **stored on the `DocumentSession`**, so each tab remembers what it had selected. Select tool picks the topmost hit across visible layers; Shift-click toggles; dragging from empty canvas draws a rubber-band marquee. Unit tests on the hit-test math, including rotated shapes.
- [x] **9.4 Selection overlay + move.** Draw the selection bounding box, 8 resize handles, and a rotation handle above the box — all at constant *screen* size. Dragging inside the selection moves it; arrow keys nudge 1px, Shift+arrow 10px. `MoveElementsCommand` coalesces one drag gesture into one undo entry. Tests.
- [x] **9.5 Resize.** Drag any of the 8 handles, reusing the element scaling from 8.1. Shapes resize losslessly (`x`/`y`/`w`/`h`); strokes scale their points about the fixed opposite anchor. Shift preserves aspect ratio; Alt resizes about the center. Dragging a handle past its anchor must flip cleanly (negative `w`/`h` normalize). `ResizeElementsCommand`. Unit tests per handle, including both flip axes.
- [x] **9.6 Rotate.** The rotation handle rotates the selection about its center; Shift snaps to 15° increments. Shapes store `rotation`; strokes rotate their points. `RotateElementsCommand`. Tests, including that 9.3 hit-testing agrees with the rendered result.
- [x] **9.7 Shape style controls.** Toolbar controls for stroke color, fill color (including "none"), stroke width, and stroke style. They set the defaults for new shapes and, when a selection exists, apply to it via `StyleElementsCommand`. Reuses the 4.3 color picker. Tests.
- [x] **9.8 Delete, duplicate, z-order.** Delete/Backspace removes the selection; Ctrl/Cmd+D duplicates it offset by (10, 10) and selects the copy; bring-forward / send-backward / bring-to-front / send-to-back reorder within the owning layer. All are commands. Tests including undo of each.

## Phase 10 — Text

A third `CanvasElement`: a **text box** with rich runs. It carries a font family, a maximum font size, and a colour; within it, any range of characters can be **bold, italic, or underlined**.

Two decisions shape the phase:

**Text uses system fonts, and the `.skd` stores the family name.** A file opened where that family is missing falls back to the platform default, so the *glyphs and line breaks change*. Rendering is therefore not byte-identical across machines: format tests must assert layout invariants and round-trip equality, never rendered pixels, and the golden fixture (11.5) asserts that a text element **loads**, not that it paints the same. Bundled fonts, which would make rendering deterministic, are in Later / Ideas.

**A text box has a fixed size, and the text shrinks to fit it.** The stored font size is a *maximum*; the renderer picks the largest scale ≤ 1 at which the wrapped text fits the box. Nothing is ever clipped or hidden — but the size you chose is not always the size you get. The fit scale is derived, never stored, so it can never disagree with the text. Below a floor (25%) it stops shrinking and the box shows an overflow marker rather than becoming unreadable.

Adding a variant to the sealed `CanvasElement` makes every non-exhaustive `switch` a compile error. That is the point: the codec, the renderer, and hit-testing cannot silently forget about text.

- [x] **10.1 TextElement + TextRun models.** `TextRun {text, bold, italic, underline}` and `TextElement extends CanvasElement {x, y, w, h, rotation, fontFamily, fontSize, colorRGBA, align, runs}`. The element's text is the concatenation of its runs, so ranges never overlap. Invariants: no empty runs, adjacent runs with equal styling are merged. `copyWith`, equality, rotation-aware `bounds` from the stored box — the domain stays Flutter-free and never lays text out. Unit tests, including that adding the variant breaks a non-exhaustive switch.
- [x] **10.2 Text layout + shrink-to-fit.** `engine/text_layout.dart`: build a `ui.Paragraph` from a `TextElement`, wrapped to `w`, and find the largest `fitScale ∈ [0.25, 1]` whose laid-out height fits `h`. Binary search to a fixed iteration count so the result is deterministic and cheap. Also exposes caret ⇄ offset mapping for 10.5. Unit tests: a narrower box wraps to more lines; a taller box needs no shrink; the scale is monotonic in box height; a box too small clamps at 0.25 and reports overflow.
- [x] **10.3 Text rendering.** Paint the paragraph inside the rotated box, honouring per-run bold/italic/underline, the fit scale, and the element colour. Replaces the `TextElement` case that 10.1 forced into the painters. An overflow marker when clamped. Layer-cache invalidation already keys on the element list, so an edit re-rasterizes its layer only.
- [x] **10.4 Text tool + create.** Tool `text` (`T`) in the toolbar. Click places a default-sized box; drag creates one of that size. Commits via `AddElementCommand` and drops straight into edit mode. Widget test: a click adds exactly one `TextElement` and focuses it.
- [x] **10.5 In-canvas editing.** Caret, character input, IME, backspace/delete, arrow keys, Home/End, click to place the caret, drag and Shift+arrow to select a range, Ctrl/Cmd+A to select all. Typing coalesces into one `EditTextCommand` per burst (idle ~500ms, or on blur), so undo steps back a word rather than a keystroke. Escape and clicking away commit.
- [ ] **10.6 Resize and reflow.** *Partly done.* The 9.4 handles resize a text box and `TextElement.scaled` grows the box and `fontSize` together, so a corner drag keeps the text's apparent size — and `layoutText` already rewraps and re-fits whenever `w` or `h` changes. **Still to do:** side handles should change the box *without* scaling `fontSize`, so dragging the right edge rewraps the text instead of magnifying it. That needs `resizeFactor` to become axis-aware, which today measures only along the diagonal.
- [x] **10.7 Bold, italic, underline on a selection.** Toolbar buttons and Ctrl/Cmd+B / I / U. With a range selected they apply to it, splitting the runs it straddles; with nothing selected they apply to the whole element. Toggling twice restores the original run list exactly — the merge rule from 10.1 is what makes that true. `StyleTextRunsCommand`. Unit tests on run splitting and merging: styling the middle of a run yields three, un-styling it collapses back to one.
- [ ] **10.8 Font family, size, and colour.** *Partly done.* A size field ships in the toolbar and `StyleTextElementCommand` covers family, size, colour and alignment. **Still to do:** the family picker (enumerating installed fonts), wiring the 4.3 colour picker to text, and the visible fallback notice when a file names a family the system lacks.

## Phase 11 — The .skd File Format

- [ ] **11.1 Element binary codec.** `element_codec.dart`: encode/decode `List<CanvasElement>` ↔ bytes per the spec in CLAUDE.md (magic, count, per-element `elementType` discriminator, float32 LE). Strokes, shapes and text elements all round-trip; text carries its family name and run list as length-prefixed UTF-8. Unit tests: round-trip equality for strokes, every shape type, and text with mixed runs (including non-ASCII); bad magic rejected, truncated data rejected, unknown `elementType` rejected.
- [ ] **11.2 Manifest + document JSON.** Serializers for `manifest.json` and `document.json` with `toJson`/`fromJson` and validation (unknown blend modes → "normal"; missing fields → error). Unit tests.
- [ ] **11.3 SkdWriter.** Assemble ZIP: uncompressed `mimetype` first entry, manifest, document.json, one `elements/<id>.bin` per layer. Writes atomically (temp file + rename). Test: output unzips with standard tools and entries match spec.
- [ ] **11.4 SkdReader.** Open ZIP → validate mimetype + formatVersion → parse manifest/document → decode element blobs → return `SkdDocument`. Errors are typed (`SkdFormatException` with reason). Tests: full round-trip write→read→deep-equals, corrupt zip rejected, formatVersion 999 rejected with clear message.
- [ ] **11.5 Golden fixture.** Commit a small hand-verified v1 `.skd` file to `test/fixtures/` containing at least one stroke, one of each shape type, and a text element with mixed bold/italic/underline runs; add a test that it always loads and deep-equals the expected model. It must **not** assert rendered pixels: text uses system fonts, so glyphs and line breaks differ across machines. This locks backward compatibility forever.
- [ ] **11.6 Thumbnail generation.** Render the flattened document to a max-256px PNG and include as `thumbnail.png` in the ZIP. Test: entry exists and decodes as a valid PNG with correct aspect ratio — not that its pixels match a golden, since text renders with whatever fonts the machine has.

## Phase 12 — Multi-Document Tabs

The state has been per-session since 2.5; this phase gives it a face. It lands before the File menu so that New, Open, Save and quit are written tab-aware from the start rather than retrofitted afterwards.

- [ ] **12.1 Tab bar UI.** A tab strip between the menu bar and the canvas: one tab per `DocumentSession`, showing its title (`Untitled 1`, `Untitled 2`, … until 13.1 gives sessions a file path), a dot when the session is dirty, and a close button. Clicking a tab calls `setActiveSession`. A `+` button opens a new empty session. Hidden entirely when only one session is open. Widget tests: two sessions render two tabs; clicking the inactive one switches the canvas.
- [ ] **12.2 Tab lifecycle + shortcuts.** Ctrl/Cmd+T opens a tab, Ctrl/Cmd+W closes one, Ctrl+Tab and Ctrl+Shift+Tab cycle, Ctrl/Cmd+1..9 jump to the nth. Closing a dirty session prompts to save (a stub dialog until 13.1 can actually write files). Closing the last session leaves one fresh empty session rather than an empty window. Tests for each path, including that closing the active tab focuses a neighbour.
- [ ] **12.3 Tab reorder + overflow.** Drag to reorder tabs. When tabs exceed the strip width they shrink to a minimum, then scroll horizontally. Middle-click closes a tab. Tests on the reorder model.

## Phase 13 — File Menu Integration

- [ ] **13.1 Save / Save As.** File menu + Ctrl/Cmd+S, acting on the **active session**. Uses `file_selector` with the `.skd` extension filter. The session gains a `filePath`; plain Save overwrites silently. Tab titles switch from `Untitled N` to the file's base name, and the window title becomes `<file> — InkPad`.
- [ ] **13.2 Open.** File → Open loads a `.skd` **into a new session/tab**, never replacing the current one. An opened document keeps the canvas size stored in the file, so fit-to-window (8.5) starts off for it — resizing the window must not silently rescale a drawing someone saved at a chosen size. If that path is already open, focus its existing tab instead of opening a duplicate. Corrupt/unsupported files show a friendly error dialog and open no tab.
- [ ] **13.3 New + dirty tracking.** File → New opens a **new tab** after a canvas-size dialog (presets + custom, plus a "fit to window" choice that leaves 8.5 enabled). Dirty state is per session (any command since that session last saved); the tab shows a dot and the window title an `*`. Closing a dirty tab, and quitting with any dirty tab, prompt to save — quit must offer to review each dirty session rather than discarding them all.
- [ ] **13.4 Recent files.** File → Open Recent (last 8), persisted with `shared_preferences`; missing files are pruned from the list. Opening one follows 13.2's rules.
- [ ] **13.5 Autosave.** Every 3 minutes, each dirty session writes a sidecar `<name>.skd.autosave`; on open, if a newer autosave exists offer recovery; delete a session's sidecar on its successful manual save. Unsaved `Untitled` sessions autosave to a scratch directory keyed by session id.
- [ ] **13.6 OS file association.** Register `.skd` association + document icon per platform (Windows installer manifest, macOS Info.plist CFBundleDocumentTypes, Linux `.desktop` + MIME xml — extending the `.desktop` file from 1.2). Opening a `.skd` from the OS launches the app with the file. Extend the 1.2 AppImage smoke test to open a `.skd` passed as `argv[1]`.

## Phase 14 — Canvas Navigation

- [ ] **14.1 Zoom.** Ctrl+scroll zooms around the cursor (10%–800%); Ctrl+0 resets to fit. Zoom is a *view* transform and never touches the document, unlike the canvas resize of 8.3. Zoom level shown in a status bar. The viewport transform lives on the `DocumentSession`, so switching tabs restores each document's own zoom and scroll position. Drawing coordinates stay correct at all zooms, selection handles keep a constant screen size, and hit-testing still picks the right element at 10% and 800% (widget tests).
- [ ] **14.2 Pan.** Space-drag and middle-mouse-drag pan the canvas; cursor changes to a hand while panning.
- [ ] **14.3 Pinch/trackpad gestures.** Two-finger scroll pans, pinch zooms, on trackpads via `PointerPanZoomEvent`s.

## Phase 15 — Export & Polish

- [ ] **15.1 Export PNG.** File → Export → PNG: flatten at 1×/2×/4× scale with optional transparent background (skip document background fill).
- [ ] **15.2 Keyboard shortcuts reference.** V = select, B = pen, E = eraser, R = rectangle, O = ellipse, L = line, A = arrow, D = diamond, `[` / `]` = brush size down/up, plus a Help → Shortcuts dialog listing everything.
- [ ] **15.3 Preferences window.** Persisted settings: default canvas size, autosave interval, default brush, default shape style, theme (light/dark/system).
- [ ] **15.4 Crash-safe format stress test.** Property-based test: generate random documents (0–50 layers, 0–1000 elements mixing strokes and all five shape types, 0–5000 points per stroke), round-trip through writer/reader, deep-compare. Fuzz the reader with random byte mutations of a valid file — must never crash, only throw `SkdFormatException`.
- [ ] **15.5 App icon + naming.** Final app name decision, and wire the master artwork in `images/` into the remaining platforms: `inkpad.ico` for the Windows runner, `inkpad.icns` / an `AppIcon.appiconset` generated from `inkpad_icon_1024.png` for macOS. Linux already ships its icons from 1.2. Set the GTK window icon (`gtk_window_set_icon_name`), verifying on a real desktop that the icon theme resolves it — inside the AppImage it currently warns "Could not load a pixbuf from icon theme". Window title format `<file> — InkPad`.

## Phase 16 — macOS Builds & Releases

Deferred until the app is feature-complete and polished on Linux. It sits after Phase 15 rather than earlier because the macOS bundle wants the real icons from 15.5, and because signing costs money that a pre-alpha doesn't justify.

- [ ] **16.1 macOS Apple Silicon build.** Workflow job on an arm64 macOS runner. Uses the app icon from 15.5 (`images/inkpad.icns`, or an `AppIcon.appiconset` rendered from `images/inkpad_icon_1024.png` — Xcode wants the asset catalog, not the `.icns`). `flutter build macos --release` → `InkPad.app` → `.dmg`. Verify the binary is arm64 (`lipo -archs`). Unsigned builds are blocked by Gatekeeper on first launch, so document the right-click → Open workaround until 16.3 lands.
- [ ] **16.2 macOS in the release workflow.** Extend the 1.3 tag workflow to also build 16.1 and attach the `.dmg` to the GitHub Release, with its checksum in `SHA256SUMS`. Update the README platform table.
- [ ] **16.3 macOS signing + notarization.** Sign with a Developer ID certificate and notarize via `notarytool`, using repository secrets. Requires a paid Apple Developer account — until one exists, 16.1's builds stay unsigned and this task is blocked.

---

## Later / Ideas (unscheduled)

- Windows binaries in CI. The `windows/` target already builds locally; this is a packaging job (MSIX or an Inno Setup installer) plus code signing, deliberately deferred.
- Linux packaging beyond AppImage: Flatpak, `.deb`, AUR.
- macOS Intel (x86_64) or universal builds, if anyone asks.
- Bundled fonts, so text renders identically on every machine. Would make thumbnails and PNG exports reproducible and let golden fixtures assert pixels. The format already stores a family name, so a bundled family is just a name the reader always resolves.
- Per-run font size and colour, not only bold/italic/underline. The run record has spare style bits.
- Text on a path; bulleted and numbered lists.
- Hand-drawn "rough" rendering style for shapes (seeded jitter, Excalidraw-like). The shape record already reserves a `seed` field, so this is an additive format change.
- Snapping and alignment guides; snap-to-grid.
- Group / ungroup elements.
- Connectors that bind to shapes and follow them when moved.
- More brush engines (texture, pencil, airbrush) — add `toolId` values, format stays v1-compatible via reserved bytes
- Format v2: per-point timestamps + tilt (bump `formatVersion`, keep v1 reader)
- Layer groups and clipping masks
- Tablet pen buttons / eraser-tip mapping
- Infinite canvas mode
