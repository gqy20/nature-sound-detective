# 底部导航参考

整理日期：2026-08-29。图片来自官方设计规范或 App Store 官方产品截图，仅用于本项目内部设计调研。

## 建议查看顺序

1. `material3-navigation-bar-page.png`
   - 来源：[Material Design 3 — Navigation bar](https://m3.material.io/components/navigation-bar/overview)
   - 重点：3–5 个等重要一级目的地、图标与标签始终可见、选中项使用轻量胶囊强调。
   - 与本项目匹配度：最高。儿童模式 3 项、家长模式 4 项都能直接套用。

2. `wechat-balanced-four-tabs.png`
   - 来源：[WeChat App Store](https://apps.apple.com/us/app/wechat/id414478124)
   - 重点：四个入口等宽排列；选中项只改变图标和文字颜色；整体稳定、克制、学习成本低。
   - 与本项目匹配度：高。适合作为家长模式四项底栏的信息架构参考。

3. `google-photos-four-tabs.jpg`
   - 来源：[Google Photos App Store](https://apps.apple.com/us/app/google-photos-backup-edit/id962194608)
   - 重点：四项底栏保持同一基线，其中“Create”仍作为普通目的地存在，没有做成凸起悬浮按钮。
   - 与本项目匹配度：高。可以借鉴为“录音”提供稍强语义，但不破坏底栏稳定性。

4. `inaturalist-emphasized-capture.png`
   - 来源：[iNaturalist App Store](https://apps.apple.com/us/app/inaturalist/id6475737561)
   - 重点：中央采集入口明显放大并使用品牌色，其他入口退居辅助位置。
   - 与本项目匹配度：中。视觉吸引力强，但容易把“录音页”误解成点击后立即录音的动作，应作为备选而不是首选。

## 当前建议

采用 Material 3 的结构和微信的克制程度：

- 儿童模式：录音 / 共听 / 自然册
- 家长模式：录音 / 共听 / 游园 / 自然册
- 所有入口等宽、图标加文字、固定在底部。
- 录音选中时可以使用较明显的浅绿色胶囊和实心图标，但先不做中央凸起大按钮。
- 顶部继续保留模式、家庭设备和设置；只把一级功能入口移到底部。

## 第二轮：更优雅的悬浮 Dock 方向

第二轮继续检查了 Awwwards 的 `dock menu`、`floating menu` 和 `fixed bottom navigation` 结果，并在 390 × 844 的移动视口中打开候选网站进行截图。

### Awwwards 参考

- `awwwards/00-awwwards-dock-menu-results.png`
  - Awwwards 的 Dock Menu 搜索结果，作为候选来源总览。
- `awwwards/02-off-menu-mobile.png`
  - 来源：[Off Menu — Awwwards SOTD](https://www.awwwards.com/sites/off-menu)
  - 可借鉴：大圆角、黑白高对比、导航容器与页面边缘留出呼吸空间。
  - 不应照搬：它在移动端仍是顶部品牌菜单，不是一级功能底栏。
- `awwwards/04-cooldock-mobile.png`
  - 来源：[Cooldock — Awwwards Honorable Mention](https://www.awwwards.com/sites/cooldock)
  - 可借鉴：悬浮 Dock 的整体轮廓、连续表面和克制的层次。
- `awwwards/06-zui-os-mobile.png`
  - 来源：[ZUI_OS — Awwwards Nominee](https://www.awwwards.com/sites/zui-os)
  - 可借鉴：底部固定、当前模块有明确区域高亮。
  - 不应照搬：终端文字风格、低对比未选中项和过小字号不适合儿童。
- `awwwards/10-rios-mobile.png`
  - 来源：[RI/OS — Awwwards Nominee](https://www.awwwards.com/sites/ri-os)
  - 可借鉴：最接近“优雅悬浮底栏”的案例——底部深色连续基座、独立圆角目的地、选中项使用不同材质色。
  - 不应照搬：六个无文字图标过多，辨识成本高。

### 更接近移动产品的参考

- `mobile-apps/alltrails-five-tabs-nature.jpg`
  - 来源：[AllTrails App Store](https://apps.apple.com/us/app/alltrails-hike-bike-run/id405075943)
  - 与自然探索场景最接近；五项仍保持非常安静，选中态只用品牌绿加强。
- `mobile-apps/headspace-calm-three-tabs.png`
  - 来源：[Headspace App Store](https://apps.apple.com/us/app/headspace-sleep-meditation/id493145008)
  - 三项目的地、低刺激配色和清晰标签，适合参考儿童模式。
- `mobile-apps/gentler-streak-soft-tabs.jpg`
  - 来源：[Gentler Streak App Store](https://apps.apple.com/us/app/gentler-streak-workout-tracker/id1576857102)
  - 当前最值得参考的“优雅方案”：底栏被收进一个轻柔的悬浮胶囊，选中项再嵌套一个低对比小胶囊，没有夸张凸起。
- `mobile-apps/komoot-map-action-bar.jpg`
  - 来源：[komoot App Store](https://apps.apple.com/us/app/komoot-hike-bike-run/id447374873)
  - 不是一级导航案例，但适合研究地图页底部操作与安全区的关系。

## 更新后的首选方向

相比整宽 Material 3 底栏，更优雅且仍然可靠的方案是：

- 使用 **内缩悬浮底栏**，左右距离屏幕边缘约 14–18dp。
- 底栏为暖白或半透明浅灰绿色连续表面，圆角约 24–28dp，使用细描边和很轻的阴影。
- 底栏主体高度约 68–72dp，下面再包含系统安全区；不要压缩触控区域。
- 儿童模式 3 项、家长模式 4 项，继续等宽排列并始终显示文字。
- 选中项使用浅绿色内嵌胶囊、深森林绿实心图标；未选中项保持安静但对比度充足。
- 录音不做凸出底栏的大圆按钮。可以让“录音”的选中胶囊稍宽或颜色稍强，但它仍然是一个目的地。
- 地图页和内容页可以延伸到底栏后方，但底栏必须保持可读，并对滚动内容预留底部空间。
