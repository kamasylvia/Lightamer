# Feature Scope Tables

> 证据口径：行数 = `wc -l` 单文件主源码；不含测试、数据、kernel、头文件。darktable 侧取
> `/Volumes/UNITEK/Documents/Development/darktable` 工作树 HEAD `16ca3f76d6`（2026-11-25），
> 上游参照 = 本地 ref `github/master` = `679d594f5d`（2026-11-22）。
> **重要更正**：该目录不是纯净官方 darktable，而是 darktamer 分叉工作树（`git describe` =
> `darktamer-0.0.4-109-g16ca3f76d6`，含 fork 独有 76 commits）。Q1 的「官方基线」按
> `github/master` ref 计；Q2 的 fork 差异按 `github/master..HEAD` 计。

## Table 1 — darktable iop 全量（103 个模块源 = 100 `.c` + 3 `.cc`，149,074 行）

`.cc` 模块 = `lens.cc`（5,209）、`bilateral.cc`（629）、`tonemap.cc`（233）。另有 17 个 helper `.c`
（`demosaicing/`、`hlreconstruct/`，10,106 行），不属于独立模块；全树 159,180 行。

`计算面外部依赖` 只列 `.c/.cc` 内 `#include` 证实的非 GTK/GLib 库；注释/字符串命中不计。
OpenCL 为所有 iop 的可选后端，不逐行重复。`pango/cairo` 仅用于面板绘图，属 UI 面，不计。

| 模块 | 行数 | 计算面外部依赖 | Lightamer | 证据 / 差异 |
|---|---:|---|---|---|
| `spektrafilm` | 6813 | — | 有 | `LightamerIOP/Sources/SpektraFilm` + `LightamerCore/Sources/Film`（5093 行） |
| `ashift` | 6280 | — | 部分 | `LightamerIOP/Sources/Ashift`（854 行 vs 6280；自动线检测/全参数未核） |
| `lens` | 5209 | lensfun | 有 | `LightamerIOP/Sources/Lens`（2477 行，Lensfun 三态） |
| `channelmixerrgb` | 5185 | — | 有 | `LightamerIOP/Sources/ChannelMixerRGB` |
| `retouch` | 4883 | — | 有 | `LightamerCore/Sources/Layers/Retouch` + `App/.../RetouchPanelView.swift`（层形态，非 iop） |
| `filmicrgb` | 4763 | — | 有 | `LightamerIOP/Sources/FilmicRGB`（默认面禁用，DRT 替代） |
| `toneequal` | 3993 | — | 有 | `LightamerIOP/Sources/ToneEqual` |
| `colorequal` | 3989 | — | 没有 | — |
| `borders` | 3863 | — | 有 | `LightamerIOP/Sources/Yiyin` + `Borders`（fork framing 超集） |
| `denoiseprofile` | 3857 | — | 有 | `LightamerIOP/Sources/DenoiseProfile`（默认面禁用，RAW9 NR 替代） |
| `liquify` | 3819 | — | 有 | `LightamerIOP/Sources/Liquify` |
| `clipping` | 3348 | — | 部分 | `Crop`（242 行）+ `Ashift`；自动取景/透视一体面未核 |
| `agx` | 3079 | — | 有 | `LightamerIOP/Sources/AgX`（默认面禁用，DRT 替代） |
| `colorzones` | 3001 | — | 有 | `LightamerIOP/Sources/ColorZones` |
| `colorin` | 2622 | lcms2, libpng | 部分 | `Core/Decode/RasterIccParser` + `Foundation/WorkingSpace`；无独立 iop 面板 |
| `temperature` | 2385 | lcms2 | 有 | `LightamerIOP/Sources/Temperature` + `Cat02WB` |
| `ashift_lsd` | 2283 | — | 部分 | `Ashift` 自研求解替代，非逐行移植 |
| `satcurvergb` | 2264 | — | 没有 | — |
| `demosaic` | 2244 | rawspeed | 有 | `Core/Decode/RAWDecoder`（CIRAW/rawspeed 解码层） |
| `basecurve` | 2162 | — | 没有 | — |
| `colorbalancergb` | 2130 | — | 有 | `LightamerIOP/Sources/ColorBalanceRGB` |
| `crop` | 2035 | — | 有 | `LightamerIOP/Sources/Crop`（242 行，参数面较窄） |
| `colorbalance` | 2029 | — | 没有 | 仅新一代 ColorBalanceRGB/ColorWheels |
| `tonecurve` | 1987 | — | 有 | `LightamerIOP/Sources/ToneCurve` |
| `diffuse` | 1960 | — | 没有 | 无 diffuse or sharpen |
| `rgbcurve` | 1958 | — | 部分 | `ToneCurve` 承担部分，无独立 RGB 曲线模块 |
| `lut3d` | 1868 | libpng | 有 | `LightamerIOP/Sources/Lut3d`（2656 行） |
| `atrous` | 1828 | — | 部分 | `Equalizer`（367 行，仅部分小波频段） |
| `cacorrect` | 1806 | — | 部分 | `Lens` 模块仅提及 cacorrectrgb 排序，未实现 CA 校正 |
| `colorharmonizer` | 1766 | — | 没有 | — |
| `filmic` | 1671 | — | 没有 | 仅 FilmicRGB 新代 |
| `colorchecker` | 1646 | — | 部分 | `ColorMatch` + `Core/ColorMatch`（1609 行） |
| `watermark` | 1628 | — | 有 | `LightamerIOP/Sources/Yiyin/WatermarkModule.swift` + `Yiyin` |
| `overlay` | 1583 | — | 没有 | `TextOverlay` 是文字叠加，非 overlay 合成 |
| `basicadj` | 1550 | — | 没有 | 能力分散在 Exposure/Contrast/WhiteBlack，无单模块 |
| `colorout` | 1532 | — | 部分 | DRT / 导出 ICC 承担，无独立 colorout 模块 |
| `rgblevels` | 1529 | — | 部分 | `Levels` 承担部分，无独立 RGB levels |
| `highlights` | 1451 | — | 部分 | CIRAW 高光重建承担，无独立参数面 |
| `exposure` | 1392 | — | 有 | `LightamerIOP/Sources/Exposure` |
| `colorreconstruction` | 1265 | — | 部分 | CIRAW / 解码层高光恢复承担 |
| `contrastntexture` | 1227 | — | 部分 | `LocalContrast`（460 行 vs 1227） |
| `hazeremoval` | 1178 | — | 有 | `LightamerIOP/Sources/Dehaze` |
| `skinsmooth` | 1158 | — | 有 | `LightamerIOP/Sources/SkinSmooth`（darktamer fork 功能，已移植） |
| `rawprepare` | 1112 | rawspeed | 有 | `Core/Decode/RAWTechnicalParams` |
| `vignette` | 1112 | — | 有 | `LightamerIOP/Sources/Vignette` |
| `graduatednd` | 1085 | — | 没有 | — |
| `negadoctor` | 1080 | — | 没有 | — |
| `rawdenoise` | 1050 | — | 部分 | RAW9 NR 部分覆盖，无 darktable rawdenoise 参数面 |
| `colormapping` | 1049 | — | 部分 | `ColorMatch`（TRACK 色转移，语义相近非全等） |
| `sigmoid` | 1044 | — | 有 | `LightamerIOP/Sources/Sigmoid`（默认面禁用，DRT 替代） |
| `blurs` | 1032 | — | 没有 | 无镜头/运动模糊模块 |
| `levels` | 988 | — | 有 | `LightamerIOP/Sources/Levels` |
| `cacorrectrgb` | 953 | — | 部分 | `Lens` 仅提及排序，未实现 CA 校正 |
| `rasterfile` | 936 | libpng | 部分 | `Layers/Masks` 栅格源部分具备，未核 PFM/PNG 导入面 |
| `spots` | 906 | — | 部分 | `Retouch` 层可覆盖部分，无独立去尘点模块 |
| `lowlight` | 828 | — | 没有 | — |
| `zonesystem` | 816 | — | 没有 | — |
| `dither` | 788 | — | 没有 | — |
| `channelmixer` | 760 | — | 有 | `LightamerIOP/Sources/ChannelMixer` |
| `grain` | 739 | — | 有 | `LightamerIOP/Sources/Grain` |
| `useless` | 726 | — | n/a | darktable 测试模块 |
| `shadhi` | 705 | — | 有 | `LightamerIOP/Sources/Shadhi` |
| `profile_gamma` | 659 | — | 没有 | — |
| `globaltonemap` | 658 | — | 没有 | — |
| `flip` | 631 | — | 有 | `LightamerIOP/Sources/Flip` |
| `bilateral` | 629 | — | 有 | `LightamerIOP/Sources/Bilateral`（surface blur，默认面禁用） |
| `monochrome` | 598 | — | 有 | `LightamerIOP/Sources/Monochrome` |
| `lowpass` | 589 | — | 没有 | 仅 `Highpass` |
| `hotpixels` | 588 | — | 部分 | 解码层 / rawspeed 承担，无独立模块 |
| `splittoning` | 537 | — | 没有 | — |
| `enlargecanvas` | 526 | — | 没有 | — |
| `colorcorrection` | 517 | — | 没有 | — |
| `invert` | 507 | — | 没有 | — |
| `bilat` | 502 | — | 没有 | 仅 `bilateral`（surface blur）；dt `bilat` 是 Lab 局部/全局对比，未见实现 |
| `reshape` | 481 | — | 没有 | darktamer fork 新模块，Lightamer 未移植 |
| `nlmeans` | 459 | — | 有 | `LightamerIOP/Sources/NLMeans`（默认面禁用） |
| `rawoverexposed` | 458 | — | 部分 | 解码/视口指示，未核完整面 |
| `overexposed` | 442 | — | 部分 | 视口 clipping 指示/直方图，未核完整面 |
| `censorize` | 439 | — | 没有 | — |
| `sharpen` | 437 | — | 有 | `LightamerIOP/Sources/Sharpen` |
| `primaries` | 432 | — | 没有 | — |
| `defringe` | 429 | — | 没有 | — |
| `ashift_nmsimplex` | 420 | — | 部分 | 同上（自研求解器） |
| `colortransfer` | 415 | — | 没有 | — |
| `rotatepixels` | 412 | — | 部分 | 解码/元数据层承担 |
| `bloom` | 398 | — | 有 | `LightamerIOP/Sources/Bloom` |
| `soften` | 392 | — | 有 | `LightamerIOP/Sources/Soften` |
| `colorize` | 376 | — | 没有 | — |
| `highpass` | 366 | — | 有 | `LightamerIOP/Sources/Highpass` |
| `scalepixels` | 362 | — | 部分 | 解码/元数据层承担 |
| `skinmask` | 353 | — | 没有 | darktamer fork 新模块，Lightamer 未移植 |
| `gamma` | 347 | — | 部分 | `Levels` / `WhiteBlack` + 管线显示变换承担 |
| `clahe` | 340 | — | 没有 | — |
| `colorcontrast` | 325 | — | 有 | `LightamerIOP/Sources/ColorContrast` |
| `velvia` | 291 | — | 有 | `LightamerIOP/Sources/Velvia` |
| `colisa` | 284 | — | 有 | `LightamerIOP/Sources/Colisa` |
| `relight` | 271 | — | 没有 | — |
| `finalscale` | 270 | — | 有 | `Core/Pipe` 输出段 |
| `equalizer` | 245 | — | 部分 | `Equalizer`（壳模块语义） |
| `tonemap` | 233 | — | 没有 | Lightamer 无 Durand 双边色调映射 |
| `vibrance` | 206 | — | 有 | `LightamerIOP/Sources/Vibrance` |
| `demosaicscale` | 192 | — | 有 | `Core/Decode/RAWDecoder` |
| `mask_manager` | 130 | — | 有 | `Core/Layers/Masks` + `LightamerIOP/Sources/Masks` |

计数：**有 43 / 部分 26 / 没有 33 / n/a 1 = 103**。
上游 `add_iop` 唯一注册名 98，fork HEAD 101（3 个 fork 新增 iop：`skinsmooth`、`reshape`、`skinmask`）。

## Table 2 — darktable 功能域（21 域）

行数为该域主源码量级（`.c/.cc`，不含 vendored `src/external/` 与测试/数据）。

| # | 功能域 | 源码位置 | 行数量级 | 说明 |
|---:|---|---|---:|---|
| 1 | 暗房处理链 | `src/iop/` + `src/develop/` | 149,074（模块）+ 10,106（helper）+ 48,150（develop） | pixelpipe、iop 调度、缓存、tiling |
| 2 | 图库 / lighttable / 选片 | `src/libs/collect.c`、`filtering.c`、`filters/`、`common/collection.c`、`views/lighttable.c`、`dtgtk/thumbtable.c`、`libs/select.c` | 19,672（核心 7 文件；另有 `duplicate`/`image`/`recentcollect` 1,739 未计） | 集合查询语言、星级/色标过滤、缩略图表 |
| 3 | 导入 / 相机支持 | `src/libs/import.c`、`src/imageio/*.c`（顶层）、`common/image.c`、`common/mipmap_cache.c` | 18,722（不含 vendored rawspeed/LibRaw） | 文件导入、raw 解码、缩略图缓存 |
| 4 | 导出 | `src/libs/export.c`、`imageio/format/`、`imageio/storage/`、`common/pdf.c`、`libs/export_metadata.c` | 16,355 | 13 格式 + 6 存储目标（disk/gallery/email/latex/piwigo/clipboard） |
| 5 | 标签 / 颜色标签 / 评分 / 元数据 | `libs/tagging.c`、`common/tags.c`、`libs/metadata*.c`、`gui/metadata_tags.c`、`filters/rating.c`、`filters/colors.c` | 10,540 | 层级标签、色标、星级、EXIF/IPTC 编辑 |
| 6 | 样式 / 预设 / 历史 | `common/styles.c`、`common/presets.c`、`common/history.c`、`libs/history.c`、`libs/copy_history.c`、`gui/presets.c`、`gui/styles_dialog.c` | 12,401 | 跨模块 style、模块 preset、撤销栈 |
| 7 | 蒙版与混合 | `develop/blend.c`、`blend_gui.c`、`develop/masks/`、`develop/masks_gui_panel_host.c`、`masks_gui_presets.c`、`masks_gui_toolbar.c` | 62,143 | 参数/绘制/栅格蒙版 + 混合模式 |
| 8 | 色彩管理 / 显示变换 | `common/colorspaces.c`、`common/iop_profile.c`、`iop/colorin.c`、`iop/colorout.c` | 8,978 | ICC、输入/输出 profile、软打样 |
| 9 | 打印 | `views/print.c`、`libs/print_settings.c`、`common/cups_print.c`、`common/pdf.c` | 6,247 | CUPS + PDF 排版 |
| 10 | 联机拍摄 | `views/tethering.c`、`common/camera_control.c`、`libs/camera.c`、`libs/live_view.c` | 4,987 | gphoto2 相机控制 + live view |
| 11 | 地图 / 地理标记 | `views/map.c`、`libs/geotagging.c`、`libs/map_locations.c`、`libs/location.c`、`libs/map_settings.c`、`common/map_locations.c` | 8,344 | OSM 地图、GPS 写入 |
| 12 | 幻灯片 | `views/slideshow.c`、`gui/presenter*.c`（+1 头文件） | 4,403（.c）+ 91（`presenter_target.h`）= 4,494 | 全屏放映 + 转场 |
| 13 | HDR / 全景 | `common/hdr_alignment.cc`、`control/jobs/control_jobs.c` 相关段 | 1,930（对齐）+ control_jobs 合并段（未单独切分） | 仅 HDR 包围合成（SIFT+RANSAC 对齐）；**无全景拼接** |
| 14 | 修饰 | `iop/retouch.c`、`iop/liquify.c`、`iop/spots.c` | 9,608 | 修复/克隆、液化、去尘点 |
| 15 | LUT | `iop/lut3d.c` | 1,868 | 3D LUT + GMIC 缓存路径兼容 |
| 16 | Lua 脚本 | `src/lua/` | 11,151 | 全 API 脚本绑定 |
| 17 | 主题 / 快捷键 | `gui/accelerators.c`、`data/themes/`、`src/dtgtk/` | 29,868（accelerators 5,914 + themes 5,679 + dtgtk 18,275） | 32 套主题、全局快捷键编辑 |
| 18 | 首选项 | `gui/preferences.c`、`preferences_ai.c`、`preferences_mcp.c` | 4,945 | 全设置面 |
| 19 | MCP | `src/mcp/` | 5,344 | 上游已带 MCP server；fork 加 GUI 常驻 |
| 20 | AI / 神经网络 | `src/ai/`、`common/ai_models.c`、`libs/neural_restore.c`、`common/vision_bridge.c` | 13,638 | ONNX 后端、AI 修复/增强、模型管理 |
| 21 | SpektraFilm | `iop/spektrafilm.c`、`common/spektra_*.c` | 15,441 | 光谱胶片模拟（上游 5.8 新模块） |

## Table 3 — darktamer 自定义功能（`github/master..HEAD`，76 commits = 75 non-merge + 1 merge）

| # | 功能 | commits | 改动规模 | 新增 / 改动 | UI 面 | 平台依赖 |
|---:|---|---:|---|---|---|---|
| 1 | yiyin / framing 成片边框 | 23 | 5 文件 +3252/−92；`borders.c` 1,081→3,863 | 改 `borders.c`（吸收 `yiyin.c`）、新增 `framing.cl`、`borders_helper.c/h`、`test_borders_zoom.c` | 有：模块面板 + 首选项 processing/framing | 无（Pango 字体路径 + OpenCL 可选） |
| 2 | skinsmooth 磨皮 | 23 | 13 文件 +6624 | 新增 `iop/skinsmooth.c`、`skinsmooth.cl`、`common/ai/skinmask.c`、`vision_bridge.c`、`vision_osx.mm`、Rust crate | 有：模块面板 + 首选项 OpenCL 说明 | **macOS Vision**（人脸/皮肤分割）+ OpenCL 可选 |
| 3 | skinmask 皮肤域栅格蒙版 | 1 | +353 | 新增 `iop/skinmask.c`，注册进 iop_order/modulegroups | 无独立面板（作为栅格蒙版源） | 复用 Vision 分割 |
| 4 | reshape 人像颌线重塑 | 2 | 2 文件 +671 + Rust 793 | 新增 `iop/reshape.c`、`reshape.cl`、`math-skinsmooth/src/reshape.rs` | 有：模块面板 + 模板预设 | **macOS Vision** 关键点 |
| 5 | CIRAW 解码后端 | 3 | 2 文件 +206 | 新增 `imageio_ciraw.m/.h`，改 `imageio.c`、`darktableconfig.xml.in` | 无独立面板（opt-in 配置） | **macOS Core Image**（Objective-C） |
| 6 | MCP 常驻 GUI server | 6 | 16 文件 +2323/−156 | 新增 `mcp_gui_server.c/h`、`mcp_framing.c/h`、`preferences_mcp.c/h`；扩展 `dt_bridge`、`mcp_tools`、`mcp_jsonrpc`、`data/mcp_tools.json` | 有：首选项 AI 页 + 可复制客户端配置 | POSIX unix socket |
| 7 | watermark 画内锚定 | 3 | +64/−28 | 改 `iop/watermark.c`、`borders_helper`、`exif.cc` | 有：字体预览 | 无 |
| 8 | HEIF 扩展名/质量 | 2 | +50/−10 | 改 `imageio/format/heif.c`、`darktableconfig.xml.in` | 有：复选框 | Apple 平台分支（`.heic` 拼写） |
| 9 | Darktamer 品牌化 | 3 | ~30 文件（文案/图标/打包） | 改 `gui/about|splash|welcome|gtk`、pixmaps、`packaging/macosx/*` | 有：全 UI 文案/图标 | macOS bundle 打包 |
| 10 | Rust 数学核心 | 随 1/2/4 | 2 crates / 3 源文件 3,289 行 | `rust/math-core`：`math-framing`（1075）、`math-skinsmooth/lib.rs`（1421）+ `reshape.rs`（793） | 无 | 无（C ABI 供 C 侧调用） |

非功能类提交：README/RELEASE_NOTES/AGENTS ~5、gitignore 2、打包 1、CMake 登记 4、merge 1。

## Table 4 — Lightamer 超出 darktable 的已有能力（Q3 补充）

| 能力 | 证据 |
|---|---|
| 全景拼接 | `LightamerCore/Sources/Stack/Pano*.swift`（6 文件：Camera/Feature/Gain/Match/Warp/Crop） |
| 焦点合成 | `Stack/FocusMeasure.swift`、`FocusStackMerge.swift` |
| HDR 合成（Mertens + MTB 对齐） | `Stack/MertensFusion.swift`、`HDRMergeMath.swift`、`MTBAlign.swift` |
| 节点式 DRT（ACES 2.0 / OpenDRT） | `App/.../DrtPanelModel.swift`、`Core/Graph/DrtRecord.swift` |
| 版本 / 分支（mini-git 语义） | `App/.../VersionsPanelView.swift`、sidecar v13 `versions` |
| 项目库 `.lalb` + 目录投影 | `Core/Library/*`（7853 行）、`Core/Catalog/*`（2907 行） |
| 自有 MCP server（HTTP/stdio） | `App/Sources/Lightamer/MCP/*`（3607 行） |
| AI 标签/评分/深度/增强 | `App/Sources/Lightamer/AI/*`（3924 行）、`Core/AI/*`（7849 行） |
| 软打样 / EDR 显示 | `Foundation/SoftProofProfile.swift`、`UI/EDRControlView.swift` |
