# 光谱核 module 化 P1 执行计划（spektra-module PLAN，2026-11-03）

> 基线 HEAD（亲核）：`e63ebb3f docs(m92): ledger the v0.3.3 bw pack decode repair and its full-suite close`
> M9-2 B&W 修复批在 HEAD 之内（`339adb33` + `e63ebb3f`）；`git status` 仅 `.work/` 未跟踪日志/提示词，Film/ 零未提交 diff——无异常。
> 执行正本 = 同目录 `RESEARCH.md`（§4 设计案 + §5 迁移 + §6 风险）。用户裁决六条 OQ 全采推荐（见 §0），不再呈裁。
> 范围 = **P1 only**：module 化不改核，视觉逐位恒等，process 不 bump，sidecar 零新键零 bump；P2 挂账不立项。

## §0 裁决冻结（预批准原文转录）

- OQ-1(a)：`.oneInstance` 单实例（需求出现再撤）。
- OQ-2(a)：保留直方图自适应求解；P2 挂账不立项。
- OQ-3(a)：spektraFilm 入 GradeCatalog + op 内 ACEScc 往返（RESEARCH §4.1(a) 形态）。
- OQ-4(b)：sidecar 版本号不 bump、键面零新键；旧档内容判定（`filmRecord` 键在场 && 无 spektraFilm 实例 = legacy 腿）。
- OQ-5(a)：节点图 Film 卡 P1 退役。
- OQ-6(a)：串行——以派遣时 HEAD 为基线（含 M9-2 全部交付）。

## §0.1 本 PLAN 的新增判定（执行层定案，orchestrator 备案）

| # | 判定 | 内容 |
|---|---|---|
| D-SM-1 | **prepareChain 无需新折叠缝** | RESEARCH §4.4 担忧"同参数不同上游统计命中陈旧平面"不成立：stats = 纯函数(本层 46.7 输入平面)，而输入平面内容已被 levelHash 链（decode ⊕ ≤i enabled hashes + 几何）完全键控——同 params + 同上游 key ⇒ 同输入内容 ⇒ 同求解。不新增 `runtimeFoldHash` 缝；AC 由 T7 负测钉死。若负测证伪，回落 4.4 缝（PixelPipe 例外 +1 hunk，需 re-plan 申报）。 |
| D-SM-2 | **执行核 delegate 形态** | `SpektraFilmModule.process` 不复制装配逻辑：直方图 → `FilmRuntimeSolve` → 构造 `FilmMethodBox`（Params 映射）→ 转发 `box.process` → ACEScc 往返。密度臂/光谱臂工厂函数体零 diff（md5 钉死），v1 冻结维持。 |
| D-SM-3 | **history 键族：保留只读 + 新写停产** | `HistoryItem.filmRecord` / `filmDocumentScope` / `commitFilm` 保留解码与 legacy 档回放；新写入（含迁移 commit）一律标准 `recordChange` + snapshot。迁移 commit label 复用 `history_film_enable` 族语义，零新键。 |
| D-SM-4 | **导出 filmTail 载体：保留为 legacy 通道** | `enqueue(filmTails:)` 参数与 `$jobFilmTail` TaskLocal 双轨期保留（legacy 档仍走旧腿进导出）；新档传 nil。`ExportQueueContract` 因此**零 diff**（修订 RESEARCH §6.1 的"删参数"申报；退役推迟到 deprecation 窗）。 |
| D-SM-5 | **ACEScc 往返走 kernel 复用** | process 内 `dispatch2DTexture(grade_acescc_out)`（log→linear）→ 胶片链 → `dispatch2DTexture(grade_acescc_in)`（linear→log），复用 `ACESccConvert.metal` 现有 PSO，零新 kernel。`needsEnvelope` 的 skipsEnvelope 优化 P1 不做（封存面代价 > 两次 1D 变换成本）。 |
| D-SM-6 | **迁移行 = 新 action case + 复用 row 组件** | `FilmMigrationAction` 新增 `.convertToModule` case（三源 gate 加 `hasLegacyFilm` 默认参，M8-3/M9-4 调用形零改）；渲染复用 `ProcessMigrationRow` 参数化形态；确认动作 = 合成实例 + 清空 carrier + 标准 commit。 |
| D-SM-7 | **多层档漂移提示 ≤2 新 zh 键** | 统计对象变更（顶面→本层 46.7 输入）如实告知：迁移确认 sheet 内一行说明。优先复用 `panel_process_migrate_*` 中性族后缀；不够则新键 ≤2，需 T8 对账申报。 |

## §0.2 任务总览

| T | 标题 | Δ文件 | ΔN（新测试法） | 封存面 |
|---|---|---|---|---|
| T1 | 注册骨架：V50Order + GradeCatalog + Registry env 门 | +2∕~4 | 6 | V50Order、GradeCatalog |
| T2 | SpektraFilmModule 本体 + ACEScc 往返臂 | +2∕~3 | 8 | —（delegate 形态） |
| T3 | 参数载体迁移：carrier→instance，sidecar 键 legacy 只读 | ~5 | 7 | —（schema 零触碰） |
| T4 | 双轨读判别门 + 迁移行 + env 门接线 | ~6 | 9 | PixelPipe（legacy 门 hunk） |
| T5 | 求解链不动验证 + tile 政策钉死 | ~1 | 4 | — |
| T6 | 下游面：DRT 交接/导出/缩略图/面板/Film 卡/MCP | ~10 | 10 | PixelPipe（upstream 语义） |
| T7 | 桥接测试 + golden 迁移 + BUNDLE-MAP | +2∕~6 | 12 | — |
| T8 | 收口：全套 + 走查 + SUMMARY/DECISIONS + 申报终表 | docs | 0 | 终表复核 |
| 合计 | | +4 新源 / ~30 触碰 | **56** | PixelPipe/V50Order/GradeCatalog 三件 |


## T1 注册骨架（V50Order + GradeCatalog + Registry env 门）

目标：46.7 槽位与目录行就位，默认 off（env 门后）。

编辑点：
1. `LightamerCore/Sources/Foundation/V50Order.swift`：`("filmicrgb", 46.0)` 后插入 `("spektraFilm", 46.7)` verbatim 行（dt `iop_order.c` v50 同值；形参注释引 RESEARCH §4.1）。add-only，一行。
2. `LightamerIOP/Sources/NodeOwnershipCatalog.swift`：GradeCatalog 新增第 21 行 `spektraFilm`（owner .grade；`identityJSON = json(of: SpektraFilmModule.Params())`；`panelExposures` = Film 面板键族现行清单，复用 `film_*` 15 键 stem——零新键）。E7 完备性断言随之更新（checker 期望 20→21）。
3. `LightamerIOP/Sources/Registry.swift`：`populate` 内 `spektraFilm` 注册行 + 条件门——KD-3 同款读法 `ProcessInfo.environment["LIGHTAMER_FILM_MODULE"] == "1"`（默认 off）；`defaultFaceDisabledOpNames` **不加** spektraFilm（它不属 D1/D2 禁用集——门是独立 env，非默认面裁剪）。`editingDefaultInstances` 不 seed（新档默认无胶片 = 今日 pristine 语义）。
4. `LightamerIOP/.../IopCatalog.swift`（若有 opName 白名单枚举消费点）：MCP/IOP 目录面如显式 switch 穷举，加 spektraFilm 分支（若走 Registry 动态查询则零改）。

AC（机检）：
- AC-T1-1：`V50Order.order(of: "spektraFilm") == 46.7`，且排序位恰在 filmicrgb 与 lut3d 列表序之间。
- AC-T1-2：env 缺席时 `ModuleRegistry.makeBox("spektraFilm") == nil`；`LIGHTAMER_FILM_MODULE=1` 时非 nil（注入式 env 读点可测，不得在 body 求值）。
- AC-T1-3：`GradeCatalog.item(opName: "spektraFilm")?.owner == .grade`；E7 checker 全绿。
- AC-T1-4：默认面测试进程（env 缺席）既有 `DefaultFaceTests` 计数契约逐位不变（full−6 不动——spektraFilm 不入默认面集合）。

ΔN = 6（V50OrderTests +1、RegistryFilmModuleTests 新文件 4、GradeCatalogTests E7 +1）。
封存面：V50Order（add-only dt-verbatim 行）、GradeCatalog（第 21 行 + E7 期望）。

## T2 SpektraFilmModule 本体 + ACEScc 往返臂

目标：可注册 module，process = ACEScc 往返 + delegate 现有 film 腿装配；flags `.supportsBlending | .oneInstance`，不设 `.allowTiling`。

编辑点：
1. 新 `LightamerIOP/Sources/SpektraFilm/SpektraFilmModule.swift`：
   - `opName = "spektraFilm"`，`iopOrder = 46.7`，`flags = [.supportsBlending, .oneInstance]`，`defaultColorspace = .RGB`。
   - `Params = { record: FilmRecord }` 原样嵌入（`ParamsCoding` 经 `FilmRecord` Codable；stableHash 字段复用 record 面）。
   - `modifyROIOut/In` 恒等直通；**不覆盖 `tileHalo`**（协议默认 0 = 永不 tile，R1 缓解的唯一实现点）。
   - `process`：输入（ACEScc log）→ `dispatch2DTexture(grade_acescc_out)` → 中间 linear 平面 → 直方图（`FilmStatsSeam.histogram` 同缝，材料已解析才跑）→ `FilmRuntimeSolve.solve/solveSpectral`（键零改）→ 构造 `FilmMethodBox`（Params = record + 求解值映射）→ `box.process` 转发 → 输出 → `dispatch2DTexture(grade_acescc_in)` → 回 ACEScc。（D-SM-2/D-SM-5）
   - `blitIdentity` 路径：材料未解析/求解失败 = 恒等直通 + 与旧腿同签名 toast（RESEARCH D14）。
2. 新 `LightamerIOP/Sources/SpektraFilm/SpektraFilmParams.swift`（若 Params 需 ParamsCoding 适配层；否则并入主文件，Δ文件 −1）。
3. `LightamerCore/Sources/Pipe/Film/`：`FilmMethodBox` 加可测构造缝（注入 Params + payloads），供 module 与桥接测试双宿主；`runPayloads` 实例字段形态零改。
4. `Project.swift`：SpektraFilm 源 + 测试登记；`tuist generate` 为该批最后一个动作（L041）。

AC（机检）：
- AC-T2-1：`SpektraFilmModule.flags == [.supportsBlending, .oneInstance]`；`.allowTiling` 缺席。
- AC-T2-2：`tileHalo` 默认 0（反射/协议默认断言）；`modifyROIIn == identity`。
- AC-T2-3：`assembleDensityFilmLeg` / `assembleSpectralFilmLeg` 函数体 md5 == 基线值（v1 冻结红线机检）。
- AC-T2-4：process 空输入恒等面：材料未解析档 `process` 输出逐位 == 输入（blitIdentity）。
- AC-T2-5：identityJSON 往返：`Params()` 编码解码逐字节 == `GradeCatalog` 登记 `identityJSON`。

ΔN = 8（SpektraFilmTests 新文件 8，落域 IOP/Core 级，BUNDLE-MAP T1 批同登记）。
封存面：无（IOP 新文件 + Core Film/ 加法缝；FilmMethodBox 改动为 additive init，不在封存清单）。

## T3 参数载体迁移（carrier→instance，sidecar 键 legacy 只读）

目标：新写入走 `ModuleInstance.paramsData`；document carrier 与 sidecar `filmRecord` 键转 legacy 只读；history 键族保留解码停产新写（D-SM-3）。

编辑点：
1. `App/.../UI/Shell/WorkspaceModel.swift`：`filmRecords` 载体标注 legacy（doc comment + deprecation 注记）；新增只读判别 `hasLegacyFilmRecord(for:)` 与实例判别 `hasSpektraFilmInstance`（后者读 `effectiveInstances()` opName 扫描）——OQ-4(b) 内容判定双条件单源。
2. `App/.../State/EditorState.swift`：`recordFilmChange` 保留（legacy 档编辑面）；新增标准路径装配——迁移/新建胶片一律经 `recordChange(opName: "spektraFilm", params:)`（D-H1 三件套语义适用）。
3. `LightamerCore/Sources/Pipe/History/HistoryStack.swift`：**零改**——`HistoryItem.filmRecord`/`filmDocumentScope`/`commitFilm`/`effectiveFilmRecord()` 保留（legacy 解码+回放只读）；新写停产（无调用者后自然停产，不删符号——sidecar 旧档仍解码）。
4. `LightamerCore/Sources/Sidecar/LightamerSidecar.swift`：**零改**——`filmRecord` 文档键 + per-item 镜像保留解码；`makeSidecarDocument` 对已迁移档不再写该键（写腿条件 = 双轨判别，见 T4 门）；`schemaVersionCurrent = 13` 不动（OQ-4(b)）。
5. `PipeCoordinator.syncFilmCarrierWithHistory()`：保留（legacy 档 undo/redo/jump 同步）；新档载体缺席 = 零动作。

AC（机检）：
- AC-T3-1：`schemaVersionCurrent == 13`（常量断言）；`LightamerSidecar.swift` diff 为空（封存红线机检）。
- AC-T3-2：含 `filmRecord` 的 v13 fixture 解码后 `hasLegacyFilmRecord == true` 且 `effectiveFilmRecord()` 值逐位 == fixture。
- AC-T3-3：新档 `recordChange("spektraFilm")` 后 sidecar 写出**无** `filmRecord` 键，实例 params 内 record 逐位 == 提交值。
- AC-T3-4：`HistoryStack.swift` diff 为空（T3/T4/T6 全批维持；终表复核）。
- AC-T3-5：迁移 commit 后旧 `filmRecord` history item 仍解码（undo 可回到 legacy 观感——回退语义不断链）。

ΔN = 7（FilmHistoryTests +2、FilmSidecarTests +3 新档负测、WorkspaceLegacyTests 新文件 2）。
封存面：无（HistoryStack/HistoryHash/sidecar 全部零 diff——RESEARCH §6.1 修订：schema 例外取消）。

## T4 双轨读判别门 + 迁移行 + env 门接线

目标：旧档走 legacy 回放腿逐位恒等；新档走 module 链；面板出「Convert to Film module」迁移行。

编辑点：
1. `App/.../State/PipeCoordinator.swift`：
   - `filmTailPolicy(for:)` 加双轨判别：`hasLegacyFilmRecord && !hasSpektraFilmInstance` 才供给 `FilmTailParams`；已迁移/新档恒 nil（thumbnail 恒 nil 门保留）。函数签名零改，内部首行加判别 hunk。
   - `filmLegRequestTags(for:)` 同判别门（paperGrade/cameraFilter tags 仅 legacy 腿消费；module 腿由 record 内字段直达）。
2. `LightamerCore/Sources/Pipe/PixelPipe.swift`：`runTerminalTails` film 分支**零逻辑改**（legacy 腿原样保留作回放臂）；仅注释标注"legacy 回放臂（spektra-module 双轨期）"。`run()`:926 与 `runSub()` 调用点零改。
3. `App/.../EditorState+FilmMigration.swift`：`FilmMigrationAction` 新增 `.convertToModule` case；`evaluate` 加 `hasLegacyFilm: Bool = false` 默认参（M8-3/M9-4 调用形零改）；判别表：`hasLegacyFilm && !editingInFlight → .convertToModule`（优先级高于 process migrate——同一文档双迁移时先转 module，process 迁移随后自然触发）。
4. 迁移行渲染：复用 `ProcessMigrationRow` 参数化形态（inputs = convert 文案 + 确认动作）；文案复用 `panel_process_migrate_*` 中性族，多层漂移说明行按 D-SM-7（≤2 新键，T8 对账）。
5. 确认动作 `PipeCoordinator.runFilmModuleConversion`：合成 `ModuleInstance(spektraFilm, Params(record: legacyRecord))` 挂**最上层 grade 层**（无层则新建层——R3 缓解默认落点）+ `recordChange` discrete commit（含 `history_film_enable` 语义 label）+ 清空 `filmRecords[url]` + `scheduleSidecarWrite`（写出无 `filmRecord` 键）。
6. env 门接线：`LIGHTAMER_FILM_MODULE` 缺席时迁移行隐藏、注册缺席（T1 门）——默认面用户零可见变化。

AC（机检）：
- AC-T4-1：legacy fixture（filmRecord 在场、无实例）：门开/关均走旧腿，输出 hash == 基线 golden（逐位恒等，双 env 测）。
- AC-T4-2：已迁移档：`filmTailPolicy(for: .full) == nil`；渲染链含 46.7 box。
- AC-T4-3：`evaluate(hasLegacyFilm: true)` → `.convertToModule`；`editingInFlight` 优先 → `.editingInFlight`；既有 M8-3/M9-4 真值表逐位不变（回归）。
- AC-T4-4：转换动作后：实例在场 + carrier 缺席 + sidecar 无 `filmRecord` 键 + undo 回到 legacy 观感（T3-5 同式）。
- AC-T4-5：env 缺席时迁移行 `migratable == false`（默认面零可见）。

ΔN = 9（FilmMigrationTests +4、PipeCoordinatorLegacyTests +3、Registry env 门 +2 并入 T1 文件）。
封存面：PixelPipe（仅注释 hunk——`runTerminalTails` 标注；若实现零改则终表记"注释例外"）。

## T5 求解链不动验证 + tile 政策钉死

目标：FilmSolveCache 键控原样；`pixelUm` 全帧锚；tile 永不可达机检钉死。

编辑点（预期极小，多为测试）：
1. `LightamerCore/Sources/Pipe/Film/FilmTailPolicy.swift`：`FilmSolveCache` 键（materialPairHash ⊕ statsHash ⊕ modeTag）零改；`FilmStatsSeam.histogram` 调用点从 `runFilmLeg` 移到 `SpektraFilmModule.process`（调用迁移，函数体零改）。**统计对象变更声明**：输入平面从"主链顶面"变为"本层 46.7 输入"——单层置顶档逐位等价（T7 桥接测试主门），多层档漂移由迁移提示承担（R3）。
2. `SpectralPayloads.swift`：`pixelUm(frameWidth:)` 零改；`tileHalo` 不覆盖（T2 已定）⇒ plane 恒层子 run 全平面 ⇒ 锚正确（R1 缓解成立）。
3. tile 政策文档：`SpektraFilmModule` doc comment 钉死"per-ROI 红线结构面延续（M3-3）+ P2 挂账"。

AC（机检）：
- AC-T5-1：`FilmDeterminismTests` 精确值逐位不变（fold 序/字节序/statsHash 全量回归）。
- AC-T5-2：`SpectralPayloads.swift` 与 `FilmTailPolicy.swift` 求解段 diff 为空（除 histogram 调用点迁移 hunk + 注释）。
- AC-T5-3：tile 框架面断言：`SpektraFilmModule` 实例在 tile  eligible 扫描中恒 excluded（flag 缺席 + halo 0 双条件）。
- AC-T5-4：`pixelUm` 全帧锚断言：process 收到的 plane 宽 == 层子 run 全平面宽（非 tile 切片——以不 tile 不变式为前提的契约测试）。

ΔN = 4（FilmDeterminismTests 0 新增全回归、SpektraTilePolicyTests 新文件 4）。
封存面：无。

## T6 下游面（DRT 交接/导出/缩略图/面板/Film 卡/MCP）

目标：film 退出终端共享序后的剩余面逐项收敛；缩略图恒 legacy；面板换锚；Film 卡退役。

编辑点：
1. **DRT 交接**：`runTerminalTails` ② DRT tail 的 upstream 值——legacy 档仍 film 输出 hash（零改）；新档 film 缺席 ⇒ upstream 回主链顶面 hash（`run()` 调用点既有语义：`topEnabledPosition` 顶面，含 46.7 输出——**代码零改**，行为自然收敛）。`DrtTailAssembly.seed` 签名零改。`isTerminalTailSkipped` film 分支保留（legacy 腿仍需降出/重放）。
2. **导出**：`ExportQueue.enqueue(filmTails:)` + `$jobFilmTail` 保留（D-SM-4 legacy 通道）；`ExportRenderer` 装配：legacy 档传 tails、新档传 nil（含 46.7 实例自然进导出链）。`ExportQueueContract` 零 diff。`ExportFilmChainTests` 加参数化形态（legacy vs module 双臂断言）。
3. **缩略图**：`SessionThumbnailRenderer` 豁免面对 spektraFilm 生效——thumbnail run 显式剥掉 opName == spektraFilm 的实例（M9-4「穿线」豁免两件先例同构）；KD-4 门（`filmTailPolicy(for: .thumbnail) == nil`）保留。grid 渲染成本不涨。
4. **Film 面板**：`FilmPanelModel` 数据源换锚——三级读改为 live 实例 params → history 投影 → carrier（carrier 仅 legacy 档）；`commitFilm` 面板调用点切标准 `recordChange`（新档）；Solve 按钮 `invalidateAll()` 保留；enable 入口改为"add instance 到最上层"（单实例语义：已有则定位）。View 主体保留。
5. **节点 Film 卡退役**（OQ-5(a)）：`NodeCanvasGeometry.filmCardID` + `includesFilmCard` + 卡渲染全撤；`FilmCardTests` 退役（文件删 + Project/BUNDLE-MAP 同批退役登记）；`editor_node_film*` 3 键：xcstrings 保留（删键 = 翻译记忆丢失惯例——zh-audit allowlist 备注退役，scanner MISSING 豁免）。
6. **MCP/NodeGraphCommand**：`NodeKind` 三 case 零新增（M2-4 红线）；spektraFilm 自动进 `apply_params` opName 寻址（Registry 动态面零改或加分支，视 IopCatalog 形态）；`requiresControl`/turn-taking 全 op 通用零改。

AC（机检）：
- AC-T6-1：新档 `.drt` 渲染：DRT tail upstream == 含 46.7 的主链顶面 hash（seed 值断言）；legacy 档 upstream == film 输出 hash（既有行为回归）。
- AC-T6-2：导出双臂：legacy 档导出含 film 腿（hash == 基线）；新档导出含 46.7 实例输出且 `filmTails` 传 nil。
- AC-T6-3：thumbnail run 实例集不含 spektraFilm（剥除断言）；`filmTailPolicy(for: .thumbnail) == nil` 回归。
- AC-T6-4：面板换锚：新档面板读 == live 实例 record；legacy 档面板读 == carrier；Solve 按钮两种档均可达。
- AC-T6-5：grep 机检 `filmCardID/includesFilmCard` 全仓零命中（除 DECISIONS 注记）；`NodeGraphCommand`/`PipelineDocument` diff 为空。
- AC-T6-6：`apply_params(opName: "spektraFilm")` 可寻址（env 门开时）；关时走 unknown-op degraded 面。

ΔN = 10（ExportFilmChainTests +3、ThumbnailStripTests +2、FilmPanelTests 换锚 +3、McpFilmTests 新文件 2）。
封存面：PixelPipe（预期零逻辑改——终表记"行为自然收敛无 hunk"或注释 hunk）。

## T7 桥接测试 + golden 迁移 + BUNDLE-MAP

目标：两宿主逐位相等桥接测试（P1 验收主门）；双臂 golden kernel 字节零改；测试域归置同批。

编辑点：
1. 新 `Tests/LightamerTests/SpektraHostBridgeTests.swift`（落域 IOPP/桥接面）：同一输入平面 + 同一 record，legacy 回放腿（`runFilmLeg` 经 filmTail 装配）vs module 链（`SpektraFilmModule.process` 经层子 run 单层置顶）输出逐位比对——覆盖密度臂/光谱臂/identity 三形态。**限制声明**：桥接相等仅在"单层、胶片置顶、无层蒙版、层内 46.7 前 ops 为空"成立（统计对象同一性前提）；多层形态测"迁移行可达 + 漂移提示渲染"不测逐位。
2. `ACEScc 往返精度门`：log→linear→log 往返误差 ≤1e-6（f32 1D 查表/公式精度带——桥接测试内断言往返项，非胶片核项；若超带则 T2 切纯函数(FMA)形态，需 re-plan）。
3. 既有 Film/Spectral 测试域归置：47 个 film/spectral 测试文件**零改名**；`FilmLegTests`/`FilmCoordinatorTests`/`ExportFilmChainTests` 加双形态参数化（T3/T4/T6 已计）；`FilmCardTests` 退役（T6-5）；新文件（RegistryFilmModuleTests、SpektraFilmTests、WorkspaceLegacyTests、SpektraTilePolicyTests、McpFilmTests、SpektraHostBridgeTests）按域模式归入唯一 target + `Project.swift` 显式登记 + BUNDLE-MAP 同批更新行。
4. `SpectralDualArmGoldenTests` / `SpectralCrossArmGoldenTests` / `FilmGoldenTests` / `BWSpectralGoldenTests`：golden 字节零改（kernel/装配零改的自然结果）；宿主路径变更由桥接测试覆盖，不改 golden 本身。

AC（机检）：
- AC-T7-1：桥接三形态逐位相等（density/spectral/identity 各 ≥1 fixture，CC0 机器样张腿）。
- AC-T7-2：ACEScc 往返误差 ≤1e-6（超带 = T2 形态回炉，门失败）。
- AC-T7-3：全部 golden 文件 md5 == 基线（`git diff --stat Tests/` 仅新文件 + 参数化测试源，无 `.bin/.png` golden 变更）。
- AC-T7-4：BUNDLE-MAP 行内 method 数对账 == 各文件终态；`tuist generate` 后全 bundle 可列（无孤儿登记）。
- AC-T7-5：D-SM-1 负测：同 params + 不同上游统计 ⇒ 平面 key 不同（无陈旧命中）；证伪则回落 4.4 缝 + re-plan。

ΔN = 12（SpektraHostBridgeTests 8、ACEScc 往返 2、D-SM-1 负测 2）。
封存面：无。

## T8 收口（全套 + 走查 + SUMMARY/DECISIONS + 申报终表）

1. 全套回归：`Scripts/test-direct.sh --all`（orchestrator 批准制；machine-guard G1-G4 + 运行时 monitor 伴跑；预期基线 = M9-2 收口值 + 本批 ΔN=56 − FilmCardTests 退役数）。
2. GUI 走查：env 门开档——迁移行渲染/确认 sheet（含漂移说明）/转换后面板换锚/单实例 add-face（已有则定位）/缩略图 grid 成本观感；关档——默认面零可见变化。证据落 `.work/gui-acceptance/spektra-module/` + MANIFEST。
3. zh 对账：`zh-audit --check` 全绿；D-SM-7 新键 ≤2 申报；`editor_node_film*` 退役 allowlist 备注。
4. 产物：`SUMMARY.md` + `DECISIONS.md`（chunked 写）+ 封存面申报终表（§封存复核）。
5. 机器纪律：machine-guard 单重活；DerivedData 收口清自建容器；commit-per-task 由执行 lane 自持。

AC（机检）：全套 0 fail；MEMFAIL 0；zh-audit 全绿；grep 退役面零命中；封存 diff == 申报终表。
ΔN = 0。封存面：终表复核。

## 封存面申报表（执行前申报；T8 终表复核）

| 封存件 | 申报形态 | 任务 | 对 RESEARCH §6.1 的修订 |
|---|---|---|---|
| PixelPipe | `runTerminalTails` 注释 hunk（legacy 回放臂标注）；逻辑零改 | T4 | 收窄：4.4 折叠缝取消（D-SM-1）；调用点 upstream 自然收敛零 hunk |
| V50Order | add-only 一行 `("spektraFilm", 46.7)`，dt-verbatim 补录 | T1 | 同 RESEARCH |
| GradeCatalog（NodeOwnershipCatalog） | 第 21 行 + E7 期望 20→21；`needsEnvelope` 零改（skipsEnvelope 优化不做） | T1 | 收窄：谓词例外取消（D-SM-5） |
| ExportQueueContract | **零 diff**（filmTails 保留为 legacy 通道） | T6 | 修订：删参数推迟到 deprecation（D-SM-4） |
| sidecar schema | **零 diff**（v13 不动、零新键） | T3 | 修订：v14 bump 取消（OQ-4(b) 本就推荐不 bump） |
| HistoryStack / HistoryHash | 零 diff（保留只读、新写停产） | T3 | 同 RESEARCH（否） |
| DrtRecord / TerminalTailPolicy / DrtTailAssembly / DrtEotf / Lut3dKernels.metal / 六格式导出矩阵 / NodeGraphCommand / PipelineDocument | 零 diff | T6 | 同 RESEARCH（否） |

实质改动仅 V50Order 一行 + GradeCatalog 一行 + E7 期望；其余全是注释/零改。D-SM-1 若证伪则 PixelPipe +1 逻辑 hunk（re-plan 触发器）。

## 风险→任务映射

| RESEARCH 风险 | 承载任务 | 门 |
|---|---|---|
| R1 pixelUm 锚 | T2（不覆盖 tileHalo）+ T5 | AC-T2-2/AC-T5-3/AC-T5-4 |
| R2 corr 网格/scratch | T5（不 tile ⇒ 零变化） | AC-T5-2 |
| R3 多层档统计漂移 | T4（最上层默认落点）+ T6（漂移提示）+ T7（限制声明） | AC-T4-5/AC-T6-4/AC-T7-1 |
| R4 100MP 内存峰 | T2（.oneInstance） | AC-T2-1 |
| R5 层内重复求解 | T5（SolveCache 命中） | AC-T5-1 |
| R6 ACEScc 往返 | T2（kernel 复用）+ T7（精度门） | AC-T7-2 |
| D-M3-2-1 翻转三问 | §4.0 已答；T6-5/T3（单一 record/默认无蒙版） | AC-T6-5/AC-T3-3 |

## 执行纪律（执行 lane 自持，抄送任务书）

- commit-per-task；产物交接 BUILD-HANDOFF.txt；machine-guard 单重活；zh-audit 每批对账。
- 双臂 golden kernel 字节零改红线（md5 机检 AC-T2-3/AC-T7-3）。
- `tuist generate` 恒为登记批最后一个动作（L041）；BUNDLE-MAP 同批。
- 默认面零可见变化直到走查 + 桥接全绿（env 门纪律）。
