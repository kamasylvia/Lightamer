# R6 修复批 — 综合验收（2026-10-27）

## 结论

**PASS / 0 B + 0 M + 0 m + 2 obs**

验收对象 = 五 commits（`363e4387` 导入零行 / `95729b14` DRT / `f77d3488` film /
`eba66447` raw / `9224188f` 账本），基线 `29be5cba`。独立复跑全套
**4292/35/0**（与战报逐位同）；导入零行 GUI 实机复验 **5/5 全绿**
（grid 行到达 0.54-0.66s，≪10s 窗）；反自取消抽查 = 机制面 sabotage
两法**确定性真红**（判别力成立），生产缝 sabotage 假绿（竞态概率性
边界，与 DECISIONS §1.3 阈值申报自洽，入 obs）。

## 一、AC 逐条对账

### 1. T1 导入零行（机制链亲核）

| 项 | 核验 | 判 |
|---|---|---|
| 修法在位 | `coalescer.invalidate()`（`LibraryProjectController.swift:464`）恰在 nil 直写（:465）之前 | ✅ |
| 三面锁语义 | submit / drainWindow / flushTerminal 三面各自锁内 `guard !invalidated` 先行返回（diff 亲核三处） | ✅ |
| 已交付不回撤 | invalidate 只置 flag + 清 pending，不触 lastDelivery/已交付面 | ✅ |
| 交错形态 | 写点全景亲核：:418 deliver 闭包（交付面）/ :438 importing / :465 nil 直写；terminal bypass = submit 内 `Task { @MainActor flushTerminal() }`（~:822）与 runImport resume 竞争 main queue——同帧 nil→复活吞掉中间 nil，onChange else 分支永无 nil 观测 | ✅ |
| 消费者 | `ImportProgressModifier`（`WorkspaceHostView.swift:1110-1140`）onChange else 分支 finish + `reloadFirstPage()` = grid 行到达发布唯一触发，亲读在位 | ✅ |
| +3 法 | `ImportProgressCoalescingTests` +2（确定性交错：三交付 job 全排队后 invalidate → 零交付 + 已交付不回撤 + 后 submit 丢）/ `ImportCompletionRegressionTests` +1（真 runImport 后 20 轮 drain 终态稳定 + DB 3/3）逐字读毕，发布断言非时间窗（与 §1.3 申报一致） | ✅ |

### 2. T3 姐妹载体三件

- **WorkspaceModel diff 逐 hunk 核**（封存面例外 = 载体族区段，M8-FIX 先例）：
  ①三段 doc 注释偏离申报（rawDecodeOverrides/drtRecords/filmRecords 各自
  R6 EXEMPT 注释，含病链与惰性论证）②三 drop 函数本体删除
  （dropSessionOverrides/dropSessionDrtRecords/dropSessionFilmRecords）
  ③closeEditor 体（三 drop 调用行删 + doc 重写为家族全员豁免）
  ④processVersions doc 勘误句（"unlike the sisters" 对比句移除）——
  四类 hunk 恰与 DECISIONS §四逐项吻合，**载体读写面函数（setSession*/
  restore*/read faces）零语义改动**（不在 diff 中）。✅
- **判定链两 guard 亲核**：`EditorWorkspaceShellView.loadCurrentImage()` 的
  `guard editorState.loadedImageURL != url`（:193 区）+ `PipeCoordinator`
  的 `historyLoadedURL != url`（:1210 区，包裹全部 restore 腿）——重开同图
  全跳 load 链成立；`loadedImageURL` 唯一写点 = `EditorState.swift:524`
  （load 本体，close 链不清）全仓 grep 亲证。✅
- **判别腿三件逐字**：
  - DRT：`DrtPersistenceTests` 改写——close 后 `hasDrtRecord` 为真 +
    `drtRecord(for:).peakLuminance == 650`（terminalTailPolicy 两读面）✅
  - film：`FilmCoordinatorTests` 改写（close 后 carrier 读面答保留值）+
    **新真渲染门腿** `testCloseKeepsTheFilmTailPolicyResolvable`
    （commit 起 `filmTailPolicy(.preview)` 非 nil → close 后仍非 nil）✅
  - raw：`SidecarV5Tests` 新法 `testCloseKeepsTheSessionOverridesForTheReopen`
    （双 url overrides 经 close 存活）✅
- raw 病链行号（`RawDecodePanelView` reseed 读空载体 → 控件归零）亲核在位。✅
- `DrtPanelModelTests` 改写 = drop 退役后编译适配（per-url reset 等价），
  零增量、零语义漂移。✅

### 3. T2 omp obs-3（文档化处置）

`.work/gui-acceptance/r6-axpress/Synthetic-Input-AXPress-Notes.md` 在位：
列级 id 覆盖机制（InspectorView:133 祖先穿透 + latitude/placement 显式
contain 存活例外）+ AXPress 驱动配方 + 不修三依据（frozen inventory /
.ignore 吞 title 风险 / omp 处方正向）+ 系统性列级容器化留独立批。✅

### 4. diff 审

- `git diff bf93e7bc..HEAD` = 纯账本 4 文件（R6-DECISIONS/SUMMARY/all-runs
  两 log）——bf93e7bc（m9-2 账本）位于四个 fix commit **之后**，产品面 0 文件。
- `git diff 29be5cba..HEAD` 产品面 = **恰 8 文件**
  （LibraryProjectController.swift + WorkspaceModel.swift + 6 测试文件），
  与 DECISIONS §四登记逐位同。
- **封存面 17 件机检零 diff**：Core/IOP 自基线全量零 diff（name-only 空）；
  17 件具名文件逐一与 diff 清单比对全 clean（TerminalTailPolicy/
  DrtTailAssembly 等内嵌于 Core 文件，随 Core 全量覆盖）。✅

## 二、全套独立复跑

guard --wait PASS（free 77%）+ 起跑前 ps 清零（0 Lightamer 实例）+
`machine-guard.sh --monitor 21600` 伴跑 + nohup disown
（`all-runs/r6-acc-all.log` / `r6-acc-monitor.log`）：

**TOTAL = 4292/35/0（3940s）** —— 与战报 4292/35/0 **逐位同**

| bundle | 本轮 | 登记值 | 逐位同 | peakRSS |
|---|---|---|---|---|
| IOP | 788/1/0 | 788/1/0 | ✅ | 5552MB |
| IOPParity | 529/11/0 | 529/11/0 | ✅ | 4536MB |
| Layers | 507/5/0 | 507/5/0 | ✅ | 875MB |
| Library | 779/4/0 | 779/4/0 | ✅ | 746MB |
| Sessions | 285/4/0 | 285/4/0 | ✅ | 1212MB |
| Export | 385/4/0 | 385/4/0 | ✅ | 4960MB |
| App | 1019/6/0 | 1019/6/0 | ✅ | 2832MB |

零失败、零 MEMFAIL（全部 ≪8G 门）、monitor 零 RSS-KILL。skip 35 =
39-4 宿主态带内（±4 容差内）。

## 三、导入零行 GUI 实机复验（关键面）

配方 = R5-2 复现面（DD 直启 Lightamer 二进制 + `-la_editor_probe
/tmp/m8fix-import`〔16 张 tif fixture〕，0.1s 轮询 stderr 打行级时间戳，
fresh throwaway 项目每轮新建；日志 `/tmp/r6-acc-gui/round{1..5}.log`）：

| 轮 | grid 行到达 | 行数 | zero-row FAIL |
|---|---|---|---|
| 1 | **0.54s** | 16/16 | 无 |
| 2 | 0.66s | 16/16 | 无 |
| 3 | 0.66s | 16/16 | 无 |
| 4 | 0.65s | 16/16 | 无 |
| 5 | 0.65s | 16/16 | 无 |

**5/5 全绿**，到达 0.54-0.66s（探针 10s 窗的 1/15 量级）。DB 法证：最新
throwaway 项目 `SELECT COUNT(*) FROM images` = **16**（行恒落库 + grid
发布全通）。对照基线：R5-2 批 9 次 4 失败（高载）/ obs-4 批 5 次 2 失败
（低载）——修复后零失败。

卫生：每轮实例 SIGTERM 清零（ps 复核 0 实例）；
`library.recentProjects` 被探针 throwaway 项目污染 → 整键删除复核
（键不存在 = 干净态）；诊断残件清。

## 四、判别力抽查（反自取消）

`/tmp/r6-sabotage` worktree（HEAD 产品码与 9224188f 全同），独立 DD
容器构建，两档 sabotage，主树零触碰，做完删净（worktree + DD 容器 +
DD glob 最新态复核回主 DD）：

- **sabotage 甲（修复撤除原样 = 删 run tail `coalescer.invalidate()`
  调用）→ 生产缝法假绿**：`--bundle Library
  'ImportCompletionRegressionTests'` = 3/0/0 全过。复活竞态在本机低载
  单轮下未触发——与 DECISIONS §1.3 申报「竞态是概率性的、时间窗断言
  会假绿」自洽（反面同真：撤修后发布断言亦可假绿）。
- **sabotage 乙（invalidate 语义掏空 = 保留调用、去 flag 去 drop）→
  机制面 2 法确定性真红**：`--bundle App 'ImportProgressCoalescingTests'`
  = 5/0/**2**——
  `testInvalidationDropsPendingAndEveryQueuedDelivery` 两断言红
  （零交付 / post-invalidate submit 丢）+
  `testInvalidationKeepsDeliveredHistoryAndKillsTheQueuedWindow` 红
  （[1,2]≠[1]）。

**结论**：修复的判别主腿 = 机制面确定性交错 2 法（sabotage 下必红）；
生产缝法 = 终态稳定性保险（非判别主腿）——两腿分工与 executor 阈值
申报完全一致，判别力成立、无自取消。

## 五、观察项（0 阻塞）

1. **obs-1（生产缝法判别力画像）**：sabotage 甲实锤
   `testRunImportNilTerminalNeverResurrects` 在修复撤除下假绿（3/0/0）。
   非缺陷——申报边界如此设计（机制腿承担判别）；登记供后续若有人
   单删生产缝调用时知悉该法不设防。
2. **obs-2（验收期间主仓并行推进）**：全套复跑期间 orchestrator 推进
   `ea437ac2`/`6667e8ff` 两笔账本 commit（9224188f→6667e8ff）——已核
   **纯 `.work/` 零产品面**，全套/GUI 复验产物 = 9224188f 构建，源码
   层与 6667e8ff 全同，结论不受影响。

## 六、卫生与提交

- 全套 + GUI + sabotage 三段各自收尾清零（ps 亲证 0 Lightamer/
  xcodebuild/machine-guard 进程）；monitor 用后停。
- /tmp 遗留：`r6-acc-gui/`（round log + 脚本）与 `r6-acc-*` 日志按
  惯例留存下轮；worktree/DD 已删净。
- 本报告单 commit（`docs(r6): acceptance report`，内部账本免关联，
  不 push）。
