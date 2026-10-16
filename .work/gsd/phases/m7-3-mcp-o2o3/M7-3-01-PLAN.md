---
phase: m7-3-mcp-o2o3
plan: "M7-3-01"
title: "MCP O2 反馈回路 + O3 项目与版本单 plan——T1 顺路件六项（F-AC-1 FilterSQL .library 快照新法 / F-AC-2 headless probe 透传 / N2-1 pristine truncated 键 / N2-3 fulltext 窄竞态 typed 抛 / N2-4 requestFailed 显式臂 / ⑥DECISIONS 句 + F-AC-4 注释随 union 批）/ T2 QuickLookRenderer.renderedPlane pristineOnly additive 默认参（全消费方零 diff 负测）+ render_preview region 归一化 0..1 裁剪 / T3 compare 默认 root 双臂内联（零新 render 代码——两臂各走 renderedPlane verbatim）+ list_luts 三件只读投影（editing 域 6→7）/ T4 第四域 ProjectToolset（project_open/create + list_versions sidecar 单源 + 无头运行时开项目缝 + EOF watcher 幂等 arm + get_state per-call 重取 + projectReadOnly(holder) 判别缝）+ requiresWriter + 错误码零新增 / T5 测试批（union 23→27 全点位显式改——本波持权 + 四域分层 + render_preview schema 两层同批 + 新工具 golden + 既有 23 工具零回归）/ T6 定向轮（App+Library+EXPORT）+ 全套 --all（批准制）+ 红线族 + 收口翻账"
wave: 1
depends_on: []
autonomous: true
requirements: ["REQUIREMENTS MCP2-04..07（:434-437，→ M7-3）+ ROADMAP §M7-3 行（验收形态三条：compare/region golden / project 工具与单写者锁仲裁 fixture / 快照族零意外 diff）", "OQ 裁决正本 = phases/m7-3-mcp-o2o3/M7-3-CONTEXT.md（D-M7-3-1..10 全按 RESEARCH §7 推荐，站 charter 授权落定，晨审可推翻）", "调研正本 = phases/m7-3-mcp-o2o3/M7-3-RESEARCH.md（§2 现状测绘 / §3 四件语义 / §4 顺路件六项 / §5 集成缝 / §6 测试策略；file:line 经 planner 批 2026-10-17 HEAD 217999a5 逐点亲核复核吻合）", "M7-2 挂账单一清单六项 = phases/m7-2-mcp-o1/M7-2-VALIDATION.md §挂账（本波 T1 收口；FIX2③ 维持 M7-4）", "夜间全自动授权在案（先例 D-07-3-T5-1；晨审可推翻）"]
success_criteria: "SC 全可机检——T1：FilterSQL .library 域快照新法绿（rating gte / flag eq / iso lt / captureDate gte / focalLength between / keywords contains 六断言 WHERE+bind 串 ≡ 现字节——FilterSQLTests，Library bundle）+ F-AC-2 = makeHeadlessSearchState 加 projectWriteProbe 默认参（缺省 nil = 既有测试构造零 diff）+ :374 调用点传既有 probe + headless get_state.control.lock = verdict 真值断言（writer 臂 self-held writable）+ N2-1 = pristine payload 恰 +1 键 truncated:false（:833-846 十二键→十三键——L1 勘误，亲点 12 键）+ pristine golden 字节同批更新 + N2-3 = fulltext 闭包 guard let store else 静默空 → typed notSessionMember(noOpenProjectMessage)（负测：nil 载体调 search_photos mode=fulltext → notSessionMember）+ N2-4 = requestFailed 臂 → modelUnavailable 断言（F-3 四案闭合）；T2：renderedPlane additive 默认参三判据——①缺省调用 ≡ 显式 pristineOnly:false byte-equal（default 值恒等负测）②pristineOnly:true 输出 ≡ 同图无 sidecar 副本缺省渲染 byte-equal（同一空链分支自证）③QL pane :123/:171 + McpRenderParityTests :221/:262/:543 + McpMatchColorParityTests :158 + QuickLookRendererTests :206/:227（除新负测——L2 口径：全消费方 9 调用点/5 文件）调用点零 diff（git diff 面核）——QuickLookRendererTests（EXPORT bundle）定向绿 + region 判据（T5 golden 预支：归一化 rect × 渲染尺寸 round+clamp ≡ 手算像素框〔两边界腿 x+w==1.0 精确 / 亚像素 w——M2〕 / w≤0|h≤0 → invalidParams / 越界 → roiOutOfBounds / region 同 rect 作用于双臂）+ schema JSON 恰 +region 属性；T3：schema 恰 +compare 属性（enum none|root 默认 root）+ compare:root 双臂 = 同一 boundedWait 窗内两遍 renderedPlane（pristine 臂 pristineOnly:true）+ 输出内容序 [current, root, text] 断言 + summary JSON {current:{w,h},root:{w,h},compare:"root"} + list_luts 零入参 readOnlyHint:true + 出参 {libraryRoot,total,luts[]} 恒等式（≡ installedNames/entry(named:) 直调——T5 golden）+ description 一句「key 即 lut3d lutName 寻址键」+ 两工具 description 分界句（detail_crop=源细节原生分辨率 / render_preview region=渲染观感 ROI）+ xcstrings render_preview 原位值改 + list_luts 新键尾块插入；T4：makeRegistry 恰第四参 project:（缺省 nil = 既有构造零 diff 负测——三参调用编译零改）+ 三工具注册（project_open/project_create requiresWriter:true；list_versions 缺省 requiresWriter:false + readOnlyHint:true）+ 错误码零新增（McpToolError 封闭表零 diff——invalidParams/projectReadOnly/internalError/serverReadOnly/notSessionMember 全既有）+ 无头运行时缝 = current-project 盒（锁保护值盒）+ liveState per-call 重取（盒空 = no-project null 面逐字节；盒持 = 真值）+ EOF watcher 抽取共享 armStdioEOFReleaseOnce()（幂等 once guard + arm 内部 mode==.stdio 自守卫〔M1〕——启动路径 :353 行为逐字节不变 + 运行时 open 成功后 arm；grep 双调用点）+ no-project stdio/http 两臂（:254-256/:263-267）换盒读 closure 形（open 前 = 既有 bare context 行为逐字节）+ 生产宿主调用点全清单（runHeadless :254/:263 / runHeadlessArbitrated :378/:390/:410）传 project provider（裸 McpSearchStateContext() 在 controller 内零命中 grep——H3）+ makeHeadlessSearchState library seam projectDirectory 锚 :194 改盒读（A→B 切换后解析锚随盒——H2）+ GUI 内嵌臂 provider MainActor hop controller 路由（held 目标 probeLockAvailable 无持有预检——held → typed projectReadOnly(holderSummary) 不动当前项目；判别缝 = before/after 差分：pendingConflict 调用前 nil ∧ 调用后非 nil ∧ projectStore 未变化 → projectReadOnly(holderSummary)——H4）+ projectReadOnly 判别缝负测 + controller 文件零 diff（git diff 面核）；T5：union 显式改全点位亲核——冻结表 render_preview schema 行 + list_luts 行 + project 三行 + 计数断言 ×4（:209/:246/:274/:421）23→27 + 组合代数四集合并 + descriptionKeys +4 行 + makeUnionRegistry 传 project fixture context + SC7 startHTTPHost 传 fixture context + F-AC-4 注释 :210 非易碎形改写 + 测试名 Union23→Union27 + all23 属性名→all27（:184-186 定义 + :207 引用）+ 过时计数注释/message 同批（头注 :15/:22 + :209 断言 message + McpRegistrySnapshotTests :30 docstring）+ union 外五处计数钉显式改（McpRegistrySnapshotTests :194 / McpSearchStateToolsetTests :270 / McpHostTests :243/:696〔:718 memory 臂 ≡ httpTools 随行〕/ McpLauncherTests :200——20→21 + message 同批，H1）+ MCP 测试面 count, 20 / all23 零残漏 grep + editing 层（McpRegistrySnapshotTests）render_preview 行 + list_luts 行 6→7 显式改（两层 consciously change together——M5-1-03 先例形）+ project 域新层（McpProjectToolsetTests：三工具 verbatim + 计数 27 分账 + 白名单负测 + 锁仲裁 fixture〔held→typed projectReadOnly+holder summary / 释放→自然恢复 / 自持切换 checkpoint 腿 / create 已存在拒 / folder 缺失拒〕+ list_versions golden〔三版本 fixture byte-equal / includeItems 两档 / 500 帽保新端逐版本 / 双地址臂 / ACTIVE 链 items ≡ get_history 同源〕）+ region/compare/list_luts golden（McpEditingToolsetTests additive）+ 既有 23 工具 descriptor 零 diff（除 render_preview 申报内字节）+ Project.swift 恰一行 + BUNDLE-MAP 恰一行 + tuist generate 恒末位 + --bundle APP 全绿；T6：--bundle App+Library+EXPORT 定向轮绿 + 全套 --all = TOTAL|3877+ΔN/35/0| 对账精确闭合（exit 0 / 0 MEMFAIL / 七 bundle 8G 门内）+ 红线族逐条机检 PASS + zh-audit --check PASS（4 新键 + 1 原位改）+ --self-test PASS"
estimated_tests: "+12..20（research §0.5 带；T1 批 ~3..4〔F-AC-1 新法 + N2-4 臂 + F-AC-2 真值断言 + N2-3 负测；N2-1 = 既有 golden 字节更新零新法〕/ T2 批 ~2..3〔pristineOnly 恒等负测两法 + region 解析负测〕/ T5 批 ~8..14〔region/compare/list_luts golden + project 域快照 + 锁仲裁 fixture + list_versions golden + union 全点位〕；执行时逐任务如实记账，越带申报）"
test_bundles: [APP, LIB, EXPORT]
baseline: "3877/35/0（M7-2 三路全套同值；其后 cb8a47de〔VALIDATION 签核〕+ 217999a5〔M7-3 research docs〕两跳 docs-only 基线零漂移；HEAD 217999a5 planner 2026-10-17 亲核 git log/status——其上零产线文件）"
expected_all: "3877 + ΔN（对账式；ΔN 预期带 +12..20，执行时按实记账；skip 35 口径维持——第三种 skip 来源 = 逐族差分申报禁静默吸收）"
red_lines:
  - "零新 SPM 依赖（Project.swift dependencies 块零 diff）"
  - "MCP 快照族显式改——本波持 union 文件（McpFinalSnapshotTests.swift）改动权（M7-2 VALIDATION 特殊事项 5 移交）：union 23→27 全点位显式改 + render_preview schema 两层（editing 域层 + union 层）consciously change together 同批；快照改动全部走「显式改 + DECISIONS 申报」形禁静默；M7-3..M7-5 串行禁并行（orchestrator 编排保证——若误并行派发 M7-5 立即停手上报，禁抢先合并快照表）"
  - "零新 render 代码（OQ-M7-3-5 最简兑现）：双臂各走 renderedPlane verbatim 不共享 decode；Core 唯一新触点 = renderedPlane additive 默认参 pristineOnly 一处（true = 跳过 :236 readDocument 走既有空链分支——零新 kernel、零新管线段）；零新 .metal（全域零 diff）"
  - "既有 23 工具 descriptor/handler 零 diff——除 render_preview 申报内 schema/description 字节（region+compare 两层同批显式改）；McpTimeouts 零新档零改档（双臂 = 既有 renderAndCrop 30s 单窗；project 族 = 既有 apply 10s / list 10s）；McpToolError 16 档封闭表零触（错误码零新增）"
  - "全消费方零 diff 红线（T2 验收核心；L2 口径勘正——原「三消费方」漏列 QuickLookRendererTests）：QuickLookRenderer.renderedPlane 全消费方 = 9 调用点 / 5 文件（QL pane 内部 QuickLookRenderer :123/:171 / McpRenderParityTests :221/:262/:543 / McpMatchColorParityTests :158 / QuickLookRendererTests :206/:227〔除新负测〕/ MCP body EditingToolset :835——后者 T3 申报内改形）默认参路径行为零变化"
  - "list_versions 恒只读（requiresWriter 缺省 + readOnlyHint:true）——sidecar 写面 / withWriteBatch / 库写腿零触；sidecar schema（LightamerSidecar）与 HistoryStack/HistoryItem 类型与 CodingKeys 零改（只读投影）；project_open/create 的 requiresWriter:true 走既有 endpoint writer gate（registry 写面分支结构零 diff）+ projectReadOnly 判别缝 provider 侧完成（工具体零 controller 类型引用——F-6 源隔离纪律延续；LibraryProjectController.swift 文件零 diff——FIX2③ 维持 M7-4）"
  - "封存面零触：DrtRecord / TerminalTailPolicy / DrtTailAssembly / PixelPipe / Lut3dKernels.metal / DrtEotf / ExportQueueContract / 六格式导出矩阵（ExportFormatSpec·ImageIOEncoders·WebPEncoder）/ NodeGraphCommand / sidecar schema（LightamerSidecar）/ HistoryStack / HistoryHash / PipelineDocument（Core）/ V50Order / GradeCatalog（NodeOwnershipCatalog）/ Registry / ModuleInstance——list_versions 是 sidecar/HistoryStack 只读投影"
  - "Alcedo GPL 代码/文档文案零复制零翻译——工具名/参数/schema/文案全部自写（snake_case MCP 与点分 JSON-RPC 天然异构），只对表命令语义（render_commands.cpp / project_commands.cpp / version_commands.cpp 只读对表）"
  - "xcstrings = 四新键 mcp_tool_desc_list_luts / _project_open / _project_create / _list_versions 尾块纯插入（历史键字节与顺序零触碰）+ mcp_tool_desc_render_preview 原位值改（en defaultValue + zh 译文同批——非尾块插入，DECISIONS 申报）；UserDefaults 零新键；执行中如需更多键 = 同纪律 + DECISIONS 申报"
  - "\\.runModal( 在 App/Sources 零命中（L057 禁令）；LocalizationValue 插值禁形代码零命中（新描述键一律 String(localized: 静态键, defaultValue:) 显式形态——禁 String.LocalizationValue(\"prefix_\\(x)\" 插值形，M2-9 F-2 禁令）"
  - "Project.swift 恰一行测试登记（McpProjectToolsetTests.swift → LightamerTestsApp 数组）+ BUNDLE-MAP 恰一行（APP 域）+ tuist generate 恒为该批最后一个动作（L041）"
  - "构建 caffeinate -dis 包裹；单测 = Scripts/test-direct.sh --bundle <域>；全套 --all orchestrator 批准制（本 plan 标注批准制，执行时 orchestrator 派发 prompt 即批准）+ 8G 门 + MEMFAIL 机检 + 运行中保持监视（AGENTS 资源监控节）；测试宿主清理先核 parentage（ps -o ppid，M2-7-3 先例——测试宿主 parent = 脚本进程树，GUI 实例 parent = launchd）"
files_modified:
  - Tests/LightamerTests/FilterSQLTests.swift                                        # T1：F-AC-1 新法 testLibraryDomainSnapshots()（.library 域 WHERE+bind 快照 ≡ 现字节；同型 testNumericSnapshots 先例 + domain: .library 传参；Library bundle 已登记 :586 零登记改）
  - App/Sources/Lightamer/MCP/McpServerController.swift                              # T1：makeHeadlessSearchState 加 projectWriteProbe 默认参 + :374 传既有 probe（F-AC-2）+ fulltext 闭包 :204-209 静默空 → typed notSessionMember（N2-3）。T4：makeRegistry 第四参 project:（缺省 nil）+ 四宿主缝 additive 透传（startHTTPHost :754 / startHeadlessStdioHost :524 / startReadOnlyHTTPHost :464 / startEmbeddedIfPreferenceEnabled :852 + EmbeddedState box project 字段——startEmbeddedServer on-leg 读出透传）+ current-project 盒（锁保护值盒：store/url/readOnly）+ makeHeadlessSearchState liveState 改盒读 per-call 重取（:209-224 启动捕获退役——盒空 = no-project null 面逐字节）+ **library seam projectDirectory 锚 :194 改盒读**（box.url.deletingLastPathComponent()——运行时切换后解析锚随盒，fix 20997721 同族第二实例关闭——H2）+ no-project stdio/http 两臂（:254-256/:263-267）bare context 换盒读 closure 形 + 生产宿主调用点全清单（:254/:263/:378/:390/:410）传 project provider（Core 直开盒读形——H3）+ EOF watcher 抽取共享 armStdioEOFReleaseOnce()（幂等 once guard + arm 内部 mode==.stdio 自守卫〔M1〕；watcher 体改 HUP 时点读盒——close + exit(0) 语义原样）+ 无头 project_open/create provider（Core 直开直建 park 盒 + 失败中间态纪律：close 成功 open 失败 = 盒清空诚实态）
  - App/Sources/Lightamer/MCP/Tools/SearchStateToolset.swift                          # T1：pristine payload +1 键 truncated:false（:833-846 十二键→十三键——形状一致化零语义变；键数勘误 L1，亲点 12 键）。T4：resolveImageURL 寻址核心抽 internal 共享 helper（(image, libraryProvider, sessionPairProvider) 签名——原 private static 吃 context 形改薄封装，行为零变；ProjectToolset 以自携同形两 seam 喂同形参——M3，禁复制形；helper 只搬 searchState 现逻辑，禁顺手动 match_color provider〔锚病在案、M7-4 路由〕）
  - Tests/LightamerTests/McpSearchStateToolsetTests.swift                             # T1：pristine golden 字节同批更新（N2-1）+ requestFailed 臂（N2-4，F-3 家族映射法补第四案）+ fulltext nil 载体 typed 负测（N2-3）+ headless get_state.control.lock verdict 真值断言（F-AC-2）。T5：:270 计数负测显式改（20→21 + message 同批——「无新域时的既有面」负测语义保持，随 list_luts 归位到 21，H1；工具面快照零 diff 红线不动）
  - LightamerCore/Sources/Export/QuickLookRenderer.swift                              # T2：renderedPlane additive 默认参 pristineOnly: Bool = false（:220 签名尾部；true = 跳过 :236 readDocument——document nil / records=[] / :238 imageID fallback 原样 = 既有无 sidecar 路径逐位同；其余函数体零改）
  - Tests/LightamerTests/QuickLookRendererTests.swift                                 # T2：pristineOnly 恒等负测两法（缺省 ≡ 显式 false byte-equal；true ≡ 无 sidecar 副本缺省渲染 byte-equal——EXPORT bundle 定向绿）
  - App/Sources/Lightamer/MCP/Tools/EditingToolset.swift                              # T2：render_preview schema +region 属性（归一化 0..1 {x,y,w,h}）+ 解析/校验（w/h≤0 → invalidParams；越界 → roiOutOfBounds）+ CGImage.cropping(to:) 归一化裁剪（rect × 渲染宽高 round，再与平面 bounds 求交 clamp；交后 w/h ≤ 0 → invalidParams 携归一化值——M2，合法入参不得落 cropping nil → renderFailed 静默面）。T3：schema +compare 属性（enum none|root 默认 root）+ 双臂 body 改形（同 boundedWait 窗两遍 renderedPlane；pristine 臂 pristineOnly:true；输出 [current, root, text] + summary JSON）+ list_luts 注册（descriptor 零入参 readOnlyHint:true + body 三件只读投影 LutLibraryStore.shared 直读）+ render_preview/list_luts description 终式（compare/region 语义 + 载荷预算边界 + 双工具分界句 + lutName 寻址键句）
  - App/Sources/Lightamer/MCP/Tools/ProjectToolset.swift                              # T4 新建：McpProjectContext（全 provider closure optional 缺省 nil——openProject/createProject 路由缝 + library/sessionPair 同形两 seam〔OQ-8：装配点共享同一闭包变量〕+ projectWriteProbe 透传面）+ ProjectOpenOutcome 值类型 = {url, name, readOnly, heldByOther}（**name = url.deletingPathExtension().lastPathComponent** 盘面 stem 单源派生——Core 无公开 name 读面禁新 Core face，与 GUI recent 列显示口径一致——L3）+ McpProjectToolset.registerAll 三工具——project_open（path 先检后开 + 无头臂先关后开）/ project_create（folder 存在 + name 非空 + 目标不存在，包名最小 sanitize）/ list_versions（双地址制——共享寻址 helper〔SearchStateToolset T4 抽取形，M3〕+ readDocument 单源不读 version_ref + includeItems 逐版本 historyKind/historyItemCap 500 保新端 + position/itemCount 真值 + 每版本 truncated 旗标）；requiresWriter 面 = project_open/create true、list_versions 缺省 + readOnlyHint:true；错误码全既有（invalidParams/projectReadOnly/internalError/serverReadOnly/notSessionMember）
  - App/Sources/Lightamer/UI/LightamerApp.swift                                       # T4：GUI 内嵌臂 project context 装配（MainActor hop provider——openProject/createProject 经 libraryProjects controller + **held 目标先 probeLockAvailable 无持有预检**（held → typed projectReadOnly(holderSummary) 不调 openProject——一次 agent 调用不得掀用户正开项目，H4）+ before/after 差分判别缝（pendingConflict 调用前 nil ∧ 调用后非 nil ∧ projectStore 未变化）→ typed projectReadOnly(holderSummary)；library/sessionPair = 与 searchState 同一 closure 变量赋两 context；controller 文件零 diff）
  - Resources/Localizable.xcstrings                                                   # T3：mcp_tool_desc_render_preview 原位值改（en defaultValue + zh 译文同批——描述扩 compare/region 语义 + 载荷预算边界句）+ mcp_tool_desc_list_luts 新键。T4：mcp_tool_desc_project_open/_project_create/_list_versions 三新键尾块纯插入（历史键字节与顺序零触碰）
  - Tests/LightamerTests/McpProjectToolsetTests.swift                                 # T5 新建：project 域快照层（三工具 name/description/schema verbatim + 域内计数 27 分账 + 白名单负测）+ 锁仲裁 fixture（held → typed projectReadOnly + holder summary / 释放 → 自然恢复 / 自持切换 checkpoint 腿 / create 已存在拒 / folder 缺失拒——in-process 双 store 锁形；McpProjectArbitrationTests 序列 A/B 跨进程 fixture 零触零 diff）+ **评审增腿族**：A→B 运行时切换后 get_state.project.path 与项目相对解析锚同指 B（H2）+ 已持 A + open held B → typed projectReadOnly 且 get_state.project 仍指 A（provider 装配逻辑腿，stub controller face——H4③）+ stale pendingConflict 挂起 + open 成功目标 → 成功应答（H4③）+ http mode 运行时 open 后 armStdioEOFReleaseOnce 不产生 watcher（M1 门控腿）+ list_versions golden（三版本 fixture：ACTIVE + 两非活跃带链 → 投影 byte-equal + includeItems 两档 + >500 帽逐版本保新端 + 双地址臂 + ACTIVE 链 items ≡ get_history 同源恒等）
  - Tests/LightamerTests/McpEditingToolsetTests.swift                                 # T5 additive：region golden（归一化 rect × 渲染平面尺寸 round+clamp ≡ 手算像素框 / 越界两臂 typed 拒 / 两边界腿强制：x+w==1.0 精确臂 + 亚像素 w 臂〔M2〕/ region+compare 组合臂同 rect 双图）+ compare:root golden（edited vs pristine 两平面尺寸恒同 + pristine 臂 ≡ 无 sidecar 图直调 render_preview + 载体序断言 + pristineOnly 缺省恒等负测引用）+ list_luts golden（临时根 seeded .cube → 投影 ≡ installedNames/entry(named:) 直调恒等式 + **seeded 内容正断言**〔已知 name/hash/size +1 条——恒等式外可见性腿，L4〕+ 键形根相对 POSIX 断言）
  - Tests/LightamerTests/McpRegistrySnapshotTests.swift                               # T5：editing 层显式改——render_preview schema 行（region+compare）+ list_luts 行加入（6→7 + 域内计数断言）（与 union 层 consciously change together——M5-1-03 先例形）+ **:194 计数钉显式改**（names.count == 20 → 21 + message 同批——H1）+ **:30 docstring 过时计数改写**（「the 14-4 union asserts all 20」）
  - Tests/LightamerTests/McpFinalSnapshotTests.swift                                  # T5：union 显式改 23→27 全点位（F-AC-4 清单形——冻结表 render_preview schema 行同批 + list_luts 行 + project 三行〔descriptors() 名序〕+ 计数断言 ×4 :209/:246/:274/:421 + 组合代数四集合并 :246 段 + descriptionKeys +4 行 + makeUnionRegistry :190-201 传 project fixture context + SC7 startHTTPHost 传 fixture context + F-AC-4 注释 :210 非易碎形改写 + **all23 属性名→all27**〔:184-186 定义 + :207 引用〕+ **过时计数注释/message 同批**〔文件头注 :15「all20 → all23」与 :22「THE UNION (23)」+ :209 断言 message「the final count is 23」〕+ 测试名 Union23→Union27——DECISIONS 申报显式改）
  - Tests/LightamerTests/McpHostTests.swift                                           # T5：union 外计数钉显式改（:243 http e2e roundTrip + :696 三宿主 conformance http 臂——:718 memory 臂断言 ≡ httpTools 无独立硬码随行绿）20→21 + message 同批（H1）
  - Tests/LightamerTests/McpLauncherTests.swift                                       # T5：union 外计数钉显式改（:200 names.count == 20 → 21 + message 同批——H1）
  - Project.swift                                                                     # T5：恰一行测试登记（McpProjectToolsetTests.swift → LightamerTestsApp 数组；tuist generate 恒末位）
  - .work/gsd/phases/m2-4-0-test-bundles/M2-4-0-BUNDLE-MAP.txt                        # T5：McpProjectToolsetTests.swift 增行（APP 域）
  - .work/gsd/phases/m7-3-mcp-o2o3/M7-3-01-SUMMARY.md                                 # T6：执行摘要（逐任务 ΔN 记账 + 三验收形态判定指针 + 快照显式改申报 + 中间红窗申报〔T2..T5 App bundle union/editing 两快照红——构建绿门维持〕）
  - .work/gsd/phases/m7-3-mcp-o2o3/M7-3-01-DECISIONS.md                               # T6：裁定记录（快照显式改申报 + recent 不对称申报〔D-M7-3-9〕+ EOF watcher 抽取终形 + current-project 盒终形 + cursor 边界承接句〔⑥〕+ F-AC-1 收口申报段 + 窄投影/键形终值 + 中间红窗处置）
  - AGENTS.md                                                                         # T6：「M7-3 架构增量」节（四工具语义 + ProjectToolset context 形 + 运行时开项目缝 + 顺路件收口 + ΔN 终值）
  - .work/TODO.md                                                                     # T6：M7-3 条目翻账（挂账六项收口申报 + FIX2③ M7-4 维持）
  - .work/GOAL-STATE.md                                                               # T6：续接点翻新（M7-3 收口 → next = M7-4/M7-5〔MCP 快照面串行接棒〕）
  - .work/gsd/REQUIREMENTS.md                                                         # T6：MCP2-04..07 翻账（Delivered + M7-3 commit 指针）
---

# Plan M7-3-01 — MCP O2 反馈回路 + O3 项目与版本（四工具 additive + 运行时开项目缝 + 快照 23→27 + 顺路件六项）

> **夜间全自动授权**（先例 D-07-3-T5-1；晨审可推翻）。裁决正本 =
> `M7-3-CONTEXT.md`（D-M7-3-1..10 全按 RESEARCH §7 推荐——站 charter 授权
> 落定）；规格正本 = `M7-3-RESEARCH.md`（§2 现状测绘 / §3 四件语义 /
> §4 顺路件六项 file:line / §5 集成缝 / §6 测试策略；file:line 经 planner
> 批 2026-10-17 HEAD `217999a5` 逐点亲核复核吻合）。
>
> **裁定权归属钉**：本 plan 无用户裁决分支（四工具 additive + 两参数扩展 +
> 无头运行时缝——既有工具行为面零变化由 T5 快照零 diff 门钉死，除
> render_preview 申报内 schema/description 字节）。执行中如触「必须扩面」
> （新错误码 / 新超时档 / 共享 decode / 降档自动缩水）= 停手上报，不得
> 自裁扩界。
>
> **执行序**：T1 → T2 → T3 → T4 → T5 → T6。T1-T4 产线码（每任务独立
> commit + 构建绿机检；App bundle 快照红窗见「风险与回退」第 1 条），
> T5 测试批一次落位（orchestrator 指定分批——测试集中在码面稳定后落位），
> T6 轮次 + 收口。每任务独立 commit（Conventional Commits，全英文，只 add
> 相关文件，不 push）。
>
> **基线**：**3877/35/0**（M7-2 三路全套同值；其后两跳 docs-only 零漂移；
> HEAD `217999a5`）。全套预期 `3877+ΔN/35/0|`（ΔN 预期带 +12..20，对账式）。
>
> **快照改动权**：本波持 union 文件改动权（M7-2 VALIDATION 特殊事项 5
> 移交）——M7-5 禁并行（orchestrator 编排保证）。

## 已定裁决（生效值，硬约束，不得重开）

OQ-M7-3-1..10 **全部按 RESEARCH §7 推荐裁**（CONTEXT D-M7-3-1..10）。本单
plan 承载全部十项；执行面速查：

1. **双宿主同源路由**（OQ-1）：无头臂 Core 直开/直建 park 盒；GUI 内嵌臂
   MainActor hop `LibraryProjectController`（conflict 对话框 = 仲裁 UI，
   判别缝 → typed `projectReadOnly(holder)`）；`requiresWriter: true`。
2. **region 归一化 0..1**（OQ-2）：渲染后平面裁剪，与 longEdge 解耦；
   与 `get_detail_crop` 分界句进 description。
3. **compare 默认 `root`**（OQ-3）：双臂 ≈3MB@1024 预算边界写明；无自动
   降档；双臂同 30s 单窗。
4. **第四域 ProjectToolset**（OQ-4）：project 三工具自立域；`list_luts`
   入 editing 6→7；union 27。
5. **双臂不共享 decode**（OQ-5）：零新 render 代码；Core 唯一新触点 =
   `pristineOnly` additive 默认参一处。
6. **Summary 不带 photo_count**（OQ-6）：出参 `{path, name, readOnly,
   heldByOther}`；计数 agent 走 search_photos/list_photos 自取。
7. **运行时 open 后 arm EOF watcher**（OQ-7）：幂等 once guard；watcher 体
   读当前项目盒；启动路径行为逐字节不变。
8. **list_versions 自携同形 seam**（OQ-8）：`library`/`sessionPair` 两
   provider 装配点共享同一闭包值；sidecar `readDocument` 单源，version_ref
   零角色。
9. **MCP 开项目不入 recent**（OQ-9）：零新增 promoteRecent 面；无头臂天然
   不入；GUI 臂经 controller 继承既有语义（不对称 DECISIONS 申报）。
10. **writer 臂照常 migrate**（OQ-10）：`open(role:)` 既有迁移语义原样；
    migrate 失败 = `internalError` 携 detail。

## read_first（全局，每任务开工前过一遍）

- `.work/gsd/phases/m7-3-mcp-o2o3/M7-3-CONTEXT.md`（D-M7-3-1..10 裁决 +
  get_state 联动改形正本 + 顺路件六项表 + 红线摘要）
- `.work/gsd/phases/m7-3-mcp-o2o3/M7-3-RESEARCH.md` §3（四件语义与 Alcedo
  对表锚）+ §4（顺路件六项 file:line + 修法草案）+ §5（集成缝 file:line）
  + §6（测试策略八条）+ §9（风险与边界）
- `.work/config.toml [gsd]` paused/auto 开关（开工前亲核）
- `.work/LESSONS.md` L041（tuist generate 恒末位）+ CONVENTIONS「新测试文件
  落域规则」（Project.swift 显式清单 + BUNDLE-MAP + tuist generate 恒末位）
- `App/Sources/Lightamer/MCP/McpToolRegistry.swift`（:61-111 McpToolError
  16 档封闭表 / :130 McpProjectLockVerdict / :179-200 McpToolOutput 内容
  数组 / :209-220 McpTimeouts 档位表）
- `App/Sources/Lightamer/MCP/McpServerController.swift`（:183-225
  makeHeadlessSearchState + liveState 启动捕获 + fulltext 闭包 / :242-300
  runHeadless 分派 + no-project stdio 臂 :254 / :303-415 runHeadlessArbitrated
  + EOF watcher :353-367 + probe :370 + searchState :374 / :464/:524/:754
  三宿主缝 + :852-920 EmbeddedState box + makeRegistry :579）
- `LightamerCore/Sources/Export/QuickLookRenderer.swift`（:220-316
  renderedPlane + :236 readDocument + :322 image(from:)）

---

## T1 — 顺路件六项（M7-2 挂账单一清单收口）

> **单一清单正本**：`M7-2-VALIDATION.md` §挂账六项 + F-AC-4 附项。合计
> ≈ 十行代码 + 一测试法 + golden 字节更新。F-AC-4 注释随 T5 union 批落
> （本任务只申报指针——见 T5 action 6）。FIX2③ 不承载（controller 零 diff）。

**read_first**：`M7-3-RESEARCH.md` §4（六项 file:line + 修法草案——planner
批已逐点亲核）；`FilterSQLTests.swift` :28-91（testNumericSnapshots 快照
同型先例）；`FilterSQL.swift` :115-123（orderBySQL `.library` 臂）+
`LibraryQueries.swift` :633-634/:673-674（`.library` 调用点）；
`McpServerController.swift` :183-225（makeHeadlessSearchState + fulltext
闭包 :204-209）+ :370-377（probe 建 + searchState 调用点）；
`SearchStateToolset.swift` :422（noOpenProjectMessage 单源）+ :833-846
（pristine payload 十二键——L1 勘误）+ :886（正常面 truncated 恒有）；
`McpSearchStateToolsetTests.swift` :566-615（F-3 家族映射法——requestFailed
臂补此法）。

- **action**：
  1. **F-AC-1（快照补申报——「二选一收口」两路同时兑现）**：
     FilterSQLTests 新法 `testLibraryDomainSnapshots()`——
     `FilterSQL.translate(group:domain: .library)` 对 rating gte / flag eq /
     iso lt / captureDate gte / focalLength between / keywords contains
     断 WHERE+bind 串（**钉住现字节 = 快照法，非新写 SQL**；同型
     testNumericSnapshots :30-91，显式传 `domain: .library`）；如 keywords
     四子句在 library 域为物化列形则同法补第二法。**DECISIONS 申报段随
     T6 落**（快照补 + DECISIONS 一段 = F-AC-1 完整收口）。
  2. **F-AC-2（probe 透传）**：`makeHeadlessSearchState` 签名加
     `projectWriteProbe: (@Sendable () async -> McpProjectLockVerdict)? =
     nil`（缺省 nil = 既有测试构造零 diff），context init 的
     `projectWriteProbe` 面带入；:374-375 调用点传既有 `probe`（:370 已建）。
     效果 = headless `get_state.control.lock` = verdict 真值（writer 臂
     self-held writable / 只读臂真 probe）。T4 的 liveState 盒读改形
     消费同一参（同缝延续）。
  3. **N2-1（pristine 补 `truncated` 键）**：SearchStateToolset :833-846
     pristine payload 字典恰 +1 行 `"truncated": .bool(false),`（十二键→
     十三键——L1 勘误：plan 前写「十三键→十四键」系 grep 口径误计，亲点
     12 键〔image/position/itemCount/items/versions/activeVersionID/note/
     keywords/rating/flag/colorLabel/author〕；形状一致化零 schema 语义变，
     加后与正常面 :882-901 十三键等形）；**McpSearchStateToolsetTests pristine
     golden 字节同批更新**（同 commit 绿门）。
  4. **N2-3（fulltext 窄竞态 typed 抛）**：McpServerController :204-209
     fulltext 闭包 `guard let store else { return [] }` →
     `guard let store else { throw McpToolError.notSessionMember
     (McpSearchStateToolset.noOpenProjectMessage) }`（闭包签名已 throws；
     消费点 `try await` 已接——与「never a silent empty result」头注纪律
     对齐；typed 面与 library seam 缺席同文案单源）。负测：nil 载体
     context 调 `search_photos mode=fulltext` → `notSessionMember`。
  5. **N2-4（requestFailed 显式测试）**：F-3 家族映射法（:566-615）补一臂：
     `registryFor(AIWorkerClientError.requestFailed("boom"))` → 断
     `code == "modelUnavailable"`（先例形两行；case 形 `requestFailed(String)`
     亲核 AIWorkerClient.swift :41）——F-3 四案闭合。
  6. **⑥（cursor 边界承接句）**：无码面——T6 DECISIONS 承接一句（边界口径
     不变：库重排后旧 cursor 可能跳行/漏行，不引入版本戳；list_versions/
     project 族无 cursor 面，零新增边界）。
  7. 构建绿机检 + 定向双 bundle：`--bundle Library`（F-AC-1 新法 +
     FilterSQL 回归）+ `--bundle App`（N2-1/N2-3/N2-4/F-AC-2 断言 + 既有
     MCP 面全绿——本任务后 App bundle 仍全绿，红窗自 T2 起）。
- **验收标准（机检）**：
  - 构建绿；`git diff --stat` 恰四文件（FilterSQLTests + McpServerController
    + SearchStateToolset + McpSearchStateToolsetTests，无它）。
  - `--bundle Library` + `--bundle App` 定向绿。
  - grep：`truncated` 在 pristine payload 恰一行（:833-847 段）；fulltext
    闭包 `return []` 零命中（typed throw 在位）；`projectWriteProbe` 默认参
    在 makeHeadlessSearchState 签名（grep 签名行）。
  - N2-1 golden 更新与 payload 变更同 commit（绿门结构性保证）。
- **commit**: `fix(m7-3): close the M7-2 carry-over ledger items`

## T2 — `renderedPlane` pristineOnly additive + region 归一化裁剪

> **Core 唯一新触点红线（OQ-5 / CONTEXT 红线③）**：`renderedPlane` 加
> `pristineOnly: Bool = false`（:220 签名尾部）；true = 跳过 :236
> `readDocument`——document nil / records=[] / :238 imageID fallback 原样
> = 与「无 sidecar 文档的 pristine 图今日渲染」**逐位同路径**（同一空链
> 分支），零新 render 代码、零 kernel 触碰。**全消费方零 diff 负测 =
> 本任务验收核心**（L2 口径勘正：9 调用点 / 5 文件——清单见红线）。

**read_first**：`M7-3-RESEARCH.md` §2.1（渲染面现状）+ §3.1（region 契约）；
`QuickLookRenderer.swift` :220-325（renderedPlane 全函数 + :236 readDocument
+ :322 image(from:)）+ :115-135（QL pane 消费——零改面）；
`EditingToolset.swift` :774-859（registerRenderPreview + renderPreviewBody）
+ :1060-1123 对应 CullingToolset `detailCrop`（roiOutOfBounds 先例形）；
`QuickLookRendererTests.swift`（现有 fixture 面——新负测落此）；
`McpToolRegistry.swift` :209-220（renderAndCrop 30s 档——零新档）。

- **action**：
  1. **Core additive**：`renderedPlane` 签名尾部加
     `pristineOnly: Bool = false`；函数体恰一处条件化——
     `let document = pristineOnly ? nil : ExportRenderer.readDocument
     (imageURL: imageURL)`（:236 行改形；其余逐行零改——records/layerStack/
     imageID fallback 全部顺既有 nil 路径）。
  2. **负测两法**（QuickLookRendererTests，EXPORT bundle）：
     ①缺省调用 ≡ 显式 `pristineOnly: false`——同 fixture（带 sidecar 预置
     参数）两次渲染 byte-equal（default 值恒等）；②`pristineOnly: true`
     输出 ≡ 同图**无 sidecar 副本**缺省渲染 byte-equal（同一空链分支
     自证——零新 render 代码的可执行判定）。fixture 复用现有
     QuickLookRendererTests 面。
  3. **region 参数（EditingToolset）**：schema 恰 +`region` 属性
     （object {x,y,w,h} 全 double，归一化 0..1）；解析校验：w ≤ 0 ∨ h ≤ 0
     → `invalidParams`（携参数名）；越界（x+w>1 ∨ y+h>1 ∨ 负坐标）→
     `roiOutOfBounds`（既有码，message 携归一化域——detailCrop :1091-1095
     先例形）；裁剪 = `CGImage.cropping(to:)`，rect × 实际渲染宽高
     **round 后与平面 bounds 求交（clamp）**——交后 w/h ≤ 0（亚像素零宽
     臂）→ `invalidParams` 携归一化值（合法归一化入参不得落
     `cropping == nil` → renderFailed 静默面——detailCrop :1096-1097
     renderFailed 只作兜底非规格，M2）；与 longEdge 解耦；region 与既有
     单图输出兼容（无 region = 现行为
     逐字节）。schema 快照红窗自本任务起（T5 两层显式改收口——见风险第 1
     条；本任务 gate = 构建绿 + EXPORT 定向绿）。
  4. description 的 region/compare 语义终式随 T3 一次落（本任务 schema
     先行——description 字符串非快照钉面，T2 中间态不申报）。
  5. 构建绿机检 + `--bundle EXPORT` 定向绿（QuickLookRendererTests 两负测
     + 既有渲染面零回归）。
- **验收标准（机检）**：
  - 构建绿；`git diff LightamerCore/Sources/Export/QuickLookRenderer.swift`
    逐 hunk 核 = 恰签名 + :236 条件化两处、其余零触。
  - 全消费方零 diff（9 调用点 / 5 文件——L2 清单见红线）：`git diff` 面核
    QL pane :123/:171 / McpRenderParityTests :221/:262/:543 /
    McpMatchColorParityTests :158 / QuickLookRendererTests :206/:227
    （除新负测）零触；
    MCP body（EditingToolset :835 调用点）T2 段调用形零改（T3 才改双臂）。
  - `--bundle EXPORT` 定向绿；grep：`pristineOnly` 在 QuickLookRenderer.swift
    恰两处（签名 + :236 条件）；`roiOutOfBounds` 在 EditingToolset region
    路径（复用既有码零新错误码）。
- **commit**: `feat(m7-3): add the pristineOnly render leg and region cropping`

## T3 — `compare` 默认 root 双臂内联 + `list_luts`（editing 6→7）

> **零新 render 代码（OQ-5）**：双臂 = 同一 `boundedWait`（renderAndCrop
> 30s 单窗，零新超时档）内两遍 `renderedPlane`（edited 臂现形 / pristine 臂
> `pristineOnly: true`）——不共享 decode。输出载体 = `McpToolOutput`
> 内容数组（:179-200 既有面零改）：`[.imageBase64(current), .imageBase64
> (root), .text(summary)]`。

**read_first**：`M7-3-RESEARCH.md` §3.1（compare 契约 + 载荷预算）+ §3.2
（list_luts 面）+ §2.4（LutLibraryStore 三件读面）；`EditingToolset.swift`
:774-859（现 descriptor + body）+ :141-160（register 面——list_luts 注册
落此）；`LutLibraryStore.swift` :110-117（shared）+ :381（installedNames）
+ :399（entry(named:)）+ :65-100（InstalledLut 字段 + resolvedRelativePath）；
`McpToolRegistry.swift` :179-200（McpToolOutput）。

- **action**：
  1. **compare 参数**：schema 恰 +`compare` 属性（enum
     `"none" | "root"`，default `"root"`）；`root` 臂 = pristine 渲染
     （pristineOnly:true）；双臂同 rect（region 同时作用于两臂——Alcedo
     同构）；summary JSON = `{"current":{width,height},"root":{width,height},
     "compare":"root"}`（内容序 current 先、root 后——description 写明）；
     `none` = 单图现行为逐字节（现调用方零感知）。载荷预算边界 description
     写明（双臂 ≈3MB@1024/q85；2048/q90 帽双臂 ≈11MB——typed 帽在位，无
     自动降档）。
  2. **description 终式（一次落）**：`mcp_tool_desc_render_preview` 原位值
     改（en defaultValue + zh 译文同批）——追加 compare/region 语义句 +
     载荷预算句 + 与 `get_detail_crop` 分界句（detail_crop = 源细节检视
     原生分辨率 / render_preview region = 渲染观感 ROI）+ region 相对渲染
     输出画面（orientation 已归一）。
  3. **list_luts（editing 域注册）**：`EditingToolset.register` 追加一注册
     ——descriptor 零入参（v1 无 group 过滤）+ `readOnlyHint: true` +
     writer 缺省（只读）+ 超时 `McpTimeouts.list`；body =
     `LutLibraryStore.shared` 直读（IOP 层公开单例，editing seams 零新
     face）——出参 `{libraryRoot, total, luts: [{key, name, hash, is1D,
     size, title?, subdirectory?, rememberedEncodings?}]}`（key =
     `resolvedRelativePath` 即 registry 键；`entry(named:)` 逐键投影；
     `libraryGroups()` 不入 v1）；description 一句 **「key 即 lut3d 模块
     params `lutName` 的新写入寻址键」**（KD-1 纪律传达；旧档裸名 fallback
     不在工具面叙述）。
  4. **xcstrings**：`mcp_tool_desc_render_preview` 原位值改（非尾块插入，
     DECISIONS 申报）+ `mcp_tool_desc_list_luts` 尾块纯插入（历史键字节与
     顺序零触碰）。
  5. 构建绿机检 + grep 结构核（golden 随 T5；本任务 gate = 构建绿——
     App bundle 快照红窗持续）。
- **验收标准（机检）**：
  - 构建绿；grep：`compare` enum 两值 + default `"root"` 在 schema JSON；
    `list_luts` 注册在 EditingToolset（`readOnlyHint: true` 在位）；
    `libraryGroups` 在 EditingToolset 零命中（v1 扁平清单纪律）。
  - diff 面申报：render_preview descriptor hunk = 恰 schema +compare +
    body 双臂改形；既有五 editing 工具 descriptor/handler 零触。
  - xcstrings diff 逐 hunk 核 = 恰一原位改 + 一尾块插入。
- **commit**: `feat(m7-3): add compare-root dual-arm preview and list_luts`

## T4 — 第四域 ProjectToolset + 无头运行时开项目缝

> **错误码零新增**：project 族全走既有 16 档（`invalidParams` /
> `projectReadOnly` / `internalError` / `serverReadOnly`〔registry writer
> gate 自动〕/ `notSessionMember`）——`McpToolError` 封闭表零 diff。
> **F-6 纪律**：工具体零 controller 类型引用（判别缝在 provider 闭包内）；
> **controller 文件零 diff**（FIX2③ 维持 M7-4）。

**read_first**：`M7-3-RESEARCH.md` §2.2（项目面三入口 + 无头臂）+ §2.3
（版本面）+ §3.3/§3.4（四工具语义）+ §5.1（注册缝）；`ProjectFileStore.swift`
:103（create 新建即锁）/ :158（open heldByOther typed）/ :199-238
（openReadOnly）/ :249（holderSummary）；`LibraryProjectController.swift`
:132-190（createProject/openProject〔conflict 不 throw〕/openProjectReadOnly/
closeProject + promoteRecent 面——**只读对表，文件零改**）；
`McpServerController.swift` :303-415（runHeadlessArbitrated 双臂 + EOF
watcher :353-367 + probe/searchState 调用点）+ :242-300（runHeadless 分派
+ no-project stdio/http 两臂 :254-256/:263-267 bare context——裸
`McpSearchStateContext()` 亲验恰两处）；`LightamerSidecar.swift` :342/
:348/:919-952（versions/activeVersionID/SidecarVersionRecord/chainStack）；
`SearchStateToolset.swift` :951-998（resolveImageURL 双地址制——同构复用
形）+ :796-810（historyKind/historyItemCap——list_versions 复用）；
`LightamerApp.swift` :1349-1526（searchState context 装配段——project
context 同段装配）。

- **action**：
  1. **`ProjectToolset.swift` 新建**：`McpProjectContext: Sendable`（全
     provider closure optional 缺省 nil——既有构造零 diff + typed 诚实臂）：
     `openProject: @Sendable (URL) async throws -> ProjectOpenOutcome` /
     `createProject: @Sendable (URL, String) async throws ->
     ProjectOpenOutcome`（宿主形态注入——无头臂 Core 直开形 / GUI 臂
     controller hop 形；`ProjectOpenOutcome` 值类型 =
     `{url, name, readOnly, heldByOther}`——D-M7-3-6 无 photo_count；
     **name = `url.deletingPathExtension().lastPathComponent`**——盘面
     stem 单源派生（Core 无公开 name 读面——`ProjectFileStore` 公开面
     fileURL/create/open/openReadOnly/close/checkpointIfNeeded/backup
     零 name 读点，禁为取 name 新开 Core face 破红线③；create/open 两路
     name 恒等该 stem，与 GUI recent 列显示口径一致——L3））+
     `library` / `sessionPair`（list_versions 双地址制同形两 seam——
     **装配点把同一 closure 变量赋给两个 context**，provider 逻辑零复制，
     OQ-8）+ `projectWriteProbe`（list_versions 只读零消费、get_state 面
     由 SearchState 自持——此处为对称透传面，缺省 nil）。
     `McpProjectToolset.registerAll(on:context:)` 注册三工具：
     - `project_open`（`requiresWriter: true`）：入参 `path`（string 必填，
       `.lalb` 绝对路径）——**先检后开**（文件不存在 → `invalidParams` 携
       路径，Alcedo 同构：错路径不动当前项目）；已持有项目 = 先关后开
       （close checkpoint 内置）；失败中间态纪律 = close 成功 open 失败 →
       盒清空诚实态（禁半开态，agent 重试）。
     - `project_create`（`requiresWriter: true`）：入参 `folder`（必填，
       须为已存在目录）+ `name`（必填非空；包名最小黑名单 sanitize）；包
       URL = `folder/<name>.lalb`；已存在 → `invalidParams`（不覆盖）。
     - `list_versions`（writer 缺省 + `readOnlyHint: true`）：入参
       `image`（必填，双地址制——**共享寻址 helper**：T4 从
       SearchStateToolset 抽 internal helper〔(image, libraryProvider,
       sessionPairProvider) 签名，行为零变纯抽取——原 `resolveImageURL`
       :951 private static 吃 `McpSearchStateContext` 直调不可达，禁
       复制形，M3〕）+
       `includeItems`（bool 默认 false）；投影 =
       `{image, activeVersionID, versions: [{id, name, createdAt, updatedAt,
       active, position, itemCount, truncated?, items?}]}`——ACTIVE 版本
       （`chainStack == nil`）读文档 `history`；非活跃读
       `record.chainStack`（:952 公开面）；`includeItems` 臂复用
       `historyKind` 五臂 + `historyItemCap` 500 保新端 + position/
       itemCount 真值 + 每版本 `truncated` 旗标（get_history F-5 同式
       逐版本）；**单源 = `readDocument`（:783）——不读 version_ref**
       （M2-8 KD-3 双真相禁令）；无 sidecar 文档 = pristine 诚实面
       （versions: [] + activeVersionID null——非错误臂）；超时
       `McpTimeouts.list`。变更类命令（create/branch/checkout/…）零注册
       （ROADMAP 二期）。
  2. **registry 第四参 + 四宿主缝**：`makeRegistry` 追加
     `project: McpProjectContext? = nil`（缺省 nil = 既有调用与全部既有
     测试零 diff）；`startHTTPHost` :754 / `startHeadlessStdioHost` :524 /
     `startReadOnlyHTTPHost` :464 / `startEmbeddedIfPreferenceEnabled` :852
     additive 参数透传；**EmbeddedState box 加 `project` 字段**
     （`startEmbeddedIfPreferenceEnabled` 存 / `startEmbeddedServer` on-leg
     读出透传——searchState F-4① 第五缝同款；缺此缝 = GUI off→on toggle
     project 工具静默缺席；grep 机检点位含 `startEmbeddedServer`）。
  3. **无头运行时缝**：
     - **current-project 盒**：锁保护值盒（store/url/readOnly 三元——
       `headlessProjectStore` 既有静态盒之上的运行时可变面）；盒写者 =
       工具 body（writer gate 串行面内，apply 同款）+ 启动臂 seeding。
     - **运行时 open/create provider（无头臂）**：`ProjectFileStore(at:)` +
       `open(role: .headless)` / `create(name:role: .headless)` → 盒 park；
       heldByOther → typed `projectReadOnly(holderSummary)` 应答
       （`SingleWriterLock.holderSummary` 既有面）；库 seam 立即活
       （closure 每调用读盒——零额外接线）。
     - **liveState per-call 重取**：`makeHeadlessSearchState` 的 liveState
       closure（:209-224 启动捕获退役）改读盒——盒空 = no-project null 面
       逐字节（零 diff）；盒持 = 真值（path/readOnly/heldByOther 派生）。
       **启动捕获退役范围 = liveState + library seam 的 projectDirectory
       锚**：:194 `projectURL.deletingLastPathComponent()` 捕获改
       `box.url.deletingLastPathComponent()`——运行时 open B（A→B 切换）
       后 PathKind 0 项目相对行的 ImageLinker 解析锚同指 B（锚仍捕旧目录
       = search_photos/list_photos/get_history/list_versions 项目相对
       路径**静默**解析到不存在文件——fix `20997721` 同族第二实例，H2）。
     - **no-project 双臂换形 + 生产调用点传 provider**：bare
       `McpSearchStateContext()` 两处（stdio :254-256 **和 http
       :263-267**——亲验恰两处）同批换盒读 closure 形（library/fulltext/
       liveState/probe 全接线）——open 前盒空 = 今日 bare context 行为
       逐字节（library seam nil → typed notSessionMember；liveState
       project null）；open 后即时活。**生产宿主调用点全清单传 project
       provider**（Core 直开盒读形，mode 捕获见 M1）：runHeadless
       :254/:263 + runHeadlessArbitrated :378/:390/:410——read-only 宿主
       :410 面上工具在位、open/create 被 registry writer gate 前置
       serverReadOnly 拒（不传 = 该宿主 project 三工具静默缺席，违双宿主
       红线「closed face identical across hosts——tools never disappear」
       ——H3）。
     - **EOF watcher 幂等 arm（OQ-7）**：:353-367 watcher 体抽取共享
       `armStdioEOFReleaseOnce()`（static once guard 幂等；watcher 体改
       HUP 时点读盒——close 当前在持 store + exit(0) 语义原样）；启动路径
       :353 改调共享函数（行为逐字节不变）+ 运行时 open 成功后 arm 同款
       （stdio mode 才有意义——http 臂不 arm）；grep 双调用点机检。
       **arm 门控机制（M1）**：provider 闭包在 `runHeadless(mode:)` /
       `runHeadlessArbitrated(mode:)` 的 mode 可见作用域内构造（mode 捕获
       进 provider/context——provider 签名不带 mode），
       `armStdioEOFReleaseOnce()` 内部自守卫 `mode == .stdio`（双保险——
       启动 if 门 + arm 内部门；防 http daemon stdin 已闭时无门控 poll
       立即 POLLHUP → close + exit(0) = 首次 open 成功即整 daemon 退出）。
       **DECISIONS 补偏离句（H3③）**：http 运行时开项目 = 进程退出
       kernel 地板，checkpoint 优雅面仅 stdio——D-M7-3-7 偏离面钉全。
  4. **GUI 内嵌臂装配（LightamerApp 同段）**：project context provider
     MainActor hop `libraryProjects` controller——`openProject/createProject`
     路由 + **held 目标无持有预检**：调用 openProject **之前**先
     `SingleWriterLock.probeLockAvailable(at: lockURL)`（既有面，零新缝）
     ——held → 直接 throw `McpToolError.projectReadOnly(holderSummary)`
     不调 openProject（**一次 agent 调用不得掀用户正开项目**：「先关后开」
     仅属无头臂；GUI 臂 held 目标零 close 零对话框——「错路径不动当前
     项目」语义延伸到「held 目标不动当前项目」，H4③）；通过预检后调用，
     **判别缝 = before/after 差分**：调用前快照 `pendingConflict`，调用后
     `pendingConflict != nil ∧ 调用前 == nil ∧ projectStore 未变化` →
     throw `McpToolError.projectReadOnly(holderSummary)`
     （holderSummary = `SingleWriterLock.holderSummary(at: lockURL)`——
     「对话框已发布、等用户裁决」诚实应答；差分式消两洞——已持项目 +
     held 目标误报成功、stale pendingConflict 反向误报，评审亲核
     `projectStore` :52 / `pendingConflict` :73 均外露可读，状态面零新缝
     ——H4）；其余 controller throw 透传
     （internalError 兜底臂语义）。`library`/`sessionPair` = 与 searchState
     装配同一 closure 变量赋两 context（OQ-8——零逻辑复制）。
     **controller 文件零 diff**；两臂行为差异 DECISIONS 一句话钉死
     （headless = 先关后开 / GUI = held 预检不动当前项目）；promoteRecent
     随 controller 既有语义（D-M7-3-9 不对称——DECISIONS 申报）。
  5. **xcstrings 三新键**：`mcp_tool_desc_project_open` /
     `_project_create` / `_list_versions` 尾块纯插入（zh-only 形——
     description 含 requiresWriter 语义句：open/create 需 writer 宿主；
     list_versions 只读双地址句）。
  6. 构建绿机检 + grep 结构核（golden 随 T5）。
- **验收标准（机检）**：
  - 构建绿；grep：`makeRegistry` 签名恰四参（缺省 nil——三参既有调用编译
    零改）；`startEmbeddedServer` 在 project 透传路径（EmbeddedState 第五缝
    同款对账——五缝清单 = 四宿主函数 + EmbeddedState 内部缝）；
    `requiresWriter: true` 恰两处（open/create）+ list_versions
    `readOnlyHint: true`；`version_ref` 在 ProjectToolset 零命中（双真相
    禁令）；`requiresWriter` 在 ProjectToolset 恰两处显式 + 一处缺省；
    裸 `McpSearchStateContext()` 在 McpServerController 内零命中（H3
    机检——:256/:267 两点清零）。
  - **controller 文件零 diff**（`git diff --stat` 核 LibraryProjectController
    不在清单）。
  - EOF watcher：`armStdioEOFReleaseOnce` 恰两调用点（启动 :353 改形 +
    运行时 open 成功后）；once guard 在位（grep）；arm 内部
    `mode == .stdio` 自守卫在位（grep——M1）。
  - 错误码零新增：`git diff App/Sources/Lightamer/MCP/McpToolRegistry.swift`
    = 零 diff（封闭表零触）。
  - 盒空逐字节负测（T5 golden 预支）：no-project stdio 臂 get_state
    project null 面与今日 bare context 逐字节同；A→B 运行时切换后
    search/get_state 的 project.path 与项目相对解析锚同指 B（H2 锚
    断言腿 golden 预支）。
- **commit**: `feat(m7-3): add the project toolset and runtime project switching`

## T5 — 测试批：union 23→27 全点位 + 四域分层 + 新工具 golden + 零回归

> **orchestrator 指定分批**：测试集中本任务一次落位（T1-T4 码面稳定后）。
> 新文件 `Tests/LightamerTests/McpProjectToolsetTests.swift`（APP 域）+
> 既有 McpEditingToolsetTests additive（list_luts/region/compare golden）。
> **union 显式改 = 本波持权**（M7-2 移交）——全点位清单落位 + DECISIONS
> 申报。**两层 consciously change together**（M5-1-03 match_color 先例形）：
> render_preview schema 字节变 = editing 域层 + union 层同批显式改。
> **登记纪律（M2-4-0 E2）**：Project.swift 恰一行 + BUNDLE-MAP 恰一行 +
> `tuist generate` 恒为该批最后一个动作（L041）。

**read_first**：`M7-3-RESEARCH.md` §6（测试策略八条）；`McpFinalSnapshotTests.swift`
（:33 editingTools 冻结表 + :184-186 all23 属性〔本波改 all27〕+ :190-201 makeUnionRegistry + :203-217 union
verbatim〔:209 计数 + :210 F-AC-4 注释 + :212-216 destructive 集〕+ :219-250
域组合代数〔:246 计数 + :248 三集合并〕+ :252-274 白名单负测〔:274 计数〕+
:281- descriptionKeys + SC7 :410 附近 startHTTPHost + :421 directTools.count
——union 显式改全点位亲核坐标）；`McpRegistrySnapshotTests.swift` :30
（assertSnapshot docstring——过时计数改写点）+ :152（render_preview 行——editing 层显式改正本）
+ **:194 计数钉**（editing+culling 无 searchState 装配的闭合面计数——H1 补列）；
`McpCullingImageBudgetTests`（makeGradientCGImage fixture 先例）；
`McpProjectArbitrationTests.swift`（跨进程序列 A/B——零触对照面）；
`LutLibraryStoreTests`（M2-5-3 临时根 fixture 先例形——list_luts golden
同款）。

- **action**：
  1. **project 域快照新层**（McpProjectToolsetTests）：三工具 name/
     description/schema verbatim（assertSnapshot 同构形）+ 域内计数 27
     分账 + 白名单负测（未注册名 = internalError unknownTool——union 先例
     形）+ requiresWriter/readOnlyHint 注解断言（open/create = writer，
     list_versions = readOnlyHint）。
  2. **锁仲裁 fixture（ROADMAP 验收②）**（McpProjectToolsetTests，
     in-process 双 store 锁形）：held（进程外 store 先持锁 → project_open）
     → typed `projectReadOnly` + holder summary 携真 pid；释放（close）→
     重试成功（自然恢复）；自持切换腿（open B while holding A = close A
     checkpoint → open B）；create 已存在拒 / folder 缺失拒 / name 空拒
     （typed invalidParams 三臂）；只读宿主（writerCheck false）→
     `serverReadOnly` 前置拒；**运行时 open 后 `get_state.project` 面即时性**
     （liveState per-call 重取腿——盒持真值断言）+ 盒空 = no-project null
     面逐字节负测 + **A→B 运行时切换后 `get_state.project.path` 与项目
     相对解析锚同指 B**（:194 锚随盒腿——H2）+ **已持 A + open held B →
     typed projectReadOnly 且 `get_state.project` 仍指 A**（GUI 差分谓词 +
     held 预检装配逻辑腿——stub controller face 可变态，H4③）+
     **stale pendingConflict 挂起 + open 成功目标 → 成功应答**（反向误报
     腿——H4③）+ **http mode 运行时 open 后 `armStdioEOFReleaseOnce`
     不产生 watcher**（stdin HUP 不触发 exit——M1 门控腿）。若 in-process flock 不足以构成 held 形（flock 同进程
     语义边界）→ 升级 `McpProjectArbitrationTests` 跨进程扩展（DECISIONS
     申报；既有序列 A/B 零 diff 维持）。
  3. **list_versions golden**：fixture sidecar（versions 三条：ACTIVE + 两
     非活跃带链）→ 投影 byte-equal；`includeItems` 两档；>500 链逐版本
     截断保新端 + truncated 旗标真值（F-5 同式）；digits/relPath 双地址臂；
     **ACTIVE 链 items ≡ get_history 同源恒等断言**（同源同投影——
     description 分工句：get_history = ACTIVE 链 + note/keywords/rating
     元数据面 / list_versions = 版本树 + 非活跃链通道）；dangling
     activeVersionID 诚实投影负测（结构按盘面报、无合成）。
  4. **region/compare/list_luts golden**（McpEditingToolsetTests additive）：
     - region：归一化 rect × 渲染平面尺寸 **round+clamp** →
       `CGImage.cropping` 输出
       宽高断言 ≡ 手算像素框；越界两臂 typed 拒（invalidParams /
       roiOutOfBounds）；**两边界腿强制（M2）**：x+w==1.0 精确臂（非
       2 幂宽上 round 双入位 → clamp 归位不 nil）+ 亚像素 w 臂（round
       后宽 0 → invalidParams 携归一化值——判定以 golden 为准）；region+
       compare 组合臂（同 rect 双图尺寸恒同）。
     - compare:root：edited（fixture sidecar 预置参数）vs pristine 两平面
       尺寸恒同；pristine 臂 ≡ 无 sidecar 同图直调 render_preview（自证
       同一渲染腿）；`pristineOnly` 缺省恒等负测引用（T2 已落 Core 面——
       此处工具面缺省调用 ≡ compare:none 行为零回归断言）；载体序
       [current, root, text] 断言 + summary JSON 键集断言。
     - list_luts：临时根 fixture（M2-5-3 先例形）seeded .cube → 投影 ≡
       `installedNames`/`entry(named:)` 直调（单源恒等式）+ **seeded 内容
       正断言**（seeded .cube 的已知 name/hash/size 断言 +1 条——恒等式
       之外断「工具读对了 store」，防同义反复自洽循环——L4，M7-2 E-2
       失明 golden 教训直接套用）+ 键形根相对
       POSIX 断言 + rememberedEncodings 透传断言。
  5. **快照同批（ROADMAP 验收③）——union 显式改全点位**（McpFinalSnapshotTests）：
     冻结表 render_preview schema 行同批更新（region+compare）+ list_luts
     行 + project 三行（名序 list_versions/project_create/project_open——
     descriptors() 名序亲核后落）；计数断言 ×4（:209/:246/:274/:421）
     23→27；**组合代数**：`Set(u) == Set(e).union(Set(c)).union(Set(s))`
     改**四集合并**（project 三工具入新域——M5-1-03 先例不能照抄：本波
     再开一层）+ 域两两 disjoint 断言 +3；`descriptionKeys` +4 行
     （list_luts/project_open/project_create/list_versions）+ 对账断言随之
     过门；`makeUnionRegistry`（:190-201）传 fixture project context
     （全 nil provider——注册面零消费，不传 = union 恒 23，27 计数永不可达）+
     SC7 `startHTTPHost` 传 fixture context + **F-AC-4 注释（:210）非易碎形
     改写**（"the 9 destructive tools are the §A write face + match_color;
     the remainder are read-only or non-destructive state-changing
     (project_open/project_create)"——消除未来计数漂移）+
     **`all23` 静态属性名 → `all27`**（:184-186 定义 + :207 引用同批改名
     ——plan 原文只写测试名改名漏属性名，H1 连带）+ **过时计数注释/
     message 同批改写**（文件头注 :15「all20 → all23」与 :22
     「THE UNION (23)」+ :209 断言 message「the final count is 23」——
     避免 M7-2 式「11 read」过时注释复发）+ 测试名
     Union23→Union27 + `destructive` 九件集断言零改（新工具全非 destructive
     ——集恒等维持）。
  6. **editing 层显式改**（McpRegistrySnapshotTests）：render_preview schema
     行（region+compare）+ list_luts 行加入（6→7 + 域内计数断言）+
     **:194 计数钉显式改**（`names.count == 20` → 21 + message 同批——
     editing+culling 无 searchState 装配的闭合面计数，plan 原文只列
     :30/:152 两点位漏此处，H1）+ **:30 docstring 过时计数改写**
     （「the 14-4 union asserts all 20」）——与 union 层同批（两层
     consciously change together）。
  7. **零回归门（H1 修订——消除「searchstate 文件不改」自相矛盾）**：
     既有 culling(14) 快照层零 diff（文件不改）；searchstate 层
     **工具面**（三工具 descriptor/schema 快照）零 diff，:270 计数负测
     **显式改**（20→21 + message 同批——「无新域时的既有面」负测语义
     保持，随 list_luts 归位到 21）；**union 外五处硬编码计数钉显式改
     同批**（`McpRegistrySnapshotTests` :194 / `McpSearchStateToolsetTests`
     :270 / `McpHostTests` :243 与 :696〔:718 memory 臂断言 ≡ httpTools
     无独立硬码，随行绿〕/ `McpLauncherTests` :200——全走「显式改 +
     DECISIONS 申报」形，防 M7-2 F-1 家族复发）；`McpEditingToolsetTests`
     既有法/`McpCullingToolsetTests`/`McpProjectArbitrationTests`（序列
     A/B 零 diff）全绿；既有 23 工具
     descriptor 零 diff（除 render_preview 申报内字节——`git diff` 面 +
     快照门双证）。
  8. **Project.swift + BUNDLE-MAP + tuist generate**（本批最后动作）+
     `--bundle APP` 定向绿（新测试 + 既有 MCP 面全绿——红窗闭合点）。
- **验收标准（机检）**：`--bundle APP` 全绿；快照显式改申报在 DECISIONS；
  新文件恰一行登记 + BUNDLE-MAP 恰一行；union 全点位逐条亲核（DECISIONS
  附点位清单）；F-AC-4 注释新形在位（grep "11 read" 零命中）；
  **MCP 测试面计数残漏 grep（H1④）**：全仓 `count, 20` / `count == 20` /
  `all23` 在 MCP 测试面（Tests/LightamerTests/Mcp*）零命中——防第六处；
  五处计数钉 + 属性/注释连带点显式改申报在 DECISIONS（点位清单附）。
- **commit**: `test(m7-3): pin the goldens and grow the union snapshot to 27`

## T6 — 定向轮 + 全套 `--all` + 红线族 + 收口翻账

- **action**：
  1. **定向轮**：`caffeinate -dis Scripts/test-direct.sh --bundle App
     --bundle Library --bundle EXPORT` 全绿（App = MCP 面；Library =
     F-AC-1 FilterSQL 快照；EXPORT = pristineOnly 负测——三域覆盖本批
     全部新测试面；IOPP parity 消费方随全套轮验证〔默认参零 diff 断言
     已由 EXPORT 恒等负测预支〕）。
  2. **全套确认轮**：`caffeinate -dis Scripts/test-direct.sh --all`
     （**批准制**——本 plan 标注在案，执行时 orchestrator 派发 prompt
     即批准；运行中保持监视 + 8G 门 + MEMFAIL 机检，超门立即 kill）。
     `TOTAL|3877+ΔN/35/0|` 对账精确闭合（ΔN 逐任务记账；skip 35 构成
     声明——第三种 skip 来源 = 逐族差分申报禁静默吸收）。
  3. **红线族机检**（front-matter `red_lines` 逐条亲跑）：零新 SPM /
     `.metal` 全域零 diff / 封存面 17 件零 diff / 既有 23 工具面零 diff
     （除 render_preview 申报内字节）/ McpToolError 封闭表零 diff /
     McpTimeouts 零 diff / controller 文件零 diff / xcstrings 恰三尾块
     插入 + 一原位改（历史键零触碰）/ UserDefaults 零新键 / runModal 零
     命中 / LocalizationValue 插值禁形零命中 / Project.swift 恰一行 +
     BUNDLE-MAP 恰一行 + tuist generate 末位核。
  4. **zh-audit 对账**：`uv run python3 Scripts/zh-audit.py --check` PASS
     （4 新键 + 1 原位改——source keys 数 +4 对账）+ `--self-test` PASS。
  5. **SUMMARY + DECISIONS**：逐任务 ΔN 记账 + 三验收形态判定指针
     （compare/region golden / 锁仲裁 fixture / 快照族零意外 diff）+
     快照显式改申报（union 全点位清单 + editing 层）+ recent 不对称申报
     （D-M7-3-9）+ EOF watcher 抽取终形 + current-project 盒终形 +
     cursor 边界承接句（⑥）+ F-AC-1 收口申报段（快照补 + 本段 = 两路
     兑现）+ 中间红窗处置申报 + list_versions 键形/投影终值 +
     **评审修订申报族（M7-3-01-PLAN-REVIEW 修毕申报）**：union 外五处
     计数钉显式改申报（H1 点位清单附）+ library projectDirectory 锚退役
     申报（H2——fix 20997721 同族第二实例关闭）+ no-project http 臂与
     生产调用点清单申报 + **http 无 EOF 腿偏离句**（H3③——http 运行时
     开项目 = 进程退出 kernel 地板，checkpoint 优雅面仅 stdio）+ EOF
     arm mode 自守卫终形（M1）+ 两臂先关后开差异句（H4②——headless
     先关后开 / GUI held 预检不动当前项目）+ **寻址单源抽取申报**
     （M3——helper 只搬 searchState 现逻辑零语义变，禁顺手动 match_color
     provider〔锚病在案、M7-4 路由〕）+ region round+clamp 与两边界
     golden 终值（M2）+ pristine 键数 12→13 勘误注记（L1）。
  6. **翻账**：REQUIREMENTS MCP2-04..07 → Delivered（M7-3 commit 指针）；
     AGENTS「M7-3 架构增量」节；TODO（M7-3 条目 + 顺路件六项收口申报 +
     FIX2③ M7-4 维持 + M7-2 挂账④⑤既有项不动）；GOAL-STATE 续接点
     （M7-3 收口 → next，**MCP 快照面串行接棒**注记——M7-5 不与本波并行
     已由本波行使完毕，改动权移交下一波）。
- **验收标准（机检）**：三域定向轮绿 + 全套 exit 0 / 0 fail / 0 MEMFAIL /
  七 bundle 8G 门内 + 对账闭合 + 红线族全 PASS + zh-audit 双 PASS + 四台账
  同批落盘（历史行只追加不改写）。
- **commit**: `docs(m7-3): reconcile the full suite and close the M7-3 ledgers`

---

## 风险与回退

- **快照红窗（T2..T5 App bundle 中间态，已申报）**：render_preview schema
  自 T2 起字节变 → union/editing 两层快照测试红至 T5 显式改收口；**每任务
  gate = 构建绿 + 定向非 App bundle 绿（T1 双域 / T2 EXPORT）**（M7-2 先例
  T1-T4 构建绿门同形）；T5 `--bundle APP` 为红窗闭合点；T6 全套轮终证。
  **禁为凑绿在 T2-T4 提前改快照**（显式改集中 T5 一批 = 全点位亲核审计面）。
- **in-process flock 边界**（T5 锁仲裁 fixture）：flock 同进程二 fd 语义
  平台相关——若 held 形不可复现 → 升级 McpProjectArbitrationTests 跨进程
  扩展（DECISIONS 申报），既有序列 A/B 零 diff 红线维持。
- **GUI 内嵌臂判别缝**（D-M7-3-1，H4 修订）：判别条件 = **before/after
  差分**（pendingConflict 调用前 nil ∧ 调用后非 nil ∧ projectStore 未
  变化）+ held 目标 probeLockAvailable 无持有预检——评审亲核 controller
  状态面 `projectStore`（:52 private(set)）/ `pendingConflict`（:73 var）
  均外露可读，「状态面不外露需补缝」分支退役；差分与预检必须与
  controller 实现对表测试（禁改 controller 写面；FIX2③ 顺手窗口
  **不开**——本波 controller 零 diff 红线）。
- **EOF watcher 抽取回归**：启动路径行为逐字节不变由「同函数抽取 + once
  guard」结构保证——若抽取引入时序差（watcher arm 早于 store park）→
  T5 盒空负测 + 既有 McpProjectArbitrationTests stdio 面零 diff 双门抓；
  违例 = 回注 T4 修复。
- **region 取整歧义**：rect × 渲染宽高取整规则（round）+ **平面 bounds
  clamp + 零尺寸 invalidParams** 已进规格（M2 修订——round vs floor 之争
  收敛为 round+clamp 单式）；T5 golden 两边界腿（x+w==1.0 精确 / 亚像素
  w）为判定对象——执行中以 golden 判定为准，禁静默换取整式。
- **compare:root 载荷膨胀**：极端调用 ≈11MB（2048/q90 双臂）——typed 帽
  在位 + description 边界句；不做服务端降档（诚实拒绝优于静默缩水，
  D-M7-3-3）。
- **T5 大批量测试后置**（orchestrator 指定分批的内在风险）：T1-T4 码面
  缺陷在 T5 才暴露 → T5 发现码面缺陷 = 回注对应任务修复（fix commit +
  T5 重跑），禁为凑绿放宽断言；golden 任一不恒等 = 停手归因。
- **快照族冲突**：本波持 union 改动权——若 orchestrator 误并行派发 M7-5
  （快照面撞车）→ 立即停手上报，禁抢先合并快照表。
- 全套轮任何 fail：先归因（本批 Δfiles 窗内?）——窗外 fail = 既有缺陷，
  停手上报不静默修。

---

## Checker 关注点（独立反向核输入）

1. **Goal-backward**：ROADMAP §M7-3 行三验收形态 ↔ 任务面逐项映射——
   compare/region golden（T5 action 4 + T2/T3 schema/裁剪面）/ project
   工具与单写者锁仲裁 fixture（T4 工具面 + T5 action 2）/ 快照族零意外
   diff（T5 action 5-7 显式改全点位 + 零回归门）；REQUIREMENTS MCP2-04..07
   四行无孤儿项（render_preview 扩展 = MCP2-04 / list_luts = MCP2-05 /
   project_open+create = MCP2-06 / list_versions = MCP2-07）；Alcedo 四命令
   对表锚（render.preview / project.open+create / versions.list / lut.list）
   → 四工具一一对应（偏离申报面：内联 JPEG vs PNG 文件、默认 1024 vs
   2048、无 photo_count——CONTEXT D-M7-3-3/6 申报）。
2. **OQ 兑现核**：D-M7-3-1..10 逐条对任务面——①双宿主路由 + requiresWriter
   （T4）②归一化 0..1 + 两工具分界句（T2/T3 description）③默认 root +
   预算句 + 无降档 + 30s 单窗（T3）④四域分层 7+14+3+3=27（T5 快照）⑤
   pristineOnly 唯一 Core 触点 + 双臂不共享 decode（T2/T3——grep
   `pristineOnly` 恰两处 + body 两遍调用形）⑥无 photo_count 出参四键
   （T4 schema）⑦EOF watcher 幂等 arm + 盒读体 + 启动路径零变（T4——
   grep 双调用点 + once guard）⑧自携同形两 seam + version_ref 零命中
   （T4——装配点同 closure 变量 + grep）⑨零新增 promoteRecent 面 +
   不对称申报（T4 controller 零 diff + T6 DECISIONS）⑩migrate 既有语义 +
   internalError 兜底（T4——零新迁移面）。
3. **快照族纪律**：union 显式改全点位（计数 ×4 + 组合代数四集合并 +
   descriptionKeys +4 + 两处 fixture context + F-AC-4 注释 + 测试名 +
   **all23→all27 属性名 + 头注 :15/:22 + :209 message 过时计数连带**）+
   **union 外五处计数钉显式改**（:194/:270/:243/:696/:200 + :30
   docstring——H1 清单）+ editing 层 render_preview/list_luts 显式改
   （两层同批）+ **count, 20 / all23 零残漏 grep** + DECISIONS
   申报；culling 层零 diff + searchstate 工具面零 diff（:270 计数显式改
   例外申报）；「本波持权 + M7-5 禁并行」在
   plan 头注与红线双写。
4. **顺路件六项收口**：F-AC-1 快照新法 + DECISIONS 段两路兑现 / F-AC-2
   默认参 + :374 透传 + get_state.control.lock 真值断言 / N2-1 恰一键 +
   golden 同批 / N2-3 typed 抛 + nil 载体负测 / N2-4 requestFailed 臂 /
   ⑥ DECISIONS 句 / F-AC-4 :210 非易碎形（grep "11 read" 零命中）；
   FIX2③ 不承载（controller 零 diff 门）。
5. **零新 render 代码**：Core diff 面 = renderedPlane 恰两处（签名 +
   :236 条件化）——函数其余逐行零触；零新 .metal；pristineOnly 恒等
   负测两法在 QuickLookRendererTests（byte-equal 判定）；全消费方调用点
   零 diff（9 调用点/5 文件——L2 清单见红线；MCP body :835 = T3 申报内
   改形——diff 逐 hunk 核）。
6. **错误码/超时零新增**：McpToolRegistry.swift 零 diff（封闭表 +
   McpTimeouts 双零）；project 族五既有码消费点在 ProjectToolset（grep
   各码）；writer gate 分支结构零 diff（registry :333 段——requiresWriter
   面结构性走既有门）。
7. **运行时缝诚实面**：liveState 盒读 per-call（启动捕获退役——**范围 =
   liveState + :194 projectDirectory 锚**，A→B 切换后解析锚随盒——H2）+
   盒空 = no-project null 逐字节负测 + no-project 双臂（stdio/http）换形
   open 前行为逐字节 + **生产调用点全清单（:254/:263/:378/:390/:410）
   传 project provider**（H3——不传 = 三工具静默缺席）+ 失败中间态纪律
   （close 成功 open 失败 = 盒清空）在 provider
   实现面；EOF watcher once guard（多次 open 只 arm 一次）+ **arm 内部
   mode==.stdio 自守卫**（M1——http daemon 不自杀）+ GUI 差分谓词与
   held 预检顺序语义（预检在 openProject 之前——held 目标不触
   openProject 不动当前项目；差分快照在预检通过后的调用前后——H4）。
8. **SC 可机检性**：每条 SC 有命令级判据（byte-equal / grep / 计数断言 /
   对账行 / 定向 bundle 绿），非「目测」；expected_all 对账式非死数；
   skip 35 构成声明条款在 T6。
9. **xcstrings 双形纪律**：四新键尾块纯插入（历史键字节与顺序零触碰——
   diff 逐 hunk 核）+ render_preview **原位值改**（非插入——DECISIONS
   申报）；描述键显式 `String(localized:defaultValue:)` 形态（插值禁形
   regex 零命中）；zh-audit --check（source keys +4 对账）+ --self-test
   双 PASS。
10. **登记纪律**：Project.swift 恰一行（McpProjectToolsetTests）+
    BUNDLE-MAP 恰一行（APP 域）+ tuist generate 恒末位（L041）——commit
    顺序核（登记与测试同 commit，generate 最后动作）。
11. **零回归面**：既有 23 工具 descriptor/handler 零 diff（除 render_preview
    申报内字节）；McpProjectArbitrationTests 序列 A/B 零 diff 绿；
    culling 快照零 diff + searchstate 工具面零 diff（:270 计数显式改
    例外）；`--all` 3877+ΔN 对账闭合（IOPP parity
    消费方随全套验证——EXPORT 恒等负测预支）。
12. **评审放行门复核**（M7-3-01-PLAN-REVIEW §四修毕条件）：修订批后按
    放行门 1-5 逐条复核——H1 五处计数钉 + 连带点 + files_modified 增行 +
    红线改写 + 零残漏 grep；H2 :194 锚退役 + 切换锚断言腿；H3 http 臂 +
    生产调用点清单 + DECISIONS 偏离句；H4 差分谓词 + held 预检 + 仲裁
    fixture 两腿；M1/M2/M3/L1-L4 一句话规格钉死——复核结论记
    `M7-3-CHECKER.md`。

---

## 评审修订注记（2026-10-17 fixer 批——M7-3-01-PLAN-REVIEW 放行门复核）

评审正本 = 同目录 `M7-3-01-PLAN-REVIEW.md`（总评「须修后放行」：4 高 /
3 中 / 4 低）。本节 = 修订批汇总 + 放行门 1-5 逐条复核结果。修订前
fixer 对评审 file:line 证据独立抽验亲核——五处计数钉
（:194/:270/:243/:696/:200）/ all23 属性（:184-186/:207）+ 注释（:15/
:22/:209/:30）/ :194 projectDirectory 捕获 / 裸 `McpSearchStateContext()`
恰两处（:256/:267）/ pristine payload 亲点 12 键 / renderedPlane 全仓
9 调用点 5 文件（含 QuickLookRendererTests :206/:227）/ controller 字段
外露（:52/:73）/ `SingleWriterLock.probeLockAvailable` 既有面 /
`resolveImageURL` :951 private static 吃 context / detailCrop :1096-1097
renderFailed——**全部与评审标称吻合，零坐标漂移**。

1. **H1 复核 PASS**——T5 action 5/6/7 + read_first + files_modified
   （McpHostTests / McpLauncherTests 增行；McpSearchStateToolsetTests/
   McpRegistrySnapshotTests/McpFinalSnapshotTests 注记扩展）落位；
   红线/T5 验收补 `count, 20`/`count == 20`/`all23` 零残漏 grep；
   「searchstate 文件不改」红线条改写为「工具面零 diff + :270 计数负测
   显式改」——plan 内部自相矛盾消除。
2. **H2 复核 PASS**——T4 action 3 liveState 退役范围补 :194 library
   projectDirectory 锚（`projectURL.deletingLastPathComponent()` 捕获
   亲验在位；`20997721` 同族第二实例引证入注）；T4 验收 + T5 仲裁
   fixture 增 A→B 切换锚断言腿。
3. **H3 复核 PASS**——no-project 双臂（:254-256 stdio / :263-267 http）
   换形 + 生产宿主调用点全清单（runHeadless :254/:263 /
   runHeadlessArbitrated :378/:390/:410）传 project provider 入 T4
   action 3；grep 机检「裸 McpSearchStateContext() 在 controller 内零
   命中」；http 无 EOF 腿偏离句入 T4 action 3 + T6 DECISIONS。
4. **H4 复核 PASS**——T4 action 4 谓词改 before/after 差分（消已持项目
   误报成功 + stale pendingConflict 反向误报两洞）+ held 目标
   probeLockAvailable 无持有预检（openProject 之前——held 不触 open，
   一次调用不得掀用户正开项目；controller 零 diff 保持）；T5 仲裁
   fixture 增两腿（held B 不动 A / stale conflict 成功应答）。
5. **M1/M2/M3/L1-L4 复核 PASS**——EOF arm mode 捕获 + 内部门双保险
   （M1）；region round+clamp + 交后零尺寸 invalidParams + 两边界
   golden（M2）；resolveImageURL 共享 helper 抽取形（直调不可达亲验——
   禁复制形，match_color provider 禁顺手动）（M3）；pristine 键数
   12→13 勘正（SC/T1/files_modified 三处）（L1）；消费方口径 9 调用点
   /5 文件（红线/T2 验收/Checker 关注点三处）（L2）；
   ProjectOpenOutcome.name = url stem 派生（L3）；list_luts golden 补
   seeded 内容正断言（L4）。

修订全为 plan 文本级（点位清单增补 / 谓词改写 / 规格句 / files_modified
增行 / 勘误），不动架构、不动任务切分、不动 OQ 裁决（OQ-M7-3-1..10
生效值原样；CONTEXT 三处实现级细节同步修订，见该文件修订注记）。
独立复核正本 = `M7-3-CHECKER.md`（放行门逐条验证 + 猎残 + 结论头）。
