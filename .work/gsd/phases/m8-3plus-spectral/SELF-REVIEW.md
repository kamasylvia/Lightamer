# M8-3+ 域内自审报告（omp subagent review）

PASS / 3 error + 12 minor

> error = 阻塞收口必须修（修码或 DECISIONS 申报 + orchestrator 接受后降级）；minor = 建议修（多可 DECISIONS  cure）；obs = 观察不计数（7 项附后）。
> T7 尚未收口：SUMMARY / DECISIONS / 走查 MANIFEST 均未落地——凡标注"待 DECISIONS"的项须 T7 落盘后二核。

## 审对象

- T1 `0b9f480d` / T2 `d0e175af` / T3 `51efaa14` / T4 `a85dbcb4` / T5 `fd9e85d7` / T6 `eb6d3953`（`git log --oneline` 自查，feat(m83p) 链连续，refs #21）
- T7 未提交面：`Tests/LightamerTests/SpectralSpatialLegTests.swift`（+2 冒烟）+ BUNDLE-MAP 行内数 4→6
- PLAN 正本 `.work/gsd/phases/m8-3plus-spectral/M8-3+-PLAN.md`（v1）；上游正本 dt spektrafilm `4d1fb6a95b` 树（git show 全带树号；HEAD 已无 wide 符号已避开）
- 方法：只读产物 review；隔离遵守（未读 omp 日志/lane prompt）；唯一写动作 = 复跑两 evidence 脚本验证可复现，复跑弄脏的 2 个 RECORD 文件已 `git checkout --` 复原（见 m12，自披露）

## Error（阻塞收口）

### E1 grain 参考尺度转录错：`referenceUm = 47.0`，上游 `SF_GRAIN_REF_UM = 10.0f`，单测把错值钉死

- 证据：`LightamerCore/Sources/Film/SpectralGrainSublayer.swift:33-34` 注释自称"Upstream's fixed reference scale (µm — `SF_GRAIN_REF_UM`)"，值 `47.0`；上游 `git show 4d1fb6a95b:src/common/spektra_core.h:326` = `#define SF_GRAIN_REF_UM 10.0f`；`pix_ref` 消费链上游 `spektra_sim.c:2546-2548/2574-2575`（`pix_ref = ref_um²`，`npart = pix_ref / max(a_grain,1e-4)`）。
- 影响：`pix_ref` 2209 vs 100（22×），`npart` 反解全错；`Tests/LightamerTests/SpectralGrainDeriveTests.swift:92-123` 用 47² 自洽重算 expected（错值钉死，单测全绿但对照错的真值）。
- 同文件其余公式亲核正确（d_ref/sig/denom/a_grain 与 `spektra_sim.c:2571-2575` 一致；A48 = π·24² 一致）。
- 复现：`git -C /Volumes/UNITEK/Documents/Development/darktable show 4d1fb6a95b:src/common/spektra_core.h | grep -n GRAIN_REF` vs `sed -n '31,36p' LightamerCore/Sources/Film/SpectralGrainSublayer.swift`。
- 处置：47→10 + 单测 expected 同改；若执行 lane 能指出 47 的另一上游出处则降级（本审按引用源 10.0 判错）。

### E2 C 收敛是死面：caption 承诺收敛，picker 数据源从未切换

- 证据：`App/Sources/Lightamer/UI/Shell/FilmPanelModel.swift:493-512` `convergedPaperStocks`（正片返回 incumbent+2383/2393）；View 纸 picker `App/Sources/Lightamer/UI/Shell/FilmPanelView.swift:257-265` 用 `paperStockSections`，其源 `FilmPanelModel.swift:125-133` = `paperStocks`（paper-support，不含 film-support 的 2383/2393）；`grep convergedPaperStocks App/` 仅 Model + 单测命中，View 零引用。
- caption（`FilmPanelView.swift:333-335`）称 "converges onto print film (2383/2393) — the current paper stays until you switch"，但用户在 picker 里永远切不到 2383/2393（单测 `FilmPanelClampedTests.swift:115-145` 注释自认 "the picker cannot bind it"）。
- PLAN T2 A5 要求"正片新选 paper 数据源 = print-film 档"——View 层未交付。
- 处置二选一：picker 接 `convergedPaperStocks`（support 分裂下 2383/2393 能否被纸面绑定须先裁决，不可硬接）；或改 caption 为诚实口径（收敛目标不可选现状 + 手动路径）。caption 现状虚假承诺，须修一侧。

### E3 grain `npart` 生产路是占位 1000：`derive`  dead（仅单测调用）+ "T5 接线"承诺过期

- 证据：`LightamerCore/Sources/Pipe/Film/SpectralPayloads.swift:987` `npart: 1000.0`；注释 `:964-968` 称 "npart rides the neutral default — the per-stock RMS wires in T5's allocator turn"——T5（`fd9e85d7`）已落地，无接线（`grep -rn "\.derive(" LightamerCore/Sources/Pipe/` 零命中；`derive` 调用者仅 `SpectralGrainDeriveTests.swift:96/130/134`）。
- 生产调用链 `dispatchGrainGroup :801-805` → `sublayerRowsForGrain`（占位），`SpectralGrainSublayer.derive`（E1 的错值所在）零生产消费。
- 影响：on 档 grain 全 stock 全通道同一 npart=1000（上游 RMS 17 典型 npart ~200 量级，1000 偏细 ~5×），面板/arm 无占位披露；on 档 golden（`SpectralGrainGoldenTests.swift:207-242`）仅断言 differs + deterministic，不校验 upstream 正确性。
- 处置：接线 derive（先修 E1）或 DECISIONS 申报"占位 grain + T7 后立项接线"并加面板 caption；注释 "T5's allocator turn" 过期必改（无论选哪条）。

## Minor（建议修）

### m1 "bit-identical" 陈旧断言 vs ULP 带现实（注释 + 测试名）

- `LightamerCore/Sources/Film/SpectralBuildEngine.swift:264-270` 称 "14 safety pairs pin anchored-vs-(50,50) bit-identical"；实测 `SpectralNeutralSolveTests.swift:165-205`（名 `testSafetyPairsHoldBitIdentityAcrossSeeds`）体用 `accuracy: 1e-9`（注释自述 worst 1231 ULPs ≈ 8.7e-12）。T1 commit message 诚实申报 ULP 带，但源码注释与测试名仍称 bit-identical。
- PLAN T1 A2/R-M83P-3 要"逐位恒等"——执行降为 1e-9 带（K1 分叉判据同步降为"CC 点量级移动"）。降带有理（Newton 路径依赖），但属 PLAN 偏离，待 DECISIONS 登记；注释与测试名须同步改（"bit-identity"→"1e-9 band"）。

### m2 阈值"交点法定"三处注释虚假陈述 + 重标探针未跑 + 两臂行为无单测

- `SpectralWideBlurPlan.swift:26-28` / `SpectralPayloads.swift:1236` / `:1693-1694` 均称 T5 probe"法定"终值；实情：T5 commit 诚实写 "re-mark reserved to T7 evidence"，`wideEffectThreshold` setter 全仓零调用（仅 `:1241` 一处消费），`effectSigmaStart`（`:31`）零消费，T7 未提交面无阈值探针。
- PLAN R-M83P-5① 要"阈值两侧 ±20px 双臂误差曲线交点法定值 + 默认 halation 阈下零变化负测"——两项皆无（`SpectralWideBlurGoldenTests` 阈值注释 `:17-21` 只描述未断言）。
- 阈值仅决定 exact/wide 走哪臂（两臂各自正确性由 trio逐位覆盖），属优化面非正确性面，故 minor：改三处注释为"100 起步值，重标 pending" + DECISIONS 登记，或 T7 补探针。

### m3 28 对 sweeping 只有 finite（PLAN 要哨兵 hash 逐位）

- `SpectralGrainGoldenTests.swift:176-205` 28 对仅断言 finite；fused-vs-split 等价证明只剩单 ramp512 hash（`:35` 值 `3613671270926763817` = STATE M8-2 行亲核一致）+ B1/B2 verbatim（本审逐行对拍通过）+ fma 同源论证。
- PLAN R-M83P-4/T4 A1 主门 = "28 对全扫逐位 + C200 回退档"。现状诚实（T4 message 写 "28-pair finite"），但证明厚度不足。修前 fused 值已不可追（除考古重跑），建议 DECISIONS 接受降级（单哨兵 + verbatim + 全套绿）或考古补 27 hash。

### m4 seed 自动折覆盖 2/5 腿

- `FilmRecordSpatialTests.swift:75-121` 只翻转 grainAmount + diffusionFamily；halationAmount / diffusionAmount / reversalPrintMode 未翻。PLAN T3 A3 要"逐字段翻转各一"。seed 机制本身亲核为真（`FilmTailPolicy.swift:57` 读 `record.stableHash()` + `:156` 折 recordHash；record 编码 synthesized，nil 缺席→hash 不动）。
- 补 3 个翻转断言（5 行级）。

### m5 bake 不折从行为证明降为源码 census

- `FilmRecordSpatialTests.swift:150-182` 用 `foldTag(` 调用点 census（3 = filter/grade/reversal，亲核 `FilmPrintBake.swift:570/577/581` 在位，reversal 折 print/scan 键 `:581` 正确，tc 键不折正确）；PLAN T3 A4 要"同 pair 异 amount → 三槽 HIT + 平面 seed 变"行为面。census 脆（改名即崩）且不证明运行时 HIT。
- 注释诚实写 "Proved at the SOURCE face"。minor：接受现状 DECISIONS 登记，或补行为腿。

### m6 kernel 16 > 预算 12

- `SpectralSpatialKernels.metal` 实数 16：grain 五 + blur 对 2 + wide 三 + bank/mix/combine/apply 4 + gauss 对 2；PLAN 红线"≤12，DECISIONS 落终清单"，K7 要求"合并或 DECISIONS 申报扩预算（不得自裁）"。
- 8 个调用面全有消费（grep 逐 kernel 有 `SpectralPayloads.swift` 引用，无死 kernel）。DECISIONS 扩预算登记即可 cure。

### m7 print-diffusion B2 座位无 on 面（A8 双座位只交一半）

- B2 钩 `SpectralFilmKernels.metal:934-943` 为 `gate==0 ? loge : loge` 空三元（注释诚实：packet 是另行调度的 kernel 对，NOT inline）；host 侧 `SpectralPayloads.swift:498-500` 恒填 0，全仓无非零装配、无 packet 调度；`grep printDiffusion Tests/` 零命中。
- PLAN T5 A8 要"双座位各一腿"——taking diffusion 有腿（前置腿，上游序 taking→halation 亲核 `SpectralPayloads.swift:1153+` 注释与分支），print 座位零腿。off-identity 安全（恒 0），功能半交。DECISIONS  scope 声明（print 腿挂账）cure。

### m8 probe kernel 未随拆口更新

- PLAN R-M83P-4 要求 probe 测点进 B1 出口 + B2 入口；`spectral_film_stage_probe`（`:956+`）仍是旧 0-6 单 stage 形态，T4 diff 未触。probe 系 debug 通道（生产零消费），现有 probe 单测仍绿（语义未变），故 minor：DECISIONS 登记"沿用旧测点"或补 B1/B2 mode。

### m9 反转 B 残差门 +1.0（PLAN 要 <）+ 曲线旁路数学断言过强

- `SpectralConservationFallbackTests.swift:268-300` 断言 `direct.residual < legacy.residual + 1.0`，注释诚实注"不同 target，sanity-banded"；PLAN T2 A4 要"残差 < legacy 残差"（跨 target 比较本无意义，PLAN 门错，执行诚实降门）。
- `SpectralNeutralSolve.swift:332-336` 称纸曲线"monotone per-channel, so ratio-zero upstream = ratio-zero downstream"——单调≠线性，异通道曲线会搬移比值，断言数学上过强（实现本身是启发式 solve，ladder 良构，无错）。
- 改注释为"近似（启发式），真值由 parity 腿标定" + DECISIONS 登记门变更。

### m10 A1 单调门从"40 轮逐轮降"降为"终值不爬升"

- `SpectralConservationFallbackTests.swift:97-157` 只比终值 ≤ 墙点残差；PLAN T2 A1 要"40 轮内残差单调降"。注释诚实解释初版比错对（1D 墙约束解不可能胜过 2D 无约束解——正确）。修后门仍有约束力（能抓爬升/符号错），但弱于 PLAN。DECISIONS 一句话登记。

### m11 ΔN +52 越 PLAN 带 +27..40（上沿 +12）

- 实测（`grep -c "func test"`）：T1 5 / T2 5+2+3=10 / T3 3+4+3=10 / T4 6+4+2=12 / T5 6+1+4+2=13 / T6 0 / T7 2，合计 +52，与各 commit message 申报逐项一致。
- 越带主因：T3（+10 vs +3..5，记录三面+seed+优先级+bake 拆法过多）/ T4（+12 vs +6..8）/ T5（+13 vs +8..11）——覆盖性超交（honest over-delivery），非注水。
- BUNDLE-MAP 行内数与实测逐项一致（12 行：5/5/2/3/3/4/7/6/4/6/1/6 全中；T3/T4/T5 树时点 MAP 时机也亲核一致）；Project.swift 12 登记行在位。
- 待 DECISIONS 越带理由（PLAN checker 要求）。

### m12 evidence 脚本非幂等：复跑重写 RECORD（本审污染已复原，自披露）

- `static_replay.py`（12/12 PASS，exit 0）与 `t6_probe.py`（3 PASS，exit 0）复跑可复现，但会重写 `REPLAY-RECORD.md` / `T6-PROBE-RECORD.md`（复跑后 `git status` 2 文件 M）。本审已 `git checkout --` 复原，工作区无残留（复原命令见本审取证记录）。
- 建议：脚本写 RECORD 前比对内容一致则跳过（幂等），或 RECORD 标注"复跑可刷新"。

## Obs（观察，不计数）

- o1 fused `stage_b` 残留仅两处注释（`SpectralFilmKernels.metal:36` 头注、`SpectralKernelGoldenTests.swift:225` 注释），代码零引用；三处旧单测（KernelGolden/LegFork/PerfProbe）已迁 B1→B2 链。退役彻底。
- o2 `SpectralGrainGoldenTests.swift:36` `closureSpread` 声明零消费；`fixtureImageID` 仅作 imageID，无 fixture 平面 hash 断言——哨兵三件套仍由 dual-arm 套件拥有（fixture `7557687968680693683` 在 `SpectralDualArmGoldenTests.swift:69` 下划线形、`closure 0.1300766902548187` 在 `:80`、v1 主门 `14_365_179_805_968_017_957` 在 `FilmDeterminismTests.swift:44`，三值与 STATE M8-2 行亲核一致；dual-arm 12 法计数未变）。
- o3 Swift 转录件只有归属注（`SpectralSpatialTables.swift:1-27` / `SpectralWideBlurPlan.swift:1-22` / `SpectralGrainSublayer.swift:1-29` 均有 `(C) darktable developers` + 4d1fb6a95b 行号），完整 GPL 头仅 `.metal` 有——与仓内 Swift 惯例一致（`SpectralBuildEngine.swift` 等亦无 GPL 块），合规。
- o4 `amount != 0` 跳过门（`SpectralPayloads.swift:734`）放过 NaN（NaN 会 dispatch）——JSON/panel 不可达 NaN，仅手构造 record 可达；nil/0 双证明齐（grain `:243-261` + spatial `:200-241` 含 orphan 优先级腿），口径一致。
- o5 seed-ULP vs bake 键理论缝：seed  deterministic per triple（锚表查表 `FilmPrintBake.swift:606-623`，缺席回落 (50,50)），实践无影响；"PCHIP 表 seed 不变"宣称在 ULP 带下近似成立。
- o6 T7 收口件 pending（SUMMARY/DECISIONS/MANIFEST 未落地）——m1/m2/m3/m5/m6/m7/m8/m9/m10/m11 + T6 A4 B-1 注记 + v4 预留登记皆系于此，落盘后须二核。
- o7 direct-positive 分支 intentionally 跳过 fallback（`SpectralBuildEngine.swift:773-785` 有 solve 无 fallback；legacy 臂 `:787-800` 有）——与 R-M83P-1 "B 亦钳制→手动 CC caption"一致，K6 路径；非遗漏。

## 分维度结论（与执行自验错开切口）

1. 封存面 17 件：PASS。除 `LightamerSidecar.swift`（例外①：`:254-269` 注释 + digit 12→13，hunk 纯净）外，`git diff --name-only 0b9f480d^..HEAD` 50 文件无一触及其余 16 件；PixelPipe 零触（例外②未启用）；编码器三件（ExportFormatSpec/ImageIOEncoders/WebPEncoder）零命中。
2. 双臂冻结：条件 PASS。v1 两文件零 diff（grep 零命中）；RenderProcess 零 diff + current 恒 3（`:92`）；M8-2 哨兵三件套值亲核全中；14 安全档为 ULP 带非逐位（→m1）。
3. B 拆口诚实面：条件 PASS。退役彻底（o1）；B1/B2 = fused 逐行 verbatim（`steps` 读位移 B2、中 split 写，语义中性；B2 增量仅 T2 gain + T5 空钩）；npart 占位（→E3）；amount-0 双证明口径一致（o4）。
4. 宽模糊转录：条件 PASS。plan（k/ox/oy/lw/lh/inv/min16）/rows/down/up 与 `4d1fb6a95b`（core.c:391-422/437-560，cl:1013-1068）逐行对拍一致（fma/钳制/打包差仅 Metal 方言）；TRUE-σ 偏离三处显式申报（头注 + NOTICE 3c + T5 message）；阈值（→m2）。
5. 反转 B 语义：条件 PASS。ladder 良构（scan XYZ 比归零，拨盘座位不变）；曲线旁路断言过强（→m9）；C 收敛死面（→E2）。
6. 回退数学：条件 PASS。A1 门弱化但诚实（→m10）；gain 经共享多项式 log-add（kernel `:642-652`，ones→+0 恰恒等）；PCHIP 未动，bake 键诚实（reversal 折 print/scan `:581`，tc 不折）；`midgrayPrintRaw` 补偿（engine `:819-823`）与渲染面一致；B 臂跳 fallback 系设计（o7）。
7. seed/键面：条件 PASS。自动折为真（FilmTailPolicy `:57`+`:156`）；覆盖 2/5（→m4）；bake census 3 fold 含 reversal（→m5）。
8. GPL 纪律：PASS。转录清单行号全实（grain.h / cl:510-660 / sim.c:100-122、2569-2592 / core.c:391-422、780-900、936-1000 / cl:1013-1068）；NOTICE 3b/3c 在位；版权头（o3）。E1 污染一处"verbatim values"宣称，随 E1 修。
9. i18n：PASS。xcstrings 2116→2128 纯插入（0 删除行，0 既有改；T2 6 + T4 2 + T5 4 = 12 键与 message 吻合，12 键全在 FilmPanelView 有消费）；zh-audit 双 PASS 本审复跑通过（--check 1795 源键/2128 目录键；--self-test V17）；禁形零命中（runModal 0；插值构键仅一条 doc 注释提及）。
10. ΔN 对账：数字 PASS，带位越带。+52 实测 = 申报（逐任务 grep 计数吻合）；PLAN 带 +27..40，越上沿 +12（→m11）；MAP/ Project/时点机检全绿。

## 越带/偏差申报复核（待 T7 DECISIONS 落盘后二核）

| # | 偏离 | 现状申报位 | DECISIONS 需补 |
|---|---|---|---|
| D1 | seed 逐位→1e-9 带（含 K1 判据降门） | T1 message + 单测注释 | 登记 + m1 注释/名修复 |
| D2 | Evidence C / §1.3 C200 行真值被 replay 推翻（106.3/197.5→108.33/250 墙） | REPLAY-RECORD calibration notes | 登记（定标漂移口径） |
| D3 | 轮数 HOLD 32（velvia×crystal 烧满） | T1 message + 单测 `:272-317` | 登记 |
| D4 | A1/A4 门弱化（m9/m10） | 单测注释 | 各一句话 |
| D5 | 28 对 hash→finite（m3） | T4 message | 接受降级或考古计划 |
| D6 | bake HIT→census（m5） | 单测注释 | 一句话 |
| D7 | kernel 16>12（m6） | 无 | 扩预算 |
| D8 | print 腿座位无 on 面（m7）+ probe 未更新（m8） | 代码注释（诚实） | scope 声明 |
| D9 | 阈值未法定（m2） | T5 message（诚实） | 终值或 pending 声明 |
| D10 | ΔN +52（m11） | 各 message | 越带理由 |
| D11 | C200 修后对照表（PLAN T2 A3 要修前修后表） | T2 message 只有修后（<0.5%/clamped/Y=250）+ 单测 `>200 steps`（修前 posterize 无钉值） | 修前值考古或声明缺口 |
| D12 | T6 A4 B-1 注记 + v4 预留登记 | 无 | 各一句话 |
| D13 | E2/E3（caption/derive） | 无（E3 有过期注释须改） | 修码或降级接受 |

## 机检命令摘要（复现路径）

- 链：`git log --oneline`（T1..T6 连续）+ `git status --short`（T7 两文件未提交）
- 封存：`git diff --name-only 0b9f480d^..HEAD | grep -iE "Drt|TerminalTail|PixelPipe|Lut3d|Export|NodeGraph|Sidecar|History|PipelineDocument|V50|GradeCatalog|NodeOwnership|Registry|ModuleInstance"`（仅 Sidecar 三文件）；编码器 grep 零命中；`git diff 0b9f480d^..HEAD -- LightamerSidecar.swift`（单 hunk）
- 冻结：v1/RenderProcess/GrainModule/CC 零命中 grep；`RenderProcess.swift:92` current=3
- xcstrings：python json 对账（2116→2128，DELETED []，MODIFIED []）+ `git diff -- xcstrings | grep -c "^-[^-]"` = 0
- zh-audit：`python3 Scripts/zh-audit.py --check` PASS + `--self-test` PASS（本审实跑，103s）
- 禁形：`runModal(` App 零命中；`LocalizationValue("prefix_` 零命中
- kernel：`grep -c "^kernel "` = 16；调用面 8/8 有消费
- 上游：`git -C <darktable> show 4d1fb6a95b:<path>` 逐段对拍（plan/down/up/trio/families/halation/nl==1/ref 常数）
- ΔN：`grep -cE "func test"` 12 文件 + MAP 逐行 + 三树时点 MAP
- evidence：`python3 static_replay.py` 12/12 exit 0 + `python3 t6_probe.py` 3/3 exit 0（后复原 RECORD）
