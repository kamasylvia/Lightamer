# M7-2-01 ACCEPTANCE-2ND — 第二路独立验收（2026-10-17 凌晨）

> 验收身份 = zcode subagent 第二路独立验收（零共享上下文，替代 omp 制度位——
> `dual_acceptance = true` 的二次验收座位；不轻信执行方与第一路，逐条实测）。
> 夜间全自动授权在案。输入 = 修订版 PLAN + CHECKER + CONTEXT + SUMMARY +
> DECISIONS + ACCEPTANCE（第一路正本，只作对照不作依据）+ 代码面 HEAD
> `8f12ffcc` 亲读 + 全套独立复跑 + 真 MCP stdio/HTTP 端到端独立抽测。
> 切入路径与第一路刻意错开：第一路重 parity 深审，本路重五面语义审计 +
> 端到端协议级复测 + 两进程只读臂独立复现。

## 结论头

**PASS / 0 error + 0 new-minor + 2 minor（第一路 F-AC-1/F-AC-2 独立确认
属实）+ 4 观察项（本路新产出）**——全套独立复跑 `TOTAL|3877/35/0|`
exit 0 / 零 MEMFAIL / 七 bundle 8G 门内（三路独立同值）；五面审计全过；
两进程只读臂经本路独立脚本全链复现（guidance → readonly discovery →
writer 文件零触 → HTTP 23 工具全列 → search/get_history 照常服务 →
heldByOther=true）；EXIF 翻段链端到端扁平序 ≡ 独立 SQL 参照。第一路
2 minor 双双独立复核属实，处置建议一致（M7-3 顺路收口）。本路 4 观察
项全部非阻塞（形状一致性/竞态窗口/测试覆盖面级）。

## 一、全套独立复跑（亲跑，2026-10-17 00:09-00:49，2102s）

`caffeinate -dis Scripts/test-direct.sh --all` → **`TOTAL|3877/35/0|`
exit 0，MEMFAIL 机检零命中**——3860 基线 + ΔN 17 精确闭合。三路对照：

| bundle | 第二路（本跑） | 第一路 | 执行批 | 判定 |
|---|---|---|---|---|
| IOP | 687/5/0, 7643MB | 687/5/0, 7588MB | 687/5/0, 7541MB | 数值同；RSS ±方差（SPIKE 注记） |
| IOPParity | 460/3/0, 8093MB | 460/3/0, 7376MB | 460/3/0, 8112MB | 同；已知贴线 bundle，三轮全 8G 门内 |
| Layers | 494/5/0, 808MB | 494/5/0, 809MB | 494/5/0, 808MB | 同 |
| Library | 729/4/0, 622MB | 729/4/0, 623MB | 729/4/0, 623MB | 同 |
| Sessions | 284/9/0, 1236MB | 284/9/0, 1637MB | 284/9/0, 1666MB | 同（RSS 波动门内） |
| Export | 379/5/0, 4868MB | 379/5/0, 6531MB | 379/5/0, 6508MB | 同（RSS 波动门内） |
| App | 844/4/0, 2832MB | 844/4/0, 2832MB | 844/4/0, 2832MB | 同（含 17 新法） |

- skip 35 构成 = 5+3+5+4+9+5+4，全部既有 env/perf-probe 门，零静默吸收。
- build-for-testing 新鲜度：DD 产物 Oct 16 22:33（执行批 T5 批 build）；
  **产物含全部终态代码的强证明 = App bundle 844/4/0 全绿**——若缺 fix
  `20997721`（library seam 目录锚），`testGetHistoryGoldenProjection`
  digits 臂必红；实测绿。运行中监视全程在案（无 GUI 实例；ru_maxrss
  机检兜底零 MEMFAIL）。
- 测试方法数独立对账：`McpSearchStateToolsetTests` 亲数 17 法 = ΔN 17 ✓。

## 二、面 1 get_history（双地址制 / kind 五臂 / 截断）

- **双地址制**：`resolveImageURL`（SearchStateToolset :951-998）=
  `libraryImageID`（全数字 → Int64，负数/空串/超宽数字落 relPath 臂）→
  digits 臂 `LibraryStore(store:).image(id:)` + `ImageLinker.resolve(
  pathKind:volumeUUID:projectDirectory:)`；else → sessionPair
  `fetchRow(relPath:)` membership 检查。与 match_color 先例形一致
  （LightamerApp :1364-1371 派生形同源）。三 kind resolve 分支亲读
  （ImageLinker :146-176）：projectRelative = **目录锚**
  `projectDirectory.appendingPathComponent(imagePath)`——fix `20997721`
  传 `deletingLastPathComponent()` 独立验证正确；match_color 未爆 =
  其行走 absolute kind（:169-171），不消费该锚——第一路论断独立成立。
  stale → typed notSessionMember（pathMissing—relink 文案）。
- **kind 五臂**：`historyKind`（:796-804）纯函数优先序 pasteSet → drt →
  film → stackSnapshot → param = CONTEXT D-M7-2-4 字面；OVERWRITE-paste
  双载荷（pasteSet+stackSnapshot 同 item）判 paste——fixture 经
  `commitPaste(records:stackSnapshot:)` 构造 + golden 断言
  `["param","structure","paste","drt","film"]` 亲读 ✓。
- **author 恒 null**：:900 硬编码 `.null` + 测试 :738 NSNull 断言；
  M7-4 前向占位契约成立。
- **limit 截断**：`suffix(limit)` 窗保留最新端（:855）+ position/
  itemCount 恒真值 + `truncated` additive 旗标（:886）；golden
  limit=2 → `["DRT tweak","Film look"]`（最新端）+ position=4/itemCount=5
  + truncated=true 亲读 ✓。
- **pristine 面**：readDocument nil → position=-1/items=[]/metadata null
  非 error（:831-848）✓。

## 三、面 2 get_state（六字段组 / hop 双判据 / 锁 verdict）

- **六字段组**：payload 恒含 project/workspace/editor/control/tasks/server
  六键（:1054-1061）——absent face = `.null`（headless 无头诚实面）。
  端到端亲证（§六）：六键全在 + workspace/editor/tasks null。
- **MainActor hop 双判据独立跑**：判据② grep亲跑
  `grep -rn "WorkspaceModel\|PipeCoordinator\|ExportState\|LibraryProjectController"
  SearchStateToolset.swift` → **零命中 PASS**（handler 只摸 context
  closure）；判据① 测试亲读（fixture liveState 闭包内
  `dispatchPrecondition(.onQueue(.main))` + 计数断言 closure 恰调一次）。
  GUI 装配点亲读（LightamerApp :1383-1518）：全部 provider 闭包
  `MainActor.run` hop 在位。
- **锁 verdict 面与 M6-1 交互**：probe 读作 control-face DATA——
  writable/held+holder 两臂 + probe nil → lock=null（:1020-1031）；
  只读豁免面测试亲读（probe.calls==0 for search/get_history + get_state
  恰 1 次读 + 计数零增量 + apply_params 对照臂 serverReadOnly——门真武装）。
  registry 写面亲读：`writeCallCount` 只在 `entry.requiresWriter` 分支
  自增（:343-350），三新工具走缺省 `requiresWriter:false` ✓。

## 四、面 3 只读臂（openReadOnly / DEBUG discovery / 两进程复现）

- **openReadOnly 亲读**（ProjectFileStore :199-224）：零 flock 获取（纯
  SQLite open）+ connection-local pragma（无 journal_mode 写腿）+ schema
  `stored == current` 双守卫（futureSchema 拒 + 旧版拒）+ readOnlyMode
  断路器 ✓。heldByOther 臂接线（McpServerController :314-337）：guidance
  → `openReadOnly()` → carrier；**失败 = log 禁 exit**（:332-337）✓；
  该臂其它 error 的 exit(1) 是 `open(role:.headless)` 失败的既有 M6-1
  语义（非本波面）。
- **DEBUG readonly discovery**：`#if DEBUG` + `LIGHTAMER_MCP_ENDPOINT_DIR`
  双门 + `writeReadOnly` 独立文件名（startReadOnlyHTTPHost :497-512）；
  McpEndpointFile additive 六面共享 writePayload/readPayload 私有体
  （既有 writer 面字节零改，禁二写纪律守住）；测试断言 writer 文件 nil。
- **两进程只读臂——本路独立复现（新证据，非套件转述）**：父进程
  fcntl 持 `.lalb.lock` + 子进程 `--mcp-http --project`（DEBUG env 门）：
  ① stdout connect-guidance JSON 亲收；② `mcp-endpoint-readonly.json`
  亲收（真端口）+ **writer 文件全程不存在**亲证；③ MCP streamable HTTP
  initialize 过线（session-id 头亲收）→ `tools/list` = **23 工具全列**
  （「closed face identical across hosts」红线亲证）；④
  `search_photos` over-the-wire 返回 fixture 五行 `[2,1,3,4,5]`
  （filename ASC 全序，含 NULL rating 行）；⑤ `get_history` over-the-wire
  返回 pristine 面（position=-1）；⑥ `get_state` project =
  `{heldByOther: true, readOnly: true}` ✓。套件双进程测试与第一路 stdio
  意外加验之外，本路补齐 **heldByOther 臂的 HTTP 过线独立第三证**。

## 五、面 4 模型依赖（modelUnavailable 族）

- **additive 15→16**：`modelUnavailable(String)` case + code switch +
  message switch 各一臂亲读（McpToolRegistry :85/:105/:117）；既有 15 值
  零扰 = 16 值穷举测试（codes 逐案 + message 恒等）+ registry diff 恰
  12 行亲核。
- **双映射**：`dimensionMismatch` → 同码 + message「semantic model
  dimension mismatch:」区分 mismatched；`SemanticSearchError.modelUnavailable`
  → 同码 +「bundled CLIP assets missing or failed to load」区分 missing
  （SearchStateToolset :657-671）。测试两向亲读 ✓。
- **AIWorkerClientError 四案归族**：实现 = 单一 `catch let error as
  AIWorkerClientError` 分支（:657-662）——**类型级归族，四案全覆盖**；
  message 携 `String(describing:)` 细节。测试显式钉 workerUnavailable
  （含「spawn failed」细节断言）/ workerCrashed / workerExhausted 三案 +
  mismatch；**requestFailed 案无显式测试**（同分支类型级覆盖，语义零
  差异）——观察项 N2-4，不阻塞。
- **既有消费方零扰**：adapter 走 `.code/.message` 通用面零改（CONTEXT
  D-M7-2-6）；`SemanticSearchError`/`AIWorkerClientError` 消费的既有
  15 值错误码穷举测试绿。
- **CLIP 10s 贴线**：三臂 handler 均包 `McpTimeouts.list`（=10s 亲读
  McpToolRegistry :212）零新档 ✓；贴线升档挂账四处登记一致。

## 六、端到端独立抽测（真二进制 stdio JSON-RPC，writer 臂）

fixture：空 SQLite stub `.lalb` → 真二进制 `--mcp-stdio --project` open
heal（user_version=5 亲证）→ sqlite3 补 5 行（3 rated + 2 unrated，
iso800）+ Media 文件 → stdio 行协议全链亲调：

- `tools/list` = **23 工具**；三新工具 `annotations.readOnlyHint=true`；
  `list_photos` 并存在位（双域分界成立）。
- **EXIF 翻段链**（iso800 + rating ASC + limit 2）：页形
  `[[1,2], [3], [4,5], []]`，segments `['main','nullTail','nullTail']`
  ——页2 = [3] 短页（anchored）→ 翻段 token；页3 = NULL tier 满页 →
  续页 token；页4 空页终止。**扁平序 [1,2,3,4,5] ≡ 本路独立 sqlite3
  参照**（`ORDER BY (rating IS NULL), rating ASC, image_path ASC`）。
  六规则翻段语义端到端亲证（E-2 边界兑现——无 gap 无重复）。
- `get_state`：六键全在；workspace/editor/tasks = null（无头诚实面）；
  project = `{path, heldByOther: false, readOnly: false}`（writer 臂）；
  **control.lock = null**（F-AC-2 亲证①——headless searchState 未透传
  probe）；server.hostMode = "stdio"。
- `get_history`：id=5（盘上无 sidecar）→ pristine 面 position=-1 +
  **`truncated` 键缺席亲证**（N2-1）；id=999 → typed notSessionMember
  「not a row of the open library」；relPath 无 session → typed
  notSessionMember「not addressable — no open session」。
- 空 query → typed invalidParams（诚实拒）；CLIP（本 CLI 环境真无资产）
  → typed **modelUnavailable**「bundled CLIP assets missing or failed
  to load」——真实错误臂亲证（非 mock 注入）。
- 残留进程零、fixture 已清、/tmp 探针脚本已清。

## 七、面 5 偏差①-④ + 挂账 + 第一路 minor 独立复核

| 项 | 本路独立结论 |
|---|---|
| 偏差① 翻段六规则（§2.1） | **PASS**——本路独立数学推导（NULL 恒尾 `(k IS NULL)` + row-value seek 对 NULL 永假〔Core :269-272 注释亲证〕+ 尾锚手搭 `.anchor` NULL 返 nil）与实现/端到端三方一致；属 E-2 边界兑现 |
| 偏差② truncated 旗标（§2.10） | **PASS**——输出面 additive（get_history inputSchema 仅 image/includeParams/limit 三键亲读），增强 F-5 可检出性 |
| 偏差③ kind 优先序（§2.11） | **PASS**——实现 :796-804 = CONTEXT D-M7-2-4 字面顺序，双载荷判 paste = payload 专一性 |
| 偏差④ workspace null（§2.8） | **PASS**——LightamerApp :1500-1510 亲读（filterSummary/selectedCount null + currentSessionRoot 可达值）+ DECISIONS §2.8 申报齐全 |
| 挂账四项 + 第五条 | 四处登记（DECISIONS §4 + SUMMARY + GOAL-STATE + TODO）亲核齐全，第五条 match_color 四处含 ✓ |
| **F-AC-1**（FilterSQL 快照未兑现未申报） | **独立确认属实**——新测试文件内 SELECT 仅 fixture 参照腿；FilterSQLTests 无 `.library` 域覆盖（grep 亲跑）。缓解成立：parity golden 走真 LibraryQueries 端到端序列恒等 + LibraryQueries 本波零 diff。维持 minor（建议 M7-3 顺路补快照或 DECISIONS 追记） |
| **F-AC-2**（headless probe 未透传） | **独立确认属实且双臂亲证**——`makeHeadlessSearchState` 不带 probe 参数（doc comment 自陈）+ 端到端两臂 `control.lock=null` 亲收（writer 臂与只读臂各一）。GUI 装配点带 probe = GUI 面有 verdict 真值。维持 minor（M7-3 一行透传顺路收口） |

## 八、红线族抽验（本路独立电池，全 PASS）

1. 零新 SPM：Project.swift diff = 恰一行测试登记（diff 全文亲读）✓
2. `*.metal` 全域零 diff ✓；Core 全域零 diff（封存面 17 件全在内）✓
3. 既有 20 工具面：EditingToolset/CullingToolset/MatchColorToolset 三
   文件 diff 空 ✓；McpToolRegistry diff 恰 12 行 = modelUnavailable
   additive 两臂 ✓
4. 三新工具恒只读：`requiresWriter` 在 SearchStateToolset 零命中（grep
   命中均为 context 字段名非注册参）+ `readOnlyHint: true` 恰 ×3
   （:189/:228/:263）+ registry 计数只在 writer 分支（:343-350）✓
5. editing(6)/culling(14) 两层快照文件 diff 空 ✓
6. xcstrings +30/-0 纯插入（numstat 亲跑）+ 三键 zh 值亲验（双域分界句
   在 zh 面）✓
7. `.runModal(` App/Sources 零命中 + SearchStateToolset 插值禁形零命中 ✓
8. Project.swift 恰一行 + BUNDLE-MAP 恰一行（APP 17）✓
9. UserDefaults 零新键（diff 无新 standard 键面；McpEndpointPaths 无
   defaults 面）✓

## 九、独立发现（本路新产出，全部非阻塞）

- **N2-1【observation｜输出形状不一致】**：get_history **pristine 面
  payload 缺 `truncated` 键**（正常面 :886 恒有；pristine 分支
  :833-846 十三键无此键）——端到端亲证（`has-truncated-key False`）。
  pristine 语义上无截断（items=[]/itemCount=0）故无语义错误，但两分支
  输出形状不一致，按「键恒在」解析的客户端拿到 missing。**处置建议：
  M7-3 顺路在 pristine 分支补 `"truncated": false` 一键（三处文件零
  schema 触碰）。**
- **N2-2【observation｜两臂 project 形状不对称】**：GUI 面 project =
  `{path, readOnly}`（:1440-1448），headless 面 project =
  `{path, heldByOther, readOnly}`（:212-216）——`heldByOther` 仅
  headless 面。各臂诚实渲染自身事实、无错误；agent 消费侧需按字段存在
  性解析。**处置建议：M7-6 SKILLS-01 文档批一句注记，零代码动作。**
- **N2-3【observation｜headless fulltext 竞态空结果】**：headless
  fulltext 闭包 `guard let store else { return [] }`（:204-208）——
  EOF close 后的窄竞态窗口返回静默空结果，与 SearchStateToolset 头注
  「never a silent empty result」的表层纪律相悖；GUI 臂同缝是 throw
  notSessionMember（:1415-1424）。实际影响≈零（close 后进程即 exit(0)；
  正常路径 library gate 先行）。**处置建议：M7-3 顺路统一为 typed
  抛（一行），或保持现状注记即可——不阻塞。**
- **N2-4【observation｜requestFailed 案无显式测试】**：AIWorkerClientError
  四案归族为类型级单分支（全案覆盖），测试显式钉三案 + mismatch；
  requestFailed 无独立断言。分支级覆盖已完整、语义零差异。**处置建议：
  M7-3 顺路补一法（两行），或接受分支级覆盖为足——不阻塞。**
- 另复核第一路 F-AC-4（union 快照注释「11 read」过时）：确认属实
  （:216 上下文行亲读；断言本体 = destructive 9 精确集合，正确）——
  cosmetic 顺路批。F-AC-3（grid 域 NULL 尾行缺陷）域外挂账，本波零
  动作正确（MCP walk 携 path 锚不受染，本路端到端亲证）。

## 十、commit 清单核对（9f69775b..8f12ffcc，6 commits + 收口）

`9f69775b` T1 → `5a89f07f` T2 → `028c6230` T3 → `9efbd976` T4 →
`20997721` fix（目录锚勘正——本路 ImageLinker 亲读独立验证正确性）→
`32055308` T5 → `8f12ffcc` T6 收口。产线文件 10 件 + phase 文档 6 件 +
台账 4 件，与 plan files_modified 对账一致（第二路独立 diff --name-only
核对：无清单外产线文件）。commit message 全英文 Conventional 形；未
push（合规）。

## 十一、分歧与一致性

与第一路结论**零分歧**：全套数字、parity 判定、快照族、只读三面、
偏差①-④、F-AC-1/F-AC-2 均独立到达同一结论（切入路径不同：本路重
五面语义 + 协议级端到端 + 两进程 HTTP 复现；第一路重 parity 数学 +
stdio 端到端）。本路新产出 4 观察项（N2-1..N2-4）为增量，非推翻。

## 十二、验收判定

- ROADMAP §M7-2 三验收形态：**parity golden ✓（端到端翻段链 ≡ 独立
  SQL 参照 + golden 套件绿）+ 快照同批 ✓（union 23 全点位 + 两层零
  diff）+ 既有 20 工具零回归 ✓（全套 3877/35/0 三路同值 + 零回归门）**。
- **第二路独立验收 = PASS**（0 error；2 minor 均为第一路同项独立确认，
  非本路新增；4 观察项全非阻塞）。
- 处置汇总转 orchestrator：F-AC-1/F-AC-2 + N2-1/N2-3/N2-4 → M7-3 顺路
  收口窗口；N2-2 + F-AC-5 → M7-6 SKILLS-01 文档批；F-AC-3 → grid 域
  挂账；F-AC-4 → 顺路批一行注释。
- M7-3 接棒注意：union 快照改动权移交（McpFinalSnapshotTests.swift
  串行显式改纪律不变）。
