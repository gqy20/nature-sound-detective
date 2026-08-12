from __future__ import annotations

import html
from pathlib import Path

import gradio as gr

from inference import ANALYZER
from studio_config import APK_URL, GITHUB_URL, VERSION, WEB_URL


CSS_PATH = Path(__file__).with_name("theme.css")
CSS = CSS_PATH.read_text(encoding="utf-8") if CSS_PATH.exists() else ""


def _empty_result(message: str) -> str:
    return f'<section class="empty-state"><span>等待声音</span><h3>{html.escape(message)}</h3><p>模型只提供调查候选，最终判断仍需要回听和现场观察。</p></section>'


def analyze(audio_path: str | None):
    if not audio_path:
        return _empty_result("请先录制或上传一段声音"), "尚未开始分析", "—"
    try:
        result = ANALYZER.analyze(audio_path)
    except Exception as exc:
        return _empty_result(f"暂时无法分析：{exc}"), "请检查音频格式后重试", "—"
    detections = result["detections"]
    if not detections:
        return _empty_result("暂时没有足够可靠的候选"), result["quality"], result["observation"]
    cards = []
    for rank, item in enumerate(detections[:5], start=1):
        title = item.species_name or item.name_zh
        subtitle = item.scientific_name or item.name_zh
        intervals = "、".join(f"{x.start:.1f}–{x.end:.1f}s" for x in item.intervals[:3]) or "全段"
        badge = "待核对" if item.tentative else "候选"
        cards.append(
            f'''<article class="candidate-card">
              <div class="candidate-rank">{rank:02d}</div>
              <div class="candidate-copy"><div class="candidate-top"><h3>{html.escape(title)}</h3><span>{badge}</span></div>
              <p>{html.escape(subtitle)}</p><small>{html.escape(item.model)} · 有效声段 {intervals}</small></div>
              <div class="candidate-score"><strong>{item.confidence * 100:.0f}</strong><i>%</i></div>
            </article>'''
        )
    return '<section class="candidate-list">' + "".join(cards) + "</section>", result["quality"], result["observation"]


def hero() -> str:
    return f'''<header class="hero">
      <div class="eyebrow">自然声探员 · {VERSION}</div>
      <h1>听见一个声音，<br><em>不必先认识它。</em></h1>
      <p>录下来，让本地声学模型提供候选；让孩子回到现场，通过倾听、观察和比较寻找答案。</p>
      <div class="hero-actions"><a href="{APK_URL}" target="_blank">下载 Android 体验包</a><a class="secondary" href="{GITHUB_URL}" target="_blank">查看开源项目 ↗</a></div>
    </header>'''


with gr.Blocks(css=CSS, title="自然声探员 · 共听杭州", theme=gr.themes.Base()) as demo:
    gr.HTML(hero())
    with gr.Tabs():
        with gr.Tab("开始调查"):
            with gr.Row(equal_height=True):
                with gr.Column(scale=5, elem_classes="input-panel"):
                    gr.Markdown("## 录下一段自然声音\n建议 5–20 秒。靠近目标声音，避开说话声和车辆。")
                    audio = gr.Audio(sources=["microphone", "upload"], type="filepath", label="真实原声")
                    submit = gr.Button("开始寻找线索", variant="primary")
                    quality = gr.Textbox(label="录音质检", interactive=False)
                with gr.Column(scale=7, elem_classes="result-panel"):
                    gr.Markdown("## 候选，不是答案")
                    result_html = gr.HTML(_empty_result("等待一段真实自然声"))
                    observation = gr.Textbox(label="下一步现场观察", interactive=False, lines=3)
            submit.click(analyze, inputs=audio, outputs=[result_html, quality, observation])
        with gr.Tab("产品闭环"):
            gr.HTML(f'''<section class="story-grid">
              <article><b>01</b><h3>听见与记录</h3><p>最长 20 秒真实原声，先检查录音是否足以成为调查证据。</p></article>
              <article><b>02</b><h3>候选与求证</h3><p>AI 和声学模型给出候选、有效声段与不确定性，孩子观察后再决定。</p></article>
              <article><b>03</b><h3>保存声音记忆</h3><p>原声、时间、模糊地点和孩子的观察共同进入私人声音册。</p></article>
              <article><b>04</b><h3>共听杭州</h3><p>经监护人单独授权，匿名线索可以等待其他自然声探员协助。</p></article>
            </section><div class="link-card"><div><span>完整交互产品</span><h2>今天，杭州正在共同倾听。</h2></div><a href="{WEB_URL}" target="_blank">打开线上体验 ↗</a></div>''')
        with gr.Tab("技术与边界"):
            gr.HTML('''<section class="tech-stack">
              <div><span>通用声景</span><strong>YAMNet</strong><p>发现鸟鸣、蛙鸣、虫鸣和环境声等通用候选。</p></div>
              <div><span>鸟类候选</span><strong>BirdNET 2.4</strong><p>结合杭州全年地理先验，从 200 种本地鸟类中寻找线索。</p></div>
              <div><span>本地类群</span><strong>Non-bird 0.1</strong><p>复用 BirdNET embedding，补充杭州蛙类与鸣虫候选。</p></div>
              <div><span>调查方法</span><strong>孩子现场核对</strong><p>模型输出不是物种定论；回听、观察和人工复核构成最终证据。</p></div>
            </section><section class="boundary"><h2>我们明确不承诺什么</h2><p>当前未接入盲源分离、目标声源提取或专用 AI 降噪。嘈杂、混合或距离较远的录音可能无法稳定判断。公开内容仅使用模糊地点，录音公开和人工复核分别授权。</p></section>''')


if __name__ == "__main__":
    demo.queue(default_concurrency_limit=2).launch()

