# 移动端版本发布规则

## 核心原则

版本号、Git Tag 和 GitHub Release 必须一一对应。禁止出现“只更新 `pubspec.yaml`，但没有 Tag 和 Release”的情况。

版本唯一来源为：

```text
mobile/pubspec.yaml
```

例如：

```yaml
version: 0.4.0+4001
```

对应关系：

- 应用版本：`0.4.0`
- Android versionCode：`4001`
- Git Tag：`0.4.0`
- GitHub Release：`0.4.0`

`+4001` 是 Android 构建号，不写入 Tag。

## 什么时候升级版本

- 普通开发、debug APK 和 QA 批次：不升级正式版本，也不打 Tag。
- 修复和小范围界面优化：升级 patch，例如 `0.4.0` → `0.4.1`。
- 新功能或主要交互变化：升级 minor，例如 `0.3.1` → `0.4.0`。
- 只有准备正式发布时才修改 `mobile/pubspec.yaml`。

## 固定发布步骤

1. 确认本次发布范围，将 `CHANGELOG.md` 的 `[Unreleased]` 整理为目标版本，并更新 `mobile/pubspec.yaml`。
2. 确认工作区中的发布内容已经提交，且没有混入无关修改。
3. 在 `mobile/` 下执行：

   ```bash
   flutter pub get --enforce-lockfile
   flutter analyze
   flutter test
   flutter build apk --release --target-platform android-arm64 --split-per-abi
   ```

4. 记录 APK 的文件名、大小和 SHA-256。
5. 创建与应用版本一致的 Tag：

   ```bash
   git tag -a 0.4.0 -m "自然声探员 0.4.0"
   git push origin main
   git push origin 0.4.0
   ```

6. 创建同名 GitHub Release，并上传 APK 与校验文件。
7. 打开 Release 页面确认可以访问、版本正确、附件可以下载。

只有第 7 步完成后，才可以宣布该版本已经发布。

## 发布失败的处理

- 测试或构建失败：停止发布，不创建 Tag。
- Tag 已推送但 Release 失败：修复 Release，不修改或复用 Tag。
- 发现发布内容错误：提升到新版本修复，不移动已经公开的 Tag。
- 工作区不干净：先整理和提交，不在临时状态上打 Tag。

## 当前遗留状态

仓库目前只存在 `0.1.0` Tag。`mobile/pubspec.yaml` 已经是 `0.3.1+3002`，但没有对应的 `0.3.1` Tag 和 GitHub Release，属于历史遗漏。

不要把当前大量后续改动补发成 `0.3.1`。应在当前改动整理、测试和提交完成后，以新的正式版本发布，并从该版本开始严格执行本规则。
