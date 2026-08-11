#!/usr/bin/env bash
set -euo pipefail

device_name="${IOS_TEST_DEVICE:-iPhone 16}"
device_os="${IOS_TEST_OS:-}"
test_only="${IOS_TEST_ONLY:-}"

device_id="$({
  xcrun simctl list devices available -j
} | python3 -c '
import json
import sys

payload = json.load(sys.stdin)
name = sys.argv[1]
preferred_os = sys.argv[2]
candidates = []
fallbacks = []

for runtime, devices in payload.get("devices", {}).items():
    if "iOS" not in runtime:
        continue
    os_version = runtime.rsplit("iOS-", 1)[-1].replace("-", ".")
    for device in devices:
        if not device.get("isAvailable", False):
            continue
        if device.get("name") == name:
            candidates.append((os_version, device["udid"]))
        if device.get("name", "").startswith("iPhone"):
            fallbacks.append((os_version, device["udid"]))

if preferred_os:
    for os_version, udid in candidates:
        if os_version == preferred_os:
            print(udid)
            raise SystemExit(0)

if candidates:
    print(sorted(candidates, reverse=True)[0][1])
    raise SystemExit(0)

if fallbacks:
    print(sorted(fallbacks, reverse=True)[0][1])
    raise SystemExit(0)

raise SystemExit(f"No available iOS simulator (preferred name: {name!r})")
' "$device_name" "$device_os")"

echo "Using iOS simulator: ${device_name} (${device_id})"
xcrun simctl shutdown "$device_id" >/dev/null 2>&1 || true
xcrun simctl boot "$device_id" >/dev/null
xcrun simctl bootstatus "$device_id" -b

test_arguments=()
if [[ -n "$test_only" ]]; then
  test_arguments+=("-only-testing:${test_only}")
  echo "Running selected iOS tests: ${test_only}"
fi

if [[ ${#test_arguments[@]} -gt 0 ]]; then
  xcodebuild \
    -project ios/bSmart.xcodeproj \
    -scheme bSmart \
    -destination "platform=iOS Simulator,id=${device_id}" \
    CODE_SIGNING_ALLOWED=NO \
    "${test_arguments[@]}" \
    test
else
  xcodebuild \
    -project ios/bSmart.xcodeproj \
    -scheme bSmart \
    -destination "platform=iOS Simulator,id=${device_id}" \
    CODE_SIGNING_ALLOWED=NO \
    test
fi
