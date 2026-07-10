#!/usr/bin/env bash
#
# Assert that a release tag matches the version in pubspec.yaml.
#
#   scripts/check_version.sh 0.1.0     # tag v0.1.0
#
# pubspec carries a build number (`0.1.0+1`); the tag does not. Only the
# semantic part is compared. Catches the easy mistake of tagging a release
# without bumping pubspec, which ships a binary that misreports its own version.

set -euo pipefail

VERSION="${1:?usage: check_version.sh <version>}"

pubspec_version=$(awk '/^version:/ { print $2; exit }' pubspec.yaml)
pubspec_semver="${pubspec_version%%+*}"

if [[ "${pubspec_semver}" != "${VERSION}" ]]; then
  echo "error: tag says ${VERSION} but pubspec.yaml says ${pubspec_semver} (from '${pubspec_version}')." >&2
  echo "hint: bump 'version:' in pubspec.yaml, or retag." >&2
  exit 1
fi

echo "version ${VERSION} matches pubspec.yaml"
