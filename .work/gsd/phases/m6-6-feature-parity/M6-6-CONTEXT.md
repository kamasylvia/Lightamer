---
phase: M6-6
slug: feature-parity
created: 2026-10-16
kind: research+plan 合批（规划 worker）
status: drafted
---

# M6-6 — FEATURE-MAP ID 化 + CI 对账门 + M6 VALIDATION 收口 CONTEXT（范围落定 + 关键裁定）

> **夜间全自动授权头注**：本规划批在夜间全自动授权链内执行（先例
> D-07-3-T5-1——用户显式「开跑，不要停」续指令 = 规划与执行授权；
> M2-8..M6-5 各 VALIDATION 同款沿用）。**晨审可推翻**：推翻 = 本件裁定
> 作废回退，盘点证据不受影响。范围红线：瘦身手术第二次触发不在 M6
> （主会话专属）；ALCE-02（EXR）维持 V2；零新 SPM。
>
> **输入正本（逐一读齐，禁凭记忆转述）**：`.work/TODO.md` Milestone 6
> 头部 + M6-6 条；`.work/gsd/ROADMAP.md` §Milestone 6（M6-6 行 + 边界
> 纪律节）；`.work/gsd/research/LIGHTCRAFT-NOTES.md`（裁决⑥正本 =
> §二面 9「量化对标方法论」+ §三候选 #4 + §六裁决记录）；`.work/gsd/
> research/ALCEDO-FEATURE-MAP.md`（330 行 survey 正本，HEAD 亲读）；
> `.work/gsd/REQUIREMENTS.md` M6INT 族（M6INT-04 = 本 phase 登记条）；
> `.github/workflows/ci.yml`（113 行亲读）；`Scripts/zh-audit.py`
> （CLI 形态亲读——`--report/--check/--self-test` 三模式 + uv 红线）；
> `phases/m6-5-ledger-clearing/M6-5-VALIDATION.md`（挂账单一清单六项
> + 移交语言「移交 M6-6 收口批、GUI 批与晨审」〔:270 汇总句——逐项
> 处置以挂账清单本体为准，N-1 项级原文 = :124「下一清算批候选」，
> 见 D7②〕）；`.work/gsd/STATE.md`
> （M6 Ledger 6/7 正本）；LightCraft 本地仓对照
> `/Volumes/UNITEK/Documents/Development/lightcraft`（`docs/gaps.md` 排名
> 清单 + `docs/parity-checklist.md` 逐条 ID 表 + `xtask/src/parity.rs`
> CI 门实现——方法论正本，零代码移植）。
> **树事实核查均为 2026-10-16 工作树 HEAD 亲核**（`git remote -v` /
> `.gitignore` / repo 根结构 / `git status` 三 untracked 兄弟件）。

---

## §1 范围落定

**入范围（本 phase 全部交付面）**：

1. **FEATURE-MAP ID 化**——`research/ALCEDO-FEATURE-MAP.md`（Alcedo 对标
   survey 正本，330 行，无 ID 体系）升维为逐条 stable-ID parity 清单。
   形态裁定见 §2 D1/D2：对账正本 = **新建 `docs/parity-checklist.md`
   （repo 树内、CI 可见）**；survey 原文保留 + 头注指针。条目盘点覆盖
   survey §1-§8 全功能面（UI 骨架 / 图库 / 编辑器 / 调整目录 18 件 /
   Develop / Geometry / 节点图 / 蒙版 / DRT / 项目模型 / 导出 / AI /
   设置页）+ §10 映射表行 + LightCraft 派生已交付件（M6 四裁决件）+
   Lightamer 独有面（OWN 域）。预估 **120-140 行**（§3 域级概算）。
   状态判定**以账面 Delivered 记录为准，不重跑验收**（证据源优先序 =
   REQUIREMENTS Delivered 标记 → STATE 各 Milestone Ledger 终态列 →
   phase VALIDATION 签核件 → AGENTS 架构增量节登记）。
2. **CI 对账门**——`Scripts/parity-audit.py`（`zh-audit.py` 同型：
   `--report / --check / --self-test` 三模式，stdlib-only）+
   `.github/workflows/ci.yml` 新增 `parity` job。门语义 =
   REQUIREMENTS M6INT-04 三机检（清单引用 id 必须存在 / id 唯一性 /
   状态词表）+ 行结构 + 证据路径存在性 + 引用链接性 + 生成块新鲜度
   （§2 D4 六断言）。CI 现状 = **已存在**（`ci.yml`：push main/PR/tag
   触发，build-and-test on macos-27 + release 两 job）——本批为
   **additive 接线**，非「无 CI 降级」形态（D4 申报）。
3. **首轮对账 gaps 报告**——T3 用 `--write` 生成 summary + gaps 两个
   标记块（LightCraft `parity:summary` 生成块同款），gaps 块 =
   Missing/V2/Parked/OOS + Partial 降序排名行；**首轮行数下限 ≥ 10**
   作为一次性 AC（不进常驻门——防未来全绿后门永久红，D5）。
4. **M6 milestone VALIDATION 收口**——`M6-6-VALIDATION.md` 兼承载
   （front-matter `milestone_closeout: M6`，M2-11/M4-3/M5-3 单文档收口
   先例）：M6-6 本 phase SC 三列对账 + **六 phase（M6-1..M6-5 + 本批）
   终态汇编 + 六裁决兑现表** + 全套 `--all` 终验轮（D8）+ **编排偏差
   登记落收口段**（裁决⑥「第一个 plan」原文——ROADMAP M6-6 行在案，
   收口段正式落位）+ **铭谢/边界节**（D9）+ M6 milestone 级挂账单一
   清单（§4）。
5. **五正本翻账**——ROADMAP（M6-6 行 ✅ + M6 milestone closed 头部）/
   REQUIREMENTS（M6INT-04 → Delivered validated）/ STATE（M6 Ledger
   7/7 + milestone closed）/ TODO（M6-6 [x] + M6 收官行）/
   GOAL-STATE（续接点）+ AGENTS「M6-6 架构增量」节（parity 门形态 +
   ID 体系登记 + 终值）。
6. **N-1 顺带清偿（rider）**——M6-5 挂账②：`McpLauncherPanelView.swift`
   :225/:242/:246 三插值键（`mcp_launcher_status_running/done_writes/
   exit_code`）补 `%lld` 目录变体（xcstrings 尾块纯插入，M6-5 T6 同款
   形）。M6-5 VALIDATION :124 原文 =「→ **下一清算批候选**」（未点名
   M6-6，评审 F3 勘误）——本批顺带清偿属**提前处置**（T4 VALIDATION
   挂账表引原文并显式登记该偏差，晨审可翻）；S 量级零风险，milestone
   收口前清掉一枚已知 zh 活体缺陷（D7）。

**不入范围（边界，随收口显式移交）**：

- **Manual-Only 19 行 GUI 走查**（M6-5 挂账④，`gui-acceptance/m6-5/
  MANIFEST.md`）——GUI 批性质，与 doc/机检收口批异质；随 M6 挂账单一
  清单移交下一 GUI 批（用户/orchestrator 安排）。
- **V17 门扩展**（M6-5 挂账③候选：zh-audit 覆盖 Text 族 + `String(`
  跨行族）——本批 parity 门是**新门**非 zh-audit 扩展；V17 保持候选
  登记，随收口移交机检硬化批。
- **smart albums / 挑片视图 / watched folders**（charter 裁决⑤挂账）、
  **SAM CoreML**（裁决⑦ V2）、**ALCE-02 EXR**（V2 原位）、**V2 九项 +
  留置五项**（V2-PROPOSAL §七）——全部随收口挂账清单移交
  V2/Maintenance 站（未立项态）。
- **零源码行为变更**：本批零 Swift 触碰（唯一库文件面 = N-1 rider 的
  xcstrings 三键）；`ΔN = 0`。

## §2 关键裁定（各带理由）

### D1 — 对账正本落 repo 树 `docs/parity-checklist.md`；survey 原地保留

**裁定**：ID 化 parity 清单落 **`docs/parity-checklist.md`**（repo 根
新建 `docs/`），**不是**原地改写 `research/ALCEDO-FEATURE-MAP.md`；
survey 文件只加一段头注指针（指向 checklist + FEAT id 体系），正文
330 行零改写。

**理由（树拓扑硬约束）**：GitHub 公开树（13-4 审计闸，pack 2.53MiB
压缩英文史）**排除 `.work/` 全目录**——`git push github` 后 CI checkout
看不见 `.work/gsd/research/` 下任何文件；对账门要挂 CI 就必须指 repo
树内文件（`.gitignore` 亲核：`.work/` 本体被跟踪，但公开树策略在 push
侧剥离；两 remote 在案 = ADO origin 私有 + github 公开）。反向理由：
survey 的 prose 价值（源码索引、勘误注记、上游增量测绘）不可压缩进
表格——保留双正本分工 = survey（研究正本，`.work/`）+ checklist（对账
正本，repo 树、CI 门控、全英文〔公开树纪律，13-4 先例〕）。漂移防线 =
checklist 是 FEAT id 唯一 mint 点，survey 永不新增 id。

### D2 — ID 体系：`FEAT-<DOM>-NN` + 三词表 + id 稳定不重编号

- **id 形**：`FEAT-<DOM>-NN`（NN = 域内两位序号，零填充；**id 稳定，
  永不重编号**——LightCraft 纪律「Ids are stable; never renumber」，
  废弃行保留 id + 状态标注，不回收号）。
- **DOM 词表（12 域）**：`SHELL`（工作区骨架/窗口/主题）/ `LIB`（图库
  与项目模型）/ `EDT`（编辑器骨架与面板）/ `ADJ`（调整目录 18 件 +
  Color Wheel + Look 分组）/ `DEV`（Develop/RAW Decode 面）/ `GEO`
  （Geometry）/ `NODE`（节点图模型）/ `MASK`（蒙版体系）/ `DRT`（显示
  渲染变换）/ `EXP`（导出）/ `AI`（AI 面）/ `OWN`（Lightamer 独有面：
  yiyin / MCP / FSIM / TRACK / Mertens / PANO / depth / 降噪族 / LUT 库）。
- **Source 词表**：`Alcedo | LightCraft | Lightamer`（行级来源——功能
  对标自 Alcedo / 语义移植自 LightCraft〔M6 四裁决件 + stacks/feather 等〕/
  自研独有）。
- **Status 词表（6 态）**：`Delivered | Partial | Missing | V2 | Parked |
  OOS`。任务书推荐五态（Delivered/Partial/Missing/V2/parked），
  **增设 `OOS` 为显式偏离申报**：存在结构性不可达/范围裁减项（Updates
  页〔2026-09-27 砍苹果渠道终裁〕、Nikon HE 恢复〔CIRAW 路线不可达〕）
  ——用 `Parked`（含重启条件语义）表达「暂时不做」会把「永不做」混进
  「等条件」；拆出 `OOS`（范围外，带裁决锚）两态各得其所。**EXR 导出
  归 `V2` 不归 OOS**（评审 F2 语义内部勘误：EXR 有重启条件 =
  V2-PROPOSAL OQ-V2-5 依赖对比再裁，属「等条件」非结构性不可达——
  锚 = ALCE-02 原位注记 + OQ-V2-5，与 §3 EXP 行「EXR→V2 行」同口径）。
  大小写统一（`parked` → `Parked`，词表机检需要精确匹配）。
- 状态判定证据规则：`Delivered` 行必须带 ≥1 证据指针；`Missing` 行必须
  带 note（缺什么一句话）；`V2` 行必须带 V2-PROPOSAL/REQUIREMENTS 锚；
  `Parked` 行必须带重启条件锚（如 IOP-MASK-06 先例）；`OOS` 行必须带
  裁决锚（charter/VALIDATION 行）。机检覆盖「非空 + 指针形」，锚内容
  人工走查（同 zh-audit spec 深检留人工的边界哲学）。

### D3 — 证据指针两级 + 公开树豁免规则

每行 Evidence 列承载 backtick 指针，两级：

- **`src:<repo-path>[:line]`** —— 代码证据（`LightamerCore/` `LightamerIOP/`
  `App/` `Tests/` `Scripts/` `Resources/` `Project.swift` `docs/` 下）。
  **存在性机检无条件执行**（含 `:line` ≤ 文件行数核验——LightCraft
  `parity.rs` 同款）；本地与 GitHub 公开树都存在。
- **`doc:<path>`** —— 流程证据（`.work/gsd/...` VALIDATION/REQUIREMENTS/
  RESEARCH 等）。**条件机检**：checkout 存在 `.work/` 根（本地真身）→
  存在性核验；`.work/` 不存在（GitHub 公开树）→ format-only + 报告
  注记「local-only evidence」。`.work/gui-acceptance/` 与
  `.work/gsd/phases/*/evidence/`（gitignored 证据域）**恒 format-only**
  （本地也不检——gitignored 面可能缺盘）。

理由：证据链要双向可用——本地批跑（red-line battery，`--check` 全量
机检）+ 公开 CI（树内面机检）。`.work/` 条件豁免让同一份 checklist
在两棵树都绿，不牺牲本地严格性。

### D4 — CI 对账门：`Scripts/parity-audit.py` + `parity` job（additive 接线）

- **脚本**：`Scripts/parity-audit.py`，stdlib-only，CLI 与 zh-audit.py
  同型（`--report` 人读 / `--check` 机检 exit 0|1 / `--self-test` golden
  红绿负测）+ `--write`（刷新生成块）+ `--checklist` 路径覆盖。本地
  运行守 uv 红线：`uv run python3 Scripts/parity-audit.py --check`。
- **六断言**（对应 M6INT-04「id 存在性/唯一性/状态词表机检」+ 批纪律
  扩展）：
  - **A1 行结构**：row 区每表行 6 列可解析、id 形合法
    （`FEAT-(SHELL|LIB|EDT|ADJ|DEV|GEO|NODE|MASK|DRT|EXP|AI|OWN)-\d{2}`）。
  - **A2 唯一性**：id 全局唯一。
  - **A3 词表**：Source ∈ 三词表、Status ∈ 六词表。
  - **A4 存在性**：`src:` 指针无条件存在性 + `:line` 界核验；`doc:`
    按 D3 条件机检。
  - **A5 引用链接性**：`REQUIREMENTS.md` / `ROADMAP.md` / `AGENTS.md`
    中被引用的 `FEAT-*` id 必须在 checklist 在册（文件缺省 = 公开树，
    graceful skip）——「清单引用 id 必须存在」的反向面：账面引用不悬空。
  - **A6 生成块新鲜度**：summary/gaps 两标记块在位且与内存重算一致
    （漂移 = 「stale, run --write」违规）——确定性纪律同 zh-audit
    self-test。
- **CI 接线**：`.github/workflows/ci.yml` 新增独立 `parity` job
  （`ubuntu-latest`，`python3 Scripts/parity-audit.py --check`，
  timeout 5min）——纯 doc 检查秒级完成，**不占 macos-27 runner、不阻塞
  build-and-test**；触发面沿用既有 `on:`（push main/PR/tag/dispatch——
  评审 F9 注记：`on:` 实含 `tags: ['v*']`，tag push 也会跑 parity
  job，无害）。
- **CI 有效性申报（非降级）**：CI 存在且本批 additive 接线落地；因
  项目处于 local-only push 态（STATE Notes 在案），**本批门的实质验收 =
  本地 `--check` PASS + job 定义在树**；CI 在线跑绿随下次 push 兑现
  （13-4「CI 首跑观测」遗留同族）。任务书预判的「无 CI 则脚本 + 手册门
  降级」**不触发**——ci.yml 在案。

### D5 — gaps 报告：生成块形态 + 一次性行数下限

gaps 报告 = `docs/parity-checklist.md` 内 `<!-- parity:gaps -->` 标记块
（`--write` 刷新，与 `<!-- parity:summary -->` 块同机制），行序 =
Missing → V2 → Parked → OOS → Partial（同域内按域码字母序；LightCraft
gaps.md「按用户影响排名」的简化形——我方无 Lightroom 级用户影响标定
数据，先用状态严重度排序，排名细化挂 V2 候选注记）。**首轮 gaps 块
行数 ≥ 10 = T3 一次性 AC**（transcript 记 SUMMARY）；常驻门只检块
存在 + 新鲜度（A6），**不检行数下限**——未来 parity 全绿时块可以合法
缩到 0 行，门不因此红。

### D6 — M6 milestone VALIDATION 收口 = 本 phase VALIDATION 兼承载

`M6-6-VALIDATION.md` front-matter 加 `milestone_closeout: M6`（M2-11 /
M4-3 / M5-3 单文档收口先例——不另立 milestone 汇总文档）。收口内容 =
§1.4 列五件。六裁决兑现表逐行：①MCP-09-A → M6-1 / ②ALCE-03 → M6-3 /
③process version → M6-2 / ④AI 分割 spike → M6-4-02 / ⑤stacks →
M6-4-01 / ⑥FEATURE-MAP + CI 门 → **本批**。**编排偏差登记落收口段**：
裁决⑥原文「作为 M6 对标里程碑的第一个 plan」被互操作先行编排取代
（ROADMAP M6-6 行在案「flippable at morning review」），收口段正式
落位申报。

### D7 — M6-5 挂账单一清单六项的 M6-6 处置（逐项，禁静默）

| # | 挂账项 | M6-6 处置 |
|---|---|---|
| ① | minor-1 勘误正本 | **已落**（M6-5 闭环批 VALIDATION §挂账①）——零动作 |
| ② | N-1 三插值键 → 下一清算批 | **顺带清偿（提前清偿偏差，晨审可翻）**（本批 T2 rider：三键 `%lld` 变体尾块纯插入；M6-5 VALIDATION :124 原文 =「→ **下一清算批候选**」，未点名 M6-6〔评审 F3 勘误：旧稿「移交语言点名 M6-6 收口批」系误引〕——本批先行清偿属提前处置，T4 VALIDATION 挂账表引原文并显式登记该偏差；milestone 收口前清一枚已知 zh 活体） |
| ③ | N-2 V16 门覆盖限定 + V17 候选 | 限定语**已落**（AGENTS M6-5 节）；V17 门扩展**不入本批**（新门 ≠ zh-audit 扩展；候选登记随收口移交机检硬化批） |
| ④ | Manual-Only 19 行 → 下一 GUI 批 | **不入本批**（GUI 批性质；随 M6 挂账单一清单显式移交，配方在 `gui-acceptance/m6-5/MANIFEST.md`） |
| ⑤ | V2 九项 + 留置五项指针 | **随收口移交** V2/Maintenance 站（V2-PROPOSAL §七登记 ≠ 立项正本不动） |
| ⑥ | M6-4 推算核销声明 | **已落**（对账链闭合，基线 = 3848 实测）——零动作 |

### D8 — 全套 `--all` 确认轮（T4 内，批准制 + 8G 门）

M6 milestone 终值须实测戳（M2-11 2961 / M3 3174 / M5 3631 先例——
milestone 终值 = 收口 phase 实测轮，非推算承继）。**预期
`TOTAL|3848/24/0|`、ΔN = 0**（本批零 Swift 测试面；对账基线 = M6-5
三路实测 3848）。命令序 **`xcodebuild build-for-testing` → `caffeinate
-dis Scripts/test-direct.sh --all`**（**build-for-testing 前置硬性**——
M6-5 I-1 陈旧二进制假绿教训入册；夜间授权链 = 批准在案，运行中监视
8G 门 + MEMFAIL，异常立即 kill）。任何 fail / ΔN≠0 / 段和≠TOTAL →
停手上报，不静默修、不静默过。零 diff 论证（M4-3 targeted 收口先例）
作为批准不达时的 documented fallback 落 DECISIONS，不替代实测。

### D9 — 铭谢/边界节（收口段组成）

- **铭谢**：量化对标方法论（gaps 排名 + parity-checklist 逐条 ID + CI
  门）借自 **LightCraft**（`storytold/lightcraft`，MIT OR Apache-2.0）。
  本批**零代码移植**（方法论/形态借鉴 + `parity.rs` 行为语义对照）——
  **无 NOTICE 义务**（成段代码移植才触发，charter 边界在案）；铭谢
  注记 + 仓库指针落收口段与 checklist 头注（公开树可见的致谢，与
  `third_party_licenses/` 既有纪律同向）。
- **边界**：M6 未做面显式汇编（§1 边界清单全量）——防「milestone
  closed = 全做完」误读；ALCE-02 / SAM CoreML / smart albums 族 /
  Manual-Only 19 行 / V17 / V2 九项 + 留置五项 / 瘦身手术（主会话
  专属）逐项带锚。

## §3 FEATURE-MAP 条目盘点概要（域级，T1 展开为行）

| 域 | survey 来源节 | 预估行数 | 状态判定主锚 |
|---|---|---:|---|
| SHELL | §1.1 + §1.4 | 5-7 | M2-3（UI shell redesign）VALIDATION 链 |
| LIB | §1.2 + §6 | 14-18 | M2-2 / M2-8 / M6-1 / M6-4 面 A（stacks）|
| EDT | §1.3 | 14-16 | M2-3 / M2-4（节点编辑）/ M2-8 / M3 系面板 |
| ADJ | §2（18 件目录 + CW + Look 分组） | 20-22 | M2-5 M2GRADE 全 Delivered + GradeCatalog |
| DEV | §2.4 | 6-8 | M4-1（raster 路由）/ CIRAW 边界（STACK.md 不可达项 → OOS 带 STACK 锚）|
| GEO | §2.5 | 3-4 | Phase 4 / M2 系 |
| NODE | §3 | 6-8 | M2-4 node model + M2-8 versions + Copy Adjustments |
| MASK | §4 | 8-10 | M2-7 M2MASK + M4-3 depth + M6-4-02 spike |
| DRT | §5 | 8-10 | M2-6 M2DRT 全 Delivered + M3 FSIM 域判别 |
| EXP | §7 | 10-12 | M2-9 M2EXP + M6-3 ALCE-03 + M2-9 挂账残留（EXR→V2 行）|
| AI | §8 | 8-10 | M2-10 M2AI 全 Delivered + M2-7 蒙版族 |
| OWN | §9/§10 反向 + M3/M5 交付 | 9-12 | REQUIREMENTS FSIM/TRACK/IOP-HDR-06/IOP-PANO-01/IOP-MASK-07 + Phase 8/14 |
| **合计** | | **~111-147** | 目标带 120-140；「条目盘点要全」以 survey 功能面零遗漏为准绳，行数带为估算非门 |

Row 措辞纪律：**我方语言转写，零 Alcedo prose 复制**（GPL-3.0 只读
红线——survey 已是事实级转写，checklist 行更短：功能名 + 一句话 +
指针；参数值/路径属事实不受限）。dt-gap 表（§9）不入 checklist 行
（dt 独有项是 Lightamer 面非 Alcedo parity 面）——OWN 域已覆盖其
交付子集。

## §4 M6 milestone 挂账单一清单（T4 收口段的移交正本，T5 落五正本时引用）

1. **Manual-Only 19 行 GUI 走查** → 下一 GUI 批（配方 =
   `gui-acceptance/m6-5/MANIFEST.md` + m6-4 MANIFEST 前置供件）。
2. **V17 zh-audit 门扩展候选**（Text 族 + `String(` 跨行族）→ 机检
   硬化批。
3. **V2 九项**（V2-PROPOSAL §七，登记 ≠ 立项）+ **留置五项** →
   V2/Maintenance 站。
4. **charter 裁决挂账**：smart albums（次之）/ 挑片视图 / watched
   folders（裁决⑤不立项部分）/ SAM CoreML（裁决⑦ V2）/ ALCE-02
   EXR（V2 原位）。
5. **编排偏差登记**（裁决⑥「第一个 plan」→ 收口段正式落位，晨审/
   用户可随时追认或推翻）。
6. **瘦身手术第二次触发**（主会话专属，GOAL-STATE 队列行原序保留——
   M6 closed 后触发确认态）。

## §5 SC 汇总（机检形，plan front-matter 镜像）

- SC1 `uv run python3 Scripts/parity-audit.py --check` exit 0（A1-A6
  零违规；id 唯一性在内）。
- SC2 `--self-test` PASS（红绿 golden：坏 id 形 / 重复 id / 非法状态 /
  缺失 src 路径各 ≥1 红例 + 1 净例）。
- SC3 首轮 gaps 块行数 ≥ 10（T3 transcript 记 SUMMARY）。
- SC4 `.github/workflows/ci.yml` 含 `parity` job；裸 `python3
  Scripts/parity-audit.py --check`（CI 形态）本地亦 PASS。
- SC5 全套 `--all` `TOTAL|3848/24/0|`（ΔN=0；异常停手上报）。
- SC6 xcstrings diff = 恰 N-1 三键尾块纯插入（rider 采纳时）。

## §6 风险与预案

- **R1 条目规模失控**（>150 行）：域内允许合并粒度（「设置页九页」可
  并 2-3 行）——盘点准绳 = survey 功能面零遗漏，行数带非门；checklist
  头注申报粒度约定。
- **R2 状态判定争议**（Partial vs Delivered 边界）：判定序 = 账面
  Delivered 记录优先（不重跑验收）；账面沉默面（Activity view 类）→
  Missing 保守侧 + note，验收批/晨审可翻。
- **R3 公开树 vs 本地树双态**：A4/A5 的条件豁免规则（D3）是唯一跨树
  缝——self-test 必须覆盖「`.work/` 缺席」分支（fixture 模拟公开树），
  防门只在本地绿。
- **R4 ci.yml 编辑回归**：只加 job 块不动既有两 job（diff 审计 =
  纯 additive）；YAML 层面本地 `python3 -c "import yaml,sys;
  yaml.safe_load(open('.github/workflows/ci.yml'))"` 校验（stdlib 无
  pyyaml 时以缩进目检 + CI 首跑兜底）。
- **R5 N-1 rider 键值措辞**：三键 `%lld` 变体 en+zh 值与既有裸键同文
  （M6-5 T6 三键同款先例）——zh-audit `--check` PASS 为门，措辞争议
  留走查。
- **R6 --all 贴线 bundle**（IOP/IOPParity ±3% 方差带，AGENTS 在案）：
  零 IOP 触碰批，连续 MEMFAIL 先查重测顺序漂移；8G 门 + 监视纪律照旧。
