import argparse
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

parser = argparse.ArgumentParser()
parser.add_argument("output", type=Path)
parser.add_argument("--width", type=int, default=1920)
parser.add_argument("--height", type=int, default=1080)
args = parser.parse_args()
out = args.output
out.parent.mkdir(parents=True, exist_ok=True)
font_root = Path.home() / "AppData/Local/Microsoft/Windows/Fonts"
regular = font_root / "AlibabaPuHuiTi-3-55-Regular.ttf"
bold = font_root / "AlibabaPuHuiTi-3-75-SemiBold.ttf"

scale = args.width / 1920
if abs(args.width / args.height - 16 / 9) > 0.001:
    raise SystemExit("Only 16:9 canvases are supported")

def pt(x, y):
    return round(x * scale), round(y * scale)

def size(value):
    return round(value * scale)

image = Image.new("RGBA", (args.width, args.height), (0, 0, 0, 0))
draw = ImageDraw.Draw(image)
ink = (21, 62, 50)

draw.text(pt(82, 250), "专用声学模型正在分析", font=ImageFont.truetype(str(bold), size(40)), fill=ink + (255,))
draw.text(pt(1320, 318), "真实振幅", font=ImageFont.truetype(str(regular), size(25)), fill=ink + (235,))
draw.text(pt(1320, 548), "频谱扫描 · 时间 × 频率", font=ImageFont.truetype(str(regular), size(25)), fill=ink + (235,))
draw.text(pt(82, 820), "逐段推理 · 候选不是结论", font=ImageFont.truetype(str(regular), size(23)), fill=ink + (185,))
draw.text(pt(82, 864), "保留不确定性，等待现场核对", font=ImageFont.truetype(str(regular), size(18)), fill=ink + (145,))
image.save(out)
