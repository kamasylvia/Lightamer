# M4-3 RESEARCH-NOTES — IOP-MASK-07 Depth 蒙版（MiDaS 级单目深度 → CoreML）

> 起草：discuss/research subagent（2026-10-09）。配套裁决草案 = 同目录 `M4-3-CONTEXT.md`。
> 参考仓只读：Lumen RAW（MIT，`/Volumes/UNITEK/Documents/Development/lumen-raw`）；
> 本地无 Alcedo Depth 面（其深度蒙版非对标项）。代码不复制入库。
> ROADMAP M4-3 字面「MiDaS ONNX→CoreML 转换」——本文 research 结论：**REQUIREMENTS :367
> 「MiDaS 级单目深度模型」的最佳兑现 = Depth Anything V2 Small（MiDaS 直系后继）的
> Apple 官方 CoreML 转换件直采，自转换降为后手**（论证见 §2/§3）。

## 1. Lumen MiDaS 集成读解（参考锚）

Lumen 是本项的采纳来源（REQUIREMENTS :367 用户裁决 2026-10-01），其集成是
「ONNX Runtime + MiDaS v2.1 small + CPU 后处理」的完整先例，逐层读解如下。

### 1.1 模型资产与分发

- 模型选型：`lumen/selection.py:39-40` —— kind→模型映射 `{'foreground': 'midas-small.onnx'}`；
  Lumen 全部蒙版/AI 模型共用一个目录 `assets/models/`（`selection.py:41`，
  `Path(__file__).resolve().parents[1]/'assets/models'/filename`）。
- 模型本体**不入 git 仓**：`assets/models/` 只放 4 份 manifest JSON；
  MiDaS 来源登记在 `assets/models/v11-models.json:3-6` ——
  `source: https://github.com/isl-org/MiDaS/releases/download/v2_1/model-small.onnx`
  + `license: "MIT, Intel ISL MiDaS"` + sha256 锁定。
  打包时由 `tools/package_windows.py:39` 把 `midas-small.onnx` 放进发布包（内置分发，非运行时下载）。
- 许可归属：`THIRD_PARTY.md:24` ——「MiDaS v2.1 small 相对深度模型 | MIT，Intel ISL，
  https://github.com/isl-org/MiDaS；assets/MiDaS-LICENSE.txt」（license 文本随包）。
- 模型事实卡：`MODEL.md:54` —— 256×256 RGB、ImageNet 归一化、输出**相对逆深度**
  （越大越近）、「不是绝对距离测量」；官方 ONNX 直链 = v2_1 release。

### 1.2 推理输入工艺（`lumen/selection.py:59-68`）

- 输入尺寸：`size = 256 if kind == 'foreground'`（`selection.py:61`）——MiDaS v2 small 固定 256²。
- 预处理：`cv2.resize(..., INTER_AREA)` → float32；**归一化分叉**（`selection.py:63-65`）：
  `kind not in ('person','foreground')` 才做 max-归一化，MiDaS 腿直接走
  ImageNet mean/std（`[.485,.456,.406] / [.229,.224,.225]`，`selection.py:65`）。
- 张量排布：`x.transpose(2,0,1)[None]` = NCHW（`selection.py:66`）。
- 有效性守卫：`np.isfinite(prediction).all()` 不过 → 抛错（`selection.py:67-68`）。

### 1.3 深度 → 蒙版管线（`lumen/selection.py:69-74`，本项语义设计的正本）

```python
if kind=='foreground':
    # MiDaS predicts relative inverse depth: larger values are nearer.
    low,high=np.percentile(prediction,[10,95])                      # :71 抗离群分位归一化
    relative=np.clip((prediction-low)/max(float(high-low),1e-6),0,1) # :72
    prediction=np.clip((relative-.48)/.22,0,1)                       # :73 近景窗 [0.48, 0.70]
    prediction=prediction*prediction*(3-2*prediction)                # :74 smoothstep 软阈
```

四段固定语义：**分位归一化（10/95 percentiles，砍两端离群）→ 线性拉伸 [0,1] →
近景窗线性重映射（relative ≥ 0.48 起算前景，≥ 0.70 全前景）→ smoothstep 软过渡**。
全部纯函数、无状态、可 golden。背景蒙版 = 反选（`selection.py:76-77`：`background` kind
对 subject 分割输出 `alpha = 1-alpha`；深度腿的反选同理可由蒙版 invert 位承载，见 §5.2）。

### 1.4 边缘对齐：guided filter（`lumen/selection.py:45-56`）

- 9×9 box 分量 + epsilon 0.002 的 guided filter，以**全分辨率亮度**为引导图，
  把 256² 粗深度边界对齐到图像边缘（`selection.py:47-56`）。
- 动机：深度模型输出分辨率（256²）远低于图像，双线性上采样的边界糊；
  语义分割蒙版（U2NetP 320²）同样过这道 refine（`selection.py:75` 对所有 kind 统一）。
- Lumen 用 OpenCV CPU 实现；我方如采纳（OQ-5）需 Metal kernel 或 vDSP 自实现。

### 1.5 蒙版存储与羽化（`lumen/selection.py:9-13, 94-100`；`lumen/auto_masks.py:77-87`）

- raster encode：float [0,1] → uint8 PNG → base64 入工程文件（`selection.py:9-13`）；
  decode 尺寸门 1..2048（`selection.py:26`）。我方对应物 = RasterMaskRef 16-bit PNG
  旁挂（`.lra.masks/<maskID>.png` + StableHash，`LightamerCore/Sources/Layers/Masks/RasterMaskRef.swift`
  头注），我方通道更强（16-bit + 哈希校验），直接复用、不学 Lumen 的 base64 内嵌。
- 羽化：`feather/100 × min(h,w) × 0.008` 高斯半径（`selection.py:94-100`）；
  自动蒙版默认 `feather=10.`（`auto_masks.py:82`）。
- 空结果守卫：`(alpha>.5).mean() < .0003`（0.03%）→ 「没有识别到明确区域」提示，
  **不落蒙版**（`auto_masks.py:77-79`）——与 AIMaskError.noSubject 同型语义。
- 竞态防护：document token 比对（`auto_masks.py:56,75`）——切图后旧推理结果丢弃。
- 上限：32 蒙版/文档（`auto_masks.py:51-52`）。

### 1.6 推理进程隔离（`lumen/ai_worker.py`，M2AI-10 已平移）

- 长驻 worker + generation 重启：`ai_worker.py:147-214`（`Worker.start/stop/request`，
  超时 kill + `WorkerCrashed`）；超时预算 `OPEN_TIMEOUT=900 / RUN_TIMEOUT=600 /
  MAX_RETRIES=4`（`ai_worker.py:29-31`）。
- 崩溃记录：`CompatRecord`（`ai_worker.py:106-142`）—— 同一 EP 两个不同模型崩溃 →
  该 EP 全禁（`:132` `info['all'] = len(info['models']) >= 2`）。
  我方 M2-10 已按 D-M2-10-CONTEXT-6 平移为 `LightamerCore/Sources/AI/CompatRecord.swift`
  （`ai-compat.json`）。
- 性能参照（M1 Pro，`TEST_REPORT.md:21`）：MiDaS small 256² = CoreML GPU 12ms /
  CPU 41ms；转换一致性（CoreML vs ONNX CPU 参考）最大绝对误差 **2.3×10⁻³**
  （未归一化逆深度，`MODEL.md:9`）——Lumen 的 golden 门取值先例。
- 固定形状教训（`TEST_REPORT.md` 动态形状段）：DRUNet 动态宽高在 CoreML 无法生成
  执行计划（正确回退 CPU）、NAFNet 被拆 80 段 740ms 慢于 CPU——**按分块尺寸固定形状**
  后达标。与 M2-10 RESEARCH §1.5「flexible shapes 伤 ANE 兼容（coremltools#1764）→
  静态形状」互相印证。

## 2. 变体对比表（体积 / 精度 / 许可 / 转换路径）

| 候选 | 架构 | 参数 | CoreML F16 体积 | 输入 | 许可（权重） | 转换路径 | 质量世代 |
|---|---|---|---|---|---|---|---|
| **Depth Anything V2 Small**（Apple 官方件） | DPT + DINOv2 ViT-S | 24.8M | **49.8MB（官方实测包）** | 518×396 固定 | **Apache-2.0**（权重 HF 卡 + Apple 转换件双清） | **零转换：官方 mlpackage 直采** | 2024（NeurIPS 2024，62M 图训练） |
| MiDaS v2.1 small（Lumen 同款） | EfficientNet-Lite3 + 轻量解码 | ~21M | ≈40MB（fp32 ONNX 65MB → F16 估算） | 256² | MIT（Intel ISL） | ONNX→coremltools 自转换 | 2020（v2.1） |
| MiDaS 3.1（LeViT/Swin/BEiT 族） | ViT 族 | ~40-460M | 80MB-1GB+ | 384/512 | MIT | 自转换；ViT 高层算子 ANE 落格风险（§3.2） | 2022 |
| DA V2 Base / Large | DINOv2 ViT-B / ViT-L | 97.5M / 335M | ≈195MB / ≈670MB | 518² | Apache-2.0 | 自转换或社区件（无 Apple 官方件） | 更高（v1 蒙版场景用不到） |

关键事实：

1. **Depth Anything V2 是 MiDaS 直系后继**——Depth Anything V1 即在 MiDaS 框架上训练，
   V2 沿用 DPT 架构 + DINOv2 骨干（HKU + TikTok，NeurIPS 2024；595K 合成标注 +
   62M 真实未标注图）。REQUIREMENTS :367「MiDaS 级单目深度模型」语义 = 相对逆深度
   单目深度这一**级别**的模型，DA V2 完全落在此语义内且质量超 MiDaS v2 一个世代。
2. **Apple 官方 CoreML 转换件在册**：`apple/coreml-depth-anything-v2-small`
   （Hugging Face，apache-2.0）——
   - `DepthAnythingV2SmallF16.mlpackage` **49.8MB** / F32 99.2MB；
   - **ANE 实测延迟**：M3 Max 24.6ms、M1 Max 32.8ms（macOS 15）、iPhone 15 Pro Max 33.9ms；
   - 输入 518×396 固定形状（~4:3 拉伸，COCO 评测集口径）；
   - 转换质量官方数：F16 abs-rel **0.0089** vs F32 0.0072（参照 PyTorch CUDA F32）；
   - 配套 Swift 示例 = `huggingface/coreml-examples`（depth-anything-example）。
3. **HF 官方 ONNX 导出也在册**（`onnx-community/depth-anything-v2-small`）——
   若裁「自转换」（OQ-1 备选），ONNX 起点现成，不必从 PyTorch 导出。
4. Lumen 同款 MiDaS v2 small 的对照意义：体积更小（≈40MB F16）、2020 质量档、
   256² 输入更省算力，但深度边界质量明显低于 DA V2（DINOv2 骨干代差）；
   若走它则须自转换 + ANE 落格实测（EfficientNet-Lite 系 Swish/SiLU 激活在 ANE
   的支持要 spike 验证）。

## 3. 转换工艺（官方件直采 vs coremltools 自转换）

### 3.1 官方件直采（推荐路径）

- 载体：`DepthAnythingV2SmallF16.mlpackage`（目录形态 mlpackage，zip 后作为
  Release 资产分发；SHA-256 锁定，D-M2-10-CONTEXT-7 既有纪律）。
- 推理面：CoreML 原生 `MLModel`（`MLModelConfiguration.computeUnits` 走
  `AIComputeUnits` 既有三档映射，`LightamerCore/Sources/AI/AIWorkerProtocol.swift:44-54`）。
- 归一化注意：Apple 件输入为拉伸到 518×396 的图像（横纵比失真换取静态形状——
  与 Lumen 256² 拉伸同型；relative depth 对拉伸不敏感，蒙版用途上采样后无可见伪影，
  plan 阶段样张走查确认）。预处理/后处理（ImageNet 归一化、输出端 min-max）须按
  mlpackage 的 input/output feature 描述核对（官方件图内已含部分预处理——plan spike
  时以 F16 件 feature 元数据为准，不凭文档转抄）。
- 输出 = relative inverse depth float 图（518×396），语义与 MiDaS 输出同型 →
  §1.3 的 Lumen 四段管线原样适用（纯函数，模型无关）。

### 3.2 自转换后手（若官方件不可用 / 需换档）

继承 M2-10 RESEARCH §1.5 已核纪律：

- 路径：HF 权重 → ONNX（官方导出在册，DA V2 Small 用 `onnx-community` 件）→
  `coremltools.convert`（mlprogram，`compute_precision=ct.precision.FLOAT16`）
  → 静态形状导出。
- **ANE 兼容**：int8 权重 + fp16 激活普遍可跑；int8 激活量化需 A17 Pro/M4+；
  **flexible shapes 伤 ANE**（coremltools#1764）→ 一律静态形状（518×396 单组
  specialization = ANE 最优）；ViT 类（DINOv2/DPT）的 LayerNorm/GELU/attention
  matmul 在 ANE 可落格（Apple「Deploying Transformers on ANE」口径，且 Apple 官方件
  本身即为 ViT 族全 ANE 跑通的实证——其 benchmark 即 ANE 延迟）。
- **格式逆优化先例**：Real-ESRGAN mlprogram 实测慢于 neuralnetwork（coremltools#2545）
  → 若自转换，两格式 A/B（M2-10-CONTEXT OQ-3 spike 同款）。
- 转换脚本 = 构建期工具链（Python + uv，不在 app 内），产物进 Release——
  运行时零新依赖（ROADMAP M4-3 纪律行原文）。

## 4. 许可审计（逐项核）

| 资产 | 许可 | 分发影响 |
|---|---|---|
| Depth Anything V2 Small 权重（`depth-anything/Depth-Anything-V2-Small-hf`） | **Apache-2.0**（HF model card 标注；代码仓 MIT+Apache-2.0 混合，权重卡为准） | 开源分发干净；NOTICE 署名 Depth Anything 团队（HKU/TikTok） |
| Apple `coreml-depth-anything-v2-small` 转换件 | **apache-2.0**（HF repo 标注） | 可再分发；NOTICE 署名 Apple ML research / huggingface coreml-examples |
| `onnx-community/depth-anything-v2-small`（自转换起点的 ONNX） | Apache-2.0（社区导出，跟随上游） | 仅构建期用，不入库 |
| MiDaS v2.1 small（备选档） | MIT（Intel ISL，`THIRD_PARTY.md:24` 同源核） | 干净 |
| 转换工具链 coremltools | BSD-3-Clause（构建期） | 不随 app 分发，无影响 |

对照 M2AI-01 教训（MobileCLIP2 `apple-amlr` 许可翻转，M2-10-CONTEXT OQ-1）：
本项主档许可链**全 Apache-2.0、零自定义条款、零灰色**——比 CLIP 主档更干净。
资产随行件按 M3-3-01 五件套先例（`Resources/FilmProfiles/` = LICENSE + NOTICE +
MANIFEST.sha256 + CHANGELOG + 资产本体；`M3-3-01-DECISIONS.md` §2）：Release 档
以 zip 内随行 LICENSE/NOTICE + 仓内 manifest `licenseName` 字段（ModelAssetCatalog
既有面）承载。

## 5. 蒙版语义设计（深度图 → 蒙版）

### 5.1 生成管线（模型无关纯函数核）

```
源图（SDR 预览分辨率，sRGB 线性化后按模型归一化）
  → CoreML 前向（518×396 静态形状，ANE 25-33ms 级）
  → relative inverse depth float 平面
  → percentile [10,95] 归一化（Lumen selection.py:71-72 同参）
  → 近景窗重映射 (r−0.48)/0.22 + smoothstep（selection.py:73-74 同参）
  → 「近景」α 平面
  → 上采样到源分辨率（AIMaskResample 既有通道）
  → 烤 16-bit PNG 入 .lra.masks/（RasterMaskRef 既有通道）
```

- 四段后处理**全纯函数**（Core 级可单测 + golden）；参数（0.48/0.22 窗、10/95 分位）
  作为 v1 默认常量起点（OQ-4 裁是否暴露可调档）。
- 我方通道映射：**生成器产物 = raster asset**，与 AIMaskService「mask GENERATOR,
  not an iop slot」同构（AIMaskService.swift 头注）；蒙版消费走 IOP-MASK-03
  raster 通道 + IOP-MASK-04 组合五式（`MaskSpec.swift:218-223`）+ 任意调整层
  （IOP-MASK-05 既有）——**蒙版语义面零新机制**。

### 5.2 近/远选择与既有蒙版组合

- **远景 = 反选**：`RasterMaskRef.invert` 既有位（KD-7 raster-first）——
  近景蒙版 + invert = 远景，零新代码；UI「近景/背景」双入口 = subject+invert
  sugar 同款先例（M2MASK-05 AI Subject「主体以外」入口，REQUIREMENTS :68）。
- 与 AI Subject 互补：Subject（Vision layer A/B）= **语义对象**（是什么）；
  Depth = **几何近远**（在哪层）。互补场景 = 「只调背景不伤人物」在 Subject
  已覆盖；Depth 独有价值 = 无明确主体的场景分层（风光前景/天空倒退、静物台面）、
  与 Subject/画笔/渐变的组合（intersect 深度×渐变 = 「由近到远渐变虚化」类）。
- 有效性守卫：分位归一化后若 `high−low ≈ 0`（平坦深度，如纯色墙）→
  typed error（noSubject 同型：「未识别到明确深度分层」），不落蒙版
  （AIMaskTypes.swift:131-152 既有错误面 additive 一 case）。

### 5.3 边缘对齐裁度（OQ-5 输入）

Lumen 用 guided filter 把粗深度边界对齐全分辨率亮度（§1.4）。裁度选项：

- **v1 双线性上采样 + 既有羽化**（AIMaskResample 通道 + RasterMask 羽化）——
  深度本质是低频信号（不像分割蒙版有强语义边界），加上模型本身 518 级输入
  （比 Lumen 256² 细一倍），边界糊的可见度低；零新 kernel。
- v2 增强 = Metal guided filter kernel（新 .metal 文件对）——挂 V2，不为它阻塞 M4-3。

## 6. golden 策略

三件套（对齐 M2-7/M3-3 golden 先例形态）：

1. **转换精度门**：同一组固定输入（含真实 RAW 降采样样张 + 合成渐变深度靶图）
   过 F16 CoreML 件 vs 参考输出（F32 包或 Apple 公布的 abs-rel 参照），
   门 = abs-rel ≤ 0.01（Apple 官方 F16 自报 0.0089，留余量）+ max-abs 上限。
   Lumen 先例 = 转换一致性 max-abs 2.3×10⁻³（未归一化域，`MODEL.md:9`）；
   DA V2 输出域未归一化，门值 plan 阶段按实测分布钉死（比较纪律：L048——
   decode 回线性 + f32 产线常数升维）。
2. **确定性门**：同输入同 computeUnits 双跑逐字节一致（`gpuPinned` 测试 pin
   先例，AIMaskService AIDevicePolicy 注记：同设备 → byte-identical）；
   跨设备只验 abs-rel 门不验字节。
3. **蒙版语义 golden**：合成靶（近景矩形物体 + 远景背景，几何已知）→
   §5.1 四段管线全开 → 期望 α 平面 PNG golden（前景命中/背景零误伤/窗过渡带
   位置三断言）+ 平坦深度 → typed error 负测 + 近景窗参数扫描纯函数性测试。

## 7. 性能预算与运行面

- 前向：ANE 25-33ms（Apple 官方 M1 Max/M3 Max 实测，§2）；GPU/CPU 兜底走
  `AIComputeUnits` 三档。蒙版生成是**一次性后台任务**（非每帧路径），预算宽松。
- 上采样 + 烤盘：AIMaskResample 既有通道（M2-7 实测过 100MP 对齐），非瓶颈。
- 并发：编辑器 Metal 渲染循环零 await（AIMaskService「nonisolated async static +
  App 层 Task 启动」同款）；推理落位 OQ-3（worker vs in-process）。
- 触发：蒙版工具栏 Depth 入口 → 单图单次生成；模型未安装 → 入口置灰
  （`AIMaskError.modelNotReady` 同型，layer B 先例）。

## 8. 分发与资产链（ModelAssetCatalog additive）

- 新 profile（编译期 manifest，`ModelAssetCatalog.swift:80-90` 五 profile 目录
  additive 一条）：`profileID: "depth-anything-v2-small-f16"`、`modelID:
  "apple/coreml-depth-anything-v2-small"`（权重上游
  `depth-anything/Depth-Anything-V2-Small-hf` 记 revision）、`inputSize: 396`
  （短边；518×396 非正方形——`inputSize` 语义为「canonical square edge」，
  plan 时为 depth profile 放宽为「canonical edge pair」或记 518 长边 + 注记，
  typed 改法随 OQ-2 裁定）、`licenseName: "Apache-2.0"`、
  `tier: .gitHubRelease`（ROADMAP 字面；OQ-2 有内置翻转口）、
  `releaseTag` 沿 `ai-models-v1` 或追加资产到该 tag。
- 下载/校验/落盘：ModelAssetStore 既有链（SHA-256 + tmp 同卷 rename 原子晋升，
  `ModelLocator.swift:94-106`）零改动复用。
- 模型**不入仓**（ROADMAP M4-3 原文「不入仓，Resources/AIModels 同款纪律」；
  `Resources/AIModels/` 现状两 bundled profile 目录为「profile 目录形态」先例，
  Release 档不入此目录）。

## 9. Sources

### Lumen RAW（本地仓，MIT）
- `lumen/selection.py:36-78`（session 映射 / 输入工艺 / 深度→蒙版管线 / guided filter）
- `lumen/auto_masks.py:49-91`（UI 调用侧 / 空结果守卫 / 竞态防护）
- `lumen/ai_worker.py:29-31,106-142,147-214`（worker 隔离 / CompatRecord）
- `assets/models/v11-models.json:3-6`（midas-small 来源 + SHA-256）
- `MODEL.md:9,54`（模型事实卡 / 转换一致性数字）
- `TEST_REPORT.md:21`（M1 Pro 性能表 + 动态形状教训）
- `THIRD_PARTY.md:24`（MiDaS MIT 归属）

### 我方底座（file:line）
- `LightamerCore/Sources/AI/AIMaskService.swift`（layer A/B 头注 / L014 fence / 失败腿严格语义 / AIDevicePolicy）
- `LightamerCore/Sources/AI/AIMaskTypes.swift:131-152`（typed error 面）
- `LightamerCore/Sources/AI/ModelAssetCatalog.swift:12-16,80-90`（tier / 五 profile 目录）
- `LightamerCore/Sources/AI/ModelLocator.swift:94-106`（安装根 / tmp 原子晋升）
- `LightamerCore/Sources/AI/AIWorkerProtocol.swift:44-65`（computeUnits 三档 / AIWorkerOp）
- `LightamerCore/Sources/Layers/Masks/RasterMaskRef.swift`（16-bit PNG + StableHash + invert）
- `LightamerCore/Sources/Layers/Masks/MaskSpec.swift:218-223`（组合五式）
- `.work/gsd/REQUIREMENTS.md:367`（IOP-MASK-07 采纳条目）
- `.work/gsd/phases/m2-10-ai-library/M2-10-CONTEXT.md`（D-7 模型资产纪律 / OQ-3 转换 spike）
- `.work/gsd/phases/m2-10-ai-library/RESEARCH-NOTES.md §1.5`（coremltools/ANE 纪律）
- `.work/gsd/phases/m3-3-fsim/M3-3-01-DECISIONS.md §2`（资产五件套先例）

### Web
- apple/coreml-depth-anything-v2-small（HF，apache-2.0，F16 49.8MB，ANE benchmark）:
  https://huggingface.co/apple/coreml-depth-anything-v2-small
- huggingface/coreml-examples（Swift 示例）: https://github.com/huggingface/coreml-examples
- Depth-Anything-V2 仓（NeurIPS 2024，「integrated into Apple Core ML Models」）:
  https://github.com/DepthAnything/Depth-Anything-V2
- onnx-community/depth-anything-v2-small（官方 ONNX 导出）:
  https://huggingface.co/onnx-community/depth-anything-v2-small
- isl-org/MiDaS（v2.1 release，model-small.onnx）: https://github.com/isl-org/MiDaS
- Apple ML models 页（Depth Anything 在册）: https://developer.apple.com/machine-learning/models/
