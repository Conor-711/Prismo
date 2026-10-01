"""One authorized production-device probe; temporary cloud function is removed afterward."""
import argparse
from datetime import datetime, timezone
import json
import os
from pathlib import Path
import secrets
import shutil
import subprocess
import tempfile
import time
from uuid import uuid4

import httpx
from sqlalchemy import create_engine, text
from sqlalchemy.engine import make_url

from .config import REPO_ROOT, normalize_database_url
from .content_release.__main__ import publication_database_url

PROJECT = "dzyitinagewdfkzjkuiz"
FUNCTION = "bsmart-push-probe"
SECRET = "BSMART_APNS_PROBE_CONFIG"


def cli(*args):
    result = subprocess.run([shutil.which("supabase") or "/opt/homebrew/bin/supabase", *args,
                             "--project-ref", PROJECT], cwd=REPO_ROOT / "supabase/ios-account",
                            capture_output=True, text=True)
    if result.returncode:
        raise RuntimeError("Supabase operation failed; credentials suppressed")
    return result.stdout


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--handle", required=True)
    parser.add_argument("--apply", action="store_true")
    parser.add_argument("--proxy", help="Optional operator network proxy, never included in reports")
    args = parser.parse_args()
    url = make_url(normalize_database_url(publication_database_url()))
    if PROJECT not in ((url.host or "") + (url.username or "")):
        parser.error("Expected the native iOS database")
    engine = create_engine(url, connect_args={"connect_timeout": 10, "options": "-c statement_timeout=10000"})
    try:
        with engine.connect() as connection:
            account = connection.execute(text("select account_id from public.bsmart_feed_profiles where handle=:h"),
                                         {"h": args.handle.removeprefix("@").lower()}).scalar_one()
            devices = connection.execute(text("""select id,apns_token,locale,updated_at from public.bsmart_push_devices
                where user_id=:u and enabled and environment='production' and updated_at>now()-interval '30 days'
                order by updated_at desc,id"""), {"u": account}).mappings().all()
        if not devices:
            raise RuntimeError("No fresh enabled production device")
        device = devices[0]
        print(json.dumps({"target": args.handle, "productionRegistrations": len(devices),
                          "selectedRegistrationAgeSeconds": round((datetime.now(timezone.utc) - device["updated_at"]).total_seconds()),
                          "sendRequested": args.apply}), flush=True)
        if not args.apply:
            return
        existing = json.loads(cli("functions", "list", "-o", "json"))
        if any(item.get("slug", item.get("name")) == FUNCTION for item in existing):
            raise RuntimeError("Probe function already exists; do not overwrite an unknown deployment")
        bearer = secrets.token_hex(32)
        config = {"bearer": bearer, "expires": int(time.time() * 1000) + 9 * 60_000, "delivery": {
            "user_id": str(account), "device_id": str(device["id"]), "apns_id": str(uuid4()),
            "apns_token": device["apns_token"], "locale": device["locale"], "environment": "production",
            "device_updated_at": device["updated_at"].isoformat(),
        }}
        fd, name = tempfile.mkstemp(prefix="bsmart-probe-", suffix=".env")
        cleanup_errors = []
        deployed = False
        try:
            with os.fdopen(fd, "w") as stream:
                stream.write(f"{SECRET}={json.dumps(json.dumps(config))}\n")
            cli("secrets", "set", "--env-file", name)
            # Mark before dispatching deployment so an uncertain CLI result still triggers cleanup.
            deployed = True
            cli("functions", "deploy", FUNCTION, "--no-verify-jwt")
            with httpx.Client(http2=True, proxy=args.proxy, timeout=30) as client:
                response = client.post(f"https://{PROJECT}.supabase.co/functions/v1/{FUNCTION}",
                                       headers={"authorization": "Bearer " + bearer}, json={})
            if response.status_code != 200:
                raise RuntimeError("Probe response unavailable; do not retry an uncertain send")
            result = response.json()
            print(json.dumps({"accepted": result.get("accepted") is True,
                              "providerStatus": result.get("providerStatus"), "attempts": 1}), flush=True)
        finally:
            os.unlink(name)
            if deployed:
                try:
                    cli("functions", "delete", FUNCTION, "--yes")
                except Exception:
                    cleanup_errors.append("function")
            try:
                cli("secrets", "unset", SECRET, "--yes")
            except Exception:
                cleanup_errors.append("secret")
            print(json.dumps({"probeCleanupComplete": not cleanup_errors, "cleanupRequired": cleanup_errors}), flush=True)
    except Exception as error:
        print(json.dumps({"errorType": type(error).__name__, "message": "Probe could not finish; no device tokens or credentials displayed"}), flush=True)
        raise SystemExit(1) from None
    finally:
        engine.dispose()


if __name__ == "__main__":
    main()
