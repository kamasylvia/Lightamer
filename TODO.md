# TODO — Lightamer

> 本文件是 `.planning/ROADMAP.md` 的可勾选镜像，记录 13 个阶段的执行进度。
> 详细的需求映射、成功标准、风险标注见 `.planning/ROADMAP.md`。
> GSD 的 `.planning/` 下构建出的计划项同步映射到本文件对应阶段下。

**总计**：13 阶段 · 123 项 v1 需求 · 100% 已映射

## v1 Roadmap（Horizontal Layers，Fine 粒度）

### Phase 1: Foundation, App Skeleton & Capability Spikes — 11 reqs
- [ ] FOUND-01: Swift 6 + SwiftUI + Metal 3 + Core Image + ImageIO，macOS 27 最低
- [ ] FOUND-02: linear Rec2020 scene-referred + float32 RGBA pixelpipe
- [ ] FOUND-03: IOPModule protocol + Darktable v50_order 模块顺序
- [ ] FOUND-05: MTKView/MTLTexture 直渲主编辑视图，60fps@100MP
- [ ] FOUND-06: Metal compute shader 调度框架 + tiling
- [ ] FOUND-07: CIRAW 9（macOS 27）`#available` opt-in
- [ ] RAW-01: 主流相机 RAW（CR3/NEF/ARW/RAF/RW2/ORF/X3F/PEF/IIQ）
- [ ] RAW-02: Adobe DNG
- [ ] RAW-04: 非 RAW 输入（JPEG/HEIC/PNG/WebP/TIFF/PSD-flat）
- [ ] RAW-05: CIRAW 9 Neural Engine demosaic+denoise
- [ ] RAW-06: EXIF/IPTC/XMP 元数据读取
- **Spikes**：CIRAW 9 边界 / 100MP Metal 性能 / filmicrgb 可行性 / raw denoise profiling（预研）

### Phase 2: Pixelpipe Core, Color Management & History Stack — 8 reqs
- [ ] FOUND-04: pixelpipe 多分辨率 + per-module per-ROI cache
- [ ] COLOR-01: 色彩管理 pipeline（camera→working→display→output）
- [ ] COLOR-04: camera profile 支持
- [ ] HIST-01: 非破坏性编辑
- [ ] HIST-02: 完整 history stack（撤销/重做/跳转）
- [ ] HIST-03: sidecar 持久化（Lightamer 自有格式）
- [ ] HIST-04: history hash 漂移检测
- [ ] RAW-03: 32-bit float TIFF/EXR/HIF（HDR 源）
- **Spike**：100MP cache fast-path 全验证 / Darktable XMP import-tolerant parser

### Phase 3: Tone & Filmic iops — 10 reqs
- [ ] IOP-TONE-01: exposure
- [ ] IOP-TONE-02: white balance（含吸管）
- [ ] IOP-TONE-03: tonecurve（per-channel）
- [ ] IOP-TONE-04: shadow & highlight
- [ ] IOP-TONE-05: contrast
- [ ] IOP-TONE-06: levels
- [ ] IOP-TONE-07: tone equalizer
- [ ] IOP-FILM-01: filmicrgb（最难单移植，spike 全验证）
- [ ] IOP-FILM-02: sigmoid
- [ ] IOP-FILM-03: 其他 filmic 变体

### Phase 4: Geometry, Lens & Detail iops — 8 reqs
- [ ] IOP-GEO-01: crop（比例锁定+旋转微调）
- [ ] IOP-GEO-02: rotate / perspective（含自动检测）
- [ ] IOP-GEO-03: lens correction（畸变/CA/渐晕）
- [ ] IOP-GEO-04: flip / orientation
- [ ] IOP-DETAIL-01: sharpen（USM/高斯/拉普拉斯）
- [ ] IOP-DETAIL-02: local contrast（clarity）
- [ ] IOP-DETAIL-03: highpass / soften
- [ ] IOP-DETAIL-04: equalizer / detail enhancement

### Phase 5: Color & Denoise iops — 12 reqs
- [ ] IOP-COLOR-01: colorbalancergb
- [ ] IOP-COLOR-02: color calibration
- [ ] IOP-COLOR-03: vibrance / saturation
- [ ] IOP-COLOR-04: channel mixer
- [ ] IOP-COLOR-05: color zones
- [ ] IOP-COLOR-06: monochrome / B&W
- [ ] IOP-COLOR-07: velvia
- [ ] IOP-COLOR-09: color contrast / correction curves
- [ ] IOP-DENOISE-01: raw denoise（profiled，第二难移植，spike 全验证）
- [ ] IOP-DENOISE-02: NLMeans denoise
- [ ] IOP-DENOISE-03: bilateral / surface blur
- [ ] IOP-DENOISE-04: hot pixels / dark frame / chromatic

### Phase 6: Layers & Masking System — 14 reqs（最大架构阶段）
- [ ] LAYER-01: 背景层 + 多个命名调整图层
- [ ] LAYER-02: 每层独立 iop 参数
- [ ] LAYER-03: 每层蒙版
- [ ] LAYER-04: 层管理（可见性/不透明度/重命名/重排序/复制/合并/编组）
- [ ] LAYER-05: PS 风格 blend modes
- [ ] LAYER-06: 图层与全局 iop 协作
- [ ] LAYER-07: 图层状态持久化到 sidecar
- [ ] IOP-MASK-01: drawn mask（画笔/多边形/椭圆/路径/贝塞尔）
- [ ] IOP-MASK-02: parametric mask（亮度/颜色范围）
- [ ] IOP-MASK-03: raster mask
- [ ] IOP-MASK-04: mask combining（并/差/交/组）
- [ ] IOP-MASK-05: 蒙版应用于任意调整图层
- [ ] IOP-GEO-05: liquify（液化）
- [ ] IOP-GEO-06: retouch（修复/克隆）

### Phase 7: AI Modules (Native Vision Masking & Retouching) — 4 reqs
- [ ] AI-01: 主体检测蒙版（`VNGenerateForegroundInstanceMaskRequest`）
- [ ] AI-05: AI 频率分离磨皮（Vision landmarks + Core Image）
- [ ] AI-06: AI 蒙版作为图层/参数蒙版输入
- [ ] AI-07: AI 蒙版可编辑/精修

### Phase 8: HDR/Stacking & Effects iops — 10 reqs
- [ ] IOP-HDR-01: HDR merge（对齐+去鬼影）
- [ ] IOP-HDR-02: focus stacking
- [ ] IOP-HDR-03: average/median stacking
- [ ] IOP-HDR-04: 32-bit float HDR pipeline
- [ ] IOP-HDR-05: HDR/EDR 显示输出
- [ ] IOP-FX-01: vignette
- [ ] IOP-FX-02: grain
- [ ] IOP-FX-03: bloom / glow
- [ ] IOP-FX-04: dehaze
- [ ] IOP-FX-05: watermark/text overlay iop

### Phase 9: Capture One Session Management — 8 reqs
- [ ] SESS-01: 文件夹即会话
- [ ] SESS-02: Capture/Crop/Output 三级子目录
- [ ] SESS-03: sidecar 自有格式随原片存放
- [ ] SESS-04: 多 Session 切换 + 最近会话
- [ ] SESS-05: FSEvents 文件夹监视（含孤儿 sidecar 处理）
- [ ] SESS-06: 浏览模式（网格/单图/culling）
- [ ] HIST-05: 调整复制/粘贴（批量应用）
- [ ] HIST-06: before/after 对比预览

### Phase 10: yiyin Border/Watermark Panel — 8 reqs
- [ ] YIYIN-01: 白边/印框生成
- [ ] YIYIN-02: EXIF 信息叠加
- [ ] YIYIN-03: 日期文字
- [ ] YIYIN-04: Logo 水印
- [ ] YIYIN-05: 自定义字体管理
- [ ] YIYIN-06: Make/Model 品牌名归一化
- [ ] YIYIN-07: 文字模板系统
- [ ] YIYIN-08: 输出尺寸/分辨率配置

### Phase 11: Export Pipeline & Batch Queue — 8 reqs
- [ ] EXP-01: JPEG / PNG / TIFF 导出
- [ ] EXP-02: HEIF/HEIC / WebP / AVIF 导出
- [ ] EXP-03: 尺寸/DPI 配置
- [ ] EXP-04: 输出色彩空间选择（嵌入 ICC）
- [ ] EXP-05: 导出时应用 yiyin 印框/水印
- [ ] EXP-06: 批量导出队列（后台/进度/取消/重试）
- [ ] EXP-07: 多规格同导（export recipe）
- [ ] EXP-08: 导出后执行动作

### Phase 12: Metadata, Rating, Presets & LUT — 11 reqs
- [ ] META-01: 星级评分（0-5）
- [ ] META-02: 颜色标签
- [ ] META-03: 关键字/标签（层级）
- [ ] META-04: 标准 EXIF/IPTC/XMP 读写
- [ ] META-05: 过滤与排序
- [ ] META-06: 智能相册/动态集合
- [ ] PRES-01: 原生预设系统（.lightamer-preset）
- [ ] PRES-02: 预设管理器
- [ ] PRES-03: .cube LUT 导入与应用
- [ ] PRES-04: 预设批量应用
- [ ] IOP-COLOR-08: LUT (.cube) 作为 iop 模块

### Phase 13: System Integration & Distribution — 11 reqs
- [ ] SYS-01: Quick Look 扩展
- [ ] SYS-02: Spotlight 索引
- [ ] SYS-03: 触控板/鼠标手势
- [ ] SYS-04: 拖放导入
- [ ] SYS-05: 多语言跟随系统（String Catalog）
- [ ] COLOR-02: 软打样（soft proofing）
- [ ] COLOR-03: 多显示器 ICC 自动切换
- [ ] DIST-01: GitHub 开源仓库
- [ ] DIST-02: Developer ID 签名 + 公证
- [ ] DIST-03: DMG / zip 分发
- [ ] DIST-04: CI（GitHub Actions）

## v2（已记录，不在当前 roadmap）

- **TETH-01/02**: 联机拍摄
- **MAP-01/02**: 地图视图（GPS）
- **PRINT-01**: 打印模块
- **AIV2-01**: AI 追色（color match）
- **AIV2-02**: AI 评分/筛图
- **AIV2-03**: 天空分离蒙版（通用 RAW，需自定义 Core ML）
- **AIV2-04**: 人像部位分割蒙版（需自定义 face-parsing Core ML）
- **AIV2-05**: 通用语义分割蒙版（需自定义 DeepLab/Mask2Former）
- **WORK-01/02**: 跨 Session 集合/全局搜索

---

*镜像自 `.planning/ROADMAP.md`（13 phases, 123 v1 reqs）。阶段进度以 `.planning/STATE.md` 为准。*
