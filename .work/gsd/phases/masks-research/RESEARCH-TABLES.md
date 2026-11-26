# RESEARCH-TABLES — 蒙版调研长表（正文见 RESEARCH.md）

> 日期 2026-11-26。行号均为本 lane 亲读（`文件:行号`）。dt 路径无前缀说明时指只读工作区 `Lightamer-rust-spike/refs/dt-master-latest`（= 上游 master `2e777184fe`）；其它项目路径指各仓库根。
> 状态：AlcedoStudio、lightcraft 两节待 scout 回报后补。

---

## T-M0 各项目拉取前后提交号

| 项目 | 拉前 | 拉后 | 说明 |
|---|---|---|---|
| AlcedoStudio（`main`） | `6024386` | `f4d36474` | `git pull --ff-only` 成功 |
| lumen-raw（`main`） | `6a2b631` | `f520192` | `git pull --ff-only` 成功 |
| SpektraLab（`main`） | `4cab8b6` | `4cab8b6`（未动） | 本地 ahead 1 / behind 28，分叉，按纪律不拉，就地读 |
| RawLab（`development`） | `db86717b` | `67c40c451` | 直连失败（fetch-pack disconnect），加代理 `10809` 后成功 |
| lightcraft（`main`） | `0da998f2` | `afa18c675` | `git pull --ff-only` 成功。**提醒：`FRAMEWORK.md`、`NOTICE` 里引用 lightcraft 的位置是按旧提交 `0da998f2` 写成的，行号已漂移** |
| yiyin（`release`） | `f8de57a` | `f8de57a`（未拉） | 有未提交改动（`?? .zcode/`），按纪律不拉，就地读 |
| dt 基线 `refs/dt-master` | `679d594f5d` | `679d594f5d`（未动） | 实现基线，不许挪；只 `git fetch github master` |
| dt 只读工作区 `refs/dt-master-latest` | — | `2e777184fe` | `git worktree add --detach ../dt-master-latest FETCH_HEAD` 新开 |

---

## T-M1 各项目蒙版清单

### T-M1a darktable（上游最新 `2e777184fe`，= 基线 `679d594f5d` 加 1 笔 GUI 提交）

| 类 | 种类 | 说明 |
|---|---|---|
| 手绘参数图形 | circle / ellipse / path / gradient / brush（`src/develop/masks.h:39-46`） | circle（中心+半径+border）、ellipse（+旋转+双半径）、path（贝塞尔多边形）、gradient（锚点+旋转+压缩+陡度+曲率）、brush（贝塞尔笔划+密度+硬度）。点结构 `masks.h:232-297` |
| AI 点选分割 | object（`masks.h:49` `DT_MASKS_OBJECT`） | SAM/segnext 点提示分割；点结构=首点 `.dtdata` 引用 + 其余点击 prompts（`masks.h:249-264`）；实现 `masks/object.c`（2638 行）；像素存 `.dtdata` sidecar |
| 参数生成 | parametric / blendif（`masks.h:50` + `blend.h:131-183`） | 16 通道（Lab/Lab输出、RGB/HSL/JzCzhz 输入+输出），每通道 4 参数曲线 + boost；可作 group 成员（`dt_masks_point_parametric_t`，`blend.h:241-254`） |
| 栅格复用 | raster（`masks.h:51`） | 引用更早模块的栅格蒙版（op+instance+id），经 `dt_dev_get_raster_mask` 扭曲到本模块 ROI（`masks/raster.c:28-40` 注释） |
| 组合容器 | group / flexi group（`masks.h:41` + `blend.h:107` `DEVELOP_MASK_FLEXI`） | 经典组：union/intersection/difference/sum/exclusion（`masks.h:66-70`）；flexi 树：screen/minimum/product/sum/difference/exclusion（`masks.h:120-125`）+ bypass/invert（`:84-92`） |
| 蒙版模式（每模块） | disabled / enabled（整图均匀）/ drawn / parametric / raster / drawn&parametric / flexi（`blend.h:99-107`） | `dt_develop_blend_params_t.mask_mode`（`blend.h:191`） |
| 精修 | feather（引导羽化）/ blur / contrast / brightness / details（`blend.h:206-217`） | feather 有 in/out × before/after 四档 guide（`blend.h:123-128`）；details 走 scharr/detail mask（`blendop.cl:1684-1698` + `blend.c:259`） |
| 混合模式 | 36 个现行模式（`blend.h:50-96`，枚举 0x00–0x29 共 42 项，去 obsolete/deprecated 6 个） | normal2/bounded/lighten/darken/multiply/average/add/subtract/screen/overlay/softlight/hardlight/vividlight/linearlight/pinlight/lightness/chromaticity/hue/color/coloradjust/difference2/lab 系/hsv 系/lab 单通道/rgb 单通道/subtract-inverse/divide/divide-inverse/geometric/harmonic 均值；另 +`REVERSE` 位（`:95`）；obsolete 6 个 |
| 蒙版归属 | 每模块一份 `dt_develop_blend_params_t` + 全局 drawn 形状库 | 形状全局存（`mask`/`masks_history` 表），模块经 `mask_id` 引用 group；`IOP_FLAGS_NO_MASKS` 模块（retouch/spots）自有形状经 `blend_mask_id`（`blend.h:224-228`） |

### T-M1b lumen-raw（`f520192`）

| 类 | 种类 | 说明 |
|---|---|---|
| 手绘参数图形 | brush / linear / radial（`lumen/model.py:67` `new_mask`；求值 `lumen/engine.py:1009` `mask_alpha`） | brush=多笔划归一化点列+radius（渲染时光栅化）；linear/radial=start/end 归一化坐标；面板 `lumen/app.py:556` |
| 参数生成 | luminance / color（`lumen/engine.py:1009` luminance 分支；`lumen/selection.py:391` `color_region`） | luminance=亮度范围+falloff；color=点选 Lab 距离+8 连通 flood fill（非 AI） |
| AI 语义 | sky / person / subject / background / foreground / water / vegetation / mountain / building / ground / object（`lumen/model.py:62` `RASTER_KINDS`） | 浮点概率图存 base64 PNG；person=DeepLabV3；subject/background=U2NetP（background=1-subject）；foreground=MiDaS 深度阈值；风光 5 种=EfficientViT-Seg ADE20K 分组；object=EfficientViT-SAM 点选；sky=SkySeg。映射 `lumen/selection.py:81` `MODELS` |
| 无 | skin / face / body | `RASTER_KINDS` 与 `AI_REGIONS` 均无；人脸走独立人像管线 `lumen/portrait.py:1`（YuNet+Face Mesh，非蒙版） |
| 组合 | 串行叠加，无布尔运算（`lumen/engine.py:1169` `apply_local`） | 每蒙版独立 alpha 后 `region·(1−w)+local·w`；逐蒙版 invert/opacity/feather；AI 栅格可叠 brush 笔划修整；上限 32 个（`lumen/app.py:958`） |
| 归属 | 照片配方 `edits['masks']` 列表成员，自带 16 项 adjustments | 预设/look 不带蒙版（`lumen/model.py:399` `LOOK_KEYS`） |

### T-M1c SpektraLab（`4cab8b6`，就地读；功能已下线）

| 类 | 种类 | 说明 |
|---|---|---|
| 手绘参数图形 | linearGradient / radialGradient（`modern_UI/Spektrafilm/Spektrafilm/Model/Mask.swift:50-51`） | 闭式解析 coverage（`modern_UI/Spektrafilm/Spektrafilm/Canvas/Shaders.metal:204-278`） |
| 参数生成 | luminanceRange / colorRange（同上） | 同上；colorRange 需取色器点选 |
| 栅格涂画 | brush（占位，不可用） | UI 添加列表故意排除（`modern_UI/Spektrafilm/Spektrafilm/Panels/Sections/MasksSection.swift:113` 注释：无光栅化后端） |
| 无 | AI 语义 | 零 CoreML/模型调用（蒙版代码内 grep 零命中） |
| 组合 | add 取 max / subtract 取 min（`modern_UI/Spektrafilm/Spektrafilm/Canvas/Shaders.metal:204-278` `maskCoverage`）+ 蒙版级 inverted/amount | 上限 8 蒙版 × 6 component（`modern_UI/Spektrafilm/Spektrafilm/Model/Mask.swift:198/:200`） |
| 状态 | `FeatureFlags.masks=false` 关闭（`modern_UI/Spektrafilm/Spektrafilm/Model/FeatureFlags.swift:41`） | 代码测试全留，sidecar 读写 round-trip 不受影响 |

### T-M1d RawLab（`67c40c451`）

无已实现蒙版。4 处名字沾边均非编辑蒙版：全局暗角 `lutools/src/core/photo_effects.cpp:69-103`、直方图 `clipping_mask` `lutools/include/sony2fuji/ffi/sony2fuji_c.h:714-733`、SwiftUI `.mask` 裁剪显示 `RawLab/RawLab/UI/Editor/ContentView+Panels.swift:384-398`、索尼对焦框 `RawLab/RawLab/Core/Camera/CameraFocusController.swift:239-263`。路线图阶段三（参数/范围蒙版，`docs/architecture/roadmap.md:124-142`）与阶段四（AI 语义/深度，`:144-152`）属规划未实现。

### T-M1e yiyin（`f8de57a`，就地读）

无蒙版体系。`mask` 命中 7 处全系印框阴影合成中间层（`electron/src/modules/image-tool/index.ts:82/164/297/435-443`、`interface.ts:137`）、位运算掩码（`web/util/md5.ts:10-12`）、EXIF 测光字符串（`electron/src/modules/exiftool/index.ts:143`）。

### T-M1f AlcedoStudio（`f4d36474`）

| 类 | 种类 | 说明 |
|---|---|---|
| 手绘参数图形 | Radial / LinearGradient（`mask_model.hpp:37-38`） | 归一化椭圆/原点+法线渐变；`mask_model.hpp:74/:87` |
| 栅格涂画 | Brush（默认关闭，不出货） | 构建开关 `ALCEDO_ENABLE_BRUSH_MASK` 默认 OFF（`CMakeLists.txt:129-132`）；GraphCompiler 遇 Brush 抛错（`graph_compiler.cpp:309`） |
| 参数生成 | ColorRange / LuminanceRange（附着于任何 Mask） | OkLCh hue / OkLab L（`mask_model.hpp:157/:174`） |
| AI 语义+prompt | AiSegmentation（`mask_model.hpp:39`） | Subject/Background/Sky/People/Person/Prompt（`ai_mask_recipe.hpp:37-85`）；SAM2.1+自训 head+S3OD+sky head（`model_set.rs`）；无皮肤/面部/身体 |
| 组合 | Mask 间 max-union（`mask.cl:285`）；单 Mask source→invert→range→opacity（`mask.cl:37-45`）；Add/Subtract 只在 AI recipe 内 | Mask 归属 Grade 节点（`color_grade_node_model.hpp:31`） |

### T-M1g lightcraft（`afa18c675`）

| 类 | 种类 | 说明 |
|---|---|---|
| 手绘参数图形 | Brush / Linear / Radial（`settings.rs:1065-1074`） | 笔刷点列+size/feather/flow/density/erase/auto_mask/pressure（`BrushStroke`，`settings.rs:1002`） |
| 参数生成 | ColorRange / LuminanceRange / DepthRange（`:1083-1095`） | DepthRange 渲染为空属占位（`masks.rs:320`） |
| AI 语义（启发式/matte） | Subject / Sky / Background（`:1101-1103`） | 无模型：天空启发式/中心显著性/1−Subject（`masks.rs:218`）；有 DNG 内嵌 matte 则用 matte（`masks.rs:103`，含 Skin/Hair/Teeth/Glasses/Person） |
| AI（SAM 3） | Object / Prompt（`:1106-1122`） | 点击/文本经 SAM 3 得 `SegMask` 存 shape 内；开放词汇无固定类 |
| 预留 | People / Landscape（`:1132-1136`） | 无创建入口；Landscape 渲染为空 |
| 无 | 面部/身体独立分割 | faces 只产检测框（`yunet.rs:52-121`） |
| 组合 | `MaskOp::{Add,Subtract,Intersect}`（`settings.rs:992`），Add=max（`masks.rs:177`） | 组件级 invert→guided→整 mask invert→amount（`masks.rs:160-198`） |

---

## T-M2 AI 蒙版类别对照表（行=类别，列=项目）

图例：●=正式功能 / ◐=实验或下线代码 / ○=规划未实现 / —=没有。行号见 T-M1 与正文。

| 类别 | darktable | lumen-raw | SpektraLab | RawLab | yiyin | AlcedoStudio | lightcraft |
|---|---|---|---|---|---|---|---|
| 皮肤 skin | — | — | — | ○（阶段四 `roadmap.md:148-149` 面部/身体皮肤） | — | —（只有整人 People） | ◐（仅 DNG 内嵌 `MatteKind::Skin`，`masks.rs:22`；无计算） |
| 人物 person | —（无语义类；仅点选 object） | ● person（DeepLabV3） | — | ○（阶段四主体，`roadmap.md:148`） | — | ● People/Person（S3OD+SAM，`ai_mask_recipe.hpp:37`） | ◐（Person matte 或 matte 并集，`masks.rs:108`；+ People 预留） |
| 背景 background | — | ● background（=1−subject，U2NetP） | — | ○（阶段四，`roadmap.md:148`） | — | ● 原生任务（`ai_mask_recipe.hpp:37`） | ●（=1−Subject；有 matte 则用 matte） |
| 天空 sky | — | ● sky（SkySeg） | — | ○（阶段四，`roadmap.md:148`） | — | ● 自训 sky head（`model_set.rs:138-141`） | ◐（启发式/matte，无模型） |
| 面部 face | — | —（YuNet 找脸仅供人像管线/闭眼提示，非蒙版） | — | ○（阶段四面部皮肤，`roadmap.md:149`） | — | — | —（faces 只产检测框） |
| 身体 body | — | — | — | ○（阶段四身体皮肤，`roadmap.md:149`） | — | — | —（最接近整人 Person matte） |
| 主体 subject | — | ● subject（U2NetP） | — | ○（阶段四，`roadmap.md:148`） | — | ● S3OD（`model_set.rs:127-130`） | ●（SAM 3 `pick_prominent` + 启发式） |
| 点选物体 object | ● object（SAM2.1/segnext 点提示） | ● object（EfficientViT-SAM 点选） | — | — | — | ● Prompt 点/盒/路径（SAM2.1 decoder） | ● Object/Prompt（SAM 3） |
| 风光组 water/vegetation/mountain/building/ground | — | ●（EfficientViT-Seg ADE20K 分组） | — | ○（植被/建筑，`roadmap.md:148`） | — | — | —（Landscape 预留，渲染为空） |
| 近景/深度 foreground/depth | — | ● foreground（MiDaS 深度阈值） | — | ○（连续 16-bit 深度，`roadmap.md:150-151`） | — | — | —（DepthRange 占位） |
| 唇/发/眼白 lips/hair/sclera | — | — | — | ○（阶段四，`roadmap.md:149`） | — | — | ◐（Hair/Teeth/Glasses 仅 DNG matte） |

---

## T-M3 「抄过来」可行性表

| 来源 | 标的 | 语言/依赖 | 落点（T-F9） | 许可 | 档 | 估时 |
|---|---|---|---|---|---|---|
| lumen-raw | sky/person/subject/background 四类 | Python+ONNX Runtime；模型 MIT/BSD/Apache-2.0 | 推理 L1（ort）+ Apple 面 `dt-apple`；参数/存储 L2/L1 | 代码 MIT ✓；权重 permissive ✓ | 改着搬 | 6 lane / 18 h |
| lumen-raw | refine/fine 后处理（引导滤波+matting） | Python；纯算法 | `dt-blend`（L1） | MIT ✓ | 改着搬 | 2 lane / 6 h |
| lumen-raw | 点选 object（EfficientViT-SAM） | Python+ORT；Apache-2.0 | 同四类 | ✓ | 改着搬 | 2 lane / 6 h |
| darktable | drawn/parametric/raster/group 全套 | C+OpenCL | `dt-blend`（L1）CPU 参考管线 | GPL-3.0 ✓ | 改着搬 | Q1：基础 10 lane / 30 h |
| darktable | object（SAM）权重 | C+ORT；权重在 darktable-ai 仓库 | 同上 | 代码 ✓；权重**未核** | 待定 | 核完再定 |
| AlcedoStudio | 任务划分+recipe+不可 transfer 纪律 | C++/Rust；思路 | 纪律进设计文档 | 思路无许可问题 | 改着搬（抄设计） | 0 lane（阅读已含） |
| AlcedoStudio | 自训 head / S3OD 权重 | onnx/mlmodelc | — | MaSS13K 商用警告 + S3OD 沿革未声明 | 搬不了（权重） | — |
| lightcraft | `SegMask` 存储/guided 边缘/作业切分 | Rust；MIT/Apache | 设计进 L1/L2/L4 | ✓ | 改着搬（抄设计） | 含在 lumen 项内 |
| lightcraft | SAM 3 权重 | safetensors 3.4 GB | — | Meta SAM License（非 OSI）+ gated | 搬不了 | — |
| SpektraLab | 参数化蒙版语义 | Swift+Metal | 思路进 `dt-blend` | GPL-3.0-or-later ✓ | 改着搬（参考语义） | 含在 Q1 内 |

---

## T-M4 代码位置表

### darktable（`dt-master-latest`）

| 文件 | 行数 | 管什么 |
|---|---|---|
| `src/develop/masks.h` | 1986 | 形状/组/状态枚举与全部点结构（亲读 `:36-145`、`:232-297`） |
| `src/develop/blend.h` | 1188 | blend v15（`:31`）、颜色空间/混合模式/蒙版模式/combine 枚举（`:41-128`）、blendif 通道（`:131-183`）、`dt_develop_blend_params_t`（`:187-236`）、parametric 点（`:241-254`） |
| `src/develop/blend.c` | 3202 | CPU `dt_develop_blend_process`（`:1006`）、CL 版（`:1579`）、feather（`:636`）、detail 精修（`:259`）、refine bypass（`:316-429`）、legacy 迁移（`:3018-3165`） |
| `src/develop/blend_gui.c` | 20338 | 蒙版面板全套 GUI（含 flexi 面板；Q4 唯一改动文件，2+/38-） |
| `src/develop/blends/blendif_{lab,raw,rgb_hsl,rgb_jzczhz}.c` | 4 文件 | 四颜色空间 parametric 求值 |
| `src/develop/masks/masks.c` | 4922 | 形状库读写、读 `dt_masks_read_masks_history`、写 `dt_masks_write_masks_history_item`（`:2578`/`:2668`） |
| `src/develop/masks/group.c` | 1483 | 组渲染 `dt_masks_group_render_roi`（`:1349`） |
| `src/develop/masks/{circle,ellipse,path,gradient,brush}.c` | 1520/2235/6140/1542/3647 | 五形状的光栅化+交互 |
| `src/develop/masks/object.c` | 2638 | AI object 形状（含 `#ifdef HAVE_AI` 分割调用） |
| `src/develop/masks/parametric.c` | 300 | group 内 parametric 成员 |
| `src/develop/masks/raster.c` | 399 | raster 成员（头注释 `:28-40` 语义） |
| `src/develop/masks/pixel_mask.c` | 1464 | 像素蒙版渲染/缓存 |
| `data/kernels/blendop.cl` | 1708 | 4 mask 核 + 5 blend 核 + tone_curve/display_channel/detail 核（`:426-1698`） |
| `src/common/ai/segmentation.{h,c}` | 229/1627 | SAM 编码一次+点提示解码；`SAM_INPUT_SIZE 1024`（`.c:32`） |
| `src/ai/backend_{h,_common,_onnx}.{h,c,c}` | 511/1338/3219 | ONNX 后端；provider 枚举 CPU/CoreML/CUDA/MIGraphX/OpenVINO/DirectML（`backend.h:28-35`） |
| `src/common/ai_models.{c,h}` | 3085/538 | 模型注册表+下载（releases-index.json，`.c:177-232`；默认仓库 `darktable-org/darktable-ai`，`darktableconfig.xml.in:512`） |
| `data/ai_models.json` | 40 行 | 模型清单：mask-object-sam21-small（默认）/mask-object-segnext-b2hq/denoise/rawdenoise/upscale |
| `src/common/database.c` | — | `mask` 表（`:221`）、`masks_history` 表（`:1073`） |
| `src/common/exif.cc` | — | XMP `masks_history` 二进制 blob 读写（读 `:4678-~4952` + 写 `:5591-5639`） |
| `src/develop/pixelpipe_hb.c` | — | `mask_display`（`:195-201`）、raster 存储开关（`:228`）、detail mask（`:295-296`） |
| `src/develop/pixelpipe_cache.c` | — | 缓存键含 blend（`:166` 注释） |

### lumen-raw（`f520192`）

| 文件 | 行数 | 管什么 |
|---|---|---|
| `lumen/selection.py` | 420 | 全部推理与栅格运算（MODELS `:81`、automatic `:297`、refine `:109`、fine `:190`、raster_alpha `:404`） |
| `lumen/auto_masks.py` | 339 | AI 蒙版 UI 与异步任务（面板 `:24`、创建 `:149`、后台精细化 `:221`） |
| `lumen/model.py` | 638 | 配方（`RASTER_KINDS` `:62`、`new_mask` `:67`、pack/unpack `:303/354`、History `:608`） |
| `lumen/engine.py` | 1779 | 管线（`mask_alpha` `:1009`、`apply_local` `:1169`、RenderCache `:1095`） |
| `lumen/compute.py` | 562 | ONNX 会话（provider 规划 `:347`、CoreML `:182`、CPU 回退 `:416`、worker 隔离 `:541`） |
| `lumen/ai_models.py` | ~240 | 模型定位/清单/下载 |
| `lumen/app.py` / `lumen/widgets.py` | 1434/1167 | 蒙版面板/画布工具与 overlay |
| `lumen/portrait.py` | 786 | 人像管线（YuNet+Face Mesh，非蒙版） |
| `MODEL.md` / `THIRD_PARTY.md` | — | 模型来源文档 / 第三方许可清单 |

### SpektraLab（`4cab8b6`）/ RawLab（`67c40c451`）/ yiyin（`f8de57a`）

见 T-M1c/d/e 行号。正文不再复表。

### AlcedoStudio（`f4d36474`）

| 文件 | 行数 | 管什么 |
|---|---|---|
| `alcedo_studio/src/include/edit/mask/mask_model.hpp` | 503 | source 枚举/Range/`MaskModel`/JSON（亲读 `:33-39`、`:74-239`、`:471`） |
| `alcedo_studio/src/edit/mask/mask_model.cpp` | 795 | 校验+JSON 编解码（亲读 `:232-352`、`:596`） |
| `.../mask/ai_mask_recipe.hpp` / `.cpp` | 160/332 | recipe/组件/任务/prompt/edge（亲读 `:27-110`） |
| `rust/puerh_mind/src/service/segmentation/model_set.rs` | 183 | 模型文件名/张量/版本（亲读 `:9-64`、`:175`） |
| `.../segmentation/backend.rs` / `ort_backend.rs` / `coreml_backend.rs` | 209/591/557 | 5 role trait / ORT 后端 / CoreML 后端 |
| `.../segmentation/engine.rs` / `task_masks.rs` | 2294/917 | 引擎 / 任务规则（亲读 `:25-77`） |
| `rust/puerh_mind/proto/segmentation.proto` | 236 | gRPC 契约（亲读 `:15-48`、`:141-210`） |
| `alcedo_studio/src/edit/runtime/graph_compiler.cpp` | 570 | Mask 栈编译（亲读 `:277-367`） |
| `.../runtime/opencl/shader/mask.cl` | 295 | 求值/range/union 核（亲读 `:37-285`） |
| `.../runtime/result_content_key.cpp` | 695 | 内容键（亲读 `:238-406`） |
| `scripts/ai_models/ai_mask_model_set_v1.json` | — | 模型集 pin（亲读 `:11-143`） |
| `scripts/ai_models/ai_mask_model_set_v1_NOTICE.txt` | — | 模型 NOTICE（亲读 `:18-90`） |

### lightcraft（`afa18c675`）

| 文件 | 行数 | 管什么 |
|---|---|---|
| `crates/develop/src/settings.rs` | 1566 | `MaskShape` 13 变体（亲读 `:992-1210`） |
| `crates/develop/src/segmask.rs` | 13.6 KB | `SegMask` 量化存储（亲读 `:12-131`） |
| `crates/pipeline/src/masks.rs` | 903 | 求值/matte/seg 采样/guided（亲读 `:18-423`） |
| `crates/gpu/src/render.rs` | — | WGSL 5 基础 kind 分发（`:1590-1665`），其余形状落 None 走 CPU（`:1678-1688` 调 `shape_alpha`） |
| `crates/pipeline/src/finish.rs` | 1169 | 混合（亲读 `:132-141`、`:699-716`） |
| `crates/segment/src/lib.rs` / `detector.rs` / `fetch.rs` | 328/495/— | SAM 3 API / DETR 后处理 / 下载（亲读 `lib.rs:1-137`、`fetch.rs:25-57`） |
| `crates/faces/src/yunet.rs` / `known.rs` | 392/— | 检测框 / 模型清单许可（亲读 `yunet.rs:1-121`、`known.rs:29-137`） |
| `crates/engine/src/segment.rs` / `segment/worker.rs` | 902/673 | Segmenter / worker（亲读 `:32-164`、`:36-93`） |
| `crates/engine/src/cmd/masks.rs` | 1206 | mask.* 命令（亲读 `:63-541`） |
| `docs/ai-masks.md` | — | AI 蒙版文档（亲读 `:39-178`） |

---

## T-M5 模型与许可证证据表

| 项目 | 模型 | 许可 | 证据文件（亲读） |
|---|---|---|---|
| lumen-raw | SkySeg（sky） | MIT | `assets/SkySeg-LICENSE.txt:1` + `THIRD_PARTY.md:20` |
| lumen-raw | DeepLabV3 MobileNetV3（person, TorchVision） | BSD-3-Clause | `THIRD_PARTY.md:21` + `assets/models/selection-models.json:9` |
| lumen-raw | U2NetP（subject/background, rembg 发布） | Apache-2.0 | `assets/U2NET-LICENSE.txt:1` + `THIRD_PARTY.md:22` |
| lumen-raw | MiDaS v2.1 small（foreground） | MIT（Intel ISL） | `assets/MiDaS-LICENSE.txt:1` + `assets/models/v11-models.json:3` |
| lumen-raw | EfficientViT-SAM L0（object）/ EfficientViT-Seg B2（风光） | Apache-2.0 | `assets/EfficientViT-LICENSE.txt:1` + `THIRD_PARTY.md:37` |
| lumen-raw | 代码 | MIT | 根 `LICENSE:1` |
| darktable | mask-object-sam21-small / segnext-b2hq | **未核**（模型在 `darktable-org/darktable-ai` 仓库，不在本地检出；禁下载，本 lane 未联网查） | `data/ai_models.json:4-17`（仅 id，无许可字段） |
| darktable | 代码 | GPL-3.0 | `LICENSE:1-4`（GPL v3 全文头） |
| SpektraLab | 无模型 | — | 蒙版代码零模型调用 |
| SpektraLab | 代码 GPL-3.0-or-later；profiles/LUTs CC BY-SA 4.0 | 见证据 | `README.md:83-85` + `license/LICENSE:1-30` + `license/SPEKTRAFILM_LICENSE.txt:2-4` |
| RawLab | DualDn（降噪，非蒙版） | CC BY-NC 4.0 | `lutools/tools/dualdn/README.md:149` + `docs/reference/licensing.md:100-107` |
| RawLab | Restormer（降噪，非蒙版） | Academic（非商业） | 同上 |
| RawLab | 代码 | GPL-3.0-only | `LICENSE:1-40` + `docs/reference/licensing.md:9`（SPDX 行） |
| yiyin | 无模型 | — | 无蒙版功能 |
| yiyin | **矛盾**：根 `LICENSE` = GPL-3.0 全文；`package.json:10` = MIT | 需上游澄清 | `LICENSE:1-33` vs `package.json:10` |
| AlcedoStudio | SAM 2.1 权重 | Apache-2.0 | `THIRD_PARTY_NOTICE.txt:204-209` + `third_party_licenses/SAM2-LICENSE.txt:1-2` |
| AlcedoStudio | S3OD 权重 | MIT | `THIRD_PARTY_NOTICE.txt:210-217` + `third_party_licenses/S3OD-LICENSE.txt:1-3` |
| AlcedoStudio | DINOv3（S3OD 内） | DINOv3 License | `THIRD_PARTY_NOTICE.txt:218-223` + `third_party_licenses/DINOv3-LICENSE.md:24-28` |
| AlcedoStudio | 自训 head + 阈值 | GPL-3.0 | `THIRD_PARTY_NOTICE.txt:224-230` |
| AlcedoStudio | Sky/MaSS13K 商用警告 + S3OD 沿革未声明 | — | `scripts/ai_models/ai_mask_model_set_v1_NOTICE.txt:48-60/80-90` + 面板常驻提示 |
| AlcedoStudio | 代码 | GPL-3.0-only + CUDA §7 附加 | `THIRD_PARTY_NOTICE.txt:4-5` + `NOTICE:5-8` + `LICENSE:676-685` |
| AlcedoStudio | ONNX Runtime 1.24.4 | MIT | `THIRD_PARTY_NOTICE.txt:245-252` |
| lightcraft | SAM 3 权重 | Meta SAM License（非 OSI）+ gated | `NOTICE:40-43` + `docs/ai-masks.md:178` 起 |
| lightcraft | YuNet / SFace / AuraFace | MIT / Apache（商用 Unknown）/ Apache | `crates/faces/src/known.rs:29-85` |
| lightcraft | 代码 MIT OR Apache-2.0；`segment` 仅 Apache-2.0 | 见证据 | `Cargo.toml:8` + `LICENSE-MIT` + `NOTICE:1-4/33-38` |
