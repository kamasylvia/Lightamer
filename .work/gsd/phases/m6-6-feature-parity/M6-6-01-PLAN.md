---
phase: m6-6
plan: "M6-6-01"
title: "M6-6 FEATURE-MAP ID 化 + CI 对账门 + M6 VALIDATION 收口（单 plan）——T1 FEAT-ID parity 清单落 repo 树 docs/parity-checklist.md（120-140 行盘点 + survey 头注指针）/ T2 Scripts/parity-audit.py（zh-audit 同型 --check/--self-test/--report/--write 六断言门）+ ci.yml parity job + N-1 三插值键 rider / T3 首轮对账（--write 生成 summary+gaps 块，gaps ≥10 行）/ T4 M6 milestone VALIDATION 兼收口（milestone_closeout: M6 + 六 phase 终态汇编 + 六裁决兑现表 + 铭谢/边界 + 全套 --all 确认轮）/ T5 五正本翻账 + AGENTS 架构增量节"
wave: 1
depends_on: []
autonomous: true
requirements: ["M6INT-04（REQUIREMENTS M6 族——FEATURE-MAP ID 化 parity 清单 + CI 对账门）", "ROADMAP §M6-6 行（裁决⑥ + M6 VALIDATION 收口 + 编排偏差登记落收口段）", "M6-5-VALIDATION §挂账单一清单（N-1 rider ② + 其余五项处置见 CONTEXT §2 D7）"]
estimated_tests: "+0（ΔN = 0——零 Swift 测试面；T2 rider 纯 xcstrings 三键；N-1 清偿后 zh-audit --check 断言 5 三键 ABSENT → PRESENT 转绿）"
test_bundles: []
baseline: "3848/24/0（M6-5 三路实测，2026-10-16；对账基线单一实测口径在案）"
expected_all: "3848/24/0（ΔN = 0——本批零 Swift 触碰；对账式 = M6-5 实测 + 0；任何 ΔN≠0 或 fail = 停手上报）"
success_criteria:
  - "SC1 uv run python3 Scripts/parity-audit.py --check exit 0（A1-A6 零违规，含 id 唯一性）"
  - "SC2 uv run python3 Scripts/parity-audit.py --self-test PASS（红绿 golden：坏 id 形 / 重复 id / 非法状态 / 缺失 src 路径各 ≥1 红例 + 1 净例 + 公开树分支〔.work 缺席〕例）"
  - "SC3 docs/parity-checklist.md gaps 块行数 ≥ 10（T3 transcript 记 SUMMARY）"
  - "SC4 .github/workflows/ci.yml 含 parity job（ubuntu-latest + parity-audit --check）；裸 python3 形态本地 PASS"
  - "SC5 全套 --all TOTAL|3848/24/0|（ΔN=0；build-for-testing 前置；异常停手上报）"
  - "SC6 Resources/Localizable.xcstrings diff = 恰 N-1 三键尾块纯插入"
files_modified:
  - docs/parity-checklist.md                                        # T1 新建：FEAT-ID parity 清单（全英文、公开树纪律）——头注（方法论铭谢 + 粒度约定 + 词表）+ 12 域 row 表（120-140 行）+ 两生成标记块占位（T3 填充）
  - .work/gsd/research/ALCEDO-FEATURE-MAP.md                        # T1：头注指针一段（additive——survey 正本保留声明 + checklist 指针 + 「FEAT id 唯一 mint 点在 checklist」纪律），正文 330 行零改写
  - Scripts/parity-audit.py                                         # T2 新建：stdlib-only 六断言门（A1 行结构 / A2 id 唯一 / A3 Source·Status 词表 / A4 证据路径存在性〔src 无条件 + doc 条件，D3 规则〕/ A5 FEAT 引用链接性 / A6 生成块新鲜度）+ --write + --self-test golden 红绿
  - .github/workflows/ci.yml                                        # T2：追加 parity job（ubuntu-latest / timeout 5min / python3 Scripts/parity-audit.py --check）；既有 build-and-test + release 两 job 零触碰（纯 additive）
  - Resources/Localizable.xcstrings                                 # T2 rider（N-1）：mcp_launcher_status_running %lld / mcp_launcher_done_writes %lld / mcp_launcher_exit_code %lld 三变体键尾块纯插入（en+zh 值与既有裸键同文）
  - .work/gsd/phases/m6-6-feature-parity/M6-6-01-SUMMARY.md         # T4：执行摘要（逐任务记账 + SC 对表 + gaps 块行数 + --all 终值 transcript 指针）
  - .work/gsd/phases/m6-6-feature-parity/M6-6-01-DECISIONS.md       # T4：裁定记录（行粒度取舍 + 状态判定争议台账 + 偏差）
  - .work/gsd/phases/m6-6-feature-parity/M6-6-VALIDATION.md         # T4：M6-6 phase SC 三列 + milestone_closeout: M6（六 phase 终态汇编 + 六裁决兑现表 + 编排偏差登记落收口段 + 铭谢/边界 + M6 挂账单一清单 = CONTEXT §4 六项）
  - AGENTS.md                                                       # T5：「M6-6 架构增量」节（parity 门形态 + ID 体系词表 + checklist 路径 + 终值 + N-1 三键登记）
  - .work/gsd/REQUIREMENTS.md                                       # T5：M6INT-04 → Delivered（validated；终态注记 = checklist 路径 + 门断言数 + 首轮 gaps 行数）
  - .work/gsd/ROADMAP.md                                            # T5：M6-6 行 ✅ 闭环 + 头部 Milestone 6 段 closed 翻账
  - .work/gsd/STATE.md                                              # T5：M6 Ledger M6-6 行 complete + m6_phases_complete 7/7 + milestone closed 注记（front-matter 语义随 M5 收口先例）
  - .work/TODO.md                                                   # T5：M6-6 条目 [x] + M6 头部收官行
  - .work/GOAL-STATE.md                                             # T5：续接点翻新（M6 closed → 晨审/主会话队列）
---

> **夜间全自动授权**（先例 D-07-3-T5-1；晨审可推翻）。范围与裁定正本 =
> `M6-6-CONTEXT.md`（§1 范围 + §2 裁定 D1-D9 + §3 盘点概要 + §4 挂账
> 单一清单 + §5 SC + §6 风险）。**零 Swift 触碰 / 零新 SPM / 零新
> UserDefaults 键 / 零 `.metal` / xcstrings 仅 N-1 三键尾块纯插入 /
> Project.swift 零 diff（Scripts 与 docs 不入 tuist 登记面，无需
> tuist generate）**。行措辞纪律：checklist 我方语言转写，零 Alcedo
> prose 复制（GPL-3.0 只读红线）；`docs/` 树文件全英文（公开树纪律）。

# Plan M6-6-01 — FEATURE-MAP ID 化 + CI 对账门 + M6 milestone 收口（单 plan）

> **性质**：对账基建 + 首轮对账 + milestone 收口三合一。每任务独立
> commit（Conventional Commits，只 add 相关文件）；构建/全套用
> `caffeinate -dis` 包裹；**全套前置 = `xcodebuild build-for-testing`
> 硬性（M6-5 I-1 教训：漏步 = 陈旧二进制假绿）**；单测定向轮本批
> 一般不触发（零 Swift 面），SC5 全套轮为唯一测试轮。
> **bundle token 纪律**：`test-direct.sh` 注册表
> `(IOP IOPParity Layers Library Sessions Export App)` 大小写敏感无
> 归一（M6-5 M-1 在册）。

## read_first（全局，每任务开工前过一遍）

- `.work/gsd/phases/m6-6-feature-parity/M6-6-CONTEXT.md`（本批正本，
  D1-D9 裁定逐条遵守）
- `.work/config.toml [gsd]` paused/auto 开关（暂停机制）
- `.work/LESSONS.md` L041（tuist generate 恒末位——本批不适用，备查）/
  I-1 事故条（build-for-testing 前置）
- `AGENTS.md` 资源监控节（--all 批准制 + 8G 门 + MEMFAIL 机检 + 贴线
  族 ±3% 口径）
- `Scripts/zh-audit.py`（门脚本形态母版——CLI 三模式 / self-test 红绿
  golden 纪律 / docstring 体例）

---

## T1 — FEAT-ID parity 清单落 repo 树（D1/D2/D3 兑现）

- **action**：
  1. 新建 `docs/parity-checklist.md`（全英文）：
     - **头注**：目的（Alcedo-parity machine-gated checklist，M6-6
       ruling ⑥）+ 方法论铭谢（LightCraft，MIT OR Apache-2.0，方法论
       借鉴零代码移植）+ **粒度约定**（row = Alcedo 功能面逐条；survey
       prose 正本指针 = `.work/gsd/research/ALCEDO-FEATURE-MAP.md`，
       公开树不可见注记）+ 三词表（Domain 12 码 / Source 3 词 /
       Status 6 词，逐词一句话定义）+ 证据指针两级规则（`src:` 无条件
       机检 / `doc:` 条件机检 + gitignored 证据域恒 format-only）+
       **id 稳定不重编号**纪律 + 维护纪律（「whoever lands a feature
       updates its row in the same commit」LightCraft 同款 + 账面
       Delivered 优先判定序）。
     - **12 域 row 节**（`## SHELL — Workspace shell` … `## OWN —
       Lightamer-exclusive surface`，节序按 CONTEXT §3 表）：每行
       `| FEAT-<DOM>-NN | <feature, own words> | <Source> | <Status> |
       <Evidence> | <Notes> |`。盘点覆盖 CONTEXT §3 全域；预估
       120-140 行（粒度合并允许，功能面零遗漏为准绳）。**状态判定 =
       账面优先序**（CONTEXT §1.1）：REQUIREMENTS Delivered 标记 →
       STATE Ledger 终态列 → phase VALIDATION → AGENTS 架构增量节；
       账面沉默面 → Missing 保守侧 + note（R2）。`OOS` 行带裁决锚
       （Updates 页 = 2026-09-27 渠道终裁 / EXR = ALCE-02 V2 裁决 /
       Nikon HE 恢复 = CIRAW 路线 / demosaic 算法菜单 = STACK.md
       不可达注记）；`V2` 行带 V2-PROPOSAL §七 / REQUIREMENTS 锚；
       `Parked` 行带重启条件锚（IOP-MASK-06 形）。
     - **两生成标记块占位**：`<!-- parity:summary -->` /
       `<!-- /parity:summary -->` 与 `<!-- parity:gaps -->` /
       `<!-- /parity:gaps -->`（空块占位，T3 `--write` 填充）。
  2. `.work/gsd/research/ALCEDO-FEATURE-MAP.md` 文件头（front-matter
     之后的引言区）插入指针段（**纯 additive**）：survey 正本保留
     声明 + checklist 路径 + FEAT id 唯一 mint 点纪律 + 升维日期与
     phase 锚。正文 330 行零改写。
- **验收标准（机检）**：
  - row 总数 ∈ [100, 160]（grep `^| FEAT-` 计数）；12 域节标题在位。
  - `FEAT-` id 无重复（`grep -o 'FEAT-[A-Z]\{3,4\}-[0-9]\{2\}' |
    sort | uniq -d` 零输出）——T2 门落地前的临时自检，T2 后由 A2 承载。
  - Status 列词表内（六词精确匹配；临时 grep 自检）。
  - checklist 全英文（非 ASCII 抽查：允许行内中文零出现——`grep -P
    '[\x{4e00}-\x{9fff}]'` 零命中）。
  - survey 文件 diff = 纯插入指针段，`git diff --stat` 正文行数不变。
- **commit**: `docs(m6-6): mint the FEAT-id parity checklist from the Alcedo feature map`

## T2 — `Scripts/parity-audit.py` 六断言门 + CI parity job + N-1 rider（D4 + D7②）

- **action**：
  1. 新建 `Scripts/parity-audit.py`（stdlib-only；docstring 体例照
     zh-audit.py——Scan domain / Assertions / Modes / Extra flags /
     uv 红线运行例）：
     - **断言族**（CONTEXT §2 D4）：
       A1 行结构（6 列可解析 + id 形 regex
       `^FEAT-(SHELL|LIB|EDT|ADJ|DEV|GEO|NODE|MASK|DRT|EXP|AI|OWN)-\d{2}$`）；
       A2 id 唯一；A3 Source ∈ {Alcedo, LightCraft, Lightamer} ∧
       Status ∈ {Delivered, Partial, Missing, V2, Parked, OOS}；
       A4 证据路径存在性（`src:` 无条件 + `:line` ≤ 文件行数；`doc:`
       按 D3——`.work/` 根存在则检、缺席则注记 skip；
       `.work/gui-acceptance/` 与 `phases/*/evidence/` 恒 format-only）；
       A5 FEAT 引用链接性（扫 `REQUIREMENTS.md`/`ROADMAP.md`/`AGENTS.md`
       中的 `FEAT-` id，须在 checklist 在册；被扫文件缺席 = skip）；
       A6 生成块新鲜度（内存重算 summary/gaps 两块 == 盘上块，漂移 =
       「stale — run --write」违规）。
     - **模式**：`--check`（全部断言，exit 0/1，键级/行号 detail）/
       `--report`（人读：域×状态计数 + gaps 预览）/ `--write`（刷新两
       生成块）/ `--self-test`（golden 红绿：坏 id 形 / 重复 id /
       非法 Status / 缺失 `src:` 路径 各 ≥1 红例 + 1 净例 +
       **公开树分支例**〔临时树无 `.work/`，A4 走 skip 分支且不误报〕；
       全命中 exit 0）。`--checklist PATH` 覆盖（self-test 用内嵌
       fixture，不打真件）。
     - 报告体例照 zh-audit（violations 计数 + 逐条 detail）。
  2. `.github/workflows/ci.yml` 追加 job（**纯 additive，既有两 job
     零触碰**）：
     ```yaml
       parity:
         # Doc-level parity gate (M6-6 ruling 6): every FEAT id unique,
         # status/source vocab, cited evidence paths exist. Pure stdlib
         # Python — no macOS runner needed.
         runs-on: ubuntu-latest
         timeout-minutes: 5
         steps:
           - uses: actions/checkout@v5
           - name: Parity checklist audit
             run: python3 Scripts/parity-audit.py --check
     ```
  3. **N-1 rider**（CONTEXT D7②）：`Resources/Localizable.xcstrings`
     补三变体键 `mcp_launcher_status_running %lld` /
     `mcp_launcher_done_writes %lld` / `mcp_launcher_exit_code %lld`
     （**尾块纯插入**，en+zh 值与既有裸键值同文；调用点
     `McpLauncherPanelView.swift` 零触碰）。
  4. AGENTS 架构增量节登记推迟到 T5（本任务不触 AGENTS，避免 T4 前
     双写）。
- **验收标准（机检）**：
  - `uv run python3 Scripts/parity-audit.py --self-test` PASS（SC2）。
  - `uv run python3 Scripts/parity-audit.py --check` PASS（SC1；A6 在
    T3 前对空占位块容忍——占位块尚未填充时 A6 检「块标记在位」，
    填充后检「内容一致」；两态语义写进 docstring）。
  - `python3 Scripts/parity-audit.py --check`（裸 python3，CI 形态）
    PASS（SC4 前半）。
  - `git diff .github/workflows/ci.yml` = 纯追加 job 块；既有 job 行
    零 diff。
  - `git diff Resources/Localizable.xcstrings` = 恰三键尾块纯插入
    （SC6）；`uv run python3 Scripts/zh-audit.py --check` PASS 且断言
    5 三键 ABSENT → PRESENT。
  - Swift 树零 diff（`git status --short` 无 `*.swift`）。
- **commit**: `feat(m6-6): add the parity-audit gate script and CI job`
  + rider 单独一笔 `fix(m6-6): add catalog variants for three McpLauncher interpolation keys`

## T3 — 首轮对账 + gaps 报告（D5 兑现）

- **action**：
  1. `uv run python3 Scripts/parity-audit.py --write`（生成 summary +
     gaps 两块；gaps 行序 = Missing → V2 → Parked → OOS → Partial，
     同状态域码字母序）。
  2. `--write` 后复跑 `--check`（A6 新鲜度转绿）；`--report`
     transcript 落 SUMMARY（域×状态计数矩阵 + gaps 逐行）。
  3. **gaps 行数下限核验**：`<!-- parity:gaps -->` 块内表行 ≥ 10
     （SC3；低于 10 = 盘点遗漏信号，回 T1 复核而非降门）。
- **验收标准（机检）**：`--check` exit 0；gaps 块行数 ≥ 10（transcript
  在案）；`git diff docs/parity-checklist.md` 限于两生成块内容。
- **commit**: `docs(m6-6): run the first parity reconciliation and pin the gaps report`

## T4 — M6 milestone VALIDATION 兼收口（D6/D8/D9 兑现）

- **action**：
  1. **全套确认轮**：`xcodebuild build-for-testing -workspace
     Lightamer.xcworkspace -scheme Lightamer -destination
     'platform=macOS' CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual
     ENABLE_HARDENED_RUNTIME=NO` → `caffeinate -dis Scripts/
     test-direct.sh --all`（夜间授权链 = 批准在案；运行中监视 8G 门 +
     MEMFAIL，异常立即 kill）。**预期 `TOTAL|3848/24/0|`（ΔN=0）**；
     任何 fail / ΔN≠0 / 段和≠TOTAL → 停手上报不静默修。
  2. `M6-6-01-SUMMARY.md`（逐任务记账 + SC1-SC6 对表 + gaps 块行数 +
     域×状态矩阵 + `--all` transcript 指针）+ `M6-6-01-DECISIONS.md`
     （行粒度取舍 / 状态判定争议台账 / 执行期偏差——零结构性偏差
     预期）。
  3. `M6-6-VALIDATION.md`：front-matter `phase: M6-6` +
     `milestone_closeout: M6` + `nyquist_compliant`（判定后填写）；
     内容 = M6-6 phase SC 三列对账（charter 验收形态「ID 清单 + CI 门
     落地跑绿 ✓ + M6 SC 三列对账 ✓」逐项）+ **六 phase 终态汇编**
     （M6-1 3689 / M6-2 3725 / M6-3 3759 / M6-4 3841→核销 3848 链 /
     M6-5 3848 / 本批实测——VALIDATION 正本指针逐行）+ **六裁决兑现
     表**（CONTEXT §2 D6 六行）+ **编排偏差登记落收口段**（裁决⑥
     「第一个 plan」原文 + 互操作先行编排 + flippable 申报）+
     **铭谢/边界节**（CONTEXT §2 D9 全文落位：LightCraft 方法论铭谢
     零 NOTICE 义务申报 + §1 边界清单 + §4 挂账单一清单六项）+
     授权记录（夜间授权链 + C 档第 3 停形态 + 晨审可推翻）+ 签核节。
  4. 双重验收注记：执行批完成后按制度编排（zcode 独立验收 → 串行
     omp 二验；omp 配额阻塞时双 zcode 独立眼替代先例）——本 plan 产
     `ACCEPTANCE` 脚手架占位节，结论由验收波回填；VALIDATION 签核 =
     验收双 PASS 后（夜间授权链下由收口批落签，晨审可推翻）。
- **验收标准（机检）**：
  - `TOTAL|3848/24/0|` exit 0 + 0 MEMFAIL + 七 bundle 全 8G 门内
    （SC5）；对账式 = 3848 + 0 精确；异常形态停手上报。
  - VALIDATION 含 milestone_closeout: M6 + 六裁决表六行 + 编排偏差
    登记段 + 铭谢/边界节 + 挂账单一清单六项（grep 可核）。
- **commit**: `docs(m6-6): close M6-6 and the M6 milestone (validation + full suite)`

## T5 — 五正本翻账 + AGENTS 架构增量节（§1.5 兑现）

- **action**：
  1. `AGENTS.md`「M6-6 架构增量」节：parity 门形态（六断言 + CI job +
     本地 red-line battery 引用形）+ ID 体系三词表 + checklist 路径与
     双正本分工（survey = `.work/` 研究正本 / checklist = repo 树对账
     正本）+ 终值 + N-1 三键登记 + 「FEAT id 唯一 mint 点 + 落功能
     同 commit 更新行」维护纪律 + V17 候选指针（M6-5 挂账③移交注记）。
  2. `REQUIREMENTS.md`：M6INT-04 → **Delivered**（validated；终态
     注记 = checklist 路径 + 六断言 + 首轮 gaps 行数 + phase 锚）。
  3. `ROADMAP.md`：M6-6 行 ✅ 闭环（SC 兑现摘要 + 终值 + 正本指针）+
     头部 Milestone 6 段追加 **closed**。
  4. `STATE.md`：front-matter `m6_phases_complete: 7` + current_phase/
     status 翻 M6 closed（milestone 字段与 closed 语义随 M5 收口批
     先例核对后落）+ M6 Ledger M6-6 行 complete + 终值列。
  5. `TODO.md`：M6-6 条目 [x]（执行 + 验收 + VALIDATION 摘要，带日期
     历史行只追加）+ M6 头部收官行（六 phase 全闭环 + 挂账移交指针）。
  6. `GOAL-STATE.md`：续接点翻新 = M6 closed → 晨审/主会话队列
     （瘦身手术第二次触发确认 + V2/Maintenance 站未立项态 + Manual-Only
     GUI 批安排——CONTEXT §4 清单引用）。
- **验收标准（机检）**：五正本 + AGENTS 六文件全落；REQUIREMENTS
  M6INT-04 Delivered 可 grep；ROADMAP 头部含 M6 closed；STATE 7/7；
  TODO M6-6 [x]；带日期历史行零改写（`git diff` 审计 = 追加为主）。
- **commit**: `docs(m6-6): flip the five ledgers — M6 milestone closed`

---

## red_lines（零 diff 机检族，T4 收口核对）

- 全部 Swift 源零 diff：`LightamerCore/` `LightamerIOP/` `App/`
  `Tests/` 全域（本批零 Swift 触碰；N-1 rider 仅 xcstrings）。
- 全部 `*.metal` 零 diff（零新 kernel 传承兑现）。
- `Project.swift` 全零 diff（Scripts/ 与 docs/ 不入 tuist 登记面；
  零新测试文件 → 无需 tuist generate，L041 不触发）。
- `LightamerSidecar.swift` 零 diff（schemaVersion 零触）；`Pipe/History/`
  + `PipeCacheKey.swift` + V50Order 零触；MCP 快照族零 diff
  （McpLauncherPanelView 调用点零触碰——rider 只动目录）；Export 六
  格式矩阵三文件（`ExportFormatSpec`/`ImageIOEncoders`/`WebPEncoder`）
  零 diff。
- UserDefaults 零新键；`\.runModal(` App/Sources 零命中；
  `String.LocalizationValue("` 插值禁形零命中。
- `*.xcstrings` **除 N-1 三键尾块纯插入外零 diff**（SC6）；
  `uv run python3 Scripts/zh-audit.py --check` PASS（含 V16 断言 5
  ABSENT 零命中——N-1 三键转绿后 27 键全 PRESENT）。
- 工作树零新增 untracked 源文件；既有三 untracked 兄弟件
  （`M3-1-ACCEPTANCE-PI.md` / `retro-dual/backfill-pi.zsh` /
  `research/dt-clone-archive/`）零触碰零入库。
- survey 正本（`ALCEDO-FEATURE-MAP.md`）正文 330 行零改写（diff =
  纯插入指针段）。

## 风险与回退

- R1 条目规模失控 → 域内合并粒度（CONTEXT §6 预案）；>160 行停手
  复盘粒度约定再续。
- R2 状态判定争议 → 账面优先序 + Missing 保守侧；争议行进 DECISIONS
  台账，验收/晨审可翻。
- R3 双树态 → self-test 公开树分支例强制（T2 AC）；A4/A5 skip 分支
  报告显式注记（禁静默 skip）。
- R4 ci.yml 回归 → 纯 additive diff 审计；YAML 本地校验 + CI 首跑
  兜底（CONTEXT §6 R4）。
- R5 N-1 键值措辞 → 与既有裸键同文纪律；`--check` PASS 为门，措辞
  争议留走查。
- R6 --all 异常 → 停手上报（fail / ΔN≠0 / 段和≠TOTAL 三态任一）；
  贴线 bundle 连续 MEMFAIL 先查重测顺序漂移（AGENTS ±3% 口径）；
  批准不达时零 diff 论证作 documented fallback 落 DECISIONS（D8）。
- 全套轮窗外 fail = 既有缺陷，停手上报不静默修（本批批内窗 =
  `docs/` + `Scripts/parity-audit.py` + ci.yml + xcstrings + `.work/`
  账面五正本，全非测试消费面）。
