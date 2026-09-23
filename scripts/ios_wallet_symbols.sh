#!/bin/bash
# Official symbols are separate release assets, not part of the SwiftPM binaries.
set -euo pipefail

if [[ "${1:-}" == "--archive" && $# == 2 ]]; then
    frameworks="$2/Products/Applications/BSmart.app/Frameworks"
    destination="$2/dSYMs"
elif [[ $# == 0 && "${ACTION:-}" == "install" && "${PLATFORM_NAME:-}" == "iphoneos" ]]; then
    # SwiftPM stages these here before Xcode's final embed/sign tasks.
    frameworks="${BUILT_PRODUCTS_DIR:?}"
    destination="${DWARF_DSYM_FOLDER_PATH:?}"
elif [[ $# == 0 ]]; then
    exit 0
else
    echo 'Usage: bash scripts/ios_wallet_symbols.sh [--archive path.xcarchive]' >&2
    exit 1
fi

cache="${HOME}/Library/Caches/bSmart/WalletCore-symbols/4.8.1"
mkdir -p "$cache" "$destination"
temporary=$(mktemp -d "$cache/work.XXXXXX")
trap 'rm -rf "$temporary"' EXIT

for name in WalletCore WalletCoreSwiftProtobuf; do
    case "$name" in
        WalletCore) checksum=585f9c4811becc6d887794a6616560514dc8cd922cfcfa782fdb5399fdd3f679 ;;
        WalletCoreSwiftProtobuf) checksum=83e598a025de31718534a661d38cb18cfcade373a39e2c8e7050abe92eecabbc ;;
    esac
    binary="$frameworks/$name.framework/$name"
    if [[ ! -f "$binary" ]]; then
        echo "error: Missing archived framework: $binary" >&2
        exit 1
    fi
    zip="$cache/$name.xcframework.dSYM.zip"
    if [[ ! -f "$zip" ]] || [[ "$(shasum -a 256 "$zip" | awk '{print $1}')" != "$checksum" ]]; then
        curl --fail --location --retry 3 --connect-timeout 20 --max-time 300 \
            "https://github.com/trustwallet/wallet-core/releases/download/4.8.1/$name.xcframework.dSYM.zip" \
            --output "$temporary/$name.zip"
        if [[ "$(shasum -a 256 "$temporary/$name.zip" | awk '{print $1}')" != "$checksum" ]]; then
            echo "error: Official $name symbols failed SHA-256 verification." >&2
            exit 1
        fi
        mv "$temporary/$name.zip" "$zip"
    fi
    unzip -q "$zip" "$name.dSYMs/$name.framework.ios-arm64.dSYM/*" -d "$temporary"
    symbols="$temporary/$name.dSYMs/$name.framework.ios-arm64.dSYM"
    binary_ids=$(xcrun dwarfdump --uuid "$binary" | awk '{print $2, $3}' | sort)
    symbol_ids=$(xcrun dwarfdump --uuid "$symbols" | awk '{print $2, $3}' | sort)
    if [[ -z "$binary_ids" || "$binary_ids" != "$symbol_ids" ]]; then
        echo "error: $name framework and official dSYM UUIDs differ; do not upload mismatched symbols." >&2
        exit 1
    fi
    ditto "$symbols" "$destination/$name.framework.dSYM"
    echo "Verified $name dSYM: $symbol_ids"
done
