#!/bin/bash
set -euo pipefail

# The input must come from build-for-testing using the current fixtures and source.
run_file="${1:?Usage: bash scripts/export_ios_representative_stories.sh PATH.xctestrun SIMULATOR_UUID}"
device="${2:?A simulator UUID is required}"
root="$(cd "$(dirname "$0")/.." && pwd)"
run_dir="$(cd "$(dirname "$run_file")" && pwd)"
export_run="$run_dir/representative-export-$$.xctestrun"
output="$(mktemp /tmp/bsmart-stories.XXXXXX)"
trap 'rm -f "$export_run" "$output"' EXIT

cp "$run_file" "$export_run"
plutil -remove BSmartTests.EnvironmentVariables.BSMART_STORY_EXPORT_PATH "$export_run" 2>/dev/null || true
plutil -insert BSmartTests.EnvironmentVariables.BSMART_STORY_EXPORT_PATH -string "$output" "$export_run"
xcodebuild test-without-building -xctestrun "$export_run" \
  -destination "platform=iOS Simulator,id=$device" -parallel-testing-enabled NO \
  -only-testing:BSmartTests/TodayRepresentativeStoryBundleTests/testExportSnapshot
plutil -lint "$output"
cp "$output" "$root/ios/BSmart/Resources/representative-stories.plist"
printf 'Updated ios/BSmart/Resources/representative-stories.plist; regenerate the Xcode project and rebuild the app.\n'
