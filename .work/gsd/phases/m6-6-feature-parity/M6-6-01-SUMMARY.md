---
phase: m6-6
plan: "M6-6-01"
kind: plan-summary
created: 2026-10-16
executor: zcode subagent（夜间全自动授权链，先例 D-07-3-T5-1）
status: executed
---

# M6-6-01 SUMMARY — FEATURE-MAP ID 化 + CI 对账门 + 首轮对账 + M6 收口

> 单 plan 三合一（对账基建 + 首轮对账 + milestone 收口）。执行链
> `93a674c8..3c7498bc` + 收口批两笔（本 SUMMARY/DECISIONS/VALIDATION +
> T5 翻账）。零 Swift 触碰（唯一库文件面 = N-1 rider xcstrings 三键）；
> ΔN = 0 纪律全程维持。

## 逐任务记账

| # | 任务 | 交付 | commit | 状态 |
|---|---|---|---|---|
| T1 | FEAT-ID parity 清单落 repo 树 | `docs/parity-checklist.md`（280 行，134 rows / 12 域 / 六状态词表 / 双生成块占位 / 头注五纪律）+ survey 头注指针（additive 7 行，正文 330 行零改写） | `93a674c8` | ✅ |
| T2a | `Scripts/parity-audit.py` 六断言门 + CI parity job | stdlib-only 六断言（A1 结构+A1b 12 域节标题 / A2 唯一 / A3 词表+D2 规则 / A4 存在性 / A5 引用链接 / A6 新鲜度两态）+ `--check/--report/--write/--self-test` + `--checklist`/`--tree-root` 注入缝；ci.yml 尾部纯追加 parity job（ubuntu-latest / 5min / 裸 python3） | `a515b3ff` | ✅ |
| T2b | N-1 rider 三插值键 | `mcp_launcher_(done_writes\|exit_code\|status_running) %lld` 尾块纯插入（51+/0- 单 hunk），en+zh 与裸键格式串同文；调用点零触碰 | `d63cf79c` | ✅ |
| T3 | 首轮对账 | `--write` 填充 summary（12 域×6 态矩阵）+ gaps（17 行，Missing→V2→Parked→OOS→Partial 序）；`--check` 复跑 PASS | `3c7498bc` | ✅ |
| T4 | 全套确认轮 + 三正本 | build-for-testing → `caffeinate -dis Scripts/test-direct.sh --all`（终值见 §全套终验）+ 本 SUMMARY + DECISIONS + `M6-6-VALIDATION.md`（milestone_closeout: M6） | 本批 | ✅ |
| T5 | 五正本翻账 + AGENTS 增量节 | ROADMAP / REQUIREMENTS / STATE / TODO / GOAL-STATE + AGENTS「M6-6 架构增量」节 + CONTEXT §5/§6 两条 minor 镜像同步 | 收口批 | ✅ |

## 执行期事件（T4 全套前置）

- **build-for-testing 首轮 ValidateEmbeddedBinary 失败（环境签名债，非源码）**：
  两个 appex（LightamerSpotlight / LightamerQuickLook）在 DerivedData 中
  残留 2026-10-15 "Lightamer Dev" CMS 签名，与父 app 的 ad-hoc 签名不匹
  配（`ValidateEmbeddedBinary` 报 Embedded=Lightamer Dev / Parent=Ad Hoc）。
  与 perf.md §事故 4 / D-09-04-D9 重签环境债同族。处置 = 两 appex 盘上
  `codesign --force --sign -` 强制 ad-hoc 重签（Signature=adhoc 亲证）→
  增量重跑 build-for-testing 通过。零源码触碰、零 Project.swift diff。
  教训登记 LESSONS（L081）。

## SC1-SC6 逐条实测

| SC | 判据 | 实测 | 结论 |
|---|---|---|---|
| SC1 | `uv run python3 Scripts/parity-audit.py --check` exit 0 | `parity-audit --check PASS (134 rows, id-unique, vocab clean, evidence paths verified)`；A1-A6 全 0；uv 与裸 python3 双形态同值 | ✅ |
| SC2 | `--self-test` PASS（红绿 golden + 公开树分支） | `SELF-TEST PASS (bad id shape / duplicate id / illegal status / illegal source / missing src path / ruleless Delivered-Missing-V2 rows / stale block all detected; clean + placeholder passes; --write heals; public-tree branch skips with explicit notes)`——红例 7 族 + 净例 + `--tree-root` 注入公开树分支例（`.work/` 缺席 → A4 doc: 走 skip 分支 + 显式注记不误报） | ✅ |
| SC3 | gaps 块行数 ≥ 10 | `<!-- parity:gaps -->` 块内表行 = **17**（3 Missing + 3 V2 + 1 Parked + 3 OOS + 7 Partial），awk 计数在案 | ✅ |
| SC4 | ci.yml 含 parity job + 裸 python3 本地 PASS | `git diff ci.yml` = 纯追加 11 行 job 块（build-and-test / release 两 job 零 diff）；`ruby -ryaml` 实载 OK；`python3 Scripts/parity-audit.py --check` exit 0 | ✅ |
| SC5 | 全套 `--all` `TOTAL|3848/24/0|`（ΔN=0） | 见 §全套终验 | ✅ |
| SC6 | xcstrings diff = 恰 N-1 三键尾块纯插入 | `git diff` = 51+/0- 单 hunk 尾部；`zh-audit --check` 前后 PASS 恒定；catalog keys **1926→1929**；grep 三 `%lld` 变体键恰 3 命中；断言 5 键集 30→30（三新键经 `INTERP_PREFIX_RE` 动态族覆盖，V16 限定口径在案） | ✅ |

## 全套终验（T4）

- 命令序：`xcodebuild build-for-testing …`（前置硬性，I-1 教训；首轮
  appex 签名债处置后 `TEST BUILD SUCCEEDED`）→ `caffeinate -dis
  Scripts/test-direct.sh --all`。
- 终值：**`TOTAL|3848/24/0|2131s` exit 0**（ΔN = 0 精确；对账基线 =
  M6-5 三路实测 3848）。**0 MEMFAIL**；七 bundle 全 8G 门内；零 crash。
- 逐 bundle（段和 = TOTAL 机核通过）：
  `IOP 686/1/0 peak 7456MB 423s` / `IOPParity 460/3/0 peak 7254MB 764s` /
  `Layers 494/4/0 peak 866MB 155s` / `Library 729/4/0 peak 614MB 79s` /
  `Sessions 284/4/0 peak 1218MB 75s` / `Export 379/4/0 peak 3678MB 217s` /
  `App 816/4/0 peak 1720MB 418s`——skip 段和 1+3+4+4+4+4+4 = 24 ✓；
  贴线族峰值 vs M6-5 参照（IOP 7560 / IOPParity 7242）全部 ±3% 带内。
- 原始 transcript：`all-run-m66-01.log`（phase 根，local-only）。

## 红线自检（T4 收口核对）

- 全部 Swift 源零 diff（`LightamerCore/` `LightamerIOP/` `App/` `Tests/`）；全部 `*.metal` 零 diff；`Project.swift` 全零 diff（零 tuist generate，L041 不触发）。
- `LightamerSidecar.swift` 零 diff；`Pipe/History/` + `PipeCacheKey.swift` + V50Order 零触；MCP 快照族零 diff（`McpLauncherPanelView.swift` 调用点零触碰——rider 只动目录）；Export 六格式矩阵三文件零 diff。
- UserDefaults 零新键；`\.runModal(` App/Sources 零命中；`String.LocalizationValue("` 插值禁形零命中。
- `*.xcstrings` = 恰 N-1 三键尾块纯插入（SC6）；zh-audit `--check` PASS 前后恒定。
- 工作树零新增 untracked 源文件；既有三 untracked 兄弟件零触碰零入库。
- survey 正本正文零改写（T1 diff = 纯插入指针段 7 行）。

## 执行期偏差

零结构性偏差。执行期事件一条（appex 签名债，§执行期事件，DECISIONS §3
同文登记）。gaps 行序 = 状态严重度序 + 域码字母序（CONTEXT D5 口径，
LightCraft 用户影响排名的显式简化，排名细化挂 V2 候选注记）。
