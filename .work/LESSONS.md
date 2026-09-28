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
