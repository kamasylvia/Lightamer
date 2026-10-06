# M2-11 Research Notes — PERF-01..07 现状审计 + SpektraLab 对标测法 + closeout 组织

> 日期：2026-10-06（research 起草 subagent）。方法学 = **誊录既有账本 + 代码锚点定位，
> 零新跑 benchmark**（门数字一律引既有 perf.md/SUMMARY 在案值；新测义务全部归 plan
> 执行面，见 §F）。机器口径继承各账本注记（M4 mini / macOS 27 / L009 SSD fixture /
> test-direct.sh 直启 Debug 为主，Release 复核义务在案处单独标注）。
> 输入：`.work/gsd/REQUIREMENTS.md` §M2PERF + 原 PERF 族（:613-620）、ROADMAP M2-11 行、
> `phases/m2-10-ai-library/M2-10-07-SUMMARY.md` §M2-11 交接节、各 phase perf.md、
> `phases/m2-4-0-test-bundles/M2-4-0-SPIKE.md`（经 AGENTS.md 资源监控节转录）、
> `.work/LESSONS.md`、`.work/GOAL-STATE.md` 续接点。

---

## §A. PERF-01..07 现状审计表

判定分档：**达标（在案数字过门）** / **缺口（有基线未过门）** / **需新测（无在案数字）** /
**定义待修（门定义与新架构脱节）**。

### A.1 PERF-01 — PREVIEW 全链 warm median ≤16.6ms（60fps@100MP 预算）

| 项 | 内容 |
|---|---|
| 定义原文 | "PREVIEW 全链（满 iop 集 enabled）warm median ≤16.6ms（60fps@100MP 预算）"（REQUIREMENTS:613） |
| 现状 | **缺口 + 定义待修**。在案数字：①color 七件启用链拖动 **4.8ms**（Debug，余量 3.5×，达标）；②denoise 单件链拖动 **85.7ms**（Debug/Release ≈0.92 外推 ~79ms，**未达，与配置无关**）；③全链基线 33.42ms Release（04-07，11 iop dt 面种子）；④DRT 尾段全链 preview-2560 **cold 117ms / warm 85ms**；⑤FULL 1024×640 全链 20ms |
| 锚点 | `phases/05-color-denoise-iops/perf.md`（SC#4 两链表）；`phases/m2-6-drt/M2-6-3-SUMMARY.md:47-51`（bench 观察行 OQ-10）+ `M2-6-3-ACCEPTANCE.md:164`（M2-11 复验预约行）；`Tests/LightamerTests/PreviewChainPerfTests.swift`（:76 `testPreviewFullChainFrameTime` / :213 `testNLMeansPreviewDowngradeTiers` / :410 `testPhase5DragGateTwoChains`）；降载杠杆读点 `LightamerCore/Sources/Pipe/PixelPipe.swift:800` |
| 缺口 | ①"满 iop 集"是 dt 39 iop 语境——M2 起 dt 面默认禁用（M2-1 feature flag），链面定义需按 Alcedo 架构重述（OQ-5）；②denoise 链 85.7ms 缺口维持（正杠杆 = nlmeans 预览更深降载，Phase 5 SC#4 遗留）；③M2-10 全链加载后复测义务（交接件 1，`M2-10-07-SUMMARY.md` §M2-11 交接①）；④100MP 源样张的 preview-2560 warm 复测未跑（既有 M2-6-3 bench 用合成图） |
| 建议 | 重述链面 = M2 默认面（Develop + 1 Grade 默认 look + DRT SDR + 拖动两档），100MP 真样张 warm 复测立门；denoise 处置见 OQ-7 |

### A.2 PERF-02 — 100MP FULL 单帧 + N 层图层栈内存 ≤3GB（TilingPlan 窗口化）

| 项 | 内容 |
|---|---|
| 定义原文 | "100MP FULL 单帧 + N 层图层栈内存足迹 ≤3GB（TilingPlan 窗口化）"（REQUIREMENTS:614） |
| 现状 | **定义待修（主缺口）+ 断言面在**。①TilingPlan 脚手架 Phase 2 落地（02-05），tiling 消费者分块==整幅全绿（TileNegotiation/NLMeans/DenoiseProfile/Bilateral 四套件，05 perf.md）；②`MemoryBudgetTests`（bilateral FULL Δfootprint 有界）+ `PreviewChainPerfTests.testFullToneEqualMemoryBudget`（:178）常驻断言；③**M2-4-0 SPIKE（`70e09e5`）证伪 <3G 宿主门口径**：by-design GB 级重测面（TilingOverlap 7865 / HDR 5913 / QuickLook 4589MB + ~1.4G 框架分页地板）数学不可达，真实跨测残留仅 0.18-2.4MB/test → 测试宿主运行门改 **8G**（`Scripts/test-direct.sh:59 RSS_LIMIT_MB=8192`，MEMFAIL 机检）；④AI 增强 100MP@×2 fp32 双缓冲峰值 ≈11.2GB → `c573087` 两阶段 engine + typed 门（>285M 输出拒绝），行带流式挂 Maintenance |
| 锚点 | `Scripts/test-direct.sh:53-59`（门修订依据注记）；`phases/m2-4-0-test-bundles/M2-4-0-SPIKE.md`（证据正本）；`Tests/LightamerTests/MemoryBudgetTests.swift`；`PipeCache.enforceBudget`（Phase 2 缓存预算执行器）；Phase 9 culling 常驻账本 ~12MB/双格（`09-session-management/perf.md` §浏览模式） |
| 缺口 | ①3GB 的**适用主体**从未定义清楚：编辑器 GUI 交互工作集 / FULL 管线瞬态 / 测试宿主三口径混用；②GUI 态（app 进程）稳态内存无 profile 落账（Phase 2 clearCaches 分层 + LRU 预算在码，无数字账） |
| 建议 | 三分口径重述（OQ-1）：GUI 稳态工作集 ≤3GB 立门（Instruments/footprint 实测）、FULL 瞬态 = TilingPlan 窗口有界断言（维持）、测试宿主 8G 运行门不变 |

### A.3 PERF-03 — Instruments 系统级 profile 落账（GPU 趟数/热点/内存 + 杠杆兑现记录）

| 项 | 内容 |
|---|---|
| 定义原文 | "Instruments 系统级 profile 报告落账（GPU 趟数/热点/内存），杠杆兑现记录在案"（REQUIREMENTS:615） |
| 现状 | **需新测（零系统级 profile 资产）**。既有自测资产（非 Instruments）：QL 渲染时延探针（`LA_QL_PERF=1` 门控，`Tests/LightamerTests/QuickLookPerfProbeTests.swift`，13-1 perf.md 全表）；嵌入扫描分解探针（独立 -O 二进制：vImage fp16→fp32 15.4ms + vDSP_dotpr 8.0ms @200k，M2-10-02 perf.md §A.1）；os_signpost 探针面（`com.kamasylvia.lightamer:draw` DRAW/DRAWABLE，Phase 2 起） |
| 锚点 | `phases/13-system-integration-distribution/perf.md`；`phases/m2-10-ai-library/perf.md` §A.1 分解探针；02-01-SUMMARY（signpost 家族） |
| 缺口 | 无任何 Instruments trace 归档；GPU 趟数/热点维度全空白 |
| 建议 | 本 phase 补一次 GUI 实机 Instruments trace（编辑会话拖动 + 图库滚动两场景），归档 `phases/m2-11-performance/profile/` + 杠杆兑现记录（与 PERF-01/04/06 新测同批互相印证） |

### A.4 PERF-04 — 交互零卡顿（滑块拖动/缩放/平移 hitch >50ms 帧间隙 = 0，MainActor 长任务清零）

| 项 | 内容 |
|---|---|
| 定义原文 | "交互零卡顿——滑块拖动/缩放/平移 hitch（>50ms 帧间隙）= 0，MainActor 长任务清零"（REQUIREMENTS:616） |
| 现状 | **需新测（计量通道在，数字空白）**。①数据面排除：10k 行 reload 26ms → 数据面不构成 hitch 源（09 perf §滚动 hitch）；②结构面就位：可见优先队列/两级缓存/LazyVGrid 复用；③hitch 计量方法在案（>50ms 帧间隙 signpost 法，09 perf 预留 09-3 T9 GUI 验收轮义务）；④**GUI 实操通道受限先例**：M2-7 synthetic pointer 不达窗口（E3 同根因，`m2-7-masks/perf.md` 表三注）——真机 hitch 计量须走 computer-use 方法学（M2-3 视觉验收先例，2026-09-27 用户授权在案） |
| 锚点 | `phases/09-session-management/perf.md` §滚动 hitch；`phases/m2-7-masks/perf.md`（E3 注记） |
| 缺口 | 拖动/缩放/平移/滚动四场景 hitch 数字全未落账；MainActor 长任务清零无系统证据（仅结构纪律：解码/IO 离主线程，M2AI-07 佐证） |
| 建议 | computer-use 真机走查批（与 AI 视觉走查、L057 面板取消腿走查并同一 GUI 轮）+ signpost hitch 计量脚本化落账 |

### A.5 PERF-05 — RAW 解码 ≤500ms 可交互（后台解码 + 渐进显示，CIRAW 9/8 双档）

| 项 | 内容 |
|---|---|
| 定义原文 | "RAW 解码——100MP 首渲可交互时间 ≤500ms（后台解码 + 渐进显示），CIRAW 9/8 双档计量"（REQUIREMENTS:617） |
| 现状 | **需新测（组件数字达标，端到端空白）+ 定义待修**。①decode 腿 warm 达标证据：A7R V decode warm **0.11s**、100MP RAF@512 warm **0.166s**（QL 探针，13-1 perf.md）；②**RAW 9 CoreML 一次性编译冷 2.62s**（首启一次性，同表分项）——若入门则冷态必不达；③全渲腿（含 pipe）量级：86MP tier B 2.87s/张 Debug、100MP@2560 warm ~2.08s（QL 全链）——**512 桶/缩略语义达标，2560 桶全链 warm 超 500ms 4×**；④后台解码结构在（错峰 decode、EditorState.load 后台腿、SessionThumbnailProvider 队列）；⑤**渐进显示（低清先出→高清替换）未实现**——`progressive` 仅存在于 ingest 侧（SessionTreeScanner 流式扫描），视口渐进上屏无对应物 |
| 锚点 | `phases/13-system-integration-distribution/perf.md`（QL 全表 + 冷格分解）；`phases/09-session-management/perf.md`（tier B/culling） |
| 缺口 | ①"可交互"交互点未定义（decode 完成？首帧上屏？何种桶）；②open→首帧端到端无计量；③渐进显示缺位是否阻塞门未裁决（warm 路径 512/缩略桶达标，2560 桶不达） |
| 建议 | 定义重述（OQ-6）：交互点 = PREVIEW 缩略/fit 桶首帧上屏 ≤500ms（warm），RAW9 编译冷一次性单列落账；端到端 bench 新测；渐进上屏立观察项 |

### A.6 PERF-06 — 懒加载万张滚动 60fps（按需解码 + LRU 预算）

| 项 | 内容 |
|---|---|
| 定义原文 | "万张级 Session 滚动 60fps，缩略图按需解码 + LRU 内存预算（Phase 9 工作基线已落账…60fps 门本体 Phase 15 清算）"（REQUIREMENTS:618） |
| 现状 | **需新测（工作基线厚，门数字空白）**。在案：①档 A 吞吐 **10.6ms/张**（86MP 嵌入预览，预算 10-50ms ✓）；②档 B 真渲染 **2.87s/张**（86MP Debug；**Release 复核 = 明文挂 Phase 15 义务**，09 perf §浏览模式头注）；③首屏 24 张 Release 热 **837-839ms**（median 15.6ms/张，p95 107-108ms，M2-3-2 量测）；④10k collection reload **26ms**；⑤LRU 逐出精确性 7 tests 全绿 + 磁盘缓存 10k ≈ 0.3-0.6GB 上限估算；⑥渐进 ingest 占位结构在 |
| 锚点 | `phases/09-session-management/perf.md` §浏览模式与缩略图管线 + §PERF-06/07 状态；`phases/m2-2-library-project/perf.md:77`（首屏 837ms 交叉登记）；`Tests/LightamerTests/SessionThumbnailProviderTests.swift`（`testThumbnailThroughputBaselineTierAAndTierB` / `testCullingDualHundredMPStaggeredOpenBaseline`） |
| 缺口 | ①真机滚动 60fps/hitch 计量未跑（GUI 通道）；②档 B Release 复核欠账；③万张滚动中档 B 生产腿对滚动的抢占未观测 |
| 建议 | Release 复核 + computer-use 万张滚动走查（与 PERF-04 同批）+ hitch 落账 |

### A.7 PERF-07 — 批量修图（懒渲染）万张 ≤5s

| 项 | 内容 |
|---|---|
| 定义原文 | "apply = 纯元数据写入零像素操作，万张 ≤5s…缩略图 stale 后台再生；导出排除"（REQUIREMENTS:619-620，**已 Delivered**） |
| 现状 | **达标（终账在案）**。段1+段2 万张 = **0.490s**（clean Release/SSD，09-05 签核终值；三轮对账 0.419→0.435→0.490 稳定，余量 ~10.2×）；段2 O(n²) 事故修复在案（77.5s→0.010s，PK seek 单事务教训）；段3 sidecar drain 8.683s/10k 只记不设门 |
| 锚点 | `phases/09-session-management/perf.md` §PERF-07 门终值复核；`Tests/LightamerTests/Perf07MassApplyTests.swift`（`testTenThousandMassApplySegmentOneAndTwoGate`） |
| 缺口 | 无交付缺口。M2 期间 Library claim 路径沿用（SESS-07 批量 apply = 索引单事务基座），无触碰记录；M2-11 只需终验轮复核数字不复燃 |
| 建议 | M2PERF-02 终验轮随 `--all` 复跑一遍门测试，数字对账 0.49s 带内即可 |

---

## §B. SpektraLab 对标线落地测法

对标登记原文（ROADMAP M2-11 行 + `research/SPEKTRALAB-NOTES.md`:4,14）：**45MP 全渲染 <1s /
预览重印 ~0.01s / 单 arm64 二进制 32MB**。SpektraLab 语义 = 81 波长光谱物理建模渲染管线，
45MP 全渲染 = 全分辨率印相出图；重印 = 同配置放大重印（数据热、LUT 重贴级）。

### B.1 映射①「45MP 全渲染 <1s」→ 我方 FULL 桶全链渲染

- **对应路径**：FULL 桶全链（CIRAW decode warm → Develop → Grade → DRT 尾段）端到端，
  45MP 级样张。在库样张：`input/RAW/DSC00012.ARW`（60.2MP A7R V，M2-7 perf.md 口径样张）、
  GFX 100MP uncompressed（Phase 9 culling 用）。45MP 可用 60MP 样张降采样语义或径用 60MP
  （更严），plan 期定。
- **既有锚点**：FULL 1024×640 全链 20ms（小图，PSO 热100MP 全幅 bench **明文归 M2-11**
  （`M2-6-3-SUMMARY.md:51` "100MP 全幅 bench 非 gate（60fps 复验归 M2-11 惯例）"）。
- **测法**：新 bench 测试（PreviewChainPerfTests 家族形态）：真 RAW 样张 → decode（warm，
  进程内二次）→ FULL 桶全链渲一帧 → 计时；cold/warm 双档三轮取中位；量级外推 = 全渲染
  主导项是 FULL 桶像素量 × 链趟数（M2-10-02 分解探针方法学同款）。
- **预期难点（如实预警）**：100MP float32 全幅单帧 ≈1.6GB 工作平面，FULL 全链趟数 × 内存
  带宽主导——<1s 是否可达取决于链长与 TilingPlan 窗口化在 FULL 桶的实活；**这正是
  "60fps 决战"之外的第二决战面**。若 warm >1s，杠杆 = TilingPlan 窗口并行 + 链趟合并，
  plan 期按 D-05-08-T6-1 先例做杠杆分解再裁决。

### B.2 映射②「预览重印 0.01s」→ 我方尾平面缓存命中重渲腿

- **语义对齐**：SpektraLab 重印 ≠ 全链重算；我方对应物 = **尾平面缓存命中后的重渲腿**
  （参数变更只重跑尾段 box 及之后，`TerminalTailPolicy` 尾平面键局部性；EOTF 切换只重跑
  EOTF box 起尾段）。既有断言面：`Tests/LightamerTests/DrtTailTests.swift:304
  testSameRecordSecondRunIsAllHits` / :318 `testEOTFSwitchReRunsOnlyTheTail`。
- **测法**：同参二次渲染计时（全命中腿）+ 单参数 tick 尾段重放计时，preview-2560 桶，
  中位。命中腿预期亚毫秒~毫秒级（blit/单 box 重放），≤10ms 门可达性高。
- **不可比项（如实注记）**：我方 **preview 全链 warm 85ms**（M2-6-3 bench）与 0.01s 不同
  语义（全链场景渲染 vs LUT 重贴），**不拿 85ms 去对标 0.01s**——对标行落在尾命中腿，
  全链 warm 85ms 作记录档 + 语义差异注记。

### B.3 二进制 32MB 行（附带）

- SpektraLab 32MB 单二进制为我方无对应单一体（Swift + 框架 + 内置 AI 模型 ≈193MB
  Resources/AIModels，M2-10-01-SUMMARY:42）。**不设对标**，落注记即可（开源分发 DMG 体
  积非 M2PERF SC 族）。

---

## §C. closeout 组织方案（M2PERF-02）

### C.1 正本形态

- **M2-11-VALIDATION.md 兼作 M2 收口正本**（推荐案，OQ-8）：单一文档承载
  ①M2PERF-01 重述后逐条 SC 三列对账 ②M2PERF-02 全族终验 ③M2 挂账总汇编（移交
  V2/Maintenance 的单一清单）。不另开 gsd-complete-milestone 全套流程（里程碑收口事实
  由 VALIDATION + 翻账批承载，避免双状态源）。

### C.2 终验证据组织

1. **全 `--all` 终轮**（orchestrator 批准 + 运行中监视 + MEMFAIL 8G 机检 + L055 核读
   纪律：逐 bundle tail 核「末条 Executed = All tests 总计」+ abnormal 签名扫描）——
   基线 = 2955/16/0（M2-10 终值）+ M2-11 新增数。
2. **M2 族全扫**：M2LIB/M2NODE/M2GRADE/M2DRT/M2MASK/M2VER/M2EXP/M2AI 各族已随各
   phase VALIDATION 翻账 Delivered——closeout 只做机械扫（uncheck 残留 = 零 +
   `[ ]` 剩余 = M2PERF-01/02 本体），`grep -n "^\- \[ \]" REQUIREMENTS.md` M2 段核。
3. **翻账批**：REQUIREMENTS M2PERF-01/02 + ROADMAP M2-11 行 ✅ + STATE.md M2-11 翻
   complete + TODO M2 条目落账 + GOAL-STATE 续接点（M2 closed → V2/Maintenance 站）。

### C.3 GUI 验收轮并案（一轮多义）

M2-11 GUI 验收轮一次承载四类义务（computer-use 方法学，M2-3 先例）：
①AI 面视觉走查（M2-10 交接件 3：设置页/对话框/双入口 Alcedo 对照截图，观察清单 =
`M2-10-VALIDATION-INPUT.md` 挂账 5）；②PERF-04/06 真机 hitch 走查（拖动/缩放/平移/
万张滚动）；③L057 面板取消腿走查（M2-9 走查批纪律：每个 NSOpenPanel/NSSavePanel 取消
腿）；④DRT 走查观察项遗存（M2-6-3 走查清单 5 项中 HDR 实机项如无 HDR 屏维持挂账）。

### C.4 交接四件对账（M2-10 → M2-11，全部有承接位）

| 交接件 | 承接位 |
|---|---|
| 1. 60fps@100MP 复验 | §A.1 审计 + §F 待新测 1-3（含 M2-10 全链加载后复测） |
| 2. MCP 面零改动 + semantic_search defer | closeout 机检：`git diff` MCP/Export/Version 红线域零命中复跑（M2-10 签核批同款）；defer 维持（OQ-12-A 签认，无新增动作） |
| 3. AI 面 GUI 走查 | §C.3 ① |
| 4. flaky 清算三案 | §D 并案清单 |

---

## §D. flaky 清算批并案清单（五件：三案 + 脚本两件）

| # | 件 | 性质 | 在案事实 | 处置方向 |
|---|---|---|---|---|
| 1 | `SidecarV5Tests` ANE flake | 环境型 | 五波台账两红三绿（01 执行/06 验收/07 首轮红；07 补跑/07 续班终轮绿 13.338s）；`ANECCompile() FAILED` 宿主编译态劣化窗口 + ~68h 重启复绿；域零接触机检四波 | 环境归因维持（M2-10-VALIDATION.md:35,66）——硬化方向 = 宿主 ANE 态自检/超时阈值/重试协议（OQ-3 裁决改码深度） |
| 2 | `LayerE2ERoundTripTests` 负载型 flaky | 负载型 | M2-2-2 起在案；M2-4-1 全套轮 SIGTRAP 同测试同形态；多次「隔离 ×3 绿」（GOAL-STATE:65） | 复现律统计落账（不改码）；若 M2-11 期间再现 → 隔离复现律采样再定 |
| 3 | `LibraryThumbnailBridgeTests.testPrioritizeReordersQueuedProductions` | 时序竞争 | 两连击复现（M2-10-05 执行批 + 验收批同断言同测试；隔离/全量复绿口径两批逐值一致）；06/07 未复现 | 队列顺序竞争断言硬化（确定性改码候选——生产队列序断言改轮询/超时窗口或序注入） |
| 4 | L055 test-direct.sh 崩溃假绿解析器 | 脚本缺陷 | 宿主中途 crash 时 BUNDLE 行取末条类 suite `Executed` 行当计数（LESSONS.md:522）；M2-9 起挂「脚本修复另案报备」 | 脚本级修复：`terminated abnormally` / `Restarting after unexpected exit` 签名 → bundle FAIL + 末条 Executed 须为 All tests 总计行校验 |
| 5 | 「Executed 1 test」单数 quirk | 脚本缺陷 | `Scripts/test-direct.sh:162` 判据 regex `Executed [0-9]+ tests` 不匹配 xctest 单数形式「Executed 1 test」→ executed=0 → L028 防空转误报 FAILED（单测试/类过滤小批量轮场景） | regex 改 `tests?` 单复数兼容（一行修） |

- 1/2 为「非确定性、归因已定」案：**本 phase 不强行改测试逻辑**（环境型无靶；负载型未
  定位）——处置 = 台账收口 + 可观测性增强，OQ-3 裁决深度。
- 3/4/5 为「确定性缺陷」件：修复即消型，建议本 phase 全收。

---

## §F. 待新测清单（plan 输入；执行面按此立项）

| # | 新测项 | 服务对象 | 通道 | 既有面复用 |
|---|---|---|---|---|
| 1 | PREVIEW 全链 warm 复测（M2 默认链，100MP 真样张，preview-2560） | PERF-01 | bench 测试（PreviewChainPerfTests 家族） | M2-6-3 bench 形态 |
| 2 | 拖动两档复测（color 七件 / denoise 单件） | PERF-01 | 同上 | testPhase5DragGateTwoChains |
| 3 | nlmeans 预览降载加深（若 OQ-7 采纳）+ 复测 | PERF-01 缺口 | 改码 + bench | PixelPipe.swift:800 杠杆点 / testNLMeansPreviewDowngradeTiers |
| 4 | FULL 桶 45-60MP/100MP 全渲染 cold/warm | SpektraLab 对标① | bench 测试 | FULL 1024 锚 + M2-10-02 分解探针方法 |
| 5 | 尾平面命中重渲计时（同参二次 + 单 tick 重放） | SpektraLab 对标② | bench 测试 | DrtTailTests 命中断言面 |
| 6 | open→首帧端到端（warm；RAW9 编译冷单列） | PERF-05 | bench/探针 | QL 探针分解法 |
| 7 | 档 B 吞吐 Release 复核 | PERF-06 | Release 直启（D-09-04-D9 重签惯例） | 09 perf 明文义务 |
| 8 | GUI hitch 计量（拖动/缩放/平移/万张滚动） | PERF-04/06 | computer-use 走查 + signpost | M2-3 方法学 |
| 9 | Instruments trace（编辑会话 + 滚动会话） | PERF-03 | GUI 实机 Instruments | signpost 探针面对齐 |
| 10 | GUI 稳态内存工作集 profile | PERF-02 | Instruments/footprint 探针 | clearCaches/LRU 面在码 |
| 11 | 全 `--all` 终轮 + PERF-07 门复核 | M2PERF-02 | test-direct.sh（批准制） | 2955 基线 |

---

## §R. 风险与如实注记

1. **FULL 桶 <1s 对标可达性未知**——100MP float32 全幅带宽主导，可能触发 TilingPlan
   实战化杠杆（非小改）。plan 期先测后裁（杠杆分解先例 D-05-08-T6-1）。
2. **GUI 通道依赖 computer-use**——synthetic pointer 不可达先例（M2-7 E3）；走查批
   需用户授权形态与 M2-3 同款（已有 2026-09-27 授权面）。
3. **Release 计量环境处置**——直启注入重签流程在案（09 perf §PERF-07 执行期发现），
   Release 轮按既定惯例，一次性环境处置非工程改动。
4. **审计为誊录性质**——所有在案数字未复跑；终验轮全 `--all` 复跑时以机检值复核
   PERF-07 等 bench 门（§F #11）。
