# CLI 与真实交互一致性调试体系

> 文档状态：决赛实施版 v0.1  
> 更新时间：2026-08-24  
> 适用范围：Python/FastAPI、Web 调查交互、CLI 调试、后续 Flutter 在线 Agent 接入

## 1. 目标

CLI 不是独立于产品的第二套实现，也不是只为“在终端运行模型”提供的薄包装。它是调查 Agent 的可复现调试入口，必须与真实 API 共享：

- 同一份模型融合结果；
- 同一份调查证据结构；
- 同一份观察问题；
- 同一套调查状态迁移；
- 同一套安全和结案规则；
- 同一份可回放运行包。

一致性的判据不是“终端显示和界面看起来差不多”，而是：

> 对相同的模型结果、地点和人类观察，CLI 与 API 调用同一个领域函数，得到相同的调查状态、轮次、停止原因和证据包。

## 2. 当前问题

项目已有大量 `scripts/*.py`，覆盖数据索引、训练、评测、压力测试和部署。这些脚本有明确价值，但尚不能完整回答一次真实调查为什么产生当前结果：

1. 模型阶段结果分散在 YAMNet、BirdNET、非鸟分类头及融合层中；
2. Web/API 任务只保存最终 `result`，缺少独立调查状态；
3. Flutter 的 `fieldChecks` 属于端侧记录，服务端没有对应的统一观察提交契约；
4. 修改融合规则后，历史案例不能从模型结果离线回放；
5. CLI、API 和移动端若各自实现状态更新，会产生行为漂移；
6. 模型版本、输入哈希、耗时和回退原因缺少统一运行包。

## 3. 共享架构

```text
录音或文件
  ↓
音频预处理
  ↓
YAMNet / BirdNET / 非鸟分类头
  ↓
result_fusion.py
  ↓
build_investigation()  ← 唯一调查初始化逻辑
  ↓
调查证据 + 当前问题 + 等待观察状态
  ├─ FastAPI / Web
  └─ CLI运行包
       ↓
apply_observation()    ← 唯一观察状态迁移逻辑
  ↓
completed / unresolved + stop_reason
```

核心约束：

- CLI 只负责解析参数、展示结果和保存运行包；
- API 只负责 HTTP 校验、权限与错误映射；
- 调查状态逻辑集中在 `app/investigation.py`；
- CLI 和 API 不得复制候选、观察或结案规则；
- 后续候选更新和问题策略必须扩展共享领域层，而不是直接写入界面或CLI。

## 4. 已落地的共享调查契约

### 4.1 调查状态

```json
{
  "schema_version": 1,
  "id": "job-...",
  "status": "awaiting_observation",
  "round": 0,
  "evidence": {},
  "question": {},
  "observations": [],
  "decision_history": [],
  "stop_reason": null
}
```

当前状态定义：

| 状态 | 含义 |
|---|---|
| `awaiting_observation` | 模型候选已生成，等待至少一项现场观察 |
| `completed` | 已记录可用的人类观察，调查可以结案 |
| `unresolved` | 儿童或家长无法判断，保留候选和不确定性 |

当前状态机只实现决赛最小的一轮交互，不声称已经完成自动候选二次排序。下一阶段优先用确定性规则记录人类观察对候选的支持或削弱；第二轮必须经过真实用户验证。

### 4.2 证据包

共享证据由最终融合结果标准化生成，包括：

- 主要声音大类；
- 已检测及可能存在的声景线索；
- 谨慎置信等级；
- 具体候选、模型来源及分数；
- 候选对应时间区间；
- YAMNet 通用声景时间片与模型不确定性；
- 各模型版本与能力范围；
- 区域级地点。

它只保存可追溯信息，不把大模型自由生成内容当作新证据。

### 4.3 观察提交

当前统一选择值：

| 值 | 面向用户含义 | 状态结果 |
|---|---|---|
| `observed` | 观察到了 | `completed` |
| `not_observed` | 没有观察到 | `completed` |
| `unknown` | 无法判断 | `unresolved` |

观察还可以携带最多 300 字的补充说明。API 与 CLI 均校验：

- 问题 ID 必须与当前调查一致；
- 调查结案后不能重复提交；
- 选择值必须在白名单中；
- 补充说明长度受限；
- 所有状态变化写入 `decision_history`。

## 5. CLI 命令

CLI 不要求手动激活虚拟环境，统一通过 `uv run` 执行。

### 5.1 环境体检

```powershell
uv run python -m app.cli doctor
uv run python -m app.cli doctor --json
```

检查 Python 3.11、FFmpeg/FFprobe、端侧模型文件及云端服务是否配置。密钥只显示是否存在，不输出内容。

### 5.2 单条录音分析

```powershell
uv run python -m app.cli analyze "data/demo.wav" `
  --mode full `
  --location "杭州植物园"
```

模式：

| 模式 | 行为 | 远程调用 |
|---|---|---|
| `full` | YAMNet + BirdNET + 非鸟分类头，与本地完整版一致 | 无 |
| `yamnet` | 只运行通用声景模型 | 无 |
| `acoustic` | 只运行BirdNET与非鸟分类头，用于专业模型调试 | 无 |

分析完成后生成 `artifacts/cli-runs/<run-id>/`。CLI 分析命令不调用 Fun-Music、Qwen-Audio-TTS 或 Wan，不产生媒体生成费用。

### 5.3 查看运行包

```powershell
uv run python -m app.cli inspect artifacts/cli-runs/<run-id>
uv run python -m app.cli inspect artifacts/cli-runs/<run-id> --stage investigation --json
```

可查看 `run/result/investigation/progress` 四个阶段。

### 5.4 提交现场观察

```powershell
uv run python -m app.cli investigate artifacts/cli-runs/<run-id> `
  --choice observed `
  --note "声音来自高处树冠"
```

`observe` 是同义命令。它调用与 API 相同的 `apply_observation()`，更新运行包中的 `investigation.json`。

### 5.5 离线回放

```powershell
uv run python -m app.cli replay artifacts/cli-runs/<run-id> --json
```

回放不调用模型。它从 `result.json` 重新建立调查，再依次应用已保存的人类观察，并比较：

- 状态；
- 轮次；
- 证据；
- 观察记录；
- 停止原因。

任一项不一致时返回非零退出码。

## 6. 运行包

```text
artifacts/cli-runs/<run-id>/
├── run.json
├── result.json
├── investigation.json
├── progress.json
└── replayed-investigation.json  # 执行replay后生成
```

`run.json` 当前记录：

-运行ID和trace ID；
-创建时间、模式和区域级地点；
-输入文件名、大小和SHA-256；
-分析后音频时长；
-云端服务是否配置；
-运行状态。

运行包默认不复制原始录音，不保存API Key。后续比较模型、阈值和规则版本时，必须继续保持输入路径、观察原文和服务配置脱敏。

## 7. 真实API交互

分析任务完成后，`JobStore` 自动使用共享函数生成 `investigation`，因此：

```http
GET /api/jobs/{job_id}
```

会同时返回识别结果和调查状态。

现场观察通过：

```http
POST /api/jobs/{job_id}/investigation/observations
Content-Type: application/json

{
  "question_id": "field-observation-1",
  "choice": "observed",
  "note": "声音来自高处树冠"
}
```

API 不自行实现状态更新，只把请求交给 `JobStore.submit_observation()`，后者调用 `apply_observation()`。

Vercel轻量版没有持久任务存储，因此分析响应直接携带 `investigation`，并提供无状态端点：

```http
POST /api/investigation/observations

{
  "investigation": {},
  "question_id": "field-observation-1",
  "choice": "observed",
  "note": ""
}
```

该端点同样调用 `apply_observation()`。Web根据服务能力自动选择本地有状态端点或云端无状态端点，不在浏览器里自行计算调查状态。

真实Web结果页读取 `investigation.question.options` 生成观察按钮；提交成功后使用服务端返回状态更新界面。调查仍处于 `awaiting_observation` 时，本地创作入口不展示，避免跳过现场观察直接进入视频创作。

已有历史任务若包含 `result` 但缺少 `investigation`，服务重启加载时会按共享契约补建调查状态。

## 8. 一致性测试

自动化测试覆盖：

1. 相同输入、ID和时间生成完全一致的调查状态；
2. JobStore与CLI观察提交产生相同状态、轮次、选择和停止原因；
3. 真实FastAPI端点返回共享调查状态；
4. CLI运行包可以提交观察并离线回放；
5. 回放证据与保存证据完全一致。

正式验收命令：

```powershell
uv run pytest tests/test_investigation_contract.py -q
uv run pytest tests -q
```

## 9. 与Flutter的一致性路线

当前 Flutter 完整版的分析与 `fieldChecks` 仍以端侧数据结构为主，本轮没有强行重写移动端。下一阶段按以下顺序接入：

1. 将服务端调查Schema生成Dart模型；
2. 在线模式把端侧YAMNet/BirdNET/nonbird证据提交给服务端调查端点；
3. Flutter展示服务端返回的 `question/options/status/stop_reason`；
4. Flutter提交观察时只发送统一的 `question_id/choice/note`；
5. 离线模式实现相同选择值和状态语义；
6.增加Python契约夹具与Dart反序列化测试，防止字段漂移。

在Flutter完成上述接入前，只能宣称“CLI与Python/FastAPI真实交互一致”，不能宣称三端已完全统一。

## 10. 下一阶段：确定性调查更新

本轮解决的是状态、证据、回放和交互入口，不冒充已经完成多轮Agent。L1/L2应在共享契约上继续：

### L1

-YAMNet、BirdNET与非鸟分类头并行生成结构化证据；
-规则层统一候选、时间片、冲突、拒识和能力范围；
-问题策略从审核过的安全问题库中选择下一步；
-分析链路不调用通用音频大模型。

### L2

-人类观察写入统一调查状态；
-确定性规则根据机器证据和人类观察记录支持、未观察到或无法判断；
-规则层验证越界候选、安全和停止条件；
-默认一轮，最多两轮；
-任何模型输出不可直接把候选升级为人工确认。

新增字段优先采用向后兼容方式，例如：

```json
{
  "agent_assessment": {},
  "candidate_changes": [],
  "question_purpose": "...",
  "rule_validation": {},
  "fallbacks": []
}
```

## 11. 决赛闸门

- `doctor`在演示机返回核心环境通过；
-三条固定案例均有可回放运行包；
-CLI `full`结果与API任务结果使用同一融合和调查初始化函数；
-API与CLI提交相同观察后得到相同状态语义；
-断网时仍能对缓存运行包执行`inspect/investigate/replay`；
-运行包不含密钥和未经授权的录音副本；
-CLI分析不触发音乐和视频付费调用；
-所有调查契约测试与完整Python测试通过。

## 12. 代码入口

- `app/investigation.py`：证据标准化、调查初始化、观察状态迁移、离线回放；
- `app/run_artifacts.py`：运行包、输入哈希和脱敏；
- `app/cli.py`：命令行适配；
- `app/jobs.py`：真实任务接入共享调查状态；
- `app/main.py`：观察提交HTTP端点；
- `tests/test_investigation_contract.py`：CLI/API一致性契约测试。
