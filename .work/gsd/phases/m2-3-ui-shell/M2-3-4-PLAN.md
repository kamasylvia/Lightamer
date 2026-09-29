---
phase: m2-3
plan: "M2-3-4"
title: "收口——zh/en 对账脚本 + 双语补录批（D9：键集对账 + zh 值一次补齐，语言 code = zh 不引第二码）；computer-use Alcedo 真机逐屏差异清单轮（D1/D10：executor 自照自比 + 验收方独立抽查，证据落 .work/gui-acceptance/m2-3/，锁屏降级转人工）；收尾审计（legacyBody 零 diff + 禁用 op 路由零命中）+ 全套回归终跑 + REQUIREMENTS M2UIW/M2DIS/M2LIB 翻账"
wave: 4
depends_on: ["M2-3-3"]
autonomous: true
requirements: [M2UIW-01, M2UIW-02, M2UIW-03, M2UIW-04, M2UIW-05, M2UIW-06, M2LIB-05, M2DIS-03, M2DIS-04, M2LIB-07]
files_modified:
  - Scripts/zh-audit.py                                    # 新建：键集对账脚本（scan String(localized: + Text("key") 蛇形键 vs Localizable.xcstrings 双向 diff + zh 值完备 + 语言 code=zh 断言 + --check/--report/--self-test 三模式）
  - Resources/Localizable.xcstrings                        # 修改：zh 补录批（M2-2 增量 ~20 + M2-3 增量 150..250 键一次补齐；语言 code 恒 `zh`）
  - .work/gui-acceptance/m2-3/MANIFEST.md                  # 新建：差异清单索引（屏清单 × 判定汇总 × 证据路径 × 锁屏降级记录 × 交互/性能观察清单——E4 接账）
  - .work/gui-acceptance/m2-3/<screen>/alcedo.png          # 新建（逐屏三件套之一）：Alcedo 真机 computer-use 截图
  - .work/gui-acceptance/m2-3/<screen>/lightamer.png       # 新建（逐屏三件套之二）：Lightamer 同屏位截图
  - .work/gui-acceptance/m2-3/<screen>/<screen>.md         # 新建（逐屏三件套之三）：差异清单表（元件/方位/交互语义/判定[一致|偏差-接受|偏差-修]/备注）
  - App/Sources/Lightamer/UI/**（条件触点，仅限 T2 偏差-修修复批；逐条对表、独立 fix(ui) commit、实际集以 MANIFEST SHA 反查为准）  # 条目
  - Tests/LightamerTests/**（同上条件触点：修复批改变可测行为时同批补/改断言）  # 条目
  - .work/gsd/phases/m2-3-ui-shell/M2-3-4-SUMMARY.md       # 新建（本 plan 即收口，SUMMARY 随 T3 落盘）
  - .work/gsd/phases/m2-3-ui-shell/M2-3-4-DECISIONS.md     # 新建
  - .work/gsd/REQUIREMENTS.md                              # 修改：M2UIW-01..06 / M2DIS-03 / M2DIS-04 翻 Delivered + M2LIB-05 壳半边注记 + M2LIB-07③④ UI 挂账注记（带证据锚）
  - .work/GOAL-STATE.md                                    # 修改：续接点翻账（M2-3 完成 + 下一步 = M2-4；C 档停等）
  - .work/TODO.md                                          # 修改：状态同步（同批，§3.1 单一状态源）
  - .work/LESSONS.md                                       # 如踩坑
---

# Plan M2-3-4 — 收口（zh 对账补录 + computer-use 差异清单轮 + 审计翻账）

> **性质**：收口 plan——零新功能；三类工作 = 双语欠账一次清偿（D9）、视觉验收证据链
> （D1/D10）、phase 审计与翻账。验收判据全部文件形态/脚本退出码/计数可机检。
> **C 档门控**：本 plan 开工前 = M2-3-3 执行+验收闭环后用户确认（C 档第 2 停）；本 plan
> 完成后 = phase VALIDATION 前停（verify-work 结论给用户过目，C 档第 3 停）。

## 已定裁决（不得重开）

- **D1（OQ-1 A）**：「像」= 信息架构/布局语义级对齐（元件逐一存在 + 方位布局一致 +
  交互语义一致）；判定方法 = **逐屏差异清单**（每屏 Alcedo/Lightamer 各一截 → 表格化
  逐行标注「一致 / 偏差-接受 / 偏差-修」），不叠图不逐像素。
- **D10（OQ-10 A）**：executor 自照自比 + 验收方独立抽查——executor 执行尾 computer-use
  开 `/Applications/AlcedoStudio.app` 逐屏截图（AX + screencapture，UAT 自答先例同款）
  配对新壳同屏位截图；**验收 subagent 独立复开 Alcedo 抽查 2-3 屏**防自评放水；
  computer-use 可用性前置检查 + **锁屏降级 = 截图留档转人工走查**（GOAL-STATE GUI
  限制惯例）。**对照以修订后布局为准——左竖胶片条为本项目标识性差异，判定列记
  「偏差-接受（设计差异）」而非缺陷**。
- **D9（OQ-9 A）**：对账脚本（新增 `String(localized` 键全集 vs `Localizable.xcstrings`
  diff）+ zh 一次补齐；基数 1146 键 `zh` code；**不引入 `zh-Hans` 第二码**。
- **D5（OQ-5 A）**：收尾审计含「禁用 op 名在新壳路由表 grep 零命中」。
- **D12（OQ-12 A）**：收尾审计含 legacyBody/Session 面板文件零 diff。

## 关键设计决策（planner 裁决，执行中不重开）

### KD-1 zh-audit 脚本 = 键集双向对账 + zh 完备 + 语言 code 断言，三模式

`Scripts/zh-audit.py`（uv 运行惯例：`uv run python3 Scripts/zh-audit.py …`，禁裸
python3——TOOLCHAIN 红线）：

- **键源扫描面**（App 层 UI 目录 + Core 面向 UI 的局部化键）：
  `String(localized: "K"` 与 `Text("K")` 两模式；`K` 必须匹配蛇形键形状
  `^[a-z][a-z0-9_]+$`（ prose 误伤豁免）；`Text(verbatim:` 与注释行排除。
- **对账三断言**：①源键 ⊆ xcstrings 键（漏登记）；②xcstrings 键 ⊆ 源键 ∪ 白名单
  （孤儿键——白名单 = 显式列出代码动态拼键族，空则无）；③xcstrings 每键 `zh` 值
  非空。
- **语言 code 断言**：locale keys 只出现 `zh`/`en`，出现 `zh-Hans` 即 FAIL（D9 不引
  第二码）。
- **三模式**：`--report`（人读报告）/ `--check`（CI/机检语义：任一断言失败 exit 1，
  全过 exit 0）/ `--self-test`（内置 golden fixture 自检扫描器本身——临时目录构造
  样例源码与样例 xcstrings，断言扫描/对账正确，防脚本回归）。
- **误伤防线（风险节正本）**：蛇形键形状过滤 + verbatim/注释排除 + `--check` 失败
  输出逐条键名（可人工豁免清单 `--allowlist <file>`，豁免键须在 DECISIONS 逐条归因）。

### KD-2 差异清单 = 逐屏三件套文件形态 + 判定词表封闭 + MANIFEST 汇总

- **屏清单（15 屏基线，executor 可增不可减；m1 如实计数）**：
  `library-welcome`（空项目态）/ `library-grid-inspector`（有图网格 + Inspector 展开）/
  `library-search-dialog` / `import-dialog` / `background-task-bar` /
  `editor-toolrail-history`（History 展开）/ `editor-viewport`（FIT/ZoomHUD）/
  `editor-filmstrip`（左竖胶片条）/ `editor-scopes`（直方图 + 波形各一截，两图可并入
  同 md 两表段）/ `editor-adjustment-stack-tone` / `editor-adjustment-stack-geometry`
  （Advanced 折叠组）/ `editor-rawdecode` / `settings-default-behavior` +
  `settings-keyboard` + `settings-about`（设置三屏代表性抽样；语言页并入 about 截图
  同段可选）。**E1 判定预期钉子**：Display Transform 页签如抽样截图，预期内容 =
  Vignette + 「DRT arrives with M2-6」占位节——AgX 属 M2-1 禁用面失挂（checker E1
  勘误），差异清单不得把 AgX 记为缺失缺陷。
- **三件套形态**：`.work/gui-acceptance/m2-3/<screen>/alcedo.png` +
  `lightamer.png` + `<screen>.md`；md 必含判定表，表头封闭：
  `| 元件/交互 | Alcedo | Lightamer | 判定 | 备注 |`；**判定词封闭集** =
  `一致` / `偏差-接受` / `偏差-修` / `偏差-接受（设计差异）`（左胶片条等用户裁定项
  专用）——其余词 = 形态违约。
- **MANIFEST.md**：屏 × 判定汇总矩阵 + 偏差-修条目清单（每条 → 修复 commit SHA）+
  锁屏降级记录位 + 抽查记录位（验收 subagent 2-3 屏填写）+ 「交互/性能观察清单」节。
- **交互/性能观察清单（checker E4 跨 plan 挂账接收节）**：走查协议在逐屏差异清单外
  增四项接账——①万行胶片条滚动 60fps 目测 + List 窗口信号 → 桥 prioritize/cancel
  **真接线兜底核验**（P1 KD-5/T4 挂，m9 并入本项）；②菜单撞键真实按键走查（P1 KD-6
  挂）；③示波器拖累 PREVIEW 帧率目测（P3 风险节挂）；④左轨工具轨 + 胶片条宽度观感
  裁决（P3 风险节挂）。逐项结论（达标/偏差-接受/挂账转人工）记 MANIFEST 观察清单节 +
  SUMMARY；观察项非门，不计入 AC 计数。
- **机检**：`bash` 形态检查（AC #5 给出逐屏 `[ -f ]` 三件套存在性 + `grep -E`
  判定词封闭集命中断言）——两条命令原样入 AC，验收方照跑。
- **偏差-修处置**：T2 内即时修复（`fix(ui): …` 独立小 commit，只 add 相关文件）→
  重截该屏 → 判定翻「一致」；修复不进 AC 计数（清单收敛为准）。

### KD-3 收尾审计 = 五项零 diff/零命中 + 翻账批同 commit 收口

1. legacyBody 零 diff：`git diff --name-only <m2-3-base>..HEAD -- App/Sources/Lightamer/UI/SidebarView.swift App/Sources/Lightamer/UI/SessionBrowserView.swift App/Sources/Lightamer/UI/CullingView.swift App/Sources/Lightamer/UI/FilterBarView.swift App/Sources/Lightamer/UI/CatalogBrowserView.swift App/Sources/Lightamer/UI/CatalogFilterBarView.swift` = 空（`<m2-3-base>` = M2-3-1 T1 前的 HEAD SHA，登记于 M2-3-1 SUMMARY——若缺登记，回溯 `git log --oneline` 首个 `feat(ui): dark glass` 前一提交）。
2. 禁用 op 零命中：`git grep -iE 'filmicrgb|sigmoid|agx|denoiseprofile|nlmeans|bilateral' -- 'App/Sources/Lightamer/UI/Shell/*'` = 空（注释豁免面 = 仅 EditorTabRoute.swift 头注的禁用说明行，grep 时 `--and --not` 不可用则人工核对该单文件命中行均属头注注释）。
3. `LightamerCore/` 相对 M2-3-base 的 diff == 恰 `Sources/Decode/RAWDecoder.swift` 一文件（P3 例外缝）+ 其 kd-4 声明的连带（如触发）。
4. `Inspector/` 33 面板 + InspectorView/InspectorRowView/IOPPanelProvider 零 diff。
5. zh-audit `--check` exit 0。

**翻账批**（T3，与审计同 commit）：REQUIREMENTS M2UIW-01..06 → Delivered（各带证据锚
= 对应 plan SUMMARY + 差异清单 MANIFEST）；M2DIS-03 → Delivered 全条（M2-1 五面收窄 +
M2-3 七页签归页）；M2DIS-04 → Delivered（RAW Decode 页签暴露 + decode overrides +
decode 层承担降噪）；M2LIB-05 注记补「壳半边 M2-3 交付」；M2LIB-07 ③④ 注记补 UI 面
交付；`.work/TODO.md` / GOAL-STATE 同批（§3.1 单一状态源纪律）。

## read_first

1. `.work/gsd/phases/m2-3-ui-shell/M2-3-CONTEXT.md`——D1/D9/D10/D5/D12 + Ruling 修订尾注。
2. `M2-3-1-SUMMARY.md` / `M2-3-2-SUMMARY.md` / `M2-3-3-SUMMARY.md`——三 plan 交付面 +
   m2-3-base SHA 登记 + 键族清单。
3. `Resources/Localizable.xcstrings`（仓库根）——1146 键基数 + `zh` code
   结构实态（m5 路径勘误：仓库根，非 App/Sources 内）。
4. `.work/GOAL-STATE.md` 环境备忘节——Alcedo 实机 + computer-use 授权 + GUI 走查惯例
   （`.work/gui-acceptance/` 路径与 FINDINGS 先例）。
5. `Scripts/` 目录既有脚本形态（`test-direct.sh` 风格参照；uv 惯例）。
6. `AGENTS.md` §3.1/§3.2——文档同批 + 截图进文档规则（视口截图、关键区、数字入图注）。

## 纪律（强制）

1. 提交纪律：每任务独立提交（全英文 Conventional、≤72 字符祈使句、body what+why +
   同批 md 清单）；只 add 本任务申报文件；不 push；`.work/gsd/...` 真路径。T2 内
   偏差-修修复批 = 独立 `fix(ui): …` commit（不与清单提交混合）。
2. 构建纪律：`caffeinate -dis` 包裹；本 plan 新建 .py 无需 `tuist generate`（非 Xcode
   工程文件）；**全 phase 零新 .swift 预期**——若 T2 修复批引入新文件，同 commit
   `tuist generate`。
3. 测试纪律：`Scripts/test-direct.sh` 双读（L028）；**基线 = 2049 + M2-3-1/2/3 终值**；
   T3 终跑全套 0 fail。
4. 边界纪律：每任务检查 `.work/config.toml [gsd]`；T2 开工前确认 C 档第 2 停已过
   （用户确认 M2-3-3 闭环）。
5. 架构红线：T2 修复批仅限清单判定「偏差-修」条目对应文件（**顺手 fix 禁止**——修复
   逐条对表）；REQUIREMENTS 翻账 = 事实陈述 + 证据锚，禁改需求字面语义；GPL 红线
   ——差异清单 md 只写布局语义比对文字，禁拷 Alcedo 截图外任何资产进仓。

## Tasks

### T1 zh-audit 脚本 + 双语补录批

- **read_first**：上列 1/3/5。
- **action**
  1. 新建 `Scripts/zh-audit.py`（KD-1 全量：双模式键源扫描 / 三断言 / 语言 code 断言 /
     `--report`/`--check`/`--self-test` 三模式 / `--allowlist` 豁免缝）。
  2. `--check` 首跑取欠账全集（预估 150..270 键：M2-2 verbatim 欠 ~20 + M2-3 各 plan
     新增）。
  3. zh 补录批：逐键补 `zh` 值（技术标识符/键名不译；文案口径与既有 1146 键风格一致
     ——简体中文、标点半角、按钮无句号）；白名单键（如有）逐条 DECISIONS 归因。
  4. 复跑 `--check` exit 0；`--self-test` 绿。
- **验收标准**
  - [ ] `uv run python3 Scripts/zh-audit.py --check` exit 0（三断言 + code 断言全过）。
  - [ ] `--self-test` 绿（扫描器 golden 自检）。
  - [ ] `Resources/Localizable.xcstrings` diff 仅增 zh 值/新键，零既有 en 值改写
        （`git diff` 抽核 10 键 + 脚本断言兜底）。

### T2 computer-use 逐屏差异清单轮（自照自比 + 偏差-修批）

- **read_first**：上列 1/2/4/6 + `.work/gui-acceptance/` 既有 FINDINGS 形态先例。
- **action**
  1. 前置检查：computer-use 可用 + Alcedo 实机在位 + **屏幕未锁**确认（锁屏 → 走
     降级路径第 6 步）。
  2. 构建并启动 Lightamer（`caffeinate -dis` + tuist build；测试项目 fixture 用
     M2-2-2 合成 C1 Session 形态导入，图数 ≥ 30 张保证网格/Inspector/Activity 有形态）。
  3. 逐屏走查（KD-2 屏清单 15+ 屏）：每屏 Alcedo 截图 + Lightamer 同屏位截图 + 差异
     清单 md（判定词封闭集；左胶片条等用户裁定项记「偏差-接受（设计差异）」）。
  4. 「偏差-修」条目逐条修复（`fix(ui): …` 独立 commit）→ 复跑该屏 → 判定翻「一致」；
     「偏差-接受」逐条备注归因（性能/成本/设计差异）。
  5. **交互/性能观察清单四项走查**（KD-2 接收节，checker E4）：①万行胶片条滚动 60fps
     目测 + List→桥真接线兜底核验（m9 并入）；②菜单撞键真实按键走查；③示波器拖累
     PREVIEW 帧率目测；④左轨工具轨 + 胶片条宽度观感裁决——逐项结论记 MANIFEST 观察
     清单节 + SUMMARY（观察项非门）。
  6. **锁屏降级路径**：computer-use 不可用或锁屏 → 已得截图留档 + MANIFEST 降级记录 +
     SUMMARY Manual-Only 登记（转人工走查，不阻塞 T3 翻账——验收项标注「视觉证据
     部分/全缺，转人工」）。
  7. 落盘 MANIFEST.md（汇总矩阵 + 偏差-修 → commit SHA 映射 + 交互/性能观察清单 +
     抽查记录位空置）。
- **验收标准**
  - [ ] 三件套形态机检过（AC #5 两条命令原样执行零 fail）。
  - [ ] 判定词封闭集：无表外判定词（grep 断言）。
  - [ ] 偏差-修条目全部闭环（MANIFEST 无未修「偏差-修」残留）或降级记录在案。
  - [ ] 交互/性能观察清单四项逐项有结论（MANIFEST 观察清单节 + SUMMARY 记录在案；
        观察项非门——checker E4）。

### T3 收尾审计 + 全套终跑 + 翻账

- **read_first**：上列 1/2 + 本 plan AC 表。
- **action**
  1. KD-3 五项审计逐条执行（命令与结果原样入 SUMMARY；第 1 项 base SHA 从 M2-3-1
     SUMMARY 取，缺则回溯定位并注明）。
  2. 全套回归终跑：`Scripts/test-direct.sh`（`caffeinate -dis` 包裹）——计数/秒数入
     SUMMARY；预期 ≈ 2049 + 70..100 = **2120..2150 / 13..15skip / 0 fail**（skip 增量
     仅限 perf 观察行门控语义）。
  3. 翻账批（KD-3）：REQUIREMENTS M2UIW-01..06/M2DIS-03/M2DIS-04 翻 Delivered +
     M2LIB-05/M2LIB-07③④ 注记；`.work/TODO.md` 同批；GOAL-STATE 续接点 = M2-3 完成 +
     C 档第 3 停（VALIDATION 前停，下一步 = verify-work / M2-4 起航待用户）。
  4. 落盘 `M2-3-4-SUMMARY.md`（= phase 收口 SUMMARY：四 plan 战果汇总 + Manual-Only
     清单 + 差异清单结论引用）+ `M2-3-4-DECISIONS.md`。
  5. `git diff --stat` 核对边界与 front-matter 一致。
- **验收标准**
  - [ ] 五项审计全绿（证据链入 SUMMARY）；全套 0 fail 计数在预估带内。
  - [ ] REQUIREMENTS/TODO/GOAL-STATE 同批翻账（单一状态源，无第二处状态漂移）。
  - [ ] diff 边界 == 申报文件集。

## 验收标准（AC 总表，逐条可机检）

| # | AC | 机检方式 |
|---|---|---|
| 1 | zh 对账三断言 + 语言 code 断言全过：源键⊆catalog ⊆ 源键∪白名单；zh 值零缺；code 恒 zh 无 zh-Hans | `uv run python3 Scripts/zh-audit.py --check` exit 0 |
| 2 | 脚本自检绿（扫描器 golden：漏登记/孤儿键/zh 缺失/code 违规四 case 均被检出） | `--self-test` exit 0 |
| 3 | 差异清单屏覆盖：屏清单 15+ 基线屏逐一在 MANIFEST；`editor-filmstrip` 判定 = 「偏差-接受（设计差异）」专用词 | MANIFEST 矩阵断言 + md grep |
| 4 | 逐屏三件套存在且判定表头/词封闭：`for d in .work/gui-acceptance/m2-3/*/; do test -f "$d/alcedo.png" -a -f "$d/lightamer.png" -a -f "$d/$(basename "$d").md" \|\| echo "MISSING $d"; done` 零输出；判定列提取（m2 写实）= `grep -rhE '^\| ' .work/gui-acceptance/m2-3/*/*.md \| awk -F'\|' '{print $5}' \| sed 's/^ *//; s/ *$//' \| sort -u`（awk -F'\|' 第 5 字段 = 表第 4 内容列「判定」），输出剔除表头行值 `判定` 后逐值 case 匹配封闭集 {一致, 偏差-接受, 偏差-修, 偏差-接受（设计差异）}，表外词 = fail | shell 两命令原样零 fail |
| 5 | 偏差-修闭环：MANIFEST 无未修「偏差-修」残留；修复批独立 `fix(ui)` commit 可追溯 | MANIFEST 逐条 SHA 反查 `git show --stat` |
| 6 | 锁屏/不可用降级：MANIFEST 降级记录位 + SUMMARY Manual-Only 登记在案（或「未触发」显式记录） | 文件形态断言 |
| 7 | 收尾审计五项：legacyBody 零 diff / 禁用 op 零命中 / Core diff 恰 RAWDecoder.swift（+声明连带）/ Inspector 族零 diff / zh-check exit 0 | KD-3 五命令原样执行，结果入 SUMMARY |
| 8 | 全套回归终跑 0 fail，计数 2120..2150 / 13..15skip | test-direct.sh Executed/failures 双读 |
| 9 | 翻账批：REQUIREMENTS M2UIW-01..06/M2DIS-03/M2DIS-04 = Delivered 带证据锚；M2LIB-05/07 注记补全；TODO/GOAL-STATE 同批无第二状态源 | 文件 grep（`M2UIW-0N*: [x]`）+ 交叉引用核对 |
| 10 | diff 边界 == 申报文件集 | `git diff --stat` 逐文件核对 |

## 风险与边界

- **zh 对账脚本误伤**：三重防线（蛇形键形状过滤 / verbatim+注释排除 / `--allowlist`
  显式豁免缝 + DECISIONS 逐条归因）；`--self-test` golden 防脚本自身回归；**白名单非
  转义门**——豁免键必须在 DECISIONS 有归因，无归因豁免 = 违约。
- **computer-use 锁屏/不可用降级**：降级 = 留档 + Manual-Only 转人工，**不伪造截图、
  不阻塞翻账**（AC #6 允许显式「未触发」记录）；人工走查挂 GOAL-STATE 待用户窗口。
- **差异清单自评放水**：D10 验收方独立抽查 2-3 屏是硬约定——MANIFEST 预留抽查记录位；
  抽查与 executor 判定不一致 → 该屏重开（验收轮语义，非本 plan 自动化范围）。
- **修复批范围蔓延**：T2 修复逐条对表（判定「偏差-修」即修复义务）；「顺手 fix」=
  纪律 5 违约——新发现缺陷一律另立清单条目（偏差-修或挂账），不混入当前条目 commit。
- **双语口径漂移**：补录批与 M1 既有 1146 键风格对齐（首键抽样 10 键人工核对 + 与
  既有 `menu_*`/`settings_*` 键风格比对）；发现既有键翻译错误**不顺手改**（超范围，
  登记待办）。
- **Alcedo 侧状态污染**：对照截图前 Alcedo 需手动进入同语义屏（其无脚本接口）——
  computer-use 操作 Alcedo 仅做导航点击（AX 授权面），不改其设置/项目文件；截图后
  退出不保存其会话态。
- **skip 计数漂移**：基线 13 + perf 门控观察行；若终跑 skip 超出 13..15 带，逐条归因
  入 SUMMARY（语义 = 门控 skip 声明，非逃逸）。

## 提交约定

- T1 `feat(scripts): zh catalog audit tooling and backfill batch`
- T2 `docs(m2-3): alcedo screen diff inventory with fix batch`
- T3 `docs(m2-3): close out phase ui shell with audit and ledger flips`
- （T2 内修复批各自 `fix(ui): <targeted shell fix>` 独立 commit）
- 全英文 Conventional Commits；body 写 what+why + 同批同步的 md 清单；不 push。
