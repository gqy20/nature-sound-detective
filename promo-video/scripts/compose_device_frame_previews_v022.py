"""Create restrained device-frame and map-expansion preview stills.

The phone screenshots are kept pixel-faithful. All styling lives outside the
screen: a thin physical edge, one inner highlight and the editorial scene.
"""

from __future__ import annotations

import argparse
from pathlib import Path

from PIL import Image, ImageDraw, ImageEnhance, ImageFilter, ImageFont


W, H = 1920, 1080
PAPER = (245, 242, 233)
FOREST = (8, 27, 22)
INK = (16, 49, 39)
MINT = (91, 171, 137)
CREAM = (247, 243, 232)


def cover(image: Image.Image, width: int, height: int) -> Image.Image:
    scale = max(width / image.width, height / image.height)
    resized = image.resize(
        (round(image.width * scale), round(image.height * scale)),
        Image.Resampling.LANCZOS,
    )
    left = (resized.width - width) // 2
    top = (resized.height - height) // 2
    return resized.crop((left, top, left + width, top + height))


def get_font(size: int, weight: str = "regular") -> ImageFont.FreeTypeFont:
    root = Path.home() / "AppData/Local/Microsoft/Windows/Fonts"
    names = {
        "regular": "AlibabaPuHuiTi-3-55-Regular.ttf",
        "medium": "AlibabaPuHuiTi-3-65-Medium.ttf",
        "semibold": "AlibabaPuHuiTi-3-75-SemiBold.ttf",
    }
    return ImageFont.truetype(str(root / names[weight]), size)


def make_device(
    screenshot: Image.Image,
    screen_height: int,
    shell: tuple[int, int, int],
    screen_radius: int = 25,
    edge: int = 8,
) -> Image.Image:
    screen_width = round(screenshot.width * screen_height / screenshot.height)
    screen = screenshot.resize((screen_width, screen_height), Image.Resampling.LANCZOS).convert("RGBA")

    device = Image.new("RGBA", (screen_width + edge * 2, screen_height + edge * 2), (0, 0, 0, 0))
    draw = ImageDraw.Draw(device, "RGBA")
    outer_radius = screen_radius + edge
    draw.rounded_rectangle(
        (0, 0, device.width - 1, device.height - 1),
        radius=outer_radius,
        fill=(*shell, 255),
    )

    screen_mask = Image.new("L", (screen_width, screen_height), 0)
    ImageDraw.Draw(screen_mask).rounded_rectangle(
        (0, 0, screen_width - 1, screen_height - 1),
        radius=screen_radius,
        fill=255,
    )
    screen.putalpha(screen_mask)
    device.alpha_composite(screen, (edge, edge))

    # A single physical highlight is enough to separate glass from the edge.
    draw.rounded_rectangle(
        (edge, edge, edge + screen_width - 1, edge + screen_height - 1),
        radius=screen_radius,
        outline=(255, 255, 255, 96),
        width=1,
    )
    return device


def clean_left_column(base: Image.Image, width: int = 548) -> Image.Image:
    out = base.convert("RGBA")
    out.alpha_composite(Image.new("RGBA", (width, H), (*PAPER, 255)), (0, 0))
    return out


def light_preview(base: Image.Image, phone: Image.Image) -> Image.Image:
    frame = clean_left_column(base)
    device = make_device(phone, screen_height=904, shell=INK)
    frame.alpha_composite(device, (42, 80))
    return frame.convert("RGB")


def dark_preview(base: Image.Image, phone: Image.Image, ribbon: Image.Image) -> Image.Image:
    frame = base.convert("RGBA")
    # The dark material continues behind the device, so the ivory edge has a
    # real job: it separates the light application screen from the scene.
    dark_left = cover(ribbon.convert("RGB"), 560, H)
    dark_left = ImageEnhance.Brightness(dark_left).enhance(0.73).convert("RGBA")
    forest_tint = Image.new("RGBA", dark_left.size, (*FOREST, 138))
    dark_left = Image.alpha_composite(dark_left, forest_tint)
    frame.alpha_composite(dark_left, (0, 0))
    device = make_device(phone, screen_height=904, shell=CREAM)
    frame.alpha_composite(device, (42, 80))
    return frame.convert("RGB")


def toned_map(map_source: Image.Image, relief: Image.Image) -> Image.Image:
    map_plate = cover(map_source.convert("RGB"), W, H)
    map_plate = ImageEnhance.Color(map_plate).enhance(0.46)
    map_plate = ImageEnhance.Contrast(map_plate).enhance(0.88)
    map_plate = Image.blend(map_plate, Image.new("RGB", (W, H), (82, 117, 102)), 0.30)

    relief_plate = cover(relief.convert("RGB"), W, H)
    relief_plate = ImageEnhance.Contrast(relief_plate).enhance(0.72)
    return Image.blend(map_plate, relief_plate, 0.18).convert("RGBA")


def expansion_preview(phone: Image.Image, map_source: Image.Image, relief: Image.Image) -> Image.Image:
    map_plate = toned_map(map_source, relief)
    frame = map_plate.copy()

    # A paper-colored left field retains the product context. Its softly cut
    # edge, rather than a connector arrow, is the transition into the map.
    paper_mask = Image.new("L", (W, H), 0)
    mask_draw = ImageDraw.Draw(paper_mask)
    mask_draw.polygon(((0, 0), (610, 0), (700, 155), (566, 334), (670, 596),
                       (560, 830), (626, H), (0, H)), fill=255)
    paper_mask = paper_mask.filter(ImageFilter.GaussianBlur(18))
    paper_layer = Image.new("RGBA", (W, H), (*PAPER, 255))
    paper_layer.putalpha(paper_mask)
    frame.alpha_composite(paper_layer)

    device = make_device(phone, screen_height=904, shell=INK)
    device_x, device_y = 42, 80
    frame.alpha_composite(device, (device_x, device_y))

    # The source screenshot is 1080x2400. Its map occupies roughly y=360..900.
    # These rings originate from that on-screen map and continue into 16:9.
    edge = 8
    scale = 904 / phone.height
    map_center_x = device_x + edge + round(phone.width * 0.50 * scale)
    map_center_y = device_y + edge + round(650 * scale)
    overlay = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    draw = ImageDraw.Draw(overlay, "RGBA")
    for rx, ry, alpha, width in (
        (236, 128, 132, 2),
        (396, 215, 90, 2),
        (592, 324, 54, 1),
    ):
        draw.ellipse(
            (map_center_x - rx, map_center_y - ry, map_center_x + rx, map_center_y + ry),
            outline=(*MINT, alpha),
            width=width,
        )
    frame.alpha_composite(overlay)

    title = get_font(42, "semibold")
    label = get_font(20, "medium")
    draw = ImageDraw.Draw(frame, "RGBA")
    draw.text((730, 96), "地图，从屏幕里展开。", font=title, fill=(*CREAM, 242))
    draw.text((734, 158), "真实界面  ·  连续空间  ·  同一份声音线索", font=label, fill=(*CREAM, 164))
    return frame.convert("RGB")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--phone", type=Path, required=True)
    parser.add_argument("--assist-phone", type=Path, required=True)
    parser.add_argument("--map", dest="map_source", type=Path, required=True)
    parser.add_argument("--relief", type=Path, required=True)
    parser.add_argument("--ribbon", type=Path, required=True)
    parser.add_argument("--light-base", type=Path, required=True)
    parser.add_argument("--dark-base", type=Path, required=True)
    parser.add_argument("--output-dir", type=Path, required=True)
    args = parser.parse_args()

    for path in (
        args.phone,
        args.assist_phone,
        args.map_source,
        args.relief,
        args.ribbon,
        args.light_base,
        args.dark_base,
    ):
        if not path.exists():
            raise SystemExit(f"Missing input: {path}")
    args.output_dir.mkdir(parents=True, exist_ok=True)

    phone = Image.open(args.phone).convert("RGB")
    assist_phone = Image.open(args.assist_phone).convert("RGB")
    map_source = Image.open(args.map_source).convert("RGB")
    relief = Image.open(args.relief).convert("RGB")
    ribbon = Image.open(args.ribbon).convert("RGB")
    light_base = Image.open(args.light_base).convert("RGB")
    dark_base = Image.open(args.dark_base).convert("RGB")

    light_preview(light_base, phone).save(
        args.output_dir / "01-light-editorial-frame-v022.png", quality=96
    )
    dark_preview(dark_base, assist_phone, ribbon).save(
        args.output_dir / "02-dark-editorial-frame-v022.png", quality=96
    )
    expansion_preview(phone, map_source, relief).save(
        args.output_dir / "03-map-expansion-state-v022.png", quality=96
    )


if __name__ == "__main__":
    main()
