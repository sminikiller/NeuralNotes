"""Validate decoded App Store profile; print its UUID only, never certificate data."""
import datetime
import plistlib
import sys
import uuid
from pathlib import Path

TEAM = "64R668842U"
BUNDLE = "com.neuralnotes.NeuralNotes"
CONTAINER = "iCloud.com.neuralnotes.NeuralNotes"


def validate(profile, now=None):
    now = now or datetime.datetime.now(datetime.timezone.utc)
    entitlements = profile.get("Entitlements", {})
    if profile.get("TeamIdentifier") != [TEAM]:
        raise ValueError("Profile belongs to a different Apple team.")
    if entitlements.get("application-identifier") != TEAM + "." + BUNDLE:
        raise ValueError("Profile does not match the explicit NeuralNotes App ID.")
    if entitlements.get("get-task-allow") is not False or profile.get("ProvisionedDevices") or profile.get("ProvisionsAllDevices"):
        raise ValueError("Use an App Store Connect distribution profile, not development/ad hoc/enterprise.")
    expires = profile.get("ExpirationDate")
    if not isinstance(expires, datetime.datetime) or expires.replace(tzinfo=datetime.timezone.utc) <= now:
        raise ValueError("Profile is expired or has no valid expiry.")
    if not profile.get("DeveloperCertificates"):
        raise ValueError("Profile contains no distribution certificate.")
    if CONTAINER not in entitlements.get("com.apple.developer.icloud-container-identifiers", []):
        raise ValueError("Profile does not grant the NeuralNotes iCloud container.")
    if "CloudKit" not in entitlements.get("com.apple.developer.icloud-services", []):
        raise ValueError("Profile does not enable CloudKit.")
    if entitlements.get("com.apple.developer.icloud-container-environment") != "Production":
        raise ValueError("Distribution requires the production CloudKit environment.")
    return str(uuid.UUID(profile["UUID"])).upper()


if __name__ == "__main__":
    try:
        print(validate(plistlib.loads(Path(sys.argv[1]).read_bytes())))
    except (ValueError, KeyError, IndexError, plistlib.InvalidFileException) as error:
        sys.exit(str(error))
