from pathlib import Path
import sys

from PIL import Image, ImageDraw, ImageFont


WIDTH = 1920
HEIGHT = 1080
INK = (30, 54, 45, 255)
MUTED = (96, 111, 102, 255)
BORDER = (190, 199, 190, 255)
ACCENT = (83, 169, 139, 255)


def main() -> None:
    if len(sys.argv) != 4:
        raise SystemExit("usage: render-real-footage-debug-overlay.py <regular-font> <semibold-font> <output.png>")

    regular_path = Path(sys.argv[1])
    semibold_path = Path(sys.argv[2])
    output_path = Path(sys.argv[3])
    output_path.parent.mkdir(parents=True, exist_ok=True)

    regular = ImageFont.truetype(str(regular_path), 27)
    semibold = ImageFont.truetype(str(semibold_path), 40)

    image = Image.new("RGBA", (WIDTH, HEIGHT), (0, 0, 0, 0))
    draw = ImageDraw.Draw(image)

    # The right-hand observation panel is deliberately flat: no drop shadow,
    # no translucent subtitle plate, and no decorative English subheading.
    draw.rounded_rectangle((623, 185, 1847, 875), radius=24, outline=BORDER, width=2)
    draw.ellipse((625, 111, 639, 125), fill=ACCENT)
    draw.text((655, 96), "现场观察影像", font=semibold, fill=INK)
    draw.text((625, 912), "声音由软件记录，影像补充现场。", font=regular, fill=MUTED)

    image.save(output_path)


if __name__ == "__main__":
    main()
