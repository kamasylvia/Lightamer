# Rust 核心可行性 spike（omp）：非 UI 部分用 Rust，能不能不靠 Swift 用上四项 Apple 能力，并复用现有 Metal 着色器

## 背景（用户刚改的裁决）

用户 2026-11-25 晚定下的架构：**非 UI 部分全部用 Rust，UI 部分用 AppKit（Swift）**。将来可能换 UI 层或有跨平台需求，所以核心与 UI 之间要有稳定接口，Apple 依赖不能散落在核心里。

用户的问题：CIRAW 解码、ColorSync、AI 蒙版用的 Vision、ImageIO 导出这四项 Apple 能力，如果不想放弃，是不是必须全用 Swift？只要 UI 层原生够不够？

塔台已核实的线索（不是结论，要你实测）：crates.io 上有 `objc2-core-image` 0.3.2、`objc2-image-io` 0.3.2、`objc2-vision` 0.3.2、`objc2-metal` 0.3.2、`cidre` 0.30.1、`metal` 0.33.0、`uniffi` 0.32.2、`swift-bridge` 0.1.59。**绑定库存在不等于我们的用法能跑通。** 这条 spike 用实测回答。

本项目的现状，供你对照：
- Metal 着色器是现成资产：仓库 `LightamerIOP/Sources/` 下 73 个 `.metal` 文件，13,317 行，与宿主语言无关。
- Vision 的实际用法很窄：`VNDetectFaceRectanglesRequest`、`VNDetectFaceLandmarksRequest`、`VNImageRequestHandler`。
- ColorSync：项目有 17 个文件直接用它的 C API（`CMProfile`、`CMWorld`），另有 40 个文件用 `CGColorSpace`。
- Core Image 与 ImageIO：分别约 24 和 18 个文件。
- 上一轮解码实测（Swift）：CIRAW v8 打开 A7R5 到适配预览 868–968 ms；rawspeed 解码 34–57 ms。rawspeed 的 C ABI 垫片源码在 `.work/gsd/phases/rawspeed-backend/spike-src/`（`rawspeed_shim.cpp`、`rs2dng.cpp`）。

## 要做的五件事

工作区新建在仓外：`/Volumes/UNITEK/Documents/Development/Lightamer-rust-spike/`。**按 S4、S1、S3、S2、S5 的顺序做**，前面的更重要。到时间上限就停，交已完成的。

**S4 用 Rust 宿主跑现有 Metal 着色器。** 从仓库拷 `LightamerIOP/Sources/Passthrough.metal` 和一个带参数的 kernel（例如 Levels 或 Exposure）到工作区（只拷不改）。Rust 侧运行时用源码编译着色器库、派发、读回。再写一个二十行左右的 Swift 参照宿主，输入完全相同，两边输出**逐字节对比**。预期一致，因为 kernel 没变。

**S1 从 Rust 调 CIRAW。** 样张只用 `~/Library/Application Support/Lightamer/TestRAW/` 里的 CC0 样张（Sony A7R5 那张）。经 `CIRAWFilter` 解码（先读该文件的 `supportedDecoderVersions`，再用 v8），经 Metal 设备的 `CIContext` 渲染进 `MTLTexture`，读回。报：尺寸、像素格式、每文件支持的解码器版本、5 次耗时中位数。时间够再做 rawspeed → 内存 DNG → CIRAW 这条路（用现成的 `rawspeed_shim.cpp`，经 `cc` crate 编进去），同样报耗时。

**S3 从 Rust 调 ImageIO 与 ColorSync。**
- ImageIO：把一块 RGBA 缓冲用 `CGImageDestination` 编成 JPEG 和 HEIC，嵌入 ICC 档案；用 `CGImageSource` 读回，确认档案名。macOS 27 上再试 AVIF。
- ColorSync：项目用的是 C API。你手写 `extern` 声明，加载一个 ICC 档案、对一小块 RGB 缓冲做变换；Swift 参照程序做同样的事，输出逐字节对比。

**S2 从 Rust 调 Vision。** 用项目实际用的 `VNDetectFaceRectanglesRequest` 在一张样张上跑人脸矩形。Swift 参照程序跑同一张图，对比框的数量和坐标。完成回调要回到 Rust 的通道或 future，在非主线程上收结果。

**S5 UI 与核心之间的桥。** 写一个很小的 Rust 对象：一个同步方法、一个异步方法、一个事件回调。用 UniFFI 暴露给 Swift（不行再试 swift-bridge）。写一个 **Swift 命令行可执行程序**（不是 app，不开窗口）把三个都调一遍。再把一个 `MTLTexture` 的指针以整数形式传过桥，在对侧直接使用，不拷贝像素。报哪种桥在本机工具链上能跑通、卡在哪。

## 纪律

- **不开任何图形窗口**，不合成任何输入事件。S5 的验证用命令行程序。GPU 工作全部离屏。
- **仓内只写 `.work/gsd/phases/rust-core/`**：`SPIKE-RUST-APPLE.md`、`SPIKE-RUST-APPLE-src/`（Cargo.toml、Cargo.lock、全部源码和 Swift 参照程序，**不含构建产物**）、日志。产品树零改动。零 commit，零 push。
- **不碰用户照片库** `/Volumes/UNITEK/Cloud Drive/QSync/Medias/Photos/Workspace`：不读、不列目录。样张只来自上面写的 CC0 目录。
- 机器：构建前跑一次 `Scripts/machine-guard.sh` 并记录结果。编译并行度 6 以内。不跑全套测试。不用 `caffeinate`；如果一定要用，带秒数上限，不留孤儿进程。
- 网络：模型调用走已给定的代理环境变量。`cargo` 拉依赖先直连，失败再单独给那一条命令加代理。
- **数字不编。** 哪一项没做成，写没做成和卡在哪一步、报错原文。绑定库缺某个 API 时，写你是怎么补的（手写 `extern` 声明、换库，还是放弃）。
- 记录每个用到的 crate 的精确版本号和许可证。
- 结束前清理：工作区里的 `target/` 目录如果超过 2 GB，删掉；列出保留的内容和总大小。
- 总墙钟不超过 170 分钟，含自审。

## omp 域内自审（项目既定模型）

产物落盘后，另起一个独立的 `omp -p --auto-approve --thinking max "<复审任务书>"` 实例复审。复审实例只读产物、源码副本和仓库，重点核三件事：逐字节对比是不是真的做了（看对比代码和输出）、耗时是怎么量的、没做成的项有没有被写成做成。结论头 `PASS / N error + N minor`，发现回注修订，修订记录附在产物末尾。复审输出落 `spike-review.log`。

## 交付

`.work/gsd/phases/rust-core/SPIKE-RUST-APPLE.md`（中文正文，英文标题）：

1. §0 结论表：S1 到 S5 各一行，「跑通 / 有保留地跑通 / 没跑通」，加一句话证据。表下面直接回答用户的问题：只要 UI 层原生，非 UI 层用 Rust，这四项能力保不保得住。
2. §1 逐项细节：做法、crate 与版本、代码行数、耗时、对比结果。
3. §2 绑定缺口与解法。
4. §3 对架构的含义：每项能力该收在什么样的接口后面，macOS 实现与将来的其它平台实现怎么分。
5. §4 没验证的。
6. §5 工作区保留内容与大小。

stdout 最后一条消息一次性完整输出，并落盘 `omp-spike-summary.md`。
