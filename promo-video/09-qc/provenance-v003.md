# v003 素材来源与生成记录

## 视觉方向

- 参考 Awwwards `Rhythm of Nature` 的极简双色、慢节奏感官叙事与声音互动；
- 参考 Awwwards `Editorial New / Typography in Motion` 的大字号、字重和字距运动思路；
- 只提炼设计原则，没有复制页面、代码、字体或具体画面。

## 生成与代码资产

- S01 杭州清晨锚点：Codex 内置 ImageGen 生成，提示词保存于 `00-brief/opening-image-prompt-v001.txt`；
- S01、S03、S07、S13、S15：`scripts/render_editorial_motion.py` 确定性生成；
- S06：项目真实录音驱动 FFmpeg `showwaves` 与 `showspectrum`；
- S10–S12：项目内 OpenStreetMap 杭州底图加代码动画，保留 `© OpenStreetMap contributors`；
- 正式旁白：MiniMax `speech-2.8-hd`，固定音色 `Chinese (Mandarin)_Warm_Girl`；
- 配乐与真实自然原声：复用项目 `artifacts/xykw-generated-music.mp3` 与 `artifacts/xykw-original-sound.wav`。

## S03 物种图片署名

- 黑斑侧褶蛙：Kim, Hyun-tae / iNaturalist，CC BY 4.0；
- 黑蚱蝉：chiuluan / iNaturalist，CC BY 4.0；
- 署名已直接写入对应视频画面。

## 当前限制

MiniMax 视频模型在 2026-08-10 当前时段的 3 次额度已用完。S01 当前采用“生成锚点图 + 确定性景深、推近、声纹与标题动画”的正式可用版本；待视频额度恢复后，可以使用同一分镜提示词替换为 7 秒纯生成视频，不影响现有时间轴、旁白、字幕或混音。
