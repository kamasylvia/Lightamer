# M7-3-01 PLAN REVIEW — 独立评审（替代 omp 路，零共享上下文）

- 评审基线：HEAD `46e32b0f`（2026-10-17 plan 定稿批；其上零产线文件）
- 评审正本：`M7-3-01-PLAN.md` + `M7-3-CONTEXT.md`（D-M7-3-1..10）+ `M7-3-RESEARCH.md`
- 交叉正本：`M7-2-VALIDATION.md` §挂账单一清单 + §特殊事项 5（快照改动权移交）
- 代码面亲验：全部 file:line 经本评审独立打开核对（非转抄 planner 批注）；
  与 plan/CONTEXT 标称坐标逐点比对，偏差见 L1/L2。
- **总评：须修后放行**（4 高 / 3 中 / 4 低；核心设计可执行，快照点位清单与
  两处诚实面缝须先补——均为 plan 文本修订，不动架构）。

---

## 一、Findings

### H1（高）快照计数钉 F-1 家族复发——plan 外 4 文件 5 处硬编码计数钉未被「全点位亲核」覆盖，T5 零回归门按现文本不可满足

M7-2 评审 F-1 教训（union 点位枚举不全）在本 plan 精确复发，且漏点在 **union
文件之外**。plan T5 action 5/7 声称「union 显式改全点位亲核」+「既有
culling/searchstate 两层快照零 diff（文件不改、测试原样绿）」+「McpHostTests
…全绿」——以下 5 处计数钉全部被 T3 的 list_luts（editing 6→7）打破，均不在
plan 的显式改清单内：

| # | 位置 | 现值 | T3 后 | files_modified 状态 |
|---|---|---|---|---|
| 1 | `McpRegistrySnapshotTests.swift:194`（`testProbeFaceRetiredFromBareRegistry`，editing+culling 无 searchState 装配） | `names.count == 20` | 21 → 红 | 文件在清单内，但该点位未枚举（plan 只列 :30 assertSnapshot + :152 render_preview 行） |
| 2 | `McpSearchStateToolsetTests.swift:270`（`testRegistryWithoutSearchStateStaysAtTwenty`） | `descriptors.count == 20` | 21 → 红 | 文件只在 T1 清单（pristine golden）；**与红线「searchstate 层文件不改、测试原样绿」直接矛盾** |
| 3 | `McpHostTests.swift:243`（`testHTTPEndToEndSDKClientRoundTrip`） | `tools.count == 20` | 21 → 红 | **文件完全不在 files_modified** |
| 4 | `McpHostTests.swift:696`（三宿主 conformance，http 臂） | `httpTools.count == 20` | 21 → 红 | 同上（:718 memory 臂断言 ≡ httpTools，无独立硬码，随 #4 连带） |
| 5 | `McpLauncherTests.swift:200` | `names.count == 20` | 21 → 红 | **文件完全不在 files_modified** |

连带同族点（同批显式改时应一并处理，避免留下 M7-2 式「11 read」过时注释）：

- union 文件 `all23` 静态属性名（`McpFinalSnapshotTests.swift:184-186`）及其
  在 :207 的引用——plan 只写「测试名 Union23→Union27」，属性改名未点名；
- union 文件头注释 :22「THE UNION (23)」与 :209 断言 message「the final
  count is 23」；
- `McpRegistrySnapshotTests.swift:30` docstring「the 14-4 union asserts all
  20」。

**建议修法**：①T5 显式改清单增补上述 5 处 + 属性/注释连带点，全部走
「显式改 + DECISIONS 申报」；②files_modified 增 `McpHostTests.swift` 与
`McpLauncherTests.swift` 两行（计数钉 20→21 + message 同批）；③红线第
「searchstate 快照零 diff」条改写为「searchstate **工具面**（三工具
descriptor/schema 快照）零 diff；:270 计数负测显式改（20→21，零 diff 负测
语义保持——『无新域时的既有面』随 list_luts 归位到 21）」——消除 plan
内部自相矛盾；④T5 验收 grep 增补：全仓 `count, 20`/`count == 20` 在 MCP
测试面零残漏命中（防第六处）。

### H2（高）T4「启动捕获退役」范围漏了 library seam 的 projectDirectory 锚——运行时切项目后 store/目录错配，路径解析静默漂移

`makeHeadlessSearchState` 现体（`McpServerController.swift:183-225`）四处
启动捕获：`projectURL`（:194 library seam 的 projectDirectory 锚 +
:213-214 liveState）、`isWriter`、`mode`。plan T4 action 3 只点名
「liveState closure（:209-224 启动捕获退役）改读盒」——**library 闭包的
`:194` `projectURL.deletingLastPathComponent()` 捕获未退役**。运行时
`project_open` 到另一项目后：盒持新 store（store 侧 :188 每调用读盒，plan
的「库 seam 立即活」对 store 半边成立），但 projectDirectory 锚仍指旧项目
目录 → PathKind 0（项目相对）行的 ImageLinker 解析全部锚错目录 →
search_photos/list_photos/get_history/list_versions 的项目相对路径**静默**
解析到不存在/错误的文件。这正是 M7-2 fix `20997721` 同族缺陷（provider 锚
必须为包目录）的第二实例。

**建议修法**：T4 action 3 明确「启动捕获退役 = liveState **+ library seam
的 projectDirectory 派生**（:194 改 `box.url.deletingLastPathComponent()`）」；
T5 补一腿 golden：运行时 open B（A→B 切换）后 search/get_state 的
project.path 与路径解析锚同指 B（现 plan 只有盒持真值断言，无切换后锚断言）。

### H3（高）无头 HTTP 无 `--project` 臂被 plan 遗漏——:267 裸 `McpSearchStateContext()` 不在换形清单，project provider 装配点缺两处生产调用点

plan T4 action 3 只写「no-project **stdio** 臂 :254 换形」。实测裸 context
构造有**两处**：`runHeadless` stdio 臂 :254-256 **和 http 臂 :263-267**
（`startHTTPHost(..., searchState: McpSearchStateContext())`）。后果：

1. 无 `--project` 的 headless HTTP daemon 上运行时 `project_open` 后，搜索
   三工具仍答 notSessionMember（library/fulltext seam 恒 nil）而 project
   工具报成功——同进程内自相矛盾的诚实面；
2. `runHeadless` :263 与 `runHeadlessArbitrated` :390（writer http 臂）两个
   生产调用点未在 plan 的装配点清单里——不传 project context 则该宿主
   project 三工具**缺席**，违反双宿主红线（「closed face identical across
   hosts——tools never disappear」；McpToolRegistry 头注 + M7-2 端到端三证
   的 23 全列纪律）。
3. 附带：http 臂运行时开项目无 EOF 释放腿（plan 明说 http 不 arm——语义
   正确但 DECISIONS 应补一句「http 运行时开项目 = 进程退出 kernel 地板，
   checkpoint 优雅面仅 stdio」，把 D-M7-3-7 的偏离面钉全）。

**建议修法**：T4 action 3 增补「no-project **http** 臂 :263-267 同批换盒读
closure 形」+「runHeadless :263 / runHeadlessArbitrated :390 两调用点传
project provider（Core 直开形，mode 捕获见 M1）」；T4 grep 机检从「:254 单
点」扩为「裸 `McpSearchStateContext()` 在 McpServerController 内零命中」。

### H4（高）GUI 内嵌臂判别缝谓词逻辑不完备——已持项目时 held 目标误报成功 + stale pendingConflict 反向误报；close-先行的 GUI 状态面风险未评估

判别缝字段本身外露可读（`LibraryProjectController.swift:52`
`private(set) projectStore`、:73 `var pendingConflict`——plan 风险节担心的
「状态面不外露」不成立），但 plan 的谓词
「`projectStore == nil ∧ pendingConflict != nil`」有两个逻辑洞：

1. **已持项目 + held 目标 = 误报成功**：GUI 臂当前已开项目 A（projectStore
   = A 非 nil），agent `project_open(B)` 且 B 被他人持有 → `openProject(B)`
   publishConflict 后 return（:150-166 亲核：不 throw），projectStore 仍是
   A → 谓词不触发 → provider 按成功路径用 projectStore 构造 outcome——
   agent 收到「已打开」的假答（实际打开的还是 A，且用户屏幕上多了个对话框）。
2. **stale pendingConflict = 反向误报**：用户此前手动 open C 触发的
   conflict 对话框还挂着（pendingConflict 仅由 dismissConflict :183-185
   清除，用户不点不清），agent `project_open(D)` 成功 → 谓词触发 → 成功
   被报成 projectReadOnly。
3. **GUI 状态面风险**：若按 T4 action 1 的「已持有项目 = 先关后开」套到
   GUI 臂（action 4 未写明，语义上疑似套用），则「agent 对 held 目标的
   一次调用」会先关掉用户正开着的 A 再 fail——用户工作区被 agent 调用掀翻，
   且 plan 的「错路径不动当前项目」保护只覆盖 not-exists，不覆盖 held。

**建议修法**：①谓词改「调用前快照 pendingConflict，调用后
`pendingConflict != nil ∧ 调用前 == nil ∧ projectStore 未变化` →
conflict 臂」或等价的 before/after 差分（两行，纯装配点逻辑，controller
零 diff 不破）；②GUI 臂先关后开之前先做**无持有 probe**（既有
`SingleWriterLock.probeLockAvailable`——零新面）：held 目标直接
`projectReadOnly(holder)`，不动当前项目——把「错路径不动当前项目」的
Alcedo 语义延伸到「held 目标不动当前项目」，headless 臂无 GUI 状态可掀、
可维持先关后开，但两臂行为差异应在 DECISIONS 一句话钉死；③T5 锁仲裁
fixture 增两腿：已持 A + open held B → typed projectReadOnly 且
get_state.project 仍指 A；stale conflict 挂起 + open 成功目标 → 成功应答。

### M1（中）EOF watcher 运行时 arm 的 stdio 门控机制未指定——若 arm 裸调，http daemon 可在首次 project_open 后立即自杀

D-M7-3-7 正确要求「stdio mode 才有意义——http 臂不 arm」（启动路径 :353
`if mode == .stdio` 门在位，亲核）。但运行时 arm 点在工具 provider 闭包内，
provider 形（`@Sendable (URL) async throws -> ProjectOpenOutcome`）不带
mode——plan 未指定 mode 如何到达 arm 点。失败模式具体：headless http
daemon 若 stdin 已闭（agent harness 后台拉起），无门控的 poll 立即
POLLHUP → close 当前项目 + `exit(0)` → **首次 open 成功即整 daemon 退出**。

**建议修法**：plan 一句话钉机制——provider/context 携带 launchMode（装配点
捕获：`runHeadless(mode:)` / `runHeadlessArbitrated(mode:)` 均在 mode 可见
作用域内构造 provider），`armStdioEOFReleaseOnce()` 内部自守卫
`mode == .stdio`（双保险）；T5 增一腿：http mode 运行时 open 后
`armStdioEOFReleaseOnce` 不产生 watcher（或 stdin HUP 不触发 exit）。

### M2（中）region 取整规则与整数框越界/零宽面未钉——合法归一化入参可落到 `CGImage.cropping(to:) == nil`

plan 只写「rect × 实际渲染宽高取整（round vs floor 由 T5 golden 钉）」，
但三个派生面未进规格：

1. **取整溢出**：x+w == 1.0（合法、不越界）在非 2 幂宽上可产生
   `round(x·W) + round(w·W) == W+1`（如 a=306.5/W=1021 双入位），整数框越
   平面 → `cropping` 返 nil；
2. **亚像素零宽**：w=0.0004 通过校验（w>0）但 ×1024 取整后宽 0 → nil；
3. nil 后的行为面未指定（detailCrop 先例 `CullingToolset.swift:1096-1097`
   = `renderFailed("cropping failed")`——直接沿用会让「合法归一化入参」
   得到 renderFailed，与 invalidParams/roiOutOfBounds 的校验承诺脱节）。

**建议修法**：T2/T3 规格补一句——「整数框 = rect×宽高后 round，再与平面
bounds 求交（clamp；交后 w/h ≤ 0 → invalidParams 携归一化值）」；T5 golden
强制含两边界腿：x+w==1.0 精确、亚像素 w（期望 invalidParams 或最小 1px，
以 golden 判定为准——plan 风险节「禁静默换取整式」已立，把判定对象补全）。

### M3（中）`resolveImageURL`「同构直调」自相矛盾——函数 private 且签名吃 `McpSearchStateContext`，ProjectToolset 按构造拿不到

`SearchStateToolset.resolveImageURL`（:951-998）为 `private static` 且第二
参 `context: McpSearchStateContext`；OQ-8 明拒 ProjectToolset 消费
searchState context（跨域耦合）。故「同构直调——零新寻址面」（research
§3.4 / plan files_modified 注）按字面不可达，剩余两路 plan 均未点名：

- **复制**：~45 行寻址逻辑落 ProjectToolset——「零新寻址面」名存实亡，
  双面漂移风险（两处 digits 判别/两处 stale 文案）；
- **共享**：把解析核心抽成吃 `(image, libraryProvider, sessionPairProvider)`
  的 internal helper（SearchStateToolset 传 context 两 seam，ProjectToolset
  传自携同形两 seam——OQ-8 的「装配点共享同一闭包变量」正好喂同一闭包），
  SearchStateToolset.swift 需在 T4 追加 hunk——而该文件在 files_modified
  只挂 T1，T4 的 diff 面申报不含它。

**建议修法**：采共享 helper 形（行为零变的纯抽取，golden 双地址臂钉住），
T4 files_modified 给 SearchStateToolset.swift 追加注记行 + DECISIONS 申报
「寻址单源抽取」；禁复制形。

### L1（低）pristine payload 键数 plan/CONTEXT/M7-2 VALIDATION 三处同错：实为 12 键 → 13 键（非 13→14）

亲点 `SearchStateToolset.swift:833-846`：image/position/itemCount/items/
versions/activeVersionID/note/keywords/rating/flag/colorLabel/author =
**12** 键（grep 计数 12）。加 truncated 后 = 13（与正常面 :882-901 十三键
对齐——「形状一致化」的实义恰是 12→13 与正常面等形）。M7-2-VALIDATION §③
同写「十三键」——源头即错。SC 的 grep 判据（truncated 恰一行）不受影响，
但执行者按 SC 核对键数会对不上。修法：plan SC 与 DECISIONS 模板把
「十三键→十四键」改「十二键→十三键」。

### L2（低）「三消费方」枚举不全（F-1 家族标注级）——实际 9 调用点 / 5 文件

红线与 D-M7-3-5 写「三消费方（QL pane :123/:171 / parity :221/:262/:543 +
MatchColor :158 / MCP body :835）」，漏 `QuickLookRendererTests.swift:206/:227`
（CONTEXT D-M7-3-5 括注里其实有，plan 前脸丢了；T2 验收括注「QuickLookRendererTests
（除新负测）零触」又捡回来了）。行为面无洞（T2 机检覆盖），但「三」的口径
与全仓 grep（9 调用点：QL 内部 2 + parity 3 + matchcolor 1 + QLRendererTests
2 + MCP body 1）不一致——F-1 的教训是枚举口径即审计面，建议改为「全消费方
清单（9 调用点 / 5 文件）」逐点列名。附带 bundle 归属核（T6 门设计依赖）：
`McpRenderParityTests` = **IOPP** bundle（BUNDLE-MAP :107）——T6 定向轮三域
（App/Library/EXPORT）不含 IOPP，plan 的「IOPP 随全套轮验证 + EXPORT 恒等
负测预支」注记正确且必要，维持。

### L3（低）`ProjectOpenOutcome.name` 来源未指定——Core 无公开 name 读面，不钉死会逼出新 Core 触点（违红线③）

grep `ProjectFileStore.swift` 公开面：`fileURL`(:89)/`create`(:103)/`open`
(:158)/`openReadOnly`(:199)/`close`(:303)/`checkpointIfNeeded`(:322)/`backup`
(:362)——**无 project name 读面**（create 的 projectName 只在写路径
:136 进 schema）。outcome 四键 `{url, name, readOnly, heldByOther}`（D-M7-3-6）
的 name 若执行者现找读面 = 新 Core face = 破「Core 唯一新触点 = pristineOnly」
红线。修法：plan 一句话钉 name = `url.deletingPathExtension().lastPathComponent`
（create 路径 name 恒等该 stem；open 路径以盘面 stem 为准，与 GUI recent
列显示口径一致）；或明示走既有某读面（若执行时核得）。

### L4（低）list_luts golden 自洽循环风险（E-2 家族预防注）

T5 golden 断言「投影 ≡ `installedNames`/`entry(named:)` 直调恒等式」——
工具与断言读同一 `LutLibraryStore.shared`（replaceShared 换临时根后），
恒等式有同义反复味，断不出「工具读对了 store」。建议恒等式之外**加 seeded
内容正断言**（seeded .cube 的已知 name/hash/size/键形 +1 条），把 golden
从「自洽」升为「可见」（M7-2 E-2 失明 golden 教训的直接套用）。plan 现有
「键形根相对 POSIX + rememberedEncodings 透传」两条已在正确方向，补内容腿
即闭环。

---

## 二、六维评审结论（逐维）

### 维度 1 — T2 pristineOnly：**可达性证实，无虚分发陷阱**
`renderedPlane` 为 static func（`QuickLookRenderer.swift:220`），全仓 9 个
调用点（5 文件，grep -l 亲证）全部 `QuickLookRenderer.renderedPlane(...)`
静态直调——无协议存在体/override 链，Swift 默认参静态分发陷阱不适用；尾部
加 `pristineOnly: Bool = false` 为源级/二进制级 additive，9 点全部编译零改
取 false。Core 侧 `decodeLeg: DecodeLeg?` 无默认参、T3 双臂各传同参不共享
decode——与 OQ-5 一致。T2 负测②的 byte-equal 依据成立：pristineOnly:true
与无 sidecar 副本同落「document nil → records=[] → imageID 新 UUID」同一
空链分支，imageID 仅作 PipeCache 身份（每调用新 cache）不入像素语义。
**但**「三消费方」口径与 region 取整规格两处须修（L2/M2）。

### 维度 2 — T4 第四域：**缝位核实，四处规格洞（H2/H3/H4/M1）**
- F-AC-2 供给面完整：`McpSearchStateContext.projectWriteProbe` 字段与默认
  参 init 在位（SearchStateToolset.swift:105/:125），get_state 消费点 :1020
  在位——「context init 带入 + :374 传既有 probe」可行，:370 probe 已建亲核。
- EOF watcher「仅 `--project` 启动路径 armed」亲核属实（:353-367 在
  runHeadlessArbitrated 内，:248-251 仅 projectURL 非 nil 时进入）。
- 四宿主缝坐标全核实：startHTTPHost :754 / startHeadlessStdioHost :524 /
  startReadOnlyHTTPHost :464 / startEmbeddedIfPreferenceEnabled :852 +
  EmbeddedState box :934-939 + on-leg 读出 :875-886——F-4① 第五缝同款成立。
- makeRegistry :579-595 三默认参现体，第四参 additive 可行。
- GUI 装配点可行：LightamerApp :1383 searchStateContext 段（library 闭包
  每调用读 controller，GUI 侧无捕获病）与 :1519 startEmbedded 同段，「同一
  closure 变量赋两 context」（OQ-8）可落。
- requiresWriter 顺序面成立：registry writer gate（McpToolRegistry :331-340）
  先于一切 handler → serverReadOnly 前置拒结构性保证；工具体内
  先检（invalidParams）后开（projectReadOnly）为 Alcedo 同构。
- 洞见 H2（library 锚捕获）/H3（http 臂）/H4（判别缝谓词）/M1（arm 门控）。

### 维度 3 — 快照红窗机制与点位清单：**红窗门可执行；点位清单自身漏 5 处（H1）**
- 四计数点 :209/:246/:274/:421 坐标亲核吻合（含 :210 F-AC-4 注释原文
  「exactly 9 destructive tools, 11 read」、:190-200 makeUnionRegistry、
  :281-305 descriptionKeys 现值 23 条、:245 三集合并、:239-241 三 disjoint、
  SC7 :410-412 + :421 directTools——「不传 project context 则 :421 改 27
  后必红」的预判正确）。
- 红窗期守门结构成立：T1 gate 含 `--bundle App`（App 当时全绿）→ T2 起
  红窗、gate = 构建绿 + EXPORT 定向（QLRendererTests 在 EXPORT，:256 亲核）
  → T5 `--bundle APP` 闭合点 → T6 三域定向 + `--all` 终证 + fail 归因条款。
  schema 红窗只影响两层快照文件，McpHostTests/LauncherTests 不钉 schema
  （只钉计数）——它们的红与快照红窗**不同源**（list_luts 计数），恰因 T3
  后无 App bundle 轮而潜伏到 T5 才爆，plan 未预见（H1 修法已含）。
- 「有无第五漏点」：有，且不止一处——见 H1 表。

### 维度 4 — T5 锁仲裁 fixture 与新工具 golden：**判据可判定，主路径已被仓内证据证实**
- **in-process held 形可构造**：`SingleWriterLock.swift` 头注明文「Darwin
  flock(2) arbiters per OPEN FILE DESCRIPTION: two independent open() fds
  IN THE SAME PROCESS also EWOULDBLOCK（checker o1，cc-verified
  2026-10-16）」——DECISIONS 申报条件（「若 in-process flock 不足以构成
  held 形」）可判定，且按仓内 cc-verified 证据主路径必成、跨进程升级
  fallback 预计不触发。fixture 可行。
- render_preview 双臂 golden 形态可行：Seams 有 decodeLeg 注入缝
  （EditingToolset :835 消费），parity 先例（McpRenderParityTests decodeLeg
  注入形）可复用；compare golden 的「pristine 臂 ≡ 无 sidecar 直调」为双
  入口收敛断言，**非 E-2 失明形**（两臂走不同代码入口再 byte-equal）。
  唯注意双臂同 30s 单窗——重图 2×render 的超时风险是已声明 typed 面闭
  （renderTimeout 可重试 compare:none），D-M7-3-3 在案，不另立 finding。
- list_luts golden 见 L4 循环注。
- project 三工具 golden：快照 verbatim + 仲裁 fixture 腿清单与 ROADMAP
  验收②对表成立；建议增 H4③ 两腿。

### 维度 5 — SC/ΔN/红线/files_modified：**ΔN 带合理；files_modified 欠 2 文件 + 1 文件缺 T4 hunk（H1/M3）；红线一条自相矛盾（H1②）**
- files_modified 实点 22 件核对吻合；欠 McpHostTests/McpLauncherTests，
  SearchStateToolset 缺 T4 hunk 注记（M3），McpRegistrySnapshotTests 缺
  :194 点位（H1①）。
- ΔN +12..20 带经盘点成立：T1 ~4（F-AC-1 新法 1-2 + N2-3/N2-4 负测 2 +
  F-AC-2 断言 1；N2-1 为 golden 字节更新零新法）+ T2 ~2-3 + T5 ~8-14
  （project 快照 ~2 + 仲裁 ~4-6 + list_versions ~4-6 + region/compare/luts
  ~4-6；union/editing 两层为显式改非新法）——中位 ~16，带内；H4③/M1/M2
  增腿后仍在带上沿内。
- 红线族与封存面交集：list_versions 只读投影不触 LightamerSidecar/
  HistoryStack 写面（SidecarVersionRecord/chainStack 公开读面亲核 :919-960，
  `var chain` internal + `chainStack` public 计算属性——投影只读可行）；
  错误码 16 档封闭表亲核（McpToolRegistry :62-76 + :85 modelUnavailable，
  plan 消费的六码全在表）；McpTimeouts 三档（list 10 / apply 10 /
  renderAndCrop 30）亲核在位——「零新增」两条红线可执行。
- xcstrings 面：render_preview 注册形 = `String(localized:defaultValue:)`
  显式形态（EditingToolset :775-788 亲核），原位值改 + 四尾块插入的双形
  纪律与现文件形兼容；zh-audit source keys +4 对账口径成立。

### 维度 6 — 独立猎残汇总
H1-H4 / M1-M3 / L1-L4 即猎残产出；另两项**核为不涉**：
- **M-5 对话筐教训（SessionBrowserView :439 MergeDialogCount）不涉本
  plan**：该教训 = `.sheet(item:)` 首帧必须吃 item 载荷而非活态读；本波
  对话框面（pendingConflict 三选单）为 M6-1 既有面、controller 零 diff、
  plan 不触其呈现与载荷——确认零交集。
- **挂账清单对表**：T1 六项 + F-AC-4 与 `M7-2-VALIDATION §挂账单一清单`
  的 M7-3 路由行逐条吻合（①②③⑥ + F-AC-4 附项；④ CLIP 贴线与⑤
  match_color 锚两行 plan 明示不动、FIX2③ 维持 M7-4——与 VALIDATION 路由
  一致）。挂账⑤（match_color projectDirectory 同病）注意：M3 的共享
  helper 抽取**不得**顺手动 match_color provider（锚病在案、M7-4 路由）——
  helper 只搬 searchState 现逻辑，零语义变。

---

## 三、正向核实清单（防评审自身盲区，均亲验）

1. pristineOnly 默认参：9 调用点 / 5 文件静态直调，零虚分发面。
2. F-AC-2 供给链：字段 :105 + init 默认参 :125 + 消费 :1020 + probe 建立
   :370 + 调用点 :374——全链在位。
3. flock 同进程 per-OFD EWOULDBLOCK：仓内 cc-verified 在案（SingleWriterLock
   头注）——in-process 仲裁 fixture 主路径成立。
4. union 四计数点 + descriptionKeys 23 + 三集合并 + SC7 装配点坐标全吻合。
5. 错误码 16 档 / McpTimeouts 三档 / McpToolOutput 数组载体——零新增红线
   全部可执行。
6. FilterSQL `.library` 域：translate domain 参在位（FilterSQL :166-169）、
   调用点 :633-634/:673-674 吻合、FilterSQLTests 现无 .library 域测试
   （新法真 additive）、testNumericSnapshots :30-91 同型先例在位、
   keywords 物化列形有注释正本（library 域 = 材化列四子句，plan 的「同法
   补第二法」条件成立）。
7. BUNDLE-MAP 归属：FilterSQLTests=LIB（:378 + Project.swift :586 登记
   属实零登记改）/ QuickLookRendererTests=EXPORT（:256）/
   McpSearchStateToolsetTests=APP（:203）/ McpProjectArbitrationTests=APP
   （:721，序列 A/B + 双跑确定性在位）/ McpRenderParityTests=IOPP（:107，
   T6 注记正确）。
8. 顺路件六项与 M7-2 VALIDATION §挂账逐条吻合，路由（M7-4/M7-6 不动项）
   一致。
9. N2-3 闭包签名已 throws（McpSearchStateContext.fulltext :95-96）+
   noOpenProjectMessage 单源在位（:422-423）。
10. M-5 对话筐不涉（controller 零 diff，pendingConflict 面为 M6-1 既有）。

---

## 四、裁决

**须修后放行。** 修法全部为 plan 文本级（点位清单增补、谓词改写、两条
files_modified 增行、四处一句话规格钉死），不动架构、不动任务切分、不动
OQ 裁决。修毕条件（放行门）：

1. H1——快照点位清单补 5 处 + 属性/注释连带点 + files_modified 增
   McpHostTests/McpLauncherTests + 红线「searchstate 文件不改」条改写 +
   `count, 20` 零残漏 grep 入 T5 验收。
2. H2——T4 启动捕获退役范围补 library projectDirectory 锚（:194）+ 切换
   后锚断言 golden 腿。
3. H3——no-project http 臂 :267 换形 + :263/:390 两生产装配点入清单 +
   http 无 EOF 腿的 DECISIONS 句。
4. H4——判别缝谓词改 before/after 差分 + GUI 臂 held 预检（不动当前项目）
   + 仲裁 fixture 增两腿。
5. M1/M2/M3/L1-L4——按各条建议一句话钉死（arm 门控机制 / region 取整+
   clamp+边界 golden / resolveImageURL 共享抽取形 / 键数勘误 / 消费方
   清单口径 / name 来源 / seeded 内容腿）。

修订可由 planner 直接落 plan 文本（本评审 file:line 证据齐备，无需再勘）；
修订批后本 plan 无需重走全评审，仅需对放行门 1-5 逐条复核。
