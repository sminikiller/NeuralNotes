import datetime
import plistlib
import tempfile
import unittest
from pathlib import Path
from release_readiness import ATTESTATIONS, SIGNING_SECRETS, archive_proof, beta_problems, configuration_problems, public_https
from validate_distribution_profile import validate


class ReleaseReadinessTests(unittest.TestCase):
    def test_unconfigured_release_is_blocked_without_secret_values(self):
        errors = configuration_problems({}, "a" * 40)
        self.assertIn("Missing or invalid public HTTPS gateway_origin", errors)
        self.assertEqual(len([e for e in errors if e.startswith("Acceptance still open:")]), len(ATTESTATIONS))

    def test_acceptance_is_bound_to_the_exact_source(self):
        config = dict(gateway_origin="https://gateway.neuralnotes.it", privacy_url="https://legal.neuralnotes.it/privacy",
                      support_url="https://legal.neuralnotes.it/support", operator_name="Fixture only",
                      support_email="support@neuralnotes.it", acceptance_source_sha="a" * 40,
                      acceptance=dict.fromkeys(ATTESTATIONS, True))
        self.assertEqual(configuration_problems(config, "a" * 40), [])
        self.assertIn("Acceptance evidence must identify the exact source commit", configuration_problems(config, "b" * 40))
        config["acceptance"]["physical_ipad"] = "true"
        self.assertIn("Acceptance still open: physical_ipad", configuration_problems(config, "a" * 40))

    def test_private_placeholder_and_credential_urls_are_rejected(self):
        for url in ("http://host.test", "https://127.0.0.1", "https://192.168.1.5", "https://localhost", "https://x.invalid",
                    "https://example.com", "https://user:secret@host.test", "https://host.test?key=secret", "https://[::1]"):
            self.assertFalse(public_https(url), url)

    def profile(self):
        return {"UUID": "00000000-0000-4000-8000-000000000001", "TeamIdentifier": ["64R668842U"],
                "ExpirationDate": datetime.datetime(2030, 1, 1), "DeveloperCertificates": [b"synthetic-not-a-certificate"],
                "Entitlements": {"application-identifier": "64R668842U.com.neuralnotes.NeuralNotes", "get-task-allow": False,
                    "com.apple.developer.icloud-container-identifiers": ["iCloud.com.neuralnotes.NeuralNotes"],
                    "com.apple.developer.icloud-services": ["CloudKit"], "com.apple.developer.icloud-container-environment": "Production"}}

    def test_archive_metadata_rejects_missing_api_reasons_and_obsolete_sdk(self):
        with tempfile.TemporaryDirectory() as directory:
            app = Path(directory) / "Products/Applications/NeuralNotes.app"; app.mkdir(parents=True)
            info = {"DTSDKName": "iphoneos26.5", "CFBundleIdentifier": "com.neuralnotes.NeuralNotes",
                    "CFBundleExecutable": "NeuralNotes", "CFBundleShortVersionString": "1.0.0", "CFBundleVersion": "1",
                    "CFBundleIcons~ipad": {"CFBundlePrimaryIcon": {"CFBundleIconName": "AppIcon"}}}
            (app / "Info.plist").write_bytes(plistlib.dumps(info))
            (app / "NeuralNotes").write_bytes(b"metadata-fixture-not-a-compiled-binary")
            (app / "Assets.car").write_bytes(b"metadata-fixture-not-an-asset-catalog")
            (app / "PrivacyInfo.xcprivacy").write_bytes(plistlib.dumps({}))
            with self.assertRaisesRegex(ValueError, "required API reason"): archive_proof(directory)
            manifest = Path(__file__).resolve().parents[1] / "NeuralNotes/Resources/PrivacyInfo.xcprivacy"
            (app / "PrivacyInfo.xcprivacy").write_bytes(manifest.read_bytes())
            self.assertEqual(len(archive_proof(directory)["requiredReasonCategories"]), 4)
            info["DTSDKName"] = "iphoneos18.5"
            (app / "Info.plist").write_bytes(plistlib.dumps(info))
            with self.assertRaisesRegex(ValueError, "SDK 26"): archive_proof(directory)

    def test_profile_metadata_requires_distribution_and_matching_cloud_entitlements(self):
        self.assertEqual(validate(self.profile()), "00000000-0000-4000-8000-000000000001")
        for field, value in (("TeamIdentifier", ["OTHERTEAM00"]), ("ProvisionedDevices", ["fixture-device"]),
                             ("ExpirationDate", datetime.datetime(2000, 1, 1))):
            profile = self.profile(); profile[field] = value
            with self.assertRaises(ValueError): validate(profile)
        profile = self.profile(); profile["Entitlements"]["get-task-allow"] = True
        with self.assertRaises(ValueError): validate(profile)
        profile = self.profile(); profile["Entitlements"]["com.apple.developer.icloud-container-environment"] = "Development"
        with self.assertRaises(ValueError): validate(profile)

    def test_internal_beta_needs_signing_secrets_but_not_public_services_or_acceptance(self):
        missing = beta_problems({})
        self.assertEqual(missing, ["Missing GitHub distribution secret: " + name for name in SIGNING_SECRETS])
        self.assertEqual(beta_problems(dict.fromkeys(SIGNING_SECRETS, "fixture-not-a-secret")), [])
        # The production path keeps every public-service and physical-acceptance requirement.
        self.assertIn("Acceptance still open: physical_ipad", configuration_problems({}, "a" * 40))

    def test_beta_profile_may_omit_the_icloud_container_but_not_distribution_checks(self):
        profile = self.profile()
        profile["Entitlements"] = {"application-identifier": "64R668842U.com.neuralnotes.NeuralNotes", "get-task-allow": False}
        with self.assertRaisesRegex(ValueError, "iCloud container"): validate(profile)
        self.assertEqual(validate(profile, require_cloud=False), "00000000-0000-4000-8000-000000000001")
        profile["ProvisionedDevices"] = ["fixture-device"]
        with self.assertRaises(ValueError): validate(profile, require_cloud=False)


if __name__ == "__main__":
    unittest.main()
