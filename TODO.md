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

## Phase 2: Pixelpipe Core — 执行中

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
