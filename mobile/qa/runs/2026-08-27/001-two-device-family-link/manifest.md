# 双设备家庭陪伴联动

- Status: `PARTIAL`
- Date: `2026-08-27`
- Batch: `001`
- Branch: `main`
- Base commit: `3e774d5`
- Working tree dirty at creation: `true`

## Goal

验证两台设备的家庭陪伴联动：家长端创建临时会话，儿童端输入 6 位连接码，家长确认后只同步有序探索事件。家长端展示本地陪伴话术、探索时间线和共同任务；AI 生成必须由家长显式触发。

## Environment

- Device / emulator: Flutter widget renderer（本轮不启动问题较多的 Android 模拟器）
- Physical size: 390 x 844 logical pixels
- Density / logical viewport: test DPR 3.0 / 390 x 844
- App version / package: `0.3.1+3002` / `com.xykw.nature_sound_detective`
- APK: `mobile/build/app/outputs/flutter-apk/app-release.apk`

## Acceptance Points

- [x] 入口同时明确家长设备和儿童设备
- [x] 6 位码加入、家长确认、角色权限与会话结束
- [x] 儿童事件可排队补发，家长端会产生即时陪伴提示
- [x] AI 用量移至设置，夸奖话术不再显示“20次”
- [x] 连接码冲突、事件幂等、过期会话和断网队列有自动测试

## Steps And Evidence

| Step | Action | Expected | Screenshot / UI tree | Result |
|---:|---|---|---|---|
| 1 | 打开家庭设备联动 | 显示家长创建和儿童连接两个清晰入口 | `screenshots/01-family-link-entry.png` | PASS |
| 2 | 家长端收到“主动回听”事件 | 先显示可直接说的本地话术，再显示 AI 显式入口、任务和时间线 | `screenshots/02-parent-live-companion.png` | PASS |
| 3 | 打开陪伴设置 | 隐私边界和 AI 用量在设置中解释，不干扰夸奖语义 | `screenshots/03-companion-settings.png` | PASS |

## Automated Verification

- Static analysis: Flutter `No issues found`，见 `logs/flutter-analyze.txt`
- Targeted tests: 家庭联动、家长陪伴、记录持久化、模式切换均通过
- Full tests: Flutter 116 passed（后续新增设置定向测试 2 passed）；Python 163 passed
- Build: release APK 成功，见 `logs/flutter-build-release.txt` 和 `artifacts/apk-release.txt`

## Findings

代码、后端合约、权限、幂等、持久化和发布构建均通过。本轮的截图是可重复的 Flutter 交互渲染，不是设计稿。

## Blockers

尚未在两台真实 Android 设备上做端到端配对和弱网漫游验证；本轮按用户要求不再启动问题较多的模拟器。详见 `screenshots/CAPTURE_BLOCKED.md`。
