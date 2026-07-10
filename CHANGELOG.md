# Changelog

All notable changes to InkPad are documented here.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and
the project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

Versions below 1.0 make no compatibility promises about the application. The
`.skd` file format is the exception: once `formatVersion` 1 ships, every later
reader must open it.

## [Unreleased]

### Added

- Flutter desktop project targeting Linux, macOS, and Windows.
- Application shell: File/Edit menu bar, left tool strip, and a white
  1920×1080 page centered on a gray backdrop.
- Immutable domain models: sealed `CanvasElement` with `Stroke` and `Shape`
  variants, `StrokePoint`, `Bounds`, and `Layer`. Strokes and shapes share one
  z-ordered list per layer.
- Freehand drawing: pressure-sensitive variable-width strokes, input thinning,
  incremental quadratic-midpoint smoothing, and an optional pull-string
  stabilizer.
- Brush toolbar: width slider, eight colour swatches, an HSV custom-colour
  picker with a recent-colours row, and a pen/eraser toggle.
- Per-layer image caching with incremental append, and a three-way repaint
  split so drawing repaints only the active layer.
- Undo/redo: a per-session command stack capped at 200, Edit-menu items naming
  the command, and Ctrl/Cmd+Z, Ctrl/Cmd+Shift+Z and Ctrl+Y shortcuts.
- Layer panel: add, delete, reorder by dragging, rename, opacity, visibility,
  and live thumbnails. Every change is undoable.
- Responsive canvas: the document follows the window and every element scales
  with it, uniformly, with a fit-to-window toggle and a status bar.
- Shapes: rectangle, ellipse, line, arrow and diamond, with fill, dashed and
  dotted outlines, drag-to-create with Shift/Alt constraints.
- Selection: click, Shift-click, rubber-band marquee, move, resize, rotate,
  delete, duplicate and z-order — all undoable, one entry per gesture.
- Text boxes with rich bold/italic/underline runs, wrapping, and shrink-to-fit.
- Continuous integration on every push: formatting, static analysis, and tests.
- Linux AppImage packaging, built and smoke-tested in CI on every push.
- Tag-driven release workflow publishing the AppImage and a `SHA256SUMS` file.
- MIT license, contributor guidelines, and code of conduct.

### Notes

- You can draw, but not undo, save, or open. There is no file format yet, so
  nothing you draw survives closing the window.
