#!/bin/bash
set -euo pipefail
ZEN_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ZEN_ROOT"
ZEN_BUILD_ARGS=(-c release)
case "${ZEN_ARCH:-native}" in
    native) ;;
    universal) ZEN_BUILD_ARGS+=(--arch arm64 --arch x86_64) ;;
    *) printf '%s\n' 'ZEN_ARCH must be native or universal.' >&2; exit 1 ;;
esac
swift build "${ZEN_BUILD_ARGS[@]}" --product Zen
ZEN_BIN_DIR="$(swift build "${ZEN_BUILD_ARGS[@]}" --show-bin-path)"
ZEN_APP="${1:-$ZEN_ROOT/build/禅.app}"
mkdir -p "$ZEN_APP/Contents/MacOS" "$ZEN_APP/Contents/Resources"
cp -R "$ZEN_BIN_DIR/Zen_ZenUI.bundle" "$ZEN_APP/Contents/Resources/"
cp "$ZEN_BIN_DIR/Zen" "$ZEN_APP/Contents/MacOS/Zen"
cp "$ZEN_ROOT/Platform/macOS-Info.plist" "$ZEN_APP/Contents/Info.plist"
if [ -f "$ZEN_ROOT/Platform/Zen.icns" ]; then
    cp "$ZEN_ROOT/Platform/Zen.icns" "$ZEN_APP/Contents/Resources/Zen.icns"
fi
cp "$ZEN_ROOT/LICENSE" "$ZEN_APP/Contents/Resources/LICENSE.txt"
cp "$ZEN_ROOT/Sources/ZenUI/Resources/SOUND-CREDITS.txt" "$ZEN_APP/Contents/Resources/SOUND-CREDITS.txt"
# Ad-hoc signature only; this does not provide Developer ID signing or notarization.
codesign --force --sign - "$ZEN_APP"
codesign --verify --deep --strict "$ZEN_APP"
printf '%s\n' "$ZEN_APP"
