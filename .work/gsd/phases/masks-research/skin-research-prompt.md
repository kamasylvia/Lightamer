# 调研 lane（omp，只读）：皮肤、面部、身体三类蒙版的外部来源

## 背景

Lightamer 正在从 Swift 全量重写成 Rust，功能面是 darktable 的，许可证 GPL-3.0-or-later，Apple 的框架只能经一个模块（`dt-apple`）使用。用户要 AI 蒙版：「皮肤、人物、背景、天空、面部、身体等蒙版，如果参考项目中有，抄过来」。

上一条调研已经查清（`.work/gsd/phases/masks-research/RESEARCH.md`，先读它的 §0、§6 的 Q2、Q3、Q5 和 §7）：人物、背景、天空、主体、点选物体在参考项目里都有，照抄的方案已定。**皮肤、面部、身体三类，所有参考项目里都没有可用的计算实现。**

用户 2026-11-26 下午的裁决：接受「Apple 的 Vision 先行，另外派一条调研去核开源人像解析模型的许可证、质量和体积，拿到事实再定」。你就是这条调研。你只读、只查，不写产品代码，不下载模型权重。

工作目录 `/Volumes/UNITEK/Documents/Development/Lightamer`。全程中文，标识符英文。

## 先读

- `.work/gsd/phases/masks-research/RESEARCH.md` 的 Q5（已列了候选的方向）和 Q3（我们定下的推理后端：ONNX Runtime 的 Rust 绑定 `ort`，Apple 那一侧收在 `dt-apple`）。
- `.work/gsd/phases/masks-research/RESEARCH-TABLES.md` 的 T-M5（上一条调研怎样核许可证：代码和权重分开核，证据写文件和行号）。
- `/Volumes/UNITEK/Documents/Development/Lightamer/docs/APPLE-BOUNDARY.md`：Apple 能力的边界规矩。
- `AGENTS.md` 里「M6-4 图库 stacks + AI 分割蒙版」和「lumen-culling」两条：旧 Swift 版用 Vision 做过什么、走到哪一步（只读文字；要核一个细节再去读 `LightamerCore/` 和 `LightamerIOP/` 下对应的 Swift 源码）。

## 要查的

**一，Apple 的 Vision 自带的能力，到底能给这三类里的什么。** 逐项查公开文档和头文件，写清楚：

- 人物分割（`VNGeneratePersonSegmentationRequest` 一类）：输出是什么、有几档质量、最大分辨率、最低系统版本、在哪种处理器上跑。它给的是整个人；对「身体」算不算够用。
- 人脸：检测框、关键点（`VNFaceLandmarks2DObservation`）。关键点能不能拼出一张「面部」蒙版（比如脸的轮廓），精度和局限。
- 人体姿态、手部：能不能转成身体蒙版。
- 皮肤：Vision 有没有任何直接或间接能给皮肤的能力。
- 前景实例（`VNGenerateForegroundInstanceMaskRequest` 一类）：它和上面几类的关系。
- 旧 Swift 版用过其中哪些，效果怎样，代码在哪（`文件:行号`）。

**二，开源的模型，逐类找候选。** 皮肤、面部、身体各找两到三个，覆盖这些方向（不限于）：人像解析（face parsing，输出皮肤、头发、嘴唇这类部位）；人像抠图和人物分割（ selfie segmentation、human matting 一类）；人体解析（human parsing，输出脸、手臂、腿、衣服这类部位）；专门的皮肤分割。

每一个候选都要写清，**查不到就写查不到，不要猜**：

- 代码的许可证；**模型权重的许可证**（常常和代码不一样，分开写）；训练数据的许可有没有公开说明。
- 权重多大；有没有现成的 ONNX 文件（我们定的后端要 ONNX）；没有的话导出难不难。
- 输入多大、输出几类、类别名各是什么。
- 在处理器上的速度有没有公开数字；有没有人在苹果芯片上跑过的记录。
- 质量口碑：对亚洲人、侧脸、暗光、身体局部的表现，有没有人报过问题。
- 最近还在维护吗， star 数、最近一次提交的日期。

**三，给结论。** 逐类回答：

- 只靠 Apple 的 Vision，这一类能做到什么程度，做不了什么。
- 要做到「可用」，最值得引入的是哪一个模型，理由；它的许可证让不让我们随包分发（我们是开源软件，免费分发，许可证 GPL-3.0-or-later）。
- 引入它的代价：体积、速度、维护。
- 你建议这一类怎么排：只靠 Vision 就够、必须引入模型、还是先不做。

## 产物

`.work/gsd/phases/masks-research/SKIN-FACE-BODY.md`，中文正文、英文标题：

- 开头一页纸：三类各一段结论，加一张「建议」表（类别、靠什么、引不引入模型、代价、建议排期）。
- 第一节：Vision 的能力，逐项，证据带链接或头文件里的名字。
- 第二节：候选模型表。行是候选，列是上面那些事实。每一条事实给来源链接；许可证要给许可证文件所在的路径或链接。
- 第三节：三类各自的结论和理由。
- 最后一节「需要用户定的事」，只列真需要拍板的，不超过三件，每件带你的推荐。
- 实测的数字标来源；没查到的写「没查到」；你的推断标「推断」。

## 纪律

- 只许新建 `.work/gsd/phases/masks-research/SKIN-FACE-BODY.md` 一个文件。别的任何文件不许改。`skin-research.log` 是塔台重定向你的输出用的，不要动。
- **不下载模型权重。** 看网页、看仓库里的说明和许可证文件、看模型卡，都可以；权重文件本身不下。
- 不构建、不跑测试、不运行 `darktable`、不打开任何图形程序、不下载安装任何软件。
- 联网：先直连，失败再给那一条命令加代理（`http://127.0.0.1:10809`）。
- 不读、不打印任何凭据文件，产物里不出现密钥。
- 不碰用户照片库 `/Volumes/UNITEK/Cloud Drive/QSync/Medias/Photos/Workspace`：不读、不列目录。
- 不进 `/Volumes/UNITEK/Documents/Development/darktable` 和 `darktamer` 两个目录。
- 机器上同时有一条执行 lane 在干活，它要构建、要开窗口。你不构建，不做大范围的磁盘扫描。
- **不要自己另起复审实例。** 复审由塔台在你退出后另派。
- 数字不编。到时间上限就交已有结果，写明停在哪。
- 总墙钟不超过 90 分钟。

stdout 最后一条消息一次性完整输出：一页纸的内容、需要用户定的事。
