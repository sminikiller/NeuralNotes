#!/bin/bash
# Build the ZIP's AppleProductTypes manifest, targets and resources, not the
# separate .xcodeproj. This is an Xcode build, not execution of iPad Playgrounds.
set -euo pipefail
cd "$(dirname "$0")/.."
task_root="$PWD"
configuration="${NEURALNOTES_PLAYGROUND_CONFIGURATION:-Debug}"
case "$configuration" in Debug|Release) ;; *) echo "Unsupported configuration: $configuration"; exit 1;; esac
command -v xcodebuild >/dev/null
xcodebuild -version
xcrun swift --version
python3 tools/package_ipad.py
playground_dir="$(python3 - <<'PY'
import tempfile
import zipfile
from pathlib import Path
from tools.package_ipad import ARCHIVE, ROOT
destination = Path(tempfile.mkdtemp(prefix='playground-build-', dir=ROOT / '.verification'))
with zipfile.ZipFile(ARCHIVE) as archive:
    archive.extractall(destination)
print(destination / 'NeuralNotes.swiftpm')
PY
)"
cd "$playground_dir"
# xcodebuild recognizes an App Playground when the containing directory keeps
# its .swiftpm extension. The CLI swift build lacks AppleProductTypes.
xcodebuild -list -json > "$task_root/.verification/playground-schemes.json"
scheme="$(python3 - "$task_root/.verification/playground-schemes.json" <<'PY'
import json
import sys
data = json.load(open(sys.argv[1]))
schemes = data.get('workspace', data.get('project', {})).get('schemes', [])
for preferred in ['NeuralNotes', 'AppModule']:
    if preferred in schemes:
        print(preferred)
        break
else:
    sys.exit(f'App Playground scheme missing: {schemes}')
PY
)"
echo "Building App Playground scheme: $scheme ($configuration)"
xcodebuild build -scheme "$scheme" -configuration "$configuration" \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath "$task_root/.verification/playground-derived-data" \
  CODE_SIGNING_ALLOWED=NO \
  'OTHER_SWIFT_FLAGS=$(inherited) -Xfrontend -warn-long-expression-type-checking=500 -Xfrontend -warn-long-function-bodies=1000'
echo "Building the same extracted App Playground for an iOS device (unsigned)."
xcodebuild build -scheme "$scheme" -configuration "$configuration" \
  -destination 'generic/platform=iOS' \
  -derivedDataPath "$task_root/.verification/playground-derived-data" \
  CODE_SIGNING_ALLOWED=NO \
  'OTHER_SWIFT_FLAGS=$(inherited) -Xfrontend -warn-long-expression-type-checking=500 -Xfrontend -warn-long-function-bodies=1000'
echo "App Playground package built with Xcode for simulator and iOS device. Compilation inside iPad Playgrounds still requires verification."
if [ "${NEURALNOTES_PLAYGROUND_SMOKE:-0}" = 1 ]; then
  bash "$task_root/tools/verify_playground_launch_macos.sh" "$task_root"
fi
