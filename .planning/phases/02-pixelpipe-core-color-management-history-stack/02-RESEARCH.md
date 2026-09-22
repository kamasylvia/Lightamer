# Phase 2 Research: Pixelpipe Core, Color Management & History Stack

**Researched:** 2026-09-18
**Confidence 汇总：** Darktable 模式映射 = High（源码逐行核过）；Swift API 设计 = High/Med（标注处需 Phase 2 内 spike 验证）；CIRAW 色彩行为 = Med（本机实测过渲染路径，输出语义推断自 Phase 1 证据）。

---

## Summary

Phase 2 是承重架构阶段，六个工作流彼此咬合。核心结论：

1. **pixelpipe 递归 + 缓存**：Darktable 的快路径本质是「**上游链 hash + ROI + 管线态 → 定位 cacheline**」，不是 per-module 独立缓存表。Swift 版可用一个**字节预算 LRU 纹理缓存 actor**（key = 上游 hash 元组）完整复刻其语义，且比 Darktable 更简洁——不需要 `cache_obsolete_order` 显式失效（hash 变化天然失效上游相同/下游不同的行）。100MP float32 单平面 1.55GB 决定：**交互主力是 PREVIEW 管线（2560px ≈ 70MB/平面），FULL 管线 on-demand 且只保留 ping-pong 双缓冲**（spike-b 证据：<1ms 帧余量 + 平面乘法爆预算）。
2. **多分辨率**：四条管线共享模块链与缓存基础设施，scale 的施加点在**管线入口**（CIRAW CIImage 直接渲染到目标分辨率的输入平面），不在模块内——pass-through 时代模块对 scale 完全无感，协议钩子（`modifyROIOut/In`）已就位但默认恒等。
3. **终端三件套**：与 Darktable 语义有一处**根本差异必须写进 ARCHITECTURE**——CIRAW 是「已显影」输出（demosaic+WB+相机矩阵+基线曝光+显示 gamma 全部内部完成），Lightamer 的 colorin 不是 Darktable 的 camera-RGB→working 矩阵转换，而是**恒等/归一化**；真正的显示变换在 colorout（3×3 gamut 矩阵）+ gamma（TRC 编码 → `.bgra8Unorm`）。Metal 快路径（Display P3/sRGB 常量矩阵）+ CIContext/ColorSync 精确路径兜底，两者互相验证。
4. **history stack**：Swift 侧需要 `ModuleInstance`（运行态容器，绕开 `any IOPModule` existential 不可形成）+ `HistoryStack`（数组 + position 指针）+ `effectiveInstances()`（按 (op, multi_priority) 去重取最新，v50 排序——这是 Darktable `GROUP BY operation, multi_priority MAX(num)` 的直译）。History hash 用**显式稳定哈希（FNV-1a 64）**而非 Swift `Hasher`（后者每次启动换种子，不能做 sidecar 漂移检测）。
5. **issue #1（D-X1）**：删除 `EditorAreaView` 的 `.task(id:)` 冗余触发，`load()` 的 decodeTask 是唯一渲染发起者；CIContext render-to-texture 异常复查作为同批 spike（spike-b 证据：首渲写空 6/6、第二次正常 → **warm-up 一次**大概率可启用直渲路径，省掉 PREVIEW 尺寸的 CPU 往返）。
6. **clearCaches**：三层 API（`PipeCache.clearCaches(keeping:)` / `CIContextPool.clearCaches()` / `MetalContext` PSO 不动），触发点 load 入口 + 60s 兜底 timer（D-C1/D-C2），保留策略按 imageID 分代。

**给 planner 的 5-8 个 plan 切分建议**（末尾 Open Questions 前给出）。

---

## Implementation Approaches

### 1. Pixelpipe 递归架构 + per-module per-ROI 缓存（FOUND-04）

#### 1.1 Darktable 模式（源码核验）

- **递归形状**（`pixelpipe_hb.c:1838` `_dev_pixelpipe_process_rec`）：从链尾向链头递归（`modules` 列表倒序遍历，`g_list_previous(modules)`，pos 递减）。禁用模块直接跳过（`pixelpipe_hb.c:1875-1881`，`_skip_piece_on_tags`）递归到上一级。递归返回后**本模块**在正确的 iop 顺序位置执行。
- **缓存命中快路径**（`pixelpipe_hb.c:1892-1921`，即 ROADMAP 标注的 L1838/1893）：
  ```c
  dt_hash_t hash = dt_dev_pixelpipe_cache_hash(roi_out, pipe, pos);   // :1893
  if (cache_available) { dt_dev_pixelpipe_cache_get(...); return FALSE; }  // :1904-1921 命中即返回，上游零计算
  ```
- **hash 构成**（`pixelpipe_cache.c:99-172`）：
  - `_dev_pixelpipe_cache_basichash`（:99-155）= `dt_hash(imgid, pipe->type, want_detail_mask)` + 4 个 profile info + **遍历 position 之前所有启用 piece 的 `piece->hash`**（piece->hash = 该模块 params + enabled，`pixelpipe_hb.h:61`）。
  - `dt_dev_pixelpipe_cache_hash`（:160-172）= basichash + `roi`（x/y/width/height/**scale**）+ detail-mask hash。
  - **注意**：position 是管线内位置，不是 iop_order（`pixelpipe_cache.c:113` 注释明说）。
- **缓存存储**（`pixelpipe_cache.c:174-195, 291-354`）：定长 cacheline 池（`DT_PIPECACHE_MIN = 2`，`pixelpipe_hb.h:32`），命中/未命中都做老化（`used[k]++`），命中行置 `used = -entries`（「important」，`_get_by_hash` :283）；淘汰取最老行，容量按字节（`memlimit`，`pixelpipe_hb.h:363-366`）。hash 命中但 size 不符 = 判脏并置 `DT_INVALID_HASH`（:261-271）。
- **管线入口的 scale 施加**（`pixelpipe_hb.c:1930-1999`）：`roi_out->scale == 1.0` 且满幅时直接引用 `pipe->input`；否则按 scale **重采样 pipe->input** 后作为第 0 级输入——即 Darktable 也是「scale 在入口施加」，模块内只看 `roi.scale`。
- **失效机制**：`pipe->changed` 事件（`pixelpipe_hb.h:83-91`：TOP_CHANGED/REMOVE/SYNCH/ZOOMED）+ `cache_obsolete_order`（`pixelpipe_hb.h:165-166`：置一个 iop_order 使 >= 该序的 cacheline 下轮失效）。**Swift 版不需要后者**——上游 hash 变化自动使下游行 key 不匹配。
- **同步语义**（`pixelpipe_hb.h:400-404`）：`create_nodes`（全量重建）/ `synch_all`（拷贝顶部新参数）/ `synch_top`（history pop）——history → pipe pieces 的三档同步粒度。

#### 1.2 Swift 设计

**缓存 key 与 hash（D-H4 联动）**——先定稳定哈希原语：

```swift
/// 稳定 64-bit FNV-1a（跨启动稳定；Swift Hasher 每进程换种子，禁用于 sidecar/缓存 key）。
/// 零依赖，镜像 Darktable dt_hash 的角色（pixelpipe_cache.c:120）。
public enum StableHash {
    public static func combine(_ seed: UInt64 = 0xcbf29ce484222325, _ bytes: UnsafeRawBufferPointer) -> UInt64
    public static func hash(_ data: some DataProtocol) -> UInt64
}
```

```swift
/// 一条缓存行的 key —— pixelpipe_cache.c:160-172 的 Swift 直译。
internal struct PipeCacheKey: Hashable {
    let imageID: UUID              // imgid（跨图防串）
    let pipeType: PipeResolution   // FULL/PREVIEW/THUMBNAIL/EXPORT（pixelpipe.h:41-62）
    let position: Int              // 链内位置（0 = 输入平面），非 iop_order
    let upstreamHash: UInt64       // Σ FNV(piece.paramsHash for enabled pieces < position)，含 decodeParamsHash
    let roi: ROI                   // 含 scale（ Equatable 已就位，Phase 1 ROI.swift）
}
```

`upstreamHash` 的关键性质：模块 m 的 params 变化 → 所有 `position >= m` 的 key 的 upstreamHash 全变（miss → 重算），`< m` 的全不变（hit）——**SC#2 的失效语义由 hash 免费获得**，不需要 `cache_obsolete_order`。

**缓存本体**（actor，字节预算 LRU——镜像 MetalContext 的 LRU 模式但按字节）：

```swift
/// per-module per-ROI 纹理缓存。actor 隔离（D-33 同款）；纹理写入后只读
/// （usage = .shaderRead），跨 actor 交接走 @unchecked Sendable 包装
/// （CIContextPool.RenderedTexture 同款契约，Phase 1 已定模式）。
internal actor PipeCache {
    init(byteBudget: Int = PipeCache.defaultBudget)   // 3 GB（D-C1），常量可调
    func texture(for key: PipeCacheKey, byteCount: Int,
                 make: @Sendable () async throws -> any MTLTexture) async throws
                 -> CachedPlane    // 命中：LRU touch + signpost "cache HIT"（SC#2 验证钩子）；未命中：make → 存储
    func invalidate(imageID: UUID)                       // 换图清理（D-C1 keep 语义见 §6）
    func clearCaches(keeping: KeepingPolicy) async       // D-C1
    var totalBytes: Int { get }
    struct CachedPlane: @unchecked Sendable { let texture: any MTLTexture; let byteCount: Int; let lastHit: ContinuousClock.Instant }
}
```

- 淘汰策略：LRU（`lastHit` 最老先逐）；**行内 size 不符的脏 key 处理直接省略**——Swift 字典 key 相等即行存在，无 Darktable 定长池的 size 冲突问题（`pixelpipe_cache.c:261-271` 整段不需要）。
- 内存记账：`totalBytes` 累加每个 plane 的 `width×height×bytesPerPixel`，超 3GB 触发淘汰到阈值以下（比如降到 2GB 再停，防抖）。

**PixelPipe 递归主体**（`PixelPipe.swift` 扩展，internal 不变；`RenderPipeline` 公共桥换形状）：

```swift
internal final class PixelPipe {
    let resolution: PipeResolution
    let cache: PipeCache
    var pieces: [Piece]                     // 每模块实例一条：module + IOPiece（Phase 1 已有）
    var decodeParamsHash: UInt64            // §1.3
    // 核心递归 —— pixelpipe_hb.c:1838 直译；Swift 用 async 迭代/递归均可：
    func processRec(position: Int, roiOut: ROI) async throws -> Plane {
        // 1) 跳过 disabled（:1875-1881）
        // 2) upstreamHash = 已随 position 递推（增量 combine，O(1)/级）
        // 3) cache.texture(for: key(position, roiOut)) { 上游 processRec(position-1, roiIn) → piece.process }（:1892-1921）
    }
}
```

**ROI 流转**：pass-through 时代 `modifyROIOut/In` 全部默认恒等（协议已定，`IOPModule.swift:62-67`）——`roiIn = roiOut` 逐级下传；全幅 ROI（`x=0,y=0,full,scale`）即 SC#4 的初始形态。**协议钩子现在就位，Phase 4 crop/lens 才真正行使**——planner 无需在本阶段为 ROI 写任何新代码，只需保证 processRec 把 roiIn 递给上游、把 roiOut 给缓存 key。

#### 1.3 解码参数进 hash（gotcha）

Phase 3 的 WB/exposure 若走「改 CIRAW 参数 → 重解码」路径，输入平面本身就变。**第一天就把 `decodeParamsHash = FNV(decoderVersionUsed, rawTech 相关项, 未来 decode 侧参数)` 并进 position-0 的 upstreamHash**（`DecodedImage.decoderVersionUsed` 已有字段，Phase 1 预留的 sidecar 戳直接复用）。否则 Phase 3 会出现「改 WB 不生效」的静默缓存陈旧。

#### 1.4 process 签名：Buffer → Texture（建议的协议破坏性变更）

现状矛盾：`IOPModule.process` 用 `MTLBuffer`（`IOPModule.swift:73-80`），而 Phase 1 渲染产物/缓存行是 `MTLTexture`（`CIContextPool`），PassthroughModule 靠「buffer↔texture staging」硬桥。**建议 Phase 2 把 process 签名改为 `MTLTexture` 进出**：纹理是管线的自然货币（`dispatch2DTexture` 已有；缓存、displayTexture、PREVIEW/FULL 全是纹理）；Buffer 只在 Phase 3+ raw Bayer 路径需要（CIRAW 已 demosaic，Lightamer 管线里不出现 Bayer float buffer）。影响面 = `IOPModule` 协议 + `PassthroughModule` + 测试——正是本阶段该锁的公共契约（API.md 同批更新）。

Confidence：递归/缓存设计 **High**（Darktable 逐行核过 + Phase 1 底座齐备）；process 签名变更为**建议项**，planner 拍板。

---

### 2. 多分辨率管线（ROADMAP SC#4 + D-C3）

#### 2.1 管线实例与生命周期

```swift
public enum PipeResolution: String, Codable, Sendable {
    case preview      // 交互主力，always-current
    case thumbnail    // 固定 360px
    case full         // on-demand：100% 查看 / 导出前置
    case export       // on-demand，无缓存（pixelpipe_hb.h:346-355：export/thumbnail 管线 Darktable 本就不建 history cache）
}
```

| 管线 | 分辨率 | 创建时机 | 存活 | 失效耦合 |
|---|---|---|---|---|
| PREVIEW | `min(drawableSize×2, 2560)` 长边，量化 360px 档（D-C3 梯子：2560/2200/1840/1480/1120/760/360） | load 成功即建并渲染（D-X1 统一路径的产物） | 常驻，参数变化即重渲 | params 变 → 重渲；窗口跨档 → 换 roi 重渲 |
| THUMBNAIL | 360px | 首次需要时（Phase 9 浏览器消费） | 渲染一次驻缓存 | params 变只置 dirty，**下次取用才重渲** |
| FULL | scale 1.0 全幅（本阶段不做 zoom ROI 平移，仅脚手架） | 100% 查看/导出请求时 | **短命**：用完即可逐出 FULL 输入平面（1.55GB@100MP） | params 变置 dirty；永不主动渲染 |
| EXPORT | 目标尺寸 | Phase 11 | 不驻留 | 无缓存，跑完即弃 |

共享的部分：模块链定义（`pieces` 的模块序列同源）、`PipeCache`（key 里已有 `pipeType` 天然分桶）、history → effectiveInstances 的同步逻辑。每管线一个 `PixelPipe` 实例（pieces 是 per-pipe 运行态，Darktable 同构）。

**失效耦合实现**：一个 `PipeCoordinator`（App 侧，EditorState 持有）订阅 history 变化 → PREVIEW 立即重渲、THUMBNAIL/FULL 置 `dirtyResolution` 集合。THUMBNAIL 的「下次取用才重渲」由 `PipeCache.texture(for:make:)` 天然保证——dirty 后把该管线的 param-generation 版本号 +1，旧 key 自然 miss，新 key 惰性构建。

#### 2.2 scale 施加点（唯一正确位置 = 管线入口）

PREVIEW 的输入平面 = CIRAW `CIImage` 经 `CIContextPool` **直接渲染到 2560px**（`CIImage.transformed(by: scale)` 后 `render(toBitmap:)`），而非先渲 100MP 再缩。这正是 Darktable 入口重采样（`pixelpipe_hb.c:1930-1999`）的镜像；区别是 CI 是 lazy 的，可能内部仍全幅 demosaic——**解码耗时是否随 scale 下降属未知，Phase 2 用 signpost 实测**（spike-b 全幅 0.35-0.85s 是上界，可接受的一次性成本）。模块收到的 `roi.scale` 在 pass-through 时代不参与任何计算——`modifyROIOut/In` 钩子挂空实现，Phase 4 才激活。

#### 2.3 量化防抖（D-C3）

窗口 resize 时目标长边落在同档内 → 不换 roi 不重渲；跨档 → 以新档重渲 PREVIEW（旧档平面留在缓存，抖动回跨档时 hit 秒回）。梯子实现为一个纯函数 `func previewBucket(forLongEdge: Int) -> Int`，单测覆盖。

---

### 3. 终端三件套 colorin/colorout/gamma（COLOR-01 + D-COL1..4）

#### 3.1 先核事实：CIRAW 输出是什么（决定 colorin 的形态）

- **Phase 1 已实证**（`01-RESEARCH.md` Open Question #7 + `CIContextPool` 现行为）：CIRAW 输出「displayable as-is（已按屏幕显影）」；Lightamer 用 `workingColorSpace/outputColorSpace = linear Rec2020` 的 `CIContext` 把它转码成 **linear Rec2020 float32 值**。即：**像素值 = CIRAW 显影结果（含相机矩阵、WB、基线曝光、tone 曲线）的线性 Rec2020 编码**。
- 因此 **Lightamer 的 colorin ≠ Darktable 的 colorin**：Darktable colorin（`colorin.c:1184-1243`）做 camera-RGB→Lab/working 的矩阵/LCMS 变换（因为它的输入是 rawprepare 之后的传感器域数据）；Lightamer 的输入**已经是 working space 值**。Lightamer colorin 的职责收缩为：① 确认/断言输入在 working space（debug assert）；② 未来的 DCP/输入 profile 参数位（COLOR-04，`kCIRAW...` 不接受外部 DCP——STACK.md 边界表）；③ 对非 RAW（sRGB JPEG）经 CIContext 转码后同样是「线性化完成」——colorin 同样恒等。**v50 表里 colorin=28.0 保留位次，实现为（近乎）no-op 的终端成员**，语义注释写明与 Darktable 的差异（这是移植性文档的关键点，Phase 3 移植 iop 时所有人都需要知道「管线输入是显影域，不是场景线性域」）。
- ⚠ 影响 Phase 3+：scene-referred iop（filmicrgb）作用于「显影域 + 基线曝光已烘入」的数据，与 Darktable 作用于真场景线性数据**数学上不等价**——这不是 Phase 2 能解决的（PROJECT.md 锁定 CIRAW=decoder），但 pipeline 文档必须现在写明，Phase 3 移植 filmic 时按「输入近似」校准 golden 容差。

#### 3.2 colorout（`iopOrder = 70.0`）：gamut 矩阵

Darktable 形态（`colorout.c:404-486, 521-546`）：Lab→linear-RGB 3×3 矩阵（cmatrix fastpath）+ 可选 TRC LUT；非矩阵 profile 走 lcms2 `cmsDoTransform`。输出 profile 选择在 `commit_params`（:548-617）：export 用覆盖 profile、thumb 用 mipmap 色彩空间、屏幕用 display profile。

Lightamer Phase 2 形态——**双路径**：

```swift
/// linear Rec2020 → 显示原色域的线性 RGB。Metal 快路径为常量矩阵；
/// CIContext/ColorSync 路径为任意 ICC 的精确基准。
final class ColorOutModule: IOPModule {
    struct Params: Codable & Hashable {
        var outputProfile: OutputProfile = .display   // D-COL3 参数位：Phase 13 注入打印机 profile
        var intent: RenderingIntent = .relativeColorimetric
    }
    enum OutputProfile: String, Codable { case display, sRGB, displayP3, /* Phase 13+: adobeRGB, proPhoto, rec2020 */ }
}
```

- **Metal 快路径**：`colorout_display` kernel，常数矩阵 = **linear Rec2020 → Display P3 线性**（两空间标准原色/白点 D65 预计算，编译期常量，非运行时 ICC 解析）。绝大多数 Mac 内置屏 `NSScreen.colorSpace` 即 Display P3（XDR/普通屏皆是），该常量覆盖主场景。
- **ColorSync 精确路径**（兜底 + 验证基准）：外置屏/非标准 profile 时，`CIContext.render(toBitmap:, format: RGBA8, colorSpace: screen.colorSpace.cgColorSpace)` ——ColorSync 全 ICC 精确变换（矩阵+TRC+intent 一步完成）。成本 = PREVIEW 尺寸 CPU 往返（2560px float32 读 70MB + 写 17MB + 纹理回传，量级 10-30ms）——**一次性换屏时可接受，不做拖拽热路径**；拖拽热路径用快路径。
- 检测逻辑：`screen.colorSpace.name` 匹配已知 P3/sRGB 命名表 → 快路径；否则 ColorSync 路径。置信 **Med**（命名匹配的健壮性需真机外接屏验证）。

#### 3.3 gamma（`iopOrder = 78.0`，管尾）：TRC 编码

Darktable gamma 模块（`gamma.c`）：linear sRGB→gamma sRGB 逐像素 + 打包 8-bit，v50 链最后一个。Lightamer 同构：

- `gamma` kernel：sRGB 分段 TRC（线性段 ≤0.04045 / 幂段 2.4）逐通道编码，**写 `.bgra8Unorm`**（drawable 非 `_srgb` 变体，软件编码正确性由我们负责；D-COL4 锁定格式不变，Phase 8 EDR 才换）。>1.0 的值 clamp（EDR headroom 是 Phase 8 的事，管线内部 float 值不截断）。
- **管尾形态建议**：PREVIEW 管线缓存到 **colorout 输出**（float32 linear-P3/sRGB 平面，可复用），gamma 作为廉价的「display handoff」pass：`colorout 平面 → gamma kernel → bgra8Unorm displayTexture`。窗口 resize / 换屏只重跑 gamma（≤2560px，~1ms），上游缓存全 hit。SC#2 的缓存快路径在 gamma 之前的模块上全部成立。

#### 3.4 显示 profile 跟随（D-COL2）

`EditorPipelineCoordinator` 监听 `NSWindow.didChangeScreen` + `NSApplication.didChangeScreenParametersNotification` → 读 `window.screen?.colorSpace ?? NSScreen.main.colorSpace` → 色彩空间名变化 → 只失效 colorout/gamma 段（缓存 key 已含一个 `displayProfileID` 进 `upstreamHash` 终端段——放进 colorout 之后各 position 的 key，上游模块不受影响）。多显示器跟随窗口所在屏，符合 D-COL2。

#### 3.5 D-COL1 验收的正确打开方式（重要 nuance）

「灰块三通道差 <2/255」是**中性度**判据——它对「逐通道相同的 tone 曲线误差不敏感」（任何单调 TRC 双重施加都不破坏中性），**抓不住** TRC 错配/色域矩阵错配。因此 golden harness 需要**两个判据**（详见 Validation Architecture）：
1. 中性度（D-COL1 字面）：ColorChecker 灰块 |R−G|、|G−B| < 2/255 —— 抓通道矩阵/白平衡级错误；
2. **交叉一致性**：同一图 pipe 全链输出 vs `CIContext` 直渲 sRGB 8-bit（ColorSync 基准）逐像素 < 2/255 —— 抓 TRC/色域错配（快路径 vs ColorSync 互相验证）。
两判据合起来才等价于 SC#1「correct color」。**不是 DECISION REVIEW**——D-COL1 可行，但 planner 必须把判据 2 一起写进验收，否则测试会漏报。

---

### 4. History stack + sidecar（HIST-01..04 + D-H1..H4 + D-S1..S3）

#### 4.1 数据模型（绕开 `any IOPModule` existential）

`associatedtype Params` 使 `any IOPModule` 无法形成（Phase 1 已注记）——history 侧用**独立运行态容器**：

```swift
/// 管线里的一个模块实例 —— Darktable dt_iop_module_t 实例侧 + dt_dev_history_item_t
/// （develop.h:34-49）的 Swift 合成。op/multi_priority/multi_name/iop_order = 身份元组。
public struct ModuleInstance: Sendable {
    public let id: UUID                      // 实例稳定 id（NDE-1：蒙版/历史按 UUID 引用，不按序数）
    public let opName: String                // Darktable op 字符串；v50 表 key
    public let multiPriority: Int            // 同 op 多实例序（Darktable multi_instance）
    public var multiName: String             // 用户可见实例名
    public var iopOrder: Float               // 实例的 v50 位次（可被自定义排序改写，Phase 6+）
    public var version: Int                  // 模块参数 schema 版本（modversion 模拟）
    public var enabled: Bool
    public var paramsData: Data              // Params 的 JSON 编码（权威载荷）
    public var paramsHash: UInt64            // FNV(paramsData)——缓存 key 与 history hash 的原子
    public func params<M: IOPModule>(of type: M.Type) throws -> M.Params   // 类型化读取
    public mutating func setParams<M: IOPModule>(_ p: M.Params, as type: M.Type) throws
}
```

```swift
/// HIST-01/02：有序 history + position 指针（undo/redo/跳转任意点）。
public struct HistoryStack: Sendable {
    public private(set) var items: [HistoryItem]     // D-H2：无上限
    public private(set) var position: Int            // -1 = pristine（= Darktable history_end）
    public struct HistoryItem: Sendable, Identifiable {
        public let id: UUID
        public let instanceID: UUID                  // 引用 ModuleInstance（或内联快照，见下）
        public let label: String
        public let timestamp: Date
    }
    public mutating func commit(_ item: HistoryItem)         // 截断 position 之后 + 追加（D-H1 拖动提交）
    @discardableResult public mutating func undo() -> HistoryItem?
    @discardableResult public mutating func redo() -> HistoryItem?
    public mutating func jump(to index: Int)
    /// history → 管线态：按 (opName, multiPriority) 去重取 position 前最新一条，
    /// 按 iopOrder 排序 —— history.c:1600-1607「GROUP BY operation, multi_priority MAX(num) ORDER BY num」直译。
    public func effectiveInstances() -> [ModuleInstance]
}
```

设计取舍：`HistoryItem` **内联整份 ModuleInstance 快照**（而非仅 instanceID 引用）——undo/跳转要恢复**当时的参数**，内联快照让 `effectiveInstances()` 纯函数化，也直接映射 sidecar 的 `items[]`（每条自带 params）。去重规则让中间步骤自动被最新参数覆盖（与 Darktable 行为一致：管线的最终态只看每实例最新参数）。

**darg-end 语义（D-H1）**：Phase 2 无滑块，但把提交 API 定形——`EditingSession.beginContinuousEdit() → 拖动中 setLiveParams(不进 history, 只驱动 PREVIEW 重渲) → commitContinuousEdit() 生成一条 HistoryItem`。Phase 3 首个滑块模块直接使用。

#### 4.2 History hash（D-H4 + HIST-04）

```swift
public enum HistoryHash {
    /// 对 effectiveInstances()（启用模块）逐个 FNV(opName ‖ multiPriority ‖ paramsData)，
    /// 按 v50 顺序组合 —— history.c:1571-1665 的结构直译（MD5→FNV-1a64；只算 enabled；
    /// 含 module-order = v50 位次序列；decodeParamsHash 一并混入，§1.3）。
    public static func hash(instances: [ModuleInstance], decodeParamsHash: UInt64) -> UInt64
}
```

用途：(a) 每模块 `paramsHash` 已进管线缓存 key（§1.2）；(b) 整链 hash 写进 sidecar，重载时重算比对 = **漂移检测**（SC#5）。同二进制内 JSON 编码确定性（synthesized Codable 按属性声明序输出）保证重算一致；跨版本漂移属预期行为（schemaVersion 承担）。

#### 4.3 Sidecar（D-S1/S2/S3）

文件：`<原文件完整名>.lra`（如 `DSC09991.ARW.lra`），与原片同目录；完全忽略 `.xmp`。

```jsonc
{
  "schemaVersion": 1,                       // D-S1 演进预留（第一天就写）
  "appVersion": "0.2.0",
  "imageID": "UUID",                        // 跨会话稳定身份（缓存 key / 实例引用的锚）
  "decoderVersionUsed": "v8",               // Phase 1 预留戳（DecodedImage）
  "decodeParamsHash": 123456789,
  "instances": [ /* ModuleInstance[] 全集（含已禁用） */ ],
  "history": {
    "items": [ /* HistoryItem[]（D-H2 全量，无上限） */ ],
    "position": 7
  },
  "historyHash": 987654321,                 // HIST-04 漂移检测锚
  "layerStack": null                        // Phase 6 预留字段
}
```

- **类型化 params 的编码**：`instances[].paramsData` 以 JSON 对象内联（`JSONEncoder` 产出，再以 `JSONSerialization`/值嵌入外层文档保持 pretty-print 可读）；解码走 `ModuleRegistry`（`opName → IOPModule.Type`，LightamerIOP API.md 已预留 Phase 2 填充位）+ 每 type 的 `init()` 反序列化。未知 op（未来版本写入、旧 app 读）→ 保留原 `paramsData` 原样透传（不做 best-effort 转换），`enabled=false` 降级并 toast——比丢弃用户数据安全。
- **写入器**：`actor SidecarWriter`，`scheduleWrite()` 2 秒节流合并（Task 睡眠期间再 schedule 则重置计时）；`flush()` 在切图与 `applicationWillTerminate` 强制调用。原子写：写同目录 `.<name>.lra.tmp-<uuid>` → `FileManager.replaceItemAt`（或 rename；同卷 rename 原子）——D-S3。
- **漂移检测流程（SC#5）**：load sidecar → 依 schema 解码 → `HistoryHash.hash(重建 instances)` vs 存档 `historyHash` → 不等 = 漂移 → 日志 + toast（D-26 分级），内存态以解码结果为准，**不回写**（用户可人工审阅外部编辑）。
- **imageID 持久化语义**：首次为图生成 UUID 并随 sidecar 存；此后缓存/实例引用全走它。sidecar 缺失 = pristine 图（仅终端三件套 + 默认模块链，history 空）。

Confidence：**High**（全部要素 Phase 1 已铺好：Params Codable & Hashable 强制、Codable 元数据类型、.lra 决策、节流决策）。

---

### 5. issue #1 统一渲染路径（D-X1/D-X2）

**根因复述**（已由 headless 双渲 harness 排除管线嫌疑）：`load()` 的 decodeTask 内嵌渲染 **和** `EditorAreaView` 的 `.task(id: loadedImageURL)` → `renderDisplayTexture` 构成双路径；后者触发时 `image` 尚为 nil → skip → 时序竞争黑屏。

**重构形状**：

1. **删除** `EditorAreaView.swift:43-45` 的 `.task(id:)` 渲染触发（视图回归纯显示）。
2. `load()` decodeTask 保持唯一渲染发起者：decode → 建 PREVIEW 管线 → 渲染 → `displayTexture` 推送（现 `EditorState.swift:113-128` 的结构即骨架，换成新 coordinator 调用）。
3. `EditorState.renderDisplayTexture` 收敛为 `rerender()`（参数变化驱动的重渲入口，Phase 2 起 coordinator 调用），删除其 URL 幂等防抖逻辑（`displayTextureRenderedForURL` 字段随之消亡——幂等性由 coordinator 的管线代数保证）。
4. `EditorMTKView` 不动（纯 blit + `isPaused` 按需重绘已是正确形态）；**D-X2**：`Coordinator.draw` 内的 drawable 回读探针（`EditorMTKView.swift:183-203`）与 RENDER/DRAW/UPDATE 日志探针在修复验证通过后移除。
5. **验证**：JPEG（`input/RAW/DSC00012.jpg`）+ ARW 各一次冷启动直开；XCUITest 已有三栏断言可复用；黑屏复现路径（open→立即切换→再切回）跑一遍。

**CIContext render-to-texture 异常复查**（同批 spike，`.work` headless 模式）：

- spike-b 证据（§2.3 Blit A）：同进程**首次** render-to-texture 写空（6/6），第二次正常 → **测试 A**：context 创建后做一次 throwaway 直渲 warm-up，验证后续直渲全部非空。成立 → PREVIEW 尺寸以下用直渲（省 CPU 往返），`CIContextPool` 保留 bitmap 路径为 FULL/兜底。
- **测试 B**：bitmap+replace 路径在 PREVIEW(2560px)/FULL(100MP) 的真实耗时再测（Phase 1 数据点：2560×1440 含上传 15.6ms/帧；100MP replace 段 ~0.3-0.5s）——若 warm-up 直渲成立，此成本只压在 FULL 路径（一次性，可接受）；若不成立，**PREVIEW 拖拽热路径不能走 bitmap**（15.6ms 预算里再叠一次 float32→CPU→GPU 往返无余量），此时 PREVIEW 显示输出改由 Metal 终端直写 `.bgra8Unorm`（§3.3 gamma 直写），bitmap 路径只留给「CIImage → 管线输入平面」这一步。→ 结论先行写进 plan：**无论 spike A/B 结果如何，拖拽热路径都是全 Metal**（decode→输入平面除外）；spike 只决定 decode leg 与 FULL 路径用哪条。

---

### 6. clearCaches 设计（D-C1/D-C2 + spike-b 行动项 ①）

**三层 API**：

```swift
// 1) 管线平面缓存（主战场）
extension PipeCache {
    struct KeepingPolicy: Sendable { var currentImageID: UUID; var previousImageID: UUID? }  // 保留当前 FULL+PREVIEW + 上一张 PREVIEW（D-C1 字面）
    func enforceBudget(now: keeping: KeepingPolicy) async -> Freed   // 3GB 阈值执行器：先逐他图 THUMBNAIL/EXPORT → 他图 FULL → 他图 PREVIEW(留最近一张) → 最后才动当前图非活动分辨率
}
// 2) CI 内部态（spike-b 证据：跨解码累积 4.3-5.4GB 的元凶之一是 CI/RawCamera 内部 per-camera state）
extension CIContextPool { func clearCaches() /* ciContext.clearCaches()，load 入口每图一次 */ }
// 3) MetalContext PSO 缓存【不动】——256 项 kernel PSO 是 MB 级，clear 反而制造 PSO 重建卡顿；D-C1 的 3GB 全在平面侧
```

**触发点**（D-C2）：① `load(url:)` 入口——同步执行（清洗旧图先行，新解码后至）；② 60s 兜底 timer——`PipeCoordinator` 内 `Task.sleep(for: .seconds(60))` 循环（actor 内，不用 Timer/RunLoop），长会话同图调参的 PREVIEW 档位版本累积由此兜住；③ Phase 9 会话切换时整体 `invalidate(session:)`（前置钩子，本阶段留 TODO 注释）。

**toast**（D-26 分级）：释放量 > 500MB 时状态栏 toast 一次（节流），静默小清理不打扰。

**保留策略精度**：D-C1 说「保留当前 FULL+PREVIEW、最近 1 张历史图的 PREVIEW」。实现上 `KeepingPolicy.previousImageID` 由 coordinator 在 load 切换时记录；`enforceBudget` 按 `(imageID, pipeType)` 分代淘汰。Confidence **High**（纯 Swift 侧逻辑，无系统 API 风险）。

---

### 7. RAW-03（32-bit float TIFF/EXR/HIF 读入）——轻量收口

- **本机已验证**（`swift` + ImageIO 实测 2026-09-18）：`CGImageSourceCopyTypeIdentifiers()` 含 `com.ilm.openexr-image`、`public.tiff`、`public.heic`——EXR/HIF 解码 ImageIO 原生可达。`RAWDecoder.decodeRaster`（`RAWDecoder.swift:157-174`）现路径已能吃到它们。
- **待验证项（Phase 2 单测）**：32-bit float TIFF 经 `CGImageSourceCreateImageAtIndex → CGImage` 是否保 float 位深（`CGImageGetBitsPerComponent == 32`）还是被降为 16/8-bit；EXR 同问。若 CGImage 路径降精度 → fallback：`CIImage(image:)` / `CIImage(contentsOf:)`（CI 自有加载器，工作格式 float，预期不降）。**验收**：构造已知值（0.0/0.5/2.0/65504.0 极值像素）的 float TIFF/EXR fixture，解码后采样断言。Confidence **Med**（方向明确，降精度行为未实测）。
- 管线侧零特殊：解码产物同走 CIImage→输入平面；HDR 值 >1.0 在 float32 管线内天然保持（D-COL4 不截断），仅 gamma 端 clamp——正是 Phase 8 前的正确行为。

---

### 8. 建议的 plan 切分（5-8 个）

1. **Plan A — D-X1 渲染路径统一 + CIContext 直渲 spike**（§5）：删 `.task(id:)` 冗余、`rerender()` 收敛、warm-up 实验定 decode-leg 路径、D-X2 探针退役。最小、独立、先解黑屏。
2. **Plan B — PipeCache + PixelPipe 递归快路径**（§1）：StableHash、PipeCacheKey、PipeCache actor、processRec、cache-hit signpost + 命中计数测试；含 `IOPModule.process` 签名 Buffer→Texture 迁移（若采纳 §1.4）。
3. **Plan C — 多分辨率管线 + PipeCoordinator**（§2 + §6）：PipeResolution、量化梯子、四管线生命周期、D-C1/C2 预算执行器 + CIContext.clearCaches 接线、EditorState 重构为 coordinator 持有。
4. **Plan D — 终端三件套**（§3）：colorin 恒等模块、colorout 双路径（P3 常量矩阵 kernel + ColorSync 兜底）、gamma kernel 直写 bgra8Unorm、换屏跟随。
5. **Plan E — HistoryStack + ModuleRegistry + sidecar**（§4）：ModuleInstance/HistoryStack/effectiveInstances、ModuleRegistry、`.lra` 读写器（节流+原子）、漂移检测。
6. **Plan F — Golden harness + torture set + RAW-03**（Validation §）：中性度+交叉一致性双判据 harness、ColorChecker/torture 样本采集、float TIFF/EXR 位深验证、SC#1..5 验收跑通。

依赖序：A → B → (C, D 可并行) → E → F；E 与 D 弱耦合可穿插。

---

## Validation Architecture

### Golden 色彩 harness（D-COL1 + SC#5，Phase 3+ 前置闸门）

- **形态**：headless smoke 模式起步（`.work/*/smoke.swift` 先行），定稿进 `LightamerTests`（golden-image 测试为 AGENTS.md 硬约定）。
- **样本**（现有 + 需采集）：ColorChecker ARW（**缺，需从 raw.pixls.us 等 CC0 源采集**，含 50% 灰块）；torture set 对齐 ROADMAP SC#5——深阴影 Bayer（Z8 NEF 现有）、饱和 LED（缺，可后补不闸门）、X-Trans RAF（DSCF 系列 + GFX100S 现有）、100MP GFX（现有）、HDR stack（32f TIFF/EXR fixture 自造极值像素 + 真实 EXR 样本）。`.work/plans/01-05/samples/` 18 份全制式可复用。
- **双判据**（§3.5）：① 中性度——管线全链 → sRGB 8-bit → 定位 ColorChecker 灰块归一化坐标采样 → `max|R−G|,|G−B| < 2/255`；② 交叉一致性——同图 `CIContext` 直渲 sRGB（ColorSync 基准）vs 管线路径逐像素 < 2/255（只在已知 display profile 的屏/profile 上跑，快路径与基准互验）。
- **PASS 判定写死容差常量**，超差输出 per-patch 差值表 + PFM/PGM dump 供人工比对。

### 缓存快路径 harness（SC#2）

- 单测：链 = `[colorin, testGain, colorout, gamma]`；run1 全 miss（计数器断言）；改 `testGain` 参数（LightamerIOP 内一个 dev-only 参数化测试模块，同时满足 SC#2「拖动参数」的演示载体——Phase 2 无真滑块，**此模块是 SC#2 的必要道具**，planner 计入 Plan B 或 E）→ run2 断言 `colorin` hit、`testGain` 起 miss；undo → run3 断言 colorin hit + testGain hit（旧参数平面仍在缓存）。signpost/计数器双通道验证。
- 内存 harness：连续 N 图加载模拟 spike-b 累积场景，断言 `PipeCache.totalBytes` 始终 < 3GB 且 load 入口触发过清理（D-C1/C2 回归）。

### Sidecar round-trip harness（SC#3）

- 写 → 关（进程内 drop 全部状态）→ 重开 → 逐字段比对 instances/history/position + 渲染输出哈希一致；漂移注入（手改 JSON 一个参数）→ 断言检测 + 不回写。

---

## Risks & Gotchas

1. **CIRAW 显影域 vs 场景线性**（§3.1）：管线输入是「显影后」数据。Phase 3 filmic/scene-referred iop 的 golden 容差必须按此校准——现在写进架构文档，防止 Phase 3 误判移植错误。
2. **Swift `Hasher` 种子跨进程随机**：任何进缓存 key/sidecar 的 hash 必须走 StableHash（FNV-1a 64）。code review 红线。
3. **100MP 平面乘法**：FULL 管线任何「每模块一平面」的缓存都会爆 4GB（spike-b §4：3 平面 ≈ 4.7GB）。FULL 管线只缓存输入平面 + colorout 平面，中间用 ping-pong；per-module per-ROI 缓存实质只对 PREVIEW/THUMBNAIL 全开。
4. **PREVIEW 2560px 上限 vs 5K/6K 全屏**（D-C3 soft note）：全屏 XDR 逻辑分辨率 2560pt×2 = 5120px > 2560px 档顶 → 全屏查看是放大 2× 显示（软)。可接受（Phase 8 EDR/Phase 4 zoom 再说），planner 知悉即可。
5. **L008**：encoder `endEncoding` 必须显式先于 `commit`（gamma/colorout kernel 直写 drawable 时同规则）；**L006**：管线内部禁 half。
6. **`MTLTexture` 跨 actor**：缓存 actor 持有纹理、取出走 `@unchecked Sendable` 包装（Phase 1 `RenderedTexture` 契约），纹理写入后只读；绝不缓存会被二次写入的纹理。
7. **`modifyROIOut` 改变尺寸的模块**（Phase 4 crop）出现前，缓存 key 的 ROI 全链恒等——pass-through 时代每个 position 的 ROI 相同是**不变量**，processRec 可 assert 之，防 Phase 4 引入尺寸变化时缓存 key 静默失配。
8. **THUMBNAIL 360px 的 PREVIEW≠THUMBNAIL 复用**：360px 档在 PREVIEW 梯子末端也存在，但两管线 key 分离（pipeType 不同）——不要为了省内存合并，Darktable 分开（mipmap cache vs preview pipe）有历史原因（色彩空间不同，`colorout.c:598-603`）。
9. **CIContext 异常未复查前的假设管理**：所有依赖直渲的 plan 语句都带「若 spike A 成立」前置；bitmap 路径是回退而非阻塞项。
10. **sidecar 未知 op 透传**（§4.3）：解码失败即降级禁用，绝不丢 `paramsData`——用户数据安全红线。
11. **USB 卷 I/O**（L009）：sidecar 原子写的 tmp 文件与 rename 都在同一目录（同卷），不要用 `/tmp` 跨卷（跨卷 rename = copy，原子性失效）。

---

## Open Questions for Planning

1. **`IOPModule.process` 签名 Buffer→Texture**（§1.4）：采纳则 Plan B 首任务迁移 PassthroughModule + API.md；否则 PixelPipe 内建 staging 桥（临时，Phase 3 前仍要迁）。建议采纳。
2. **终端三件套落位**：LightamerCore（管线基础设施，测试零 IOP 依赖可跑）vs LightamerIOP（「模块都在 IOP」一致性）。建议 Core 新建 `Sources/Pipe/Terminal/`；planner 定。
3. **decode-at-scale 实测**：CIRAW CIImage 渲染 2560px 是否显著快于全幅（决定 PREVIEW 首渲 UX 文案与进度 UI 优先级）；Plan A 的 signpost 顺手测。
4. **FULL 管线本阶段深度**：SC#4 说「FULL at zoom ROI」而 zoom UI 是 Phase 4——建议本阶段 FULL = 全幅 scale 1.0 脚手架 + 可从测试调用，zoom ROI 交互留 Phase 4（roadmap 本就把 ROI 协商端到端放在 Phase 4 验收）。
5. **dev-only `testGain` 模块**的归属（LightamerIOP public 或测试 target 内部）：影响 API.md 面积；建议 LightamerIOP 内 `#if DEBUG` 或独立 `LightamerTestIOP`（planner 权衡 Tuist target 复杂度）。
6. **colorout 快路径的 profile 命名匹配表**：初始只认 Display P3 + sRGB 两个名，其余全走 ColorSync 慢路径——够不够本阶段验收（外接屏验证是否纳入 Phase 2）。
7. **60s 兜底 timer 的测试性**：`enforceBudget` 纯函数化 + timer 只做调用者，单测绕过 timer 直调——建议 planner 直接锁定此形状。

---

## Sources

### Darktable（本地源码，file:line 均已核）

- `src/develop/pixelpipe_hb.c:1838-1999` — `_dev_pixelpipe_process_rec`：递归 + 跳过禁用 + cache-hit 快路径（:1892-1921）+ 入口 scale 重采样（:1930-1999）
- `src/develop/pixelpipe_hb.c:2104-2153` — 递归展开后逐模块执行 + 输出 cacheline 预留
- `src/develop/pixelpipe_hb.h:32`（DT_PIPECACHE_MIN）、`:45-81`（piece 结构：hash=params+enabled、processed_roi、iscale）、`:83-91`（changed 事件枚举）、`:161-265`（pipe 结构：cache_obsolete_order、type、input/iscale）、`:339-404`（管线 init 变体 / create_nodes / synch_all / synch_top）
- `src/develop/pixelpipe.h:41-62` — 管线类型位掩码（FULL/PREVIEW/THUMBNAIL/EXPORT/SCREEN/FAST）
- `src/develop/pixelpipe_cache.c:99-155`（basichash：imgid+pipe type+profiles+逐 piece hash）、`:160-172`（+ROI+scharr）、`:174-195`（available 扫描）、`:261-289`（size 失配判脏 + 命中置 important）、`:291-354`（get：老化/淘汰/分配）
- `src/develop/develop.h:34-49` — `dt_dev_history_item_t` 身份元组（op_name/iop_order/multi_priority/multi_name/blend_params/params）
- `src/common/history.h:37-54` — history hash 类型（BASIC/AUTO/CURRENT/MIPMAP）
- `src/common/history.c:1571-1665` — hash 计算：仅启用项、`GROUP BY operation,multi_priority MAX(num) ORDER BY num`、含 module_order
- `src/iop/colorin.c:1184-1243`（process：cmatrix/lcms2 分派）、`:1245+`（commit_params）
- `src/iop/colorout.c:404-486`（矩阵+TRC LUT fastpath）、`:521-546`（process 分派）、`:548-617`（commit_params：export/thumb/preview2/display profile 选择）
- `src/iop/gamma.c` — 管尾 sRGB TRC 编码 + 打包

### 项目内（Phase 1 证据链）

- `spike-b-100mp-perf.md` §2.2/§2.3/§4 — 缓存累积 4.3-4.8GB、clearCaches 硬需求、cached-frame 15.6ms@102MP、blit-A 首渲写空 6/6、平面乘法爆预算推算
- `01-RESEARCH.md` Open Question #7（CIRAW 输出 display-ready 结论）、§3（CIContext 配置）、§9（模块边界）
- `LESSONS.md` L005/L006/L008/L009/L010
- 现行代码：`LightamerCore/Sources/{Pipe,Metal,Layers,Decode,Foundation}/`、`App/Sources/Lightamer/State/EditorState.swift`、`App/Sources/Lightamer/UI/{EditorAreaView,EditorMTKView}.swift`、两份 `API.md`
- 本机实测（2026-09-18，research 期间）：`CGImageSourceCopyTypeIdentifiers()` 含 `com.ilm.openexr-image` / `public.tiff` / `public.heic`（RAW-03 可达性）；`V50Order` colorin=28.0 / colorout=70.0 / gamma=78.0

### Apple 文档

- `CIRAWFilter` / RAW image options（decoderVersion、baselineExposure、neutralChromaticity）— developer.apple.com/documentation/coreimage/cirawfilter
- `CIContext` options（workingColorSpace/outputColorSpace/cacheIntermediates）与 `render(_:toBitmap:rowBytes:bounds:format:colorSpace:)`
- `NSScreen.colorSpace` / `NSColorSpace.cgColorSpace`（D-COL2 显示 profile 获取）
- Metal：`MTLTexture` storage mode / `.bgra8Unorm` drawable 语义（软件 TRC 编码的前提）
- ImageIO：`CGImageSource` 类型识别（RAW-03 路径）

---
*Phase 2 Research — 2026-09-18。产物仅本文件；未提交 git。*
