# spektra-module P1 PLAN **v3** 复审（zcode review lane，第三轮）

> 审对象：`.work/gsd/phases/spektra-module/PLAN.md`（64,193B / 453 行，v3，2026-11-03 21:05 落盘）。
> 闭合对照：`SM-PLAN-REVIEW-V2.md`（FAIL / 4 blocking + 8 major + 10 minor）、`SM-PLAN-REVIEW.md`（v1）。
> 设计正本：`RESEARCH.md`。用户裁决：`DECISIONS.md`（**D-SM-0 全量五条生命线不降档**）。
> 基线：`git rev-parse HEAD` = `f32cb76b`；`git merge-base --is-ancestor 25e01172 HEAD` 成立，且 `git diff --stat 25e01172 HEAD` 仅两文件（`DECISIONS.md` + `sm-replan3-prompt.md`）——**源码面与任务书基线 `25e01172` 逐字节一致**，基线有效。
> 纪律：只读；零 commit / 零构建；唯一产出 = 本文件（chunked 追加）。全部判定基于 HEAD 亲核 file:line。

---

## 结论头

**FAIL / 2 blocking + 5 major + 9 minor**

一句话：v3 的方法论转向（先缝验证后写设计）见效——`§缝验证` 七节（S-B1..S-B4/S-M3/S-M4/S-M6/S-DSM11）的 HEAD 事实**逐条复核属实**（`FilmStatsSeam` 形态、`attachFilmStore` 落点、`runProcessMigration` 双门、`mergeDown` retouch refuse 同缝、QuickLook 三件 registry、写入面双进、通用层腿、`gradeScopeEntries` static 都实测对得上），v2 的 B1/B3/B4 与 M1/M2/M6/M7 **真消解**。但两处承重面仍未闭合：①**用户裁决 D-SM-0 第 4 条生命线（appex 注册）被 T6'-3 显式降级为「P2 立项」**，且 PLAN 全文未登记 D-SM-0（`grep D-SM-0` 零命中）；②**既有测试改写申报第三轮仍不全**——`GradeCatalogTests:139` 的 `resolved.count == 19` 必红（而 PLAN 明写「`:130-139` E7 零改（恒注册即过）」= 与 HEAD 事实直接相反），`V50OrderTests:24` 的 `entries.count == 108` 与 `:284-293` 的 `nativeRows`/`:294` `stripped.count == 93` 也必红且完全未申报。T1' 首轮即红，AC-T1'-3 不可达。

| v2 finding | v3 判定 | 一句话（HEAD 证据位） |
|---|---|---|
| B1 材料解析缝 | **真消解** | 缝形态与 `FilmStatsSeam` 同构属实（`FilmTailPolicy.swift:542-570` / `Registry.swift:88`）；安装点 `attachFilmStore` 在位（`PipeCoordinator.swift:1109-1111`）；闭包类型全 Core（`FilmProfile` 为 Core public struct，`FilmMaterialStore.swift`/`FilmProfile.swift:99`），IOP→Core only（`Project.swift:144`）成立 |
| B2 tags 供给 | **部分消解** | 预览腿链路成立（`renderCurrentChain` TaskLocal 包住 `processComposite`，`PipeCoordinator.swift:2807-2815`）；但**导出兄弟图**在 module 档仍恒 nil（`ExportInspectorView.swift:1218-1224` 的 per-target 门），新架构下「有胶片无 grade/filter」是 legacy 时代不存在的新语义 → 见 M2 |
| B3 动作面 guard | **真消解** | `:1028-1030` guard + `:1037-1045` 两支实测在位；`recordLayerChange` 第三支可达（`EditorState.swift:1151-1156`）；AC-T4'-4 的「点击后 process 号真翻」可机检（`setProcessVersion` 在 guard 之后，`:1031`） |
| B4 merge 蒸发 | **真消解（机制细节留 major）** | `mergeDown` retouch refuse 同缝属实（`LayerStack.swift:165-172`，restore + nil）；`mergeLayerDown` nil 分支 stack 不写回（`EditorState.swift:741-749`）→ 层原地、零数据丢失；但 refuse 与其他 nil 原因共享返回值，toast 区分机制未给 → M5 |
| M1 ε 带 | **真消解** | 推导表 + slope 实测钉死 + 方向修正（高光 ≤ 中段）+ 99.5% 分位 / max 10× / 外推单列 + 样本集写死 + 双向 AC（实测 ≤ 推导上界）齐全 |
| M2 env 语义 | **真消解** | 选 (a) 成立且与 M5(a) 恒注册自洽：`degradedForUnknownOps` 判据是 `makeBox == nil`（`LightamerSidecar.swift:1152`），恒注册下永不触发 → 删 degrade 子句是**唯一正确**修法 |
| M3 渲染入口 | **部分消解** | 两条 strip 落点 HEAD 可行（`AdjustmentLayer` 全参 public init `:54-74`；provider 物化层非封存）；**QL 处置与 D-SM-0 冲突** → 本轮 blocking 1 |
| M4 写入面 | **部分消解** | (b) 双进点属实（`AdjustmentTransfer.swift:215/237`）且修法可落；(a) 拒绝判据的**读面未定**（`composeCurrent` 只回 `payload.instances`，层内 spektraFilm 根本不在其中）；(c) 与 (b) 职责重叠 → M3 |
| M5 落域/RSS | **部分消解** | 绝对门 + 基线轮方向对；但 `SpektraFilmTests` 落域只写「IOP/Core 级」，IOP 基线 7654MB（`M2-4-0-SPIKE.md:34`）；且 AC-T2'-6 是 skip 探针 → 门只在探针轮生效 → M4 |
| M6 live 腿 | **真消解** | 通用层腿实测在位（`PipeCoordinator.swift:2028-2040` 的 `layerID` 分支、`:2050-2078` 的 `layerScope` commit 分支）；`usesModuleLeg` 单源 + AC-T6'-12 齐全 |
| M7 封存/D-SM-1 | **真消解** | 五行补齐（PLAN:426-430）；D-SM-1 证伪改「需 re-plan」；AC 提前到 T2'（AC-T2'-10）；选型下「零 diff」申报**诚实**（TaskLocal 路不改两文件签名 = 真零改） |
| M8 scratch | **真消解** | 不借 allocator 的方向对（`Leg` 三值 `SpectralScratchAllocator.swift:49-53` + `claim` 抛错 `:149-157` 实测属实）；自持 ≤1 张在七步链上可达（步骤②订明第一跳直写 `output`），spectral 内部面 legacy 同款 → 仅 AC 口径待拆（本轮 r-m9，minor 级） |

> **编号约定**：上表 B1..B4 / M1..M8 是 **v2 报告编号**（闭合对照）。本报告的**新 finding** 用 `R-B1/R-B2`（blocking）、`R-M1..R-M5`（major）、`r-m1..r-m9`（minor）区分。

---

## 一、blocking（2，本轮新增）

### R-B1 — D-SM-0 第 4 条生命线被静默降级：QuickLook appex 注册判「P1 不纳入 = P2 立项」

**定位**：PLAN:339（T6'-3 渲染入口清单第 4 条）、AC-T6'-4（PLAN:360「QuickLook P1 不纳入（迁移档预览无胶片 == legacy 基线）」）、T8' 产物清单（PLAN:404「QuickLook P1 不纳入」）、D-SM-0 第 4 条（`DECISIONS.md`：**「appex 注册（M3）：QuickLook registry 仅三件，spektraFilm 恒 unknown op」**）。

**裁决原文与 PLAN 的冲突（亲核）**：

1. `DECISIONS.md` 五条生命线第 4 条把「appex 注册」与材料缝、tags、merge、scratch **并列**为 P1 必需项，并写死「**禁拆 P1a/P1b**」「分档会造出半成品态——**比不做更糟（用户可见的假功能）**」「**P1 全量 PASS 才算闭环**」。
2. PLAN:339 的原文是「QuickLook：**P1 不纳入**（恒无胶片，与 legacy 一致；DECISIONS 登记；**appex 加 populate = P2 立项**）」——这是把生命线 4 整条推到 P2。
3. `grep -n "D-SM-0" PLAN.md` **零命中**：PLAN 全文（含 §v3 changelog、§0 裁决冻结、§0.1 判定）没有任何一处登记这条用户裁决，也没有任何一处说明「第 4 条为何不适用」。§v3 changelog 的 M3 行（PLAN:28）只写「QL = P1 不纳入（恒无胶片，与 legacy 一致）」，把「与 legacy 一致」当作免责理由——但 D-SM-0 的语义恰恰是「legacy 无胶片不算理由，module 化后必须一致」。

**为何不能以「与 legacy 一致」免责（亲核事实）**：

- legacy 时代 QL 无胶片是**架构性缺失**：appex 的 registry = `ModuleRegistry.makeDefault()`（`LightamerQuickLook.swift:36`，仅 `colorin/colorout/gamma` 三件，`ModuleRegistry.swift:44-58`），且 appex 全文件无 `LightamerIOPRegistry.populate` 调用。
- 但 module 化后这条缺失的**性质变了**：`QuickLookRenderer` 走 `ExportChainBuilder` + `materializeBoxes`（`QuickLookRenderer.swift:254`），`document?.layerStack` 会被重建并进 `processComposite`（`:270-289`）。**若同批不做 strip，则 QL 会渲染层内 spektraFilm 之外的 grade op、却独独跳过胶片** ——这恰好是 D-SM-0 定义的「用户可见的假功能」（同一文档，Finder 预览与编辑器观感不一致）。
- 反之若要做 strip（PLAN 未写），则「P1 不纳入」并不成立，因为 strip 本身就是对 QL 路径的改动。**PLAN 两条路都没走通：既没做 populate，也没做 strip。**

**后果**：

- 用户裁决的核心约束（「P1 全量」）被绕过而 PLAN 未申报 → **评审无法判定这属于「用户已同意降档」**（DECISIONS 里没有任何 P1 例外条款）。
- AC-T6'-4 的第三子句「迁移档预览无胶片 == legacy 基线」是一个**反向断言**（断言 QL 不渲染），会把降级固化成机检通过项——后续修复需要推翻一条 AC。
- 更严重：`ExportChainBuilder` 路径在 QL 与**导出**共用（`ExportRenderer.swift:460` 同一 `materializeBoxes`）。PLAN 让导出 include（T6'-2）、QL 不纳入，则两条共用同一 builder 的路径给出**相反**的胶片语义，而 builder 本身零改——语义分叉落在调用方，无单源。

**修法（二选一，须 orchestrator 裁决；任一必须写入 DECISIONS）**：

- **(甲) 补齐生命线 4**：T6' 增编辑点——appex 侧装 registry（`LightamerQuickLook.swift` 的 `Env.registry` 改为经 `LightamerIOPRegistry.populate` 填充，或增一个最小 `populate` 变体只注册 spektraFilm）+ 装 `FilmMaterialSeam` 闭包（appex 进程自带 `FilmMaterialStore`，FilmProfiles 已在 app bundle 的 folder reference `Project.swift:187/193`，appex 经 host bundle 取 resource 需验证路径）。AC 改为「QL render 含 46.7 实例输出 == 导出同档输出（ε 带）」。
- **(乙) 显式申请降档**：向用户提请，把 D-SM-0 第 4 条改成「P1 不纳入，P2 立项」，理由写「appex 需独立 registry + 独立 material store 装配，属独立装配面」。**批准后**才能保留 PLAN:339，且 AC-T6'-4 第三子句必须改为「**已知缺口**：QL 无胶片（DECISIONS 登记）」而不是「== legacy 基线」。

> 评审倾向 **(乙)**（成本/风险最低，且 QL 观感回归不构成数据损坏），但**必须由用户点头**——D-SM-0 是用户裁决，评审无权在 PLAN 里看到它被静默降级。

### R-B2 — 既有测试改写申报第三轮仍不全：`GradeCatalogTests` 两处 + `V50OrderTests` 两处必红且未申报

**定位**：T1' 编辑点 4（PLAN:214）、PLAN:214 末尾的「`:130-139` E7 零改（恒注册即过——仍列为验证项）」、「§执行纪律」末尾的「既有测试改写申报」（PLAN:452）。

**HEAD 亲核（逐条）**：

| # | 文件:行 | 现状 | PLAN 申报 | 结果 |
|---|---|---|---|---|
| 1 | `GradeCatalogTests.swift:39` | `GradeCatalog.items.count == 20` → 21 | ✅ 已申报（`count 20→21`） | 会红，已列 |
| 2 | `:41-48` | `catalogID` 字面量数组 20 项 → 21 | ✅ 已申报（尾部追加 `"spektraFilm"`） | 会红，已列 |
| 3 | `:50` | `Set(...catalogID).count == 20` → 21 | ✅ 已申报 | 会红，已列 |
| 4 | `:55` | `grade.count == 16` → 17 | ✅ 已申报 | 会红，已列 |
| 5 | `:95` | `catalogOps.count == 19` → 20 | ✅ 已申报 | 会红，已列 |
| 6 | **`:100-109` `newSevenOps` 白名单** | 该集合是「seed-deferred」清单，含 10 个 op（`Cat02WB…Colormatch`）；`alignedOps = catalogOps.subtracting(newSevenOps)` 后断言 `alignedOps.isSubset(of: face)`（`:108-110`）。spektraFilm 不在清单内 → 进 `alignedOps` → 断言「这些 op 必须 default-face registered」。**恒注册下 spektraFilm 确实 registered，所以此断言不会红**——但语义错：spektraFilm 是 panel seed-deferred 族（T1' 明写「`editingDefaultInstances` 不 seed」，与 filmPlacement 同族，HEAD `:104` 注释把 placement op 列在此清单内），不进白名单 = 测试声明它是「aligned preexisting op」。 | ❌ **未申报** | 语义错（绿但判别力丢失；后续若有人把 spektraFilm 从恒注册改回条件注册，本测试不会报警） |
| 7 | **`:139` `resolved.count == 19`** | `testAllCatalogOpsAreDefaultFaceRegistered` 遍历全部 `GradeCatalog.items` 并计数唯一 op → spektraFilm 加入后唯一 op = 20 | ❌ **未申报**，且 PLAN 明写「`:130-139` E7 零改（恒注册即过）」——**该行恰在 `:130-139` 区间内**，与 HEAD 事实直接相反 | **必红** |
| 8 | **`:145-166` `testOwnerMatrixOverAllEighteenRows` 的 `expected` 字典** | 20 项 `[catalogID: NodeOwnership]`，循环 `for item in GradeCatalog.items` 断言 `item.owner == expected[item.catalogID]`（`:167-169`）→ spektraFilm 缺键 = `expected[...]` nil ≠ `.grade` | ⚠️ 半申报：PLAN:214 写「`testOwnerMatrixOverAllEighteenRows`（`:144`）加 `"spektraFilm": .grade` 行」——**已列**，但行号写 `:144`（实为函数声明 `:144`，`expected` 字典起于 `:145`），措辞是「加一行」未说明这是「必红修复」 | 会红，已列（行号偏差可忽略） |
| 9 | **`:193-205` `lightamerGradeRows`** | 实测 **12 项**（`acesccIn/filmPlacement/colormatch/acesccOut/colorWheels/cat02WB/contrast/white/black/saturation/tint/hls`），PLAN 写「加 `("spektraFilm", 46.7)` 成 13 项」 | ✅ 已申报（且 m9 正确指出「既有串已过时 1 项」） | 会红，已列 |
| 10 | **`:228` 断言串** | `"the eleven LIGHTAMER rows are unique"` | ✅ 已申报（→ thirteen） | 字符串，不影响通过 |
| 11 | **`V50OrderTests.swift:24`** | `V50Order.entries.count == 108` → 109 | ❌ **完全未申报**（PLAN:223 的 ΔN 只写「V50OrderTests +1」） | **必红** |
| 12 | **`V50OrderTests.swift:284-293` `nativeRows` 集合** | 显式 15 个 native row 的 Set；`:294` `stripped.count == 93`。spektraFilm 是 native row → 不在集合内则 stripped = 94 | ❌ **完全未申报** | **必红** |

**后果**：T1' 是第一个执行任务。按 PLAN 现有申报，执行者改完已列的 7 处后跑 bundle，仍会有 **至少 3 处硬红**（#7 `:139 resolved.count`、#11 `V50OrderTests:24 entries.count`、#12 `:294 stripped.count`）+ **1 处语义错**（#6 `newSevenOps` 判别力丢失）。而 PLAN 的 AC-T1'-3 写「E7 checker 全绿（唯一 op 20、行 21）」——`resolved.count` 恰是「唯一 op 数 == 19」的断言，加行后必为 20，**AC 与测试现状直接矛盾**；且 PLAN:214 明写「`:130-139` E7 零改（恒注册即过）」而 `:139` 就在该区间内、必改，属**已申报项与实际相反**（比未申报更危险：执行者会照 PLAN 跳过）。

> 注：#11/#12 属 `V50OrderTests`（不是 `GradeCatalogTests`），PLAN 的 T1' ΔN 只写「`V50OrderTests +1`」而无改写申报，两条均未被任何一处列出。

**修法**：

1. T1' 编辑点 4 改写为**两条独立批次**：(i) `GradeCatalogTests` 7 处（`39/41-48/50/55/95/139` + `expected` 字典 + `lightamerGradeRows` + `:228` 串）；(ii) `newSevenOps` 白名单（`:100-109`）追加 `SpektraFilmModule.opName` —— **语义理由**：panel seed-deferred 族成员（与 filmPlacement 同一 deferral 理由，HEAD `:104` 注释已写「M3-3-02 placement op」）。
2. 新增 `V50OrderTests` 两处：(i) `:24` → 109 + 说明串补 `+ spektraFilm`；(ii) `:284-293` `nativeRows` 追加 `"spektraFilm"`。
3. 删除 PLAN:214 的「`:130-139` E7 零改（恒注册即过——仍列为验证项）」——**该表述与 HEAD 相反**，`:139` 必红。改为「`:130-139` 内 `:139` count 19→20 必改；恒注册只保证 `makeBox` 非 nil，不保证计数不变」。
4. T8' 的自查清单（PLAN:452）补「`V50OrderTests` 2 处」。

---

## 二、major（5，本轮新增；v2 的 8 条已在结论头表逐条闭合）

### R-M1 — 导出兄弟图在 module 档 = 「有胶片、无 grade/filter」的半渲染（legacy 时代不存在的新语义）

**定位**：T6'-2（PLAN:334「module 档 `legTagsForLoaded` 由 D-SM-14 门供给、**targets 其余位恒 nil 既有语义保留**」）、D-SM-14（PLAN:186）、S-B2-4（PLAN:94）。

**HEAD 亲核**：

1. 导出 tags 的 per-target 形状 = 只有 loaded 图位有值，其余位 nil（`ExportInspectorView.swift:1218-1224`；`legTagsForLoaded` 由 `:383` 传入 `pipeCoordinator.filmLegRequestTags(for: .export)`）。PLAN 的 S-B2-4 也如实记录了这点并注「其余图恒 nil 是既有语义」。
2. 但 **legacy 时代兄弟图根本不渲染胶片**：`filmTailPolicy` 是 per-url carrier 门（`PipeCoordinator.swift:851-855`），导出只给 loaded 图传 `filmTails`（`ExportInspectorView.swift:1217-1220`），兄弟图 `filmTail = nil` → 无 film 腿。**所以「无 tags」与「无胶片」在 legacy 是一致的。**
3. module 化后，兄弟图的 spektraFilm 在**各自的 history/layerStack 里**（sidecar 加载，`ExportRenderer.swift:460` 的 `materializeBoxes` + `:491-499` 的 layerStack 重建）。因此兄弟图**会**渲染胶片（46.7 box 在链上），但 `$requestTags = nil` → `SpectralPrintBake.tables` 走「absent tags = 裸 pairHash + 自解中性」（`FilmPrintBake.swift:555-556`）→ **BW 的 grade 2 默认仍在（`:567-573`），但显式 grade / cameraFilter / reversalPrintMode / publishedRms 全丢**。
4. 后果不是「少一点色彩」：BW 相纸的显式 grade 选择丢失 + reversal 模式丢失 = 成片明显不同（`FilmPrintBake.swift` 的 reversal 分支改变 print/scan 键与 B 路径）。

**后果**：批量导出同一批胶片档（同一胶片/相纸、不同 grade）时，只有当前打开的图拿到 grade —— 其余全部退回中性。这是 **legacy 从未有过的、用户可批量生成的静默差异化**。AC-T6'-2 只断言「新档导出含 46.7 实例输出且 filmTails 传 nil」，抓不到这条。

**修法**：T6'-2 增一条明确裁定 + AC——(甲) 兄弟图 tags 也供给：`legTags` 改为 per-target 从**各自 sidecar 的 spektraFilm 实例 record** 解析（`resolveLegTags(record:store:)` 已是纯函数，只需把 record 来源从 loaded 的 carrier 扩到 per-target 的链），或 (乙) 显式登记为**已知限制**（「批量导出时未打开图的 grade/filter 不生效」），并在导出面板给一句说明。**推荐 (甲)**——`resolveLegTags` 已是纯函数（D-SM-14 设计），per-target 扩只是把 record 来源换掉，无新机制。

### R-M2 — 预设创建的「拒绝」判据读面未定：`composeCurrent` 返回的 payload 里根本没有层内 spektraFilm

**定位**：T6'-7(a)（PLAN:351「含 spektraFilm 的档调 `createPresetFromCurrent` = **拒绝创建**（typed 错误 + 面板提示）」）、AC-T6'-9（PLAN:365）。

**HEAD 亲核**：

1. `createPresetFromCurrent` 的输入是 `composeCurrent?()`（`PresetController.swift:142`），它产 `PastePayload`；而 `PastePayload.compose` 的 `instances` 来自 `sourceEffective` = `history.effectiveInstances()`（**仅全局项**，`HistoryStack.swift:437-466` 的层分区规则）+ 跳集过滤。
2. 层内 spektraFilm **不进 `payload.instances`**（层链只走 `layerStack` 字段，而 `PresetsStore.create` 的签名没有 layerStack 形参（`PresetsStore.swift:212-218`），构造 `LightamerPreset` 时恒 nil（`:224-226`））→ payload 里既没有 spektraFilm 的 instances 份，也没有 layer 份（写侧断链）。
3. 因此 T6'-7(a) 若按 PLAN 字面在「payload 含 spektraFilm instances」处拒绝，**永远不会触发**：含层内胶片的档创建预设 → 静默成功，只是胶片没进预设（层链本来就不进）。AC-T6'-9 的「→ 拒绝（typed 错误）」不可达。

**后果**：用户拍了「含胶片层的档建预设」，得到的是一个**看起来成功、实际丢了胶片**的预设——比拒绝更糟（无提示的静默丢失）。而 T6'-7(b) 单独修 `buildPayload` 也不能覆盖，因为预设路径不走 `buildPayload`（`PresetController` → `PastePayload.compose` 是另一条）。

**修法**：T6'-7(a) 的判据改到**层面**读取——`createPresetFromCurrent` 前检查 `editorState.layerStack?.compositeLayers` 各 chain 的 opName（复用 D-SM-8R 的 `hasSpektraFilmInstance` 单源谓词），命中 → typed 拒绝。同时把 AC-T6'-9 改为可触发形态（构造含层内 spektraFilm 的 fixture，断言 `createPresetFromCurrent` 抛 typed 错误 + `PresetsStore` 无新文件）。并注明「本判据与 payload 无关，payload 路径的防御过滤（`makePayload`）只是第二道」。

### R-M3 — `SpektraFilmTests` 落域只写「IOP/Core 级」：若落 IOP（基线 7654MB）则 100MP 探针必越 8192 门；且 RSS 门本身只在 skip 探针轮生效

**定位**：T2' ΔN 行（PLAN:253「落域 IOP/Core 级」）、AC-T2'-6（PLAN:246「`LIGHTAMER_PERF_PROBE=1` + XCTSkipUnless 默认 skip」）、T8' 基线轮（PLAN:399-400）、T7' 落域（PLAN:378）。

**HEAD 亲核**：

1. `Scripts/test-direct.sh:78` 的 `RSS_LIMIT_MB=8192` 是**宿主进程级** `ru_maxrss` 门。
2. `.work/gsd/phases/m2-4-0-test-bundles/M2-4-0-SPIKE.md:34` 实测：**IOP bundle 峰值 7654MB**（`TilingOverlapTests` 单测 100MP 合成图吃掉 7.3G，`:34-38`）；LAYERS **944MB**（`:49`）；IOPParity 5788MB。
3. PLAN 把 `SpektraFilmTests` 的落域写成「IOP/Core 级」二选一，**没有指定 target**。若落 IOP：基线 7654 + module 档 1.6-3.2GB 中间面 = **9254-10854MB → 必然 MEMFAIL**（与 v2-M5 指出的同一死结，v3 只在 T7' 桥接测试上解决了，T2' 本体没解决）。
4. 更硬的漏洞：AC-T2'-6 的 RSS 断言是 `LIGHTAMER_PERF_PROBE=1 + XCTSkipUnless`（默认 skip）。**默认套件不跑它**，所以「100MP 峰值 RSS ≤ 8192MB」在 `--all` 里根本不被检查；而 `--all` 的宿主门只看进程峰值——一旦该测试类在 IOP 宿主里跑 100MP 合成，**即使不做断言也会把宿主推到门下**（分配本身就是内存）。门的对象搞反了：断言 skip，但分配照跑。
5. 唯一真正有效的护栏是 T8'-1 的 `Scripts/test-direct.sh --all` 的 MEMFAIL 机检（`:147-149`）——但那是**失败后**才有信号，且 PLAN 把它放在最后一个任务。

**修法**：(i) 明确 `SpektraFilmTests` 落 **LAYERS**（944MB 基线，同 `FilmLegTests`/`FilmPrintBakeTests` 的既落域先例，`M2-4-0-BUNDLE-MAP.txt:582-583`）；(ii) AC-T2'-6 的 100MP 探针**改为合成中平面**（如 8K）默认跑，或加 `.tags(.memoryHeavy)` 级独立 bundle——但成本高，**推荐：100MP 只留在 `LIGHTAMER_PERF_PROBE=1` 探针轮，默认套件用中平面（≤2K）跑分配计数断言**；(iii) T8' 的基线轮**提前到 T2' 开头**（当前 T8' 才跑 = 发现冲突时已改完 6 个任务）。

### R-M4 — `mergeLayerDown` 的 nil 分支拿不到「为何 refuse」：`MergeDownOutcome?` 的 nil 不带原因

**定位**：T3'-3（PLAN:263「`mergeLayerDown` nil 分支：区分「无此层/retouch 既有静默面」与「含 spektraFilm refuse」——后者 toast」）、D-SM-8R（PLAN:182）、AC-T3'-6（PLAN:274）。

**HEAD 亲核**：

1. `LayerStack.mergeDown(id:)` 的返回类型是 `MergeDownOutcome?`（`LayerStack.swift:76-86` 的 enum 只有 `.mergedIntoLayer` / `.mergedIntoBase`），**nil 有三个来源**：无此 id（`:162-164`）、merged 非 AdjustmentLayer（retouch，`:169-172`）、下层非 chain（`:182-187`）。
2. 调用方 `mergeLayerDown`（`EditorState.swift:741-749`）只写 `guard let outcome = stack.mergeDown(id: id) else { return }` —— **nil 分支直接 return，没有任何区分信息可读**。
3. PLAN 要求在这个 nil 分支里 toast「含 spektraFilm refuse」，但 spektraFilm 的 refuse 逻辑（B4 修法）是**在 `mergeDown` 内部新增的第四个 nil 来源**（PLAN:263 的编辑点 3 就写在 `LayerStack.swift`）。四个来源共享 nil → 调用方无法区分。

**后果**：实现者只有两条路——(甲) 在调用方**递归/降级**：先自己检查 `stack.adjustmentLayers.first(where: { $0.id == id })` 是否含 spektraFilm（预检，不进 `mergeDown`），命中就先 toast 再 return（不调 `mergeDown`）。这条路可行且零 Core 改动扩展，但 PLAN 没写；(乙) 给 enum 加 `.refusedFilmInChain` case——那要改 `MergeDownOutcome`（Core 公开类型）且 `LayerCoreTests.swift:126/149/339` 三处消费点要同步。PLAN 两条都没写，只写「区分」二字。

**修法**：T3'-3 钉死实现形——**推荐 (甲)**：`mergeLayerDown` 开头加预检（`if let target = layerStack.adjustmentLayers.first(where: {$0.id == id}) as? AdjustmentLayer, HistoryStack.effectiveChain(target.chain).contains(where: {$0.opName == "spektraFilm"}) { presentToast(...); return }`），`LayerStack.mergeDown` 的 refuse hunk 保留为**纵深防御**（数据面契约完整性，`LayerCoreTests` 可加一条直接调 `mergeDown` 的负测）。这样调用方零枚举改动、Core 零公开类型改动。

### R-M5 — 封存面申报表缺 `LayerStack` 行：全批**唯一实质 Core 代码 hunk** 无处登记

**定位**：§封存面申报表（PLAN:412-432，15 行）、结论句（PLAN:432「`LayerStack.mergeDown` refuse hunk 在 Core Layers（**非封存，逐 hunk 申报**）」）、T3' 编辑点 3（PLAN:263）。

**HEAD 亲核（逐行对表）**：

15 行申报的形态归类：

| 形态 | 行 | 是否实质代码改动 |
|---|---|---|
| 零 diff | ExportQueueContract / sidecar / HistoryStack·HistoryHash / DrtRecord 组 8 件 / UserDefaults / filmPlacement / SessionThumbnailRenderer / FilmTailPolicy / FilmPrintBake / FilmMaterialStore / LayerCompositeDriver | **零**（11 行） |
| add-only 一行 | V50Order | 实质（1 行） |
| 一行 + 期望 | GradeCatalog | 实质（1 行） |
| 注释 hunk | PixelPipe | 实质（注释） |
| 测试落域 | 桥接测试 | 非产品代码 |

→ 「实质 2 行 + 1 注释例外」（PLAN:432 的自我描述）与表内形态**基本对得上**，且零 diff 的 11 行在 v3 选型下**确实成立**（TaskLocal 路不改 `FilmTailPolicy`/`FilmPrintBake` 签名 —— HEAD `FilmPrintBake.swift:453-461` 的 `@TaskLocal` 声明 + 两函数体不动 = 真零改；`FilmMaterialSeam` 落新文件 = `FilmMaterialStore.swift` 真零改；App 副本过滤 = `LayerCompositeDriver.swift` 真零改）。这部分是**诚实**的。

**但漏了一行**：T3' 编辑点 3 明写「`LayerStack.swift`（Core Layers，**非封存 1 hunk**，B4）：`mergeDown` 在 `.mergedIntoBase` 返回前加「combined chain 含 spektraFilm → restore + return nil」」。这是**全批唯一的实质 Core 逻辑改动**（不是注释、不是 add-only 行、不是新文件），而封存表的 15 行里**没有 `LayerStack`**。结论句用「非封存，逐 hunk 申报」带过——但「逐 hunk 申报」的载体就是这张表，表里没行 = 无处申报。

**后果**：T8' 的 AC-T8'-2「封存 diff == 申报终表」在 `LayerStack.swift` 上**无法判定**（表里没有该文件的期望 diff 形态）。同理，T3' 的「封存面：无」（PLAN:277）与编辑点 3 的「Core Layers 1 hunk」**自相矛盾**——T3' 表头写「封存面：无」。

**修法**：封存表增第 16 行——`LayerStack.mergeDown`（`mergeDown(id:)` 一处 guard + restore，1 hunk；申报形态 = 「Core Layers 实质 1 hunk，非封存面但逐 hunk 申报」）；T3' 的「封存面：无」改「`LayerStack.mergeDown` 1 hunk（见封存表第 16 行）」；PLAN:432 的结论句改为「实质 3 行 + 1 注释例外」。

---

## 三、v3 新引入面逐项核（HEAD 可行性）

| 新面 | PLAN 定位 | HEAD 可行性 | 判定 |
|---|---|---|---|
| `FilmMaterialSeam`（Core 新文件） | D-SM-13 / T2'-1 | `FilmStatsSeam` 形态实测同构：`public enum` + `public nonisolated(unsafe) static var` + `@Sendable` 闭包默认恒等（`FilmTailPolicy.swift:542-570`）；`LayerCompositeSeam.acesccEnvelope` 第二先例（`LayerCompositeDriver.swift:725-728`）。闭包签名 `(String, String) -> (FilmProfile, FilmProfile, UInt64)?` 全 Core 类型（`FilmProfile` = `public struct ... Sendable`，`FilmProfile.swift:99`；`FilmMaterialStore.materialPairHash` = `public static`，`:145`），**不引入 Core→App 依赖** ✓ | **可落** |
| `attachFilmStore` 内联安装 | D-SM-13 / T4'-1 | 方法在位（`PipeCoordinator.swift:1109-1111`），App 侧可读 `filmStore`（`private` 同文件）；装配根调用点 `LightamerShell.swift:960` 单点。**注意**：该函数当前是纯赋值（nil 合法 = film face dark），加闭包安装要处理「nil 装缺席闭包」的双分支，PLAN 已写 ✓ | **可落** |
| **module process 是否真能拿到非 nil 材料** | 全链路 | 链路完整：`SpektraFilmModule.process` → `FilmMaterialSeam.resolve(record.filmStock, record.paperStock)` → App 安装的闭包（强捕获 store）→ `store.profile(id:)`（`FilmMaterialStore.swift:120-122`）+ `materialPairHash` → 传入 `FilmLegFactory.assemble` → `PixelPipe.assembleFilmLeg(record:film:paper:…)`（`:1301-1306`，`static` internal，同 module? **跨 module**） | **⚠️ 见下** |
| `FilmLegFactory` 跨 target 调 `assembleFilmLeg` | T2'-3 | **HEAD 硬约束**：`assembleFilmLeg` 是 `static` **internal**（`PixelPipe.swift:1301` 无 `public` 修饰）。`SpektraFilmModule` 在 `LightamerIOP` target，`PixelPipe` 在 `LightamerCore` target（`Project.swift:114-146`）——**internal 跨 target 不可见**。PLAN 把 `FilmLegFactory` 也放 Core（`LightamerCore/Sources/Pipe/Film/FilmLegFactory.swift`）→ **同 target 调 internal 成立** ✓（v2 的 M2 结论延续）；但 `FilmLegFactory` 必须 `public` 才能被 IOP 的 module 调用，其 `assemble` 签名里 `FilmStatsSeam.PlaneHistogram`/`FilmLegAssembly` 均 public ✓ | **可落（同 target 转发 + public 门面）** |
| `resolveLegTags`（App 纯函数） | D-SM-14 / T4'-1 | 解析体 verbatim 搬移可行：`PipeCoordinator.swift:886-918` 四项（grade/filter/reversal/rms）全部只依赖 `record` + `FilmMaterialStore` + `PaperGradeTable` + `SpectralConstantsData` + `publishedRmsForFilmStock`（App private static，`:924-935`）。**注意**：`publishedRmsForFilmStock` 是 `private static` 且依赖 `RmsTableBox`（`:920-945`）——抽纯函数要么一并搬、要么把 memo 留在 coordinator 内并给纯函数注入 rms。PLAN 未提，属实现细节（minor） | **可落（需搬 memo 或注入）** |
| `layerOnlyOp` token（FIXED 表扩五） | T6'-7(c) | `PasteRejectionReason` = `private enum` + 四个 `static let`（`EditingToolset.swift:771-776`）✓ 可扩。**但**：该表只服务 MCP `paste_adjustments` 的 per-target 拒绝行（`:994/1002/1038/1139/1141`），**GUI paste 走 `PasteSemantics` 不经过它**。PLAN T6'-7(c) 把「paste→legacy 档含 spektraFilm = 拒绝」与 token 混写，未说明 GUI 面的拒绝呈现 → minor | **可落（MCP 面）/ GUI 面未定** |
| `LayerStack.mergeDown` refuse | T3'-3 | retouch refuse 同缝实证（`:165-172` restore + nil）✓；但 nil 不带原因（见 R-M4） | **可落（原因区分需补）** |
| GA 门控（`isFilmModuleRequested`） | T1'-3 | `LibraryLegacyGate` 先例建议成立；`Registry.populate` 签名当前是 `(registry, defaultFace:)`（`Registry.swift:69-70`）→ 加参 `filmModule` 会**破 20+ 测试调用点**（`defaultFace:` 有默认值，加新参也可给默认值，零破）✓ m3 已改为删死参 + 纯函数 | **可落** |
| ΔN 91（95−4） | §0.2 | 逐任务：T1' 7 ✓ / T2' **15（PLAN 写 14）** / T3' 13 ✓ / T4' 15 ✓ / T5' 4 ✓ / T6' 24 ✓ / T7' 18 ✓ / T8' 0 = **96**，减 4 = **92** | **算术 off-by-one**（minor m1） |
| 封存表 15 行 | §封存申报 | 行数实计 15 ✓；「实质 2 行 + 1 注释例外」与表内形态对得上（11 行真零 diff）；**但漏 `LayerStack` 1 hunk**（见 R-M5） | **诚实度：部分**（缺一行） |

### 关于「module process 真能拿到非 nil 材料」的链路复核（任务书指定重点）

**结论：链路可通，但 PLAN 少写了一个必需条件。**

- 通的部分：`record.filmStock`/`paperStock` 来自 `Params.record`（`FilmRecord` 原样嵌入，T2' Params 设计）；store 是 App 会话级强捕获；`profile(id:)` 与 `materialPairHash` 均 public（`FilmMaterialStore.swift:120/145`）。
- **缺的部分**：`filmTailPolicy` 现状有一条 `guard !isFilmRecordDefault(record) else { return nil }`（`PipeCoordinator.swift:856`）——**未绑定 stock 的默认 record 不供给**。D-SM-13 的 resolver 闭包**没有这条门**：`{ _, _ in ... store.profile(id: "") ... }` 对默认 record 会返回 nil（`profile("")` 未命中 → nil），**行为上等价**，但语义上是「靠 id 未命中兜底」而不是「显式 pristine 门」。这不会破坏 AC，但**`FilmMaterialSeam.resolve("", "")` 的日志会打一条 error**（T2' 写「nil → blitIdentity + logger.error」）——pristine 档（用户从未启用胶片）每帧打一条 error 日志，是噪声回归。建议 resolver 前置 `guard !stock.isEmpty`，或在 module 侧 `guard !isFilmRecordDefault(record)` 提前恒等（后者与 legacy 逐条对齐）。

---

## 四、D-SM-0 五条生命线落实核（降级 = blocking）

| # | 生命线 | PLAN 承载 | 落实 | 判定 |
|---|---|---|---|---|
| 1 | 材料解析缝 | D-SM-13 / T2'-1 / AC-T2'-7/8 | 新建 Core 缝 + 安装点 + 正负测齐全 | ✅ **全量** |
| 2 | requestTags 供给 | D-SM-14 / T4'-1 / AC-T4'-2 / AC-T7'-7 | 门改双源 + record→tags 纯函数 + 三形态等价 AC | ⚠️ **全量但兄弟图缺口**（R-M1，非降级） |
| 3 | merge-down 语义 | D-SM-8R / T3'-3 / AC-T3'-6 | refuse + 计数守恒 + 入层正常 + redo 不丢 | ✅ **全量**（实现形待补，R-M4） |
| 4 | **appex 注册** | T6'-3「**P1 不纳入**；appex 加 populate = **P2 立项**」 | **无任何编辑点、无 AC（反向 AC）** | ❌ **静默降级 → R-B1 blocking** |
| 5 | scratch 分配 | D-SM-12R / T2'-1 / AC-T2'-6/11 | 自持面不借 allocator + 无 BorrowError 正测 + 计数 AC | ✅ **全量**（AC 口径待拆，r-m9） |

**结论**：五条中 **4 条全量、1 条（第 4 条）被降级**。按任务书「降级即 blocking」，本轮判 **blocking 成立**。且该降级**在 PLAN 内零登记**（`grep "D-SM-0"` 零命中，§v3 changelog 与 §0 裁决冻结均无该条），属于「绕过用户裁决而不申报」——比单纯的技术分歧更严重，须在 v4 里显式落位（补做 / 申请批准降档，二选一）。

---

## 五、minor（9）

| # | 定位 | 亲核问题 | 修法 |
|---|---|---|---|
| r-m1 | §0.2 合计（PLAN:201）/ T2' ΔN（PLAN:253） | T2' 枚举实算 15 法（`2-1/2-2/2-4/2-5` 各 1 = 4；`2-3` md5 双臂 = 2；`2-6` 分配 1 + RSS 探针 1 = 2；`2-7/2-8/2-9/2-10/2-11` 各 1 = 5；工厂透传 2 → **4+2+2+5+2 = 15**），PLAN 写 `ΔN = 14`。v2 的 `1-1` 笔误已改但总数仍差 1。按 15 算，合计 = 7+15+13+15+4+24+18+0 = **96**，净增 96−4 = **92**（PLAN 写 91）。 | T2' 改 15；§0.2 与 T8' 基线公式改 96 / 92。 |
| r-m2 | T7' 编辑点 4（PLAN:381「47 个 film/spectral 测试文件零改名」） | 实测 `ls Tests/LightamerTests/ \| grep -iE "film\|spectral\|bw"` = **49** 文件（v2 时代 47 → M9-2/M8-3+ 批新增至少 2）。数字过时，且该数被 T7' 用作「零改名」的范围声明。 | 改 49（或改为「按 BUNDLE-MAP 的 film/spectral 行集为准，不写死数字」，更稳）。 |
| r-m3 | T1'-1（PLAN:218）/ AC-T1'-1 | `V50Order.order(for: "spektraFilm") == 46.7` 本身可过（46.7 全表空位实测零命中）。**但**：`V50OrderTests.testNoDuplicateOpNameExceptDeliberateCollisions` 断言 `Set(orderCounts.keys) == [28.5, 41.0]`（`Tests:45-49`）——46.7 唯一，不冲突 ✓；`testEntriesCountApproximately76` 的 108 必红（R-B2 #11）。AC-T1'-1 只断言新行，未覆盖既有计数测试 → 与 R-B2 同源。 | 见 R-B2；AC-T1'-1 补「`V50OrderTests` 两处计数断言同批改」。 |
| r-m4 | T6'-3 库网格 strip 落点（PLAN:337） | PLAN 写落 `SessionThumbnailProvider.buildRenderRequest` 物化层「records 过滤 `opName == spektraFilm`」。HEAD 该函数做的是 `degradedLayerStack` → `runtimeLayers` → `addAdjustment`（`SessionThumbnailProvider.swift:508-518`），**它拿的是 layer 结构而非 records 列表**；过滤点应在 `runtimeLayers` 各层的 `chain` 上，措辞「records 过滤」不精确。另注意：`degradedLayerStack` 已会对 unknown op 标脏层（`LightamerSidecar.swift:1182-1191`）——恒注册后 spektraFilm 不是 unknown，故 degrade 不帮忙。 | 措辞改「`runtimeLayers` 各层 `chain` 过滤 `opName == spektraFilm`（渲染前副本，不改 `layerRecord`）」。 |
| r-m5 | T3'-3 的 `filmRecords` 清空与 merge refuse 交互 | D-SM-8R 让基链 `recordChange` 对 spektraFilm typed reject（PLAN:262），B4 让 merge 入基 refuse。**但**：`filmRecords` carrier（legacy）与 spektraFilm 实例可**同时在场**（迁移中档：T4' 的 convert 才清 carrier）。此窗口内 `filmTailPolicy` 门 = `hasLegacyFilmRecord && !hasSpektraFilmInstance`（PLAN:285）→ 双在场时 film 腿关、module 腿开 = **胶片只渲一次** ✓。但 `recordChange` 的 typed reject 是**无条件**的（`:262` 无「基链」限定），而 T6'-4 的 `commitContinuousEdit(layerScope:)` 走 `recordLayerChange`（不经过 `recordChange`）✓；`FilmPanelModel.applyRecommendedGrainStrength` 走 `editorState.recordChange(record, ...)`（`FilmPanelModel.swift:250`）——该 record 是 **grain** 不是 spektraFilm ✓。结论：无实际冲突，但 PLAN 未明说「`recordChange` 的 reject 仅对 spektraFilm opName」，执行者若写成「含 film 语义即拒」会误伤。 | `:262` 措辞补「仅 `snapshot.opName == "spektraFilm"` 时拒；grain/halation 等 Post 四件不受影响」。 |
| r-m6 | T2' AC-T2'-8 的 logger 断言（PLAN:248「OSLog 捕获或行为断言二选一，SUMMARY 实报」） | 「二选一」= 执行者自行定标准，属 v1/v2 反复点名的「AC 不可机检」模式回潮。HEAD 无 OSLog 捕获基建（`grep` 无 `OSLogStore` 使用）。 | 钉死行为断言：`process` 在缝缺席档输出逐位 == 输入（已有 AC-T2'-4）+ **不 crash + 不 throw**；logger 不断言。 |
| r-m7 | T4' 编辑点 4 键族「≤4」（PLAN:292/307/409） | `panel_film_convert_{title,body,button,confirm}` = 4 键 + 「cancel 复用中性键」。**该复用成立**：`alert_cancel` 在册且是真正中性键（en "Cancel" / zh "取消"，`Resources/Localizable.xcstrings`）。问题只在于 PLAN 未点名用哪一枚（同族里 `panel_film_migrate_cancel` 也在册但属退役族、`panel_process_migrate_cancel` 属 process 迁移语境）。 | 显式写「cancel 复用 `alert_cancel`」，键预算维持 ≤4。 |
| r-m8 | T8' 走查项（PLAN:402「缩略图 grid 可度量（单张渲染耗时对照 legacy ±10% 内））」 | 「±10%」在 GUI 走查里人工量测不可靠（无基线脚本、无重复采样规定）。且 T6'-3 明确缩略图 **strip 掉胶片** → module 档缩略图与 legacy 缩略图**本来就是同一画面**（都无胶片），耗时对比无意义。 | 删该子句，改为「grid 缩略图与编辑器同档观感一致（都无胶片）」的目视项；性能归 T2' 探针。 |
| r-m9 | AC-T2'-6 第二句（PLAN:246）、D-SM-12R（PLAN:184） | 「自持面分配计数 ≤1」与「ΔRSS ≤ 1 张全帧平面」被写成一条，观测面其实不同（前者 module 内部计数、后者宿主 `ru_maxrss`）。**D-SM-12R 的面数结论本身成立**：七步链最少 1 张自持面（步骤②已订明第一跳直写 pipe `output`），spectral 内部面（mix/preCopy/corr，`SpectralPayloads.swift:611/647/660-665`）legacy 腿同款分配 → 不构成 Δ。残留问题仅：**计数槽从哪读未定义**（生产代码为测试加静态计数 = 新测试缝，须申报）。 | AC-T2'-6 拆两条：(i) 自持面计数 ≤1（计数槽形态照 `FilmStatsSnapshot.last` 的 advisory 槽先例，`Registry.swift:98-100`，显式申报为测试缝）；(ii) ΔRSS 参考断言 ≈1 张全帧平面（同链对比，spectral 内部面不计）。D-SM-12R 补「strength<1 的 mix 面属 box 内部、legacy 同款，不计入自持账面数」。 |

---

## 六、v1 遗留残余复核

v2 报告已判 v1 的 B1（挂载三互斥）/B2（ε 带）/M1/M2/M3 的残余，v3 的处理：

| v1 项 | v2 残余 | v3 处理 | 判定 |
|---|---|---|---|
| v1-B1 paste/批量全局 epoch 的 reject 落点 | 未定 | M4(c) 给 `layerOnlyOp` token + `PasteSemantics` overwrite/merge 面剔 instances 份 | **部分消解**（GUI 面呈现未定 → r-m5 邻域） |
| v1-B1 merge-down 数据丢失 | 未消解 | B4 refuse | **真消解** |
| v1-B2 ε 带三段带宽不自洽 | 未消解 | D-SM-9R 重写 | **真消解** |
| v1-M6 迁移行动作面 guard | 未消解 | B3 | **真消解** |
| v1-M1/M2/M3 | 已消解 | v2 修法继承 | **维持** |

**结论**：v1 遗留的**技术面**残余全部消解；唯一残留是 GUI paste 的拒绝呈现（不构成 blocking）。

---

## 七、replan v4 闭合清单（回注 omp）

**必修（blocking，2）**

1. **R-B1**：D-SM-0 第 4 条（appex 注册）二选一并落 PLAN + DECISIONS——(甲) T6' 增 appex populate + material seam 装配 + AC「QL 输出 == 导出输出（ε 带）」；(乙) 向用户申请批准降档，PLAN 的 AC-T6'-4 第三子句改为「已知缺口登记」而非「== legacy 基线」。**PLAN 须新增 `D-SM-0` 落实节**（当前零命中）。
2. **R-B2**：T1' 编辑点 4 重写——`GradeCatalogTests` 补 `:100-109 newSevenOps` 与 `:139 resolved.count`，删掉「`:130-139` E7 零改」的错误表述；新增 `V50OrderTests:24`（108→109）与 `:284-293 nativeRows`（追加 `spektraFilm`）两处。T8' 自查清单同步。

**必修（major，5）**

3. **R-M1**：T6'-2 兄弟图 tags 裁定 + AC（推荐 per-target 从各自 sidecar 的 spektraFilm record 经 `resolveLegTags` 解析）。
4. **R-M2**：T6'-7(a) 拒绝判据改到层面（`hasSpektraFilmInstance` 单源）；AC-T6'-9 改可触发 fixture。
5. **R-M3**：`SpektraFilmTests` 落 **LAYERS**（非 IOP）；100MP 探针降为中平面默认跑 + 探针轮保留 100MP；基线轮提前到 T2' 开头。
6. **R-M4**：T3'-3 钉死 merge refuse 的原因区分实现形（推荐 `mergeLayerDown` 开头预检 + `LayerStack.mergeDown` 保留纵深防御）。
7. **R-M5**：封存表增第 16 行 `LayerStack.mergeDown`；T3' 的「封存面：无」改「1 hunk」；结论句「实质 2 行」改「实质 3 行」。

**随修（minor，9）**

8. r-m1 ΔN 96/92；r-m2 49 文件或去数字；r-m3 AC-T1'-1 补计数测试；r-m4 缩略图过滤措辞；r-m5 `recordChange` reject 限 opName；r-m6 AC-T2'-8 钉行为断言；r-m7 点名 cancel 复用 `alert_cancel`；r-m8 删缩略图 ±10% 性能子句；r-m9 AC-T2'-6 拆两条 + 计数槽申报为测试缝。

**复审节点**

10. 修后重走本 lane：R-B1/R-B2 全核 + R-M1..R-M5 全核 + minor 抽核。

---

## 八、验收自查

- [x] 基线亲核：HEAD `f32cb76b`，`25e01172` 为祖先且源码面零 diff（仅 DECISIONS + prompt 两文件）——与任务书给的 `25e01172` 等价。
- [x] v2 的 4 blocking 逐个判定（真消解 3 / 部分消解 1）；8 major 逐个抽核（真消解 6 / 部分消解 2）。
- [x] v3 新引入面 10 项逐个核 HEAD 可行性（含「module process 真能拿到非 nil 材料」全链路走查）。
- [x] D-SM-0 五条生命线逐条核落实（4 全量 / 1 降级）。
- [x] 每条判定带 HEAD file:line；未修改 PLAN。
- [x] 只读：零 commit / 零构建 / 零测试；唯一产出 = 本文件（chunked 追加 6 段，逐段 `wc -c` + U+FFFD 自检 = 0）。
- [x] 结论头 `FAIL / 2 blocking + 5 major + 9 minor`。

### 亲核心证抽查（本轮 ≥6 个关键判定）

| # | PLAN 判定 | 结果 | 证据 |
|---|---|---|---|
| K1 | 「`FilmStatsSeam` 同款形态」可作新缝先例 | **PASS** | `public enum FilmStatsSeam` + `public nonisolated(unsafe) static var histogram: @Sendable (...) = { _, _ in nil }`（`FilmTailPolicy.swift:542-570`）；安装点 `FilmStatsSeam.histogram = {...}`（`Registry.swift:88`） |
| K2 | 「`:130-139` E7 零改（恒注册即过）」 | **FAIL** | `GradeCatalogTests.swift:139` = `XCTAssertEqual(resolved.count, 19, "19 unique catalog ops all resolve")`，循环体 `:134` 遍历全部 `GradeCatalog.items` → 加行后必为 20 |
| K3 | 「`V50OrderTests` 只需 +1」 | **FAIL** | `:24` `entries.count == 108` 必红；`:284-293 nativeRows` 未含 spektraFilm → `:294 stripped.count == 93` 变 94 必红 |
| K4 | 「QL P1 不纳入，与 legacy 一致」不违反裁决 | **FAIL** | `DECISIONS.md` D-SM-0 第 4 条显式列「appex 注册」为 P1 必需；PLAN 全文 `grep D-SM-0` 零命中 = 未登记 |
| K5 | 「QuickLook P1 不纳入（迁移档预览无胶片 == legacy 基线）」可作 AC | **FAIL（语义）** | `QuickLookRenderer.swift:270-289` 会重建 `layerStack` 并进 `processComposite`；不做 strip 时 QL 会渲其它 grade op 而跳过胶片 = 假功能；做 strip 则「不纳入」不成立 |
| K6 | 「`mergeLayerDown` nil 分支可区分 refuse 原因」 | **FAIL** | `MergeDownOutcome` 仅两 case，`mergeDown` 返回 `?`，nil 有 3 个既有来源（`LayerStack.swift:162/169/182`）+ 新增 1 个；`EditorState.swift:741-749` 只 `guard let` 后 return，无原因可读 |
| K7 | 「`createPresetFromCurrent` 可据 payload 判定含 spektraFilm」 | **FAIL** | `composeCurrent` 产 `PastePayload`，其 `instances` 来自 `effectiveInstances()`（全局项 only，`HistoryStack.swift:443-466`）；层内 spektraFilm 不入 payload；`PresetsStore.create` 无 layerStack 形参（`:212-218`） |
| K8 | 「module 自持 1 张中间面足够」 | **PASS（面数）/ 口径待拆** | 七步链最少 = pipe output + 1 自持面（PLAN 步骤②已订明第一跳直写 `output`，`PixelPipe.swift:437-457`）✓；spectral 内部面（mix/preCopy/corr，`SpectralPayloads.swift:611/647/660-665`）legacy 腿同款 → ΔRSS 1.6GB 量级**成立**；仅 AC 两口径混写（r-m9） |
| K9 | 「封存表实质 2 行 + 1 注释例外」诚实 | **PARTIAL** | 15 行中 11 行真零 diff（TaskLocal 选型成立，`FilmPrintBake.swift:453-461` 未动）✓；但漏 `LayerStack.mergeDown` 1 实质 hunk（T3' 编辑点 3 自述） |
| K10 | 「`T7'` 47 个 film/spectral 测试文件」 | **FAIL（数字）** | 实测 49 文件 |
