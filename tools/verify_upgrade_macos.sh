#!/bin/bash
# Simulator binary replacement, NOT a physical iPad/Playgrounds container upgrade.
set -euo pipefail
cd "$(dirname "$0")/.."
root="$PWD"
baseline=24dc088fbeaf49b320beaf077815918f7424713d
folder="$root/.verification/upgrade"
mkdir -p "$folder/baseline"
git fetch --no-tags origin "$baseline" --depth=1
git archive "$baseline" | tar -x -C "$folder/baseline"
simulator_id="$(xcrun simctl list devices available --json | python3 -c 'import json,sys; print(next(d["udid"] for group in json.load(sys.stdin)["devices"].values() for d in group if d.get("isAvailable") and "iPad" in d["name"]))')"
xcrun simctl boot "$simulator_id" || true
xcrun simctl bootstatus "$simulator_id" -b
xcodebuild build -project "$folder/baseline/NeuralNotes.xcodeproj" -scheme NeuralNotes -configuration Debug -destination "platform=iOS Simulator,id=$simulator_id" -derivedDataPath "$folder/old" CODE_SIGNING_ALLOWED=NO
xcrun simctl install "$simulator_id" "$folder/old/Build/Products/Debug-iphonesimulator/NeuralNotes.app"
xcrun simctl launch --terminate-running-process "$simulator_id" com.neuralnotes.NeuralNotes --ui-testing --reset-ui-storage --ui-audio-fixture
container="$(xcrun simctl get_app_container "$simulator_id" com.neuralnotes.NeuralNotes data)"
ready=false
for attempt in {1..30}; do
  if python3 tools/check_upgrade_data.py "$container" --output "$folder/before.json"; then ready=true; break; fi
  sleep 1
done
[ "$ready" = true ]
xcrun simctl terminate "$simulator_id" com.neuralnotes.NeuralNotes
xcodebuild build -project NeuralNotes.xcodeproj -scheme NeuralNotes -configuration Debug -destination "platform=iOS Simulator,id=$simulator_id" -derivedDataPath "$folder/new" CODE_SIGNING_ALLOWED=NO
# Install over the same bundle, without uninstall/reset or a fixture launch flag.
xcrun simctl install "$simulator_id" "$folder/new/Build/Products/Debug-iphonesimulator/NeuralNotes.app"
xcrun simctl launch --terminate-running-process "$simulator_id" com.neuralnotes.NeuralNotes --ui-testing
sleep 3
container="$(xcrun simctl get_app_container "$simulator_id" com.neuralnotes.NeuralNotes data)"
python3 tools/check_upgrade_data.py "$container" --baseline "$folder/before.json" --output "$folder/after.json"
xcrun simctl spawn "$simulator_id" launchctl list | grep com.neuralnotes.NeuralNotes
printf '%s\n' 'UPGRADE_PASS: 0.20.8 to current binary; previous notebook/catalog retained, new app running'
