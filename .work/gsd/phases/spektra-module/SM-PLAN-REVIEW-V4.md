# spektra-module P1 PLAN **v4** 复审（zcode review lane，第四轮）

> 审对象：`.work/gsd/phases/spektra-module/PLAN.md`（52,419B / 389 行，v4，2026-11-04 00:58 落盘，commit `da5d9fb7`）。
> 闭合对照：`SM-PLAN-REVIEW-V3.md`（FAIL / 2 blocking + 5 major + 9 minor，本轮闭合基准）；v2/v1 报告在册。
> 设计正本：`RESEARCH.md`。用户裁决：`DECISIONS.md`（D-SM-0 五条生命线全量禁降档）。
> 基线亲核：`git rev-parse HEAD` = `da5d9fb7`（= PLAN 落盘 commit）；`git diff --stat 0d7d0e90 da5d9fb7` 仅 3 文件（PLAN.md + omp-replan4.log + sm-replan4-prompt.md），**源码面与 v3 评审基线 `0d7d0e90` 逐字节一致**——PLAN 自述基线 `0d7d0e90` 有效。
> 纪律：只读；零 commit / 零构建；唯一产出 = 本文件（chunked 追加，逐段 wc -c + U+FFFD 自检）。全部判定基于 HEAD 亲核 file:line，未修改 PLAN。

---

## 结论头

**PASS / 0 blocking + 0 major + 3 minor**

一句话：v4 把 v3 的 2 blocking + 5 major + 9 minor **全部真消解**——R-B1 走修法 (甲)（D-SM-0 落实表文首登记 + D-SM-15 appex 独立装配 + QL include + 正测 AC 替换反向断言），其 S-QL 六节 HEAD 证据**逐条亲核属实**（appex deps 含 IOP `Project.swift:270-274`、appex grep populate 零命中、`populate` public async + defaultFace 缺省 `Registry.swift:69-93`、`QuickLookRenderer` 层重建 + registry 入参、`FilmMaterialStore.init(profilesDirectories:)` public throwing、Shell `Bundle.main.resourceURL` 装配先例、folder reference `Project.swift:187/193`）；R-B2 两批 12+1 条改写申报与 HEAD **逐位吻合**（我独立 grep 全部现值一致，`CatalogAddFaceTests` 现 14 项实证），且我的全仓广扫**未发现第 13 条未申报红**（`filmic<lut3d<colisa` 列表序断言在「filmicrgb 后插入」下仍成立，`:300-307`）；五 major 的读面/基线/枚举/封存行全部在 HEAD 落到实处；ΔN 分项 7+15+14+15+4+28+18+0=101、净增 97 算术自洽（FilmCardTests 4 法退役实证）。本轮仅余 3 条 minor（新增）：封存结论句漏计 Core Presets 两处 hunk、D-SM-15① async 装配机制留白、AC-T6'-13 的 appex 装配面自动化可达性注记——均不构成门槛缺陷。

### v3 finding 闭合总表

| v3 finding | v4 判定 | 一句话（HEAD 证据位） |
|---|---|---|
| R-B1 appex 注册降级 | **真消解（修法甲）** | D-SM-0 落实表在 PLAN:49-57 文首、第 4 条 = T6'-3 + AC-T6'-4/13 全量；v3「P2 立项」显式撤销（PLAN:56/111）；S-QL 六节证据逐条实测属实；反证（QL 渲其它 grade op 独跳胶片）由 include 正面消解（S-QL-4 明写 + 装配后 QL/导出同 registry 同 builder 语义单源） |
| R-B2 测试申报 grep 化 | **真消解** | T1'-4 两批 12+1 条逐条 file:line + 现值→新值；「`:130-139` E7 零改」错误表述删除（PLAN:154 改「`:139` resolved.count 19→20…恒注册只保证 makeBox 非 nil」）；AC-T1'-5「bundle 全绿零未申报红」新增（PLAN:165）；零改 grep 证据抽 4 条全对 |
| R-M1 兄弟图 tags | **真消解（甲）** | D-SM-14+ per-target 化 + S-RM1 四节 + AC-T6'-2 第三臂；`filmTails`/`legTags` 双门同形实测（`ExportInspectorView.swift:1217-1226`）；索引形 legTags 机制 M9-2 已有 = 纯供给侧改动；`filmTails` 维持 loaded-only 与 legacy 兄弟无腿一致 |
| R-M2 预设拒绝读面 | **真消解** | 判据改层面读取（S-RM2 三节）+ `PresetError.layerOnlyOpPresent` additive + AC-T6'-9 可触发 fixture；`composeCurrent` 闭包可读 `editorState.layerStack`（`LightamerShell.swift:653-666`）实证；`makePayload` 实位（Core `PresetApplier.swift:59`） |
| R-M3 落域/RSS 门 | **真消解** | 落域 LAYERS（944MB 基线 `M2-4-0-SPIKE.md:50`，非 IOP 7654 `:34`；FilmLegTests/FilmPrintBakeTests 既落 LAYERS 先例 `BUNDLE-MAP:582-583`）+ T2'-0 基线轮提前 + AC-T2'-6 拆两条 + 100MP 只留探针轮/默认中平面 |
| R-M4 nil 无原因 | **真消解（甲）** | 预检 toast + `mergeDown` refuse 纵深防御、枚举零改；nil 三来源（`LayerStack.swift:162/169/182`）+ `mergeLayerDown` guard-let-return（`EditorState.swift:738-751`）+ `effectiveChain` public static（`HistoryStack.swift:481`）+ `LayerCoreTests:126/149/339` 三消费点全实测 |
| R-M5 封存漏行 | **真消解** | 封存表 16 行实数（第 16 行 = `LayerStack.mergeDown`）；T3' 封存面改「1 hunk 见第 16 行」（PLAN:222）；结论句改「实质 3 行 + 1 注释例外」（PLAN:366）——但结论句仍有漏计，见 r4-m1 |
| r-m1..r-m9（9 minor） | **逐条全修** | 见 §三 逐条核对表 |

---

## 一、blocking 判定（v3 两条，逐个）

### R-B1（appex 注册回归 P1）——**消解成立**

**四项要求逐核**：

1. **真纳入（populate 改法 file:line 落证）**：D-SM-15（PLAN:122）三件套——① `registry` 改 `await LightamerIOPRegistry.populate(ModuleRegistry.makeDefault())` 全量装配；② QL 进程自建 `FilmMaterialStore` + `FilmMaterialSeam` 装闭包（host bundle resource 路径分支）；③ run 内 tags 供给（Core 对等小函数或 TaskLocal 直装，二选一 SUMMARY 实报）。S-QL-1..6 六节证据我逐条亲核：
   - appex 依赖 Core+IOP 已声明（`Project.swift:270-274` `.target(name: "LightamerIOP")` 在 deps 内）——v3 担心的「appex 不能引用 IOP」被实证推翻 ✓
   - `Env.registry = ModuleRegistry.makeDefault()`（`LightamerQuickLook.swift:34-37`）+ appex 全目录 `grep populate` = 0 命中 ✓
   - `populate` = `public static func populate(_ registry:, defaultFace: Bool = false) async`（`Registry.swift:69-71`），`FilmStatsSeam.histogram` 安装在 populate 体内（`:87-93`）→「同调用顺带安装」属实 ✓
   - `QuickLookRenderer` 在 Core（`LightamerCore/Sources/Export/`），`preview/renderedPlane` 第 4 步重建 layerStack（`:270-289` `snapshot.makeLayers() → addAdjustment → processComposite`）✓；registry 为函数入参（`:112/148/224`）→「渲染体零改」成立 ✓
   - `FilmMaterialStore.init(profilesDirectories:)` public throwing（`FilmMaterialStore.swift:57-64`）✓；主进程装配先例 `Bundle.main.resourceURL + FilmProfiles/profiles + FilmProfilesBW/profiles`（`LightamerShell.swift:949-955`）✓；两 folder reference（`Project.swift:187/193`）✓；`previewLongEdge = 2560`（`LightamerQuickLook.swift:42`）✓
2. **反证正面消解**：S-QL-4 原文明写反证（「不 strip 则 QL 渲其它 grade op 而独跳胶片 = 新的不一致；QL 与导出共用同一 builder 语义分叉无单源」），解法 = include（populate + seam + tags 三件）→ QL 进程与导出同 registry 装配、同 `ExportChainBuilder`，语义单源恢复。**没有走 strip 路线，也没有静默不作为**——v3 提出的两条失败路都绕开了。
3. **AC 替换**：v3 的反向断言「迁移档预览无胶片 == legacy 基线」删除；AC-T6'-4 改正测「QL preview（2560 fit）== 导出同档同尺寸输出（ε 带，D-SM-16）」+ legacy 回归（PLAN:299）；AC-T6'-13 新增「unknownOps 不含 spektraFilm + appex→host resource 落盘验证」（PLAN:303）✓
4. **D-SM-0 落实表**：PLAN:49-57 文首登记，五行逐条有任务号 + AC 号（行 4 = T6'-3 / AC-T6'-4+13，状态「全量（v3『P2 立项』撤销）」）；PLAN:6 头部加「与 D-SM-0 冲突时以 D-SM-0 为准」总则；§0 注记显式撤销 v3 判词（PLAN:111）✓。五条生命线终态：**1/2/3/5 维持全量、4 补齐全量**——与 DECISIONS「P1 全量 PASS 才算闭环」一致。

残余（不 blocking）：r4-m2（async 装配机制留白）+ r4-m3（appex 装配面自动化可达性），见 §五。

### R-B2（测试申报 grep 化）——**消解成立**

**四项要求逐核**：

1. **两处 `GradeCatalogTests` + 两处 `V50OrderTests` 逐条列入且现值与 HEAD 一致**（我亲自 grep）：

| 条目 | HEAD 实测 | v4 申报 | 一致 |
|---|---|---|---|
| `GradeCatalogTests:39` | `items.count == 20` | 20→21 | ✓ |
| `:41-48` | 字面量数组 20 项 | 尾部追加 | ✓ |
| `:50` | `Set.count == 20` | 20→21 | ✓ |
| `:55` | `grade.count == 16` + 注释「14 Grade ops + Tint + colormatch」 | 16→17 + 注释 14→15 | ✓ |
| `:95` | `catalogOps.count == 19` + 注释「20 rows; …」 | 19→20 + 注释 20→21 | ✓ |
| `:100-109` | `newSevenOps` 10 项（含 `FilmPlacementModule.opName`，`:104` 注释「the M3-3-02 placement op」佐证 deferral 同族） | 追加 `SpektraFilmModule.opName`（判别力修复） | ✓ |
| `:139` | `resolved.count == 19`（循环体 `:134` 遍历全部 items） | 19→20 + 「E7 零改」撤销 | ✓ |
| `:144-166` | `expected` 字典 20 项（函数声明 `:144`） | 加 `"spektraFilm": .grade` | ✓ |
| `:193-205` | `lightamerGradeRows` 12 项 | 加 46.7 成 13 项 | ✓ |
| `:228` | 「the eleven LIGHTAMER rows are unique」 | → thirteen | ✓ |
| `V50OrderTests:24` | `entries.count == 108` | 108→109 + 说明串补 | ✓ |
| `:284-293` | `nativeRows` 15 项（未含 spektraFilm） | 追加 `"spektraFilm"` | ✓ |
| `CatalogAddFaceTests:233-239` | add-face 期望数组 **14 项** | 14→15 尾部追加 | ✓ |

2. **`:294` 不动算术成立**：加行后 entries=109，nativeRows 15+1=16，stripped = 109−16 = 93 ✓（v4 明写「追加后 stripped 仍 93」）。`filmic<lut3d<colisa` 列表序断言（`:300-307` firstIndex 比较）在「`('filmicrgb', 46.0)` 后插入」下 filmic 仍 < lut3d → 不破 ✓（AC-T1'-1 的「列表索引之间」措辞与该断言自洽）。
3. **「凡零改必带 grep 证据」执行**（抽 4 条）：① `DefaultFaceTests` 四计数（HEAD `:365` ops==19 / `:370` defaultFaceOps==16 / `:388` names==16 / `:414` fullNames==19）——IopCatalog 手写静态表不加行（T6'-6「IopCatalog 不加行」）→ 零改推理成立 ✓；② `NodeOwnershipCatalogTests:88` `expectedNonGrade == 13`——face = 终端三件 + `editingDefaultInstances(defaultFace:)`，spektraFilm 不 seed（T1'-3）→ face 不增 → 零改成立 ✓（且 spektraFilm owner=.grade，即便进 face 也不入 nonGrade，双保险）；③ `SidecarSeedTopUpTests` 自持两行 seed 夹具（文件内私有 fixture，与 GradeCatalog 无耦合）✓；④ 46.7 全表空位——`grep -rn "46\.7"` 源码/测试零命中 ✓。**执行**：我的全仓广扫（`entries.count` / `GradeCatalog.items.count` / `catalogOps.count` / `resolved.count` / `filmicrgb` 邻域）未发现第 13 条未申报红。
4. **AC-T1'-5 已加**：PLAN:165「T1' 完成后 `test-direct.sh --bundle <域>` 全绿，零未申报红（红 = 本 T 编辑点 4 未列出的断言）」——全批第一道门 ✓。

---

## 二、v3 五 major 抽查（逐条）

### R-M1 导出兄弟图 tags —— **修法自洽，判定 PASS**

- **修法**：(甲) per-target 解析（D-SM-14+，PLAN:121）——loaded 位旧路、兄弟位从各 target `readDocument().layerStack` 的 spektraFilm 实例 params 经 `resolveLegTags` 解析（无实例 = nil）；`filmTails` 维持 loaded-only。
- **自洽性**：legacy 时代兄弟图 `filmTail=nil` 无胶片、module 档兄弟图 46.7 box 在各自链上会渲胶片（`ExportRenderer.swift:421-430` per-target readDocument + `:491-499` 层重建 + processComposite）——所以「供给 tags」与「`filmTails` loaded-only」**不矛盾**：film 腿的载体从 legacy carrier 换成链上 box 后，tags 才成为兄弟图的必需品，而 `filmTails` 通道（legacy carrier）对兄弟图保持 nil 恰与 legacy 行为逐位一致。R-M1 修的正是「module 新语义下 tags 缺失」，不是 legacy 通道。
- **HEAD 可行性**：`legTags` 索引形数组（`ExportInspectorView.swift:1223-1226`）M9-2 已有，enqueue→`$requestTags` per-job TaskLocal 管道现成 → **纯供给侧改动**；`readDocument` public static（`ExportRenderer.swift:852-861`）；store 同进程可达（`PipeCoordinator.swift:1050-1063` `filmMaterialStore` 公开读）；v3 注记的 rms memo 归属已处理（T4'-1「rms 经形参注入——`rmsTableBox` memo 留 coordinator 内」，`publishedRmsForFilmStock` 确为 private static `:920+`）✓。
- **AC**：AC-T6'-2 第三臂「同一批不同 grade 的 module 档批量导出，兄弟图输出 == 各自 grade 下 legacy 腿同 record 输出（ε 带）」可机检（夹具双侧可控）✓。
- 残余实现细节（不立项）：`makeRunAssembly` 取 rms 需 coordinator 一个公开 accessor（PLAN 未点名，executor 自明）。

### R-M2 预设拒绝读面 —— **读面真实可达，判定 PASS**

- v3 指出 `composeCurrent` payload 无层内 spektraFilm → v4 判据改**层面读取**：S-RM2-2 实证 `composeCurrent` 闭包组装点同文件可读 `editorState.layerStack`（`LightamerShell.swift:653-666` 闭包内确在读 `editorState.layerStack` 组 layerRecord）→ 判据前检查 `compositeLayers` 各 chain（复用 `hasSpektraFilmInstance` 单源谓词）**真可达** ✓。
- `createPresetFromCurrent`（`PresetController.swift:136-149`）与 `PresetsStore.create`（无 layerStack 形参，`:212-218`）实测同 v3 所述；`PresetError` 为 public enum（`:29-44`）→ `layerOnlyOpPresent` additive 成立 ✓。
- AC-T6'-9 改可触发形态（fixture 档 → typed 错误 + `PresetsStore` 无新文件 + `makePayload` 防御过滤断言）✓；`makePayload` 实位 Core `PresetApplier.swift:59` ✓（Core Presets 非封存，但见 r4-m1 申报口径）。
- 附带核实：闭包本就传 `layerStack:` 给 `PastePayload.compose`（payload 有层结构字段，只是 create 不收）——v4「payload 路径防御过滤为第二道」的分层判断与该事实吻合。

### R-M3 落域 vs RSS 门 —— **判定 PASS**

- `Scripts/test-direct.sh:78` `RSS_LIMIT_MB=8192` 宿主级 `ru_maxrss` 门实测 ✓；IOP 基线 7654MB / LAYERS 944MB（`M2-4-0-SPIKE.md:34/50`）✓；`FilmLegTests`/`FilmPrintBakeTests` 既落 LAYERS（`BUNDLE-MAP:582-583`）先例 ✓。
- v4 三修全落：`SpektraFilmTests` 落 LAYERS（T2' 编辑点 5「BUNDLE-MAP SpektraFilmTests 行落 LAYERS」+ §0.2 表 T2' 行）；T2'-0 基线轮提前（PLAN:174，门算式 = 基线 + 本批 ≤8192）；AC-T2'-6 拆两条——(i) 自持面计数默认跑（合成平面）、(ii) 100MP 只留 `LIGHTAMER_PERF_PROBE=1` 探针轮 + 默认套件中平面 ≤2K（PLAN:191）。LAYERS 944MB + ≤2K 夹具 ≪ 8192；探针轮 100MP 面 1.6-3.2GB + 944 ≈ 2.5-4.1GB < 8192 → 两态都不贴门 ✓。v3 指出的「断言 skip 但分配照跑推爆宿主」死结随落域 LAYERS + 默认中平面**双解** ✓。

### R-M4 MergeDownOutcome reason 枚举 —— **零波及判定 PASS**

- v4 钉修法 (甲)：`mergeLayerDown` 开头预检（`effectiveChain` 扫 spektraFilm → toast + return，不调 `mergeDown`）+ `LayerStack.mergeDown` refuse hunk 保留为纵深防御；`MergeDownOutcome` 枚举**零改**（S-RM4-4 + T3'-3 grep `case refused` 零命中机检）。
- **对既有调用方的波及 = 零**：`LayerCoreTests:126`（`.mergedIntoLayer` 断言）/`:149`（`.mergedIntoBase` 断言）/`:339`（retouch refuse `XCTAssertNil`）三消费点在枚举零改下全部不受扰 ✓（实测三行确为该三形态）。
- HEAD 前提全实证：enum 两 case（`LayerStack.swift:76-88`）、nil 三来源（`:162-164` 无此 id / `:169-172` retouch restore+nil / `:182-187` 下层非 chain）、`mergeLayerDown` nil 直接 return（`EditorState.swift:738-751`）、`effectiveChain` `public static`（`HistoryStack.swift:481`）✓。
- 附注（不入 finding）：S-RM4-1 称该 enum「internal」——实际上 `mergeDown`（public extension 成员）以它为返回值且 `EditorState:745` 对 App 暴露 pattern-match，可视为模块外可见；v4 修法不动枚举，该措辞瑕疵零设计影响。

### R-M5 封存表 16 行 —— **判定 PASS（附 r4-m1）**

- 封存表实数 **16 行**（PLAN:347-364，我逐行数过），第 16 行 = `LayerStack.mergeDown`「Core Layers 实质 1 hunk…非封存面但逐 hunk 申报 + 枚举零改」✓；T3' 封存面改「`LayerStack.mergeDown` 1 hunk（见封存表第 16 行）」（PLAN:222）——v3 的 T3'「封存面：无」自相矛盾已消 ✓；结论句改「实质 3 行（V50Order/GradeCatalog/LayerStack）+ 1 注释例外（PixelPipe）」（PLAN:366）✓。
- AC-T8'-2 对账式改「封存 diff == 申报终表（16 行）」✓。
- 残余：结论句「实质 3 行」仍漏计 R-M2 修法带入的 Core Presets 两处 hunk（`PresetError.layerOnlyOpPresent` additive case + `PresetApplier.makePayload` 防御过滤）——见 §五 r4-m1（minor）。

---

## 三、9 minor 逐条核对 + ΔN 算术

| v3 minor | v4 落点 | 核对 |
|---|---|---|
| r-m1 ΔN 算术 | §0.2（PLAN:127-140） | **PASS**：分项 T1'=7（1+5+1）/ T2'=15（4+2+2+5+2）/ T3'=14（2+3+8+1）/ T4'=15（5+6+2+2）/ T5'=4 / T6'=28（4+4+5+3+3+2+4+2+1）/ T7'=18（12+6）/ T8'=0 → **7+15+14+15+4+28+18+0 = 101** ✓；净增 101−4 = **97** ✓；FilmCardTests 4 法退役实证（`FilmCardTests.swift` 恰 4 个 test 法）✓；v3→v4 增量表（PLAN:140）95→96（r-m1 纠算）→+5（T3' +1、T6' +4）= 101 自洽 |
| r-m2 49 文件 | T7'-4（PLAN:316） | **PASS**：改「按 BUNDLE-MAP 的 film/spectral 行集为准，不写死数字」+ HEAD 实测 49 注记 |
| r-m3 AC-T1'-1 | PLAN:161 | **PASS**：补「`V50OrderTests` 两处计数断言同批改（r-m3）」 |
| r-m4 strip 措辞 | T6'-3（PLAN:281） | **PASS**：改「`runtimeLayers` 各层 `chain` 过滤 `opName == spektraFilm`」——与 HEAD 结构吻合（`SessionThumbnailProvider.swift:508-518` 确为 `degradedLayerStack → runtimeLayers → addAdjustment`，非 records 列表） |
| r-m5 reject 限定 | T3'-2（PLAN:207） | **PASS**：补「仅 `opName == spektraFilm` → …（r-m5：film 语义 op（grain 等）不受影响；`FilmPanelModel.applyRecommendedGrainStrength` 走 grain record 不误伤）」 |
| r-m6 logger 断言 | AC-T2'-8（PLAN:193） | **PASS**：钉死「blitIdentity + 不 crash + 不 throw（行为断言；logger 不断言）」 |
| r-m7 cancel 键 | T4'-4（PLAN:237）+ AC-T8'-2 | **PASS**：点名「cancel 复用 **`alert_cancel`**」 |
| r-m8 ±10% | T8'-3（PLAN:335） | **PASS**：删耗时子句，改「缩略图 grid 目视（与编辑器同档观感一致，都无胶片，r-m8）」 |
| r-m9 计数槽 | AC-T2'-6 + D-SM-12R+（PLAN:120） | **PASS**：拆两条（自持面计数 ≤1 + ΔRSS 参考断言非门）；计数槽 `liveSurfaceCount` 照 `FilmStatsSnapshot.last` advisory 先例**显式申报为测试缝**（生产读零消费者 grep 机检）；mix 面注记入 D-SM-12R+ |

**9/9 逐条修，无偷偷降级、无空转改写。**

---

## 四、v4 新引入面逐项核（HEAD 可行性）

| 新面 | PLAN 定位 | HEAD 可行性核 | 判定 |
|---|---|---|---|
| QL appex populate 依赖方向 | S-QL-1 / D-SM-15① | appex deps **已含** `.target(LightamerIOP)`（`Project.swift:270-274`）——非新增依赖，host 携带 Frameworks + runpath 解析注释在位；`populate` public async + `defaultFace` 缺省 → appex 一行 `await populate(registry)` 可达 | **可落** |
| QL material seam 装配 | D-SM-15② | `FilmMaterialStore.init(profilesDirectories:)` public throwing；host bundle resource 分支有 Shell 先例可抄（`:949-955`）；两 folder reference 在位——appex `Bundle.main` = appex bundle、folder ref 物理在 host Resources，PLAN 已如实写「须 host bundle 取 resource + 落盘测试验证」 | **可落**（resource 路径 = 执行期验证项，PLAN 已标注） |
| QL tags 供给 | D-SM-15③ | `QuickLookRenderer` 入参 `registry` 已存在（`:112/148/224`）；TaskLocal 沿 async 上下文传播——appex 侧包 `QuickLookRenderer` 调用即达 FilmPrintBake 消费点，渲染体零改成立；Core 对等小函数备选（appex 不能 import App target，PLAN 如实写二选一） | **可落** |
| D-SM-16 QL/导出 parity | PLAN:123 | `previewLongEdge = 2560` 实位；`QuickLookRenderer` 在 Core（可测 target 直调）；D-SM-9R ε 带口径复用 | **可落** |
| 兄弟图腿（per-target legTags） | D-SM-14+ / T6'-2 | 索引形 legTags + per-job TaskLocal 机制 M9-2 已有；per-target `readDocument` public；App import IOP 解 Params 现成 | **可落** |
| reason 枚举波及 | T3'-3 / S-RM4 | 修法甲 = 枚举零改 → `LayerCoreTests:126/149/339` 与一切 `mergeDown` 调用方**零波及** | **零波及** |
| `resolveLegTags` 纯函数出体 | T4'-1 | 解析体（`PipeCoordinator.swift:881-919`）四项依赖（record/store/PaperGradeTable/SpectralConstantsData）+ rms 注入——verbatim 出体可行；rms memo 留守声明诚实 | **可落** |
| T2'-1 resolver pristine 门 | PLAN:175 | v3 链路复核的「pristine 档每帧 error 日志」噪声回归已接（`guard !stock.isEmpty` 或 module 侧 `isFilmRecordDefault` 提前恒等，二选一 SUMMARY 实报）；`isFilmRecordDefault` App 侧在位（`PipeCoordinator.swift:856`） | **可落** |
| sidecar v13 零 bump / process 不 bump | §0 / AC-T3'-1 / AC-T8'-1 | `schemaVersionCurrent == 13`（`LightamerSidecar.swift:269`）✓；`RenderProcessVersion.current == 3`（`RenderProcess.swift:92`）✓——两 AC 现值口径与 HEAD 一致 | **可落** |
| ΔN 101/97 | §0.2 | 见 §三 r-m1 行 | **算术自洽** |

---

## 五、本轮新增 findings（3 minor，均不阻断）

### r4-m1 — 封存结论句「实质 3 行」漏计 Core Presets 两处 hunk

- **定位**：PLAN:366 结论句 + 封存表 16 行（PLAN:347-364）。
- **事实**：R-M2 修法带入两处 **Core 既有文件**实质改动——① `PresetsStore.swift` 增 `PresetError.layerOnlyOpPresent` additive case（S-RM2-3 自述「Core Presets 非封存」）；② `PresetApplier.makePayload` 防御过滤 hunk（T6'-7(a)「`PresetApplier.makePayload` 防御过滤为第二道」，函数实位 `LightamerCore/Sources/Presets/PresetApplier.swift:59`）。两者既不在 16 行封存表（表只收封存件，Presets 两件非封存——形式上合规），也不在结论句「实质 3 行 + 1 注释例外」的实质面清单里——而该句的自我定位是全批实质 Core diff 面的总账（v3 R-M5 就是同一类缺口）。
- **影响**：AC-T8'-2（封存 diff == 16 行终表）不受扰（两件非封存件）；仅总结账口径失真。
- **修法**：结论句改「实质 3 行 + 1 注释例外 + Core Presets 非封存两处小 hunk（PresetError additive case / makePayload 过滤）」；或把 makePayload 防御过滤改到 App 调用点过滤（`PresetController.swift:114` 取 payload 后剔份），Core 只留 additive case。

### r4-m2 — D-SM-15① async 装配机制留白

- **定位**：D-SM-15①（PLAN:122）/ S-QL-6（PLAN:72）。
- **事实**：`Env.registry` 现为 `static let`（`LightamerQuickLook.swift:34-37`），而 `populate` 是 `async`（`Registry.swift:69-71`）——`static let` 闭包内不能 `await`，装配机制（semaphore 等待 Task / lazy async computed / principal class init 内 await 后写 static var 等）PLAN 未钉；S-QL-6 只写「registry 改 populate 后实例」，机制面留白。
- **影响**：appex 无单测 target，该缝只有 T8'-3 走查兜底；机制选错（如在 static let 初始化里死等）会引入首帧阻塞或死锁风险。
- **修法**：PLAN 注记一行「装配机制 = 执行 lane SUMMARY 实报」（与 D-SM-15③「二选一实报」同款先例），并禁 static let 初始化内无界等待。

### r4-m3 — AC-T6'-13 的 appex 装配面自动化可达性注记

- **定位**：AC-T6'-13（PLAN:303）。
- **事实**：「QL registry `unknownOps` 不含 spektraFilm（populate 装配断言）」在测试进程调 `LightamerIOPRegistry.populate` 即可断言（等价形态：`makeBox("spektraFilm")` 非 nil）——但这测的是 Registry 行为，**appex `Env` 内的实际装配代码**无测试 target 可达（appex source 不入任何单测 bundle）；「appex→host resource 路径落盘验证」同理——若 host-bundle 路径解析做成 Core 内带 `Bundle` 形参的 helper 则可测，PLAN 未钉该形态。
- **影响**：AC 的两条断言可落但存在「测了 Registry ≠ 测了 appex 接线」的口径缝；真实保障 = T8'-3 走查的「QL preview 观感（与导出同档一致，R-B1）」项（在位）。
- **修法**：AC-T6'-13 措辞补「appex `Env` 装配面与 resource 路径由 T8'-3 走查兜底；resource 解析 helper 落 Core 带 `Bundle` 形参（可测形）」。

---

## 六、终判与复审节点

### 结论

**PASS / 0 blocking + 0 major + 3 minor**

- v3 的 2 blocking（R-B1 appex 降级 / R-B2 测试申报不全）**真消解**——R-B1 走修法 (甲) 补齐 D-SM-0 第 4 条生命线且证据面全部经 HEAD 亲核；R-B2 两批申报与 HEAD 逐位一致且我的独立广扫未发现遗漏。
- v3 的 5 major **真消解**（R-M1 修法自洽 / R-M2 读面可达 / R-M3 落域+双解 / R-M4 零波及 / R-M5 16 行闭环）。
- v3 的 9 minor **逐条全修**。
- v4 新引入面（QL 装配 / 兄弟图腿 / parity 口径 / ΔN）**无不可行项**。
- 本轮 3 minor（r4-m1/r4-m2/r4-m3）均为申报口径与机制注记级，可随执行批 SUMMARY 顺手消解，**不构成 re-plan 门槛**。

### 复审节点（回注 orchestrator）

1. 3 minor 可直接随执行批消解（r4-m1 结论句补记或过滤点挪 App；r4-m2 机制实报注记；r4-m3 AC 措辞补走查兜底），无需第五轮全量复审。
2. 若 orchestrator 认为需第五轮，仅核 §五三条 + 执行 HEAD 的 T1' 首轮（AC-T1'-5 零未申报红是天然收敛点）。
3. execute 派遣可启动：T1' 为首个执行任务，按 PLAN:389「AC-T1'-5 为全批第一道门」执行。

---

## 七、验收自查

- [x] 基线亲核：HEAD `da5d9fb7`；`git diff --stat 0d7d0e90 da5d9fb7` 仅 PLAN + 两个 prompt/log 文件——源码面与任务书基线 `0d7d0e90` 一致，基线有效。
- [x] R-B1 逐项判定（纳入落证 / 反证消解 / AC 替换 / D-SM-0 表）——S-QL 六节证据全部 HEAD 实测。
- [x] R-B2 逐项判定（12+1 条现值 grep 一致 / `:294` 算术 / 零改抽 4 条 / AC-T1'-5 在位）+ 独立全仓广扫无第 13 条。
- [x] v3 五 major 逐条抽核（全 PASS，附 2 条注记级残余）。
- [x] 9 minor 逐条核对（9/9 全修）+ ΔN 分项算术（101/97）复核。
- [x] v4 新引入面 10 项 HEAD 可行性逐个核（重点：appex 依赖方向 / 兄弟图腿 / reason 枚举波及）。
- [x] 每条判定带 HEAD file:line 实测证据；未修改 PLAN；零 commit / 零构建 / 零测试。
- [x] 唯一产出 = 本文件（chunked 追加 5 段；首段 10.8KB 略超 8KB 限额——如实登记，其余四段各 3.0/5.1/5.8/4.3KB；终件 29,037B，U+FFFD = 0）。
- [x] 结论头 `PASS / 0 blocking + 0 major + 3 minor`。

### 亲核心证抽查（本轮 ≥6 个关键判定）

| # | 判定对象 | 结果 | 证据 |
|---|---|---|---|
| K1 | v4 申报「appex 依赖 IOP 可达」 | **PASS** | `Project.swift:270-274` deps 含 `.target(name: "LightamerIOP")` + runpath 注释 |
| K2 | v4 申报「appex grep populate 零命中」 | **PASS** | 实测 0 命中；`Env.registry = ModuleRegistry.makeDefault()`（`LightamerQuickLook.swift:34-37`） |
| K3 | v4 申报「`:139` resolved.count 19→20 必改」 | **PASS** | `GradeCatalogTests.swift:139` = `XCTAssertEqual(resolved.count, 19, …)`，循环体 `:134` 遍历全部 items |
| K4 | v4 申报「`:294` stripped 93 不动」 | **PASS** | nativeRows 15 项（`:284-293`）+ 追加后 109−16=93；`filmic<lut3d<colisa`（`:300-307`）插入后不破 |
| K5 | v4 申报「46.7 全表空位」 | **PASS** | `grep -rn "46\.7"` 源码/测试零命中；`V50Order.swift:171` filmicrgb=46.0 |
| K6 | v4 申报「`expectedNonGrade == 13` 零改」 | **PASS** | face = 终端三件 + seed（`NodeOwnershipCatalogTests:66-71`），spektraFilm 不 seed 不进 face |
| K7 | v4 申报「composeCurrent 闭包可读 layerStack」 | **PASS** | `LightamerShell.swift:653-666` 闭包内实读 `editorState.layerStack` 组 layerRecord |
| K8 | v4 申报「`MergeDownOutcome` 三消费点」 | **PASS** | `LayerCoreTests.swift:126`（mergedIntoLayer）/`:149`（mergedIntoBase）/`:339`（retouch XCTAssertNil） |
| K9 | v4 申报「filmicrgb 46.0 后插入」 | **PASS** | `V50Order.swift:171` `("filmicrgb", 46.0)`；`:174` lut3d=36.0（列表序宿位） |
| K10 | v4 申报「FilmCardTests −4」 | **PASS** | `FilmCardTests.swift` 恰 4 个 `func test` |
| K11 | v4 申报「schemaVersionCurrent 13 / process current 3」 | **PASS** | `LightamerSidecar.swift:269`；`RenderProcess.swift:92` |
| K12 | v4 申报「`makePayload` 防御过滤」落点 | **PASS（实位）+ r4-m1** | `LightamerCore/Sources/Presets/PresetApplier.swift:59` public static——实位在，但 Core 既有文件 hunk 未入结论句总账 |
