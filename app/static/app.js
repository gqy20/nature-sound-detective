const $ = (id) => document.getElementById(id);
const reducedMotion = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
const MAX_ANALYSIS_SECONDS = 20;
const MAX_UPLOAD_BYTES = 15 * 1024 * 1024;
const SOFT_WAIT_SECONDS = 60;
const HARD_WAIT_SECONDS = 90;
const COLLECTION_KEY = "nature-sound-detective:collection-v1";
const LOCAL_FEEDBACK_KEY = "nature-sound-detective:feedback-v1";
const MAX_COLLECTION_ITEMS = 12;
const API_BASE = String(window.NATURE_API_BASE || "").replace(/\/$/, "");
const apiUrl = (path) => `${API_BASE}${path}`;
const nativeFetch = window.fetch.bind(window);
let activeTraceId = "web_boot";

function newTraceId() {
  const value = crypto.randomUUID?.().replaceAll("-", "") || `${Date.now()}_${Math.random().toString(16).slice(2)}`;
  return `web_${value}`;
}

function webLog(level, event, fields = {}) {
  const safe = Object.fromEntries(Object.entries(fields).filter(([key]) => !/(token|authorization|audio_data|audio_path|prompt|response_body)/i.test(key)));
  const entry = { timestamp: new Date().toISOString(), level, component: "web", event, trace_id: activeTraceId, ...safe };
  (console[level] || console.log)(JSON.stringify(entry));
}

function tracedFetch(input, init = {}) {
  const headers = new Headers(init.headers || {});
  headers.set("X-Trace-ID", activeTraceId);
  return nativeFetch(input, { ...init, headers });
}

window.addEventListener("error", (event) => webLog("error", "uncaught_error", {
  error_type: event.error?.name || "Error", line: event.lineno, column: event.colno,
}));
window.addEventListener("unhandledrejection", (event) => webLog("error", "unhandled_rejection", {
  error_type: event.reason?.name || "Error",
}));

const stages = {
  queued: [18, "正在准备录音"],
  analyzing: [48, "正在寻找声音线索"],
  enriching: [72, "正在核对自然知识"],
  composing: [88, "正在生成声音卡"],
};

const categoryColors = {
  "鸟类鸣叫": "#28734a",
  "蛙类鸣叫": "#14766f",
  "昆虫鸣叫": "#b66a22",
  "雨水": "#367a9a",
  "流水": "#367a9a",
  "风和树叶": "#647b48",
};

let selectedBlob = null;
let selectedName = "户外录音.webm";
let mediaRecorder = null;
let mediaStream = null;
let chunks = [];
let timerHandle = null;
let elapsed = 0;
let previewUrl = null;
let audioContext = null;
let analyser = null;
let microphoneSource = null;
let visualFrame = null;
let idleFrame = null;
let fingerprintReady = false;
let selectedDuration = 0;
let activeRunId = 0;
let analysisAbortController = null;
let selectedAudioValid = false;
let currentJob = null;
let creationPollToken = 0;

function showPanel(id) {
  const captureFlow = id === "capture-panel" || id === "ready-panel";
  $("intro").hidden = !captureFlow;
  $("capture-panel").hidden = id !== "capture-panel";
  $("ready-panel").hidden = id !== "ready-panel";
  $("progress-panel").hidden = id !== "progress-panel";
  $("result-panel").hidden = id !== "result-panel";
  $("collection-panel").hidden = id !== "collection-panel";
  $("error-panel").hidden = id !== "error-panel";
}

function resetCapture() {
  activeRunId += 1;
  analysisAbortController?.abort();
  analysisAbortController = null;
  selectedBlob = null;
  selectedName = "户外录音.webm";
  selectedDuration = 0;
  selectedAudioValid = false;
  currentJob = null;
  creationPollToken += 1;
  fingerprintReady = false;
  if (previewUrl) URL.revokeObjectURL(previewUrl);
  previewUrl = null;
  $("file-input").value = "";
  $("preview").removeAttribute("src");
  $("preview").load();
  $("result-audio").pause();
  $("result-audio").removeAttribute("src");
  $("play-card-button").textContent = "播放录音";
  document.querySelector(".parent-details").open = false;
  $("clip-notice").textContent = "";
  $("quality-notice").textContent = "";
  $("quality-notice").classList.remove("is-warning");
  $("analyze-button").disabled = false;
  $("save-status").textContent = "";
  $("progress-help").textContent = "通常需要 20–60 秒";
  $("partial-clues").hidden = true;
  $("partial-clue-list").replaceChildren();
  $("record-label").textContent = "开始录音";
  $("timer").textContent = "20秒以内";
  $("record-button").classList.remove("recording");
  $("capture-visual").classList.remove("recording");
  $("capture-visual").style.setProperty("--record-progress", "0deg");
  showPanel("capture-panel");
  refreshHistoryButton();
  startIdleVisual();
}

function formatDuration(seconds) {
  if (!Number.isFinite(seconds)) return "";
  const whole = Math.max(0, Math.round(seconds));
  return `${Math.floor(whole / 60)}:${String(whole % 60).padStart(2, "0")}`;
}

function readAudioDuration(audio) {
  if (Number.isFinite(audio.duration)) return Promise.resolve(audio.duration);
  return new Promise((resolve) => {
    const done = () => resolve(Number.isFinite(audio.duration) ? audio.duration : 0);
    audio.addEventListener("loadedmetadata", done, { once: true });
    audio.addEventListener("error", () => resolve(0), { once: true });
    setTimeout(() => resolve(0), 2500);
  });
}

async function setReady(blob, name) {
  selectedBlob = blob;
  selectedName = name;
  if (previewUrl) URL.revokeObjectURL(previewUrl);
  previewUrl = URL.createObjectURL(blob);
  $("preview").src = previewUrl;
  $("preview").load();
  $("file-name").textContent = name.startsWith("自然录音") ? name : "已有录音";
  $("file-name").title = name;
  showPanel("ready-panel");
  selectedDuration = await readAudioDuration($("preview"));
  const durationLabel = formatDuration(selectedDuration);
  const isLong = selectedDuration > MAX_ANALYSIS_SECONDS + .25;
  $("clip-notice").classList.toggle("is-warning", isLong);
  $("clip-notice").textContent = isLong
    ? `录音长 ${durationLabel}，本次只分析前 20 秒。`
    : durationLabel ? `将分析完整录音 · ${durationLabel}` : "本次最多分析前 20 秒。";
  try {
    const samples = await decodeBlob(blob);
    drawLinearWave($("ready-wave"), samplePeaks(samples, 110), "#28734a", "#dcecdf");
    const quality = assessAudioQuality(samples);
    selectedAudioValid = true;
    $("quality-notice").classList.toggle("is-warning", quality.level !== "good");
    $("quality-notice").textContent = quality.message;
    $("analyze-button").disabled = false;
  } catch (_) {
    selectedAudioValid = false;
    const fallback = Array.from({ length: 110 }, (_, index) => .18 + Math.abs(Math.sin(index * .31)) * .55);
    drawLinearWave($("ready-wave"), fallback, "#28734a", "#dcecdf");
    $("quality-notice").classList.add("is-warning");
    $("quality-notice").textContent = "无法读取这段录音，请重新选择音频文件。";
    $("analyze-button").disabled = true;
  }
}

function assessAudioQuality(samples) {
  if (!samples.length) return { level: "poor", message: "没有检测到声音，请重新录制。" };
  const stride = Math.max(1, Math.floor(samples.length / 24000));
  let sumSquares = 0;
  let silent = 0;
  let clipped = 0;
  let count = 0;
  for (let index = 0; index < samples.length; index += stride) {
    const value = Math.abs(samples[index] || 0);
    sumSquares += value * value;
    if (value < .008) silent += 1;
    if (value > .985) clipped += 1;
    count += 1;
  }
  const rms = Math.sqrt(sumSquares / Math.max(count, 1));
  const silentRatio = silent / Math.max(count, 1);
  const clippedRatio = clipped / Math.max(count, 1);
  if (rms < .012 || silentRatio > .82) return { level: "warning", message: "声音偏小或静音较多，靠近目标声音再录一次会更容易识别。" };
  if (clippedRatio > .025) return { level: "warning", message: "声音有些过强，离声源远一点可以减少失真。" };
  return { level: "good", message: "录音质量适合识别。" };
}

function recorderMimeType() {
  const options = ["audio/webm;codecs=opus", "audio/mp4", "audio/ogg;codecs=opus"];
  return options.find((type) => window.MediaRecorder && MediaRecorder.isTypeSupported(type)) || "";
}

function canvasContext(canvas) {
  return canvas.getContext("2d");
}

function drawRadialBars(canvas, values, color = "#28734a") {
  const ctx = canvasContext(canvas);
  const { width, height } = canvas;
  const cx = width / 2;
  const cy = height / 2;
  const base = width * .285;
  ctx.clearRect(0, 0, width, height);
  ctx.save();
  ctx.translate(cx, cy);
  ctx.strokeStyle = color;
  ctx.lineWidth = 4;
  ctx.lineCap = "round";
  const count = 56;
  for (let index = 0; index < count; index += 1) {
    const value = values[index % values.length] / 255;
    const angle = (Math.PI * 2 * index) / count - Math.PI / 2;
    const inner = base;
    const outer = base + 8 + value * 35;
    ctx.beginPath();
    ctx.moveTo(Math.cos(angle) * inner, Math.sin(angle) * inner);
    ctx.lineTo(Math.cos(angle) * outer, Math.sin(angle) * outer);
    ctx.stroke();
  }
  ctx.restore();
}

function startIdleVisual() {
  cancelAnimationFrame(idleFrame);
  const canvas = $("live-wave");
  const render = (time = 0) => {
    const values = Array.from({ length: 56 }, (_, index) => 32 + 26 * (1 + Math.sin(index * .55 + time / 680)));
    drawRadialBars(canvas, values, "#4e8e67");
    if (!reducedMotion && (!mediaRecorder || mediaRecorder.state !== "recording")) idleFrame = requestAnimationFrame(render);
  };
  render();
}

function startMicrophoneVisual(stream) {
  cancelAnimationFrame(idleFrame);
  audioContext = new (window.AudioContext || window.webkitAudioContext)();
  analyser = audioContext.createAnalyser();
  analyser.fftSize = 256;
  analyser.smoothingTimeConstant = .78;
  microphoneSource = audioContext.createMediaStreamSource(stream);
  microphoneSource.connect(analyser);
  const values = new Uint8Array(analyser.frequencyBinCount);
  const render = () => {
    analyser.getByteFrequencyData(values);
    drawRadialBars($("live-wave"), values, "#28734a");
    visualFrame = requestAnimationFrame(render);
  };
  render();
}

async function stopMicrophoneVisual() {
  cancelAnimationFrame(visualFrame);
  microphoneSource?.disconnect();
  if (audioContext && audioContext.state !== "closed") await audioContext.close();
  audioContext = null;
  analyser = null;
  microphoneSource = null;
}

async function toggleRecording() {
  if (mediaRecorder && mediaRecorder.state === "recording") {
    mediaRecorder.stop();
    return;
  }
  if (!navigator.mediaDevices?.getUserMedia || !window.MediaRecorder) {
    return showError("当前浏览器不能直接录音", "请使用“选择已有录音”，上传手机录音机保存的文件。", "capture", "选择已有录音");
  }
  try {
    mediaStream = await navigator.mediaDevices.getUserMedia({ audio: true });
    const mimeType = recorderMimeType();
    mediaRecorder = new MediaRecorder(mediaStream, mimeType ? { mimeType } : undefined);
    chunks = [];
    elapsed = 0;
    $("record-button").classList.add("recording");
    $("capture-visual").classList.add("recording");
    $("record-label").textContent = "结束录音";
    $("timer").textContent = "00:00 / 00:20";
    startMicrophoneVisual(mediaStream);
    mediaRecorder.ondataavailable = (event) => { if (event.data.size) chunks.push(event.data); };
    mediaRecorder.onstop = async () => {
      clearInterval(timerHandle);
      mediaStream?.getTracks().forEach((track) => track.stop());
      await stopMicrophoneVisual();
      $("record-button").classList.remove("recording");
      $("capture-visual").classList.remove("recording");
      $("record-label").textContent = "开始录音";
      const type = mediaRecorder.mimeType || "audio/webm";
      const extension = type.includes("mp4") ? "m4a" : type.includes("ogg") ? "ogg" : "webm";
      await setReady(new Blob(chunks, { type }), `自然录音.${extension}`);
    };
    mediaRecorder.start(500);
    timerHandle = setInterval(() => {
      elapsed += 1;
      $("timer").textContent = `00:${String(elapsed).padStart(2, "0")} / 00:20`;
      $("capture-visual").style.setProperty("--record-progress", `${Math.min(elapsed / 20, 1) * 360}deg`);
      if (elapsed >= 20 && mediaRecorder.state === "recording") mediaRecorder.stop();
    }, 1000);
  } catch (error) {
    await stopMicrophoneVisual();
    showError("没有获得麦克风权限", "请允许浏览器使用麦克风，或改为上传已有录音。", "capture", "返回录音");
  }
}

async function decodeBlob(blob) {
  const context = new (window.AudioContext || window.webkitAudioContext)();
  try {
    const buffer = await context.decodeAudioData((await blob.arrayBuffer()).slice(0));
    return buffer.getChannelData(0);
  } finally {
    await context.close();
  }
}

async function toAnalysisWav(blob) {
  const context = new (window.AudioContext || window.webkitAudioContext)();
  try {
    const buffer = await context.decodeAudioData((await blob.arrayBuffer()).slice(0));
    const sampleRate = 16000;
    const frameCount = Math.min(
      Math.floor(MAX_ANALYSIS_SECONDS * sampleRate),
      Math.floor(buffer.duration * sampleRate),
    );
    const pcm = new Int16Array(frameCount);
    for (let frame = 0; frame < frameCount; frame += 1) {
      const sourcePosition = frame * buffer.sampleRate / sampleRate;
      const left = Math.floor(sourcePosition);
      const right = Math.min(left + 1, buffer.length - 1);
      const fraction = sourcePosition - left;
      let sample = 0;
      for (let channel = 0; channel < buffer.numberOfChannels; channel += 1) {
        const values = buffer.getChannelData(channel);
        sample += values[left] * (1 - fraction) + values[right] * fraction;
      }
      sample = Math.max(-1, Math.min(1, sample / buffer.numberOfChannels));
      pcm[frame] = sample < 0 ? sample * 32768 : sample * 32767;
    }
    const wav = new ArrayBuffer(44 + pcm.byteLength);
    const view = new DataView(wav);
    const text = (offset, value) => [...value].forEach((char, index) => view.setUint8(offset + index, char.charCodeAt(0)));
    text(0, "RIFF"); view.setUint32(4, 36 + pcm.byteLength, true); text(8, "WAVE");
    text(12, "fmt "); view.setUint32(16, 16, true); view.setUint16(20, 1, true);
    view.setUint16(22, 1, true); view.setUint32(24, sampleRate, true);
    view.setUint32(28, sampleRate * 2, true); view.setUint16(32, 2, true); view.setUint16(34, 16, true);
    text(36, "data"); view.setUint32(40, pcm.byteLength, true);
    new Int16Array(wav, 44).set(pcm);
    return new Blob([wav], { type: "audio/wav" });
  } finally {
    await context.close();
  }
}

function samplePeaks(samples, count) {
  const step = Math.max(1, Math.floor(samples.length / count));
  const peaks = [];
  for (let index = 0; index < count; index += 1) {
    let peak = 0;
    const start = index * step;
    for (let cursor = start; cursor < Math.min(start + step, samples.length); cursor += Math.max(1, Math.floor(step / 40))) {
      peak = Math.max(peak, Math.abs(samples[cursor] || 0));
    }
    peaks.push(peak);
  }
  const max = Math.max(...peaks, .001);
  return peaks.map((peak) => peak / max);
}

function drawLinearWave(canvas, peaks, color, background) {
  const ctx = canvasContext(canvas);
  ctx.fillStyle = background;
  ctx.fillRect(0, 0, canvas.width, canvas.height);
  const center = canvas.height / 2;
  const gap = canvas.width / peaks.length;
  ctx.strokeStyle = color;
  ctx.lineWidth = Math.max(2, gap * .42);
  ctx.lineCap = "round";
  peaks.forEach((peak, index) => {
    const height = 8 + peak * canvas.height * .72;
    const x = (index + .5) * gap;
    ctx.beginPath();
    ctx.moveTo(x, center - height / 2);
    ctx.lineTo(x, center + height / 2);
    ctx.stroke();
  });
}

async function drawBlobWaveform(blob, canvas, color, background) {
  try {
    const samples = await decodeBlob(blob);
    const peaks = samplePeaks(samples, 110);
    drawLinearWave(canvas, peaks, color, background);
    return peaks;
  } catch (_) {
    const fallback = Array.from({ length: 110 }, (_, index) => .18 + Math.abs(Math.sin(index * .31)) * .55);
    drawLinearWave(canvas, fallback, color, background);
    return fallback;
  }
}

function showError(title, message, mode = "ready", buttonText = "返回录音") {
  $("error-title").textContent = title;
  $("error-message").textContent = message;
  $("error-retry").dataset.mode = mode;
  $("error-retry").textContent = buttonText;
  showPanel("error-panel");
  $("error-title").focus({ preventScroll: true });
}

async function startAnalysis() {
  if (!selectedBlob || !selectedAudioValid) return;
  const runId = ++activeRunId;
  activeTraceId = newTraceId();
  analysisAbortController = new AbortController();
  const startedAt = Date.now();
  const form = new FormData();
  const analysisBlob = await toAnalysisWav(selectedBlob);
  webLog("info", "analysis_started", { upload_bytes: analysisBlob.size });
  form.append("audio", analysisBlob, "nature-analysis.wav");
  form.append("location", $("location").value.trim() || "杭州");
  updateStage("queued");
  $("progress-help").textContent = "通常需要 20–60 秒";
  showPanel("progress-panel");
  await drawBlobWaveform(selectedBlob, $("progress-wave"), "#28734a", "#edf4ee");
  try {
    const response = await tracedFetch(apiUrl("/api/analyze"), {
      method: "POST",
      body: form,
      signal: analysisAbortController.signal,
    });
    activeTraceId = response.headers.get("X-Trace-ID") || activeTraceId;
    if (runId !== activeRunId) return;
    if (!response.ok) {
      const submissionError = new Error(await response.text());
      submissionError.status = response.status;
      throw submissionError;
    }
    const job = await response.json();
    webLog("info", "analysis_accepted", { status_code: response.status, job_id: job.id || "synchronous" });
    if (job.status === "completed") await renderResult(job);
    else await pollJob(job.id, runId, startedAt);
  } catch (error) {
    if (error?.name === "AbortError" || runId !== activeRunId) return;
    webLog("error", "analysis_failed", { error_type: error?.name || "Error", status_code: error?.status || 0 });
    showAnalysisError(error);
  } finally {
    if (runId === activeRunId) analysisAbortController = null;
  }
}

function showAnalysisError(error) {
  const message = readableError(error);
  if ([413, 415, 422].includes(error?.status)) {
    showError("这段录音还不能分析", message, "capture", "重新选择录音");
    return;
  }
  if (/90 秒|等待/.test(message)) {
    showError("等待时间有点久", `${message} 录音仍保留在当前页面。`, "ready", "返回录音");
    return;
  }
  showError("网络连接没有完成", `${message} 录音仍保留，可以再次提交。`, "ready", "再次提交");
}

function updateStage(status, message) {
  const [percent, fallback] = stages[status] || stages.queued;
  $("stage-message").textContent = message || fallback;
  $("stage-fill").style.width = `${percent}%`;
}

function renderPartialClues(partial) {
  const birdNames = (partial?.bird_species || []).map((item) => item.name_zh).filter(Boolean);
  const nonbirdNames = (partial?.nonbird_species || []).map((item) => item.name_zh).filter(Boolean);
  const names = [...new Set([...birdNames, ...nonbirdNames])].slice(0, 5);
  const container = $("partial-clue-list");
  container.replaceChildren();
  for (const name of names) {
    const clue = document.createElement("span");
    clue.className = "partial-clue";
    clue.textContent = name;
    container.append(clue);
  }
  $("partial-clues").hidden = names.length === 0;
  if (partial?.total_windows) {
    const ratio = Math.min(1, partial.processed_windows / partial.total_windows);
    $("stage-fill").style.width = `${Math.round(30 + ratio * 35)}%`;
  }
}

async function pollJob(jobId, runId, startedAt) {
  while (true) {
    await new Promise((resolve) => setTimeout(resolve, 1400));
    if (runId !== activeRunId) return;
    const elapsedSeconds = (Date.now() - startedAt) / 1000;
    if (elapsedSeconds >= HARD_WAIT_SECONDS) {
      throw new Error("等待超过 90 秒。请稍后重试，录音仍保留在当前页面。 ");
    }
    if (elapsedSeconds >= SOFT_WAIT_SECONDS) {
      $("progress-help").textContent = "比平时久一些，你可以继续等待或取消后重试。";
    }
    const response = await tracedFetch(apiUrl(`/api/jobs/${jobId}`));
    if (!response.ok) throw new Error(await response.text());
    const job = await response.json();
    if (job.status === "failed") {
      showError("这次没有听清", job.error || "请换一段更清晰的录音后重试。", "ready", "返回录音");
      return;
    }
    if (job.status === "completed") {
      webLog("info", "analysis_completed", { job_id: job.id, duration_ms: Date.now() - startedAt });
      await renderResult(job);
      return;
    }
    updateStage(job.status, job.stage_message);
    renderPartialClues(job.partial_result);
  }
}

function wrapCanvasText(ctx, text, x, y, maxWidth, lineHeight, maxLines = 3) {
  const chars = [...text];
  let line = "";
  let lineIndex = 0;
  for (const char of chars) {
    const test = line + char;
    if (ctx.measureText(test).width > maxWidth && line) {
      ctx.fillText(line, x, y + lineIndex * lineHeight);
      line = char;
      lineIndex += 1;
      if (lineIndex >= maxLines - 1) break;
    } else {
      line = test;
    }
  }
  if (lineIndex < maxLines) ctx.fillText(line, x, y + lineIndex * lineHeight);
}

function drawFingerprint(result, peaks, location) {
  const canvas = $("fingerprint-canvas");
  const ctx = canvasContext(canvas);
  const primary = categoryColors[result.sound_types[0]] || "#28734a";
  ctx.fillStyle = "#f3f6f1";
  ctx.fillRect(0, 0, canvas.width, canvas.height);
  ctx.fillStyle = primary;
  ctx.fillRect(0, 0, canvas.width, 16);

  ctx.fillStyle = "#153226";
  ctx.font = '700 29px "Microsoft YaHei UI", "Microsoft YaHei", sans-serif';
  ctx.fillText("自然声探员", 62, 82);
  ctx.fillStyle = "#66786e";
  ctx.font = '22px "Microsoft YaHei UI", "Microsoft YaHei", sans-serif';
  ctx.textAlign = "right";
  ctx.fillText(`${location} · ${new Date().toLocaleDateString("zh-CN")}`, 838, 82);
  ctx.textAlign = "left";

  const cx = 450;
  const cy = 405;
  ctx.save();
  ctx.translate(cx, cy);
  ctx.strokeStyle = primary;
  ctx.lineCap = "round";
  peaks.slice(0, 96).forEach((peak, index) => {
    const angle = (Math.PI * 2 * index) / 96 - Math.PI / 2;
    const inner = 138;
    const outer = 160 + peak * 100;
    ctx.globalAlpha = .45 + peak * .55;
    ctx.lineWidth = 5;
    ctx.beginPath();
    ctx.moveTo(Math.cos(angle) * inner, Math.sin(angle) * inner);
    ctx.lineTo(Math.cos(angle) * outer, Math.sin(angle) * outer);
    ctx.stroke();
  });
  ctx.globalAlpha = 1;
  ctx.fillStyle = "#ffffff";
  ctx.beginPath();
  ctx.arc(0, 0, 118, 0, Math.PI * 2);
  ctx.fill();
  ctx.restore();

  ctx.textAlign = "left";
  ctx.fillStyle = "#153226";
  ctx.font = '700 57px "Microsoft YaHei UI", "Microsoft YaHei", sans-serif';
  wrapCanvasText(ctx, result.card.title, 62, 730, 776, 67, 2);
  ctx.fillStyle = primary;
  ctx.font = '700 25px "Microsoft YaHei UI", "Microsoft YaHei", sans-serif';
  ctx.fillText(result.sound_types.join("、"), 62, 860);
  ctx.strokeStyle = "#cdd9d0";
  ctx.beginPath();
  ctx.moveTo(62, 910);
  ctx.lineTo(838, 910);
  ctx.stroke();
  ctx.fillStyle = "#66786e";
  ctx.font = '19px "Microsoft YaHei UI", "Microsoft YaHei", sans-serif';
  ctx.fillText("AI识别，仅供观察参考", 62, 958);
  fingerprintReady = true;
}

async function renderResult(job, { persist = true } = {}) {
  const result = job.result;
  currentJob = job;
  document.querySelector(".parent-details").open = false;
  $("feedback-block").hidden = Boolean(job.is_demo || job.capabilities?.feedback === false);
  $("feedback-status").textContent = "";
  $("correction-panel").hidden = true;
  $("feedback-yes").disabled = false;
  $("feedback-no").disabled = false;
  $("save-status").textContent = "";
  $("result-title").textContent = result.card.title;
  $("confidence").textContent = ({ demo: "示例结果", high: "AI 线索：较清晰", medium: "AI 猜测：较可能", low: "AI 猜测：待确认" })[result.confidence_level] || "AI 参考结果";
  $("sound-tags").replaceChildren(...result.sound_types.map((name) => {
    const tag = document.createElement("span");
    tag.className = "sound-tag";
    tag.textContent = name;
    return tag;
  }));
  $("result-audio").pause();
  $("result-audio").removeAttribute("src");
  $("result-audio").load();
  $("play-card-button").textContent = "播放录音";
  $("play-card-button").hidden = !job.audio_url;
  document.querySelector(".card-actions").classList.toggle("single-action", !job.audio_url);
  if (job.audio_url) $("result-audio").src = job.audio_url;
  else $("result-audio").removeAttribute("src");
  $("child-explanation").textContent = result.card.explanation;
  $("observation-question").textContent = result.card.question;
  $("safety-note").textContent = result.card.safety_note;
  $("uncertainty").textContent = result.uncertainty ? `还不能确认：${result.uncertainty}` : "";
  const possibleSounds = result.possible_sound_types || [];
  $("possible-sounds").hidden = possibleSounds.length === 0;
  $("possible-sounds").textContent = possibleSounds.length
    ? `可能还听到：${possibleSounds.join("、")}。这些线索不会写入儿童故事。`
    : "";
  $("evidence-list").replaceChildren(...result.evidence.map((text) => {
    const item = document.createElement("li");
    item.textContent = text;
    return item;
  }));
  const birds = result.bird_species || [];
  $("scope-note").textContent = job.capabilities?.birdnet === false
    ? "云端展示版可判断自然声音大类；具体鸟种候选请使用本地完整版。"
    : "当前可判断自然声音大类；鸟类会补充杭州常见候选种，蛙类和昆虫暂不保证识别到具体物种。";
  $("bird-result").hidden = birds.length === 0;
  $("bird-list").replaceChildren(...birds.map((bird) => {
    const row = document.createElement("div");
    row.className = "bird-item";
    const name = document.createElement("span");
    name.textContent = bird.name_zh;
    const confidence = document.createElement("span");
    confidence.textContent = `${Math.round(bird.confidence * 100)}%`;
    row.append(name, confidence);
    return row;
  }));
  renderCreation(job);

  let peaks;
  try {
    if (!job.audio_url) throw new Error("demo has no audio");
    const response = await tracedFetch(job.audio_url);
    if (!response.ok) throw new Error("recording expired");
    peaks = samplePeaks(await decodeBlob(await response.blob()), 110);
  } catch (_) {
    peaks = Array.from({ length: 110 }, (_, index) => .2 + Math.abs(Math.sin(index * .37)) * .65);
  }
  drawFingerprint(result, peaks, job.location || $("location").value || "杭州");
  showPanel("result-panel");
  if (persist && !job.is_demo) saveToCollection(job);
  refreshHistoryButton();
  $("result-title").focus({ preventScroll: true });
  $("result-panel").scrollIntoView({ behavior: reducedMotion ? "auto" : "smooth", block: "start" });
}

function renderCreation(job) {
  const creation = job.creation || { status: "idle" };
  const status = creation.status || "idle";
  const busy = ["queued", "generating_music", "generating_narration", "generating_video", "composing_video"].includes(status);
  $("creation-block").hidden = Boolean(job.is_demo || job.capabilities?.creation === false);
  $("create-postcard-button").hidden = busy || status === "completed";
  $("create-postcard-button").textContent = status === "partial" || status === "failed" ? "重新尝试" : "开始创作";
  $("creation-progress").hidden = !busy;
  $("creation-stage").textContent = creation.stage_message || "正在准备创作";

  const hasMusic = Boolean(creation.music_url);
  const hasNarration = Boolean(creation.narration_url);
  const hasVideo = Boolean(creation.video_url);
  $("creation-media").hidden = !hasMusic && !hasNarration && !hasVideo;
  $("music-result").hidden = !hasMusic;
  $("narration-result").hidden = !hasNarration;
  $("video-result").hidden = !hasVideo;
  if (hasMusic) {
    $("creation-audio").src = creation.music_url;
    $("download-music").href = creation.music_url;
    $("music-provider").textContent = creation.music_provider === "minimax-music"
      ? "MiniMax Music 3.0"
      : "原声混音";
  } else {
    $("creation-audio").removeAttribute("src");
  }
  if (hasNarration) {
    $("creation-narration").src = creation.narration_url;
    $("download-narration").href = creation.narration_url;
  } else {
    $("creation-narration").removeAttribute("src");
  }
  if (hasVideo) {
    $("creation-video").src = creation.video_url;
    $("download-video").href = creation.video_url;
    $("video-provider").textContent = ({
      "wan2.7-t2v": "Wan2.7 · 竖屏",
      "reused-demo-video": "演示画面 · 竖屏",
      "local-mock-video": "开发占位 · 竖屏",
    })[creation.video_provider] || "竖屏";
  } else {
    $("creation-video").removeAttribute("src");
  }
  if (status === "partial") {
    $("creation-status").textContent = `音乐已经完成；视频暂时没有生成。${creation.video_error || "可以稍后重试。"}`;
  } else if (status === "failed") {
    $("creation-status").textContent = creation.error || "创作没有完成，可以重新尝试。";
  } else if (status === "completed") {
    const musicLabel = creation.music_provider === "minimax-music"
      ? "音乐由 MiniMax Music 3.0 生成"
      : "音乐使用本次自然原声制作";
    const narrationLabel = hasNarration ? "旁白由 MiniMax Speech 生成" : "本次未生成旁白";
    const videoLabel = creation.video_provider === "wan2.7-t2v"
      ? "画面由 Wan2.7 生成"
      : creation.video_provider === "reused-demo-video" ? "画面使用演示素材" : "画面为开发占位素材";
    $("creation-status").textContent = `${musicLabel}，${narrationLabel}；${videoLabel}。`;
  } else {
    $("creation-status").textContent = "";
  }
}

async function startCreation() {
  if (!currentJob || currentJob.is_demo) return;
  const token = ++creationPollToken;
  $("create-postcard-button").disabled = true;
  try {
    webLog("info", "creation_started", { job_id: currentJob.id });
    const response = await tracedFetch(apiUrl(`/api/jobs/${encodeURIComponent(currentJob.id)}/creation`), { method: "POST" });
    if (!response.ok) throw new Error(await response.text());
    currentJob = await response.json();
    renderCreation(currentJob);
    const deadline = Date.now() + 8 * 60 * 1000;
    while (Date.now() < deadline && token === creationPollToken) {
      await new Promise((resolve) => setTimeout(resolve, 3500));
      const next = await tracedFetch(apiUrl(`/api/jobs/${encodeURIComponent(currentJob.id)}`));
      if (!next.ok) throw new Error(await next.text());
      currentJob = await next.json();
      renderCreation(currentJob);
      const status = currentJob.creation?.status;
      if (["completed", "partial", "failed"].includes(status)) {
        webLog(status === "failed" ? "error" : "info", "creation_finished", { job_id: currentJob.id, status });
        saveToCollection(currentJob);
        return;
      }
    }
    if (token === creationPollToken) $("creation-status").textContent = "生成仍在继续，可以稍后从声音册回来查看。";
  } catch (error) {
    webLog("error", "creation_failed", { job_id: currentJob?.id || "unknown", error_type: error?.name || "Error" });
    $("creation-progress").hidden = true;
    $("create-postcard-button").hidden = false;
    $("creation-status").textContent = readableError(error);
  } finally {
    $("create-postcard-button").disabled = false;
  }
}

function collectionItems() {
  try {
    const items = JSON.parse(localStorage.getItem(COLLECTION_KEY) || "[]");
    return Array.isArray(items) ? items : [];
  } catch (_) {
    return [];
  }
}

function writeCollection(items) {
  try { localStorage.setItem(COLLECTION_KEY, JSON.stringify(items.slice(0, MAX_COLLECTION_ITEMS))); }
  catch (_) { /* local storage is optional */ }
}

function saveToCollection(job) {
  const compact = JSON.parse(JSON.stringify(job));
  if (compact.result) delete compact.result.usage;
  compact.saved_at = new Date().toISOString();
  const items = collectionItems().filter((item) => item.id !== compact.id);
  items.unshift(compact);
  writeCollection(items);
}

function refreshHistoryButton() {
  const count = collectionItems().length;
  $("history-button").textContent = count ? `声音册 · ${count}` : "声音册";
}

function demoJob() {
  return {
    id: "demo-west-lake-blackbird",
    is_demo: true,
    location: "杭州植物园",
    created_at: new Date().toISOString(),
    audio_url: null,
    result: {
      sound_types: ["鸟类鸣叫"],
      primary_sound_type: "鸟类鸣叫",
      possible_sound_types: [],
      confidence_level: "demo",
      possible_species: ["乌鸫"],
      bird_species: [{ name_zh: "乌鸫", confidence: .72 }],
      evidence: ["连续出现清楚的哨音", "声音之间有稳定停顿", "适合远距离继续观察"],
      uncertainty: "这是流程示例，实际结果会根据你的录音重新分析。",
      card: {
        title: "树梢传来的歌声",
        explanation: "示例中比较明显的是鸟儿的叫声。不同鸟类会用声音联系同伴、提醒危险或表达自己的位置，我们可以先记下节奏，再远远观察。",
        question: "安静听一听，这个声音每隔多久会重复一次？",
        safety_note: "户外观察请和大人同行，只倾听和记录，不追逐或触摸动物。",
      },
    },
  };
}

function renderCollection() {
  const items = collectionItems();
  $("collection-list").replaceChildren(...items.map((job) => {
    const article = document.createElement("article");
    article.className = "collection-item";
    const time = document.createElement("time");
    const savedAt = new Date(job.saved_at || job.created_at || Date.now());
    time.dateTime = savedAt.toISOString();
    time.textContent = savedAt.toLocaleString("zh-CN", { month: "numeric", day: "numeric", hour: "2-digit", minute: "2-digit" });
    const title = document.createElement("h3");
    title.textContent = job.result?.card?.title || "声音记录";
    const meta = document.createElement("p");
    meta.textContent = `${job.location || "杭州"} · ${job.result?.primary_sound_type || job.result?.sound_types?.[0] || "待确认"}`;
    const actions = document.createElement("div");
    actions.className = "collection-item-actions";
    const open = document.createElement("button");
    open.className = "collection-open";
    open.type = "button";
    open.textContent = "查看";
    open.addEventListener("click", async () => {
      if (job.id && !job.is_demo) {
        try {
          const response = await tracedFetch(apiUrl(`/api/jobs/${encodeURIComponent(job.id)}`));
          if (response.ok) return renderResult(await response.json(), { persist: false });
        } catch (_) { /* fall back to local snapshot */ }
      }
      return renderResult(job, { persist: false });
    });
    const remove = document.createElement("button");
    remove.className = "collection-delete";
    remove.type = "button";
    remove.textContent = "删除";
    remove.addEventListener("click", () => deleteCollectionItem(job));
    actions.append(open, remove);
    article.append(time, title, meta, actions);
    return article;
  }));
  $("collection-empty").hidden = items.length > 0;
  $("clear-collection").hidden = items.length === 0;
}

async function deleteCollectionItem(job) {
  if (job.id && !job.is_demo) {
    try {
      const response = await tracedFetch(apiUrl(`/api/jobs/${encodeURIComponent(job.id)}`), { method: "DELETE" });
      if (!response.ok && response.status !== 404) throw new Error("delete failed");
    } catch (_) {
      $("collection-empty").hidden = false;
      $("collection-empty").textContent = "服务器删除暂时没有完成，请检查网络后重试。";
      return;
    }
  }
  writeCollection(collectionItems().filter((item) => item.id !== job.id));
  refreshHistoryButton();
  renderCollection();
}

async function submitFeedback(isCorrect, correctedType = null) {
  if (!currentJob || currentJob.is_demo) return;
  const correctedTaxon = $("corrected-taxon").value || null;
  const payload = {
    job_id: currentJob.id,
    recording_id: currentJob.id,
    is_correct: isCorrect,
    decision: isCorrect ? "correct" : (correctedType === "无法判断" ? "uncertain" : "wrong"),
    corrected_type: correctedType,
    corrected_taxon_id: correctedTaxon,
    consent_to_retain_audio: $("feedback-consent").checked,
  };
  try {
    const response = await tracedFetch(apiUrl("/api/feedback"), {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(payload),
    });
    if (!response.ok) throw new Error("feedback failed");
    $("feedback-status").textContent = isCorrect ? "谢谢确认，这会帮助我们检查模型表现。" : "更正已记录，谢谢你帮助我们听得更准。";
  } catch (_) {
    const local = (() => { try { return JSON.parse(localStorage.getItem(LOCAL_FEEDBACK_KEY) || "[]"); } catch (_) { return []; } })();
    local.push({ ...payload, created_at: new Date().toISOString() });
    try { localStorage.setItem(LOCAL_FEEDBACK_KEY, JSON.stringify(local.slice(-30))); } catch (_) { /* optional */ }
    $("feedback-status").textContent = "网络暂时不可用，更正已保存在当前设备。";
  }
  $("feedback-yes").disabled = true;
  $("feedback-no").disabled = true;
  $("correction-panel").hidden = true;
  $("feedback-consent").disabled = true;
}

function readableError(error) {
  const text = String(error?.message || error);
  try {
    const parsed = JSON.parse(text);
    return parsed.detail || text;
  } catch (_) {
    return text;
  }
}

$("record-button").addEventListener("click", toggleRecording);
$("upload-button").addEventListener("click", () => $("file-input").click());
$("demo-button").addEventListener("click", () => renderResult(demoJob(), { persist: false }));
$("file-input").addEventListener("change", async (event) => {
  const file = event.target.files[0];
  if (!file) return;
  if (file.size > MAX_UPLOAD_BYTES) {
    showError("录音文件太大", "请选择 15MB 以内的录音，或先截取需要识别的 20 秒。", "capture", "重新选择录音");
    return;
  }
  await setReady(file, file.name);
});
$("clear-button").addEventListener("click", resetCapture);
$("analyze-button").addEventListener("click", startAnalysis);
$("cancel-button").addEventListener("click", () => {
  activeRunId += 1;
  analysisAbortController?.abort();
  analysisAbortController = null;
  showPanel("ready-panel");
  $("analyze-button").focus();
});
$("history-button").addEventListener("click", () => {
  renderCollection();
  showPanel("collection-panel");
  $("collection-title").focus({ preventScroll: true });
});
$("play-card-button").addEventListener("click", async () => {
  const audio = $("result-audio");
  try {
    if (audio.paused) {
      await audio.play();
      $("play-card-button").textContent = "暂停";
    } else {
      audio.pause();
      $("play-card-button").textContent = "播放录音";
    }
  } catch (_) {
    $("save-status").textContent = "录音已经过期或暂时无法播放，声音卡仍可查看。";
  }
});
$("result-audio").addEventListener("ended", () => { $("play-card-button").textContent = "播放录音"; });
$("save-card-button").addEventListener("click", () => {
  if (!fingerprintReady) return;
  $("fingerprint-canvas").toBlob((blob) => {
    const link = document.createElement("a");
    link.href = URL.createObjectURL(blob);
    link.download = `自然声音卡-${Date.now()}.png`;
    link.click();
    $("save-status").textContent = "声音卡已交给浏览器保存。";
    $("save-card-button").disabled = true;
    setTimeout(() => { $("save-card-button").disabled = false; }, 1200);
    setTimeout(() => URL.revokeObjectURL(link.href), 1000);
  }, "image/png");
});
$("create-postcard-button").addEventListener("click", startCreation);
$("feedback-yes").addEventListener("click", () => submitFeedback(true));
$("feedback-no").addEventListener("click", () => {
  $("correction-panel").hidden = false;
  $("corrected-type").focus();
});
$("submit-correction").addEventListener("click", () => submitFeedback(false, $("corrected-type").value));
$("restart-button").addEventListener("click", () => {
  resetCapture();
  $("intro").scrollIntoView({ behavior: reducedMotion ? "auto" : "smooth" });
});
$("error-retry").addEventListener("click", () => {
  if ($("error-retry").dataset.mode === "capture") resetCapture();
  else if (selectedBlob) showPanel("ready-panel");
  else resetCapture();
});
$("collection-back").addEventListener("click", resetCapture);
$("clear-collection").addEventListener("click", async () => {
  const items = collectionItems();
  await Promise.allSettled(items.filter((item) => item.id && !item.is_demo).map((item) => (
    tracedFetch(apiUrl(`/api/jobs/${encodeURIComponent(item.id)}`), { method: "DELETE" })
  )));
  writeCollection([]);
  refreshHistoryButton();
  renderCollection();
});

startIdleVisual();
refreshHistoryButton();
