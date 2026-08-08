# 内测诊断包

移动端诊断能力由编译期开关 `ENABLE_DIAGNOSTICS` 控制。日常 push 的 GitHub Actions
产物使用 release 性能构建，但显式开启该开关；正式发布包必须保持关闭。

```bash
# 内测 release APK
flutter build apk --release --dart-define=ENABLE_DIAGNOSTICS=true

# 正式 release APK（诊断入口不可见）
flutter build apk --release --dart-define=ENABLE_DIAGNOSTICS=false
```

内测包首页右上角显示诊断图标。点击后会打包当前录音；当前没有录音时，使用声音册中
最近保存的一条。长按首页标题仍可进入“运行诊断”，在那里可以关闭原始录音后再导出。

ZIP 内容包括：

- `manifest.json`：App 版本、构建模式、会话 ID 和隐私声明；
- `device.json`：Android、设备型号、ABI 和原生录音器诊断；
- `config.json`：创作功能是否配置及模型名称，不包含任何密钥值；
- `session/result.json`：录音参数、音质指标和识别候选；
- `session/recording.*`：用户允许时包含的原始录音；
- `logs/app.jsonl`：有界滚动日志快照；
- `logs/session.jsonl`：按录音 `trace_id` 筛选的会话日志。

导出采用字段白名单，不读取原始设置文件。打包前会再次扫描 Bearer、`sk-`、API Key、
Token 和带签名查询参数；发现疑似凭据时停止导出并删除未完成文件。缓存目录最多保留最近
三个 ZIP，避免长期占用手机空间。
