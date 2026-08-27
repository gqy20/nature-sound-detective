# Repository Instructions

## 版本发布

- `mobile/pubspec.yaml` 是移动应用正式版本号的唯一来源。
- 不得只修改版本号而不完成发布；QA 批次号和普通 debug APK 不属于正式版本升级。
- 每次升级 `mobile/pubspec.yaml` 中的正式版本，必须在同一个发布任务中完成：
  1. 提交该版本的全部目标改动；
  2. 运行要求的测试并成功构建发布 APK；
  3. 创建与版本名完全一致的 Git Tag，例如 `version: 0.4.0+4001` 对应 Tag `0.4.0`；
  4. 推送发布提交和 Tag；
  5. 创建同名 GitHub Release；
  6. 上传 APK 和 SHA-256 校验文件。
- GitHub Release 可访问后，版本升级任务才算完成。Tag、Release 或产物缺少任意一项，都必须明确报告发布未完成。
- 工作区有未提交改动时不得打发布 Tag；已经发布的 Tag 不得移动、覆盖或复用。
- 未经用户明确要求，不得自行升级版本、创建 Tag、推送 Tag 或创建 GitHub Release。
- 具体步骤见 `docs/release-process.md`。

## 移动端验证

- 仓库根目录的 `Makefile` 是移动端本地命令的统一入口；优先使用 `make analyze`、`make test`、`make build`、`make verify` 和 `make release`，不再临时查找 Flutter SDK。`make format-check` 单独检查全局格式，避免验证时擅自格式化工作区里的其他改动。
- 移动端正式发布前至少运行 `make verify` 和 `make release`；`make release` 只负责验证并构建 release APK，不会自动修改版本、打 Tag、推送或创建 GitHub Release。
- 交互测试资料继续归档到 `mobile/qa/runs/YYYY-MM-DD/NNN-slug/`；QA 批次通过不等同于正式版本发布。
- 正式发布产物必须记录文件名、字节数和 SHA-256。
