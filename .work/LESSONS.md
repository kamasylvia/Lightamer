# LESSONS — Lightamer

> 记录开发过程中学到的经验、踩过的坑、验证过的决策。
> 每条经验：背景 → 现象/问题 → 根因 → 对策 → 适用范围。
> 阶段完成后由 `$gsd-extract-learnings` 或手动补充。

## 项目初始化阶段（$gsd-new-project）

### L001: "Core Image RAW 9" 不是 macOS 14/15/26 的功能
- **背景**：项目立项时假设 CIRAW 9 在 macOS 14/15 可用。
- **现象**：研究阶段（STACK.md）查证 Apple 文档与 WWDC26 Session 305 后发现矛盾。
- **根因**：RAW 9 是 WWDC26（2026-06）发布、macOS 27 / iOS 27（2026 秋，目前 beta）才有的 Core ML 融合 demosaic+denoise 引擎。macOS 14（Sonoma）/15（Sequoia）/26（Tahoe）只到 RAW 8。RAW 9 通过 `kCIInputDecoderVersionKey` / `decoderVersion = .version9` 按图 opt-in，且 beta 期仅支持少量相机（如 Fuji X-T5/X-T50），随 OS 生命周期扩展。
- **对策**：锁定 macOS 27 为最低版本（用户决策），原生获得 RAW 9；`#available(macOS 27, *)` 用于独占能力。不再假设旧 macOS 有 RAW 9。
- **适用**：所有涉及 CIRAW 的阶段（Phase 1/2 等）；与用户沟通时不要沿用"RAW 9 在 macOS 14"的旧表述。
- **来源**：`.planning/research/STACK.md`、`.planning/research/SUMMARY.md`。

### L002: WebP 写入 macOS 至今无原生支持；AVIF 写入 macOS 26+ 才原生
- **背景**：导出格式需求包含 WebP、AVIF。
- **现象**：研究 Export Encoder Matrix 发现 Apple `CGImageDestination` 不支持 WebP 写入（即使 macOS 26 Tahoe），AVIF 写入是 macOS 26 才加的。
- **根因**：Apple 的 ImageIO 编码器覆盖滞后于解码器。WebP 解码 macOS 11+ 就有，但编码始终未暴露。
- **对策**：必须引入两个 SPM 依赖——libwebp binding（WebP 写入，所有目标 OS）+ libavif binding（AVIF 写入兜底；macOS 27 floor 下原生可用，但保留 binding 作为质量/位深控制兜底）。`ExportEncoder` 协议，每格式一个实现。
- **适用**：Phase 11（Export）。依赖最小化原则的已知例外（仅这两个 SPM 依赖）。
- **来源**：`.planning/research/STACK.md` Export Format Encoder Matrix。

### L003: Darktable sidecar 的二进制兼容性做不到，不要承诺互通
- **背景**：最初 PROJECT.md 写"sidecar 与 Darktable 二进制兼容为目标"。
- **现象**：ARCHITECTURE/PITFALLS 研究查证 Darktable 源码 `src/common/exif.cc` 后确认不可能。
- **根因**：Darktable 把 iop 参数序列化为 base64 编码的二进制 struct blob 存到 `Xmp.darktable.history[*]/darktable:params`，带 `modversion` 版本号，跨实现（不同编译器/struct 布局/平台）无法可靠 round-trip。还有 `legacy_params` 升级路径依赖 Darktable 自身代码。
- **对策**：sidecar 用 Lightamer 自有格式（Codable JSON 或自有二进制），不追求与 Darktable 互通。预设同样不互通。仅标准 EXIF/IPTC/XMP 元数据（评级/标签/关键字）读写以兼容其他工具。
- **适用**：Phase 2（HIST-03 sidecar）、Phase 12（PRES 预设）。任何"互通"需求都要先确认技术上可行。
- **来源**：`.planning/research/PITFALLS.md` INTEROP-1、`.planning/research/ARCHITECTURE.md`。

### L004: AI 能力的原生边界——天空/人像部位/通用分割无公开 API
- **背景**：用户要求 v1 做 AI 蒙版（主体/天空/人像/通用分割）+ AI 磨皮。
- **现象**：专项研究 macOS 27 Vision/Core Image 后发现能力边界不均。
- **根因**：
  - 主体检测（`VNGenerateForegroundInstanceMaskRequest`）公开可用，任意图像 ✓
  - 天空/人像部位 matte（`CIRAWFilter.semanticSegmentationSkyMatteImage` / `AVSemanticSegmentationMatte`）只能读 iPhone 拍摄时嵌入的数据，不能从任意 DSLR RAW 计算 ✗
  - 通用多类语义分割无公开 API（Photos.app 内部有但不暴露）✗
- **对策**：v1 仅纳入 Apple 原生可直接实现的（主体检测 + 频率分离磨皮——后者用 Vision landmarks + Core Image 滤镜手工实现，无需自定义模型）。天空/人像部位/通用分割/追色/评分需自定义 Core ML 模型，留 v2。
- **适用**：Phase 7（AI）。任何新增 AI 能力都要先确认是原生 API 还是需自定义模型。
- **来源**：专项 AI 能力边界研究（macOS 27 Vision/Core Image 文档 + WWDC26 Session 237/305）。

### L005: Capture One adjustment layers 必须从 pixelpipe 设计之初纳入
- **背景**：用户选择 C1 风格调整图层（每层独立 iop + 蒙版 + 混合模式）作为局部调整机制。
- **现象**：ARCHITECTURE 研究指出这"不能后期贴上"。
- **根因**：Darktable 是全局 pixelpipe + per-iop mask 模型；C1 layers 是层栈模型，每个图层是独立的调整容器。两者数据结构与渲染流程根本不同。如果 Phase 2 pixelpipe 按纯 Darktable 模型建，Phase 6 加图层会重写。
- **对策**：Phase 2 pixelpipe 设计时就把 layer-ready 缓存/历史标识纳入（FOUND-04 带 multi-res + layer-ready cache）；Phase 6 是最大架构阶段，layers + masking 一起交付（互依赖）。
- **适用**：Phase 2/6。任何"局部调整"相关架构改动都要先确认与图层栈模型一致。
- **来源**：`.planning/research/ARCHITECTURE.md`、`.planning/research/PITFALLS.md` NDE-1。

### L006: 半精度（half）浮点会在阴影产生 banding
- **背景**：Metal compute shader 性能优化时可能想用 half。
- **现象**：PITFALLS 研究明确警告（METAL-1）。
- **根因**：half 精度在深阴影/低亮度区域的量化误差可见为色阶条纹。WWDC16 Session 606 也警告 half 字面量混用问题（`0.5` vs `0.5h`）。
- **对策**：pixelpipe 内部一律 float32 RGBA（FOUND-02 锁定）。half 仅用于中间纹理的存储优化（且只在不影响精度的路径，如缩略图）。
- **适用**：所有 Metal kernel 编写。
- **来源**：`.planning/research/PITFALLS.md` METAL-1、WWDC16 #606。

### L007: FSEvents 不可靠，必须配合目录扫描 reconcile
- **背景**：Session 模式需要监视文件夹变化。
- **现象**：PITFALLS 研究指出 FSEvents 有 coalescing、4096 路径限制、rename 丢失等问题（Watchexec 公开称选 FSEvents 是"a mistake"）。
- **对策**：FSEvents 只作为提示，应用获焦时配合目录扫描 reconcile 真实状态。孤儿 sidecar、原片被外部移走等 edge case 优雅处理（提供 reconcile 动作，不硬失败）。
- **适用**：Phase 9（SESS-05 FSEvents 监视）。
- **来源**：`.planning/research/PITFALLS.md` SESS-1..5。

### L008: Metal render encoder 的 `defer endEncoding` 会在 commit 之后才执行 → validation abort
- **背景**：Phase 1 屏显验证（打开 60MP ARW）时 app 启动后 8 秒 SIGABRT，崩溃栈 `EditorMTKView.Coordinator.draw → commit → IOGPUMetalCommandBuffer.validate → MTLReportFailure`。
- **现象**：错误消息 `commit command buffer with uncommitted encoder`。空状态（texture nil 提前 return）完全不触发——只有真实图片走到 commit 才炸。
- **根因**：`defer { encoder.endEncoding() }` 在**函数退出时**才执行，而 `commandBuffer.commit()` 写在函数体内——commit 执行时 render encoder 仍然 open。Swift 的 defer 语义与 Metal 的 encoder 生命周期约定冲突：**endEncoding 必须显式先于 commit 调用，不能依赖 defer**。
- **对策**：手写顺序：draw → `encoder.endEncoding()` → `present` → `commit`。无图路径也要 endEncoding 后再 commit（clear 出画布底色）。同类陷阱适用于 ComputeEncoderSession（Plan 06 已踩过一次：未 endEncoding 就丢弃 session 导致 runner 崩溃）。
- **适用**：所有 Metal encoder 使用（render + compute）。code review 检查项：commit 前必须有显式 endEncoding。
- **来源**：Phase 1 屏显验证崩溃报告（2026-09-16）+ 崩溃日志 `-[IOGPUMetalCommandBuffer validate]:215`。

### L009: 开发环境在 USB 机械盘上时，冷读 I/O 会让构建病态化
- **背景**：仓库与 Xcode 均在 `/Volumes/UNITEK`（14TB USB HDD，非 SSD），DerivedData 在内置 SSD。
- **现象**：构建曾稳定工作（缓存热），随后 xcodebuild 卡死在 dlopen/类实例化（0% CPU）、`xcodebuild -version` 从瞬时变 9.9 秒。随机读实测 ~250ms/文件（90 个 4KB 文件 23.6 秒）。
- **根因**（2026-09-20 归因修正）：机械盘冷读是实测事实；"同卷 Resilio Sync 并发同步 → 磁头寻道冲突"降级为**未完全验证假设**——当时仅凭 Resilio 进程在跑 + SIGSTOP 后一次变快（4.27s→0.095s，非对照 A/B）即归因。用户确认 Resilio 确实同步 UNITEK 上其它目录，机制成立的前提是**其正在活跃传输**（磁头竞争是卷级，不要求目录重叠）；仅进程常驻不构成慢因。慢窗口真因未定案（候选：Resilio 活跃传输 / USB 盘休眠唤醒 / 当日机械盘特性）。
- **对策**：(1) **不例行 SIGSTOP Resilio**（归因未定案，暂停同步有代价）；卷慢态（>2s）时先查 Resilio 是否在活跃传输（网络/磁盘活动），是则可暂停作**诊断性 A/B**，构建完恢复；(2) 长期把 Xcode 与仓库迁回内置 SSD；(3) 本机构建前先 `time xcodebuild -version`（>2s 即卷处于慢态，先查 I/O）。诊断手法：`sample <pid>` 看卡点是否在 dlopen/IO；`dd` 随机小文件测卷延迟。
- **适用**：本机所有 Xcode/构建活动；跨机器开发时注意目标卷类型。
- **来源**：Phase 1 屏显验证会话（2026-09-16）。

### L010: SwiftUI 容器上的 accessibilityLabel 会吞掉子元素的 AX 暴露
- **背景**：为让 XCUITest 查询"编辑视口"区域，在 EditorAreaView 的 ZStack 容器上加了 `.accessibilityLabel`。
- **现象**：XCUITest 三栏断言中 sidebar/viewport/inspector 全过，但空状态卡片（EmptyStateView 的 combine 元素）从 AX 树里消失——`app.debugDescription` 的树 dump 显示编辑区只剩容器 Button，空状态内容不见了。
- **根因**：SwiftUI 里容器视图设置 accessibilityLabel 后，AX 把容器变成合成元素并**吸收子元素**——子视图不再单独暴露。identifier 则不会（只是标记，不改变树结构）。
- **对策**：区域查询用 `.accessibilityIdentifier`（稳定、不本地化、不吞子元素）；label 只加在叶子视图上。XCUITest 匹配优先 identifier（predicate 里已包含）。组合元素（`.accessibilityElement(children: .combine)`）的 label 可能被拼接，用 CONTAINS 或 identifier 更稳。
- **适用**：所有 SwiftUI + XCUITest 的可查询性设计；新增面板/区域时先加 identifier。
- **来源**：Phase 1 UITests 闭环会话（2026-09-18），tree-dump 定位法（失败消息里嵌 `app.debugDescription`）。

### L011: XCUITest 稳定授权三件套：统一证书签名 + Debug 去 hardened runtime + 去 debug-dylib
- **背景**：macOS 27 + Xcode 26 上 XCUITest 反复 "Timed out while enabling automation mode"，与锁屏/授权时序纠缠数日。
- **现象**：run1（用户刚点过授权）成功；重签/重建后全部 timeout；app 自身也出现启动即崩（debug dylib Team-ID mismatch）。
- **根因**（三个因素叠加）：(1) ad-hoc 签名的 TCC 授权按 cdhash 记录，重签即失效；(2) hardened runtime 的 library validation 拒绝加载不同签名的插件/debug-dylib（"different Team IDs"）；(3) Xcode 26 的 ENABLE_DEBUG_DYLIB 把 Debug app 拆成薄启动器 + .debug.dylib，增量构建时签名状态混合。
- **对策**（已固化到 Project.swift）：(a) 全 target 手动签名用本地自签证书 "Lightamer Dev"（openssl 生成 + `security import` + `add-trusted-cert -p codeSign`；无 Apple Developer 证书时的标准做法）；(b) Debug 配置 `ENABLE_DEBUG_DYLIB=NO` + `ENABLE_HARDENED_RUNTIME=NO`，Release 保留 hardened（DIST-5）；(c) 首次授权需真人在密码弹窗输入登录密码——TCC 授权本身无法合成输入（安全边界）。之后重建不再弹窗。
- **适用**：本机所有 XCUITest；新机器克隆后需重建该证书并重新授权一次。
- **来源**：Phase 1 UITests 闭环（2026-09-16 → 09-18）。

### L012: SwiftUI WindowGroup 在 macOS 27 每 odoc Apple Event 开新窗口 → "黑屏/复开不显示"类 UI bug 的真凶
- **背景**：issue #1（JPEG 黑屏）最初诊断为"双渲染路径竞争"（load() 的 decodeTask + EditorAreaView 的 `.task(id:)`）。Plan 02-01 按 D-X1 统一为单渲染路径后，UAT 复验黑屏依旧。
- **现象**：冷启动首开必显示；此后每次 `open`（odoc）视口黑屏。draw 全部执行、drawable 回读（framebufferOnly=false 后合法）含正确像素、零 command buffer error、每帧新 drawable、60fps 连续绘制也一样黑。
- **根因**：**SwiftUI `WindowGroup` 对每个传入的 odoc Apple Event（`open -a app file`、Finder 双击、Dock 拖放）默认开一个新窗口**。新窗口在 decode 期间（`displayTexture` 尚为 nil）创建，其新 MTKView 与旧窗口的视图层层堆叠，屏幕上可见的是"画布帧"，真正有纹理的窗口被盖住。9 次 open 产生了 10 个窗口 / 10 个 MTKView（view 身份探针实证）。首开必成功是因为启动期到达的 open 走 `AppDelegate` 缓冲、`flushBuffered()` 复用首个窗口。
- **对策**：Phase 1/2 单编辑器场景改用 `Window("Lightamer", id: "main")` 单窗口 scene（`LightamerApp.swift`），odoc 只路由进 `application(_:open:)` 处理器；修复后 9/9 UAT 步全显示、全程仅 1 个 MTKView。多窗口等 Phase 9 Session 管理再以受控方式回归（不靠 WindowGroup 的 odoc 默认行为）。
- **教训泛化**：①"渲染/状态层排查到证据完备仍解释不了 UI 症状"时，先查**窗口/视图层级增殖**（每 open 一窗、ZStack transition 残留），别急着怀疑 GPU/present 链路；②排查 MTKView 黑屏时把 `CAMetalLayer.framebufferOnly=false` 才能让 drawable 回读成为合法证据（默认 true 时回读未定义）；③诊断探针（drawable 回读、view 身份日志）按 D-X2 模式"修完即退役"，避免探针自身成为干扰源。
- **适用**：所有 macOS SwiftUI + WindowGroup + odoc/Finder/Drop 打开文件的 app；任何"第二次打开就不对"类症状优先数窗口数。
- **来源**：Plan 02-01 checkpoint→修复全过程（2026-09-19），证据 `.work/plans/02-01/uat-results.md` + `uat-t*.log` + 截图链。

### L013: JSONEncoder keyed 输出顺序无契约稳定性 → 哈希输入禁止用 JSON 字节（跨场域语义）
- **背景**：Plan 02-02 把 `decodeParamsHash` 实现为 `FNV(JSONEncoder().encode(rawTech))`，PipeCacheTests 全链缓存语义测试"第二轮全 miss"。
- **现象**：同一进程内两次 encode 同一 struct，产出的 JSON 键序为 `blackLevel,noiseReductionAmount,neutralChromaticity,whiteLevel,...` —— 既非 encode(to:) 调用序也非属性声明序；缓存 key 跨轮漂移（且 macOS 27 Foundation 的 keyed 容器发射顺序无稳定性契约）。
- **根因**：JSONEncoder 的 keyed 容器发射顺序是实现细节（内部哈希表序），不是 ABI/文档承诺。任何"哈希 JSON 字节当稳定身份"的用法都在踩 RESEARCH Risk #2 的变体——不稳定源从 Hasher 换成了 JSON 键序。
- **对策**：进入哈希/持久化身份的载荷一律**字段显式折叠**（`StableHash.chain(seed, field.bitPattern)`，Double 用 bitPattern）；decodeParamsHash 已改此实现（`PixelPipe.run`）。**02-04 补：params 载荷哈希已全面切到规范化编码**——`ParamsCoding.encode`（`.sortedKeys`）实测同进程跨调用仍会分裂键序（02-04 cache 测试 run4 复现），sortedKeys 后稳定；全部 `commitParams` + `ModuleBox.setParams` 已路由经它，sidecar 漂移检测（02-06）直接复用。
- **适用**：所有"内容寻址"场景：PipeCacheKey/HistoryHash/sidecar historyHash/golden 测试输出指纹。
- **来源**：Plan 02-02-06 调试过程（2026-09-19），PipeCacheTests 全 miss 复现 → DBGPIPE 探针定位。

### L014: CI 腿跨队列读竞态——CI 渲染纹理背书 CIImage 前必须 fence 本队列
- **背景**：Plan 02-06 的 SC#3 真机 round-trip 探针发现：同一份 .lra 恢复后重渲输出全黑（4/4 稳定复现），而 live-edit 路径渲染正确（2/2）；Core 级单测逐级 bisect 显示 input 平面正确、colorout ColorSync 腿（`CIContextPool.convertTexture`）输出为零。
- **现象**：恢复渲染一次跑完 5 个 dispatch（input→colorin→testgain→colorout→gamma）时，colorout 的 CI bitmap 读到刚分配的**全零**平面；短渲染（live-edit，缓存命中上游）则侥幸通过。
- **根因**：`CIContext(mtlDevice:)` 在自己的**内部队列**执行 `render(toBitmap:)`，而输入纹理是我们串行队列上 `dispatch2DTexture` **commit 过但未必完成**的写入。Metal 跨队列对同一纹理的读/写没有隐式顺序——CI 读与 kernel 写竞态。字节级排障时还叠加了第二层伪影：`MTLTexture.getBytes` 不等待 in-flight encoder，读回必须先 fence（测试端同款问题，Golden/Trio 测试早已内置 `drain()`，新测试漏抄）。
- **对策**：(1) `convertTexture` 开头 commit 空 command buffer + `waitUntilCompleted`（fence），保证本队列既有写入对 CI 可见；(2) 所有测试/探针读回纹理前一律 drain；(3) 判定"渲染黑图"前先排除读取竞态（黑图 + alpha=255 是"gamma 写了黑 RGB"，而全 0 才是"没写"）。
- **适用**：任何"我们的队列写纹理 + CI/其他队列读"的混用场景（colorout fallback 腿、未来 CI 复合导出路径）；所有 GPU 纹理读回（测试与探针）。
- **来源**：Plan 02-06-04 SC#3 验收排障（2026-09-19），证据 `.work/plans/02-06/roundtrip.md` + `SidecarRoundTripTests.testRoundTripRestoresIdenticalRenderedOutput`。

### L015: Darktable XMP 的未压缩 params 是 HEX ASCII，不是 base64
- **背景**：Plan 03-01-T1 按 03-RESEARCH §6.3 的配方（「纯 base64（>100B 才 zlib）」）生成 exposure 钉参 XMP，darktable-cli 重建后 XMP history 行虽被写入库，但 op_params 全为默认值，输出恒等。
- **现象**：`--core -d params` 日志显示 `[history] successfully loaded module exposure ... params v. 7: version ok params WRONG`——params blob 尺寸校验失败，dt 静默回退默认参数。
- **根因**：`dt_exif_xmp_encode_internal`（exif.cc:3292-3311）的两条路径：压缩 = `"gz"` + 2 位压缩因子 + base64；**未压缩 = 小写 HEX ASCII（每字节 2 字符）**。`dt_exif_xmp_decode`（exif.cc:3317+）按 `gz` 前缀分派，无前缀时按 hex 解析——base64 字符串被当 hex 解出错误长度，history loader 标 `params WRONG` 后用模块默认值顶替。
- **对策**：XMP `darktable:params` 一律 `binascii.hexlify(struct.pack(...))`（小写）。生成脚本 `input/golden/fixtures/gen_fixtures.py` 的 `exposure_params_blob` 是正本；后续模块（WB/sigmoid/…）的钉参 XMP 照此办理。验证手段：`--core -d params` 看 `params v. N: version ok params ok` + `sqlite3 <library.db> "SELECT hex(op_params) FROM main.history WHERE operation='<op>'"`。
- **适用**：所有 Phase 3+ golden 钉参 XMP 生成；任何「直接改 dt 库 DB」的手工实验。
- **来源**：Plan 03-01-T1 排障（2026-09-19），RESEARCH §6.3 已知勘误点（exif.cc:3218-3241 段的编码分派读岔）。

### L016: macOS 27 ImageIO 的 float32 EXR 解码逐通道错位；CGColorSpace.itur_2020 不是 linear
- **背景**：Plan 03-01-T3 golden parity 轨 A 需要把 dt-cli 产出的 float32 EXR fixture 送进 Lightamer 管线；最初走 `RAWDecoder.decodeRaster`（CGImageSource → CGImage → CIImage）。
- **现象**：管线输入平面每个通道以**不同的列偏移/次采样率**出现（R≈v(50+x/3)、G≈v(29+x/2.7)、B≈v(x/3)），且对 darktable 写的文件与自研 writer 写的文件同样错位；同一文件经 dt（libopenexr）与手写 reader 读取均逐字节正确——错的是 ImageIO 解码器。另：把 fixture CGImage 标成 `CGColorSpace(name: .itur_2020)` 后，CI 腿把已 linear 的值再 gamma 解码（v^2.4，v(0)=2^-8 → 2^-19.2 特征值）。
- **根因**：① macOS 27 ImageIO 的 float32 EXR 解码路径内部布局假设与 OpenEXR 规范不一致（逐通道错位，机制未深究——官方框架行为，绕开即可）；② `kCGColorSpaceITUR_2020` 带 BT.1886 gamma-2.4 TRC，**不是 linear Rec2020**；linear 版本常量是 `CGColorSpace.linearITUR_2020`（项目内 `WorkingSpace.colorSpace`）。
- **对策**：① float EXR 精确读取一律走 `GoldenParityTests.UncompressedEXR`（手写 uncompressed scanline float32 reader，regenerate.sh 已用 `--configdir` 把 dt 写出钉成 uncompressed float32，PIZ 输入会 fail-fast）；fixture → 管线用 `CGImageCreate`（float32 字节直构，不经过 ImageIO 解码器）+ `WorkingSpace.colorSpace` 标签。② 任何「linear Rec2020」语义必须用 `WorkingSpace.colorSpace`，禁止 `.itur_2020` 字面常量。
- **适用**：Phase 3 全部 golden parity 测试；Phase 11 导出 EXR 预览/回读；一切 CI+float 图像的 colorspace 标签。
- **来源**：Plan 03-01-T3 排障（2026-09-19），证据探针 `/tmp/citest.swift`、`/tmp/cgmake.swift`（会话内），修复后轨 A 全绿。

### L017: darktable-cli float 导出对本机 arm64 构建的空间损坏 — golden 参考必须按语义可验证性分流
- **背景**：Plan 03-02 为 temperature 钉参组生成 dt-cli golden（EXR，03-01 同一管线），轨 A parity 全线失败。
- **现象**：同一 dt-cli（重建 dc58cf0ba1，Apple clang + libomp，macOS 27/arm64）对**空间均匀**图像（平场）的 float 导出逐值正确，对**空间变化**图像（ramp/阶梯/饱和块）输出空间损坏且模式随输入变化：EXR = 逐通道平面错排；PFM/TIFF = 水平"涂抹"（各通道以 (2/3, 1/3, 0)·w 相位偏移重采样）；同一命令确定性复现。8-bit TIFF（gamma 启用路径）与均匀平场 PFM 输出正确。`--core -d all` 的管线内 min/max 统计显示模块输出正确 → 损坏发生在管线与写出之间。
- **根因**：未定位到具体提交（需 debugger 级排查）；属本机构建组合（clang OpenMP simd / libomp / arm64 向量化）与 dt 导出路径的相互作用，非 Lightamer 侧问题。旁证：no-OpenMP 重建（`USE_OPENMP=OFF`）后 dt-cli 在启动期 `dt_image_get_camera_id` 死锁，不可用（sidecar_jobs.c 还需压制 clang thread-safety 误报才能编译）。
- **对策**：golden 参考按"语义可验证性"分流——①参考语义无算法自由度的模块（temperature = 逐通道乘法）：参考由 gen_fixtures.py 按共有语义**合成**（canonical fixture × 钉参增益，float64），dt 侧以三证据锁定：库 DB `op_params` hex 采纳实证 + `--core -d params` 日志 + 均匀平场 PFM probe 逐值对照（(0.6,0.5,0.4) exact，4e-8）；②其他模块继续优先 dt-cli EXR（exposure 已证可用），但**新增 case 首次使用前必须先做均匀平场 + 变化图像的双重 probe**，probe 不过即走①路线并在 manifest 落账。
- **适用**：Phase 3+ 所有 dt-cli golden 生成；任何"依赖外部工具导出数值参考"的验证链。
- **来源**：Plan 03-02-T2 排障（2026-09-19），证据链：dt 管线 stats vs 落盘字节对照、库 DB op_params hex、PFM/EXR/TIFF 三 writer 交叉、no-OMP 构建 hang；manifest "dt-cli host finding" 节。

### L018: read_write 纹理同线程 RMW 不回报写入值；.private buffer 分配毒化后续 CI 渲染（macOS 27 beta）
- **背景**：Plan 03-04-T1 GaussianBlur（Deriche IIR，需 backward pass 累加 forward 结果）与 T2 shadhi 接线排障（2026-09-19）。两个独立缺陷，均为探针逐层二分定位。
- **缺陷 1（read_write 纹理 RMW）**：`texture2d<float, access::read_write>` 在**同一 kernel、同一线程**内先 `write` 后 `read`，`read` 返回 0（M4 / macOS 27 beta 实测；MSL 语义上应可见）。症状：IIR backward 累加消失，输出 = 纯 backward 分量（平场 DC 增益 = coefn 而非 1）。dt 的 OpenCL 正因如此用 `__global float4 *` buffer（`gaussian.cl` `out[loc] += ...`）而非 image2d。
- **对策 1**：按 dt 原形移植——中间结果走 `device float4*` **buffer 平面**（device 内存同线程 store→load 程序序有保证），col pass 写平面、row pass 读平面 0 写平面 1（**双缓冲**）、`gaussian_store` 收尾拷回纹理。
- **缺陷 2（行 pass 原位读写）**：row pass 若在**同一平面**上原位读写，backward 读到的"输入"是 forward 刚写入的**输出**，DC 增益坍缩为 `coefp·(1+coefn)`（σ=8 实测 0.77578，精确吻合）。dt 的水平 pass 本就是读一个 buffer 写另一个。
- **缺陷 3（.private 分配毒化 CI 渲染）**：blur 测试中 `.storageModePrivate` plane（σ=20 IIR 写入模式）分配释放后，**同进程后续测试的 CIContext 渲染确定性丢失 viewed-下半帧**（内容上移、上半黑，色彩正确——GoldenColorTests D-COL1 误报）。`.storageModeShared` 分配同一测试内容即消除。判定为 macOS 27 beta 驱动/分配器围栏交互，非代码逻辑错误；UMA 上 shared 无带宽代价，统一用 shared。
- **对策 2（测试法）**：跨测试状态污染的排查路径——①单跑受害测试（通过→污染）；②按字母序找前驱测试二分；③在嫌疑测试内部按参数二分（σ=0.1 干净 / σ=20 触发）；④换分配路径（private→shared）验证。全量套件绿 ≠ 单测试语义正确，反之亦然。
- **适用**：Phase 3+ 所有 IIR/邻域 kernel；一切 read_write 纹理累积模式；CI 渲染与 GPU compute 混跑的测试与 App 路径。
- **来源**：Plan 03-04-T1/T2 排障（2026-09-19），证据链：.work/plans/03-04/probe-gauss*.log（fwd-only uniform 灭零法 + 底部脉冲分解）、bisect-s01/s20/shared 日志、neutral-dump.png（半帧可视化）。

### L019: XCTest「Enable UI Automation」密码弹窗会阻塞 App-host 单测全链；computer-use SDK client 缺失时用 coreautha 重建法消弹窗
- **背景**：Plan 04-02 验收复跑全量 suite（2026-09-20）。`xcodebuild test` 两个 runner（LightamerTests 单测 + UITests）全部「The test runner hung before establishing connection」——**连不需要 UI Automation 的单测 runner 也挂**。15:07 全量还能过，之后 4 连挂。
- **根因**：屏幕上悬着系统授权弹窗「XCTest 正在尝试 Enable UI Automation…输入用户密码以继续」（新二进制形态触发，非锁屏）。coreautha（LocalAuthentication）持有 secure input，弹窗对 test 会话的 automation enrollment 是**模态阻塞**——runner 起了但连不回 testmanagerd。误判过程：kCGSSessionSecureInputPID 有值被当成「锁屏」，实际截屏一看是弹窗（**先截屏再推断**，session dict 只能证 secure input 被持有，不能证锁屏）。
- **排障路径（按序，含死胡同）**：① CGEvent 直发键入密码——osascript/uv-python 进程 **AXIsProcessTrusted=False**，事件被系统静默丢弃；② osascript System Events——进程级 AX 操作同样「不允许辅助访问」；③ computer-use SDK——本安装 **computer-use-client.mjs 缺失**（构建缓存不全，browser-use 0.5.1 里只有 browser-client.mjs），get_app_state 全局未注入；④ 终解：`kill -TERM`→`kill -9` coreautha（弹窗宿主，launchd 按需重生，语义=用户点「取消」），secure input 释放、弹窗消失，单测 runner 立即可连。
- **对策**：a) 测试 runner「hung before connection」≠ 代码问题，先 `screencapture -x` 看屏幕有无模态弹窗，有则先消弹窗再跑测试；b) 无 AX 权限的 CLI 进程（CGEvent/osascript 均废）消系统弹窗 = 杀宿主进程（coreautha/UserNotificationCenter 均可安全重生）；c) 该弹窗一旦出现**会持续阻塞后续所有 xcodebuild 会话**，不是瞬时故障——15:07 后 4 连挂即此因；d) 消弹窗=放弃 UI Automation 授权（UITests 仍 L011 挂账），单测不受影响。
- **适用**：所有 xcodebuild/App-host 测试会话；一切「进程有 GUI 会话但 AX 未授权」的自动化场景。
- **修正案（L019a，2026-09-21）**：辅助功能授予 ZCode 后弹窗正解 =「自动完成 enrollment」（AX 填密码 + 点好；app 签名 DR 键 certificate root 跨构建稳定，已实测）。持久化失败主因 = kill coreautha 中止 enrollment 形成循环 + Tuist 重生成改 runner 形态。kill 法降级为兜底。
- **来源**：04-02 验收排障（2026-09-20），证据链：xcresult 双 runner failureText、CGSessionCopyCurrentDictionary、AXIsProcessTrusted=False、前后截屏对照、secure input 释放确认。

### L019b: 单测直启宿主根治 enrollment 弹窗——XCTestConfigurationFilePath + DYLD 注入绕开 testmanagerd
- **背景**：L019a 后弹窗仍每轮重建必弹（enrollment 键 = runner cdhash，重建即变；DR 证书根稳定但没用）。根治 = 绕开 testmanagerd：单测不需要 UI automation，直启宿主二进制跑测试即可。
- **配方**（Scripts/test-direct.sh 正本）：`DYLD_INSERT_LIBRARIES=<Debug>/Lightamer.app/Contents/Frameworks/libXCTestBundleInject.dylib` + `DYLD_LIBRARY_PATH/DYLD_FRAMEWORK_PATH`（DerivedData Debug + Xcode 平台库）+ `XCTestConfigurationFilePath`（最小 plist：TestBundlePath + productModuleName）→ 直启 `Lightamer.app/Contents/MacOS/Lightamer [-XCTest <类>]`。抓取方法：跑一个最小 xcodebuild test，`ps -wwE -p <runner>` 高频轮询抓注入现场（XCTestSessionIdentifier 是 testmanagerd 会话钩子——直启时**不带**它）。
- **实证**：2026-09-22 全套直启 480/3skip/0fail 与 xcodebuild 逐值等价；-XCTest 类过滤生效（7 tests）；零弹窗、零 testmanagerd 依赖。构建（xcodebuild build）不触发弹窗——弹窗只在 test 会话。
- **对策**：单测一律 Scripts/test-direct.sh；xcodebuild test 保留给 UITests/xcresult 需求；弹窗若再遇（UITests 路径）按 L019a。
- **适用**：一切 macOS app-host 单测；一切被 testmanagerd enrollment 阻塞的 CI/自动化场景。
- **来源**：2026-09-22 直启实验（注入现场 ps -wwE 抓取 + 两轮等价性验证）。

### L020: dt modify_roi_in 公式不可直接照搬——backward walk 的 roi 坐标系两边不同（crop 双重偏移真 bug）
- **背景**：Plan 04-02 验收补真 crop golden track A（原测试恒真空转）后首跑即抓出：crop_center50 输出 (0,0) lightamer=0.25（=fixture(0.75)，[0.75..1] 角）而 ref=0.015625（=fixture(0.25)，正确窗口 [0.25..0.75] 原点）。04-01 ROI 协商测试 8/8 全绿——但那些断言只钉**记账**（尺寸/次数/键），从未钉**内容**；golden track A 是管线首个内容级断言。
- **根因（坐标系约定冲突）**：dt `crop.c:576-592` 的 `roi_in = roi_out + buf_in·cx` 再加原点公式，前提是其 backward walk（`pixelpipe_hb.c:2085`）从**屏幕 roi** 出发、roi_out 为**窗口相对**坐标（原点=窗口角 (0,0)）。我们的 backward walk（processRec）从 **forward walk 结果**出发（`get_dimensions` 语义，`buf_out.xy` 已是上游相对窗口原点 16）——模块再加一次 left → 双加到 32，上游渲染了 [32..64) 而非 [16..48)；`process` 的 blit 又按全平面假设平移（dx=roiIn−roiOut，dt `copy_image_roi` 实为 `roi_out − roi_in`，`imagebuf.c:194`）→ 双重错位。
- **对策**：①判断 dt roi 公式可否照搬，先核对其 walk 的坐标系前提（`pixelpipe_hb.c` backward walk vs `get_dimensions` forward walk），两 walk 语义不同；②修复 = modifyROIIn 保形（xy 已是原点，只 clamp）+ process dx=roiOut−roiIn，注释钉死帧约定（**部分下游请求的逐几何边界 re-base 协议留给 04-03 rotate**——旋转会强制帧变换成为一等公民）；③纯记账测试（尺寸/次数/键）对坐标错位免疫——几何模块必须有**内容级**断言（golden/逐像素）兜底，记账绿≠内容对；④照搬 dt 源码时，被移植函数在 dt 中走的分支（如 copy_image_roi 尺寸相等走快路径、坐标数学从未执行）也要核实——死分支里的公式可能从未被 dt 自己验证过。
- **适用**：04-03 rotate/perspective、04-04 lens（全部几何/重采样模块）；一切「从 dt 移植 ROI/坐标数学」的场景。
- **来源**：04-02 验收排障（2026-09-20），证据链：golden 失败逐像素值反解 fixture 坐标（0.25=2^(-8+8·0.75)）、dt pixelpipe_hb.c:2085/3368-3405 两 walk 对照、imagebuf.c:188-223 快慢路径分析、修复后 311 全绿。

### L021: dscIn 是本 run 平面像素——模块 ROI 钩子禁止再 ×scale；显示腿（blit+布局）无单测覆盖必须走真实 GUI 验收
- **背景**：Plan 04-06 GUI 显示腿修复（2026-09-21）。首次真实可执行 GUI 验收（Debug 产物 + DSC00012.ARW）抓出单测全绿但肉眼可见的 4 缺陷：视口近全黑（GUI-1）+ 白对角线（GUI-2）+ fit 溢出（GUI-3）+ 三列均分（GUI-4）。358+ 测试验证的是管线纹理；MTKView→CAMetalLayer 显示腿与布局只有 Phase 1 时代覆盖。
- **现象**：全 seed 链经 coordinator.load 真实路径黑（2560×1707 mean (0,6,5)，<16=94.2%），trio-only 亮；二分锁定 crop（trio+crop-only 黑 / trio+flip-only 亮）。
- **根因（GUI-1）**：`CropModule.modifyROIIn` 把已 entry 缩放的 `dscIn` 又 ×`roi.scale`（double-scale）：760 档 clamp 界坍缩 60×40 → 协商 roiIn 60×40 → process 左上小窗 blit、其余全零。scale=1.0 恒等掩盖了它——全部 golden/crop 单测（小合成图全尺寸）免疫。同类 `dscIn × scale` 还有 toneequal blending 直径（preview 半径偏小，质量向）与 flip bw/bh（.none 恒等免疫），修 crop 一处、余者 Phase 5 审计。
- **对策**：①`modifyROIIn` clamp 界直用 dscIn（同 run 平面像素），注释钉死坐标系（PixelPipe.run 按 bufInROI 逐级 stamp）；②常驻回归 `testScaledFullFrameCropMatchesTrioOnly`（trio+crop 逐字节 == trio-only @longEdge 48，pre-fix 红）；③判别探针（GUIProbeTests，A–Q7 真 RAW 消融）按 L012 D-X2 退役删除，常驻回归只留合成图毫秒级门；④显示腿：大三角形→顶点矩形 strip（quad 即 fit 矩形，ViewportFit.fittedRect 同源，letterbox=clearColor）+ 布局收窄（侧栏 200/Inspector 280，视口 ≥50%）；⑤GUI 复验按 PLAYBOOK §2 观察层量化（screencapture + PIL/numpy 数字进 FINDINGS.md），macOS 持久化 split frames 须 `defaults delete` 后看新窗口默认值。
- **适用**：一切读 `piece.dscIn` 的 ROI 钩子（crop/lens/ashift/toneequal/flip…）；一切 MTKView blit/布局改动（先 GUI 验收再签收）。
- **来源**：Plan 04-06 T1–T5（2026-09-21），证据 `.work/plans/04-06/probe-gui1.md` + `.work/gui-acceptance/2026-09-21-fix-*.png` + FINDINGS.md 闭环；全 suite 389 绿（3 skip）。

### L022: omp 执行期间禁止一切工作区编辑——整文件回写会吞掉并发改动
- **背景**：05-01 与 05-02 两次omp 执行期间，orchestrator 并发编辑 LESSONS/GOAL-STATE/PLAYBOOK（纯文本小改、未 git 操作），omp 收尾时按其上下文里的**陈旧快照整文件回写**，并发编辑全部丢失（05-01 丢 3 处；05-02 收尾再次吞掉本条首版）。
- **根因**：omp 文档任务（SUMMARY/LESSONS/TODO closeout）按启动时读取的快照重写共享文档——orchestrator 运行中段的编辑不在快照里。reflog 无 checkout/stash，纯文件覆写。
- **对策**：omp 运行期间 orchestrator **零工作区写入**（含纯文本编辑、截屏产物落工作区）；编排侧记录写到 /tmp，omp 收工后搬入并提交。巡检规则同理。
- **适用**：omp 执行模型全程；一切「子进程整文件回写共享文档」的编排形态。
- **来源**：05-01/05-02 两次编辑丢失（2026-09-21/22），证据：grep 关键字 = 0 + reflog 仅 commits。

### L023: uniforms 对是"半边契约"时 parity 测试必须钉全往返，禁止钉半边（matrix-in/out 中性往返恒等式）
- **背景**：Plan 05-02-T5 续跑（2026-09-22）。HOLD 后首跑全套红 9 项 `testMatricesInvert`：断言 `matrixOut · matrixIn ≈ I`，首值 0.643 vs 1.0——T3 落盘时绿？实为 T1→T3 间 `matrixOut` 定义变更（`X2R·L2X` → `X2R` 直接，bisect 2.9156606 回归证据）后测试前提过期：L2X 腿（`cb_lms_to_xyz` = YrgGamut.lms2006toXYZD65）在 MSL kernel 内，不在 uniforms——uniforms 对只是"半边契约"，mo·mi = xyzD65toLMS2006 ≠ I 是构造使然。
- **根因（契约边界错位）**：commit 进 uniforms 的矩阵对 ≠ kernel 实际走的完整变换链；测试把 uniforms 的半边当全链钉。真中性往返 = mo·L2X·mi ≈ I（实测 max dev 3.7e-9，门 1e-6）。
- **对策**：①凡 kernel 内含固定折叠腿（LMS↔XYZ、Bradford、CAT 等）的矩阵 uniforms，parity 测试必须从 kernel 源码逐腿列出完整往返式再钉断言；②注释在矩阵定义处写明"半边" + 真往返式（本轮 `matrixOut` 注释已更正）；③矩阵定义变更（T1→T3 bisect）必须同步重审依赖它的测试前提——定义与断言同批提交。
- **适用**：一切"CPU commit 预计算 + GPU 求值"模式的 uniforms 矩阵（filmicrgb/colorbalancergb 类）；05-03/04 的矩阵链模块（channelmixerrgb 等）先写往返式再写测试。
- **来源**：05-02-T5（2026-09-22），证据：九连红 failureText（0.643011698389447 vs 1.0）、numpy 三矩阵互证（F−R2X 2.8e-9、P−I 3.7e-9）、修复后隔离双测 + 终轮 445/0/3 全绿。

### L024: CL 标量核并行化时滚动 tmp 必须逐通道持有；混合进制解码的位权与步长不许混用（bilateral grid 双缺陷）

**现象**（05-08-T2 bilateral 5D 网格）：① blur_line 的 dt CL 原文是逐元素滚动（`tmp1/tmp2` 每元素独立），并行化把 4 个 payload 通道折叠进一个线程时把**标量 tmp 跨通道复用**——val 通道的滚动值污染 w 通道，val/w 比被破坏（平场 0.18 输出 0.495，golden/平场门当场红）；② 线解码先用了「排除 axis 的压缩位权」当「真步长」算基址（应压缩位权解码 digit、真步长算地址），分块==整幅 rel 0.19。

**修复**：滚动 tmp 升级 float4/SIMD4 逐通道持有（kernel 与 CPU 参考同构）；解码=压缩位权、地址=真步长（Π_{e<d} dims[e] 含 axis 因子）。

**教训**：把 CL 标量 kernel（每线程一元素）改写成每线程多元素/多通道时，**每个跨迭代局部变量都要问一次「它属于哪个通道/哪个元素」**——标量语义在并行化下静默变跨通道共享；同理，混合进制 flat 索引里「枚举位权」和「内存步长」是两个不同的数（跳过的维度仍占地址位）。防线 = 平场恒等门（任何 val/w 比破坏当场暴露）+ 分块==整幅门（任何相位/寻址漂移当场暴露）——两门必须常驻。

### L025: String Catalog 新增键的语言标签必须跟全库既有约定（zh 而非 zh-Hans）——部分翻译的 .lproj 会整体破坏运行时回退

**现象**（06-07 T4）：新增 19 个 catalog 键用 `zh-Hans` 标签（全库既有键为 `zh`）→
xcstrings 编译器随之产出**仅 22 键的部分 zh-Hans.lproj**；其存在使 zh-Hans 系统
locale 的 Bundle 解析停在该表（不再向 zh.lproj 回退）——**全 app 字符串渲染为裸键**
（不仅是新键），而 `entire contents`/plutil 抽查单键均"存在"，极难定位。

**修复**：新键统一 `zh` 标签；修复后 en/zh 表 592/592、zh-Hans.lproj 不再产出、
中文全量渲染恢复。

**教训**：① 资源表语言标签是**全库约定**，不是每键自由选择——新增键先查既有标签；
② 部分翻译的 .lproj 不是"多一点少一点"，它会**改变 Bundle 的 fallback 链选择**，
把原本可达的表变不可达（伤害面 = 全库而非增量）；③ 防线 = GUI 轮首屏截图必查
中文渲染（裸键 = catalog 层问题先于逻辑层排查），`ls *.lproj` 应作为 catalog
变更后的 smoke。


### L027: Foundation 的路径"同形"是幻觉——enumerator 物理化 root 符号链接而 URL.path 不解析，跨源路径比对必须 realpath(3) 归一；fileSystemRepresentation 指针禁 deallocate

- **现象**（09-01 T3 SessionTreeScanner）：以 `NSTemporaryDirectory()`（`/var/folders/...`）为根建 fixture，`FileManager.enumerator(at:)` 返回的子路径是**符号链接解析后的物理形态**（`/private/var/...`），而 `URL.path` / `URL.resolvingSymlinksInPath()` / `(NSString as NSString).resolvingSymlinksInPath` 全都保留 `/var` 前缀——三者都无法与 enumerator 的输出做前缀匹配。后果两级：先是无害级（relPath 退化为 leaf 名），后是**语义级**（根级保留目录判定 `Capture/` 因父路径串不匹配而失效 → deeper/Capture/ 被误当根级保留目录整体排除）。另一陷阱：用 `FileManager.fileSystemRepresentation(withPath:)` 返回的指针调 `deallocate()` → 堆损坏，测试宿主 SIGABRT（`POINTER_BEING_FREED_WAS_NOT_ALLOCATED`，崩在毫不相干的 NSConcreteData dealloc）。
- **根因**：①"同一目录的路径字符串"在 Foundation 里有多种合法形态（原样 / standardized / 符号链接解析），每个 API 自选其一且无文档契约——`enumerator` 内部 realpath 了根，字符串 API 不解析前缀链接；②`fileSystemRepresentation(withPath:)` 的返回值不是独立分配的缓冲（与 `getFileSystemRepresentation(_:maxLength:)` 填充式 API 不同源），对其 free 即破坏堆。
- **对策**：①一切"从子路径剥离根前缀"的逻辑，用 `realpath(3)`（`withCString` + 4096 缓冲）显式求物理根，**同时匹配多种拼写**（物理 + 原样）；目录树归属判定不要用"父路径字符串相等"，改用自身 relPath 是否含 `/`（`dropFirst` 式裁剪而非 `replacingOccurrences`——后者会在中段误替换制造 `/private` + 名字的缝合怪）；②`realpath` 的 C 交互一律 `withCString` 作用域缓冲，禁止对 `fileSystemRepresentation(withPath:)` 结果 deallocate/free。
- **适用**：一切目录扫描/相对路径计算（Phase 9 全系：scanner/store/watcher reconcile）；一切 Foundation C 字符串桥接。
- **增补（09-02 T2，FSEvents 场景活体复现）**：`FSEventStream`（UseCFTypes）上报的事件路径同样是**物理拼写**（`/private/var/...`），与 `URL.path` 的 `/var` 前缀不匹配——watcher 初版全部文件事件被前缀过滤静默丢弃，而 WatchRoot flag-only 事件正常到达（不看路径），极易误判为「流没起」。对策：watcher init 时 `realpath(3)` 求物理根**双前缀匹配**；下游 journal 查询 / rowKey 映射同用双拼写**变体对**（`pathVariants`）。测试侧注意：`kFSEventStreamEventIdSinceNow` 会把 arm 前瞬间的合并残留事件投递进来，时序断言用基线差值。来源：09-02 T2 SessionWatcherTests 三轮排障（create 事件 10s 超时 → WatchRoot 单测却绿 → 前缀比对定位）。
- **增补（M2-10-01，冗余分隔符也是拼写差）**：launch path 含 `//`（如 test-direct.sh 的 `Debug//Lightamer.app`）时，`URL.path` **保留**双斜杠而 `FileManager.enumerator` 物理化（realpath）**折叠**——树哈希 prefix 匹配全数失败静默退化 `lastPathComponent` 兜底（字节总量守恒 → 不炸、只有 hash 不符，且同目录树下不同文件可呈现「有的匹配有的不匹配」的假象）。对策：一切「URL 拼 prefix 再剥子路径」的比较，两侧先归一化（折叠 `//+` 与尾斜杠）再比；仅凭「字节量一致」不足以证明枚举正确，树哈希测试必须钉逐行行集。来源：M2-10-01 CatalogTests 资源门三轮排障（standalone Swift 全对、测试内全错 → DBG 打印 URL 双斜杠定位）。
- **来源**：09-01 T3 golden 测试三轮排障（首轮 `/privatescan.jpg` 缝合串、次轮 leaf 退化 + deeper/Capture 误排除、`fileSystemRepresentation` SIGABRT 崩溃报告 malloc 栈定位）。

### L028: px --up 自锁——代理 env 常开而 daemon 未跑时，起 daemon 的工具链自身也被死端口坑；解法 = 清代理 env 跑 px --up

- **现象**（11-01 T4 SPM fetch）：会话 shell profile 常开 `http_proxy/https_proxy/ALL_PROXY`（指向 `127.0.0.1:10809/10808`）但 xray daemon 未运行 → 一切走代理的进程（git clone SPM 包）报 `Connection refused`；而救场命令 `px --up` **自己也会失败**——其内部 `xray.py` 经 `uv run --with requests python3` 拉 requests，uv 同样读代理 env 走死端口，鸡生蛋死锁。
- **根因**：代理 env 是「声明式意图」（有无 daemon 都在），消费方不探测 daemon 存活；px 自身的网络前置（uv/pypi）没有豁免自身代理 env 的逻辑。
- **对策**：起代理前清 env：`env -u http_proxy -u HTTP_PROXY -u https_proxy -u HTTPS_PROXY -u ALL_PROXY px --up`；daemon 起来后再跑需要代理的命令（或 `px --proxy <cmd>` 注入）。收尾恒 `px --stop`。诊断入口：git 报错里的 `Failed to connect to 127.0.0.1 port 10809` 即「env 开而 daemon 死」指纹。
- **适用**：一切 SPM/cargo/uv/go 等首次拉取场景（本机代理 env 常开布局下）；R3 型网络预案照抄本解法。

### L029: `CIImage(mtlTexture:)` 读纹理是底向上 origin——裸 CI render 把平面垂直镜像；定向断言必须程序化枚举映射而非逐点手算

- **背景**（11-02 T2 出口腿 `renderToEncodedBitmap`）：管线 float32 纹理 → CI bitmap 直出 CPU buffer 的导出腿，首版 fence 测试失败，失败形态是「样本整体位移」假象——逐点手算三种映射（翻转/行交换）全部对不上，差点误判为 fence 竞态。
- **根因**：① Core Image 以**底向上 origin** 约定解释 Metal 纹理（纹理行 0 = CI 图像底部），而 `render(toBitmap:)` 顶向下写 bitmap——一次「纹理进、bitmap 出」的 CI 腿净效果 = **纯垂直镜像**（列序不变；程序化枚举 identity/vflip/rot180/offset 后 vflip 0-mismatch / identity 64-mismatch 钉死）。② 排障方法论：对「读回定向」这类未知约定，先写**映射候选枚举探针**（每个候选一害 0-mismatch 判定）再下结论——逐点手算逆推在 i%17 这类自相似 pattern 上会产生系统性误读（shift-14 假象）。
- **对策**：① 一切「MTLTexture 进、CI bitmap 出」的腿在函数**内部**做 `.oriented(.downMirrored)` 复位，契约 = 「bitmap 行序 == 纹理行序」，配套行序 pattern 测试常驻（修复前 64/64 错位——不修则导出文件上下颠倒）；② 排障期探针用小图（4×4）+ 程序化候选映射，结论（vflip）得出后再固化成最小契约测试；③ **已知同病未修**：`CIContextPool.convertTexture`（colorout ColorSync **fallback** 腿）完全同型镜像——fast path 不经它所以预览从未暴露，修复 = 同款 `.downMirrored` + fast/fallback 双腿**内容级** parity（记账型测试对镜像免疫，参照 L020-④「纯记账测试对坐标错位免疫」同类教训）+ GUI 走查兜底。
- **适用**：一切 CI 腿（纹理↔bitmap 往返：导出、软打样、Phase 14 MCP render_preview）；一切「读回定向未知」的排障（先枚举映射再定位）。
- **来源**：11-02 T2 fence/行序双测试三轮排障（fence 首跑样本位移假象 → 探针 vflip 0-mismatch 定位 → `.downMirrored` 修复后恒等 0-mismatch 双向验证）。

### L030: ping-pong scratch 复用必须尺寸感知——画布增长模块接 uncached 尾段时，无脑复用把输出静默截断成旧尺寸

- **现象**（11-03 T4 导出 E2E）：`PixelPipe.processRec` uncached 腿（FULL 中间面 / 全 EXPORT 面）在 borders（76.0，画布扩展模块）接管后，返回给下游的平面仍是**主图尺寸**而非画布尺寸——negotiated-ROI 前置断言在 watermark 位触发；四态矩阵里「仅框画布应增长」也同步失真。FULL 分辨率 + 增画布模块的组合（08-1 起）理论上同样中招，只是全幅 uncached + borders 的测试从未同框（yiyin E2E 全走 PREVIEW 缓存管线），属**潜伏两波**的真缺陷。
- **根因**：`nextScratchPlane` 的 ping-pong 池只有两个槽位，首次分配后**无条件交替复用**——前段全部 identity/同尺寸模块把两槽都定型在入口尺寸，尺寸变化的第一位模块拿到旧尺寸槽位即被截断（模块自身只写 roiOut 矩形，不检查 output 尺寸——契约由分配方单边保证）。
- **对策**：① 复用前按 `roiOut` 尺寸校验，不匹配即重分配该槽位；`scratchFlip` 交替语义保留（输出永不别名上游刚返回的平面——同尺寸复用仍交替，别名即 kernel 读写同缓冲腐蚀）；② negotiated-ROI 前置断言补 opName + 三个 ROI + 平面尺寸的诊断信息（ trapping 信息从「哪一位违反」升级到「什么形状违反」，本轮定位时间主要花在补这个）；③ 排障方法：把「管线协商失败」从猜测模块语义改为先读 trap 诊断的形状三元组（roiOut/roiIn/upstream）——形状对了语义自然显形。
- **适用**：一切自管 working-set 复用池（scratch/memo/buffer pool）：池项复用判据必须含**形状**（尺寸/格式），不只槽位；画布增长/裁剪类几何模块与 uncached 腿同框的管线（FULL zoom ROI、EXPORT、Phase 5 tile 腿）。
- **来源**：11-03 T4 ExportRendererE2ETests 双尺寸用例 trap（四态矩阵同步失真 → 最初误归因测试夹具 → 前置断言加诊断后形状三元组一步定位）。

### L031: 模块内 GPU 提交必须走唯一路由获取点——identity blit 硬编 editor queue 在导出链上与 compute 跨队列竞速，产出「两个稳定形态交替」的假非确定

- **现象**（11-03 yiyin 4 态 E2E，11-04 起挂 flaky）：`testYiyinFourStateMatrixAndBorderedRoundTrip` 「双关==基线」断言在 byte-exact 与像素容差 1/255 下都间歇红（byte 漂移 18801/23326 两侧、容差下 max diff 35-38）；修复前隔离也高概率复现（3/4），呈现**两个稳定形态严格交替**（同参数连渲 A/B/A/B，B 形态逐字节可复现），预热 10 轮后收敛到 ≤2 级——「负载下偶发、隔离必绿」的旧口径是时序概率描述而非机制。
- **根因**：① 10+ iop 模块的 identity blit 快速路径（lens/ashift/crop/flip 系/sharpen/localcontrast/equalizer/skinsmooth/soften/liquify/monochrome/borders/watermark）在模块内部自建 `MTLBlitCommandEncoder`，command buffer 硬编 `metal.commandQueue`（editor queue）——绕过 11-03 T1 的唯一路由获取点 `makeCommandBuffer()`（TaskLocal `routesToExportQueue`）；② 导出链 pipe compute 全在 `exportCommandQueue`，这些 blit 在 editor queue，**两队列无任何同步**——下游 compute 读该平面的时刻可能早于 blit 写入：读到旧 plane（含上一渲染残留/零页）→ 后续模块对错输入做确定性处理 → 输出 = 「错输入的完整正确渲染」（两个平滑图像形态，非撕裂/黑块）；③ 竞速两种结局各自确定 → A/B 交替；editor queue 空闲时 blit 恒先完成 → 预热后假绿；全套长跑改变两队列拥塞形态 → 偶发。旁证：修复前逐步探针里 identity blit 后的平面 fence 读回恒 0（fence 在 export queue 等不到 editor queue 的写）。
- **对策**：① `MetalContext.makeRoutedCommandBuffer()` 提为 public，16 处调用点（12 blit 写平面 + 4 读回 fence：wavelet/histogram/borders drain）统一改 `try? metal.makeRoutedCommandBuffer()`——模块级「自建 command buffer」从此同源路由；② 排障方法论：**「同参数渲染多稳定形态交替」≠ 数值非确定/竞态撕裂，优先排查双队列提交源**——用逐步探针（每模块 fresh plane + fence + 读回中心像素）找 alpha/值分叉首点；逐步探针自身读回必须同步 semaphore drain（async `completed()` 有读早竞态，本轮 E5 首版全 0 即此假象）；③ 「GPU 非确定」归因要留质疑：本轮把 11-04 的「GPU 非确定双侧漂移」结论推翻为跨队列竞速——先钉机制再下非确定结论。
- **适用**：一切多队列 Metal 工程（editor/export/preview 分队列 + TaskLocal 路由模式）；一切「绕过统一 encoder/dispatch 门面自建 MTLCommandBuffer」的代码（blit/fence/并行 encoder 同罪）；新增 iop 模块的 identity 快速路径 review 项。
- **来源**：11-03 flaky 专项调试（E1-E5 探针矩阵：E1 自比判别 → E2 冷启动复现+dump → E3 禁用二分 → E4 pipe 直观测 planes 恒定+alpha 异常 → E5 逐步分叉定位；修复后同参数连渲逐字节 0 差）。

### L032: GUI 走查自动化三坑——截图坐标三套比例、IME 候选吃键、AsyncStream 单次消费假 0 行

**现象**（12-1 T6 走查 + T2 迁移测试）：① System Events `click at` 用 pt，screencapture 原图是 2x px（3008 宽 = 1504pt），Read 工具展示又缩到 2000 宽——三套比例混用导致点空（对 2000px 图量出的坐标直接喂 click 全偏）；② `keystroke` 经中文 IME 会弹候选窗吃键（"abc" 变候选列表），粘贴绕开但点击未聚焦时 ⌘V 静默落空；③ 同一 `AsyncStream` 喂两次 `openSession`，第二次得 0 页 0 行——parity 测试首跑 added=0 假象。

**根因**：① 每个环节各自缩放无契约，必须以「pt = 原图 px / scale（scale = 原图宽 / 1504）」单点换算；② TextField 未聚焦时键盘事件去往别处，paste 无声失败——先验证聚焦（截字段区）再输入；③ AsyncStream 消费即枯竭，复用 = 空流。

**对策**：① 走查脚本一律 `sips -g pixelWidth` 或读原图尺寸，pt 换算写成函数不心算；② 文本输入优先「点击 → 截图确认聚焦环 → pbcopy + ⌘V → 回车」，IME 场景先 Esc 消候选；③ 需要 N 次 open 就构造 N 个流（工厂函数），并在断言里加 `added>0` 防空转；④ 合成 click 不携 shift/修饰键进 SwiftUI 手势（`NSEvent.modifierFlags` 读不到）——多选/拖选类交互 AX 驱动不可达，如实记 Manual-Only，不以假阳性截图充当走查证据。

**适用**：一切 macOS GUI 自动化走查（Phase 12-2/12-4/12-5 面板轮、Phase 13）；一切「同 fixture 多次 open」的索引测试。

## L033: 复制调整是编辑器绑定操作——GUI 测试必须匹配设计上下文（2026-09-26，UAT 自答轮）

`编辑/复制调整` 按钮 `.disabled(editorState.loadedImageURL == nil)`：复制的是**编辑器打开文档**的参数（C1 式「复制你看的图」），与网格选中无关。UAT computer-use 自答时在网格态直点菜单=disabled 空点，剪贴板滞留自载荷，产出「粘贴不传输」假缺陷（误报 major，后由干净态单变量测试翻案）。
**对策**：①GUI 验收脚本写步骤前先核对操作的**设计上下文**（哪个面板/文档/焦点），不能纯几何驱动；②粘贴类断言用 sidecar paramsData 字节对比（明文 JSON），勿用 instance 名单（全量中性栈名单恒同）；③误报翻案必须留痕（本条 + UAT G-09-T4 retracted 行），假缺陷记录与真缺陷同等有价值。

## L034: xcodebuild 管道吞码 + 混合代际产物——测试束 dlopen 符号错配的定位与处置（2026-09-27，16-4 T1）

**现象**：Release `build-for-testing` 直启测试束报 `dlopen ... Symbol not found: _$s13LightamerCore...`（mangled 签名 `A2_`/`A3_` 模块引用差异）；排查中两份 `LightamerCore.framework`（DerivedData 根 + app 内嵌）UUID 相同，排除「陈旧副本被优先加载」。真因 = 更早一次构建实际 **TEST BUILD FAILED**——`xcodebuild ... | tail -3; echo $?` 管道让 `$?` 取自 `tail`（恒 0），失败被吞；失败构建留下混合代际产物（旧 LightamerCore + 新测试束）。

**对策**：① xcodebuild 退出码**不进管道**——先重定向落日志再 `echo $?`，或判据改读日志内 `** TEST BUILD SUCCEEDED **` 行（同 test-direct.sh「判据 = 结果行非退出态」的镜像教训：退出态与结果行**都要**看，各防一类假绿）；② 测试束 dlopen 符号错配（同 UUID 框架缺符号）= 混合代际产物症状，处置 = 删该配置 `Build/Products/<config>` 目录全量重编，不逐符号考古；③ 增量编译从未重编的既有测试文件在首次全量重编时才暴露编译错（本轮 CatalogOrganizationTests 的 await-in-autoclosure），切构建方式/重生成工程后预期一轮「编译修复批」；④ `tuist generate` 重生成 pbxproj 后等同全量重编译语义，调度上要预留修复窗口。

## L035: 异步测试的抛错会被任务取消语义吞成 `CancellationError()`——分段 do/catch 打点定位是唯一可靠手段（2026-09-28，14-4 T3 SC#7 链测试）

**现象**：SC#7 链测试报 `caught error: "CancellationError()"`，但分段打点后真实抛点是
`JSONSerialization` 的 "Unable to parse empty data"（SSE `data:` 空载荷行）与
invalidFilter——与取消毫无关系。XCTest async 测试的默认 per-test 任务在被取消（或
foundation/transport 层在错误传播路径上触发取消）时，顶层报错呈现为 CancellationError，
**真实首错被吞**；`Task.sleep` 轮询等待还会把取消放大成必现红。

**处置**：①轮询等待改裸循环 + `usleep`（不 sleep 不 throw，对取消免疫——McpHostTests
`mcpBlockingWait` 同款纪律的推广）；②嫌疑 await 逐个包 `do { } catch { print(位置);
throw }` 二分定位真实抛点；③解析器宽容化（空载荷跳过、失败回退原文），断言放测试层说话。

**教训**：异步测试看到 CancellationError 时**不要相信它**——它是包装纸不是病灶；先分段
catch 打点找真实首错，再修根因。等待原语在测试里一律用不抛的 bounded 轮询。

## L036: 生产路径深处直读进程级开关（env/defaults）= 测试环境继承开关态——开关在组装根读一次、显式注入（2026-09-28，M2-1 T2）

**现象**：M2-1 按 plan T2.1 处方在 `PipeCoordinator` pristine seed 处 env 直读
`!isFullFaceRequested`，全套回归 55 个 PanelWiringTests case 全红（`pristine seed must
include nlmeans` 族）——测试进程无该 env → 生产代码路径在测试中也走 default face →
经 `coordinator.load` 驱动生产路径的既有种子断言全量撞面。同样的撞面在 MCP 侧二连：
`McpHostTests` 期望元组手工构造 full-face seams，对照的生产三形态走 default face（18 vs 15）。

**对策**：①face/flag 类进程级开关**只在组装根（App 启动 task / makeEditingSeams）读一次**，
经参数/字段显式注入下游（`attach(registry:defaultFace:)` / `Seams.defaultFace`），下游默认值
= 旧行为（KD-2 式「默认参数 = full face」）——生产收窄语义与测试隔离同时成立；②「测试自建
构造 vs 生产构造」的期望值对比（conformance 类测试）必须与被测对象**同源同 face**，否则测的
不是传输一致性而是开关态差；③收窄 API 一律带默认参数且默认 = 既有行为，生产组装点显式传新
值——这是零破坏演化的通用形（本次四面验证：populate/seed/panels/catalog）。

**适用**：一切「默认行为切换」类 feature-flag（M2 后续 phases 的 Alcedo 化开关、M2-3 设置
页后端缝）；一切 conformance/一致性测试的期望元组构造。

## L037: SQLiteStatement 复用循环必须 reset-before-bind——DONE 后 rebind/step 即 SQLITE_MISUSE（2026-09-29，M2-2-1 T4）
- **背景**：LibraryStore.removeAlbum 子树级联递减 ref_count，decrement UPDATE 在 imageID 循环内复用同一 prepared statement。
- **现象**：一图入两相册的级联用例抛 `execFailed code 21 "bad parameter or other API misuse"`；单成员路径全绿——复用 ≥2 次才暴露。
- **根因**：`sqlite3_step` 返回 DONE 后语句处于完成态，未 `reset` 就 bind/step 是 API misuse；单次使用（含 fixture 常见的一插一断言）天然免疫。
- **对策**：循环内复用语句一律 `try statement.reset()` 置于每次 bind 之前（与 `SessionIndexSchema.seedProjectMeta` 既有写法对齐）；或每轮 fresh prepare（子树小，开销可忽略）。
- **适用**：一切批量写循环（refcount 批量调整、批量 UPDATE/INSERT faces）；code 21 排查先查复用语句的 reset 缺失。

## L038: XCTest 断言自闭包不持 await/actor 调用——先落局部变量再断言；typed 错误用 do/catch 辅助函数（2026-09-29，M2-2-1 T2/T4）
- **背景**：Swift 6 strict concurrency + actor store API 测试面（`XCTAssertTrue(await store.isOpen)` 型）。
- **现象**：`'await' in an autoclosure that does not support concurrency` / `actor-isolated property can not be referenced from a nonisolated autoclosure`；闭包捕获 XCTestCase self 传 `sending` 参数再触发 region-isolation 错。
- **根因**：XCTAssert* 的表达式参数是 non-async autoclosure；测试类实例非 Sendable，闭包只要引用 `self.xxx` helper 即被编译器拒收。
- **对策**：①actor 调用先 `let x = await store.face()` 再断言；②typed 错误断言写 `assertLibraryError(_:from:)` async 辅助（do/catch + Equatable 精确比，XCTAssertThrowsError 非 async 不可用）；③传给 actor `sending` 闭包零实例捕获——测试 helper 提 static、调用处类名限定（`LibraryStoreTests.insertImage`）。
- **适用**：一切 actor-based store 的单测（M2-2-2/2-3 的 ImportService/LibraryQueries 测试同型）。

## L039: macOS firmlink 下路径拼写三分——列目录一律解析拼写而 URL 保留原拼写，相对路径禁 prefix-cut（2026-09-29，M2-2-2 T3）
- **背景**：ImportService 扫描 temp 目录（`/var/folders/...`）做「源子树相对路径」裁剪；同语义第三处是 ImageLinker kind1 的卷根相对拼写（statfs 挂载点 `/System/Volumes/Data`）。
- **现象**：T3 首轮 6/9 测试失败——mediaRelativePath 错位成 `Card/n1/Card/DSC00001.ARW` 形态（裁剪量与真实前缀差 8 字符 = len("/private")）。
- **根因（三重实测）**：①`FileManager.enumerator`/`contentsOfDirectory` 产出的子路径**一律**解析到 `/private/var/...`，与调用方 URL 的 `/var/...` 拼写不一致；②`URL.resolvingSymlinksInPath()` **不解析 firmlink**（/var 原样返回——firmlink 非 symlink）；③挂载点内拼写 `/System/Volumes/Data/var/...` 不可达（探针 stat 失败）。三者叠加 = 任何基于绝对路径字符串前缀裁剪的相对化都构造性不可靠。
- **对策**：①相对路径**逐层 `lastPathComponent` 积累**（递归下降时拼相对分量，拼写无关）——ImportService 扫描器与测试的 mediaFiles 同款；②「同一文件」断言用 `URLResourceKey.fileIdentifierKey`（同卷 inode 稳定）而非 URL 相等；③涉及卷根相对存储时记录双拼写候选（挂载点前缀优先、`/` 根拼写回退——resolve 双试）。
- **适用**：一切「目录扫描 + 相对路径落库」面（导入、导出、watcher、M2-3 项目包 Media 树列举）；以及任何拿 `/var|/tmp|/Users` 下路径做卷根相对化的代码（根卷 firmlink 三拼写陷阱）。

## L040: git commit -m 双引号串内反引号 = 命令替换——多段 commit message 一律 -F 文件（2026-09-29，M2-2-4 T1）
- **背景**：M2-2-4 T1 首次提交用 `git commit -m "...\`isLegacyLibraryRequested(environment:)\`..."`（body 内含 Swift 签名反引号）。
- **现象**：zsh 报 `parse error near 'legacyLibraryEnabled...'`，提交静默未落（文件仍 staged，无半成品提交）。
- **根因**：双引号串内反引号触发命令替换（command substitution），zsh 先求值再传参——与引号内 `$var` 同族；commit message 习惯性用 markdown 反引号包代码标识符，撞 shell 元字符。
- **对策**：①多段/含代码标识符的 commit message **一律写临时文件 + `git commit -F <file>`**（本会话 T1 起执行）；②失败后先 `git log --oneline -1` 核对未落再重提交（staged 态无害，防重复 add）；③或 heredoc 单引号定界（`<< 'EOF'`）写文件，同样免疫元字符。
- **适用**：一切 shell 内联多行文本（commit/tag/release note）；agent 执行器的 -m 长串场景尤甚。

## L041: tuist generate 必须落在「全部新文件落盘之后」——后建文件缺席旧 project，test-direct 报 Executed 0 防假绿（2026-09-29，M2-3-1 T3）
- **背景**：M2-3-1 批量建文件（T1/T2 generate 一次），T3 的 LibraryThumbnailBridgeTests.swift 在 generate 之后才写盘。
- **现象**：`Scripts/test-direct.sh 'LibraryThumbnailBridgeTests'` 报 `FAILED — Executed 0 tests（过滤名不匹配或旧容器）`；`xcodebuild build` 却 BUILD SUCCEEDED（旧 project 里根本没有该文件——不是编译失败，是缺席）；nm 查 .xctest 二进制零该类符号。
- **根因**：Tuist sources glob 在 generate 时展开；generate 后新建的文件不进 .xcodeproj，build「成功」只是没编它。多 DerivedData 容器（mtime 选择）又添一层迷惑。
- **对策**：①批量建文件的批次内，**tuist generate 永远是该批最后一个动作**（或新文件落盘后无条件重跑 generate——幂等秒级）；②test-direct 的 `Executed 0 tests` 防空转闸门（L028 双读）正是此类缺席的唯一可靠信号，见到先查「文件是否进 project」再查过滤名；③`nm -gU <.xctest>/MacOS/LightamerTests | grep <ClassName>` 三秒定位缺席面。
- **适用**：一切 Tuist 工程「建文件 + generate + build + test」循环（每 plan 批量建文件场景必踩面）。

## L042: Core 写面缺口先查 access level——编排型 plan 的数据缝要落到「可编译的调用」才算缝（2026-09-29，M2-3-2 T4）
- **背景**：M2-3-2 KD-4 数据缝 = `ImageLinker.relinkRecord`（Core public，零改动消费），编排循环在 App 层——plan 期默认「记录重建 = 落库」。
- **现象**：T4 实装发现 `ProjectFileStore.withWriteBatch` 是 internal（M2-2-1 交付面测试经 @testable 使用，App 层不可见）；App 层能算出 relink 记录却没有任何公共写面能落库（`updateProjection` 只写 has_edits/params_hash；remove+insert 破 rowid/FK 级联；第二路 SQLite 连接破 WAL 单写者纪律）。Core 零 diff 红线又禁当场补面。
- **根因**：plan 期的「数据缝」核对只查了「签名存在且 public」，没查「缝的下游依赖是否也 public 可达」——`relinkRecord` 返回值需要写面消费，写面缺席 = 缝悬空。
- **对策**：①编排型任务 read_first 增加「缝 → 下游消费 → 全链 access level」三步核对（grep `public func` 到最终 IO 为止）；②缺口处置 = 注入式 leg + 测试 @testable 真写验证 + 生产诚实 gate（本 plan D2 形态），缺口本体登记 Core-face 小 plan（`LibraryStore.relinkImage` 族）；③禁临时绕路：@testable import 进产品码、第二写连接、remove+insert 换 rowid 全是坑不是路。
- **适用**：一切「App 层编排 + Core 数据面」plan（M2-4+ 节点模型、导出队列、AI 腿同理）；orchestrator 审 plan 时对「壳零 SQL」类约束同时核对写面存在性。

## L043: macOS 27 SDK 废弃 CoreImage legacy C-string option 键——新代码一律 CIRAWFilterOption 现代拼写（2026-09-29，M2-3-3 T4）
- **背景**：M2-3-3 T4 aggregate NR 腿按 pre-27 文档写 `options[kCIInputNoiseReductionAmountKey] = amount`（前任 worker 草稿）。
- **现象**：macOS 27.0 SDK 编译报 `'kCIInputNoiseReductionAmountKey' has been renamed to 'CIRAWFilterOption.noiseReductionAmount'`（CIRAWFilter_Deprecated.h apinotes obsoleted）——错误信息即正确答案，但按旧拼写 grep 全网/头文件样例代码会得出「key 存在」的误判。
- **根因**：`CIRAWFilterOption` 的 legacy C 宏键在新 SDK 经 apinotes 批量改名 Swift 成员拼写；字符串键与 `[CIRAWFilterOption: Any]` 字典键类型不匹配是编译期拦截（好过运行期），但 Apple 文档/社区样例大量仍是旧拼写。
- **对策**：①CIRAWFilter options 新代码一律 `CIRAWFilterOption.<member>` 现代拼写（`.noiseReductionAmount` / `.enableSharpening` / `.imageOrientation` 族，CoreImage.apinotes 为准）；②遇到 `has been renamed to` 错误直接采纳改名，不查旧样例；③MacOSX27.0.sdk 的 `CoreImage.apinotes` 是改名映射的正本（`SwiftName:` 行）。
- **适用**：一切 macOS 27 目标的 CoreImage（含 CIRAWFilter RAW 9）新代码；RAW 9 参数面（M2-5+ 校准）同理。

## L044: 直启选 bundle 唯一旋钮 = XCTestBundlePath env——旧 config plist 的 TestBundlePath 被无视（2026-09-30，M2-4-0 T2）
- **背景**：M2-4-0 拆七 bundle 后 `Scripts/test-direct.sh` 需按域选 .xctest。旧 L019b 配方 = `XCTestConfigurationFilePath` 指向最小 plist（TestBundlePath + productModuleName）。
- **现象**：config 指向 Library.xctest，宿主却加载 App.xctest（字母序首个）；无任何 env 时同样加载 App——**宿主实际行为 = 扫宿主 app 的 PlugIns 取首个 .xctest**，config 的 TestBundlePath 从未被读。
- **根因**：本栈（Xcode 26 直启 + libXCTestBundleInject 注入）bundle 选择唯一被尊重的旋钮 = **`XCTestBundlePath` env**。旧单 bundle 时代「scan 取唯一」与「config 指定唯一」巧合等价，L019b 的 480/3skip 等价性验证无法区分两者；多 bundle 拆分才暴露。
- **对策**：①多 bundle 直启一律 `XCTestBundlePath=<.xctest 绝对路径>`，config plist 整体弃用（test-direct.sh 现正本）；②凡「环境旋钮是否被尊重」的机制断言，必须做**反证实验**（指向 A 加载 B）——单值场景的等价性验证对「根本没读」不设防；③`-XCTest <类>` 过滤不改变 bundle 选择（E3 实验：全限定名也不重定向）。
- **适用**：一切 macOS app-host 直启多测试 bundle 场景；一切「配置文件被无视、行为靠缺省路径」的怀疑场景。
- **来源**：M2-4-0 T2 冒烟 Executed 0 排障（A/E1/E2/E3 四实验矩阵，2026-09-30）。

## L045: 测试宿主内存口径——ps 轮询低估约 2×，ru_maxrss 才是真峰值；积累 ≈17-26MB/test 线性，bundle 拆分不能线性救人（2026-09-30，M2-4-0 T3）
- **背景**：GOAL-STATE 基线「全套峰值 3.73G」来自 ps/活动监视器口径；M2-4-0 按 checker M1 改用 `/usr/bin/time -l` ru_maxrss（内核记账精确峰值，macOS 单位 bytes）。
- **现象**：同一工作负载，精确口径 = 旧口径约 2×（IOP 拆前 6.9-8.1G vs 历史「全套 3.73G」）；七 bundle 实测 IOP 7654MB / Export 6659MB / IOPParity 5788MB，其余 4 域 292-1593MB。按测试数归一：渲染/kernel 密集域 ≈17-26MB/test，轻域 0.7-6MB/test，**跨域同型线性积累**。
- **根因**：①ps 1s 轮询漏瞬态峰（GPU/Metal 池分配尖峰短于采样间隔）；②积累主体 = 跨测试不释放的进程级驻留（CI/Metal 池/缓存，具体根因未查——产品侧 spike 未做）；③bundle 边界只清「进程级」，不清「每测试级」——<3G 硬门 ÷ ~20MB/test ≈ 150 test/bundle，4-7 bundle 粒度数学上不可达。
- **对策**：①设内存门前先用**精确口径**测基线（`/usr/bin/time -l` 包宿主，parse ru_maxrss；ps 轮询只配后备）；②阈值推导 = 目标门 ÷ 实测每测试积累，先算可达性再定 bundle 数；③真解在「每测试/每 bundle 边界释放」（clearCaches/池复位）或接受现实档门 + 运行监视——M2-4-0 OQ 三选一待裁决（SUMMARY「内存事实」节）。
- **适用**：一切长跑测试宿主的内存预算；一切「多进程拆分 vs 单进程清理」的取舍判断。
- **来源**：M2-4-0 七 bundle 矩阵（对账 2165/14/0 精确 + MEMFAIL×3，2026-09-30）。

## L046: 测试装配 tuple 弃元 = 弱引用网静默死亡——`let (a, _, c, d) = make()` 会让被装配对象当场失联（2026-09-30，M2-4-1 T5）
- **背景**：SidecarV5Tests AC7 真链用例需要 EditorState + PipeCoordinator + WorkspaceModel 三方弱引用交叉 attach（生产同款组合根）。
- **现象**：第二套装配 `let (editorState2, _, workspace2, metal2) = makeAssembly()` 把 coordinator 丢进 `_`——decode 完成、image 就位，但 pipe load / sidecar restore / 恢复腿全程不发生；排障三轮（hook 到没到 / store 读没读到 / 探针进没进）才定位：**`_` 绑定 = 值立即释放**，弱引用集体归 nil，`guard let` 全部静默走丢失分支（os_log 不可见，stdout 无痕迹）。
- **根因**：Swift tuple 解构的 `_` 槽不持有强引用；组合根类全是 weak 互指（防环纪律的正确设计），装配面一旦无人强持有，整网静默蒸发——不是 bug，是生命周期契约被测试写法击穿。
- **对策**：①多对象装配 helper 的返回值**每个槽位具名绑定**（哪怕 `let c = ...; _ = c` 保活到 scope 尾）；②装配型测试的断言失败先查「被测对象还活着吗」（weak 网存活检查）再查业务逻辑；③排障 instrumentation 优先打在**守卫出口**而非入口（本例三轮入口探针全绿、出口早退，教训即此）。
- **适用**：一切「weak 互指 + 外部强持有」的组合根测试（EditorState/PipeCoordinator/WorkspaceModel 族、未来 NodesPanelModel 同款）；一切「静默不作为」类失败的生命周期排查。
- **来源**：M2-4-1 T5 AC7 真链用例三轮排障（hook/store/探针三级 instrumentation，2026-09-30）。

## L047: xcodebuild 增量构建漏 .metal 重编——drift 值逐位不变即 binary 陈旧信号（2026-09-30，M2-5-1 T3）
- **背景**：CAT02 golden 测试 kernel vs Swift 参考漂移排障：改 `.metal`（含 precise:: 数学替换）后重跑，drift 数值**逐位一致**（1.453622958171752 连续三轮相同）。
- **现象**：`xcodebuild build-for-testing` 显示 TEST BUILD SUCCEEDED，default.metallib 未吸收新 kernel 源；touch `.metal` 文件后 MetalLink 才真正重跑。
- **根因**：外置卷工程（L009 环境族）+ 增量构建的 .metal mtime 探测失灵——源码已改、产物陈旧，编译器无告警；「测试跑绿/跑红但数值纹丝不动」是唯一症状。
- **对策**：①kernel golden 排障时**先 touch 全部相关 .metal 再重建**（成本秒级，排除陈旧维度）；②漂移数值逐位不变的复跑 = binary 未换的强信号，此时改源码无意义，先解决构建；③新建 `.metal` 文件必须 `tuist generate`（新文件不在 pbxproj 编列，metallib 永不包含——functionNotFound 同根因）。
- **适用**：一切 Metal kernel 的 golden/parity 排障；外置卷工程的增量构建信任问题。

## L048: GPU golden 比较空间选型——encode 对数腿零点斜率放大 f32 固有误差 750×（2026-09-30，M2-5-1 T3）
- **背景**：CAT02 golden 逐 texel 比较，个别样本 encoded 域漂移 ~1e-4，其余 ≤1e-7——离群点全部落在 adapted linear ≈ 0 的 texel。
- **根因**：ACEScc encode 对数腿斜率 = 1/(x·17.52·ln2)，x→0 时发散（x=1e-4 处 ~750×）：f32 kernel 的固有 epsilon（linear 域 ~1e-7，f32 求和不可消除）在 encoded 空间被放大两个数量级——不是 kernel 错，是**比较空间选错**。
- **对策**：①ACEScc 域 op 的 golden 比较一律 decode 回 linear 再比（斜率 ~12×，对零交叉稳健）；②Swift Float64 参考的数学常数用**出厂 f32 值升 Double**（`Double(Float(17.52))`）——精确十进制参考会把常数舍入系统差（decode 斜率 ~4e-5）烤进每个线性腿样本；③encoded 空间统计按 plan 原文做 [-0.5, 2.5] 窗裁剪，病态参数化（适应阵元 ~1e10 角点）只做 bounded/NaN 断言——f32 求和消散在该处数学上不可达 1e-5。
- **适用**：一切对数域传输函数（ACEScc/log 编码）两端 op 的 golden/parity 容差设计；任何「大部分样本极好、零交叉样本离群」的漂移形态归因。

## L049: 定向轮残留目录吃穿系统盘——ENOSPC 让后续 bundle 假性挂测试（2026-10-01，M2-6-2 T5）
- **背景**：App bundle 首轮 3 fail（2×Vision Code=9 + 2×ENOSPC），复跑只执行 10/376 且宿主
  "terminated abnormally" 于 SidecarV5 写盘测试。
- **根因**：`/private/var/folders/.../T/sidecarv5-*` 测试夹具目录（每个 ~71MB RAW 拷贝）**只在
  全绿时清理**——fail/中断轮残留累积 193 目录共 13GB；系统盘自由空间跌到 ~6G 后 RAW 拷贝
  ENOSPC → 级联假失败 + 宿主异常终止。重跑不清残留 → 逐轮恶化。
- **对策**：①App bundle fail 且错误带 `NSPOSIXErrorDomain Code=28` / "No space left" 时，先
  `rm -rf $TMPDIR/sidecarv5-*` 再归因（本次 13GB 即释）；②测试自身夹具改 `TearDown` 强清是
  正解（挂账，改测试非本 plan 半径）；③Vision Code=9 "Unspecified error" 在磁盘压力下同发，
  清盘复跑即绿——不要当场归因产品代码。
- **适用**：一切「测试夹具写盘 + 仅成功路径清理」的 bundle；夜间连跑多轮后 App/Sessions 类
  写盘重测先查 `$TMPDIR` 残留。

## L050: 版本 pin 触点穷举靠 grep 不靠人工枚举——checker 四处名单漏了第五处+一个 LIB bundle 字节 golden 家族（2026-10-01，M2-8-1）
- **背景**：sidecar `schemaVersionCurrent` 6→7 升版，checker E3 人工穷举版本 pin
  测试触点四处（DrtSidecarTests/LibraryDocumentTests/DefaultLookTests/
  LibrarySchemaTests）；执行期实测又冒出三处同类：DrtPersistenceTests:325（APP）
  、SidecarMetadataV3Tests:178/250/261/265/268（LIB bundle 字节 golden——含
  `\"schemaVersion\" : 6` 字面 diff 期望集）、DefaultLookTests 快照文件名触点。
- **根因**：版本号既是「断言值」又是「字节 golden 的组成」——凡 pin 字节形的测试
  都可能嵌字面版本位；人工枚举按「测试名/主题」联想必漏。症状固定：升版后全套
  必红，失败行即完整名单。
- **对策**：升版任务把「`grep -rn 'schemaVersion.*: 6\|== 6\|, 6)' Tests/` + 字节
  golden 测试全名单」列为 T1 机检步骤，跑红即穷举（每处改引
  `schemaVersionCurrent`，一次修毕三代免改）；勿在 plan 期承诺「除点名处外零改动」
  ——以机检名单为准写入 front-matter。
- **适用**：一切 one-way format lock 升版（sidecar/.lalb/预设）；连带触发面
  （如迁移快照文件名）同批穷举。

## L051: store open 期间持第二读连接挡 TRUNCATE checkpoint——statement 停在 SQLITE_ROW 即持 WAL 读锁（2026-10-01，M2-8-1 T3）
- **背景**：迁移测试在 `store.open()` 后开 `SQLiteHandle` 读 user_version/行数，
  close 顺序换成「读句柄先关」仍 busy=1/log=4。
- **根因**：`SELECT COUNT(*)` step 返回 ROW 后未 drain，statement 停在半途持隐式
  读锁；`sqlite3_close_v2` 对含未 finalize statement 的连接转 zombie，读锁不放，
  store 的强制 `wal_checkpoint(TRUNCATE)` 必败。测试代码问题，非产品 checkpoint
  纪律问题。
- **对策**：测试需要读迁移结果时用 DefaultLookTests 形态——`store.close()` 后再
  开 detached 句柄读（TRUNCATE 已完成，读的是干净态）；必须 open 期间读的，走
  store 自身 seam（withHandle）且 statement 读完 drain。
- **适用**：一切「checkpoint 纪律 + 测试旁路读」组合（SessionIndex 同族）。

## L052: NSApplicationDelegate 可选回调形参类型错写 = "nearly matches" 警告即永不触发（2026-10-01，M2-8-2 T4）

- **现象**：kill -9 走查发现清退腿从不执行——`applicationWillTerminate(_ application: NSApplication)`
  的形参类型写错（协议正身 = `(_ notification: Notification)`），Swift 6 报
  "nearly matches optional requirement" 警告但**不接 ObjC 选择器分发**，回调自
  02-06 起从未真正触发；2s debounce 常态下先于退出写完盘，缺口被完全掩盖。
- **根因**：@objc 协议可选要求按选择器匹配，形参类型不符 = 选择器不存在 =
  永不调用；编译器只给 warning 不给 error。
- **对策**：①"nearly matches" 警告一律当 bug 修（对表协议正身签名），不当代
  码异味容忍；②依赖 delegate 回调的面（flush/哨兵/终止清理）必须有运行期验证
  走查（defaults/file 痕迹读回），编译绿 ≠ 回调活。
- **适用**：一切 NSApplicationDelegate/UITraitEnvironment 等 @objc 可选回调的
  手写实现。

## L053: macOS 27 自建 ICC 三坑——CalibratedRGB 生成器坏、para fn=0 被误解析、嵌入写出行重序列化（2026-10-03，M2-9-02 T1/T2）

- **现象**（三个独立坑，同属「程序构造 ICC profile」家族）：
  ①`CGColorSpaceCreateCalibratedRGB` 在 macOS 27 生成的 ICC **非合规**——wtpt
  携带原始色度 (x,y,1) 而非 D50 PCS 三刺激、bXYZ 退化为 (32768,1,-32768)、三个
  TRC 标签同一偏移；任何经它的 ColorSync/CI 转换返回垃圾（灰→0 或补色）。
  ②ICC v4 `para` fn=0（单参数 gamma）TRC 被 ColorSync **误解析**——同矩阵同
  gamma 换 `curv` count=1 就精确转换（linear 0.5 → γ2.2 编码 0.7297 钉死），
  para 则跨 profile 转换塌缩成 0/1。
  ③含自建 ICC 的 PNG/TIFF **文件字节跨渲染不稳定**——ImageIO/ColorSync 写出时
  对自定义嵌入 profile 重序列化（iCCP 块内等长、早偏移漂移、时敏抖动），两次
  渲染像素逐字节相同而文件不同。
- **根因**：①②= 平台缺陷（探针证据在 M2-9-02-DECISIONS §1；Alcedo 自带 .icc
  资产同 d50+chad+para 结构但行为以实测为准）；③= 写出路径对非系统 profile 的
  规范化/重盖章，非确定性源在框架内部。
- **对策**：①弃 CalibratedRGB，自建 ICC v4 matrix-shaper 字节（Bradford D50
  适配 + D50 wtpt + chad + curv-1 TRC）走 `CGColorSpace(iccProfileData:)`
  （deprecated 但工作）；②TRC 一律 curv count=1（u8Fixed8 载体 1/256 量化为
  ICC 格式自身地板）；③跨渲染恒等断言只钉**像素 parity + profile 名**，文件
  字节恒等只对系统 profile profile（sRGB 等）使用；ICC 载体字节确定性单独在
  纯函数层钉（copyICCData 相等）。
- **适用**：一切程序化 ICC 构造/嵌入场景（导出 ICC、软打样、HDR 容器 V2）；一
  切「同渲染两次文件字节应相等」的 golden 设计（先确认嵌入数据不走重序列化）。
- **来源**：M2-9-02 T1 探针（probe2-probe8 行为矩阵 + probe13 para/curv 对照 +
  T2 队列 parity 测试的 iCCP diffAt=58 诊断）。

## L054: ImageIO 写入面 ≠ readback 面——seat/payload 断言先字节探针，readback 会双向说谎（2026-10-03，M2-9-03 T2/T3）

- **现象**（三族独立坑，同属「ImageIO 元数据断言」家族）：
  ①**seat 双向假象**：`{Exif}["Software"]` 键在全部容器被 writer 静默丢弃
  （EXIF 0x0131 是 IFD0 tag，不属 Exif IFD 面）；`{TIFF}["Software"]` 写入
  JPEG EXIF APP1 后 **readback 永不回显 `{TIFF}`**（字节在、readback nil，
  probe4 H 双证）——readback 断言假阴性；裸 Software 单键 `{TIFF}` dict 又
  被 JPEG writer 整体丢弃（round-trip Exif dict 在场才序列化）。
  ②**profileName 推断回落**：已知空间（sRGB）的 JPEG/PNG 产物 writer **不嵌
  任何 profile payload**（JFIF marker / sRGB chunk 推断），untagged 化后
  readback 仍报 "sRGB IEC61966-2.1"（JPEG/TIFF 面）；PNG 才真 nil——
  「profileName nil == 未嵌入」断言假阳性/假阴性双向。
  ③**跨 ICC 上下文 decode 不可比**：同一文件带/不带嵌入 profile 经
  color-managed decode 出不同 device 值——「剥离前后像素相等」的 decode
  比对在 ICC 面测试中天然不成立。
- **根因**：ImageIO 的属性 readback 是**推断合成的展示面**（inferred
  defaults + 命名空间重映射），不是容器字节的镜像；writer 对「已知空间」
  走省略优化、对「不可归属键」静默丢弃——三者都不告警。
- **对策**：①任何 seat/payload 断言先 ObjC 探针**字节取证**（`strings`/
  marker 逐段走查），再选断言面——字节在 readback 不回显的容器走
  byte-scan；readback 面断言只用于探针证实回显的容器。②「未嵌入」断言 =
  payload 签名缺席（`ICC_PROFILE`/`iCCP`/`acsp`）+ typed 无 payload 降解
  面，不用 profileName。③ICC 面完整性断言用**剥离确定性**
  （`stripped == strip(embedded)` 逐字节）+ 熵流/IDAT 恒等，不用 decode
  像素比对。
- **适用**：一切 ImageIO 元数据 seat 消费（EXIF Software/GPS 剥离、TIFF tag
  面、容器 ICC tier）、导出 tier 测试设计、任何「writer 写了 X」类主
  张的验证。
- **来源**：M2-9-03 T2/T3 探针（probe2–probe9 + 测试三轮迭代：裸 dict 陷阱/
  host trio 面/TIFF 孤儿清零）。

## L055: test-direct.sh 崩溃假绿——宿主中途 crash 时解析器取末条类 suite 行当 bundle 计数（2026-10-03，M2-9-03 收尾）

- **现象**：全套 --all 轮 App bundle 宿主在 `HistoryRowJumpTests` 中途 crash
  （`time: command terminated abnormally`，126 tests 已过），BUNDLE 行却报
  `App|15/0/0` 且脚本整体 EXIT=0——bundle 计数 = 日志中**末条
  `Executed N tests` 行**，恰是崩溃前最后一个完整类 suite（GradeCatalogTests
  15 tests），非 bundle 总计。
- **根因**：脚本判据 = 「测试结果行」（L019b 家族设计），但未区分「类 suite
  的 Executed 行」与「All tests 总计行」，也未把 `terminated abnormally`
  / 宿主异常退出当作 bundle 失败信号——崩溃恰落在类间时输出形似正常完成。
- **对策**：①读全套数字先 `tail` 各 bundle 段核对「末条 Executed 是否
  All tests 总计 + passed 数与 BUNDLE 行一致」；②`grep "terminated
  abnormally\|Restarting after unexpected exit" <log>` 作为崩 Vanity 信号
  纳入人工/验收轮机检；③脚本级修复（崩溃签名 → bundle FAIL）另案报备
  orchestrator（M2-9-03 执行波不改脚本，front-matter 外）。
- **适用**：一切 test-direct.sh 结果判读（执行波/验收波/巡检）；任何「按
  末条结果行取数」的日志解析器设计。
- **来源**：M2-9-03 收尾全套跑 1（App 15/0/0 假绿 → 隔离复跑 ×2 揭示：
  481/0/1 + 481/0/0）。

## L057: macOS 27 NSOpenPanel 取消路径可 SIGSEGV——面板「取消」腿必须 GUI 走查覆盖（2026-10-03，M2-9-05 走查 F-1）

- **现象**：Import Folder 面板（NSOpenPanel.runModal）点「取消」→ app
  SIGSEGV，2/2 复现；`.ips` 栈 = `swift release_dealloc` 链至 SwiftUI
  `destroy for Button`（闭包过度释放，"Could not determine thread index for
  stack guard region"）。`.ips` 存档
  `~/Library/Logs/DiagnosticReports/Lightamer-2026-10-03-072103/-072747.ips`。
- **根因**：runModal 的模态返回路径上 SwiftUI 闭包销毁顺序问题（M2-3 时代
  导入面板装配）；单测不可能覆盖（runModal 阻塞主线程，测试宿主无法驱动）。
- **对策**：①一切 NSOpenPanel/NSSavePanel 调用点的「取消」腿必须真机走查
  （单测绿 ≠ 面板取消活）；②临时规避 = 不取消面板（重开代替）；③修复另案
  （面板调用点包 autoreleasepool 或改异步 presented 形态，归 M2-3 面小修）。
- **适用**：一切 macOS 面板（open/save/modal）调用点；GUI 走查清单必须含
  每个面板的取消腿。
- **来源**：M2-9-05 走查批（2026-10-03，导入夹具时两次取消即崩）。

## L058: String.LocalizationValue 插值字面量 = 查表键带 %@ 占位——catalog 无该键时静默回退裸键观感（2026-10-03，M2-9-05 走查 F-2）

- **现象**：导出页格式 Picker 显示裸键 `export_format_jpeg`——而 catalog 明明
  有该键（zh/en 双语 JPEG）。`String(localized: String.LocalizationValue(
  "export_format_\(kind.rawValue)"))` 的插值字面量使 LocalizationValue 携带
  pattern `export_format_%@`——运行时查表键是 **`export_format_%@`**（不存在）
  → 回退渲染「pattern 代入实参后的文本」= 拼接结果 = 裸键观感。
- **根因**：`String.LocalizationValue` 把字符串插值编译为 format pattern；
  与「先拼好完整字符串再查表」的直觉相反。zh-audit `--check` 静态扫描看到
  的是源码字面量 `export_format_` 前缀 + 六静态键在册 → PASS 不报——查表键
  （含 %@ 的动态形态）对 scanner 不可见（M2-7-3 xcstrings 动态族教训同族）。
- **对策**：①动态查表键一律先落常量再包装：`String.LocalizationValue(key)`
  （key 为 String 变量、无插值）——查的就是拼接结果本身；②禁止
  `String.LocalizationValue("prefix_\(x)")` 形态入码（review 项）；③catalog
  键的运行时有效性验证靠 GUI 走查首屏中文渲染检查（L025 防线②），不靠
  zh-audit。
- **适用**：一切 String Catalog 动态键构造（本项目第二次踩：06-07 L025
  zh-Hans 标签、本次插值 pattern）；zh-audit 工具的能力边界注记。
- **来源**：M2-9-05 走查批（证据 `.work/gui-acceptance/m2-9/m2-9-01-export-page-five-sections.png`）。

## L059: 外部内容 FTS + INSERT OR REPLACE = 索引静默双文档（2026-10-03，M2-10-02 T2）

- **现象**：`replaceUnderstanding` 用 `INSERT OR REPLACE` 落 UNIQUE(image,task)
  行后，`MATCH '旧词'` 仍命中、新词也命中——外部内容索引同 rowid 挂了**两份
  文档**。
- **根因**：SQLite 的约束解决删除（REPLACE 撞 UNIQUE 时的隐式 DELETE）**只在
  `recursive_triggers=ON` 时才触发 DELETE 触发器**（默认 OFF）——AFTER DELETE
  腿没执行，FTS 'delete' 命令没入，旧行词项残留。普通显式 DELETE 恒触发。
- **对策**：外部内容 FTS 表上的 upsert 一律**显式 DELETE 再 INSERT**（同事务），
  禁 INSERT OR REPLACE；FTS 同步测试必须覆盖「同 task 重写后旧词不再命中」腿。
- **来源**：M2-10-02 SemanticStoreTests（testUnderstandingReconcileFlipsActiveAndMirrorsFTS 首轮红）。

## L060: 内置 CoreML .mlpackage 三坑——需 compileModel、cropping 返 nil、fp16 输出 trap（2026-10-03，M2-10-02 T4）

- **①未编译包拒载**：`MLModel(contentsOf:)` 对 `.mlpackage` 目录直接报错
  （"Compile the model with Xcode or MLModel.compileModel(at:)"）——内置资产
  必须先 `MLModel.compileModel(at:)`（CLIP img 塔 ~21s），`.mlmodelc` 缓存进
  `~/Library/Caches/…`（可重建派生物）跨启动复用，否则每次启动白付编译。
- **②cropping 对 context-backed 图返 nil**：`CGImage.cropping(to:)` 在
  CGContext `makeImage()` 产物上实测返回 nil（RAW 解码帧同族风险）——resize
  +center-crop 用**单次 bitmap context draw**（负偏移原点 + 高质量插值），
  万无一失。
- **③量化模型输出是 FP16 MLMultiArray**：int8 权重 + fp16 激活的转换产物，
  输出数组 dataType = float16——`withUnsafeBytes` 里把指针 `bindMemory(to:
  Float.self)` 直接 EXC_BREAKPOINT（测试宿主 crash，.ips 帧落在闭包内）。
  读向量用逐元素 `NSNumber.doubleValue`（MLMultiArray 下标），几百元素零成本；
  或按 `dataType` 分派。**别对 MLMultiArray 的 scoped 字节接口做类型重绑**。
- **附**：`MLMultiArray.withUnsafeMutableBytes` 闭包是双参（指针 + strides
  `[Int]`）；`MLModel.prediction(from:options:)` 在 Swift 6 并发导入为 async。
- **来源**：M2-10-02 M5 真模型 sanity（资源门激活态）三轮 bisect，证据链
  `.ips` ×2 + 探针 probe 汇总在 M2-10-02-DECISIONS §4。

## L061: vDSP/Accelerate 半精度检索的 API 实名与形状（2026-10-03，M2-10-02 T3）

- **fp16→fp32**：研究稿 `vDSP_vconvert` 无 half 重载（`vDSP.convertElements`
  亦无）——可用原语 = `vImageConvert_Planar16FtoPlanarF`（vImage_Buffer 支持
  多行块、可直指平面 payload 零拷贝）；逐元素 Swift 循环在 -O 下 106ms/20 万
  行不可用。点积实名 = `vDSP_dotpr`（`vDSP_dotv` 不存在）。
- **逐行 Data 面的 Debug 宿主税**：200k 行 × 每行 `Data.copyBytes` 桥接在
  Debug 宿主 +25ms 量级——生产扫描面必须整表平面 buffer（装载时一次 memcpy
  合并），预算哨兵量在生产形状上，别让 sketch face 的形状税污染预算结论。
- **来源**：perf.md §A.3 方法学注记 + 独立 -O 探针（转换 15.4ms/点积 8.0ms/
  逐行循环 106ms）。

## L062: Data.resetBytes 默认 range 是 0..<0——裸调用清零零字节（2026-10-04，M2-10-04 T1）

- **背景**：Keychain 凭据读出缓冲的 zeroize 契约（M2AI-06：读出 Data 用完
  resetBytes）。
- **现象**：`key.resetBytes()` 直接编译错 `missing argument for parameter 'in'
  in call`——直觉以为 resetBytes() 无参可用。
- **根因**：Foundation 的 `Data.resetBytes(in range: Range<Data.Index>)` 的
  默认值是**空区间 0..<0**（文档语义 = 不清任何字节）。本 SDK 把默认实参去掉
  强制显式 range，编译期拦住了「以为清了其实没清」的静默安全洞；但旧文档/
  AI 样例大量演示无参调用。
- **对策**：①全项目 zeroize 一律 `resetBytes(in: 0..<count)`，字节级断言
  （allSatisfy == 0）钉在测试里，不以「编译过 = 清了」自证；②安全相关 API
  的「默认参数」要查签名实义——默认值本身可能就是 no-op（本例是幸存的编译错，
  若默认实参在就是静默零防护）。
- **适用**：一切密钥/明文缓冲用后清场景（凭据、剪贴板敏感串、导出密钥）；
  一切「安全行为靠约定」的 API 消费。
- **来源**：M2-10-04 AICredentialStoreTests E4 断言首写（2026-10-03），
  DECISIONS §4。

## L063: UInt8 原位移位仍是 UInt8——多字节大端装载必须先宽化再移位（2026-10-03，M2-10-05 T1）

- **背景**：worker 帧协议的 4 字节大端长度前缀解码写成
  `UInt8(byte0) << 24 | …`——Swift 里 `UInt8 << 24` 的移位结果类型仍是
  UInt8（模 256 截断），5359 字节的帧长度 0x14EF 被读成 0xEF = 239，
  JSON 尾部截断后解码报「格式不正确」。
- **根因**：Swift 整数移位是**同类型**运算，不自动宽化；小端/单字节
  路径永远踩不到，只有载荷 >255 字节的帧才暴露——golden 测试用 25 字节
  小帧全绿（低位字节掩蔽了 bug），是 512 维 float 数组的 ~5KB 帧当场抓出。
- **对策**：①逐字节装载一律先 `UInt32(byte)` 宽化再移位；②帧协议测试
  必须含 >255 字节载荷的 round-trip（单字节 golden 是假覆盖）；③
  `load(as: UInt8.self)` 后紧跟移位的代码是固定审计点。
- **适用**：一切二进制协议头/长度前缀/魔数解析（本仓后续：sidecar 容器、
  导出封装、IPC 通道）。
- **来源**：AIWorkerProtocolTests testResponseRoundTripKeepsEmbeddingPrecision
  首跑红（2026-10-03），独立 swiftc 复现器定位。

## L064: 同步阻塞的 actor 方法饿死执行器——actor 内派生子任务等不到调度即死锁（2026-10-03，M2-10-05 T2）

- **背景**：worker 主循环 `serve()` 是同步 actor 方法，循环体 blocking 读
  管道（availableData）；`run` 的 async 推理腿用
  `Task { await self.forwardRun(...) }` 派发——子任务永远排不上该 actor
  的执行器（同步方法不挂起、不让位），run 请求零响应 → 客户端超时 kill
  → 降级链三档全烧 → exhausted。ping/open/spike 全内联处理所以只有
  run 挂（症状高度误导，像是模型/ANE 问题）。
- **根因**：actor 的串行执行器被同步阻塞占用 = 该 actor 上一切后续任务
  （包括自己派生的）饿死。Swift actor 不是线程，是「挂起点之间的互斥」
  ——blocking call 没有挂起点。
- **对策**：①actor 方法内禁派生依赖同一 actor 的子任务——要么内联
  await（本例：`await forwardRun(...)`，await 挂起即让位），要么把阻塞
  读移出 actor；②「部分 op 有响应、部分 op 零响应」的 hang 先查执行器
  饿死再查模型；③专用进程里的阻塞读可容忍（无其他任务可饿），但必须
  保证无子任务派生。
- **适用**：一切 actor 包 I/O 的形状（SidecarStore/PipeCache 家族复核过
  无此形态；后续 worker/长任务 actor 遵此）。
- **来源**：AIWorkerClientTests testRealModelEmbedImageThroughWorkerProcess
  482s exhausted 首跑（2026-10-03）；python 管道探针复现 run 响应缺失。

## L065: 裸 `await taskHandle` 不等待任务——join 必须 `await task.value`（2026-10-04，M2-10-06 T3d）

- **现象**：测试里 `let runTask = Task { await model.run() }` … `await runTask` 后立刻断言
  run 的终态，断言看到的是中间态——`await runTask` **零等待立即返回**（独立 swiftc 探针：
  join 返回耗时 0.0s，被等任务 300ms 后才完成）。
- **根因**：`Task` 句柄是普通 Sendable 值；裸 `await` 作用其上是**冗余 await**（对非挂起
  表达式的合法 no-op），不是 join。真正等待 = `await task.value`（throwing 任务再 try）。
  心智陷阱来自 `async let` 的**隐式 join**语法（`await (a, b)`）——那是对 `async let`
  绑定的特例，不适用于显式 `Task {}` 句柄。
- **对策**：①join 一律写 `await task.value`（或 `try await task.value`）；②「await 了
  Task 却看到中间态」先查本条再查 actor 饥饿；③冗余 await 编译器不警告——测试里 join
  后断言终态的形状是固定审计点。
- **适用**：一切 unstructured Task + 测试/调用方需要等终态的场景。
- **来源**：EnhanceDialogTests testCancelMidRun 首跑 2 连红（2026-10-04），独立 swiftc
  复现器定位。

## L066: 插值键 + defaultValue 不能共存——StaticString 限制（2026-10-04，M2-10-07）

- **现象**：`String(localized: "key \(x)", defaultValue: "…\(x)…")` 编译报
  「cannot convert value of type 'String' to expected argument type
  'StaticString'」——带 `defaultValue:` 的重载要求 key 为 StaticString 字面量，
  插值 key 走的是「keyAndValue」重载（无 defaultValue，文案全靠 catalog）。
- **根因**：Foundation 两个重载的 key 参数类型不同（`StaticString` vs
  `String.LocalizationValue`）；插值只有后者接受。
- **对策**：①插值键一律 `String(localized: "key \(x)")` + catalog 双语条目
  （键族提取照常覆盖，zh-audit 动态族规则 c）；②格式占位 = Int→`%lld`、
  String→`%@`（Error 需先 `String(describing:)`——Error 不 conform CVarArg）。
- **适用**：一切本地化新键；静态键 + 插值 defaultValue 合法（format 编译进
  defaultValue），二选一。

## L067: URLProtocol 子类嵌在 @MainActor 测试类里继承隔离——文件顶层放置（2026-10-04，M2-10-07）

- **现象**：`@MainActor final class XTests` 内嵌 `URLProtocol` 子类，startLoading
  报隔离冲突（主 actor 隔离方法覆写 nonisolated 方法）。
- **根因**：嵌套类型继承外层 actor 隔离；URLProtocol 的回调来自 session 队列
  （nonisolated）。
- **对策**：mock URLProtocol 放文件顶层（AIProviderClientTests 外层非隔离所以
  没踩过——抄它的嵌套形态到 @MainActor 类里才爆）。
- **适用**：一切 @MainActor 测试类 + 协议 mock 回调形状。

## L068: SwiftUI Slider 自动化驱动 = drag 语义——合成单击不改值（2026-10-07，M2-11-04 T1）

- **现象**：CGEvent 合成单击（down/up 同点，clickState=1）打在编辑器色温滑块 thumb 中心与轨道上，值零变化（6504K 纹丝不动）；同一坐标换 `leftMouseDown → leftMouseDragged ×12 → leftMouseUp` 序列立即改值（23521K，截图实证）。按钮/菜单/toggle 单击照常可达（波形 toggle 实证切换）。
- **根因**：SwiftUI Slider 的值变更绑在拖拽手势的连续编辑路径；合成单击不携带 moved 事件序列，不触发真鼠标 NSSlider 的 track-click-to-jump 行为——合成事件语义 ≠ 真鼠标语义的又一例（L032 ④ 合成 click 无修饰键的同族）。
- **对策**：①AX/CGEvent 驱动滑块一律 drag（down → 分步 dragged → up，驱动源 `phases/m2-11-performance/profile/cgdrive.swift`）；②值是否真改必须截图/AX 复核（本轮首轮 click 序列 10 连击全部空点、截图发现值未动——「事件发了」≠「控件吃了」）；③滑块坐标从原分辨率截图量取再换算 pt（L032 ① 比例纪律）。
- **适用**：一切 macOS GUI 自动化滑块驱动（M2-11-05 GUI 走查轮、hitch 计量轮、Phase 12/13 走查脚本复用）。

## L069: coordinator live box 集跨重叠 render Task 共享——IOP 模块可变引用态必须加锁（2026-10-07，V2/Maintenance 首波 ToneEqual 修复批）

- **现象**：SIGTRAP `swift_unknownObjectRetain` ← `ToneEqualModule.dispatchPack/dispatchLuma`（.ips ×2；崩点漂移跨测试类、隔离复跑全绿、当日 5 红 2 绿、盘/缓存卫生后净轮——统计性不复发 ≠ 根因消除）。.ips 亲读实锤：faultingThread 13（测试 `load` 腿渲染）与 thread 3（先前 `notifyLayerChange` fire-and-forget Task 渲染仍未返回）**两路并发同在 ToneEqualModule.process 内**。
- **根因**：PipeCoordinator 的 renderPreview 是 fire-and-forget Task，generation 门只丢弃**结果**、从不取消在飞 run；两次重叠 run 共享同一 live `instances` box 集 → 同一 `ToneEqualModule` 实例并发 `process`。模块类的引用态可变存储（ToneEqual `scratch` 结构体含 8 个纹理/缓冲引用且按平面尺寸**整体替换**、`resolvedDevice`/`pieceBuffer`/`lutBuffer`）无同步 → 撕裂引用被强 retain = `swift_unknownObjectRetain` 陷阱（release 侧 = SIGSEGV 形态）；崩点随堆态漂移、单测隔离恒绿。「pipe 串行 per run」成立，**跨 run 无串行化保证**才是缺口。
- **对策**：①有引用态的 IOP 模块，全部读-改-写窗口用 `NSLock` 守护（ToneEqualModule `stateLock` 先例：commitParams/ensureScratch/process 三处提取窗口，锁内零 await，微秒级）；process 入口把引用**提取为局部**后全程只用局部。②GUI-10/GUI-13 先例（apply 同步化）同理推广：跨线程共享的类实例，凡引用槽位写入都要么单 owner 要么加锁。③同型存量：NLMeans/DenoiseProfile 的 scratch 元组、全模块 pieceBuffer 模式——出现同签名崩溃按此方处置（登记 Maintenance）。④协调面根治（render 串行化/取消传播）= 架构级改动，挂 Maintenance 不随手做。
- **适用**：一切 IOPModule 实现（含新模块评审项：引用态字段清单 + 锁纪律）；任何「共享 box 集 + 重叠异步 run」的管线形态。
- **来源**：V2/Maintenance 首波修复批（2026-10-07，commit 见 GOAL-STATE 续接点；证据 `phases/m2-11-performance/profile/appbundle-crash-2026-10-07-0812.ips` + Flaky 台账 2026-10-07 行）。

## L070（2026-10-08）— 全史手术日：message 重写 + 媒体剥离一体批
- **触发**：M1 时代 33 条中文 message（09-20~24，规则生效前）用户令重写；顺带发现 `.work` 2.8G 大头 = Phase 1 RAW 样片（~625MB）与双份 fixtures（~290MB）被 commit 入史（pack 1.91GiB）。
- **做法**：①filter-branch --msg-filter 按 `$GIT_COMMIT` 键 `/tmp/rewrite-batch/new/<old>.txt` 定向 main ②filter-repo `--invert-paths --path <fixtures> --strip-blobs-bigger-than 50M`（70s，pack 1.91GiB→907MB）→ ADO 单次 force-push 瘦身史（避免 1.9GB 胖史 + 瘦身史两次全量重传）。
- **教训**：①**evidence 入仓的仓禁做 message 级手术而不掂量传输**——SHA 级联 = 全量重传，体积 = pack 全重；②msg-filter 的 `%B` 会被 git 补尾换行（byte-compare 假阴性），**SHA 映射用 subject 首行匹配构建**最稳（33/33）；③`git filter-repo` 保留 remotes/Worktree 但会重写 refs/stash（pop 回即可）；④子代理 SSH 能力完好（launchd agent 继承、ADO auth 实证），push 失败是传输体积问题——**push 收敛主会话**是状态机纪律非能力限制；⑤RAW 样片/fixtures 从此 untracked-by-design（`.gitignore` 媒体类 + 路径），新克隆不再拉几百 MB 样片。

## L071（2026-10-08）— 双 error 批：批回归假象 = 文档考古 + AX 驱动双陷阱（陈帧截图 / press 未生效）
- **触发**：LUT 页空白 queue 行的「M3-1-01 批回归」疑判（T7 正常 → 复现空白）被夜间批证伪——真因 = restore 不补种（pre-12-5 文档 base 缺 lut3d，页面零行零面板无空态）；同构建对照（base 含 lut3d 的 GFX 文档完整渲染）一步定案。
- **教训**：①**「X 批时正常」的截图证据必须核对到文档身份**——走查常用 throwaway 项目会换镜像，sidecar base = 首次 pristine 写入时代的种子快照且 restore 从不补种，不同文档不同 base，「同项目」≠「同文档」；recents 里 8 个 editor-probe-* 同前缀实例，ff_drive 前缀匹配可能错配。②**AX press 会静默不生效**（AXPress err=0 但选中态不变）——按压后必须 AXSelected 复核再下「页面空白」结论；本批两轮「仍空白」误判均源于此。③**d.shot 截图有陈帧/错窗风险**（两次 AX 已在 LUT 页而截图仍是色调页；一次抓到 ZCode 自己的前窗）——判据以 AX 树为准、截图仅旁证；坐标点击前必须确认目标 app 前置。④主线程栈 guard 族崩溃（74-165 帧即打穿 8MB）先查 Debug -Onone 巨帧放大——修复选项 = `-Xlinker -stack_size`（vmmap thread-0 reserve 机检），不是所有 stack overflow 都有自研递归可修。

## L072（2026-10-10）— M3 收官手术批：msg 定向重写执行序 + strip 集先算后砍（前提证伪）
- **触发**：M3 门清（omp 回溯 16/16 PASS）后的收官批——S2 msg 补课（3 枚英文 body 内嵌 zh 引文）+「全史瘦身手术第二次」（SPEC 预期 pack 907→400-500MB）按合并单次强推编排。
- **教训**：①**msg-filter 的 perl 模式必须 `-Mutf8`**——`-CSD` 只解码 STDIN/STDOUT，`-e` 脚本字面模式默认 byte 语义，中文模式永不命中且 filter-branch 只报 "Ref 'refs/heads/main' is unchanged"（静默零操作假成功）；改脚本前先在命令行对单条 `%B` 做 diff 验证。②**定向 msg 重写的 SHA churn = 后代全量**（本次 3 枚目标波及 57 枚后代，含用户令 `a2d3c0a`→`a435f50d`、checkpoint `81114d4`→`5f6860d`）——**msg 重写批与 blob 手术若同批，必须一次重写单次强推**（两跳重写会让 map 中间态失真）；map 按「原 SHA → 终态活 SHA」单跳入账，subject-exact 配对断言逐对互证。③**strip 手术前必须先实算 strip 集再动手**（本次红线断言先行救了一命）：SPEC 写于 L070 次日，其前提（LUTs 旧版本/归档证据历史版可剥 ~500MB）已被 L070 手术本身剥净——5995 blob 中 tip 不可达仅 41 个/2.16MB，SPEC 目标数学不可达；无断言先跑 filter-repo = 零收益全史重写 + 全账面 SHA 失效。**「预期收益」类手术步骤，收益侧也要断言（收益 < 阈值 = 停手上报）**。④pack 大头 = tip 在册证据（.work/gsd/phases 882MB + Resources/LUTs 314MB + gui-acceptance ~300MB，tip 可达 1895.4MB/1897.5MB）——**瘦身的天花板在 tip 内容政策（证据资产出仓），不在历史剥离**；L070 已把历史层榨干，再谈瘦身先立项资产出仓（LFS/外部仓/降采样归档）。⑤`--force-with-lease=<ref>:<已知远端 SHA>` 显式租约优先裸 `--force`（solo 仓也守此纪律）。
- **适用**：一切 filter-branch/filter-repo 批（map 单跳入账 + 收益侧断言 + `-Mutf8`）；「SPEC 预期数值」消费前先复核其前提是否被中间批消账。

## L073（2026-10-10）— 证据分仓手术：pack 政策 B 落地工艺（tip 资产出仓版全史剥离）
- **触发**：M3 收官后用户两令——①pack 政策 = B 证据分仓（gui-acceptance + phases/*/evidence 出主仓入独立私有 ADO 仓 `lightamer-evidence`）②M4 charter 同批（范围收窄 RAW + TIFF）。L072④ 的「tip 内容政策」路线兑现。
- **做法**：①az 建仓遇 **visibility 是项目级**——Kamasylvia 项目实为 public（匿名 `git -c credential.helper= ls-remote` 实证 origin 一直可匿名读！），单仓无法在 public 项目内转私有 → 改道**新建私有项目 Evidence** 装仓（新项目默认 private），public 项目里误建的空仓即删（零 ref 零泄漏）；②快照先行（rsync -aR 保相对路径，733 文件/2.2GB，聚合 shasum 双侧一致）→ push 私有仓（2.2GB 传输 ~85 分钟，**harness 会 reap 长跑后台任务（exit 137）——用 nohup+disown 脱管 + 轮询远端 ref 出现判完成**）→ 主仓 `git rm --cached`（保盘上文件）→ filter-repo `--invert-paths --paths-from-file`（14 条路径全史剥离，--strip-blobs-bigger-than 禁用保 LUTs 314MB 产品资产）→ 重 add remotes + `git update-ref refs/remotes/github/main <release>` 恢复跟踪（**不 fetch 旧谱系，防 pack 回胀**）→ gc --prune=now → force-push origin main。
- **教训**：①**filter-repo 会把「剥离后变空」的提交连根 prune**——untracking 提交若只含 index 删除（.gitignore 增补忘 `git add`），剥完路径即真空被 prune，且其 `reset --hard` 顺带抹掉盘上未提交的 .gitignore 改动 → **gitignore 规则必须独立成提交且在手术提交前 `git add`**；prune 掉的提交在 commit-map 里 new SHA = 全零（本批 12 枚）。②**手术前先查 release 谱系对 strip 路径的「提交级 + 树级」双零命中**（`git log release -- <paths>` + `git ls-tree -r release`）——双零 ⇒ filter-repo 后 release SHA 必不变（本批 ec389f2 实证），github 公开谱系零扰动。③**zsh 不分词变量**——`$ARGS` 传 filter-repo 会整串变单参数报 unrecognized arguments；用 `--paths-from-file` 最稳；abort 过的 run 留 `.git/filter-repo/already_ran` 触发交互确认（EOF crash），重跑前 `rm -rf .git/filter-repo`。④size-pack 971.73→**517.81MiB**（非预期带 200-400 的原因：LUTs 现行 314MB + LUTs 历史版本 + fixtures 按红线保留——剩余大对象全是产品资产，历史层已无可剥）。⑤ADO 匿名探测法：`GIT_TERMINAL_PROMPT=0 git -c credential.helper= ls-remote <https URL>`——helper 禁用后仍返回 ref = 匿名可读实锤。
- **适用**：一切「资产出仓 + 全史剥离」批（快照先行 + push 完成判据 + 双零预检 + gitignore 独立提交 + update-ref 恢复跟踪）；ADO 建仓先验项目 visibility（2027 起 ADO public 项目整体退役转私有，届时 origin 匿名可读问题自动消解——晨审可提前裁决翻转）。

## L074（2026-10-11）— golden 对照先证参考侧对位 + 直驱 commit 测试图片锚必须 temp 化（M4-3-01 双案）
- **触发**：M4-3-01 T6 精度门 target-edges 三连假失败（0.16 abs-rel ≫ 0.0036 matched 值）；T4 落地后 RasterEditFaceTests restore/seed 两法在 App 全量轮 3/5 间歇挂。
- **golden 侧**：三假说递进——①ICC 缺失致 CG/PIL 输入分歧（嵌 sRGB profile 数字逐位不变 → 证伪；全平面 byte-diff=0）；②ANE vs CPU 设备分叉（standalone .cpuOnly session 与 coremltools CPU predict **逐位一致** max-diff=0.000000 → 证伪）；③**真因 = 测试参考块错索引**——ref-f32.bin 按生成器五输入序排块，测试用 gate 列表枚举序取块 → edges 对上 horizon 的参考。**教训：golden 对照失败先证「参考侧对位」（输出-vs-参考的索引/序映射单源化），再疑产线执行路径**；`referenceOrder` 显式单源 + 探针三路对拍（session/py/ref）是最快定位手法。
- **污染侧**：直驱 `commitRasterMask` 的测试直接 load 共享 fixture → masks 目录（`.lra.masks/ai-depth-*.png`）+ sidecar（`.lra`）落在 fixture 旁 → 跨 bundle 污染 RasterEditFaceTests 的 restore 读竞态（mtime 取证实锤 = 本批测试运行时刻）。**教训：凡产线缝会「图片 URL 旁写文件」的测试，图片锚一律 temp 拷贝**（`tempFixtureCopy` 形态）；共享 fixture 目录是跨 bundle 共享态，mtime 是污染归属的第一证据。对照实验纪律：一次「嫌疑测试全 skip 仍挂」只能排除负载假说，不能排除已落盘残留——**先清场再对照**。
- **处置**：修复（tempFixtureCopy + 残留清除）后 App 711/4/0 全绿 + RasterEditFaceTests 7/0/0；三向对照存档 = `phases/m4-3-depth/M4-3-01-DECISIONS.md` §7。

## L075（2026-10-12）— test-direct.sh 直用 DerivedData 产物：改测试后必须先 build-for-testing 对应 scheme（M5-1-03 假红事故）

- **现象**：改完测试文件直接跑 `Scripts/test-direct.sh --bundle App <类>`，两轮
  结果与行号逐字节相同（5 败 → 修完 → 仍同 5 败）——跑的是**旧宿主产物里的旧
  测试代码**；补 `xcodebuild build-for-testing -scheme <对应 bundle 的 scheme>`
  后立刻转为真实结果。
- **根因**：test-direct.sh 直启 `DerivedData/.../LightamerTests<Bundle>.xctest`
  宿主（L019b 直启纪律的副作用），**自身不触发编译**；`-quiet` 下编译步骤
  缺位 = 产物陈旧不可见。首批新测试能跑到，是因为此前刚为编译验证跑过
  build-for-testing——掩盖了脚本无编译步的事实。
- **对策**：①任何测试文件改动后，先对**受影响 bundle 的 scheme**（含同文件
  重新编列的其它 bundle）跑 `build-for-testing`，再进 test-direct；②连续两轮
  输出逐字节相同 + 行号不动 = 陈旧产物签名，先怀疑产物不怀疑修复；③L041
  （tuist generate 在文件落盘后）管的是工程编列，本条管的是**产物新鲜度**，
  两道工序缺一不可。
- **适用**：一切 test-direct.sh 定向轮/收口轮；执行波与验收波同罚。

## L076（2026-10-12）— 验收遇非本批缺陷：同签名 .ips 序列 + 单类复现定性，定向亲跑补齐批内面，挂账不掩盖（M5-1-03 验收批）

- **现象**：M5-1-03 验收全套 `--all` 轮 App bundle 宿主 SIGSEGV；L055 重跑
  两轮同点复发；`--bundle App FilmPanelTests` 单类隔离 3/3 复现（崩点 =
  `testShiftSliderLiveWindowCommitsOnce`，签名 = `runFilmLeg` 的
  `FilmMethodBox.Params`/`FilmGPUPayloads` 过度释放）。执行 worker 当日两轮
  全绿——时序敏感潜伏竞态（`FilmMethodBox.runContext` 进程级静态槽跨 await
  悬挂窗，连续 coordinator 渲染互踩），非本批引入（zero Core diff 铁证 +
  PixelPipe 末触 M4 批溯源）。
- **定性路径（可复用）**：①崩溃轮日志即存副本（重跑会覆盖 `/tmp`）+
  DiagnosticReports `.ips` 同签名序列（≥2 同签名 = 非随机）+ 当日系统内存
  压力背景（swap 占用）一并取证；②归因先做**零 diff 溯源**（`git log -1
  -- <嫌疑文件>`）分清「本批引入」vs「预存暴露」；③**单类隔离复现**把
  「全套偶发」收敛为「确定性载体」；④批内验收面用定向轮补齐亲跑
  （`--bundle <b> <类>` 不受全 bundle 缺陷扰）；⑤全套单轮全绿未达时以
  三重互证替代（验收方逐位 + 批内定向逐位 + 对方日志逐份重析），**诚实
  记录替代口径，不得以对方数字充己方亲跑**。
- **处置**：挂账独立修复批（不混入被验收批——修复闸门禁照单全修的同义
  延伸：验收批不顺手修域外竞态）；registry = `M5-1-03-ACCEPTANCE.md` §7 +
  GOAL-STATE/TODO 挂账行 + .ips 证据入 `phases/*/evidence/`。
- **适用**：一切验收批遭遇疑似非本批 crash/缺陷的定性流程。

## L077（2026-10-14）— 大面探针三连环：脏页 footpring 杀进程 / defer 不跑残留吃盘 / PERF 行要 stderr（M5-2-02 探针轮）

- **背景**：M5-2-02 T4 100MP×5 预算探针（staged 8.1GB + 融合工作集 ~4GB，
  16GB 机器基线 swap 已 6.2GB）。三起连环环境事故，产线零缺陷。
- **现象与根因**：
  ①首轮 Debug 探针 fuse 段被系统杀死（3277s，无 .ips，`time` 报
  `signal: Invalid argument`）——ru_maxrss 本身 6248MB 达标（8G 门内），
  但 **8.1GB staged 未回写脏页计入 phys_footprint**（dirty file cache 是
  footprint 组成），叠加工作集把 footprint 推到 16.28GB → 系统内存压力
  杀进程。**ru_maxrss 达标 ≠ 系统层面安全**：大面 staged 写必须逐文件
  `synchronizeFile` 强制回写（脏→净，语义也更诚实——融合读的就是盘上
  字节）。
  ②被杀进程 **`defer` 清理不跑** → `$TMPDIR/la-stack-*` staged 残留
  8.1GB×2 轮两度吃满系统盘 → **ENOSPC 让 harness 无法开命令日志**
  （L049 同族新变体：不是测试夹具失败路径泄漏，是宿主被杀后清理段整个
  跳过）。手工清扫恢复；同批顺手清 3 个陈旧 DerivedData 容器（7.3GB）。
  ③PERF 计时行走 stdout（块缓冲）——进程被杀时缓冲全丢，一轮 55 分钟
  跑完零数据。**探针计时行一律 stderr**（无缓冲，逐行落盘）。
- **对策**（runbook 化）：大面探针轮 = ①staged 写后 sync ②PERF 行 stderr
  ③**轮前后清扫 `$TMPDIR` 模式目录**（la-stack-*/mertens-* 等本批命名）
  ④先查盘（`df`）再开跑，基线 swap 一并看（`sysctl vm.swapusage`）。
  CPU 数值面在直启 Release 链不可达时走 `swiftc -O` 独立脚手架
  （M2-7-3 先例；生产驱动形镜像 + 产线函数本体，来源入 evidence 存证）。
- **适用**：一切 GB 级 staged IO 的测试/基准（100MP 级 merge/export/
  panorama 族）；一切后台/夜间批的磁盘预算管理。

## L078（2026-10-13）— 键入册 xcstrings 后 defaultValue 插值走表格式：非 String 参数过 %@ 崩进程（M6-1-01 仲裁批）
- **现象**：T6 子进程三连死（「read-only arm must stay resident」×3）——指引 JSON 已出、stderr 人类行缺席，进程在 emit 中段消失。前一轮全绿、本轮唯一差异 = 两枚 stderr 键入册 xcstrings。
- **根因**：`String(localized:defaultValue:)` 在键**不在**表里时走 defaultValue 的类型安全编译插值（Int32 直插无碍）；键**入册**后运行时改走表格式字符串（%@/%d）+ 参数盒——表值用 `%1$@` 而 Int32 实参过 %@ = Foundation 格式 precondition 失败，进程即崩。**同一行代码，键入册前后行为分叉**。
- **对策**：①凡 defaultValue 插值会被入册的键，插值实参一律显式 `String(...)` 化（表值占位符恒 %@）；②「新增键必须实跑 zh-audit --check + 受影响 fixture 复跑」是硬闭环——本例正是 T9 要求的复跑抓到的（V15 教训「硬化首轮实跑对账」同族：**提取器/目录面改动后必须实跑一轮再收工**）。
- **适用**：一切 String Catalog 新键批（含插值键）；排查「键入册后进程崩/行为分叉」先查占位符类型与实参类型匹配。

## L079（2026-10-13）— flock 按 open file description 仲裁：同一把锁全进程只许一个获锁点（M6-1-01 writer 臂自锁）
- **现象**：headless writer 臂子进程起手即 typed `projectHeldByOther(pid=自己)`——外部 acquire 成功后 `store.open(role:)` 内部再 acquire 同路径锁，同进程第二 fd EWOULDBLOCK 打自己。
- **根因**：Darwin flock 仲裁对象是 open file description（非进程/非 fd）：同进程两次独立 `open()` 的第二把 EX|NB 锁照样 EWOULDBLOCK（checker o1 cc 实证的同一语义，反向咬了自己）。「锁在我手里」不等于「probe/acquire 会成功」。
- **对策**：①一把锁在一个进程内**只许一个获锁点**——项目锁的唯一获锁点 = `ProjectFileStore.open(role:)/create(role:)` 内部（held 分支即冲突臂触发器）；装配层只传 role，不做外部 acquire。②自持态判定（probe 闭包/自持豁免）不靠「试锁成功」，靠装配态显式传布尔（writer 臂 `selfHeld` 直返 writable）——「探自己的锁」结构性禁止。
- **适用**：一切 flock/SingleWriterLock 消费点（现有：mcp-endpoint 锁、`.lalb.lock`、session.lock；未来任何同件消费）；评审项 = 「锁的获锁点唯一性 + 自持豁免来源」两问。
