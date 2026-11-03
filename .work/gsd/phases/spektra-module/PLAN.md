# 光谱核 module 化 P1 执行计划（spektra-module PLAN v2，2026-11-03）

> 基线 HEAD（亲核）：`9a69d0e4 docs(sm): plan review — FAIL / 2 blocking + 10 major + 9 minor`
> v1（25KB，在册 `be6e5886`）经 zcode review lane 评审 FAIL——本 v2 逐条消解，
> 修法正本 = 同目录 `SM-PLAN-REVIEW.md`（§一/§二/§三）；设计正本 = `RESEARCH.md`。
> 范围 = **P1 only**：module 化不改核；process 不 bump（B2 新理由）；sidecar 零新键零 bump。
> 等价口径 = **ε 带**（B2：逐位恒等 v1 口径作废，仅 legacy 回放臂保留逐位）。

## §v2 v2 changelog（评审 finding → 消解位置）

| finding | 消解 | 位置 |
|---|---|---|
| B1 挂载作用域三互斥 | spektraFilm = grade 层专属 op；迁移/面板复用 `addPlacement()` 形态（最上层 adjustment 层，无则 `addAdjustmentLayer()`）+ `addModuleToLayer`；参数写走 `recordLayerChange` / D-H1 layerScope 腿；谓词 = 全作用域 presence 单源 `hasSpektraFilmInstance`；基链/`recordChange` 对 spektraFilm typed reject；**MCP 判定 = P1 显式拒绝**（`apply_params` 对 spektraFilm 返 invalidParams 写理由——扩层参数 = MCP schema 破坏性变更，P2 立项） | D-SM-8/§0.2 T3'/T4'/T6'、T4'-4/T6'-6 AC |
| B2 逐位主门不可达 | 口径改 ε 带：module 路径两次 f32 ACEScc 往返，相对误差 ~1e-6/往返（log 放大 12×），膠片链斜率再放大；带宽三段：\|v\|<2^-15 绝对带 2e-5、中段相对带 5e-4、高光 >1 相对带 2e-3（实测收窄只许紧不许松）；AC-T7'-1/AC-T7'-2 改容差断言（L048：linear 回 + `Double(Float(x))`）；「process 不 bump」理由重写 = 用户确认显式转换 + legacy 档未转换逐位走旧腿（M9-4 colorWheels 小近似先例同形） | D-SM-9、T7' 全节、D-SM-6 修订 |
| M1 carrier 导航重灌 | sync 腿改「全作用域 spektraFilm 在场 → 清 carrier；否则 = effectiveFilmRecord」；`versionActionDidChange` 同款接入；谓词 presence 语义（enabled 无关）；DECISIONS 登记成对写锚有意解除（driftDetected 只读 history，J5，不误报） | D-SM-10、T3'-4/T4'-5、AC-T3'-4/AC-T4'-5 |
| M2 工厂访问级 | 非封存文件立 public 包装缝 `FilmLegFactory`（同 target 调 internal `assembleFilmLeg`，传 `piece.renderProcess`）；D-SM-2 改写经该缝；删 T2-3（HEAD 已有 public init，FilmTailPolicy.swift:355-365）；AC 钉 `assembleFilmLeg` 访问级/签名零 diff | D-SM-2 修订、T2'-2、AC-T2'-3 |
| M3 histogram 调用点 | T5'-1 改「module 侧新增（T2' 已实现），legacy `runFilmLeg` 原样保留至 deprecation」；AC 改 `runFilmLeg` 函数体 diff 为空；删 T5/T2 重复描述 | T5' 全节、AC-T5'-2 |
| M4 单实例无执行面 | 全入口守卫：面板 enable 定位已有；add 菜单已有则隐藏；MCP typed reject；paste=单实例合并（目标同持 instance 则覆盖、不同时持与 carrier=门判 module 胜但写迁移 UX 而非静默）；paste→legacy 档 = 拒绝（走迁移确认）；`isAdjustmentTransferable` 对 spektraFilm 处置 = 可迁移但单实例合并 | D-SM-11、T6'-4、AC-T6'-5 |
| M5 env 门与闭包互斥 | 采 (a)：registry **恒注册**（不门），env 只门 UI/迁移/写入口；AC-T1-2 重写；计数口径修正唯一 op 19→20、行 20→21；`testOwnerMatrixOverAllEighteenRows` 加行；`testAllCatalogOpsAreDefaultFaceRegistered` 零改（默认面恒注册即过）；既有 3-4 法改动申报 + ΔN | T1' 全节、AC-T1'-2..4 |
| M6 process 门失效 | process 门 film 源改「`hasLegacyFilmRecord` ∨ 全作用域 spektraFilm 在场」；第三标记形（spektraFilm params verbatim 经 `recordLayerChange`）；模块档禁走 film-item 标记形；`migratable` 扩认 `.convertToModule` | D-SM-6 修订、T4'-3、AC-T4'-4 |
| M7 渲染入口盲区 | T6' 渲染入口清单逐面裁定：export include / thumbnail-grid strip 落 SessionThumbnailProvider 物化层（禁改 SessionThumbnailRenderer 零触）/ QuickLook include / ColorMatch strip（`filmTail: nil` 同语义）；T8' grid 成本改可度量指标 | T6'-3、AC-T6'-3/4、T8'-2 |
| M8 中间面内存 | 中间面复用判定：out 纹理承接首段 + 单中间面（借 SpectralScratchAllocator slot）；100MP 峰值 RSS 探针 AC（`LIGHTAMER_PERF_PROBE=1` + XCTSkipUnless，module 腿相对 legacy 腿 ΔRSS ≤ 1 张全帧平面 ~1.6GB）；全套前贴线 bundle 定向轮 | D-SM-12、T2'-4、AC-T2'-6/T8'-1 |
| M9 测试策略 | 桥接测试改名 `SpektraBridgeParityTests`（命中 IOPP 路由）；夹具 = 合成小平面三形态 + 1 张降采样 CC0；**每任务同批**登记 Project.swift + BUNDLE-MAP + `tuist generate`；T8' 基线写死「M9-2 收口值 + ΔN − 4」 | T7' 全节、各 T 登记行、T8'-1 |
| M10 蒙版/回退缺项 | T7' 增蒙版 AC（层 opacity 0.5 / 径向蒙版 = 层混合公式期望，合成平面）；T8' 走查增蒙版项；T4' 增 env-off 迁移档 AC（toast/数据保留/legacy 不复活/重开 env 后 enabled 显式语义 = 仍 disabled 需手动开）；**判定 = convert 前打 pre-convert 备份**（M2-8 `pre-migrate.N-M.bak` 轮换先例），DECISIONS 另接受非逐位回退的两层含义 | T7'-3/T8'-2、T4'-6、AC-T4'-6 |
| m1 基线漂移 | 执行基线 = 派遣 HEAD（≥ `9a69d0e4`）；函数体 md5、golden md5 在执行 HEAD 重钉 | 卷首基线行、T2'-AC 注 |
| m2 API 名漂移 | `order(of:)`→`order(for:)`；`recordChange(opName:params:)`→ 基链/层两腿签名分写；md5 提取法写死（签名行至同缩进闭合 `}` 确定性截取） | 各 AC、T2'-AC 注 |
| m3 populate 内读 env | `populate(_:defaultFace:filmModule: Bool = false)` + `isFilmModuleRequested`（M5(a) 下恒 true 调用——注册恒开，参数保留作未来缝）；迁移行/写入口门以 registry 可解析为单源 | T1'-3、AC-T1'-2 |
| m4 IopCatalog 未决 | **裁定 = 不加行**（handwritten 19-op 表是 key REFERENCE 非 whitelist；spektraFilm 走 full-JSON replace 无字段参考，与 payload/geometry/denoise 同待遇）；`mcp_tool_desc_apply_params` 零改；反射守卫零触 | T6'-6 注、AC-T6'-6 |
| m5 Film 卡 grep 集 | grep 集扩至 `NodesPanelModel.FilmCardProjection/filmCard` + `EditorNodesPanelView.filmCardView/filmCardMarker` + AX id `editor.nodes.film`；Film 页入口（`LightamerShell.swift:2255` filmPanel 动作）保留声明 | AC-T6'-7 |
| m6 宽容度数据源 | T6'-4 补宽容度面板/descriptor 数据源换锚（`currentFilmRecord` carrier-only → live 实例 record）；`FilmStatsSnapshot.last` 语义注记 = 模块档为层 46.7 输入统计（R3 同族）；+1 AC | T6'-4、AC-T6'-5 |
| m7 undo 步数 | 转换 undo 步数声明（有层 = 2 item：addModuleToLayer 结构 + recordLayerChange 参数；无层 = 3 item：+ addAdjustmentLayer）；已有层优先（`addPlacement()` 形态已是最少）；AC-T4' 按步数断言 | T4'-5、AC-T4'-5 |
| m8 零触碰声明补行 | 补：UserDefaults 零新键 / filmPlacement 20.8 零改 / process 常量断言 AC（`RenderProcessVersion.current == 3`）/ xcstrings 尾块纯插入 | 封存表补行、AC-T8'-1 |
| m9 迁移文案键预算 | `ProcessMigrationInputs` 加文案字段（title/body/button/confirm，App 非封存）；键预算改 ≤4（`panel_film_convert_{title,body,button,confirm}` 新族，cancel 复用中性键）；convert 行独立 AX id 前缀 `film.convert.*` | D-SM-6 修订、T4'-4、AC-T8'-2 |

（任务编号：v2 重编为 T1'..T8'，与 v1 T1..T8 一一对应；AC 同理。DECISIONS 另勘误 RESEARCH §4.2「或 nil = 基链」。）
## §0 裁决冻结（预批准原文转录，v2 增 B1/B2 勘误注）

- OQ-1(a)：`.oneInstance` 单实例（需求出现再撤）。**v2 注**：flag 本体无执行面（M4 亲核：零消费者）——执行面 = D-SM-11 全入口守卫。
- OQ-2(a)：保留直方图自适应求解；P2 挂账不立项。
- OQ-3(a)：spektraFilm 入 GradeCatalog + op 内 ACEScc 往返（RESEARCH §4.1(a) 形态）。
- OQ-4(b)：sidecar 版本号不 bump、键面零新键；旧档内容判定（`filmRecord` 键在场 && 无 spektraFilm 实例 = legacy 腿）。**v2 注**：后一条件读全作用域 presence 谓词（B1）。
- OQ-5(a)：节点图 Film 卡 P1 退役。
- OQ-6(a)：串行——以派遣时 HEAD 为基线（含 M9-2 全部交付）。

## §0.1 判定（v1 D-SM-1..7 修订 + v2 新增 D-SM-8..12）

| # | 判定 | 内容 |
|---|---|---|
| D-SM-1 | **prepareChain 无需新折叠缝**（v1 保留，J1 亲核成立） | stats = 纯函数(本层 46.7 输入平面)，输入平面内容被 levelHash 链完全键控。不新增 `runtimeFoldHash` 缝；AC 由 T7' 负测钉死。若证伪，回落 RESEARCH §4.4 缝（PixelPipe 例外 +1 hunk，需 re-plan 申报）。将来触发器：会话内 pack 重载（平面键缺材料内容项）——登记非本轮项。 |
| D-SM-2 | **执行核 delegate 形态**（v2 修订，M2） | `SpektraFilmModule.process`：直方图（`FilmStatsSeam.histogram` 同缝，材料已解析才跑）→ public 包装缝 `FilmLegFactory.assemble(record:materialPairHash:histogram:plane:metal:renderProcess:)`（新文件 `LightamerCore/Sources/Pipe/Film/FilmLegFactory.swift`，非封存；同 target 内调 internal `PixelPipe.assembleFilmLeg`；`renderProcess` 传 `piece.renderProcess`——`IOPiece` 已携，`ColorWheelsModule.swift:318` 先例）→ 得 payloads → 构造 `FilmMethodBox`（HEAD public init，`FilmTailPolicy.swift:355-365`，零新缝）→ 转发 `box.process` → ACEScc 往返。密度臂/光谱臂工厂函数体零 diff（md5 钉死），v1 冻结维持。 |
| D-SM-3 | **history 键族：保留只读 + 新写停产**（v1 保留） | `HistoryItem.filmRecord` / `filmDocumentScope` / `commitFilm` 保留解码与 legacy 档回放；新写入（含迁移 commit）一律层内标准写入（B1：`addModuleToLayer` + `recordLayerChange`，非 `recordChange`）。迁移 commit label 复用 `history_film_enable` 族语义，零新键。 |
| D-SM-4 | **导出 filmTail 载体：保留为 legacy 通道**（v1 保留） | `enqueue(filmTails:)` 参数与 `$jobFilmTail` TaskLocal 双轨期保留；新档传 nil。`ExportQueueContract` **零 diff**。 |
| D-SM-5 | **ACEScc 往返走 kernel 复用**（v1 保留，J4 命名/方向成立） | process 内 `grade_acescc_out`（log→linear）→ 胶片链 → `grade_acescc_in`（linear→log），复用 `ACESccInModule/OutModule` PSO（`ACESccKernel.in/outFunctionName`），零新 kernel。`needsEnvelope` skipsEnvelope 优化 P1 不做。等价性见 D-SM-9（ε 带）。 |
| D-SM-6 | **迁移行 = 新 action case + 文案参数化 row**（v2 修订，M6/m9） | `FilmMigrationAction` 新增 `.convertToModule` case；`evaluate` 签名加 `hasLegacyFilm: Bool = false` 默认参（M8-3/M9-4 调用形零改）；`migratable` 扩认 `.convertToModule`；process 门 film 源改「`hasLegacyFilmRecord` ∨ 全作用域 spektraFilm 在场」（两调用点 `FilmPanelModel.swift:579-584` / `IOPPanelProvider.swift:124` 同改，谓词单源）；**第三标记形** `recordLayerChange` params-verbatim（模块档禁走 film-item 标记形）；`ProcessMigrationInputs` 加文案字段（title/body/button/confirm，App 非封存）；convert 键族 `panel_film_convert_{title,body,button,confirm}`（≤4，cancel 复用中性键）；AX id 前缀 `film.convert.*`。判别优先级：editingInFlight > convertToModule > process migrate——同一文档双迁移先转 module，process 迁移随后自然触发（门已修，M6 成立）。 |
| D-SM-7 | **多层档漂移提示归入 convert 键族**（v2 修订，m9 联动） | 统计对象变更（顶面→本层 46.7 输入）如实告知：convert 确认 sheet body 内一段。键预算并入 D-SM-6 的 ≤4（不另立 D-SM-7 预算）。T8' 对账。 |
| D-SM-8 | **grade 层专属 op**（v2 新增，B1） | spektraFilm 钉死 NodeOwnershipCatalog `.grade` 语义 + 层专属：一切创建走 `addPlacement()` 形态（最上层 adjustment 层，无则 `addAdjustmentLayer()`）+ `addModuleToLayer`；参数写走 `recordLayerChange` / D-H1 `commitContinuousEdit(layerScope:)`；基链写入（`recordChange` 直调、MCP `apply_params`、Copy/Paste 全局 epoch、merge 入基链）对 spektraFilm = typed reject（各一条负测 AC）。判别谓词 `hasSpektraFilmInstance` = 全作用域 presence 单源（全局 effectiveInstances ∪ 各 AdjustmentLayer `ModuleRegistry.effectiveInstances(layer:)`，presence 不看 enabled），供 filmTailPolicy / filmLegRequestTags / 迁移行 / 面板 / sync 腿 / process 门共用。 |
| D-SM-9 | **ε 带等价口径**（v2 新增，B2） | module 路径 = 层包夹 + module 内往返 = **两次 f32 ACEScc 往返**；编码 `(log2(v)+9.72)/17.52`：log 域 1 ulp ≈ 6e-8，decode 放大 ln2·17.52 ≈ 12× → 单次往返相对误差 ~1e-6；矩阵逆 f32 行叠加；胶片链（密度 65³ 四面体 / 光谱 tc LUT）非线性斜率再放大。**带宽**：\|v\|<2^-15 绝对带 2e-5；中段相对带 5e-4；>1 高光相对带 2e-3。执行实测收窄只许紧不许松；超带 = T2' 形态回炉（纯函数 FMA 臂）+ re-plan。比较空间按 L048。**process 不 bump 新理由**：迁移 = 用户确认显式转换（M9-4 colorWheels「a small approximation can remain」先例同形），legacy 档未转换前仍逐位走旧腿（AC-T4'-1 保留逐位）；ε 级差异不构成 M6-2 改观感。 |
| D-SM-10 | **sync 腿门控**（v2 新增，M1） | `syncFilmCarrierWithHistory` 改「全作用域 spektraFilm 在场 → 清 carrier；否则 = effectiveFilmRecord」；`versionActionDidChange` 同款接入（修既存姊妹缺口：只 sync DRT 不 sync film）；已迁移档 M3-3 成对写锚**有意解除**（driftDetected 只读 history，J5，不误报——DECISIONS 登记）。 |
| D-SM-11 | **单实例全入口守卫**（v2 新增，M4） | 面板 enable：已有则定位（已有语义保留）；add 菜单：已有则该行隐藏（`gradeScopeEntries` 过滤，不动 `templateInstance` ——spektraFilm 须进 `templateInstance` 供 `addPlacement()` 形态用）；MCP：typed reject（D-SM-8）；paste：单实例合并（目标同持 instance 则覆盖；paste→legacy 档 = 拒绝，提示走迁移确认）；`isAdjustmentTransferable` 对 spektraFilm = 可迁移但单实例合并（谓词单源内加 op 特例）。版本/粘贴走同谓词。每入口一条负测/正测 AC。 |
| D-SM-12 | **中间面复用**（v2 新增，M8） | `IOPModule.process` 只给 in/out 两纹理；D-SM-5 链「out→linear→胶片→linear→log」以 **out 纹理承接首段 + 单中间面**（借 `SpectralScratchAllocator` slot，串行复用纪律）实现——P1 单 pass 融合不做（kernel 复用红线优先），中间面恒 ≤1 张全帧 float32（100MP ≈ 1.6GB）。峰值 RSS 探针见 AC-T2'-6；全套前贴线 bundle 定向轮见 T8'-1。 |
## §0.2 任务总览（v2）

| T | 标题 | Δ文件 | ΔN（新测试法） | 封存面 |
|---|---|---|---|---|
| T1' | 注册骨架：V50Order + GradeCatalog + Registry（恒注册）+ env 门写入口 | +1∕~4 | 7 | V50Order、GradeCatalog |
| T2' | SpektraFilmModule 本体 + ACEScc 往返臂 + FilmLegFactory 包装缝 | +2∕~2 | 10 | —（delegate 形态） |
| T3' | 参数载体迁移：谓词单源 + sync 腿门控 + sidecar 键 legacy 只读 | ~5 | 10 | —（schema 零触碰） |
| T4' | 双轨读判别门 + 迁移行 + 备份 + env 门接线 | ~7 | 13 | PixelPipe（legacy 门 hunk→注释） |
| T5' | 求解链不动验证 + tile 政策钉死 | ~1 | 4 | — |
| T6' | 下游面：DRT 交接/导出/渲染入口清单/面板换锚/Film 卡/MCP 拒绝 | ~11 | 16 | PixelPipe（upstream 语义零 hunk） |
| T7' | ε 带桥接测试 + 蒙版 AC + golden 迁移 + BUNDLE-MAP | +2∕~6 | 16 | — |
| T8' | 收口：贴线定向轮 + 全套 + 走查 + SUMMARY/DECISIONS + 申报终表 | docs | 0 | 终表复核 |
| 合计 | | +5 新源 / ~36 触碰 | **76** | PixelPipe/V50Order/GradeCatalog 三件 |

**登记纪律**：每任务各自同批登记 Project.swift + BUNDLE-MAP + `tuist generate` 末动作（L041/M2-4-0 E2）——M9 修法，各 T 末行单列登记项。
**env 门** `LIGHTAMER_FILM_MODULE=1` 默认 off：M5(a) 下**注册恒开**，env 只门 UI/迁移/写入口（T1' 谓词单源读 registry 可解析 + env 双条件；AC-T1'-2 钉死）。

## T1' 注册骨架（V50Order + GradeCatalog + Registry 恒注册）

目标：46.7 槽位与目录行就位；M5(a)：注册恒开，env 只门写入口/UI。

编辑点：
1. `LightamerCore/Sources/Foundation/V50Order.swift`：`("filmicrgb", 46.0)` 后插入 `("spektraFilm", 46.7)` verbatim 行（dt `iop_order.c` v50 同值；形参注释引 RESEARCH §4.1）。add-only，一行。
2. `LightamerIOP/Sources/NodeOwnershipCatalog.swift`：GradeCatalog 新增第 21 行 `spektraFilm`（owner .grade；`identityJSON = json(of: SpektraFilmModule.Params())`；`panelExposures` = Film 面板键族现行清单复用 `film_*` 15 键 stem——零新键）。E7 口径修正：唯一 op 19→20、行 20→21（M5）。
3. `LightamerIOP/Sources/Registry.swift`：`populate(_:defaultFace:filmModule: Bool = false)` 加默认参（m3；M5(a) 下生产组装根恒传 true——注册恒开，参数保留作未来缝）+ `public static var isFilmModuleRequested`（`ProcessInfo` env 读点，KD-3 `isFullFaceRequested` 同款形态，供写入口/UI 门读）；`defaultFaceDisabledOpNames` **不加** spektraFilm；`editingDefaultInstances` 不 seed。
4. 既有测试改写（申报）：`GradeCatalogTests.swift:95` 期望 19→20；`testOwnerMatrixOverAllEighteenRows`（:144）加 `"spektraFilm": .grade` 行；`CatalogAddFaceTests.swift:224`（若 spektraFilm 进 add 菜单——D-SM-11 隐藏语义下仍进枚举再过滤，期望更新）；`testAllCatalogOpsAreDefaultFaceRegistered`（:130-139）**零改**（恒注册即过——M5(a) 的收益）。
5. 登记：`Project.swift` + BUNDLE-MAP（RegistryFilmModuleTests 行）+ `tuist generate`。

AC（机检）：
- AC-T1'-1：`V50Order.order(for: "spektraFilm") == 46.7`（m2 改正名），且排序位恰在 filmicrgb 与 lut3d 列表序之间。
- AC-T1'-2：`ModuleRegistry.makeBox("spektraFilm")` env 缺席/在场**均非 nil**（恒注册）；写入口/UI 门（迁移行 `migratable`、面板 enable、add 菜单行）env 缺席时全隐（M5(a) 改写、m3 联动：门以 `isFilmModuleRequested` 为单源，注入式可测）。
- AC-T1'-3：`GradeCatalog.item(opName: "spektraFilm")?.owner == .grade`；E7 checker 全绿（唯一 op 20、行 21）；`testOwnerMatrixOverAllEighteenRows` 全绿。
- AC-T1'-4：默认面测试进程（env 缺席）`DefaultFaceTests` 计数契约逐位不变（full−6 不动——spektraFilm 不入默认面集合）；`McpSchemaCatalog.encodedDefaults` 读 `GradeCatalog.item` 面：spektraFilm 行在但 MCP 写拒绝（D-SM-8，T6' AC 覆盖）。

ΔN = 7（V50OrderTests +1、RegistryFilmModuleTests 新文件 5 恒注册/门语义、GradeCatalogTests E7 +1；既有 3-4 法改写不计 ΔN，T8' 对账列申报）。
封存面：V50Order（add-only dt-verbatim 行）、GradeCatalog（第 21 行 + E7 期望）。

## T2' SpektraFilmModule 本体 + ACEScc 往返臂 + FilmLegFactory

目标：可注册 module，process = ACEScc 往返 + 经包装缝 delegate 现有 film 腿装配；flags `.supportsBlending | .oneInstance`，不设 `.allowTiling`。

编辑点：
1. 新 `LightamerIOP/Sources/SpektraFilm/SpektraFilmModule.swift`：
   - `opName = "spektraFilm"`，`iopOrder = 46.7`，`flags = [.supportsBlending, .oneInstance]`，`defaultColorspace = .RGB`。
   - `Params = { record: FilmRecord }` 原样嵌入（`ParamsCoding` 经 `FilmRecord` Codable；stableHash 字段复用 record 面；求解值不入 Params——D-SM-2）。
   - `modifyROIOut/In` 恒等直通；**不覆盖 `tileHalo`**（协议默认 0 = 永不 tile，R1 缓解的唯一实现点）。
   - `process`：输入（ACEScc log）→ 首段承接 out 纹理 `dispatch2DTexture(grade_acescc_out)` → 单中间面（D-SM-12：借 `SpectralScratchAllocator` slot）→ 直方图（`FilmStatsSeam.histogram` 同缝，材料已解析才跑）→ 包装缝 `FilmLegFactory.assemble`（传 `piece.renderProcess`）→ `FilmMethodBox`（HEAD public init）→ `box.process` 转发 → `dispatch2DTexture(grade_acescc_in)` → 回 ACEScc。（D-SM-2/D-SM-5/D-SM-12）
   - `blitIdentity` 路径：材料未解析/求解失败 = 恒等直通 + 与旧腿同签名 toast（RESEARCH D14）。
2. 新 `LightamerCore/Sources/Pipe/Film/FilmLegFactory.swift`（非封存）：`public enum FilmLegFactory` + `public static func assemble(record:materialPairHash:histogram:plane:metal:renderProcess:)` → 同 target 调 internal `PixelPipe.assembleFilmLeg`（M2 修法；`renderProcess` 透传供 exhaustive switch 分叉）。
3. `SpektraFilmParams.swift` 若需 ParamsCoding 适配层则新建，否则并入主文件（Δ文件 −1，SUMMARY 实报）。
4. 登记：`Project.swift` + BUNDLE-MAP（SpektraFilmTests 行）+ `tuist generate`。

AC（机检）：
- AC-T2'-1：`SpektraFilmModule.flags == [.supportsBlending, .oneInstance]`；`.allowTiling` 缺席。
- AC-T2'-2：`tileHalo` 默认 0；`modifyROIIn == identity`。
- AC-T2'-3：`assembleDensityFilmLeg` / `assembleSpectralFilmLeg` 函数体 md5 == 执行 HEAD 基线值（v1 冻结红线；**提取法**（m2）：函数签名行至同缩进闭合 `}` 确定性截取；基线在派遣 HEAD 重钉（m1））；`PixelPipe.assembleFilmLeg` 访问级 internal + 签名零 diff（M2）。
- AC-T2'-4：材料未解析档 `process` 输出逐位 == 输入（blitIdentity）。
- AC-T2'-5：identityJSON 往返：`Params()` 编码解码逐字节 == `GradeCatalog` 登记 `identityJSON`。
- AC-T2'-6：中间面恒 ≤1 张全帧 float32（分配计数断言，合成平面）+ 100MP 峰值 RSS 探针（`LIGHTAMER_PERF_PROBE=1` + XCTSkipUnless 默认 skip：module 腿相对 legacy 腿 ΔRSS ≤ 1 张全帧平面 ~1.6GB；M8）。

ΔN = 10（SpektraFilmTests 新文件 10：1-1/2-2/2-4/2-5 各 1、2-3 md5 双臂 2、2-6 分配 1 + RSS 探针 1 + 工厂透传 2。落域 IOP/Core 级）。
封存面：无（IOP 新文件 + Core Film/ 新文件；PixelPipe/工厂函数体零 diff）。

## T3' 参数载体迁移（谓词单源 + sync 腿门控 + sidecar 键 legacy 只读）

目标：判别谓词单源就位；sync 腿门控；`filmRecords` 载体与 sidecar `filmRecord` 键转 legacy 只读；history 键族保留解码停产新写（D-SM-3）。

编辑点：
1. `App/.../UI/Shell/WorkspaceModel.swift`：`filmRecords` 载体标注 legacy（doc comment + deprecation 注记）；新增 `hasLegacyFilmRecord(for:)`（carrier 在场，OQ-4(b) 条件一）与 `hasSpektraFilmInstance` **全作用域 presence 单源**（B1/D-SM-8：全局 `effectiveInstances()` ∪ 各 AdjustmentLayer `ModuleRegistry.effectiveInstances(layer:)` 的 opName 扫描，presence 不看 enabled；WorkspaceModel 持有 editorState/history/layerStack 读面——若跨层不可读则落 `PipeCoordinator`，SUMMARY 实报落点）。
2. `App/.../State/EditorState.swift`：`recordFilmChange` 保留（legacy 档编辑面）；**基链 typed reject**：`recordChange(_:label:)` 首行加 `opName == spektraFilm → 拒收并 toast`（D-SM-8；防直调误落基链）；层写入面零改（`addModuleToLayer` 的 ownership 校验已覆盖 `.grade`）。
3. `HistoryStack.swift` / `LightamerSidecar.swift`：**零改**（v1 T3-3/T3-4 保留；J5 成立）。
4. `PipeCoordinator.syncFilmCarrierWithHistory()`：改 D-SM-10 门控形（在场 → 清 carrier；否则 = effectiveFilmRecord）；`versionActionDidChange()` 同款接入（M1 姊妹缺口）。
5. 登记：`Project.swift` + BUNDLE-MAP（WorkspaceLegacyTests 行）+ `tuist generate`。

AC（机检）：
- AC-T3'-1：`schemaVersionCurrent == 13`；`LightamerSidecar.swift` diff 为空。
- AC-T3'-2：含 `filmRecord` 的 v13 fixture 解码后 `hasLegacyFilmRecord == true` 且 `effectiveFilmRecord()` 值逐位 == fixture。
- AC-T3'-3：层内 spektraFilm 实例在场时谓词 true（正测）；基链放同名仿造实例时谓词仍读全域但转换门以**层内**为准——基链 spektraFilm 经 typed reject 不可达（负测：`recordChange` 拒收 + history 无该 item）；enabled=false 的层内实例谓词仍 true（presence 语义，M1）。
- AC-T3'-4：`HistoryStack.swift` diff 为空（T3'/T4'/T6' 全批维持；终表复核）+ sync 腿门控：实例在场 → undo/redo/jump 后 carrier 缺席；实例缺席 → carrier = effectiveFilmRecord（M1）。
- AC-T3'-5：迁移 commit 后旧 `filmRecord` history item 仍解码（undo 可回到 legacy 观感——回退语义不断链）。

ΔN = 10（FilmHistoryTests +2、FilmSidecarTests +3 新档负测、WorkspaceLegacyTests 新文件 5 谓词/基链拒绝/sync 门控）。
封存面：无。
## T4' 双轨读判别门 + 迁移行 + 备份 + env 门接线

目标：旧档走 legacy 回放腿逐位恒等；新档走 module 链；面板出「Convert to Film module」迁移行；convert 前 pre-convert 备份。

编辑点：
1. `App/.../State/PipeCoordinator.swift`：
   - `filmTailPolicy(for:)` 加双轨判别：`hasLegacyFilmRecord && !hasSpektraFilmInstance` 才供给 `FilmTailParams`（谓词 = T3' 单源）；已迁移/新档恒 nil（thumbnail 恒 nil 门保留）。签名零改，内部首行加判别 hunk。
   - `filmLegRequestTags(for:)` 同判别门（paperGrade/cameraFilter tags 仅 legacy 腿消费；module 腿由 record 内字段直达）。
2. `LightamerCore/Sources/Pipe/PixelPipe.swift`：`runTerminalTails` film 分支**零逻辑改**（legacy 腿原样保留作回放臂）；仅注释标注"legacy 回放臂（spektra-module 双轨期）"。`run()`:926 与 `runSub()` 调用点零改。
3. `App/.../EditorState+FilmMigration.swift`：`FilmMigrationAction` 新增 `.convertToModule` case；`evaluate` 加 `hasLegacyFilm: Bool = false` 默认参（M8-3/M9-4 调用形零改）+ film 源改「hasLegacyFilm ∨ spektraFilm 在场」（M6：`evaluate` 签名加 `hasSpektraFilmInstance: Bool = false` 默认参，两面板调用点传单源谓词值）；判别表：`hasLegacyFilm && !editingInFlight → .convertToModule`（优先级高于 process migrate）；`migratable` 扩认 `.convertToModule`。**第三标记形**：模块档 process 迁移标记 = spektraFilm params verbatim 经 `recordLayerChange`（禁走 film-item 标记形，M6）。
4. 迁移行渲染：`ProcessMigrationInputs` 加文案字段（title/body/button/confirm，m9）+ convert 键族 `panel_film_convert_{title,body,button,confirm}`（≤4，cancel 复用中性键，D-SM-6/D-SM-7；body 含多层漂移说明段）；AX id 前缀 `film.convert.*`（独立于 `film.migrate.*`）。
5. 确认动作 `PipeCoordinator.runFilmModuleConversion`：**pre-convert 备份**（M10：M2-8 `pre-migrate.N-M.bak` 轮换先例，sidecar 快照）→ 合成 `ModuleInstance(spektraFilm, Params(record: legacyRecord))` 经 `addPlacement()` 形态落地（最上层 adjustment 层，无则 `addAdjustmentLayer()`；B1）+ `addModuleToLayer` + `recordLayerChange` 参数 commit（含 `history_film_enable` 语义 label）+ 清空 `filmRecords[url]` + `scheduleSidecarWrite`（写出无 `filmRecord` 键）。**undo 步数声明**（m7）：有层 = 2 item（结构 + 参数），无层 = 3 item（+ 建层）。
6. env 门接线：`LIGHTAMER_FILM_MODULE` 缺席时迁移行隐藏（`migratable` 门读 `isFilmModuleRequested` 单源）、面板 enable 隐藏、add 菜单行隐藏——默认面用户零可见变化（注册恒开但不可达，M5(a)）。
7. 登记：`Project.swift` + BUNDLE-MAP（FilmMigrationTests 行更新）+ `tuist generate`。

AC（机检）：
- AC-T4'-1：legacy fixture（filmRecord 在场、无实例）：门开/关均走旧腿，输出 hash == 基线 golden（**逐位恒等保留**，双 env 测——D-SM-9 的 legacy 面）。
- AC-T4'-2：已迁移档：`filmTailPolicy(for: .full) == nil`；渲染链含 46.7 box；实例落点 = grade 层内（B1 落点断言）；基链无 spektraFilm（负测）。
- AC-T4'-3：`evaluate(hasLegacyFilm: true)` → `.convertToModule`；`editingInFlight` 优先；既有 M8-3/M9-4 真值表逐位不变（回归）；`migratable` 对 `.convertToModule` = true。
- AC-T4'-4：v1 legacy 档（stored process < current，无 colorWheels 编辑）→ convert 后 process 迁移行可见（M6 门修）；确认后标记 = `recordLayerChange` params-verbatim item（history 无 filmRecord item 写回——负测）；v3 臂生效（`documentProcessVersion == .current`）。
- AC-T4'-5：转换动作后：实例在场 + carrier 缺席 + sidecar 无 `filmRecord` 键 + **按步数 undo 回到 legacy 观感**（有层 2 步/无层 3 步，m7）+ undo→redo 后 carrier 仍缺席（M1 导航不变量）+ 关 module 后 legacy 不复活（presence 语义：谓词仍 true → 尾段不供给）；跨转换点版本切换两侧观感各自正确（M1）。
- AC-T4'-6：env 缺席时迁移行 `migratable == false`（默认面零可见）+ env-off 迁移档：spektraFilm 走 `degradedForUnknownOps`（enabled=false + toast，M10）→ 画面退回无胶片；数据保留（params 字节不动）；legacy 不复活（谓词 presence 仍 true）；重开 env 后实例**仍 disabled**（显式语义：degrade pass 改写 enabled 位已持久化，需手动开——M10 不可逆面申报，DECISIONS 登记）。

ΔN = 13（FilmMigrationTests +5、PipeCoordinatorLegacyTests +4、Registry env 门 +2 并入 T1' 文件、备份/回退 +2）。
封存面：PixelPipe（仅注释 hunk——`runTerminalTails` 标注；若实现零改则终表记"注释例外"）。
## T5' 求解链不动验证 + tile 政策钉死

目标：FilmSolveCache 键控原样；`pixelUm` 全帧锚；tile 永不可达机检钉死；legacy `runFilmLeg` 统计原样保留（M3）。

编辑点（预期极小，多为测试）：
1. `LightamerCore/Sources/Pipe/Film/FilmTailPolicy.swift`：`FilmSolveCache` 键（materialPairHash ⊕ statsHash ⊕ modeTag）零改；`FilmStatsSeam.histogram` **module 侧新增调用点**（T2' process 内已实现），legacy `runFilmLeg`（`PixelPipe.swift:1241-1243`）**原样保留至 deprecation 窗**（M3 修法——v1"移到"作废）。**统计对象变更声明**：module 侧输入平面从"主链顶面"变为"本层 46.7 输入"——单层置顶档 ε 带等价（T7' 桥接测试主门），多层档漂移由迁移提示承担（R3）。
2. `SpectralPayloads.swift`：`pixelUm(frameWidth:)` 零改；`tileHalo` 不覆盖（T2' 已定）⇒ plane 恒层子 run 全平面 ⇒ 锚正确（R1 缓解成立）。
3. tile 政策文档：`SpektraFilmModule` doc comment 钉死"per-ROI 红线结构面延续（M3-3）+ P2 挂账"。
4. 登记：`Project.swift` + BUNDLE-MAP（SpektraTilePolicyTests 行）+ `tuist generate`。

AC（机检）：
- AC-T5'-1：`FilmDeterminismTests` 精确值逐位不变（fold 序/字节序/statsHash 全量回归）。
- AC-T5'-2：`PixelPipe.swift` `runFilmLeg` 函数体 diff 为空（M3 改写；m2 提取法同 AC-T2'-3）+ `SpectralPayloads.swift` 求解段 diff 为空（注释除外）。
- AC-T5'-3：tile 框架面断言：`SpektraFilmModule` 实例在 tile eligible 扫描中恒 excluded（flag 缺席 + halo 0 双条件）。
- AC-T5'-4：`pixelUm` 全帧锚断言：process 收到的 plane 宽 == 层子 run 全平面宽（非 tile 切片——以不 tile 不变式为前提的契约测试）。

ΔN = 4（FilmDeterminismTests 0 新增全回归、SpektraTilePolicyTests 新文件 4）。
封存面：无。

## T6' 下游面（DRT 交接/导出/渲染入口清单/面板换锚/Film 卡/MCP 拒绝）

目标：film 退出终端共享序后的剩余面逐项收敛；渲染入口清单逐面裁定；面板换锚；Film 卡退役；MCP 显式拒绝。

编辑点：
1. **DRT 交接**：`runTerminalTails` ② DRT tail 的 upstream 值——legacy 档仍 film 输出 hash（零改）；新档 film 缺席 ⇒ upstream 回主链顶面 hash（`run()` 调用点既有语义：`topEnabledPosition` 顶面，含 46.7 输出——**代码零改**，行为自然收敛，J2）。`DrtTailAssembly.seed` 签名零改。`isTerminalTailSkipped` film 分支保留（legacy 腿仍需降出/重放）。
2. **导出**：`ExportQueue.enqueue(filmTails:)` + `$jobFilmTail` 保留（D-SM-4 legacy 通道）；`ExportRenderer` 装配：legacy 档传 tails、新档传 nil（含 46.7 实例自然进导出链）。`ExportQueueContract` 零 diff。`ExportFilmChainTests` 加参数化形态（legacy vs module 双臂断言）。
3. **渲染入口清单**（M7 逐面裁定 + AC）：
   - export：**include**（46.7 实例自然进导出链）；
   - thumbnail/grid：**strip**——落 `SessionThumbnailProvider` 物化层（显式 disable opName==spektraFilm）；`SessionThumbnailRenderer.swift`（Phase 8 contract 禁改）**零触**；KD-4 门（`filmTailPolicy(for: .thumbnail) == nil`）保留；
   - QuickLook：**include**（正确观感；DECISIONS 申报"legacy 档 QuickLook 恒无胶片 → 迁移档有胶片"的观感变化）；
   - ColorMatch 追色参考统计：**strip**（与 legacy `filmTail: nil` 同语义——`ColorMatchService.swift:217,223` 加同形排除）；
   - followEdges surface / mask overlay 探针面（`PipeCoordinator.swift:2360,2854,2940`）：**strip**（与 thumbnail 同理——统计/探针面不染胶片；DECISIONS 申报）。
4. **Film 面板换锚 + 单实例守卫**：`FilmPanelModel` 数据源换锚——三级读改为 live 实例 params → history 投影 → carrier（carrier 仅 legacy 档）；`commitFilm` 面板调用点切 `recordLayerChange`（新档，B1）；Solve 按钮 `invalidateAll()` 保留；enable 入口改为 `addPlacement()` 形态（已有则定位，D-SM-11）；add 菜单行已有则隐藏（`gradeScopeEntries` 过滤）；宽容度面板/descriptor 数据源换锚（m6：`currentFilmRecord` carrier-only → live 实例 record；`FilmStatsSnapshot.last` 语义注记 = 模块档为层 46.7 输入统计）。
5. **节点 Film 卡退役**（OQ-5(a)）：`NodeCanvasGeometry.filmCardID` + `includesFilmCard` + 卡渲染全撤；`FilmCardTests` 退役（**−4** 法，M9；文件删 + Project/BUNDLE-MAP 同批退役登记）；`editor_node_film*` 3 键：xcstrings 保留（删键 = 翻译记忆丢失惯例——zh-audit allowlist 备注退役，scanner MISSING 豁免）；Film 页入口（`LightamerShell.swift:2255` filmPanel 动作）**保留**（m5）。
6. **MCP**：`apply_params` 对 spektraFilm = **typed reject**（B1 P1 判定：`projectInstances` 首行 op 特例，返 invalidParams 带"层专属 op，P1 不开放 MCP 写"理由；扩层参数 = MCP schema 破坏性变更，P2 立项）；`requiresControl`/turn-taking 全 op 通用零改；`IopCatalog` **不加行**（m4 裁定：handwritten 表是 REFERENCE 非 whitelist）；`mcp_tool_desc_apply_params` 零改。
7. **Copy Adjustments**：`isAdjustmentTransferable` 对 spektraFilm = 可迁移但单实例合并（D-SM-11；谓词单源内 op 特例）；paste→legacy 档 = 拒绝（提示走迁移确认）。
8. 登记：`Project.swift` + BUNDLE-MAP（ThumbnailStripTests/McpFilmTests 行）+ `tuist generate`。

AC（机检）：
- AC-T6'-1：新档 `.drt` 渲染：DRT tail upstream == 含 46.7 的主链顶面 hash（seed 值断言）；legacy 档 upstream == film 输出 hash（既有行为回归）。
- AC-T6'-2：导出双臂：legacy 档导出含 film 腿（hash == 基线）；新档导出含 46.7 实例输出且 `filmTails` 传 nil。
- AC-T6'-3：thumbnail run 实例集不含 spektraFilm（物化层剥除断言）；`filmTailPolicy(for: .thumbnail) == nil` 回归；`SessionThumbnailRenderer.swift` diff 为空（禁改面机检）。
- AC-T6'-4：QuickLook include（迁移档预览含胶片输出断言）/ ColorMatch strip（统计 == 无胶片基线）/ 探针面 strip（surface 实例集不含 spektraFilm）——三面各一条。
- AC-T6'-5：面板换锚：新档面板读 == live 实例 record；legacy 档面板读 == carrier；Solve 两种档均可达；宽容度/descriptor 新档读 live 实例（m6）；add 菜单已有隐藏 + 面板 enable 已有定位 + paste 单实例合并 + paste→legacy 拒绝（D-SM-11 各一条）。
- AC-T6'-6：`apply_params(opName: "spektraFilm")` → invalidParams（含层专属理由串断言）；`IopCatalog.swift` diff 为空；`mcp_tool_desc_apply_params` 零改（m4）。
- AC-T6'-7：grep 机检 `filmCardID/includesFilmCard/FilmCardProjection/.filmCard/filmCardView/filmCardMarker/editor.nodes.film` 全仓零命中（除 DECISIONS 注记，m5 扩集）；`NodeGraphCommand`/`PipelineDocument` diff 为空。

ΔN = 16（ExportFilmChainTests +3、ThumbnailStripTests +2、FilmPanelTests 换锚 +4、McpFilmTests 新文件 2、渲染入口三面 +3、D-SM-11 paste/菜单 +2）。
封存面：PixelPipe（预期零逻辑改——终表记"行为自然收敛无 hunk"或注释 hunk）。
## T7' ε 带桥接测试 + 蒙版 AC + golden 迁移 + BUNDLE-MAP

目标：两宿主 ε 带等价桥接测试（P1 验收主门，B2 口径）；蒙版收益验收（M10）；双臂 golden kernel 字节零改；测试域归置同批。

编辑点：
1. 新 `Tests/LightamerTests/SpektraBridgeParityTests.swift`（**落域 IOPP**：文件名命中 `*Parity*` 路由模式，M9）：同一合成小平面 + 同一 record，legacy 回放腿（`runFilmLeg` 经 filmTail 装配）vs module 链（`SpektraFilmModule.process` 经层子 run 单层置顶）输出 ε 带比对——覆盖密度臂/光谱臂/identity 三形态。**限制声明**：桥接等价仅在"单层、胶片置顶、无层蒙版、层内 46.7 前 ops 为空"成立（统计对象同一性前提）；多层形态测"迁移行可达 + 漂移提示渲染"不测等价。夹具 = 合成小平面三形态 + **1 张降采样 CC0**（MEMFAIL 规避，M9；全量 CC0 实拍腿不立项）。
2. `ACEScc 往返精度门`：log→linear→log 往返**相对误差**口径（B2 改写）：中段 ≤5e-4、高光 ≤2e-3、暗部绝对 ≤2e-5（D-SM-9 三段带；执行实测收窄只许紧不许松）；超带 = T2' 形态回炉 + re-plan。
3. 蒙版 AC（M10）：层 opacity 0.5 / 径向蒙版下 module 输出 == 层混合公式期望（合成平面，ε 带内）；走查项见 T8'。
4. 既有 Film/Spectral 测试域归置：47 个 film/spectral 测试文件**零改名**；`FilmLegTests`/`FilmCoordinatorTests`/`ExportFilmChainTests` 加双形态参数化（T3'/T4'/T6' 已计）；`FilmCardTests` 退役（T6'-5，−4）；新文件（RegistryFilmModuleTests、SpektraFilmTests、WorkspaceLegacyTests、SpektraTilePolicyTests、McpFilmTests、SpektraBridgeParityTests、ThumbnailStripTests）按域模式归入唯一 target + `Project.swift` 显式登记 + BUNDLE-MAP 同批更新行（各 T 已分散登记，本 T 复核行内 method 数终态）。
5. `SpectralDualArmGoldenTests` / `SpectralCrossArmGoldenTests` / `FilmGoldenTests` / `BWSpectralGoldenTests`：golden 字节零改（kernel/装配零改的自然结果；在执行 HEAD 重钉 md5，m1）；宿主路径变更由桥接测试覆盖，不改 golden 本身。
6. 跑法：`Scripts/test-direct.sh --bundle <域>`（M9）；IOPP 贴线 bundle（5788MB）MEMFAIL 风险：桥接测试夹具小平面 + 降采样 CC0 单张，若定向轮 MEMFAIL 则夹具再降采样（不扩豁免）。

AC（机检）：
- AC-T7'-1：桥接三形态 ε 带等价（density/spectral/identity 各 ≥1 合成 fixture + 1 降采样 CC0；D-SM-9 三段带；比较空间 L048：decode 回 linear、f32 常数 `Double(Float(x))` 升维）。
- AC-T7'-2：ACEScc 往返相对误差三段带（超带 = T2' 回炉，门失败）。
- AC-T7'-3：全部 golden 文件 md5 == 执行 HEAD 基线（`git diff --stat Tests/` 仅新文件 + 参数化测试源，无 `.bin/.png` golden 变更）。
- AC-T7'-4：BUNDLE-MAP 行内 method 数对账 == 各文件终态；`tuist generate` 后全 bundle 可列（无孤儿登记）。
- AC-T7'-5：D-SM-1 负测：同 params + 不同上游统计 ⇒ 平面 key 不同（无陈旧命中）；证伪则回落 RESEARCH §4.4 缝 + re-plan。
- AC-T7'-6：蒙版两形态 == 层混合公式期望（opacity 0.5 / 径向蒙版，合成平面，ε 带内）。

ΔN = 16（SpektraBridgeParityTests 10：三形态 ×3 + CC0 1、ACEScc 往返 2、D-SM-1 负测 2、蒙版 2）。
封存面：无。
## T8' 收口（贴线定向轮 + 全套 + 走查 + SUMMARY/DECISIONS + 申报终表）

1. 贴线定向轮（M8/M9 前置）：全套前先跑 `Scripts/test-direct.sh --bundle IOP` 与 `--bundle IOPP` 定向轮（machine-guard G1-G4 + 运行时 monitor 伴跑；MEMFAIL/压力转红即停查夹具/顺序漂移，不扩豁免）。
2. 全套回归：`Scripts/test-direct.sh --all`（orchestrator 批准制；monitor 伴跑；预期基线 = **M9-2 收口值 + 本批 ΔN=76 − FilmCardTests 退役 4**（M9 写死公式））。
3. GUI 走查：env 门开档——迁移行渲染/确认 sheet（含漂移说明）/pre-convert 备份存在/转换后面板换锚/单实例 add-face（已有则隐藏/定位）/蒙版项（单层只放 spektraFilm + 径向蒙版观感，M10）/缩略图 grid **可度量**（单张渲染耗时对照 legacy ±10% 内 + planesRendered 计数对照，M7 改写）；关档——默认面零可见变化。证据落 `.work/gui-acceptance/spektra-module/` + MANIFEST。
4. zh 对账：`zh-audit --check` 全绿；convert 键族 ≤4 申报（AC-T8'-2）；`editor_node_film*` 退役 allowlist 备注；xcstrings 尾块纯插入（m8）。
5. 产物：`SUMMARY.md` + `DECISIONS.md`（chunked 写；DECISIONS 含 RESEARCH §4.2「或 nil = 基链」勘误 + 成对写锚解除 + QuickLook 观感变化 + 回退不可逆面四登记）+ 封存面申报终表（§封存复核）。
6. 机器纪律：machine-guard 单重活；DerivedData 收口清自建容器；commit-per-task 由执行 lane 自持（T 序可串行：T1'→T2'→T3'→T4'→T5'→T6'→T7'→T8'，每 T 独立 commit）。

AC（机检）：
- AC-T8'-1：全套 0 fail；MEMFAIL 0；`RenderProcessVersion.current == 3`（m8：process 不 bump 机检）；UserDefaults 零新键（grep 键登记面无新增，m8）；`FilmPlacementModule`/`FilmPlacementKernels.metal`/GradeCatalog 第 19 行 diff 为空（m8：20.8 零改）。
- AC-T8'-2：zh-audit 全绿；convert 键族 ≤4（`panel_film_convert_{title,body,button,confirm}` 在册）；grep 退役面（m5 扩集）零命中；封存 diff == 申报终表。
ΔN = 0。封存面：终表复核。
## 封存面申报表（v2 执行前申报；T8' 终表复核）

| 封存件 | 申报形态 | 任务 | 对 RESEARCH §6.1 的修订 |
|---|---|---|---|
| PixelPipe | `runTerminalTails` 注释 hunk（legacy 回放臂标注）；逻辑零改（M2 包装缝 + M3 保留双统计双前提成立——修后终表复核） | T4' | 收窄：4.4 折叠缝取消（D-SM-1）；调用点 upstream 自然收敛零 hunk |
| V50Order | add-only 一行 `("spektraFilm", 46.7)`，dt-verbatim 补录 | T1' | 同 RESEARCH |
| GradeCatalog（NodeOwnershipCatalog） | 第 21 行 + E7 期望（唯一 op 19→20、行 20→21）；`needsEnvelope` 零改（skipsEnvelope 优化不做） | T1' | 收窄：谓词例外取消（D-SM-5）；计数口径修正（M5） |
| ExportQueueContract | **零 diff**（filmTails 保留为 legacy 通道） | T6' | 修订：删参数推迟到 deprecation（D-SM-4） |
| sidecar schema | **零 diff**（v13 不动、零新键） | T3' | 修订：v14 bump 取消（OQ-4(b)） |
| HistoryStack / HistoryHash | 零 diff（保留只读、新写停产） | T3' | 同 RESEARCH（否） |
| DrtRecord / TerminalTailPolicy / DrtTailAssembly / DrtEotf / Lut3dKernels.metal / 六格式导出矩阵 / NodeGraphCommand / PipelineDocument | 零 diff | T6' | 同 RESEARCH（否） |
| UserDefaults 键族 | 零新键（m8 补行） | 全批 | 登记制：grep 键登记面无新增 |
| filmPlacement 20.8 | 零改（m8 补行） | 全批 | `FilmPlacementModule`/kernels/第 19 行 diff 为空 |
| 既定禁改面（非 17 件） | `SessionThumbnailRenderer.swift` 零触（M7：strip 落物化层） | T6' | Phase 8 contract |

**结论**：v1「2 行 + 1 期望」在 M2/M3 非封存修法前提下**仍成立**（PixelPipe 条件成立——终表复核两前提）。D-SM-1 若证伪则 PixelPipe +1 逻辑 hunk（re-plan 触发器）。

## 风险→任务映射（v2）

| RESEARCH 风险 | 承载任务 | 门 |
|---|---|---|
| R1 pixelUm 锚 | T2'（不覆盖 tileHalo）+ T5' | AC-T2'-2/AC-T5'-3/AC-T5'-4 |
| R2 corr 网格/scratch | T5'（不 tile ⇒ 零变化）+ T2'（中间面借 slot） | AC-T5'-2/AC-T2'-6 |
| R3 多层档统计漂移 | T4'（最上层默认落点 + 漂移提示 + 备份）+ T7'（限制声明） | AC-T4'-5/AC-T6'-5/AC-T7'-1 |
| R4 100MP 内存峰 | T2'（.oneInstance + 中间面复用 D-SM-12）+ T8'（贴线定向轮） | AC-T2'-1/AC-T2'-6/AC-T8'-1 |
| R5 层内重复求解 | T5'（SolveCache 命中） | AC-T5'-1 |
| R6 ACEScc 往返 | T2'（kernel 复用）+ T7'（ε 带精度门） | AC-T7'-2 |
| D-M3-2-1 翻转三问 | §4.0 已答；T6'-5/T3'（单一 record/默认无蒙版） | AC-T6'-7/AC-T3'-3 |

## 执行纪律（执行 lane 自持，抄送任务书）

- commit-per-task（T1'..T8' 可串行，每 T 独立 commit）；产物交接 BUILD-HANDOFF.txt；machine-guard 单重活；zh-audit 每批对账。
- 双臂 golden kernel 字节零改红线（md5 机检 AC-T2'-3/AC-T7'-3，执行 HEAD 重钉）。
- `tuist generate` 恒为登记批最后一个动作（L041）；BUNDLE-MAP 同批（每 T 自登记，T7' 复核终态）。
- env 门纪律：默认面零可见变化直到走查 + 桥接全绿；注册恒开（M5(a)），env 只门 UI/迁移/写入口。
- 既有测试改写申报（T8' 对账列实报）：GradeCatalogTests 2 法期望、CatalogAddFaceTests 1 法（若进 add 菜单）、FilmMigrationTests 真值表扩、ExportFilmChainTests / FilmLegTests / FilmCoordinatorTests 双形态参数化。
