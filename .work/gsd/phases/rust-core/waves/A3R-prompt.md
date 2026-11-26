# 执行 lane A3R（omp）：把工作区重排成分层布局，加上强制依赖方向的检查和测试套件

## 背景

阶段 A 在连跑。A1（许可证）、A2（骨架）、A3（模块描述与自动注册）已完成。你是下一波，名字叫 A3R，R 是重排（re-layout）。

用户的裁决（已定，不要重开）：

- **框架学 LightCraft，兼容 darktable。** LightCraft 是引擎优先的分层工作区，依赖方向由检查强制；「一切皆命令」；每张照片带处理版本号。它的源码在本机 `/Volumes/UNITEK/Documents/Development/lightcraft`，只读，许可证是 MIT 或 Apache-2.0。设计和代码都可以取用，取用代码要在 `NOTICE` 里署名。
- **修改历史只存会话数据库**，没有 XMP，没有每张图的设置文件。照片按 Capture One 的会话管理。
- 模块自动发现和注册不能退回写名单。Apple 能力独占 `dt-apple`，只在 macOS 构建里存在。

先读：

- `.work/gsd/phases/rust-core/FRAMEWORK.md` 的 §1（LightCraft 怎样分层、怎样强制）、§9（映射与新布局）、§11（对计划的影响），以及 `FRAMEWORK-TABLES.md` 的 T-F9（新分层布局：层、crate、允许依赖谁）和 T-F10 的第 1、2 项（可取用的代码和署名写法）。
- `.work/gsd/phases/rust-core/PLAN-AMENDMENTS.md`，全部十五条。
- `crates/README.md`：现在 19 个包各是什么。
- `.work/gsd/phases/rust-core/waves/VERIFY.md` 的 A3 一节：上一波的核验，说明哪些东西不能动。

工作目录 `/Volumes/UNITEK/Documents/Development/Lightamer`。HEAD 先亲核并记录。全程中文，代码注释和标识符英文，commit message 英文。这一波**只搬空壳、建空壳、写检查和测试套件**，不写业务逻辑。

## 要做的

**1. 重排到 T-F9 的布局。** 用 `git mv`，保留历史。

- 改名两个：`dt-core` 改成 `dt-pipeline`，`dt-library` 改成 `dt-catalog`。它们都还是空壳。
- 删掉三个空壳：`dt-api`、`dt-app`、`dt-export`。它们的职责以后并进 `dt-engine`。
- 把 `dt-cli` 从 `crates/` 挪到 `apps/dt-cli`。工作区的成员改成 `crates/*` 加 `apps/*`。
- 新建空壳，风格和 A2 建的一样（继承工作区字段，一行文档注释，一个最简单的测试）：
  - L0：`dt-geom`、`dt-raster`、`dt-color-math`、`dt-sysmem`
  - L1：`dt-meta`、`dt-scenes`
  - L3：`dt-preview`、`dt-gpu`、`dt-merge`
  - L4：`dt-engine`
  - L5：`dt-mcp`
  - 测试套件：`dt-testkit`
- 重排完是 28 个包。`dt-gpui` 这一波不建，到 A7b 再建，但检查的表里要有它。
- crate 之间的依赖现在只有这些：四个域 crate 依赖 `dt-iop-traits`；`dt-registry` 依赖四个域 crate 和 `dt-iop-traits`。重排后它们都符合 T-F9 的方向，不用改。

**不许动的东西**：四个域 crate 里 `src/modules/` 下的模块桩，一个字节都不能变；`dt-registry/fixtures/` 下的夹具，一个字节都不能变。A3 写的测试和 `xtask` 的三个子命令（生成桩、同步检查、查模块名）要原样继续通过。查模块名那个子命令查的三个目录要跟着改名换掉：`dt-core` 没了，换成 `dt-pipeline`；`dt-api` 没了，换成 `dt-engine`。

**2. 分层检查。** 取 LightCraft 的 `xtask/src/layers.rs`（316 行，只读，不要在它的目录里运行任何东西），改造成我们的，放进 `crates/xtask/`。命令是 `cargo xtask layers`。

- 表按 T-F9 换：每一层有哪些 crate；同层之内允许的依赖链（L0 是 `dt-geom`、`dt-color-math`、`dt-raster`，L1 是 `dt-meta`、`dt-decode`，L2 是 `dt-registry`、`dt-history`、`dt-pipeline`）；界面 crate 的名单和它们的最小层号；测试套件只许作开发依赖；哪些 crate 不查（`apps/dt-cli` 和 `xtask`）。
- 规则照它原来的：只能向下依赖；同层依赖只许出现在允许的链上；界面 crate 不得低于第 5 层；测试套件不得作普通依赖。
- 它原来查不到的两处，要么补上，要么在检查的说明里写明查不到：传递依赖；表里登记了却已经不存在的 crate。后者对我们更要紧，因为以后还会改名和删空壳，表里留着一个不存在的名字应该报错。
- 每一条规则都要有单元测试：造一份带违规的依赖数据，检查必须报出来。
- 另外在真实的仓库上做一次活体负测：临时给一个 crate 加一条违规的依赖，比如让 `dt-iop-traits` 依赖 `dt-registry`，跑检查，必须以非零退出并指出这一条；然后撤掉。命令和输出写进报告，撤掉之后工作区要干净。

**3. 测试套件。** 取 LightCraft 的 `crates/testkit/src/lib.rs`（190 行），照搬改名成 `dt-testkit`。让一个已有的测试用它一次，证明接得上。

**4. 署名。** 凡是取自 LightCraft 的文件，文件头加一行 `// Derived from lightcraft <路径>（commit 0da998f2）`，说明是原样还是改造。`NOTICE` 里按 T-F10 的 N1 模板加 LightCraft 的条目。

**5. 总检查。** `Scripts/rust-ci-lite.sh` 里加上分层检查这一步，放在许可证检查之后。

**6. 地图。** 更新 `crates/README.md`：按层列出 28 个包，每个一行用途，哪一波会往里填。

## 计划规定的通用纪律（原样保留）

- 变换规则：不改任何封存面；新增依赖先过 A1（本波不新增依赖）。
- 验收清单：`cargo fmt --all --check` 与 `cargo clippy --workspace --all-targets -- -D warnings` 绿；`Scripts/machine-guard.sh` 在构建之前跑一次；任务书末尾附「未做 / 未验」。
- 通用纪律：`.work/` 之外不写计划面文件；一次只跑一个重活；报告里每个数字给命令。

## 7. 验收清单（命令和输出都写进报告）

- `cargo metadata --locked --no-deps --format-version 1 | jq '.packages | length'` 是 28。
- `cargo xtask layers` 退出 0，打印每一层有哪些 crate。
- 活体负测：按第 2 节做一次，检查以非零退出并点出那条违规；撤掉之后 `git status --porcelain` 里没有残留。
- `cargo test -p xtask` 绿，分层检查的每一条规则各有一个单元测试。
- `cargo test --workspace --locked` 绿，测试数不少于 A3 时的 33 个加上新建空壳自带的和 `xtask` 新增的。
- `cargo xtask check-order-sync` 和 `cargo xtask check-no-iop-names` 仍然通过，后者查的三个目录是换过之后的。
- `Scripts/rust-discovery-probe.sh` 仍然是两个方向都通过。
- `Scripts/check-licenses.sh` 不带参数，退出 0。
- `Scripts/rust-ci-lite.sh` 从头到尾退出 0，日志里能看到分层检查这一步跑过。
- 模块桩和夹具没变：`git diff --stat <起始 HEAD> HEAD -- 'crates/dt-iop-*/src/modules' crates/dt-registry/fixtures` 没有输出。
- 改名是 `git mv`：`git log --follow --oneline -- crates/dt-pipeline/Cargo.toml` 能追到 `crates/dt-core` 时期的提交。
- `rg -n 'dt-core|dt-api|dt-app|dt-export|dt-library' crates apps Scripts xtask 2>/dev/null` 在源码和脚本里没有残留的旧名字（文档和 `.work` 里的历史记录不用管）。
- `NOTICE` 里有 LightCraft 的条目；取自 LightCraft 的文件都有那行署名头。
- Swift 那边零改动：`App/`、`LightamerCore/`、`LightamerIOP/`、`Tests/`、`Project.swift`、`Tuist.swift`、两个 Xcode 工程都不在改动里。

## omp 域内自审（项目既定模型）

产物落盘并提交后，另起一个独立的 `omp -p --auto-approve --thinking max "<复审任务书>"` 实例复审。复审实例只读：重跑第 7 节的全部验收；对照 LightCraft 的 `layers.rs` 逐条核我们的检查有没有把它的规则抄漏；核对模块桩和夹具确实逐字节没变；核对 `git show --stat` 只含允许的路径。结论头 `PASS / N error + N minor`。发现的问题回注修订，修订记录附在报告末尾。复审输出落 `.work/gsd/phases/rust-core/waves/A3R-review.log`。

## 纪律

- **只允许新增或修改这些路径**：`crates/` 整个目录（含改名、删除、新建）；`apps/` 整个目录；根目录的 `Cargo.toml`、`Cargo.lock`、`crates/README.md`；`Scripts/rust-ci-lite.sh`，以及因为路径变了必须跟着改的 `Scripts/rust-*.sh`；`NOTICE`；`.work/gsd/phases/rust-core/waves/A3R-REPORT.md` 和 `A3R-review.log`。其它一律不动。
- 一个 commit，Conventional Commits 格式，message 带 `refs #32`，逐路径 `git add`，禁 `git add -A`。**零 push。**
- 构建之前跑一次 `Scripts/machine-guard.sh` 并记录输出。并行度 6 以内。不用 `caffeinate`；一定要用就带秒数上限，不留孤儿进程。
- 不跑 Swift 的构建和测试，不打开任何图形程序，不下载安装任何软件。
- 不读、不打印任何凭据文件，报告里不出现密钥。
- 不碰用户照片库 `/Volumes/UNITEK/Cloud Drive/QSync/Medias/Photos/Workspace`：不读、不列目录。
- 每个源文件带 SPDX 头 `GPL-3.0-or-later`。
- 数字不编。哪一项没做成，写没做成和卡在哪一步。到时间上限就交已有结果。
- 总墙钟不超过 240 分钟，含自审。

## 交付

1. 上面的文件和一个 commit。
2. `.work/gsd/phases/rust-core/waves/A3R-REPORT.md`（中文正文，英文标题）：结论头，三行以内；新的分层布局一张表；分层检查比 LightCraft 多查了什么、没查什么；第 7 节每条验收的命令与输出；commit 的最终哈希与 `git show --stat`；「未做 / 未验」两段。

stdout 最后一条消息一次性完整输出同样内容。
