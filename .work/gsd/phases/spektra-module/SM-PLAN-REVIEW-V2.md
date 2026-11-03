# spektra-module P1 PLAN **v2** 复审（zcode review lane，第二轮）

> 审对象：`.work/gsd/phases/spektra-module/PLAN.md`（46,206B，v2，2026-11-03 07:17 落盘）。
> 闭合对照：同目录 `SM-PLAN-REVIEW.md`（v1 报告：FAIL / 2 blocking + 10 major + 9 minor）。
> 设计正本：`RESEARCH.md`。基线：HEAD `9a69d0e4`（亲核；`git status` 显示 PLAN.md 为 ` M` 工作区修改，无对应 commit）。
> 纪律：只读；零 commit / 零构建 / 零测试；全部判定基于 HEAD `9a69d0e4` 亲核 file:line。唯一产出 = 本文件（chunked 追加）。
> 审核日 2026-11-03。

---

## 结论头

**FAIL / 4 blocking + 8 major + 10 minor**

一句话：v2 对 v1 的**形态类**批评（挂载作用域、逐位口径、工厂访问级、histogram 双轨、env 门闭包测试、渲染入口清单、单实例入口枚举、测试登记时序、迁移文案键预算）作了系统回应，绝大部分**方向正确、可执行**——v1 的 B1 三互斥已被 D-SM-8 拆解、B2 逐位主门已改 ε 带、M2/M3/M9 的修法实测可行。但 v2 在把「module 化」落到生产链时，**四处承重结构仍缺件**：①模块拿不到材料 profile（`FilmLegFactory` 签名无 film/paper，`FilmMaterialStore` 只注入 App）；②`$requestTags` 的 grade/filter/reversal 在 module 路无供给（PLAN 称"record 内字段直达"，而 `SpectralPrintBake.tables/solveSpectral` 只读 TaskLocal）；③`runProcessMigration` 的 action guard 未改（M6 只修了 evaluate 门，确认按钮点了不生效）；④`recordChange` typed reject × `mergeLayerDown` 组合 = **胶片实例静默蒸发**（数据丢失路径）。四条都会让 T4'/T6'/T7' 的 AC 直接不可达或产生用户可见回归。

| 必核项 | v1 判定 | v2 判定 | 一句话 |
|---|---|---|---|
| B1 挂载作用域 | blocking | **部分消解** | 层放置 + `addPlacement()` 形态 + `recordLayerChange` + 全作用域 presence 谓词**成立**（D-SM-8 与 HEAD `FilmPanelModel.swift:751-765` / `EditorState.swift:1151-1156` / `ModuleRegistry.swift:132-134` 对齐）；但 **paste/批量全局 epoch 的 reject 落点未定**（M4）、**merge-down 数据丢失**（B4）。 |
| B2 ε 带口径 | blocking | **部分消解** | 逐位→容差的口径转换成立、AC 改写成立、"process 不 bump" 新理由站得住；但**三段带宽推导不自洽且低段不可判别**（M1）。 |
| M1 carrier 回灌 | major | **已消解** | D-SM-10 门控 + `versionActionDidChange` 接入 + AC-T4'-5 导航不变量；`performUndo→rebuildLayerStack→sync` 时序可满足（`EditorState.swift:448-481`）。 |
| M2 工厂注入缝 | major | **已消解（附 B1）** | 同 target 调 internal `PixelPipe.assembleFilmLeg`（`:1301` 无 access 修饰 = internal）可行，PixelPipe 零 diff 可保；但工厂**缺材料入参**（B1）。 |
| M3 histogram 双轨 | major | **已消解** | T5'-1「module 侧新增 + legacy `runFilmLeg` 原样保留」与 T4' 注释-only 自洽；AC-T5'-2 改「函数体 diff 为空」正确。 |
| M6 process 迁移行存活 | major | **部分消解** | `evaluate` 门改「hasLegacyFilm ∨ 在场」+ 第三标记形声明 OK；但**动作面 guard 未改**（B3）→ AC-T4'-4 不可达。 |

其余抽查（M4..M8 与 10 minor）见 §二/§三；新引入面（D-SM-8..12）见 §五。

> **编号约定（防混淆）**：上表的 `B1/B2/M1/M2/M3/M6` 指 **v1 报告的编号**（对照闭合用）。
> 本报告 §一/§二 新给出的 **B1..B4 / M1..M8 是 v2 的新 finding，编号与 v1 不同序**——
> 例：v1-M6（process 迁移行存活）→ 本报告 **B3**；v1-M1（carrier 回灌）→ 已消解、无新编号。

---

## 一、blocking（4）

### B1 — 材料解析缝缺失：module 生产路恒 blitIdentity

**定位**：D-SM-2（`FilmLegFactory.assemble(record:materialPairHash:histogram:plane:metal:renderProcess:)`，PLAN:50/109）、T2'-1 process 步骤（PLAN:107）、AC-T2'-4（"材料未解析档 = 恒等"PLAN:117）、AC-T7'-1（桥接三形态）。

**亲核事实**：
1. `PixelPipe.assembleFilmLeg` 签名含 `film: FilmProfile?, paper: FilmProfile?`（`PixelPipe.swift:1301-1305`），密度臂/光谱臂**都**是 `guard let film, let paper ... else { 返回 nil payloads }`（`:1328-1340`、`:1374-1381`）→ 材料为 nil 时 `FilmMethodBox.process` 走 `blitIdentity`（`FilmTailPolicy.swift:418-422`）。
2. 材料解析的唯一实现在 App：`PipeCoordinator.filmStore`（`PipeCoordinator.swift:1053`，`attachFilmStore` :1109），注入点为 `LightamerShell.swift:952-955`；`filmTailPolicy` 在 App 侧解析 `filmStore.profile(id:)` 并把 `FilmProfile` 塞进 `FilmTailParams`（`filmTailPolicy` `:851-872`）。
3. **Core/IOP 无任何全局材料持有者**：`FilmMaterialStore` 无 `shared`（全文件无 static 实例）；`FilmProfile` 在 `LightamerIOP/Sources/` **零引用**（grep 空）。module 落 `LightamerIOP`（另一 target），只依赖 Core（`Project.swift:144` `D-03: IOP → Core only`）。
4. PLAN 的工厂签名**不含 film/paper**，`materialPairHash` 是入参——但 pairHash 本身由 `FilmMaterialStore.materialPairHash(film:paper:)` 产生，需要两个 profile 才能算（`FilmMaterialStore.swift:145-152`）。

**后果**：按 PLAN 落地，`SpektraFilmModule.process` 永远拿不到 profiles → 永远 identity → **已迁移档胶片整段消失**（不是 ε 级，是全丢）；AC-T7'-1 的 density/spectral 两形态桥接必然红（legacy 腿有材料、module 腿无）。PLAN 把"材料未解析"当作合法降级态（AC-T2'-4），但生产链里它是**唯一态**。

**修法建议**：新增 Core 侧材料解析缝（`FilmStatsSeam`/`LayerCompositeSeam` 同款安装形态，如 `FilmMaterialSeam.profiles(for records:) -> (film, paper, pairHash)?`，由 IOP/App 在 populate 时注入 `FilmMaterialStore` 的只读转发）；`FilmLegFactory.assemble` 或 `SpektraFilmModule.process` 经该缝解析材料，新增 AC「store 已注入 → module 腿 payloads 非 nil」「store 缺席 → blitIdentity + 一次 toast」，并在封存/零触碰表申报该缝（Core 新文件，非封存）。

### B2 — `$requestTags` 在 module 路无供给：grade / cameraFilter / reversalPrintMode 全部静默失效

**定位**：T6'-1（"module 腿由 record 内字段直达"，PLAN:151）、D-SM-2（工厂入参只有 `record/materialPairHash/histogram`）、T4'-1（`filmLegRequestTags` 判别门，PLAN:156）。

**亲核事实**（三处消费点全部只读 TaskLocal，**无一处读 record**）：
1. `SpectralPrintBake.tables(forPairHash:film:paper:)` 首行 `let tags = Self.requestTags`（`FilmPrintBake.swift:555`）；grade tag 折进 print/scan 键并 pin `parameters.printCC`（`:566-568, 600-603`）、cameraFilter 折进 tc/print/scan 三键并写 `parameters.cameraFilter`（`:576-578, 605-607`）。
2. `FilmRuntimeSolve.solveSpectral` 的 modeTag 追加 `|grade:`、`|filter:`、`|reversal:`（`FilmTailPolicy.swift:851-866`），gain  Consumption 读 `requestTags?.paperGrade?.exposureEv`（`:906`）。
3. 唯一绑定者 = App 侧 `renderCurrentChain` 的 `SpectralPrintBake.$requestTags.withValue(tags)`（`PipeCoordinator.swift:2806-2811`）+ 导出链 `ExportQueue.swift:502`。绑定值来自 `filmLegRequestTags(for:)`，而该函数首行 `guard resolution != .thumbnail, …, workspace.hasFilmRecord(for: url), let filmStore`（`PipeCoordinator.swift:882-884`）——**carrier 缺席即 nil**。

**后果**：
- T4'-2 让"已迁移/新档恒 nil"作用于 `filmLegRequestTags`（PLAN:156「同判别门」）。carrier 被 T4'-5 清空后，导出腿（`ExportQueue` 的 per-job legTags 走同一函数，`ExportInspectorView.swift:383`）与预览腿都拿到 nil → **grade / filter / reversal 三项在 module 路全面失效**。
- 即便不改判别门，`FilmLegFactory.assemble` 也没有 tags 入参——工厂内部 `SpectralPrintBake.tables` 只会读到调用栈上的 TaskLocal（此时由 `filmLegRequestTags` 决定），与 record 无关。PLAN 的"record 内字段直达"在 HEAD 无任何实现基础（`FilmRecord` 的 `paperGrade`/`cameraFilter`/`reversalPrintMode` 在 Core/IOP 除 film-tail 的 tags 路径外**零消费者**；`grainAmount`/`halationAmount`/`diffusion*` 由 `FilmMethodBox.process` 直读 record，`:400-408`）。
- 后果二：`PaperGradeTable` 的 BW 默认档（`FilmPrintBake.swift:567-573`，仅 `paper.info.channelModel == "bw"` 时补"2"档）与实际 record 的 grade 键分叉——module 路若不接 tags，BW 相的显式 grade 选择丢失。

**修法建议**：(a) 由 module 自持：`Params` 增 `grade/filter/reversal` 的**解析后快照**（不是 record 原始名），process 内经 `FilmLegFactory.assemble(record:tags:...)` 显式传入，`SpectralPrintBake.tables/solveSpectral` 增一个可选 tags 形参（Core 内两函数签名变更，需申报：非封存）；或 (b) 保持 TaskLocal 语义，把 `filmLegRequestTags` 的门从 carrier 改为"legacy 或 module 在场"，并在 module 路继续 `withValue` 供给（改动小但把渲染正确性绑在 TaskLocal 作用域上）。二者都须新增 AC「module 路 grade/filter/reversal 三形态输出 == legacy 腿同 record 输出（ε 带）」。

### B3 — `runProcessMigration` 的动作面 guard 未改：convert 后 process 迁移按钮点了不生效

**定位**：T4'-3（`evaluate` 加 `hasLegacyFilm` / `hasSpektraFilmInstance` 默认参，PLAN:153）、AC-T4'-4（"convert 后 process 迁移行可见 ... v3 臂生效"PLAN:163）、D-SM-6。

**亲核事实**：`FilmMigrationAction.evaluate` 的适用门（`EditorState+FilmMigration.swift:53-57`）与 `PipeCoordinator.runProcessMigration` 的**动作面**是**两个独立门**：
- 动作面：`let hasFilm = workspace.hasFilmRecord(for: url); let hasCW = hasColorWheelsEdits(); guard hasFilm || hasCW else { return }`（`PipeCoordinator.swift:1028-1030`）。
- marker 分支：`if hasFilm { commitProcessMigrationMarker(record: workspace.filmRecord(for: url), ...) } else if let cw = colorWheelsVerbatimInstance { ... }`（`:1037-1045`）。

convert 动作按 T4'-5 清空 `filmRecords[url]` 后，`hasFilm == false`；若该档无 colorWheels 编辑 → **`guard` 直接 return，process 号不翻**（`workspace.setProcessVersion(.current:)` 在 `:1031`，位于 guard 之后）。PLAN 只在 `evaluate` 上加参，**未列 `runProcessMigration` 的编辑点**（T4' 编辑点 1-7 全文中无 `runProcessMigration` 字样）。

**后果**：AC-T4'-4「v1 legacy → convert → process 迁移行可见、确认后 v3 臂生效」不可达（行可见但点击无声）。且 PLAN 声明的"第三标记形 = spektraFilm params verbatim 经 `recordLayerChange`"在 `runProcessMigration` 里没有落地位置——该函数现有两支（film item / colorWheels verbatim），第三支缺失。

**修法建议**：T4' 增编辑点——`runProcessMigration` 的 guard 与 marker 分支同步改：`guard hasFilm || hasCW || hasSpektraFilmInstance else { return }`；marker 三支（film item 仅 `hasFilm` 且无在场实例时；在场实例 → `recordLayerChange` params-verbatim；否则 CW）；AC 增负测「已转换档（无 carrier、无 CW）调用 `runProcessMigration` 确实翻号并写一条 layer-scope item」。

### B4 — `recordChange` typed reject × `mergeLayerDown` = 胶片实例静默蒸发（数据丢失）

**定位**：T3'-2（"`recordChange(_:label:)` 首行加 `opName == spektraFilm → 拒收并 toast`"，PLAN:130）、AC-T3'-3（负测"`recordChange` 拒收 + history 无该 item"）。

**亲核事实**：`mergeLayerDown(id:)` 的"并入基链"分支**先**移除该层并提交结构 item，**再**对层内每个 record 走 `recordChange`（`EditorState.swift:748-754`）：
```
if case let .mergedIntoBase(chain) = outcome {
    for record in chain { recordChange(record, label: ...) }
}
```
`LayerStack.mergeDown` 在 `index == 0` 时 `adjustmentLayers.remove(at: index)` 并返回 `.mergedIntoBase(chain:)`（`LayerStack.swift:165-180`）——层已被移出栈。若 `recordChange` 对 spektraFilm 拒收，则该 record **既不进基链、也不在任何层**：参数彻底丢失（history 里只有一条结构 item，且 undo 会退回——但 redo 后再次丢失；用户侧表现为"合并图层后胶片没了，且无法通过 undo 之外的手段找回"）。

**后果**：v2 的 reject 面与既有 merge-down 写路径冲突，构成**新的数据丢失入口**（v1 无此问题）。AC-T3'-3 的负测只覆盖"直调 `recordChange`"，抓不到这条链路。

**修法建议**：`mergeLayerDown` 对含 spektraFilm 的层走**专用分支**——要么 refuse merge（toast，层保持原地），要么把实例按层语义落到"最上层 adjustment 层"（若 base 是 `BackgroundLayer` 则无层可落 → 只能 refuse）。同款审视 `mergeLayerUp`（若有）/`InsertFromJson`/`PastePayload.overwrite` 的 base 落点。新增 AC「含 spektraFilm 的层合并 → 明确结果（refuse 或层内保活），实例计数前后守恒」。

---

## 二、major（8）

### M1 — ε 带三段带宽无推导、高光段方向可疑、低段容忍度过宽、缺 max/分位口径

**定位**：D-SM-9（PLAN:57）、T7'-2（PLAN:224）、AC-T7'-1/T7'-2（PLAN:231-232）。

**亲核事实**：
1. 往返量级自洽：`acescc_encode = (log2(v)+9.72)/17.52`（`ACESccMath.metal:52-57`），e≈0.5 处 f32 半 ulp ≈ 3e-8；`acescc_decode` 的 `dv/de = v·ln2·17.52 ≈ 12.14·v`（`:64-75`）→ 单次往返相对误差 ≈ 4e-7，两次 ≈ 8e-7 ≈ PLAN 的 "~1e-6" ✓。PLAN 的 12× 算式与"两次往返"计数**成立**。
2. 但三段的**分段依据缺失**：往返相对误差在 v > 2^-15 全域是**常数**（≈3.6e-7），与 v 无关；PLAN 却把中段定 5e-4、高光定 2e-3（4 倍差）。唯一可能的放大源是胶片链在 decode 与 encode 之间的一次非线性映射——而密度/印相曲线在**肩部（高光）斜率趋平**、在**趾部/中间调更陡**，即放大应集中在低中段，**高光段需 2e-3 的假设方向相反**（除非另有 SAC/grain 等分段理由，PLAN 未给）。
3. 低段绝对带 2e-5 在阈值处等效 65% 相对误差（2^-15 ≈ 3.05e-5）：`|v| < 2^-15` 内断言几乎无判别力；且该区间的 decode 走 `value < kFloor` 的**线性延伸支**（`ACESccMath.metal:70-72`），与 log 支不同阶，2e-5 是否够由线性支的 f32 累积决定（PLAN 未分段处理）。
4. **无 max / 分位口径**：逐像素比较时单个外推像素即可击穿任何相对带。M3-3 的先例明确用"平滑域筛选"排除外推像素（AGENTS M3-3 golden 门一节，实测 8.7e-5 钉 1e-4）；PLAN 未继承该纪律。且 M3-3 的既有门是 **1e-4**（kernel 级），v2 的中段 5e-4 比既有更松 5 倍——"实测收窄只许紧不许松"的写法无法防止初版即取松端。
5. AC-T7'-2 "超带 = T2' 回炉" 没有定义重试上限/判定样本集（哪张图、哪些像素），执行者无法机检。

**修法建议**：D-SM-9 补推导表（逐段：往返项 + 胶片链局部斜率实测项），分段改为按**胶片链斜率实测**划分（先 T2' 落地后实测 slope 分布再定带），高光段不得宽于中段；逐像素口径改为「≥99.5% 分位 ≤ 带 + max ≤ 10× 带 + 外推像素（|v|>2^8 或密度轴端点）单列」；补一条"实测带必须 ≤ 推导带上界"的机检 AC（防止取松端）。

### M2 — AC-T4'-6「env-off 迁移档走 degradedForUnknownOps」与 M5(a)「注册恒开」直接矛盾

**定位**：§0.2 env 门（PLAN:76）、AC-T1'-2（PLAN:91）、AC-T4'-6（PLAN:165）、M10 回退面（PLAN:24）。

**亲核事实**：`degradedForUnknownOps` 的唯一判据是 `registry.makeBox(opName:) == nil`（`LightamerSidecar.swift:1153`）；`list_iops`/面板/seed 面同理。v2 采 M5(a) = **注册恒开**（`populate` 无条件注册 spektraFilm，PLAN:76/85/91），则 `makeBox("spektraFilm")` 恒非 nil → degrade pass **永不触发**。于是 AC-T4'-6 的三段子句里"走 degradedForUnknownOps（enabled=false + toast）→ 画面退回无胶片"与"重开 env 后实例仍 disabled"**都不成立**：env 缺席时迁移档照常渲染胶片。

**后果**：M10 的"回退面"整段（env 关闭 = 降级 + 不可逆面申报 + pre-convert 备份的理由）在 M5(a) 下失去对象；T4'-6 的 env 门接线（迁移行/面板/菜单隐藏）与"已迁移档 picture 行为"混为一谈。这不是措辞问题——AC 是机检项，写错的 AC 会让执行者去实现一个不存在的降级。

**修法建议**：二选一并写死：(a) 承认"env 只门 UI/写入口，已迁移档在 env off 下照常渲染"（回退面改为"关 env 后新写入不可达，已迁移档继续渲染"，删除 degrade 子句与"仍 disabled"子句）；或 (b) 注册仍恒开但 `SpektraFilmModule.process` 在 env off 时走 blitIdentity（等于降级，但这与"default face 零可见"口径不同源，须另立门）。推荐 (a) + 在 DECISIONS 登记"env 不是回退开关，只是可见性开关"。

### M3 — 渲染入口清单两处前提错误：QuickLook 的 registry 未 populate；编辑器 `.thumbnail` 无 strip 点

**定位**：T6'-3（PLAN:196-200）、AC-T6'-3/T6'-4（PLAN:210-211）、M7 修法（PLAN:21）。

**亲核事实**：
1. **QuickLook**：appex 的 registry = `ModuleRegistry.makeDefault()`（`LightamerQuickLook.swift:36`，**只有终端三件**：`ModuleRegistry.swift:44-58` 直接写三个工厂），appex 全文件**无** `LightamerIOPRegistry.populate` 调用（`grep -rn populate App/Extensions/` 空）。`QuickLookRenderer.preview` 用它 `materializeBoxes`（`:252`），未知 op 直接跳过。→ **在 QL 进程里 spektraFilm 恒为 unknown op**，PLAN 的"QuickLook: include（正确观感）"在当前架构下**不可能成立**（除非同批给 appex 加 populate，那是 QL target 的改动，且会连带启用所有 IOP 模块——观感面大幅变化，须单独裁决）。
2. **编辑器 thumbnail**：`PipeCoordinator.fetchThumbnail` → `renderCurrentChain(resolution: .thumbnail)`（`:2620-2621`）→ `processComposite(instances: chain, layerStack: currentLayerStack, …)`（`:2852-2871`）。spektraFilm 在**层链**里，不在 `instances`；没有任何实例集可"剥"。PLAN 的 strip 点只落在 `SessionThumbnailProvider`（库网格路径，`SessionThumbnailProvider.swift:508-520`），**覆盖不到编辑器自身缩略图**。legacy 时代 `filmTailPolicy(for: .thumbnail) == nil` 使其天然无胶片；module 化后该路径会渲染胶片 → AC-T6'-3「thumbnail run 实例集不含 spektraFilm」对这条路径不可断言。

**修法建议**：QL 面改为两条互斥选项——「P1 不纳入（QL 恒无胶片，与 legacy 一致；DECISIONS 登记）」或「同批给 appex 加 populate + 材料缝，作为独立子任务与 AC」（推荐前者，成本/风险最低）；编辑器 thumbnail 的 strip 点需落在**驱动侧或 layer 物化侧**（如 `LayerCompositeDriver` 增一个 `stripOpNames` 形参，或 `chain`/`layerStack` 在 `.thumbnail` 分派前做副本过滤）——后者要动 driver（非封存，但属 PixelPipe 邻域，须逐 hunk 申报）；AC 按两条路径各写一条。

### M4 — 全局写入面未闭合：预设创建丢层 → 实例落基链；paste reject 无 token 落点

**定位**：D-SM-8（"Copy/Paste 全局 epoch ... typed reject"，PLAN:56）、T6'-7（PLAN:204）、D-SM-11。

**亲核事实**：
1. **预设创建**：`PresetsStore.create(name:kind:category:instances:exportRecipe:)` 的签名**没有 layerStack 形参**（`PresetsStore.swift:212-218`），构造 `LightamerPreset(...)` 时不传 → 恒 nil（`:224-226`）；而 `LightamerPreset.layerStack` 字段**是存在的**（`LightamerPreset.swift:78`，`PresetApplier.makePayload` 也会读它，`PresetApplier.swift:59-68`）。→ **读侧支持、写侧断链**：`createPresetFromCurrent`（`PresetController.swift:142-152`）只能落 `payload.instances`，层链恒丢。`PastePayload.compose` 的 `instances` 由 `sourceEffective`（= `history.effectiveInstances()`，**仅全局项**，`HistoryStack.swift:453`）+ skip 集过滤而来，**层内实例不进 `payload.instances`**（层链只走 `layerStack` 字段，而该字段在写侧恒 nil）。→ 从含 spektraFilm 的文档创建预设 = 静默丢胶片；反过来，若某预设 payload 含 spektraFilm（例如来自旧全局路径），应用到目标档会写进 `document.instances` = **基链**，绕过 D-SM-8 的 reject。
2. **paste_adjustments 的拒绝原因**：`PasteRejectionReason` 是**固定 token 集**（`EditingToolset.swift:771-776`，四个），PLAN 要求"paste→legacy 档 = 拒绝"，但没说 token 名、也没说该表扩容（表注释自称 FIXED）。批量路径 `SessionBatchApplier.apply` 只回 `failedRelPaths`（`SessionBatchApplier.swift:288-295`），拒绝理由在 `pasteFailureReason`（`EditingToolset.swift`）里推导——新语义要从哪里读出来未定。
3. `AdjustmentTransferCatalog.enumerateSnapshot` 走 `LayerStackProjection.rebuild`，层内 spektraFilm 会作为**可迁移行**出现（`isAdjustmentTransferable` 只看 owner==.grade，`AdjustmentTransfer.swift:36-39`），而 `buildPayload` 把它塞进 `layer.chain`（`:215`）+ `records`（`:235`）→ records 集合里也有一份，落到 `PastePayload.instances`。**同一实例同时进 instances 与 layerStack**（既有结构），目标档 overwrite 时 `instances` 那份落基链 → 又是基链 spektraFilm。

**修法建议**：D-SM-8 的写入面清单补三处并各给 AC——(a) 预设创建：含 spektraFilm 时要么拒绝创建（带理由）要么把层结构升级进预设（P2）；(b) `AdjustmentTransferCatalog.buildPayload` 对 spektraFilm 单列（只进 layer.chain，不进 records）；(c) `pasteFailureReason` 增一个固定 token（如 `layerOnlyOp`）并在 schema/文档同步；新增负测「预设/paste 应用后目标档基链无 spektraFilm」。

### M5 — AC-T2'-6 的 RSS 门（ΔRSS ≤ 1.6GB）与 8192MB 运行门不兼容

**定位**：D-SM-12（PLAN:60）、AC-T2'-6（PLAN:119）、T8'-1 贴线定向轮（PLAN:242）。

**亲核事实**：AGENTS「资源监控」节给的标尺是测试宿主 bundle 级 `ru_maxrss` 峰值：IOP 7654MB、IOPParity 5788MB，运行门 `RSS_LIMIT_MB=8192`（`Scripts/test-direct.sh`），且明示「by-design GB 级重测单类自峰 TilingOverlap 7865 / HDR 5913 / QuickLook 4589MB + ~1.4G 框架地板」。若把 SpektraFilm 的 module 路用例放进 IOP 或 IOPP bundle，**基线 7654 + 1.6GB 中间面 = 9254MB → 必然 MEMFAIL**（IOPParity 5788 + 1.6G = 7388，勉强；但 AC-T7'-1 还要跑 CC0 实拍 + 三形态）。

PLAN 的写法是"ΔRSS ≤ 1 张全帧平面 ~1.6GB"作为**探针断言**（默认 skip），但没回答"AC-T7'-1 的桥接测试在哪个 bundle、该 bundle 基线是多少、加 1.6GB 后是否越门"。M9（v1）已提过这一点，v2 只在 T7'-6 写"夹具小平面 + 降采样 CC0；若 MEMFAIL 再降采样"，把交付风险留给执行者临时决策。

**修法建议**：把 `SpektraBridgeParityTests` 落到基线最低的 bundle（查 BUNDLE-MAP 现值；当前 APP/LAYERS 均远低于 IOP），或在 T7' 增一行"先测基线宿主的 `ru_maxrss`，再决定落域"；AC-T2'-6 的 ΔRSS 探针改为**绝对门**（`ru_maxrss ≤ 8192MB`，与脚本同源）而非相对 Δ，避免"基线已 7.6G 时相对门毫无意义"；T8'-1 的贴线定向轮写明"先跑无 spektraFilm 的基线轮取现值"。

### M6 — 层内 `recordChange` reject 与 `commitContinuousEdit(layerScope:)` 的 autoEnable 语义冲突（面板 enable 走错路）

**定位**：D-SM-8（参数写走 `recordLayerChange` / `commitContinuousEdit(layerScope:)`）、T6'-4（面板 enable 改 `addPlacement()` 形态）、AC-T6'-5。

**亲核事实**：`commitContinuousEdit` 有 `autoEnable` 逻辑（`PipeCoordinator.swift:2050-2078`）：`if autoEnable, !effective.enabled { effective.enabled = true }`。`FilmPanelModel` 现有的全部写面都走**文档级** `recordFilmChange`（`FilmPanelModel.swift:396-403` 的 `commit(_:label:)` funnel），其 live/commit trio 走 `beginFilmEdit/setFilmLive/commitFilmEdit`（`PipeCoordinator.swift:1125-1150`），后者调 `editorState?.recordFilmChange(pending, ...)`（`:1140`）——**不经过 D-H1 的 layerScope 腿**。T6'-4 只说"commitFilm 面板调用点切 `recordLayerChange`"，但 live 三段（begin/setLive/commit）的 `setFilmLive` 写的是 **carrier**（`workspace?.setSessionFilmRecord`，`:1127`），而 module 档的 live 值必须写 **layer chain 的 live 投影**（`applyLiveLayerInstance`，`EditorState.swift:1141-1146`）。PLAN 未区分这两条 live 腿。

**后果**：拖拽 tick 时 carrier 被写（对 module 档无意义，且 T4'-5 要求 carrier 缺席）、层链不更新 → 预览不跟手；提交时 `commitFilmEdit` 走 `recordFilmChange` → 若该函数保留（PLAN T3'-2 保留 legacy 编辑面），module 档会写出一个 filmRecord item（污染 M1 的 presence 语义），若被 reject 则拖拽整体失效。

**修法建议**：T6'-4 明确 module 档的三段腿 = `beginContinuousEdit` + `setLiveParams(layerScope:)` + `commitContinuousEdit(label:layerScope:)`（`PipeCoordinator` 已有该形态，见 `:2060-2075` 的 `recordLayerChange` 分支）；`beginFilmEdit/setFilmLive/commitFilmEdit` 明确**仅 legacy 档**使用；`FilmPanelModel` 增"当前档走哪条腿"的单源判定（复用 `hasSpektraFilmInstance`），并给一条 AC「module 档拖拽 tick 不改 carrier、只改层链 live 投影」。

### M7 — 封存面新申报的"2 行 + 1 期望"仍未计入 driver/store 侧改动，且 D-SM-1 的证伪代价被低估

**定位**：§封存面申报表（PLAN:253-268）、结论行（PLAN:268）、D-SM-1（PLAN:49）、AC-T7'-5。

**亲核事实**：
1. **D-SM-1 证伪代价**：PLAN 写"回落 RESEARCH §4.4 缝（PixelPipe 例外 +1 hunk）"。但 RESEARCH §4.4 的缝要求把 `solvedPackHash` 写进 piece 后由 `prepareChain` 折入 levelHash——`prepareChain` 的 levelHash 计算在 `PixelPipe.swift:967-982`，是**主链与层子 run 共用的**；折入一个"运行期才可得"的量会让 `prepareChain` 依赖 process 期的产物，而 `prepareChain` 在 `run()`/`runSub()` **入口**就要算完（`:1076`）。真实修法只能是"目标 box 的参数 hash 由 module 自填"（`commitParams` 里把 statsHash 折进 paramsHash）——但那只在 process 前拿不到 histogram。**结论：D-SM-1 若证伪，回落路径不是"+1 hunk"，而是"cache key 语义重构"**，PLAN 的低估会让执行者在 T7' 撞墙。
2. 封存表仍**未列** `LayerCompositeDriver`（M3 的 thumbnail strip 落点若改驱动即触碰；D-SM-8 的层放置语义依赖 `LayerCompositeSeam.acesccEnvelope` 已在位，本身零改 ✓）、`FilmTailPolicy.swift`（D-SM-2 说"HEAD public init 零新缝"✓，但 B2 的 tags 形参一旦加就触碰该文件）、`FilmPrintBake.swift`（B2 同）、`FilmMaterialStore.swift`（B1 的缝）。这些都不是"2 行 + 1 期望"。

**修法建议**：封存表增「待定行」并区分"P1 申报 vs 依赖 B1/B2 修法"；D-SM-1 的证伪后果重写为"需 re-plan（cache key 语义）"，并把 AC-T7'-5 的负测提前到 **T2'**（process 内一旦产出 payloads 即可断言"同 params 不同 stats ⇒ 平面 key 不同"，不必等到 T7'）。

---

### M8 — D-SM-12「借 `SpectralScratchAllocator` slot」与 spectral 链争用同一 slot → 运行期抛 `alreadyBorrowed`

**定位**：D-SM-12（PLAN:60）、T2'-1 process 步骤（"单中间面（D-SM-12：借 `SpectralScratchAllocator` slot）"，PLAN:107）、AC-T2'-6（"中间面恒 ≤1 张全帧 float32"）。

**亲核事实**：
1. `Slot.claim(_ leg:)` 对不同 `Leg` 值**抛错**（`SpectralScratchAllocator.swift:149-157`），`borrowPlanes` 首行即 `try claim(leg)`（`:164-172`）。
2. `Leg` 枚举只有三值 `spatialPre/grain/stageB2`（`:49-53`），**无 film 值**；新增即 Core 改动（非封存但须申报）。
3. `FilmMethodBox` 已在同一 run 内消费 scratch：`runScratch`/`SpectralGPUPayloads.dispatchFilmChain(..., scratch: runScratch)`（`FilmTailPolicy.swift:353-360, 398-408`），光谱链内部按 stage 借用（`SpectralPayloads.swift` 多处 `scratch:` 形参）。

**后果**：若 `SpektraFilmModule.process` 先借 slot 做 ACEScc 往返中间面、再调 `box.process`（spectral 链内部再借同级或不同级 leg），`claim` 会因 holder 已占而抛 `BorrowError.alreadyBorrowed` → module 档渲染失败（不是降级），且失败点在 GPU 前、易被误判为"材料未解析"。若反之先让 spectral 借、module 后借同一 leg，则 `claim` 幂等放行但**两张平面并发存活**，AC-T2'-6 的"≤1 张全帧"断言反而红。

**修法建议**：D-SM-12 改为「module **自持**一张 run-scoped 中间面（`device.makeTexture` 一次、run 结束释放），不借 `SpectralScratchAllocator`」，并把该平面计入 AC-T2'-6 计数；或（若坚持借）新增独立 `Leg.filmModule` 值 + 明确"借—还"在 `box.process` 前后严格成对（release 在 spectral 借用之前），并给一条"module 档 + spectral 臂 + grain/halation 全开 ⇒ 无 BorrowError"的正测。

---

## 三、minor（10）

| # | 定位 | 问题（亲核） | 修法 |
|---|---|---|---|
| m1 | AC-T1'-1（PLAN:90） | 表述**本身正确**（亲核：`filmicrgb 46.0` 在 `:171`、`lut3d 36.0` 在 `:174`，列表序夹逼成立，文件头 `:20-22` 也明写 lut3d「LISTED out of numeric order」）；风险只在执行者把"列表序"误读为"值域夹逼"——lut3d 的值 36.0 < 46.7，写成值域断言会红。 | 断言补一句限定：「列表索引夹逼（非值域）；值断言只钉 `== 46.7`」，避免歧义。 |
| m2 | T1'-4（PLAN:86） | `CatalogAddFaceTests.swift:224` 的期望是 14 项**字面量数组**（`:224-232`，`["cat02WhiteBalance", … "filmPlacement", "colormatch"]`）；D-SM-11「已有则隐藏」是**运行期过滤**，`gradeScopeEntries()` 仍枚举全部（`EditorState.swift:1008-1019`）→ 该数组要加 `"spektraFilm"` 一项，PLAN 只说"期望更新"未给数（Δ）。 | 写死"14 → 15 项，尾部追加 `spektraFilm`"。 |
| m3 | T1'-2（PLAN:85） | `populate(_:defaultFace:filmModule:)` 加参（M5(a) 下恒 true）——**该参数是死参**（无 false 调用者）。且 `isFilmModuleRequested` 若只在写入口读，`AC-T1'-2` 的"注入式可测"没有注入点（HEAD 的 `isFullFaceRequested` 是 `ProcessInfo` 直读静态属性，测试靠 env 设置，不是注入）。 | 删掉 `filmModule` 参（恒注册不需要）；`isFilmModuleRequested` 改为 `internal static func isFilmModuleRequested(environment: [String: String]) -> Bool` 纯函数 + 生产 wrapper（M2LIB-06 `LibraryLegacyGate` 先例）。 |
| m4 | T6'-6（PLAN:203） | `IopCatalog` 不加行 → `list_iops` 不含 spektraFilm ✓（`DefaultFaceTests.swift:365` 的 19 不动）；但 `apply_params` 的**寻址**不依赖 IopCatalog，而 `projectInstances` 的 `params` 校验走 `defaultRecord(opName:)`（`EditingToolset.swift:1224-1229`）→ 拒绝点若放在 `parseParamOps`（`ParamOp` 已带 opName）即可，PLAN 写"`projectInstances` 首行 op 特例"——**位置错**：`projectInstances` 是 `static func` 收 `[ParamOp]`，放首行会连 `remove: true` 一起拒（应拒的是"写"）。 | 拒绝点落 `applyParamsBody` 的 ops 循环前（或 `parseParamOps` 后），负测覆盖 `remove` 也拒（或明确允许 remove）。 |
| m5 | m4 裁定（PLAN:28） | "`spektraFilm` 走 full-JSON replace 无字段参考，与 payload/geometry/denoise 同待遇"——与 T6'-6 的 **typed reject** 矛盾（后者禁止一切 `apply_params` 写）。二选一。 | 保留 typed reject 时删掉 m4 的"同待遇"类比，改述"因层专属而完全不计入 MCP 面"。 |
| m6 | AC-T8'-1（PLAN:250） | `FilmPlacementModule`/`FilmPlacementKernels.metal`/GradeCatalog 第 19 行 diff 为空 —— **GradeCatalog 第 21 行是新增**（T1'-2），"第 19 行 diff 为空"和"文件有新增行"不冲突但表述含混；`RenderProcessVersion.current == 3` 断言缺"文件级零 diff"（PLAN 的 process 不 bump 应同时机检 `RenderProcess.swift` 的 `current` 行）。 | 拆成三条机检：`RenderProcessVersion.current.rawValue == 3`、`RenderProcess.swift` 的 case 列表未增、FilmPlacement 三件 md5 不变。 |
| m7 | T5'-3（PLAN:182） | PLAN 称不 tile 的双条件是"flag 缺席 + halo 0"，**漏了真正的否决门**：`tileNeeded` 的五门 = `outputFormat == working.pixelFormat` ∧ `resolution == .full` ∧ `tileWorkingSetBytesPerPixel > 0` ∧ `tileHalo > 0` ∧ 面积 > `maxTileWorkingBytes`（`PixelPipe.swift:496-508`）。`tileWorkingSetBytesPerPixel` 默认 0（`IOPModule.swift:158`「0 = never tiled」）才是首道否决，halo 0 只是第二道。 | 断言改为三条并存「`tileWorkingSetBytesPerPixel == 0` ∧ `tileHalo == 0` ∧ `flags ∌ .allowTiling`」+ 一条 `.full` 分辨率下 `process` 调用次数 == 1 的行为断言（AC-T5'-4 的"非 tile 切片"由此机检，不再靠宽度推断）。 |
| m8 | PLAN:35（v2 编号注记） | "v2 重编为 T1'..T8'"——但正文标题仍写 `## T1'`…`## T8'`，changelog 表头写 "§v2 v2 changelog"，`§0.2` 表头写 "（v2）"，编号体系与 v1 混用（如 PLAN:65 表头 `T1'` 但列名 `ΔN（新测试法）`）。此外 PLAN:63-73 的 ΔN 合计 **76** 与各 T 之和 7+10+10+13+4+16+16+0 = 76 ✓（算术自洽）；但 T8' 的基线公式写 "M9-2 收口值 + 本批 ΔN=76 − FilmCardTests 退役 4" = "+72"，而 T6'-5 的退役记在 T6'（−4），**ΔN 合计表未减 4** → 净增 72 而非 76。 | 合计行改 72（或单列 `−4` 行）；补一句"v2 起编号后缀 '，DECISIONS 记录版本对应"。 |

| m9 | T1'-4 既有测试申报（PLAN:86） | 申报只列 3 处（`:95`、`testOwnerMatrix`（`:144`）、`:130-139`）+ CatalogAddFaceTests`:224`。**同文件漏 5 处会红**：`:39` `GradeCatalog.items.count == 20`、`:41-48` 的 `catalogID` 字面量数组（需尾部追加 `"spektraFilm"`）、`:50` `Set(catalogID).count == 20`、`:55` `grade.count == 16`（spektraFilm owner=.grade → 17）、`:193-205` `lightamerGradeRows` **实测 12 项**（acesccIn/filmPlacement/colormatch/acesccOut/colorWheels/cat02WhiteBalance/contrast/white/black/saturation/tint/hls）+ `:228` 断言串仍写 "the eleven LIGHTAMER rows"（**既有口径已过时 1 项**）→ 需加 `("spektraFilm", 46.7)` 成 13 项并改串。 | 申报清单补全为 6 处 + CatalogAddFaceTests 1 处；`ΔN` 附注"改数不计 ΔN，T8' 对账列实报"（PLAN 已有该句，只需补数）。 |
| m10 | D-SM-8「复用 `addPlacement()` 形态」（PLAN:56） | 照抄会落坑：`FilmPanelModel.addPlacement` 取 `layerStack?.adjustmentLayers.last`（`FilmPanelModel.swift:755`），而 `adjustmentLayers` **同时含 RetouchLayer**（`LayerStack.swift:91-93` 的 `addAdjustment(_ layer: any Layer)` + `:35` 声明；`addRetouchLayer` 走同一入口，`EditorState.swift:1268-1282`）；`EditorState.adjustmentLayer(id:)` 只查 `compositeLayers`（`EditorState.swift:679-681`）→ 顶层是修图层时 `addModuleToLayer` 返回 nil，**静默失败**。既有 `addPlacement` 已带此潜伏缺陷（P1 复制即继承）。 | PLAN 措辞改为"最上层 **AdjustmentLayer**"并给实现形：`layerStack?.compositeLayers.last`（或 `adjustmentLayers.compactMap { $0 as? AdjustmentLayer }.last`），无则 `addAdjustmentLayer()`；顺带建议同一实现替换 `addPlacement` 的 `adjustmentLayers.last`（既有缺陷，可挂 P1 顺修或另案，须在 DECISIONS 说明取哪种）。 |

---

## 四、封存面申报复核（亲核）

| 封存件 | PLAN v2 申报 | 亲核结论 |
|---|---|---|
| PixelPipe | `runTerminalTails` 注释 hunk；逻辑零改（M2 包装缝 + M3 双统计） | **条件成立**：`assembleFilmLeg` 为 internal（`PixelPipe.swift:1301`）→ 同 target 新文件 `Film/FilmLegFactory.swift` 可调 ✓；`runFilmLeg` 保留即可满足 T5'-2 ✓。**但 D-SM-1 证伪时的回落不是 +1 hunk**（见 M7①）——申报应改为"条件式 + 证伪即 re-plan"。 |
| V50Order | add-only 一行 46.7 | 成立（`V50Order.swift:171-172` filmicrgb 46.0 之后插行，值唯一 ✓；`testWholeTableCollisionsAreOnlyTheDeclaredExceptions` 的 `{28.5, 41.0}` 不变 ✓）。 |
| GradeCatalog（NodeOwnershipCatalog） | 第 21 行 + E7 期望（19→20 op / 20→21 行） | 计数口径正确 ✓（`:39`/`:50`/`:95`/`:139` 四处对应 items/ids/ops/resolved）；但申报漏 `:55` grade.count 16→17、`:41-48` 字面量数组、`:193-228` lightamerGradeRows（m9）。`needsEnvelope` 零改 ✓（`ACESccInModule.swift:126-128` 走 `GradeCatalog.item != nil`，spektraFilm 入目录后自动包夹——这正是 B1 的正向依据）。 |
| ExportQueueContract | 零 diff（filmTails 保留 legacy 通道） | 成立 ✓（`ExportQueue.swift:266,280-282,502` 全部保留；新档传 nil 走 `ExportInspectorView.swift:1218-1224` 的 per-target 门）。 |
| sidecar schema | 零 diff（v13 不动、零新键） | 成立 ✓（`LightamerSidecar.swift:269` `schemaVersionCurrent = 13`；spektraFilm 走 `ModuleInstance.paramsData` 既有通道）。 |
| HistoryStack / HistoryHash | 零 diff | **条件成立**：D-SM-3 保留 `filmRecord` 解码 ✓；但 `mergeLayerDown` 的 reject 交互（B4）若靠改 `EditorState` 解，HistoryStack 仍零 diff ✓；若靠改 `LayerStack.mergeDown` 返回新 case 则触碰 Core Layers（非封存，但须申报）。 |
| DrtRecord / TerminalTailPolicy / DrtTailAssembly / DrtEotf / Lut3dKernels / 六格式矩阵 / NodeGraphCommand / PipelineDocument | 零 diff | 成立 ✓（T6'-1 的 upstream 自然收敛经 `runTerminalTails:1177` 的 `levelHash[topEnabledPosition]`，filmTail 为 nil 时不覆盖 ✓）。 |
| **未申报但会被 B1/B2/M3 触碰** | — | `FilmTailPolicy.swift`（B2 的 tags 形参）、`FilmPrintBake.swift`（B2）、`FilmMaterialStore.swift`（B1 的缝）、`LayerCompositeDriver.swift`（M3 的 thumbnail strip 若走驱动）、`SpektraBridgeParityTests` 落域（M5）。**五项须在终表增行**，否则"2 行 + 1 期望"是**不诚实**的收窄。 |
| Phase 8 禁改面 | `SessionThumbnailRenderer.swift` 零触 | 成立 ✓（PLAN 明确 strip 落 provider）；但编辑器 thumbnail 路径另有 strip 缺口（M3②）。 |

**结论**：v2 的收窄**方向成立但不完整**——"实质 2 行 + 1 期望"的前提是 B1/B2 的缝落在**新文件**内；B1 需 Core 新缝（可新文件）、B2 需改 `FilmPrintBake` 两函数签名（既有文件），故终表至少 "+2 文件签名 + 1 Core 新缝"。

---

## 五、新引入面（D-SM-8..12）风险

| 判定 | 新风险 | 评估 |
|---|---|---|
| D-SM-8 层专属 + 全作用域 presence | ①**谓词落点未定**：T3'-1 写"WorkspaceModel 持有 editorState/history/layerStack 读面——若跨层不可读则落 PipeCoordinator"。亲核：`WorkspaceModel` **无** editorState 引用（`grep editorState WorkspaceModel.swift` 命中的只有 `pipeCoordinator` 弱引用，`:206`），只有 `PipeCoordinator` 持有 `private weak var editorState`（`:142`）。→ 谓词**必须**落 `PipeCoordinator`，PLAN 的"SUMMARY 实报落点"是把架构决策留给执行者。 | major 级歧义，已并入 M4 语境；建议 T3'-1 直接钉 `PipeCoordinator`。 |
| | ②`effectiveInstances(layer:)` 需 `AdjustmentLayer` 实例（`ModuleRegistry.swift:132`）→ 遍历 `layerStack.compositeLayers` 即可，不需 registry（`HistoryStack.effectiveChain(layer.chain)` 纯值）；PLAN 写"各 AdjustmentLayer `ModuleRegistry.effectiveInstances(layer:)`"在 Core 侧 `ModuleRegistry` 是 **actor**（`ModuleRegistry.swift:27`）→ 该调用要 `await`，放进 MainActor 的 sync 谓词里不成立。 | 落点必须走 `HistoryStack.effectiveChain`（pure，`HistoryStack.swift:481`），或拆 async 谓词 + 缓存。属 blocking 邻域的可执行性瑕疵，已并入 M4。 |
| D-SM-9 ε 带 | 边界值 2^-15/1 的选取无依据（M1） | major（已计） |
| D-SM-10 sync 门控 | 谓词在 sync 腿被调用（`syncFilmCarrierWithHistory` 是 sync func，`PipeCoordinator.swift:1116`）→ 若谓词为 async（见上）则该腿要改 async 或走缓存；`versionActionDidChange` 本就是 async ✓ | minor（并入 M4 的落点裁定） |
| D-SM-11 单实例 | add 菜单"已有则隐藏"要求 `gradeScopeEntries`（`static` 纯函数，`EditorState.swift:1008`）读到 presence → static 方法无法读实例状态，须改为实例方法或参数注入（`addFaceEntries` 已是实例方法 `:995`，可下传）；PLAN 未说。 | minor |
| D-SM-12 中间面复用 | "借 `SpectralScratchAllocator` slot"：`Slot.borrowPlanes(_:device:count:width:height:pixelFormat:)` 是 public（`SpectralScratchAllocator.swift:164-172`），但 `Leg` 枚举只有 `spatialPre/grain/stageB2` 三值（`:49-53`）→ 新增第四 leg 值 = Core 改动（非封存，须申报）；且 `FilmMethodBox` 的 `runScratch` 已占同一 slot（`FilmTailPolicy.swift:353`）→ **module 若借同一 slot，spectral 链内部再 borrow 会撞 `alreadyBorrowed`**（`borrowPlanes` 的 `claim` 对不同 leg 抛错，`:149-157`）。 | **major 级机制冲突**——建议 AC-T2'-6 增"同 run 内 scratch 不重入（或 module 自建 slot）"，并把 D-SM-12 的"借 slot"改为"module 侧持自有中间面（≤1 张）"以免与 spectral 链争用。 |
| ΔN 76 可核性 | 各 T 分项给到法级（7/10/10/13/4/16/16/0）✓；T6' 16 = 3+2+4+2+3+2 ✓、T7' 16 = 10+2+2+2 ✓、T4' 13 = 5+4+2+2 ✓ 三项可逐条对上。T2' 的 10 枚举写「1-1/2-2/2-4/2-5 各 1、2-3 md5 双臂 2、2-6 分配 1 + RSS 探针 1 + 工厂透传 2」——**`1-1` 不对应任何 T2' AC**（T2' AC 编号是 2-1..2-6），按 AC 数（6 条，其中 2-3 与 2-6 各 2 法 = 8）+ 工厂透传 2 = 10 **可达**，只是枚举笔误。T1' 7 = 「V50Order +1、RegistryFilmModuleTests 5、E7 +1」= 7 ✓。**唯一实质问题是合计未减 FilmCardTests −4**（见 m8）。 | minor：T2' 枚举把 `1-1` 改 `2-1`；合计行 76 → 72。 |

---

## 六、replan 闭合清单（回注 omp）

**必修（blocking）**
1. **B1**：立 Core 材料解析缝（非封存新文件，`FilmMaterialSeam` 形），`SpektraFilmModule`/`FilmLegFactory` 经缝取 `(film, paper, pairHash)`；AC「store 注入 → payloads 非 nil」「store 缺席 → blitIdentity + toast」。
2. **B2**：grade/filter/reversal 三项在 module 路的供给路径钉死（形参显式传入 或 TaskLocal 门改）；`SpectralPrintBake.tables/solveSpectral` 的签名变更逐条申报；AC「三形态 module vs legacy ε 带」。
3. **B3**：`runProcessMigration` 的 guard + marker 三支同批改（T4' 增编辑点与 AC）。
4. **B4**：`mergeLayerDown` 对含 spektraFilm 的层走 refuse 或层内保活；同时审 `mergeLayerUp`/`InsertFromJson`/overwrite-paste 的 base 落点；AC「实例计数前后守恒」。

**必修（major）**
5. M1 ε 带推导表 + 分段依据 + 分位/max/外推口径 + "实测带 ≤ 推导上界"AC。
6. M2 env-off 回退语义二选一（推荐"env 只是可见性开关"），删/改 AC-T4'-6 的 degrade 子句。
7. M3 QuickLook 裁定（推荐 P1 不纳入）+ 编辑器 thumbnail 的真正 strip 落点 + 两路径各一条 AC。
8. M4 预设创建/AdjustmentTransfer payload/paste reject token 三处闭合 + 负测。
9. M5 桥接测试落域按基线选（非 IOP/IOPP 优先）+ AC-T2'-6 改绝对 `ru_maxrss ≤ 8192MB`。
10. M6 面板 live 三段腿钉 layerScope 形态；`beginFilmEdit/setFilmLive/commitFilmEdit` 限定 legacy。
11. M7 封存表增五行（待定行）+ D-SM-1 证伪代价改写 + AC-T7'-5 提前到 T2'。
12. M8 D-SM-12 改 module 自持中间面（或 `Leg.filmModule` + 严格成对）。

**随修（minor）**
13. m1..m10 逐条落 PLAN（重点：m9 的测试申报 6 处、m10 的 `adjustmentLayers.last` 陷阱、m8 的 ΔN 76→72、m7 的 tile 三条件）。

**复审节点**
14. 修后重走本 lane（建议：B1-B4 全核 + M1/M2/M3/M8 核 + 其余抽核）。

---

## 七、验收自查

- [x] 只读：零 commit / 零构建 / 零测试；唯一产出 = 本文件（chunked 追加 6 段，每段落盘后 `wc -c` + U+FFFD 自检 = 0）
- [x] 六必核逐条判定（§结论头表 + §一/§二/§三）；必核项均给「已消解 / 部分消解 / 未消解」+ PLAN 定位
- [x] 每 finding 带 PLAN 章节定位 + HEAD 证据（file:line）+ 修法建议；未修改 PLAN
- [x] 抽查余项（v1 的 M4/M5/M7/M8/M9/M10 + 9 minor → 本报告实计 M4..M8 + 10 minor）；新引入面 §五（D-SM-8..12）+ ΔN 可核性
- [x] 结论头 `FAIL / 4 blocking + 8 major + 10 minor`；正文中文，标识符 / file:line 保持原文

### 亲核心证抽查（本轮 ≥3 个关键判定）

| # | PLAN 判定 | 结果 | 证据 |
|---|---|---|---|
| K1 | D-SM-8「复用 `addPlacement()` 形态」可得层内放置 + ACEScc 包夹 | **PASS（形态）/ 有陷阱（m10）** | `addPlacement` = `layerStack.adjustmentLayers.last` → 无则 `addAdjustmentLayer()` → `addModuleToLayer`（`FilmPanelModel.swift:751-765`）；包夹只作用 adjustment 层子 run（`LayerCompositeDriver.swift:396-398`）；但 `adjustmentLayers` 含 RetouchLayer（`LayerStack.swift:91-93, 35`）而 `adjustmentLayer(id:)` 只查 `compositeLayers`（`EditorState.swift:679-681`）→ 顶层是修图层时静默 nil。 |
| K2 | D-SM-8「`ModuleRegistry.effectiveInstances(layer:)` 供谓词」可同步调用 | **FAIL** | `ModuleRegistry` 是 `public actor`（`ModuleRegistry.swift:27`）；`effectiveInstances(layer:)`（`:132`）为 actor 方法 → 需 `await`。纯值替代 = `HistoryStack.effectiveChain(layer.chain)`（`HistoryStack.swift:481`，static 非隔离）。 |
| K3 | D-SM-2「工厂只差访问级」 | **FAIL（差材料）** | `assembleFilmLeg(record:film:paper:materialPairHash:…)`（`PixelPipe.swift:1301-1305`）必须 film/paper；Core/IOP 无 store 持有者（`FilmMaterialStore` 无 shared，`LightamerIOP` 零 `FilmProfile` 引用）→ 见 B1。 |
| K4 | T6'-3「QuickLook include」可达成 | **FAIL** | appex registry = `ModuleRegistry.makeDefault()`（`LightamerQuickLook.swift:36`，仅三件），无 `populate`（全 appex grep 空）→ spektraFilm 恒 unknown op，`materializeBoxes` 跳过（`QuickLookRenderer.swift:252`）。 |
| K5 | AC-T4'-6「env-off 走 degradedForUnknownOps」 | **FAIL** | M5(a) 注册恒开 → `makeBox` 恒非 nil → degrade 判据（`LightamerSidecar.swift:1153`）永不成立。 |
