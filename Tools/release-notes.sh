#!/bin/bash
# Prints a release's notes: its section of CHANGELOG.md - or, when the changelog has none, the commits since the
# last release - and then how to install it. Usage: Tools/release-notes.sh 1.2.0
set -euo pipefail

VERSION="${1:?usage: release-notes.sh <version>}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

notes="$(awk -v version="${VERSION}" '
    /^## / { if (found) exit; found = index($0, "[" version "]") > 0; next }
    found
' "${ROOT}/CHANGELOG.md")"

if [[ -z "${notes//[[:space:]]/}" ]]; then
    previous="$(git -C "${ROOT}" describe --tags --abbrev=0 2>/dev/null || true)"
    notes="### Changes"$'\n\n'"$(git -C "${ROOT}" log --no-merges --pretty='- %s' ${previous:+"${previous}..HEAD"})"
fi

printf '%s\n\n' "$(printf '%s' "${notes}" | sed -e '/./,$!d')"
cat <<EOF
### Installing

Open \`Cartridge-${VERSION}.dmg\` and drag Cartridge into Applications.

Cartridge is ad-hoc signed rather than notarized, so macOS stops it the first time:

- **macOS 15 or later:** try to open it, then choose **Open Anyway** in **System Settings → Privacy & Security**.
- **macOS 14:** right-click the app and choose **Open**.
EOF
