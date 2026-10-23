#!/bin/bash
# Build the ZIP's AppleProductTypes manifest, targets and resources, not the
# separate .xcodeproj. This is an Xcode build, not execution of iPad Playgrounds.
set -euo pipefail
cd "$(dirname "$0")/.."
task_root="$PWD"
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
echo "Building App Playground scheme: $scheme"
xcodebuild build -scheme "$scheme" -configuration Debug \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath "$task_root/.verification/playground-derived-data" \
  CODE_SIGNING_ALLOWED=NO \
  'OTHER_SWIFT_FLAGS=$(inherited) -Xfrontend -warn-long-expression-type-checking=500 -Xfrontend -warn-long-function-bodies=1000'
echo "App Playground package built with Xcode. Physical iPad compilation still requires verification."
