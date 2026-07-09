# InkPad Roadmap

Tasks are ordered and sized so each one is a single Claude Code session: "implement task X.Y". Each task includes its tests. Don't start a task until everything it depends on is checked off. Check tasks off here as they're completed.

InkPad is both a freehand sketching tool and a light diagramming tool: strokes and parametric shapes are peers. Both are `CanvasElement`s, live in the same ordered list inside a layer, and share one selection/transform system.

---

## Phase 0 — Project Skeleton

- [x] **0.1 Init project.** Create Flutter project with desktop targets enabled (windows/macos/linux), remove mobile/web folders, add `flutter_lints`, `riverpod`, `archive`, `uuid`, `path_provider` to pubspec. App runs showing an empty window titled "InkPad".
- [x] **0.2 Folder structure.** Create the `lib/` layout from CLAUDE.md (`app/`, `domain/models/`, `domain/commands/`, `format/`, `engine/`, `ui/`, `state/`) with placeholder barrel files, and a mirrored `test/` tree. `flutter analyze` passes.
- [x] **0.3 App shell.** Basic window layout: menu bar area (File/Edit placeholders, no actions yet), left toolbar strip (empty), central canvas area with a solid white 1920×1080 "page" centered on a gray background. No interactivity.
- [ ] **0.4 Continuous integration.** `.github/workflows/ci.yml`: on push and pull request, run `flutter analyze`, `dart format --set-exit-if-changed`, and `flutter test` on an Ubuntu runner. Pin the Flutter version. Required to pass before merge. Add a status badge to the README.

## Phase 1 — Core Domain Models

- [ ] **1.1 CanvasElement + Stroke models.** Sealed `CanvasElement {id}` with an abstract `bounds` getter. Immutable `StrokePoint {x, y, pressure}` and `Stroke extends CanvasElement {colorRGBA, baseWidth, toolId, points}` with `copyWith`, equality, and unit tests (including `bounds` of a zero- and one-point stroke).
- [ ] **1.2 Shape model.** `ShapeType {rectangle, ellipse, line, arrow, diamond}`, `StrokeStyle {solid, dashed, dotted}`, and `Shape extends CanvasElement {type, x, y, w, h, rotation, strokeColorRGBA, fillColorRGBA, strokeWidth, strokeStyle}`. `fillColorRGBA` with alpha 0 means unfilled. Includes `normalized()` (folds negative `w`/`h` into `x`/`y`) and rotation-aware `bounds`. `copyWith`, equality, unit tests.
- [ ] **1.3 Layer model.** Immutable `Layer {id, name, visible, opacity, blendMode, elements}` where `elements` is an ordered `List<CanvasElement>`, bottom to top. Add/remove/replace/reorder-element copy helpers. Unit tests.
- [ ] **1.4 SkdDocument model.** `SkdDocument {canvasWidth, canvasHeight, background, layers}` with helpers: `newDefault()` (one empty layer), layer lookup by id, replace-layer, and `findElement(id)` returning the owning layer plus the element. Unit tests.
- [ ] **1.5 Document state provider.** Riverpod `StateNotifier` holding the current `SkdDocument` + `activeLayerId`. Exposes `addElementToActiveLayer(CanvasElement)`. Unit tests via `ProviderContainer`.

## Phase 2 — Draw a Line on Screen

- [ ] **2.1 Pointer capture.** Canvas widget wraps the page in a `Listener`; on pointer down/move/up, collect raw `StrokePoint`s (use `event.pressure`, default 1.0 for mouse) converted into document space. For now, just `debugPrint` the point count on pointer-up.
- [ ] **2.2 In-progress stroke rendering.** `CustomPainter` that renders a list of points as a stroked polyline with round caps/joins at fixed width and color. Live repaint while dragging via a `currentStroke` provider.
- [ ] **2.3 Commit stroke on pointer-up.** On pointer-up, finalize the in-progress stroke into the active layer via `addElementToActiveLayer`; clear `currentStroke`. Committed elements render too (naive full repaint is fine for now). Widget test: simulate a drag, assert the active layer gained a `Stroke` with >1 points.
- [ ] **2.4 Input thinning.** Drop incoming points closer than a minimum distance (e.g. 1.5px in document space) to the previous point. Unit tests on the thinning function.
- [ ] **2.5 Stroke smoothing.** Pure-Dart incremental Catmull-Rom (or quadratic midpoint) smoothing in `engine/smoothing.dart`, applied to the in-progress stroke as points stream in. Unit tests: smoothed output has expected point counts and stays within bounds of input.

## Phase 3 — Brush Feel

- [ ] **3.1 Pressure → width.** Render each stroke as a filled variable-width path: width = `baseWidth * lerp(minFactor, 1.0, pressure)`. Unit test the width function; visual check for the path.
- [ ] **3.2 Brush settings state.** `Brush {colorRGBA, baseWidth}` provider; new strokes read from it. Simple toolbar controls: width slider (1–64) and 8 hardcoded color swatches.
- [ ] **3.3 Color picker dialog.** Tapping a "custom color" swatch opens an HSV picker dialog; picked color becomes the brush color and is added to a recent-colors row (max 8, most recent first). The same picker is reused for shape stroke/fill in 7.7.
- [ ] **3.4 Eraser tool.** Tool enum gains `{pen, eraser}` + toolbar toggle. Eraser strokes have `toolId=1` and render with `BlendMode.clear` within their layer. Rendering per layer must use `saveLayer` so erasing only affects that layer. Note: the eraser clears the layer's raster, so it erases shapes in that layer too — it is not a shape-delete.
- [ ] **3.5 Stroke stabilization option.** Optional pull-string/averaging stabilizer with strength 0–10, off by default, selectable in toolbar. Unit tests on the stabilizer function.

## Phase 4 — Performance Pass

- [ ] **4.1 Layer caching.** Composite each layer's committed elements into a cached `ui.Image`; invalidate a layer's cache only when its elements change. Only the in-progress stroke paints live. Manual perf check: drawing stays smooth with 500+ elements.
- [ ] **4.2 Incremental in-progress painting.** Repaint only the dirty region of the active stroke (use `RepaintBoundary` + smallest-rect invalidation). Verify with `debugRepaintRainbowEnabled`.

## Phase 5 — Undo / Redo

- [ ] **5.1 Command infrastructure.** `Command` interface (`apply(doc)`, `revert(doc)`), `CommandStack` with undo/redo stacks (cap 200), Riverpod integration. Unit tests.
- [ ] **5.2 AddElementCommand.** Route stroke commit (pen and eraser) through it; Phase 7 reuses the same command for shapes. Tests: undo removes the element, redo restores it, new action clears redo stack.
- [ ] **5.3 Undo/redo UI.** Edit-menu items + Ctrl/Cmd+Z, Ctrl/Cmd+Shift+Z (and Ctrl+Y on Windows) via `Shortcuts`/`Actions`. Buttons disable when stacks are empty.

## Phase 6 — Layers

- [ ] **6.1 Layer panel UI.** Right-side panel listing layers top-to-bottom, showing name, visibility eye toggle, and active-layer highlight. Clicking selects the active layer.
- [ ] **6.2 Add/delete layer commands.** `AddLayerCommand`, `DeleteLayerCommand` (deleting the last layer is disallowed). Panel buttons + tests including undo behavior.
- [ ] **6.3 Reorder layers.** Drag-to-reorder in the panel via `ReorderableListView`, as `ReorderLayerCommand`. Tests.
- [ ] **6.4 Layer opacity + rename.** Opacity slider per layer and rename via double-click, both as commands. Tests.
- [ ] **6.5 Layer thumbnails.** 48px live thumbnail per layer in the panel, regenerated (throttled, e.g. 500ms after last change) from the layer cache image.

## Phase 7 — Shapes & Selection

Shapes are parametric and stay editable forever: resizing a rectangle changes its `w`/`h`, it never resamples pixels. Selection, move, rotate, delete, duplicate and z-order operate on **any** `CanvasElement`; only resize/rotate behave differently per type (shapes adjust their parameters, strokes transform their point list).

- [ ] **7.1 Shape tool + drag-to-create.** Tool enum grows to `{select, pen, eraser, rectangle, ellipse, line, arrow, diamond}` with toolbar buttons. Dragging on the canvas creates a shape from the drag rect; Shift constrains to square/circle/45° line, Alt draws from the center. Live preview while dragging; on pointer-up commit via `AddElementCommand`. Widget test: a drag with the rectangle tool adds exactly one `Shape` to the active layer.
- [ ] **7.2 Shape rendering.** Pure function `(ShapeType, Rect) → ui.Path` for all five types (arrow = shaft + head sized relative to `strokeWidth`; diamond = 4-point polygon). Painter fills then strokes, honoring `strokeStyle` (solid/dashed/dotted) and `rotation`. Unit tests on path bounds and segment counts per type.
- [ ] **7.3 Hit-testing + selection state.** Pure `hitTest(element, point, tolerance)`: shapes test their filled region when filled and their stroked outline otherwise, applying the inverse rotation first; strokes test distance to any segment. `selectionProvider` holds a `Set<String>` of element ids. Select tool picks the topmost hit across visible layers; Shift-click toggles; dragging from empty canvas draws a rubber-band marquee. Unit tests on the hit-test math, including rotated shapes.
- [ ] **7.4 Selection overlay + move.** Draw the selection bounding box, 8 resize handles, and a rotation handle above the box — all at constant *screen* size. Dragging inside the selection moves it; arrow keys nudge 1px, Shift+arrow 10px. `MoveElementsCommand` coalesces one drag gesture into one undo entry. Tests.
- [ ] **7.5 Resize.** Drag any of the 8 handles. Shapes resize losslessly (`x`/`y`/`w`/`h`); strokes scale their points about the fixed opposite anchor. Shift preserves aspect ratio; Alt resizes about the center. Dragging a handle past its anchor must flip cleanly (negative `w`/`h` normalize). `ResizeElementsCommand`. Unit tests per handle, including both flip axes.
- [ ] **7.6 Rotate.** The rotation handle rotates the selection about its center; Shift snaps to 15° increments. Shapes store `rotation`; strokes rotate their points. `RotateElementsCommand`. Tests, including that 7.3 hit-testing agrees with the rendered result.
- [ ] **7.7 Shape style controls.** Toolbar controls for stroke color, fill color (including "none"), stroke width, and stroke style. They set the defaults for new shapes and, when a selection exists, apply to it via `StyleElementsCommand`. Reuses the 3.3 color picker. Tests.
- [ ] **7.8 Delete, duplicate, z-order.** Delete/Backspace removes the selection; Ctrl/Cmd+D duplicates it offset by (10, 10) and selects the copy; bring-forward / send-backward / bring-to-front / send-to-back reorder within the owning layer. All are commands. Tests including undo of each.

## Phase 8 — The .skd File Format

- [ ] **8.1 Element binary codec.** `element_codec.dart`: encode/decode `List<CanvasElement>` ↔ bytes per the spec in CLAUDE.md (magic, count, per-element `elementType` discriminator, float32 LE). Unit tests: round-trip equality for strokes and every shape type, bad magic rejected, truncated data rejected, unknown `elementType` rejected.
- [ ] **8.2 Manifest + document JSON.** Serializers for `manifest.json` and `document.json` with `toJson`/`fromJson` and validation (unknown blend modes → "normal"; missing fields → error). Unit tests.
- [ ] **8.3 SkdWriter.** Assemble ZIP: uncompressed `mimetype` first entry, manifest, document.json, one `elements/<id>.bin` per layer. Writes atomically (temp file + rename). Test: output unzips with standard tools and entries match spec.
- [ ] **8.4 SkdReader.** Open ZIP → validate mimetype + formatVersion → parse manifest/document → decode element blobs → return `SkdDocument`. Errors are typed (`SkdFormatException` with reason). Tests: full round-trip write→read→deep-equals, corrupt zip rejected, formatVersion 999 rejected with clear message.
- [ ] **8.5 Golden fixture.** Commit a small hand-verified v1 `.skd` file to `test/fixtures/` containing at least one stroke and one of each shape type; add a test that it always loads. This locks backward compatibility forever.
- [ ] **8.6 Thumbnail generation.** Render the flattened document to a max-256px PNG and include as `thumbnail.png` in the ZIP. Test: entry exists and decodes as a valid PNG with correct aspect ratio.

## Phase 9 — File Menu Integration

- [ ] **9.1 Save / Save As.** File menu + Ctrl/Cmd+S. Uses `file_selector` with the `.skd` extension filter. Tracks current file path; plain Save overwrites silently.
- [ ] **9.2 Open.** File → Open loads a `.skd`, replaces the document, resets undo history and selection. Corrupt/unsupported files show a friendly error dialog, current document untouched.
- [ ] **9.3 New + dirty tracking.** File → New with canvas-size dialog (presets + custom). Track dirty state (any command since last save); title bar shows `*`; New/Open/quit prompt to save when dirty.
- [ ] **9.4 Recent files.** File → Open Recent (last 8), persisted with `shared_preferences`; missing files are pruned from the list.
- [ ] **9.5 Autosave.** Every 3 minutes when dirty, write to a sidecar `<name>.skd.autosave`; on open, if a newer autosave exists offer recovery; delete sidecar on successful manual save.
- [ ] **9.6 OS file association.** Register `.skd` association + document icon per platform (Windows installer manifest, macOS Info.plist CFBundleDocumentTypes, Linux .desktop + MIME xml). Opening a `.skd` from the OS launches the app with the file.

## Phase 10 — Canvas Navigation

- [ ] **10.1 Zoom.** Ctrl+scroll zooms around the cursor (10%–800%); Ctrl+0 resets to fit. Zoom level shown in a status bar. Drawing coordinates stay correct at all zooms, selection handles keep a constant screen size, and hit-testing still picks the right element at 10% and 800% (widget tests).
- [ ] **10.2 Pan.** Space-drag and middle-mouse-drag pan the canvas; cursor changes to a hand while panning.
- [ ] **10.3 Pinch/trackpad gestures.** Two-finger scroll pans, pinch zooms, on trackpads via `PointerPanZoomEvent`s.

## Phase 11 — Export & Polish

- [ ] **11.1 Export PNG.** File → Export → PNG: flatten at 1×/2×/4× scale with optional transparent background (skip document background fill).
- [ ] **11.2 Keyboard shortcuts reference.** V = select, B = pen, E = eraser, R = rectangle, O = ellipse, L = line, A = arrow, D = diamond, `[` / `]` = brush size down/up, plus a Help → Shortcuts dialog listing everything.
- [ ] **11.3 Preferences window.** Persisted settings: default canvas size, autosave interval, default brush, default shape style, theme (light/dark/system).
- [ ] **11.4 Crash-safe format stress test.** Property-based test: generate random documents (0–50 layers, 0–1000 elements mixing strokes and all five shape types, 0–5000 points per stroke), round-trip through writer/reader, deep-compare. Fuzz the reader with random byte mutations of a valid file — must never crash, only throw `SkdFormatException`.
- [ ] **11.5 App icon + naming.** Final app name decision, icons for all three platforms, window title format `<file> — InkPad`.

## Phase 12 — Open Source & Distribution

InkPad ships as a public GitHub repository. CI builds binaries for **Linux (AppImage, x86_64)** and **macOS (Apple Silicon, arm64)**. The `windows/` target stays in the tree and builds locally, but no official Windows binaries are published yet.

- [ ] **12.1 Repository hygiene.** `LICENSE` (MIT), `CONTRIBUTING.md` (build steps, the analyze/test bar, conventional commits), `CODE_OF_CONDUCT.md`, GitHub issue and pull-request templates, and a `CHANGELOG.md` seeded with the first release.
- [ ] **12.2 Linux AppImage.** Workflow job on the oldest supported Ubuntu runner (glibc floor determines how many distros can run the output). `flutter build linux --release` → assemble an AppDir with the `.desktop` file and icon from 9.6 → package with `linuxdeploy` → `InkPad-x86_64.AppImage`. Smoke-test the artifact in CI under `xvfb`: it launches, and opening a `.skd` passed as `argv[1]` works.
- [ ] **12.3 macOS Apple Silicon build.** Workflow job on an arm64 macOS runner. `flutter build macos --release` → `InkPad.app` → `.dmg`. Verify the binary is arm64 (`lipo -archs`). Unsigned builds are blocked by Gatekeeper on first launch, so document the right-click → Open workaround until 12.5 lands.
- [ ] **12.4 Release workflow.** On a `v*` tag: run 12.2 and 12.3, publish a GitHub Release, attach the AppImage and the `.dmg`, and generate a `SHA256SUMS` file. Release notes drawn from `CHANGELOG.md`.
- [ ] **12.5 macOS signing + notarization.** Sign with a Developer ID certificate and notarize via `notarytool`, using repository secrets. Requires a paid Apple Developer account — until it exists, 12.3's builds stay unsigned and this task is blocked.

---

## Later / Ideas (unscheduled)

- Windows binaries in CI. The `windows/` target already builds locally; this is a packaging job (MSIX or an Inno Setup installer) plus code signing, deliberately deferred.
- Linux packaging beyond AppImage: Flatpak, `.deb`, AUR.
- macOS Intel (x86_64) or universal builds, if anyone asks.

- Hand-drawn "rough" rendering style for shapes (seeded jitter, Excalidraw-like). The shape record already reserves a `seed` field, so this is an additive format change.
- Text elements (click to place, in-canvas editing, resizable box) — needs font metrics in the format.
- Snapping and alignment guides; snap-to-grid.
- Group / ungroup elements.
- Connectors that bind to shapes and follow them when moved.
- More brush engines (texture, pencil, airbrush) — add `toolId` values, format stays v1-compatible via reserved bytes
- Format v2: per-point timestamps + tilt (bump `formatVersion`, keep v1 reader)
- Layer groups and clipping masks
- Tablet pen buttons / eraser-tip mapping
- Infinite canvas mode
