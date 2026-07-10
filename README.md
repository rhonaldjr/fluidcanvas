# InkPad

[![CI](https://github.com/rhonaldjr/fluidcanvas/actions/workflows/ci.yml/badge.svg)](https://github.com/rhonaldjr/fluidcanvas/actions/workflows/ci.yml)

A cross-platform desktop app for freehand sketching and light diagramming.

Draw with a mouse or a pressure-sensitive stylus, drop in resizable shapes, organize everything into layers, and save to `.skd` — an open, documented file format.

> **Status: pre-alpha. You cannot draw yet.**
>
> What exists: the app shell (window, menu bar, tool strip, blank page), Linux AppImage packaging with a tag-driven release workflow, and the immutable domain models — `CanvasElement`, `Stroke`, `Shape`, `Layer`.
>
> What doesn't: pointer input, rendering, undo, tabs, and the `.skd` file format. There are no releases yet.
>
> Progress is tracked task by task in the [roadmap](Roadmap.md). Watch the repo if you want to know when it becomes usable.

## What it will do

- **Freehand strokes** with pressure-sensitive width, input smoothing, and an optional stabilizer.
- **Predefined shapes** — rectangle, ellipse, line, arrow, diamond — that stay parametric. Resizing a rectangle changes its width and height; it never resamples pixels.
- **One selection system for both.** Strokes and shapes are peers. Select, move, rotate, reorder, and delete either.
- **Multiple documents in tabs.** Each tab keeps its own undo history, selection, and zoom level.
- **Layers** with visibility, opacity, blend modes, reordering, and live thumbnails.
- **Undo/redo** for every document mutation, via a command stack.
- **A real file format.** `.skd` is a ZIP container with a JSON manifest and binary element data, specified in [CLAUDE.md](CLAUDE.md) and locked by golden-fixture tests.
- **PNG export** at 1×, 2×, or 4×, with an optional transparent background.

## Platform support

| Platform | Official binaries | Notes |
| --- | --- | --- |
| Linux | AppImage (x86_64) | Built by CI. Developed and tested on Debian-based systems. Needs a desktop with the usual font stack and GL drivers; everything else is bundled. |
| macOS | None yet | Apple Silicon builds are planned once the app is feature-complete on Linux. Builds locally today. |
| Windows | None yet | The `windows/` target is in the tree and builds locally. Packaging and signing are deferred. |

No web or mobile targets are planned.

Every release attaches a `SHA256SUMS` file. To verify a download:

```bash
sha256sum -c SHA256SUMS
```

## Building from source

You need the [Flutter SDK](https://docs.flutter.dev/get-started/install) on the stable channel (developed against 3.44.6 / Dart 3.12).

**Linux** additionally needs the desktop toolchain:

```bash
sudo apt install clang cmake ninja-build pkg-config libgtk-3-dev
```

**macOS** needs Xcode and its command-line tools.

Then:

```bash
git clone https://github.com/rhonaldjr/fluidcanvas.git
cd fluidcanvas
flutter pub get
flutter run -d linux      # or: -d macos
```

Run `flutter doctor` if something fails; it names missing pieces precisely.

## Development

```bash
flutter test                 # all tests
flutter test test/format/    # file-format tests only
flutter analyze              # static analysis — must be clean
dart format lib test         # formatting
```

To build the AppImage locally, after `flutter build linux --release`:

```bash
./scripts/build_appimage.sh        # → dist/InkPad-x86_64.AppImage
./scripts/smoke_test_appimage.sh   # launches it under xvfb to prove it starts
```

`flutter analyze` and `flutter test` must both pass before any change is considered done.

### Design notes

A handful of decisions shape everything else. Most are enforced by the compiler or by tests.

- **`lib/domain/` and `lib/format/` contain no Flutter imports**, so they are unit-testable without a widget harness. A test fails the build if you add one. This is why the domain has its own `Bounds` instead of using `ui.Rect`.
- **`CanvasElement` is a sealed type** with exactly two variants, `Stroke` and `Shape`. Adding a third makes every non-exhaustive `switch` a compile error, which is how the codec, the renderer, and hit-testing stay in sync.
- **Strokes and shapes are peers.** They share one ordered `List<CanvasElement>` per layer, bottom to top, so z-order between a freehand line and a rectangle needs no special case.
- **Shapes are parametric.** Resizing changes `w`/`h`; it never resamples pixels. Mid-drag a shape may carry negative extents — `normalized()` folds the sign back into `x`/`y`.
- **`bounds` is geometry, not ink.** It ignores stroke width, because a 40px stroke paints 20px beyond its points. Callers needing painted extent call `inflate(width / 2)`.
- **Models are immutable.** Every mutator returns a copy, lists are unmodifiable, and equality is by value, compared deeply.
- **All document mutations go through command objects**, never direct mutation from UI code. This is what makes undo/redo total.
- **There is no "the" document.** Each open tab is a `DocumentSession` owning its own document, undo stack, selection, and zoom.
- **Wire values are pinned.** The numbers behind `ShapeType` and `ToolId` are written into `.skd` files; reordering an enum would silently reinterpret every saved document. An unknown *shape* is rejected, while an unknown *blend mode* falls back to `normal` — a file from a future version must still open.

Architecture, coding conventions, and the full `.skd` format specification live in [CLAUDE.md](CLAUDE.md).

## Contributing

The project is built roadmap task by roadmap task — see [Roadmap.md](Roadmap.md), where each entry is scoped to a single self-contained change with its tests. Picking up an unchecked task is the easiest way in. Please don't bundle several tasks into one pull request.

Read [CONTRIBUTING.md](CONTRIBUTING.md) before opening a pull request; it covers the setup, the architecture rules that are enforced by tests, and the commit conventions. Everyone participating is expected to follow the [Code of Conduct](CODE_OF_CONDUCT.md).

## License

[MIT](LICENSE). Copyright © 2026 Akro Technologies.
