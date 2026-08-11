#!/usr/bin/env bash
set -euo pipefail

team_id="${APPLE_TEAM_ID:?Set APPLE_TEAM_ID to the Apple Developer team identifier.}"
api_base_url="${IOS_ALPHA_API_BASE_URL:-https://api.158-247-196-93.sslip.io}"
archive_path="${IOS_ALPHA_ARCHIVE_PATH:-$PWD/build/bSmart-Internal-Alpha.xcarchive}"

case "$api_base_url" in
  https://*) ;;
  *) echo "IOS_ALPHA_API_BASE_URL must use HTTPS." >&2; exit 2 ;;
esac

(
  cd ios
  xcodegen generate
)

xcodebuild \
  -project ios/bSmart.xcodeproj \
  -scheme "bSmart Internal Alpha" \
  -configuration InternalAlpha \
  -destination "generic/platform=iOS" \
  -archivePath "$archive_path" \
  -allowProvisioningUpdates \
  DEVELOPMENT_TEAM="$team_id" \
  BSMART_ENDPOINT_URL="$api_base_url" \
  archive

python3 scripts/check_ios_release_bundle.py \
  --expected-data-environment production \
  --expected-api-base-url "$api_base_url" \
  "$archive_path/Products/Applications/BSmart.app"

echo "Internal Alpha archive ready: $archive_path"
