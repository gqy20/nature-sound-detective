from pathlib import Path
import argparse

from PIL import Image, ImageDraw, ImageFont


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("source", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()

    image = Image.open(args.source).convert("RGB")
    if image.width / image.height != 0.45:
        raise ValueError(f"Expected 9:20 portrait source, got {image.size}")

    scale = image.width / 900
    def s(value: int) -> int:
        return round(value * scale)

    draw = ImageDraw.Draw(image)
    cream = (248, 246, 238)
    mint = (207, 235, 219)
    border = (184, 181, 171)
    ink = (21, 48, 39)
    box = tuple(s(value) for value in (40, 1035, 880, 1121))

    draw.rounded_rectangle(box, radius=s(45), fill=cream, outline=border, width=s(2))
    draw.rectangle(tuple(s(value) for value in (320, 1037, 600, 1119)), fill=mint)
    draw.line(tuple(s(value) for value in (320, 1036, 320, 1120)), fill=border, width=s(2))
    draw.line(tuple(s(value) for value in (600, 1036, 600, 1120)), fill=border, width=s(2))

    font_path = Path.home() / "AppData/Local/Microsoft/Windows/Fonts/AlibabaPuHuiTi-3-65-Medium.ttf"
    font = ImageFont.truetype(str(font_path), s(29))
    labels = ((180, "今日新声"), (460, "等待协助"), (740, "本周任务"))
    for x, label in labels:
        draw.text((s(x), s(1078)), label, font=font, fill=ink, anchor="mm")

    args.output.parent.mkdir(parents=True, exist_ok=True)
    image.save(args.output, quality=96)


if __name__ == "__main__":
    main()
