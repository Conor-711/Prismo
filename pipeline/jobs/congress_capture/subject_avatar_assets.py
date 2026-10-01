"""Bundle verified celebrity portraits and institutional marks for offline iOS use."""

from __future__ import annotations

import argparse
from concurrent.futures import ThreadPoolExecutor, as_completed
from io import BytesIO
import json
from pathlib import Path
import time

from PIL import Image, ImageOps, UnidentifiedImageError
import requests


MAX_DOWNLOAD_BYTES = 4_000_000
IMAGE_SIZE = 320


def asset_name(subject_id: str) -> str:
    return "SubjectAvatar_" + subject_id.replace(":", "_").replace("-", "_")


def render_avatar(data: bytes, kind: str) -> bytes:
    if len(data) > MAX_DOWNLOAD_BYTES:
        raise ValueError("Image exceeds download limit")
    try:
        with Image.open(BytesIO(data)) as source:
            source.load()
            minimum_height = 24 if kind == "celebrity" else 8
            if source.width < 24 or source.height < minimum_height:
                raise ValueError("Image resolution is too small")
            source = ImageOps.exif_transpose(source)
            if kind == "celebrity":
                image = ImageOps.fit(source.convert("RGB"), (IMAGE_SIZE, IMAGE_SIZE),
                                     method=Image.Resampling.LANCZOS, centering=(0.5, 0.3))
            else:
                image = Image.new("RGB", (IMAGE_SIZE, IMAGE_SIZE), "#f7f8f7")
                mark = source.convert("RGBA")
                mark.thumbnail((280, 280), Image.Resampling.LANCZOS)
                x = (IMAGE_SIZE - mark.width) // 2
                y = (IMAGE_SIZE - mark.height) // 2
                image.paste(mark, (x, y), mark)
    except UnidentifiedImageError as exc:
        raise ValueError("Unrecognized image") from exc
    output = BytesIO()
    image.save(output, format="JPEG", quality=85, optimize=True)
    return output.getvalue()


def fetch_avatar(subject: dict) -> tuple[str, bytes]:
    url = subject["url"]
    for attempt in range(4):
        try:
            response = requests.get(url, timeout=25, headers={
                "User-Agent": "bSmart subject image audit/1.0 (https://bsmart.today)",
            })
            if response.status_code in (429, 500, 502, 503, 504):
                raise requests.RequestException(f"HTTP {response.status_code}")
            response.raise_for_status()
            if not response.headers.get("Content-Type", "").lower().startswith("image/"):
                raise ValueError("Response is not an image")
            return subject["id"], render_avatar(response.content, subject["kind"])
        except requests.RequestException:
            if attempt == 3:
                raise
            time.sleep(2 ** attempt)
    raise RuntimeError("unreachable")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--snapshot", type=Path,
                        default=Path("ios/BSmart/Resources/subject-activity.json"))
    parser.add_argument("--sources", type=Path,
                        default=Path(__file__).with_name("subject_avatar_sources.json"))
    parser.add_argument("--assets", type=Path,
                        default=Path("ios/BSmart/Assets.xcassets"))
    args = parser.parse_args()
    subjects = json.loads(args.snapshot.read_text())["subjects"]
    sources = {entry["id"]: entry for entry in json.loads(args.sources.read_text())["subjects"]}
    missing = []
    for subject in subjects:
        if subject["kind"] not in ("celebrity", "institution"):
            continue
        directory = args.assets / f"{asset_name(subject['id'])}.imageset"
        if directory.exists():
            continue
        source = sources.get(subject["id"])
        if source is None or not source.get("url"):
            raise ValueError(f"No image source for {subject['id']}")
        missing.append({**source, "kind": subject["kind"]})

    images: dict[str, bytes] = {}
    failures = []
    with ThreadPoolExecutor(max_workers=3) as pool:
        futures = {pool.submit(fetch_avatar, source): source["id"] for source in missing}
        for future in as_completed(futures):
            try:
                subject_id, image = future.result()
                images[subject_id] = image
            except (requests.RequestException, ValueError) as exc:
                failures.append(f"{futures[future]}: {exc}")

    for subject_id, image in images.items():
        directory = args.assets / f"{asset_name(subject_id)}.imageset"
        directory.mkdir(parents=True, exist_ok=True)
        (directory / "avatar.jpg").write_bytes(image)
        (directory / "Contents.json").write_text(json.dumps({
            "images": [{"filename": "avatar.jpg", "idiom": "universal"}],
            "info": {"author": "xcode", "version": 1},
        }, indent=2) + "\n")
    print(f"Bundled {len(images)} celebrity/institution avatars")
    if failures:
        raise RuntimeError("Avatar downloads failed:\n" + "\n".join(sorted(failures)))


if __name__ == "__main__":
    main()
