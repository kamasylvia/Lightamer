# 核心设计调研 lane（omp，带两个小 spike）：darktable 的模块怎样搬到 Rust 核心，rawspeed 解码路径怎么定，拿什么当验收对照

## 背景与裁决（已定，不要重开）

用户 2026-11-25 晚定下：
- 产品 = darktable 的功能 + darktamer 的自定义功能，UI 交互复刻 darktable。Lightamer 有而 darktable 没有的功能保留。
- 全部用 Rust：核心 + gpui 族界面。Apple 能力（Core Image 解码、ColorSync、Vision、ImageIO、Metal）独占一个模块，只在 macOS 构建里存在，其余代码不依赖 Apple 框架。
- **解码主路径是 rawspeed**。
- 编辑历史要兼容 darktable / darktamer 的相同模块（#34，另一条 lane 在查历史格式，你不用管）。
- 旧的 Swift 版已冻结，它的输出不需要匹配。**验收对照是 darktable 本身**，用官方二进制。
- 许可证保持 GPL-3.0，可以移植 darktable 的代码（GPL-3.0，保留版权声明并标注修改）。

已有的输入，先读：
- `.work/gsd/phases/rust-core/FEATURE-SCOPE.md`：darktable 103 个模块与 21 个功能域的盘点、第 0 期的建议范围。
- `.work/gsd/phases/rust-core/SPIKE-RUST-APPLE.md`：Rust 调四项 Apple 能力的实测；rawspeed 转 DNG 再走 Core Image 的解码耗时。
- `.work/gsd/phases/rawspeed-backend/SPIKE.md`：上一轮解码实测。其中记着 rawspeed 转 DNG 路线偏色，`mean_abs_diff 22.8/255`。
- `.work/gsd/phases/gpui-fast-scout/` 与 `.work/gsd/phases/gpui-viewport/`：界面的能力边界，只在涉及核心接口时参考。

资料位置：
- **官方 darktable 源码是一份干净的工作树**：`/Volumes/UNITEK/Documents/Development/Lightamer-rust-spike/refs/dt-master`（上游 `master`，提交 `679d594f5d`，2026-11-22）。读它。
- **不要读** `/Volumes/UNITEK/Documents/Development/darktable` 的工作目录，那是 darktamer 分叉的工作树。
- rawspeed 已编好：`/Volumes/UNITEK/Documents/Development/Lightamer-rawspeed-spike/`（`build/` 里有静态库，`rawspeed/` 是源码，`shim/` 是 C ABI 垫片）。
- 上一条 Rust spike 的工作区：`/Volumes/UNITEK/Documents/Development/Lightamer-rust-spike/`。`out/bin/` 里有可直接运行的可执行文件，其中 `s1-ciraw` 用 Core Image 解码并渲染到全分辨率；源码副本在仓内 `.work/gsd/phases/rust-core/SPIKE-RUST-APPLE-src/`。
- CC0 样张：`~/Library/Application Support/Lightamer/TestRAW/`。

## 要做的七件事

**C1 管线与模块接口怎样对应到 Rust（读源码）。** darktable 一个模块要实现哪些回调（初始化、默认值、提交参数、处理、改变感兴趣区域、蒙版形变、顺序标签等），管线分哪些阶段（_rawprepare_、去马赛克、色彩输入、各模块、色彩输出、显示变换、剪切），全尺寸、预览、缩略图三条管线的关系，分块处理，混合与蒙版在哪一步。给出一个不带界面的 Rust trait 设计：方法、输入输出类型、错误处理、同步还是异步。标明每个方法对应 darktable 的哪个回调。只设计第 0 期用得到的部分。

**C2 第 0 期的模块清单（读源码）。** 第 0 期范围：导入、图库、解码、基础暗房（曝光、白平衡、曲线、裁剪、镜头校正）、色彩管理与显示变换、历史、蒙版与混合基础、导出 JPEG/PNG/TIFF/HEIC。列出每一步对应的 darktable 模块：源文件、行数、有没有 OpenCL 版本、参数大小、外部依赖（lcms2、lensfun、rawspeed 等）、CPU 与 OpenCL 两版输出有没有已知差异。默认模块顺序表在 `src/common/iop_order.c`，照它列。

**C3 rawspeed 解码路径（小 spike，要编译）。**
- 列出 rawspeed 自带的去马赛克算法。写一个小程序，对 A7R5 那张 CC0 样张：rawspeed 解码，再分别用这些算法做去马赛克，各报耗时（5 次中位，默认线程数）。
- 把「rawspeed 解码加去马赛克」的结果和 `s1-ciraw` 的 Core Image 解码结果对比：黑电平、白平衡缩放、相机矩阵这些各自怎么取，逐项列出来；报平均差和最大差。不要求对齐，要求说清差在哪。
- 查上一轮「rawspeed 转 DNG 偏色」的原因：对照 DNG 规范和 Core Image 的读法，检查 DNG 写入器里的白平衡、色彩矩阵、黑电平、线性化表。在垫片的工作副本里试一个修法，报修前修后的差值。查不出就写查到了哪一步。
- 结论：不用 Apple 模块时，这条路径的去马赛克用哪个算法起步；Apple 模块要不要提供一条可选的更快路径。

**C4 验收对照的工具（小 spike，要下载并运行官方 darktable）。**
- 从 darktable 官方 Releases 下载 macOS Apple Silicon 的安装包，版本用 5.6 系列（#26 的基线是 5.6.2）。记录下载地址、版本号、文件的 sha256。只挂载，不安装到「应用程序」：`hdiutil attach -nobrowse -readonly`，直接从挂载卷里运行 `darktable.app/Contents/MacOS/darktable-cli`。
- 配出一条可靠的命令：给一张图应用它旁边的一份历史（XMP），输出 16 位 PNG 或浮点 TIFF，并把配置、缓存、库全部隔离到临时目录。
- **偏好保护**：第一次启动 darktable 之前执行 `defaults export org.darktable <临时目录>/org.darktable.before.plist`（域不存在而失败是正常的）。全部跑完后再导出一次，如果前后不同，执行 `defaults import org.darktable <临时目录>/org.darktable.before.plist` 还原。禁止 `killall cfprefsd`。环境上同时隔离 `HOME` 和 `CFFIXED_USER_HOME`。
- 用 A7R5 那张样张跑三组：不带历史；只加曝光；再加一个简单模块。每组分别用 CPU 和 OpenCL 渲染，报两者的差值。这个差值就是我们与 darktable 比对时的噪声底线。
- 写一个比对脚本（Python 一律走 `uv run --with …`），输入两张图，输出平均差、最大差、在容差内的像素比例。把命令、脚本和输出留在证据目录里。
- 结束时卸载挂载卷、删除安装包和临时目录，报删除前的大小。

**C5 GPU 后端选型（设计，给推荐）。** 管线着色器用哪种形式写：以 WGSL 配 wgpu 为底、Apple 模块里再给 Metal 快路径；还是直接用 Metal。依据是 C2 的模块清单里有多少需要 GPU、各自的数据量，以及「Apple 能力只在 macOS 模块里」这条裁决。说明 darktable 的 OpenCL kernel 移植到 WGSL 的工作量量级。Lightamer 现有的 73 个 Metal 着色器文件里，有多少能对上第 0 期的模块。

**C6 仓库布局（设计）。** 给一个 cargo 工作区的划分：核心、各模块、平台接口、Apple 模块（只在 macOS 构建里编进去）、界面、命令行与对照工具。写清 Apple 模块怎样做到「只在 macOS 版本里可见」：编译期怎样门控，界面怎样知道某项能力在不在。Lightamer 独有的功能放在哪。

**C7 移植的做法与量级（设计加估算）。** 一个 darktable 模块从 C 加 OpenCL kernel 变成 Rust 加着色器，步骤是什么，版权声明和修改标注怎么留。按 C2 的清单，估第 0 期每个模块要几条执行 lane。按今天的实测速度校准：一条 lane 一到两小时能交付一千行上下、带测试的代码。估算标明是估算。

## 读法与诚实要求

- 数字不编。耗时写清怎么量的。查不到就写查不到，并写出查过什么。
- 结论和证据分开写。没有证据的判断标「推断」。
- 裁决点只列真需要用户定的，每点给选项和你的推荐。

## omp 域内自审（项目既定模型）

产物落盘后，另起一个独立的 `omp -p --auto-approve --thinking max "<复审任务书>"` 实例复审你的产物。复审实例重点核：C3 的对比是不是真做了（看程序和输出）、C4 的命令能不能照着复现（至少复跑一组）、耗时是怎么量的、没做成的项有没有被写成做成。结论头 `PASS / N error + N minor`。发现的问题回注修订，修订记录附在产物末尾。复审输出落 `core-design-review.log`。

## 纪律

- 仓内只写 `.work/gsd/phases/rust-core/` 下的文件：`CORE-DESIGN.md`、`CORE-DESIGN-TABLES.md`、`decode-oracle-evidence/`（命令、脚本、输出、校验和）、`decode-spike-src/`（spike 程序源码，不含构建产物）、`core-design-review.log`、`omp-core-design-summary.md`。产品树零改动。零 commit，零 push。
- spike 程序放在仓外 `/Volumes/UNITEK/Documents/Development/Lightamer-rust-spike/` 下新建的子目录里。
- **不碰用户照片库** `/Volumes/UNITEK/Cloud Drive/QSync/Medias/Photos/Workspace`：不读、不列目录。样张只用 CC0 目录里的。
- **只运行 `darktable-cli`，不打开图形界面，不合成输入事件。**
- 机器：构建前跑一次 `Scripts/machine-guard.sh` 并记录结果。编译并行度 6 以内。不同时跑两个编译。不用 `caffeinate`；一定要用就带秒数上限，不留孤儿进程。
- 网络：模型调用走已给定的代理环境变量。下载和 `cargo` 拉依赖先直连，失败再单独给那一条命令加代理。
- 结束时退出你启动的所有进程。自建的 `target/` 目录超过 2 GB 就删掉，报保留内容和总大小。
- 总墙钟不超过 200 分钟，含自审。到点交已有结果，标明没完成的部分。

## 交付

`CORE-DESIGN.md`（中文正文，英文标题）：

1. §0 一页纸：Rust 模块接口的形状、第 0 期的模块数与总行数、解码路径的结论、验收对照命令、GPU 后端推荐、第 0 期的 lane 数估算。**不超过 45 行。**
2. §1 到 §7 对应上面七件事，正文只放汇总，长表放 `CORE-DESIGN-TABLES.md`。
3. §8 裁决点清单：问题、选项、推荐、依据。
4. §9 没验证的。

stdout 最后一条消息一次性完整输出，并落盘 `omp-core-design-summary.md`。
