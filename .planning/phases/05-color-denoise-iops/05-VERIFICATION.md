---
phase: 05-color-denoise-iops
verified: 2026-09-23T09:00:00+08:00
status: human_needed
score: 12/12 must-haves verified（SC#1-3 自动化证据全绿；SC#4 color 链达标 + tiling 承重绿，denoise 拖动 60fps = 已裁决 override 公开挂账）
behavior_unverified: 0
overrides_applied: 2
overrides:
  - must_have: "SC#4 所有 color/denoise 模块 PREVIEW 拖动 60fps（16.6ms）"
    reason: "denoise 单件链（nlmeans 降载档）85.7ms Debug 未达——降载 7.5×（481→57 趟）/批合并/PSO 预热杠杆兑现后仍不达；Open#9 应急判定按 D-05-CONTEXT-6 触发条件成立，但判定依据（.work/05/perf.md + DECISIONS D-05-08-T6-1）表明 Lab 往返共享对该缺口仅贡献 ~5%（NLMeans 本征趟数为主体），应急 plan 启动不改变结论；正杠杆 = 更深预览降载（K/window/分辨率），移交 Phase 6+/独立 perf plan；TODO.md:143 公开挂账非静默放宽；color 七件链 4.8ms（余量 3.5×）达标 + tiling fallback 承重全绿。05-VALIDATION 签核口径 accepted（『本签核唯一公开的未达标项』）"
    accepted_by: "用户（05-VALIDATION status: validated 签核）"
    accepted_at: "2026-09-23T08:11:00+08:00"
  - must_have: "SC#3 NLMeans + bilateral + hot-pixel/dark-frame/chromatic-noise reduction 全部去噪不损细节"
    reason: "SC#3 措辞落差注记（VALIDATION Per-Requirement Annotations）：实际交付 = NLMeans ✓ + bilateral ✓ + chromatic ✓（denoise 双件承载，方向门钉住）；hot pixels / dark frame subtraction 正式 defer（D-05-08-T4-1：hotpixels.c:94 IOP_CS_RAW Bayer 单通道域 + CIRAW 无 despeckle 键双重证据——需求解释权裁决非缺口；dark frame 需解码前传感器访问 v1 无路径；重启条件 = v2 自研 RAW 解码）；REQUIREMENTS IOP-DENOISE-04 行已翻 Resolved"
    accepted_by: "用户（05-VALIDATION 需求注记行签核）"
    accepted_at: "2026-09-23T08:11:00+08:00"
re_verification:
  previous_status: none
  previous_score: none
  gaps_closed: []
  gaps_remaining: []
  regressions: []
gaps: []
deferred:
  - truth: "rgbcurve（42.0）/ rgblevels（43.0）不在本 Phase 交付"
    addressed_in: "Phase 6+ stretch（无专属 phase，REQUIREMENTS 注记 stretch 补齐）"
    evidence: "D-05-CONTEXT-1（IOP-COLOR-09 交付本体 = colorcontrast 56.0，已交付）+ REQUIREMENTS IOP-COLOR-09 注记行 + V50Order.swift:108-109 槽位在表现表（CurveTools 全复用机械增量）"
behavior_unverified_items: []
human_verification:
  - test: "bilateral 面板真机视觉走查（PLAYBOOK：Debug 产物 + 新文件名 ARW 副本 → 找「表面模糊」行 → 启用 → radius 拖动 → screencapture 量化 → 撤销 1 条，证据归档 FINDINGS）"
    expected: "边缘保持、平坦区噪声消失、tile 缝目检无竖向接缝、撤销还原。自动化腿已绿：PanelWiring 54/54（dispatch + 拖动=1 commit + 复位还原 pristine hash）+ golden 9/9 <1e-6 + 分块==整幅 4.5e-7"
    why_human: "AX 行枚举路径本轮未贯通（L011 口径）；保边平滑为视觉判据。VALIDATION Manual-Only 表 row 1（pending-manual 2026-09-23）"
  - test: "denoise 三件 torture 真实 RAW 目检（高 ISO 样本 DSC00012 补拍后正式 torture 目检）"
    expected: "去噪后细节保持（人眼定标）。自动化已钉方向 + 能量 + parity（≤5.7e-6 / <1e-6 / 8.6e-7）"
    why_human: "「无细节损失」需人眼判据。VALIDATION Manual-Only 表 row 2（pending-manual）"
  - test: "PERF-5 denoise 链 Release 复测（xcodebuild build-for-testing -configuration Release → Release 容器直启复跑 testPhase5DragGateTwoChains，数字补 perf.md）"
    expected: "Release 数字落 perf.md；Debug≈Release 历史 0.92（GPU-bound）外推 ≈79ms，未达标结论不受配置影响"
    why_human: "Release 产物需独立构建轮（test-direct.sh 锁定 Debug 容器）。VALIDATION Manual-Only 表 row 3（pending-manual）"
  - test: "noiseprofiles.json 许可证核对（dt GPL 项目内贡献数据再分发合规判读）"
    expected: "核对结论写 LICENSE-NOTES → 解除「不对外分发」限制（核对完成前限制继续有效，TODO.md:144）"
    why_human: "法律判读需人工。VALIDATION Manual-Only 表 row 4（pending-manual，签核复核仍未完成）"
---

# Phase 5: Color & Denoise iops — 阶段目标级验证报告

**Phase Goal（ROADMAP §Phase 5）:** Advanced color modules（colorbalancergb、color calibration、channel mixer、color zones、monochrome/B&W、vibrance、velvia、color contrast/curves）+ denoise family（profiled raw denoise——第二难移植、NLMeans、bilateral/surface blur、hot pixels/dark frame/chromatic noise）。
**Verified:** 2026-09-23T09:00:00+08:00
**Status:** human_needed（自动化层全绿 + 2 项已裁决 override；4 项 Manual-Only 挂账待人工，均有正式记录、非阻塞）
**Re-verification:** No — 初始验证（阶段目标级，非 plan 级复验）

## Goal Achievement

### 验证方法

从 ROADMAP §Phase 5 的 GOAL + 12 条需求（IOP-COLOR-01..07/09 + IOP-DENOISE-01..04；IOP-COLOR-08 归 Phase 12）+ SC#1-4 反向推导 must-have，逐条在**代码库**找承载实现（模块类/kernel/注册/面板），核内容级测试覆盖（抽查测试体确认真循环非恒真）。SUMMARY 自述不作为唯一证据。证据来源：

1. **注册面**：`LightamerIOP/Sources/Registry.swift`（11 模块 register 实体行 :123-205 + prewarm + seed）+ `LightamerCore/Sources/Foundation/V50Order.swift`（11 槽位全对齐：9.0/10.0/28.5/29.0/39.0/41.5/56.0/57.0/58.0/60.0/64.0）。
2. **测试面**：抽查 5 个测试体（DenoiseProfileParityTests 双 parity 循环 + SC#2 方向测试、NLMeansParityTests chroma/luma 半边门、ColorBalanceRGBParityTests anti-vacuum 循环、BilateralParityTests OQ7 预算、PanelWiringTests TaskGroup×100 竞态回归）——全部真实比较循环 + `compared>0` 断言。
3. **独立实跑**：`xcodebuild build-for-testing` 重编（覆盖 73a1a02 签核后编辑）+ `Scripts/test-direct.sh` 全套一次——**609 tests / 3 skipped / 1 failure**（失败定性见下节，判定为 02-04 台账在案的同族 flake，非 Phase 5 回归）。
4. **GUI 红线**：`.work/gui-acceptance/FINDINGS.md` W1-W7 闭环核对（W6 修复轮 2026-09-23 GUI-10..13 全闭，commits `909b7bd`/`fffd51d` 经 git log 核实在场）。

### 独立实跑记录（flake 定性）

| 轮 | 命令 | 结果 | 定性 |
|---|---|---|---|
| 全套（609） | `zsh Scripts/test-direct.sh`（build-for-testing 重编后） | 609 executed / 3 skip / **1 fail**：`GoldenColorTests.testNeutralPatchesSyntheticTarget`（gray patch level 0.0 vs ≈224——全黑帧读出） | 同类内**失败点轮次漂移**（见下两行）→ 时序性 |
| 类隔离 | `Scripts/test-direct.sh 'GoldenColorTests'` | 6 executed / 2 skip / 1 fail：换成了 **`testCrossConsistencyLinearDomain`**（TODO.md:162 在案的 02-04 遗留 flake，L014 GPU 读回时序同族）；neutralPatches 本轮通过 | 失败点随轮次漂移 = 环境/时序非确定性 |
| 单测隔离 | `Scripts/test-direct.sh 'GoldenColorTests/testNeutralPatchesSyntheticTarget'` | **1 executed / 0 fail（0.083s）** | 全量轮失败测试隔离必现通过 → 按 02-04 台账纪律判定为已知 flake 族，非回归 |

判定：签核轮（08:11）与本轮（08:43）间源码差异仅为 73a1a02 的 BilateralParityTests TEMP print 删除 + 文档（git show 核实），不可能引入 GoldenColor 回归；失败模式与 TODO.md:162「全 suite/类内运行偶发、隔离必现通过」一致。**建议**（非阻塞）：将 `testNeutralPatchesSyntheticTarget`（level 腿黑帧变体）补入 TODO:162 同行 flake 族注记。

### 逐需求判定表

| 需求 | 代码证据（file:line） | 测试证据 | 判定 |
|---|---|---|---|
| **IOP-COLOR-01** colorbalancergb | `Registry.swift:123-125`（v50 41.5，seed DISABLED——D1 默认非恒等论证）+ `ColorBalanceRGB/`（commit 推导 + MSL + D65-native 矩阵）+ `ColorBalanceRGBPanelView.swift`（4 区 + hue 圆盘） | `ColorBalanceRGBParityTests`（轨 A 6 case×8 fixture 真循环，anti-vacuum `:230` + 恒等门 `:317` + hue/vibrance 方向探针）+ dt 采纳 6/6 XMP + `PanelWiringTests` +3（拖动=1 commit） | ✓ VERIFIED |
| **IOP-COLOR-02** color calibration（channelmixerrgb） | `Registry.swift:131-133`（28.5 共槽）+ `ChannelMixerRGB/`（params v3 160B + derive + illuminants/CAT 泛化）+ `ChannelMixerRGBPanelView.swift` | `ChannelMixerRGBParityTests`（6×4 <1e-5 + 矩阵 float64 交叉 + illuminant hash 链）+ dt-cli 采纳 12/12（F1 修复后 88B/160B blob 实跑，`.work/plans/05-03/ADOPTION.md`）+ 28.5 tie-break 回归 | ✓ VERIFIED |
| **IOP-COLOR-03** vibrance / saturation | `Registry.swift:157-159`（58.0，D-05-CONTEXT-8 独立模块非 cb 代偿）+ `Vibrance/` + `VibrancePanelView.swift` | `VibranceVelviaParityTests`（2×6 <1e-5 + 恒等门）+ `VibranceVelviaCommitTests`（Lab 手算点）+ dt 采纳 5/5 | ✓ VERIFIED |
| **IOP-COLOR-04** channel mixer（legacy） | `Registry.swift:138-140`（39.0，弃用头注）+ `ChannelMixer/`（v2 88B + 4 模式 derive）+ `ChannelMixerPanelView.swift` | `ChannelMixerColorContrastParityTests`（legacy 3×4 + ramp≠flat 非空转门）+ dt 采纳（同 12/12 轮） | ✓ VERIFIED |
| **IOP-COLOR-05** color zones | `Registry.swift:164-166`（60.0）+ `ColorZones/`（V2 splines + 3×0x10000 LUT + colorzones_v3 kernel）+ `ColorZonesPanelView.swift`（L-C-h 三 tab + CurveEditorView 复用） | `ColorZonesParityTests`（MAIN 59.7 万样本 strict 100% + SPECTRAL envelope + LUT-direct 双闸 + **hue sweep 全环实跑** `:138-147`）+ `ColorZonesCommitTests` 11/11 | ✓ VERIFIED |
| **IOP-COLOR-06** monochrome / B&W（含色彩滤镜） | `Registry.swift:172-174`（64.0）+ `Monochrome/`（filter/apply kernel + Lab 色轮 + BilateralGrid3D 腿）+ `MonochromePanelView.swift` | `MonochromeParityTests`（4×4 <1e-6 + R==G==B 单色门 + size→∞ 恒等）+ `MonochromeGridTests`（grid==窗口交叉 + 强制分块==整幅——TilingPlan 第三消费者）+ dt 采纳 4/4 | ✓ VERIFIED |
| **IOP-COLOR-07** velvia | `Registry.swift:150-152`（57.0）+ `Velvia/`（RGB pmax/pmin→clamp 本体 + strength≤0 HDR 语义三处对齐）+ `VelviaPanelView.swift` | `VibranceVelviaParityTests`（3×6 含 clamp 100 极端腿）+ `testVelviaStrengthZeroPassesHDRThroughUnclamped` + dt 采纳 | ✓ VERIFIED |
| **IOP-COLOR-09** color contrast / correction curves | `Registry.swift:143-145`（56.0）+ `ColorContrast/`（Lab a/b slope+offset + unbound 双档）+ `ColorContrastPanelView.swift`；交付本体 = colorcontrast（D-05-CONTEXT-1 口径，rgbcurve/rgblevels 划出 → deferred 节） | `ChannelMixerColorContrastParityTests`（3×4 含 bound ±128 钳制腿）+ dt 采纳（20B blob） | ✓ VERIFIED（口径注记入账） |
| **IOP-DENOISE-01** raw denoise（profiled） | `Registry.swift:194-196`（9.0）+ `DenoiseProfile/DenoiseProfileModule.swift`（:596 profiles 消费 + :607 NoiseProfileStore 注入 + 头注 :43-51 EXIF maker/model/ISO→插值→a/b）+ `Common/NoiseProfileStore.swift:79`（actor，433 models 规范化 bundle `LightamerIOP/Resources/NoiseProfiles/noiseprofiles.json`）+ `DenoiseProfilePanelView.swift`（mode/profile/force 曲线） | `DenoiseProfileParityTests`（8×3 ≤9e-6 真循环 + **testSC2ProfileDirections** `:304-354` 三方 RMS 方向断言 + tiling==整幅 + FULL 分块封顶 `:475-492`）+ `DenoiseProfileDerivationTests` 18/18 + dt-cli 采纳 8/8（416B byte-identical）+ `NoiseProfileStoreTests`（手算向量） | ✓ VERIFIED |
| **IOP-DENOISE-02** NLMeans | `Registry.swift:183-185`（29.0）+ `NLMeans/`（六 kernel threadgroup 滑窗 + 降载三件套派生）+ `NLMeansPanelView.swift` | `NLMeansParityTests`（12/12 ≤5.7e-6 + workgroup 扫描逐字节一致 `:134` + 降载推导 + tiling==整幅 `:342` + FULL grid>1）+ MemoryBudgetTests Δfootprint 352MB | ✓ VERIFIED |
| **IOP-DENOISE-03** bilateral / surface blur | `Registry.swift:203-205`（10.0）+ `Bilateral/`（直连 stamp ≤rad6 + 稠密 5D 网格 pentalinear + OQ7 预算）+ `BilateralPanelView.swift`（dt soft range 4 滑块） | `BilateralParityTests`（9/9 golden <1e-6 + 直连 vs 精确公式 8e-7 + σ→0 逐字节 + 路径切换钉参 + 分块==整幅 4.5e-7 + **testOQ7BudgetFormulaAndBounds** `:417-447` 公式/100MP 上界/放粗收敛）+ dt-cli 采纳 3/3 | ✓ VERIFIED |
| **IOP-DENOISE-04** hot pixels / dark frame / chromatic noise | chromatic 半边：nlmeans `chroma` 参数（`NLMeansModule.swift`）+ denoiseprofile Y0U0V0 色度模式；hotpixels/dark-frame 正式 defer（模块头注 + D-05-08-T4-1） | `testLumaZeroChromaOnlySmoothing`（NLMeansParityTests `:611-649`：chroma 平滑 + ΔL 压倒性方向门）+ `testChromaZeroLumaOnlySmoothing`（`:651+` 通道分离门）+ denoiseprofile 色度腿 | ✓ VERIFIED（chromatic 半边交付；defer 部分经 override #2 裁决） |

### SC#1-4 判定（ROADMAP 契约）

| SC | 判据 | 代码/测试证据 | 独立实跑 | 判定 |
|---|---|---|---|---|
| **SC#1** | color 八模块全部 match Darktable references | manifest「Phase 5 golden 完整性总账」11/11 有账（`input/golden/manifest.md:1009-1029`）+ 逐模块轨 A parity（合成 float64 参考，L017 双轨）+ dt 三证据（blob XMP 采纳 + `--d params` ok + 平场探针）齐；抽查 3 个 parity 测试体均真循环 + anti-vacuum | 本轮全套实跑相关 ParityTests 全绿（唯一失败为 GoldenColor flake，见上） | ✓ VERIFIED（rgbcurve/rgblevels 划出口径注记入账） |
| **SC#2** | profiled raw denoise match + per-camera profile loaded from EXIF/metadata（spike 正式验证） | parity 8×3 ≤9e-6 + **SC#2 闭环三断言**（`testSC2ProfileDirections`：correct<noisy / correct<generic / mismatch≥correct——真值=clean ramp、输入=种子化 iso1600 加噪）+ `NoiseProfileStore`（EXIF 链 + 线性插值 + generic 回落）被 `DenoiseProfileModule.reloadDefaults` 消费 + manifest「SC#2 = PASS」结论行（`manifest.md:962-964`） | 实跑含该测试，全绿 | ✓ VERIFIED |
| **SC#3** | NLMeans / bilateral / chromatic 去噪不损细节（torture images） | NLMeans：torture 加噪集 parity ≤5.7e-6 + strength 单调三档 + luma/chroma 半边方向门；bilateral：9/9 <1e-6 + delta 脉冲远场回平场 + σ→0 恒等；chromatic：两半边方向测试钉住。hot-pixel/dark-frame 域不可达正式 defer（override #2） | 实跑全绿 | ✓ VERIFIED（口径注记 + override） |
| **SC#4** | 全 color/denoise 模块 PREVIEW 60fps 拖动 + tiling fallback 承重 | 拖动门 `PreviewChainPerfTests.testPhase5DragGateTwoChains:410-501`（真实拖拽帧型：稳定 imageID + params tick，median of 10）：**color 七件链 4.8ms 达标 ✓**；denoise 单件链 85.7ms 未达 ✗（降载 7.5× 兑现后仍不达 → Open#9 应急判定成立但 ~5% 贡献非正杠杆 → 移交 Phase 6+，TODO:143 公开挂账，override #1）。**tiling fallback 承重 ✓**：四消费者（nlmeans/denoiseprofile/bilateral/monochrome）「分块==整幅」四套件全绿（实测 ≤5.7e-6/0.0/4.5e-7/<1e-3，grid>1 断言）+ FULL Δfootprint 有界（`MemoryBudgetTests.testNLMeansFullFootprintBudget:84` mach_footprint 实测 352MB / denoiseprofile 35 tiles / bilateral OQ7 公式上界 1.47GB 放粗收敛） | 拖动门测试在本轮全套实跑中绿（sanity 门 <500ms）；60fps 数字来自签核轮 PERF8 记录（`.work/05/perf.md`，Debug，Release 外推 ≈79ms） | ⚠️→**PASSED (override)**（denoise 拖动半边未达标已裁决：触发条件→判定→证据→移交→公开挂账全链齐备，非静默放宽；tiling 半边全绿） |

### 内容级验证覆盖抽查（非恒真确认）

- `DenoiseProfileParityTests.swift:304-354`（SC#2）：truth=clean ramp EXR、input=种子化加噪 EXR（「noisy pixels are the pipe INPUT, never the baseline」注释显式防恒等真空转），三条 RMS 方向断言（①剖面匹配胜 generic ②错配欠去噪方向）——SC#2 的正式验证非自述。
- `NLMeansParityTests.swift:611-649`（IOP-DENOISE-04 chromatic 半边）：全像素 Lab 双循环 + `compared>0` + 「ΔL 压倒性大于 Δab」通道分离方向门。
- `ColorBalanceRGBParityTests.swift:230`：`XCTAssertGreaterThan(compared, 0, "parity loop compared zero pixels — anti-vacuity")` + `:317` 恒等门双循环。
- `BilateralParityTests.swift:417-447`（OQ7）：grid_bytes 逐项算式钉参 + 100MP $DEFAULT 档 22GB→预算内放粗收敛 + 极限预算 16KB 不发散。
- `PanelWiringTests.swift:892-946`（W6 GUI-13 回归）：TaskGroup 交错发射 100 轮（recordChange 腿 + setLiveParams 腿同发，与崩溃报告双栈同构）+ commit 计数精确断言 + 终态一致性——GUI-10/13 修复的常驻回归钉。

### 漂移检查（计划外管线共享路径改动）

| 漂移 | 改动位置 | 回归钉住 | LESSONS | 判定 |
|---|---|---|---|---|
| 05-01 iscale stamp | `IOPiece.swift:57`（dt piece->iscale 同构）+ `PixelPipe.swift:517-527`（run 前向 walk 唯一写点 + tile 内不可改写契约） | `IOPieceIscaleTests`（三档 stamp + 跨 piece 常量 + 强制分块不变性）+ `TileNegotiationRegressionTests`（stamp 不变性 + 四消费者预演 :231） | L021 沿用（dscIn 禁 ×scale，11 模块 ROI 头注钉死） | ✓ 可接受（有回归、有记录） |
| 04-03 union-clamp（沿革沿用） | `PixelPipe.swift:700`（`roiIn.clamped(to: frameROI.union(roiOut))`） | `ROINegotiationTests.testAshiftWarpAABBGrowsOutputAndBoundsInput:441` + `testCropForwardShrinkDownstream:273` + `testSharpenBackwardExpandsUpstream:367`（Phase 4 钉全数在场未回退） | L020 | ✓ 可接受 |
| W6 moduleList ScrollView（GUI-11/12 布局修复） | `InspectorView.swift:93`（`ScrollView(.vertical)`）+ `:69-70,86`（高度 = min(内容, 38% 列高) 约束） | FINDINGS.md W6 节闭环记录（AX 压力 20 轮零崩溃 + 布局量化）+ PanelWiring AX 语义层钉（面板 dispatch/拖动=1 commit 与布局解耦） | GUI 红线走查（AGENTS.md Phase 执行模型） | ✓ 可接受（视觉面留 GUI 轮，AX/量化在档） |
| W6 setParams 同步化（GUI-10/13 竞态修复） | `ModuleBox.swift:187-194`（async→sync，注释引 forensics `.work/gui-acceptance/gui10-forensics.md`：修复前双线程并发 over-release paramsData） | `testEnableCommitRacingLiveTicksHundredRounds`（PanelWiringTests:892，×100 交错发射 + 计数精确 + 终态一致） | 取证记录落 gui10-forensics.md | ✓ 可接受（有回归、有记录） |

LESSONS 落账核对：L022（omp 编辑冲突）、L023（uniforms 半边契约→parity 钉全往返，05-02 invert 恒真修复沉淀）、L024（bilateral grid 双移植缺陷：步长/位权 + 滚动 tmp 跨通道）——三条均在 `LESSONS.md`（:197/:204/:190 附近），与 Phase 5 实际踩坑一一对应。GUI 红线：05-02/03/04/05/06/07 各轮 FINDINGS 登记 + W6 闭环 + 05-08 汇总复核（FINDINGS.md:449-451「W1-W7 全轮 GUI-1..13 全部闭环」）——红线已满足（bilateral 真机视觉走查为唯一 pending-manual，L011 口径）。

### Gap 清单

**须补做：无。** 自动化层未发现 MISSING/STUB/NOT_WIRED/恒真测试/未钉回归的漂移；12/12 需求在代码库交付且注册（11 dt 模块 + chromatic 半边承载于 nlmeans/denoiseprofile 双件）。

**可接受裁决/挂账（7 项，均有正式记录、非阻塞）：**

| # | 项 | 记录位置 | 性质 |
|---|---|---|---|
| 1 | SC#4 denoise 链 60fps 未达标（85.7ms Debug）——Open#9 应急判定 + 正杠杆移交 Phase 6+/perf plan | `.work/05/perf.md` + 05-08-DECISIONS D-05-08-T6-1 + TODO.md:143 + override #1 | 已裁决公开挂账（非静默放宽；判定链完整） |
| 2 | rgbcurve/rgblevels 划出 | D-05-CONTEXT-1 + REQUIREMENTS IOP-COLOR-09 注记 + V50Order:108-109 槽位在表 | 规划期签核裁决 → deferred |
| 3 | denoiseprofile VARIANCE 模式划出（enum 位保留 + UI 禁用注记 `DenoiseProfilePanelView.swift:9`） | D-05-CONTEXT-3 + 模块头注 | 规划期裁决（v1 后补路径明确） |
| 4 | channelmixerrgb color-checker 自动剖面子树划出（`ChannelMixerRGBModule.swift:32-34` NOT PORTED 头注 + params 位保留） | D-05-CONTEXT-5 + 模块/Common 双处头注 | 规划期裁决（v2/Phase 12 再议） |
| 5 | wb ≡ (1,1,1) 已知分歧（真实 CIRAW WB 增益接入留管线级 stamp；参数化就绪 `DenoiseProfileModule.swift:35-38,205-206`）；highlight-pres ISO shift 恒 0（metadata 源 v1 缺，公式已移植单测） | D-05-07-T2-1 + 模块头注 | 已知分歧，Phase 6+ 接线点注记 |
| 6 | Manual-Only 3 行（bilateral 视觉走查 / torture 目检 / Release 复测） | VALIDATION Manual-Only 表 + TODO.md:145（L011 口径） | 人工挂账 → human_verification |
| 7 | noiseprofiles.json LICENSE 未核对（不对外分发限制有效） | `LightamerIOP/Resources/NoiseProfiles/LICENSE-NOTES.md`（在档）+ TODO.md:144 + VALIDATION row 4 | 人工法律判读 → human_verification |

**文档漂移（Info 级，不改判）：** `.work/05/perf.md` 将 bilateral FULL footprint 门归到「MemoryBudgetTests」——实际承载为 `BilateralParityTests.testOQ7BudgetFormulaAndBounds`（公式上界 + 放粗收敛，非 mach_footprint 实测；mach_footprint 实测腿为 nlmeans `MemoryBudgetTests.testNLMeansFullFootprintBudget` 与 denoiseprofile `testFullFootprintBudget`）。覆盖实质存在，仅归属行文不准，建议下次触碰 perf.md 时顺手勘正。

### 反模式扫描

11 模块目录 + Registry + 11 面板全量扫描：无 TBD/FIXME/XXX/HACK/PLACEHOLDER/空实现/`return null`/未接线 TODO（唯一历史命中 `Registry.swift:5` 的 `XXXModule` 模式名文档占位非债务；05-07 的 TEMP DEBUG 与 73a1a02 删除的 TEMP probe print 均已清）。73a1a02 提交的 golden-dump pfm 为 flake 取证档案（.work/），非常驻债务。

### Requirements Coverage

REQUIREMENTS.md 映射表（:308-324）：IOP-COLOR-01..07/09 → Phase 5 Delivered、IOP-DENOISE-01..03 Delivered、IOP-DENOISE-04 Resolved（chromatic 交付 + defer 裁决）、IOP-COLOR-08 → Phase 12（PRES-03 同体）——与代码库状态一致，无 orphaned 需求。需求复选框行（:69-91）已勾选（除 COLOR-08）。

### Human Verification Required

见 frontmatter `human_verification` 4 项（bilateral 视觉走查 / torture 目检 / Release 复测 / LICENSE 核对）——全部为 VALIDATION Manual-Only 表在案项（L011 口径），自动化腿均已覆盖语义/数值。

## 结论

**GOAL ACHIEVED-WITH-GAPS → 判定 ACHIEVED（无阻塞缺口）。** 12/12 需求在代码库交付且注册（11 模块 v50 槽位全对齐 + seed + 面板 + zh catalog），SC#1-3 自动化证据全绿（SC#2 加噪→去噪闭环 + 错配方向断言为真测试），SC#4 = color 链 60fps 达标 + tiling fallback 承重全绿，denoise 拖动 60fps 半边为**已裁决公开挂账**（override，判定链/证据/移交齐备，非静默放宽）。漂移改动均有回归钉住且 LESSONS 落账；GUI 红线验收 W1-W7 闭环。独立实跑 609/3/1 的唯一失败经隔离判定为 02-04 台账在案的 GoldenColor flake 族（失败点轮次间漂移 + 单测隔离必现通过），非 Phase 5 回归。剩余 4 项人工挂账（3 视觉/性能 + 1 法律判读）→ GSD status `human_needed`：阶段目标已达成，人工补验完即可关账。

---

_Verified: 2026-09-23T09:00:00+08:00_
_Verifier: Claude (gsd-verifier, goal-backward 阶段级)_
