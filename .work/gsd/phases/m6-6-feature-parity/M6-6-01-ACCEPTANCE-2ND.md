---
phase: m6-6
plan: "M6-6-01"
kind: plan-acceptance（双重验收第二路，zcode 独立眼替代 omp 制度位——配额阻塞替代先例，偏差登记 VALIDATION §四.3）
created: 2026-10-16
lane: 2（第二独立眼，零共享上下文；基线 = 微修批 `4e61977b` 在 HEAD，执行链 `93a674c8..c51fd92d` + `4e61977b`）
verdict: "PASS / 0 blocking + 3 error-grade 内容更正候选（docs-only，含 1 覆盖缺口）+ 2 minor + 3 nit"
---

# M6-6-01 ACCEPTANCE — 第二路独立验收（FEATURE-MAP parity 门 + M6 milestone 收口）

> **结论头：PASS / 0 blocking + 3 error-grade 内容更正候选（docs-only）+ 2 minor + 3 nit。**
> 六条 SC 全数独立复跑通过（含**独立全套亲跑** `TOTAL|3848/24/0|2104s` exit 0，
> build-for-testing 前置亲跑，ΔN=0 亲证）；本路核心职责 = **checklist 134 行
> 全量逐行终审**（第一路 24 行抽样抓 2 误判，本路全量再抓 2 误判 + 1 覆盖缺
> 口 + 1 小覆盖缺口）——微修批两行翻正锚点代码级亲证成立；门脚本红绿真实
> 性以独立回归实验亲证（亲手重引入解析器缺陷 → self-test 与真件 `--check`
> 双翻红）；六裁决兑现表 / 对账链 3689→3848 / 编排偏差两处 / 挂账移交清单
> 独立对表全闭合。全部发现 docs-only，**不翻任何 SC、不需复测全套**。

## 一、SC1-SC6 逐条独立复跑（全部亲跑，非转录）

| SC | 判据 | 本路独立实测 | 结论 |
|---|---|---|---|
| SC1 | `uv run python3 Scripts/parity-audit.py --check` exit 0 | uv 形态 rc=0 + 裸 python3 形态 rc=0 双亲跑，输出 `PASS (134 rows, id-unique, vocab clean, evidence paths verified)` | ✅ |
| SC2 | `--self-test` PASS（红绿 golden + 公开树分支） | rc=0，红 7 族全检出 + 净例 + placeholder 容忍 + `--write` 愈合 + `--tree-root` 公开树分支显式注记亲验；**红绿真实性独立回归实验**：`/tmp` 副本删除 `if in_block: continue` 两行重引入 DECISIONS §3.2 解析器缺陷 → `--self-test` 翻红（`C --write heals` 失败）+ 同缺陷态真 checklist `--check --tree-root <repo>` 翻红 rc=1——产线修复承 bacterial 亲证 | ✅ |
| SC3 | gaps 块行数 ≥ 10 | awk 独立计数 = **15**（1 Missing + 3 V2 + 1 Parked + 3 OOS + 7 Partial，微修批后现值）；行序 = D5 状态严重度 + 域码字母序亲核（V2 段 AI<EXP<MASK、OOS 段 DEV<DEV<SHELL、Partial 段 ADJ<DEV<EXP<LIB<OWN<SHELL<SHELL） | ✅ |
| SC4 | ci.yml 含 parity job + 裸 python3 本地 PASS | `git diff a515b3ff^..HEAD -- ci.yml` = 纯追加 11 行（build-and-test/release 零触）；`ruby -ryaml` 实载 OK（jobs = build-and-test,release,parity；ubuntu-latest / timeout 5 / checkout@v5 + 裸 python3 --check） | ✅ |
| SC5 | 全套 `--all` `TOTAL\|3848/24/0\|`（ΔN=0） | **本路独立亲跑**：`caffeinate -dis xcodebuild build-for-testing`（`TEST BUILD SUCCEEDED`，本轮无 appex 签名债复发）→ `caffeinate -dis Scripts/test-direct.sh --all` → **`TOTAL\|3848/24/0\|2104s` exit 0**；段和机核 686+460+494+729+284+379+816 = 3848、skip 1+3+4+4+4+4+4 = 24 精确；**零 MEMFAIL**；七 bundle 峰值 6575/5591/1175/616/1211/4983/2832 MB 全 8G 门内（贴线族 IOP 6575 / IOPParity 5591 vs M6-5 参照 7560/7242 带内）；逐 bundle executed/skipped/failed 与执行方、第一路**逐行同值**。transcript = `evidence/acc2/acc2-all-run.log`（local-only） | ✅ |
| SC6 | xcstrings = 恰 N-1 三键尾块纯插入 | `git diff d63cf79c^..HEAD -- Resources/Localizable.xcstrings` = 51 内容加行 / 0 删行 / 单 hunk（diff 头 4 行剔除后机核）；三 `%lld` 变体键各恰 1 命中；**python json 亲比** en/zh 值与裸键逐字节同文（三键 × 双语言 six/six same）；catalog keys 独立 json 计数 = **1929**；`zh-audit --check` PASS（1682 source / 1929 catalog / 30 interp all variant-PRESENT）；调用点 `McpLauncherPanelView.swift` 零 diff | ✅ |

## 二、checklist 134 行全量独立终审（本路核心职责）

- **结构机检独立复核**：手维护行 134（生成块内行排除后 awk 计数）；12 域
  节标题在位；域行数 SHELL 6 / LIB 16 / EDT 15 / ADJ 19 / DEV 8 / GEO 3 /
  NODE 8 / MASK 12 / DRT 10 / EXP 14 / AI 11 / OWN 12（DECISIONS §1 同表）；
  summary 矩阵 119/7/1/3/1/3 与行集独立重算一致；全英文（`rg
  '[\x{4e00}-\x{9FFF}]'` 零命中）+ U+00B7 / em-dash 零命中（M-2 修正确认）+
  绝对路径 / 用户名零命中；`.work/` 泄露 = 仅 59 处 `doc:` 路径字符串（头注
  知情申报形态，无内容泄露）。
- **全量逐行状态判定**（判定序 = REQUIREMENTS Delivered 标记 → STATE →
  phase VALIDATION → AGENTS 增量节，账面正本逐域亲读：M2LIB/UIW/NODE/GRADE/
  DRT/MASK/VER/EXP/AI 全族 + IOP/LAYER/AI/YIYIN/META/PRES/EXP/SYS v1 族 +
  M6 五 VALIDATION TOTAL 亲读）：**131 行判定成立**（含 24 行态内的全部
  V2/Parked/OOS 语义合规行——EXR=V2 不入 OOS 兑现 F2；Parked 唯一行
  MASK-12 重启条件锚 REQUIREMENTS :366 亲证）；**2 行误判 + 2 覆盖缺口**
  见 §三 E-3/E-4/E-5/M-3。
- **微修批 `4e61977b` 两行翻正锚点代码级亲证（本路独立复核，不轻信）**：
  - **E-1（LIB-04 Activity view → Delivered）成立**：`LibraryInspectorView
    .swift:161`（activitySection）/:195（`toggleActivityDay` 点击腿）+
    `LibraryQueries.swift:545`（activitySeries）/:578（dayFilter UTC 整日投
    影）+ REQUIREMENTS :26 M2LIB-05 Delivered 明文含 Activity view——原
    Missing 判定违反账面优先序，翻正正确。
  - **E-2（LIB-13 Smart albums → Delivered）成立，且对第一路建议修法有分
    歧**：第一路建议翻 **Partial**；实际落地 **Delivered**。本路独立判定 =
    **Delivered 正确**——判定序第一条（REQUIREMENTS Delivered 优先）即命
    中双锚：M2LIB-02/:23（智能相册 Filter JSON 谓词 **Delivered**）+
    M2LIB-05/:26（SMART ALBUMS evaluate(.library) 成员闭环 + 相册谓词折叠
    **Delivered**）+ META-06（Phase 12 智能相册 Delivered）；代码三锚亲证
    （`WorkspaceHostView.swift:559` 项目工作区装配 `SmartAlbumStore()` /
    `smartAlbumsSection` :378 / store CRUD+evaluate :147/:167/:202/:288）。
    第一路的 Partial 保守 instincts 与 checklist 自申判定序不符；落地版
    note 保留「LightCraft 语义增强未立项 = 独立候选」的 nuance，语义分层
    干净。**追认落地版。**
- **survey 覆盖对表（孤儿扫描）**：§1-§8 逐节对表 + §2.6 并 DRT（DRT-09 +
  ADJ-13..16）+ §9 dt-gap 不入行（OWN-12/ADJ-19 承载）+ §10 缺失清单十项
  逐条有行 + 上游增量五条处置登记（DEV-08/EDT-13 note/不 mint 三件/LIB-09）
  + Target 0.3.2 与 survey 增补节一致——**孤儿两处**（E-5 Nikon HE 行缺席 /
  M-3 PNG 压缩等级无行），其余零命中。

## 三、独立发现（本路自有，按严重度）

### E-3【error·内容更正候选】FEAT-EXP-13（TIFF compression options）= Partial 误判，应 Delivered
- **事实（三层证据亲证）**：①编码器实装三档——`ImageIOEncoders.swift:237`
  （`guard case .tiff(_, let compression)`）+ :246-252（`.none/.lzw/.zip` →
  TIFF 压缩值 1/5/8 写入 destination）；②**M2 导出页 UI picker 在位且活装
  配**——`ExportInspectorView.swift:582-590`（none/lzw/zip Picker，AX
  `export.page.tiff_compression`）+ `:829` 模型字段（默认 `.none`）+ `:957`
  装配进 format spec + `InspectorView.swift:121`（`exportPageActive` 活分
  支挂载）；③legacy sheet 同款 picker（`ExportPanelView.swift:628-635`）。
- **账面**：v1 EXP-01（REQUIREMENTS :299）**Delivered** 明文含「TIFF（含
  8/16/32-bit float、**压缩选项**）」+ golden「PNG/TIFF 8|16 **全压缩变体**
  逐位」——判定序第一条即命中。
- **违规点**：行 note「an explicit compression picker is not exposed
  (encoder defaults)」**双向不实**（UI 已暴露 + 编码器非默认值在跑）；
  DECISIONS §2「显式 NONE/LZW/ZIP picker 无账面记录」与「编码器默认值在
  跑」两句均被代码证伪。第一路 Partial 抽验放行该行 = 抽样盲区。
- **修法（docs-only）**：EXP-13 → **Delivered**（evidence 加
  `src:…ExportInspectorView.swift` 即可，现 src 已指 ImageIOEncoders）；
  summary Delivered 119→120 / Partial 7→6；gaps 15→14。

### E-4【error·内容更正候选】FEAT-SHELL-03（Dark theme token family）= Partial 违反账面优先序，应 Delivered
- **账面**：REQUIREMENTS :31 **M2UIW-01 Delivered 明文点名「暗色玻璃主题
  tokens」**（「路由+顶栏+tokens = M2-3-1」）+ `M2-3-1-ACCEPTANCE.md` :35
  AC1 = 「ThemeTokens 七族在册 + 亮暗序 + 新壳裸 hex 仅 tokens 命中 ✅」
  （机检在案）——判定序第一条即命中。
- **代码自证**：`ThemeTokens.swift` 自述 = "the DARK-GLASS color family of
  the NEW shell, the SINGLE color source"，七 glass family（含 card surface/
  border 语义位）；值刻意自写不抄 Alcedo DESIGN.md（GPL 红线 OQ-1 A **by
  design**）——「非一比一复刻」不是 Partial 依据（parity 行问功能面存在性，
  非像素值拷贝；一比一拷贝反而违反 GPL）。
- **违规点**：DECISIONS §2 前提「M2-3 交付的是 Alcedo 式 IA 骨架**而非其暗
  色玻璃 token 集**」与账面（M2UIW-01 明文 + AC1）及代码自述三方矛盾——
  与 LIB-04/LIB-13 同型（账面 Delivered 被自判推翻）。第一路将其归「在册
  争议可翻不算违规」——本路不同意该宽免：争议台账不豁免判定序，且争议前
  提本身不实。
- **修法（docs-only）**：SHELL-03 → **Delivered**（note 改「self-written
  values per the GPL red line; single color source for the new shell」）；
  summary Delivered 120→121 / Partial 6→5；gaps 14→13。

### E-5【error·覆盖缺口】Nikon HE 恢复无行——plan T1 明文要求的 OOS 锚缺位
- **事实**：plan T1 明文「`OOS` 行带裁决锚（Updates 页 = … / **Nikon HE 恢
  复 = CIRAW 路线** / demosaic 算法菜单 = …）」；survey :49 明文
  `NikonHeRecoveryDialog.qml`（Nikon HE NEF 恢复）为 Alcedo 功能面；CONTEXT
  D2 / TODO M6-6 条 / GOAL-STATE 续接点三处账面均把 Nikon HE 列入 OOS 集；
  checklist `grep -i nikon` **零命中**（本路亲测）。
- **违规点**：三 OOS 行（DEV-05/DEV-06/SHELL-06）之外的第四个 plan 点名面
  无行——「no Alcedo feature surface may be missing from a row」覆盖规则
  违反 + plan T1 AC 局部未兑现（第一路孤儿扫描亦漏）。
- **修法（docs-only）**：mint `FEAT-DEV-09 | Nikon HE (high-efficiency NEF)
  recovery | Alcedo | OOS | doc:.work/gsd/research/STACK.md`（note =
  CIRAW route makes a separate HE-recovery path unreachable/unneeded）；
  rows 134→135 / OOS 3→4 / gaps 14→15。

### M-3【minor·覆盖缺口】PNG compression-level 选项无行（与 EXP-13 行粒度不对称）
- **事实**：survey :194 明文 Alcedo `ExportFormatOptions` 含「PNG
  `compression_level_` 默认 5（**UI 0–9**）」；我方导出 UI 无 PNG 压缩控制
  （ExportInspectorView / encoders grep 零命中亲测）且 checklist 无行——
  TIFF 压缩独立成行（EXP-13）而 PNG 压缩等级缺席，粒度不对称。
- **修法（docs-only）**：mint `FEAT-EXP-15 | PNG compression-level option |
  Alcedo | Missing |`（note = not exposed; encoder defaults）。rows 136 /
  Missing 1→2 / gaps 15（修后口径，仍 ≥10）。

### M-4【minor·文档同步债】微修批后计数残留（§3.1 同批同步半途）
- `4e61977b` 把 checklist 翻到 119/7/1 + gaps 15 并在同 commit message 申
  报「Delivered 117 -> 119, Missing 3 -> 1」，但同批只同步了两处 L081 错引：
  - `.work/gsd/STATE.md:28` M6-6 段仍写「Delivered 117 / Partial 7 /
    Missing 3」（现状描述位，非带日期历史行）；
  - `M6-6-01-SUMMARY.md` SC3 行仍写「17（3 Missing + 3 V2 + 1 Parked +
    3 OOS + 7 Partial）」（T3 时点值 vs 盘上 15）。
  - 本 VALIDATION §一 gaps 行「17 行」= T4 时点事实可保留，但 §八第一路
    backfill「gaps 降至 16-17 行」与实际 15 不符（第一路修法预估，落地版
    全 Delivered 后实为 15）。
- **修法（docs-only）**：STATE/SUMMARY 两处计数同步现值（或加「as of T3/
  T4, superseded by `4e61977b`」注记）；本件 §八回填已按 15 记账。

### N-2【nit·观察】A5 正路径零负载
A5 三个被扫文件中 REQUIREMENTS/ROADMAP 当前 FEAT 引用为零、AGENTS 两处命
中为 regex 字面量（不匹配 token regex）——A5 现状空转绿；self-test 亦无
「账面引用 FEAT id」的正例 fixture（plan SC2 未要求，合规）。机检硬化批
（V17 候选同批）可补 A5 正/负例 fixture。

### N-3【nit·观察】EDT-07 可补 per-op 参数 delta 延期注记
Alcedo 历史行含「操作名+参数 delta+时间」（survey :47）；我方 delta 半边经
D-M2-8-CONTEXT-8-A 裁决 Deferred（M2VER-04 在案）。行文未声称 delta 故非
假陈述；可选加一行 note（Delivered 状态不动，账面优先序维持）。

### N-4【nit·第一路笔误两处】
第一路 ACCEPTANCE 写 survey 指针段「纯插入 7 行」（实测 diff = 6 加行 0 删
行）；「gaps 降至 16-17 行」（落地实为 15）。均 prose 精度问题，不影响其结论。

## 四、六裁决兑现表逐条独立对表（裁决原文 = LIGHTCRAFT-NOTES §六亲读）

| # | 裁决原文（:111-115 亲读） | 兑现 phase | 本路亲验 |
|---|---|---|---|
| ① | MCP-09-A 单写者锁 + 活实例转发 | M6-1 | `M6-1-VALIDATION.md` :24 `TOTAL\|3689/24/0\|2157s` 亲读；OWN-03 行锚可达 |
| ② | ALCE-03 解冻（UltraHDR） | M6-3 | `M6-3-VALIDATION.md` :33/:234 `TOTAL\|3759/24/0\|` 两路 2106s/2130s 亲读；EXP-03 锚可达 |
| ③ | per-photo process version | M6-2 | `M6-2-VALIDATION.md` :26/:220 `TOTAL\|3725/24/0\|2113s` 亲读；NODE-08 锚可达 |
| ④ | AI 分割 spike 达标即收 | M6-4-02 | `M6-4-VALIDATION.md` :34 亲读（spike 五行判定 + Describe 不可达 → SAM V2 裁决⑦）；AI-10/MASK-11 V2 锚可达 |
| ⑤ | stacks + auto-stack 优先（smart albums 次之、挑片/watched folders 挂账） | M6-4-01 | 同上 :34（01 双路 3815）；LIB-11/12 锚可达；LIB-14 Partial / LIB-15 Missing 与「挂账」语义对表一致 |
| ⑥ | FEATURE-MAP 升维 + CI 对账门 | M6-6（本批） | 本路 §一 SC1-SC4 全过 = 直接兑现；「第一个 plan」偏差见 §五 |

## 五、milestone 收口面独立对表

- **对账链 3689→3848 终核**：M6-1 3689/24/0（:24）→ M6-2 3725/24/0（:26）→
  M6-3 3759/24/0 两路（:33/:234）→ M6-4 3841 实测（:34）+ 修批推算 3843 →
  **由 M6-5 实测 3848 核销**（M6-5 :261/:267「3841+2+5 = 3848」亲读）→
  M6-5 3848 三路（:27）→ **本批 3848（本路独立亲跑 2104s，ΔN=0）**——
  VALIDATION §二汇编表逐行与五份 VALIDATION 正本一致，链闭合亲证。
- **编排偏差两处独立追认意见**：
  1. **§四.1 互操作先行编排 —— 追认**。裁决⑥原文「作为 M6 对标里程碑的
     第一个 plan」亲证在案（LIGHTCRAFT-NOTES :115）；取代编排实质更优的论
     证本路独立成立且比第一路表述更强：checklist 判定序第一条就是
     REQUIREMENTS Delivered 标记——若 checklist 先行，五裁决件在盘点时点
     全为未交付态，首轮 gaps 必然大面积失真，收口前须整体重审 134 行；实
     际编排让首轮对账直接站在终态账面上。登记三处在案（ROADMAP :77 pre-flip
     注记 + VALIDATION §四.1 + M6 closed 块），晨审/用户可翻通道完备。
  2. **§四.2 N-1 提前清偿 —— 追认**。M6-5-VALIDATION :124 项级原文
     「→ 下一清算批候选」（未点名 M6-6）与 :270 汇总句（点名收口批）两层
     亲读无误；提前清偿 = S 量级 + milestone 收口前清一枚已知 zh 活体
     （SC6 本路三键同文亲证）；登记引原文 + 偏差标注齐备。
- **挂账单一清单完备性**：VALIDATION §五/§六六项 = CONTEXT §4 六项逐条同
  构（Manual-Only 19 行 GUI 批 / V17 硬化批 / V2 九项+留置五项 / charter
  挂账五件〔smart albums、挑片、watched folders、SAM CoreML、ALCE-02〕/
  编排偏差 / 瘦身手术主会话专属）——移交面无缺项；GOAL-STATE :19 续接点
  收敛（晨审 → 主会话队列）亲读一致。
- **五正本翻账抽核**：REQUIREMENTS :413 M6INT-04 Delivered（锚全）✓ /
  ROADMAP :8 M6 closed 块 + :77 M6-6 行 ✅ ✓ / STATE current phase M6
  closed ✓（计数残留 = M-4）/ TODO :356 M6-6 [x] ✓ / AGENTS :477-484
  M6-6 增量节六条 ✓。带日期历史行零改写（执行链 diff 审计 = 17 文件全在
  申报面内，零 Swift/零 .metal/零 Project.swift 亲证）。

## 六、执行期三事件处置复核

1. **L081 签名债**：LESSONS :843 `## L081` 四段结构在案（L080 = :837 代理
   env 课亲证不同课）；微修批后 SUMMARY :37 与 STATE :28 均已指向 L081
   （M-1 修正确认）。本轮 build-for-testing 亲跑无复发（增量态）。
2. **解析器缺陷修复**：本路独立回归实验亲证（§一 SC2 行）——缺陷态下
   self-test 翻红 + 真件 `--check` 翻红（gaps 行被重吸入致 A1 爆量），产线
   修复承重、红绿真实。
3. **A5 扫描路径裁定**：脚本 `SCANNED_FILES = (.work/gsd/REQUIREMENTS.md,
   .work/gsd/ROADMAP.md, AGENTS.md)` 与 DECISIONS §3.3 登记一致（plan 字面
   仓根路径勘误为账面实位）；公开树 skip 分支经 `--tree-root` 注入缝亲测
   显式注记。正路径零负载观察 = N-2。

## 七、commit 清单（执行链 7 + 微修批 1，逐笔亲验）

| commit | 内容 | 本路验收 |
|---|---|---|
| `93a674c8` | docs(m6-6): mint the FEAT-id parity checklist | T1 ✓（134 行/survey 纯插入 6 行零删；含 E-3/E-4 两误判 + E-5/M-3 两缺口 = 本路发现） |
| `a515b3ff` | feat(m6-6): add the parity-audit gate script and CI job | T2a ✓（六断言 + self-test + 注入缝 + ci.yml 纯追加；解析器缺陷已在 T2 内闭环且回归钉亲证） |
| `d63cf79c` | fix(m6-6): add catalog variants for three McpLauncher interpolation keys | T2b ✓（51+/0- 三键同文 json 亲比） |
| `3c7498bc` | docs(m6-6): run the first parity reconciliation and pin the gaps report | T3 ✓（17 行 ≥10 时点值；A6 新鲜度现绿） |
| `73fd3ce9` | docs(m6-6): close M6-6 and the M6 milestone (validation + full suite) | T4 ✓（全套 + 三正本；SC5 本路独立复证 2104s 同值） |
| `3c2824c8` | docs(m6-6): flip the five ledgers - M6 milestone closed | T5 ✓（五正本 + AGENTS 节） |
| `c51fd92d` | docs(m6-6): pin the full-suite transcript and land the L081 cross-reference | 收口批 ✓（transcript 在树；SUMMARY/STATE 两处 L080 漏网 = M-1，已由微修批清偿） |
| `4e61977b` | fix(m6-6-01): acceptance corrections - LIB-04/LIB-13, L081, ascii header | 微修批 ✓（两行翻正锚点亲证成立；E-2 采 Delivered 优于第一路 Partial 建议 = 本路追认；L081 两处修正确认；M-2 ASCII 确认；**计数同步半途 = M-4**） |

## 八、与第一路的分歧与盲区互补

1. **LIB-13 修法分歧（追认落地版）**：第一路建议 Partial，落地 Delivered；
   本路判定 Delivered 正确（§二）——判定序 + META-06 Phase 12 双保险锚，
   Partial 反而与 checklist 自申规则相悖。
2. **第一路抽样盲区（本路全量补抓）**：EXP-13（E-3，Partial 抽验放行但
   UI/账面双向可证 Delivered）；SHELL-03（E-4，第一路宽免为「在册争议」，
   本路判违反判定序且前提不实）；Nikon HE 缺行（E-5，第一路孤儿扫描漏）；
   PNG 压缩缺行（M-3）。两路合计 134 行覆盖率 = 100%（24 抽样 + 110 差集
   复核 + 4 项发现行三眼交叉）。
3. **第一路笔误两处**（N-4）：prose 精度，不影响其 PASS 结论与证据链。

## 九、结论

- **第二路结论 = PASS（附与第一路同型的 docs-only 更正清单）**：六 SC 独
  立复跑全过（含独立全套亲跑 3848/24/0 ΔN=0）+ 红线族全零 + 收口链闭合 +
  两编排偏差追认 + 微修批追认（含一处修法分歧裁定）。**4 项内容发现
  （E-3/E-4/E-5/M-3）+ 2 minor（M-4 计数同步 + N-2 观察登记）全部
  docs-only**，不翻任何 SC、不需复测全套；建议随晨审一并落地（翻 2 行 +
  mint 2 行 + `--write` + `--check` 复跑 + STATE/SUMMARY 计数同步；修后
  gaps = 15 行仍 ≥10 一次性 AC 不回退）。**M6 milestone closed 状态不被阻
  塞**（与第一路同判）。
- 双路 PASS 均已落账（本件 + `M6-6-01-ACCEPTANCE.md`）；VALIDATION §八双
  路回填齐备，签核生效（晨审可推翻）。
- 本验收零 commit 零 push（回填与正本留工作树，`4e61977b` 先例同款——验
  收波产物由 orchestrator 收敛）；验收独立 transcript =
  `.work/gsd/phases/m6-6-feature-parity/evidence/acc2/acc2-all-run.log`
  （local-only，gitignored 证据域）。
