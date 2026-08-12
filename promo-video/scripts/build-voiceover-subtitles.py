import argparse
import json
import re
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SIDE_SCENES = {"S02", "S04", "S05", "S06", "S08", "S09", "S13"}
DARK_SCENES = {"S01", "S03", "S07", "S11", "S13", "S14", "S15"}


def srt_seconds(value: str) -> float:
    hours, minutes, rest = value.strip().replace(".", ",").split(":")
    seconds, millis = rest.split(",")
    return int(hours) * 3600 + int(minutes) * 60 + int(seconds) + int(millis) / 1000


def srt_time(value: float) -> str:
    millis = max(0, round(value * 1000))
    hours, millis = divmod(millis, 3_600_000)
    minutes, millis = divmod(millis, 60_000)
    seconds, millis = divmod(millis, 1000)
    return f"{hours:02d}:{minutes:02d}:{seconds:02d},{millis:03d}"


def ass_time(value: float) -> str:
    centis = max(0, round(value * 100))
    hours, centis = divmod(centis, 360_000)
    minutes, centis = divmod(centis, 6_000)
    seconds, centis = divmod(centis, 100)
    return f"{hours}:{minutes:02d}:{seconds:02d}.{centis:02d}"


def clean_text(text: str) -> str:
    text = re.sub(r"<#\d+(?:\.\d+)?#>", "", text)
    text = re.sub(r"\s+", " ", text).strip()
    return (text
            .replace("千问三点五 Omni", "千问 3.5 Omni")
            .replace("通义万相二点七", "通义万相 Wan 2.7"))


def parse_srt(path: Path) -> list[tuple[float, float, str]]:
    if not path.exists():
        return []
    blocks = re.split(r"\r?\n\s*\r?\n", path.read_text(encoding="utf-8-sig").strip())
    events = []
    for block in blocks:
        lines = [line.strip() for line in block.splitlines() if line.strip()]
        timing_index = next((i for i, line in enumerate(lines) if " --> " in line), None)
        if timing_index is None:
            continue
        start_text, end_text = lines[timing_index].split(" --> ", 1)
        text = clean_text("".join(lines[timing_index + 1 :]))
        if text:
            events.append((srt_seconds(start_text), srt_seconds(end_text), text))
    return events


def split_phrases(text: str, max_chars: int) -> list[str]:
    text = clean_text(text)
    if len(text) <= max_chars * 2:
        return [text]
    pieces = [part for part in re.split(r"(?<=[。！？；])", text) if part]
    groups: list[str] = []
    current = ""
    for piece in pieces:
        if current and len(current + piece) > max_chars * 2:
            groups.append(current)
            current = piece
        else:
            current += piece
    if current:
        groups.append(current)
    final: list[str] = []
    for group in groups:
        while len(group) > max_chars * 2:
            candidates = [i for i in range(max_chars, min(len(group), max_chars * 2) + 1) if group[i - 1] in "，、：；"]
            cut = candidates[-1] if candidates else max_chars * 2
            final.append(group[:cut])
            group = group[cut:]
        if group:
            final.append(group)
    return final


def two_lines(text: str, max_chars: int) -> str:
    if len(text) <= max_chars:
        return text
    low = max(1, len(text) - max_chars)
    high = min(max_chars, len(text) - 1)
    split = min(
        range(low, high + 1),
        key=lambda index: (0 if text[index - 1] in "，、：；" else 4) + abs(index - len(text) / 2),
    )
    return text[:split] + r"\N" + text[split:]


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--version", default="v011")
    args = parser.parse_args()

    config = json.loads((ROOT / "video-config.json").read_text(encoding="utf-8"))
    narration = {
        item["id"]: item for item in json.loads((ROOT / "00-brief/narration-scenes.json").read_text(encoding="utf-8"))
    }
    manifest_path = ROOT / f"06-audio/voiceover/formal/voiceover-timing-{args.version}.json"
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    timing_by_id = {item["id"]: item for item in manifest["scenes"]}

    header = """[Script Info]
ScriptType: v4.00+
PlayResX: 1920
PlayResY: 1080
WrapStyle: 2
ScaledBorderAndShadow: no

[V4+ Styles]
Format: Name, Fontname, Fontsize, PrimaryColour, SecondaryColour, OutlineColour, BackColour, Bold, Italic, Underline, StrikeOut, ScaleX, ScaleY, Spacing, Angle, BorderStyle, Outline, Shadow, Alignment, MarginL, MarginR, MarginV, Encoding
Style: StoryLight,Alibaba PuHuiTi 3.0 55 Regular,42,&H00273110,&H00273110,&H00000000,&H00000000,0,0,0,0,100,100,0.8,0,1,0,0,2,180,180,80,1
Style: StoryDark,Alibaba PuHuiTi 3.0 55 Regular,42,&H00E8F3F7,&H00E8F3F7,&H00000000,&H00000000,0,0,0,0,100,100,0.8,0,1,0,0,2,180,180,80,1
Style: SideLight,Alibaba PuHuiTi 3.0 55 Regular,42,&H00273110,&H00273110,&H00000000,&H00000000,0,0,0,0,100,100,0.8,0,1,0,0,2,700,160,80,1
Style: SideDark,Alibaba PuHuiTi 3.0 55 Regular,42,&H00E8F3F7,&H00E8F3F7,&H00000000,&H00000000,0,0,0,0,100,100,0.8,0,1,0,0,2,700,160,80,1

[Events]
Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text
"""
    ass_events: list[str] = []
    scene_ass_events: dict[str, list[str]] = {}
    global_srt: list[str] = []
    srt_index = 1

    for scene in config["scenes"]:
        scene_id = scene["id"]
        scene_ass_events[scene_id] = []
        timing = timing_by_id[scene_id]
        lead_in = float(timing["speech_start"]) - float(scene["start"])
        source_srt = Path(timing["source_subtitles"]) if timing["source_subtitles"] else Path()
        events = parse_srt(source_srt) if timing["source_subtitles"] else []
        if not events:
            events = [(0.0, float(timing["raw_duration"]), narration[scene_id]["text"])]

        max_chars = 20
        for local_start, local_end, source_text in events:
            parts = split_phrases(source_text, max_chars)
            weights = [max(1, len(re.sub(r"[，。！？；、]", "", part))) for part in parts]
            cursor = float(scene["start"]) + lead_in + local_start
            event_end = min(float(scene["end"]) - 0.08, float(scene["start"]) + lead_in + local_end)
            usable = max(0.08, event_end - cursor)
            for part, weight in zip(parts, weights):
                finish = min(event_end, cursor + usable * weight / sum(weights))
                styled = two_lines(part, max_chars).replace("{", r"\{").replace("}", r"\}")
                scene_local_start = cursor - float(scene["start"])
                if scene_id == "S10":
                    style = "SideLight" if scene_local_start < 2.1 else "StoryLight"
                elif scene_id == "S11":
                    style = "SideLight" if scene_local_start < 3.0 else "StoryDark"
                elif scene_id == "S12":
                    style = "SideLight" if scene_local_start < 3.1 else "StoryDark"
                else:
                    position = "Side" if scene_id in SIDE_SCENES else "Story"
                    tone = "Dark" if scene_id in DARK_SCENES else "Light"
                    style = position + tone
                ass_events.append(
                    f"Dialogue: 0,{ass_time(cursor)},{ass_time(finish)},{style},,0,0,0,,{{\\fad(100,120)}}{styled}"
                )
                scene_ass_events[scene_id].append(
                    f"Dialogue: 0,{ass_time(scene_local_start)},{ass_time(finish - float(scene['start']))},{style},,0,0,0,,{{\\fad(100,120)}}{styled}"
                )
                global_srt.extend([
                    str(srt_index),
                    f"{srt_time(cursor)} --> {srt_time(finish)}",
                    part,
                    "",
                ])
                srt_index += 1
                cursor = finish

    ass_path = ROOT / f"07-edit/subtitles/xykw-promo-designed-{args.version}.ass"
    srt_path = ROOT / f"07-edit/subtitles/xykw-promo-voice-timed-{args.version}.srt"
    ass_path.parent.mkdir(parents=True, exist_ok=True)
    ass_path.write_text(header + "\n".join(ass_events) + "\n", encoding="utf-8-sig")
    srt_path.write_text("\n".join(global_srt), encoding="utf-8-sig")
    scene_ass_dir = ROOT / f"07-edit/subtitles/{args.version}-scenes"
    scene_ass_dir.mkdir(parents=True, exist_ok=True)
    for scene_id, events in scene_ass_events.items():
        (scene_ass_dir / f"{scene_id}.ass").write_text(
            header + "\n".join(events) + "\n", encoding="utf-8-sig"
        )
    print(f"Wrote {ass_path}")
    print(f"Wrote {srt_path}")
    print(f"Wrote per-scene ASS files to {scene_ass_dir}")


if __name__ == "__main__":
    main()
