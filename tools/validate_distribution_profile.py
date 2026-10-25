"""Validate decoded App Store profile; print its UUID only, never certificate data."""
import datetime
import plistlib
import sys
import uuid
from pathlib import Path

TEAM = "64R668842U"
BUNDLE = "com.neuralnotes.NeuralNotes"
CONTAINER = "iCloud.com.neuralnotes.NeuralNotes"


def validate(profile, now=None, require_cloud=True):
    """require_cloud=False is the internal TestFlight beta, signed without the iCloud container."""
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
    if require_cloud and CONTAINER not in entitlements.get("com.apple.developer.icloud-container-identifiers", []):
        raise ValueError("Profile does not grant the NeuralNotes iCloud container.")
    if require_cloud and "CloudKit" not in entitlements.get("com.apple.developer.icloud-services", []):
        raise ValueError("Profile does not enable CloudKit.")
    if require_cloud and entitlements.get("com.apple.developer.icloud-container-environment") != "Production":
        raise ValueError("Distribution requires the production CloudKit environment.")
    return str(uuid.UUID(profile["UUID"])).upper()


if __name__ == "__main__":
    try:
        arguments = sys.argv[1:]
        require_cloud = "--no-cloud" not in arguments
        paths = [argument for argument in arguments if argument != "--no-cloud"]
        print(validate(plistlib.loads(Path(paths[0]).read_bytes()), require_cloud=require_cloud))
    except (ValueError, KeyError, IndexError, plistlib.InvalidFileException) as error:
        sys.exit(str(error))
