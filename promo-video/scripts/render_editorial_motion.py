"""Deterministic editorial motion scenes for the Nature Sound Detective promo."""

from __future__ import annotations

import argparse
import json
import math
import subprocess
from pathlib import Path

from PIL import Image, ImageDraw, ImageEnhance, ImageFilter, ImageFont

W, H, FPS = 1920, 1080, 30
OUT_W, OUT_H = W, H
SCALE = 1.0
CREAM = (247, 242, 226)
FOREST = (13, 42, 34)
GREEN = (103, 218, 154)
CYAN = (96, 196, 211)
AMBER = (245, 177, 88)
INK = (18, 43, 35)


def clamp(v, lo=0.0, hi=1.0):
    return max(lo, min(hi, v))


def smooth(v):
    v = clamp(v)
    return v * v * (3 - 2 * v)


def fade(t, start, end, ramp=0.45):
    return smooth((t-start)/ramp) * smooth((end-t)/ramp)


def scaled(value):
    if isinstance(value, (tuple, list)):
        return type(value)(scaled(item) for item in value)
    if isinstance(value, (int, float)):
        return value * SCALE
    return value


class ScaledDraw:
    def __init__(self, image):
        self.draw = ImageDraw.Draw(image)

    def line(self, xy, **kwargs):
        if "width" in kwargs:
            kwargs["width"] = max(1, round(kwargs["width"] * SCALE))
        return self.draw.line(scaled(xy), **kwargs)

    def ellipse(self, xy, **kwargs):
        if "width" in kwargs:
            kwargs["width"] = max(1, round(kwargs["width"] * SCALE))
        return self.draw.ellipse(scaled(xy), **kwargs)

    def rounded_rectangle(self, xy, **kwargs):
        if "width" in kwargs:
            kwargs["width"] = max(1, round(kwargs["width"] * SCALE))
        if "radius" in kwargs:
            kwargs["radius"] = round(kwargs["radius"] * SCALE)
        return self.draw.rounded_rectangle(scaled(xy), **kwargs)

    def text(self, xy, text, **kwargs):
        return self.draw.text(scaled(xy), text, **kwargs)


def draw_ctx(image):
    return ScaledDraw(image)


def canvas(color=(0, 0, 0, 0)):
    return Image.new("RGBA", (OUT_W, OUT_H), color)


def fonts():
    root = Path.home()/"AppData/Local/Microsoft/Windows/Fonts"
    return {
        "display": ImageFont.truetype(str(root/"SmileySans-Oblique.otf"), round(120*SCALE)),
        "display_l": ImageFont.truetype(str(root/"SmileySans-Oblique.otf"), round(170*SCALE)),
        "title": ImageFont.truetype(str(root/"AlibabaPuHuiTi-3-75-SemiBold.ttf"), round(58*SCALE)),
        "body": ImageFont.truetype(str(root/"AlibabaPuHuiTi-3-55-Regular.ttf"), round(30*SCALE)),
        "small": ImageFont.truetype(str(root/"AlibabaPuHuiTi-3-55-Regular.ttf"), round(20*SCALE)),
        "tiny": ImageFont.truetype(str(root/"AlibabaPuHuiTi-3-55-Regular.ttf"), round(15*SCALE)),
    }


def cover(image, width, height):
    scale = max(width/image.width, height/image.height)
    image = image.resize((round(image.width*scale), round(image.height*scale)), Image.Resampling.LANCZOS)
    x, y = (image.width-width)//2, (image.height-height)//2
    return image.crop((x, y, x+width, y+height))


def waveform(draw, x, y, width, amp, t, color, phase_shift=0):
    points = []
    for i in range(120):
        u = i/119
        envelope = math.sin(math.pi*u)**0.55
        wave = math.sin(u*14*math.pi+t*4+phase_shift) + 0.38*math.sin(u*37*math.pi-t*2.7)
        points.append((x+u*width, y+wave*amp*envelope))
    draw.line(points, fill=color, width=3, joint="curve")


def sampled_waveform(draw, x, y, width, amp, values, progress, color):
    """Draw the RMS amplitude envelope sampled from the exact audio clip."""
    if not values:
        return
    count = max(1, len(values) - 1)
    top = [
        (x + index / count * width, y - amp * float(value))
        for index, value in enumerate(values)
    ]
    bottom = [
        (x + index / count * width, y + amp * float(value))
        for index, value in enumerate(values)
    ]
    draw.line((x, y, x + width, y), fill=(*color[:3], max(28, color[3] // 3)), width=1)
    draw.line(top, fill=color, width=2, joint="curve")
    draw.line(bottom, fill=color, width=2, joint="curve")
    play_x = x + width * clamp(progress)
    draw.line((play_x, y - amp - 13, play_x, y + amp + 13), fill=color, width=2)
    draw.ellipse((play_x - 5, y - 5, play_x + 5, y + 5), fill=color)


def base_dark():
    image = canvas(FOREST+(255,))
    layer = canvas()
    draw = draw_ctx(layer)
    for y in range(0, H, 90):
        draw.line((0,y,W,y), fill=(*CREAM,8), width=1)
    for x in range(0, W, 120):
        draw.line((x,0,x,H), fill=(*CREAM,6), width=1)
    image.alpha_composite(layer)
    return image


def opening_frame(t, duration, f, source):
    raw = Image.open(source).convert("RGB")
    scale = 1.0 + 0.045*smooth(t/duration)
    base = cover(raw, round(OUT_W*scale), round(OUT_H*scale))
    x = round((base.width-OUT_W)*(0.25+0.35*smooth(t/duration)))
    y = round((base.height-OUT_H)*0.42)
    frame = base.crop((x,y,x+OUT_W,y+OUT_H)).convert("RGBA")
    frame = ImageEnhance.Color(frame).enhance(0.86)
    frame.alpha_composite(canvas((6,29,24,58)))
    layer = canvas()
    draw = draw_ctx(layer)
    # Sound is suggested as restrained rings around a dew drop, never a visible sci-fi wave.
    for delay, reach in ((0.0,110),(0.65,165)):
        age = t-0.4-delay
        if age >= 0:
            p = (age%2.4)/2.4
            r = 18+reach*p
            draw.ellipse((948-r,310-r,948+r,310+r), outline=(*CREAM,round(58*(1-p))), width=2)
    a = fade(t, 5.25, 7.0, 0.55)
    if a:
        draw.text((112,790), "听得见", font=f["display"], fill=(*CREAM,round(250*a)))
        draw.text((430,790), "，却还看不见", font=f["display"], fill=(*GREEN,round(250*a)))
        draw.text((118,945), "A SOUND MYSTERY BEGINS", font=f["tiny"], fill=(*CREAM,round(150*a)))
    draw.text((1720,70), "01 / 15", font=f["small"], fill=(*CREAM,100))
    frame.alpha_composite(layer)
    return frame


def technology_frame(t, duration, f):
    frame = base_dark()
    layer = canvas()
    draw = draw_ctx(layer)
    title_a = fade(t, 0.0, 5.35, 0.5)
    draw.text((92,76), "声音先被听见，再变成问题", font=f["display"], fill=(*CREAM,round(250*title_a)))

    cards = [
        (110, 350, 610, 620, "声学模型", "发现声音候选", "YAMNet · BirdNET · 杭州分类头", GREEN, 0.35),
        (760, 350, 1290, 620, "千问 3.5 Omni", "理解复杂声景", "把线索转成可以观察的问题", CYAN, 1.15),
    ]
    for x1, y1, x2, y2, label, detail, note, color, born in cards:
        a = smooth((t-born)/0.5)
        draw.rounded_rectangle((x1,y1,x2,y2),radius=28,fill=(8,31,26,round(220*a)),outline=(*color,round(135*a)),width=2)
        draw.text((x1+38,y1+42),label,font=f["title"],fill=(*CREAM,round(255*a)))
        draw.text((x1+38,y1+130),detail,font=f["body"],fill=(*color,round(245*a)))
        draw.text((x1+38,y1+190),note,font=f["small"],fill=(*CREAM,round(175*a)))

    # The audience-facing endpoint is the child's verification, not an
    # unexplained engineering "rule layer". Text is anchored to the circle
    # centre so it remains optically centred at both 1080p and native 4K.
    target = (1575, 485)
    ta = smooth((t-2.0)/0.6)
    draw.line((610,485,760,485),fill=(*GREEN,round(125*ta)),width=3)
    draw.line((1290,485,target[0]-128,485),fill=(*CYAN,round(125*ta)),width=3)
    draw.ellipse((target[0]-128,target[1]-128,target[0]+128,target[1]+128),outline=(*GREEN,round(90*ta)),width=3)
    draw.ellipse((target[0]-104,target[1]-104,target[0]+104,target[1]+104),fill=(5,24,20,round(240*ta)),outline=(*CREAM,round(125*ta)),width=2)
    draw.text((target[0],target[1]-20),"孩子",font=f["body"],anchor="mm",fill=(*CREAM,round(255*ta)))
    draw.text((target[0],target[1]+32),"确认",font=f["title"],anchor="mm",fill=(*GREEN,round(255*ta)))
    waveform(draw,98,850,1720,18,t,(*GREEN,150))
    draw.text((98,740),"AI 给出线索，孩子完成调查",font=f["title"],fill=(*CREAM,round(245*fade(t,2.3,5.4,0.6))))
    frame.alpha_composite(layer)
    return frame


def tracks_frame(t, duration, f):
    frame=canvas(CREAM+(255,))
    layer=canvas(); draw=draw_ctx(layer)
    draw.text((92,72),"真实原声，仍在作品中央",font=f["display"],fill=(*INK,245))
    draw.text((98,214),"ORIGINAL SOUND REMAINS THE EVIDENCE",font=f["tiny"],fill=(*INK,130))
    tracks=[("真实自然原声",GREEN,0.25,350),("AI 配乐",CYAN,0.8,520),("科普旁白",AMBER,1.35,690)]
    merge=(1470,610)
    for idx,(label,color,born,y) in enumerate(tracks):
        a=smooth((t-born)/0.5)
        draw.text((110,y-24),label,font=f["body"],fill=(*INK,round(235*a)))
        draw.rounded_rectangle((370,y-36,1210,y+38),radius=34,fill=(*color,round(34*a)),outline=(*color,round(110*a)),width=2)
        waveform(draw,405,y,760,14+idx*2,t,(*color,round(230*a)),idx*1.7)
        p=smooth((t-born-0.6)/2.0)
        draw.line((1210,y,1210+(merge[0]-1210)*p,y+(merge[1]-y)*p),fill=(*color,round(150*a)),width=3)
    ma=smooth((t-2.4)/0.8)
    draw.ellipse((merge[0]-115,merge[1]-115,merge[0]+115,merge[1]+115),fill=(*INK,round(238*ma)),outline=(*GREEN,round(120*ma)),width=3)
    draw.text((merge[0]-69,merge[1]-52),"自然声音",font=f["body"],fill=(*CREAM,round(255*ma)))
    draw.text((merge[0]-55,merge[1]+2),"明信片",font=f["title"],fill=(*GREEN,round(255*ma)))
    caption=fade(t,4.0,7.0,0.5)
    draw.text((110,918),"原声不是素材之一，它是调查本身。",font=f["title"],fill=(*INK,round(240*caption)))
    frame.alpha_composite(layer)
    return frame


def brand_frame(t, duration, f):
    frame=base_dark(); layer=canvas(); draw=draw_ctx(layer)
    a=smooth(t/0.6); exit_a=smooth((duration-t)/0.35); a*=exit_a
    waveform(draw,190,390,1540,24,t,(*GREEN,round(130*a)))
    draw.text((W//2,H//2-115),"自然声探员",font=f["display_l"],anchor="mm",fill=(*CREAM,round(255*a)))
    draw.text((W//2,H//2+76),"每一个孩子，都是自然声探员",font=f["title"],anchor="mm",fill=(*GREEN,round(245*a)))
    draw.text((W//2,H//2+150),"听见一声，追踪一段生命",font=f["body"],anchor="mm",fill=(*CREAM,round(205*a)))
    pulse=((t*0.7)%1); r=18+70*pulse
    draw.ellipse((W/2-r,390-r,W/2+r,390+r),outline=(*GREEN,round(80*(1-pulse)*a)),width=2)
    frame.alpha_composite(layer)
    return frame


def montage_frame(t, duration, f, sources, waveform_data):
    labels = ["鸟鸣", "蛙声", "虫鸣", "流水", "风雨"]
    colors = [GREEN, CYAN, AMBER, (108,174,214), (172,210,152)]
    cuts = [0.0, 1.30, 2.40, 3.50, 4.70, duration]
    index = next((i for i in range(5) if cuts[i] <= t < cuts[i+1]), 4)
    local = t-cuts[index]
    span = cuts[index+1]-cuts[index]
    source = sources[index]
    scale = 1.04 + 0.035*smooth(local/max(span,0.001))
    image = cover(source, round(OUT_W*scale), round(OUT_H*scale))
    x = round((image.width-OUT_W)*(0.18+0.55*index/5))
    y = round((image.height-OUT_H)*0.5)
    frame = image.crop((x,y,x+OUT_W,y+OUT_H)).convert("RGBA")
    frame = ImageEnhance.Color(frame).enhance(0.78)
    frame.alpha_composite(canvas(FOREST+(105,)))
    layer=canvas(); draw=draw_ctx(layer)
    a=smooth(local/0.18)*smooth((span-local)/0.16)
    draw.text((92,72),f"0{index+1} / 05",font=f["small"],fill=(*CREAM,round(150*a)))
    draw.text((92,205),labels[index],font=f["display_l"],fill=(*CREAM,round(255*a)))
    sampled_waveform(
        draw, 100, 850, 1500, 42,
        waveform_data[index]["waveform"], local / max(span, 0.001),
        (*colors[index], round(215*a)),
    )
    draw.text((100,930),"每一种声音，都可能是一条自然线索",font=f["body"],fill=(*CREAM,round(225*a)))
    if index == 0:
        credit = "白头鹎 · CharlesLam / iNaturalist · CC BY-SA 2.0"
    elif index == 1:
        credit = "黑斑侧褶蛙 · Kim, Hyun-tae / iNaturalist · CC BY 4.0"
    elif index == 2:
        credit = "黑蚱蝉 · chiuluan / iNaturalist · CC BY 4.0"
    else:
        credit = "Ckpixel / Wikimedia Commons · CC BY-SA 4.0" if index == 3 else "杭州雨中树叶"
    draw.text((W-90,H-70),credit,font=f["tiny"],anchor="ra",fill=(*CREAM,round(130*a)))
    frame.alpha_composite(layer)
    return frame


def main():
    global OUT_W, OUT_H, SCALE
    parser=argparse.ArgumentParser()
    parser.add_argument("--scene",choices=["opening","montage","technology","tracks","brand"],required=True)
    parser.add_argument("--output",type=Path,required=True)
    parser.add_argument("--source",type=Path)
    parser.add_argument("--frog",type=Path)
    parser.add_argument("--insect",type=Path)
    parser.add_argument("--bird",type=Path)
    parser.add_argument("--water",type=Path)
    parser.add_argument("--weather",type=Path)
    parser.add_argument("--waveforms",type=Path)
    parser.add_argument("--duration",type=float,required=True)
    parser.add_argument("--poster",type=Path)
    parser.add_argument("--width",type=int,default=1920)
    parser.add_argument("--height",type=int,default=1080)
    parser.add_argument("--encoder",default="libx264")
    args=parser.parse_args(); args.output.parent.mkdir(parents=True,exist_ok=True)
    OUT_W, OUT_H = args.width, args.height
    if abs(OUT_W / OUT_H - W / H) > 0.001:
        raise SystemExit("Only 16:9 canvases are supported")
    SCALE = OUT_W / W
    if args.poster: args.poster.parent.mkdir(parents=True,exist_ok=True)
    f=fonts()
    montage_sources = None
    montage_waveforms = None
    if args.scene == "montage":
        dawn = Image.open(args.source).convert("RGB")
        bird = Image.open(args.bird).convert("RGB") if args.bird else dawn
        frog = Image.open(args.frog).convert("RGB")
        insect = Image.open(args.insect).convert("RGB")
        water = Image.open(args.water).convert("RGB") if args.water else dawn
        weather = Image.open(args.weather).convert("RGB") if args.weather else dawn
        montage_sources = [bird, frog, insect, water, weather]
        if not args.waveforms:
            raise SystemExit("--waveforms is required for montage so audio and trace stay truthful")
        waveform_payload = json.loads(args.waveforms.read_text(encoding="utf-8"))
        montage_waveforms = waveform_payload["categories"]
        if len(montage_waveforms) != 5:
            raise SystemExit("Montage waveform data must contain exactly five categories")
    renderers={
        "opening":lambda t: opening_frame(t,args.duration,f,args.source),
        "montage":lambda t: montage_frame(t,args.duration,f,montage_sources,montage_waveforms),
        "technology":lambda t: technology_frame(t,args.duration,f),
        "tracks":lambda t: tracks_frame(t,args.duration,f),
        "brand":lambda t: brand_frame(t,args.duration,f),
    }
    codec_args = (["-c:v","h264_nvenc","-preset","p7","-tune","hq","-rc","vbr","-cq","18","-b:v","0"]
                  if args.encoder == "h264_nvenc" else
                  ["-c:v","libx264","-preset","veryfast","-crf","18"])
    cmd=["ffmpeg","-hide_banner","-loglevel","error","-y","-f","rawvideo","-pix_fmt","rgb24","-s",f"{OUT_W}x{OUT_H}","-r",str(FPS),"-i","-","-an",*codec_args,"-pix_fmt","yuv420p","-movflags","+faststart",str(args.output)]
    proc=subprocess.Popen(cmd,stdin=subprocess.PIPE); assert proc.stdin
    mid=round(args.duration*FPS*.62)
    try:
        for i in range(round(args.duration*FPS)):
            frame=renderers[args.scene](i/FPS).convert("RGB")
            if args.poster and i==mid: frame.save(args.poster,quality=94)
            proc.stdin.write(frame.tobytes())
    finally: proc.stdin.close()
    if proc.wait()!=0: raise SystemExit("FFmpeg encode failed")


if __name__=="__main__": main()
