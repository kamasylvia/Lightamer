# 执行 lane A2（omp）：Rust 工作区骨架

## 背景

开发计划的阶段 A 在连跑。A1（许可证核查）已经完成。你是第二波。先读：

- `.work/gsd/phases/rust-core/PLAN.md` 的 A2 那张波次卡（阶段 A 里第二张）和 §3.0 的共用任务书模板。计划顶部有一行修订提示。
- `.work/gsd/phases/rust-core/PLAN-AMENDMENTS.md`：全部八条。和本波直接相关的是 A-4（工作区放仓库根目录，与冻结的 Swift 代码树并存）、A-5（脚本放已有的 `Scripts/`）、A-8（脚本文件名带 `rust-` 前缀）。
- `.work/gsd/phases/rust-core/PLAN-TABLES.md` 的 T2：crate 清单、目录布局、体积与时间预算的门。
- `docs/LICENSE-AUDIT.md` 的 §1：本项目的许可政策。A1 产出的 `Scripts/check-licenses.sh` 和两个数据文件也在。

用户的有关裁决，照做：全部用 Rust；Apple 能力独占一个模块（`dt-apple`），只在 macOS 构建里存在；核心里不写模块名单；许可证 `GPL-3.0-or-later`；旧的 Swift 版冻结。

工作目录 `/Volumes/UNITEK/Documents/Development/Lightamer`。HEAD 先亲核并记录。全程中文，commit message 英文。这一波**只建骨架和脚本，不写任何业务逻辑，不建界面 crate**。

## 要做的

**1. 工作区放在仓库根目录。** 根目录现在有 Xcode 和 Tuist 的工程文件，以及 Swift 的三个包目录。Rust 工作区与它们并存，互不影响：

- `Cargo.toml`：工作区成员是 `crates/*`。工作区级的包字段：版本 `0.1.0`、edition `2024`、最低 Rust `1.100`、许可证 `GPL-3.0-or-later`、不发布。工作区级的 lint 设置你自己定一个合理的起点，并写进报告。构建 profile 也定一个起点。
- `rust-toolchain.toml`：钉 `1.100.0`，带 `rustfmt` 和 `clippy`。本机已经装了这个版本。
- `.cargo/config.toml`：并行度上限 6（机器一次只跑一个重活，这是项目规定），加几个常用的命令别名。
- `Cargo.lock` 入库。`.gitignore` 加上 Rust 的构建目录，构建目录绝不入库。

**2. 空 crate 骨架。** 按 T2 的清单建，**除了 `dt-gpui`**，它到 A7b 再建。每个 crate：`Cargo.toml` 继承工作区字段；`src/lib.rs` 只有一行说明用途的文档注释和一个最简单的测试。`dt-cli` 用 `src/main.rs`，打印自己的名字和版本后退出 0。`dt-apple` 现在就是一个普通的空 crate，macOS 门控是 A6 的事。

这一波**不引入任何外部依赖**，crate 之间也先不互相依赖，这样冷构建只剩编译器自己的开销。`dt-cli` 也先不要参数解析库。

另建一个 `xtask` crate，只做一件事：`check-i18n`。它比较指定目录下的键表；现在没有任何键表，所以打印一句说明后退出 0。骨架留好，B17 起才会真正用到。

**3. 脚本。** 全部放 `Scripts/`，可执行，过 `bash -n`。已有的 `Scripts/machine-guard.sh` 是 Swift 版也在用的守卫脚本，**复用，不重写，不改一个字**。

- `Scripts/rust-guard.sh`：调用 `machine-guard.sh`。不带参数时立刻返回它的结果；带 `--wait` 时轮询到通过为止，有上限，并定期打印状态。
- `Scripts/rust-build.sh [--cold]`：`--cold` 先清构建目录；然后 `cargo build --workspace --locked`，并行度 6，打印耗时。
- `Scripts/rust-test.sh`：格式检查、`cargo clippy --workspace --all-targets -- -D warnings`、`cargo test --workspace --locked`，打印测试数量。
- `Scripts/rust-budget.sh [--cold]`：量四项并对照 T2 的门，任何一项越门就以 1 退出。四项是：冷构建时间（`--cold` 时量）、单个 crate 的增量检查时间（用 `cargo check -p dt-iop-color`）、界面 release 二进制的体积（现在没有就标不适用）、构建目录的体积。
- `Scripts/rust-ci-lite.sh`：一条命令串起来。守卫（不等待，不过就停）、许可证检查、构建、测试、预算。脚本开头 `set -euo pipefail`。

**4. `crates/README.md`。** 一张简短的地图：每个 crate 一行用途，哪一波会往里填东西，指向 `PLAN.md`。

## 计划规定的通用纪律（原样保留）

- 变换规则：不改任何封存面；新增依赖先过 A1（本波不新增依赖）。
- 验收清单：本波卡片第 5 条的命令逐条跑绿，加上本任务书第 5 节的几条；`cargo fmt --all --check` 与 `cargo clippy --workspace --all-targets -- -D warnings` 绿；`Scripts/machine-guard.sh` 在构建之前跑一次；任务书末尾附「未做 / 未验」。
- 通用纪律：`.work/` 之外不写计划面文件；一次只跑一个重活；报告里每个数字给命令。

## 5. 验收清单（命令和输出都写进报告）

- 每个脚本的 `bash -n` 通过。本机没有 shellcheck，写明「未跑」。
- `time Scripts/rust-build.sh --cold` 不超过 6 分钟。
- `Scripts/rust-test.sh` 退出 0。
- `time cargo check -p dt-iop-color` 不超过 40 秒。
- `Scripts/rust-budget.sh --cold` 退出 0。
- `Scripts/rust-guard.sh` 退出 0。
- `Scripts/check-licenses.sh` 不带参数，退出 0。根工作区的包许可证字段都齐了，所以 A1 报告里登记的那几条 spike 例外在本仓库上用不到。
- `cargo xtask check-i18n` 退出 0。
- `cargo metadata --locked --no-deps` 列出的包数等于 T2 清单减一，再加 `xtask`。
- **Swift 那边零改动**：`git status --porcelain` 里只有本波的路径；`git diff --stat -- Scripts/machine-guard.sh Scripts/test-direct.sh` 为空；`App/`、`LightamerCore/`、`LightamerIOP/`、`Tests/`、`Project.swift`、`Tuist.swift`、`Lightamer.xcworkspace`、`Lightamer.xcodeproj` 一个都没有出现在改动里。

## omp 域内自审（项目既定模型）

产物落盘并提交后，另起一个独立的 `omp -p --auto-approve --thinking max "<复审任务书>"` 实例复审。复审实例只读：重跑第 5 节的全部验收命令；核对 `git show --stat` 只含本波的文件；抽查三个 crate 的 `Cargo.toml` 字段是否继承工作区。结论头 `PASS / N error + N minor`。发现的问题回注修订，修订记录附在报告末尾。复审输出落 `.work/gsd/phases/rust-core/waves/A2-review.log`。

## 纪律

- **只允许新增或修改这些路径**：根目录的 `Cargo.toml`、`Cargo.lock`、`rust-toolchain.toml`、`.cargo/config.toml`、`.gitignore`（只追加）；`crates/` 整个目录；`Scripts/rust-guard.sh`、`Scripts/rust-build.sh`、`Scripts/rust-test.sh`、`Scripts/rust-budget.sh`、`Scripts/rust-ci-lite.sh`；`.work/gsd/phases/rust-core/waves/A2-REPORT.md` 和 `A2-review.log`。其它一律不动。
- 一个 commit，Conventional Commits 格式，message 带 `refs #32`，逐路径 `git add`，禁 `git add -A`。**零 push。**
- 构建之前跑一次 `Scripts/machine-guard.sh` 并记录输出。并行度 6 以内。不用 `caffeinate`；一定要用就带秒数上限，不留孤儿进程。
- 不跑 Swift 的构建和测试，不打开任何图形程序，不下载安装任何软件。
- 不读、不打印任何凭据文件，报告里不出现密钥。
- 不碰用户照片库 `/Volumes/UNITEK/Cloud Drive/QSync/Medias/Photos/Workspace`：不读、不列目录。
- 数字不编。哪一项没做成，写没做成和卡在哪一步。到时间上限就交已有结果。
- 总墙钟不超过 150 分钟，含自审。

## 交付

1. 上面的文件和一个 commit。
2. `.work/gsd/phases/rust-core/waves/A2-REPORT.md`（中文正文，英文标题）：结论头，三行以内；第 5 节每条验收的命令与输出；你定的工作区 lint 和 profile 起点及理由；commit 的哈希与 `git show --stat`；构建目录的大小；「未做 / 未验」两段。

stdout 最后一条消息一次性完整输出同样内容。
