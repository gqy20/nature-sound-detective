# 截图采集阻塞

- Status: `BLOCKED`
- Target: 共听杭州内嵌地图、全屏地图、亲子游园指南推荐更新状态
- AVD: `Resizable_Experimental`
- Device size: `1080 × 2400` / `420 dpi`

## 现象

- 可见与无窗口模式均出现 `System UI isn't responding`；
- Flutter 进程随后出现 native crash，`ApplicationExitInfo` 为 status 11；
- 冷启动并尝试 `auto`、`swiftshader_indirect`、`software` GPU 后端仍不稳定；
- Widget golden 可以生成布局图，但当前测试宿主缺少正常中文字体与音频平台插件，不符合“真实稳定页面截图”的接收标准，因此未归档为实现截图。

## 已完成替代验证

- 地图全屏入口、放大、缩小、复位、城区选择和返回均由 Widget test 覆盖；
- 游园筛选更新状态、空状态、变化原因和底部结果入口均由 Widget test 覆盖；
- 全量静态分析和110项测试通过；
- 三张组件设计参考保存在 `../references/`。

## 后续动作

在稳定的实体Android设备或重新创建的AVD上重新执行本批次，并至少补齐：

1. `01-soundscape-inline-map.png`
2. `02-soundscape-fullscreen-map.png`
3. `03-soundscape-area-selected.png`
4. `04-park-guide-filter-change.png`
5. `05-park-guide-results-updated.png`
