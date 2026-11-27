# 续做 lane B1-a-r（omp）：把 B1-a 收完——复审的三处 minor、报告的两个空节、提交

## 背景

阶段 B 是第 0 期，每一波做完都要停下来给用户看。B1 是第三波（管线内核），分三段串行，第一段 B1-a（地基）的执行实例在 2026-11-27 10:16 被网络错误打断（代理那头 TLS 握手失败），**代码和报告已经提交，收尾没做完**。你是一条短的续做 lane：只做收尾，不扩范围。

磁盘上的现状（每一条你自己核）：

- 提交 `c258dfc7`（`feat(rust-core): B1-a pipeline foundation …`）：30 个文件——五个 crate 的代码和测试、`docs/PIPELINE.md`、`crates/README.md`、`.work/gsd/phases/rust-core/waves/B1-a-REPORT.md`（10:04 的版本）。
- 复审实例已经跑完，结论头 `PASS / 0 error + 3 minor`，日志在 `.work/gsd/phases/rust-core/waves/B1-a-review.log`（**还没有进提交**）。三处 minor 在日志的 Findings 一节。
- 工作区里 `crates/lightamer-pipeline/src/tiling.rs` 有上一实例没提交的改动：它在修 M1 和 M2（`SHRINK_BRANCH` 常量取上游的 `0.333f`；注释行号改成 727 / 730）。先 `git diff` 看它，对就沿用，不对就改。
- M3 还没动。
- 报告的第 11 节「复审的结论头」和第 12 节「修订记录」还写着「复审实例运行中」。

原任务书是 `waves/B1-a-prompt.md`（同目录），纪律和验收清单以它为准。先读它，再读复审日志和报告。

工作目录 `/Volumes/UNITEK/Documents/Development/Lightamer`。HEAD 先亲核并记录。全程中文，代码注释和标识符英文，commit message 英文。

## 要做的

**1. 三处 minor**（复审日志 Findings 一节）：

- M1、M2：确认 `tiling.rs` 里的改动是完整的——两处比较都用那个常量；注释里的行号对着 `/Volumes/UNITEK/Documents/Development/Lightamer-rust-spike/refs/dt-master/src/develop/tiling.c` 用 `sed -n` 亲核（这个目录只读；**不要读** `/Volumes/UNITEK/Documents/Development/darktable` 和 `darktamer`）。`docs/PIPELINE.md` 里如果写了「与上游同公式」而没提这个字面量，补一句。
- M3：`crates/lightamer-pipeline/src/chain.rs` 里 `assert_chained` 的包含断言现在是恒真的（上一行的相等断言已经蕴含它；自己包含自己）。把它改成真的在验「每个节点的输入区域装得下它要的那一块」：用例里给每个节点写出**应得的**输入区域——按调用方要的输出区域和各节点的缩放自己算，不从被测函数的返回值推——然后断言相等或真包含。空区域的用例不许靠「空集被任何区域包含」过关。几何链的每一个用例都要受益，测试名保持能看出测的是什么。报告第 6 节「相等 + 包含，即装得下」那句按改后的事实重写。

**2. 报告**（`waves/B1-a-REPORT.md`）：第 11 节写复审的结论头；第 12 节写三处 minor 各改了什么；第 13 节按最终状态更新；第 9 节的测试数按你最后一次重跑的数写。全文不许留「待填」「运行中」。

**3. 重跑验收**：原任务书第 9 节的全部条目，命令和输出写进报告（原报告已有的输出如果因为你的改动变了，换成新的）。

**4. 提交**：逐路径 `git add`（`tiling.rs`、`chain.rs`、需要的测试文件、`docs/PIPELINE.md`、报告、`B1-a-review.log`），然后 `git commit --amend`——保留原来的 subject，body 末尾加一段说明复审结论和三处修订；`refs #32` 还在。**零 push。**

**5. 退出前**：`git status --porcelain` 里没有已跟踪文件的改动、暂存区是空的；系统的临时目录里没有你留下的目录；没有残留的进程。

## 纪律

- **只允许新增或修改这些路径**：`crates/lightamer-pipeline/` 目录；`docs/PIPELINE.md`；`.work/gsd/phases/rust-core/waves/B1-a-REPORT.md`；`.work/gsd/phases/rust-core/waves/B1-a-review.log`（只许原样加进提交，**不许改它的内容**）。其它一律不动。
- **不需要再起复审实例**：相对已经复审过的 `c258dfc7`，改动只有这三处 minor 和报告，这段差量由塔台自己核。
- `.work/` 下有很多以前各波留下的未跟踪文件（`*.pid`、旧日志），不是你的，不碰也不提交。
- 构建之前跑一次 `Scripts/machine-guard.sh` 并记录输出。并行度 6 以内。不用 `caffeinate`。一次只跑一个重活。
- 不跑 Swift 的构建和测试，不打开任何图形程序，不运行 `darktable`，不下载安装任何软件，不安装任何编译目标，不跑任何非 macOS 目标的检查。
- 不读、不打印任何凭据文件，报告里不出现密钥。不碰用户照片库。
- 机器上可能有别人同时在跑的 omp 会话，不是你的，不碰。守卫不过就等它过了再构建。
- 数字不编。哪一项没做成，写没做成和卡在哪一步。到时间上限就交已有结果。
- **总墙钟不超过 60 分钟。**

## 交付

1. amend 之后的提交哈希（`git log -1`）。
2. 报告更新完毕，并在 stdout 最后一条消息里一次性完整输出：结论头三行以内、三处修订各一句、全工作区测试数、第 9 节每条验收的结果、未做 / 未验。
