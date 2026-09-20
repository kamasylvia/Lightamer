# TODO — Lightamer

> 镜像 `.planning/ROADMAP.md`（13 phases, 123 v1 reqs）+ 当前执行状态。
> 阶段进度以 `.planning/STATE.md` 为准。

---

## ✅ 环境已就绪（2026-09-16）

- [x] **Xcode 27.0 正式版**（27A266a）+ macOS 27.0 SDK + license 已接受
- [x] **Tuist 4.208.0**（brew install）
- [x] Swift 6.4（target `arm64-apple-macosx27.0.0`）

---

## 项目初始化（已完成 ✓）

- [x] GSD 项目初始化（PROJECT.md / config.json / 5 份研究 / REQUIREMENTS / ROADMAP 13 phases / STATE）
- [x] GitHub 仓库 + Azure DevOps 镜像；分支 master→main；远程 origin = Azure
- [x] AGENTS.md / TODO.md / LESSONS.md 三件套建立
- [x] 关键决策锁定：macOS 27 floor、linear Rec2020 float32 RGBA、v50_order、Metal-first/CIRAW-as-decoder、sidecar 自有格式、多 target + Tuist 解耦

## Phase 1: Foundation, App Skeleton & Capability Spikes — 执行完成（6/6 plans，2026-09-16）

**状态**：6 plans 已 executed + committed（0 BLOCKER）；测试骨架全绿；VALIDATION 已签核（manual-only 行 pending-manual 见该文件）。38/38 决策覆盖、11/11 需求覆盖。

**架构（多 target + Tuist，D-02/D-03 修订）**：
- `LightamerCore`（framework）— Decode/Metal/Pipe/Layers/Foundation
- `LightamerIOP`（framework，依赖 Core）— iop 模块集（Phase 1 仅 Passthrough）
- `Lightamer`（app，依赖 Core+IOP）— UI/Session/Export/Yiyin/AI
- `LightamerTests` + `LightamerUITests`

### Wave 1（顺序，构建端到端 vertebra "打开 RAW → 显示"）— 全部完成 ✓
- [x] **Plan 01** — Tuist Project.swift + app shell（三栏 NavigationSplitView、强制深色、空状态、toolbar、菜单栏）+ WorkingSpace/AppError（Core/Foundation, public）+ SessionState/EditorState/ExportState/InspectorState 隔离（D-03b）（2026-09-16 完成，见 `01-01-SUMMARY.md`）
- [x] **Plan 02** — RAWDecoder（Core/Decode, public）CIRAWFilter 封装 + RAW 9 opt-in+降级 + 元数据三类 + 统一 RAW/非RAW 入口 + async 可取消解码（2026-09-16 完成：actor + RAW9 探测回退 + D-23 三类元数据 + signpost；冒烟 JPEG/HEIC/TIFF/取消/损坏文件 typed error 全过；RAW 实机样本留给 Plan 06，见 `01-02-SUMMARY.md`）
- [x] **Plan 03** — MetalContext（Core/Metal, public）+ CIContextPool + 两层 dispatch + 懒加载 PSO cache + function-constants + EditorMTKView（app/UI）render-pipeline blit — **tracer 完成**（2026-09-16：全链无头冒烟 13 项 PASS，含 pass_through bit-exact、PSO cache 冷 3ms/热 0.2ms、function-constants 两个特化、decode→CIContextPool→blit 逐字节往返；⚠ 本机 `CIContext.render-to-MTLTexture` 全格式静默写空，改 bitmap+replace 方案，Phase 2 复测；MTKView 屏显待人工目检，见 `01-03-SUMMARY.md`）
- [x] **Plan 04** — IOPModule 协议（Core/Pipe, public）+ V50Order（Core/Foundation, port iop_order.c:298-415）+ **Layer 骨架（Core/Layers, D-03a）** + PassthroughModule（IOP）+ PixelPipe 骨架（layer-aware）（2026-09-16 完成：iop 契约 + 93 条 V50Order + Layer 骨架 + PassthroughModule 全 conformance + 内部 PixelPipe（持 LayerStack）+ `RenderPipeline` public 桥接入 EditorState→EditorMTKView；无头冒烟 13 项 PASS（含 process 缓冲 bit-exact、decode→PixelPipe→texture）；absorb macOS 27 SDK blit/completed 签名；MTKView 屏显待人工目检（同 Plan 03 遗留类），见 `01-04-SUMMARY.md`）

### Wave 2（验证 + 包装）
- [x] **Plan 05** — Spike A（CIRAW 9 能力边界）+ Spike B（100MP 性能）（2026-09-16 完成：真实相机样本 13 份 CC0（raw.pixls.us）实测；Spike A = RAW 9 GM 仅 69 机型（GFX100S/Z8/X100VI 不在列）、v9 no-op NR keys 双重证实、IQ4 150MP CIRAW 无法解码、ProRAW skyMatte 实测、demosaic 菜单建议不列为 v1 硬需求（用户 phase verification 定夺）；Spike B = 100MP 解码 Bayer 833ms/uncompressed RAF 848ms 达标、lossless-c GFX RAF 20.9s 超标 10×（RAF 无损解压器病态）、float32 1.55GB plane 峰值 2.0-2.8GB 达标、cached 帧 15.6ms≈64fps 达标、D-20 维持（Phase 2 tiling 硬需求证据落账）、render-to-texture 首写空复现+clearCaches 新要求；报告 `spike-a-ciraw9-boundary.md` / `spike-b-100mp-perf.md` + golden samples 入 `.planning/spikes/`；执行形式改为无头 harness（无独立 spike 分支，见 SUMMARY 记录），见 `01-05-SUMMARY.md`）
- [x] **Plan 06** — 测试骨架（Tests+UITests）+ 模块 API.md（D-03c）+ os.signpost 性能基线（2026-09-16 完成：LightamerTests 全绿 36 执行/1 跳过（CR3 样本无 GPS）/0 失败——真实相机 RAW 样本跑通 RAW-01/02/04/05/06 + FOUND-06/03 + D-03a；顺带修出两个真 bug：CR3 ISO 需走 EXIF 2.3 ISOSpeed 键（93c4eb6）、PSO 探针未 endEncoding 触发 Metal fatal assertion；三份 API.md 落账；`01-PERF-BASELINE.md` 汇总 Spike B + 真实 app 管线双腿测量（cached 显示 4-6ms、100MP 首渲 1.7s 待 Phase 2 cache、lossless GFX RAF 20.9s 唯一 decode 超标项、会话内存需 clearCaches）；⚠ 环境遗留：本机执行期间屏幕锁定 → XCUITest（automation-mode 超时）+ Instruments signpost 目检 + 屏显目检三项目前 pending-manual，测试代码已就绪且 a11y label 与 String Catalog 逐字核对，解锁后重跑 `xcodebuild test -only-testing:LightamerUITests` 即可，见 `01-06-SUMMARY.md`）

**Phase 1 执行完毕**（6/6 plans 完成，Wave 1+2 全绿；遗留 pending-manual 清单见 `01-VALIDATION.md` 与 `01-06-SUMMARY.md`）

**执行命令**：`$gsd-execute-phase 1`

## Phase 2: Pixelpipe Core — 执行完成（6/6 plans，2026-09-19）

**状态**：6 plans 已 executed + committed（1 次 checkpoint 确认 + 1 个 pre-existing 真缺陷修复）；单测 133 全绿（3 skip 合规）；VALIDATION 已签核（`nyquist_compliant: true` / `wave_0_complete: true` / SC#1..5 全数有证据）；UITests 沿用 L011 pending-manual 口径。

- [x] **Plan 02-01**（tracer）完成（2026-09-19，含一次 checkpoint→修复回路）：
  - Task 01 单渲染路径统一（0c54a68）；Task 02 CIContext warm-up spike（decision=**bitmap**：直渲在本机为 0.0ms 静默 no-op，连默认 context 也空写，warm-up 无效——Phase 1"首渲写空第二次正常"理论修正，报告 `.work/02-01/spike-render-leg.md`）；Task 03 CIContextPool bitmap 决议落账（a97ea65）；Task 04 StableHash FNV-1a 64 public + 7 向量测试（376ddaa）
  - Task 05 UAT 曾 CHECKPOINT：黑屏复现 → **真根因 = SwiftUI WindowGroup 每 odoc Apple Event 开新窗口**（10 窗/10 MTKView，新窗 decode 期建、盖住真显示窗），非渲染路径竞争。修复 = 单 `Window` scene（ac84596，Phase 9 多窗口再回归）→ 9/9 UAT 步全显示（含压力循环）
  - Task 06 D-X2 探针退役（88afa0c）：drawable 回读/drawProbe/身份探针全删，`framebufferOnly` 等诊断配置还原默认；paused 模式（D-13）保留无偏离
  - 收尾：单测 43/43 绿（1 跳过）；UITest 未跑（screen 环境同 Phase 1 pending-manual 口径，三栏断言代码就绪）；SUMMARY 见 `02-01-SUMMARY.md`；根因教训入 LESSONS L012
- [x] **Plan 02-02**（PipeCache + 递归快路径）完成（2026-09-19：StableHash FNV 原子 + PipeCache 3GB LRU actor + PipeCacheKey hash 链 + PixelPipe processRec + IOPModule Buffer→Texture 迁移 + TestGain dev-only 模块；PipeCacheTests 9/9；教训入 LESSONS L013，见 `02-02-SUMMARY.md`）
- [x] **Plan 02-03**（多分辨率管线 + PipeCoordinator）完成（2026-09-19：PreviewBucket D-C3 梯子 + renderToTexture(longEdge:) + PipeResolution 生命周期 + PipeCoordinator 单渲染路径；单测 63 全绿零回归；D-C3 resize app 内实证 + 60MP 冒烟内存 2.07GB<3GB，见 `02-03-SUMMARY.md`）
- [x] **Plan 02-04**（终端三件套 + ModuleRegistry + golden 双判据 harness）完成（2026-09-19）：
  - colorin 恒等（28.0，COLOR-04 inputProfile 预留 + displayed-domain 架构注记）/ colorout 双路径（70.0，Rec2020→P3/sRGB 常量矩阵快路径 + ColorSync 精确腿 + D-COL3 参数位）/ gamma（78.0，sRGB TRC → .bgra8Unorm 管尾，D-COL4 唯一 clamp 点）+ TerminalKernels.metal（Core 首个 metallib）
  - ModuleRegistry actor（default chain + 未知 op nil 降级位）+ LightamerIOPRegistry.populate + ModuleBox instanceID 注入 init + setParams 采纳 committed hash
  - DisplayProfile（P3/sRGB 匹配表 + ICC fallback + stableID）+ D-COL2 屏幕跟随（configure(window:) + 双通知 + 幂等 guard）+ EditorMTKView display-ready blit regime + CAMetalLayer colorspace
  - Golden 双判据 harness green：①中性度 6 灰块逐块 <2/255；②交叉一致性（线性域 <0.004 + 字节域 ColorSync 基准分层断言）；缓存断言（display change → 仅 ≥colorout miss）；合成 NeutralTarget.tif committed；ColorChecker ARW 采集 pending（raw.pixls.us 不收 color target，skip-with-reason 就位，`.work/02-04/colorchecker-acquisition.md`）
  - 单测 83 全绿（3 skip 合规）；真 RAW 冒烟 7/7 + 全链 vs CI 直渲对照一致（`.work/02-04/smoke-run.md`）；修复 3 个真缺陷：gamma TRC 写成 decode 方向、ModuleBox 不采纳 committed hash（stableID fold 对缓存不可见）、JSONEncoder 键序不稳定全面切 ParamsCoding(sortedKeys)（L013 对策落地）
  - SUMMARY 见 `02-04-SUMMARY.md`
- [x] **Plan 02-05**（HistoryStack + D-H1 API + TilingPlan 脚手架）完成（2026-09-19）：
  - `ModuleInstance` 身份元组（九冻结字段 = 02-06 sidecar schema）+ `HistoryStack`/`HistoryItem`（inline snapshot、undo/redo/jump、redo 尾截断）+ `effectiveInstances()`（history.c GROUP BY MAX(num) 直译，v50 + (iopOrder,multiPriority,opName) tiebreak）
  - `HistoryHash`（FNV-1a enabled-only 链 + golden 向量 0x684AEC372467B526）+ PixelPipe `TODO(02-05)` 兑现：`decodeParamsHash(for:)` 提取为共享 D-H4 原子
  - EditorState 拥有 history/instances（D-03b）；PipeCoordinator `historyDidChange()` 替换 `paramsDidChange()`（record→box 按 UUID 原位物化，未变参数缓存平面存活）+ D-H1 三件套 `beginContinuousEdit/setLiveParams/commitContinuousEdit` + undo/redo/jumpToHistory
  - `TilingPlan` 纯几何脚手架（D-20，unwired，Phase 5 挂接注记在 PixelPipe 头部）
  - 单测 106 全绿（3 skip 合规）；`Hasher(` grep 守卫 clean；checkpoint 六锁 affirmed（70cc389）；SUMMARY 见 `02-05-SUMMARY.md`
- [x] **Plan 02-06**（Sidecar + clearCaches + RAW-03 + 签核）完成（2026-09-19）：
  - checkpoint 02-06-01：D-S1 sidecar schema 七锁 affirmed（含 **UInt64-as-String** ONE-WAY 锁），e9edd50
  - `LightamerSidecar` schema v1（02-05 冻结拼写 verbatim + `UInt64String` wrapper + drift primitive + 未知 op 降级）+ `SidecarStore` actor（2s debounce 合并 / 同目录 tmp 原子写 / 损坏→nil），3a11cb6 + 5429570
  - App 接线：load 切换 flush→restore-or-fresh（imageID 恢复不重铸 / 漂移 toast 不回写 / 未知 op 降级 toast）、history 移动→scheduleWrite、`applicationWillTerminate`→有界同步 flush、D-26 toast 面（StatusBar leading）+ String Catalog zh/en；DEBUG `-la_sidecar_probe` headless 双跑探针，5e0d699
  - **真缺陷修复（LESSONS L014）**：colorout ColorSync 腿跨队列读竞态（restore 5-dispatch 渲染稳定黑图）→ `convertTexture` 读前 fence；Core 级 SC#3 字节级 round-trip 测试固化
  - `enforceBudget(keeping:)` 纯策略执行器（锁定 4 层逐出序 + floor）+ `clearCICaches()` + load 入口/60s sweep 双触发 + >500MB toast；`MemoryBudgetTests` 7（注入小预算），c208339
  - RAW-03：32f TIFF/EXR fixtures（极值 65504.0 pinned）+ `RAW03Tests` 7 全绿；宿主决策：CGImage 路 float-faithful、fallback 不采纳（记录于 `decodeRaster`），6a72691
  - 单测 **133 全绿**（3 skip 合规）；grep 守卫：`.xmp` 零读写路径；VALIDATION 签核（SC#1..5 证据 + 需求追溯 7/7）+ 真机 round-trip `.work/02-06/roundtrip.md`；SUMMARY 见 `02-06-SUMMARY.md`

## Phase 3: Tone & Filmic iops — 执行完成（6/6 plans，2026-09-20）

- [x] **Plan 03-01**（Wave 0 基建 + exposure tracer）完成（2026-09-19）：
  - T1 darktable-cli 从 dc58cf0ba1 重建（5.5.0+1862~gdc58cf0ba1-dirty；构建修复：CLT SDK `-isystem` 与 Xcode 27 clang 的 libc++ `<cstddef>` 冲突 → 缓存 SDK 路径改指 Xcode SDK + fresh configure + 显式 libomp + 内置 Lua），XMP 钉参链路实证采纳（+1EV XMP：ramp 0.25 列 → 0.5 exact；直通 bit-exact）——预构建版丢历史缺陷消失，GUI 模板回退方案无需启用（6c7bc7e）
  - T2 `input/golden/`：gen_fixtures.py（纯 stdlib EXR writer，8 fixtures + 4 exposure 钉参 XMP cases，**XMP params = 小写 HEX ASCII 非 base64**（RESEARCH §6.3 勘误，exif.cc:3317））+ regenerate.sh 四段管线（--configdir 钉 float32/uncompressed 写出保证机器无关 hash + --apply-custom-presets 0）+ manifest（dt commit + blob hash + 输出 sha256 + dt↔Lightamer 字段映射表）；roundtrip passthrough maxdiff 0.0（预算 ≤1e-6）
  - T5 `ExposureModule`（.swift+.metal 对，v50=21.0 注册）：v7 params 镜像 + `white=exp2(−EV)`/`scale=1/(white−black)`；divergence 头注（默认 0EV 非 dt 0.7EV / deflicker 不实现位保留 / processed_maximum 不跟踪 / EXIF bias 补偿预留）
  - T3+T4 `GoldenParityTests`（轨 A：fixture×case 逐像素 <1e-5 **GREEN**；轨 B：Phase 2 双判据带 exposure 插入链 green）+ `CPUDerivationTests`（exposure 公式直译 8 向量 + 后续模块占位节）；全 suite 143 绿（3 skip 合规）
  - 两个 macOS 27 host finding（L015/L016）：dt XMP 未压缩 params 为 hex ASCII 非 base64；ImageIO float32 EXR 解码逐通道错位（绕道 = 自研 EXR reader + CGImageCreate float32 + WorkingSpace（**linear**）Rec2020 标签；⚠ `CGColorSpace.itur_2020` 是 gamma-2.4 非 linear）
  - SUMMARY 见 `03-01-SUMMARY.md`
- [x] **Plan 03-02**（WB temperature/tint + 吸管 plumbing + Inspector 面板框架）完成（2026-09-19）：
  - T1/T2 `TemperatureModule`（.swift+.metal 对，v50=3.0 注册；slot 语义 divergence 头注 = post-CIRAW 校正层）：`CIEData.swift`（dt `cie_colorimetric_tables.c` 逐值搬移）+ `WhiteBalanceMath`（SPD→CMF 积分→XYZ 与 dt 同源 <1e-4，C 参照 harness `.work/03-02/wb_reference.c`；Rec2020 原生 `gains = W/T`，W=D65 锚经同一路径 → 恒等 (1,1,1)；dt Y-hack tint 语义保留；K↔gains 二分互求 1e-4K 收敛，round-trip <1e-3K）；吸管 `gainsFromPicked` = dt temperature.c:1933-1955 逐行移植（通道比值域无关）
  - golden：temperature 钉参组 4 case（增益直设绕开 Kelvin 域差，RESEARCH §5）×5 灰 fixture parity <1e-5；**dt-cli host finding（manifest 落账）**：本环境 dt-cli 对空间变化图像的 float 导出（EXR/PFM/TIFF 全路径）空间损坏，均匀图像精确 → track-A 参考由 gen_fixtures.py `refs` 按共有语义合成（canonical fixture × gains，float64），dt 侧以 ①库 DB op_params hex 采纳实证 ②均匀平场 PFM probe（(0.6,0.5,0.4) exact 4e-8）双证据锁定；no-OMP 重建尝试（USE_OPENMP=OFF）→ dt-cli 启动 hang 不可用
  - T3/T4 D-T6 `IOPPanelProvider` + `LightamerSlider`（D-H1 三件套映射 + 双击归零）+ `InspectorState` factory 分发 + `InspectorView` 实体化 + exposure/WB 首两面板；pristine 编辑种子 = terminal trio + temperature/exposure（identity，缓存中性）；`PanelWiringTests`（拖动=恰 1 条 history、拖动风暴 newest-wins、归零还原原 paramsHash=缓存全 hit、sidecar 节流写、dispatch）
  - T5/T6 D-T4 `PipeCoordinator.pickColor`（视口点→真 aspect-fit uv→线性段重渲（缓存全 hit）→L014 fence→5×5 面积均值）+ EditorAreaView 吸管模式（十字光标+点击路由）+ `EyedropperTests`（中性采样 <1e-5、20 连点 fence 安全、采样零污染、蓝偏平场端到端中性化）；**blit shader uv 修复**：aspect-fit 除以 per-axis scale（原先中心裁切；大三角形覆盖的斜边溢出属 Phase 4 fit 路径）
  - 单测 **165 全绿**（3 skip 合规）；LightamerTests 新增 app-target 依赖（@testable 驱动 D-03b 状态层）
  - SUMMARY 见 `03-02-SUMMARY.md`；下一批 = 03-03（Lab 三模块）/ 03-04（shadhi+sigmoid）
- [x] **Plan 03-03**（Lab 域三模块：tonecurve + levels + colisa + LabRoundTrip 共享件）完成（2026-09-19）：
  - T1 `LabRoundTrip` 共享件（IOP/Sources/Common/）：BT.2020 Rec2020→XYZ（项目唯一常量集）+ Bradford D65→D50 + Lab 参考白锚定管线白（**中性 a=b=0 精确成立**，轨 B 判据）；dt 同形 f（cbrt/cube，κ/ε）负值有定义；CPU Double 往返 <1e-9（实测 2.4e-15）、GPU float32 <1e-6；**Metal 无 cbrt → 有号 powr(1/3)**；`LabMath.h` 供模块单 pass 内联（无管线级 Lab 共享，RESEARCH Open#9 → Phase 5+）（3932653）
  - T2 `ColisaModule`（v50=47.0）：ctable/ltable（colisa.c:190-235 逐行；**plan 勘误：gamma = 1/(1+b)/(1−b) 非 10^(−b)**）+ extrapolation 拟合；5 case × 6 fixture parity；**dt-cli Lab 链新 finding**：XMP blob 采纳实证（DB op_params hex + params ok）但导出 piece 态非确定（饱和度=-1 时灰变黑，数学上不可能）→ probe 路线不可用走合成；**顺带修复 libcolisa/libtonecurve/liblevels .so 陈旧**（OpenCL 改名前的旧符号致 dlopen 失败）（a60d43d）
  - T3 `ToneCurveModule`（v50=48.0）：curve_tools.c 三插值逐行（monotone hermite/catmull-rom/natural cubic + d3_np_fs）+ 0x10000 LUT×3 + XYZ/RGB 联动表重推导（RGB 走工作域 Rec2020）+ 5 组外推拟合 + preserve_colors norm 家族；`CurveEditorView`（拖节点 + 实时 CPU LUT 曲线显示 = 显示即管线数学）+ ToneCurvePanelView；4 case × 5 fixture（含 stair_1d 10001 点 LUT 靶）（b745d72）
  - T4/T5 `LevelsModule`（v50=49.0）：compute_lut 逐行（manual 0/0.5/1 恒等）+ automatic = `HistogramReduce`（Common/，两趟 256-bin 线程组原子归约，Lab L 内联；MPS 备选不接线；signpost 计时）→ percentile 三点（levels.c:212-250 逐行）→ LUT 重写 → apply；automatic 参考自洽（GPU 直方图→LUT→apply vs float64 同 levels，解析 ±1 bin + <1e-4 + ΔE p99<1.0）（15ea14d / 0c278e8）
  - T6 三面板（Colisa/Levels/ToneCurve）+ `InspectorState.registerDefaultProviders` + pristine 种子 +39 条本地化；`PanelWiringTests` +4（三面板拖动=恰 1 条 commit、colisa 归零还原 hash、levels 模式切换离散一条）
  - **关键工程发现 → ParityGate 双闸**：LUT nearest 截断查表在 f32-vs-f64 下有索引翻转悬崖（中性 a_in=0.5 恰在截断边界 → 21% 违规）；Lightamer 改**四舍五入索引**（≤1 LSB 语义差）+ 双闸（≥99% <1e-5 rel + 2.5e-5 abs floor / 1e-4 包络 100%）——ParityGate.swift 是后续 LUT 模块（shadhi/rgblevels…）的标准闸
  - 单测 **199 全绿**（3 skip 合规）；SUMMARY 见 `03-03-SUMMARY.md`；下一批 = 03-04（shadhi+sigmoid，复用 LabRoundTrip）
- [x] **Plan 03-04**（shadhi gaussian 腿 + sigmoid D-T2 基线 + Common/GaussianBlur 共享件）完成（2026-09-19）：
  - T1 `GaussianBlur`（Common/）：dt gaussian.c Deriche IIR（ZERO order，Double 推导 Float 发布）+ `device float4*` **双平面**三 pass（col→row→store；L018：read_write 纹理同线程 RMW 不回报写入值 + 行 pass 原位读写 DC 坍缩为 cp·(1+cn) + `.private` 分配毒化后续 CI 渲染，全按 dt `__global float4*` 原形规避）；GPU-vs-float64 σ 分档门（≤5:1e-6 / σ20:2e-5，纯 float32 舍入）
  - T2 `ShadhiModule`（v50=50.0，.Lab）：Lab 域 prep→blur→mix；overlay 数学 shadhi.c:399-490 逐式直译（含 :462/:486 quirk）；bilateral 腿 → Phase 5（checkpoint 落账），golden 钉 `shadhi_algo=gaussian`；4 case × 6 fixture parity <1e-4 + ΔE p99<1.0 + 恒等逐像素不变
  - T3/T4 `SigmoidModule`（v50=45.3）+ `SigmoidDerivation`：commit_params 四标量 Double 推导 + primaries 矩阵链（默认路径恒等）；**中间探针抓出 invert3 单格余因子笔误**（G 行 [0,0.9735,−1.0001] → 中性输入 G 取反，即"符号翻转"真身）；5 case × 6 fixture <1e-5 + GPU 曲线约束（f(0)/f(grey)/f(∞)）+ 双路径中性
  - T5 两面板（Sigmoid 四滑块+Picker+dt 预设 / Shadhi +algo Picker bilateral 禁用+Phase 5 注记）+ `PanelWiringTests` +2 + Registry 注册；golden cases shadhi 4 + sigmoid 5 + manifest/regenerate 落账
  - 附带：GoldenColor D-COL1 链范围收窄为终端三件套（shadhi 默认阴影 +50 按设计生效，iop 级中性由独立门把守）；`GaussianBlur.coeffs` Double 推导（expf ulp 在大 σ 放大破 parity 门）
  - 单测 **220 全绿**（3 skip 合规，连续两次全量稳定）；SUMMARY 见 `03-04-SUMMARY.md`；下一批 = 03-05（toneequal）/ 03-06（filmicrgb，引用 sigmoid 基线）
- [x] **Plan 03-05**（toneequal：CorrectionLUT + EIGF/guided kernel 群 + TilingPlan FULL 首战）完成（2026-09-19）：
  - T1 `CorrectionLUT`（ToneEqual/）：9 带 → 9×8 RBF 最小二乘（**float32 逐式复刻 choleski.h**——dt 权重出自 float 运算，Double 推导在条件数下漂 ~3e-4）→ **80001 点 LUT**（plan 勘误：非 10001）clamp [0.25,4]；UI 曲线与 kernel LUT 同源（uiCurveSamples/channelGainsEV）
  - T2 `toneeq_luma_estimate`：**7 估计器**（plan 勘误「9」= bands 数）+ linear_contrast；method 走 uniform 分支（PSO LRU 预算决策落 DECISIONS）
  - T3 EIGF/guided kernel 群（bilinear/quantize/pack4/box_mean_x/y/guided_ab/blend）：**plan 勘误——EIGF 的模糊是 Gaussian 非 box**（`guided_filter.cl` 是彩色 guidedfilter 的 kernel；toneequal 真实路径 = eigf.h），复用 03-04 GaussianBlur；常量 bounds 与 dt 数据 min/max clamp 点位等价（论证落 `03-05-DECISIONS.md`）
  - T4 `toneeq_apply`（**4 通道全乘** dt quirk 保 parity）+ 三段组装（NONE 直通 / EIGF 全分辨率逐迭代 / guided ds 平面迭代）+ `PixelPipe.run` stamp `piece.dscIn`（dt piece->iwidth 同构）；v50=24.0 注册
  - T5 golden 两档（none <1e-5 双闸 / EIGF <1e-4 + ΔE76 p99<1.0）：float64 参考 + **float32 复刻 choleski**（与 Swift 权重一致 ~1e-7）；5 case × 6 fixture；v2 blob 72B 采纳实证（params v. 2 ok + DB hex）；**中间探针抓参考端 contrast 双重 exp2**（仅 ramp EIGF 档失败的定位法 = Python 逐像素复算参考链）
  - T6 TilingPlan FULL 首战：`IOPModule.tileHalo/tileWorkingSetBytesPerPixel` seam（默认 0 零破坏）+ `PixelPipe.executeTiled`（上游一次渲染 → TilingPlan 网格 → halo 外扩 readRect 整幅语义执行 → blit 裁回）；toneequal halo = **4r+65**（IIR 跑道 exp(−1.695d/σ) 推导，决策文件）；强制分块 vs 整幅 <1e-5 + 100MP FULL Δfootprint <3GB 双门绿
  - T7 `ToneEqualPanelView`（同源曲线 Canvas + 9 带滑块 + 全参数控件 + zh/en catalog）+ 面板注册 + seed 实例；**PERF-5 预验数据记录**：Debug 构建 PREVIEW 全链（10 模块）warm median 63.4ms > 16.6ms 预算——按 plan「超限先记录后优化」注记，正式门 03-06-T7（杠杆：Release/PSO 预热/dispatch 批合并）
  - 单测 **244 全绿**（3 skip 合规，连续两次全量稳定）；SUMMARY 见 `03-05-SUMMARY.md`；下一批 = 03-06（filmicrgb + agx + PERF-5 正式签收）
- [x] **Plan 03-06**（filmicrgb F0-F4 + agx 变体 + PERF-5 正式记录 + Phase 3 签核）完成（2026-09-20）：
  - T0 checkpoint：D-T1 三项范围定稿（V5 only / 高光重建划出（mask kernel + 参数位）/ norm 家族全实现）+ 5 条源码勘误，`03-06-DECISIONS.md`
  - T1-T5 `FilmicSpline`（compute_spline v1/v2/v3 全分支 + output_power + norm 界）+ `FilmicRGBKernels`（filmic_chroma_v5 直译：MAX_RGB norm→ratios（无 sanitize 勘误）→log→spline→pow + naive + 饱和度混合 + Yrg gamut 全链）+ `YrgGamut`（Bradford/CAT16/LMS2006 编译期常量积 + clip-chroma 族）；`FilmicRGBModule` v50=46.0 注册 + editing seed
  - golden：F1 三方（Metal vs CPU Double 分段门：toe/linear 1e-6、poly4 shoulder f32/FMA 档 1e-5 + 1e-4 包络）+ F2/F4 组合 parity（5 钉参 case × 5 fixture）+ F3 光谱入域/中性轴 + norm 六模式 + auto 三键（grey 吸管 /2 语义；black/white = 新 `HistogramReduce.rgbMinMax` uint 编码原子归约端到端）+ F5 mask kernel 权重 + 轨 B；参考 = float32-FMA 逐式复刻（M 网格 + math.fma 单舍入 Horner——缺一即 3-5e-5 系统差）；`saturated` 划出数值 parity（log 未定义域 ±1e-7 边界，保留 F3 合法性靶）
  - dt 侧证据：116B blob 库 DB op_params hex 逐字节 + history load + piece commit（filmic/agx CPU 腿本机导出崩溃 = sigmoid per_channel SIGSEGV 同族，③d adoption probes 落账）
  - T6 `AgXModule` + `kernel_agx` 直译（tone_mapping_params 全推导 + primaries 四矩阵复用 SigmoidProfile builder）v50=45.5 注册 + 面板；5 case × 6 fixture parity + 曲线不变式 + round-trip；hatchless 无对标注记
  - T7 PERF-5：`PreviewChainPerfTests` 2/2 进套（真实拖拽形状：稳定 imageID + exposure tick 全链失效 + PSO 启动预热）；**Release warm median 36.23ms**（预算 16.6ms 未达——RESEARCH 7-10 趟假设证伪，实测 ~40 GPU 趟；晚链单滑块 2-6ms ✓；杠杆分配：Lab 往返共享 Phase 5 / dispatch 批合并 Phase 4）`.work/03/perf-record.md`；FULL toneequal Δfootprint 289MB << 3GB ✓
  - 排障收获：Python 参考 log2 漏除 grey；Swift rational 闭合式漏 −1；f32 系数网格 + FMA 单舍入必须复刻；PSO 预热撞 function-constant validation abort；Release 测试构建三连（DEBUG 探针守卫 / ENABLE_TESTABILITY / hardened runtime 签名验证——CLI 覆盖跑）
  - 单测 **267 全绿**（3 skip 合规，连续两轮）；SUMMARY 见 `03-06-SUMMARY.md`；**Phase 3 VALIDATION 签核（nyquist_compliant: true；SC#1/2/4 ✓、SC#3 ⚠️ 晚链成立/全链注记）**

## Phase 4（Geometry, Lens & Detail iops，执行中 2026-09-20）

> 执行模型：omp 无头执行 + ZCode subagent 独立验收（AGENTS.md「Phase 执行模型」）。

- [x] **Plan 04-01**（ROI 协商协议改造）完成（2026-09-20）：omp 执行 8 commits；subagent 验收 PASS——AC 逐条实证 + 独立 282 tests 0 失败 + SC#4 四断言 8/8（真模块回归）+ D-X1 JPEG 冒烟回归确认；SUMMARY 见 `04-01-SUMMARY.md`
- [x] **Plan 04-02**（crop + flip/orientation + overlay 手柄）完成（2026-09-20）：omp 执行 5 commits；验收初判 FAIL（`testCropGoldenParity` 恒真空转——无比较循环），验收方直接修（补 3 case × 4 fixture 双循环，12 golden EXR 实比对）+ 补 manifest 04-02 节（blob/引用 sha256 表 + L017 probe 落账）后转绿；交付面：T1 CropModule 窗口三钩子（crop.c:517-592 直译）+ CropParity 8/8、T2 FlipModule 8 态 remap + FlipParity 8/8 + V50 flip<crop 顺序硬约束、T3 L017 双重 probe + 轨 A <1e-6 + 轨 B 2/2、T4 ViewportFit 三处同源 + 9 手柄/网格/暗膜 + D-H1 live-disabled 拖拽、T5 CropPanelView + catalog 20 keys + PanelWiring +3；overlay 交互 3 行 Manual-Only 表（L011 口径）；SUMMARY 见 `04-02-SUMMARY.md`
- [x] **Plan 04-03**（rotate/perspective ashift + Vision 自动检测）完成（2026-09-20）：T0 单一 ashift op（v50 15.0，`iop_order.c:319` 实测）+ 透视 (a) 参数面 + Vision 填充 + EXIF 分工；T1 Homography CPU（dt `_homography` Double 直译 + DLT + fitParams，HomographyTests 6/6）；T2 ashift_warp kernel + 模块三钩子（L020 帧约定注释钉死）+ Registry/种子/V50 双钉；T3 Vision 探针 4/4（θ<0.2°/矩形<0.5%/符号钉死/0° nil 特性）；T4 L017 合成参考（7 钉参 × 4 fixture，<1e-5/<1e-5）+ manifest 落账 + **管线修复：后向 clamp 改 `frameROI.union(roiOut)`**（grow 契约擦除根因）+ ColorIn 断言松绑；T5 AshiftPanelView + catalog 18 keys + PanelWiring +2 + ROI 回归 +1；排障沉淀：半 texel 采样约定（0.5/63 精确签名）、float 数组 packing 改 float4 行、sub-region getBytes 回零（harness 改全幅读回）；SUMMARY 见 `04-03-SUMMARY.md`
## pending-manual（累计，解锁后重跑）

- [ ] Vision 自动检测真机 RAW 抽检（04-03 遗留，素材与步骤 `.work/04-03/vision-field-notes.md`：DSC00012 水平线 / DSC09991 矩形）
- [ ] XCUITest 三栏断言（L011 授权；Phase 1 起遗留）：`xcodebuild test -only-testing:LightamerUITests`
- [ ] ColorChecker ARW 实拍补采（02-04 遗留，采集路径 `.work/02-04/colorchecker-acquisition.md`）
- [ ] 跨屏 profile 跟随实测（02-04 遗留，单显示器环境 skip-with-reason）
- [ ] 屏显色彩目检（SC#1 非 headless 部分，Phase 13 COLOR-03 前置可复验）
- [ ] `GoldenColorTests.testCrossConsistencyLinearDomain` 间歇性失败排查（02-04 harness 遗留 flake，03-01 期间复现：全 suite/类内运行偶发 diverge 1.0，单测隔离必现通过；03-01 排除本类后仍复现 → 与 03-01 无关；疑似 CI baseline 腿跨渲染时序，L014 同族）
- [ ] 滑块拖动 60fps Instruments 交互目检（PERF-5/SC#3 手动项；数据面已由 `.work/03/perf-record.md` 覆盖——晚链 2-6ms ✓，全链重渲 36ms 注记）

## Phase 3 遗留/分配（签核注记，非阻塞）

- [ ] PERF-5 全链重渲 36ms → 16.6ms：管线级 Lab 往返共享（Open#9，Phase 5+）+ 跨模块 dispatch 批合并（Phase 4+）
- [ ] filmicrgb 高光重建子树（F5 à-trous wavelet + HQ 循环）：mask kernel + 参数位已就位，重建挂 Phase 8 HDR/v1 后期
- [ ] filmic/sigmoid/agx displayed-domain 默认值校准（CIRAW 显影域 vs 场景线性假设）——产品语义任务，随 Phase 8/实机校准

## Phase 2-13（已规划，未开始）

| # | Phase | Reqs | 关键内容 |
|---|-------|------|---------|
| 2 | Pixelpipe Core, Color Mgmt & History | 8 | per-module cache、terminal trio、history stack+hash、sidecar、layer-aware pixelpipe |
| 3 | Tone & Filmic iops | 10 | exposure/WB/curve/shadhi/levels/toneq + filmicrgb（最难移植） |
| 4 | Geometry, Lens & Detail iops | 8 | crop/rotate/lens/sharpen/localcontrast |
| 5 | Color & Denoise iops | 12 | colorbalancergb/colorzones/monochrome + profiled denoise（第二难） |
| 6 | Layers & Masking System | 14 | C1 调整图层 + drawn/parametric/raster mask + blend modes + liquify/retouch（最大架构阶段，Layer 骨架已就位） |
| 7 | AI Modules（Native Vision） | 4 | 主体检测 + 频率分离磨皮（仅 Apple 原生 API） |
| 8 | HDR/Stacking & Effects iops | 10 | HDR merge/focus stack + EDR + vignette/grain/bloom/dehaze |
| 9 | Capture One Session Management | 8 | 文件夹即会话 + Capture/Crop/Output + FSEvents + 多会话 + 复制粘贴/前后对比 |
| 10 | yiyin Border/Watermark Panel | 8 | 印框/EXIF/日期/Logo/字体/品牌归一化，移植为原生 |
| 11 | Export Pipeline & Batch Queue | 8 | 6 格式 + 配方 + 后台队列 + yiyin 应用 |
| 12 | Metadata, Rating, Presets & LUT | 11 | 评级/标签/关键字/智能相册 + 原生预设 + .cube LUT |
| 13 | System Integration & Distribution | 11 | Quick Look/Spotlight/软打样/多 ICC/手势/i18n + GitHub 开源/签名公证/CI |

详细需求/成功标准见 `.planning/ROADMAP.md`，需求清单见 `.planning/REQUIREMENTS.md`。

## v2（已记录，不在当前 roadmap）

AI 追色 / AI 评分 / AI 天空分离 / AI 人像部位 / AI 通用语义分割（需自定义 Core ML 模型）/ 联机拍摄 / 地图视图 / 打印 / 跨 Session 搜索

---

*镜像自 `.planning/ROADMAP.md`。阶段进度以 `.planning/STATE.md` 为准。*
