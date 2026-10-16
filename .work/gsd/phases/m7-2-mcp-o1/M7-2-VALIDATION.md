---
phase: M7-2（MCP O1 检索与状态读——MCP2-01..03）
slug: m7-2-mcp-o1
status: validated
nyquist_compliant: true
created: 2026-10-16
validated: 2026-10-17
batch_form: dual-acceptance closeout（执行批 ΔN +17 已入库；本签核批 doc-only）
---

# Phase M7-2（MCP O1 检索与状态读）— Validation（双路独立验收 PASS 签核——agent 检索/历史/状态三读面交付）

> 体例对齐 `phases/m7-1-shell/M7-1-VALIDATION.md`（正本链上溯
> `phases/fix2-defects/FIX2-VALIDATION.md` → `phases/v2-maintenance/V2M-VALIDATION.md`）。
> 执行链 `9f69775b..8f12ffcc`（7 commits 含 fix `20997721`）；双路独立验收 =
> 第一路 `M7-2-01-ACCEPTANCE.md`（切入 = parity 深审 + 真 MCP stdio 端到端）
> + 第二路 `M7-2-01-ACCEPTANCE-2ND.md`（切入刻意错开 = 五面语义审计 + 真
> MCP stdio/HTTP 端到端独立抽测 + 两进程只读臂独立复现）——**PASS /
> 0 error + 2 minor 零实质分歧**（2 minor = F-AC-1 / F-AC-2 双路独立确认
> 属实，登记缺口级不阻塞）；**三路全套同值 `TOTAL|3877/35/0|`**（执行批
> T5 + 双路独立复跑，exit 0 零 MEMFAIL，七 bundle 全 8G 门内；= 3860 基线
> + ΔN 17 精确闭合）。omp 制度路由双 zcode 独立眼替代（M6-2..M6-5 先例，
> 晨审可裁）；夜间全自动授权在案（先例 D-07-3-T5-1，晨审可推翻）。端到端
> 证据面 = 真 MCP 宿主 stdio 23 工具 + HTTP 两进程三证 + EXIF 翻段链 ≡
> 独立 SQL 参照（两路独立到达同一序）。裁定正本 = `M7-2-CONTEXT.md`
> （D-M7-2-1..9 零重开）+ `M7-2-01-DECISIONS.md`（§1 显式改申报 + §2 实现
> 裁定）+ 双 ACCEPTANCE；数字正本 = 本文件。

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Batch form** | 执行批 T1→T6（`9f69775b` T1 骨架+context+registry 第三参+五缝+xcstrings → `5a89f07f` T2 三路由+modelUnavailable → `028c6230` T3 两投影 → `9efbd976` T4 只读臂+discovery 变体 → `20997721` fix projectDirectory 目录锚〔T5 golden 抓获回注，闭环〕→ `32055308` T5 测试批+union 23+登记 L041 → `8f12ffcc` T6 收口翻账）→ 双路验收 → 本签核批（doc-only） |
| **Full suite（三路同值）** | 执行批 T5（2026-10-16 23:19）/ 第一路（2026-10-17 00:20-01:15）/ 第二路（2026-10-17 00:09-00:49，2102s）三路独立跑 `caffeinate -dis Scripts/test-direct.sh --all` 均 **`TOTAL\|3877/35/0\|` exit 0 零 MEMFAIL**；七 bundle 逐值稳定：IOP 687/5/0（RSS 7541/7588/7643MB ±方差）/ IOPParity 460/3/0（8112/7376/8093MB——已知贴线 bundle，三轮全 8G 门内）/ Layers 494/5/0 / Library 729/4/0 / Sessions 284/9/0 / Export 379/5/0 / App 844/4/0（三路 RSS 2832MB 同值）；skip 35 构成 = 5+3+5+4+9+5+4，全部既有 env/perf-probe 门，零静默吸收 |
| **ΔN 记账** | **ΔN = +17**（`McpSearchStateToolsetTests` 17 法，双路亲数对账）；对账链 3860 基线 + 17 = 3877 **精确闭合**；union 快照显式改 20→23 全点位（本波持改动权**已用讫**——M7-3/M7-5 接棒显式改 `McpFinalSnapshotTests.swift`，串行禁并行） |
| **红线族机检** | 双路独立电池各 9 项全 PASS：零新 SPM（Project.swift 恰一行测试登记）／既有 20 工具面零 diff（Editing/Culling/MatchColor 三 toolset 文件 diff 空；registry diff 恰 12 行 = modelUnavailable additive 两臂）／三新工具恒只读（`requiresWriter` 零命中 + `readOnlyHint: true` 恰 ×3 + writeCallCount 只在 writer 分支）／封存面 17 件零 diff／`.metal` 全域零 diff／xcstrings 三新键尾块纯插入（+30/-0）／`runModal` 零命中 + LocalizationValue 插值禁形零新增／UserDefaults 零新键／BUNDLE-MAP 恰一行（APP 17）+ tuist generate 恒末位 |
| **端到端证据** | 真 MCP 宿主协议级抽测：第一路 stdio JSON-RPC 全链亲调（tools/list 23 + EXIF 翻段链 + typed 错误面 + heldByOther 臂意外加验）+ 第二路 stdio（writer 臂）与 streamable HTTP（只读臂）双宿主独立抽测——详见 §端到端证据面；/tmp 探针即弃（fixture 已清，关键数值内联双 ACCEPTANCE） |
| **zh 对账** | xcstrings 三新键（`mcp_tool_desc_search_photos`/`_get_history`/`_get_state`）尾块纯插入 zh-only 形；zh-audit `--check` PASS（1691 source keys）+ `--self-test` PASS；UserDefaults 零新键 |
| **验收形态偏差申报** | plan 预设 `dual_acceptance = true`（第一路 PASS 后串行 omp 二验）；**omp 制度路由双 zcode 独立眼替代**（M6-2..M6-5 先例——配额阻塞替代形态，晨审可裁）；偏差①-④（翻段六规则 / truncated additive 旗标 / kind 优先序 / workspace 面 null）双路独立裁定全 PASS = 裁决边界兑现非重开；夜间全自动授权在案（先例 D-07-3-T5-1，晨审可推翻） |

## SC/AC 三列证据（ROADMAP §M7-2 三验收形态 ↔ 双路对表）

| # | 验收形态 | 第一路证据 | 第二路证据 | 判定 |
|---|---|---|---|---|
| 1 | **三工具 parity golden ✓**（对齐 GUI 同源查询结果） | §二 parity 深审：对照腿独立于工具实现路径（`referenceWalk` 直调 `LibraryQueries.searchPage`/`searchNullTail` 双查询自建 walk，不经工具 cursor 链——E-2 失明洞无复发）；NULL-key 可达断言真实（fixture 12 行含 4 unrated + 1 无 captureDate；rating ASC / captureDate DESC 两向 NULL 恒排尾亲核 FilterSQL :79-85）；`advanceMain` 翻段六规则数学验证无 gap 无重复；cursor 机制负测族过线（跨工具 token 拒/换键失效/garbage/越臂/scanEpoch 白名单外）；stdio 端到端翻段链 `[2,1]→[]→[4]` ≡ 独立 sqlite3 参照 | §二/§六/§七：翻段六规则独立数学推导（NULL 恒尾 + row-value seek 对 NULL 永假 + 尾锚手搭 `.anchor` NULL 返 nil）与实现/端到端三方一致；端到端页形 `[[1,2],[3],[4,5],[]]` segments `['main','nullTail','nullTail']` 扁平序 `[1,2,3,4,5]` ≡ 本路独立 sqlite3 参照；CLIP mock 等价性边界诚实（只替 `SemanticSearching` 协议，投影面钉死）；全文 = `AIDescriptionService.imageIDs` 直调恒等（真 seam 非 mock，更强） | **✓ 双路零分歧**——golden 非永真性双路亲读成立 |
| 2 | **tools/list 快照同批更新 ✓** | §五快照族亲核：冻结表 +3 行 / 计数断言 ×4（23）/ 三集合并 + 三对 pairwise disjoint + `Set(s)` 新域独立断言 / descriptionKeys +3 行 / makeUnionRegistry + SC7 传 fixture context / 注册源 ↔ 冻结表双向逐字节相等（程序化提取比对亲跑）/ editing(6)/culling(14) 两层零 diff | §一 ΔN 17 法独立对账 + §四两进程 HTTP `tools/list` = **23 工具全列**（「closed face identical across hosts」红线亲证）+ §八两层快照文件 diff 空 | **✓ 双路零分歧**——union 23 全点位兑现，串行波序注记保持 |
| 3 | **既有 20 工具面零回归 ✓** | §一全套独立复跑 3877/35/0 + §四 registry writer gate 亲读（writeCallCount 只在 `entry.requiresWriter` 分支）+ McpHostTests / McpEditingToolsetTests / McpCullingToolsetTests / McpProjectArbitrationTests（序列 A/B fixture）全绿零触 | §一全套独立复跑同值（2102s）+ §三锁 verdict 面与 M6-1 交互亲核（probe 读作 DATA / 只读豁免面 probe.calls==0 / apply_params 对照臂 serverReadOnly = 门真武装）+ §八 registry diff 恰 12 行 | **✓ 双路零分歧**——三路全套同值 + 零回归门双亲核 |

**REQUIREMENTS 对账**：MCP2-01..03 三行 ✅ Delivered（T6 批翻账，commit 指针在案）+ LabelQueries 勘误兑现（「复用 FilterSQL/SemanticEngine/AIDescriptionService 单源」形）——双路 §十/§十二 亲核 ✓。

## nyquist 判定

**`nyquist_compliant: true`**——采样密度充分性四依据：①**双路切入路径刻意错开**（第一路重 parity 数学深审 + stdio 端到端；第二路重五面语义审计 + 协议级端到端 + 两进程 HTTP 复现）→ 盲区结构性不重叠，第二路 4 观察项为增量非推翻；②**三路全套同值**（执行批 + 双路独立复跑，跨 23:19/00:20/00:09 三个时窗，3877/35/0 逐 bundle 稳定）→ 基线无漂移；③**端到端跨宿主三证**（套件两进程测试 + 第一路 stdio 意外加验 + 第二路独立 HTTP 脚本全链复现）→ 只读臂不在单通道假绿；④**2 minor 双路独立确认**（第二路双臂亲证 F-AC-2 端到端 `control.lock=null`）→ 缺口级结论可信。登记缺口（2 minor + 6 观察项）全部非阻塞且带处置路由（§挂账单一清单），无未申报实质偏差。

## 双眼记录

| 眼 | 载体 | 范围 | 结论 |
|---|---|---|---|
| **眼一：第一路独立验收** | `M7-2-01-ACCEPTANCE.md` | 全套独立复跑（00:20-01:15）+ parity 深审（六点）+ 真 MCP stdio 端到端抽测 + 只读三面结构性不触亲核 + 快照族亲核 + 偏差①-④裁决 + 红线 9 项亲跑 + commit 清单核对 | **PASS / 0 error + 2 minor（F-AC-1/F-AC-2 本路新产出）+ 3 观察项（F-AC-3 grid 域域外 / F-AC-4 cosmetic / F-AC-5 文档歧义）** |
| **眼二：第二路独立验收** | `M7-2-01-ACCEPTANCE-2ND.md` | 全套独立复跑（00:09-00:49，2102s）+ 五面语义审计（get_history 双地址制/kind 五臂/截断 + get_state 六字段/hop 双判据/锁 verdict + 只读臂 openReadOnly/discovery/两进程复现 + modelUnavailable 族 + 偏差①-④）+ stdio/HTTP 双宿主独立抽测 + 第一路 minor 独立复核 + 红线 9 项独立电池 | **PASS / 0 error + 0 new-minor + 2 minor 独立确认属实（处置建议一致）+ 4 观察项（N2-1..N2-4 增量）** |
| **裁断** | 双路 **零实质分歧**（全套数字 / parity 判定 / 快照族 / 只读三面 / 偏差①-④ / F-AC-1 / F-AC-2 均独立到达同一结论） | —— | 本 VALIDATION 即裁断落账载体；omp 制度路由双 zcode 独立眼替代（先例沿用），晨审可裁 |

## 端到端证据面（协议级，非套件转述）

1. **stdio 23 工具**：第一路零字节 stub `.lalb` 经真二进制 `--project` open heal（user_version=5）→ sqlite3 补行 → stdio 行协议 initialize/initialized/tools/list/tools/call 全链亲调——`tools/list` = **23 工具**，三新工具 `annotations.readOnlyHint` 全 true，`list_photos` 并存在位（双域分界成立）；`get_history` digits 臂 typed notSessionMember「pathMissing—relink」/ 不存在 id「not a row of the open library」/ pristine 面 position=-1；空 query typed invalidParams（诚实拒）；fulltext 空索引诚实空结果。第二路 writer 臂独立复测同构，另获 **CLIP 真实错误臂**（本 CLI 环境真无 bundled 资产 → typed `modelUnavailable`「bundled CLIP assets missing or failed to load」——非 mock 注入）。
2. **HTTP 两进程三证**：①套件 `testReadOnlyArmServesSearchPhotosTwoProcess`（读缝拿端口 → HTTP 亲调 search_photos + get_state heldByOther=true）；②第一路残留探针进程持锁时 server 走 heldByOther 臂 + `openReadOnly()` 降级照常服务（stdio 意外加验）；③第二路独立脚本全链复现——父进程 fcntl 持 `.lalb.lock` + 子进程 `--mcp-http --project`：connect-guidance JSON 亲收 → `mcp-endpoint-readonly.json` 亲收（真端口）+ **writer 文件全程不存在**亲证 → streamable HTTP initialize 过线（session-id 头）→ `tools/list` 23 全列 → `search_photos` over-the-wire 返回 fixture 五行 → `get_history` pristine → `get_state` project `{heldByOther: true, readOnly: true}`。
3. **翻段链独立 SQL 参照**：两路各自以 sqlite3 独立构建参照序（`ORDER BY (rating IS NULL), rating ASC, image_path ASC`），工具翻段链扁平序与参照恒等（第一路 `[2,1,4]` / 第二路 `[1,2,3,4,5]`，fixture 不同）——六规则翻段语义（空页翻段 / 满页 NULL 尾携 NULL 行 path 锚 / 短页终判）端到端亲证 **无 gap 无重复**；MCP 工具 walk 不继承 GUI grid 域 NULL 尾行缺陷（F-AC-3，双路端到端亲证不受染）。

## 挂账单一清单（六项，正本 = 本节；STATE/GOAL-STATE/TODO 同批翻账）

| # | 项 | 形态 | 触发/动作 |
|---|---|---|---|
| ① | **F-AC-1 FilterSQL `.library` 域快照未交付未申报** | 登记缺口级（不阻塞）——缓解成立：parity golden 走真 LibraryQueries 端到端序列恒等（行为覆盖强于 SQL 文本快照）+ LibraryQueries 本波零 diff | **M7-3 顺路补快照**（FilterSQLTests 同型落 `.library` 域）或 DECISIONS 追记申报（一条 commit 注记级）——二选一收口 |
| ② | **F-AC-2 headless searchState 未透传 projectWriteProbe**（`get_state.control.lock` headless 面 = null；GUI 面 = verdict 真值；双臂端到端亲证） | 登记缺口级（实现注记在产线 doc comment，DECISIONS 未以偏差名义登记） | **M7-3 顺路一行透传**（probe 闭包复用 `makeProjectWriteProbe` 产物，只读消费零红线冲突）或 DECISIONS 追记申报——二选一收口 |
| ③ | **N2-1..N2-4 第二路观察项 → M7-3 收口清单** | N2-1 = get_history **pristine 面 payload 缺 `truncated` 键**（正常面恒有 :886；pristine 分支 :833-846 十三键无此键——形状不一致无语义错）→ 补一键 `"truncated": false`（零 schema 触碰）；N2-3 = headless fulltext 闭包 `guard let store else { return [] }` 窄竞态静默空结果（与「never a silent empty result」头注纪律表层相悖；实际影响 ≈ 0）→ 统一 typed 抛一行；N2-4 = `AIWorkerClientError.requestFailed` 案无显式测试（类型级单分支已全案覆盖，语义零差异）→ 补一法两行；**N2-2 = GUI/headless 两臂 project 字段不对称（`heldByOther` 仅 headless 面）→ M7-6 SKILLS-01 文档句**（零代码）；附带三项第一路观察随批路由：F-AC-3 grid 域 NULL 尾行缺陷 → grid 域挂账（域外，M2 域修复批/走查批顺路）/ F-AC-4 union 注释「11 read」过时 → 顺路批一行注释 / F-AC-5 翻段空页 description 歧义 → M7-6 文档句 | M7-3 顺路收口（N2-1/N2-3/N2-4 合计 ≈ 四行）；N2-2/F-AC-5 随 M7-6 文档批 |
| ④ | **CLIP 10s 贴线** | 三臂 handler 均包 `McpTimeouts.list`（10s）零新档；本波零实测数据 | 万级库 vDSP 扫贴线**实测超时才申报升 20s 档**（禁静默新增档位或改既有档值——CONTEXT D-M7-2-3 红线） |
| ⑤ | **match_color provider projectDirectory 同病** | match_color 自身 provider 仍传文件 URL（其 golden 行走 absolute kind 未爆——`ImageLinker` :169-171 不消费该锚）；本波 fix `20997721` 已勘正 searchState 两装配点 | M7-4 若触 match_color 库域面**顺路勘正为目录锚**（`deletingLastPathComponent()`，WorkspaceHostView urlResolver 先例形）；本波零触其文件 |
| ⑥ | **auto 分类器后置 + cursor 跨调用稳定性边界** | auto = mode 显式三枚举不入 v1（Alcedo classifier 是 GUI 启发式单源，引入 = 新面非复用）；cursor = 与 list_photos 同口径已知边界（库重排后旧 cursor 可能跳行/漏行；不引入版本戳——先例一致） | auto 挂 M7-4+ 若立项；cursor 边界登记维持（DECISIONS §4） |

## 特殊事项

1. **fix `20997721` 闭环叙事（parity golden 门活体证明）**：E-1 修订批 provider 形在 GUI 装配沿用 match_color provider 的 `projectURL` 文件 URL 直传，但 `ImageLinker.projectRelative` 解析锚必须是**包所在目录**——T5 golden get_history digits 臂「恒 stale」抓获 → 回注 `deletingLastPathComponent()` 两装配点同批勘正 → 转绿；双路独立亲读 ImageLinker :146-176 验证修法正确性。match_color 未爆 = absolute kind 行不消费该锚（挂账⑤同病登记）。
2. **omp 制度路替代申报**：plan 预设第一路 zcode + 第二路 omp；omp 制度路由双 zcode 独立眼替代（M6-2..M6-5 同款，晨审可裁）——双路切入路径刻意错开保证独立性（§nyquist 判定①）。
3. **GUI workspace 面诚实 null（偏差④）**：`WorkspaceModel.LibraryPhaseState` per-window 形自 app 级装配点不可达（亲核 LightamerApp `focusedWorkspace` 链）——filter/selectedIDs 键保留 + null 诚实面 + `currentSessionRoot` 可达值；真值须新汇集缝（挂 M7 站后续裁量，DECISIONS §2.8 申报双路亲核）。
4. **F-6 结构纪律兑现**：SearchStateToolset 源对 WorkspaceModel/PipeCoordinator/ExportState/LibraryProjectController 零直接引用（第二路 grep 亲跑零命中）——@Observable 态全部经 liveState 闭包内 `MainActor.run` hop，测试 fixture 内 `dispatchPrecondition(.onQueue(.main))` 可执行判定钉死。
5. **快照串行波序注记保持**：本波 union 改动权 20→23 已用讫；**M7-3（list_versions 等工具）/ M7-5 接棒时继续显式改 `McpFinalSnapshotTests.swift`，串行波序，禁并行派发**（orchestrator 编排保证）。

## 留痕

- 签核正本 = 本文件；验收正本 = `M7-2-01-ACCEPTANCE.md` + `M7-2-01-ACCEPTANCE-2ND.md`（双份随本批入库）；执行正本 = `M7-2-01-{SUMMARY,DECISIONS}.md` + `M7-2-CONTEXT.md`（D-M7-2-1..9）+ `M7-2-01-{PLAN,PLAN-REVIEW}.md` + `M7-2-CHECKER.md` + `M7-2-RESEARCH.md`。
- 端到端探针 = /tmp 即弃域（两路各自 fixture 已清、残留进程零、探针脚本已清；关键数值全部内联双 ACCEPTANCE）。
- 执行链 = `9f69775b..8f12ffcc`（7 commits，未 push）；本 VALIDATION = doc-only commit；不 push。
