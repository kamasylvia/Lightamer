# Phase 4: Geometry, Lens & Detail iops - Context

**Gathered:** 2026-09-20
**Status:** Ready for planning — 决策由保活巡检以最佳判断定稿（YOLO 授权延续；可审阅推翻）

<domain>
## Phase Boundary

Geometry（crop、rotate/perspective、lens correction、flip/orientation）+ Detail（sharpen、local contrast、highpass/soften、equalizer/detail enhancement）8 项需求。核心架构目标：**ROI 协商端到端**（crop 前向收缩 + sharpen 后向扩展的最小区域处理）。

**Phase 4 不做**：liquify/retouch（Phase 6，依赖蒙版）、色彩类模块（Phase 5）、Lensfun C++ 链接（依赖红线）、scRGB/HDR 变更（Phase 8）。

</domain>

<decisions>
## Implementation Decisions

### 镜头校正数据源（ROADMAP 遗留 open decision 本阶段拍板）
- **D-G1:** 镜头校正 = **三层策略**：(a) CIRAW 内嵌校正直通（Phase 1 已实证 CIRAW 对支持的镜头自动应用 DNG opcode 校正——已解码数据里已含）；(b) **手动滑块校正**（畸变 k1/k2、横向 CA R/B 位移、渐晕量——Metal warp + 逐通道偏移 kernel，无外部数据库依赖）；(c) **Lensfun XML 数据只读集成**（解析 lensfun XML 数据库匹配镜头 → 参数喂给同一 Metal warp——不链 C++，数据文件后置下载不入 git）。默认 (a)+(b) 全启用，(c) 作为 Phase 4 后半任务（XML parser + 匹配逻辑，数据库文件用户自备或小体积子集内置）。 — **Reversibility:** reversible — (c) 是纯增量。
- **D-G2:** crop/rotate 管线语义 = **crop 作为显示窗口变换**（ROI 前向收缩，管线内 buffer 不实际裁切内存——与 dt 的 CLIP 处理一致，避免 decode 后内存拷贝）；rotate/perspective 为 Metal warp（透视 4 点单应矩阵）。输出 window 记入 sidecar history（非破坏性，原图永远保留）。 — **Reversibility:** costly — ROI 语义与缓存 key 的 roi 字段联动（Phase 2 PipeCacheKey 已预留）。

### Detail 模块实现路径
- **D-G3:** local contrast（clarity）= **复用 Phase 3 EIGF/guided filter 基建**（03-05 已移植的 edge-improving guided filter 正是 clarity 的标准实现路径——大半径 guided 分解 + 细节层增强），不新写双边滤波。highpass/soften = USM 变体（复用 GaussianBlur）。 — **Reversibility:** reversible。
- **D-G4:** sharpen（USM）= GaussianBlur + 线性组合 kernel（amount/radius/threshold 三参），equalizer/detail enhancement = 多频段分解复用 toneequal 的 CorrectionLUT 模式（Phase 3 已验证的 band→LUT→apply 架构）。全部走 ParityGate 双闸 + golden 双轨（dt-cli fixture parity + ColorSync 回归）。 — **Reversibility:** reversible。

### ROI 协商端到端（本阶段架构验收核心）
- **D-G5:** ROI 语义 = **crop 前向收缩 output ROI**（modifyROIOut 返回裁切后窗口）、**sharpen/blur 后向扩展 input ROI**（modifyROIIn 按核半径外扩）——Phase 2 PipeCacheKey 的 roi 字段首次实际生效。验收 = 树内断言（crop 后下游模块看到的纹理尺寸=裁切尺寸）+ 内存断言（sharpen 只按需外扩不取全图）。 — **Reversibility:** costly — ROI 协商协议是 PipeCacheKey 的一部分。

### 交互与面板
- **D-G6:** crop/rotate 交互 = **EditorMTKView 内 overlay 手柄**（角落拖拽 + 旋转手柄 + 网格线 + 比例锁定），实时 PREVIEW 重渲染经 PipeCoordinator（D-C3 档位量化防抖）。面板 = D-T6 框架扩展（crop 比例下拉/角度滑块/透视四点）。 — **Reversibility:** reversible。

### the agent's Discretion
- Metal warp 的具体插值方案（双线性 vs 单应采样）、flip 与 rotation 的合并优化、auto-detect 算法（水平线检测用 Sobel+Hough 简化版还是 Vision framework VNDetectHorizonRequest——**倾向 Vision framework**，Apple 原生零依赖）、XML parser 选型（Foundation XMLParser 即够）——planner/executor 决定。

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

- `.planning/ROADMAP.md` §Phase 4（成功标准 4 条 + Lensfun open decision 本阶段拍板 + liquify/retouch Phase 6 注记 + 风险 CIRAW-3、METAL-6/7、PERF-5）
- `.planning/REQUIREMENTS.md`（IOP-GEO-01..06 [05/06→Phase 6]、IOP-DETAIL-01..04）
- `.planning/phases/02-pixelpipe-core-color-management-history-stack/` — PipeCacheKey roi 字段、ROI 协商协议、processRec 结构
- `.planning/phases/03-tone-filmic-iops/03-05-SUMMARY.md` — TilingPlan/EIGF/CorrectionLUT 模式（local contrast 复用）
- `/Volumes/UNITEK/Documents/Development/darktable/src/iop/{crop,rotatepixels,aspherical,lens,clahe,hazeremoval,highpass,sharpen,equalizer}.c` + `data/kernels/` 对应 OpenCL
- Apple: `VNDetectHorizonRequest`（水平自动检测）、`VNGeneratePerspectiveTransform`（透视）、Metal warp patterns
- `LESSONS.md`（L005/L008/L010/L013/L018）
- `AGENTS.md`

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `IOPModule`/`ModuleBox`/`ModuleRegistry`/`PipeCoordinator` seams — 新模块即插即用
- `GaussianBlur`（Deriche IIR + 双平面三 pass）— USM/local contrast 直接复用
- `HistogramReduce`（两趟原子归约）— levels auto 模式 + crop 亮度统计
- `TilingPlan` — 大核模块（toneequal 首战已验证；local contrast 大半径同场景）
- `PipeCacheKey.roi` 字段 — ROI 协商的缓存联动（首次实际生效）
- `Vision framework` — VNDetectHorizonRequest（rotate 自动检测，Apple 原生）

### Established Patterns
- `.swift + .metal` 文件对 + ModuleRegistry 注册（v50 槽位：crop/flip 在 rawprepare 前段处理、lens ~10.0、detail 后段 16-18.0）
- ParityGate 双闸 + golden 双轨（dt-cli fixture parity + ColorSync 回归）
- D-H1 drag-end 三件套 → history commit → 缓存失效链

### Integration Points
- crop/rotate → PipeCacheKey.roi（缓存正确性）
- lens correction warp → CIRAW 解码后第一个几何模块
- detail 模块 → toneequal 后的 v50 后段（16-18.0）
- EditorMTKView overlay 手柄 → PipeCoordinator → rerender

</code_context>

<specifics>
## Specific Ideas

- ROI 协商是本阶段架构验收核心（ROADMAP SC#4）——crop 前向收缩 + detail 后向扩展的端到端证明比单个模块的 parity 更重要。
- Lensfun XML 只读集成：数据库文件（~30MB 全量）用户自备或提供精简子集，不入 git。
- Vision framework 的 VNDetectHorizonRequest 可直接服务 rotate 自动检测（Apple 原生零依赖，与 D-G1 Vision 倾向一致）。

</specifics>

<deferred>
## Deferred Ideas

- liquify — Phase 6（蒙版依赖）
- retouch/heal/clone — Phase 6
- Lensfun C++ 链接 — 依赖红线永不
- perspective 自动检测（VNPerspectiveTransformation）— 按需评估

</deferred>

---

*Phase: 4-Geometry, Lens & Detail iops*
*Context gathered: 2026-09-20（保活巡检自主定稿，YOLO 授权延续）*
