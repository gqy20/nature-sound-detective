"""Render 1080p community scenes with product proof left and meaning right."""

from __future__ import annotations

import argparse
import subprocess
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont


W, H, FPS = 1920, 1080, 30
PAPER = (244, 241, 232)
PANEL = (249, 247, 240)
INK = (18, 49, 39)
MUTED = (103, 116, 108)
MINT = (89, 171, 137)
PALE_MINT = (218, 235, 225)
AMBER = (224, 164, 78)
LINE = (198, 205, 197)


def clamp(value: float) -> float:
    return max(0.0, min(1.0, value))


def smooth(value: float) -> float:
    value = clamp(value)
    return value * value * (3 - 2 * value)


def appear(t: float, born: float, duration: float = 0.55) -> float:
    return smooth((t - born) / duration)


def load_fonts() -> dict[str, ImageFont.FreeTypeFont]:
    root = Path.home() / "AppData/Local/Microsoft/Windows/Fonts"
    return {
        "hero": ImageFont.truetype(str(root / "AlibabaPuHuiTi-3-75-SemiBold.ttf"), 58),
        "hero_l": ImageFont.truetype(str(root / "AlibabaPuHuiTi-3-75-SemiBold.ttf"), 76),
        "mega": ImageFont.truetype(str(root / "AlibabaPuHuiTi-3-75-SemiBold.ttf"), 330),
        "title": ImageFont.truetype(str(root / "AlibabaPuHuiTi-3-75-SemiBold.ttf"), 34),
        "body": ImageFont.truetype(str(root / "AlibabaPuHuiTi-3-55-Regular.ttf"), 27),
        "label": ImageFont.truetype(str(root / "AlibabaPuHuiTi-3-65-Medium.ttf"), 22),
        "small": ImageFont.truetype(str(root / "AlibabaPuHuiTi-3-55-Regular.ttf"), 18),
        "number": ImageFont.truetype(str(root / "AlibabaPuHuiTi-3-75-SemiBold.ttf"), 64),
    }


def phone_layer(source: Image.Image, height: int = 940, x: int = 74, y: int = 70) -> Image.Image:
    width = round(source.width * height / source.height)
    phone = source.resize((width, height), Image.Resampling.LANCZOS).convert("RGBA")
    layer = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    layer.alpha_composite(phone, (x, y))
    draw = ImageDraw.Draw(layer)
    draw.rounded_rectangle((x - 1, y - 1, x + width + 1, y + height + 1), radius=3,
                           outline=(189, 193, 185, 105), width=1)
    draw.line((x + width + 66, y + 16, x + width + 66, y + height - 16),
              fill=(188, 198, 190, 105), width=1)
    return layer


def paper_texture(frame: Image.Image) -> None:
    """Add restrained deterministic grain without shadows or gradients."""
    draw = ImageDraw.Draw(frame, "RGBA")
    for index in range(180):
        x = (index * 137 + 43) % W
        y = (index * 251 + 91) % H
        draw.point((x, y), fill=(31, 58, 48, 3))


def today_scene(frame: Image.Image, t: float, fonts) -> None:
    draw = ImageDraw.Draw(frame, "RGBA")
    a = appear(t, 0.15)
    draw.text((650, 92), "一条声音被上传，", font=fonts["hero"], fill=(*INK, round(255 * a)))
    draw.text((650, 166), "整座城市都能接着听。", font=fonts["hero"], fill=(*INK, round(255 * a)))
    draw.line((652, 258, 1782, 258), fill=(*LINE, round(150 * a)), width=1)

    for x, number, label, born, color in (
        (650, "12", "今日新声", 0.7, MINT),
        (860, "04", "等待协助", 1.05, AMBER),
    ):
        item_a = appear(t, born)
        draw.text((x, 292), number, font=fonts["number"], fill=(*color, round(255 * item_a)))
        draw.text((x + 90, 329), label, font=fonts["label"], fill=(*MUTED, round(235 * item_a)))

    # An editorial city-sound network: it explains the collective effect
    # without repeating or magnifying the product map.
    nodes = [
        ((738, 612), "07:42", "西溪湿地", "林间鸟鸣", MINT, 1.15),
        ((1120, 492), "09:16", "植物园", "树梢虫声", (119, 176, 111), 2.15),
        ((1502, 664), "13:08", "运河沿岸", "风与水", (92, 163, 187), 3.15),
    ]
    for index in range(len(nodes) - 1):
        p = appear(t, 1.65 + index)
        start, end = nodes[index][0], nodes[index + 1][0]
        destination = (start[0] + (end[0] - start[0]) * p, start[1] + (end[1] - start[1]) * p)
        draw.line((start, destination), fill=(*MINT, round(92 * p)), width=2)

    for (x, y), time_text, place, sound, color, born in nodes:
        node_a = appear(t, born)
        radius = 10 + 15 * ((t - born) % 1.8) / 1.8 if t >= born else 10
        draw.ellipse((x - radius, y - radius, x + radius, y + radius), outline=(*color, round(60 * node_a)), width=2)
        draw.ellipse((x - 7, y - 7, x + 7, y + 7), fill=(*color, round(255 * node_a)))
        draw.rounded_rectangle((x - 58, y + 34, x + 246, y + 155), radius=22,
                               fill=(*PANEL, round(248 * node_a)), outline=(*LINE, round(145 * node_a)), width=1)
        draw.text((x - 32, y + 53), time_text, font=fonts["small"], fill=(*color, round(255 * node_a)))
        draw.text((x + 46, y + 51), place, font=fonts["label"], fill=(*INK, round(255 * node_a)))
        draw.text((x - 32, y + 92), sound, font=fonts["body"], fill=(*MUTED, round(235 * node_a)))
        draw.line((x + 86, y + 112, x + 216, y + 112), fill=(*color, round(95 * node_a)), width=1)
        for dot in range(3):
            dot_x = x + 108 + dot * 38
            draw.ellipse((dot_x - 3, y + 109, dot_x + 3, y + 115), fill=(*color, round(205 * node_a)))

    footer_a = appear(t, 4.8)
    draw.text((650, 949), "声音从一个坐标出发，成为杭州共同保存的自然线索。",
              font=fonts["body"], fill=(*INK, round(230 * footer_a)))


def assist_scene(frame: Image.Image, t: float, fonts) -> None:
    draw = ImageDraw.Draw(frame, "RGBA")
    a = appear(t, 0.15)
    draw.text((650, 92), "一个人没有听清，", font=fonts["hero"], fill=(*INK, round(255 * a)))
    draw.text((650, 166), "另一位探员可以接着听。", font=fonts["hero"], fill=(*INK, round(255 * a)))
    draw.line((652, 258, 1782, 258), fill=(*LINE, round(150 * a)), width=1)

    left = (780, 560)
    right = (1585, 560)
    for center, number, label, detail, born, color in (
        (left, "01", "探员 A", "留下原声", 0.8, MINT),
        (right, "02", "探员 B", "接着倾听", 3.0, AMBER),
    ):
        item_a = appear(t, born)
        x, y = center
        draw.ellipse((x - 80, y - 80, x + 80, y + 80), fill=(*PANEL, round(255 * item_a)),
                     outline=(*color, round(190 * item_a)), width=3)
        draw.text((x, y - 13), number, font=fonts["title"], anchor="mm", fill=(*color, round(255 * item_a)))
        draw.text((x, y + 111), label, font=fonts["title"], anchor="mm", fill=(*INK, round(255 * item_a)))
        draw.text((x, y + 154), detail, font=fonts["body"], anchor="mm", fill=(*MUTED, round(230 * item_a)))

    relay = appear(t, 1.65, 1.4)
    end_x = 1457
    current_x = 908 + (end_x - 908) * relay
    draw.line((908, 560, current_x, 560), fill=(*MINT, round(185 * relay)), width=2)
    if relay > 0:
        for index in range(7):
            phase = ((t * 0.32) + index / 7) % 1.0
            dot_x = 930 + (1415 - 930) * phase
            if dot_x <= current_x:
                radius = 3 if index % 2 else 5
                draw.ellipse((dot_x - radius, 560 - radius, dot_x + radius, 560 + radius),
                             fill=(*MINT, round(210 * relay)))
    badge_a = appear(t, 2.0)
    draw.rounded_rectangle((1082, 476, 1284, 520), radius=22, fill=(*PALE_MINT, round(255 * badge_a)))
    draw.text((1183, 498), "公开声音线索", font=fonts["small"], anchor="mm", fill=(*INK, round(255 * badge_a)))

    result_a = appear(t, 5.0)
    draw.rounded_rectangle((690, 815, 1718, 962), radius=28, fill=(*PANEL, round(255 * result_a)),
                           outline=(*LINE, round(150 * result_a)), width=1)
    draw.ellipse((730, 861, 754, 885), fill=(*MINT, round(255 * result_a)))
    draw.text((782, 840), "发现由一个人开始，答案由大家共同完成。",
              font=fonts["title"], fill=(*INK, round(255 * result_a)))
    draw.text((782, 896), "接着听、比较候选，为调查补上一段现场证据。",
              font=fonts["body"], fill=(*MUTED, round(235 * result_a)))


def today_editorial_scene(frame: Image.Image, t: float, fonts) -> None:
    draw = ImageDraw.Draw(frame, "RGBA")
    title_a = appear(t, 0.15, 0.65)
    draw.text((620, 88), "今天，杭州又多了", font=fonts["title"], fill=(*INK, round(255 * title_a)))

    number_a = appear(t, 0.55, 0.9)
    draw.text((604, 135), "12", font=fonts["mega"], fill=(*PALE_MINT, round(235 * number_a)),
              stroke_width=2, stroke_fill=(*MINT, round(80 * number_a)))
    draw.text((1060, 276), "个被听见的", font=fonts["hero_l"], fill=(*INK, round(255 * number_a)))
    draw.text((1060, 369), "瞬间。", font=fonts["hero_l"], fill=(*INK, round(255 * number_a)))

    # A single editorial timeline replaces the previous card-based network.
    path = ((720, 790), (1085, 690), (1400, 738), (1740, 570))
    route_a = appear(t, 1.4, 2.8)
    total_segments = len(path) - 1
    for index, (start, end) in enumerate(zip(path, path[1:])):
        local = clamp(route_a * total_segments - index)
        if local <= 0:
            continue
        destination = (start[0] + (end[0] - start[0]) * local,
                       start[1] + (end[1] - start[1]) * local)
        draw.line((start, destination), fill=(*MINT, round(145 * route_a)), width=2)

    moments = (
        (path[0], "07:42", "西溪湿地", 1.5),
        (path[1], "09:16", "植物园", 2.5),
        (path[3], "13:08", "运河沿岸", 3.5),
    )
    for index, ((x, y), time_text, place, born) in enumerate(moments):
        item_a = appear(t, born, 0.55)
        radius = 5 + 12 * (((t - born) % 2.1) / 2.1) if t >= born else 5
        draw.ellipse((x - radius, y - radius, x + radius, y + radius),
                     outline=(*MINT, round(50 * item_a)), width=1)
        draw.ellipse((x - 5, y - 5, x + 5, y + 5), fill=(*MINT, round(255 * item_a)))
        text_x = x - 4 if index != 2 else x - 184
        text_y = y + 32 if index != 1 else y - 78
        draw.text((text_x, text_y), time_text, font=fonts["small"], fill=(*MINT, round(255 * item_a)))
        draw.text((text_x, text_y + 30), place, font=fonts["label"], fill=(*INK, round(245 * item_a)))

    waiting_a = appear(t, 4.15, 0.7)
    draw.text((1398, 833), "04", font=fonts["title"], fill=(*AMBER, round(255 * waiting_a)))
    draw.text((1460, 842), "条声音等待协助", font=fonts["label"], fill=(*MUTED, round(235 * waiting_a)))
    footer_a = appear(t, 5.0, 0.7)
    draw.text((620, 965), "声音正在成为这座城市的另一张地图。",
              font=fonts["body"], fill=(*INK, round(235 * footer_a)))


def assist_editorial_scene(frame: Image.Image, t: float, fonts) -> None:
    draw = ImageDraw.Draw(frame, "RGBA")
    title_a = appear(t, 0.15, 0.65)
    draw.text((620, 92), "听不清，", font=fonts["hero_l"], fill=(*INK, round(255 * title_a)))
    draw.text((620, 184), "不代表线索就此停止。", font=fonts["hero"], fill=(*INK, round(255 * title_a)))

    line_y = 528
    left_x, middle_x, right_x = 690, 1180, 1742
    base_a = appear(t, 0.85, 0.6)
    draw.line((left_x, line_y, right_x, line_y), fill=(*LINE, round(185 * base_a)), width=1)
    draw.text((left_x, line_y - 66), "尚未确认", font=fonts["label"], fill=(*MUTED, round(230 * base_a)))
    draw.text((left_x, line_y + 34), "来自一位探员", font=fonts["small"], fill=(*MUTED, round(190 * base_a)))
    draw.ellipse((left_x - 7, line_y - 7, left_x + 7, line_y + 7), fill=(*AMBER, round(255 * base_a)))

    travel = appear(t, 1.4, 3.8)
    travel_x = left_x + (right_x - left_x) * travel
    draw.line((left_x, line_y, travel_x, line_y), fill=(*AMBER, round(205 * travel)), width=2)
    for offset, alpha in ((0, 255), (-28, 130), (-56, 55)):
        dot_x = max(left_x, travel_x + offset)
        draw.ellipse((dot_x - 5, line_y - 5, dot_x + 5, line_y + 5), fill=(*AMBER, round(alpha * travel)))

    middle_a = appear(t, 2.25, 0.65)
    draw.line((middle_x, line_y - 18, middle_x, line_y + 18), fill=(*AMBER, round(180 * middle_a)), width=1)
    draw.text((middle_x, line_y - 66), "正在被接着听", font=fonts["label"], anchor="mm",
              fill=(*INK, round(255 * middle_a)))

    end_a = appear(t, 4.95, 0.65)
    draw.ellipse((right_x - 18, line_y - 18, right_x + 18, line_y + 18),
                 outline=(*AMBER, round(210 * end_a)), width=2)
    draw.line((right_x - 8, line_y, right_x - 1, line_y + 8, right_x + 12, line_y - 10),
              fill=(*AMBER, round(255 * end_a)), width=3)
    draw.text((right_x, line_y - 66), "补充证据", font=fonts["label"], anchor="mm",
              fill=(*INK, round(255 * end_a)))
    draw.text((right_x, line_y + 34), "抵达另一双耳朵", font=fonts["small"], anchor="ma",
              fill=(*MUTED, round(210 * end_a)))

    quote_a = appear(t, 5.25, 0.9)
    draw.text((720, 710), "它会抵达下一双", font=fonts["hero"], fill=(*INK, round(255 * quote_a)))
    draw.text((720, 782), "愿意倾听的耳朵。", font=fonts["hero"], fill=(*INK, round(255 * quote_a)))
    draw.line((720, 892, 1030, 892), fill=(*AMBER, round(150 * quote_a)), width=2)
    draw.text((1060, 877), "共同判断 · 补充现场证据", font=fonts["label"],
              fill=(*MUTED, round(230 * quote_a)))


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--scene", choices=("today", "assist", "today_editorial", "assist_editorial"), required=True)
    parser.add_argument("--source", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--duration", type=float, required=True)
    parser.add_argument("--encoder", default="h264_nvenc")
    args = parser.parse_args()
    args.output.parent.mkdir(parents=True, exist_ok=True)

    source = Image.open(args.source).convert("RGB")
    fonts = load_fonts()
    editorial = args.scene.endswith("_editorial")
    phone = phone_layer(source, height=900, x=58, y=90) if editorial else phone_layer(source)
    codec = (["-c:v", "h264_nvenc", "-preset", "p7", "-tune", "hq", "-rc", "vbr", "-cq", "18", "-b:v", "0"]
             if args.encoder == "h264_nvenc" else ["-c:v", "libx264", "-preset", "veryfast", "-crf", "18"])
    command = ["ffmpeg", "-hide_banner", "-loglevel", "error", "-y", "-f", "rawvideo", "-pix_fmt", "rgb24",
               "-s", f"{W}x{H}", "-r", str(FPS), "-i", "-", "-an", *codec, "-pix_fmt", "yuv420p",
               "-movflags", "+faststart", str(args.output)]
    process = subprocess.Popen(command, stdin=subprocess.PIPE)
    assert process.stdin
    try:
        for index in range(round(args.duration * FPS)):
            t = index / FPS
            frame = Image.new("RGBA", (W, H), (*PAPER, 255))
            paper_texture(frame)
            frame.alpha_composite(phone)
            if args.scene == "today":
                today_scene(frame, t, fonts)
            elif args.scene == "assist":
                assist_scene(frame, t, fonts)
            elif args.scene == "today_editorial":
                today_editorial_scene(frame, t, fonts)
            else:
                assist_editorial_scene(frame, t, fonts)
            process.stdin.write(frame.convert("RGB").tobytes())
    finally:
        process.stdin.close()
    if process.wait() != 0:
        raise SystemExit("FFmpeg encode failed")


if __name__ == "__main__":
    main()
