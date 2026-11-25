# FEATURE-SCOPE — darktable + darktamer 功能面盘点（只读 lane）

> 日期 2026-11-25。口径：只读源码 + git 元数据；零构建、零测试、零 commit。
> 明细表在 `FEATURE-SCOPE-TABLES.md`。本节所有行数命令可复现（`wc -l`）。

## §0 一页纸

- **darktable iop**：**103 个模块源**（100 个 `.c` + 3 个 `.cc`）= **149,074 行**；另有 17 个 helper `.c`（`demosaicing/`、`hlreconstruct/`）10,106 行，全树 159,180 行。`add_iop` 唯一注册名：fork HEAD **101**，上游 ref **98**。
- **darktable 功能域**：**21 个**（含暗房链、图库、导入、导出、标签、样式、蒙版、色彩管理、打印、联机、地图、幻灯片、HDR、修饰、LUT、Lua、主题/快捷键、首选项、MCP、AI、SpektraFilm）。
- **darktamer 自定义**：**8 个功能 + 品牌化改造 + 1 个 Rust 数学核心**，共 **76 commits**、**109 文件、+14,808/−933**（`git diff --stat github/master...HEAD`）。
- **Lightamer iop 对照**（103 个 darktable 模块）：**有 43 / 部分 26 / 没有 33 / n/a 1**。
- **Lightamer 功能域对照**（21 域）：**有 12 / 部分 4 / 没有 5**（没有 = 打印、联机拍摄、地图/geotag、幻灯片、Lua）。
- **最重要更正**：本机 `/Volumes/UNITEK/Documents/Development/darktable` **不是纯净官方树**，而是 darktamer 分叉工作树（`git describe` = `darktamer-0.0.4-109-g16ca3f76d6`，`github-fork` remote 指向 `kamasylvia/darktamer`）。上游基线取本地 ref `github/master` = `679d594f5d`（2026-11-22）。
- **darktamer 自定义清单**：yiyin/framing 边框、skinsmooth 磨皮、skinmask 皮肤蒙版、reshape 颌线重塑、CIRAW 解码后端、MCP 常驻 GUI server、watermark 画内锚定、HEIF 扩展名 + Darktamer 品牌化；`rust/math-core` 3 crates / 3,289 行已把 framing + skinsmooth/reshape 数学搬到 Rust。
- **Lightamer 已超出 darktable**：全景拼接、焦点合成、HDR 合成、节点式 DRT、版本分支、`.lalb` 项目库、自有 MCP、AI 标签/评分。
- **最大功能空洞**（相对 darktable）：打印、联机拍摄、地图、幻灯片、Lua、retouch 之外的修饰链（diffuse/blurs/defringe）、长尾显示变换（basecurve/negadoctor/colorize 等）。
- **分期建议（§4，非结论）**：P0 = 导入→图库→解码→基础暗房→DRT→sidecar/历史→蒙版→导出闭环；P1 = 调色全量 + 修饰 + HDR/全景/焦点 + 库检索/批量导出 + fork 人像功能；P2 = 打印/联机/地图/幻灯片/Lua/长尾 iop。

## §1 Q1 — darktable 功能面

**规模总览**（`src/` 主源码，`wc -l`）：

| 层 | 文件数 | 行数 |
|---|---:|---:|
| `src/iop/` | 100 `.c` + 3 `.cc` + 6 `.h` | 149,074（模块）；+10,106（helper）= 159,180 |
| `src/develop/`（pixelpipe/blend/mask） | 18 `.c` | 48,150 |
| `src/common/` | 94 `.c/.cc` | 98,145 |
| `src/libs/`（lighttable 面板族） | 33 `.c` + 17 filters | 51,748 + 3,701 |
| `src/views/` | 7 `.c` | 14,910 |
| `src/imageio/` | 20 `.c`（顶层） | 10,320（format/storage 另计 12,348） |
| `src/gui/` | 22 `.c` | 31,577 |
| `src/dtgtk/` | 17 `.c` | 18,275 |
| `src/lua/` | 29 `.c` | 11,151 |
| `src/mcp/` | 6 `.c` | 5,344 |
| `src/ai/` | 2 `.c` | 4,557 |
| `data/kernels/*.cl` | 57 | 25,871 |

**iop 组成**：103 个模块源（100 `.c` + 3 `.cc`：`lens`、`bilateral`、`tonemap`），其中 3 个是 fork 新增（`skinsmooth`、`reshape`、`skinmask`），2 个是 ashift 的 vendored 求解器（`ashift_lsd`、`ashift_nmsimplex`），1 个 dummy（`mask_manager`），1 个测试模块（`useless`）。另有 17 个 helper `.c` 在 `demosaicing/`、`hlreconstruct/`。逐模块用途、行数、计算面外部依赖见 `FEATURE-SCOPE-TABLES.md` Table 1。

**外部库依赖（计算面，非 UI）**：绝大多数 iop 只依赖 GLib/GTK 与可选 OpenCL；按 `#include` 证实的计算面外部库只有：
- `lcms2`：`colorin`、`temperature`
- `libpng`：`colorin`、`lut3d`、`rasterfile`
- `rawspeed`（vendored）：`demosaic`、`rawprepare`
- `lensfun`：`lens`
- `exiv2`：无 iop 直接 include（元数据在 `common/exif.cc`）

`pango/cairo` 出现在大量 iop 中，但全部是面板绘图（曲线/波形控件），不进入像素链。

**功能域与量级**：21 域，逐域源码位置与行数见 Table 2。量级最大的三块：
1. 暗房处理链：149k（iop 模块）+ 10k（解码 helper）+ 48k（develop）≈ **207k 行**；
2. 蒙版与混合：`develop/masks/` 35,227 + `blend_gui.c` 20,374 + `blend.c` 3,202 + `masks_gui_*` 3,340 = **62,143 行**；
3. 主题/快捷键/自绘控件：≈ **29.9k 行**。

**HDR 与全景**：darktable 有 HDR 包围合成（`common/hdr_alignment.cc` 1,930 行，SIFT + RANSAC 单应对齐，`control_jobs` 累积 raw CFA）；**没有全景拼接**（`grep -ri panorama` 只命中裁剪比例预设与注释）。

**导出格式与流程**：`src/imageio/format/` 13 个编码器 = `jpeg`、`png`、`tiff`、`heif`、`avif`、`webp`、`jxl`、`j2k`、`pdf`、`xcf`、`pfm`、`ppm`、`copy`；`src/imageio/storage/` 6 个目标 = `disk`、`gallery`、`email`、`latex`、`piwigo`、`clipboard`。流程 = `libs/export.c` 组装 → `imageio` 编码 → storage 落盘，元数据经 `libs/export_metadata.c`。

**非暗房模式**：`src/views/` 7 个 = `view.c` / `lighttable` / `darkroom` / `print` / `tethering` / `map` / `slideshow`。打印 = 6,247 行、联机 = 4,987 行、地图 = 8,344 行、幻灯片 = 4,494 行。

**AI / MCP（上游已有，非 fork 独有）**：`src/ai/` ONNX 后端 + `common/ai_models.c` + `libs/neural_restore.c` ≈ 14.2k 行；`src/mcp/` 5.7k 行（fork 在其上加了 GUI 常驻服务）。

## §2 Q2 — darktamer 自定义功能

**方法**：本机树本身是 darktamer 工作树且保留上游 ref，因此无需 GitHub API、无需克隆。差异口径：
`git rev-list --count github/master..HEAD` = **76 commits**（75 non-merge + 1 merge）；
`git diff --stat github/master...HEAD` = **109 files changed, 14,808 insertions(+), 933 deletions(-)**。
**未做浅克隆**，报告目录大小 = 0（无新增副本）。

**8 个功能 + Rust 数学核心**（逐条文件/行数/UI/平台依赖见 Table 3）：

1. **yiyin / framing 成片边框**（23 commits）：`borders.c` 从 1,081 行扩到 3,863 行，吸收 `yiyin.c`；新增 `data/kernels/framing.cl`、`develop/borders_helper.c/h`、缩放回归测试。三种模式：basic / blur / film strip；最多 3 行 EXIF 信息条、字体/透明度/尺寸可配。UI = 模块面板 + 首选项。
2. **skinsmooth 磨皮**（23 commits）：新增 `src/iop/skinsmooth.c`（1,158 行）+ `data/kernels/skinsmooth.cl` + `common/ai/skinmask.c` + `common/vision_bridge.c` + `common/vision_osx.mm`；数学主体在 `rust/math-core/crates/math-skinsmooth`（1,421 行）。UI = 模块面板 + OpenCL 首选项说明。平台 = **macOS Vision**（人脸/皮肤分割）+ 可选 OpenCL。
3. **skinmask 皮肤域栅格蒙版**（1 commit，+353 行）：新增 `src/iop/skinmask.c`，注册进 `iop_order`/`modulegroups`；无独立面板，作为栅格蒙版源。
4. **reshape 人像颌线重塑**（2 commits）：新增 `src/iop/reshape.c`（481 行）+ `data/kernels/reshape.cl` + Rust `reshape.rs`（793 行）；全身体区模板 + 关键点驱动。平台 = macOS Vision 关键点。
5. **CIRAW 解码后端**（3 commits）：新增 `imageio_ciraw.m`（160 行）/`.h`（46 行），改 `imageio.c` 与配置；opt-in，不替换 rawspeed 默认路径。平台 = **macOS Core Image**（Objective-C）。
6. **MCP 常驻 GUI server**（6 commits，16 文件 +2,323/−156）：新增 `mcp_gui_server.c/h`（624 行）、`mcp_framing.c/h`、`preferences_mcp.c/h`；扩展 `dt_bridge`、`mcp_tools`、`mcp_jsonrpc`、`data/mcp_tools.json`。能力：导入/列表/打开暗房/实时改栈/导出/评分色标/驱动 lighttable 集合/读写选区/样式/渲染统计；首选项 AI 页可复制客户端配置。平台 = POSIX unix socket。
7. **watermark 画内锚定**（3 commits，+64/−28）：水印锚到画面而非采样窗口；附字体预览。
8. **HEIF 扩展名/质量**（2 commits，+50/−10）：Apple 构建提供 `.heic` 拼写复选框，默认质量 75。
9. **Rust 数学核心**（随 1/2/4）：`rust/math-core` 2 crates / 3 源文件 3,289 行（`math-framing` 1,075；`math-skinsmooth/lib.rs` 1,421 + `reshape.rs` 793），C ABI 供 C 侧调用。**这是「非 UI 用 Rust」方向的现成先例。**

**附带改动**：Darktamer 品牌化（About/Splash/Welcome/图标/打包，~30 文件）、README/RELEASE_NOTES、gitignore、CMake 登记。`src/iop/lut3d.c` 与 `src/iop/spektrafilm.c` 只有 2/4 行品牌或注释级改动，不算功能。

**盘全程度**：以本机 fork 历史为准，76 commits 全量读过 subject + name-status；未逐个 commit 读 diff 内容（行级细节按 diffstat）。未核对 GitHub issue 台账（`11de3fdf93 docs: keep fork development memory in GitHub issues` 指向 issue，但本次未拉取）。

## §3 Q3 — Lightamer 现状对照

**口径**：以 `LightamerIOP/Sources/Registry.swift` 的 `registry.register` 行 + 目录存在性 + `LightamerCore` 对应实现为「有」；只有部分参数/由解码层或别模块承担为「部分」；无实现为「没有」。保守判定，未逐参数面深核。

**iop 对照计数**（Table 1）：**有 43 / 部分 26 / 没有 33 / n/a 1**。

**Lightamer 模块注册实数**：`Registry.swift` 直接 `register` 47 个（含 DEBUG 专用 `TestGain`），`gatedRegister` 6 个（`FilmicRGB`、`Sigmoid`、`AgX`、`DenoiseProfile`、`NLMeans`、`Bilateral`，默认面跳过）；即生产 iop 模块 **52** 个。`retouch` 不在 registry，走 `Layers/Retouch` 层形态。

- **有**（43）：`agx`、`bilateral`、`bloom`、`borders`、`channelmixer`、`channelmixerrgb`、`colisa`、`colorbalancergb`、`colorcontrast`、`colorzones`、`crop`、`demosaic`、`demosaicscale`、`denoiseprofile`、`exposure`、`filmicrgb`、`finalscale`、`flip`、`grain`、`hazeremoval`、`highpass`、`lens`、`levels`、`liquify`、`lut3d`、`mask_manager`、`monochrome`、`nlmeans`、`rawprepare`、`retouch`、`shadhi`、`sharpen`、`sigmoid`、`skinsmooth`、`soften`、`spektrafilm`、`temperature`、`tonecurve`、`toneequal`、`velvia`、`vibrance`、`vignette`、`watermark`。
- **部分**（26）：`ashift`、`ashift_lsd`、`ashift_nmsimplex`、`atrous`、`cacorrect`、`cacorrectrgb`、`clipping`、`colorchecker`、`colorin`、`colormapping`、`colorout`、`colorreconstruction`、`contrastntexture`、`equalizer`、`gamma`、`highlights`、`hotpixels`、`overexposed`、`rasterfile`、`rawdenoise`、`rawoverexposed`、`rgbcurve`、`rgblevels`、`rotatepixels`、`scalepixels`、`spots`。集中在「darktable 一整块、Lightamer 由解码层/DRT/别模块分担」与「参数面窄」两类。
- **没有**（33）：`basecurve`、`basicadj`、`bilat`、`blurs`、`censorize`、`clahe`、`colorbalance`、`colorcorrection`、`colorequal`、`colorharmonizer`、`colorize`、`colortransfer`、`defringe`、`diffuse`、`dither`、`enlargecanvas`、`filmic`、`globaltonemap`、`graduatednd`、`invert`、`lowlight`、`lowpass`、`negadoctor`、`overlay`、`primaries`、`profile_gamma`、`relight`、`reshape`、`satcurvergb`、`skinmask`、`splittoning`、`tonemap`、`zonesystem`。

**功能域对照**（21 域）：

| 状态 | 域 |
|---|---|
| 有（12） | 暗房处理链、图库/lighttable、导入、色彩管理/显示变换、蒙版与混合、HDR 合成、修饰、LUT、首选项、MCP、AI、SpektraFilm |
| 部分（4） | 导出（6 格式 vs darktable 13）、标签/色标/评分（有 rating/label/flag，无层级 tag/IPTC 关键词面）、样式/预设（模块 preset 有，跨模块 style 未核）、主题/快捷键（主题 token 有，自定义快捷键编辑器未核） |
| 没有（5） | 打印、联机拍摄、地图/geotag、幻灯片、Lua |

**Lightamer 的超出项**（不是差距，是已有资产）：全景拼接、焦点合成、HDR 合成、节点式 DRT（ACES 2.0 / OpenDRT）、版本分支、`.lalb` 项目库、自有 MCP server、AI 标签/评分/深度/增强、软打样/EDR。证据见 Table 4。

**结论性观察**：Lightamer 的 iop 覆盖面已接近 darktable 的「日常可用」子集（43 有 + 26 部分 = 69/103）；缺口集中在（a）darktable 的 legacy/长尾显示变换模块，（b）非暗房模式（打印/联机/地图/幻灯片/Lua），（c）retouch 之外的修饰链（diffuse/blurs/defringe/censorize）。

## §4 Q4 — 分期建议（建议，非结论）

按「一个用户拿它处理自己照片的日常流程」排。目标形态 = darktable 功能面 + darktamer 自定义，UI 复刻 darktable，非 UI Rust。

**P0 — 不做就不能日常用**
- 导入 + 图库浏览/选片（缩略图、星级/色标、基本过滤）
- RAW 解码（CIRAW / rawspeed 路线）
- 基础暗房：曝光、白平衡、ToneCurve/Levels、裁剪/旋转/透视、镜头校正
- 色彩管理 + 显示变换（DRT）
- sidecar / 历史 / 撤销 / 版本
- 蒙版 + 混合基础
- 导出 JPEG/PNG/TIFF/HEIC
- 首选项 + 菜单/快捷键骨架
- 理由：这条链闭合，用户才能「把卡里的照片变成成品」。缺任何一环，后面所有模块都无法被真实使用。

**P1 — 专业工作流与差异化**
- 调色全量：ColorBalanceRGB、ColorWheels、ColorZones、HLS、LUT、SpektraFilm 胶片模拟
- 修饰：Retouch（修复/克隆）、Liquify；fork 的 skinsmooth/skinmask/reshape 人像链
- framing/yiyin 成片边框（darktamer 一等功能）
- 图库检索/标签/IPTC、批量导出、命名模板/元数据策略
- HDR 合成、全景拼接、焦点合成
- HDR/EDR 视口、软打样
- AI 选片/评分/标签
- 完整蒙版工具（参数/绘制/栅格）
- 理由：这些是「为什么不用 Lightroom」的答案，也是 darktamer 已有的差异化；但都建立在 P0 闭环上。

**P2 — 以后再做**
- 打印、联机拍摄、地图/geotag、幻灯片
- Lua 脚本/插件生态（若 Rust 侧有替代，可只保留兼容层）
- 长尾 iop：`blurs`、`censorize`、`negadoctor`、`basecurve`、`colorize`、`graduatednd`、`splittoning`、`zonesystem`、`lowlight`、`globaltonemap`、`colorequal`、`satcurvergb`、`primaries`、`defringe`、`dither`、`lowpass`、`enlargecanvas`、`colorcorrection`、`invert`、`clahe`、`relight`、`colortransfer`、`colorharmonizer`、`overlay`、`basicadj`
- 主题/快捷键编辑器
- 理由：非常用路径、可被现有模块近似替代、或依赖外部硬件/服务（打印机、相机、地图瓦片）。

## §5 没查到的

- **Lightamer 参数面深度**：只按注册表/文件存在判定；「部分」是保守标记，未逐模块核对参数完整度、golden 覆盖、GPU/CPU 双跑。
- **darktable iop 的 CPU/OpenCL 双腿覆盖**：未逐模块统计，只知 OpenCL 为全 iop 可选后端。
- **darktable 外部依赖**：按 `.c/.cc` 的 `#include` 判定；间接依赖（`common/` 里的 lensfun/lcms/rawspeed 封装）未逐调用链展开。
- **darktamer 逐 commit diff 内容**：只读 subject + name-status；行级改动按 diffstat，未逐 hunk 审。
- **darktamer GitHub issue 台账**：未拉取（本地树已足够回答功能面；issue 可能含未合入的设计）。
- **Lightamer 样式/预设与 darktable styles 的语义等价性**：未逐字段比对。
- **Lightamer 自定义快捷键**：只确认 `MenuCommandSet` / `NSMenuBridge` 存在，未核是否有用户可编辑的快捷键映射表。
- **打印/幻灯片/联机/地图**：用 `grep -ril` 判「没有」，未逐目录深挖是否存在半成品。
- **行数口径**：`.c/.cc`（Table 1 与 §1 表）；Table 2 域 12 额外含 1 个头文件 `presenter_target.h`（91 行），已在格内标注。不含测试、数据、kernel（kernel 单独 25,871 行）。不同口径不可直接相加。
- **域 13 的 control_jobs 合并段**：未从 1.9k 行的 `control_jobs.c` 里切出 HDR 专用行数，只给对齐模块的精确值。

## §6 复审修订记录（对照 `scope-review.log`）

独立 `omp -p` 复审判 `6 error + 11 minor`。已修：

- **E1** `borders.c` 上游基线 863 → **1,081**（`git show github/master:src/iop/borders.c | wc -l`）；Table 3 与 §2 同改。
- **E2** Rust 核心 3 crates → **2 crates / 3 源文件**（`math-framing` + `math-skinsmooth`，后者含 `lib.rs`/`reshape.rs`）。
- **E3** lensfun 误挂 `cacorrect`/`demosaic`/`overlay` → 只挂 **`lens`**（`#include <lensfun.h>` 唯一命中）；同批删掉无 include 证据的 lcms2/rawspeed/exiv2 误挂。
- **E4** watermark commits 2 → **3**（含字体预览提交）。
- **E5** Pano 文件 7 → **6**。
- **E6** 补 3 个 `.cc` 注册模块（`lens` 5,209 / `bilateral` 629 / `tonemap` 233，共 6,071 行）；分母 100 → **103**，计数重算为 **43/26/33/1**；`bilat` 从「有」下调为「没有」（Lightamer `Bilateral` 实为 dt `bilateral`，不是 `bilat`）。
- **m1** 含头文件的行数已全部改为 `.c/.cc`-only（develop 55,604→48,150、common 121,812→98,145、views 15,674→14,910、gui 35,442→31,577、dtgtk 20,275→18,275、lua 12,591→11,151、mcp 5,697→5,344、ai 5,165→4,557）。
- **m2** `add_iop` 改用唯一名：上游 98 / fork 101（此前 104/107 是行数含重复）。
- **m3** 76 commits 标注为 75 non-merge + 1 merge。
- **m4** 域 7 蒙版/混合 62,112 → **62,143**。
- **m5** 域 4 导出按精确和 **16,355**（原稿 16,377 为估算）；域 11 的 8,344 可复现（含 `map_settings.c` 160）。
- **m6** 域 2/6/12 源码清单补全，域 12 标注含 1 头文件。
- **m7** MCP diffstat 15/+2,243 → **16/+2,323**。
- **m8** HEIF 维持 50/−10（单文件口径），已注明。
- **m9** watermark 证据路径改为 `LightamerIOP/Sources/Yiyin/WatermarkModule.swift`。
- **m10/m11** 文件计数与 `~` 口径已在标题/表格内标注。

