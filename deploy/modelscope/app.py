from __future__ import annotations

import html
import logging
import shutil
from pathlib import Path

import gradio as gr
import soundfile as sf
from inference import ANALYZER
from studio_config import (
    APK_URL,
    BIRD_SPECIES_DISPLAY_THRESHOLD,
    GITHUB_URL,
    MAX_AUDIO_SECONDS,
    MAX_UPLOAD_BYTES,
    STUDIO_DIRECT_URL,
    SUPPORTED_AUDIO_SUFFIXES,
    VERSION,
    WEB_URL,
)

APP_ROOT = Path(__file__).resolve().parent
CSS_PATHS = (APP_ROOT / "theme.css", APP_ROOT / "instrument.css")
CSS = "\n".join(path.read_text(encoding="utf-8") for path in CSS_PATHS if path.exists())
gr.set_static_paths(paths=[APP_ROOT / "assets" / "ui"])
LOGGER = logging.getLogger(__name__)
ANALYSIS_PROGRESS = gr.Progress()
APP_THEME = gr.themes.Base(
    primary_hue="green",
    font=[gr.themes.Font("PingFang SC"), "Microsoft YaHei", "Noto Sans CJK SC", "sans-serif"],
    font_mono=[gr.themes.Font("Cascadia Mono"), "Consolas", "monospace"],
).set(
    loader_color="#174936",
    button_primary_background_fill="#174936",
    button_primary_background_fill_hover="#205e47",
)
APP_JS = r"""
(() => {
  const liveWave = {
    analyser: null,
    audioContext: null,
    data: null,
    frame: 0,
    phase: 0,
    source: null,
    stream: null,
  };

  const ensureLiveWaveCanvas = () => {
    const wrapper = document.querySelector("#source-audio .component-wrapper");
    if (!wrapper) return null;
    let canvas = wrapper.querySelector(".live-waveform");
    if (!canvas) {
      canvas = document.createElement("canvas");
      canvas.className = "live-waveform";
      canvas.setAttribute("aria-hidden", "true");
      wrapper.appendChild(canvas);
    }
    return canvas;
  };

  const drawLiveWave = (timestamp = window.performance.now()) => {
    const canvas = ensureLiveWaveCanvas();
    if (!canvas) {
      liveWave.frame = window.requestAnimationFrame(drawLiveWave);
      return;
    }
    const rect = canvas.getBoundingClientRect();
    const ratio = Math.min(window.devicePixelRatio || 1, 2);
    const width = Math.max(1, Math.round(rect.width * ratio));
    const height = Math.max(1, Math.round(rect.height * ratio));
    if (canvas.width !== width || canvas.height !== height) {
      canvas.width = width;
      canvas.height = height;
    }
    const context = canvas.getContext("2d");
    context.clearRect(0, 0, width, height);
    const center = height / 2;
    const isLive = Boolean(liveWave.analyser && liveWave.data);

    context.lineCap = "round";
    context.lineJoin = "round";
    context.strokeStyle = isLive ? "rgba(236, 240, 218, 0.96)" : "rgba(207, 220, 199, 0.58)";
    context.lineWidth = isLive ? 1.35 * ratio : 1 * ratio;
    context.shadowColor = isLive ? "rgba(223, 235, 207, 0.45)" : "transparent";
    context.shadowBlur = isLive ? 8 * ratio : 0;
    context.beginPath();

    if (isLive) {
      liveWave.analyser.getByteTimeDomainData(liveWave.data);
      const step = width / Math.max(1, liveWave.data.length - 1);
      for (let index = 0; index < liveWave.data.length; index += 1) {
        const normalized = (liveWave.data[index] - 128) / 128;
        const x = index * step;
        const y = center + normalized * height * 0.39;
        if (index === 0) context.moveTo(x, y);
        else context.lineTo(x, y);
      }
    } else {
      liveWave.phase = timestamp * 0.0024;
      const points = 180;
      for (let index = 0; index <= points; index += 1) {
        const progress = index / points;
        const envelope = Math.pow(Math.sin(progress * Math.PI), 1.7);
        const signal = Math.sin(progress * 34 + liveWave.phase) * 0.52
          + Math.sin(progress * 73 - liveWave.phase * 1.4) * 0.18;
        const x = progress * width;
        const y = center + signal * envelope * height * 0.045;
        if (index === 0) context.moveTo(x, y);
        else context.lineTo(x, y);
      }
    }
    context.stroke();
    liveWave.frame = window.requestAnimationFrame(drawLiveWave);
  };

  const stopLiveWave = () => {
    liveWave.source?.disconnect();
    liveWave.analyser?.disconnect();
    liveWave.source = null;
    liveWave.analyser = null;
    liveWave.data = null;
    liveWave.stream = null;
    document.querySelector("#source-audio")?.classList.remove("recording-live");
  };

  const startLiveWave = async (stream) => {
    stopLiveWave();
    const AudioContextClass = window.AudioContext || window.webkitAudioContext;
    if (!AudioContextClass || !stream?.getAudioTracks?.().length) return;
    liveWave.audioContext ||= new AudioContextClass();
    if (liveWave.audioContext.state === "suspended") await liveWave.audioContext.resume();
    const source = liveWave.audioContext.createMediaStreamSource(stream);
    const analyser = liveWave.audioContext.createAnalyser();
    analyser.fftSize = 2048;
    analyser.smoothingTimeConstant = 0.76;
    source.connect(analyser);
    liveWave.source = source;
    liveWave.analyser = analyser;
    liveWave.data = new Uint8Array(analyser.fftSize);
    liveWave.stream = stream;
    document.querySelector("#source-audio")?.classList.add("recording-live");
    stream.getAudioTracks().forEach((track) => track.addEventListener("ended", stopLiveWave, { once: true }));
  };

  if (navigator.mediaDevices?.getUserMedia && !navigator.mediaDevices.getUserMedia.__natureWaveHook) {
    const nativeGetUserMedia = navigator.mediaDevices.getUserMedia.bind(navigator.mediaDevices);
    const hookedGetUserMedia = async (constraints) => {
      const stream = await nativeGetUserMedia(constraints);
      if (constraints?.audio) startLiveWave(stream).catch(() => {});
      return stream;
    };
    hookedGetUserMedia.__natureWaveHook = true;
    navigator.mediaDevices.getUserMedia = hookedGetUserMedia;
  }
  drawLiveWave();

  const setWorkspaceView = (view) => {
    document.querySelector(".main")?.classList.toggle(
      "workspace-show-results",
      view === "results"
    );
    if (window.matchMedia("(max-width: 760px)").matches) {
      document.querySelector("#audio-input-panel")?.style.setProperty(
        "display",
        view === "results" ? "none" : "flex",
        "important"
      );
      document.querySelector("#analysis-result-panel")?.style.setProperty(
        "display",
        view === "results" ? "flex" : "none",
        "important"
      );
    }
    document.querySelectorAll("[data-workspace-view]").forEach((button) => {
      const selected = button.dataset.workspaceView === view;
      button.setAttribute("aria-selected", String(selected));
    });
  };

  const syncWorkspaceViewport = () => {
    if (!window.matchMedia("(max-width: 760px)").matches) {
      document.querySelector("#audio-input-panel")?.style.removeProperty("display");
      document.querySelector("#analysis-result-panel")?.style.removeProperty("display");
    }
  };
  window.addEventListener("resize", syncWorkspaceViewport);

  const audioHost = () => document.querySelector("#source-audio");
  const fileDrag = (event) => Array.from(event.dataTransfer?.types || []).includes("Files");
  const selectUploadSource = () => {
    const uploadButton = audioHost()?.querySelector(
      '.source-selection button[aria-label="Upload file"]'
    );
    if (uploadButton && !uploadButton.classList.contains("selected")) uploadButton.click();
  };
  const openFilePicker = () => {
    selectUploadSource();
    let attempts = 0;
    const open = () => {
      const input = audioHost()?.querySelector('input[type="file"]');
      if (!input && attempts++ < 12) {
        window.requestAnimationFrame(open);
        return;
      }
      input?.click();
    };
    open();
  };
  const clearAudioDragState = () => audioHost()?.classList.remove("audio-file-dragging");
  const deliverDroppedAudio = (files) => {
    let attempts = 0;
    const deliver = () => {
      const input = audioHost()?.querySelector('input[type="file"]');
      if (!input && attempts++ < 12) {
        window.requestAnimationFrame(deliver);
        return;
      }
      if (!input) return;
      const transfer = new DataTransfer();
      files.forEach((file) => transfer.items.add(file));
      input.files = transfer.files;
      input.dispatchEvent(new Event("change", { bubbles: true }));
    };
    deliver();
  };

  document.addEventListener("dragenter", (event) => {
    if (!fileDrag(event) || !document.querySelector("#audio-input-panel")?.contains(event.target)) return;
    selectUploadSource();
    audioHost()?.classList.add("audio-file-dragging");
  }, true);
  document.addEventListener("dragover", (event) => {
    if (!fileDrag(event) || !document.querySelector("#audio-input-panel")?.contains(event.target)) return;
    event.preventDefault();
    if (event.dataTransfer) event.dataTransfer.dropEffect = "copy";
  }, true);
  document.addEventListener("dragleave", (event) => {
    if (!event.relatedTarget || !document.querySelector("#audio-input-panel")?.contains(event.relatedTarget)) {
      clearAudioDragState();
    }
  }, true);
  document.addEventListener("drop", (event) => {
    const panel = document.querySelector("#audio-input-panel");
    if (!fileDrag(event) || !panel?.contains(event.target)) {
      clearAudioDragState();
      return;
    }
    event.preventDefault();
    event.stopPropagation();
    const files = Array.from(event.dataTransfer?.files || []);
    selectUploadSource();
    clearAudioDragState();
    if (files.length) deliverDroppedAudio(files);
  }, true);

  document.addEventListener("click", (event) => {
    const path = event.composedPath();
    if (path.some((node) => node instanceof HTMLElement && node.matches?.(".stop-button.recording, .icon-button-wrapper"))) {
      window.setTimeout(stopLiveWave, 120);
    }
    const viewTrigger = path.find(
      (node) => node instanceof HTMLElement && node.matches?.("[data-workspace-view]")
    );
    if (viewTrigger) setWorkspaceView(viewTrigger.dataset.workspaceView);

    if (path.some((node) => node instanceof HTMLElement && node.id === "drop-audio-surface")) {
      openFilePicker();
      return;
    }

    if (path.some((node) => node instanceof HTMLElement && node.id === "analyze-button")) {
      setWorkspaceView("results");
    }
    if (path.some((node) => node instanceof HTMLElement && node.id === "reset-investigation")) {
      setWorkspaceView("capture");
    }

    const trigger = path.find(
      (node) => node instanceof HTMLElement && node.matches?.(".interval-chip[data-start]")
    );
    if (!trigger) return;
    const waveformHost = Array.from(document.querySelectorAll("#source-audio *")).find(
      (node) => node.shadowRoot?.querySelector("audio")
    );
    const player = waveformHost?.shadowRoot?.querySelector("audio");
    if (!player) return;
    player.currentTime = Number(trigger.dataset.start || 0);
    player.play().catch(() => {});
  });
})();
"""


def _status_panel(label: str, message: str, *, tone: str = "neutral") -> str:
    return (
        f'<section class="status-panel status-panel--{html.escape(tone)}">'
        f'<span>{html.escape(label)}</span><p>{html.escape(message)}</p></section>'
    )


def _empty_result(message: str) -> str:
    return (
        '<section class="empty-state" role="status" aria-live="polite">'
        '<div class="empty-state__signal" aria-hidden="true"><i></i><i></i><i></i><i></i><i></i></div>'
        f'<span>等待声音</span><h3>{html.escape(message)}</h3>'
        '<p>模型只提供调查候选，最终判断仍需要回听和现场观察。</p></section>'
    )


def _signal_label(confidence: float, tentative: bool) -> tuple[str, str]:
    if tentative:
        return "待核对", "tentative"
    if confidence >= 0.72:
        return "较强线索", "strong"
    if confidence >= 0.42:
        return "一般线索", "medium"
    return "微弱线索", "weak"


def _audio_preflight(audio_path: str | None) -> tuple[bool, str, str]:
    if not audio_path:
        return False, "还没有可分析的声音。", "attention"

    path = Path(audio_path)
    if not path.is_file():
        return False, "没有找到这段录音，请重新录制或上传。", "error"

    suffix = path.suffix.lower()
    if suffix not in SUPPORTED_AUDIO_SUFFIXES:
        formats = "、".join(value.removeprefix(".").upper() for value in sorted(SUPPORTED_AUDIO_SUFFIXES))
        return False, f"暂不支持 {suffix.removeprefix('.').upper() or '未知'} 格式，请换用 {formats}。", "error"

    size_bytes = path.stat().st_size
    size_mb = size_bytes / (1024 * 1024)
    if size_bytes > MAX_UPLOAD_BYTES:
        return False, f"文件为 {size_mb:.1f} MB，超过 15 MB 上限。请先裁短或压缩后重试。", "error"
    if size_bytes <= 0:
        return False, "这段录音没有有效内容，请重新录制。", "error"

    try:
        duration = float(sf.info(str(path)).duration)
    except (RuntimeError, sf.LibsndfileError):
        duration = None

    format_name = suffix.removeprefix(".").upper()
    if duration is None:
        if not shutil.which("ffmpeg"):
            return False, f"当前运行环境无法解码 {format_name}，请换用 WAV、MP3、FLAC 或 OGG。", "error"
        return True, f"已读取 {format_name} · {size_mb:.1f} MB。分析时将自动解码，最长取前 20 秒。", "success"
    if duration <= 0:
        return False, "这段录音没有可读取的时长，请重新录制。", "error"
    if duration < 5:
        return True, f"已读取 {duration:.1f} 秒 · {size_mb:.1f} MB。可以分析，但录到 5 秒以上通常更容易找到稳定线索。", "attention"
    if duration > MAX_AUDIO_SECONDS:
        return True, f"已读取 {duration:.1f} 秒 · {size_mb:.1f} MB。本次只分析前 {MAX_AUDIO_SECONDS} 秒。", "attention"
    return True, f"已读取 {duration:.1f} 秒 · {size_mb:.1f} MB，将分析完整录音。", "success"


def inspect_audio(audio_path: str | None):
    is_valid, message, tone = _audio_preflight(audio_path)
    result_message = "声音已就绪，等待开始分析" if is_valid else "请处理录音问题后再分析"
    if not audio_path:
        result_message = "等待一段真实自然声"
    return (
        _status_panel("录音准备", message, tone=tone),
        gr.Button("分析这段声音", variant="primary", interactive=is_valid),
        _empty_result(result_message),
        _status_panel("现场观察", "完成一次分析后，这里会给出新的现场观察任务。"),
    )


def reset_investigation():
    return (
        None,
        _status_panel("录音准备", "录制或上传后，会先检查格式、大小和时长。"),
        gr.Button("分析这段声音", variant="primary", interactive=False),
        _empty_result("等待一段真实自然声"),
        _status_panel("现场观察", "分析后，这里会给出一项可以立刻执行的观察任务。"),
    )


def analyze(audio_path: str | None, progress=ANALYSIS_PROGRESS):
    is_valid, preflight_message, preflight_tone = _audio_preflight(audio_path)
    if not is_valid:
        result_message = "录音未通过检查" if audio_path else "请先录制或上传一段声音"
        return (
            _empty_result(result_message),
            _status_panel("录音准备", preflight_message, tone=preflight_tone),
            _status_panel("现场观察", "录音后，这里会给出一项可以立刻执行的观察任务。"),
        )
    try:
        progress(0.12, desc="检查录音质量")
        result = ANALYZER.analyze(audio_path)
        progress(0.84, desc="整理候选与有效声段")
    except Exception:
        LOGGER.exception("ModelScope Studio analysis failed")
        return (
            _empty_result("这段声音暂时无法分析"),
            _status_panel("录音质检", "请确认文件小于 15 MB，并换用 WAV、MP3、M4A 或 OGG 后重试。", tone="error"),
            _status_panel("现场观察", "原录音不会被修改。你可以重新上传或换一段更短的声音。"),
        )
    detections = result["detections"]
    if not detections:
        progress(1, desc="生成录音改进建议")
        return (
            _empty_result("暂时没有足够可靠的候选"),
            _status_panel("录音质检", result["quality"], tone="attention"),
            _status_panel("下一步", result["observation"]),
        )
    cards = []
    for rank, item in enumerate(detections[:5], start=1):
        species_is_specific = bool(
            item.species_name
            and not item.tentative
            and item.confidence >= BIRD_SPECIES_DISPLAY_THRESHOLD
        )
        title = item.species_name if species_is_specific else item.name_zh
        if item.species_name and not species_is_specific:
            subtitle = f"可能的物种线索：{item.species_name}"
        else:
            subtitle = item.scientific_name or item.name_zh
        interval_buttons = []
        for interval in item.intervals[:3]:
            label = f"{interval.start:.1f}–{interval.end:.1f}s"
            interval_buttons.append(
                f'<button type="button" class="interval-chip" data-start="{interval.start:.3f}" '
                f'aria-label="从 {interval.start:.1f} 秒开始回听">{html.escape(label)}</button>'
            )
        interval_html = "".join(interval_buttons) or '<span class="interval-chip interval-chip--static">全段</span>'
        signal_label, signal_tone = _signal_label(item.confidence, item.tentative)
        signal_value = max(0, min(100, round(item.confidence * 100)))
        scientific = f" · {html.escape(item.scientific_name)}" if item.scientific_name else ""
        cards.append(
            f'''<article class="candidate-card">
              <div class="candidate-rank" aria-hidden="true">{rank:02d}</div>
              <div class="candidate-copy">
                <div class="candidate-top"><h3>{html.escape(title)}</h3><span class="signal-badge signal-badge--{signal_tone}">{signal_label}</span></div>
                <p>{html.escape(subtitle)}</p>
                <div class="candidate-meta"><span>点击回听有效声段</span>{interval_html}</div>
                <details class="candidate-details"><summary>技术详情</summary><p>{html.escape(item.model)}{scientific} · 模型线索 {signal_value}/100，仅用于本次排序。</p></details>
              </div>
            </article>'''
        )
    result_html = (
        '<section class="candidate-list" role="region" aria-label="声音候选" aria-live="polite">'
        f'<div class="candidate-guide"><span>已分析 {float(result.get("duration", 0)):.1f} 秒 · 找到 {len(cards)} 条候选</span><p>弱线索先显示声音类别；具体物种仍需回听和现场核对。</p></div>'
        + "".join(cards)
        + "</section>"
    )
    progress(1, desc="生成现场观察任务")
    return (
        result_html,
        _status_panel("录音质检", result["quality"], tone="success"),
        _status_panel("下一步现场观察", result["observation"], tone="action"),
    )


def workspace_header() -> str:
    return f'''<a class="skip-link" href="#investigation">跳到录音工作台</a>
    <header class="workspace-header">
      <div class="brand-lockup" aria-label="自然声探员">
        <img class="brand-mark" src="/gradio_api/file=assets/ui/logo-mark.png" alt="" />
        <div><strong>自然声探员</strong><span>共听杭州 · {VERSION}</span></div>
      </div>
      <div class="workspace-title" aria-label="听见此刻的自然">
        <span aria-hidden="true"></span><div><strong>听见此刻的自然</strong><small>每一段真实自然声，都是此刻的证据。</small></div><span aria-hidden="true"></span>
      </div>
      <div class="workspace-view-switch" role="tablist" aria-label="工作台视图">
        <button type="button" data-workspace-view="capture" role="tab" aria-selected="true">录音</button>
        <button type="button" data-workspace-view="results" role="tab" aria-selected="false">结果</button>
      </div>
      <nav class="workspace-nav" aria-label="产品与项目链接">
        <a href="{STUDIO_DIRECT_URL}" target="_blank" rel="noopener noreferrer">全屏打开</a>
        <details class="workspace-about">
          <summary>关于与边界</summary>
          <div class="workspace-about__panel">
            <span>如何使用</span>
            <h2>录下声音，查看候选，再回到现场核对。</h2>
            <p>模型在本地运行环境中分析最长 20 秒声音。候选不是识别结论；嘈杂、混合或距离较远的录音可能无法稳定判断。</p>
            <p>请避开姓名和对话等可识别语音。上传内容只用于本次即时分析，不会自动进入训练集或公开声音册。</p>
            <div class="workspace-about__links">
              <a href="{WEB_URL}" target="_blank" rel="noopener noreferrer">完整产品</a>
              <a href="{APK_URL}" target="_blank" rel="noopener noreferrer">Android 版</a>
              <a href="{GITHUB_URL}" target="_blank" rel="noopener noreferrer">开源代码</a>
            </div>
          </div>
        </details>
      </nav>
    </header>'''


with gr.Blocks(title="自然声探员 · 共听杭州") as demo:
    gr.HTML(workspace_header())
    with gr.Row(equal_height=True, elem_id="investigation"):
        with gr.Column(scale=4, min_width=600, elem_id="audio-input-panel", elem_classes="workspace-panel input-panel"):
            gr.HTML('''<section class="instrument-heading"><div><span>FIELD INPUT · 01</span><h1>录下一段自然声音</h1></div><p>靠近目标声音，避开说话声和车辆。</p></section>''')
            audio = gr.Audio(sources=["microphone", "upload"], type="filepath", label="真实原声", elem_id="source-audio", buttons=["download"])
            gr.HTML('''<button id="drop-audio-surface" type="button"><strong>拖入一段音频，或点击选择文件</strong><small>WAV / MP3 / M4A / FLAC / OGG · 最大 15 MB</small></button>''')
            gr.HTML('''<div class="upload-notes"><span>建议 5–20 秒</span><span>最长分析前 20 秒</span><span>录音不会自动公开</span></div>''')
            submit = gr.Button("分析这段声音", variant="primary", elem_id="analyze-button", interactive=False)
            quality = gr.HTML(_status_panel("录音准备", "录制或上传后，会先检查格式、大小和时长。"), elem_id="quality-status")
            gr.HTML('''<section class="field-context" aria-label="录音现场信息">
              <div><span>录音建议</span><strong>安静时段 · 远离人声与车辆</strong></div>
              <div><span>位置（可选）</span><strong>杭州</strong></div>
              <div><span>环境（可选）</span><strong>安静 · 微风</strong></div>
            </section>''')
            gr.HTML('''<p class="privacy-note">请避开姓名和对话；录音不会自动公开或进入训练集。</p>''')
        with gr.Column(scale=1, min_width=285, elem_id="analysis-result-panel", elem_classes="workspace-panel result-panel"):
            gr.HTML('''<section class="panel-heading panel-heading--result"><div><span>FIELD NOTES · 02</span><h2>观测册</h2><p>候选，不是答案</p></div></section>''')
            result_html = gr.HTML(_empty_result("等待一段真实自然声"), elem_id="result-content")
            gr.HTML('''<ol class="rail-process" aria-label="调查流程">
              <li><span>01</span><div><strong>录下一段自然声音</strong><small>点击开始聆听，或拖入已有音频。</small></div></li>
              <li><span>02</span><div><strong>模型分析，提供候选</strong><small>线索只用于调查，不替代你的判断。</small></div></li>
              <li><span>03</span><div><strong>回听与现场观察</strong><small>结合现场环境，确认真实来源。</small></div></li>
            </ol>''')
            observation = gr.HTML(_status_panel("现场观察", "分析后，这里会给出一项可以立刻执行的观察任务。"), elem_id="observation-task")
            reset = gr.Button("清空结果，换一段声音", variant="secondary", elem_id="reset-investigation")
    audio.change(
        inspect_audio,
        inputs=audio,
        outputs=[quality, submit, result_html, observation],
        show_progress="hidden",
    )
    submit.click(analyze, inputs=audio, outputs=[result_html, quality, observation])
    reset.click(
        reset_investigation,
        outputs=[audio, quality, submit, result_html, observation],
        show_progress="hidden",
    )


if __name__ == "__main__":
    demo.queue(default_concurrency_limit=1).launch(
        css=CSS,
        js=APP_JS,
        theme=APP_THEME,
        max_file_size=MAX_UPLOAD_BYTES,
    )
