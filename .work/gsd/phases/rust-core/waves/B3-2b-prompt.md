# 执行 lane B3-2b（omp）：转写 highlights，第一部分（剪切、LCH 外推、对向）

## 背景

B3 这一波转写 darktable 的 raw 头段四个模块。对照架 `crates/lightamer-oracle` 已经搭好，`rawprepare`、`hotpixels`、`temperature` 已经转写并逐像素对过上游。`highlights` 是最后一个，也是最大的一个：上游主文件 1352 行，外加六个体积不小的算法文件。它拆成两段，你这一段做模块本体和前三个方法；小波重建那一个方法归下一段。

钉住的 `release-5.7.0` 里 `highlights` 有六个处理方法：剪切、LCH 外推、小波重建、补绘、基于分割、对向（缺省）。这一段转写**剪切、LCH 外推、对向**三个。

工作目录 `/Volumes/UNITEK/Documents/Development/Lightamer`，HEAD 是上一段（B3-2a）的提交，先亲核（工作树里 `waves/VERIFY.md` 有塔台没提交的改动，不是你的，别碰）。全程中文，代码注释和标识符英文，commit message 英文。

**先读这两个技能文件并照做**：`/Users/kamasylvia/.agents/skills/ponytail/SKILL.md`、`/Users/kamasylvia/.agents/skills/rust-best-practices/SKILL.md`。项目自己的优先级：公开的项写 `///`，其余注释只写为什么；错误类型手写（不引 thiserror / anyhow）；不跟「一个测试只断言一件事」和类型状态；没人要的代码不写。

## 用户已定的几条（不许动）

- 阶段 0 只保证解 A7R5（A-27）。**取样只用** `~/Library/Application Support/Lightamer/TestRAW/7RM5-LosslessCompressedLarge.ARW`（CC0 样张）。样张不在就跳过并写明。**不碰用户的照片库** `/Volumes/UNITEK/Cloud Drive/QSync/Medias/Photos/Workspace`（不读、不列目录）；`/Volumes/UNITEK/Cloud Drive/` 下面一个字都不写。
- darktable 的上游基线钉在 `release-5.7.0`。参考源码只读，在 `/Volumes/UNITEK/Documents/Development/Lightamer-rust-spike/refs/dt-master`，用 `git show release-5.7.0:<路径>` 读。不改它、不构建它、不运行 darktable。**不读** `/Volumes/UNITEK/Documents/Development/darktable` 和 `darktamer` 这两个工作树。
- 模块自动发现、自动注册，不设中央清单。
- GPL 同许可复制纪律：转写来的代码保留 darktable 的版权声明，SPDX 用 `GPL-3.0-or-later`，加一行 `Modified for Lightamer: <日期> <改了什么>`；`NOTICE` 同步。

## 先读

- `crates/lightamer-oracle/README.md` 和前两段的报告（`waves/B3-1c-REPORT.md`、`waves/B3-2a-REPORT.md`）：第四个模块怎么加进对照架、逐像素查 CFA 的写法、三模块链的入口。
- `crates/lightamer-iop-traits/src/{module,state,image,kind,stats}.rs`：`IopModule` 现在的签名（`commit` 带链上状态和渲染种类，`process` 带链上状态）、`roi_out / roi_in / tiling`、`stats()` 和整图需求的表达方式。
- `crates/lightamer-pipeline/src/{render,stream}.rs`：模块要求的输入区域盖不住时怎么拒绝（分了类型的拒绝、分配之前）；模块的临时平面怎么从预算里领（仓库里现成的领法）。
- 上游 `src/iop/highlights.c`：参数和枚举（40–165 行）、`modify_roi_out / modify_roi_in`（342–389）、`tiling_callback`（390–462）、`process_clip`（707）、`process`（814–1010）、`commit_params`（1011）、`init_pipe / cleanup_pipe`（1103）、`reload_defaults`（1201）；它include 的算法文件 `src/iop/hlreconstruct/lch.c`（270 行）和 `opposed.c`（588 行）；它们用的纯头文件 `src/common/box_filters.h`、`bspline.h`、`fast_guided_filter.h`。

## 我的读法（以源码为准，不一致时以源码为准并在报告里写明）

- 模块在显示效果那个 crate 里（`lightamer-iop-display`），链序 4：`rawprepare`（1）→ `temperature`（3）→ **`highlights`（4）** → `hotpixels`（6）→ 去马赛克（8）。
- 参数照上游的表：方法、强度、剪切阈值、噪声水平、迭代次数、小波直径、候选、合并、重建模式、纯色；两个写着「未用」的 `blendL / blendC` 也留着（以后对 dt 的历史）。
- 提交：参数原样进数据；不是 RAW 的图像一律按剪切处理。
- 处理读**处理时刻**链上的四路最大值（乘上剪切阈值当裁切线），所以它排在 temperature 之后、读的是乘过白平衡系数的值。
- **对向法要看整张图**：`modify_roi_in` 对对向法把输入区域设成整张（尺度 1），上游也因此不允许它分块。剪切和 LCH 是局部的。
- 六个方法里另外三个（小波重建、补绘、基于分割）这一段**不转写**：参数选到它们时返回分了类型的拒绝，绝不许悄悄按剪切处理。小波重建归下一段；补绘和基于分割做不做由用户定。

## 要做的

**1. 对照架加第四个模块**（照 README）。原样取：`highlights.c` 的非图形界面部分、`lch.c` 和 `opposed.c` 整个文件、三个纯头文件。为了让原样的 `process` 链接通过，它调到的其它几个方法的 C 文件（小波、补绘、分割）如果便宜就一并原样编进去（只是编译 C，不是转写），需要更多替身的话在报告里写明取了哪些、替了什么。`process` 里图形界面专用的可视化和蒙版广播那两段不取（替身让它恒为关）。Rust 入口 `run_highlights` 和三模块链的入口（`rawprepare` → `temperature` → `highlights`）。

**2. 转写 `highlights`**（`crates/lightamer-iop-display/src/modules/highlights/`）：

- 参数描述用 `ParamsDesc`；枚举参数照仓库里已有的做法；校验在 `commit` 里，错误类型手写。
- `commit`、`process` 的剪切路（拜耳和 X-Trans）、LCH 路（拜耳和 X-Trans）、对向路（拜耳和 X-Trans）逐行转写。浮点一步一步算，不许合并或换序；逐像素的 CFA 颜色按区域偏移查链上状态里的图案；逐行用 rayon，归约照上游。
- `roi_in / roi_out / tiling`：对向法要整张图，照上游表达；剪切和 LCH 照上游（余量为 0）。
- 临时平面**从预算里领**，不许裸分配；领不到是分了类型的失败，不许悄悄少开。
- 这一段不做的输入：非马赛克的输入（普通图片、线性 RAW）——遇到时返回分了类型的拒绝。上游对这类输入走的是另一条路，留给普通图片的输入来源那一波。
- 不做：图形界面；蒙版；OpenCL；可视化的数据广播；小波重建、补绘、基于分割三个方法的转写。

**3. 测试**（`crates/lightamer-iop-display/tests/`）：

- 三模块链对上游。对向法要整张图，所以每块瓦片都当成「一整张图」来比。真样张取 4 块（居中、左上角、最亮、最暗，各 256×256），其中两块人为做出过曝（把一小块的像素设到白点）。剪切、LCH、对向三个方法各比一遍，缺省参数加几组改过的（剪切阈值 0.5 / 1.0 / 2.0、强度 0 / 0.5 / 1.0）。
- 合成：单通道过曝、两通道过曝、三通道全过曝、不过曝时逐位不变、拜耳和 X-Trans 各一套、`solid_color` 开和关。
- 链上状态：处理前后四路最大值两边相等。
- 流式：对向法在流式那条路上被分了类型的拒绝，且发生在任何分配之前（走管线的流式入口测）；剪切和 LCH 在流式路上能跑，结果和整帧逐字节相等。
- 选到没转写的方法：分了类型的拒绝。
- 每块都过门（平均绝对差 < 1/65535，容差 1/65535 内占比 > 0.9999）。LCH 和对向里有幂、指数、对数，两边调的都是系统的同一个数学库，但 Rust 和 C 不保证逐位相同——**最大绝对差和逐位相等的比例都要写进报告**；差得比最后几位大要解释。

**4. 量一下对向法的内存。** 读代码数出它在峰值时同时活着几张和输入一样大的浮点平面；再用一块 15 MP 左右的样张区域（当成整张图）跑一遍对向法，`/usr/bin/time -l` 量**峰值常驻**和**峰值占用**。两个数和推算写到 A7R5 整帧（61 MP）会是多少，写进报告。

**5. 演示脚本**：如果哪个演示或 bench 用了 `highlights` 的假参数，照 B3-1b 报告第十节的办法改成真参数。

## 每一步的内存约束

- 对向法在整帧上跑时，临时平面加输入输出都是 244 MB 一张（A7R5）；全部走预算，预算不够就分了类型的失败。这一段把它量出来。
- 测试只用瓦片；15 MP 那一次量数单独跑、串行，不要和别的加载样张的测试并发。
- 流式路：对向法的拒绝必须发生在分配之前。

## 验收清单（命令和输出写进报告）

- `cargo test --workspace --locked --no-fail-fast -j6` 绿、零失败；测试总数不少于上一段的总数加上你新增的（逐个列出）。前三个模块的对照测试一个不改、照旧通过。
- 六条不崩溃 lint（`CARGO_INCREMENTAL=0`，`-D warnings`）和文档零警告；`cargo fmt --all --check`；`cargo xtask layers`、`check-order-sync`、`check-no-iop-names`、`Scripts/check-licenses.sh` 通过。
- 五个演示脚本都退出 0（`Scripts/rust-session-demo.sh`、`rust-history-demo.sh`、`rust-render-demo.sh`、`rust-decode-demo.sh`、`rust-stream-demo.sh`）。机器上可能有别人自己的重活，负载高时计时步骤会报「测不准」，内存紧时守卫会拦，等它，不要绕。
- `LIGHTAMER_DT_REF=<参考克隆> tools/extract.sh highlights --check` 逐字节一致；前三个模块的 `--check` 照旧一致。
- 全部瓦片过门；最大绝对差和逐位相等的比例写进报告。
- `lightamer-iop-display::lookup_implemented("highlights")` 查得到，描述表和 registry 里都有。
- `git show --name-only HEAD` 只含「纪律」里允许的路径；不新增依赖，`Cargo.lock` 不变。

## 产物先落盘，再收尾

代码第一次全绿就提交；之后每完成一小块提交一次，最后 squash 成一个（Conventional Commits，subject 用 `feat(rust-core): …`，body 写 what + why，带 `refs #32`）。绿之前离开要留带路径的 stash 说明。

**退出顺序**：先填完报告 `waves/B3-2b-REPORT.md` → 再起一个 `omp -p` 实例做只读自审（隔离：只读产物，不读你的过程；第一行写结论头 `PASS / N error + N minor`；发现回写 `waves/B3-2b-review.log`）→ 有发现就修，修法记进报告的一节「复审」→ **修完之后把全套测试、lint、文档、五个演示、`--check` 重跑一遍**（上一段偷了这一步）→ 把报告和复审日志并进那一个提交 → 删掉临时文件 → 退出。复审日志一个字不改。自审的任务书不要放进提交。

## 纪律

- **只允许新增或修改这些路径**：`crates/lightamer-oracle/`、`crates/lightamer-iop-display/`、`crates/lightamer-iop-traits/`（只有在必须补一道缝的时候，改了要写明为什么）、`crates/lightamer-pipeline/`（只有在必须补一道缝的时候）、`crates/lightamer-testkit/`、`apps/lightamer-cli/` 和 `Scripts/rust-*-demo.sh`（演示和 bench 里跟着改参数）、`docs/PIPELINE.md`、`NOTICE`、`.work/gsd/phases/rust-core/waves/B3-2b-REPORT.md` 和 `B3-2b-review.log`。其它一律不动。
- 命令被移到后台就轮询等它结束，**不许在后台作业还没结束时收工**。
- 构建之前跑一次 `Scripts/machine-guard.sh` 并记录输出。并行度 6 以内。不用 `caffeinate`。一次只跑一个重活。
- 不跑 Swift 的构建和测试，不打开任何图形程序，不运行 `darktable`，不下载安装任何软件。不读、不打印任何凭据文件。机器上别人的 omp 会话和重活，不碰。
- `.work/` 下以前各波留下的未跟踪文件不碰也不提交。
- 新文件带 SPDX 头（`// SPDX-License-Identifier: GPL-3.0-or-later`）。
- 数字不编。哪一项没做成，写没做成和卡在哪一步。上游那块拿不准的，写清楚你的读法和依据。总墙钟不超过 6 小时。

## 交付

一个提交；`waves/B3-2b-REPORT.md`（对照架加了什么、原样取了哪些行、三个方法各做了哪些、对向法的内存两个数和推算、每块瓦片的门限、最大绝对差和逐位比例、验收清单每条的命令与输出）；`waves/B3-2b-review.log`。stdout 最后一条消息一次性完整输出：结论、新增测试清单、没做的、commit 哈希。
