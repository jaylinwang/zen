#!/bin/bash
set -euo pipefail
ZEN_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ZEN_ROOT"
swift run ZenCoreChecks
swift run ZenChecks "$@"
swift run ZenChecks --verify-navigation
swift build --product Zen
plutil -lint Platform/macOS-Info.plist Platform/iOS-Info.plist Platform/macOS.entitlements Zen.xcodeproj/project.pbxproj
