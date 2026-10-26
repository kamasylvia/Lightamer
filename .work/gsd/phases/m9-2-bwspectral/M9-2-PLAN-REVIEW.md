# M9-2 PLAN REVIEW — 黑白族 + 滤色镜光谱延展 plan 独立评审（2026-10-27）

```
评审对象: .work/gsd/phases/m9-2-bwspectral/M9-2-PLAN.md + CONTEXT.md
依据正本: RESEARCH.md（事实源）/ REQUIREMENTS M9BW-01..03 / ROADMAP §M9 /
          AGENTS 跨批不变量 / M8 先例（M8-2-PLAN + CONTEXT X7 + M7-6 封存面清单）
性质: 纯读评（零 commit / 零构建）；抽核锚点 26 个（本地仓 21 + SpektraLab 上游 5）
结论档位: PASS-with-notes
计数: 0 blocking + 1 major + 6 minor + 6 observations
```

---

## 一、结论档位：PASS-with-notes

plan 骨架成立：T1→T5 依赖序正确（数据面先行、T2 消费 T1 资产、T3 主门独立、
T5 收口）；六维评审全部有实底；26 个抽核锚点全部命中（其中 2 锚带发现）。
唯一 major 是 `paperGrade: Int?` 的档位编码缺裁决——上游 7 档含 "00" 与 "0"
两个**不同**档位，Int 类型无法无歧义表达，且该编码贯穿 sidecar v12 持久键 /
gradeTag 缓存键 / UI picker 三处消费面，属「plan 期钉死防执行临场发明」制度
（D-M92-5 自己立的原则）的同款场景——补一行裁决即可，不动摇 plan 结构。

---

## 二、分级清单

### blocking（0 条）

无。

### major（1 条）

**MAJ-1 `paperGrade: Int?` 档位编码歧义未钉死（D-M92-4 / X-M92-2 / T2 action 2）**
- 实锤：上游 `paper_grades.json` 档 key = `{"00","0","1","2","3","4","5"}` 共
  7 档（git show origin/main 亲核），"00"（y_filter_neutral 199.0）与 "0"
  （137.9）是两个不同档。`Int?` 下二者无法区分（0 只能表达其一）。上游 wire
  无 paperGrade Int 先例（grade 档是表 key 字符串 + m/y_filter_neutral 浮点
  对），Int 编码为本站自创。
- 波及面：sidecar v12 双键之一（入盘即 ONE-WAY 格式锁）+ D-M92-5 gradeTag
  折 print/scan 槽键的折叠值 + UI picker「无/00-5 档」数据源——三处共享同一
  编码，执行临场任选将使持久化语义无裁决定形。
- 修复要求：执行 T2 前在 CONTEXT/DECISIONS 补编码裁决（三选一即可：
  `Int? ∈ {-1..5}` 且 -1≡"00"；或 `String?`（"00".."5" verbatim）；或
  `PaperGrade` 枚举 rawValue String）。plan 其余面零改动。

### minor（6 条）

**MIN-1 midscale_neutral_density 折入 fold 与「fold = 消费集」设计注释相悖（D-M92-5 / T3 action 4）**
- `FilmMaterialStore.foldProfile` 的 doc 注释明文「The folded fields are
  exactly the consumed ones…identity and consumption can never drift apart」；
  而 `SpectralBuildEngine` 对 `midscaleNeutralDensity` **零消费**（grep 全文
  仅 logSensitivity :374/:575、channelDensity :384/:585、viewingIlluminant
  :408-412 在消费）。log_sensitivity/channel_density/viewing_illuminant 三键
  折入 = 真对齐消费集（M8 遗留漂移的实锤修正，判断正确）；midscale 折入是
  超集。终清单 DECISIONS 落地时应改理由为「防未来消费扩面预折」或剔除——
  按现表述「对齐消费集」写入会与源注释直接矛盾。

**MIN-2 SidecarV12Tests 落域 Layers 与近例不一致（T2 / files_modified）**
- BUNDLE-MAP 实况：SidecarV10Tests = **LIB**（:733）、SidecarV11Tests =
  **LIB**（:739）、SidecarV7Tests = APP（:323，早期）。sidecar 测试近例两连
  在 LIB，plan 指定 Layers 无先例。E2 登记（front-matter 判定）时会被挑；
  建议对齐 LIB 或在 DECISIONS 说明漂移理由。

**MIN-3 T2/T3/T4 各任务缺「本任务 Project.swift 数组登记 + tuist generate
末位」步骤文字（对照 L041 逐批纪律）**
- plan 只在 T1 action 7（T1 测试 + folderReference）与 T5 action 1（全量
  核对）写了 Project.swift；T2-T4 各新增 2-4 个测试文件且验收标准要求
  「构建绿 + 测试绿」——测试要跑就必须当批登记（验收机制实际兜底，机械
  执行者仍可能漏）。files_modified 的注记（「T5：…随 T1 资产落位」）强化
  了「T2-T4 不动 Project.swift」的误读。补一句「每任务 commit 含各自
  Project.swift 数组行 + tuist generate 末位（L041），T5 只做全量核对」。

**MIN-4 封存面计数口径 15 vs 17（红线 5 / T5 action 4）**
- M7-6-01-SUMMARY 原始清单 = **封存面 17 件**（含 IOP Registry / ModuleInstance
  两件，:47 亲核）；plan 红线 5 的「15 项」跟随 AGENTS 速查口径。本站零
  v50 新 iop / 零 Registry 面，两件被触概率≈0，实质风险可忽略——但机检
  清单若照 plan 执行会少检两件。备考性 minor：T5 机检按 17 件全集跑或注记
  口径来源。

**MIN-5 FilmPanelModel.isPristine 手写判定面未被注意事项点名（T2 action 3）**
- pristine 判定有两处面：Core `isFilmRecordDefault`（FilmRecord.swift:141，
  synthesized == 自动覆盖新字段 nil 档 ✓ 无需扩）+ App `FilmPanelModel.
  isPristine` **手写逐字段判定**（FilmPanelModel.swift:80-83 亲核——
  `r.filmStock.isEmpty && … && r.exposureEv == 0 && !hasActiveRecord`）。
  后者加 cameraFilter/paperGrade 后必须手扩，否则「仅 grade/filter 设置」
  的 record 在 UI 面被误判 pristine。T2 测试「pristine 判定扩」隐含覆盖，
  但 action 文字只点名了 isFilmRecordDefault——补点 FilmPanelModel 面一句。

**MIN-6 FilmRecord 新字段必须进 CodingKeys——静默丢字段风险未提醒（T2 action 2）**
- FilmRecord 是手写 `init(from:)`（tolerant decode，FilmRecord.swift:107-118）
  + synthesized encode；stableHash = canonical JSON encode（:123-132）。新
  optional 字段**不进 CodingKeys 时编译通过、decode 恒 nil、encode 静默丢
  键、recordHash 不含**——一处三静默。plan 说「stableHash 自动含」成立的前
  提是 CodingKeys 同步扩，建议 plan 显式提醒（Swift 经验者会做，防机械执行）。

### observations（6 条，不计级）

**OBS-1 sidecar v12 bump 触封存面的豁免判定：成立（评审亲核先例）**
- 任务书专项核对项。事实链：①封存面清单登记于 M7-6 收口（2026-10-17），
  其后 sidecar 从未被动过（M8 明确「无 schema bump」——GOAL-STATE 勘误行在
  案）；②v12 将是封存面登记后 sidecar **首次** bump；③但豁免依据充分：
  LightamerSidecar 文件自带 bump 章程（:247-254 bump 注释链 v8 aiProvenance
  / v9 filmRecord / v10 process / v11 note——「a persisted-face addition
  bumps」亲核在案）；AGENTS 速查表述「sidecar schema 现行 v11
  （schemaVersionCurrent 单源）」承认 bump 机制存在；plan 侧申报完备
  （CONTEXT 红线 5 显式例外 + D-M92-4 先例链引证 + plan red_lines 复述 +
  T5 机检「除 sidecar v12」）。结论：**bump 豁免成立**；SUMMARY/DECISIONS
  落账时建议显式登记「封存面登记以来首例 sidecar bump」事实。

**OBS-2 golden 真值自建的验收判别力评估：结构性错误充分 / common-mode 弱——
R8 风险声明诚实，接受**
- 任务书专项核对项。中性门（三通道散 ≤2e-3）是结构性判别：数据三通道不同
  值 / 引擎色偏 / 相纸谱错（三乳剂分裂错同样破坏中性闭合）都会红——判别力
  保留 ✓。盲区 = common-mode（整谱平移的绝对标定漂移）——阶调门 18% 灰
  0.55-0.95 带宽（±40%）对此判别弱；唯一外部定量锚 = 滤镜因子交叉（6/7
  ≤0.21 档，T3 ⑧）。后果限定在「打印观感无 bit 对照对象」域，plan 的
  「登记即合规、不伪装成 bit 级真值」立场与上游 bw_checks 同构（同为带状
  断言非 bit 真值）。判定：充分性可接受，无需加门。

**OBS-3 OQ 编号勘误验证：产物面全自洽，无残留错位**
- 任务书专项核对项。交叉核对范围：CONTEXT D-M92-1..8 ↔ RESEARCH §6
  OQ-M92-1..8 逐条对齐 ✓；CONTEXT:41 与 PLAN:331 引「OQ-M9-8 站级裁决
  『仅标定面』」= charter 级 OQ-M9-8（ROADMAP §M9「OQ-8：仅标定面」正本
  一致）✓，与站级 OQ-M92-x 双轨不混淆 ✓；charter 输入 OQ-M9-1..9 与
  ROADMAP 简写（OQ-2A/OQ-5/OQ-7/OQ-8/OQ-9）全对应 ✓；PLAN frontmatter
  requirements 三条与 REQUIREMENTS M9BW-01..03 验收形态逐字一致 ✓。规划
  任务书原文不在库（无法反推勘误动作本身），但落位结果零错编号。

**OBS-4 基线数字勘误确认：plan 取值正确**
- charter 输入记 M8-3 全套 4286/46/0（2026-10-26 三眼时刻）；plan 基线 =
  4287/39/0 并标注「GOAL-STATE 2026-10-26 亲核」——GOAL-STATE 深夜续接点
  原文「四 plan ΔN+80 + M8-FIX +1，全套 4287/39/0」亲核吻合（修正批 +1 后
  终态）。plan 取终态正确，charter 数字为陈旧值非 plan 缺陷。

**OBS-5 双 .metal 零 diff 可守性：结构性成立（亲核插入点）**
- X-M92-1 插入点亲核：SpectralBuildEngine :451 = window 段闭合、:453 = tc
  注释行——「窗口段后、tc 循环前」坐标精确；滤镜只改 build 期 sensW 输入，
  kernel 消费表（tc_lut/print/scan）形态不变 → 零 kernel 触碰是结构保证非
  纪律保证 ✓。T3 机检（git diff 两文件零命中）可守。附带自洽性验证：
  T3 fold 对齐改变全量 pairHash → 缓存全冷 miss → build 确定性 → 渲染输出
  逐字节不变 → filmRampPlaneHash 哨兵族不受扰（hash 只做缓存键，grep 消费
  点亲核：PixelPipe/FilmPrintBake/FilmTailPolicy 全为运行时缓存，零持久化
  消费）✓。

**OBS-6 数字化工具依赖形态未写明（T1 action 2）**
- 「uv run python3 + pdfplumber」符合全局 Python 红线，但 pdfplumber 的注入
  形态（`uv run --with pdfplumber` 或 PEP 723 inline metadata）未写。执行
  细节，DECISIONS 顺带落即可。

---

## 三、六维评审明细

### 1. 目标回溯（M9BW-01..03 验收形态逐条可兑现）— PASS

- M9BW-01「profile 入谱面体系 + MANIFEST 对账 + 中性/阶调 golden」→ T1
  （资产 + MANIFEST + schema 接受）+ T2（中性门/阶调门）全覆盖；「BW 落盘
  即 decode」的根据亲核成立（FilmProfile channelModel :148 / 六谱键
  :225-233 M8-1a additive decode 在位；上游 Tri-X dump 三通道同值 + 1/3
  密度 + channel_model:"bw" 亲核——「BW 语义由数据涌现」论断实证）。
- M9BW-02「滤色镜 ON/OFF 中性链零漂移负测 + 光谱透传 golden」→ T3 负测组
  ⑤（nil 档 = M8 基线逐字节）+ 门 3/4；「4+ 卷」下限的回退条款（<4 停手
  上报）诚实。
- M9BW-03「per-film 标定表 + 强度语义断言」→ T4（表 + 推荐强度层 + RMS 同
  带断言）；GrainModule :50-76 dt 三滑杆无 per-film 概念亲核——量纲桥必要
  性实证成立。
- golden 判别力评估见 OBS-2。

### 2. 坐标真实性（26 锚抽核）— PASS（命中 26/26，其中 2 锚带发现）

本地仓 21 锚全命中（详见第四节表）；上游 5 锚全命中。任务书点名的窗口全部
亲核：SpectralBuildEngine :431-474（窗口段 + tc 循环精确）/ :211 printCC
（nil=solve / 非 nil 钉死注释逐字对应）/ :558-572 illumPrintFor（dichroic
谱乘）/ FilmMaterialStore :109-160 fold 集（确不含三谱键——R1 实锤）/
FilmProfile :148 / GrainModule :50-76 等。带发现的锚：paper_grades.json
（→MAJ-1）、foldProfile 设计注释（→MIN-1）。

### 3. 红线完备 — PASS（豁免判定成立 + 纪律逐条落位）

- **数据自建非 GPL 复制**：PDF 不入仓（原件落 evidence 分仓）/ NOTICE 来源
  表（URL+出版物号+sha256，机检 ≥7 条）/ MANIFEST 逐文件 sha256 对账 /
  双源独立转录 + 上游只读第三源对照 / 「禁复制 SpektraLab 数组」grep 机检
  ——逐条落位 ✓。
- **双 .metal 零 diff**：结构性成立（OBS-5）+ 机检在 T3 验收 ✓。
- **sidecar v12 触封存面**：豁免成立（OBS-1 专项裁定——封存面登记以来首例
  bump，文件自带章程 + persisted-face 先例链 + plan 显式例外申报三重依据）。
- **bake 键负测组 = 收口门**：T3 负测 ①-⑧ 枚举完整（三槽 miss / tc HIT 分槽
  断言 / absent 逐字节恒等 / fold 对齐恒等 + 谱变 miss / 零漂移 / 18% 灰
  factor 归一 / 方向断言 / 因子交叉外部锚），「缺任一 = 收口门拒绝」在
  CONTEXT 红线 3 + plan red_lines + T3 验收三处复述 ✓。
- **process 零 bump**：RenderProcess :90 current=2 亲核 + 零 diff 机检 ✓；
  v3 让位 M9-4 的编号协调与 ROADMAP 一致 ✓。

### 4. 可执行性 — PASS（一处文字缺漏 MIN-3）

- T 序依赖合理（T2 消费 T1 资产、T3 主门独立于 T2 键族但 absent 恒等语义
  T2 先钉位、T4 独立、T5 收口）。
- ΔN 构成自洽：下限 3+5+4+2+1=15 / 上限 4+6+5+3+2=20 = 带 +15..20 =
  charter M 档 15-20N 精确命中；越带申报机制在 frontmatter + T5 双落。
- 带式对账锚诚实（4287/39/0 ⊕ ΔN_R6 在飞 ⊕ ΔN_M9-1 待执行 + 开工前亲核
  义务；OBS-4 确认基线取值正确；m9-1-aimask 目录已存在，亲核义务设计覆盖
  动态）。
- 数字化工作流可复现（工具自检「PDF 本地存在时输出逐字节一致」+ evidence
  落盘）；依赖形态细节 OBS-6。
- 量级 vs 任务面：charter 站 2 工期档 2-3 周，plan 风险 R9 如实登记数据面
  ~4-5 人机协作日 + 栅格卷长杆 + 回退条款——工期量级诚实。

### 5. OQ 采纳 — PASS

- D-M92-1..8 与 RESEARCH §6 OQ-M92-1..8 推荐逐条一致（8/8）；X-M92-1..6
  设计钉死与 research §1/§4 方案骨架对应。
- OQ 编号勘误验证通过（OBS-3）：产物面零残留错位；charter 级 OQ-M9-8 与
  站级 OQ-M92-x 双轨引用全部语义正确。

### 6. 量级诚实与测试落域 — PASS（两处落域备注 MIN-2 / 先例确认）

- 测试落域与 M8 批近例核对：PaperGradeTableTests/CameraFilterTests（Core
  谱面族纯函数）落 **IOP** 与 M8 近例一致（SpectralProfileDecodeTests/
  SpectralTcFitTests/SpectralSolveTests 全 = IOP，BUNDLE-MAP :866-878 亲核）
  ——plan 落点有先例支撑 ✓；BWSpectralGoldenTests/FilterBakeKeyTests 落
  IOPP = *Golden*/*Bake* 域惯例 ✓；GrainCalibrationTests 落 IOP = GrainTests
  同域 ✓；FilmPanelBWTests 落 APP = FilmPanelSpectralUITests 先例 ✓。唯
  SidecarV12Tests 落 Layers 与 V10/V11 双连 LIB 近例不一致（MIN-2）。
- BUNDLE-MAP 增行 + tuist 末位（L041/E2）在 T5 收口；逐批纪律文字缺漏见
  MIN-3。

---

## 四、抽核锚点登记（26 锚）

| # | 锚 | 结果 |
|---|---|---|
| 1 | SpectralBuildEngine.swift :354 build 入口 | ✓ |
| 2 | :374-381 filmSens = 10^logSensitivity | ✓ |
| 3 | :431-451 sensW 窗口段（erf4 + per-channel 归一） | ✓ |
| 4 | :453-474 tc 展开循环（acc += spectrum·sensW） | ✓ |
| 5 | :201-211 Parameters.printCC（nil=solve/非 nil 钉死） | ✓ |
| 6 | :558-572 illumPrintFor（dichroicTransmissions 谱乘） | ✓ |
| 7 | :402-414 refSPD/viewingIlluminant（factor 公式输入在位） | ✓ |
| 8 | FilmMaterialStore.swift :42 init 单目录 | ✓ |
| 9 | :106-151 materialPairHash fold 集（确不含三谱键） | ✓（→MIN-1 关联） |
| 10 | FilmProfile.swift :148 channelModel + :225-233 六谱键 | ✓ |
| 11 | GrainModule.swift :50-76 dt 三滑杆无 per-film | ✓ |
| 12 | FilmRecord.swift :51-90 七字段 + :123-132 stableHash + :141 isFilmRecordDefault | ✓（→MIN-5/MIN-6 关联） |
| 13 | LightamerSidecar.swift :247-255 v11 + bump 注释链 | ✓ |
| 14 | RenderProcess.swift :85-92 current=2 | ✓ |
| 15 | FilmTailPolicy.swift :104-108 policyTag switch + :122-158 seed 四项序 | ✓ |
| 16 | FilmPrintBake.swift :345-432 SpectralPrintBake 三槽（tc6/print8/scan8，键=pairHash） | ✓ |
| 17 | FilmPanelModel.swift :85-110 双 picker + :80-83 isPristine 手写 | ✓（→MIN-5） |
| 18 | Resources/FilmProfiles/ 28 卷 + 四件文书 | ✓ |
| 19 | BUNDLE-MAP 域先例（M8 谱面→IOP / V10/V11→LIB / Golden→IOPP） | ✓（→MIN-2） |
| 20 | M8 CONTEXT X7 + M8-2-PLAN 缓存键形态（键形不变+折键「非 legacy 才折」+exposureEv 不入键） | ✓ |
| 21 | M7-6-01-SUMMARY :47 封存面 17 件原文 + GOAL-STATE 4287/39/0 | ✓（→MIN-4/OBS-4） |
| 22 | [上游] hanatos.cpp :165-196 乘法数学（绿通道 factor / t÷factor 乘入） | ✓ 逐字一致 |
| 23 | [上游] paper_grades.json 7 档 {00,0,1,2,3,4,5} | ✓（→MAJ-1） |
| 24 | [上游] Tri-X dump（三通道同值 ×81 / channel_density 全 1/3 / metadata tags SHEET+ASSUMED） | ✓ |
| 25 | [上游] bw_checks.py（五色块 chart + tone-path-only 隔离） | ✓ |
| 26 | [上游] params.cpp PRINT 域 wire（m/y_filter_neutral ∈ [0,200]；无 grade Int 先例） | ✓（佐证 MAJ-1） |

## 五、修复要求汇总（执行前动作）

1. **[MAJ-1] 补 paperGrade 档位编码裁决**——T2 开工前落 CONTEXT D-M92-4 附注
   或 DECISIONS（建议 `String?` verbatim "00".."5"，与上游表 key 直映，nil
   语义已定；`Int? ∈ {-1..5}` 亦可但需注释 -1≡"00"）。一行裁决，其余零改。
2. **[MIN-1..6] 随对应任务 DECISIONS 顺带落**——无一项需要重开 plan 结构；
   MIN-3（逐批 Project.swift 步骤）与 MIN-5（isPristine 面点名）建议在
   plan 文本各补一句，防机械执行者漏。

—— 评审员：zcode 独立评审 subagent，2026-10-27；零 commit / 零构建。
