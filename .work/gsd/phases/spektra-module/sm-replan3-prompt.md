# spektra-module P1 replan v3 lane（omp）

你是 spektra-module P1 的 replanner（第三轮）。工作目录 /Volumes/UNITEK/Documents/Development/Lightamer。全程中文。**唯一产出 = 重写 `.work/gsd/phases/spektra-module/PLAN.md`（v3），零产品代码、零构建、零 commit。**

## 输入（按优先级）

1. **闭合清单（最高优先）**：`.work/gsd/phases/spektra-module/SM-PLAN-REVIEW-V2.md`（FAIL / 4 blocking + 8 major + 10 minor）
2. 前一轮评审：`SM-PLAN-REVIEW.md`（v1 报告——部分项在两轮间仍未消解，需一并核）
3. 设计正本：`RESEARCH.md`
4. 现行 PLAN.md（v2，将被 v3 覆盖）
5. 基线 HEAD `25e01172`（先亲核）

## 本轮强制方法变更（前两轮的失败模式）

前两轮失败根因 = **未验证缝就写设计**（v2 的 B1 材料解析缝、B2 requestTags 供给，都是 PLAN 假设存在的通道在 HEAD 根本不存在）。

**本轮硬性顺序：每个 touching 面先做「缝存在性验证」（读 HEAD 代码 + file:line 落证），再写设计；验证不通过的缝必须写成「新建缝任务」而非假设。**

## 4 个新 blocking 的必答

- **B1 材料解析缝**：`FilmMaterialStore` 仅 App 侧持有（`PipeCoordinator.swift:1053`），Core/IOP 无。设计 = 注入形态？还是 module params 直接携带材料谱面载体？给判定 + 具体注入点 file:line + 生命周期（谁建/谁持有/何时失效）。
- **B2 `$requestTags` 供给**：三处消费（`FilmPrintBake.swift:555/566/576/605`、`FilmTailPolicy.swift:851-866/906`）全读 TaskLocal。设计 = module 路怎么供（TaskLocal 继续 + 新供给点 / 还是 params 直达）——给判定 + 与 T4' 判别门的冲突消解。
- **B3 迁移动作面 guard**：`PipeCoordinator.swift:1028-1030` 的 return 条件必须列进编辑点，AC 要能机检（点击后 process 号真翻）。
- **B4 merge-down 蒸发**：`.mergedIntoBase` 分支（`EditorState.swift:748-754`）× recordChange typed reject → 数据丢。设计 = merge 对 spektraFilm 的处置（禁止 merge？预转 legacy 回 carrier？）给判定 + 负测 AC。

## 8 major 必答（摘要，逐条给修法）

M3 QuickLook appex registry 仅三件（`LightamerQuickLook.swift:36`）→ spektraFilm 恒 unknown op；M2 `degradedForUnknownOps` 与 M5 恒注册自相矛盾 AC；M8 `SpectralScratchAllocator.Slot.claim` 的 `Leg` 三值与 module 争槽 + RSS 基线 7654MB+1.6GB 必越 8192 门；m10 `addPlacement` 取 `adjustmentLayers.last` 含 RetouchLayer 而 `adjustmentLayer(id:)` 只查 `compositeLayers` → 静默 nil；m9 五处测试会红未申报；m8 ΔN 应 72（减 FilmCardTests −4）；D-SM-11 add 菜单隐藏需 static 读实例态的下传路径；封存面申报须增五行（FilmTailPolicy/FilmPrintBake/FilmMaterialStore/LayerCompositeDriver/桥接测试落域）。

## 交付要求

- PLAN v3：chunked 写（每段 ≤8KB，逐段 `wc -c` 自检）；文首「§v3 changelog」表 = 两轮评审全部 finding（4B+8M+10m 本轮 + v1 遗留未消解项）→ 消解位置或显式「本轮不解，挂 P2/挂账」三态。
- 每任务 AC 机检可验；**每条新缝必须带「缝验证证据」小节（HEAD file:line + 现状行为）**。
- ΔN 重估（含 −4）；封存面完整申报表。
- stdout 最后一条一次性完整输出（4B+8M 逐条消解摘要 + 新缝清单 + ΔN + 封存表行数）。
