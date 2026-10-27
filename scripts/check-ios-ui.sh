#!/bin/bash
set -euo pipefail
ZEN_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ZEN_ROOT"
ZEN_RUNTIME="$(xcrun simctl list runtimes -j | python3 -c 'import json,sys; r=[x["identifier"] for x in json.load(sys.stdin)["runtimes"] if x.get("isAvailable") and x["identifier"].startswith("com.apple.CoreSimulator.SimRuntime.iOS-")]; print(r[-1] if r else "")')"
if [ -z "$ZEN_RUNTIME" ]; then
    echo 'Install the iOS Simulator runtime in Xcode Settings > Components first.' >&2
    exit 1
fi
# All fixtures and UI actions are confined to this new, disposable simulator.
ZEN_DEVICE="$(xcrun simctl create 'Zen UI Checks' com.apple.CoreSimulator.SimDeviceType.iPhone-17 "$ZEN_RUNTIME")"
cleanup() {
    xcrun simctl shutdown "$ZEN_DEVICE" >/dev/null 2>&1 || true
    xcrun simctl delete "$ZEN_DEVICE" >/dev/null 2>&1 || true
}
trap cleanup EXIT
xcrun simctl boot "$ZEN_DEVICE"
xcrun simctl bootstatus "$ZEN_DEVICE" -b
xcodebuild -project Zen.xcodeproj -scheme Zen-iOS -destination "platform=iOS Simulator,id=$ZEN_DEVICE" -derivedDataPath build/iOS-DerivedData build-for-testing
xcrun simctl install "$ZEN_DEVICE" build/iOS-DerivedData/Build/Products/Debug-iphonesimulator/Zen-iOS.app
ZEN_CONTAINER="$(xcrun simctl get_app_container "$ZEN_DEVICE" personal.zen.ios data)"
python3 - "$ZEN_CONTAINER" <<'PY'
import json, sys
from pathlib import Path
root = Path(sys.argv[1])
(root / 'Documents/ZenRecords').mkdir(parents=True, exist_ok=True)
support = root / 'Library/Application Support/Zen'
support.mkdir(parents=True, exist_ok=True)
preferences = dict(focusMinutes=1, restMinutes=1, sound='wood', volume=0.05, woodInterval=2,
                   soundDefaultsVersion=1, notificationEnabled=False, completionSound=False,
                   startKey=49, startModifiers=6144, abandonKey=53, abandonModifiers=6144)
(support / 'preferences.json').write_text(json.dumps(preferences))
PY
xcodebuild -project Zen.xcodeproj -scheme Zen-iOS -destination "platform=iOS Simulator,id=$ZEN_DEVICE" -derivedDataPath build/iOS-DerivedData -resultBundlePath "build/iOS-UI-$ZEN_DEVICE.xcresult" -parallel-testing-enabled NO test-without-building
# XCTest may reinstall the app and change its data-container UUID. Resolve it again.
ZEN_CONTAINER="$(xcrun simctl get_app_container "$ZEN_DEVICE" personal.zen.ios data)"
python3 - "$ZEN_CONTAINER" <<'PY'
import json, sys
from pathlib import Path
root = Path(sys.argv[1])
files = list((root / 'Documents').rglob('*.md'))
assert len(files) == 1, f'Expected only the completed session, found {len(files)} files'
content = files[0].read_text()
assert '- outcome: completed' in content and '- focused_seconds: 60' in content
assert 'Read one page.' in content
state = json.loads((root / 'Library/Application Support/Zen/recovery.json').read_text())
assert not state.get('active') and not state.get('drafts')
print('Verified actual iPhone record, full duration, saved annotation and cleared recovery')
PY
