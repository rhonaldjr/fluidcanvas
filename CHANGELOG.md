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
- Continuous integration on every push: formatting, static analysis, and tests.
- Linux AppImage packaging, built and smoke-tested in CI on every push.
- Tag-driven release workflow publishing the AppImage and a `SHA256SUMS` file.
- MIT license, contributor guidelines, and code of conduct.

### Notes

- Nothing is drawable yet. This is a skeleton, not a usable application.
