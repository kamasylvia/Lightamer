---
phase: M9-3
plan: v2
title: "M9-3 执行 plan — 几何校正 Upright 系（T1 数学面 UprightMath+cropFitAngle+golden 六门 / T2 upright op v50 15.5 骑 ashift_warp / T3 rotate·straighten 联动+90°+段检测防呆+Constrain Crop / T4 导线 overlay+求解 live / T5 收口：定向+全套带式+zh-audit+走查配方）"
depends_on: ["M9-2 闭环（站序串行 + 机器级单重活制）", "M9-0 charter"]
autonomous: true
requirements: ["research 正本 = phases/m9-3-upright/RESEARCH.md（§2 上游测绘 / §3 我方盘点含勘误 / §4 差距矩阵+方案骨架+坐标系 / §5 数值精度 / §6 风险+OQ / §7 许可）", "裁决正本 = 同目录 CONTEXT.md（D-M9G-1..6 = OQ-M9-3-1..6 全按 research 推荐〔OQ-1 落地形态 planner 修正为同批双 item〕+ charter 勘误登记 + 转写勘误 IopCatalog + 红线 7 组 + 风险 R-1..R-5；晨审可推翻）", "REQUIREMENTS M9GEO-01..02（验收形态即各 T 验收源——01 按 charter 勘误读解为联动 UX 缺口）", "charter = ROADMAP §M9 站 3（M，ΔN +12..18；lightcraft MIT 可移植带归属）", "全套对账锚 = R6 收口终值 4292/35/0（R6-SUMMARY:55 亲核）⊕ ΔN_M9-1（+20..29）⊕ ΔN_M9-2（+15..20）——开工前亲核实数落基线表达式"]
success_criteria: "SC 全可机检——T1：UprightMath golden 六门（合成梯形逆解 spread<1.5px+四角差<0.01 / 单线 level 1e-9 / 分辨率无关<0.006 / 符号 −6°±0.5 / 病态三防线〔近平行 identity·共点拒·focal 域外回落 1.5〕）+ cropFitAngle 闭式（解析例/非最大框不放大/角回 0 复原/手调框不再 fit 绕中心收缩保 aspect）+ 双跑逐位确定性 + MIT 头注与 NOTICE 在案；T2：upright off 恒等 byte-exact（blit identity）+ 产线 warp 梯形恢复（骑 ashift_warp 共名，AshiftKernels.metal git diff 零命中机检）+ params 往返+StableHash + V50Order 15.5 add-only 断言（不重排/现行序逐字节）+ pointMapSegment 供 .homography 段往返 + off 负测判定面 = 恒等直通 byte-exact + params 持久仍合法（upright 进默认 seed ⇒ paramsData 恒写〔ashift/flip 同形〕，「off 不写 sidecar」分支禁止——pristine 是 document record 面语义不适用 instance params 面）；T3：段检测合成暗线 golden（方向<0.7°/长度≥0.6×）+ 拉直防呆门（单线 None/带纹 −4°±0.5/20° None·8° −8°±0.5）+ recordLinkedChanges 原子批（两 item 零中间渲染+单次 historyDidChange）+ 联动重算单源谓词（框==旧角 cropFitAngle 输出才自动重算/手调框仍 fit 不动负测+不再 fit 绕中心收缩保 aspect〔#1794 中段〕/非最大框不放大）+ 90° 位覆盖（.auto→显式位持久+resolved 直通）+ Constrain Crop（blank_fraction<0.002+aspect 保持）+ 旋转 90/任意角 golden（AABB 闭式）；T4：导线交互态机（按下即画/近端拖 1e-3 跟随/近线点选/空白清/Delete 删选中无选中零动作/≤4 上限 toast）+ 选中态 UI-only 负测（不入 params/sidecar）+ 导线持久 = upright.Params.guides（每编辑步一 history item）+ mapper 逆映射入档（视口⇄输入帧往返 <1px）+ live 重解 debounce 探针（PERF_PROBE+L014 fence，>50ms hitch=0）+ 面板座位（Geometry 页基础排+mode off/guided+guides readout+Constrain 按钮）；T5：Project.swift 数组+BUNDLE-MAP 增行+tuist 末位 + 定向 IOP/IOPP/APP 全绿 + 全套带式对账（基线链+本批 +14..19，orchestrator 预批）+ zh-audit 双 PASS + gui-acceptance m9-3 MANIFEST 走查配方（AXPress 纪律）"
estimated_tests: "+14..19（T1 +5..7 / T2 +3..4 / T3 +4..5 / T4 +2..3 / T5 0；charter 带 12-18 / research 复核 14-22——plan 实分解越 charter 上沿至多 +1，申报 = golden 六门各承载独立红线论证〔RESEARCH §5 明列〕+ 病态防线负测族不可并法；收口轮按实数对账）"
test_bundles: [IOP, IOPParity, App]
baseline: "带式 = R6 收口终值 4292/35/0（R6-SUMMARY:55 亲核）⊕ ΔN_M9-1（plan v2 估 +20..29，以 M9-1 SUMMARY 实数落）⊕ ΔN_M9-2（plan 估 +15..20，以 M9-2 SUMMARY 实数落）——本 plan 开工前亲核 GOAL-STATE 与两 SUMMARY 实数落基线表达式"
expected_all: "全套 = 基线链 + 本批 +14..19（--all 归 orchestrator 批准轮；本 plan 验收 = 构建 + 定向 bundle〔IOP/IOPParity/App〕+ 对账表达式申报）"
red_lines:
  - "裁决正本 = 同目录 CONTEXT.md（D-M9G-1..6 + charter 勘误 + 红线 7 组；晨审可推翻）；research 正本 = RESEARCH.md；执行以 CONTEXT 转写勘误为准（IopCatalog 零触碰）。"
  - "封存面 17 件零 diff，唯二 additive 例外 = V50Order 15.5 一行（add-only：不重排、现行序逐字节，filmPlacement 20.8 先例）+ Registry upright 注册行族（默认 seed + kernel 清单共名行；defaultFaceDisabledOpNames 不触）。AshiftKernels.metal 零 diff 机检（git diff 两文件零命中）——upright 骑 ashift_warp 共名（AshiftModule.swift:73 functionName 字符串常量形态 + Registry :517 共名先例）；需 wrapper = 逐 hunk 申报豁免停手上报。HistoryStack/HistoryHash/PipelineDocument/LightamerSidecar/GradeCatalog 严格零 diff（OQ-1 裁②的结构面依据）。"
  - "零 schema 触碰：schemaVersionCurrent 不 bump、LightamerSidecar 零 diff（M9-2 已预定 v12；本批 params 走 per-instance paramsData 既有编码，M2-1 colormatch 先例）。UserDefaults 零新键。"
  - "MIT 归属不可延后：UprightMath.swift / StraightenDetect.swift 文件头 lightcraft 版权声明 + 移植注记 + commit 锚（fbc927f0/7635b38c/693c3593/54c6c43b/7d3cd8af）+ 根 NOTICE 新条目（T1 随件落地）；零归属入库 = 流程违规。"
  - "数学域：UprightMath/StraightenDetect 全 Double；kernel float32（L006）；L048 比较空间纪律（decode 回线性再比 + Double(Float(x)) 升维）；L014 探针读回先 fence。坐标系统 = 导线存 upright 输入帧归一 0..1、mapper 唯一通道、H 居中归一域入 kernel 前像素换算（Double）。"
  - "通用族：xcstrings 尾块纯插入 + zh-audit 双 PASS + 动态键禁形 / 测试落域唯一 target + Project.swift 显式数组 + BUNDLE-MAP 登记行 + tuist generate 恒末位（L041）/ 机器级单重活（machine-guard 前置 + 排程避让 M9-2 轮 + GUI 实例起跑前 ps 清零）+ --all 批准制 + 8G 门 / commit-per-task feat(m93) 前缀全英文 / D-H1 三段 / disable-not-unmount / parentage 清理纪律。"
files_modified:
  - LightamerCore/Sources/Pipe/UprightMath.swift            # T1：新建——Guided 数学全件（Segment/refineVP Jacobi/focalFromVPs 正交闭式/rotationBetween/solveVertical/solveFull Gram-Schmidt/recentre/solveGuided/levelAngle），f64，MIT 头注（GeometryPointMapper 同域聚集）
  - LightamerCore/Sources/Pipe/CropFitAngle.swift           # T1：新建——最大内接矩形闭式 + 角度联动单源谓词（纯函数，供 T3）
  - Tests/LightamerTests/UprightMathTests.swift             # T1：新建（IOP——HomographyTests/LensAutoCropTests Core 纯函数同域先例）——golden 六门 + 确定性双跑
  - Tests/LightamerTests/CropFitAngleTests.swift            # T1：新建（IOP）——闭式解析例 + #1794 三分支负测（仍 fit 不动/不再 fit 绕中心收缩/回 0 复原）
  - NOTICE                                                   # T1：lightcraft 条目（移植臂真落地，ALCE-03 对偶）
  - LightamerIOP/Sources/Upright/UprightModule.swift        # T2：新建——Params{mode off/guided, guides≤4} + functionName="ashift_warp" 共名 + commit=solveGuided 确定式重导（不缓存）+ process 骑 kernel + ROI 协商 ashift 同款 + neutral(off)→blit identity + pointMapSegment 供段
  - LightamerCore/Sources/Foundation/V50Order.swift         # T2：15.5 add-only 一行（ashift 15.0 后 flip 16.0 前 + 注释行）
  - LightamerIOP/Sources/Registry.swift                     # T2：upright 注册行族（默认 seed + kernel 清单共名 dedupe 注记；defaultFaceDisabledOpNames 不触）
  - Tests/LightamerTests/UprightModuleParityTests.swift     # T2：新建（IOPParity——AshiftParity/CropParity 同域）——off 恒等 byte-exact + 产线 warp 梯形恢复 + params 往返/StableHash + V50Order 断言 + pointMapSegment 往返
  - LightamerCore/Sources/Pipe/StraightenDetect.swift       # T3：新建——detect_segments + levelAngle 消费 + STRAIGHTEN 常量（MAX_DEGREES=10.0/MIN_LINES=3）+ ≥3 线共识门，CPU Swift，MIT 头注
  - App/Sources/Lightamer/State/EditorState.swift           # T3：additive recordLinkedChanges(_ snapshots: [ModuleInstance], label:)（原子批：连续 commit 零中间渲染 + 单次 historyDidChange；recordChange :217 邻位）
  - App/Sources/Lightamer/State/CropToolRotation.swift      # T3：新建——角度手柄/拉直滑杆/90° 按钮的 commit 编排（写 ashift.rotation / flip.orientation + 联动 cropFitAngle 重算批）+ 手调框保护谓词消费
  - App/Sources/Lightamer/UI/Overlay/CropOverlayView.swift  # T3/T4：角度手柄 + 拉直滑杆 UI（:27-28 注记兑现改写；D-H1 三段 live=ashift live tick）
  - Tests/LightamerTests/StraightenDetectTests.swift        # T3：新建（IOP——VisionDetectTests 同域）——合成暗线 golden + 防呆门三态 + 符号门
  - Tests/LightamerTests/CropToolRotationTests.swift        # T3：新建（App——CropOverlayTests 同域）——原子批/联动谓词/手调框保护/90° 位覆盖/Constrain Crop/旋转 golden
  - App/Sources/Lightamer/UI/Overlay/UprightGuidesOverlay.swift # T4：新建——导线 overlay（按下即画/端点拖/近线点选/空白清/Delete 删选中/≤4 上限）+ 选中态 UI-only + mapper 逆映射入档
  - App/Sources/Lightamer/State/PipeCoordinator.swift       # T4：导线工具装配 + live 重解 debounce 缝 + 求解 preview warp（App 侧协调器非封存面；detectionSourceImage :2029 邻域零改）
  - App/Sources/Lightamer/UI/Inspector/UprightPanelView.swift # T4：新建——mode off/guided + guides readout/清除 + Constrain Crop 按钮 + 双 warp 提示 note（R-3 观察项）
  - App/Sources/Lightamer/UI/Shell/EditorTabRoute.swift     # T4：Geometry 页基础排 upright 行（:266-278 窗口，crop/flip/lens 后）
  - Tests/LightamerTests/UprightGuidesInteractionTests.swift # T4：新建（App——CropOverlayTests/overlay 族同域）——交互态机断言（upstream tests_guided_guides 5+5 法对照）+ 选中态不入档负测 + mapper 往返 + debounce
  - Resources/Localizable.xcstrings                          # T3/T4：upright_*/straighten_*/crop 工具族键尾块纯插入
  - Project.swift                                            # T1-T4 逐任务：六个新测试文件当批入对应 bundle 显式数组；tuist generate 恒各批末位（L041）
  - .work/gsd/phases/m2-4-0-test-bundles/M2-4-0-BUNDLE-MAP.txt # T1-T4：六行落域登记
  - .work/gsd/phases/m9-3-upright/M9-3-SUMMARY.md            # T5：执行摘要（ΔN 终账 + 走查证据指针）
  - .work/gsd/phases/m9-3-upright/M9-3-DECISIONS.md          # T5（滚动）：裁定记录（OQ-1 undo 序/探针选型/live 形态实测/符号钉死值）
  - .work/gui-acceptance/m9-3/MANIFEST.md                    # T5：走查配方（AXPress 纪律）
---

# Plan M9-3 — 几何校正 Upright 系（M9GEO-01..02，charter 勘误后语义）

> **裁决正本** = `CONTEXT.md`（D-M9G-1..6 + charter 勘误 + 红线 7 组；晨审
> 可推翻）。**规格正本** = `RESEARCH.md`（上游测绘 §2 / 我方盘点 §3 /
> 差距矩阵与骨架 §4 / 数值精度 §5；planner 抽核 16 点吻合 + 1 处勘误）。
> 勘误后主战场 = **既有件扩展（ashift/crop/flip）+ 导线系新建（UprightMath
> + upright op + overlay）**——rotate 本体已在 ashift 达标（AshiftParityTests
> 在案），零新 rotate op。
>
> **执行序**：T1 → T2 → T3 → T4 → T5 串行（机器级单重活制）。每任务独立
> commit（Conventional Commits 全英文，前缀 `feat(m93)/test(m93)/…`，只 add
> 相关文件）；重活起跑前过 `Scripts/machine-guard.sh`（**M9-2 在飞时让位**，
> guard block 即停）；开工前核 `.work/config.toml [gsd]` paused/auto + 基线
> 链实数（GOAL-STATE + M9-1/M9-2 SUMMARY）。
>
> **C 档停**：T5 闭环后停汇报（附走查样例清单供用户过目——§12.3 铁律：
> 验收样例动工前对齐口径；走查面以我方 mapper 唯一通道/恒等 byte-exact
> 语义断言，不照抄上游 UX 细节）。
>
> **基线**：R6 收口终值 `4292/35/0` ⊕ ΔN_M9-1 ⊕ ΔN_M9-2（实数落）。本 plan
> 分账 **+14..19**（charter 12-18 上沿越至多 +1，申报见 ΔN 预算表注）。

## ΔN 预算表（逐任务，越带申报理由）

| 任务 | 测试增量 | 构成 | 落点（bundle） |
|---|---|---|---|
| T1 数学面 | **+5..7** | UprightMath 4..5 法（梯形逆解门〔spread+四角差一法双断言〕/单线 level 1e-9/分辨率无关/符号门 + 病态三防线可并 1..2 法）+ CropFitAngle 1..2 法（解析例 + #1794 三分支〔复原/不放大/不再 fit 收缩〕——收缩 golden 并法承载，一法多断言）| IOP（UprightMathTests + CropFitAngleTests） |
| T2 op 面 | **+3..4** | off 恒等 byte-exact + 产线 warp 梯形恢复（kernel parity 面）+ params 往返/StableHash + V50Order/pointMapSegment（可并 1 法） | IOPParity（UprightModuleParityTests） |
| T3 联动面 | **+4..5** | StraightenDetect 2..3 法（合成暗线 golden + 防呆三态〔单线 None/带纹 −4°/陡线 20° None·8° −8°〕+ 符号）+ CropToolRotation 2 法（原子批+联动谓词+手调框保护 / 90° 位覆盖+Constrain+旋转 golden——一法多断言） | IOP（StraightenDetectTests）+ App（CropToolRotationTests） |
| T4 导线交互 | **+2..3** | 交互态机（画/拖/选/删/上限——upstream 5+5 法对照可并 2 法）+ 选中态 UI-only 负测 + mapper 往返/debounce 1 法 | App（UprightGuidesInteractionTests） |
| T5 收口 | **0** | docs + Project.swift + BUNDLE-MAP + tuist + zh-audit + 走查配方 | — |
| **合计** | **+14..19** | 基线链 + ΔN → 全套申报带 | 六新测试文件（三 IOP + 一 IOPParity + 二 App） |

> **越 charter 上沿至多 +1 申报**：golden 六门各承载独立红线论证（RESEARCH
> §5 逐门列明——逆解门 = 数学正确性 / 单线精确 = 符号与旋转纯度 / 分辨率
> 无关 = 坐标归一 / 符号门 = 用户可见方向 / 病态防线 = 不崩承诺），并法
> 压缩只到断言不伤论证的限度；病态三防线可并法但不可省族。**如实申报优先
> 于带内压缩**（M9-1 先例同款）。

---

## T1 数学面 — `UprightMath` + `cropFitAngle` Core 纯函数件 + golden 六门

**目标**：Guided Upright 全部数学以 Core 级纯函数落地（f64，lightcraft
MIT 移植带归属），六门 golden 钉死；crop 联动闭式同批就位（T3 消费）。

**read_first 注记（upstream 读取纪律，评审 obs-3）**：lightcraft 本地工作
树落后 origin/main 1031 commits（upright.rs 工作树 611 行 vs upstream
634 行、tests_guided_guides.rs 工作树不存在）——**upstream 引用一律
`git show origin/main:<path>`，工作树文件不可信**（评审亲历工作树误判：
常量/测试文件双缺）。

**Action（file:line 预估）**：

1. 新建 `LightamerCore/Sources/Pipe/UprightMath.swift`（~250-350 行，
   GeometryPointMapper 同域；RESEARCH §4.2 件 A 边界）：
   - `Segment`（居中归一坐标）+ `line()` / `tiltFromVertical()`
     （≤45° 分垂直/水平族判据）；
   - `refineVP`（`Σ w·l·lᵀ` 最小特征向量，w=线长——Jacobi 旋转 50 轮、
     收敛 1e-15，upright.rs `refine_vp` 直译）；
   - `focalFromVPs`（正交闭式 `f² = −(vx·hx + vy·hy)`，接受域 0.5..6.0，
     VP 无穷远 `v[2]≈0` → nil → 回落 DEFAULT_FOCAL=1.5）；
   - `rotationBetween`（Rodrigues，PanoCamera 同族复用 Mat3D）；
   - `solveVertical`（垂直 VP → y 轴）+ `solveFull`（Gram–Schmidt 双族）+
     `recentre`（中心钉住 + Jacobian 行列式开方归一尺度）+ `K·R·K⁻¹`
     合成（transform.rs `rotation_homography` 直译）；
   - `solveGuided(guides: [Guide]) -> Mat3D`（≤4 条：同族 ≥2 → refineVP
     跳 RANSAC；双族 → solveFull + 正交估焦；仅垂直 → solveVertical；仅
     水平 → 问题旋转 90° 共轭 `(x,y)→(y,−x)`；单条/无 → levelAngle 纯旋转）；
   - `levelAngle`（长度加权中位偏角 + ±2° 共识门，水平族优先 0.5 倍判据）；
   - 病态防线：近平行（VP 叉积范数 <1e-24）→ identity 回落；VP 帧内
     半径 <2.0 → 拒；focal 域外 → DEFAULT_FOCAL。
   - **不移植**：detect_segments/RANSAC/reliable 全防线/analyze_source
     缓存（D-M9G-3——Guided 导线即内点，不需要）。
2. 新建 `LightamerCore/Sources/Pipe/CropFitAngle.swift`（~80-120 行）：
   `cropFitAngle(angle:aspect:frame:)` 最大内接矩形闭式（upstream
   `crop_fit_angle` 直译）+ 联动单源谓词 `shouldAutoRefit(current:oldAngle:
   newAngle:)`（框 == 旧角输出或全图 → true〔最大框随角重算〕；仍 fit 的
   手调框 → false 不动；非最大框永不放大——#1794 两端语义）+
   `shrinkToFit(current:angle:frame:)` 绕中心收缩保 aspect 闭式（**#1794
   中段裁决〔v2〕：手调框转角后不再 fit → 绕中心等比收缩至仍内接，对齐
   upstream**——crop.rs `with_angle_keeps_a_crop_that_still_fits` +
   `with_angle_shrinks_a_crop_that_no_longer_fits_keeping_its_aspect`
   双测试语义。依据：plan 现文 T3「aspect 保持」已隐含收缩 + #1794 是
   用户可感 bug 修复 + D-M9G-1 自我定位 = upstream 三代 issue 收敛件；
   保守回退形 = 完全不动〔框悬空含黑边〕，晨审可翻）。
3. NOTICE 新增 lightcraft 条目（移植臂真落地——commit 锚 + 「数学移植自
   lightcraft（MIT OR Apache-2.0），实现独立 Swift 重写」）。
4. 新建 `Tests/LightamerTests/UprightMathTests.swift` + `CropFitAngleTests.swift`
   （IOP 域，Project.swift 数组 + BUNDLE-MAP 同批，tuist 末位）。

**验收标准（机检）**：
- [ ] golden 六门全绿（CONTEXT §测试策略 1-5 门逐值断言：spread <1.5px /
      四角差 <0.01 / 1e-9 / <0.006 / −6°±0.5 / 三防线各自断言）。
- [ ] cropFitAngle：3:2 @10° 解析例闭式对照 + 非最大框不放大 + 角回 0 框
      复原（#1388 语义）+ 手调框不再 fit 绕中心收缩保 aspect（#1794 中段，
      upstream crop.rs 双测试语义同参）。
- [ ] 确定性：solveGuided 双跑逐位（闭式无 RNG）。
- [ ] L048 比较空间纪律：golden 对照先 decode 回线性 + `Double(Float(x))`
      升维（M3-3 同款）。
- [ ] MIT 头注 + NOTICE 在案（零归属 = 收口门拒绝）。

**ΔN**：+5..7。

---

## T2 op 面 — `upright` 新 op（v50 15.5）骑 `ashift_warp`

**目标**：Guided 解经产线兑现——新 op 注册 + 共名 kernel dispatch +
params 持久化 + off 恒等；零 schema、零新 kernel。

**Action（file:line 预估）**：

1. 新建 `LightamerIOP/Sources/Upright/UprightModule.swift`（~180-250 行，
   AshiftModule 结构模板）：
   - `Params { mode: Mode(off/guided), guides: [Guide] ≤4 }`（Guide =
     op 输入帧归一 0..1 两端点 ×2 Double——CONTEXT 红线 6 坐标系）；
     Codable + `paramsData` 既有编码（M2-1 colormatch 先例）；
   - `functionName = "ashift_warp"`（字符串常量共名，`AshiftModule.swift:73`
     同形）——**AshiftKernels.metal 零 diff、零 wrapper**（Registry `:517`
     「perspective share one kernel」先例，PSO 清单 dedupe）；
   - `commit_params`：guides 变更 → `UprightMath.solveGuided` 确定式重导
     前向/逆向 Mat3D（**不缓存**——D-M9G-3：upstream upright_transform
     持久化是 auto 模式件，Guided 导线即真相、f64 重导出逐位同）；
     H 居中归一域 → kernel uniforms 前平面像素缩放（Double 计算，
     Float32 入 uniforms——ashift compose 同位换算）；
   - `process`：mode == .off 或 guides 空 → **blit identity（byte-exact）**；
     非 off → 骑 `ashift_warp` 后向采样；
   - ROI 协商：ashift 同款（前向角点 AABB / 逆向后向 + 2px 插值边距）；
   - `pointMapSegment()`：nil（neutral/singular）或 `.homography(forward:
     inverse: clip:inSize:outSpan:)` 段（`GeometryPointMapper.swift:42-52`
     既有 case——**mapper 本体零 diff**）；
   - neutral 谓词：mode == .off（enabled 实例 off = 恒等直通——ashift
     DECISIONS D6「面板有实例可驱、cache-neutral」同款语义）。
2. `V50Order.swift`：`("upright", 15.5)` add-only 一行（ashift 15.0 后
   flip 16.0 前 + 注释；现行序逐字节不动）。
3. `Registry.swift`：upright 注册行族（默认 seed + kernel 清单共名 dedupe
   注记；**defaultFaceDisabledOpNames 不触**——upright 默认面启用）。
4. 新建 `Tests/LightamerTests/UprightModuleParityTests.swift`（IOPParity 域）。

**验收标准（机检）**：
- [ ] off 恒等 byte-exact：enabled off 实例经产线 = 无实例逐位（Colormatch
      Identity 先例同形）+ off 实例 paramsData 恒入 sidecar（默认 seed
      形态，ashift/flip 同形）。**off 负测判定面 = 渲染恒等 + params 持久
      仍合法**，「off 不写 sidecar」分支禁止（v2 minor-2 钉死：pristine
      惯例是 DRT/film document record 面语义，不适用 instance params 面）。
- [ ] 产线 warp 梯形恢复：T1 合成门经真实 kernel 腿复验（spread 门同值）。
- [ ] `git diff AshiftKernels.metal` 零命中 + `git diff` V50Order 恰 15.5
      add-only hunk（现行行零改）机检。
- [ ] params 往返（guide 坐标 Double 精度保持）+ paramsHash StableHash。
- [ ] pointMapSegment 段往返（视口点 → 输入帧 → 视口 <1px）。
- [ ] MCP `apply_params` 全 JSON replace 路径不回归（IopCatalog 零触碰——
      上游 19 白名单 + geometry 族 NOT cataloged 常态断言可选）。

**ΔN**：+3..4。

---

## T3 联动面 — rotate/straighten 工具（角度手柄 + 拉直 + 90° + 段检测 + Constrain Crop）

**目标**：M9GEO-01 勘误后语义兑现——crop 工具面的旋转/拉直/步进全联动，
`with_angle` 三代 issue 语义收敛到我方双 op 架构。

**Action（file:line 预估）**：

1. 新建 `LightamerCore/Sources/Pipe/StraightenDetect.swift`（~150-200 行，
   CPU Swift，MIT 头注）：`detectSegments(lum)`（σ0.8 高斯 → Sobel →
   level-line 角 → 自适应阈 p90×0.35 下限 0.008 → 区域生长 22.5° 容差 →
   加权主轴拟合 → 长 ≥0.04·长边且长宽比 ≥5；居中归一坐标输出）+
   `levelDegrees(segs) -> Double?`（levelAngle 消费 + **STRAIGHTEN_MAX_
   DEGREES=10.0 / STRAIGHTEN_MIN_LINES=3** 共识门 + 符号约定：右倾下降
   地平线 → 负角）。检测源 = `detectionSourceImage()` decoded 裸探针起步；
   **T3 内一次对比实测**（vs followEdgesSurface 截断栈形 lens 后帧），
   DECISIONS 申报选型（R-5）。
2. `EditorState.swift` additive `recordLinkedChanges(_ snapshots:
   [ModuleInstance], label:)`（`recordChange :217` 邻位）：两 item 同批
   连续 commit、零中间渲染、单次 historyDidChange（D-M9G-1——undo 两次
   LIFO 序 DECISIONS 登记）。
3. 新建 `App/Sources/Lightamer/State/CropToolRotation.swift`（~150-250 行）：
   - 角度手柄（框外角度轮）+ 拉直滑杆（±45）→ **写 ashift.rotation**；
     拖动 live = ashift live tick（`applyLiveInstance`——直显旋转用 live
     而非 disable，OQ-5）；松手单 commit；
   - **联动重算批**（`recordLinkedChanges`）：任一角度/90° 变更 commit 时
     同批重算 crop rect（`cropFitAngle` + `shouldAutoRefit` 单源谓词——
     手调框保护：仍 fit 不动 / 不再 fit 绕中心收缩保 aspect〔#1794 中段，
     T1 `shrinkToFit` 件〕/ 永不放大）；
   - 90° 按钮 ×2 → `flip.orientation` 显式位（`.rotCW90`/`.rotCCW90`——
     **符号映射探针钉死**〔位集 rawValue 5/6 与 CW/CCW 视觉方向，golden
     断言〕；覆盖 `.auto` 后持久，`resolved(forEXIF:)` non-auto 直通）；
   - auto straighten 按钮：StraightenDetect 优先（≤10° + ≥3 线，None →
     toast 明说）+ Vision 地平线回落（AshiftAutoDetect 现役件零动）；
   - Constrain Crop 一键：upright/ashift 后黑边收缩（48×4 边采样数值版
     对照 LensAutoCrop 闭式形——实现域 DECISIONS 定，crop 重写单 commit）。
4. `CropOverlayView.swift`：角度手柄 + 拉直滑杆 UI 挂载（:27-28 注记兑现
   改写——「rotation handles belong to 04-03 ashift」 linkage 落位）；
   90° 按钮 + auto straighten 入 crop 工具栏（LR 位）。
5. 新建 `Tests/LightamerTests/StraightenDetectTests.swift`（IOP）+
   `CropToolRotationTests.swift`（App）。

**验收标准（机检）**：
- [ ] 段检测合成暗线 golden：方向误差 <0.7°、长度 ≥0.6×真值
      （upstream `segment_detector_finds_known_lines` 同参）。
- [ ] 拉直防呆门：单边线 → None；带纹地平线 → −4°±0.5；20° → None、
      8° → −8°±0.5；**符号门**：右倾下降 6° → −6°±0.5（ashift.rotation
      CG y-down 衔接——VisionDetect 头注先例）。
- [ ] `recordLinkedChanges` 原子批：恰两条 item、零中间渲染（history
     DidChange 单次断言）、undo 序 = 先框后角。
- [ ] 联动谓词：框 == 旧角 cropFitAngle 输出 → 重算；手调框仍 fit → 不动
      （负测）；手调框不再 fit → 绕中心收缩保 aspect（#1794 中段 golden：
      收缩后仍内接 + 中心不变 + aspect 不变）；非最大框不放大；角回 0
      最大框复原。
- [ ] 90°：`.auto` → 显式位持久 + 重读 sidecar 后位保持 + EXIF 变化不
      翻转（non-auto 直通）；旋转 90/任意角 golden（线迹 spread <1.5px +
      AABB 尺寸闭式断言——flip 位集与 ashift.rotation 两腿）。
- [ ] Constrain Crop：blank_fraction <0.002 + aspect 保持（upstream
      `constrain_crop_removes_blank_areas` 同参）。
- [ ] AshiftPanelView 现役面零 diff（Auto Level 按钮回落位不动）。

**ΔN**：+4..5。

---

## T4 交互面 — Guided 导线 overlay + 求解 live + 面板座位

**目标**：M9GEO-02 用户面——导线画/选/拖/删 + 拖动 live 重解 + upright
面板（Geometry 页基础排）。

**Action（file:line 预估）**：

1. **首动作 = 预算探针**（D-M9G-5，R-4）：导线解 + preview warp + 尾段
   重渲时长探针（`LIGHTAMER_PERF_PROBE=1` + XCTSkipUnless + **L014 queue
   fence 先行**——无 fence 计时 = 假数）；实测 >50ms hitch → 回落②
   disabled+scrim 形（crop T0 先例），DECISIONS 申报。
2. 新建 `App/Sources/Lightamer/UI/Overlay/UprightGuidesOverlay.swift`
   （~250-350 行，CropOverlayView/MaskOverlayHost 直系模板）：
   - 交互态机照 upstream 语义（`tests_guided_guides.rs` 5+5 法对照）：
     **按下即画**（新导线起于按压点）+ 拖端点（近端跟随指针 1e-3、远端
     不动）+ 近线点选（白/加粗/大端点选中态）+ 点空白/画新线/离工具清除
     选中 + Delete/Backspace 只删选中（无选中零动作零 undo）+ ≤4 条上限
     toast；
   - **选中态 UI-only**（不进 params——upstream serde skip 同语义）；
   - 导线本体持久 = `upright.Params.guides`（**每编辑一步 = 一 history
     item**，upstream undo 粒度同款——经 EditorState 既有单实例 commit，
     guides 是 upright 单实例 params，无联动批）；
   - 坐标经 `GeometryPointMapper` 逆映射入档（视口 → upright 输入帧归一
     ——唯一通道，勿开第二映射点）；
   - 端点拖动 live：debounce 重解（μs 闭式）+ preview 重渲（一 warp）；
     live 值不进 commit（D-H1——松手单 commit）。
3. `PipeCoordinator.swift`（App 侧，非封存）：导线工具装配 + live 重解
   debounce 缝（mask overlay request 通道邻域形态——**不改 render 主链**）。
4. 新建 `App/Sources/Lightamer/UI/Inspector/UprightPanelView.swift`
   （~120-180 行）：mode off/guided toggle + guides 计数/清除 readout +
   Constrain Crop 按钮（T3 件座位）+ **双 warp 提示 note**（ashift.
   rotation ≠ 0 且 upright 非空 → 「拉直可并入导线解」提示——R-3 缓解
   观察项）。
5. `EditorTabRoute.swift` Geometry 页基础排 upright 行（`:266-278` 窗口：
   crop/flip/lens 后追加——**ashift 留 Advanced 不动**，D-M9G-2）。
6. 新建 `Tests/LightamerTests/UprightGuidesInteractionTests.swift`（App）。

**验收标准（机检）**：
- [ ] 交互态机断言（upstream 5+5 法对照面）：按下即画起于按压点 / 近端
      1e-3 跟随远端不动 / 近线选中态 / 空白清 / Delete 无选中零动作零
      item / 第 5 条拒 + toast。
- [ ] 选中态 UI-only 负测：params/sidecar 零选中态痕迹（serde skip 语义）。
- [ ] 导线持久：每编辑步恰一 history item（guides = upright 单实例 params）；
      undo 逐步回导线。
- [ ] mapper 往返：视口画线 → 输入帧归一 → 重建视口 <1px（ashift 非零时
      经 `.homography` 段往返）。
- [ ] live 形态：拖动期 history 零 item（live 值不进 commit）；松手单
      commit；debounce 探针值 DECISIONS 落账。
- [ ] 面板座位：Geometry 页基础排在案 + AshiftPanelView 零 diff；mode
      off（默认）文档渲染逐字节现状（零 upright 实例 = 无行为）。
- [ ] xcstrings 键族尾块纯插入 + zh-audit 双 PASS。

**ΔN**：+2..3。

---

## T5 收口 — 定向 bundle + 全套带式对账 + zh-audit + 走查配方

**Action**：
1. `Project.swift` 全量核对（六新测试文件归位数组：三 IOP / 一 IOPParity /
   二 App）+ BUNDLE-MAP 六行登记核对 + `tuist generate` 恒末位（L041）。
2. 定向 bundle 轮：`Scripts/test-direct.sh --bundle iop` / `--bundle
   iopparity` / `--bundle app`（几何域三域）全绿。
3. 全套带式对账（orchestrator 预批制 + 8G 门 + MEMFAIL 机检 + GUI 实例
   ps 清零 + monitor 伴跑）：**基线链 = 4292/35/0 ⊕ ΔN_M9-1 ⊕ ΔN_M9-2
   （开工前亲核实数）⊕ 本批 +14..19**——终值按执行时序实数落 SUMMARY。
4. `Scripts/zh-audit.py --check` + `--self-test` 双 PASS。
5. `.work/gui-acceptance/m9-3/MANIFEST.md` 走查配方（AXPress 纪律 +
   parentage）：①crop 工具角度手柄拖动 → 框联动重算 → undo×2 复原（含
   「手调框 + 大角度 + 框不再 fit」收缩边界样张——obs-4/minor-3 联动）；
   ②拉直滑杆 + auto straighten（带纹地平线样张 −4° 档 + 单线 None toast）；
   ③90° 按钮两方向 + 位持久重开验证；④Guided 导线：画两条竖导线 →
   keystone 恢复 + 拖端点 live + Delete 删 + 第 5 条 toast；⑤Constrain
   Crop 黑边收缩 before/after；⑥双 warp 提示 note 出现/消失。
6. `M9-3-SUMMARY.md`（ΔN 终账 + 证据指针）+ `M9-3-DECISIONS.md` 滚动
   核对（OQ-1 undo 序 / 探针选型 / live 实测值 / 符号钉死值全在案）。

**验收标准（机检）**：
- [ ] 定向三 bundle 全绿；全套对账带式落 SUMMARY 实数。
- [ ] zh-audit 双 PASS；封存面机检（AshiftKernels.metal/LightamerSidecar/
      HistoryStack/HistoryHash/PipelineDocument/GradeCatalog + 唯二例外
      diff 形核对）全零/恰形。
- [ ] NOTICE lightcraft 条目在案；MIT 头注双文件在案。
- [ ] 走查 MANIFEST 六项配方在册（execute/validate 道消费）。

**ΔN**：0。

---

## 风险节（对照 RESEARCH §6，裁决已内嵌）

- **R-1 旋转×裁切联动（最高）——OQ-1 三案裁决对照**：①document 级 item
  （research 推荐）= 单 undo 最清，但**必触封存面三件**（HistoryItem 加
  case + HistoryStack scope + HistoryHash 折入——DRT〔M2-6〕/film〔M3-3〕
  落 document item 时是当时批正业，今天是零 diff 红线）+ record 镜像 =
  参数双真相（违反 params 唯一真相）；②同批双 item（**采纳**，D-M9G-1
  修正落地）= EditorState（非封存）additive 批 API，undo 两次（LIFO 先
  框后角，中间态一瞬，DECISIONS 登记）——upstream 三代 issue 的教训本体
  是**框语义**（各入口同框 #742 / 最大框复原 #1388 / 非最大框不放大
  #1794）非 undo 计数，`shouldAutoRefit` 单源谓词 + 手调框保护负测承
  接；③两 item 一 undo 组 = HistoryStack 无组机制（:342-350 单步 undo
  亲核），实现 = 新机制面 = 触封存，与①同罪。**晨审若坚持单 undo →
  翻案 = 解封 HistoryStack 三件（红线 2 破口申报），不建议**。
- **upstream with_angle 三代 issue 教训对照**（T3 验收断言直取）：#742
  → 联动单源谓词（角度为真相、框为派生，各入口同框——crop 工具/拉直
  滑杆/auto straighten 全走 `recordLinkedChanges` 单缝）；#1388 → 角回
  0 框复原断言；#1794 → 非最大框不放大 + 不再 fit 绕中心收缩保 aspect
  断言（v2 中段裁决 = 对齐 upstream）。
- **病态输入防线**（T1 golden 5 号门 + T3 防呆门）：近平行导线 → identity
  不崩；共点 VP 帧内 → 拒（场景特征 vs 相机倾侧判别）；focal 正交解域外
  → DEFAULT_FOCAL=1.5 回落；段检测 ≤10° + ≥3 线（误转 79→19 张实证门）。
- **R-2 符号三重奏**：golden 4 号符号门 + 90° 位映射探针 + 单线 1e-9 精确
  门三重钉死（符号错 = 门爆，无口头纪律）。
- **R-3 双 warp 软化**：T4 面板 note 缓解 + 单遍合成挂 UPSTREAM-QUEUE
  （挂账申报，本批不背）。
- **R-4 拖动实时性**：T4 首动作探针 + 回落②保底（DECISIONS 申报制）。
- **R-5 段检测探针源**：T3 对比实测 + DECISIONS 选型（followEdgesSurface
  截断栈形为升级选项）。

---

## 评审修复记录（v2，2026-10-25）

> 评审输入 = `M9-3-PLAN-REVIEW.md`（PASS-with-notes：0 error / 3 minor /
> 4 observation，31 锚亲核）。修复面 = 本 plan 单文件（CONTEXT.md 未触
> ——MIN-3 裁决按 D-M9G-1「upstream 三代 issue 收敛件」意图细化中段
> 语义，晨审可翻）。

| 项 | 处置 |
|---|---|
| MIN-1 落域汇总数错 | ΔN 预算表合计行 + T5 Action 1 两处：「二 IOP + 一 IOPParity + 三 App」→「**三 IOP + 一 IOPParity + 二 App**」（UprightMath/CropFitAngle/StraightenDetect = IOP；UprightModuleParity = IOPParity；CropToolRotation/UprightGuidesInteraction = App；六文件总数与 files_modified 逐行标注原已正确）。 |
| MIN-2 off 负测语义张力 | 判定面钉死 = **「off 恒等直通 byte-exact + params 持久仍合法」**：upright 进默认 seed ⇒ instance paramsData 恒写（ashift/flip 同形），「off 不写 sidecar」分支禁止；「pristine 惯例」是 DRT/film document record 面语义，不适用 instance params 面。改写点：frontmatter success_criteria T2 段 + T2 验收首条扩充。 |
| MIN-3 shouldAutoRefit 中段 | 裁决 = **收缩对齐 upstream**（手调框转角后不再 fit → 绕中心收缩保 aspect；仍 fit → 不动；非最大框永不放大）。依据：①plan 现文 T3「aspect 保持」已隐含收缩语义；②#1794 是用户可感 bug 修复（crop.rs `with_angle_keeps_a_crop_that_still_fits` + `with_angle_shrinks_a_crop_that_no_longer_fits_keeping_its_aspect` 双测试钉死该语义），对齐可免自养同款 bug；③D-M9G-1 自我定位即「upstream #742/#1388/#1794 三代 issue 收敛件」，中段收缩是 #1794 语义组成部分。保守回退形 = 完全不动（框悬空含黑边），晨审可翻。落点：T1 新增 `shrinkToFit` 闭式 + #1794 三分支 golden（并入 CropFitAngle 1..2 法预算一法多断言，ΔN 带 +14..19 不变）；T3 Action/验收、风险节、frontmatter 同步改写；T5 走查①补「手调框+大角度+不再 fit」收缩边界样张（obs-4 联动验证）。 |
| OBS-3 upstream 读取 | T1 新增 read_first 注记：lightcraft 本地树落后 origin/main 1031 commits——upstream 引用一律 `git show origin/main:<path>`，工作树文件不可信（工作树 upright.rs 611 行 vs upstream 634 行、tests_guided_guides.rs 工作树不存在，评审亲历工作树误判）。 |
| OBS-1/2/4 | 未采（不强制）：OBS-1 `UprightKernel` enum 同形已含在 T2「`AshiftModule.swift:73` 同形」表述内；OBS-2 spread 门维持 1.5px 统一值（判别力已足，执行批愿收严可按 upstream 分域 1.2/1.5 自便）；OBS-4 边界样例已借 MIN-3 落入 T5 走查①。 |
