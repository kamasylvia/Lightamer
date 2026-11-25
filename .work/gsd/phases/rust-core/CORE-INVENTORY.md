# CORE-INVENTORY — Lightamer 非 UI 核心盘点

> 范围：`LightamerCore/Sources`（232 Swift / 80,887 行）+ `LightamerIOP/Sources`（105 Swift / 36,719 行 + 59 `.metal`）+ `App/Sources/Lightamer/{AI,Export,Library,MCP,Session,State,Yiyin}`（94 Swift / 38,442 行）+ 73 个 `.metal`（13,317 行 / 186 kernels）+ `Tests/`（530 文件 / 4,623 XCTest 方法）。
> 口径：Swift 行数 = `wc -l`；分层行数 = 每文件 `splitlines()`（合计 156,050，与 `wc -l` 差 2 行，差在无尾换行文件）。只读盘点，产品树零改动，零 commit。
> 证据：逐条命令见 `CORE-INVENTORY-TABLES.md` §K；逐文件大表见同文件 §A–§J。

## §0 One-page summary

| 难度档 | 文件 | 行 | 占比 | 判据（粗） |
|---|---:|---:|---:|---|
| 纯逻辑 Pure | 197 | 59,720 | 38.2% | Foundation/simd/几何/SQL/JSON；无 Apple 像素、色彩、ML 或 UI 框架 |
| 着色器宿主 Shader host | 118 | 43,225 | 27.7% | 持有 `MTLTexture`/PSO/dispatch；含 105 个 IOP Swift 文件 |
| Apple 框架适配 Apple adapter | 66 | 31,221 | 20.0% | Core Image / ImageIO / Vision / CoreML / CoreText / CGColorSpace |
| 与界面耦合 UI-coupled | 50 | 21,884 | 14.0% | SwiftUI / AppKit 视图或 `@Observable` 状态模型，需先拆 |
| **合计（本 lane 口径）** | **431** | **156,050** | **100%** | 另有 73 `.metal` / 13,317 行 / 186 kernels（原样保留） |

- 范围外邻近非 UI：`App/Sources/Lightamer/Catalog` 4 文件/1,229 行（全 `@Observable`）、`Settings` 非 UI 模型 3 文件/818 行、`EditorState+FilmMigration.swift` 77 行；纳入后 439 文件/158,174 行（纯 +320、UI +1,804）。见 §1.5。

- Apple 能力处数：RAW 解码 `CIRAWFilter` 18 处/5 文件；`CIContext` 64/21、`CIImage` 84/13；`CGColorSpace` 221/40、`CGColorConversion` 10/2（ColorSync C API `CMProfile/CMWorld` 0）；Vision `VN*` 28/4；ImageIO 读 `CGImageSource` 95/18、写 `CGImageDestination` 71/17；Metal `MTL*` 1,485/102；CoreML 28/3（符号口径，排除 `MLModelRunner` 类名；字面 `MLModel` 32/3）；CoreText 38/4；UTType 13/9；SQLite `sqlite3_*` 117/6。
- 必须不变：`.lra` schema **v13**（22 个顶层键）；`.lalb` `user_version` **6**（13 实体表 + 2 FTS5）；哈希 FNV-1a 64 且 UInt64 一律十进制字符串；37 个 UserDefaults 键 + 2 前缀（本 lane 7 目录范围）；MCP **34** 工具（14 个需控制权）；导出元数据 6 开关 + ICC/DRT 输出约定。
- 测试：7 个单测 target + 1 个 UI target；530 文件 / 4,623 方法。可直接作 Rust 验收对照 = **400 文件 / 3,455 方法**（非 APP target、无 SwiftUI/AppKit）；其中不依赖 Metal 的 233 文件 / 2,121 方法。Golden/Parity 命名 61 文件 / 429 方法。
- 结论：Rust 核要接约 **134k 行**（纯逻辑 + 着色器宿主 + Apple 适配），UI 层另有 21.9k 行 Swift 需重写为 AppKit。43.2k 行着色器宿主中，MSL 本体（13.3k 行）不动，重写的是 Rust 侧纹理/PSO/dispatch 宿主。

## §1 Module map

### 1.1 LightamerCore（16 目录 / 232 文件 / 80,887 行）

| 目录 | 文件 | 行 | 职责一句话 | 关键公开类型 / 接口 |
|---|---:|---:|---|---|
| `AI/` | 30 | 8,102 | 本地语义（CLIP embedding/label）、AI worker 协议、主体蒙版、评级/增强、模型资产 | `SemanticEngine`, `SemanticStore`, `AIWorkerProtocol`, `AIMaskService`, `AISubjectSeed`, `AICredentialStore` |
| `Catalog/` | 5 | 2,907 | `.lalb` 目录索引、组织树、投影/重建 | `CatalogIndexStore`, `CatalogProjector`, `CatalogRebuilder`, `CatalogIndexSchema` |
| `ColorMatch/` | 8 | 1,609 | Oklab/CDF 配色求解与 3D LUT 烘焙 | `ColorMatchSolver`, `ColorMatchCDFSolver`, `ColorMatchBake`, `OklabMath` |
| `Decode/` | 10 | 4,049 | RAW/raster 解码入口、智能预览、EXIF/ICC 读取 | `RAWDecoder.decode(_:) async -> DecodedImage`, `RasterDecoder`, `SmartPreviewStore`, `CaptureMetadata` |
| `Export/` | 18 | 6,491 | 导出链、六格式编码、元数据/ICC、命名、DRT 输出 | `ExportQueue`, `ExportRenderer`, `ExportEncoder`, `ExportFormatSpec`, `ExportMetadataPolicy`, `DrtOutputColorSpace` |
| `Film/` | 13 | 5,093 | 光谱胶片/相纸 profile、密度/曲线、颗粒、材料库 | `FilmMaterialStore`, `SpectralFilmRuntime`, `SpectralBuildEngine`, `FilmProfile`, `PaperGradeTable` |
| `Foundation/` | 11 | 1,697 | 哈希、色彩空间、V50 顺序、错误、软打样、设置数学 | `StableHash`, `WorkingSpace`, `V50Order`, `ParamsCoding`, `AppError`, `SoftProofProfile` |
| `Graph/` | 6 | 1,548 | 文档模型、节点图命令、DRT/Film record | `PipelineDocument`, `NodeGraphCommand`, `DrtRecord`, `FilmRecord`, `RasterDefaultRecord` |
| `Layers/` | 18 | 4,474 | 图层栈、蒙版（绘制/参数/栅格）、retouch、blend | `LayerStack`, `AdjustmentLayer`, `MaskSpec`, `DrawnMaskRasterizer`, `RetouchEngine`, `BlendMode` |
| `Library/` | 17 | 7,853 | `.lalb` 打开/迁移/备份、导入、EXIF 搜索、分析、重链 | `ProjectFileStore`, `LibraryStore`, `LibrarySchema`, `ImportService`, `LibraryQueries`, `LibraryAnalysisService` |
| `Metal/` | 6 | 1,402 | Metal device/queue、PSO 缓存、CIContext 池、dispatch 门面 | `MetalContext`, `CIContextPool`, `ComputeEncoderSession`, `MetalError` |
| `Pipe/` | 48 | 17,758 | 像素管线、模块盒、缓存、历史、DRT/Film 尾段、输入/平铺 | `PixelPipe`, `IOPModule`, `ModuleRegistry`, `PipeCache`, `HistoryStack`, `DrtTailAssembly`, `FilmTailAssembly` |
| `Presets/` | 3 | 654 | 预设文档、应用/校验 | `LightamerPreset`, `PresetsStore`, `PresetApplier` |
| `Session/` | 16 | 5,720 | session 索引 SQLite、缩略图、过滤 SQL、XMP 导入、智能相册 | `SessionIndexStore`, `SessionThumbnailProvider`, `FilterSQL`, `SmartAlbumStore`, `XMPImport` |
| `Sidecar/` | 6 | 2,127 | `.lra` v13 schema、2s debounce 原子写、蒙版 PNG 存储 | `LightamerSidecar`, `SidecarStore`, `SidecarLayerStack`, `RasterMaskStore`, `UInt64String` |
| `Stack/` | 17 | 9,403 | 对焦堆栈、HDR/Mertens、全景、MTB 对齐、float TIFF | `StackMergeService`, `FocusStackMerge`, `HDRMergeMath`, `MertensFusion`, `PanoWarp`, `FloatTIFFWriter` |

Core 的跨模块契约索引正本：`LightamerCore/API.md`；未列入 API.md 的声明按 internal 实现细节处理（可自由重构）。

### 1.2 LightamerIOP（54 目录 / 105 Swift / 36,719 行 / 59 `.metal`）

- 56 个 opName（`acesccIn/Out`、`black/white`、`borders/watermark` 同目录各两个），逐目录 opName/行数/kernel 数见 `CORE-INVENTORY-TABLES.md` §B。
- 统一接口：`IOPModule`（`opName`/`iopOrder`/`flags`/`defaultColorspace`/`commitParams`/`process(input:output:...)`）；每模块一个 `Params: Codable & Hashable` + 一个 `*Kernel.functionName` + 一个 `.metal`。
- 3 个目录无自有 `.metal`：`Crop/`、`Upright/`、`SpektraFilm/`（复用 Core/Common kernel 或纯几何/参数）。
- 默认面禁用 6 个 op：`filmicrgb`、`sigmoid`、`agx`、`denoiseprofile`、`nlmeans`、`bilateral`（`LightamerIOPRegistry.defaultFaceDisabledOpNames`；`LIGHTAMER_FULL_IOP_FACE=1` 可恢复）。
- 跨模块契约索引正本：`LightamerIOP/API.md`。

### 1.3 App 非 UI 目录（94 文件 / 38,442 行）

| 目录 | 文件 | 行 | 职责一句话 | 核心 / UI 拆分（行） |
|---|---:|---:|---|---|
| `AI/` | 12 | 3,924 | AI worker 客户端/进程体、ML 会话、增强/深度、评级/标注、连接存储 | UI 1,544 / Apple 适配 1,497 / 纯 883 |
| `Export/` | 8 | 3,312 | 导出页三个 View + 文件落盘、命名模板、预设、导出后动作 | UI 2,832 / 纯 480 |
| `Library/` | 21 | 6,567 | 项目生命周期、网格/搜索/检视/重链模型、6 个 View、导入进度 | UI 5,829 / Apple 适配 286 / 纯 452 |
| `MCP/` | 18 | 10,280 | MCP server 内核、传输/启动器/端点锁、34 工具、schema 目录 | 纯 7,158 / Apple 适配 3,122 |
| `Session/` | 9 | 2,372 | session 协调/扫描/监听/对账、Lensfun 数据分发 | UI 1,296 / 纯 1,076 |
| `State/` | 24 | 10,956 | `@Observable` 状态模型与协调器、渲染/裁剪/版本/导出状态 | UI 9,352 / Apple 适配 686 / 纯 918 |
| `Yiyin/` | 2 | 1,031 | 印框面板 View + sheet 尺寸数学 | UI 1,031 |

App 非 UI 目录的关键内部类型：AI = `AIWorkerClient`/`AIInferenceService`/`AIAnalysisRegistry`/`DepthMaskService`；Export = `ExportFileWriter`/`ExportNamingTemplates`/`ExportPresetStore`/`PostExportActions`；Library = `LibraryProjectController`/`LibraryGridModel`/`LibrarySearchModel`/`LibraryThumbnailBridge`/`LibraryRelinkModel`；MCP = `McpToolRegistry`/`McpServerController`/`McpLauncher`/`McpHTTPTransport` + 34 tools；Session = `SessionCoordinator`/`SessionWatcher`/`SessionReconciler`/`SessionTreeScanner`；State = `EditorState`/`PipeCoordinator`/`LayerEditingState`/`ExportState`/`SessionState`；Yiyin = `YiyinPanelView`/`YiyinSheetSizing`。App target 无 `public` 面（`App/Sources/Lightamer/API.md`）。

### 1.4 State/ 的纯逻辑 vs SwiftUI 胶水

- **非 UI 绑定（可进 Rust 核，先抽 Apple 适配）**：`AIMaskEditing.swift` 500、`CropToolRotation.swift` 380、`MaskRefineCoordinator.swift` 304、`SessionThumbnailRenderer.swift` 186、`LensDefaultsWiring.swift` 98、`CleanTerminateSentinel.swift` 80、`YiyinSheetMetrics.swift` 56。合计 1,604 行。
- **`@Observable` 状态模型（SwiftUI/Observation 绑定，需先拆）**：`PipeCoordinator` 3,293、`EditorState` 1,356、`LayerEditingState` 971、`ExportState` 548、`AdjustmentTransfer` 447、`VersionCoordinator` 433、`ColorMatchService` 422、`AgentControlCoordinator` 356、`SessionState` 347、`InspectorState` 287、`ViewportState` 277、`PresetController` 157、`MetadataController` 142、`BeforeAfterState` 66、`SoftProofState` 116、`AdjustmentsPasteboard` 44、`EDRHeadroomMonitor` 90。合计 9,352 行。
- **重点**：`PipeCoordinator` 3,293 行是最大单文件，绝大多数是渲染编排/Metal/Task 生命周期，不是视图代码；拆 UI 时应先把它的纯渲染协调面下沉，`@Observable` 只留薄通知层。[推断：按文件头注释与 `MTL`/`CIContext` 使用密度判断]

### 1.5 Scope addendum — 未纳入 156k 基线的非 UI 邻近代码

用户指定的 38,442 行范围之外的 App 非 UI 代码，单独列出不改写基线：

| 路径 | 文件 | 行 | 性质 |
|---|---:|---:|---|
| `App/Sources/Lightamer/Catalog/` | 4 | 1,229 | legacy catalog 模式：`CatalogBrowserModel`/`CatalogPreferences`/`CatalogThumbnailRouter`/`CatalogTreeModel`，全部 `@Observable`，需拆 |
| `App/Sources/Lightamer/Settings/` 非 UI 模型 | 3 | 818 | `AppPreferences` 320（纯逻辑）+ `ACASettingsModel` 226 + `LCRSettingsModel` 272（`@Observable`）；`SettingsPages.swift` 是 UI，未计 |
| `App/Sources/Lightamer/EditorState+FilmMigration.swift` | 1 | 77 | `EditorState` 的 process migration 扩展，UI 耦合 |
| **合计** | **8** | **2,124** | 纳入后 439 文件 / 158,174 行（纯 +320、UI +1,804；着色器/Apple 不变） |

## §2 Apple dependency map

| 能力 | 核心需要它做什么 | 输入 → 输出 | 同步性 | 命中（文件/处） | 候选接口边界（只写语义） |
|---|---|---|---:|---|---|
| RAW 解码 | 相机 RAW → 线性 float32 平面 + 元数据 + decoder 版本 | URL + `RAWTechnicalParams` → `DecodedImage` | async（actor） | 5 / 18 | `RawDecoder::decode(path, params) -> DecodedImage`；核心只见平面/元数据，不见 `CIRAWFilter` |
| Raster 解码 | JPEG/PNG/TIFF/HEIF 等 → float32/16bit + ICC | URL/Data → 平面 + `RasterColorDescription` | sync | `CGImageSource` 18 / 95 | `RasterDecoder::decode(path) -> RasterImage`；ICC 由 `ColorProfile` 域类型承载 |
| 色彩管理 | ICC 解析/生成、工作空间转换、软打样 | 像素 + 源/目标 profile → 像素 / ICC 字节 | sync | `CGColorSpace` 40/221；`CGColorConversion` 2/10 | `ColorEngine::convert/parse_icc/make_icc`；禁止 `CGColorSpace` 泄漏到管线 |
| Vision | 人脸/眼睛/主体/皮肤区域 | `CGImage`/`CVPixelBuffer` → observations / mask | async | `VN*` 4/28 | `VisionService::faces/eyes/subject(pixels) -> [Observation]` |
| CoreML | CLIP embedding、标签、深度、增强推理 | 模型 URL + 张量 → 张量/标签 | async（独立 worker 进程） | `MLModel` 等 3/28 | `MlEngine::load/infer`；进程隔离与超时留在宿主层 |
| 编码 | JPG/PNG/TIFF/HEIF/AVIF 写；WebP 走 libwebp | 像素 + 元数据 + recipe → 文件/字节 | sync | `CGImageDestination` 17/71 | `Encoder::encode(image, metadata, format) -> Bytes`；格式矩阵是纯枚举 |
| Metal | device/queue/PSO/纹理/命令缓冲 | shader + 纹理 + uniforms → 纹理 | async（command buffer） | `MTL*` 102/1,485 | `GpuDevice::dispatch(kernel, textures, uniforms)`；MSL 原样，Rust 只做宿主 |
| 图像元数据 | EXIF/XMP/IPTC/TIFF 标签读写、ICC 剥离 | 文件/字节 → 字典 / 新字节 | sync | ImageIO 元数据 + `XMPWriter`/`ExportICCStrip` | `MetadataIo::read/write/strip_icc`；键名与容器位置是契约 |
| 文本栅格 | 印框/水印文字 → coverage 位图 | 字符串 + 字体 → 8-bit coverage | sync | `CT*` 4/38 | `TextRasterizer::rasterize(text, font, size) -> Bitmap` |
| SQLite（非 Apple，但平台 C） | `.lalb`/session 索引/缩略图索引 | SQL + 绑定 → 行 | sync | `sqlite3_*` 6/117 | `Sqlite::open/exec/prepare`；Rust 可直接用 rusqlite，不属 Apple 适配 |

**边界原则**：Core/Rust 只暴露领域类型（`ImageBuffer`、`ColorProfile`、`FaceObservation`、`EncodedImage`、`GpuTexture`）；`CIImage`/`CGImage`/`MTLTexture` 不进入核心 API。`CMProfile/CMWorld` 全仓 0 处——ColorSync 只经 `CGColorSpace` 与 `CGColorConversionInfo` 使用。补充计数口径：Vision 有 7 文件 `import Vision`，其中 4 文件实际调用 `VN*`；CoreML 有 7 文件 import，3 文件用 `MLModel`/`MLMultiArray`；CoreVideo `CVPixelBuffer` 45 处/3 文件（AI 蒙版/推理腿）；`NSFileProvider` 0。

## §3 Shader inventory

- 总量：**73 `.metal` / 13,317 行 / 186 kernels**。IOP 59 文件 / 8,700 行；Core 13 文件 / 4,531 行；App UI 1 文件 / 86 行（vertex+fragment，0 kernel）。
- 逐文件（行数、kernel 数、宿主）见 `CORE-INVENTORY-TABLES.md` §E。
- 宿主/着色器约定：
  1. **纹理**：工作面 `texture2d<float, access::read/write>`，像素格式 `.rgba32Float`（`WorkingSpace.pixelFormat`）；显示面 `.bgra8Unorm`；EDR 面 `.rgba16Float`；LUT/打印表 `texture3d<float, access::read>`、一维 LUT `texture1d`。
  2. **绑定**：输入 texture 0、输出 texture 1；uniform 一般 buffer 0（`setBuffer`/`setBytes`）；多 pass kernel 用 2–5 个纹理槽（BlendOp/Denoise/Dehaze/ToneEqual）。
  3. **线程组**：默认纹理 8×8；buffer 16×16；归约/直方图 64×1（`MetalContext.dispatch2DTexture` 缺省 8×8，`dispatch2D` 缺省 16×16；host 侧 80 处 8×8、25 处 16×16、3 处 64×1）。
  4. **uniform**：Swift 镜像 struct 显式补齐 16 字节 stride（如 `ExposureUniforms` 两 float + padding）；`commitParams` 计算 `paramsHash = StableHash(ParamsCoding.encode(params))` 并把 buffer 存 `IOPPiece.data`；`process` 绑定，不重编码。
  5. **函数常量**：4 个 shader 用 `[[function_constant(N)]]`（`EditorBlitShader`、`TerminalKernels`、`Passthrough`、`ToneEqualKernels`）；PSO 必须一次填满全部常量（否则创建失败）。
  6. **特殊依赖**：原子操作 5 文件（`RetouchKernels`、`BilateralKernels`、`BilateralGrid3DKernels`、`HistogramReduceKernels`、`ScopeReduceKernels`）；`texture3d` 2 文件（`Lut3d`、`FilmSubRun`）；`texture1d` 1 文件（`Lut3d`）；`texture2d<uint>` 1 文件（`ScopeReduce`）；`access::sample` 2 文件（`Liquify`、`Yiyin`）；实际 `access::read_write` 声明仅 1 文件（`SpectralSpatial`；另 10 文件在注释里记录 L018 禁用，literal 提及共 11 文件）。
  7. **特例**：`ACESccMath.metal` 无 kernel（被 `ACESccConvert.metal` `#include` 的常量头）；`EditorBlitShader.metal` 是 UI 的 vertex+fragment，不属于计算管线；`StackKernels.metal` 的 `focus_sml` 走 buffer 而非纹理。

## §4 Load-bearing contracts

### 4.1 `.lra` sidecar — v13

- 正本：`LightamerCore/Sources/Sidecar/LightamerSidecar.swift`（`schemaVersionCurrent = 13`）、`SidecarStore.swift`、`SidecarLayerStack.swift`。
- 顶层 22 键：`schemaVersion`, `appVersion`, `imageID`, `decoderVersionUsed`, `decodeParamsHash`, `instances`, `history`, `historyHash`, `layerStack`, `rating`, `flag`, `colorLabel`, `keywords`, `note`, `provenance`, `rawOverrides`, `displayTransform`, `versions`, `activeVersionID`, `aiProvenance`, `filmRecord`, `process`。
- 关键嵌套：`history = {items, position}`；`HistoryItem = {id, snapshot, label, timestamp, layerScope, stackSnapshot, pasteSet, drtRecord, filmRecord, note, author}`；instance = `{id, opName, multiPriority, multiName, iopOrder, version, enabled, paramsData(base64), paramsHash(decimal string)}`；layer = `{id, kind, name, isVisible, enabled, opacity, blendMode, blendOptions, chain, mask, strokes?}`；mask = `{version, drawn?, parametric?, raster?, deletionProtected?, contentRevision?}`；version = `{id, name, createdAt, updatedAt, chain?}`。
- 写法：JSON **prettyPrinted + sortedKeys**；`UInt64String` 十进制字符串；`paramsData` base64；2s debounce + 同目录 `.tmp-<uuid>` 原子晋升；损坏 JSON = nil（不抛 UI）。
- 逐字兼容含义：Rust 侧必须产生相同键序/相同 JSON 字节语义（sortedKeys），否则 drift 检测与 golden 字节测试失败。

### 4.2 `.lalb` library — `user_version = 6`

- 正本：`LightamerCore/Sources/Library/LibrarySchema.swift`、`ProjectFileStore.swift`。
- 13 个实体表 + 2 个 FTS5 虚表：`project_meta`, `images`, `albums`, `album_content`, `version_ref`, `stacks`, `stack_content`, `semantic_model`, `image_embedding`, `image_label`, `label_query`, `ai_understanding`, `ai_rating`；FTS = `images_fts`, `ai_understanding_fts`（+ 6 个同步触发器）。列清单见 TABLES §H。
- 写入纪律：WAL + `synchronous=NORMAL`；close 强制 checkpoint；迁移前自动 `sqlite3_backup` 快照；`backup(to:)` 是唯一钦定备份路径；`version_ref` 是 `.lra` 版本 UUID 的投影，真身在 sidecar。
- 另有 session 索引库：`SessionIndexSchema.schemaVersion = 2`（`images` + `meta` + FTS），与 `.lalb` 分开。

### 4.3 Hash / params

- 正本：`Foundation/StableHash.swift`、`Foundation/ParamsCoding.swift`、`Pipe/History/HistoryHash.swift`。
- FNV-1a 64（offset `0xcbf29ce484222325`，prime `0x00000100000001b3`）；UTF-8 字符串、小端定点整数、canonical params bytes（`.sortedKeys`）按固定顺序折叠；`HistoryHash` 种子 = `decodeParamsHash`，再按 v50 有效实例顺序折叠 `opName`/`multiPriority`/`version`/`paramsData`，layer 维度追加 layer id/name/props/chain/mask hash。
- 入 JSON 的 UInt64 一律 decimal String（`UInt64String`）；Swift `Hasher` 与未排序 JSON 禁止跨进程。

### 4.4 UserDefaults — 37 键 + 2 前缀

- 正本分散在 `Library/ImportFilter.swift`、`Library/LibraryAnalysisService.swift`、`Decode/SmartPreviewStore.swift`、`Catalog/CatalogProjector.swift`、`AI/*`、`Export/*`、`MCP/McpServerController.swift`、`State/*`、`YiyinSheetMetrics.swift`、`Lut3d/LutLibraryStore.swift`、`Lens/LensModule.swift`。完整键表见 TABLES §F。
- 前缀族：`display.override.icc.<profile-hash>`（显示器手动覆盖）、`orphanIgnore/<path>`（session 孤儿忽略）。
- 邻近但不在 37 键内（因源文件在 Catalog/Settings）：`mask.behavior.default`（`Settings/AppPreferences.swift:39`，消费点在 `State/LayerEditingState.swift:372`）、`catalogs.databasePath` / `organization.mode`（`Catalog/CatalogPreferences.swift:33/37`）、`keyboard.override.` 前缀（`AppPreferences.swift:42`）；另有 UI 层 `layout.*` / `browser.mode` / `mcp_agent_*_template`，本盘点不计。

### 4.5 MCP — 34 工具 / 14 个需控制权

- 正本：`App/Sources/Lightamer/MCP/McpToolRegistry.swift`、`Tools/*.swift`；**逐字 schema 冻结**在 `Tests/LightamerTests/McpFinalSnapshotTests.swift`（34 键集）与各 domain snapshot。
- 域：editing 11、culling 14、search/state 3、project 3、control 3。
- 需 `requiresControl` 的 14 个：`load_image`, `apply_params`, `paste_adjustments`, `export_image`, `refine_masks`, `set_rating`, `set_flag`, `set_color_label`, `append_note`, `set_keywords`, `apply_preset`, `match_color`, `project_open`, `project_create`。`McpControlToolsetTests.controlCandidateTools` 的 13 名单是 `refine_masks` 之前的陈旧集（测试只断言候选被 gate，不排除额外 gate）；运行时实际 14。
- 参数与只读/破坏提示见 TABLES §G；实现不得改 schema 字节，否则 `McpFinalSnapshotTests` 失败。

### 4.6 Export product metadata

- 正本：`Export/ExportMetadataPolicy.swift`、`Export/ExportEncoder.swift`、`Export/ImageIOEncoders.swift`、`Export/ExportICCStrip.swift`、`Export/DrtOutputColorSpace.swift`、`Export/ExportFileNameTemplate.swift`。
- `ExportMetadataPolicy`：`mode ∈ {standard, none}` + 6 bool（`includeExif/includeXMP/includeIPTC` 默认 true；`includeLocation/includeSerials/includeEditingHistory` 默认 false，固定剥离）。EXIF `Software` 只写 `{TIFF}` 字典；已知空间（sRGB）零 profile payload；ICC 剥离是 post-encode（JPEG APP2/PNG iCCP/TIFF 34675）。
- DRT 输出：`DrtOutputColorSpace` 由 space×EOTF 决定 ICC；HDR 走 `ITUR_2100_PQ/HLG`，SDR 自建 ICC v4 字节（Bradford D50 + chad + curv-1）；peak 不写 ICC，由 `ExportVariant.validate` 闸门/容器承载；六格式矩阵 = JPEG/PNG/TIFF/HEIF/AVIF/WebP，位深/质量键冻结。
- 命名模板 11 token（`ExportFileNameTemplate`）；输出目录记忆 `export.lastDirectory`；冲突档 `increment/fail/replace`。

## §5 Test inventory

| Target | 文件 | 方法（实计） | 性质 | 可直接作 Rust 对照？ |
|---|---:|---:|---|---|
| `LightamerTestsIOPParity` | 84 | 587 | kernel golden/parity（图像/平面比较） | 是（需 GPU 或 CPU 参考；输入 fixture 可复现） |
| `LightamerTestsIOP` | 100 | 843 | iop 行为 + 数学 + golden | 是 |
| `LightamerTestsLayers` | 67 | 576 | 图层/蒙版/retouch | 是（蒙版 kernel 需 Metal） |
| `LightamerTestsLibrary` | 83 | 802 | `.lalb`/导入/搜索/分析（含 3 个 BUNDLE-MAP 未登记但 Project.swift 归 LIB 的测试） | 是 |
| `LightamerTestsSessions` | 26 | 289 | session 索引/过滤/缩略图 | 是 |
| `LightamerTestsExport` | 40 | 391 | 编码/DRT/元数据/命名 | 是（文件字节级） |
| `LightamerTestsApp` | 127 | 1,135 | `EditorState`/UI 模型/面板/宿主 | 多数否（需 App 状态或 UI） |
| `LightamerUITests` | 1 | 3 | XCUITest 启动/可访问性 | 否 |

- 上表 7 个单测 target = `LightamerTests` 的 527 文件 / 4,623 方法；加 3 个零测试 SHARED helper（`Fixtures`/`ParityGate`/`ChainBuilderHelpers` 跨 target 重复列出）= 530 文件。`LightamerUITests` 的 1 文件 / 3 方法为独立 suite，不计入 4,623。BUNDLE-MAP 的 method 列合计 4,550（文件头基线 2,165 已多次追加，行内数滞后），**以实计为准**；3 个 BUNDLE-MAP 未登记文件在 `Project.swift` 归 `LightamerTestsLibrary`，已计入该行。IOP 两行按 `Project.swift` 归属（`LutEncodingExpansionTests` 在 IOPP block），BUNDLE-MAP 的 83/581 + 101/849 是陈旧归属。
- 直接对照候选：**400 文件 / 3,455 方法**（非 APP target 且无 SwiftUI/AppKit import）；其中 **233 文件 / 2,121 方法** 不 import Metal，可纯 CPU 跑。Golden/Parity 命名 **61 文件 / 429 方法**（Golden 28/204，Parity 34/230，1 文件重合）。
- 依赖：211 文件 import Metal；99 import CoreImage；30 import ImageIO；4 import Vision；4 import CoreML；20 文件 import SwiftUI/AppKit（列表见 TABLES §I）。
- 不能直接当对照的典型：`EditorState`/`LayerEditingState`/`VersionCoordinator` 行为测试（依赖 App 单例与 `@Observable`）、`SheetEnvironmentInjectionTests`/`ToastFaceTests`（真 SwiftUI 挂载）、`NSMenuParityTests`/`ThemeTokensTests`（AppKit 外观）、3 个 XCUITest。

## §6 Rewrite difficulty (estimate)

| 档 | 文件 | 行 | 内容 |
|---|---:|---:|---|
| 纯逻辑 | 197 | 59,720 | 数据结构、JSON/sidecar、SQL、哈希、色彩数学、预设、管线编排、MCP 协议/工具、AI 文本/协议 |
| 着色器宿主 | 118 | 43,225 | 105 IOP Swift + Core Metal/Pipe/Mask/Retouch/Film/Drt/Terminal/Input 宿主 + App `PipeCoordinator`/缩略图 Metal 部分 |
| Apple 适配 | 66 | 31,221 | RAW/raster 解码、CI/ImageIO 编码、色彩、Vision、CoreML、CoreText、iOSurface/CVPixelBuffer |
| UI 耦合 | 50 | 21,884 | SwiftUI View、AppKit 面板/菜单/屏幕、`@Observable` 状态模型（需拆薄壳） |
| **合计** | **431** | **156,050** | 估：±10–15%（边界文件归类见 §7） |

- 逐模块主导档 + 混合行数见 TABLES §J。Core 主导档：纯逻辑 12 目录、Apple 适配 3（Decode/Export/Metal）、着色器宿主 1（Layers）；其中 AI/Foundation/Library/Pipe/Session/Sidecar/Stack 以纯逻辑为主但含 Apple/Metal 混合行。IOP 的 54 个目录全部归着色器宿主（逐目录行数见 §B，不再逐行重复标档）；App MCP = 纯逻辑，App 其余 = UI 主导。
- 重写工作量不等同于行数：着色器宿主 43.2k 行里 MSL 13.3k 原样保留，Rust 侧主要是 PSO/纹理/uniform 绑定，属于机械但高密度的移植；Apple 适配 31.2k 行是边界最厚、最需要行为对齐的部分（尤其 CI 色彩、ImageIO 元数据、Vision/CoreML）。[推断]
- 纯逻辑中可直接先行的低风险块：`Foundation/StableHash`、`Sidecar`、`LibrarySchema`/`Catalog`、`Presets`、`Graph`、`Film` 数学、`ColorMatch`、`Stack` 的纯算法、`MCP` 协议/工具层。

## §7 Not found / limits

- 未逐行审计 156k 行的业务语义；Q1 的职责来自文件头注释与公开类型名，不是行为规格。
- Q2 的“处”是符号文本命中数，不等于运行期调用次数；`CIImage`/`MTL*` 在桥接处会重复计数。
- Q3 的线程组只按 host 的 `MTLSize` 字面统计；动态计算的 `MTLSize(width: ..., height: ...)` 未逐 shader 还原，故只给默认值与字面分布。
- Q3 的宿主列是“引用该 kernel 名/同目录模块”的映射；`BlendOp`、`Lut3d`、`Mask*`、`Terminal` 存在跨目录宿主，已在表中注明。
- MCP 的参数表只列主参数/必填面；逐字 JSON Schema 以 `McpFinalSnapshotTests.swift` 为唯一正本，本盘点未逐字节抄录全部 34 个 schema。
- `CMProfile/CMWorld` 全仓 0 命中，但不排除 Core Image 内部使用 ColorSync；这是“我方代码直接调用”的口径。
- Q6 四档是文件级主导依赖启发式：`MetalContext` 归 Apple 适配、`PixelPipe` 归 Apple 适配、`PipeCoordinator` 归 UI 耦合，均存在跨档成分；行数合计因此只能当量级，不是精确预算。
- **范围说明**：§0–§6 的 431/156,050 严格等于用户指定的 Core + IOP + 7 个 App 目录；`App/Sources/Lightamer/Catalog`（4/1,229）、`Settings` 非 UI 模型（3/818）、`EditorState+FilmMigration.swift`（77）未纳入基线，单列于 §1.5；纳入后 439/158,174（纯 +320、UI +1,804）。
- 未测任何性能/内存；本 lane 不构建、不跑测试、不开 GUI。
- 用户实拍照片库未读取、未列目录；样张相关结论不在本盘点范围。

## §8 Review revisions（独立 omp 复审，2026-11-25）

复审结论：`FAIL / 2 error + 8 minor`；以下逐条回注（原始输出见 `core-review.log`）。

| # | 级别 | 复审 finding | 修订 |
|---|---|---|---|
| 1 | ERROR | MCP 需控制权实为 14（`refine_masks` 也注册 `requiresControl: true`），正文写 13 | §0、§4.5 改 14；补 `refine_masks`；注明 `McpControlToolsetTests.controlCandidateTools` 的 13 是陈旧候选集 |
| 2 | ERROR | “App 非 UI 目录 94/38,442”未含 App/Catalog、Settings 非 UI 模型、EditorState+FilmMigration，100% 合计表述过强 | 新增 §1.5 scope addendum（Catalog 4/1,229、Settings 3/818、扩展 77 = 2,124；纳入后 439/158,174）；§0 标注“本 lane 口径”，§7 加范围说明 |
| 3 | MINOR | IOPParity/IOP 按 BUNDLE-MAP 83/581、101/849，按 Project.swift 为 84/587、100/843 | §5/TABLES I.1 改 84/587、100/843，注明 `LutEncodingExpansionTests` 归属差 |
| 4 | MINOR | 530 文件列和 524+3 差 3 个 SHARED helper；未映射 3 实际归 LIB | §5/TABLES I.1 补 3 helper 与 LIB 归属说明 |
| 5 | MINOR | `read_write` 写 2 文件，实际声明仅 SpectralSpatial；literal 提及 11 | §3 改“实际声明 1 文件 + 10 文件注释记录”，§E.2 GaussianBlur 行改注释说明 |
| 6 | MINOR | CoreML 28 是排除 `MLModelRunner` 的符号口径；字面 `MLModel` 32/3、import 7 | §0/§2/§D 标注口径：28 符号 / 32 字面 / 7 import |
| 7 | MINOR | §K 的 `find .` 把 `.work` 内 shader 算进来（75/13,370/188） | §K 命令加 `-not -path './.work/*'`，kernel 统计限定产品树 |
| 8 | MINOR | UserDefaults 漏 `mask.behavior.default` 等邻近键 | §4.4/§F 补邻近 4 键（不计入 37），标明 7 目录范围 |
| 9 | MINOR | Parity 名单含不存在的 `SofteningParity`/`WhiteBlackParity`，漏 `TemperatureParity`/`UprightModuleParity`/`VibranceVelviaParity` | TABLES I.2 名单修正 |
| 10 | MINOR | Metal 1,485 是词界口径，plain 1,488；§K 命令统计行数而非处数 | §D 标“词界 `\bMTL[A-Z]`；plain 1,488”；§K 说明 grep 统计口径 |

> 复审覆盖：总量/73 shader 逐行/12 族依赖/契约/测试分布逐项重跑；未逐文件重跑四档、未逐列核 `.lalb` DDL、未逐字节核 34 MCP schema（见 §7）。
