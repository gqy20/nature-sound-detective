from pathlib import Path
import sys

from PIL import Image, ImageDraw, ImageFont


def render(path: Path, regular_path: Path, semibold_path: Path, mode: str) -> None:
    image = Image.new("RGBA", (1920, 1080), (0, 0, 0, 0))
    draw = ImageDraw.Draw(image)
    regular = ImageFont.truetype(str(regular_path), 28)
    semibold = ImageFont.truetype(str(semibold_path), 46)
    ink = (29, 53, 44, 255)
    muted = (93, 108, 99, 255)
    accent = (75, 160, 130, 255)

    draw.text((70, 65), "AI 转译线索", font=semibold, fill=ink)
    draw.line((70, 128, 260, 128), fill=accent, width=3)
    if mode == "lead":
        draw.text((900, 330), "候选不是答案", font=semibold, fill=ink)
        draw.text((900, 405), "AI 把复杂线索变成现场问题。", font=regular, fill=muted)
    else:
        draw.ellipse((900, 190, 914, 204), fill=accent)
        draw.text((932, 172), "现场核对", font=semibold, fill=ink)
        draw.text((900, 850), "让孩子观察，再决定是否确认。", font=regular, fill=muted)
    image.save(path)


def main() -> None:
    if len(sys.argv) != 5:
        raise SystemExit("usage: render_s08_sync_overlay.py <regular> <semibold> <mode> <output>")
    render(Path(sys.argv[4]), Path(sys.argv[1]), Path(sys.argv[2]), sys.argv[3])


if __name__ == "__main__":
    main()
