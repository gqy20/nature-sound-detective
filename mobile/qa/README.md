# 移动端交互验证归档

所有需要人工核对的移动端交互验证，都必须建立独立批次并保存证据，不能只依赖聊天记录或 `build/` 临时目录。

## 固定目录

```text
mobile/qa/runs/YYYY-MM-DD/NNN-topic/
├── manifest.md        # 批次目标、环境、操作步骤、结果和阻塞项
├── screenshots/       # 实际运行界面截图
├── references/        # 设计稿、组件草图或对照图
├── ui-tree/           # Android uiautomator XML 等结构证据
├── logs/              # 定向测试、静态分析、设备日志
└── artifacts/         # APK 哈希、包信息等轻量构建证据
```

用以下命令创建批次：

```powershell
uv run python scripts/create_mobile_qa_batch.py --slug map-fullscreen --title "地图全屏交互"
```

## 截图命名

按实际操作顺序编号：

```text
01-entry.png
02-control-open.png
03-after-selection.png
04-result.png
05-empty-or-error.png
```

截图必须记录对应步骤、设备尺寸、应用版本和状态。截图前要确认页面已经稳定，拒绝保存加载中、错误窗口、裁切错误或不属于目标应用的画面。

## 每批最低要求

- `manifest.md` 中写明目标和验收点；
- 至少包含入口状态、交互后状态、最终结果三类截图；
- 有结构化交互时保存 UI 树；
- 保存定向测试结果和静态分析结果；
- 保存 APK 路径、大小和 SHA-256，不重复提交大型 APK；
- 截图失败时在 `screenshots/CAPTURE_BLOCKED.md` 写明原因、已尝试方案和后续动作；
- 最终回复必须链接到本批次目录或清单。

## 批次状态

`manifest.md` 使用以下状态之一：

- `PASS`：验收点全部完成；
- `PARTIAL`：代码与自动测试通过，但部分人工证据缺失；
- `BLOCKED`：无法完成核心交互或证据采集；
- `FAIL`：已确认存在待修复问题。
