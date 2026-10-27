#!/bin/bash
set -euo pipefail
ZEN_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ZEN_ROOT"
if ! xcodebuild -version; then
    printf '%s\n' 'iPhone verification requires full Xcode and the iOS Simulator SDK.' >&2
    exit 1
fi
# Building the simulator target only needs its SDK; a runtime is needed to launch or test it.
xcodebuild -project Zen.xcodeproj -target Zen-iOS -configuration Debug -sdk iphonesimulator ARCHS="$(uname -m)" ONLY_ACTIVE_ARCH=YES CODE_SIGNING_ALLOWED=NO build
python3 - <<'PYVERIFY'
from pathlib import Path
import plistlib
app = Path('build/Debug-iphonesimulator/Zen-iOS.app')
with (app / 'Info.plist').open('rb') as f:
    info = plistlib.load(f)
assert 'audio' in info.get('UIBackgroundModes', []), 'Background audio mode missing'
assert info.get('UIFileSharingEnabled') is True, 'Files app visibility missing'
assert info.get('LSSupportsOpeningDocumentsInPlace') is True, 'In-place file access missing'
for name in ['mokugyo', 'qing', 'pine', 'rain']:
    assert (app / f'Zen_ZenUI.bundle/{name}.wav').is_file(), f'{name} recording missing'
print('iPhone app configuration and bundled recording verified')
PYVERIFY
