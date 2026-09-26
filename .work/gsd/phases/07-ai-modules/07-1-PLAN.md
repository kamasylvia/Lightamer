---
phase: 7
plan: "07-1"
title: "Vision 基建 + AI-01 主体隔离：SDK 复核 + Vision benchmark 基线（首任务）+ AIMaskService（层 A/B 双后端 + fence + 后台 Task + ANE/CPU device 面）+ raster 烘焙管线接线（双线性上采样 + 羽化增件 + 同 maskID 覆盖）+ 下载 UI 三态/双后端回落 + 确定性/语义/round-trip 测试"
wave: 1
depends_on: []
autonomous: true
requirements: [AI-01, AI-06]
files_modified:
  - LightamerCore/Sources/AI/AIMaskService.swift           # 新建：handler 封装 + 后台 Task + L014 fence + device 面（Core 级可单测）
  - LightamerCore/Sources/AI/AIMaskTypes.swift             # 新建：种子/质量档/instance 选择/错误类型（Y 翻转换算收口于此）
  - LightamerCore/Sources/AI/AIAssetStatus.swift           # 新建：层 B 模型 assetStatus 三态状态机 + downloadAssets(Subprogress) + 首启预下载策略入口
  - LightamerCore/Sources/Layers/Masks/RasterMaskStore.swift      # bake 入口增件：羽化半径参数（MaskPostProcessKernels 接线）——零既有行为改动
  - LightamerCore/Sources/Metal/MaskPostProcessKernels.metal      # 如需单通道 feather kernel 适配（复用为主）
  - LightamerCore/Sources/AI/AIMaskResample.swift          # 新建：低清 mask → 解码帧分辨率双线性上采样（独立于 load 的 per-scale nearest 口径）
  - App/Sources/Lightamer/UI/AIDownloadPrompt.swift        # 新建：首启预下载提示 + 层 B 未就绪引导（07-3 MaskToolbar 消费同一状态模型）
  - Tests/LightamerTests/AIMaskDeterminismTests.swift      # 新建：pin CPU + 同输入两次推理逐字节恒等（进程内/跨进程）
  - Tests/LightamerTests/AIMaskSemanticTests.swift         # 新建：合成图 IoU ≥0.9 / 背景区 ≤0.1 / 层 B seed→非空 / excluded 方向断言 / 无主体 nil
  - Tests/LightamerTests/AIMaskGeometryTests.swift         # 新建：上采样对齐（行 0=图顶）+ 交互点 Y 翻转 + bake 羽化剖面
  - Tests/LightamerTests/RasterMaskRoundTripTests.swift    # AI mask bake→load uint16 恒等 + 覆盖重 bake hash 翻转扩展
  - .work/07/perf.md                                       # 新建：Vision benchmark 基线（只记录不设门；SC#5 门执行期定）
  - .planning/phases/07-ai-modules/07-1-SUMMARY.md
  - .planning/phases/07-ai-modules/07-1-DECISIONS.md
  - TODO.md
  - LESSONS.md                                             # 如踩坑
---

# Plan 07-1 — Vision 基建 + AI-01 主体隔离

> 背景：Phase 7 首个 plan = **AI 推理基建 + 层 A/B 主体蒙版**。AI-01 = class-agnostic 主体
> 隔离，双层形态（D-07-CONTEXT-1）：层 A `VNGenerateForegroundInstanceMaskRequest`
> （macOS 14+，OS 内置、离线、一键全自动、多 instance 可勾选）+ 层 B
> `GenerateIterativeSegmentationRequest`（macOS 27，tap-to-segment，`seedPoint/seedBox`
> + `addIncludedPoint/addExcludedPoint`，**首次使用需一次性模型下载**——`DownloadableAssetsRequest`）。
> 消费通道 = raster 烘焙（D-07-CONTEXT-3）：`AIMaskService` 产 r32Float 平面 →
> 上整形（双线性上采样 + 羽化）→ `RasterMaskStore.bake` → `MaskSpec.raster`，继承
> Phase 6 全部蒙版能力（移交清单①③落位；②层栈写入在 07-3 UI 层）。**首任务 =
> SDK 复核 + Vision benchmark**（07-RESEARCH §5 定为首任务——beta 期 API 漂移 +
> 耗时基线双保险）。本 plan 不含视口交互与面板（07-3）；服务层接口先行，App 侧
> 仅下载提示三态。

## read_first

1. `.planning/phases/07-ai-modules/07-RESEARCH.md` §1（双层 API + 烘焙管线 + 失败腿）、§5（性能/benchmark/缓存）、§6（验证策略表 AI-01 层 A/B 行 + Vision 确定性行 + 上采样行）、Risks 1/2/3/4/5/7/8、§Plan 07-1 行
2. `.planning/phases/07-ai-modules/07-CONTEXT.md` D-07-CONTEXT-1（双层共存）/3（raster 唯一通道）/5（同 maskID 覆盖）+ 继承定案节（推理输入 = 解码帧 / fence / 生成失败语义）+ 验证红线节
3. 本机 SDK：`.../MacOSX27.0.sdk/.../Vision.swiftmodule/arm64e-apple-macos.swiftinterface` `:1700-1766`（GenerateIterativeSegmentationRequest 全接口快照——**T1 复核**）、`:615-620`（perform(on:) 输入）、`:1965`（ComputeStage）
4. `LightamerCore/Sources/Sidecar/RasterMaskStore.swift:46-101`（bake 签名与 masksDirectory）+ `LightamerCore/Sources/Layers/Masks/RasterMaskRef.swift` + `MaskSpec.swift:239-299`（stableHash 派生链）
5. `LightamerIOP/Sources/Masks/MaskPostProcessKernels.metal`（单通道 blur/feather kernel 复用面）
6. `LESSONS.md` L014（跨队列 fence——解码帧纹理→CVPixelBuffer→Vision 读）/L017（golden 分流——AI 无 dt 对照的变体口径）/L018（IIR RMW——羽化若走 GaussianBlur 平面纪律）/L022（omp 零写入）
7. `.planning/phases/06-layers-masking/06-DISCUSSION-LOG.md` 终节（移交清单①③）

## 纪律（强制）

- **每任务独立提交**（Conventional Commits，只 add 相关文件）；`caffeinate -dis`；单测 `Scripts/test-direct.sh`；**RasterMaskStore/蒙版面改动后全量回归**。
- **每任务边界检查 `.work/PAUSE`**（任务收尾 commit 后、下一任务开工前——在制品已 commit、工作区干净地停、报告断点；AGENTS.md 2026-09-24 暂停机制，Phase 7 起强制）。
- **L014 fence 红线**：解码帧 `MTLTexture` → `CVPixelBuffer` → Vision 读取前，本队列既有写入必须 fence（commit 空 buffer + waitUntilCompleted，convertTexture/readPlane 同款前置）。
- **防空转**：语义门必须带**方向断言**（IoU ≥ 0.9 / 背景区 ≤ 0.1 / excludedPoint 后主体内 mask 下降），禁"存在输出即过"；确定性门 = 逐字节恒等非"均差小"。
- **测试 pin CPU**：一切进 suite 的 Vision 请求 `setComputeDevice(CPU, for:)`（`supportedComputeStageDevices` 枚举断言含 CPU 常驻）；运行时不做跨 device 恒等承诺。
- **失败腿语义**：推理失败 / nil observation / 模型未下载 → 报错 + 不落 mask（typed error），**禁止**降级全一平面（那是 load 三失败腿语义，严格区分）。
- **不新增缓存类**：推理产物以 maskPlane 级进既有缓存；推理中间态不缓存。
- **不 SIGSTOP Resilio Sync**；卷慢态先查（L009）。
- RESEARCH 未覆盖的实现细节（handler 复用形态/上采样 kernel 精确签名/下载提示 UI 形态）标注**执行期决策**入 `07-1-DECISIONS.md`，不臆造。

## Tasks

### T1 SDK 复核 + Vision benchmark 基线（首任务，RESEARCH §5 钦定）

- **action**
  1. **SDK 复核**：对本机 swiftinterface 复核 `GenerateIterativeSegmentationRequest` `:1700-1766` 快照（availability/init 签名/点数上限 13·11/qualityLevel/setComputeDevice）——与 07-RESEARCH 记录 diff，漂移即回注 planner（C 档门控），无漂移落 DECISIONS 一行。
  2. **benchmark**：100MP GFX RAF 解码帧 + 24MP 常规帧 × {层 A, 层 B（模型就绪态）, personSeg, faceLandmarks} × qualityLevel {fast/balanced/accurate} × {ANE, CPU pin} 实测耗时 + mask 分辨率，落 `.work/07/perf.md`（表格 + 机器/SDK 版本头注）。层 B 模型未下载时先 `downloadAssets`（下载耗时一并记录）。
  3. **SC#5 门定夺输入**：按实测分布给出"单次生成 ≤1s 可接受"的判定建议（执行期决策，最终门值落 DECISIONS；只记录不设 perf 门——与 PERF-5 口径同）。
- **证据**：`perf.md`（数字表）+ DECISIONS 复核结论 + benchmark 可重跑（脚本或 dev-only 测试形态，执行期决策）。

### T2 AIMaskService 核心 + 层 A 接入

- **action**
  1. `LightamerCore/Sources/AI/`（新目录）`AIMaskService`：`VNImageRequestHandler`/`perform(on:)` 封装 + 后台 Task（Swift concurrency，推理非拖动热路径）+ 推理输入构造（解码帧 IOSurface-backed texture → `CVPixelBuffer` → `CIImage` 零拷贝路径，**L014 fence 前置**）+ device 面（ANE 优先 `setComputeDevice` / 测试 CPU pin 注入）。
  2. 层 A 接入：`VNGenerateForegroundInstanceMaskRequest` → `VNInstanceMaskObservation`——`allInstances` 枚举 + `generateMask(forInstances:)`（低清勾选子集）+ `generateScaledMaskForImage(forInstances:from:)`（原分辨率，**首选**）——多 instance 子集选择进 `AIMaskTypes`（服务返回 instance 列表 + 子集 mask 两段 API，勾选浮层 07-3 消费）。
  3. typed error 面：推理失败 / 无主体（`results` 空）/ handler 错误三分（`AIMaskTypes`），供 UI 报错与"不落 mask"失败腿。
- **证据**：`AIMaskDeterminismTests` 层 A 腿（同输入同 CPU device 两次推理 mask 逐字节恒等，进程内 + 跨进程各一）+ `supportedComputeStageDevices` 含 CPU 枚举断言。

### T3 层 B 接入 + 下载三态 + 双后端回落

- **action**
  1. `GenerateIterativeSegmentationRequest` 接入：`init(seedPoint:)` / `init(seedBox:)`（**scribble 种子 v1 不接**——D-07-CONTEXT-4，`AIMaskTypes` 种子枚举预留 scribble case 注记升级缝）+ `addIncludedPoint/addExcludedPoint`（点数上限 13/11 计数与超限 typed error）+ `qualityLevel`（`.accurate` 起步）+ `regionOfInterest` 透传。**交互点 Y 翻转换算收口在 `AIMaskTypes`**（`y_vision = 1 − y_view_norm`，单测常驻）。
  2. `AIAssetStatus` 状态机：`assetStatus` 三态（未下载/下载中含 `Subprogress` 回调/就绪）+ `downloadAssets(progress:)` 包装 + 首启预下载策略入口（提示制——用户同意后后台下载，拒绝则层 B 入口禁用引导；D-07-CONTEXT-1）。
  3. **双后端回落**：层 B 未就绪 → 调用方拿 typed error/状态可禁用层 B 入口；层 A 全程可用不受影响（回落是 UI 入口级非服务内部静默切换——语义边界落 DECISIONS）。
  4. App 侧 `AIDownloadPrompt`（首启预下载提示 + 进度呈现；**层 B 下载中/失败不静默**）——挂接点执行期决策（AppState/AppDelegate 启动序列），07-3 MaskToolbar 复用同一状态模型。
- **证据**：`AIMaskSemanticTests` 层 B 腿（合成图 seedPoint 点中主体 → mask 非空 + addExcludedPoint 后主体内 mask 下降方向断言）+ 点数上限超限 throws 单测 + Y 翻转向量单测 + `AIAssetStatus` 状态机跃迁单测（下载失败可重试）。

### T4 mask 上整形 + bake 接线（移交清单①③）

- **action**
  1. `AIMaskResample`：层 A/层 B mask 低于解码帧分辨率时**双线性**上采样至解码帧分辨率（**独立于** `RasterMaskStore.load` 的 per-scale nearest 口径——load 只对已 bake 高分辨率 PNG 跨 scale 缩小，二者并存、注释钉死边界）；行 0 = 图顶对齐断言（与输入像素对齐，无翻转）。
  2. `RasterMaskStore.bake` 增件：可选羽化半径参数——bake 前对 r32Float mask 平面跑单通道 Gaussian（`MaskPostProcessKernels` 复用；L018 平面纪律如适用）。**零既有行为改动**（默认半径 0 == 现行为，回归钉住）。
  3. **同 maskID 覆盖重 bake**（D-07-CONTEXT-5）：`<maskID>.png` 覆盖写 → `maskHash` 随 PNG 字节变 → `MaskSpec.stableHash()` 翻转 → mask plane/前缀缓存链自动失效——**只验证不新增机制**。
  4. 消费面最小 API：`AIMaskService.generate(...) -> r32Float 平面 + bake 参数`（挂层写入/stackSnapshot 在 07-3 UI 层——本 plan 服务接口先行，App 不接线编辑流）。
- **证据**：`AIMaskGeometryTests`（上采样双线性权重断言 + 对齐 + 羽化剖面）+ `RasterMaskRoundTripTests` 扩展（AI mask bake→load uint16 恒等 + 覆盖重 bake 后 hash 翻转 + mask plane 缓存失效记账）+ bake 默认参数零改动回归。

### T5 测试收口 + 回归 + SUMMARY

- **action**：全量回归（0 fail；Vision 测试进 suite 的部分全 pin CPU——CI 稳定性）；无主体 nil 报错腿（纯背景合成图 → typed error 不落 mask）；层 A 多 instance 子集 mask case；TODO 勾选；`07-1-SUMMARY.md` + DECISIONS（SDK 复核结论/SC#5 门建议/回落语义边界/上采样与 bake 增件实现形态）。
- **证据**：测试计数 + SUMMARY + `perf.md` 基线在档。

## Verification

| 验收面 | 判据 | 命令 |
|---|---|---|
| 确定性门 | 同输入同 CPU device 两次推理 mask 逐字节恒等（层 A 进程内+跨进程；层 B 进程内） | `Scripts/test-direct.sh 'AIMaskDeterminismTests'` |
| 语义门 | 合成图 IoU ≥0.9 / 背景区 ≤0.1；层 B seed 非空 + excluded 方向下降；无主体 typed error | `Scripts/test-direct.sh 'AIMaskSemanticTests'` |
| 烘焙 round-trip | AI mask bake→load uint16 恒等 + 覆盖重 bake hash 翻转 + 缓存失效记账 | `Scripts/test-direct.sh 'RasterMaskRoundTripTests'` |
| 几何 | 上采样双线性 + 行 0=图顶 + Y 翻转向量 + 羽化剖面 | `Scripts/test-direct.sh 'AIMaskGeometryTests'` |
| benchmark | `.work/07/perf.md` 基线表 + SC#5 门建议落 DECISIONS | 读文件 |
| 回归 | 全 suite 0 fail | `Scripts/test-direct.sh`（全套） |

## 验收标准（Acceptance）

- [ ] SDK 复核结论落 DECISIONS（漂移即回注 planner，零静默）；benchmark 基线落 `.work/07/perf.md` + SC#5 门建议（执行期决策记录）
- [ ] 层 A：确定性恒等（逐字节，进程内+跨进程）+ 合成图 IoU ≥0.9 / 背景 ≤0.1 + 多 instance 子集 + 无主体 nil 报错腿（不落 mask、不降级全一平面）
- [ ] 层 B：seedPoint/seedBox + 含/排点 + 超限 throws + Y 翻转单测 + scribble 枚举升级缝注记
- [ ] 下载三态 + 首启预下载提示 + 双后端回落（层 B 未就绪禁用引导、层 A 不受影响）；下载失败不静默
- [ ] bake 接线：双线性上采样（对齐断言）+ 羽化增件（默认零改动回归）+ 同 maskID 覆盖重 bake（hash 翻转 + 缓存失效验证，零新机制）
- [ ] 测试全 pin CPU（`supportedComputeStageDevices` 枚举断言常驻）；L014 fence 在推理输入构造路径固化
- [ ] 全量 suite 0 fail；无 /tmp 过程产物入工作区；决策入 `07-1-DECISIONS.md`；SUMMARY 落盘
