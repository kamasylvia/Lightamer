# `.work/` — Lightamer 开发流程中枢

> 本目录承载 GSD 自动化流水线的**全部状态、账本与证据**。
> 新会话 / 巡检恢复的**唯一入口 = `GOAL-STATE.md` 续接点**（文件头第一段 ✅ 行）。
> 本 README 只做地图与索引；一切状态判定以 §3 各正本为准，此处数字仅作导览。

---

## 1. 目录架构

```
.work/
├── README.md               # 本文：地图 + 流程索引 + 残渣清单
├── config.toml             # 流水线开关与阵容配置（唯一可执行配置）
│   ├── [gsd]               #   auto（自动流转）/ paused（全链暂停）——消费方每任务边界必读
│   ├── [matrix.vibe.*]     #   执行档 roster（slot 分窗；23:00-09:00 全 subagents）
│   └── [matrix.review.*]   #   复审档阈值（min_valid_lanes=4 / min_votes=2 / clean_streak_close=3 等）
├── GOAL-STATE.md           # ★ 续接点正本 + 巡检指令 + 阻塞登记 + Flaky 台账（追加式，每批一条 ✅ 行）
├── GSD-PROGRESS.log        # 巡检/worker 动作流水账（[时间] 动作 → 结果，一行一事）
├── TODO.md                 # 面向人的进度镜像（镜像 ROADMAP；阶段进度以 STATE.md 为准）
├── LESSONS.md              # L001.. 经验教训账（背景→现象→根因→对策→适用；被各文件以 L0xx 引用）
├── gsd/                    # GSD 规划与证据主库（2.8G）
│   ├── PROJECT.md          #   项目定义（经 GSD 块注入根 AGENTS.md）
│   ├── ROADMAP.md          #   阶段路线图（M1 历史 / M2 全账 / M3 活跃站）
│   ├── REQUIREMENTS.md     #   ★ 需求真值（家族条目 + Delivered 翻账）
│   ├── STATE.md            #   ★ phase 账（front-matter + Completion Ledger，唯一阶段进度判据）
│   ├── config.json         #   gsd-tools 工作流配置（checker/verifier/git 策略）
│   ├── research/           #   研究正本（STACK/FEATURES/ARCHITECTURE/PITFALLS/SUMMARY
│   │                       #   + ALCEDO-FEATURE-MAP（V1 测绘锚）+ LUMEN/SPEKTRALAB/RAWMAKASE 笔记
│   │                       #   + dt-clone-archive/ 归档）
│   ├── spikes/             #   Spike A（CIRAW9 边界）/ Spike B（100MP 性能）探针与报告
│   ├── artifacts/          #   跨 phase 共享产物（现仅 fixtures/ 测试夹具会话目录）
│   └── phases/<slug>/      #   ★ 每 phase 一目录的完整证据链（见 §2.1）
├── gui-acceptance/         # 真机走查截图证据（553M；根级散图 = M1 时代，
│                           #   子目录 m2-*/fix-batch/reverify-* = M2 时代，各含 MANIFEST.md）
├── matrix/                 # 多路复审存档（05-05-r1 一轮；细则正本 = skills/matrix/SKILL.md + config.toml）
├── debug-flaky/            # [gitignored] flaky 探针残渣（2026-09-26，调查已收口）
└── tmp-public/             # [gitignored] 公开仓抽取 scratch（2026-09-27/28；repo/ 自带独立 .git）
```

仓库根的 `.planning -> .work/gsd` 符号链接是 gsd-tools 兼容垫片（不入 git）；git pathspec 一律用 `.work/gsd/` 真路径。

## 2. 开发流程怎么跑

### 2.1 一个 phase 的生命周期（GSD 循环全链）

```
discuss/research          phases/<slug>/<N>-CONTEXT.md + RESEARCH-NOTES.md 落盘
   │
   ▼
【C 档第 1 停】            research 定稿后停：OQ 清单交用户裁决（先例：OQ-V2-1..10「按推荐」预裁）
   │
   ▼
plan + checker            <N>-PLAN.md 逐波落盘 → plan-checker 机检 → 修复回注
   │
   ▼
execute                   omp / subagent worker（夜间 23:00-09:00 全 subagents）；
   │                      任务级 commit（T1..Tn + T6 收口 SUMMARY/DECISIONS，Conventional Commits）
   ▼
独立验收                  ZCode subagent 零共享上下文：AC 逐条核对 + 复跑测试对账；
   │                      <N>-ACCEPTANCE.md 落盘
   ▼
【C 档第 2 停】            每 plan 执行+验收闭环后停：汇报该 plan 战果 + 下一 plan 摘要，等「继续」
   │
   ▼            （多 plan phase 循环上面四步）
phase VALIDATION          verify-work 签核：<PHASE>-VALIDATION-INPUT.md（对账输入）
   │                      → <PHASE>-VALIDATION.md（status: validated + nyquist_compliant: true）
   ▼
【C 档第 3 停】            签核前停，结论给用户过目。
   │                      夜间授权先例 D-07-3-T5-1 + 用户「开跑，不要停」→ 可落盘即签核，晨审可推翻
   ▼
翻账批（五正本同批）       STATE.md 翻 complete + ROADMAP ✅ + REQUIREMENTS 翻 Delivered
                          + TODO 落账 + GOAL-STATE 追加续接点；GSD-PROGRESS.log 追加行
```

phase 证据链目录惯例（M2 时代定式）：

```
gsd/phases/<slug>/
├── <slug>-CONTEXT.md            # discuss 产物：OQ + 直接裁决项
├── RESEARCH-NOTES.md            # research 产物（file:line 实测）
├── <N>-PLAN.md / -SUMMARY.md    # 每 plan 一对（N = 波次号）
├── <N>-DECISIONS.md             # 执行期决策 + 偏差申报（回注 planner 项也在内）
├── <N>-ACCEPTANCE.md            # 独立验收报告（PASS / N error + N minor 头）
├── <slug>-CHECKER.md            # plan-checker 机检账
├── <slug>-VALIDATION-INPUT.md   # 签核对账输入（SC 三列对账正本）
├── <slug>-VALIDATION.md         # 签核正本（M2-11 兼 milestone 收口）
├── perf.md                      # phase 级性能账本（数字正本，落在 slug 根）
└── evidence/<plan-id>/          # plan 执行证据（探针/日志/截图）
```

### 2.2 测试与运行门（七 bundle）

- **唯一标准命令** = `Scripts/test-direct.sh`（直启宿主，绕开 testmanagerd，L019b 配方）。
- **七域 bundle**：`IOP / IOPParity / Layers / Library / Sessions / Export / App`（共享同一宿主二进制，串行各起独立进程）。归属正本 = `.work/gsd/phases/m2-4-0-test-bundles/M2-4-0-BUNDLE-MAP.txt`（新测试文件同 commit 登记，`tuist generate` 恒为该批最后动作，L041）。
- **运行门 = 8G**（`RSS_LIMIT_MB=8192`，ru_maxrss 内核口径机检 MEMFAIL）。原 <3G 门经 SPIKE（`70e09e5`）证伪：GB 级峰值 = by-design 重测瞬态 + ~1.4G 框架分页地板，证据 = `M2-4-0-SPIKE.md`。
- **全套 `--all` 轮须 orchestrator 批准 + 运行中保持监视**；定向 `--bundle <name>` 轮可常跑（机检兜底）。
- **L055 判据**（防崩溃假绿）：读数先核各 bundle 段「末条 Executed 是否 `All tests` 总计行 + passed 数与 BUNDLE 行一致」；`terminated abnormally` / `Restarting after unexpected exit` 签名 = bundle FAIL 计数置零。脚本已内置 crash / no-total-line / MEMFAIL / ANE-DEGRADED 四 verdict 机检 + `LA_SELFTEST=1` 自证。

### 2.3 测试基线演进（M2 时代锚点；M1 历史 36→…→1881 见 `STATE.md` Completion Ledger）

| 终值 | Phase | 锚点 |
|---|---|---|
| 2165 | M2-4-0 七 bundle 拆分基线 | 拆分批 `eca777c`/`281bda9`/`46bf1c7` |
| 2240 | M2-4 node model | `M2-4-ACCEPTANCE.md` |
| 2327 | M2-5 color grade | `STATE.md` 账 |
| 2464 | M2-6 DRT | `STATE.md` 账 |
| 2525 | M2-7 masks | `STATE.md` 账 |
| 2577 | M2-8 versions | `M2-8-VALIDATION.md`（修复锚 `e9c03af`/`4e7fc58`） |
| 2693 | M2-9 export | `M2-9-VALIDATION.md`（验收批 `afb1f88`） |
| 2955 | M2-10 AI library | `M2-10-VALIDATION.md`（翻账 `de68703`） |
| **2961** | **M2-11 performance + M2 收口** | **`M2-11-VALIDATION.md`（签核 `3f91221`/终审 `80f778f`，TOTAL\|2961/16/0\|1081s）** |

skip 恒 16 零新增为 M2 后期纪律；对账链逐波独立验收背书，正本 = `STATE.md`。

### 2.4 保活巡检与停滞恢复

- 巡检（cron，约 30min）正本指令 = `GOAL-STATE.md`：**读本文件 → 执行队列第一项 → 更新本文件 → commit**（当前纪律：本地 commit 即完成态，**默认不 push**，推送由用户/orchestrator 决定）。
- 每轮附带资源监控：`ps aux | grep -i lightamer`；GUI app 内存 >3G 或 CPU 持续异常 → `sample <pid> 3` 采栈上报；测试宿主 >8G 或内存压力红 → 立即 kill。
- **停滞恢复硬规则**：巡检时 `git log` 最近 commit >6h 且无在飞 worker 证据（phases 产物 mtime / GOAL-STATE 在飞登记）→ 判停滞，按续接点续班（先例：M2-10-07 前任 worker 死亡后续班，D16 续班事实节）。
- 在飞判定后**不重复派遣同一 plan**；修复批与主线波次维持 owned 面隔离纪律（派遣前复核 `git log`/GOAL-STATE）。

### 2.5 暂停 / 恢复开关（`.work/config.toml [gsd]`）

| 字段 | 语义 |
|---|---|
| `paused = true` | 全链路停：巡检不推进、worker 任务边界干净停（在制品 commit 后停）、不派新验收 |
| `auto = false` | 自动流转关：worker 完成当前波后停等用户「继续」（计划性门控） |

恢复 = 用户把字段改回。C 档三停（§2.1）独立于此开关始终生效；PAUSE 语义的兜底即 `paused` 字段。

### 2.6 提交纪律（摘要）

- Conventional Commits，任务级小步 commit（executor 每任务一笔，只 add 相关文件，禁 `git add -A`）。
- commit message 全英文；docs 批须说明同步更新了哪些 md（§3.1 一致性门）。
- 不直写 STATE.md/ROADMAP.md（用 gsd-tools verb）；GOAL-STATE/LESSONS/GSD-PROGRESS 一律追加式。

## 3. 关键正本指针（防双状态源）

| 问题 | 唯一去看的地方 |
|---|---|
| 现在推进到哪、下一步干什么 | `.work/GOAL-STATE.md` 续接点（文件头最新 ✅ 行） |
| 流水线开没开 / 阵容 | `.work/config.toml` `[gsd]` + `[matrix.*]` |
| 某需求交付没有 | `.work/gsd/REQUIREMENTS.md`（家族条目 + Delivered 翻账） |
| 某 phase 状态 / 终值测试数 | `.work/gsd/STATE.md`（Completion Ledger） |
| 某 phase 怎么做出来的 | `.work/gsd/phases/<slug>/` 全套证据链（§2.1 惯例） |
| 架构现状 / 依赖 / 键族登记 | 根 `AGENTS.md`（各 milestone 架构增量节 = 约定正本） |
| 性能数字 | 各 phase `perf.md`（当前 = `phases/m2-11-performance/perf.md`） |
| M2 里程碑收口 | `phases/m2-11-performance/M2-11-VALIDATION.md`（兼收口正本，OQ-8-A 单文档制） |
| 踩过的坑 | `.work/LESSONS.md`（L0xx 编号被全仓引用） |
| 走查证据 | `.work/gui-acceptance/<phase-or-batch>/`（MANIFEST.md 逐行索引） |

## 4. 挂账入口（要找「还没做的事」）

1. **单一清单** = `gsd/phases/m2-11-performance/M2-11-VALIDATION-INPUT.md` §4.4——M2 挂账总汇编（Maintenance 栏 M1-M7 + V2/观察项栏 V1-V17），各 phase 原文不改写、只在此汇编。
2. **GOAL-STATE 挂账节**：各续接点行内「挂账/移交」段 + Flaky 台账（追加行）。
3. 各 phase `*-VALIDATION.md` 挂账节保留原文（历史账，不删不改写）。

## 5. 孤儿/残渣清单（2026-10-07 普查；**只列不删**，处置需用户裁决）

| # | 路径 | 判断依据 |
|---|---|---|
| O1 | `.work/tmp-public/`（46M，gitignored） | 公开仓抽取 scratch（2026-09-27/28）：`messages/`+`tree/`+`repo/`（repo 自带独立 `.git`）。gitignore 注记「local-only scratch」。使命已完成即残渣；注意有会话以 `tmp-public/repo` 为 cwd 复用作 scratch，清除前须确认无在飞引用 |
| O2 | `.work/debug-flaky/`（464K，gitignored） | 2026-09-26 flaky 探针（`probe*.raw/png`）。调查已收口（flake 台账五波终态环境型归因，M2-10-07 收口），GOAL-STATE/LESSONS 零引用 → 残渣 |
| O3 | `.work/.DS_Store` 及各级同名义件 | Finder 垃圾（gitignore 已全局忽略，不入库）；仅观感问题 |
| O4 | `.work/gui-acceptance/09-3-tiers-{raf,arw,nef}-A-vs-B.jpg` | 9-3 D10 抽检**再生成物**（复跑必 dirty）：raf 一张已被 gitignore 钉；arw/nef 两张现为 working-tree 脏文件，GOAL-STATE 已登记「存量脏两 jpg 不入修复批」——保留在案，勿手工"修复" |
| O5 | `TODO.md` Phase 7 节引用 `.work/gsd/artifacts/07/perf.md` | **断链**（目录不存在）。2026-09-27 目录整并后现位 = `.work/gsd/phases/07-ai-modules/perf.md`。TODO 属历史账按追加式纪律不改写，此处登记正确落点 |
| O6 | `.work/matrix/`（仅 `05-05-r1/review/TASK.md`，4K） | 非残渣但近乎闲置：多路复审自 2026-09-22 起改走串行单验收路（config.toml [matrix.review] 仍为阵容/阈值正本）。保留 |

**不列入清理的易混淆项**：working tree 中 61 个 .work 未跟踪/已修改文件（`gsd/phases/m3-1-w1/*`、`gsd/research/dt-clone-archive/`、REQUIREMENTS.md、BUNDLE-MAP.txt、散张走查截图）= **在飞工作产物**（M3-1 worker + 修复批），归属各在飞批的收口 commit，禁止他人代提交。
