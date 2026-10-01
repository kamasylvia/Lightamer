# Phase M2-7 perf.md — 蒙版体系性能账本（P3 收口批，2026-10-01）

> 口径钉死（风险节要求，跨 phase 纵比禁用）：**Debug 构建 + 进程内探针直驱真链**
> （机器 = Mac mini Apple Silicon，macOS 27，'Lightamer-dgzsvdww' DerivedData 产物；
> 样张 = `input/RAW/DSC00012.ARW` 60.2MP ILCE-7RM5；探针正本 =
> `evidence/m2-7-3/probe/`，walker/kernel 原文编译、脚手架 shim 仅复制
> `MetalContext.makeEncoder`/`maskLikeShape` 机械；计时 = `CLOCK_MONOTONIC`
> 包围 + 中位数）。GUI 实操通道环境受限（synthetic pointer 不达窗口，
> E3 同根因）→ 观察项以探针实测 + 既有 bench 引证落账，GUI-only 手感项
> 如实挂账 Manual-Only，不虚报。

## 表一 — stamping 基线复测（回归性复验，非新 bench）

| 项 | 值 | 证据 |
|---|---|---|
| stamping bench 基线 | **0.744 ms/千枚 @2560×1707**（06-03 T1 实测，基准不重跑——本 phase `DrawnMaskRasterizer` 零 diff，基线继续有效） | `phases/06-layers-masking/06-03-DECISIONS.md` |
| golden 族复归（P3 新鲜复跑） | Layers **298/3/0**（= P2 终值逐值持平；含 DrawnMaskRaster/MaskCombine/MaskFeatherAlign/FollowEdges 全族 golden） | `caffeinate -dis Scripts/test-direct.sh --bundle Layers`（25s，BUNDLE 行） |
| App 域复归（熔断一行后） | App **429/0/0**（= P2 终值逐值持平） | `Scripts/test-direct.sh --bundle App`（167s，BUNDLE 行） |
| 全套回归 | P2 终跑 **2525/16/0 / 882s EXIT=0**（M2-7-2-SUMMARY）；P3 源码增量 = 熔断一行（App 域已定向复归绿），Core 零 diff | M2-7-2-SUMMARY + 本批 App/Layers BUNDLE 行 |

## 表二 — 缩略 pass（OQ-11 观察项）

| 项 | 值 | 处置 |
|---|---|---|
| 单格渲染耗时（112px，drawn/parametric/raster 各一） | **未测得**——探针路线不可达（`MaskThumbnailRenderer` 依赖完整 Core framework 链，swiftinterface 拉入 libwebp 模块闭包无法独立编译；GUI 路线需面板内已有蒙版内容，无 pointer 注入无法绘制蒙版 → 无缩略可渲） | **挂账 Manual-Only**（随 M2-7-3-ACCEPTANCE-INPUT 清单；E3 五点同批） |
| 面板 20 格滚动总耗时 | 同上未测得 | 同上 |
| 复杂度对照（架构面） | O(缩略像素) 单入口复用 assembleUnmasked + LRU 键缓存（stableHash⊕size⊕dims），零 queue/device 创建（P2 AC9 grep 钉）——架构预算面成立，运行时数字留实测 | M2-7-2 AC1/AC9 |

## 表三 — Follow Edges 边缘图：首算 / 缓存命中（探针实测 ×10 中位）

| 项 | 值 | 对照 |
|---|---|---|
| 边缘图首算（GPU Sobel + L014 fence 读回 + ≤512 箱式降采样，preview 桶 2560×1707） | **中位 6.1 ms**（min 5.7 / max 7.3，×10；首调 PSO 编译噪声 74.8 ms 一次性） | 单帧预算 16.7 ms @60fps：**达标**（冷态亦 < ½ 帧） |
| 缓存命中后（walker-only，同层连笔语义） | **中位 ~0.001 ms**（×100 seed 网格；命中率语义 = `PipeCoordinator` prefixHash：imageID⊕base⊕下层 id+chain records⊕IOP instances——**mask append 不在折叠集**（`instances` = IOP 模块实例非 mask），同层连续 seed 恒命中，下方层编辑/参数变更才翻失） | 命中收益 ≈ 6000×；KD-2「100 枚 seed 计时」以 ×100 网格覆盖 |
| 100MP FULL 读回（判据③语境） | FULL 9504×6336 单发 **80.3 ms**（> 1 帧）——但 **P2 seam 只跑 preview 桶**（`followEdgesSurface` resolution: .preview + `currentBucket ?? cap`），FULL 读回不在出货路径 → 判据③ **n/a（如实记录，非豁免）**；若 V2 把边缘图上 FULL 需改 stroke-local 窗口裁读 | KD-1 判据③ |
| 边缘图质量（真样张目测） | `field_vis.png`：脊线连续（建筑直边/灯笼圆轮廓可辨），非降采样碎裂 | 走查裁决输入 |

## OQ-11 预算项逐条对照（CONTEXT D-M2-7-CONTEXT-11）

| 预算/观察项 | 结论 | 证据 |
|---|---|---|
| Follow Edges 边缘图 per-image 一次预计算随缓存失效 | **达标**（冷 6.1 ms < ½ 帧；失效键语义实现正确） | 表三 |
| 缩略图 pass O(缩略像素)/格 | **架构面达标 / 运行时未实测** → Manual-Only 挂账 | 表二 |
| 手柄 overlay display 腿不进 pipe 与 60fps 解耦 | 既有架构（06-07 display 腿先例）未重测——**观察项挂账**（随 GUI 验收轮） | — |
| 双羽化手柄拖动实时性（超标 fallback = 拖动中缩略窗口预览） | **GUI 实操未取得**（E3 五点之一，pointer 注入不可达）→ fallback 未启用、挂账 Manual-Only | M2-7-2 DECISIONS §四 |
| Follow Edges 交互手感（流线追踪） | **熔断触发**——streamline 真样张断链（判据②成立）：8 景盒 × 2 阈值链长 0-3 点、100-seed 网格 82/100 空、场分辨率/步长扫频 0/3 功能链；snap 12px 触达内确定性 2 点贴边线。冷延迟 6.1 ms（判据①远内）。**默认值翻 `.snap`（`60582c3`），walker 保留 V2** | `evidence/m2-7-3/`（ev_*.png + probe.log） |
