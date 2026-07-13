#!/usr/bin/env bash
#
# Package the release macOS bundle as a drag-to-install .dmg.
#
# Run `flutter build macos --release` first. Output lands in dist/.
#
# The build is ad-hoc signed (the project's Release config sets
# CODE_SIGN_IDENTITY = "-"), so no Apple Developer account is needed to produce
# it — but Gatekeeper blocks an unsigned app on first launch. Until signing +
# notarization land (roadmap 16.3), users open it with right-click → Open once.

set -euo pipefail

APP_NAME="InkPad"
APP="build/macos/Build/Products/Release/${APP_NAME}.app"
BIN="${APP}/Contents/MacOS/${APP_NAME}"
STAGING="build/dmg"
OUTPUT="${APP_NAME}-arm64.dmg"

if [[ ! -d "${APP}" ]]; then
  echo "error: ${APP} not found. Run 'flutter build macos --release' first." >&2
  exit 1
fi

# The whole point of the arm64 runner: refuse to ship an x86_64 (or fat) binary
# labelled as an Apple Silicon build. `lipo -archs` lists the slices present.
archs=$(lipo -archs "${BIN}")
if [[ "${archs}" != "arm64" ]]; then
  echo "error: expected an arm64-only binary, got '${archs}'." >&2
  echo "hint: this job must run on an Apple Silicon (arm64) runner." >&2
  exit 1
fi
echo "verified ${BIN} is arm64"

# Stage the .app beside an /Applications symlink, so the mounted volume shows
# the familiar "drag InkPad onto Applications" layout.
rm -rf "${STAGING}" dist
mkdir -p "${STAGING}" dist
cp -R "${APP}" "${STAGING}/"
ln -s /Applications "${STAGING}/Applications"

# UDZO = zlib-compressed, the standard read-only distribution format.
hdiutil create \
  -volname "${APP_NAME}" \
  -srcfolder "${STAGING}" \
  -ov \
  -format UDZO \
  "dist/${OUTPUT}"

echo "built dist/${OUTPUT}"
