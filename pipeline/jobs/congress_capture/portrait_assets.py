"""Cache identity-keyed congressional portraits in the iOS asset catalog."""

from __future__ import annotations

import argparse
from concurrent.futures import ThreadPoolExecutor, as_completed
import hashlib
import json
from pathlib import Path
import ssl
import time
from urllib.request import Request, urlopen

import certifi


def preserved_portraits(assets: Path, sources: Path) -> set[str]:
    preserved = set()
    for override in json.loads(sources.read_text()).get("bundledOverrides", []):
        subject_id = override["id"]
        if not subject_id.startswith("politician:"):
            continue
        directory = assets / ("SubjectAvatar_" + subject_id.replace(":", "_") + ".imageset")
        filename = override["filename"]
        if Path(filename).name != filename:
            raise ValueError("Invalid bundled portrait filename")
        contents = json.loads((directory / "Contents.json").read_text())
        data = (directory / filename).read_bytes()
        if contents["images"][0]["filename"] != filename or hashlib.sha256(data).hexdigest() != override["sha256"]:
            raise ValueError(f"Bundled portrait override changed: {subject_id}")
        preserved.add(subject_id)
    return preserved


def download(subject: dict) -> tuple[str, bytes]:
    subject_id = subject["id"]
    url = subject.get("avatarURL")
    if not url or not subject_id.startswith("politician:"):
        raise ValueError(f"Missing politician portrait: {subject_id}")
    context = ssl.create_default_context(cafile=certifi.where())
    request = Request(url, headers={"User-Agent": "bSmart portrait audit/1.0"})
    for attempt in range(4):
        try:
            with urlopen(request, context=context, timeout=20) as response:
                if response.headers.get_content_type() != "image/jpeg":
                    raise ValueError(f"Unexpected portrait type: {subject_id}")
                image = response.read(2_000_001)
            if len(image) < 2_000 or len(image) > 2_000_000 or not image.startswith(b"\xff\xd8"):
                raise ValueError(f"Invalid portrait image: {subject_id}")
            return subject_id, image
        except (OSError, TimeoutError):
            if attempt == 3:
                raise
            time.sleep(1 + attempt * 2)
    raise RuntimeError("unreachable")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--snapshot", type=Path,
                        default=Path("ios/BSmart/Resources/subject-activity.json"))
    parser.add_argument("--assets", type=Path,
                        default=Path("ios/BSmart/Assets.xcassets"))
    parser.add_argument("--sources", type=Path,
                        default=Path(__file__).with_name("subject_avatar_sources.json"))
    args = parser.parse_args()
    preserved = preserved_portraits(args.assets, args.sources)
    subjects = [subject for subject in json.loads(args.snapshot.read_text())["subjects"]
                if subject["kind"] == "politician" and subject["id"] not in preserved]
    images = {}
    failures = []
    with ThreadPoolExecutor(max_workers=5) as pool:
        futures = {pool.submit(download, subject): subject["id"] for subject in subjects}
        for future in as_completed(futures):
            try:
                subject_id, image = future.result()
                images[subject_id] = image
            except (OSError, TimeoutError, ValueError) as exc:
                failures.append(f"{futures[future]}: {exc}")
    if failures:
        raise RuntimeError("Portrait audit failed; no assets written:\n" + "\n".join(sorted(failures)))
    for subject_id, image in images.items():
        asset_name = "SubjectAvatar_" + subject_id.replace(":", "_")
        directory = args.assets / f"{asset_name}.imageset"
        directory.mkdir(parents=True, exist_ok=True)
        (directory / "avatar.jpg").write_bytes(image)
        (directory / "Contents.json").write_text(json.dumps({
            "images": [{"filename": "avatar.jpg", "idiom": "universal"}],
            "info": {"author": "xcode", "version": 1},
        }, indent=2) + "\n")
    print(f"Validated and bundled {len(images)} politician portraits")


if __name__ == "__main__":
    main()
