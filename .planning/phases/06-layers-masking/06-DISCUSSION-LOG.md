# Phase 6 Discussion Log

> 签核体例对齐 05-08-PLAN T6（SC 逐条核对 + 证据指针落账）。本文件由 06-05（前半签核）创建；
> liquify/retouch 签核节由 06-06/06-07 收口时追加。

## Phase 6 前半签核（2026-09-24，Plan 06-05 收口）

**范围**：SC#1（层独立运作）、SC#2（drawn/parametric/raster mask + combine）、
SC#3（blend 模式 + opacity 合成）、SC#5 前半（层栈持久化 round-trip）。
**不在本签核范围**：SC#4 liquify/retouch——**liquify 已由 06-06 交付并验收**
（SUMMARY 06-06：warp parity 0.0 / 位移场解析 ≤2.4e-7 / 映射器 roundtrip 2.5e-10 px /
GUI 复验 4 截图），其签核证据随 06-07 终签核合并；**retouch 在 6-7**。

### SC#1 层独立运作（LAYER-01/02）✅

- 层 K 参数隔离：`LayerUIWiringTests.testLayerParamEditIsolatedFromBase`——层 K exposure
  编辑后 base 实例 paramsHash 逐字节不变 + 层链持新值 + 恰 1 个 layerScope 项 + undo 还原。
- 内容级：`LayerUIWiringTests.testMaskedLayerRenderChangesInsideMaskOnly`——层内容只在蒙版内
  改变渲染、蒙版外与无层基线逐字节相同（L014 fence）。
- 同 iop 不同参数/层缓存语义：06-01 证据（LayerCoreTests 11 / LayerCacheTests 10 /
  LayerCompositeTests 8，恒等三元组逐字节）+ 06-02 GPU parity 全表 <1e-5。
- UI 路由零串扰：24 既有面板在 layerScope 会话下全部正确分发
  （`LayerUIWiringTests.testAllProvidersResolveUnderLayerScope`）+ 全量回归 764/0fail。

### SC#2 drawn/parametric/raster mask + combine 可用（LAYER-03 / IOP-MASK-01..04）✅

- 四形态解析 golden：DrawnMaskRasterTests（ellipse/path/gradient ≤1e-6、旋转羽化带 1.34e-6
  分层门 5e-6、brush 三档剖面 ≤4.2e-7、eraser 负 flow、tile 缝 0.0）。
- parametric：ParametricMaskParityTests（6 case × 6 fixture；平场二元门；L023 往返）。
- raster：RasterMaskRoundTripTests（16-bit 灰度 PNG uint16 恒等 + hash 校验 + 三失败腿降级）。
- combine 五式：MaskCombineTests（逐式 <1e-6 + 两圆解析面积 golden + 嵌套组）。
- 三类 ⊕ 单一有效平面：06-04 T5（drawn⊗parametric⊓raster <1e-5/1e-6 + 编辑记账双向独立）。
- UI 端到端：本轮 GUI 轮 brush 描画 + chip + overlay tint + 跨重启蒙版恢复
  （FINDINGS 06-05 节，`2026-09-24-0605-t6-mask-stroke.png` / `t6-overlay-on.png`）。

### SC#3 blend 模式 + opacity 合成正确（LAYER-05）✅

- 公式面：06-02 全模式 GPU parity <1e-5（算术）/ pow-chain 地板门（感知，Jz 探针 <1e-6）+
  dt 三证据 54/54（blendop_params 420B + params ok + 平场 PFM）+ REVERSE 逐值一致。
- 三元组装：compositeLayer 单 kernel（mask × blend × opacity，mask 预乘有效 opacity 契约）
  + 恒等三元组逐字节（op=0/op=1/空层/禁用层）。
- UI 面：LayersPanel blend Picker（17 模式 zh/en）+ opacity 滑块 D-H1（拖动实时、松手恰 1
  结构项）——`LayerUIWiringTests.testLayerPropertyDragCommitsOnceAndUndoRestores`。

### SC#5 前半：层栈持久化 round-trip（LAYER-07 的层维度）✅

- **真 RAW E2E**：`LayerE2ERoundTripTests.testRealRAWRoundTripThroughHistoryAndSidecar`——
  DNG（23MB 真实 RAW）→ 3 层（异 blend/opacity）+ brush/gradient 蒙版 + 层内参数
  （layerScope 型）+ 重排 → undo×2 → 侧车写出（drift 自查通过）→ **全新 coordinator 走真实
  restore 路径重开** → 层 UUID 恒等 + 链参数逐字节 + mask stableHash 恒等 + history
  位置/条数恒等 + **渲染逐字节恒等**（L014 fence；1024 长边 PREVIEW bgra8 平面）。
- 侧车面：Phase6SidecarTests（v1 兼容读 / 层感知漂移 / 未知 op 层降级 / stackSnapshot
  双路径 round-trip）+ 06-05 C0 的锚点 mask 折叠（D-06-05-C0-2）。
- GUI 面：跨 quit/restart 两层 + 蒙版恢复（FINDINGS 06-05 节 `t6-overlay-on.png`）。

### 拖动 60fps（层维度）✅（Debug 实测达标）

- 10 层全启用链稳态拖动（2560 PREVIEW，层 K tick/帧）：**Debug median 15.6–16.4ms
  < 16.6ms**（多轮复测一致；`.work/06/perf.md` 账 + `LayerDragPerfTests`
  .testTenLayerSteadyStateDrag；门 = PERF-5 口径回归界 Release <20ms / Debug <120ms，
  无静默放宽）。

### 前半缺口台账（零静默）

| 缺口 | 处置 |
|---|---|
| GUI-14 添加模块菜单空链塌缩不可见 | ✅ 当场修复（moduleListHeight 下限）+ 回归绿 |
| GUI-15 显示蒙版请求不触发重渲 | ✅ 当场修复（setMaskOverlayRequest 内 re-render） |
| GUI-16 三个 SF Symbol 缺失致图标空白 | ✅ 当场修复（circle.dashed/line.diagonal/circle） |
| GUI-17 showmask 按钮偶发不可见 | ⏳ 人工复验（FINDINGS Manual-Only；不阻塞——overlay 请求路径由 row-tap 验证） |
| cmd-drag 调 brush size 未实现 | ⏳ 6-7 前补（参数环面板等效能力已交付） |
| gradient/ellipse/path viewport 手势细粒度 | ⏳ 人工复验（数据腿/kernel 已由 06-03/04 单测钉住） |
| 100MP 蒙版笔画延迟 | ⏳ 性能轮（本轮 24MP 实测无卡顿） |
| SC#4 retouch | 6-7 |
