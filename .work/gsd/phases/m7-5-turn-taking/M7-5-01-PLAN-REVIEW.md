# M7-5-01 PLAN REVIEW — 独立 plan 评审（替代 omp 路，零共享上下文）

```
phase:        m7-5-turn-taking
reviewee:     M7-5-01-PLAN.md（HEAD f5c23f04 = plan 自身 commit；plan 引用基线
              cbad16eb 与 f5c23f04 间为 research/plan 两笔 docs commit，代码
              零漂移——坐标核验有效）
reviewer:     独立评审 subagent（ZCode；2026-10-13/17）
method:       PLAN/CONTEXT/RESEARCH 三文档通读 + 代码面逐点亲验（McpToolError
              双 switch / Entry+writerCheck+dispatch / McpTimeouts 八档 /
              makeRegistry+四宿主+EmbeddedState box / runHeadless 三臂 /
              13 工具候选集注册点逐点 grep / union 快照全点位 + 五钉 + 残漏
              grep 扫描 / get_state control 面与既有断言形态 / 穷举测试自证
              结构 / BackgroundTaskHosting 全文 + Bar 双呈现面 /
              begin/commitContinuousEdit 全调用点 + DRT/Film 窗三族 /
              ScopePanelView 挂载门 / 禁编辑 12 面落点逐文件 grep /
              LightamerApp 装配段与菜单先例 / M7-3 H1/H4 + M7-4 F1/F2 先例
              文档 / M7-4 VALIDATION §挂账五项 / xcstrings 键缺席核对）
verdict:      须修后放行（1 blocking + 2 major + 3 medium + 3 low +
              3 info；修法全部落在 plan 文本/SC 措辞/落点清单层面，
              不动三工具+一道门+coordinator+活动卡的架构骨架——骨架
              本身经码面亲核全部可落）
```

## Findings 总表

| # | 严重度 | 任务面 | 一句话 |
|---|---|---|---|
| F1 | **BLOCKING** | T4/T6/T7 | 宿主接线形未定形且与「五钉 23 零触」红线互斥：McpHostTests 两枚 23 计数钉 + InMemory≡HTTP 等值断言（:243/:697/:719）直骑产线 `startHTTPHost`——接线落宿主函数体内即破钉（23→26），接线落调用点则 T4 的「恰五调用点（:463/:475/:579/:749 段/:988 段/:686 段）」grep 验收不可满足（六坐标≠五点）且缺省 nil = H3「静默缺席」结构回归窗——M7-4 F1 红线自相矛盾家族复发 |
| F2 | **MAJOR** | T2/T6 | live-edit 窗口径排除 DRT/Film 的机理申报为假：DrtPanelModel :24-25「Peak slider runs the D-H1 trio — beginDrtEdit → setDrtLive → commitDrtEdit」+ FilmPanelModel :193/:229——DRT Peak 与 Film 滑杆**就是拖动连续窗**（isEditingDrt/isEditingFilm），acquire 等待漏两族在飞拖动 = turn-taking 破窗；且 liveEditDepth 配对计数在视图拆卸丢 commit 时永久卡 >0 = 此后一切 acquire 10s 超时（turn-taking 永久失能）——M7-4 F2 机理为假家族复发 |
| F3 | **MAJOR** | T1/T6 | SC「四 Toolset 恰 13 处 `requiresControl: true`」计数不可达：culling write five 经共享 `registerOne` helper 注册（CullingToolset :316-:326 单 register 点 5 工具共用）——字面量实为 **9 处**（4+1+1+1+2），非 13 处——M7-3 H1 计数钉家族复发 |
| F4 | MEDIUM | T2/风险节 | get_state「golden」红窗为幻影：现码 get_state control 面断言全逐键（:910-911/:965-968/:985/:400），无键集/全 payload golden——+1 agent 键**零既有测试变红**；穷举测试 :1021 自建 16 元素数组自证（count==16 恒真）+3 case 后**仍绿**（不完备非红）——风险节「两面红至 T6」的中间红窗叙事整体失真（真实 T1..T5 无自动红窗：union fixture 默认 control nil） |
| F5 | MEDIUM | T2 | 禁编辑落点两处失真：①Undo/Redo/history 不住 MenuCommandSet.swift（86 行纯 IA 可见性函数无 disabled 面）——真身 = LightamerApp :1906-:1918（:1913/:1918 已有 `.disabled(!canUndo \|\| isReadOnly)` 合并形先例）；read_first「:1600 菜单 disabled 先例」坐标错（:1600 = project create 闭包）②delete 面不存在：全 App 无图库删除路由（LibraryGridView contextMenu = AI Upscale/Denoise 族）——files_modified 的 LibraryGridView「图库删除路由控件」为死条目，与「禁硬造点位」自相矛盾 |
| F6 | MEDIUM | T1/SC | McpToolError `message` switch（:110-120 逐 case 模式绑定）plan 未列——+3 臂为编译强制；SC grep「恰各一处 case + 各一处 code 臂」按现文本 = 每名 2 处，实为 3 处（case + code 臂 + message 臂）——SC 机检判据会把正确实现误判为失败 |
| F7 | LOW | T6 | 「14 件面外工具」计数与枚举失真：29−13 = 16 件面外；plan 枚举 copy_adjustments/render_preview/list_*/get_*/search_photos = 15 件（list_\* 六件）且漏 diff_presets——候选集精确性断言应覆盖全 16 件 |
| F8 | LOW | T3 | agent 行 Stop 路由未显式规避 `registry.cancel(id:)`（:94-98）的自动 finish 移除臂：若 bar/dialog 复用 registry.cancel，Stop 后 pinned Canceled 任务即被移除 = resume 活动连续性 UX 破 + dismiss 不可达——须明示 agent 行走 handle.cancel() 直呼 |
| F9 | LOW | 前置 | ΔN 组成与带算术不符：两新测试文件组成 ~10..13 + ~8..12 = **18..25**（union/穷举/golden 显式改 = 零新法口径），带 +14..22 下界 14 < 组成下界 18——对账式记账兜底在案，带本身建议改 +18..25 |
| F10 | INFO | T1/T4 | 「第六缝」编号 vs 真实 box 字段序：EmbeddedState context 字段序 = editing/culling/searchState/project/control——control 是第 5 个 context 字段（M7-3 的 project 未编号）；「第六缝」沿 F-4①「第五缝」血统跳号——机制同款亲核成立，建议 DECISIONS 注记一句 |
| F11 | INFO | T2 | 前置 title 行「beginCommand 边界」与 T2 action 1 API 面（admit/acquire/release/stop + liveEditActive）不一致——D-M7-5-6 边界驱动闭形下 admit 即 begin，beginCommand 独立 API 不存在；措辞统一即可 |
| F12 | INFO | T2 | coordinator → BackgroundTaskRegistry 的注入（acquire 时 register handle）未在单写点 API 清单显式列出——文件面（coordinator 文件内 AgentTaskHandle）与装配点（LightamerApp）已覆盖，补一句 init 依赖枚举即闭合 |

---

## Findings 详述（证据 + 修法）

### F1（BLOCKING）T4 宿主接线形未定形 + 五钉零触红线互斥

**证据（码面亲验）**：

- 五钉中两枚骑**产线宿主函数**：`McpHostTests.testHTTPEndToEndSDKClientRoundTrip` 直调
  `McpServerController.startHTTPHost(paths:editing:culling:)` 后断言 `tools.count == 23`
  （:243）；`testHelloConformanceAcrossThreeHostForms` 同样直调 startHTTPHost 断言
  `httpTools.count == 23`（:697），且尾段断言 `XCTAssertEqual(memoryTools, httpTools,
  "InMemory tools/list ≡ HTTP")`（:719——InMemory 臂走 4 参 makeRegistry :707-:712）。
  另 stdio 形断言（:504-507）只查成员（list_iops 在 + ping 缺）——控制域加入后幸存。
- plan T4 action 2：「五无头宿主接线：runHeadless :451 两臂 + runHeadlessArbitrated :512 +
  startHeadlessStdioHost :749 + startHTTPHost :988 + startReadOnlyHTTPHost :686——全传
  `control: makeHeadlessControlContext()`」；T4 验收 grep：「`makeHeadlessControlContext`
  恰一定义 + 恰五调用点（:463/:475/:579/:749 段/:988 段/:686 段）」。
- 红线（front-matter red_lines 第 5 条）：「union 外五钉 23 断言零触」；T6 action 11 与
  T7 红线族重复同一门。

**矛盾分叉**（两形必居其一，现文本两头都立不住）：

- **形 A（接线在宿主函数体内）**：makeHeadlessControlContext 在 :749/:988/:686 三函数体内
  恒装配（"段"字面读法）→ 三个宿主的一切调用者（含 McpHostTests 两 fixture）registry 面
  23→26 → **:243/:697/:719 三断言红灯**（InMemory 23 ≢ HTTP 26）→ 与「五钉零触」+
  T6/T7 门直接互斥——feature 落地即红灯，M7-4 F1「依现 plan 落地即死脸」同构。且 T4 验收
  「恰五调用点」仍不可满足（函数体内三点 + runHeadless 三臂是否还要显式传 = 计数歧义）。
- **形 B（接线在生产调用点，宿主函数加缺省 nil 参）**：startHeadlessStdioHost/startHTTPHost/
  startReadOnlyHTTPHost 各加 `control: McpControlContext? = nil` 透传 makeRegistry（与
  searchState/project 第四参同款——M7-3 先例形），生产调用点（runHeadless :461-464/:471-476、
  arbitrated :584-586/:596-601/:617-619、startEmbeddedServer :1111-1126 box 读出、
  LightamerApp :1608 GUI 装配）显式传 context → McpHostTests fixture 不传 → 23 保绿 ✓、
  InMemory≡HTTP 保绿 ✓、五钉红线成立 ✓。但 T4 验收 grep 的「:749 段/:988 段/:686 段」
  不可满足（函数体内零 makeHeadlessControlContext），且缺省 nil = **H3 教训的结构回归窗**：
  未来新增生产调用点忘传 control = 该宿主 29 面静默缺席（M7-3 H3 的 D-M7-3 换形清单教训
  正是「宿主缝不接线 = 工具静默缺席」）。

**修法建议（二选一，plan 明示）**：

- **推荐形 B**：T4 验收改为「宿主函数恰 +1 缺省参（三签名 diff 面核）+ 生产调用点清单
  grep（:461/:471/:584/:596/:617/:1120 + LightamerApp :1608——七点）+
  `makeHeadlessControlContext` 恰一定义 + 恰五调用点（五处**生产调用点**：runHeadless
  stdio/http 两臂 + arbitrated 一处共享 + startEmbeddedServer 一处 + LightamerApp GUI
  内嵌臂一处——执行时逐点亲核如实申报）+ 宿主函数体内 makeHeadlessControlContext 零
  命中（缺省 nil 恒不落地为静默缺席的机检面）」；H3 风险以「测试 fixture 显式不传 +
  生产清单 grep 双门」承接，并在 DECISIONS 申报「缺省 nil 的静默缺席窗 = 已知取舍，
  未来新宿主调用点须过 T4 清单」。
- 若晨审坚持形 A（恒装配 = union 单值最强保证）：红线⑤「五钉 23 零触」须显式修订为
  「三钉零触（:223/:200/:274——makeRegistry 4 参直调面）+ 两钉显式改 23→26（:243/:697，
  本波持权申报）+ :719 InMemory≡HTTP 断言 InMemory 臂同步补 control context」，T6/T7
  门与 files_modified（McpHostTests 已列 T5 注释批——须扩 T4 断言批）联动改写。

### F2（MAJOR）live-edit 窗口径排除 DRT/Film 机理申报为假 + 深度计数配对脆弱

**证据（码面亲验）**：

- plan T2 action 2：「其余 begin 系〔beginDrtEdit :737/beginFilmEdit :922〕零触面申报：
  live-edit 窗口径 = D-H1 continuous 窗，**DRT/Film 单独窗不入——它们无拖动连续态**，
  非未封合冲突窗」。
- 码面反证：`DrtPanelModel.swift` :24-25 头注原文「the Peak slider runs the D-H1 trio —
  beginDrtEdit → setDrtLive (carrier + re-render, ZERO items) → commitDrtEdit (exactly
  ONE item when the drag…)」——DRT Peak 滑杆**就是**拖动连续窗（beginDrtEdit :737 置
  isEditingDrt=true，commitDrtEdit :730 置 false，PipeCoordinator :746/:933 私有 Bool）。
  `FilmPanelModel.swift` :193/:229 beginFilmEdit/commitFilmEdit 同构（M3-3 AGENTS 节
  「D-H1 三件套走 coordinator begin/setFilmLive/commitFilmEdit」同证）。M2-6 AGENTS 节
  「Peak slider = D-H1 三件（live 零 item，松手一 commit）」同证。
- Alcedo 语义正本（research §1.1）：acquire 拒形 2 = 「UnsealedEditorInput → 等待——用户
  正在拖**编辑器滑杆**（未到封合边界）时 acquire 挂起」——语义是「任何编辑器输入未封合」，
  不限于 IOP 面板。
- 破窗时序：用户拖 DRT Peak → agent control_acquire → liveEditDepth（只计 isEditingContinuous）
  = 0 → 直通得手 → 禁编辑 12 面 disable 生效（但 SwiftUI `.disabled` 不中断已在飞手势）→
  用户松手 → commitDrtEdit 落 history item——**agent 控制期 GUI 写入**，与「用户夺回前
  GUI 编辑动作全拒」的 turn-taking 不变量冲突。IOP 滑杆同场景被等待机制覆盖、DRT/Film
  滑杆不覆盖 = 同类冲突窗保护不对称。
- 配对脆弱性：`beginContinuousEdit`/`commitContinuousEdit` 现语义 = Bool 置位（:1772/:1818）。
  改深度计数的隐患：SwiftUI 手势在视图拆卸（切图/页签切换/面板隐藏）时可能不触发
  onEditingChanged(false) → commit 丢失 → liveEditDepth 永久 >0 → **此后一切 acquire 走满
  10s 超时回 controlBusy = turn-taking 永久失能**，且计数无负值/泄漏守护申报。深度计数
  相对 Bool-OR 的唯一增益 = 嵌套窗（本 GUI 单手势单窗，嵌套不存在——:107/:114/:154/:162/
  :73/:88/:119/:122/:134/:136/:2748/:2750 全部调用点亲核为严格配对或同函数 begin+commit）。

**修法建议**：

- 口径改为三窗 OR：PipeCoordinator 恰 additive 一个 internal 只读计算属性
  `liveEditActive = isEditingContinuous || isEditingDrt || isEditingFilm`（零新可变状态、
  零配对风险、三读点全 private 既有 Bool——与红线「additive 一处、其余函数体零触」兼容），
  替代 liveEditDepth 计数；coordinator 的 liveEditActive provider 闭包喂该属性。
- 机理申报句改写：「DRT/Film 窗与 D-H1 窗同为拖动连续窗（三族 Bool），acquire 等待口径
  = 三窗 OR——Alcedo UnsealedEditorInput 全语义对表」。
- T6 acquire 三态补一条腿：「DRT/Film 在飞窗 → acquire 挂起→封合即得」（注入 stub
  provider 即可测，无 GUI 依赖）。
- 若晨审坚持收窄口径（只计 D-H1 窗）：须在 D-M7-5-7 与 plan 双处显式改申报「DRT/Film
  在飞拖动 = 已知竞态窗（disable 不中断在飞手势），接受 + GUI 走查行登记」，不得以
  「无拖动连续态」为据——该机理为假。

### F3（MAJOR）SC「恰 13 处 requiresControl: true」计数不可达

**证据（码面亲验）**：culling metadata write face 五工具（set_rating/set_flag/set_color_label/
append_note/set_keywords）经共享 `registerOne` helper 注册——`registerWriteFive`
（CullingToolset :316）内单个 `func registerOne`（:321）单个 `registry.register` 调用点
（:326），`requiresWriter: true` 单点（:338）覆盖五工具；五工具经 :369/:387/:405/:423/:436
五次 registerOne 调用进入。requiresControl 是 register() 参数（Entry 字段，descriptor 面零
新字段——红线③），故加门只能加在 helper 的 register 调用内**一处**，字面量总数 =
editing 4（:142/:147/:161/:218）+ helper 1（:326 段）+ apply_preset 1（:516 段）+
match 1（MatchColorToolset :164）+ project 2（ProjectToolset :139/:202）= **9 处**。
SC 现文本「四 Toolset 恰 13 处 `requiresControl: true`」按 grep 计数必假失败，或诱导执行者
把 write five 拆成五个独立 register（违「descriptor/handler 体零触」+ 无谓 churn）。

**附**：plan 给的坐标本身错位——「editing 4（load_image :279 / export_image :366 /
apply_params :538 / paste_adjustments :809）+ match 1 :59 + apply_preset :518」全部是
**descriptor 声明行**（`name:` 行），而编辑动作发生在 register 调用点（:142/:218/:147/
:161/:164/:516——ProjectToolset :141/:204 恰为 register 内 name 行，唯此两处贴合）。
「各 register 调用点恰 +1 行」的 action 语词与坐标面不符——执行者 grep 可自纠，但
「每 hunk 恰一行」的逐 hunk 审计面会按错误坐标核对。

**修法建议**：SC 改「四 Toolset 恰 9 处 `requiresControl: true` 字面量（write five 共用
registerOne helper 一处覆盖五工具——:326 段单点）+ 13 工具覆盖断言归 T6（registry 层
逐名 Entry.requiresControl 断言——T6 action 1/2 已有此面）」；坐标列改 register 调用点
（:142/:147/:161/:218 / :326 段 / :516 段 / :164 / :139/:202）。

### F4（MEDIUM）红窗叙事失真——get_state「golden」不存在 + 穷举测试不会自动红

**证据（码面亲验）**：

- get_state control 面的全部既有断言逐键取值：`control["lock"]`（:910/:966/:985/:984）、
  `control["holder"]`（:967/:994）、`control["writeCallCount"]`（:911/:968）——无任何
  键集断言/全 payload 串比较。`get_state` 的其余消费（McpProjectToolsetTests :237-:400、
  McpFinalSnapshotTests :209 冻结表 schema 行）均不触 agent 键。→ T2 加 `"agent"` 键后
  **零既有测试变红**——「get_state golden 自 T2 起红」为幻影；T6「get_state golden 显式改」
  指向不存在的 golden（执行者会 hunting 一个不存在的断言）。
- 穷举测试 `testMcpToolErrorCodesSixteenValuesExhaustive`（:1021-1041）自建 16 元素数组、
  断言 count==16 与 codes/expected 对表——**测试自己的数组**与 McpToolError 定义无关，
  +3 case 后测试照跑照绿（不完备而非红）。「穷举 16→19 自 T1 起红」机理不成立；T1 的真实
  强制 = `McpToolError.code`（:88-107）与 `message`（:110-120）两 switch 编译期 exhaustive
  （漏臂 = 编译错）——该强制在 T1 内闭合（T1 构建绿门要求即加臂），不构成 App bundle
  跨任务红窗。
- 真实的 T1..T5 红窗 = **无**：T1 makeRegistry 第五参缺省 nil → union fixture（makeUnionRegistry
  :251-268 不传 control）→ union 计数 ×4 全绿至 T6 显式改；T2 get_state agent 键零红；
  T4 若按形 B 接线五钉亦零红。plan 风险节「快照红窗（T1..T6 App bundle 中间态，已申报）」
  的红窗清单与真实红窗错位。

**修法建议**：风险节第 1 条改写为「**无自动红窗**——穷举与 get_state 面的既有断言在
+3/+1 后仍绿（不完备非红），守门 = T6 显式改 + 残漏 grep + DECISIONS 申报（集中一批 =
全点位亲核审计面不变）」；T6 action 10 改为「get_state agent 键断言**新法**：扩展
testGetStateHeadlessNoProjectNullsContract（:905）加 `control["agent"] is NSNull` 腿 +
新增真值 provider 腿（action 5 同文件）——既有三键断言零触即零回归门」；「禁为凑绿在
T1-T5 提前改穷举/golden」条款保留（守门理由从「红窗」改为「显式改集中审计」）。

### F5（MEDIUM）禁编辑落点两处失真——MenuCommandSet 错文件 + delete 面不存在

**证据（码面亲验）**：

- `MenuCommandSet.swift`（86 行）= 纯 IA 可见性函数（MenuCommandID 枚举 + visibleCommandIDs
  纯函数），**无任何 Button/disabled 面**；undo/redo 菜单项真身 = `LightamerApp.swift`
  :1906-:1918 `CommandGroup(replacing: .undoRedo)`，且 :1913/:1918 已有
  `.disabled(!editorState.canUndo || libraryProjects.isReadOnly)`——正是 plan 要的合并形
  先例。read_first 引「LightamerApp :1600（菜单 disabled 先例）」坐标错（:1600 实为
  project create 闭包的 probeLockAvailable 段）；菜单 disabled 先例族在 :1744-:1903。
- delete 面不存在：全 App grep 无图库删除路由（onDelete 唯一命中 = ExportPanelView 的
  导出配方删除；LibraryGridView contextMenu :188 = AI Upscale/Denoise 族；无
  deleteImage/removeFromProject 类路由）。files_modified 的「LibraryGridView.swift # T2：
  禁编辑点位——图库删除路由控件合并 disabled」为死条目——与 plan 风险节自己的
  「禁为凑表数硬造点位」自相矛盾。

**修法建议**：files_modified 的 MenuCommandSet 条目删除（或改注「零触——undo/redo 面在
LightamerApp :1906-:1918」）；LightamerApp 条目的 T2 hunk 清单补「undo/redo/history 命令项
合并形（:1906-:1918 + history 导航项）」；read_first 坐标 :1600 → :1913/:1918；LibraryGridView
条目改为「delete 面 = 我方语义缺席（无删除工具〔MCP 面 29 无 delete〕+ 无删除 UI）——
零落点申报，Alcedo 禁面语义由缺席覆盖」；12 面清单同批改 11 面 + 1 缺席申报（面数语义
清单不变，落点如实）。rating 面（LibraryInspectorView :134 `.disabled(inert)`）与 import
面（ImportModeDialog :142）落点亲核在位 ✓。

### F6（MEDIUM）McpToolError.message switch 未列 + SC grep 口径错

**证据**：`McpToolError.message`（:110-120）以 16 case 逗号连绑模式列表穷举——+3 case
不加臂 = 编译错（与 code switch 同级强制）。T1 action 3 与 SC 只写「code switch 恰 +3 臂」；
SC grep「`controlNotHeld|controlRevokedByUser|controlBusy` 在 McpToolRegistry 恰各一处
case + 各一处 code 臂」= 每名 2 处，正确实现为 3 处（case + code 臂 + message 连绑臂）。

**修法**：T1 action 3 补「message switch 连绑列表 +3 名」；SC grep 口径改「每名恰 3 处
（case 声明 + code 臂 + message 连绑臂）」。

### F7（LOW）「14 件面外工具」计数与枚举失真

29−13 = **16** 件面外；plan 枚举「copy_adjustments/render_preview/list_\*/get_\*/search_photos」
= 1+1+6+6+1 = 15（list_\* = list_iops/list_luts/list_photos/list_presets/list_bursts/
list_versions 六件）且漏 **diff_presets**（只读 diff 面也免 admit，应入精确性断言）。
T6 action 2 的候选集精确性断言按 14 件写会漏。修法：改 16 件 + 枚举补 diff_presets
（逐名免 admit 照答断言）。

### F8（LOW）agent 行 Stop 路由须绕开 registry.cancel 的自动 finish

`BackgroundTaskRegistry.cancel(id:)`（:94-98）= `await handle.cancel()` + `finish(id:)`
（移除）。bar/dialog 既有行 cancel 全走 registry.cancel（BackgroundTaskBarView :99/:150）。
agent 行若复用同路由：Stop 后 pinned Canceled 任务**立即被移除**——resume 活动连续性
（同 id 留列表复燃）破、dismiss 钮永不可达。plan T3 action 4 只写「cancel 钮 = Stop」
未指明路由；验收「agent 行 cancel → coordinator.stop() 单路由」方向正确但未排除
registry.cancel 陷阱。修法：T3 补一句「agent 行取消路由 = `handle.cancel()` 直呼
（= coordinator.stop；registry.cancel 的 finish 移除臂对 pinned 任务禁入）」+ T6 补
「Stop 后句柄仍在 registry.handles（pinned 留列表）」断言。resume 同 id 安全性已核：
`register`（:77-80）按 id 去重，resume re-register 幂等 ✓。

### F9（LOW）ΔN 组成与带算术不符

estimated_tests 组成 = McpControlToolsetTests ~10..13 + AgentControlCoordinatorTests
~8..12 = **18..25**（union/穷举/golden 显式改 = 零新法口径——即全部 ΔN 由两新文件承载）；
ΔN 带 +14..22 下界 14 < 组成下界 18。对账式 + 越带申报兜底在案（M7-4 带差 −2 如实记账
先例），但带本身建议改 +18..25 免执行期无谓「越带申报」。

### F10（INFO）「第六缝」编号 vs 真实 box 字段序

EmbeddedState（:1174-1185）context 字段序 = editing/culling/searchState/project/control
——control 是第 **5** 个 context 字段（M7-3 的 project box 字段未参与缝编号）；「第六缝」
沿 M7-2 F-4①「第五缝」（searchState）血统跳号。机制同款（box 字段 + on-leg 读出
:1095-1100/:1114-1116）亲核成立 ✓；建议 DECISIONS 注记「第六缝 = F-4① 血统编号非字段序」
一句免混淆。

### F11（INFO）「beginCommand 边界」措辞残留

前置 title 行「单写点 API acquire/stop/release/resume/admit/beginCommand 边界」与 T2
action 1 的 API 面（admit/acquire/release/stop + liveEditActive provider）不一致——
D-M7-5-6 边界驱动闭形下 admit 即 begin（seam 只承 admit，end 由下一边界闭），无独立
beginCommand API。措辞统一即可。

### F12（INFO）coordinator → registry 注入未显式列出

AgentTaskHandle 须在 acquire 成功时 `registry.register`（bar/dialog 才有行）——coordinator
的 init 依赖（BackgroundTaskRegistry 引用 + PipeCoordinator liveEditActive provider）未在
单写点 API 清单枚举。文件面与装配点（LightamerApp :1268-1390 段）已覆盖，补一句 init
依赖枚举即闭合。

---

## 亲核吻合清单（验证通过面——非 finding）

以下 plan 坐标/判据经码面逐点亲验**吻合**（fresh 坐标申报成立）：

- **registry 面**：McpToolError 16 档 :62-85 ✓；Entry :283-287 + writerCheck seam :296 +
  writeCallCount :303（仅 writer 门增计 :350——controlAdmit 不增计的插入点成立）✓；
  register :310-317 + setWriterCheck :320-322（setControlAdmit 同形机械 ✓）；dispatch
  `call` :336-353（writerCheck → handler 序，controlAdmit 插 writer 后 handler 前 ✓）；
  descriptors() 按名字典序排序（:326-330）→ control_acquire/control_get/control_release
  名序申报正确 ✓。
- **超时/错误码 additive 申报自洽**：McpTimeouts 八档 :208-226 亲数 ✓；M7-4 VALIDATION
  红线机检「McpToolRegistry.swift 含 McpTimeouts 零 diff」在案 → 「历史零 diff 后本波
  首开新档」勘误申报（D-M7-5-7）自洽 ✓；错误码 16→19 additive 持权 + M7-2 15→16 先例 ✓。
- **控制命令免 admit 自洽**：三工具 requiresControl 缺省 false → dispatch 跳 controlAdmit
  → 无递归 admit 问题 ✓（Alcedo「控制命令改变的只是控制本身」同语义对表成立）。
- **controller 面**：makeRegistry :807-829 四参形 ✓（第五参 additive 缺省 nil = 既有构造
  零 diff）；四宿主 startReadOnlyHTTPHost :686 / startHeadlessStdioHost :749 /
  startHTTPHost :988 / startEmbeddedIfPreferenceEnabled :1089 + startEmbeddedServer :1111 +
  EmbeddedState box :1174-1185 ✓；runHeadless :451 两臂 :461-464/:471-476 ✓；
  runHeadlessArbitrated :512 + :579-581 ✓；warmLutLibrary :676 ✓；makeHeadlessSearchState
  :217 ✓；**生产宿主装配点全清单亲核无遗漏**（runHeadless 三臂 + embedded 两点 +
  LightamerApp :1608 + SettingsPages :1242/:1265 经 :1111 收敛——M7-3 H3 换形清单教训
  已吸收，H3 复发风险仅在 F1 的缺省 nil 取舍面）✓。
- **13 工具候选集**：与现码工具面精确吻合——editing 9（8+match_color，注册点
  :142-:226 亲读）/ culling 14（write five 经 :316 helper + preset trio + image trio +
  bursts/faces）/ searchState 3 / project 3 = 29 ✓；候选 13 名全部在码、排除 16 件语义
  正确（计数/枚举文本失真见 F7，集合本身正确）✓。
- **union 全点位**：all29 :245 定义 + :273 引用 ✓；makeUnionRegistry :251 ✓；
  testFinalSnapshotUnion29Verbatim :270 ✓；计数 ×4 = :275/:328/:356/:510 ✓；disjoint
  断言 :311-316（六条——加 control 后 +4 = 十条 ✓）；五集合并 :318 段 ✓；
  descriptionKeys :363 ✓；:268 "exactly these 27" ✓；头注 :14-34 分代史 ✓；
  残漏 grep 面（count, 29 / count == 29 / all29 在 Mcp\* 零命中——CatalogIndexSchemaTests
  :136 的 29 属 CatalogIndexSchema 非 MCP 面，plan 的 grep 限域 Mcp\* 正确避开假阳性）✓。
- **五钉**：McpRegistrySnapshotTests :223 / McpHostTests :243/:697 / McpLauncherTests :200 /
  McpSearchStateToolsetTests :274 全部在位 ✓（但 :243/:697 骑产线宿主——F1 分叉）。
- **S-1 五坐标**：McpFinalSnapshotTests :268 + McpHostTests :466/:668 +
  McpSearchStateToolsetTests :16/:265 全部在案 ✓；S-2 让渡 = M7-4 VALIDATION 原路由 ✓；
  S-3 = §挂账④ 指名「M7-5 走查顺路补实测值」✓ + 50.2s 冷窗正本在案（M7-3
  ACCEPTANCE-2ND :173-174）✓ + test-direct.sh 中央 env 门（VALIDATION :96）与 T5
  「不设 env 直 spawn」相容 ✓；S-4 第四波 ✓；S-5 无动作（M7-4 观察项 A 已勘误在案）✓。
- **get_state control 面**：:1053-1076 ✓；McpSearchStateContext additive provider 形 ✓；
  既有三键 lock/holder/writeCallCount 值形 ✓。
- **穷举测试**：:1021-1041 ✓（plan「message 同批」已覆盖 message 数组 ✓）。
- **活动卡底座**：BackgroundTaskHandle 协议 :53 / register :77（按 id 去重——resume 同 id
  re-register 幂等 ✓）/ update :83 / finish :89 / cancel :94 / cancelAll :101 ✓；
  BackgroundTaskBarView descriptor :20 / bar :43 / dialog :113 ✓；bar 挂载 :143 +
  ToastBarView :166-167 底部 inset 共存结构 ✓（agent 行 additive 无新通道 ✓）；
  isPinned extension 默认 false = 既有三 conformer 零改 ✓。
- **liveEdit/scope 面**：beginContinuousEdit :1771 / commitContinuousEdit :1815 ✓（全部
  调用点亲核严格配对——:107/:114/:154/:162/:73/:88/:119/:122/:134/:136/:2748/:2750）；
  ScopePanelView 挂载门 :139-140 ✓；setScopeTapEnabled :2139 + ScopeThrottle :2129 ✓
  （保活三纪律的码面依据成立——采样门确为挂载可见性单源，disable-not-unmount 结构性
  保活论据成立）✓。
- **禁编辑落点（10/12 亲核在位）**：WorkspaceHostView :625/:638 export/yiyin 同点位 ✓ +
  :153 banner + :1447-1451 banner 结构 ✓；EditorWorkspaceShellView :171 stackSlot ✓；
  EditorAdjustmentStackView 容器结构可容层 ✓；EditorToolRailView :171/:180 历史列表
  disabled 点 ✓；VersionsPanelView 八处 `.disabled(versions.isReadOnly)` 合并点 ✓；
  ImportModeDialog :142 ✓；LibraryInspectorView :134 `.disabled(inert)` ✓；
  FilmstripView tap/select 面 ✓（无既有 disabled——新门位）；project 菜单族
  LightamerApp :1825-:1848 既有 disabled 先例 ✓（MenuCommandSet/delete 两处失真见 F5）。
- **装配段/单写点/正交面**：LightamerApp :1268-1390 GUI MCP 装配段 ✓（MainActor.run hop
  纪律 liveState 先例 :1458-1473 ✓）；get_state control 对象 = lock（M6-1 probe）+ agent
  （coordinator）**正交双源不同概念**——无双真相（两键各自单源：lock 读 probe、agent 读
  coordinator provider；失效场景 = provider nil → .null 诚实面）✓；coordinator @MainActor
  + F-6 provider 注入（工具体零 coordinator 类型引用）✓；与 SingleWriterLock/
  LibraryProjectController 零耦合声明与 files_modified 零交集一致 ✓。
- **xcstrings/登记**：10 新键全数缺席于现 catalog（尾块插入无冲突）✓；现有 tasks_\* 族
  31 键不受扰 ✓；UserDefaults 零新键 ✓；Project.swift 恰两行 + BUNDLE-MAP 恰两行 +
  tuist generate 恒末位（L041）✓；zh-audit 10 = 3 desc + 3 error + 4 卡面 算术 ✓。
- **基线**：3925/35/0 = M7-4 VALIDATION 三方同值 ✓；skip 35 = 5+3+5+4+9+5+4 ✓；
  HEAD f5c23f04（plan 自身 docs commit）与 cbad16eb 间零代码漂移 ✓。
- **封存面**：files_modified 与封存 17 件零交集 ✓；PipeCoordinator 非封存面、触碰限制
  「additive 一处 + 函数体零触」机检可执行（F2 修法同兼容）✓；`.metal`/SPM 红线与
  触碰面无交集 ✓。
- **Alcedo 对表**：acquire 三拒形/owner 单写点/Stop→resume（7e0c9cb）/scopes 保活
  （c7ba784）语义面与研究 §1 一致；GPL 零复制纪律（文案自写/只对表语义）在 plan 红线⑧ ✓。

---

## 总评

**须修后放行。** 架构骨架（三工具第五域 + requiresControl Entry 第三字段 + setControlAdmit
seam + coordinator 单写点 + 活动卡 pinned/activity/dismiss/resume + 无头恒真面 + union
29→32 显式改）经码面逐点亲核**全部可落**，落点坐标整体 fresh 度高（约九成坐标逐字吻合），
M7-3/M7-4 先例教训（H3 换形清单、五钉显式枚举、S 顺路件路由、对账式 ΔN）已被 plan 显式
吸收。须修的七项全部为 plan 文本/SC 措辞/落点清单层面：

1. **F1（blocking）**：T4 宿主接线形二选一明示——推荐形 B（宿主函数加缺省参 + 生产调用点
   清单接线 + T4 验收 grep 重写）；形 A 则须把 :243/:697/:719 三断言显式改入持权清单并
   修订红线⑤。现文本两头互斥，不修则执行到 T4 必红灯或必假失败。
2. **F2（major）**：live-edit 口径改三窗 OR（isEditingContinuous || isEditingDrt ||
   isEditingFilm）替代深度计数，机理申报句改写；或晨审显式接受 DRT/Film 竞态窗并双处
   申报——不得保留「无拖动连续态」假机理。
3. **F3/F6（major/medium）**：SC 计数口径修正（9 处字面量 + T6 逐名覆盖断言；每错误名
   3 处含 message 臂）。
4. **F4/F5（medium）**：红窗叙事改写（无自动红窗 + 显式改集中审计）；MenuCommandSet/
   LibraryGridView 两死条目处置 + LightamerApp :1906-:1918 真身补位 + :1600 坐标勘正。
5. **F7..F12（low/info）**：枚举/路由/带/编号/措辞校正，随批顺手。

修法不触架构、不扩错误码、不越 13 候选集、不改 12 面语义清单——全部落在「plan 文本与
SC 措辞」量级，修后 T1..T7 可直接放行执行（夜间全自动授权在案不变）。
