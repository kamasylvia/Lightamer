# Phase 7 — Discussion Log（SC 终核对 + 移交）

> 本文件为 Phase 7 签核记录（07-3 T5 新建——SC#1-5 终核对节 + Phase 8 移交清单，
> 体例对齐 06-DISCUSSION-LOG 终节）。计划期讨论正本 = `07-CONTEXT.md`
> （D-07-CONTEXT-1..6 用户裁决，2026-09-24）；各 plan 执行期决策正本 =
> `07-1/07-2/07-3-DECISIONS.md`。

---

## SC#1-5 终核对（Phase 7 签核，2026-09-24）

> 证据指针口径：测试名 / 文件 / FINDINGS 行 / manifest 节 / perf.md。缺口零静默，
> 逐条注记。

### SC#1 — 主体隔离双层可用交互 ✅

> ROADMAP 原文：subject lifting (people/animals/food/generic objects, class-agnostic)
> via `VNGenerateForegroundInstanceMaskRequest` … iterative refinement usable
> interactively。

| 判据面 | 证据 |
|---|---|
| 层 A 一键生成（class-agnostic，离线） | 07-1 T2/T3 语义门 10 测试（合成图 IoU ≥0.9 + 背景环 ≤0.1 + 双主体 subset 双向 + noSubject typed）；07-3 T4 GUI 真机：IMG_4276.CR3 真实推理 bake `ai-subject-<uuid>.png`（FINDINGS 07-3 节「层 A 一键主体蒙版」行） |
| 层 B iterative refinement（tap/box 交互） | 07-1 T3 服务逻辑全测（seedPoint/seedBox/含排点/13-11 预算/Y 翻转）；07-3 T2 视口第 4 编辑模式：`LayerUIWiringTests.testSegmentRouteMutexExhaustive` + `.testSegmentSessionBudgetAndYFlipWiring`；GUI 手感 = Manual-Only（见 VALIDATION 表——ready 态入口跃迁被 GUI-20 beta 资产供给阻断，数据腿全钉） |
| 确定性门 | 07-1：层 A gpuPinned 逐字节恒等（进程内 + 跨进程 byteIdentity）；层 B default（不 pin）探针 2/2 逐字节 equal（perf.md「pin 探针补充数据」）——设备面 beta 现实见 D-07-1-T1-2 |
| instance 多主体勾选 | 07-1 subset 双向断言 + 07-3 T1 `InstancePickerOverlay`（checkbox 子集 + 预览高亮，零额外推理）；真机浮层 = Manual-Only（需多主体样张，FINDINGS 07-3 Manual-Only 表） |

**判定：PASS**（交互层 07-1 服务 + 07-3 UI 全交付；scribble/lasso = D-07-CONTEXT-4
v1 后升级缝——种子枚举已预留，属计划内圈定非缺口）。

### SC#2 — 磨皮保细节不塑料 ✅

> ROADMAP 原文：frequency-separation retouching … natural-looking skin that preserves
> pores/edges — no plastic look。

| 判据面 | 证据 |
|---|---|
| 频率分离数学 | 07-2 T4：float64 参考 parity 6 case × 6 fixture 双闸 <1e-5（低频腿实测 7.2e-7；manifest skinSmooth 节）；恒等三元组逐字节（a=0 blit / mask nil==全一 / 平场 DC-1） |
| 防塑料感机制 | raised-cosine 阈值式高频衰减（D-07-CONTEXT-6 / D-07-2-T2-1）——低幅高频（色斑/噪点）强衰减、高幅高频（毛孔/发丝/边缘）保留；`testSkinSmoothEnabledCompositeDiffersFromDisabled` 内容级启用态差异断言（PanelWiringTests） |
| 定位皮肤（landmarks + personSeg） | 07-2 T3 SkinRegionLocator 纯 Swift 几何 8 测试（hull − 五官保护区 ⊗ personSeg + yaw 门 + 多脸 union）；07-3 T3 `testSkinLocateCommitWritesMaskSlotOneCommit`（commit 通道） |
| pore-level 人眼目检 | **Manual-Only pending**（现有 3 张样张均无含人脸样张——07-2 遗留 1 项并案 07-3 复验，FINDINGS 07-3 Manual-Only 表「磨皮 pore-level 目检」行）；数据腿（parity + 三元组 + 启用态差异）已钉，目检不阻塞签核（L011 口径挂账） |

**判定：PASS（数据腿）+ Manual-Only 挂账 1 行**（真模型腿 GUI 走查在 T4 完成 skinSmooth
面板入层链 + sidecar 链证据；pore 级人眼质量判据待含人脸样张补采——与 ColorChecker
补拍同批，TODO 登记）。

### SC#3 — AI mask 接入调整层（AI-06）✅

| 判据面 | 证据 |
|---|---|
| bake 为 raster mask（IOP-MASK-03 通道） | 07-1 T4：`AIMaskResample.upsampleToDecodeFrame`（双线性像素中心 + 对齐断言）+ `RasterMaskStore.bake(featherRadius:)` 羽化增件（默认 0 逐字节零改动）+ RasterMaskRoundTrip 9/9（AI 平面 uint16 恒等） |
| 挂任意 Phase 6 调整层 | 07-3 T1：`AIMaskEditing` 单通道（生成 → bake → `MaskSpec.raster` 写选中层 mask 槽 = 恰 1 条 stackSnapshot 结构项）；`testAIMaskCommitOneSnapshotUndoAndRefineOverwrite`（⌘Z 恰 1 + undo 还原空态 + PNG 落盘）；GUI 真机 ⌘Z（sidecar position 1→0，层保留 NDE-1，FINDINGS 07-3 节） |
| parametric 直挂腿 | **D-07-CONTEXT-3 注记**：v1 唯一忠实通道 = raster 烘焙（Vision mask 是像素非参数曲线）；parametric 语义曲线预设（肤色 hz 曲线）= v2（REQUIREMENTS AI-06 注记已落）——计划内圈定非缺口 |
| round-trip 存活 | `testAIMaskSourceFileIdentity`（源文件身份 round-trip）+ AIMaskEditPaths 五路径 sidecar round-trip + GUI 真机 sidecar history/undo/redo |

**判定：PASS**。

### SC#4 — 可编辑非黑箱（AI-07）✅

| 判据面 | 证据（AIMaskEditPathsTests 6/6，内容级 L020） |
|---|---|
| 手动边缘 refinement（drawn 修补） | `testDrawnPatchDifferenceRepairDirection`——brush union − ellipse difference 组 ⊗ raster 交，drawn 差集移除方向 + raster 界不复活 |
| 与其他蒙版组合（parametric ⊓） | `testParametricIntersectTightensRaster`——blendif luma 窗收紧至左上象限（采样工作平面同源） |
| 反向 | `testInvertFlipsEffectivePlane`——ref toggle 翻转载入平面，toggle 回 = 逐字节还原（盘上像素永不变） |
| 羽化 | `testFeatherRebakeSoftensEdgesAndFlipsIdentity`——新文件身份（hash 翻转）+ 边界列均值下降/内部稳定 |
| refine 重生成 | `testRefineRegenerateOverwritesSameMaskIDWithCacheBookkeeping`——同 maskID 覆盖 + MISS-then-HIT 缓存记账（零新缓存类）+ 收缩方向断言 |
| 生成参数不落盘 | `testSidecarSchemaZeroUpgradeAIParamsNeverPersist`——移除 mask 子树后层记录逐字节还原；编码字节只含 fileName/maskHash/invert，无 quality/seed/refine 键 |

**判定：PASS**——生成即 bake，产物进入与手画蒙版完全相同的编辑/合成/持久化世界
（AI-07 红线兑现）。

### SC#5 — 离线 / 延迟 / 缓存 ✅（措辞按 D-07-CONTEXT-1 修订版核对）

> 修订后原文：layer A … run locally on the Neural Engine (offline, no network);
> layer B … requires a one-time model download on first use, gated by assetStatus UI
> with layer A as the always-available fallback (D-07-CONTEXT-1); latency on a 100MP
> image is acceptable for interactive use (cache result so re-edit does not re-run
> Vision)。

| 判据面 | 证据 |
|---|---|
| 层 A 离线可用（OS 内置模型无下载） | perf.md：层 A/personSeg/faceLandmarks 均 OS 内置，真机下载前置不存在；GUI 真机层 A 在层 B 未下载态全程可用（FINDINGS 07-3「层 B 拒绝后入口置灰，层 A 不受影响」行） |
| 层 B 一次性下载 + assetStatus 三态门控 + 层 A fallback | 07-1 T3 AIAssetStore 状态机矩阵（downloading 中态/失败可重试/ready 幂等）+ AIDownloadPrompt 首启提示；07-3 T1 `testLayerBEntryGateStates`（needsDownload→引导 / downloading→spinner / ready→进入 / failed→retry）+ GUI 真机三态走查（prompt 弹窗 zh / declined 持久化 / 置灰引导，FINDINGS 07-3 节） |
| 100MP 交互延迟 | `.work/07/perf.md` 基线：**warm 单次生成全 ≪1s**——层 A 15-16ms / 层 B accurate 85-126ms / personSeg accurate 42-44ms（GFX 102MP 实测）；cold = 进程内模型首编译（层 A 最高 5.5s，一次性，后台 Task + spinner 承接） |
| 重编辑不重跑 Vision（缓存） | bake 持久化天然满足：产物 = `.lra.masks/<maskID>.png` 落盘，重编辑消费已 bake raster（Phase 6 mask 缓存链）；精修重跑 = 用户主动（refine 点），同 maskID 覆盖 + 既有 maskPosition/maskPlane 缓存键 MISS/HIT 记账实证（AIMaskEditPaths refine 路径） |
| 遗留观察 | **GUI-20（低-中）**：dev-signed Debug 构建下层 B `downloadAssets()` 无错误返回但 assetStatus 恒 notReady——macOS 27 beta 资产供给对 development 签名不放行（与 07-1 测试宿主 entitlement 同根）；三态 UI 行为诚实（引导态保持、无静默假就绪、无崩溃）。**待 Developer ID / 正式分发签名复验**（v1 后观察项，TODO 登记） |

**判定：PASS**（SC#5 门按 07-1 D-07-1-T1-3 建议 = warm 路径裁定；cold 首编译为一次性
成本，UI 已承接）。

---

## Phase 8 移交清单（AI mask 消费端 + Phase 7 遗留对表）

### ① AI mask 消费端接口（HDR/Effects 阶段消费面）

- **`RasterMaskRef`（raster 通道唯一入口）**：`.lra.masks/<maskID>.png` 16-bit 灰度
  旁挂 + decimal-String `maskHash`（UInt64String 格式锁）+ `invert` 位——AI 产物与
  手画产物在数据面不可区分（07-3 T4 GUI 真机 + sidecar 零升级断言实证）。Phase 8
  HDR merge/focus stack 若需蒙版限定（如 ghosting 抑制区），直接消费此形态。
- **层栈 API 面**：`LayerStack` mutation 全套 + `MaskSpec.raster/parametric/drawn`
  三 payload ⊗ 装配（`MaskCombiner.effectivePlane`）+ history 双轨（`__layerStack__`
  结构项 / layerScope 参数项）。AI 生成路径（`AIMaskEditing.commitRasterMask`）即
  该 API 面的一个消费者——Phase 8 效果模块挂层 mask 无需新机制。
- **缓存面**：零新缓存类——AI 产物以 maskPlane/layerPlane 级进入既有
  maskPosition/maskPlane/blendTriple 前缀键 + enforceBudget 五档；`PipeCoordinator`
  display tint 已扩展至任意 payload（raster/parametric 回落 effectivePlane，07-3
  T1 commit）。
- **skinSmooth 66.5 槽位**：V50Order 66.5（soften 66.0 / splittoning 67.0 之间，
  非 dt 行首例，表头双标记）——Phase 8 watermark 77.0/78.0 邻域核对：66.5 与 77+
  无槽位冲突；非 dt 行纪律（只增不改、V50OrderTests strip-to-93 零移动钉常驻）。
- **AIMaskService 复用面（pluggable segmentation）**：`LightamerCore/Sources/AI/`
  服务层（层 A/B/personSeg/faceLandmarks 共用 handler + fence + 后台 Task 骨架），
  v2 高保真自定义模型后端按 D-07-CONTEXT-1 Reversibility 独立插拔，不动消费端。
- **Vision 推理基建**：fence 输入腿（L014 固化于 `AIMaskInput`）+ 设备选择骨架
  （`setComputeDevice` + typed 拒绝校验）——未来 v2 AI 评分/追色共用。

### ② 07-1 遗留对表（承接 07-1-SUMMARY 遗留节）

| 遗留项 | Phase 7 终态 |
|---|---|
| 层 B 端到端测试宿主 entitlement 阻断 | **GUI 轮真机复验完成**：下载三态 UI 全走查（prompt/declined/引导态）；ready 态跃迁被 GUI-20（beta 资产供给对 dev-signed 不放行）阻断——服务逻辑全测 + 状态机矩阵钉住，**剩余复验点 = Developer ID 签名下资产下载**（v1 后观察项） |
| 层 A 512 级分辨率（标签合成腿） | **维持现状**：`generateScaledMask` beta 双重损坏未修（D-07-1-T2-4），层 A 走 `allInstancesMask` 标签合成（512 级 + bake 双线性上采样）；GUI 真机 IMG_4276.CR3 主体蒙版 overlay ΔR 量化达标（10.31% 变化像素），实用精度足够；Apple 修复后切回 scaled（升级缝保留） |
| Vision beta API 漂移面（scaledMask 偏移/subset/层 B pin 崩/CPU 不在 supported） | 全部升级缝保留（`#available` 下可收回）；正式版复验 = v1 后观察项 |
| 真模型腿宿主 skip（层 B 2 条 + 卡通脸 1 条） | **部分闭环**：层 A 真机实证；层 B ready 跃迁 + 磨皮真人像目检仍挂（GUI-20 + 样张缺失）——见③ |

### ③ 07-3 遗留登记对表（正本 FINDINGS 07-3 节 + VALIDATION Manual-Only 表）

| 项 | 级别 | 处置 |
|---|---|---|
| GUI-19 层链行不显示 | 中 | 添加模块到图层后模块行未在 Inspector 层链列表出现（sidecar 链证据确凿，渲染/刷新路径嫌疑）——挂 UI 打磨轮（AX 对 tap-gesture 行不可驱动，复验需真鼠标） |
| GUI-20 层 B 资产供给 | 低-中 | dev-signed 构建下载无错误但 notReady——待 Developer ID/正式分发签名复验（v1 后）；UI 下载卡顿超时提示 = v1.1 候选 |
| tap-to-segment 手感 | Manual-Only | 数据腿全钉（预算/互斥/Y 翻转 5 测试）；手势对 CGEvent/AX 均不可驱动 + ready 入口被 GUI-20 阻断——待资产可下载后真机复验 |
| 磨皮 pore-level 目检 | Manual-Only | parity <1e-5 + 三元组 + 启用态差异已钉；需含人脸样张（现有 3 张均无人脸）——与 ColorChecker 补拍同批 |
| instance 勾选浮层真机 | Manual-Only | 子集语义 07-1 双向断言已钉；需多主体样张（酒瓶单主体未触发浮层，v1 单主体直接 bake 路径已真机实证） |
| 保护区显示 toggle 视觉 | 已覆盖 | overlay 通道 = raster 染色 ΔR 量化达标（同一通道，FINDINGS 07-3） |
| GoldenColor flake | 既有 | testCrossConsistencySyntheticTarget 负载态偶发（07-2 遗留 4，与 AI 改动无关）——TODO 既有行跟踪 |
