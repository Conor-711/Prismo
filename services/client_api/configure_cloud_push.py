"""Upload APNs configuration to the existing iOS Supabase project, without printing secrets."""
import argparse
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

PROJECT = "dzyitinagewdfkzjkuiz"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--private-key-path", type=Path, required=True)
    parser.add_argument("--key-id", required=True)
    parser.add_argument("--team-id", required=True)
    args = parser.parse_args()
    if any(len(value) != 10 or not value.isascii() or not value.isalnum()
           for value in (args.key_id, args.team_id)):
        parser.error("Expected ten-character Apple identifiers")
    path = args.private_key_path.expanduser().resolve()
    if not path.is_file() or path.stat().st_size > 4096 or path.stat().st_mode & 0o077:
        parser.error("Private key must be a protected regular file with mode 0600")
    # Apple's bundled LibreSSL does not implement `pkey -check`.
    openssl = next((str(candidate) for candidate in (
        Path("/opt/homebrew/opt/openssl@3/bin/openssl"),
        Path("/usr/local/opt/openssl@3/bin/openssl")) if candidate.is_file()), shutil.which("openssl"))
    if not openssl:
        parser.error("OpenSSL is required for private key validation")
    check = subprocess.run([openssl, "pkey", "-in", str(path), "-check", "-noout"], capture_output=True)
    if check.returncode:
        parser.error("Private key validation failed")
    values = {"BSMART_APNS_TEAM_ID": args.team_id, "BSMART_APNS_KEY_ID": args.key_id,
              "BSMART_APNS_TOPIC": "today.bsmart.ios", "BSMART_APNS_PRIVATE_KEY": path.read_text(),
              "BSMART_CLOUD_PUSH_ENABLED": "false"}
    # Use a protected temporary env file; private key never appears in process arguments.
    fd, filename = tempfile.mkstemp(prefix="bsmart-apns-", suffix=".env")
    try:
        with os.fdopen(fd, "w") as stream:
            for key, value in values.items():
                stream.write(f"{key}={json.dumps(value)}\n")
        cli = shutil.which("supabase") or "/opt/homebrew/bin/supabase"
        result = subprocess.run([cli, "secrets", "set", "--project-ref", PROJECT,
                                 "--env-file", filename], capture_output=True)
        if result.returncode:
            raise SystemExit("Supabase configuration failed; no credentials displayed")
    finally:
        os.unlink(filename)
    print(json.dumps({"project": PROJECT, "credentialsConfigured": True, "cloudPushEnabled": False}))


if __name__ == "__main__":
    main()
