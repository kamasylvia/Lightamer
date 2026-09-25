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

- [x] **SESS-01**: "文件夹即会话"模型——选择一个文件夹作为 Session 根，所有操作围绕该文件夹，不做中央库
- [x] **SESS-02**: Session 内自动维护 Capture（原片）/ Crop（调整副本）/ Output（导出）三级子目录结构（沿用 Capture One 习惯）
- [x] **SESS-03**: sidecar 调整文件随原片存放于 Capture 子目录，格式为 Lightamer 自有格式（不与 Darktable 二进制兼容，最大化参数调节能力）
- [x] **SESS-04**: 多 Session 切换 + 最近会话列表（最近打开、快速切换）
- [x] **SESS-05**: FSEvents 文件夹监视——外部新增/移动/删除文件时自动同步到 Session 视图（含 edge case：用户在 Finder 中移走文件后的孤儿 sidecar 处理）
- [x] **SESS-06**: Session 内浏览模式：网格视图（thumbnail grid）、单图大图、culling 对比视图（多图并排筛选）
- [x] **SESS-07**: 会话级索引 DB（可重建派生缓存，C1 `.cosessiondb` 同构）——sidecar 索引（params hash/评分/图层栈摘要）+ 缩略图索引；**真身恒为 sidecar**，DB 删除无损可重建；批量 apply = 索引单事务 + sidecar 批量写队列（懒渲染基座，PERF-07 万张 ≤5s）
  **Delivered**（Phase 9，SESS-01..07）：五步编排 + 三级目录幂等（SESS-02 = REQUIREMENTS 字面三级，Trash/Selects 不建、Crop/ v1 空目录维护——D-09-CONTEXT-3）+ `.lra` 同目录自有格式（L003/L013）+ recent 去重/上限 + FSEvents hint-only 四缺陷对策与四时点 reconcile（SESS-05 孤儿处置 = 移除带确认/忽略持久化两动作，永不硬失败）+ 浏览三态（SESS-06 culling v1 = 2 图 cap，D-09-CONTEXT-6）+ 索引 DB schema v1 冻结 25 列（Phase 12 预留列在表）+ 删库重建逐列 parity。证据：09-VALIDATION SC#1-6 三列对照 + Session 族 100+ 测试 + FINDINGS 09-3/09-4 真机走查。

### History & Non-Destructive Editing (HIST)

- [ ] **HIST-01**: 非破坏性编辑——所有调整存为参数序列（history stack），原文件永不被修改
- [ ] **HIST-02**: 完整 history stack——支持任意时刻的撤销/重做、跳转到任意历史点、压缩/展开历史步骤
- [ ] **HIST-03**: history stack 持久化到 sidecar（含模块顺序、multi_priority、multi_name、blendop 参数）
- [ ] **HIST-04**: history hash 用于漂移检测（参数变化时正确失效缓存，避免蒙版失效类损坏）
- [x] **HIST-05**: 调整同步/复制粘贴——复制一张图的全部或部分调整参数到其他图（多选批量应用）
- [x] **HIST-06**: before/after 对比预览（分屏对比、快照点对比、按住键临时查看原图）
  **Delivered**（Phase 9）：三式粘贴（overwrite/merge/partial）+ skip 集（decode 域 `< ashift 15.0`，D-09-04-D1——plan 公式修正，dt 正本 flag 制）+ 单提交 pasteSet additive 机制（⌘Z 恰 1 + 旧档兼容）+ 三段式批量管线（索引单事务 + 串行写队列 + 崩溃自愈；pristine 目标铸造自洽 doc）；before/after 三形态（split 双平面 / peek 逐字节==重放 / hold 零渲染）。注记：**跨图 undo 组（批级撤销）defer v2**（per-image commit 可退）。证据：PasteSemanticsTests 16 + SessionBatchApplierTests 12 + BeforeAfterTests 5 + FINDINGS 09-4 真会话全链。

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
- [x] **IOP-GEO-05**: liquify（液化，肖像修饰，复杂模块）——**已交付（06-06）**：base 链 18.0 warp 模块（bezier 路径 + 扭曲场 + lanczos/bicubic kernel）；扭曲场解析 ≤2.4e-7、warp parity 0.0、蒙版内容锚定经 GeometryPointMapper liquify 段
- [x] **IOP-GEO-06**: retouch（修复画笔/克隆，依赖蒙版框架）——**已交付（06-07，独立图层 kind，D-06-CONTEXT-4）**：四算法 clone/heal/blur/fill（heal 基准 median ~10ms 预算内，降级条款未触发）；stroke 形状即蒙版（NO_MASKS）；v1 圈定：视口圆形绘制（path 数据腿就绪）、blur gaussian、fill 纯色

### Layers System (LAYER) — Capture One 风格调整图层

Lightamer 采用 Capture One 风格的 adjustment layers 作为局部调整的核心组织机制。每个图层是一个独立的调整容器，携带自己的 iop 参数 + 蒙版 + 混合方式。这是与 Darktable（全局 pixelpipe + per-iop 蒙版）的根本架构差异，必须在 pixelpipe 设计时就纳入考虑（roadmapper 会规划具体架构）。

- [x] **LAYER-01**: 背景层（base layer）+ 多个可命名调整图层（adjustment layers）的图层栈模型——**已交付（06-01 层核 + 06-07 retouch kind 扩展）**：`any Layer` 双 kind 栈（adjustment + retouch）
- [x] **LAYER-02**: 每层独立 iop 参数——**已交付（06-01，层 K 增量账本 + 24 面板零改动路由 06-05）**
- [x] **LAYER-03**: 每层蒙版——**已交付（06-03 drawn + 06-04 parametric/raster + 三类 ⊗ 装配单平面；内容锚定经 GeometryPointMapper，D-06-CONTEXT-7）**
- [x] **LAYER-04**: 层管理——**已交付（06-05 UI + 06-01 data face）**；注记：合并 = mergeDown v1 交付；**编组（层文件夹）= v2**（D-06-CONTEXT-6——纯 UX 组织，蒙版组由 MaskGroup 内嵌套承载）
- [x] **LAYER-05**: 混合模式——**已交付（06-01 定案 + 06-02 引擎）**：值不重编 + dt MODERN 公式（D-06-CONTEXT-2）+ REVERSE 位 + PS dodge/burn 新值增补；dt 三证据 54/54
- [x] **LAYER-06**: 图层与全局 iop 的协作——**已交付（混合模型 (c)，06-RESEARCH §1）**：base 链全局 iop + 1+N+1 合成（层子链 + blend 三元组），walk/缓存/ROI 零改动；轨 B 恒等层逐字节实证
- [x] **LAYER-07**: 图层状态持久化到 sidecar——**已交付（06-01 sidecar v2 + 06-03/04 mask payload + 06-07 retouch strokes）**：真 RAW E2E 渲染逐字节（06-05）；history 双轨全粒度；ONE-WAY 拼写锁

### Image Operation Modules (iop) — Masking / Local (IOP-MASK)

蒙版系统服务于 LAYER（每层一个蒙版）。蒙版形态：

- [x] **IOP-MASK-01**: drawn mask——**已交付（06-03）**：五形态 GPU 光栅化（解析 ≤1e-6）+ combine 组壳 + maskVersion 缓存键
- [x] **IOP-MASK-02**: parametric mask——**已交付（06-04）**：luma+JzCzhz 单 kernel（D-06-CONTEXT-3）；注记：dt 双域 UI（Lab+RGB）defer——可逆扩展位
- [x] **IOP-MASK-03**: raster mask——**已交付（06-04）**：旁挂 16-bit PNG + StableHash 校验 + 三失败腿降级；Phase 7 AI mask 经此通道消费
- [x] **IOP-MASK-04**: mask combining operations——**已交付（06-04）**：五式逐行 + 嵌套组 + 解析面积 golden
- [x] **IOP-MASK-05**: 蒙版可应用于任意调整图层——**已交付（06-04 T5 驱动器接线）**；retouch 层除外（NO_MASKS，D-06-CONTEXT-4）

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

**v1 AI（全部基于公开 Vision/Core Image API，零自定义模型、Neural Engine 加速、本地运行无联网；例外：tap-to-segment 层 B `GenerateIterativeSegmentationRequest` 首次使用需一次性模型下载——层 A 与磨皮定位请求全程离线，D-07-CONTEXT-1）：**

- [x] **AI-01**: 主体检测蒙版（subject isolation）——基于 `VNGenerateForegroundInstanceMaskRequest`（macOS 14+，WWDC26 增强 iterative tap/scribble/lasso），自动识别人/动物/食物/物体（class-agnostic），适用于任意 demosaic 后的 RAW 图像
  **Delivered**（Phase 7）：层 A 一键离线 + 层 B tap/box 精修（D-07-CONTEXT-1 双层共存，assetStatus 三态门控）；scribble/lasso 手势 = v1 后（D-07-CONTEXT-4，种子枚举升级缝预留）；多主体 instance 勾选浮层。证据：07-1 确定性/语义门 + 07-3 MaskToolbar AI 组/SegmentEditingOverlayHost + FINDINGS 07-3 真机走查。
  - 注记（2026-09-26 登记）：**AI Background 类型入口** = subject 蒙版 + invert 组合的 UI sugar（combine inverted 已交付），对标 Nitro Photo AI Background；任意 UI 轮捎带，不立新需求。
- [x] **AI-05**: AI 磨皮——基于 `VNFaceLandmarks2D` + `VNGeneratePersonSegmentationRequest` 定位皮肤区域，Core Image 高斯模糊/高通滤波实现频率分离（frequency separation），保细节平滑、肤色自然不塑料感；无需自定义模型
  **Delivered**（Phase 7）：skinSmooth iop @ V50Order 66.5（两频高斯 + raised-cosine 阈值衰减防塑料感，D-07-CONTEXT-6；多频/bilateral 变体 = v2 位预留）+ SkinRegionLocator（hull−保护区⊗personSeg，yaw 门）+ 面板第 25 席（「定位皮肤」接线）。证据：float64 parity 6×6 <1e-5 + 恒等三元组逐字节 + PanelWiringTests 60/60；pore-level 目检 = Manual-Only 挂账（待含人脸样张）。
- [x] **AI-06**: AI 蒙版作为图层/参数蒙版输入——AI 生成的 mask 可烘焙为 raster mask 或直接作为 parametric mask 应用到任意调整图层；注记：**像素 mask 走 raster 烘焙（v1 唯一忠实通道）**，parametric 语义曲线预设（肤色 hz 曲线）留 v2（D-07-CONTEXT-3）
  **Delivered**（Phase 7，raster 口径）：AIMaskResample 双线性 + RasterMaskStore.bake 羽化增件 → `MaskSpec.raster` 写选中层 mask 槽（恰 1 stackSnapshot，⌘Z 可退）；层 B 下载例外 = D-07-CONTEXT-1（本节头注）。证据：RasterMaskRoundTrip 9/9 + LayerUIWiringTests + GUI 真机（FINDINGS 07-3：bake 落盘 + ⌘Z 恰 1 + overlay ΔR 量化）。
- [x] **AI-07**: AI 蒙版可编辑/精修——AI 生成的蒙版不是黑盒，可手动调整边缘、羽化、反向、与其他蒙版组合
  **Delivered**（Phase 7）：五条覆盖路径内容级 E2E（drawn 修补/parametric ⊓ 收紧/invert/羽化重 bake/refine 同 maskID 重生成——AIMaskEditPathsTests 6/6）+ sidecar schema 零升级（AI 参数不落盘逐字节断言）+ refine 精修 = 同 maskID 覆盖重 bake（D-07-CONTEXT-5，缓存链自动失效）。

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

- [x] **YIYIN-01**: 白边/印框生成（边距、比例、颜色、是否按原比例扩展、竖转横/横转竖布局）—— **Delivered**（08-1：BordersModule 76.0 + YiyinLayout 逐值 parity + 全腿渲染；08-3 T1 面板整合）
- [x] **YIYIN-02**: EXIF 信息叠加（拍摄参数：相机/镜头/焦距/光圈/快门/ISO/拍摄时间，可配置字段与格式）—— **Delivered**（08-2 格式化层 15 字段 + 08-3 T2 decoder walk 真实样张接通；品牌 Logo 明暗 auto 分派）
- [x] **YIYIN-03**: 日期文字（可配置字体/大小/颜色/位置/旋转）—— **Delivered**（v1 口径 = 行内语义 + 九宫格锚点，D-08-CONTEXT-2；rotation 参数位预留，完整旋转 defer v2）
- [x] **YIYIN-04**: Logo 水印（PNG/透明图，可配置位置/大小/透明度）—— **Delivered**（v1 口径 = 九宫格锚点 + 透明度滑杆，D-08-CONTEXT-2/5；内嵌 26 件品牌 PDF + 用户上传双通道）
- [x] **YIYIN-05**: 自定义字体管理（用户可上传 .ttf/.otf，仅本地存储不联网）—— **Delivered**（08-2 T5 YiyinFontStore：会话注册 + 启动重扫自愈 + typed 四错；零联网）
- [x] **YIYIN-06**: Make/Model 品牌名归一化（如 Sony ILCE→α、Nikon Z→ℤ，移植 yiyin 的 model-map）—— **Delivered**（08-2 T2 表驱动逐点；D-08-2-2 定性 model-map.ts 为死代码面——归一化走 exif-format 活跃路径，忠实 yiyin 实际行为）
- [x] **YIYIN-07**: 文字模板系统（预设模板 + 用户自定义模板字符串）—— **Delivered**（08-2 T3 引擎三门/交错/forceUse + 面板 CRUD 稳定 key 行）
- [x] **YIYIN-08**: 输出尺寸/分辨率配置（DPI、长边/短边像素、是否保留原尺寸）—— **Delivered**（08-3 T3 YiyinExportSettings 独立值类型 + 校验 + 纯 targetSize 数学 + 与水印参数正交；物理应用 resize/DPI 写入 = Phase 11 EXP-03、导出消费点 = EXP-05，D-08-CONTEXT-7 裁决）

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

### Masking Extensions (v2) — 对标 Nitro Photo 补齐（2026-09-26 登记）

对标 Gentlemen Coders Nitro Photo（macOS）蒙版面的缺口项；蒙版主体已在 v1 Phase 6/7 交付（IOP-MASK-01..05 + AI-01/05/06/07）。

- **IOP-MASK-06**: Follow Edges 边缘感知笔刷——brush 沿图像轮廓单侧跟随涂抹（edge-aware/contour-following），Metal 边缘导向实现；Nitro 独门能力，算法级新需求（可插队 v1 后期 UI 打磨轮）
- **IOP-MASK-07**: Depth 深度蒙版——读取图像内嵌深度数据（AVDepthData / ProRAW embedded matte，iPhone 人像类源）作为蒙版源；桌面 RAW 深度源稀缺，依赖数据面非算法面

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
| SESS-01 | Phase 9 — Capture One Session Management | Delivered |
| SESS-02 | Phase 9 — Capture One Session Management | Delivered |
| SESS-03 | Phase 9 — Capture One Session Management | Delivered |
| SESS-04 | Phase 9 — Capture One Session Management | Delivered |
| SESS-05 | Phase 9 — Capture One Session Management | Delivered |
| SESS-06 | Phase 9 — Capture One Session Management | Delivered |
| SESS-07 | Phase 9 — Capture One Session Management | Delivered |
| HIST-01 | Phase 2 — Pixelpipe Core, Color Mgmt & History | Pending |
| HIST-02 | Phase 2 — Pixelpipe Core, Color Mgmt & History | Pending |
| HIST-03 | Phase 2 — Pixelpipe Core, Color Mgmt & History | Pending |
| HIST-04 | Phase 2 — Pixelpipe Core, Color Mgmt & History | Pending |
| HIST-05 | Phase 9 — Capture One Session Management | Delivered |
| HIST-06 | Phase 9 — Capture One Session Management | Delivered |
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
| IOP-GEO-05 | Phase 6 — Layers & Masking System | Delivered |
| IOP-GEO-06 | Phase 6 — Layers & Masking System | Delivered |
| LAYER-01 | Phase 6 — Layers & Masking System | Delivered |
| LAYER-02 | Phase 6 — Layers & Masking System | Delivered |
| LAYER-03 | Phase 6 — Layers & Masking System | Delivered |
| LAYER-04 | Phase 6 — Layers & Masking System | Delivered |
| LAYER-05 | Phase 6 — Layers & Masking System | Delivered |
| LAYER-06 | Phase 6 — Layers & Masking System | Delivered |
| LAYER-07 | Phase 6 — Layers & Masking System | Delivered |
| IOP-MASK-01 | Phase 6 — Layers & Masking System | Delivered |
| IOP-MASK-02 | Phase 6 — Layers & Masking System | Delivered |
| IOP-MASK-03 | Phase 6 — Layers & Masking System | Delivered |
| IOP-MASK-04 | Phase 6 — Layers & Masking System | Delivered |
| IOP-MASK-05 | Phase 6 — Layers & Masking System | Delivered |
| AI-01 | Phase 7 — AI Modules (Native Vision Masking & Retouching) | Delivered |
| AI-05 | Phase 7 — AI Modules (Native Vision Masking & Retouching) | Delivered |
| AI-06 | Phase 7 — AI Modules (Native Vision Masking & Retouching) | Delivered |
| AI-07 | Phase 7 — AI Modules (Native Vision Masking & Retouching) | Delivered |
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
| YIYIN-01 | Phase 8 — yiyin Border/Watermark Panel | Delivered |
| YIYIN-02 | Phase 8 — yiyin Border/Watermark Panel | Delivered |
| YIYIN-03 | Phase 8 — yiyin Border/Watermark Panel | Delivered |
| YIYIN-04 | Phase 8 — yiyin Border/Watermark Panel | Delivered |
| YIYIN-05 | Phase 8 — yiyin Border/Watermark Panel | Delivered |
| YIYIN-06 | Phase 8 — yiyin Border/Watermark Panel | Delivered |
| YIYIN-07 | Phase 8 — yiyin Border/Watermark Panel | Delivered |
| YIYIN-08 | Phase 8 — yiyin Border/Watermark Panel | Delivered |
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
| MCP-01 | Phase 14 — MCP Server | Pending |
| MCP-02 | Phase 14 — MCP Server | Pending |
| MCP-03 | Phase 14 — MCP Server | Pending |
| MCP-04 | Phase 14 — MCP Server | Pending |
| MCP-05 | Phase 14 — MCP Server | Pending |
| MCP-06 | Phase 14 — MCP Server | Pending |
| MCP-07 | Phase 14 — MCP Server | Pending |
| MCP-08 | Phase 14 — MCP Server | Pending |
| MCP-09 | Phase 14 — MCP Server | Pending |
| MCP-10 | Phase 14 — MCP Server | Pending |

**Coverage:**
- v1 requirements: 134 total (119 + 4 AI + 1 SESS-07 + 10 MCP)
- Mapped to phases: 134 (100%)
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
| 9 — Capture One Session Management | SESS-01..07, HIST-05, HIST-06 | 9 |
| 10 — yiyin Border/Watermark Panel | YIYIN-01..08 | 8 |
| 11 — Export Pipeline & Batch Queue | EXP-01..08 | 8 |
| 12 — Metadata, Rating, Presets & LUT | META-01..06, PRES-01..04, IOP-COLOR-08 | 11 |
| 13 — System Integration & Distribution | SYS-01..05, DIST-01..04, COLOR-02, COLOR-03 | 11 |
| 14 — MCP Server (远程 AI 修图 + 自动筛选) | MCP-01..10 | 10 |
| **Total** | | **134** |

### Cross-phase placement rationale
- **IOP-GEO-05 (liquify) / IOP-GEO-06 (retouch) → Phase 6 (Layers/Masking):** both architecturally depend on the mask/distortion framework; they cannot ship before masking exists.
- **AI-01, AI-05..07 → Phase 7 (AI Modules):** the v1 AI features (subject masking + frequency-separation retouching + mask integration/editability) depend on the Phase 6 layer/mask system (AI-06 feeds masks into layers), so AI ships immediately after Layers/Masking. These are the only AI capabilities Apple's native Vision/Core Image frameworks implement without a custom Core ML model; sky/portrait-parts/semantic segmentation (AI-02/03/04 → AIV2-03/04/05) moved to v2.
- **IOP-COLOR-08 (.cube LUT) → Phase 12 (Presets/LUT):** it is the same feature as PRES-03; they ship together as the `.cube` LUT module + its preset entry point.
- **HIST-05 (copy/paste) / HIST-06 (before/after) → Phase 9 (Session):** workflow features layered on the Phase 2 history stack, best delivered alongside the session browse modes they operate within.
- **COLOR-02 (soft proof) / COLOR-03 (multi-display ICC) → Phase 13 (System):** complete the color pipeline alongside system integration (Quick Look/Spotlight), which is where multi-display behavior becomes observable.

---
*Requirements defined: 2026-08-03*
*Last updated: 2026-09-24 — Phase 7 sign-off: AI-01/05/06/07 → Delivered（AI-06 raster 口径 D-07-CONTEXT-3 / AI-01 scribble 后置 D-07-CONTEXT-4 / 层 B 下载例外 D-07-CONTEXT-1）*
*Last updated: 2026-09-26 — Phase 9 sign-off: SESS-01..07 + HIST-05/06 → Delivered（SESS-06 culling cap 2 = D-09-CONTEXT-6 / SESS-05 孤儿两动作 / HIST-05 跨图 undo defer + skip D1 / PERF-07 门 0.490s Release-SSD + PERF-06 留 Phase 15）；证据 = 09-VALIDATION + 09-DISCUSSION-LOG 终节*

### MCP Server (MCP)

- [ ] **MCP-01**: MCP 工具集：load_image / apply_params / render_preview / iop 参数 schema 元数据，远程 client 可完成「载入 → 修图 → 取回预览图」闭环
- [ ] **MCP-02**: 双入口：GUI 偏好开关（开即启动/关即停）与 CLI 无头拉起同一 server（无 GUI 进程）
- [ ] **MCP-03**: 渲染一致性：MCP 返回的预览图与本地 GUI 渲染量化一致（同参数同输出）
- [ ] **MCP-04**: 安全面：默认仅回环绑定；非回环暴露必须带鉴权 token
- [ ] **MCP-05**: 筛选读面（2026-09-26 扩充）：list_photos（会话索引查询：EXIF 轻量列/rating/flag/has_edits）+ get_thumbnails（批量缩略图取回，档 A/B 缓存直读）+ get_contact_sheet（服务端拼图返回单图）+ get_detail_crop（原尺寸 ROI 局部裁剪）
- [ ] **MCP-06**: 筛选写面（2026-09-26 扩充）：set_rating / set_flag / set_color_label / append_note——写回以 sidecar 为真，复用 Phase 9 批量管线（段1 内存变换 + 段2 索引单事务 + 段3 串行写队列）语义，GUI 缩略图 stale 再生联动可见
- [ ] **MCP-07**: culling 辅助（2026-09-26 扩充）：burst/连拍分组查询（拍摄时间+机型聚类）+ 脸部区域定位（复用 Phase 7 Vision faceLandmarks 基建）支撑细节裁剪
- [ ] **MCP-08**: 筛选写回安全边界（2026-09-26 扩充）：写回限元数据字段（rating/flag/color/note），禁止像素修改与文件删除/移动；传输安全同 MCP-04
- [ ] **MCP-09**: 筛选/修图扩充工具组（2026-09-26 登记）：list_presets / apply_preset / diff_presets（预设三件套，上游依赖 PRES-01..04）+ export_image（尺寸/质量/格式落盘，render_preview 不落盘之补位）+ set_keywords（关键词写面，上游依赖 META-04）。**研究项**（Phase 14 research 定案）：A = GUI 与无头 MCP 同会话并发 sidecar 双写对策（WAL 仅覆盖索引层；单写者锁/后开者只读/移交）；B = 多版本参数组/历史快照 MCP 语义（多版本交付需保存/切换/对比参数组工具面）；C = match_color MCP 工具位（agent 编排层：选参考/批量触发 colormatch/强度/事后 apply_params 微调；签名预留，依赖 V2 TRACK colormatch iop，与 Phase 12 .cube LUT 协同）
- [ ] **MCP-10**: GUI launcher（2026-09-26 用户裁决进 V1）：偏好存 agent CLI 启动命令模板（如 pi/omp）+ 可选任务 prompt 模板（筛图口径/修图审美方向）+「一键 AI 筛图/修图」动作——app 拉起 agent 进程挂自身 MCP server，写回由 server 完成（sidecar 真身），输出日志面板显示 agent 文字流；agent 的 provider 配置归 agent 自身体系，app 零 AI 代码；launcher 拉起路径 app 侧串行化（研究项 A）

### Performance (PERF)

- [ ] **PERF-01**: PREVIEW 全链（满 iop 集 enabled）warm median ≤16.6ms（60fps@100MP 预算）
- [ ] **PERF-02**: 100MP FULL 单帧 + N 层图层栈内存足迹 ≤3GB（TilingPlan 窗口化）
- [ ] **PERF-03**: Instruments 系统级 profile 报告落账（GPU 趟数/热点/内存），杠杆兑现记录在案
- [ ] **PERF-04**: 交互零卡顿——滑块拖动/缩放/平移 hitch（>50ms 帧间隙）= 0，MainActor 长任务清零
- [ ] **PERF-05**: RAW 解码——100MP 首渲可交互时间 ≤500ms（后台解码 + 渐进显示），CIRAW 9/8 双档计量
- [ ] **PERF-06**: 懒加载——万张级 Session 滚动 60fps，缩略图按需解码 + LRU 内存预算（Phase 9 工作基线已落账 `.work/09/perf.md`：双档缩略图管线 + LRU + 10k reload 26ms；**60fps 门本体 Phase 15 清算**）
- [x] **PERF-07**: 批量修图（懒渲染）——apply = 纯元数据写入零像素操作，万张 ≤5s（dt sqlite 事务对标；sidecar 批量写策略）；缩略图 stale 后台再生；导出排除
  **Delivered**（Phase 9）：段1+段2 万张 = **0.490s（Release/内置 SSD，09-05 签核轮 clean 构建终值）**，门 ≤5s 余量 ~10×；三轮对账 0.419→0.435→0.490 稳定；段3 sidecar drain 与 UNITEK 对照只记录不设门（L009 卷型标注）；零渲染零解码常驻断言（writer=nil 磁盘字节不变）。证据：`Perf07MassApplyTests` + `.work/09/perf.md` PERF-07 终账节。

## V2 Requirements

### Color Transfer / 追色 (TRACK)【V2；2026-09-22 用户指令维持 V2（当日曾短暂提级 Phase 7，已回撤）】

> **定位再确认（2026-09-26）**：计算核 native 不可外包——追色是统计算法（Reinhard/CDF/OT → 3D LUT），TRACK-05 确定性门与 TRACK-02 多参考统计聚合排除 agent vision 迭代路线（LumaRescue 类方法论无色彩匹配算法）。MCP+agent 作**编排皮**：选参考/批量触发/强度/事后微调（MCP-09 研究项 C `match_color` 工具位，依赖本模块 colormatch iop）；与 AIV2-01「AI 追色」的语义由编排层承载。GUI 拖入交互（TRACK-04）与 agent 编排并存不冲突。

- [ ] **TRACK-01**: 追色计算——参考图色彩分布特征提取 + 色彩变换求解（Reinhard Lab 对齐 / 直方图 CDF 匹配 / 最优传输族中选定算法），输出 3D LUT（或等效参数曲线组）
- [ ] **TRACK-02**: 多参考图支持——N 张参考的统计聚合或逐参考混合，权重可调
- [ ] **TRACK-03**: 非破坏落位——追色结果以 `colormatch` iop 模块实例落位（内嵌 LUT + tetrahedral 插值 kernel），sidecar 持久化、可继续手调、cache 语义正确
- [ ] **TRACK-04**: 交互——拖入/选择参考图 → 自动计算并预览；强度/透明度可调；before/after 对比
- [ ] **TRACK-05**: 质量门——LUT apply 的 golden parity（kernel vs float64 参考）、HDR/广色域裁剪策略明确、确定性（同输入同 LUT）
