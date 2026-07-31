# 第一阶段数据整理与 Freesound 背景采集

> 状态：已实现采集与索引工具，等待 Freesound API Token 进行实际下载  
> 更新日期：2026-07-31

## 0. 当前执行结果

现有数据索引已经实际运行：

| 项目 | 数量 |
|---|---:|
| 音频文件 | 26 |
| Xeno-canto 文件 | 12 |
| 本地或共享文件 | 14 |
| 文件名提示混合声景 | 7 |
| 音频读取失败 | 0 |
| SHA-256 完全重复组 | 1 |

重复组是两个文件名略有差异、内容完全相同的 `XC1145570` 小䴙䴘 WAV。当前只写入重复报告，没有删除任何文件。26条录音均为 `pending`，需要人工审核。

Freesound 查询配置和脚本已通过语法及 JSON 校验。当前机器没有配置 `FREESOUND_API_TOKEN`，因此使用公开网页回退模式完成了预览采集。

根据项目当前没有 API Token 的实际情况，另提供公开网页回退采集器。该模式只读取公开搜索页和声音详情页，并下载页面公开提供的高质量 CDN 预览；不会访问需要登录的原始文件下载接口。由于网页结构可能变化，台账中的许可和作者信息必须在正式发布前再次核验。

公开预览采集结果：

| 类别 | 数量 |
|---|---:|
| 风与树叶 | 10 |
| 远处交通 | 10 |
| 游客与脚步 | 10 |
| 雨水与公园环境 | 10 |
| 非目标动物与混合声景 | 10 |
| 合计 | 50 |

50条均为高质量 MP3 预览，总大小约58.8 MiB。许可证包括30条 CC0、19条 CC BY、1条 CC BY-NC；49条标记为商业兼容。完整性检查没有发现文件缺失、哈希不一致、重复 ID、重复预览或时长越界。

## 1. 阶段目标

第一阶段完成两件事：

1. 不移动、不重命名、不删除现有 `data/` 音频，生成格式、时长、哈希、弱标签和重复文件报告；
2. 从 Freesound 为五类背景各收集 10 条候选，保存来源与许可，人工审核后再进入训练数据。

Freesound 五类候选为风与树叶、远处交通、游客与脚步、雨水与公园环境、非目标动物与混合声景。所有候选默认 `review_status=pending`。

## 2. 整理现有数据

```powershell
uv run python scripts/index_existing_data.py
```

输出：

- `data/metadata/existing_recordings.csv`：现有录音索引；
- `data/metadata/duplicate_groups.json`：相同 SHA-256 的重复文件组。

文件名解析得到的物种只是弱标签。含“背景”“二重奏”“至少包含”等文字的文件会标记 `mixture_hint=true`，仍需人工审核。

## 3. 配置 Freesound Token

在 [Freesound API 凭证申请页](https://freesound.org/apiv2/apply/)申请 API key，然后只在当前终端设置环境变量：

```powershell
$env:FREESOUND_API_TOKEN="你的 API key"
```

不要把真实 Token 写入 `.env.example`、脚本、文档或 Git。

## 4. 先收集元数据

```powershell
uv run python scripts/collect_freesound_backgrounds.py
```

这一步请求五类候选并生成台账，但不下载音频。输出：

- `data/metadata/freesound_candidates.csv`；
- `data/metadata/freesound_candidates.jsonl`；
- `data/raw/freesound/api_responses/` 下的原始 API 响应。

如只允许未来可商业使用的 CC0/CC BY 数据：

```powershell
uv run python scripts/collect_freesound_backgrounds.py --commercial-only
```

## 5. 下载高质量预览

确认候选和许可字段正常后执行：

```powershell
uv run python scripts/collect_freesound_backgrounds.py --download-previews
```

脚本优先下载 `preview-hq-ogg`，缺失时回退 `preview-hq-mp3`，并计算下载文件 SHA-256。下载文件进入 `data/raw/freesound/previews/<category>/`，不会直接进入 `processed/`。

### 无 API Token 的公开预览模式

```powershell
uv run python scripts/collect_freesound_public_previews.py
```

该命令会直接收集五类各10条公开预览。需要优先保证未来商业兼容时使用：

```powershell
uv run python scripts/collect_freesound_public_previews.py --commercial-only
```

公开网页模式是无 Token 时的回退方案；拥有 Token 后仍优先使用官方 API，因为字段更完整、接口更稳定。

## 6. 人工审核

审核时填写：

- 是否为真实现场录音；
- 是否包含目标物种；
- 是否包含清晰人声或隐私风险；
- 应归为 background、unknown、mixed 还是 rejected；
- 可用时间段；
- 拒绝原因和审核人。

游客与脚步类必须优先检查人声和隐私。没有完成审核的 `pending` 数据不能用于正式训练、测试或公开 Demo。

重复运行完整性检查：

```powershell
uv run python scripts/validate_data_stage1.py
```

检查结果写入 `data/metadata/stage1_validation.json`。

## 7. 当前边界

- Freesound 候选只用于训练背景、unknown 和混音增强；
- 杭州手机实录仍是最终测试集；
- 试听版是有损转码，不用于精细高频生态声学结论；
- CC BY-NC 数据必须与未来商业兼容数据隔离；
- 同一上传者、pack 或原始声音的切片不得跨训练集和测试集。

## 8. 完成状态

- [x] 建立 raw、interim、processed、metadata 目录结构；
- [x] 建立现有音频非破坏性索引；
- [x] 计算 SHA-256 并输出重复组；
- [x] 建立五类 Freesound 查询配置；
- [x] 实现元数据、许可和高质量预览采集器；
- [x] 实现无 Token 的公开网页预览回退采集器；
- [x] 建立人工审核字段模板；
- [ ] 配置 Freesound API Token；
- [x] 无 Token 模式实际收集五类各10条候选；
- [x] 验证50条文件存在、哈希、ID、时长和许可证字段；
- [ ] 人工试听并完成 background、unknown、mixed、rejected 分类；
