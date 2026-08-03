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

---

*本文件随开发进展持续更新。阶段完成后运行 `$gsd-extract-learnings` 自动提取。*
