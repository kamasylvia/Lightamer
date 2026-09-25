# Phase 11 Research: Export Pipeline & Batch Queue（导出管线与批量队列）

**Gathered:** 2026-09-26（researcher subagent；前提 = 11-CONTEXT.md D-11-CONTEXT-1..8，
逐条落实验证，零推翻——两处 API 事实修正见 §1.3/§4.4，均不触裁决意图）
**Status:** Ready for planning — 八问全答 + 本机 UTI 实探钉死 D-11-CONTEXT-1

<domain>
## Summary

- **六格式编码面全在 ImageIO（CGImageDestination）+ 单点 libwebp**。本机实探（2026-09-26，
  `swift` 一次性脚本跑 `CGImageDestinationCopyTypeIdentifiers()`，macOS 27 host）：
  **AVIF=`public.avif` 存在 ✅ / WebP 缺失 ✅（证实 libwebp 必需）/ HEIC/TIFF/PNG/JPEG 全有**。
  D-11-CONTEXT-1 的 reversibility 条款（「research 验证即钉」）就此闭环，libavif 不进 v1。
- **渲染→编码出口**：EXPORT 管线（float32 linear Rec2020、无缓存语义已就位）→ 出口一次
  转换（复用 `CIContextPool` bitmap 腿，per-render `colorSpace:` 即 ICC primaries+TRC 一次
  完成）→ CPU 按格式量化 8/16/32f。量化域分层照 D-11-CONTEXT-7：显示域 8/16-bit、
  TIFF 32f 保线性。
- **队列**：`ExportQueue` actor 完全复刻 9-3 `SessionThumbnailProvider` 的 generation-cancel
  + 有界并发骨架（并发 1）；专用 `MTLCommandQueue` 经 **TaskLocal 路由**接入既有 dispatch
  面（零 iop 调用点改动）。⚠️ D-11-CONTEXT-2 写的 `queue.priority = .low` **无公开 Metal API**
  （SDK 头文件实证，§4.4）——「低优先级」落地为独立队列 + 并发 1 + Utility QoS 提交，裁决
  意图（不阻塞编辑）不变。
- **yiyin（EXP-05）**：联合上下文注入生产先例已在 `injectYiyinRunContext`
  （PipeCoordinator.swift:1587-1626）+ 无头等价先例在 `YiyinE2ETests.swift:260-273`；
  版式分辨率无关（08-3 已验 PREVIEW vs 2× 归一化相等）→ 任意 EXPORT 分辨率直接继承。
- **SPM 新增唯一依赖 = `ainame/Swift-WebP`**（MIT / Swift 6 language mode / libwebp 1.5.0+
  via libwebp-Xcode / macOS 11+ / SPM，WebPEncoder+Config 覆盖 lossy/lossless+quality）。

</domain>

<research>
## 1. 六格式编码矩阵（EXP-01/02）

### 1.1 运行时探针（本机实证，2026-09-26）

```swift
let ids = CGImageDestinationCopyTypeIdentifiers() as! [String]
// 结果（macOS 27 / Apple M4 host）：
// public.avif = true / org.webmproject.webp = false /
// public.heic = true / public.tiff = true / public.png = true / public.jpeg = true
```

- `public.avif` 恒可用（macOS 27 地板）→ **libavif SPM 免引入**（D-11-CONTEXT-1 钉死）。
- WebP 写缺失 → libwebp SPM 是唯一新依赖（与 CONTEXT 预判一致）。
- 探针脚本一次性，不入仓；执行轮 golden 测试内固化同等断言作回归锚。

### 1.2 每格式参数面（CGImageDestination / libwebp）

| 格式 | UTI | 位深 | 质量键 | 色彩空间 | 压缩/备注 |
|---|---|---|---|---|---|
| JPEG | `public.jpeg` | 8-bit | `kCGImageDestinationLossyCompressionQuality`（0-1，10.4+） | sRGB/P3/AdobeRGB/ProPhoto 任一 ICC（`kCGImageDestinationColorProfile` 或 CGImage 自带） | 4:2:0/4:4:4 不外露；EXIF/IPTC/XMP 经 metadata 键 |
| PNG | `public.png` | **8/16-bit**（源 CGImage `bitsPerComponent` 决定，无质量键） | —（deflate 内置，无选项面） | 同上 + `gAMA/sRGB` chunk 派生自 ICC | EXP-01 只要 8/16-bit，无需压缩菜单 |
| TIFF | `public.tiff` | **8/16/32-bit float**（32f = floatComponents CGImage，先例 `YiyinE2ETests.swift:318-325` 构造 + `.work/plans/02-04/probe-tiff.swift` 实证可写） | — | 同上；32f 目标 = 选中 primaries 的**线性变体** ICC（§3.3） | `kCGImagePropertyTIFFDictionary[kCGImagePropertyTIFFCompression]`：`1`=None、`5`=LZW、`8`=AdobeDeflate(ZIP)（7=JPEG 不用——有损域混线性域有歧义；PackBits 32773 仅 8-bit，不进 v1 菜单） |
| HEIC | `public.heic` | **8/10-bit** | `kCGImageDestinationLossyCompressionQuality` | 同上 | 10-bit 路径 = 16bpc 源 CGImage 或 `kCGImageDestinationEncodeBasePixelFormatRequest`（SDK 标 macOS 16+，本机可用）——**执行轮 golden 验证项** |
| AVIF | `public.avif` | **8/10-bit 确证、12-bit 执行轮验证** | `kCGImageDestinationLossyCompressionQuality` | 同上 | 原生 macOS 26+；12-bit 走 16bpc 源同 HEIC——**执行轮验证**，失败即 v1 文档化 8/10-bit 上限（不引 libavif，协议缝 `AVIFEncoder` 保留） |
| WebP | （libwebp 直编，不走 ImageIO） | 8-bit（libwebp v1 能力边界） | `WebPEncoderConfig` preset + quality；**lossless** 独立配置面 | 显示域 ICC chunk 需 mux（§2.3 OQ） | 输入 = 量化后 RGBA8 buffer + stride |

- **DPI**：纯元数据——所有 ImageIO 格式经 `CGImageDestinationAddImage` properties 的
  `kCGImagePropertyDPIWidth/Height` 写入（`YiyinExportSettings.swift:39-41` 预告的消费点）。
  不影响像素；yiyin DPI 语义照搬。
- **色彩空间嵌 ICC**：统一走「目标 CGColorSpace 先转换进像素 + 嵌 profile」：
  `CGImageDestinationAddImage` 时 CGImage 自带 target colorspace，ImageIO 自动嵌 ICC；
  或显式 `kCGImageDestinationColorProfile`。推荐前者（转换与嵌入同源，杜绝错配）。
- **元数据 round-trip（EXP-05/D-11-CONTEXT-5）**：
  - 读：`CGImageSourceCopyMetadataAtIndex(src, 0, [kCGImageSourceShouldCache: false])`。
  - 写：`kCGImageDestinationMetadata`（10.8+）+ 不加 `MergeMetadata`（见 §1.3 事实 2）。
  - 编辑摘要：mutable metadata 上 `CGImageMetadataSetValueWithPath` 写 `xmp:CreatorTool`
    = Lightamer + 版本；rating/flag 字段面 Phase 12 预留（本 Phase 只留 API 位）。

### 1.3 两处 ImageIO 事实修正（不推翻 D-11-CONTEXT-5，落地形态修正）

1. **XMP packet 语义**：SDK 头文档明示「指定 `kCGImageDestinationMergeMetadata` 时保留
   EXIF/IPTC 但**不写 XMP packet**」→ 正确姿势 = `kCGImageDestinationMetadata` **整体替换
   模式**（不带 Merge），源 metadata 含 XMP packet 才会跟随写入。每格式是否真落 XMP
   （JPEG/TIFF/PNG/HEIC/AVIF 逐个）= **执行轮 golden 断言项**；失败格式的文档化限制 +
   后补二段式（重编码代价大，v1 只做文档注记）。
2. **WebP 元数据例外**：libwebp 裸 encode（RGBA buffer 入口）无 EXIF/ICC/XMP 面——
   WebP 容器元数据走 `WebPMux` chunk。**Swift-WebP 当前公开面未见 mux 封装** → v1 推荐：
   WebP 无内嵌元数据 + UI 文档注记（ROADMAP Notes「EXIF+XMP embedded」对 WebP 打折）；
   若执行轮确认其隐藏面含 mux 再升级（OQ-11-5）。

## 2. WebP SPM 选型（EXP-02，全项目唯一新增依赖）

### 2.1 候选对照

| 候选 | License | 维护 | Swift 6 | SPM | encode API | 判定 |
|---|---|---|---|---|---|---|
| **ainame/Swift-WebP** | MIT | **活跃**（v0.6.0 现代化重构；Swift Package Index 在册；2026-07 registry 记录） | **language mode 6，toolchain 6.2.3** | ✅ | `WebPEncoder.encode(rgbaPointer, format:, config:, originWidth:, originHeight:, stride:)` + `WebPEncoderConfig`（preset+quality；lossless 面在 config） | **推荐** |
| TimOliver/WebPKit | MIT | 陈旧（README「SPM coming soon」长期未兑现） | 未声明 | ❌/半 | 有 | 否 |
| `swift-libwebp`（STACK.md 泛称） | — | 无单一活跃同名 repo 命中 | — | — | — | 否（泛称落空） |
| vendored libwebp 自绑 | BSD-3 | 自己背 | — | ✅ | 自写 shim | 备选兜底（仅当 Swift-WebP 执行轮暴露硬伤） |

### 2.2 推荐包事实（官方 README 核过，glm-webReader 拉取 2026-09-26）

- `libwebp 1.5.0+`（经 `libwebp-Xcode` 传递依赖——C 源码包，SPM 原生构建，无 xcframework
  下载步骤）；macOS deployment target 11.0+（macOS 27 地板下无约束）；跨平台含 Linux。
- decode/encode/`WebPImageInspector`（码流检查——lossless golden 断言可用）。
- v0.6.0 起 minor breaking（本 Phase 新引入无迁移负担）。

### 2.3 集成注意（执行轮）

- **依赖落位**：`Project.swift` Tuist manifest 加 `packages: [.package(url: "https://github.com/ainame/Swift-WebP.git", from: "0.6.0")]`，product `WebP` 挂 **LightamerCore** target（D-03 约束 = Core 不依赖其他 Lightamer target，外部包不受限；编码器按目录惯例放 `LightamerCore/Sources/Export/`——与 sidecar 同批「Core 级可单测」红线）。App 的 `LSItemContentTypes` 已含 `org.webmproject.webp`（Project.swift，读取侧已在）。
- **网络**：本机 USB 外置卷 + 直连环境；首次 `tuist fetch`/`swift package resolve` 需 GitHub 直连。实测本会话 glm-webReader 可达 GitHub 页面（云端读）；本机 git 直连失败则 `px --up` 走代理完成**首次** fetch，SPM 缓存落定后离线增量构建无碍。
- **Swift 6 strict concurrency**：包 language mode 6（README 声明），但其 API 是否全部 `Sendable` 标注 = **执行轮验证**；即使不达标，我们的调用面把它圈在 ExportQueue actor 内的单编码路径（§4），`@unchecked` 边界成本≈0。
- lossless 具体 knob 名（config 字段 vs preset case）执行轮按 API 面 定——能力面（lossy/lossless+quality）README 已证。

## 3. 渲染→编码出口（EXP-01..04、05；D-11-CONTEXT-7 落地式）

### 3.1 管线现状与 EXPORT 激活点

- 四管线声明齐备：`PipeResolution.export`——「export target size、no caching、reserved stub
  runs throw .notImplemented」（PipeResolution.swift:36 + PixelPipe.swift:475-476/:644-645
  两处 typed stub）。`cachesIntermediatePlanes == false`（PipeResolution.swift:43-48）→
  EXPORT 无缓存语义现成，`PipeCacheKey.pipeType` 独立命名空间（PipeCacheKey.swift:37）。
- 两条渲染入口都在：`RenderPipeline.process`（平链）/ `processComposite`（调整图层合成），
  `resolution: .export` 参数现成（renderCurrentChain 的调用形，PipeCoordinator.swift:1418/:1437）。
- **链尾裁剪（gamma 出链）**：`gamma`（78.0）是显示交接（sRGB TRC + 唯一 clamp + bgra8，
  GammaModule.swift:14-17；管尾格式策略 PixelPipe.swift:221-222 只认 gamma 在尾）。导出链
  **只剔除 gamma record**（导出组装器过滤 `opName == "gamma"`）→ 管输出保持 float32 线性，
  管尾格式策略永不触发，零管内改动。colorout 是否同剔见 OQ-11-2。

### 3.2 出口转换 = 单次 CI bitmap render（COLOR-2 矩阵族的 CI 腿复用）

- **机制**：`CIImage(mtlTexture:options:[.colorSpace: WorkingSpace.colorSpace])`（纹理即
  linear Rec2020，CIContextPool.swift:481-485 同款）→ `ciContext.render(toBitmap:rowBytes:
  bounds:format: .RGBAf, colorSpace: <目标CGColorSpace>)`（:494-501 同款）。ColorSync 在
  这一次 render 里完成 **primaries + white + TRC encode** 全部 ICC 语义——线性值进、
  目标编码值出。D-11-CONTEXT-7 的「单出口转换」字面落地。
- **先例与纪律**：`CIContextPool.convertTexture`（:460-521）是同族函数但只出**线性**目标
  （display 腿 TRC 归 gamma 模块）；导出新增姊妹函数
  `renderToEncodedBitmap(_:toSpace:width:height:) -> [UInt8/float32 buffer]`（不建纹理，
  直出 CPU buffer——导出不需要纹理回腿）。三纪律必抄：
  1. **跨队列 fence**（:477-479，L014/GUI-22）：CI 读纹理前 empty-command-buffer
     commit+wait，fence 挂 **exportCommandQueue**（§4.3）非主队列。
  2. **`cacheIntermediates: false`**（CIRAW-4，:148）。
  3. CI 渲染是 CPU bitmap 腿（host finding :18-42）——导出腿天然同型，无「直渲纹理 no-op」风险。
- **Metal 直渲腿 vs CI 腿取舍**：CI 腿（推荐）= 复用 ColorSync 任意 profile（AdobeRGB/
  ProPhoto 无需手写矩阵）；Metal 腿（COLOR-2 常量矩阵族）仅覆盖 Rec2020→P3/sRGB 两族
  （ColorOutModule.swift:33-49），ProPhoto/AdobeRGB 无常量矩阵。导出是吞吐场景，
  10-30ms@2560px 的 CPU 往返可接受（:458-459 已批注同款成本），全分辨率一次付。
  **不**为导出新增 Metal 矩阵族。

### 3.3 量化链（格式位深惯例表；dt 对标 imageio.c:1403-1460 的 `×0xff/×0xffff + CLAMP`）

| 目标 | 出口 colorspace（CI render 的 `colorSpace:` 参数） | 量化 | 产物域 |
|---|---|---|---|
| JPEG / PNG 8 / HEIC 8 / AVIF 8 / WebP | 目标 ICC（显示 TRC 版：sRGB/P3/AdobeRGB/ProPhoto） | `roundf(CLAMP(v*255))` | 显示编码 8-bit |
| PNG 16 / TIFF 16 / HEIC 10 / AVIF 10(12) | 同上（TRC 版） | `roundf(CLAMP(v*65535))`（10/12-bit 在 16bpc 容器内 ×1023/×4095 源值域由编码器处理） | 显示编码（行业互操作惯例） |
| **TIFF 32f** | 目标 ICC 的**线性变体**（`CGColorSpace(name:.linearITUR_2020)` 等 / linear ProPhoto） | 原样 float32（≤CLAMP[0,1] 按 D-11-CONTEXT-7 钳亮度；不量化） | **线性**（scene-referred 交接） |

- **HDR 裁剪（D-11-CONTEXT-7）**：SDR 白以上钳位 = 量化前 `CLAMP(v,0,1)`（gamma 模块的
  唯一 clamp 语义搬到出口）；chroma 不裁 = 转换到**目标 primaries 后**才钳（宽域目标
  P3/Rec2020/ProPhoto 的域内值不被 sRGB 域强制）。中性灰恒中性（ColorSync 保灰，
  ColorOutModule.swift:47-49 已验的矩阵不变量同源）。
- **量化器单点**：`ExportQuantizer` 纯函数族（linear-or-encoded float buffer → UInt8/
  UInt16/Float32 + packed layout），golden 单测钉死（`×255` 四舍五入 vs truncation 用
  dt 同款 `roundf`）。
- 16-bit 优化位（可选不默认）：16-bit 目标可让 CI render 直接出 `RGBAh`（half，位深减半
  内存减半）再 CPU 量化——先 float32 全量正确性，Phase 15 再议优化。

### 3.4 resize/DPI（EXP-03）

- **resize = 管线入口 scale-at-entry**（现成机制：`renderToTexture(_:longEdge:)`
  CIContextPool.swift:221-266 + `PixelPipe.run` 的 entry scale；渲染即缩放，不付 100MP
  中间面）。`longEdge` 取 `ExportVariant.sizing.targetSize(canvasWidth:canvasHeight:)`
  的结果——**直接复用 `YiyinExportSettings`**（D-08-CONTEXT-7 预告的物理应用点；其
  `targetSize` 数学（YiyinExportSettings.swift:87-108）= original/长边/短边 + 永不放大 +
  100_000px 上限校验（:60-80），与 EXP-03「长边/短边/百分比/原尺寸」中「百分比」缺位）
  → 百分比模式在 variant 层换算成 longEdge px 后进同一数学（薄糖，不动 Core 模型）。
- **DPI = 纯元数据写**（§1.2），与像素正交。
- 溢画布/奇偶尺寸：编码器面无需对齐约束（JPEG/PNG/TIFF 任意偶奇；HEIC/AVIF 偶数
  对齐由 Apple 编码器内部处理——执行轮 golden 用奇数尺寸探一次）。

## 4. 队列规格（EXP-06/07；D-11-CONTEXT-2/8）

### 4.1 `ExportQueue` actor 契约（App/State 层；骨架照抄 9-3）

参照 `SessionThumbnailProvider`（SessionThumbnailProvider.swift:112-310）逐件复用：

| 9-3 件 | 导出版 | 出处行 |
|---|---|---|
| `actor` 隔离 + `pending/inFlight/concurrency` | 同构；`concurrency = 1`（D-11-CONTEXT-2，非参数偷懒——全幅 float32 工作面 ≈1.6GB@100MP） | :154-157 |
| `QueuedJob`（seq/generation 快照） | `ExportJob{id, imageURL, relPath, document 快照(instances+layerStack), variants, seq, generation, state}` | :145-151 |
| generation epoch + `cancelAll()`（bump + 清 pending + resume waiters nil；**在飞任务不中断**，generation 闸门丢弃结果） | 同语义 + `cancel(jobID)`（pending 移除；in-flight 置 cancelled 标——渲染完成后丢弃不落盘、tmp 删净） | :256-269 |
| `pump()`（并发闸 + 顺序） | FIFO（导出无可见优先；保留 seq 保序） | :272-283 |
| `execute()` 的 generation gate（:294 出闸后才付渲染） | 同——取消的 job 出闸即弃 | :285-310 |
| 测试缝 `ThumbnailDecodeLeg/RenderLeg` 注入 | `ExportRenderLeg` / `ExportEncodeLeg` 闭包注入 → 队列语义单测毫秒级（照 `SessionThumbnailProviderTests` 先例） | :107-110 |
| idle delay / visible jump（:140-143/:247-254） | **不要**——导出是吞吐场景，非交互；仅保留「编辑活跃让位」反向开关位（OQ-11-8） | — |

**job 生命周期状态机**：`pending → rendering → encoding → done(url)` / `failed(AppError)`
/ `cancelled`。`progress` 快照（`@Sendable` 快照结构体，UI 经 ExportState 桥）两层：
队列层 `(done, total)`（EXP-07 的 N variants = N jobs 计入 total）+ job 层
`phase(rendering|encoding)`（不承诺渲染内百分比——单一管线调用无渐进点）。

**retry 策略**：**无自动重试**（v1；dt 同款——单图 store 失败即整体 cancel job，
control_jobs.c 的 `_control_export_job_run` 循环）。`failed` job 保留 error + 显式
`retry(jobID)` 重新入队尾（EXP-06 的「失败重试」= 供能不自动）。可重试性判定不做
错误分类（幂等：删 tmp 即可重跑；D-11-CONTEXT-8 幂等论证）。

### 4.2 与 9-3 复用清单（直接照抄件）

- generation 取消 + 有界并发 + continuation waiters + 测试缝注入 + actor 单实例生命周期
  （session 切换 `cancelAll()` + `flushForTeardown` 语义位——导出无 journal，D-11-CONTEXT-8，
  在飞 job 完成或丢弃随 generation 闸门）。
- **不复用**：双层 tier 判定 / stale 再生 / 磁盘缓存（导出无缩略图概念，CONTEXT 明示）。

### 4.3 专用 MTLCommandQueue 接入（TaskLocal 路由，零 iop 改动）

- `MetalContext` 已预留接口位：头注「second low-priority export queue as a NEW property,
  never by reassigning」（MetalContext.swift:12 + :48-49 D-15）。init 里
  `device.makeCommandQueue()` 再造一条挂 `exportCommandQueue`。
- **路由机制（推荐）**：`MetalContext` 内 `@TaskLocal static var routesToExportQueue = false`
  + `makeCommandBuffer()`（:426-427，**全 dispatch 面唯一取队列点**——dispatch2D/
  dispatch2DTexture/makeEncoder 都走它）按 TaskLocal 选队列。导出 job runner 顶层
  `$routesToExportQueue.withValue(true) { try await RenderPipeline.process(...) }` →
  同一任务树下全部 iop dispatch 自动落 export 队列；编辑器任务树不受染。
  TaskLocal 随 async 传播、无 actor 作用域换队的重入竞态（对比「actor 暂时换 activeQueue」
  方案——导出 await PSO 构建期间编辑器 dispatch 会误入导出队列，弃）。
- **备选**（若执行轮证 TaskLocal 与 nonisolated makeCommandBuffer 组合有障碍）：给
  dispatch2D/dispatch2DTexture/makeEncoder 加 `queue:` 可选参（iop 不传 = 主队列；导出走
  PixelPipe 内部传）——签名改动 3 处 + PixelPipe 透传，iop 调用点零改。
- fence/CIContext：出口腿（§3.2）的 fence 挂 exportCommandQueue；导出腿用独立
  `CIContextPool(device:exportCommandQueue)` 实例（:141-150 构造参数现成）——其 GUI-22
  input-plane memo（:83）在导出场景是**反缓存**（memoByteCap 512MB :123 < 全幅面），
  导出实例以 `dedupeKey: nil` + identity 键走单次渲染即弃（memo 触 LRU 单超容容忍
  :120-123），或导出腿绕过 memo 直调私有 render 路径（构造 internal 可见即可）。
  **执行轮注意**：同图预览已冻结的 PREVIEW 输入面不能复用（尺寸不同），导出恒全幅
  一次 CIRAW 执行（可接受：导出本来就是重活）。

### 4.4 「低优先级」的 API 事实修正（回注级发现，非推翻）

- **D-11-CONTEXT-2 写 `queue.priority = .low`**——SDK 头文件实证（本机 xcrun SDK）：
  `MTLCommandQueue.h` 无任何 priority API；`MTLIOPriority` 只存在于
  `MTLIOCommandQueue.h:20`（IO 命令队列——磁盘/压缩流量，非 GPU 渲染/计算队列）。
- **裁决意图（不阻塞编辑）保留，机制改为**：独立队列（在飞缓冲不与编辑队列串行）+
  并发 1（GPU 峰值面预算）+ job runner 以 `Task.detached(priority: .utility)` 提交
  （CPU 侧 encode/IO 降 QoS）。Apple Silicon GPU 时间片无用户态优先级控制——若 Phase 15
  实测导出吃 GPU 影响编辑帧率，追加「编辑活跃让位」泵停（editor-active 信号延迟出队，
  9-3 可见优先的反向应用；接口位预留 `ExportQueue.yieldsToEditor`）。

### 4.5 与编辑互不阻塞的完整面（SC#2）

独立队列（4.3）+ 并发 1（4.1）+ Utility QoS（4.4）+ **渲染懒执行**（job 出队才渲染——
导出不在 PERF-07 零渲染约束域，CONTEXT §domain#5）+ 内存预算：单 job 峰值 ≈ 输入面
1.6GB + 管中间 ping-pong 2×面 + 出口 bitmap 1.6GB + 编码中间 ≈ 5GB 级 @100MP（32f
TIFF 落盘再 +1.6GB 文件）——并发 1 是红线推导（CONTEXT 同），执行轮 perf 记录（不设门）。

## 5. yiyin 应用点（EXP-05）

- **生产注入先例**：`injectYiyinRunContext(longEdge:resolution:)`
  （PipeCoordinator.swift:1587-1626）——per-run DATA（captureExif/logo provider/
  `JointContext(mainImageSize ⊕ bordersParams)`）经 `makeJointLayoutRecord` 落
  `bordersBox.module.jointLayoutOverride`；`mainImageSize` 严格镜像 entry scale
  （min(target/long, target/short, 1.0)，:1601-1608）。**无头等价先例已验证**：
  `YiyinE2ETests.swift:260-273` 在测试里做同一套注入并渲染成功——导出无头渲染器
  （§6）照此组装，不依赖 PipeCoordinator。
- **任意 EXPORT 分辨率继承结论**：08-3 已验 `YiyinLayout.layout` PREVIEW(2560) vs 2×
  全幅**归一化记录相等**（08-3-SUMMARY.md:26-27，20+ 字段真比较 + 舍入容差）——版式
  分辨率无关在 2× 成立，归一化数学（比例驱动）在任意分辨率成立；导出按 targetSize
  入链时 joint context 用**入链平面尺寸**（= targetSize），borders band 预留与水印行
  同比例缩放。执行轮 golden：同 recipe 出 2560 与 4096 两尺寸，归一化记录相等断言
  （照 08-3 断言复用）。
- **resize × 印框次序**（D-11-CONTEXT-3 variant 组成 → 单向流）：
  1. `variant.sizing.targetSize(源画布)` = **主图**目标尺寸（永不放大钳制在此）；
  2. 该尺寸 = 管线入口 longEdge（scale-at-entry 下采样）；
  3. borders（76.0）在链内**画布扩展**（比例预设 1.0-1.5 等）→ 最终输出 = targetSize ×
     边框扩展因子（**可大于 targetSize**——yiyin 语义：边框是加 margin，不是「输出
     不超过」约束）；watermark（77.0）行落 band；
  4. 出口（§3）→ 编码（含 DPI 元数据写）。
  - **无双 resize 主**：yiyin 关闭时 sizing 仍走同一 `targetSize`（EXP-03 独立成立）；
    yiyin 开启时 sizing 语义即 yiyin 的 OutputMode——推荐 variant.sizing **就是**
    `YiyinExportSettings` 实例（D-08-CONTEXT-7 的正主），面板里印框节与尺寸节绑同一
    模型（OQ-11-6）。
- **色彩语义注记（非阻塞）**：导出链保持 colorout 之后的 yiyin 于管线域（线性
  Rec2020）工作——与预览路径（线性显示域）存在 primaries 差；yiyin 颜色面 = 中性
  （白框/黑字/灰字）+ logo PNG。中性量各空间恒同；饱和 logo 色存在「管线域指派」
  既有语义（08-2 起 logo 字节被指派到管线 primaries——预览在 P3 显示下即已如此），
  导出与预览一致即契约，不新引入偏差。

## 6. EXP-08 安全面（post-export actions；D-11-CONTEXT-6 落地式）

- **shell 动作 = 路径制**：NSOpenPanel 选可执行脚本 → 存路径（非沙盒 app 无需
  security-scoped bookmark 才能读——`ENABLE_USER_SELECTED_FILES: read-write` 已在
  Project.swift；持久化用普通 `URL(bookmarkData:)` 做路径漂移校验即可，
  `withSecurityScope` 在非沙盒下无害等价，任选，推荐普通 bookmark + 启动时
  `checkResourceIsReachable` 降级提示重选）。
- **调用形态**：`Process` 直 exec——脚本有执行位 → `executableURL = 脚本URL`、
  `arguments = ["$1 输出文件路径"]`；无执行位（.sh 文本）→ `/bin/sh <脚本> <输出>`。
  **不经 shell 解释字符串**（D-11-CONTEXT-6 收窄注入面的字面兑现——用户路径含空格/
  元字符安全）。文档明示脚本以用户权限全权执行（MCP-10 同款哲学）。
- **触发语义**（OQ-11-7 待 planner 定）：每完成一个导出文件触发一次（$1=文件路径，
  $2=输出目录）vs 批次终了触发一次（$1=目录）。推荐前者（dt `darktable|exported` tag
  的逐图语义对齐）+ 队列层去抖可后补。
- **Finder 动作**：`NSWorkspace.shared.activateFileViewerSelecting([url])`（单文件选高亮
  / 目录直接开）——标准 API，无沙盒/权限边角。动作在**导出 job 完成回调**（MainActor
  hop 经 ExportState）触发，失败 job 不触发。

## 7. 测试策略（执行轮；golden + 队列 + 只记性能）

1. **每格式 golden round-trip**（LightamerTests，Core 级可测）：合成量化 buffer（梯度
   fixture 先例 `.work/plans/02-04/probe-tiff.swift` + `YiyinE2ETests.swift:301-330` 的
   float32 CGImage 构造）→ encode → `CGImageSource` 解码断言：
   - 像素：8/16-bit 逐位（有损格式 JPEG/HEIC/AVIF/WebP-lossy 用容差带 + 已知点：中性
     灰、纯色四角、0.5 线性→sRGB 187-188 显示值）；32f TIFF 数值恒等；WebP-lossless
     逐位。
   - ICC：`kCGImagePropertyProfileName`/CGImage colorspace model == 目标。
   - 元数据：EXIF 指定 tag round-trip、DPI、XMP packet 存在性（§1.3 事实 1 的逐格式
     断言落此处）。
   - 奇数尺寸 + 10-bit HEIC/12-bit AVIF 探针用例（§1.2 标注项）。
2. **COLOR-2 已知点复用**：出口腿 neutrality（灰恒灰）+ sRGB encode 已知值断言并入
   §7-1 已知点集；P3/Rec2020/ProPhoto 目标各跑中性 + 饱和角点。
3. **队列单测**（毫秒级，leg 注入）：enqueue→done 顺序、`cancel(pending)`、
   `cancel(inFlight)`（结果弃、无落盘）、`cancelAll`+generation、retry 重入队尾、
   progress `(done,total)` 快照、concurrency=1 断言（inFlight 上限）、失败不毒化队列。
4. **yiyin 导出 E2E**：同 recipe 双尺寸归一化相等（§5）+ 双开/双关 4 态（照 08-3 T4）+
   有印框导出的全链 round-trip（渲染→出口→编码→解码）。
5. **性能只记不设门**（Phase 15 清算——`.work/11/perf.md` 惯例）：单图全幅导出耗时
   分段（render/exit/encode per 格式）、100MP 内存峰值、模糊腿 Release 复测（08-3
   遗留 #5，08-3-SUMMARY.md:70）。

## 8. Open Questions for Planning（给 planner 的分解面）

### OQ-11-1 任务波次建议（依赖序）

- **W1（纯模型，无 GPU/网络）**：T1 `ExportRecipe`/`ExportVariant` 模型 + 命名/冲突
  递增纯函数（D-11-CONTEXT-3/4 的 Codable 值类型 + 纯函数测试）+ `Project.swift` SPM
  依赖接线（§2.3，fetch 失败走 px 代理一次性）。
- **W2（编码平面，可与 W1 并行启动）**：T2 出口腿（`renderToEncodedBitmap` +
  `ExportQuantizer`）+ T3 五原生格式 `ExportEncoder` 协议 + 实现 + golden（§7-1）；
  T4 WebP 编码器 + golden（依赖 T1 的包）。
- **W3（渲染腿）**：T5 `PixelPipe` .export 双 stub 激活 + 无头 `ExportRenderer`
  （disk sidecar→instances 组装照 `SessionBatchApplier.composeSegment` 读盘法 + gamma
  剔除 + yiyin 无头注入）+ 出口/编码串联 E2E。
- **W4（队列 + UI）**：T6 `ExportQueue` actor（§4 契约全套 + 单测）；T7 导出面板 UI
  （recipe 内联编辑 + 队列状态/进度/取消/重试 + `ExportState` 桥——现 stub
  ExportState.swift:13-18 扩展）。
- **W5（收口）**：T8 EXP-08 post actions + T9 golden 补全（10/12-bit/XMP 探针）+
  perf 记录 + 验收材料。

### OQ-11-2 导出链 colorout 去留（唯一真设计分叉）

- **推荐：colorout 保留、target 覆写为导出目标（线性变体）**——yiyin 与预览共享
  「colorout→borders→watermark」的显示域语义（§5 色彩注记），且 colorout 的 ColorSync
  精确路径本就为任意 profile 预留（`OutputProfile` enum 需 additive 扩 AdobeRGB/
  ProPhoto/Rec2020 或引入 profile-override 直通——D-COL3 插座即此处）。
- 备选：colorout 也剔除（字面最简，出口全权）——yiyin 落入管线域 primaries，与预览
  存在系统性 primaries 差（中性无感、饱和 logo 有感）。
- 决策权 planner；无论哪支，**gamma 必剔**（§3.1）。

### OQ-11-3 队列作用域

session 级（session 切换 cancelAll + 重建，9-3 同款）vs app 级（跨 session 续跑）。
推荐 **session 级**（实例快照绑定 session root/registry；跨 session 续跑要 journal，
与 D-11-CONTEXT-8 冲突）。

### OQ-11-4 失败呈现粒度

per-job error 面板（推荐：job 级 `failed(AppError)` + 面板行内重试）vs 批级 toast。
影响 ExportState/UI 接口形状。

### OQ-11-5 WebP 元数据 v1 口径

无内嵌元数据 + 文档注记（推荐，§1.3-2）vs 执行轮先探 Swift-WebP mux 面（若露出
WebPMux 即零成本升级 ICC/EXIF/XMP chunk）。

### OQ-11-6 sizing 模型归属

`variant.sizing = YiyinExportSettings` 直接复用（推荐，D-08-CONTEXT-7 正主）vs 新立
`ExportSizing` 类型再桥接。前者少一个平行模型，后者为 Phase 12 预设面解耦 yiyin 命名。

### OQ-11-7 post-action 触发粒度

逐文件（推荐）vs 批次终了（§6）。

### OQ-11-8 编辑让位开关位

v1 只留 `yieldsToEditor` 接口位不实现（§4.4）vs 首版就接「编辑帧活跃→泵暂停」。
推荐前者（Phase 15 实测驱动）。

### 风险表

| # | 风险 | 缓解/缝 |
|---|---|---|
| R1 | HEIC 10-bit / AVIF 12-bit 编码路径实测不达 | §7-1 探针先行；失败降级文档化位深上限；`AVIFEncoder` 协议缝（D-11-CONTEXT-1） |
| R2 | Swift-WebP strict concurrency / lossless knob 面 | 圈进 actor 单路径；执行轮验证；兜底 = vendored libwebp shim（§2.1） |
| R3 | SPM 首次 fetch 网络失败（USB 卷 + 直连） | px --up 代理一次性 fetch；缓存后离线（§2.3） |
| R4 | 100MP 32f TIFF 全链内存/磁盘峰值 | 并发 1 红线（D-11-CONTEXT-2）；perf 只记；长宽裁剪警告 UI |
| R5 | XMP packet 逐格式写入差异 | §1.3 事实 1；逐格式 golden 断言；失败格式文档化 |
| R6 | yiyin 模糊腿全幅 Release 成本（08-3 遗留） | §7-5 记录；模糊量上限 UI 已有 |
| R7 | TaskLocal 队列路由与 nonisolated 组合意外 | 备选 queue: 参数透传（§4.3），改动面可控 |
| R8 | TaskLocal 出口腿读回栅栏挂错队列（用主队列 fence → 假绿/花屏） | §3.2/§4.3 纪律：导出腿 CIContextPool 实例化时传 exportCommandQueue；单测含 fence 断言（照 GUI-22 测法） |

</research>

## Sources

### Lightamer 代码（现码，file:line 已核）

- `LightamerCore/Sources/Pipe/PipeResolution.swift:20-67`（四管线 + export 无缓存）
- `LightamerCore/Sources/Pipe/PixelPipe.swift:475-476,644-645`（export typed stub）、
  `:196-222`（gamma 尾格式策略）
- `LightamerCore/Sources/Pipe/PipeCacheKey.swift:37`（pipeType 命名空间）
- `LightamerCore/Sources/Metal/MetalContext.swift:12,48-49`（D-15 导出队列接口位）、
  `:128-209`（dispatch2D/dispatch2DTexture/makeEncoder）、`:426-427`（唯一取队列点）
- `LightamerCore/Sources/Metal/CIContextPool.swift:43-150`（CIContext 选项/GUI-22 memo/
  memoByteCap）、`:341-444`（bitmap+replace 腿）、`:460-521`（convertTexture：fence +
  per-render colorSpace 先例）
- `LightamerCore/Sources/Pipe/Terminal/ColorOutModule.swift:33-72`（两常量矩阵族 +
  ColorSync 精确路径 + OutputProfile/D-COL3 插座）
- `LightamerCore/Sources/Pipe/Terminal/GammaModule.swift:14-17`（sRGB TRC + 唯一 clamp）
- `LightamerCore/Sources/Foundation/WorkingSpace.swift:22-23`（linear Rec2020）
- `LightamerCore/Sources/Foundation/YiyinExportSettings.swift:18-108`（sizing/DPI/校验/
  targetSize 永不放大）
- `LightamerCore/Sources/Session/SessionBatchApplier.swift:5-29,158-222`（三段批量 +
  磁盘 sidecar 读法）
- `LightamerCore/Sources/Session/SessionThumbnailProvider.swift:107-310`（9-3 队列骨架
  全件：generation/cancelAll/pump/execute/leg 注入/idle）
- `App/Sources/Lightamer/Session/SessionLayout.swift:64-74`（outputDirectory 移交常量）
- `App/Sources/Lightamer/State/PipeCoordinator.swift:1401-1447`（renderCurrentChain）、
  `:1587-1626`（injectYiyinRunContext 生产注入）
- `App/Sources/Lightamer/State/ExportState.swift:13-18`（export 状态 stub）
- `Tests/LightamerTests/YiyinE2ETests.swift:260-330`（无头 yiyin 注入 + fence 读回 +
  float32 CGImage 构造）
- `Project.swift`（D-03 Core 零依赖、LSItemContentTypes webp 在册、非沙盒文件授权）

### 平台 / SDK（本机实证）

- UTI 探针（2026-09-26 本机 swift 脚本）：`public.avif` ✅ / WebP ❌ / HEIC/TIFF/PNG/JPEG ✅
- ImageIO SDK 头（xcrun SDK）：`kCGImageDestinationLossyCompressionQuality`(10.4+)、
  `kCGImageDestinationMetadata`/`MergeMetadata`(10.8+，Merge 不写 XMP packet)、
  `kCGImageDestinationEncodeBasePixelFormatRequest`(macOS 16+)、
  `kCGImageDestinationImageMaxPixelSize`(10.10+)、`kCGImageDestinationEncodeToSDR`(macOS 15+)
- Metal SDK 头：`MTLCommandQueue.h` 无 priority API；`MTLIOPriority` 仅
  `MTLIOCommandQueue.h:20`（IO 队列专属）
- ainame/Swift-WebP README（glm-webReader 2026-09-26）：MIT / toolchain 6.2.3 /
  language mode 6 / libwebp 1.5.0+（libwebp-Xcode）/ macOS 11+ / WebPEncoder+Config

### Darktable 参考（只读，语义对标）

- `src/imageio/imageio.c:1045-1140`（`dt_imageio_export_with_flags`：format `levels()` 位深
  驱动 export pipe + icc_type/filename/intent + copy_metadata 面）
- `src/imageio/imageio.c:1345-1382`（export pipe `process_no_gamma`——导出无 gamma 的
  同构决策）、`:1403-1460`（8/16-bit `roundf(CLAMP(v*0xff/0xffff))` 量化同款）
- `src/control/jobs/control_jobs.c`（`_control_export_job_run`：串行循环 + `_job_cancelled`
  逐图闸 + num/total 进度 + store 失败即 cancel——无自动重试的先例）

### 项目文档

- `.planning/phases/11-export-pipeline/11-CONTEXT.md`（D-11-CONTEXT-1..8）
- `.planning/ROADMAP.md:181-193`（Phase 11 Goal/SC#1-5/Notes）、`:256-267`（Phase 14
  MCP 面对导出/渲染出口的消费位意识：`export_image`/`render_preview` 复用）
- `.planning/REQUIREMENTS.md:201-208`（EXP-01..08）
- `.planning/research/STACK.md`（Export Format Encoder Matrix + What NOT to Use）
- `.planning/phases/08-yiyin-border-watermark/08-3-SUMMARY.md:26-27,70`（版式分辨率无关
  + 模糊腿遗留）
