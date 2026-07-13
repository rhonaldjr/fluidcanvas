#!/usr/bin/env bash
#
# Package the release Linux bundle as a Debian .deb.
#
# Run `flutter build linux --release` first. Output lands in dist/.
#
# Layout follows the convention for a self-contained (non-distro-built) app:
# the whole Flutter bundle goes under /opt, and /usr/bin/inkpad is a symlink to
# it. The Flutter embedder finds data/ and lib/ via /proc/self/exe, which
# resolves through the symlink to the real /opt path, so the launcher works
# from anywhere on PATH.

set -euo pipefail

APP_NAME="InkPad"
BIN_NAME="inkpad"
BUNDLE="build/linux/x64/release/bundle"
PKGROOT="build/deb"
ARCH="amd64"

if [[ ! -x "${BUNDLE}/${BIN_NAME}" ]]; then
  echo "error: ${BUNDLE}/${BIN_NAME} not found. Run 'flutter build linux --release' first." >&2
  exit 1
fi

# Version from pubspec: the semantic part before the build number.
version=$(awk '/^version:/ { print $2; exit }' pubspec.yaml)
version="${version%%+*}"
OUTPUT="${BIN_NAME}_${version}_${ARCH}.deb"

# Clear our own staging and prior .deb, but leave the rest of dist/ alone: the
# AppImage build shares this directory, and CI runs both.
rm -rf "${PKGROOT}"
mkdir -p dist
rm -f "dist/${OUTPUT}"

# --- Payload -------------------------------------------------------------
install -d "${PKGROOT}/opt/${BIN_NAME}"
cp -r "${BUNDLE}/." "${PKGROOT}/opt/${BIN_NAME}/"

install -d "${PKGROOT}/usr/bin"
ln -s "/opt/${BIN_NAME}/${BIN_NAME}" "${PKGROOT}/usr/bin/${BIN_NAME}"

install -Dm644 packaging/linux/${BIN_NAME}.desktop \
  "${PKGROOT}/usr/share/applications/${BIN_NAME}.desktop"
install -Dm644 packaging/linux/${BIN_NAME}-skd.xml \
  "${PKGROOT}/usr/share/mime/packages/${BIN_NAME}-skd.xml"
install -Dm644 packaging/linux/io.github.rhonaldjr.InkPad.metainfo.xml \
  "${PKGROOT}/usr/share/metainfo/io.github.rhonaldjr.InkPad.metainfo.xml"

# Every hicolor size, PNG and the scalable SVG, so each desktop context picks a
# crisp icon instead of scaling one.
while IFS= read -r icon; do
  install -Dm644 "${icon}" \
    "${PKGROOT}/usr/share/icons/${icon#packaging/linux/icons/}"
done < <(find packaging/linux/icons -type f \( -name '*.png' -o -name '*.svg' \))

install -Dm644 LICENSE "${PKGROOT}/usr/share/doc/${BIN_NAME}/copyright"
install -Dm644 fonts/LICENSE-DejaVu.txt \
  "${PKGROOT}/usr/share/doc/${BIN_NAME}/LICENSE-DejaVu.txt"

# --- Control -------------------------------------------------------------
# Installed-Size is in KiB, per Debian policy.
installed_kib=$(du -ks "${PKGROOT}" | cut -f1)

install -d "${PKGROOT}/DEBIAN"
cat > "${PKGROOT}/DEBIAN/control" <<EOF
Package: ${BIN_NAME}
Version: ${version}
Section: graphics
Priority: optional
Architecture: ${ARCH}
Installed-Size: ${installed_kib}
Depends: libgtk-3-0 (>= 3.24.0), libglib2.0-0, zlib1g
Maintainer: Akro Technologies <rhonaldjr@akrotechnologies.ca>
Homepage: https://github.com/rhonaldjr/fluidcanvas
Description: ${APP_NAME} — freehand sketching and light diagramming
 InkPad is a cross-platform desktop sketching and light diagramming app.
 Draw freehand strokes, place resizable shapes, type rich text into boxes,
 organize work into layers, and save to the .skd file format. Fonts are
 bundled, so text renders identically on every machine.
EOF

# Refresh the desktop, MIME, and icon caches so the launcher and the .skd
# association appear immediately. Each guard tolerates a minimal system that
# lacks the tool.
cat > "${PKGROOT}/DEBIAN/postinst" <<'EOF'
#!/bin/sh
set -e
if [ "$1" = "configure" ]; then
  if command -v update-desktop-database >/dev/null 2>&1; then
    update-desktop-database -q /usr/share/applications || true
  fi
  if command -v update-mime-database >/dev/null 2>&1; then
    update-mime-database /usr/share/mime || true
  fi
  if command -v gtk-update-icon-cache >/dev/null 2>&1; then
    gtk-update-icon-cache -q -t -f /usr/share/icons/hicolor || true
  fi
fi
EOF
chmod 0755 "${PKGROOT}/DEBIAN/postinst"

cp "${PKGROOT}/DEBIAN/postinst" "${PKGROOT}/DEBIAN/postrm"

# --- Build ---------------------------------------------------------------
# --root-owner-group so files are owned by root:root without needing fakeroot.
dpkg-deb --build --root-owner-group "${PKGROOT}" "dist/${OUTPUT}"
echo "built dist/${OUTPUT}"
