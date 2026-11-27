# 修复 lane B1d-c（omp）：流式作业不许先取整帧——只探尺寸、按区域取输入；管线交出一个按区域取输入的流式入口

## 背景

B1d（整链行带流式）两段都已做完：管线这一侧（B1d-a，提交 `e5f9c300`）、引擎这一侧（B1d-b，提交 `1bc3e1cc`）。用户的裁决（修订 A-24）：**内存里只留带或方块、不留整帧**。

塔台核 B1d-b 时发现引擎这条路没有做到：它的「这台机器上的上限表」里，两亿像素的图走引擎的流式，条带模式的峰值常驻是 4.58 GB，五亿像素约 7 GB——而管线自己的测试里同一张图只要 66 MB。读代码找到原因：

- 引擎的渲染作业**总是先整帧取出输入**（为了知道画面多大），拿去跑整帧入口；放不下了，才把整帧丢掉、改走流式。于是峰值内存跟着帧的大小涨，和流式的目的正相反。
- 流式那一段，引擎自己又规划了一遍，然后每一块调一次管线的流式入口——两层规划套在一起。

**根子在塔台的任务书**：B1d-a 让流式入口的请求里带着整帧的画面，B1d-b 没有写明「流式作业不许整帧取输入」。你是一条短的修复 lane。

**先读这两个技能文件，并照做**：`/Users/kamasylvia/.agents/skills/ponytail/SKILL.md`、`/Users/kamasylvia/.agents/skills/rust-best-practices/SKILL.md`。两个技能打架的地方：公开的项写 `///`，其余的注释只写为什么；错误类型保持手写。不跟：一个测试只断言一件事、用类型编码状态。项目自己的门优先。

先读（都在 `.work/gsd/phases/rust-core/` 下，除非写了别的路径）：

- `PLAN-AMENDMENTS.md` 的 A-24。`waves/B1db-REPORT.md`（「超限自动转的规则」「这台机器上的上限表」两节）。`waves/VERIFY.md` 的最后两节。
- `docs/PIPELINE.md`（仓库根下）的「行带流式」一节。
- `crates/lightamer-pipeline/src/stream.rs`（`Pipe::render_stream`、`plan_stream`、它怎样取每一块的输入）和 `render.rs` 的 `RenderRequest`。
- `crates/lightamer-engine/src/render.rs`：渲染作业开头整帧取输入的地方，和 `run_stream_fallback`。

工作目录 `/Volumes/UNITEK/Documents/Development/Lightamer`。HEAD 先亲核并记录。全程中文，代码注释和标识符英文，commit message 英文。

## 要做的

**1. 管线：按区域取输入的流式入口。** 管线 crate 里定一个很小的 trait：给它一块区域，它交出那一块的画面。再加一个入口：请求里**不带整帧画面**，带这个来源——管线自己规划一次，逐块向来源要输入、跑完整条链、交给接收者。现有的 `render_stream`（请求里带整帧画面的那个）保留，改成经这个入口实现（来源 = 整帧裁一块），B1d-a 的测试一个不改。整帧入口 `render` 一个字不改。

**2. 引擎：只探尺寸，不取像素。**

- 给输入来源加一个「探」的办法：交出这张画面的图像信息和整幅尺寸，**不取像素**。默认实现是整帧取出来、只留下信息（现有的来源行为不变）；自己写的来源可以便宜地答。
- 渲染作业的次序改成：先探尺寸 → 如果这种实例会自动转流式、并且整幅放不下（拿管线交出的「最大帧」比）→ **直接走流式**，来源就是「按区域取输入」；否则才整帧取输入、跑整帧入口（和现在一样）。
- **流式这一条路一次都不许整帧取输入。**
- `run_stream_fallback` 里那一套引擎自己规划、逐块调用的循环删掉：规划归管线，引擎只把来源和接收者接上。

**3. 重测上限表。** 两种模式各量几档（两亿到五亿五千万像素），发行版、串行。预期：峰值常驻不再跟着帧的大小涨——条带模式是几十 MB 加拼装的缓冲，方块模式在 1 GB 以内——一直到最后撞磁盘上限。把新表和 B1d-b 的旧表并排写进报告。表里的每一行都要是你自己量的；负载高时常驻内存的数会抖，多量两遍取稳的。

**4. 测试。** 默认的「探」等于整帧取出来再取信息（逐值相同）；流式作业整帧取输入的次数是零、按区域取的次数不少于块数（用计数的来源）；同一张小图走流式和走整帧逐字节相同；自动转的决定是按探到的尺寸做的、在取任何像素之前；取消和取代的规则不变；删掉的那套循环没有测试还在依赖它。

## 验收清单（命令和输出都写进报告）

- `cargo test -p lightamer-pipeline --locked`、`cargo test -p lightamer-engine --locked`、`cargo test -p lightamer-cli --locked` 绿。
- `cargo test --workspace --locked --no-fail-fast` 绿，零失败；测试数不少于起点减去随删掉的循环一起去掉的测试（逐个列出）。
- B1d-a 已有的测试一个没改（ diff 里它们的断言不动）。
- 整帧入口 `render` 的函数体一个字不改。
- `rg -n 'std::fs|create_dir|read_dir|std::fs::copy|fs::copy|File::create|tempfile' crates/lightamer-engine/src` 没有输出。
- 六条不崩溃 lint（用 `CARGO_INCREMENTAL=0`）和文档零警告；`cargo xtask layers` 等检查通过；`Scripts/check-licenses.sh` 退出 0（不新增依赖）。
- 历史模型、注册表、会话库、模块桩、Apple 模块都没变。
- `Scripts/rust-stream-demo.sh` 打印的峰值常驻按新表更新（演示里那几档的数是新的）；五个演示脚本都退出 0；`Scripts/rust-ci-lite.sh` 退出 0（守卫不过就等，不要绕）。
- 跑完之后 `git status --porcelain` 里没有临时文件；系统的临时目录里没有这一波留下的目录和文件。
- `git show --name-only HEAD` 里只含「纪律」一节允许的路径；其中有 `B1dc-REPORT.md` 和 `B1dc-review.log`。

## 产物先落盘，再收尾

- **代码和测试一绿就先提交一次**；之后每完成一小块提交一次；最后收成**一个**提交。
- **自审**：另起一个独立的 `omp -p --auto-approve --thinking max "<复审任务书>"` 实例复审（任务书里也写明先读那两个技能文件）。复审实例只读，但可以运行构建、测试和演示：重跑验收清单的全部；读代码核流式那条路确实一次都不整帧取输入；核「探」的默认实现和原来逐值相同；核规划只在管线里做一次；自己把上限表抽两档重量；核 `git show --stat` 只含允许的路径。结论头 `PASS / N error + N minor`。发现的问题回注修订。复审输出落 `.work/gsd/phases/rust-core/waves/B1dc-review.log`。
- **退出的次序**：复审实例写完结论头之后，依次——填报告、`git commit --amend` 把报告和复审日志并进那一个提交（不 push）、删临时文件和目录、主进程才退出。报告里不许留「待填」。

## 纪律

- **只允许新增或修改这些路径**：`crates/lightamer-pipeline/`；`crates/lightamer-engine/`；`apps/lightamer-cli/`（只许演示和测试跟着改）；`Scripts/rust-stream-demo.sh`（只许跟着新表改）；`docs/PIPELINE.md`；`crates/README.md`（只改动了的那几行）；`.work/gsd/phases/rust-core/waves/B1dc-REPORT.md` 和 `B1dc-review.log`。其它一律不动。不新增依赖，`Cargo.lock` 不许变。
- 一个 commit，Conventional Commits 格式，subject 用 `fix(rust-core): B1d-c …` 的形式，message 带 `refs #32`，逐路径 `git add`，禁 `git add -A`。**零 push。**
- 命令被移到后台就轮询等它结束，**不许在后台作业还没结束时收工**。
- 构建之前跑一次 `Scripts/machine-guard.sh` 并记录输出。并行度 6 以内。不用 `caffeinate`。一次只跑一个重活。
- 不跑 Swift 的构建和测试，不打开任何图形程序，不运行 `darktable`，不下载安装任何软件，不安装任何编译目标。
- 不读、不打印任何凭据文件。不碰用户照片库。机器上别人的 omp 会话和重活，不碰。
- `.work/` 下以前各波留下的未跟踪文件不碰也不提交。每个源文件带 SPDX 头 `GPL-3.0-or-later`。
- 数字不编。哪一项没做成，写没做成和卡在哪一步。总墙钟不超过 180 分钟，含自审。

## 交付

1. 代码、测试、文档和一个 commit。
2. `.work/gsd/phases/rust-core/waves/B1dc-REPORT.md`（中文正文，英文标题）：结论头三行以内；管线的区域来源入口长什么样；引擎的新次序；新旧上限表并排；验收清单每条的命令与输出；commit 的最终哈希；复审的结论头；「未做 / 未验」两段。

stdout 最后一条消息一次性完整输出同样内容。
