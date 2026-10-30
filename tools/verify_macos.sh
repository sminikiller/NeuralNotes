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
if [ "${NEURALNOTES_UI_ONLY:-0}" != 1 ] && [ "${NEURALNOTES_NATIVE_ONLY:-0}" != 1 ] && [ "${NEURALNOTES_CORE_VALIDATED:-0}" != 1 ]; then
  swift test || verification_status=1
fi

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
# macOS ships Bash 3.2: an empty array expanded under `set -u` aborts the
# full suite before xcodebuild. Keep the command array nonempty in every scope.
# UI tests also share simulator preferences, so run them serially.
test_selection=(-parallel-testing-enabled NO)
append_ui_tests() {
  local ui_case
  local ui_cases=()
  IFS=',' read -r -a ui_cases <<< "$NEURALNOTES_UI_TEST"
  for ui_case in "${ui_cases[@]}"; do
    [[ "$ui_case" =~ ^[A-Za-z_][A-Za-z0-9_]*/test[A-Za-z0-9_]+$ ]]
    test_selection+=("-only-testing:NeuralNotesUITests/$ui_case")
  done
}
if [ "${NEURALNOTES_FOCUSED_TESTS:-0}" = 1 ]; then
  test_selection+=(-only-testing:NeuralNotesTests/EditorReliabilityTests -only-testing:NeuralNotesTests/EditorIntegrationTests -only-testing:NeuralNotesTests/AudioTranscriptionTests -only-testing:NeuralNotesTests/AudioCompressionTests -only-testing:NeuralNotesTests/EditorContentTests -only-testing:NeuralNotesTests/AccountNotebookSyncTests -only-testing:NeuralNotesTests/PhotoPerspectiveTests -only-testing:NeuralNotesTests/ShapeEditorTests -only-testing:NeuralNotesTests/SelectionAlignmentTests -only-testing:NeuralNotesTests/DiagramEditingTests -only-testing:NeuralNotesTests/DiagramCompatibilityTests -only-testing:NeuralNotesTests/MarkerAndRecognitionTests -only-testing:NeuralNotesTests/MarkerRenderingTests -only-testing:NeuralNotesTests/ProtractorIntegrationTests -only-testing:NeuralNotesTests/DiskEditorHistoryTests -only-testing:NeuralNotesTests/WordIndexInvalidationTests)
  if [ -n "${NEURALNOTES_UI_TEST:-}" ]; then append_ui_tests
  else test_selection+=(-only-testing:NeuralNotesUITests/AudioActionsUITests -only-testing:NeuralNotesUITests/EditorQuickActionsUITests); fi
fi
if [ "${NEURALNOTES_UI_ONLY:-0}" = 1 ]; then
  if [ -n "${NEURALNOTES_UI_TEST:-}" ]; then
    append_ui_tests
  else
    test_selection+=(-only-testing:NeuralNotesUITests/AudioActionsUITests -only-testing:NeuralNotesUITests/EditorQuickActionsUITests)
  fi
  echo "UI-only follow-up: Core/native/Release/package evidence must come from the same application sources."
fi
if [ "${NEURALNOTES_NATIVE_ONLY:-0}" = 1 ]; then
  [ -n "${NEURALNOTES_NATIVE_TEST:-}" ]
  IFS=',' read -r -a native_cases <<< "$NEURALNOTES_NATIVE_TEST"
  for native_case in "${native_cases[@]}"; do
    [[ "$native_case" =~ ^[A-Za-z_][A-Za-z0-9_]*/test[A-Za-z0-9_]+$ ]]
    test_selection+=("-only-testing:NeuralNotesTests/$native_case")
  done
  echo "Native-only follow-up: unchanged application sources are required by the workflow guard."
fi
xcodebuild test -project NeuralNotes.xcodeproj -scheme NeuralNotes \
  -destination "platform=iOS Simulator,id=$simulator_id" \
  -derivedDataPath DerivedData \
  -resultBundlePath "$result_dir/NeuralNotes.xcresult" \
  "${test_selection[@]}" CODE_SIGNING_ALLOWED=NO || verification_status=1
if [ -d "$result_dir/NeuralNotes.xcresult" ]; then
  # Keep screenshots viewable outside macOS as well as the original result bundle.
  # This optional export never changes the test outcome.
  xcrun xcresulttool export attachments --path "$result_dir/NeuralNotes.xcresult" \
    --output-path "$result_dir/screenshots" || echo "Screenshot export unavailable; original xcresult retained."
fi
if [ "${NEURALNOTES_UI_ONLY:-0}" != 1 ] && [ "${NEURALNOTES_NATIVE_ONLY:-0}" != 1 ]; then
  xcodebuild build -project NeuralNotes.xcodeproj -scheme NeuralNotes \
    -configuration Release -destination 'generic/platform=iOS' \
    -derivedDataPath DerivedData CODE_SIGNING_ALLOWED=NO || verification_status=1
fi
if [ "$verification_status" -ne 0 ]; then
  echo "Apple verification failed; inspect the logs for each phase."
  exit "$verification_status"
fi
echo "Mac build and tests passed. Device acceptance still required: docs/ACCEPTANCE.md"
