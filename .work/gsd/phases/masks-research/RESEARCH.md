# 蒙版调研：各参考项目是怎样写的，我们该抄哪些

> 日期 2026-11-26。只读 lane，不写产品代码。长表见 `RESEARCH-TABLES.md`（T-M*）。
> 全文中文，标识符英文。每条带 `文件:行号` 的都是本 lane（主 agent 或 scout）亲手打开核对过的；
> 行号未亲读的一律注明。实测数字标来源，没实测的写「推断」，官方没写的写「官方未说明」。
> dt 路径指只读工作区 `Lightamer-rust-spike/refs/dt-master-latest`（= 上游 master `2e777184fe`），其它指各仓库根。

---

## §0 一页纸

**五个问题各一句话：**

1. **基础蒙版照 dt 的范围**：dt 蒙版 = 5 种手绘形状 + AI 点选 object + 16 通道 parametric + raster 复用 + 经典组/flexi 树 + 36 混合模式 + feather/blur/detail 精修；B14「基础」建议 = 4 形状（circle/ellipse/gradient/path）+ 经典组（union/intersection/difference/exclusion/sum）+ opacity/invert + 核心混合 12 个 + 缓存折键，约 10 lane / 30 h（CPU 参考管线；brush、parametric 全量、raster、flexi、余下模式顺延）。
2. **AI 蒙版各有什么**：人物/背景/天空/主体四类在 lumen-raw、AlcedoStudio、lightcraft 三家全有（正式功能）；点选物体在 dt、lumen、Alcedo、lightcraft 四家有；皮肤/面部/身体三类在所有参考项目里都没有可用的计算实现（只有 DNG 内嵌 matte 与路线图）。
3. **「抄过来」可行性**：能直接搬的没有（语言/架构都不一样）；要改着搬的 = lumen 的 sky/person/subject/background 整套（含模型清单与后处理算法）+ Alcedo 的 sky head/S3OD 任务划分思路 + dt 的 drawn/parametric/raster/group 转写 + lightcraft 的 Rust 结构（`SegMask` 量化存储、guided 边缘、命令/作业切分）；搬不了的 = lightcraft SAM 3（3.4 GB、Meta SAM License gated）、Alcedo 自训 head（GPL-3.0 权重可用但 MaSS13K 商用警告 + S3OD 数据沿革未声明）。
4. **上游最新 vs 基线**：蒙版相关只差 1 笔提交（`64051a66a3`，flexi 菜单图标性能，GUI only，blend_gui.c 2+/38-）；另 1 笔 `337d47b88e` 只改 ONNX Runtime 的 CMake 获取方式（NuGet），不碰蒙版行为。基线 `679d594f5d` 未动。
5. **点名而全缺的类别**：皮肤、面部、身体（及唇/发/眼白细分）。外部候选只列：Apple Vision 自带（person 分割、face 检测/关键点）、开源人像解析模型（face parsing 类、selfie/body 分割类）——均为未验证候选，需另开 lane 核许可与质量。

**建议：**

- **B14 范围**：按 Q1 的「基础包」做（4 形状 + 经典组 + 12 混合 + opacity/invert + 折键），10 lane / 30 h；原 B14 卡（2 lane 启用位+整图不透明度）改为 B14-0 先行，基础包为 B14-1…B14-4。
- **单开 AI 蒙版波**：开，`B-AIM`（或 C-6-AI），里面放：① ONNX 推理后端选型与落地（ort crate + CoreML EP，落 `dt-apple` 做 Apple 面、L1 做通用面）；② sky/person/subject/background 四类（lumen 模型清单：SkySeg/DeepLabV3/U2NetP，Apache/MIT/BSD 全 permissive）；③ 点选 object（SAM 类，dt/Alcedo/lumen 三家互证的 encoder-1024 + decoder-256 形态）；④ refine/fine 后处理（引导滤波 + matting，转写 lumen `selection.py`）。估 12 lane / 36 h。不放：皮肤/面部/身体（无参考实现，等 Q5 立项结论）。

---

## §1 darktable（上游最新 `2e777184fe`；基线 `679d594f5d` 同体系）

### 1.1 蒙版有哪几种

- **手绘参数图形 5 种**：circle / path / gradient / ellipse / brush（`src/develop/masks.h:39-46`）。点结构：circle=中心+半径+border（`masks.h:232-237`）、ellipse=+双半径+旋转（`:240-247`）、path=贝塞尔角点+双控点+双 border（`:267-274`）、brush=path+密度+硬度（`:277-286`）、gradient=锚点+旋转+压缩+陡度+曲率（`:289-297`）。
- **AI 点选 object**：`DT_MASKS_OBJECT`（`masks.h:49`）。首点存 `.dtdata` 引用、其余为点击 prompts（`masks.h:249-264`）；实现 `src/develop/masks/object.c`（2638 行）。
- **参数生成 parametric**：16 通道 blendif（Lab 输入/输出、RGB/HSL/JzCzhz 输入/输出，`src/develop/blend.h:131-183`），每通道 4 参数 + boost（`blend.h:229-231`）；可作 group 成员（`dt_masks_point_parametric_t`，`blend.h:241-254`）。四颜色空间求值在 `src/develop/blends/blendif_{lab,raw,rgb_hsl,rgb_jzczhz}.c`。
- **栅格复用 raster**：引用更早模块的栅格蒙版，经 `dt_dev_get_raster_mask` 扭曲到本模块 ROI（`src/develop/masks/raster.c:28-40` 头注释）。
- **组合容器 group / flexi group**：经典组 union/intersection/difference/sum/exclusion（`masks.h:66-70`）；flexi 树 screen/minimum/product/sum/difference/exclusion（`masks.h:120-125`）+ bypass/invert（`:84-92`）。
- **无固定类别语义蒙版**：dt 的 AI 只有点选 object，没有 sky/person/skin 等一键类。

### 1.2 AI 蒙版靠什么

- 框架：自研 `src/ai` 后端 + ONNX Runtime（`src/ai/backend_onnx.c` 3219 行），provider 有 CPU/CoreML/CUDA/MIGraphX/OpenVINO/DirectML（`src/ai/backend.h:28-35`）。
- 模型：`data/ai_models.json:4-17` 登记 `mask-object-sam21-small`（默认）与 `mask-object-segnext-b2hq`；SAM encoder 输入 1024（`src/common/ai/segmentation.c:32`），decoder 点提示，输出 logits 上采样回原图。
- 模型来源：`darktable-org/darktable-ai` 仓库（默认，`data/darktableconfig.xml.in:512`），经 releases-index.json 解析版本下载（`src/common/ai_models.c:177-232`）。
- **模型权重许可：未核**（模型仓库不在本地检出，本 lane 禁下载、未联网查；`ai_models.json` 无许可字段）。
- 后处理：DenseCRF/距离变换/栅格转矢量（`masks/object.c` 头 include，`#ifdef HAVE_AI` 段）。

### 1.3 组合与归属

- 每模块一份 `dt_develop_blend_params_t`：`mask_mode` 七档（disabled/整图均匀/drawn/parametric/raster/drawn&parametric/flexi，`blend.h:99-107`）+ `mask_combine`（正/反 × 排他/包含，`blend.h:110-120`）+ `opacity`（`:199`）。
- 形状全局存（`mask`/`masks_history` 表，`src/common/database.c:221/:1073`），模块经 `mask_id` 引用 group；retouch/spots 类自有形状经 `blend_mask_id`（`blend.h:224-228`）。
- 每点 opacity + 组 opacity（`masks.h:330-337`）。

### 1.4 管线生效

- CPU `dt_develop_blend_process`（`src/develop/blend.c:1006`）与 CL 版（`:1579`）；group 在 OpenCL 管线里仍走 CPU 渲染（`raster.c:36` 注释）。
- 混合模式 36 个现行 + `REVERSE` 位（`blend.h:50-96`，枚举 0x00–0x29 共 42 项，标 obsolete/deprecated 恰 6 个），obsolete 6 个；CL 核：4 mask 核 + 5 blend 核 + tone_curve/display/detail 核（`data/kernels/blendop.cl:426-1698`）。
- 缓存键含 blend（`src/develop/pixelpipe_cache.c:166` 注释：hash 反映含 blending 的全部参数）。
- 精修：feather 四档 guide（`blend.h:123-128`）+ blur + contrast/brightness + details（scharr，`blend.c:259`）。

### 1.5 历史存储

- 库：`mask` + `masks_history` 表（见上）；读 `dt_masks_read_masks_history`、写 `dt_masks_write_masks_history_item`（`src/develop/masks/masks.c:2578/:2668`）。
- XMP：`masks_history` 二进制 blob（读路径 `src/common/exif.cc:4678-~4952`，`findKey` 循环；写路径 `:5591-5639`，`xmpData.add` + 序列化）。
- AI object 像素：存 `.dtdata` sidecar（`masks.h:249-252` 注释；基线内提交 `9d054e21bf`）。

### 1.6 交互

- `src/develop/blend_gui.c`（20338 行）蒙版面板全套；mask manager、形状手柄、黄色覆盖显示（`pixelpipe_hb.c:195-201` `mask_display`）。GUI 量级大，移植时只取语义不取实现。

---

## §2 AlcedoStudio（`f4d36474`）

### 2.1 蒙版有哪几种

- `MaskSourceKind` 封闭 4 值：Brush（构建开关默认 OFF，不出货）/ Radial / LinearGradient / AiSegmentation（`alcedo_studio/src/include/edit/mask/mask_model.hpp:33-39`；kind 字符串 `mask_model.cpp:596`）。
- Radial=归一化椭圆（`mask_model.hpp:74`）、LinearGradient=原点+法线+过渡（`:87`）、AiSegmentation=`asset_key`+descriptor+recipe+edge 等（`:112`）。
- Range 附着于任何 Mask：ColorRange（OkLCh hue，`:157`）、LuminanceRange（OkLab L，`:174`）；Mask 本体含 enabled/opacity/invert（`:239`，注释 invert/opacity 属于 Mask 不属于 source）。
- Brush 即使打开构建，GraphCompiler 也抛错（`graph_compiler.cpp:309`）。无钢笔/多边形。

### 2.2 AI 蒙版靠什么

- 模型集 `alcedo-ai-mask-v1`（`rust/puerh_mind/src/service/segmentation/model_set.rs:9`），5 role（`backend.rs:22`）：SAM 2.1 Hiera tiny encoder（`model_set.rs:78-81`）+ SAM 2.1 tiny decoder（`:87-90`）+ 自训 people/sky head（`:105-108`）+ S3OD `s3od-synth`（`:127-130`，内含 DINOv3 ViT-B/16）+ 自训 sky head（`:138-141`）。
- 大小（pin 在 `scripts/ai_models/ai_mask_model_set_v1.json:69-143`，实测数字）：Windows ONNX 全套约 356.8 MB（encoder 109 MB、subject 219 MB 为大头）；macOS mlmodelc 全套约 433.4 MB。仓库内无权重，运行时下载到 `<model-dir>/alcedo-ai-mask-v<version>/`（`ai_model_package_install.hpp:19-23`）。
- 推理在 Rust sidecar `puerh_mind` 经 gRPC（`proto/segmentation.proto:33-45`，7 个 rpc，5 组语义：Load/Unload/Status/Session×2/Decode/Task）；Windows=ONNX Runtime+DirectML（`ort_backend.rs:1-7`），macOS=原生 CoreML `.mlmodelc`（`coreml_backend.rs:5-8`，encoder `All`、decoder `CpuOnly`）。C++ 主进程的 onnxruntime 只给 AI Denoise 用（`decoders/CMakeLists.txt:142-178` 注释）。
- 输出：encoder 1024→embed；decoder logits 256（`model_set.rs:21`）；任务输出一律 ALPHA 网格，`>=0.5` 为内（`segmentation.proto:178-186`）。
- 后处理：sidecar 取峰+NMS（`task_masks.rs:25-29`）；host 联合双边上采样 + gain 规则（S3OD 用半倍率、sky 用 1 保半透明，`ai_mask_coverage_composition.hpp:34-106`）；Add=max、Subtract=min（`:116`）；提交裁包围盒（`:129`）。
- 类别：Subject / Background / Sky / People（含单人 Person toggles）/ Prompt 点盒路径（`ai_mask_recipe.hpp:37-85`）。**皮肤/面部/身体：没查到**。
- 许可：代码 GPL-3.0-only + CUDA Section 7 附加（`THIRD_PARTY_NOTICE.txt:4-5`、`LICENSE:676-685`）。权重：SAM 2.1 Apache-2.0（条目 27）、S3OD MIT（条目 28）、DINOv3 用 DINOv3 License（条目 29）、自训 head GPL-3.0（条目 30）。**商用警告两处**：Sky 训练集 MaSS13K 许可不明（条目 30 + 面板常驻提示）；S3OD 的 FLUX 非商业许可与 teacher 数据条款是否传导，Alcedo 明确不作声明（`scripts/ai_models/ai_mask_model_set_v1_NOTICE.txt:48-60`）。

### 2.3 组合与归属

- Mask 归属 Color Grade 节点（`color_grade_node_model.hpp:31`）；Mask 间只有 max-union（`mask.cl:285`；CPU 参考 `grade_mask_coverage.hpp:27`）；单 Mask 顺序 source→invert→range→opacity→clamp（`mask.cl:37-45`，公式 `mask_model.hpp:471`）；Add/Subtract 只在 AI recipe 组件内（`ai_mask_recipe.hpp:34`）。

### 2.4 管线生效

- 每 Mask 一 `MaskEvaluate` pass，Grade 经 `mask` 端口消费 union（`graph_compiler.cpp:339-367`）；混合 `mix=grade_mix*mask` 后线性插值（`primary_grade.cl:299-310`）。
- 缓存 FNV-1a `ContentKey`，`kMaskImplementationVersion=3`（`content_key.hpp:47`）；AI 只 mix `asset_key`+descriptor+edge，不 mix recipe（`result_content_key.cpp:312` 注释）。
- 覆盖纹理缓存 256 MB（`mask_coverage_texture_cache.hpp:49`）；Feather/Expand 在 device 做（高斯/形态学，`ai_mask_coverage_work.hpp:62-90`）；AI 缩略图不支持（`mask_thumbnail_spec.cpp:169-172` 抛错）。

### 2.5 历史存储

- 历史操作 Add/Remove/ReplaceMaskSource/SetMaskField（`pipeline_edit_batch.hpp:32-35`）；规范 JSON 往返校验（`pipeline_edit_json.cpp:262`）；AI source JSON 白名单键（`mask_model.cpp:322-352`）。
- 参数与数据分离：JSON 存参数+`asset_key`（xxHash128，`mask_asset.hpp:100`），像素 zlib 存 DuckDB `MaskAsset` 表（`mask_asset_store.hpp:18-64`，含 GC）。
- AI 蒙版不可 transfer/paste（`document_transfer.cpp:365-368` 直接 Fail）。

### 2.6 交互

- AI 工具：point/box/path + 4 任务按钮 + People 列表 + level + Feather/Expand（拖预览、放落步）+ Undo/Redo（`editor_ai_mask_tool.hpp` 353 行；面板 `EditorAiMaskPanel.qml` 650 行）。
- Range 区通用（`EditorMaskRangeSection.qml` 299 行）；覆盖预览四态机（`editor_mask_coverage_preview.hpp:25-38`）。

---

## §3 lumen-raw（`f520192`）

### 3.1 蒙版有哪几种

- 参数图形：brush（多笔划归一化点列，渲染时光栅化）/ linear / radial（`lumen/model.py:67`；求值 `lumen/engine.py:1009`）。
- 参数生成：luminance（亮度范围+falloff）/ color（点选 Lab 距离+flood fill，非 AI，`lumen/selection.py:391`）。
- AI 语义 11 种：sky/person/subject/background/foreground/water/vegetation/mountain/building/ground/object（`lumen/model.py:62` `RASTER_KINDS`；风光 5 种 `model.py:60`）。
- **皮肤/面部/身体：无**。人脸走独立人像管线（YuNet+Face Mesh，`lumen/portrait.py:1`），非蒙版。

### 3.2 AI 蒙版靠什么

- 框架：ONNX Runtime，无 Apple Vision（`lumen/compute.py:182-296`；provider 序 CoreML/TRT/CUDA/DirectML，失败回 CPU，`:347-416`；GPU 在独立 worker 进程，`:541`）。
- 模型（映射 `lumen/selection.py:81`）：sky=SkySeg（MIT，320×320）；person=DeepLabV3 MobileNetV3（BSD，384×384，21 类取 person）；subject/background=U2NetP（Apache，320×320，background=1−subject）；foreground=MiDaS small（MIT，256×256，深度分位阈值）；风光 5 种=EfficientViT-Seg B2（Apache，短边 512，ADE20K 150 类分组求和）；object=EfficientViT-SAM L0（Apache，encoder 512 + decoder 点击，输出 256 logits）。
- 大小（`assets/editing-assets.json` 实测数字）：object-encoder 123 MB、decoder 16 MB、landscape 61 MB；sky/person/u2netp/midas 字节数没查到（清单无 bytes 字段，仓库无实体）。
- 后处理三级：quick（0.5 sharpen + 彩色引导滤波，`selection.py:109`）→ fine（无学习 matting + 灰度引导滤波，`:190`，sky 专用 grow/shrink，`:266`）→ 渲染羽化（`:404`）。
- 许可：代码 MIT（根 `LICENSE:1`）；权重 SkySeg MIT / DeepLabV3 BSD / U2NetP Apache / MiDaS MIT / EfficientViT Apache（证据 `assets/*-LICENSE.txt` + `THIRD_PARTY.md:20-37`，T-M5）。

### 3.3 组合与归属

- 蒙版隶属照片配方 `edits['masks']`，自带 16 项 adjustments（`model.py:67`）；上限 32（`app.py:958`）；串行叠加无布尔运算（`engine.py:1169`）；逐蒙版 invert/opacity/feather；AI 栅格可叠 brush 修整。

### 3.4 管线生效

- 只算包围盒+margin（`engine.py:1161`）；缓存 `alpha_key` 含几何+引用键（`engine.py:1292-1293`）；预览 1600 解码（`engine.py:128`）；栅格缩小用面积平均保分块一致（`selection.py:61-69`）。

### 3.5 历史存储

- 内存 History 全量深拷贝上限 100（`model.py:608-612`）；工程 `.lumen` JSON，raster 抽顶层按 digest 去重、蒙版存 `raster_ref`（`model.py:303-354`）；object 存点击 points（上限 32，`model.py:64`）；look 不带蒙版（`model.py:399`）。

### 3.6 交互

- AI 按钮 + 点选/颜色 toggle + 精细化（`auto_masks.py:24`）；brush/linear/radial/object/color 五画布工具（`widgets.py:821` + `app.py:1055`）；紫色 overlay（`widgets.py:729`）。

---

## §4 lightcraft（`afa18c675`）

**提醒：此前文档（`FRAMEWORK.md`、`NOTICE`）按旧提交 `0da998f2` 写成；本节行号是新提交 `afa18c675` 的。**

### 4.1 蒙版有哪几种

- `MaskShape` 13 变体（`crates/develop/src/settings.rs:1064`）：Brush/Linear/Radial（手绘，`:1065-1074`）+ ColorRange/LuminanceRange/DepthRange（范围，`:1083-1095`，Depth 渲染为空属占位，`masks.rs:320`）+ Subject/Sky/Background（`:1101-1103`，无模型：启发式或 DNG 内嵌 matte，`masks.rs:103-218`）+ Object/Prompt（`:1106-1122`，SAM 3 点击/文本）+ People/Landscape（`:1132-1136`，无创建入口，Landscape 渲染为空）。
- faces=检测框非分割（`crates/faces/src/yunet.rs:52-121`），只服务聚类；segment=SAM 3 实例/概念分割（`segment/src/lib.rs:1`），开放词汇，硬编码仅 person/animal（`lib.rs:86`）。

### 4.2 AI 蒙版靠什么

- SAM 3 纯 Rust 移植跑 candle（`lib.rs:1-25`，candle 钉 `=0.9.2`）；权重 3.44 GB（`fetch.rs:31`），`model.safetensors`+vocab（`lib.rs:89-92`），默认镜像为空、用户手放或环境变量（`fetch.rs:39-57`）。
- 推理：macOS Metal 否则 CPU（`lib.rs:99-103`）；独立 worker 线程（`worker.rs:40-52`），GPU 失败回退 CPU（`:93`），闲置 10 分钟卸载（`:36`）。输入长边 1008（`segment.rs:32`），输出 logits 288（`lib.rs:78`），阈值 0.5 存 `SegMask`（`worker.rs:483-493`）。
- 后处理：实例 merge（`detector.rs:325-332`）+ subject 挑主体（`:338-408`）+ 渲染端 guided filter（`masks.rs:367-407`）+ Edge −100…100（`:292`）。
- 许可：代码 MIT OR Apache-2.0（`Cargo.toml:8`），`segment` 仅 Apache-2.0（移植 HF transformers）；**SAM 3 权重 = Meta SAM License（非 OSI 开源），gated**（`NOTICE:40-43`、`docs/ai-masks.md:178` 起）；人脸权重 YuNet MIT / SFace Apache（商用 Unknown）/ AuraFace Apache（`known.rs:29-85`）。

### 4.3 组合与归属

- `MaskOp::{Add,Subtract,Intersect}`（`settings.rs:992`），`Add=max`（`masks.rs:177`）；组件级 invert→guided refine→整 mask invert→amount（`masks.rs:160-198`）；`seg` 存所属 shape 内；Lens Blur 经 `focus_mask` 引用（`lens_blur.rs:272-273`）。

### 4.4 管线生效

- 每 render 求全部可见 mask（`local.rs:255`），无跨 render mask 缓存；混合=17 项 alpha 加权求和（`finish.rs:132-141`）；WGSL 只实现 5 基础 kind，AI 形回 CPU（`crates/gpu/src/render.rs:1679`）；`hash64` 含 mask 全字节（`develop/src/lib.rs:107`）。

### 4.5 历史存储

- `Op::SetDevelop` 入栈（Add/Edit/Brush/Object Mask 等标签，`cmd/masks.rs:274-411`）；`SegMask` base64+deflate+i8 量化（`segmask.rs:20-61`，`MAX_SIDE=1024`）；快照 grid 去重（`journal.rs:354-397`）；sidecar 整份 JSON（`sidecar.rs:691`）。

### 4.6 交互

- 10 宫格面板（`masking.rs:97-107`）+ loupe 点击（`detail/masks.rs:612-660`）+ 自动精化（`app.rs:591`）+ 5 种 MaskView（`visualize.rs:75`）。

---

## §5 SpektraLab（`4cab8b6`，就地读）/ RawLab（`67c40c451`）/ yiyin（`f8de57a`，就地读）

- **SpektraLab：有基础、无 AI、已下线**。5 component（linear/radialGradient、luminance/colorRange、brush 占位不可用，`modern_UI/Spektrafilm/Spektrafilm/Model/Mask.swift:50-51`）；闭式 coverage（`modern_UI/Spektrafilm/Spektrafilm/Canvas/Shaders.metal:204-278`）；add=max/subtract=min + inverted/amount（同上）；8 蒙版×6 component 上限（`modern_UI/Spektrafilm/Spektrafilm/Model/Mask.swift:198/:200`）；sidecar 参数存储（`modern_UI/Spektrafilm/Spektrafilm/Model/Sidecar.swift:125-186`）；`FeatureFlags.masks=false`（`modern_UI/Spektrafilm/Spektrafilm/Model/FeatureFlags.swift:41`）。许可：代码 GPL-3.0-or-later、profiles/LUTs CC BY-SA 4.0（`README.md:83-85`）。
- **RawLab：无实现，只有路线图**。阶段三参数/范围蒙版（`docs/architecture/roadmap.md:124-142`）、阶段四 AI 语义（主体/天空/背景/植被/建筑/面部皮肤/身体皮肤/眼白/唇/发，`:148-149`）+ 连续深度（`:150-151`）。许可：代码 GPL-3.0-only（`docs/reference/licensing.md:9`）；降噪权重 CC BY-NC / Academic（非蒙版，警示用）。
- **yiyin：无蒙版**。`mask` 全系阴影中间层/位掩码/EXIF 字符串。**许可矛盾**：根 `LICENSE`=GPL-3.0 全文 vs `package.json:10`=MIT，需澄清（与蒙版无关，抄它代码前必须先定）。

---

## §6 五问

### Q1 基础蒙版照 dt：范围是什么

dt 上游最新蒙版体系 = §1 全表（5 形状 + object + 16 通道 parametric + raster + 经典组/flexi + 36 混合 + feather/blur/detail + mask manager GUI）。

B14「基础」建议（CPU 参考管线，Rust 转写；图形处理器份以后再做）：

| 包 | 内容 | lane×h |
|---|---|---|
| B14-0（原卡） | 启用位 + 整图不透明度 + S12 接通 + 折键 | 2×3（已立项） |
| B14-1 drawn 核心 | circle/ellipse/gradient/path 光栅化（CPU）+ 经典组 union/intersection/difference/exclusion/sum + opacity/invert + oracle 对照 | 4×3 |
| B14-2 混合 | 核心 12 混合（normal2/bounded/multiply/screen/overlay/softlight/add/subtract/lighten/darken/average/difference2，运算进 `dt-blend` L1）+ blend v15 参数编解码（读 dt 用，写自有；编解码进 `dt-history` L2） | 2×3 |
| B14-3 缓存与管线 | mask 身份折缓存键 + ROI/tiling + 降采样预览 + latest-wins 下的 mask 失效 | 2×3 |
| 小计 | | 10 lane / 30 h |

顺延（非基础）：brush（dt `brush.c` 3647 行，交互最重）→ C-6；parametric 16 通道全量（4 文件）→ C-6（先只做 Lab L 通道随 B14-1 验证链路，含在 B14-1 内）；raster（跨模块传 mask）→ C-6；flexi 树 → C-6；余下 24 混合 → C-6；mask manager GUI → 界面波。

理由：B14-1 的 4 形状覆盖 dt drawn 蒙版 90% 用法（brush 除外，推断）；经典组五算子是 flexi 之前十年的全部组合语义；12 混合覆盖日常所需；parametric 先单通道验证链路、全量后补是最小风险顺序。工作量按 dt 源码量级估：4 形状光栅化约当 B4 demosaic（4 lane），混合+参数约当 B7（2 lane），缓存约当 B1 零头（2 lane）。

纪律检查（§1.9/§7/架构约束）：光栅化与混合是渲染作业内算子，不进命令（命令只改参数）；Apple 东西零新增（CPU 纯 Rust）；`dt-blend`（L1，栅格化与混合运算）+ `dt-history`（L2，混合参数编解码）+ `dt-pipeline` 接线，层表 T-F9 不动。

### Q2 AI 蒙版各项目各有什么

对照表见 T-M2。用户点名六类逐类：

- **皮肤**：全缺。最接近的是 lightcraft DNG 内嵌 `MatteKind::Skin`（有 matte 才有，无计算）与 RawLab 路线图面部/身体皮肤（规划）。
- **人物**：lumen ●（DeepLabV3 正式）/ Alcedo ●（People/Person，S3OD+SAM 正式）/ lightcraft ◐（Person matte 或 matte 并集 + People 预留，无独立计算）/ dt —（仅点选 object）。
- **背景**：lumen ●（1−subject）/ Alcedo ●（原生任务）/ lightcraft ●（1−Subject 启发式，有 matte 则用 matte）。
- **天空**：lumen ●（SkySeg）/ Alcedo ●（自训 sky head）/ lightcraft ◐（启发式/ matte，无模型）。
- **面部**：全缺（只有检测框：LC YuNet、lumen 人像管线；无分割蒙版）。
- **身体**：全缺（RawLab 路线图身体皮肤除外）。

另：主体 subject 在 lumen/Alcedo/LC 三家正式；点选 object 在 dt/lumen/Alcedo/LC 四家正式（dt SAM2.1、lumen EfficientViT-SAM、Alcedo SAM2.1、LC SAM3——形态互证：encoder-1024 + decoder-256 + 点击 prompts）。

### Q3 「抄过来」每一项的可行性

**能直接搬**：没有。语言（C/C++/Python/Swift/QML）与架构（dt 整块 blob、Alcedo 节点+sidecar、lumen Python、LC 强类型）无一与我们（Rust + T-F9 分层 + 自有设置模型）同构。

**要改着搬**（按优先级）：

1. **lumen 四类语义（sky/person/subject/background）**：模型清单 SkySeg/DeepLabV3/U2NetP 全 permissive（MIT/BSD/Apache，T-M5），输入 320-384 小图、单类输出，转写 Rust + ort 推理。落点：推理后端 L1（ort 通用）+ Apple 面进 `dt-apple`（CoreML EP 探针已有 `vision_requests` 先例，`APPLE-BOUNDARY.md` §3）；参数/存储 L2/L1。估 6 lane / 18 h（含 ort 选型 + 1 类打通 + 3 类复制 + oracle）。
2. **lumen refine/fine 后处理**：引导滤波 + matting 纯算法（`selection.py:109-266`），MIT，转写进 `dt-blend`（L1）。估 2 lane / 6 h。
3. **lumen 点选 object（EfficientViT-SAM）**：Apache-2.0，encoder 123 MB 可接受；形态与 dt/Alcedo 互证。估 2 lane / 6 h。
4. **dt drawn/parametric/raster/group 转写**：GPL-3.0 同许可，C→Rust。见 Q1。
5. **lightcraft Rust 结构**：`SegMask` 量化存储（`segmask.rs`）、guided 边缘（`masks.rs:367`）、作业切分（worker+回退+卸载），MIT/Apache，可抄设计。估含在 1-3 内（0.5 lane 阅读）。
6. **Alcedo 任务划分思路**：S3OD subject + sky head + SAM prompt 三路分工、recipe 可复现、AI 蒙版不可 transfer（`document_transfer.cpp:365`）——抄纪律不抄代码。0 lane（阅读已含）。

**搬不了**：

1. **LC SAM 3**：权重 Meta SAM License（非 OSI 开源）+ gated + 3.4 GB。设计可参考，权重不可随包。
2. **Alcedo 自训 head**：权重 GPL-3.0 可用，但 Sky 训练集 MaSS13K 许可不明（商用警告）+ S3OD 数据沿革未声明；且 macOS 侧是 CoreML 原生、Windows 侧 ONNX——搬权重等于搬两套。结论：不搬权重，搬任务划分。
3. **dt object 权重**：许可未核（Q4 留尾巴），核完再定。
4. **RawLab 降噪权重**：CC BY-NC / Academic 非商业——与蒙版无关，列出是警示：模型许可必须逐个核，不能默认随代码许可。

许可总账：我们是 GPL-3.0-or-later。GPL 系（dt/Alcedo/SpektraLab/RawLab 代码）✓；MIT/BSD/Apache（lumen/LC 代码+模型）✓；Meta SAM License ✗；DINOv3 License 未细读（Alcedo S3OD 内含，不搬则无关）；yiyin 矛盾（不抄则无关）。

### Q4 上游最新 vs 基线，蒙版有没有变

**只有 1 笔，且是 GUI 性能**：`64051a66a3`（flexi 算子菜单图标去 PNG 往返，`src/develop/blend_gui.c` 2+/38-，另带 `src/gui/gtk.c` 通用函数 67+/9- 及 `gtk.h` 5+/0-）。`src/develop/masks*`、`blend.c/h`、`blends/`、`blendop.cl`、`masks_gui_*` 其余零 diff（`git diff --stat 679d594f5d..FETCH_HEAD` 亲跑）。另 `337d47b88e add ONNXRuntime via NuGet` 只改 `cmake/modules/FindONNXRuntime.cmake` 获取方式，不碰行为。基线 `679d594f5d` 未动（`git worktree list` 亲证 detached 未挪）。

### Q5 点名而全缺的类别与外部来源

- 全缺：**皮肤、面部、身体**（及唇/发/眼白细分）。部分解：LC DNG 内嵌 matte（依赖拍摄端，不可算）。
- 外部来源（只列，未验证，需另开 lane 核许可+质量+体积）：
  1. Apple Vision 自带：person 分割（`dt-apple` 能力表已有 `vision_requests` 探针位，`APPLE-BOUNDARY.md:63`）、face 检测/关键点（转分割需自研后处理）、body 姿态。优点：零权重、走 `dt-apple` 即合规；缺点：无皮肤类、person 为整人。
  2. 开源人像解析（face parsing）模型：输出 skin/hair/lips 等部位。优点：正好补皮肤/唇/发；缺点：许可与体积逐个核，多为研究权重。
  3. 开源 selfie/body 分割模型：人物二值/多类。优点：小而快；缺点：不管皮肤细分。
- 不做决定：Q5 的选择（Vision 先行 vs 外部权重）是「需要用户定的事」第 4 件。

---

## §7 需要用户定的事（4 件）

1. **B14 按「基础包」做（10 lane / 30 h）还是维持原卡（2 lane）把余部全扔 C-6？**
   推荐：基础包。理由：原卡（启用位+整图不透明度）验证不了任何蒙版链路；基础包一次把 drawn→组→混合→缓存链路打通，后续 brush/parametric/raster 都是加法。代价：阶段 B +8 lane / +24 h（81→89 lane）。
2. **单开 AI 蒙版波 B-AIM（12 lane / 36 h）吗？里面放 lumen 四类 + object + 后处理？**
   推荐：开，范围如 §0 建议。理由：四类模型全 permissive、无许可雷；形态四家互证；与 B14 链路正交（B-AIM 产的是栅格蒙版源，消费 B14 的组/混合）。若不开：AI 蒙版整体顺延到 C 期，第 0 期无 AI。
3. **推理后端：ort（ONNX Runtime Rust 绑定）+ CoreML EP 吗？**
   推荐：ort。理由：lumen/dt/Alcedo(Windows) 三家同栈，模型互通（onnx 文件可直接复用清单）；Apple 面收进 `dt-apple`（CoreML EP + Vision），通用面 L1 ort 后端，层表合规。备选 candle（LC 路线，纯 Rust 但只有 SAM3 可用、生态小）。需 B-AIM 内先做选型 lane（含许可登记，ort 是 MIT）。
4. **皮肤/面部/身体缺口：接受「Vision 先行（person/face 能力）+ 外部权重候选另开调研」吗？**
   推荐：接受。理由：参考项目里没有可用实现，硬做等于自研；Vision 零权重先补 person 级，皮肤细分等调研 lane 结论（许可+质量+体积三门）再定。若不接受：三类从路线图拿掉，明确不做。

---

## §8 修订记录

（自审回注后填。）

2026-11-26 按独立评审（`review.log`，`PASS / 1 error + 13 minor`）回注：E1 Alcedo 商用警告引文改正确文件名（`scripts/ai_models/ai_mask_model_set_v1_NOTICE.txt:48-60`，§2.2 与 T-M5 两处）；M1 混合模式数 36（§1.4、§0、Q1、T-M1a 四处，顺延余数 ~18→24）；M2 `ai_models.h` 538 行；M3 写侧函数全名（§1.5 与 T-M4 两处）；M4 XMP 读写双路径（§1.5 与 T-M4 两处；评审写 T-M1a，实为 T-M4，T-M1a 无 XMP 行）；M5 gRPC 7 个 rpc；M6 `crates/gpu/src/render.rs:1679` 全路径（§4.4，T-M4 补行）；M7 `:160-198`（§4.3 与 T-M1g 两处）；M8 补 `app.py:1055`（评审写 T-M1b，实为 §3.6，T-M1b 无该行）；M9 13 变体（§4.1 与 T-M4 两处）；M10 经典组补 sum（§0 与 B14-1 两处，入 B14-1）；M11 混合编解码落 `dt-history`（L2，B14-2 与纪律检查两处）；M12 SpektraLab 上限 `:198/:200` 并统一补路径前缀（§5 与 T-M1c）；M13 补 `gtk.h`。以上不改 §7 四项用户决策（评审结论）。

---

## 附：证据索引

- 拉取记录与提交号：T-M0。蒙版清单：T-M1a–g。类别对照：T-M2。可行性：T-M3。代码位置：T-M4。模型与许可：T-M5。
- dt 只读工作区：`Lightamer-rust-spike/refs/dt-master-latest`（`2e777184fe`）；基线 `refs/dt-master`（`679d594f5d`）未动。
- 各 scout 全文：本会话 agent 记录（AlcedoMasks / LumenMasks / SpektraYiyin / RawLabMasks / LightCraftMasks）。
