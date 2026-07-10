#!/usr/bin/env bash
#
# Package the release Linux bundle as an AppImage.
#
# Run `flutter build linux --release` first. Output lands in dist/.
#
# The AppImage's glibc floor is whatever this script runs on, so CI runs it on
# the oldest supported Ubuntu runner. Building on a newer distro produces an
# AppImage that silently refuses to start on older ones.

set -euo pipefail

APP_NAME="InkPad"
BUNDLE="build/linux/x64/release/bundle"
APPDIR="build/AppDir"
TOOLS="build/appimage-tools"
OUTPUT="${APP_NAME}-x86_64.AppImage"
LINUXDEPLOY_URL="https://github.com/linuxdeploy/linuxdeploy/releases/download/continuous/linuxdeploy-x86_64.AppImage"
# Flutter's Linux embedder is a GTK app. Plain linuxdeploy copies the libraries
# an ELF directly needs but not GTK's runtime scaffolding — gdk-pixbuf loaders,
# GIO modules, the theme machinery — nor the transitive stack behind them. The
# gtk plugin bundles those and writes the env vars that point GTK at them.
GTK_PLUGIN_URL="https://raw.githubusercontent.com/linuxdeploy/linuxdeploy-plugin-gtk/master/linuxdeploy-plugin-gtk.sh"
APPIMAGETOOL_URL="https://github.com/AppImage/AppImageKit/releases/download/continuous/appimagetool-x86_64.AppImage"

if [[ ! -x "${BUNDLE}/inkpad" ]]; then
  echo "error: ${BUNDLE}/inkpad not found. Run 'flutter build linux --release' first." >&2
  exit 1
fi

rm -rf "${APPDIR}" dist
mkdir -p "${APPDIR}/usr/bin" "${TOOLS}" dist

# The Flutter embedder locates data/ and lib/ relative to the executable via
# /proc/self/exe, so the bundle has to stay intact next to the binary.
cp -r "${BUNDLE}/." "${APPDIR}/usr/bin/"

install -Dm644 packaging/linux/inkpad.desktop \
  "${APPDIR}/usr/share/applications/inkpad.desktop"

# Ship every hicolor size, not just the 256 that linuxdeploy needs: desktop
# environments pick per context (16px in a window list, 512px in an app grid),
# and a missing size gets scaled from whatever is nearest, which looks muddy.
#
# PNG only. If the scalable SVG is present, linuxdeploy makes it the AppImage's
# .DirIcon, and the spec wants a PNG there — thumbnailers and some launchers
# render nothing from an SVG .DirIcon. The SVG stays in packaging/ for distro
# packages, which do want it.
while IFS= read -r icon; do
  install -Dm644 "${icon}" "${APPDIR}/usr/share/icons/${icon#packaging/linux/icons/}"
done < <(find packaging/linux/icons -type f -name '*.png')

ICON_256="packaging/linux/icons/hicolor/256x256/apps/inkpad.png"

if [[ ! -x "${TOOLS}/linuxdeploy" ]]; then
  curl -fsSL -o "${TOOLS}/linuxdeploy" "${LINUXDEPLOY_URL}"
  chmod +x "${TOOLS}/linuxdeploy"
fi
if [[ ! -x "${TOOLS}/linuxdeploy-plugin-gtk.sh" ]]; then
  curl -fsSL -o "${TOOLS}/linuxdeploy-plugin-gtk.sh" "${GTK_PLUGIN_URL}"
  chmod +x "${TOOLS}/linuxdeploy-plugin-gtk.sh"
fi
if [[ ! -x "${TOOLS}/appimagetool" ]]; then
  curl -fsSL -o "${TOOLS}/appimagetool" "${APPIMAGETOOL_URL}"
  chmod +x "${TOOLS}/appimagetool"
fi

# linuxdeploy is itself an AppImage. Without FUSE (containers, some runners) it
# cannot mount itself, so tell it to unpack instead.
export APPIMAGE_EXTRACT_AND_RUN=1
export OUTPUT
# The plugin finds itself on PATH, not by path.
export PATH="${PWD}/${TOOLS}:${PATH}"
export DEPLOY_GTK_VERSION=3

# Flutter's own .so files live in usr/bin/lib and are found via an $ORIGIN
# rpath. Pointing linuxdeploy at them lets it resolve their system deps without
# relocating them out from under that rpath.
#
# Deliberately not `--output appimage`: with several icon sizes present,
# linuxdeploy picks one arbitrarily for the AppDir root (it chose 64x64), and
# that file becomes .DirIcon — the thumbnail every file manager shows. We pack
# separately so the root icon is the 256 the spec asks for.
"${TOOLS}/linuxdeploy" \
  --appdir "${APPDIR}" \
  --executable "${APPDIR}/usr/bin/inkpad" \
  --desktop-file "${APPDIR}/usr/share/applications/inkpad.desktop" \
  --icon-file "${ICON_256}" \
  --library "${APPDIR}/usr/bin/lib/libflutter_linux_gtk.so" \
  --plugin gtk

install -m644 "${ICON_256}" "${APPDIR}/inkpad.png"
ln -sf inkpad.png "${APPDIR}/.DirIcon"

"${TOOLS}/appimagetool" "${APPDIR}" "dist/${OUTPUT}"
echo "built dist/${OUTPUT}"
