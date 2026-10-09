# M2-8 ACCEPTANCE-OMP — 「版本与历史」回溯二次验收（phase 粒度）

> 验收：omp 独立二次验收员（零共享上下文，不轻信首验结论，一切证据亲测），2026-10-09。
> 对象 = M2-8-1（版本模型核）+ M2-8-2（面板与交互）+ M2-8-3（收口 + 两 FINDING 修复）。
> 正本亲读：三 ACCEPTANCE + 三 SUMMARY + M2-8-3-DECISIONS + 仓库根 AGENTS.md「M2-8 架构增量」节。
> 时代树锚点 = `a26b005`（M2-8-3 验收 docs commit，FINDING 双修复已在树内）；HEAD 已演进至 sidecar v9，
> 回溯项以时代树亲证为准，现树语义保持另行核对。
> **结论头：PASS / 0 error + 1 minor（SHA 口径差，已注明消解）**

## 一、逐 plan 判定

### M2-8-1 版本模型核 — PASS

sidecar v7 双键、swap 单路径、version_ref 激活三面全部亲证成立（见 §二抽查点 1/2）。
首验结论（PASS / 0E+1m已修+2o）复核无实质分歧：BUNDLE-MAP 第二批勘误（SidecarV7Tests 9→8、
VersionSwapTests 10→11）在现树 `M2-4-0-BUNDLE-MAP.txt:274-275` 登记为 8/11，与实况 grep 计数
逐值一致（§二⑤）。

### M2-8-2 面板与交互 — PASS

Versions 面板、历史行升级、Copy Adjustments 三 pane、崩溃哨兵四交付物全部在位：
`App/Sources/Lightamer/UI/Shell/VersionsPanelView.swift`、
`App/Sources/Lightamer/State/AdjustmentTransfer.swift`（`isAdjustmentTransferable` 单谓词 +
`AdjustmentTransferTerminalTrio` 显式排除集，§二⑤）、
`App/Sources/Lightamer/State/CleanTerminateSentinel.swift` 均在位；
四测试类计数 5/7/8/3 与 BUNDLE-MAP 登记逐值一致（§二⑤）。
首验的环境臂归因（两轮 --all 各 1 条 ANE fail、冷态全绿、受害用例零触碰）逻辑链完整，
本轮定向测试未复现异常，予以采信。

### M2-8-3 收口 + 两 FINDING 修复 — PASS

零源码 diff 红线（T1/T2/T3 三提交）+ 两 error 级走查发现修复闭环全部亲证成立（§二③）。
首验结论（PASS / 0E+0m+2o）复核无实质分歧。

## 二、逐抽查点证据

### ① sidecar v7 双键 + 不双写 + v6 零漂移 + hash 隔离 — PASS

- 双键在位：现树 `LightamerCore/Sources/Sidecar/LightamerSidecar.swift:302,308`
  `versions: [SidecarVersionRecord]?` + `activeVersionID: String?`（v8/v9 后相加法扩展未动此二键）。
- `SidecarVersionRecord`（同文件 :833-888）：id/name/createdAt/updatedAt + 非活跃链
  `chain: SidecarHistoryRecord?`（internal，复用 FROZEN `{items,position}` 拼写）；
  public 面 = `init(id:name:createdAt:updatedAt:chain: HistoryStack?)`（:853-862，
  单点铸造 `SidecarHistoryRecord(stack:)`）+ `chainStack` 读回（:866）；active 槽
  `encodeIfPresent(chain)` 键缺席（:884-886）= items 不双写的编码面。
- nil 双键 v6 零漂移：时代树 `a26b005` 亲证 `decodeIfPresent`（:422,424）+
  `encodeIfPresent`（:482,483）；`schemaVersionCurrent = 7`（时代树同文件 :178）。
  现树该常量 = 9（后相 M2-10/M3 加法扩展所致，非 M2-8 回归）。
- `SidecarV7Tests` 8 法全文亲读（`Tests/LightamerTests/SidecarV7Tests.swift:100-305`）：
  ①v6 形 decode→re-encode 逐字节相等（:100-122，先断两新键缺席再回拨版本位，前置自洽在）；
  ②nil 面 = v6 形仅 schemaVersion 位差（字符串替换后全等 + 回拨字节 decode `schemaVersion==6`
  零版本键，:126-148）；③带版本 round-trip 字节忠实 + re-encode 同字节（:152-179）；
  AC#6 items 不双写 = active 记录无 `chain` 键 + 全文档 `"items"` 计数 == 1（:183-211）；
  hash 负测 = 篡改 `versions[].name` → `driftDetected == false`（:215-240）；
  dangling verbatim（:244-260）；pristine KD-6②（:264-281）；`copyingPrefixOf`（:285-305）。
- 定向实跑：`Scripts/test-direct.sh --bundle App SidecarV7Tests` =
  `BUNDLE|App|8/0/0|peakRSS=192MB|3s`，**8/0/0 全绿**。

### ② version_ref 激活 + 迁移轮换 + sink 注入 + swap 单路径 + pristine 收窄 — PASS

- reduced DDL：`LibrarySchema.swift:368-390` — `version_ref` 恰 5 列
  （version_id/element_id/display_name/created_at_unix/updated_at_unix），CASCADE DDL 在列定义；
  `versionRefColumns` 顺序冻结面与 DDL 逐列一致。`head_commit_hash` 不激活（注释钉明，
  首验翻面负测在案）。
- 快照轮换：`ProjectFileStore.swift:144-156` — `<stem>.pre-migrate.<stored>-<to>.bak`
  代际命名 + 同名旧件先删后照；`backup(from:to:)` 死参收窄注释在 :238-242。
- sink 注入单点：`VersionProjectionSink`（`VersionCoordinator.swift:50`）+ 装配点
  `EditorWorkspaceShellView.swift:192-196`（projectStore 有值装配 / Sessions 模式 nil）。
- swap 单路径：`switchTo`（`VersionCoordinator.swift:257-269`）=
  原链 `captureActiveChain` 写回槽 → 目标链 `installVersionChain` 装入 → 目标槽清 nil →
  `finishVersionAction` 尾；`installVersionChain`（`EditorState.swift:132-135`）=
  `history = chain + rebuildInstances() + rebuildLayerStack()`，EditorState 半径无 decode 面，
  同图零重解码结构性成立。
- pristine 收窄：`has_edits = history.position >= 0` 亲证三处同式 —
  `SessionIndexStore.swift:792`（backfill）、`:1274`（写回）、`SessionBatchApplier.swift:191`；
  `SessionIndexSchema.swift:76` 注释钉明语义。版本结构不翻转判定 = active 链续住 `history` 键的
  直接推论 + M2-8-3 端到端差分复核在案（DECISIONS §2.3）。

### ③ 两 FINDING 修复闭环 — PASS（SHA 口径 minor，见本节末）

- FINDING-A（Copy Adjustments 开即崩）→ 实 SHA `66f0cb7`（subject 与首验申报一致，
  `--stat` 5 文件：LightamerApp + AdjustmentTransferView + Project.swift + BUNDLE-MAP +
  SheetEnvironmentInjectionTests）。diff 亲读：新增 `AdjustmentTransferSheetContent`
  内容面（init 双参 + 内部 `.environment(versions)` + `.environment(editorState)`），
  app-root sheet 闭包改挂该面；其余面零触。机制（sheet 闭包在 `.environment` 写入之外）
  与 DECISIONS §3.2 一致。
- FINDING-B（toast 默认面零渲染点）→ 实 SHA `9d9ed87`（`--stat` 4 文件：
  WorkspaceHostView + Project.swift + BUNDLE-MAP + ToastFaceTests）。diff 亲读：
  `WorkspaceHostView` 底部 `safeAreaInset` 挂 `ToastBarView`（nil = EmptyView 零 chrome；
  有 toast = 22pt / surfaceRaised / monospaced / hairline + `status_toast` 标识）；
  legacyBody 零触。与 DECISIONS §3.3 申报一致。
- 回归测试亲读 + 实跑：
  - `SheetEnvironmentInjectionTests`（1 法：真 NSWindow + 真 `.sheet` 挂载生产面，
    runloop 泵至 onAppear + 5 轮 settled）：`--bundle App SheetEnvironmentInjectionTests` =
    `BUNDLE|App|1/0/0`，**1/0/0 全绿**。负腿（掏空注入 = 同 fatal 签名硬失败）为首验一次性
    实测证据，本轮未重复破坏性验证（只读验收纪律），采信首验记录。
  - `ToastFaceTests`（3 法：nil 零 chrome + 有 toast 22pt 面 + 真 WorkspaceHostView 挂载
    AX 树 `status_toast` wiring）：`--bundle App ToastFaceTests` = `BUNDLE|App|3/0/0`，
    **3/0/0 全绿**。
- **minor（SHA 口径差，已注明消解）**：本任务书正文引用的 `e9c03af`/`4e7fc58` 在当前树
  不存在（`git show` 报 unknown revision）；同 subject 同内容的 commits 实为
  `66f0cb7`/`9d9ed87`（父链 `66f0cb7→9d9ed87→a26b005` 连续，diff 内容与 DECISIONS §3 /
  首验 M2-8-3-ACCEPTANCE §三申报逐项一致）。判定为历史重写后的 SHA 漂移，非实质分歧；
  本报告一律以实 SHA 引用。

### ④ 定向测试 — PASS（3 类，禁全套已遵守）

| 类 | 命令 | 结果 |
|---|---|---|
| SidecarV7Tests | `test-direct.sh --bundle App SidecarV7Tests` | **8/0/0**（3s，192MB） |
| SheetEnvironmentInjectionTests | `test-direct.sh --bundle App SheetEnvironmentInjectionTests` | **1/0/0** |
| ToastFaceTests | `test-direct.sh --bundle App ToastFaceTests` | **3/0/0**（2s，223MB） |

合计 12/0/0，全绿。未跑 `--all`。

### ⑤ git 机检 + 单谓词 + 登记对账 — PASS

- fix commits `--stat` 与 DECISIONS §3 申报对照：A = 内容面重注入 + 回归测试，
  B = ToastBarView + 回归测试，各自 Project.swift + BUNDLE-MAP 同批，`--stat` 文件集
  与首验 M2-8-3-ACCEPTANCE §三申报一致。
- `isAdjustmentTransferable` 单谓词（`AdjustmentTransfer.swift:35-38`）=
  terminal trio 排除 + `owner(of:) == .grade`；`AdjustmentTransferTerminalTrio.opNames`
 （:42-46）= ColorIn/ColorOut/Gamma 三模块 `opName` 常量，零字符串字面量。
- `HistoryHash` 折叠面（`HistoryHash.swift:37-81`）：签名 = instances/decodeParamsHash
  + stack 便利形，版本结构无入口 = 结构性隔离；行为负测见抽查点①。
- BUNDLE-MAP 登记 vs 实况（`grep -c "func test"`）：SidecarV7Tests 8/8、
  VersionSwapTests 11/11、VersionsPanelTests 5/5、HistoryRowJumpTests 7/7、
  AdjustmentTransferTests 8/8、CleanTerminateSentinelTests 3/3、
  SheetEnvironmentInjectionTests 1/1、ToastFaceTests 3/3——**八行逐值一致**，
  首验两批勘误（9→8、10→11、7→8）终值稳定。时代树 `a26b005` 计数同值（VersionSwap 11、
  AdjustmentTransfer 8 亲核）。

## 三、与首验分歧点

无实质分歧。仅两项记录口径注记（不入计数）：

1. SHA 口径：任务书 `e9c03af`/`4e7fc58` vs 现树实 SHA `66f0cb7`/`9d9ed87`
   （§二③ minor，内容一致，历史重写漂移）。
2. 现树 `schemaVersionCurrent = 9` vs M2-8 时代值 7（后相加法扩展，v7 双键拼写冻结未动；
   回溯项已按时代树 `a26b005` 取证）。

## 四、会话卫生

- 只读验收：除本报告文件外零写入；未修改源码与既有文档；未 push。
- 定向测试仅 3 类（App 域），未跑 `--all`；测试宿主进程随脚本正常退出，无残留处置。
- 工作区 `git status` 除本报告新文件外无新增修改（验收前现状未动）。

OMP-VERDICT: PASS
