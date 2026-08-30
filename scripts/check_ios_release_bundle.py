#!/usr/bin/env python3
"""Fail when a bSmart Release bundle leaks fixtures or omits privacy metadata."""

from __future__ import annotations

import argparse
import plistlib
from pathlib import Path
from urllib.parse import urlparse


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("app_bundle", type=Path)
    parser.add_argument(
        "--expected-data-environment",
        choices=("demo", "production"),
        default="production",
    )
    parser.add_argument("--expected-api-base-url", default="")
    args = parser.parse_args()
    bundle = args.app_bundle

    if not bundle.is_dir():
        raise SystemExit(f"Release app bundle not found: {bundle}")

    fixture_files = sorted(bundle.rglob("*.json"))
    required_snapshots = {
        "portfolio.json",
        "portfolio-history.json",
        "portfolio-signals.json",
        "smart-account-updates.json",
        "smart-money-movements.json",
        "ticker-intelligence.json",
        "smart-accounts.json",
        "smart-account-evidence.json",
        "smart-money.json",
        "smart-money-evidence.json",
        "events.json",
        "research.json",
    }
    bundled_snapshots = {path.name for path in fixture_files}
    missing_snapshots = sorted(required_snapshots - bundled_snapshots)
    unexpected_snapshots = sorted(bundled_snapshots - required_snapshots)
    if missing_snapshots:
        raise SystemExit(
            "Release bundle is missing offline bootstrap snapshots: "
            + ", ".join(missing_snapshots)
        )
    if unexpected_snapshots:
        raise SystemExit(
            "Release bundle contains unexpected JSON resources: "
            + ", ".join(unexpected_snapshots)
        )

    manifest_path = bundle / "PrivacyInfo.xcprivacy"
    if not manifest_path.is_file():
        raise SystemExit("Release bundle is missing PrivacyInfo.xcprivacy")

    with manifest_path.open("rb") as handle:
        manifest = plistlib.load(handle)

    if manifest.get("NSPrivacyTracking") is not False:
        raise SystemExit("Privacy manifest must explicitly disable tracking")

    accessed_types = {
        item.get("NSPrivacyAccessedAPIType"): set(item.get("NSPrivacyAccessedAPITypeReasons", []))
        for item in manifest.get("NSPrivacyAccessedAPITypes", [])
    }
    if "CA92.1" not in accessed_types.get("NSPrivacyAccessedAPICategoryUserDefaults", set()):
        raise SystemExit("Privacy manifest is missing the UserDefaults CA92.1 reason")

    info_path = bundle / "Info.plist"
    with info_path.open("rb") as handle:
        info = plistlib.load(handle)

    data_environment = info.get("BSMART_DATA_ENVIRONMENT")
    if data_environment != args.expected_data_environment:
        raise SystemExit(
            f"Expected {args.expected_data_environment!r} data environment, found {data_environment!r}"
        )

    api_base_url = info.get("BSMART_API_BASE_URL", "")
    parsed_url = urlparse(api_base_url)
    if parsed_url.scheme != "https" or not parsed_url.hostname:
        raise SystemExit(f"Client API URL must be an HTTPS origin: {api_base_url!r}")
    expected_api_base_url = args.expected_api_base_url.strip()
    if expected_api_base_url and api_base_url != expected_api_base_url:
        raise SystemExit(
            f"Expected client API {expected_api_base_url!r}, found {api_base_url!r}"
        )
    if (
        data_environment == "production"
        and not expected_api_base_url
        and api_base_url != "https://api.bsmart.today"
    ):
        raise SystemExit(f"Production build points to an unexpected API: {api_base_url}")
    if data_environment == "demo" and api_base_url == "https://api.bsmart.today":
        raise SystemExit("Demo build must not point to the production API")

    if not (bundle / "Assets.car").is_file():
        raise SystemExit("Release bundle is missing compiled app assets")
    primary_icon = (
        info.get("CFBundleIcons", {})
        .get("CFBundlePrimaryIcon", {})
        .get("CFBundleIconFiles", [])
    )
    if not primary_icon:
        raise SystemExit("Release bundle does not declare a primary App Icon")

    print(f"Release bundle check passed: {bundle}")
    print(f"- offline bootstrap snapshots: {len(required_snapshots)}")
    print("- unexpected JSON resources: 0")
    print("- privacy manifest: present")
    print("- tracking: disabled")
    print("- UserDefaults reason: CA92.1")
    print(f"- data environment: {data_environment}")
    print(f"- client API: {api_base_url}")
    print(f"- primary App Icon: {primary_icon[-1]}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
