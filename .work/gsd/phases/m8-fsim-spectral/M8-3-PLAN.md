---
phase: m8-fsim-spectral
plan: "M8-3"
title: "plan 3 — FSIM 面板 + 收口（T1 UI 零新增确认 + adaptation 不暴露 / T2 descriptor·probe 跟随核验 / T3 「Update to Current Process」迁移 UX / T4 曝光语义钉死 + NOTICE 措辞批修 / T5 全套 --all 收口 / T6 SUMMARY·DECISIONS + gui 走查 + C 档停）"
wave: 4
depends_on: ["M8-2"]
autonomous: true
requirements: ["charter = 本 phase CONTEXT.md（D-M8-6/D-M8-7/D-M8-8 + 红线 4/11/13）——全阶段闭环波", "research 正本 = phases/m8-fsim-spectral/RESEARCH.md（9b256482）§3.1（descriptor 同工厂跟随）/ §5 OQ-6/7/8 / §6.1 M8-3 行", "OQ 裁决正本 = 同目录 CONTEXT.md（UI 零新增 + adaptation 不暴露 + solve gain 钉死 + NOTICE 批修）；M6-2 §6 迁移 UX 挂账正主在本 plan 落地", "基线带 = M8-2 终态（预期 4256..4274）；本 plan 分账 +10..14；全套 --all 对账 = 本 plan 收口轮（基线 4206/41/0 → 终值带 4266..4288）", "C 档停位 = 本 plan 闭环 = phase 收口汇报（VALIDATION 前停——verify-work 结论给用户过目）"]
success_criteria: "SC 全可机检——T1：UI 零新增断言（Film 面板控件清单零 diff——面板视图文件 diff 行号域 = 零新增控件/零新增 section；readout 数值随核变 = 非 UI 面登记）+ adaptation 不暴露机检（bandwidth/surface/表选择器在 App/ 零命中 + UserDefaults 零新键断言 + build 期常量面 grep）；T2：descriptor/probe 跟随核验（FilmDescriptorProbe 走 assembleFilmLeg 同工厂——v2 档 probe 输出在案 + ISO 6846 归约/面板数学零改断言 + response 读数变化登记 by design）；T3：迁移 UX（「Update to Current Process」= 面板按钮 + 确认 sheet〔L057 缝——sheet 非 runModal〕+ document 级 process 升 2 单 discrete commit + 历史键族 history_process_migrate + 旧档零迁移语义确认〔frozen 恒可选〕）；T4：曝光语义钉死（exposureEv solve gain 负测组 DECISIONS 裁决登记——D-M8-8 终账）+ NOTICE 消费披露行升格（逐波长材料链语义）+ 用户可见措辞升格「光谱重建材质模拟（逐波长），非场景光谱重放」+ AGENTS/M3-2 历史文档勘误行追加〔原文不改〕+ MANIFEST 对账零漂移确认；T5：全套 --all 收口（orchestrator 批准制 + machine-guard + caffeinate -dis + 8G 门 + MEMFAIL 机检 + parentage 纪律）+ ΔN 终账对账（4206 → 4266..4288 + skip 逐族申报）+ gui 走查证据（.work/gui-acceptance/m8/ MANIFEST）；T6：SUMMARY/DECISIONS + VALIDATION 前停"
estimated_tests: "+10..14（T1 +2..3 / T2 +2..3〔review M2——原 +1..2 致行和 9..13 ≠ 表称 +10..14，+1 对齐；行和复核 2..3+2..3+4..5+2..3 = 10..14 ✓〕/ T3 +4..5 / T4 +2..3 / T5 对账零增量〔--all 实测数即终账〕/ T6 0；越带申报理由）"
test_bundles: [App, IOPParity]
baseline: "M8-2 终态带 4256..4274（基线 4206/41/0 + 1a + 1b + 2 分账；本 plan 开工前亲核 M8-2-SUMMARY 实数）"
expected_all: "全套终值带 4266..4288（4206/41/0 + ΔN 60..82；skip 41 + 1b probe 族 + 本批零 skip 增量——逐族申报；--all = orchestrator 批准制，本 plan 收口轮统一对账）"
red_lines:
  - "共用红线正本 = CONTEXT §四 plan 红线 front-matter 17 条（本 plan 高相关 = 红线 4 xcstrings 尾块〔迁移 UX 新键〕/ 红线 11 UserDefaults 零新键 / 红线 13 L057 缝 / 红线 9 --all 批准制）。"
  - "UI 零新增 = Alcedo 对标面零新增（D-M8-7）：Film 面板材料 picker/Y·M/Solve/宽容度面板数学零改；迁移按钮 = M6-2 §6 挂账正主非对标面（唯一例外，DECISIONS 登记）。"
  - "历史文档原文不改：NOTICE 披露行 = 升格语义非新增条目（亲核登记⑦）；AGENTS M3-3 节/M3-2 RESEARCH-NOTES = 勘误行追加；Resources/FilmProfiles/ profile JSON 与 neutral_print_filters 字节零动（MANIFEST 对账）。"
  - "旧档零迁移语义：process ≤ 1 文档恒密度核冻结渲染；迁移 = 用户显式动作一次 commit，无自动迁移无后台批量；迁移不可逆面 = 无（process 是渲染代际非数据变换，DECISIONS 登记说明）。"
files_modified:
  - App/Sources/Lightamer/UI/Shell/FilmPanelView.swift            # T3：迁移按钮 + 确认 sheet（T1 核验零 diff 于控件清单——按钮为唯一新增元素；路径勘正 review M4——真身在 UI/Shell/ 非 UI/Inspector/，实测亲核）
  - App/Sources/Lightamer/EditorState+FilmMigration.swift          # T3：新建——迁移动作（document 级 process 升 2 单 discrete commit；App 侧 EditorState 域）
  - Resources/Localizable.xcstrings                                # T3/T4：迁移 UX 键族 + 措辞键值面（尾块纯插入）
  - Resources/FilmProfiles/NOTICE                                  # T4：消费披露行升格（§2 语义面——byte-verbatim 范围仅指 profiles/ 数据件，NOTICE 是我方文件可改）
  - AGENTS.md                                                      # T4：M3-3 增量节勘误行追加 + M8 增量节补登（随 M8-2 T4 账本行同域）
  - Tests/LightamerTests/FilmPanelSpectralUITests.swift            # T1/T3：新建（App bundle）——零新增断言 + 迁移 UX 模型
  - Tests/LightamerTests/SpectralExposureSemanticsTests.swift      # T4：新建（IOPParity）——exposureEv solve gain 负测组
  - Project.swift                                                  # T6：两新测试文件入对应 bundle 显式数组
  - .work/gsd/phases/m2-4-0-test-bundles/M2-4-0-BUNDLE-MAP.txt     # T6：两行落域登记
  - .work/gui-acceptance/m8/MANIFEST.md                            # T5：gui 走查证据正本
  - .work/gsd/phases/m8-fsim-spectral/M8-3-SUMMARY.md              # T6：执行摘要（逐任务记账 + ΔN 终账 + 全套对账）
  - .work/gsd/phases/m8-fsim-spectral/M8-3-DECISIONS.md            # T6：裁定记录（曝光语义终账 + 迁移 UX 形态 + 各偏差）
  - .work/gsd/phases/m8-fsim-spectral/M8-VALIDATION.md             # T6：phase 签核预备（C 档停——verify-work 结论输入）

# Plan M8-3 — FSIM 面板 + 收口：UI 零新增确认 + 迁移 UX + NOTICE 批修 + 全套对账

> **裁决正本** = `CONTEXT.md`（D-M8-6/D-M8-7/D-M8-8 + 红线 4/11/13；晨审
> 可推翻）；规格正本 = `RESEARCH.md`（§5 OQ-6/7/8 + §6.1 M8-3 行；planner
> 抽核吻合）。本 plan = 全阶段闭环波：面板零新增确认 + 迁移 UX（M6-2 §6
> 挂账正主）+ NOTICE/措辞批修 + 曝光语义终账 + 全套 `--all` 对账。
>
> **裁定权归属钉**：本 plan 无用户裁决分支（T1-T6 形态 = CONTEXT 落定值）。
> 执行中如触「必须扩面」（新增光谱控件 / adaptation 开关 / 自动迁移 /
> profile JSON 或 NOTICE 数据件字节改动 / UserDefaults 新键）= 停手上报，
> 不得自裁扩界。
>
> **执行序**：T1 → T2 → T3 → T4 → T5 → T6。每任务独立 commit；重活
> （xcodebuild / --all / gui 走查）起跑前过 `Scripts/machine-guard.sh`；
> **--all = orchestrator 批准制**（T5 前取得批准 + 运行监视）。
>
> **C 档停**：T6 闭环 = phase 收口汇报（**VALIDATION 前停**——verify-work
> 结论给用户过目，AGENTS C 档门控第 3 条）。
>
> **基线**：M8-2 终态（带 4256..4274；开工前亲核 M8-2-SUMMARY 实数）。
> **全套终值带 4266..4288**（4206/41/0 + ΔN 60..82；skip 增量 = 1b probe
> 族逐条 + 本批零新 skip）。

## ΔN 预算表（逐任务，本 plan 分账带 +10..14；越带须申报理由）

| 任务 | 测试增量 | 构成 | 落点 |
|---|---|---|---|
| T1 UI 零新增确认 | **+2..3** | 控件清单零 diff 断言 + adaptation/表选择器/UserDefaults 零命中 grep 组 | App（FilmPanelSpectralUITests） |
| T2 probe 跟随核验 | **+2..3**〔review M2——+1 对齐行和〕 | v2 档 probe 输出在案 + 面板数学零改断言 + 读数对照记录测试 | IOPParity |
| T3 迁移 UX | **+4..5** | 迁移动作模型（升 2 commit/键族/不可重复迁移守卫）+ 确认 sheet 挂载 + 零自动迁移负测 | App（FilmPanelSpectralUITests） |
| T4 曝光语义 + NOTICE | **+2..3** | exposureEv 负测组终账 + 措辞键值面断言 + MANIFEST 对账 | IOPParity（SpectralExposureSemanticsTests） |
| T5 --all 收口 | **0** | 实测数即终账（对账式非增量） | — |
| T6 收口 | **0** | docs + tuist | — |
| **合计** | **+10..14** | 基线带 → 全套终值带 4266..4288 | 两新测试文件 |

## 已定裁决（生效值，硬约束，不得重开）

1. **UI 零新增**（D-M8-7）——材料 picker/Y·M/Solve/宽容度数学零改；
   adaptation bandwidth/surface 恒 build 期常量；迁移按钮 = 唯一例外。
2. **旧档零迁移语义**——frozen 恒可选；迁移 = 显式单 commit；无后台批量。
3. **NOTICE 批修三面**（D-M8-6）——披露行升格 + 用户可见措辞升格 + 历史
   文档勘误行追加（原文不改）。
4. **曝光语义终账**（D-M8-8）——solve gain 消费层负测钉死 + DECISIONS
   裁决登记。
5. **--all 批准制**（红线 9）——T5 前取得 orchestrator 批准；8G 门 +
   MEMFAIL + parentage 纪律全程。

## read_first（全局，每任务开工前过一遍）

- `.work/gsd/phases/m8-fsim-spectral/CONTEXT.md`（D-M8-6/7/8 + 红线 17 条
  + 亲核登记⑦ + 晨审索引）
- `.work/gsd/phases/m8-fsim-spectral/RESEARCH.md` §5 OQ-6/7/8 + §3.1
  descriptor 段 + §6.1 M8-3 行
- `.work/gsd/phases/m8-fsim-spectral/M8-2-SUMMARY.md` + `M8-2-DECISIONS.md`
  （五件套终账 + 分叉点登记——本 plan 消费）
- `.work/gsd/phases/m6-2-process-version/RESEARCH-NOTES.md` §6（迁移 UX
  挂账正本——本 plan 兑现）
- `App/Sources/Lightamer/UI/Shell/FilmPanelView.swift` 全文（M3-3-03
  最小面正本——零新增的核对基线；路径勘正 review M4——真身在 UI/Shell/）；
  `Resources/FilmProfiles/NOTICE` 全文
  （披露行现文亲核）
- `.work/LESSONS.md` L041（tuist 末位）+ L057（PanelPresentation 缝正本）
  + AGENTS.md「L057 面板呈现约定」+「M2-9 架构增量」F-2（Localization
  Value 禁形）

---

## T1 — UI 零新增确认 + adaptation 不暴露（D-M8-7）

> 光谱核上线后 Film 面板零新增控件：readout 数值随核变 = 渲染面事实非 UI
> 面；adaptation 两开关/上游表选择器不存在于我方模型面。

**read_first**：CONTEXT D-M8-7 + 亲核登记⑦；`FilmPanelView.swift` 全文
（M3-3-03 最小面——控件清单核对基线）；RESEARCH §OQ-7；AGENTS.md
「M3-3 架构增量」Film 面板节。

- **action**：
  1. 控件清单核对：FilmPanelView 现有 section/控件清单逐项过（材料
     picker / Y·M 双轮 / Solve / readout / 宽容度入口）——本 plan T3 前
     零新增断言基线（清单 = 测试内表驱动快照）。
  2. adaptation 不暴露机检：`bandwidth`/`surface`/表选择器语义在 `App/`
     面零命中（grep 组——参数名可撞车，grep 按语义键组：
     `adaptationBandwidth`/`adaptationSurface`/`upsampling` 于 App target
     源零命中）；UserDefaults 零新键断言（`library.analysis` 等既有键族
     清单外零新增——红线 11 机检）。
  3. 测试（App bundle）：控件清单快照断言（零新增）+ 零新键 grep 组。
- **验收标准（机检）**：
  - 构建绿；`git diff --stat` 本任务产线面 = 零（纯测试 + 核对）。
  - 控件清单快照测试在册；grep 组零命中输出留档。
  - `--bundle App` 定向零回归。
- **commit**: `test(m83): pin film panel zero new controls invariant`
- **回滚与偏差申报要求**：回滚 = revert 单 commit；偏差（清单快照形态）=
  DECISIONS 申报；**禁在本任务触碰面板视图文件**（T3 才动——迁移按钮）。

## T2 — descriptor/probe 跟随核验（零改确认）

> `FilmDescriptorProbe` 走 `assembleFilmLeg` 同工厂（PixelPipe :1222 注释
> 面）——M8-2 换臂后 probe 自动跟随光谱核；ISO 6846 归约/宽容度面板数学
> 零改；response 读数（print reflectance luma 语义）随核变 = by design。

**read_first**：RESEARCH §3.1 descriptor 段 + §4.3 宽容度段；CONTEXT
D-M8-7；`LightamerCore/Sources/Pipe/Film/FilmDescriptorProbe.swift` +
`LightamerCore/Sources/Film/FilmDescriptor.swift`（ISO 6846 归约面——零
改确认对象）。

- **action**：
  1. 核验（零改确认门）：probe 经同工厂 v2 臂输出在案（M8-2 T1 跟随
     冒烟的扩臂）——ISO 6846 归约/面板数学零 diff 机检（FilmDescriptor
     .swift 零 diff 断言）。
  2. response 读数变化登记：v1 vs v2 同图 probe 读数对照（DECISIONS 表
     ——by design 申报，非回归）。
  3. 测试（IOPParity）：v2 档 probe 输出存在性 + FilmDescriptor 零 diff
     编译面断言（随构建绿即证）+ 读数对照记录测试（双档数值在案，不断
     言相等——语义随核变）。
- **验收标准（机检）**：
  - 构建绿；`git diff --stat` 产线面 = 零（FilmDescriptor/
    FilmDescriptorProbe 零 diff）。
  - 读数对照表落 DECISIONS。
- **commit**: `test(m83): verify descriptor probe follows spectral arm`
- **回滚与偏差申报要求**：回滚 = revert 单 commit；偏差（对照图选择）=
  DECISIONS 申报；**禁做 ISO 6846/面板数学「适配性修改」**（零改确认门
  ——读数变 = 语义非缺陷）。

## T3 — 「Update to Current Process」迁移 UX（M6-2 §6 正主）

> v2 上线后 v1 档恒冻结渲染（零迁移义务）；迁移 = 用户显式动作：面板按钮
> + 确认 sheet + document 级 process 升 2 单 discrete commit。形态 = 最
> 小面（一个按钮 + 一个确认 sheet），非 Alcedo 对标面（D-M8-7 唯一例外，
> DECISIONS 登记）。

**read_first**：CONTEXT D-M8-7（例外登记）+ 红线 4/13；`FilmPanelView.swift`
（applyDiscrete 缝 + sheet 挂载先例——M2-8 SheetEnvironmentInjection 教训
：app-root sheet 内容面显式重注入）；L057 DECISIONS（D1R/D2——sheet 非
runModal）；`.work/gsd/phases/m6-2-process-version/RESEARCH-NOTES.md` §6；
AGENTS.md「M2-8 架构增量」走查双缺陷节。

- **action**：
  1. 迁移动作模型（App 侧可测纯模型 `FilmMigrationAction`——输入 = 文档
     现状 process/编辑态，输出 = 可迁移判定 + commit 描述；View 只消费）：
     守卫三件——已 v2 档 = 不可重复迁移（按钮隐藏/置灰）；有未保存编辑 =
     提示先落盘（sidecar flush 语义复用）；迁移 = document 级单 discrete
     commit（process 升 2——不触碰 history items/pixel 数据，DECISIONS
     登记「迁移非数据变换」说明）。
  2. `FilmPanelView` 迁移行：v1 档显示「Update to Current Process」按钮 +
     确认 sheet（L057 缝——SwiftUI sheet；app-root 挂载则内容面显式重注
     入——M2-8 教训）；v2 档隐藏（零观感差）。
  3. 键族：`history_process_migrate`（commit 键）+ `panel_film_migrate_*
     （按钮/确认标题/确认正文/取消）4-5 键——xcstrings 尾块纯插入 +
     zh-audit 双 PASS。
  4. 测试（App bundle）：迁移模型表驱动（v1 可迁移/v2 拒/未落盘守卫/
     重复迁移拒）+ commit 键族断言 + sheet 挂载断言（环境注入面——负腿
     掏空注入 = fatal 签名先例形态）+ 零自动迁移负测（无任何后台迁移
     路径——grep 断言）。
- **验收标准（机检）**：
  - 构建绿；`git diff --stat` 恰两产线文件（FilmPanelView + EditorState+
    FilmMigration）+ xcstrings。
  - grep：`.runModal(` 零命中；新键全部静态字面量（LocalizationValue
    插值禁形零命中）；zh-audit `--check` + `--self-test` 双 PASS 输出
    留档。
  - 迁移 commit 后 sidecar `process=2` 往返断言；history items 零增量
    断言（迁移非编辑——不产生 pixel history item）。
  - `--bundle App` 定向零回归。
- **commit**: `feat(m83): add update to current process migration`
- **回滚与偏差申报要求**：回滚 = revert 单 commit（回无迁移面态——已迁
  移文档 process=2 由 clamp 兜底渲染）；偏差（键清单/按钮文案终值/sheet
  挂载位）= DECISIONS 申报；**禁自动迁移/后台批量**（红线）；**禁触
  HistoryStack/HistoryHash**（迁移走 document 级既有 commit 缝——M2-6
  drtRecord 先例同域）；**禁在 body 求值路径做迁移判定重活**（模型纯函
  数 + 状态缓存）。

## T4 — 曝光语义钉死 + NOTICE 措辞批修（D-M8-8/D-M8-6）

**read_first**：CONTEXT D-M8-8/D-M8-6 + §亲核登记⑦；`Resources/FilmProfiles/
NOTICE` 全文（§2 披露行现文）；`Resources/FilmProfiles/MANIFEST.sha256`
对账面；RESEARCH-PRE §2.3（三分口径——措辞正本）；M8-2 DECISIONS（
exposureEv 实现面引用）。

- **action**：
  1. 曝光语义负测组（IOPParity）：exposureEv 消费层终账——record 变 →
     缓存解不变→增益变；缓存键不含 exposure 项（M8-2 T2 断言的端到端
     扩臂）+ 宽容度 descriptor 在 exposureEv 变化下的响应面；DECISIONS
     落 D-M8-8 裁决登记（终账）。
  2. NOTICE 披露行升格：§2 消费披露语义从密度域投影扩为「full
     per-wavelength material-chain simulation (metameric reconstruction
     upstream of the material chain)」——我方文件可改；profile JSON/
     neutral_print_filters/MANIFEST.sha256 **字节零动**（MANIFEST 对账
     测试随批跑绿）。
  3. 用户可见措辞升格：README/help 面实际存在点批修（「物理流程建模，
     非光谱重放」→「光谱重建材质模拟（逐波长），非场景光谱重放」——
     grep 全仓定位实际存在点，逐点批修；xcstrings 值面含此措辞则同批）。
  4. AGENTS.md M3-3 增量节勘误行追加（光谱不可达注记收窄语——原文不改
     惯例）+ M3-2 RESEARCH-NOTES 勘误行（如有引用点）。
  5. 测试（IOPParity）：MANIFEST 对账（零漂移门——既有测试跑绿确认）+
     NOTICE §2 新披露语义存在断言（文本 fixture 级）。
- **验收标准（机检）**：
  - 构建绿；`git diff --stat` = NOTICE + AGENTS.md + （README/help 命中
    点）+ 一新测试文件；`Resources/FilmProfiles/profiles/` 与
    `neutral_print_filters.json` 与 `MANIFEST.sha256` 零 diff（git status
    核对）。
  - MANIFEST 对账测试绿；措辞旧串残留 grep（升格点全命中核对）。
  - exposureEv 负测组绿。
- **commit**: `docs(m83): revise spectral wording notice and pin exposure semantics`
- **回滚与偏差申报要求**：回滚 = revert 单 commit；偏差（措辞命中点清单/
  勘误行措辞）= DECISIONS 申报；**禁改 profile JSON/MANIFEST 字节**；**禁
  删历史文档原文**（勘误行追加）；**禁把 exposure 语义改成链头折入**（
  D-M8-8 翻案须晨审先例）。

## T5 — 全套 --all 收口对账（orchestrator 批准制）

- **action**：
  1. 取得 orchestrator --all 批准（派单申报：预算带 + skip 逐族清单）。
  2. machine-guard --wait → caffeinate -dis 包裹 → `Scripts/test-direct.sh
     --all`；运行中监视（8G 门 + MEMFAIL 机检 + Lightamer 进程资源观察
     ——AGENTS 资源监控节）；测试宿主清理先核 parentage（M2-7-3 先例）。
  3. ΔN 终账对账：基线 4206/41/0 → 终值（预期带 4266..4288）+ skip 逐族
     （41 基线 + 1b probe 族逐条申报）；MEMFAIL/贴线 bundle（IOP 7654 /
     IOPParity 5788 贴线注记）按 AGENTS 口径处置。
  4. gui 走查证据：迁移 UX 走查 + v2 档面板 readout 走查 + 导出递缝走查
     → `.work/gui-acceptance/m8/MANIFEST.md`（逐项证据）。
- **验收标准（机检）**：
  - --all 输出七 bundle 行全绿零 fail 零 MEMFAIL；TOTAL 行 = 终账。
  - 终值带对账（越带 = SUMMARY 申报理由）。
  - gui-acceptance MANIFEST 在库（走查项逐条证据路径）。
- **commit**: `test(m83): close out m8 with full suite reconciliation`
- **回滚与偏差申报要求**：--all 失败/MEMFAIL = 停手按 AGENTS 资源监控节
  处置（kill 权限 = 立即 + 事后报告）；越带 = SUMMARY 申报；禁跳过批准
  直跑 --all（流程违规）。

## T6 — SUMMARY/DECISIONS/VALIDATION 预备 + C 档停

- **action**：
  1. `Project.swift` 两新测试文件入对应 bundle 显式数组（App ×1：
     FilmPanelSpectralUI；IOPParity ×1：SpectralExposureSemantics）+
     BUNDLE-MAP 两行登记。
  2. `tuist generate` = 本批最后一个动作（L041）。
  3. M8-3-SUMMARY（逐任务记账 + ΔN 终账 + 全套对账 + gui 证据指针）+
     M8-3-DECISIONS（曝光语义终账 + 迁移 UX 形态 + 措辞命中点清单 + 各
     偏差）落盘。
  4. M8-VALIDATION 预备（phase 签核输入汇编：四 plan 终账 + 双臂 golden
     面 + probe 真值 + 走查证据索引）。
  5. 汇报 + **C 档停（VALIDATION 前——verify-work 结论给用户过目）**。
- **验收标准（机检）**：定向 bundle（App/IOPParity）全绿零回归；
  Project.swift diff = 恰两行；BUNDLE-MAP 在库；SUMMARY/DECISIONS/
  VALIDATION 预备在库；tuist generate 后无生成物入 git。
- **commit**: `docs(m83): summarize m8 phase and prepare validation`
- **回滚与偏差申报要求**：回滚 = revert 单 commit；禁漏 tuist generate；
  VALIDATION 本体 = 用户过目后的独立批（不在本 plan 范围）。

---

## 风险与回退

- **迁移 UX 面膨胀**：确认 sheet 文案/守卫细节发散 → 最小面纪律（一按钮
  一 sheet 一 commit；守卫三件钉死）；超面 = DECISIONS 申报并砍至最小。
- **--all 贴线 bundle 波动**：IOP/IOPParity 历史贴线（7654/5788MB 注记）
  ——先查重测顺序漂移（±3% 方差）再判真 MEMFAIL（AGENTS 口径）；光谱
  probe 族使 IOPParity 峰值上移是预期面（probe ③ 数据在 DECISIONS 引用）。
- **措辞批修漏点**：grep 定位 + 走查双确认（用户可见面命中点清单落
  DECISIONS；zh-audit 双 PASS 兜 xcstrings 面）。
- **已迁移档在回滚窗口**：T3 回滚后 process=2 文档 clamp 渲染 v1（M8-2
  同款窗口语义）——非损坏；DECISIONS 登记。

## Checker 关注点（独立反向核输入）

1. **Goal-backward**：RESEARCH §6.1 M8-3 行 ↔ T1-T6 逐项（面板平移 =
   T1 确认形 / descriptor 换臂 = T2 / 迁移 UX = T3 / VALIDATION = T6 预
   备）；M6-2 §6 挂账 ↔ T3 兑现。
2. **OQ 兑现核**：D-M8-6（NOTICE 三面——T4 逐面）/ D-M8-7（零新增 +
   adaptation 不暴露——T1 grep 组）/ D-M8-8（solve gain 终账——T4 负测
   组 + DECISIONS 登记）。
3. **红线核**：xcstrings 尾块 + zh-audit 双 PASS；UserDefaults 零新键；
   L057 缝（.runModal 零命中）；profile/MANIFEST 字节零动；历史文档勘误
   行追加非改写；--all 批准制 + parentage 纪律。
4. **SC 可机检性**：零 diff/grep 组/快照断言/对账式终账；走查证据逐条
   路径；ΔN 对账非死数。
