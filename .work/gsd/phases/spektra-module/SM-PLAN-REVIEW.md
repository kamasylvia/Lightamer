# spektra-module P1 PLAN 评审（zcode review lane）

> 审对象：`.work/gsd/phases/spektra-module/PLAN.md`（25KB，omp planner 产物，在册 HEAD `be6e5886`）。
> 对照正本：同目录 `RESEARCH.md`（51KB 设计案）+ `sm-plan-prompt.md`「用户裁决」六 OQ + AGENTS.md 跨批不变量速查 / M8·M9-4 节。
> 审核纪律：只读；零 commit / 零构建 / 零测试；全部判定基于 HEAD `be6e5886` 亲核（file:line 实测）。唯一产出 = 本文件（chunked 追加写）。
> 产物命名：任务书正本写 `M8SM-PLAN-REVIEW.md`，派遣补充纪律指定 `SM-PLAN-REVIEW.md`——按后者（更具体、更晚）落盘。审核日 2026-11-03。

---

## 结论头

**FAIL / 2 blocking + 10 major + 9 minor**

（格式 = `<PASS|FAIL> / N blocking + N major + N minor`；PASS 仅当 0 blocking——按 repo 先例「FAIL / 1 error + …」写 FAIL。）

- **一句话**：PLAN 的六 OQ 转录、风险→任务映射骨架、封存面收窄方向基本忠实；DRT 交接零改、sidecar 写腿零改、D-SM-1 免折叠缝三个关键判定亲核**成立**。但**实例挂载作用域**（全局 `recordChange` vs「最上层 grade 层」）、**ACEScc 包夹域**、**判别谓词扫描范围**三者在 HEAD 语义下互斥（B1）；且 **P1 验收主门「两宿主逐位相等」按构造不可达**（B2：module 路径多两次 f32 ACEScc 往返）。二者须 replan 后重审。
- 修复路径：omp replan 按本报告 §一/§二/§三 修法逐条落 PLAN → 重走本 review（建议同 lane 复审 B1/B2/M1/M2/M3/M6 闭合）。

| 维度（任务书清单） | 判定 | 一句话 |
|---|---|---|
| 1 裁决一致性 | FAIL | OQ-2/3/4/5/6 落实；**OQ-1 `.oneInstance` 仅声明无执行面**（M4）；OQ-3(a) 的层蒙版收益被 B1 挂载歧义架空 |
| 2 研究覆盖 | FAIL | §4.0-4.2/4.4-4.8、§6 R1-R6 有映射；**§4.3 蒙版验收、§5.3 回退面缺项**（M10）；§5.2 filmPlacement 零改未声明（m8） |
| 3 AC 可机检性 | PASS* | 无「合理/正确」类主观词；但 AC-T7-1 逐位断言不可达（B2）、AC-T1-1/T2-3 API 名与 md5 提取法不准（m2） |
| 4 封存面申报核 | PASS* | 收窄（ExportQueueContract/sidecar 零 diff、PixelPipe 注释-only）**条件成立**——前提 = M2（assembleFilmLeg 访问级）与 M3（histogram 调用点）按非封存解法修；schema 零触碰已显式声明 ✓ |
| 5 T 序可行性 | FAIL | T5 与 T4 双轨矛盾（M3）；测试登记集中 T7 违反同批纪律（M9）；env 门 body 读与注入式 AC 冲突（m3） |
| 6 ΔN 与测试策略 | FAIL | 56 算术自洽；桥接测试落域与 IOPP 路由规则冲突、贴线 bundle 内存未评估、FilmCardTests −4 未给数（M9） |
| 7 裁决心证抽查 | 3 PASS / 2 FAIL | 见下表 J1-J5 |
| 8 反盲区 | FAIL | processComposite 全消费者自动纳入胶片（M7）；process 迁移门失效（M6）；MCP 写入落基链（B1）；add-face/IopCatalog/UserDefaults/卡退役残留（M5/m4/m5/m8） |

### 心证抽查（亲核 HEAD `be6e5886`）

| # | PLAN 判定 | 结果 | 证据 |
|---|---|---|---|
| J1 | D-SM-1 prepareChain 无需新折叠缝 | **PASS** | `levelHash[i] = decode ⊕ enabled paramsHash≤i (+processFork)`（PixelPipe.swift:967-981）；层子 run seed = `prefixHash`（折 base levelHash + 下层 chain/blend/mask，LayerCompositeDriver.swift:402-414）→ 输入平面内容被键控 → 统计/求解确定。材料内容：store 仅启动期构建一次（LightamerShell.swift:950-956）；`materialPairHash` 为 profile 内容折叠（FilmMaterialStore.swift:145-152）。**残余注记**：module Params 只携 stock id，若未来引入会话内 pack 重载，平面键缺材料内容项（legacy seed 折 solvedPackHash）——登记为将来触发器，非本轮 finding |
| J2 | T6-1 DRT upstream「代码零改、自然收敛」 | **PASS** | `runTerminalTails` 起始 `upstreamSeed = levelHash[topEnabledPosition]`（PixelPipe.swift:1177），仅 `filmTail` 非 nil 时被 film 输出 hash 覆盖（:1179-1186）。RESEARCH §4.7「run():926 调用点换回」表述不准，PLAN 修正成立 |
| J3 | OQ-4(b) 判别式 `hasLegacyFilmRecord && !hasSpektraFilmInstance`（后者读 `effectiveInstances()`） | **FAIL** | `effectiveInstances()` = scope nil，只走 `item.layerScope == nil` 的全局项，注释「layer-scoped items never leak」（HistoryStack.swift:437-466）→ 层内实例不可见（B1） |
| J4 | D-SM-5 ACEScc 往返复用现有 kernel | **PASS（命名/方向）/ FAIL（等价性）** | `grade_acescc_in/out` 存在（ACESccInModule.swift:109-113）；方向 out = decode + AP1→Rec2020、in = Rec2020→AP1 + encode（ACESccMath.metal）正确；但往返非恒等 → B2 |
| J5 | T3-4 LightamerSidecar.swift 零 diff | **PASS** | `makeSidecarDocument` 在 App 层（PipeCoordinator.swift:1693），film 字段读 carrier（:1723-1727,1775）；`driftDetected` 只读 history 投影（LightamerSidecar.swift:1127-1133）→ 已迁移档缺键不误报漂移 |

---

## 一、blocking（2）

### B1 — 实例挂载作用域 × ACEScc 包夹域 × 判别谓词扫描范围，三者互斥

**定位**：T3-2（「迁移/新建胶片一律经 `recordChange(opName: "spektraFilm", params:)`」）、T4-5（「挂**最上层 grade 层**（无层则新建层）+ `recordChange` discrete commit」）、T6-4（「add instance 到最上层」）、T6-6（MCP `apply_params` 可寻址）、T3-1（`hasSpektraFilmInstance` 读 `effectiveInstances()` opName 扫描）、D-SM-5（process 内无条件 ACEScc 往返）。

**亲核事实**：
1. `EditorState.recordChange(_ snapshot:label:)` → `history.commit(snapshot, label:)`，**无 layerScope = 全局基链**（EditorState.swift:217-219）。层内写入是另外的路：`addModuleToLayer(layerID:template:)`（:924-954，含 ownership 校验 + 结构 commit）、`recordLayerChange(_:layerID:label:)`（:1151-1156）、`commitContinuousEdit(layerScope:)`（PipeCoordinator.swift:2050-2075）。
2. ACEScc 包夹**只作用于 adjustment 层子 run**：`guard let adjustment = layer as? AdjustmentLayer` 后 `boxes = LayerCompositeSeam.acesccEnvelope(boxes)`（LayerCompositeDriver.swift:387-398）；基链从不包夹（「Envelope boxes are NEVER registered」，Registry.swift:72-76）。代码库**已知且已有正确先例**：`FilmPanelModel.addPlacement()` 注释明写「the ACEScc envelope wraps it ONLY inside an adjustment layer's sub-run」，实现 = 取最上层 adjustment 层、无则 `addAdjustmentLayer()`、再 `addModuleToLayer`（FilmPanelModel.swift:748-766）。
3. `effectiveInstances()`（scope nil）只遍历 `item.layerScope == nil` 的全局项（HistoryStack.swift:437-466）。
4. MCP `apply_params` 以 (opName, multiPriority) 寻址，input schema 无层目标参数（EditingToolset.swift:591-604）→ 只能写全局。
5. RESEARCH §4.2 原文「layerScope = 所在 grade 层 UUID（或 nil = 基链）」本就允许基链——PLAN 继承了该缺口。

**后果（任一执行读法都破一处）**：
- 按 T3-2/T4-5 字面走 `recordChange` → 实例落**基链**（46.7 < 70 = 基链 A 段）→ 输入为 scene-linear Rec2020，module 仍对其做 `grade_acescc_out`（decode + AP1→Rec2020）→ **全部模块档色彩错误**；基链无层蒙版 → OQ-3(a) 核心收益落空。
- 按「最上层 grade 层」走层写入 → 包夹正确，但 `hasSpektraFilmInstance`（全局扫描）**看不见层内实例** → carrier 一旦非空（M1：任一 undo/redo 即回灌）→ `hasLegacyFilmRecord && !hasSpektraFilmInstance` 为真 → **legacy 尾段 + 层内 module 双胶片**；迁移行重现 → 可重复转换出第二实例。
- MCP `apply_params("spektraFilm")` 恒落基链 → 同第一条色彩错误。
- 现有 AC 抓不住：AC-T7-1 桥接走「经层子 run 单层置顶」（包夹路径），AC-T4-2「渲染链含 46.7 box」对基链放置同样为真。

**修法建议**：
1. 钉死 spektraFilm = **grade 层专属 op**（NodeOwnershipCatalog `.grade` 语义）；迁移确认 / 面板 enable 复用 `addPlacement()` 形态（最上层 adjustment 层，无则 `addAdjustmentLayer()`）+ `addModuleToLayer`，参数写入走 `recordLayerChange` / `commitContinuousEdit(layerScope:)`；声明 undo 步数（m7）。
2. `hasSpektraFilmInstance` = **全作用域扫描**（全局 ∪ 每个 AdjustmentLayer 的 effective chain，`ModuleRegistry.effectiveInstances(layer:)` 形，ModuleRegistry.swift:132-134），**presence 语义**（不看 enabled，见 M1）；单源函数供 filmTailPolicy / filmLegRequestTags / 迁移行 / 面板 / sync 腿 / process 门（M6）共用。
3. 基链写入面（`recordChange`、MCP `apply_params`、Copy/Paste 全局 epoch）对 spektraFilm = **typed reject**（或 P1 显式不开放 MCP 写，`apply_params` 返 `invalidParams` 带层专属提示），各一条负测 AC。
4. 增 AC：「spektraFilm 出现在基链」不可达（负测）；三入口（迁移/面板/MCP）落点断言 = grade 层；判别谓词层内实例正测 + 基链零命中负测。
5. RESEARCH §4.2「或 nil = 基链」在 DECISIONS 勘误。

### B2 — P1 验收主门「两宿主逐位相等」按构造不可达

**定位**：PLAN 头「视觉逐位恒等」、T7-1 / AC-T7-1（「legacy 回放腿 vs module 链……输出逐位比对」「桥接三形态逐位相等」）、AC-T7-2（ACEScc 往返 ≤1e-6）、风险表 R6；RESEARCH §4.4「单层、胶片置顶……逐位等价」。

**亲核事实**：module 路径 = **层包夹**（acesccIn 20.5：`rec2020_to_ap1` + `acescc_encode`；acesccOut 69.9：`acescc_decode` + `ap1_to_rec2020`）**+ module 内 D-SM-5 往返** = 两次 f32 ACEScc 往返；legacy 腿在终端段线性域运行，零往返。编码 `(log2(v)+9.72)/17.52`（ACESccMath.metal `acescc_encode/decode`）：log 值 ~0.5 处 1 ulp ≈ 6e-8，decode `exp2(e·17.52−9.72)` 放大 ln2·17.52 ≈ 12× → **单次往返相对误差 ~1e-6 量级**；矩阵逆为 float32 行（文件注释自称矩阵段 ~ε，但叠加 log 段后不再是 ε）。胶片链（密度 65³ 四面体 / 光谱 tc LUT）非线性，输入 ε 可被局部斜率放大。

**后果**：
- AC-T7-1 逐位断言**必红** → 触发 T2「回炉 re-plan」；AC-T7-1 与 AC-T7-2 自相矛盾（往返若需 ≤1e-6 容差，桥接就不可能逐位）。
- AC-T7-2「≤1e-6」未定义绝对/相对：HDR scene-linear 高光（≫1）绝对误差随值放大；log 放大下相对误差亦贴/越 1e-6 → 精度门可能直接越带。
- PLAN 头「视觉逐位恒等」与「process 不 bump」的论证基础（M6-2「改观感 = 新 process 号」）需重述。

**修法建议**：
1. P1 等价口径改为 **ε 带**：往返数学推导 + 实测定带（相对误差，按值域分段：< 2^-15 线性段 / 中灰段 / > 1 高光段）；AC-T7-1 改容差断言（比较空间按 L048：decode 回 linear、f32 常数 `Double(Float(x))` 升维），AC-T7-2 同步改相对误差口径。
2. DECISIONS 写明「process 不 bump」新理由：迁移 = 用户确认的显式转换（M9-4 colorWheels「a small approximation can remain」先例同形），legacy 档未转换前仍逐位走旧腿（AC-T4-1 保留逐位）；ε 级差异不构成 M6-2 改观感。
3. 若坚持逐位：须重设计（单 spektraFilm 层免包夹 = RESEARCH §4.1 被 D-SM-5 放弃的 skipsEnvelope 优化 + module 域感知、不做内往返），涉 `needsEnvelope`（GradeCatalog 封存面例外）——属 re-plan 申报。

---

## 二、major（10）

### M1 — 迁移后任何导航都会把 legacy carrier 灌回（sync 腿 × effectiveFilmRecord 时间旅行）

**定位**：T3-5（「syncFilmCarrierWithHistory 保留……新档载体缺席 = 零动作」）、T4-5（确认动作「清空 filmRecords[url]」）、AC-T3-3 / AC-T4-4（「sidecar 无 filmRecord 键」）。

**亲核事实**：undo / redo / jump 均调 `syncFilmCarrierWithHistory()`（PipeCoordinator.swift:2099-2137）→ `setSessionFilmRecord(history.effectiveFilmRecord())`（:1116-1120）；`effectiveFilmRecord()` = 指针以下**最后一个**携 filmRecord 的 item（HistoryStack.swift:557-560）。迁移 commit 是实例 item、不带 filmRecord，旧 film item 仍在其下 → 转换后**一次 undo + redo** 即把 legacy record 灌回 carrier → `makeSidecarDocument` 从 carrier 写出 `filmRecord` 键（PipeCoordinator.swift:1723-1727,1775）。另：版本切换面 `versionActionDidChange()`（:586-591）只 sync DRT、**不 sync film**（既存姊妹缺口；双轨期依赖更重——跨转换点切版本时 carrier 不更新）。

**后果**：AC-T3-3/T4-4 持久化不变量导航后即失效；与 B1 谓词组合 = 双胶片；若 `hasSpektraFilmInstance` 按 enabled 判定，用户**关闭** module 后 legacy 尾段复活（carrier 已被导航灌回）。

**修法建议**：sync 腿改为「全作用域存在 spektraFilm 实例 → 清 carrier；否则 = effectiveFilmRecord」，同款接入 `versionActionDidChange`；`hasSpektraFilmInstance` 钉 **presence** 语义；DECISIONS 登记 M3-3「film item + 文档字段成对写」锚一致性对已迁移档的**有意解除**（driftDetected 只读 history，J5，不误报）；增 AC：转换 → undo → redo → carrier 缺席 + sidecar 无键 + 迁移行不可见；转换 → 关 module → 无胶片（legacy 不复活）；跨转换点版本切换两侧观感各自正确。

### M2 — D-SM-2 delegate 路径按 HEAD 访问级不可执行；封存申报潜在漏项

**定位**：D-SM-2、T2-1 process 步骤、T2-3（「FilmMethodBox 加可测构造缝」）、封存表 PixelPipe 行。

**亲核事实**：`static func assembleFilmLeg(...)`（PixelPipe.swift:1301）**无 public = internal**；载荷（密度 65³ bake / 光谱 tc payload）只在 `private static assembleDensityFilmLeg`（:1328）/ `assembleSpectralFilmLeg`（:1373）内构建。`SpektraFilmModule` 落 LightamerIOP（另一 target）→ 不可调用。D-SM-2 文本「直方图 → FilmRuntimeSolve → 构造 FilmMethodBox（Params 映射）→ box.process」**漏掉工厂**——无 payloads 的 `FilmMethodBox.process` 走 blitIdentity（RESEARCH §2.3 process 分派）。执行者的自然解法「把 assembleFilmLeg 改 public」= PixelPipe 封存 hunk，**未申报**。另 T2-3 冗余：`public init(record:method:payloads:spectralPayloads:scratch:)` HEAD 已在（FilmTailPolicy.swift:355-365）。

**修法建议**：在非封存文件立 public 包装缝（`Pipe/Film/` 新 `FilmLegFactory.swift` 或 FilmTailPolicy.swift 内 `public enum`，同 target 内调 internal `PixelPipe.assembleFilmLeg`）→ PixelPipe 零 diff 可保；D-SM-2 改写为「histogram → 包装缝（传 `piece.renderProcess`——IOPiece 已携，ColorWheelsModule.swift:318 先例）→ `FilmMethodBox(init 注入 payloads)` → process」；删 T2-3；AC 增「PixelPipe.swift `assembleFilmLeg` 访问级/签名零 diff」。

### M3 — T5「histogram 调用点迁移」与 T4 双轨 / 封存申报自相矛盾

**定位**：T5-1、AC-T5-2、封存表 PixelPipe「逻辑零改」。

**亲核事实**：legacy 腿统计在 `runFilmLeg` 内（PixelPipe.swift:1241-1243）。双轨期 legacy 回放臂必须保留它（AC-T4-1 逐位）。T5-1 字面「从 runFilmLeg **移到** SpektraFilmModule.process」= 删 legacy 统计 → legacy 解 nil histogram（:1237-1240 注释：增益仅剩手动曝光）→ AC-T4-1 红；且为 PixelPipe 逻辑 hunk，与申报「注释-only」冲突。AC-T5-2 指向 FilmTailPolicy.swift，但 `runFilmLeg` 在 PixelPipe.swift。T2-1 已在 process 内调 histogram，T5-1 重复。

**修法建议**：T5-1 改「module 侧**新增**调用点（T2 已实现），legacy `runFilmLeg` 原样保留至 deprecation 窗」；AC-T5-2 改为「PixelPipe.swift `runFilmLeg` 函数体 diff 为空」；删 T5 与 T2 的重复描述。

### M4 — OQ-1(a)「`.oneInstance` 单实例」仅声明、无执行面

**定位**：§0 OQ-1、T2 flags、AC-T2-1、风险表 R4→AC-T2-1、T6-4（「单实例语义：已有则定位」）。

**亲核事实**：grep `oneInstance`（排除 IOPFlags.swift:26 定义行）在 App/Core **零消费者**；8 个模块声明（Temperature/Flip/Crop/Lens/Ashift/Borders/Upright/Watermark）但 add-face / 层 / paste / MCP 均不读该 flag；`addModuleToLayer` 只做 ownership 校验（EditorState.swift:928-938）。第二实例可达入口：
- grade 层 add 菜单 = **catalog 驱动**：`gradeScopeEntries()` 枚举 `GradeCatalog.gradeItems()` 再经 `templateInstance(for:)` 静态 switch 过滤（EditorState.swift:1006-1019,1049-）——若为面板 enable 复用 `addPlacement` 形态而加 `templateInstance` 分支，spektraFilm 即自动进 add 菜单（filmPlacement/colormatch 先例，CatalogAddFaceTests.swift:224-232 注）；
- MCP `apply_params`；Copy Adjustments（`isAdjustmentTransferable` = owner==.grade 单谓词 → spektraFilm 可迁移）；版本/粘贴。
- 另：模块档调整 paste 到 **legacy 档** → 目标同持 instance + carrier → 门判 module 胜，legacy 被**静默抑制**，绕过迁移 UX。

**修法建议**：列全写入入口并逐一加单实例守卫（面板 enable 定位已有；add 菜单「已有则隐藏/定位」或 `templateInstance` 分支不进 `gradeScopeEntries`；MCP typed reject 第二实例；paste 合并策略）+ 每入口负测 AC；DECISIONS 声明 Copy Adjustments 对 spektraFilm 的处置（排除 or 单实例合并）与 paste→legacy 档语义（建议拒绝或走迁移确认）；R4 缓解改挂执行面 AC。

### M5 — T1 env 门注册与 GradeCatalog 闭包 / add 菜单测试互斥

**定位**：T1-2/T1-3、AC-T1-3（「E7 checker 全绿」）、AC-T1-4（「env 缺席默认面契约逐位不变」）。

**亲核事实**：
- `testAllCatalogOpsAreDefaultFaceRegistered`（GradeCatalogTests.swift:130-139）遍历**全部** GradeCatalog 行并断言 `populate(defaultFace: true)` 下 makeBox 非 nil → spektraFilm 入目录 + env 门注册 ⇒ 默认测试进程（env 缺席）**该测必红**；AC-T1-3 与 AC-T1-4 不可同时满足。
- 计数口径：断言是**唯一 opName** `catalogOps.count == 19`（:95，行数 20，shadhi 双行）/ `resolved.count == 19`（:139）；PLAN「E7 期望 20→21」口径不准（应为唯一 op 19→20、行 20→21）；`testOwnerMatrixOverAllEighteenRows`（:144）期望表亦需加行；`testGradeScopeAddFaceEnumeratesTheCatalogMatrix`（CatalogAddFaceTests.swift:224）若 spektraFilm 进 add 菜单则需改。
- catalog 驱动消费者在 env 缺席时仍见该行：`McpSchemaCatalog.encodedDefaults` 读 `GradeCatalog.item`（McpSchemaCatalog.swift:350）；grade add 菜单（M4）→「默认面零可见变化」需逐面核。

**修法建议**：二选一写入 T1——(a) registry **恒注册**（不门），env 只门 UI/迁移/写入口 → 改写 AC-T1-2；(b) 保留注册门 + 闭包测试加 env-gated 豁免（testgain `#if DEBUG` 豁免先例，GradeCatalogTests.swift:111-118 注）并申报既有 3-4 法改动与 ΔN。推荐 (a)：门控单源、闭包测试零豁免、MCP/add 菜单面一致。

### M6 — process 迁移门在模块档失效 + 标记形态冲突

**定位**：T4-3（「.convertToModule 优先……process 迁移随后自然触发」）、D-SM-6。

**亲核事实**：`FilmMigrationAction.evaluate(processRawValue:hasFilmRecord:hasColorWheelsEdits:editingInFlight:...)`（EditorState+FilmMigration.swift:48-58）以 `hasFilmRecord || hasColorWheelsEdits` 为适用门；面板传 `hasFilmRecord: coordinator.hasFilmRecord(for: url)` = **carrier 存在**（FilmPanelModel.swift:579-584；IOPPanelProvider.swift:124 同形）。convertToModule 清空 carrier 后，v1/v2 文档（无 colorWheels 编辑）process 迁移 = `.notApplicable` → **被困冻结臂**（v1 密度 / v2 光谱）；「随后自然触发」在 HEAD 不成立。且 M9-4 film 标记形 = film item VERBATIM（commitFilm 族）——对已转换档触发会把 filmRecord item 写回 history，叠加 M1 重灌 carrier。`migratable` 只认 `.migrate`（EditorState+FilmMigration.swift:61-64），新 case 需显式纳入。

**修法建议**：process 门 film 源改为「`hasLegacyFilmRecord` ∨ 全作用域 spektraFilm 实例在场」；新增第三标记形（spektraFilm params verbatim 经 `recordLayerChange`），模块档禁走 film-item 标记形；`migratable` 扩认 `.convertToModule`；增 AC：v1 legacy → convert → process 迁移行可见、确认后标记不写 filmRecord、v3 臂生效。

### M7 — 渲染面反盲区：processComposite 全消费者自动纳入胶片

**定位**：T6-3（缩略图）、T8 走查「缩略图 grid 成本观感」、PLAN 头「视觉逐位恒等」。

**亲核事实**：spektraFilm 入 grade 层后，一切走 `RenderPipeline.processComposite` 的入口**自动**渲染胶片（grep 7 处消费者）：
- `QuickLookRenderer.swift`：全文零 film —— legacy 档 QuickLook 恒无胶片；
- `ColorMatchService.swift:217,223`：显式 `filmTail: nil` 排除胶片（追色参考统计）；
- `SessionThumbnailProvider.swift:508-528` 物化 layerStack → `SessionThumbnailRenderer.swift`（头注「**Phase 8 contract (禁改)**」）渲染 grid；
- `ExportRenderer`：预期纳入 ✓。

PLAN T6-3 只处理缩略图，且编辑点表述（「SessionThumbnailRenderer 豁免面对 spektraFilm 生效」）指向禁改文件；QuickLook 预览与追色参考统计对已迁移档 = 观感/统计变化，与 P1「视觉逐位恒等」前提冲突且未申报。

**修法建议**：T6 增「渲染入口清单」逐面裁定 include/strip + 每面一条 AC：export include；thumbnail/grid strip 落 **SessionThumbnailProvider 物化层**（不触 SessionThumbnailRenderer）；QuickLook / ColorMatch 显式裁定（建议 QuickLook include = 正确观感、ColorMatch strip = 与 legacy `filmTail: nil` 同语义）写 DECISIONS；T8「缩略图 grid 成本观感」改可度量指标（单张渲染耗时 / planesRendered 对照 legacy）。

### M8 — R4 内存：ACEScc 往返中间平面未计账

**定位**：D-SM-5、风险表 R4→AC-T2-1、R6。

**亲核事实**：`IOPModule.process(input:output:roiIn:roiOut:piece:metal:)`（IOPModule.swift:125-132）只给 in/out 两张纹理；D-SM-5「log→linear→胶片→linear→log」需 ≥1-2 张全帧 float32 中间面（100MP × 16B ≈ 1.6GB/张），叠加光谱 scratch（SpectralScratchAllocator）。legacy 腿在终端段线性域运行，无此中间面。AGENTS 标尺：IOP bundle 峰 7654MB 贴 8192 门；运行时看门狗单实例 >9GB kill-9。RESEARCH R4/R6 只算算力（R6「2 次 log/pow ≪ 胶片链本体」），PLAN 把 R4 映射到 `.oneInstance` flag（且该 flag 本身无执行面，M4）。

**修法建议**：规定中间面复用（借 SpectralScratchAllocator slot 或以 out 纹理承接首段 + 单中间面）；增 100MP 峰值 RSS 探针 AC（`LIGHTAMER_PERF_PROBE=1` + XCTSkipUnless 惯例，断言 module 腿相对 legacy 腿 ΔRSS ≤ 1 张全帧平面）；全套 `--all` 前跑一次贴线 bundle 定向轮（`--bundle` IOP/IOPParity）。

### M9 — 测试策略：桥接测试落域 / 规模 / 登记时序

**定位**：T7-1（「落域 IOPP/桥接面」）、AC-T7-1（CC0 机器样张腿）、T7-3（集中登记）、T2「BUNDLE-MAP T1 批同登记」、T8-1 基线公式。

**亲核事实**：
1. IOPP 桶按**文件名模式**路由（`*Parity*|Golden*|ToneEqual*|Lut3d*`，BUNDLE-MAP 头 D5 实拆记录）；`SpektraHostBridgeTests` 不命中任何模式 →「落域 IOPP」与路由规则冲突，域归属不确定。
2. IOP / IOPP 为贴线 bundle（AGENTS：IOP 7654 / IOPParity 5788MB）；AC-T7-1 要求 CC0 实拍样张过两套全宿主（+ M8 中间面）→ MEMFAIL 风险未评估。
3. T7-3 把 BUNDLE-MAP / Project.swift 登记集中到 T7，但新测试文件分别在 T1/T3/T5/T6 commit 创建 → 违反 M2-4-0 E2「同 commit 登记 + `tuist generate` 末动作（L041）」；T1..T6 的 AC 在各自 commit **无法机检**（文件不在任何 target，测试不跑）。
4. FilmCardTests 退役 = APP **4** 法（BUNDLE-MAP:615；`grep -c "func test"` = 4），T8-1 基线公式未写数。

**修法建议**：桥接测试改名命中 IOPP 模式（如 `SpektraBridgeParityTests`）或明确落 LAYERS 并写 BUNDLE-MAP 行；夹具 = 合成小平面（密度/光谱/identity 三形态各一）+ 1 张降采样 CC0；跑法 `Scripts/test-direct.sh --bundle <域>`；**每任务各自同批**登记 Project.swift + BUNDLE-MAP + `tuist generate`；T8 基线写死「M9-2 收口值 + ΔN（含本报告新增）− 4」。

### M10 — 研究覆盖缺项：§4.3 蒙版收益验收 + §5.3 回退面

**定位**：PLAN 全任务（无对应 AC）；RESEARCH §4.3 / §5.3。

**事实**：
- §4.3（层 opacity / blendMode / mask 自动继承 = OQ-3(a) 裁决的核心理由「蒙版是用户令核心收益」）在 PLAN 中**无任何 AC 或走查项**：T7 桥接限定「无层蒙版」、T8 走查清单无蒙版项。
- §5.3 回退面：env 关闭后，已迁移档的 spektraFilm 走 `degradedForUnknownOps`（enabled=false + toast，LightamerSidecar.swift:1145-1160）→ 画面退回无胶片（**非逐位回退**）；RESEARCH 明列并建议 pre-migrate 备份（M2-8 `pre-migrate.N-M.bak` 先例）。PLAN 只覆盖「未迁移档 env 关 = 零可见」（T4-6/AC-T4-5）。degrade pass 还改写 history items 的 enabled 位，若随后写回 sidecar，再开 env 后实例仍为 disabled——回退的不可逆面未申报。

**修法建议**：T7/T8 增蒙版 AC（层 opacity 0.5 / 径向蒙版下 module 输出 = 层混合公式期望，合成平面）+ 走查项；T4 增 env-off 迁移档 AC（toast、数据保留、legacy 不复活、重开 env 后 enabled 状态的显式语义），并裁定是否在 convert 前打 pre-convert 备份（或在 DECISIONS 接受非逐位回退）。

---

## 三、minor（9）

| # | 定位 | 问题 | 修法 |
|---|---|---|---|
| m1 | PLAN 头基线 | 基线写 `e63ebb3f`，现 HEAD `be6e5886`；其间 `1efbc9e2`（M9-2 review 修复）改 FilmProfile.swift（+22/−）、SpectralDualArmGoldenTests 阈值、SpectralProfileDecodeTests（`git diff --stat e63ebb3f be6e5886`）；PixelPipe 未动 | 执行基线 = 派遣 HEAD（≥ `be6e5886`）；AC-T2-3 函数体 md5、AC-T7-3 golden md5 在执行 HEAD 重钉 |
| m2 | AC-T1-1、T3-2、AC-T2-3 | API 名漂移：`V50Order.order(of:)` 实为 `order(for:)`（V50Order.swift:251）；`recordChange(opName:params:)` 实为 `recordChange(_ snapshot: ModuleInstance, label:)`（EditorState.swift:217，作用域问题见 B1）；函数体 md5 未定义提取法 | 改正名；md5 提取法写死（函数签名行至同缩进闭合 `}` 的确定性截取） |
| m3 | T1-3 vs AC-T1-2 | T1-3「populate 内读 ProcessInfo」= body 求值，与 AC-T1-2「注入式、不得在 body 求值」冲突；KD-3 实形 = `isFullFaceRequested` static 计算属性 + 组装根传 `populate(_:defaultFace:)`（Registry.swift:57-71） | `populate(_:defaultFace:filmModule: Bool = false)` + `isFilmModuleRequested`；迁移行/写入口门以 registry 可解析为单源，不二读 env（与 M5 二选一联动） |
| m4 | T1-4 | IopCatalog 条件句未决；HEAD 为手写静态 19-op 表（IopCatalog.swift:59；头注「the catalog is the key REFERENCE, not a whitelist」）→ `apply_params` 可寻址不依赖它，但 `list_iops` 不会列 spektraFilm | 显式裁定：加行（+ McpEditingToolsetTests 反射守卫 / version）或声明不加；`mcp_tool_desc_apply_params` 描述零改声明 |
| m5 | AC-T6-5 | Film 卡退役 grep 仅 `filmCardID/includesFilmCard`；残留面 `NodesPanelModel.FilmCardProjection/filmCard`（NodesPanelModel.swift:58-86）、`EditorNodesPanelView.filmCardView/filmCardMarker "editor.nodes.film"`（:140,264-268,508-556） | grep 集扩至上述符号 + AX id；声明 Film 页入口保留（`LightamerShell.swift:2255` filmPanel 动作） |
| m6 | T6-4 | 宽容度/统计快照语义：`FilmStatsSnapshot.last` 由最后一次 histogram 调用写入（Registry.swift:88-93），模块档 = 层 46.7 输入统计；`currentFilmRecord`（PipeCoordinator.swift ~:1094）carrier-only，模块档宽容度/descriptor 数据路需换锚 | T6-4 补宽容度面板/descriptor 数据源换锚 + 统计对象语义注记（R3 同族）+ 一条 AC |
| m7 | T4-5、D-SM-6、AC-T4-4 | 「无层则新建层」= 建层结构 commit + `addModuleToLayer` 结构 commit + 参数 `recordLayerChange` ≥2-3 item（HistoryStack 无组机制，EditorState.swift:230-236 注）；「discrete commit」单数不准；AC-T4-4「undo 回到 legacy」未给步数 | 声明 undo 步数（M9-3-T3 linked-change 先例），或「已有层优先 + 模板直接携 legacy params 入 add」压到最少 item |
| m8 | 零触碰声明 | 缺：UserDefaults 零新键（AGENTS 登记制）、filmPlacement 20.8 零改（RESEARCH §5.2）、process 不 bump 的机检 AC（`RenderProcessVersion.current == 3`）、xcstrings 尾块纯插入惯例 | 封存/零触碰表各补一行 + process 常量断言 AC |
| m9 | D-SM-6/D-SM-7 | ProcessMigrationRow/MigrationConfirmSheet 文案硬编码 process 语义（FilmPanelView.swift:150-212：button「Update to Current Process」、title、body 讲冻结 process 代际、confirm「Update」，仅 cancel 中性）；`ProcessMigrationInputs` 只有 action + onMigrate（:139-142）——「参数化形态」HEAD 不成立；convert 至少需 button/title/body（+ 漂移说明）**≥3-4 新键 > ≤2 上限**；AX id `film.migrate.*` 复用与 GUI 探针冲突 | Inputs 加文案字段（App 非封存）；键预算改 ≤4 并 T8 对账；convert 行用独立 AX id 前缀 |

---

## 四、封存面申报核（清单第 4 项）

| 封存件 | PLAN 申报 | 亲核结论 |
|---|---|---|
| PixelPipe | `runTerminalTails` 注释 hunk only | **条件成立**：需 M2（包装缝、不改 `assembleFilmLeg` 访问级）+ M3（不删 `runFilmLeg` histogram）按非封存解法修；否则 ≥1-2 逻辑 hunk 未申报。DRT upstream 零改成立（J2） |
| V50Order | add-only 一行 46.7 | 成立（插 filmicrgb V50Order.swift:171 与 lut3d :174 之间，dt v50 同值） |
| GradeCatalog（NodeOwnershipCatalog） | 第 21 行 + E7 | 成立，但计数口径修正为唯一 op 19→20（M5）；`needsEnvelope` 零改成立（D-SM-5 不做 skipsEnvelope） |
| ExportQueueContract | 零 diff（filmTails 保留为 legacy 通道） | 成立（D-SM-4） |
| sidecar schema（LightamerSidecar） | 零 diff（v13 不动、零新键） | 成立且已显式声明 ✓（AC-T3-1；`makeSidecarDocument` 在 App 层，J5） |
| HistoryStack / HistoryHash | 零 diff | 成立（`effectiveFilmRecord` / hash 尾折保留；M1 修法落 App sync 腿，不触此二件） |
| DRT 族 / Lut3dKernels / 六格式导出矩阵 / NodeGraphCommand / PipelineDocument | 零 diff | 成立（Film 卡退役只动 App 侧投影） |
| **既定禁改面（非 17 件）** | — | `SessionThumbnailRenderer.swift`「Phase 8 contract (禁改)」——T6-3 编辑点须避开（M7） |

**结论**：RESEARCH §6.1「5 件触碰」→ PLAN「实质 2 行 + 1 期望」的收窄**方向成立**；schema 版本号零触碰已显式声明。PixelPipe 零逻辑 hunk 依赖 M2/M3 修法落地——修后 T8 终表复核即可。

## 五、ΔN 复核（清单第 6 项）

- PLAN 56 = 6+8+7+9+4+10+12，算术自洽；FilmCardTests 退役 **−4**（M9）。
- 既有测试改动面须列入申报（PLAN 未列）：GradeCatalogTests 3 法（:95/:130-139/:144）、CatalogAddFaceTests 1 法（:224，若进 add 菜单）、FilmMigrationTests 真值表扩、ExportFilmChainTests / FilmLegTests / FilmCoordinatorTests 双形态参数化。
- 本报告修法将新增测试面（估）：B1 落点/谓词正负测 +4..6、M1 导航不变量 +3、M4 单实例入口负测 +3..4、M5 闭包测试改写（新增 0..1）、M6 process 门 +2、M7 渲染面逐面 +3..4、M8 RSS 探针 +1（默认 skip）、M10 蒙版/回退 +3 → 估 **+19..24**；replan 后 ΔN ≈ 75..80，再 −4。
- 两宿主桥接测试落域与跑法见 M9（改名命中 IOPP 模式或落 LAYERS；`Scripts/test-direct.sh --bundle <域>`）。

## 六、replan 闭合清单（回注 omp，修法正本 = §一/§二/§三）

1. **B1**：挂载作用域钉 grade 层（复用 `FilmPanelModel.addPlacement` 形态）+ 层写入路径 + 全作用域 presence 谓词（单源）+ 基链/MCP/paste 拒绝 + AC。
2. **B2**：等价口径改 ε 带（推导 + 实测带，相对误差分段）+ AC-T7-1/T7-2 改写 + 「process 不 bump」新理由入 DECISIONS（或 re-plan 走 skipsEnvelope 逐位案并申报 GradeCatalog 例外）。
3. **M1-M10** 按各节修法落 PLAN（优先 M1/M2/M3/M6——与 B1 同链）；m1-m9 随 replan 顺修。
4. 重走本 review（建议同 lane 复审 B1/B2/M1/M2/M3/M6 闭合，其余抽核）。

## 七、验收自查

- [x] 只读：零 commit / 零构建 / 零测试；唯一产出 = 本文件（chunked 追加 8 段，各段 ≤8KB，每段落盘后字节数 + U+FFFD 自检，发现即修）
- [x] 任务书清单 8 项逐项判定（§结论头维度表）；心证抽查 J1-J5（≥2 个关键判定亲核 file:line：J3 判别式前提证伪、J4 ACEScc 选型核名/方向/等价）
- [x] 每 finding 带 PLAN 章节定位 + HEAD 证据（file:line）+ 修法建议；未修改 PLAN
- [x] 结论头 `FAIL / 2 blocking + 10 major + 9 minor`；正文中文，标识符 / file:line 保持原文
