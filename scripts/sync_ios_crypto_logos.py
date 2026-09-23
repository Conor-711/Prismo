#!/usr/bin/env python3
"""Bundle Hyperliquid coin artwork as PNG. Requires curl, Node.js and sharp."""
import argparse
from concurrent.futures import ThreadPoolExecutor
import hashlib
import json
from pathlib import Path
import re
import subprocess
from urllib.parse import quote
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
ASSETS = ROOT / "ios/BSmart/Assets.xcassets"
AUDIT = ROOT / "ios/asset-sources/crypto-logos.json"
BASE = "https://app.hyperliquid.xyz/coins/"
# These contracts quote 1,000 tokens; the official image uses the underlying name.
LOGO_NAMES = {"kBONK": "BONK", "kDOGS": "DOGS", "kFLOKI": "FLOKI",
              "kLUNC": "LUNC", "kNEIRO": "NEIRO", "kPEPE": "PEPE", "kSHIB": "SHIB"}


def sized_svg(data):
    root = ET.fromstring(data)
    if "viewBox" not in root.attrib:
        if "viewbox" in root.attrib:
            root.set("viewBox", root.attrib.pop("viewbox"))
        else:
            dimensions = [float(root.attrib[key].removesuffix("px")) for key in ("width", "height")]
            root.set("viewBox", f"0 0 {dimensions[0]:g} {dimensions[1]:g}")
    # Preserve vector coordinates and colors, but bound Xcode's rasterization size.
    root.set("width", "64")
    root.set("height", "64")
    ET.register_namespace("", "http://www.w3.org/2000/svg")
    ET.register_namespace("xlink", "http://www.w3.org/1999/xlink")
    return ET.tostring(root, encoding="utf-8", xml_declaration=True)


def fetch(url, payload=None):
    command = ["curl", "--http1.1", "--fail", "--silent", "--show-error", "--max-time", "25",
               "--retry", "1", url]
    if payload is not None:
        command += ["-H", "Content-Type: application/json", "-d", json.dumps(payload)]
    return subprocess.run(command, check=True, capture_output=True).stdout


def png(data):
    script = """const sharp = require('sharp');
const chunks = [];
process.stdin.on('data', c => chunks.push(c));
process.stdin.on('end', async () => {
  try {
    const data = await sharp(Buffer.concat(chunks), {density: 288})
      .resize(256, 256, {fit: 'contain', background: '#00000000'}).png().toBuffer();
    process.stdout.write(data);
  } catch (error) { console.error(error); process.exitCode = 1; }
});"""
    return subprocess.run(["node", "-e", script], input=sized_svg(data),
                          check=True, capture_output=True, timeout=30).stdout


def install(coin):
    symbol = coin.upper()
    url = BASE + quote(LOGO_NAMES.get(coin, coin), safe="") + ".svg"
    try:
        data = fetch(url)
        source_hash = hashlib.sha256(data).hexdigest()
        root = ET.fromstring(data)
        if root.tag != "{http://www.w3.org/2000/svg}svg":
            raise ValueError("Response is not SVG")
        for node in root.iter():
            if node.tag.rsplit("}", 1)[-1] in {"script", "foreignObject"}:
                raise ValueError("Unsupported active SVG content")
            for key, value in node.attrib.items():
                if (node.tag.rsplit("}", 1)[-1] != "a"
                        and key.rsplit("}", 1)[-1] == "href"
                        and not value.startswith(("#", "data:image/"))):
                    raise ValueError("SVG references an external resource")
        data = png(data)
        folder = ASSETS / f"Crypto_{symbol}.imageset"
        folder.mkdir(exist_ok=True)
        contents_path = folder / "Contents.json"
        previous = json.loads(contents_path.read_text()) if contents_path.exists() else {}
        filename = f"{symbol}.png"
        (folder / filename).write_bytes(data)
        contents = {
            "images": [{"filename": filename, "idiom": "universal"}],
            "info": {"author": "xcode", "version": 1},
            "properties": {"template-rendering-intent": "original"},
        }
        contents_path.write_text(json.dumps(contents, indent=2) + "\n")
        for image in previous.get("images", []):
            old = image.get("filename")
            if old and old.casefold() != filename.casefold() and Path(old).name == old:
                (folder / old).unlink(missing_ok=True)
        return symbol, {"coin": coin, "source": url, "asset": filename,
                        "source_sha256": source_hash, "rendered_size": 256,
                        "sha256": hashlib.sha256(data).hexdigest(), "status": "downloaded"}
    except (subprocess.SubprocessError, ValueError, OSError, ET.ParseError) as error:
        return symbol, {"coin": coin, "source": url, "status": "unavailable",
                        "error": str(error)}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--meta", type=Path, help="Saved official native-perp meta response")
    parser.add_argument("--missing-only", action="store_true", help="Retry only unverified assets")
    parser.add_argument("--rasterize-bundled", action="store_true",
                        help="Convert verified local SVGs to PNG without downloading")
    args = parser.parse_args()
    if args.rasterize_bundled:
        audit = json.loads(AUDIT.read_text())
        for symbol, entry in audit["logos"].items():
            if entry["status"] != "downloaded":
                continue
            if entry["asset"].endswith(".png"):
                continue
            path = ASSETS / f"Crypto_{symbol}.imageset" / entry["asset"]
            data = path.read_bytes()
            if hashlib.sha256(data).hexdigest() != entry["sha256"]:
                raise ValueError(f"Changed source file: {symbol}")
            entry.setdefault("source_sha256", entry["sha256"])
            data = png(data)
            output = path.with_suffix(".png")
            output.write_bytes(data)
            contents = json.loads((path.parent / "Contents.json").read_text())
            contents["images"] = [{"filename": output.name, "idiom": "universal"}]
            contents["properties"] = {"template-rendering-intent": "original"}
            (path.parent / "Contents.json").write_text(json.dumps(contents, indent=2) + "\n")
            path.unlink()
            entry.pop("viewport", None)
            entry.update(asset=output.name, sha256=hashlib.sha256(data).hexdigest(), rendered_size=256)
        AUDIT.write_text(json.dumps(audit, indent=2, sort_keys=True) + "\n")
        return
    meta = json.loads(args.meta.read_bytes() if args.meta else
                      fetch("https://api.hyperliquid.xyz/info", {"type": "meta"}))
    coins = sorted({item["name"] for item in meta["universe"]})
    if not coins or any(not re.fullmatch(r"[A-Za-z0-9_.-]+", coin) for coin in coins):
        raise ValueError("Invalid native coin universe")
    previous = json.loads(AUDIT.read_text()).get("logos", {}) if AUDIT.exists() else {}
    if args.missing_only:
        def verified(coin):
            entry = previous.get(coin.upper(), {})
            path = ASSETS / f"Crypto_{coin.upper()}.imageset" / entry.get("asset", "missing")
            return (entry.get("status") == "downloaded" and path.is_file()
                    and hashlib.sha256(path.read_bytes()).hexdigest() == entry.get("sha256"))
        coins = [coin for coin in coins if not verified(coin)]
    with ThreadPoolExecutor(max_workers=4) as pool:
        results = dict(pool.map(install, coins))
    # A failed refresh must not discard provenance for an already verified asset.
    for symbol, entry in results.items():
        if entry["status"] == "downloaded":
            previous[symbol] = entry
        elif previous.get(symbol, {}).get("status") != "downloaded":
            previous[symbol] = entry
    AUDIT.write_text(json.dumps({"catalog_source": "https://api.hyperliquid.xyz/info (meta)",
                                 "logos": previous}, indent=2, sort_keys=True) + "\n")
    missing = [s for s, entry in results.items() if entry["status"] != "downloaded"]
    print(json.dumps({"requested": len(coins), "downloaded": len(coins) - len(missing),
                      "unavailable": missing}, indent=2))


if __name__ == "__main__":
    main()
