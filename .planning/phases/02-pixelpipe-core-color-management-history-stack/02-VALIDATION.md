---
phase: 2
slug: pixelpipe-core-color-management-history-stack
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-09-18
---

# Phase 2 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | XCTest (unit) + headless smoke harnesses (`.work/*/smoke.swift` 模式) |
| **Config file** | `Project.swift` (Tuist) — LightamerTests target |
| **Quick run command** | `xcodebuild test -project Lightamer.xcodeproj -scheme Lightamer -destination 'platform=macOS' -only-testing:LightamerTests` |
| **Full suite command** | `xcodebuild test -project Lightamer.xcodeproj -scheme Lightamer -destination 'platform=macOS'` |
| **Estimated runtime** | ~30-90 seconds（golden 色彩 harness 含 60MP 渲染会拉长） |

---

## Sampling Rate

- **After every task commit:** quick unit tests (LightamerTests only)
- **After every plan wave:** full suite
- **Before `$gsd-verify-work`:** full suite must be green
- **Max feedback latency:** ~90 seconds

---

## Per-Task Verification Map

> Task IDs filled by planner. Seeds from RESEARCH §Validation Architecture.

| Task ID | Plan | Wave | Requirement | Threat Ref | Secure Behavior | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|------------|-----------------|-----------|-------------------|-------------|--------|
| 02-02-06 | 02-02 | 2 | FOUND-04 | — | N/A | unit | PipeCacheTests：run1 全 miss → 改 testGain → 上游命中/下游 miss → undo 全命中（精确计数器断言）| ✅ | ✅ green（9/9）|
| 02-03-05 | 02-03 | 3 | FOUND-04 | Risk #8 | N/A | unit | MultiResolutionTests：scale-at-entry 60MP→2560px 长边、PREVIEW@360 ≠ THUMBNAIL key（两套缓存行）、THUMBNAIL lazy（dirty 才渲）、FULL scale-1.0 + 只缓存输入/终帧、EXPORT typed `.notImplemented`、roi.scale<1 断言（6 测试）+ PreviewBucketTests 梯子边界（5 测试）| ✅ | ✅ green（63 全套，1 skip 既有）|
| 02-05-07 | 02-05 | 4 | HIST-01/02/04（HIST-03 归 02-06） | Risk #2 | N/A | unit | HistoryStackTests（18）：commit/undo/redo/jump 指针 + redo 尾截断 + clamp + 100 项 uncapped；(opName,multiPriority) 去重取最新 + multi-instance 双留 + disabled 进 effective 不进 hash；D-H1 三件套 item 经济（live 0 条 / commit 恰 1 条）；HistoryHash golden 向量 0x684AEC372467B526 + 跨方法确定性 + 重排敏感 + 50.5 冲突簇 tiebreak 确定性；ModuleInstance/HistoryStack Codable round-trip（02-06 schema 守卫）；SC#2 undo 腿端到端（record→box 物化→pipe 缓存计数）；`Hasher(` grep = clean。TilingPlanTests（5）：3×3 精确网格 / overlap 内边收缩 / 退化输入 / 单 tile / 默认 bytesPerPixel | ✅ | ✅ green（2026-09-19；106 全套 0 失败 3 既有 skip）|
| 02-06-02/03/07 | 02-06 | 5 | HIST-03 | Risk #10/#11 | N/A | unit | SidecarRoundTripTests（13）：schema round-trip（真实 HistoryStack 全等 + undo 中态）/UInt64-String 盘上拼写/D-S2 命名/debounce 合并（fake clock 单次写、末文档胜）/flushNow 幂等/原子写无 tmp/损坏→nil；**SC#3** `testRoundTripRestoresIdenticalRenderedOutput`（写→全弃→恢复→重渲字节级一致）；**漂移注入** `testDriftInjectionDetectedAndDoesNotRewrite`（检测 + 不回写 + 后续编辑正常回写）；**未知 op** `testUnknownOpDegradesDisabledWithParamsPreserved`（paramsData 字节保持 + enabled=false）；真机 headless 双跑 `.work/02-06/roundtrip.md`（displayHash 一致 + cmp IDENTICAL） | ✅ | ✅ green（2026-09-19；133 全套 0 失败）|
| (planner) | 02-04 | 3 | COLOR-01 | — | N/A | golden | `GoldenColorTests`:①中性度(合成 NeutralTarget 6 灰块,全链后 \|R−G\|,\|G−B\|<2/255 + patch 级别 sanity);②交叉一致性(线性域严格 <0.004 + 字节域 vs ColorSync 8-bit 基准 p90<2/255、低端 ICC 表区有界,host finding 记录于测试注释);真 RAW 全链对照 R 通道 meanAbsDiff 1.52(`.work/02-04/smoke-run.md` §B)| ✅ | ✅ green(2026-09-19;ColorChecker ARW 两测试 XCTSkip 待人工补拍,合成 fixture 承担 gate)|
| 02-06-06 | 02-06 | 5 | RAW-03 | — | N/A | unit | RAW03Tests（7）：32f TIFF/EXR fixtures（极值 0.0/0.5/1.0/**2.0/65504.0** pinned）解码 + 管线输入平面保真（D-COL4 pre-gamma >1.0 不断裂）+ 内部级不钳制 + gamma 唯一钳制点 + 16-bit HEIC raster 路径（HIF float fixture 限制如实记录于测试注释）；宿主决策记录于 `RAWDecoder.decodeRaster` 注释：CGImage 路 float-faithful，`CIImage(contentsOf:)` fallback 不采纳；生成器 `Scripts/gen-float-fixtures.py` committed | ✅ | ✅ green（2026-09-19）|
| 02-06-05/07 | 02-06 | 5 | D-C1/C2 | spike-b 4.3-5.4GB 证据 | N/A | unit | MemoryBudgetTests（7）：keep/evict 矩阵（锁定的 4 层顺序 + current-PREVIEW 豁免 + previous-PREVIEW 保留）/tier 内 LRU 最老先逐/tier-3（他图 PREVIEW 留 previous）/tier-4（当前图非 PREVIEW）/阈值下 no-op/**load 循环**（6 连加载注入小预算，bytes 恒 ≤ floor 且 ≥1 次 enforce 实际逐出）/clearCICaches 冒烟；coordinator 触发点（load 入口 BEFORE 渲染 + 60s Task sweep + >500MB toast 节流）由构建 + 源码走查验证（App target 不可 import，02-05 偏差 #1 同例） | ✅ | ✅ green（2026-09-19）|

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [x] `Tests/LightamerTests/PipeCacheTests.swift` — FOUND-04 缓存快路径 + 失效语义（02-02：9 测试全绿，含 SC#2 主链/禁用跳过/FULL 政策/LRU 淘汰/decodeHash 失效/PipeHash 组成/invalidate 扫除）
- [x] `Tests/LightamerTests/PreviewBucketTests.swift` — D-C3 量化梯子边界（02-03：5 测试全绿，纯函数）
- [x] `Tests/LightamerTests/MultiResolutionTests.swift` — FOUND-04 多分辨率生命周期（02-03：6 测试全绿；手测 resize 防抖见 `.work/02-03/resize-verification.md`）
- [x] testGain dev-only 参数模块（SC#2 演示载体，LightamerIOP）——02-02 交付
- [x] `Tests/LightamerTests/HistoryStackTests.swift` — HIST-01/02/04（02-05-07：18 测试全绿，含 D-H1 drag-end item 经济、golden 哈希向量、SC#2 undo 腿端到端；HIST-03 sidecar 部分归 02-06 的 SidecarRoundTripTests）
- [x] `Tests/LightamerTests/SidecarRoundTripTests.swift` — HIST-03（02-06：13 测试全绿，含 SC#3 字节级 round-trip + 漂移不回写 + 未知 op 降级；真机双跑 `.work/02-06/roundtrip.md`）
- [x] `Tests/LightamerTests/GoldenColorTests.swift` — COLOR-01 双判据（02-04：双判据 green；判据 1 中性度 + 判据 2 线性域/字节域双层；ColorChecker ARW 路径 XCTSkip 就位，采集记录 `.work/02-04/colorchecker-acquisition.md` — raw.pixls.us 已不收 color target，待人工补拍后自动激活）
- [x] `Tests/LightamerTests/RAW03Tests.swift` — RAW-03 位深保真（02-06：7 测试全绿；极值含 65504.0；宿主决策记录于 `RAWDecoder.decodeRaster`）
- [x] `Tests/LightamerTests/MemoryBudgetTests.swift` — D-C1/C2 回归（02-06：7 测试全绿；注入小预算，CI 无 3GB 分配）
- [x] Synthetic 中性 golden fixture `Resources/TestFixtures/NeutralTarget.tif`（02-04-06：1024² 16-bit sRGB TIFF，6 灰块线性值逐块精确，生成器 `.work/02-04/make-neutral-target.swift`）；ColorChecker ARW 人工补拍 pending（原因与激活路径见 `.work/02-04/colorchecker-acquisition.md`）

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| 拖动滑块 60fps 无全链重算 | FOUND-04 SC#2 | 交互时序 + Instruments signpost 目检 | 打开 100MP → 拖 testGain → Instruments 确认 colorin 无重算、缓存命中计数递增 |
| 屏幕色彩正确性（非 headless 可测部分）| COLOR-01 SC#1 | 已知中性目标上屏目检 | 打开中性目标 RAW → 灰块在屏无偏色（02-04：合成 NeutralTarget 经全链后 6 灰块逐块通过双判据；真 RAW 全链输出与 CI 直渲基线逐通道一致，`.work/02-04/smoke-run.md` §B；app 内屏显 + color 日志 `.work/02-04/screen-change.md`；跨屏 profile 跟随实测单显示器 skip-with-reason，Phase 13 补）|

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 90s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
