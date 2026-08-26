# 亲子游园指南视觉对照

- source visual truth: `mobile/design/park-guide-option-3-reference.png`
- implementation top screenshot: `mobile/design/qa/park-guide-final-top.png`
- implementation lower screenshot: `mobile/design/qa/park-guide-final-lower.png`
- full comparison: `mobile/design/qa/park-guide-qa-comparison.png`
- focused lower comparison: `mobile/design/qa/park-guide-qa-lower-comparison.png`
- source pixels: 852 × 1800，对应约 426 × 900 @2x
- implementation pixels: 1080 × 2400，Android 模拟器 420 dpi，对应约 411 × 914 logical px
- comparison normalization: source downsampled to 426 × 900；implementation removed 60 px system top inset、裁为 1080 × 2280 后缩放到 426 × 900
- state: 8–9岁、20–40分钟、都可以、轻松步行、无障碍关闭，线上试点数据加载完成

## Full-view comparison evidence

实现保持了参考图的湿地水彩首屏、暖米白纸面、墨绿信息层级、成长/时间自然刻度、兴趣插画带、路线插画和推荐缩略图。实现比参考图稍长，这是为了保留至少约 44 logical px 的触控区域和真实中文字号；内容可连续滚动，没有裁切核心操作。

## Focused-region comparison evidence

下半屏对照确认：兴趣、活动偏好、无障碍要求和推荐结果的层级与参考图一致。两个推荐公园使用不同实景插画；年龄、路线时长、建议时段和数据不足声明均保持可读。

## Required fidelity surfaces

- Fonts and typography: 延续应用现有中文无衬线字体，未照搬生成图中不可稳定跨平台复现的手写字形；标题、分组标题、正文和辅助说明层级清晰，无截断。
- Spacing and layout rhythm: 采用连续纸面和轻分隔线；比参考图略宽松以满足触控尺寸。圆角、边距和纵向节奏在上下屏一致。
- Colors and visual tokens: 使用现有 `#174936` 森林绿、`#F8F5EC` 米白、浅纸绿选中态和赭黄勾选，前景对比清楚。
- Image quality and asset fidelity: 首屏、成长、时间、兴趣、路线和三个公园缩略图均为独立生成并人工检查的真实 raster 资产；透明边缘、比例和裁切正常，没有占位图、代码绘图或拉伸。
- Copy and content: 年龄改为互不重叠范围；时间改为预算区间；无障碍从偏好拆为硬条件；推荐文案与筛选状态一致。

## Comparison history

### Pass 1 — blocked

- [P1] 年龄和时间选中态使用深绿大面积填充，遮挡植物/蝴蝶插画，并使选中文字对比不足。
- [P2] 所有推荐卡重复同一张湿地缩略图，削弱公园辨识度。

Fixes:

- 选中态改为浅纸绿色半透明底、森林绿描边和赭黄勾选。
- 为杭州植物园、太子湾公园和湿地分别生成独立缩略图，并按公园 ID 映射。

Post-fix evidence:

- `mobile/design/qa/park-guide-final-top.png`
- `mobile/design/qa/park-guide-final-lower.png`

### Pass 2 — passed

未发现仍需修复的 P0/P1/P2。参考图与实现的主要差异为实现纵向节奏更宽松，属于满足真实触控尺寸和可读性的有意约束。

## Interactions verified

- 年龄范围可切换；低于路线年龄下限时出现明确空状态。
- 时间、兴趣和活动偏好均为可点击的单选组件。
- 无障碍开关在模拟器中可用，开启后推荐数量由 2 变为 1。
- 推荐卡可进入公园详情及路线流程，相关 widget test 已覆盖。
- 上下滚动、网络加载、部分失败和重试状态均有测试覆盖。

## Follow-up P3 polish

- 后续若引入已获授权的跨平台中文展示字体，可进一步靠近参考图的自然手帐标题气质。
- 后端应补充正式的路线无障碍结构化字段，替换当前试点公园白名单。

final result: passed
