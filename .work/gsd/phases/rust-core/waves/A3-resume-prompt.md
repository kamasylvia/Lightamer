# 执行 lane A3（续做，omp）：模块描述与自动发现注册

## 背景：这是一次续做

这一波之前派过，任务书是 `.work/gsd/phases/rust-core/waves/A3-prompt.md`。上一条 lane 做到一半时，用户下令暂停全部执行，它被停下，没有提交。现在用户已经定了架构、下令恢复，它的半成品已经原样恢复到了工作区里。**你把它做完。**

**原来那份任务书全文有效，先完整读一遍。** 下面只写续做要知道的状态和此后的变化。

工作目录 `/Volumes/UNITEK/Documents/Development/Lightamer`。HEAD 先亲核并记录。全程中文，代码注释和标识符英文，commit message 英文。这一波**不写任何像素处理**，不碰 `dt-core` 和 `dt-api`。

## 塔台看到的状态

这些只是塔台看了一眼，**每一条你都要自己核**。半成品里可能有写了一半的文件、对不上的地方。

- 开始时 `git status --porcelain` 里有 13 个改动过的已跟踪文件，`crates/` 下有 13 项未跟踪的新文件。这些都是上一条 lane 留下的，是你的起点，不是别人的改动。
- `cargo check --workspace --offline` 现在能通过。
- 夹具 `crates/dt-registry/fixtures/dt-order-679d594f5d.json` 和同目录的 `README.md` 已经有了。
- 四个域 crate 里都有了构建脚本，也都有了模块桩目录：`dt-iop-raw` 8 个，`dt-iop-geom` 21 个，`dt-iop-color` 22 个，`dt-iop-display` 52 个。
- `dt-registry` 的 `src/` 下只有 `lib.rs`，没有看到测试。
- `crates/xtask/src/main.rs` 有 133 行。
- 没有看到 `Scripts/rust-discovery-probe.sh`，没有看到波次报告和复审日志。

照原任务书对照，至少这些还没做完：注册表里的四类测试（raw 顺序链、jpg 顺序链、行内序对调的负测、标识不重复）；`xtask` 的三个子命令（生成桩和夹具、同步检查、查核心里有没有模块名）；探针脚本和它用的测试；`crates/README.md` 的更新；报告、自审、提交。实际差多少，以你核对出来的为准。已经做对的部分保留，不要推倒重来。

## 原任务书之后的变化

读 `.work/gsd/phases/rust-core/PLAN-AMENDMENTS.md` 的 A-12 和 A-15。和这一波有关的只有一条：

- **darktable 的历史兼容不再是需求**，我们自己的修改历史只存进会话数据库，格式是我们自己的。所以**模块描述里的参数描述不要按 C 结构体的布局来建**：不要字节大小，不要字段偏移，不要迁移函数的位置，也不要把 darktable 的模块版本号当成「当前版本」。参数描述写成给我们自己的设置模型用的样子：每个参数一个名字、一个类型，字段先空着不填。标识（就是 darktable 的 op 名）、顺序键、标志位、所属分组，照原样。
- 顺序夹具不变，基线仍是上游 `master` 的提交 `679d594f5d`。

其余全部不变：第 6 节的验收清单、omp 域内自审、纪律一节允许改的路径、一个 commit 并带 `refs #32`、零 push。

## 续做要多做的一步

动手之前，先把半成品过一遍，在报告里写一节「接手时的状态」：哪些文件在、各自完成到什么程度、你发现了哪些问题、哪些留用、哪些重写。接手后发现的错误算这一波的，修掉。

## 交付

和原任务书相同：代码、测试、夹具、脚本和一个 commit；`.work/gsd/phases/rust-core/waves/A3-REPORT.md`（加「接手时的状态」一节）和 `A3-review.log`。总墙钟不超过 200 分钟，含自审。

stdout 最后一条消息一次性完整输出报告内容。
