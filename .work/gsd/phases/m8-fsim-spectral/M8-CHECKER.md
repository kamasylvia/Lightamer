# M8-CHECKER — M8-1 fixer 后 checker 复核（2026-10-24）

> 复核对象：`CONTEXT.md` + `M8-1A-PLAN.md` + `M8-1B-PLAN.md` + `M8-2-PLAN.md`
> + `M8-3-PLAN.md`（fixer `dd9490fe` 后 HEAD，+169/−50，五文件纯 docs）。
> 评审正本 = 同目录 `M8-PLAN-REVIEW.md`（`a1dd6b65`）15 条处方
> （1 blocking + 4 major + 9 minor）。
> 复核方法 = 处方逐条对账 + 三处出入点独立实测（dt 上游 / 产线源码 /
> 28 张 profile 数据面重扫）+ 数字链亲算 + grep 机检 + 标记抽核 + 可执行性
> 终判。零源码触碰；唯一产出 = 本文件。

## 结论头

**退回 / 1 residual**

- 15 条处方 **14 条完整落地**（B1 + M1 + M2 + M4 + m1-m9 全绿，逐条见下）；
  1 条半落地：**M3② 的「M8-2 T1/T3 消费」要素只落在 charter 侧（CONTEXT
  X7），M8-2 plan 层零锚点**（R1，详见残留节）。
- 三处出入点**全部有据非发明**（M1 坐标勘误经本轮独立 grep 实锤为真勘正；
  M2 择径算术闭合；M3② 择径先例在产线源码亲核在位）。
- 数字链全闭合；grep 机检零残留活规格；review 标记 39 处覆盖 15 条全谱系；
  fixer 零源码触碰（commit stat 五 .md 实证）。
- **可执行性终判**：B1 修复后 M8-1a T1 按 SC 可实现（Optional 解码标准
  Codable 面 + 投影 face 先例在库 + 冒烟断言数值带经本轮 28 张独立重扫
  可操作）；**M8-1a / M8-1b 即刻可开工**；R1 不阻 M8-1 开波，**须在 M8-2
  开工前一批 plan 文本勘正闭合**。

---

## 15 条处方逐条对账

| # | 判定 | 落点（fixer 后实测） | 复核方式 |
|---|---|---|---|
| B1 | **落地 ✓** | M8-1A SC:9 + T1 action:111-141：`channelDensity [[Float?]]` / `midscaleNeutralDensity [Float?]` + baseDensity 先例引称 + null 语义投影 face 单源（`baseDensityProjection()` 家族同位）+ 形状校验「逐点 null 不触发降级」+ 28 张冒烟 null-aware（null 计数带申报）+ typed 载体双形注记（window 4 标量 / surface 3×15） | 28 张 profile 本轮独立重扫：channel_density **28/28 含 null（15-78/243）**、midscale **28/28（5-26/81）**、log_sensitivity **零 null**（保留 `[[Float]]` 正确）、portra_400 恰 22/243——与 plan 引用数逐位吻合；`baseDensity: [Float?]` 真身 FilmProfile.swift:171 + 投影 face 注释 :25/:170 亲核 |
| M1 | **落地 ✓** | M8-1A T4 action:239-249（remap 预折进表 + compress_xy_radial 数学面 + 白心 = proj_xy 纪律）+ M8-1B T1 expose:107-111（kernel 面零 remap 代码、fetch 走已压缩域）+ M8-1B SC:9 注记 | **出入点①**：dt 本轮独立 grep——`input_gamut_compress /* true */` 真身 = `src/common/spektra_sim.h:601`，`spektrafilm.c` 零命中；sim.c:3840-3845 白心注释（"Centring it elsewhere would walk the neutral off the cell" + `compress_xy_radial(..., proj_xy, ...)`) 逐字亲核 |
| M2 | **落地 ✓** | M8-3 front-matter:10（T2 +2..3 带 review 标记与行和复核式）+ ΔN 表 :62（同改 +「读数对照记录测试」构成注）+ CONTEXT 分账表 M8-3 行同批 | **出入点②（择径）**：评审两案（某行 +1 ↔ 合计勘正 9..13）中取「T2 +1..2 → +2..3」保终值带 4266..4288 不动——下游四 plan 累计带零扰动，择径有据；行和亲算 2+2+4+2=10 / 3+3+5+3=14 ✓ |
| M3① | **落地 ✓** | CONTEXT X1:213-218（拟合目标 = 色度域 metameric 构造式、系数表 film 无关共享、sens 仅入质量门与 per-sim 积分、「本句为钉死正本」）+ X2 附注挂 X7 | X1/X2 矛盾消解逻辑自洽；T3 正文论文式构造式即共享形，引称吻合 |
| M3② | **半落地 → R1** | charter 侧完整：CONTEXT X7 节 :301-311（FilmPrintBake 家族同位 per-pair LRU / M8-2 T3 承载 tc_lut 槽 / T1 消费命中面 / 禁临场发明）+ X1/X2 挂引 | **出入点③（择径）**：评审两案（FilmPrintBake 同位 ↔ 新 SpectralBuildCache）中取前者——产线先例亲核在位（FilmPrintBake.swift:287-295 per-pair LRU 16、键 = materialPairHash、bakeCount 同形）；**但 M8-2 plan 层零回注 = R1（见残留节）** |
| M3③ | **落地 ✓** | M8-1A T5 action:282-287（秒级/表量级带 + 量级算术注记 192²×Float64 + 33³×2≈5.8M 超越函数 + concurrentPerform 并行预期 + 实测 DECISIONS 申报）+ 风险节 :309-313 同批 | <100ms 旧估两处全替换，grep 无「<100ms 级」残留 |
| M4 | **落地 ✓** | M8-3 files_modified:20 + read_first:91 两处均改 `App/Sources/Lightamer/UI/Shell/FilmPanelView.swift` | 本轮 ls 实证：Shell/ 真身在库，UI/Inspector/FilmPanelView.swift 不存在；grep 全仓活规格零残留（仅评审文档历史引称） |
| m1 | **落地 ✓** | M8-2 T4 action:229-235（DECISIONS 同批登记收窄差：fold discriminator = resolved arm 窄于 header `rawValue > 0` 字面形）+ T6 action:300-303 DECISIONS 落盘清单同批 | 双落点均有 review m1 标记；charter 契约修订面定性表述准确 |
| m2 | **落地 ✓** | CONTEXT 特别登记一:18-26（FilmSubRunKernels.metal 移出豁免面 → 恒零 diff + 光谱核正业 = 新建 SpectralFilmKernels.metal）+ 红线 2:408-411 同批 + 引称改「M7-6/M3-3 封存清单邻接面（四名中仅 PixelPipe 在册）」 | 两处矛盾消解；与 M8-1B/M8-2 冻结红线方向一致 |
| m3 | **落地 ✓** | CONTEXT 红线 1:397-400：FIX2③ = LibraryProjectController.swift（AGENTS:395 现行）+ McpServerController.swift 零 diff 延续面双列 | 两真身均本轮 ls 实证在库（Library/ 与 MCP/ 大写目录——红线 1 只写裸文件名无路径前缀，grep 可命中，无残留问题） |
| m4 | **落地 ✓** | M8-2 T1 action:127-133（断言改「resolving 全域 → 密度 payload 形——含 rawValue=2 clamp 面」+ 后移说明）+ T4 action:236-238（「v2 档 → 光谱 payload 形——T1 后移断言，bump 后为真」） | T1 时序不可能断言已清除（grep 证实「v2 文档 → 光谱」仅存于 T1 的原因注记内，非活断言）；T1/T4 双落点带标记 |
| m5 | **落地 ✓** | M8-1B red_lines:11（红线 16 GPL 移植合规入高相关清单）+ T1 验收:135-138（文件头 GPL 归属块 + NOTICE 登记行 grep 双断言） | 红线 17 条清单闭环；机检判据可操作 |
| m6 | **落地 ✓** | M8-2 T2 action:160-162：「消费 M8-1a T4 SpectralBuildEngine 积分面〔review m6〕」 | 指称勘正；grep「消费 T2 引擎」零残留 |
| m7 | **落地 ✓** | M8-1A T4 action:256-258：preflight 参数面预留（`preflash_exposure /* 0 */` sim.h:552 默认 0 恒等关 + typed 占位与黑白点臂同待遇 + DECISIONS 注记） | 本轮 dt grep 实锤 sim.h:552 逐字吻合 |
| m8 | **落地 ✓** | CONTEXT X5:271-274：「Swift 侧显式 `fma()` 调用——禁依赖编译器 contract 合并；MSL 侧 `fma()`」+ 原文残缺注记 | 表述完整；`&*` 字样仅存于勘误注记引文中 |
| m9 | **落地 ✓** | M8-1B SC:9 + T2 action:152-155 + T2 红线:172-174 三处：tc_lut 载体 = rgba32Float（alpha pad，体积门 442KB 量级弹性）或 buffer，与 kernel 消费签名一致 | grep「texture2d float3 / texture2d×float3」全五文件零命中 |

---

## 数字链亲算（全链闭合）

- **M8-3 行和**：T1 +2..3 / T2 +2..3 / T3 +4..5 / T4 +2..3 / T5 0 / T6 0
  → **10..14 = 表称 ✓**（front-matter `estimated_tests`、ΔN 表、CONTEXT
  分账表三处同值）。
- **四 plan 行和**：1a 18..24 ✓ / 1b 12..18 ✓ / M8-2 20..26 ✓ / M8-3
  10..14 ✓（逐行亲算）。
- **累计带**：4206 + 18..24 = 4224..4230 ✓ → +12..18 = 4236..4248 ✓ →
  +20..26 = 4256..4274 ✓ → +10..14 = **4266..4288 ✓**；
  4206+60=4266 / 4206+82=4288 ✓；合计行 +60..82 ✓。
- M2 择径后终值带 4266..4288 全链零漂移——保带择径的意图达成。

## 标记与残检

- **review 标记**：五文件合计 **39 处**（`review B1` ×9 / M1 ×4 / M2 ×3 /
  M3 ×4 / M4 ×2 / m1 ×2 / m2 ×3 / m3 ×1 / m4 ×2 / m5 ×3 / m6 ×1 / m7 ×1 /
  m8 ×1 / m9 ×3），15 条全谱系覆盖，落点与上下文逐处通读（≥10 抽核要求
  以全量满足）；CONTEXT 尾部勘误登记节逐条索引落点。
- **grep 机检（活规格零残留）**：
  - `[[Float]]` 硬型 → 仅存 logSensitivity 语境（SC:9 / action:111）与
    「非可选对 null decode 即 throw」 rationale 句——log_sensitivity 零
    null 实测下保留非可选为正确形态，非残留；
  - `UI/Inspector/FilmPanelView` → 活规格零命中（仅 M8-PLAN-REVIEW.md
    历史引称）；
  - `texture2d float3` / `texture2d×float3` → 五文件零命中；
  - 「消费 T2 引擎」→ 活规格零命中；「<100ms 级」→ 零命中。
- **无评审外发明**：三处出入点均实测有据（见对账表）；唯一超处方着墨 =
  M8-3 T2 构成列补「读数对照记录测试」为 +1 对账（与 T2 既有「response
  读数变化登记 by design」SC 项同构，无害）+ M8-1A 风险节「per-sim 一次」
  →「per-pair 缓存一次」（与 X7 一致性顺路修正）。均记 note 非残留。

## 残留（退回依据）

### R1 — M3② 消费要素未落 plan 层：X7 tc_lut 缓存 face 在 M8-2 plan 零锚点

- **事实**（本轮 grep 实证）：
  1. `M8-2-PLAN.md` 全文 **零处提及 tc_lut**（grep 零命中）；
  2. requirements 行 8 的 charter 枚举 = `D-M8-1/D-M8-8 + X4 + 红线
     2/3/17`——**X7 不在枚举**（执行者权威读单不见 X7）；
  3. T3（bake 家族）标题/action/验收域 = **仅 print/scan PCHIP 33³**，
     read_first（RESEARCH §4.3 + FilmPrintBake.swift + SpectralBuildEngine
     .swift + M8-1A-DECISIONS）无 CONTEXT/X7；验收门「恰一产线文件」
     对 tc_lut 槽缺位无拦截；
  4. T1（分叉骨架）read_first/action 无缓存命中消费注记。
- **机理**：执行模型 = 按 plan 文件 read_first → action → 验收核验推进
  （AGENTS.md Phase 执行模型）；X7 的裁决与「禁临场发明」禁令都在
  charter 侧，M8-2 执行者按 plan 自带读单**不会触达 X7** → bake 家族按
  T3 字面只建 PCHIP 槽 → tc_lut 每 run 重建（秒级/表 × per-run）——正是
  M3② 处方要消解的 hazard；且 CONTEXT 勘误登记「M8-2 T3 承载/T1 消费」
  在 plan 层账实不符。
- **修复处方**（一批 plan 文本，零源码）：
  1. M8-2 requirements charter 枚举补 X7；
  2. T3 标题/action 1 增 tc_lut 槽位（与 PCHIP 槽并存、各自 LRU、容量
     DECISIONS 申报——X7 形态）+ read_first 补 CONTEXT X7 + 验收标准补
     「tc_lut 缓存命中面断言（同 pair 二次构建 = HIT）」；
  3. T1 action 2（光谱臂 payload 构造）补「消费 tc_lut 缓存命中面（X7）」；
  4. CONTEXT 勘误登记 M3 行注记消费落点回注完成（或维持现文——R1 闭合后
     即为真）。
- **严重度与时序**：minor 级文本批；**不阻 M8-1a/M8-1b 开波**（消费点在
  wave 3 M8-2）；**M8-2 开工前必须闭合**。

## Notes（非违反，记录在案）

1. M8-3 T2 构成列「读数对照记录测试」为 +1 对账补注——超出处方字面但与
   既有 SC 项同构，无害。
2. M1 引称勘误（评审 spektrafilm.c:601 → sim.h:601）经本轮独立 grep 实锤
   为**真勘正**——fixer 对评审正本的微差纠错有据。
3. M8-1B T2:158「run-scoped 生命周期」字样保留——指 GPU 载体（instance
   消费面）per-run 上传，与 X7 缓存的构建成本面（Swift 侧 Float64 表）
   正交，非矛盾；R1 闭合后 T3 缓存面与 T2 上传面的分工在 DECISIONS 一句
   说清即可（可在 M8-2 执行期顺路）。
4. m7 处方「preflash」fixer 写作「preflight」仅出现在 commit message
   正文，plan 文件内拼写正确。

## 可执行性终判

- **B1 修复后 M8-1a T1 按 SC 可实现**：`[[Float?]]`/`[Float?]` 为标准
  Codable 解码面（null → nil）；投影 face 单源有产线先例同位
  （baseDensityProjection 家族，FilmProfile.swift:25/:170）；冒烟断言
  数值带（15-78/243、5-26/81）经本轮 28 张独立重扫**可操作**；缺键旧
  JSON 零漂移负测不受影响（decodeIfPresent/encodeIfPresent 惯例不变）。
- **四 plan 就绪度**：M8-1a ✓（B1/M1/M3③/m7 齐）、M8-1b ✓（M1 注记/m5/
  m9 齐）、M8-3 ✓（M2/M4 齐）——三者可按 wave 序开工；**M8-2 有 R1 一处
  plan 文本缺口，开工前须闭合**（约 4 个触点的单批勘正，见修复处方）。

> 本复核零源码触碰；唯一产出 = 本文件。数据面结论以本轮 28 张 profile
> 独立重扫为准（非转录评审数）。
