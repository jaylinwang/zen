#!/bin/bash
set -euo pipefail
ZEN_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ZEN_ROOT"
ZEN_VERSION=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' Platform/macOS-Info.plist)
if [[ ! "$ZEN_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    printf '%s\n' 'Expected a numeric X.Y.Z version in macOS-Info.plist.' >&2
    exit 1
fi
ZEN_WORK=$(mktemp -d "${TMPDIR:-/tmp}/zen-dmg.XXXXXX")
ZEN_MOUNT="$ZEN_WORK/mounted"
cleanup() {
    if mount | grep -Fq " on $ZEN_MOUNT "; then
        hdiutil detach "$ZEN_MOUNT" -quiet || true
    fi
    rm -rf "$ZEN_WORK"
}
trap cleanup EXIT
mkdir -p "$ZEN_WORK/image" "$ZEN_ROOT/dist"
ZEN_APP="$ZEN_WORK/image/禅.app"
ZEN_ARCH=universal "$ZEN_ROOT/scripts/build-mac.sh" "$ZEN_APP"
lipo "$ZEN_APP/Contents/MacOS/Zen" -verify_arch arm64 x86_64
for ZEN_RESOURCE in mokugyo.wav qing.wav pine.wav rain.wav SOUND-CREDITS.txt; do
    test -f "$ZEN_APP/Contents/Resources/Zen_ZenUI.bundle/$ZEN_RESOURCE" ||
        test -f "$ZEN_APP/Contents/Resources/Zen_ZenUI.bundle/Contents/Resources/$ZEN_RESOURCE"
done
ln -s /Applications "$ZEN_WORK/image/Applications"
cp LICENSE "$ZEN_WORK/image/LICENSE.txt"
cp Sources/ZenUI/Resources/SOUND-CREDITS.txt "$ZEN_WORK/image/SOUND-CREDITS.txt"
cat > "$ZEN_WORK/image/安装说明.txt" <<'INSTALL'
将「禅.app」拖入 Applications，然后从「应用程序」打开。
macOS 13+；支持 Apple Silicon 和 Intel。
首次运行后，在设置中选择记录文件夹。

此版本为开源社区构建，使用临时签名，尚未经过 Apple 公证。
若被系统拦截，确认来源后参考 Apple 官方说明：
https://support.apple.com/zh-cn/102445

项目与反馈：https://github.com/jaylinwang/zen
代码采用 MIT，录音采用 CC0；详见随附 LICENSE.txt 和 SOUND-CREDITS.txt。
INSTALL
ZEN_DMG="$ZEN_ROOT/dist/Zen-$ZEN_VERSION-macOS-universal.dmg"
hdiutil create -volname "Zen $ZEN_VERSION" -srcfolder "$ZEN_WORK/image" -ov -format UDZO "$ZEN_DMG"
hdiutil verify "$ZEN_DMG"
hdiutil attach "$ZEN_DMG" -nobrowse -readonly -mountpoint "$ZEN_MOUNT"
codesign --verify --deep --strict "$ZEN_MOUNT/禅.app"
lipo "$ZEN_MOUNT/禅.app/Contents/MacOS/Zen" -verify_arch arm64 x86_64
test "$(readlink "$ZEN_MOUNT/Applications")" = /Applications
test -s "$ZEN_MOUNT/禅.app/Contents/Resources/LICENSE.txt"
test "$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$ZEN_MOUNT/禅.app/Contents/Info.plist")" = "$ZEN_VERSION"
hdiutil detach "$ZEN_MOUNT" -quiet
(cd "$ZEN_ROOT/dist" && shasum -a 256 "$(basename "$ZEN_DMG")" > SHA256SUMS.txt && shasum -a 256 -c SHA256SUMS.txt)
printf 'Verified DMG: %s\n' "$ZEN_DMG"
