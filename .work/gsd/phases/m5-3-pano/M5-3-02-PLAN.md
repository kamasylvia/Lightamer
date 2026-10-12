---
phase: m5-3
plan: "M5-3-02"
title: "全景生产腿批（wave 2 = RESEARCH §6 plan-02）——PanoWarp（sphericalMap 纯函数 + 矩阵尺度回投 + boundedRois 200MP 收缩循环）+ PanoGain（重叠 median-log 方程 + 参考锚定 lstsq + exp clip）+ PanoCrop（min-pool 直方图栈 + naive 对照）+ runPanoLeg 生产腿装配（双 pass 几何/融合分离 + 512px tile 流式 + 12% 羽化带 + FloatTIFFWriter 行带直写 + landStackProduct additive rowProvider）+ StagedSet additive readRows + G3 分段 golden + G1 腿级闭环 + 200MP×8 预算探针（8G 门）"
wave: 2
depends_on: ["M5-3-01"]
autonomous: true
requirements: ["IOP-PANO-01"]
estimated_tests: "+30..40"
test_bundles: [IOP, Export]
files_modified:
  - LightamerCore/Sources/Stack/PanoWarp.swift     # 新建：sphericalMap 纯函数（merge.py:205-211 直译）/preview_scale 矩阵回投 + K() 构造/全局 scale = median 焦距/boundedRois ≤8 轮 ×0.998 收缩循环 + 200MP 帽常量 + typed canvasInvalid；文件头 MIT 归属注记
  - LightamerCore/Sources/Stack/PanoGain.swift     # 新建：≤900px 采样画布 + 重叠 pairwise median-log 方程（≥80px 样本 + 双值 ∈ (0.04,0.9)）+ 参考锚定（权重 10）+ Accelerate lstsq + exp clip(±0.5)；MIT 归属注记
  - LightamerCore/Sources/Stack/PanoCrop.swift     # 新建：≤1024-cell min-pool 网格 + 直方图栈最大全有效矩形 O(cells) + naive O(N²M²) 参考对照 + 空矩形 typed；MIT 归属注记
  - LightamerCore/Sources/Stack/StackMergeService.swift # 修改：runPanoLeg 生产腿本体（KD-10 编排：staged+预览派生 → 特征/相机 → 双 pass 几何/融合分离 → 行带直写落盘 → landStackProduct rowProvider）+ StagedSet additive readRows（全宽行带无 shift 读）+ landStackProduct additive rowProvider 参（nil = 既有路径字节零漂移）
  - LightamerCore/Sources/Stack/BandStreamer.swift # 修改：FloatTIFFWriter 流式行带写 additive（sRGB tag；既有 writeFloatTIFF 零漂移——负测钉死）
  - Tests/LightamerTests/PanoWarpTests.swift       # 新建（IOP/Core 级）：sphericalMap 闭式解逐点/boundedRois 不变式/矩阵回投/scale 中位数/typed
  - Tests/LightamerTests/PanoGainTests.swift       # 新建（IOP/Core 级）：合成方程组恢复/门值（80px/(0.04,0.9)）/锚定/clip 上限
  - Tests/LightamerTests/PanoCropTests.swift       # 新建（IOP/Core 级）：直方图栈 vs naive 逐位/空矩形 typed/min-pool 保守性
  - Tests/LightamerTests/PanoLegTests.swift        # 新建（IOP/Core 级，合成 decode 腿小 fixture）：happy path/进度恒式 3N+6/typed 三态/双跑产物 bit-identity（G1 腿级闭环）/sRGB tag/pano 分账名/provenance 快照回写
  - Tests/LightamerTests/PanoFusionPerfProbeTests.swift # 新建（EXPORT 级，env 门 LIGHTAMER_PERF_PROBE=1 + XCTSkipUnless——默认套件 skip）：200MP×8 tile 融合预算探针（墙钟分账 + ru_maxrss）
  - Project.swift                                  # 修改：五新测试文件登记对应 target 数组 + tuist generate 恒为该批最后一个动作（L041）
  - .work/gsd/phases/m2-4-0-test-bundles/M2-4-0-BUNDLE-MAP.txt # 修改：五新测试文件增行登记（E2；probe 落 EXPORT rationale 注记随行——M5-2 同款）
  - .work/gsd/phases/m5-3-pano/perf.md             # 新建：probe 出数正本（几何/增益/融合/写盘墙钟分账 + ru_maxrss；M2-11/M5-2 perf.md 惯例）
  - .work/gsd/phases/m5-3-pano/M5-3-02-SUMMARY.md  # 新建（T6）
  - .work/gsd/phases/m5-3-pano/M5-3-02-DECISIONS.md # 新建（T6）
  - .work/gsd/phases/m5-3-pano/M5-3-02-ACCEPTANCE.md # 新建（m1 双重验收记录——zcode PASS 后串行 omp 二次验收，严禁并发）
  - .work/GOAL-STATE.md                            # 修改：续接点
  - .work/TODO.md                                  # 修改：M5-3 条目
  - .work/LESSONS.md                               # 如踩坑
---

# Plan M5-3-02 — 全景生产腿批（wave 2：投影 → 增益 → 裁切 → runPanoLeg 装配 → 预算 → G3）

> **性质**：M5-3 后继 plan（依赖 M5-3-01 全绿）。本批执行**生产行为落地**：
> ①投影/增益/裁切三纯函数族（G3 分段 golden）；②`runPanoLeg` 生产腿装配
> （M5-3-01 stub 换腿体，dispatch 结构零二次编辑）；③双 pass 几何/融合分离
> + tile 流式 + 行带直写——**全画布像素面永不物化**的内存红线本体；④200MP×8
> 预算探针（ru_maxrss 8G 门机检钉）。**既有六 kind 与 Robertson/Mertens 路径
> 字节零回退**为本批第一红线（G5 复验）。
>
> **基线**：M5-3-01 验收后的实测全套值（对账链 = **3539/22/0** + M5-3-01
> 增量；01-SUMMARY 记账后起算——M5-2-02 同款衔接措辞）。定向轮 bundle 分账见
> T6；全套 `--all` 轮照批准制（本 plan 收口轮申请）。

## 已定裁决（生效值，硬约束，不得重开）

承 M5-3-01 已列七值（OQ-1/2/3 数学面 + OQ-4 张数门 + OQ-7 类型面）；本 plan
承载落地面生效值：

1. **OQ-3 = A（落地面）**：全链 **sRGB 编码 float32 [0,1]**（Mertens 腿同域
   ——`DrtEotfMath.srgbPiecewiseEncode` 接缝现成）；产物 = **sRGB-tagged 32f
   TIFF**（Mertens T2 `productColorSpace` 同参）→ M4-1 raster ingest 重导入
   （域判别 = ICC tag 基，`MertensRasterDomainTests` 亲读在案——pano 产物
   同 face 零新机制）。
2. **OQ-4 = A（落地值）**：**200MP 输出帽**（`PANORAMA_MAX_PIXELS` 同值常量）
   + `boundedRois` ×0.998 ≤8 轮收缩循环；**ru_maxrss < 8G 门机检**（预算探针
   钉，实测入 perf.md；MEMFAIL 兜底照 test-direct 惯例）。
3. **OQ-5 = A（落地值）**：**恒 inner_crop**（v1 无开关）+ **alpha 不写**
   （产物 RGBA alpha 恒 1——valid 掩码信息在恒裁后已表达，掩码不进 alpha；
   M4-1 raster 链 alpha 丢弃语义不变）。
4. **OQ-6 = A（落地值）**：v1 全 CPU（Accelerate/vImage）——零新 `.metal`、
   零 PSO 面；**预算探针越门 → GPU kernel 化另立 plan**（per-phase 零新
   kernel 纪律，立项才动）。
5. **OQ-7 = A（生产面）**：`runPanoLeg` 生产腿 + provenance/details 回写
   （canvas/gains/crop 快照）；UI = M5-3-03。

**架构红线（本 plan 全程 + checker 机检面）**：
- **Robertson/Mertens 逐字节不动**：`runHDRLeg`/`runMertensLeg`/
  `runFocusStackLeg`/`runStackAggregateLeg`/`ExifPrecheck` 全族零 diff；既有
  六 kind 行为零变化（`landStackProduct` additive 参缺省路径字节零漂移专测
  钉死；`writeFloatTIFF` 既有调用零漂移负测钉死）。
- **零新 SPM**（dependencies 块零 diff）+ **零新 `.metal`**（git diff grep
  截屏入 SUMMARY）+ `LightamerIOP/`/`Sidecar/`/`Pipe/History/`/`Graph/`
  （V50Order/Registry）零 diff + sidecar schemaVersion 不动。
- **ExportQueue/六格式导出矩阵零 diff**（`LightamerCore/Sources/Export/`
  本 plan 零触——产物入编辑链走 M4-1 已交付 raster ingest）。
- **8G 运行门**（AGENTS 资源监控节）：探针轮 orchestrator 批准 + 运行中
  监视；>8G 或内存压力转红立即 kill。
- darktable GPL 零复制；OpenCV detail 语义只读；Lumen MIT 成段移植带归属注记。

## 关键设计决策（planner 裁决，执行中不重开）

### KD-1 色彩域与 staging（每源单 render 一次解码预算）

- 全链 sRGB 编码 float32：源平面 render（dedicated queue CIContext 线性
  Rec2020）→ **sRGB 编码 in-place**（`mertensDisplayEncodeInPlace` 同函数
  语义——`DrtEotfMath.srgbPiecewiseEncode` + clamp）→ staged 16B/px 落盘
  （`StagedSet` 复用）→ **同平面派生预览灰度**（M5-3-01 制备函数）后释放
  ——每源恰好一次 render/解码（HDR ×2 render 先例的改进面，DECISIONS 记录）。
- `StagedSet` additive：`readRows(index:firstRow:rows:)` 全宽行带无 shift 读
  （tile 任意坐标 gather 的行源；既有 `readShiftedPixels` 整数 shift 读法
  零改——pano 位移是连续单应/球面映射，非整数平移）。

### KD-2 球面投影纯函数（merge.py:205-211 直译；MIT 归属注记）

- `sphericalMap(rect, scale, k, r) -> (mx, my)`：画布像素 (x,y) →
  u=(x+x0)/scale, v=(y+y0)/scale；ray_sph = (sin v·sin u, −cos v, sin v·cos u)；
  camera = ray_sph @ R；projected = camera @ Kᵀ；**z > 1e-6 有效，否则坐标
  = −1**（无效标记）。纯函数、无状态、逐 tile 调用（全画布映射面从不物化）。
- Float32 全程（Lumen np.float32 同精度域——G3 逐点对照的精度前提）。

### KD-3 矩阵尺度回投与全局 scale（merge.py:249-254）

- `matrices = inv(preview_scale) @ camera.K()`——预览域标定 K 回投全分辨率；
  全局投影 **scale = median(各图 f)**（抗单图离群）。
- K 构造面 = 对角 (f, f, 1)（主点 = 图心；无畸变——OQ-2 模型面）。

### KD-4 boundedRois 收缩循环（merge.py:192-202 直译；200MP 帽）

- ≤8 轮：每轮按候选 scale 求每图球面 ROI → 并集 bounds；`w*h ≤ 200MP` →
  收；超 → `scale *= sqrt(200MP/(w*h)) * 0.998` 重投；8 轮不达 / 零面积 /
  非有限 scale → **typed `"panorama canvas invalid: ..."`**（M5-3-01 KD-4
  词汇消费点）。
- 输出分辨率上限由此机制决定（等比收缩，非固定缩放）——200MP 帽常量 =
  `PanoWarp.maxCanvasPixels = 200_000_000`（Lumen 同值）。

### KD-5 双 pass 几何/融合分离（内存红线核心；Lumen 单 pass + memmap 的等价替身）

- **数学依据**：valid = `weight > 0`，而 weight = Σ α·inside **纯几何量**
  （α 只依赖源图尺寸与映射坐标，不依赖像素值）——裁切界可先于像素融合解析。
- **pass 1（几何）**：512px tile 扫全画布，逐图 sphericalMap → inside/α →
  weight>0 → valid 掩码（**UInt8 1B/px 常驻，200MP = 200MB**）→ `PanoCrop`
  解出裁切矩形。
- **pass 2（融合）**：512px tile 扫**裁切相交域**——逐图 ROI 相交跳过 +
  sphericalMap 取源坐标 + staged 行带读 + 双线性 gather + 羽化 α + 增益 →
  fused 行带**直写 FloatTIFFWriter**（crop 外行/列跳过）。
- **全画布像素面（3.2GB @200MP）永不物化**；无 Lumen memmap 磁画布、无
  staged 输出画布。G3 钉：小画布上两 pass 裁切输出 == naive 单 pass 全画布
  融合后裁切参考**逐位**。
- 内存账（200MP × 8 源）：valid 掩码 200MB + tile accum/weight O(tile²) +
  staged IO 行带缓冲 + 预览域 <1GB —— 8G 门可达（探针实测背书，KD-12）。

### KD-6 曝光增益求解（merge.py:255-273 直译；MIT 归属注记）

- ≤900px 长边采样画布：逐图球面采样进画布坐标 → 重叠域 pairwise：
  两图重叠样本 **≥80px** 且双值 ∈ **(0.04, 0.9)**（排除黑场/高光裁剪）→
  方程 `g_i − g_j = median(log(J_j/J_i))`（Rec709 luma 域）。
- 参考帧锚定方程（权重 10，值 0）+ **最小二乘联解**（Accelerate `dgelsd`
  或正规方程 `dgesv`——执行期定，DECISIONS 记录）；`gains =
  exp(clip(x, ±0.5))`——增益上限 **e^0.5 ≈ 1.65×**，防单对噪声炸增益；
  参考帧增益恒 1。
- 几何不连通图不静默丢失（锚定 + lstsq 最小范数性质——merge.py:257-258
  注释亲读）；采样实现用 M5-3-01 `sphericalMap` 同函数（900px 采样画布域）。

### KD-7 tile 融合与羽化带（merge.py:274-289 直译；MIT 归属注记）

- 512px tile；每 tile 对 ROI 相交的每图：sphericalMap 源坐标 → inside 门 →
  **边缘羽化 α = clip(到源图边缘最近距离 / (min(ih,iw)×0.12), 0.001, 1) ×
  inside**（每图 12% 短边宽渐出带——逐图几何边缘带，非 mask 羽化）。
- `accum += warped × (α·gain)`；`weight += α`；输出 =
  `accum / max(weight, 1e-8)`，clip [0,1]。
- 采样 = 双线性 + 坐标 clamp（BORDER_REPLICATE 语义等价——贴边复制防 seam
  假黑；Lumen remap flags 语义）；实现 = vImage 或手写 gather 执行期定
  （**确定性优先于微性能**——G1 腿级双跑逐位为硬门）。

### KD-8 有效域裁切（merge.py:100-117 直译；恒 on）

- valid 掩码 → **≤1024-cell min-pool 网格**（保守：一格任一像素无效即无效格，
  `minimum.reduceat` 语义的分块最小）→ **最大全有效矩形** = 直方图栈算法
  （逐行高度 + 单调栈，O(cells)）。
- 找不到非空矩形 → typed `"panorama canvas invalid: ..."`（merge.py:115
  语义）；crop 记录 `[x0,y0,x1,y1]` 入 provenance 快照。
- **naive O(N²M²) 参考实现**同文件提供（golden 正本位，产线不调用）——
  G3 逐位对照锚。

### KD-9 落盘与 landStackProduct additive（共享尾段零重实现）

- `BandStreamer.FloatTIFFWriter` additive：构造（width/height/colorSpace）+
  `write(rows:)` 行带推进 + `finish()`——**既有 `writeFloatTIFF` 零 diff**
  （可内部委托或并列，既有调用零漂移负测钉死）；sRGB tag =
  `CGColorSpace(name: .sRGB)`（Mertens T2 同参）；alpha 恒 1（OQ-5）。
- `landStackProduct` additive 参 `rowProvider: ((firstRow: Int, rowCount: Int)
  throws -> [Float])? = nil`：nil = 既有 rgba 全平面路径**字节零漂移**（专测
  钉死）；非 nil = 行带路径（写盘段二选一，sidecar/provenance/命名段全复用）。
  pano 传行带闭包（crop 后区域行带直读）。
- pano 分账：tag `pano` → `<base>_pano.tif`（M5-3-01 defaultTag）；provenance
  快照回写 `panoCanvas/panoGains/panoCrop`（M5-3-01 KD-7 字段消费）；
  alignment 标签 = per-source `"reference"` / `"inliers=<n>"`（确定性字符串，
  provenance `alignment` 数组语义）；holeFraction = 0（恒裁后无洞语义）；
  warnings = 增益 clip 触发记录（可空）。

### KD-10 runPanoLeg 编排与进度 bump 点（stepTotal 3N+6 消费）

- 编排：extent **不做一致门**（异视点合法——与 Mertens/HDR 的关键差异，
  DECISIONS 记录）+ N∈2...32 腿级 guard → 逐源 render/编码/staged/预览灰度
  （特征步 N bump）→ M5-3-01 链（匹配/BA/波校正 1 bump → 画布/ROI 1 bump →
  增益 1 bump）→ pass 1 几何 + crop → pass 2 tile 融合（融合 N bump，
  tile-paced 补足——Mertens band-paced 同形）→ 行带直写 + landStackProduct
  （write/sidecar/settle 3 bump）。
- `done == total` 恒式测试钉死（N=3 合成腿全绿路径）。
- typed 三态词汇消费：alignment/disconnected（M5-3-01 词汇）+ canvas
  invalid（KD-4/KD-8）。

### KD-11 G3 分段 golden（research §4 表落地）+ G1 腿级闭环

- **G3①** `sphericalMap` vs 测试本地闭式解逐点（小画布，公式独立重算——
  与 P1 G2 渲染器同形的独立实现，防同源循环）。
- **G3②** 羽化带：已知几何 → α 带宽 = 12% 短边（带内/带外采样点表）；
  weight 归一 `accum/max(weight,1e-8)`；零权 = invalid（valid 掩码逐 tile 一致）。
- **G3③** gain 合成方程组恢复：已知增益合成重叠样本 → 求解恢复带
  （clip 上限负测：人为 ±0.6 方程 → 钳 ±0.5）。
- **G3④** `PanoCrop` 直方图栈 vs naive 逐位（多形状矩阵：L 形/双岛/满格/
  单行）。
- **G3⑤** `boundedRois` 不变式：输出 ≤200MP + 轮次 ≤8 + 收缩后每图 ROI
  仍非空。
- **G1 腿级闭环**（research G1「全链闭环轮」落点）：`runPanoLeg` 小画布
  合成腿双跑产物 **bit-identity**（全链含特征段——种子化 RNG 全握的终验）。

### KD-12 预算探针（8G 门机检；NO GATE 数值记录）

- `PanoFusionPerfProbeTests`（EXPORT，env 门 `LIGHTAMER_PERF_PROBE=1` +
  XCTSkipUnless——默认套件 skip；Mertens probe 同构）：**真产线融合驱动**
  （runPanoLeg 内部 tile 融合函数 `nonisolated static internal` 直驱——
  `mertensBandOuterFuse` 先例；零探针侧重实现）；200MP 画布 × 8 合成 staged
  源（已知真值 R/K 网格几何）。
- 分账：几何 pass / 增益 / 融合 / 写盘墙钟 + ru_maxrss 打点（`/usr/bin/time
  -l` 内核口径由 test-direct 机检 MEMFAIL 兜底；**运行门 8G**——探针轮需
  orchestrator 批准 + 监视）。
- **NO GATE**（OQ-6 同款）：数值记录入 perf.md；**越门 → GPU kernel 化另立
  plan 的决策面**，本 plan 零 Metal 面。

## read_first

1. `.work/gsd/phases/m5-3-pano/M5-3-CONTEXT.md` + `M5-3-01-PLAN.md`/
   `M5-3-01-DECISIONS.md`（七生效值 + P1 数学面词汇——typed 三态/stepTotal/
   params 三字段消费契约）
2. `/Volumes/UNITEK/Documents/Development/lumen-raw/lumen/merge.py`
   :100-117（inner_crop）/:192-315（bounded_rois/spherical_map/panorama/
   增益/tile 融合）——MIT 正本逐段对照移植
3. `LightamerCore/Sources/Stack/StackMergeService.swift`（runMertensLeg 流式
   腿先例/StagedSet/landStackProduct additive 面/stepTotal 3N+6 声明）
4. `LightamerCore/Sources/Stack/BandStreamer.swift`（writeFloatTIFF/行带
   语义/bands）
5. `LightamerCore/Sources/Stack/MertensFusion.swift`（MIT 归属注记体例 +
   sRGB 域约定）+ `StackMergeService.mertensDisplayEncodeInPlace`
   （编码 in-place 先例）
6. `Tests/LightamerTests/MertensFusionPerfProbeTests.swift`（探针 env 门/
   真产线直驱/NO GATE 程序）+ `MertensRasterDomainTests.swift`（域判别 =
   ICC tag 基亲读——pano 产物同 face 依据）
7. `LightamerCore/Sources/Decode/RAWDecoder.swift`（raster ingest 链——产物
   重导入零新机制依据，零 diff 面）
8. `.work/gsd/phases/m5-2-mertens/M5-2-02-PLAN.md`（本 plan 体例正本——
   生产腿/落盘 additive/探针/收口全先例）
9. `Scripts/test-direct.sh`（--bundle 分账/MEMFAIL 机检/批准制 --all）
10. `.work/gsd/phases/m5-3-pano/M5-3-01-SUMMARY.md`（P1 实测基线增量——
    本 plan 对账链起算点）

## 纪律（强制）

- **每任务独立提交**（Conventional Commits 全英文；只 add 相关文件）；
  新测试文件随各自任务 commit 登记进 BUNDLE-MAP（E2）+ `Project.swift`
  对应数组（L041：`tuist generate` 恒为该批最后一个动作）。
- **构建**：`caffeinate -dis` 包裹；单测标准命令 =
  `Scripts/test-direct.sh --bundle <域>`；**探针轮（T5）= 定向 EXPORT bundle
  env 门轮，orchestrator 批准 + 运行中监视（8G 门/kill 线）**；全套 `--all`
  收口轮单独申请。
- **L072**：合成 fixture 与 staged 产物一律 temp 域 + `defer` 清理。
- **L048**：golden 比较 f32 产线常数 `Double(Float(x))` 升维；G3 逐点对照
  公式用同一精度域（Float32）。
- **L014**：源平面 render 走 dedicated queue CIContext（既有 render face），
  读回前 fence 固化在源——本 plan 零新 GPU 读回面。
- **零 diff 红线自证**（T6）：`git diff <M5-3-01 终点 SHA>..HEAD --
  LightamerIOP/ LightamerCore/Sources/Sidecar/ LightamerCore/Sources/Export/
  LightamerCore/Sources/Graph/ '*.metal'` 零命中 + dependencies 块零 diff +
  Robertson/Mertens 腿体零 diff（`runHDRLeg/runMertensLeg` 函数体 diff 空）
  截屏入 SUMMARY。
- 中文标注（待核/待定/待补）一律显式；无源待核项入 DECISIONS 待供件清单。

## Tasks

### T1 PanoWarp 纯函数族（KD-2/KD-3/KD-4）

- read_first 2 → 新建 `LightamerCore/Sources/Stack/PanoWarp.swift`：文件头
  MIT 归属注记 + sphericalMap/preview_scale 回投/K 构造/scale 中位数/
  boundedRois 循环/200MP 常量/typed canvasInvalid。
- 验收：`PanoWarpTests`（IOP）——sphericalMap vs 闭式解逐点（小画布抽查 +
  z≤1e-6 无效标记）/回投矩阵恒等（预览域 K 经 inv(preview_scale) 回投 ==
  全分辨率 K）/scale 中位数锚/boundedRois 不变式五条（KD-11⑤）/typed 前缀。

### T2 PanoGain 纯函数族（KD-6）

- read_first 2 → 新建 `LightamerCore/Sources/Stack/PanoGain.swift`：采样画布
  构建/重叠方程组/锚定/lstsq/clip/参考帧增益 1。
- 验收：`PanoGainTests`（IOP）——合成方程组恢复（已知增益 → 恢复带，实测
  收窄钉）/门值正反（<80px 样本无边；0.04/0.9 边界外剔除）/锚定行/clip
  上限（±0.6 → ±0.5）/不连通图增益有解（锚定最小范数）/双跑逐位。

### T3 PanoCrop 纯函数族（KD-8）

- read_first 2 → 新建 `LightamerCore/Sources/Stack/PanoCrop.swift`：min-pool
  网格/直方图栈/naive 参考实现/typed。
- 验收：`PanoCropTests`（IOP）——直方图栈 vs naive 逐位（L 形/双岛/满格/
  单行/全无效 typed 多形状矩阵）/min-pool 保守性（一格无效 → 格无效）/
  返回值域 = 原图界 clamp。

### T4 runPanoLeg 生产腿装配（KD-1/KD-5/KD-7/KD-9/KD-10）+ StagedSet/Writer/landStackProduct additive

- read_first 3/4/5 → `StackMergeService.swift`：runPanoLeg 腿体（stub 换
  本体，dispatch 零二次编辑）+ StagedSet `readRows` + 融合驱动
  `nonisolated static internal`（探针直驱缝）→ `BandStreamer.swift`：
  FloatTIFFWriter + `landStackProduct` rowProvider additive。
- 验收：`PanoLegTests`（IOP，合成 decode 腿小 fixture）——happy path（小
  画布合成景全绿落盘）/进度恒式 `done == total`（3N+6，N=3）/typed 三态
  （异视点不重叠 → alignment/disconnected；超帽构造 → canvas invalid）/
  **双跑产物 bit-identity（G1 腿级闭环，KD-11）**/产物 sRGB tag + alpha 恒 1
  + `_pano` 分账名/provenance 快照回写三字段/`landStackProduct` nil 路径
  既有六 kind 字节零漂移负测/`writeFloatTIFF` 既有调用零漂移负测。

### T5 预算探针 + perf.md（KD-12）

- read_first 6/9 → `PanoFusionPerfProbeTests`（EXPORT，env 门）：200MP×8
  合成 staged 源真产线融合驱动分账（几何/增益/融合/写盘墙钟 + ru_maxrss）。
- 验收：批准的定向 EXPORT env 门轮跑通；数值入
  `.work/gsd/phases/m5-3-pano/perf.md`（M2-11 惯例格式 + 内存账对照
  KD-5）；**NO GATE**——越门只记观察项 + GPU 另立项建议，不阻塞本 plan
  （决策面上报 orchestrator/用户）。

### T6 G3 补齐 + G5 共存零回归 + 收口

- G3 分段 golden 落 `PanoWarpTests`/`PanoGainTests`/`PanoCropTests`/
  `PanoLegTests` 各自任务（T1-T4 已含）；本任务 = 交叉复核五靶全覆盖清单。
- 收口轮：`--bundle IOP` + `--bundle Export` 定向轮全绿（exit 0 + 零
  MEMFAIL）+ 零 diff 红线自证清单（纪律节六路 grep 截屏）+ SUMMARY（任务序/
  内存账实测/对账链 3539/22/0 + P1 增量 + 本批增量/bundle 分账）+ DECISIONS
  （KD 偏差/lstsq 实现定夺/双 pass 依据/N=2 路径观察）+ GOAL-STATE 续接点
  （M5-3-03 待启）+ TODO 同批。
- **双重验收（config `dual_acceptance = true`，m1）**：zcode subagent 独立
  验收 PASS 后 → **串行** omp 二次验收（**严禁并发**）；两路结论落
  `M5-3-02-ACCEPTANCE.md`；FAIL 回注修复批后重走验收。
- **C 档第 2 停**：执行+验收闭环后停——汇报本 plan 战果（含探针数值）+
  M5-3-03 摘要，等用户确认再启。
