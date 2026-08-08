"""Download openly licensed representative images for challenge species.

The official catalog remains the source of truth. Entries without an
unambiguous scientific name are skipped, and every downloaded image receives a
license sidecar. Wikimedia Commons is used because its API exposes machine-
readable authorship and reuse terms; the images are normalized by
``prepare_species_image.py`` before they enter the Flutter bundle.
"""

from __future__ import annotations

import argparse
import html
import json
import re
import subprocess
import tempfile
import time
import urllib.parse
import urllib.error
import urllib.request
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
DEFAULT_CONFIG = ROOT / "ml/configs/challenge_2026_species.json"
DEFAULT_OUTPUT = ROOT / "mobile/assets/species"
DEFAULT_DART = ROOT / "mobile/lib/core/models/species_media_catalog.g.dart"
USER_AGENT = "NatureSoundDetective/1.0 (challenge demo; species media sync)"
ALLOWED_LICENSES = ("CC0", "CC BY", "CC BY-SA", "PUBLIC DOMAIN")
PREFER_INATURALIST = {
    "Mecopoda elongata",
    "Cryptotympana atrata",
    "Teleogryllus emma",
    "Streeyola mongolica",
    "Velarifictorus micado",
    "Pelophylax nigromaculatus",
    "Nidirana mangveni",
    "Microhyla fissipes",
    "Fejervarya multistriata",
}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--config", type=Path, default=DEFAULT_CONFIG)
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT)
    parser.add_argument("--dart-output", type=Path, default=DEFAULT_DART)
    parser.add_argument("--refresh", action="store_true")
    parser.add_argument("--only", action="append", default=[])
    return parser.parse_args()


def api_json(base: str, params: dict[str, str]) -> dict:
    url = f"{base}?{urllib.parse.urlencode(params)}"
    for attempt in range(4):
        try:
            request = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
            with urllib.request.urlopen(request, timeout=45) as response:
                result = json.load(response)
            time.sleep(0.8)
            return result
        except OSError as error:
            if attempt == 3:
                raise
            retry_after = None
            if isinstance(error, urllib.error.HTTPError):
                retry_after = error.headers.get("Retry-After")
            delay = float(retry_after) if retry_after else 8.0 * (attempt + 1)
            time.sleep(delay)
    raise AssertionError("unreachable")


def wikidata_entity(scientific_name: str) -> tuple[str, dict]:
    search = api_json(
        "https://www.wikidata.org/w/api.php",
        {
            "action": "wbsearchentities",
            "search": scientific_name,
            "language": "en",
            "type": "item",
            "limit": "10",
            "format": "json",
        },
    )
    ids = [item["id"] for item in search.get("search", [])]
    if not ids:
        raise RuntimeError(f"No Wikidata item found for {scientific_name}")
    entities = api_json(
        "https://www.wikidata.org/w/api.php",
        {
            "action": "wbgetentities",
            "ids": "|".join(ids),
            "props": "claims",
            "format": "json",
        },
    ).get("entities", {})
    for entity_id in ids:
        entity = entities.get(entity_id, {})
        for claim in entity.get("claims", {}).get("P225", []):
            value = claim.get("mainsnak", {}).get("datavalue", {}).get("value")
            if isinstance(value, str) and value.casefold() == scientific_name.casefold():
                return entity_id, entity
    raise RuntimeError(f"No exact taxon match found for {scientific_name}")


def commons_media(
    entity_id: str, entity: dict, scientific_name: str
) -> dict[str, str]:
    claims = entity.get("claims", {}).get("P18", [])
    candidates = [
        f"File:{claim['mainsnak']['datavalue']['value']}" for claim in claims
    ]
    search = api_json(
        "https://commons.wikimedia.org/w/api.php",
        {
            "action": "query",
            "generator": "search",
            "gsrsearch": f'"{scientific_name}" filetype:bitmap',
            "gsrnamespace": "6",
            "gsrlimit": "30",
            "prop": "imageinfo",
            "iiprop": "url|extmetadata",
            "iiurlwidth": "1600",
            "format": "json",
        },
    )
    pages = search.get("query", {}).get("pages", {}).values()
    searched = sorted(
        pages,
        key=lambda page: page.get("index", 10_000),
    )
    by_title = {page["title"]: page for page in searched}
    ordered = [by_title[title] for title in candidates if title in by_title]
    ordered.extend(page for page in searched if page not in ordered)
    unsuitable = ("map", "range", "distribution", "egg", "drawing", "illustration")
    for page in ordered:
        title = page.get("title", "").casefold()
        if any(word in title for word in unsuitable):
            continue
        image_info = page.get("imageinfo") or []
        if not image_info:
            continue
        info = image_info[0]
        metadata = info.get("extmetadata", {})
        license_name = metadata.get("LicenseShortName", {}).get("value", "").strip()
        if not license_name.upper().startswith(ALLOWED_LICENSES):
            continue
        artist_html = metadata.get("Artist", {}).get("value", "Unknown contributor")
        artist = clean_html(artist_html) or "Unknown contributor"
        return {
            "author": artist,
            "license": license_name,
            "download_url": info.get("thumburl", info["url"]),
            "source_url": info["descriptionurl"],
            "source_name": "Wikimedia Commons",
            "wikidata_url": f"https://www.wikidata.org/wiki/{entity_id}",
        }
    raise RuntimeError(f"No compatible Commons image found for {scientific_name}")


def inaturalist_media(scientific_name: str) -> dict[str, str]:
    taxa = api_json(
        "https://api.inaturalist.org/v1/taxa",
        {
            "q": scientific_name,
            "rank": "species",
            "per_page": "20",
        },
    ).get("results", [])
    taxon = next(
        (
            item
            for item in taxa
            if item.get("name", "").casefold() == scientific_name.casefold()
        ),
        None,
    )
    if taxon is None:
        raise RuntimeError(f"No exact iNaturalist taxon found for {scientific_name}")
    taxon_id = str(taxon["id"])
    observations = api_json(
        "https://api.inaturalist.org/v1/observations",
        {
            "taxon_id": taxon_id,
            "photos": "true",
            "photo_license": "cc0,cc-by,cc-by-sa",
            "quality_grade": "research",
            "order_by": "votes",
            "per_page": "20",
        },
    ).get("results", [])
    photos = [
        photo
        for observation in observations
        for photo in observation.get("photos", [])
    ]
    default_photo = taxon.get("default_photo")
    if isinstance(default_photo, dict):
        photos.append(default_photo)
    license_names = {
        "cc0": "CC0 1.0",
        "cc-by": "CC BY 4.0",
        "cc-by-sa": "CC BY-SA 4.0",
    }
    for photo in photos:
        license_code = (photo.get("license_code") or "").casefold()
        license_name = license_names.get(license_code)
        if license_name is None:
            continue
        photo_url = photo.get("large_url") or photo.get("medium_url") or photo.get("url")
        if not photo_url:
            continue
        photo_url = photo_url.replace("/square.", "/large.")
        return {
            "author": clean_attribution(
                photo.get("attribution") or "iNaturalist contributor"
            ),
            "license": license_name,
            "download_url": photo_url,
            "source_url": f"https://www.inaturalist.org/photos/{photo['id']}",
            "source_name": "iNaturalist",
            "wikidata_url": f"https://www.inaturalist.org/taxa/{taxon_id}",
        }
    raise RuntimeError(f"No compatible iNaturalist photo found for {scientific_name}")


def clean_html(value: str) -> str:
    without_tags = re.sub(r"<[^>]+>", " ", value)
    return " ".join(html.unescape(without_tags).split())


def clean_attribution(value: str) -> str:
    cleaned = clean_html(value)
    match = re.match(
        r"^(?:\(c\)|©)\s*(.+?),\s*some rights reserved.*$",
        cleaned,
        flags=re.IGNORECASE,
    )
    return match.group(1).strip() if match else cleaned


def download(url: str, destination: Path) -> None:
    for attempt in range(4):
        try:
            request = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
            with urllib.request.urlopen(request, timeout=90) as response:
                destination.write_bytes(response.read())
            return
        except OSError:
            if attempt == 3:
                raise
            time.sleep(1.5 * (attempt + 1))


def prepare_image(source: Path, output: Path, species: dict, media: dict[str, str]) -> None:
    subprocess.run(
        [
            "python",
            str(ROOT / "scripts/prepare_species_image.py"),
            "--input",
            str(source),
            "--output",
            str(output),
            "--scientific-name",
            species["scientific_name"],
            "--author",
            media["author"],
            "--license",
            media["license"],
            "--source-url",
            media["source_url"],
        ],
        check=True,
    )
    sidecar = output.with_suffix(".license.json")
    sidecar.write_text(
        json.dumps(
            {
                "taxon_id": species["taxon_id"],
                "name_zh": species["name_zh"],
                "scientific_name": species["scientific_name"],
                "author": media["author"],
                "license": media["license"],
                "source_name": media["source_name"],
                "source_url": media["source_url"],
                "reference_url": media["wikidata_url"],
                "wikidata_url": media["wikidata_url"],
                "asset": output.name,
            },
            ensure_ascii=False,
            indent=2,
        )
        + "\n",
        encoding="utf-8",
    )


def dart_string(value: str) -> str:
    return value.replace("\\", "\\\\").replace("'", "\\'")


def generate_dart(output: Path, species: list[dict], assets: Path) -> None:
    lines = [
        "// Generated by scripts/sync_challenge_species_images.py.",
        "// Do not edit by hand.",
        "part of 'species_media.dart';",
        "",
        "const Map<String, SpeciesMedia> generatedSpeciesMedia = {",
    ]
    for item in species:
        scientific_name = item.get("scientific_name")
        if not scientific_name:
            continue
        sidecar_path = assets / f"{item['taxon_id']}.license.json"
        if not sidecar_path.is_file():
            continue
        media = json.loads(sidecar_path.read_text(encoding="utf-8"))
        cleaned_author = clean_attribution(media["author"])
        if cleaned_author != media["author"]:
            media["author"] = cleaned_author
            sidecar_path.write_text(
                json.dumps(media, ensure_ascii=False, indent=2) + "\n",
                encoding="utf-8",
            )
        lookup_names = {scientific_name.casefold()}
        birdnet_name = item.get("birdnet_scientific_name")
        if birdnet_name:
            lookup_names.add(birdnet_name.casefold())
        for lookup_name in sorted(lookup_names):
            key = dart_string(lookup_name)
            lines.extend(
                [
                    f"  '{key}': SpeciesMedia(",
                    f"    assetPath: 'assets/species/{dart_string(media['asset'])}',",
                    f"    author: '{dart_string(media['author'])}',",
                    f"    license: '{dart_string(media['license'])}',",
                    f"    sourceName: '{dart_string(media.get('source_name', 'Wikimedia Commons'))}',",
                    f"    sourceUrl: '{dart_string(media['source_url'])}',",
                    f"    referenceUrl: '{dart_string(media.get('reference_url', media.get('wikidata_url', media['source_url'])))}',",
                    "  ),",
                ]
            )
    lines.extend(["};", ""])
    output.write_text("\n".join(lines), encoding="utf-8")


def main() -> None:
    args = parse_args()
    catalog = json.loads(args.config.read_text(encoding="utf-8"))
    species = catalog["classes"]
    targets = [item for item in species if item.get("scientific_name")]
    if args.only:
        selected = {value.casefold() for value in args.only}
        targets = [
            item
            for item in targets
            if item["taxon_id"].casefold() in selected
            or item["scientific_name"].casefold() in selected
        ]
    args.output.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="xykw-species-") as temporary:
        temporary_path = Path(temporary)
        for index, item in enumerate(targets, start=1):
            destination = args.output / f"{item['taxon_id']}.webp"
            sidecar = destination.with_suffix(".license.json")
            if destination.is_file() and sidecar.is_file() and not args.refresh:
                print(f"[{index}/{len(targets)}] keep {item['name_zh']}")
                continue
            print(f"[{index}/{len(targets)}] fetch {item['name_zh']}")
            scientific_name = item["scientific_name"]
            if scientific_name in PREFER_INATURALIST:
                try:
                    media = inaturalist_media(scientific_name)
                except RuntimeError as error:
                    print(f"  iNaturalist unavailable ({error}); trying Commons")
                    entity_id, entity = wikidata_entity(scientific_name)
                    media = commons_media(entity_id, entity, scientific_name)
            else:
                try:
                    entity_id, entity = wikidata_entity(scientific_name)
                    media = commons_media(entity_id, entity, scientific_name)
                except RuntimeError as error:
                    print(f"  Commons unavailable ({error}); trying iNaturalist")
                    media = inaturalist_media(scientific_name)
            source = temporary_path / f"{item['taxon_id']}.source"
            download(media["download_url"], source)
            prepare_image(source, destination, item, media)
    generate_dart(args.dart_output, species, args.output)
    print(f"Prepared {len(targets)} licensed species images")


if __name__ == "__main__":
    main()
