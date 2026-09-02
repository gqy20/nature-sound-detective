"""Export the competition Markdown document to a polished, reproducible PDF.

The source keeps Mermaid blocks editable. During export, the small flowchart
subset used by the document is converted to ReportLab vector drawings so the
PDF does not depend on a browser, Mermaid CLI, or screenshots.
"""

from __future__ import annotations

import argparse
import math
import re
import shutil
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path

from PIL import Image as PILImage
from reportlab.graphics.shapes import Drawing, Line, Polygon, Rect, String
from reportlab.graphics.barcode.qr import QrCodeWidget
from reportlab.lib import colors
from reportlab.lib import textsplit
from reportlab.lib.enums import TA_CENTER, TA_LEFT, TA_RIGHT
from reportlab.lib.pagesizes import A4
from reportlab.lib.styles import ParagraphStyle, getSampleStyleSheet
from reportlab.lib.units import mm
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont
from reportlab.platypus import (
    BaseDocTemplate,
    CondPageBreak,
    Frame,
    Image,
    KeepTogether,
    NextPageTemplate,
    PageBreak,
    PageTemplate,
    Paragraph,
    Spacer,
    Table,
    TableStyle,
)
from reportlab.platypus.tableofcontents import TableOfContents
import reportlab.platypus.paragraph as reportlab_paragraph


ROOT = Path(__file__).resolve().parents[1]
DEFAULT_SOURCE = ROOT / "docs/参赛项目说明书-自然声探员-v003.md"
DEFAULT_OUTPUT = ROOT / "output/pdf/自然声探员-决赛参赛项目说明书-v003.pdf"
FIGURE_WORK_DIR = ROOT / "tmp/pdfs/competition-assets"

PAGE_W, PAGE_H = A4
MARGIN_L = 22 * mm
MARGIN_R = 20 * mm
MARGIN_T = 22 * mm
MARGIN_B = 20 * mm
CONTENT_W = PAGE_W - MARGIN_L - MARGIN_R

INK = colors.HexColor("#123A31")
INK_SOFT = colors.HexColor("#42635A")
MINT = colors.HexColor("#53A889")
MINT_PALE = colors.HexColor("#EAF5F0")
GOLD = colors.HexColor("#B78A47")
WARM = colors.HexColor("#FBFAF6")
RULE = colors.HexColor("#D7E2DD")
TEXT = colors.HexColor("#263B35")
MUTED = colors.HexColor("#667872")

# ReportLab's built-in CJK table omits several Simplified Chinese full-width
# marks. Extend it so closing punctuation stays with the preceding text instead
# of appearing at the beginning of a line (中文标点避头规则).
ZH_CANNOT_START_LINE = "，。！？；：、）》】〕〉」』’”％‰℃…—"


def configure_chinese_line_breaks() -> None:
    cannot_start = "".join(dict.fromkeys(
        textsplit.ALL_CANNOT_START + ZH_CANNOT_START_LINE
    ))
    # paragraph.py imports this value directly, so both references must change.
    textsplit.ALL_CANNOT_START = cannot_start
    reportlab_paragraph.ALL_CANNOT_START = cannot_start


def register_fonts() -> None:
    user_fonts = Path.home() / "AppData/Local/Microsoft/Windows/Fonts"
    font_files = {
        "Alibaba-Regular": user_fonts / "AlibabaPuHuiTi-3-55-Regular.ttf",
        "Alibaba-Medium": user_fonts / "AlibabaPuHuiTi-3-65-Medium.ttf",
        "Alibaba-SemiBold": user_fonts / "AlibabaPuHuiTi-3-75-SemiBold.ttf",
    }
    missing = [str(path) for path in font_files.values() if not path.exists()]
    if missing:
        raise FileNotFoundError("Missing required fonts: " + ", ".join(missing))
    for name, path in font_files.items():
        pdfmetrics.registerFont(TTFont(name, str(path)))


def clean_text(text: str) -> str:
    text = text.replace("—", "-").replace("–", "-")
    text = re.sub(r"<(https?://[^>]+)>", r'<a href="\1" color="#2F765F">\1</a>', text)
    text = re.sub(r"`([^`]+)`", r'<font name="Alibaba-Medium">\1</font>', text)
    text = re.sub(r"\*\*([^*]+)\*\*", r'<font name="Alibaba-SemiBold">\1</font>', text)
    text = re.sub(r"\[([^]]+)]\(([^)]+)\)", r'<a href="\2" color="#2F765F">\1</a>', text)
    text = re.sub(r"&(?!(?:amp|lt|gt|quot|apos);)", "&amp;", text)
    return text


def build_styles() -> dict[str, ParagraphStyle]:
    base = getSampleStyleSheet()
    return {
        "cover_title": ParagraphStyle(
            "CoverTitle", parent=base["Title"], fontName="Alibaba-SemiBold", fontSize=34,
            leading=36, textColor=INK, alignment=TA_LEFT, spaceAfter=10 * mm,
        ),
        "cover_subtitle": ParagraphStyle(
            "CoverSubtitle", fontName="Alibaba-Medium", fontSize=14,
            leading=21, textColor=INK_SOFT, alignment=TA_LEFT,
        ),
        "cover_label": ParagraphStyle(
            "CoverLabel", fontName="Alibaba-Medium", fontSize=9.5,
            leading=14, textColor=MINT, alignment=TA_LEFT,
        ),
        "h2": ParagraphStyle(
            "H2", fontName="Alibaba-SemiBold", fontSize=20.5, leading=25,
            textColor=INK, spaceBefore=6 * mm, spaceAfter=4.5 * mm, keepWithNext=True,
        ),
        "h3": ParagraphStyle(
            "H3", fontName="Alibaba-SemiBold", fontSize=15.5, leading=20,
            textColor=INK, spaceBefore=5.5 * mm, spaceAfter=2.5 * mm, keepWithNext=True,
        ),
        "h4": ParagraphStyle(
            "H4", fontName="Alibaba-Medium", fontSize=12.5, leading=17,
            textColor=INK_SOFT, spaceBefore=4.5 * mm, spaceAfter=2 * mm, keepWithNext=True,
        ),
        "body": ParagraphStyle(
            "Body", fontName="Alibaba-Regular", fontSize=11.1, leading=17.8,
            textColor=TEXT, alignment=TA_LEFT, firstLineIndent=22.2,
            spaceAfter=1.6 * mm,
            wordWrap="CJK", allowWidows=0, allowOrphans=0,
        ),
        "quote": ParagraphStyle(
            "Quote", fontName="Alibaba-SemiBold", fontSize=12.3, leading=19,
            textColor=INK, wordWrap="CJK",
        ),
        "caption": ParagraphStyle(
            "Caption", fontName="Alibaba-Regular", fontSize=8.7, leading=12,
            textColor=MUTED, alignment=TA_CENTER, spaceBefore=1.5 * mm, spaceAfter=3 * mm,
        ),
        "table": ParagraphStyle(
            "TableText", fontName="Alibaba-Regular", fontSize=9.1, leading=12.8,
            textColor=TEXT, wordWrap="CJK",
        ),
        "table_head": ParagraphStyle(
            "TableHead", fontName="Alibaba-SemiBold", fontSize=9, leading=12.5,
            textColor=INK, wordWrap="CJK",
        ),
        "list": ParagraphStyle(
            "ListText", fontName="Alibaba-Regular", fontSize=11.1, leading=17.8,
            textColor=TEXT, leftIndent=0, firstLineIndent=0, wordWrap="CJK",
        ),
        "list_mark": ParagraphStyle(
            "ListMark", fontName="Alibaba-Regular", fontSize=11.1, leading=17.8,
            textColor=MINT, alignment=TA_RIGHT,
        ),
        "toc": ParagraphStyle(
            "TOC", fontName="Alibaba-Medium", fontSize=12.2, leading=23,
            textColor=TEXT, leftIndent=0, rightIndent=0,
        ),
    }


@dataclass
class MermaidNode:
    ident: str
    label: str


def parse_mermaid(source: str) -> tuple[dict[str, MermaidNode], list[tuple[str, str]]]:
    nodes: dict[str, MermaidNode] = {}
    edges: list[tuple[str, str]] = []
    for raw in source.splitlines():
        line = raw.strip()
        for ident, label in re.findall(r"([A-Za-z][A-Za-z0-9]*)\[([^]]+)]", line):
            nodes.setdefault(
                ident,
                MermaidNode(ident, label.replace("<br/>", " / ").replace("\\n", " / ")),
            )
        match = re.match(r"([A-Za-z][A-Za-z0-9]*)\s*-->\s*([A-Za-z][A-Za-z0-9]*)", line)
        if match:
            edges.append(match.groups())
    return nodes, edges


def split_label(label: str, limit: int = 10) -> list[str]:
    parts = label.split(" / ")
    result: list[str] = []
    for part in parts:
        while len(part) > limit:
            result.append(part[:limit])
            part = part[limit:]
        if part:
            result.append(part)
    return result[:3]


def add_node(drawing: Drawing, x: float, y: float, width: float, height: float,
             label: str, *, fill=colors.white, stroke=RULE, number: str | None = None) -> None:
    drawing.add(Rect(x, y, width, height, rx=7, ry=7, fillColor=fill, strokeColor=stroke, strokeWidth=1))
    if number:
        drawing.add(String(x + 4 * mm, y + height - 5.2 * mm, number, fontName="Alibaba-SemiBold",
                           fontSize=6.8, fillColor=MINT, textAnchor="start"))
    parts = split_label(label, 11 if width > 40 * mm else 8)
    line_y = y + height / 2 - (1.2 * mm if number else 0) + (len(parts) - 1) * 4
    for part in parts:
        drawing.add(String(x + width / 2, line_y, part, fontName="Alibaba-Medium", fontSize=8.1,
                           fillColor=INK, textAnchor="middle"))
        line_y -= 10


def add_arrow(drawing: Drawing, x1: float, y1: float, x2: float, y2: float, *, color=MINT) -> None:
    drawing.add(Line(x1, y1, x2, y2, strokeColor=color, strokeWidth=1.25))
    dx, dy = x2 - x1, y2 - y1
    length = max((dx * dx + dy * dy) ** 0.5, 1)
    ux, uy = dx / length, dy / length
    px, py = -uy, ux
    bx, by = x2 - ux * 5.5, y2 - uy * 5.5
    drawing.add(Polygon([x2, y2, bx + px * 2.3, by + py * 2.3, bx - px * 2.3, by - py * 2.3],
                        fillColor=color, strokeColor=color))


def journey_drawing(nodes: dict[str, MermaidNode], width: float) -> Drawing:
    order = list(nodes)
    height = 91 * mm
    drawing = Drawing(width, height)
    drawing.add(Rect(0, 0, width, height, rx=10, ry=10, fillColor=WARM, strokeColor=RULE))
    cols = 4
    gap_x = 4 * mm
    gap_y = 7 * mm
    node_w = (width - 18 * mm - gap_x * 3) / cols
    node_h = 18 * mm
    positions: list[tuple[float, float]] = []
    for index in range(len(order)):
        row, logical_col = divmod(index, cols)
        col = logical_col if row % 2 == 0 else cols - 1 - logical_col
        x = 7 * mm + col * (node_w + gap_x)
        y = height - 8 * mm - (row + 1) * node_h - row * gap_y
        positions.append((x, y))
    for index in range(len(positions) - 1):
        x, y = positions[index]
        nx, ny = positions[index + 1]
        if abs(y - ny) < 1:
            if nx > x:
                add_arrow(drawing, x + node_w, y + node_h / 2, nx - 2, ny + node_h / 2)
            else:
                add_arrow(drawing, x, y + node_h / 2, nx + node_w + 2, ny + node_h / 2)
        else:
            add_arrow(drawing, x + node_w / 2, y, nx + node_w / 2, ny + node_h + 2)
    for index, ident in enumerate(order):
        x, y = positions[index]
        add_node(drawing, x, y, node_w, node_h, nodes[ident].label, number=f"{index + 1:02d}")
    return drawing


def architecture_drawing(nodes: dict[str, MermaidNode], width: float) -> Drawing:
    # Keep the architecture compact enough to follow its heading naturally;
    # an oversized, indivisible drawing otherwise creates a false page break.
    height = 98 * mm
    drawing = Drawing(width, height)
    drawing.add(Rect(0, 0, width, height, rx=10, ry=10, fillColor=WARM, strokeColor=RULE))
    left = 8 * mm
    label_w = 25 * mm
    card_x = left + label_w + 5 * mm
    usable = width - card_x - 8 * mm
    row_h = 15 * mm
    row_gap = 3 * mm
    rows = [
        ("采集层", ["A", "B", "C"]),
        ("感知层", ["D1", "D2", "D3"]),
        ("调查层", ["E", "F", "G"]),
        ("记忆与协作", ["H", "I"]),
        ("AI 共创", ["J", "K", "L"]),
    ]
    previous_centers: list[tuple[float, float]] = []
    current_y = height - 7 * mm - row_h
    for row_index, (row_name, ids) in enumerate(rows):
        drawing.add(String(left + label_w / 2, current_y + row_h / 2 - 3, row_name,
                           fontName="Alibaba-SemiBold", fontSize=8.6, fillColor=INK_SOFT, textAnchor="middle"))
        drawing.add(Line(left + label_w - 1 * mm, current_y + 2 * mm, left + label_w - 1 * mm,
                         current_y + row_h - 2 * mm, strokeColor=MINT, strokeWidth=2))
        count = len(ids)
        gap = 4 * mm
        card_w = (usable - gap * (count - 1)) / count
        centers: list[tuple[float, float]] = []
        for col, ident in enumerate(ids):
            x = card_x + col * (card_w + gap)
            label = nodes[ident].label if ident in nodes else ident
            add_node(drawing, x, current_y, card_w, row_h, label,
                     fill=MINT_PALE if row_index in (1, 2) else colors.white)
            centers.append((x + card_w / 2, current_y + row_h / 2))
        if previous_centers:
            source_y = previous_centers[0][1] - row_h / 2
            target_y = centers[0][1] + row_h / 2
            add_arrow(drawing, card_x + usable / 2, source_y, card_x + usable / 2, target_y + 2)
        previous_centers = centers
        current_y -= row_h + row_gap
    return drawing


def mermaid_drawing(source: str, width: float) -> Drawing:
    nodes, _edges = parse_mermaid(source)
    if not nodes:
        return Drawing(width, 20 * mm)
    if "D1" in nodes:
        return architecture_drawing(nodes, width)
    return journey_drawing(nodes, width)


def image_flowable(path: Path, max_width: float, max_height: float = 105 * mm) -> Image:
    with PILImage.open(path) as picture:
        width, height = picture.size
    scale = min(max_width / width, max_height / height)
    return Image(str(path), width=width * scale, height=height * scale)


@dataclass(frozen=True)
class FigureSpec:
    """Print-oriented treatment for a long mobile screenshot."""

    mode: str = "phone"
    crop_box: tuple[int, int, int, int] | None = None
    width: float = 68 * mm
    max_height: float = 125 * mm


FIGURE_SPECS = {
    "微信图片_20260902163835_2855_24.jpg": FigureSpec(
        crop_box=(0, 0, 1260, 1900), width=84 * mm, max_height=126 * mm,
    ),
    "02-start-listening.png": FigureSpec(width=59 * mm, max_height=131 * mm),
    "03-candidate-evidence.png": FigureSpec(mode="candidate_split"),
    "04-field-observation.png": FigureSpec(
        crop_box=(0, 650, 1080, 1900), width=76 * mm, max_height=84 * mm,
    ),
    "微信图片_20260902163524_2850_24.jpg": FigureSpec(
        mode="paired", crop_box=(0, 0, 1260, 1850), width=58 * mm, max_height=92 * mm,
    ),
    "微信图片_20260902163717_2851_24.jpg": FigureSpec(
        mode="paired", crop_box=(0, 350, 1440, 2250), width=58 * mm, max_height=92 * mm,
    ),
    "微信图片_20260902163802_2853_24.jpg": FigureSpec(mode="community_split_v2"),
    "微信图片_20260902163803_2854_24.jpg": FigureSpec(
        mode="paired", crop_box=(0, 0, 1260, 2050), width=58 * mm, max_height=92 * mm,
    ),
    "微信图片_20260902163453_2849_24.jpg": FigureSpec(
        mode="paired", crop_box=(0, 0, 1260, 2500), width=58 * mm, max_height=92 * mm,
    ),
}


def cropped_image(path: Path, crop_box: tuple[int, int, int, int] | None, suffix: str) -> Path:
    """Create a non-destructive print crop under tmp/pdfs."""

    if crop_box is None:
        return path
    FIGURE_WORK_DIR.mkdir(parents=True, exist_ok=True)
    destination = FIGURE_WORK_DIR / f"{path.stem}-{suffix}.png"
    with PILImage.open(path) as picture:
        width, height = picture.size
        left, top, right, bottom = crop_box
        safe_box = (
            max(0, min(left, width - 1)),
            max(0, min(top, height - 1)),
            max(1, min(right, width)),
            max(1, min(bottom, height)),
        )
        if safe_box[2] <= safe_box[0] or safe_box[3] <= safe_box[1]:
            raise ValueError(f"Invalid crop {crop_box} for {path} ({width}x{height})")
        picture.crop(safe_box).convert("RGB").save(destination, "PNG", optimize=True)
    return destination


def figure_table(images: list[Image]) -> Table:
    columns = len(images)
    table = Table(
        [images], colWidths=[CONTENT_W / columns] * columns,
        hAlign="CENTER", splitByRow=0,
    )
    table.setStyle(TableStyle([
        ("VALIGN", (0, 0), (-1, -1), "TOP"),
        ("ALIGN", (0, 0), (-1, -1), "CENTER"),
        ("LEFTPADDING", (0, 0), (-1, -1), 2 * mm),
        ("RIGHTPADDING", (0, 0), (-1, -1), 2 * mm),
        ("TOPPADDING", (0, 0), (-1, -1), 0),
        ("BOTTOMPADDING", (0, 0), (-1, -1), 0),
    ]))
    return table


def figure_group(
    entries: list[tuple[str, str]],
    caption: str,
    source_dir: Path,
    styles: dict[str, ParagraphStyle],
) -> list[object]:
    """Render one or two screenshots as a readable, indivisible figure block."""

    resolved = [(alt, (source_dir / relative).resolve()) for alt, relative in entries]
    if not all(path.exists() for _alt, path in resolved):
        missing = [str(path) for _alt, path in resolved if not path.exists()]
        raise FileNotFoundError("Missing figure assets: " + ", ".join(missing))

    flowables: list[object] = []
    required_height = 132 * mm
    if len(resolved) == 2:
        images: list[Image] = []
        for index, (_alt, path) in enumerate(resolved, 1):
            spec = FIGURE_SPECS.get(path.name, FigureSpec(mode="paired", width=58 * mm))
            prepared = cropped_image(path, spec.crop_box, f"pair-{index}")
            images.append(image_flowable(prepared, spec.width, spec.max_height))
        flowables.append(figure_table(images))
        required_height = 105 * mm
    else:
        _alt, path = resolved[0]
        spec = FIGURE_SPECS.get(path.name, FigureSpec())
        if spec.mode == "candidate_split":
            evidence = cropped_image(path, (0, 300, 1080, 1370), "evidence")
            candidates = cropped_image(path, (0, 1280, 1080, 2250), "candidates")
            flowables.append(figure_table([
                image_flowable(evidence, 77 * mm, 80 * mm),
                image_flowable(candidates, 77 * mm, 80 * mm),
            ]))
            required_height = 92 * mm
        elif spec.mode == "community_split":
            top = cropped_image(path, (0, 0, 1080, 1120), "map")
            lower = cropped_image(path, (0, 1030, 1080, 2020), "card")
            flowables.append(figure_table([
                image_flowable(top, 77 * mm, 80 * mm),
                image_flowable(lower, 77 * mm, 80 * mm),
            ]))
            required_height = 92 * mm
        elif spec.mode == "community_split_v2":
            top = cropped_image(path, (0, 0, 1260, 1500), "map")
            lower = cropped_image(path, (0, 1370, 1260, 2780), "card")
            flowables.append(figure_table([
                image_flowable(top, 77 * mm, 80 * mm),
                image_flowable(lower, 77 * mm, 80 * mm),
            ]))
            required_height = 92 * mm
        else:
            prepared = cropped_image(path, spec.crop_box, "focus")
            flowables.append(figure_table([
                image_flowable(prepared, spec.width, spec.max_height),
            ]))
            required_height = spec.max_height + 13 * mm

    if caption:
        flowables.extend([
            Spacer(1, 1.3 * mm),
            Paragraph(clean_text(caption), styles["caption"]),
        ])
    return [CondPageBreak(required_height), KeepTogether(flowables), Spacer(1, 2.5 * mm)]


def qr_code_drawing(url: str, label: str, short_url: str) -> Drawing:
    width = 48 * mm
    height = 50 * mm
    drawing = Drawing(width, height)
    widget = QrCodeWidget(url)
    widget.barWidth = 31 * mm
    widget.barHeight = 31 * mm
    widget.x = 8.5 * mm
    widget.y = 14 * mm
    drawing.add(widget)
    drawing.add(String(
        width / 2, 8.5 * mm, label,
        fontName="Alibaba-SemiBold", fontSize=8.8, fillColor=INK, textAnchor="middle",
    ))
    drawing.add(String(
        width / 2, 3.2 * mm, short_url,
        fontName="Alibaba-Regular", fontSize=6.4, fillColor=MUTED, textAnchor="middle",
    ))
    return drawing


def experience_qr_table() -> Table:
    drawings = [
        qr_code_drawing(
            "https://github.com/gqy20/nature-sound-detective",
            "GitHub", "github.com/gqy20",
        ),
        qr_code_drawing(
            "https://modelscope.cn/studios/gqy2025/nature-sound-detective",
            "ModelScope", "modelscope.cn/studios",
        ),
        qr_code_drawing(
            "https://listen.gqy20.top/",
            "Web 展示", "listen.gqy20.top",
        ),
    ]
    table = Table([drawings], colWidths=[CONTENT_W / 3] * 3, hAlign="CENTER")
    table.setStyle(TableStyle([
        ("ALIGN", (0, 0), (-1, -1), "CENTER"),
        ("VALIGN", (0, 0), (-1, -1), "TOP"),
        ("LEFTPADDING", (0, 0), (-1, -1), 1 * mm),
        ("RIGHTPADDING", (0, 0), (-1, -1), 1 * mm),
        ("TOPPADDING", (0, 0), (-1, -1), 1 * mm),
        ("BOTTOMPADDING", (0, 0), (-1, -1), 2 * mm),
    ]))
    return table


def parse_table(lines: list[str], source_dir: Path, styles: dict[str, ParagraphStyle]) -> Table:
    is_image_gallery = any("![" in line for line in lines)
    header_cells = [cell.strip() for cell in lines[0].strip().strip("|").split("|")]
    rows: list[list[object]] = []
    for row_index, line in enumerate(lines):
        cells = [cell.strip() for cell in line.strip().strip("|").split("|")]
        if row_index == 1 and all(re.fullmatch(r":?-{3,}:?", cell) for cell in cells):
            continue
        row: list[object] = []
        for cell in cells:
            image_match = re.fullmatch(r"!\[([^]]*)]\(([^)]+)\)", cell)
            if image_match:
                image_path = (source_dir / image_match.group(2)).resolve()
                gallery_height = 105 * mm if is_image_gallery else 66 * mm
                row.append(image_flowable(
                    image_path,
                    CONTENT_W / max(1, len(cells)) - 4 * mm,
                    gallery_height,
                ))
            else:
                style = styles["table_head"] if row_index == 0 else styles["table"]
                row.append(Paragraph(clean_text(cell), style))
        rows.append(row)
    columns = len(rows[0])
    if columns == 2:
        col_widths = [CONTENT_W * 0.31, CONTENT_W * 0.69]
    elif columns == 3:
        col_widths = [CONTENT_W * 0.25, CONTENT_W * 0.25, CONTENT_W * 0.50]
        if is_image_gallery:
            col_widths = [CONTENT_W / 3] * 3
        elif header_cells[0] == "优先级":
            col_widths = [CONTENT_W * 0.12, CONTENT_W * 0.31, CONTENT_W * 0.57]
        elif header_cells[-1] == "代表提交":
            col_widths = [CONTENT_W * 0.31, CONTENT_W * 0.43, CONTENT_W * 0.26]
    elif columns == 4:
        col_widths = [CONTENT_W * 0.24, CONTENT_W * 0.14, CONTENT_W * 0.18, CONTENT_W * 0.44]
    else:
        col_widths = [CONTENT_W / columns] * columns
    table = Table(rows, colWidths=col_widths, repeatRows=1, hAlign="LEFT", splitByRow=1)
    table.setStyle(TableStyle([
        ("BACKGROUND", (0, 0), (-1, 0), MINT_PALE),
        ("TEXTCOLOR", (0, 0), (-1, 0), INK),
        ("VALIGN", (0, 0), (-1, -1), "MIDDLE"),
        ("ALIGN", (0, 0), (-1, 0), "LEFT"),
        ("LEFTPADDING", (0, 0), (-1, -1), 6),
        ("RIGHTPADDING", (0, 0), (-1, -1), 6),
        ("TOPPADDING", (0, 0), (-1, -1), 6),
        ("BOTTOMPADDING", (0, 0), (-1, -1), 6),
        ("LINEBELOW", (0, 0), (-1, 0), 1, MINT),
        ("LINEBELOW", (0, 1), (-1, -1), 0.45, RULE),
    ]))
    if is_image_gallery:
        table.setStyle(TableStyle([
            ("ALIGN", (0, 1), (-1, 1), "CENTER"),
            ("TOPPADDING", (0, 1), (-1, 1), 4 * mm),
            ("BOTTOMPADDING", (0, 1), (-1, 1), 3 * mm),
            ("VALIGN", (0, 1), (-1, 1), "BOTTOM"),
        ]))
    return table


def list_table(items: list[str], ordered: bool, styles: dict[str, ParagraphStyle]) -> Table:
    rows: list[list[Paragraph]] = []
    for index, item in enumerate(items, 1):
        mark = f"{index}." if ordered else "•"
        rows.append([
            Paragraph(mark, styles["list_mark"]),
            Paragraph(clean_text(item), styles["list"]),
        ])
    mark_width = 6 * mm
    table = Table(rows, colWidths=[mark_width, CONTENT_W - mark_width], hAlign="LEFT", splitByRow=1)
    table.setStyle(TableStyle([
        ("VALIGN", (0, 0), (-1, -1), "TOP"),
        ("LEFTPADDING", (0, 0), (0, -1), 0),
        ("RIGHTPADDING", (0, 0), (0, -1), 0.8 * mm),
        ("LEFTPADDING", (1, 0), (1, -1), 0),
        ("RIGHTPADDING", (1, 0), (1, -1), 0),
        ("TOPPADDING", (0, 0), (-1, -1), 0.6 * mm),
        ("BOTTOMPADDING", (0, 0), (-1, -1), 0.8 * mm),
    ]))
    return table


def quote_block(text: str, styles: dict[str, ParagraphStyle]) -> Table:
    """Render a restrained Chinese-document pull quote with a vertical rule."""
    table = Table(
        [["", Paragraph(clean_text(text), styles["quote"])]],
        colWidths=[2.2 * mm, CONTENT_W - 2.2 * mm],
        hAlign="LEFT",
    )
    table.setStyle(TableStyle([
        ("BACKGROUND", (0, 0), (0, 0), MINT),
        ("VALIGN", (0, 0), (-1, -1), "MIDDLE"),
        ("LEFTPADDING", (0, 0), (0, 0), 0),
        ("RIGHTPADDING", (0, 0), (0, 0), 0),
        ("TOPPADDING", (0, 0), (0, 0), 0),
        ("BOTTOMPADDING", (0, 0), (0, 0), 0),
        ("LEFTPADDING", (1, 0), (1, 0), 5 * mm),
        ("RIGHTPADDING", (1, 0), (1, 0), 4 * mm),
        ("TOPPADDING", (1, 0), (1, 0), 3 * mm),
        ("BOTTOMPADDING", (1, 0), (1, 0), 3 * mm),
        ("LINEABOVE", (1, 0), (1, 0), 0.35, RULE),
        ("LINEBELOW", (1, 0), (1, 0), 0.35, RULE),
    ]))
    return table


def markdown_story(
    source: Path,
    styles: dict[str, ParagraphStyle],
    *,
    include_toc: bool = False,
) -> list[object]:
    lines = source.read_text(encoding="utf-8").splitlines()
    story: list[object] = [NextPageTemplate("body"), PageBreak()]
    if include_toc:
        story.append(Paragraph("目录", styles["h2"]))
        toc = TableOfContents()
        toc.levelStyles = [styles["toc"]]
        toc.dotsMinLevel = 0
        toc.tableStyle = TableStyle([
            ("VALIGN", (0, 0), (-1, -1), "MIDDLE"),
            ("LEFTPADDING", (0, 0), (-1, -1), 0),
            ("RIGHTPADDING", (0, 0), (-1, -1), 0),
            ("TOPPADDING", (0, 0), (-1, -1), 1.4 * mm),
            ("BOTTOMPADDING", (0, 0), (-1, -1), 1.4 * mm),
        ])
        story.extend([toc, PageBreak()])

    i = 0
    paragraph_buffer: list[str] = []

    def flush_paragraph() -> None:
        if paragraph_buffer:
            story.append(Paragraph(clean_text(" ".join(paragraph_buffer)), styles["body"]))
            paragraph_buffer.clear()

    while i < len(lines):
        line = lines[i]
        stripped = line.strip()
        if line.startswith("## 附"):
            flush_paragraph()
            break
        if line.startswith("# ") or (line.startswith("> ") and i < 5) or stripped == "---":
            flush_paragraph()
            i += 1
            continue
        if stripped.startswith("```mermaid"):
            flush_paragraph()
            block: list[str] = []
            i += 1
            while i < len(lines) and not lines[i].strip().startswith("```"):
                block.append(lines[i])
                i += 1
            story.extend([Spacer(1, 2 * mm), mermaid_drawing("\n".join(block), CONTENT_W), Spacer(1, 4 * mm)])
            i += 1
            continue
        if stripped.startswith("```"):
            flush_paragraph()
            code: list[str] = []
            i += 1
            while i < len(lines) and not lines[i].strip().startswith("```"):
                code.append(lines[i])
                i += 1
            story.append(Paragraph(clean_text("<br/>".join(code)), styles["table"]))
            i += 1
            continue
        image_match = re.fullmatch(r"!\[([^]]*)]\(([^)]+)\)", stripped)
        if image_match:
            flush_paragraph()
            entries = [(image_match.group(1), image_match.group(2))]
            caption = ""
            cursor = i + 1
            while cursor < len(lines):
                candidate = lines[cursor].strip()
                if not candidate:
                    cursor += 1
                    continue
                next_image = re.fullmatch(r"!\[([^]]*)]\(([^)]+)\)", candidate)
                if next_image:
                    entries.append((next_image.group(1), next_image.group(2)))
                    cursor += 1
                    continue
                if candidate.startswith("*图") and candidate.endswith("*"):
                    caption = candidate[1:-1].strip()
                    cursor += 1
                break
            story.extend(figure_group(entries, caption, source.parent, styles))
            i = cursor
            continue
        if stripped.startswith("|") and stripped.endswith("|"):
            flush_paragraph()
            table_lines = []
            while i < len(lines) and lines[i].strip().startswith("|"):
                table_lines.append(lines[i])
                i += 1
            story.extend([parse_table(table_lines, source.parent, styles), Spacer(1, 4 * mm)])
            continue
        if line.startswith("## "):
            flush_paragraph()
            heading = line[3:].strip()
            story.append(Paragraph(clean_text(heading), styles["h2"]))
        elif line.startswith("### "):
            flush_paragraph()
            heading = line[4:].strip()
            if heading.startswith("8.3"):
                story.append(CondPageBreak(72 * mm))
            story.append(Paragraph(clean_text(heading), styles["h3"]))
            if heading.startswith("8.3"):
                story.extend([
                    experience_qr_table(),
                    Spacer(1, 3 * mm),
                ])
        elif line.startswith("#### "):
            flush_paragraph()
            story.append(Paragraph(clean_text(line[5:].strip()), styles["h4"]))
        elif line.startswith("> "):
            flush_paragraph()
            story.extend([
                Spacer(1, 2 * mm),
                quote_block(line[2:].strip(), styles),
                Spacer(1, 4 * mm),
            ])
        elif re.match(r"^[-*] ", stripped):
            flush_paragraph()
            items: list[str] = []
            while i < len(lines) and re.match(r"^[-*] ", lines[i].strip()):
                text = re.sub(r"^[-*] ", "", lines[i].strip())
                items.append(text)
                i += 1
            story.extend([list_table(items, False, styles), Spacer(1, 3 * mm)])
            continue
        elif re.match(r"^\d+\. ", stripped):
            flush_paragraph()
            items: list[str] = []
            while i < len(lines) and re.match(r"^\d+\. ", lines[i].strip()):
                text = re.sub(r"^\d+\. ", "", lines[i].strip())
                items.append(text)
                i += 1
            story.extend([list_table(items, True, styles), Spacer(1, 3 * mm)])
            continue
        elif stripped:
            paragraph_buffer.append(stripped)
        else:
            flush_paragraph()
        i += 1
    flush_paragraph()
    return story


class RectFlowable(Spacer):
    def __init__(self, width: float, height: float, color: colors.Color):
        super().__init__(width, height)
        self.rect_width = width
        self.rect_height = height
        self.color = color

    def draw(self) -> None:
        self.canv.setFillColor(self.color)
        self.canv.rect(0, 0, self.rect_width, self.rect_height, fill=1, stroke=0)


class CompetitionDocTemplate(BaseDocTemplate):
    """Collect H2 headings so ReportLab can build a paginated TOC."""

    def afterFlowable(self, flowable) -> None:
        if isinstance(flowable, Paragraph) and flowable.style.name == "H2":
            title = flowable.getPlainText()
            if title != "目录" and not title.startswith("附录"):
                self.notify("TOCEntry", (0, title, self.page))


def draw_cover(canvas, doc) -> None:
    canvas.saveState()
    canvas.setFillColor(WARM)
    canvas.rect(0, 0, PAGE_W, PAGE_H, fill=1, stroke=0)

    left = 24 * mm
    right = PAGE_W - 22 * mm

    # Competition identity: visible first, but deliberately quieter than the product.
    canvas.setFont("Alibaba-Medium", 10)
    canvas.setFillColor(MINT)
    canvas.drawString(left, PAGE_H - 31 * mm, "2026“小有可为”创新挑战")
    canvas.setFillColor(MUTED)
    canvas.drawRightString(right, PAGE_H - 31 * mm, "绿色发展赛道 · 项目说明书")
    canvas.setStrokeColor(RULE)
    canvas.setLineWidth(0.6)
    canvas.line(left, PAGE_H - 37 * mm, right, PAGE_H - 37 * mm)

    # Product name and value proposition form one strong, compact reading block.
    canvas.setFillColor(INK)
    canvas.setFont("Alibaba-SemiBold", 44)
    canvas.drawString(left, PAGE_H - 78 * mm, "自然声探员")
    canvas.setFillColor(MINT)
    canvas.roundRect(left, PAGE_H - 86 * mm, 37 * mm, 2.2 * mm,
                     1.1 * mm, fill=1, stroke=0)

    canvas.setFont("Alibaba-SemiBold", 20)
    canvas.setFillColor(INK_SOFT)
    canvas.drawString(left, PAGE_H - 105 * mm, "让孩子从一段自然原声出发")
    canvas.setFillColor(INK)
    canvas.drawString(left, PAGE_H - 119 * mm, "完成一次真实的自然调查")

    # Narrative question and acoustic bars: the cover borrows the product's
    # recording language instead of using a generic decorative sine curve.
    canvas.setFont("Alibaba-Medium", 12)
    canvas.setFillColor(MUTED)
    canvas.drawString(left, PAGE_H - 145 * mm, "一个看不见的声音，能带孩子走多远？")

    wave_left = left
    wave_right = right
    wave_mid = PAGE_H - 166 * mm
    wave_width = wave_right - wave_left
    canvas.setStrokeColor(colors.HexColor("#C9DDD5"))
    canvas.setLineWidth(0.45)
    canvas.line(wave_left, wave_mid, wave_right, wave_mid)
    canvas.setLineCap(1)
    bars = 72
    for index in range(bars):
        progress = index / (bars - 1)
        x = wave_left + progress * wave_width
        envelope = 0.26 + 0.74 * math.sin(math.pi * progress) ** 0.62
        texture = abs(
            math.sin(index * 0.47)
            + 0.55 * math.sin(index * 0.19 + 1.2)
            + 0.25 * math.sin(index * 0.83 + 0.4)
        )
        half_height = envelope * (1.8 + 4.6 * texture) * mm
        canvas.setStrokeColor(GOLD if 0.43 <= progress <= 0.57 else MINT)
        canvas.setLineWidth(1.35 if 0.43 <= progress <= 0.57 else 1.05)
        canvas.line(x, wave_mid - half_height, x, wave_mid + half_height)

    steps = ["听见", "记录", "AI 提供线索", "现场求证", "城市共听"]
    step_y = PAGE_H - 187 * mm
    canvas.setFont("Alibaba-Medium", 9.5)
    for index, label in enumerate(steps):
        x = wave_left + index * wave_width / (len(steps) - 1)
        canvas.setFillColor(MINT if index < len(steps) - 1 else GOLD)
        canvas.circle(x, step_y + 7 * mm, 1.45 * mm, fill=1, stroke=0)
        canvas.setFillColor(INK_SOFT)
        if index == 0:
            canvas.drawString(x, step_y, label)
        elif index == len(steps) - 1:
            canvas.drawRightString(x, step_y, label)
        else:
            canvas.drawCentredString(x, step_y, label)

    # Bottom metadata is anchored to the page edge as one restrained block.
    canvas.setStrokeColor(RULE)
    canvas.setLineWidth(0.6)
    canvas.line(left, 47 * mm, right, 47 * mm)
    canvas.setFont("Alibaba-Medium", 10.5)
    canvas.setFillColor(INK_SOFT)
    canvas.drawString(left, 36 * mm, "参赛团队｜雨林声纹队")
    canvas.setFont("Alibaba-Regular", 9.2)
    canvas.setFillColor(MUTED)
    canvas.drawString(left, 28 * mm, "所属单位｜中国科学院西双版纳热带植物园")
    canvas.drawRightString(right, 28 * mm, "葛庆宇 · 梁皓宇 · 2026 年 9 月")
    canvas.restoreState()


def draw_body(canvas, doc) -> None:
    canvas.saveState()
    canvas.setFont("Alibaba-Regular", 8)
    canvas.setFillColor(MUTED)
    canvas.drawString(MARGIN_L, 10 * mm, "自然声探员 · 小有可为绿色发展赛道")
    canvas.drawRightString(PAGE_W - MARGIN_R, 10 * mm, str(doc.page))
    canvas.setStrokeColor(RULE)
    canvas.setLineWidth(0.4)
    canvas.line(MARGIN_L, PAGE_H - 13 * mm, PAGE_W - MARGIN_R, PAGE_H - 13 * mm)
    canvas.restoreState()


def export(source: Path, output: Path, *, include_toc: bool = False) -> None:
    configure_chinese_line_breaks()
    register_fonts()
    styles = build_styles()
    output.parent.mkdir(parents=True, exist_ok=True)
    body_frame = Frame(MARGIN_L, MARGIN_B, CONTENT_W, PAGE_H - MARGIN_T - MARGIN_B,
                       leftPadding=0, rightPadding=0, topPadding=0, bottomPadding=0)
    cover_frame = Frame(MARGIN_L, MARGIN_B, CONTENT_W, PAGE_H - MARGIN_T - MARGIN_B,
                        leftPadding=0, rightPadding=0, topPadding=0, bottomPadding=0)
    doc = CompetitionDocTemplate(
        str(output), pagesize=A4, leftMargin=MARGIN_L, rightMargin=MARGIN_R,
        topMargin=MARGIN_T, bottomMargin=MARGIN_B,
        title="自然声探员 - 参赛项目说明书",
        author="葛庆宇、梁皓宇",
        subject="小有可为绿色发展赛道参赛项目",
        pageCompression=1,
    )
    doc.addPageTemplates([
        PageTemplate(id="cover", frames=[cover_frame], onPage=draw_cover),
        PageTemplate(id="body", frames=[body_frame], onPage=draw_body),
    ])
    # TOC page numbers require at least two layout passes.
    doc.multiBuild(markdown_story(source, styles, include_toc=include_toc))


def find_poppler_binary(name: str) -> Path:
    direct = shutil.which(name)
    if direct:
        path = Path(direct)
        if path.suffix.lower() == ".exe":
            return path
    runtime_root = Path.home() / ".cache/codex-runtimes/codex-primary-runtime/dependencies/native/poppler/Library/bin"
    candidate = runtime_root / f"{name}.exe"
    if candidate.exists():
        return candidate
    raise FileNotFoundError(f"Cannot find Poppler binary: {name}")


def verify_and_render(pdf_path: Path, render_dir: Path, dpi: int) -> None:
    from pypdf import PdfReader
    import pdfplumber

    render_dir.mkdir(parents=True, exist_ok=True)
    for previous in render_dir.glob("page-*.png"):
        previous.unlink()
    reader = PdfReader(str(pdf_path))
    if not reader.pages:
        raise RuntimeError("Generated PDF contains no pages")
    page_summaries = []
    with pdfplumber.open(pdf_path) as pdf:
        for index, page in enumerate(pdf.pages, 1):
            text = page.extract_text() or ""
            if index > 1 and len(text.strip()) < 20:
                raise RuntimeError(f"Page {index} appears blank or nearly blank")
            page_summaries.append((index, len(text), text.splitlines()[0] if text else ""))
    pdftoppm = find_poppler_binary("pdftoppm")
    ascii_pdf = render_dir.parent / "competition-document.pdf"
    ascii_pdf.write_bytes(pdf_path.read_bytes())
    subprocess.run([
        str(pdftoppm), "-png", "-r", str(dpi), str(ascii_pdf), str(render_dir / "page")
    ], check=True)
    rendered = sorted(render_dir.glob("page-*.png"))
    if len(rendered) != len(reader.pages):
        raise RuntimeError(f"Rendered {len(rendered)} pages for a {len(reader.pages)}-page PDF")
    print(f"Verified {len(reader.pages)} pages; rendered PNGs: {render_dir}")
    for index, chars, heading in page_summaries:
        print(f"  page {index:02d}: {chars:4d} chars | {heading[:42]}")


def main() -> None:
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    parser = argparse.ArgumentParser()
    parser.add_argument("--source", type=Path, default=DEFAULT_SOURCE)
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT)
    parser.add_argument("--toc", action="store_true", help="Include a dedicated contents page")
    parser.add_argument("--render", action="store_true", help="Render every page to PNG and run structural checks")
    parser.add_argument("--render-dir", type=Path, default=ROOT / "tmp/pdfs/competition-pages")
    parser.add_argument("--dpi", type=int, default=150)
    args = parser.parse_args()
    export(args.source.resolve(), args.output.resolve(), include_toc=args.toc)
    if args.render:
        verify_and_render(args.output.resolve(), args.render_dir.resolve(), args.dpi)
    print(args.output.resolve())


if __name__ == "__main__":
    main()
