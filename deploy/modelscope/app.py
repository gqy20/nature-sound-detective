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
    BUILD_REVISION,
    GITHUB_URL,
    MAX_AUDIO_SECONDS,
    MAX_UPLOAD_BYTES,
    RELEASE_DATE,
    STUDIO_DIRECT_URL,
    SUPPORTED_AUDIO_SUFFIXES,
    VERSION,
    WEB_URL,
)

APP_ROOT = Path(__file__).resolve().parent
CSS_PATHS = (APP_ROOT / "theme.css", APP_ROOT / "instrument.css", APP_ROOT / "experience.css")
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

  const updateParkRecommendation = () => {
    const selected = (group) => document.querySelector(`[data-choice-group="${group}"][aria-pressed="true"]`)?.dataset.choiceValue;
    const age = selected("age");
    const time = selected("time");
    const sound = selected("sound");
    const walk = selected("walk");
    let park = sound === "bird" ? "botanical" : "wetland";
    if (sound === "frog" || time === "long") park = "wetland";
    if (sound === "water") park = "taiziwan";
    if (age === "young" || walk === "easy") park = "taiziwan";
    const recommendations = {
      wetland: {
        image: "/gradio_api/file=assets/ui/park-guide/hero-wetland.webp",
        title: "西溪湿地更适合这次探索",
        reason: "水岸、芦苇和林下生境相连，完整路线适合寻找蛙虫、鸟鸣与水声。",
      },
      botanical: {
        image: "/gradio_api/file=assets/ui/park-guide/park-botanical.webp",
        title: "杭州植物园更适合这次探索",
        reason: "林下步道集中、移动距离较短，适合在有限时间里比较不同方向的鸟鸣。",
      },
      taiziwan: {
        image: "/gradio_api/file=assets/ui/park-guide/park-taiziwan.webp",
        title: "太子湾公园更适合这次探索",
        reason: "草地与水岸路线平缓，适合低龄孩子或希望轻松步行的家庭。",
      },
    };
    const recommendation = recommendations[park];
    const image = document.querySelector("#park-result-image");
    const title = document.querySelector("#park-result-title");
    const reason = document.querySelector("#park-result-reason");
    if (image) image.src = recommendation.image;
    if (title) title.textContent = recommendation.title;
    if (reason) reason.textContent = recommendation.reason;
    document.querySelectorAll("[data-park-card]").forEach((card) => card.classList.toggle("selected", card.dataset.parkCard === park));
  };

  const downloadInvestigation = (followup) => {
    const observation = followup.querySelector("[data-observation-value][aria-pressed='true']")?.dataset.observationValue;
    if (!observation) return;
    const candidate = followup.dataset.candidate || "自然声音候选";
    const duration = followup.dataset.duration || "—";
    const quality = followup.dataset.quality || "未记录";
    const body = [
      "自然声探员 · 本地调查卡",
      "",
      `候选：${candidate}`,
      `分析时长：${duration} 秒`,
      `录音质量：${quality}`,
      `现场观察：${observation}`,
      "",
      "候选不是物种确认。请结合回听、现场环境和后续观察继续求证。",
      "这份记录在浏览器本地生成，没有上传到社区或训练集。",
    ].join("\n");
    const url = URL.createObjectURL(new Blob([body], { type: "text/plain;charset=utf-8" }));
    const anchor = document.createElement("a");
    const now = new Date();
    const localDate = [now.getFullYear(), now.getMonth() + 1, now.getDate()]
      .map((value, index) => index === 0 ? String(value) : String(value).padStart(2, "0"))
      .join("-");
    anchor.href = url;
    anchor.download = `自然声调查卡-${localDate}.txt`;
    anchor.click();
    window.setTimeout(() => URL.revokeObjectURL(url), 500);
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

    const productTrigger = path.find(
      (node) => node instanceof HTMLElement && node.matches?.("[data-product-view]")
    );
    if (productTrigger) {
      const productView = productTrigger.dataset.productView;
      const experienceActive = productView === "experience";
      const main = document.querySelector(".main");
      main?.classList.toggle("experience-mode", experienceActive);
      document.querySelectorAll("[data-product-view]").forEach((button) => {
        button.setAttribute("aria-current", String(button.dataset.productView === productView));
      });
      document.querySelectorAll(".workspace-view-switch [data-workspace-view], .mobile-experience-toggle").forEach((button) => {
        if (window.matchMedia("(max-width: 760px)").matches && experienceActive) {
          button.style.setProperty("display", "none", "important");
        } else {
          button.style.removeProperty("display");
        }
      });
      const mobileBack = document.querySelector(".mobile-workbench-toggle");
      if (mobileBack) {
        if (window.matchMedia("(max-width: 760px)").matches && experienceActive) {
          mobileBack.style.setProperty("display", "inline-flex", "important");
        } else {
          mobileBack.style.removeProperty("display");
        }
      }
      if (experienceActive) {
        document.querySelector("#product-experience")?.scrollTo({ top: 0, behavior: "smooth" });
      }
    }

    const tourTrigger = path.find(
      (node) => node instanceof HTMLElement && node.matches?.("[data-tour-target]")
    );
    if (tourTrigger) {
      document.querySelector(tourTrigger.dataset.tourTarget)?.scrollIntoView({ behavior: "smooth", block: "start" });
    }

    const familyRole = path.find(
      (node) => node instanceof HTMLElement && node.matches?.("[data-family-role]")
    );
    if (familyRole) {
      const familyDemo = document.querySelector(".family-demo");
      familyDemo?.setAttribute("data-active-role", familyRole.dataset.familyRole);
      document.querySelectorAll("[data-family-role]").forEach((button) => {
        button.setAttribute("aria-pressed", String(button === familyRole));
      });
    }

    const choice = path.find(
      (node) => node instanceof HTMLElement && node.matches?.("[data-choice-group]")
    );
    if (choice) {
      document.querySelectorAll(`[data-choice-group="${choice.dataset.choiceGroup}"]`).forEach((button) => {
        button.setAttribute("aria-pressed", String(button === choice));
      });
      updateParkRecommendation();
    }

    const resultView = path.find(
      (node) => node instanceof HTMLElement && node.matches?.("[data-result-view]")
    );
    if (resultView) {
      const followup = resultView.closest(".investigation-followup");
      const view = resultView.dataset.resultView;
      followup?.querySelectorAll("[data-result-view]").forEach((button) => button.setAttribute("aria-pressed", String(button === resultView)));
      followup?.querySelectorAll("[data-result-panel]").forEach((panel) => panel.toggleAttribute("hidden", panel.dataset.resultPanel !== view));
    }

    const observationChoice = path.find(
      (node) => node instanceof HTMLElement && node.matches?.("[data-observation-value]")
    );
    if (observationChoice) {
      const followup = observationChoice.closest(".investigation-followup");
      followup?.querySelectorAll("[data-observation-value]").forEach((button) => button.setAttribute("aria-pressed", String(button === observationChoice)));
      const summary = followup?.querySelector("[data-investigation-summary]");
      const status = followup?.querySelector("[data-investigation-status]");
      const download = followup?.querySelector("[data-download-investigation]");
      if (summary) summary.textContent = observationChoice.dataset.observationValue || "已记录一条现场观察";
      if (status) status.textContent = "现场观察已记录，这次调查可以保存到本机。";
      if (download) download.removeAttribute("disabled");
    }

    const downloadTrigger = path.find(
      (node) => node instanceof HTMLElement && node.matches?.("[data-download-investigation]")
    );
    if (downloadTrigger && !downloadTrigger.hasAttribute("disabled")) {
      const followup = downloadTrigger.closest(".investigation-followup");
      if (followup) downloadInvestigation(followup);
    }

    const soundMarker = path.find(
      (node) => node instanceof HTMLElement && node.matches?.("[data-sound-marker]")
    );
    if (soundMarker) {
      document.querySelectorAll("[data-sound-marker]").forEach((marker) => marker.classList.toggle("selected", marker === soundMarker));
      const title = document.querySelector("#map-selection-title");
      const detail = document.querySelector("#map-selection-detail");
      if (title) title.textContent = soundMarker.dataset.markerTitle || "杭州声音线索";
      if (detail) detail.textContent = soundMarker.dataset.markerDetail || "公开分区 · 模糊位置";
    }

    const exampleTrigger = path.find(
      (node) => node instanceof HTMLElement && node.matches?.("[data-example-audio]")
    );
    if (exampleTrigger) {
      exampleTrigger.setAttribute("aria-busy", "true");
      exampleTrigger.textContent = "正在载入示例…";
      fetch(exampleTrigger.dataset.exampleAudio)
        .then((response) => {
          if (!response.ok) throw new Error("example unavailable");
          return response.blob();
        })
        .then((blob) => {
          selectUploadSource();
          deliverDroppedAudio([new File([blob], "公共领域流水示例.ogg", { type: blob.type || "audio/ogg" })]);
          exampleTrigger.textContent = "流水示例已载入";
        })
        .catch(() => {
          exampleTrigger.textContent = "示例暂时无法载入";
        })
        .finally(() => exampleTrigger.removeAttribute("aria-busy"));
    }

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


def _display_detection_title(item) -> str:
    species_is_specific = bool(
        item.species_name
        and not item.tentative
        and item.confidence >= BIRD_SPECIES_DISPLAY_THRESHOLD
    )
    return item.species_name if species_is_specific else item.name_zh


def _investigation_followup(primary, result: dict) -> str:
    category = primary.category_id
    title = _display_detection_title(primary)
    prompt, choices = {
        "bird": ("声音主要从哪里传来？", ("树冠方向", "灌木附近", "地面附近", "暂时不清楚")),
        "frog": ("声音和水边的距离怎样？", ("靠近水边", "来自草丛", "在更远处", "暂时不清楚")),
        "insect": ("这段声音的节奏怎样？", ("连续出现", "间隔重复", "忽强忽弱", "暂时不清楚")),
        "rain": ("雨滴落在什么表面？", ("树叶", "泥土或草地", "屋檐或硬地", "暂时不清楚")),
        "water": ("水声怎样变化？", ("持续稳定", "一阵一阵", "忽远忽近", "暂时不清楚")),
        "wind": ("声音和树叶摆动一致吗？", ("变化一致", "声音更早出现", "没有看清树叶", "暂时不清楚")),
    }.get(category, ("现场还有什么可以帮助判断？", ("方向比较明确", "节奏可以重复", "周围干扰较多", "暂时不清楚")))
    say, action, avoid = {
        "bird": ("“我们再听一次，节奏和刚才一样吗？”", "留在原地，比较树冠和灌木两个方向。", "不追逐、不爬树、不靠近巢穴。"),
        "frog": ("“声音是从水面还是草丛传来的？”", "站在安全岸边，比较近处和远处。", "不下水、不捕捉、不触碰动物。"),
        "insect": ("“我们数一数，它隔几秒重复一次？”", "安静听十秒，把重复规律记下来。", "不拨开草叶、不抓取昆虫。"),
        "water": ("“这段水声一直一样，还是会变强变弱？”", "保持安全距离，比较连续与间隔变化。", "不靠近湿滑岸边或进入水中。"),
    }.get(category, ("“我们先把听到的特点记下来，再决定下一步。”", "回听关键声段，并观察方向、节奏和环境。", "不追逐、不触碰，不把候选直接当成答案。"))
    choice_html = "".join(
        f'<button type="button" data-observation-value="{html.escape(choice)}" aria-pressed="false">{html.escape(choice)}</button>'
        for choice in choices
    )
    quality = "弱动态信号" if result.get("weak_signal") else "清晰声音"
    duration = float(result.get("duration", 0))
    return f'''<section class="investigation-followup" data-candidate="{html.escape(title)}" data-category="{html.escape(category)}" data-duration="{duration:.1f}" data-quality="{quality}">
      <div class="result-perspective-switch" role="group" aria-label="切换调查视角">
        <button type="button" data-result-view="child" aria-pressed="true">儿童视角</button>
        <button type="button" data-result-view="parent" aria-pressed="false">家长视角</button>
      </div>
      <div class="perspective-panel perspective-panel--child" data-result-panel="child">
        <h3>{html.escape(prompt)}</h3>
        <p>先根据现场真实情况选择，也可以保留“暂时不清楚”。</p>
        <div class="observation-choice-grid">{choice_html}</div>
      </div>
      <div class="perspective-panel perspective-panel--parent" data-result-panel="parent" hidden>
        <h3>陪孩子继续求证</h3>
        <dl>
          <div><dt>可以说</dt><dd>{html.escape(say)}</dd></div>
          <div><dt>一起做</dt><dd>{html.escape(action)}</dd></div>
          <div><dt>需要避免</dt><dd>{html.escape(avoid)}</dd></div>
        </dl>
        <p>这是基于候选类别的本地审核模板，没有调用云端生成服务。</p>
      </div>
      <article class="investigation-card-local">
        <div><span>本地调查卡</span><strong>{html.escape(title)}</strong><small>{quality} · 已分析 {duration:.1f} 秒</small></div>
        <p data-investigation-summary>完成一项现场观察后，可以下载本次记录。</p>
        <button type="button" data-download-investigation disabled>下载调查记录</button>
        <small data-investigation-status>记录只在当前浏览器生成，不会上传社区。</small>
      </article>
    </section>'''


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
        title = _display_detection_title(item)
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
        f'<div class="candidate-guide"><span>已分析 {float(result.get("duration", 0)):.1f} 秒 · 找到 {len(cards)} 条候选</span>'
        f'<strong class="quality-flag quality-flag--{html.escape(str(result.get("quality_state", "clear")))}">'
        f'{"弱动态信号" if result.get("weak_signal") else "清晰声音"}</strong>'
        '<p>弱线索先显示声音类别；具体物种仍需回听和现场核对。</p></div>'
        + "".join(cards)
        + "</section>"
        + _investigation_followup(detections[0], result)
    )
    progress(1, desc="生成现场观察任务")
    return (
        result_html,
        _status_panel("录音质检", result["quality"], tone="attention" if result.get("weak_signal") else "success"),
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
        <button type="button" class="mobile-experience-toggle" data-product-view="experience">全览</button>
        <button type="button" class="mobile-workbench-toggle" data-product-view="workbench">返回分析</button>
      </div>
      <nav class="workspace-nav" aria-label="产品与项目链接">
        <button type="button" class="product-view-link" data-product-view="workbench" aria-current="true">声音分析</button>
        <button type="button" class="product-view-link product-view-link--accent" data-product-view="experience" aria-current="false">完整体验</button>
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


def product_experience() -> str:
    asset = "/gradio_api/file=assets/ui"
    return f'''<main class="product-experience-shell" aria-labelledby="experience-title">
      <section class="experience-hero" id="experience-overview">
        <div class="experience-hero__copy">
          <h1 id="experience-title">一次声音调查，连接孩子、家长与整座城市。</h1>
          <p>魔搭负责可信的声音候选分析；Android 完整版把线索继续带进现场观察、家庭陪伴、共听地图、亲子游园和自然册。</p>
          <div class="experience-actions">
            <a class="experience-action experience-action--primary" href="{APK_URL}" target="_blank" rel="noopener noreferrer">下载 Android 0.4.0</a>
            <button class="experience-action" type="button" data-product-view="workbench">返回声音分析</button>
          </div>
          <dl class="release-ledger" aria-label="当前发布信息">
            <div><dt>版本</dt><dd>{VERSION}</dd></div>
            <div><dt>发布日期</dt><dd>{RELEASE_DATE}</dd></div>
            <div><dt>构建修订</dt><dd>{BUILD_REVISION}</dd></div>
          </dl>
        </div>
        <div class="experience-hero__visual" aria-label="自然声音探索路径">
          <img src="{asset}/hangzhou-mist.webp" alt="杭州湿润山林与湖岸的雾景" />
          <div class="field-note field-note--one"><span>01</span><strong>录下真实声音</strong><small>本地模型先给候选</small></div>
          <div class="field-note field-note--two"><span>02</span><strong>回到现场求证</strong><small>孩子保留判断权</small></div>
          <div class="field-note field-note--three"><span>03</span><strong>家庭共同完成</strong><small>只同步结构化事件</small></div>
        </div>
      </section>

      <nav class="tour-index" aria-label="完整体验章节">
        <button type="button" data-tour-target="#family-experience"><span>01</span>家庭陪伴</button>
        <button type="button" data-tour-target="#city-listening"><span>02</span>共听杭州</button>
        <button type="button" data-tour-target="#park-guide"><span>03</span>亲子游园</button>
        <button type="button" data-tour-target="#nature-book"><span>04</span>自然册</button>
        <button type="button" data-tour-target="#model-boundary"><span>05</span>模型边界</button>
      </nav>

      <section class="experience-section family-section" id="family-experience">
        <header class="section-heading">
          <div><h2>孩子探索，家长陪伴。</h2></div>
          <p>同一条调查记录提供两种视角。孩子先听、先描述；家长掌握安全与公开边界，不替孩子确认答案。</p>
        </header>
        <div class="family-layout">
          <div class="family-demo" data-active-role="child">
            <div class="role-switch" role="group" aria-label="切换家庭视角">
              <button type="button" data-family-role="child" aria-pressed="true">儿童探索</button>
              <button type="button" data-family-role="parent" aria-pressed="false">家长陪伴</button>
            </div>
            <article class="device-frame device-frame--child">
              <span class="device-label">孩子设备 · 已连接</span>
              <h3>去听一段有节奏的声音</h3>
              <div class="mission-progress"><i></i><i></i><i></i></div>
              <p>任务 2 / 3：站在原地听十秒，记下声音是否重复。</p>
              <button type="button">到这里开始聆听</button>
            </article>
            <article class="device-frame device-frame--parent">
              <span class="device-label">家长设备 · 连接码 482 617</span>
              <h3>陪孩子继续求证</h3>
              <dl class="parent-guidance-card">
                <div><dt>可以说</dt><dd>“我们再听一次，节奏和刚才一样吗？”</dd></div>
                <div><dt>一起做</dt><dd>留在步道上，比较远近两次声音。</dd></div>
                <div><dt>需要避免</dt><dd>不追逐、不拨开灌木、不靠近巢穴。</dd></div>
              </dl>
            </article>
          </div>
          <aside class="family-principles">
            <blockquote>孩子拥有判断权，家长拥有安全与公开边界权，AI 只拥有建议权。</blockquote>
            <ul>
              <li><span>只同步</span><strong>任务、步骤与完成反馈</strong></li>
              <li><span>不同步</span><strong>儿童身份、原始录音与精确位置</strong></li>
              <li><span>家长端</span><strong>依据真实行为生成过程性回应</strong></li>
            </ul>
          </aside>
        </div>
      </section>

      <section class="experience-section soundscape-section" id="city-listening">
        <header class="section-heading section-heading--compact">
          <div><h2>共听杭州，不公开精确位置。</h2></div>
          <p>地图只展示城区、公园和公开分区坐标；体验数据与真实观察分开标记。</p>
        </header>
        <div class="soundscape-layout">
          <div class="soundscape-map">
            <img src="{asset}/hangzhou-osm.png" loading="lazy" alt="杭州城区与试点公园的离线地图" />
            <button class="sound-marker sound-marker--one selected" type="button" data-sound-marker data-marker-title="西溪湿地 · 芦苇水岸" data-marker-detail="2 条真实观察 · 3 条体验示例" aria-label="查看西溪湿地声音线索"><i></i></button>
            <button class="sound-marker sound-marker--two" type="button" data-sound-marker data-marker-title="杭州植物园 · 林下步道" data-marker-detail="1 条真实观察 · 3 条体验示例" aria-label="查看杭州植物园声音线索"><i></i></button>
            <button class="sound-marker sound-marker--three" type="button" data-sound-marker data-marker-title="太子湾公园 · 水岸草地" data-marker-detail="近期数据不足 · 3 条体验示例" aria-label="查看太子湾公园声音线索"><i></i></button>
            <div class="map-selection-card"><span>当前分区</span><strong id="map-selection-title">西溪湿地 · 芦苇水岸</strong><small id="map-selection-detail">2 条真实观察 · 3 条体验示例</small></div>
            <div class="map-source-note"><i></i>公开分区 · 模糊坐标</div>
          </div>
          <div class="sound-feed" aria-label="社区声音示例">
            <article><div class="sound-feed__top"><span>真实观察</span><time>清晨 06:42</time></div><h3>芦苇深处的重复短鸣</h3><p>候选：鸟类鸣叫 · 等待其他探员协助</p><div class="mini-wave" aria-hidden="true"><i></i><i></i><i></i><i></i><i></i><i></i><i></i><i></i></div></article>
            <article class="sound-feed__demo"><div class="sound-feed__top"><span>体验示例</span><time>仅用于功能演示</time></div><h3>林下步道的雨后虫鸣</h3><p>不会提高真实生态数据充分度</p><div class="mini-wave" aria-hidden="true"><i></i><i></i><i></i><i></i><i></i><i></i><i></i><i></i></div></article>
            <div class="data-boundary"><strong>社区原则</strong><p>只有经成年人单独授权的匿名线索才能公开，并且可以撤回。</p></div>
          </div>
        </div>
      </section>

      <section class="experience-section park-section" id="park-guide">
        <header class="section-heading">
          <div><h2>先选择家庭条件，再推荐今天去哪听。</h2></div>
          <p>年龄、时间、声音兴趣、步行偏好和无障碍要求共同参与排序；数据不足时不制造“动物最多”等结论。</p>
        </header>
        <div class="park-journal">
          <div class="park-criteria">
            <article class="criterion-card"><img src="{asset}/park-guide/age-growth-strip.png" loading="lazy" alt="从幼儿到少年阶段的年龄选择插画" /><span>孩子年龄</span><div class="choice-row"><button type="button" data-choice-group="age" data-choice-value="young" aria-pressed="false">6–7 岁</button><button type="button" data-choice-group="age" data-choice-value="middle" aria-pressed="true">8–9 岁</button><button type="button" data-choice-group="age" data-choice-value="older" aria-pressed="false">10–11 岁</button></div></article>
            <article class="criterion-card"><img src="{asset}/park-guide/time-nature-strip.png" loading="lazy" alt="家庭在自然步道安排游园时间的插画" /><span>可用时间</span><div class="choice-row"><button type="button" data-choice-group="time" data-choice-value="short" aria-pressed="true">约 1 小时</button><button type="button" data-choice-group="time" data-choice-value="long" aria-pressed="false">约 2 小时</button></div></article>
            <article class="criterion-card"><img src="{asset}/park-guide/interest-nature-strip.png" loading="lazy" alt="鸟鸣、蛙虫与流水等声音兴趣插画" /><span>想听什么</span><div class="choice-row"><button type="button" data-choice-group="sound" data-choice-value="bird" aria-pressed="true">鸟鸣</button><button type="button" data-choice-group="sound" data-choice-value="frog" aria-pressed="false">蛙虫</button><button type="button" data-choice-group="sound" data-choice-value="water" aria-pressed="false">流水风雨</button></div></article>
            <article class="criterion-card"><img src="{asset}/park-guide/walk-routes-strip.png" loading="lazy" alt="轻松步行与完整路线偏好的插画" /><span>怎样走</span><div class="choice-row"><button type="button" data-choice-group="walk" data-choice-value="easy" aria-pressed="false">轻松步行</button><button type="button" data-choice-group="walk" data-choice-value="full" aria-pressed="true">完整路线</button></div></article>
          </div>
          <div class="park-results">
            <div class="park-results__hero"><img id="park-result-image" src="{asset}/park-guide/park-botanical.webp" loading="lazy" alt="根据当前家庭条件推荐的亲子声音路线" /><span>根据当前条件</span><h3 id="park-result-title">杭州植物园更适合这次探索</h3><p id="park-result-reason">林下步道集中、移动距离较短，适合在有限时间里比较不同方向的鸟鸣。</p></div>
            <div class="park-cards">
              <article data-park-card="wetland"><img src="{asset}/park-guide/park-wetland.webp" loading="lazy" alt="西溪湿地亲子声音路线" /><div><span>水岸与蛙虫</span><strong>西溪湿地</strong><small>水岸 · 芦苇 · 林下</small></div></article>
              <article class="selected" data-park-card="botanical"><img src="{asset}/park-guide/park-botanical.webp" loading="lazy" alt="杭州植物园亲子声音路线" /><div><span>当前推荐</span><strong>杭州植物园</strong><small>林下 · 缓坡 · 鸟鸣</small></div></article>
              <article data-park-card="taiziwan"><img src="{asset}/park-guide/park-taiziwan.webp" loading="lazy" alt="太子湾公园亲子声音路线" /><div><span>轻松步行</span><strong>太子湾公园</strong><small>草地 · 水岸 · 轻松步行</small></div></article>
            </div>
          </div>
        </div>
      </section>

      <section class="experience-section book-section" id="nature-book">
        <header class="section-heading section-heading--compact">
          <div><h2>把候选、原声和观察留在自然册。</h2></div>
          <p>声音册默认保存在当前设备；公开、研究贡献与生成作品都有独立选择。</p>
        </header>
        <div class="book-layout">
          <article class="sound-fingerprint">
            <div class="fingerprint-heading"><span>声音指纹 · 2026.08.27</span><strong>雨后林下的短促鸣叫</strong></div>
            <div class="fingerprint-wave" aria-hidden="true"><i></i><i></i><i></i><i></i><i></i><i></i><i></i><i></i><i></i><i></i><i></i><i></i></div>
            <dl><div><dt>候选</dt><dd>鸟类鸣叫</dd></div><div><dt>现场观察</dt><dd>树冠方向 · 节奏重复</dd></div><div><dt>地点</dt><dd>杭州 · 模糊记录</dd></div></dl>
            <p>候选不是确认。下次可以在相同时段再次回听。</p>
          </article>
          <div class="book-story">
            <h3>你听到的节奏，是连续的，还是每隔几秒出现一次？</h3>
            <div class="observation-options"><button type="button">连续出现</button><button type="button">间隔重复</button><button type="button">暂时不知道</button></div>
            <details><summary>家长查看判断依据</summary><p>模型来源、关键声段、不确定性和安全边界会在这里展开；家长不替孩子作答。</p></details>
          </div>
          <aside class="creation-preview"><span>AI 共创 · 可选</span><h3>自然声音短片</h3><p>把已经保存的线索制作成配乐、科普旁白和竖屏短片。生成失败不会影响原始调查记录。</p><div class="creation-track"><i></i><div><strong>原声仍然是主角</strong><small>旁白和音乐单独下载</small></div></div><a href="{WEB_URL}" target="_blank" rel="noopener noreferrer">打开完整 Web 产品</a></aside>
        </div>
      </section>

      <section class="experience-section model-section" id="model-boundary">
        <header class="section-heading">
          <div><h2>三个本地模型，职责彼此分开。</h2></div>
          <p>分数只用于本次候选排序，不代表物种正确概率。混合、嘈杂或远距离声音允许没有可靠结果。</p>
        </header>
        <div class="model-ledger">
          <article><span>通用声景</span><h3>YAMNet</h3><p>先判断鸟鸣、蛙鸣、虫鸣、风雨、流水和交通等声音大类。</p><small>Apache-2.0 · 16 kHz</small></article>
          <article><span>鸟类候选</span><h3>BirdNET 2.4</h3><p>使用杭州全年地理先验，从 200 种本地鸟类目录中寻找候选。</p><small>CC-BY-NC-4.0 · 非商业展示</small></article>
          <article><span>本地类群</span><h3>Non-bird 0.1</h3><p>复用 BirdNET embedding，补充杭州蛙类与鸣虫的实验线索。</p><small>高阈值 · 背景与相似度拒绝</small></article>
        </div>
        <div class="boundary-ledger"><strong>当前明确不承诺</strong><p>不提供盲源分离、目标声源提取或专用 AI 降噪；不把一次录音写成物种定论；不自动公开录音或加入训练集。</p><div><a href="{GITHUB_URL}" target="_blank" rel="noopener noreferrer">查看开源代码</a><button type="button" data-product-view="workbench">现在分析一段声音</button></div></div>
      </section>
    </main>'''


with gr.Blocks(title="自然声探员 · 共听杭州") as demo:
    gr.HTML(workspace_header())
    with gr.Row(equal_height=True, elem_id="investigation"):
        with gr.Column(scale=4, min_width=600, elem_id="audio-input-panel", elem_classes="workspace-panel input-panel"):
            gr.HTML('''<section class="instrument-heading"><div><h1>录下一段自然声音</h1></div><p>靠近目标声音，避开说话声和车辆。</p></section>''')
            audio = gr.Audio(sources=["microphone", "upload"], type="filepath", label="真实原声", elem_id="source-audio", buttons=["download"])
            gr.HTML('''<button id="drop-audio-surface" type="button"><strong>拖入一段音频，或点击选择文件</strong><small>WAV / MP3 / M4A / FLAC / OGG · 最大 15 MB</small></button>''')
            gr.HTML('''<div class="upload-notes"><span>建议 5–20 秒</span><span>最长分析前 20 秒</span><span>录音不会自动公开</span></div>''')
            gr.HTML('''<div class="example-audio-row"><button type="button" data-example-audio="/gradio_api/file=assets/ui/examples/flowing-water-public-domain.ogg">试用公共领域流水示例</button><span>来源：Wikimedia Commons · Public domain</span></div>''')
            submit = gr.Button("分析这段声音", variant="primary", elem_id="analyze-button", interactive=False)
            quality = gr.HTML(_status_panel("录音准备", "录制或上传后，会先检查格式、大小和时长。"), elem_id="quality-status")
            gr.HTML('''<section class="field-context" aria-label="录音现场信息">
              <div><span>录音建议</span><strong>安静时段 · 远离人声与车辆</strong></div>
              <div><span>位置（可选）</span><strong>杭州</strong></div>
              <div><span>环境（可选）</span><strong>安静 · 微风</strong></div>
            </section>''')
            gr.HTML('''<p class="privacy-note">请避开姓名和对话；录音不会自动公开或进入训练集。</p>''')
        with gr.Column(scale=1, min_width=285, elem_id="analysis-result-panel", elem_classes="workspace-panel result-panel"):
            gr.HTML('''<section class="panel-heading panel-heading--result"><div><h2>观测册</h2><p>候选，不是答案</p></div></section>''')
            result_html = gr.HTML(_empty_result("等待一段真实自然声"), elem_id="result-content")
            gr.HTML('''<ol class="rail-process" aria-label="调查流程">
              <li><span>01</span><div><strong>录下一段自然声音</strong><small>点击开始聆听，或拖入已有音频。</small></div></li>
              <li><span>02</span><div><strong>模型分析，提供候选</strong><small>线索只用于调查，不替代你的判断。</small></div></li>
              <li><span>03</span><div><strong>回听与现场观察</strong><small>结合现场环境，确认真实来源。</small></div></li>
            </ol>''')
            observation = gr.HTML(_status_panel("现场观察", "分析后，这里会给出一项可以立刻执行的观察任务。"), elem_id="observation-task")
            reset = gr.Button("清空结果，换一段声音", variant="secondary", elem_id="reset-investigation")
    gr.HTML(product_experience(), elem_id="product-experience")
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
