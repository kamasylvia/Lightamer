# 执行 lane A9（omp）：lint 和文档的收口

## 背景

阶段 A 已经做完（A1 到 A8）。A8 把 crate 改名成了 `lightamer-` 前缀，并给四个构建脚本加了一行豁免。改名之后露出一件早就存在的事：项目立过一条「不崩溃」的规矩——产品代码里不许直接下标索引、不许 `unwrap`、`expect`、`panic!`、`todo!`、`unimplemented!`——但它只在写过逻辑的几个 crate 里落实了，也没有进总检查。你这一波把它收口：让这条规矩对整个工作区成立，并且以后每一波都自动过。

同时顺手修掉文档里的 7 条断链警告。

先读：

- `.work/gsd/phases/rust-core/waves/VERIFY.md` 的 A8 一节：底数是什么，为什么会这样。
- `crates/lightamer-history/src/lib.rs` 和 `crates/lightamer-history/src/settings.rs` 的开头：A4b 立的写法——根部六条拒绝，测试代码放开前三条。照这个样子。
- `crates/lightamer-history/src/history.rs` 开头的 `HistoryStack`：注意它的下标访问是怎样避开直接索引的（A4b 的做法），改别处时照它。
- `apps/lightamer-cli/src/`：命令行工具。它已经有一套退出码：0 成功，1 检查没过，2 用法或输入输出的错误。
- `Scripts/rust-ci-lite.sh`：总检查。

工作目录 `/Volumes/UNITEK/Documents/Development/Lightamer`。HEAD 先亲核并记录。全程中文，代码注释和标识符英文，commit message 英文。这一波**不改任何行为**。

## 现在的底数（塔台量的，你动手前自己再量一遍）

- 六条 lint 用命令行开关跑整个工作区（`cargo clippy --workspace --all-targets --locked -- -D clippy::indexing_slicing -D clippy::unwrap_used -D clippy::expect_used -D clippy::panic -D clippy::todo -D clippy::unimplemented`）是红的。
- `crates/lightamer-registry`：23 处命中，**全在测试代码里**；它的根部没有那六条声明。
- 其余空壳 crate（还没写过逻辑的那些）根部都没有那六条声明。
- `crates/xtask`：约 80 处，是开发工具。
- `apps/lightamer-cli`：库里有旧存量；二进制入口里可能也有。
- `cargo doc --workspace --no-deps --locked`：7 条警告，引擎 5 条、历史 2 条（有没解开的交叉链接，有指向私有项的链接）。

## 要做的

**1. 把规则写下来。** 在 `crates/README.md` 里加一小节，写明：

- 层表里第 0 层到第 5 层的每一个 crate（「产品 crate」），在**库目标的根部**声明六条拒绝；测试代码放开前三条（直接下标索引、`unwrap`、`expect`）。测试套件 crate 里的测试辅助代码按测试代码对待。
- 开发工具可以豁免，但要在根部写明是哪几条、为什么：`xtask` 整个 crate；`lightamer-cli` 的**二进制入口**；构建脚本。`lightamer-cli` 的**库**按产品 crate 对待。
- 以后新写的 crate 一建出来就带上这几行，不是等到有了逻辑再补。

**2. 给每一个产品 crate 补上声明。** 照 `lightamer-history` 的写法。空壳 crate 也补，一条规矩不留例外。模块桩（`crates/lightamer-iop-*/src/modules/` 下的文件）一个字节都不许动，你只动各 crate 的 `src/lib.rs` 顶部。

**3. 注册表 crate。** 生产代码现在是干净的，只缺声明；测试代码按规则放开。你量出来如果生产代码里也有命中，改成不崩的写法（照 `HistoryStack` 的做法），不许用豁免了事。

**4. `xtask`。** 根部写明豁免那六条和理由（开发工具，出错时 cargo 会把信息报给开发者）。它的代码一行不改。

**5. `lightamer-cli`。** 库里命中的地方改成返回错误，接上它已有的退出码约定；库的根部加上六条声明。二进制入口 `main.rs` 是薄的一层，根部写明豁免及理由。**行为不变**：动手之前先把这几个的输出存下来——`help`、`capabilities`、`commands`、拿 A7a 报告里那份命令文件跑 `run`、对照工具 `cmp` 的几个用法——改完逐字节比对，必须相同。出错路径上以前是崩出来的，现在变成一句错误加退出码 2，这算改进，在报告里逐条列出改了哪些。

**6. 文档的 7 条警告。** 该指向公开路径的交叉链接改成指向公开路径；指向私有项的改成普通的代码字体。**不要为了消警告把私有的类型公开。** 只动文档注释。

**7. 进总检查。** `Scripts/rust-ci-lite.sh` 在分层检查之后加两步，任何一步红就停：

- 上面那条六条 lint 的命令行口径，对整个工作区、带 `--all-targets`。
- `RUSTDOCFLAGS="-D warnings" cargo doc --workspace --no-deps --locked`。

## 计划规定的通用纪律（原样保留）

- 变换规则：不改任何封存面；这一波不新增依赖。
- 验收清单：`cargo fmt --all --check` 与 `cargo clippy --workspace --all-targets -- -D warnings` 绿；`Scripts/machine-guard.sh` 在构建之前跑一次；任务书末尾附「未做 / 未验」。
- 通用纪律：`.work/` 之外不写计划面文件；一次只跑一个重活；报告里每个数字给命令。

## 8. 验收清单（命令和输出都写进报告）

- 动手前先量：上面「现在的底数」里的每一条，命令和数字写进报告。
- `cargo clippy --workspace --all-targets --locked -- -D clippy::indexing_slicing -D clippy::unwrap_used -D clippy::expect_used -D clippy::panic -D clippy::todo -D clippy::unimplemented` 退出 0。
- `RUSTDOCFLAGS="-D warnings" cargo doc --workspace --no-deps --locked` 退出 0。
- `cargo test --workspace --locked` 绿，测试数不少于 192。
- `lightamer-cli` 的 `help`、`capabilities`、`commands`、`run`、`cmp` 的输出，改前改后逐字节相同（把比对命令和结果写进报告）。
- 每一个产品 crate 的 `src/lib.rs` 根部都有那六个名字：给一条搜索命令和它的输出，命中的 crate 数等于层表里第 0 到第 5 层的 crate 数。
- `cargo xtask layers`、`check-order-sync`、`check-no-iop-names`、`check-apple-boundary` 通过；`Scripts/rust-apple-boundary.sh` 退出 0。
- `cargo check --workspace --exclude lightamer-gpui --all-targets --target x86_64-unknown-linux-gnu --locked` 通过，零警告。
- `Scripts/rust-ci-lite.sh` 从头到尾退出 0，日志里能看到新加的两步跑过。
- 模块桩、顺序夹具、引擎的行为、历史模型的行为都没变：`git diff --stat <起始 HEAD> HEAD -- 'crates/lightamer-iop-*/src/modules' crates/lightamer-registry/fixtures` 没有输出；引擎和历史只有文档注释变了（`git diff` 里给证据）。
- `git show --name-only HEAD` 里只有下面「纪律」一节允许的路径。

## omp 域内自审（项目只信重跑过的数字）

产物落盘并提交后，另起一个独立的 `omp -p --auto-approve --thinking max "<复审任务书>"` 实例复审。复审实例只读，但可以运行构建和测试：重跑第 8 节的全部验收；核有没有哪一处改动超出了「补声明、改错误返回、修文档、加两步检查」；核 `lightamer-cli` 的输出确实逐字节没变；核没有把私有类型公开；核 `git show --stat` 只含允许的路径。结论头 `PASS / N error + N minor`。发现的问题回注修订，修订记录附在报告末尾。复审输出落 `.work/gsd/phases/rust-core/waves/A9-review.log`。**复审实例写完结论头之后你的主进程才退出。**

## 纪律

- **只允许新增或修改这些路径**：`crates/*/src/lib.rs`（只许动顶部的 lint 声明和测试模块的放开那几行，注册表 crate 除外，它按第 3 节）；`crates/lightamer-engine/src/` 和 `crates/lightamer-history/src/`（只许动文档注释）；`apps/lightamer-cli/src/`；`crates/xtask/src/main.rs`（只许动顶部的豁免）；`crates/README.md`；`Scripts/rust-ci-lite.sh`；`.work/gsd/phases/rust-core/waves/A9-REPORT.md` 和 `A9-review.log`。其它一律不动。
- 一个 commit，Conventional Commits 格式，message 带 `refs #32`，逐路径 `git add`，禁 `git add -A`。**零 push。**
- 构建之前跑一次 `Scripts/machine-guard.sh` 并记录输出。并行度 6 以内。不用 `caffeinate`。
- 不跑 Swift 的构建和测试，不打开任何图形程序，不运行 `darktable`，不下载安装任何软件。
- 不读、不打印任何凭据文件，报告里不出现密钥。不碰用户照片库。
- 机器上可能有别人同时在跑的 omp 会话，不是你的，不碰。守卫不过就等它过了再构建。
- 数字不编。哪一项没做成，写没做成和卡在哪一步。到时间上限就交已有结果。
- 总墙钟不超过 150 分钟，含自审。

## 交付

1. 改动和一个 commit。
2. `.work/gsd/phases/rust-core/waves/A9-REPORT.md`（中文正文，英文标题）：结论头，三行以内；动手前的底数；规则原文；`lightamer-cli` 里逐条改了哪里、以前怎样崩、现在怎样报；文档 7 条各改了什么；第 8 节每条验收的命令与输出；commit 的最终哈希；复审的结论头；「未做 / 未验」两段。

stdout 最后一条消息一次性完整输出同样内容。
