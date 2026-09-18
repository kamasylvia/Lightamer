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
- **根因**：机械盘 + 同卷 Resilio Sync 并发同步 → 磁头寻道冲突；磁盘缓存被挤出后冷读全部打在慢卷上。
- **对策**：(1) 构建时段暂停 Resilio；(2) 长期把 Xcode 与仓库迁回内置 SSD；(3) 本机构建前先 `time xcodebuild -version`（>2s 即卷处于慢态，先查 I/O）。诊断手法：`sample <pid>` 看卡点是否在 dlopen/IO；`dd` 随机小文件测卷延迟。
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
- **来源**：Plan 02-01 checkpoint→修复全过程（2026-09-19），证据 `.work/02-01/uat-results.md` + `uat-t*.log` + 截图链。

---

*本文件随开发进展持续更新。阶段完成后运行 `$gsd-extract-learnings` 自动提取。*
