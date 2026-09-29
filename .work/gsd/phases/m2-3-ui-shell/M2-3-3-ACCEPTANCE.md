# M2-3-3 ACCEPTANCE — 编辑器面（三段布局 + 七页签归页 + 示波器 GPU + RAW Decode 面板 + Settings 十入口）（独立验收报告）

> **PASS / 0 error + 1 minor**（3 条 observation 不计数，见 Findings）
> 独立验收 subagent（2026-09-29）。plan = checker 修正版（`897bcb2` 批，含 E1 勘误 =
> DT 页 Vignette+M2-6 占位、AgX 失挂）；执行 = 6 commits（两班接力）：
> 前任 worker T1 `46e13fb` → T2 `29553ba` → T3 `05317d1`（T4 在制品机器重启阵亡），
> 续班 worker T4 `921a98f` → T5 `8d556c7` → T6 `07ef644`（收口）；另有 orchestrator
> 越界豁免件 `02f727f`（边界审计按剔除口径，本报告第 5 节有翻案级 findings）。

## Verdict

12/12 AC 全过、六重点核查全过（含 T1 前置硬闸 DECISIONS 在案）、12 条偏差全部核实
且合理、红线零违反。两班接力交接质量高（续班对前任在制品的 4 处救援修复逐条核实，
front-matter 膨胀字段申报与 diff 逐 hunk 一致）。

**复跑归因事件（本验收批的核心 findings）**：首复跑 **2160 / 14 skip / 6 failures**
——6 条 failures 全部集中在 `McpHostTests` 三个 flock 测试（LOCKED handshake 超时），
**与本 plan 变更面零交集**（本 plan 30 条新测试全绿、其余 2157 全绿）。隔离 ×3 +
非沙盒复跑均稳定复现（非负载 flake，是确定性红）。根因经 sample 栈 + 精确形状探针
实锤 = **豁免件 `02f727f` 的修复不完整**：其注释「`print` has already delivered the
bytes」在 pipe 上不成立——C stdio 对 pipe 全缓冲，fixture park-until-EOF 永不走到
exit 路径，LOCKED 字节滞留缓冲，handshake 必然超时（sample 显示子进程已 park 在
`read()` 而 LOCKED 仍在 stdio 缓冲内）。修复 = `syncStdoutBestEffort()` 补
`fflush(stdout)` 一行（豁免件同函数，2 行 hunk），修复后单族 18/18 绿（0.5s），
全套重跑 **2160 / 14 skip / 0 fail**。该缺陷归 orchestrator 豁免件域，非执行 worker、
非本 plan 变更面；验收方修复以 `fix(mcp)` 单独提交。

翻账：REQUIREMENTS M2UIW-01（双面齐终 Delivered）/ M2UIW-02 / M2UIW-03 / M2UIW-04 /
M2UIW-05 → Delivered；M2DIS-03 补终注（七页签 IA 收纳兑现）；M2DIS-04 → Delivered；
M2LIB-07 补 Import Defaults 设置页注记。验收批另修 1 处 minor 文档悬空引用
（DECISIONS KD-2 补 34/33 基数落位，测试注释所引「DECISIONS D3」编号漂移注记）。

## 复跑（独立）

- 验收方 fresh `xcodebuild build-for-testing`（HEAD = `07ef644`，工作树仅 .work
  历史滞留物）→ `caffeinate -dis Scripts/test-direct.sh` 全套：
  **R1 = Executed 2160 tests, with 14 tests skipped and 6 failures（871.0s）**。
- 6 failures 归因（`McpHostTests.testFlockKernelSelfReleaseAfterCrash` /
  `testFlockMutexTwoProcesses` / `testFlockReleasedOnHolderExit`，各 2 断言）：
  - 隔离复跑 ×3 全部 `Executed 18 tests, with 6 failures`（90-96s，稳定复现，
    非相邻域负载 flake——M2-2-3 在案「负载型留观」族的判定条件不成立）；
    非沙盒环境复跑同红（排除验收 Bash 沙盒伪影）。
  - 手动 spawn 同一产物 fixture（`-la_mcp_hold_lock`）：普通形状 LOCKED 正常输出
    （exit 路径 exit-flush 掩盖）；**精确测试形状**（stdout/stdin 双 pipe 保持打开）
    6 秒 pipe 零字节（非阻塞读 None）——确定性 hang 实锤。
  - 对卡住子进程 `sample`：栈 = `main → holdLockFixtureIfRequested() →
    NSConcreteFileHandle readDataOfLength: → read (blocked)`——子进程已过
    acquire+print、park 在 stdin 读，LOCKED 字节滞留 stdio 全缓冲。
  - **归属**：`02f727f` 豁免件把 crash（fsync-on-pipe EINVAL → SIGABRT）钉死后，
    引入静默 `return` 分支但未补 `fflush`——crash 形态变 hang 形态。前任终轮
    0fail 声明在其执行时刻真实达成（产物代际/环境态差异，未完全定案，见 Findings
    O-3），但该域缺陷在当前 HEAD 是确定性红。
- **修复后**（`fflush(stdout)` 补入 `syncStdoutBestEffort`）：`McpHostTests` 隔离
  18/18 绿（0.533s，handshake 立达——90s 超时窗归零互证根因）；全套重跑
  **R2 = Executed 2160 tests, with 14 tests skipped and 0 failures (0 unexpected)
  in 790.8s**——与执行方声明终轮（2160/14/0, 697.4s）计数逐值一致。
- skip 14 = M2-3-2 终态原样（LA_THUMB_BENCH MANUAL-ONLY gate 等），零新增 skip。

## Commit 边界核查（AC#12 + 重点④⑤）

- 6 commits + 豁免件逐个 `git show --stat`；累计 `git diff --name-status d603ba2..07ef644`
  = **31 文件**。对 front-matter 申报集（29 项）核对：
  - 申报集全量命中；`EditorAreaView.swift` **全 plan 零 diff**（比「增量缝」更保守，
    KD-1 零 diff 包装路径——AC#2 从字面达标走向事实达标）。
  - 两笔计划外文件均申报在案：`LightamerApp.swift`（D2 偏差，见下）+
    `McpServerController.swift`（D3 豁免件 = orchestrator 修复，剔除口径成立——
    本 plan 6 commits 未触碰该文件）。
  - `M2-3-3-PLAN.md` 自身 diff = T4 膨胀字段触发时的 front-matter/纪律 5 同批申报
    （纪律 5 要求的行为，非越界）。
- `LightamerCore/` diff = 恰 3 文件 = 申报例外全表（`RAWDecoder.swift` +
  `RAWTechnicalParams.swift` + `HistoryHash.swift`，全在 921a98f 单 commit 内 =
  膨胀字段两文件与主缝**同批申报**核实）；`LightamerCore/Sources/Library/` 域
  **零 diff**（重点⑤ ✓）；legacyBody 树资产（ContentView/Sidebar/legacy 四族）
  零 diff ✓；Inspector 33 面板 + InspectorView/InspectorRowView/IOPPanelProvider +
  HistogramReduce 既有文件零 diff ✓（AC#4）。

## 六重点核查结论

1. **T1 前置硬闸（KD-1）**：DECISIONS KD-1 在案记录前置核对结论——M2-2-4 冻结快照
   （`LibraryLegacyGateTests` 7 个 `Set<String>`：session/catalog/mode-switcher/
   settings-catalog/content/project face 族）逐一核读，**零编辑器域 identifier**；
   执行走更保守的零 diff 包装路径（`git log d603ba2..07ef644 -- EditorAreaView.swift`
   = 空）。快照测试 T5 后复跑全绿。硬闸合规。
2. **TAB-MATRIX 33 恰一次 + 禁用 6 零命中（AC#3）**：路由表页行 8+13+1+1+8+0+0=31 +
   topBarSheet 2（watermark/borders）= 33；`EditorStackRoutingTests` 为**真动态断言**
   （`registerDefaultProviders(defaultFace: true)` → `panelOpNames` 动态集减
   TextOverlay，恰一次 + 基数 33 双钉），非硬编码集合。禁用 6 名 `git grep -i`：
   filmicrgb/sigmoid/denoiseprofile/nlmeans/bilateral 三文件零命中；agx 7 处命中全部
   为 E1 勘误注记/注释（路由条目 `panels(for:)` 零命中）。DT 页占位节存在
   （`EditorTabRoute.swift:186-193` specialContent + TAB-MATRIX:53）。TAB-MATRIX md
   与表逐行对账有测试钉（`testTabMatrixMatchesTheRoutingTableLineByLine`）。
   基数口径差异（plan 37/31 vs provider 34/33）在 TAB-MATRIX 头注完整归因（模块 vs
   面板 provider 两口径），执行取动态集合规。
3. **示波器 L031 队列路由 + L014 fence（T3 完成态复核）**：新增代码
   `makeCommandQueue` grep 零命中（ScopeReduce/PipeCoordinator/ScopePanelView/kernels
   四文件）；`ScopeReduce` 全部经 `makeEncoder`/`makeRoutedCommandBuffer` 唯一路由；
   直方图与波形读回前均有 fence（`ScopeReduce.swift:123-126` / `:207-210`，L014
   HistogramReduce 先例同型）。PipeCoordinator tap = PREVIEW 完成回调后的 additive
   follow-up（不进渲染生产者链，D-X1 单生产者不变式保持），ScopeThrottle 纯
   MainActor 状态机（≤15Hz 流式 + 250ms idle settle + 不可见零 tap）单测在册。
4. **Core 例外面**：`RAWDecoder.swift` public 缝纯增量（`decode` 第二参数默认
   `.identity` = 既有调用点编译级零改动）；D4 内部重构
   （`resolveDecoderVersion` 纯函数）与旧 version-selection 块逐语义等价
   （automatic = v9 ⇔ macOS 27 ∧ probe 含 v9，测试矩阵 7 断言钉死）。膨胀字段
   `RAWTechnicalParams`（Optional + encodeIfPresent + `applyOverrides` nil 腿不写）+
   `HistoryHash`（nil 不折）——**nil=零漂移单测为真**：`testIdentityDecodeIsByteIdenticalToTheDefaultPath`
   断言 params Equatable 相等 + hash 相等 + **编码 JSON 键集不含 sharpnessAmount/boost**
   （pre-M2-3-3 字节形契约，三维钉死；像素面因 CIRAW speckle 非确定不作断言面 =
   D7 的诚实裁决）；`testNilLegsLeaveTheHashUntouched` 纯 Core 面再钉 hash 纪律。
   五腿 apply+drift（NR×3/sharpness/boost/aggregate/decoder-version）+ 越界钳制断言
   全在册。
5. **legacyBody/Library 域零 diff**：见边界核查节（✓）。
6. **偏差核查**：续班 4 偏差 + 前任偏差全部核实——
   - **D2（LightamerApp.swift 越界一行）判合理**：基线 `d603ba2` 的
     `SettingsView.swift:68` 已有 `@Environment(PipeCoordinator.self)` +
     `:369/:404` `refreshDisplayProfile()`，而 Settings scene 从未注入——13-2 存量
     缺失注入属实（Observable 环境缺失 = SwiftUI 运行时 fatal），不补则迁移后的
     displays 页打开即 crash；迁移显形 + 一行增量修复 + DECISIONS 申报，处理正确。
   - D1 膨胀字段触发 = front-matter/纪律 5/DECISIONS 三处同批申报核实（非静默扩）。
   - D4 decodeRAW 重构 = KD-4 授权腿内（见上）。
   - D5/D6 aggregate NR 腿走 INIT options + 空字典等价 = identity 单测钉死。
   - D7-D12（identity 断言面/会话载体/草稿救援 4 处/计数口径/Keyboard v1/窗口宽度）
     逐条与 diff/测试实态一致。

## 逐 AC 表

| # | AC | 结果 | 证据 |
|---|---|---|---|
| 1 | 三段方位 + 左竖胶片条 + 工具轨三态 marker | ✅ | shell HStack `[rail|filmstrip(148pt)|viewport|right(280pt)]`；`editor.rail.*`/`editor.stack.tab.*` marker 断言（EditorStackRoutingTests 9 条） |
| 2 | EditorAreaView 零迁移 | ✅ | 全 plan 零 diff（超「仅增量」达标）；legacy gate 快照 7 族零编辑器域；既有测试零改动全绿 |
| 3 | 路由完备性 + 禁用 6 零命中 + md 对账 | ✅ | 动态恰一次断言 + 基数 33 双钉；grep 证据（agx 仅勘误注记）；md 对账测试 |
| 4 | 33 面板 + Inspector 族零 diff | ✅ | 全量 diff 文件清单核（Inspector 域零文件） |
| 5 | ScopeReduce parity/确定性/单队列/fence | ✅ | ScopeReduceTests 7（solid/bimodal/gradient 逐 bin + 像素总数、波形列 parity+确定性、1x1 退化）；`makeCommandQueue` 零命中；fence 两处 |
| 6 | 示波器节流状态机 | ✅ | ScopeThrottle ≤15Hz/idle 补算/不可见零 tap 断言（ScopeReduceTests 内 2 函数 3 语义） |
| 7 | RAW overrides 四断言 | ✅ | RawDecodeOverridesTests 5：version 矩阵/identity 零漂移/apply+drift/钳制/nil 腿 hash 纪律 |
| 8 | RAWDecoder 唯一 Core 触点仅增量 | ✅ | public 缝纯增量；D4 重构授权论证 + 等价测试；Decode 域既有测试零改动全绿 |
| 9 | Settings 页集/三选/冲突检测/门控零迁移 | ✅ | SettingsPagesTests 9（十项精确 + Acceleration/Updates 负例 + gate 两态 + round-trip + 冲突检测 + Import Defaults）；`visibleCatalogSectionMarkers` 零 diff；LibraryLegacyGateTests 11 零改动全绿 |
| 10 | String(localized:) 全量 + legacyBody 零 diff | ✅ | 新 UI 8 文件 localized 全覆盖（直写 key = M1 InspectorView 惯例；`RAW 8`/`MIT`/Keyboard 命令 id = 技术字面豁免族）；legacyBody 树零 diff |
| 11 | 全套 0 fail，计数 ≈ 基线+25..35 | ✅（修复后） | R2 = 2160/14skip/0fail（+30 = routing9+scope7+rawdecode5+settings9，带上沿）；R1 的 6 fail = 豁免件域缺陷，验收批已修（见复跑节） |
| 12 | diff 边界 == 申报集 | ✅ | 31 文件 = 申报 29 − EditorAreaView（零 diff）+ 2 申报偏差/豁免 + PLAN 自申报更新 |

## Findings

- **F-1（error 级，验收批已修，归属豁免件域）**：`02f727f` 修复不完整——
  `syncStdoutBestEffort` 在 pipe 分支静默 return，未刷 C stdio 全缓冲；fixture
  park-until-EOF 永不 exit → LOCKED 滞留缓冲 → `McpHostTests` 三个 flock 测试确定性
  超时（全套 R1 = 6 failures）。修复 = 补 `fflush(stdout)` 一行 + 注释更正（验收批
  `fix(mcp)` 单独提交）。修复后单族 18/18 绿（0.5s）、全套 R2 = 2160/14/0。
  **不计入本 plan 执行缺陷**（文件不在申报集、变更面零交集、前任终轮声明在其时刻
  真实）。
- **F-2（minor，验收批已修）**：DECISIONS 基数裁决编号悬空——TAB-MATRIX:16 与
  `EditorStackRoutingTests:68` 注释均引「DECISIONS D3」指 34/33 基数，而终稿
  DECISIONS.md 的 D3 = 豁免件条目（T2 执行时的 D3 编号在 T6 终稿被占用）。修复 =
  KD-2 节补基数落位注记（本批同 commit）。
- **O-1（observation）**：DECISIONS KD-3/SUMMARY 称「3 条状态机单测」，实际
  ScopeThrottle 断言为 2 个测试函数（覆盖 ≤15Hz/idle/零 tap 三语义）。总数 7 正确，
  措辞差异不修（历史行）。
- **O-2（observation）**：`RawDecodeOverridesTests.testIdentityDecodeIsByteIdenticalToTheDefaultPath`
  的两次 decode 均显式传 `.identity`（默认参数路径 = 同一函数值，无行为差异可能），
  注释已诚实自述——cosmetic，不修。
- **O-3（observation，未完全定案）**：前任终轮（21:44，0fail）与验收复跑（22:04 起，
  稳定 6 fail）同 HEAD 源码不同结果——豁免件修复 commit（21:33:58）早于终轮，产物
  代际（21:33:06 构建的产物内容与源码写入时序）无法事后考古。不影响 F-1 修复的正确
  性（`fflush` 对 file/tty/pipe 全语义正确且幂等）；若后续该域再出红，优先怀疑
  test-direct 直启环境下子进程 stdio 行为，而非测试或生产逻辑。

## 续班交接质量注记

两班接力无断层：续班对前任 T4 在制品的 4 处救援修复（macOS 27 SDK 改名 key/Picker
selection/public 面+Equatable/MARK 恢复）逐条在 `921a98f` diff 核实；front-matter
膨胀字段申报与 Core 3 文件 diff 逐 hunk 一致；D1-D12 偏差全案可追溯；GOAL-STATE
续接点完整（C 档第 2 停语义清晰）。前任三 commit（T1-T3）的 DECISIONS 引用与
续班终稿的编号漂移（F-2）是接力唯一的记账毛刺。

## 翻账（本批同 commit）

- REQUIREMENTS **M2UIW-01** → `[x]` 终 **Delivered**（双工作区路由 M2-3-1 + 图库面
  M2-3-2 + 编辑器面 M2-3-3 双面齐；布局语义三分全兑现）
- REQUIREMENTS **M2UIW-02** → `[x]` **Delivered**（M2-3-3 T1 三段布局 + 左竖胶片条
  + 示波器/调整栈右栏；推挤语义 = 推视口不推胶片条）
- REQUIREMENTS **M2UIW-03** → `[x]` **Delivered**（M2-3-3 T2 七页签 + 节点头
  EXIF 四腿）
- REQUIREMENTS **M2UIW-04** → `[x]` **Delivered**（M2-3-3 T3 GPU compute 直方图
  256×4 + 波形小纹理；v1 波形呈现 = 小纹理 CPU 读（DECISIONS D6 登记项），P4 观察
  清单接账）
- REQUIREMENTS **M2UIW-05** → `[x]` **Delivered**（M2-3-3 T5 十入口导航；蒙版三选
  = 存储面交付、接线归 M2-7；Keyboard v1 = 展示/检测/恢复三面不活绑）
- REQUIREMENTS **M2DIS-03** → 补「Delivered 终注」（M2-3-3 七页签 IA 收纳兑现全半边）
- REQUIREMENTS **M2DIS-04** → `[x]` **Delivered**（M2-3-3 T4 CIRAW NR 参数族 +
  decoder version + boost 在 RAW Decode 页签暴露；Neural Engine 校准归 M2-5+）
- REQUIREMENTS **M2LIB-07** → 补 Import Defaults 设置页交付注记（M2-3-3 T5）
- 修复批：`fix(mcp)` fflush（F-1）；`M2-3-3-ACCEPTANCE.md` 本报告；DECISIONS KD-2
  基数落位（F-2）
