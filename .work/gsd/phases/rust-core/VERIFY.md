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

## §5 追加：历史兼容调研（2026-11-25 深夜）

核验对象 = `HISTORY-COMPAT.md`、`HISTORY-COMPAT-TABLES.md`。我对照官方基线工作树（`refs/dt-master`，`679d594f5d`）抽查了这些，全部对上：

- 写 sidecar 的默认模式是 `on import`（`data/darktableconfig.xml.in`）。
- XMP 版本常量是 5（`src/common/exif.cc:83`）；已知键表 `dt_xmp_keys[]` 在 `:446`，写回时只删已知键的 `_remove_known_keys` 在 `:530`。
- 遇到不认识的模块：`iop_order == INT_MAX` 就 `continue` 跳过这一条（`src/develop/develop.c:2614-2625`）；模块版本比自己新时用默认参数并保留条目（`:2769-2782`）。
- 顺序枚举 `CUSTOM / LEGACY / V30 / V30_JPG / V50 / V50_JPG`，默认 RAW 用 V50、非 RAW 用 V50_JPG（`src/common/iop_order.h`）；三张顺序表在 `iop_order.c:81 / 306 / 556`。
- 参数超过 100 字节且首选项允许时，用 zlib 加 base64，带 `gz` 前缀（`exif.cc:4028`、`:4078-4085`）。
- 曝光模块的版本号是 7（`DT_MODULE_INTROSPECTION(7, …)`）。树内样例 `src/tests/masking/flexi/xmps/G1_bare_uniform.xmp` 的曝光条目是版本 6、24 字节，我逐字节解了一遍：模式 0、黑位 0、曝光 5.0、百分位 50.0、目标 −4.0、补偿开关关，与报告一致。

一处路径勘误：报告写 `develop.c` 时省略了目录，实际在 `src/develop/develop.c`，不在 `src/common/`。

没有核的：九个模块的结构体大小是报告按字段推算的，没有编译验证；各处行号有约 10 行的漂移，报告自己已注明。

lane 的自审：独立复审 `3 error + 13 minor`，均已修订。

## §6 追加：核心设计调研与两个小实测（2026-11-26 凌晨）

核验对象 = `CORE-DESIGN.md`、`CORE-DESIGN-TABLES.md`、`decode-oracle-evidence/`、`decode-spike-src/`。

- **rawspeed 不带拜耳去马赛克**：lane 这一条我核过源码。`rawspeed/src/librawspeed/interpolators/` 只有一个文件，是佳能 sRAW 的插值器；去马赛克在 darktable 自己的 `src/iop/demosaic.c` 和七个 `demosaic_*.cl` 里。所以 rawspeed 路径必须移植 darktable 的去马赛克。
- **去马赛克计时**：`demosaic_bench.log` 里解码 50.7 毫秒，双线性五次中位 27.8 毫秒，MHC 43.4 毫秒，与报告一致。程序是 lane 自己写的两个基线算法，不是 darktable 的 RCD；RCD 的耗时是估算。
- **偏色**：三组对照日志在 `dngfix-cmp-t0/t1/t2.log`。基线 22.784 复现，两次修法都没有改善。根因是 lane 的推断：rawspeed 的相机数据与 Apple 内置的相机配置不是同一个来源。**这条只影响可选的 Core Image 路径。** darktable 自己用的就是 rawspeed 的相机数据，验收对照又是 darktable，所以 darktable 兼容的路径上不存在这个问题。
- **验收对照命令**：官方包的下载地址、大小、sha256 都在 `SOURCES.md`。后端证据行在 `full-runs.log`：CPU 那一路写的是 `NOT utilized`，OpenCL 那一路是 `RCD` 分块、161 个事件全部成功。噪声底线表在 `RESULTS.md`：重复渲染逐像素相同；CPU 与 OpenCL 的平均差约 0.013（16 位最低位），最大差 842 到 904，只落在约 10 个像素上。
- **用户偏好没有被碰**：lane 跑完后 `defaults export org.darktable` 的结果与跑之前的备份逐字节相同。备份文件里是用户的 darktable 设置，我没有让它入库，已从证据目录删掉。
- **清理**：挂载卷已卸载，没有残留的 darktable 进程，安装包与临时目录已删。lane 仓外的 spike 目录留有 1.9 GB，待处理。

没有核的：对照渲染的输出图（约 2.4 GB）已删，我没能复跑一组，只读了日志；lane 的去马赛克基线程序没有逐行读。

**与后来的裁决冲突的两处**，计划里必须改：§6 的仓库布局没有模块自动发现与注册的机制；§7 第 ① 步写的是「参数结构版本为 1、不做旧版本迁移」，与历史兼容的要求相反，参数必须按 darktable 的布局和版本迁移来。

lane 的自审：两份独立复审，`PASS / 3 error + 11 minor` 与 `PASS / 1 error + 10 minor`，均已修订。

## §7 追加：开发计划（2026-11-26 凌晨）

核验对象 = `PLAN.md`、`PLAN-TABLES.md`、`plan-review.log`。

- **用户的 17 条裁决逐条有落点**：`PLAN.md` §1.1 是一张 17 行的对照表，我逐行对过任务书里的裁决清单，没有遗漏。
- **估时加总对**：阶段 A 九波是 1+2+3+1+3+2+1+2+2 = 17 条 lane、43.5 小时；阶段 B 二十波是 76 条 lane、208 小时。合计 29 波、93 条 lane、251.5 小时，与一页纸一致。
- **阶段 A 的九张波次卡我全文读过**。每张都有能机检的验收：顺序夹具 93 条逐位相等、核心里 grep 不到任何模块名、21 个参数结构逐字段比对偏移、对照工具自检复现噪声底线、Apple 模块在非 macOS 构建里零符号、核心接口五条无界面测试、视口探针四项读数。
- **基线版本的更正属实**：上游 `master` 是 `release-5.7.0` 之后 2234 个提交，不是发布版。白平衡模块 `temperature` 在 master 是版本 5，在 5.7.0 和 5.6.2 都是版本 4；`colorin` 在 master 是 8，在两个发布版都是 7。`spektrafilm` 不在 5.7.0 的源码树里，只在 master。计划因此把参数布局和模块顺序钉在 `release-5.7.0`。
- **lane 的自审**：三个复审实例里只有一个出了结论，`PASS / 6 error + 12 minor`，18 项都已处置并记在 §7.3；另两个实例到定稿时没产出。修订后的计划没有再复审一轮。我自己补核了结构四项（裁决落点、加总、阶段 A 卡片、基线版本），没有逐条核阶段 B 的二十张卡片和阶段 C、D 的清单。

**开工前要用户确认的四件事**，都写在计划的相应位置：许可证的精确变体取 GPL-3.0-or-later；Rust 工作区放在仓库根目录，与冻结的 Swift 代码树并存；基线钉 `release-5.7.0`，官方对照包有 5.7.0 就用，没有降到 5.6.2；阶段 A 也每波停下。
