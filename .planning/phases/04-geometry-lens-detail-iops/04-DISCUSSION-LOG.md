# Phase 4: Geometry, Lens & Detail iops - Discussion Log

> **Audit trail only.**

**Date:** 2026-09-20
**Phase:** 4-Geometry, Lens & Detail iops
**Mode:** 保活巡检自动推进（YOLO 授权延续；与 Phase 2/3 同模式）

---

## 过程

- 巡检触发，用户离线未应答灰色地带 multiSelect（延续 Phase 2/3 模式）。
- 处置：自主定稿，重点拍板 ROADMAP 遗留 open decision（Lensfun C++ vs XML-data-only）。

## 决策摘要

| 域 | 决策 |
|---|---|
| 镜头校正 | 三层：CIRAW 内嵌直通 + 手动滑块 Metal warp + Lensfun XML 只读（数据不入 git，后置）|
| crop/rotate 语义 | 显示窗口变换（ROI 前向收缩），不实际裁内存；记入 history sidecar |
| local contrast | 复用 03-05 EIGF/guided filter（clarity 标准路径），不新写双边 |
| sharpen/highpass | USM 变体（GaussianBlur 复用）|
| equalizer | 复用 toneequal CorrectionLUT 模式 |
| ROI 协商 | crop 前向收缩 + detail 后向扩展——PipeCacheKey.roi 首次实际生效（架构验收核心）|
| 交互 | EditorMTKView overlay 手柄 + Vision framework 自动水平检测 |
| deferred | liquify/retouch → Phase 6；Lensfun C++ → 永不（依赖红线）|

## 04-01-T0 ROI 协议定稿（2026-09-20，executor 确认三件实施口径）

- **口径 1（D-G2 读法）**：按 04-01-PLAN T0 实施——ROI 协商收缩，下游平面按窗口尺寸原生分配（无全幅 buffer、无窗口拷贝浪费）。
- **口径 2（roiHint 形状）**：`RenderPipeline.process(roiHint: ROI? = nil)`，nil = 全幅；Phase 4 仅测试/探针面，UI zoom-ROI 另议。
- **口径 3（验收口径）**：SC#4 四断言为本 plan all-green 闸门 + `04-VALIDATION.md` Wave 1 行签核；04-02..04-05 以本 plan 全绿为开工条件。
- **dt 依据**：前向 `pixelpipe_hb.c:3368-3405`（get_dimensions，直通分支 `:3378-3384`）+ 后向 `pixelpipe_hb.c:2085-2096`（递归体 modify_roi_in + processed_roi_in/out 盖章）；crop 实例 `crop.c:517-531`（out 收缩）/`:576-592`（in 偏移回取）。
