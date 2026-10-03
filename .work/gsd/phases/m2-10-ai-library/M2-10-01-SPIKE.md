# M2-10-01 SPIKE — 转换 A/B 实测报告

> 执行日期 2026-10-03（chain 7 = 首个端到端全绿链；产物 = `Resources/AIModels/`
> 内置资产 + `ModelAssetDigests.generated.swift` 重写）。复现：
> `Scripts/ai-models/build_default_bundle.sh`（README 步骤）。机器 = M4（本机
> macOS 27 直启），ComputeUnit.ALL 含 ANE 调度。

## ⓪ 首步：CLIP 输入尺寸实证【E4】

- HF `OFA-Sys/chinese-clip-vit-base-patch16` @ revision
  `36e679e65c2a2fead755ae21162091293ad37834`（hf-mirror API + raw config 双取）：
  `config.json → vision_config.image_size = 224`、`patch_size = 16`；
  `preprocessor_config.json → size = {height: 224, width: 224}`。
- **结论：224×224（ViT-B/16 官方输入）**——已固化
  `ModelAssetManifest.inputSize = 224`，02/03 一律读 manifest，禁字面复制。
  （checker E4 的「禁预写 256²」红线满足——256² 是 MobileCLIP2 的数字。）
- 文本 seq len = 52（官方 ONNX 导出默认），图内 L2-normalize 双塔收进（D-8）。

## ① Chinese-CLIP ViT-B/16 int8 延迟（20 次取中位，ms）

| leg | compute units | median ms |
|---|---|---|
| image 224² | ALL | 16.21 |
| image 224² | CPU | 14.92 |
| text 52 tok | ALL | 5.59 |
| text 52 tok | CPU | 5.25 |

- 体积实数：img 88MB + txt 103MB + vocab.txt 108KB = **≈191MB**（RESEARCH §6
  估算 ≈190MB 命中）。
- ALL ≈ CPU → int8 权重 + fp16 激活主要跑 CPU/ANE 混合，均为十毫秒级；查询
  文本编码 5.6ms ≪ <100ms 总目标（RESEARCH §5 复核成立）。1 万张导入批 =
  16.2ms × 1 万 ≈ 2.7 分钟后台（M2AI-07 异步必要性证实）。

## ② Real-ESRGAN x4plus 双格式 A/B（coremltools#2545 复测，256² tile，20 次中位）

| format | median ms |
|---|---|
| mlprogram | 62.83 |
| neuralnetwork | 62.35 |

- **结论：平级（差 0.8%，噪声带内）**——#2545 的「mlprogram 显著慢于
  neuralnetwork」在本机（torch 2.7.1 + coremltools 10.x + M4）**未复现**。
- **格式裁决：x4plus/general-x4v3/DRUNet 统一打包 mlprogram**（理由：与
  iOS18 deployment target 对齐、后续 int8 per-block 量化路线仅 mlprogram
  支持、两格式实测无延迟差；general-x4v3 已按 mlprogram 转换并内置，
  20.55ms/tile）。M2-10-06 实测若推翻此裁决，重转换成本 = 单脚本一次。
- 转换注意（#2545 之外的实测约束，脚本已内置）：
  - `convert_to: "neuralnetwork"` 与 `minimum_deployment_target ≥ iOS15`
    互斥 → nn 腿须用 legacy target（iOS13）；
  - `compute_precision` 仅 mlprogram 接受 → nn 腿 fp16 走
    `quantization_utils.quantize_weights(nbits: 16)` 后处理；
  - int8 per_block 量化要求 `minimum_deployment_target ≥ ct.target.iOS18`
    （macOS 27 地板下无兼容负担）。

## ③ 嵌入质量抽查（3 zh/en 查询对 × 3 合成结构图，人读判断）

| 查询 | best match | 得分 |
|---|---|---|
| `一只猫` / `a cat` | landscape | cat 0.322 / landscape 0.330 / car 0.319 |
| `一张风景照片` / `a landscape photo` | car | cat 0.346 / landscape 0.340 / car 0.348 |
| `一辆汽车` / `a car` | **car** | cat 0.332 / landscape 0.328 / car 0.332 |

- **诚实结论：inconclusive**——合成线稿（PIL 平色块几何图）CLIP 语义密度
  过低，余弦全部挤在 0.32-0.35 平票带；仅「汽车」查询排中。管线本身
  端到端验证成立（两塔前向 + 归一化 norm=1 + 余弦可算）。
- 真图相对序验证转 M2-10-02 的 golden 测试（真实照片 fixture，gitignored
  资产不入库）；本 spike 的质量门只作 sanity 非阈值断言（KD-2 原文）。

## 转换链工程事实（复现者须知）

- 环境 = `uv run --with "torch==2.7.*" --with transformers --with
  coremltools --with numpy --with pillow`（torch 钉 2.7.x = coremltools
  官方测试矩阵上限；2.14 实测 text 塔踩 `new_ones` 未实现 op）。
- CLIP 文本塔 mask = **展开 float32 [1,1,52,52]**（2D mask 走现代
  masking-function 管线 → `new_ones` 不可转换）；图内 `> 0.5` 转 bool。
- 链路首绿 = chain 7（此前 6 轮迭代：transformers 新版 get_*_features 返回
  对象改子模块组合、iOS18 target、nn 腿 legacy target、digest 哨兵名映射、
  字面量逗号）；全链耗时 ≈ 12 分钟（env 热）。
- digest（SHA-256，最终分发字节；目录 = canonical tree hash）：
  - `chinese-clip-vitb16-int8` primary 92,558,991 B `f3edaccb…7c7` + aux
    txt 108,474,128 B + vocab 109,540 B
  - `realesr-general-x4v3-fp16` primary 2,494,268 B `2f4838ec…a21`
  - Swift 侧经 `ModelAssetStore.artifactDigestHex` 在真实 app bundle 上
    互验通过（ModelAssetCatalogTests 资源门激活态 13/0/0）。
- Release 三档 digest 维持 nil（fail-closed，未上架）。
