---
phase: m7-2-mcp-o1
plan: "M7-2-01"
title: "MCP O1 检索与状态读单 plan——T1 SearchStateToolset 骨架 + McpSearchStateContext provider 面 + makeRegistry 第三参数装配（三工具注册，全只读 requiresWriter:false + readOnlyHint） / T2 search_photos 三路由（EXIF keyset / CLIP top-K / 全文 bm25）+ McpToolError.modelUnavailable additive 15→16 / T3 get_history（readDocument→HistoryStack 只读投影 + versions meta + includeParams）+ get_state（六字段面 + MainActor hop + 锁 verdict） / T4 无头只读臂 openReadOnly()（schema 守卫 + 写断路器 + connect-guidance 零 diff） / T5 测试批（parity golden 三臂对齐 GUI 同源 + tools/list 快照 union 20→23 显式改 + 既有 20 工具零回归 + McpToolError 16 值穷举 + 单写者锁只读豁免面） / T6 定向轮 + 全套 --all（批准制 + 8G 门）+ 收口翻账"
wave: 1
depends_on: []
autonomous: true
requirements: ["REQUIREMENTS MCP2-01..03（:431-433，→ M7-2）+ ROADMAP §M7-2 行（验收形态三条：parity golden / 快照同批 / 既有 20 工具零回归）", "OQ 裁决正本 = phases/m7-2-mcp-o1/M7-2-CONTEXT.md（D-M7-2-1..9 全按 RESEARCH §6 推荐，站 charter 授权落定，晨审可推翻）", "调研正本 = phases/m7-2-mcp-o1/M7-2-RESEARCH.md（§2 现状测绘 / §3 三工具语义 / §4 集成缝 / §5 测试策略）", "夜间全自动授权在案（先例 D-07-3-T5-1；晨审可推翻）"]
success_criteria: "SC 全可机检——T1：makeRegistry 缺第三参（缺省 nil）= 20 descriptor 逐字节零 diff 负测 + 第三参装配 = 恰 3 新工具注册且全 requiresWriter:false / readOnlyHint:true 断言 + 宿主装配点对账 grep 机检在位（六调用点 / 四缝 + EmbeddedState 内部缝——N-8 清单，F-4①第五缝含 startEmbeddedServer）；T2：parity golden 三臂恒等——EXIF 臂工具输出 id 集与序 ≡ GUI 同源两段走法（直调 searchPage 主段 + searchNullTail NULL 尾段拼接，同 sort/anchor，同 fixture .lalb；fixture 必含 NULL-key 行〔unrated / 无 captureDate〕且断言工具可达——E-2 失明洞修补；cursor token 携 segment 字段）+ ExifSearchParser.parse plan 恒等断言（工具与 GUI 共用 parse 的结构性保证）/ CLIP 臂 mock SemanticSearching 注入下 hit 序与 score 投影恒等（CI 零模型资产）/ 全文臂工具输出 ≡ 直调 AIDescriptionService.imageIDs（rank 序恒等）+ typed 错误臂五件（空 query=invalidParams / 解析错 token=invalidParams / 无开项目=notSessionMember / SemanticSearchError→modelUnavailable / AIWorkerClientError 四案→modelUnavailable message 携 worker 细节〔F-3〕）+ 越臂组合（clip|fulltext 带 cursor/sort）typed 拒负测〔N-4〕+ description 双域分界句（library vs session）在 schema 快照内；T3：get_history golden byte-equal（fixture sidecar 五种 kind item + 双载荷项一例〔N-5〕+ versions 三条 + note/keywords）+ includeParams 两档断言 + limit >帽 截断保留最新端断言〔F-5〕+ position=-1 pristine 面 + kind 判别五臂纯函数 + author 恒 null 负测 + get_state 六字段面（无项目 typed nulls 契约 + 每字段至少一活一空臂 + MainActor hop 机检双判据〔fixture liveState 闭包 dispatchPrecondition 主线程断言 + grep SearchStateToolset 源 @Observable 类型名零直接引用——F-6〕）；T4：双进程锁 fixture 下只读臂 search_photos 照常服务（F-2 甲：DEBUG 门控只读 face 写独立文件名 per-test discovery〔LIGHTAMER_MCP_ENDPOINT_DIR 域，Release 零触〕测试经同族读缝拿端口——registry 级降格备选注记在案，McpHostTests 先例复用）+ withWriteBatch 断路器 typed 拒不破 + connect-guidance 序列 A/B 零 diff 绿 + 只读臂零 flock 获取（openReadOnly 锁免语义）；T5：域快照新层（3 工具 name/description/schema verbatim + 计数 23）+ union 快照显式改 20→23（冻结表 +3 行 + 计数断言 ×4 + 组合代数断言三集合并 + descriptionKeys +3 行对账 + makeUnionRegistry/SC7 startHTTPHost 传 fixture context + 表头注释 + 测试名 Union20→Union23，M5-1-03 先例形——F-1 全点位）+ 既有 editing(6)/culling(14) 两层快照零 diff + McpToolError 16 值穷举（code 字符串逐案断言）+ 只读工具 writeCallCount 零计与 writerCheck:false 不拒断言 + --bundle APP 全绿；T6：--bundle APP 定向轮绿 + 全套 --all = TOTAL|3860+ΔN/35/0| 对账精确闭合（exit 0 / 0 MEMFAIL / 七 bundle 8G 门内）+ 红线族逐条机检 PASS + zh-audit --check PASS"
estimated_tests: "+12..20（T5 批承载：parity golden 三臂 ~6..8 + get_history/get_state golden ~4..6 + 域快照 ~2 + 注册零 diff/计数负测 ~2 + 错误码穷举/锁豁免 ~2..3；T1-T4 产线码零新测试——机检判据为构建绿 + grep 结构核；执行时逐任务如实记账，越带申报）"
test_bundles: [APP]
baseline: "3860/35/0（FIX2 终态三路同值；M7-1 定罪批 ΔN=0 逐值维持；HEAD d08306fd = research docs commit，其上零产线文件——基线未漂移，planner 2026-10-16 亲核 git log/status）"
expected_all: "3860 + ΔN（对账式；ΔN 预期带 +12..20，执行时按实记账；skip 35 口径维持——第三种 skip 来源 = 逐族差分申报禁静默吸收）"
red_lines:
  - "零新 SPM 依赖（Project.swift dependencies 块零 diff）"
  - "MCP 快照族 additive 显式改（D-14-CONTEXT-3 机制内）——本波持 union 文件（McpFinalSnapshotTests.swift）改动权，M7-3/M7-5 串行在后（orchestrator 编排保证不并行派发）；editing(6) 层 McpRegistrySnapshotTests / culling(14) 层 McpCullingToolsetTests 两快照文件零触；快照改动全部走「显式改 + DECISIONS 申报」形，禁静默"
  - "工具面 additive——既有 20 工具 descriptor/handler/McpTimeouts 零 diff（CLIP 贴线需升 20s 档 = DECISIONS 申报，禁静默改档或新增档）"
  - "三新工具恒只读：requiresWriter:false（注册缺省值）+ readOnlyHint:true——writer gate / writeCallCount 计数 / projectWriteProbe 写面消费三面结构性不触（registry :333 requiresWriter 分支结构保证）；get_state 对 writeCallCount/projectWriteProbe 只读引用（server/control 快照面），零写路径（sidecar 写面 / withWriteBatch / 库写腿零触；openReadOnly 只读臂零 flock 获取）"
  - "Alcedo GPL 代码/文档文案零复制零翻译——工具名/参数/schema 全部自写（snake_case MCP 与点分 JSON-RPC 天然异构），只对表命令语义"
  - "封存面零触：DrtRecord / TerminalTailPolicy / DrtTailAssembly / PixelPipe / Lut3dKernels.metal / DrtEotf / ExportQueueContract / 六格式导出矩阵（ExportFormatSpec·ImageIOEncoders·WebPEncoder）/ NodeGraphCommand / sidecar schema（LightamerSidecar）/ HistoryStack / HistoryHash / PipelineDocument（Core）/ V50Order / GradeCatalog（NodeOwnershipCatalog）/ Registry / ModuleInstance——get_history 是 HistoryStack/HistoryItem 只读投影，类型与 CodingKeys 零改"
  - "零新 .metal（全域零 diff）"
  - "xcstrings = 三新键 mcp_tool_desc_search_photos / _get_history / _get_state 尾块纯插入（历史键字节与顺序零触碰）；执行中如需更多键 = 同纪律 + DECISIONS 申报；UserDefaults 零新键"
  - "\\.runModal( 在 App/Sources 零命中（L057 禁令）；LocalizationValue 插值禁形代码零命中（新描述键一律 String(localized: 静态键, defaultValue:) 显式形态——禁 String.LocalizationValue(\"prefix_\\(x)\" 插值形，M2-9 F-2 禁令）"
  - "Project.swift 恰一行测试登记 + BUNDLE-MAP 恰一行（APP 域）+ tuist generate 恒为该批最后一个动作（L041）"
  - "构建 caffeinate -dis 包裹；单测 = Scripts/test-direct.sh --bundle APP；全套 --all orchestrator 批准制（本 plan 标注批准制，执行时 orchestrator 派发 prompt 即批准）+ 8G 门 + MEMFAIL 机检 + 运行中保持监视（AGENTS 资源监控节）；测试宿主清理先核 parentage（ps -o ppid，M2-7-3 先例）"
files_modified:
  - App/Sources/Lightamer/MCP/Tools/SearchStateToolset.swift   # T1-T3 新建：McpSearchStateContext（全 provider closure，optional 缝缺省 nil；library provider = ProjectFileStore + projectDirectory——E-1 修法甲，LibraryStore 按需公开 init 派生）+ 三工具 registerAll（search_photos/get_history/get_state，readOnlyHint:true）+ kind 判别纯函数 + EXIF 窄投影两段走法/CLIP/全文三路由 + 双地址制解析（digits→LibraryStore.image+ImageLinker / relPath→sessionPair）
  - App/Sources/Lightamer/MCP/McpToolRegistry.swift            # T2：McpToolError additive modelUnavailable(String)（code/message 两 switch 补臂，15→16）；registry 其余零改
  - App/Sources/Lightamer/MCP/McpServerController.swift        # T1：makeRegistry 第三参数 searchState:（缺省 nil）+ startHTTPHost/startHeadlessStdioHost/startReadOnlyHTTPHost/startEmbeddedIfPreferenceEnabled 四缝 additive 参数透传 + EmbeddedState box searchState 字段（startEmbeddedServer on-leg 同路透传——F-4① 第五缝）+ 无头臂 headless searchState 装配（library seam = headlessProjectStore 直携）；T4：runHeadlessArbitrated heldByOther 臂 emitConnectGuidance 后 openReadOnly()（失败 = nil seam + log 降级，禁 exit）+ 只读 http face DEBUG 门控独立文件名 per-test discovery（F-2 甲，Release 零触）——connect-guidance 双通道与 stdio EOF 腿零改
  - App/Sources/Lightamer/MCP/McpEndpointFile.swift            # T4：discovery 写读 additive 变体（writeReadOnly/readReadOnly 或 paths 变体——独立文件名 mcp-endpoint-readonly.json；既有 write/read 与 mcp-endpoint.json 语义零改——R-1，checker 批补申报；禁在 McpServerController 内二写 discovery 逻辑）
  - App/Sources/Lightamer/UI/LightamerApp.swift                # T1：GUI 装配点（:1331-1374 同段）构造 McpSearchStateContext（library/sessionPair/semanticStore/semantic/fulltext/liveState/projectWriteProbe——@Observable 态全部闭包内 MainActor.run hop）传 startEmbeddedIfPreferenceEnabled
  - Resources/Localizable.xcstrings                            # T1：三新键尾块纯插入（描述文案 = 三工具语义边界，search_photos 含 library-vs-session 双域分界句）
  - Tests/LightamerTests/McpSearchStateToolsetTests.swift      # T5 新建：域快照层（3 工具 verbatim + 计数 23）+ parity golden 三臂 + get_history/get_state golden + typed 错误臂 + McpToolError 16 值穷举 + 只读豁免面（writeCallCount 零计 / writerCheck:false 不拒 / probe 不触）
  - Tests/LightamerTests/McpFinalSnapshotTests.swift           # T5：union 显式改 20→23（冻结表 +3 行〔名序 get_history/get_state/search_photos——descriptors() 名序〕+ 计数断言 :174/:202/:230/:373 + 组合代数 :200 三集合并 + descriptionKeys :237-259 +3 行与 :274 对账 + makeUnionRegistry :159 传 fixture context + SC7 startHTTPHost :363 传 fixture context + 表头注释 :22-27/:226 + 测试名 Union20→Union23，M5-1-03 先例形——F-1 全点位）
  - Project.swift                                              # T5：恰一行测试登记（McpSearchStateToolsetTests.swift → LightamerTestsApp 数组；tuist generate 恒末位）
  - .work/gsd/phases/m2-4-0-test-bundles/M2-4-0-BUNDLE-MAP.txt # T5：McpSearchStateToolsetTests.swift 增行（APP 域）
  - .work/gsd/phases/m7-2-mcp-o1/M7-2-01-SUMMARY.md            # T6：执行摘要（逐任务 ΔN 记账 + parity golden 判定指针 + 快照显式改申报 + auto 后置挂账登记）
  - .work/gsd/phases/m7-2-mcp-o1/M7-2-01-DECISIONS.md          # T6：裁定记录（context provider 终形 / 窄投影列映射终值〔images 表实存列核对〕/ CLIP 超时档裁定〔10s 维持或 20s 申报〕/ 只读臂降级形 / 只读臂端口判据通道终形〔F-2 甲/乙〕/ worker 族映射终形〔F-3〕/ 快照显式改申报）
  - AGENTS.md                                                  # T6：「M7-2 架构增量」节（三工具语义 + context seam 形 + modelUnavailable 错误码 + 只读臂 openReadOnly 形 + ΔN 终值）
  - .work/TODO.md                                              # T6：M7-2 条目翻账（auto 分类器后置挂账 + cursor 跨调用稳定性已知边界登记）
  - .work/GOAL-STATE.md                                        # T6：续接点翻新（M7-2 收口 → next = M7-3〔MCP 快照面串行接棒〕）
  - .work/gsd/REQUIREMENTS.md                                  # T6：MCP2-01..03 翻账（Delivered + M7-2 commit 指针）+ MCP2-01 行 LabelQueries→AIDescriptionService 勘误（CONTEXT 勘误注记兑现）
---

# Plan M7-2-01 — MCP O1 检索与状态读（三工具 additive + 快照同批 + parity golden）

## 评审修订记录（M7-2-01-PLAN-REVIEW，2026-10-16 fixer 批）

> 修订正本输入 = `M7-2-01-PLAN-REVIEW.md`（E-1/E-2 两 error + F-1..F-6
> 六 minor + N-1..N-8 八注记，file:line 证据全亲核复核）。落位一览：
>
> - **E-1（error，修法甲择定）**：`McpSearchStateContext.library` provider
>   形改携 **ProjectFileStore**——`(store: ProjectFileStore,
>   projectDirectory: URL)?`（三路由单源 `LibraryQueries` /
>   `SemanticStore` / `AIDescriptionService.imageIDs` 全吃
>   ProjectFileStore，亲核三 init 签名成立）；`LibraryStore` 需要处
>   （get_history digits 臂 `LibraryStore.image(id:)`）由 toolset 用公开
>   `LibraryStore(store:)` init 现场派生——GUI 装配点 LightamerApp
>   :1362-1371 match_color provider 已演示派生形。**不加 LibraryStore
>   accessor**（零 Core diff；files_modified 清单经核对无涉——修订是
>   plan/CONTEXT 文本级）。CONTEXT D-M7-2-9 provider 清单同步改写。
> - **E-2（error，修法甲择定）**：EXIF 臂改**两段走法**（GUI 同源
>   LibraryGridModel :5-13/:88-91）——`searchPage` 主段（恒
>   nullTail:false，亲核 :231-236）耗尽 → cursor token 翻 `segment =
>   nullTail`（anchor=nil）走 `searchNullTail` NULL tier（:239-256）；
>   cursor token（PhotoProjection.Cursor 同形）加 `segment` 字段。parity
>   golden 对照腿同步改两段拼接（单段对照 = 双腿同盲禁用）+ fixture 必含
>   NULL-key 行（unrated / 无 captureDate）可达断言。**乙（v1 只服主段
>   显式降级裁决）不采**——按 plan 自述无用户裁决分支 + C 档门控停等
>   成本，两段走法是 GUI 同源正形。
> - **F-1**：union 快照显式改点位补全——四处计数断言之外 + 组合代数
>   断言（:200 `Set(u) == Set(e).union(Set(c))` 改三集合并——三新工具
>   入新域非并入既有域）+ `descriptionKeys` 映射表 +3 行与 :274 对账
>   断言 + `makeUnionRegistry`（:159-160）传 fixture searchState context
>   + SC7 `startHTTPHost`（:363）传 fixture context + 表头注释
>   （:22-27/:226）+ 测试名 Union20→Union23。
> - **F-2（甲择定）**：T4「只读臂 search_photos 照常服务」SC 判据通道 =
>   DEBUG 门控下只读 http face 也写 discovery 文件——
>   `LIGHTAMER_MCP_ENDPOINT_DIR` per-test 域内（:115-124
>   headlessEndpointPaths 同款 `#if DEBUG` 门形），**独立文件名**
>   （`mcp-endpoint-readonly.json`）不覆 writer 的 `mcp-endpoint.json`
>   （guidance 真相源零触碰）；Release 路径零触；测试经
>   `McpEndpointFile` 同族读缝拿端口。registry 级降格（乙）注记为
>   DECISIONS 申报降级路径；stderr 刮端口（丙）不采。
> - **F-3**：CLIP 腿 typed 错误臂补第四族——`AIWorkerClientError` 四案
>   （workerUnavailable / workerCrashed / workerExhausted / requestFailed，
>   亲核 AIWorkerClient.swift :31-43）→ **归 `modelUnavailable` 族**
>   （「语义运行时对本查询不可用」语义——与 D-M7-2-6「语义诚实优于
>   错误码数量最小化」裁定同构；`internalError` 会把资产/进程缺席
>   误导成我方 bug，排障语义错位），message 携 worker 案名与细节；
>   T5 补 worker 族映射一法（mock searcher 抛 workerUnavailable →
>   断言 modelUnavailable 码）。D-M7-2-6 同批补注记（映射规则延伸，
>   非裁决重开）。
> - **F-4**：①EmbeddedState **第五缝**钉进 T1——searchState 随 box
>   存取（`startEmbeddedIfPreferenceEnabled` 存 / `startEmbeddedServer`
>   on-leg 读出再传 `startHTTPHost` 同路透传，亲核 :721-750），缺 =
>   GUI 先关后开 MCP 三工具静默缺席；grep 机检点位含
>   startEmbeddedServer。②T1 action 5「probe/writeCallCount = 既有面
>   透传」修形——probe = 既有面透传；writeCallCount = GUI embedded 走
>   `embeddedWriteCallCount()` 同源（:585-588），headless / 只读 face
>   无 handle 外露面 = **null 诚实面**（server 字段缺席语义），不立项
>   新 plumbing（无消费者）。
> - **F-5**：get_history `limit` 语义一句话钉死——**默认 =
>   min(全量, 500)；截断保留最新端（position 侧，有效历史优先）；
>   itemCount 恒真值总数**（可检出截断）。T5 golden 补 >帽 截断方向
>   断言。CONTEXT D-M7-2-4 同步。
> - **F-6**：MainActor hop 改**机检双判据**——①fixture `liveState`
>   闭包体内 `dispatchPrecondition(condition: .onQueue(.main))` +
>   调用计数，get_state 断言「闭包被调且在主线程」；②grep 机检：
>   SearchStateToolset.swift 源对 WorkspaceModel / PipeCoordinator /
>   ExportState / LibraryProjectController 类型名零直接引用（handler
>   只摸 context closure）。
> - **N-2**：search_photos description 注明无状态语义（"each call
>   evaluates the query against the full library (no layered session
>   filter state)"）——落 T2 action 2。
> - **N-3**：schema 显式钉默认 sort = `{key: "filename", ascending:
>   true}`（GUI 同源 LibraryGridModel :97）——落 T2 action 1。
> - **N-4**：cursor/sort 越臂组合（mode=clip|fulltext 携 cursor/sort）
>   typed 拒入 T2 schema + T5 负测；EXIF token 嵌 sort 键+方向
>   （PhotoProjection.Cursor 同形）白拿换键失效负测。
> - **N-5**：T5 golden fixture 五种 item 外加一例双载荷项
>   （pasteSet+stackSnapshot 并存 → 归 paste 先序显式断言）。
> - **N-6**：imagePath path-kind 相对语义注明（T2 description 一句）；
>   窄投影九字段列支撑 / metadata 取数源 / versions meta 亲核 ✓
>   （「无列支撑字段如实缺席」条款大概率零行使）。
> - **N-7**：只读 store `close()` 的 `checkpointTruncate` 语义（writer
>   持 WAL 时 typed 失败 + stdio EOF `try?` 吞 + 进程退出兜底）作 T4
>   知悉注记——既有 GUI openProjectReadOnly 路径同语义，非本波新增面。
> - **N-8**：宿主装配点对账形改「六调用点 / 四缝 + EmbeddedState 内部
>   缝」——front-matter SC + T1 AC 措辞同步。
> - **N-1**（基线与开关亲核 ✓）：零修订；plan 自述 HEAD `d08306fd` 为
>   撰写时点，评审批亲核两跳 docs-only 基线未漂移。
>
> 修订性质 = plan/CONTEXT 文本级 + 测试点位清单级——**不动任务序
> （T1-T6）、波次、九裁决归属、files_modified 骨架与量级带**。
> E-1/E-2 为实现细节级行使（V2M E-2 / F1 家族先例形），属 plan 修订
> 非裁决重开。

> **夜间全自动授权**（先例 D-07-3-T5-1；晨审可推翻）。裁决正本 =
> `M7-2-CONTEXT.md`（D-M7-2-1..9 全按 RESEARCH §6 推荐——站 charter 授权
> 落定）；规格正本 = `M7-2-RESEARCH.md`（§2 现状测绘 / §3 三工具语义 /
> §4 集成缝 / §5 测试策略；file:line 均 HEAD `d08306fd` 亲核）。
>
> **裁定权归属钉**：本 plan 无用户裁决分支（三工具全只读、零有损形、
> 零行为变更面——pristine 档与既有 20 工具面逐字节不变由 T5 快照零 diff
> 门钉死）。执行中如触「必须写面」（任何 requiresWriter/写路径诱惑）
> = 停手上报，不得自裁扩界。
>
> **执行序**：T1 → T2 → T3 → T4 → T5 → T6。T1-T4 产线码（每任务独立
> commit + 构建绿机检），T5 测试批一次落位（orchestrator 指定分批——
> 测试集中在码面稳定后落位，风险面见「风险与回退」第 1 条），T6 轮次
> + 收口。每任务独立 commit（Conventional Commits，全英文，只 add
> 相关文件，不 push）。
>
> **基线**：**3860/35/0**（FIX2 终态三路同值 + M7-1 定罪批逐值维持；
> HEAD `d08306fd`，其上零产线文件）。全套预期 `3860+ΔN/35/0|`（ΔN
> 预期带 +12..20，对账式）。

## 已定裁决（生效值，硬约束，不得重开）

OQ-M7-2-1..9 **全部按 RESEARCH §6 推荐裁**（CONTEXT D-M7-2-1..9）。本单
plan 承载全部九项；执行面速查：

1. **主域 = 库域**（open `.lalb`）；`search_photos` 纯库域 keyset、
   `get_history` 双地址制（digits 库 id | open-session relPath）、
   `get_state` project 面随装配态。description 双域分界句必带。
2. **mode = `exif|clip|fulltext` 显式三枚举，默认 `exif`**；auto 后置挂账。
3. **EXIF keyset cursor（两段：main→nullTail，token 携 `segment` 字段——
   E-2 修订）+ 窄投影九字段；CLIP top-K 帽 256；全文 top-K 帽
   500**；缩略图走 `get_thumbnails` 不内嵌；超时复用 `McpTimeouts.list`（10s）。
4. **get_history = summary + `includeParams`**（默认 false）；author 前向
   占位 v1 恒 null；kind 判别五臂纯函数（paste/drt/film/structure/param）。
5. **versions 只 meta**（id/name/createdAt/updatedAt/active）+ activeVersionID；
   完整链归 M7-3 `list_versions`。
6. **`McpToolError.modelUnavailable` additive 15→16**；`modelUnavailable`
   与 `dimensionMismatch` 双映射（message 区分 missing/mismatched）；
   `AIWorkerClientError` 四案同归该族（message 携 worker 细节——F-3
   映射规则延伸，非裁决重开）。
7. **无头只读臂 `openReadOnly()` 服务读面**（锁免 / schema 守卫 / 写断路器
   原样）；失败 = nil seam 降级 + log，禁 exit。
8. **get_state 六字段组** = project/workspace/editor/control/tasks/server；
   tasks 面 = M2 导出队列计数；merge/pano/AI-worker 不入 v1。
9. **库 seam = 新 context 自带 provider**（closure 形）；match_color
   static box 不复用。

## read_first（全局，每任务开工前过一遍）

- `.work/gsd/phases/m7-2-mcp-o1/M7-2-CONTEXT.md`（D-M7-2-1..9 裁决 + 红线摘要）
- `.work/gsd/phases/m7-2-mcp-o1/M7-2-RESEARCH.md` §2（registry/宿主/快照族
  现状）+ §3（三工具语义与 GUI 同源链）+ §4（集成缝 file:line）+ §5（测试
  策略）+ §8（风险与边界）
- `.work/config.toml [gsd]` paused/auto 开关（开工前亲核）
- `.work/LESSONS.md` L041（tuist generate 恒末位）/ L013（StableHash 纪律
  ——cursor token 序列化如触哈希面则 FNV-1a）+ CONVENTIONS「新测试文件落域
  规则」（Project.swift 显式清单 + BUNDLE-MAP + tuist generate 恒末位）
- `App/Sources/Lightamer/MCP/McpToolRegistry.swift`（:61-111 McpToolError
  封闭表 / :276-345 register/call/writer gate / :198-216 McpTimeouts）
- `App/Sources/Lightamer/MCP/McpServerController.swift`（:242-345
  runHeadlessArbitrated 双臂 / :376-470 只读 http face + stdio host +
  makeRegistry / :571-588 writeCallCount 面）
- `App/Sources/Lightamer/Library/LibrarySearchModel.swift`（:100-244 三腿
  provider 形与 provider 接线正本——McpSearchStateContext 闭包签名同源）

---

## T1 — SearchStateToolset 骨架 + McpSearchStateContext + registry 第三参数装配

> **additive 唯一缝（RESEARCH §4.1）**：`makeRegistry(editing:culling:)`
> 追加第三参数 `searchState: McpSearchStateContext? = nil`——缺省 nil =
> 既有调用与全部既有测试零 diff；宿主活装配点全部传 context（「closed
> face identical across hosts」纪律——只读宿主同样列出全 23 工具，数据面
> 缺席 = typed 错误诚实臂，非工具缺席）。

**read_first**：`M7-2-RESEARCH.md` §4.1/§4.2（注册缝 + GUI 装配点）；
`McpServerController.swift` :456-468（makeRegistry）+ :203-206（无项目
http 路径）+ :299-323（headless writer http 臂）+ :376-409（只读 http
face + stdio host）+ :571-588（writeCallCount /
embeddedWriteCallCount）+ :721-750（EmbeddedState box +
startEmbeddedServer on-leg——F-4① 第五缝正本）；`LibrarySearchModel.swift`
:100-146（provider 三件形）；`MatchColorToolset.swift` :90-115（static box
——**不复用**，对照面）；`EditingToolset.swift` :60-110（Seams struct 体例）。

- **action**：
  1. **context struct**：新建
     `App/Sources/Lightamer/MCP/Tools/SearchStateToolset.swift`——
     `McpSearchStateContext: Sendable`，全 provider closure 注入（CONTEXT
     D-M7-2-9 清单）：`library`（**`(store: ProjectFileStore,
     projectDirectory: URL)?`——E-1 修法甲：三路由单源 `LibraryQueries` /
     `SemanticStore` / `AIDescriptionService.imageIDs` 全吃
     ProjectFileStore，provider 直携；`LibraryStore` 需要处（get_history
     digits 臂 `LibraryStore.image(id:)`）由 toolset 用公开
     `LibraryStore(store:)` init 现场派生——GUI 装配点 LightamerApp
     :1362-1371 match_color provider 已演示派生形；不加 LibraryStore
     accessor（零 Core diff））/ `sessionPair`（get_history relPath
     臂）/ `semanticStore` / `semantic` / `fulltext`
     （`AIDescriptionService.imageIDs` 查询缝，
     LibrarySearchModel fulltextProvider 同形）/ `liveState`（get_state
     workspace/editor/tasks 快照载体，闭包内 MainActor hop）/ `projectWriteProbe`
     （control 面，复用既有 probe 形）/ `writeCallCount`（server 面，
     F-4② 终形见 action 5）。
     optional 缝缺省 nil = 既有构造零 diff + typed 诚实错误臂
     （notSessionMember / modelUnavailable / null 字段）。
  2. **三工具注册**：`McpSearchStateToolset.registerAll(on:context:)`——
     `search_photos` / `get_history` / `get_state`，全
     `requiresWriter: false`（注册缺省值，不显式传）+ `readOnlyHint: true`
     （list_photos 只读工具惯例形，CullingToolset :267）。descriptor 三件
     本任务先落 name + description（`String(localized: "mcp_tool_desc_<tool>",
     defaultValue: String.LocalizationValue(<verbatim english>))` 显式形态）
     + 最小 inputSchemaJSON 骨架（schema 终式随 T2/T3 各自任务补全——本任务
     先通装配）；`search_photos` description **必含双域分界句**（"queries
     the OPEN LIBRARY (.lalb) — `list_photos` addresses the open session
     instead"，D-M7-2-1）。
  3. **registry 第三参数**：`makeRegistry` 追加
     `searchState: McpSearchStateContext? = nil`——非 nil 时
     `await McpSearchStateToolset.registerAll(on:context:)`；四宿主缝
     additive 参数透传：`startHTTPHost` / `startHeadlessStdioHost` /
     `startReadOnlyHTTPHost` / `startEmbeddedIfPreferenceEnabled`（缺省
     nil = 既有签名调用零 diff）。**EmbeddedState 第五缝（F-4①）**：
     searchState 随 box 存取——`startEmbeddedIfPreferenceEnabled` 把
     searchState 与 editing/culling 同批存进 EmbeddedState box，
     preference toggle on-leg 的 `startEmbeddedServer` 从 box 读出再传
     `startHTTPHost` 同路透传（亲核 :721-750 既有 editing/culling 形）；
     缺此缝 = GUI 用户先关后开 MCP 时三工具静默缺席。grep 机检点位含
     `startEmbeddedServer`。
  4. **GUI 装配**（LightamerApp :1331-1374 同段）：构造 context——
     library = `libraryProjects.projectStore/projectURL`（ProjectFileStore
     直携——E-1；MainActor.run hop，MatchColor 装配闭包同形但不走
     static box）；sessionPair =
     sessionIndexController.currentSession；semantic/fulltext = GUI 同源
     provider 形（AIInferenceService.semanticSearcher / imageIDs 缝）；
     liveState = workspace/editor/exportState 快照闭包；projectWriteProbe
     复用既有 `projectWriteProbe` 闭包；writeCallCount = GUI embedded 走
     `embeddedWriteCallCount()` 同源（McpServerController :585-588）。
     传 `startEmbeddedIfPreferenceEnabled`。
  5. **无头装配**（runHeadlessArbitrated 两臂 + 无 `--project` 路径）：
     library seam = `headlessProjectStore` 直携（本就是 ProjectFileStore——
     E-1 后 provider 形吻合；writer 臂已 open；只读臂 T4 接线后同源；
     nil = typed notSessionMember）；liveState = nil（诚实 null）；
     semantic/semanticStore/fulltext = open 包派生（bundled 资产
     同 binary 可达，RESEARCH §4.5）。**probe/writeCallCount 终形
     （F-4②）**：probe = 既有面透传；writeCallCount = GUI embedded 走
     `embeddedWriteCallCount()` 同源，headless / 只读 face 无 handle
     外露面 = **null 诚实面**（server 字段缺席语义）——不立项新
     plumbing（无消费者）。stdio EOF 优雅腿与 connect-guidance 双通道
     **零改**。
  6. **xcstrings 三新键**：`mcp_tool_desc_search_photos` / `_get_history` /
     `_get_state` 尾块纯插入（历史键字节与顺序零触碰）。
  7. 构建绿机检：`caffeinate -dis tuist generate && xcodebuild build`
     （或项目现行构建缝）——本任务零测试文件（T5 批承载），AC = 构建
     绿 + 下述 grep 结构核。
- **验收标准（机检）**：
  - 构建绿；`git diff --stat` 恰五文件（SearchStateToolset 新建 +
    McpServerController + LightamerApp + xcstrings + 无它）。
  - grep：`makeRegistry` 全部调用点核（缺省 nil 调用保持编译零改）；
    `readOnlyHint: true` ×3 在 SearchStateToolset；`requiresWriter` 在
    SearchStateToolset 零显式出现（缺省 false）；宿主装配点对账
    （N-8 清单形）= 六调用点（LightamerApp :1374 / runHeadless :196/:203 /
    runHeadlessArbitrated :292/:303/:322）/ 四缝 + EmbeddedState 内部缝
    （grep 点位含 `startEmbeddedServer`——F-4①）。
  - 既有 MCP 测试面不触（T5 快照零 diff 门预支：本任务不改任何既有测试
    文件）。
- **commit**: `feat(m7-2): add the search/state toolset skeleton and host wiring`

## T2 — `search_photos` 三路由 + `modelUnavailable` 错误臂

> **单源红线（RESEARCH §0.1）**：EXIF 腿 = `ExifSearchParser.parse` →
> `LibraryQueries.searchPage` + `searchNullTail`（两段走法两查询皆既有
> 单源——FilterSQL `.library` 域，`stackMode: .flat` MCP 先例）；CLIP 腿 =
> `SemanticEngine.search`；全文腿 =
> `AIDescriptionService.imageIDs`——**无第二 SQL/检索面**（FilterSQL 头注
> 「no second SQL face may exist」直接覆盖本工具）。

**read_first**：`M7-2-RESEARCH.md` §3.1（工具面提案 + 显式偏离三条）；
`LibrarySearchModel.swift` :145-244（三分派正本）；`LibraryQueries.swift`
:202-256（sort 白名单 + searchPage/searchNullTail 两查询签名——两段走法
正本，searchPage 恒 nullTail:false / NULL tier 独立查询）；`ExifSearchParser.swift` :38-44
（typed 错误）；`SemanticEngine.swift` :40-45/:82（错误 + search 签名）；
`AIDescriptionService.swift` :146（imageIDs）。

- **action**：
  1. **schema 终式**（D-M7-2-2/3 生效值）：`query`（string 必填，空串 =
     typed `invalidParams`——GUI 空串语义是「清过滤」，MCP 面诚实拒绝）；
     `mode` enum `exif|clip|fulltext` 默认 `exif`；`limit` 1..500（EXIF
     默认 200 / CLIP 帽 256 / 全文帽 500）；`cursor`（EXIF 臂 only，
     opaque token——**PhotoProjection.Cursor 同形 base64 + sortedKeys
     JSON，payload 加 `segment` 字段（main|nullTail，**缺失 = typed
     `invalidParams` 拒——跨工具 token（list_photos 传入 search_photos）
     静默接受 = 语义混淆，cursor 是 OUR token，PhotoProjection decode
     garbage 同纪律（R-3，checker 批钉）**）+ sort 键 + 方向 +
     anchor（E-2 两段走法；sort 键嵌入白拿换键失效负测，:198-270 先例
     形）**）；`sort`（EXIF 臂 only，`{key, ascending}` 白名单
     五键 filename/rating/captureDate/iso/focalLength，**默认显式钉
     `{key: "filename", ascending: true}`——GUI 同源 LibraryGridModel
     :97（N-3）**——`scanEpoch` 显式排除 = typed 拒）。**越臂组合
     typed 拒（N-4）**：mode=clip|fulltext 携 cursor 或 sort =
     `invalidParams`（schema 层 + handler 双拒，T5 负测钉）。
  2. **EXIF 路由（两段走法，GUI 同源——E-2 修法甲）**：parse → plan
     （`ExifSearchFilter(group:plan:)`）→ **主段 `searchPage`**（`.library`
     域 + `.flat`；恒 `nullTail: false`，只含 sort key 非 NULL 行——
     LibraryQueries :231-236）→ 主段耗尽（返回行数 < limit）→
     `nextCursor` **翻段**（token `segment = nullTail`、anchor = nil）→
     **尾段 `searchNullTail`**（NULL tier 独立查询，:239-256——五个 sort
     键全可空故尾段对五键全合法）；尾段亦尽 = 无 `nextCursor`。
     **尾段续页 anchor 手搭（R-2，checker 批钉）**：`.anchor(of:key:)`
     对 NULL-key 行返 nil（LibraryQueries :89 guard），尾段续页 cursor
     的 anchor = `LibraryPageAnchor(keyValue: .int(nil),
     imagePath: last.imagePath)`（keyValue 未用，image_path 唯一 seek——
     LibraryGridModel `advanceTail` :296-300 注记正本同款）；翻段首尾页
     anchor=nil 不受此涉。与
     LibraryGridModel 两段走法（:5-13/:88-91 Segment{main, nullTail}）
     一一对应。窄投影九字段（CONTEXT
     D-M7-2-3——列映射以 `images` 表实存列为准，无列支撑字段如实缺席，
     禁加 schema 面或第二查询面；DECISIONS 登记列映射终值）。sort 键序 +
     `image_path` tiebreaker 单源（两段查询原样）。**description 注明
     （N-2/N-6）**："each call evaluates the query against the full
     library (no layered session filter state)"（无状态语义诚实）+
     imagePath = path-kind 相对形（agent 寻址走 imageID）。
  3. **CLIP 路由**：semantic 缝 → `SemanticEngine.search(query, limit≤256,
     in: semanticStore)` → cosine 降序 + `score` 字段；缝缺席/资产缺席 =
     `modelUnavailable`（D-M7-2-6 映射规则——modelUnavailable 与
     dimensionMismatch 双映射，message 区分 missing/mismatched）。
  4. **全文路由**：fulltext 缝（`imageIDs`，limit≤500）→ bm25 rank 序 +
     rank 序位字段。
  5. **typed 错误臂**：空 query / 解析错（`unrecognizedToken`/
     `disjointDateRanges` → `invalidParams` 携 token，GUI ErrorFamily
     同构信息进 message）/ 无开项目 → `notSessionMember`（文案 "no open
     project — open a .lalb first"）/ CLIP 双错 → `modelUnavailable` /
     **`AIWorkerClientError` 四案（workerUnavailable / workerCrashed /
     workerExhausted / requestFailed）→ 亦归 `modelUnavailable`（F-3——
     M2-10-05 后 production runner 是 worker 进程，此族不是
     SemanticSearchError、adapter 只捕 McpToolError，不映射 = 协议级
     无码兜底，比 GUI 面〔LibrarySearchModel :211-214 catch-all 同型〕
     排障信息更差；归 modelUnavailable = 「语义运行时对本查询不可用」
     族语义，message 携 worker 案名与细节——D-M7-2-6 语义诚实裁定同构，
     DECISIONS 申报终形；`internalError` 备选不采——资产/进程缺席映射成
     我方 bug 是排障误导）**。
  6. **McpToolError additive**：`modelUnavailable(String)` case——`code`
     switch 补 `"modelUnavailable"` + message 提取 switch 补臂（:61-111
     封闭表 additive 显式改；16 值穷举测试 T5 钉）。
  7. 超时：三臂复用 `McpTimeouts.list`（10s）——CLIP 贴线实测超时才
     DECISIONS 申报升 20s 档，禁止静默。
- **验收标准（机检）**：
  - 构建绿；schema JSON 含 mode 三枚举 + 双域分界句在 description；
    sort 白名单外键 typed 拒路径在码（grep + T5 测试钉）。
  - `git diff App/Sources/Lightamer/MCP/McpToolRegistry.swift` 逐 hunk 核
    = 恰 modelUnavailable 两臂、其余零触。
  - 既有 20 工具零触（diff 面申报 + T5 快照零 diff 门预支）。
- **commit**: `feat(m7-2): implement the search_photos three-route query face`

## T3 — `get_history` + `get_state` 只读投影

> **零新持久化读法（RESEARCH §0.1）**：`get_history` =
> `ExportRenderer.readDocument(imageURL:)`（LightamerCore/Sources/Export/
> ExportRenderer.swift:783，editing 面已在用的 sidecar 读缝）→
> HistoryStack/versions/note 只读投影；`get_state` = seam closure 注入
> 快照（`liveImageURL` / `installLibraryProvider` 两先例同构形）。

**read_first**：`M7-2-RESEARCH.md` §3.2/§3.3（两工具面提案 + 状态源表）；
`HistoryStack.swift` :34-140（HistoryStack/HistoryItem 五种 item 字段）；
`LightamerSidecar.swift` :293-309（metadata 面）+ :919-940
（SidecarVersionRecord）；`McpServerController.swift` :120-136
（McpProjectLockVerdict）。

- **action**：
  1. **`get_history` schema**：`image`（string 必填——双地址制：digits 库
     id 经 `LibraryStore.image(id:)`（LibraryStore 由 context 的
     ProjectFileStore 用公开 `LibraryStore(store:)` init 现场派生——E-1）
     + ImageLinker.resolve 落文件路径；
     relPath 经 sessionPair 臂；两臂皆不可达 = `notSessionMember`）；
     `includeParams`（bool 默认 false）；`limit`（items 帽——**F-5 一句
     钉死：默认 = min(全量, 500)；截断保留最新端（position 侧，有效历史
     优先）；itemCount 恒真值总数（截断可由 position/itemCount 检出，
     保留方向影响 agent 自查序列正确性故显式钉）**）。
  2. **投影**：readDocument → `{position, itemCount, items[]{id, label,
     timestamp, kind, layerScope, params?}, versions[]{id, name, createdAt,
     updatedAt, active}, activeVersionID, note, keywords, rating, flag,
     colorLabel, author?}`。kind 判别纯函数五臂（D-M7-2-4）；drt/film
     占位 snapshot 按 drtDocumentScope/filmDocumentScope 剔除；versions
     meta only（`chain == nil` = active）；**author 恒 null**（M7-4 前向
     占位）。无 sidecar 文档 = pristine 诚实面（position=-1、items 空、
     metadata 全 null）——非错误臂。
  3. **`get_state` schema**：零入参；一行 JSON 快照六字段组（CONTEXT
     D-M7-2-8 逐字段）——project/workspace/editor 从 `liveState` 缝取
     （MainActor hop inside，@Observable 态即取即走零跨 actor 长持）；
     control = projectWriteProbe verdict + writeCallCount；tasks =
     ExportState.queue 四态计数；server = serverName/serverVersion +
     host mode + readOnly 立场。字段缺 = null 诚实面（无头臂 workspace/
     editor/tasks null；无 `--project` 臂 project null）。
  4. **热态语义**：description 注明 "one-shot snapshot; fields are not
     guaranteed consistent between calls"（RESEARCH §8）。
  5. schema 终式补全随本任务（T1 骨架的 get_history/get_state 两件）。
- **验收标准（机检）**：
  - 构建绿；kind 判别纯函数独立可调（`static func`，T5 golden 直调）；
    author 恒 null 在码面（grep + T5 负测钉）。
  - diff 面申报：HistoryStack/LightamerSidecar/PipelineDocument 封存面
    零触（`git diff --stat` 核）。
- **commit**: `feat(m7-2): add get_history and get_state read-only projections`

## T4 — 无头只读臂 `openReadOnly()` 服务读面

> **现缺口（RESEARCH §2.2/§4.3）**：heldByOther 臂不 open store
> （`headlessProjectStore` 保持 nil，仅 emitConnectGuidance + serve）——
> 只读工具在该臂无数据面。D-M7-2-7 = open（零写险：`openReadOnly()`
> ProjectFileStore.swift:199 锁免 + schema `stored == current` 守卫 +
> 写腿 `withWriteBatch` :454 typed 拒断路器全部原样）。

**read_first**：`McpServerController.swift` :242-286（双臂 + EOF 腿）+
:376-409（只读 http face / stdio host）；`ProjectFileStore.swift` :60-66/
:187-199/:454-463（openReadOnly 锁免头注 + 断路器）；`McpProjectArbitrationTests.swift`
（序列 A/B fixture 正本）。

- **action**：
  1. heldByOther 臂（runHeadlessArbitrated）：emitConnectGuidance 之后
     `try? store.openReadOnly()` → 成功 = `headlessProjectStore = store`
     （library seam 全活）；失败 = nil + log 诚实降级（三工具 typed
     notSessionMember）——**禁 exit(1)**（D-M7-2-7）。
  2. 两宿主透传核：只读 http face 与 stdio host 的 searchState context
     library seam 同源 headlessProjectStore（T1 已布，本任务接通数据面）。
  3. **connect-guidance 双通道零改**（序列 A/B fixture 是零回归门）；
     stdio EOF 优雅腿零改（`try? await headlessProjectStore?.close()`
     自然覆盖只读 store 释放）。
  4. **flock 语义零改**：openReadOnly 零锁获取（grep + 既有 LIB 只读
     测试面零触佐证）。
  5. **SC 判据通道（F-2 甲——只读 face 端口发现）**：DEBUG 门控下只读
     http face 也写 discovery 文件——`LIGHTAMER_MCP_ENDPOINT_DIR`
     per-test 域内（:115-124 `headlessEndpointPaths` 同款 `#if DEBUG`
     门形），**独立文件名 `mcp-endpoint-readonly.json`**（不覆 writer 的
     `mcp-endpoint.json`——heldByOther 场景 writer 文件是 guidance
     真相源，零覆写）；Release 路径零触（「no discovery json — that
     file belongs to the writer」:316-323 注记语义在 Release 面原样）；
     测试父进程经 `McpEndpointFile` 同族读缝拿绑定端口——SC「照常服务」
     从无可接线判据变为机器可判（评审亲核：先例 McpProjectArbitrationTests
     序列 A/B 只断言 guidance JSON + 进程驻活、从不过线调工具，
     McpHostTests HTTP 面全走 in-process handle——两先例均不覆盖本 SC）。
     registry 级降格（乙：readOnlyMode store + `writerCheck { false }` +
     search 走通 + 序列 A/B 驻活门照旧，双进程过线保真放弃）为 DECISIONS
     申报降级路径；stderr 刮端口（丙）不采（弱且脆）。
- **知悉（N-7 亲核，非本波新增面）**：只读 store `close()` 会跑
  `checkpointTruncate`（:303-312）——writer 持 WAL 时 typed 失败、stdio
  EOF 腿 `try?` 吞掉 + 进程退出兜底；writer 空闲且 WAL 已全 checkpoint
  时 truncate 是 SQLite 语义内安全操作（既有 GUI openProjectReadOnly
  路径同语义）。
- **验收标准（机检）**：
  - 构建绿；`git diff` 逐 hunk 核 = 恰 heldByOther 臂一处插入 + 透传 +
    只读 face DEBUG discovery 写（action 5，`#if DEBUG` 分支——Release
    路径零 diff）+ McpEndpointFile additive 变体两缝（write/read 与
    `mcp-endpoint.json` 既有语义零改——R-1）；connect-guidance 发射面/
    stdio EOF 腿/writer 臂零 diff。
  - 只读臂「search_photos 照常服务」经 action 5 端口通道亲调工具断言
    成功面（双进程锁 fixture 下；T5/SC 判据同源）。
  - `McpProjectArbitrationTests` 序列 A/B 零 diff 绿（T6 定向轮亲跑；
    本任务构建绿 + 逻辑核预支）。
- **commit**: `feat(m7-2): serve read-only tools from the headless held-project arm`

## T5 — 测试批：parity golden + 快照同批 + 零回归 + 穷举 + 锁豁免

> **orchestrator 指定分批**：测试集中本任务一次落位（T1-T4 码面稳定后
> ）。新文件 `Tests/LightamerTests/McpSearchStateToolsetTests.swift`
> （APP 域——与既有 Mcp* 同 bundle，research §4.6 默认裁定行使）。
> **登记纪律（M2-4-0 E2）**：Project.swift 恰一行 + BUNDLE-MAP 恰一行
> （APP 域）+ `tuist generate` 恒为该批最后一个动作（L041）。

**read_first**：`M7-2-RESEARCH.md` §5（测试策略七条）；`McpFinalSnapshotTests.swift`
（:22-27 冻结表 + :174/:202/:230/:373 计数断言 + :200 组合代数 +
:237-259/:274 descriptionKeys 对账 + :159-160 makeUnionRegistry +
:363 SC7 startHTTPHost——union 显式改全点位见 F-1 清单）；`McpRegistrySnapshotTests.swift`（editing 层零触对照）；
`FilterSQLTests`（WHERE/bind 快照同型先例）；`McpHostTests`（双进程
fixture 先例）。

- **action**：
  1. **parity golden 三臂（ROADMAP 验收形态①）**：
     - EXIF：fixture `.lalb` 上 `search_photos` 输出 id 集与序 ≡ **GUI
       同源两段走法**——直调 `searchPage`（主段）+ `searchNullTail`
       （尾段）拼接（同 sort/anchor；**对照腿同为两段，单段对照 = 双腿
       共享 NULL 盲区禁用——E-2**）；**fixture 必含 NULL-key 行**（至少
       一行 unrated + 一行无 captureDate）且 sort=rating / sort=captureDate
       两向各断言工具翻段后可达该行（F1 失明洞修补——验收门对 NULL 尾段
       不再失明）；cursor 翻段链路断言（主段耗尽 → token
       segment=nullTail → 尾段续走）；越臂组合 typed 拒负测（N-4）；
       `ExifSearchParser.parse(query)` plan 恒等断言
       （工具与 GUI 共用 parse 的结构性保证）；FilterSQL WHERE/bind 快照
       （FilterSQLTests 同型，可落本文件或既有 FilterSQLTests——落点
       DECISIONS 申报）。
     - CLIP：mock `SemanticSearching` 注入（LibrarySearchModel 测试先例，
       CI 零模型资产）——确定性 fixture embedding 下 hit 序/score 投影
       恒等 + modelUnavailable/dimensionMismatch 双映射臂。
     - 全文：fixture `ai_understanding(_fts)` 行 → 工具输出 ≡ 直调
       `AIDescriptionService.imageIDs`（rank 序恒等）。
  2. **get_history golden**：fixture sidecar 文档（param/structure/paste/
     drt/film 五种 item + **双载荷项一例（pasteSet+stackSnapshot 并存 →
     归 paste 先序显式断言——N-5）** + versions 三条〔一 active 两
     chained〕+ note/keywords/rating）→ 投影 JSON byte-equal；
     `includeParams` 两档；**limit >帽 截断方向断言（保留最新端——F-5）**；
     position=-1 pristine 面；kind 判别五臂纯函数直调；author 恒 null
     负测。
  3. **get_state golden**：无头无项目 typed nulls 契约（project/workspace/
     editor/tasks null + control/server 活）；context 注入 fixture 后
     六字段面各臂至少一活一空；**MainActor hop 机检双判据（F-6）**——
     ①fixture `liveState` 闭包体内 `dispatchPrecondition(condition:
     .onQueue(.main))` + 调用计数，get_state 断言「闭包被调且在主线程」
     （hop 结构在位的可执行判定）；②grep 机检：SearchStateToolset.swift
     源对 WorkspaceModel / PipeCoordinator / ExportState /
     LibraryProjectController 类型名零直接引用（handler 只摸 context
     closure）。
  4. **快照同批（ROADMAP 验收形态②）**：域快照新层（3 工具 name/
     description/schema verbatim + 域内计数 23 分账）；union 显式改——
     **全点位清单（F-1 补全，McpFinalSnapshotTests.swift 亲核坐标）**：
     冻结表 +3 行（名序 get_history/get_state/search_photos，:22-27 表头
     注释同步）+ 计数断言 ×4（:174 descriptors.count / :202 u.count /
     :230 tools.count / :373 directTools.count，均 20→23）+
     **组合代数断言（:200）`Set(u) == Set(e).union(Set(c))` 改三集合并
     （三新工具入新域非并入既有 editing/culling——M5-1-03 先例形不能
     照抄：match_color 是并入既有域，本波是新域）** +
     **descriptionKeys 映射表 +3 行（:237-259）+ :274 `Set(key map) ==
     Set(descriptors.map(\.name))` 对账断言随之过门** +
     **makeUnionRegistry（:159-160）传 fixture searchState context
     （不传 = union 恒 20，23 计数永不可达）** + **SC7 startHTTPHost
     （:363）传 fixture context** + :226 注释行 + 测试名 Union20→
     Union23（M5-1-03 先例 19→20 形）——**DECISIONS 申报显式改**。
  5. **零回归（ROADMAP 验收形态③）**：既有 editing(6)/culling(14) 两层
     快照零 diff（文件不改、测试原样绿）；`McpHostTests`/
     `McpEditingToolsetTests`/`McpCullingToolsetTests` 全绿；白名单负测
     （未注册名 = internalError）随域快照。
  6. **McpToolError 16 值穷举**：code 字符串逐案断言（15 既有 + 
     modelUnavailable；穷举 switch 编译期 + 运行期双钉）+ **worker 族
     映射一法（mock searcher 抛 `AIWorkerClientError.workerUnavailable`
     → 断言映射 modelUnavailable 码与 message 携细节——F-3）**。
  7. **单写者锁只读豁免面**：三工具在 `writerCheck { false }` 下照常
     成功（写类对照 = serverReadOnly 拒）；`writeCallCount` 调用前后
     零增量断言；projectWriteProbe 零触（probe 计数/记录面不加访问）。
  8. **Project.swift + BUNDLE-MAP + tuist generate**（本批最后动作）。
- **验收标准（机检）**：`--bundle APP` 全绿（新测试 + 既有 MCP 面全绿）；
  快照显式改申报在 DECISIONS；新文件恰一行登记 + BUNDLE-MAP 恰一行。
- **commit**: `test(m7-2): pin the search/state goldens and grow the union snapshot to 23`

## T6 — 定向轮 + 全套 `--all` + 收口翻账

- **action**：
  1. **定向轮**：`caffeinate -dis Scripts/test-direct.sh --bundle APP`
     （MCP 宿主面全在 APP 域——BUNDLE-MAP 亲核）全绿。
  2. **全套确认轮**：`caffeinate -dis Scripts/test-direct.sh --all`
     （**批准制**——本 plan 标注在案，执行时 orchestrator 派发 prompt
     即批准；运行中保持监视 + 8G 门 + MEMFAIL 机检，超门立即 kill）。
     `TOTAL|3860+ΔN/35/0|` 对账精确闭合（ΔN 逐任务记账；skip 35 构成
     声明——第三种 skip 来源 = 逐族差分申报禁静默吸收）。
  3. **红线族机检**（front-matter `red_lines` 逐条亲跑）：零新 SPM /
     `.metal` 全域零 diff / 封存面 17 件零 diff / 既有 20 工具面零 diff /
     xcstrings 尾块纯插入（三新键，历史键零触碰）/ UserDefaults 零新键 /
     runModal 零命中 / LocalizationValue 插值禁形零命中 / Project.swift
     恰一行 + BUNDLE-MAP 恰一行 + tuist generate 末位核。
  4. **zh-audit 对账**：`uv run python3 Scripts/zh-audit.py --check` PASS
     + `--self-test` PASS（V17 门引用形——三新描述键入 zh 面，静态键
     scanner 可见；动态族无新增申报）。
  5. **SUMMARY + DECISIONS**：逐任务 ΔN 记账 + parity golden 判定指针 +
     快照显式改申报 + auto 分类器后置挂账 + cursor 跨调用稳定性已知边界
     （与 list_photos 同风险同口径，不引入 cursor 版本戳）+ 窄投影列映射
     终值 + CLIP 超时档裁定 + worker 族映射终形（F-3——modelUnavailable
     族申报）+ 只读臂端口判据通道终形（F-2——甲落地或乙降格申报）。
  6. **翻账**：REQUIREMENTS MCP2-01..03 → Delivered（M7-2 commit 指针）
     + MCP2-01 行 LabelQueries→AIDescriptionService 勘误（CONTEXT 勘误
     注记兑现）；AGENTS「M7-2 架构增量」节；TODO（M7-2 条目 + 挂账）；
     GOAL-STATE 续接点（M7-2 收口 → next = M7-3，**MCP 快照面串行接棒**
     注记——M7-3/M7-5 不与本波并行）。
- **验收标准（机检）**：定向轮绿 + 全套 exit 0 / 0 fail / 0 MEMFAIL /
  七 bundle 8G 门内 + 对账闭合 + 红线族全 PASS + zh-audit PASS + 四台账
  同批落盘（历史行只追加不改写）。
- **commit**: `docs(m7-2): reconcile the full suite and close the M7-2 ledgers`

---

## 风险与回退

- **T5 大批量测试后置**（orchestrator 指定分批的内在风险）：T1-T4 码面
  缺陷在 T5 才暴露 → T5 发现码面缺陷 = 回注对应任务修复（fix commit +
  T5 重跑），禁为凑绿放宽断言；parity golden 三臂任一不恒等 = 停手归因
  （单源链断裂嫌疑——查是否绕过 parse/searchPage/searchNullTail/
  imageIDs 直连）。
- **CLIP 贴线超时**（万级库 vDSP 扫）：10s 档实测超时 → DECISIONS 申报
  升 `thumbnailsAndContact` 20s 档（唯一许可路径）；禁静默改档或加新档。
- **F-2 甲 DEBUG discovery 写的碰撞面**：只读 face 独立文件名
  （`mcp-endpoint-readonly.json`）不覆 writer 的 `mcp-endpoint.json`；
  per-test 专用 `LIGHTAMER_MCP_ENDPOINT_DIR` 域内 writer/reader 各自
  文件零碰撞——若执行中发现同目录残读（前一 case 的 readonly 文件），
  测试侧 case 边界清扫（`remove` 同族缝），不为此改 Release 语义。
- **只读臂 openReadOnly 失败**（schema 守卫拒旧包）：诚实降级 nil seam
  （三工具 notSessionMember）+ log——禁 exit、禁扩 schema 迁移面
  （迁移归 ProjectFileStore 既有 migrator 域，本波零触）。
- **快照族冲突**：本波持 union 改动权——若 orchestrator 误并行派发
  M7-3/M7-5（快照面撞车）→ 立即停手上报，禁抢先合并快照表。
- **get_state 热态读崩**（@Observable 跨 actor）：一切 @Observable 读取
  必须在 liveState 闭包内 MainActor.run 完成——handler 直接观测 = 结构
  违规，T5 结构断言钉死。
- 全套轮任何 fail：先归因（本批 Δfiles 窗内?）——窗外 fail = 既有缺陷，
  停手上报不静默修（NLMeans flake 先例：隔离重跑 + 台账）。

---

## Checker 关注点（独立反向核输入）

1. **Goal-backward**：ROADMAP §M7-2 行三验收形态 ↔ T5（parity golden +
   快照同批 + 零回归门）/ T2-T3（三工具语义）/ T6（定向 + 全套轮）逐项
   映射；REQUIREMENTS MCP2-01..03 三行无孤儿项；Alcedo 三命令对表锚
   （search.query/editor.history/state.get）→ 三工具一一对应。
2. **OQ 兑现核**：D-M7-2-1..9 逐条对任务面——①双域分界句在 description
   （T2 action 1）+ get_history 双地址两臂（T3）②mode 三枚举默认 exif
   ③CLIP 帽 256/全文帽 500/EXIF 两段 cursor（segment 字段）/窄投影九字段/
   默认 sort filename asc ④summary+includeParams + limit 截断保留最新端
   + author 恒 null 负测 ⑤versions meta only（无 chain 字段——schema
   快照核）⑥modelUnavailable additive 两 switch 补臂 + 16 值穷举 +
   dimensionMismatch 双映射 + AIWorkerClientError 族归 modelUnavailable
   （F-3）⑦只读臂 openReadOnly + 失败降级禁 exit + F-2 甲端口判据通道
   ⑧六字段组 + tasks=M2 导出队列 ⑨context provider 形（ProjectFileStore
   直携——E-1）+ static box 零复用（MatchColorToolset 零 diff 核）。
3. **只读三面结构性不触**：三工具注册零 `requiresWriter: true`；
   registry writer gate 分支（:333-341）零 diff；writeCallCount 只在
   requiresWriter 分支内自增（T5 豁免面测试钉）；projectWriteProbe 在
   SearchStateToolset 内只读引用（get_state control 面），零写面消费。
4. **快照族纪律**：union 显式改全点位（F-1 清单——计数 ×4 + 组合代数
   + descriptionKeys + 两处 fixture context + 表头注释 + 测试名）+
   DECISIONS 申报；editing/culling
   两层快照文件零 diff（`git diff --stat` 核）；域快照新层 verbatim 断言
   形与既有两层同构；「本波持 union 改动权」编排前提在 plan 头注与红线
   双写（M7-3/M7-5 串行）。
5. **单源红线**：T2 三路由 diff 面核——ExifSearchParser.parse /
   LibraryQueries.searchPage + searchNullTail（两段走法两查询皆既有单源）
   / SemanticEngine.search / AIDescriptionService
   .imageIDs 直调消费，无第二 SQL 面（新 SQL 字符串/新 FTS 查询 grep
   零命中）；窄投影无 schema 面 additions。
6. **封存面**：HistoryStack/LightamerSidecar/DrtRecord/ExportQueueContract
   等 17 件零 diff（get_history 纯只读投影——类型/CodingKeys/schema 零触）；
   `*.metal` 全域零 diff。
7. **SC 可机检性**：每条 SC 有命令级判据（golden byte-equal / grep 机检 /
   计数断言 / 对账行），非「目测」；expected_all 对账式非死数；skip 35
   构成声明条款在 T6。
8. **xcstrings 纯插入**：三新键 diff = 纯插入（历史键字节与顺序零触碰——
   diff 逐 hunk 核）；描述键显式 `String(localized:defaultValue:)` 形态
   （插值禁形 regex 零命中）；zh-audit --check + --self-test 双 PASS。
9. **登记纪律**：Project.swift 恰一行（McpSearchStateToolsetTests）+
   BUNDLE-MAP 恰一行（APP 域）+ tuist generate 恒末位（L041）——commit
   顺序核（登记与测试同 commit，generate 最后动作）。
10. **零回归面**：既有 20 工具 descriptor/handler/McpTimeouts 零 diff；
    McpProjectArbitrationTests 序列 A/B 零 diff 绿（connect-guidance
    面不变）；writer 臂行为零变化（T4 恰 heldByOther 臂一处插入——
    逐 hunk 核）；全套轮 3860+ΔN 对账闭合。
