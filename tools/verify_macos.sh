#!/bin/bash
# Run on a Mac with full Xcode selected and an installed iPad simulator runtime.
set -euo pipefail
cd "$(dirname "$0")/.."
command -v xcodebuild >/dev/null
command -v python3 >/dev/null
xcodebuild -version
xcrun swift --version
xcodebuild -showsdks
python3 tools/check_project.py
verification_status=0
swift test || verification_status=1

simulator_id="${NEURALNOTES_SIMULATOR_ID:-}"
if [ -z "$simulator_id" ]; then
  simulator_id="$(xcrun simctl list devices available --json | python3 -c '
import json, sys
devices = [d for group in json.load(sys.stdin)["devices"].values() for d in group
           if d.get("isAvailable") and "iPad" in d["name"]]
devices.sort(key=lambda d: d.get("state") != "Booted")
if not devices:
    sys.exit("Install an iPad simulator runtime in Xcode, or set NEURALNOTES_SIMULATOR_ID.")
print(devices[0]["udid"])
')"
fi
result_dir=".verification/$(date +%Y%m%d-%H%M%S)-$$"
mkdir -p "$result_dir"
test_selection=()
if [ "${NEURALNOTES_FOCUSED_TESTS:-0}" = 1 ]; then
  test_selection=(-only-testing:NeuralNotesTests/EditorReliabilityTests -only-testing:NeuralNotesUITests/AudioActionsUITests)
fi
xcodebuild test -project NeuralNotes.xcodeproj -scheme NeuralNotes \
  -destination "platform=iOS Simulator,id=$simulator_id" \
  -derivedDataPath DerivedData \
  -resultBundlePath "$result_dir/NeuralNotes.xcresult" \
  "${test_selection[@]}" CODE_SIGNING_ALLOWED=NO || verification_status=1
xcodebuild build -project NeuralNotes.xcodeproj -scheme NeuralNotes \
  -configuration Release -destination 'generic/platform=iOS' \
  -derivedDataPath DerivedData CODE_SIGNING_ALLOWED=NO || verification_status=1
if [ "$verification_status" -ne 0 ]; then
  echo "Apple verification failed; inspect the logs for each phase."
  exit "$verification_status"
fi
echo "Mac build and tests passed. Device acceptance still required: docs/ACCEPTANCE.md"
