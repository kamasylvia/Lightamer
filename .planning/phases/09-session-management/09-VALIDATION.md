---
phase: 9
slug: session-management
status: validated
nyquist_compliant: true
created: 2026-09-26
validated: 2026-09-26
---

# Phase 9 — Validation（签核：SC#1-6 三列对照 + Per-Task Map + Manual-Only 汇总）

> 体例对齐 07-VALIDATION（frontmatter/Checklist）+ 06-VERIFICATION（逐条判定）。
> **翻账只认证据**：SC 表逐条「一手证据 + 测试锚 + GUI 实证」三列；无证据 ✅ = 违规。
> GUI 缺陷编号按 09 轮口径标注（09 轮 GUI-19/20/21 与 Phase 7 轮撞名，体系未换轨）。

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | XCTest（unit / timer 计量 / FSEvents 合成事件 / 崩溃注入 / 直启宿主） |
| **Quick run** | `Scripts/test-direct.sh`（L019b 直启，零弹窗） |
| **Full suite（终轮）** | touch Tests + `build-for-testing` 重编复跑 = **1133 tests / 6 skip / 0 fail**（323.1s，2026-09-26 00:22） |
| **基线演变** | Phase 8 末 973 → 9-1 +42（1017）→ 9-2 +37（1054）→ 9-3 +43（1097）→ 9-4 +36（1133）→ 09-05 终轮 **1133**（签核 plan 零新测试） |

---

## SC#1-6 对照表（ROADMAP §Phase 9 契约，三列证据）

| SC | 判据 | 一手证据（文件/决策） | 测试锚（类/用例） | GUI 实证（FINDINGS 节） | 判定 |
|---|---|---|---|---|---|
| **SC#1** | 选文件夹即 Session；Capture/Crop/Output 三级子目录自动创建维护 | `App/Sources/Lightamer/Session/SessionLayout.swift`（幂等创建 + reservedRootDirectoryNames 单一真源）+ `SessionCoordinator.swift`（开/切/recent 同一五步编排，③=ensureDirectories，失败完全解绑 D-09-01-T1-4） | `SessionTreeScannerTests.testEnsureDirectoriesCreatesExactlyThreeTiers` / `.testEnsureDirectoriesIsIdempotentZeroDiff`（双跑 mtime 快照相等）/ `.testOutputDirectoryConstantVectors`；`SessionSwitchTests.testSwitchRunsFiveTeardownStepsBeforeStateUpdate` | FINDINGS 09-3：「三级目录幂等:Capture/Crop/Output 在打开时创建 ✓；`.lightamer/`(session.lindex+WAL+thumbs/)落位 ✓」 | ✅ |
| **SC#2** | FSEvents 监视 Finder 增/移/删同步视图；孤儿 sidecar reconcile 处置、永不硬失败 | `SessionWatcher.swift`（四 flags + WatchRoot + 私有队列 + AsyncStream）+ `SessionReconciler.swift`（四时点 + SidecarWriteJournal 双防）+ `ReconcileDiff.swift`（六桶纯函数）+ 孤儿移除/忽略两动作（meta KV 零迁移） | `SessionWatcherTests` 8 + `ReconcileDiffTests` 16 + `SessionReconcileScheduleTests` 8 + `SessionReconcileE2ETests` 5（Finder 模拟四类变更收敛 index==disk + rename 幸存自愈 + **100 sidecar 零自触发常驻断言**） | FINDINGS 09-3：「监视状态 未监视→扫描中→已同步(FSEvents armed)」+ 侧栏孤儿动作面（确认弹窗，L010 `session.orphan.<pathhash>`） | ✅ |
| **SC#3** | 多 Session 切换 + recent 列表，无跨会话泄漏（显式 teardown） | `SessionCoordinator.swift` 五步 teardown（flush→cancel 缝→`PipeCoordinator.prepareForSessionSwitch`→索引关→state 更新）+ SessionState recent 持久化去重/上限10/剔除 | `SessionSwitchTests` 13：`testSwitchPurgesPipeCacheFourStepLeakAssertion`（真 PipeCoordinator 填缓存后 totalBytes==0）+ `testThreeSessionOpensSpawnNoNewWindowsOrMTKViews`（L012 窗口/MTKView delta 0）+ recent 4 向量 | FINDINGS 09-3：「侧栏『最近会话』点击 → 计数『共 4 张 · 已编辑 2 · 孤儿 0』精确」；重启恢复浏览模式（@AppStorage） | ✅ |
| **SC#4** | 浏览三态：thumbnail grid / 单图 / culling 并排 | `SessionBrowserView.swift`（三态 segmented 整页替换 + cell 四件 + 渐进占位）+ `SessionBrowserModel.swift` + `CullingView.swift`（独立子管线错峰 cap 2）+ 双档缩略图管线（`SessionThumbnailProvider` has_edits 红线 + LRU 384MB + 磁盘 JPEG q85） | `SessionBrowserModelTests` 11（渐进时序：首屏早于全扫）+ `SessionThumbnailProviderTests` 16（双档真值表/pristine 禁走 B 反向断言/stale hash 翻转）+ `ThumbnailMemoryCacheTests` 7（逐出精确到字节）+ `CullingPipelineTests` 5（cap 拒第 3/释放归零）+ PipeCache 隔离常驻断言 | FINDINGS 09-3：三态切换/L010 identifier/双档真机确认（2 edited 走档 B、2 pristine 走档 A）/磁盘缓存秒开（0 重渲）/culling 双格真实渲染含 100MP + 截图 3 张 | ✅ |
| **SC#5** | 调整复制/粘贴（全量/部分参数、多选批量）+ before/after（split/快照点/hold 看原图） | `PastePayload.swift`/`PasteSemantics.swift`（三式 + skip 集 D1 + 部分选择面）+ `HistoryItem.pasteSet` additive 单提交（D3）+ `SessionBatchApplier`/`BatchSidecarWriter` 三段管线 + `BeforeAfterState` + renderPreview override + split 双 scissor 零新 kernel | `PasteSemanticsTests` 16（overwrite 精确非超集/⌘Z 恰 1 逐字节/sidecar 往返 drift-free/pasteSet additive 字段存活）+ `SessionBatchApplierTests` 12（writer=nil 磁盘零字节【零渲染常驻断言】/崩溃注入自愈/缩略图 stale 翻转）+ `BeforeAfterTests` 5（BEFORE==独立 pristine 渲染逐字节/peek==重放/hold 零 history 项） | FINDINGS 09-4：真会话粘贴链 15s 内 claim/落盘/清 dirty/E 徽章/缩略图再生全实证（DB 三列 + `.lra` 落盘）+ split HUD/hold \ 切换截图 3 张 | ✅ |
| **SC#6** | 会话级索引 DB（可重建派生缓存）：sidecar 索引 + 缩略图；真身恒 sidecar；批量 apply = 索引单事务 + 批量写队列（PERF-07 基座） | `SessionIndexSchema.swift`（v1 冻结 25 列 + L013 TEXT + Phase 12 预留列 + WAL/synchronous=NORMAL）+ `SessionIndexStore.swift`（单事务增量 sync + claimBatchApply/clearBatchDirty/healDirtyRows）+ 段2 D8 PK-seek 修正 | `SessionIndexStoreTests` 16：`testDeleteAndRebuildParityColumnByColumn`（删库重建 13 列×50 行逐列 compared>400【SESS-07 门】）+ `testWALCrashRecoveryCommittedSurvivesUncommittedRollsBack` + `testTenThousandRowSingleTransactionUpdateTiming`（12.9ms）+ `Perf07MassApplyTests`（万张段1+2 Release 门） | FINDINGS 09-4：真会话 DB 实证 `has_edits=1 / thumb_state=3(stale)→再生 / dirty=0` + FINDINGS 09-3 `session.lindex` 落位 | ✅ |

**Notes「mutable and untrusted」原则验证口径**：reconcile 全程 hint-only（watcher 只触发不直改）+ 索引 DB 三重可重建证据（parity 逐列 / WAL 崩溃恢复 / mtime 漂移重读 D-09-01-T5-2「真身恒 sidecar」）+ 段1 compose 以磁盘 sidecar 为真（`testBatchApplyTreatsTheDiskSidecarAsTheComposeAuthority` 毒化索引反证）——目录被外部改写的语义全部走「重推导」而非「信任缓存」。

---

## Per-Task Map（09-01..09-05）

| Task | Plan | 交付 | commit | Status |
|---|---|---|---|---|
| 09-01 T1 | 会话模型 | SessionState 状态机 + SessionCoordinator 五步编排 + prepareForSessionSwitch hook + UI 三段侧栏/菜单 + 12 键 catalog | `e461fff` | ✅ |
| 09-01 T2 | 三级目录 | SessionLayout 幂等 + outputDirectory Phase 11 消费点 + reservedRoot 单一真源 | `ee3c39c` | ✅ |
| 09-01 T3 | 扫描器 | SessionTreeScanner 递归分页流 + exclude 单一真源 + 孤儿分类不硬失败 | `c077a06` | ✅ |
| 09-01 T4 | 索引 DB | SQLiteHandle（零 SPM）+ schema v1 冻结 25 列 + Store actor 单事务 sync + App 接线 | `0f26e0a` | ✅ |
| 09-01 T5 | 回填 | sidecar 摘要回填（params_hash==historyHash）+ mtime 漂移重读 + EXIF 轻量列 | `de8a34c` | ✅ |
| 09-01 T6 | 深度测试 | 删库重建 parity + WAL 崩溃恢复 + 10k 单事务 12.9ms | `abf99a8` | ✅ |
| 09-01 T7 | 泄漏+计量 | 泄漏四步断言 + L012 探针 + 开卷 10k 暖/冷基线 + perf.md | `64c0532` | ✅ |
| 09-01 T8 | 收口 | SUMMARY/DECISIONS(12)/TODO/GOAL-STATE/LESSONS L027 | 本提交批 | ✅ |
| 09-02 T1 | 纯函数 | ReconcileDiff 六桶 golden + rename 幸存 apply 腿 | `5ab2868` | ✅ |
| 09-02 T2 | watcher | FSEventStream 封装四 flags + 四缺陷对策 + exclude 重构 | `fe51f41` | ✅ |
| 09-02 T3 | 调度 | 四时点 reconcile + journal 双防 + 100 sidecar 零自触发 + markRowsStale | `d847948` | ✅ |
| 09-02 T4 | 孤儿+E2E | 移除/忽略两动作 + rootLost 五态 + 侧栏动作面 + Finder 四类变更 E2E | `46ef09e`（amend 修 message） | ✅ |
| 09-02 T5 | 收口 | 全量回归 + SUMMARY/DECISIONS(12)/L027 增补/账目 | 收尾提交 | ✅ |
| 09-03 T1 | 行模型 | SessionBrowserModel + ThumbnailMemoryCache LRU + ThumbnailPath | feat(session) | ✅ |
| 09-03 T2 | 磁盘缓存 | ThumbnailDiskStore + 行绑定腿 + removed 清 thumb 挂接 | feat(session) | ✅ |
| 09-03 T3 | 档 A | 双档判定 + ImageIO 档 A + 回落缝 + tier B 材料化 | feat(session) | ✅ |
| 09-03 T4 | 档 B | 真 pipe 渲染 + 后台队列（并发2/可见优先）+ memory stale + PipeCache 隔离 | feat(session) | ✅ |
| 09-03 T5 | 三态 UI | segmented + grid cell 四件 + culling 形状 + wiring + catalog 10 键 | feat(ui) | ✅ |
| 09-03 T6 | culling | 子管线独立 decode+1480 rung + 错峰 + cap 2 + 释放账本 | feat(ui) | ✅ |
| 09-03 T7 | 一致性 | A→B 升级只在编辑 + 真样张抽检 D10 + 转换腿双域修复 | test(session) | ✅ |
| 09-03 T8 | PERF-06 基线 | perf.md 09-3 节 + MemoryBudget 扩 case | test(perf) | ✅ |
| 09-03 T9 | GUI 轮+收口 | FINDINGS 09-3 + **09 轮 GUI-19（浏览模式 Inspector 未隐藏）当场修** | 修复 `10cf39d` + 收口 | ✅ |
| 09-04 T1 | 载荷 | PastePayload 冻结载荷 + skip 集 + 部分选择面 | `2c0545f` | ✅ |
| 09-04 T2 | 三式 | PasteSemantics overwrite/merge/partial + live 路径 + 对话框 + 菜单 | `1ad1ac9` | ✅ |
| 09-04 T3 | 段1+2 | SessionBatchApplier compose/claim + 索引逐列 + App 批量路由 | `9ee9eb3` | ✅ |
| 09-04 T4 | 段3 | BatchSidecarWriter 串行队列 + 崩溃注入自愈 + flush 缝 | `0d0fa05` | ✅ |
| 09-04 T5 | PERF-07 | 门 0.419s Release/SSD + O(n²) claim 修复（D8）+ perf.md | `7b564ee` | ✅（**终账复跑 0.490s 本轮，见 PERF 记账**） |
| 09-04 T6/T7 | before/after | pristine 平面 + peek + hold blit + HUD + renderPreview override | `b9ed069` | ✅ |
| 09-04 T8 | 再生链+收口 | 全局投影作用域过滤回归修复 + stale 再生 E2E + dirty 徽章 + GUI 轮 | `cf1019c` | ✅ |
| 09-05 T1-T3 | 签核 | 本文件 + DISCUSSION-LOG + perf 终账 + REQUIREMENTS 翻账 + 收口 | 本提交批 | ✅ |

*09-04 验收 6 注记处置：①恒真断言（防空转瑕疵）②helper 名不符实 ③串行序断言较弱——测试纪律瑕疵，已在验收轮登记、不阻塞（行为面断言在案）；④GUI 编号撞名——本轮统一「09 轮 GUI-NN」口径；⑤PERF-07 门以最终代码再复核——**本轮已办（0.490s，clean Release 构建）**；⑥pristine mint imageID 自洽——见 Per-Requirement Annotations HIST-05 行。*

---

## Per-Requirement Annotations（九项 + PERF-07 注记）

| Requirement | 注记 |
|---|---|
| **SESS-01** | 文件夹即会话：SessionState + SessionCoordinator，无中央库；打开失败完全解绑（D-09-01-T1-4）。 |
| **SESS-02** | 字面三级 Capture/Crop/Output（D-09-CONTEXT-3）；C1 惯例 Trash/Selects **不建**（v1 无删除工作流）；Crop/ v1 仅幂等创建空目录，不承接工作副本语义。 |
| **SESS-03** | `.lra` 与原片同目录（Capture 子目录），自有 JSON 格式不与 Darktable 兼容（L003）；schemaVersion 1 + UInt64 decimal String（L013）。 |
| **SESS-04** | recent 持久化去重/上限10/剔除 + ⇧⌘O/菜单/odoc 路由；切换走同一五步编排（L012 同窗）。 |
| **SESS-05** | FSEvents hint-only 四缺陷对策 + 四时点 reconcile；**孤儿处置两动作**（移除带确认 / 忽略持久化 meta KV）永不硬失败；rename 幸存 (mtime,size) 配对自愈。 |
| **SESS-06** | 三态浏览；**culling v1 = 2 图 cap（D-09-CONTEXT-6）**，4 图扩展位与同步缩放挂后（常驻账本复核口径 ~24MB+瞬态 ~92MB，D11）；rating overlay 只布局不接数据（Phase 12，D-09-CONTEXT-7）。 |
| **SESS-07** | 索引 DB `.lightamer/session.lindex`：25 列冻结 + Phase 12 预留列（rating/color_label/keywords）；真身恒 sidecar（mtime 漂移重读 + compose 磁盘真身反证）；删库重建 parity 逐列。 |
| **HIST-05** | 三式粘贴 + 批量 apply 三段；skip 集 = `< ashift 15.0` decode 域（D1，plan 公式修正——dt 正本 flag 制，IOPFlags 升级后平移）；**跨图 undo 组 defer**（per-image commit 可退，批级 journal v2——REQUIREMENTS 注记行挂账）；**pristine 铸造自洽**：无 sidecar 目标铸造 doc 携 `imageID=UUID()` + `decodeParamsHash=0` + `unknown-batch`，driftDetected 按文件自身双字段重算不误报（`testBatchApplyMintsSelfConsistentDocForPristineTargets`）。 |
| **HIST-06** | 三形态：split（双平面 blit + HUD slider）/ 快照点 peek（逐字节==重放）/ hold \ 临时看原图（零渲染快路径）；peek/hold 零 history 项。 |
| **PERF-07** | 门达成（见 PERF 记账）；**PERF-06 留 Phase 15 清算注记**（60fps 门本体 + Release 分栏 + 10k 滚动 hitch signpost；本 Phase 交付工作基线）。 |

---

## Manual-Only Verifications（L011 汇总：9-3 六行 + 9-4 四行）

| # | Behavior | 来源 | Why Manual | 状态 |
|---|---|---|---|---|
| 1 | 10k 大集合滚动 hitch（>50ms 帧间隙 signpost） | 9-3 | 本轮 fixture 4 图；大集合走查 = Phase 15 门清算随行 | ⏳ pending-manual（Phase 15） |
| 2 | 滚动手感/惯性（grid ScrollView） | 9-3 | 手感判据 | ⏳ pending-manual |
| 3 | culling 布局手感（两格比例/标签观感） | 9-3 | 布局正确；比例手感待人工 | ⏳ pending-manual |
| 4 | 缩略图占位渐显观感（0.15s easeIn 已实现） | 9-3 | 视觉判据 | ⏳ pending-manual |
| 5 | 多选 ⌘/⇧ 手感（数据面已单测） | 9-3 | 交互手感 | ⏳ pending-manual |
| 6 | 双档缩略图混排观感（D10 残差） | 9-3 | 抽检判定「可辨」——根因 = v1 管线色彩形态（编辑器同链同色实证），P3+ 色彩 iop 校准后常驻抽检复核；全走档 B 退路**否决**（冲突 PERF-06 吞吐） | ⏳ pending-manual（P3+） |
| 7 | split 分界线拖动手感（HUD slider 数据面已接） | 9-4 | 视口内拖线交互 | ⏳ pending-manual |
| 8 | hold 键响应延迟观感（\ 按下/松开） | 9-4 | 截图链已证即时切换；延迟观感待人工 | ⏳ pending-manual |
| 9 | peek 步进渲染等待观感（每点首渲 ~百 ms，缓存后零渲染） | 9-4 | 等待观感 | ⏳ pending-manual |
| 10 | 部分粘贴对话框真机走查（勾选子集 + 覆盖/合并 picker） | 9-4 | 数据面 5 测试钉死；对话框交互待人工 | ⏳ pending-manual |

---

## 反模式扫描（09-05 终轮）

- **Session 新面全量 grep**（`App/Sources/Lightamer/Session` + `LightamerCore/Sources/Session` + `SessionThumbnailRenderer.swift` + Paste/Batch/Perf07/BeforeAfter 测试文件）：TBD/FIXME/XXX/HACK/PLACEHOLDER/coming soon/unimplemented/`return nil` 静默路径——**债务标记零命中**。唯一 `PLACEHOLDER` 命中 = `SessionBrowserModel.swift:19` 头注「渐进 ingest 占位行」语义文档（D-09-03-D5 设计行为，非债务）。
- **PipeCache 隔离复查**（9-3 检查项终验）：`grep -rn PipeCache LightamerCore/Sources/Session App/Sources/Lightamer/Session` = **0 命中**（红线维持：provider 注入腿制，GPU 腿唯一持有点 App/State throwaway per-run）。
- **pasteSet 持久格式增量抽查**（9-4 移交面）：additive `decodeIfPresent`（HistoryStack.swift:136-137，旧档缺键解码 nil）+ `testPasteCommitRoundTripsThroughTheSidecarSpelling`（pasteSet 骑 additive sidecar 字段往返 + drift-free）+ `testPayloadCodableRoundTripIsByteIdentical`——终轮 1133 全绿内含。

---

## PERF 记账（摘要，正本 .work/09/perf.md）

- **PERF-07 门终值（09-05 复跑，2026-09-26 01:0x）**：段1+段2 万张 = **0.490s（Release / 内置 SSD，clean 构建）** ≤5s 门，余量 ~10.2×（compose 0.476s + claim 0.014s）。三轮对账：9-4 执行 0.419s → 9-4 验收 0.435s → 09-05 终账 0.490s——同量级稳定，无漂移趋势，**门维持达成**。
- 段3 SSD drain 10k：8.683s（1152 docs/s）只记录不设门（9-4：6.23s / 1606 docs/s，同量级）；UNITEK 对照只记标卷型（L009）。
- **PERF-06**：工作基线已落账（档 A 10.6ms / 档 B 2.87s(86MP Debug) / 10k reload 26ms / culling 双 100MP 2.9s 错峰 / LRU+磁盘两级）；**60fps 门本体 Phase 15 清算**（挂账不变）。

---

## Sign-Off Checklist

- [x] 全部 4 执行 plans 完成（09-01..09-04），SUMMARY 逐 plan 落盘；09-05 签核材料齐（本文件 + DISCUSSION-LOG + perf 终账）
- [x] SC#1-6 逐条三列证据（一手证据 + 测试锚 + GUI 实证）——无证据 ✅ 零条
- [x] 全套回归终轮 touch + build-for-testing 重编复跑 **1133/6skip/0fail**；三族重点复跑（HistoryStack 18 / LayerCore 11 + RetouchLayerCore 5 / BeforeAfter 5）全绿（9-4 层投影作用域过滤回归教训闭环）
- [x] 反模式扫描零静默命中 + PipeCache 隔离 grep 终验零命中 + pasteSet 持久格式抽查
- [x] PERF-07 门以最终代码再复核（9-4 验收必办项⑤）：**0.490s Release/SSD clean 构建，余量 ~10×**
- [x] Phase 11 移交清单四条 + 遗留对表落 `09-DISCUSSION-LOG.md` 终节
- [x] REQUIREMENTS 九项翻账 Delivered（含注记行）+ TODO/GOAL-STATE 同批收口（§3.1）
- [x] `status: validated` + `nyquist_compliant: true`
- [x] **C 档第 3 停执行记录**：用户 2026-09-26 显式指令「继续全自动推进 lightamer,下一项:09-05 签核」= 终签核授权（先例 D-07-3-T5-1「续班 executor 指令 = 终签核授权，签核结论以 VALIDATION frontmatter 为准，用户终验留 verify-work 轮」），详见 `09-05-DECISIONS.md` D-09-05-T1-1
