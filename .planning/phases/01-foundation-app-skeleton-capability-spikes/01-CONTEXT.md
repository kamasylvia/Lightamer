# Phase 1: Foundation, App Skeleton & Capability Spikes - Context

**Gathered:** 2026-08-03
**Revised:** 2026-08-04 (D-02/D-03 multi-target + Tuist decoupling; Layer skeleton; state isolation; module API contracts)
**Status:** Ready for planning — **plans need revision to match the new module structure**

<domain>
## Phase Boundary

搭起 macOS 27 原生 app 的"脊椎"——一个能启动的 app、CIRAW 9 RAW 解码、Metal compute 调度框架、`IOPModule` 协议 + `v50_order` 模块顺序表、MTKView 视口（显示一张解码后的 RAW，无调整无交互）、Layer 抽象骨架（Phase 6 才实现，但类型从第一天就位）。外加两个独立 spike 验证 CIRAW 9 能力边界与 100MP Metal 性能。这是后续所有阶段插入的骨架——基础决策在此锁定且昂贵难反。

**Phase 1 不做**：pixelpipe 多分辨率缓存（Phase 2）、色彩管理 terminal trio（Phase 2）、history stack（Phase 2）、任何 iop 算法（Phase 3+）、tiling 框架（Phase 2）、缩放/平移交互（后期）、UI 错误提示组件的完整实现（仅骨架）、CI（后期）。

</domain>

<decisions>
## Implementation Decisions

> **2026-08-04 修订**：原 D-02（单 app target）已废弃——单 target 放弃了编译器强制的模块边界，对未来改动多的项目是债务复利。改为多 target + Tuist，从第一天就用 Swift access control 强制子系统解耦。原 D-03（子系统目录）相应升级为多 target 的 module 布局。其余决策不变。

### Project Structure — 多 target + Tuist（修订 D-02/D-03）

- **D-02 (REVISED):** 多 target 结构 + Tuist 生成 `.xcodeproj`。从第一天用 Swift access control（`internal` 限定 module 内、`public` 暴露 API 表面）强制子系统边界。未来改 A 子系统，编译器立刻暴露所有跨 module 调用点。 — **Reversibility:** one-way — 模块拆分一旦发布、跨 module 的 `public` API 被依赖，合并/重拆需要迁移；选 Tuist 后转 XcodeGen/SPM 也要重写配置。理由：用户明确"未来改动会很多，希望尽量解耦"，单 target 的"约定式"子系统目录无法被编译器强制，是债务复利起点。
- **D-02a (NEW — Tuist 选型理由):** Tuist vs XcodeGen vs 本地 SPM 三条路在"解耦强度"上完全相同（都靠 Swift module 边界）。选 Tuist 是因为：(1) `Project.swift` 用 Swift 写，类型安全、可复用辅助函数，多 target 配置比 XcodeGen YAML 干净；(2) `tuist graph` 可视化依赖图；(3) 未来若 target 数量增长（iop 按类别拆 target、Session/Export 独立），Tuist 的依赖图与缓存红利显现。代价：多一个工具依赖 + `brew install tuist`。 — **Reversibility:** costly — Tuist→XcodeGen 迁移需重写配置，但 module 边界本身不变。
- **D-03 (REVISED):** 模块/target 布局如下。每个 target 是独立 Swift module，`internal` 限定模块内、`public` 暴露跨模块 API 表面：

  | Target | 类型 | 依赖 | 职责 | 对外 public 表面 |
  |---|---|---|---|---|
  | **LightamerCore** | Tuist target (framework) | — | pixelpipe 骨架、MetalContext、IOPModule 协议、RAWDecoder、Layer 抽象骨架、WorkingSpace、AppError、ROI、V50Order | `RAWDecoder`、`DecodedImage`、`MetalContext`、`protocol IOPModule`、`protocol Layer`、`struct LayerStack`、`PixelPipe`、`WorkingSpace`、`AppError`、`ROI`、`V50Order` |
  | **LightamerIOP** | Tuist target (framework) | LightamerCore | iop 模块集合（Phase 1 仅 Passthrough；Phase 3+ 加 Exposure/WB/curve...） | 每个 iop 的 `public final class XXXModule: IOPModule` |
  | **Lightamer** (app) | Tuist target (app) | LightamerCore + LightamerIOP | SwiftUI shell、Session、Export、Yiyin、AI、EditorMTKView | app bundle |
  | **LightamerTests** | Tuist target (unit test) | LightamerCore + LightamerIOP | 单元测试 | — |
  | **LightamerUITests** | Tuist target (UI test) | Lightamer (app) | UI 测试 | — |

  **模块边界铁律**：
  - app target（UI/Session/Export/Yiyin/AI）**只能依赖** LightamerCore/LightamerIOP 的 `public` 类型——不能 import 它们的 `internal`
  - LightamerIOP 只依赖 LightamerCore 的 `public`（`IOPModule` 协议、`MetalContext`、`ROI` 等），iop 之间互相不可见 `internal`
  - LightamerCore 不依赖任何其他 Lightamer module（最底层）
  - 跨 module 调用必须走 `public` API——这一步就是"API 表面"的强制声明

  **目录结构**：
  ```
  Lightamer/                          # 仓库根
  ├── Project.swift                   # Tuist manifest（定义所有 target）
  ├── Tuist/                          # Tuist 配置（Config.swift、依赖锁）
  ├── LightamerCore/
  │   └── Sources/
  │       ├── Decode/                 # RAWDecoder, DecodedImage, metadata
  │       ├── Metal/                  # MetalContext, dispatch, PSO cache
  │       ├── Pipe/                   # PixelPipe, IOPModule protocol
  │       ├── Layers/                 # Layer protocol, LayerStack (骨架)
  │       └── Foundation/             # WorkingSpace, AppError, ROI, V50Order
  ├── LightamerIOP/
  │   └── Sources/
  │       ├── Passthrough.swift + Passthrough.metal
  │       └── (Phase 3+: Exposure.swift, WB.swift, ...)
  ├── App/
  │   └── Sources/Lightamer/
  │       ├── UI/                     # SwiftUI shell, 三栏, EditorMTKView
  │       ├── Session/                # Capture One Session 模式
  │       ├── Export/                 # 导出流水线
  │       ├── Yiyin/                  # 印框/水印面板
  │       └── AI/                     # Vision 蒙版
  ├── Tests/LightamerTests/
  ├── Tests/LightamerUITests/
  └── Resources/                      # .metallib, xcstrings, test fixtures
  ```

- **D-03a (NEW — Layer 抽象骨架):** Phase 1 在 LightamerCore 定义 Layer 抽象**骨架类型**（`protocol Layer`、`struct LayerStack`、背景层 + 调整图层 + 蒙版占位），让 Phase 2 pixelpipe 从第一天就 layer-aware。Phase 6 只填实现，不改架构。这是研究 LESSON L005 的直接对策——图层必须从 pixelpipe 设计之初纳入，不能后期贴上。骨架类型用 `public` 暴露，但方法可暂返回占位/未实现。 — **Reversibility:** one-way — Layer 协议是 pixelpipe 的核心数据结构，一旦 Phase 2+ 依赖它，改协议等于迁移。
- **D-03b (NEW — 状态隔离契约):** SwiftUI 状态按子系统隔离为独立 `@Observable` 对象，禁止合并成 god-object：
  - `SessionState`（当前 Session、最近会话列表、文件夹监视状态）
  - `EditorState`（仅当前编辑的图像 + 图层栈 + history + 解码/错误状态）
  - `ExportState`（导出队列、配方、进度）
  - `InspectorState`（当前选中 iop 面板、面板展开状态）
  视图只注入它需要的那个 state 对象，不持有全部。 — **Reversibility:** costly — 状态边界是 SwiftUI 视图的依赖契约，后期拆 god-object 波及所有视图。
- **D-03c (NEW — 子系统 API 契约文档):** 每个 module 目录下放一个 `API.md`，列出"对外暴露的 public 类型/协议/函数"和"内部实现（internal，禁止跨 module 依赖）"。靠 code review 守，比什么都没有强；module 边界由编译器强制，API.md 是人类可读的契约索引。 — **Reversibility:** reversible。
- **D-04:** 资源放 `Resources/` 目录（`.metallib` 编译后 shader、String Catalog、golden image 样本），随 app target 打包；测试 fixtures 放 `Resources/TestFixtures` 并加入 LightamerTests target 的 sources。 — **Reversibility:** reversible。
- **D-05:** Bundle ID = `com.kamasylvia.lightamer`。 — **Reversibility:** one-way — 一旦发布/签名公证，Bundle ID 锁定。
- **D-06:** Spike 交付形式 = 独立 spike 分支 + 最小验证 app（不同于主 app），产出报告文档。

### App 窗口布局（不变）
- **D-07:** 三栏 NavigationSplitView（左 Session/相册导航、中网格/编辑区、右 Inspector iop 面板）。 — **Reversibility:** costly
- **D-08:** 三栏可调节：拖动调宽 + 折叠/隐藏面板 + 布局位置记忆 + 上下左右栏可互换（C1 高级特性）。**互换能力后期补**，Phase 1 只搭基础三栏骨架。 — **Reversibility:** reversible
- **D-09:** 网格浏览与编辑同窗切换（点缩略图进编辑、返回回网格），不独立窗口。
- **D-10:** v1 强制深色模式（专业摄影后期默认深色背景，色彩判断准确）；v2 加入可切换 + 跟随系统。 — **Reversibility:** reversible
- **D-11:** 首次启动 = 空状态提示（"选择文件夹创建 Session" / "拖放 RAW 到此"），无向导、无示例 Session。
- **D-12:** 顶部工具栏（导入/导出/前后对比/缩放等高频操作）+ 菜单栏。
- **D-13:** Phase 1 编辑视图范围 = 只显示一张解码后 RAW（无调整、无缩放/平移交互）。验证 MTKView↔SwiftUI 桥接能跑；交互/缩放/前后对比留后期。 — **Reversibility:** reversible

### MetalContext 设计（不变）
- **D-14:** Device = `MTLCreateSystemDefaultDevice()`（Apple Silicon 统一内存 GPU）。 — **Reversibility:** reversible
- **D-15:** 单 `MTLCommandQueue`（Phase 1 无争抢场景——只显示无交互；Metal 并行单位是 command buffer 非 queue）。后期导出队列（Phase 11）再加低优先级 compute queue。 — **Reversibility:** reversible
- **D-16:** PSO 缓存 = 懒加载 + 内存缓存。理由：Metal 不支持完整 PSO 磁盘序列化；活跃 PSO 内存占用小（< 50 个 = 几十 MB），16GB 不是瓶颈；`.metallib` 随 app bundle。 — **Reversibility:** costly
- **D-17:** 启用 function-constants（编译时参数注入，一个 kernel 文件生成多个特化变体）。
- **D-18:** 错误处理 = Swift throws（typed error，调用层 catch）。
- **D-19:** 两层 dispatch API：高层 `dispatch2D(texture, threadsPerThreadgroup, callback)` 供简单 iop；底层 `computeCommandEncoder + dispatchThreads` 暴露供精细控制（如后期 tiling）。 — **Reversibility:** costly
- **D-20:** Tiling 框架 Phase 1 不做（100MP float32 RGBA = 1.6GB/张，统一内存容得下；spike 验证）。框架留 Phase 2。 — **Reversibility:** reversible

### CIRAW 解码封装（不变）
- **D-21:** `RAWDecoder` 封装类（封装 `CIRAWFilter`，输入 URL → 输出 `CIImage` + 元数据），位于 LightamerCore，`public` 暴露。 — **Reversibility:** one-way — pixelpipe 的输入契约。
- **D-22:** RAW 9 opt-in 策略 = 默认请求 RAW 9（`decoderVersion = .version9`），不支持该相机时自动降级 RAW 8。用 `#available(macOS 27, *)` + `supportedDecoderVersions` 探测。 — **Reversibility:** reversible
- **D-23:** RAWDecoder 暴露三类元数据：(a) 拍摄元数据（EXIF/IPTC/XMP）；(b) RAW 技术参数（黑/白电平/基准曝光/中性色度，为 Phase 2 色彩管理用）；(c) 嵌入 segmentation matte（iPhone ProRAW，为 Phase 7 AI 用）。 — **Reversibility:** costly
- **D-24:** 非 RAW 输入（JPEG/HEIC/PNG/WebP/TIFF/PSD-flat，RAW-04）走同一 RAWDecoder 统一入口（内部判断走 CIRAWFilter 还是 CGImageSource）。 — **Reversibility:** reversible

### 错误处理与用户提示（不变）
- **D-25:** 统一 `AppError` 枚举（符合 `Error + LocalizedError`），位于 LightamerCore，`public` 暴露。各层抛 typed error，UI 层统一转人可读提示。 — **Reversibility:** costly
- **D-26:** 分级用户提示：非阻塞 alert/sheet（警告）+ 阻塞 alert（致命错误）+ 后台错误走状态栏 toast。Phase 1 SwiftUI shell 含错误提示组件骨架。 — **Reversibility:** reversible
- **D-27:** 错误日志用 `os.Logger`（Apple 统一日志系统，Console.app 可查、性能开销低、等级分级）。 — **Reversibility:** reversible

### 测试与 CI 策略（不变）
- **D-28:** Phase 1 搭测试骨架：`LightamerTests` target（单测）+ `LightamerUITests` target（UI 测）+ 示例单测。框架就绪，不追求覆盖率。golden-image 测框架留 Phase 2。 — **Reversibility:** reversible
- **D-29:** CI 后期再接（不在 Phase 1）。减少前期配置负担；Azure DevOps 存代码，CI 平台发布前再定。

### 性能预算与插桩（不变）
- **D-30:** Phase 1 度量 4 项性能指标：60fps 帧率、RAW 解码耗时、内存占用（峰值/稳态）、Metal kernel GPU 耗时。
- **D-31:** 性能插桩 = Instruments + `os.signpost` 代码插桩。 — **Reversibility:** reversible
- **D-32:** 设硬性能预算：100MP 解码 ≤ 2s、显示 ≤ 500ms、稳态内存 ≤ 4GB。 — **Reversibility:** reversible

### Swift Concurrency 模型（不变）
- **D-33:** Swift Concurrency（async/await + actor）为整个 app 并发基础。`MainActor` 隔离 UI，后台 `Task` 跑解码/Metal，`actor` 保护可变状态。 — **Reversibility:** one-way
- **D-34:** RAW 解码走后台 async Task（不阻塞主线程），解码完成后回 MainActor 更新 UI；用户可取消。 — **Reversibility:** reversible
- **D-35:** SwiftUI 状态管理用 `@Observable` macro，**按子系统隔离**（见 D-03b），不合并成 god-object。 — **Reversibility:** costly

### the agent's Discretion
- 无——所有 area 用户均做了具体选择，无"你决定"项。

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### 项目级决策（必读）
- `.planning/PROJECT.md` — 项目上下文、Core Value、约束（macOS 27、linear Rec2020、float32 RGBA、v50_order、Metal-first/CIRAW-as-decoder、依赖最小化、sidecar 自有格式）
- `.planning/REQUIREMENTS.md` — Phase 1 需求：FOUND-01/02/03/05/06/07、RAW-01/02/04/05/06
- `.planning/ROADMAP.md` §Phase 1 — 成功标准、spike 清单、风险标注

### 研究产出（必读——含关键技术边界）
- `.planning/research/STACK.md` — CIRAW 9 能力边界表、Export Encoder Matrix、macOS floor 论证
- `.planning/research/ARCHITECTURE.md` — Darktable pixelpipe 架构、iop 模块 API、OpenCL→Metal 映射、v50_order、建议构建顺序
- `.planning/research/PITFALLS.md` — CIRAW/Metal/NDE/性能/互通陷阱与对策
- `.planning/research/SUMMARY.md` — 研究综合

### 本阶段研究（必读——含实现路径）
- `.planning/phases/01-foundation-app-skeleton-capability-spikes/01-RESEARCH.md` — 8 个实现路径（XcodeGen → **需更新为 Tuist**、CIRAWFilter、MetalContext、MTKView 桥接、IOPModule、ImageIO 元数据、Swift Concurrency、Spike 方法论）
- `.planning/phases/01-foundation-app-skeleton-capability-spikes/01-VALIDATION.md` — Nyquist 验证策略
- `.planning/phases/01-foundation-app-skeleton-capability-spikes/01-UI-SPEC.md` — UI 设计契约（spacing/typography/color/copywriting/interaction/a11y + UI Considerations 状态覆盖）

### 参考源码（Darktable）
- `/Volumes/UNITEK/Documents/Development/darktable/src/develop/pixelpipe.h` / `pixelpipe_hb.c` — pixelpipe 多分辨率与 per-module cache
- `/Volumes/UNITEK/Documents/Development/darktable/src/common/iop_order.c` — `v50_order` 模块顺序表（Lightamer 直接采用）
- `/Volumes/UNITEK/Documents/Development/darktable/src/iop/iop_api.h` — iop 模块插件契约（映射到 Swift `protocol IOPModule`）

### 经验记录
- `LESSONS.md` — L001（CIRAW 9 是 macOS 27）、L002（WebP/AVIF 编码）、L005（layers 必须从 pixelpipe 设计之初纳入，对应 D-03a）、L006（half 精度阴影 banding）、L007（FSEvents 不可靠）

### 外部规范
- Apple Developer: `CIRAWFilter`、`kCIInputDecoderVersionKey`、`MTLCreateSystemDefaultDevice`、`MTKView`、`NavigationSplitView`、`@Observable`、`os.Logger`/`os.signpost`
- Tuist: `Project.swift` / `Config.swift` 文档（tuist.io）
- WWDC26/305 — Enhance RAW image processing with Core Image（RAW 9）

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- 无（greenfield 项目，Phase 1 从零搭建）

### Established Patterns
- 无（Phase 1 将建立项目的基础模式：`RAWDecoder` 封装、`MetalContext` 调度、`IOPModule`/`Layer` 协议、`AppError` 错误流、Swift Concurrency + `@Observable` 状态隔离、多 target module 边界——这些模式会被后续所有阶段复用）

### Integration Points（模块边界——编译器强制）
- `LightamerCore`（最底层）→ 被 LightamerIOP + app 依赖，暴露 `public`：RAWDecoder、DecodedImage、MetalContext、IOPModule、Layer、LayerStack、PixelPipe、WorkingSpace、AppError、ROI、V50Order
- `LightamerIOP`（依赖 Core）→ 被 app 依赖，暴露 `public`：每个 iop 的 `XXXModule: IOPModule`
- app（UI/Session/Export/Yiyin/AI）→ 只依赖上面两个 module 的 `public`，不能触及它们的 `internal`
- `EditorMTKView`（NSViewRepresentable）位于 app target 的 UI，通过 Core 的 `public` 类型与 MetalContext/PixelPipe 交互
- Layer 协议在 Core 定义，Phase 1 放骨架类型，Phase 2 pixelpipe layer-aware，Phase 6 填实现

</code_context>

<specifics>
## Specific Ideas

- 用户硬件约束：16GB 内存 + 内置 SSD 紧张 + 外置硬盘丰余。影响 tiling 优先级、DerivedData 留内置 SSD、PSO 内存缓存。
- 用户核心诉求：**解耦**（"未来可能的改动会很多，因此希望项目尽量解耦"）。这是 D-02 修订为多 target + Tuist 的根本动因。模块边界由编译器强制，不靠约定。
- Capture One 风格窗口可重构性（上下左右栏互换）——长期目标，Phase 1 只搭基础三栏。
- 性能预算设硬指标（100MP 解码≤2s/显示≤500ms/稳态内存≤4GB）。

</specifics>

<deferred>
## Deferred Ideas

- **上下左右栏互换**（C1 风格完全可重构布局）—— 后期补。
- **tiling 框架** —— Phase 2 建。
- **CI 接入** —— 后期发布前。
- **深色模式可切换/跟随系统** —— v2。
- **预热高频 kernel PSO** —— 若懒加载冷启动延迟感知明显再加。
- **iop 按类别拆为多个 target**（如 LightamerIOPColor / LightamerIOPDenoise）—— 当前 iop 共用 LightamerIOP 一个 target；未来若 iop 数量极大且需要独立缓存，可按类别拆。Tuist 多 target 配置支持这种演进。
- **RAWDecoder 改为 protocol RAWDecoding + 多实现（libraw fallback）** —— v2+ 若某些相机 CIRAW 不支持。

</deferred>

---

*Phase: 1-Foundation, App Skeleton & Capability Spikes*
*Context gathered: 2026-08-03*
*Revised: 2026-08-04 — multi-target + Tuist decoupling (D-02/D-03), Layer skeleton (D-03a), state isolation (D-03b), module API contracts (D-03c). Plans require revision to match.*
