# 塔台核验记录：Rust 核心可行性与范围盘点

日期 2026-11-25。核验对象 = 同目录 `SPIKE-RUST-APPLE.md`、`FEATURE-SCOPE.md`、`CORE-INVENTORY.md`（三条 omp lane 的产物）。原则：先核证据，再读结论。

## §0 结论头

- **非 UI 层用 Rust、同时保住 Apple 能力，前提成立。** 四项能力（Core Image 解码、ImageIO、ColorSync、Vision）都从 Rust 直接调通，仓库现有 Metal 着色器在 Rust 宿主下的输出与 Swift 宿主逐字节相同。两项逐字节对比我亲自复跑过。
- **功能范围**：darktable 基线 103 个 iop 模块源（149,074 行）、21 个功能域；darktamer 在其上加 8 个功能、品牌化和一个 Rust 数学核心（76 个提交，109 个文件，+14,808 / −933）。Lightamer 对 103 个模块是「有 43 / 部分 26 / 没有 33」。
- **重写规模**：非 UI Swift 156,048 行。按文件主导依赖粗分：纯逻辑 59,720 行、着色器宿主 43,225 行、Apple 适配 31,221 行、与界面耦合 21,884 行（后两类有重叠口径，见盘点报告）。
- **落盘契约必须逐字兼容**：sidecar schema v13、项目库 user_version 6、FNV-1a 64 位哈希的十进制字符串写法、UserDefaults 键族、MCP 34 个工具。

## §1 我核实了什么

| 对象 | 我的核验 | 结果 |
|---|---|---|
| S4 着色器 | 用 lane 留下的两个程序（Rust 宿主、Swift 参照）在同一份输入上各跑一次，`cmp` | 逐字节相同，793,616 字节，sha256 `b0e01d2f…` |
| S4 源文件 | 拷到工作区的两个 `.metal` 与仓库里的文件 `cmp` | 逐字节相同，未被改动 |
| S3 ColorSync | 重跑 Rust 程序，与 Swift 参照的输出 `cmp`；源缓冲 `cmp` | 均逐字节相同，3,072 字节 |
| S2 Vision | 两份输出文本 `cmp` | 相同（人脸 0 个，矩形 1 个，坐标一致） |
| 功能范围 | `git describe`、两个 remote、领先上游的提交数、改动文件数与增删行数、iop 文件数与行数、`rust/math-core` 行数 | 全部与报告一致（math-core 总行数我数到 3,261，报告写 3,289，小出入） |
| 核心盘点 | kernel 数（186）、IOP Swift 文件数（105）、App 非 UI 文件数（94）、sidecar 版本（13）、项目库版本（6）、测试方法数（4,621 对报告 4,623） | 一致或小出入 |

没有核的：S1 的耗时没有重跑计时（只看了报告与日志，口径见报告 §1）；S5 桥没有重跑；核心盘点的逐文件难度分档没有逐个复核。

## §2 我更正自己的两处说法

- **darktamer 就在本机。** `/Volumes/UNITEK/Documents/Development/darktable` 是 darktamer 的工作树（remote `github` 指上游，`github-fork` 指用户的分叉，HEAD 领先上游 76 个提交）。我此前对用户说「本机没有副本」，并在任务书里把它写成「官方 master、无 remote」，两处都错。lane 按实测纠正，改用树内的 `github/master` 作官方基线。**读官方基线要用那个 ref，不要直接读工作树。**
- **项目没有用 ColorSync 的 C 接口。** 我此前说「17 个文件直接用 C API」，那是按「ColorSync」字样数出来的文件数。按 `CMProfile`、`CMWorld` 一类符号数，调用为 0；项目走的是 CoreGraphics 的 `CGColorSpace`（61 处调用、24 个文件）。结论不变：两类接口都能从 Rust 调。

## §3 带限制的结论

- 着色器 73 个只验证了 2 个；Vision 项目用到的 5 类请求只测了 2 类，且样张里没有人脸。
- ImageIO 写 sRGB 时不写 ICC 数据，只打已知空间标记；非标准 ICC 会真写入，但只在 Swift 探针里验过。
- 过桥传纹理只测了第一行，两边各有一次接口拷贝，不是字面上的零拷贝。
- Metal 着色语言是 Apple 专属。Rust 宿主能原样跑，不等于着色器可移植；跨平台需要第二套着色器。
- rawspeed 转内存 DNG 的路线上一轮记过偏色（平均差 22.8/255），本轮没有复核。解码主路径选它之前要先解决。

## §4 lane 的自审

三条 lane 各有一个独立复审实例，发现均已修订，修订后都没有再做第二轮复审：spike `PASS / 3 error + 10 minor`（撤回「ICC 确实写入」和「零拷贝」两条说法）；功能范围 6 error + 11 minor；核心盘点 `FAIL / 2 error + 8 minor`（原结论首行，修订记录在报告 §8）。
