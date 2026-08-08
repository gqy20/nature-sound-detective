# 日志与诊断

项目使用统一的结构化 JSON 事件连接 Flutter、Android 原生录音、Vercel API、FastAPI 后台任务与模型服务。目标是回答“哪一步失败、用了多久、属于哪次录音”，而不是收集用户内容。

## 事件结构

```json
{
  "timestamp": "2026-08-02T12:00:00Z",
  "level": "info",
  "component": "birdnet",
  "event": "inference_completed",
  "trace_id": "rec_12345678",
  "duration_ms": 842,
  "window_count": 6,
  "detection_count": 2
}
```

一次移动端录音使用录音 ID 作为 `trace_id`，串联录制、音质检查、本地识别、保存和科普卡操作。一次 AI 创作使用作品 ID 作为 `trace_id`，串联音乐、旁白、Wan 视频、素材下载、本机合成和后台恢复事件。

## 移动端

Flutter 启动时安装三类全局异常处理：Flutter 框架错误、PlatformDispatcher 异步错误、Dart Zone 未捕获错误。日志同时写入调试控制台、内存中的最近 200 条记录，以及 App Support 私有目录下的滚动 JSONL 文件。

- 单个日志文件上限 512 KiB；
- 最多保留当前文件和两个历史文件；
- 首页右上角诊断按钮可以查看本次运行事件；
- “导出诊断日志”生成 JSONL 快照，并把文件路径复制到剪贴板；
- Android 录音错误同时写入 Logcat，标签为 `NatureAudio`。
- Android 后台视频任务写入 `native.jsonl`，独立轮转，并在导出时与 Flutter 日志合并；
- 后台日志同时写入 Logcat，标签为 `NatureDiagnostic`。

常用排查命令：

```bash
adb logcat -s NatureAudio NatureDiagnostic flutter
```

移动端关键组件包括 `audio`、`yamnet`、`birdnet`、`inference`、`storage`、`creation`、`creation_worker`、`works`、`settings`、`flutter` 和 `dart`。视频轮询只在供应商状态变化时记录，避免固定间隔产生重复日志。

`inference.analysis_completed` 同时记录各模型和最终融合候选的诊断摘要，包括类别、物种标识、四舍五入到两位的分数、模型来源及最多四个时间窗。摘要不包含录音内容和文件路径，用于定位重复候选、阈值误报和时间窗冲突。

## 服务端

Python 使用标准库 `logging` 输出单行 JSON，适配本地 Uvicorn、Vercel 函数日志和常见日志采集平台。`LOG_LEVEL` 可设置为 `DEBUG`、`INFO`、`WARNING` 或 `ERROR`，默认 `INFO`。

关键事件包括 HTTP 请求、分析任务阶段、模型加载、推理、云模型耗时、生成媒体耗时、降级路径和未捕获异常。异常只记录异常类型和调用栈位置，不写入第三方完整响应正文。

## 隐私规则

日志不得包含：

- 录音二进制或 Base64；
- 录音文件完整路径；
- API Key、Authorization、Token；
- 带签名参数的素材下载地址；
- 完整提示词或模型响应；
- 设备序列号、广告标识符或用户账号。

日志允许包含非识别性诊断信息，例如设备厂商与型号、Android SDK、App 版本、采样率、音频字节数、模型版本、候选数量和处理耗时。字段名包含敏感关键词时会自动替换为 `[REDACTED]`，常见 Bearer 和 `sk-` 密钥格式也会被二次脱敏。

## 故障定位顺序

1. 从用户截图或诊断文件取得 `trace_id`；
2. 检查 `audio.recording_completed`，确认录音参数和音质；
3. 比较 YAMNet、BirdNET 的模型加载和推理事件；
4. 查看 `inference.analysis_completed` 的融合前后候选数量；
5. 如涉及联网，用同一 `trace_id` 查询 Vercel/FastAPI 日志；
6. 根据 `status_code`、异常类型和最后完成的阶段判断客户端、网络、模型或供应商故障。

创作问题使用作品 ID 检索 `creation` 和 `creation_worker`：先找最后一个 `stage_changed`，再检查对应的供应商响应、状态变化、下载或合成事件。应用退到后台后的故障以导出文件中的 `creation_worker` 事件为准。
