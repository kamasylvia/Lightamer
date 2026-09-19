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

## Phase 3: Tone & Filmic iops — 执行中（2/6 plans）

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

## pending-manual（累计，解锁后重跑）

- [ ] XCUITest 三栏断言（L011 授权；Phase 1 起遗留）：`xcodebuild test -only-testing:LightamerUITests`
- [ ] ColorChecker ARW 实拍补采（02-04 遗留，采集路径 `.work/02-04/colorchecker-acquisition.md`）
- [ ] 跨屏 profile 跟随实测（02-04 遗留，单显示器环境 skip-with-reason）
- [ ] 屏显色彩目检（SC#1 非 headless 部分，Phase 13 COLOR-03 前置可复验）
- [ ] `GoldenColorTests.testCrossConsistencyLinearDomain` 间歇性失败排查（02-04 harness 遗留 flake，03-01 期间复现：全 suite/类内运行偶发 diverge 1.0，单测隔离必现通过；03-01 排除本类后仍复现 → 与 03-01 无关；疑似 CI baseline 腿跨渲染时序，L014 同族）

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
