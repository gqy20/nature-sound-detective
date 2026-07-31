# BirdNET 基线测试记录

> 测试日期：2026-07-28  
> 状态：E0 管线基线 v0.1  
> 结论范围：验证环境、模型加载、音频推理与 JSON 导出；不是正式准确率报告。

## 1. 环境

- 环境管理：uv 0.8.10；
- Python：3.11.11；
- BirdNET Python：0.2.16；
- 模型：BirdNET Acoustic 2.4；
- 后端：TensorFlow CPU；
- TensorFlow / TensorFlow-Intel：2.15.0；
- 系统：Windows x86-64。

依赖已写入 `pyproject.toml` 并生成 `uv.lock`。由于 PyPI 发布包尚未包含官方仓库文档提到的 ONNX extra，且最新 TensorFlow 依赖组合在 Windows 缺少对应 wheel，本轮固定使用 Python 3.11 与 TensorFlow 2.15.0。

## 2. 执行方式

```powershell
uv sync
uv run python ml/baseline/run_birdnet_baseline.py --max-per-class 1 --top-k 5
```

脚本从现有 `data/` 中按文件名弱标签选择乌鸫、白头鹎和珠颈斑鸠样本，运行 BirdNET 并生成 `artifacts/baseline/birdnet_baseline.json`。

## 3. 首轮结果

| 指标 | 结果 |
|---|---:|
| 样本数 | 3 |
| 弱标签进入全局 Top-1 | 1 |
| 弱标签进入全局 Top-3 | 1 |
| 任意结果中检出弱标签 | 1 |
| 平均单文件推理时间 | 84.677 秒 |

逐文件观察：

- 白头鹎：正确命中，最高置信度 0.965494；
- 乌鸫：未命中，需要人工确认文件中有效乌鸫叫声的区间和 BirdNET 分类名；
- 珠颈斑鸠：脚本误选到主标签为古铜色卷尾、珠颈斑鸠只在背景中的混合录音，因此不能作为珠颈斑鸠单源准确率样本。

首轮选择规则已修正：优先选择文件名同时包含目标科学名、且以 `XC` 开头的公开录音，避免把“背景里有目标物种”的文件当作单源样本。

修正样本选择后单独复测 XC1002930：BirdNET 将珠颈斑鸠识别为 `Streptopelia chinensis`，最高置信度 0.996310。项目数据使用 `Spilopelia chinensis`，二者为分类学名称差异；已在配置中增加 BirdNET 专用学名映射。复测报告保存在 `artifacts/baseline/birdnet_pearl_necked_dove.json`。原始复测汇总中的“未检出”是评估脚本未处理同物异名造成的假阴性，不是模型漏检。

## 4. 当前可以确认的结论

1. uv 管理的 Python 3.11 环境可在 Windows 上稳定导入 BirdNET 与 TensorFlow；
2. BirdNET 2.4 模型能够自动下载、加载并对 WAV/MP3 完成推理；
3. BirdNET 0.2.16 实际返回 `AcousticFilePredictionResult`，需要调用 `to_dataframe()`，不能完全照搬 README 中把返回值直接视为 DataFrame 的写法；
4. JSON 结果导出链路已经跑通；
5. 直接处理数分钟原始录音的 CPU 耗时不适合作为在线接口，产品端必须限制为 5–15 秒；
6. 文件名只能作为弱标签，正式准确率必须建立人工确认的有效片段测试集。
7. 模型标签必须经过分类学同物异名映射，不能只做字符串完全匹配。

## 5. 下一轮 E0 测试

- [ ] 每个核心鸟类准备至少 5 条人工确认的 5–15 秒片段；
- [ ] 单独建立背景/unknown 测试集；
- [ ] 加入杭州经纬度和第 31 周的地理季节先验对照；
- [ ] 统计逐类 precision、recall、F1，而不是只看全局 Top-3；
- [ ] 对比完整类别输出和杭州候选类别过滤；
- [ ] 保存每条样本的许可、原始文件、裁剪区间和审核人。
