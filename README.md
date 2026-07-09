# InkPad

A cross-platform desktop app for freehand sketching and light diagramming.

Draw with a mouse or a pressure-sensitive stylus, drop in resizable shapes, organize everything into layers, and save to `.skd` — an open, documented file format.

> **Status: pre-alpha.** Phase 0 of the [roadmap](Roadmap.md) is complete: the app opens a window and shows a blank page. You cannot draw anything yet. There are no releases, and the file format is not yet implemented. Watch the repo if you want to know when it becomes usable.

## What it will do

- **Freehand strokes** with pressure-sensitive width, input smoothing, and an optional stabilizer.
- **Predefined shapes** — rectangle, ellipse, line, arrow, diamond — that stay parametric. Resizing a rectangle changes its width and height; it never resamples pixels.
- **One selection system for both.** Strokes and shapes are peers. Select, move, rotate, reorder, and delete either.
- **Layers** with visibility, opacity, blend modes, reordering, and live thumbnails.
- **Undo/redo** for every document mutation, via a command stack.
- **A real file format.** `.skd` is a ZIP container with a JSON manifest and binary element data, specified in [CLAUDE.md](CLAUDE.md) and locked by golden-fixture tests.
- **PNG export** at 1×, 2×, or 4×, with an optional transparent background.

## Platform support

| Platform | Official binaries | Notes |
| --- | --- | --- |
| Linux | AppImage (x86_64) | Built by CI. |
| macOS | Apple Silicon (arm64) | Built by CI. Initially unsigned, so Gatekeeper needs a right-click → Open on first launch. |
| Windows | None yet | The `windows/` target is in the tree and builds locally. Packaging and signing are deferred. |

No web or mobile targets are planned.

## Building from source

You need the [Flutter SDK](https://docs.flutter.dev/get-started/install) on the stable channel (developed against 3.44.6 / Dart 3.12).

**Linux** additionally needs the desktop toolchain:

```bash
sudo apt install clang cmake ninja-build pkg-config libgtk-3-dev
```

**macOS** needs Xcode and its command-line tools.

Then:

```bash
git clone https://github.com/<owner>/fluidcanvas.git
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

`flutter analyze` and `flutter test` must both pass before any change is considered done. Two rules the codebase enforces with tests:

- `lib/domain/` and `lib/format/` contain **no Flutter imports**, so they are unit-testable without a widget harness.
- All document mutations go through command objects, never direct mutation from UI code. This is what makes undo/redo total.

Architecture, coding conventions, and the full `.skd` format specification live in [CLAUDE.md](CLAUDE.md).

## Contributing

The project is built roadmap task by roadmap task — see [Roadmap.md](Roadmap.md), where each entry is scoped to a single self-contained change with its tests. Picking up an unchecked task is the easiest way in. Please don't bundle several tasks into one pull request.

Commit messages follow the conventional style: `feat:`, `fix:`, `test:`, `refactor:`.

Contributor guidelines, issue templates, and a code of conduct arrive with roadmap task 12.1.

## License

MIT. The `LICENSE` file lands with roadmap task 12.1.
