import json
import re
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont


ROOT = Path(__file__).resolve().parents[1]
W, H = 1920, 1080
FONT_DIR = Path.home() / "AppData/Local/Microsoft/Windows/Fonts"
REGULAR = FONT_DIR / "AlibabaPuHuiTi-3-55-Regular.ttf"
MEDIUM = FONT_DIR / "AlibabaPuHuiTi-3-65-Medium.ttf"
DISPLAY = FONT_DIR / "SmileySans-Oblique.otf"


def font(path: Path, size: int):
    return ImageFont.truetype(str(path), size)


def rounded_label(draw, xy, text, fill, text_fill, fnt, radius=22, pad_x=24, pad_y=13):
    box = draw.textbbox((0, 0), text, font=fnt)
    tw, th = box[2] - box[0], box[3] - box[1]
    x, y = xy
    draw.rounded_rectangle((x, y, x + tw + pad_x * 2, y + th + pad_y * 2), radius, fill=fill)
    draw.text((x + pad_x, y + pad_y - box[1]), text, font=fnt, fill=text_fill)


OVERLAYS = {
    "S02": ("真实调查", "从一段原声开始", "01 / SOURCE"),
    "S04": ("听见", "却还看不见", "02 / LOCATE"),
    "S05": ("记录证据", "先检查声音质量", "03 / RECORD"),
    "S08": ("AI 提出候选", "孩子继续核对", "04 / VERIFY"),
    "S09": ("保存的不是答案", "是一份调查记录", "05 / ARCHIVE"),
}

V005_OVERLAYS = {
    "S02": ("真实录音", "调查从原声开始", "01 / CAPTURE", (("现场录制", "最长 20 秒，保留原始声景"), ("文件导入", "支持已有 WAV 或音频文件"))),
    "S04": ("成为探员", "每个孩子都能循声调查", "02 / LOCATE", (("认真倾听", "从看不见的生命开始"), ("孩子主导", "AI 只提供调查协助"))),
    "S05": ("小探员取证", "先录下真实声音", "03 / ANALYZE", (("录音质检", "噪声过高时提示重新录制"), ("证据片段", "查看波形、时段与置信度"))),
    "S08": ("AI 转译线索", "孩子回到现场找证据", "04 / VERIFY", (("儿童可理解", "把复杂候选变成观察问题"), ("现场验证", "树冠、灌木与重复节奏"))),
    "S09": ("小探员结案", "把发现保存成调查记录", "05 / ARCHIVE", (("调查档案", "原声、时间与观察记录"), ("隐私控制", "模糊地点，授权后再共享"))),
    "S13": ("小探员邀请 AI 共创", "把真实调查变成专属作品", "06 / CREATE", (("AI 配乐与科普语音", "帮助表达孩子的发现"), ("通义万相 Wan 2.7", "生成自然画面，真实原声保留"))),
}


def build_overlays():
    out = ROOT / "05-motion/editorial/overlays"
    out.mkdir(parents=True, exist_ok=True)
    for scene, (headline, subhead, eyebrow) in OVERLAYS.items():
        im = Image.new("RGBA", (W, H), (0, 0, 0, 0))
        d = ImageDraw.Draw(im)
        # Editorial annotations live in the negative space around the portrait recording.
        d.line((142, 174, 330, 174), fill=(31, 94, 74, 170), width=3)
        d.text((142, 120), eyebrow, font=font(MEDIUM, 22), fill=(31, 94, 74, 190))
        d.text((142, 216), headline, font=font(DISPLAY, 67), fill=(20, 57, 46, 245))
        d.text((146, 306), subhead, font=font(MEDIUM, 31), fill=(61, 77, 69, 220))
        rounded_label(d, (1450, 784), "自然声探员", (24, 65, 52, 225), (246, 243, 232, 255), font(MEDIUM, 24))
        d.ellipse((1480, 180, 1492, 192), fill=(91, 167, 124, 215))
        d.line((1486, 210, 1486, 516), fill=(40, 91, 72, 82), width=2)
        for i, label in enumerate(("听", "记", "辨", "证")):
            yy = 238 + i * 78
            d.ellipse((1468, yy - 16, 1504, yy + 20), outline=(40, 91, 72, 120), width=2)
            d.text((1475, yy - 12), label, font=font(REGULAR, 19), fill=(30, 72, 57, 190))
        im.save(out / f"{scene}-editorial-overlay-v004.png")


def build_v005_overlays():
    out = ROOT / "05-motion/editorial/overlays"
    out.mkdir(parents=True, exist_ok=True)
    for scene, (headline, subhead, eyebrow, cards) in V005_OVERLAYS.items():
        im = Image.new("RGBA", (W, H), (0, 0, 0, 0))
        d = ImageDraw.Draw(im)
        d.line((132, 132, 324, 132), fill=(39, 98, 78, 135), width=3)
        d.text((132, 172), headline, font=font(DISPLAY, 64), fill=(18, 57, 45, 245))
        d.text((136, 260), subhead, font=font(MEDIUM, 29), fill=(70, 83, 75, 225))

        card_x, card_w, card_h = 1360, 420, 116
        for i, (title, description) in enumerate(cards, start=1):
            y = 178 + (i - 1) * 142
            d.rounded_rectangle((card_x + 5, y + 7, card_x + card_w + 5, y + card_h + 7), 24, fill=(20, 48, 40, 24))
            d.rounded_rectangle((card_x, y, card_x + card_w, y + card_h), 24,
                                fill=(249, 247, 239, 238), outline=(45, 102, 82, 78), width=2)
            d.ellipse((card_x + 24, y + 28, card_x + 70, y + 74), fill=(223, 239, 228, 255))
            n = str(i)
            nb = d.textbbox((0, 0), n, font=font(MEDIUM, 20))
            d.text((card_x + 47 - (nb[2]-nb[0])/2, y + 51 - (nb[3]-nb[1])/2 - nb[1]), n,
                   font=font(MEDIUM, 20), fill=(27, 88, 68, 255))
            d.text((card_x + 90, y + 22), title, font=font(MEDIUM, 25), fill=(23, 61, 48, 245))
            d.text((card_x + 90, y + 64), description, font=font(REGULAR, 20), fill=(78, 91, 82, 220))
        if scene == "S05":
            # Fill the lower negative space with a quiet evidence trace, without inventing measurements.
            d.text((136, 612), "原声波形", font=font(MEDIUM, 23), fill=(28, 70, 55, 220))
            points = []
            for x in range(136, 514, 4):
                phase = (x - 136) / 18
                amp = 7 + 5 * abs(__import__("math").sin((x - 136) / 61))
                y = 674 + __import__("math").sin(phase) * amp
                points.append((x, y))
            d.line(points, fill=(66, 139, 105, 150), width=3)
            d.line((136, 712, 514, 712), fill=(47, 96, 76, 50), width=1)
            d.text((136, 734), "保留原声  ·  检查质量  ·  提取候选", font=font(REGULAR, 18), fill=(72, 91, 80, 180))

            d.text((1362, 610), "证据路径", font=font(MEDIUM, 22), fill=(28, 70, 55, 220))
            stages = (("01", "原声已保存"), ("02", "质量可识别"), ("03", "候选待核对"))
            for idx, (number, label) in enumerate(stages):
                yy = 672 + idx * 72
                d.ellipse((1363, yy, 1377, yy + 14), fill=(72, 150, 112, 210))
                if idx < len(stages) - 1:
                    d.line((1370, yy + 18, 1370, yy + 66), fill=(47, 105, 81, 75), width=2)
                d.text((1400, yy - 7), number, font=font(MEDIUM, 16), fill=(70, 110, 93, 155))
                d.text((1450, yy - 10), label, font=font(REGULAR, 21), fill=(46, 73, 61, 210))
        im.save(out / f"{scene}-editorial-overlay-v010.png")


def ass_time(seconds):
    cs = round(seconds * 100)
    h, rem = divmod(cs, 360000)
    m, rem = divmod(rem, 6000)
    s, c = divmod(rem, 100)
    return f"{h}:{m:02d}:{s:02d}.{c:02d}"


def phrase_groups(text):
    clauses = [x.strip() for x in re.split(r"(?<=[。！？；])|(?<=，)", text) if x.strip()]
    groups, current = [], ""
    for clause in clauses:
        if current and len(current) + len(clause) > 34:
            groups.append(current)
            current = clause
        else:
            current += clause
    if current:
        groups.append(current)
    normalized = []
    for group in groups:
        while len(group) > 38:
            cut = max((i for i in range(18, 39) if group[i-1] in "，、：；"), default=34)
            normalized.append(group[:cut])
            group = group[cut:]
        if group:
            normalized.append(group)
    return normalized


def two_lines(text, max_chars=20):
    if len(text) <= max_chars:
        return text
    low = max(5, len(text) - max_chars)
    high = min(max_chars, len(text) - 5)
    split = min(range(low, high + 1),
                key=lambda i: (0 if text[i] in "，、：" else 4) + abs(i-len(text)/2))
    if text[split] in "，、：":
        split += 1
    return text[:split] + r"\N" + text[split:]


def build_ass():
    scenes = json.loads((ROOT / "00-brief/narration-scenes.json").read_text(encoding="utf-8"))
    config = json.loads((ROOT / "video-config.json").read_text(encoding="utf-8"))
    spans = {s["id"]: (float(s["start"]), float(s["end"])) for s in config["scenes"]}
    header = """[Script Info]
ScriptType: v4.00+
PlayResX: 1920
PlayResY: 1080
WrapStyle: 2
ScaledBorderAndShadow: yes

[V4+ Styles]
Format: Name, Fontname, Fontsize, PrimaryColour, SecondaryColour, OutlineColour, BackColour, Bold, Italic, Underline, StrikeOut, ScaleX, ScaleY, Spacing, Angle, BorderStyle, Outline, Shadow, Alignment, MarginL, MarginR, MarginV, Encoding
Style: Story,Alibaba PuHuiTi 3.0 55 Regular,48,&H00F7F3E8,&H00F7F3E8,&H0020352D,&H00000000,0,0,0,0,100,100,1.2,0,1,2.4,0,2,180,180,68,1
Style: Side,Alibaba PuHuiTi 3.0 55 Regular,40,&H0020352D,&H0020352D,&H00F5F1E6,&H00000000,0,0,0,0,100,100,0.8,0,1,2.0,0,1,132,1180,76,1

[Events]
Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text
"""
    events = []
    for scene in scenes:
        start, end = spans[scene["id"]]
        groups = phrase_groups(scene["text"])
        side_caption = scene["id"] in {"S02", "S04", "S05", "S08", "S09", "S13"}
        if side_caption:
            compact = []
            for group in groups:
                while len(group) > 24:
                    cut = max((i for i in range(11, 25) if group[i-1] in "，、：；"), default=22)
                    compact.append(group[:cut])
                    group = group[cut:]
                if group:
                    compact.append(group)
            groups = compact
        weights = [max(2, len(re.sub(r"[，。！？；、]", "", g))) for g in groups]
        usable = max(0.5, end - start - 0.30)
        cursor = start + 0.16
        for group, weight in zip(groups, weights):
            duration = usable * weight / sum(weights)
            finish = min(end - 0.08, cursor + duration)
            line = two_lines(group, 13 if side_caption else 20).replace("{", r"\{").replace("}", r"\}")
            line = r"{\fad(140,160)}" + line
            style = "Side" if side_caption else "Story"
            events.append(f"Dialogue: 0,{ass_time(cursor)},{ass_time(finish)},{style},,0,0,0,,{line}")
            cursor = finish
    out = ROOT / "07-edit/subtitles/xykw-promo-designed-v010.ass"
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(header + "\n".join(events) + "\n", encoding="utf-8-sig")


def build_postcard_overlay():
    out = ROOT / "05-motion/editorial/overlays"
    im = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    d.text((116, 114), "真实原声，始终保留", font=font(DISPLAY, 73), fill=(248, 244, 232, 250))
    d.text((122, 214), "AI 让孩子的发现被看见、被听见", font=font(MEDIUM, 34), fill=(233, 239, 228, 235))
    d.line((122, 284, 402, 284), fill=(138, 202, 155, 220), width=4)
    im.save(out / "S14-postcard-overlay-v010.png")

    share = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    sd = ImageDraw.Draw(share)
    # Keep the left editorial column calm and vertically centered.
    sd.text((116, 286), "一张明信片，继续被听见", font=font(DISPLAY, 70), fill=(248, 244, 232, 250))
    chips = [
        (122, 516, 350, 594, "留在自然册", (128, 198, 151, 225)),
        (390, 516, 630, 594, "分享给家人", (235, 184, 108, 225)),
    ]
    for left, top, right, bottom, label, color in chips:
        sd.rounded_rectangle((left, top, right, bottom), radius=24, fill=(9, 40, 33, 218), outline=color, width=2)
        sd.text(((left + right) / 2, (top + bottom) / 2), label, font=font(MEDIUM, 27), anchor="mm", fill=(248, 244, 232, 246))
    share.save(out / "S14-postcard-overlay-v011.png")


def build_opening_overlay():
    out = ROOT / "05-motion/editorial/overlays"
    im = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    px = im.load()
    for y in range(H):
        strength = max(0.0, min(1.0, (y - 470) / 560))
        alpha = int(168 * strength * strength)
        for x in range(W):
            side = max(0.28, 1.0 - x / 2100)
            px[x, y] = (7, 31, 25, int(alpha * side))
    d = ImageDraw.Draw(im)
    d.text((112, 758), "一段看不见的声音，藏着什么？", font=font(DISPLAY, 76), fill=(249, 246, 237, 255))
    d.line((118, 874, 438, 874), fill=(135, 204, 155, 230), width=4)
    im.save(out / "S01-opening-title-overlay-v008.png")


if __name__ == "__main__":
    build_overlays()
    build_v005_overlays()
    build_ass()
    build_postcard_overlay()
    build_opening_overlay()
    print("Generated v004 editorial overlays and designed subtitles")
