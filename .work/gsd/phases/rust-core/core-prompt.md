# 核心盘点 lane（omp，只读）：Lightamer 非 UI 部分有哪些东西、各自依赖什么，重写成 Rust 时怎么分

## 背景（用户刚定的方向）

用户 2026-11-25 晚定下：**非 UI 部分全部用 Rust，UI 用 AppKit。** 将来可能换 UI 层或跨平台，所以每项 Apple 依赖要收在一个接口后面，核心对 UI 只暴露一个稳定接口。现有代码里非 UI 的 Swift 约 156,000 行，要重写成 Rust。这条 lane 把「要重写什么」盘清楚。

你这条 lane 只做盘点，不做设计，不改任何代码。另一条 lane 在盘功能范围（darktable 与 darktamer），你不用管它。

盘点对象：
- `LightamerCore/Sources/`（232 个文件，80,887 行）
- `LightamerIOP/Sources/`（Swift 36,719 行，另有 73 个 `.metal` 文件共 13,317 行）
- `App/Sources/Lightamer/` 下的非 UI 目录：`AI`、`Export`、`Library`、`MCP`、`Session`、`State`、`Yiyin`（共 38,442 行）
- `Tests/` 的结构（只看目录和数量，不读全部内容）
- 约定与格式正本：仓库 `AGENTS.md`（「Conventions」下的架构增量各节、`.lra` 与 `.lalb` 形态、UserDefaults 键登记）

## 要回答的问题

**Q1 模块地图。** 按目录列出：职责一句话、Swift 行数、文件数、对外的类型或接口概况。`State/` 里哪些是纯逻辑、哪些是给 SwiftUI 用的胶水（将来归 UI 层，不进 Rust 核心），要分开列。

**Q2 Apple 依赖地图。** 哪些文件调用了下面每一类，各多少处，分别属于哪种能力：
- Core Image（`CIRAWFilter`、`CIContext`、`CIImage`）
- ColorSync 的 C API（`CMProfile`、`CMWorld`）与 `CGColorSpace`、`CGColorConversion`
- Vision
- ImageIO（`CGImageSource`、`CGImageDestination`）
- Metal（设备、命令队列、着色器宿主、纹理读写）
- 其它 Apple 框架（CoreML、Vision 之外的 ML、UniformTypeIdentifiers、FileProvider 等，有就列）

按**能力**归并（解码、色彩、人脸、编码、GPU 计算……），每种能力给一个候选的接口边界：核心需要它做什么（输入、输出、同步还是异步），不写实现。

**Q3 着色器清单。** 73 个 `.metal` 文件逐个列：文件、kernel 个数、行数、属于哪个 iop、宿主在哪个 Swift 文件、是否依赖特殊纹理格式或原子操作。它们与宿主语言无关，重写时原样保留，所以要把宿主与着色器之间的约定列出来：纹理格式、线程组大小、uniform 结构、参数打包方式。

**Q4 必须保持不变的东西。** 列出跨进程或落盘的契约：`.lra` sidecar 的 schema（现行版本号与字段）、`.lalb` 的表结构、入包哈希的写法、UserDefaults 键族、MCP 工具清单（名称、参数、是否需要控制权）、导出产物的元数据约定。每项给出正本所在的文件。这些在 Rust 实现里必须逐字兼容，否则用户现有的图库和编辑历史打不开。

**Q5 测试盘点。** 按测试 target 列：测试文件数、测试方法数、哪些是 golden 图测试、哪些是行为测试、哪些依赖 SwiftUI 或 AppKit。标出哪些测试可以直接当作 Rust 实现的验收对照（输入输出都能脱离界面复现），哪些不能。

**Q6 重写难度分档。** 把 Q1 的每个模块标成四档之一：纯逻辑（数据结构、解析、SQL）、着色器宿主（Metal 派发与纹理）、Apple 框架适配（调用 Core Image、ColorSync、Vision、ImageIO）、与界面耦合（需要先拆）。每档给行数合计。这是工作量量级的粗估，标明是估。

## 读法与诚实要求

- 数字不编。每个数字写出得出它的命令或文件清单。
- 结论和证据分开写。没有证据的判断标「推断」。
- 查不到就写查不到。

## omp 域内自审（项目既定模型）

产物落盘后，另起一个独立的 `omp -p --auto-approve --thinking max "<复审任务书>"` 实例复审。复审实例逐条抽查你的数字（自己重跑命令），结论头 `PASS / N error + N minor`，发现回注修订，修订记录附在产物末尾。复审输出落 `core-review.log`。

## 纪律

- 仓内只写 `.work/gsd/phases/rust-core/` 下的文件：`CORE-INVENTORY.md`、`CORE-INVENTORY-TABLES.md`（大表）、`core-review.log`、`omp-core-summary.md`。
- 产品树零改动。零 commit，零 push。
- 不构建、不跑测试、不开图形程序。
- 不碰用户照片库 `/Volumes/UNITEK/Cloud Drive/QSync/Medias/Photos/Workspace`：不读、不列目录。
- 总墙钟不超过 100 分钟，含自审。到点交已有结果，标明没完成的部分。

## 交付

`CORE-INVENTORY.md`（中文正文，英文标题）：

1. §0 一页纸：四档难度各自的行数合计、Apple 依赖按能力的处数合计、必须保持不变的契约清单、可直接当验收对照的测试数。**不超过 40 行。**
2. §1 到 §6 对应上面六个问题，正文里只放汇总，长表放 `CORE-INVENTORY-TABLES.md`。
3. §7 没查到的。

stdout 最后一条消息一次性完整输出，并落盘 `omp-core-summary.md`。
