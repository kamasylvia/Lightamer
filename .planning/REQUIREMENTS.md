# Requirements: Lightamer

**Defined:** 2026-08-03
**Core Value:** 在 macOS 上用 Metal 加速提供 100MP+ 大图下零延迟的 RAW 调整体验，并让 Capture One Session 工作流与 Darktable 级调整深度在同一原生 app 中共存。

## v1 Requirements

Requirements for initial release. Each maps to roadmap phases.
v1 = 完整工作流闭环 + 蒙版系统 + HDR/堆栈 + 印框/水印 + 全量 iop（按 Fine 粒度分阶段交付，不设上限）。

### Platform & Foundation (FOUND)

- [ ] **FOUND-01**: 应用基于 Swift 6 + SwiftUI + Metal 3 + Core Image（CIRAW，macOS 27 起原生 RAW 9）+ ImageIO 构建，macOS 27 为最低版本
- [ ] **FOUND-02**: 工作色彩空间锁定为 linear Rec2020 scene-referred，pixelpipe 内部数据类型为 float32 RGBA（与 Darktable modern pipeline 对齐，便于移植算法）
- [ ] **FOUND-03**: iop 模块系统采用 Swift `protocol IOPModule { associatedtype Params: Codable, Hashable }`，模块顺序采用 Darktable `v50_order` 位置方案（rawprepare→demosaic→colorin→creative iops→colorout→gamma）
- [ ] **FOUND-04**: pixelpipe 多分辨率架构（FULL/PREVIEW/THUMBNAIL/EXPORT 至少四条管线），每模块带 per-module per-ROI 缓存（hash 命中跳过上游），参数拖动时只重算受影响模块
- [ ] **FOUND-05**: 主编辑视图用 MTKView/MTLTexture 直接渲染 Metal 输出，通过 NSViewRepresentable 与 SwiftUI 桥接，参数拖动 60fps（100MP+ 下不卡顿）
- [ ] **FOUND-06**: Metal compute shader 调度框架（build-time 编译 kernel、function-constants、PSO 缓存），支持 tile-based 处理以避免 100MP 全量入内存
- **FOUND-07**: macOS 27 起原生 CIRAW 9（Core ML demosaic+denoise on Neural Engine）通过 `#available` opt-in；未来 macOS 升级时无需改架构即可获益

### RAW Decoding & Input (RAW)

- [ ] **RAW-01**: 通过 CIRAWFilter 读取主流相机 RAW：佳能 CR3、尼康 NEF、索尼 ARW、富士 RAF、松下 RW2、奥林巴斯 ORF、适马 X3F、宾得 PEF、徕卡 DNG、Phase One IIQ 等
- [ ] **RAW-02**: 读取 Adobe DNG（含嵌入原始 DNG 与转换 DNG）
- [ ] **RAW-03**: 读取 32-bit float TIFF/EXR/HIF 作为 HDR/堆栈源文件
- [ ] **RAW-04**: 读取非 RAW 格式作为输入并支持调色：JPEG、HEIC、PNG、WebP、TIFF、PSD（扁平）
- [ ] **RAW-05**: macOS 27 起原生 CIRAW 9（Neural Engine demosaic+denoise）；macOS 27 以下场景若必须降级，需明确支持的相机子集与回退策略
- [ ] **RAW-06**: EXIF/IPTC/XMP 元数据读取（相机型号、镜头、焦距、光圈、快门、ISO、GPS、拍摄时间）

### Capture One Session Management (SESS)

- [ ] **SESS-01**: "文件夹即会话"模型——选择一个文件夹作为 Session 根，所有操作围绕该文件夹，不做中央库
- [ ] **SESS-02**: Session 内自动维护 Capture（原片）/ Crop（调整副本）/ Output（导出）三级子目录结构（沿用 Capture One 习惯）
- [ ] **SESS-03**: sidecar 调整文件随原片存放于 Capture 子目录，格式为 Lightamer 自有格式（不与 Darktable 二进制兼容，最大化参数调节能力）
- [ ] **SESS-04**: 多 Session 切换 + 最近会话列表（最近打开、快速切换）
- [ ] **SESS-05**: FSEvents 文件夹监视——外部新增/移动/删除文件时自动同步到 Session 视图（含 edge case：用户在 Finder 中移走文件后的孤儿 sidecar 处理）
- [ ] **SESS-06**: Session 内浏览模式：网格视图（thumbnail grid）、单图大图、culling 对比视图（多图并排筛选）
- [ ] **SESS-07**: 会话级索引 DB（可重建派生缓存，C1 `.cosessiondb` 同构）——sidecar 索引（params hash/评分/图层栈摘要）+ 缩略图索引；**真身恒为 sidecar**，DB 删除无损可重建；批量 apply = 索引单事务 + sidecar 批量写队列（懒渲染基座，PERF-07 万张 ≤5s）

### History & Non-Destructive Editing (HIST)

- [ ] **HIST-01**: 非破坏性编辑——所有调整存为参数序列（history stack），原文件永不被修改
- [ ] **HIST-02**: 完整 history stack——支持任意时刻的撤销/重做、跳转到任意历史点、压缩/展开历史步骤
- [ ] **HIST-03**: history stack 持久化到 sidecar（含模块顺序、multi_priority、multi_name、blendop 参数）
- [ ] **HIST-04**: history hash 用于漂移检测（参数变化时正确失效缓存，避免蒙版失效类损坏）
- [ ] **HIST-05**: 调整同步/复制粘贴——复制一张图的全部或部分调整参数到其他图（多选批量应用）
- [ ] **HIST-06**: before/after 对比预览（分屏对比、快照点对比、按住键临时查看原图）

### Image Operation Modules (iop) — Tone (IOP-TONE)

按 Darktable 全量对标，Fine 粒度 roadmap 分阶段交付。v1 起逐步覆盖以下模块：

- [x] **IOP-TONE-01**: exposure（曝光）
- [x] **IOP-TONE-02**: temperature / white balance（白平衡：色温/色调，含吸管取色）
- [x] **IOP-TONE-03**: tonecurve（色调曲线，可作用于 RGB/各通道）
- [x] **IOP-TONE-04**: shadow & highlight（阴影/高光恢复）
- [x] **IOP-TONE-05**: contrast（对比度）
- [x] **IOP-TONE-06**: levels（色阶）
- [x] **IOP-TONE-07**: tone equalizer（色调均衡器，Darktable 高价值模块）

### Image Operation Modules (iop) — Filmic / Scene-Referred (IOP-FILM)

- [x] **IOP-FILM-01**: filmicrgb（Darktable 标志性 scene-referred tone mapping，最复杂的移植之一，需早期 spike）
- [x] **IOP-FILM-02**: sigmoid（替代 tone mapping）
- [x] **IOP-FILM-03**: hatchless / other filmic variants

### Image Operation Modules (iop) — Color (IOP-COLOR)

- [x] **IOP-COLOR-01**: colorbalancergb（色彩平衡 RGB，高级色彩调整）
- [x] **IOP-COLOR-02**: color calibration（色彩校准，channel mixer 升级版）
- [x] **IOP-COLOR-03**: vibrance / saturation（自然饱和度/饱和度）
- [x] **IOP-COLOR-04**: channel mixer（通道混合器）
- [x] **IOP-COLOR-05**: color zones（色相/饱和度/亮度的分区域调整）
- [x] **IOP-COLOR-06**: monochrome / black & white（黑白转换，含色彩滤镜模拟）
- [x] **IOP-COLOR-07**: velvia（鲜艳度）
- [ ] **IOP-COLOR-08**: LUT (.cube) 作为 iop 模块——导入并应用 1D/3D .cube LUT（含 DOMAIN_MIN/MAX、tetrahedral 插值，参考 Darktable lut3d）
- [x] **IOP-COLOR-09**: color contrast / color correction curves — **已交付=colorcontrast（56.0）**；rgbcurve/rgblevels 划出 Phase 5（D-05-CONTEXT-1），Phase 6+ stretch 补齐（CurveTools 全复用机械增量）

### Image Operation Modules (iop) — Detail & Sharpen (IOP-DETAIL)

- [x] **IOP-DETAIL-01**: sharpen（锐化，含 USM 与高斯/拉普拉斯变体）
- [x] **IOP-DETAIL-02**: local contrast（局部对比度，等效 clarity）
- [x] **IOP-DETAIL-03**: highpass / soften
- [x] **IOP-DETAIL-04**: equilizer / detail enhancement

### Image Operation Modules (iop) — Denoise (IOP-DENOISE)

- [x] **IOP-DENOISE-01**: raw denoise（profiled denoise，基于相机噪声 profile，Darktable denoise (profiled) 的 Metal 移植，最复杂移植之一）
- [x] **IOP-DENOISE-02**: non-local means denoise（非局部均值）
- [x] **IOP-DENOISE-03**: bilateral / surface blur — 已交付：直连档（rad≤6）+ 稠密 5D 网格档（dt lattice 同族近似，D-05-08-T2-2）
- [x] **IOP-DENOISE-04**: hot pixels / dark frame / chromatic noise — chromatic noise 已交付（05-06 chroma 参数 + 05-07 Y0U0V0 模式）；**hotpixels/dark-frame 正式 defer**（hotpixels.c:94 IOP_CS_RAW Bayer 域 + CIRAW 无 despeckle 键——需求解释权裁决，非缺口；重启 = v2 自研 RAW 解码），cacorrect 复议维持 defer（D-05-08-T4-1，与 Phase 6 无关）

### Image Operation Modules (iop) — Geometry & Lens (IOP-GEO)

- [x] **IOP-GEO-01**: crop（裁剪，含比例锁定、旋转微调）
- [x] **IOP-GEO-02**: rotate / perspective（旋转/透视校正，含自动检测）
- [x] **IOP-GEO-03**: lens correction（镜头校正：几何畸变、横向色差、渐晕——CIRAW 不足部分用 Metal 补，含 lensfun-style 数据库或自有 profile）
- [x] **IOP-GEO-04**: flip / orientation（翻转/方向）
- [ ] **IOP-GEO-05**: liquify（液化，肖像修饰，复杂模块）
- [ ] **IOP-GEO-06**: retouch（修复画笔/克隆，依赖蒙版框架）

### Layers System (LAYER) — Capture One 风格调整图层

Lightamer 采用 Capture One 风格的 adjustment layers 作为局部调整的核心组织机制。每个图层是一个独立的调整容器，携带自己的 iop 参数 + 蒙版 + 混合方式。这是与 Darktable（全局 pixelpipe + per-iop 蒙版）的根本架构差异，必须在 pixelpipe 设计时就纳入考虑（roadmapper 会规划具体架构）。

- [ ] **LAYER-01**: 背景层（base layer）+ 多个可命名调整图层（adjustment layers）的图层栈模型
- [ ] **LAYER-02**: 每层独立 iop 参数——每个调整图层可独立设置曝光/色彩/锐化等 iop（同一 iop 在不同层可有不同参数）
- [ ] **LAYER-03**: 每层蒙版——每个调整图层携带一个蒙版（手绘 drawn / 参数 parametric / 栅格 raster，见 IOP-MASK），定义该层调整的作用范围
- [ ] **LAYER-04**: 层管理——可见性开关、不透明度、重命名、重排序、复制、删除、合并、编组
- [ ] **LAYER-05**: 混合模式——PS 风格 blend modes（normal / multiply / screen / overlay / soft light / hard light / color dodge / burn / difference / hue / saturation / color / luminosity 等）
- [ ] **LAYER-06**: 图层与全局 iop 的协作——存在既可在背景层做全局调整、又可在调整图层做局部调整的能力（架构需明确二者如何共存于同一 pixelpipe）
- [ ] **LAYER-07**: 图层状态持久化到 sidecar（层栈、每层 iop 参数、蒙版、混合模式、不透明度）

### Image Operation Modules (iop) — Masking / Local (IOP-MASK)

蒙版系统服务于 LAYER（每层一个蒙版）。蒙版形态：

- [ ] **IOP-MASK-01**: drawn mask（手绘蒙版：画笔、多边形、椭圆、路径、贝塞尔）
- [ ] **IOP-MASK-02**: parametric mask（参数蒙版：按亮度/颜色范围选择，含羽化/反转/模糊）
- [ ] **IOP-MASK-03**: raster mask（栅格蒙版：从其他蒙版烘焙而来）
- [ ] **IOP-MASK-04**: mask combining operations（多蒙版并/差/交运算、蒙版组）
- [ ] **IOP-MASK-05**: 蒙版可应用于任意调整图层（见 LAYER-03）

### Image Operation Modules (iop) — HDR & Stacking (IOP-HDR)

- [ ] **IOP-HDR-01**: HDR merge（多张不同曝光的 HDR 合并，含对齐、鬼影去除）
- [ ] **IOP-HDR-02**: focus stacking（焦点堆栈合并）
- [ ] **IOP-HDR-03**: average/median stacking（平均值/中位数堆栈降噪）
- [ ] **IOP-HDR-04**: 32-bit float HDR pipeline 支持（合并后可继续在 linear Rec2020 中调整）
- [ ] **IOP-HDR-05**: HDR/EDR 显示输出（在支持 EDR 的显示器上呈现真实高动态范围）

### Image Operation Modules (iop) — Effects (IOP-FX)

- [ ] **IOP-FX-01**: vignette（渐晕）
- [ ] **IOP-FX-02**: grain（胶片颗粒）
- [ ] **IOP-FX-03**: bloom / glow（光晕）
- [ ] **IOP-FX-04**: dehaze（除雾）
- [ ] **IOP-FX-05**: watermark/text overlay（作为 iop 层，独立于 yiyin 面板的最终出图水印）

### AI Modules (AI) — 基于 Apple Vision / Core Image 原生框架（v1 仅含原生可实现项）

**划分原则**：v1 仅纳入 Apple 原生框架（Vision / Core Image / Core ML 系统提供）可直接实现、无需自定义训练模型的 AI 能力。需自定义 Core ML 模型的进 v2。研究阶段已确认能力边界（见 `.planning/research/SUMMARY.md` 与 STACK.md）。

**v1 AI（全部基于公开 Vision/Core Image API，零自定义模型、Neural Engine 加速、本地运行无联网）：**

- [ ] **AI-01**: 主体检测蒙版（subject isolation）——基于 `VNGenerateForegroundInstanceMaskRequest`（macOS 14+，WWDC26 增强 iterative tap/scribble/lasso），自动识别人/动物/食物/物体（class-agnostic），适用于任意 demosaic 后的 RAW 图像
- [ ] **AI-05**: AI 磨皮——基于 `VNFaceLandmarks2D` + `VNGeneratePersonSegmentationRequest` 定位皮肤区域，Core Image 高斯模糊/高通滤波实现频率分离（frequency separation），保细节平滑、肤色自然不塑料感；无需自定义模型
- [ ] **AI-06**: AI 蒙版作为图层/参数蒙版输入——AI 生成的 mask 可烘焙为 raster mask 或直接作为 parametric mask 应用到任意调整图层
- [ ] **AI-07**: AI 蒙版可编辑/精修——AI 生成的蒙版不是黑盒，可手动调整边缘、羽化、反向、与其他蒙版组合

**以下 AI 能力因 Apple 无公开原生 API（需自定义 Core ML 模型）→ 移至 v2（见 v2 章节 AIV2）：**
- 天空分离（通用 RAW）——`CIRAWFilter.semanticSegmentationSkyMatteImage` 仅能读取 iPhone ProRAW 嵌入的 matte，不能从任意 DSLR RAW 计算
- 人像部位分割（皮肤/头发/嘴唇/眼睛等独立 mask）——`AVSemanticSegmentationMatte` 仅 iPhone 捕获时数据；DSLR RAW 需自定义 face-parsing Core ML 模型
- 通用语义分割（植被/建筑/水体/雪地等）——无公开多类分割 API，需自定义 DeepLab/Mask2Former 模型

### Color Management (COLOR)

- [ ] **COLOR-01**: 色彩管理 pipeline——camera RGB → linear Rec2020 working → display (Display P3 / ICC profile) → output (sRGB / Display P3 / Adobe RGB / ProPhoto / Rec2020)
- [ ] **COLOR-02**: 软打样（soft proofing）——模拟打印机/输出设备的色彩空间，含 out-of-gamut 警告
- [ ] **COLOR-03**: 多显示器 ICC profile 自动切换
- [ ] **COLOR-04**: camera profile 支持（CIRAW 内置 profile；未来扩展 DCP-style 自定义 profile）

### Border / Watermark (yiyin panel) (YIYIN)

将 yiyin（壹印）作为 Lightamer 内置一等公民面板，功能对齐 yiyin 现有能力：

- [ ] **YIYIN-01**: 白边/印框生成（边距、比例、颜色、是否按原比例扩展、竖转横/横转竖布局）
- [ ] **YIYIN-02**: EXIF 信息叠加（拍摄参数：相机/镜头/焦距/光圈/快门/ISO/拍摄时间，可配置字段与格式）
- [ ] **YIYIN-03**: 日期文字（可配置字体/大小/颜色/位置/旋转）
- [ ] **YIYIN-04**: Logo 水印（PNG/透明图，可配置位置/大小/透明度）
- [ ] **YIYIN-05**: 自定义字体管理（用户可上传 .ttf/.otf，仅本地存储不联网）
- [ ] **YIYIN-06**: Make/Model 品牌名归一化（如 Sony ILCE→α、Nikon Z→ℤ，移植 yiyin 的 model-map）
- [ ] **YIYIN-07**: 文字模板系统（预设模板 + 用户自定义模板字符串）
- [ ] **YIYIN-08**: 输出尺寸/分辨率配置（DPI、长边/短边像素、是否保留原尺寸）

### Metadata & Organization (META)

- [ ] **META-01**: 星级评分（0-5 星）
- [ ] **META-02**: 颜色标签（C1 风格彩色标签）
- [ ] **META-03**: 关键字/标签（层级关键字、批量编辑）
- [ ] **META-04**: 标准 EXIF/IPTC/XMP 读写（与其他工具兼容，评级/标签/关键字随 sidecar 同步）
- [ ] **META-05**: 按评分/标签/关键字/相机/镜头/日期/ISO/焦距等过滤与排序
- [ ] **META-06**: 智能相册/动态集合（基于规则的虚拟分组，不复制文件）

### Presets & Styles (PRES)

- [ ] **PRES-01**: 原生预设系统——保存完整调整堆栈为 Lightamer 预设（.lightamer-preset，JSON/Codable）
- [ ] **PRES-02**: 预设管理器（创建/编辑/删除/导入/导出/分类）
- [ ] **PRES-03**: .cube LUT 导入与应用（作为 IOP-COLOR-08 模块的能力，含 1D/3D、DOMAIN_MIN/MAX、tetrahedral 插值）
- [ ] **PRES-04**: 预设可应用于单图或批量多图

### Export (EXP)

- [ ] **EXP-01**: 导出格式：JPEG（含质量参数）、PNG（含 8/16-bit）、TIFF（含 8/16/32-bit float、压缩选项）
- [ ] **EXP-02**: 导出格式：HEIF/HEIC（含质量、10-bit）、WebP（依赖 libwebp SPM，含质量/有损无损）、AVIF（macOS 27 起原生，否则依赖 libavif SPM，含 8/10/12-bit）
- [ ] **EXP-03**: 导出尺寸/分辨率/DPI 配置、长边/短边/百分比/原尺寸
- [ ] **EXP-04**: 输出色彩空间选择（sRGB / Display P3 / Adobe RGB / ProPhoto / Rec2020，含嵌入 ICC profile）
- [ ] **EXP-05**: 导出时应用 yiyin 印框/水印（导出流水线的最后一步，与编辑器内 yiyin 面板共享配置）
- [ ] **EXP-06**: 批量导出队列——后台执行多图导出，含进度、可取消、失败重试
- [ ] **EXP-07**: 多规格同导（同一原片一次性输出多种尺寸/格式/水印组合的导出配方 export recipe）
- [ ] **EXP-08**: 导出后执行动作（如运行 shell 脚本、打开文件夹）

### System Integration (SYS)

- [ ] **SYS-01**: Quick Look 扩展——Finder 中按空格预览 RAW 文件（含调整后预览，不仅是原片缩略图）
- [ ] **SYS-02**: Spotlight 索引——通过 RAW 调整后状态检索（评级/标签/关键字/EXIF 元数据可被 Spotlight 检索）
- [ ] **SYS-03**: 触控板/鼠标手势（双指缩放、捏拉、旋转、双指拖动平移）
- [ ] **SYS-04**: 拖放导入（从 Finder 拖入 Session 或直接拖入编辑）
- [ ] **SYS-05**: 多语言跟随系统（String Catalog，至少 zh/en，结构预留扩展）

### Distribution & Project (DIST)

- [ ] **DIST-01**: GitHub 开源仓库（MIT 或类似宽松许可证）
- [ ] **DIST-02**: Developer ID 签名 + 公证（非 Mac App Store、非沙盒）
- [ ] **DIST-03**: DMG / zip 分发
- [ ] **DIST-04**: CI（GitHub Actions：构建、测试、签名、公证、发布）

## v2 Requirements

Deferred to future release. Tracked but not in current roadmap.

### Tethering

- **TETH-01**: 相机联机拍摄（通过 PTP/USB 实时捕获，自动入库到 Session Capture 子目录）
- **TETH-02**: 联机参数控制（光圈/快门/ISO/白平衡远程调节）

### Map / GPS

- **MAP-01**: 地图视图（MapKit，按 GPS EXIF 在地图标点）
- **MAP-02**: 点击地图标点查看该位置的图集

### Printing

- **PRINT-01**: 打印模块（色彩管理打印、布局、contact sheet）

### Advanced AI (v2) — 需自定义 Core ML 模型或非原生 API

这些能力 Apple 原生框架（Vision/Core Image）无公开 API 直接实现，需自定义训练 Core ML 模型或外部依赖，故留 v2。

- **AIV2-01**: AI 追色（color match）——分析参考图/参考风格，自动调整当前图色彩向其靠拢；Apple 无 `CIColorTransfer`，需实现经典 Reinhard/直方图匹配或自定义 Core ML 色彩映射模型
- **AIV2-02**: AI 评分/筛图（culling assist）——基于构图/曝光/对焦/清晰度自动给候选图打分排序；Apple 无质量评分 API，需自定义（Laplacian 方差模糊度量 + 直方图分析 + 可能的审美评分 Core ML 模型）
- **AIV2-03**: 天空分离蒙版（通用 RAW）——从任意 DSLR/无反 RAW 计算天空 mask（非仅读 iPhone ProRAW 嵌入 matte）；需自定义 Core ML 天空分割模型
- **AIV2-04**: 人像部位分割蒙版——皮肤/头发/嘴唇/眼睛/眉毛/牙齿等独立 mask，用于任意 RAW（非仅 iPhone 捕获时数据）；需自定义 face-parsing Core ML 模型（如 BiSeNet 风格）
- **AIV2-05**: 通用语义分割蒙版——植被/建筑/水体/雪地/地面等多类语义分割（Lightroom Adaptive Presets 风格）；需自定义 DeepLab/Mask2Former Core ML 模型

### Editor Workflow Extensions

- **WORK-01**: 标签/收藏夹集合（虚拟文件夹跨 Session）
- **WORK-02**: 全局搜索（跨 Session 检索，需索引）

## Out of Scope

Explicitly excluded. Documented to prevent scope creep.

| Feature | Reason |
|---------|--------|
| Lightroom catalog 模式（中央库） | 与 Capture One Session 理念冲突；个人工作流偏好文件夹即会话 |
| Mac App Store 分发 / 沙盒 | 沙盒限制文件访问与 Session 模式冲突；开源免费路线选独立签名公证 |
| iOS / iPadOS 版本 | 项目定位 macOS 专属；依赖 Metal / Core Image / SwiftUI 桌面版 |
| Windows / Linux 跨平台 | 依赖 Metal / Core Image / SwiftUI；跨平台会牺牲原生体验与性能 |
| 账号体系 / 云同步 / 订阅 | 开源免费；个人自用优先；无云依赖 |
| 与 Darktable sidecar 二进制兼容 | 研究确认 Darktable 用 base64 二进制 blob + modversion，跨实现兼容做不到；Lightamer 用自有格式最大化参数能力 |
| 与 Darktable/Lightroom 预设互通 | 与 sidecar 决策一致；不互通，自有预设格式 + 标准 .cube LUT 即可 |
| 移动端配套 app | macOS 专属定位；移动端不在范围 |
| AI 追色/AI 评分/AI 天空/人像部位/通用分割（v1） | v1 仅做 Apple 原生 API 可实现的 AI（主体检测 + 频率分离磨皮）；天空分离/人像部位/通用语义分割/追色/评分需自定义 Core ML 模型，留 v2 |

## Traceability

Which phases cover which requirements. Updated during roadmap creation (2026-08-03).

| Requirement | Phase | Status |
|-------------|-------|--------|
| FOUND-01 | Phase 1 — Foundation, App Skeleton & Spikes | Pending |
| FOUND-02 | Phase 1 — Foundation, App Skeleton & Spikes | Pending |
| FOUND-03 | Phase 1 — Foundation, App Skeleton & Spikes | Pending |
| FOUND-04 | Phase 2 — Pixelpipe Core, Color Mgmt & History | Pending |
| FOUND-05 | Phase 1 — Foundation, App Skeleton & Spikes | Pending |
| FOUND-06 | Phase 1 — Foundation, App Skeleton & Spikes | Pending |
| FOUND-07 | Phase 1 — Foundation, App Skeleton & Spikes | Pending |
| RAW-01 | Phase 1 — Foundation, App Skeleton & Spikes | Pending |
| RAW-02 | Phase 1 — Foundation, App Skeleton & Spikes | Pending |
| RAW-03 | Phase 2 — Pixelpipe Core, Color Mgmt & History | Pending |
| RAW-04 | Phase 1 — Foundation, App Skeleton & Spikes | Pending |
| RAW-05 | Phase 1 — Foundation, App Skeleton & Spikes | Pending |
| RAW-06 | Phase 1 — Foundation, App Skeleton & Spikes | Pending |
| SESS-01 | Phase 9 — Capture One Session Management | Pending |
| SESS-02 | Phase 9 — Capture One Session Management | Pending |
| SESS-03 | Phase 9 — Capture One Session Management | Pending |
| SESS-04 | Phase 9 — Capture One Session Management | Pending |
| SESS-05 | Phase 9 — Capture One Session Management | Pending |
| SESS-06 | Phase 9 — Capture One Session Management | Pending |
| HIST-01 | Phase 2 — Pixelpipe Core, Color Mgmt & History | Pending |
| HIST-02 | Phase 2 — Pixelpipe Core, Color Mgmt & History | Pending |
| HIST-03 | Phase 2 — Pixelpipe Core, Color Mgmt & History | Pending |
| HIST-04 | Phase 2 — Pixelpipe Core, Color Mgmt & History | Pending |
| HIST-05 | Phase 9 — Capture One Session Management | Pending |
| HIST-06 | Phase 9 — Capture One Session Management | Pending |
| IOP-TONE-01 | Phase 3 — Tone & Filmic iops | Delivered |
| IOP-TONE-02 | Phase 3 — Tone & Filmic iops | Delivered |
| IOP-TONE-03 | Phase 3 — Tone & Filmic iops | Delivered |
| IOP-TONE-04 | Phase 3 — Tone & Filmic iops | Delivered |
| IOP-TONE-05 | Phase 3 — Tone & Filmic iops | Delivered |
| IOP-TONE-06 | Phase 3 — Tone & Filmic iops | Delivered |
| IOP-TONE-07 | Phase 3 — Tone & Filmic iops | Delivered |
| IOP-FILM-01 | Phase 3 — Tone & Filmic iops | Delivered |
| IOP-FILM-02 | Phase 3 — Tone & Filmic iops | Delivered |
| IOP-FILM-03 | Phase 3 — Tone & Filmic iops | Delivered |
| IOP-COLOR-01 | Phase 5 — Color & Denoise iops | Delivered |
| IOP-COLOR-02 | Phase 5 — Color & Denoise iops | Delivered |
| IOP-COLOR-03 | Phase 5 — Color & Denoise iops | Delivered |
| IOP-COLOR-04 | Phase 5 — Color & Denoise iops | Delivered |
| IOP-COLOR-05 | Phase 5 — Color & Denoise iops | Delivered |
| IOP-COLOR-06 | Phase 5 — Color & Denoise iops | Delivered |
| IOP-COLOR-07 | Phase 5 — Color & Denoise iops | Delivered |
| IOP-COLOR-08 | Phase 12 — Metadata, Rating, Presets & LUT | Pending |
| IOP-COLOR-09 | Phase 5 — Color & Denoise iops | Delivered |
| IOP-DETAIL-01 | Phase 4 — Geometry, Lens & Detail iops | Delivered |
| IOP-DETAIL-02 | Phase 4 — Geometry, Lens & Detail iops | Delivered |
| IOP-DETAIL-03 | Phase 4 — Geometry, Lens & Detail iops | Delivered |
| IOP-DETAIL-04 | Phase 4 — Geometry, Lens & Detail iops | Delivered |
| IOP-DENOISE-01 | Phase 5 — Color & Denoise iops | Delivered |
| IOP-DENOISE-02 | Phase 5 — Color & Denoise iops | Delivered |
| IOP-DENOISE-03 | Phase 5 — Color & Denoise iops | Delivered |
| IOP-DENOISE-04 | Phase 5 — Color & Denoise iops | Resolved（chromatic 交付；hotpixels/dark-frame defer） |
| IOP-GEO-01 | Phase 4 — Geometry, Lens & Detail iops | Delivered |
| IOP-GEO-02 | Phase 4 — Geometry, Lens & Detail iops | Delivered |
| IOP-GEO-03 | Phase 4 — Geometry, Lens & Detail iops | Delivered |
| IOP-GEO-04 | Phase 4 — Geometry, Lens & Detail iops | Delivered |
| IOP-GEO-05 | Phase 6 — Layers & Masking System | Pending |
| IOP-GEO-06 | Phase 6 — Layers & Masking System | Pending |
| LAYER-01 | Phase 6 — Layers & Masking System | Pending |
| LAYER-02 | Phase 6 — Layers & Masking System | Pending |
| LAYER-03 | Phase 6 — Layers & Masking System | Pending |
| LAYER-04 | Phase 6 — Layers & Masking System | Pending |
| LAYER-05 | Phase 6 — Layers & Masking System | Pending |
| LAYER-06 | Phase 6 — Layers & Masking System | Pending |
| LAYER-07 | Phase 6 — Layers & Masking System | Pending |
| IOP-MASK-01 | Phase 6 — Layers & Masking System | Pending |
| IOP-MASK-02 | Phase 6 — Layers & Masking System | Pending |
| IOP-MASK-03 | Phase 6 — Layers & Masking System | Pending |
| IOP-MASK-04 | Phase 6 — Layers & Masking System | Pending |
| IOP-MASK-05 | Phase 6 — Layers & Masking System | Pending |
| AI-01 | Phase 7 — AI Modules (Native Vision Masking & Retouching) | Pending |
| AI-05 | Phase 7 — AI Modules (Native Vision Masking & Retouching) | Pending |
| AI-06 | Phase 7 — AI Modules (Native Vision Masking & Retouching) | Pending |
| AI-07 | Phase 7 — AI Modules (Native Vision Masking & Retouching) | Pending |
| IOP-HDR-01 | Phase 8 — HDR/Stacking & Effects iops | Pending |
| IOP-HDR-02 | Phase 8 — HDR/Stacking & Effects iops | Pending |
| IOP-HDR-03 | Phase 8 — HDR/Stacking & Effects iops | Pending |
| IOP-HDR-04 | Phase 8 — HDR/Stacking & Effects iops | Pending |
| IOP-HDR-05 | Phase 8 — HDR/Stacking & Effects iops | Pending |
| IOP-FX-01 | Phase 8 — HDR/Stacking & Effects iops | Pending |
| IOP-FX-02 | Phase 8 — HDR/Stacking & Effects iops | Pending |
| IOP-FX-03 | Phase 8 — HDR/Stacking & Effects iops | Pending |
| IOP-FX-04 | Phase 8 — HDR/Stacking & Effects iops | Pending |
| IOP-FX-05 | Phase 8 — HDR/Stacking & Effects iops | Pending |
| COLOR-01 | Phase 2 — Pixelpipe Core, Color Mgmt & History | Pending |
| COLOR-02 | Phase 13 — System Integration & Distribution | Pending |
| COLOR-03 | Phase 13 — System Integration & Distribution | Pending |
| COLOR-04 | Phase 2 — Pixelpipe Core, Color Mgmt & History | Pending |
| YIYIN-01 | Phase 10 — yiyin Border/Watermark Panel | Pending |
| YIYIN-02 | Phase 10 — yiyin Border/Watermark Panel | Pending |
| YIYIN-03 | Phase 10 — yiyin Border/Watermark Panel | Pending |
| YIYIN-04 | Phase 10 — yiyin Border/Watermark Panel | Pending |
| YIYIN-05 | Phase 10 — yiyin Border/Watermark Panel | Pending |
| YIYIN-06 | Phase 10 — yiyin Border/Watermark Panel | Pending |
| YIYIN-07 | Phase 10 — yiyin Border/Watermark Panel | Pending |
| YIYIN-08 | Phase 10 — yiyin Border/Watermark Panel | Pending |
| META-01 | Phase 12 — Metadata, Rating, Presets & LUT | Pending |
| META-02 | Phase 12 — Metadata, Rating, Presets & LUT | Pending |
| META-03 | Phase 12 — Metadata, Rating, Presets & LUT | Pending |
| META-04 | Phase 12 — Metadata, Rating, Presets & LUT | Pending |
| META-05 | Phase 12 — Metadata, Rating, Presets & LUT | Pending |
| META-06 | Phase 12 — Metadata, Rating, Presets & LUT | Pending |
| PRES-01 | Phase 12 — Metadata, Rating, Presets & LUT | Pending |
| PRES-02 | Phase 12 — Metadata, Rating, Presets & LUT | Pending |
| PRES-03 | Phase 12 — Metadata, Rating, Presets & LUT | Pending |
| PRES-04 | Phase 12 — Metadata, Rating, Presets & LUT | Pending |
| EXP-01 | Phase 11 — Export Pipeline & Batch Queue | Pending |
| EXP-02 | Phase 11 — Export Pipeline & Batch Queue | Pending |
| EXP-03 | Phase 11 — Export Pipeline & Batch Queue | Pending |
| EXP-04 | Phase 11 — Export Pipeline & Batch Queue | Pending |
| EXP-05 | Phase 11 — Export Pipeline & Batch Queue | Pending |
| EXP-06 | Phase 11 — Export Pipeline & Batch Queue | Pending |
| EXP-07 | Phase 11 — Export Pipeline & Batch Queue | Pending |
| EXP-08 | Phase 11 — Export Pipeline & Batch Queue | Pending |
| SYS-01 | Phase 13 — System Integration & Distribution | Pending |
| SYS-02 | Phase 13 — System Integration & Distribution | Pending |
| SYS-03 | Phase 13 — System Integration & Distribution | Pending |
| SYS-04 | Phase 13 — System Integration & Distribution | Pending |
| SYS-05 | Phase 13 — System Integration & Distribution | Pending |
| DIST-01 | Phase 13 — System Integration & Distribution | Pending |
| DIST-02 | Phase 13 — System Integration & Distribution | Pending |
| DIST-03 | Phase 13 — System Integration & Distribution | Pending |
| DIST-04 | Phase 13 — System Integration & Distribution | Pending |

**Coverage:**
- v1 requirements: 123 total (119 + 4 AI)
- Mapped to phases: 123 (100%)
- Unmapped: 0 ✓

### Per-phase coverage counts

| Phase | Requirements | Count |
|-------|--------------|-------|
| 1 — Foundation, App Skeleton & Capability Spikes | FOUND-01..03, FOUND-05..07, RAW-01, RAW-02, RAW-04..06 | 11 |
| 2 — Pixelpipe Core, Color Management & History Stack | FOUND-04, RAW-03, COLOR-01, COLOR-04, HIST-01..04 | 8 |
| 3 — Tone & Filmic iops | IOP-TONE-01..07, IOP-FILM-01..03 | 10 |
| 4 — Geometry, Lens & Detail iops | IOP-GEO-01..04, IOP-DETAIL-01..04 | 8 |
| 5 — Color & Denoise iops | IOP-COLOR-01..07, IOP-COLOR-09, IOP-DENOISE-01..04 | 12 |
| 6 — Layers & Masking System | LAYER-01..07, IOP-MASK-01..05, IOP-GEO-05, IOP-GEO-06 | 14 |
| 7 — AI Modules (Native Vision Masking & Retouching) | AI-01, AI-05..07 | 4 |
| 8 — HDR/Stacking & Effects iops | IOP-HDR-01..05, IOP-FX-01..05 | 10 |
| 9 — Capture One Session Management | SESS-01..06, HIST-05, HIST-06 | 8 |
| 10 — yiyin Border/Watermark Panel | YIYIN-01..08 | 8 |
| 11 — Export Pipeline & Batch Queue | EXP-01..08 | 8 |
| 12 — Metadata, Rating, Presets & LUT | META-01..06, PRES-01..04, IOP-COLOR-08 | 11 |
| 13 — System Integration & Distribution | SYS-01..05, DIST-01..04, COLOR-02, COLOR-03 | 11 |
| **Total** | | **123** |

### Cross-phase placement rationale
- **IOP-GEO-05 (liquify) / IOP-GEO-06 (retouch) → Phase 6 (Layers/Masking):** both architecturally depend on the mask/distortion framework; they cannot ship before masking exists.
- **AI-01, AI-05..07 → Phase 7 (AI Modules):** the v1 AI features (subject masking + frequency-separation retouching + mask integration/editability) depend on the Phase 6 layer/mask system (AI-06 feeds masks into layers), so AI ships immediately after Layers/Masking. These are the only AI capabilities Apple's native Vision/Core Image frameworks implement without a custom Core ML model; sky/portrait-parts/semantic segmentation (AI-02/03/04 → AIV2-03/04/05) moved to v2.
- **IOP-COLOR-08 (.cube LUT) → Phase 12 (Presets/LUT):** it is the same feature as PRES-03; they ship together as the `.cube` LUT module + its preset entry point.
- **HIST-05 (copy/paste) / HIST-06 (before/after) → Phase 9 (Session):** workflow features layered on the Phase 2 history stack, best delivered alongside the session browse modes they operate within.
- **COLOR-02 (soft proof) / COLOR-03 (multi-display ICC) → Phase 13 (System):** complete the color pipeline alongside system integration (Quick Look/Spotlight), which is where multi-display behavior becomes observable.

---
*Requirements defined: 2026-08-03*
*Last updated: 2026-08-03 — Phase 7 rescoped to native-only AI (4 reqs: AI-01, AI-05, AI-06, AI-07); AI-02/03/04 moved to v2 as AIV2-03/04/05*

### MCP Server (MCP)

- [ ] **MCP-01**: MCP 工具集：load_image / apply_params / render_preview / iop 参数 schema 元数据，远程 client 可完成「载入 → 修图 → 取回预览图」闭环
- [ ] **MCP-02**: 双入口：GUI 偏好开关（开即启动/关即停）与 CLI 无头拉起同一 server（无 GUI 进程）
- [ ] **MCP-03**: 渲染一致性：MCP 返回的预览图与本地 GUI 渲染量化一致（同参数同输出）
- [ ] **MCP-04**: 安全面：默认仅回环绑定；非回环暴露必须带鉴权 token

### Performance (PERF)

- [ ] **PERF-01**: PREVIEW 全链（满 iop 集 enabled）warm median ≤16.6ms（60fps@100MP 预算）
- [ ] **PERF-02**: 100MP FULL 单帧 + N 层图层栈内存足迹 ≤3GB（TilingPlan 窗口化）
- [ ] **PERF-03**: Instruments 系统级 profile 报告落账（GPU 趟数/热点/内存），杠杆兑现记录在案
- [ ] **PERF-04**: 交互零卡顿——滑块拖动/缩放/平移 hitch（>50ms 帧间隙）= 0，MainActor 长任务清零
- [ ] **PERF-05**: RAW 解码——100MP 首渲可交互时间 ≤500ms（后台解码 + 渐进显示），CIRAW 9/8 双档计量
- [ ] **PERF-06**: 懒加载——万张级 Session 滚动 60fps，缩略图按需解码 + LRU 内存预算
- [ ] **PERF-07**: 批量修图（懒渲染）——apply = 纯元数据写入零像素操作，万张 ≤5s（dt sqlite 事务对标；sidecar 批量写策略）；缩略图 stale 后台再生；导出排除

## V2 Requirements

### Color Transfer / 追色 (TRACK)【V2；2026-09-22 用户指令维持 V2（当日曾短暂提级 Phase 7，已回撤）】

- [ ] **TRACK-01**: 追色计算——参考图色彩分布特征提取 + 色彩变换求解（Reinhard Lab 对齐 / 直方图 CDF 匹配 / 最优传输族中选定算法），输出 3D LUT（或等效参数曲线组）
- [ ] **TRACK-02**: 多参考图支持——N 张参考的统计聚合或逐参考混合，权重可调
- [ ] **TRACK-03**: 非破坏落位——追色结果以 `colormatch` iop 模块实例落位（内嵌 LUT + tetrahedral 插值 kernel），sidecar 持久化、可继续手调、cache 语义正确
- [ ] **TRACK-04**: 交互——拖入/选择参考图 → 自动计算并预览；强度/透明度可调；before/after 对比
- [ ] **TRACK-05**: 质量门——LUT apply 的 golden parity（kernel vs float64 参考）、HDR/广色域裁剪策略明确、确定性（同输入同 LUT）
