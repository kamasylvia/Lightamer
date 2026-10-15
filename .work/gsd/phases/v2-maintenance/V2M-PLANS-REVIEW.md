# V2M-01 / V2M-02 PLAN 评审（独立 zcode 路，2026-10-13）

> 评审身份：独立 plan 评审（替代 omp 路），零共享上下文。
> 输入 = `V2M-01-PLAN.md` + `V2M-02-PLAN.md` + `V2M-CONTEXT.md` + `RESEARCH.md`
> + 先例两份（`phases/m6-5-ledger-clearing/M6-5-01-PLAN-REVIEW.md`、
> `phases/m6-6-feature-parity/M6-6-01-PLAN-REVIEW.md` F1 可观测性教训）
> + 代码面 HEAD 亲验（下引全部 file:line 实读，非转述）。
> 实跑佐证：`zh-audit --check` 现状 PASS（1682 source / 1929 catalog /
> 30 interp keys all variant-PRESENT）；`\.runModal(` App/Sources = 0；
> `String.LocalizationValue("` App/Sources = 2（见 M-3）；单行 `Text("K \(…)")`
> 族独立复扫 = 9 处（与 planner 预扫一致）。
>
> **结论头**：
> - **V2M-01（波 1）= 须修后放行——1 error + 2 minor + 6 注记**。骨架
>   （五缺陷映射 / bisect 三段式 / 红线族 / 对账口径）成立且证据链亲证；
>   E-1 是修法机制级的（按 plan 原文执行会在不存在的挂点上空转或交付带回
>   退窗的半修），修订不改变任务序与量级。
> - **V2M-02（波 2）= 须修后放行——1 error + 4 minor（M-3/M-4 与波 1 共账）
>   + 注记**。E-2 是 V17 门语义级的（推导供给面不足使两 plan 交叉引用的
>   「D-5 绿例活体」不可交付 + 多参键集合式判定有位置洞），修订限于 T1
>   action 与 self-test golden 清单。

---

## 一、findings

### E-1【error｜V2M-01 T1】`updateInstance` 兑现方案的挂点不存在于 provider——刷新点清单还漏了拖动 commit 尾

**证据链（HEAD 亲验，全链闭合）**：

1. **钩子实现缺席确认**：`updateInstance` 全仓 grep 仅 1 命中 =
   `ColorMatchPanelModel.swift:54` doc comment（"the model refreshes
   through `updateInstance`"）——plan 论断成立，兑现该钩子 = 修法正形，
   这半步无疑义。
2. **「由面板 provider 在 instance 参数变化时调用」在架构上不可实现**：
   - provider = `ColorMatchPanelProvider`（ColorMatchPanelView.swift:21-28，
     `IOPPanelProvider` 的 `panel(for:edit:)` 值工厂）——它只在
     `InspectorState.panelView(for:edit:)`（InspectorState.swift:218-220）
     被 InspectorView body 求值时调用（InspectorView.swift:341），**返回
     view value，不持有 model**；model 是 ColorMatchPanelView 的
     `@State`（ColorMatchPanelView.swift:39），只在 `.onAppear` 一次性
     创建（:47-52），view 身份无 `.id()` 锚——**实例/参数变化时 @State
     model 存活、其 `instance` 属性滞留创建时值**。
   - 在 body 求值期（即 provider 被调用的时点）调 `updateInstance` = 
     view update 期副作用（正是本修法要消灭的形态类别）。
   - `InspectorEditSession`（IOPPanelProvider.swift:54-83）只有
     begin/update/endEditing 三动词，**无任何实例变更通知面**。
3. **刷新点清单不全**：plan action 1 列 ①init ②实例切换/revision 钩子
   ③solve 尾（:185 `liveParams = nil` 处）。**漏了
   `commitStrengthDrag()`（:231-234）**——commit 置 `liveParams = nil`
   后 getter 落到快照层；若快照未在 commit 尾刷新，滑杆/读数回跳拖动前
   值一帧以上（等外部钩子补刷）。plan 自己的 Checker #3 点名「checker
   反向找漏刷新路径」——本条即该反向核的产出，但 action 清单应直接补全
   而非留给两层下游再发现。
4. **外部写腿覆盖依赖挂点形态**：colormatch params 可经 MCP
   `apply_params`（14-2 T2 面，SessionBatchApplier 直复）改
   `editorState.instances`——快照化后唯一不失明的覆盖方式 = 挂点键在
   **instance 值**（InspectorView 随 editorState 重渲 → 新 instance
   value → 钩子触发），而非「provider 动作」。

**修法（plan 修订三处，量级不变）**：

- action 1② 的挂点改写为 **view 级 seam**：`ColorMatchPanelView` 内
  `.onChange(of: instance) { model.updateInstance(instance) }`（或
  `.task(id: instance.paramsHash)`）——`ModuleInstance` 已是
  `Equatable, Hashable`（ModuleInstance.swift:44），`instance` 是
  InspectorView 每次重渲都携新值的 `let`（:32），该 seam 天然覆盖
  实例切换 / commit 后的重渲 / 外部 MCP 写腿三类路径；
- 刷新点清单补第④点：**`commitStrengthDrag()` 尾**（清 `liveParams`
  的同批从末次 live 值或重读 record 刷快照——action 上下文非 layout 期，
  此处读 coordinator 不违修法本意）；
- 风险节的回退预案（coordinator revision 通知）保留不变。

### E-2【error｜V2M-02 T1】V17 specifier 推导供给面按现文交付不出「D-5 绿例」——且多参键的集合式判定有位置洞

**证据链**：

1. **交叉引用的绿例不可交付**：V2M-01 T5 头注「V17 specifier 深检落地
   后此键成为绿例活体」+ V2M-02 Checker #2「checker 用波 1 修后树干跑
   `--check`：`toast_hdr_merge_done %lld` 应为绿例（Int 插值推导 %lld
   与目录一致）」。但修后调用点 =
   `Int((holeFraction * 100).rounded())`（LightamerApp.swift:2019，
   `holeFraction: Float` 是**函数参数**——:2017
   `refreshGridAfterMerge(holeFraction: Float)`）。plan T1 的推导供给面
   写的是「**字面变量声明类型** + 简单算式传播」——函数参数声明不在
   字面义内，`Int(…)`/`.rounded()` 包装是调用形传播不是「简单算式」。
   按现文实现，该键落 EXEMPT（不红但非绿）→ Checker #2 的「应为绿例」
   无从核起 = F1 同类「验收机制不可观测」问题在波间的再现。
2. **多参键位置洞**：plan 断言 6 判定式写「目录变体 specifier 集合 ∩
   推导类型集合 = 空 → 红」。集合交集对多参键失真：插值
   `[String, Int]` vs 目录 `%lld %lld` 的类型集合交集
   `{%lld} ≠ ∅` → 放行，实际逐位错配。在册多参活体即有
   `settings_catalogs_rebuild_progress %lld %lld`（两处调用：
   SettingsPages.swift:1406 / CatalogBrowserView.swift:71）、
   `session_counts %lld %lld %lld`（SidebarView.swift:372）、
   `toast_import_partial %lld %lld`（LightamerApp.swift:943）——门一上
   线就要面对的形态，判定式必须有序。
3. **self-test golden 负测清单缺口**：现列四例（spec 错配红 / Text 族
   无变体红 / 跨行绿 / 豁免例）——缺①位置错配红例 ②Int 家族宽度的
   正例（`mcp_launcher_status_running \(pid)` 的 pid = **Int32**，在册
   变体是 `%lld`，M6-6 rider 亲证——映射表须写明全 Int 族 → `%lld`）
   ③Float 与 Double 同映射 `%lf` 的正例（D-5 样本即 Float→`%lf`）④
   注释免疫例（`LightamerApp.swift:2061` 的 doc comment 内含插值禁形
   字面——V15 form 1c「注释行保持 pending」逻辑已在，V17 新增的 Text
   族 regex 必须同款免疫，否则新误报源）。

**修法（T1 action 三处补钉）**：

- 推导供给面显式扩为：`let/var` 声明 + **函数参数声明** +
  简单算式传播 + **`Int(…)` 包装调用形**（覆盖 `.rounded()` 链）；
  其余（跨文件/泛型/协议/元组成员）EXEMPT 不变；
- 断言 6 判定式从「集合 ∩ = 空」改为**逐参有序比对**（长度不等或任一
  位错配 = MISMATCH）；
- self-test golden 增上述四例；V2M-01 T5 头注的「绿例活体」措辞与
  V2M-02 Checker #2 同批生效（两 plan 一次修订对齐）。

### M-1【minor｜V2M-01 T4】主修形态对 plan 自列的两候选机制都不鲁棒——机制定案排在修法之后

- 亲验事实：`pendingTargets` 在 SessionBrowserView.swift **无任何清空
  路径**（全文件仅 7 次 arm 写 :152/:157/:168/:180/:191/:199/:205 +
  捕获读 :267/:291/:325/:354/:382/:411 + @State :433）——「live read
  取 0」因此几乎不能是「数组被清空」，只剩 plan 自列的两候选：视图
  身份/状态店重建（@State 同灭——主修 `@State pendingTargetsCount`
  **同样同灭**）或呈现事务对写前 view value 的陈旧快照（sheet 闭包捕
  捉旧值——快照属性**同样陈旧**）。而 GUI-M6C-13 的合并动作以正确
  targets 跑通（`let targets = pendingTargets` 在按钮 tap 时捕获成功）
  ——状态店未整体失效，机制进一步收窄到「呈现时点快照」族，两种存
  活假设下主修都有相当概率非修。
- 验收兜底在案（走查 AC 要求三对话框标题计数正确——非修过不了门），
  故只损失一轮返工、不产假交付 → minor。
- **修法（二选一）**：①把 action 3 的机制走查提到 action 1 之前
  （先定案再择形）；②直接换机制鲁棒形态——arm 时构造 payload
  （targets + count）走 `.sheet(item:)` 呈现携带，标题读 payload，
  与状态店/呈现快照两机制解耦。plan 风险节的「快照上移」预案保留。

### M-2【minor｜V2M-01 T2】fixture 级回归钉的具名路径 `Tests/Fixtures/` 与仓内两 tier 供件先例冲突

- 亲验：`Tests/LightamerTests/Fixtures.swift:8-24` 明文两 tier 设计——
  小 raster 走 `Resources/TestFixtures/**` 资源 glob（Project.swift:193
  等 9 处），**真机 RAW 样张明确 NOT tracked / NOT bundled**（~1.2GB
  留 `.work/plans/01-05/samples` untracked + 三级搜索序 + 缺席
  XCTSkip——RAW03Tests 即此口径，BUNDLE-MAP :175「无样张环境
  XCTSkip——skip 对账」）。TiffRaster/（现 612K）全为小 TIFF。
- plan 具名 `Tests/Fixtures/` 落缺陷 RAW 样张 = tracked 多 MB 二进制
  进开源仓 + 违背两 tier 成文设计；落 `Resources/TestFixtures/` 则
  glob 使其乘 7 bundle（:359 注释「~6.2 MB each」即体积敏感先证）。
- **修法**：fixture 级主路径改指既定 untracked 供件机制
  （`LIGHTAMER_RAW_SAMPLES_DIR` / TestRAW 镜像 / .work samples 搜索序
  + 条件 XCTSkip，钉在 RawDecodeOverridesTests/RAWDecoderTests），
  「钉规则不钉文件」降为第二选项；`Tests/Fixtures/` 直落仅当样张确
  能裁小（同机身小样张通常仍 MB 级，不成立）。红线 `Project.swift`
  零 diff 三种路径下均可保。

### M-3【minor｜两 plan 红线】`String.LocalizationValue("` 插值禁形零命中——现树有两处命中（一注释一代码），battery grep 需钉形

- 亲验实跑：①`LightamerApp.swift:2061`——doc comment 内含插值形态
  字面（V14/FINDING-G 的旧形注记，:2058-2065）；②
  `ExportInspectorView.swift:433`——`String(localized:
  String.LocalizationValue("export_format_" + kind.rawValue))` 代码在
  用（**拼接形**动态查表键，M2-9 F-2 同族行为但非插值字面）。
- 两 plan 红线均写「`String.LocalizationValue("` 插值禁形零命中」无
  「代码/注释/插值形」限定——T6 干跑按字面 grep 会双命中。
  M6-5-01-ACCEPTANCE.md:128 的在册先例写法 = 「禁形**代码**零命中」。
- **修法**：两 plan 红线条补齐限定（「插值字面形、代码行、非注释」）
  或登记两条已知豁免锚（:2061 注记 / :433 拼接形在用）；
  :433 是否顺带 V17 化（改显式 switch 静态键，V14 先例）由执行批裁量，
  非本批义务。

### M-4【minor｜两 plan front-matter】ΔN 预期带下界与分任务组成不闭合

- V2M-01：`+3..5` vs 分任务 `T1 +1..2 / T2 +1..2 / T3 +0..1` → 算术
  下界 = 2。仅当 T1 的两个具名测试（①快照刷新 ②优先级负测）都视作
  必做（即 T1 实为 +2）时带才自洽——建议 T1 直接写 `+2` 或带宽改
  `+2..5`。
- V2M-02：`+0..6` vs `T3 +0..2 / T5 +2..4` → 下界 = 2；T5 是波尾固定
  范围非容量门任务，`+0` 不可达。建议改 `+2..6`（T3 销账形态另记）。
- 对账语义本身无恙（T6 按 `== 基线 + ΔN 实记账` 精确判，不符即停），
  纯账面精度修订——M6-3 minor-1 同源滑差先例，执行前订正防对账自扰。

### M-5【minor｜V2M-02 T5】`collisionPolicy 同位`与 REQUIREMENTS :401 字段清单及 M3-1-03 会话态裁定的张力未裁

- 亲验：REQUIREMENTS.md:401 预设字段清单 =「格式/质量/位深/sizing/
  元数据策略/ICC/命名模板」——**无冲突档**；M3-1-03 KD-1 裁定
  collisionPolicy = Export 页会话态（「页关即复位……非持久 = KD-1
  裁定，跨会话记忆属新挂账」）；而 V2M-02 files_modified 的
  ExportState.swift 行写「预设存取 + 套用投影 + **collisionPolicy
  同位**」——若预设捕获冲突档 = 静默开立 M3-1-03 挂账的「跨会话记忆」。
- **修法**：T5 范围句显式钉死——预设**不捕获** collisionPolicy（推荐，
  与 :401 清单及 M3-1-03 对齐；套用只动面板态，冲突档仍由用户显式选
  ——plan 风险节 T5 的推荐语义本就如此，files_modified 措辞同步收
  口即可）；执行批若要捕获 = 先修订申报。
- 顺带一注（不另立 finding）：预设捕获「命名模板选择」时，模板后被
  删的悬挂引用应 typed degrade（NamingTemplateStore 三内置 + Custom
  回落先例），建议列入 T5 的「变体字段逐项落位」测试面。

### M-6【minor｜V2M-02 T2 × V2M-01 T1】GUI 批行清单两处口径毛边

- **06 行去重歧义**：V2M-01 T1 写 06 行「挂 V2M-02 T2 走查批（或 D-2
  修复后本批内补走，按 D-2 先后定）」，V2M-02 T2 行清单含 06 但只在
  03/05/08 给了「波 1 已走则以波 1 证据为准不重跑」条款——06 需同款
  条款，防双走。
- **供件矩阵孤儿项**：T2 供件矩阵列「layer B 资产」，但行清单无消费
  者——唯一消费行是 GUI-M6C-30（layer B patch 真图，MANIFEST :63 行
  Blocked-Env：assetStatus=notReady），未入行清单也未给排除理由。
  按批内哲学（供件缺席行如实记 Blocked 保持）应二选一：纳入 30（SAM
  资产到位即可走）或删供件项/注记排除理由。行清单对其余三处静默排除
  （10 Registered-obs 无判据 / 14 Blocked-Env 双通道缺席 / 31 真多人
  素材）与「波 1 解锁后可达」准入判据自洽，不构成缺口。

---

## 二、注记（不要求修订，执行批知悉）

### N-1 T2 解码探针的依赖闭包宽于 M2-7 先例

RAWDecoder.swift（621 行，系统框架 import）引用 AppError /
RAWTechnicalOverrides / DecodedImage / CIRAWDecoderVersion /
RasterDecoder 等跨文件型；且 `decodeRAW` 为 private——探针走 public
`decode(_:technicalOverrides:)`（:120 UTI 路由）会把 RasterDecoder 拉
进闭包。M2-7 方法论（单文件级 Core 源 + shim + `.metal` 运行时
makeLibrary）可承但 shim 集合按此宽度备料；`.forceV8` 请求形态在册
（`RAWTechnicalOverrides.DecoderRequest`，resolveDecoderVersion 三臂
switch 亲读）。七步其余各步供件/证人核实：`/Applications/AlcedoStudio.app`
在位（第 7 步可执行）；供件门降级链（同机身样张 → 停在 transcript
上报）完整。

### N-2 T1 静态机检 AC 的形态

「params/currentRecord getter 函数体内零 `pipeCoordinator` 触达」非裸
grep 可表达（函数体作用域）——plan 已自带「DECISIONS 附改后文件段锚
定」条款，配 GUI 三行走查 + 单测双观测点，满足 F1 可观测性教训；维持
原文即可。

### N-3 zh-audit 现状与 CONTEXT §二 双保险吻合

`--check` PASS（1682/1929/30 all PRESENT）；catalog 1929 = M6-6-01
PLAN-REVIEW F1 预测值；McpLauncher 三键 `%lld` 变体 PRESENT
（xcstrings:32369/:32386/:32403 域）——CONTEXT §二「首跑报 ABSENT 即
勘误有误」的双保险前态确认。V17 首跑的红面将**只**来自新开的 Text 族
ABSENT 门——单行 9 处中亲验活体 ABSENT 恰 1 键
（`catalog_session_remove_confirm_body %@`；近邻
`session_orphan_remove_confirm_body %@` PRESENT），与 planner 预扫一致。

### N-4 行号精度总评（亲验全对）

两 plan 引用锚全部实读命中：SessionBrowserView :280/:305/:340 + 七
arm 点；EditorWorkspaceShellView :94-96/:101-109/:117-123/:178；
LightamerApp :2019（`toast_hdr_merge_done \(holeFraction * 100)`）；
xcstrings:2072（裸键）/ :23513（`%lld` manual 变体，en/zh 整数百分数
语义——D-5 Int 化偏离 RESEARCH「补 %lf 变体」的申报**成立**：目录值
即整数语义，`%lf` 变体反而渲染「12.340000%」劣化，偏离已在 T5 头注
+ Checker #6 双处显式申报）；zh-audit.py :358-367（断言 5 + 「Specifier
deep-checking stays manual」）；ColorMatchPanelModel :54/:99-111/:185/
:208-215；FilmPanelModel :62-71 / DrtPanelModel record getter（纯
history 扫描 + carrier dict，无 per-read JSONDecoder——HistoryStack
:521-536 亲读；FilmPanelTests / DrtPanelModelTests 在位，孪生三分的
「定向测试全绿」 clause 可满足）；PipeCoordinator :1667-1669 线性扫 +
ModuleInstance.params(of:) :146-152 每次 `JSONDecoder().decode`——
D-1 根因链全部坐实。

### N-5 EXPORT-PRESET-01 接缝亲核（简报第 4 维问点）

接缝全在位：`ExportState`（State/ExportState.swift:23 @Observable，
六记忆键 + makeRunAssembly :492/:541 collisionPolicy 形参）；
`ExportM2PanelModel` + `makeRunAssembly`（ExportInspectorView.swift
:709/:1006，M3-1-03 纯缝范式在位）；`NamingTemplateStore`/
`ExportFileNameTemplate`（Export/NamingTemplates.swift:5/:27）。plan
形态 = 预设层为新面（ExportState 扩展 + 新 UserDefaults 键）+ 命名
模板作为既有引擎**被引用不复制**——与 RESEARCH §F「逐项记忆键是数据
基座，加层不撞键族」一致，无引擎二写风险。六键族
（lastDirectory/jpegQuality/heicQuality/avifQuality/webpQuality/
namingTemplates）与新键候选 `export.presets` 零撞。悬挂模板引用边缘
见 M-5 顺带注。

### N-6 bundle 归域与基线

BUNDLE-MAP 亲核：ColorMatchPanelModelTests = APP :289 ✓ /
RawDecodeOverridesTests = IOP :181 ✓ / FilmstripModelTests = LIB :382 ✓
/ SessionBrowserModelTests = SESS :397 ✓；test-direct.sh:165 合法
token = (IOP IOPParity Layers Library Sessions Export App)——两 plan
所用 token 全合法（M6-5 评审 M-1 的 LIB/SESS token 错误已在这两 plan
免疫）。基线 3848/24/0 = M6-5 SUMMARY :40 三路亲跑同值 ✓。Sessions/
LIB 测试 `@testable import Lightamer`——App 源变更在这些 bundle 的编
译面被覆盖（T4 仅跑 Sessions 仍有编译防线）。T4 零新键声明成立：
`focus_stack_dialog_title %lld` / `stack_denoise_dialog_title %lld` /
`hdr_merge_dialog_title %lld` 三变体亲证在册。

### N-7 两波交接与条件任务

V2M-02 baseline = 「V2M-01 终值（以 T6 全套轮实测为准）」+ T6
`TOTAL == 波 1 终值 + ΔN₂` 对账式——引用链 3848 → +ΔN₁ → 波 1 终值
→ +ΔN₂ 逐环可追 ✓。D-5 条件并入判定 = grep 调用点形态，可机检 ✓。
GUI 走查提前口（OQ-VM-5）边界干净：走查 local-only 零 commit、零源
码面，V2M-02 T2 红线「T2 时窗内逐 commit 核源码零 diff」可核 ✓。
PATCH-LIVEPLANE 余量盘点判定物具体（M6-4-VALIDATION :146 D-13 两笔
原文 + `b49215bb` diff 亲读——stamp+身份比对消费缝已落，残差归零与
否可对表）；RELEASE-DIRECT-INJECT 配方实证链完整（perf.md §事故 4
:55-61 + m6-closeout MANIFEST :59/:108 P1 探针 rc=0）。容量门非机检
判定，但默认落点已注册（容量不足原样留挂账、登记不销账）——可接受。

### N-8 T3 复现加固判据可再钉半格（不强制）

「N 轮零卡死」的逐 click 判据建议钉成可脚判形式：每 click 后 AX 读
画布 imageURL（或 sidecar 解码日志行）== 预期 URL；plan 现文「记录
每次画布 URL/sidecar 解码日志」已含材料，仅判据句可再实一声。概率
缺陷的诚实置信条款（不可稳定复现 → 大 N 零复现 + 机制论证 + DECISIONS
置信声明）在案，充分。

---

## 三、放行面复核结论（逐维度对简报七问）

1. **T1 修法面**：根因链与修法方向亲证成立；挂点机制错位 + 刷新点
   缺口 = E-1（唯一必修）；多实例切换/外部写腿覆盖随 E-1 修法（view
   级 instance 值键控 seam）一并解决；「layout 期零观察读取」的机检
   缝 = 形态级 grep + DECISIONS 段锚 + GUI 走查 + D-H1 硬门，可测性
   边界（XCT 不可达）如实申报，N-2 维持。
2. **T2 D-2 面**：七步配方逐步可执行（供件门三级降级 + Alcedo 证人在
   位）；「修法留执行批裁定」的验收 = transcript + 定向轮 + 回归钉 +
   复验证据四观测点，无不可判定 AC；供件门「不硬造」+ 停手上报完整；
   fixture 路径按 M-2 重指。探针闭包宽度知悉（N-1）。
3. **T3/T4/T5**：T3 三腿钉序嫌疑缝行号全对、加固策略充分（N-8 可选
   加钉）；T4 三 sheet 同族一致、零新键成立，主修形态鲁棒性按 M-1
   处置；D-5 偏离申报成立（N-4 内证）。
4. **V2M-02**：V17 门语义按 E-2 补钉后自洽（豁免登记 + 禁误报 +
   self-test 负测扩四例）；T2 行清单/供件矩阵按 M-6 收口；容量门/
   余量盘点判定物具体（N-7）；EXPORT-PRESET-01 接缝为复用引用非新
   引擎（N-5），collisionPolicy 张力按 M-5 钉死。
5. **两 plan 交接**：对账链 + 条件任务 + 提前口边界全数成立（N-7）。
6. **SC 机检性**：两 plan SC 逐条有观测点（grep/diff 形态/脚本判据/
   走查证据/transcript），无 F1 型「不可观测验收」残留——E-2 是唯一
   跨 plan 的可观测性缺口，修法明确。ΔN 算术 M-4 顺手订正。bundle
   归域全对（N-6）。
7. **独立猎残**：E-1/E-2/M-1/M-3/M-5/M-6 均为简报维度外/深挖产出；
   未发现结构性驳回项（波次切分、批次治理、红线族、暂停开关
   config.toml `auto=true/paused=false` 现值复核无误）。

## 总评

**两 plan 均须修后放行**。证据纪律是这两份 plan 的突出强项——全部
file:line 锚亲验命中（N-4），先例教训（M6-5 M-1 token / M6-6 F1 可观
测性）已明显被吸收；两处 error 均为机制/判定式精度级（E-1 = T1 挂点
重指 view 级 + 补 commit 尾刷新点；E-2 = V17 推导供给面扩形 + 有序比
对 + golden 四例），修法明确、量级不变、不动任务序与批次治理。波 1
修订后可先行派发（E-1/M-1/M-2/M-4 波 1 侧条目）；波 2 修订（E-2 与
波 1 的绿例措辞联动、M-3/M-5/M-6）可与波 1 执行并行完成。
