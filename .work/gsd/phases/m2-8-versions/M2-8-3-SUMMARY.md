# M2-8-3 SUMMARY — 收口（zh 对账 + 观察项三查 + 翻账 + phase 小结）

> Plan 正本 = 同目录 `M2-8-3-PLAN.md`（checker 修正版）。执行 = ZCode
> subagent worker（2026-10-01/02 夜间，`[gsd] paused=false / auto=true`）。
> 三任务三提交，**未 push**。裁决签注 = 同目录 `M2-8-3-DECISIONS.md`。
> **零功能 plan 红线兑现：源码 diff = 0 文件**（zh 键已在前波落盘，本轮
> 纯核验——`git diff` 全程无 .swift/.metal 触碰，T3 机检在案）。

## 交付总览

| 任务 | 提交 | 内容 |
|---|---|---|
| T1 | `7b7f475` | zh-audit 对账（`--check` PASS 开局即绿，xcstrings **零补行**——M2-8-2「zh 键随手落」载体已把 42 新键落齐；对账表 + 43→42 勘误对账落 DECISIONS §1） |
| T2 | `71c8baf` | 观察项三查（程序化 scratch 探针即弃不入仓：500 链切换 / 万条 .lra IO / pristine 三客户面差分 / 105 版本滚动——四项全 PASS 不立项）+ GUI 真机走查（证据 `.work/gui-acceptance/m2-8/` 11 件）+ **两个 error 级 FINDING 登记**（§走查发现） |
| T3 | 本提交 | 翻账五账同批（REQUIREMENTS M2VER-03 翻勾 + 04/05 走查追记；GOAL-STATE 续接点 + C 档第 3 停；TODO M2-8 行；AGENTS.md M2-8 增量节；DECISIONS §4 checker M5 勘误）+ 全套终跑 + 边界核对 |

## zh-audit 对账（AC#1）

```
uv run python3 Scripts/zh-audit.py --check
→ zh-audit --check PASS (1362 source keys, 1588 catalog keys, zh complete, locale codes = {en, zh})
EXIT=0
```

- 对账数字 = **42 键**（T1 15 + T2 4 + T3 22 + T4 1；**非 43**——承 M2-8-2
  验收 observation①：`history_paste_adjustments` 系 09-04 既有键复用）；
  键级亲核：42 键 en/zh 双语非空 + 源码引用面全命中 + 孤儿键
  `editor_versions_placeholder` 不在场（净 +41 = 1588 − 1547 精确）。
- 译文质量归人工审（机检只判键在册与 locale 纪律），**译文待人工润色**
  不视为缺口。
- 源码 diff：无（.xcstrings 本波零改动——AC#1「diff 仅 .xcstrings 一文件」
  以更严形态达成：零源码 diff）。

## 观察项三查（AC#2/#3——数字行，方法与明细 = DECISIONS §2）

| # | 观察项 | 实测（debug 构建口径） | 判定 |
|---|---|---|---|
| 1 | 500+ 链版本切换耗时（真链 ×20） | 装入 500 链 **avg 0.562ms / max 1.073ms**（0.35–1.07）；轻链向 avg 0.020ms；基线单编辑 commit 0.021ms | **PASS**——与既有编辑操作同数量级，不可感，不立项 |
| 2 | 万条历史 .lra 保存/加载（SidecarStore 直测面） | save **53.9–57.7ms** / load **45.8–46.4ms** / 文件 6,792,256 bytes；footprint 135→139MB（进程级口径，ru_maxrss 为 bundle 级——L045 注记） | **PASS**——2s debounce 语境不可感，不立项 |
| 3 | Versions 面板百版本列表滚动（真机） | 105 版本 fixture：翻页直达底部即时、逐位置渲染无空白行、滚动条跟随（顶部/中部/底部三截屏在案） | **PASS**（目测口径如实登记；headless 无法量化帧率） |
| 4 | pristine 收窄三客户面（P1 风险节销账） | 真 SessionIndexStore 全流程差分：`.lra 存在∧链空∧versions 非空` 图 = present 1 / has_edits **0** / tier **A**；编辑对照图 = 1 / 1 / tier B | **PASS**——判定面全按 items/position，版本结构零翻转 |

- 探针形态：临时追加 probe 类进 App bundle 测试文件 → build-for-testing →
  单类跑 → 数字取自日志 → `git checkout` 还原——**探针零入仓**（checker
  M5a 落法）；探针自误（断言笔误）1 次如实登记 DECISIONS §2.1，计时不受影响。

## GUI 真机走查（AC 走查项 + 两 FAIL 级发现）

### 通过项（证据 = `.work/gui-acceptance/m2-8/`，AX + cliclick 真机驱动）

- **Versions 面板全操作**：列表/活跃徽标/updated_at/新建+Branch 在场
  （m2-8-01）；单击行切换即时生效——Inspector 曝光随目标版本链值跳变
  （+0.55→−0.10 EV，m2-8-02/02b）；切换跨重启持久（版本 3 行 updated_at
  bump 复验）。
- **历史行交互**：倒序行 + position 高亮纯派生（+0.55 行高亮 ↔ Inspector
  +0.55 EV，m2-8-04/04b）；行点击 jump 生效——高亮移至「曝光 +0.35」行 +
  Inspector 重投影 +0.35 EV + redo 尾两行保留（m2-8-05/05b——「跳回保尾」
  可视面印证）。
- **列表面板体挤出可视区**（GUI-12/13 先例坑）：未复现——面板在轨内自滚动；
  附带观察：行宽下双位数版本名截断「版本…」（truncation，非溢出）。

### ⚠️ FINDING-A（error 级，确定性崩溃）：Copy Adjustments 对话框开即崩

- 复现 2/2：编辑器开图 → Edit「复制调整…」→ `EXC_BREAKPOINT`；
  stderr 断言原文（`m2-8-08-transfer-crash-stderr.txt`）=
  `SwiftUICore/Environment+Objects.swift:34: Fatal error: No Observable
  object of type VersionCoordinator found.`——sheet 内容环境快照缺
  `VersionCoordinator` Observable 注入（`AdjustmentTransferView` 用
  `@Environment(Type.self)` 跨呈现边界；单测全绿因挂非 sheet 层级）。
- **影响**：M2VER-05 UI 面用户可达入口 100% 崩溃；**M2-8-2 验收翻账
  Delivered 的对话框面带此缺陷**。修复建议（sheet 内重注入或 init 参数
  注入——仓内 LibraryWelcomeView 惯例）在 DECISIONS §3.2；**本 plan 红线
  内不修，另案**；phase VALIDATION 裁决项。

### ⚠️ FINDING-B（error 级，视觉面结构性缺失）：哨兵 toast 及全部 D-26
toast 在默认 shell 无渲染点

- 复现：非清态 → 启动 → 开项目 → 进编辑器 → 0.7s 连拍 16 帧全扫底条——
  帧帧无 toast、底条恒无 Ready/Decoding 尾位文本。
- 根因（代码级）：toast 渲染点 `StatusBar`（读 `editorState.toast`）**只挂
  `legacyBody`**（env=1 回切面）；默认 `WorkspaceHostView` 项目工作区面
  Shell 目录 grep 零 StatusBar/toast 面——哨兵/导出失败/删除锁/drift 等
  全部 D-26 toast 对默认面用户**结构性不可见**。哨兵键机制本身为真
  （M2-8-2 kill 走查五格机器验证）。
- **影响**：M2VER-04「崩溃恢复条最小面」的屏上面缺席。**本 plan 红线内
  不修，另案**；phase VALIDATION 裁决项。

## 回归实测（AC#7）

- 定向：本 plan 零新测试（E2 免登记）；探针即弃。
- **全套终跑（报备）**：`caffeinate -dis xcodebuild build-for-testing`（探针
  还原后重建）+ `Scripts/test-direct.sh --all` =
  **`TOTAL|2573/16/0|901s EXIT=0`**。七 bundle 逐行：
  `IOP 467/1/0|6418MB · IOPParity 362/3/0|5991MB · Layers 298/3/0|1043MB ·
  Library 436/4/0|306MB · Sessions 279/4/0|1644MB · Export 260/1/0|6401MB ·
  App 471/0/0|1333MB`（sampling=time；MEMFAIL 零触发，峰值 IOP 6418MB <
  8G 门）。
- 对账：**M2-8-2 终态 2573/16/0 精确持平，零新增**（本 plan 零源码 diff 的
  直接推论）；App bundle 471 中**无**探针残迹（重建后探针类已还原）。

## 边界核对（AC#8，纪律 4/7）

- `git diff`（工作区）滞留：`.work/gui-acceptance/09-3-tiers-*.jpg` 两文件
  改动 mtime 早于本波执行窗（前波走查遗留，非本批产物，未纳入本批提交）。
- 本波三提交逐 commit `--name-only` 全集 = DECISIONS/SUMMARY/
  `.work/gui-acceptance/m2-8/` 证据件 + REQUIREMENTS/GOAL-STATE/TODO/
  AGENTS.md 账本——**零第三类源码文件**（front-matter 的
  `Resources/Localizable.xcstrings` 以「零改动」满足）。
- 走查宿主侧效已还原：quit clean（`app.cleanTerminate`=0）+
  `library.import.rawExtensions` defaults 删除（回归冻结默认白名单）。
- 未 push；GPL 参考零接触；Core 不 import App 面未触。

## M2-8 phase 小结（3 plans 执行面全闭环）

| plan | 交付 | 终态 commit | 验收 |
|---|---|---|---|
| M2-8-1 | 版本模型核（sidecar v7 additive 双可选键 + VersionCoordinator 三命令/swap/物化 + `.lalb` version_ref v2→v3 reduced DDL + pre-migrate 快照轮换） | `69a30ec`（收口） | PASS 0E+1m 已修 + 2o（`M2-8-1-ACCEPTANCE.md`，`301ebea`） |
| M2-8-2 | 面板与交互（VersionsPanelView + 历史行可点跳/类型图标/position 高亮 + Copy Adjustments 三 pane + 崩溃哨兵 + willTerminate 形参真缺陷修复 L052） | `8f2394c`（收口） | PASS 0E+1m 已修 + 3o（`M2-8-2-ACCEPTANCE.md`，`b10c7cb`） |
| M2-8-3 | 收口（zh 对账 42 键 + 观察项三查 + 翻账五账 + phase 小结 + **两 FINDING 登记**） | 本提交 | 待验收 subagent（下一步） |

- **测试演进**：2525（M2-7 终态）→ 2550（M2-8-1，+25）→ **2573/16skip/0fail**
  （M2-8-2，+23）→ **本 plan 0 新增持平**（+0；skip 恒 16）。
- **M2VER 全族终态（REQUIREMENTS 本批翻账）**：
  - **M2VER-01** ✅ Delivered（v1 收窄态：sidecar v7 + version_ref 双载体；
    **晨审追认项①**——OQ-2-A commit hash 图不落库，独立线性链替代 DAG，
    `edit_commit/pipeline_root` 列名维持预留可 additive 翻回）。
  - **M2VER-02** ✅ Delivered（命令面 + 面板全字面；**晨审追认项②**——
    OQ-3-A fork-from-root 并入「从原始态新建」（无 DAG 同型，两按钮同行为
    即 UI 欺骗，M2-8-1 裁决））。
  - **M2VER-03** ✅ Delivered (in-memory)（OQ-5-A：active 链常驻内存 +
    param 重放；`image_edit_state` 表维持预留不落库；切换即时性观察数字
    = 本 SUMMARY 观察项①——0.562ms avg，同数量级不超带）。
  - **M2VER-04** ✅ Delivered（历史行 UI + 永久 undo 固化 + 崩溃恢复条
    最小面；「参数 delta」半边维持 D-M2-8-CONTEXT-8-A Deferred——
    **带走查追记：toast 屏上面在默认 shell 缺席（FINDING-B）**）。
  - **M2VER-05** ✅ Delivered（三 pane 对话框 + 排除面单谓词；库内图像
    选择器 Deferred——**带走查追记：对话框打开确定性崩溃（FINDING-A）**）。
  - 追认项①②任一被晨审推翻 = 回 Alcedo DDL 照抄线重规划（plan 风险节
    预案；已交付 `.lra` 真身/swap/面板不回滚，增量叠加世界线）。
- **执行期真缺陷档案**：M2-8 修 1 枚——`applicationWillTerminate` 形参
  类型错写致回调自 02-06 起从未触发（M2-8-2 T4，L052；flush-on-quit 面
  复活）。
- **挂账清单（Deferred，交接面全量转录）**：
  1. **per-op 参数 delta 摘要设施**（displayValue/changed-keys 摘要器）——
     OQ-8-A 挂账，M2-5 18 目录稳定后立项（M2VER-04 半边收窄的正名）。
  2. **commit 图可视化**（`DateCommitGraph` 式时间轴）——待真 DAG
     （OQ-2-B 世界线 / 追认项①翻回时随行）。
  3. **库内版本选择器**（Copy Adjustments 跨图源选择器 + 库网格版本徽标
     消费面）——M2-8-2 DECISIONS §1.3 晨审追认点。
  4. **版本快照缩略图**（版本列表行内缩略预览）——库面消费版本数据时并议。
  5. **版本导出/导入**（单版本存预设/文件）——预设系统与版本系统交汇，后置。
- **⚠️ VALIDATION 裁决项（本 phase 特有）**：**FINDING-A**（Copy Adjustments
  开即崩，DECISIONS §3.2）+ **FINDING-B**（D-26 toast 默认面零渲染点，
  DECISIONS §3.3）——两 error 级走查发现按零源码 diff 红线未修，修复
  plan 立项与否 = phase 签核前置裁决（先修后签 or 带挂账签核）。
- **M2-9 依赖面交接（ROADMAP M2-9 下游核）**：导出管线消费面已备——
  `EditorState.instances/layerStack` 投影 + `effectiveDrtRecord` 载体
  （版本切换后随 active 链走，M2-8-1 T2 测钉）+ 既有 6 格式 Export 管线
  （Sessions 域 ExportPipeTests 面）零改动；M2-9 的尺寸四模式/元数据策略/
  文件名模板/输出 ICC 联动/队列 UI 按其 plan 展开，版本面无新增依赖；
  `.lalb` 版本投影列（导出 manifest 消费）如需 = 注入 sink 形态复用
  （AGENTS.md M2-8 节）。
- **ANE 尾段脆弱面 + SidecarV5 temp 恒漏**（M2-8-2 验收 observation②③，
  预存卫生缺陷）：本波 `--all` **单轮即绿零复发**（2573/16/0，首轮无宿主
  异常、无 ANE fail、无 flake——环境窗良好）——按前波处置继续挂账观察，
  不扩本 plan 范围。
- **下一步**：M2-8-3 验收 subagent（对照 plan AC 8 条 + DECISIONS 复核；
  两 FINDING = 登记事实核验非修复验收）→ orchestrator **C 档门控第 3 停**：
  M2-8 phase VALIDATION 签核（verify-work 输入 = 三 SUMMARY + 三 DECISIONS +
  本 phase 小结 + 两 FINDING 裁决）→ 用户确认后 M2-9（导出选项 Alcedo 化）。
