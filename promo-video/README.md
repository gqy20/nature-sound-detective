# 《自然声探员》宣传视频制作工程

## 当前逐片调试（v027）

- 1080p 正式成片：`08-exports/1080p/xykw-promo-v027-1080p.mp4`
- 成片交付清单：`08-exports/1080p/xykw-promo-v027-1080p-manifest.json`
- 成片来源说明：`08-exports/1080p/xykw-promo-v027-1080p-provenance.md`

- 1080p 调试片段：`07-edit/debug-segments-v027/`
- 2 fps 抽帧检查：`09-qc/story-scenes-v027-2fps/`
- 正式旁白：`06-audio/voiceover/formal/formal-voiceover-v013-105.wav`
- 设计字幕：`07-edit/subtitles/xykw-promo-designed-v013-105.ass`
- 通用字幕：`07-edit/subtitles/xykw-promo-voice-timed-v013-105.srt`
- 逐镜头字幕：`07-edit/subtitles/v013-105-scenes/`
- 15 镜头校验清单：`07-edit/debug-segments-v027/manifest-complete.json`
- 字幕规范：`00-brief/subtitle-system-v013-105.md`
- 质量检查：`09-qc/v013-105-narration-subtitle-review.md`

v013-105 以“这段声音里，藏着什么？”贯穿家长、孩子、AI 调查和共听杭州；正式配音全片固定 `1.05x`，未使用逐场变速。v027 已将真实发音时间字幕接入全部 15 个独立 1080p 片段，所有尾留白低于 2 秒，并输出 110 秒 1080p 正式成片；逐片与成片均已按每秒 2 帧完成 220 帧抽检。

## 当前 4K 交付（v014-map-entry）

- 推荐审片：`08-exports/4k-native/xykw-promo-polish-v014-map-entry.mp4`
- 无字幕母版：`08-exports/4k-native/xykw-promo-polish-v014-map-entry-clean.mp4`
- 构建配置：`video-config-v014-map-entry.json`
- 交付清单：`08-exports/4k-native/xykw-promo-polish-v014-map-entry-manifest.json`
- 质量检查：`09-qc/v014-map-entry-review.md`

本版使用 3840×2160、30 fps 的独立时间线重新渲染；修复地图 4K 双重缩放，增加真实“共听杭州”界面、连续地图放大转场、今日新声和等待协助内容展示。少数摄影底片和地图纹理受源素材分辨率限制，具体口径见质量检查文档。

本目录用于制作 110 秒、16:9 的《自然声探员》宣传片。产品代码和原始录屏不在这里复制或修改；`artifacts/` 保持为只读素材源。

## 当前制作阶段

- [x] 建立素材清单与代理文件；
- [x] 生成接触表并确认第一组选段；
- [x] 输出 105 秒无声结构粗剪；
- [x] 接入本地临时旁白与中文字幕轨；
- [x] 生成真实原声波形和频谱；
- [x] 以代码生成 25 秒 16:9 杭州声景地图，并接入 S10–S12；
- [x] 将波形和频谱接入动态精修版；
- [x] 替换独立生成开场、正式旁白与精细动效；
- [x] 输出 v004 设计字幕版与无字幕母版；
- [x] 输出 v012 原生 4K 主片和无字幕母版。

当前审片文件：

- `08-exports/review/xykw-promo-rough-v001.mp4`：无声结构版；
- `08-exports/review/xykw-promo-rough-vo-v001.mp4`：临时旁白＋内嵌中文字幕轨。
- `08-exports/review/xykw-promo-rough-vo-v002.mp4`：地图细节精修对照版；
- `08-exports/review/xykw-promo-polish-v003.mp4`：正式旁白、混音与全套动态图形版，当前推荐。
- `08-exports/review/xykw-promo-polish-v004.mp4`：生成式悬念开场、编辑式录屏侧栏、隐私化地图、设计字幕与 S14 明信片高潮，当前推荐。
- `08-exports/review/xykw-promo-polish-v004-clean.mp4`：与 v004 同步的无字幕母版。
- `08-exports/review/xykw-promo-polish-v005.mp4`：无字幕底框、软件能力卡重排、完整产品流程录屏与自适应字幕版，当前推荐。
- `08-exports/review/xykw-promo-polish-v005-clean.mp4`：与 v005 同步的无字幕母版。
- `08-exports/review/xykw-promo-polish-v006.mp4`：S05 操作区近景、声音证据补充层与完全无阴影字幕版，当前推荐。
- `08-exports/review/xykw-promo-polish-v006-clean.mp4`：与 v006 同步的无字幕母版。
- `08-exports/review/xykw-promo-polish-v007.mp4`：高密度杭州声景地图与真实自然明信片使用界面版，当前推荐。
- `08-exports/review/xykw-promo-polish-v007-clean.mp4`：与 v007 同步的无字幕母版。
- `08-exports/review/xykw-promo-polish-v008.mp4`：统一删除装饰性英文眉题并重新平衡标题留白的简洁版，当前推荐。
- `08-exports/review/xykw-promo-polish-v008-clean.mp4`：与 v008 同步的无字幕母版。
- `08-exports/review/xykw-promo-polish-v009.mp4`：修正声学识别技术口径并强化 AI 调查转译的过渡版本。
- `08-exports/review/xykw-promo-polish-v009-clean.mp4`：与 v009 同步的无字幕母版。
- `08-exports/review/xykw-promo-polish-v010.mp4`：确立“每个孩子都是自然声探员”的主角逻辑，AI 回归助手角色，并将生成画面模型恢复为实际使用的通义万相 Wan 2.7，当前推荐。
- `08-exports/review/xykw-promo-polish-v010-clean.mp4`：与 v010 同步的无字幕母版。
- `08-exports/review/xykw-promo-polish-v011.mp4`：历史审片版本；全片使用 `0.96x` 语速、真实发音时间字幕和共创后分享闭环，不再作为当前配音基准。
- `08-exports/review/xykw-promo-polish-v011-clean.mp4`：与 v011 同步的无字幕母版。
- `08-exports/4k/xykw-promo-polish-v011-4k.mp4`：3840 × 2160 的4K观感审片版；画面使用 Lanczos 高质量放大，字幕在4K画布重新渲染。

完整分镜见 [`../docs/22-宣传视频完整分镜.md`](../docs/22-宣传视频完整分镜.md)。

## 单一时间轴来源

`video-config.json` 保存主片尺寸、帧率、片长、字体方案以及 15 个镜头的起止时间。脚本和剪辑工程都应以它为准。

## 常用命令

```powershell
powershell -ExecutionPolicy Bypass -File .\promo-video\scripts\build-asset-manifest.ps1
powershell -ExecutionPolicy Bypass -File .\promo-video\scripts\make-proxies.ps1
powershell -ExecutionPolicy Bypass -File .\promo-video\scripts\make-contact-sheets.ps1
powershell -ExecutionPolicy Bypass -File .\promo-video\scripts\build-rough-cut.ps1
powershell -ExecutionPolicy Bypass -File .\promo-video\scripts\make-temp-voiceover.ps1
powershell -ExecutionPolicy Bypass -File .\promo-video\scripts\make-review-subtitles.ps1
powershell -ExecutionPolicy Bypass -File .\promo-video\scripts\mux-rough-review.ps1
powershell -ExecutionPolicy Bypass -File .\promo-video\scripts\render-core-motion-assets.ps1
powershell -ExecutionPolicy Bypass -File .\promo-video\scripts\render-hangzhou-map-motion.ps1
powershell -ExecutionPolicy Bypass -File .\promo-video\scripts\render-editorial-motion.ps1
powershell -ExecutionPolicy Bypass -File .\promo-video\scripts\render-analysis-waveform.ps1
powershell -ExecutionPolicy Bypass -File .\promo-video\scripts\make-formal-voiceover.ps1
powershell -ExecutionPolicy Bypass -File .\promo-video\scripts\make-final-mix.ps1
powershell -ExecutionPolicy Bypass -File .\promo-video\scripts\render-opening-v004.ps1
powershell -ExecutionPolicy Bypass -File .\promo-video\scripts\render-postcard-climax.ps1
powershell -ExecutionPolicy Bypass -File .\promo-video\scripts\build-v004-master.ps1
```

地图动画源代码位于 `scripts/render_hangzhou_map_motion.py`。它以项目内 OpenStreetMap 杭州底图为地理基础，通过代码控制镜头、色彩、区域声源、涟漪、连线、计数和波形；不是对手机截图做简单放大。v002 进一步加入精确的点位镜头绑定、低透明度地理网格、扫描光、路径流动粒子、演示数据标识和协助状态反馈。

## 关键约束

- 不覆盖 `artifacts/` 中的任何文件；
- 不把阿里巴巴普惠体字体文件提交到 Git 或随工程分发；
- 代理文件用于剪辑，最终主片重新连接 4K 原片；
- 候选物种不得在字幕或地图中改写为专业确认结果；
- 地图仅展示区域级模糊位置；
- 独立生成开场必须保留“AI 生成”来源说明，但不作为识别证据。
