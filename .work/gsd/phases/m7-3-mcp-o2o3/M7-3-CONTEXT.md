# M7-3 CONTEXT — MCP O2 反馈回路 + O3 项目与版本（OQ 裁决落定批，2026-10-17）

> **裁决正本**：OQ-M7-3-1..10 **全部按 `M7-3-RESEARCH.md` §7 推荐落定**（M7 站
> charter 授权站内 auto-advance + OQ 全按推荐；先例 M6-3/M6-4、M7-2 同款）。
> **晨审可推翻**——推翻 = 用户晨审修订本文件对应 D 条，下游 plan 受影响任务面
> 重开（已执行部分按「晨审推翻先例」惯例处理）。读解正本 = 同目录
> `M7-3-RESEARCH.md`（§0 结论摘要 / §2 现状测绘 / §3 四件语义 / §4 顺路件
> 六项 / §5 集成缝 / §6 测试策略 / §7 OQ 表；file:line 均 2026-10-17 HEAD
> `217999a5` planner 批逐点亲核复核——renderedPlane :220/:236 / descriptor
> :774 / body :823-859 / installedNames :381 / entry(named:) :399 /
> libraryGroups :443 / create :103 / open :158 / openReadOnly :199 /
> projectHeldByOther :249 / makeHeadlessSearchState :183 / liveState 启动捕获
> :209-224 / fulltext 静默空 :204-209 / runHeadlessArbitrated :303 / EOF
> watcher :353-367 / probe :374 / openProject conflict 不 throw :150-166 /
> promoteRecent :165 / pristine payload :833-847 / versions meta :869-880 /
> resolveImageURL :951 / union 计数 :209/:246/:274/:421 + F-AC-4 注释 :210 /
> requestFailed(String) :41 全部吻合）。
>
> **夜间全自动授权在案**（先例 D-07-3-T5-1；晨审可推翻）：本 phase 执行批
> （omp 执行 + subagent 验收 + 全套 `--all` 轮〔批准制——执行时 orchestrator
> 派发 prompt 即批准〕）可夜间全自动推进，不需逐任务等待用户确认。
>
> **C 档门控行使记录**：RESEARCH 自标「C 档第 1 停（OQ 裁决前不进 plan）」——
> 该停由站 charter 授权链行使（OQ 全按推荐落定即裁决，本文即落定载体）；
> C 档第 2/3 停（plan 闭环汇报 / VALIDATION 签核）照常保留——站内
> auto-advance 只覆盖第 2 停的**等待面**（闭环汇报照发，不停等确认），
> 第 3 停（VALIDATION 签核给用户过目）不受站内授权覆盖，仍走人工过目。
>
> **快照改动权移交**：M7-2 VALIDATION 特殊事项 5——本波持 union 文件
> （`McpFinalSnapshotTests.swift`）显式改权（23→27），**M7-3..M7-5 串行禁
> 并行**（orchestrator 编排保证；若误并行派发 = 立即停手上报，禁抢先合并）。

## Phase Goal（ROADMAP §M7-3 行锚定）

`render_preview` 加 `compare:"root"`（原图对比出图）+ `region`（ROI）参数
——agent 自评调色的 before/after 反馈闭环（Alcedo `render.preview` 语义对表）
+ `list_luts` 小件 + `project_open`/`project_create`（agent 全流程第一步；
与 M6-1 项目单写者锁面交互 = OQ-M7-3-1 裁决）+ `list_versions`（只读投影；
变更类命令视单写者余量二期）。验收形态（ROADMAP 原文）= compare/region
golden ✓ + project 工具与单写者锁仲裁 fixture ✓ + 快照族零意外 diff ✓。
对应 REQUIREMENTS MCP2-04..07（:434-437）；对表锚 = Alcedo `render.preview` /
`project.open`+`project.create` / `versions.list` / `lut.list`
（ALCEDO-CLI-AI-SURVEY.md 块一 + 本地源 render_commands.cpp /
project_commands.cpp / version_commands.cpp 只读对表——GPL 零复制）。

## 决议（D-M7-3-1..10，生效值，硬约束，执行中不重开）

### D-M7-3-1 `project_open`/`project_create` 宿主形态 = 双宿主同源路由（OQ-M7-3-1）

- **裁决 = RESEARCH 推荐（双宿主同源）**：两工具在双宿主面同语义落地，路由
  单源在装配点——
  - **无头臂（agent 默认承载面）**：Core `ProjectFileStore` 直开/直建
    （`open(role: .headless)` / `create(name:role: .headless)`）→ park
    `headlessProjectStore` 载体——库 seam 立即活（closure 每调用读载体，
    零额外接线）；heldByOther → typed `projectReadOnly(holderSummary)`
    应答（holder summary 从锁 payload 读，`SingleWriterLock.holderSummary`
    既有面）。
  - **GUI 内嵌臂**：MainActor hop 经 `LibraryProjectController
    .openProject/createProject`（Alcedo 同构：automation 寄宿 GUI；controller
    是开项目单源，零新路径）；conflict 对话框即仲裁 UI——`openProject` 对
    heldByOther **不 throw**（publishConflict :150-166 亲核），工具应答判别
    = **before/after 差分**（`pendingConflict` 调用前 nil ∧ 调用后非 nil ∧
    `projectStore` 未变化）→ typed `projectReadOnly(holder)`（「对话框已
    发布、等用户裁决」的诚实应答；评审修订：原「调用后 projectStore ==
    nil ∧ pendingConflict != nil」单点式有两洞——已持项目 + held 目标误报
    成功、stale pendingConflict 反向误报；GUI 臂 held 目标另加
    `SingleWriterLock.probeLockAvailable` 无持有预检——held 直接 typed 拒
    不调 openProject，**一次 agent 调用不得掀用户正开项目**）；
    判别缝在 context provider 闭包内完成，工具体零 controller 类型引用
    （F-6 源隔离纪律延续）。**controller 文件本身零 diff**（provider 闭包
    外部装配——FIX2③ import coalescer 两枚维持 M7-4 挂账，本波不触其尾部）。
- **`requiresWriter: true`**（双宿主一致）：状态变更面走 endpoint writer
  gate；只读宿主天然 `serverReadOnly` 拒（held 臂不能换项目，语义正确）。
- 被否备选：v1 无头 only、内嵌臂 typed 拒（降级可后补——不采，controller
  路由零新路径成本更低且 Alcedo 同构）。

### D-M7-3-2 `region` 坐标契约 = 归一化 0..1（OQ-M7-3-2）

- **裁决 = RESEARCH 推荐（归一化 0..1）**：object `{x, y, w, h}` 全 double，
  归一化矩形；语义 = 在**渲染后平面**上裁剪（`CGImage.cropping(to:)`，
  rect × 实际渲染宽高取整）——与 longEdge 解耦（缩放不变，agent 免换算
  像素）。
- **两工具分界写进 description**：`get_detail_crop` = 源细节检视（绝对像素
  ROI，原生分辨率）；`render_preview region` = 渲染观感 ROI（归一化，
  相对渲染输出画面）。region 同时作用于 current 与 root 两臂（同 rect，
  Alcedo 同构）。
- 校验：w/h ≤ 0 → `invalidParams`；越界（x+w>1 / y+h>1 / 负坐标）→
  `roiOutOfBounds`（既有码，message 携归一化域）。EXIF orientation 已在
  decode 链归一（region 相对渲染输出画面，无第二坐标系——description 注明）。
- 完整边界表归 M7-6 SKILLS-01（N2-2/F-AC-5 同批文档句面）。
- 被否备选：绝对像素（与 detail_crop 同形但坐标系基准面歧义更大）。

### D-M7-3-3 `compare` 默认 = `root`（OQ-M7-3-3）

- **裁决 = RESEARCH 推荐（默认 root）**：enum `"none" | "root"`，默认
  `root`——反馈回路的语义即对比，agent 每次渲染自动拿 before/after；显式
  `none` 供省载荷。
- 载荷预算边界写进 description：双臂 ≈3MB@1024/q85（2048/q90 帽双臂
  ≈11MB 极端）——typed 帽在位（D7 2048/q90 不变），**不做服务端自动降档**
  （诚实拒绝优于静默缩水）。
- 双臂超时 = 既有 `McpTimeouts.renderAndCrop` 30s 单窗（两遍预览级渲染远低
  于单遍 100MP 全流程谱；**零新超时档**——CONTEXT D-M7-2-3 档位红线延续）。
- 与 GUI 的显式偏离申报（RESEARCH §3.1）：Alcedo 落 PNG 文件
  （out_dir/file_stem），我方内联 JPEG（D5/D7 内联优先纪律不变）；Alcedo
  `long_edge` 默认 2048，我方默认 1024（D7 token 效率线，不动）。
- 被否备选：默认 `none`（agent 忘传 compare 就丢 before/after——回路退化）。

### D-M7-3-4 域归属 = 第四域 ProjectToolset + list_luts 入 editing 6→7（OQ-M7-3-4）

- **裁决 = RESEARCH 推荐（是）**：
  - **ProjectToolset 新第四域**：`project_open` / `project_create` /
    `list_versions` 三工具（Alcedo project/version 命令族同构；锁仲裁语义
    自成一族，union 分层命名归位）。
  - **`list_luts` 入 editing 域**（6→7）：lut3d 模块参数的库读面，与
    `list_iops`（参数目录）同族。
  - union 分层变为 editing(7) + culling(14) + searchstate(3) + project(3)
    = **27**。
- 被否备选：list_luts 也入 ProjectToolset（LUT 与 project 语义无 affinity）；
  list_versions 入 searchstate 域（版本树是 project 语义面）。

### D-M7-3-5 compare:root 双臂不共享 decode = 零新 render 代码（OQ-M7-3-5）

- **裁决 = RESEARCH 推荐（v1 不共享）**：两臂各走 `renderedPlane` verbatim
  （pristine 臂传同 `decodeLeg` 即各解一次）——「零新 render 代码」红线的
  最简兑现；性能损失 = 多一次 decode，预览级可忽略。
- 共享 decode 属后续优化：若实测慢再立项（届时 `renderedPlane` 再开缝，
  Core 触点扩大需新裁决）。
- **Core 唯一新触点** = `renderedPlane` additive 默认参
  `pristineOnly: Bool = false`（true 时跳过 :236 `readDocument`——
  document nil / records=[] / layerStack nil = 与「无 sidecar 文档的
  pristine 图今日渲染」逐位同路径，同一空链分支）；既有消费方（QL pane
  :123/:171 / parity 测试 :221/:262/:543 / MatchColor parity :158 /
  QuickLookRendererTests :206/:227 / MCP body :835）默认参零 diff。

### D-M7-3-6 ProjectSummary 不带 photo_count（OQ-M7-3-6）

- **裁决 = RESEARCH 推荐（v1 不带）**：两工具出参 =
  `{path, name, readOnly, heldByOther}`——open 应答要快（count 需额外查询，
  open 路径持锁窗口内少一次 SQLite 往返）；字段缺席 = schema 自描述诚实面。
- agent 需要计数时 `search_photos`（mode=exif 空查询）/`list_photos` 自取
  （既有工具面，零新增）。
- 被否备选：带 count（Alcedo 同构加分但非零成本——二期若 agent 实测高频
  需要再立项）。

### D-M7-3-7 运行时 open 后 arm EOF 释放 watcher（OQ-M7-3-7）

- **裁决 = RESEARCH 推荐（是）**：无头臂首次运行时 open/create 成功后 arm
  同款 stdin HUP watcher（`runHeadlessArbitrated` :353-367 现体**只在
  `--project` 启动路径** armed——亲核；运行时开项目路径零 armed）。幂等
  guard 一行（static once 面——运行时多次 open 只 arm 一次）；watcher 体
  从「闭包捕获 `headlessProjectStore`」改读**当前项目盒**（HUP 时点读当前
  在持 store——close + exit(0) 语义原样，M6-1 checkpoint 优雅面延续到运行时
  开项目路径）。启动路径既有 arm 点行为逐字节不变（同函数抽取共享，
  grep 机检）。
- 不补 = 进程退出 kernel 释放地板（M6-1 语义允许但丢 checkpoint 优雅面）——
  DECISIONS 申报偏离；本裁决采补。
- **评审修订钉全（M1/H3③）**：arm 门控机制 = provider 闭包在
  `runHeadless(mode:)` / `runHeadlessArbitrated(mode:)` 的 mode 可见作用域
  内构造（mode 捕获进 provider/context——provider 签名不带 mode）+
  `armStdioEOFReleaseOnce()` 内部自守卫 `mode == .stdio`（双保险——防
  http daemon stdin 已闭时无门控 poll 立即 POLLHUP → close + exit(0) =
  首次 open 成功即整 daemon 退出）；**偏离面补句：http 运行时开项目 =
  进程退出 kernel 地板，checkpoint 优雅面仅 stdio**（http 臂不 arm 语义
  正本不变，申报面钉全）。
- 被否备选：不 arm（丢优雅 checkpoint）。

### D-M7-3-8 `list_versions` seam = ProjectToolset 自携同形两 seam（OQ-M7-3-8）

- **裁决 = RESEARCH 推荐（自携同形）**：`McpProjectContext` 自带
  `library` / `sessionPair` 两 provider（与 `McpSearchStateContext` 同形
  closure 签名）——**装配点把同一 closure 变量赋给两个 context**（provider
  逻辑零复制，F-6 单域自持纪律：工具体不跨域消费另一 toolset 的 context
  实例）。
- 寻址 = `get_history` 双地址制 verbatim 复用（digits 库 id 经
  `LibraryStore.image(id:)` + ImageLinker / open-session relPath；
  寻址核心抽 internal 共享 helper——`(image, libraryProvider,
  sessionPairProvider)` 签名（评审修订：原「`resolveImageURL` :951-998
  同构直调」按字面不可达——该函数 private static 且第二参吃
  `McpSearchStateContext`，OQ-8 禁 ProjectToolset 消费之；共享抽取 =
  行为零变的纯抽取，SearchStateToolset 传 context 两 seam、
  ProjectToolset 传自携同形两 seam，零新寻址逻辑、禁复制形；
  helper 只搬 searchState 现逻辑，禁顺手动 match_color provider——
  锚病在案、M7-4 路由）。
- **单源声明**：sidecar `readDocument`（`ExportRenderer.readDocument`
  :783 既有读缝）唯一真相——**不读 `.lalb` version_ref 投影**（投影 ≠ 真相，
  M2-8 KD-3；读了 = 双真相禁令违例）。version_ref 在本工具零角色。
- 被否备选：ProjectToolset 直接消费 `McpSearchStateContext`（跨域耦合，
  快照白名单语义混）。

### D-M7-3-9 MCP 开项目不入 `library.recentProjects`（OQ-M7-3-9）

- **裁决 = RESEARCH 推荐（否）**：**零新增 promoteRecent 调用面**——
  recent 是 GUI 用户面，agent 批量轮次不得主动写它。
- **双臂不对称申报**（research §3.3 原文机制，CONTEXT 升正本）：无头臂不经
  controller（Core 直开/直建），**天然不入 recent**——agent 默认面不受
  污染；GUI 内嵌臂经 controller 复用既有 GUI open 语义（`promoteRecent`
  :165/:142/:179 随行——同源纪律优先：为 MCP 调用面加抑制 plumbing = 新
  controller 面 + 新旗标参数，成本大于收益）。DECISIONS 钉死此不对称。
- 被否备选：入 recent（Alcedo 无此概念无从对表；污染面真实）。

### D-M7-3-10 `project_open` writer 臂照常 migrate（OQ-M7-3-10）

- **裁决 = RESEARCH 推荐（照常 migrate）**：`open(role:)` 既有迁移语义
  原样——stub/旧 schema 包在 writer 臂正常 migrate（agent 拿到的是完整
  可写项目，与 GUI open 同构）；migrate 失败 = `internalError` 携
  LibraryError detail（兜底臂，零新错误码）。
- 只读宿主（serverReadOnly 前置拒）与 held 臂（projectReadOnly）不达
  migrate 路径——迁移面只在真 writer 臂行使。
- 被否备选：拒旧 schema 逼用户先 GUI 打开（多一步无收益）。

## get_state 联动改形（非 OQ，plan 任务面硬约束——RESEARCH §3.3 亲核正本）

`makeHeadlessSearchState` 的 `liveState` closure（:209-224）现体是**启动期
捕获值**（`projectURL`/`isWriter` 闭包捕获）——运行时 open/create 后
`get_state.project`/`server` 面会说谎。本波必修：liveState 改读**当前项目
盒**（carrier + 可变 currentURL 小盒，per-call 重取）——盒空 = 现状
no-project null 面逐字节（零 diff），盒持 = 真值；**启动捕获退役范围 =
liveState + library seam 的 projectDirectory 锚（:194
`projectURL.deletingLastPathComponent()` 改盒读）**——运行时切换后
PathKind 0 项目相对行解析锚随盒换项目（锚捕旧目录 = 静默解析错文件，
fix `20997721` 同族第二实例——H2）；无 `--project` 两臂（stdio
:254-256 **和 http :263-267**——裸 `McpSearchStateContext()` 亲验恰两处）
同批换盒读 closure 形（open 前
library/fulltext seam 读空盒 = nil = typed `notSessionMember` 与今日 bare
context 行为逐字节同；open 后即时活——零额外接线）；**生产宿主调用点
全清单传 project provider**（runHeadless :254/:263 /
runHeadlessArbitrated :378/:390/:410——不传 = 该宿主 project 三工具静默
缺席，违双宿主红线「tools never disappear」——H3）。F-AC-2 probe 透传
（`makeHeadlessSearchState` 加 `projectWriteProbe` 默认参 + :374 调用点传
既有 probe）同缝落——headless `get_state.control.lock` = verdict 真值。

## 顺路件六项（M7-2 挂账单一清单，本波收口；正本 = M7-2-VALIDATION §挂账）

| # | 项 | 裁决 |
|---|---|---|
| ① | F-AC-1 FilterSQL `.library` 域快照补申报 | 新法 `testLibraryDomainSnapshots()`（FilterSQLTests，Library bundle，Project.swift :586 已登记零登记改）+ DECISIONS 申报段——F-AC-1「二选一收口」两路同时兑现 |
| ② | F-AC-2 headless searchState 透传 projectWriteProbe | `makeHeadlessSearchState` 加默认参 + :374 传既有 probe（与 get_state 联动改同缝） |
| ③ | N2-1 pristine 面补 `truncated` 键 | payload 加 `"truncated": .bool(false)` 一行（形状一致化零语义变）+ pristine golden 字节同批更新 |
| ④ | N2-3 fulltext 闭包窄竞态 typed 抛 | `guard let store else { return [] }`（:204-209）→ typed `notSessionMember(noOpenProjectMessage)`（闭包已 throws；与「never a silent empty result」头注纪律对齐） |
| ⑤ | N2-4 `requestFailed` 显式测试 | F-3 家族映射法补一臂（`AIWorkerClientError.requestFailed("…")` → `modelUnavailable`，亲核 case 形 :41 `requestFailed(String)`）——F-3 四案闭合 |
| ⑥ | cursor 跨调用稳定性边界注记 | 无码面——本波 DECISIONS 承接一句（边界口径不变：库重排后旧 cursor 可能跳行/漏行，不引入版本戳；list_versions/project 族无 cursor 面，零新增边界） |
| 附 | F-AC-4 union 注释「11 read」过时（:210） | 随 union 显式改同批一行（改写为非易碎形，消除未来计数漂移） |

**FIX2 挂账③（import coalescer 窄边界两枚）本波不承载**：修法落点
`LibraryProjectController.swift` 尾部，而本波 controller 文件零 diff
（provider 闭包外部装配）——顺手窗口不开，维持 M7-4 挂账。

## 键族 / 登记面

- **xcstrings 尾块纯插入 4 新键**：`mcp_tool_desc_list_luts` /
  `mcp_tool_desc_project_open` / `mcp_tool_desc_project_create` /
  `mcp_tool_desc_list_versions`（zh-only 形）+ **原位值改 1 键**：
  `mcp_tool_desc_render_preview`（en defaultValue + zh 译文同批——描述扩
  compare/region 语义；非尾块插入）。zh-audit `--check` 对账 source keys
  数 +4；`--self-test` PASS。
- **UserDefaults 零新键**（project 工具不记忆路径——agent 每调显式传；
  recent 面 D-M7-3-9 零新增写入）。
- **Project.swift 恰一行**（McpProjectToolsetTests.swift → LightamerTestsApp）
  + **BUNDLE-MAP 恰一行**（APP 域）+ **`tuist generate` 恒为该批最后一个
  动作**（L041）。

## 红线（正本移交 `M7-3-01-PLAN.md` front-matter `red_lines`，此处摘要）

①MCP 快照族显式改——本波持 union 改动权（23→27 + render_preview schema
两层 consciously change together）；M7-3..M7-5 串行禁并行。②零新 SPM。
③零新 render 代码（双臂不共享 decode = D-M7-3-5；Core 唯一新触点 =
renderedPlane additive 默认参一处）。④既有 23 工具 descriptor/handler/
McpTimeouts 零 diff（除 render_preview 申报内 schema 字节 + description
键值）。⑤错误码零新增（16 档封闭表零触；project 族全走既有码）。⑥封存面
零触（list_versions 是 sidecar/HistoryStack 只读投影——类型/CodingKeys/
schema 零改；LightamerSidecar/HistoryStack/PixelPipe/ExportQueueContract
等 17 件零 diff）。⑦Alcedo GPL 代码/文案零复制零翻译（只对表命令语义）。
⑧xcstrings 4 新键尾块纯插入 + render_preview 原位改 + zh-audit 双 PASS；
UserDefaults 零新键。⑨`--all` 全套轮批准制 + 8G 门 + MEMFAIL 机检 + 运行中
保持监视；测试宿主清理先核 parentage。

---

## 评审修订注记（2026-10-17 fixer 批）

`M7-3-01-PLAN-REVIEW.md`（4 高 / 3 中 / 4 低，总评「须修后放行」）修订批
已落 plan 文本；本文件同步修订四处实现级细节（**OQ 裁决本身零重开，
D-M7-3-1..10 生效值不变**）：D-M7-3-1 判别缝谓词改 before/after 差分 +
held 目标 probeLockAvailable 预检（H4）；D-M7-3-7 补 arm mode 自守卫
+ http 无 EOF 腿偏离句（M1/H3③）；D-M7-3-8「resolveImageURL 同构直调」
改共享寻址 helper 抽取形（M3——原句按字面不可达，private + 吃
searchState context）；「get_state 联动改形」节补 no-project http 臂
+ 生产宿主调用点清单 + :194 projectDirectory 锚退役（H3/H2）。

**键数勘误（L1）**：pristine payload（SearchStateToolset :833-846）亲点
= **12 键**（image/position/itemCount/items/versions/activeVersionID/
note/keywords/rating/flag/colorLabel/author），加 truncated = **13**——
plan SC/T1/files_modified 三处「十三键→十四键」已改「十二键→十三键」；
`M7-2-VALIDATION.md` §③ 同写「十三键」系源头同错，属历史签核文档不回改，
以本注记为准。SC grep 判据（truncated 恰一行）不受影响。
