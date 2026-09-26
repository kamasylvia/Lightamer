# Phase 5: Color & Denoise iops - Context

**Gathered:** 2026-09-21
**Status:** Ready for planning — 8 项 Open Questions 全部裁决（采纳 05-RESEARCH 推荐；既定授权模式：推荐可逆且已论证，可审阅推翻）

<domain>
## Phase Boundary

Color（colorbalancergb、channelmixerrgb/color calibration、channelmixer legacy、colorzones、monochrome、vibrance、velvia、colorcontrast）+ Denoise（denoiseprofile、nlmeans、bilateral/surface blur、chromatic noise 承载）——12 项需求（IOP-COLOR-01..07/09 + IOP-DENOISE-01..04）→ 11 个 dt 模块映射。核心架构目标：**TilingPlan 首次多模块承重**（nlmeans/denoiseprofile/bilateral/monochrome 四消费者，100MP FULL working set 超预算必分块）+ **SC#2 噪声剖面 spike 的正式验证闭环**（加噪→去噪→剖面错配方向断言）+ **SC#4 60fps 拖动门**（denoise 预览降载三件套 + D-C3 梯子）。

**Phase 5 不做**：rgbcurve/rgblevels（D-05-CONTEXT-1 划出）、IOP-COLOR-08 .cube LUT（Phase 12 = PRES-03）、hotpixels/dark-frame raw-domain 腿（D-05-CONTEXT 关联 defer，见 05-08 决议）、denoiseprofile VARIANCE 模式（D-05-CONTEXT-3）、channelmixerrgb color-checker 自动剖面（D-05-CONTEXT-5）、mask_display 棋盘预览（Phase 6 蒙版域）、管线级 Lab leg（D-05-CONTEXT-6 降级为应急预案）。

**关键勘误（RESEARCH §1.2，推翻任务书预判）**：dt `denoiseprofile`（9.0）不是 raw-domain——`default_colorspace = IOP_CS_RGB`（denoiseprofile.c:837-843），位于 demosaic(8.0) 之后、colorin(28.0) 之前的 post-demosaic 线性 RGB。Lightamer 管线入口 = CIRAW 已显影 linear Rec2020，与 dt「demosaic 后相机 RGB」同层，**无 Bayer 域障碍**（与 04-05 cacorrect 教训对照，本阶段无同类风险）。

</domain>

<decisions>
## Implementation Decisions

> 全部采纳 05-RESEARCH 推荐。授权依据：既定授权模式——推荐可逆且 RESEARCH 已逐项论证；本节逐条记录裁决 + 理由 + 可逆性。

### D-05-CONTEXT-1: rgbcurve(42.0)/rgblevels(43.0) 划出 Phase 5
- **裁决**：IOP-COLOR-09 的交付本体 = colorcontrast（56.0，Lab a/b 斜率+偏移单 kernel）；rgbcurve/rgblevels（「color correction curves」半边）**划出 Phase 5**，移 Phase 6+ 评估或作后续 stretch。
- **理由**：① 需求文字「color contrast / color correction curves」以 color contrast 为名，colorcontrast 是语义本体；② rgbcurve/rgblevels 与已交付 tonecurve(48)/levels(49) 同构（RGB 通道版，CurveTools 全复用），是独立可后补的机械增量（~2 天量级），不构成 Phase 5 签核阻塞；③ Phase 5 已含全项目第二难移植（denoiseprofile）+ TilingPlan 四消费者承重，不叠加非必要体量。
- **记账**：`.planning/ROADMAP.md` 需求映射注记（Phase 5 备注 = IOP-COLOR-09 以 colorcontrast 交付，rgbcurve/rgblevels 后补路径注记）；05-08 签核时落 VALIDATION 注记（类比 04 对 IOP-DETAIL-01「高斯/拉普拉斯变体」的口径）。
- **Reversibility**: reversible — 未来以独立小 plan 补齐即可，槽位 42.0/43.0 在 V50Order 现表。

### D-05-CONTEXT-2: noiseprofiles.json 内置全量 + LICENSE 注记
- **裁决**：dt `data/noiseprofiles.json`（1.79MB / 19 makers / 433 models / per-ISO a[3]+b[3]）**构建期规范化转换后内置 bundle**，EXIF maker/model/ISO（RAW-06 已读）线性插值 + generic 回落；分发前对数据文件单独做 LICENSE 注记（GPL 项目内社区贡献数据的再分发合规核对）。
- **理由**：① 体积一个量级小于 Lensfun 曾担心的数字（4.2MB 首跑下载 vs 1.79MB 内置），无网络依赖、无版本时效问题（传感器噪声特性不随镜头库更新）；② 与 Phase 1 spike「RAW 9 不减少 denoiseprofile 移植需求」结论闭环——剖面来源不依赖 CIRAW；③「generic 内置 + 用户指 dt 路径」降级方案保留为许可证阻塞时的 fallback（不阻塞工程，RESEARCH Risk#7）。
- **任务落位**：转换脚本 + 加载器 = 05-01；LICENSE 合规核对 + 注记写进 05-08 分发相关任务（签核轮文档收口）；**TODO 登记待用户知悉项**（许可证核对未完成前不对外分发 release）。
- **Reversibility**: reversible — 数据文件可替换/降级 generic，加载器接口不变。

### D-05-CONTEXT-3: denoiseprofile VARIANCE 模式 v1 划出
- **裁决**：v1 交付 WAVELETS + NLMEANS 两手动模式 + **AUTO 档 = 剖面 infer 参数族直译**（`infer_radius/scattering/shadows/bias_from_profile`，denoiseprofile.c:2622-2650 已有解析式）；VARIANCE（process_variance 局部方差统计自动定 strength）**划出 v1**。params 结构保留 mode enum 位（sidecar 兼容），UI 对 VARIANCE 项禁用 + 注记。
- **理由**：VARIANCE 是「无剖面时的自动估计」路径，与剖面体系正交；AUTO-infer 直译成本低且覆盖主工作流（有剖面用户）；VARIANCE 的局部方差统计质量在 dt 中本身标注为次优，不值得挤占本阶段预算。
- **Reversibility**: reversible — enum 位已留，未来独立补。

### D-05-CONTEXT-4: monochrome bilateral 腿 = dt 3D grid 移植
- **裁决**：采纳 RESEARCH §5.3 方案 (a)——移植 dt 3D bilateral grid（`src/common/bilateral.c` splat/blur/slice + `bilateral.cl` grid kernel，~300 行 C + 3 kernel），monochrome 的 filter 贡献平滑消费之（sigma_r=250、sigma_s=20/scale、detail=−1）。
- **理由**：① 一次投入换三处收益——monochrome + 未来 bilat/shadhi 的 bilateral 腿全部获得 dt 同源 parity（03-03 shadhi bilateral 腿挂账正是等待此件）；② grid splat 的原子散射与 HistogramReduce 同模式，工程风险已知；③ 方案 (b) EIGF 替代会永久放弃 monochrome 的 dt-cli 平场外一致域，golden 全合成不可交叉验证。
- **任务落位**：grid 共享件 + float64 参考建在 05-01（shared），05-05 接线消费。
- **Reversibility**: costly — grid 是共享件，但接口按 dt 语义锁死后替换成本高；故 05-01 即做小图 float64 交叉验证钉住正确性。

### D-05-CONTEXT-5: channelmixerrgb color-checker 自动剖面划出 v1
- **裁决**：`_extract_color_checker`/24 色块单应/delta-E 求解子树（channelmixerrgb.c:2114-2230 run_profile 分支 + `src/common/colorchecker.h`）**划出 v1**（建议 v2/Phase 12 预设生态再议）；AI WB 检测（`#ifdef AI_ACTIVATED`，dt 默认不编译）不移植。**params 位保留**（illuminant enum 含检测项时 UI 禁用 + 注记）。
- **理由**：色卡自动建 profile 是「拍色卡工作流」，与 v1 主线（手动校准）正交；划出后 channelmixerrgb 剩 ~1500 行核心，量级与 filmicrgb 相当；colorchecker.h 参考数据另有许可证问题（同 D-05-CONTEXT-2 族）。
- **Reversibility**: reversible — params 位保留，UI 禁用注记即扩展点。

### D-05-CONTEXT-6: Open#9 管线级 Lab leg 降级为 SC#4 失败应急预案（03/04 签核批分配修订）
- **裁决**：**v1 不做管线级 Lab 往返共享**。Open#9 从「Phase 5+ 主动杠杆」降级为「SC#4 拖动门实测失败的应急预案」（触发条件与门槛写进 05-06/05-08）。
- **理由**（RESEARCH §9 论证，三点）：① Lab 模块链在真实用户栈中会被任意 RGB 模块切断（tonecurve 48 与 colorcontrast 56 之间隔着 filmic/sigmoid 族 45-46），共享腿只对连续 run 生效，收益不稳；② 共享腿中间平面是 Lab 值 → 每模块缓存平面的域随邻居组合变化，PipeCacheKey 需绑域一致谓词，复杂度/风险 > 恒定 2 趟/模块的收益；③ 04-07 实测全链 33.42ms 的成本分散在 ~40 趟小 kernel，**dispatch 批合并 + Release/PSO 预热**是更大的杠杆（PERF-5 主杠杆改为这两项 + denoise 预览降载三件套）。
- **对 03/04 签核批分配的修订**：03-06 PERF-5 杠杆分配表原列「Lab 往返共享 Phase 5」、04-07 移交清单含「Lab 往返共享」——本裁决修订这两处指向：Phase 5 交付的是「批合并 bounded 版本核查 + 预览降载」，Lab leg 转应急预案。TODO Phase 3 遗留节 Open#9 行已注记（同批更新）。
- **应急预案启用条件**：05-08 SC#4 拖动门（color 全启用 + denoise 单件启用两条链 PREVIEW 拖动 60fps）实测失败，且批合并/降载杠杆兑现后仍失败 → 启用 Open#9 应急 plan（03-03 LabRoundTrip 现成共享件为起点）。
- **Reversibility**: reversible — 应急预案本身就是回退路径。

### D-05-CONTEXT-7: bilateral 5D grid 预算在 05-08 plan 期定
- **裁决**：5D grid 的 grid_bytes 公式、内存上界与超预算回落策略（TilingPlan 对应物 vs 参数软上限 UI）**留 05-08 执行期定稿**，plan 内已留专门 Task（T2）承载该决策 + 05-08-DECISIONS 落账。
- **理由**：`_compute_sigmas` 的 scale 折算实现（bilateral.cc:320，RESEARCH 标 Confidence Med）需逐行核过才能写公式；dt 的 maxbuf 机制与我们 TilingPlan 的对应关系也依赖该实现细节。提前拍板会拍错。
- **Reversibility**: reversible — 决策局部于 bilateral 一个模块。

### D-05-CONTEXT-8: vibrance 独立模块交付
- **裁决**：IOP-COLOR-03 = **独立 vibrance 模块**（58.0，Lab 域单 kernel，4B params）；不由 colorbalancergb 的 vibrance 滑块代偿。
- **理由**：dt 虽标 DEPRECATED 指向 colorbalancergb，但两者公式不同族（vibrance 是 Lab 域旧版 `out = {L·(1−0.25·a·sw), a·(1+a·sw), b·(1+a·sw)}`，colorbalancergb 的是 Ych 域 `vib·(1−chroma^|vib|)`）；独立交付成本 ≈0（4B params 单 kernel），且保住 ROADMAP 需求映射的 1:1 对应。模块头注记录 dt 弃用背景与推荐去向。
- **Reversibility**: reversible — 单模块可弃用不破坏链。

### 交互与面板（继承 Phase 3/4 定案，不重开）
- 全部面板走 D-T6 `IOPPanelProvider` + `LightamerSlider` 三件套映射 + zh/en String Catalog + L010 identifier；交互路由全走 D-H1（拖动实时 → 松手恰 1 history commit）；D-C3 拖动梯子（拖动 tick 低档 PREVIEW → 松手 commit 后当前档重渲）是 denoise 拖动门的承载件。
- colorbalancergb 4-way hue 圆盘 / colorzones 三 tab 曲线 / monochrome Lab 色轮的 Canvas 交互 = ToneEqualPanelView / CurveEditorView 已验证模式复用。
- **GUI 布局红线沿用 04-06 定案**：新增面板不撑宽 Inspector（280pt 约束），视口 ≥50% 占比不回退。

### golden 与 ROI 红线（全 plan 写死，执行期不得放宽）
- **防空转**：所有 golden/parity 测试必须真实比较循环 + `compared > 0` 断言（04-02 恒真空转教训；L017 合成参考主轨 + dt 三证据：DB op_params hex 采纳 + `--d params` ok + 均匀平场 PFM probe）。
- **ROI 红线**：每模块 `modifyROIIn/Out` 注释钉坐标系前提（dscIn = 本 run 平面像素，已含 entry 缩放）；**dscIn 禁止再 ×scale**（L021）；denoise 半径补偿只用「roi.scale ÷ 入口 iscale」标量（dt `fmin(roi.scale,2)/fmax(piece.iscale,1)` 同构）。11 个模块 ROI 全恒等，空间支持全靠 tileHalo/tileWorkingSet 声明。
- **denoise golden 策略**（RESEARCH §7）：clean fixture + 种子化 Poisson-Gaussian 加噪（按真实剖面档）→ Lightamer denoise vs float64 参考实现双方同跑比对；剖面错配（低 ISO 剖面去高 ISO 噪声）断言欠去噪方向 = SC#2 正式验证。
- **容差档**：点态 RGB/Lab <1e-5 rel；含 pow/cbrt 链 Lab 通道 <1e-4 + ΔE76 p99<1.0；denoise 族 <1e-3 rel + 恒等/极限门逐字节；LUT 查表走 ParityGate 双闸。

</decisions>

<open_question_9_revision>
## Open#9 处置变更——对 03/04 签核批分配的修订说明（D-05-CONTEXT-6 详版）

**变更内容**：03-06-SUMMARY PERF-5 杠杆分配「管线级 Lab 往返共享（Open#9，Phase 5+）」与 04-07 移交清单「Lab 往返共享」两条，修订为「Phase 5 交付批合并核查 + 预览降载；Open#9 降级为 SC#4 失败应急预案」。

**修订理由**：
1. **收益前提不成立**：共享 Lab leg 只在「连续 Lab 模块 run」间生效。真实用户栈中 Lab 域模块（nlmeans 29 需已校准色、colorzones 60、colorcontrast 56、vibrance 58、monochrome 64）被 scene-referred RGB 模块（filmic 45/sigmoid 46/agx 47/colorbalancergb 41.5）天然切割——全 Lab 链是不现实的工作流假设。
2. **缓存域一致性复杂度**：共享腿的中间平面携带 Lab 值，PipeCacheKey 必须把「平面域」纳入键谓词，否则 RGB 模块读到 Lab 平面静默出错；这一致性谓词的实现与验证成本超过它省下的 2 趟/模块（~4-6ms）。
3. **杠杆排序实测支持**：04-07 实测 Release 全链 33.42ms、~40 趟小 kernel 分散成本——dispatch 批合并（encoder/commit 开销摊薄）+ PSO 预热 + denoise 预览降载的合计预期收益 > Lab leg 理论上限，且不引入缓存语义风险。

**应急预案**：05-08 SC#4 拖动门失败且上述杠杆兑现后仍失败时，Open#9 作为应急 plan 启用（LabRoundTrip/LabKernels 现成，03-03 已交付）。TODO Phase 3 遗留节 PERF-5 行已同批注记。
</open_question_9_revision>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

- `.planning/phases/05-color-denoise-iops/05-RESEARCH.md`（正本：§1 模块清单/槽位、§2 剖面机制、§3 NLMeans/tiling、§4-5 逐模块数学、§6 ROI 红线、§7 golden 表、§8 GUI 清单、§9 perf/plan 拆分）
- `.planning/ROADMAP.md` §Phase 5（SC#1-4 原文 + IOP-COLOR-08→Phase 12 注记）；`.planning/REQUIREMENTS.md` IOP-COLOR/DENOISE 条目 + 映射表
- `/Volumes/UNITEK/Documents/Development/darktable/src/iop/{colorbalancergb,channelmixerrgb,channelmixer,colorzones,monochrome,vibrance,velvia,colorcontrast,denoiseprofile,nlmeans,bilateral}.c(cc)` + `data/kernels/{nlmeans,denoiseprofile,bilateral,channelmixer,extended,basic}.cl` + `src/common/{noiseprofiles.c,bilateral.c,illuminants.h}` + `data/noiseprofiles.json`
- `LESSONS.md`（L006/L008/L009/L013/L014/L015/L017/L018/L020/L021）
- `AGENTS.md`（Conventions + Phase 执行模型 + Phase 2 架构增量）
- `.planning/phases/04-geometry-lens-detail-iops/04-VERIFICATION.md`（Phase 5 移交清单）；`04-VALIDATION.md`（VALIDATION 体例正本）
- `.work/gui-acceptance/PLAYBOOK.md`（GUI 验收操作细则 §0-§6）
- `TODO.md`（Phase 3 遗留：L021 审计挂账 + Open#9 注记）

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets（现码核过）
- `LightamerIOP/Sources/FilmicRGB/YrgGamut.swift` — CAT16/LMS2006/Yrg/Ych 常量与 clip-chroma 族 = colorbalancergb 整条色空间链复用面
- `LightamerIOP/Sources/Common/`：LabRoundTrip/LabKernels（nlmeans Lab 域往返）、HistogramReduce（两趟原子归约 → denoiseprofile sum_y2 同模式）、GaussianBlur（kernel 工程纪律参照：L018 buffer 双平面）
- `LightamerCore/Sources/Pipe/`：IOPModule tileHalo/tileWorkingSetBytesPerPixel seam（:124-130）+ 默认恒等 ROI（:138-143）；TilingPlan + PixelPipe.executeTiledNegotiated（:334-344）；IOPiece（iscale 协议增量落点）
- `LightamerCore/Sources/Foundation/V50Order.swift` — 11 个槽位全数在表（28.5 共槽 tie-break 已由 02-05 effectiveInstances 机制化）
- `LightamerIOP/Sources/ToneEqual/CorrectionLUT.swift` + 03-03 CurveTools — colorzones 三曲线 LUT / denoiseprofile force 曲线模式
- `Tests/LightamerTests/ParityGate.swift`（LUT 双闸）、`ROINegotiationTests.swift`（SC#4 harness）、`PanelWiringTests.swift`、`MemoryBudgetTests.swift`、`PreviewChainPerfTests.swift`
- `input/golden/fixtures/gen_fixtures.py`（L015 hex 配方正本 + 合成参考生成器；Phase 5 增加噪器/hue sweep/delta 脉冲）

### Established Patterns
- `.swift + .metal` 文件对 + Registry 注册/prewarm/seed（seed 默认 disabled——colorbalancergb 等默认参数不恒等模块照 highpass/soften D11 处置）
- golden 双轨：L017 合成 float64 参考（主轨）+ dt 三证据（采纳/参数日志/平场 probe）；manifest 逐模块落账
- 每任务独立提交 + 全 suite 绿闸门 + omp 执行/ZCode subagent 验收两级模型（AGENTS.md Phase 执行模型）

### Integration Points
- NoiseProfileStore（05-01）→ denoiseprofile profile 行（05-07）
- nlmeans kernel 群（05-06）→ denoiseprofile NLMeans 腿（05-07，VST 前后包夹）
- BilateralGrid3D（05-01）→ monochrome filter 平滑（05-05）
- IOPiece.iscale（05-01）→ nlmeans/denoiseprofile/bilateral 半径补偿（05-06/07/08）
- 预览降载三件套（05-06）→ SC#4 拖动门（05-08 签核）

</code_context>

<specifics>
## Specific Ideas

- 执行顺序刚性：05-01 基建全绿后模块 plan 才动工（剖面/加噪器/iscale/tile 回归是所有 denoise parity 的前置）；05-06 先于 05-07（kernel 群共享）。
- denoiseprofile 参考实现**先于 kernel 写**（Python float64 逐式复刻），kernel 与参考同步推进（filmicrgb F1 三方门模式）——四套机制（VST/eaw 波列/Bayesshrink/NLMeans）叠在一个模块，参考先行是唯一可控路径。
- 波列 band 循环原地累加直接踩 L018（read_write RMW 不可靠）——照 dt CPU 原形用 `device float4*` buffer 平面 + band 间双缓冲，禁 image2d read_write。
- nlmeans horiz/vert 的 threadgroup 滑窗：MSL `threadgroup` 内存 + workgroup 尺寸用 dispatch 参数化并做尺寸扫描测试（dt 由 `dt_opencl_local_buffer_opt` 探测，Metal 上显式定）。
- 28.5 共槽回归：sidecar 未来导入同槽多实例历史的 tie-break（effectiveInstances opName tertiary）补一例回归测试（05-03）。

</specifics>

<deferred>
## Deferred Ideas

- **rgbcurve/rgblevels** — D-05-CONTEXT-1，Phase 6+ / stretch（CurveTools 全复用的机械增量）
- **hotpixels / dark frame subtraction** — raw/Bayer 域不可移植（hotpixels.c:94 IOP_CS_RAW + CIRAW 无 despeckle 键，Spike A 实证）；05-08 正式决议文档化；cacorrect 复议结论 = **维持 defer**（04-05 D-04-05-T0-0 同一 Bayer 域论证成立；**与 Phase 6 无关**——Phase 6 是蒙版/图层，cacorrect 是 RAW 域问题，不随 Phase 6 接收，重启条件 = v2 自研 RAW 解码路径论证）
- **denoiseprofile VARIANCE 模式** — D-05-CONTEXT-3，v1 后补（enum 位保留）
- **channelmixerrgb color-checker 自动剖面** — D-05-CONTEXT-5，v2/Phase 12 预设生态再议
- **mask_display 棋盘预览（colorbalancergb）** — Phase 6 蒙版域
- **管线级 Lab leg（Open#9）** — D-05-CONTEXT-6 应急预案
- **AI WB 检测（channelmixerrgb `#ifdef AI_ACTIVATED`）** — dt 默认不编译，不移植

</deferred>

---

*Phase: 5-Color & Denoise iops*
*Context gathered: 2026-09-21（planner 裁决定稿；全部采纳 RESEARCH 推荐并注明理由——既定授权模式）*
