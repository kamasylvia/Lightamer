---
phase: m5-1
plan: "M5-1-03"
title: "TRACK P3——match_color MCP 最小面（reference/targets 批量逐目标独立求解/strength/solver/attach + 返回 params 摘要与求解哈希；微调走既有 apply_params、验收走 render_preview、元数据走 list_iops 零新增面）+ G4 MCP 端到端 parity（Phase 14 SC#3 同型）+ 五门 golden 收口复验（跨 plan 门台账）+ REQUIREMENTS 翻账留验收 + M5-1 phase 收口"
wave: 3
depends_on: ["M5-1-01", "M5-1-02"]
autonomous: true
requirements: ["MCP-09（研究项 C 兑现）", "TRACK-05（G4 + 五门收口）"]
estimated_tests: "+10..16"
test_bundles: [APP]
files_modified:
  - App/Sources/Lightamer/MCP/Tools/MatchColorToolset.swift   # 新建：match_color 工具（签名/批量 fan-out/attach 缝/摘要与哈希返回；render gate 消费）
  - App/Sources/Lightamer/MCP/Tools/EditingToolset.swift      # 修改：register 内一行 `await MatchColorToolset.register(into:seams:)`（密封面最小 diff）
  - Tests/LightamerTests/McpMatchColorToolsetTests.swift      # 新建（APP/App 级）：签名/解析/fan-out/attach/哈希披露/安全面
  - Tests/LightamerTests/McpMatchColorParityTests.swift       # 新建（APP/App 级，G4）：match_color → apply_params → render_preview vs 本地渲染
  - Tests/LightamerTests/McpRegistrySnapshotTests.swift       # 修改（checker 回注 E3，2026-10-09）：`names.count == 19`→`== 20`（:186——security face 注记「closed set asserted VERBATIM」，快照更新必须显式申报非 executor 顺手改数）
  - Tests/LightamerTests/McpLauncherTests.swift               # 修改（E3）：`names.count == 19`→`== 20`（:200）
  - Tests/LightamerTests/McpHostTests.swift                   # 修改（E3）：closed 19-tool face → 20（:242/:694 两处；宿主形态一致性）
  - Tests/LightamerTests/McpFinalSnapshotTests.swift          # 修改（E3）：frozen 19-tool 逐字表 → 20（:165/:193——match_color 的 descriptor/inputSchema/destructiveHint 入 `all19` 表并更名 all20；`testFinalSnapshotUnion19Verbatim` 同步）
  - .work/gsd/phases/m5-1-track/M5-1-03-SUMMARY.md            # 新建（收口）
  - .work/gsd/phases/m5-1-track/M5-1-03-DECISIONS.md          # 新建（收口）
  - .work/gsd/phases/m5-1-track/M5-1-03-ACCEPTANCE.md         # 新建（双重验收）
  - .work/gsd/phases/m5-1-track/M5-1-GATE-LEDGER.md           # 新建：五门跨 plan 台账（每门 → 测试锚 → 终值带 → 落位 plan）——VALIDATION 输入件
  - .work/gsd/REQUIREMENTS.md                                 # 修改：TRACK-01..05 + MCP-09 研究项 C 勾选（翻账留验收惯例）
  - .work/GOAL-STATE.md                                       # 修改：续接点
  - .work/TODO.md                                             # 修改：M5-1 条目
  - .work/LESSONS.md                                          # 如踩坑
---

# Plan M5-1-03 — TRACK P3：match_color MCP 最小面 + G4 + 五门收口

> **性质**：M5-1 三 plan 之三（收口批）。本批交付：`match_color` MCP 编排工具
> （MCP-09 研究项 C 兑现——LumaRescue 式「选参考 → 触发求解 → 强度微调 → 预览
> 验收」agent 编排皮，方法论零搬、许可红线维持）→ G4 端到端 parity → 五门跨
> plan 收口台账 → REQUIREMENTS 翻账。**生产行为可见变化 = MCP 工具列表 +1**；
> GUI/渲染面零变化。规格正本 = `RESEARCH-NOTES.md` §1.3/§5/§6；裁决正本 =
> `M5-1-CONTEXT.md` 裁决记录（OQ-6 最小面生效）。
>
> **基线**：M5-1-02 验收后的实测全套值（对账链 = 3335/16/0 + P1 + P2 增量）。

## 已定裁决（生效值，硬约束，不得重开）

本 plan 承载八项生效值中的 **⑥（match_color 最小面）⑧（G4 + 五门收口）**：

6. **OQ-6（最小面）**：`match_color(reference, targets?, strength?, solver?, attach?)`——reference = 库内 id/路径（load_image 语义同源）；targets 缺省当前图、数组 = 批量（**逐目标独立求解**——源统计逐图不同；工具内 fan-out 一次调用）；strength 缺省 1.0 / solver 缺省 gaussian-ot；attach 默认 true = 自动落位 colormatch 实例并返回 `{op, instanceId, params 摘要, statsHash/求解哈希}`，false = 只返回参数组由 agent 自行 apply_params。**事后微调走既有 `apply_params`，验收走既有 `render_preview`，元数据走既有 `list_iops`——零新增面**。
8. **OQ-8（G4 + 收口）**：G4 = match_color → apply → render_preview 与本地渲染量化一致（Phase 14 SC#3 同型）；五门收口 = 跨 plan 门台账复验。

**架构红线（本 plan 全程 + checker 机检面）**：
- **零新增既有三工具外的任何 MCP 面**（不暴露簇统计/高级参数——OQ-6 备选 B 否；preset 化挂 V2——备选 A 否）。
- **零新网络面、零新依赖**：复用 MCP server 既有绑定/鉴权（回环默认 + token）+ render gate（§RQ-14-13——match_color 为 render-class 工具，进 `withRenderGate`）。
- `EditingToolset.swift` diff 收窄到 register 内**一行**（工具实现全在新文件——密封面最小 diff 申报）。
- GUI/渲染/管线面零 diff（本 plan 纯 App/MCP/测试/文档）；源统计/参考统计提取 = M5-1-02 `ColorMatchService` 既有面复用，零新提取路径（**checker 回注 E6，2026-10-09：一致性注记**——P2 提取面已钉死为管线级 API `extractStats(document:bucket:)`（in-pipe 无头渲染 + readback + P1 纯函数，GUI PREVIEW 完成点只是一调用点），非打开目标图的批量 fan-out 与 attach（store 级实例投影缝）同面复用，本红线与 OQ-6 批量语义同时成立）。
- **许可红线**：LumaRescue 文本/代码零搬（RESEARCH §1.3）——工具 doc/帮助文本自写。

## 关键设计决策（planner 裁决，执行中不重开）

### KD-1 工具签名与语义（T1，OQ-6 生效值）

- 入参 schema（JSON Schema 面）：`reference`（string，必填——**两种形态解析缝钉死（checker 回注 m6，2026-10-09）**：①库内 image id（数字串）→ `LibraryStore.image(id:)`（:438）取行 → `ImageLinker.resolve`（:146——PathKind 0 项目相对 / 1 卷相对+UUID / 2 绝对+UUID 三态）→ URL；②路径 → load_image 同源 `resolveMember(relPath:seams:)`（open-session 成员限定，`notSessionMember` typed 错误）；两形态均 typed 失败披露）；`targets`（string | string[]，缺省 = 当前图）；`strength`（number 0..1，缺省 1.0）；`solver`（enum `gaussian-ot|reinhard|cdf`，缺省 gaussian-ot）；`attach`（boolean，缺省 true）。
- **fan-out 语义**：N 目标 = N 次独立（源统计, 同参考池化统计）求解——**解各不相同是设计语义非缺陷**（工具返回逐目标摘要数组）；单目标 = 数组一角。
- 多参考：**v1 单 reference/调用**（裁决最小面字面——多参考池化 = GUI 面 M5-1-02；MCP 多参考 = V2 若 agent 编排暴露真实需求）。DECISIONS 注记。
- **attach = true**：落位 = `ColorMatchService` 既有 attach 缝（**store 级实例投影缝——apply_params `projectInstances` 同缝，checker 回注 E6**；GUI addAdjustmentLayer 非本缝依赖）+ params commit；返回 `{op: "colormatch", instanceId, params: {solver, strength, statsHash 对}, solveHash: solution.stableHash 十进制}`。**attach = false**：返回参数组（matrix/offset 或 assetRef 语义说明），agent 经 `apply_params` 自行落位（**回灌可行性 = P1 E2 optional 显式 null 编码决策**——cataloged op 键集含 optional 键，未知键拒绝不误伤；T1 端到端断言，checker 回注 m4）。
- **确定性承诺（G1 面向 agent 的披露）**：同 reference + 同 target + 同 params → 同 solveHash——工具返回值携带哈希，agent 可自行复验（文档字符串写明）。
- 超时/并发：render gate 串行（§RQ-14-13 既有）；工具超时 = McpTimeouts render 档既有。

### KD-2 G4 端到端 parity（T2，OQ-8；Phase 14 SC#3 同型）

- 链路 = `match_color(attach=true)` → `apply_params`（strength 0.7 微调——「事后微调走 apply_params」闭环实测）→ `render_preview` → 与**本地 GUI 同参渲染**量化一致（McpRenderParityTests 同型判据：像素容差带 + 实测收窄钉门）。
- 参考图 fixture = 合成图入库测试夹具（确定性解码——禁真 RAW 依赖；L031 路由 queue 纪律自动继承）。
- solveHash 披露断言：两次同参 match_color 调用 → 同 solveHash（G1 的 MCP 面映照）。

### KD-3 五门收口台账（T3，OQ-8）

- `M5-1-GATE-LEDGER.md`：五门 × {定义（CONTEXT 裁决原文）, 测试锚（文件:法）, 终值带（G2 实测带/parity 带）, 落位 plan} 全表；每行 = 台账批亲验（重跑锚测试或引验收轮实测值，禁无证据 ✅——VALIDATION nyquist 口径）。
- 收口轮 = 定向全 bundle（LAYERS/IOPParity/APP + IOP 回归零漂移抽验）全绿 + 对账链闭合（3335 + P1 + P2 + P3 增量逐位）。
- **全套 `--all` 轮 = orchestrator 批准制**（本 plan 收口申请点；运行门 8G + MEMFAIL 机检兜底 + 运行中监视——AGENTS 资源监控节）。

### KD-4 翻账与收口（T4）

- REQUIREMENTS：TRACK-01..05 勾选 + MCP-09 研究项 C 注记兑现（**翻账留验收**惯例——终态 Delivered 由 VALIDATION 批盖）；逐条附门锚（TRACK-01→G1/G3、02→池化测试、03→G5/持久化、04→面板走查、05→五门台账）；**TRACK-03 勾选注记显式记录裁决偏差（checker 回注 m7，2026-10-09）**：REQUIREMENTS TRACK-03 原文「**内嵌 LUT** + tetrahedral 插值 kernel」→ 生效值 = `.cube` 派生资产 + params 存引用（内嵌 → 派生资产，OQ-M5-1-3 裁决 2026-10-11）——防 VALIDATION 期对表困惑。
- VALIDATION 输入件 = GATE-LEDGER + 三 plan ACCEPTANCE + 走查配方（`.work/gui-acceptance/m5-1/` MANIFEST——P2 T8 已落，本批汇总指针）。
- **双重验收**照 config（zcode → 串行 omp；严禁并发）。

## read_first

1. `.work/gsd/phases/m5-1-track/M5-1-CONTEXT.md`（OQ-6/OQ-8 生效值正本）+ `RESEARCH-NOTES.md` §1.3/§5/§6
2. `App/Sources/Lightamer/MCP/Tools/EditingToolset.swift` 全文（register 形/Seams 面/apply_params 落位缝 :627/render gate——match_color 的直接宿主）
3. `App/Sources/Lightamer/MCP/Tools/IopCatalog.swift`（colormatch 行——list_iops 元数据自动可用面）
4. `App/Sources/Lightamer/MCP/McpToolRegistry.swift`（register/descriptors/render gate/超时档）
5. `Tests/LightamerTests/McpEditingToolsetTests.swift` + `McpRenderParityTests.swift`（工具测试与 G4 parity 的体例正本）
6. `App/Sources/Lightamer/State/ColorMatchService.swift`（M5-1-02——attach/提取/重解缝的唯一消费面）
7. `.work/gsd/phases/14-mcp-server/` 的 SC#3 记录（G4 判据先例）+ `phases/m5-1-track/M5-1-01-DECISIONS.md`/`M5-1-02-DECISIONS.md`（P1/P2 实测带——台账终值上游）

## 纪律（强制）

- 与 P1/P2 同款全套（每任务独立提交 / caffeinate / test-direct 定向轮 / 零 diff 自证 / 资源监控 / 中文标注显式）。
- **收口机检**：`grep -rn "\"match_" App/Sources/Lightamer/MCP/Tools/` = MatchColorToolset.swift 一文件（零新工具面申报）；`git diff <P2基线>..HEAD -- LightamerCore LightamerIOP` 零命中（本 plan 零 Core/IOP 触碰铁证）；EditingToolset diff = register 一行。
- 工具 JSON doc/描述文本全英文自写（许可红线——零 LumaRescue 文本）。

## Tasks

### T1 match_color 工具（KD-1）

- read_first 2/4/6 → `MatchColorToolset.swift` + EditingToolset register 一行。
- **19-tool 快照族全量更新（checker 回注 E3，2026-10-09——独立验收面非顺手改数）**：`McpRegistrySnapshotTests`（:186）/`McpLauncherTests`（:200）/`McpHostTests`（:242/:694）`names.count`/`tools.count` 19→20 + `McpFinalSnapshotTests` frozen 逐字表（:165/:193）入 match_color descriptor/inputSchema 并更名 all20——四文件在 files_modified 申报内；`McpRenderParityTests.swift:564` 为注释级引用不动（checker 亲核）。工具名快照属 security face，更新显式入 SUMMARY。
- 验收：`McpMatchColorToolsetTests`（APP）——schema 解析全参/缺省；reference 解析（id→`LibraryStore.image(id:)`+`ImageLinker.resolve` / 路径→`resolveMember` / 非法 typed 错误——m6 解析缝两形态各一条）；fan-out（双目标 → 两摘要两解）；**无头批量一条（checker 回注 E6）**：非打开 GUI 会话态目标图 → `extractStats(document:bucket:)` 无头提取 + store 级 attach 落位 → 摘要返回；attach=true 落位链（实例在 grade 层 + params 摘要 + solveHash 十进制）；attach=false 参数组返回 + **参数组经 `apply_params` 回灌成功端到端一条（checker 回注 m4——assetRef 语义说明在参数组内，显式 null 编码键集接纳）**；strength/solver 透传；render gate 消费断言；**colormatch 经 list_iops/apply_params 元数据自动可用**（IopCatalog 既有机制端到端一条）。

### T2 G4 端到端 parity（KD-2）

- read_first 5/7 → `McpMatchColorParityTests`（APP）。
- 验收：match_color → apply_params(strength 0.7) → render_preview vs 本地渲染量化一致（实测带收窄钉门入 DECISIONS）；双调用同 solveHash；批量双目标 parity 一条。

### T3 五门收口台账 + 收口轮（KD-3）

- read_first 7 → `M5-1-GATE-LEDGER.md` + 定向全 bundle 轮 + 对账链闭合。
- 验收：五门全表每行有锚有值有落位（亲验记录）；LAYERS/IOPParity/APP 定向全绿零 MEMFAIL；IOP 抽验零漂移；对账链 = 3335 + 三批增量逐位闭合；全套 `--all` **申请 orchestrator 批准**后执行（批准前不得自跑）。

### T4 翻账 + 收口（KD-4）

- 验收：REQUIREMENTS 勾选 + 门锚注记；SUMMARY/DECISIONS/GOAL-STATE/TODO 同批；VALIDATION 输入件清单成文（GATE-LEDGER + 三 ACCEPTANCE + 走查 MANIFEST 指针）。
- **双重验收**：zcode 独立验收 → **串行** omp 二次验收（严禁并发）；结论落 `M5-1-03-ACCEPTANCE.md`。

## 验收标准（AC 总表）

1. **生效值⑥（最小面）**：match_color 五参签名全落（reference/targets 批量逐目标独立求解/strength/solver/attach）；返回摘要 + solveHash；微调/验收/元数据全走既有三工具（**零新 MCP 面**机检）；**19-tool 快照族 19→20 全量更新 + match_color 入 frozen 逐字表（checker E3）**；无头批量提取/attach 一条（E6）+ attach=false 参数组 apply_params 回灌一条（m4）。【T1】
2. **生效值⑧（G4）**：端到端 parity 链量化一致（Phase 14 SC#3 同型）+ solveHash 披露断言（G1 的 agent 可复验面）。【T2】
3. **五门收口**：GATE-LEDGER 五门全表（定义/锚/终值带/落位）亲验闭合；对账链逐位。【T3】
4. **确定性承诺**：同输入同 solveHash（双调用断言）——agent 自行复验可行。【T2】
5. **红线自证**：零新依赖/零新网络面/零 Core-IOP diff/EditingToolset 一行 diff/render gate 消费/LumaRescue 零搬。【T4】
6. **翻账**：TRACK-01..05 + MCP-09 研究项 C 勾选 + 门锚（留验收终态）。【T4】

## 风险与边界

- **fan-out 多目标时长**：N 目标 = N 次求解 + N 次落位——render gate 串行下批量上限照 apply_params 批量档惯例；超时面 typed 错误逐目标披露（部分成功形态显式——DECISIONS 记录部分失败返回形态）。
- **G4 带宽**：render_preview 与本地渲染的量化一致带以 McpRenderParityTests 既有判据为基；colormatch 采样非确定性（GPU）已在既有判据容差内——实测超带先查比较域（L048）再查 gate 串行性。
- **参考图不可达（MCP 面）**：reference 解析失败 = typed 错误；统计重解遇参考不可达 = degrade 语义（P2 既有）+ 工具错误披露——不静默空解。
- **MCP 多参考缺口**：v1 单 reference/调用为裁决字面；agent 侧多参考需求 → V2（preset 化同批挂账——OQ-6 备选 A）。

## 提交约定

- T1 `feat(mcp): match color tool with per target fan out`
- T2 `test(mcp): match color end to end render parity`
- T3 `docs(m5-1): five gate ledger with closeout runs`
- T4 `docs(m5-1): close track phase with requirements ledger`
- 全英文 Conventional Commits；不 push。
