# 执行 lane HYG-1（omp）：代码卫生清理——把存量代码对齐两个技能

## 背景

Lightamer 在用 Rust 全量重写。用户 2026-11-27 问：「我们的 Rust 代码有用 `rust-best-practices` 和 `ponytail` 吗？」如实答：只沾了半边——ponytail 是塔台的工作方式，但没有写进给 lane 的任务书；`rust-best-practices` 没用过。用户令：**存量做一次短的清理，以后每一条 lane 都照这两个技能做**。你是这条清理 lane：小步，只做对齐，不加任何功能，不改任何行为。

**先读这两个技能文件，并照做**（全程有效）：

- `/Users/kamasylvia/.agents/skills/ponytail/SKILL.md`
- `/Users/kamasylvia/.agents/skills/rust-best-practices/SKILL.md`（它的 `references/` 各章按需要读）

**用户定的优先级**（两个技能打架的地方按这个来）：

- 公开的项（`pub`）写 `///` 文档注释，说清是什么、怎样用；其余的 `//` 注释只写代码表达不了的「为什么」。
- 错误类型保持手写，不引入 `thiserror` / `anyhow`。
- **不跟**两条：一个测试只断言一件事（我们是一条行为一个测试，可以多处断言）；用类型编码状态。
- 项目自己的门优先：各 crate 根部的六条不崩溃 lint、分层检查、许可证清单、rustdoc 零警告、`cargo fmt`。

工作目录 `/Volumes/UNITEK/Documents/Development/Lightamer`。HEAD 先亲核并记录。全程中文，代码注释和标识符英文，commit message 英文。

## 现在的起点（塔台粗量的，每一条你自己精量）

- `#[allow(…)]` 全仓约 73 处（生产代码里约 47 处，其余在测试和工具里），`#[expect(…)]` 零处。技能要求：能用 `#[expect]` 就用，并写一句理由——这样不再命中的豁免会让编译失败，不会留成死豁免。
- 根 `Cargo.toml` 的 `[workspace.lints.rust]` 里 `missing_docs = "warn"`，靠 clippy 那一步的 `-D warnings` 兜着；没有显式写成 `deny`。公开项的文档应该已经齐了（塔台粗量出三十几处没有，多半是漏数——文档和函数之间隔着别的属性行）——你用编译器自己的输出精量。
- `cargo clippy` 那一步没有带 `-D clippy::perf`。
- **「以后再填」的东西**（ponytail：没人要的代码不写；这些是塔台当初在任务书里要的）：
  - `crates/lightamer-iop-traits/src/tiling.rs` 里分块请求的两个字段 `factor_cl`、`maxbuf_cl`（图形处理器那一侧的，填了没人用）。
  - `crates/lightamer-geom/src/roi.rs` 的 `Roi::to_scale`——除了它自己的测试，全仓零调用。
- 错误类型全是手写的，保持。

## 要做的

**1. `#[allow]` 换 `#[expect]`。** 逐处判断：确定会命中的，换成 `#[expect(clippy::…)]` 并在旁边写一句为什么要压这个 lint；换了之后全工作区必须编译过。确实不该换的（说得出理由的）保留 `#[allow]`，理由写在旁边。每一处的去向列进报告。

**2. 文档。** 把 `[workspace.lints.rust]` 里的 `missing_docs` 从 `warn` 改成 `deny`。用编译器的输出找出真正缺文档的公开项（crate 本身、模块、类型、特征、函数、字段），补上：一到三句，说是什么、怎样用；代码一眼能看出来的不写。改完 rustdoc 零警告、clippy 零警告。

**3. `clippy::perf`。** 跑 `cargo clippy --workspace --all-targets --locked -- -D warnings -D clippy::perf` 加上现有的六条不崩溃 lint。真问题就修；是误报就 `#[expect]` 加理由。全绿之后把 `-D clippy::perf` 加进 `Scripts/rust-test.sh` 里那一条 clippy 命令（只有这一处），让它从今往后是常设的门。修了什么、各是什么问题，列进报告。

**4. 「以后再填」的东西。** 上面两项**删掉**：连同它们的测试，以及 `docs/PIPELINE.md` 里对应的句子（留一句「图形处理器那一侧的分块请求等图形处理器那一波再加」）。然后自己再扫一遍：对每个 `pub` 项找调用点，列出「除自己的测试外零调用」的，逐个判断——是给后面的波或界面用的接缝（引擎的注入口、读取方法这一类），还是「以后再填」；是后者就删，判断和理由列进报告。**接缝不许误删。**

**5. 不许改的。** 不许改任何函数的签名和行为；不许改任何序列化的字节（历史模型有逐位的测试守着）；不许加任何依赖；不碰子模块 `external/rawspeed`。

## 验收清单（命令和输出都写进报告）

- `#[allow(` 和 `#[expect(` 的前后两个数；留下的每一处 `#[allow]` 旁边有一句理由。
- 根 `Cargo.toml` 里 `missing_docs = "deny"`；`RUSTDOCFLAGS="-D warnings" cargo doc --workspace --no-deps --locked` 退出 0。
- 带上 `-D clippy::perf` 的 clippy 对整个工作区退出 0；`Scripts/rust-test.sh` 里那一条命令带上了它。
- 删掉的项逐个列出（名字、位置、为什么是「以后再填」）；`docs/PIPELINE.md` 相应更新。
- `cargo test --workspace --locked` 绿；测试数不少于起点减去被删项的测试数（逐个对上）。
- 没有行为变化：A7a 那份五行命令文件的汇总值不变（`waves/A7a-REPORT.md` §5 有文件和当时的数）；四个演示脚本（会话、历史、渲染、解码）都退出 0。
- `cargo xtask layers` 等检查通过；`Scripts/rust-apple-boundary.sh` 退出 0；`Scripts/check-licenses.sh` 退出 0（没有新依赖）。
- `Scripts/rust-ci-lite.sh` 从头到尾退出 0（守卫不过就等，不要绕；等不到就如实写明）。派你的时候机器上有用户自己的重活在跑（负载可能到每个核一个多），构建和测试会慢：预算那一步如果因为负载红了，把当时的负载读数和那一步的耗时如实写进报告，不要绕，也不要反复重跑到绿。
- `git show --name-only HEAD` 里只有下面「纪律」一节允许的路径；其中有 `HYG1-REPORT.md` 和 `HYG1-review.log`。

## 产物先落盘，再收尾

- **代码一绿就先提交一次**。之后可以继续提交，最后用 `git commit --amend` 或 squash 收成**一个**提交。
- **自审**：产物落盘并提交后，另起一个独立的 `omp -p --auto-approve --thinking max "<复审任务书>"` 实例复审（复审任务书里也写明先读那两个技能文件）。复审实例只读，但可以运行构建和测试：重跑验收清单的全部；核每一处 `#[expect]` 都真的会命中（随便挑几处把被压的代码去掉，确认编译会失败，再改回来——只在它自己的临时副本里做，或者只读地论证）；核 `missing_docs = "deny"` 确实在位；核删掉的项确实零调用、接缝一个没少；核 diff 里没有行为改动（逐文件看）；核 `git show --stat` 只含允许的路径。结论头 `PASS / N error + N minor`。发现的问题回注修订，修订记录附在报告末尾。复审输出落 `.work/gsd/phases/rust-core/waves/HYG1-review.log`。
- **退出的次序**：复审实例写完结论头之后，你才依次做四件事——把复审的结论头和修订记录写进报告；`git commit --amend` 把最终的报告和 `HYG1-review.log` 并进那一个提交（不 push，所以 amend 是安全的）；删掉你建的临时文件和目录；最后主进程才退出。报告里不许留「待填」。

## 纪律

- **只允许新增或修改这些路径**：各 crate 的源码和 `Cargo.toml`（`crates/*/`，子模块 `external/` 除外）；`apps/lightamer-cli/src/`；根目录的 `Cargo.toml`（只动 `[workspace.lints]`）；`Scripts/rust-test.sh`（只动那一条 clippy 命令）；`docs/PIPELINE.md`（只动被删项对应的句子）；`crates/README.md`（只改动了的那几行）；`.work/gsd/phases/rust-core/waves/HYG1-REPORT.md` 和 `HYG1-review.log`。其它一律不动。`Cargo.lock` 不许变。
- 一个 commit（见上），Conventional Commits 格式，message 带 `refs #32`，逐路径 `git add`，禁 `git add -A`。**零 push。**
- 构建之前跑一次 `Scripts/machine-guard.sh` 并记录输出。并行度 6 以内。不用 `caffeinate`。一次只跑一个重活。
- 不跑 Swift 的构建和测试，不打开任何图形程序，不运行 `darktable`，不下载安装任何软件，不安装任何编译目标，不跑任何非 macOS 目标的检查。
- 不读、不打印任何凭据文件，报告里不出现密钥。不碰用户照片库。
- 机器上可能有别人同时在跑的 omp 会话，不是你的，不碰。
- `.work/` 下有很多以前各波留下的未跟踪文件（`*.pid`、旧日志），不是你的，不碰也不提交。
- 数字不编。哪一项没做成，写没做成和卡在哪一步。到时间上限就交已有结果。
- 总墙钟不超过 150 分钟，含自审。

## 交付

1. 代码和一个 commit。
2. `.work/gsd/phases/rust-core/waves/HYG1-REPORT.md`（中文正文，英文标题）：结论头，三行以内；`#[allow]` 每一处的去向；补了文档的项；`clippy::perf` 查出并修掉的问题；删掉的项和保留的接缝；验收清单每条的命令与输出；commit 的最终哈希；复审的结论头；**给用户看的汇报**（一节）；「未做 / 未验」两段。

stdout 最后一条消息一次性完整输出同样内容。
