# 执行 lane B3-1a（omp）：链上状态——模块之间沿链传递的事实

## 背景

B3 这一波转写 darktable 的 raw 头段四个模块（`rawprepare` / `hotpixels` / `highlights` / `temperature`）。读上游源码发现，这些模块不是孤立的：它们沿链读写一份共享状态 `pipe->dsc`。举两个实侤断：

- `rawprepare` 的 `process`（`src/iop/rawprepare.c:324` 起）处理完一块，会把 `pipe->dsc.processed_maximum` 四路都置成 `1.0f`，并把随裁切调整过的 CFA 图案写回 `pipe->dsc.filters` 和 `pipe->dsc.xtrans`。
- `highlights` 读 `dsc.processed_maximum`（15 处）和 `dsc.temperature`（4 处，`temperature` 写的）；`hotpixels` 读 `dsc.filters`。

我们的模块接口没有这个通道：`commit(&self, params, image)` 和 `process(&self, data, input, output, rin, rout)` 都拿不到上游留下的事实。下一波的去马赛克也要读 `rawprepare` 写回去的 CFA 图案。**现在仓库里还没有真模块**（只有测试和演示里的模块），是加这个参数最便宜的时候。你这一段只做这个机制，不转写任何模块。

**这份状态是渲染时的临时量，不落库、不跨请求保留**（用户 2026-11-28 明确问过，答案是「不用数据库」）。库里只存用户的编辑历史。

工作目录 `/Volumes/UNITEK/Documents/Development/Lightamer`，HEAD = `1b6b17a9`（先亲核；工作树里 `waves/VERIFY.md` 有塔台没提交的改动，不是你的，别碰）。全程中文，代码注释和标识符英文，commit message 英文。

**先读这两个技能文件并照做**：`/Users/kamasylvia/.agents/skills/ponytail/SKILL.md`、`/Users/kamasylvia/.agents/skills/rust-best-practices/SKILL.md`。项目自己的优先级：公开的项写 `///`，其余注释只写为什么；错误类型手写（不引 thiserror / anyhow）；不跟「一个测试只断言一件事」和类型状态；没人要的代码不写。

## 用户已定的几条（不许动）

- darktable 的上游基线钉在 `release-5.7.0`。参考源码只读，在 `/Volumes/UNITEK/Documents/Development/Lightamer-rust-spike/refs/dt-master`，用 `git show release-5.7.0:<路径>` 读。不改它、不构建它、不运行 darktable。**不读** `/Volumes/UNITEK/Documents/Development/darktable` 和 `darktamer` 这两个工作树。
- 这一段用合成数据，不用样张。不碰用户的照片库。

## 先读

- `docs/PIPELINE.md`。
- `crates/lightamer-iop-traits/src/{module,image,lib}.rs`：`IopModule` 特征、`ImageInfo`、`RawFacts`（上一波 B3-0a 加的）、`CfaPattern`。
- `crates/lightamer-pipeline/src/{render,cache,chain,stream,spill}.rs`：链怎么建（哪里调 `commit`）、怎么逐节点处理（哪里调 `process`）、平面缓存和链式键、从缓存平面接着算、流式那条路。
- `crates/lightamer-engine/src/render.rs`；`crates/lightamer-testkit/src/`；`apps/lightamer-cli/src/`：所有实现了 `IopModule` 的地方（`git grep -n 'impl IopModule for'`）。
- 上游怎么管这份状态，**逐处读并记下行号**：
  - `src/develop/pixelpipe_hb.c` 约 300–345 行：初始化（335 行把 `processed_maximum` 置 `1.0f`）。
  - 同文件约 1990–2060 行：建链期每个模块之后 `pipe->dsc = piece->dsc_out`（2006、2052 行）。
  - 同文件约 1440–1520 行和 2440–2535 行：处理期整帧和分块调 `module->process` / `process_tiling` 的前后，对 `dsc` 做了什么——**每块开始时是重置回建链期的终值，还是接着上一块留下来的值**，这一条要从源码读出结论，写进报告和文档。
  - 四个模块读写 `dsc` 的全部位置。已知的字段：`filters`、`xtrans`、`channels`、`datatype`、`processed_maximum`、`temperature` 子结构。

## 现在的起点

- `IopModule::commit(&self, params: &Map<String, Value>, image: &ImageInfo) -> Result<CommitData, PipeError>`；`process(&self, data, &CommitData, input: &Plane, output: &mut PlaneMut, rin: Roi, rout: Roi) -> Result<(), PipeError>`。
- `ImageInfo` 带可选的 `RawFacts`（黑位、白点、白平衡、颜色矩阵、CFA 图案、裁切等）和 `format`。
- 管线有逐节点的平面缓存和链式键，可以从缓存平面接着往后算；流式那条路逐块走同一条链。

## 要做的

**1. 把上游的模型写清楚。** 一张表：每个字段——谁在什么时候读（建链期还是处理期）、谁在什么时候写；建链期和处理期是不是同一份状态接着用；分块时每块从什么值出发。放在报告里，并浓缩成一节写进 `docs/PIPELINE.md`（标题「链上状态」）。拿不准的地方去读源码，不要猜。

**2. 新类型。** 在 `lightamer-iop-traits` 里加链上状态（纯数据、固定大小、`Copy`，**不引入堆分配**）。字段**只建这四个模块和去马赛克实际读写的**：CFA 图案（用已有的 `CfaPattern`，不用 dcraw 的位模式）、X-Trans 表、输入缓冲的通道数和数据类型、四路最大值、`temperature` 写、`highlights` 读的那些值。没有模块读写的字段不加，不预先留位。

**3. 改签名。** `commit` 和 `process` 各多一个参数：`state: &mut <链上状态>`。更新所有实现（测试模块、演示、测试工具），机械改动，行为不变。

**4. 管线照上游的语义接上。**
- 起点：从图像事实初始化（照上游初始化那处：四路最大值为 1.0，CFA 图案和 X-Trans 表来自图像）。
- 建链期：按链序把同一个状态以可变引用逐个模块传下去。
- 处理期：每块（或整帧）从**建链期的终值**出发——这是我的读法，**以你从源码读出的结论为准**；如果上游不是这样，照上游做，并在报告和文档里写明差别。
- **和缓存对上**：从第 k 个节点的缓存平面接着往后算时，后面的模块要看到的状态必须是「算到第 k 个节点为止」的值。做法：每个缓存的平面旁边存一份那个节点处理完之后的状态（同样几十个字节）。这是这一段最关键的一条，必须有测试。
- 流式那条路同样处理。

**5. 测试**（列出每个测试钉的是什么）：
- 一个测试模块在建链期和处理期各写一个值，下游一个模块读：下游读到上游写的值，顺序对；上游不在链上时下游读到起点值。
- 两块：每块从同一个建链期终值出发（或按你从源码读出的语义）。
- **缓存续算**：下游的结果依赖上游写的状态；第一次算、缓存命中上游平面后再算，两次下游的输出逐字节相等。
- 流式路同样一例。
- 不碰状态的模块：输出逐字节不变（旧测试的断言一行不改，只跟着签名加参数）。

## 每一步的内存约束

- 状态固定大小、在栈上，每个渲染作业一份；每个缓存平面多存一份（几十字节）。
- 不许因为加状态而产生新的堆分配或新的 Arc。
- 作业取消、平面被驱逐时，状态跟着平面走，没有别的持有者。

## 验收清单（命令和输出写进报告）

- `cargo test --workspace --locked --no-fail-fast -j6` 绿、零失败；测试总数不少于 737 加上你新增的（逐个列出）。旧测试函数体除跟着签名加参数之外不改。
- 六条不崩溃 lint（`CARGO_INCREMENTAL=0`，`-D warnings`）和文档零警告；`cargo fmt --all --check`；`cargo xtask layers`、`check-order-sync`、`check-no-iop-names`、`Scripts/check-licenses.sh` 通过。
- 五个演示脚本都退出 0（`Scripts/rust-session-demo.sh`、`rust-history-demo.sh`、`rust-render-demo.sh`、`rust-decode-demo.sh`、`rust-stream-demo.sh`）。机器上可能有别人自己的重活，负载高时计时步骤会报「测不准」，等它重试，不要绕。
- `docs/PIPELINE.md` 有「链上状态」一节。
- `git show --name-only HEAD` 只含「纪律」里允许的路径；`Cargo.lock` 不变（这一段不需要新的 crate 依赖边）。

## 产物先落盘，再收尾

代码第一次全绿就提交；之后每完成一小块提交一次，最后 squash 成一个（Conventional Commits，subject 用 `feat(rust-core): …`，body 写 what + why，带 `refs #32`）。绿之前离开要留带路径的 stash 说明。

**退出顺序**：先填完报告 `waves/B3-1a-REPORT.md` → 再起一个 `omp -p` 实例做只读自审（隔离：只读产物，不读你的过程；第一行写结论头 `PASS / N error + N minor`；发现回写 `waves/B3-1a-review.log`）→ 有发现就修，修法记进报告的一节「复审」→ 把报告和复审日志并进那一个提交 → 删掉临时文件 → 退出。复审日志一个字不改。自审的任务书不要放进提交。

## 纪律

- **只允许新增或修改这些路径**：`crates/lightamer-iop-traits/`、`crates/lightamer-pipeline/`、`crates/lightamer-engine/`、`crates/lightamer-testkit/`、`apps/lightamer-cli/`、`docs/PIPELINE.md`、`.work/gsd/phases/rust-core/waves/B3-1a-REPORT.md` 和 `B3-1a-review.log`。其它一律不动。
- 命令被移到后台就轮询等它结束，**不许在后台作业还没结束时收工**。
- 构建之前跑一次 `Scripts/machine-guard.sh` 并记录输出。并行度 6 以内。不用 `caffeinate`。一次只跑一个重活。
- 不跑 Swift 的构建和测试，不打开任何图形程序，不运行 `darktable`，不下载安装任何软件。不读、不打印任何凭据文件。机器上别人的 omp 会话和重活，不碰。
- `.work/` 下以前各波留下的未跟踪文件不碰也不提交。
- 新文件带 SPDX 头（`// SPDX-License-Identifier: GPL-3.0-or-later`）。
- 数字不编。哪一项没做成，写没做成和卡在哪一步。上游语义那块拿不准的，写清楚你的读法和依据。总墙钟不超过 4 小时。

## 交付

一个提交；`waves/B3-1a-REPORT.md`（字段表——谁读谁写、什么时候；分块时的语义和源码依据；和缓存怎么对上；留下了什么没做；验收清单每条的命令与输出）；`waves/B3-1a-review.log`。stdout 最后一条消息一次性完整输出：结论、新增测试清单、没做的、commit 哈希。
