# 执行 lane A4b（omp）：我们自己的历史模型，带每张照片的处理版本号

## 背景

阶段 A 在连跑。A1、A2、A3、A3R 已完成。工作区现在按层摆好了，共 28 个包。你这一波往 L2 的 `dt-history` 里写第一块有分量的逻辑。

用户的裁决（已定，不要重开）：

- **修改历史只存会话数据库。** 没有 XMP，没有每张图的设置文件。历史和设置的格式是我们自己的，**不照 darktable 的参数布局**，不做它的版本迁移链。
- **框架学 LightCraft。** 编辑模型学它那一套：设置是宽容演进的纯数据；每张照片带处理版本号；历史是快照。它的源码在本机 `/Volumes/UNITEK/Documents/Development/lightcraft`，只读，许可证是 MIT 或 Apache-2.0，设计和代码都能取用，取用代码要在 `NOTICE` 里署名。
- **核心里不写模块名单。** `dt-history` 是核心，源码里不许出现任何 darktable 模块名，测试里也不许。
- darktable 的模块顺序仍然照它（A3 已做），因为每个模块的输出都要和 darktable 官方渲染对照。

先读：

- `.work/gsd/phases/rust-core/FRAMEWORK.md` 的 §3（LightCraft 的编辑模型）和 §12 的 C3、C6（真相与版本、命令粒度）。C1 和 C7 两节是按「读 darktable 历史」写的，已经作废，见 `PLAN-AMENDMENTS.md` 的 A-12 和 A-15。
- `.work/gsd/phases/rust-core/PLAN-AMENDMENTS.md`，全部十五条。
- `crates/dt-iop-traits/src/lib.rs`：A3 做的模块描述，里面有参数字段的描述类型 `ParamField`。设置模型要和它对接。
- LightCraft 的源码，这些位置上一轮调研核过：
  - `docs/process-versions.md`：处理版本号的规则正本。
  - `crates/develop/src/settings.rs`：设置模型；`ProcessVersion` 从第 23 行起，宽容读取的规则在文件前部和第 103 到 120 行附近。
  - `crates/develop/src/lib.rs` 第 59 行：`hash64`，全部缓存键的核。
  - `crates/catalog/src/model.rs` 第 219 到 254 行：`HistoryStep`，每一步存一份设置的快照。
  - `crates/catalog/src/lib.rs` 第 73 行：历史的步数上限。
  - `crates/engine/src/lib.rs` 第 925 到 945 行附近：一次设置提交，以及拖动开始与结束怎样合并成一步。
  - `crates/develop/src/tests_process.rs`：它自己怎样测处理版本号。

工作目录 `/Volumes/UNITEK/Documents/Development/Lightamer`。HEAD 先亲核并记录。全程中文，代码注释和标识符英文，commit message 英文。这一波**只有数据模型和它的测试**：不接数据库，不接界面，不写管线。

## 要做的

**1. 设置模型。** 一张照片的设置是纯数据：

- 处理版本号。照 LightCraft 的规则：读的时候字段缺失或非法，当作第 1 版；遇到比自己认识的新版本号，保留它，不降级；只有显式的「升级到当前版本」才改它。
- 模块实例的列表。每个实例有：模块标识（就是 A3 描述里的标识）、多实例的序号、可选的名字、是否启用、参数。参数是「参数名到带类型的值」的映射。值的类型由你定，要够第 0 期的 21 个模块用：开关、整数、浮点、枚举、字符串、浮点列表（曲线和控制点要用）。先读 A3 的 `ParamField`，两边对得上。
- 宽容演进：读一份将来的格式，不认识的字段忽略，缺失的字段取默认值。不认识的模块标识和参数名要**保留**，不丢弃，等以后有这个模块时能用。这一点和 LightCraft 不同，是有意的：我们的模块是自动注册的，读设置时不认识的模块，可能只是这个构建里没有编进去。
- 描述里登记了参数字段时，按字段校验：类型不对、超出范围，报错，不悄悄改值。A3 的桩里字段还都是空的，所以校验路径现在多数走不到，测试里自己造带字段的描述来覆盖它。

**2. 规范的序列化。** 同一份设置，不管插入顺序怎样，序列化出来的字节必须一样。用 `serde` 加 `serde_json`，映射用有序的容器。外层带一个格式版本号。存储到会话数据库是后面的事，这一波只保证字节稳定、能原样读回。

**3. 缓存键。** 照 LightCraft 的 `hash64`：对规范的序列化做 FNV-1a 64 位，设置和处理版本号都算进去。对外同时给一个十进制字符串的形式，项目里凡是落盘的 64 位哈希都用十进制字符串。同样的设置必须得到同样的键；任何一个参数变了，键必须变。

**4. 历史。** 照 LightCraft：每一步存一份设置的快照，用 `Arc` 共享；有一个当前位置；步数有上限，超了丢最旧的。要有的操作：

- 提交一步。它会把当前位置之后的步全部丢掉。
- 撤销、重做、跳到某一步。
- 拖动合并：一次交互有一个开始和一个结束，中间不管改了多少次，结束时只提交一步；交互中途放弃，就回到这次交互之前的状态。还要规定开始之后一直没有结束时，下一次提交怎样处理。
- 把一张照片的调整拷到另一张：替换模块实例，但目标的处理版本号不变。
- 批量提交：一次改动同时作用到很多张照片，每张照片各得一步。批量的载体里**没有**处理版本号这个字段，从类型上就保证它带不过去。

每一步带一个标签，记是哪条命令提交的。

**5. 不崩溃的 lint。** 照 LightCraft 的做法，在这个 crate 的根部把这几条设为拒绝：直接下标索引、`unwrap`、`expect`、`panic!`、`todo!`、`unimplemented!`。测试代码放开前三条。这是工作区里第一个有真正逻辑的 crate，从它开始立这个规矩，后面的 crate 照做。

**6. 把 `dt-history` 加进「核心里不许出现模块名」的检查。** `cargo xtask check-no-iop-names` 现在查三个目录，改成四个。所以你的测试里造模块标识要用假名字，比如 `mod_a`。

**7. 新依赖的登记。** `serde` 和 `serde_json` 是新依赖，会带进几个传递依赖。每一条的许可证表达式必须已经在 `Scripts/licenses-allow.txt` 里；**如果有哪一条不在，停下报告，不要自己改那个文件。** 在 `docs/LICENSE-AUDIT.md` 里给每个此前没有登记的 crate 各追加一行：名称、版本、许可证、证据。`crates/README.md` 里 `dt-history` 那一行改成它现在的内容。

## 计划规定的通用纪律（原样保留）

- 变换规则：不改任何封存面；新增依赖先过 A1。
- 验收清单：`cargo fmt --all --check` 与 `cargo clippy --workspace --all-targets -- -D warnings` 绿；`Scripts/machine-guard.sh` 在构建之前跑一次；任务书末尾附「未做 / 未验」。
- 通用纪律：`.work/` 之外不写计划面文件；一次只跑一个重活；报告里每个数字给命令。

## 8. 验收清单（命令和输出都写进报告）

- `cargo test -p dt-history` 绿。下面每一项都要有一个测试，测试名能看出测的是什么：
  - 设置写出再读回，完全相等。
  - 不认识的字段被忽略，缺失的字段取默认值；不认识的模块和参数被保留。
  - 带字段描述时，类型不对和超出范围都报错。
  - 提交一步会丢掉重做部分；撤销、重做、跳转都对；超过上限丢最旧的。
  - 一次交互只成一步；交互中途放弃回到之前。
  - 拷贝调整后，目标的处理版本号不变。
  - 批量提交后每张照片各多一步；批量的载体里没有处理版本号。
  - 处理版本号缺失或非法时读成第 1 版；比自己新的版本号被保留。
  - 同样的设置得到同样的缓存键；改一个参数，键就变。
  - 插入顺序不同，序列化的字节完全相同。
- `cargo clippy -p dt-history -- -D clippy::indexing_slicing -D clippy::unwrap_used -D clippy::expect_used -D clippy::panic -D clippy::todo -D clippy::unimplemented` 绿。这几条是写在 crate 根部的，所以 `cargo clippy --workspace --all-targets -- -D warnings` 也绿。
- `cargo xtask layers` 退出 0。`dt-history` 只依赖分层表允许它依赖的 crate。
- `cargo xtask check-no-iop-names` 通过，查的是四个目录。
- `cargo xtask check-order-sync` 通过，`Scripts/rust-discovery-probe.sh` 两个方向都通过。
- `Scripts/check-licenses.sh` 不带参数，退出 0。
- `rg -n 'repr\(C\)|modversion|legacy_params' crates/dt-history` 没有输出。
- `cargo test --workspace --locked` 绿，测试数不少于之前的 62 个加上这一波新增的。
- `Scripts/rust-ci-lite.sh` 从头到尾退出 0。
- 模块桩和夹具没变：`git diff --stat <起始 HEAD> HEAD -- 'crates/dt-iop-*/src/modules' crates/dt-registry/fixtures` 没有输出。
- `git show --name-only HEAD` 里只有下面「纪律」一节允许的路径。

## omp 域内自审（项目既定模型）

产物落盘并提交后，另起一个独立的 `omp -p --auto-approve --thinking max "<复审任务书>"` 实例复审。复审实例只读：重跑第 8 节的全部验收；打开 LightCraft 的 `docs/process-versions.md` 逐条核我们的处理版本号规则有没有抄漏或抄错；核宽容读取的行为是不是真的保留不认识的模块；核批量的载体是不是从类型上就带不了处理版本号。结论头 `PASS / N error + N minor`。发现的问题回注修订，修订记录附在报告末尾。复审输出落 `.work/gsd/phases/rust-core/waves/A4b-review.log`。

## 纪律

- **只允许新增或修改这些路径**：`crates/dt-history/`；`crates/xtask/`（只许改查模块名那个子命令查的目录和它的测试）；根目录的 `Cargo.toml` 和 `Cargo.lock`；`docs/LICENSE-AUDIT.md`（只追加行）；`crates/README.md`（只改 `dt-history` 那一行）；`NOTICE`（只有取用了 LightCraft 的代码才动）；`.work/gsd/phases/rust-core/waves/A4b-REPORT.md` 和 `A4b-review.log`。其它一律不动。
- 一个 commit，Conventional Commits 格式，message 带 `refs #32`，逐路径 `git add`，禁 `git add -A`。**零 push。**
- 构建之前跑一次 `Scripts/machine-guard.sh` 并记录输出。并行度 6 以内。不用 `caffeinate`；一定要用就带秒数上限，不留孤儿进程。
- 不跑 Swift 的构建和测试，不打开任何图形程序，不下载安装任何软件。不在 LightCraft 的目录里运行任何东西。
- 不读、不打印任何凭据文件，报告里不出现密钥。
- 不碰用户照片库 `/Volumes/UNITEK/Cloud Drive/QSync/Medias/Photos/Workspace`：不读、不列目录。
- 每个源文件带 SPDX 头 `GPL-3.0-or-later`。
- 数字不编。哪一项没做成，写没做成和卡在哪一步。到时间上限就交已有结果。
- 总墙钟不超过 240 分钟，含自审。

## 交付

1. 上面的代码、测试和一个 commit。
2. `.work/gsd/phases/rust-core/waves/A4b-REPORT.md`（中文正文，英文标题）：结论头，三行以内；设置模型和历史模型的要点，以及和 LightCraft 不同的一处（保留不认识的模块）及理由；新增了哪些依赖、各自是否在允许清单里；第 8 节每条验收的命令与输出；commit 的最终哈希与 `git show --stat`；「未做 / 未验」两段。

stdout 最后一条消息一次性完整输出同样内容。
