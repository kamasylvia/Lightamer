# 续做 lane B1d-a-r（omp）：把流式管线这一侧收完——盘点半成品、接着做、验收、自审

## 背景

阶段 B 是第 0 期，每一波做完都要停下来给用户看。B1d（整链行带流式）分两段串行，**B1d-a（管线这一侧）的执行实例在 2026-11-28 02:47 被网络错误打断**（代理那边 TLS 握手失败，第 32 分钟），代码还一次都没提交。你是一条续做 lane：从盘上的半成品接着做，做完原任务书的全部。

**原任务书是 `waves/B1da-prompt.md`（同目录），范围、做法、测试、验收清单、纪律都以它为准**——先完整读它，包括里面「代码写法」一节（先读 `ponytail` 和 `rust-best-practices` 两个技能文件并照做）。下面只写和原任务书不同的地方。

工作目录 `/Volumes/UNITEK/Documents/Development/Lightamer`。起点 HEAD 是 `1535a9e2`，先亲核。全程中文，代码注释和标识符英文，commit message 英文。

## 盘上的现状（塔台看的，每一条你自己核）

- 工作区有未提交的改动，全是上一实例留下的（`git status`）：
  - 改动：`Cargo.lock`；`crates/lightamer-iop-traits/src/lib.rs`、`module.rs`；`crates/lightamer-pipeline/Cargo.toml`、`src/lib.rs`、`src/render.rs`、`src/chain.rs`、`src/fakes.rs`。
  - 新文件：`crates/lightamer-iop-traits/src/stats.rs`（「要不要看整图」的声明和影响范围的一致性判据，约 258 行）；`crates/lightamer-pipeline/src/stream.rs`（规划器、执行器，约 1750 行）；`crates/lightamer-pipeline/src/spill.rs`（输出的拼装和内存映射落盘，约 520 行）。
  - `crates/lightamer-pipeline/Cargo.toml` 新加了三个依赖：`bytemuck`、`memmap2`、`tempfile`（锁文件里都已经有）。**许可证表达式必须先在 `Scripts/licenses-allow.txt` 里**，不在就停下报告，那个文件不许改。
- 这些文件里已经有测试（粗数：`stream.rs` 17 个、`spill.rs` 6 个、`stats.rs` 4 个）。**它们编不编得过、过不过，没人知道**——上一实例没走到那一步。
- 构建目录刚被清空过，第一次构建是从头编，要几分钟。

## 要做的

**1. 先盘点，再动手。** 读 diff 和三个新文件；跑 `cargo check -p lightamer-iop-traits -p lightamer-pipeline --locked`，把编译错误和警告列出来。对上一实例写的东西：对的接着用，不对的改，缺的补——不要推倒重写，也不要为了省事把没写完的部分删掉了事。盘点结果（哪些完整、哪些半截）写进报告。

**2. 做完原任务书的全部**：要做的八条、测试一节、验收清单。逐条对照，没做的补上。

**3. 提交的节奏改一下**（网络错误今天已经打断过三条 lane）：盘点完、代码第一次编译过的那一刻就提交一次；之后**每完成一小块就提交一次**（可以有很多个提交），最后用 squash 或 `git commit --amend` 收成**一个**提交。

**4. 自审和退出的次序**照原任务书：复审实例写完结论头之后，填报告、把报告和 `B1da-review.log` 并进那一个提交、删临时文件和目录、主进程才退出。复审输出仍落 `waves/B1da-review.log`，报告仍写 `waves/B1da-REPORT.md`；报告里单列一节「续做：盘上的半成品哪些完整、哪些半截、你补了什么」。

## 纪律

- 允许的路径、`refs #32`、零 push、守卫、并行度 6 以内、不用 `caffeinate`、不跑 Swift 和图形程序、不读凭据、不碰别人的 omp 会话、`.work/` 下的旧文件不碰——都和原任务书相同。
- 派你的时候机器上有用户自己的重活在跑（负载在每个核一个上下），构建和测试会慢；计时类的步骤如果报「测不准」，把负载读数如实记下，不要绕，也不要反复重跑到绿。
- 总墙钟不超过 240 分钟，含自审。

## 交付

和原任务书相同：代码、测试、文档和一个 commit；`waves/B1da-REPORT.md`；stdout 最后一条消息一次性完整输出报告要点（加上「续做」那一节）。
