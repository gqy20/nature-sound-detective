# 自然声探员

面向杭州亲子家庭的自然声音 AI 工具原型：采集户外声音，识别常见物种，生成儿童科普内容，并逐步扩展声音故事、音乐与成长记录。

## 当前进度

- 使用 `uv` 管理 Python 3.11 环境；
- 非破坏性索引 26 条既有物种录音；
- 收集 50 条 Freesound 公开预览背景声；
- 建立包含 76 条录音的本地人工复核工具；
- 完成 BirdNET 2.4 第二阶段基线；
- 生成 142 个三秒候选片段，并按源录音隔离训练、验证和测试集合。
- 跑通 Qwen3.5-Omni + BirdNET 亲子识别 MVP，并加入 20 秒输入提示、可取消等待、谨慎置信度、儿童内容安全护栏和上一次结果恢复。
- 完成体验增强：无模型示例、录音音质检查、结果纠错、本机声音册、分类错误恢复和 24 小时录音清理。
- 跑通 MiniMax Music 3.0、Speech 2.8 HD、Wan2.7 与 FFmpeg 三轨合成的创作闭环；开发环境默认不调用付费视频接口。

所有机器标签均为候选标签，未经人工试听确认的数据不能作为正式测试集。

## 环境

```powershell
uv sync
```

## 启动亲子 MVP

在根目录 `.env` 配置百炼密钥后运行：

```powershell
uv run uvicorn app.main:app --host 0.0.0.0 --port 8770
```

浏览器打开 `http://127.0.0.1:8770/`。MVP 支持手机录音或上传，使用 Qwen3.5-Omni 识别自然声音大类，并用 BirdNET 补充杭州常见鸟类候选。完整说明见 [Qwen MVP 完整流程](./docs/09-Qwen-MVP完整流程.md)。

复制 `.env.example` 后填写密钥。`WAN_VIDEO_MODE` 默认为 `mock`，不会产生视频费用；比赛演示可设为 `reuse` 并指定已有成片，只有最终验收才显式设为 `live`。

## 启动统一标注页面

```powershell
uv run python scripts/prioritize_freesound_review.py
uv run python scripts/prepare_unified_review.py
uv run python scripts/review_freesound.py --port 8767
```

浏览器打开 `http://127.0.0.1:8767/`。

## 复现实验

```powershell
uv run python scripts/index_existing_data.py
uv run python scripts/validate_data_stage1.py
uv run python scripts/run_stage2_birdnet.py
uv run python scripts/validate_stage2.py
uv run python scripts/audit_evaluation_readiness.py
```

已存在 BirdNET 检测结果、仅需重新生成划分和报告时：

```powershell
uv run python scripts/run_stage2_birdnet.py --reuse-detections
```

## 目录

- `docs/`：创意方案、技术调研、杭州物种筛选和实验记录；
- `scripts/`：数据索引、采集、机器预标注、人工复核与基线脚本；
- `data/metadata/`：数据台账、复核队列、检测结果和片段清单；
- `data/raw/`：原始或公开预览音频，不纳入 Git；
- `artifacts/`：可重新生成的实验产物，不纳入 Git。
- `app/`：亲子移动端 MVP、异步分析接口和模型融合流程；
- `outputs/mvp/`：MVP 上传、任务结果和本地测试产物，不纳入 Git。

详细入口见 [项目文档索引](./docs/README.md)。
