# 听见万物移动端

这是项目的 Flutter 移动端，当前优先交付 Android 比赛版，同时保留 iOS 工程和跨平台业务层。它不是网页的 WebView 包装：录音、音质检查、BirdNET/YAMNet 推理、结果融合和声音册都在设备本地运行；只有用户主动确认后，才会调用云端生成儿童科普卡片。

## 当前链路

1. Android 原生 `AudioRecord` 录制 48 kHz、单声道、16-bit PCM WAV，单次最长 20 秒。
2. 本地检测过静音、音量过低和削波，并允许回放重录。
3. YAMNet 将音频重采样为 16 kHz，识别鸟、蛙、昆虫、流水、风雨等通用声音类别。
4. BirdNET 使用 48 kHz、3 秒窗口，在杭州全年地理先验筛出的 200 种鸟类中给出候选。
5. 融合层去重并输出“线索强度、模型来源、时间片”，不把模型分数包装成准确率。
6. 用户可将录音、质量信息和识别结果保存到本地声音册。
7. 用户明确确认后，才调用现有 `/api/analyze` 生成科普内容。

非鸟分类头当前输出黑蚱蝉、布氏泛树蛙以及其他鸣虫/蛙类候选，并带拒识策略；来源标签测试结果不能替代杭州公园实录验收。

## 本地开发

```bash
flutter pub get
flutter analyze
flutter test
flutter run
```

构建 Android arm64 发布包：

```bash
flutter build apk --release --target-platform android-arm64 --split-per-abi
```

默认云端地址为 `https://xykw-api.vercel.app`。开发时可覆盖：

```bash
flutter run --dart-define=XYKW_API_BASE_URL=http://10.0.2.2:8000
```

自动测试不会请求云端 API；云端客户端使用替身响应验证协议和错误处理。

应用创建单例分析器，并在首帧后异步预加载 YAMNet、BirdNET 和非鸟分类头。并发的预加载与识别共享同一个加载任务和模型实例；加载失败不会缓存，下一次分析会重试。预加载不阻塞首屏，但首次立即录音时仍可能与后台加载重叠。

本地识别按 BirdNET 的 3 秒窗口逐段发布候选，结果面板会显示当前窗口进度；全部窗口完成后再与并行运行的 YAMNet 结果融合。阶段结果仅作为动态线索，保存与云端科普使用最终结果。

release APK 只打包 CPU 推理库，界面使用平台中文字体，杭州背景图采用 WebP；BirdNET、YAMNet、非鸟分类头和对应标签不会因包体优化而裁剪。

2026-08-04 的 Android arm64 干净 release 构建从 68,050,394 字节降至 51,605,504 字节，减少约 24.2%。包内检查确认三套模型仍在，且不再包含 GPU JNI、AlibabaPuHuiTi 字体和旧 PNG。

## 日志与诊断

首页右上角的诊断按钮可以查看结构化运行事件并导出脱敏 JSONL。一次录音以录音 ID 贯穿端侧分析和云端请求；Android 原生录音日志可通过 `adb logcat -s NatureAudio flutter` 查看。完整字段、轮转策略和隐私边界见 [`docs/logs.md`](../docs/logs.md)。

## 模型与许可

- `assets/models/yamnet.tflite`：YAMNet，Apache-2.0，用于通用声音类别。
- `assets/models/birdnet.tflite`：BirdNET V2.4 FP16，原始输出 6,522 类；`assets/labels/birdnet_hz.json` 保存杭州 200 种候选及输出索引。模型权重为 CC BY-NC 4.0。

BirdNET 可以用于本次非商业比赛原型；如果产品商业化，需要重新确认模型权重授权或替换为许可兼容的模型。模型哈希和标签范围记录在 `assets/models/manifest.json`。

## 当前验收边界

静态分析、单元测试和 Android APK 构建均可在 Windows 完成。仍需在目标 Android 真机上完成麦克风权限、真实录音推理延迟、连续三次全流程、内存和功耗验收。iOS 目录已保留，但签名和真机测试必须在 macOS/Xcode 环境进行。
