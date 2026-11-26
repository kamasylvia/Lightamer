# 评审 lane（omp，只读）：独立核一份蒙版来源调研里的许可证和事实

你要独立评审一份刚写完的调研。调研回答的是：皮肤、面部、身体三类蒙版，Apple 的 Vision 能给什么、要引哪个开源模型。它的结论会直接变成用户的决策，所以**每一条许可证的结论和每一个体积数字都要对着原始来源再核一遍**。

被评的文件（只读，一个字不许改）：`/Volumes/UNITEK/Documents/Development/Lightamer/.work/gsd/phases/masks-research/SKIN-FACE-BODY.md`。先读全文。

工作目录 `/Volumes/UNITEK/Documents/Development/Lightamer`。全程中文，标识符英文。

## 逐项核

1. **许可证，逐条对原文。** §2.2 列了每一条的证据路径。逐条打开核：
   - `yakhyo/face-parsing`：仓库的 `LICENSE` 是不是 MIT；README 里有没有单独说权重是什么许可（调研说「随项目 MIT 发布，README 未单列权重许可」）；README 的数据集一节是不是明写了 CelebAMask-HQ；权重的 Release 页面上有没有另附许可说明。调研给出的结论「权重许可 MIT」是事实还是推断，你要分清并写明。
   - CelebAMask-HQ 的协议原文（官网 Agreement）：非商业的条款约束的是谁——数据集本身的再分发，还是用它训练出来的模型。调研写的是「约束对象是数据集再分发而非权重使用」，这是它自己的解读，你去读原文，判断这个解读站不站得住，写明你的依据。**这一条最重要。**
   - `zllrunning/face-parsing.PyTorch`、SCHP：权重许可「未声明」是否属实（README 里真的一句都没有？issue 里作者有没有答复过？能搜就搜一下）。
   - RVM（`PeterL1n/RobustVideoMatting`）：代码是 GPL-3.0 是否属实；权重有没有单独的许可说明；调研把权重「按同仓 GPL 理解」标成了推断，你看有没有更硬的证据（Release 说明、README、issue）。
   - MODNet：README 的 License 一节是否明写了「code, models, and demos」都是 Apache-2.0。
   - MediaPipe 自拍多类分割：权重页的许可证栏、格式（是不是只有 tflite）。
2. **体积和可用性。** 调研里每个字节数（yakhyo 的 53,205,364 等）它说是用 HEAD 请求量的。你用同样的方法（只发 HEAD，**不下载权重文件**）复核每一个数。「官方有没有现成 ONNX」逐个核。
3. **Vision 的事实。** §1 里每一条关于 Vision 的说法（人物分割的档位和分辨率上限、人脸关键点的组数和点数、前景实例那一族请求的名字、人体和手部姿态的关节点数、最低系统版本），对着本机 SDK 里 `Vision.framework` 的头文件核（路径用 `xcrun --show-sdk-path` 取）。调研引用的旧 Swift 版的做法（§1.6），对着 `LightamerCore/`、`LightamerIOP/`、`App/` 下的 Swift 源码核 `文件:行号`。
4. **结论和证据对不对得上。** §0 的建议表和 §3 的三条结论，每一条的理由是不是都落在核过的事实上；有没有哪一条把「没查到」的东西当成了已知。§4 的三件待定事项，推荐的理由成不成立。

## 产物

你的输出直接写 stdout（塔台重定向存档），第一行是结论头：`PASS / N error + N minor`。error 是会让用户做错决定的事实错误（许可证、体积、可用性）；minor 是引文精度、措辞。然后逐项写结论和证据，证据带链接或 `文件:行号`。最后一张表：每一条发现的位置、问题、证据、建议怎么改。

## 纪律

- 只读。不写任何文件，不动 git。
- 不构建、不跑测试、不运行 `darktable`、不打开任何图形程序、不下载安装任何软件。**不下载模型权重**（HEAD 请求不算下载）。
- 联网先直连，失败再给那一条命令加代理（`http://127.0.0.1:10809`）。
- 不读、不打印任何凭据文件。不碰用户照片库 `/Volumes/UNITEK/Cloud Drive/QSync/Medias/Photos/Workspace`。不进 `/Volumes/UNITEK/Documents/Development/darktable` 和 `darktamer` 两个目录。
- 引用是你真的打开看过的才写。数字不编，核不到的写核不到。
- 最后一条消息一次性完整输出全部结论。墙钟不超过 40 分钟。
