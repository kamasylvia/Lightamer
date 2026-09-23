---
phase: 6
slug: layers-masking
status: validated
nyquist_compliant: true
wave_0_complete: true
created: 2026-09-22
validated: 2026-09-24
---

# Phase 6 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.
> 体例对齐 04/05-VALIDATION。

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | XCTest (unit) + golden/parity harness（float64 解析参考双轨 + blend dt 三证据） |
| **Config file** | `Project.swift` (Tuist) — LightamerTests target |
| **Quick run command** | `Scripts/test-direct.sh`（直启宿主零弹窗；L019b 三加固） |
| **Full suite command** | `Scripts/test-direct.sh`（签核终轮 = touch Tests + build-for-testing 重编复跑） |
| **Estimated runtime** | ~210-265 seconds（788 tests；层/golden/parity/蒙版/面板/perf） |

---

## Sampling Rate

- **After every task commit:** quick unit tests（test-direct.sh 全套）
- **After every plan wave:** full suite
- **Before phase sign-off:** full suite must be green（0 fail）
- **Max feedback latency:** ~265 seconds

---

## Per-Task Verification Map

> 14 needs → 7 plans（06-01..06-07）。LAYER-01..07 / IOP-MASK-01..05 / IOP-GEO-05/06。

| Task ID | Plan | Wave | Requirement | Test Type | Evidence（测试/文件/数字） | Status |
|---------|------|------|-------------|-----------|---------------------------|--------|
| 06-01-T1..T7 | 06-01 | 1 | LAYER-01/02/05/06 + sidecar v2 + BlendMode 定案 | unit+golden | BlendMode 三方映射 13 值对 blend.h；恒等三元组逐字节双档；层 K 增量精确账本；PipeCacheKey.layerID + enforceBudget tier-5；层感知 drift；轨 B 恒等层 == 基线逐字节 | ✅ green |
| 06-02-T1..T5 | 06-02 | 1 | LAYER-05 blend 引擎 | golden+adoption | compositeLayer 单 kernel；算术全表 <1e-5 + JzCzhz 五模式；REVERSE 消费；**dt 三证据 54/54**（v14 blob 420B + params ok + 平场 PFM）；分块恒等逐字节 | ✅ green |
| 06-03-T1..T8 | 06-03 | 2 | LAYER-03 + IOP-MASK-01（drawn）+ maskVersion 缓存 | unit+golden+GUI | stamping spike（render-pipeline additive 0.744ms/1000 stamps）；GeometryPointMapper roundtrip ~1e-12 px；drawn 解析 ≤1e-6 + tile 缝 0.0；蒙版编辑零链重算双向记账；overlay 显示腿 GUI 量化（ΔR +65.5 黄调显著） | ✅ green |
| 06-04-T1..T6 | 06-04 | 2 | IOP-MASK-02/03/04（parametric/raster/combine） | golden+unit | blendif 单 kernel（luma+JzCzhz 全通道族）；平场二元门抓 kernel+参考同源反转 bug（双边修复）；combine 五式逐行 + 解析面积；raster 16-bit + StableHash + 三失败腿降级；三类 ⊗ 装配单平面 + round-trip 渲染逐字节 | ✅ green |
| 06-05-T1..T6 | 06-05 | 3 | LAYER-04 层管理 UI + history 全粒度 + 前半签核 | unit+GUI+perf | LayersPanelView 全件 live AX；24 面板零改动路由实证；互斥状态机穷举；**10 层拖动 Debug median 15.6-16.4ms < 16.6ms（60fps 达标）**；FULL 政策 benchmark 维持 fullColdLayer（D-06-05-T5-1）；真 RAW E2E 渲染逐字节；GUI 走查 8 截图（当场修 GUI-14/15/16）；**前半签核 SC#1/2/3/5 落 DISCUSSION-LOG** | ✅ green |
| 06-06-T1..T5 | 06-06 | 4 | IOP-GEO-05 liquify | golden+unit+GUI | 场解析 ≤2.4e-7（独立 float64 参考）；warp parity 0.0（27,648 采样）；空路径逐字节恒等；五段链 roundtrip 2.5e-10 px；蒙版内容锚定端到端 0.039；分块==整幅 0.0；GUI 真机复测（拖拽实时/⌘Z 恰 1 commit/互斥路由） | ✅ green |
| 06-07-T1 | 06-07 | 5 | LAYER-01 扩展（retouch kind）+ LAYER-07 拼写扩展 | unit | RetouchLayerCoreTests 5（kind/dt 槽位/形状门/duplicate NDE-1/栈 mutation + mergeDown 拒绝）；RetouchSidecarTests 4（冻结拼写 JSON 表/round-trip/history 投影/pre-06-07 兼容） | ✅ green |
| 06-07-T2 | 06-07 | 5 | IOP-GEO-06 clone/blur/fill + 跨窗扩窗 | golden+unit | RetouchParityTests：clone 解析 ≤1e-5 + 外部逐字节；fill 常数域 ≤1e-5（含层 opacity）；blur 剖面（边缘塌缩 + 线性场保持 ≤2e-3）；**跨窗 hint 32→57px 无源区黑边 ≤1e-5**；空层恒等逐字节；stroke 腿缓存记账 | ✅ green |
| 06-07-T3 | 06-07 | 5 | IOP-GEO-06 heal + D-06-CONTEXT-1 判定 | golden+perf | heal_laplace_step 红黑 SOR（dt heal.c 逐式）**vs 独立 float64 参考 <1e-3** + Dirichlet 外区不动；**基准 median 9.99-11.63ms << 100ms → heal 留 6-7 不拆 6.5b**（D-06-07-T3-1）；composite smoke（真 RAW 掩码内变/外区逐字节） | ✅ green |
| 06-07-T4 | 06-07 | 5 | retouch 交互 + 面板四件套 | unit+GUI | LayerUIWiringTests 14/14（retouch 路由互斥 + stroke 恰 1 commit/⌘Z 还原）；GUI 真机走查（真 RAW：加修复层→画 heal stroke→⌘Z chip 1→0；4 截图 FINDINGS 06-07 节）；**GUI-18 zh-Hans catalog 缺陷当场修复**（592/592 键） | ✅ green |
| 06-07-T5 | 06-07 | 5 | golden 收口 + 回归 | all | manifest「Phase 6 golden 完整性总账」节（blendop/mask/liquify/retouch 四族）；touch + build-for-testing 重编；终轮全套 **788/3skip/0fail** | ✅ green |
| 06-07-T6 | 06-07 | 5 | Phase 6 签核 | all | 本文件 + DISCUSSION-LOG SC#1-5 终节 + REQUIREMENTS 14 reqs 翻账 + PERF-2 记账（perf.md）+ Phase 7 移交清单 | ✅ green |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Per-Requirement Annotations（需求口径注记）

| Requirement | 注记 |
|---|---|
| **LAYER-04** | 「合并」= mergeDown v1 交付（data face + 1 commit 语义，D-06-05-T1-2）；「编组（层文件夹）」= **v2**（D-06-CONTEXT-6：纯 UX 组织不产生管线语义；蒙版组由 MaskGroup 内嵌套承载 = IOP-MASK-04）。SC#5 的「group」以 MaskGroup 组语义判定满足，层文件夹公开挂 v2。 |
| **LAYER-06** | 共存架构 = 混合模型 (c)：全局 iop = base 链（背景层），局部 = 调整层子链 + blend 三元组合成；同一 pixelpipe walk 之上（零 walk 改动），06-01 轨 B 恒等层逐字节 + 06-05 E2E 实证。 |
| **IOP-MASK-02** | v1 域 = luma + JzCzhz 单 kernel（D-06-CONTEXT-3）；dt 双域 UI（Lab+RGB 双面板）defer——可逆扩展位（域枚举 + kernel 参数族同构）。 |
| **IOP-GEO-06** | retouch = **独立图层 kind**（D-06-CONTEXT-4，非 base 链模块——dt iop_order 20.0 槽位保留 V50Order 表作参考不消费）；NO_MASKS 语义钉死（stroke 形状即蒙版，parametric 叠加 defer）；四算法 clone/heal/blur/fill 全交付（heal 降级条款未触发：median ~10ms 预算内，D-06-07-T3-1）；v1 圈定：视口绘制圆形（path 数据腿就绪）、blur gaussian（bilateral defer）、fill 纯色（erase defer）——均 optional additive 路径，非缺口。 |
| **SC#4 判定** | liquify + retouch 均「与蒙版/变形框架架构耦合」交付：liquify 经 GeometryPointMapper liquify 段接入蒙版内容锚定（06-06 T3）；retouch stroke mask 经 06-03 光栅化器 + mapper 渲染（内容锚定同源）——SC#4 原文「both architecturally depend on the mask/distortion framework」以实际耦合证据判定 **PASS**。 |
| **heal 降级条款** | D-06-CONTEXT-1 的降级路径（拆 6.5b）**未触发**：基准实测预算内（D-06-07-T3-1），无用户确认待办。 |

---

## Wave 0 Requirements

- [x] blend 引擎先行（06-02）——退化三元组（06-01）之上补全模式表 + dt 证据
- [x] stamping spike 两方案先行定稿（06-03 T1，render-pipeline additive 胜出）
- [x] TilingPlan 多消费者跨层回归加固（06-06 强制分块，轨 B 零增量）

---

## Manual-Only Verifications（L011 口径挂账汇总）

> 06-03/06-05/06-06/06-07 四轮 Manual-Only 逐行汇总；已闭环项划掉。

| Behavior | Requirement | Why Manual | 状态 |
|----------|-------------|------------|------|
| 笔刷延迟/落点精度/光标环手感 | IOP-MASK-01 | 单测不可达（L011 红线） | 06-05 GUI 轮已走查（黄色描线实时跟随）；100MP 延迟 → 性能轮 |
| 蒙版 overlay 黄调量化 | IOP-MASK-05 | 亮度域断言需真机 | ✅ 06-03 T7（ΔR +65.5/ΔG +80.4/ΔB −35.6） |
| liquify 节点拖拽/⌘Z/互斥 | IOP-GEO-05 | 手感判据 | ✅ 06-06 T4（强度手柄拖拽实时 0→10.11、⌘Z 恰 1 commit） |
| **source 拾取手感**（十字线+连线跟随） | IOP-GEO-06 | 视觉/手感判据 | ⏳ pending-manual（数据腿 parity 已钉；CGEvent 合成点击与本 app 菜单状态机互扰，交互轮未走完） |
| **stroke 羽化视觉**（border 渐变带） | IOP-GEO-06 | 视觉判据 | ⏳ pending-manual（解析断言已钉） |
| **heal 效果人像目检** | IOP-GEO-06 | 人眼质量判据 | ⏳ pending-manual（parity <1e-3 + latency ~10ms 已钉） |
| GUI-17 showmask 偶发不可见 | LAYER-04 | 偶发布局塌缩待人工复现 | ⏳ 挂人工（不阻塞——overlay 请求路径 row-tap 驱动验证 + GUI-15 修复） |
| stroke path lasso 视口手势 | IOP-GEO-06 | 数据腿 parity 就绪，手势未接 | ⏳ 后续 plan（v1 圈定注记） |

---

## PERF 记账（摘要，正本 .work/06/perf.md）

- **PREVIEW 拖动门（层维度 SC 门）**：10 层稳态拖动 Debug median 15.6-16.4ms <
  16.6ms（60fps 达标，06-05；门 = Release 20ms / Debug 病理 120ms 回归界）。
- **PERF-2 正式记账**：窗口化 coldLayer 166.7MB vs cacheAll 280.0MB（10 层账本）；
  100MP 视窗外推 + 冷层政策（fullColdLayer 维持）→ 工作集远低于 3GB 预算；
  retouch patch 腿 O(patch)（全平面替代会追加 2×1.63GB——破预算，已规避）。
- **PERF-5 联动**：层维度缓存是 denoise 拖动 85.7ms 的结构利好（单层失效不扩散），
  只记录不设门（本轮），实测留 perf plan。
- **heal 基准**：median 9.99-11.63ms @160×120 patch（预算 100ms；门 25ms）。

---

## Sign-Off Checklist

- [x] 全部 7 plans 执行完成（06-01..06-07），SUMMARY 逐 plan 落盘
- [x] SC#1-5 逐条证据指针落 DISCUSSION-LOG 终节（前半 06-05 + 本轮 SC#4 终核；缺口注记零静默：LAYER-04 编组=v2 / 层内几何=v1 禁用 / retouch v1 圈定 / Manual-Only 8 行）
- [x] golden 完整性总账四族（manifest「Phase 6 golden 完整性总账」节：blendop 54 blob sha256 总账 + mask 11 行 + liquify/retouch 解析轨测试锚）
- [x] 层栈 sidecar round-trip（Phase6SidecarTests + RetouchSidecarTests + LayerE2ERoundTripTests 真 RAW 渲染逐字节）+ 未知 op 层降级回归绿
- [x] 轨 B 全链回归绿（空 retouch 层插链零增量逐字节；Phase 3+4+5 全模块基线保持）
- [x] PERF-2 正式记账 + PERF-5 联动记录（.work/06/perf.md 06-07 节）
- [x] GUI 验收轮汇总（06-03/05/06/07 四轮 + 本轮 4 截图）；Manual-Only 汇总表（本文件）
- [x] LAYER-04 编组 / LAYER-06 共存 / IOP-MASK-02 单域 / IOP-GEO-06 独立层 kind 需求注记行（本文件 + REQUIREMENTS.md）
- [x] Phase 7 移交清单（DISCUSSION-LOG 终节：AI mask 消费端接口 / 层栈 API 面 / mask 版本化 / pipe 缓存面）
- [x] `status: validated` + `nyquist_compliant: true`；TODO/LESSONS/GOAL-STATE/REQUIREMENTS 同批更新（§3.1 commit guard）
- [x] 终轮全 suite 0 fail（788/3skip/0fail；touch Tests + build-for-testing 重编复跑防增量吞更新）
