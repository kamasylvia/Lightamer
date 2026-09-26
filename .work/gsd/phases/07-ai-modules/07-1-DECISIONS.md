# Plan 07-1 Decisions — Vision 基建 + AI-01 主体隔离

> 执行期决策 + SDK 复核结论。规划期决策见 `07-CONTEXT.md`（D-07-CONTEXT-1..6）。

## D-07-1-T1-1: SDK 复核结论——零漂移（首任务）

对本机 `MacOSX27.0.sdk` `Vision.swiftmodule/arm64e-apple-macos.swiftinterface` 逐符号复核 `:1700-1766` 快照（2026-09-24 复核）：`GenerateIterativeSegmentationRequest` 全成员与 07-RESEARCH 记录一致（availability macOS 27.0 / DownloadableAssetsRequest / assetStatus / downloadAssets(progress: consuming Subprogress) / Result = PixelBufferObservation? / revision1 / QualityLevel {accurate, balanced, fast} / init(seedPoint:|seedBox:|seedScribbleBuffer:) / regionOfInterest / setComputeDevice / addIncluded·ExcludedPoint throws / qualityLevel / supportedComputeStageDevices）。**无 API 面漂移，无需回注 planner。**

命名差异（非漂移，仅 Swift 化拼写记录）：新 Swift struct `InstanceMaskObservation` 的成员为 `allInstancesMask` / `generateScaledMask(for:scaledToImageFrom:)`（research 引用的 `instanceMask` / `generateScaledMaskForImage(forInstances:from:)` 是旧 VN ObjC API 拼写）；本 plan 全部走新 Swift API（`Vision.ImageRequestHandler` + `perform`，macOS 15+ 面），**不用** VNImageRequestHandler——新 API 是唯一暴露 `setComputeDevice`/`supportedComputeStageDevices` 的面（测试 device pin 的前提）。

## D-07-1-T1-2: 设备面现实——CPU pin 不可行（回注 planner 项）

**规划前提与 OS 现实冲突**：CONTEXT/PLAN 假设「测试 pin CPU（supportedComputeStageDevices 枚举断言含 CPU 常驻）」。实测（macOS 27.0b 26A428，探针 + benchmark 双重复现）：

| 事实 | 证据 |
|---|---|
| layer A supportedComputeStageDevices[.main] = **[ane, gpu]**，layer B = **[gpu]**——CPU 不在集合 | bench-full.log 枚举节 |
| pin 不支持的设备**不抛错而是 SIGTRAP**（EXC_BREAKPOINT） | pin-probe（cpupin-main → RC=133，.ips 在案） |
| layer B pin GPU（在 supported 集内！）**进程 SIGKILL**：Foundation "recursively lock an os_unfair_lock" abort——Vision beta bug | pin-probe4 gpupin → RC=137，.ips 在案 |
| layer A pin GPU：512 合成图可用且逐字节确定；100MP 实拍图 SIGTRAP | pin-probe2 / bench 两次 100MP 崩溃 |

**落定**：
1. `AIMaskService` 的 pin 全部**先验校验** supported 集（防 trap），layer B 一律拒绝 pin（typed `deviceUnavailable`，注释钉 beta bug）。
2. 测试确定性策略改为：**layer A = `.gpuPinned`（合成 512 图，逐字节恒等已探针实证）+ layer B = `.anePreferred` 不 pin（default ANE 逐字节恒等已探针实证 2/2）**。确定性门的语义（同 device 两次推理逐字节恒等）不变——「同 device」在 layer B 腿由「default 选择稳定」承载（本机 = ANE）。
3. 测试断言改为「supportedComputeStageDevices 含 GPU（两层）」+「CPU 缺席时 cpuPinned 抛 typed error 不崩」——替代规划期的「含 CPU 常驻」断言。
4. **回注 planner**：07-2/07-3 与 SC 相关措辞中「测试 pin CPU」一律按本决策口径替换；若 macOS 27 正式版 supported 集加入 CPU，恢复 cpuPinned 路径（`AIDevicePolicy.cpuPinned` 保留）。

## D-07-1-T1-3: SC#5 门定夺建议（执行期决策，供签核采信）

按实测分布：**「单次生成 ≤1s」建议按 warm 路径裁定 = PASS**——layer A warm 14-16 ms、layer B accurate warm 85-126 ms（25-102MP 全档），全部 ≪ 1s。cold（进程内首次，模型编译）layer A 最高 5.5 s——一次性成本，由生成中 spinner（后台 Task 既定架构）承接，不计入门值。最终门值随 07-3 签核落 VALIDATION。

## D-07-1-T2-1: 推理输入零拷贝路径 = `CIImage(mtlTexture:)`（fence 前置）

规划的「IOSurface-backed texture → CVPixelBuffer → CIImage」链在现管线下不可直接成立：解码帧纹理均为 `.shared` storage 直接 makeTexture（非 IOSurface 分配），`texture.iosurface == nil`。执行期落定：`AIMaskInput(texture:)` = **L014 fence（commit 空 buffer + waitUntilCompleted）+ `CIImage(mtlTexture:options:)`**（working-space 色彩标签）——同等零拷贝语义（GPU 字节不动，CI 内部队列采样时读），fence 纪律不变。CVPixelBuffer 直入腿保留（测试与 buffer 管线用）。

## D-07-1-T2-2: handler 复用形态 = 每次生成新建 `ImageRequestHandler`

新 Swift `ImageRequestHandler` 是轻量值包装（模型缓存进程级在 Vision 内部），per-call 新建无摊销损失；layer A 两段 API 的 stage 2（`generateScaledMask`）需要 stage 1 的 handler 存活——由 `AIInstanceCatalog` 携带（observation + handler 同体返回）。不缓存 handler（「推理中间态不缓存」红线）。

## D-07-1-T3-1: 点数上限计数口径 = 种子计 1 + 全部 refine 点（point 种子 ≤13 / box 种子 ≤11）

SDK 不说明其内部 13/11 上限是否含种子。服务层门 = **确定性预检**：point 种子计 1 + refine 计数 ≤ 13；box 种子 0 + refine ≤ 11，超限先于 Vision 抛 `AIMaskError.pointLimitExceeded`；Vision 自身 throw 一律折叠进同 typed face（兜底）。UI 计数器（07-3）消费同一常量（`AIPointBudget`）。

## D-07-1-T3-2: AIDownloadPrompt 挂接点 = ContentView（modifier）

首启提示是 app 级状态：`AIDownloadPrompt` ViewModifier 挂 `ContentView`（.task bootstrap + alert×2 + 下载进度 safeAreaInset）；状态模型 = Core `AIAssetStore`（07-3 MaskToolbar 复用同一 actor，不建第二状态机）。Subprogress 包装 = `Progress.subprogress(assigningCount:)` 直传 `downloadAssets(progress:)`（consumers 语义经编译验证）；KVO 桥接 `NSProgressFractionCompletedDidUpdate` → phase（下载进度呈现非静默）。

## D-07-1-T4-1: bake 羽化增件实现形态 = `MaskCombiner.blur` 复用（IOP metallib 软依赖）

`RasterMaskStore.bake` 增 `featherRadius: Float = 0` 参数：>0.1（dt 门）时经 **Core 侧已有的 `MaskCombiner.blur`**（单通道 Deriche IIR，`MaskPostProcessKernels.metal` 的 mask_blur_col/row/store——IOP metallib 经 registerDefaultLibrary 解析，与 06-04 parametric 后处理链同源同核）预跑一遍再量化。**默认 0 = 零字节改动**（回归钉死）。不新建 `LightamerCore/Sources/Metal/MaskPostProcessKernels.metal`（plan files_modified 的「如需适配」分支：复用为主，无需拷贝）。

## D-07-1-T4-2: 上采样边界实测更新——layer B balanced/accurate 产全分辨率

benchmark 实证 layer B balanced/accurate 直接产解码帧分辨率 mask（102MP 11648×8736），仅 fast（256×256）需上采样。`AIMaskResample.upsampleToDecodeFrame` 的「小于才升」门让 balanced/accurate 自动跳过（零成本直通）；双线性 kernel 与对齐断言不受影响（fast 档 + 几何单测覆盖）。

## D-07-1-T2-3: benchmark 可重跑形态 = 独立 swiftc 脚本（`.work/07/bench.swift`）

不入 test suite（百兆实拍 + 分钟级跑时会拖垮 CI 节奏）；perf.md 头部注释含编译/运行命令。

## D-07-1-T2-4: `generateScaledMask` 双重损坏 → 层 A stage 2 统一走 `allInstancesMask` 标签合成（Apple 修复后升级缝）

探针实证（macOS 27.0b 26A428，单盒/双盒合成图两组独立复现）：

1. **subset 语义坏**：`generateScaledMask(for: [1])` 渲染全部 instance、`for: [2]` 渲染空——仅精确等于 `allInstances` 的集合正确。
2. **几何偏移**：all 集合的 mask 相对主体**双轴 +3/16 偏移**（居中 0.25..0.75 盒落在 0.44..0.94；语义门首跑 IoU 0.328 + 右背景泄漏 0.498 即此）。
3. `allInstancesMask` 标签图（'L008'）两案几何与分割均正确。

**落定**：`subjectMask(from:selection:)` 的 `.all` 与 `.subset` 都走标签合成腿（label ∈ selection → 1，分辨率 = 标签图分辨率，bake 时双线性上采样——与层 B 同一 reshape 契约）。代价 = 放弃 scaled 的全分辨率软边（标签图为硬 0/1 + 上采样软化）；`scaledMask` 私有函数保留为升级缝（注释钉死切换条件）。**回注 planner**：07-3 的层 A 蒙版精度预期按标签图分辨率口径。

另：scaled 输出格式为 half-float `'L00f'`（0x4C303066）——`maskPlane(from:)` 已加该格式读法（文档没写，探针定标）。

## D-07-1-T2-5: 跨进程确定性探针 = app init 时机驱动 + LaunchServices/直exec 双可跑

探针最初挂 Window `.task`（sidecarProbe 同款）——在本环境实测不触发（scene 生命周期敏感）；改为 **`LightamerApp.init()` 直接驱动**（pre-scene、环境无关，跑完 `exit(0)`）。测试内经 `/usr/bin/open -n -a` 拉起（直 exec 会撞 launch constraints：`sandbox_extension_issue_file_to_process`）。探针代码在 `#if DEBUG`。

## D-07-1-T3-3: 测试宿主的层 B 资产下载被 entitlement 阻断 → 推理腿 skip-with-reason（07-3 GUI 轮真机复验）

xcodebuild 测试构建给 app 注入 test entitlements（mach-lookup temporary-exception 等）；该上下文里 `downloadAssets()` "成功"但 `assetStatus` 恒 `notReady`（bench 的普通未签名二进制一切正常，3-11ms ready）→ 测试宿主内层 B **推理**腿（determinism 的层 B in-process + semantic 的 seed/excluded）以 `XCTSkipUnless` 带原因跳过。证据链：probe + bench 的普通进程行为在 `.work/07/perf.md`；层 B 服务逻辑（种子/预算/Y 翻转/门控）全部不依赖推理已测；**07-3 GUI 验收轮在真实 app 上下文复验层 B 端到端**（已登记为 07-3 前置项）。

## D-07-1-T3-2 补充: 下载进度 v1 = 不定态 spinner

macOS 27 无 `NSProgressFractionCompletedDidUpdate` 类通知（编译实证）；实测下载 3-11ms 无进度粒度可言。`Progress`（非 Sendable）不跨 actor hop——v1 UI 用不定态 spinner，`downloadAssets(progress: Subprogress)` 消费缝保留在 store 层。

## D-07-1-T1-2 补充: layer B 点数上限的 SDK 自身 throw 语义未触发

Vision 自身 13/11 上限在本机全部由服务层预检先行（`pointLimitExceeded`），SDK throw 分支未被观察到——保留 try/catch 折叠为兜底。
