---
phase: audit-repair
plan: "AR-02"
title: "plan B — M2 39 面板 stored-params codemod：params(of:) 每 tick 重解码提升 stored（每面板 init 一次解码存 let params、删 computed property、binding 闭包捕获 stored 值；PanelEditing helper 签名不变；ModuleInstance Core 面零改）+ env 门解码探针（LIGHTAMER_PERF_PROBE=1 + XCTSkipUnless，非门留档，可选 +1）+ 面板拖动走查 + D-6 探针复测"
wave: 1
depends_on: []
autonomous: true
requirements: ["审计修复批 charter：B 路 M2 major 修复（正本 = .work/audits/xcode27-skills-2026-10/LANEB-FINDINGS.md M2 行）", "调研正本 = phases/audit-repair/RESEARCH.md §5（勘测 + 修法 + 性能门评估）+ §9 m2 行 + §10 切分", "OQ 裁决正本 = phases/audit-repair/AUDIT-REPAIR-CONTEXT.md（D-M7-AR-5 stored-params 形态 + D-M7-AR-6 验收 + D-M7-AR-9 编排）", "全套基线 3963/35/0；本 plan 带 +0..1 → 终值带 3963..3964（叠加 plan A 时按累计口径对账）", "与 plan A 并行合法性 = 文件零交集（本 plan = UI/Inspector/ 面板域；plan A = UI/Shell/ 宿主面板族 + ContentView + LibraryGridView；唯一共享依赖 LightamerSlider 只读）"]
success_criteria: "SC 全可机检——T1 codemod：codemod 前 grep 清单落 DECISIONS（`private var params:` 直读形 = 39 文件 + `PanelEditing.params(of:` helper 式调用点逐处清点）→ codemod 后①grep `private var params:` 在 App/Sources/Lightamer/UI/Inspector/ 零命中②每面板 init/成员初始化内恰一次 params 解码（`params(of:` 或 helper 调用——codemod 后命中数 = 直读形处数 × 1（39 文件 44 处——review F-4）+ PanelEditing helper 本体 + 既有非 computed 合法调用点，grep 域限定 App/Sources/Lightamer/UI/Inspector/ 域内（review F-2——全仓域 62 命中会扰算术），逐文件对账清单落 DECISIONS）③binding get/set 闭包内零 params(of:)/PanelEditing.params 解码调用（捕获 stored 值）④`ModuleInstance.swift` 零 diff（Core 面零改）⑤`IOPPanelProvider.swift` PanelEditing.params helper 签名零 diff⑥单 commit；T2 探针（可选）：PanelParamsDecodeProbeTests 新文件两法（默认 skip 腿 = XCTSkipUnless 环境门断言；PERF 腿 = LIGHTAMER_PERF_PROBE=1 下代表性 Params 解码 µs 基线 stderr PERF 行留档）+ Project.swift 恰 +1 行（LightamerTestsApp 数组）+ BUNDLE-MAP 恰 +1 行（APP 域）+ tuist generate 恒为该批最后一个动作（L041）；T3 验收：构建绿 + `--bundle App` 定向轮全绿 + 1-2 面板拖动走查（ChannelMixerRGB 代表）+ D-6 探针复测一次（面板批后；A/B 并行可合并到两 plan 都落盘后一跑）+ SUMMARY/DECISIONS 落盘"
estimated_tests: "+0..1（T2 探针 PERF 腿 +1——若裁定零探针 = ΔN 0 且 Project.swift 零 diff；T1 codemod 本身 ΔN=0 纯机械）"
test_bundles: [APP]
baseline: "3963/35/0（M7-6 收口终态；HEAD 363117ee = audit-repair research docs-only 产线零漂移）"
expected_all: "3963 + ΔN（对账式；本 plan 带 +0..1；全批三 plan 终值带 3964..3972——review F-1，plan A 带 +1..7；skip 35 口径维持；--all 批准制 + A/B 并行窗口 /tmp/la-audit-repair-all.lock 串行）"
red_lines:
  - "D-6 交互禁区（正本 = RESEARCH §1，与 plan A 同款共用清单）：①menus/focus 形态零触碰。②threshold 承载面不得结构性增删（双 safeAreaInset/.inspector 分栏/编辑器三段内容段数）。③每次树形改动 = FIX2 T1 探针复测硬门：本 plan 面板批后复测一次（重开项目进编辑器静置 CPU<10% ps/sample 机检 + 空载无项目面同口径记录；A/B 并行可合并）。④AX 自动化轻用。⑤o6 LutPanelView .id(libraryRevision) 本批不动（挂 D-6 专项卷）。"
  - "Core 面零改：LightamerCore/Sources/Pipe/History/ModuleInstance.swift 零 diff（params(of:) 每 call JSONDecoder 语义是本修的病源事实，但本修 = 纯 App 层消费形态提升 stored，Core 不动）；LightamerIOP/ 全域零 diff。"
  - "PanelEditing helper 面零改：IOPPanelProvider.swift 的 PanelEditing.params(of:as:) 签名与函数体零 diff（值传参已解耦——codemod 后 helper 仍可被非面板面合法调用）；panel(for:) -> AnyView 注册缝零 diff（o3/D12 33-panel 契约）。"
  - "FIX2③ = LibraryProjectController.swift 文件零 diff。"
  - "封存面零 diff（FIX2 红线族，与 plan A 同款共用清单）：*.metal 全域 / LightamerSidecar / DrtRecord / TerminalTailPolicy / DrtTailAssembly / PixelPipe / Lut3dKernels.metal / DrtEotf / ExportQueueContract / 六格式导出矩阵 / NodeGraphCommand / HistoryStack / HistoryHash / PipelineDocument（Core）/ V50Order / GradeCatalog（NodeOwnershipCatalog）/ Registry / ModuleInstance。"
  - "xcstrings 零 diff（本 plan 零新键——与 plan A 的 m9 豁免不同，本 plan 不触本地化面）；UserDefaults 零新键（KD-4）。"
  - "禁形机检：String.LocalizationValue(\"prefix_\\(x)\" 插值禁形零命中（本 plan 零新键面——纯预防性随批）；.runModal( App/Sources 零命中（L057）。"
  - "面板行为面零改：codemod = 纯语义等价改造（instance let 值捕获论据，RESEARCH §5）——禁顺手改任何面板布局/绑定逻辑/默认值；发现行为差 = 停手上报。"
  - "C 路并入条款（RESEARCH §11）：周一合并 MANIFEST 落盘后逐条分诊并入——C 路若推翻本 plan 面数清单（39）以 C 路为准修正；执行前亲读合并 MANIFEST 一轮；基线按合并 MANIFEST 落盘时点全套终态重算 ΔN 对账带（review F-9——RESEARCH §11②）。"
  - "构建 caffeinate -dis 包裹；单测 = Scripts/test-direct.sh --bundle App；全套 --all 批准制 + A/B 并行窗口 /tmp/la-audit-repair-all.lock 串行（macOS 无 flock(1) 用 mkdir/fcntl/进程树探测等价——M7-6 验收先例口径）；测试宿主清理先核 parentage（ps -o ppid）。"
files_modified:
  - App/Sources/Lightamer/UI/Inspector/*.swift                     # T1：39 面板 codemod（清单执行时以 grep `private var params: ` 定死落 DECISIONS；代表锚 = ChannelMixerRGBPanelView.swift :23 let instance / :26-28 computed / :322 discreteBinding 闭包捕获面）——每面板 init 一次解码存 let params + 删 computed + 闭包捕获 stored；ChannelMixerRGBPanelView 为首批样板
  - Tests/LightamerTests/PanelParamsDecodeProbeTests.swift         # T2（可选）：新文件两法（skip 腿 + PERF 腿）；若裁定零探针 = 本行撤销
  - Project.swift                                                  # T2（可选）：恰 +1 行（探针测试登记 LightamerTestsApp 数组）；tuist generate 恒末位（L041）
  - .work/gsd/phases/m2-4-0-test-bundles/M2-4-0-BUNDLE-MAP.txt     # T2（可选）：恰 +1 行（APP 域）
  - .work/gui-acceptance/audit-repair/MANIFEST.md                  # T3：走查配方（AR-02 节：1-2 面板拖动 + stored 提升后 readout 面零漂移观察行）
  - .work/gsd/phases/audit-repair/AR-02-SUMMARY.md                 # T3：执行摘要（39 文件清单终账 + ΔN 记账）
  - .work/gsd/phases/audit-repair/AR-02-DECISIONS.md               # T3：裁定记录（codemod 前后 grep 对账清单 + 探针裁定 + init 形态终账）
---

# Plan AR-02 — plan B：M2 39 面板 stored-params codemod（每 tick 重解码 → init 一次解码）

> **裁决正本** = `AUDIT-REPAIR-CONTEXT.md`（D-M7-AR-5 stored-params
> 形态落定值）；规格正本 = `RESEARCH.md` §5 + §9 m2 行。
>
> **零 stale 风险论据（本 plan 语义等价性的正本，执行与验收均以此为
> 准）**：`instance` 是面板 View 的 `let` 值捕获
> （ChannelMixerRGBPanelView.swift:23）——computed `params` 与 Binding
> get/set 闭包内读（discreteBinding :322 等）每次解码的是**同一份字
> 节**；记录变更恒经 `edit.update` → 父链重估 → 面板以新 instance
> 重建 → init 重解码。提升 stored = 纯语义等价，无 stale 风险。
>
> **面数勘误（CONTEXT §勘误①）**：RESEARCH「48 文件」实为 **48 命中
> / 41 文件 / 39 直读面板**（`private var params: X.Params {` 直读形
> = 39，codemod scope 正本）；helper 式调用点执行时逐处清点。
>
> **YiyinPanelView 同病残余登记（review F-2）**：`App/Sources/Lightamer/
> Yiyin/YiyinPanelView.swift:59-60/:65` 双 computed params（watermark/
> borders，同 helper 同 ModuleInstance 解码底座）= M2 同病残余，不在本
> plan codemod scope（39 清单 = UI/Inspector/ 域口径）——处置二选一
> （挂账注明 ∨ 以 +1 文件并入清单）执行时落 DECISIONS，禁静默漏网。
>
> **计量单位勘误（review F-4）**：「39 面板」实为 39 **文件** / 44 处
> `private var params` 直读形（GradeScalarPanels.swift 一文件 6 个面板
> struct 各 1 处）——命中数恒等式按处数闭合（44 + helper 1 + 其余 3 =
> 48）；SC 与验收对账一律写「处数」口径。
>
> **裁定权归属钉**：本 plan 无用户裁决分支（D-M7-AR-5 落定 stored
> 形；探针可选面 = plan 内裁量非用户裁决）。执行中如触「必须扩面」
> （Core params(of:) 改形 / helper 签名改 / AnyView 注册缝动 / 面板行
> 为面顺手改）= 停手上报，不得自裁扩界。
>
> **执行序**：T1 → T2 → T3。T1 单 commit（39 文件机械批）；T2 可选
> 探针独立 commit；T3 验收收口。每任务独立 commit（Conventional
> Commits，全英文，只 add 相关文件，不 push）。
>
> **与 plan A 并行**：文件零交集合法（唯一共享依赖 LightamerSlider
> 只读）；D-6 探针轮可合并到两 plan 都落盘后一跑（D-M7-AR-6）。
>
> **基线**：**3963/35/0**；本 plan ΔN 带 +0..1。

## ΔN 预算表（逐任务，合计带 +0..1；越带须申报理由）

| 任务 | 测试增量 | 构成 | 落点 |
|---|---|---|---|
| T1 codemod | **0** | 纯机械语义等价改造——回归靠既有 App bundle 面（39 面板行为面零改） | 既有面板测试面 + 定向轮 |
| T2 探针（可选） | **+0..1** | PanelParamsDecodeProbeTests PERF 腿 1（skip 腿 = 环境门断言不计 ΔN——默认 skip） | 新文件 APP 域 |
| T3 验收 | **0** | 轮次 + 走查 + 收口文档 | — |
| **合计** | **+0..1** | 3963 → 终值带 3963..3964（叠加 plan A 时累计口径） | Project.swift 探针例外 +1 行 |

## 已定裁决（生效值，硬约束，不得重开）

1. **stored-params 形态**（OQ-5）：每面板 custom init（或保留
   memberwise + init 内一次解码）存 `let params`，删 computed
   property；helper 签名不变；binding 闭包捕获 stored 值；Core 零改。
2. **被否备选**：body-top `let params = self.params`（helper 闭包再
   读需逐处过——48 命中面不推荐）；@State 缓存（per-tick paramsHash
   必 miss，弃）。
3. **性能门评估 = 不需要 PERF 硬门**（RESEARCH §5）：N→1 是机械可证
   构造（init 一次 vs body N 读），无用户可见预算面；env 门探针 =
   文档面非门（M2-5 PERF 惯例：LIGHTAMER_PERF_PROBE=1 +
   XCTSkipUnless 默认 skip）。
4. **验收**（OQ-6）：编译 + App bundle 定向轮 + 1-2 面板拖动走查 +
   D-6 探针复测一次（面板批后）。

## read_first（全局，每任务开工前过一遍）

- `.work/gsd/phases/audit-repair/AUDIT-REPAIR-CONTEXT.md`（D-M7-AR-5
  + 勘误① + 编排总纲）
- `.work/gsd/phases/audit-repair/RESEARCH.md` §5 全节（消费形态两式 +
  解码计数实测 24+ + 修法三备选 + 性能门评估）
- `ModuleInstance.swift` :146-152（params(of:) 每次 JSONDecoder——
  Core 面零 diff 红线锚）
- `ChannelMixerRGBPanelView.swift` :23（let instance）/ :26-28
 （computed）/ :322 起（discreteBinding 闭包捕获面）——codemod 样板
  正本
- `IOPPanelProvider.swift` :194-198（PanelEditing.params helper）+
  :47（panel AnyView 注册缝——零触锚）
- `.work/config.toml [gsd]` paused/auto 开关（开工前亲核）
- `.work/LESSONS.md` L041（tuist generate 恒末位——T2 触发时）+
  M2-5 架构增量节（perf 探针惯例：env 门 + XCTSkipUnless + stderr
  无缓冲 PERF 行）

---

## T1 — 39 面板 stored-params codemod（单 commit 机械批）

> **codemod 纪律**：每面板改造 = 三步（init 一次解码存 `let params`
> → 删 `private var params` computed → body 直读与闭包捕获 stored
> 值）；除三步外零触碰（布局/绑定逻辑/默认值/AX identifier 零改）。

**read_first**：RESEARCH §5 全节 + §9 m2 行；`ChannelMixerRGBPanelView.swift`
全文（样板正本——:23/:26-28/:322 三面）；`IOPPanelProvider.swift`
:194-198（helper 形态——②式消费代表）；39 文件 grep 清单（执行时
`rg -l "private var params: .*\.Params \{" App/Sources/Lightamer/UI/Inspector/`
定死，落 DECISIONS）。

- **action**：
  1. **清单定死**：codemod 前 grep 两式清单落 DECISIONS——①直读式
     `private var params: X.Params { (try? instance.params(of: X.self)) ?? .init() }`
     （39 文件）②helper 式 `PanelEditing.params(of: instance, as:)`
     调用点逐处清点；对账 RESEARCH/B 路 39 口径（勘误①——39 文件
     44 处直读形，review F-4 计量单位）。
  2. **样板先行**：ChannelMixerRGBPanelView 首改——init（或成员初始
     化处）`let params = (try? instance.params(of:
     ChannelMixerRGBModule.self)) ?? ChannelMixerRGBModule.Params()`
     存 stored；删 :26-28 computed；body 直读 `params.*` 与
     discreteBinding 闭包捕获 stored 值零改语义。构建绿 + 单独编译
     走查后批量推广。
  3. **批量 codemod**：其余 38 文件同款三步；两种消费式（直读/helper）
     统一收敛到 stored 形；**binding 闭包内零解码调用**（闭包捕获
     stored 值——Swift 值捕获语义下闭包读的是 init 时字节，与现行为
     逐位等价，论据见头注）。
  4. 构建绿机检（caffeinate -dis 包裹）。
  5. 单 commit（39 文件一批——机械同构，拆分无验收增量）。
- **验收标准（机检）**：
  - 构建绿；`git diff --stat` 恰 39±ε 文件（ε = helper 式清单出入，
    DECISIONS 申报——禁静默吸收）。
  - grep：`private var params:` 在 App/Sources/Lightamer/UI/Inspector/
    **零命中**；codemod 后 `params\(of:` 命中数（**UI/Inspector/ 域内
    ——review F-2 域限定**，禁按全仓跑）= 直读形处数 × 1（39 文件
    44 处——review F-4，init 各一次）+ PanelEditing helper 本体 1 +
    既有非 computed 合法调用点（对账清单落 DECISIONS——域内命中数应
    ≤ codemod 前 48）。
  - **ModuleInstance.swift / IOPPanelProvider.swift 零 diff**（Core
    面 + helper 面）；`panel(for:) -> AnyView` 注册缝零 diff。
  - **LibraryProjectController.swift 零 diff**；LightamerSlider.swift
    零 diff（共享依赖只读——并行纪律锚）。
  - 既有面板测试面全绿（`--bundle App` 过滤面板相关法）。
- **commit**: `perf(ar02): decode panel params once per instance (audit M2)`
- **回滚与偏差申报要求**：回滚 = revert 单 commit（回 computed 每
  tick 重解码形——行为无差，性能退化回归原病）；偏差（面数清单出入 /
  init 形态分化 / 个别面板结构特例需不同处理）= DECISIONS 逐文件申
  报，禁静默；**发现任何面板行为面需顺手改 = 停手上报**（本 plan 纯
  机械批——行为面改动越 scope）。

## T2 — env 门解码探针（可选，+1；M2-5 PERF 惯例形）

> **文档面非门**（RESEARCH §5 评估结论）：代表性 Params 解码 µs 基线
> 留档，供后续面板性能面考古对照；默认 skip 不占全套时长。

**read_first**：RESEARCH §5 性能门评估段；M2-5 架构增量（AGENTS.md
「性能探针惯例」节：LIGHTAMER_PERF_PROBE=1 + XCTSkipUnless + PERF 行
stderr 无缓冲）；`ModuleInstance.swift` :146-152（解码路径——探针测
量对象）。

- **action**：
  1. **PanelParamsDecodeProbeTests.swift** 新文件（APP 域）两法：
     ①skip 腿 = `XCTSkipUnless(ProcessInfo.processInfo.environment[
       "LIGHTAMER_PERF_PROBE"] == "1")`（默认 skip——环境门断言本身
     即测试法）；②PERF 腿 = 构造代表性 Params（ChannelMixerRGB.Params
     代表 + 39 面板 Params 族抽 2-3 个）经 `ModuleInstance` paramsData
     往返解码，PERF 行走 **stderr 无缓冲**（`FileHandle.standardError`
     直写）输出 µs 基线（decode µs / Params 名 / 迭代数）。
  2. **登记三行**：Project.swift LightamerTestsApp 数组恰 +1 行 +
     BUNDLE-MAP 恰 +1 行（APP 域）+ **`tuist generate` 恒为该批最后
     一个动作**（L041）。
  3. 构建绿机检。
- **验收标准（机检）**：
  - 构建绿；默认环境（无 env 门）下该法 skip（`--bundle App` 轮 skip
    计数 +1 构成申报）；`LIGHTAMER_PERF_PROBE=1` 下 PERF 行落档
    （stderr 捕获记录进 DECISIONS）。
  - Project.swift diff = 恰一行；BUNDLE-MAP diff = 恰一行；tuist
    generate 后 pbxproj 再生成为该 commit 内最后动作（L041——commit
    顺序面核）。
- **commit**: `test(ar02): add env-gated params decode probe`
- **回滚与偏差申报要求**：回滚 = revert 单 commit（Project.swift/
  BUNDLE-MAP 三行随 revert）；裁定零探针 = 本任务整体跳过（ΔN 0，
  DECISIONS 申报一行）；探针若需 GPU fence（L014）= 本探针纯 CPU 计
  时不需要——发现涉 GPU 面 = 停手上报（越文档面 scope）。

## T3 — 验收：定向轮 + 面板走查 + D-6 探针复测 + 收口文档

> 面板批改的是面板 init/body 形（树形面亦变）→ **D-6 探针复测一
> 次**（D-M7-AR-6；A/B 并行可合并到两 plan 都落盘后一跑）。

**read_first**：RESEARCH §7（验收三层）+ §10 plan B 行；`FIX2-01-PLAN.md`
T1 SC（探针判定式）；CONTEXT 编排总纲（探针合并窗口）。

- **action**：
  1. **定向轮**：`caffeinate -dis Scripts/test-direct.sh --bundle App`
     全绿（叠加 plan A ΔN 时按累计口径对账）。
  2. **面板走查**（配方落盘 MANIFEST，实机归验收批/用户）：
     ChannelMixerRGB 代表 + 任一 helper 式面板——滑杆拖动 60Hz 目测
     + readout 面零漂移 + binding 开关（normalize 族 discrete）行为
     零差。
  3. **D-6 探针复测**：重开 ≥6 图项目进编辑器静置 CPU<10% + 空载面
     同口径记录（独立跑或与 plan A 合并；采样命令形与 pid parentage
     判别沿 AR-01 T5 钉死形——review F-8，记录落本 plan DECISIONS
     探针记录节）。
  4. **全套 --all（可选，批准制）**：A/B 并行窗口持
     `/tmp/la-audit-repair-all.lock` 串行。
  5. **SUMMARY + DECISIONS 落盘**（39 文件清单终账 + codemod 前后
     grep 对账 + 探针裁定 + ΔN 记账）+ MANIFEST AR-02 节。
- **验收标准（机检）**：定向轮绿 + 探针复测记录（CPU 数值 + 命令）+
  SUMMARY 对账表（3963+ΔN 带 3963..3964）+ MANIFEST 在库。
- **commit**: `test(ar02): reconcile app suite and panel walkthrough manifest`
- **回滚与偏差申报要求**：探针门未达 = 归因排查（本批 init 形改动或
  plan A 树形改动——并行时先与本 plan 隔离复测），禁放行；定向轮
  fail = 先归因窗口，禁静默修窗外缺陷。

---

## 风险与回退

- **个别面板结构特例**：39 面板同构但有分化（双 Params 族/条件 Params
  面等）——特例面板单独处理 + DECISIONS 逐文件申报；禁为凑「单 commit
  机械批」硬套样板（语义等价优先于批形）。
- **闭包捕获语义边界**：面板内若存在跨 init 时点读 paramsData 的非
  computed 面（理论不应存在——发现 = 该面板出 codemod 清单 + 停手上
  报，语义等价论据不覆盖）。
- **codemod 规模摩擦**：39 文件单 commit 的 diff 审查面大——DECISIONS
  附 codemod 前后 grep 对账清单（机械可验）替代逐 hunk 人工读。
- **与 plan A 并行的探针归因**：若合并探针轮未达 CPU 门 = 先隔离两
  plan 分别复测归因（本 plan init 形改动理论零树形结构变化——嫌疑面
  在 plan A；隔离复测是裁决面）。

## Checker 关注点（独立反向核输入）

1. **Goal-backward**：B 路 M2 行 ↔ T1 codemod 全覆盖（39 直读 + helper
   式清点）；RESEARCH §0.1「m2① 勘误降级 + 剩余项归 plan A」↔ 本 plan
   不含 solveReadout/isCustomLook/placementTarget（AR-01 T3 面——无
   孤儿无重复）。
2. **语义等价性**：instance let 值捕获论据在 DECISIONS 正式登记 + 闭
   包捕获面逐文件对账（discreteBinding 样板面核）。
3. **红线核**：ModuleInstance/IOPPanelProvider/LibraryProjectController/
   LightamerSlider 零 diff；AnyView 注册缝零 diff；xcstrings 零 diff；
   封存面零 diff。
4. **L041**：探针路径触发时 Project.swift/BUNDLE-MAP 恰一行 + tuist
   generate 末位（commit 顺序面核）；零探针裁定 = 三面全零 diff。
5. **SC 可机检性**：grep 对账清单 + 定向轮 + 探针 CPU 数值；ΔN 对账
   式（带 3963..3964）。
6. **C 路并入**：合并 MANIFEST 亲读记录（39 口径是否被 C 路修正）。
7. **编排**：并行零交集维持（LightamerSlider 零 diff 锚）；探针合并
   窗口记录；--all 批准制 + 锁串行。
