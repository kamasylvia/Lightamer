---
phase: m8-fsim-spectral
plan: "M8-2"
title: "plan 2 — FSIM 管线集成（T1 film leg 工厂 process 分叉换臂 / T2 FilmSolveCache 光谱域求解 / T3 FilmPrintBake 光谱表 bake 家族 / T4 process v2 bump 五件套 / T5 双臂冻结 golden + sidecar 零 bump + 折键负测 / T6 收口）"
wave: 3
depends_on: ["M8-1a", "M8-1b"]
autonomous: true
requirements: ["charter = 本 phase CONTEXT.md（D-M8-1/D-M8-8 + X4 + 红线 2/3/17）——光谱核产线上线波（v2 档）+ 密度核冻结", "research 正本 = phases/m8-fsim-spectral/RESEARCH.md（9b256482）§3.1（缝位零改）/ §3.2（process 双臂）/ §4.3（solve/bake/descriptor 换内核）/ §6.1 M8-2 行", "OQ 裁决正本 = 同目录 CONTEXT.md（process 单源 + solve gain 消费层 + 零 FilmRecord 字段零 schema bump）；NOTICE/OQ-6/OQ-7 面归 M8-3（编排总纲调整注记）", "基线带 = M8-1b 终态（预期 4236..4248）；本 plan 分账 +20..26——双臂 golden 面最大波", "C 档停位 = 本 plan 执行+验收闭环后停汇报；确认后 M8-3 起跑；执行排程在图库选片批验收链后（机器级单重活）"]
success_criteria: "SC 全可机检——T1：assembleFilmLeg/assembleFilmPayloads 工厂内 exhaustive switch over RenderProcess.resolving（.v1/.legacy=密度核冻结臂零改字节 / .v2=光谱臂——FilmMethodBox 消费 SpectralPayloads + SpectralFilmKernels dispatch 编排：A→corr 模糊→B）+ runTerminalTails 骨架/seed 折叠序/3×2 降出矩阵零 diff + 子管线 renderProcess 继承在位（filmPipe.renderProcess）+ descriptor probe 同工厂自动跟随（PixelPipe :1222 注释面亲核——零改确认）；T2：FilmSolveCache 光谱域 AUTO 核重推导（中性包 = dichroic SPD × 负片谱透射 × 相纸感光积分；键形 fnv(materialPairHash ⊕ statsHash ⊕ modeTag) 不变 + modeTag 扩光谱段 + K 标定光谱域重标定）+ exposureEv 走 solve gain 消费层（D-M8-8——record 项消费叠加不入缓存键）；T3：FilmPrintBake 光谱表 bake 家族（PCHIP 33³ Float64 构建 + LRU + bakeCount 可观测——机制同位扩展）+ per-pair 键控不变；T4：process v2 bump 五件套（case v2 doc 账本/all=[.v1,.v2]/current=2/AGENTS 账本行/分叉点登记）+ mint 升号（新档 process=2 写 sidecar）+ 缓存折键「非 legacy 才折」（policyTag 升光谱段——折叠序钉死 + legacy 档键字节恒等负测）；T5：双臂冻结 golden（密度核 v1 档全链零漂移——既有 FilmDeterminism goldens 含 filmRampPlaneHash=14_365_179_805_968_017_957 逐位 + 光谱臂 v2 golden 三件套：ramp 场/真图抽样/中性闭合）+ sidecar 零 bump 验证（v11 decode→encode 逐字节 + process 键往返 + 零 FilmRecord 字段零新键 grep）+ 默认中性零行为门（pristine 文档零 diff）；T6：收口"
estimated_tests: "+20..26（T1 +2..3 / T2 +4..5 / T3 +3..4 / T4 +3..4 / T5 +5..6 / T6 +3..4〔光谱臂端到端 + sidecar 往返 + 零漂移负测组〕；越带申报理由）"
test_bundles: [IOP, IOPParity, Layers]
baseline: "M8-1b 终态带 4236..4248（基线 4206/41/0 + 1a + 1b 分账；本 plan 开工前亲核 M8-1B-SUMMARY 实数）"
expected_all: "M8-1b 终态 + ΔN（本 plan 终态带 4256..4274；--all 归 M8-3 收口轮统一对账——本 plan 验收 = 构建 + 定向 bundle〔IOP/IOPParity/Layers〕）"
red_lines:
  - "共用红线正本 = CONTEXT §四 plan 红线 front-matter 17 条（本 plan 高相关 = 红线 2 封存面〔film leg 自有区豁免——runTerminalTails 骨架/seed 序/box 对外面仍零改〕/ 红线 3 零 FilmRecord 字段零 schema bump / 红线 17 process 五件套 = 本 plan 收口门）。"
  - "密度核冻结臂 = 逐字节冻结：密度核代码 + 65³ bake 密度域路径 + FilmFilterPackSolver + film_subrun kernel + 密度域 K 标定——.v1/.legacy 分支行为零改，既有 goldens（含 FilmDeterminismTests 全套）零漂移是本 plan 主门。"
  - "折键「非 legacy 才折」契约（RenderProcess :37-44 亲核）：legacy/进程≤1 文档的 film sub-run seed 及全部缓存键逐位恒等——负测钉死；光谱臂 policyTag 折叠序 = X4 钉死形态（DECISIONS 登记终式）。"
  - "MCP/导出/面板面零触：ExportQueueContract/$jobFilmTail 递缝零改（filmTail 跟随文档 record + process）；UI 面归 M8-3；NOTICE/措辞归 M8-3（编排总纲调整）。"
files_modified:
  - LightamerCore/Sources/Pipe/PixelPipe.swift                    # T1：film leg 工厂分叉（assembleFilmLeg/assembleFilmPayloads exhaustive switch——film leg 自有区豁免域）
  - LightamerCore/Sources/Pipe/Film/FilmTailPolicy.swift          # T1/T2：光谱臂 payload 换形 + FilmSolveCache modeTag 光谱段 + policyTag 折叠
  - LightamerCore/Sources/Pipe/Film/FilmPrintBake.swift           # T3：光谱表 bake 家族（PCHIP 33³ per-pair）
  - LightamerCore/Sources/Pipe/Film/SpectralPayloads.swift        # T1：dispatch 编排接线面（A/模糊/B + 降采样调度——M8-1b 预备面的消费接线）
  - LightamerCore/Sources/Pipe/RenderProcess.swift                # T4：case v2 + all + current + processVersion（五件套之账本体）
  - AGENTS.md                                                     # T4：process 账本行 + M8 增量节登记（架构索引）
  - Tests/LightamerTests/SpectralLegForkTests.swift               # T1：新建（IOPParity）——分叉点/冻结臂/probe 跟随
  - Tests/LightamerTests/SpectralSolveTests.swift                 # T2：新建（IOP）——光谱域求解/K 标定/曝光语义
  - Tests/LightamerTests/SpectralBakeTests.swift                  # T3：新建（IOPParity）——bake 家族确定性/键控
  - Tests/LightamerTests/RenderProcessLedgerTests.swift           # T4：新建（Layers）——账本五件套/mint 升号/clamp 表
  - Tests/LightamerTests/SpectralDualArmGoldenTests.swift         # T5：新建（IOPParity）——双臂冻结 golden + sidecar 零 bump + 折键负测
  - Project.swift                                                 # T6：五新测试文件入对应 bundle 显式数组
  - .work/gsd/phases/m2-4-0-test-bundles/M2-4-0-BUNDLE-MAP.txt    # T6：五行落域登记
  - .work/gsd/phases/m8-fsim-spectral/M8-2-SUMMARY.md             # T6：执行摘要（逐任务记账 + ΔN 终账）
  - .work/gsd/phases/m8-fsim-spectral/M8-2-DECISIONS.md           # T6：裁定记录（分叉点登记五件套之⑤ + K 标定终值 + 各偏差）
---

# Plan M8-2 — FSIM 管线集成：film leg 换臂 + solve/bake 光谱域 + process v2 bump

> **裁决正本** = `CONTEXT.md`（D-M8-1/D-M8-8 + X4 + 红线 2/3/17；晨审可推
> 翻）；规格正本 = `RESEARCH.md`（§3.1 缝位零改逐点锚 / §3.2 process 双臂
> 五件套 / §4.3 solve/bake/descriptor 换内核段；planner 抽核吻合）。本
> plan = 光谱核**产线上线波**：换臂后 v2 新档走光谱核、一切旧档
> （process 0/1/absent）走冻结密度核零漂移——双臂 golden 是本 plan 主门。
>
> **裁定权归属钉**：本 plan 无用户裁决分支（T1-T6 形态 = CONTEXT 落定值；
> 迁移 UX = M8-3——本 plan 不做任何 UI 面）。执行中如触「必须扩面」
> （FilmRecord 字段 / sidecar 新键 / schema bump / runTerminalTails 编排
> 骨架改动 / 密度核行为改动 / seed 折叠序重排）= 停手上报，不得自裁扩界。
>
> **执行序**：T1 → T2 → T3 → T4 → T5 → T6（T4 bump 前必须 T1/T2/T3 就位
> ——bump = 上线动作，前后语义由 exhaustive switch 编译期保证）。每任务
> 独立 commit；重活起跑前过 `Scripts/machine-guard.sh`。
>
> **C 档停**：T6 闭环后**停汇报**；确认后 M8-3 起跑。
>
> **基线**：M8-1b 终态（带 4236..4248；开工前亲核 M8-1B-SUMMARY 实数）。
> 全套预期 = 基线 + ΔN（本 plan 分账 +20..26；全套对账归 M8-3 收口轮）。

## ΔN 预算表（逐任务，本 plan 分账带 +20..26；越带须申报理由）

| 任务 | 测试增量 | 构成 | 落点 |
|---|---|---|---|
| T1 换臂分叉 | **+2..3** | 分叉 exhaustive switch（v1→密度/v2→光谱）+ 冻结臂零 diff 断言 + probe 同工厂跟随 | IOPParity（SpectralLegForkTests） |
| T2 solve 光谱域 | **+4..5** | AUTO 核光谱重推导中性命中/K 标定/键形不变/modeTag 扩段/exposureEv 消费层不入键 | IOP（SpectralSolveTests） |
| T3 bake 家族 | **+3..4** | PCHIP 33³ bake 确定性双跑/per-pair 键控/LRU/bakeCount | IOPParity（SpectralBakeTests） |
| T4 process v2 | **+3..4** | 账本五件套/clamp 表（0→v1 冻结/2→v2/3→clamp v2）/mint 升号写档 | Layers（RenderProcessLedgerTests） |
| T5 双臂 golden | **+5..6** | 密度核零漂移组 + 光谱臂三件套 + sidecar 零 bump + 折键负测 + pristine 零行为 | IOPParity（SpectralDualArmGoldenTests） |
| T6 收口 | **+3..4** | 端到端 v2 档渲染冒烟 + sidecar 往返 + 28 张×双臂矩阵冒烟 + 登记 | IOPParity |
| **合计** | **+20..26** | 基线带 → 本 plan 终态带 4256..4274 | 五新测试文件 |

## 已定裁决（生效值，硬约束，不得重开）

1. **process 单源**（D-M8-1）——`≥2` 光谱 / `≤1`+absent 密度冻结；零
   FilmRecord 字段、零 schema bump、零 sidecar 新键。
2. **分叉点 = film leg 工厂 exhaustive switch**（X4）——编译器逐点指向；
   runTerminalTails 骨架/seed 折叠序/3×2 降出矩阵/导出递缝零改。
3. **exposureEv 走 solve gain 消费层**（D-M8-8/X6）——不入缓存键。
4. **账本五件套 = v2 bump 收口门**（红线 17）——缺一 = 拒绝收口。
5. **NOTICE/OQ-6/OQ-7 归 M8-3**（CONTEXT 编排总纲调整）——本 plan 零
   UI 零措辞面。

## read_first（全局，每任务开工前过一遍）

- `.work/gsd/phases/m8-fsim-spectral/CONTEXT.md`（D-M8-1/D-M8-8 + X4 +
  红线 17 条 + 亲核登记 + 晨审索引）
- `.work/gsd/phases/m8-fsim-spectral/RESEARCH.md` §3.1-§3.2（缝位零改锚
  + 双臂形态）/ §4.3（solve/bake/descriptor 换内核）
- `.work/gsd/phases/m8-fsim-spectral/M8-1B-SUMMARY.md` + `M8-1B-DECISIONS.md`
  （corr 终值 + 分级带 + probe 真值——dispatch 编排参数来源）
- `LightamerCore/Sources/Pipe/Film/FilmTailPolicy.swift` 全文（assembly/
  box/solve 三段现状）；`PixelPipe.swift:1145-1402`（film leg + factory +
  replay）；`RenderProcess.swift` 全文（账本 + bump 纪律 + 折键契约）
- `.work/gsd/phases/m6-2-process-version/RESEARCH-NOTES.md`（账本机制正本
  + 迁移 UX 挂账——M8-3 消费预读）
- `.work/LESSONS.md` L041（tuist 末位——五个新测试文件）+ L013（StableHash
  ——折键面）+ AGENTS.md「M2-8 架构增量」（sidecar 零漂移专测先例）+
  「M2-5 架构增量」（LutLibraryStore 键升级 fallback 先例——solve 键形
  演进同构参照）

---

## T1 — film leg 工厂 process 分叉换臂（X4）

> 密度核冻结 = 逐字节冻结；光谱臂 = `FilmMethodBox` 新 payload 形 +
> SpectralFilmKernels dispatch 编排（A→corr 模糊→B，M8-1b T4 corr 终值
> 为降采样因子）。三 leg 编排/seed 四项序/降出矩阵零改——换的只是工厂臂
> 内的 payload 集。

**read_first**：RESEARCH §3.1（工厂同构锚 :1262-1367 + probe 同工厂
:1222 注释）；`PixelPipe.swift:1207-1367`（assembleFilmLeg/
assembleFilmPayloads/runFilmLeg 现状）；`FilmTailPolicy.swift:197-331`
（FilmMethodBox + nil-payload blit）；M8-1B-DECISIONS（corr 终值）。

- **action**：
  1. `assembleFilmLeg`/`assembleFilmPayloads` 内 exhaustive switch over
     `RenderProcess.resolving(renderProcess)`：`.v1` = 现密度核路径**原
     样**（payload 构造与 dispatch 零字节改——冻结臂）；`.v2` = 光谱臂
     （`SpectralPayloads` 构造自 `SpectralBuildEngine` per-sim 表 + A/
     corr 模糊/B dispatch 编排 + nil-payload blit degrade 同语义）。
  2. `FilmMethodBox` 消费面扩形：payload 载体按臂分型（光谱臂 =
     SpectralGPUPayloads；密度臂 = 既有 FilmGPUPayloads）——box 对外面
     （iopOrder 74.0 / nil blit / instances per-run 载体）零改。
  3. 子管线继承确认（`filmPipe.renderProcess = renderProcess` 既有行零
     改）+ descriptor probe 同工厂跟随确认（零改确认门——probe 走
     assembleFilmLeg 同路径，核换臂后自动跟随；response 读数随核变 =
     by design 登记）。
  4. 测试（IOPParity）：分叉断言（**resolving 全域 → 密度 payload 形——
     含 rawValue=2 clamp 面**〔review m4——T1 时序内 `all=[.v1]`，
     `resolving(2)` forward-clamp 回 v1，「v2 文档 → 光谱 payload 形」
     断言在本任务不可能为真（光谱臂代码亦无从挂载），后移 T4 action 5；
     v1 文档 → 密度 payload 形照常断言〕）+ 冻结臂零 diff（v1 路径构造
     的 payload 字节与 bump 前基线恒等）+ probe 跟随冒烟 + nil-payload
     degrade 双臂。
- **验收标准（机检）**：
  - 构建绿；`git diff --stat` 产线文件 ⊆ {PixelPipe.swift,
    FilmTailPolicy.swift, SpectralPayloads.swift}。
  - `git diff PixelPipe.swift` 仅 film leg 工厂区段（runTerminalTails/
    runFilmLeg 骨架行零 diff 机检——diff 行号域核对）。
  - 冻结臂字节恒等断言在册。
  - 既有 FilmDeterminismTests 零回归。
- **commit**: `feat(m82): fork film leg on render process`
- **回滚与偏差申报要求**：回滚 = revert 单 commit（回单臂密度态）；偏差
  （payload 分型形态/编排切分）= DECISIONS 申报；**禁动 seed 折叠序/3×2
  降出矩阵/导出递缝**；**禁在 T1 引入 v2 case**（bump 归 T4——T1 先以
  resolving 现表〔恒 v1〕落地分叉骨架，v2 case 追加时编译器指向补臂）。

## T2 — FilmSolveCache 光谱域求解（D-M8-8 落地）

> AUTO 核（M0,Y0 + autoGain）在光谱域重推导：中性包求解 = dichroic SPD ×
> 负片谱透射 × 相纸感光积分（RESEARCH §4.3）；锚数据不变（neutral_print_
_filters ±10 CC sanity 带续用）；K 标定（session 操作点）光谱域重标定。

**read_first**：RESEARCH §4.3 solve 段 + §1.4（dichroic/中性配平数学）；
`FilmTailPolicy.swift:411-657`（FilmStatsSeam/FilmSolveCache/
FilmRuntimeSolve 现状——键形/LRU 8/RECORD-terms-consumption 契约亲核面）；
`LightamerCore/Sources/Film/FilmFilterPackSolver.swift`（密度域求解参照
——冻结不改）；CONTEXT D-M8-8 + X6。

- **action**：
  1. 光谱域 AUTO 核求解函数（构建期/求解期 Float64——消费 M8-1a T4
     SpectralBuildEngine 积分面〔review m6——原文「T2 引擎」指称错位：
     引擎 = 1a T4，1a T2 = 常量资产，两头不沾〕）：
     中性命中目标 = 中灰印相反射中性（几何均值配平——RESEARCH
     §1.4 数学）；K 标定 = session 系统操作点光谱域重标（中灰灰阶误差
     恰 0 纪律平移——RFC-028 我方域形态）。
  2. `FilmSolveCache` 键形不变 + `modeTag` 扩光谱段（光谱域 tag 与密度域
     tag 空间隔离——跨核不串值）；record 项（手动 Y/M + exposureEv）消
     费层叠加不入键（exposureEv → solve gain 增益路径 = D-M8-8 落地点）。
  3. 测试（IOP）：中性命中（光谱域 solve → 中灰反射中性带）+ K 标定灰阶
     误差 0 + 键形不变（跨核串值负测——同 pair+stats 双 tag 隔离）+
     exposureEv 消费层（record 变 → 解不变→增益变；缓存键不含 exposure
     项断言）+ ±10 CC sanity 带回归（锚数据不变门）。
- **验收标准（机检）**：
  - 构建绿；`git diff --stat` 恰一产线文件（FilmTailPolicy.swift solve
    段）。
  - 键形 grep 断言：`fnv(materialPairHash ⊕ statsHash ⊕ modeTag)` 契约
    行零 diff；modeTag 光谱段常量恰一处声明。
  - 密度域 FilmFilterPackSolver 零 diff。
  - exposureEv 不入键断言在册。
- **commit**: `feat(m82): rewire film solve for spectral core`
- **回滚与偏差申报要求**：回滚 = revert 单 commit（回密度域求解单臂态）；
  偏差（K 标定终值/求解迭代形态）= DECISIONS 申报；**禁改缓存键四项契
  约**（pair ⊕ stats ⊕ tag 三项 + LRU 8）；**禁入 record 项进键**；**禁
  密度域求解器改动**（冻结臂）。

## T3 — FilmPrintBake 光谱表 bake 家族（PCHIP 33³）

**read_first**：RESEARCH §4.3 bake 段 + §1.4（enl 表 33³ build_lut3d 形
态）；`FilmPrintBake.swift` 全文（65³/Float64/concurrentPerform/LRU/
bakeCount 机制正本）；`SpectralBuildEngine.swift`（表构建消费面）；
M8-1A-DECISIONS（PCHIP 带终值）。

- **action**：
  1. 光谱印相/扫描表 bake 家族：per-pair（film×paper）33³ PCHIP 表 Float64
     构建（concurrentPerform 晶格切片 + 固定 ladder——机制同位扩展）+
     float 存储 + cmin/cmax 钳位面随表 + LRU 承载（机制面与 65³ 密度域
     并存——两家族各自 LRU 槽，互不挤兑；容量 DECISIONS 申报）+
     bakeCount 可观测同形。
  2. 测试（IOPParity）：双 bake 同 pair 逐位恒等（确定性门平移）+ per-pair
     键控（pair 变 → miss）+ LRU 容量淘汰 + bakeCount 计数 + 表域钳位面
     断言。
- **验收标准（机检）**：
  - 构建绿；`git diff --stat` 恰一产线文件（FilmPrintBake.swift）。
  - 确定性逐位断言在册；密度域 65³ bake 路径零 diff（冻结）。
- **commit**: `feat(m82): add spectral print bake family`
- **回滚与偏差申报要求**：回滚 = revert 单 commit；偏差（LRU 容量/家族
  拆分形态）= DECISIONS 申报；**禁动密度域 bake 路径与既有 LRU 槽语义**
  ；**禁逐像素精确臂进 bake 面**（D-M8-3）。

## T4 — process v2 bump 五件套（X4/红线 17，上线动作）

**read_first**：`RenderProcess.swift` 全文（bump 纪律 + :109-115 预案
doc-comment = 本任务执行正本）；CONTEXT §X4；M6-2 RESEARCH-NOTES（账本
正本）；AGENTS.md「里程碑一页表」+ process 账本行登记位。

- **action**：
  1. `RenderProcess` 追加 `case v2`（doc-comment = 账本行：M8 光谱核代
     际——fork 点 = film leg 工厂；冻结臂 = v1 密度核）→ `all = [.v1,
     .v2]` → `RenderProcessVersion.current` 升 2 → `processVersion` 补
     映射（exhaustive switch 编译器指向）。
  2. AGENTS.md：process 账本行（M6-2 登记处追加 v2 行）+ 架构索引里程碑
     表 M8 行 + 键族登记节（本批 UserDefaults 零新增声明）。
  3. mint 升号确认面：新档 sidecar `process=2` 写入（既有 mint 点零改
     ——current 即 2）；resolving clamp 表行为断言（0/absent→v1 冻结、
     1→v1、2→v2、>2→clamp v2）。
  4. 缓存折键「非 legacy 才折」落地：光谱臂 policyTag 升光谱段（终式 =
     `"lightamer.film.subrun.v2-spectral"`——X4 钉死形态；折叠序 =
     既有 seed 四项序内 tag 段替换，序本身零改）；v1/legacy 档 tag 不变
     → 键字节恒等。**DECISIONS 同批登记收窄差**〔review m1〕：fold
     discriminator = resolved arm（光谱/密度臂判别），**窄于
     RenderProcess header `rawValue > 0` 字面形**（:41-43 字面形含 v1
     折值）——v1 键冻结是 filmRampPlaneHash 恒等主门要求，本条 = charter
     契约的修订面申报非字面执行。
  5. 测试（Layers）：账本表驱动（all 序/current/clamp 四域/processVersion
     反查）+ mint 升号写档断言 + 折键负测（v1 文档 seed 与 bump 前基线
     逐位恒等——FilmDeterminism 基线值消费）+ **分叉臂断言（v2 档 → 光
     谱 payload 形——T1 后移断言，bump 后为真）**〔review m4〕。
- **验收标准（机检）**：
  - 构建绿；`git diff --stat` 恰 RenderProcess.swift + AGENTS.md。
  - exhaustive switch 编译通过 = 分叉点全覆盖的编译期证明。
  - 折键负测在册（legacy 恒等）。
  - AGENTS 账本行 + 里程碑行在 diff。
- **commit**: `feat(m82): bump render process to v2 for spectral core`
- **回滚与偏差申报要求**：回滚 = revert 单 commit（回 v1 单代际——文档
  process=2 已写出者由 clamp 兜底渲染 v2→clamp v1 后语义回密度核，DECISIONS
  申报该窗口档位处置）；偏差（policyTag 终式/账本行措辞）= DECISIONS 申
  报；**禁触 HistoryHash/ModuleInstance.version**（正交性红线——process
  不折 history hash）；**禁改 resolving clamp 语义**。

## T5 — 双臂冻结 golden + sidecar 零 bump + 折键负测（主门）

> 测试策略门 5/6 正本（CONTEXT）。双臂 golden = 本 plan 最大面：密度核
> v1 档零漂移 + 光谱臂 v2 三件套。

**read_first**：CONTEXT §测试策略门 5/6；`Tests/LightamerTests/
FilmDeterminismTests.swift`（既有 golden 常量面 + 哨兵消费形）；M8-1B
SUMMARY/DECISIONS（光谱臂 ramp 哨兵值 + 分级带）；AGENTS.md「M2-8 架构
增量」（sidecar 零漂移专测先例）；`LightamerSidecar.swift`（v11 往返
测试先例位）。

- **action**：
  1. 密度核零漂移组：既有 FilmDeterminismTests 全套零改跑绿（process v1
     档 golden 含 filmRampPlaneHash 逐位）+ v1 文档全链缓存键恒等负测
     （T4 折键负测的端到端扩臂：seed/levelHash/replay 键族逐位）。
  2. 光谱臂 v2 三件套：合成 ramp 场（光谱臂新哨兵值登记——M8-1b probe ④
     消费）+ 真图抽样 golden（v2 档端到端输出哈希 + 精度带）+ 中性闭合
     （中灰过 v2 全链通道散 ≤2e-3）。
  3. sidecar 零 bump 验证：schemaVersionCurrent=11 零 diff 断言 + v11
     文档 decode→encode 逐字节往返 + process 键往返（2 写读恒等 + 0≡
     absent 语义 + hash-isolated 断言——不进 HistoryHash/driftDetected）+
     零 FilmRecord 新字段/零新键 grep。
  4. pristine 零行为门：无 film record 文档 v1/v2 build 渲染逐位恒等。
  5. 测试（IOPParity）：上述五面各成组（SpectralDualArmGoldenTests）。
- **验收标准（机检）**：
  - 构建绿；`git diff --stat` 恰一新测试文件。
  - 密度核零漂移组全绿（既有 goldens 零改）。
  - sidecar 断言组全绿（schemaVersionCurrent grep 恰 11；LightamerSidecar
    .swift 零 diff）。
  - `git diff --stat` 产线面 = T1-T4 五文件 + AGENTS.md，无第六产线文件。
- **commit**: `test(m82): pin dual arm frozen goldens and sidecar invariant`
- **回滚与偏差申报要求**：回滚 = revert 单 commit；偏差（golden 输入面/
  抽样图选择）= DECISIONS 申报；**禁改既有 goldens 常量**（零漂移主门
  ——光谱臂哨兵是新常量非替换）；**禁放宽 sidecar 断言**（零 bump 是
  D-M8-1 机检面）。

## T6 — 收口（端到端冒烟 + 登记 + tuist）

- **action**：
  1. `Project.swift` 五新测试文件入对应 bundle 显式数组（IOPParity ×3：
     SpectralLegFork/SpectralBake/SpectralDualArmGolden；IOP ×1：
     SpectralSolve；Layers ×1：RenderProcessLedger）+ BUNDLE-MAP 五行
     登记。
  2. `tuist generate` = 本批最后一个动作（L041）。
  3. `--bundle IOP` + `--bundle IOPParity` + `--bundle Layers` 定向全绿；
     ΔN 实数对账（预算 +20..26）。
  4. 端到端冒烟：28 张 profile × 双臂（v1/v2 档）渲染矩阵冒烟 + v2 档
     导出递缝冒烟（$jobFilmTail 零改确认——导出面走查归 M8-3 gui 批，
     此处仅定向 bundle 面）。
  5. SUMMARY（逐任务记账 + ΔN 终账 + probe/峰 RSS 引用）+ DECISIONS（
     分叉点登记〔五件套之⑤〕+ policyTag 终式 + **折键收窄差登记〔
     review m1——fold discriminator = resolved arm，窄于 header
     `rawValue > 0` 字面形；v1 键冻结 = 主门要求〕** + K 标定终值 + 各
     偏差）落盘。
  6. 汇报 + **C 档停**。
- **验收标准（机检）**：定向 bundle 全绿零回归；Project.swift diff = 恰
  五行数组插入；BUNDLE-MAP 在库；tuist generate 后无生成物入 git；
  SUMMARY/DECISIONS 在库；红线 17 五件套逐项在 DECISIONS 勾对。
- **commit**: `test(m82): register spectral integration suites and close out`
- **回滚与偏差申报要求**：回滚 = revert 单 commit；ΔN 越带 = SUMMARY 申
  报理由；禁漏 tuist generate。

---

## 风险与回退

- **冻结臂意外漂移**：分叉重构的连带触碰（如 payload 类型提升引出的间接
  改动）——`git diff` 行号域核对随 T1 验收 + 既有 goldens 零改跑绿双门；
  漂移即停手收敛。
- **光谱域 solve 不收敛**：中性命中迭代在病态 pair 上发散 → 密度域求解
  值作初值 + 光谱域精化的两段式（DECISIONS 申报）；仍不收敛 = 该 pair
  typed 拒绝面（panel 数学既有 typed 拒绝先例）。
- **clamp 窗口档位**：T4 回滚窗口中已写 process=2 的文档在回滚 build 下
  clamp 渲染 v1（密度核）——观感回退但非损坏；DECISIONS 登记处置（重升
  级即恢复）。
- **双臂 golden 面膨胀**：真图抽样 golden 的 fixture 面控制（3-5 张代表
  图 + ramp 场为主，不铺大矩阵——28 张×双臂 = 冒烟级非 golden 级）。

## Checker 关注点（独立反向核输入）

1. **Goal-backward**：RESEARCH §3.2 五件套 ↔ T4 逐件；§3.1 缝位零改锚 ↔
   T1 骨架零 diff 机检；§4.3 solve/bake/descriptor ↔ T2/T3/probe 跟随。
2. **OQ 兑现核**：D-M8-1（零字段零 bump 单源——T5 grep 断言）/ D-M8-8
   （exposureEv 消费层——T2 断言）/ X4（分叉 exhaustive switch + 折键负
   测 + 五件套）。
3. **红线核**：密度核冻结逐字节；既有 goldens 零改；LightamerSidecar/
   HistoryHash/ExportQueueContract 零 diff；Project.swift 数组段 + tuist
   末位；红线 17 五件套勾对。
4. **SC 可机检性**：零 diff 机检（diff 行号域）+ 逐位断言 + grep 计数；
   clamp 表四域表驱动；ΔN 对账式非死数。
