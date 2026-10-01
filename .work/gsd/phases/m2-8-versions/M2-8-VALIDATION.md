---
phase: M2-8
slug: versions
status: validated
nyquist_compliant: true
created: 2026-10-02
validated: 2026-10-02
---

# Phase M2-8 — Validation（版本与历史 mini-git：SC#1-5 三列证据 + Per-Plan Map + FINDING 闭环 + 授权记录）

> 体例对齐 16-VALIDATION（frontmatter / Checklist）。**翻账只认证据**：SC 表逐条
> 「SC 原文 + 证据指针（测试名 + 数字 + commit SHA + ACCEPTANCE 节）+ 判定」；
> 无证据 ✅ = 违规。SC 数字对账基线 = **修复后最新全套 `TOTAL|2577/16/0|896s EXIT=0`**
> （`e9c03af`/`4e7fc58` 两 FINDING 修复 + 4 回归测试后，`M2-8-3-ACCEPTANCE.md` §四）。
> **两 FINDING 裁决项消解**：验收批「先修后签」已兑现（复现 → 修复 → 回归测试 →
> 真机复验四环证据链在案），本签核 = 带挂账五项 + observation 清单照常放行。

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | XCTest（unit / golden / 真链装配 / 直启宿主 / 真机 AX+cliclick 走查） |
| **Quick run** | `Scripts/test-direct.sh`（L019b 直启；`--bundle`/`--all`） |
| **Full suite（phase 终轮）** | `caffeinate -dis Scripts/test-direct.sh --all` = **2577 tests / 16 skip / 0 fail**（896s，2026-10-02 验收批独立复跑，EXIT=0；MEMFAIL 零，峰值 Export 6641MB < 8192 门） |
| **基线演变** | M2-7 末 2525 → M2-8-1 +25（**2550**：SidecarV7Tests 8 + VersionSwapTests 11 + LIB +6）→ M2-8-2 +23（**2573**：VersionsPanel 5 + HistoryRowJump 7 + AdjustmentTransfer 8 + CleanTerminateSentinel 3）→ M2-8-3 +0（收口零源码 diff 持平）→ 验收批 +4（**2577**：SheetEnvironmentInjectionTests 1 + ToastFaceTests 3）；skip 恒 16 |
| **在案 flake** | M2-8-2 T3 SidecarV5Tests 写腿时序型 ×1（单类+全量复跑均绿，02-06 起形态未动）；验收轮两环境臂 ANE fail（受害用例零字节触碰 + 冷态全绿 + 执行方轮全绿——observation③ 挂账观察）；phase 终轮单轮即绿零复发 |
| **GUI 证据** | `.work/gui-acceptance/m2-8/`（走查 11 件 + 验收批复验 7 件：m2-8-09..15） |

---

## SC#1-5 对照表（ROADMAP §M2-8 行契约 = REQUIREMENTS M2VER-01..05，三列证据）

| SC | 判据（SC 原文） | 证据指针（测试名 + 数字 + commit SHA + ACCEPTANCE 节） | 判定 |
|---|---|---|---|
| **SC#1** | **EditCommit 不可变 commit 图（双亲=分支/合并）**（M2VER-01） | **v1 收窄态（晨审追认①，OQ-2-A）**：独立线性事务链替代 hash DAG；双载体交付——①sidecar v7 additive 双可选键 `versions:[SidecarVersionRecord]?` + `activeVersionID`（`schemaVersionCurrent` 6→7；nil 双键与 v6 形逐字节零漂移、`"items"` 全文档计数==1 不双写、篡改 `versions[].name` → `driftDetected == false` hash 零折叠负测）`2afeb3a`；②`.lalb` `version_ref` v2→v3 reduced DDL（`edit_commit/pipeline_root` 列名维持预留，翻回 DAG 世界线可 additive 激活）`69a30ec`。测试锚：SidecarV7Tests 8 法（三字节面）+ LibrarySchemaTests（v2→v3 真 open 迁移 + `pre-migrate.2-3.bak` + 链式两代 1→3/2→3 快照共存 E2 钉死 + fresh v3）+ VersionSwapTests 11 法。实证：2550/16/0（2525+25 精确）；三域独立复跑 App 448/0/0 + Library 436/4/0 + Layers 298/3/0；HistoryStack.swift/HistoryHash.swift 零 diff 机检（`M2-8-1-ACCEPTANCE.md` §二 AC1/2/6/7 + §三①②④） | ✅（收窄态注记；晨审翻回 = 预案世界线重规划，已交付 `.lra` 真身/swap/面板不回滚） |
| **SC#2** | **VersionRef 命名版本——从导入原始态新建 + branch from current commit + fork from root + rename/remove；版本切换即时、自动保存**（M2VER-02） | 命令面 `788e1a7`：VersionCoordinator 三命令 createFromScratch/branchFromCurrent/switchTo + rename/remove + materialize-on-first-create + dangling typed degrade；**fork-from-root 并入「从原始态新建」（晨审追认②，OQ-3-A——无 DAG 同型，两按钮同行为即 UI 欺骗）**；面板面 `c5e1ea7`：VersionsPanelView（列表/活跃徽标/updated_at/新建/Branch/inline rename/Remove 确认对话框/单击切换/空态引导；`editor.versions.placeholder` marker 退役零残留 grep 亲核）+ KD-1 名规则归 UI（三命令 name 参数化）。测试锚：VersionSwapTests 11 法（materialize 双槽/branch 快照时点保 jump 点/switch 往返 items+position 精确相等/remove active 切首/remove 唯一回隐式保链/E4 跨图污染「Version 1」起算）+ VersionsPanelTests 5 法。实证：真机走查单击切换 Inspector 曝光 +0.55→−0.10 EV 即时跳变（m2-8-02/02b）+ 切换跨重启持久 updated_at bump 复验（m2-8-01）；500 链装入 avg 0.562ms/max 1.073ms（`M2-8-3-DECISIONS.md` §2.1）；自动保存 = 版本动作 `scheduleSidecarWrite` 走既有 2s debounce（`M2-8-2-ACCEPTANCE.md` §二 AC1/§三⑤） | ✅（fork-from-root 并入注记；库网格版本徽标/批量版本 UI = 挂账#3 后置消费面） |
| **SC#3** | **ImageEditState 材质化缓存**（active_version/materialized_head/transaction_chain；仅加速恢复非用户概念）（M2VER-03） | **Delivered (in-memory)（OQ-5-A）**：active 链常驻内存 + `rebuildLayerStack` param 重放 = 切换即时语义的需求侧兑现；`image_edit_state` 表维持预留**不落库**；投影通道 = `replaceVersionRefs` 整表 reconcile 幂等 + FK CASCADE + 注入式 sink 装配于 `loadCurrentImage()`（非 body，`69a30ec`）。测试锚：VersionSwapTests switch 往返精确相等 + E4 切图重水合 3 槽；LibraryStoreTests 3 新法（round-trip 行集相等/reconcile 删除/幂等 + FK CASCADE + typed unknown-image）+ VersionSwapTests 法 11 真 `.lalb` 行集镜像。实证：切换即时性观察数字 = 500 链 avg 0.562ms（debug 口径，与单编辑 commit 0.021ms 同数量级——不超带不立项）；完整落库面随需求重开另立案（`M2-8-1-ACCEPTANCE.md` §二 AC7/8/9 + `M2-8-3-DECISIONS.md` §2.1） | ✅（in-memory 注记如实落 REQUIREMENTS） |
| **SC#4** | **永久 undo/redo + 历史事务行（操作名+参数 delta+时间）+ 崩溃恢复条 + 自动保存**（M2VER-04） | ①版本内线性事务流 = v7 `history` 键语义升级「active 版本链」（拼写冻结零改，v6 读者降级可读）`2afeb3a`；②历史行 UI `161a773`：行可点跳（原始索引换算视图层）+ 类型图标（闭集 `HistoryRowKind` enum 穷举 switch）+ position 高亮纯派生；③undo 四条验收固化；④崩溃恢复条 `81f361b`：CleanTerminateSentinel（`app.cleanTerminate` 双向哨兵 + 一次性 toast）+ **附带修复 02-06 起 `applicationWillTerminate` 形参类型错写致回调从未触发的潜伏缺陷（LESSONS L052）**；⑤FINDING-B 修复 `4e7fc58`：`ToastBarView` 零 chrome 面挂 `WorkspaceHostView` 底部 safeAreaInset（D-26 toast 通道默认面渲染点补齐，legacyBody 零触碰）。测试锚：HistoryRowJumpTests 7 法（跳回保尾/再编辑丢尾/双入口同源/500 链 .lra 重载逐字节 + 全程 undo 到 −1）+ CleanTerminateSentinelTests 3 法 + ToastFaceTests 3 法（零 chrome 契约 + 真 WorkspaceHostView 挂载 AX 树 wiring）。实证：kill 走查五格程序化（defaults 读回法，`M2-8-2-SUMMARY.md`）+ 修复后真机复验哨兵 toast 默认面底条清晰渲染 + 4s auto-clear 消退（m2-8-12/13，`M2-8-3-ACCEPTANCE.md` §五 B）；自动保存 = SidecarStore 2s debounce 既有面，万条 .lra save≈55ms/load≈46ms（`M2-8-3-DECISIONS.md` §2.2） | ✅（**「参数 delta」半边按 D-M2-8-CONTEXT-8-A 维持 Deferred**——per-op 摘要设施挂账#1，M2-5 18 目录稳定后立项，不阻翻账；M2VER-04 追记已如实注记） |
| **SC#5** | **Copy Adjustments 三层面板（Version→Node→Item 勾选 → Paste 新 Version；排除 RAW decode/lens/crop）**（M2VER-05） | 交付 `56360ee`：AdjustmentTransfer 模型（isAdjustmentTransferable 单谓词——owner==.grade + **terminal trio 显式排除集**；develop 15 + drtPost 4 全表穷举断言）+ pasteChain（OVERWRITE-paste epoch item + DRT 第二 item + 蒙版 contentRevision 置 nil + 隐式目标 materialize）+ AdjustmentTransferView 三 pane（来源段 = 当前图/外部 .lra v7 多版本二级选择·v6 单链·损坏源 typed 错误）+ `edit.copyAdjustments` 菜单。**FINDING-A 修复 `e9c03af`**：`AdjustmentTransferSheetContent` sheet 内容面显式重注入 `VersionCoordinator`/`EditorState` 两 Observable（app-root sheet 闭包在 `.environment(...)` 写入之外——3/3 确定性崩溃 `EXC_BREAKPOINT` 根因）。测试锚：AdjustmentTransferTests 8 法（排除面枚举完整/epoch+DRT 形状/蒙版 revision nil/真 .lra 粘贴 + 版本物化 + 激活写盘）+ **SheetEnvironmentInjectionTests 1 法以真 `.sheet` 呈现挂载生产 face（负腿实测：掏空注入 = 测试宿主同一 fatal 签名硬失败——检测力实证）**。实证：修复前 3/3 崩溃复现（`.ips` 存档 m2-8-15）→ 修复后真机复验对话框 4 次开启全渲染零崩 + 三 pane/来源段/排除/枚举/空层禁用守卫活体正确（m2-8-09/10/11，`M2-8-3-ACCEPTANCE.md` §二/三/五 A）；库内图像选择器 Deferred（`M2-8-2-DECISIONS.md` §1.3 晨审追认点，外部 .lra 入口功能完整） | ✅（修复闭环后签核；屏上含 grade 项全传输 = 层激活 AX 驱动深度，传输语义单测覆盖——observation①） |

---

## FINDING 闭环记录（本 phase 特有裁决项 → 已消解）

| FINDING | 级别 | 发现（M2-8-3 走查） | 修复（验收批） | 复验证据 |
|---|---|---|---|---|
| **A**：Copy Adjustments 对话框开即崩 | error | 2/2 复现 `EXC_BREAKPOINT`（sheet 内容环境快照缺 `VersionCoordinator`——app-root sheet 闭包在 `.environment` 写入外；DECISIONS §3.2） | `e9c03af` `AdjustmentTransferSheetContent` 内容面重注入 + `SheetEnvironmentInjectionTests` 真 `.sheet` 挂载回归（负腿同 fatal 签名实证） | 真机 4 开全渲染零崩（m2-8-09/10/11；验收批独立复现 1/1 累计 3/3） |
| **B**：哨兵 toast 及全部 D-26 toast 默认面零渲染点 | error | 9 帧连拍帧帧无 toast（StatusBar 只挂 legacyBody；键机制真——DECISIONS §3.3） | `4e7fc58` `ToastBarView` 零 chrome 面挂 `WorkspaceHostView` 底部 safeAreaInset + `ToastFaceTests` 3 法 | 真机哨兵 toast 默认面清晰渲染 + 4s auto-clear（m2-8-12/13） |

两 defect 修复 commit 边界干净（各触缺陷面 + 各带回归测试 + Project.swift/BUNDLE-MAP
随批登记）；登记纪律兑现（CONVENTIONS 新增「app-root 级 sheet 闭包禁止裸
`@Environment` 跨界」约定）。

---

## Per-Plan Map（M2-8-1..3 + 验收批）

| Plan | 交付 | 终态 commits | 验收 |
|---|---|---|---|
| M2-8-1 版本模型核 | sidecar v7 additive 双可选键 + VersionCoordinator 三命令/swap/物化 + `.lalb` version_ref v2→v3 reduced DDL + pre-migrate 快照轮换 | `2afeb3a`/`788e1a7`/`69a30ec`/`0578da1`（收口） | PASS / 0E + 1m 已修 + 2o（`M2-8-1-ACCEPTANCE.md`） |
| M2-8-2 面板与交互 | VersionsPanelView + 历史行可点跳/类型图标/position 高亮 + Copy Adjustments 三 pane + 崩溃哨兵 + willTerminate 形参真缺陷修复 L052 | `c5e1ea7`/`161a773`/`56360ee`/`81f361b`/`8f2394c`（收口） | PASS / 0E + 1m 已修 + 3o（`M2-8-2-ACCEPTANCE.md`） |
| M2-8-3 收口 | zh-audit 42 键对账 PASS + 观察项三查全 PASS 不立项 + 翻账五账 + phase 小结 + 两 FINDING 登记 | `7b7f475`/`71c8baf`/`5102ea4` | PASS / 0E + 0m + 2o（`M2-8-3-ACCEPTANCE.md`） |
| 验收批（两 FINDING 修复） | `e9c03af` + `4e7fc58` + 回归 4 法 + 复验证据 7 件 | 同左 | 同上报告 §三/四/五 |

---

## nyquist 覆盖判断

- **判定：`nyquist_compliant: true`**。SC#1-5 每条均有 ≥1 机器锚（专项测试族：
  SidecarV7 8 / VersionSwap 11 / VersionsPanel 5 / HistoryRowJump 7 /
  AdjustmentTransfer 8 / CleanTerminateSentinel 3 / SheetEnvironmentInjection 1 /
  ToastFace 3 / LibrarySchema·LibraryStore 迁移与投影族）+ ≥1 数字/走查实证
  （全套 2577/16/0 独立复跑 + 真机走查 m2-8-01..15 证据件）。
- 覆盖密度与前序已签核 phase（16-VALIDATION 同款）对齐：数据面字节级 pin
  （三字节面/items 计数/hash 负测）、语义面真链装配（VersionSwapTests 真链零后门）、
  UI 面真机走查（AX + cliclick + 截图在案）、缺陷面正反双向（负腿检测力实证）。
- 采样率对变更面不成欠账：M2-8 三 plan 全部 AC 逐条机检（12+12+8 条）+ 两验收
  subagent 零共享上下文独立复跑；无「无证据 ✅」项。

---

## 授权记录（C 档第 3 停夜间签核）

- **授权先例**：D-07-3-T5-1——用户显式继续指令 = 终签核授权（C 档第 3 停夜间
  授权先例，晨审可推翻）。
- **本次授权原话（2026-10-01/02 夜间，用户两条显式指令）**：
  1. 「今晚任务不要停下，自动化持续推进」
  2. 「开跑，不要停」
- 依上述授权，本 VALIDATION 由夜间全自动批落盘签核（`[gsd] paused=false /
  auto=true` 在案）；用户晨审可推翻本签核（推翻 = M2-9 暂停回退，已交付面不受影响）。

---

## 挂账清单（Deferred 五项 + observation，交接 M2-9 与后续批）

**Deferred 五项（非缺陷，功能后置；REQUIREMENTS 注记同步）**：
1. **per-op 参数 delta 摘要设施**（displayValue/changed-keys 摘要器）——OQ-8-A /
   D-M2-8-CONTEXT-8-A；M2VER-04 半边收窄的正名；M2-5 18 目录稳定后立项。
2. **commit 图可视化**（`DateCommitGraph` 式时间轴）——待真 DAG（OQ-2-B 世界线 /
   晨审追认①翻回时随行）。
3. **库内版本选择器**（Copy Adjustments 跨图源选择器 + 库网格版本徽标消费面）——
   `M2-8-2-DECISIONS.md` §1.3。
4. **版本快照缩略图**（版本列表行内缩略预览）——库面消费版本数据时并议。
5. **版本导出/导入**（单版本存预设/文件）——预设系统与版本系统交汇，后置。

**observation 挂账（不阻塞，随批处置）**：
- **O-1（M2-8-3 验收 observation①）**：屏上「含 grade 项的真传输」未走通——层激活
  态 AX 驱动深度问题；传输语义已由 AdjustmentTransferTests 8 法覆盖；后续 GUI 批
  如需可视化粘贴证据建议探针参数化（`-la_transfer_probe` 形态）。
- **O-2（M2-8-3 验收 observation②）**：`test-direct.sh` 记账解析不匹配「Executed
  1 test」单数形态（恰好 1 条过滤跑记 0；无假绿风险，TOTAL 低记 1）——修复归
  test-direct.sh 另案（一行 regex），不顺手修。
- **O-3（前波 observation②③ 延续）**：App bundle 尾段 ANE 推理面环境脆弱 +
  SidecarV5Tests temp 工作拷贝失败路径恒漏（预存卫生缺陷）——M2-8 期终轮单轮即绿
  零复发，继续挂账观察，不扩范围。
- **译文人工润色**：M2-8 新增 42 键译文质量归人工审（机检只判键在册与 locale 纪律）。

---

## 翻账与移交

- REQUIREMENTS **M2VER-01..05 全 Delivered 终态复核通过**（01/03 带收窄态与
  in-memory 注记；04 参数 delta 半边 Deferred 如实注记 + FINDING-B 已修追记；
  05 FINDING-A 已修追记）——本批零改动（前波翻账已终态）。
- STATE.md：M2-8 翻 complete（2577/16/0）+ M2-9 标 next（本批）。
- ROADMAP §M2-8 行状态同步 ✅（本批）。
- GOAL-STATE 续接点增量更新：M2-8 closed → **M2-9（导出选项 Alcedo 化）discuss/
  research 起草为下一步**；挂账五项 + observation 清单随交接写明（本文件 + GOAL-STATE）。
- M2-9 依赖面交接（`M2-8-3-SUMMARY.md` phase 小结节）：导出管线消费面已备——
  `EditorState.instances/layerStack` 投影 + `effectiveDrtRecord` 载体（版本切换后
  随 active 链走）+ 既有 6 格式 Export 管线零改动；`.lalb` 版本投影列（导出
  manifest 消费）如需 = 注入 sink 形态复用；版本面无新增依赖。
- 未 push；GPL 参考零接触；`.xmp` 零读写删。

## 签核

- SC#1-5 全项 ✅（三列证据齐；SC 数字对账 = 2577/16/0 修复后基线）。
- `status: validated` + `nyquist_compliant: true`。
- 两 FINDING 裁决项消解（先修后签兑现）；挂账五项 + observation 四条随 M2-9 交接。
- **C 档第 3 停 = 夜间授权先例（D-07-3-T5-1）落签，晨审可推翻。**
