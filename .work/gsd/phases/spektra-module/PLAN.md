# 光谱核 module 化 P1 执行计划（spektra-module PLAN v4，2026-11-04）

> 基线 HEAD（亲核）：`0d7d0e90 docs(sm): plan review v3`
> v3（64KB）在册同 HEAD，经第三轮评审 FAIL——本 v4 逐条消解。
> 修法正本 = `SM-PLAN-REVIEW-V3.md`（§一/§二/§三/§五；R-B1/R-B2/R-M1..R-M5/r-m1..r-m9 为 v3 新 finding）+ `SM-PLAN-REVIEW-V2.md`（v2 未消解项原始出处）+ `SM-PLAN-REVIEW.md`（v1）。
> **用户裁决 = `DECISIONS.md` D-SM-0（五条生命线全量，禁降档）——本 PLAN 任一条款与 D-SM-0 冲突时以 D-SM-0 为准。**
> 设计正本 = `RESEARCH.md`。范围 = **P1 only**：module 化不改核；process 不 bump；sidecar 零新键零 bump。等价口径 = **ε 带**（D-SM-9R：方法 + 上界 + 实测钉死）。
> **本轮方法**：v3「先缝验证后写设计」延续；R-B2 类计数申报一律 HEAD grep 实数，凡写「零改」必须带 grep 证据。任务编号沿用 T1'..T8'。

## §v4 changelog（三轮评审全部 finding → 消解位置 / 显式不解）

三态：消解位置 / 本轮不解挂 P2（须 DECISIONS 登记 + 用户批准）/ 本轮不解注记（HEAD 无此面或既有语义保留，DECISIONS 登记）。v1/v2 已消解项只列继承行。

### v3 blocking（2，本轮核心）

| # | 消解 | 位置 |
|---|---|---|
| R-B1 appex 注册降级 | (甲) 补齐生命线 4：QL 进程独立装配（registry 全量 populate + `FilmMaterialSeam` 装闭包 + per-QL-run tags 供给）纳入 P1；v3「P2 立项」判撤销；AC-T6'-4 反向断言删除，改「QL 输出 == 导出输出（ε 带）」正测 | D-SM-15、S-QL、T6'-3/AC-T6'-4/13 |
| R-B2 测试改写不全 | T1' 编辑点 4 重写为两批：GradeCatalogTests 10 条（补 `:100-109 newSevenOps` 白名单 + `:139 resolved` 19→20；删「`:130-139` E7 零改」错误表述）+ V50OrderTests 2 条（`:24` 108→109、`:284-293 nativeRows` 追加）；全仓计数 grep 扫一轮结论附后；新增 AC-T1'-5「T1' 后 bundle 全绿零未申报红」 | T1'-4、AC-T1'-1/3/5 |

### v3 major（5）

| # | 消解 | 位置 |
|---|---|---|
| R-M1 兄弟图 tags | (甲) 修：`legTags` per-target 从各自 sidecar 的 spektraFilm record 经 `resolveLegTags` 解析（供给点 = `makeRunAssembly` + `ExportRenderer.readDocument` 既有读面） | D-SM-14 增补、T6'-2、AC-T6'-2 |
| R-M2 预设拒绝读面 | 判据改层面读取：`createPresetFromCurrent` 前检查 `editorState.layerStack`（`hasSpektraFilmInstance` 单源谓词）→ typed 拒绝 `PresetError.layerOnlyOpPresent`；`makePayload` 防御过滤为第二道 | T6'-7(a)、AC-T6'-9 |
| R-M3 落域/RSS 门 | `SpektraFilmTests` 落 **LAYERS**（944MB 基线）；100MP 只留探针轮，默认套件中平面（≤2K）+ 分配计数；基线轮提前到 T2' 开头（T2'-0） | T2'-0/ΔN、AC-T2'-6、T8'-1 |
| R-M4 nil 无原因 | 推荐 (甲)：`mergeLayerDown` 开头预检（toast + return）+ `LayerStack.mergeDown` refuse hunk 保留为纵深防御；`MergeDownOutcome` 枚举零改 | T3'-3、AC-T3'-6 |
| R-M5 封存漏行 | 封存表增第 16 行 `LayerStack.mergeDown`；T3'「封存面：无」改「1 hunk」；结论句「实质 2 行」改「实质 3 行」 | 封存表、T3' |

### v3 minor（9）

| # | 消解 | 位置 |
|---|---|---|
| r-m1 ΔN 算术 | T2' 14→15；合计 96，净增 96−4=**92**（本 v4 再加 R-B1/R-M1/R-M2 新法，见 §0.2 实数） | §0.2、T2'、T8' |
| r-m2 film 文件数 | 「47」改「按 BUNDLE-MAP 的 film/spectral 行集为准，不写死数字」（HEAD 实测 49，`ls \| grep` 证据） | T7'-4 |
| r-m3 AC-T1'-1 | 补「`V50OrderTests` 两处计数断言同批改」 | AC-T1'-1 |
| r-m4 strip 措辞 | 「records 过滤」改「`runtimeLayers` 各层 `chain` 过滤 `opName == spektraFilm`」 | T6'-3 |
| r-m5 reject 限定 | `recordChange` reject 措辞补「仅 `opName == spektraFilm`，film 语义 op（grain 等）不受影响」 | T3'-2 |
| r-m6 logger 断言 | 钉死行为断言：输出逐位 == 输入 + 不 crash + 不 throw；logger 不断言 | AC-T2'-8 |
| r-m7 cancel 键 | 点名复用 `alert_cancel`（en Cancel / zh 取消，在册中性键） | T4'-4、AC-T8'-2 |
| r-m8 走查 ±10% | 删耗时子句，改目视项「grid 缩略图与编辑器同档观感一致（都无胶片）」 | T8'-4 |
| r-m9 计数槽 | AC-T2'-6 拆两条（自持面计数 ≤1 + ΔRSS 参考）；计数槽照 `FilmStatsSnapshot.last` advisory 先例申报为测试缝；D-SM-12R 补 mix 面注记 | AC-T2'-6、D-SM-12R |

### v2/v1 继承（v3 已消解，v4 不重述）

v2 B1/B3/B4 + M1/M2/M6/M7 + v1 全部技术残余 = v3 修法继承（见 v3 changelog 存档行，DECISIONS 记继承链）；v2 B2/M3/M4/M5 的「部分消解」尾巴 = 本轮 R-M1/R-B1/R-M2/R-M3 收口。

## D-SM-0 五条生命线落实表（v4 文首登记；R-B1 修法要求）

| # | 生命线（DECISIONS 原文） | 落实任务 | AC | 状态 |
|---|---|---|---|---|
| 1 | 材料解析缝：FilmMaterialStore 下沉/注入到 IOP module 可达面 | T2'-1（`FilmMaterialSeam` 新缝）+ T4'-1（`attachFilmStore` 安装点） | AC-T2'-7/8（注入正测/缺席负测） | 全量 |
| 2 | requestTags 供给：三处 TaskLocal 消费在 module 路有供给点 | T4'-1（`filmLegRequestTags` 门改 + `resolveLegTags` 纯函数）+ T6'-2（导出 per-target 供给，R-M1） | AC-T4'-2（module 档 tags 非 nil）/ AC-T6'-2（双臂）/ AC-T7'-7（三形态等价） | 全量 |
| 3 | merge-down 语义：`.mergedIntoBase` × reject 蒸发有显式处置 | T3'-3（`mergeDown` refuse + `mergeLayerDown` 预检 toast，R-M4 钉形） | AC-T3'-6（refuse/守恒/redo） | 全量 |
| 4 | appex 注册：QuickLook registry 加 populate，spektraFilm 非 unknown op | T6'-3（QL 进程独立装配：populate + material seam + tags，D-SM-15） | AC-T6'-4（QL==导出 ε 带）/ AC-T6'-13（unknownOps 不含 spektraFilm） | 全量（v3「P2 立项」撤销） |
| 5 | scratch 分配：Leg 三值争槽 + RSS 8192 门 | T2'-1（自持 run-scoped 中间面，不借 allocator）+ T2'-0（基线轮提前） | AC-T2'-6（计数≤1 + 绝对门）/ AC-T2'-11（无 BorrowError）/ AC-T8'-1（MEMFAIL 0） | 全量 |

## §缝验证（每条新缝的 HEAD 证据；基线 `0d7d0e90`）

v3 七节（S-B1..S-B4/S-M3/S-M4/S-M6/S-DSM11）经 v3 评审逐条复核属实，v4 继承不重述；本轮新增 S-QL（R-B1）+ S-RM1（R-M1）+ S-RM2（R-M2）+ S-RM4（R-M4）四节。凡写「零改」处均带 grep 证据（R-B2 教训）。

### S-QL appex 独立装配缝（→ D-SM-15 新建；R-B1）

| # | HEAD 事实 | 证据 |
|---|---|---|
| S-QL-1 | appex target 已依赖 Core+IOP：`LightamerQuickLook` dependencies = `.target(LightamerCore)` + `.target(LightamerIOP)`（host 携带 Frameworks 拷贝，appex 经 runpath 解析）→ 「appex 不能引用 IOP」的不可行理由**不成立**，`LightamerIOPRegistry.populate` 在 QL 进程可达 | `Project.swift:270-274` |
| S-QL-2 | QL 进程 registry 现状 = 终端三件：`Env.registry = ModuleRegistry.makeDefault()`；appex 全目录 `grep populate` **零命中** → spektraFilm 在 QL 恒 unknown op | `LightamerQuickLook.swift:34-37`；appex grep 空 |
| S-QL-3 | `populate` 为 `public static func populate(_:defaultFace:)` async（`defaultFace` 有缺省）→ appex 可 `await LightamerIOPRegistry.populate(registry)` 全量装配；`FilmStatsSeam.histogram` 同调用顺带安装（直方图供给同解） | `Registry.swift:69-93` |
| S-QL-4 | 反证坐实：`QuickLookRenderer.preview/renderedPlane` 第 4 步重建 `layerStack`（`document?.layerStack` → `makeLayers()` → `addAdjustment`）进 `processComposite` → 不 strip 则 QL 渲其它 grade op 而独跳胶片 = 新的不一致；QL 与导出共用 `ExportChainBuilder.exportChain` + `materializeBoxes`（同一 builder 语义分叉无单源） | `QuickLookRenderer.swift:252,270-289`；`ExportChainBuilder.swift` 同 builder |
| S-QL-5 | 材料 store 可在 QL 进程独立构建：`FilmMaterialStore.init(profilesDirectories:)` public throwing（Core 内）；主进程装配先例 = `Bundle.main.resourceURL` 取 `FilmProfiles/profiles` + `FilmProfilesBW/profiles`（QL 进程的 `Bundle.main` = appex bundle，需经 host bundle 取 resource——装配代码须写「appex bundle → host Frameworks/Resources」路径分支并以落盘测试验证） | `FilmMaterialStore.swift:54-64`；`LightamerShell.swift:949-955`；`Project.swift:187/193` folder reference |
| S-QL-6 | QL 进程装配点唯一：`Env` 私有枚举（metal + registry 两个 static let）→ 加第三 static（material store + seam 安装）+ registry 改 populate 后实例；appex 红线「ZERO business logic」守住（装配 = glue，渲染仍走 `QuickLookRenderer` Core 面） | `LightamerQuickLook.swift:8-37` |

**验证结论**：appex 侧 populate + material seam 在 HEAD 架构下**无不可行项**（依赖已声明、符号全 public、装配点唯一）→ 走修法 (甲) 补齐生命线 4，不申请降档。唯一待执行期验证 = appex→host resource 路径（AC-T6'-13 覆盖）。

### S-RM1 导出兄弟图 tags 供给缝（→ D-SM-14 增补；R-M1 修法甲）

| # | HEAD 事实 | 证据 |
|---|---|---|
| S-RM1-1 | per-target 门现状：`filmTails`/`legTags` 均为 `targets.map { url == loaded ? loaded值 : nil }`（loaded 位填 `filmLegRequestTags(for: .export)`，兄弟位恒 nil）→ legacy 时代兄弟图 `filmTail=nil` 无胶片，无 tags 一致 | `ExportInspectorView.swift:1217-1224`（filmTails 门 + legTags 门同形） |
| S-RM1-2 | module 化后兄弟图必渲胶片：`ExportRenderer` 第 3 步对**每 target** `readDocument(imageURL:)`（盘 sidecar 真相）→ 第 4 步重建各自 `layerStack`（`:491-499`）→ `processComposite` → 层内 spektraFilm（46.7 box）在链上；但 `$requestTags=nil` → `tables` 走 absent 中性（BW 显式 grade/reversal 丢） | `ExportRenderer.swift:405-427,491-499,540-543`；`FilmPrintBake.swift:555-556,567-573` |
| S-RM1-3 | 供给读面存在：`readDocument` 为 `public static`（SessionBatchApplier 同款读法，QL 亦复用 `:243-245`）→ per-target 的 `document.layerStack` 可解出各自 spektraFilm 实例 record；`resolveLegTags(record:store:)`（D-SM-14 纯函数）record 来源换 per-target 链即可，无新机制 | `ExportRenderer.swift:852-861`；`QuickLookRenderer.swift:243` |
| S-RM1-4 | store 可达：`resolveLegTags` 需 `FilmMaterialStore`（grade/filter 解析）+ rms memo；导出装配在 App 进程（`makeRunAssembly`），`pipeCoordinator.filmStore` 同进程可读 → per-target 解析不跨进程 | `PipeCoordinator.swift:1050-1063`（store 持有）；`filmLegRequestTags:881-919`（解析体出体来源） |

**验证结论**：走修法 (甲)——`legTags` 改 per-target 解析（loaded 位维持旧路，兄弟位从各自 sidecar record 解析）。`filmTails` 维持 loaded-only（legacy 档兄弟图本就无腿，D-SM-4 通道不动）。

### S-RM2 预设拒绝判据读面（→ T6'-7(a) 改判据；R-M2）

| # | HEAD 事实 | 证据 |
|---|---|---|
| S-RM2-1 | `createPresetFromCurrent` 输入 = `composeCurrent?()` 产 `PastePayload`（guard 空即 `emptyComposition`），后调 `PresetsStore.create(name:kind:category:instances:)`（签名无 layerStack，`:212-218`）→ payload 层内 spektraFilm 不进 `instances`（`effectiveInstances()` 仅全局项） | `PresetController.swift:136-149`；`PresetsStore.swift:212-226`；`HistoryStack.swift:437-466` |
| S-RM2-2 | 层面读面存在：`composeCurrent` 闭包组装点同文件可读 `editorState.layerStack`（闭包内已读 `editorState.loadedImageURL` + `editorState.layerStack` 组 `layerRecord`）→ 判据前检查 `layerStack.compositeLayers` 各 chain opName（复用 D-SM-8R `hasSpektraFilmInstance` 单源谓词）可达 | `LightamerShell.swift:653-666`（闭包组装）；`PresetController.swift:54`（缝形态 D-03b） |
| S-RM2-3 | typed 错误有槽：`PresetError` 为 Core 侧 `public enum`（`emptyName/notFound/corruptPreset/invalidPreset/...`）→ 增 `layerOnlyOpPresent` case 为 additive（Core Presets 非封存） | `PresetsStore.swift:29-44` |

**验证结论**：判据改层面读取（payload 无关），`makePayload` 防御过滤降为第二道。

### S-RM4 merge refuse 原因区分（→ T3'-3 钉形；R-M4 修法甲）

| # | HEAD 事实 | 证据 |
|---|---|---|
| S-RM4-1 | nil 四来源共享：`mergeDown` 返回 `MergeDownOutcome?`（enum 仅 `.mergedIntoLayer/.mergedIntoBase` 两 case，**internal**——`LayerStack.swift:52 public extension` 内第 76 行 `enum` 无 public）；nil 来源 = 无此 id（`:162-164`）/ retouch（`:169-172`）/ 下层非 chain（`:182-187`）/ 新增 spektraFilm refuse | `LayerStack.swift:52-88,161-193` |
| S-RM4-2 | 调用方无原因可读：`mergeLayerDown` 仅 `guard let outcome = stack.mergeDown(id:) else { return }`（`:741`）→ nil 分支直接 return | `EditorState.swift:738-751`（`App/Sources/Lightamer/State/EditorState.swift`） |
| S-RM4-3 | 预检读面存在：调用方同文件可读 `layerStack.adjustmentLayers` + `HistoryStack.effectiveChain`（static 非隔离，`:481`）→ 预检 `target chain 含 spektraFilm → toast + return（不调 mergeDown）` 零 Core 改动 | `EditorState.swift:738-742`；`HistoryStack.swift:481` |
| S-RM4-4 | 枚举改动代价：加 case 要改 Core 公开类型 + `LayerCoreTests:126/149/339` 三处消费点（`:339` 为 `XCTAssertNil` retouch refuse 断言，枚举改形不影响该行但新增 case 需新法）→ 修法甲（预检 + 纵深防御）零枚举改动更优 | `LayerCoreTests.swift:126,149,339` |

**验证结论**：钉修法 (甲)——调用方预检（toast 面）+ `mergeDown` 内 refuse hunk（数据面纵深防御）；`MergeDownOutcome` 零改（grep `case refused` 零命中为机检）。

## §0 裁决冻结（v3 继承 + v4 勘误注）

- OQ-1(a)..OQ-6(a)：v3 六条继承（见 v3 §0 存档；D-SM-0 新增为最高优先，冲突时 OQ 让路）。
- **v4 注**：v3 T6'-3「QuickLook P1 不纳入」判**撤销**（与 D-SM-0 第 4 条冲突）；v3「`:130-139` E7 零改」表述**撤销**（与 HEAD `:139` 事实相反）；v3 M4(a)「payload 含 spektraFilm 拒绝」判据**改层面读取**。
- **v4 基线 = `0d7d0e90`**（md5/golden 在执行 HEAD 重钉，m1 类推）。

## §0.1 判定（v4：D-SM-8R/9R/12R/13/14 继承 + D-SM-15/16 新增）

v3 D-SM-8R/9R/12R/13/14 全文继承（v3 §0.1 存档）；本轮两处增补 + 两个新判定：

| # | 判定 | 内容 |
|---|---|---|
| D-SM-12R+ | r-m9 增补 | mix 面（strength<1）属 box 内部、legacy 同款，不计入自持账面数；计数槽 = `SpektraFilmModule.liveSurfaceCount` advisory 槽（`FilmStatsSnapshot.last` 先例，`Registry.swift:812` 同款 `public enum` + 可写 slot），**显式申报为测试缝**（生产读零消费者，grep 机检）。 |
| D-SM-14+ | R-M1 增补 | `legTags` per-target 化：loaded 位 = `resolveLegTags(loadedRecord:store:)`（旧路）；兄弟位 = `resolveLegTags(sidecarRecord:store:)`（record 取自各 target `readDocument().layerStack` 内 spektraFilm 实例 params，无实例 = nil）。`filmTails` 维持 loaded-only（D-SM-4 legacy 通道不动）。 |
| D-SM-15 | **appex 独立装配**（v4 新增，R-B1） | QL 进程 `Env` 增三件：① registry 改 `await LightamerIOPRegistry.populate(registry)` 全量装配（含 spektraFilm 恒注册行 + `FilmStatsSeam` 安装）；② `FilmMaterialSeam` 装闭包（store = QL 进程自建 `FilmMaterialStore`，resource 路径经 host bundle 解析）；③ tags 供给 = QL run 内 `resolveLegTags` 等价解析（record 取自 QL `document.layerStack` 内实例；QL Core 侧无 App 纯函数 → Core 内对等小函数或 TaskLocal 直装，执行 lane 二选一 SUMMARY 实报）。`QuickLookRenderer` 渲染体零改（registry 入参已存在）。 |
| D-SM-16 | **QL/导出 parity 口径**（v4 新增，R-B1） | QL preview（2560 fit）与导出同档（同尺寸）在 module 档逐像素 ε 带等价（D-SM-9R 口径复用；QL 长边 2560 vs 导出长边取同值对照）。legacy 档 QL 行为逐位不变（无实例 = 无胶片 = 旧观感）。 |

## §0.2 任务总览（v4，ΔN 实数）

| T | 标题 | Δ文件 | ΔN（新测试法） | 封存面 |
|---|---|---|---|---|
| T1' | 注册骨架：V50Order + GradeCatalog + Registry（恒注册）+ env 纯函数 | +1∕~4 | 7 | V50Order、GradeCatalog |
| T2' | SpektraFilmModule 本体 + ACEScc 往返臂 + FilmLegFactory 包装缝 + FilmMaterialSeam（落域 LAYERS） | +3∕~2 | 15 | —（delegate 形态）|
| T3' | 谓词单源 + sync 腿门控 + merge refuse（预检钉形）+ sidecar 键 legacy 只读 | ~6 | 14 | LayerStack.mergeDown 1 hunk |
| T4' | 双轨读判别门 + 迁移行 + 动作面 guard + 备份 + env 门接线 | ~8 | 15 | PixelPipe（legacy 门 hunk→注释）|
| T5' | 求解链不动验证 + tile 政策钉死 | ~1 | 4 | — |
| T6' | 下游面：DRT/导出 per-target tags/渲染入口（QL 装配）/面板换锚/Film 卡/MCP 拒绝/写入面三修 | ~15 | 28 | PixelPipe（upstream 语义零 hunk）|
| T7' | ε 带桥接测试 + 蒙版 AC + golden 迁移 + 落域 LAYERS | +1∕~6 | 18 | — |
| T8' | 收口：贴线定向轮 + 全套 + 走查 + SUMMARY/DECISIONS + 申报终表 | docs | 0 | 终表复核 |
| − | FilmCardTests 退役 | −1 | **−4** | — |
| 合计 | | +5 新源 / ~42 触碰 | **净增 97**（101 − 4） | PixelPipe/V50Order/GradeCatalog/LayerStack 四件 |

v3→v4 ΔN 增量说明（r-m1 实数交付）：T2' 14→15（+1，r-m1 纠算）、T3' 13→14（+1，R-M4 预检 toast 法）、T6' 24→28（+4：R-B1 QL 装配 2 + R-M1 兄弟图 tags 1 + R-M2 层面拒绝 1）。v3 合计 95→96 纠算后再 +5 = **101**，净增 101−4 = **97**。

**登记纪律**：每任务各自同批登记 Project.swift + BUNDLE-MAP + `tuist generate` 末动作（L041/M2-4-0 E2）。
**env 门** `LIGHTAMER_FILM_MODULE=1` 默认 off：注册恒开，env 只门 UI/迁移/写入口（M2 选 a；已迁移档 env-off 照常渲染）。

## T1' 注册骨架（V50Order + GradeCatalog + Registry 恒注册）

目标：46.7 槽位与目录行就位；注册恒开，env 只门写入口/UI。

编辑点：
1. `V50Order.swift`：`("filmicrgb", 46.0)` 后插入 `("spektraFilm", 46.7)` verbatim 行。add-only，一行。
2. `NodeOwnershipCatalog.swift`：GradeCatalog 新增第 21 行 `spektraFilm`（owner .grade；`identityJSON = json(of: SpektraFilmModule.Params())`；`panelExposures` 复用 `film_*` 15 键 stem——零新键）。E7 口径：唯一 op 19→20、行 20→21。
3. `Registry.swift`：恒注册 spektraFilm 工厂行；`defaultFaceDisabledOpNames` 不加；`editingDefaultInstances` 不 seed。新增 `isFilmModuleRequested(environment: [String: String]) -> Bool` 纯函数（`LibraryLegacyGate` 先例）+ 生产 wrapper；**删 `filmModule` 死参**。
4. 既有测试改写（R-B2 重写：两批共 12 条（+ add-face 1 法另计），逐条 file:line + 现值→新值 + 改写方式）：
   - (i) `GradeCatalogTests.swift` 10 条：`:39` count 20→21；`:41-48` 字面量数组尾部追加 `"spektraFilm"`；`:50` Set count 20→21；`:55` grade.count 16→17（含注释串 `14 Grade ops + Tint + colormatch` → `15 Grade ops + Tint + colormatch`）；`:95` 唯一 op 19→20（含注释串 `20 rows` → `21 rows`）；`:100-109` `newSevenOps` 白名单追加 `SpektraFilmModule.opName`（panel seed-deferred 族，与 filmPlacement 同 deferral 理由——判别力修复，非红改绿）；`:139` `resolved.count` 19→20（v3「E7 零改」撤销——恒注册只保证 `makeBox` 非 nil，不保证计数不变）；`:144-166` `testOwnerMatrixOverAllEighteenRows` 的 `expected` 字典加 `"spektraFilm": .grade` 行；`:193-205` `lightamerGradeRows` 加 `("spektraFilm", 46.7)` 成 13 项 + `:228` 断言串「eleven」→「thirteen」。
   - (ii) `V50OrderTests.swift` 2 条：`:24` `entries.count` 108→109（说明串补 `+ spektraFilm`）；`:284-293` `nativeRows` 集合追加 `"spektraFilm"`（`:294` `stripped.count == 93` 不动——追加后 stripped 仍 93）。
   - (iii) `CatalogAddFaceTests.swift:224-239` 期望 **14 → 15 项，尾部追加 `spektraFilm`**（`templateInstance` 加 case 后 add-face 枚举多一项）。改数不计 ΔN，T8' 对账列实报。
   - 全仓计数 grep 结论（R-B2 建议方法实测）：`DefaultFaceTests` 的 `IopCatalog.ops == 19`（`:365`）/ `defaultFaceOps == 16`（`:370`）/ `names == 16`（`:388`）/ `fullNames == 19`（`:414`）**零改**（IopCatalog 手写静态表不加行，T6' MCP 拒绝面维持）；`NodeOwnershipCatalogTests:88` `expectedNonGrade == 13` **零改**（face union = 三件 + seed，spektraFilm 不 seed 不进 face）；`SidecarSeedTopUpTests` 自持两行 seed fixture **零改**；`testLightamerRowsAreMutuallyUnique` 46.7 唯一**天然过**（`Set(order)` 全表唯一，46.7 全表空位 grep 零命中）。
5. 登记：`Project.swift` + BUNDLE-MAP（RegistryFilmModuleTests 行）+ `tuist generate`。

AC（机检）：
- AC-T1'-1：`V50Order.order(for: "spektraFilm") == 46.7`，且排序位恰在 filmicrgb 与 lut3d **列表索引**之间；`V50OrderTests` 两处计数断言同批改（r-m3）。
- AC-T1'-2：`makeBox("spektraFilm")` env 缺席/在场均非 nil（恒注册）；`isFilmModuleRequested(environment:)` 纯函数两形态 + 生产 wrapper 同值；写入口/UI 门 env 缺席时全隐。
- AC-T1'-3：`GradeCatalog.item(opName: "spektraFilm")?.owner == .grade`；E7 checker 全绿（唯一 op 20、行 21）。
- AC-T1'-4：默认面测试进程（env 缺席）`DefaultFaceTests` 计数契约逐位不变；`McpSchemaCatalog.encodedDefaults` 面：spektraFilm 行在但 MCP 写拒绝（T6' AC 覆盖）。
- AC-T1'-5（R-B2 新增）：T1' 完成后 `Scripts/test-direct.sh --bundle <域>`（GradeCatalogTests + V50OrderTests + CatalogAddFaceTests 所在域）全绿，**零未申报红**（红 = 本 T 编辑点 4 未列出的断言）。

ΔN = 7（V50OrderTests +1、RegistryFilmModuleTests 新文件 5、GradeCatalogTests E7 +1）。封存面：V50Order（add-only）、GradeCatalog（第 21 行 + E7 期望）。

## T2' SpektraFilmModule 本体 + ACEScc 往返臂 + FilmLegFactory + FilmMaterialSeam

目标：可注册 module，process = 材料缝解析 → ACEScc 往返 + 经包装缝 delegate 现有 film 腿装配；flags `.supportsBlending | .oneInstance`，不设 `.allowTiling`。D-SM-1 负测提前到本 T。**落域 LAYERS**（R-M3）。

编辑点：
0. **T2'-0 基线轮提前**（R-M3 修法 iii）：动工前跑无 spektraFilm 的 LAYERS bundle 基线轮取 `ru_maxrss` 现值归档（`evidence/t2/layers-baseline.md`）；门算式 = 基线 + 本批 ≤8192（基线 944MB，余量 ~7.2GB）。
1. 新 `LightamerCore/Sources/Pipe/Film/FilmMaterialSeam.swift`（D-SM-13 缝本体，非封存）：resolver 闭包 holder（`FilmStatsSeam` 同款形态）。resolver 前置 `guard !stock.isEmpty`（v3 §三链路复核：pristine 档不打 error 日志；或 module 侧 `guard !isFilmRecordDefault(record)` 提前恒等——二选一 SUMMARY 实报）。
2. 新 `LightamerIOP/Sources/SpektraFilm/SpektraFilmModule.swift`：
   - `opName = "spektraFilm"`，`iopOrder = 46.7`，`flags = [.supportsBlending, .oneInstance]`，`defaultColorspace = .RGB`。
   - `Params = { record: FilmRecord }` 原样嵌入（`ParamsCoding` 经 `FilmRecord` Codable；求解值不入 Params）。`Params()` 默认形 = `record: FilmRecord()`（供 `templateInstance` 与 identityJSON）。
   - `modifyROIOut/In` 恒等直通；**不覆盖 `tileHalo` + `tileWorkingSetBytesPerPixel` 保持默认 0 + 不设 `.allowTiling`**（三条件全钉）。
   - `process` 七步：① 材料缝解析（nil → blitIdentity + `logger.error`，无 toast）→ ② `dispatch2DTexture(grade_acescc_out)` → ③ 自持 run-scoped 中间面（D-SM-12R，不借 allocator）+ `liveSurfaceCount` advisory 计数槽 → ④ 直方图（`FilmStatsSeam.histogram` 同缝）→ ⑤ `FilmLegFactory.assemble`（传 `piece.renderProcess`）→ ⑥ `FilmMethodBox` 转发 → ⑦ `dispatch2DTexture(grade_acescc_in)`。
3. 新 `LightamerCore/Sources/Pipe/Film/FilmLegFactory.swift`（非封存）：`public enum` + `public static assemble(record:film:paper:materialPairHash:histogram:plane:metal:renderProcess:)` → 同形透传 internal `PixelPipe.assembleFilmLeg`。
4. `SpektraFilmParams.swift` 若需适配层则新建，否则并入主文件（Δ文件 −1，SUMMARY 实报）。
5. 登记：`Project.swift` + BUNDLE-MAP（**SpektraFilmTests 行落 LAYERS**）+ `tuist generate`。

AC（机检）：
- AC-T2'-1：`flags == [.supportsBlending, .oneInstance]`；`.allowTiling` 缺席。
- AC-T2'-2：`tileHalo` 默认 0；`modifyROIIn == identity`。
- AC-T2'-3：`assembleDensityFilmLeg` / `assembleSpectralFilmLeg` 函数体 md5 == 执行 HEAD 基线值（提取法：签名行至同缩进闭合 `}` 确定性截取；基线在派遣 HEAD 重钉）；`PixelPipe.assembleFilmLeg` internal + 签名零 diff。
- AC-T2'-4：材料未解析档 `process` 输出逐位 == 输入（blitIdentity；缝缺席闭包形态）。
- AC-T2'-5：identityJSON 往返：`Params()` 编解码逐字节 == 登记值。
- AC-T2'-6（R-M3/r-m9 重写，拆两条）：(i) 自持面计数（`liveSurfaceCount` 槽）≤1（合成平面，默认跑）；(ii) 100MP 峰值 RSS 探针（`LIGHTAMER_PERF_PROBE=1` + XCTSkipUnless 默认 skip）：`ru_maxrss ≤ 8192MB` 绝对门；默认套件用中平面（≤2K）跑分配计数断言。参考断言：module 腿相对 legacy 腿 ΔRSS ≤ 1 张全帧平面（非门）。
- AC-T2'-7（B1 正测）：缝注入 store → module 腿 payloads 非 nil（合成平面 + 测试 store 注入）。
- AC-T2'-8（B1 负测，r-m6 钉死）：缝缺席 → blitIdentity + 不 crash + 不 throw（行为断言；logger 不断言）。
- AC-T2'-9（M1）：实测胶片链局部斜率分布 → slope 表落盘；**实测带 ≤ 推导上界**；高光实测带 ≤ 中段实测带。
- AC-T2'-10（M7/D-SM-1 提前）：process 内产出 payloads 后断言「同 params 不同 stats ⇒ 平面 key 不同」；证伪 = **需 re-plan**，非 +1 hunk。
- AC-T2'-11（M8）：module 档 + spectral 臂 + grain/halation 全开 ⇒ 无 BorrowError。

ΔN = 15（SpektraFilmTests 新文件落 LAYERS：AC-T2'-1/2-2/2-4/2-5 各 1、2-3 md5 双臂 2、2-6 分配 1 + RSS 探针 1、2-7/2-8/2-9/2-10/2-11 各 1、工厂透传 2 = 4+2+2+5+2）。
封存面：无（IOP 新文件 + Core Film/ 两新文件；PixelPipe/工厂函数体零 diff）。

## T3' 参数载体迁移（谓词单源 + sync 腿门控 + merge refuse + sidecar 键 legacy 只读）

目标：判别谓词单源就位；sync 腿门控；`filmRecords` 载体与 sidecar `filmRecord` 键转 legacy 只读；history 键族保留解码停产新写；merge refuse 落地（R-M4 钉形）。

编辑点：
1. `PipeCoordinator.swift`（谓词落点）：新增 `hasSpektraFilmInstance: Bool`（sync 纯值：全局 `history.effectiveInstances()` ∪ `layerStack.compositeLayers` 各 `HistoryStack.effectiveChain(chain)` opName 扫描，presence 不看 enabled）+ `findSpektraFilmInstance() -> (layerID: UUID, instance: ModuleInstance)?`（全局命中 layerID=nil；零/多（防御）= nil）；`WorkspaceModel` 只加 `hasLegacyFilmRecord(for:)`。
2. `EditorState.swift`：`recordFilmChange` 保留（legacy 档编辑面）；**基链 typed reject**：`recordChange(_:label:)` 首行加「仅 `opName == spektraFilm` → presentToast + return」（r-m5：film 语义 op（grain 等）不受影响；`FilmPanelModel.applyRecommendedGrainStrength` 走 grain record 不误伤）。层写入面零改。
3. `LayerStack.swift`（Core Layers，**封存表第 16 行**，R-M4 甲 + R-M5）：`mergeDown` 在 `.mergedIntoBase` 返回前加「combined chain 含 spektraFilm → restore + return nil」（retouch 同缝同形，纵深防御）。`mergeLayerDown`（`EditorState.swift:738-751`）开头加预检：`target chain 含 spektraFilm → presentToast(toast_layer_merge_film_refused) + return`（不调 `mergeDown`）。`MergeDownOutcome` 枚举零改（grep `case refused` 零命中机检）。
4. `HistoryStack.swift` / `LightamerSidecar.swift`：**零改**（J5 成立；`git diff` 机检为空）。
5. `PipeCoordinator.syncFilmCarrierWithHistory()`：改 D-SM-10 门控形（在场 → 清 carrier；否则 = effectiveFilmRecord）；`versionActionDidChange()` 同款接入（async 内调 sync 谓词）。
6. 登记：`Project.swift` + BUNDLE-MAP（WorkspaceLegacyTests 行）+ `tuist generate`。

AC（机检）：
- AC-T3'-1：`schemaVersionCurrent == 13`；`LightamerSidecar.swift` diff 为空。
- AC-T3'-2：含 `filmRecord` 的 v13 fixture 解码后 `hasLegacyFilmRecord == true` 且 `effectiveFilmRecord()` 逐位 == fixture。
- AC-T3'-3：层内实例在场谓词 true；`recordChange` 拒收 + history 无该 item；enabled=false 仍 true（presence）。
- AC-T3'-4：`HistoryStack.swift` diff 为空 + sync 门控（在场 → carrier 缺席；缺席 → carrier = effective）。
- AC-T3'-5：迁移 commit 后旧 `filmRecord` item 仍解码（undo 可回 legacy 观感）。
- AC-T3'-6（B4/R-M4）：含 spektraFilm 的底底层 merge → refuse（toast + 层原地 + 计数守恒）；入层 merge 正常（计数守恒）；redo 不丢实例；**预检 toast 法**（mock 调用 `mergeLayerDown` 断言 toast 键 + `mergeDown` 未调）。

ΔN = 14（FilmHistoryTests +2、FilmSidecarTests +3、WorkspaceLegacyTests 新文件 8、R-M4 预检 toast +1）。
封存面：`LayerStack.mergeDown` 1 hunk（见封存表第 16 行）。键预算：`toast_layer_merge_film_refused` 1 枚。

## T4' 双轨读判别门 + 迁移行 + 动作面 guard + 备份 + env 门接线

目标：旧档走 legacy 回放腿逐位恒等；新档走 module 链；面板出「Convert to Film module」迁移行；`runProcessMigration` 三源 guard；convert 前 pre-convert 备份；env 只是可见性开关。

编辑点：
1. `PipeCoordinator.swift`：
   - `filmTailPolicy(for:)` 加双轨判别：`hasLegacyFilmRecord && !hasSpektraFilmInstance` 才供给 `FilmTailParams`（thumbnail 恒 nil 门保留）。签名零改，内部首行判别 hunk。
   - `filmLegRequestTags(for:)` 门改 D-SM-14 形：`resolution != .thumbnail` 前置 + 「legacy carrier ∨ module 实例在场」；解析体抽 `resolveLegTags(record:store:rms:)` 纯函数（`:886-918` verbatim 出体；rms 经形参注入——`rmsTableBox` memo 留 coordinator 内，S-RM1-4；legacy 档传 carrier record，module 档传 `findSpektraFilmInstance().params.record`）。
   - `FilmMaterialSeam` 安装：`attachFilmStore` 内联装 resolver / 缺席闭包（D-SM-13；本 T 落地安装点）。
2. `PixelPipe.swift`：`runTerminalTails` film 分支**零逻辑改**；仅注释标注"legacy 回放臂（spektra-module 双轨期）"。`run()` 与 `runSub()` 调用点零改。
3. `EditorState+FilmMigration.swift` + `PipeCoordinator.runProcessMigration`（B3）：
   - `FilmMigrationAction` 新增 `.convertToModule` case；`evaluate` 加 `hasLegacyFilm: Bool = false` + `hasSpektraFilmInstance: Bool = false` 双默认参；判别表：`hasLegacyFilm && !editingInFlight → .convertToModule`（优先于 process migrate）；`migratable` 扩认；process 门 film 源改「`hasLegacyFilmRecord` ∨ 全作用域在场」（两面板调用点传单源谓词值）。
   - `runProcessMigration`：guard 改 `hasFilm || hasCW || hasSpektraFilmInstance`；marker 三支：`hasFilm && !hasSpektraFilmInstance` → film item VERBATIM / `findSpektraFilmInstance()` 非 nil → `recordLayerChange` params-verbatim（全局命中退 CW 支；禁 film-item 标记形）/ 否则 CW verbatim。
4. 迁移行渲染：`ProcessMigrationInputs` 加文案字段 + convert 键族 `panel_film_convert_{title,body,button,confirm}`（≤4，cancel 复用 **`alert_cancel`**（r-m7 点名）；body 含多层漂移说明段 D-SM-7）；AX id 前缀 `film.convert.*`。
5. 确认动作 `PipeCoordinator.runFilmModuleConversion`：**pre-convert 备份**（M2-8 轮换先例，sidecar 快照）→ 合成 `ModuleInstance(spektraFilm, Params(record: legacyRecord))` 经「最上层 AdjustmentLayer」形态落地（`compositeLayers.last`，无则 `addAdjustmentLayer()`）+ `addModuleToLayer` + `recordLayerChange`（`history_film_enable` 语义 label）+ 清空 `filmRecords[url]` + `scheduleSidecarWrite`。**undo 步数**：有层 = 2 item（结构 + 参数），无层 = 3 item（+ 建层）。
6. env 门接线：缺席时迁移行隐藏（`migratable` 门读 `isFilmModuleRequested` 单源）、面板 enable 隐藏、add 菜单行隐藏——**已迁移档 env-off 照常渲染**（M2 选 a）。
7. 登记：`Project.swift` + BUNDLE-MAP（FilmMigrationTests 行更新）+ `tuist generate`。

AC（机检）：
- AC-T4'-1：legacy fixture：门开/关均走旧腿，输出 hash == 基线 golden（逐位恒等，双 env 测）。
- AC-T4'-2：已迁移档：`filmTailPolicy(for: .full) == nil`；`filmLegRequestTags(for: .full)` 非 nil；渲染链含 46.7 box；实例落 grade 层内；基链无 spektraFilm（负测）。
- AC-T4'-3：`evaluate(hasLegacyFilm: true)` → `.convertToModule`；`editingInFlight` 优先；M8-3/M9-4 真值表逐位不变；`migratable` 对 `.convertToModule` = true。
- AC-T4'-4：v1 legacy 档 → convert 后 process 迁移行可见；确认后标记 = `recordLayerChange` params-verbatim item（history 无 filmRecord 写回——负测）；`documentProcessVersion == .current`（点击后真翻）。
- AC-T4'-5：转换后：实例在场 + carrier 缺席 + sidecar 无 `filmRecord` 键 + 按步数 undo 回 legacy 观感 + undo→redo 后 carrier 仍缺席 + 关 module 后 legacy 不复活；跨转换点版本切换两侧观感各自正确。
- AC-T4'-6（M2 选 a）：env 缺席迁移行 `migratable == false` + env-off 迁移档**照常渲染**（hash == env-on；`degradedForUnknownOps` 不触发）；回退面 = 手动 disable + pre-convert 备份。
- AC-T4'-7（B3 负测）：已转换档（无 carrier、无 CW）调 `runProcessMigration` 翻号 + 写一条 layer-scope item；无 film 无 CW 无实例档 = no-op。

ΔN = 15（FilmMigrationTests +5、PipeCoordinatorLegacyTests +6、Registry env 门 +2 并入 T1' 文件、备份/回退 +2）。
封存面：PixelPipe（仅注释 hunk——若实现零改则终表记"注释例外"）。键预算：convert 族 ≤4。

## T5' 求解链不动验证 + tile 政策钉死

目标：FilmSolveCache 键控原样；`pixelUm` 全帧锚；tile 永不可达机检钉死；legacy `runFilmLeg` 统计原样保留。

编辑点（预期极小，多为测试）：
1. `FilmTailPolicy.swift`：`FilmSolveCache` 键零改；`FilmStatsSeam.histogram` module 侧新增调用点（T2' 已实现），legacy `runFilmLeg`（`PixelPipe.swift:1241-1243`）原样保留至 deprecation 窗。**统计对象变更声明**：module 侧输入平面从"主链顶面"变为"本层 46.7 输入"——单层置顶档 ε 带等价（T7' 主门），多层档漂移由迁移提示承担（R3）。
2. `SpectralPayloads.swift`：`pixelUm(frameWidth:)` 零改；不 tile 三条件 ⇒ plane 恒层子 run 全平面 ⇒ 锚正确。
3. tile 政策文档：`SpektraFilmModule` doc comment 钉死"per-ROI 红线结构面延续 + P2 挂账"。
4. 登记：`Project.swift` + BUNDLE-MAP（SpektraTilePolicyTests 行）+ `tuist generate`。

AC（机检）：
- AC-T5'-1：`FilmDeterminismTests` 精确值逐位不变。
- AC-T5'-2：`PixelPipe.swift` `runFilmLeg` 函数体 diff 为空 + `SpectralPayloads.swift` 求解段 diff 为空（注释除外）。
- AC-T5'-3：`tileWorkingSetBytesPerPixel == 0` ∧ `tileHalo == 0` ∧ `flags ∌ .allowTiling` 三条并存（`tileNeeded` 首道否决 0 = never tiled 为主断言）。
- AC-T5'-4：`.full` 下 `process` 调用次数 == 1 + `pixelUm` 全帧锚断言（plane 宽 == 层子 run 全平面宽）。

ΔN = 4（SpektraTilePolicyTests 新文件 4）。封存面：无。

## T6' 下游面（DRT 交接/导出 per-target tags/渲染入口 QL 装配/面板换锚/Film 卡/MCP 拒绝/写入面三修）

目标：film 退出终端共享序后剩余面逐项收敛；渲染入口清单逐面裁定（含 QL 装配 D-SM-15）；面板换锚 + live 腿钉形；Film 卡退役；MCP 显式拒绝；写入面三修（含 R-M2 层面判据）。

编辑点：
1. **DRT 交接**：`runTerminalTails` ② DRT tail upstream——legacy 档仍 film 输出 hash（零改）；新档 film 缺席 ⇒ upstream 回主链顶面 hash（含 46.7 输出——**代码零改**，行为自然收敛）。`DrtTailAssembly.seed` 签名零改。`isTerminalTailSkipped` film 分支保留。
2. **导出**（R-M1 甲）：`ExportQueue.enqueue(filmTails:)` + `$jobFilmTail` + `$requestTags` 保留（legacy 通道；`filmTails` 维持 loaded-only）；`legTags` 改 per-target：`makeRunAssembly` 内 loaded 位 = `resolveLegTags(loadedRecord:store:)`（旧路），兄弟位 = `resolveLegTags(sidecarRecord:store:)`（record 取自各 target `ExportRenderer.readDocument().layerStack` 内 spektraFilm 实例 params，无实例 = nil）。`ExportRenderer` 装配：legacy 档传 tails、新档传 nil（含 46.7 自然进链）。`ExportQueueContract` 零 diff。`ExportFilmChainTests` 加参数化（legacy vs module 双臂 + 兄弟图 tags 臂）。
3. **渲染入口清单**：
   - export：**include**（46.7 自然进链）；
   - 库网格 thumbnail：**strip**——`SessionThumbnailProvider.buildRenderRequest` 物化层对 `runtimeLayers` 各层 `chain` 过滤 `opName == spektraFilm`（r-m4 措辞；渲染前副本，不改 `layerRecord`）；`SessionThumbnailRenderer.swift`（Phase 8 contract 禁改）零触；KD-4 门保留；
   - 编辑器 thumbnail：**strip**——App `renderCurrentChainInner`（`:2852` 分派前）：`resolution == .thumbnail` 时对 `currentLayerStack` 做**副本过滤**（`AdjustmentLayer` 全参 public init `:54-74`；原栈不动）后传 driver；**`LayerCompositeDriver` 零 hunk**；
   - QuickLook：**include**（D-SM-15，v3「P1 不纳入」撤销）：`LightamerQuickLook.swift` `Env` 增三件——① `registry` 改 `await LightamerIOPRegistry.populate(ModuleRegistry.makeDefault())` 全量装配；② 自建 `FilmMaterialStore`（host bundle resource 路径分支）+ `FilmMaterialSeam` 装闭包；③ run 内 tags 供给（record 取自 QL `document.layerStack` 内实例）。`QuickLookRenderer` 渲染体零改；
   - ColorMatch 追色参考：**strip**（与 legacy `filmTail: nil` 同语义——`ColorMatchService.swift:217,223` 加同形排除）；
   - followEdges surface / mask overlay 探针面（`:2360,2854,2940`）：**strip**（DECISIONS 申报）。
4. **Film 面板换锚 + live 腿钉形 + 单实例守卫**（v3 T6'-4 全文继承：数据源换锚三级读改 live 实例 → history → carrier；`commit` 按 `usesModuleLeg` 分腿；module 档通用 D-H1 腿 + film 三段限定 legacy；enable 入口「最上层 AdjustmentLayer」形态 + add 菜单 `excludingOpNames` 下传 + **P1 顺修** `addPlacement` + `templateInstance` 加 case；Solve 保留；宽容度/descriptor 换锚）。
5. **节点 Film 卡退役**（OQ-5(a)，v3 T6'-5 继承）：`filmCardID` + `includesFilmCard` + 卡渲染全撤；`FilmCardTests` 退役（**−4** 法；文件删 + 登记退役）；`editor_node_film*` 3 键 xcstrings 保留（zh-audit allowlist 备注退役）；Film 页入口（`LightamerShell.swift:2255`）保留。
6. **MCP**（v3 T6'-6 继承）：`apply_params` 对 spektraFilm typed reject（拒绝点 `applyParamsBody` ops 循环前；`remove: true` 亦拒；「因层专属而完全不计入 MCP 面」）；`requiresControl`/turn-taking 零改；`IopCatalog` 不加行；`mcp_tool_desc_apply_params` 零改。
7. **写入面三修**：
   - (a) 预设创建（R-M2）：`createPresetFromCurrent` 前层面检查（`hasSpektraFilmInstance` 单源谓词读 `editorState.layerStack`）→ 命中 = **拒绝创建**（typed 错误 `PresetError.layerOnlyOpPresent`（Core Presets additive case）+ 面板提示；层结构进预设 = P2）；`PresetApplier.makePayload` 防御过滤为第二道（payload instances 份剔除 + log）。
   - (b) `AdjustmentTransferCatalog.buildPayload`：spektraFilm 只进 `layer.chain`，**不进** `records`；`isAdjustmentTransferable` 不变。
   - (c) `PasteRejectionReason` 增 `layerOnlyOp` token（FIXED 表扩四→五，schema/文档同步）；paste→legacy 档含 spektraFilm = 拒绝（提示走迁移确认）；`PasteSemantics` overwrite/merge 面剔 instances 份。
8. 登记：`Project.swift` + BUNDLE-MAP（ThumbnailStripTests/McpFilmTests/QuickLookFilmTests 行）+ `tuist generate`。

AC（机检）：
- AC-T6'-1：新档 `.drt` 渲染 upstream == 含 46.7 主链顶面 hash；legacy 档 == film 输出 hash（回归）。
- AC-T6'-2：导出三臂：legacy 档含 film 腿（hash == 基线）；新档 loaded 图含 46.7 且 `filmTails` 传 nil；**兄弟图 tags 臂**（R-M1：同一批不同 grade 的 module 档批量导出，兄弟图输出 == 各自 grade 下 legacy 腿同 record 输出，ε 带）。
- AC-T6'-3：库网格 thumbnail run 实例集不含 spektraFilm；`filmTailPolicy(for: .thumbnail) == nil` 回归；`SessionThumbnailRenderer.swift` diff 为空。
- AC-T6'-4（R-B1 重写）：**QL preview（2560 fit）== 导出同档同尺寸输出（ε 带，D-SM-16）**；legacy 档 QL 观感逐位不变（回归）。
- AC-T6'-5..8：v3 同编号继承（面板换锚/MCP 拒绝/Film 卡退役 grep/编辑器 thumbnail 副本过滤）。
- AC-T6'-9（R-M2 重写）：含层内 spektraFilm 的 fixture 档调 `createPresetFromCurrent` → 抛 `PresetError.layerOnlyOpPresent` + `PresetsStore` 无新文件；`makePayload` 防御过滤（instances 份无 spektraFilm）。
- AC-T6'-10/11/12：v3 同编号继承（buildPayload 负测/paste 负测+token/module 拖拽腿）。
- AC-T6'-13（R-B1 新增）：QL registry `unknownOps` 不含 `spektraFilm`（populate 装配断言）+ appex→host resource 路径落盘验证（store 构建成功）。

ΔN = 28（ExportFilmChainTests +4、ThumbnailStripTests +4、FilmPanelTests +5、McpFilmTests 3、渲染入口三面 +3、D-SM-11 paste/菜单 +2、M4 三修 +4、QL 装配 +2、层面拒绝 +1）。
封存面：PixelPipe（预期零逻辑改——终表记"行为自然收敛无 hunk"或注释 hunk）。

## T7' ε 带桥接测试 + 蒙版 AC + golden 迁移 + 落域 LAYERS

目标：两宿主 ε 带等价桥接测试（P1 验收主门）；蒙版收益验收；tags 三形态等价；双臂 golden kernel 字节零改；测试域归置同批。

编辑点：
1. 新 `Tests/LightamerTests/SpektraBridgeTests.swift`（**落域 LAYERS**：文件名避 `*Parity*`→IOPP 路由）：同一合成小平面 + 同 record，legacy 回放腿 vs module 链输出 ε 带比对——密度臂/光谱臂/identity 三形态。**限制声明**：仅"单层、胶片置顶、无层蒙版、层内 46.7 前 ops 为空"成立；多层形态测"迁移行可达 + 漂移提示渲染"不测等价。夹具 = 合成小平面三形态 + **1 张降采样 CC0**（全量实拍腿不立项）。基线轮已在 T2'-0 落地（本 T 复用归档值，不重跑）。
2. `ACEScc 往返精度门`：D-SM-9R 口径；超带 = T2' 形态回炉 + re-plan。
3. 蒙版 AC：层 opacity 0.5 / 径向蒙版下 module 输出 == 层混合公式期望（合成平面，ε 带内）；走查项见 T8'。
4. 既有 Film/Spectral 测试域归置：按 BUNDLE-MAP 的 film/spectral 行集为准（r-m2：不写死数字；HEAD 实测 49 文件），零改名；`FilmLegTests`/`FilmCoordinatorTests`/`ExportFilmChainTests` 加双形态参数化（T3'/T4'/T6' 已计）；`FilmCardTests` 退役（T6'-5，−4）；新文件按域模式归入唯一 target + 显式登记（各 T 已分散登记，本 T 复核行内 method 数终态）。
5. `SpectralDualArmGoldenTests` / `SpectralCrossArmGoldenTests` / `FilmGoldenTests` / `BWSpectralGoldenTests`：golden 字节零改（执行 HEAD 重钉 md5）；宿主路径变更由桥接测试覆盖。
6. 跑法：`Scripts/test-direct.sh --bundle <域>`；MEMFAIL 风险：夹具小平面 + 降采样 CC0 单张，若定向轮 MEMFAIL 则夹具再降采样（不扩豁免）。

AC（机检）：
- AC-T7'-1：桥接三形态 ε 带等价（density/spectral/identity 各 ≥1 合成 + 1 降采样 CC0；D-SM-9R 口径；比较空间 L048）。
- AC-T7'-2：ACEScc 往返三段带（超带 = T2' 回炉；重试上限 1 次 + 样本集 = AC-T7'-1 同集）。
- AC-T7'-3：golden md5 == 执行 HEAD 基线（`git diff --stat Tests/` 仅新文件 + 参数化测试源，无 `.bin/.png` 变更）。
- AC-T7'-4：BUNDLE-MAP 行内 method 数对账 == 终态；`tuist generate` 后全 bundle 可列（无孤儿登记）。
- AC-T7'-5：D-SM-1 负测复核（T7' 重跑 AC-T2'-10 回归）。
- AC-T7'-6：蒙版两形态 == 层混合公式期望（opacity 0.5 / 径向蒙版，ε 带内）。
- AC-T7'-7（B2）：module 路 grade/filter/reversal 三形态输出 == legacy 腿同 record 输出（ε 带；BW 显式 grade 不丢失）。

ΔN = 18（SpektraBridgeTests 12；其余 6 = 双形态参数化增量跨文件）。封存面：无。

## T8' 收口（贴线定向轮 + 全套 + 走查 + SUMMARY/DECISIONS + 申报终表）

1. 贴线定向轮：全套前先跑 `--bundle IOP` 与 `--bundle LAYERS` 定向轮（machine-guard G1-G4 + 运行时 monitor 伴跑；MEMFAIL/压力转红即停查夹具/顺序漂移，不扩豁免）。基线轮已在 T2'-0（本 T 引用归档值）。
2. 全套回归：`Scripts/test-direct.sh --all`（orchestrator 批准制；monitor 伴跑；预期基线 = **M9-2 收口值 + 本批 ΔN=101 − FilmCardTests 退役 4 = 净增 97**）。
3. GUI 走查：env 门开档——迁移行渲染/确认 sheet（含漂移说明）/pre-convert 备份存在/转换后面板换锚/单实例 add-face/merge refuse toast/蒙版项（单层只放 spektraFilm + 径向蒙版观感）/缩略图 grid 目视（与编辑器同档观感一致，都无胶片，r-m8）/QL preview 观感（与导出同档一致，R-B1）；关档——迁移行/面板 enable/add 行零可见 + **已迁移档照常渲染**。证据落 `.work/gui-acceptance/spektra-module/` + MANIFEST。
4. zh 对账：`zh-audit --check` 全绿；convert 键族 ≤4（cancel 复用 `alert_cancel`）+ merge toast 1 申报；`editor_node_film*` 退役 allowlist 备注；xcstrings 尾块纯插入。
5. 产物：`SUMMARY.md` + `DECISIONS.md`（chunked 写；DECISIONS 含 v3 九登记 + v4 六登记：R-B1 修法甲裁决 + appex resource 路径实报 + R-M1 兄弟图 tags 供给声明 + R-M2 层面判据 + R-M4 预检钉形 + D-SM-15/16）+ 封存面申报终表。
6. 机器纪律：machine-guard 单重活；DerivedData 收口清自建容器；commit-per-task（T 序串行，每 T 独立 commit）。

AC（机检）：
- AC-T8'-1（m6 拆三条）：全套 0 fail；MEMFAIL 0；`RenderProcessVersion.current.rawValue == 3` + case 列表未增；UserDefaults 零新键；`FilmPlacementModule`/`FilmPlacementKernels.metal` md5 不变 + GradeCatalog 第 19 行 diff 为空（第 21 行为 T1' 新增）。
- AC-T8'-2：zh-audit 全绿；convert 键族 ≤4（`panel_film_convert_{title,body,button,confirm}` 在册，cancel=`alert_cancel`）+ `toast_layer_merge_film_refused` 在册；grep 退役面零命中；封存 diff == 申报终表（16 行）。
ΔN = 0。封存面：终表复核。

## 封存面申报表（v4 执行前申报，16 行；T8' 终表复核）

| 封存件 | 申报形态 | 任务 | 对 RESEARCH §6.1 的修订 |
|---|---|---|---|
| PixelPipe | `runTerminalTails` 注释 hunk（legacy 回放臂标注）；逻辑零改（**D-SM-1 证伪 = re-plan，非 +1 hunk**） | T4' | 收窄：4.4 折叠缝取消；upstream 自然收敛零 hunk |
| V50Order | add-only 一行 `("spektraFilm", 46.7)`，dt-verbatim 补录 | T1' | 同 RESEARCH |
| GradeCatalog（NodeOwnershipCatalog） | 第 21 行 + E7 期望（唯一 op 19→20、行 20→21；grade.count 16→17）；`needsEnvelope` 零改 | T1' | 收窄：谓词例外取消；计数口径修正 |
| ExportQueueContract | **零 diff**（filmTails + legTags 保留为 legacy/双轨通道；per-target 解析落 App 装配侧） | T6' | 修订：删参数推迟到 deprecation（D-SM-4） |
| sidecar schema | **零 diff**（v13 不动、零新键） | T3' | 修订：v14 bump 取消（OQ-4(b)） |
| HistoryStack / HistoryHash | 零 diff（保留只读、新写停产；merge refuse 落 `LayerStack` 数据面） | T3' | 同 RESEARCH（否） |
| DrtRecord / TerminalTailPolicy / DrtTailAssembly / DrtEotf / Lut3dKernels.metal / 六格式导出矩阵 / NodeGraphCommand / PipelineDocument | 零 diff | T6' | 同 RESEARCH（否） |
| UserDefaults 键族 | 零新键 | 全批 | 登记制：grep 键登记面无新增 |
| filmPlacement 20.8 | 零改 | 全批 | 三件 md5 + 第 19 行 diff 为空 |
| 既定禁改面（非 17 件） | `SessionThumbnailRenderer.swift` 零触（strip 落物化层 + App 副本过滤） | T6' | Phase 8 contract |
| FilmTailPolicy.swift | **零 diff**（TaskLocal 路：`tables`/`solveSpectral` 零签名改） | T2'/T4' | v3 选型结论：终表复核 diff 为空 |
| FilmPrintBake.swift | **零 diff**（同上） | T2'/T4' | 同上 |
| FilmMaterialStore.swift | **零 diff**（缝 = 新文件 holder + App/QL 安装点，store 本体不动） | T2'/T4'/T6' | 同上 |
| LayerCompositeDriver.swift | **零 diff**（编辑器 thumbnail strip 走 App 副本过滤，不加形参） | T6' | 同上 |
| 桥接测试落域 | `SpektraBridgeTests` 落 LAYERS + `SpektraFilmTests` 落 LAYERS（R-M3）+ 基线轮先行（T2'-0） | T2'/T7'/T8' | M5 修法 |
| LayerStack.mergeDown（R-M5 增行⑯） | Core Layers 实质 1 hunk（refuse guard + restore；非封存面但逐 hunk 申报）+ `MergeDownOutcome` 枚举零改 | T3' | v4 新增申报 |

**结论**：v4 落为「实质 3 行（V50Order/GradeCatalog/LayerStack）+ 1 注释例外（PixelPipe）」——B1/B2/M3 的缝全部落在**新文件**（FilmMaterialSeam/FilmLegFactory）与 **App/QL 非封存面**（安装点/门改/副本过滤/装配）内。

## 风险→任务映射（v4）

| RESEARCH 风险 | 承载任务 | 门 |
|---|---|---|
| R1 pixelUm 锚 | T2'（三条件）+ T5' | AC-T2'-2/AC-T5'-3/AC-T5'-4 |
| R2 corr 网格/scratch | T5'（不 tile ⇒ 零变化）+ T2'（自持中间面） | AC-T5'-2/AC-T2'-6/AC-T2'-11 |
| R3 多层档统计漂移 | T4'（最上层落点 + 漂移提示 + 备份）+ T7'（限制声明） | AC-T4'-5/AC-T6'-5/AC-T7'-1 |
| R4 100MP 内存峰 | T2'（.oneInstance + 自持面 + 绝对 RSS 门 + 基线轮提前）+ T8'（贴线定向轮） | AC-T2'-1/AC-T2'-6/AC-T8'-1 |
| R5 层内重复求解 | T5'（SolveCache 命中） | AC-T5'-1 |
| R6 ACEScc 往返 | T2'（kernel 复用）+ T7'（ε 带精度门） | AC-T7'-2/AC-T2'-9 |
| D-M3-2-1 翻转三问 | §4.0 已答；T6'-5/T3' | AC-T6'-7/AC-T3'-3 |
| R-B1 QL parity（v4 新增） | T6'-3（appex 装配 D-SM-15） | AC-T6'-4/AC-T6'-13 |

## 执行纪律（执行 lane 自持，抄送任务书）

- commit-per-task（T1'..T8' 可串行，每 T 独立 commit）；产物交接 BUILD-HANDOFF.txt；machine-guard 单重活；zh-audit 每批对账。
- 双臂 golden kernel 字节零改红线（md5 机检 AC-T2'-3/AC-T7'-3，执行 HEAD 重钉）。
- `tuist generate` 恒为登记批最后一个动作（L041）；BUNDLE-MAP 同批（每 T 自登记，T7' 复核终态）。
- env 门纪律：M2 选 a——默认面迁移行/写入口零可见 + 已迁移档照常渲染，直到走查 + 桥接全绿。
- 既有测试改写申报（T8' 对账列实报）：GradeCatalogTests 10 条（8 期望 + 1 断言串 + 1 白名单语义）、V50OrderTests 2 条、CatalogAddFaceTests 1 法（14→15）、FilmMigrationTests 真值表扩、ExportFilmChainTests / FilmLegTests / FilmCoordinatorTests 双形态参数化。
- 键预算：convert 族 ≤4（cancel 复用 `alert_cancel`）+ merge toast 1（xcstrings 尾块纯插入，T8' 对账）。
- **v4 新增纪律（R-B2 教训）**：凡 PLAN 写「零改」必须带 grep 证据；T1' 首个执行，AC-T1'-5 为全批第一道门。
