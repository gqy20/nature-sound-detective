from __future__ import annotations

import argparse
import csv
import json
import mimetypes
import os
from pathlib import Path
import re
import sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import unquote, urlparse

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from ml.nonbird.config import load_nonbird_config


HTML = r"""<!doctype html><html lang="zh-CN"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>蛙虫声音复核</title><style>body{font:16px system-ui;margin:auto;max-width:820px;padding:24px;background:#eef2ea;color:#172018}.card{background:white;border-radius:16px;padding:20px;margin:14px 0}audio{width:100%}.grid{display:grid;grid-template-columns:1fr 1fr;gap:12px}label{display:flex;flex-direction:column;gap:5px}input,select,textarea,button{font:inherit;padding:9px}textarea{min-height:70px}.actions{display:flex;gap:8px;margin-top:14px}.approve{background:#245c35;color:white}@media(max-width:650px){.grid{grid-template-columns:1fr}}</style></head>
<body><h1>蛙虫声音人工复核</h1><div id="progress"></div><section class="card"><h2 id="title"></h2><p id="meta"></p><audio id="audio" controls></audio><div class="grid"><label>确认标签<select id="label"></select></label><label>复核人<input id="reviewer"></label><label>有效区间<input id="intervals" placeholder="例如 3.0-8.5;12-16"></label><label>备注<textarea id="notes"></textarea></label></div><div class="actions"><button onclick="save('rejected')">剔除</button><button onclick="save('uncertain')">不确定</button><button class="approve" onclick="save('human_reviewed')">确认并下一条</button></div></section>
<script>let rows=[],labels=[],i=0;const $=x=>document.getElementById(x);async function init(){const p=await(await fetch('/api/items')).json();rows=p.items;labels=p.labels;const n=rows.findIndex(x=>x.review_status==='pending');i=n<0?0:n;show()}function show(){const x=rows[i];if(!x)return;$('progress').textContent=`${i+1} / ${rows.length} · ${x.review_status}`;$('title').textContent=`${x.name_zh} · ${x.scientific_name||x.source_id}`;$('meta').textContent=`${x.period||x.locality||''} | 相似度 ${x.reference_similarity||'-'} | ${x.attribution||''}`;const start=x.start_seconds||0,end=x.end_seconds||'';$('audio').src=`/audio/${encodeURIComponent(x.source_id)}#t=${start},${end}`;$('label').innerHTML=labels.map(v=>`<option value="${v.taxon_id}" ${v.taxon_id===x.taxon_id?'selected':''}>${v.name_zh}</option>`).join('');$('reviewer').value=localStorage.reviewer||x.reviewer||'';$('intervals').value=x.valid_intervals||'';$('notes').value=x.review_notes||''}async function save(status){const x=rows[i],body={source_id:x.source_id,status,taxon_id:$('label').value,reviewer:$('reviewer').value.trim(),valid_intervals:$('intervals').value.trim(),review_notes:$('notes').value.trim()};localStorage.reviewer=body.reviewer;const r=await fetch('/api/review',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(body)});if(!r.ok){alert(await r.text());return}Object.assign(x,body,{review_status:status});if(i<rows.length-1)i++;show()}init()</script></body></html>"""


class CandidateReviewStore:
    def __init__(self, path: Path, config_path: Path | None = None):
        self.path = path
        config = load_nonbird_config(config_path) if config_path else load_nonbird_config()
        self.classes = {item.taxon_id: item for item in config.classes}

    def rows(self) -> list[dict[str, str]]:
        with self.path.open("r", encoding="utf-8-sig", newline="") as handle:
            return list(csv.DictReader(handle))

    def update(self, payload: dict[str, str]) -> dict[str, str]:
        source_id = str(payload.get("source_id", ""))
        status = str(payload.get("status", ""))
        taxon_id = str(payload.get("taxon_id", ""))
        reviewer = str(payload.get("reviewer", "")).strip()
        intervals = str(payload.get("valid_intervals", "")).strip()
        if status not in {"human_reviewed", "rejected", "uncertain"}:
            raise ValueError("invalid review status")
        if taxon_id not in self.classes:
            raise ValueError("invalid taxon_id")
        if status == "human_reviewed" and not reviewer:
            raise ValueError("确认样本必须填写复核人")
        if intervals and not re.fullmatch(
            r"\d+(?:\.\d+)?-\d+(?:\.\d+)?(?:;\d+(?:\.\d+)?-\d+(?:\.\d+)?)*",
            intervals,
        ):
            raise ValueError("有效区间格式应为 3.0-8.5;12-16")
        rows = self.rows()
        target = next((row for row in rows if row["source_id"] == source_id), None)
        if target is None:
            raise KeyError(source_id)
        item = self.classes[taxon_id]
        target.update(
            {
                "taxon_id": taxon_id,
                "name_zh": item.name_zh,
                "scientific_name": item.scientific_name or "",
                "category_id": item.category_id,
                "review_status": status,
                "reviewer": reviewer,
                "valid_intervals": intervals,
                "review_notes": str(payload.get("review_notes", "")).strip(),
            }
        )
        temporary = self.path.with_suffix(self.path.suffix + ".tmp")
        with temporary.open("w", encoding="utf-8-sig", newline="") as handle:
            writer = csv.DictWriter(handle, fieldnames=list(rows[0]))
            writer.writeheader()
            writer.writerows(rows)
        os.replace(temporary, self.path)
        return target


def make_handler(store: CandidateReviewStore):
    class Handler(BaseHTTPRequestHandler):
        def send_body(self, body: bytes, content_type: str, status: int = 200) -> None:
            self.send_response(status)
            self.send_header("Content-Type", content_type)
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)

        def do_GET(self):
            path = urlparse(self.path).path
            if path == "/":
                return self.send_body(HTML.encode(), "text/html; charset=utf-8")
            if path == "/api/items":
                labels = [
                    {"taxon_id": key, "name_zh": value.name_zh}
                    for key, value in store.classes.items()
                ]
                body = json.dumps({"items": store.rows(), "labels": labels}, ensure_ascii=False).encode()
                return self.send_body(body, "application/json; charset=utf-8")
            if path.startswith("/audio/"):
                source_id = unquote(path.removeprefix("/audio/"))
                row = next((item for item in store.rows() if item["source_id"] == source_id), None)
                if not row:
                    return self.send_error(404)
                local = Path(row.get("local_path", ""))
                if local.name and local.is_file():
                    return self.send_body(
                        local.read_bytes(),
                        mimetypes.guess_type(local.name)[0] or "application/octet-stream",
                    )
                media_url = row.get("media_url", "")
                if media_url.startswith("https://"):
                    self.send_response(302)
                    self.send_header("Location", media_url)
                    self.end_headers()
                    return
                return self.send_error(404)
            self.send_error(404)

        def do_POST(self):
            if urlparse(self.path).path != "/api/review":
                return self.send_error(404)
            try:
                payload = json.loads(self.rfile.read(int(self.headers.get("Content-Length", "0"))))
                saved = store.update(payload)
                self.send_body(json.dumps(saved, ensure_ascii=False).encode(), "application/json; charset=utf-8")
            except (ValueError, KeyError, json.JSONDecodeError) as exc:
                self.send_body(str(exc).encode(), "text/plain; charset=utf-8", 400)

        def log_message(self, format, *args):
            print(f"candidate-review: {format % args}")

    return Handler


def main() -> None:
    parser = argparse.ArgumentParser(description="在本地浏览器人工复核蛙虫声音候选")
    parser.add_argument("manifest", type=Path)
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=8766)
    parser.add_argument("--config", type=Path)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    store = CandidateReviewStore(args.manifest.resolve(), args.config)
    if args.check:
        counts: dict[str, int] = {}
        for row in store.rows():
            counts[row["review_status"]] = counts.get(row["review_status"], 0) + 1
        print(json.dumps({"items": sum(counts.values()), "statuses": counts}, ensure_ascii=False))
        return
    server = ThreadingHTTPServer((args.host, args.port), make_handler(store))
    print(f"Open http://{args.host}:{args.port} to review {len(store.rows())} candidates")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()


if __name__ == "__main__":
    main()
