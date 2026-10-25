"""Fail closed before a production upload; never read or display secret values."""
import argparse
import ipaddress
import json
import os
import plistlib
import re
import subprocess
import sys
import urllib.parse
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
ATTESTATIONS = (
    "physical_ipad", "long_audio_and_standby", "camera_and_pencil", "upgrade_keeps_notebooks",
    "live_ai", "smtp_delivery", "cloud_two_accounts", "account_deletion", "icloud_production", "privacy_review",
)


def public_https(value):
    try:
        url = urllib.parse.urlsplit(value)
        host = url.hostname or ""
        if url.scheme != "https" or url.username or url.password or url.fragment or url.query:
            return False
        if "." not in host or host.endswith((".invalid", ".example", ".localhost", ".local")) or host in ("example.com", "example.org", "example.net"):
            return False
        try:
            if not ipaddress.ip_address(host).is_global:
                return False
        except ValueError:
            pass
        return True
    except (ValueError, TypeError):
        return False


def configuration_problems(config, source_sha):
    problems = []
    for key in ("gateway_origin", "privacy_url", "support_url"):
        if not public_https(config.get(key, "")):
            problems.append("Missing or invalid public HTTPS " + key)
    if not config.get("operator_name", "").strip():
        problems.append("Missing operator_name for the privacy notice")
    email = config.get("support_email", "")
    if not re.fullmatch(r"[^\s@]+@[^\s@]+\.[^\s@]+", email) or email.endswith((".invalid", ".example")):
        problems.append("Missing support_email")
    if not source_sha or config.get("acceptance_source_sha") != source_sha:
        problems.append("Acceptance evidence must identify the exact source commit")
    for name in ATTESTATIONS:
        if config.get("acceptance", {}).get(name) is not True:
            problems.append("Acceptance still open: " + name)
    return problems


def archive_proof(folder):
    app = Path(folder) / "Products/Applications/NeuralNotes.app"
    info = plistlib.loads((app / "Info.plist").read_bytes())
    sdk = info.get("DTSDKName", "")
    match = re.fullmatch(r"iphoneos(\d+)(?:\.\d+)*", sdk)
    if not match or int(match[1]) < 26:
        raise ValueError("Archive was not built with iOS SDK 26 or later")
    if info.get("CFBundleIdentifier") != "com.neuralnotes.NeuralNotes":
        raise ValueError("Unexpected archive Bundle ID")
    if not (app / info.get("CFBundleExecutable", "missing")).is_file():
        raise ValueError("Archive executable missing")
    if not (app / "Assets.car").is_file() or not info.get("CFBundleIcons~ipad", info.get("CFBundleIcons")):
        raise ValueError("Archive app icon/catalog missing")
    if not (app / "PrivacyInfo.xcprivacy").is_file():
        raise ValueError("Archive privacy manifest missing")
    return {"bundleID": info["CFBundleIdentifier"], "version": info["CFBundleShortVersionString"],
            "build": info["CFBundleVersion"], "sdk": sdk, "minimumOS": info.get("MinimumOSVersion"),
            "signed": (app / "_CodeSignature/CodeResources").is_file(), "uploaded": False}


def production_problems(config, source_sha, online=False):
    problems = configuration_problems(config, source_sha)
    for path in ("NeuralNotes/Resources/Info.plist", "NeuralNotes/App/PlaygroundInfo.plist"):
        info = plistlib.loads((ROOT / path).read_bytes())
        for key, field in (("NeuralNotesServiceURL", "gateway_origin"), ("NeuralNotesPrivacyURL", "privacy_url"), ("NeuralNotesSupportURL", "support_url")):
            if not config.get(field) or info.get(key) != config[field].rstrip("/"):
                problems.append(path + " is not bound to " + field)
    privacy = plistlib.loads((ROOT / "NeuralNotes/Resources/PrivacyInfo.xcprivacy").read_bytes())
    if not privacy.get("NSPrivacyCollectedDataTypes"):
        problems.append("Privacy manifest still declares no collected data; review hosted account/cloud data")
    if online and not problems:
        # Only the explicitly configured public services; never provider calls.
        from configure_service import verify, NoRedirects
        verify(config["gateway_origin"].rstrip("/"))
        opener = urllib.request.build_opener(NoRedirects())
        for key in ("privacy_url", "support_url", "gateway_origin"):
            url = config[key].rstrip("/") + ("/ready" if key == "gateway_origin" else "")
            with opener.open(url, timeout=20) as response:
                body = response.read(65537)
                if response.status != 200 or not body:
                    problems.append("Public endpoint unavailable: " + key)
                elif key == "gateway_origin" and json.loads(body).get("ready") is not True:
                    problems.append("Gateway database is not ready")
    return problems


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--production", action="store_true")
    parser.add_argument("--online", action="store_true")
    parser.add_argument("--archive", type=Path)
    parser.add_argument("--report", type=Path)
    args = parser.parse_args()
    report = {"production_checked": args.production, "problems": []}
    if args.archive:
        report["archive"] = archive_proof(args.archive)
    if args.production:
        raw = os.environ.get("NN_PRODUCTION_CONFIG", "{}")
        config = json.loads(raw)
        sha = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip()
        report["problems"] = production_problems(config, sha, args.online)
    report["passed"] = not report["problems"]
    encoded = json.dumps(report, indent=2)
    if args.report:
        args.report.parent.mkdir(parents=True, exist_ok=True)
        args.report.write_text(encoded + "\n", encoding="utf-8")
    print(encoded)
    return 0 if report["passed"] else 2


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception:
        # Do not echo URLs containing credentials, keys, provider output or config JSON.
        sys.exit("Release preflight failed; inspect public configuration and artifact inputs. No secret values logged.")
