"""Normalize a licensed species photo for the Flutter species card.

The foreground is always fitted inside 720x450, while a blurred copy fills the
remaining canvas. This keeps the animal's head and body visible without letterbox
bars. The script never downloads an image: reviewers must supply a local source
file and explicit attribution.
"""

from __future__ import annotations

import argparse
import json
import shutil
import subprocess
from pathlib import Path


ALLOWED_LICENSE_PREFIXES = (
    "CC0",
    "CC BY ",
    "CC BY-SA ",
    "PUBLIC DOMAIN",
)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--input", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--scientific-name", required=True)
    parser.add_argument("--author", required=True)
    parser.add_argument("--license", required=True)
    parser.add_argument("--source-url", required=True)
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    if not args.input.is_file():
        raise SystemExit(f"Source image does not exist: {args.input}")
    normalized_license = args.license.strip().upper()
    if not normalized_license.startswith(ALLOWED_LICENSE_PREFIXES):
        raise SystemExit(
            "Unsupported or ambiguous license. Use CC0, CC BY, CC BY-SA, "
            "or Public Domain media only."
        )
    if not args.source_url.startswith(("https://", "http://")):
        raise SystemExit("--source-url must be an HTTP(S) URL")
    ffmpeg = shutil.which("ffmpeg")
    if ffmpeg is None:
        raise SystemExit("ffmpeg is required to normalize species images")

    args.output.parent.mkdir(parents=True, exist_ok=True)
    filter_graph = (
        "[0:v]scale=720:450:force_original_aspect_ratio=increase,"
        "crop=720:450,gblur=sigma=24[bg];"
        "[0:v]scale=720:450:force_original_aspect_ratio=decrease[fg];"
        "[bg][fg]overlay=(W-w)/2:(H-h)/2,format=yuv420p"
    )
    subprocess.run(
        [
            ffmpeg,
            "-hide_banner",
            "-loglevel",
            "error",
            "-y",
            "-i",
            str(args.input),
            "-filter_complex",
            filter_graph,
            "-frames:v",
            "1",
            "-c:v",
            "libwebp",
            "-quality",
            "82",
            str(args.output),
        ],
        check=True,
    )
    sidecar = args.output.with_suffix(".license.json")
    sidecar.write_text(
        json.dumps(
            {
                "scientific_name": args.scientific_name,
                "author": args.author,
                "license": args.license,
                "source_url": args.source_url,
                "asset": args.output.name,
            },
            ensure_ascii=False,
            indent=2,
        )
        + "\n",
        encoding="utf-8",
    )
    print(f"Prepared {args.output} and {sidecar}")


if __name__ == "__main__":
    main()
