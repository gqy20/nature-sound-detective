# Qwen3.5-Omni MVP 完整流程

## 1. 当前目标

第一版不追求蛙类和昆虫的具体物种识别，优先验证亲子用户是否愿意完成“录音、等待、发现、继续观察”的完整闭环。

MVP 输出以下声音大类：鸟类鸣叫、蛙类鸣叫、昆虫鸣叫、雨水、流水、风和树叶、人声、脚步、交通或机械噪声、其他及无法判断。

## 2. 已实现流程

1. 手机浏览器录音，或上传已有音频；
2. 服务端使用 ffmpeg 截取最长 20 秒，并统一为 16 kHz 单声道 WAV；
3. 后台并行调用 Qwen3.5-Omni 与 BirdNET；
4. Qwen 输出多标签声景、大类置信等级、听觉依据、不确定性和儿童科普内容；
5. BirdNET 在杭州 MVP 六种常见鸟类范围内提供物种候选；
6. 服务端融合结果，前端轮询任务状态并生成自然声音卡片。

## 3. 服务接口

- `GET /api/health`：服务健康检查；
- `POST /api/analyze`：上传 `audio` 和可选 `location`，返回异步任务；
- `GET /api/jobs/{job_id}`：查询分析阶段和结果；
- `GET /api/jobs/{job_id}/audio`：播放标准化后的本次录音。

任务阶段为 `queued`、`analyzing`、`enriching`、`composing`、`completed` 或 `failed`。

## 4. 启动方式

在项目根目录创建 `.env`：

```dotenv
DASHSCOPE_API_KEY=替换为百炼密钥
DASHSCOPE_BASE_URL=https://dashscope.aliyuncs.com/compatible-mode/v1
```

安装并启动：

```powershell
uv sync
uv run uvicorn app.main:app --host 0.0.0.0 --port 8770
```

电脑访问 `http://127.0.0.1:8770/`。同一局域网的手机可以访问电脑局域网地址，但手机浏览器直接调用麦克风通常要求 HTTPS；局域网 HTTP 环境可先使用“选择已有录音”。

## 5. 当前边界

- Qwen 的 `high/medium/low` 是语言模型判断等级，不是经过校准的概率；
- BirdNET 当前仅增强六种配置鸟类，页面明确显示为候选；
- 大类识别不能替代蛙类和昆虫的物种级分类器；
- 任务保存在本机 `outputs/mvp/`，尚未接入用户账号和数据库；
- 单次真实分析约需 40 至 60 秒；
- 用户上传可能包含人声，正式公网部署前需要补充隐私告知、自动删除策略、HTTPS 和访问控制。

## 6. 下一轮验收

使用鸟、蛙、昆虫、雨水、人声交通五类独立录音，每类至少 10 条，记录大类准确率、漏检、混淆、调用时间和 token 消耗。具体物种结果不纳入第一轮核心指标。
