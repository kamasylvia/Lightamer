# 在 macOS 上用 Apple Core Image RAW 9 做 RAW 解码——可行性分析

> 探索性文档，非既定方案。评估“用 Apple Core Image 最新的 **RAW 9** 解码器替换/补充 darktable 现有 RawSpeed+LibRaw 解码栈”这一想法。
> 日期：2026-08-03。

## TL;DR

**结论：作为 darktable 的 RAW 解码后端——技术上可行但价值很低、代价很大，不推荐。**
作为**可选的“高质量降噪/去马赛克”IOP 模块**（类似 RawTherapee 的那种后期增强）——**这才是 RAW 9 真正发光的地方**，值得一做，但需要 macOS 27 + Apple Silicon。

核心矛盾在于：darktable 的解码层需要的是**裸传感器数据 + 元数据**（Bayer/X-Trans mosaic、黑电平、白点、WB 系数、色彩矩阵），交给自己的 pixelpipe 后续处理；而 Core Image 的 `CIRAWFilter` 是一个**端到端处理器**——它吃 RAW 文件，吐**已经去马赛克、已降噪、已应用色彩**的 RGB 图像。两者职责重叠，强行塞进解码层会架空 darktable 的大半个流水线。

---

## 1. 两边的技术事实

### 1.1 darktable 现有解码架构（来自仓库调研）

- **入口**：`src/imageio/imageio.c:1626` `dt_imageio_open()` → 按魔数表（:274）选 loader，失败链 `rawspeed` → `libraw` → `exotic`。
- **RawSpeed**（`src/external/rawspeed` 子模块，始终编译）是主解码器：Canon CR2/CRW、Nikon NEF、Sony ARW、Fuji RAF、Olympus ORF、Panasonic RW2、Phase One IIQ 等。
- **LibRaw**（`USE_LIBRAW`，默认 ON）兜底 Canon **CR3**（HEIF 基底）与 Sigma **X3F**。
- **解码层的产出**是 mosaic 原始数据 + 元数据：
  - `img->wb_coeffs`（白平衡系数）→ `src/iop/temperature.c`
  - `img->d65_color_matrix`（相机→XYZ，由 RawSpeed 的 `colorMatrix` 填充，见 `imageio_rawspeed.cc:266`）→ `src/iop/colorin.c`
  - 黑/白点 → `src/iop/rawprepare.c`，之后 `src/iop/demosaic.c` + `demosaicing/` 做去马赛克。
- **macOS 现状**：`src/osx/osx.{h,mm}` 只做 UI/打包（菜单栏、bundle），**完全不碰 Apple 图像框架做解码**；`CMAKE_FIND_FRAMEWORK LAST`。
- 架构文档：`dev-doc/pixelpipe_architecture.md`。

关键点：**darktable 自己做去马赛克、自己持色彩管线**。解码后端被刻意设计成“只取原始数据”。

### 1.2 Apple Core Image RAW 9（来自公开资料）

`CIRAWFilter` 是 `CIFilter` 子类，自 iOS 15 / macOS 12 起为公开 API。**RAW 9 / `decoderVersion == .version9`** 是 WWDC26（session 305 “Enhance RAW image processing with Core Image”）发布的新一代解码器：

- **最大变化**：去马赛克 + 降噪**合并进一个 CoreML 模型**同时完成（此前是分步、互相损耗）。Apple 工程师 David Hayward 称之为“major improvement”。
- **质量声称**：被对比到“DxO DeepPRIME 3”级别，社区称“new noise reduction king”。大幅改善锐度、色彩、噪声。
- **格式/机型**：声称支持 **784 种相机**；演示含 Fuji **X-T5 的 X-Trans** 与传统 **Bayer**——即覆盖传统与非传统（quad/非贝尔）传感器。**不限于 Apple ProRAW**。
- **API 形态**：`CIRAWFilter(contentsOf: url)`（或 `initWithContentsOfURL:`）→ 设属性 → 取 `outputImage`（`CIImage`）。可调属性含 `baselineExposure`、`noiseReduction`、`sharpness`、`contrast`、`decoderVersion`、`boost`（局部对比）等。
- **运行**：CoreML 模型**端侧**跑在 Apple A/M 系列的 **Neural Engine** 上；比旧版本更吃资源。
- **平台**：随 **iOS 27 / iPadOS 27 / visionOS 27 / macOS 27** 交付（2026 秋）。
- 第三方已接入：Pixelmator Pro、Nitro 等，证明 API 可用于生产。

---

## 2. 核心冲突：端到端 vs. 取原始数据

| 维度 | darktable 解码层需要的 | CIRAWFilter RAW 9 给的 |
|---|---|---|
| 产出物 | **mosaic 原始数据**（Bayer/X-Trans 单通道 + 黑/白点） | **已去马赛克 + 已降噪的 RGB `CIImage`** |
| 去马赛克 | 自己做（AMAZE/RCD/LMMSE/VNG…），用户可选算法 | 它自己做（CoreML 黑盒，不可换） |
| 色彩 | 给出矩阵，`colorin` 自己管 ICC/工作空间 | 已应用色彩，不易剥离回线性场景光 |
| 白平衡 | `wb_coeffs` 给 `temperature` 模块 | 已烤进输出 |
| 高光重建 | `highlights` 模块在 mosaic 域做 | 已过去马赛克，失真已固化 |
| 可逆性 | 全程非破坏性、参数化 | 部分参数不可逆地融进 CoreML 输出 |

darktable 的整个价值主张是“**拿到原始传感器数据，用我自己的、可逆的、参数化的 pixelpipe 处理**”。把去马赛克和白平衡外包给 Core Image，等于：

- 架空 `rawprepare` / `demosaic` / `temperature`，至少 `colorin` 也要重写（输入不再是相机原色而是处理过的 RGB）；
- 高光重建、某些降噪模块失去在 mosaic 域操作的输入；
- 跨平台一致性被打破——同一 `.NEF` 在 Linux/Windows（RawSpeed）和 macOS（Core Image）下出图不同，XMP 侧车文件不可移植。

---

## 3. 三个集成方案与评估

### 方案 A：整体替换解码后端（RawSpeed/LibRaw → CIRAWFilter）
**不推荐。**
- 上述冲突全部命中，pixelpipe 上游要大改。
- 失去跨平台与可移植性，社区几乎肯定拒绝合并。
- 收益（“解码更快/更好”）方向错误——darktable 的质量瓶颈不在解码，在 pixelpipe。

### 方案 B：CIRAWFilter 作为又一个 loader（macOS-only，可选）✅ 技术可行
在 `imageio.c:274` 魔数表 + 失败链里加一个 `dt_imageio_open_coreimage`，产出 RGB 后视作“已去马赛克的 LDR/HDR 图像”进入管线（类似现在 sRAW 或 JPEG 的路径）。
- **优点**：改动局部、可选（`USE_COREIMAGE_RAW`，`if(APPLE)`）；给 macOS 用户一个“我就是要 Apple 那套发色”的入口。
- **缺点**：本质上把 RAW 当 JPEG 处理，丢掉 darktable 的 RAW 优势；用户收益存疑。
- **真正适合的场景**：只用来支持 **darktable/RawSpeed/LibRaw 都不认识的、但 macOS 原生支持的新格式**（某新机的 `.RAF`/`.CR3`/ProRAW `.dng`）——作为“能打开 > 打不开”的兜底，而非质量追求。这是它最有说服力的落地形态。

### 方案 C：把 RAW 9 的能力做成一个 IOP 模块（推荐探索）✅✅
**不在解码层，而在 pixelpipe 后期**加一个“Apple RAW 9 降噪/去马赛克增强”模块：
- 用 `CIRAWFilter` 处理同一 RAW 文件，拿到它的高质量 RGB，作为“参考/增强层”与 darktable 自己的 pixelpipe 输出融合（类似现有 AI 降噪的思路）。
- 或者更激进：提供一条“Apple 引擎”渲染路径，让用户在 darktable UI 内直接调用 RAW 9 出图，绕开自家 demosaic。
- **优点**：定位正确（把 RAW 9 当**质量增强**，不当数据源）；不破坏既有解码、不破坏跨平台；macOS 限定、可选编译，社区阻力小；正面对标 DxO DeepPRIME，是有市场的故事。
- **缺点**：需要把 Core Image 的输出色阶/色彩空间对齐回 darktable 的工作空间（色管对接是难点）；需要 macOS 27 + Apple Silicon；要处理两次解码（RawSpeed 取数据 + Core Image 出增强层）的性能与内存。
- 与本 fork 已有的 `USE_AI` / ONNX Runtime 基础设施（见 `dev-doc/AI.md`）同属一类工作，可复用部分管线。

---

## 4. 其他硬约束

1. **平台**：仅 macOS 27+（2026 秋才发布），且 RAW 9 的 CoreML 跑在 **Apple Silicon Neural Engine** 上——Intel Mac 无缘或体验差。darktable 官方仍支持较旧的 macOS 与 Intel，任何默认开启都会是回归。
2. **可移植性**：XMP 侧车里若混入 Apple 引擎的参数，在 Linux/Windows 打不开或被忽略，跨机器/跨版本一致性受损。需把这类参数标记为“macOS 专属、不写主流水线 XMP”或单独命名空间。
3. **授权与上游接受度**：darktable 是 GPL、跨平台优先的项目；任何 APPLE-only、需要闭源框架的代码，社区接受门槛高。以“可选模块 + 清晰隔离”形式提出比“动核心解码”现实得多。
4. **API 黑盒**：RAW 9 的去马赛克/降噪是 CoreML 黑盒，无法微调算法、无法对齐 darktable 现有色管；只能把它当“出图引擎”整体接受或不用。
5. **格式覆盖**：Apple 声称 784 机型的覆盖面与 RawSpeed/LibRaw 高度重叠，新增价值主要在极新机型和 ProRAW。

---

## 5. 建议

- **不要**把 Core Image RAW 9 用作 darktable 的 RAW 解码后端（方案 A）。职责冲突，得不偿失。
- 若目标是**兜底打开新格式**，走方案 B：加一个 `USE_COREIMAGE_RAW`（`if(APPLE)`）的 imageio loader，作为 RawSpeed/LibRaw 之后的 macOS 兜底，产出按已去马赛克图像入管线。改动小、风险可控。
- 若目标是**借 RAW 9 的画质**（这才是它真正强的地方），走方案 C：做一个 macOS 专属的“Apple RAW 9 增强”IOP 模块，对标 DxO DeepPRIME。先做 PoC 验证色管对齐与双解码性能，再决定是否推进。
- 在 fork 内探索时，建议先在独立分支跑 PoC（方案 C 的最小版本：单张图、命令行、对比出图质量），再谈集成。

---

## 参考来源

- Apple — WWDC26 Session 305 “Enhance RAW image processing with Core Image”：https://developer.apple.com/videos/play/wwdc2026/305/
- Apple — CIRAWFilter 文档：https://developer.apple.com/documentation/coreimage/cirawfilter
- Apple — baselineExposure 属性：https://developer.apple.com/documentation/coreimage/cirawfilter/baselineexposure
- Apple — RAW Image Options：https://developer.apple.com/documentation/coreimage/raw-image-options
- PetaPixel — “Apple's RAW Processing is Finally Evolving After a Decade…”：https://petapixel.com/2026/06/10/apples-raw-processing-is-finally-evolving-after-a-decade-and-its-a-big-deal/
- Galaxus — “Apple's new RAW development drastically reduces noise”：https://www.galaxus.at/en/page/apples-new-raw-development-drastically-reduces-noise-42974
- Stack Overflow — 用 CIRAWFilter 加载 RAW 文件：https://stackoverflow.com/questions/75551542
- darktable — 支持的文件格式手册：https://docs.darktable.org/usermanual/4.6/en/overview/supported-file-formats/
- RawSpeed 文档：https://darktable-org.github.io/rawspeed/
