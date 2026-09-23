#!/usr/bin/env python3
"""Bundle catalog logos and retain a source/hash audit. Requires Pillow and curl."""
import argparse
import concurrent.futures
import hashlib
import io
import json
from pathlib import Path
import re
import subprocess
import xml.etree.ElementTree as ET

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
ASSETS = ROOT / "ios/BSmart/Assets.xcassets"
AUDIT = ROOT / "ios/asset-sources/ticker-logos.json"
OFFICIAL_OVERRIDES = {
    "DGXX": "https://www.digipowerx.com/icon.png",
    "MRLN": "https://merlinlabs.com/icons/icon-512x512.png?v=ddd2864990cce3a12677fa91f6f1ee8a",
    "UNITREE": "https://www.unitree.com/unitree-favicon.svg",
    "LYTE": "https://www.roundhillinvestments.com/assets/img/roundhill-round-logo-white.svg",
    "NCLD": "https://www.roundhillinvestments.com/assets/img/roundhill-round-logo-white.svg",
    "SHEIN": "https://www.sheingroup.com/apple-touch-icon-152x152.png",
    "YMTC": "https://www.ymtc.com/cn/1ca/image/20210521/671aa77220b00477809847e105bbf72e.png",
}


def fetch(url):
    return subprocess.run(["curl", "--fail", "--location", "--silent", "--show-error",
                           "--max-time", "25", "--retry", "1", url],
                          capture_output=True, check=True).stdout


def symbols_in(value):
    if isinstance(value, dict):
        for key, item in value.items():
            if key in {"ticker", "recentTicker"} and isinstance(item, str):
                yield item.strip().upper().lstrip("$")
            elif key == "topTickers" and isinstance(item, list):
                yield from (s.upper().lstrip("$") for s in item if isinstance(s, str))
            else:
                yield from symbols_in(item)
    elif isinstance(value, list):
        for item in value:
            yield from symbols_in(item)


def official_sources(script_directory):
    sources = {}
    for path in script_directory.glob("*.js"):
        for name, asset in re.findall(r'MARKET_([A-Z0-9_]+)="(/?markets/[^\"]+)"', path.read_text()):
            symbol = Path(asset).stem.upper()
            if name == "XYZ100":
                symbol = "XYZ100"
            sources[symbol] = "https://app.trade.xyz/" + asset.lstrip("/")
    return sources


def install(symbol, sources, previous):
    folder = ASSETS / f"Ticker_{symbol}.imageset"
    if folder.exists():
        return symbol, previous.get(symbol, {"status": "existing", "source": "existing project asset"})
    candidates = [sources[symbol]] if symbol in sources else []
    candidates.append(f"https://financialmodelingprep.com/image-stock/{symbol}.png")
    for url in candidates:
        try:
            data = fetch(url)
            suffix = ".svg" if url.endswith(".svg") else ".png"
            if suffix == ".svg":
                root = ET.fromstring(data)
                if not root.tag.endswith("svg"):
                    raise ValueError("Not SVG")
            else:
                with Image.open(io.BytesIO(data)) as image:
                    image.load()
                    if min(image.size) < 16:
                        raise ValueError("Undersized image")
                    # Normalize formats; some .png endpoints return JPEG/WebP bytes.
                    output = io.BytesIO()
                    image.convert("RGBA").save(output, format="PNG")
                    data = output.getvalue()
            folder.mkdir()
            filename = symbol + suffix
            (folder / filename).write_bytes(data)
            contents = {"images": [{"filename": filename, "idiom": "universal"}],
                        "info": {"author": "xcode", "version": 1}}
            if suffix == ".svg":
                contents["properties"] = {"preserves-vector-representation": True}
            (folder / "Contents.json").write_text(json.dumps(contents, indent=2) + "\n")
            return symbol, {"status": "downloaded", "source": url,
                            "sha256": hashlib.sha256(data).hexdigest(), "asset": filename}
        except (subprocess.SubprocessError, ValueError, OSError, ET.ParseError):
            continue
    return symbol, {"status": "missing"}


def needs_template(symbol):
    """Detect monochrome marks on transparency; never recolor brand colors."""
    if symbol in {"AVAV", "PLTR", "UNITREE"}:
        return True
    path = ASSETS / f"Ticker_{symbol}.imageset/{symbol}.png"
    if not path.exists():
        return False
    with Image.open(path) as image:
        pixels = list(image.convert("RGBA").getdata())
    opaque = [(r, g, b) for r, g, b, a in pixels if a > 32]
    if not opaque or len(opaque) > len(pixels) * 0.95:
        return False
    dark_neutral = sum(max(rgb) < 90 and max(rgb) - min(rgb) < 30 for rgb in opaque)
    return dark_neutral / len(opaque) > 0.97


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--official-scripts", type=Path,
                        help="Public app.trade.xyz scripts, downloaded for source verification")
    parser.add_argument("--market-catalog", type=Path,
                        help="Public Hyperliquid metaAndAssetCtxs JSON for additional market coverage")
    args = parser.parse_args()
    sources = official_sources(args.official_scripts) if args.official_scripts else {}
    sources.update(OFFICIAL_OVERRIDES)
    symbols = set(sources)
    for fixture in (ROOT / "contracts/fixtures").glob("*.json"):
        symbols.update(symbols_in(json.loads(fixture.read_text())))
    if args.market_catalog:
        meta = json.loads(args.market_catalog.read_text())[0]
        symbols.update(m["name"].split(":")[-1] for m in meta["universe"])
    symbols = {s for s in symbols if re.fullmatch(r"[A-Z0-9.-]+", s)}
    previous = json.loads(AUDIT.read_text()).get("logos", {}) if AUDIT.exists() else {}
    symbols.update(previous)
    # MARKET represents an account with no open position, not a listed security.
    symbols.discard("MARKET")
    for symbol, entry in previous.items():
        if entry.get("source", "").startswith("https://"):
            sources.setdefault(symbol, entry["source"])
    with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:
        result = dict(pool.map(lambda s: install(s, sources, previous), sorted(symbols)))
    AUDIT.parent.mkdir(parents=True, exist_ok=True)
    AUDIT.write_text(json.dumps({"logos": result}, indent=2, sort_keys=True) + "\n")
    bundled = [s for s, entry in result.items() if entry["status"] != "missing"]
    registry = ROOT / "ios/BSmart/Core/DesignSystem/TickerLogoRegistry.swift"
    lines = ["// Generated by scripts/sync_ios_ticker_logos.py; sources in ios/asset-sources.",
             "enum TickerLogoRegistry {", "    static let symbols: Set<String> = ["]
    for offset in range(0, len(bundled), 8):
        lines.append("        " + ", ".join(json.dumps(s) for s in bundled[offset:offset + 8]) + ",")
    templates = [s for s in bundled if needs_template(s)]
    lines.extend(["    ]", "    static let templateSymbols: Set<String> = [",
                  "        " + ", ".join(json.dumps(s) for s in templates), "    ]", "}", ""])
    registry.write_text("\n".join(lines))
    missing = [s for s, entry in result.items() if entry["status"] == "missing"]
    hashes = {}
    for symbol, entry in result.items():
        if "sha256" in entry:
            hashes.setdefault(entry["sha256"], []).append(symbol)
    print(json.dumps({"total": len(result), "missing": missing,
                      "duplicate_images": [s for s in hashes.values() if len(s) > 1]}, indent=2))


if __name__ == "__main__":
    main()
