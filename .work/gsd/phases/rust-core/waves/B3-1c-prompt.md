# 执行 lane B3-1c（omp）：转写 hotpixels

## 背景

B3 这一波转写 darktable 的 raw 头段四个模块。上一段（B3-1b，提交 `d4b93c23`）搭好了模块级对照架 `crates/lightamer-oracle`，并用它转写了 `rawprepare`——19 块瓦片对上游逐位相等。你这一段照同一条路转写第二个模块 `hotpixels`：先把它加进对照架，再转写，再逐像素比。

工作目录 `/Volumes/UNITEK/Documents/Development/Lightamer`，HEAD = `d4b93c23`（先亲核；工作树里 `waves/VERIFY.md` 有塔台没提交的改动，不是你的，别碰）。全程中文，代码注释和标识符英文，commit message 英文。

**先读这两个技能文件并照做**：`/Users/kamasylvia/.agents/skills/ponytail/SKILL.md`、`/Users/kamasylvia/.agents/skills/rust-best-practices/SKILL.md`。项目自己的优先级：公开的项写 `///`，其余注释只写为什么；错误类型手写（不引 thiserror / anyhow）；不跟「一个测试只断言一件事」和类型状态；没人要的代码不写。

## 用户已定的几条（不许动）

- 阶段 0 只保证解 A7R5（A-27）。**取样只用** `~/Library/Application Support/Lightamer/TestRAW/7RM5-LosslessCompressedLarge.ARW`（CC0 样张）。样张不在就跳过并写明。**不碰用户的照片库** `/Volumes/UNITEK/Cloud Drive/QSync/Medias/Photos/Workspace`（不读、不列目录）；`/Volumes/UNITEK/Cloud Drive/` 下面一个字都不写。
- darktable 的上游基线钉在 `release-5.7.0`。参考源码只读，在 `/Volumes/UNITEK/Documents/Development/Lightamer-rust-spike/refs/dt-master`，用 `git show release-5.7.0:<路径>` 读。不改它、不构建它、不运行 darktable。**不读** `/Volumes/UNITEK/Documents/Development/darktable` 和 `darktamer` 这两个工作树。
- 模块自动发现、自动注册，不设中央清单。
- GPL 同许可复制纪律：转写来的代码保留 darktable 的版权声明，SPDX 用 `GPL-3.0-or-later`，加一行 `Modified for Lightamer: <日期> <改了什么>`；`NOTICE` 同步。

## 先读

- `crates/lightamer-oracle/README.md`：对照架的结构、「行为替身」表、「加第二个模块」的六步。照它做。
- `crates/lightamer-iop-raw/src/modules/rawprepare/mod.rs` 和 `crates/lightamer-iop-raw/tests/rawprepare_oracle.rs`：上一个模块怎么转写、怎么对上游，是这一段的样板。`.work/gsd/phases/rust-core/waves/B3-1b-REPORT.md` 第一、三、五节。
- `crates/lightamer-iop-traits/src/{module,state,image,lib}.rs`：`IopModule` 签名、`PipeState`、`RawFacts`、`ParamsDesc`。
- 上游 `src/iop/hotpixels.c`（478 行）：参数和数据类型（29–40 行）、`_process_bayer`（105）、`_process_monochrome`（161）、`_process_xtrans`（219）、`process`（327）、`reload_defaults`（358）、`commit_params`（368）、`init_pipe / cleanup_pipe`（387–398）。图形界面函数不取。
- 上游每次处理之前给每个模块按区域派生 CFA 表的函数：`dt_dev_prepare_piece_cfa`（`src/develop/pixelpipe_hb.c:1289`，调用点 `:1391`）。上游判渲染种类的几个判定（`dt_pipe_is_thumb` / `is_export` 一类），自己找到出处。

## 现在的起点

- `hotpixels` 在 `lightamer-iop-raw` 里只有一个描述桩（链序 6，在 `temperature` 之后、去马赛克之前）。
- 链上状态 `PipeState` 里有 CFA 图案（拜耳 2×2 或 X-Trans 表）。B3-1a 定下的做法：上游每次处理前按区域预计算每个模块的 CFA 表，我们让模块按区域偏移查表，要求是纯函数等价。
- `commit` 和 `process` 现在拿不到渲染种类（缩略图 / 预览 / 完整分辨率 / 导出）。
- 上游 `hotpixels` 的参数：`strength`（0–1，缺省 0.25）、`threshold`（0–1，缺省 0.05）、`markfixed`（布尔，缺省关）、`permissive`（布尔，缺省关：三个邻居而不是四个）。提交时：乘数 = 强度的一半；`markfixed` 在缩略图和导出的管线上强制为假；按图像标志定单色两条路；不支持的图像或强度为 0 时这一片被禁用。处理时：先整块拷贝，再分拜耳 / X-Trans / 单色三条路原地修热点；修了几个像素的计数只给图形界面用。

## 要做的

**1. 对照架加第二个模块**（照 README 的六步）。另外两条：

- `dt_dev_prepare_piece_cfa` **原样取进对照架**，照上游在建链和处理之前调用。不许重写它。
- 小管线要能带渲染种类：上游靠管线旗标判缩略图和导出，对照架建链时按调用方给的种类设旗标，Rust 入口加种类参数。新入口 `run_hotpixels`，再加一个两模块链的入口（`rawprepare` → `hotpixels`）。

**2. `commit` 多一个参数：渲染种类。** 原因就是上面那条——`markfixed` 在缩略图和导出时为假，后面的模块还会用到。管线把自己的种类传进去；所有实现机械跟上；加一个测试：同样的参数，预览时 `markfixed` 生效，导出时为假。`process` 的签名不动。

**3. 转写 `hotpixels`**，照上一个模块的六步。要点（以源码为准，和我的读法不一致时以源码为准并在报告里写明）：

- 参数描述用 `ParamsDesc`；校验在 `commit` 里，错误类型手写。
- `commit`：四个值照上游算；CFA 图案取建链时刻状态里的那份（和上游一样是快照）；不适用（不是 RAW 马赛克）或强度为 0 时等价于上游的「禁用」：输出等于输入、不报错，沿用 `rawprepare` 已有的约定。
- `process`：三条检测路逐行转写，浮点一步一步算，不许合并或换序。每个像素的 CFA 颜色按区域偏移查 `PipeState` 里的图案——和上游按区域派生的表逐像素对得上，这是对照测试要证明的。邻居读取只在 `roi_out` 范围内，和上游一样（分块边界上的像素看不到块外，上游也是这样，报告里记一笔，不改）。
- 不做：图形界面；「修了几个像素」的计数（模块接口现在没有回传通道，记进待办，归设置面板那一波）。

**4. 测试**（`crates/lightamer-iop-raw/tests/`）：

- 两模块链（`rawprepare` → `hotpixels`）对上游：真瓦片 4 块（居中、左上角、最亮、最暗），每块里人为点几个热点（孤立的像素设成很高的值）。
- 合成：四种 CFA 位置各一个热点；相邻的一对热点（`permissive` 开和关）；没有热点时逐位不变；X-Trans 表；单色拜耳；强度 0（直通）；`markfixed` 开——预览和导出各一例；非 RAW 马赛克直通。
- 参数：缺省、改阈值、改强度。
- 每块都过门（平均绝对差 < 1/65535，容差 1/65535 内占比 > 0.9999）；最大绝对差写进报告。这几条路是比大小和取最大值，应该是逐位相等。

**5. 演示脚本**：如果哪个演示或 bench 用了 `hotpixels` 的假参数，照 B3-1b 报告第十节的办法改成真参数。

**6. 清掉对照库的 C 警告。** 塔台重跑时构建日志里有 28 行来自对照库构建脚本的警告（`upstream/rawprepare_gainmaps.inc` 的符号比较两处、`rawprepare_pipe.inc` 和 `rawprepare_roi.inc` 的未用参数六处）。它们都在逐字的上游代码里，改不了。做法：编上游片段时关掉这两类警告（或整段 `-w`），自己写的胶水和替身保留警告；加完第二个模块之后，`cargo build -p lightamer-oracle` 和 `cargo doc --workspace` 的输出里不许再有来自这个 crate 的警告行。

## 每一步的内存约束

- 测试只用瓦片，不用整帧；取瓦片用解码 crate 的 `pipe_input(region)`，不要先转整帧（整帧 244 MB，解码峰值约 900 MB）。同一个测试二进制里不许并发加载多张。
- 转写的 `process` 除了 rayon 的行并行之外不额外分配；提交数据是固定大小的栈数据。

## 验收清单（命令和输出写进报告）

- `cargo test --workspace --locked --no-fail-fast -j6` 绿、零失败；测试总数不少于 775 加上你新增的（逐个列出）。`rawprepare` 的对照测试一个不改、照旧通过。
- 六条不崩溃 lint（`CARGO_INCREMENTAL=0`，`-D warnings`）和文档零警告；`cargo fmt --all --check`；`cargo xtask layers`、`check-order-sync`、`check-no-iop-names`、`Scripts/check-licenses.sh` 通过。
- 五个演示脚本都退出 0（`Scripts/rust-session-demo.sh`、`rust-history-demo.sh`、`rust-render-demo.sh`、`rust-decode-demo.sh`、`rust-stream-demo.sh`）。机器上可能有别人自己的重活，负载高时计时步骤会报「测不准」，等它重试，不要绕。
- `LIGHTAMER_DT_REF=<参考克隆> tools/extract.sh hotpixels --check` 逐字节一致；`rawprepare --check` 照旧一致。
- 全部瓦片过门；最大绝对差写进报告。
- `lightamer-iop-raw::lookup_implemented("hotpixels")` 查得到，描述表和 registry 里都有。
- `git show --name-only HEAD` 只含「纪律」里允许的路径；不新增依赖，`Cargo.lock` 不变。

## 产物先落盘，再收尾

代码第一次全绿就提交；之后每完成一小块提交一次，最后 squash 成一个（Conventional Commits，subject 用 `feat(rust-core): …`，body 写 what + why，带 `refs #32`）。绿之前离开要留带路径的 stash 说明。

**退出顺序**：先填完报告 `waves/B3-1c-REPORT.md` → 再起一个 `omp -p` 实例做只读自审（隔离：只读产物，不读你的过程；第一行写结论头 `PASS / N error + N minor`；发现回写 `waves/B3-1c-review.log`）→ 有发现就修，修法记进报告的一节「复审」→ 把报告和复审日志并进那一个提交 → 删掉临时文件 → 退出。复审日志一个字不改。自审的任务书不要放进提交。

## 纪律

- **只允许新增或修改这些路径**：`crates/lightamer-oracle/`、`crates/lightamer-iop-raw/`、`crates/lightamer-iop-traits/`（只许加渲染种类的参数和类型）、`crates/lightamer-pipeline/`、`crates/lightamer-engine/`、`crates/lightamer-testkit/`、`apps/lightamer-cli/`（演示和 bench 里跟着签名或参数改）、`Scripts/rust-*-demo.sh`（只许按第 5 条改参数）、`docs/PIPELINE.md`（只许补一两句）、`NOTICE`（有新条目才动）、`.work/gsd/phases/rust-core/waves/B3-1c-REPORT.md` 和 `B3-1c-review.log`。其它一律不动。
- 命令被移到后台就轮询等它结束，**不许在后台作业还没结束时收工**。
- 构建之前跑一次 `Scripts/machine-guard.sh` 并记录输出。并行度 6 以内。不用 `caffeinate`。一次只跑一个重活。
- 不跑 Swift 的构建和测试，不打开任何图形程序，不运行 `darktable`，不下载安装任何软件。不读、不打印任何凭据文件。机器上别人的 omp 会话和重活，不碰。
- `.work/` 下以前各波留下的未跟踪文件不碰也不提交。
- 新文件带 SPDX 头（`// SPDX-License-Identifier: GPL-3.0-or-later`）。
- 数字不编。哪一项没做成，写没做成和卡在哪一步。上游那块拿不准的，写清楚你的读法和依据。总墙钟不超过 4 小时。

## 交付

一个提交；`waves/B3-1c-REPORT.md`（对照架加了什么、原样取了哪些行、CFA 按区域派生怎么对上的、转写做了哪些没做哪些、每块瓦片的门限和最大绝对差、验收清单每条的命令与输出）；`waves/B3-1c-review.log`。stdout 最后一条消息一次性完整输出：结论、新增测试清单、没做的、commit 哈希。
