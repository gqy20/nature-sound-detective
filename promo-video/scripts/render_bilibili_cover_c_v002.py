from pathlib import Path

from PIL import Image, ImageDraw, ImageFont


ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "docs/assets/bilibili-covers/v001/cover-c-city-base.png"
OUTPUT = ROOT / "docs/assets/bilibili-covers/v002/cover-c-city-v002.png"

USER_FONTS = Path.home() / "AppData/Local/Microsoft/Windows/Fonts"
SYSTEM_FONTS = Path("C:/Windows/Fonts")

INK = (16, 55, 46, 255)
INK_SOFT = (37, 79, 68, 255)
MINT = (67, 132, 108, 255)
GOLD = (183, 138, 71, 255)


def tracked_text(draw, xy, text, font, fill, tracking):
    x, y = xy
    for character in text:
        draw.text((x, y), character, font=font, fill=fill)
        box = draw.textbbox((0, 0), character, font=font)
        x += box[2] - box[0] + tracking


def main():
    image = Image.open(SOURCE).convert("RGBA")
    draw = ImageDraw.Draw(image)

    display = ImageFont.truetype(str(USER_FONTS / "SmileySans-Oblique.otf"), 180)
    question = ImageFont.truetype(str(USER_FONTS / "SmileySans-Oblique.otf"), 132)
    eyebrow = ImageFont.truetype(str(USER_FONTS / "AlibabaPuHuiTi-3-65-Medium.ttf"), 34)

    # A compact editorial block, kept inside the left-side thumbnail safe area.
    draw.ellipse((106, 128, 121, 143), fill=MINT)
    tracked_text(draw, (146, 109), "自然声探员", eyebrow, INK_SOFT, 7)
    draw.line((107, 173, 490, 173), fill=(67, 132, 108, 115), width=2)

    draw.text((84, 174), "听见自然", font=display, fill=INK)
    draw.text((101, 368), "之后呢", font=question, fill=INK_SOFT)

    # Separate punctuation gives the question a restrained brand accent.
    q_width = draw.textlength("之后呢", font=question)
    draw.text((101 + q_width + 6, 368), "？", font=question, fill=GOLD)

    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    image.convert("RGB").save(OUTPUT, quality=96, subsampling=0)
    print(OUTPUT)


if __name__ == "__main__":
    main()
