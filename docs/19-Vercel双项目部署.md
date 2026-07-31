# Vercel 双项目部署

## 已部署项目

| 项目 | 生产地址 | 功能 |
|---|---|---|
| `xykw-web` | <https://xykw-web.vercel.app> | 移动端静态页面、录音转 WAV、示例和声音卡展示 |
| `xykw-api` | <https://xykw-api.vercel.app> | FastAPI、Qwen3.5-Omni 声音大类理解、安全卡片整理 |

两个项目均属于 Vercel 团队 `gqys-projects`，源码位于 GitHub 私有仓库 `gqy20/xykw`。

## 为什么云端是轻量版

Vercel API 不安装 TensorFlow、BirdNET 或 FFmpeg，也不运行后台线程和本地任务数据库。浏览器先将录音转换为单声道 16 kHz WAV，再提交给云端 Qwen。API 在同一次请求中同步返回完成的声音卡片。

云端结果会返回能力声明：

```json
{
  "birdnet": false,
  "creation": false,
  "feedback": false,
  "persistence": false
}
```

前端据此隐藏媒体创作与反馈模块，并说明具体鸟种候选需要本地完整版。BirdNET、MiniMax 音乐与旁白、Wan 视频和 FFmpeg 三轨合成继续运行在本地或未来的常驻容器服务中。

## API 部署

根目录通过 `.vercel/project.json` 关联 `xykw-api`。生产环境必须配置：

- `DASHSCOPE_API_KEY`：Sensitive；
- `DASHSCOPE_BASE_URL`：百炼兼容接口地址。

`.vercelignore` 排除数据、模型、TensorFlow 依赖和本地应用，只上传轻量入口。Vercel 使用 `requirements.txt`，不读取完整版 `pyproject.toml/uv.lock`。

```powershell
vercel link --yes --project xykw-api --scope gqys-projects
vercel deploy --prod --yes --scope gqys-projects
```

健康检查：

```text
GET https://xykw-api.vercel.app/api/health
→ {"status":"ok","mode":"vercel-qwen-only"}
```

## Web 部署

静态目录 `app/static` 单独关联 `xykw-web`。在该目录执行：

```powershell
vercel link --yes --project xykw-web --scope gqys-projects
vercel deploy --prod --yes --scope gqys-projects
```

`deploy-config.js` 在 HTTPS 部署环境使用 `https://xykw-api.vercel.app`，在本地 HTTP 开发环境使用同源 `/api`，因此同一套页面同时支持云端轻量版和本地完整版。

## 已验证结果

- API 根路径与健康检查均返回 200；
- 一段 19.8 秒杭州录音在约 51 秒内完成云端识别；
- 返回模型为 `qwen3.5-omni-plus`，主要声音为“风和树叶”；
- 生产前端成功跨域访问生产 API；
- 390 px Chromium 页面宽度与滚动宽度均为 390；
- 示例结果可正常打开；
- 浏览器控制台 0 错误、0 警告。

## 已知边界

- 同步识别接近 60 秒函数时限时可能超时，演示应使用清晰且不超过 20 秒的录音；
- 云端不会返回 BirdNET 具体鸟种；
- 云端不保存原始录音、任务或反馈；
- 云端不生成音乐、旁白或视频；
- 比赛完整功能仍应准备本地服务和已有成片作为备用。
