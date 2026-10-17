# M7-5-01 SUMMARY — GUI agent turn-taking 执行摘要（2026-10-17 夜）

> 执行链：`599601d7`(T1)→`89d8bbff`(T2)→`4755941d`(T3)→`dea46168`(T4)→
> `47737c1d`(T5)→`f91d9aee`(T6)→T7 docs。夜间全自动授权在案（先例
> D-07-3-T5-1）；`--all` 批准制由本波派发 prompt 批准。裁定正本 =
> 同目录 `M7-5-01-DECISIONS.md`；OQ 落定正本 = `M7-5-CONTEXT.md`。

## 逐任务战果

| 任务 | commit | 面 | gate |
|---|---|---|---|
| T1 | `599601d7` | ControlToolset 第五域（McpControlState/McpControlContext/三工具免 admit）+ registry 第三道门（Entry.requiresControl 缺省 false + setControlAdmit + dispatch 序 writer→control→handler，writeCallCount 零波及）+ 错误码 16→19 + McpTimeouts.controlAcquire 10s 新档 + 9 处 requiresControl 字面量（13 工具覆盖）+ makeRegistry 第五参 + 四宿主缝 + EmbeddedState 第六缝 + xcstrings 3 描述键 | 构建绿 + grep 全中（每错误名恰 3 处 / registry requiresControl 恰 3 处 / ControlToolset 零显式） |
| T2 | `89d8bbff` | AgentControlCoordinator（@MainActor @Observable 单写点：held/stoppedByUser/holderName/taskId/activity/stoppedHolderName + holdsControl 派生 + admit 三拒 + acquire 等待/恢复路由 + release 幂等 + stop 单入口）+ PipeCoordinator.liveEditActive 三窗 OR（additive 只读计算属性）+ get_state control.agent 键 + GUI 禁编辑 11 实落点（合并形容器层）+ 装配（probe 跨附着 + coordinator-backed control context） | 构建绿 + LibraryProjectController 零 diff + scopes 零引用 + 条件卸载零命中 |
| T3 | `4755941d` | registry 演进（isPinned 协议要求 + extension 缺省 false 既有三腿零改 + dismiss(id:) 薄封装）+ AgentTaskHandle（isPinned=true）+ bar/dialog agent 行（Stop 单入口 handle.cancel 直呼，registry.cancel 移除臂禁入——F8）+ 终态 dismiss 路由 + 活动列表 + AX 族 + xcstrings 4 键 | 构建绿 + finish/cancel/cancelAll 体零触 + 既有行 diff 零触 |
| T4 | `dea46168` | makeHeadlessControlContext 恒真面（恰 1 定义恰 3 调用点）+ 七点接线（runHeadless 两臂 + arbitrated 共享 const 喂三臂 + :1120 box 读出〔T1 就位〕+ :1608 GUI 臂〔T2 就位〕）+ makeHeadlessSearchState additive agentControl 参 + read-only 宿主照常注册（OQ-10）+ scopes 三纪律复核 | 构建绿 + 形 B 七点 grep ①..⑦ 全过 |
| T5 | `47737c1d` | S-1 四处注释清零（五钉 23 断言零触）+ S-3 预热实测（8.4 ms vs 50.2s 冷窗）+ S-2 让渡/S-4 第四波/S-5 无动作申报起草 | grep "21-tool face"/"count rides 21" 零命中 + evidence 分仓在库 |
| T6 | `f91d9aee` | union 29→32 全点位显式改（冻结表 +3 + 计数 ×4 + all32 改名 + 五集合并 + disjoint +4 + descriptionKeys +3 + fixture + SC7 宿主 + 头注 + 测试名）+ 穷举 16→19 + get_state agent 断言新法 + 两新测试文件（15+10 法）+ Project.swift 恰两行 + BUNDLE-MAP 恰两行 + tuist generate 恒末位 + xcstrings 三错误键补齐（恰 10 新键） | `--bundle App` **904/4/0**（基线 879+25=904，预期带 +18..25 顶格）；peakRSS 2832MB |
| T7 | 本批 | 定向轮 + 全套 `--all` + 红线族 11 项机检 + zh-audit 双 PASS + 走查 MANIFEST + SUMMARY/DECISIONS + 四台账翻账 | 见下 |

## 全套终值（T7 亲证）

`TOTAL|3950/35/0|` exit 0，**零 MEMFAIL，七 bundle 全部 8G 门内**（IOP
7813MB 贴线达标）。ΔN = **+25**（两新文件 15+10 法；union 显式改/穷举
16→19/get_state 断言新法 = 零新法口径），**3925+25 = 3950 对账精确**——
预期带 3943..3950 落顶格。逐 bundle：App **904/4/0**〔+25；peakRSS
2832MB〕/ IOP 687/5〔7813MB〕/ IOPParity 460/3〔7626MB〕/ Layers 494/5
〔808MB〕/ Library 736/4〔624MB〕/ Sessions 284/9〔1630MB〕/ Export
385/5〔6125MB〕——其余六 bundle 与 M7-4 终态逐值一致（skip 35 构成零漂移）。

## 四验收形态判定指针（ROADMAP §M7-5）

1. **双端 fixture**（agent 持锁 GUI typed 拒 + 用户夺回 agent 失权）：T6
   McpControlToolsetTests.testAdmitRefusalsThreeFaces /
   testRequiresControlCandidateSetIsExactlyThirteen + AgentControlCoordinatorTests
   状态机全序 + 禁编辑点位 manifest。判定 = **PASS**（机检在库）。
2. **GUI 活动卡走查**：T3 卡面 + T7 `.work/gui-acceptance/m7-5/MANIFEST.md`
   配方（A/B/C/R 四组 22 行）。判定 = **配方就绪，实机走查归验收批**
   （TURN-02 验收形态②的 Manual-Only 面）。
3. **Stop→resume 活动连续 fixture**：T6 testFullSequenceAcquireAdmitStopResumeReleaseDismiss
   （同 id + activity 延续 + interrupted 终形）+ testDifferentHolderAfterStopMintsNewTask。
   判定 = **PASS**。
4. **无头恒持有负测**：T6 testHeadlessControlContextConstantFace /
   testHeadlessAdmitNilWriteToolsAnswerStraightIntoHandler /
   testReadOnlyHostArmControlFaceRegisteredAndWriteGatePrecedes。判定 = **PASS**。

## 红线族（11 项全 PASS，命令级亲证）

零新 SPM（Project.swift 仅测试登记两行）/ `.metal` 全域零 diff / 封存面
17 件零 diff / 既有 29 工具 descriptor-handler 零 diff（快照门双证：per-domain
层零触 + union verbatim 表零触）/ 五钉 23 零触（:243/:697/:277/:200/:223）/
writeCallCount 计数行 zero-diff / LibraryProjectController 零 diff（diff 0 行）/
PipeCoordinator 恰 additive liveEditActive（其余函数体零触）/ 保留面文件
零触（ScopePanelView/ScopeThrottle/SettingsView 不在 diff 清单）/ xcstrings
恰 10 尾块插入（1946→1956）+ UserDefaults 零新键 / runModal 零命中 +
LocalizationValue 插值禁形零命中（唯一命中为既有注释行）/ Project.swift
恰两行 + BUNDLE-MAP 恰两行 + tuist generate 恒末位。

## zh-audit

`--check` PASS（source keys 1698→1708 恰 +10；1956 catalog keys；38 interp
keys variant-PRESENT）+ `--self-test` PASS（V17 golden 八例）。

## 偏差清单（正本 = DECISIONS）

①acquire 超时单一执法点（tool 面不叠 10s 包装——typed controlBusy 优先）；
②registry 注入缝（configureLiveEditProbe 可换缝 + attachTaskRegistry weak
附着——F12 的装配现实形）；③xcstrings 三错误键随 T6 补齐（T1 漏插，对账
缺口当轮发现）；④Stop 闭形终态化（interrupted 不被后续边界改写）；
⑤S-1 union 注释 token 以措辞改写清零；⑥evidence 走 policy B 分仓
（plan files_modified 的 evidence 路径以 lightamer-evidence `9b36b42`
承载）；⑦两 GUI fixture 测试 +1 环境行（never-held，面零漂移）。
无结构性偏差（plan 与代码事实零冲突面）。

## M7-4 挂账收口

S-1 全收口（四处 T5 + union 两处 T6）/ S-3 完成（8.4ms）/ S-2 让渡
下一 Export 波 / S-4 第四波维持注记 / S-5 无动作。FIX2③ 第四波维持。
