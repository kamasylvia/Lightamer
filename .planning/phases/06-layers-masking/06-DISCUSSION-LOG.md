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

---

# Phase 6 终签核：SC#1-5 逐条证据核对（Plan 06-07-T6.1，2026-09-24）

> 体例 = 04-07/05-08 模式：每条 SC 逐项列证据指针（测试名/文件/数字）；前半签核
> （06-05 收工节）已核 SC#1/2/3/5 前半，本节补 SC#4（liquify+retouch）并汇总终判。
> 缺口零静默：全部注记公开，处置列明。

## SC#1 层独立运作（LAYER-01/02）✅

| 证据 | 指针 |
|---|---|
| 层栈模型 + 独立参数（同 iop 异参数异层） | LayerCoreTests（栈 mutation/NDE-1/scope 投影）；LayerCompositeTests（层 K 增量账本精确——顶层 4h2m1b/底层 3h3m2b 连锁/重排链全存活） |
| 独立渲染范围（层输出 ≠ 串味） | L021 层维度 precondition 群（driver 常驻：entry dscIn == 自 bufInROI.first == window）+ LayerCompositeTests 恒等层逐字节 |
| GUI：24 面板零改动路由 + 层选中 | LayerUIWiringTests.testAllProvidersResolveUnderLayerScope + FINDINGS 06-05 节 |
| 06-01..06-05 验收记录 | GOAL-STATE Phase 6 各 plan 行（验收 PASS 记录） |

## SC#2 蒙版四形态 + combine（IOP-MASK-01..05）✅

| 证据 | 指针 |
|---|---|
| drawn（brush/path/ellipse/gradient/bezier ctrl 点） | DrawnMaskRasterTests（解析 ≤1e-6，tile 缝 0.0）；MaskEditIncrementTests（蒙版编辑零链重算双向记账） |
| parametric（luma+JzCzhz，含羽化/反转/模糊） | ParametricMaskParityTests（blendif 平腿 <1e-5 / ramp 5e-4 档）+ 平场二元门 + 后处理链序 pin |
| raster（烘焙） | RasterMaskRoundTripTests（uint16 恒等 + 三失败腿降级） |
| combine + 组 | MaskCombineTests（五式 <1e-6 + 解析面积 + 嵌套组） |
| 应用于任意层 | 三类 ⊗ 装配单平面（06-04 T5）+ driver mask 腿接线（06-03 T6） |

## SC#3 blend + opacity（LAYER-05）✅

| 证据 | 指针 |
|---|---|
| 全模式公式 + 两域 | BlendOpParityTests（算术 <1e-5 / JzCzhz pow-chain 档）+ dt 三证据 54/54（manifest blendop 节） |
| opacity 折叠 | compositeLayer mask×blend×gopacity 单 kernel（06-02 T2）+ 驱动器 blendTripleHash |
| 恒等三元组 | LayerCompositeTests 逐字节双档 + 常驻回归 |

## SC#4 liquify + retouch（IOP-GEO-05/06）✅

| 证据 | 指针 |
|---|---|
| liquify（06-06） | LiquifyParityTests：场解析 ≤2.4e-7、warp parity 0.0（27,648 采样）、五段链 roundtrip 2.5e-10 px、分块==整幅 0.0、蒙版内容锚定端到端 0.039 |
| retouch 本轮 | RetouchParityTests 9/9：clone ≤1e-5 / fill ≤1e-5 / blur 剖面 ≤2e-3 / **跨窗扩窗无源区黑边 ≤1e-5** / **heal vs float64 <1e-3** / composite smoke |
| heal 判定（D-06-CONTEXT-1） | **交付，不拆 6.5b**——benchmark median 9.99-11.63ms << 100ms（D-06-07-T3-1，perf.md 记账） |
| retouch 交互 | FINDINGS 06-07 节：加修复层→画 stroke→⌘Z 恰回退（截图 4 张） |

## SC#5 层栈 round-trip + 架构共存（LAYER-03/04/06/07）✅

| 证据 | 指针 |
|---|---|
| 真 RAW E2E round-trip（渲染逐字节） | LayerE2ERoundTripTests.testRealRAWRoundTripThroughHistoryAndSidecar（06-05） |
| 全栈语义（可见性/重排/复制/合并/重命名/opacity D-H1/history 全粒度） | LayerUIWiringTests（14/14）+ Phase6SidecarTests |
| retouch kind 并入（本轮） | RetouchSidecarTests 4/4（kind 分派 round-trip + 冻结拼写表 + pre-06-07 兼容）+ history snapshot kind 投影 |
| 14 reqs 翻账 | REQUIREMENTS.md（本批 [x] + 注记行）+ 06-VALIDATION Per-Requirement Annotations |

## Phase 7 移交清单（T6.5）

1. **AI mask 消费端接口（AI-06/07 挂点）**：
   - raster 烘焙入口 = `RasterMaskRef`（.lra.masks/<id>.png 16-bit + StableHash 校验，
     06-04 T4）——AI mask 生成后 bake 成 raster PNG 即入此通道，继承全部蒙版编辑/
     版本化/round-trip 能力。
   - parametric 输入 = `MaskSpec.parametric`（blendif 单 kernel，D-06-CONTEXT-3）——
     AI 直接产出 parametric 曲线亦可挂。
   - 可编辑性面 = maskVersionHash ⊕ mapper 几何态缓存键（06-05 C0）+ 蒙版编辑零链
     重算（06-03 T6）+ drawn forms 并组（06-04 combine）——AI mask 从生成起即用户
     可编辑（画笔叠加/羽化/反相）。
2. **层栈 API 面**：`LayerStack`（addAdjustment/replaceAny/remove/reorder/duplicate/
   mergeDown——retouch mergeDown v1 拒绝）+ `LayerCompositeDriver.composite`（kind
   分派：adjustment 链腿 + retouch stroke 腿 + blend 三元组统一）+ history 双轨
   （layerScope 参数项 / `__layerStack__` 结构项）。AI 修图结果若作为新层落地，直接
   消费此面（EditorState.addRetouchLayer/addAdjustmentLayer 同形扩展）。
3. **mask 版本化机制（NDE-3 口径）**：`MaskSpec.stableHash()`（canonical sortedKeys
   JSON ⊕ StableHash + mapper 几何态折叠，06-05 C0）——mask 内容演进 = version 字段
   + optional additive 字段（drawn→parametric→raster 三步先例）；AI mask 版本化直接
   沿用（不 ordinal、不迁移）。
4. **pipe 缓存/性能面**：retouchPosition 腿缓存 + blendTriple 前缀键 + enforceBudget
   五档 + FULL 冷层政策（D-06-CONTEXT-8）——AI 推理腿接入时沿用（推理结果 = 一条
   layerPlane/maskPlane 级产物，不新增缓存类）。

## 缺口/注记台账（终核，零静默）

| 项 | 处置 |
|---|---|
| LAYER-04「编组」 | v2（D-06-CONTEXT-6；MaskGroup 内嵌套承载组语义，REQUIREMENTS 注记） |
| 层内几何模块 | v1 禁用（D-06-CONTEXT-5；UI 隐藏集 = 13/15/16/17 ∪ crop/enlargecanvas/liquify） |
| retouch mergeDown | v1 拒绝（无链可折，层完整保留——LayerCoreTests 钉住） |
| stroke path lasso 视口手势 | 数据腿就绪（path 形状 parity），手势未接——Manual-Only/后续 |
| mask 工具条在 retouch 路由仍显示 | minor 视觉冗余（FINDINGS 06-07），UI 打磨轮 |
| GUI-17 showmask 偶发不可见 | 挂人工（06-05 遗留，不阻塞——路径由 row-tap 驱动验证） |
| cmd-drag 调 brush size | 未实现（参数环面板等效能力已交付，06-05 台账顺延） |
