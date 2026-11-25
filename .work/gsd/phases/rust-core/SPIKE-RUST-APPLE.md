# SPIKE-RUST-APPLE — 非 UI 用 Rust 调 Apple 四能力的可行性实测

- 日期：2026-11-25
- 机器：Apple M4 / macOS 27.3 (26C5035r) / 10 核 / 16GB
- 工具链：rustc 1.100.0 (0ef1bc386 2026-11-09)，Swift 6.4 (swiftlang-6.4.0.34.1)，Xcode SDK macOS 27.3
- 机器守卫（构建前，`Scripts/machine-guard.sh` 原样输出）：`GUARD PASS (heavy=0 free=62% swap=?M disk=?GB)`
- 工作区：`/Volumes/UNITEK/Documents/Development/Lightamer-rust-spike/`（仓外）
- 纪律：未开图形窗口、未合成输入事件、未读用户照片库；产品树零改动；零 commit / 零 push。样张全部来自 `~/Library/Application Support/Lightamer/TestRAW/`。

## §0 结论表

| 项 | 结论 | 一句话证据 |
|---|---|---|
| S1 CIRAW | **跑通** | Rust 经 `objc2-core-image` 调用 `CIRAWFilter`：9504×6336、RGBA16Float、支持解码器 `["7","8","9"]`；5 次「解码+渲染+读回」中位 **945.7 ms**；rawspeed→内存 DNG→CIRAW 中位 **398.6 ms** |
| S2 Vision | **有保留地跑通** | `VNDetectFaceRectanglesRequest` 从 Rust 跑通、完成回调经 mpsc 回主线程（回调线程 ThreadId(3)）；但 CC0 样张 9/9 均无脸 → 人脸框比对是 0/0，另用 `VNDetectRectanglesRequest` 得 1 个非空框与 Swift 完全一致 |
| S3 ImageIO + ColorSync | **跑通（ICC payload 有保留）** | JPEG/HEIC/AVIF 三格式编码成功；sRGB 读回 profileName 但**不写 ICC payload**（JPEG 无 APP2、HEIF/AVIF 用 nclx），非标准 ROMM ICC 补测则真写入（JPEG APP2 / HEIC prof）；ColorSync 输出与 Swift 参照**逐字节相同**（sha256 `88cffad7…`） |
| S4 Metal 着色器 | **跑通** | 仓库原样 `Passthrough.metal` + `ExposureKernels.metal` 在 Rust 运行时编译、派发、读回；与 Swift 参照输出**逐字节相同**（sha256 `b0e01d2f…`，793,616 B） |
| S5 UI/核心桥 | **跑通** | UniFFI 0.32.2：同步、async（返回 42）、事件回调（Rust 线程回调 Swift）全通；`MTLTexture` 以 u64 指针过桥、无图像序列化；Rust `replaceRegion` 写首行（一次 API 拷贝），Swift `getBytes` 读回（再一次），首像素 `[12,200,77,255]` |

### 直接回答

**不必全用 Swift。** 四项 Apple 能力都能由 Rust 直接驱动：CIRAW（Core Image）、ImageIO、ColorSync、Vision 均有可用绑定或可用手写 `extern` 补齐的最小表面；本机实测全部跑通，两项逐字节对照（S4 渲染、S3 色彩变换）通过。**UI 层原生 Swift 足够**，非 UI 核心可以是 Rust。

但有三个限定：

1. **「复用现有 Metal 着色器」只在 Metal 后端成立。** MSL 是 Apple 专属资产；换 UI 不影响它，但换平台（Linux/Windows）必须另写 WGSL/SPIR-V 或做翻译层。Rust 宿主能原样跑 MSL，不等于着色器可移植。
2. **四项能力本身仍把核心钉在 macOS。** Rust 只是去掉了「必须 Swift」这一层，没有去掉「必须 Apple 框架」这一层。要跨平台，必须把它们关在 trait 后面并准备第二实现（lcms2 / rawspeed / image-rs / ONNX 等）。
3. **CIRAW 不是唯一解码路径，而且不是最快。** rawspeed→内存 DNG→CIRAW 把端到端时间从 945.7 ms 压到 398.6 ms（本机、本样张），代价是 122 MB 内存 DNG 与 rawspeed 的 C++ 依赖。

## §1 逐项细节

### 公共部分

- 直接依赖（`Cargo.lock` 在源码目录）：`objc2 0.6.5`、`objc2-foundation 0.3.2`、`objc2-core-foundation 0.3.2`、`objc2-core-graphics 0.3.2`、`objc2-metal 0.3.2`、`objc2-core-image 0.3.2`、`objc2-image-io 0.3.2`、`objc2-vision 0.3.2`、`block2 0.6.2`、`libc 0.2.191`、`cc 1.11.3`（build-dep）、`uniffi 0.32.2`。
- 许可证：objc2 / objc2-foundation / block2 = MIT；objc2 框架绑定（metal/core-image/image-io/vision/core-graphics/core-foundation）= Zlib OR Apache-2.0 OR MIT；uniffi 全家 = **MPL-2.0**（文件级弱 copyleft，链接不传染，改动 uniffi 自身源码才需公开）；cc/libc = MIT OR Apache-2.0。
- 传递依赖：完整解析图与锁定版本见 `SPIKE-RUST-APPLE-src/Cargo.lock`；uniffi 系 8 个 crate（uniffi/uniffi_bindgen/uniffi_core/uniffi_macros/uniffi_meta/uniffi_pipeline/uniffi_udl/uniffi_internal_macros）均 0.32.2 / MPL-2.0；构建期 askama 0.16.1、serde 1.0.229、syn 2/3、toml 1.2.3 等为 MIT OR Apache-2.0；`unicode-ident` 为 MIT/Apache + Unicode-3.0。
- 代码量（自写，不含拷贝的 shader/shim）：Rust 1,120 行（`src/s1 122`、`src/s1r 194`、`src/s2 142`、`src/s3 300`、`src/s4 172`、`bridge/src/lib.rs 154`、`build.rs 33`、bindgen bin 3）；Swift 参照 227 行（6 个程序）。
- 所有 GPU 工作离屏；S4/S1 用 `MTLTexture` + compute/render，无 `MTKView`、无窗口。

### S1 — Rust 调 CIRAW

**直接路径**（`src/s1/main.rs`）：

- `CIRAWFilter::filterWithImageURL` + `setDecoderVersion(CIRAWDecoderVersion8)`；`supportedDecoderVersions` 实测 `["7", "8", "9"]`。
- Metal 设备上建 `CIContext::contextWithMTLDevice`，`render:toMTLTexture:commandBuffer:bounds:colorSpace:` 渲染到 `RGBA16Float`（extended linear sRGB），自建 command buffer 提交并 `waitUntilCompleted`，`getBytes` 读回。
- 尺寸：`nativeSize` = **9504 × 6336**（A7R5，61MP）；渲染目标 481,738,752 B。
- 计时口径：每轮新建 filter（含完整解码）+ 渲染 + 回读，`Instant` 墙钟；5 轮取排序后第 3 个。

| 轮 | filter 创建 | 解码+渲染+读回 |
|---|---|---|
| 1（冷） | 49.4 ms | 1896.0 ms |
| 2 | 82.1 ms | 945.7 ms |
| 3 | 55.4 ms | 1089.4 ms |
| 4 | 50.7 ms | 855.2 ms |
| 5 | 50.8 ms | 835.6 ms |
| **中位** | ~50.8 ms | **945.7 ms** |

注：945.7 ms **包含**约 481 MB 的 GPU→CPU 回读；纯预览不读回会更低。上一轮 Swift 的 868–968 ms **不是同口径**（fit 2560 + sRGB RGBA8；本轮 9504×6336 + RGBA16Float + 481 MB 回读），只能作量级参照，不能据此断言「无额外解码开销」。删 `target/` 后用保留的可执行文件复跑一次，中位 890.4 ms（暖机；`evidence/rerun-after-cleanup.log`），同量级。

**rawspeed → 内存 DNG → CIRAW**（`src/s1r/main.rs`，shim 原样复用 `.work/gsd/phases/rawspeed-backend/spike-src/` 的 `rawspeed_shim.cpp/.h` + `dngwriter.h`，经 `cc` crate 编入）：

- rawspeed 报告：`SONY ILCE-7RM5`、mosaic 9568×6376、CFA、black 512 / white 15360。
- `rs_build_dng` 在内存生成未压缩 CFA DNG **122.0 MB**；`CIRAWFilter::filterWithImageData_identifierHint(..., "DNG")` 直接吃内存，**不落临时文件**。
- DNG 支持的解码器版本：`["6.dng", "7.dng", "8.dng", "9.dng"]`；设 `8` 后实际生效 **`8.dng`**（不是 `8`）。
- 5 轮（release 构建）：

| 轮 | rawspeed | DNG 构建 | CIRAW filter | render+readback+488MB alloc/zero+tex create | 总计 |
|---|---|---|---|---|---|
| 1（冷） | 47.1 ms | 24.4 ms | 99.9 ms | 359.3 ms | 538.4 ms |
| 2 | 54.9 | 50.3 | 14.6 | 294.6 | 431.5 |
| 3 | 62.8 | 11.1 | 11.9 | 306.4 | 398.6 |
| 4 | 54.0 | 11.0 | 14.1 | 294.4 | 382.4 |
| 5 | 54.1 | 10.7 | 11.8 | 312.7 | 395.5 |
| **中位** | **54.1** | **11.1** | **14.1** | **306.4** | **398.6 ms** |

注：`总计` = 端到端，含 `rs_fill_info` 等未单列项，故中位不等于各列之和（54.1+11.1+14.1+306.4=385.7）；`rawspeed` 列每轮重建 `CameraMetaData`（含 cameras.xml 解析），与上一轮 34–57 ms 的「解码段」非严格同口径；S1 与 S1r 的分配/读回结构也不同构。删 `target/` 后复跑一次：中位 356.4 ms（`evidence/rerun-after-cleanup.log`），同量级且更快。

结论：rawspeed 只解决「解码」，CIRAW 仍要做 demosaic+渲染（~300 ms）。即使走 DNG，CIRAW 的渲染成本仍是主项；对 60MP 预览，本轮复跑比直开 ARW 快 2.4–2.5×（945.7/398.6、890.4/356.4；上一轮 full-res harness 为 1.9×，口径不同）。稳态多 122 MB DNG；峰值未实测，按代码至少 2–3 份 122 MB 并存（shim 结果 `malloc`、`NSData` 复制、rawspeed 原始平面），见 §4。rawspeed 数字与此前 spike 的 34–57 ms 一致。

### S2 — Rust 调 Vision

`src/s2/main.rs`：

- 在主线程建 `std::sync::mpsc` channel，工作线程用 `VNImageRequestHandler::initWithURL_options` + `VNDetectFaceRectanglesRequest::initWithCompletionHandler`。
- 完成回调（Objective-C block，经 `block2::RcBlock`）把「回调触发 + results 数」送回 channel；主线程 `recv` 打印。实测：worker `ThreadId(2)`，**回调在 `ThreadId(3)`**，主线程收到消息——回调确实回到 Rust 通道且不在主线程。
- 结果坐标在工作线程读 `VNFaceObservation.boundingBox`，排序后写 `out/s2-rust.txt`；Swift 参照（`swift-refs/s2_ref.swift`）同图同请求写 `out/s2-swift.txt`，`diff` **完全一致**。
- **保留项**：`TestRAW/` 9 个 CC0 样张全部 0 张人脸（`face_probe.log`），所以人脸比对是 0/0，只证明「空结果 + 通道」而非「坐标编组」。为补非空证据，同一 handler 追加 `VNDetectRectanglesRequest`（项目 Ashift 也用，`LightamerIOP/Sources/Ashift/VisionDetect.swift:52`；本次仅作非空对照）：Rust/Swift 均 1 框，坐标 `0.232867,0.065037,0.251476,0.171964`，逐字符相同。ColorChecker.ARW 为输入。

### S3 — Rust 调 ImageIO 与 ColorSync

`src/s3/main.rs`：

- 用系统 `sRGB Profile.icc`（3144 B）经 `CGColorSpaceCreateWithICCData` 建色彩空间，`CGImage` 64×48 RGBA8（premultiplied last）。
- `CGImageDestinationCreateWithData` + `CGImageDestinationAddImage` + `Finalize`：
  - JPEG `public.jpeg` → 1,810 B
  - HEIC `public.heic` → 1,291 B
  - AVIF `public.avif` → 1,160 B（macOS 27 原生写入可用）
- 三格式 `CGImageSourceCopyPropertiesAtIndex` 读回 `kCGImagePropertyProfileName` = **`sRGB IEC61966-2.1`**，`CGImageGetColorSpace` 名 = `kCGColorSpaceSRGB`，尺寸 64×48。**但这不等于 ICC payload 被写入**：嵌入形式由图像色彩空间决定；sRGB 是系统已知空间，实测 `s3.jpg` 无 APP2 `ICC_PROFILE`，`s3.heic`/`s3.avif` 的 `colr` 为 `nclx` 而非 `prof`。
- 补测（Swift 探针 `icc_embed_probe.swift`，同一 ImageIO 调用形态）：改用非标准 `ROMM RGB.icc` 后，JPEG 出现 APP2 `ICC_PROFILE`、HEIC 出现 `prof` box。结论：嵌入能力在，sRGB 被折叠为已知空间；Rust 侧未重跑该补测（见 §4）。
- ColorSync：手写 `extern` 声明 `ColorSyncProfileCreateWithURL` / `ColorSyncTransformCreate` / `ColorSyncTransformConvert`（`#[link(name = "ColorSync", kind = "framework")]`），profile 序列必须是**字典数组**（`kColorSyncProfile` + `kColorSyncRenderingIntent` + `kColorSyncTransformTag`，源 `DeviceToPCS`、目标 `PCSToDevice`），直接传 profile 数组会返回 NULL（Swift 同样失败；首轮失败输出未留档，成功轮见 `cs_probe.log`）。
- 变换：sRGB ICC → Display P3 ICC，16×16、float32、3 通道、AlphaNone、相对色度。输出 3,072 B 与 Swift 参照 `ColorSyncTransformConvert` **逐字节相同**（sha256 `88cffad7…`），源缓冲也逐字节相同（`58494c24…`）。

### S4 — Rust 宿主跑现有 Metal 着色器

`src/s4/main.rs` + `swift-refs/s4_ref.swift`：

- 从仓库**原样拷贝**（未改一字节）：`Passthrough.metal`（sha256 `46748a37…`）与 `ExposureKernels.metal`（`f2b806a8…`）。
- Rust 用 `newLibraryWithSource` 在运行时编译两个文件拼接的 MSL；`pass_through` 带两个 function constants（`useSrgbGamma=false`、`exposureEV=0.5`），再串 `exposure_apply`（black=0.02、scale=1.35），257×193 RGBA32Float，16×16 线程组，读回。
- Swift 参照用同样输入文件（`s4-input.bin`，由 Rust 生成并由两边共同读取，排除输入分叉）、同样常量与派发。输出 793,616 B，`cmp` **IDENTICAL**，双方 sha256 均 `b0e01d2f…`；首像素 `[-0.027000, -0.027000, -0.023286, 1.0]` 两边一致。
- 说明：仓库 `LightamerIOP/Sources` 有 59 个 `.metal`，全仓 75 个 / 13,370 行；本次只验证 2 个代表（1 个无参 + 1 个带 uniform），未全量编译。`LevelsKernels.metal` 依赖 `../Common/LabMath.h`，拷贝时必须连同头文件保持相对路径；本次按「只拷不改」选了自包含的 Exposure。

### S5 — UI 与核心之间的桥

- `bridge/src/lib.rs`（UniFFI 0.32.2，proc-macro 模式，`crate-type = ["cdylib","staticlib"]`）：
  - 同步 `ping(name:)` → `pong:swift from rust aarch64 on ThreadId(1)`
  - 异步 `slow_add(20,22)` → `42`（runtime-free timer future：首次 poll 返回 Pending，定时线程 wake；不引入 tokio）
  - 事件：`EventListener` callback interface + `set_listener` / `fire_event`（Rust 线程回调）；Swift 侧 `Listener.onEvent` 收到 `hello (thread ThreadId(3))`
  - 纹理：`texture_info(texture_ptr: u64)` 用 `Retained::retain` 从裸指针取回 `MTLTexture`，读 `width/height/pixelFormat`；`paint_texture` 直接 `replaceRegion` 写入首行。Swift 打印 `32x16 pixelFormat=70`（RGBA8Unorm），读回首像素 `[12,200,77,255]`。**口径修正**：跨 FFI 只传 `u64`、无图像序列化；Rust `replaceRegion` 与 Swift `getBytes` 各是一次 API 拷贝，且只写/读首行。程序早期打印的 `ZERO-COPY …` 标签已改为 `TEXTURE POINTER PATH OK`（旧证据日志保留原字符串）。
- 桥选型：**UniFFI 跑通，swift-bridge 未试**（按任务「不行再试」的条件，UniFFI 已满足）。生成命令 `uniffi-bindgen generate --library liblightamer_bridge.dylib --language swift`；Swift CLI 由 `swiftc -parse-as-library` 链接生成绑定 + 静态/动态库，纯命令行、无窗口。
- 已知坑：UniFFI 生成的 C 头里 self 句柄参数名固定为 `ptr`，导出方法若有同名参数 `ptr` 会生成 `uint64_t ptr, uint64_t ptr` 重定义（原始编译输出未留档，错误文本见文末修订记录）；改名为 `texture_ptr` 即解。异步若在方法里用 `tokio::time::sleep`，UniFFI 不会自动建 tokio reactor，会 panic `there is no reactor running`；要么自带 runtime，要么用 runtime-free future。

## §2 绑定缺口与解法

| 缺口 | 现象 | 解法 |
|---|---|---|
| ColorSync 无 objc2 绑定 | 全仓无 `ColorSync` crate；项目实际也主要走 `CGColorSpace` 而非 `CM*` | 手写 3 个 ColorSync 函数 + 6 个 `CFStringRef` 静态符号 + `CFRelease` + 3 个 CG/CF 函数（`CGColorSpaceCreateWithICCData` / `CGColorSpaceRelease` / `CFStringGetCString`），共 13 项；CF 容器用 `objc2-core-foundation` 的 `CFArray`/`CFDictionary` |
| ColorSync profile 序列格式 | 直接传 `[profile, profile]` 返回 NULL（Rust 与 Swift 同败） | 必须传字典数组：`kColorSyncProfile` + `kColorSyncRenderingIntent` + `kColorSyncTransformTag`（源 `DeviceToPCS`、目标 `PCSToDevice`） |
| `CGColorSpaceCreateWithICCData` 的 `&CFType` 参数 | `CFData` 无 `AsRef<CFType>`，类型层不好接 | 手写同签名 `extern` 用 `*const c_void` 传入；或在类型绑定上把 `CFData` 指针强转为 `&CFType`。本次选手写 |
| `CFString` → Rust `String` | 读回 profile 名需要 CF→UTF8 | 手写 `CFStringGetCString` + 固定缓冲；也可用 `CFString: Display`（绑定已提供） |
| Vision `boundingBox` 的归属 | 泛型 `VNRequest::results()` 返回 `VNObservation`，该类型没有 `boundingBox`；方法在 `VNDetectedObjectObservation` | 用具体请求的 typed `results()`（`VNFaceObservation` / `VNRectangleObservation`）读框 |
| Metal 常量设置 | `setConstantValue_type_atIndex` 要 `NonNull<c_void>` 而非裸指针 | `NonNull::new_unchecked`；`MTLCreateSystemDefaultDevice` 已返回 `Option<Retained<_>>` |
| Metal 纹理读回/上传 | `getBytes` / `replaceRegion` 同样要 `NonNull<c_void>` | 同上 |
| UniFFI 参数名冲突 | 导出方法参数名为 `ptr` 时，生成 C 头自我重定义 | 参数改名（`texture_ptr`） |
| UniFFI 异步运行时 | `tokio::time::sleep` 在无 reactor 时 panic | 自写 timer future（Pending + Waker），核心不依赖 tokio |
| `cidre` / `metal` crate | 已查存在（cidre 0.30.1、metal 0.33.0），未采用 | objc2 家族覆盖全部所需 API，少一层封装；cidre 可作为备选但未实测 |
| swift-bridge 0.1.59 | 未试 | UniFFI 已跑通三件套 + 指针传递，无需第二方案 |

## §3 对架构的含义

### 每项能力收在什么接口后面

- **解码**：`trait RawDecoder { fn open(path) -> DecodedFrame; fn decode(&self, opts) -> Plane; }`。`DecodedFrame` 只暴露尺寸/CFA/黑电平/白电平/矩阵/WB 与 float32 平面，不暴露 `CIRAWFilter`/`CIImage`。macOS 实现可二选一：CIRAW（短路径、Apple 质量）或 rawspeed→DNG→CIRAW（本轮复跑快 2.4–2.5×、稳态多 122 MB，见 §1/§4）。其它平台实现 = rawspeed 直出 + 自写 demosaic，或 LibRaw。
- **导出**：`trait ImageEncoder { fn encode(&self, frame, spec) -> Vec<u8> }`，`spec` 含格式/位深/质量/ICC/元数据策略。macOS 实现 = ImageIO（JPEG/PNG/TIFF/HEIC/AVIF）+ libwebp；其它平台 = image-rs/libwebp/libavif。**不要让 `CGImageDestination` 出现在核心 API 上**。
- **色彩**：`trait ColorTransform { fn transform(&self, src_icc, dst_icc, pixels) }`。macOS 可选 ColorSync（逐字节对照已过）；跨平台实现 = lcms2（Rust 绑定或 C）。工作空间仍是 linear Rec2020 float32，ICC 只在出入口出现；ColorSync 不应成为像素管线内部的每步依赖。
- **AI**：`trait FaceDetector` / `trait MaskRefiner`（项目实际用到 5 类 Vision 请求，见 §4）。macOS 实现 = Vision；其它平台 = ONNX Runtime / tract。返回值必须是纯 Rust 结构（框、点、mask 平面），不返回 `VNObservation`。
- **GPU**：`trait ShaderBackend` 只暴露「编译源码/派发/读回」，不暴露 `MTLDevice`。macOS 实现 = Metal；其它平台 = wgpu。**MSL 源码本身不可跨平台**，跨平台时要么维护第二套 shader，要么引入 SPIRV-Cross 类翻译；这是四项能力之外、但同样影响「核心可移植」的硬约束。

### 边界与生命周期

- 本次 S5 证明 `MTLTexture` 指针可以作为 `u64` 过 UniFFI，Rust 侧 `Retained::retain` 后直接读写，**无图像序列化**（`replaceRegion`/`getBytes` 各一次 API 拷贝）。它只在**同进程、同地址空间**成立；契约必须写死：Swift 持有所有权，Rust 只借用，调用期间不得释放；跨进程/跨沙盒不可用。跨平台时应改为共享内存句柄（IOSurface / dma-buf / 共享纹理）而不是裸指针。
- UI↔核心的稳定接口建议以「命令 + 事件」为主（UniFFI object + callback interface），不要每帧传 `CIImage`/`MTLTexture` 对象；纹理/帧缓冲用句柄 + 显式生命周期方法，避免 ARC 与 Rust 所有权互相踩。
- 桥的许可证：UniFFI 是 MPL-2.0。动态链接/生成绑定不要求开源本方代码；若修改 UniFFI 自身源码需公开修改。对 GPL-3.0 项目兼容。

### 结论性建议

- 短期：Rust 核心 + Swift/AppKit UI 可行；四项能力全部留在 macOS 实现层，接口按上面的 trait 切。
- 中期：rawspeed 是解码主路径的候选，但**先完成 rawspeed→DNG 的色彩/几何标定**（同目录 `rawspeed-backend/SPIKE.md:262` 记录 P1/P0 位图 `mean_abs_diff 22.8/255`、P1 偏青），并处理 **LGPL-2.1** 的动态链接/可重链接义务；CIRAW 作为质量/兼容兜底。导出与色彩先留 macOS 实现，跨平台时再补第二实现。
- 长期：真正的跨平台瓶颈不是「Rust 能不能调 Apple」，而是 **Metal 着色器与 Apple 解码/色彩质量**；这两项要有第二实现或翻译层，不能靠 UI 换层解决。

## §4 没验证的

- **人脸非空比对**：CC0 样张无人脸，S2 的人脸结果是 0/0；只有矩形检测是非空对照。项目实际用到 5 类 Vision 请求（`VNDetectFaceRectanglesRequest`、`VNDetectFaceLandmarksRequest`、`VNDetectRectanglesRequest`、`VNDetectHorizonRequest`、`VNGeneratePersonSegmentationRequest`），本次只测前两类中的 face rectangles 与 rectangles，horizon / landmarks / 人像分割未测。
- **Vision 性能**：只测正确性与通道，未测耗时、未测 60MP 大图。
- **ICC payload**：sRGB 三格式未写 ICC payload（nclx/标准空间标记）；非标准 ROMM ICC 只在 Swift 探针里验证过嵌入（JPEG APP2 / HEIC prof），Rust 侧未重跑，也未测 AVIF 的 `prof` 与自定义 ICC 的读回名。
- **AVIF 像素正确性**：仅验证可编码/可读回元数据，未验证 10/12-bit、HDR、CICP、解码像素。
- **ColorSync 覆盖**：只测 3 通道 float32、相对色度、sRGB→P3、16×16；未测 alpha、16-bit、CMYK、绝对色度、软打样。
- **CIRAW 覆盖**：单文件（A7R5）、单机（M4）、只测 v8；未测 v9、未测其它相机、未测 EDR/HDR 输出、未测 draft mode。
- **rawspeed 构建与色彩**：复用兄弟 spike 工作区已编好的 `librawspeed.a`，本次未从源码重编；rawspeed 为 **LGPL-2.1**（静态链接需可重链接能力），本次未做法务复核。rawspeed→DNG 输出的色彩/几何**未与 CIRAW 直开比对**；既有证据 `rawspeed-backend/SPIKE.md:262` 记 `mean_abs_diff 22.8/255`（P1 偏青），本次未复核。内存峰值未测 RSS。
- **Metal 覆盖**：只 2 个 kernel、运行时源码编译；未全量编译 75 个 `.metal`，未测预编译 metallib、未测 PSO 缓存、未测 100MP。
- **S5 覆盖**：只 UniFFI；swift-bridge 未试；未做 XCFramework 打包、签名、沙盒、跨语言异常/取消；async 只测一个 20 ms timer；指针只测同进程；纹理只写/读首行，整纹理与每帧路径未测；`replaceRegion`/`getBytes` 各含一次 API 拷贝，不是字面意义的零拷贝。
- **跨平台**：完全没有 Linux/Windows 构建或运行证据；trait 分层是设计建议，不是实测结论。
- **UI**：按要求未开窗口，AppKit 只作为「未来 UI 层」讨论，未写任何 UI 代码。

## §5 工作区保留内容与大小

仓外工作区 `/Volumes/UNITEK/Documents/Development/Lightamer-rust-spike/`：

| 路径 | 内容 | 大小 |
|---|---|---|
| `Cargo.toml` / `Cargo.lock` / `build.rs` | workspace + rawspeed shim 构建 | 27 K |
| `src/s1` `src/s1r` `src/s2` `src/s3` `src/s4` | 五个 Rust 宿主 | 48 K |
| `bridge/` | UniFFI 库 + bindgen bin | 16 K |
| `csrc/` | rawspeed shim 源码（自仓库原样拷贝） | 28 K |
| `shaders/` | 两个 `.metal`（自仓库原样拷贝） | 8 K |
| `swift-refs/` | 5 个 Swift 参照/探针 | 20 K |
| `out/` | 全部可执行（Rust 五个 + Swift 参照 + s5 + 依赖 dylib）、生成的 Swift 绑定、对比产物（S4/S3 二进制、S2 txt、三格式图片） | 12 M |
| `logs/` | 全部运行日志 | 44 K |

- `target/` 构建目录实测 **2.2 GB**（`du -sh target`，>2 GB；删除前未把 du 输出留档），按要求**已删除**；`out/bin/` 保留了全部可执行文件与 `liblightamer_bridge.dylib`，删 target 后已复跑 S1/S1r/S2/S3/S4 对比（S2/S3/S4 仍 IDENTICAL）与 S5（需 `DYLD_LIBRARY_PATH=out/bin`，因为链接期 install name 指向原 target 路径），日志 = `evidence/rerun-after-cleanup.log`、`evidence/s5-rerun-after-cleanup.log`。
- 仓库内交付：`.work/gsd/phases/rust-core/SPIKE-RUST-APPLE.md`、`SPIKE-RUST-APPLE-src/`（Cargo.toml、Cargo.lock、build.rs、全部 Rust/Swift/shim/shader 源，无构建产物）、`SPIKE-RUST-APPLE-evidence/`（日志 + 对比输出 + 校验和，96 K）。
- 产品树零改动；零 commit / 零 push。

## §6 复审与修订记录

- 复审：独立 `omp -p --auto-approve --thinking max` 实例，只读白名单；结论 `PASS / 3 error + 10 minor`；复跑确认 S4/S3/S2 对比仍 IDENTICAL，产品树 tracked changes = 0。复审日志 = `spike-review.log`。
- 快照：复审读的是 21:34 版本；本文件在其后按 findings 修订，修订项如下。

| 编号 | 级别 | 处置 |
|---|---|---|
| E1 ICC payload | error | 撤回「ICC 确实随文件写入」。改为：sRGB 被折叠为 nclx/标准空间（JPEG 无 APP2，HEIF/AVIF `colr=nclx`）；补 Swift 探针 `icc_embed_probe.swift` 用 ROMM RGB 证明非标准 ICC 会写 JPEG APP2 / HEIC `prof`；§4 增列 AVIF/自定义 ICC 未测 |
| E2 零像素拷贝 | error | 撤回「零像素拷贝」。改为「跨 FFI 只传 u64、无图像序列化；`replaceRegion` 与 `getBytes` 各一次 API 拷贝，且只写/读首行」；Swift 打印标签改为 `TEXTURE POINTER PATH OK`（旧证据日志保留旧字符串）；§4 增列整纹理/每帧未测 |
| E3 rawspeed 主路径 | error | §3 加限定：先做色彩/几何标定（同目录 `rawspeed-backend/SPIKE.md:262` 的 `mean_abs_diff 22.8/255`），并处理 LGPL-2.1 可重链接义务；§4 增列未复核项 |
| m1 计时口径 | minor | S1r 列名改为 `render+readback+488MB alloc/zero+tex create`；注明 total 中位 ≠ 各列中位之和、`rs_open` 含 cameras.xml 解析、S1/S1r 非同构 |
| m2 跨口径比较 | minor | 删除「无额外解码开销」推断，明确 868–968 ms 是 fit 2560 RGBA8，本轮是 full-res RGBA16F+回读 |
| m3 加速比 | minor | 改为 2.4–2.5×（本轮复跑）+ 上一轮 1.9×（口径不同） |
| m4 内存峰值 | minor | 改为「稳态多 122 MB；峰值至少 2–3 份 122 MB 并存，未测 RSS」 |
| m5 rectangles 归属 | minor | 改为「项目 Ashift 也用（`VisionDetect.swift:52`），本次仅作对照」 |
| m6 Vision 请求集 | minor | §4 列全 5 类请求，标明只测 face rectangles + rectangles |
| m7 extern 数量 | minor | 改为 13 项（3 ColorSync 函数 + 6 静态符号 + CFRelease + 3 个 CG/CF 函数） |
| m8 日志缺失 | minor | 删除无留证的「见日志」措辞；补 `rerun-after-cleanup.log`、`s5-rerun-after-cleanup.log`、`icc-embed.log`；S5 编译错误原文未留档，本记录补录：`uniffi_lightamer_bridge_fn_method_core_paint_texture(uint64_t ptr, uint64_t ptr, ...)` → `error: redefinition of parameter 'ptr'`（UniFFI self 句柄占名） |
| m9 大小 | minor | evidence 84→96 K（补日志后）；Cargo 三件 24→27 K；target 2.2 GB 标注「删除前未把 du 输出留档」 |
| m10 自审收口 | minor | 本节即收口；报告冻结 |

- 复审后新增证据：`SPIKE-RUST-APPLE-evidence/icc-embed.log`（ROMM ICC → JPEG APP2 / HEIC prof）、`rerun-after-cleanup.log`（S1 890.4 ms / S1r 356.4 ms）、`s5-rerun-after-cleanup.log`（删 target 后 S5 全通）。
- 仍未做（不在本轮范围）：swift-bridge、AVIF 自定义 ICC、rawspeed 色彩标定、RSS 峰值、跨平台。
