# 收尾 lane B1d-c-close（omp）：修复审的两处 minor、填完报告、并成一个提交

## 背景

B1d-c（流式作业不再先取整帧）的代码已经提交（两个提交：`fix(rust-core): B1d-c probe-first streaming, region-source pipe entry` 和其后的 `docs(rust-core): B1d-c pipeline doc and crate rows`）。执行 lane 的主进程在自审写完之前退出了，报告是带「待填」的草稿。塔台另派的只读复审已经做完：`.work/gsd/phases/rust-core/waves/B1dc-review.log`，结论头 **`PASS / 0 error + 2 minor`**。你做三件事：修掉这两处 minor、把报告填完、把所有东西并成**一个**提交。**不再起复审实例**——改动很小，塔台自己核。

**先读这两个技能文件并照做**：`/Users/kamasylvia/.agents/skills/ponytail/SKILL.md`、`/Users/kamasylvia/.agents/skills/rust-best-practices/SKILL.md`。公开的项写 `///`，其余注释只写为什么；错误类型手写。

工作目录 `/Volumes/UNITEK/Documents/Development/Lightamer`。HEAD 先亲核（两个提交都在）。全程中文，代码注释和标识符英文，commit message 英文。

先读（都在 `.work/gsd/phases/rust-core/waves/` 下）：

- `B1dc-prompt.md`（原任务书）、`B1dc-REPORT.md`（报告草稿）、`B1dc-review.log`（复审全文，最后两行是两处 minor 和建议的修法）。
- `crates/lightamer-engine/src/render.rs` 的渲染作业（探尺寸 → 判断 → 流式或整帧）和 `InputSource::probe` 的文档注释。
- `docs/PIPELINE.md`（仓库根下）的「行带流式」一节。

## 要做的

**1. minor-1：「探」和真实像素不一致。** 在 `InputSource::probe` 的文档注释上写明契约——来源必须保证探到的尺寸和真实像素一致；不一致时两种方向的行为各是什么（探大取小：默认来源按区域取的时候越界，是分了类型的失败；探小取大：按探到的尺寸规划，输出比真实的画面小）。再补两个测试把这两个方向钉住（用默认的按区域取；探小取大那一例断言输出尺寸等于探到的尺寸，并在测试注释里写明「这是来源撒谎的后果，不是期望的行为」）。

**2. minor-2：白探一次、整帧取两次。** 只有「这种实例会自动转流式、并且链不是空的」时才去探尺寸；预览、缩略图和空链不探（它们永远不可能转流式），整帧那条路照旧只取一次输入。完整分辨率和导出两种实例在用默认的「探」时仍然会取两次（探里一次、取像素一次）——在 `probe` 的文档注释上写明「大帧的来源应该覆写它，便宜地答，否则整帧那条路会解码两次」。补一个测试：预览实例上整帧取输入恰好一次。

**3. 一个小毛病，查清并修**：塔台跑 `Scripts/rust-history-demo.sh`（退出 0、全绿）之后，系统的临时目录里留下了一个 `lightamer-history-demo-*` 目录（带着三万张占位照片）。脚本自己的收尾是 `rm -rf "$TMP"` 然后 `trap - EXIT`。你自己跑一两遍（负载高时它会先「测不准」、等 60 秒重试），看残留是哪条路径留下的，修掉。修不了就写明复现条件和你的判断。

**4. 填完报告** `waves/B1dc-REPORT.md`：把「待填」全部填上——commit 的最终哈希（并完之后填，或者写「见 `git log -1`」）；复审的结论头 `PASS / 0 error + 2 minor` 和两处的修法；「未做 / 未验」两段如实写。另外在上限表下面加一小节「峰值占用（复审量的）」：把复审日志里第 9 条的四行数字（峰值常驻、峰值占用）抄成一张表，一句话说清——帧放大 2.5 倍，峰值占用条带 50 → 79 MB、方块 672 → 631 MB，基本不涨；峰值常驻里多出来的是拼装输出的内存映射页，干净可回收。

**5. 并成一个提交。** 把现在的两个提交和报告、复审日志并成**一个**提交：subject 沿用 `fix(rust-core): B1d-c probe-first streaming, region-source pipe entry`，body 里写明修了两处 minor、并入了文档和报告，带 `refs #32`。逐路径 `git add`，禁 `git add -A`。**零 push。** 并完之后 `git show --name-only HEAD` 里要有 `B1dc-REPORT.md` 和 `B1dc-review.log`，并且只含「纪律」一节的路径。**复审日志一个字不许改。**

## 验收清单（命令和输出写进报告末尾）

- `cargo test -p lightamer-engine --locked` 绿；`cargo test --workspace --locked --no-fail-fast` 绿、零失败，测试数不少于 672 加上这一段新增的（逐个列出）。
- 六条不崩溃 lint（`CARGO_INCREMENTAL=0`）和文档零警告；`cargo xtask layers` 等检查通过。
- 预览、缩略图、空链不探尺寸（测试）；预览实例上整帧取输入恰好一次（测试）。
- `Scripts/rust-history-demo.sh` 退出 0，跑完之后系统的临时目录里没有 `lightamer-history-demo-*`。
- `Scripts/rust-stream-demo.sh`、`Scripts/rust-session-demo.sh`、`Scripts/rust-render-demo.sh`、`Scripts/rust-decode-demo.sh` 都退出 0。
- 一个提交；`git status --porcelain` 里没有临时文件（塔台会随后补提交它自己的几个文件，那些不是你的）。

## 纪律

- **只允许新增或修改这些路径**：`crates/lightamer-engine/`；`Scripts/rust-history-demo.sh`（只许修残留那一条路径）；`docs/PIPELINE.md`（只许跟着 minor 补一两句）；`.work/gsd/phases/rust-core/waves/B1dc-REPORT.md`。其它一律不动。`B1dc-review.log` 只许原样加进提交。不新增依赖，`Cargo.lock` 不许变。
- 命令被移到后台就轮询等它结束，**不许在后台作业还没结束时收工**。
- 构建之前跑一次 `Scripts/machine-guard.sh` 并记录输出。并行度 6 以内。不用 `caffeinate`。一次只跑一个重活。
- 不跑 Swift 的构建和测试，不打开任何图形程序，不运行 `darktable`，不下载安装任何软件。不读、不打印任何凭据文件。不碰用户照片库。机器上别人的 omp 会话和重活，不碰。
- `.work/` 下以前各波留下的未跟踪文件不碰也不提交。
- 数字不编。哪一项没做成，写没做成和卡在哪一步。总墙钟不超过 90 分钟。

## 交付

一个提交；填完的 `waves/B1dc-REPORT.md`；stdout 最后一条消息一次性完整输出：两处 minor 各怎么修的、新增的测试、历史演示残留的原因和修法、验收清单每条的命令与输出、commit 的最终哈希。
