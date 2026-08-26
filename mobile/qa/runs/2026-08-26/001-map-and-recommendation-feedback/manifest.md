# 地图全屏与推荐反馈优化

- Status: `PARTIAL`
- Date: `2026-08-26`
- Batch: `001`
- Branch: `main`
- Base commit: `3e774d5`
- Working tree dirty at creation: `true`

## Goal

验证“共听杭州”地图全屏交互和“亲子游园指南”推荐变化反馈：地图应有可发现的全屏入口、缩放/复位控制和城区返回；筛选变化应改变排序并让用户看见更新状态、变化原因和结果入口。

## Environment

- Device / emulator: Android `Resizable_Experimental` AVD（截图采集阻塞）
- Physical size: `1080 × 2400`
- Density / logical viewport: `420 dpi`，约 `411 × 914 logical px`
- App version / package: `0.3.1+3002` / `com.xykw.nature_sound_detective`
- APK: `mobile/build/app/outputs/flutter-apk/app-arm64-v8a-release.apk`

## Acceptance Points

- [x] 代码入口状态与组件参考
- [x] 核心交互自动测试
- [x] 结果或返回状态自动测试
- [x] 空状态 / 错误恢复自动测试
- [ ] 当前实现真实运行截图

## Steps And Evidence

| Step | Action | Expected | Screenshot / UI tree | Result |
|---:|---|---|---|---|
| 1 | 查看内嵌杭州地图 | 显示“仅显示区域”和全屏按钮 | `references/soundscape-inline-map.png` | 参考完成；实机截图阻塞 |
| 2 | 打开全屏地图 | 支持缩放、平移、双击、加减和复位 | `references/soundscape-fullscreen-map.png` | Widget test通过；实机截图阻塞 |
| 3 | 选择城区并返回 | 返回后筛选对应城区声音 | Widget test断言 | PASS |
| 4 | 修改游园筛选 | 显示“推荐已更新”、条件摘要和变化原因 | `references/park-guide-live-feedback.png` | Widget test通过；实机截图阻塞 |
| 5 | 点击底部推荐栏 | 滚动至推荐结果；无匹配时返回条件区域 | Widget test断言 | PASS |

## Automated Verification

- Static analysis: `flutter analyze`，无问题
- Targeted tests: 地图、推荐引擎和游园页面共13项通过
- Full tests: `flutter test`，110项通过
- Build: arm64 Release成功，56.4 MB

## Findings

- 推荐引擎此前把公园、分区和路线标签合并成布尔匹配，多个选项容易得到相同分数；现已改为路线优先的分级权重。
- “完整路线”此前为所有存在路线的公园统一加分，无法改变排序；现按路线距离分别加权。
- 结果数量不变时用户无法感知更新；现增加更新状态、条件摘要、首位变化原因、列表动画和固定结果栏。

## Blockers

Android AVD 在当前主机上出现 `System UI isn't responding` 和 Flutter native status 11，无法接受为真实截图证据。已记录在 `screenshots/CAPTURE_BLOCKED.md`；本批次因此保持 `PARTIAL`，不能标记为 `PASS`。
