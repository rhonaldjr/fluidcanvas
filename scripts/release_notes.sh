#!/usr/bin/env bash
#
# Print the CHANGELOG.md section for one version, for use as release notes.
#
#   scripts/release_notes.sh 0.1.0
#
# Fails loudly when the section is missing. A release published with silently
# empty notes is worse than a release that refuses to publish.

set -euo pipefail

VERSION="${1:?usage: release_notes.sh <version>}"
CHANGELOG="CHANGELOG.md"

[[ -f "${CHANGELOG}" ]] || { echo "error: ${CHANGELOG} not found" >&2; exit 1; }

# Print lines after the matching `## [x.y.z]` heading, stopping at the next
# `## ` heading. awk beats sed here because the terminator is a pattern, not a
# line count.
notes=$(awk -v version="${VERSION}" '
  $0 ~ "^## \\[" version "\\]" { capture = 1; next }
  capture && /^## / { exit }
  capture { print }
' "${CHANGELOG}")

# Strip leading and trailing blank lines.
notes=$(printf '%s\n' "${notes}" | sed -e '/./,$!d' | tac | sed -e '/./,$!d' | tac)

if [[ -z "${notes}" ]]; then
  echo "error: no '## [${VERSION}]' section in ${CHANGELOG}, or the section is empty." >&2
  echo "hint: rename the [Unreleased] heading to [${VERSION}] before tagging." >&2
  exit 1
fi

printf '%s\n' "${notes}"
