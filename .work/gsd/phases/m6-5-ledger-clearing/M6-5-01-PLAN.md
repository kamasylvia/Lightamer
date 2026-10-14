---
phase: m6-5
plan: "M6-5-01"
title: "M6-5 挂账清算批（单 plan）——清偿六件（T1 孤儿 fixture 根治〔RasterEditFaceTests restore 腿 temp 化〕/ T2 SessionBatchApplier 文档级 additive 字段携带补齐 / T3 McpServerController 头注 19→20 / T4 gain-map HDR-base 行序方向性断言 / T5 门③载体分叉 API 消费者注记 / T6 格式键插值形态机检硬化）+ Manual-Only 走查汇编（纯 doc）+ 转 V2 九项登记（纯 doc）+ 全套 --all 确认轮（预期 3846/24/0 = 3843 核销基线 + 3，8G 门红线）"
wave: 1
depends_on: []
autonomous: true
requirements: ["M6-5（ROADMAP §M6-5 行 + TODO M6-5 条——挂账单一清单逐项闭合或转 V2 挂账留痕）"]
estimated_tests: "+3（T2 +2 / T4 +1；执行时逐任务如实记账）"
test_bundles: [APP, LIB]
baseline: "3843/24/0（M6-4 修批后推算，带 3840..3844；本批 --all 确认轮核销）"
expected_all: "3846/24/0（= 3841 实测 + 2 修批 + 3 本批；对账式精确，执行时按 ΔN 实记账）"
files_modified:
  - Tests/LightamerTests/RasterEditFaceTests.swift                  # T1：testRestoreWinsOverDerive 改 tempFixtureCopy（DepthMaskEditingTests.swift:273 helper 同款）——写腿（recordDrtChange + flushUntilPersisted）落在 tmp 副本；repo 路径仅读 + 入口防御前清保留；:173-200
  - Tests/LightamerTests/SessionBatchApplierTests.swift             # T2：+2 法（既有档臂七 additive 字段全带 + pristine 臂 additive 面零变化）
  - LightamerCore/Sources/Session/SessionBatchApplier.swift         # T2：composeSegment 既有档臂显式捕获 7 字段（provenance/rawOverrides/displayTransform/versions/activeVersionID/aiProvenance/filmRecord）+ 构造点传入；process 分支条件盖章纪律零触（:158-163 E1 注记原样）；pristine 臂缺省 nil 不变
  - App/Sources/Lightamer/MCP/McpServerController.swift             # T3：:15 + :447-449 两处 19-tool 头注/文档注释 → 20-tool（match_color 在册）；零行为
  - Tests/LightamerTests/ExportGainMapTests.swift                   # T4：+1 法——非 uniform 增益面（上下半场异增益）× 非对称 base 的行序方向性断言（锚 = ExportGainMapEncoder.swift:137 .oriented(.downMirrored)）
  - LightamerCore/Sources/Export/ExportRecipe.swift                 # T5：validate 门③（:158-191）加 API-consumer 契约注记（载体分叉残余；全 UI 路不可达）；零行为
  - LightamerCore/Sources/Export/ExportRenderer.swift               # T5：:519 headroom 取值点同款注记（两载体同源自证义务）；零行为
  - AGENTS.md                                                       # T6/T9：M6-5 架构增量节（机检硬化形态登记 + --all 确认轮终值 + 清算台账指针）
  - .work/gui-acceptance/m6-5/MANIFEST.md                           # T7（gitignored 证据域，不 commit——落盘即可）：Manual-Only 走查汇编 ~17 行
  - .work/gsd/phases/v2-station/V2-PROPOSAL.md                      # T8：挂账区追加九项（§CONTEXT §5 措辞）
  - .work/gsd/phases/m6-5-ledger-clearing/M6-5-01-SUMMARY.md        # T9：执行摘要（逐任务 ΔN 记账 + 挂账闭合对表）
  - .work/gsd/phases/m6-5-ledger-clearing/M6-5-01-DECISIONS.md      # T9：裁定记录（分类偏差 + 执行期发现）
  - .work/TODO.md                                                   # T9：M6-5 条目落账
  - .work/GOAL-STATE.md                                             # T9：续接点
---

> **夜间全自动授权**（先例 D-07-3-T5-1；晨审可推翻）。清查正本 =
> `M6-5-CONTEXT.md`（盘点表 40 项 + 分类裁定 + file:line 量级评估）。
> 派遣形态 = research+plan 合批 worker 产物，执行批（omp 或 ZCode
> executor）接手本 plan。**零新 SPM / 零新 UserDefaults 键 / 零 `.metal`
> / 零 xcstrings**（T3/T5 注记不引入键；T4 断言复用既有 fixture 域）。

# Plan M6-5-01 — 挂账清算批（单 plan）

> **性质**：清偿 + 汇编 + 登记 + 确认轮四合一。每个清偿任务独立 commit
> （Conventional Commits，只 add 相关文件）；doc 任务（T7/T8）与收口
> （T9）各一 commit。构建用 `caffeinate -dis` 包裹；单测标准命令 =
> `Scripts/test-direct.sh`（直启宿主，绕开 testmanagerd）。

## read_first（全局，每任务开工前过一遍）

- `.work/gsd/phases/m6-5-ledger-clearing/M6-5-CONTEXT.md`（本批正本）
- `.work/config.toml [gsd]` paused/auto 开关（暂停机制）
- `.work/LESSONS.md` L041（tuist generate 恒末位）/ L074（直驱 commit
  类测试图片锚必须 temp 化）/ L014（GPU 读回 fence）
- `AGENTS.md` 资源监控节（--all 批准制 + 8G 门 + MEMFAIL 机检）

---

## T1 — 孤儿 fixture 根治（A1/B2/C3 三源同条；M4-1 挂账 #6 终局）

- **action**：
  1. `RasterEditFaceTests.swift` 增加 `tempFixtureCopy(_:)` helper
     （`DepthMaskEditingTests.swift:273` verbatim 同款：fixture 拷
     temp UUID 目录，调用方 tearDown 随目录清除）。
  2. `testRestoreWinsOverDerive`（:173-200）：`let url = try
     tempFixtureCopy("srgb-matrix-8.tif")` 替换 repo fixture 取用——
     :187-190 的真实写腿（load → recordDrtChange → flushUntilPersisted）
     全部落 tmp 副本；repo 侧保留一行防御性 `removeItem`（存量孤儿不毒轮）。
  3. 文件头注释补一行 M4-1 #6 终局注记（写腿 temp 化 = L074 纪律兑现）。
  4. 测试运行前置清扫：删除现存孤儿 `Tests/Fixtures/TiffRaster/srgb-matrix-8.tif.lra`（untracked，直接 rm）。
- **验收标准（机检）**：
  - 定向 `--bundle APP RasterEditFaceTests` 全绿（7 法含改后 restore 法）。
  - 定向 `--bundle EXPORT RasterRoundTripTests` 全绿（读同 fixture 的
    跨 bundle 面不受扰）。
  - 轮毕 `find Tests/Fixtures -name "*.lra"` 零命中（transcript 记
    SUMMARY）。
  - `git status` 确认 Tests/Fixtures 无新增 untracked。
- **commit**: `fix(m6-5): move the restore-leg sidecar write onto a tmp fixture copy`

## T2 — SessionBatchApplier 文档级 additive 字段携带补齐（C2）

- **action**：
  1. `SessionBatchApplier.swift` 既有档臂（:111-118 decode 成功分支）：
     捕获 `provenance = document.provenance`、`rawOverrides`、
     `displayTransform`、`versions`、`activeVersionID`、`aiProvenance`、
     `filmRecord` 七字段（命名 = `LightamerSidecar.swift:317-365` 原文）。
  2. :149-163 `LightamerSidecar(` 构造点：七参显式传入（additive、
     缺省 nil 语义不变）；**`process: processStamp` 分支条件盖章纪律
     零触碰**（:158-163 注记原样保留；禁 `?? .current`）。
  3. pristine 臂（:119-133 else 分支）零改（新档 additive 字段缺省 nil
     = 既有字节面零漂移）。
  4. `SessionBatchApplierTests.swift` +2 法：
     - `testBatchApplyCarriesDocumentLevelAdditiveFields`——构造含七
       字段的目标档（decode document 直写盘），composeSegment 后断言
       composed 文档七字段全带（+ process 走既有档臂 verbatim）。
     - `testBatchApplyPristineArmKeepsAdditiveFaceEmpty`——无档目标
       compose 后七字段全 nil（既有面负测）。
- **验收标准（机检）**：定向 `--bundle LIB SessionBatchApplierTests`
  全绿（既有法含三态 process 法不红）；`git diff LightamerCore/Sources/Session/SessionBatchApplier.swift`
  仅 :100-163 窗内 additive 行；sidecar schema 文件零 diff。
- **commit**: `fix(m6-5): carry document-level additive fields through batch apply`

## T3 — McpServerController 头注 19→20（A13）

- **action**：`McpServerController.swift` :15（「closed 19-tool set」）
  与 :447-449（「frozen 19-tool set」）两处注释改 20-tool 并补一句
  「+ match_color（M5-1-03）」；不加新注释块，原位改词。
- **验收标准（机检）**：`grep -n "19-tool" App/Sources/Lightamer/MCP/McpServerController.swift`
  零命中；`grep -rn "20-tool" App/Sources/Lightamer/MCP/McpServerController.swift`
  ≥2 命中；`git diff` 仅注释行（零代码行变更）。
- **commit**: `docs(m6-5): update the MCP tool-face header to the 20-tool set`

## T4 — gain-map HDR/base 行序方向性断言（D2）

- **action**：
  1. `ExportGainMapTests.swift` +1 法
     `testGainMapRowOrderIsTheDownMirroredAlignment`——构造非 uniform
     增益面（上半场 gain ≈1.0 / 下半场 gain ≈2.0，单通道）× 非对称
     base（上半场中灰 / 下半场高光），走 `ExportGainMapEncoder.encode`
     产文件 → ImageIO 重读 aux 增益面：断言下半场采样点增益语义显著
     高于上半场（行序方向单向断言；如单向断言带不稳，改 flip 反置
     负测——手工翻转增益面重编码，两产物逐位不同 + 方向互换）。
  2. 断言形式执行时择稳（CONTEXT §3.4 预案二选一），DECISIONS 记选择
     理由。
- **验收标准（机检）**：定向 `--bundle EXPORT ExportGainMapTests`
  全绿（25 法 = 24+1）；新法在无 gain-map 负测族之外独立；`git diff`
  仅测试文件 additive。
- **commit**: `test(m6-5): pin the gain-map row order with a directional assertion`

## T5 — 门③载体分叉 API 消费者注记（D4）

- **action**：`ExportRecipe.swift` validate 门③（:158-191）与
  `ExportRenderer.swift:519` headroom 取值点各加一段注释：直接构造
  `ExportQueue.Request` 的 API 消费者可组出「`drtOutput.peakLuminance`
  ≥203 合格 + `drtTail.record.peakLuminance` 偏低」→ 产物
  headroom<1（gain 语义弱化非崩溃）；两载体须消费方自证同源（生产 UI
  路经 `enqueueExportM2` 强制联动不可达——M6-3 双路验收在案）。零行为。
- **验收标准（机检）**：`git diff` 仅两文件注释行；Export 定向轮编译
  绿（`--bundle EXPORT` 抽一轮或 build 证编译）；无断言/行为变化。
- **commit**: `docs(m6-5): note the gate-3 carrier-fork contract on the public export API`

## T6 — 格式键插值形态机检硬化（F1 顺带候选采纳）

- **action**：
  1. 在红线机检电池（per-batch grep 族）登记新检查形态：
     `grep -rnE 'String\(localized: "[^"]*\\' App/Sources LightamerCore/Sources LightamerIOP/Sources`
     （`String(localized: "…\(` 插值禁形——V14 家族第二形态，M2-9 F-2
     先例的 localized: 入口面）。
  2. 本批跑一轮全仓机检，transcript 记 SUMMARY（预期零命中基线；若有
     命中 = 执行期发现，逐条评估改显式 switch 静态键或登记豁免，
     禁静默）。
  3. 检查形态写入 AGENTS「M6-5 架构增量」节一行（后续批红线电池引用）。
- **验收标准（机检）**：transcript 在案（命令 + 输出 + 处置）；AGENTS
  登记行落盘。
- **commit**: `docs(m6-5): register the localized-key interpolation grep gate`

## T7 — Manual-Only 走查汇编（纯 doc，不执行）

- **action**：落盘 `.work/gui-acceptance/m6-5/MANIFEST.md`——汇编
  CONTEXT §6 行集（M5-1 human rows + G2/A8/A10 观察行；M5-2 行 1/3/4；
  M5-3 行 2/3/5 + 行 4 屏面；M6-1 C 行；M6-3 跨生态可选行；M6-4
  M-1..M-4 + plan01 五行 + D-06/D-07 补录义务行；rider = M4-3 guided
  filter 深边界糊）。每行 = 配方指针（来源 MANIFEST 锚）+ 前置供件 +
  预期观测。**bake 生产耗时（A4）单列 perf 观察行**（非 GUI 行）。
- **验收标准**：MANIFEST 行数 = CONTEXT §6 明细逐条可对；每行有来源
  指针；零执行声明（「本批不执行」头注）。
- **commit**：**不入 git**（`.work/gui-acceptance/` 证据域 gitignored，
  L073 口径）——落盘即可，SUMMARY 记路径。

## T8 — 转 V2 九项登记（纯 doc）

- **action**：`V2-PROPOSAL.md` 末尾追加「七、M6 清算批转 V2 挂账
  （2026-10-16 M6-5 批登记）」节——CONTEXT §5 九项措辞落盘（每项：
  名称 / 来源 phase + 锚 / 触发条件 / 规模 / 一句话）；登记头注声明
  「登记 ≠ 立项，终裁在用户」。C1（PROCESS-WIRING）落触发条件档形态，
  触发条款与 M6-2 DECISIONS §6 逐字一致。
- **验收标准（机检）**：九项各有一级标题行 + 触发条件字段；来源锚
  可 grep（各 VALIDATION 挂账节原文在位）；零删除既有内容（纯追加节）。
- **commit**: `docs(m6-5): register nine V2 candidates from the M6-5 ledger sweep`

## T9 — 全套 `--all` 确认轮 + 收口（批准制 + 8G 门红线）

- **action**：
  1. `tuist generate`（如 Project.swift 有登记变更——本批 files_modified
     无新测试文件，一般不需要；有则 generate 恒末位，L041）。
  2. **全套确认轮**：`caffeinate -dis Scripts/test-direct.sh --all`
     （夜间授权链覆盖 = 批准在案；运行中保持监视，>8G 或内存压力转红
     立即 kill）。
  3. 轮毕孤儿复扫：`find Tests/Fixtures -name "*.lra"` 零命中
     （T1 终验 transcript）。
  4. SUMMARY（逐任务 ΔN 记账 + 挂账闭合对表 40 项逐行状态）+
     DECISIONS；AGENTS「M6-5 架构增量」节（终值 + 硬化形态 + 台账
     指针）；TODO M6-5 条目 [x]；GOAL-STATE 续接点翻新 = M6-5 closed
     → M6-6。
- **验收标准（机检）**：
  - exit 0 + 0 fail + 0 MEMFAIL + 七 bundle 全 8G 门内；
  - **TOTAL == 3843 + ΔN（预期 3846/24/0；ΔN = T2 +2 + T4 +1，执行时
    如实记账）**；对账式 = 3841（M6-4 实测）+ 2（M6-4 修批）+ 3（本批）
    = 3846 精确；异常形态（ΔN=0）回退核销带 3840..3844 判定并停手上报；
  - 孤儿复扫零命中 transcript；
  - 五正本翻账同批（TODO/GOAL-STATE/AGENTS/ROADMAP M6-5 行 ✅ 由
    VALIDATION 批执行——本 plan 只翻 TODO/GOAL-STATE/AGENTS，ROADMAP
    M6-5 行翻账留 M6-6 VALIDATION 或本批 VALIDATION 面，执行时按
    orchestrator 指令）。
- **commit**: `docs(m6-5): close the ledger-clearing batch (full-suite confirmation)`

---

## red_lines（零 diff 机检族，T9 收口核对）

- `LightamerIOP/` 全域零 diff；全部 `*.metal` 零 diff。
- `LightamerSidecar.swift` 零 diff（schema 零字节变更；T2 只消费
  既有字段）。
- `Pipe/History/` + `PipeCacheKey.swift` 零 diff；V50Order 零触。
- MCP 快照族（McpRegistrySnapshotTests 等）零 diff（T3 纯注释不触
  descriptor 面——快照若含注释面则复核 diff 仅 McpServerController）。
- Export 六格式矩阵面（`ExportFormatSpec`/`ImageIOEncoders`/
  `WebPEncoder`）零 diff（T5 纯注释）。
- `Project.swift` dependencies 块零 diff（零新 SPM）；无新测试文件则
  Project.swift 全零 diff。
- `*.xcstrings` 零 diff + UserDefaults 零新键 + `\.runModal(` App/Sources
  零命中 + `String.LocalizationValue("` 插值禁形零命中 + T6 新门零命中
  基线。
- 工作树零新增 untracked 源文件（孤儿 fixture 复扫零命中是唯一允许的
  「无残留」态）。

## 风险与回退

- T1 改法若遇 restore 腿在 tmp 域的时序差（flushUntilPersisted 轮询
  语义同构，风险低）——回退预案 = 保持 repo 路径写但在 tearDown 后
  加有界 write-behind 等待窗再清扫（同步序），DECISIONS 记录。
- T4 断言形式二选一预案在 action 内置（单向断言不稳 → flip 反置负测）。
- --all 轮贴线 bundle（IOP/IOPParity）连续 MEMFAIL → 先查重测顺序漂移
  （AGENTS 在案口径），非本批引入面（零 IOP 触碰）。
- 全套轮任何 fail：先归因（本批 Δfiles 窗内?）——本批批内窗 =
  SessionBatchApplier.swift + 4 测试文件 + 3 注释文件；窗外 fail =
  既有缺陷，停手上报不静默修。
