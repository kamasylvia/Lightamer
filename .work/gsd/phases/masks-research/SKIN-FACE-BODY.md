# Skin/Face/Body: Vision 基线与开源模型调研

> 日期 2026-11-26。只读 lane，不写产品代码，不下载权重。上游问题见 `RESEARCH.md` Q5（皮肤/面部/身体在参考项目里无可用实现）与 §7 第 4 件待定事项。
> 全文中文，标识符英文。实测数字标来源；没查到的写「没查到」；推断标「推断」。
> 头文件证据指本机 SDK `MacOSX27.2.sdk`（`xcrun --show-sdk-path` 实测路径下 `Vision.framework`）。

---

## §0 一页纸

**皮肤**：Vision 无任何直接给皮肤的能力；旧 Swift 版用「人脸地标 hull − 五官保护区 ⊗ 人体 matte」的几何链拼过一张粗糙皮肤蒙版（已交付、有面板，但只是多边形级，且侧脸拒收）。要像素级皮肤，唯一对得上后端的候选是 BiSeNet 系 face parsing：`yakhyo/face-parsing` 的 `resnet18.onnx`（MIT 项目，权重无单独许可声明，见 §2.1；ONNX 现成 50.7 MB、19 类含 skin/neck/hair/lip、2026 年仍在维护）。代价是训练数据 CelebAMask-HQ 为 non-commercial 协议（我们是非商业免费开源，风险低但要拍板）。

**面部**：Vision 地标（76 点星座：faceContour/eyes/brows/nose/lips/pupils）+ roll/yaw/pitch，拼脸轮廓蒙版够用，旧版已验证整条链；精度止于多边形级，无像素级唇/眼分割。像素级面部与皮肤是同一个模型的同一输出（yakhyo 19 类），引入即顺带解决。结论：Vision 先行零成本，模型与皮肤同批。

**身体**：Vision 的 person 是整人二值 matte（分不清手臂/腿/衣服），person-instance 能区分多人；姿态/手部是骨骼点（19/21 关节点），转蒙版只能自研膨胀，粗糙。身体部位细分（arm/leg/衣服）只有 SCHP 类人体解析能给，但它三门皆弱（权重许可未声明、LIP 数据 non-commercial、无官方 ONNX 且导出要改代码、体积没查到）；整人像素级 alpha 则有 RVM（代码 GPL-3.0、官方 ONNX fp16 仅 7.2 MB、官方 CoreML；全身/单/多人 README 未明写，印象待补源）。结论：整人用 Vision，alpha 引入 RVM，部位细分先不做。

**建议表**：

| 类别 | 靠什么 | 引入模型 | 体积代价 | 速度代价（公开数） | 建议排期 |
|---|---|---|---|---|---|
| 皮肤 | yakhyo resnet18.onnx（19 类取 skin/neck） | 是 | +50.7 MB（运行时下载则包体积零增） | Pi 5 CPU ~250 ms/帧（LiteRT 镜像实测）；ANE 数没查到 | B-AIM 内引入；Vision 几何链作回落 |
| 面部 | Vision 地标 hull 先行；像素级与皮肤同一模型 | 随皮肤顺带，不单独引 | 0（复用皮肤模型） | layer 级毫秒级（旧版 bench：见 §1.6） | Vision 先行；像素级随皮肤同批 |
| 身体 | Vision person/instance 先行；alpha 引 RVM；部位细分不做 | RVM mobilenetv3 fp16（可选） | +7.2 MB | RVM 只有 GPU 公开数（GTX 1080Ti HD 104 FPS）；CPU/ANE 数没查到 | Vision 先行；RVM 进 B-AIM 可选；SCHP 先不做 |

---

## §1 Vision 能给什么（头文件 + 文档逐项）

本机 SDK：`MacOSX27.2.sdk/System/Library/Frameworks/Vision.framework`（Headers + `Modules/Vision.swiftmodule/arm64e-apple-macos.swiftinterface`，3535 行）。我们最低版本 macOS 27，以下可用性全命中。

### 1.1 人物分割：`VNGeneratePersonSegmentationRequest` / `GeneratePersonSegmentationRequest`

- **输出**：单人/多人二值 matte。ObjC 腿 `results: [VNPixelBufferObservation]`（`VNGeneratePersonSegmentationRequest.h:58`）；Swift 腿 `Result = PixelBufferObservation`（swiftinterface `:1802`）。输出像素格式可选 OneComponent32Float/16Half/8（`:56` 注释，默认 8-bit）。
- **质量三档**（`:16-21` 头注释逐字语义）：`accurate`（默认）= balanced 输出 + matting 精修；`balanced` = 高精度分割；`fast` = 低精度、可跑在带神经网络引擎设备上的流式档。
- **最大分辨率**：官方未说明。旧版 bench 未单独钉 personSeg 输出尺寸；旧 Swift 版消费端一律按「模型分辨率 → bake 时上采样」处理（`AIMaskService.swift:423-425` 注释），佐证输出低于源图。
- **最低版本**：macOS 12.0（`:33` `API_AVAILABLE(macos(12.0)...）`；Swift  struct 版 macOS 15+。
- **处理器**：CoreML 后端，默认 ANE 优先（07-RESEARCH §5 口径；`fast` 档头注释点名 neural engine）。注意：该请求**无 `supportedComputeStageDevices` 查询面**（swiftinterface `:1802` 段只有 `setComputeDevice`，无 supported 面——旧版 `AIMaskService.swift:450-463` `refusePin` 把它和地标请求列为 legacy，pin 一律 typed 拒绝）。
- **对「身体」够不够用**：整人抠人够用；身体部位（手臂/腿/衣服/皮肤）完全不给——这是它与 §2 人体解析模型的分界线。
- 文档：https://developer.apple.com/documentation/vision/vngeneratepersonsegmentationrequest （200 已验）。

### 1.2 人脸：检测框 + 关键点

- **检测框**：`VNDetectFaceRectanglesRequest`（macOS 10.13+，`VNDetectFaceRectanglesRequest.h` 同族；Swift `DetectFaceRectanglesRequest`）→ `FaceObservation`（boundingBox + roll/yaw/pitch + confidence + captureQuality，swiftinterface `:2193-2210`）。
- **关键点**：`VNDetectFaceLandmarksRequest` → `VNFaceLandmarks2D`，13 个 region：allPoints/faceContour/leftEye/rightEye/leftEyebrow/rightEyebrow/nose/noseCrest/medianLine/outerLips/innerLips/leftPupil/rightPupil（`VNFaceLandmarks.h:120-182`）。星座 65 点（rev1-3）/ 76 点（rev3+，`VNDetectFaceLandmarksRequest.h:17-23`）；Swift `DetectFaceLandmarksRequest.Revision` = rev3 + rev4（macOS 27 新增，swiftinterface `:847-850`）。
- **拼「面部」蒙版**：能。旧版整条链已交付：faceContour hull + 额头带闭合 −（眼/眉/唇/鼻孔保护区）→ 多脸 union ⊗ person matte（`LightamerIOP/Sources/SkinSmooth/SkinRegionLocator.swift:6-14` 链式注释；纯几何 CPU 光栅化 `:263-423`；Vision 只供点列，经 `FaceLandmarkProviding` 缝注入 `:430-481`）。精度 = 多边形级（点列 hull），非像素级；局限 = |yaw|>45° 的脸 typed 拒收（`:31-34` yaw 门）、无唇/眼白像素分割、额头是外推带非实测。
- 文档：https://developer.apple.com/documentation/vision/vndetectfacelandmarksrequest （200 已验）。

### 1.3 人体姿态 / 手部姿态

- `DetectHumanBodyPoseRequest` → `HumanBodyPoseObservation`，`JointName` 19 关节点（nose/neck/双耳眼/肩/肘/腕/root/髋/膝/踝，swiftinterface `:3151` 起枚举逐字数得 19 个）+ 6 组（face/torso/leftArm/rightArm/leftLeg/rightLeg）。
- `DetectHumanHandPoseRequest` → `HumanHandPoseObservation`，单手 21 关节点（wrist + 五指 ×4，`:782` 起枚举逐字数得 21 个）+ chirality（左右手）。
- **转身体蒙版**：只能走「关节点 → 自研膨胀/hull」拼粗糙蒙版，无官方转法；旧 Swift 版未消费这两个请求（全仓 grep 零命中）。结论：姿态点对「身体蒙版」是弱信号，不建议立项。
- 文档：https://developer.apple.com/documentation/vision/vndetecthumanbodyposerequest 、https://developer.apple.com/documentation/vision/vndetecthumanhandposerequest （200 已验）。

### 1.4 皮肤：Vision 无直接或间接能力

- 全框架无 skin/tone 语义分割请求（Headers 53 个头文件名逐一过目，无皮肤项；`CISmoothLinearGradientSkinTone` 类 API 不存在——07-RESEARCH §2 已查证，Core Image 无皮肤滤镜）。
- 间接只有 §1.2 的地标 hull 链（旧版 AI-05），本质是几何近似而非皮肤语义。

### 1.5 前景实例与点选：`GenerateForegroundInstanceMaskRequest` / `GeneratePersonInstanceMaskRequest` / `GenerateIterativeSegmentationRequest`

- 前景实例（macOS 14+）：class-agnostic 多实例 label 图 + `generateScaledMask` 高清腿（`VNObservation.h:789` / swiftinterface `:2338`）。与三类的关系：人是它的子集，不分部位。
- 人体实例（macOS 14+）：仅人的 per-instance mask（`VNGeneratePersonInstanceMaskRequest.h:19-25`），多人像区分就靠它；有完整 compute-device 面（旧版 `AIMaskService.swift:514-530`，main=[ane,gpu,cpu]）。
- 点选分割（macOS 27+，WWDC session 号待核）：seed 点/盒/涂鸦 + qualityLevel 三档 + DownloadableAssetsRequest（首次联网下模型）。与三类的关系：**点人脸即得像素级面部蒙版、点手臂即得身体局部蒙版**——是「Vision 先行」方案里精度最高的兜底，但需一次交互且首次联网。
- 三者都不给皮肤语义。

### 1.6 旧 Swift 版用过哪些、效果怎样

| 能力 | 旧版消费点（文件:行号） | 效果（有据） |
|---|---|---|
| 前景实例 layer A | `LightamerCore/Sources/AI/AIMaskService.swift:150-190` | warm 14-16 ms；cold 最高 5.5 s（07-1-DECISIONS D-07-1-T1-3 bench）。macOS 27.0b `generateScaledMask` 双损坏（subset 语义 + 几何偏移 +3/16），全消费面切 label 合成硬 0/1 腿（`AIMaskService.swift:176-183`） |
| 点选 layer B | 同上 `:285-362` | accurate warm 85-126 ms（25-102MP 全档）；balanced/accurate 直产解码帧分辨率（102MP 11648×8736），仅 fast（256×256）需上采样（D-07-1-T4-2）。测试宿主内恒 notReady 跳过（T4 备注） |
| person 分割 | 同上 `:426-445` | 作皮肤链背景排除；单跑 bench 数没查到（bench 矩阵未列该项） |
| 人体实例 | 同上 `:478-566` + M6-4 | revision1 钉死（`:506-512`）；素场幻觉登记：纯白/灰128 图报 1 实例（ARCHIVE M6-4 D-06） |
| 人脸地标 | `SkinRegionLocator.swift:427-481` provider、`EyeClosureAnalyzer.swift:87-99`、`CullingToolset.swift:1323` | 皮肤 hull 链交付（面板「定位皮肤」`SkinSmoothPanelView.swift:105`）；闭眼检测交付（LUMEN-A）；MCP get_face_regions 直调交付 |
| 姿态/手部 | 无 | 全仓 grep 零消费 |

---

## §2 候选模型（逐个事实）

6 个候选：BiSeNet 上游（zllrunning）、BiSeNet-ONNX 现成版（yakhyo）、MediaPipe Selfie Multiclass、SCHP、RVM、MODNet。权重一律未下载；字节数来自 HTTP HEAD（`content-length`）与页面标注。

### 2.1 总表（行=候选，列=事实）

| 候选 | 代码许可 | 权重许可 | 训练数据许可 | 权重体积 | ONNX | 输入/输出/类名 | 公开速度 | 苹果芯片记录 | 质量口碑 | 维护/star/末提交 |
|---|---|---|---|---|---|---|---|---|---|---|
| zllrunning BiSeNet | MIT（`LICENSE` 文件，GitHub 标注 MIT） | **未声明**（README 只给 Google Drive 链接，无许可字样） | CelebAMask-HQ：non-commercial research only（官网 Agreement 第 1 段；第 2 段另含 derived data + commercial 条款，权重是否属 derived data 未明说，见 §3.1） | 没查到（Drive 直链，HEAD 不可达） | 无官方；纯 CNN，torch.onnx 可导（推断：社区多有导出实践，但本 lane 未核任一具体版本） | 512×512 / 19 类 logits：background, skin, l/r_brow, l/r_eye, eyeglass, l/r_ear, earring, nose, mouth, u/l_lip, neck, necklace, cloth, hair, hat（HF 镜像模型卡逐字） | Pi 5 CPU ~249 ms、Pixel 8a GPU ~22-53 ms（HF 镜像 `litert-community/BiSeNet-Face-Parsing-LiteRT` 模型卡 benchmark_model 实测）；Pixel 8a CPU 数未亲证（页内 "229" 命中系归一化 std 0.229） | 没查到具体记录 | 没查到针对亚洲人/侧脸/暗光的专项报告（推断：CelebAMask-HQ 以正脸名人为主，侧脸/遮挡降质是该类模型通病） | 停更；star 没查到（GitHub API 限流）；末提交 2019-05-18（commits atom） |
| yakhyo BiSeNet | MIT（`LICENSE` 文件 2024；README License 节 "project MIT"） | 随项目 MIT 发布（README 未单列权重许可；权重挂 GitHub Release `weights`） | 同上（CelebAMask-HQ，README Dataset 节明示） | **resnet18.onnx 53,205,364 B（≈50.7 MB）**、resnet34.onnx ≈89 MB、resnet18.pt ≈52.8 MB（HEAD 实测；README 标称 ~43 MB/~82 MB 为约数） | **官方现成**（Release 直链 + 仓内 `onnx_export.py`，README Usage 节） | 512×512 / 19 类（同上类表，`--num-classes 19` 缺省） | 同 zllrunning 行（同架构；本仓无独立测速） | 没查到（ONNX 纯 CNN，ort CoreML EP 可跑属推断） | 同上 | **活跃**；star 没查到（API 限流）；末提交 2026-10-26（atom；Fix/security updates #21） |
| MediaPipe Selfie Multiclass | Apache-2.0（google-ai-edge/mediapipe 仓） | Apache-2.0（上游模型卡 PDF 声明；HF `litert-community` 镜像页 license 栏 apache-2.0） | 未公开说明（模型卡未列训练集许可） | 16.37 MB（`selfie_multiclass_256x256.tflite` FP32，HF 页文件表 + SHA） | **无，且难**：tflite 格式；ort 不读 tflite；tflite→ONNX 工具（tflite2onnx）算子覆盖有限，MediaPipe 系 tflite 含自定义算子，社区转换多报 unsupported ops（证据：`google/mediapipe#3238`（face_landmark）、`onnx/tensorflow-onnx#2024`（TFL 自定义算子）——同系类比，非 selfie_multiclass 本体） | 256×256 / 6 类：background, hair, body-skin, face-skin, clothes, others（HF 页 I/O 表） | Pixel 6 CPU 217.76 ms / GPU 71.24 ms（官方 Image Segmenter 文档 benchmarks，HF 页转引） | iOS sample 可跑（官方 mediapipe-samples 有 iOS 例）；Mac/ort 路径没查到 | **有公平性实测**：mIoU 77.23%（918 图/1902 人）；Monk 肤色 1-10 档 68.25%（9+10 档）~79.18%（6 档）；男女 ~77.1/77.3%（2023-05 上游模型卡） | 上游 Google 持续维护；权重 2023-04-26（GCS Last-Modified）；star 不适用（模型页） |
| SCHP（GoGoDuck912） | MIT（`LICENSE` 文件，Copyright 2020 Peike Li，curl 实读） | **未声明**（README 只给 Drive 链接 + 精度数，无许可字样） | LIP：non-commercial（sysu-hcp 官网 License 栏："freely available ... for non-commercial purposes"） | 没查到（Drive 直链） | **无官方；导出要改代码**：`torch.onnx.export` 报 `aten::adaptive_avg_pool2d` 不支持，作者回复须换固定核 avg pool（`#6` issue，2019-12，closed） | LIP 档 473×473（`simple_extractor.py:30`）、ATR/Pascal 档 512×512；LIP 20 类：Background/Hat/Hair/Glove/Sunglasses/Upper-clothes/Dress/Coat/Socks/Pants/Jumpsuits/Scarf/Skirt/**Face**/**Left-arm**/**Right-arm**/**Left-leg**/**Right-leg**/L/R-shoe（README 逐字）；mIoU 59.36% | 没查到 | 没查到 | 没查到专项报告 | 停更；**1.3k star**（仓库页 About 栏实读）；末提交 2021-04-28（atom，README） |
| RVM（PeterL1n） | **GPL-3.0**（`LICENSE` 文件全文；README News "2021-09-16 Code re-released under GPL-3.0"） | **未单独声明**（README 只说 code 转 GPL；权重随 v1.0.0 Release 发布——按同仓 GPL 理解属推断） | 没查到（README/training 文档未给数据许可说明） | **mobilenetv3 fp32 onnx 14,975,696 B（≈14.3 MB）**、**fp16 onnx 7,503,483 B（≈7.2 MB）**、pth ≈14.5 MB（HEAD 实测） | **官方现成**（Release 4 个 onnx + 导出器 `onnx` 分支，opset 12，ORT CPU/CUDA 测过——README Download 表） | 任意分辨率（视频 matting；`downsample_ratio` 超参）/ 人像 alpha + foreground；全身/单/多人 README 未明写（showreel 印象，待补源） | 只有 GPU 公开数：GTX 1080Ti HD 104 FPS / 4K 74 FPS（README Speed 表，batch 1）；CPU/ANE 数没查到 | **官方 CoreML**（Release 4 个 .mlmodel，iOS 13+，README Download 表）——Apple 芯直接证据 | 没查到专项报告（showreel + 第三方移植多，口碑好但无亚洲人/暗光专项数） | 停更（2023 后仅社区 PR）；star 没查到（API 限流）；末提交 2023-03-13（atom） |
| MODNet（ZHKKKe） | Apache-2.0（`LICENSE` 文件 201 行；GitHub 标注） | **Apache-2.0（明示）**：README License 节 "The code, models, and demos ... are released under Apache-2.0"——6 个候选里唯一权重许可写明的 | 没查到（README 只说 "trained on the datasets mentioned in our paper"） | 没查到（文件名 `modnet_photographic_portrait_matting.ckpt` 系公开知识，Drive 链接未亲证）；在线 demo 版（未发布）7M（README Online Application 节，与发布权重无关） | 社区版（仓内 `onnx/` 目录 + Colab，非官方维护——README Community 节） | 短边对齐 512（`demo/image_matting/colab/inference.py:35` `ref_size = 512` 实读）/ 人像 alpha；**半身人像向**（PPM benchmark  portrait） | 定性 "2K on common PC/Mobile Fast"（README，无毫秒数） | 没查到 | 没查到专项报告 | 停更；star 没查到（API 限流）；末提交 2022-07-29（atom） |

### 2.2 许可证据路径（T-M5 体例：文件与行号）

- zllrunning：代码 `github.com/zllrunning/face-parsing.PyTorch/blob/master/LICENSE`（MIT）；权重 Drive 链接在 `README.md` Training 节（无许可字样）；数据 https://mmlab.ie.cuhk.edu.hk/projects/CelebA/CelebAMask_HQ.html （Agreement 三段）；HF 镜像模型卡 https://huggingface.co/litert-community/BiSeNet-Face-Parsing-LiteRT （类表与测速来源）。
- yakhyo：`LICENSE`（MIT，curl 头 3 行）；`README.md:301-303`（"project MIT"）；Release `.../releases/download/weights/resnet18.onnx`。
- MediaPipe：权重页 https://huggingface.co/litert-community/MediaPipe-ImageSegmenter-Selfie-Multiclass （license 栏 + 文件表 + 基准表 + 公平性节）；官方文档 https://developers.google.com/edge/mediapipe/solutions/vision/image_segmenter 。
- SCHP：`LICENSE`（MIT，curl 实读）；`README.md` 权重 Drive 段（无许可字样）+ LIP 20 类表；ONNX 证据 `.../issues/6`（2019-12）；数据 https://www.sysu-hcp.net/resources/datasets/index.html （License 栏）。
- RVM：`LICENSE`（GPL-3.0 全文，实读前 300 行）；`README.md` News 节（转 GPL 日期）+ Download 表 + Speed 表；Release `.../releases/download/v1.0.0/rvm_mobilenetv3_fp16.onnx`。
- MODNet：`LICENSE`（Apache-2.0，search 页 `:201` 行）；`README.md` License 节（code+models+demos Apache-2.0）+ Community 节（ONNX 社区版）；`demo/image_matting/colab/inference.py:35`（ref_size 512）。

---

## §3 三类结论

### 3.1 皮肤：引入 yakhyo resnet18.onnx，Vision 几何链作回落

- **只靠 Vision**：地标 hull 链（旧版已交付）能给「脸部大致区域」，非真皮肤语义：额头外推、脖子/手臂皮肤全无、侧脸拒收。磨皮类「压斑点不压毛孔」场景下精度不够。
- **最值得引入**：`yakhyo/face-parsing` resnet18.onnx。理由四条：① 19 类直出 skin/neck/hair/lip，正好是皮肤+唇+发；② ONNX 现成，与 Q3 定的 ort 后端零摩擦；③ MIT 且 2026 年仍在维护（6 候选唯一活跃）；④ 50.7 MB 可接受（运行时下载则包体积零增）。
- **许可**：代码 MIT ✓；权重随 MIT 项目发布（无单独权重许可文件；按 MIT 理解属推断，风险低）；训练数据 CelebAMask-HQ non-commercial——协议未明确提及权重，"derived data" 留有解释空间，非商业使用下触发风险低（解读非事实），且我们是非商业免费开源。结论：可随包/随下载分发，但 §4 第 1 件请用户拍板。
- **代价**：体积 50.7 MB；速度只有手机/Pi 级 CPU 数（~230-250 ms/帧），ANE 数没查到，需 B-AIM 选型 lane 实测 ort CoreML EP；维护：跟随上游（活跃，风险低）。
- **排期**：B-AIM 内引入；Vision hull 链保留作无模型回落（旧代码可转写）。

### 3.2 面部：Vision 先行，像素级随皮肤同批

- **只靠 Vision**：检测框 + 76 点地标 + yaw 门，脸轮廓蒙版够用（旧版整链交付）；点选分割（layer B）一点人脸即得像素级面部蒙版，是精度最高的 Vision 内兜底。做不了的是无交互像素级唇/眼/眉分割。
- **最值得引入**：不单独引——yakhyo 19 类已含全脸部件（brow/eye/nose/mouth/lip），皮肤引入即顺带解决面部。若皮肤被否，面部退回 Vision 地标 + 点选兜底。
- **代价**：复用皮肤模型，边际 0。
- **排期**：Vision 先行（转写旧链）；像素级随皮肤同批，不单独立项。

### 3.3 身体：Vision 整人先行 + RVM alpha 可选，部位细分先不做

- **只靠 Vision**：person 整人 matte + person-instance 多人区分，抠人够用；姿态/手部骨骼点转蒙版粗糙，不立项。做不了身体部位（手臂/腿/衣服）与发丝级 alpha。
- **最值得引入（alpha）**：RVM `rvm_mobilenetv3_fp16.onnx`。理由：① 代码 GPL-3.0 与我们同许可（6 候选唯一）；② 官方 ONNX + 官方 CoreML，ort 后端与 dt-apple 两侧都通；③ 7.2 MB 最小；④ 任意分辨率（全身/单/多人 README 未明写，印象待补源）。MODNet 作备选（权重 Apache 明示最干净，但半身向 + 体积没查到 + ONNX 社区版）。
- **部位细分（SCHP）先不做**：权重许可未声明 + LIP non-commercial + 无官方 ONNX（导出要改网络代码）+ 体积/速度/苹果芯片记录全没查到 + 2021 年停更。五门四弱，不值得在 B-AIM 期啃。
- **代价**：RVM +7.2 MB；速度只有 NVIDIA GPU 公开数，CPU/ANE 需实测；单帧用法 = recurrent 状态置空首帧（README 推理例写法，用法上有据）。
- **排期**：Vision 先行；RVM 进 B-AIM 可选件（与 person 档同一后端，复制成本低）；SCHP 明确先不做。

---

## §4 需要用户定的事（3 件）

1. **皮肤/面部引入 yakhyo 权重，接受 CelebAMask-HQ non-commercial 背景吗？**
   推荐：接受。理由：协议未明确提及权重，"derived data" 留有解释空间，非商业使用下触发风险低（解读非事实）；我们是非商业免费开源；MIT 项目 + 活跃维护 + ONNX 现成是 6 候选最优。若不接受：皮肤退回 Vision hull 链（多边形级），面部像素级一并落空。
2. **权重随包分发还是运行时下载（yakhyo 50.7 MB + RVM 7.2 MB）？**
   推荐：运行时下载。理由：dt（darktable-ai 仓 + releases-index）与 Alcedo（model-set 包）全是运行时下载先例；随包 +57 MB 且 GPL 权重的 Corresponding Source 义务更重。若随包：包体积 +57 MB，LICENSE-AUDIT 登记两条。
3. **身体部位细分（手臂/腿/衣服，SCHP 类）明确先不做吗？**
   推荐：先不做。理由：许可/体积/ONNX/维护四门皆弱，B-AIM 期啃它会拖住整波；整人（Vision）+ alpha（RVM）已覆盖调色蒙版 90% 用法（推断）。若要做：先开权重许可澄清（联系作者）+ ONNX 导出 spike，两 lane 起。

---

## §5 修订记录

2026-11-26 按独立评审（`skin-review.log`，`PASS / 0 error + 14 minor`）回注：m1 CelebAMask-HQ 措辞（§2.1 补 derived data 注、§3.1、§4-1 三处）改为"协议未明确提及权重，derived data 留解释空间，非商业下风险低（解读）"；m2 §0 标"权重无单独许可声明"；m3 Headers 53；m4 质量注释 `:16-21`；m5 65/76 点补 `VNDetectFaceLandmarksRequest.h`；m6 姿态 6 组真名；m7 generateScaledMask 换 `VNObservation.h:789`；m8 末提交安全更新；m9 全身/多人三处（§0、§2.1、§3.3）改"README 未明写"；m10 MODNet 权重托管未亲证；m11 补 HF 镜像 URL（§2.1 与 §2.2 两处）；m12 Pixel 8a CPU 数未亲证；m13 两 issue 标同系类比；m14 WWDC session 号待核。以上不改 §3/§4 任一结论（评审结论）。
