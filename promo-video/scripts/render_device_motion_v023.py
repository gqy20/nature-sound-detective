"""Render S11/S12 1080p device-frame motion previews with locked timing."""

from __future__ import annotations

import argparse
import math
import subprocess
from pathlib import Path

from PIL import Image, ImageDraw, ImageEnhance, ImageFilter, ImageFont


W, H, FPS = 1920, 1080, 30
PAPER = (245, 242, 233)
FOREST = (8, 27, 22)
INK = (16, 49, 39)
MINT = (91, 171, 137)
AMBER = (222, 165, 81)
CREAM = (247, 243, 232)


def clamp01(value: float) -> float:
    return max(0.0, min(1.0, value))


def smoothstep(value: float) -> float:
    value = clamp01(value)
    return value * value * (3.0 - 2.0 * value)


def font(size: int, weight: str = "medium") -> ImageFont.FreeTypeFont:
    root = Path.home() / "AppData/Local/Microsoft/Windows/Fonts"
    names = {
        "regular": "AlibabaPuHuiTi-3-55-Regular.ttf",
        "medium": "AlibabaPuHuiTi-3-65-Medium.ttf",
        "semibold": "AlibabaPuHuiTi-3-75-SemiBold.ttf",
    }
    return ImageFont.truetype(str(root / names[weight]), size)


def centered_text(
    frame: Image.Image,
    lines: tuple[str, ...],
    y: int,
    fill: tuple[int, int, int, int],
    x_center: int = 1215,
) -> None:
    draw = ImageDraw.Draw(frame, "RGBA")
    f = font(28, "medium")
    gap = 39
    for index, line in enumerate(lines):
        draw.text((x_center, y + index * gap), line, font=f, anchor="ma", fill=fill)


def subtitle_s11(frame: Image.Image, t: float) -> None:
    if 0.25 <= t < 2.75:
        centered_text(frame, ("今天，探员们又记录了", "十二条新声。"), 875, (*INK, 238))
    elif 3.25 <= t < 4.50:
        centered_text(frame, ("一个个发现，",), 895, (*INK, 238))
    elif 4.55 <= t < 7.55:
        centered_text(frame, ("正在汇成杭州的", "城市声音地图。"), 875, (*INK, 238))


def subtitle_s12(frame: Image.Image, t: float) -> None:
    if 0.20 <= t < 1.25:
        centered_text(frame, ("有些声音，",), 885, (*CREAM, 238))
    elif 1.30 <= t < 3.15:
        centered_text(frame, ("一个人还无法确定。",), 885, (*CREAM, 238))
    elif 3.25 <= t < 6.75:
        centered_text(frame, ("另一位探员可以接着听，", "比较候选，"), 865, (*CREAM, 238))
    elif 6.80 <= t < 9.20:
        centered_text(frame, ("为调查补上一段证据。",), 885, (*CREAM, 238))


def s11_start(final: Image.Image, relief: Image.Image) -> Image.Image:
    start = final.copy().convert("RGBA")
    relief = relief.resize((W, H), Image.Resampling.LANCZOS)
    relief = ImageEnhance.Contrast(relief).enhance(0.55)
    quiet = Image.blend(Image.new("RGB", (W, H), PAPER), relief.convert("RGB"), 0.34).convert("RGBA")
    start.alpha_composite(quiet.crop((548, 0, W, H)), (548, 0))
    return start


def radial_reveal_mask(progress: float) -> Image.Image:
    mask = Image.new("L", (W, H), 0)
    if progress <= 0:
        return mask
    draw = ImageDraw.Draw(mask)
    cx, cy = 420, 430
    radius_x = 80 + 1840 * smoothstep(progress)
    radius_y = 45 + 1040 * smoothstep(progress)
    draw.ellipse((cx - radius_x, cy - radius_y, cx + radius_x, cy + radius_y), fill=255)
    return mask.filter(ImageFilter.GaussianBlur(52))


def add_sound_sources(frame: Image.Image, t: float) -> None:
    draw = ImageDraw.Draw(frame, "RGBA")
    points = (
        (760, 446, MINT),
        (1000, 630, MINT),
        (1275, 350, MINT),
        (1535, 520, AMBER),
        (1160, 790, MINT),
        (1580, 820, MINT),
    )
    for index, (x, y, color) in enumerate(points):
        onset = 2.0 + index * 0.38
        local = smoothstep((t - onset) / 0.55)
        if local <= 0:
            continue
        pulse = 0.5 + 0.5 * math.sin((t - onset) * math.tau * 0.72)
        radius = 15 + 13 * pulse
        alpha = round((74 + 62 * (1.0 - pulse)) * local)
        draw.ellipse((x - radius, y - radius, x + radius, y + radius), outline=(*color, alpha), width=2)
        draw.ellipse((x - 4, y - 4, x + 4, y + 4), fill=(*CREAM, round(240 * local)))
        draw.ellipse((x - 7, y - 7, x + 7, y + 7), outline=(*color, round(220 * local)), width=2)


def frame_s11(final: Image.Image, start: Image.Image, t: float) -> Image.Image:
    progress = (t - 0.45) / 3.8
    mask = radial_reveal_mask(progress)
    frame = Image.composite(final, start, mask).convert("RGBA")
    add_sound_sources(frame, t)
    subtitle_s11(frame, t)

    fade = smoothstep(t / 0.42) * smoothstep((9.0 - t) / 0.32)
    if fade < 0.999:
        frame.putalpha(round(255 * fade))
        bg = Image.new("RGBA", (W, H), (*PAPER, 255))
        bg.alpha_composite(frame)
        frame = bg
    return frame.convert("RGB")


def s12_start(final: Image.Image) -> Image.Image:
    dark = Image.new("RGBA", (W, H), (*FOREST, 255))
    # The real framed phone stays present while the shared memory field forms.
    dark.alpha_composite(final.crop((0, 0, 560, H)), (0, 0))
    return dark


def directional_mask(progress: float) -> Image.Image:
    mask = Image.new("L", (W, H), 0)
    x = round(500 + smoothstep(progress) * 1530)
    ImageDraw.Draw(mask).rectangle((500, 0, x, H), fill=255)
    return mask.filter(ImageFilter.GaussianBlur(58))


def frame_s12(final: Image.Image, start: Image.Image, t: float) -> Image.Image:
    progress = (t - 0.35) / 5.4
    mask = directional_mask(progress)
    frame = Image.composite(final, start, mask).convert("RGBA")

    # A narrow amber glint marks the active front of the memory ribbon.
    if 0.35 < t < 5.75:
        p = smoothstep(progress)
        x = round(520 + p * 1390)
        glint = Image.new("RGBA", (W, H), (0, 0, 0, 0))
        gd = ImageDraw.Draw(glint, "RGBA")
        gd.line((x, 350, x, 760), fill=(*AMBER, 62), width=3)
        glint = glint.filter(ImageFilter.GaussianBlur(10))
        frame.alpha_composite(glint)

    subtitle_s12(frame, t)
    fade = smoothstep(t / 0.42) * smoothstep((10.0 - t) / 0.32)
    if fade < 0.999:
        frame.putalpha(round(255 * fade))
        bg = Image.new("RGBA", (W, H), (*FOREST, 255))
        bg.alpha_composite(frame)
        frame = bg
    return frame.convert("RGB")


def encode(
    output: Path,
    audio: Path,
    duration: float,
    frame_builder,
) -> None:
    output.parent.mkdir(parents=True, exist_ok=True)
    command = [
        "ffmpeg", "-y",
        "-f", "rawvideo", "-pix_fmt", "rgb24",
        "-s", f"{W}x{H}", "-r", str(FPS), "-i", "-",
        "-i", str(audio),
        "-c:v", "libx264", "-preset", "medium", "-crf", "16",
        "-pix_fmt", "yuv420p", "-r", str(FPS),
        "-c:a", "aac", "-b:a", "192k",
        "-t", f"{duration:.3f}", "-movflags", "+faststart",
        str(output),
    ]
    process = subprocess.Popen(command, stdin=subprocess.PIPE)
    assert process.stdin is not None
    total = round(duration * FPS)
    try:
        for index in range(total):
            frame = frame_builder(index / FPS)
            process.stdin.write(frame.tobytes())
    finally:
        process.stdin.close()
    code = process.wait()
    if code != 0:
        raise SystemExit(f"ffmpeg failed with exit code {code}")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--s11-still", type=Path, required=True)
    parser.add_argument("--s12-still", type=Path, required=True)
    parser.add_argument("--relief", type=Path, required=True)
    parser.add_argument("--s11-audio", type=Path, required=True)
    parser.add_argument("--s12-audio", type=Path, required=True)
    parser.add_argument("--output-dir", type=Path, required=True)
    args = parser.parse_args()

    for path in (args.s11_still, args.s12_still, args.relief, args.s11_audio, args.s12_audio):
        if not path.exists():
            raise SystemExit(f"Missing input: {path}")

    s11_final = Image.open(args.s11_still).convert("RGBA")
    s12_final = Image.open(args.s12_still).convert("RGBA")
    relief = Image.open(args.relief).convert("RGB")
    s11_quiet = s11_start(s11_final, relief)
    s12_quiet = s12_start(s12_final)

    encode(
        args.output_dir / "S11-device-map-reveal-v023-1080p.mp4",
        args.s11_audio,
        9.0,
        lambda t: frame_s11(s11_final, s11_quiet, t),
    )
    encode(
        args.output_dir / "S12-device-memory-flow-v023-1080p.mp4",
        args.s12_audio,
        10.0,
        lambda t: frame_s12(s12_final, s12_quiet, t),
    )


if __name__ == "__main__":
    main()
