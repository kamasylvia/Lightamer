# M8-PLAN-REVIEW — M8-1 四 plan 独立 goal-backward 评审（2026-10-24）

> 评审对象：本目录 `CONTEXT.md` + `M8-1A-PLAN.md` + `M8-1B-PLAN.md` +
> `M8-2-PLAN.md` + `M8-3-PLAN.md`（HEAD `179c78f3`，五文件 1664 行）。
> 上游对照 = `RESEARCH.md`（`9b256482`）+ `RESEARCH-PRE.md` + 产线源码亲读
> （FilmTailPolicy / PixelPipe / RenderProcess / LightamerSidecar /
> FilmProfile / FilmSolveCache / FilmPrintBake / FilmDeterminismTests /
> NOTICE / test-direct.sh / machine-guard.sh）+ dt 上游亲读抽核
> （`spektrafilm.c` / `spektra_sim.{c,h}` / `spektrafilm.cl` / 单测）+
> **28 张 profile JSON 数据面实测扫描**（nullability / 键在册性）。

## 结论头

**FAIL / 1 blocking + 4 major + 9 minor**

- 架构面无实质缺陷：四 plan 依赖链、缝位零改纪律、process v2 五件套、
  双臂冻结 golden、三板斧逐项落点、GPL/CC BY-SA 双许可合规、测试六门——
  亲核全部成立；RESEARCH §6 六目标逐项有 plan 承载且验收可机检。
- 1 blocking = 谱字段类型面与 28/28 数据实态不符（nullability），
  **修复轮（plan 文本一批勘正）后即可放行执行**；4 major 中两条
  （remap 缺口 / tc 拟合身份-缓存-成本模型）须在 M8-1a 开工前落 DECISIONS
  或 CONTEXT 修订，另两条（ΔN 算术 / 面板路径坐标）为 plan 文本勘误。

---

## 亲核覆盖声明（本轮实测，非转录）

1. **产线八条登记全核**（CONTEXT §亲核登记①-⑧）：①基线证据链
   （LUMEN-BC-ACCEPTANCE.md:13 `TOTAL|4204/41/0|` + d2bcaf06 commit body
   「Library bundle: 13/0/0 (includes the two new tests)」→ 4206 ✓）；
   ②FilmProfile 类型面四项 + viewingIlluminant zero hit ✓，六键 28/28
   JSON 在册 ✓；③行号抽核（runTerminalTails :1145 / policyTag :89 /
   seed 四项序 :100-112 / FilmMethodBox :197 / iopOrder 74.0 :227 /
   displayReplayResidents :164-185 / solve cache 键+LRU 8+RECORD-terms
   :441-501 / FilmPrintBake 65³ Float64 / RenderProcess 账本 :107-150 /
   sidecar schemaVersionCurrent=11 :255 + process 键 :385）✓；
   ④filmRampPlaneHash=14_365_179_805_968_017_957（FilmDeterminismTests
   .swift:44）✓；⑤probe 先例（LensPerfProbe/DepthPerfProbe/
   GradeEnvelopePerfProbe/ColorMatchBakeGolden 四件在库）✓；⑥七 bundle
   （test-direct.sh:173）✓；⑦NOTICE §2 谱数组披露在册 ✓；⑧machine-guard
   v1.4（--monitor 在位）✓。
2. **dt 上游抽核 ~15 处全吻合**：tri2quad（sim.c:1719-1727）/
   hanika_sigmoid（:1732-1737）/ PCHIP float twin（:2137-2145）/
   Kr=0→1e30 哨兵（:4085）/ FP_CONTRACT 注释（cl:91-103，host honored
   device ignored）/ inv_le_step+enl_inv_range host-double（sim.h:262-284，
   含「real CPU/GPU divergence」原文）/ exact spectral no GPU path
   （sim.h:249-251）/ sf_sim_build tc 六段（sim.c:3664-3861，sens_w→
   adaptation→逐 cell 积分→kind→remap）/ expose 单取倒+Y=0 硬化
   （sim.c:3394-3406）/ exposure_ev 进 sim 键（spektrafilm.c:1514）+
   链头消费（:1780）/ adaptation 双开关默认（spektrafilm.c:324-332
   bandwidth TRUE / surface FALSE + sim.h:483-497 同款）/ 上游单测内嵌
   期望值（test_spektra_sim.c eps 1e-9/1e-6 + 0179-spektrafilm
   expected.png——「dt 同源对表」可操作性实证）/ input_gamut_compress
   **默认 true**（spektrafilm.c:601）/ preflash 默认 0（sim.h:552）。
3. **数据面实测（本轮新增，planner 未做）**：28 张 profile 逐一扫描——
   `log_sensitivity` 全带零 null；`channel_density` **28/28 含 null**
   （15-78/243）；`midscale_neutral_density` **28/28 含 null**（5-26/81）；
   `window_params` = 4 标量、`surface_params` = 3×15 矩阵。
4. **ΔN 算术逐 plan 亲算**：1a 18..24 ✓ / 1b 12..18 ✓ / M8-2 20..26 ✓ /
   **M8-3 行和 9..13 ≠ 表称 10..14（见 M2）**；累计带 4224..4230 /
   4236..4248 / 4256..4274 / 4266..4288 逐级闭合 ✓（基于表称值）；
   4206+60=4266 / 4206+82=4288 ✓。

---

## Blocking（修复轮必须先做，回注 M8-1a plan 文本）

### B1 — 谱字段类型面与数据实态不符：channel_density / midscale_neutral_density 全 28 张含 null，plan 写死非可选类型 = 两字段全档丢失

- **severity**: blocking。
- **证据**：
  - `M8-1A-PLAN.md:112-113`（T1 action）：`channelDensity: [[Float]]`
    （81×3）/ `midscaleNeutralDensity: [Float]`（81）——非可选；
  - `M8-1A-PLAN.md:9`（SC）：同型写死；
  - 数据实测：28/28 profile 的 `channel_density` 含 null
    （如 kodak_portra_400 22/243、kodak_kodachrome_64 78/243、
    kodak_endura_premier 66/243）；`midscale_neutral_density` 28/28 含
    null（5-26/81）；
  - 同结构体先例：`FilmProfile.swift:171` `baseDensity: [Float?]`
    （「nullable at the ends」——上游同款 null 语义已有 typed 先例）；
  - 下游依赖：T4 构建引擎的印相/扫描 81 波长积分消费 channel_density
    （RESEARCH §1.4 `cmy_to_print_lograw = Σ_l illum·10^-(base+Σchan·cmy)`）。
- **机理**：`[[Float]]` 对含 null JSON decode 即 throw →「违形 = nil 降级
  不 throw」的宽容门会把**整字段**降 nil（非逐点）→ 六项解码正例若断言
  非 nil 值则 T1 当场失败；若正例只断「decode 成功」则两字段静默全档
  nil，T4 引擎在空数据面上开工，失败污染下游。
- **处方**：T1 类型面改为 `channelDensity: [[Float?]]` +
  `midscaleNeutralDensity: [Float?]`（baseDensity 同款），null 语义 =
  投影/插值 face 单源（`baseDensityProjection()` 家族同位，防每个消费点
  自带插值）；SC :9、28 张全量冒烟断言（「81 点/轴一致/值域带」）同步
  null-aware；`FilmProfileAdaptationParams` typed 载体注明双形
  （window 4 标量 / surface 3×15 deg4）。

---

## Major（M8-1a 开工前须落定或勘正）

### M1 — 输入 gamut 压缩 remap（上游默认 on）未落入任何 plan 任务面

- **severity**: major。
- **证据**：RESEARCH §1.2 构建六段之⑥明确「输入 gamut 压缩 remap：
  new[tc]=old[compress(tc)] 径向 xy Reinhard (0,1,6) 压向光谱轨迹多边形
  （3826-3851 + 1778-1847）——预折进表」；dt `spektrafilm.c:601`
  `bool input_gamut_compress; /* true */` = **默认开启**的默认语义面；
  而 `M8-1A-PLAN.md` T4 action 1 构建清单（tc 展开/中性配平/印相扫描表/
  黑白点拟合臂）无 remap 步；`M8-1B-PLAN.md` T1 expose kernel 列
  （m_in mat→Σxyz=Y→互倒→tri2quad→Mitchell gather→×Y×ev）亦无。
- **后果**：out-of-locus 场景色度（真实照片常态：饱和高光/窄谱 LED）
  fetch 语义与上游默认不同（clamp 透传 vs 压向 locus）；自建 golden 是
  自指系统测不出该缺口，仅 dt 同源对表可能暴露——漏检即静默语义偏离。
- **处方**：M8-1a T4 增 remap 构建步（compress_xy_radial 数学面 +
  「白心 = proj_xy」居中纪律——sim.c:3840-3843 注释明示居中错位会走样）
  或 DECISIONS 显式申报「v1 省略 remap + 边界行为声明 + 用户可见面无
  对标损失」二选一；M8-1b T1 expose 列表同步注记。

### M2 — M8-3 ΔN 预算表内部算术不闭合（行和 9..13 ≠ 表称 +10..14）

- **severity**: major。
- **证据**：`M8-3-PLAN.md` ΔN 表逐行：T1 +2..3 / T2 +1..2 / T3 +4..5 /
  T4 +2..3 / T5 0 / T6 0 → 行和 = **9..13**；同表合计行与 front-matter
  `estimated_tests` 均写 **+10..14**（首尾各差 1）；`CONTEXT.md` ΔN 分账
  表 M8-3 行 = +10..14 → 终值带 4266..4288 以此为基。其余三 plan 行和
  亲算全部闭合（18..24 / 12..18 / 20..26 ✓）。
- **后果**：对账式 ΔN 纪律下，M8-3 收口对账必现 ±1 越带噪声；终值带
  严格说应漂移为 4265..4287。
- **处方**：两处择一——某行 +1（如 T2 改 +2..3）或合计勘正 9..13 并同
  批同步 CONTEXT 分账表与终值带表述（4266..4288 → 4265..4287）；
  M8-3 front-matter `estimated_tests` 同批。

### M3 — tc 自拟合的身份/缓存/成本模型未钉死：X1 与 X2 内部矛盾 + tc_lut 运行期缓存 face 缺位 + 时长带估乐观

- **severity**: major。
- **证据**：
  - 矛盾：`CONTEXT.md` X1「拟合器……输入 = 常量资产 + **胶片 sens 数据**，
    输出 = 系数表」暗示 per-film 拟合；X2 卖点「系数表……换光源/感光度
    适配**零重拟合**」= 共享系数表（film 无关 metameric 目标）。T3 正文
    （`M8-1A-PLAN.md:186-189`「拟合目标谱生成……该色度 metameric 谱的
    构造式——论文式」）指向共享形，但 X1 的 sens-输入句未被勘正——
    拟合目标构式（目标谱是否含 film 响应形）是 T3 执行者无法自裁的
    设计分叉。
  - 缓存 face 缺位：M8-2 T3 的 LRU bake 家族**只覆盖 print/scan PCHIP
    per-pair**（`M8-2-PLAN.md:190-192`）；`M8-1B-PLAN.md` T2 载体明写
    「run-scoped 生命周期」——tc_lut（含其上游拟合 + 展开 + 积分全成本）
    无任何跨 run 缓存 face。对照先例：密度域 65³ bake 有 per-pair LRU。
  - 时长带估：T5（`M8-1A-PLAN.md:258-259`）「tc 构建估 <100ms 级/表」
    ——192²=36864 cell × Float64 非线性拟合（确定性迭代）+ 33³×2 套
    81 波长积分（~5.8M 次超越函数），纯 Swift 串行合理量级为秒级；
    <100ms 大概率低 1-2 个量级。
- **后果**：每 run 重建 = 秒级/帧不可接受；每会话重建 = 首帧大停顿且
  28 张全量构建冒烟预期失真；执行者被迫临场发明缓存 face（越权面）。
- **处方**：CONTEXT 修订三句——①X1 勘正「sens 仅入质量门与积分，不入
  拟合目标（系数表 = 色度域共享，film 无关）」或反向钉死 per-film；
  ②新增 tc_lut 缓存 face 裁决（FilmPrintBake 家族同位 per-film LRU 或
  新 SpectralBuildCache，M8-2 T1/T3 消费）；③T5 时长带改为「秒级/表量级
  带 + concurrentPerform 并行预期 + 实测 DECISIONS 申报」。

### M4 — M8-3 面板文件路径坐标错误：UI/Inspector/FilmPanelView.swift 不存在

- **severity**: major。
- **证据**：`M8-3-PLAN.md:20`（files_modified）
  `App/Sources/Lightamer/UI/Inspector/FilmPanelView.swift` 与 `:91`
  （T1 read_first）同路径——实测真身 =
  **`App/Sources/Lightamer/UI/Shell/FilmPanelView.swift`**
  （FilmPanelModel.swift 同在 Shell/；UI/Inspector/ 下 film 相关仅
  FilmicRGBPanelView.swift）。
- **后果**：commit-scope 清单与验收判据（「git diff --stat 恰两产线
  文件」）指向不存在路径；执行者须临场勘正。
- **处方**：M8-3 files_modified 与 read_first 两处路径勘正为
  `App/Sources/Lightamer/UI/Shell/FilmPanelView.swift`。

---

## Minor（随修复轮顺路批，不阻断）

### m1 — 折键「非 legacy 才折」引用口径与实作的收窄差未登记

- **证据**：`RenderProcess.swift:41-43` header 契约字面形 =
  `process.rawValue > 0` 折（**含 v1**）；`CONTEXT.md` X4 与
  `M8-2-PLAN.md` 红线 3 的实作 = 臂判别（仅 v2 光谱臂换 policyTag，
  v1+legacy 双档键恒等）。实作是零漂移主门的必要收窄（v1 若折值则
  filmRampPlaneHash 恒等门必破），但 charter 把它记作「:37-44 契约」的
  执行，严格说是契约修订面。
- **处方**：M8-2 DECISIONS 显式登记「fold discriminator = resolved arm
  （光谱/密度），窄于 header `rawValue > 0` 字面形——v1 键冻结是主门
  要求」。

### m2 — CONTEXT 红线 2/特别登记一豁免清单把 FilmSubRunKernels.metal 列为「本批正业」，与两执行 plan 冻结红线矛盾

- **证据**：`CONTEXT.md:20` 与 `:383-384` 豁免清单含
  `FilmSubRunKernels.metal`；`M8-1B-PLAN.md:16`（既有 .metal 全仓零
  diff）与 `M8-2-PLAN.md:16`（film_subrun kernel 逐字节冻结）反向钉死。
  另外 FilmTailPolicy/FilmPrintBake/FilmSubRunKernels.metal 本不在
  AGENTS.md M7-6 封存清单内（「M7-6 封存面清单中」引称失真，四名中仅
  PixelPipe 在册）。
- **后果**：charter 层许可与 plan 层冻结冲突；per-plan 红线是操作门故
  风险低，但 checker 对照 charter 会见矛盾。
- **处方**：CONTEXT 两处勘正——FilmSubRunKernels.metal 移入冻结面
  （或注记「恒零 diff，新建 SpectralFilmKernels.metal 才是正业」）；
  「M7-6 封存面清单中」引称改「M7-6/M3-3 封存清单邻接面」。

### m3 — FIX2③ 指称漂移：CONTEXT 沿用 M7 旧指称（McpServerController），AGENTS 现行 = LibraryProjectController

- **证据**：`CONTEXT.md:374-375`（红线 1）= `App/Sources/Lightamer/Mcp/
  McpServerController.swift` 零 diff；`AGENTS.md:395` 跨批不变量 =
  「FIX2③：`LibraryProjectController.swift` 零 diff（连续六波亲证）」。
  M7 时代 FIX2③ 确指 controller（ARCHIVE 多处），后已重登记。
- **处方**：CONTEXT 红线 1 按 AGENTS 现行登记勘正，或双列「FIX2③ =
  LibraryProjectController.swift（AGENTS:395）+ McpServerController.swift
  零 diff（M7-4 起延续面）」。

### m4 — M8-2 T1 的 v2 分叉断言在 T1 时序不可满足

- **证据**：`M8-2-PLAN.md:141`「禁在 T1 引入 v2 case（bump 归 T4——T1
  先以 resolving 现表〔恒 v1〕落地分叉骨架）」；而 T1 测试清单 `:127-129`
  含「v2 文档 → 光谱 payload 形」断言——T1 时 `all=[.v1]`，
  `resolving(2)` forward-clamp 回 v1，该断言不可能为真（光谱臂代码亦无
  从挂载）。
- **处方**：该断言移 T4/T5；T1 改断言「resolving 全域（含 rawValue=2
  clamp 面）→ 密度 payload 形」。

### m5 — M8-1b 高相关红线清单漏红线 16（GPL 移植合规），T1 验收无归属机检

- **证据**：`M8-1B-PLAN.md:15-18` 高相关清单仅列红线 2/7/8/14；kernel
  族是本批最大 GPL 衍生面（.cl→MSL 移植），版权头 + Modified by
  Lightamer + NOTICE 登记纪律（CONTEXT 红线 16）未入 T1 验收机检。
- **处方**：T1 验收补一条「文件头 GPL 归属块 + NOTICE 登记行在库」
  grep 机检。

### m6 — M8-2 T2「消费 T2 引擎积分面」指称错位

- **证据**：`M8-2-PLAN.md:157`——引擎 = M8-1a **T4**（SpectralBuildEngine），
  1a T2 = 常量资产；「T2 引擎」两头不沾。
- **处方**：改「消费 M8-1a T4 SpectralBuildEngine 积分面」。

### m7 — preflash（RESEARCH §1.4）无参数面预留

- **证据**：`M8-1A-PLAN.md` T4 构建清单中黑白点拟合臂有「默认关，参数面
  预留」同款待遇，preflash（sim.h:552 默认 0，恒等关）无预留无声明。
- **处方**：T4 参数面预留一行或 DECISIONS 声明省略（默认 0 恒等，影响
  小）。

### m8 — CONTEXT X5 文字残缺：「Swift 侧 `a &* `→ `fma()`」

- **证据**：`CONTEXT.md:265`——`&*` 是整型溢出算子，Float 无此形；显式
  fma 纪律的表述残缺。
- **处方**：改「Swift 侧显式 `fma()` 调用（禁依赖 contract 合并）/ MSL
  侧 `fma()`」。

### m9 — tc_lut 载体形态「texture2d float3」非 Metal 可表达像素格式

- **证据**：`M8-1B-PLAN.md:163-164` 禁形「tc_lut = texture2d×float3」
  ——Metal 无 float3 像素格式（rgba32Float + alpha pad 或 buffer 二选
  一）；442KB 断言按「量级」措辞有弹性故不破门，但形态描述会误导 T2。
- **处方**：T2 载体形态改「rgba32Float（alpha pad，体积门按 442KB 量级）
  或 buffer，与 kernel 消费签名一致」。

---

## 评审清单九项逐项判定

| # | 清单项 | 判定 |
|---|---|---|
| 1 | 目标覆盖 | **达成**——RESEARCH §6 六目标逐项有承载：81 波长数学 = 1a T3/T4 + 1b T1；bit-exact = 1b T1/T3；缝位零改+process v2 = M8-2 T1/T4/T5（亲核吻合，见上）；资产自建+GPL fallback = 1a T2/T3 分支 + 红线 3/16；性能预算 = 1b T4 probe ②；coupler 降采样 = 1b T1 + probe ③ 双门。验收标准能证「达成」（golden 门 + probe 真值 + 零漂移负测），唯 remap 缺口见 M1 |
| 2 | 数学忠实性 | **骨架成立**——1b 七 stage 逐段公式在 action 内可溯至 RESEARCH §1.1-§1.6 行锚（本轮 dt 侧 ~15 处抽核全吻合）；三板斧 CPU/GPU 对称性写死（1a T4 落 host 常量面 / 1b T1 MSL 同表 + T2 host 取倒 + T3 三专项）；golden 双轨可操作（上游单测内嵌期望值实证在库）。缺口 = M1（remap）+ B1（数据面） |
| 3 | tc 自拟合 vs 直接谱表 | **决策成立、论据有缺口**——X2 1/27 体积（442KB vs 11.97MB）亲算成立；直接谱表否决理由（28×12MB 资产膨胀 + 上游存谱理由 = 跨胶片共享）成立；**构建时长预算乐观 + 拟合身份矛盾 + 缓存 face 缺位 = M3**；上游 build 期 33³ 成本（35937×81 积分）在 RESEARCH §1.4 有账、plan 侧未单独对账（fold 入 M3 处方③） |
| 4 | 缝位零改 + process v2 | **亲核全吻合**——runTerminalTails :1145 三段骨架 + filmTail==nil 零路径、seed 四项序 :100-112、3×2 降出矩阵 :164-185、FilmMethodBox 对外面（74.0/nil blit/instance 载体 :197-331）、solve 键形+LRU 8+RECORD-terms :441-548 与 plan 描述逐点一致；分叉点 = assembleFilmLeg/runFilmLeg 工厂（PixelPipe :1207-1267）准确；legacy 恒等负测设计在位（M8-2 T4.5+T5）。残留 = m1（折键口径）+ m4（T1 断言时序） |
| 5 | coupler 降采样臂 | **成立**——1/4-1/8 内存数亲算（1.2GB 全幅 → 75/18.75MB）✓；probe ③ 双门（RSS + 高频损失偏差带，全幅对照臂仅 probe 内）✓；8G 超门 fallback = 砍 coupler（禁用段 = 纯密度链）✓；与 M6-2 交互安全 by construction（fallback 裁决在 1b probe、bump 在 M8-2 T4 之后——v2 带何种 coupler 形上线无 post-hoc bump 问题；建议 DECISIONS 一句注记） |
| 6 | 依赖与编排 + ΔN | **结构成立、算术一plan 破**——1a→1b→2→3 依赖链 + wave/depends_on + 机器单重活 + C 档四停位 + --all 批准制全在；ΔN 亲算 1a/1b/M8-2 闭合，**M8-3 行和 9..13 ≠ 10..14（M2）**；累计带逐级闭合 |
| 7 | 测试策略 | **可操作**——dt 同源对表 = 上游单测内嵌期望值转录入 evidence 非 CI 门（`test_spektra_sim.c` eps 1e-9/1e-6 + 0179 expected.png 实证在库，「dt 跑不跑」答 = 不跑，跑不起）；构建期产物比对 = NumPy 对拍 evidence + Swift 独立复算为 CI 门本体；bit-exact 断言三级（表逐位/逐像素 ≤1e-6 带域/分段边界专项）+ legacy 双臂 + perf probe 五件（门/fence/RSS 口径齐）。缺口 = B1 的冒烟断言须 null-aware |
| 8 | 红线与转写勘误 | **front-matter vs AGENTS 三处指称漂移**——m3（FIX2③）/ m2（封存面引称）/ CONTEXT 红线 2 豁免清单自相矛盾；其余 17 条与 AGENTS 制度（V50Order add-only / L057 / L041 / xcstrings V14 / LocalizationValue 禁形 / process 正交性）逐条相符；亲核登记八条**全数复核成立**（超「抽 ≥5」要求），唯一增补 = 亲核登记②未查 nullability（B1 正体） |
| 9 | 遗漏 | **两处**——M1（remap 无承载）+ M3（tc 缓存 face）；OQ-M8-8 落位完整（D-M8-8 裁决 + M8-2 T2 实现 + M8-3 T4 钉死终账）；NOTICE 批修归属 M8-2→M8-3 调整在 CONTEXT 编排总纲显式声明（「M8-2/§任务清单以本编排为准」）✓；RESEARCH→plan 信息丢失检查 = 亲核登记②对 RESEARCH §3.3 的两项增补（midscale/viewingIlluminant）为正向细化非丢失 ✓；m7（preflash 预留）轻微 |

---

## 处方汇总（修复轮输入，按优先序）

1. **B1**：M8-1a T1/SC 类型面 `[[Float?]]`/`[Float?]` + 投影 face 单源 +
   冒烟断言 null-aware（文本批，零代码）。
2. **M1**：M8-1a T4 增 remap 构建步或 DECISIONS 申报省略 + 1b T1 注记。
3. **M3**：CONTEXT X1/X2 修订（拟合身份钉死）+ tc_lut 缓存 face 裁决
   （M8-2 T1/T3 落点）+ T5 时长带重估。
4. **M4**：M8-3 面板路径勘正（Shell/ 真身）。
5. **M2**：M8-3 ΔN 表行和/合计对齐 + CONTEXT 分账表同批。
6. m1-m9 顺路批（DECISIONS 登记 ×2 / CONTEXT 勘正 ×3 / plan 文本勘正
   ×4）。

> 本评审零源码触碰；唯一产出 = 本文件。评审方法 = goal-backward（RESEARCH
> §6 目标 → plan 任务 → 验收判据反向逐项闭合）+ 产线/dt/数据三层实测亲核。
