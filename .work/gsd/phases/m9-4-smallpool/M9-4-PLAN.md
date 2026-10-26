---
phase: M9-4
plan: v2
title: "M9-4 — 小件池：T1 ColorWheels v3 数学面（ApplyToneWheel 新 kernel + ConvertLegacy 转换 + golden 三面）/ T2 process v3 bump 五件套 + 双臂 + PipeCache 折键负测 + 迁移 UX 泛化 + 面板双形 / T3 LUT encodings 表扩（10 行 + 7 曲线 + 6 gamut）/ T4 尾件三件（Filmstrip stars + 双态 / Show in Finder / XPan ratio 三行）/ T5 收口"
wave: 1
depends_on: ["R6 + M9-1 + M9-2 + M9-3 收口让位（本站 = M9 末站；开工前核 GOAL-STATE 与四前站 SUMMARY 实数落基线表达式）"]
autonomous: true
requirements: ["research 正本 = phases/m9-4-smallpool/RESEARCH.md（§1 上游 v2 测绘 / §2 我方差距 / §3 process v3 迁移形态 / §4 尾件四件 / §5 差距矩阵 / §6 风险 / §7 OQ）", "裁决正本 = 同目录 CONTEXT.md（D-M9SP-1..9 全按 research 推荐〔OQ-2 甲形态带 planner 两补强 / OQ-6 三行值采纳候选集〕+ X1..X6 设计承接 + hazards 五条 + 红线 15 条 + 转写勘误四条）", "REQUIREMENTS M9SM-01..02（验收形态即各 T 验收源；M9SM-02「+24」按 OQ-3 修正 = 10 行 + 7 曲线 + 6 gamut）", "charter = ROADMAP §M9 站 4（S-M，ΔN +10..15；零依赖）", "全套对账锚 = R6 收口终值 4292/35/0（R6-SUMMARY:55 亲核）⊕ ΔN_M9-1..3（前站实数落）"]
success_criteria: "SC 全可机检——T1：ColorWheels.metal append grade_color_wheels_v3 + ToneWheelUniforms（14 float；现行 grade_color_wheels 逐字节保留——红线 2 唯一新 kernel 申报面）+ ResolveToneWheelKernelParams/ApplyToneWheels CPU 预解（X1 四公式 + 常数 kToneBlackEv=−6/kToneWhiteEv=+6/R=12）+ referenceV3 Float64 镜 + Params.offset additive optional（encodeIfPresent 字节零漂负测：Params() 编码 hash 常量钉死 + 旧 JSON 无 offset → nil tolerant decode）+ ColorWheelsLegacyConvert.swift 新建（lift→offset 精确 K=(color+luma)×B + FitLegacyGammaGain Gauss-Newton 25 采样/雅可比 1e-4/3×3 消元/≤20 迭代/收敛 1e-9，纯函数 GPL 头）+ DiscToChannelStops/ChannelStopsToDisc/ClampDiscPoint + golden 三面（kernel-vs-ref 参数点族含超域采样〔OQ-4〕/ 上游解析锚套件移植〔每轮+1 档 ΔEV≈1 + 分离比 ≥4× + 中性 ≤1e-6 + disc↔stops 往返 1e-4〕/ 转换锚〔lift→offset 精确 + 拟合 ≤0.03 档常见域 + ≈0.12 档极端域 + 不截断〕）+ NOTICE 上游条目；T2：RenderProcess 五件套（case v3 账本 doc-comment + all 尾插 + current 2→3〔RenderProcess.swift:90〕+ processVersion switch 补腿 + AGENTS 账本行）+ fork 点 ColorWheelsModule.process 读 piece.renderProcess exhaustive switch（.v1/.v2 冻结路径逐字节 / .v3 新 dispatch + params 镜像缓存 NSLock + 14-float memo 键=paramsHash）+ ModuleBoxing processForkHash default nil + ModuleBox 转发 + PixelPipe.prepareChain 折一处（逐 hunk 申报——红线 5 例外）+ 渲染入口穿线核验（未穿 9 调用点穿 doc 值 + THUMBNAIL guard 设计修订申报 + 豁免面登记——M-1 修订后口径）+ 缓存折键负测三件（同 params 字节 v1 vs v3 键不等 / legacy·v1·v2 键逐位恒等 / params 维不吞）+ 迁移 UX 泛化（evaluate gate 扩 hasFilmRecord||colorWheels 非中性 + editing 窗含 colorWheels / marker 泛化 film item→cw verbatim params item 二形 / panel_process_migrate_* 中性键族 / ProcessMigrationRow 双面板挂点）+ 面板双形 fork（v1/v2 三轮冻结视图逐字节 / v3 四轮 stops + D-H1 + 编辑投影消费 X2 转换器〔首编辑物化 offset 在场〕）+ GradeCatalog identityJSON 零改断言；T3：LutEncodingId 尾插 10 case + LutTransferCurve 尾插 7 case（encodeChannel/decodeChannel Float64 双落笔，常数 git show c740f7b 直取）+ gamuts 增 6 键（primaries/white 逐值照上游）+ all 表 10 行（peakNits 逐行照上游含 P3 48）+ golden（每曲线往返/单调/端点 + gamut 对拍 + 10 行 typed find + 端到端采样）+ 既有 17 行 9 gamut 既有曲线字节零触碰断言 + OCIO BSD 注记随 NOTICE；T4：FilmstripRowView stars 行（row.rating 直读——勘误① + ratingBadge 先例形 + AX id filmstrip.row.rating.<id>）+ editing/selected 双态分档核验（accent edge/selectedRing 保留）+ Show in Finder 三门（图库 grid contextMenu / Filmstrip contextMenu / 编辑器 Image 菜单——revealInFinder :174 先例同款）+ CropAspectPreset 尾插 3 case（65:24 / 2.75:1=dn(11,4) / 6:17=dn(17,6)）+ dn 臂 + picker 3 行 + ratio bits 双向映射臂 + zh 键族；T5：Project.swift 数组 + BUNDLE-MAP 登记行 + tuist generate 末位（L041）+ 定向 IOP+APP 全绿 + 全套 --all（orchestrator 预批 + 8G 门 + MEMFAIL + GUI ps 清零 + monitor 伴跑）带式对账 + zh-audit --check/--self-test 双 PASS + gui-acceptance m9-4 MANIFEST 走查配方 + AGENTS 键族/账本/约定正本回写"
estimated_tests: "+11..15（T1 +4..5 / T2 +3..4 / T3 +2..3 / T4 +2..3 / T5 0；charter 带 +10..15 内——下沿 11 高于 charter 10 因缓存负测三件不可并法〔H-SP1 主风险独立红线论证〕；一法多断言可压缩面已压：解析锚套件并法/golden 参数点族并法；收口轮按实数对账）"
test_bundles: [IOP, APP]
baseline: "带式 = R6 收口终值 4292/35/0（R6-SUMMARY:55 亲核）⊕ ΔN_M9-1（plan v2 估 +20..29，以 M9-1 SUMMARY 实数落）⊕ ΔN_M9-2（plan 估 +15..20，实数落）⊕ ΔN_M9-3（plan 估 +14..19，实数落）——本站大概率最后执行，开工前亲核实数落基线表达式"
expected_all: "基线链 ⊕ 本批 +11..15 → 终带 4352..4375（前站全取估带时；实数落后重算）；全套 --all 归 T5 收口轮 orchestrator 预批后跑"
red_lines:
  - "共用红线正本 = CONTEXT §红线 front-matter 15 条（v3 五件套 / 双臂 + 新 kernel 申报面唯一〔grade_color_wheels_v3〕/ PipeCache 折键 resolved-arm + 负测三件 / params 甲红线〔零 modversion·零 schema bump·旧档字节零改写·encodeIfPresent 零漂〕/ 封存面 17 件零 diff + 例外申报恰两处〔PixelPipe prepareChain 逐 hunk + ColorWheels.metal append 纪律面〕+ GradeCatalog identityJSON 零改 / LUT add-only / xcstrings 尾插 + zh-audit 双 PASS + V14 + 禁形 / GPL 归属不可延后 / 上游 git show 读法 / D-H1 + L057 / 测试落域 IOP+APP + L041 tuist 末位 / 带式对账 + 单重活 + GUI ps 清零 / UserDefaults 零新键 / commit-per-task + 产品面 issue 关联 / C 档门控）。"
  - "冻结臂逐字节主门：现行 GradeKernelGoldenTests colorWheels 两法（:508-555）原样跑绿即冻结臂 golden——body 零改（piece 缺省 .legacy → v1 臂）；改即违规。"
  - "转换不落盘红线：offset 缺席 shape 的转换只存在于渲染预解（memo）与面板编辑投影——history/sidecar 里的 params 字节在用户未于 v3 臂动轮前零变化；物化仅经 v3 面板首编辑 commit（D-M9SP-2 补强①）。"
  - "渲染入口穿线：一切渲染腿（FULL/PREVIEW/THUMBNAIL/EXPORT/子 run）thread doc 的 stored process——.legacy 缺省腿属 bug（v3 档缩略图/导出与主视图撕裂）；THUMBNAIL 腿现行 guard（PipeCoordinator.swift:2508-2514）是 M8-3 T3 显式 process 层设计决定（注释明文 thumbnail cache-key space never moves），本批穿 thumbnail = 修订该设计决定（DECISIONS 单独申报「M8-3 thumbnail guard 设计修订」+ M8-3 注释同批修订），非补漏；豁免面禁穿（SessionThumbnailRenderer Phase 8 禁改契约 + CullingView pristine 默认链——.legacy 即正确值）；清单正本 = D-M9SP-8 第四段（v2 修订后）+ T2 Action 3③；穿线批大概率触「超 10 行」停手线——触线属计划内申报（见裁定权归属钉预告）。"
files_modified:
  - LightamerIOP/Sources/ColorWheels/ColorWheelsModule.swift    # T1/T2：Params.offset additive + isIdentityV3 + DiscToChannelStops/ChannelStopsToDisc/ClampDiscPoint + ResolveToneWheelKernelParams + referenceV3 + params 镜像缓存（NSLock）+ process fork（piece.renderProcess switch）+ processForkHash override；frozen 打包/旧 static/reference 逐字节保留
  - LightamerIOP/Sources/ColorWheels/ColorWheels.metal         # T1：append grade_color_wheels_v3 + ToneWheelUniforms（14 float）；现行 grade_color_wheels 逐字节保留（红线 2）
  - LightamerIOP/Sources/ColorWheels/ColorWheelsLegacyConvert.swift # T1：新建——ConvertLegacyColorWheel + FitLegacyGammaGain 纯函数（上游 e1effd8 直译，GPL 头）
  - LightamerCore/Sources/Pipe/RenderProcess.swift             # T2：case v3（账本 doc-comment）+ all 尾插 + current 2→3（:90）+ processVersion switch 补腿（:167-172）
  - LightamerCore/Sources/Pipe/ModuleBox.swift                 # T2：ModuleBoxing processForkHash default nil + ModuleBox 转发（~6 行）
  - LightamerCore/Sources/Pipe/PixelPipe.swift                 # T2：prepareChain 折一处（:946-976 域，逐 hunk 申报——红线 5 例外①）
  - App/Sources/Lightamer/EditorState+FilmMigration.swift      # T2：evaluate gate 泛化（hasColorWheelsEdits 输入 + editing 窗）——类型/文件名保持
  - App/Sources/Lightamer/State/PipeCoordinator.swift          # T2：runProcessMigration guard/marker 泛化（cw verbatim item 二形）+ colorWheels 读面（非中性判定）+ 渲染腿穿线（:2001/:2073/:2161/:2607/:2626 五点穿 doc 值 + :2508-2514 thumbnail guard 设计修订〔M-1〕）
  - App/Sources/Lightamer/UI/Shell/FilmPanelView.swift        # T2：ProcessMigrationRow copy 中性化（panel_process_migrate_*）+ 双面板挂点改造
  - App/Sources/Lightamer/UI/Inspector/ColorWheelsPanelView.swift # T2：面板双形 fork（v3 四轮 stops Section + Offset + D-H1 + 编辑投影物化 + 迁移行挂点；v1/v2 三轮视图逐字节）
  - LightamerIOP/Sources/Lut3d/LutEncodingCatalog.swift        # T3：LutEncodingId 尾插 10 case + all 表 10 行 + gamuts 6 键（add-only）
  - LightamerIOP/Sources/Lut3d/LutTransferMath.swift           # T3：LutTransferCurve 尾插 7 case + encode/decode 双落笔（add-only）
  - App/Sources/Lightamer/UI/Shell/FilmstripView.swift        # T4：stars 行 + 双态分档核验（row.rating 直读——勘误①）+ 行 contextMenu Show in Finder
  - App/Sources/Lightamer/UI/Overlay/CropOverlayHost.swift    # T4：CropAspectPreset 尾插 3 case + dn 臂
  - App/Sources/Lightamer/UI/Inspector/CropPanelView.swift    # T4：picker 3 行 + ratio bits 双向映射臂（:36-149 域）
  - App/Sources/Lightamer/Library/Views/LibraryGridView.swift # T4：grid 行 contextMenu Show in Finder
  - 编辑器 Image 菜单正本（execute 期定位——AIEnhance 菜单同区）# T4：Finder 第三门
  - Resources/Localizable.xcstrings                           # T2/T4：panel_wheels_{shadows,midtones,highlights,offset} + tooltip 族 + panel_process_migrate_* 5 键（title/body/button/cancel/confirm——m-1：film 族 5 键亲核，confirm 随 copy 中性化）+ action_show_in_finder + panel_crop_aspect 三键（尾块纯插入，~16-18 静态键）
  - NOTICE                                                    # T1/T3：Alcedo color_wheel_tone + encoding catalog 条目 + OCIO 2.5.1 BSD 注记
  - Tests/LightamerTests/ColorWheelsToneWheelGoldenTests.swift # T1：新建（IOP）
  - Tests/LightamerTests/ColorWheelsLegacyConvertTests.swift   # T1：新建（IOP）
  - Tests/LightamerTests/ProcessForkCacheKeyTests.swift       # T2：新建（IOP——PipeHash 纯函数域 + fork hash 断言）
  - Tests/LightamerTests/ProcessMigrationGateTests.swift      # T2：新建（APP——evaluate 五态表驱动 + marker 双形 + 面板 fork 读投影）
  - Tests/LightamerTests/LutEncodingExpansionTests.swift      # T3：新建（IOP）
  - Tests/LightamerTests/SmallPoolUITests.swift               # T4：新建（APP——stars/ratio 映射/Finder AX 可达）
  - Project.swift                                             # T5：六新测试文件入 IOP/APP 数组（显式清单）
  - .work/gsd/phases/m2-4-0-test-bundles/M2-4-0-BUNDLE-MAP.txt # T5：六行落域登记
  - AGENTS.md                                                 # T5：process 账本 v3 行 + M9-4 约定正本节 + 键族登记
  - .work/gsd/phases/m9-4-smallpool/M9-4-SUMMARY.md           # T5：执行摘要（逐任务记账 + ΔN 终账）
  - .work/gsd/phases/m9-4-smallpool/M9-4-DECISIONS.md         # T5：裁定记录（穿线核验清单结论 + M8-3 thumbnail guard 设计修订〔M-1①：单独条目，区别于 9 点补漏〕+ 豁免面判断〔m-3：SessionThumbnailRenderer Phase 8 禁改/CullingView pristine 链〕+ 穿线实际行数 + marker 泛化定形 + XPan 值 + 编辑器菜单定位 + 偏差登记）
---

# Plan M9-4 — 小件池（ColorWheels LGG+Offset 主件 + 尾件四件）

> **裁决正本** = `CONTEXT.md`（D-M9SP-1..9 + X1..X6 + hazards 五条 + 红线
> 15 条 + 勘误四条；晨审可推翻）；规格正本 = `RESEARCH.md`（§1 上游 v2
> 测绘 / §3 迁移形态 / §4 尾件；planner 抽核 ~25 点吻合 + 勘误四条见
> CONTEXT——①Filmstrip rating 已通 / ②上游工作区 stale / ③迁移通道泛化
> 面实核 / ④peakNits 逐行照上游）。本 plan = LightamerIOP + Core Pipe 两
> 点 + App UI 泛化，**零新 SPM、零新 iop（V50Order 零新增）、零 sidecar
> schema bump、UserDefaults 零新键**。
>
> **裁定权归属钉**：执行中如触「必须扩面」（sidecar schema / HistoryStack
> / GradeCatalog identityJSON / 再加新 kernel / 缩略图·导出腿穿线修正超
> 10 行）= 停手上报，不得自裁扩界。**穿线超线预告（v2，M-1③）**：渲染
> 入口穿线批（9 未穿调用点 ×1-3 行 + thumbnail guard 修订 + M8-3 注释
> 同步，见 T2 Action 3③）**预期触「超 10 行」停手线**——触线停手上报
> 属计划内流程而非方案失败；本 plan 已预授权该缝穿线，上报后按
> DECISIONS 登记实际行数与逐点清单即继续（其余四类扩面照旧硬停）。
>
> **执行序**：T1 → T2 → T3 → T4 → T5。每任务独立 commit（Conventional
> Commits 全英文、只 add 相关文件、不 push、产品面带 issue ref）；重活起
> 跑前过 `Scripts/machine-guard.sh` + GUI 实例 ps 清零验证；开工前核
> `.work/config.toml [gsd]` paused/auto 与 GOAL-STATE 续接点。
>
> **C 档停**：T5 闭环后停汇报（M9-4 = M9 末站；phase VALIDATION 另批）。

## ΔN 预算表（逐任务，本 plan 分账带 +11..15；越带须申报理由）

| 任务 | 测试增量 | 构成 | 落点 |
|---|---|---|---|
| T1 v3 数学面 | **+4..5** | golden 三面（kernel-vs-ref 参数点族含超域 / 解析锚套件 / 转换锚）+ v3 identity 逐位 + params 字节零漂/round-trip | IOP（ColorWheelsToneWheelGoldenTests + ColorWheelsLegacyConvertTests） |
| T2 bump+折键+迁移 | **+3..4** | 缓存折键负测三件（不可并法——H-SP1 主风险独立红线论证）+ 五件套/入口穿线 + 迁移 gate 五态/marker 双形/面板 fork | IOP（ProcessForkCacheKeyTests）+ APP（ProcessMigrationGateTests） |
| T3 LUT 表扩 | **+2..3** | 7 曲线 golden（往返/单调/端点，一法多曲线并法）+ gamut 对拍 + 10 行 lookup/端到端 | IOP（LutEncodingExpansionTests） |
| T4 尾件三件 | **+2..3** | stars 行表驱动 + XPan dn·bits 双向 + Finder AX 可达 + 双态视觉模型 | APP（SmallPoolUITests） |
| T5 收口 | **0** | docs + Project.swift 数组 + BUNDLE-MAP + tuist generate | — |
| **合计** | **+11..15** | 基线链 ⊕ 本批 → 终带 4352..4375（前站实数落后重算） | 六新测试文件（四 IOP + 二 APP） |

## 已定裁决（生效值，硬约束，不得重开）

1. **冻结臂锚定我方现行字节**（D-M9SP-1）——含 `1/γ_leg` 换算形态；现行
   golden 原样保留即冻结主门。
2. **params 甲形态 + 判别子/镜像两补强**（D-M9SP-2）——offset 在场与否
   = v1/v2 语义判别子；首编辑物化；模块 params 镜像（NSLock）供 v3 全
   保真预解；frozen 16-float 打包逐字节不动。
3. **缓存折键 = prepareChain 级 per-box processForkHash、discriminator =
   resolved arm**（D-M9SP-8）——v1/v2/legacy 零折键字节恒等；负测三件
   T2 硬门。
4. **LUT 范围 = 10 行 + 7 曲线 + 6 gamut**（D-M9SP-3）；peakNits 逐行照
   上游（P3 行 48）。
5. **XPan 三行 = 65:24 / 2.75:1 / 6:17**（D-M9SP-6，晨审可直改值）。
6. **迁移 UX 单行泛化 + marker 二形**（D-M9SP-7）——film item 优先、cw
   verbatim item 兜底；中性 copy 键族。
7. **Filmstrip 双态轻臂**（D-M9SP-5）——语义保留 + stars 补齐 + 走查
   核验，不重做上游视觉。

## read_first（全局，每任务开工前过一遍）

- `.work/gsd/phases/m9-4-smallpool/CONTEXT.md`（D-M9SP-1..9 + X1..X6 +
  hazards + 红线 15 条 + 勘误四条 + 晨审索引）
- `.work/gsd/phases/m9-4-smallpool/RESEARCH.md` §1-§4/§6-§7
- 上游直译源（只读，**一律 `git show <sha>:<path>`，禁工作区**——勘误②）：
  `e1effd8:alcedo_studio/src/include/edit/operators/models/color_wheel_tone.hpp`
  （四公式/常量/ToneWheelKernelParams/ConvertLegacy 签名——planner 亲核
  与 research 逐条吻合）+ `…/models/color_wheel_tone.cpp` + `…/models/
  color_wheel_model.hpp`（kDiscMaxStops=1.0/kMasterMaxStops=2.0/payload
  四轮）+ `e1effd8:alcedo_studio/tests/edit/graph/color_wheel_tone_test.cpp`
  （解析锚 265 行）+ `c740f7b:alcedo_studio/src/color/color_encoding_catalog.cpp`
  （10 行 + 6 gamut + 7 曲线常数）+ `7ccb0ec` Filmstrip tiles QML（T4
  视觉参照）
- 我方正本：`ColorWheelsModule.swift` / `ColorWheels.metal` /
  `RenderProcess.swift`（:88-90 bump 位 + :108-172 账本）/
  `PipeCacheKey.swift`（:48-55 链语义）/ `PixelPipe.swift`（:946-976
  prepareChain + :995-999 stamp + :2209/:2276 入口）/
  `EditorState+FilmMigration.swift` / `PipeCoordinator.swift`（:851-875
  迁移 + :2510-2553 穿线）/ `WorkspaceModel.swift`（:379-410 carrier）/
  `ParamsCoding.swift`（sortedKeys 纪律）/ `LutEncodingCatalog.swift` +
  `LutTransferMath.swift` / `FilmstripView.swift` / `LibraryGridView.swift`
  （:562-565 ratingBadge 先例）/ `CropOverlayHost.swift`（:25-40 dn）/
  `CropPanelView.swift`（:36-149）/ `PostExportActions.swift`（:174）
- `.work/LESSONS.md` L013（fork tag 走 StableHash）/ L041（tuist 末位）/
  L014（本批无计时面，备忘）/ L009（无文件落盘面，备忘）
- `.work/config.toml [gsd]` paused/auto + GOAL-STATE 续接点

---

## T1 — ColorWheels v3 数学面（kernel + 预解 + 转换器 + params + golden 三面）

> 依赖：无（本 plan 首任务）。产出 = v3 数学全部纯面 + kernel + 测试锚，
> **不带 process fork 接线**（T2 接线——T1 的 v3 dispatch 以直调/单测形
> 验证，process() fork 开关 T2 落）。

### Action

1. **`ColorWheelsLegacyConvert.swift` 新建**（LightamerIOP/ColorWheels/）：
   `convertLegacyColorWheel(_ legacy: LegacyValues) -> Params`（offset 在
   场 quad 输出）+ `fitLegacyGammaGain`（Gauss-Newton，X2 参数照单：25
   采样 −6..+6EV / 数值雅可比 step 1e-4 / 3×3 高斯消元 / ≤20 迭代 / 收敛
   <1e-9）+ lift→offset 精确腿 `K = (color + luma) × CE_ACESCC_B`。文件
   头 GPL 归属（上游 `e1effd8` 版权声明 + 修改标注）；NOTICE 首条目随本
   commit。
2. **`ColorWheelsModule.swift` 数学面**：①`Params.offset:
   ColorWheelControl?` additive（缺省 nil；synthesized Codable 走
   encodeIfPresent——init 增加 offset 缺省参数，既有构造点零改）；
   ②`isIdentityV3`（四轮全中性 0 基 + offset 判 v2 形）；③新盘族
   `discToChannelStops`/`channelStopsToDisc`/`clampDiscPoint` + 常量
   `discMaxStops = 1.0`/`masterMaxStops = 2.0`（**新增常量面**；v1 的
   strengthRange/luminanceRange/kEpsilon/cdlDelta/colorOffset(from:) 原
   样保留——冻结视图与 frozen 打包消费）；④`resolveToneWheelKernelParams
   (_ params: Params) -> ToneWheelKernelParams`（14 float；offset 缺席
   shape 先过 convertLegacy——effective 语义单源）+ `applyToneWheels`
   CPU 标量式；⑤`referenceV3(acescc:params:)` Float64 镜；⑥params 镜像
   缓存（`lastParams/lastLock`——commitParams 写、process 读，uniformsBuffer
   同款纪律）+ 14-float memo（键 = paramsHash）。
3. **`ColorWheels.metal` append**：`ToneWheelUniforms`（14 float：offset3/
   liftScale3/gammaExp3/gainScale3/toneBlack/toneRange）+ kernel
   `grade_color_wheels_v3`（ApplyToneWheels 直译 + 中性早退 flag）。
   **现行 `grade_color_wheels` + `ColorWheelsUniforms` 逐字节保留**（红线
   2——本批唯一新 kernel 申报面）。
4. **golden 三面 + identity + params 零漂**（两新测试文件，IOP）：
   - `ColorWheelsToneWheelGoldenTests`：v3 identity 四轮中性逐位 blit；
     kernel vs referenceV3 参数点族（四轮各一 + combined + ACEScc 编码域
     外采样点〔OQ-4——t ∉ (0,1) 分支边界像素级断言〕）；上游解析锚移植
     （每轮 +1 档目标影调 ΔEV≈1 / Lift-Gain 分离比 ≥4× / 中性全影调
     ≤1e-6 / disc↔stops 往返 1e-4 / 越界截单位圆——上游 test 数值对照）；
     `Params()` 编码 hash 常量钉死（字节零漂，H-SP2）+ offset 在场/
     缺席 round-trip + 旧 JSON 无 offset → nil。
   - `ColorWheelsLegacyConvertTests`：lift→offset 精确逐通道；拟合误差
     常见参数域 ≤0.03 档 + 极端域（旧 lift ≈1.4 档同调 gamma）≈0.12 档
     带内；拟合 K 拆均值/零均值 + disc 反演截单位圆；不截断（渲染值 =
     拟合值断言）；v3 shape round-trip。
5. 现行 `GradeKernelGoldenTests.swift` colorWheels 两法（:508-555）**零
   改**（冻结臂 golden——缺省 piece `.legacy` → v1 臂逐字节现状）。

### 验收机检

- `grep -c "grade_color_wheels_v3" LightamerIOP/Sources/ColorWheels/ColorWheels.metal` ≥ 1；现行 kernel 函数体 md5 与 HEAD 同值（冻结主门）。
- 新两测试文件全绿（`Scripts/test-direct.sh --bundle IOP` 定向）；identity 逐位断言 accuracy: 0。
- `Params()` 编码 hash == 钉死常量（负测在册）。
- 上游解析锚套件数值与 `git show e1effd8:…test.cpp` 断言值同源（tolerance 注释引上游行）。
- NOTICE 含 Alcedo 条目；`grep -rn "runModal(" App/Sources` 零命中（顺带）。

---

## T2 — process v3 bump 五件套 + 双臂 fork + PipeCache 折键 + 迁移 UX 泛化 + 面板双形

> 依赖：T1（v3 数学面在位）。本任务 = 全批最高风险缝集中地（H-SP1/H-SP4）。

### Action

1. **五件套**（D-M9SP-9 照单）：`RenderProcess.swift` 追加 `case v3`
   （doc-comment 账本：ColorWheels LGG+Offset 代际——fork 点 =
   ColorWheelsModule.process；缓存折 = processForkHash「非 legacy 才折
   〔resolved-arm 收窄形〕」）+ `all` 尾插 `.v3` + `current` 2→3（`:90`）
   + `processVersion` switch 补腿（`:167-172`——编译器先行指向）+
   AGENTS.md process 账本行（T5 统一回写亦可，本任务先落账本行）。
2. **渲染 fork**：`ColorWheelsModule.process` 读 `piece.renderProcess`
   → `RenderProcess.resolving` exhaustive switch：`.v1/.v2` → 现 dispatch
   路径**逐字节**（frozen buffer + `grade_color_wheels`）；`.v3` →
   `resolveToneWheelKernelParams(effective(lastParams))` + memo + dispatch
   `grade_color_wheels_v3`。IOPiece stamp（M6-2-01 T2）预留消费位兑现，
   零新线程面。
3. **缓存折键**（D-M9SP-8）：①`ModuleBox.swift`：`ModuleBoxing` 增
   `processForkHash(_ renderProcess: RenderProcessVersion) -> UInt64?`
   协议要求 + extension default nil（全模块零改）；`ModuleBox` 转发到
   module（ColorWheelsModule 实现：resolved == .v3 → `StableHash.hash(
   "lightamer.colorwheels.v3")`，否则 nil）。②`PixelPipe.prepareChain`
   （`:946-976` 域）：enabled 分支折 `running = chain(running,
   box.paramsHash)` 后追加 `if let fork = box.processForkHash(renderProcess)
   { running = chain(running, fork) }`——**恰一处、逐 hunk 申报**（红线 5
   例外①；M6-2 IOPiece 注释预留缝 + M8-2 同文件 fork 先例）。③**渲染
   入口穿线（M-1 修订：显式清单正本，机检面 `grep -rn
   "RenderPipeline.process" App/Sources LightamerCore/Sources`）**：
   - **已穿（正资产，核验零工作量）**：coordinator 主渲染双路
     （`PipeCoordinator.swift:2521/:2543` 传 `migratedProcess`）+ EXPORT
     主腿（`ExportRenderer.swift:550/:562` `renderProcess:
     documentProcess`）。
   - **未穿 9 调用点（全部 `.legacy` 缺省，逐点改穿 doc stored 值）**：
     `QuickLookRenderer.swift:287/:296`（QuickLook 预览）/
     `PipeCoordinator.swift:2001`（eyedropper 线性链）/`:2073`
     （followEdgesSurface 层子 run）/`:2161`（filmic auto 采样）/
     `:2607/:2626`（EDR display override 双路）/`ColorMatchService.swift
     :205/:214`（colormatch 提取）——v3 文档下吸管读数/自动黑白键/EDR
     预览/QuickLook/colormatch/edge surface 若不穿即与主视图不同臂。
   - **THUMBNAIL guard = M8-3 设计决定的修订（非补漏）**：主渲染双路的
     `guard resolution != .thumbnail`（`PipeCoordinator.swift:2508-2514`，
     注释明文「thumbnail cache-key space never moves」）是 M8-3 T3 显式
     process 层决定——本批删 guard 让 thumbnail 穿 doc 值 = **修订该
     决定**，M8-3 注释同批改写；DECISIONS **单独申报**「M8-3 thumbnail
     guard 设计修订」条目（区别于上述 9 点的补漏性质）。
   - **豁免面（禁穿，.legacy 即正确值；判断登记 DECISIONS——m-3）**：
     `SessionThumbnailRenderer.swift:42/:59`（文件头「Phase 8 contract
     （禁改）」契约 + legacy session 库无 process 载体，机械套「一切
     渲染腿」会撞禁改契约）；`CullingView.swift:227`（culling pristine
     默认链 `makeDefaultChain()` + 每次新 UUID + throwaway cache，无
     doc stored process 可穿）。
   - **超线预告**：本缝（9 点 ×1-3 行 + guard 修订 + 注释同步）预期触
     「超 10 行」停手线——触线按裁定权归属钉预告走计划内申报（DECISIONS
     记实际行数 + 逐点清单），非方案失败。
4. **缓存折键负测三件**（`ProcessForkCacheKeyTests`，IOP）：
   `PipeHash.upstream` 表驱动——①同 paramsHash 列表 + v1 vs v3 臂 →
   链 hash 不等；②legacy/v1/v2 臂 → 链 hash 与折前逐位恒等（零漂）；
   ③v3 臂 paramsHash 变更 → 链 hash 翻转（参数维不吞）+ fork tag 常量
   钉死（L013）。
5. **迁移 UX 泛化**（D-M9SP-7）：①`EditorState+FilmMigration.swift`：
   `evaluate` 输入扩 `hasColorWheelsEdits: Bool`（gate = hasFilmRecord ||
   hasColorWheelsEdits；editingInFlight 语义注记扩 colorWheels 窗——实
   际守卫读 coordinator 面）；②`PipeCoordinator.runProcessMigration`：
   guard 扩；marker 二形——film 记录在场 = M8-3 film item VERBATIM（零
   diff），缺席 = colorWheels verbatim params item（同
   `history_process_migrate` label；params 零 diff commit 形）；
   ③`FilmPanelView` ProcessMigrationRow copy 中性化
   （`panel_process_migrate_*` 新 5 键：title/body/button/cancel/**
   confirm**——m-1 勘正：film 族现役即 5 键〔xcstrings 亲核〕，迁移行
   保留 confirm sheet〔红线 10 L057 形〕故 confirm 键必然随 copy 中性化；
   `panel_film_migrate_*` 留册停引用）+ ColorWheelsPanel 挂同一行（单行
   单动作）；④fit 残差如实文案
   （body 键含「拟合近似非逐位」声明——H-SP3）。
6. **面板双形 fork**（`ColorWheelsPanelView`）：面板模型读
   `coordinator.documentProcessVersion`（FilmPanelModel :245-250 同通道）
   ——v1/v2 档 = 现三轮视图**逐字节**（冻结视图与冻结渲染一致）；v3 档
   = 四轮 Section（Shadows/Midtones/Highlights/Offset——`panel_wheels_
   shadows/midtones/highlights/offset` 新键 + 英文副标题 + tooltip）+
   stops 域（discMaxStops/masterMaxStops 单源常量）+ D-H1 三段 + 编辑投影
   `effective(params) = offset == nil ? convert : params`（首编辑物化
   offset 在场——D-M9SP-2 补强①）。**v1/v2 档面板路径零 diff 断言**。
7. `ProcessMigrationGateTests`（APP）：evaluate 五态表驱动（film-only /
   cw-only / 双有 / 双无 / editingInFlight）+ marker 二形 + 面板 fork
   读投影（v3 视图消费转换后基线）。

### 验收机检

- `RenderProcess.all == [.v1, .v2, .v3]` + `current.rawValue == 3` 单测；`git diff` PixelPipe.swift **恰 prepareChain 一 hunk**（逐 hunk 申报豁免——红线 5）。
- 负测三件全绿；fork tag 常量钉死。
- `grep -rn "processVersion(for\|documentProcessVersion" App/Sources/Lightamer/UI/Inspector/ColorWheelsPanelView.swift` 面板 fork 读面在册；v1/v2 面板路径零 diff（diff 审）。
- `grep -c "panel_film_migrate" App/Sources` 引用归零（键留册）；`panel_process_migrate_*` 5 键（含 confirm——m-1）xcstrings 尾插。
- GradeCatalog.swift / GradeKernelGoldenTests.swift colorWheels 段 / HistoryStack.swift / LightamerSidecar.swift `git diff` 零（封存 + 冻结主门）。
- 定向：`Scripts/test-direct.sh --bundle IOP`（含新负测）+ `--bundle App`（迁移 gate）全绿。

---

## T3 — LUT encodings 表扩（10 行 + 7 曲线 + 6 gamut + golden）

> 依赖：无硬依赖（与 T1/T2 并行面，但单重活纪律下串行排 T3 位）。纯表
> 数据 + Float64 曲线族，add-only。

### Action

1. **`LutTransferMath.swift`**：`LutTransferCurve` 尾插 7 case（flog2 /
   clog2 / log3g10 / bmdFilmGen5 / davinciIntermediate / dlog / gamma26）
   + `encodeChannel`/`decodeChannel` exhaustive switch 双落笔（Float64
   正逆对；常数 `git show c740f7b:…color_encoding_catalog.cpp` 直取——
   OCIO 2.5.1 port 注记入文件头 + NOTICE 补条）。
2. **`LutEncodingCatalog.swift`**：`gamuts` 增 6 键（sgamut3cine /
   redwidegamutrgb / bmdwg_gen5 / davinci_wide_gamut / dgamut / p3dci——
   primaries/white 逐值照上游矩阵）；`LutEncodingId` 尾插 10 case（id
   拼写照上游 `c740f7b`：sony_slog3_sgamut3cine 等——**X5 十 case 列表
   为正本**；m-2 勘正：id 拼写对上游属 X5/勘误④（peakNits）面，原引
   「勘误③」系笔误——勘误③是 M8-3 迁移通道泛化面）；`all` 表增
   10 行（scene 7 + display 3；peakNits 逐行照上游——p3d65_gamma26 =
   **48**；`linearRec2020` 行位置不动）。
3. **`LutEncodingExpansionTests`**（IOP）：每曲线正∘逆恒等（1e-12 级）+
   单调 + 端点；6 gamut primaries/white 与上游表逐值对拍（硬编码上游值
   断言）；10 行 `find(id:)` typed lookup + 全 27 行 id 唯一性 + referral/
   gamut 一致性 + 端到端 encode→decode 采样往返；**既有 17 行 + 9 gamut
   字节零触碰断言**（all 前缀 == 旧 17 行序列）。
4. NOTICE OCIO 注记（若 T1 未落则本任务补）。

### 验收机检

- `LutEncodingCatalog.all.count == 27` + `gamuts.count == 15` 单测；旧行前缀恒等断言在册。
- 曲线 golden 全绿（定向 IOP）；常数与上游逐值对拍在册（H-SP5 消解）。
- `git diff` Lut3d 件 = 纯 append（add-only——红线 6）。

---

## T4 — 尾件三件（Filmstrip stars + 双态 / Show in Finder / XPan ratio）

> 依赖：无（纯 App UI）。勘误①生效——stars = 纯 FilmstripView 改动。

### Action

1. **Filmstrip stars + 双态**（`FilmstripView.swift`）：`FilmstripRowView`
   caption 区加星行（`row.rating` 直读——`LibraryImageRow.rating` 已通；
   `ratingBadge` 先例形：★ 重复 min(rating,5) + 0 值「–」占位 + AX id
   `filmstrip.row.rating.<row.id>`）；editing/selected 双态分档核验
   （accent edge = editing、selectedRing = selected 语义保留；视觉层次
   走查项入 MANIFEST——不足则调 token 不改结构，D-M9SP-5）。
2. **Show in Finder 三门**：图库 grid 行 contextMenu
   （`LibraryGridView`）+ Filmstrip 行 contextMenu + 编辑器 Image 菜单
   （AIEnhance 菜单同区——正本 execute 期 grep 定位，DECISIONS 登记）；
   `NSWorkspace.shared.activateFileViewerSelecting([url])`
   （`PostExportActions.revealInFinder :174` 先例同款；L057 无涉）。zh
   键 `action_show_in_finder` + 各门 AX id（`library.grid.action.finder` /
   `filmstrip.action.finder` / `menu.image.finder`）。
3. **XPan ratio 三行**（`CropOverlayHost.swift` + `CropPanelView.swift`）：
   `CropAspectPreset` 尾插 3 case（rawValue "65:24" / "2.75:1" / "6:17"）
   + `dn` 臂（(65,24) / (11,4) / (17,6)——d ≥ n 纪律）+ picker 3 行
   （`panel_crop_aspect_65x24` / `_2_75x1` / `_6x17` 新键）+ ratio bits
   双向映射臂（`CropPanelView.swift:36-149` 域——N/D 整数对入现 Int 存储，
   零 schema 影响）。
4. **`SmallPoolUITests`**（APP）：stars 行渲染表驱动（rating 0-5 + nil）+
   AX id 可达；XPan dn/bits 双向 + picker 三行；Finder 三门 AX 可达 +
   缺文件 typed degrade（reveal 前存活性检查——revealInFinder 先例同款
   语义）。
5. xcstrings 尾块纯插入（本任务键：action_show_in_finder + crop 三键；
   panel_wheels/panel_process_migrate 族已随 T2 落）。

### 验收机检

- 定向 `--bundle App` 全绿；三 AX id 在树断言。
- `grep -n "ratio65x24\|65:24" App/Sources/Lightamer/UI/Overlay/CropOverlayHost.swift` case + dn 臂在册；旧 7 档行为零 diff（dn 表驱动回归）。
- zh-audit 增量键全在册（本任务 4 键）。

---

## T5 — 收口（Project.swift/BUNDLE-MAP/tuist + 定向 + 全套带式 + zh-audit + 走查配方 + 账本回写）

### Action

1. **L041 三件**：六新测试文件入 `Project.swift` 对应 bundle 显式数组
   （四 IOP + 二 APP）+ `M2-4-0-BUNDLE-MAP.txt` 六行落域登记 +
   `tuist generate` **恒为该批最后一个动作**。
2. **定向全绿**：`Scripts/test-direct.sh --bundle IOP` + `--bundle App`
   （重活前 machine-guard + GUI ps 清零验证）。
3. **全套带式对账**（orchestrator 预批 + 8G 门 + MEMFAIL 机检 + monitor
   伴跑 + caffeinate -dis + 测试宿主清理 parentage 核验）：基线链 =
   4292/35/0 ⊕ ΔN_M9-1 ⊕ ΔN_M9-2 ⊕ ΔN_M9-3（**开工前亲核四前站 SUMMARY
   实数落**）⊕ 本批实数 → 终值落 SUMMARY；skip 增量逐族申报。
4. **zh-audit**：`Scripts/zh-audit.py --check` + `--self-test` 双 PASS
   （本批静态键全族：panel_wheels 4 + tooltip + panel_process_migrate 5 +
   action_show_in_finder + crop 3 ≈ 16-18 键——SUMMARY 键清单并集对账，
   动态族零新增〔全静态键显式〕；m-1 后键数与 xcstrings 尾插对账）。
5. **走查配方**：`.work/gui-acceptance/m9-4/MANIFEST.md`——v3 档四轮面
   板操作（四轮各拖 + strength/luma 域 + reset）/ v2 档冻结视图 + 迁移行
   确认 sheet + 升号后拟合观感并排（H-SP3 验收）/ v2 档升号前后缓存不撞
   （切图往返观察重渲）/ stars 行 + 双态 / Finder 三门 / XPan 三档裁切。
6. **账本回写**：AGENTS.md process 账本 v3 行 + M9-4 约定正本节（v3 数学
   面/折键/迁移泛化/LUT 扩/stars·Finder·XPan）+ 键族登记；TODO/LESSONS
   同批（新教训随件）。
7. **SUMMARY/DECISIONS**：逐任务记账 + ΔN 终账 + DECISIONS（穿线核验清
   单结论 / marker 泛化定形 / XPan 值 / 编辑器菜单定位 / fit 残差文案 /
   偏差登记）。

### 验收机检

- `tuist generate` 后构建绿（六新文件编译进对应 target）。
- 全套终值 = 基线链 ⊕ 本批实数（SUMMARY :对账行）；ΔN 越带申报理由在册。
- zh-audit 双 PASS；BUNDLE-MAP 六行在册与 Project.swift 数组一致。
- AGENTS 账本/键族/约定节在册；`git log` 每任务一 commit、产品面 commit
  带 issue ref、`.work/gsd/**` 免关联。

---

## 风险节（plan 级复述 + 绑定）

1. **PipeCache 双臂缓存错配（最高风险）**：甲形态 params 字节不变 → 三臂
   同 paramsHash → 无折则共缓存平面互污；box hash 在 setParams 时刻提交，
   升号不触发。**消解 = T2 折键（run 级 prepareChain + resolved-arm
   discriminator）+ 负测三件硬门**（D-M9SP-8/X3）；execute 期另做一次
   实跑观察（v2 档渲染 → 升号 → 画面必变〔拟合近似〕→ 降回不可能〔无
   面〕——T5 走查配方第三项）。
2. **ColorWheels golden 重钉清单（凡涉面枚举）**：现行 identity + 4 参数
   点 golden（**零改**——冻结主门）；新增 = v3 identity/v3 kernel-vs-ref/
   解析锚/转换锚/params 零漂/fork 负测；**凡 colorWheels 涉面测试**
   （AdjustmentTransferTests / GradeParamsCodingTests /
   EditorStackRoutingTests / CatalogAddFaceTests 持 params 字面量）——
   additive optional 缺省 nil 保证旧构造点编译零改，encode 字节零漂保证
   hash 断言零改；若某测试因新增 API 面需触，逐处登记 DECISIONS（预期
   零触）。
3. **迁移 UX 复用边界（两代迁移并存）**：M8-3 film 通道（gate = film 专属
   + film marker）与本批泛化（gate 二源 + marker 二形）并存——**单行单
   动作**双面板挂点防双行；v2 档文档观感链 = 冻结逐位 → 升号 → 拟合近似
   （非逐位，文案如实）；marker 优先 film item（M8-3 语义零变），cw
   verbatim item 为兜底新增（label 同族）；类型/文件名保持
   `FilmMigrationAction`（历史沿革——DECISIONS 注记泛化史）。
4. **封存面纪律**：PixelPipe prepareChain 一 hunk（逐 hunk 申报豁免）+
   ColorWheels.metal append（纪律面登记）= 全批例外恰两处；GradeCatalog
   identityJSON **天然零改**（m-4 勘正措辞：`defaultLook` **无 colorWheels
   identityJSON 条目**——`NodeOwnershipCatalog.swift:297` 亲核仅
   exposure/contrast/saturation 三条，v3 臂转换不触 catalog，「零改」
   结论不变、原「v1 形 pristine 单源」论证无实体对象；若执行中发现
   identityJSON 消费面逼改 = 停手上报）。
5. **入口穿线遗漏（M-1 修订后口径）**：未穿 9 调用点 + THUMBNAIL guard
   （M8-3 设计决定修订）漏穿 doc process → v3 档缩略图/QuickLook/吸管/
   colormatch/EDR 预览与主视图不同臂（用户可见撕裂）——T2 Action 3③
   显式清单（含豁免面防机械套红线）+ T5 走查第三项双保险；EXPORT 主腿
   已穿（正资产）。

---

## 评审修复记录（v1 → v2，2026-10-25）

> 依据 = `M9-4-PLAN-REVIEW.md`（PASS-with-notes：major 1 / minor 4 /
> obs 2）。major 全修；minor 全修。零 commit、零构建，纯文档批。

| 条目 | 处置 | 落点 |
|---|---|---|
| **M-1①** D-M9SP-8 断言与代码不符 | 已修：CONTEXT D-M9SP-8 第四段改写如实叙事——`PipeCoordinator.swift:2508-2514` thumbnail guard 是 **M8-3 T3 显式 process 层设计决定**（注释明文「thumbnail cache-key space never moves」），非 tail-policy 先例、非漏穿；本批穿 thumbnail = **修订该设计决定**，M8-3 注释同批修订，DECISIONS 单独申报「M8-3 thumbnail guard 设计修订」；红线 4 同步改写（「.legacy 缺省腿属 bug」保留、误引先例句删除）；CONTEXT X3 引用同步 | CONTEXT D-M9SP-8/X3 + 本 plan 红线 4 |
| **M-1②** 核验清单不完备 | 已修：T2 Action 3③ 显式清单——**未穿 9 调用点**（评审 8 点全数列 + 修复批亲核补 1 点：`PipeCoordinator:2073` followEdgesSurface 层子 run）；**已穿正资产正面登记**（主渲染双路 `:2521/:2543` + `ExportRenderer.swift:550/:562`〔评审引 :555/:570，实测语句行 :550/:562，事实一致〕核验零工作量）；机检面 grep 一网打尽 | 本 plan T2 Action 3③ + 风险节 5 + frontmatter PipeCoordinator 行 |
| **M-1③** 超线预告缺失 | 已修：裁定权归属钉加「穿线超线预告」——本缝预期触「超 10 行」停手线，触线 = 计划内申报（plan 预授权 + DECISIONS 记实际行数与逐点清单），非方案失败；其余四类扩面照旧硬停；红线 4 / T2 Action 3③ / CONTEXT D-M9SP-8 末段同款 | 本 plan 裁定权钉/红线 4/T2 3③ + CONTEXT D-M9SP-8 |
| **m-1** 键族 4→5 | 已修：`panel_process_migrate_*` = title/body/button/cancel/**confirm** 5 键（film 族现役 5 键 xcstrings 亲核；confirm sheet 保留 L057 形故 confirm 键随 copy 中性化）——frontmatter xcstrings 行 / T2 Action 5③ / T2 验收机检 / T5 Action 4（15-17→16-18）/ CONTEXT D-M9SP-7③ 五处同步 | 本 plan 四处 + CONTEXT D-M9SP-7 |
| **m-2** T3 引用笔误 | 已修：「id 拼写勘误③对上游」→「照上游 c740f7b，X5 十 case 列表为正本」+ 笔误注记（勘误③ = 迁移通道泛化面；id 拼写属 X5/勘误④面） | 本 plan T3 Action 2 |
| **m-3** SessionThumbnailRenderer 豁免 | 已修：豁免面（`.legacy` 即正确值，禁穿）登记于 T2 Action 3③ + 红线 4 + CONTEXT D-M9SP-8——依据 = 文件头「Phase 8 contract（禁改）」契约（`:22` 亲核）+ legacy 库无 process 载体；同批补 `CullingView.swift:227`（pristine 默认链，无 doc stored process）同列豁免；判断入 DECISIONS 登记项 | 本 plan T2 3③/红线 4/DECISIONS 行 + CONTEXT D-M9SP-8 |
| **m-4** GradeCatalog 论证空转 | 已修：措辞「v1 形 pristine 单源」→「**天然零改**」（`defaultLook` 无 colorWheels identityJSON 条目，`NodeOwnershipCatalog.swift:297` 亲核仅 exposure/contrast/saturation 三条；结论不变）——plan 风险节 4 + CONTEXT H-SP4/红线 5 三处同步 | 本 plan 风险 4 + CONTEXT 两处 |
| obs ΔN 上沿超 ROADMAP | 不处置（评审自注「非本 plan 义务」；前站实数落后对账面已有红线 12 覆盖） | — |
| obs ParamsCoding 路径 | 顺手落正：read_first 已带文件名，修复批在 CONTEXT 抽核域补注 = `LightamerCore/Sources/Foundation/`（评审 :22-28 域亲核吻合） | 无需改文（本轮 M-1 修订文本未涉该行） |

**修复批亲核增量**（评审清单外新核两点，已并入 M-1② 处置）：
`PipeCoordinator.swift:2073`（followEdgesSurface——「子 run 腿」字面涵盖
但评审未点名，补入未穿清单）；`CullingView.swift:227`（culling pristine
默认链——与 SessionThumbnailRenderer 同理豁免，防机械套红线）。
