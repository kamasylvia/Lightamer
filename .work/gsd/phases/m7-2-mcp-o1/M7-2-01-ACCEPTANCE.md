# M7-2-01 ACCEPTANCE — 第一路独立验收（2026-10-17 夜）

> 验收身份 = zcode subagent 第一路独立验收（不轻信执行方报告，逐条实测；
> 夜间全自动授权在案）。`dual_acceptance = true`——本路 PASS 后由
> orchestrator 串行派遣 omp 二次验收（禁止并发）。
> 输入 = 修订版 PLAN + CHECKER + CONTEXT + SUMMARY + DECISIONS +
> 代码面 HEAD `8f12ffcc` 亲读 + 全套独立复跑 + 真 MCP 端到端抽测。

## 结论头

**PASS / 0 error + 2 minor + 3 观察项**——全套独立复跑逐值对账闭合
（`TOTAL|3877/35/0|` exit 0 / 零 MEMFAIL / 七 bundle 8G 门内）；parity
golden 非永真性亲读成立；三只读面结构性不触亲核成立；快照族 union 23
全点位兑现；真 MCP stdio 宿主端到端抽测亲证（tools/list 23 + EXIF 翻段
链 `[2,1]→[]→[4]` ≡ 独立 SQL 参照序）。2 minor 均不阻塞（登记缺口级，
建议 M7-3 顺路收口）。

## 一、全套独立复跑（亲跑，2026-10-17 00:20-01:15）

`caffeinate -dis Scripts/test-direct.sh --all` → **`TOTAL|3877/35/0|`
exit 0，零 MEMFAIL**——3860 基线 + ΔN 17 对账精确闭合（17 =
`McpSearchStateToolsetTests` 实测方法数）。七 bundle 逐值：

| bundle | 本验收跑 | 执行批申报 | 判定 |
|---|---|---|---|
| IOP | 687/5/0, 7588MB, 435s | 687/5/0, 7541MB | 数值同；RSS ±方差（SPIKE 注记） |
| IOPParity | 460/3/0, 7376MB, 766s | 460/3/0, 8112MB | 数值同；RSS 门内贴线 bundle，两轮均在 8G 门内 |
| Layers | 494/5/0, 809MB | 494/5/0, 808MB | 同 |
| Library | 729/4/0, 623MB | 729/4/0, 623MB | 同 |
| Sessions | 284/9/0, 1637MB | 284/9/0, 1666MB | 同 |
| Export | 379/5/0, 6531MB | 379/5/0, 6508MB | 同 |
| App | 844/4/0, 2832MB | 844/4/0, 2832MB | 同（含 17 新法 + union 23 + 两进程只读臂） |

skip 35 构成 = 5+3+5+4+9+5+4，全部既有 env/perf-probe 门，零静默吸收。
build-for-testing 新鲜度：套件实际使用 DD
`Lightamer-dgzsvdww…`（App xctest 2026-10-16 22:33，符号表含
McpSearchStateToolsetTests 12 符号；digits golden 转绿证明含 fix
`20997721`）。运行中监视全程在案（无 GUI 实例，测试宿主由脚本
ru_maxrss 机检兜底）。

## 二、parity 深审（最重项）——golden 非永真性亲读

1. **对照腿独立于工具实现路径**：`referenceWalk` 直调
   `LibraryQueries.searchPage`/`searchNullTail` 双查询自建 walk（
   `page.count==limit && anchor(of:)!=nil` 守卫形 = GUI
   `loadAllForSearch` 同构），不经工具的 `SearchCursor`/`advanceMain`；
   工具腿走完整 `registry.call` cursor 链。E-2 失明洞教训无复发——
   **非双腿共享盲区**。
2. **NULL-key 可达断言真实**：fixture 12 行含 4 unrated + 1 无
   captureDate；golden① rating ASC 断言 iso800-unrated 行经翻段可达且
   居尾 + `segments.contains("nullTail")`；golden② captureDate DESC
   断言 NULL-date 行居尾（`orderByTerm` = `(k IS NULL), k ASC|DESC`
   ——NULL 两方向恒排尾，亲核 FilterSQL.swift :79-85）+ parse→直调
   searchPage 首页恒等。
3. **单源链亲核**：`searchPage` 恒 `nullTail:false`（LibraryQueries
   :235）/ `searchNullTail` = `IS NULL` + `image_path > ?` 独立 NULL
   tier 查询（:279-286）/ `sortableKeys` 恰五键 scanEpoch 排除（:204）/
   `.anchor(of:key:)` 对 NULL 行返 nil（:89 guard → R-2 手搭尾锚的
   依据）/ 工具窄投影九字段全有 `LibraryImageRow` 列支撑 / CLIP =
   `SemanticSearching` 协议（GUI LibrarySearchModel 同源消费）/ 全文 =
   `AIDescriptionService.imageIDs` 直调恒等（真 seam 非 mock，更强）。
4. **CLIP mock 等价性边界**：mock 只替 `SemanticSearching`（GUI 同
   协议），投影面（rank/score/limit 切片）被钉死；引擎本体归 Core
   既有测试——边界诚实，与 plan §5 裁定一致。
5. **`advanceMain` 翻段规则数学验证**：`(k IS NULL), k ASC, image_path
   ASC` 下 NULL 恒尾 + 锚定 row-value seek 对 NULL 永假 → 六规则推导
   翻段**无 gap 无重复**；「全页 NULL 尾行 → 携 NULL 行 path 锚翻段」
   与 GUI `loadAllForSearch` 的 break-to-tail 形一致。golden 对照腿在
   limit=3 fixture 下 NULL 行不进主段页，两腿序列域恒等成立。
6. **cursor 机制负测族过线**：跨工具 token（无 `s` 字段，list_photos
   形 payload 亲证）typed 拒 / 换键失效 / garbage / 越臂组合（N-4）/
   scanEpoch 白名单外拒。`SearchCursor.decode` 与 PhotoProjection
   `.decodeCursor` 同形同容差（`d != "desc"`——既有形，非本批新引入）。

## 三、真 MCP 端到端抽测（独立通道，stdio JSON-RPC over wire）

fixture：零字节 stub `.lalb` 经真二进制 `--project` open heal
（user_version=5）→ sqlite3 补 4 行 → stdio 宿主起 server → 行协议
initialize/initialized/tools/list/tools/call 全链亲调：

- `tools/list` = **23 工具**，`search_photos`/`get_history`/`get_state`
  在位且 annotations.readOnlyHint 全 true；`list_photos` 并存在位
  （双域分界成立）。
- **EXIF 翻段链**：iso800 + rating ASC limit 2 → 页1 `[2,1]`
  （token segment=main）→ 页2 `[]`（token segment=nullTail——翻段
  发生）→ 页3 `[4]`（无 cursor 终止）；**扁平序 [2,1,4] ≡ 我方独立
  sqlite3 参照**（`WHERE iso=800 ORDER BY (rating IS NULL), rating ASC,
  image_path ASC`）。
- `get_state` 六字段组在位（project/server/control/workspace/editor/
  tasks）；writer 臂 heldByOther=false/readOnly=false；
  （另获一轮意外加验：早前残留探针进程持锁时，server 走 heldByOther
  臂 + `openReadOnly()` 降级照常服务 search_photos/get_state，
  heldByOther=true——**T4 只读臂真实 stdio 过线**，与套件 HTTP
  双进程测试互证。）
- `get_history` digits 臂：盘上文件缺席 → typed notSessionMember
  「pathMissing—relink」；不存在 id 999 → typed notSessionMember
  「not a row of the open library」；pristine 面 position=-1。
- 空 query → typed invalidParams（诚实拒，GUI 清过滤语义不入 MCP 面）；
  fulltext 空索引 → 诚实空结果集。
- 判定：**端到端证据补强成立**（协议级 + 数据面 + typed 错误面全通）。

## 四、只读三面结构性不触（亲核）

- registry writer gate：`writeCallCount` 只在 `entry.requiresWriter`
  分支内自增（McpToolRegistry :343-350 亲读）；三新工具注册零显式
  `requiresWriter`（grep 零命中）+ `readOnlyHint: true` 恰 ×3。
  `McpToolRegistry` diff 恰 modelUnavailable 三臂（case + code +
  message 提取），gate/计数/超时面零触。
- 行为豁免面测试亲读：`writerCheck { false }` 下三工具照常服务 +
  probe.calls==0（search/get_history）+ get_state 恰一读 probe（读作
  DATA）+ 计数零增量 + apply_params 对照臂 serverReadOnly（证明门
  真的武装）。
- `openReadOnly` 恰 heldByOther 臂一处插入（diff 逐 hunk 核）；失败 =
  nil seam + log 禁 exit；stdio EOF 腿 `try? close()` 自然覆盖；
  writer 臂/connect-guidance 双通道零 diff。
- DEBUG readonly discovery：`#if DEBUG` + `LIGHTAMER_MCP_ENDPOINT_DIR`
  双门 + 独立文件名 `mcp-endpoint-readonly.json`；Release 分支零编译；
  writer 的 `mcp-endpoint.json` 零触碰（套件断言亲证 nil）。
- EmbeddedState 第五缝（F-4①）：searchState 随 box 存取 +
  `startEmbeddedServer` on-leg 读出透传（:872-889 亲读）；N-8 宿主
  装配对账 = 四缝七调用点全传（无项目面 = 全 nil 诚实 context）。

## 五、快照族亲核

- union 显式改全点位（F-1 清单逐项）：冻结表 +3 行（名序
  get_history/get_state/search_photos）/ 计数断言 ×4（23）/ 组合代数
  三集合并 + 三对 disjoint + `Set(s)` 独立断言（新域非并入）/
  descriptionKeys +3 行 / makeUnionRegistry + SC7 startHTTPHost 传
  fixture context / 表头注释 / 测试名 Union20→Union23——全兑现。
- 三新工具 schema **注册源 ↔ 冻结表双向逐字节相等**（程序化提取比对
  亲跑）。
- editing(6)/culling(14) 两层快照文件零 diff（git diff 核）；
  McpHostTests/McpProjectArbitrationTests（序列 A/B fixture）零触。
- `McpEndpointFile` additive 六面（write/read/remove ↔ *ReadOnly 共享
  writePayload/readPayload 私有体）——既有 writer 面语义字节零改，
  禁二写纪律守住（调用点只写 info）。
- assertSnapshot 比对面 = name 集 + schema verbatim + hints（description
  只查非空）——冻结表新行 "snapshot" 占位 description 与既有机制一致。

## 六、偏差①-④裁决（DECISIONS §2 对应逐条）

1. **§2.1 翻段六规则（E-2 边界补全）**：**裁定 PASS**——数学验证
   无 gap/重复 + 与 GUI loadAllForSearch 同构 + golden 独立对照腿
   亲证；属裁决的边界兑现非重开。
2. **§2.10 `truncated` additive 旗标（F-5 之上）**：**裁定 PASS**——
   输出面 additive（非 input schema），增强 F-5「截断可检出」，零
   红线冲突。
3. **§2.11 kind 优先序（双载荷判 paste）**：**裁定 PASS**——
   D-M7-2-4 字面顺序（pasteSet→drt→film→stackSnapshot→param）+ N-5
   payload 专一性优先；是裁决的字面兑现，非偏差。
4. **§2.8 GUI workspace 面诚实 null（filter/selectedIDs）**：**裁定
   PASS**——per-window `LibraryPhaseState` 自 app 级装配点不可达属实
   （亲核 LightamerApp focusedWorkspace 链）；键保留 + null 诚实面 +
   四台账申报齐全；真值汇集缝挂账 M7 站裁量，处置得当。

**挂账移交四项**（auto 分类器后置 / cursor 跨调用稳定性 / GUI
workspace 真值汇集缝 / CLIP 10s 贴线）：DECISIONS §4 + SUMMARY +
GOAL-STATE + TODO 四处登记齐全、各带触发条件——登记质量 PASS
（另有第五条 match_color projectDirectory 语义顺路勘正挂账，同合格）。

## 七、红线族亲跑（9 项全 PASS）

1. 零新 SPM 依赖（Project.swift diff 仅测试登记一行）✓
2. 快照族显式改（本波持 union 改动权；editing/culling 两层零触）✓
3. 既有 20 工具 descriptor/handler/McpTimeouts 零 diff（Editing/
   Culling/MatchColor 三 toolset 文件 diff 空）✓
4. 三新工具恒只读（结构 + 行为双证，§四）✓
5. 封存面 17 件零 diff（HistoryStack/LightamerSidecar/DrtRecord/
   ExportQueueContract/PixelPipe/Lut3dKernels.metal/DrtEotf 等 glob
   diff 空；Core 全域 diff 空）✓
6. `*.metal` 全域零 diff ✓
7. xcstrings 三新键尾块纯插入（diff 删除行 = 0 内容行；zh-only 块形）✓
8. `.runModal(` App/Sources 零命中 + LocalizationValue 插值禁形零新增
   （唯一命中为既有注释）✓ + UserDefaults 零新键 ✓
9. Project.swift 恰一行 + BUNDLE-MAP 恰一行（APP 17）+ zh-audit
   `--check` PASS（1691 source keys）+ `--self-test` PASS ✓

## 八、独立发现（本验收新产出）

- **F-AC-1【minor｜计划项未兑现未申报】**：plan T5 action 1 末条
  「FilterSQL WHERE/bind 快照（FilterSQLTests 同型，落点 DECISIONS
  申报）」未交付且 DECISIONS 零提及（新测试文件无 SQL 断言；
  FilterSQLTests 亦无 `.library` 域覆盖）。缓解：EXIF parity golden
  走真 LibraryQueries 端到端序列恒等（行为覆盖强于 SQL 文本快照）+
  LibraryQueries 本波零 diff（SQL 面未动）。**处置建议：DECISIONS
  追记申报（一条 commit 注记级）或 M7-3 顺路补快照；不阻塞本路 PASS。**
- **F-AC-2【minor｜未申报小偏差】**：headless/只读臂的 searchState
  context 未透传既有 `projectWriteProbe`（plan T1 action 5「probe =
  既有面透传」）→ `get_state.control.lock` 在 headless 面 = null
  （GUI 面 = verdict 真值；两进程套件测试只断言 project.heldByOther，
  未暴露此差）。实现注记在产线码注释（makeHeadlessSearchState doc
  comment）但 DECISIONS 未以偏差名义登记。影响面小（agent 可从
  project.readOnly/heldByOther 部分补偿）。**处置建议：M7-3 顺路
  一行透传（probe 闭包复用 makeProjectWriteProbe 产物，只读消费零
  红线冲突）或 DECISIONS 追记申报；不阻塞。**
- **F-AC-3【observation｜域外既有 GUI 缺陷，非本波引入】**：
  `LibraryGridModel.loadNextPage`（M2-2-3 时代面）在全页 NULL 尾行
  边缘（过滤集非 NULL 行数 < pageSize 且存在 NULL 行）`mainAnchor`
  被置 nil 且 segment 滞留 `.main` → 下一页回卷重读头页 + NULL tier
  剩余行永不达（expanded 模式被 S2 去重垫底成「卡页」，collapsed/
  semantic 模式可见重复行）。MCP 工具 walk **不继承**该缺陷（翻段携
  path 锚，本验收端到端亲证正确）。**处置建议：开 grid 域独立挂账
  （M2 域修复批/走查批顺路），本波零动作。**
- **F-AC-4【cosmetic】**：union 快照测试注释「exactly 9 destructive
  tools, 11 read」过时（现 14 read）——断言本体为精确集合正确；顺路
  修一行注释。
- **F-AC-5【observation】**：MCP 翻段边界的「空页 + nextCursor」页帧
  （页2 = [] + 翻段 token）与 GUI 同页拼齐（remaining 一次填满）不同
  ——行覆盖与顺序等价（checker E-2 已裁非偏离）；工具 description
  「a short page means the end」对空页中间态略有歧义（agent 需再走一
  页至 nextCursor=null）。**处置建议：M7-6 SKILLS-01 文档批补一句；
  不改本波面。**

## 九、commit 清单核对（9f69775b..8f12ffcc，7 commits）

`9f69775b` T1 骨架+context+第三参+五缝+xcstrings → `5a89f07f` T2
三路由+modelUnavailable → `028c6230` T3 两投影 → `9efbd976` T4 只读臂
+discovery 变体 → `20997721` fix（projectDirectory 目录锚——T5 golden
抓获回注，闭环）→ `32055308` T5 测试批+union 23+登记 L041 →
`8f12ffcc` T6 收口翻账。files_modified 实际 20 件 vs 申报 15 件之差
= plan/review/checker/CONTEXT/SUMMARY/DECISIONS 六件 phase 文档 +
AGENTS/TODO/GOAL-STATE/REQUIREMENTS 四台账——全部 T6 申报范围内，
零未申报产线文件。commit message 全英文 Conventional 形，未 push
（合规）。

## 十、验收判定

- ROADMAP §M7-2 三验收形态：**parity golden ✓（§二）+ 快照同批 ✓
  （§五）+ 既有 20 工具零回归 ✓（全套 3877/35/0 + 两层快照零 diff）**。
- REQUIREMENTS MCP2-01..03 Delivered 翻账 + LabelQueries 勘误兑现
  亲核 ✓。
- **第一路独立验收 = PASS**。F-AC-1/F-AC-2 两条 minor 转交 orchestrator
  （申报级/顺路级处置，M7-3 收口窗口）；F-AC-3 转 grid 域挂账；
  F-AC-4/F-AC-5 顺路批。
- 按 `dual_acceptance = true`：本路 PASS 后由 orchestrator 串行派遣
  omp 二次验收（禁并发）；omp 结论同落本目录 ACCEPTANCE 记录。
