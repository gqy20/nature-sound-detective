# Vercel 双项目部署

## 已部署项目

| 项目 | 生产地址 | 功能 |
|---|---|---|
| `xykw-web` | <https://xykw-web.vercel.app> | 移动端静态页面、录音转 WAV、示例和声音卡展示 |
| `xykw-api` | <https://listen-api.gqy20.top>（Vercel项目域名：<https://xykw-api.vercel.app>） | FastAPI、轻量YAMNet声音大类候选、安全卡片整理 |

两个项目均属于 Vercel 团队 `gqys-projects`，源码位于 GitHub 私有仓库 `gqy20/xykw`。

## 为什么云端是轻量版

Vercel API 不安装完整TensorFlow、BirdNET或FFmpeg，也不运行后台线程和本地任务数据库。浏览器先将录音转换为单声道16 kHz WAV，API使用`tflite-runtime`运行约4 MB的YAMNet模型，并在同一次请求中同步返回声音大类候选和调查状态。

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

根目录通过 `.vercel/project.json` 关联 `xykw-api`。YAMNet分析不需要模型API Key；社区数据库或对象存储仍按对应功能配置服务端环境变量。

`.vercelignore` 排除数据、模型、TensorFlow 依赖和本地应用，只上传轻量入口。Vercel 使用 `requirements.txt`，不读取完整版 `pyproject.toml/uv.lock`。

```powershell
vercel link --yes --project xykw-api --scope gqys-projects
vercel deploy --prod --yes --scope gqys-projects
```

健康检查：

```text
GET https://listen-api.gqy20.top/api/health
→ {"status":"ok","mode":"vercel-yamnet-only"}
```

## Web 部署

静态目录 `app/static` 单独关联 `xykw-web`。在该目录执行：

```powershell
vercel link --yes --project xykw-web --scope gqys-projects
vercel deploy --prod --yes --scope gqys-projects
```

`deploy-config.js` 在 HTTPS 部署环境使用 `https://listen-api.gqy20.top`，在本地 HTTP 开发环境使用同源 `/api`，因此同一套页面同时支持云端轻量版和本地完整版。

## 已验证结果

- API 根路径与健康检查均返回 200；
- Qwen历史版本的51秒耗时已不适用；YAMNet版本发布后需要重新记录冷启动与热运行耗时；
- 返回模型为 `YAMNet tflite-1`，主要声音为“风和树叶”；
- 生产前端成功跨域访问生产 API；
- 390 px Chromium 页面宽度与滚动宽度均为 390；
- 示例结果可正常打开；
- 浏览器控制台 0 错误、0 警告。

## 已知边界

- 冷启动需要加载约4 MB的YAMNet模型；发布后需验证Vercel函数内存、包体和P95耗时；
- 云端不会返回 BirdNET 具体鸟种；
- 云端不保存原始录音、任务或反馈；
- 云端不生成音乐、旁白或视频；
- 比赛完整功能仍应准备本地服务和已有成片作为备用。
