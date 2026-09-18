#!/bin/bash
# Packs build/Cartridge.app into build/Cartridge-<version>.dmg: the app, a shortcut to Applications and a pixel-art
# background, laid out the way a Mac installer is. Usage: ./Tools/make-dmg.sh (after ./build-app.sh)
#
# dmgbuild writes the window layout directly rather than scripting Finder, so this works the same on a GitHub
# runner as on a Mac with a screen.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="$(sed -n 's/^VERSION="\(.*\)"$/\1/p' "${ROOT}/build-app.sh")"
APP="${ROOT}/build/Cartridge.app"
OUT="${ROOT}/build/Cartridge-${VERSION}.dmg"
DMGBUILD_VERSION="1.6.7"
[[ -d "${APP}" ]] || { echo "No ${APP} - run ./build-app.sh first" >&2; exit 1; }

WORK="$(mktemp -d)"
trap 'rm -rf "${WORK}"' EXIT

# dmgbuild, pinned, in its own environment unless one was handed in.
DMGBUILD="${DMGBUILD:-}"
if [[ -z "${DMGBUILD}" ]]; then
    VENV="${ROOT}/.build/dmgbuild-${DMGBUILD_VERSION}"
    if [[ ! -x "${VENV}/bin/dmgbuild" ]]; then
        echo "==> Installing dmgbuild ${DMGBUILD_VERSION}"
        python3 -m venv "${VENV}"
        "${VENV}/bin/pip" install --quiet "dmgbuild==${DMGBUILD_VERSION}"
    fi
    DMGBUILD="${VENV}/bin/dmgbuild"
fi

echo "==> Drawing the background"
swift "${ROOT}/Tools/make-dmg-background.swift" "${WORK}/background.png" 1 "${VERSION}"
swift "${ROOT}/Tools/make-dmg-background.swift" "${WORK}/background@2x.png" 2 "${VERSION}"
tiffutil -cathidpicheck "${WORK}/background.png" "${WORK}/background@2x.png" -out "${WORK}/background.tiff" >/dev/null

# A clean copy: files under ~/Desktop pick up extended attributes that have no business in an installer.
ditto --noextattr --norsrc "${APP}" "${WORK}/Cartridge.app"

echo "==> Packing ${OUT##*/}"
rm -f "${OUT}"
"${DMGBUILD}" -s "${ROOT}/Tools/dmg-settings.py" \
    -D app="${WORK}/Cartridge.app" -D background="${WORK}/background.tiff" -D version="${VERSION}" \
    "Cartridge ${VERSION}" "${OUT}"

# The app inside must still be exactly what was signed.
MOUNT="$(mktemp -d)"
hdiutil attach -nobrowse -readonly -mountpoint "${MOUNT}" "${OUT}" >/dev/null
codesign --verify --deep "${MOUNT}/Cartridge.app"
hdiutil detach "${MOUNT}" >/dev/null
echo "==> ${OUT}"
