# Phase 7 Research: AI Modules (Native Vision Masking & Retouching)

**Researched:** 2026-09-26
**Confidence 汇总：** Apple Vision API 面 = High（**本机 macOS 27 SDK swiftinterface + Vision.tbd 逐符号实证** + Apple 文档 md data 端点可用性元数据核对，双源一致；WWDC26/237 transcript 逐段核过）；Phase 6 消费端接口 = High（`Layers/Masks/`、`RasterMaskStore`、`LayerCompositeDriver`、`MaskCombiner` 现码逐文件核，移交清单 06-DISCUSSION-LOG 终节对齐）；频率分离数学 = High（GaussianBlur/Highpass/Soften/Bilateral 既有件源码核过，频率分离为经典 Photoshop 技法、数学自封闭可 float64 参考）；Vision 推理耗时/精度 = **Med**（文档无官方数字，macOS 27 系新 API beta 期行为待 plan 期 benchmark 钉；确定性口径已给出可测方案）；skinSmooth 槽位裁决 = Med（V50Order 为 dt verbatim 表，插入非 dt 行是本项目首例，需 planner 拍板）。

---

## Summary

Phase 7 = 4 个需求（AI-01/05/06/07），全项目最小的功能阶段，但它是**第一个消费 Apple ML 推理的阶段**——与 Phase 2-6 的"纯确定性像素数学"范式分界。核心结论：

1. **两层主体蒙版 API（§1）**：全自动 class-agnostic = `VNGenerateForegroundInstanceMaskRequest`（macOS 14+，OS 内置模型、无下载前置）；交互式精修 = `GenerateIterativeSegmentationRequest`（macOS 27+，WWDC26/237 tap-to-segment，`seedPoint/seedBox/seedScribbleBuffer` 三种种子 + `addIncludedPoint/addExcludedPoint` 迭代精修，点数上限 13/11，**遵守 `DownloadableAssetsRequest`——首次使用需模型下载**）。两者输出互补：前者给 instance 集合（可勾选子集），后者给点击处连通主体的高/低清 mask。ROADMAP SC#1 的 "iterative tap/scribble/lasso refinement" 正是后者（macOS 27 floor 直接命中）。
2. **磨皮 = 频率分离 iop + Vision 定位（§2）**：**Core Image 无皮肤平滑滤镜**（`CISmoothLinearGradientSkinTone` 类 API 不存在，已查证；Apple 无内置 skin-smoothing CIFilter）——AI-05 的实现正解 = 新 `skinSmooth` Metal iop（两频分离：`GaussianBlur` Deriche IIR 既有件作 low 腿 + 新阈值式高频衰减 kernel，"压斑点不压毛孔"防塑料感）+ Vision 人脸地标/人体分割驱动的空间限定（`VNDetectFaceLandmarksRequest` 地标集 → face hull − 五官保护区 ⊗ `VNGeneratePersonSegmentationRequest` 人体 matte）。darktable 无 AI 磨皮先例（`channelmixerrgb.c:1796-1797` 的 skin hue 1.0 rad 只是 solver 权重），但 soften/highpass/lowpass 模糊族是我们的数学基座。
3. **AI mask 消费主通道 = raster 烘焙（§3）**：Phase 6 移交面**零改动即可承接**——`RasterMaskStore.bake(plane:directory:fileName:invert:metal:)`（`RasterMaskStore.swift:74`）接受任意 r32Float 平面，AI mask 生成后直接 bake 成 `.lra.masks/<maskID>.png`（16-bit 灰度）+ `RasterMaskRef` 引用，**继承全部 Phase 6 能力**：StableHash 校验、三失败腿降级、per-scale resample、invert、与 drawn/parametric 的 combine（`MaskCombiner.effectivePlane` 三 payload 装配）。"直接作为 parametric mask"（REQUIREMENTS AI-06 措辞）的工程正解：Vision mask 是**像素**不是参数曲线，v1 唯一可落通道是 raster；parametric 腿的 AI 用途只能是从地标拟合的语义曲线预设（可选增强，OQ3）。
4. **非黑箱 = 生成即 bake + 全套蒙版编辑（§4）**：AI 输出永不以黑盒引用存在——生成瞬间落为 raster PNG（数据资产，可版本化可校验），之后 (a) drawn 笔画 union/difference 修补（`MaskGroupItem` combine 既有）、(b) parametric ⊓ 收紧、(c) invert、(d) 羽化重 bake、(e) refine 点重生成，五条用户覆盖路径全部复用 Phase 6 机制，**Phase 7 不需要发明任何新蒙版编辑原语**。缺件仅一处：raster 腿的**羽化**（bake 管线内的单通道 mask blur——`MaskPostProcessKernels` 已有同款 kernel，接到 bake 入口即可）。
5. **性能（§5）**：Vision 推理走后台 Task（ANE 优先，`setComputeDevice(MLComputeDevice?, for: ComputeStage)` + `supportedComputeStageDevices` macOS 27 实证可枚举可 pin），与 Metal pipe **无帧内耦合**（PERF-1 的对策：推理是"生成蒙版"按钮的一次性动作，不是拖动热路径）；mask bake 一次即持久缓存（旁挂 PNG 本身就是推理缓存，SC#5 "re-edit 不重跑 Vision" 天然满足）；100MP 输入 Vision 内部下采样（模型输入远小于全分辨率），瓶颈在 bake 读回（r32Float 全幅 ~400MB → 分块可行）。
6. **验证策略（§6）——L017 分流的 AI 变体**：AI 输出**无 dt 对照、不可逐字节 golden**；替代口径 = (a) 确定性门（同输入同 device 两次推理 mask 逐字节恒等 + 测试 pin CPU device 保跨机器稳定）、(b) 合成语义门（纯背景+居中几何主体合成图 → IoU 阈值断言；合成人脸 → 地标 bbox 容差断言）、(c) 频率分离数学 float64 parity（<1e-5，03/06 定式）+ 恒等三元组（amount 0 逐字节 / mask 空 no-op / 平场恒等）。GUI 验收：生成蒙版 overlay 截图量化（06-03 ΔR 模式）+ 磨皮前后人像目检（Manual-Only）。
7. **v50 槽位（§7）**：AI-01 主体隔离 = **mask 生成器服务，不占 iop 槽**（产出 raster 资产，不是像素变换）；AI-05 磨皮 = **像素变换必须占槽**——推荐 `skinSmooth` 新行 66.5（soften 66.0 与 splittoning 67.0 之间，模糊/creative 族邻域；V50Order 表加非 dt 原生行是首例，表头注释标记）。
8. **plan 拆分建议 3 个**（§Plan）：07-1 Vision 基建 + AI-01 主体隔离（AIMaskService + bake 管线 + 确定性/语义测试 + assetStatus 处理）→ 07-2 skinSmooth 频率分离 iop（kernel 对 + skin mask 生成 + parity + 面板）→ 07-3 AI-06/07 集成精修与 GUI 签核（tap-to-segment 视口交互 + instance 勾选 + 羽化/combine + PLAYBOOK 验收轮）。总量 ~15-19 T。依赖序：07-1 →（07-2 依赖 07-1 的 AIMaskService 皮肤腿）→ 07-3。
9. **执行纪律增量**：本阶段起 AGENTS.md 暂停机制生效（`.work/PAUSE` + 任务边界检查 + C 档门控三点停）；omp 执行模型照旧（L019b 直启单测 + L022 零写入）。**研究定稿后即 C 档门控第 1 停**——本文 Open Questions 6 项需用户过目。
10. **最大风险 = 离线声明与模型下载的矛盾（OQ1）**：ROADMAP SC#5 写 "All AI detection runs locally on the Neural Engine (offline, no network)"，但 `GenerateIterativeSegmentationRequest` 遵守 `DownloadableAssetsRequest`（`assetStatus` + `downloadAssets()`，SDK 接口 `:1704-1706` 实证）——首次 tap-to-segment 需联网拉模型（一次性，之后本地）。`VNGenerateForegroundInstanceMaskRequest` / person segmentation / face landmarks 均为 OS 内置无此问题。处置建议：双后端 + 自动回落 + 首启预下载提示（OQ1 详述）。

---

## Implementation Approaches

### 1. AI-01 主体隔离（subject isolation）

#### 1.1 API 双层实证（本机 SDK + 文档双源）

**层 A：全自动 class-agnostic——`VNGenerateForegroundInstanceMaskRequest`**

| 面 | 实证 |
|---|---|
| 可用性 | macOS 14.0+ / iOS 17.0+（文档 availability 元数据；macOS 27 floor 直接命中） |
| 输入 | `VNImageRequestHandler(ciImage/cvPixelBuffer/cgImage/url/data:orientation:)` 或 Swift `perform(on: CIImage, orientation:)`（SDK interface `:615-620`） |
| 输出 | `results: [VNInstanceMaskObservation]`——`allInstances: IndexSet`（除背景外全部 instance）、`instanceMask: CVPixelBuffer`（**低分辨率**全 instance 标号 mask）、`generateMask(forInstances:)`（低清单子集 mask）、`generateScaledMaskForImage(forInstances:from:)`（**高分辨率** mask，需保留 handler）、`generateMaskedImage(ofInstances:from:croppedToInstancesExtent:)`（ matte 图，我们不用——要 mask 不要抠图） |
| 语义 | "noticeable objects to separate from the background"，class-agnostic（人/动物/食物/物体），任意 demosaic 后图像（**不限 ProRAW**——这是它区别于 `CIRAWFilter.semanticSegmentationSkyMatteImage` 的关键，L004） |
| 模型 | OS 内置（不遵守 DownloadableAssetsRequest，无下载前置） |
| URL | https://developer.apple.com/documentation/vision/vngenerateforegroundinstancemaskrequest |

**层 B：交互式 tap-to-segment——`GenerateIterativeSegmentationRequest`（macOS 27 新，WWDC26/237）**

SDK swiftinterface（`Vision.swiftmodule/arm64e-apple-macos.swiftinterface:1700-1766`）逐符号实证：

```swift
@available(macOS 27.0, *)
final class GenerateIterativeSegmentationRequest : ImageProcessingRequest, DownloadableAssetsRequest {
    var assetStatus: DownloadableAssetsRequestStatus { get async }      // :1704
    func downloadAssets(progress: consuming Subprogress) async throws   // :1705
    typealias Result = PixelBufferObservation?                          // 灰度 mask；nil = 无可分割物
    enum Revision { case revision1 }
    enum QualityLevel { case accurate, balanced, fast }                 // 控制 mask 分辨率
    init(seedPoint: NormalizedPoint, _ revision: Revision? = nil)       // :1737
    init(seedBox: NormalizedRect, _ revision: Revision? = nil)
    init(seedScribbleBuffer: CVReadOnlyPixelBuffer, _ revision: Revision? = nil)
    var regionOfInterest: NormalizedRect                                 // ROI 门
    func addIncludedPoint(_ point: NormalizedPoint) throws               // 点数上限：point/scribble 种子 13、box 种子 11
    func addExcludedPoint(_ point: NormalizedPoint) throws
    var qualityLevel: QualityLevel
    func setComputeDevice(_ computeDevice: MLComputeDevice?, for computeStage: ComputeStage)
    var supportedComputeStageDevices: [ComputeStage : [MLComputeDevice]]
}
```

- WWDC26/237 "What's new in image understanding"（https://developer.apple.com/videos/play/wwdc2026/237）transcript 实证要点：tap 点击即隔离；**lasso 线宽 ≥ 图宽 1%**（细线效果差）；scribble 可一次圈多物；mask 生成后 add 点**重跑同一 request** 即精修（含/排点）；**首次使用前必须下载模型**（`downloadAssets` API + `assetStatus` 检查）。
- **坐标系**：Vision 归一化坐标**原点左下**（transcript 原话 "coordinate origin in the lower left hand corner"，值域 0..1）。对 mask **buffer** 无影响（CVPixelBuffer 与输入像素对齐，行 0 = 图顶）；对**交互传点**有影响——视口 y 向下，seedPoint/addPoint 需 Y 翻转（`y_vision = 1 − y_view_norm`）。
- 配套：`VNGeneratePersonInstanceMaskRequest`（macOS 14+，**仅人**的 per-instance mask）——人像工作流可作层 A 的人体子集替代，v1 不必接（层 A 已覆盖人，instance 区分够用）。

#### 1.2 烘焙管线（AI mask → RasterMaskRef）

```
解码帧(demosaic 后、无编辑) ──fence(L014)──▶ CVPixelBuffer/CIImage
   │
   ▼  AIMaskService.generate(frame, seeds?)          [后台 Task, ANE]
VNInstanceMaskObservation / PixelBufferObservation
   │  generateScaledMaskForImage → 原分辨率灰度 CVPixelBuffer
   ▼  mask 上整形（上采样质量 + 羽化 + 可选 invert）
r32Float mask 平面（解码帧分辨率）
   │
   ▼  RasterMaskStore.bake(plane:directory:fileName:invert:metal:)   ← Phase 6 现成，零改动
RasterMaskRef { fileName, maskHash(StableHash PNG bytes), invert } → MaskSpec.raster
   │
   ▼  MaskCombiner.effectivePlane（三 payload ⊗ 装配 + per-scale resample）
LayerCompositeDriver mask 腿 → blendop 合成
```

裁决与要点：

- **推理输入 = 解码帧（无编辑）**：mask 语义内容锚定（蒙版贴的是"照片里的主体"，不是"当前调整后的主体"）；与 Phase 6 内容锚定坐标系（`MaskSpec.swift:7-11`，dt 归一化全解码帧坐标）同构。用户在编辑中途生成蒙版，编辑不污染 mask 源。
- **分辨率对齐**：`generateScaledMaskForImage` 直接产**原分辨率**高清 mask（首选，省一步上采样）；层 B 的 `PixelBufferObservation` 分辨率由 `qualityLevel` 决定（文档：controls the resolution of the produced mask）——`.accurate` 起步。若仍低于解码帧，走双线性上采样（**不用 nearest**——`RasterMaskStore.load:129-132` 的 per-scale resample 是 nearest v1 口径，对 AI 软边缘 mask 会块状化；bake 入口的上采样单独走双线性，OQ 范围内由 plan 钉 kernel）。
- **羽化**：bake 前对 mask 平面跑单通道 Gaussian（`LightamerIOP/Sources/Masks/MaskPostProcessKernels.metal` 已有同款 kernel；半径 = AI 面板滑块 0..N px）。这是 raster 腿唯一的 Phase 7 增件（§4）。
- **版本化**：每次生成/精修 = 新 PNG 文件（文件名 = `<maskID>.png`，同 maskID 覆盖重 bake；`RasterMaskRef.maskHash` 随之变化 → `MaskSpec.stableHash()` 派生哈希变 → mask plane 缓存与前缀链正确失效——Phase 6 机制自动接管，**不新增缓存类**，对齐移交清单第 4 条"推理结果 = 一条 maskPlane 级产物"）。
- **失败腿**（与 raster 降级语义区分）：层 A/B 推理失败/`nil` observation/模型未下载 → **UI 报错 + 不落 mask**（不是全一平面——那是 load 失败的降级语义，生成失败的降级会静默毁掉蒙版语义）；模型未下载态 = 按钮禁用 + 下载入口（§5 assetStatus）。
- **多主体**：层 A `allInstances` 多 instance → UI 勾选子集 → `generateMask(forInstances:)` 合成单 mask bake；层 B 天然单主体（点击处连通域）。

#### 1.3 层 A/B 分工

| 场景 | 用层 | 理由 |
|---|---|---|
| 一键"选中主体"（背景虚化/局部调整打底） | A | 无交互、class-agnostic、多主体可勾选 |
| 主体边界差一点（手/发丝/枝叶） | B refine | tap 含/排点迭代，SC#1 的 "usable interactively" |
| 只想要画面某物（非"前景主体"） | B | A 是"前景显著性"，B 是"点击处连通物" |
| 完全离线（未下载模型） | A | B 需模型下载（OQ1） |

### 2. AI-05 频率分离磨皮（skinSmooth）

#### 2.1 数学形态（v1 推荐两频 + 阈值式高频衰减）

经典频率分离（Photoshop 技法，dt 生态无专用模块、由 soften/highpass 手工组合）：

```
low  = GaussianBlur(I, σ_spatial)          ← 既有件：GaussianBlur（Deriche IIR，Common/GaussianBlur.swift）
high = I − low                              ← 分离
out  = low + attenuate(high) · (1 − m·a) …  ← 新 kernel
```

**防塑料感的关键 = 阈值式高频衰减（detail-preserving）**：纯低通替换（`out = low + high·(1−m·a)`）会把毛孔/发丝/边缘一起压掉 = 塑料。衰减函数按 |high| 分段：

```
attenuate(h) = |h| ≤ t ? h·(1 − m·a)·k_soft      // 低幅高频（色斑/噪点）→ 强衰减
                       : h                        // 高幅高频（毛孔边缘/发丝/轮廓）→ 原样保留
```

- `σ_spatial`：低频半径（斑点尺度，典型 4-12px @PREVIEW 等效，dt soften/highpass 的 σ 链公式可援引 `highpass.c:140`：σ = √((r(r+1)8+2)/3)）。
- `t`：高频保护阈值（"保细节"滑块）；`a`：强度；`m`：skin mask 平面（§2.2）。
- **色彩处理**：在 linear Rec2020 RGB 上做分解（频率分离对三通道独立分解，色斑 = 低频色差，经低频腿保留、不被磨掉——这正是频率分离优于"直接磨皮 blur+mask"的点）；衰减只作用于幅值。备选：分解在 luma、色度分离处理（Y 通道衰减 + C 通道轻度低通）——v1 先全 RGB 分解（与 soften 同域，`SoftenModule.swift:24-25` 注释钉的 RGB linear 先例）。
- **多频（小波多尺度）defer v2**（OQ6）：两频是 Photoshop 对标基线，多频是 dt diffuse 式进阶，v1 不背。

#### 2.2 皮肤区域限定（Vision 驱动 → 自动蒙版 → 可编辑）

```
VNDetectFaceLandmarksRequest（rev3/rev4 macOS 27）
  └─ per-face VNFaceObservation.landmarks: VNFaceLandmarks2D
       faceContour（脸缘闭合折线）/ outerLips / nose / leftEye·rightEye /
       leftEyebrow·rightEyebrow / noseCrest / medianLine / pupils
       （坐标 = face boundingBox 归一化、原点左下；VNImagePointForFaceLandmarkPoint 换算到图坐标）
  ├─ skin_hull = faceContour 多边形外扩（额头上缘补齐 = 眉毛上缘−faceContour 顶点带状闭合）
  ├─ protect   = eyes ∪ brows ∪ outerLips ∪ nostrils（各 region 折线内缩 buffer）
  └─ face_mask = hull − protect（CPU 解析几何，纯 Swift 可单测）
⊗ VNGeneratePersonSegmentationRequest（qualityLevel .accurate）
  └─ person matte（人体范围，排除背景中与肤色同调的木质/沙岩）
= skin_mask = face_mask ⊗ person_matte → Gaussian 羽化 → bake RasterMaskRef
```

- **地标集实证**（文档 Topics 逐条）：`VNFaceLandmarks2D` 暴露 allPoints/faceContour/leftEye/rightEye/leftEyebrow/rightEyebrow/nose/noseCrest/medianLine/outerLips/innerLips/leftPupil/rightPupil（https://developer.apple.com/documentation/vision/vnfacelandmarks2d）。Swift 版 `DetectFaceLandmarksRequest`（rev3 + **rev4 macOS 27**）+ `FaceObservation`（roll/yaw/pitch + captureQuality，SDK interface `:844-876/:2193-2210`）。
- **hull 几何是纯 Swift 解析**（点列 → 多边形 buffer → 布尔差）——**不依赖模型输出质量即可单测**（合成点列恒等断言，§6）；Vision 只供点列。
- **侧脸/多人脸**：results 数组逐脸处理取 union；roll/yaw/pitch 超阈值（如 |yaw| > 45°）的脸可标记"地标可信度低"→ UI 提示（不静默给坏 mask）。
- **蒙版 = 自动生成 → 落入蒙版编辑器（AI-07 原则）**：skin_mask bake 为该调整层 mask 的 raster 腿后，用户可 draw 修补（手背/腿露肤处 union 一笔）、parametric ⊓ 收紧、羽化重 bake——与 §4 同一套机制。
- **皮肤色调 parametric 补充（可选）**：dt `channelmixerrgb.c:1796-1797` 的皮肤 hue 角参考（均值 1.0 rad、范围 [0.75, 1.25]）可换算为 JzCzhz hz 通道 4 点曲线预设，作为 parametric 腿的"肤色范围"AI 预设（与 raster skin_mask ⊓ 交叠加收紧）——v1 可选项（OQ3）。

#### 2.3 既有件盘点（频率分离基座）

| 件 | 位置 | 复用方式 |
|---|---|---|
| `GaussianBlur`（Deriche IIR 双 pass + 双缓冲平面，L018 合规） | `LightamerIOP/Sources/Common/GaussianBlur.swift` + `GaussianBlurKernels.metal` | low 腿直接复用（σ 链援引 dt） |
| `HighpassModule`（invert→blur→CL mix，Lab 域） | `LightamerIOP/Sources/Highpass/` | **不复用实现**（Lab 域 + invert 语义不符），但 σ/halo 公式与"分解→mix"结构是直接参照（`HighpassModule.swift:19-21,134-149`） |
| `SoftenModule`（overexposed→blur→linear blend，RGB linear） | `LightamerIOP/Sources/Soften/` | mix 公式与 ROI halo 先例（`SoftenModule.swift:27-30`：`out = amt·blurred + (1−amt)·in`） |
| `BilateralModule` + `BilateralGrid3D`（边缘感知） | `LightamerIOP/Sources/Bilateral/` + `Common/BilateralGrid3D.swift` | 可选高配腿（edge-aware 低通替代纯高斯，保边缘更强）；v1 两频高斯起步，bilateral 变体留扩展位 |
| `ShadhiModule` | `LightamerIOP/Sources/Shadhi/` | 不直接相关（shadows/highlights），列作模糊族邻域参考 |

skinSmooth 新增 = 一对 kernel（`SkinSmoothKernels.metal`：`skin_split`（low/high 分解，或直接调 GaussianBlur 后一减）+ `skin_mix`（阈值衰减 + mask 合成））+ `SkinSmoothModule.swift`（参数面：radius/σ、strength a、detail-preserve t、mask 来源引用层 mask）+ skin mask 生成服务（§2.2 CPU 几何 + Vision 调用）。

### 3. AI-06 蒙版系统接入（三条通道）

Phase 6 移交清单（06-DISCUSSION-LOG 终节）逐条对位：

| 移交面 | Phase 6 现码 | Phase 7 接法 |
|---|---|---|
| raster 烘焙入口 | `RasterMaskRef`（`.lra.masks/<id>.png` 16-bit + StableHash 校验）+ `RasterMaskStore.bake`（`RasterMaskStore.swift:74-101`） | **主通道**。AIMaskService 产出 r32Float 平面 → bake → `MaskSpec.raster`。零改动（bake 入口本就接受任意 r32Float 平面） |
| parametric 输入 | `MaskSpec.parametric`（`ParametricMask`：luma/JzCzhz 通道槽位 verbatim dt + 4 点曲线 + 后处理链，`ParametricMask.swift:34-100`） | **可选通道**。AI 只能产出"语义曲线预设"（如 §2.2 肤色 hz 曲线），像素 mask 无法表达为 parametric——v1 主推 raster，parametric 预设作增强（OQ3） |
| 版本化 | `MaskSpec.stableHash()`（canonical sortedKeys JSON ⊕ StableHash，派生不持久）+ `version: Int`（NDE-3）+ optional additive 字段先例（drawn→parametric→raster 三步） | AI mask 的迭代精修 = 重 bake（同 maskID 新 PNG 新 hash）→ stableHash 自然翻转 → mask plane/前缀缓存链正确失效。**无需新机制** |
| 层栈 API 面 | `LayerStack`（add/replaceAny/remove/reorder/duplicate/mergeDown）+ `LayerCompositeDriver.composite`（kind 分派）+ history 双轨（layerScope 参数项 / `__layerStack__` 结构项） | AI 生成蒙版 = 一次层栈结构写（挂 mask 到选中层或新建层）→ `stackSnapshot` 型 history item → ⌘Z 可退（LayerUIWiringTests 14/14 同款语义） |
| pipe 缓存面 | retouchPosition 腿缓存 + blendTriple 前缀键 + enforceBudget 五档 + FULL 冷层政策 | 推理腿**不新增缓存类**——推理产物以 maskPlane/layerPlane 级进入既有缓存（移交清单第 4 条口径） |

**"可编辑非黑箱"的交互形态（AI-06 + AI-07 落点）**：生成蒙版动作完成后，蒙版立即出现在选中层的 mask 槽（LayersPanel 缩略 mask chip 可见，`LayersPanelView` 既有），蒙版工具条自动激活该层的蒙版编辑模式——用户看到的不是"AI 结果"，是一条**普通 raster 蒙版**（这正是非黑箱：AI 退到生成器角色，产物进入与手画蒙版完全相同的编辑/合成/持久化世界）。

### 4. AI-07 非黑箱（可解释 / 可调 / 可覆盖）

每个 AI 输出的三面：

| AI 输出 | 可解释面（看得见） | 可调面（滑块/参数） | 用户覆盖路径 |
|---|---|---|---|
| AI-01 主体 mask | mask overlay 显示（06-03 overlay pass 复用）+ instance 列表勾选（哪些主体进 mask） | qualityLevel（生成档）+ 羽化半径 + invert + refine 点（含/排） | (a) drawn 笔画 union/diff 修补 (b) parametric ⊓ 收紧 (c) invert（`RasterMaskRef.invert`）(d) 删了重生成 (e) bake 后手画整段替换 |
| AI-05 skin mask | mask overlay + 保护区（眼/唇）可视化 | hull 外扩量、羽化半径、保护区 margin | 同上 + 手画 union（露肤处）|
| AI-05 磨皮强度 | 磨皮前后对比（按住空格看原图 = Phase 9 before/after 未交付前的面板 toggle） | strength / radius / detail-preserve t | 层 opacity / blend mode / 蒙版收紧（全 Phase 6 机制） |

- **红线**：任何 AI 参数不进"黑盒历史项"——skinSmooth 是普通 iop（参数入 `ModuleInstance`，sidecar/history 全套复用）；AI mask 生成参数（qualityLevel/seeds/refine 点）**不持久化为编辑语义**（生成完 bake 即弃——蒙版像素才是编辑语义；重生成参数留在 UI 状态，不进 sidecar。这与"AI 是生成器不是编辑"的架构裁决一致，也避免 sidecar schema 再升级）。
- Phase 7 唯一新蒙版原语 = **raster 腿羽化**（bake 管线内单通道 blur，§1.2）——其余全部复用。

### 5. 性能

- **Vision 请求耗时**：Apple 文档无官方毫秒数；**研究口径 = plan 07-1 首任务 benchmark 钉基线**（100MP GFX RAF 解码帧 + 24MP 常规帧 × 层 A/层 B/personSeg/faceLandmarks × fast/balanced/accurate，ANE vs CPU 实测）。预算锚：SC#5 "latency acceptable for interactive use + cache result"——单次生成 ≤1s 可接受（非拖动热路径），plan 期定门。
- **ANE vs CPU**：Vision 的 CoreML 后端默认 ANE 优先；macOS 27 Swift 请求暴露 `setComputeDevice(MLComputeDevice?, for: ComputeStage)` + `supportedComputeStageDevices`（SDK `:1757-1760` 实证）——运行时枚举可 pin；ObjC 腿 `VNRequest.usesCPUOnly`。**测试 pin CPU 保确定性**（§6）。
- **推理与 Metal pipe 的并发（PERF-1 对策）**：推理跑后台 Task（Swift concurrency），完成回调才 bake/写层栈——Metal 渲染循环零感知；ANE 与 GPU 是独立单元，无帧内资源竞争路径。
- **mask bake 成本**：`RasterMaskStore.readPlane`（`:55-73`）= fence + 同步读回；100MP r32Float 全幅 = ~400MB float → uint16 ~200MB → PNG 编码。AI mask 是**一次性动作**不在热路径；若 100MP bake 峰值超预算（Instrument 实测），分块读回（`readPlane` 改窗口化循环，plan 期定）。
- **推理输入构造**：解码帧 IOSurface-backed `MTLTexture` → `CVPixelBuffer` → `CIImage`/`perform(on:)` 零拷贝路径；跨队列纹理必须先 fence（**L014 红线**——我们的队列写、Vision/CI 内部队列读，与 colorout 腿同款风险）。
- **缓存策略**：(a) **持久**：旁挂 PNG = 推理结果落盘（重开 app/重选图零重推理，SC#5 天然满足）；(b) **内存**：mask plane 既有缓存键（`maskVersionHash` 折叠）全沿用；(c) **推理中间态**：无缓存需求（重生成 = 用户主动）。
- **模型资产**：层 B 首次用前 `assetStatus` 检查 + `downloadAssets()`（带 Subprogress）；层 A/personSeg/landmarks OS 内置零成本。

### 6. Golden / 验证策略（L017 分流的 AI 变体）

| 对象 | 轨 A（dt 证据） | 参考/断言口径 | 钉参 case（初值） |
|---|---|---|---|
| AI-01 层 A mask | **不适用**（dt 无对照；模型输出不可逐字节 golden） | ①确定性门：同输入同 device 两次推理 mask 逐字节恒等（进程内 + 跨进程各一）②合成语义门：纯背景 + 居中高对比几何主体合成图 → mask 与已知主体 bbox 的 IoU ≥ 0.9、背景区 mask ≤ 0.1 ③bake→load round-trip uint16 恒等（RasterMaskRoundTrip 同款） | 3（单主体/多主体勾选/无主体 nil） |
| AI-01 层 B mask | 不适用 | 同上①③ + seedPoint→mask 非空（合成图点击主体中心）+ excludedPoint 后主体内 mask 下降（方向性断言，不钉数值） | 3 |
| Vision 确定性 | — | 测试 `setComputeDevice` pin CPU（`supportedComputeStageDevices` 枚举断言含 CPU）——跨机器 golden 稳定前提 | 1（常驻） |
| skin hull 几何 | — | 纯 Swift 解析断言（**不跑模型**）：合成点列 → hull 内 mask=1 / 保护区=0 / 羽化带剖面（Gaussian 剖面，DrawnMaskRasterTests 模式）| 4（正脸/侧脸 yaw 门/多脸 union/空 landmarks 降级） |
| 频率分离数学 | —（自研参考） | float64 Swift 参考 parity（low/high 分解 + 阈值衰减逐式，`SkinSmoothReference.swift`）<1e-5 + **恒等三元组**：a=0 逐字节恒等 / mask 空 == no-op / 平场恒等（任何 DC-1 blur，L017-proof）| 6（σ×a×t 组合） |
| mask 上采样/翻转 | — | 合成小 mask（左上角块）→ 上采样双线性权重断言 + 与解码帧像素对齐断言（行 0 = 图顶）；交互点 Y 翻转单测 | 2 |
| GUI 验收轮 | — | 真实 RAW：①生成主体蒙版 overlay 开/关截图量化（06-03 ΔR 模式）②人像 RAW 磨皮前后对比截图 + pore-level 目检（Manual-Only）③tap-to-segment 手感（点选/排点/lasso 线宽 ≥1% 图宽）| PLAYBOOK §0-§6 |

- **轨 B 照旧**：全链 ColorSync 中性度 + 交叉一致性不回归（D-COL1）；skinSmooth 启用/禁用态均过。
- **防空转**：语义门必须带方向断言（IoU > 阈值 / mask 下降），禁"存在输出即过"（06 VERIFICATION 内容级抽查口径）。

### 7. v50 槽位分析

- **AI-01 主体隔离 = mask 生成器服务，不占 iop 槽**：它不变换像素，产出蒙版资产（raster 腿）——与 dt `mask_manager`（22.0，管理器非处理模块）同位的非模块角色，但我们的落点是服务+UI 入口，连槽位都不需要。
- **AI-05 skinSmooth = 像素变换，必须占槽**。候选：
  - **66.5（推荐）**：soften（66.0）与 splittoning（67.0）之间——模糊/柔化族邻域，RGB 段（colorin 28.0 之后），与 soften 同域先例。
  - 备选 28.5 系（diffuse/censorize 邻域，"signal processing"注释区）——但那是 denoise 语义区，磨皮是 creative 修复，语义不符。
  - **V50Order 表是 dt verbatim port**（`V50Order.swift:1-15` 头注），插入非 dt 原生行是**项目首例**——表头注释标记"非 dt 行（Phase 7 skinSmooth）"，沿用 dt 不可重排/唯一性纪律（sidecar 自 Phase 2 携带 order，新行只增不改）。
  - 或**完全不占表**：层内 iop 也从同一 V50Order 取序（`AdjustmentLayer.chain` 与全局同拼写）——skinSmooth 无论全局还是层内用都得有 order，表内新行不可避免（除非 hack 复用 soften 槽，否决——混淆语义）。
- 磨皮的层形态：skinSmooth 可挂 base 链（全局，配 raster skin mask）或调整层 chain（层内，配层 mask）——两形态都合法（`ModuleInstance` 同构）；推荐默认 = 调整层（C1 工作流语义：磨皮是局部修复步骤，可整层开关），面板入口在层上下文。

### 8. UI 面（GUI 红线）

- **AI 蒙版入口**（`MaskToolbarView` 增 AI 组或 Inspector 蒙版区增按钮）：「主体蒙版」（层 A 一键）+「点击选取」（层 B 进视口交互模式）；生成中 spinner（后台 Task）+ 完成即 mask chip 更新（LayersPanel）。
- **tap-to-segment 视口交互**（`LayerEditingState` 编辑模式状态机增第 4 模式）：单击 = seedPoint/addIncludedPoint；⌥/右键 = addExcludedPoint；lasso 拖拽 = seedScribbleBuffer（**线宽强制 ≥1% 图宽**，UI 光标环提示）；box 拖拽（⇧）= seedBox。点数计数器（13/11 上限，满即禁点 + 提示）。与 crop/mask 绘制/retouch 路由互斥（LayerUIWiringTests 同款断言扩展）。
- **instance 勾选**：层 A 多主体 → 浮层列表（checkbox per instance + 预览高亮）→ 确认 bake。
- **skinSmooth 面板**（`IOPPanelProvider` 注册，24 面板同款四件套）：strength / radius / detail-preserve 三滑块 + 「定位皮肤」按钮（生成 skin mask 挂层）+ 保护区显示 toggle。
- **模型下载态**（层 B）：assetStatus 三态（未下载/下载中含 Subprogress/就绪）→ 按钮态与进度条；下载失败报错不静默。
- **GUI 红线**：蒙版生成可视化 = overlay 截图量化（06-03 ΔR 口径，FINDINGS 落账）；磨皮质感与 tap 手感 = Manual-Only 表登记（L011）；全部 AI 按钮 L010 identifier 全量（`ai.mask.subject` / `ai.skin.locate` 等）。

## Validation Architecture

1. **顺序**：07-1 基建 + 层 A/B（确定性/语义/bake 门全绿）→ 07-2 skinSmooth（频率分离 parity + hull 几何 + 面板）→ 07-3 集成精修 + GUI 验收轮 + 阶段签核。
2. **双闸**：ParityGate（频率分离 <1e-5 + 恒等三元组逐字节）+ AI 确定性门（同输入两次推理恒等 + CPU pin）。
3. **内容级兜底**（L020 对策③沿用）：语义门方向断言（IoU/mask 下降）防空转；上采样/翻转对齐断言防坐标错位。
4. **GUI 验收轮**（AGENTS.md 硬性项）：真实 RAW 端到端（生成蒙版 → 编辑蒙版 → 磨皮 → ⌘Z 回退链）+ PLAYBOOK 量化 + Manual-Only 表。
5. **性能**：Vision benchmark 基线落 `.work/07/perf.md`（只记录不设门，SC 门 = 单次生成 ≤1s plan 期定）；bake 峰值内存 Instrument 记账。
6. **单测标准命令**：`Scripts/test-direct.sh`（L019b）；Vision 请求在测试中 pin CPU。

## Risks & Gotchas

1. **离线声明 vs 模型下载（OQ1，最大风险）**：`GenerateIterativeSegmentationRequest` 需一次性 `downloadAssets`；ROADMAP SC#5 声明 offline。若不处理 = 首次点按钮静默失败。对策：assetStatus 门控 UI + 预下载提示 + 层 A 自动回落（OQ1 三选一需拍板）。
2. **Vision 坐标系 Y 翻转**：API 传点原点左下（mask buffer 像素对齐无需翻转）——传点换算漏翻 = 点击选中镜像位置的物体；上采样对齐断言 + 传点单测双防线。
3. **低清 mask 上采样块状**：nearest（RasterMaskStore.load 现口径）对软边缘 AI mask 会块状——bake 入口独立双线性/羽化路径；load 的 per-scale resample 口径不变（已 bake 的 PNG 是高分辨率，跨 scale 缩小 nearest 可接受）。
4. **macOS 27 beta 系 API 行为漂移**：层 B 是 WWDC26 新 API（revision1 唯一）；点数上限/qualityLevel 语义以 SDK 实测为准，benchmark 首任务钉基线；API 签名若在正式版变（beta 期风险），07-1 动工前用本机 SDK swiftinterface 复核一遍（本研究已存 `:1700-1766` 快照）。
5. **推理输入跨队列（L014）**：解码帧纹理 → CVPixelBuffer → Vision 读取，必须 fence 本队列既有写入（`convertTexture`/`readPlane` 同款前置空 commit + waitUntilCompleted）。
6. **100MP bake 内存峰值**：readPlane 全幅 float ~400MB；Instrument 实测超预算则分块（§5）。
7. **点数上限 13/11**：UI 计数器 + 满禁点；超限 `addIncludedPoint` throws 需接错误呈现（不崩不静默）。
8. **确定性跨 device 漂移**：ANE 与 CPU 推理结果可能非逐字节同（浮点顺序）——测试 pin 单一 device（CPU）；运行时给用户的结果不做跨 device 恒等承诺（同 device 恒等即达 SC 口径）。
9. **迭代精修版本链膨胀**：每次 refine 重 bake PNG（同 maskID 覆盖，不累积文件）；但 history 的 `stackSnapshot` 每次精修一条（蒙版编辑语义）——极端百次精修 = 百条结构项，体积可忽略（点列/引用非像素），照 LayerUIWiring 语义不设限。
10. **执行纪律**：omp 运行期 orchestrator 零工作区写入（L022）；**暂停机制（AGENTS.md 2026-09-24）**：subagent 每任务边界查 `.work/PAUSE`；C 档门控三点停（研究定稿停/每 plan 闭环停/签核前停）——本文件交付即触发第 1 停。

## Plan 拆分建议（3 个，依赖序）

| Plan | 内容 | T 数（估） | 验收要点 |
|---|---|---|---|
| **07-1 Vision 基建 + AI-01 主体隔离** | `AIMaskService`（Core/新 `AI/` 目录：handler 封装 + 后台 Task + fence + assetStatus 门控）+ 层 A/层 B 接入 + mask 上整形（双线性上采样 + 羽化 bake 增件）+ `RasterMaskStore.bake` 接线 + Vision benchmark 基线（`.work/07/perf.md`）+ 确定性/语义/round-trip 测试 | 5-6 | 同输入两次推理恒等；合成图 IoU ≥0.9；bake→load 恒等；无主体 nil 报错腿；benchmark 落账 |
| **07-2 skinSmooth 频率分离磨皮** | `SkinSmoothKernels.metal`（分解 + 阈值衰减）+ `SkinSmoothModule`（66.5 槽，V50Order 非 dt 行标记）+ skin mask 生成（landmarks hull − 保护区 ⊗ personSeg，CPU 几何）+ float64 参考 + 面板四件套 + 恒等三元组 | 5-6 | 频率分离 <1e-5；a=0 逐字节恒等；hull 几何解析断言；平场恒等；面板接线 PanelWiring |
| **07-3 AI-06/07 集成精修 + GUI 签核** | tap-to-segment 视口交互（第 4 编辑模式 + Y 翻转 + 点计数）+ instance 勾选浮层 + 三通道接入（raster 主 + parametric 预设若 OQ3 通过）+ drawn/parametric 覆盖路径 E2E + GUI 验收轮（overlay 量化 + 磨皮目检 Manual-Only）+ 阶段签核（VALIDATION + REQUIREMENTS 翻账 + Phase 8 移交清单） | 5-7 | 生成蒙版 ⌘Z 恰 1 commit；overlay ΔR 量化；PLAYBOOK 全过；suite 全绿 |

依赖序：07-1 → 07-2（AIMaskService 皮肤腿）→ 07-3。总量 ~15-19 T（Phase 6 ~38-48T 的四成弱，符合 4 需求小阶段定级）。可选拘认：07-2 与 07-3 的 parametric 预设部分并行。

## Open Questions for Planning

1. **离线声明 vs tap-to-segment 模型下载（SC#5 措辞冲突，07-1 动工前拍板）**：(a) 推荐——双后端自动回落（assetStatus 未就绪时层 B 按钮置灰引导下载，层 A 全程可用；首启可后台预下载）+ SC#5 措辞修订为"推理本地 ANE、层 B 模型一次性下载"；(b) 只做层 A（彻底离线，放弃 SC#1 的 iterative refinement 半句）；(c) 只做层 B（体验最好但首次必联网）。
2. **skinSmooth 落位**：(a) 推荐——独立 iop `skinSmooth` @ V50Order 66.5 新行（表头标记非 dt 行）；(b) "AI 面板组合预设"形态（生成 skin mask + 组 soften/highpass 两层——零新 kernel 但频率分离数学凑不齐、阈值衰减防塑料感做不了）；(c) 层 kind（retouch 同款）——磨皮不是 stroke 系统，不符。
3. **AI-06 "直接作为 parametric mask" 的实现口径**：(a) 推荐——v1 只走 raster 烘焙（像素 mask 的唯一忠实通道），REQUIREMENTS AI-06 措辞注记"parametric = 可选预设"；(b) 增加 AI→parametric 语义曲线预设（landmarks → 肤色 hz 4 点曲线 + luma 范围，dt hue 1.0 rad 参考换算）作为第二通道一并交付。
4. **tap-to-segment 交互 v1 范围**：(a) 推荐——tap 含/排点 + box 先行（点击是修图主力，scribble/lasso 手势后置）；(b) 全量三手势（tap/scribble/lasso 一次交付，scribble buffer 构造 + 线宽 UI 成本 +1T）。
5. **迭代精修的版本文件策略**：(a) 推荐——同 maskID 覆盖重 bake（hash 链自然失效，无孤儿文件）；(b) 版本递增多文件保留（精修历史可考古，代价 = 孤儿清理逻辑 + 磁盘）。
6. **磨皮数学形态**：(a) 推荐——v1 两频高斯分离 + 阈值高频衰减（Photoshop 对标基线，参数面 3 滑块）；(b) 多尺度分离（小波 3-4 频，dt diffuse 式——更强但参数面复杂 +1T，bilateral/多频变体留 v2 扩展位）。

## Sources

### Apple 文档（availability 元数据 + API 面，docs data 端点）

- `VNGenerateForegroundInstanceMaskRequest`（macOS 14+）：https://developer.apple.com/documentation/vision/vngenerateforegroundinstancemaskrequest
- `VNInstanceMaskObservation`（allInstances/instanceMask/generateMask/generateScaledMaskForImage/generateMaskedImage）：https://developer.apple.com/documentation/vision/vninstancemaskobservation
- `GenerateIterativeSegmentationRequest`（macOS 27+，tap-to-segment）：https://developer.apple.com/documentation/vision/generateiterativesegmentationrequest
- `DownloadableAssetsRequest`（assetStatus/downloadAssets）：https://developer.apple.com/documentation/vision/downloadableassetsrequest
- `VNGeneratePersonSegmentationRequest`（macOS 12+，qualityLevel fast/balanced/accurate + outputPixelFormat + supportedOutputPixelFormats）：https://developer.apple.com/documentation/vision/vngeneratepersonsegmentationrequest
- `VNDetectFaceLandmarksRequest` / `VNFaceLandmarks2D`（地标集 + boundingBox 归一化 + `VNImagePointForFaceLandmarkPoint`）：https://developer.apple.com/documentation/vision/vndetectfacelandmarksrequest 、https://developer.apple.com/documentation/vision/vnfacelandmarks2d
- `VNGeneratePersonInstanceMaskRequest`（macOS 14+，人像 per-instance 备选）：https://developer.apple.com/documentation/vision/vngeneratepersoninstancemaskrequest
- `CIFilter`（Core Image 无皮肤平滑滤镜的查证基线）：https://developer.apple.com/documentation/coreimage/cifilter
- WWDC26/237 "What's new in image understanding"（tap-to-segment 演示 + 坐标系左下原点 + lasso 线宽 ≥1% 图宽 + 模型下载）：https://developer.apple.com/videos/play/wwdc2026/237

### 本机 macOS 27 SDK（Xcode on /Volumes/UNITEK，符号级实证）

- `.../MacOSX27.0.sdk/System/Library/Frameworks/Vision.framework/Versions/A/Modules/Vision.swiftmodule/arm64e-apple-macos.swiftinterface`
  - `:82`（RequestDescriptor case）、`:1700-1766`（GenerateIterativeSegmentationRequest 全接口：availability macOS 27.0、DownloadableAssetsRequest、init(seedPoint/seedBox/seedScribbleBuffer:)、addIncluded/ExcludedPoint、qualityLevel、regionOfInterest、setComputeDevice/supportedComputeStageDevices）、`:844-876`（DetectFaceLandmarksRequest rev3/rev4）、`:2193-2210`（FaceObservation：landmarks/roll/yaw/pitch/captureQuality）、`:615-620`（perform(on:) 六种输入）、`:1965`（ComputeStage）
- `.../Vision.framework/Versions/A/Vision.tbd`（GenerateIterativeSegmentationRequest 链接符号在库）

### Darktable（本地源码，树 dc58cf0ba1；对照面——dt 无 AI 磨皮）

- `src/iop/channelmixerrgb.c:1796-1797`（skin hue 角参考：均值 1.0 rad、范围 [0.75, 1.25]——parametric 肤色曲线预设的 dt 依据）
- `src/iop/soften.c` / `src/iop/highpass.c` / `src/iop/lowpass.c` / `src/iop/blurs.c`（频率分离数学基座族；Lightamer 已移植 soften 66.0 / highpass 34.0）
- `src/common/gaussian.c:41-100`（Deriche IIR 系数——已移植为 `Common/GaussianBlur.swift`）
- dt 无 skin-smoothing 专模块（`grep -rn "skin" src/iop/` 仅 preset/hue 权重命中）——AI-05 为自研数学 + Vision 定位，无 dt parity 轨

### Lightamer 代码（Phase 6 交付面，现码 file:line 核过）

- `LightamerCore/Sources/Layers/Masks/MaskSpec.swift:7-11`（内容锚定坐标）、`:160-177`（四 drawn 形态）、`:239-299`（三 payload + `stableHash()` 派生身份）
- `LightamerCore/Sources/Layers/Masks/RasterMaskRef.swift:20-37`（fileName/maskHash decimal-String lock/invert）
- `LightamerCore/Sources/Sidecar/RasterMaskStore.swift:46-101`（masksDirectory/bake）、`:104-147`（load + 三失败腿降级 + per-scale resample nearest）
- `LightamerCore/Sources/Layers/Masks/MaskCombiner.swift`（effectivePlane 三 payload 装配/resample/invert/fill——06-VERIFICATION 判定表）
- `LightamerCore/Sources/Pipe/LayerCompositeDriver.swift:69-98`（1+N+1 编排 + kind 分派）；`LightamerCore/Sources/Layers/LayerStack.swift:91-184`（层栈 mutation API）
- `LightamerIOP/Sources/Common/GaussianBlur.swift`（Deriche IIR 共享原语——skinSmooth low 腿）；`Highpass/HighpassModule.swift:19-21,134-149`（σ/halo 链 + 分解→mix 参照）；`Soften/SoftenModule.swift:24-30`（RGB linear + mix 公式先例）；`Bilateral/` + `Common/BilateralGrid3D.swift`（边缘感知可选腿）
- `LightamerIOP/Sources/Masks/MaskPostProcessKernels.metal`（单通道 mask blur/feather kernel——bake 羽化增件参照）
- `LightamerCore/Sources/Foundation/V50Order.swift:1-15`（dt verbatim 表头纪律）+ soften 66.0/splittoning 67.0 邻域（表内行）
- `LightamerIOP/Sources/Registry.swift`（模块注册面，skinSmooth 注册点）

### 项目文档

- `.planning/ROADMAP.md` §Phase 7（:118-133，SC#1-5 + PERF-1/NDE 风险 + 追色 V2 移出注记）
- `.planning/REQUIREMENTS.md` AI 节（:136-149，AI-01/05/06/07 + AI-02/03/04 → v2 划界 + 划分原则）
- `.planning/phases/06-layers-masking/06-RESEARCH.md`（体例范本）；`06-VERIFICATION.md`（14/14 交付基线 + Manual-Only 5 项挂账）；`06-07-SUMMARY.md` + `06-DISCUSSION-LOG.md` 终节（Phase 7 移交清单四条）
- `LESSONS.md` L004（AI 原生边界）/L011（Manual-Only）/L013（显式折叠哈希）/L014（跨队列 fence）/L017（golden 分流）/L020（坐标内容级断言）/L021（GUI 验收红线）/L022（omp 零写入）/L023（半边契约）/L025（String Catalog）
- `AGENTS.md` Phase 执行模型（2026-09-20）+ **暂停机制（2026-09-24，Phase 7 起强制：PAUSE 文件 + 任务边界检查 + C 档门控三点停）**

---

*Phase 7 Research — 2026-09-26。产物仅本文件（`.planning/phases/07-ai-modules/` 目录新建）；未提交 git；研究期间已按 §6 规范开/关代理（px --up → 查证 → px --stop）。*
