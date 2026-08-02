# 听见万物移动端

这是项目的 Flutter 移动端，当前优先交付 Android 比赛版，同时保留 iOS 工程和跨平台业务层。它不是网页的 WebView 包装：录音、音质检查、BirdNET/YAMNet 推理、结果融合和声音册都在设备本地运行；只有用户主动确认后，才会调用云端生成儿童科普卡片。

## 当前链路

1. Android 原生 `AudioRecord` 录制 48 kHz、单声道、16-bit PCM WAV，单次最长 20 秒。
2. 本地检测过静音、音量过低和削波，并允许回放重录。
3. YAMNet 将音频重采样为 16 kHz，识别鸟、蛙、昆虫、流水、风雨等通用声音类别。
4. BirdNET 使用 48 kHz、3 秒窗口，给出杭州首批鸟种候选。
5. 融合层去重并输出“线索强度、模型来源、时间片”，不把模型分数包装成准确率。
6. 用户可将录音、质量信息和识别结果保存到本地声音册。
7. 用户明确确认后，才调用现有 `/api/analyze` 生成科普内容。

第一版对非鸟类只做到声音大类，不宣称可区分具体蛙种或昆虫种；这些类别需要后续用杭州本地数据训练专用分类头。

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

## 模型与许可

- `assets/models/yamnet.tflite`：YAMNet，Apache-2.0，用于通用声音类别。
- `assets/models/birdnet.tflite`：BirdNET V2.4 FP16，用于杭州首批鸟种；模型权重为 CC BY-NC 4.0。

BirdNET 可以用于本次非商业比赛原型；如果产品商业化，需要重新确认模型权重授权或替换为许可兼容的模型。模型哈希和标签范围记录在 `assets/models/manifest.json`。

## 当前验收边界

静态分析、单元测试和 Android APK 构建均可在 Windows 完成。仍需在目标 Android 真机上完成麦克风权限、真实录音推理延迟、连续三次全流程、内存和功耗验收。iOS 目录已保留，但签名和真机测试必须在 macOS/Xcode 环境进行。
