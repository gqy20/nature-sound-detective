# v014-map-entry 交付检查

- 检查日期：2026-08-11
- 主文件：`08-exports/4k-native/xykw-promo-polish-v014-map-entry.mp4`
- 无字幕母版：`08-exports/4k-native/xykw-promo-polish-v014-map-entry-clean.mp4`
- 画面：3840×2160，30 fps，110.000 秒，H.264
- 音频：AAC，48 kHz，双声道
- 完整解码：通过，退出码 0
- 字幕：42 条；最大单行 18 个字符；无底框、无描边、无阴影
- SHA-256：`20BD6BEF9AB16007F6595680F9BCD5EE98949611FDE0467A35C3D4173DA68502`

## 地图修复

- 修复 4K 底图被重复乘以缩放系数的问题，不再产生越界黑区。
- 杭州底图铺满 3840×2160，S10–S12 不再套用手机镜头的 2000 像素缩进框。
- 地图相机锁定，点位、路线、计数、扫描线和波形独立运动，避免道路文字产生细碎晃动。
- 地图和代码点位统一在一套坐标变换中，不再出现底图与数据层错位。

## 共听杭州展示

- S10 先完整展示真实“共听杭州”使用截图，再连续放大截图中的杭州地图，并溶解到全屏代码声景地图。
- S11 先展示全屏“今日新声”网络，再回到真实软件界面；完整手机界面与放大的“12 条公开线索 / 4 条等待探员协助 / 区域地图”同时可见。
- S12 先展示真实线索卡、波形、候选按钮和“暂时无法判断”，随后进入全屏等待协助网络。
- 原录制截图没有单独保存“等待协助”选中态；本版只用确定性代码将现有三段标签的选中状态从“今日新声”切换到“等待协助”，没有生成或改写产品能力、数量和线索内容。

## 来源与可追溯性

- 真实软件截图：`artifacts/recording-part05-map.png`
- OSM 杭州底图：`mobile/assets/maps/hangzhou_osm.png`
- 固定地图资产：`05-motion/4k-v013/hangzhou-soundscape-map-v013-4k.mp4`
- 产品进入地图转场：`05-motion/4k-v014/map-entry-v014-4k.mp4`
- 今日新声展示：`05-motion/4k-v014/community-today-v014-4k.mp4`
- 等待协助展示：`05-motion/4k-v014/community-assist-v014-4k.mp4`
- 旧 S10 已保留为：`07-edit/scene-renders-4k/v014-map-entry/S10-before-full-interface-fix.mp4`
- 地图段联系表：`09-qc/v014-map-entry/final-map-section-sheet-v2.png`

