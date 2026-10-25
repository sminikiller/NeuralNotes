"""Bind both app builds to a verified public gateway, without receiving secrets."""
from pathlib import Path
import argparse
import json
import plistlib
import urllib.parse
import urllib.request
import base64

ROOT = Path(__file__).resolve().parents[1]


def secure_origin(raw):
    value = urllib.parse.urlsplit(raw)
    if (value.scheme != 'https' or not value.hostname or value.username or value.password
            or value.query or value.fragment or value.path.endswith('/v1/study')):
        raise ValueError('Provide the HTTPS gateway origin/prefix, without credentials, query or /v1/study.')
    return raw.rstrip('/')


class NoRedirects(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, *_args, **_kwargs):
        return None


def verify(origin):
    opener = urllib.request.build_opener(NoRedirects())
    with opener.open(origin + '/v1/config', timeout=20) as response:
        data = response.read(65_537)
    if len(data) > 65_536:
        raise ValueError('Configuration too large.')
    value = json.loads(data)
    auth = value.get('auth') or {}
    if value.get('version') != 1 or value.get('managed') is not True:
        raise ValueError('Gateway is not configured for managed accounts.')
    public_key = auth.get('publicKey', '')
    allowed = public_key.startswith('sb_publishable_') and len(public_key) > 24
    if not allowed:
        try:
            payload = public_key.split('.')[1]
            allowed = json.loads(base64.urlsafe_b64decode(payload + '=' * (-len(payload) % 4))).get('role') == 'anon'
        except (ValueError, IndexError, TypeError):
            allowed = False
    if not allowed:
        raise ValueError('Gateway must expose a publishable/anon key, never a service-role secret.')
    auth_origin = secure_origin(auth.get('url', ''))
    if urllib.parse.urlsplit(auth_origin).path not in ('', '/'):
        raise ValueError('Invalid Auth origin.')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--origin', required=True, help='Public HTTPS origin/prefix, not a provider key.')
    parser.add_argument('--privacy-url', help='Published HTTPS privacy notice; requires --support-url too.')
    parser.add_argument('--support-url', help='Published HTTPS support page; requires --privacy-url too.')
    args = parser.parse_args()
    origin = secure_origin(args.origin)
    verify(origin)  # No plist is edited on a failed remote check.
    pages = {}
    if bool(args.privacy_url) != bool(args.support_url):
        parser.error('Provide both --privacy-url and --support-url.')
    if args.privacy_url:
        opener = urllib.request.build_opener(NoRedirects())
        for key, raw in [('NeuralNotesPrivacyURL', args.privacy_url), ('NeuralNotesSupportURL', args.support_url)]:
            url = secure_origin(raw)
            with opener.open(url, timeout=20) as response:
                if response.status != 200 or not response.read(1):
                    raise ValueError('Published privacy/support page is not accessible.')
            pages[key] = url
    files = [ROOT / 'NeuralNotes/Resources/Info.plist', ROOT / 'NeuralNotes/App/PlaygroundInfo.plist']
    encoded = []
    for file in files:
        value = plistlib.loads(file.read_bytes())
        value['NeuralNotesServiceURL'] = origin
        value.update(pages)
        encoded.append((file, plistlib.dumps(value, sort_keys=False)))
    for file, data in encoded:
        temporary = file.with_suffix('.plist.pending')
        temporary.write_bytes(data)
        temporary.replace(file)
    print('Configured both app builds for the verified managed gateway; no credentials written.')


if __name__ == '__main__':
    main()
