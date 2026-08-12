"""Render a cinematic 16:9 Hangzhou soundscape map.

OpenStreetMap stays geographically recognizable; camera movement, grading,
sound nodes, ripples, routes and UI are generated deterministically in code.
"""

from __future__ import annotations

import argparse
import math
import subprocess
from pathlib import Path

from PIL import Image, ImageDraw, ImageEnhance, ImageFilter, ImageFont


WIDTH, HEIGHT = 1920, 1080
OUT_WIDTH, OUT_HEIGHT = WIDTH, HEIGHT
SCALE = 1.0
CREAM = (247, 242, 226)
MINT = (128, 224, 174)
AMBER = (245, 177, 88)


def clamp(value: float, low: float = 0.0, high: float = 1.0) -> float:
    return max(low, min(high, value))


def smoothstep(value: float) -> float:
    value = clamp(value)
    return value * value * (3.0 - 2.0 * value)


def window(t: float, start: float, end: float, fade: float = 0.6) -> float:
    return smoothstep((t - start) / fade) * smoothstep((end - t) / fade)


def load_font(path: Path, size: int) -> ImageFont.FreeTypeFont:
    return ImageFont.truetype(str(path), size=round(size * SCALE))


def scaled(value):
    if isinstance(value, (tuple, list)):
        return type(value)(scaled(item) for item in value)
    if isinstance(value, (int, float)):
        return value * SCALE
    return value


class ScaledDraw:
    def __init__(self, image):
        self.draw = ImageDraw.Draw(image)

    def _width(self, kwargs):
        if "width" in kwargs:
            kwargs["width"] = max(1, round(kwargs["width"] * SCALE))
        return kwargs

    def line(self, xy, **kwargs):
        return self.draw.line(scaled(xy), **self._width(kwargs))

    def ellipse(self, xy, **kwargs):
        return self.draw.ellipse(scaled(xy), **self._width(kwargs))

    def rectangle(self, xy, **kwargs):
        return self.draw.rectangle(scaled(xy), **self._width(kwargs))

    def rounded_rectangle(self, xy, **kwargs):
        if "radius" in kwargs:
            kwargs["radius"] = round(kwargs["radius"] * SCALE)
        return self.draw.rounded_rectangle(scaled(xy), **self._width(kwargs))

    def text(self, xy, text, **kwargs):
        return self.draw.text(scaled(xy), text, **kwargs)

    def textbbox(self, xy, text, **kwargs):
        box = self.draw.textbbox(scaled(xy), text, **kwargs)
        return tuple(value / SCALE for value in box)


def draw_ctx(image):
    return ScaledDraw(image)


def canvas(color=(0, 0, 0, 0)):
    return Image.new("RGBA", (OUT_WIDTH, OUT_HEIGHT), color)


def cover(image: Image.Image, width: int, height: int) -> Image.Image:
    scale = max(width / image.width, height / image.height)
    resized = image.resize(
        (round(image.width * scale), round(image.height * scale)),
        Image.Resampling.LANCZOS,
    )
    left = (resized.width - width) // 2
    top = (resized.height - height) // 2
    return resized.crop((left, top, left + width, top + height))


def build_base(source: Path) -> Image.Image:
    image = cover(Image.open(source).convert("RGB"), round(2380*SCALE), round(1340*SCALE))
    image = ImageEnhance.Color(image).enhance(0.72)
    image = ImageEnhance.Contrast(image).enhance(0.90)
    return Image.blend(image, Image.new("RGB", image.size, (20, 62, 51)), 0.32)


def map_frame(base: Image.Image, t: float, duration: float) -> Image.Image:
    # Keep the geographic layer locked. Motion comes from the data overlays;
    # a fixed camera avoids the sub-pixel shimmer visible on street labels.
    crop_w = round(2220 * SCALE)
    crop_h = round(crop_w * HEIGHT / WIDTH)
    cx = base.width * 0.49
    cy = base.height * 0.50
    left, top = round(cx - crop_w / 2), round(cy - crop_h / 2)
    # `base` is already built at physical output scale. Cropping it with a
    # second SCALE multiplier pushed the 4K crop outside the image and made
    # Pillow fill most of the frame with black.
    crop = base.crop((left, top, left + crop_w, top + crop_h))
    return crop.resize((OUT_WIDTH, OUT_HEIGHT), Image.Resampling.LANCZOS).convert("RGBA")


def build_vignette() -> Image.Image:
    small = Image.new("RGBA", (240, 135), (0, 0, 0, 0))
    px = small.load()
    for y in range(small.height):
        for x in range(small.width):
            nx = (x - small.width / 2) / (small.width / 2)
            ny = (y - small.height / 2) / (small.height / 2)
            edge = clamp((nx * nx + ny * ny - 0.18) / 0.90)
            px[x, y] = (6, 28, 24, round(25 + 102 * edge + 22 * y / small.height))
    return small.resize((OUT_WIDTH, OUT_HEIGHT), Image.Resampling.BILINEAR)


def rounded_panel(layer, box, fill, outline=None, radius=28):
    draw_ctx(layer).rounded_rectangle(
        box, radius=radius, fill=fill, outline=outline, width=2
    )


def point_position(xy: tuple[int, int], t: float, duration: float) -> tuple[int, int]:
    """Return stable logical screen coordinates for a locked map camera."""
    return xy


def draw_geo_overlay(layer: Image.Image, t: float) -> None:
    """Quiet cartographic texture that adds depth without obscuring street data."""
    draw = draw_ctx(layer)
    drift = round((t * 7) % 120)
    for x in range(-120 + drift, WIDTH + 120, 120):
        draw.line((x, 0, x, HEIGHT), fill=(*CREAM, 8), width=1)
    for y in range(-120 + drift // 2, HEIGHT + 120, 120):
        draw.line((0, y, WIDTH, y), fill=(*CREAM, 7), width=1)

    scan_y = round(((t % 6.0) / 6.0) * (HEIGHT + 220) - 110)
    glow = canvas()
    glow_draw = draw_ctx(glow)
    glow_draw.rectangle((0, scan_y - 5, WIDTH, scan_y + 5), fill=(*MINT, 22))
    layer.alpha_composite(glow.filter(ImageFilter.GaussianBlur(14*SCALE)))
    draw.line((0, scan_y, WIDTH, scan_y), fill=(*MINT, 30), width=1)


def draw_node(layer, xy, t, born, color, label, detail, fonts):
    age = t - born
    if age < 0:
        return
    appear = smoothstep(age / 0.55)
    draw = draw_ctx(layer)
    x, y = xy
    for delay, width, reach in ((0.0, 3, 76), (0.8, 2, 102)):
        if age < delay:
            continue
        phase = ((age - delay) % 2.4) / 2.4
        radius = 20 + reach * phase
        alpha = round(110 * (1 - phase) * appear)
        draw.ellipse((x-radius, y-radius, x+radius, y+radius), outline=(*color, alpha), width=width)
    glow = canvas()
    draw_ctx(glow).ellipse((x-28, y-28, x+28, y+28), fill=(*color, round(105*appear)))
    layer.alpha_composite(glow.filter(ImageFilter.GaussianBlur(16*SCALE)))
    draw.ellipse((x-9, y-9, x+9, y+9), fill=(*CREAM, round(250*appear)))
    draw.ellipse((x-5, y-5, x+5, y+5), fill=(*color, round(255*appear)))
    label_x, label_y = x + 24, y - 43
    label_box = draw.textbbox((label_x, label_y), label, font=fonts["label"])
    detail_box = draw.textbbox((label_x, label_y + 36), detail, font=fonts["detail"])
    panel_w = max(label_box[2], detail_box[2]) - label_x + 26
    rounded_panel(layer, (label_x-13, label_y-10, label_x+panel_w, label_y+72),
                  (8, 31, 27, round(208*appear)), (181, 220, 194, round(65*appear)), 18)
    draw.text((label_x, label_y), label, font=fonts["label"], fill=(*CREAM, round(255*appear)))
    draw.text((label_x, label_y+36), detail, font=fonts["detail"], fill=(*color, round(245*appear)))


def draw_route(layer, points, t):
    draw = draw_ctx(layer)
    reveal = smoothstep((t - 2.2) / 4.8)
    segments = list(zip(points, points[1:]))
    for index, (start, end) in enumerate(segments):
        local = clamp(reveal * len(segments) - index)
        if local > 0:
            destination = (round(start[0] + (end[0]-start[0])*local),
                           round(start[1] + (end[1]-start[1])*local))
            draw.line((start, destination), fill=(*MINT, 105), width=2)
            if local >= 0.98:
                flow = ((t * 0.18 + index * 0.21) % 1.0)
                bead = (round(start[0] + (end[0]-start[0])*flow),
                        round(start[1] + (end[1]-start[1])*flow))
                draw.ellipse((bead[0]-4, bead[1]-4, bead[0]+4, bead[1]+4), fill=(*MINT, 190))


def draw_ambient_node(layer, xy, t, born, color=MINT):
    """Draw a quiet unlabeled regional sound point."""
    age = t - born
    if age < 0:
        return
    appear = smoothstep(age / 0.45)
    draw = draw_ctx(layer)
    x, y = xy
    phase = (age % 3.0) / 3.0
    radius = 11 + 24 * phase
    draw.ellipse((x-radius, y-radius, x+radius, y+radius),
                 outline=(*color, round(38 * (1-phase) * appear)), width=2)
    draw.ellipse((x-7, y-7, x+7, y+7), fill=(*color, round(38*appear)))
    draw.ellipse((x-3, y-3, x+3, y+3), fill=(*CREAM, round(205*appear)))


def draw_waveform(draw, x, y, width, t, color):
    values = []
    for i in range(72):
        phase = i / 71
        envelope = math.sin(math.pi * phase) ** 0.7
        wave = math.sin(phase*13*math.pi+t*5.2) + 0.45*math.sin(phase*29*math.pi-t*3.1)
        values.append((x + phase*width, y + wave*envelope*12))
    draw.line(values, fill=color, width=3, joint="curve")


def render_frame(base, vignette, t, duration, fonts):
    frame = map_frame(base, t, duration)
    frame.alpha_composite(vignette)
    layer = canvas()
    draw = draw_ctx(layer)
    draw_geo_overlay(layer, t)
    alpha = round(255 * smoothstep(t / 0.8))
    draw.text((92, 68), "共听杭州", font=fonts["display"], fill=(*CREAM, alpha))
    draw.line((96, 154, 410, 154), fill=(*MINT, round(96*alpha/255)), width=2)

    ambient_source = (
        (245,335),(505,320),(735,255),(930,575),(1140,285),(1275,405),
        (1510,295),(1705,445),(315,705),(555,760),(790,830),(1015,745),
        (1185,625),(1470,575),(1615,810),(430,900),(900,925),(1230,875),
    )
    ambient_points = [point_position(p, t, duration) for p in ambient_source]
    ambient_colors = (MINT, (164,218,126), (112,202,223))
    for index, ambient in enumerate(ambient_points):
        draw_ambient_node(layer, ambient, t, 0.7 + index * 0.38,
                          ambient_colors[index % len(ambient_colors)])

    points = [point_position(p, t, duration) for p in ((420,520),(645,610),(1050,470),(1390,655))]
    draw_route(layer, points, t)
    draw_node(layer, points[0], t, 1.0, MINT, "西溪湿地", "白头鹎 · 07:42", fonts)
    draw_node(layer, points[1], t, 3.2, (164,218,126), "杭州植物园", "黑蚱蝉 · 09:16", fonts)
    draw_node(layer, points[2], t, 6.4, (112,202,223), "运河沿岸", "风与水 · 13:08", fonts)
    draw_node(layer, points[3], t, 9.0, AMBER, "钱塘江南岸", "等待协助 · 18:31", fonts)

    today = window(t, 5.2, 15.3, 0.7)
    if today:
        rounded_panel(layer, (1455,64,1828,222), (8,31,27,round(220*today)), (128,224,174,round(75*today)), 28)
        draw.text((1500,92), "今日新声", font=fonts["label"], fill=(*CREAM, round(245*today)))
        count = min(12, max(1, int((t-5.0)*2.4)))
        draw.text((1494,128), f"{count:02d}", font=fonts["number"], fill=(*MINT, round(255*today)))
        draw.text((1650,160), "坐标正在亮起", font=fonts["detail"], fill=(*CREAM, round(190*today)))
        draw.ellipse((1767, 99, 1777, 109), fill=(*MINT, round(220*today)))

    assist = window(t, 14.4, 25.0, 0.7)
    if assist:
        rounded_panel(layer, (1320,720,1828,954), (17,28,24,round(230*assist)), (245,177,88,round(90*assist)), 32)
        draw.text((1364,754), "等待协助 · 04", font=fonts["label"], fill=(*AMBER, round(255*assist)))
        draw.text((1364,813), "听一听，你发现了什么线索？", font=fonts["body"], fill=(*CREAM, round(245*assist)))
        draw_waveform(draw, 1366, 893, 392, t, (*AMBER, round(225*assist)))
        draw.text((1654, 922), "1 位探员正在听", font=fonts["detail"], fill=(*CREAM, round(165*assist)))

    draw.text((96,1000), "杭州 · 区域级声景 · 保护精确位置", font=fonts["detail"], fill=(*CREAM,165))
    draw.text((1608,1012), "© OpenStreetMap contributors", font=fonts["micro"], fill=(*CREAM,150))
    intro = window(t, 0.3, 6.2, 0.7)
    if intro:
        draw.text((96,846), "从一部手机", font=fonts["title"], fill=(*CREAM,round(250*intro)))
        draw.text((96,912), "进入整座杭州", font=fonts["title"], fill=(*MINT,round(250*intro)))
    frame.alpha_composite(layer)
    return frame.convert("RGB")


def main():
    global OUT_WIDTH, OUT_HEIGHT, SCALE
    parser = argparse.ArgumentParser()
    parser.add_argument("--source", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--poster", type=Path)
    parser.add_argument("--duration", type=float, default=25.0)
    parser.add_argument("--fps", type=int, default=30)
    parser.add_argument("--width", type=int, default=1920)
    parser.add_argument("--height", type=int, default=1080)
    parser.add_argument("--encoder", default="libx264")
    parser.add_argument("--ffmpeg", default="ffmpeg")
    parser.add_argument("--still-time", type=float)
    args = parser.parse_args()
    args.output.parent.mkdir(parents=True, exist_ok=True)
    OUT_WIDTH, OUT_HEIGHT = args.width, args.height
    if abs(OUT_WIDTH / OUT_HEIGHT - WIDTH / HEIGHT) > 0.001:
        raise SystemExit("Only 16:9 canvases are supported")
    SCALE = OUT_WIDTH / WIDTH
    if args.poster:
        args.poster.parent.mkdir(parents=True, exist_ok=True)
    user_fonts = Path.home() / "AppData/Local/Microsoft/Windows/Fonts"
    fonts = {
        "display": load_font(user_fonts/"SmileySans-Oblique.otf", 70),
        "title": load_font(user_fonts/"AlibabaPuHuiTi-3-75-SemiBold.ttf", 54),
        "body": load_font(user_fonts/"AlibabaPuHuiTi-3-55-Regular.ttf", 30),
        "label": load_font(user_fonts/"AlibabaPuHuiTi-3-65-Medium.ttf", 28),
        "detail": load_font(user_fonts/"AlibabaPuHuiTi-3-55-Regular.ttf", 20),
        "number": load_font(user_fonts/"AlibabaPuHuiTi-3-75-SemiBold.ttf", 62),
        "micro": load_font(user_fonts/"AlibabaPuHuiTi-3-55-Regular.ttf", 16),
    }
    base, vignette = build_base(args.source), build_vignette()
    if args.still_time is not None:
        if not args.poster:
            raise SystemExit("--still-time requires --poster")
        render_frame(base, vignette, args.still_time, args.duration, fonts).save(args.poster, quality=94)
        return
    codec_args = (["-c:v","h264_nvenc","-preset","p7","-tune","hq","-rc","vbr","-cq","18","-b:v","0"]
                  if args.encoder == "h264_nvenc" else
                  ["-c:v","libx264","-preset","medium","-crf","18"])
    command = [args.ffmpeg,"-hide_banner","-loglevel","error","-y","-f","rawvideo",
               "-pix_fmt","rgb24","-s",f"{OUT_WIDTH}x{OUT_HEIGHT}","-r",str(args.fps),"-i","-",
               "-an",*codec_args,"-pix_fmt","yuv420p","-movflags","+faststart",str(args.output)]
    process = subprocess.Popen(command, stdin=subprocess.PIPE)
    assert process.stdin is not None
    poster_frame = round(17.5 * args.fps)
    try:
        for index in range(round(args.duration * args.fps)):
            frame = render_frame(base, vignette, index/args.fps, args.duration, fonts)
            if args.poster and index == poster_frame:
                frame.save(args.poster, quality=94)
            process.stdin.write(frame.tobytes())
    finally:
        process.stdin.close()
    if process.wait() != 0:
        raise SystemExit("FFmpeg failed while encoding the map animation")


if __name__ == "__main__":
    main()
