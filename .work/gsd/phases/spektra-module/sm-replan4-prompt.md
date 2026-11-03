# spektra-module P1 replan v4 lane（omp）

你是 spektra-module P1 的 replanner（第四轮）。工作目录 /Volumes/UNITEK/Documents/Development/Lightamer。全程中文。**唯一产出 = 重写 `.work/gsd/phases/spektra-module/PLAN.md`（v4），零产品代码、零构建、零 commit。**

## 输入（按优先级）

1. **闭合清单（最高优先）**：`SM-PLAN-REVIEW-V3.md`（FAIL / 2 blocking + 5 major + 9 minor）——v3 的判定表（4 blocking 里 B1/B3/B4 真消解、B2 部分）已确认，不要推翻重做已消解项，只补未消解与新增。
2. v2 报告（v3 未消解项的原始出处）：`SM-PLAN-REVIEW-V2.md`；v1：`SM-PLAN-REVIEW.md`
3. **用户裁决（不可违反）**：`DECISIONS.md` D-SM-0——五条生命线全量，禁降档。
4. 设计正本：`RESEARCH.md`
5. 基线 HEAD `0d7d0e90`（先亲核）

## 两个 blocking 的必答（本轮核心）

### R-B1 — D-SM-0 第 4 条生命线（appex 注册）被静默降级

v3 PLAN:339 判「QuickLook P1 不纳入，P2 立项」，且全文 `grep D-SM-0` 零命中。

**必须改为**：QuickLook/appex 注册纳入 P1。并消解评审的反证——`QuickLookRenderer.swift:270-289` 会重建 layerStack 进 `processComposite`，不 strip 时 QL 会渲染其它 grade op 而独独跳过胶片 → **不是「与 legacy 一致」，是新的不一致**。

交付要求：
- 给出 appex registry `populate` 的具体改法（`LightamerQuickLook.swift:36` 现仅 `makeDefault()` 三件），file:line 落证；
- 若确有不可行的技术理由（如 appex 不能引用 LightamerIOP），必须写「缝验证证据」证明，并把替代方案（如 strip 过滤）写清——**不许只写「挂 P2」**；
- PLAN 文首显式登记 D-SM-0 五条生命线的落实状态表（1 材料/2 tags/3 merge/4 appex/5 scratch，逐条 = 任务号 + AC 号）。

### R-B2 — 既有测试改写申报第三轮仍不全，且「已申报项与事实相反」

- `GradeCatalogTests:139` `resolved.count == 19` → 加行后必为 20，**必红**；而 PLAN:214 写「`:130-139` E7 零改（恒注册即过）」——**已申报项与 HEAD 事实直接相反**（比未申报更危险，执行者会照 PLAN 跳过）。
- `V50OrderTests:24`（`entries.count == 108`）、`:284-293 nativeRows` / `:294`（`stripped.count == 93`）两处必红，完全未申报。

**必须做**：T1'（首个执行任务）前把**全部会红的既有断言**逐条列清（file:line + 现值 + 新值 + 改写方式），并加一条 AC：「T1' 完成后 `test-direct --bundle <域>` 全绿，零未申报红」。**建议方法**：不要靠记忆盘点，直接在 HEAD 上 grep 这些计数断言（`count ==`、`resolved.count`、`entries.count`、`stripped.count`）逐条核。

## 5 major 必答

- **R-M1** 导出兄弟图 tags 恒 nil（`ExportInspectorView.swift:1218-1224`）→ module 化后兄弟图渲染胶片却无 grade/filter/reversal = legacy 从未有的静默差异。给判定：修（怎么供）or 明确保持 legacy 行为（不给 module 档兄弟图渲染胶片）。
- **R-M2** 预设拒绝判据读面未定：`composeCurrent` 的 payload 不含层内 spektraFilm → 拒绝逻辑抓不到。给具体读面。
- **R-M3** `SpektraFilmTests` 落域未定：落 IOP 则基线 7654MB + 探针必越 8192 门；且 RSS 断言是 skip 探针，门只在探针轮生效。给落域判定 + 门策略。
- **R-M4** `MergeDownOutcome?` nil 不带原因，四条来源无法区分 → 改为带 reason 的枚举，逐来源 AC。
- **R-M5** 封存表漏 `LayerStack.mergeDown`（全批唯一实质 Core 逻辑 hunk），且 T3' 写「封存面：无」自相矛盾。

## 9 minor 逐条修（ΔN 实为 96−4=92、film 测试文件 49 非 47、cancel 键点名 `alert_cancel` 等）

## 交付要求

- PLAN v4：chunked 写（每段 ≤8KB，逐段 `wc -c` 自检）；文首两张表 = ①「§v4 changelog」= 三轮评审全部 finding → 消解位置/显式不解（三态）②「D-SM-0 五条生命线落实表」。
- **禁止**再出现「已申报零改」与 HEAD 事实相反的条目——凡写「零改」的必须带 grep 证据。
- 每条新缝带「缝验证证据」小节（HEAD file:line + 现状行为）。
- ΔN 重估（v3 报 96，评审实为 96−4=92，以 v4 实数交付）；封存表 16 行（补 LayerStack）。
- stdout 最后一条一次性完整输出（2B + 5M 逐条消解 + 生命线落实表 + ΔN + 封存表行数）。
