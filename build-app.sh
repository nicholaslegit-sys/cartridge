#!/bin/bash
# Builds Cartridge.app into ./build. Usage: ./build-app.sh
set -euo pipefail

VERSION="1.3.2"
BUILD="9"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Assemble and sign outside ~/Desktop: iCloud-synced folders keep adding extended attributes that codesign rejects.
STAGE="$(mktemp -d)"
trap 'rm -rf "${STAGE}"' EXIT
APP="${STAGE}/Cartridge.app"
OUT="${ROOT}/build/Cartridge.app"
cd "${ROOT}"

echo "==> Building (release)"
swift build -c release --product Cartridge
BIN="$(swift build -c release --product Cartridge --show-bin-path)/Cartridge"

echo "==> Assembling"
rm -rf "${APP}"
mkdir -p "${APP}/Contents/MacOS" "${APP}/Contents/Resources"
cp "${BIN}" "${APP}/Contents/MacOS/Cartridge"

ICONSET="$(mktemp -d)/Cartridge.iconset"
mkdir -p "${ICONSET}"
cp .github/assets/icon.png "${ICONSET}/icon_512x512@2x.png"
for s in 16 32 128 256 512; do
    sips -z $s $s "${ICONSET}/icon_512x512@2x.png" --out "${ICONSET}/icon_${s}x${s}.png" >/dev/null
    sips -z $((s * 2)) $((s * 2)) "${ICONSET}/icon_512x512@2x.png" --out "${ICONSET}/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "${ICONSET}" -o "${APP}/Contents/Resources/Cartridge.icns"

cat > "${APP}/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>Cartridge</string>
    <key>CFBundleDisplayName</key><string>Cartridge</string>
    <key>CFBundleIdentifier</key><string>app.cartridge.launcher</string>
    <key>CFBundleExecutable</key><string>Cartridge</string>
    <key>CFBundleIconFile</key><string>Cartridge</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>${VERSION}</string>
    <key>CFBundleVersion</key><string>${BUILD}</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSApplicationCategoryType</key><string>public.app-category.games</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSHumanReadableCopyright</key><string>© 2026 Nicholas Seymour</string>
</dict>
</plist>
PLIST

echo "==> Signing (ad-hoc)"
xattr -cr "${APP}"
codesign --force --sign - "${APP}"
codesign --verify "${APP}"

mkdir -p "$(dirname "${OUT}")"
rm -rf "${OUT}"
ditto --noextattr --norsrc "${APP}" "${OUT}"
codesign --verify "${OUT}"
echo "==> ${OUT}"
