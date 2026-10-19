---
phase: f0prime-prod
plan: "F0P-03"
title: "plan P3 — 死码退役 + 文档回填（T1 SwiftUI App/Scene/Commands 全族退役〔App struct + 三窗 scene + .commands 块 + @FocusedBinding/@State/openWindow 面摘除 + focused-value 键族退役 + statics/helpers 迁壳 + AgentControl manifest face ⑤ 重指 + ProjectReadOnlyFaceTests static 转移——同一 commit 原子〕/ T2 退役 grep 机检族 / T3 FB 文档回填呈用户〔OQ-F0P-10〕/ T4 README Known Issues 勘正〔D-6 条目撤除 + toolbar 差异登记〕/ T5 走查抽样复证 + App bundle 定向轮 + SUMMARY/DECISIONS）"
wave: 3
depends_on: ["F0P-01", "F0P-02"]
autonomous: true
requirements: ["依赖 P2 闭环（全套三轮同值绿 + 16 面走查全绿）——退役前必须全套绿（RESEARCH §7 依赖序）；C 档停确认后起跑", "调研正本 = phases/f0prime-prod/RESEARCH.md（§2.3 末段 manifest 退役后重指〔勘误②裁定 P3 落地〕/ §5.2 直接依赖点表〔2 文件微改〕/ §7 P3 行 / §8 OQ-F0P-10）", "OQ 裁决正本 = phases/f0prime-prod/CONTEXT.md（D-F0P-1..10；转写勘误② manifest 重指随退役同 commit 原子落地）", "测试基线权威数 3969/37/0（勘误 RESEARCH 3905）；本 plan 分账 +0（退役零新增测试；重指 = 修改非新增）", "C 档停位 = 本 plan 执行+验收闭环后停汇报（全批收口呈用户——FB 稿终章 + README 勘正同批过目）"]
success_criteria: "SC 全可机检——T1：App struct 全族退役（LightamerApp.swift 的 internal struct LightamerApp + scene builder + .commands 块 + @NSApplicationDelegateAdaptor + @State 43 字段 + @FocusedBinding 消费 + toggleSidebar/toggleInspector + openWindow 使用点 + entry `_ = { LightamerApp.main() }` 死行摘除）+ focused-value 键族退役（LightamerColumnVisibilityKey/ExportPanelRequestKey/metadataFieldFocused/lightamerWorkspaceModel 键 + 定义 + view 侧 .focusedSceneValue publish 全摘——ContentView/WorkspaceHostView/InspectorView 三处）+ statics/helpers 迁壳（batchPasteBlocked/readOnlyPasteToast → 壳类型或同名转发 + DEBUG 探针 static armed 旗标壳侧持有确认）+ AgentControlCoordinatorTests face ⑤ 行重指壳文件（同 commit）+ ProjectReadOnlyFaceTests batchPasteBlocked 调用点重指（同 commit）；T2：grep 机检 = `.commands(` / `WindowGroup` / `Settings {` / `@FocusedBinding` / `focusedSceneValue` 在 App target 零命中 + `.runModal(` 复跑零命中 + `String.LocalizationValue(\"prefix_\\(` 禁形零命中 + `F0PrimeShell` 零命中复跑；T3：APPLE-FB-D6-DRAFT.md 终章回填（双重排除法 + churn 功能性发现 + 壳交接 0.0% 终数据）呈用户（手动提交惯例）；T4：README Known Issues D-6 条目撤除 + window toolbar 形态差异登记行补入；T5：App bundle 定向轮全绿（退役后回归底线）+ 走查抽样复证（启动/编辑器进出/三窗/菜单分发/退出链五点）+ SUMMARY/DECISIONS 落盘"
estimated_tests: "+0（退役 = 删除面 + 重指修改；零新增测试；如退役暴露需补回归 = 越带申报理由）"
test_bundles: [APP]
baseline: "P2 闭环终态（3969 + ΔN，带内 3984..3994——P2 SUMMARY 终账为本 plan 起算基线）"
expected_all: "P2 闭环终态维持（退役零 ΔN；全套不强制——改动面 = LightamerApp.swift 死码域 + 2 测试文件重指，App bundle 定向轮 + 走查抽样为验收面；若 orchestrator 批准加跑 --all = 批准制纪律照旧）"
red_lines:
  - "共用红线正本 = CONTEXT §三 plan 红线 front-matter 15 条（FIX2③ / 封存面 / 无 QA 回切 / 翻转 commit 独立可 revert〔P1 产物——本 plan 退役不得破坏 revert 面：P1 翻转 commit 的 revert 语义退役后变为「回 P2 终态」由 git 历史承载，属正常演化〕/ xcstrings 零 diff / LocalizationValue 禁形 / disable-not-unmount〔face ⑤ manifest 行重指后 Swift 侧 .disabled 其余 9 面零触〕/ 基线 3969/37/0 / AppDelegate.swift 字节零改 / DEBUG fork 序零触 / L057 / UserDefaults / --all 批准制 / C 档门控 / LightamerShell* 改名维持）。"
  - "退役 = 删除死码，非重写：壳侧（LightamerShell/NSMenuBridge/ShellGraph/ShellWindowControllers）本 plan 零 diff（P1 产物冻结）；退役面 = LightamerApp.swift 死码域 + view 侧 focused-value 面三处摘除 + 2 测试文件重指——文件清单外零触碰。"
  - "重指原子性（勘误②）：AgentControlCoordinatorTests face ⑤ 行 + ProjectReadOnlyFaceTests static 调用点与退役同 commit——任何中间态（退役已落、重指未落）= 测试红 = 不可提交态。"
  - "willTerminate 链零断：AppDelegate.swift 字节零改 + ShellDelegate 组合转发链零触（退役后 open Apple Events / terminate flush 全链走 ShellDelegate→AppDelegate 转发，走查面 14/退出链复证）。"
  - "FB 稿回填 = 文档面：APPLE-FB-D6-DRAFT.md 终章补写呈用户，禁代用户提交（OQ-F0P-10 手动提交惯例）。"
  - "README 勘正 = 与退役同批（文档与产物同批更新纪律）：D-6 条目撤除理由（壳交接消除 churn 机器——非「已修复的框架缺陷」措辞，upstream 缺陷定性不变）+ toolbar 差异行补入。"
files_modified:
  - App/Sources/Lightamer/UI/LightamerApp.swift              # T1：App struct 全族退役 + entry 死行摘除（保留 entry enum + fork 序 + ShellMain.run() 尾 + AppDelegate + WindowCapture）
  - App/Sources/Lightamer/UI/ContentView.swift               # T1：.focusedSceneValue 双 publish 摘除（:249-250）
  - App/Sources/Lightamer/UI/Shell/WorkspaceHostView.swift   # T1：.focusedSceneValue publish 摘除（:195；B20 note 保留）
  - App/Sources/Lightamer/UI/InspectorView.swift             # T1：.focusedSceneValue publish 摘除（:428-432；B19 note 保留）
  - Tests/LightamerTests/AgentControlCoordinatorTests.swift  # T1：face ⑤ 行重指壳文件（同 commit 原子）
  - Tests/LightamerTests/ProjectReadOnlyFaceTests.swift      # T1：batchPasteBlocked 调用点重指壳类型（同 commit 原子）
  - .work/gsd/research/APPLE-FB-D6-DRAFT.md                  # T3：终章回填（双重排除法 + churn 功能性发现 + 0.0% 终数据）
  - README.md                                                # T4：Known Issues D-6 条目撤除 + toolbar 差异行补入
  - .work/gsd/phases/f0prime-prod/F0P-03-SUMMARY.md          # T5：执行摘要（退役对账 + ΔN 终账 + 全批收口）
  - .work/gsd/phases/f0prime-prod/F0P-03-DECISIONS.md        # T5：裁定记录（static 转移终形 + 重指终形 + 各偏差）
---

# Plan F0P-03 — plan P3：死码退役 + FB 回填 + README 勘正

> **裁决正本** = `CONTEXT.md`；规格正本 = `RESEARCH.md` §2.3 末段 +
> §5.2 + §7 P3 行 + §8 OQ-F0P-10。**前置门**：P2 全套三轮同值绿 + 16 面
> 走查全绿（退役前必须全套绿——RESEARCH §7 依赖序）。
>
> **裁定权归属钉**：本 plan 无用户裁决分支。执行中如触「必须扩面」（壳
> 侧文件改形 / Commands 面部分保留 / AppDelegate 触碰 / fork 序调整）=
> 停手上报，不得自裁扩界。
>
> **执行序**：T1（退役 + 重指同 commit 原子）→ T2（grep 机检族）→ T3
> （FB 回填）→ T4（README 勘正）→ T5（复证 + 收口）。每任务独立 commit
> （Conventional Commits，全英文，只 add 相关文件，不 push）。
>
> **C 档停**：T5 闭环后**停汇报**（全批收口呈用户——FB 终章 + README 勘
> 正同批过目）。
>
> **基线**：P2 闭环终态（`TOTAL|3969+ΔN/37/0|`，带内）。本 plan ΔN +0。

## ΔN 预算表（P3 分账 +0）

| 任务 | 测试增量 | 构成 | 落点 |
|---|---|---|---|
| T1 退役+重指 | **+0** | 删除面 + 重指修改（static 转移 = 调用点改指，法数不变；face ⑤ 行重指 = 1 行改） | 2 测试文件修改非新增 |
| T2-T5 | **+0** | 机检/docs/复证 | — |
| **合计** | **+0** | P2 终态维持（如退役暴露需补回归 = 越带申报） | App bundle 定向轮为底线 |

## read_first（全局，每任务开工前过一遍）

- `.work/gsd/phases/f0prime-prod/CONTEXT.md`（勘误②原子性裁定 + 红线）+
  `F0P-01-DECISIONS.md`（壳侧终名/接线终形——退役面边界对账源）+
  `F0P-02-SUMMARY.md`（P2 终账 = 本 plan 基线）
- `.work/gsd/phases/f0prime-prod/RESEARCH.md` §5.2（直接依赖点 2 文件正
  本）+ §2.3 末段（face ⑤ 重指原文）+ §7 P3 行
- `App/Sources/Lightamer/UI/LightamerApp.swift` 全文结构对账（:15-35 键
  定义 / :168-201 AppDelegate 保留段 / :252-2244 App struct 退役域 /
  :128-158 entry 保留段 / :2639 static / :2692-2702 toggle 面）——退役
  = 精确删除域圈定，开工前逐段圈定落 DECISIONS
- `.work/gsd/research/APPLE-FB-D6-DRAFT.md`（现状 + 修订节结构）+
  `README.md:118-130`（Known Issues D-6 条目现形）
- `.work/config.toml [gsd]` paused/auto 开关（开工前亲核）

---

## T1 — SwiftUI App/Scene/Commands 全族退役 + 测试面重指（同一 commit 原子）

> 退役 = 删除死码（P1 翻转后 App struct 已不可达）；重指与退役同 commit
> ——任何中间态测试红 = 不可提交态（勘误②）。

- **action**：
  1. **退役域圈定**（先圈后删，落 DECISIONS）：`LightamerApp.swift` 内
     `internal struct LightamerApp: App` 全体（@NSApplicationDelegateAdaptor
     + @State 43 字段 + @FocusedBinding 消费 + @Environment(\.openWindow)
     + scene builder〔Window×3 + Settings〕+ `.commands` 全块 +
     toggleSidebar/toggleInspector + batchPasteBlocked/readOnlyPasteToast
     statics）+ entry 内 `_ = { LightamerApp.main() }` 死行。**保留段**：
     entry enum + DEBUG fork 序 + `LightamerShellMain.run()` 尾 +
     `AppDelegate` 类（:168-263 域）+ `WindowCapture`。
  2. **statics 迁壳**：`batchPasteBlocked`/`readOnlyPasteToast` → 壳类型
     （LightamerShell 域或同名转发形——RESEARCH §5.2「static 转移壳类型
     (或保留同名转发)」二选一，终形落 DECISIONS）；DEBUG 探针 static
     armed 旗标壳侧持有确认（P1 已随探针函数迁壳——面核零遗漏）。
  3. **focused-value 键族退役**：键定义（LightamerColumnVisibilityKey/
     ExportPanelRequestKey + metadataFieldFocused/lightamerWorkspaceModel
     键定义所在——全文 grep 圈定）+ view 侧 `.focusedSceneValue` publish
     三处摘除（ContentView :249-250 / WorkspaceHostView :195 /
     InspectorView :428-432——**B19/B20 note 修饰符保留**，那是活链）。
  4. **测试面重指（同 commit）**：`AgentControlCoordinatorTests` face ⑤
     行（:229-231）重指壳文件 token（bridge enabler 读 holdsControl 的
     活源——终形落 DECISIONS）；`ProjectReadOnlyFaceTests` batchPaste
     Blocked 调用点（:499-506）改指壳类型。
  5. 构建绿机检。
- **验收标准（机检）**：
  - 构建绿；`git show --stat` 恰五产线/测试文件（LightamerApp + 三 view
    + 2 测试文件——重指与退役恰一 commit）。
  - grep（App target）：`.commands(` / `WindowGroup` / `Settings {` /
    `@FocusedBinding` / `focusedSceneValue` **全零命中**；`struct
    LightamerApp` 零命中；`LightamerShellMain.run()` 调用恰一处；
    `batchPasteBlocked` 恰一处定义（壳侧）。
  - **保留段零 diff**：entry fork 序 / AppDelegate 类 / WindowCapture /
    壳侧四文件全零 diff（`git diff` 逐 hunk 面核）。
  - **AgentControlCoordinatorTests + ProjectReadOnlyFaceTests 全绿**（
    `--bundle App` 定向）；note 修饰符（B19/B20）零 diff。
- **commit**: `refactor(f0p3): retire swiftui app scene family and repoint test surface`
- **回滚与偏差申报要求**：回滚 = revert 单 commit（死码复活——P2 终态
  恢复，无行为差）；偏差（static 转移终形/重指 token 形/键族圈定界）=
  DECISIONS 申报；**禁触壳侧四文件**（P1 冻结）；**禁触 AppDelegate**；
  **禁部分保留 Commands 面**（全族退役——发现「还有活消费者」= 停手上
  报，那是审计缺口不是退役边界问题）。

## T2 — 退役 grep 机检族（复跑门）

- **action**：全域机检复跑：①`.commands(`/`WindowGroup`/`Settings {`/
  `@FocusedBinding`/`focusedSceneValue` App target 零命中（T1 判据复跑
  独立核）②`.runModal(` App/Sources 零命中（L057 门复跑——P1 翻转后菜
  单 action 面再核一遍）③`String.LocalizationValue("prefix_\(` 禁形零
  命中 ④`F0PrimeShell` 零命中复跑 ⑤xcstrings diff = 零（全批预期）⑥
  UserDefaults 应用级键零新增（`defaults` 键登记面 + diff 面核）。
- **验收标准（机检）**：六项逐条命令输出落 DECISIONS（零命中/零 diff 证
  据行）。
- **commit**: `chore(f0p3): run retirement grep gate sweep`
- **回滚与偏差申报要求**：任一命中 = 停手归因（禁静默吸收）；机检输出
  不全 = 收口不完整。

## T3 — FB 文档回填呈用户（OQ-F0P-10）

- **action**：`APPLE-FB-D6-DRAFT.md` 终章回填——①双重排除法证据链（F0
  菜单桥 FAIL + F0' 面排除 → 载体 = 生命周期机器）②churn 功能性发现
  （F0PRIME §4.3——96% 机器曾承担未追踪读的功能性负载，菜单缩放重绘即
  实例）③壳交接终数据（A 96.0 → B 0.0，−96.0pp，三轮交错 + 四哨兵）④
  P2 D-6 门定版数据引用；**呈用户**（手动提交惯例——禁代提交，禁加提
  交渠道面）。
- **验收标准（机检）**：终章四件在文档（内容面核）；数据与
  F0PRIME/P2 DECISIONS 一致（数值逐项对账）。
- **commit**: `docs(f0p3): finalize apple feedback draft with shell-handover evidence`
- **回滚与偏差申报要求**：数据不一致 = 逐项勘正；禁改 FB 稿历史章节（只
  补终章——历史行不改写纪律）。

## T4 — README Known Issues 勘正（D-6 条目撤除 + toolbar 差异登记）

- **action**：README Known Issues——①D-6 条目（:120-130「Editor may spin
  at high CPU…」）撤除（churn 机器由壳交接消除；撤除注记 = upstream 缺
  陷定性不变、非「框架已修复」措辞——本 app 侧不再复现）②window toolbar
  形态差异行补入（窗级 unified 附着形态缺席、in-face 渲染仍活、NSToolbar
  重造后置候选——OQ-F0P-2 用户可见面如实申报）。
- **验收标准（机检）**：README Known Issues 段两处变更（撤除 + 补入）；
  无其它 README 段被触碰（`git diff` 面核）。
- **commit**: `docs(f0p3): retire d6 known-issue entry and register toolbar deviation in readme`
- **回滚与偏差申报要求**：措辞偏差（撤除注记定性）= DECISIONS 申报；文
  档与产物同批纪律——本任务与 T1-T3 同 plan 批内完成，禁「先退役后补文
  档」跨批拖欠。

## T5 — 走查抽样复证 + App bundle 定向轮 + 收口

- **action**：
  1. **App bundle 定向轮**：`caffeinate -dis Scripts/test-direct.sh
     --bundle App` 全绿（P2 终态法数维持——退役零 ΔN 对账）。
  2. **走查抽样复证**（退役无回归五点）：启动 + welcome；编辑器进出
     （⌘E/⌘W）；三窗（⌘, / preset-manager / mcp-launcher）；菜单分发
     抽五动作（AXPress → handleMenu 全链）；退出链（willTerminate flush +
     clean sentinel）。记录 MANIFEST。
  3. **SUMMARY + DECISIONS 落盘**（退役域圈定终账 + static 转移终形 +
     重指终形 + 机检六项输出 + 全批 ΔN 终账汇总）。
  4. 汇报 + **C 档停**（全批收口呈用户——FB 终章 + README 勘正同批过
     目；全批终值带 3984..3994 对账收口）。
- **验收标准（机检）**：定向轮全绿 + 五点走查记录在 MANIFEST + SUMMARY
  ΔN 全批对账表闭合（3969 +15..+25 → 3984..3994 实际值终账）。
- **commit**: `test(f0p3): run retirement verification and close out f0-prime batch`
- **回滚与偏差申报要求**：定向轮任何 fail = 先归因（退役窗内 = T1 revert
  二分；窗外 = 停手上报）；走查五点任一 fail = 停手禁放行。

---

## 风险与回退

- **退役域圈定误差**：App struct 面大（:252-2244），删除域圈定错漏 =
  编译红（安全面）或死码残留（grep 机检兜底）——「先圈后删 + 双机检」
  双保险；发现 Commands 面仍有活消费者 = 审计缺口信号，停手上报。
- **重指原子性破坏**：退役与重指分 commit = 中间态测试红——红线明令同
  commit；revert 单 commit 回 P2 终态。
- **focused-value 残余消费者**：四键退役前提 = NSMenuBridge note-box 是
  唯一菜单侧读源（P1 兑现）——若退役后走查发现菜单行为差（如多屏场景
  focused 语义），= 停手上报（D-F0P-6 恒主窗单源的边界重议，orchestrator
  裁决面）。
- **README/FB 措辞**：D-6 撤除注记的定性（「本 app 侧不再复现」≠「框架
  已修复」）——upstream 缺陷定性不变是 FB 稿一致性前提。

## Checker 关注点（独立反向核输入）

1. **Goal-backward**：RESEARCH §7 P3 行 ↔ T1-T5 映射 + §5.2 两文件 ↔
   T1 重指逐项 + §2.3 face ⑤ ↔ T1 同 commit。
2. **退役边界核**：保留段（entry/fork 序/AppDelegate/WindowCapture/壳侧
   四文件）零 diff 逐 hunk 面核；删除域 grep 五项零命中。
3. **原子性核**：退役 + 重指恰一 commit（`git show --stat` 五文件）；
   中间态不存在（时间序面核）。
4. **红线核**：壳侧零 diff + AppDelegate 零 diff + xcstrings/UserDefaults
   零 diff + .runModal/禁形复跑零命中 + B19/B20 note 保留。
5. **文档纪律核**：README 两处变更恰面 + FB 终章数据对账 + 历史章节零触。
6. **SC 可机检性**：每条 SC 有命令级判据；全批 ΔN 终账闭合（P2 终态维
   持 + 0）。
