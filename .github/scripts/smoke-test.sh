#!/bin/bash
# Launches a built Cartridge.app and checks it actually comes up: signature intact, process stays alive,
# and a window on screen. Runs against a throwaway CARTRIDGE_HOME so it never touches a real library.
# Usage: ./.github/scripts/smoke-test.sh [path/to/Cartridge.app] [seconds to wait for the window]
set -euo pipefail

APP="${1:-build/Cartridge.app}"
WAIT="${2:-30}"
BIN="${APP}/Contents/MacOS/Cartridge"

if [ ! -x "${BIN}" ]; then
    echo "No executable at ${BIN} - build it first with ./build-app.sh" >&2
    exit 1
fi

HOME_DIR="$(mktemp -d)"
LOG="$(mktemp)"
WINDOW_CHECK="$(mktemp -d)/window.swift"
cleanup() {
    [ -n "${PID:-}" ] && kill "${PID}" 2>/dev/null || true
    rm -rf "${HOME_DIR}" "${LOG}" "$(dirname "${WINDOW_CHECK}")"
}
trap cleanup EXIT

# Not --strict: an iCloud-synced folder such as Desktop keeps adding extended attributes to the copy in build/,
# which --strict counts as detritus even though the signature itself is fine.
echo "==> Verifying the signature"
codesign --verify "${APP}"

# CGWindowList reports the owner and bounds of every window without needing screen-recording permission.
# An app owns more than its window: a 0x0 placeholder and the 1024x24 menu bar are both layer 0, so the window
# has to be picked by size. Anything smaller than the app's own minimum is not the app having come up.
cat > "${WINDOW_CHECK}" <<'SWIFT'
import CoreGraphics
import Foundation

let pid = Int(CommandLine.arguments[1])!
let deadline = Date().addingTimeInterval(Double(CommandLine.arguments[2]) ?? 30)
let minimum = CGSize(width: 400, height: 300)

func windows(of pid: Int) -> [(name: String, size: CGSize)] {
    let all = (CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]]) ?? []
    return all.compactMap { entry in
        guard entry[kCGWindowOwnerPID as String] as? Int == pid, entry[kCGWindowLayer as String] as? Int == 0,
              let bounds = entry[kCGWindowBounds as String] as? [String: Any] else { return nil }
        let size = CGSize(width: bounds["Width"] as? Double ?? 0, height: bounds["Height"] as? Double ?? 0)
        return (entry[kCGWindowName as String] as? String ?? "", size)
    }
}

while Date() < deadline {
    if let real = windows(of: pid).filter({ $0.size.width >= minimum.width && $0.size.height >= minimum.height })
        .max(by: { $0.size.width * $0.size.height < $1.size.width * $1.size.height }) {
        print("window \(Int(real.size.width))x\(Int(real.size.height))\(real.name.isEmpty ? "" : " “\(real.name)”")")
        exit(0)
    }
    usleep(500_000)
}
let seen = windows(of: pid).map { "\(Int($0.size.width))x\(Int($0.size.height)) “\($0.name)”" }
FileHandle.standardError.write(Data("""
    no window of at least \(Int(minimum.width))x\(Int(minimum.height)) appeared for pid \(pid)
    windows it does own: \(seen.isEmpty ? "none" : seen.joined(separator: ", "))

    """.utf8))
exit(1)
SWIFT

echo "==> Launching with CARTRIDGE_HOME=${HOME_DIR}"
CARTRIDGE_HOME="${HOME_DIR}" "${BIN}" >"${LOG}" 2>&1 &
PID=$!

fail() {
    echo "$1" >&2
    echo "--- app output ---" >&2
    cat "${LOG}" >&2
    for report in "${HOME}/Library/Logs/DiagnosticReports/Cartridge"*; do
        [ -e "${report}" ] || continue
        echo "--- ${report} ---" >&2
        head -40 "${report}" >&2
    done
    exit 1
}

if ! swift "${WINDOW_CHECK}" "${PID}" "${WAIT}"; then
    kill -0 "${PID}" 2>/dev/null && fail "Cartridge started but never showed a window"
    fail "Cartridge exited before showing a window"
fi

kill -0 "${PID}" 2>/dev/null || fail "Cartridge quit right after opening its window"

echo "==> Quitting"
kill "${PID}"
wait "${PID}" 2>/dev/null || true
PID=""
echo "==> Cartridge.app runs"
