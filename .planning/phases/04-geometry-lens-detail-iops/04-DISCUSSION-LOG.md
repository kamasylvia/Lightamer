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
