"""Compose exact-product styleframes from generated material components."""

from __future__ import annotations

import argparse
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw, ImageEnhance, ImageFilter, ImageFont


W, H = 1920, 1080
PAPER = (245, 242, 233)
FOREST = (8, 27, 22)
INK = (16, 49, 39)
MINT = (91, 171, 137)
AMBER = (222, 165, 81)
CREAM = (247, 243, 232)


def cover(image: Image.Image, width: int, height: int) -> Image.Image:
    scale = max(width / image.width, height / image.height)
    resized = image.resize((round(image.width * scale), round(image.height * scale)), Image.Resampling.LANCZOS)
    left = (resized.width - width) // 2
    top = (resized.height - height) // 2
    return resized.crop((left, top, left + width, top + height))


def fonts() -> dict[str, ImageFont.FreeTypeFont]:
    root = Path.home() / "AppData/Local/Microsoft/Windows/Fonts"
    return {
        "hero": ImageFont.truetype(str(root / "AlibabaPuHuiTi-3-75-SemiBold.ttf"), 50),
        "body": ImageFont.truetype(str(root / "AlibabaPuHuiTi-3-55-Regular.ttf"), 26),
        "label": ImageFont.truetype(str(root / "AlibabaPuHuiTi-3-65-Medium.ttf"), 21),
        "small": ImageFont.truetype(str(root / "AlibabaPuHuiTi-3-55-Regular.ttf"), 17),
        "number": ImageFont.truetype(str(root / "AlibabaPuHuiTi-3-75-SemiBold.ttf"), 40),
    }


def paste_phone(frame: Image.Image, source: Image.Image, x: int = 48, y: int = 80, height: int = 920) -> int:
    width = round(source.width * height / source.height)
    phone = source.resize((width, height), Image.Resampling.LANCZOS).convert("RGBA")
    frame.alpha_composite(phone, (x, y))
    draw = ImageDraw.Draw(frame, "RGBA")
    draw.rectangle((x - 1, y - 1, x + width + 1, y + height + 1), outline=(143, 153, 145, 62), width=1)
    return x + width


def organic_map_mask() -> Image.Image:
    mask = Image.new("L", (W, H), 0)
    draw = ImageDraw.Draw(mask)
    draw.polygon(((650, 255), (1060, 145), (1540, 125), (1920, 215), (1920, 1080),
                  (690, 1080), (620, 880), (680, 630)), fill=225)
    draw.ellipse((760, 95, 1990, 1095), fill=238)
    return mask.filter(ImageFilter.GaussianBlur(22))


def compose_map_styleframe(phone: Image.Image, map_source: Image.Image, relief: Image.Image,
                           ripples: Image.Image, f) -> Image.Image:
    relief_plate = cover(relief.convert("RGB"), W, H)
    relief_plate = ImageEnhance.Contrast(relief_plate).enhance(0.72)
    frame = Image.blend(Image.new("RGB", (W, H), PAPER), relief_plate, 0.48).convert("RGBA")

    map_plate = cover(map_source.convert("RGB"), W, H)
    map_plate = ImageEnhance.Color(map_plate).enhance(0.34)
    map_plate = ImageEnhance.Contrast(map_plate).enhance(0.82)
    map_tint = Image.new("RGB", (W, H), (96, 127, 113))
    map_plate = Image.blend(map_plate, map_tint, 0.34).convert("RGBA")
    map_plate.putalpha(organic_map_mask())
    frame.alpha_composite(map_plate)

    # The generated ripple plate contributes optical texture only. Exact map
    # and interface information remain in the real source layers.
    ripple_plate = cover(ripples.convert("RGB"), W, H)
    screened = ImageChops.screen(frame.convert("RGB"), ripple_plate).convert("RGBA")
    right_mask = Image.new("L", (W, H), 0)
    ImageDraw.Draw(right_mask).rectangle((560, 210, W, H), fill=112)
    screened.putalpha(right_mask)
    frame.alpha_composite(screened)

    # Restore a clean product column after all material treatments.
    clean_left = Image.new("RGBA", (548, H), (*PAPER, 255))
    frame.alpha_composite(clean_left, (0, 0))
    phone_right = paste_phone(frame, phone)
    draw = ImageDraw.Draw(frame, "RGBA")
    draw.line((phone_right + 50, 92, phone_right + 50, 988), fill=(50, 79, 68, 54), width=1)

    draw.text((610, 90), "声音，正在成为杭州的另一张地图。", font=f["hero"], fill=(*INK, 255))
    draw.line((612, 170, 990, 170), fill=(*MINT, 140), width=2)
    draw.text((610, 962), "12", font=f["number"], fill=(*MINT, 255))
    draw.text((674, 978), "条今日新声", font=f["label"], fill=(*INK, 210))
    draw.text((904, 962), "04", font=f["number"], fill=(*AMBER, 255))
    draw.text((976, 978), "条等待协助", font=f["label"], fill=(*INK, 210))
    draw.text((1578, 995), "真实地图 · 匿名声景", font=f["small"], fill=(*CREAM, 165))
    return frame.convert("RGB")


def compose_relay_styleframe(phone: Image.Image, ribbon: Image.Image, f) -> Image.Image:
    frame = Image.new("RGBA", (W, H), (*FOREST, 255))
    ribbon_plate = cover(ribbon.convert("RGB"), W, H)
    ribbon_plate = ImageEnhance.Contrast(ribbon_plate).enhance(1.04)
    frame.alpha_composite(ribbon_plate.convert("RGBA"))

    # Give the product its own calm paper field while allowing the memory
    # ribbon to remain the sole visual protagonist on the right.
    frame.alpha_composite(Image.new("RGBA", (520, H), (*PAPER, 255)), (0, 0))
    phone_right = paste_phone(frame, phone)
    draw = ImageDraw.Draw(frame, "RGBA")
    draw.line((520, 0, 520, H), fill=(*CREAM, 40), width=1)

    draw.text((625, 88), "声音，会抵达下一双耳朵。", font=f["hero"], fill=(*CREAM, 250))
    draw.line((627, 168, 904, 168), fill=(*AMBER, 165), width=2)

    start = (645, 540)
    end = (1775, 654)
    for x, y, label, anchor in (
        (*start, "留下原声", "la"),
        (*end, "接着听", "ra"),
    ):
        draw.ellipse((x - 10, y - 10, x + 10, y + 10), outline=(*AMBER, 215), width=2)
        draw.ellipse((x - 3, y - 3, x + 3, y + 3), fill=(*CREAM, 235))
        label_x = x + 18 if anchor == "la" else x - 18
        draw.text((label_x, y + 24), label, font=f["label"], anchor=anchor, fill=(*CREAM, 205))

    draw.text((1390, 985), "共同判断 · 补充现场证据", font=f["small"], fill=(*CREAM, 150))
    return frame.convert("RGB")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--phone", type=Path, required=True)
    parser.add_argument("--assist-phone", type=Path, required=True)
    parser.add_argument("--map", dest="map_source", type=Path, required=True)
    parser.add_argument("--relief", type=Path, required=True)
    parser.add_argument("--ripples", type=Path, required=True)
    parser.add_argument("--ribbon", type=Path, required=True)
    parser.add_argument("--output-dir", type=Path, required=True)
    args = parser.parse_args()
    args.output_dir.mkdir(parents=True, exist_ok=True)

    inputs = (args.phone, args.assist_phone, args.map_source, args.relief, args.ripples, args.ribbon)
    for path in inputs:
        if not path.exists():
            raise SystemExit(f"Missing input: {path}")

    f = fonts()
    phone = Image.open(args.phone).convert("RGB")
    assist_phone = Image.open(args.assist_phone).convert("RGB")
    map_source = Image.open(args.map_source).convert("RGB")
    relief = Image.open(args.relief).convert("RGB")
    ripples = Image.open(args.ripples).convert("RGB")
    ribbon = Image.open(args.ribbon).convert("RGB")

    compose_map_styleframe(phone, map_source, relief, ripples, f).save(
        args.output_dir / "S11-component-composite-v021.png", quality=96
    )
    compose_relay_styleframe(assist_phone, ribbon, f).save(
        args.output_dir / "S12-component-composite-v021.png", quality=96
    )


if __name__ == "__main__":
    main()
