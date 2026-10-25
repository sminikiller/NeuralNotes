import copy
import datetime
import unittest
from release_readiness import ATTESTATIONS, configuration_problems, public_https
from validate_distribution_profile import validate


class ReleaseReadinessTests(unittest.TestCase):
    def test_unconfigured_release_is_blocked_without_secret_values(self):
        errors = configuration_problems({}, "a" * 40)
        self.assertIn("Missing or invalid public HTTPS gateway_origin", errors)
        self.assertEqual(len([e for e in errors if e.startswith("Acceptance still open:")]), len(ATTESTATIONS))

    def test_acceptance_is_bound_to_the_exact_source(self):
        config = dict(gateway_origin="https://gateway.neuralnotes.test", privacy_url="https://legal.neuralnotes.test/privacy",
                      support_url="https://legal.neuralnotes.test/support", operator_name="Fixture only",
                      support_email="support@neuralnotes.test", acceptance_source_sha="a" * 40,
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


if __name__ == "__main__":
    unittest.main()
