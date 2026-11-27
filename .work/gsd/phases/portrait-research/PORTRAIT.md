# Portrait Features in Alcedo and Lumen RAW: Inventory and Adoption List

> 只读调研 lane 产物，2026-11-27。两个参考仓库均拉到最新后盘点；不改 Lightamer 代码、不构建、不提交。
> 行号约定：`A:` 前缀 = AlcedoStudio 仓内相对路径，`L:` 前缀 = lumen-raw 仓内相对路径；`W:` = 本仓 `.work/gsd/` 下已有笔记。所有 `文件:行号` 均为主进程或子 lane 亲自读到的源码原文；子 lane 引用的行号主进程已用 grep/sed 逐条复验。
> 许可三句体例：①代码许可 ②权重许可 ③训练数据许可；权重无单独声明的一律如实写「没有单独声明」，不推断。

---

## 1. Version Baseline（两仓各自的变化）

### 1.1 拉新结果

| 仓库 | 拉新前 | `git status` | `git pull --ff-only` | 拉新后 | 新提交数 |
|---|---|---|---|---|---|
| AlcedoStudio（`main`） | `f4d36474`（v0.3.7，2026-11-25） | 干净（空输出） | Already up to date | `f4d36474`，`describe` = v0.3.7 | 0 |
| lumen-raw（`main`） | `f520192`（v2.3.2，2026-11-21） | 干净（空输出） | Already up to date | `f520192`，`describe` = v2.3.2 | 0 |

两仓工作区干净且已是最新，无需停下报告。2026-09-20 至今提交数：Alcedo 1159 个（`rev-list --count --since=2026-09-20`），Lumen 25 个。

### 1.2 Alcedo 窗口内发布（v0.3.4–v0.3.7，全部落在 2026-09-20 之后）

- v0.3.4（`627bd06c`，2026-10-30）：**AI Masks**——Subject / Background / Sky / People 四任务 + 点/框/路径点选（`A:docs/changelog/0.3.4.en.txt:15`）。**这是近两月 Alcedo 唯一人像相关交付。**
- v0.3.5（`7bdd4af2`，2026-11-07）：Film Print（30 负片 + 5 反转片模拟，`A:docs/changelog/0.3.5.en.txt:12`），无人像项。
- v0.3.6（`b5833da2`，2026-11-16）：Tone Curve（含 8 预设，无 portrait，`A:docs/changelog/0.3.6.en.txt:14`；`A:alcedo_studio/src/edit/operators/models/tone_curve_presets.cpp:31-39`），无人像项。
- v0.3.7（`f4d36474`，2026-11-25）：AI Denoise（`A:docs/changelog/0.3.7.en.txt:5`）+ 用户版本预设 `.alcpreset`（`:19`，用户自存机制，非人像风格），无人像项。

对 `A:docs/changelog/` 全文 grep（`portrait|retouch|beauty|skin|face`，排除 interface/surface/preface）：**零命中**。结合 `A:alcedo_studio/src` + `A:rust/puerh_mind/src` 全文 grep（`retouch|liquify|beautif|face_mesh|facemesh|yunet|YuNet|skin_tone|skintone|teeth|eye_enhance|slim_face` 与 `bokeh|DepthMap|background_blur|BackgroundBlur|catchlight|VNDetectFace|FaceDetect|face_detect`）：**两轮均为零命中**。结论：Alcedo 除 0.3.4 AI 蒙版四任务外，无任何人像修饰/人脸/皮肤/虚化/眼神光功能。

### 1.3 Lumen 窗口内发布（2.1.1–2.3.2）

- **2.3.0（2026-11-05，`L:CHANGELOG.md:53`）：新增「人像」面板**——YuNet 人脸检测 + MediaPipe Face Mesh 478 关键点，7 项修饰（磨皮/美白/祛痘/去黑眼圈/白牙/大眼/瘦脸），工程格式升为 9（`L:CHANGELOG.md:78` 人脸检测段，`:103` 格式 9）。**这是近两月 Lumen 唯一人像功能版本。**
- 2.1.1（2026-10-26）：闭眼分析维护（两个后台开关），无新功能。
- 2.1.2（2026-10-29）：GPS 水印/更新镜像/图库修复，功能性人像关键词零命中（`L:CHANGELOG.md:128` 缺陷叙事附带提及闭眼分析的人脸检测一次，非功能变更），无人像变更。
- 2.3.1（2026-11-19）：显影 chroma/副本镜头/MCP，人像关键词零命中（`L:CHANGELOG.md:1-52` 逐行已读），无人像变更。
- 2.3.2（2026-11-21）：索尼 RAW 尺寸修复，同上零命中，无人像变更。

---

## 2. Feature Inventory（功能盘点总表）

| # | 方向 | Alcedo | Lumen RAW |
|---|---|---|---|
| F1 | 人物自动蒙版（整人） | 有：People/Person（§3.1） | 有：person（DeepLabV3）+ subject/background（U2NetP）+ foreground（MiDaS）（§3.2） |
| F2 | 脸/皮肤/头发/眼/牙/身体部位细分蒙版 | 无（§3.1 双证据 N-A1） | 无（§3.2 双证据 N-L1） |
| F3 | 点选主体 | 有：Subject 一键 + 点/框/路径（§3.1） | 有：点选物体 EfficientViT-SAM（§3.2） |
| F4 | 磨皮与肤色 | 无（N-A2） | **有：7 项人像修饰**（§3.3） |
| F5 | 人脸感知曝光/美白 | 无（N-A3） | 人脸感知曝光无（N-L2）；美白有（手动滑杆，§3.3）；vibrance 肤色保护相近物（§3.5） |
| F6 | 人像景深虚化/背景替换 | 无（N-A4） | 无（N-L3） |
| F7 | portrait 预设/风格 | 无（N-A5；胶片/曲线/DCP 名均为非人像物） | 半有：全局「柔和人像」风格有，人像设置预设无（§3.4） |
| F8 | 眼神光 | 无（N-A6） | 无（N-L4） |
| F9 | 面部识别（检测/关键点/闭眼） | 无（N-A6） | 有：YuNet + Face Mesh（选片闭眼 + 人像检测，§3.3） |

---

## 3. Item Details（逐项说明）

### 3.1 Alcedo：人物蒙版 People/Person + 点选（F1/F3，有）

**做什么，用户怎样用。** 蒙版面板打开 AI 蒙版工具：点 People 任务即得全图人物蒙版；People 列表逐个加入/移除单人（按人物序号重放）；点/框/路径三 prompt 工具 + 加/减模式 + 单击三级 mask；羽化/扩展滑杆；面板内独立撤销/重做；确认提交为一条历史记录。面板行为见 `A:alcedo_studio/src/ui/alcedo_main/qml/EditorAiMaskPanel.qml:6-12`（注释逐字：four tasks、People list、Point/Box/Path、Feather/Expand、Undo/Redo；无模型只显示状态 + "Open AI Models"）。

**怎样实现。**

- 任务枚举 host 侧 4 值 `AiMaskTaskKind { Subject, Background, Sky, People }`（`A:alcedo_studio/src/include/edit/mask/ai_mask_recipe.hpp:37`）；单人切换 `AiMaskPersonToggle{index, operation, box}`（`:85-90`）。
- sidecar 协议 5 任务 `SUBJECT/BACKGROUND/SKY/PEOPLE/PERSON`（`A:rust/puerh_mind/proto/segmentation.proto:167-176`）；掩膜统一 alpha 网格，`>=0.5` 为内（`:183-186`）。
- People = 自训 people_sky_head 在 64 栅格上定位人物框（读 SAM2.1 tiny `image_embed`，`A:rust/puerh_mind/src/service/segmentation/model_set.rs:104-124`）；Person = S3OD 在人物 crop 上的 alpha（proto `:174` 注释：`The S3OD alpha of the crop of one person`）。
- 点选 = SAM 2.1 Hiera tiny encoder-1024 + decoder-256（`A:.../model_set.rs:19-21` `IMAGE_SIZE=1024`/`LOGIT_SIZE=256`），点数上限 64、level 上限 2（`A:.../ai_mask_recipe.hpp:25-27`）。
- 推理后端：Rust sidecar `puerh_mind` 经 gRPC；Windows = ONNX Runtime + DirectML，macOS = 原生 CoreML `.mlmodelc`（**不用 ORT CoreML EP**），工厂切换见 `A:rust/puerh_mind/src/service/segmentation/mod.rs:8-10,35-45`。
- 模型（`A:scripts/ai_models/ai_mask_model_set_v1.json`，size 字段实测）：point_encoder 109,381,695 B onnx / 134,260,018 B mlmodelc（`:75`/`:109`）；point_decoder 21,188,206 / 21,098,274（`:73`/`:97`）；subject_masks（S3OD `okupyn/s3od-synth`）219,301,899 / 271,166,829（`:79`/`:121`）；people_sky_head 自训 1,119,131 / 1,138,418（`:71`/`:85`）；sky_head 自训 5,821,904 / 5,860,515（`:77`/`:133`）。来源与 checkpoint 见 `A:scripts/ai_models/ai_mask_model_set_v1_NOTICE.txt:24-26,39-40,66-67,80-81`。

**许可三句。** ①代码 GPL-3.0-only + CUDA Section 7 附加（`A:THIRD_PARTY_NOTICE.txt:4-5`）。②权重：SAM 2.1 Apache-2.0（NOTICE `:27`）；S3OD MIT（`:41`），但其内含 DINOv3 ViT-B/16 编码器适用 **DINOv3 License**（`:42-43`，重分发须附文本，`A:third_party_licenses/DINOv3-LICENSE.md:28`）；双自训 head GPL-3.0（`:68`/`:82`）；转制均未改权重（`:28-29`/`:44-46`）。③训练数据：SAM2 用 SA-1B/SA-V 及视频数据（`:30-31`）；s3od-synth 仅用 **FLUX.1 Krea [dev] 合成图**（**FLUX.1 [dev] Non-Commercial License**，`:50-52`），标签来自 teacher decoder（DIS5K/HR-SOD/UHRSD/DUTS 监督，`:53-54`），**Alcedo 明确不表态这些条款是否传导至权重/输出**（`:56-57`，原文 `does not state whether these terms apply`）；people head 用 COCO 2017 + Open Images V7（`:69-72`，CC BY 4.0 标注 + Flickr Terms/图片 CC BY 2.0）；sky head 用 MaSS13K，**仓库未声明清晰许可**（`:83-87`，商用需联系数据集作者；0.3.4 发布说明同步警告，`A:docs/changelog/0.3.4.en.txt:6`）。

**平台依赖。** Windows 需 DirectML GPU + ORT；macOS Apple 芯片原生 CoreML。**权重获取：不随包**，首次在设置 AI 模型页从签名 feed 下载（`https://static.aoraw.org/ai-models/v1/`，`A:THIRD_PARTY_NOTICE.txt:200-202`），包内自带 `licenses/` 全文 + `NOTICE.txt`。AI 蒙版权重在仓库内零文件（`A:scripts/ai_models/` 只有包定义；测试夹具 `.7z` 均为 1-2KB 占位）；仓内另有 DemosaicNet 随仓权重两份（`A:alcedo_studio/src/config/models/bayer.safetensors` 158,868 B 与 `xtrans.safetensors` 136,516 B，解码器引用 `A:alcedo_studio/src/decoders/processor/nn/demosaicnet_cache.cpp:32-36`），与 AI 蒙版无关。

### 3.2 Lumen：人物/主体/背景/前景自动蒙版 + 点选（F1/F3，有）

**做什么，用户怎样用。** 「蒙版」面板一键生成人物/主体/背景/前景等语义蒙版，叠加局部调整；点选物体 = 画面点击加选/减选得软蒙版（可点单人）。种类全表 `L:lumen/selection.py:80-83`（`MODELS`：sky/person/background/subject/foreground/landscape/object-encoder/object-decoder）与 `L:lumen/model.py:60-62`（`LANDSCAPE_KINDS` 5 种 + `RASTER_KINDS` 全表）。三处全列举均无 face/skin/hair/eyes/teeth/body-part。

**怎样实现。** `person` = TorchVision DeepLabV3 MobileNetV3（384×384，21 类取 person，`L:MODEL.md:117`）；`subject/background` = U2NetP（320×320，background=1−subject，`L:lumen/selection.py:317-318`；`L:MODEL.md:118`）；`foreground` = MiDaS small（256×256，`L:MODEL.md:102`，深度分位阈值）；`object` = EfficientViT-SAM L0（encoder 长边 512 + decoder 点击，输出 256 logits，`L:MODEL.md:19`；输入尺寸总表 `L:lumen/selection.py:146` `NETWORK`）。后端 ONNX Runtime（GPU 可选，macOS 经 CoreML EP，失败回 CPU，`L:lumen/compute.py:182` `:362`）；`landscape/object` 强制 CPU（`L:lumen/selection.py:84-87` `CPU_ONLY`，注释写明单张 CPU 比 DirectML 快）。后处理三级：quick 彩色引导滤波（`L:lumen/selection.py:109`）→ fine 无学习 matting（`:190`）→ 渲染羽化（羽化默认 `L:lumen/model.py:72-75`）。

**模型与大小**（`*_assets.json` pin，float32 原始字节）：person-deeplab 44,094,917（`L:assets/runtime-assets.json:2612`）；u2netp 4,574,861（`:2637`）；midas-small 66,764,249（`:2597`）；skyseg 175,997,079（`:2632`）；object-encoder 123,112,917（`L:assets/editing-assets.json:14`）+ decoder 16,470,362（`:20`，HF `mit-han-lab/efficientvit-sam` 固定版 `a2f0c59`）。

**许可三句。** ①代码 MIT（`L:LICENSE:1-3`）。②权重：SkySeg MIT / DeepLabV3 BSD-3 / U2NetP Apache-2.0 / MiDaS MIT / EfficientViT Apache-2.0（`L:THIRD_PARTY.md:20-37` + `L:assets/*-LICENSE.txt`，均无超出包文本的单独权重声明）。③训练数据：五个权重均**没有单独声明**（仓库内无训练集许可说明）。

**平台依赖。** 纯 ONNX + NumPy/OpenCV，无原生 API 依赖。**权重获取：随包**（完整安装包/便携包/Mac 镜像内 `models/` 目录，内容命名 `*.<sha12>.onnx`），缺失时从自有 `ai-models` release 下载并验 SHA-256（`L:lumen/ai_models.py:31` `RELEASE`，`:38-44` 15 模型 `FEATURES` 表），2.1.2 起 GitHub 失败回退新加坡→香港镜像（`L:CHANGELOG.md:122-125`）。仓库检出内无 `.onnx`（`L:assets/models/` 仅 4 个 JSON 清单，`ls` 实测）。

### 3.3 Lumen：2.3.0 人像修饰 + 面部识别（F4/F5 美白/F9，有；本次最大发现）

**做什么，用户怎样用。** 「人像」面板（`L:lumen/portrait_panel.py:35` `build_portrait`，8 面板之一（`L:CHANGELOG.md:65`），`L:lumen/app.py:343`）：首次打开自动检测人脸（`:79` `portrait_shown`）或点重新检测（`:84` 后台线程）；人脸从左到右编号，画面显示编号框（`:224`）；点编号单选、Ctrl/Shift 多选、「全部」全选（`:138`/`:147`）；两组滑杆作用于所选每张脸——皮肤组磨皮/美白/祛痘/去黑眼圈（`:20` `SKIN`），五官组大眼/瘦脸/白牙（`:21` `FEATURES`）；重检测按框 IoU>0.3 保留原设置（`L:lumen/portrait.py:198-214` `merge`）。限制：侧脸/遮挡多/很小的人脸可能找不到（`L:CHANGELOG.md:78`）。

**检测链路（面部识别）。** YuNet 检测 + Face Mesh 478 关键点（`L:lumen/portrait.py:133-161` `detect`，复用选片 `culling.faces()`；`_candidates` 在原尺寸 + 640/320 两个粗尺寸上找大脸，`:165-186`）。YuNet 由 **OpenCV `FaceDetectorYN` 运行（非 ORT）**（`L:lumen/culling.py:115`，阈值 0.7；`L:tools/compact_models.py:28-30` 注释明说 `which OpenCV's DNN runs, not ONNX Runtime`）；Face Mesh 由 **ORT CPU** 运行（`L:lumen/culling.py:108` `providers=['CPUExecutionProvider']`，2 线程）。检测图长边 1280（`L:lumen/culling.py:36`）。模型：`face-yunet.onnx` 232,589 B（`L:assets/culling-assets.json:7-8`，OpenCV Zoo `face_detection_yunet_2023mar.onnx`，提交 f12e127）+ `face-landmarks.onnx` 4,920,995 B（`:13-14`，`face_landmarker.task` float16 v1 内 `face_landmarks_detector.tflite` 经 tf2onnx 转 opset 17，权重未改动，naklitechie 固定版；`L:MODEL.md:28-33`）。打包后合计约 2.7 MB（`L:MODEL.md:28`）。**2.3.0 无新增模型**（`L:CHANGELOG.md:104`：AI 模型仍 15 个，人像复用已有两人脸模型）。

**修饰算法（`L:lumen/portrait.py` 全 786 行，纯 NumPy+OpenCV CPU，修饰本身无神经网络）。** 设置 `KEYS` 7 项（`:44`），最多 24 脸（`:47`），工作尺寸 520（`:77`）。流程位置：修复之后、白平衡与调色之前，作用于镜头校正后线性数据（`L:lumen/engine.py:1202-1212` `_base`）；每脸只算其窗口（`:236` `window`，含脖子下延），分块外扩保证与整图一致（`:251` `needed`，`:262` `apply`）；100% 图块缓存整脸（`:285-314`，512MB 上限，每块 3.8s→0.07s，`L:CHANGELOG.md:92` 段）；关键点随工程保存（格式 9，`L:lumen/model.py:28-30`，校验 `L:lumen/portrait.py:95-123`），导出不再需要模型（`L:CHANGELOG.md:83`）。

- 皮肤掩膜 `Face.skin`（`:365-395`）：脸轮廓椭圆 + 脖子多边形 − 眼/眉/唇/鼻孔（索引表 `:52-62`）× 从脸颊额头 7 采样点（`:65`）学到的色度高斯似然（`:474-496`）− 眼高细长线（镜框/发丝，`:397-437`）。
- 磨皮 `_smooth`（`:544-562`）：工作尺寸导向滤波频率分离，大强度加第二遍宽滤波，毛孔保留（高强度略柔化）。
- 祛痘 `_acne` + `_round_spots`（`:565-647`）：形态学黑帽/红帽找小而圆实心斑点，仅搜 `open_skin` 开阔皮肤（`:439-472`，避鼻翼/法令纹/眼下/唇周/下巴褶皱/脖子），深色偏冷痣/文身保留（`:84` `MARK_CONTRAST`），归一化卷积填补 + 平移纹理回填。8 张测试人像实测：干净皮肤误改 5–17%→0.2–3.7%，斑点去除 22–78%→39–83%（`L:CHANGELOG.md:99`）。
- 去黑眼圈 `_circles`（`:650-686`）：眼下带向下方脸颊低频靠拢，只提亮不压暗（负向按 25% 作用，`:681`；上游文档写不压暗，`L:CHANGELOG.md:80`）。
- 美白 `_whiten`（`:689-696`）：类 screen 曲线（`1-(1-x)^(1+.55a)`）+ 轻去饱和，不动高光（`p>1` 保留），经皮肤掩膜延到脖子。
- 白牙 `_teeth`（`:699-723`）：内唇（`LIPS_INNER`）内明亮不偏红像素去黄提亮，舌头牙龈不受影响。
- 大眼+瘦脸 `_warp`（`:726-786`）：一次逆映射：虹膜（468/473）中心半径 1.1 眼宽平滑放大（`EYE_SCALE=.25`，`:79`）；下颌 8 点（`JAW`，`:67`；上游文档写六个点，`L:CHANGELOG.md:81`，与代码 8 元组口径差）向中轴 Gustafsson 局部平移（`SLIM_SHIFT=.05`，`:80`），权重归一化不折叠。

**许可三句。** ①修饰算法代码 MIT（`L:LICENSE:1-3`）。②权重：YuNet 随包 MIT 文本（`L:assets/YuNet-LICENSE.txt:1-3`，Shiqi Yu 2020；该文本来自训练代码仓；仓库内无权重侧单独声明文本，上游侧未核）；Face Mesh Apache-2.0（`L:assets/MediaPipe-LICENSE.txt:1-2`；`L:THIRD_PARTY.md:35` 注明 ONNX 转换为 naklitechie Apache-2.0、权重未改动）。③训练数据：两个模型均**没有单独声明**。测试人像 15 张 Wikimedia（CC BY/BY-SA 等）只用于测试、不分发不宣传（`L:CHANGELOG.md:110`）。

**平台依赖。** 检测+修饰全平台 CPU 可跑，无 GPU/NPU/系统版本额外门槛；该仓**未用 Apple Vision**（`lumen/` 全文 grep `VNDetect|CIDetector|Vision.framework` 零命中；`requirements-macos.txt` 仅 Cocoa/Metal PyObjC）。macOS 门槛 arm64 15+（`L:requirements-macos.txt:1-4`，Qt/ORT 要求，与人像链路无关）。

### 3.4 Lumen：portrait 预设（F7，半有）

内置 12 风格之一「柔和人像」（`PORTRAIT · 温润肤色`，`L:lumen/model.py:593-595`：曝光+.15、对比−6、质感−15、清晰度−8、橘色明度+12 等）是作用整图的调色预设。但**预设与复制调色明确不含人像 7 项设置**（`L:CHANGELOG.md:103`；`LOOK_KEYS` 9 项无 `portrait`，`L:lumen/model.py:399`）。许可：预设代码与参数 MIT，无权重、无训练数据。

### 3.5 Lumen：vibrance 肤色保护（F5 相近物）

自然饱和度对肤色（OkLCh 约 40–75°）作用减半：`Vibrance acts less on skin hues (orange, OkLCh ≈ 40–75°)`（`L:lumen/color.py:278-282` `vibrance_weights`，中心 58° 高斯半减）。纯算法，MIT。这是两仓唯一「肤色感知」调色逻辑。

### 3.6 否定性结论与双证据

**Alcedo：**

- N-A1 无脸/皮肤/头发/眼/牙/身体部位蒙版：(a) 任务枚举穷举——proto 仅 5 任务（`A:.../segmentation.proto:167-176`），host 仅 4 任务（`A:.../ai_mask_recipe.hpp:37`），单人切换仅按人物序号（`:85-90`），无部件概念；(b) `A:alcedo_studio/src/config/mask_icons/` 全列举 14 个图标（ai-subject/background/people/sky/point/box/path/level-1..3/radial/gradient/radial-add/gradient-add），无脸部部件图标。
- N-A2 无磨皮/肤色：(a) `alcedo_studio/src` + `rust` 全文 grep 修饰关键词零命中（§1.2）；(b) `BuiltinAdjustmentCatalog` 全列举 18 种全局调整（`A:alcedo_studio/src/edit/operators/models/adjustment_catalog.cpp:34-51`），无磨皮/肤色/美颜；QML 200 项内容 grep 实质命中仅 3 处良性（裁剪方向注释 `EditorGeometryPanel.qml:103`、模型来源 `AiModelsSettingsPanel.qml:328`、字体 mono/UI face `EditorVersionsPanel.qml:1209-1211`），无 Portrait/Beauty/Face/Whiten 功能面板。
- N-A3 无人脸感知曝光/美白：(a) `FaceDetect|face_detect|FaceBox|face_landmark|facial` 在 `src` 零命中（§1.2 同轮 grep）；(b) QML 实质命中仅 N-A2b 三处良性，无 Portrait/Beauty/Face/Whiten 面板。
- N-A4 无虚化/背景替换：(a) `bokeh|DepthMap|background_blur|BackgroundBlur` 在 `src`+`rust` 零命中（§1.2）；(b) 调整目录 18 项无虚化类（同 N-A2b）；`Background` 只是蒙版任务（recipe `:37`），发布说明只字未提虚化（0.3.4 `:15`）。
- N-A5 无 portrait 预设/风格：(a) 色调曲线预设全列举 8 种无 portrait（`A:.../tone_curve_presets.cpp:31-39`）；0.3.5 胶片（30 负片+5 反转，0.3.5 `:12`）与 0.3.7 `.alcpreset` 用户机制（0.3.7 `:19`）均为非人像物；(b) changelog 全目录 portrait grep 零命中（§1.2）。易混淆（均为方向/尺寸/厂商名/示例文本语义）：裁剪 portrait 方向逻辑（`A:alcedo_studio/src/app/editor_parameter_catalog.cpp:2016-2019`、`A:alcedo_studio/src/include/ui/edit_viewer/crop_geometry.hpp:120`、`A:alcedo_studio/src/ui/edit_viewer/crop_geometry.cpp:215-221`）、4:5 输出限（`A:alcedo_studio/src/ui/alcedo_main/album_backend/export_recipe_builder.cpp:316`）、QML 同注释（`A:.../qml/EditorGeometryPanel.qml:103`）、DCP 厂商风格名（`A:docs/roadmap/alcedo_studio/raw-processing/dcp_camera_profile_plan.md:69`、`A:.../dcp_profile_tone_curve_study.md:78`）、对话框 mock 文本 Warm Portrait（`A:docs/roadmap/alcedo_studio/edit/node_mask_editor/phase_nm10_adjustment_transfer_plan.md:89`，shipped 面 `src/config/` 内 portrait 零命中）。
- N-A6 无眼神光/面部识别：(a) `catchlight|VNDetectFace|FaceDetect|face_detect` 在 `src`+`rust` 零命中；(b) QML 实质命中仅 N-A2b 三处良性，无眼神光/面部面板。附带：图库语义搜索有 `portrait` 标签原型（`A:alcedo_studio/src/include/storage/store/semantic/semantic_label_config.hpp:96`），属检索非编辑；其 Jina CLIP 权重为 **CC-BY-NC-4.0 非商业**（`A:alcedo_studio/src/app/model_asset_catalog.cpp:51-52`），SigLIP2 Apache-2.0（`:53-54`）。

**Lumen：**

- N-L1 无细分蒙版：(a) `L:lumen/selection.py:80-83` + `LANDSCAPE` + `L:lumen/model.py:60-62` 三处种类全列举，均无细分项；(b) 全仓 grep `hair.?seg|body.?part|身体部位|skin.*mask|teeth.*mask`：模式命中仅 portrait.py 内部肤色掩膜，无蒙版实现；身体部位零命中；color.py 肤色权重（`L:lumen/color.py:278-282`，无 mask 一词）系另查相近物。
- N-L2 无人脸感知曝光：(a) `L:lumen/portrait.py:44` `KEYS` 7 项全列举无曝光；(b) `L:CHANGELOG.md:78-83` 人像章节枚举无曝光；辅证：自动曝光按整图小图测量（2.3.0「自动」章节），`auto_adjust.py` 无 face 命中（仅 surface 两处注释，`:9`/`:75`）。
- N-L3 无虚化/背景替换：(a) 跨 `lumen/` grep `bokeh|虚化|背景替换|relight|portrait.?mode` 零命中；近似物（另以 景深|前景|发丝 查得）仅三处：多张堆栈景深合成（`L:lumen/merge.py:14`）、前景/景深蒙版名（`L:lumen/ai_models.py:40`）、发丝边缘细化 tooltip（`L:lumen/auto_masks.py:67`），均非单图人像虚化；(b) `lumen/` 97 个 `.py` 全列举无 bokeh/portrait-mode/relight 模块。
- N-L4 无眼神光：(a) `catchlight|眼神光` 全仓零命中；(b) `portrait.py:44` + `portrait_panel.py:20-21` 功能/滑杆全列举无眼神光（虹膜仅作大眼 warp 中心，`portrait.py:63,502-503,738`）。

---

## 4. Comparison Against B14/B14A（对照我们已有的）

B14A 卡片现状（`W:phases/rust-core/PLAN-B.md:423-434`，A-19）：ort 后端 + lumen 四类（SkySeg/DeepLabV3/U2NetP）+ EfficientViT-SAM 点选 + `selection.py` 边缘细化转写 + 风光组/近景深度 + 皮肤面部 yakhyo + Vision 整人/RVM 可选。15 lane / 45 h。

| 本次发现 | 对照结论 |
|---|---|
| Lumen 7 项人像修饰（§3.3 算法面） | **完全没有**：B14/B14A 是蒙版波，修饰算法（磨皮/祛痘/美白/ warp）无立项。候选 P1/P2/P3 |
| Lumen 配方存 478 关键点 + per-face 窗口 + 分块精确语义（`needed`/`apply`） | **完全没有**：分辨率无关渲染 + 与 A-23 流式带正交的架构模式。候选 P3 |
| Lumen YuNet + FaceMesh 检测链 | **计划里有但做得不一样**：B14A 皮肤/面部走 Vision 地标 hull + yakhyo 像素级；Lumen 用 2.7 MB 双小模型给 478 点。Vision 在 macOS 上零权重覆盖检测，候选 P4（暂不收） |
| Lumen 柔和人像全局预设 | **完全没有**（B 期无预设波，属 C 期小件）。候选 P5 |
| Lumen vibrance 肤色保护 | **完全没有**（一行高斯权重）。候选 P6 |
| Alcedo People/Person 整人 + per-person toggles | **已有等价/更优**：B14A 已有 Vision person-instance + RVM 整人；toggles 是 UX 模式可抄。候选 P7（UX 注记，零权重） |
| Alcedo S3OD/自训 head/SAM2.1 | **已有不做结论维持**：B14A 不做面已列 Alcedo 自训 head/S3OD（MaSS13K 商用警告 + S3OD 沿革未声明）；本次核到 DINOv3 License + FLUX NC + MaSS13K 三条，维持不收。SAM2.1 与 EfficientViT-SAM 重复，且 Alcedo 主计划自认特写人像点/框失效（`A:docs/roadmap/alcedo_studio/edit/ai_segmentation_mask_master_plan.md:393`）。候选 P9（不收） |
| Alcedo/Lumen 权重分发与许可 UX | **计划里有但可加细**：B14A ⑧⑨ 已有 sha256 锁 + 首下 + 登记；两家的清单/收养/包内 licenses/商用警告是细节参照。候选 P8（零 lane） |
| 虚化/背景替换/眼神光/人脸感知曝光/身体部位细分 | **两家皆无**，无参考实现；身体部位维持 `W:phases/masks-research/SKIN-FACE-BODY.md` §3.3 不做结论。候选 P10（不收） |

---

## 5. Adoption List（借鉴清单）

### P1 Lumen 七修饰算法转写（收）

- 是什么：磨皮/祛痘/去黑眼圈/美白/白牙 5 颜色类 + 大眼/瘦脸 2 warp 类（§3.3）。
- 出处：`L:lumen/portrait.py:511-786`（MIT）。
- 怎样实现：Rust 转写进新修饰模块（L1 纯算法 + 管线接线）；供点走 Vision（B14A ⑥ hull 链已立项，地标→本算法掩膜）；颜色类先行、warp 类后；以 Lumen 同参数输出为 oracle（容差门，同 B14A ⑥对照体例）。
- 许可：①代码 MIT ②无权重 ③无训练数据。
- 依赖：B14A ⑥ Vision 地标链（供点）；OpenCV 算子改纯 Rust 栅格（B15/B16 选型 crate 复用）。
- 估算：4 lane × 3 h（颜色类 2 + warp 1 + 管线接线与 oracle 1）。
- 落波：**新开 PORTRAIT 波**（B14A 之后；B14A 是蒙版波，修饰另开一波最干净）。
- 风险：隐私全本机（零外发）；无权重下载；warp 在流式带上的支持域需与 A-23 调研对齐（瘦脸半径 0.34 脸宽，大眼 1.1 眼宽，均有界）。
- 推荐：**现在就收**。理由：两仓唯一人像修饰参考实现，MIT 纯算法零权重，7 项可独立验收（一项红不挡其余）。

### P2 皮肤掩膜算法（收）

- 是什么：脸椭圆+脖子 − 五官保护区 × 自学肤色似然 − 镜框线（`L:lumen/portrait.py:365-496`）。
- 出处/实现/许可/依赖：同 P1（MIT 纯算法；供点 Vision；转写 L1）。
- 估算：1 lane × 3 h（含与 yakhyo 皮肤类的对照：掩膜法 vs 19 类分割，同一测试图比优劣）。
- 落波：PORTRAIT 波（P1 前置）。
- 风险：全本机；Vision 76 点 vs FaceMesh 478 点的掩膜精度差由对照 lane 实测回答，不预设结论。
- 推荐：**现在就收**。理由：P1 的地基；即使 yakhyo 在 B14A 落地，掩膜法仍是零权重回落腿。

### P3 配方存关键点 + per-face 窗口 + 分块精确语义（收）

- 是什么：检测点列归一化存配方（渲染/导出零模型）；每脸独立窗口；`needed`/`apply` 分块与整图一致（`L:lumen/portrait.py:95-123,236-280`；`L:lumen/engine.py:1202-1212`；格式 `L:lumen/model.py:28-30`）。
- 出处/许可：Lumen MIT；无权重。
- 怎样实现：PORTRAIT 波设计约束——history 编解码加 portrait 段（归一化点列 + 7 设置），渲染作业按脸窗扩展 ROI。
- 估算：0（P1 接线 lane 内含）。
- 落波：PORTRAIT 波。
- 风险：点列随快照膨胀（478 点 × 24 脸 × 2 浮点 ≈ 23K 浮点/图，可接受）；与 A-23 流式带：脸窗天然是 ROI 扩展，方向一致。
- 推荐：**现在就收**。理由：零成本架构模式，且提前 answered A-23 的「需要看整图的模块怎样对待」中的一类（有界窗口类）。

### P4 YuNet + FaceMesh 检测权重（暂不收）

- 是什么：2.7 MB 双小模型给 478 点（`L:assets/culling-assets.json`）。
- 许可：①代码 MIT ②权重：YuNet 仓库内无权重侧单独声明文本（随包 MIT 文本来自训练代码仓），上游侧未核；FaceMesh Apache-2.0（转换未改权重）③训练数据：两者均**没有单独声明**。
- 依赖：ort（B14A 已有）；但 YuNet 后处理（NMS/框解析）Lumen 走 OpenCV DNN，Rust 侧需自写。
- 估算（若收）：2 lane × 3 h（ort 接线 + YuNet 后处理自写与对照）。
- 落波：PORTRAIT 波可选腿。
- 风险：权重许可弱于 yakhyo（已接受）但强于 SCHP（已拒绝）；478 点 vs Vision 76 点的边际收益未实测。
- 推荐：**暂不收**。理由：macOS 上 Vision 零权重覆盖检测+地标（B14A ⑥已立项）；非 macOS 不在 scope（A-20）；等 P2 对照 lane 证明 76 点不够再收，不预付。

### P5 柔和人像全局预设（收）

- 是什么：整图调色参数组（`L:lumen/model.py:593-595`）。
- 许可：MIT 参数，无权重、无数据。依赖：预设/look 落盘面。估算：顺带 0（有预设波时抄半小时）。
- 落波：管预设的那一波（B 期若无则 C 期小件；**不含**人像 7 设置，Lumen 自身亦排除，`L:CHANGELOG.md:103`）。
- 风险：零。推荐：**现在就收**（顺带）。

### P6 Vibrance 肤色保护（收）

- 是什么：OkLCh 40–75° 高斯半减（`L:lumen/color.py:278-282`）。
- 许可：MIT 一行算法。依赖：vibrance 模块。估算：顺带 0。落波：管 vibrance 的色彩模块波。
- 风险：观感微调，需 oracle 钉死（前后对比各一例）。推荐：**现在就收**（顺带）。

### P7 Alcedo per-person 多人 toggles UX（收）

- 是什么：People 列表逐个加入/移除单人（`A:.../ai_mask_recipe.hpp:85-90` + 面板 `A:.../EditorAiMaskPanel.qml:6-12`）。
- 许可：UX 模式，GPL 代码不抄（行为克隆）。依赖：B14A person-instance 腿。估算：0（B14A 设计注记）。
- 落波：B14A（蒙版面板/命令面设计时照做）。
- 风险：零（无权重）。推荐：**现在就收**（注记）。

### P8 权重分发与许可 UX 纪律（收）

- 是什么：内容命名 + 清单 pin + sha256 验 + 旧版收养（Lumen，`L:lumen/ai_models.py:31,38-44`）+ 包内 `licenses/` + `NOTICE.txt` + 商用警告（Alcedo，`A:THIRD_PARTY_NOTICE.txt:200-202` + 0.3.4 `:6`）。
- 许可：流程纪律，无代码许可问题。估算：0。落波：B14A ⑧⑨（首下与登记面细化）。
- 风险：零。推荐：**现在就收**（B14A 任务书加三行：包内 licenses、商用警告面、收养旧版）。

### P9 Alcedo S3OD/自训 head/SAM2.1（不收）

- 维持 B14A 不做面。理由：S3OD 链 DINOv3 License + FLUX NC 上游 + Alcedo 不表态传导（`A:.../ai_mask_model_set_v1_NOTICE.txt:50-57`）；sky head MaSS13K 许可不明（`:83-89`）；SAM2.1 与 EfficientViT-SAM 重复且 Alcedo 自认特写失效（`A:docs/roadmap/alcedo_studio/edit/ai_segmentation_mask_master_plan.md:393`）；体积 219–271 MB（subject）远大于现有选项。

### P10 虚化/背景替换/眼神光/人脸感知曝光/身体部位细分（不收）

- 理由：两家皆无参考实现（N-A3/N-A4/N-A6/N-L2/N-L3/N-L4）；身体部位维持 SKIN-FACE-BODY §3.3 四理由不做。若用户坚持任一项，需另开自研/外部权重调研（非本次借鉴）。

---

## 6. Estimates（估算合计）

| 项 | lane | 小时 | 落波 |
|---|---|---|---|
| PORTRAIT 波：P1 修饰 4 + P2 掩膜 1 + 面板/命令面 1（`mask.generate` 扩展或新命令 + A3 面板描述） | 6 | 18 | 新波，B14A 之后 |
| P3/P5/P6/P7/P8（注记与顺带） | 0 | 0 | B14A / 对应波内 |
| P4（暂不收，若收） | 2 | 6 | PORTRAIT 可选腿 |
| **现在就收合计** | **6** | **18** | B14A（15/45）不动 |

## 7. Risks（风险）

- 隐私：P1–P8 全本机（检测走 Vision/ort 本地，修饰纯 CPU），零外发；与 Lumen「随包离线」同构。
- 权重下载：现在就收项**零新增权重**（P4 暂不收）；B14A 权重清单不变。
- 体积：PORTRAIT 波零权重体积；配方膨胀约 23K 浮点/图上限（478 点 × 24 脸），可接受。
- 许可：P1–P3/P5/P6 为 MIT 纯算法转写（署名 + LICENSE 文本，`NOTICE` 登记一条）；P4 的 YuNet 权重仓内无单独文本（上游未核）+ 训练数据无声明是暂不收的主因之一。
- 精度：Vision 76 点 vs FaceMesh 478 点的掩膜/修饰差距未实测——P2 对照 lane 回答，不预设结论；若 76 点不够，P4 是已备好的回退。
- 范围：PORTRAIT 波只做 Lumen 同款 7 项 + 掩膜；虚化/眼神光/身体部位明确不在内（P10）。

## 8. Decisions for User（待用户定的事，4 件）

1. **开新波 PORTRAIT 吗（6 lane / 18 h，B14A 之后）？** 推荐：开。内容 = P1 七修饰 + P2 皮肤掩膜 + P3 配方/分块语义 + 面板/命令面；Vision 供点，零新权重。若不开：P1–P3 退回 C 期，人像修饰无排期。
2. **P4（YuNet + FaceMesh 权重）暂不收，可以吗？** 推荐：暂不收。理由：Vision 零权重覆盖 + 非 macOS 不在 scope（A-20）+ YuNet 权重仓内无单独文本（上游未核）+ 训练数据无声明；P2 对照若证 76 点不够再收。若收：+2 lane / 6 h 进 PORTRAIT 可选腿。
3. **P5（柔和人像预设）+ P6（vibrance 肤色保护）顺带收吗？** 推荐：收。零 lane，落对应波；oracle 各钉一例。
4. **P7（per-person toggles UX）+ P8（分发许可纪律）进 B14A 设计注记吗？** 推荐：收。零 lane，B14A 任务书加注；B14A 估时（15/45）不动。

---

## 9. Revision Notes（修订记录）

- 2026-11-27 初稿。独立复审（`review.log`，`5 error + 17 minor`，结论全成立）回注：E1 QML 三处良性命中改述（N-A2b/N-A3b/N-A6b）/ E2 97 个 py（自查已先改）/ E3 N-L3a 模式与命中对齐 / E4 :128 附带提及 / E5 DemosaicNet 随仓权重两份；M1 :99（自查已先改）/ M2 :36 / M3 :84-87 / M4 DINOv3-LICENSE:28 / M5 surface 两处 / M6 N-L1b 改述 / M7 YuNet 上游未核（§3.3/P4/§7/待定2）/ M8 易混淆清单补全+DCP 引用 / M9–M14 补引用（MODEL/compute/model/CHANGELOG/requirements）/ M15 负向 25% / M16 六点口径差 / M17（自查已先改）。以上不改任一推荐结论。
