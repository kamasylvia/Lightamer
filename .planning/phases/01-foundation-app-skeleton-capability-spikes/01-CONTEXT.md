# Phase 1: Foundation, App Skeleton & Capability Spikes - Context

**Gathered:** 2026-08-03
**Status:** Ready for planning

<domain>
## Phase Boundary

搭起 macOS 27 原生 app 的"脊椎"——一个能启动的 app、CIRAW 9 RAW 解码、Metal compute 调度框架、`IOPModule` 协议 + `v50_order` 模块顺序表、MTKView 视口（显示一张解码后的 RAW，无调整无交互）。外加两个独立 spike 验证 CIRAW 9 能力边界与 100MP Metal 性能。这是后续所有阶段插入的骨架——基础决策在此锁定且昂贵难反。

**Phase 1 不做**：pixelpipe 多分辨率缓存（Phase 2）、色彩管理 terminal trio（Phase 2）、history stack（Phase 2）、任何 iop 算法（Phase 3+）、tiling 框架（Phase 2）、缩放/平移交互（后期）、UI 错误提示组件的完整实现（仅骨架）、CI（后期）。

</domain>

<decisions>
## Implementation Decisions

### Xcode 工程搭建
- **D-01:** XcodeGen 生成 `.xcodeproj`（`project.yml`，不提交 `.pbxproj`）。开源项目主流、merge 不冲突、可重现。 — **Reversibility:** costly — 后期换 Tuist 需重写 project 定义，但 XcodeGen→Tuist 迁移有先例。
- **D-02:** 先单 app target + 子系统目录；后期若迭代变慢再迁移 Tuist + 多 target。单 target 下 Tuist 的依赖图缓存/选择性生成/二进制缓存红利用不上（都依赖多 target 边界）；91 个 iop = ~180 文件量在单 target 内 Xcode 增量编译已够快。 — **Reversibility:** reversible — 单 target→多 target 是渐进迁移。
- **D-03:** 子系统目录结构：`Sources/Core/`（RAWDecoder、MetalContext、pixelpipe 骨架）、`Sources/IOP/`（每个 iop 一个 `.swift` + `.metal` 文件对）、`Sources/UI/`（SwiftUI shell）、`Sources/Session/`、`Sources/Export/`、`Sources/Yiyin/`、`Sources/AI/`，全部在同一 app target 内。
- **D-04:** 资源放 `Resources/` 目录（`.metallib` 编译后 shader、String Catalog、golden image 样本），随 app target 打包。 — **Reversibility:** reversible。
- **D-05:** Bundle ID = `com.kamasylvia.lightamer`。 — **Reversibility:** one-way — 一旦发布/签名公证，Bundle ID 锁定，改名需重新签名所有已分发版本。
- **D-06:** Spike 交付形式 = 独立 spike 分支 + 最小验证 app（不同于主 app），产出报告文档。隔离干净，验证后可提炼到主 app 或弃用。

### App 窗口布局
- **D-07:** 三栏 NavigationSplitView（左 Session/相册导航、中网格/编辑区、右 Inspector iop 面板）。与 Capture One / Lightroom / Darktable 一致。 — **Reversibility:** costly — 三栏是 SwiftUI shell 的骨架，改结构影响所有子视图。
- **D-08:** 三栏可调节：拖动调宽 + 折叠/隐藏面板 + 布局位置记忆 + 上下左右栏可互换（C1 高级特性）。**互换能力后期补**，Phase 1 只搭基础三栏骨架（拖动调宽 + 折叠/隐藏 + 记忆）。 — **Reversibility:** reversible — 互换是渐进增强。
- **D-09:** 网格浏览与编辑同窗切换（点缩略图进编辑、返回回网格），不独立窗口。Capture One 风格。
- **D-10:** v1 强制深色模式（专业摄影后期默认深色背景，色彩判断准确）；v2 加入可切换 + 跟随系统。 — **Reversibility:** reversible。
- **D-11:** 首次启动 = 空状态提示（"选择文件夹创建 Session" / "拖放 RAW 到此"），无向导、无示例 Session。
- **D-12:** 顶部工具栏（导入/导出/前后对比/缩放等高频操作）+ 菜单栏。
- **D-13:** Phase 1 编辑视图范围 = 只显示一张解码后 RAW（无调整、无缩放/平移交互）。验证 MTKView↔SwiftUI 桥接能跑；交互/缩放/前后对比留后期。 — **Reversibility:** reversible — 是范围限定，非架构锁定。

### MetalContext 设计
- **D-14:** Device = `MTLCreateSystemDefaultDevice()`（Apple Silicon 统一内存 GPU）。单 GPU 机器无需多 device 选择。 — **Reversibility:** reversible。
- **D-15:** 单 `MTLCommandQueue`（Phase 1 无争抢场景——只显示无交互；Metal 并行单位是 command buffer 非 queue；Darktable 也单 queue 起步）。后期导出队列（Phase 11）再加低优先级 compute queue。 — **Reversibility:** reversible — 加 queue 是增量。
- **D-16:** PSO 缓存 = 懒加载 + 内存缓存。理由：(a) Metal 不支持完整 PSO 磁盘序列化（不像 Vulkan pipeline cache）；(b) 活跃 PSO 内存占用小（用户一次编辑不会同时调全部 91 个 iop，活跃 PSO 通常 < 50 个 = 几十 MB），16GB 不是瓶颈；(c) `.metallib` 随 app bundle 打包无需额外缓存层；(d) 真正吃内存的是图像数据（100MP float32 RGBA = 1.6GB/张），那才是 tiling 要解决的。冷启动延迟通过"首次用到才编译"分摊。 — **Reversibility:** costly — PSO 缓存策略是 MetalContext 核心，改它影响所有 iop 调用路径。
- **D-17:** 启用 function-constants（编译时参数注入，一个 kernel 文件生成多个特化变体）。Darktable OpenCL 常用类似手段优化多模式 kernel。
- **D-18:** 错误处理 = Swift throws（typed error，调用层 catch）。
- **D-19:** 两层 dispatch API：高层 `dispatch2D(texture, threadsPerThreadgroup, callback)`（调用者只管"处理整张图"，内部算 threadgroup grid）供简单 iop；底层 `computeCommandEncoder + dispatchThreads` 暴露供精细控制（如后期 tiling 的 denoise）。 — **Reversibility:** costly — API 形态是每个 iop 的调用契约。
- **D-20:** Tiling 框架 Phase 1 不做（100MP float32 RGBA = 1.6GB/张，Apple Silicon 统一内存 16GB 容得下；100MP 解码+显示的 spike 会验证）。框架留 Phase 2 遇内存压力再加。 — **Reversibility:** reversible — 是范围限定。

### CIRAW 解码封装
- **D-21:** `RAWDecoder` 封装类（封装 `CIRAWFilter`，输入 URL → 输出 `CIImage` + 元数据）。隐藏 CIRAWFilter 细节，为 Phase 2 pixelpipe 提供 clean 输入。 — **Reversibility:** one-way — 这是 pixelpipe 的输入契约，Phase 2+ 所有模块依赖此接口。
- **D-22:** RAW 9 opt-in 策略 = 默认请求 RAW 9（`decoderVersion = .version9`），不支持该相机的 RAW 9 时自动降级 RAW 8。用户无感、获得最佳质量。用 `#available(macOS 27, *)` + `supportedDecoderVersions` 探测。 — **Reversibility:** reversible。
- **D-23:** RAWDecoder 暴露三类元数据：(a) 拍摄元数据（相机/镜头/焦距/光圈/快门/ISO/GPS/拍摄时间，EXIF/IPTC/XMP）；(b) RAW 技术参数（黑电平/白电平/基准曝光/中性色度等 CIRAWFilter properties，为 Phase 2 色彩管理用）；(c) 嵌入 segmentation matte（`semanticSegmentationSkyMatteImage` 等，iPhone ProRAW 嵌入的，为 Phase 7 AI 用）。 — **Reversibility:** costly — 元数据接口扩展容易，删字段会破坏调用方。
- **D-24:** 非 RAW 输入（JPEG/HEIC/PNG/WebP/TIFF/PSD-flat，RAW-04）走同一 RAWDecoder 统一入口（内部判断走 CIRAWFilter 还是 CGImageSource）。调用方无感。 — **Reversibility:** reversible。

### 错误处理与用户提示
- **D-25:** 统一 `AppError` 枚举（符合 `Error + LocalizedError`），各层（RAW/Metal/Session）抛 typed error，UI 层统一转人可读提示。错误可追溯、可分类。 — **Reversibility:** costly — 错误类型是跨层契约。
- **D-26:** 分级用户提示：非阻塞 alert/sheet（警告，可继续操作）+ 阻塞 alert（致命错误如文件损坏/解码失败）+ 后台错误走状态栏 toast。Phase 1 SwiftUI shell 含错误提示组件骨架。 — **Reversibility:** reversible。
- **D-27:** 错误日志用 `os.Logger`（Apple 统一日志系统，Console.app 可查、性能开销低、等级分级）。 — **Reversibility:** reversible。

### 测试与 CI 策略
- **D-28:** Phase 1 只搭测试骨架：一个 `LightamerTests` target（单测）+ `LightamerUITests` target（UI 测）+ 几个示例单测（验证 RAWDecoder 能解码、MetalContext 能初始化）。框架就绪，不追求覆盖率。golden-image 测框架留 Phase 2（研究明确指 Phase 2 建 harness）。 — **Reversibility:** reversible。
- **D-29:** CI 后期再接（不在 Phase 1）。减少前期配置负担；Azure DevOps 存代码，CI 平台（GitHub Actions vs Azure Pipelines）发布前再定。

### 性能预算与插桩
- **D-30:** Phase 1 度量 4 项性能指标（为 Phase 2 缓存优化设基线）：(a) 60fps 帧率（Core Value）；(b) RAW 解码耗时；(c) 内存占用（峰值/稳态，16GB 硬约束）；(d) Metal kernel GPU 耗时。
- **D-31:** 性能插桩 = Instruments（Xcode 自带，Time Profiler/Metal System Trace/Allocations）+ `os.signpost` 代码插桩（与 os.Logger 一致，运行时自动收集，开销低，可在 Instruments 看时间轴）。 — **Reversibility:** reversible。
- **D-32:** 设硬性能预算：100MP 解码 ≤ 2s、显示 ≤ 500ms、稳态内存 ≤ 4GB。超出则 spike 报警，作为 Phase 2 优化目标。 — **Reversibility:** reversible。

### Swift Concurrency 模型
- **D-33:** Swift Concurrency（async/await + actor）为整个 app 并发基础。`MainActor` 隔离 UI，后台 `Task` 跑解码/Metal，`actor` 保护可变状态。Swift 6 data race 安全。 — **Reversibility:** one-way — 并发模型是全局架构，渗透所有代码，后期换模型等于重写。
- **D-34:** RAW 解码走后台 async Task（不阻塞主线程），解码完成后回 MainActor 更新 UI；用户可取消。 — **Reversibility:** reversible。
- **D-35:** SwiftUI 状态管理用 `@Observable` macro（Swift 5.9+/macOS 14+），取代 ObservableObject，性能更好、与 async/await 天然兼容。 — **Reversibility:** costly — 状态管理渗透所有视图。

### the agent's Discretion
- 无明确"你决定"项——所有 8 个 area 用户均做了具体选择。

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### 项目级决策（必读）
- `.planning/PROJECT.md` — 项目上下文、Core Value、约束（macOS 27、linear Rec2020、float32 RGBA、v50_order、Metal-first/CIRAW-as-decoder、依赖最小化、sidecar 自有格式）
- `.planning/REQUIREMENTS.md` — Phase 1 需求：FOUND-01/02/03/05/06/07、RAW-01/02/04/05/06
- `.planning/ROADMAP.md` §Phase 1 — 成功标准、spike 清单、风险标注（CIRAW-1/2/3、METAL-3/4、SOLO-1）

### 研究产出（必读——含关键技术边界）
- `.planning/research/STACK.md` — CIRAW 9 能力边界表（哪些 demosaic/denoise/lens 原生覆盖）、Export Encoder Matrix、macOS floor 论证、What NOT to Use
- `.planning/research/ARCHITECTURE.md` — Darktable pixelpipe 架构（`src/develop/pixelpipe_hb.c:1838` 递归 processRec + cache-hit）、iop 模块 API、OpenCL→Metal 映射、v50_order（`src/common/iop_order.c:298`）、建议构建顺序
- `.planning/research/PITFALLS.md` — CIRAW/Metal/NDE/性能/互通陷阱与对策（CIRAW-1..5、METAL-1..8、NDE-1..6、PERF-1..5）
- `.planning/research/SUMMARY.md` — 研究综合（CIRAW 9 是 macOS 27 不是 14 的关键纠正在此）

### 参考源码（Darktable——iop 算法/架构移植参考）
- `/Volumes/UNITEK/Documents/Development/darktable/src/develop/pixelpipe.h` / `pixelpipe_hb.c` — pixelpipe 多分辨率与 per-module cache 模式
- `/Volumes/UNITEK/Documents/Development/darktable/src/common/iop_order.c` — `v50_order` 模块顺序表（Lightamer 直接采用）
- `/Volumes/UNITEK/Documents/Development/darktable/src/iop/iop_api.h` — iop 模块插件契约（映射到 Swift `protocol IOPModule`）

### 经验记录
- `LESSONS.md` — L001（CIRAW 9 是 macOS 27）、L002（WebP/AVIF 编码）、L005（layers 必须从 pixelpipe 设计之初纳入）、L006（half 精度阴影 banding）

### 外部规范
- Apple Developer: `CIRAWFilter`、`kCIInputDecoderVersionKey`、`supportedDecoderVersions`、`VNGenerateForegroundInstanceMaskRequest`、`MTLCreateSystemDefaultDevice`、`MTKView`、`NavigationSplitView`、`@Observable`、`os.Logger`/`os.signpost`
- WWDC26/305 — Enhance RAW image processing with Core Image（RAW 9）

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- 无（greenfield 项目，Phase 1 从零搭建）

### Established Patterns
- 无（Phase 1 将建立项目的基础模式：`RAWDecoder` 封装、`MetalContext` 调度、`IOPModule` 协议、`AppError` 错误流、Swift Concurrency + `@Observable` 状态管理——这些模式会被后续所有阶段复用）

### Integration Points
- `RAWDecoder` → Phase 2 pixelpipe 的输入层（CIImage + 元数据）
- `MetalContext` → Phase 2+ 所有 iop 的 dispatch 入口
- `IOPModule` protocol + `v50_order` → Phase 3+ 每个 iop 实现的契约
- `EditorMTKView`（NSViewRepresentable）→ SwiftUI shell 与 Metal 视口的桥接点
- `AppError` → 跨层错误传递的统一类型

</code_context>

<specifics>
## Specific Ideas

- 用户硬件约束明确：16GB 内存 + 内置 SSD 紧张 + 外置硬盘丰余（项目所在）。这影响：tiling 优先级（100MP 1.6GB/张对 16GB 是真实压力，但 Phase 1 spike 验证后再定）、DerivedData 应留内置 SSD（外置编译慢）、PSO 内存缓存而非磁盘（16GB 容得下活跃 PSO）。
- 用户重视 C1 风格的窗口可重构性（上下左右栏可互换）——这是长期目标，Phase 1 只搭基础三栏。
- 性能预算设硬指标（100MP 解码≤2s/显示≤500ms/稳态内存≤4GB）——用户接受这些作为 spike 的验证门槛。

</specifics>

<deferred>
## Deferred Ideas

- **上下左右栏互换**（C1 风格的完全可重构布局）—— Phase 1 只搭基础三栏骨架，互换能力后期补（可能作为独立 UX 优化阶段或并入相关功能阶段）。
- **tiling 框架** —— Phase 2 建（遇 100MP 内存压力时；研究明确指 Phase 2 pixelpipe 阶段加）。
- **CI 接入** —— 后期发布前（CI 平台 GitHub Actions vs Azure Pipelines 待定）。
- **深色模式可切换/跟随系统** —— v2。
- **预热高频 kernel PSO** —— 若懒加载的冷启动延迟感知明显，后期可加 Top-N kernel 预热。
- **多 GPU 选择 / 用户可选 GPU** —— 几乎用不上，不做。

</deferred>

---

*Phase: 1-Foundation, App Skeleton & Capability Spikes*
*Context gathered: 2026-08-03*
