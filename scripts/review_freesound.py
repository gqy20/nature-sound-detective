"""Local browser-based listening and annotation tool for stage-1 previews."""

from __future__ import annotations

import argparse
import csv
import json
import mimetypes
import os
import re
from datetime import datetime, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import urlparse


HTML = r"""<!doctype html>
<html lang="zh-CN"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>自然声音人工复核</title>
<style>
:root{font-family:system-ui,-apple-system,"Segoe UI",sans-serif;color:#172018;background:#edf1e9}*{box-sizing:border-box}
body{margin:0}.wrap{max-width:980px;margin:auto;padding:24px}.head,.card{background:#fff;border:1px solid #d7ded2;border-radius:16px;padding:20px;margin-bottom:16px}
h1{font-size:24px;margin:0 0 8px}.muted{color:#667064}.row{display:flex;gap:12px;flex-wrap:wrap;align-items:center}.pill{padding:5px 10px;background:#e7eee2;border-radius:99px}
audio{width:100%;margin:18px 0}.grid{display:grid;grid-template-columns:1fr 1fr;gap:14px}.field{display:flex;flex-direction:column;gap:6px}
label{font-weight:650}select,input,textarea,button{font:inherit;border:1px solid #bcc8b8;border-radius:9px;padding:10px;background:#fff}textarea{min-height:82px;resize:vertical}
button{cursor:pointer}.primary{background:#245c35;color:#fff;border-color:#245c35}.danger{background:#8b2c2c;color:#fff}.nav{display:flex;justify-content:space-between;gap:10px;margin-top:16px}
.meta{font-size:14px;line-height:1.7;word-break:break-word}.progress{height:8px;background:#dce4d7;border-radius:9px;overflow:hidden}.progress i{display:block;height:100%;background:#3b7b4e}
@media(max-width:680px){.grid{grid-template-columns:1fr}.wrap{padding:12px}}
</style></head><body><div class="wrap">
<section class="head"><h1>杭州自然声音 · 人工复核</h1><div class="row"><span id="counter"></span><span id="priority" class="pill"></span><span id="status" class="muted"></span></div><div class="progress"><i id="bar"></i></div></section>
<section class="card"><h2 id="name"></h2><div id="meta" class="meta muted"></div><audio id="audio" controls preload="metadata"></audio>
<div class="grid">
<div class="field"><label>最终类别</label><select id="final"><option value="">待判断</option><option value="background">可用背景声</option><option value="mixed">混合声景</option><option value="target_species">含目标物种</option><option value="reject">剔除</option><option value="uncertain">不确定</option></select></div>
<div class="field"><label>是否含可辨识人声</label><select id="speech"><option value="">待判断</option><option value="no">否</option><option value="yes">是</option><option value="uncertain">不确定</option></select></div>
<div class="field"><label>是否含目标物种</label><select id="target"><option value="">待判断</option><option value="no">否</option><option value="yes">是</option><option value="uncertain">不确定</option></select></div>
<div class="field"><label>有效区间（如 3.0-18.5;22-30）</label><input id="intervals" placeholder="留空表示整段或尚未判断"></div>
<div class="field"><label>复核人</label><input id="reviewer" placeholder="姓名或代号"></div>
<div class="field"><label>备注</label><textarea id="notes" placeholder="噪声、人声内容、鸟叫位置、剔除原因等"></textarea></div>
</div>
<div class="nav"><button id="prev">← 上一条</button><div class="row"><button id="reject" class="danger">快速剔除</button><button id="save" class="primary">保存并下一条 →</button></div></div></section></div>
<script>
let items=[],index=0; const $=id=>document.getElementById(id);
async function load(){items=await(await fetch('/api/items')).json(); const pending=items.findIndex(x=>x.review_status!=='human_reviewed'); index=pending<0?0:pending; render()}
function render(){const x=items[index]; if(!x)return; $('counter').textContent=`${index+1} / ${items.length}`;$('priority').textContent=`优先级 ${x.review_priority}`;$('status').textContent=x.review_status;
$('bar').style.width=`${100*(index+1)/items.length}%`;$('name').textContent=`${x.source_id||x.freesound_id||x.item_id} · ${x.name}`;
$('meta').innerHTML=`类别：${x.category_name_zh}　时长：${Number(x.duration_seconds).toFixed(1)} 秒　许可：${x.license_code}<br>复核原因：${x.review_reasons}<br>机器提示：人声 ${x.contains_speech}；目标物种 ${x.contains_target_species}；音质 ${x.quality_flag}`;
$('audio').src=`/audio/${x.item_id}`;$('final').value=x.human_final_class||'';$('speech').value=x.human_contains_speech||'';$('target').value=x.human_contains_target_species||'';$('intervals').value=x.human_valid_intervals||'';$('reviewer').value=x.human_reviewer||localStorage.reviewer||'';$('notes').value=x.human_review_notes||'';document.title=`${index+1}/${items.length} ${x.name}`}
async function save(next=true){const x=items[index], payload={dataset_key:x.dataset_key,item_id:x.item_id,human_final_class:$('final').value,human_contains_speech:$('speech').value,human_contains_target_species:$('target').value,human_valid_intervals:$('intervals').value,human_reviewer:$('reviewer').value.trim(),human_review_notes:$('notes').value.trim()};
localStorage.reviewer=payload.human_reviewer;const r=await fetch('/api/review',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(payload)});if(!r.ok){alert(await r.text());return}Object.assign(x,payload,{review_status:payload.human_final_class?'human_reviewed':'machine_labeled_needs_listening'});if(next&&index<items.length-1)index++;render()}
$('save').onclick=()=>save(true);$('reject').onclick=()=>{$('final').value='reject';save(true)};$('prev').onclick=()=>{if(index>0){index--;render()}};document.addEventListener('keydown',e=>{if(e.target.matches('input,textarea,select'))return;if(e.key==='ArrowRight')save(true);if(e.key==='ArrowLeft'&&index>0){index--;render()}if(e.key===' '){e.preventDefault();$('audio').paused?$('audio').play():$('audio').pause()}});load();
</script></body></html>"""


class ReviewStore:
    HUMAN_FIELDS = (
        "human_final_class", "human_contains_speech", "human_contains_target_species",
        "human_valid_intervals", "human_reviewer", "human_reviewed_at", "human_review_notes",
    )

    def __init__(self, queues: dict[str, Path], order: Path):
        self.queues = queues
        self.order = order

    @staticmethod
    def read(path: Path) -> list[dict[str, str]]:
        with path.open("r", encoding="utf-8-sig", newline="") as handle:
            return list(csv.DictReader(handle))

    def items(self) -> list[dict[str, str]]:
        queues = {}
        for dataset, path in self.queues.items():
            dataset_rows = self.read(path)
            queues[dataset] = {
                (row.get("item_id") or f"freesound_{row['freesound_id']}"): row
                for row in dataset_rows
            }
        items = self.read(self.order)
        for item in items:
            current = queues[item["dataset_key"]][item["item_id"]]
            for field in self.HUMAN_FIELDS + ("review_status",):
                item[field] = current.get(field, "")
        return items

    def save(self, payload: dict[str, str]) -> dict[str, str]:
        dataset = str(payload.get("dataset_key", ""))
        item_id = str(payload.get("item_id", ""))
        if dataset not in self.queues:
            raise ValueError("invalid dataset")
        final_allowed = {"", "background", "mixed", "target_species", "reject", "uncertain"}
        flag_allowed = {"", "yes", "no", "uncertain"}
        if payload.get("human_final_class", "") not in final_allowed:
            raise ValueError("invalid final class")
        if payload.get("human_contains_speech", "") not in flag_allowed:
            raise ValueError("invalid speech flag")
        if payload.get("human_contains_target_species", "") not in flag_allowed:
            raise ValueError("invalid target-species flag")
        intervals = payload.get("human_valid_intervals", "")
        if intervals and not re.fullmatch(r"\s*\d+(?:\.\d+)?\s*-\s*\d+(?:\.\d+)?(?:\s*;\s*\d+(?:\.\d+)?\s*-\s*\d+(?:\.\d+)?)*\s*", intervals):
            raise ValueError("invalid intervals; use 3.0-18.5;22-30")

        queue_path = self.queues[dataset]
        rows = self.read(queue_path)
        found = False
        for row in rows:
            row_item_id = row.get("item_id") or f"freesound_{row.get('freesound_id', '')}"
            if row_item_id != item_id:
                continue
            found = True
            for field in self.HUMAN_FIELDS:
                if field in {"human_reviewed_at"}:
                    continue
                row[field] = str(payload.get(field, "")).strip()
            row["human_reviewed_at"] = datetime.now(timezone.utc).isoformat()
            row["reviewed_class"] = row["human_final_class"]
            row["valid_intervals"] = row["human_valid_intervals"]
            row["review_status"] = "human_reviewed" if row["human_final_class"] else "machine_labeled_needs_listening"
            saved = {field: row.get(field, "") for field in self.HUMAN_FIELDS + ("review_status",)}
            break
        if not found:
            raise KeyError(item_id)

        fields = list(rows[0])
        temporary = queue_path.with_suffix(queue_path.suffix + ".tmp")
        with temporary.open("w", encoding="utf-8-sig", newline="") as handle:
            writer = csv.DictWriter(handle, fieldnames=fields, extrasaction="ignore")
            writer.writeheader(); writer.writerows(rows)
        os.replace(temporary, queue_path)
        return saved


def make_handler(store: ReviewStore):
    class Handler(BaseHTTPRequestHandler):
        def send_bytes(self, body: bytes, content_type: str, status: int = 200, headers: dict[str, str] | None = None):
            self.send_response(status); self.send_header("Content-Type", content_type); self.send_header("Content-Length", str(len(body)))
            for key, value in (headers or {}).items(): self.send_header(key, value)
            self.end_headers(); self.wfile.write(body)

        def do_GET(self):
            path = urlparse(self.path).path
            if path == "/": return self.send_bytes(HTML.encode(), "text/html; charset=utf-8")
            if path == "/api/items": return self.send_bytes(json.dumps(store.items(), ensure_ascii=False).encode(), "application/json; charset=utf-8")
            match = re.fullmatch(r"/audio/([A-Za-z0-9_]+)", path)
            if match:
                item = next((row for row in store.items() if row["item_id"] == match.group(1)), None)
                if not item: return self.send_error(404)
                audio = Path(item["local_path"]); data = audio.read_bytes(); start, end = 0, len(data)-1; status = 200
                range_header = self.headers.get("Range", "")
                range_match = re.fullmatch(r"bytes=(\d*)-(\d*)", range_header)
                if range_match:
                    start = int(range_match.group(1) or 0); end = min(int(range_match.group(2) or end), end); status = 206
                headers = {"Accept-Ranges":"bytes"}
                if status == 206: headers["Content-Range"] = f"bytes {start}-{end}/{len(data)}"
                return self.send_bytes(data[start:end+1], mimetypes.guess_type(audio.name)[0] or "audio/mpeg", status, headers)
            self.send_error(404)

        def do_POST(self):
            if urlparse(self.path).path != "/api/review": return self.send_error(404)
            try:
                payload = json.loads(self.rfile.read(int(self.headers.get("Content-Length", "0"))))
                saved = store.save(payload)
                self.send_bytes(json.dumps(saved, ensure_ascii=False).encode(), "application/json; charset=utf-8")
            except (ValueError, KeyError, json.JSONDecodeError) as exc:
                self.send_bytes(str(exc).encode(), "text/plain; charset=utf-8", 400)

        def log_message(self, format, *args):
            print(f"review-server: {format % args}")
    return Handler


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--freesound-queue", type=Path, default=Path("data/metadata/freesound_review_queue.csv"))
    parser.add_argument("--existing-queue", type=Path, default=Path("data/metadata/existing_review_queue.csv"))
    parser.add_argument("--order", type=Path, default=Path("data/metadata/unified_review_order.csv"))
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=8765)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    store = ReviewStore(
        {"freesound": args.freesound_queue.resolve(), "existing": args.existing_queue.resolve()},
        args.order.resolve(),
    )
    items = store.items()
    if args.check:
        print(json.dumps({"items": len(items), "first_id": items[0]["item_id"], "audio_exists": all(Path(row["local_path"]).exists() for row in items)}))
        return 0
    server = ThreadingHTTPServer((args.host, args.port), make_handler(store))
    print(f"Open http://{args.host}:{args.port} ({len(items)} items). Press Ctrl+C to stop.")
    try: server.serve_forever()
    except KeyboardInterrupt: pass
    finally: server.server_close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
