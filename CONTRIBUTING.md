# Contributing to InkPad

Thanks for your interest. InkPad is pre-alpha — the app opens a window and
nothing else works yet — so the most useful contributions right now are
roadmap tasks, not bug reports against features that don't exist.

By participating you agree to abide by the [Code of Conduct](CODE_OF_CONDUCT.md).

## How the project is built

Work is organized as an ordered list of tasks in [Roadmap.md](Roadmap.md). Each
task is scoped to be completed, **with its tests**, in one sitting, and each
names its own acceptance criteria.

- Pick an **unchecked** task whose dependencies are all checked off.
- Open an issue (or comment on an existing one) saying you're taking it, so two
  people don't do the same work.
- **One task per pull request.** Don't bundle several tasks together, even if
  they feel related. Small reviewable changes are the entire point of the
  structure.
- Check the task off in `Roadmap.md` as part of the same pull request.

If you want to do something that isn't on the roadmap, open an issue first and
let's discuss where it fits. The "Later / Ideas" section at the bottom of the
roadmap is the parking lot for unscheduled work.

## Setting up

You need the [Flutter SDK](https://docs.flutter.dev/get-started/install) on the
stable channel. The project is developed against **Flutter 3.44.6 / Dart 3.12**,
which is also what CI pins.

Linux additionally needs the desktop toolchain:

```bash
sudo apt install clang cmake ninja-build pkg-config libgtk-3-dev
```

macOS needs Xcode and its command-line tools.

```bash
git clone https://github.com/rhonaldjr/fluidcanvas.git
cd fluidcanvas
flutter pub get
flutter run -d linux      # or: -d macos
```

Run `flutter doctor` if something fails; it names missing pieces precisely.

## The bar for a change

CI runs these three on every push, and all three must pass:

```bash
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test
```

Run them locally before you push. `dart format lib test` fixes formatting in
place.

## Architecture rules

These are enforced, not merely encouraged. [CLAUDE.md](CLAUDE.md) has the full
picture; the load-bearing rules are:

- **`lib/domain/` and `lib/format/` contain no Flutter imports.** They are pure
  Dart so they can be unit-tested without a widget harness. A test in
  `test/architecture_test.dart` fails the build if you break this.
- **Every document mutation goes through a command object** in
  `lib/domain/commands/`. Never mutate `SkdDocument` from UI code. This is what
  makes undo/redo total rather than best-effort.
- **Coordinates in the model are document space**, logical pixels at 100% zoom.
  The canvas widget owns the document↔screen transform.
- **`CanvasElement` is a sealed type.** Adding a variant means updating the
  codec, the renderer, and hit-testing. The compiler will point at every
  exhaustive switch that needs a new case; a codec round-trip test is mandatory.

## The file format

`.skd` is specified in [CLAUDE.md](CLAUDE.md). Two rules matter more than the
rest:

- **Never break v1 compatibility.** Additive changes only; anything structural
  bumps `formatVersion`.
- Every format change needs a write→read→compare test in `test/format/`, and the
  golden fixtures in `test/fixtures/` must keep loading forever.

## Tests

- `domain/`, `format/`, `engine/smoothing`, `engine/hit_test`, `engine/shape_paths`:
  plain Dart unit tests, high coverage expected.
- Format tests must cover round-trip equality, corrupt-file rejection,
  unknown-future-version rejection, and golden-fixture loading.
- UI: widget tests for critical interactions. Don't chase pixel-perfect golden
  images for the canvas.

## Commits and pull requests

Commit messages follow the conventional style:

```
feat: add ellipse shape tool
fix: normalize negative width when resizing past the anchor
test: cover truncated stroke blobs
refactor: extract shape path generation
docs: clarify formatVersion policy
```

Describe *what changed and why* in the pull request body. If the change is
visual, attach a screenshot. If it's a roadmap task, say which one.

## Cutting a release

Releases are driven entirely by pushing a `v*` tag. The workflow builds the
AppImage with the same reusable job CI runs, smoke-tests it, and publishes a
GitHub Release with the binary and a `SHA256SUMS` file.

Two things must line up before you tag, and the workflow fails loudly if they
don't:

1. **`pubspec.yaml` version matches the tag.** Tag `v0.3.0` requires
   `version: 0.3.0+<build>`. Otherwise the binary misreports its own version.
2. **`CHANGELOG.md` has a section for it.** Rename `## [Unreleased]` to
   `## [0.3.0] - YYYY-MM-DD`; that section becomes the release notes. An empty
   or missing section aborts the release rather than publishing blank notes.

```bash
# after bumping pubspec.yaml and renaming the changelog heading
git commit -am "chore: release 0.3.0"
git tag v0.3.0
git push origin main --tags
```

Anything below `1.0.0`, or carrying a suffix like `0.3.0-beta.1`, is published
as a GitHub **pre-release**.

You can rehearse the checks locally without tagging:

```bash
./scripts/check_version.sh 0.3.0
./scripts/release_notes.sh 0.3.0
```

## Reporting bugs

Use the issue templates. A bug report without a reproduction is a wish. Include
your OS, `flutter --version`, and — if it's a file-format problem — attach the
`.skd` file if you can share it.
