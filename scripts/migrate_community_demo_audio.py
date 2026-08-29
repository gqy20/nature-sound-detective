"""Move the six CC0 community demo clips to first-party object storage.

The migration uploads each unique source once, then updates only the seeded
``demo-2026-*`` rows in Neon. Run without ``--apply`` to preview the plan.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re

import httpx
import psycopg
from dotenv import load_dotenv
from vercel.blob import put

from scripts.seed_community_demo import CC0_AUDIO, DEMO_OWNER_HASH, DEMO_POSTS


def _source_id(url: str) -> str:
    match = re.search(r"/previews/\d+/(\d+)_", url)
    if match is None:
        raise ValueError(f"无法从示例音频地址提取 Freesound ID：{url}")
    return match.group(1)


def _download(url: str) -> bytes:
    with httpx.Client(timeout=httpx.Timeout(60, connect=15), follow_redirects=True) as client:
        response = client.get(url)
        response.raise_for_status()
        payload = response.content
    if len(payload) < 1_024:
        raise ValueError(f"示例音频下载结果过小：{url}")
    return payload


def migrate(*, database_url: str, blob_token: str, apply: bool) -> None:
    unique_sources = {url: credit for url, credit in CC0_AUDIO.values()}
    print(
        f"Migration plan: {len(unique_sources)} CC0 clips, "
        f"{len(DEMO_POSTS)} demo rows"
    )
    if not apply:
        print("Preview only. Re-run with --apply to upload and update Neon.")
        return

    blob_urls: dict[str, str] = {}
    asset_metadata: dict[str, dict[str, object]] = {}
    for source_url, credit in unique_sources.items():
        source_id = _source_id(source_url)
        payload = _download(source_url)
        digest = hashlib.sha256(payload).hexdigest()
        blob = put(
            f"community/demo/freesound-{source_id}-lq.mp3",
            payload,
            access="public",
            content_type="audio/mpeg",
            add_random_suffix=False,
            overwrite=True,
            cache_control_max_age=31_536_000,
            token=blob_token,
        )
        blob_urls[source_url] = blob.url
        asset_metadata[source_url] = {
            "audio_source": credit,
            "source_url": source_url,
            "storage": "vercel_blob",
            "sha256": digest,
            "byte_length": len(payload),
        }
        print(f"Uploaded Freesound #{source_id}: {len(payload)} bytes")

    updated = 0
    with psycopg.connect(database_url) as connection, connection.cursor() as cursor:
        for post in DEMO_POSTS:
            metadata = asset_metadata[post.audio_url]
            cursor.execute(
                """UPDATE community_posts
                   SET audio_url=%s,
                       model_snapshot=COALESCE(model_snapshot, '{}'::jsonb) || %s::jsonb
                   WHERE id=%s AND owner_hash=%s""",
                (
                    blob_urls[post.audio_url],
                    json.dumps(metadata, ensure_ascii=False),
                    post.id,
                    DEMO_OWNER_HASH,
                ),
            )
            updated += cursor.rowcount
        if updated != len(DEMO_POSTS):
            raise RuntimeError(
                f"预计更新 {len(DEMO_POSTS)} 条体验记录，实际更新 {updated} 条"
            )
        connection.commit()
    print(f"Updated {updated} Neon demo rows.")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--apply", action="store_true")
    args = parser.parse_args()
    load_dotenv()
    database_url = os.getenv("DATABASE_URL", "").strip()
    blob_token = os.getenv("BLOB_READ_WRITE_TOKEN", "").strip()
    if not database_url:
        raise SystemExit("DATABASE_URL is not configured")
    if not blob_token:
        raise SystemExit("BLOB_READ_WRITE_TOKEN is not configured")
    migrate(database_url=database_url, blob_token=blob_token, apply=args.apply)


if __name__ == "__main__":
    main()
