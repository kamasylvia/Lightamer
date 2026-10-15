---
phase: M6-6
slug: feature-parity
status: validated
nyquist_compliant: true
created: 2026-10-16
validated: 2026-10-16
signed: 2026-10-16
milestone_closeout: M6
---

# Phase M6-6 — Validation（FEATURE-MAP ID 化 + CI 对账门 + 首轮对账；**兼 Milestone 6 收口正本**，`milestone_closeout: M6`）

> 体例对齐 `phases/m5-3-pano/M5-3-VALIDATION.md`（M2-11/M4-3/M5-3 单文
> 档收口先例）。**状态 = validated**（2026-10-16 签核批落签；夜间全自
> 动授权在案〔先例 D-07-3-T5-1〕，**晨审可推翻**）——C 档第 3 停已过：
> 双重验收按制度编排（zcode 独立验收 → 串行 omp 二验；omp 制度路配额
> 阻塞时双 zcode 独立眼替代先例）；**本件 ACCEPTANCE 结论节为脚手架
> 占位，结论由验收波回填**；签核 = 验收双 PASS 后由收口批落签，晨审
> 可推翻。
> **SC 数字对账基线 = 全套 `--all` 批准轮 `TOTAL|3848/24/0|` exit 0**（
> 本批实测，transcript = `all-run-m66-01.log`；对账基线 = M6-5 三路实测
> 3848，ΔN = 0 精确——本批零 Swift 测试面）。

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | XCTest（unit / golden / parity / 直启宿主 / 环境门探针——本批零新增测试面，ΔN = 0） |
| **Quick run** | `Scripts/test-direct.sh`（`--bundle`/`--all`；MEMFAIL / ru_maxrss 8G 机检兜底） |
| **Full suite（phase 终轮）** | 全套 `--all` 批准轮 = **`TOTAL|3848/24/0|` exit 0**（2026-10-16 本批实测，`caffeinate -dis`；0 MEMFAIL、七 bundle 全 8G 门内、零 crash；原始日志 = phase 根 `all-run-m66-01.log`） |
| **对账链** | 3848（M6-5 三路实测）+ 0（本批零 Swift 面）= **3848 精确，ΔN = 0**；build-for-testing 前置硬性兑现（I-1 教训——首轮 appex 签名债处置后 `TEST BUILD SUCCEEDED`，事件台账 = `M6-6-01-DECISIONS.md` §3.1） |
| **zh 对账** | N-1 rider 三键尾块纯插入（51+/0-）——`zh-audit --check` PASS 前后恒定，catalog keys **1926→1929**，断言 5 interp 键集 30→30（三新键经 `INTERP_PREFIX_RE` 动态族覆盖） |
| **在 flake/环境事件** | build-for-testing 首轮 appex 签名债一条（环境域处置，DECISIONS §3.1）；全套轮零事件 |

## 一、Charter 验收形态对账（M6-6 phase SC 三列）

> charter 验收形态 =「ID 清单 + CI 门落地跑绿 ✓ + M6 SC 三列对账 ✓」。

| SC 项 | 判据锚 | 实测终态 |
|---|---|---|
| ID 清单落地 | `docs/parity-checklist.md`（repo 树、全英文公开树纪律） | **134 rows / 12 域**（`FEAT-<DOM>-NN` 唯一 mint 点 + 六状态词表 + 双生成块）；row 数 ∈ [100,160] 机检过；id 重复裸 grep 零输出；survey 正本正文零改写（纯插入指针段）——`93a674c8` |
| CI 门落地跑绿 | `Scripts/parity-audit.py` 六断言 + ci.yml `parity` job | `--check` PASS（uv + 裸 python3 双形态 exit 0）；`--self-test` PASS（红 7 族 + 净例 + `--tree-root` 公开树分支例）；ci.yml 纯追加 11 行 job（ruby yaml 实载 OK）——`a515b3ff` |
| 首轮对账 gaps | `--write` 填充 + gaps ≥ 10 一次性 AC | gaps 块 **17 行**（3 Missing / 3 V2 / 1 Parked / 3 OOS / 7 Partial，D5 序）；A6 新鲜度转绿——`3c7498bc` |
| N-1 rider（挂账②提前清偿） | 三键 `%lld` 变体尾块纯插入 | 51+/0- 单 hunk；PASS 恒定 + 1926→1929 + grep 恰 3——`d63cf79c`（SC6） |
| M6 milestone 终值实测 | 全套 `--all` 批准轮 | **`TOTAL|3848/24/0|`** exit 0，ΔN = 0（SC5） |
| 五正本翻账 + AGENTS 节 | ROADMAP / REQUIREMENTS / STATE / TODO / GOAL-STATE + AGENTS | 收口批落（T5，本批 commit 链） |

## 二、Mile­stone 6 六 phase 终态汇编

| Phase | 裁决 | 终态（全套 `--all` 实测） | 正本 |
|---|---|---|---|
| M6-0 | 立项与站规格 | closed 2026-10-16（charter 五正本落账） | ROADMAP §Milestone 6 |
| M6-1 | ①MCP-09-A | closed 2026-10-14；**`TOTAL\|3689/24/0\|` 2157s**（对账链 3631+53+4+1） | `phases/m6-1-interop/M6-1-VALIDATION.md` |
| M6-2 | ③process version | closed 2026-10-14；**`TOTAL\|3725/24/0\|` 2113s**（3689+36） | `phases/m6-2-process-version/M6-2-VALIDATION.md` |
| M6-3 | ②ALCE-03 | closed 2026-10-14；**`TOTAL\|3759/24/0\|`** 两路 2106s/2130s（3725+34） | `phases/m6-3-ultrahdr/M6-3-VALIDATION.md` |
| M6-4 | ⑤stacks + ④AI 分割 spike | closed 2026-10-16；实测 **3841/24/0**（01 双路 3815 + 02 双路 3841）→ 修批后推算 3843 → **由 M6-5 实测 3848 核销**（3841+2+5） | `phases/m6-4-gallery-stacks/M6-4-VALIDATION.md` |
| M6-5 | M5 挂账清算批 | closed 2026-10-16；**`TOTAL\|3848/24/0\|`** 三路独立亲跑同值 2099s/2087s/2096s | `phases/m6-5-ledger-clearing/M6-5-VALIDATION.md` |
| M6-6（本批） | ⑥FEATURE-MAP + CI 门 | **`TOTAL\|3848/24/0\|`** exit 0（ΔN = 0，本批实测） | 本件 + `M6-6-01-{SUMMARY,DECISIONS}.md` |

数字链：3689 → 3725 → 3759 → 3841（实测）/3843（推算，核销）→ **3848 → 3848**（本批，ΔN = 0）。

## 三、六裁决兑现表（charter ①..⑥）

| # | 裁决（LIGHTCRAFT-NOTES §六，用户回批 2026-10-11） | 兑现 phase | 终态 |
|---|---|---|---|
| ① | MCP-09-A 项目级单写者锁 + `--connect` 转发 | M6-1 | Delivered（`SingleWriterLock` 五态泛化 + connect 指引 + GUI 只读面；三段验收链 PASS） |
| ② | ALCE-03 UltraHDR 解冻 | M6-3 | Delivered（CI `.hdrImage` 全服务路 + ISO 21496-1 容器 + 六门 validate；六格式矩阵零改动红线维持） |
| ③ | per-photo process version | M6-2 | Delivered（sidecar v10 `process` additive + 出生点盖章 + 冻结 golden 四门） |
| ④ | AI 分割蒙版原生 spike | M6-4-02 | 达标即收（三原生件落地 + Describe 原生不可达收口 → SAM CoreML V2，裁决⑦） |
| ⑤ | 图库 stacks + auto-stack | M6-4-01 | Delivered（schema v5 两新表 + auto-stack 全套语义 + 分页×堆叠） |
| ⑥ | FEATURE-MAP ID 化 + CI 对账门 | **M6-6（本批）** | Delivered（134-row checklist + 六断言 CI 门 + 首轮对账；charter 验收形态三列全 ✓） |

## 四、编排偏差登记（收口段正式落位）

1. **裁决⑥「第一个 plan」偏差（晨审/用户可随时追认或推翻）**：裁决⑥
   原文 = FEATURE-MAP 升维「作为 M6 对标里程碑的第一个 plan」（ROADMAP
   M6-6 行在案）。实际编排 = M6 互操作四件（M6-1..M6-4）先行、M6-5 清算
   批接续、本批殿后收口——**互操作先行编排**取代「第一个 plan」原文。
   依据 = FEATURE-MAP 无依赖任何 M6 件、四裁决件依赖链单向（ROADMAP
   依赖列），编排自由度在 charter 内；ROADMAP M6-6 行已注记「flippable
   at morning review」。本段为收口正式登记位。
2. **N-1 rider 提前清偿偏差（评审 F3 登记，晨审可翻）**：M6-5 VALIDATION
   :124 项级原文 =「N-1 McpLauncherPanelView 三处插值裸键 → **下一清算
   批候选**」（未点名 M6-6；:270 汇总句「移交 M6-6 收口批、GUI 批与晨
   审」为六项汇总口径）——本批先行清偿属**提前处置**（非逐字移交兑
   现）：S 量级零风险 + milestone 收口前清掉一枚已知 zh 活体缺陷
   （CONTEXT D7② 理由）。挂账表引 :124 原文并显式登记本偏差。
3. **omp 制度路双验替代先例沿用**：M6-2..M6-5 各批 omp 配额阻塞时以双
   zcode 独立眼替代（在案先例）；本批验收波编排注记同款（见 ACCEPTANCE
   占位节），晨审可裁。

## 五、铭谢与边界（D9）

**铭谢**：量化对标方法论（gaps 排名 + parity-checklist 逐条 ID + 生成
块 + CI 门）借自 **LightCraft**（`storytold/lightcraft`，MIT OR
Apache-2.0）。本批**零代码移植**（方法论/形态借鉴 + `parity.rs` 行为
语义对照）——**无 NOTICE 义务**（成段代码移植才触发，charter 边界在
案）；铭谢注记落本节与 `docs/parity-checklist.md` 头注（公开树可见的
致谢，与 `third_party_licenses/` 既有纪律同向）。

**边界（M6 未做面显式汇编——防「milestone closed = 全做完」误读）**：

1. Manual-Only 19 行 GUI 走查（M6-5 挂账④）→ 下一 GUI 批；配方 =
   `.work/gui-acceptance/m6-5/MANIFEST.md` + m6-4 MANIFEST 前置供件。
2. V17 zh-audit 门扩展候选（Text 族 + `String(` 跨行族）→ 机检硬化批
   （M6-5 挂账③移交；本批 parity 门是新门非 zh-audit 扩展）。
3. V2 九项（V2-PROPOSAL §七，登记 ≠ 立项）+ 留置五项 → V2/Maintenance
   站（未立项态）。
4. charter 裁决挂账：smart albums（次之）/ 挑片视图 / watched folders
   （裁决⑤不立项部分）/ SAM CoreML（裁决⑦ V2）/ ALCE-02 EXR（V2 原
   位；本批 checklist EXP-02 行锚 = ALCE-02 + OQ-V2-5）。
5. 编排偏差登记（§四.1）——晨审/用户可随时追认或推翻。
6. 瘦身手术第二次触发（主会话专属，GOAL-STATE 队列行原序保留——M6
   closed 后触发确认态）。

## 六、挂账单一清单（M6 milestone 级移交正本 = CONTEXT §4 六项）

上节边界 1-6 即移交清单（单一正本 = `M6-6-CONTEXT.md` §4；五正本翻账
时引用）。六裁决件全兑现、M6-5 挂账六项全处置（①⑥本批前已落 / ②本
批提前清偿〔偏差登记 §四.2〕/ ③⑤移交注记 / ④GUI 批移交）。

## 七、授权记录

- 夜间全自动授权链（先例 D-07-3-T5-1——用户显式「开跑，不要停」续指
  令 = 规划与执行授权；M2-8..M6-5 各 VALIDATION 同款沿用）。
- 全套 `--all` 批准 = orchestrator 夜间授权链内 pre-approved（本批唯一
  测试轮；8G 门 + MEMFAIL 机检 + 异常停手上报全程适用，实测零异常）。
- C 档第 3 停 = phase 签核前停——本批以收口批落签形态行使（夜间授权
  先例），**晨审可推翻**；验收双 PASS 回填 ACCEPTANCE 后签核生效。

## 八、ACCEPTANCE 结论（脚手架占位，验收波回填）

> 双重验收制度（config `dual_acceptance = true`）：zcode 独立验收 →
> 串行 omp 二验（omp 配额阻塞时双 zcode 独立眼替代，偏差登记 §四.3）。
> 结论行由验收波回填；本节仅为占位脚手架。

- [x] 第一路（zcode 独立验收）：**PASS**（SC1-SC6 全数独立复跑过，含独立全套亲跑
  `TOTAL|3848/24/0|2381s` exit 0 ΔN=0）——附 **2 项必修内容更正**（checklist
  FEAT-LIB-04 / FEAT-LIB-13 状态误判 Missing，账面 REQUIREMENTS M2LIB-05/:26 与
  M2LIB-02/:23 明文 Delivered + 活代码在树；详见正本
  `M6-6-01-ACCEPTANCE.md` §七 E-1/E-2）+ 2 minor + 2 nit；修法 = docs-only
  翻行 + `--write` 复跑（gaps 降至 16-17 行仍 ≥10，一次性 AC 不回退）。
  证据正本 = `M6-6-01-ACCEPTANCE.md` + 验收独立 transcript
  `evidence/acc1/acc1-all-run.log`（local-only）。—— 已回填（2026-10-16 验收波）
- [x] 第二路（omp 制度位由第二 zcode 独立眼替代，偏差登记 §四.3 同款）：**PASS**（SC1-SC6 全数独立复跑过，含**独立全套亲跑**
  `TOTAL|3848/24/0|2104s` exit 0 ΔN=0——build-for-testing 前置亲跑，段和
  686+460+494+729+284+379+816 = 3848 / skip 1+3+4+4+4+4+4 = 24 机核精确，
  0 MEMFAIL，七 bundle 峰值 6575/5591/1175/616/1211/4983/2832 MB 全 8G 门
  内，逐 bundle 值与执行方/第一路逐行同值）——**checklist 134 行全量终审**
  （非抽样；本路核心职责）另报 **3 项 error 级内容更正候选 + 2 minor**（
  FEAT-EXP-13 Partial 误判应 Delivered〔M2 页 + legacy 双 UI picker + 编码
  器三档实装 + v1 EXP-01 账面 Delivered 含「压缩选项」〕/ FEAT-SHELL-03
  Partial 违反账面优先序应 Delivered〔M2UIW-01 明文 tokens Delivered +
  M2-3-1-ACCEPTANCE AC1 + ThemeTokens.swift 七族自证〕/ Nikon HE 恢复行缺
  席〔plan T1 明文要求该 OOS 锚，survey :49 在列，grep 零命中〕+ PNG 压缩
  等级选项无行〔Alcedo 0-9 UI，我方无 UI 亦无行，与 EXP-13 行粒度不对称〕
  / 微修批后 STATE/SUMMARY 计数残留 117/17 未同步 119/15）；均 docs-only、
  不翻任何 SC、gaps 15 行在任何建议修后仍 ≥10。正本 =
  `M6-6-01-ACCEPTANCE-2ND.md` + 验收独立 transcript
  `evidence/acc2/acc2-all-run.log`（local-only）。—— 已回填（2026-10-16 第二
  路验收波）
- [x] `ACCEPTANCE` 正本文件：第一路 = `M6-6-01-ACCEPTANCE.md`；第二路 =
  `M6-6-01-ACCEPTANCE-2ND.md`（双路正本随本收敛批 commit 入库——4e61977b
  先例的「留工作树待收敛」到此兑现）
- [x] **分歧两处终裁（双路对表后落定，晨审可翻）**：
  - **分歧 1（LIB-13 修法）—— 追认落地版 Delivered**：第一路建议保守侧
    Partial，微修批 `4e61977b` 落地 Delivered；第二路独立判定 Delivered
    正确（判定序第一条即命中 REQUIREMENTS M2LIB-02/:23 + M2LIB-05/:26 双
    Delivered 锚 + META-06 Phase 12 三保险；Partial 反与 checklist 自申
    判定序相悖）——**追认落地版**，行 note 保留「LightCraft 语义增强未
    立项 = 独立候选」nuance。
  - **分歧 2（SHELL-03 处置）—— 判 E 级、采纳修正**：第一路宽免为「在册
    争议可翻不算违规」；第二路判违反判定序且争议前提不实（M2UIW-01 明文
    tokens Delivered + `M2-3-1-ACCEPTANCE.md` AC1 机检 + ThemeTokens.swift
    七族自证三方一致，DECISIONS §2 前提句被证伪）——**采纳 E 级更正**，
    翻 Delivered。
- [x] **四项内容更正全部落地（终收敛批 `0174a1b6`，docs-only 零 Swift、
  零复测全套）**：E-3 EXP-13 → Delivered / E-4 SHELL-03 → Delivered /
  E-5 mint FEAT-DEV-09（Nikon HE 恢复，OOS，STACK.md 锚）/ M-3 mint
  FEAT-EXP-15（PNG compression-level，Missing）+ M-4 计数同步（STATE
  现状位 + SUMMARY SC3）；`--write` 后实测终值 = **136 rows / Delivered
  121 / Partial 5 / Missing 2 / V2 3 / Parked 1 / OOS 4 / gaps 15 行**
  （2+3+1+4+5，仍 ≥10 一次性 AC 不回退）；`--check` + `--self-test` 终跑
  全绿。带日期历史行零改写（T3 时点值以注记保留，链锚引文不动）。
- [x] **两编排偏差追认落定（双路独立追认一致）**：§四.1 互操作先行编排
  （双路同判实质更优——checklist 判定序以账面为准，FEATURE-MAP 若按原文
  先行，首轮 gaps 必然大面积失真、收口前须整体重审）+ §四.2 N-1 提前
  清偿（:124 项级 / :270 汇总两层原文亲读无误，S 量级零风险、收口前清
  一枚已知 zh 活体）——**追认成立**；登记通道（ROADMAP pre-flip 注记 +
  §四 + M6 closed 块 flippable 注记）维持，晨审/用户可随时推翻。

## 签核

- charter 验收形态「ID 清单 + CI 门落地跑绿 ✓ + M6 SC 三列对账 ✓」全项
  兑现（§一 七行对账表）；SC1-SC6 全 PASS（`M6-6-01-SUMMARY.md` 对表）；
  终值全套实测 `TOTAL|3848/24/0|` exit 0（ΔN = 0 精确）。
- `status: validated` + `nyquist_compliant: true` + `milestone_closeout: M6`。
- **M6（互操作与图库强化）milestone closed**：M6-0..M6-6 七 phase 全闭
  环；六裁决件全兑现（§三）；M6 milestone 挂账单一清单六项移交（§六）。
- 双重验收双 PASS 已回填（§八）：第一路 `M6-6-01-ACCEPTANCE.md`（2 error
  修正式）+ 第二路 `M6-6-01-ACCEPTANCE-2ND.md`（全量终审 4 项发现）；四项
  内容更正随终收敛批 `0174a1b6` 落地、三门终跑全绿（136 rows / gaps 15）；
  分歧两处终裁 + 两编排偏差追认落定（§八）。
- **签核：signed 2026-10-16（M6-6 终收敛批落签）**——夜间全自动授权链在案
  （先例 `D-07-3-T5-1`：用户显式「开跑，不要停」续指令 = 规划与执行授权；
  M2-8..M6-5 各 VALIDATION 同款沿用），C 档第 3 停以本签核行使；
  **晨审可推翻**（推翻窗内任何判定被翻 → 按 checklist 判定序 + 本件 §八
  终裁注记重开对应面，SC5 零 Swift 面不需复测全套）。
