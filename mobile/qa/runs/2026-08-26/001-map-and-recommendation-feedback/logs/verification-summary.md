# 自动验证摘要

## 静态分析

```text
flutter analyze
No issues found.
```

## 定向测试

```text
flutter test \
  test/core/park_guide/park_recommendation_engine_test.dart \
  test/features/park_guide/park_guide_page_test.dart \
  test/features/community/soundscape_page_test.dart

13 tests passed.
```

## 全量测试

```text
flutter test
110 tests passed.
```

## Release构建

```text
flutter build apk --release --target-platform android-arm64 --split-per-abi
Built app-arm64-v8a-release.apk (56.4MB).
```
