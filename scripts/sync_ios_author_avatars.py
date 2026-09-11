#!/usr/bin/env python3
"""Bundle small public avatars by exact URL, without embedding author/ranking data."""
import argparse
from concurrent.futures import ThreadPoolExecutor, as_completed
import hashlib
import io
import json
from pathlib import Path
import subprocess
from urllib.parse import urlencode, urlsplit

from PIL import Image, ImageOps

ROOT = Path(__file__).resolve().parents[1]
ASSETS = ROOT / "ios/BSmart/Assets.xcassets"
AUDIT = ROOT / "ios/asset-sources/author-avatars.json"
REGISTRY = ROOT / "ios/BSmart/Core/Data/AuthorAvatarRegistry.swift"
HOSTS = {"pbs.twimg.com", "yt3.ggpht.com", "yt3.googleusercontent.com", "yt4.ggpht.com",
         "styles.redditmedia.com", "i.redd.it", "www.redditstatic.com", "xavatar.imedao.com"}


def source_urls(directory):
    urls = set()
    for filename, field in [("smart-accounts.json", "avatarURL"),
                            ("smart-account-updates.json", "authorAvatarURL")]:
        for row in json.loads((directory / filename).read_text()):
            url = row.get(field)
            if not isinstance(url, str):
                continue
            parsed = urlsplit(url)
            if parsed.scheme == "https" and parsed.hostname in HOSTS and not parsed.username and not parsed.password:
                urls.add(url)
    return sorted(urls)


def install(url, previous, allow_proxy):
    key = hashlib.sha256(url.encode()).hexdigest()
    name = f"AuthorAvatar_{key}"
    folder = ASSETS / f"{name}.imageset"
    image_path = folder / "avatar.jpg"
    old = previous.get(url, {})
    if image_path.exists() and hashlib.sha256(image_path.read_bytes()).hexdigest() == old.get("sha256"):
        return url, old
    candidates = [url]
    if allow_proxy:
        candidates.append("https://images.weserv.nl/?" + urlencode({"url": url, "w": 256, "h": 256,
                                                                   "fit": "cover", "output": "jpg"}))
    for candidate in candidates:
        try:
            result = subprocess.run(["curl", "--fail", "--location", "--silent", "--show-error",
                                     "--proto", "=https", "--proto-redir", "=https",
                                     "--connect-timeout", "4", "--max-time", "10",
                                     "--max-filesize", "4194304", candidate], capture_output=True, check=True)
            raw = result.stdout
            if len(raw) > 4 * 1024 * 1024:
                continue
            with Image.open(io.BytesIO(raw)) as image:
                if image.width * image.height > 20_000_000 or min(image.size) < 16:
                    continue
                thumbnail = ImageOps.exif_transpose(image).convert("RGB")
                thumbnail.thumbnail((256, 256))
                output = io.BytesIO()
                thumbnail.save(output, "JPEG", quality=86, optimize=True)
            data = output.getvalue()
            folder.mkdir(parents=True, exist_ok=True)
            image_path.write_bytes(data)
            (folder / "Contents.json").write_text(json.dumps({
                "images": [{"filename": "avatar.jpg", "idiom": "universal"}],
                "info": {"author": "xcode", "version": 1}}, indent=2) + "\n")
            return url, {"status": "bundled", "key": key, "bytes": len(data),
                         "sha256": hashlib.sha256(data).hexdigest(),
                         "retrievedVia": "origin" if candidate == url else "images.weserv.nl"}
        except (subprocess.SubprocessError, OSError, ValueError, Image.DecompressionBombError):
            continue
    return url, {"status": "unavailable", "key": key}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--read-model-dir", type=Path, default=ROOT / "contracts/fixtures")
    parser.add_argument("--fallback-proxy", action="store_true",
                        help="Allow a build-time public-image relay when the origin is unreachable; never used by the app")
    parser.add_argument("--limit", type=int, default=400)
    parser.add_argument("--reddit-only", action="store_true", help="Bundle only Reddit CDN URLs")
    args = parser.parse_args()
    urls = source_urls(args.read_model_dir)
    if args.reddit_only:
        urls = [url for url in urls if urlsplit(url).hostname in
                {"styles.redditmedia.com", "i.redd.it", "www.redditstatic.com"}]
    selected = urls[:max(0, args.limit)]
    previous = json.loads(AUDIT.read_text()).get("avatars", {}) if AUDIT.exists() else {}
    records = dict(previous)
    with ThreadPoolExecutor(max_workers=4) as pool:
        futures = [pool.submit(install, url, previous, args.fallback_proxy) for url in selected]
        for count, future in enumerate(as_completed(futures), 1):
            url, record = future.result()
            records[url] = record
            if count % 25 == 0 or count == len(futures):
                print(f"Avatars {count}/{len(futures)}", flush=True)
    # Preserve previously audited assets, but never register an incomplete/missing image set.
    registered = sorted({record["key"] for record in records.values()
                         if record.get("status") == "bundled"
                         and (ASSETS / f'AuthorAvatar_{record["key"]}.imageset/avatar.jpg').exists()})
    AUDIT.parent.mkdir(parents=True, exist_ok=True)
    AUDIT.write_text(json.dumps({"source": "public avatar URLs in existing read models", "avatars": records},
                               indent=2, sort_keys=True) + "\n")
    REGISTRY.write_text("// Generated by scripts/sync_ios_author_avatars.py. Exact source-URL hashes only.\n"
                        "enum AuthorAvatarRegistry {\n    static let keys: Set<String> = [\n"
                        + "".join(f'        "{key}",\n' for key in registered) + "    ]\n}\n")
    bundled = [records[url] for url in selected if records[url].get("status") == "bundled"]
    print(json.dumps({"sourceURLs": len(urls), "attempted": len(selected), "bundled": len(bundled),
                      "unavailable": len(selected) - len(bundled),
                      "bytes": sum(item["bytes"] for item in bundled)}, indent=2))


if __name__ == "__main__":
    main()
