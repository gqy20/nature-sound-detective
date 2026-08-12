# v022 手机框与地图展开预览

本轮只验证展示语言，尚未批量应用到所有视频片段。

- `01-light-editorial-frame-v022.png`：浅色编辑场景，8 px 深森林绿设备边缘。
- `02-dark-editorial-frame-v022.png`：深色情绪场景，8 px 暖象牙白设备边缘。
- `03-map-expansion-state-v022.png`：手机内真实地图向 16:9 杭州地图展开的动画中间态。

统一约束：

- 真实录屏像素内容不重绘、不改字、不补造 UI。
- 无刘海、无伪造按键、无投影。
- 仅使用一层实体边缘与 1 px 内高光。
- 地图转场从手机内地图区域发起，不采用简单同比放大。

可复现脚本：`promo-video/scripts/compose_device_frame_previews_v022.py`
