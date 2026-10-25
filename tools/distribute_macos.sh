#!/bin/bash
# App Store archive check by default. A real upload is explicit and needs secrets.
set -euo pipefail
umask 077
cd "$(dirname "$0")/.."
root="$PWD"
output="$root/.verification/distribution"
mkdir -p "$output"
upload="${NN_DELIVERY_UPLOAD:-0}"
[[ "$upload" = 0 || "$upload" = 1 ]]
# 1: production signing with the CloudKit container. 0: internal TestFlight beta without iCloud.
cloud="${NN_ICLOUD:-1}"
[[ "$cloud" = 0 || "$cloud" = 1 ]]
version="${NN_RELEASE_VERSION:-1.0.0}"
build="${NN_RELEASE_BUILD:-52}"
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]
[[ "$build" =~ ^[1-9][0-9]*$ ]]
sdk="$(xcrun --sdk iphoneos --show-sdk-version)"
[[ "${sdk%%.*}" -ge 26 ]] || { echo 'Distribution requires iOS SDK 26 or later.'; exit 1; }
xcodebuild -version
scratch="$(mktemp -d "${RUNNER_TEMP:-${TMPDIR:-/tmp}}/neuralnotes-signing.XXXXXX")"
keychain="$scratch/signing.keychain-db"
profile_path=""
cleanup() {
  if [ -f "$scratch/keychains.json" ]; then
    python3 - "$scratch/keychains.json" <<'PY'
import json, subprocess, sys
subprocess.run(['security', 'list-keychains', '-d', 'user', '-s', *json.load(open(sys.argv[1]))], check=False, stdout=subprocess.DEVNULL)
PY
  fi
  if [ -f "$keychain" ]; then security delete-keychain "$keychain" >/dev/null 2>&1 || true; fi
  if [ -n "$profile_path" ]; then rm -f "$profile_path"; fi
  # scratch is the exact directory returned by mktemp, never a user path.
  rm -rf "$scratch"
}
trap cleanup EXIT
signing=(CODE_SIGNING_ALLOWED=NO)
if [ "$upload" = 1 ]; then
  python3 - <<'PY'
import os, sys
required = ['NN_CERTIFICATE_P12_BASE64', 'NN_CERTIFICATE_PASSWORD', 'NN_PROFILE_BASE64',
            'NN_ASC_KEY_BASE64', 'NN_ASC_KEY_ID', 'NN_ASC_ISSUER_ID']
missing = [name for name in required if not os.environ.get(name)]
if missing:
    sys.exit('Missing GitHub distribution secrets: ' + ', '.join(missing))
PY
  export NN_SIGNING_SCRATCH="$scratch"
  python3 - <<'PY'
import base64, os
from pathlib import Path
folder = Path(os.environ['NN_SIGNING_SCRATCH'])
for name, filename in [('NN_CERTIFICATE_P12_BASE64','distribution.p12'),
                       ('NN_PROFILE_BASE64','distribution.mobileprovision'),
                       ('NN_ASC_KEY_BASE64','AuthKey.p8')]:
    (folder / filename).write_bytes(base64.b64decode(os.environ[name], validate=True))
PY
  security cms -D -i "$scratch/distribution.mobileprovision" > "$scratch/profile.plist"
  if [ "$cloud" = 1 ]; then profile_uuid="$(python3 tools/validate_distribution_profile.py "$scratch/profile.plist")"
  else profile_uuid="$(python3 tools/validate_distribution_profile.py --no-cloud "$scratch/profile.plist")"; fi
  profile_folder="$HOME/Library/MobileDevice/Provisioning Profiles"
  mkdir -p "$profile_folder"
  candidate_profile="$profile_folder/$profile_uuid.mobileprovision"
  # Do not overwrite a pre-existing profile on a developer's machine.
  [ ! -e "$candidate_profile" ] || { echo 'Profile already installed; use an isolated CI runner.'; exit 1; }
  profile_path="$candidate_profile"
  cp "$scratch/distribution.mobileprovision" "$profile_path"
  keychain_password="$(openssl rand -hex 24)"
  security create-keychain -p "$keychain_password" "$keychain"
  security set-keychain-settings -lut 21600 "$keychain"
  security unlock-keychain -p "$keychain_password" "$keychain"
  python3 - "$scratch/keychains.json" "$keychain" <<'PY'
import json, shlex, subprocess, sys
from pathlib import Path
previous = shlex.split(subprocess.check_output(['security','list-keychains','-d','user'], text=True))
Path(sys.argv[1]).write_text(json.dumps(previous), encoding='utf-8')
subprocess.run(['security','list-keychains','-d','user','-s',sys.argv[2],*previous], check=True)
PY
  security import "$scratch/distribution.p12" -k "$keychain" -P "$NN_CERTIFICATE_PASSWORD" -T /usr/bin/codesign -T /usr/bin/security >/dev/null
  security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$keychain_password" "$keychain" >/dev/null
  if [ "$cloud" = 1 ]; then
    python3 - "$scratch/production.entitlements" <<'PY'
import plistlib, sys
from pathlib import Path
value = plistlib.loads(Path('NeuralNotes/Resources/NeuralNotes.entitlements').read_bytes())
value['com.apple.developer.icloud-container-environment'] = 'Production'
Path(sys.argv[1]).write_bytes(plistlib.dumps(value))
PY
    signing=(CODE_SIGNING_ALLOWED=YES CODE_SIGN_STYLE=Manual 'CODE_SIGN_IDENTITY=Apple Distribution'
      "PROVISIONING_PROFILE_SPECIFIER=$profile_uuid" 'DEVELOPMENT_TEAM=64R668842U'
      "CODE_SIGN_ENTITLEMENTS=$scratch/production.entitlements"
      "OTHER_CODE_SIGN_FLAGS=--keychain $keychain")
  else
    # Internal beta: no iCloud container entitlement, and the app keeps iCloud sync
    # switched off. Both files live in the temporary folder, never in the checkout.
    python3 - "$scratch/beta.entitlements" "$scratch/Info.plist" <<'PY'
import plistlib, sys
from pathlib import Path
Path(sys.argv[1]).write_bytes(plistlib.dumps({}))
info = plistlib.loads(Path('NeuralNotes/Resources/Info.plist').read_bytes())
info['NNCloudSigned'] = False
Path(sys.argv[2]).write_bytes(plistlib.dumps(info))
PY
    signing=(CODE_SIGNING_ALLOWED=YES CODE_SIGN_STYLE=Manual 'CODE_SIGN_IDENTITY=Apple Distribution'
      "PROVISIONING_PROFILE_SPECIFIER=$profile_uuid" 'DEVELOPMENT_TEAM=64R668842U'
      "CODE_SIGN_ENTITLEMENTS=$scratch/beta.entitlements" "INFOPLIST_FILE=$scratch/Info.plist"
      "OTHER_CODE_SIGN_FLAGS=--keychain $keychain")
  fi
fi
archive="$output/NeuralNotes.xcarchive"
[ ! -e "$archive" ] || { echo 'Archive already exists; use a fresh CI checkout.'; exit 1; }
xcodebuild archive -project NeuralNotes.xcodeproj -scheme NeuralNotes -configuration Release \
  -destination 'generic/platform=iOS' -archivePath "$archive" \
  -derivedDataPath "$output/DerivedData" \
  "MARKETING_VERSION=$version" "CURRENT_PROJECT_VERSION=$build" "${signing[@]}"
python3 tools/release_readiness.py --archive "$archive" --report "$output/archive-proof.json"
if [ "$upload" = 1 ]; then
  codesign --verify --deep --strict "$archive/Products/Applications/NeuralNotes.app"
  python3 - "$scratch/export.plist" "$profile_uuid" <<'PY'
import plistlib, sys
from pathlib import Path
Path(sys.argv[1]).write_bytes(plistlib.dumps({
    'method': 'app-store-connect', 'destination': 'upload', 'teamID': '64R668842U',
    'signingStyle': 'manual', 'signingCertificate': 'Apple Distribution',
    'provisioningProfiles': {'com.lorenzominichilli.neuralnotes': sys.argv[2]},
    'manageAppVersionAndBuildNumber': False, 'uploadSymbols': True,
}))
PY
  xcodebuild -exportArchive -archivePath "$archive" -exportOptionsPlist "$scratch/export.plist" \
    -exportPath "$scratch/export" -authenticationKeyPath "$scratch/AuthKey.p8" \
    -authenticationKeyID "$NN_ASC_KEY_ID" -authenticationKeyIssuerID "$NN_ASC_ISSUER_ID"
  if [ "$cloud" = 0 ]; then echo 'Internal TestFlight beta: iCloud sync is not included in this build.'; fi
  echo 'UPLOAD_COMMAND_SUCCEEDED: Apple processing and TestFlight availability still need confirmation.'
else
  echo 'ARCHIVE_VALIDATED_UNSIGNED: no signing, upload, TestFlight release or App Review submission performed.'
fi
