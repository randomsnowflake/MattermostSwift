#!/bin/sh
# Authentication-only E2E: no posts, channels, or account-setting changes.
set -eu
cd "$(dirname "$0")/.."
swift build --product MattermostSwiftCLI
export MATTERMOST_LOGIN_TEST_BINARY="$(swift build --show-bin-path)/MattermostSwiftCLI"
python3 - <<'PYTHON'
import base64
import getpass
import hashlib
import hmac
import os
import struct
import subprocess
import sys
import time

settings = os.environ.copy()
for key, prompt in [("MATTERMOST_URL", "Server URL: "),
                    ("MATTERMOST_USERNAME", "Username or email: "),
                    ("MATTERMOST_PASSWORD", "Password: ")]:
    if not settings.get(key):
        if not sys.stderr.isatty():
            raise SystemExit(f"Missing environment variable: {key}")
        settings[key] = getpass.getpass(prompt)
secret = settings.pop("MATTERMOST_MFA_SECRET", "").replace(" ", "").upper()
if secret:
    # Generate after compilation, avoiding codes that expire during the build.
    remaining = 30 - time.time() % 30
    if remaining < 5:
        time.sleep(remaining + 0.2)
    try:
        key = base64.b32decode(secret + "=" * (-len(secret) % 8))
    except ValueError:
        raise SystemExit("MATTERMOST_MFA_SECRET must be a Base32 authenticator setup secret.")
    digest = hmac.new(key, struct.pack(">Q", int(time.time()) // 30), hashlib.sha1).digest()
    offset = digest[-1] & 15
    value = (struct.unpack(">I", digest[offset:offset + 4])[0] & 0x7fffffff) % 1000000
    settings["MATTERMOST_MFA_TOKEN"] = f"{value:06d}"
elif not settings.get("MATTERMOST_MFA_TOKEN") and sys.stderr.isatty():
    code = getpass.getpass("Current 6-digit MFA code (Enter if MFA is disabled): ")
    if code:
        settings["MATTERMOST_MFA_TOKEN"] = code.strip()
raise SystemExit(subprocess.run([settings.pop("MATTERMOST_LOGIN_TEST_BINARY"), "diag", "login-test"], env=settings).returncode)
PYTHON
