#!/bin/bash
# Launch the real SwiftPM app, rather than the separate Xcode app/test target.
set -euo pipefail
task_root="${1:?Pass the repository root}"
evidence="$task_root/.verification/playground-launch"
mkdir -p "$evidence"
products="$task_root/.verification/playground-derived-data/Build/Products/Debug-iphonesimulator"
app="$(python3 - "$products" <<'PY'
from pathlib import Path
import sys
apps = list(Path(sys.argv[1]).glob('*.app'))
if len(apps) != 1:
    sys.exit(f'Expected one App Playground app, found {apps}')
print(apps[0])
PY
)"
bundle_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$app/Info.plist")"
simulator_id="$(xcrun simctl list devices available --json | python3 -c '
import json, sys
groups = json.load(sys.stdin)["devices"]
preferred = [d for runtime, group in groups.items() if "iOS-18-5" in runtime for d in group
             if d.get("isAvailable") and "iPad" in d["name"]]
devices = preferred or [d for group in groups.values() for d in group
                       if d.get("isAvailable") and "iPad" in d["name"]]
devices.sort(key=lambda d: ("10th generation" not in d["name"], d.get("state") != "Booted"))
if not devices:
    sys.exit("No available iPad simulator")
print(devices[0]["udid"])
')"
echo "App Playground launch: bundle=$bundle_id simulator=$simulator_id"
xcrun simctl boot "$simulator_id" || true
xcrun simctl bootstatus "$simulator_id" -b
xcrun simctl install "$simulator_id" "$app"
status=0
launch="$(xcrun simctl launch --terminate-running-process \
  --stdout="$evidence/stdout.log" --stderr="$evidence/stderr.log" \
  "$simulator_id" "$bundle_id" 2>&1)" || status=$?
printf '%s\n' "$launch" | tee "$evidence/launch.log"
pid="${launch##*: }"
if [ "$status" = 0 ]; then
  if [[ "$pid" =~ ^[0-9]+$ ]]; then
    for second in {1..20}; do
      if ! kill -0 "$pid" 2>/dev/null; then
        echo "App Playground exited during the launch check at second $second."
        status=1
        break
      fi
      sleep 1
    done
  else
    echo "Could not identify the App Playground process."
    status=1
  fi
fi
xcrun simctl io "$simulator_id" screenshot "$evidence/screen.png" || status=1
xcrun simctl spawn "$simulator_id" log show --last 2m --style compact \
  --predicate 'process == "NeuralNotes"' > "$evidence/system.log" 2>&1 || true
python3 - "$evidence" "$bundle_id" "$simulator_id" "$pid" "$status" <<'PY'
import json, pathlib, sys
path, bundle, simulator, pid, status = sys.argv[1:]
proof = dict(bundle=bundle, simulator=simulator, pid=pid, survived_20_seconds=status == '0',
             application_source='App Playground ZIP', physical_iPad=False)
(pathlib.Path(path) / 'result.json').write_text(json.dumps(proof, indent=2) + '\n')
PY
if [ "$status" != 0 ]; then
  echo "App Playground launch failed; inspect the preserved logs and screenshot."
  exit "$status"
fi
echo "App Playground launch PASS: process survived 20 seconds; inspect screen.png for the actual scene."
