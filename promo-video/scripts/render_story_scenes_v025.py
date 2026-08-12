"""Render the v025 story-scene repair set at 1080p/30fps.

Real product footage remains pixel-faithful inside a restrained device edge.
All copy, labels, waveforms and diagrams are deterministic overlays.
"""

from __future__ import annotations

import argparse
import json
import math
import re
import subprocess
from pathlib import Path

import cv2
from PIL import Image, ImageDraw, ImageEnhance, ImageFilter, ImageFont


W, H, FPS = 1920, 1080, 30
PAPER = (245, 242, 233)
FOREST = (8, 27, 22)
INK = (16, 49, 39)
MUTED = (94, 111, 103)
MINT = (91, 171, 137)
PALE = (220, 235, 226)
AMBER = (222, 165, 81)
CREAM = (247, 243, 232)
PROJECT = Path(__file__).resolve().parents[1]
WORKSPACE = PROJECT.parent


SCENES = {
    "S02": (4.0, "听得见，却看不见。"),
    "S03": (7.0, "整片声景，都是线索。"),
    "S04": (6.0, "一次散步，变成共同调查。"),
    "S05": (7.0, "先确认这段声音证据。"),
    "S06": (10.0, "候选，不是答案。"),
    "S07": (6.0, "模型找候选，孩子去验证。"),
    "S08": (11.0, "AI 不替孩子作答。"),
    "S09": (8.0, "保存孩子的自然记忆。"),
    "S10": (6.0, "从一部手机，进入整座杭州。"),
    "S13": (7.0, "原声与观察，长成自然明信片。"),
    "S15": (4.0, "每一个孩子，都是自然声探员。"),
}


SUBTITLES = {
    "S02": ((0.0, 1.45, ("真正的调查，",)), (1.48, 3.35, ("从真实录音开始。",))),
    "S03": ((0.0, 1.20, ("不只鸟鸣。",)), (1.28, 5.03, ("蛙声、虫鸣、流水、风雨，",)),
            (5.08, 6.72, ("也都是自然线索。",))),
    "S04": ((0.0, 1.80, ("当孩子认真倾听，",)), (1.88, 4.05, ("他就成为了", "自然声探员。"))),
    "S05": ((0.0, 2.00, ("小探员先录下原声，",)), (2.05, 5.20, ("再确认这段声音证据", "是否清楚。"))),
    "S06": ((0.0, 2.78, ("专用声学模型", "逐段分析录音，")), (2.82, 4.50, ("找到有效声段，",)),
            (4.54, 7.35, ("再提出物种与", "环境声候选。"))),
    "S07": ((0.0, 3.02, ("千问 3.5 Omni", "补充声景理解，")),
            (3.05, 5.55, ("让复杂线索", "变得可调查。"))),
    "S08": ((0.0, 2.00, ("AI 不替孩子下结论。",)), (2.08, 4.86, ("它把复杂线索", "变成现场问题：")),
            (4.92, 7.28, ("声音来自树冠", "还是灌木？")), (7.34, 9.05, ("节奏有没有重复？",))),
    "S09": ((0.0, 2.18, ("孩子回听、观察、比较。",)),
            (2.24, 4.55, ("保存下来的，", "不只是一次调查。")),
            (4.62, 7.52, ("更是孩子独一无二的", "自然记忆。"))),
    "S10": ((0.0, 1.35, ("家长授权后，",)), (1.40, 5.30, ("匿名的声音线索", "可以回到杭州地图。"))),
    "S13": ((0.0, 1.28, ("调查完成后，",)), (1.34, 3.20, ("小探员邀请 AI，",)),
            (3.24, 6.72, ("让真实原声变成", "一张自然明信片。"))),
    "S15": ((0.0, 1.42, ("每一个孩子，",)), (1.50, 3.48, ("都是自然声探员。",))),
}


def srt_seconds(value: str) -> float:
    hours, minutes, rest = value.strip().replace(".", ",").split(":")
    seconds, millis = rest.split(",")
    return int(hours) * 3600 + int(minutes) * 60 + int(seconds) + int(millis) / 1000


def semantic_lines(text: str, max_chars: int = 20) -> tuple[str, ...]:
    text = re.sub(r"\s+", " ", text).strip()
    if len(text) <= max_chars:
        return (text,)
    low = max(1, len(text) - max_chars)
    high = min(max_chars, len(text) - 1)
    split = min(
        range(low, high + 1),
        key=lambda index: (0 if text[index - 1] in "，。！？；：、" else 5) + abs(index - len(text) / 2),
    )
    return (text[:split], text[split:])


def load_timed_subtitles(version: str) -> dict[str, tuple[tuple[float, float, tuple[str, ...]], ...]]:
    path = PROJECT / f"07-edit/subtitles/xykw-promo-voice-timed-{version}.srt"
    config_path = PROJECT / "video-config.json"
    if not path.exists() or not config_path.exists():
        return {}
    config = json.loads(config_path.read_text(encoding="utf-8"))
    blocks = re.split(r"\r?\n\s*\r?\n", path.read_text(encoding="utf-8-sig").strip())
    result: dict[str, list[tuple[float, float, tuple[str, ...]]]] = {scene["id"]: [] for scene in config["scenes"]}
    for block in blocks:
        lines = [line.strip() for line in block.splitlines() if line.strip()]
        timing_index = next((i for i, line in enumerate(lines) if " --> " in line), None)
        if timing_index is None:
            continue
        start_text, end_text = lines[timing_index].split(" --> ", 1)
        start, end = srt_seconds(start_text), srt_seconds(end_text)
        text = "".join(lines[timing_index + 1:])
        for scene in config["scenes"]:
            scene_start, scene_end = float(scene["start"]), float(scene["end"])
            if start < scene_end and end > scene_start:
                local_start = max(start, scene_start) - scene_start
                local_end = min(end, scene_end) - scene_start
                result[scene["id"]].append((local_start, local_end, semantic_lines(text)))
                break
    return {scene: tuple(events) for scene, events in result.items() if events}


def clamp01(v: float) -> float:
    return max(0.0, min(1.0, v))


def smooth(v: float) -> float:
    v = clamp01(v)
    return v * v * (3 - 2 * v)


def appear(t: float, born: float, span: float = 0.55) -> float:
    return smooth((t - born) / span)


def fonts() -> dict[str, ImageFont.FreeTypeFont]:
    root = Path.home() / "AppData/Local/Microsoft/Windows/Fonts"
    return {
        "display": ImageFont.truetype(str(root / "SmileySans-Oblique.otf"), 64),
        "hero": ImageFont.truetype(str(root / "AlibabaPuHuiTi-3-75-SemiBold.ttf"), 50),
        "title": ImageFont.truetype(str(root / "AlibabaPuHuiTi-3-75-SemiBold.ttf"), 34),
        "body": ImageFont.truetype(str(root / "AlibabaPuHuiTi-3-55-Regular.ttf"), 27),
        "subtitle": ImageFont.truetype(str(root / "AlibabaPuHuiTi-3-55-Regular.ttf"), 42),
        "label": ImageFont.truetype(str(root / "AlibabaPuHuiTi-3-65-Medium.ttf"), 22),
        "small": ImageFont.truetype(str(root / "AlibabaPuHuiTi-3-55-Regular.ttf"), 18),
    }


def cover(image: Image.Image, width: int, height: int) -> Image.Image:
    scale = max(width / image.width, height / image.height)
    resized = image.resize((round(image.width * scale), round(image.height * scale)), Image.Resampling.LANCZOS)
    left = (resized.width - width) // 2
    top = (resized.height - height) // 2
    return resized.crop((left, top, left + width, top + height))


def trim_recording_gutters(screen: Image.Image) -> Image.Image:
    """Remove the neutral side gutters baked into the 2160 px phone capture."""
    if screen.width != 2160 or screen.height != 3840:
        return screen
    gutter = 115
    return screen.crop((gutter, 0, screen.width - gutter, screen.height))


class TimelineReader:
    def __init__(self, clips: list[tuple[float, float, Path, float]]):
        self.clips = clips
        self.cap: cv2.VideoCapture | None = None
        self.active = -1

    def frame(self, t: float) -> Image.Image:
        index = next((i for i, (a, b, _, _) in enumerate(self.clips) if a <= t < b), len(self.clips) - 1)
        a, _, path, source_start = self.clips[index]
        if index != self.active:
            if self.cap is not None:
                self.cap.release()
            self.cap = cv2.VideoCapture(str(path))
            self.cap.set(cv2.CAP_PROP_POS_MSEC, source_start * 1000.0)
            self.active = index
        assert self.cap is not None
        ok, bgr = self.cap.read()
        if not ok:
            self.cap.set(cv2.CAP_PROP_POS_MSEC, (source_start + max(0.0, t - a)) * 1000.0)
            ok, bgr = self.cap.read()
        if not ok:
            raise RuntimeError(f"Cannot read {path} at {source_start + t - a:.2f}s")
        return Image.fromarray(cv2.cvtColor(bgr, cv2.COLOR_BGR2RGB))

    def close(self) -> None:
        if self.cap is not None:
            self.cap.release()


def make_device(screen: Image.Image, height: int = 904, shell=INK) -> Image.Image:
    edge = 8
    width = round(screen.width * height / screen.height)
    screen = screen.resize((width, height), Image.Resampling.LANCZOS).convert("RGBA")
    mask = Image.new("L", (width, height), 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, width - 1, height - 1), radius=25, fill=255)
    screen.putalpha(mask)
    device = Image.new("RGBA", (width + edge * 2, height + edge * 2), (0, 0, 0, 0))
    draw = ImageDraw.Draw(device, "RGBA")
    draw.rounded_rectangle((0, 0, device.width - 1, device.height - 1), radius=33, fill=(*shell, 255))
    device.alpha_composite(screen, (edge, edge))
    draw.rounded_rectangle((edge, edge, edge + width - 1, edge + height - 1), radius=25,
                           outline=(255, 255, 255, 90), width=1)
    return device


def paper_frame(relief: Image.Image | None = None) -> Image.Image:
    if relief is None:
        return Image.new("RGBA", (W, H), (*PAPER, 255))
    plate = cover(relief, W, H)
    plate = ImageEnhance.Contrast(plate).enhance(0.58)
    return Image.blend(Image.new("RGB", (W, H), PAPER), plate, 0.16).convert("RGBA")


def draw_waveform(draw: ImageDraw.ImageDraw, values: list[float], box: tuple[int, int, int, int],
                  progress: float, color=MINT, alpha=230) -> None:
    x1, y1, x2, y2 = box
    mid = (y1 + y2) / 2
    amp = (y2 - y1) * 0.42
    count = len(values) - 1
    end = max(2, round(len(values) * clamp01(progress)))
    top = [(x1 + i / count * (x2 - x1), mid - values[i] * amp) for i in range(end)]
    bottom = [(x1 + i / count * (x2 - x1), mid + values[i] * amp) for i in range(end)]
    draw.line((x1, mid, x2, mid), fill=(*color, 42), width=1)
    draw.line(top, fill=(*color, alpha), width=2, joint="curve")
    draw.line(bottom, fill=(*color, alpha), width=2, joint="curve")
    px = x1 + clamp01(progress) * (x2 - x1)
    draw.line((px, y1 - 8, px, y2 + 8), fill=(*color, min(255, alpha)), width=2)


def draw_playing_waveform(draw: ImageDraw.ImageDraw, values: list[float],
                          box: tuple[int, int, int, int], t: float,
                          color=MINT, alpha=235) -> float:
    """Keep the recorded contour exact while a scan window follows playback."""
    x1, y1, x2, y2 = box
    mid = (y1 + y2) / 2
    amp = (y2 - y1) * 0.42
    count = len(values) - 1
    top = [(x1 + i / count * (x2 - x1), mid - values[i] * amp) for i in range(len(values))]
    bottom = [(x1 + i / count * (x2 - x1), mid + values[i] * amp) for i in range(len(values))]
    reveal = appear(t, 0.18, 0.8)
    draw.line((x1, mid, x2, mid), fill=(*color, round(42 * reveal)), width=1)
    draw.line(top, fill=(*color, round(105 * reveal)), width=2, joint="curve")
    draw.line(bottom, fill=(*color, round(105 * reveal)), width=2, joint="curve")

    phase = ((max(0.0, t - 0.25)) / 4.6) % 1.0
    center = round(phase * count)
    radius = max(4, round(count * 0.105))
    start = max(0, center - radius)
    end = min(len(values), center + radius + 1)
    active_top = top[start:end]
    active_bottom = bottom[start:end]
    if len(active_top) >= 2:
        draw.line(active_top, fill=(*color, round(alpha * reveal)), width=3, joint="curve")
        draw.line(active_bottom, fill=(*color, round(alpha * reveal)), width=3, joint="curve")

    px = x1 + phase * (x2 - x1)
    glow = 0.5 + 0.5 * math.sin(t * math.tau * 1.35)
    draw.line((px, y1 - 10, px, y2 + 10), fill=(*color, round((180 + 65 * glow) * reveal)), width=2)
    radius_px = 4 + 2 * glow
    draw.ellipse((px - radius_px, mid - radius_px, px + radius_px, mid + radius_px),
                 fill=(*color, round(245 * reveal)))
    return phase


def draw_subtitle(frame: Image.Image, scene: str, t: float, f, dark: bool = False, center: int = 1230) -> None:
    lines = next((lines for start, end, lines in SUBTITLES[scene] if start <= t < end), None)
    if not lines:
        return
    layer = Image.new("RGBA", frame.size, (0, 0, 0, 0))
    draw = ImageDraw.Draw(layer, "RGBA")
    color = CREAM if dark else INK
    # Keep every narration caption on the same 80 px bottom safe line.
    last_baseline = H - 80
    line_gap = 54
    first_baseline = last_baseline - line_gap * (len(lines) - 1)
    for index, line in enumerate(lines):
        draw.text((center, first_baseline + index * line_gap), line, font=f["subtitle"], anchor="ms",
                  fill=(*color, 250))
    frame.paste(layer, (0, 0), layer)


def title(draw, text: str, f, dark=False, y=76) -> None:
    draw.text((610, y), text, font=f["display"], fill=(*(CREAM if dark else INK), 250))
    draw.line((612, y + 82, 900, y + 82), fill=(*(AMBER if dark else MINT), 150), width=2)


def product_frame(scene: str, t: float, screen: Image.Image, f, relief, wave, extras) -> Image.Image:
    dark = scene == "S13"
    frame = Image.new("RGBA", (W, H), (*FOREST, 255)) if dark else paper_frame(relief)
    if scene == "S04":
        screen = trim_recording_gutters(screen)
    device = make_device(screen, shell=CREAM if dark else INK)
    frame.alpha_composite(device, (42, 80))
    # Composite source imagery first, then draw translucent graphics on RGB so
    # their alpha is blended instead of being discarded by the final RGB cast.
    frame = frame.convert("RGB")
    graphics = Image.new("RGBA", frame.size, (0, 0, 0, 0))
    draw = ImageDraw.Draw(graphics, "RGBA")

    if scene == "S02":
        title(draw, "听得见，却看不见。", f)
        p = smooth((t - 0.25) / 2.7)
        draw_waveform(draw, wave, (660, 400, 1770, 635), p, MINT)
        a = appear(t, 2.25)
        draw.ellipse((1204, 508, 1222, 526), fill=(*AMBER, round(255 * a)))
        draw.text((1250, 486), "第一条线索", font=f["title"], fill=(*INK, round(255 * a)))
        draw.text((660, 690), "先保留声音，再开始判断。", font=f["label"], fill=(*MUTED, 225))
    elif scene == "S04":
        title(draw, "一次散步，变成共同调查。", f)
        # A short listening pulse resolves into the real locally recorded bird.
        cx, cy = 1215, 505
        pulse_fade = 1.0 - smooth((t - 0.35) / 0.85)
        for delay, radius in ((0.0, 58), (0.18, 104), (0.36, 150)):
            p = clamp01((t - delay) / 1.15)
            r = radius * (0.58 + 0.42 * p)
            draw.ellipse((cx - r, cy - r, cx + r, cy + r),
                         outline=(*MINT, round(125 * pulse_fade * (1 - p * .35))), width=2)
        draw.ellipse((cx - 9, cy - 9, cx + 9, cy + 9), fill=(*INK, round(245 * pulse_fade)))

        bird = cover(extras["bird_video_frame"], 1060, 596).convert("RGBA")
        bird_mask = Image.new("L", bird.size, 0)
        ImageDraw.Draw(bird_mask).rounded_rectangle((0, 0, bird.width - 1, bird.height - 1), radius=34, fill=255)
        bird_alpha = round(255 * appear(t, 0.42, 0.72))
        bird_mask = bird_mask.point(lambda value: round(value * bird_alpha / 255))
        bird.putalpha(bird_mask)
        frame.paste(bird, (685, 230), bird)
        video_a = appear(t, 0.72, 0.55)
        draw.rounded_rectangle((685, 230, 1745, 826), radius=34,
                               outline=(*MINT, round(150 * video_a)), width=2)
        draw.rounded_rectangle((725, 750, 1110, 805), radius=27,
                               fill=(*FOREST, round(205 * video_a)))
        draw.text((755, 762), "本地真实观察 · 原声保留", font=f["label"],
                  fill=(*CREAM, round(245 * video_a)))
        a = appear(t, 1.45)
        draw.text((1215, 865), "听见  ·  记录  ·  观察  ·  求证", font=f["title"], anchor="ma",
                  fill=(*INK, round(255 * a)))
    elif scene == "S05":
        title(draw, "先确认这段声音证据。", f)
        p = smooth((t - 0.35) / 3.7)
        draw_waveform(draw, wave, (650, 330, 1770, 555), p, MINT)
        for index, label in enumerate(("原声", "时段", "环境记录")):
            a = appear(t, 1.4 + index * 0.65)
            x = 650 + index * 310
            draw.line((x, 650, x + 215, 650), fill=(*MINT, round(130 * a)), width=2)
            draw.text((x, 677), label, font=f["title"], fill=(*INK, round(255 * a)))
            done = appear(t, 4.15 + index * 0.28, 0.38)
            draw.ellipse((x + 184, 684, x + 208, 708), fill=(*MINT, round(255 * done)))
            draw.line((x + 190, 696, x + 196, 702, x + 204, 690), fill=(*CREAM, round(255 * done)), width=3)
        ready = appear(t, 5.0, 0.65)
        draw.rounded_rectangle((650, 770, 1125, 836), radius=33, fill=(*PALE, round(235 * ready)))
        draw.ellipse((680, 795, 696, 811), fill=(*MINT, round(255 * ready)))
        draw.text((722, 786), "证据就绪，进入分析", font=f["label"], fill=(*INK, round(255 * ready)))
    elif scene == "S08":
        title(draw, "AI 不替孩子作答。", f)
        macro = extras["macro"].copy().convert("RGBA")
        macro = cover(macro, 1260, 720)
        macro.putalpha(55)
        frame.paste(macro, (560, 225), macro)
        if t < 2.1:
            phrase = "保留不确定性"
        elif t < 5.0:
            phrase = "把线索变成现场问题"
        elif t < 7.4:
            phrase = "树冠，还是灌木？"
        elif t < 9.0:
            phrase = "节奏，有没有重复？"
        else:
            phrase = "让下一步观察，更具体。"
        draw.text((650, 430), phrase, font=f["hero"], fill=(*INK, 255))
        draw.line((650, 520, 1540, 520), fill=(*INK, 58), width=1)
        for index, label in enumerate(("时间", "位置", "环境特征")):
            a = appear(t, 2.0 + index * 0.55)
            draw.text((650 + index * 310, 590), label, font=f["title"], fill=(*MINT, round(255 * a)))
        field = appear(t, 8.85, 0.65)
        steps = ((650, "回听"), (870, "观察"), (1090, "比较"), (1310, "保存"))
        for index, (x, label) in enumerate(steps):
            a = field * appear(t, 8.85 + index * 0.16, 0.35)
            if index:
                draw.line((steps[index - 1][0] + 78, 745, x - 24, 745), fill=(*MINT, round(130 * a)), width=2)
            draw.ellipse((x, 732, x + 26, 758), fill=(*MINT, round(255 * a)))
            draw.text((x + 42, 720), label, font=f["label"], fill=(*INK, round(255 * a)))
    elif scene == "S09":
        title(draw, "保存孩子的自然记忆。", f)
        labels = ("原声", "时间", "模糊地点", "孩子的观察")
        for index, label in enumerate(labels):
            a = appear(t, 0.75 + index * 0.75)
            y = 330 + index * 112
            draw.rounded_rectangle((650, y, 1120, y + 76), radius=24,
                                   fill=(*PALE, round(176 * a)))
            draw.ellipse((682, y + 24, 710, y + 52), fill=(*MINT, round(255 * a)))
            draw.line((688, y + 37, 696, y + 45, 706, y + 30),
                      fill=(*CREAM, round(255 * a)), width=3)
            draw.text((744, y + 17), label, font=f["title"], fill=(*INK, round(255 * a)))

        saved = appear(t, 4.35, 0.72)
        draw.rounded_rectangle((1225, 365, 1745, 705), radius=42,
                               fill=(*FOREST, round(248 * saved)))
        draw.ellipse((1427, 420, 1543, 536), outline=(*MINT, round(230 * saved)), width=4)
        draw.line((1455, 477, 1477, 500, 1520, 452),
                  fill=(*CREAM, round(255 * saved)), width=7)
        draw.text((1485, 570), "已保存到声音册", font=f["hero"], anchor="ma",
                   fill=(*CREAM, round(255 * saved)))
        draw.text((1485, 644), "一段独一无二的自然记忆", font=f["label"], anchor="ma",
                  fill=(*PALE, round(220 * saved)))
    elif scene == "S13":
        title(draw, "原声与观察，长成自然明信片。", f, dark=True)
        growth = cover(extras["growth"], 1360, 820).convert("RGBA")
        mask = Image.new("L", growth.size, 0)
        x = round(growth.width * smooth((t - 0.35) / 5.0))
        ImageDraw.Draw(mask).rectangle((0, 0, x, growth.height), fill=205)
        mask = mask.filter(ImageFilter.GaussianBlur(42))
        growth.putalpha(mask)
        frame.paste(growth, (560, 220), growth)
        # Align the exact recorded trace to the component's native waveform
        # baseline instead of placing a second, offset waveform card above it.
        draw.rounded_rectangle((560, 492, 1210, 742), radius=32, fill=(*FOREST, 72))
        draw_waveform(draw, wave, (568, 518, 1198, 724), smooth((t - .4) / 3.0), MINT, 230)
        for index, (label, value) in enumerate((("声音与旁白", "AI"), ("自然画面", "通义万相 Wan 2.7"))):
            a = appear(t, 1.6 + index * 1.2)
            y = 760 + index * 74
            draw.text((650, y), label, font=f["label"], fill=(*CREAM, round(195 * a)))
            draw.text((930, y), value, font=f["title"], fill=(*(MINT if index == 0 else AMBER), round(255 * a)))
    frame.paste(graphics, (0, 0), graphics)
    draw_subtitle(frame, scene, t, f, dark=dark)
    return frame


def montage_frame(t: float, f, assets, waveforms) -> Image.Image:
    cuts = (0, 1.12, 2.22, 3.32, 4.42, 5.52, 7.0)
    labels = ("鸟鸣", "蛙声", "虫鸣", "流水", "雨声", "风与树叶")
    images = assets["montage"]
    index = next((i for i in range(6) if cuts[i] <= t < cuts[i + 1]), 5)
    local = t - cuts[index]
    span = cuts[index + 1] - cuts[index]
    frame = cover(images[index], W, H).convert("RGBA")
    frame = ImageEnhance.Color(frame).enhance(.80)
    frame.alpha_composite(Image.new("RGBA", (W, H), (*FOREST, 86)))
    frame = frame.convert("RGB")
    graphics = Image.new("RGBA", frame.size, (0, 0, 0, 0))
    draw = ImageDraw.Draw(graphics, "RGBA")
    a = smooth(local / .16) * smooth((span - local) / .15)
    draw.text((86, 70), f"0{index + 1} / 06", font=f["small"], fill=(*CREAM, round(150 * a)))
    draw.text((86, 176), labels[index], font=f["display"], fill=(*CREAM, round(255 * a)))
    wf = waveforms[min(index, 4)]
    draw_waveform(draw, wf, (92, 780, 1715, 925), local / span, (MINT, AMBER)[index in (2, 4)], round(220 * a))
    frame.paste(graphics, (0, 0), graphics)
    draw_subtitle(frame, "S03", t, f, dark=index != 2, center=960)
    return frame


def analysis_frame(t: float, screen: Image.Image, f, relief, wave, assets) -> Image.Image:
    frame = paper_frame(relief)
    frame.alpha_composite(make_device(screen), (42, 80))
    frame = frame.convert("RGB")
    graphics = Image.new("RGBA", frame.size, (0, 0, 0, 0))
    draw = ImageDraw.Draw(graphics, "RGBA")
    title(draw, "候选，不是答案。", f)
    phase = draw_playing_waveform(draw, wave, (650, 275, 1770, 455), t, MINT)
    spectrum = cover(assets["spectrum"], 1120, 245).convert("RGBA")
    spectrum.putalpha(round(175 * appear(t, 1.15)))
    frame.paste(spectrum, (650, 500), spectrum)
    scan_x = 650 + phase * 1120
    scan_a = round(220 * appear(t, 1.15))
    draw.rectangle((scan_x - 10, 500, scan_x + 10, 745), fill=(*MINT, round(scan_a * 0.08)))
    draw.line((scan_x, 500, scan_x, 745), fill=(*MINT, scan_a), width=2)
    for index, (x1, x2, label, color) in enumerate(((760, 940, "有效声段", MINT), (1110, 1285, "鸟类候选", MINT),
                                                     (1390, 1630, "环境声候选", AMBER))):
        a = appear(t, 2.2 + index * .75)
        draw.line((x1, 770, x2, 770), fill=(*color, round(240 * a)), width=5)
        draw.text(((x1 + x2) // 2, 800), label, font=f["label"], anchor="ma", fill=(*INK, round(255 * a)))
    frame.paste(graphics, (0, 0), graphics)
    draw_subtitle(frame, "S06", t, f)
    return frame


def technology_frame(t: float, f) -> Image.Image:
    frame = Image.new("RGB", (W, H), FOREST)
    graphics = Image.new("RGBA", frame.size, (0, 0, 0, 0))
    draw = ImageDraw.Draw(graphics, "RGBA")
    title(draw, "模型找候选，孩子去验证。", f, dark=True)
    stages = (
        (170, "声学模型", "YAMNet · BirdNET 2.4", "发现候选声段", MINT),
        (720, "千问 3.5 Omni", "理解复杂声景", "转成现场问题", (92, 173, 190)),
        (1270, "孩子", "观察 · 倾听 · 比较", "完成现场核对", AMBER),
    )
    for index, (x, heading, line1, line2, color) in enumerate(stages):
        a = appear(t, .35 + index * .8)
        draw.text((x, 350), heading, font=f["hero"], fill=(*CREAM, round(255 * a)))
        draw.text((x, 440), line1, font=f["label"], fill=(*color, round(255 * a)))
        draw.text((x, 490), line2, font=f["body"], fill=(*CREAM, round(205 * a)))
        draw.line((x, 555, x + 360, 555), fill=(*color, round(145 * a)), width=2)
        if index < 2:
            draw.line((x + 390, 465, x + 505, 465), fill=(*CREAM, round(80 * a)), width=1)
            draw.ellipse((x + 495, 459, x + 507, 471), fill=(*color, round(210 * a)))
    a = appear(t, 3.2)
    draw.text((170, 760), "安全校验：候选不是结论", font=f["title"], fill=(*CREAM, round(210 * a)))
    draw.line((170, 830, 1745, 830), fill=(*CREAM, round(30 * a)), width=1)
    frame.paste(graphics, (0, 0), graphics)
    draw_subtitle(frame, "S07", t, f, dark=True, center=960)
    return frame


def map_frame(t: float, phone: Image.Image, f, assets) -> Image.Image:
    map_plate = cover(assets["map"], W, H)
    map_plate = ImageEnhance.Color(map_plate).enhance(.48)
    map_plate = Image.blend(map_plate, Image.new("RGB", (W, H), (80, 115, 101)), .27).convert("RGBA")
    start = paper_frame(assets["relief"])
    start.alpha_composite(make_device(phone), (42, 80))
    p = smooth((t - .7) / 3.0)
    mask = Image.new("L", (W, H), 0)
    draw_mask = ImageDraw.Draw(mask)
    cx, cy = 285, 385
    rx, ry = 110 + 1950 * p, 70 + 1080 * p
    draw_mask.ellipse((cx - rx, cy - ry, cx + rx, cy + ry), fill=255)
    mask = mask.filter(ImageFilter.GaussianBlur(48))
    frame = Image.composite(map_plate, start, mask).convert("RGBA")
    # Keep the full real device visible until the map has clearly escaped it.
    if t < 2.2:
        frame.alpha_composite(make_device(phone), (42, 80))
    frame = frame.convert("RGB")
    graphics = Image.new("RGBA", frame.size, (0, 0, 0, 0))
    draw = ImageDraw.Draw(graphics, "RGBA")
    a = appear(t, 2.0)
    # The transition starts on warm paper and ends on a detailed map. Invert the
    # typography with the reveal instead of relying on a shadow or title plate.
    title_color = INK
    draw.text((690, 84), "从屏幕里的地图，进入整座杭州。", font=f["display"], fill=(*title_color, round(255 * a)))
    for index, (x, y, color) in enumerate(((820, 430, MINT), (1120, 620, MINT), (1450, 400, AMBER), (1640, 730, MINT))):
        na = appear(t, 2.5 + index * .35)
        r = 18 + 9 * (.5 + .5 * math.sin(t * 3.4 + index))
        draw.ellipse((x-r, y-r, x+r, y+r), outline=(*color, round(105 * na)), width=2)
        draw.ellipse((x-5, y-5, x+5, y+5), fill=(*CREAM, round(245 * na)))
    anchor_mix = smooth((p - .42) / .30)
    subtitle_center = round(1230 * (1 - anchor_mix) + 960 * anchor_mix)
    frame.paste(graphics, (0, 0), graphics)
    draw_subtitle(frame, "S10", t, f, dark=False, center=subtitle_center)
    return frame


def brand_frame(t: float, f, wave: list[float]) -> Image.Image:
    frame = Image.new("RGB", (W, H), FOREST)
    graphics = Image.new("RGBA", frame.size, (0, 0, 0, 0))
    draw = ImageDraw.Draw(graphics, "RGBA")
    p = smooth(t / 2.5)
    # Two traces converge toward the wordmark without adding a sub-title stack.
    left_end = 960 - 150 * (1 - p)
    right_start = 960 + 150 * (1 - p)
    draw_waveform(draw, wave, (150, 360, int(left_end), 470), p, MINT, 115)
    reversed_wave = list(reversed(wave))
    draw_waveform(draw, reversed_wave, (int(right_start), 360, 1770, 470), p, MINT, 115)
    a = appear(t, .45)
    draw.text((960, 520), "自然声探员", font=f["display"], anchor="mm", fill=(*CREAM, round(255 * a)))
    draw.text((960, 620), "每一个孩子，都是自然声探员", font=f["title"], anchor="mm", fill=(*MINT, round(245 * a)))
    frame.paste(graphics, (0, 0), graphics)
    draw_subtitle(frame, "S15", t, f, dark=True, center=960)
    return frame


def paths() -> dict[str, Path]:
    return {
        "demo": PROJECT / "02-proxies/demo-v005/xykw-demo-flow-verified-30fps.mp4",
        "part01": WORKSPACE / "artifacts/xykw-part01-4k.mp4",
        "part02": WORKSPACE / "artifacts/xykw-part02-4k.mp4",
        "save": PROJECT / "02-proxies/demo-v005/xykw-demo-save-verified-30fps.mp4",
        "part03": WORKSPACE / "artifacts/xykw-part03-4k.mp4",
        "map_phone": WORKSPACE / "artifacts/recording-part05-map.png",
        "map": WORKSPACE / "mobile/assets/maps/hangzhou_osm.png",
        "relief": PROJECT / "04-design/components-v020/paper-topographic-relief.png",
        "macro": PROJECT / "04-design/components-v020/feather-leaf-dew-macro.png",
        "growth": PROJECT / "04-design/components-v024/s13-ai-cocreation-growth-v024-1080p.png",
        "water": PROJECT / "04-design/components-v024/s03-flowing-water-v024-1080p.png",
        "rain": PROJECT / "04-design/components-v024/s03-rain-on-leaves-v024-1080p.png",
        "wind": PROJECT / "04-design/components-v024/s03-wind-through-canopy-v024-1080p.png",
        "bird": WORKSPACE / "mobile/assets/species/pycnonotus_sinensis.webp",
        "frog": WORKSPACE / "mobile/assets/species/pelophylax_nigromaculatus.webp",
        "insect": WORKSPACE / "mobile/assets/species/cryptotympana_atrata.webp",
        "spectrum": PROJECT / "05-motion/spectrogram/original-sound-spectrum-4k.png",
        "waveforms": PROJECT / "06-audio/nature-stems/s03-v016/s03-waveforms-v016.json",
        "nature_bed": PROJECT / "06-audio/nature-stems/s03-v016/s03-category-nature-bed-v016.wav",
        "bird_video": PROJECT / "01-source/wudong.mp4",
    }


def reader_for(scene: str, p: dict[str, Path]) -> TimelineReader | None:
    return {
        "S02": lambda: TimelineReader([(0, 4, p["demo"], 0)]),
        "S04": lambda: TimelineReader([(0, 6, p["part01"], 0)]),
        "S05": lambda: TimelineReader([(0, 7, p["demo"], 4)]),
        "S06": lambda: TimelineReader([(0, 10, p["part02"], 0)]),
        "S08": lambda: TimelineReader([(0, 2.15, p["part02"], 8), (2.15, 5, p["part02"], 16),
                                        (5, 11, p["part02"], 54)]),
        "S09": lambda: TimelineReader([(0, 8, p["save"], .5)]),
        "S13": lambda: TimelineReader([(0, 7, p["part03"], 449)]),
    }.get(scene, lambda: None)()


def encode(scene: str, output: Path, encoder: str, voice_version: str) -> None:
    duration, _ = SCENES[scene]
    p = paths()
    for path in p.values():
        if not path.exists():
            raise SystemExit(f"Missing input: {path}")
    payload = json.loads(p["waveforms"].read_text(encoding="utf-8"))
    waveforms = [item["waveform"] for item in payload["categories"]]
    wave = waveforms[0]
    f = fonts()
    relief = Image.open(p["relief"]).convert("RGB")
    assets = {
        "relief": relief,
        "macro": Image.open(p["macro"]).convert("RGB"),
        "growth": Image.open(p["growth"]).convert("RGB"),
        "map": Image.open(p["map"]).convert("RGB"),
        "spectrum": Image.open(p["spectrum"]).convert("RGB"),
        "montage": [Image.open(p[key]).convert("RGB") for key in ("bird", "frog", "insect", "water", "rain", "wind")],
    }
    phone_map = Image.open(p["map_phone"]).convert("RGB")
    reader = reader_for(scene, p)
    bird_reader = TimelineReader([(0, duration, p["bird_video"], 11.5)]) if scene == "S04" else None
    voice = PROJECT / f"06-audio/voiceover/formal/scenes/{voice_version}/{scene}-voice.wav"
    output.parent.mkdir(parents=True, exist_ok=True)
    codec = (["-c:v", "h264_nvenc", "-preset", "p7", "-tune", "hq", "-rc", "vbr", "-cq", "18", "-b:v", "0"]
             if encoder == "h264_nvenc" else ["-c:v", "libx264", "-preset", "veryfast", "-crf", "17"])
    command = ["ffmpeg", "-hide_banner", "-loglevel", "error", "-y", "-f", "rawvideo", "-pix_fmt", "rgb24",
               "-s", f"{W}x{H}", "-r", str(FPS), "-i", "-", "-i", str(voice)]
    if scene == "S03":
        command += ["-i", str(p["nature_bed"]), "-filter_complex", "[1:a][2:a]amix=inputs=2:weights='1 0.34':normalize=0[a]",
                    "-map", "0:v:0", "-map", "[a]"]
    else:
        command += ["-map", "0:v:0", "-map", "1:a:0"]
    command += [*codec, "-pix_fmt", "yuv420p", "-r", str(FPS), "-c:a", "aac", "-b:a", "192k", "-ar", "48000",
                "-t", f"{duration:.3f}", "-movflags", "+faststart", str(output)]
    process = subprocess.Popen(command, stdin=subprocess.PIPE)
    assert process.stdin is not None
    try:
        for index in range(round(duration * FPS)):
            t = index / FPS
            screen = reader.frame(t) if reader else None
            if bird_reader:
                assets["bird_video_frame"] = bird_reader.frame(t)
            if scene in {"S02", "S04", "S05", "S08", "S09", "S13"}:
                assert screen is not None
                frame = product_frame(scene, t, screen, f, relief, wave, assets)
            elif scene == "S03":
                frame = montage_frame(t, f, assets, waveforms)
            elif scene == "S06":
                assert screen is not None
                frame = analysis_frame(t, screen, f, relief, wave, assets)
            elif scene == "S07":
                frame = technology_frame(t, f)
            elif scene == "S10":
                frame = map_frame(t, phone_map, f, assets)
            else:
                frame = brand_frame(t, f, wave)
            process.stdin.write(frame.convert("RGB").tobytes())
    finally:
        process.stdin.close()
        if reader:
            reader.close()
        if bird_reader:
            bird_reader.close()
    if process.wait() != 0:
        raise SystemExit(f"FFmpeg failed for {scene}")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--scene", choices=tuple(SCENES), required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--encoder", default="h264_nvenc")
    parser.add_argument("--voice-version", default="v012")
    args = parser.parse_args()
    global SUBTITLES
    SUBTITLES.update(load_timed_subtitles(args.voice_version))
    encode(args.scene, args.output, args.encoder, args.voice_version)


if __name__ == "__main__":
    main()
