# 执行 lane A8（omp）：工作区的 crate 改名，`dt-` 换成 `lightamer-`

## 背景

阶段 A 在收尾：A1 到 A7a 已完成，A7b（视口与输入）在你之前刚做完。工作区按层摆好，28 个包加一个不参与分层检查的命令行工具。

用户 2026-11-26 下午的裁决，原话：

> `dt-catalog`/`dt-history`/`dt-pipeline`/`dt-decode` 等带 `dt-` 前缀，现在已经裁决不兼容 dt 历史了，还有必要吗？
> （塔台答：没有必要了，它是「兼容 darktable」那个年代起的；建议改名。）用户：**改，但不改 `la-`。改全称 `lightamer-`。**

所以这一波是**纯改名**：一个行为都不变，一个测试都不增不减。它必须赶在阶段 B 开始之前做完，因为阶段 B 会往这些 crate 里写几万行。

先读：

- `.work/gsd/phases/rust-core/waves/VERIFY.md` 的最后三节（A6、A7a、补记）：现在的工作区长什么样，哪些检查是必须过的。
- `.work/gsd/phases/rust-core/FRAMEWORK-TABLES.md` 的 T-F9：层表。crate 的层和依赖方向这一波不变。
- `crates/README.md`、`crates/xtask/src/layers.rs`、`crates/xtask/src/apple_boundary.rs`、`crates/xtask/src/no_names.rs`：crate 名字被写死的地方。
- `NOTICE`：取自 LightCraft 的文件按路径登记在这里。

工作目录 `/Volumes/UNITEK/Documents/Development/Lightamer`。HEAD 先亲核并记录。全程中文，代码注释和标识符英文，commit message 英文。

## 改名的规则

**一，28 个包，一一对应。** `crates/dt-X` 改成 `crates/lightamer-X`；`apps/dt-cli` 改成 `apps/lightamer-cli`。包名、目录名、命令行工具的二进制名（`lightamer-cli`）一起改。唯一的例外：

- `dt-lightamer` 改成 **`lightamer-ai`**。它是放 Lightamer 自有的人工智能功能的占位包，按规则会变成 `lightamer-lightamer`，那不是任何人的意思。它的文档注释里把这一点写明。

**二，源码里的标识符跟着改。** `dt_history::` 变 `lightamer_history::`，其余同理。文档里的交叉引用（`[`dt_engine::Engine::execute`]` 这一种）必须跟着改，否则 rustdoc 的链接会断。环境变量是我们自己的、带 `DT_` 前缀的（例如发现探针用的那一个），改成 `LIGHTAMER_` 前缀，源码和脚本两边一起改。

**三，检查和脚本里写死的名字跟着改。** 分层检查的表、查模块名的目录清单、Apple 边界检查里的 crate 名、生成桩和顺序同步里的路径、`Scripts/` 下每一个脚本里的包名和二进制路径（`rust-budget.sh`、`rust-apple-boundary.sh`、`rust-discovery-probe.sh`、`rust-gui-viewport-probe.sh`、`oracle.sh`，以及其余的 `rust-*.sh`）。子命令的名字不改（`cargo xtask layers` 还是叫 `layers`）。

**四，跟着改的文档**：`crates/README.md`、`docs/APPLE-BOUNDARY.md`、`docs/ORACLE-BASELINE.md`、`fixtures/oracle/README.md`、根目录的 `README.md` 和 `AGENTS.md` 里**只改出现 crate 名字的句子**，别的一个字不动。`NOTICE` 里取自 LightCraft 的文件按路径登记，路径改成新位置，并在那一条里加一句「文件于 2026-11-26 由 `dt-` 前缀改名为 `lightamer-` 前缀」。

**五，不许改的名字。**
- 顺序夹具的文件名 `dt-order-679d594f5d.json`。它是 darktable 的顺序，名字说的就是这件事。
- 模块的标识（`exposure`、`colorin` 这些）和描述里的任何数据。
- 源码注释里引用的 darktable 函数名、类型名、文件名（例如说明某个算法出自 `masks.c` 的哪一段）。那是别人的名字。
- `.work/` 下的任何文件，除了你自己的报告和复审日志。研究、计划、核验日志、以前每一波的报告都是历史记录，里面的旧名字不改；阶段 B 的计划另有专人改。

**六，用 `git mv`。** 目录改名用 `git mv`，历史要能追回去。

## 怎么做

1. **先盘点，再动手。** 把上面几类里所有出现旧名字的地方数出来，写进报告：每个区域多少个文件、多少处。盘点要自己搜，不要照塔台报的数。
2. 逐个 crate 改：`git mv` 目录，改清单里的包名和依赖，改源码里的路径和标识符。
3. 改检查、脚本、文档。
4. 每改完一批就编一次，别等全改完。

## 计划规定的通用纪律（原样保留）

- 变换规则：不改任何封存面；这一波不新增依赖。模块桩、顺序夹具的内容一个字节都不能变（它们的**路径**会随目录变，内容不变）。
- 验收清单：`cargo fmt --all --check` 与 `cargo clippy --workspace --all-targets -- -D warnings` 绿；`Scripts/machine-guard.sh` 在构建之前跑一次；任务书末尾附「未做 / 未验」。
- 通用纪律：`.work/` 之外不写计划面文件；一次只跑一个重活；报告里每个数字给命令。

## 顺手做的一件小事

A7a 留下的一个缺口：用命令行开关跑那六条「不崩溃」的 lint（`clippy::indexing_slicing`、`unwrap_used`、`expect_used`、`panic`、`todo`、`unimplemented`）时，会把工作区依赖的构建脚本一起查，四个模块域 crate 的 `build.rs` 里有 16 处 `panic!` 和 `expect`，于是整体变红。构建脚本按惯例可以崩，那是 cargo 报错的正常途径。**在四个 `build.rs` 的顶部加一行豁免**（连同那六条里命中的几条），并写明理由。只许动这一处，构建脚本的逻辑一个字不改。改完那条命令要整体变绿，把命令和输出写进报告。

## 验收清单（命令和输出都写进报告）

- `cargo metadata --locked --no-deps --format-version 1` 里包的数目不变（29，含 `xtask`），名字全部是 `lightamer-` 前缀或 `xtask`。
- `cargo test --workspace --locked` 绿，测试总数**和改名前逐个相同**（A7b 之后的数你自己先记下来；一个不多，一个不少）。
- `cargo check --workspace --all-targets --target x86_64-unknown-linux-gnu --locked` 通过，零警告（本机装了这个目标）。
- `cargo xtask layers`、`cargo xtask check-order-sync`、`cargo xtask check-no-iop-names`、`cargo xtask check-apple-boundary` 全部通过，并且输出里能看到新名字。
- `Scripts/rust-apple-boundary.sh` 退出 0；`Scripts/rust-discovery-probe.sh` 两个方向都通过；`Scripts/rust-ci-lite.sh` 从头到尾退出 0；`Scripts/rust-budget.sh` 退出 0。
- `target/debug/lightamer-cli help` 列出的子命令和改名前一样多；`target/debug/lightamer-cli capabilities` 照常。
- 六条「不崩溃」lint 的命令行口径整体变绿（见上一节）。
- `cargo doc --workspace --no-deps --locked` 不报断掉的交叉引用。
- 改名是 `git mv`：`git log --follow --oneline -- crates/lightamer-history/Cargo.toml` 能追到目录还叫 `crates/dt-history` 时期的提交；再抽两个 crate 各验一次。
- 残留扫描，都是零命中（把命令和输出写进报告）：
  - 包名：`rg -n '\bdt-(apple|blend|catalog|cli|color|color-math|decode|engine|geom|gpu|gpui|history|iop-[a-z]+|lightamer|mcp|merge|meta|pipeline|preview|raster|registry|scenes|sysmem|testkit)\b' crates apps Scripts docs NOTICE README.md AGENTS.md fixtures`
  - 标识符：`rg -n '\bdt_[a-z_]+::' crates apps`
  - 环境变量：`rg -n '\bDT_[A-Z_]+' crates apps Scripts`
- 模块桩和顺序夹具的内容没变：按**新路径**比旧路径，`git diff --stat <起始 HEAD> HEAD -M -- 'crates/lightamer-iop-*/src/modules' 'crates/lightamer-registry/fixtures'` 里只有路径变化，没有内容变化（用 `git log --follow` 或逐文件比哈希证明）。
- `git show --stat HEAD` 里只有下面「纪律」一节允许的路径。

## omp 域内自审（项目只信重跑过的数字）

产物落盘并提交后，另起一个独立的 `omp -p --auto-approve --thinking max "<复审任务书>"` 实例复审。复审实例只读，但可以运行构建和测试：重跑第验收清单的全部；抽 10 个文件用 `git log --follow` 确认历史连着；核有没有哪个改动超出了「改名」（任何逻辑改动都算 error）；核不许改的名字一个都没被改；核 `.work/` 下除报告和复审日志外没有被动。结论头 `PASS / N error + N minor`。发现的问题回注修订，修订记录附在报告末尾。复审输出落 `.work/gsd/phases/rust-core/waves/A8-review.log`。

**你的主进程必须在复审实例写完结论头之后才退出。** 上一波有一条 lane 在它的复审还没跑完时就退出了，复审实例被一起停掉，什么都没留下。你的最后一条消息里要报告复审的结论头；做不到就如实写「自审未完成」。

## 纪律

- **只允许新增或修改这些路径**：`crates/` 整个目录（改名、清单、源码里的名字、文档注释）；`apps/` 整个目录；根目录的 `Cargo.toml`、`Cargo.lock`；`Scripts/` 下的脚本（只改名）；`docs/`（只改名）；`NOTICE`；`crates/README.md`；根目录 `README.md` 和 `AGENTS.md`（只许改出现 crate 名字的句子）；`.work/gsd/phases/rust-core/waves/A8-REPORT.md` 和 `A8-review.log`。其它一律不动。
- 一个 commit，Conventional Commits 格式，message 带 `refs #32`，逐路径 `git add`，禁 `git add -A`。**零 push。**
- 构建之前跑一次 `Scripts/machine-guard.sh` 并记录输出。并行度 6 以内。不用 `caffeinate`；一定要用就带秒数上限，不留孤儿进程。
- 不跑 Swift 的构建和测试，不打开任何图形程序，不运行 `darktable`，不下载安装任何软件，不安装任何编译目标。
- 不读、不打印任何凭据文件，报告里不出现密钥。
- 不碰用户照片库 `/Volumes/UNITEK/Cloud Drive/QSync/Medias/Photos/Workspace`：不读、不列目录。
- 机器上可能有别人同时在跑的 omp 会话，还有塔台派的一条只读调研 lane（不构建），都不是你的，不碰。守卫不过就等它过了再构建。
- 每个源文件带 SPDX 头 `GPL-3.0-or-later`。
- 数字不编。哪一项没做成，写没做成和卡在哪一步。到时间上限就交已有结果。
- 总墙钟不超过 180 分钟，含自审。

## 交付

1. 改名后的工作区和一个 commit。
2. `.work/gsd/phases/rust-core/waves/A8-REPORT.md`（中文正文，英文标题）：结论头，三行以内；新旧名字对照表（29 行）；盘点数字（每个区域多少文件、多少处）；「顺手做的一件小事」的命令与输出；验收清单每条的命令与输出；commit 的最终哈希与 `git show --stat` 的汇总；复审的结论头；「未做 / 未验」两段。

stdout 最后一条消息一次性完整输出同样内容。
