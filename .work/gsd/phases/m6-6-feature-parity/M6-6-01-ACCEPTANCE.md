---
phase: m6-6
plan: "M6-6-01"
kind: plan-acceptance（双重验收第一路，zcode 独立验收）
created: 2026-10-16
lane: 1（zcode 独立眼；第二路 = omp 或双 zcode 替代，待回填）
verdict: "PASS / 0 blocking + 2 error-grade 内容更正（必修）+ 2 minor + 2 nit"
base: "执行链 `93a674c8..c51fd92d`（7 commits）；不轻信执行方报告，逐条实测"
---

# M6-6-01 ACCEPTANCE — 第一路独立验收（FEATURE-MAP parity 门 + M6 milestone 收口）

> **结论头：PASS / 0 blocking + 2 error-grade 内容更正（必修）+ 2 minor + 2 nit。**
> 六条 SC 全数独立复跑通过（含**独立全套亲跑** `TOTAL|3848/24/0|2381s` exit 0，
> ΔN=0 亲证）；门脚本六断言 + self-test 红绿亲验（含**回归钉住实验**——
> 亲手重引入 DECISIONS §3.2 解析器缺陷，self-test 如实翻红）；红线族全零。
> 残留 = checklist 两行状态误判（LIB-04/LIB-13，docs-only 修）+ 两处 L080
> 错引 + 两个 nit。修复不动 SC5（零 Swift 面），无需复测全套。

## 一、SC1-SC6 逐条独立复跑（全部亲跑，非转录）

| SC | 判据 | 本路独立实测 | 结论 |
|---|---|---|---|
| SC1 | `uv run python3 Scripts/parity-audit.py --check` exit 0 | uv 形态 rc=0 + **裸 python3 形态 rc=0** 双亲跑，输出 `PASS (134 rows, id-unique, vocab clean, evidence paths verified)` | ✅ |
| SC2 | `--self-test` PASS（红绿 golden + 公开树分支） | rc=0，红 7 族（坏 id 形/重复 id/非法 status/非法 source/缺 src 路径/Delivered-Missing-V2 无据规则/stale 块）全断言族级检出；净例 + placeholder 容忍 + `--write` 愈合 + `--tree-root` 公开树分支显式注记亲验 | ✅ |
| SC3 | gaps 块行数 ≥ 10 | awk 独立计数 = **17**（3 Missing + 3 V2 + 1 Parked + 3 OOS + 7 Partial），行序 = D5 状态严重度 + 域码字母序亲核 | ✅ |
| SC4 | ci.yml 含 parity job + 裸 python3 本地 PASS | `git diff a515b3ff^..HEAD -- ci.yml` = 纯追加 11 行（build-and-test/release 两 job 零触）；`ruby -ryaml` 实载 OK（jobs = build-and-test/release/parity；runs-on ubuntu-latest / timeout 5 / checkout@v5 + 裸 python3 --check） | ✅ |
| SC5 | 全套 `--all` `TOTAL\|3848/24/0\|`（ΔN=0） | **本路独立亲跑**：`xcodebuild build-for-testing`（rc=0）→ `caffeinate -dis Scripts/test-direct.sh --all` → **`TOTAL\|3848/24/0\|2381s` exit 0**；段和机核 686+460+494+729+284+379+816 = 3848、skip 1+3+4+4+4+4+4 = 24 精确；零 MEMFAIL；七 bundle 峰值 5458/4280/1153/614/1190/4662/2832 MB 全 8G 门内；逐 bundle executed/skipped/failed 与执行方值**逐行同值**。transcript = `evidence/acc1/acc1-all-run.log`（local-only） | ✅ |
| SC6 | xcstrings = 恰 N-1 三键尾块纯插入 | `git diff d63cf79c^..HEAD` = 51+/0-（0 删行）单 hunk 尾块；三 `%lld` 变体键 grep 各恰 1 命中且 en/zh 值与裸键**逐字节同文**（python json 亲比）；`zh-audit --check` PASS = `1682 source keys, 1929 catalog keys, 30 interp keys all variant-PRESENT`；catalog keys 独立 json 计数 = **1929**；调用点 `McpLauncherPanelView.swift` 零 diff | ✅ |

## 二、checklist 质量面

- **结构机检**：134 手维护行（生成块内行已排除后独立计数）；id 全局唯一
  （awk id 列 `uniq -d` 零输出）；12 域节标题在位；`rg '[\x{4e00}-\x{9FFF}]'`
  零命中（plan AC 判据）。注：DECISIONS §1 关于裸 grep 误计 Notes 交叉引用的
  申明亲证——手维护行 Notes 列零 `FEAT-` token，裸 grep 重复输出全部来自
  gaps 生成块（A2 只取 id 单元格，语义更准，self-test 钉死口径）。
- **六状态抽验 24 行**（要求 ≥20，各态覆盖：Delivered 14 / Partial 6 /
  Missing 3 / V2 3 / OOS 3 / Parked 1）：
  - **Delivered 抽验全对**：LIB-01（M2-2-1 验收件在）、LIB-05（M2LIB-04
    Delivered 对表）、LIB-09（M4-1 导入类型选择器）、LIB-11/12（M6-4
    VALIDATION + src 三件在树）、EXP-03（M6-3 VALIDATION + GainMapEncoder）、
    NODE-08（M6-2 VALIDATION + RenderProcess）、OWN-03（M6-1 VALIDATION）、
    ADJ-10/DRT-02（M2-5/M2-6 AGENTS 增量节）、MASK-04（M2-7-2 beyond-parity
    判定与 DECISIONS §2 同源）、EDT-08、OWN-09、AI-09——src + doc 指针全可达。
  - **Partial 抽验**：SHELL-03（ThemeTokens.swift 自述 dark-glass 家族；
    Partial 为 DECISIONS §2 在案争议判定「晨审可翻」——与 REQUIREMENTS
    M2UIW-01「tokens Delivered」存在判定序张力，但在册可翻，不算违规）/
    SHELL-05 / EXP-13 / LIB-14 / DEV-07 / OWN-12——全部带 note + 锚。
  - **V2 抽验**：AI-10 / MASK-11（V2-PROPOSAL §七 + 裁决⑦）、EXP-02
    （ALCE-02 + OQ-V2-5 :31 亲证）——EXR 归 V2 不入 OOS（F2 勘误兑现）。
  - **OOS 抽验**：DEV-05/06（STACK.md CIRAW 结构性不可达）、SHELL-06
    （PROJECT.md :68 2026-09-27 渠道终裁亲证）。
  - **Parked**：MASK-12（REQUIREMENTS :366 IOP-MASK-06 parked + 重启条件锚亲证）。
  - **Missing 抽验 = 本路两条 error 级发现**（见 §七 E-1/E-2）；LIB-15
    watched folders 复核为真 Missing（命中仅 legacy Session 时代
    FolderWatchStatus 状态显示，非图库 auto-ingest 语义；charter ⑤ 锚成立）。
- **12 域覆盖 / 孤儿扫描**：survey §1-§8 逐节对表 + §2.6 并 DRT（DRT-09 +
  ADJ-13..16）+ §9 dt-gap 不入行（OWN-12 + ADJ-19 承载，DECISIONS §1 在案）+
  §10 缺失清单十项逐条有行（示波器 → EDT-04、设置面 → SHELL-04/05/06 等）+
  上游增量测绘五条处置有登记（raster→DEV-08 / LUT 编码→EDT-13 / OCIO·分组·
  任务岛不 mint / 0.3.1 选择器→LIB-09）。孤儿零命中。checklist「Target 0.3.2」
  与 survey 增补节（v0.3.2 = `9ce6a24`）一致。
- **公开树纪律**：全英文（CJK 零命中）；`doc:` 知情申报在头注（路径公开/
  内容不公开两层写明）；Methodology credit（LightCraft MIT，零代码移植零
  NOTICE）在头注。

## 三、六裁决兑现表逐条对表（charter 六裁决，LIGHTCRAFT-NOTES §六）

| # | 兑现 phase | 本路亲验 |
|---|---|---|
| ① MCP 单写者锁 | M6-1 | `M6-1-VALIDATION.md` 在（:39 SingleWriterLock 对账链亲读）；OWN-03 行 Delivered 锚可达 |
| ② UltraHDR | M6-3 | `M6-3-VALIDATION.md` 在（:29 ISO 21496-1 亲读）；EXP-03 行锚可达 |
| ③ process version | M6-2 | `M6-2-VALIDATION.md` 在（标题行 + sidecar v10 `process`）；NODE-08 行锚可达 |
| ④ AI 分割 spike | M6-4-02 | M6-4 VALIDATION 在（spike 判定 + SAM CoreML → V2 裁决⑦）；AI-10/MASK-11 V2 行锚可达 |
| ⑤ stacks/auto-stack | M6-4-01 | M6-4 VALIDATION 在（schema v5 两新表 + auto-stack 语义）；LIB-11/12 行锚可达 |
| ⑥ FEATURE-MAP + CI 门 | M6-6（本批） | 本路 §一 SC1-SC4 全过 = 直接兑现 |

## 四、milestone 收口面

- **六 phase 终态汇编数字链对账**：M6-1 `TOTAL|3689/24/0|2157s`（:24 亲读）→
  M6-2 `TOTAL|3725/24/0|2113s`（:26）→ M6-3 `TOTAL|3759/24/0|` 两路（:33）→
  M6-4 3841 实测（:34）→ M6-5 `TOTAL|3848/24/0|` 三路（:27）→ **本批本路
  独立亲跑 3848/24/0（ΔN=0）**——VALIDATION §二汇编表逐行与各 VALIDATION
  正本一致，链 3689→3725→3759→3841/3843 核销→3848→3848 亲证闭合。
- **五正本翻账**：REQUIREMENTS M6INT-04 Delivered（:413，锚全）✓ / ROADMAP
  M6-6 行 ✅（:77 全细节）+ M6 closed 头部块 ✓ / STATE `milestone: M6` +
  `m6_phases 7/7`（:21-22）+ current/status 翻转带 prior 内联 ✓ / TODO M6-6
  [x]（:356 五任务 commit 链）+ M6 头部收官行（:348）✓ / GOAL-STATE 续接点
  前插（:19，晨审 → 主会话队列）✓ / AGENTS「M6-6 架构增量」节（:477-484，
  六条）✓。带日期历史行零改写（diff 审计 = 追加为主亲核）。
- **编排偏差两处追认意见**：
  1. **§四.1 互操作先行编排 —— 追认**。裁决⑥原文「作为 M6 对标里程碑的
     第一个 plan」亲证在案（LIGHTCRAFT-NOTES :98/:113 + pre-flip ROADMAP
     M6-6 行 git 考古）；取代编排的依据（FEATURE-MAP 无依赖、四裁决件单向
     依赖链）成立且**实质更优**：checklist 状态判定以账面为准——若按原文
     先行，M6-1..M6-5 五裁决件盘点时全为未交付态，首轮 gaps 必然大面积失
     真、收口前须整体重审；实际编排使首轮对账直接站在终态账面。登记三处
     在案（ROADMAP pre-flip 行 + VALIDATION §四.1 + M6 closed 块 flippable
     注记），晨审/用户可随时推翻的通道完备。
  2. **§四.2 N-1 rider 提前清偿 —— 追认**。M6-5-VALIDATION :124 项级原文
     「→ 下一清算批候选」（未点名 M6-6）与 :270 汇总句（点名收口批）两层
     亲读无误；本批先行清偿 = S 量级零风险 + milestone 收口前清一枚已知
     zh 活体（SC6 亲证清偿质量：三键同文、PASS 恒定、1926→1929）；登记
     引原文 + 偏差标注齐备。
- **挂账单一清单完备性**：VALIDATION §五/§六六项 = CONTEXT §4 六项逐条同构
  （Manual-Only 19 行 GUI 批 / V17 硬化批 / V2 九项+留置五项 / charter 挂账
  五件 / 编排偏差 / 瘦身手术主会话专属）——移交面无缺项。

## 五、执行期三事件处置复核

1. **L081 签名债登记**：LESSONS L081（:843-847）四段结构完整（现象/根因/
   对策/适用），与 DECISIONS §3.1 同文；L080 确为 M6-4-02 代理 env 课占用
   亲证。**残留错引两处**（minor M-1，见 §七）：`M6-6-01-SUMMARY.md:37` 与
   `STATE.md:28`（Current phase 行）仍写「LESSONS L080」——`c51fd92d` 的
   交叉引用修正只落了 DECISIONS，两处漏网。
2. **解析器缺陷修复（marker 重吸入）**：**self-test 确实钉住该回归**——
   本路做了正反实验：对 `/tmp` 副本亲手删除 `if in_block: continue` 两行
   重引入缺陷 → `--self-test` 翻红（`C --write heals the stale block` 失败
   —— 愈合后的 gaps 块 FEAT 行被重吸入致 A2 重复翻红，即 DECISIONS 所述
   「stale fixture 往返测试红」机理）；同缺陷态下真 checklist `--check`
   翻红（A1 ×17）证明产线修复承重。原版 self-test PASS。红绿真实性亲证。
3. **A5 扫描路径裁定**：脚本 `SCANNED_FILES = (.work/gsd/REQUIREMENTS.md,
   .work/gsd/ROADMAP.md, AGENTS.md)` 与 DECISIONS §3.3 登记一致（plan 字面
   仓根路径勘误为账面实位）；文件缺席 = 显式 skip 注记（`--tree-root` 注入
   缝下公开树分支亲测）。

## 六、红线族亲跑（执行链 `93a674c8^..HEAD`）

- Swift 全域（LightamerCore/LightamerIOP/App/Tests）+ `*.metal` +
  `Project.swift`：**零 diff**（`git diff --name-only` 过滤零命中亲证）。
- `LightamerSidecar.swift` / Pipe/History / PipeCacheKey / V50Order / MCP
  快照族（McpLauncherPanelView 调用点）/ Export 三件（ExportFormatSpec/
  ImageIOEncoders/WebPEncoder）：零 diff（含于上条全域零命中）。
- UserDefaults 零新键（diff 内 `UserDefaults|.standard` 命中仅 STATE/DECISIONS
  账面 prose，零代码）；`\.runModal(` App/Sources 零命中；
  `String.LocalizationValue("` 插值禁形零命中。
- xcstrings = 恰三键尾块纯插入（SC6，51+/0-）。
- survey 正本：diff = 纯插入 7 行指针段（330→337 行），正文零改写。
- 三 untracked 兄弟件（`M3-1-ACCEPTANCE-PI.md` / `retro-dual/backfill-pi.zsh`
  / `research/dt-clone-archive/`）在位零触碰；工作树零新增 untracked 源文件。

## 七、独立发现（本路自有，按严重度）

### E-1【error·内容必修】FEAT-LIB-04（Activity view）= Missing 误判
- **事实**：功能在项目工作区**已交付且在树**——
  `App/Sources/Lightamer/Library/Views/LibraryInspectorView.swift:161-206`
  `activitySection` = 按日照片数柱图（peak 归一化柱 + ACTIVITY 头）+ 点击
  `toggleActivityDay`；`LibraryInspectorModel.swift:122/:171/:247` =
  `activitySeries` 装载 + `.day` 臂折叠（click-a-day-to-filter）；
  `LightamerCore/Sources/Library/LibraryQueries.swift:542-573` `activitySeries`
  + `:575` `dayFilter` UTC 整日投影。
- **账面**：REQUIREMENTS :26 **M2LIB-05 = Delivered 数据面+壳面（合龙终态
  2026-09-29）**，明文含「Activity view（按日数量图点击过滤）」与「ACTIVITY
  柱点击=日期腿」——判定序第一条（REQUIREMENTS Delivered 优先）即命中。
- **违规点**：checklist 行状态 Missing + note「ledger-silent surface」不实
  （账面非沉默）；DECISIONS §2「Missing 全集……账面沉默面（前者）」同句
  不实。survey :28 亦明文该功能面对象。
- **修法**：LIB-04 → **Delivered**（evidence 加 `src:…LibraryInspectorView.swift`
  + `doc:.work/gsd/REQUIREMENTS.md`）；summary 矩阵 Delivered 117→118 /
  Missing 3→2；gaps 17→16。

### E-2【error·内容必修】FEAT-LIB-13（Smart albums）= Missing 误判
- **事实**：saved-filter collections 全链在树且**已装配进项目工作区**——
  `LightamerCore/Sources/Session/SmartAlbumStore.swift`（create/rename/
  remove/evaluate，app 级 JSON 目录）；`App/Sources/Lightamer/UI/SidebarView.swift
  :294/:321/:340/:454`（CRUD + 列表节）；`App/Sources/Lightamer/UI/Shell/
  WorkspaceHostView.swift:556-559`（**项目工作区**装配 `LibraryInspectorModel
  (…, smartAlbums: SmartAlbumStore())`）；`LibraryInspectorView.swift:378-405`
  SMART ALBUMS 节（evaluate(.library) 成员数 + 谓词折叠 arming）。
- **账面**：REQUIREMENTS :23 **M2LIB-02 = Delivered**（「智能相册（Filter
  JSON 谓词）」）+ :26 M2LIB-05 = Delivered（「SMART ALBUMS evaluate(.library)
  成员闭环+相册谓词折叠」）。
- **违规点**：行 note「only a legacy session-era store exists, no
  project-workspace smart albums」不实（store 已进项目工作区 Inspector 并按
  项目库求值）；charter 裁决⑤「smart albums 次之」指 LightCraft 语义**增强
  候选**的排序（未立项），行把「增强未立项」与「基本功能不存在」两语义混
  为 Missing。
- **修法**：LIB-13 → **Partial**（保守侧：registry 为 app 级非 per-project、
  与 Alcedo 项目内语义的偏差作 note；若晨审判「面已齐」可再翻 Delivered）；
  summary Missing 3→1 / Partial 7→8；gaps 行数不变（Missing→Partial 同在
  gaps 序内移段）。**修正后 gaps 16-17 行仍 ≥10，SC3 一次性 AC 不回退。**
- **共性根因**：两行均违反 plan T1/CONTEXT §1.1 自申的「账面 Delivered 优先
  判定序」——判定时未对 REQUIREMENTS M2LIB 族做 Delivered 标记对表。修法
  docs-only：翻行 + note + `--write` 复跑 `--check`（A6 新鲜度门强制同步）；
  零 Swift 面，**SC5 无需复测**。

### M-1【minor】`LESSONS L080` 错引残留两处
`M6-6-01-SUMMARY.md:37` 与 `.work/gsd/STATE.md:28` 写「教训登记 LESSONS
（L080）」，正确定 = **L081**（L080 = M6-4-02 代理 env 课）。`c51fd92d` 只
订正了 DECISIONS。修法 = 两处一字改。

### M-2【minor】checklist 头注两个 U+00B7（`·`）
`docs/parity-checklist.md:3/:5`（Last updated 行 + Gate 行）。plan AC =
CJK 零命中（过）；与 DECISIONS §3.4 ci.yml 注释 em-dash→ASCII 的自申纪律
不同向。修法可选（`·`→`;` 或 `,`）。

### N-1【nit·观察】账面日期 2026-10-16 vs git author date 2026-10-15
本批全部文件/账面写 2026-10-16，commit 与机器时钟为 2026-10-15。**M6-5 批
同款既有模式**（`e7e369b1` 2026-10-15 06:37 关账「2026-10-16」），账面内部
一致、非本批新缺陷；晨审知悉即可，暂不动（改法如需 = 全批一次性勘误批）。

## 八、commit 清单（7 commits，逐笔亲验）

| commit | 内容 | 验收 |
|---|---|---|
| `93a674c8` | docs(m6-6): mint the FEAT-id parity checklist | T1 ✓（134 行/survey 纯插入；两行状态误判 = E-1/E-2） |
| `a515b3ff` | feat(m6-6): add the parity-audit gate script and CI job | T2a ✓（六断言 + self-test + 注入缝 + ci.yml 纯追加） |
| `d63cf79c` | fix(m6-6): add catalog variants for three McpLauncher interpolation keys | T2b ✓（51+/0- 三键同文） |
| `3c7498bc` | docs(m6-6): run the first parity reconciliation and pin the gaps report | T3 ✓（17 行 ≥10；内容含 E-1/E-2 两假行） |
| `73fd3ce9` | docs(m6-6): close M6-6 and the M6 milestone (validation + full suite) | T4 ✓（全套 + 三正本；SC5 本路独立复证） |
| `3c2824c8` | docs(m6-6): flip the five ledgers - M6 milestone closed | T5 ✓（五正本 + AGENTS 节 + CONTEXT 两 minor 镜像同步） |
| `c51fd92d` | docs(m6-6): pin the full-suite transcript and land the L081 cross-reference | 收口批 ✓（transcript + DECISIONS L081；SUMMARY/STATE 两处漏网 = M-1） |

## 九、结论

- **第一路结论 = PASS（附必修清单）**：六 SC 独立复跑全过 + 红线族全零 +
  收口链闭合 + 两编排偏差追认；2 项 error 级内容更正（checklist LIB-04/
  LIB-13）为 docs-only 小修，建议随第二路验收批或晨审一并落地（翻行 +
  `--write` + `--check` 复跑 + M-1 两处一字改），不阻塞 milestone closed
  状态、不需复测全套。
- 第二路（omp 或双 zcode 替代）独立验收待行；双 PASS 后 VALIDATION 签核
  生效（晨审可推翻）。
- 本验收零 push；验收独立 transcript =
  `.work/gsd/phases/m6-6-feature-parity/evidence/acc1/acc1-all-run.log`
  （local-only，gitignored 证据域）。
