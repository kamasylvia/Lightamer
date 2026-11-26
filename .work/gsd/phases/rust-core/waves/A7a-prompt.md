# 执行 lane A7a（omp）：命令分发口，一切皆命令

## 背景

阶段 A 在连跑。A1 到 A6 已完成（A6 是 Apple 模块边界）。工作区按层摆好，共 28 个包。`crates/dt-engine` 在第 4 层，现在还是空壳。`crates/dt-history`（第 2 层）在 A4b 有了我们自己的历史模型：一张照片的设置、处理版本号、快照式的历史栈、交互的合并、拷贝调整和批量提交。

用户的裁决（已定，不要重开）：

- **框架学 LightCraft，一切皆命令。** 界面、命令行、MCP 今后都只走同一个入口。它的源码在本机 `/Volumes/UNITEK/Documents/Development/lightcraft`，只读，许可证是 MIT 或 Apache-2.0，骨架可以改造取用，取用要在 `NOTICE` 里署名。
- **形态已经改过一次**（`PLAN-AMENDMENTS.md` 的 A-17，先读）：不做消息管道，不做带超时的远程查询。`dt-engine` 的 `execute` 是唯一入口；读状态直接拿快照；事件是状态变更的通知；费时间的活是作业，不放在命令里做。
- **修改历史只存会话数据库**（A-15）。数据库是 B12′ 的事，**这一波数据全放内存**，不建任何文件，不引入 SQLite。
- **核心里不写模块名单。** `check-no-iop-names` 查的四个目录里有 `dt-engine`，你的源码和测试里不许出现任何 darktable 模块名，要模块就用假名字，或者运行时从注册表里取（见下面第 7 节的提醒）。
- 菜单位置和快捷键不写进引擎的命令里。

先读：

- `.work/gsd/phases/rust-core/PLAN-AMENDMENTS.md`，全部十七条。A-17 和 A-15 是这一波的直接依据。
- `.work/gsd/phases/rust-core/FRAMEWORK.md` 的 §2（LightCraft 的引擎与命令）和 §12 的 C6（命令粒度）。
- `.work/gsd/phases/rust-core/ARCHITECTURE-TABLES.md` 的 T-A8：会话架构下的命令清单。**命令标识照它写**，一个字都不要改，以后各波按同一套名字往里加。这一波只做其中编辑和历史那一类。
- `crates/dt-history/src/`：A4b 的模型，这一波的命令全部架在它上面。先读它的测试，看每个操作许诺了什么。
- `crates/dt-registry/src/lib.rs`：按标识找模块描述的入口。
- LightCraft 的源码，这些位置调研时核过：
  - `crates/engine/src/cmd/mod.rs`（225 行）：命令声明、查找、分发的骨架。
  - `crates/engine/src/lib.rs`：第 512 到 513 行是唯一入口；第 587 行附近是一次提交怎样记一步；第 724 和 749 行附近是撤销和重做怎样也是命令；第 925 到 945 行附近是拖动的开始与结束怎样合并成一步。
  - `crates/engine/src/activity.rs`（438 行）：长活的登记、进度、取消。
- `.work/gsd/phases/rust-core/waves/VERIFY.md` 的 A6 一节（塔台核完 A6 之后才有）。

工作目录 `/Volumes/UNITEK/Documents/Development/Lightamer`。HEAD 先亲核并记录（塔台派你时是 `1fcbbeab`）。全程中文，代码注释和标识符英文，commit message 英文。这一波**只有引擎层的分发口和编辑类命令**：没有像素，没有数据库，没有文件，没有界面。

## 要做的

**1. 命令的声明和登记。** 照 LightCraft 的骨架改：

- 每条命令是一条静态的声明：标识、一句话说明、参数的清单、能不能跑的判断、跑的函数。
- 参数是带类型的值的映射（`serde_json::Value`，和 LightCraft 一样），但**每条命令都带一份机器可读的参数清单**。LightCraft 没有这一份，是它的缺口，我们不继承。清单里每个参数有：名字、种类、是否必填、说明。种类够这一波用就行：开关、整数、浮点、文本、枚举、照片标识的列表、补丁（一次要改的参数）。
- 登记表是一张静态的数组，按类分成几个模块，汇总成一个函数。另给一个按标识查找的函数。
- 标识不许重复；清单里参数的名字不许重复；每条命令都有说明。这三条要有测试。
- 不放进声明里的东西：菜单、快捷键、日志回放。这一波用不到，以后要再加字段。

**2. `execute` 的契约。** `Engine::execute(&mut self, id, params) -> Result<Outcome, CommandError>`。下面每一条都要有测试：

- **要么全做成，要么什么都没发生。** 任何一个环节出错，引擎的状态和调用之前逐字节相同。「状态」指每一张照片的设置、历史、当前位置、处理版本号，加上剪贴板和作业表。比对的办法用 A4b 的 `hash64_decimal`，对全部照片算一个汇总值。
- 出错是分类型的，至少分清：没有这条命令；参数里有不认识的键；缺必填的参数；参数的类型不对或超出范围；这条命令现在不能跑（带原因）；没有打开的会话；没有这张照片；没有在进行的交互；重入。每种都要能变成一句人能读的话。
- **命令只做有界的活。** 这一波没有落盘，命令只改内存。以后从 B13′ 起，命令可以带至多一次有界的落盘（一条小事务）。无界的活不许放在命令里：拷文件、扫文件夹、解码、渲染、编码、整包备份、等网络。这些由命令启动成作业，见第 5 节。crate 文档里就按这个写，别写成「命令永不碰磁盘」，那是这一波的口径，不是定稿。
- 改历史的命令，每张照片恰好记一步，这一步的标签就是命令的标识（A4b 的栈已经给每一步留了标签）。
- **不能跑的命令不许跑。** 每条声明带一个判断（现在有没有打开的会话、有没有选中的照片之类）。判断说不能跑，`execute` 就返回带原因的错误，状态不变。
- **重入**：事件的监听者里面再调 `execute`，返回重入的错误，不嵌套执行。

**3. 编辑和历史类的命令。** 标识照 T-A8，架在 A4b 的模型上。数据放内存：引擎里一张表，照片标识到它的历史栈。

| 命令 | 做什么 |
|---|---|
| `develop.set` | 一批照片，一个模块，一块补丁。模块的标识必须能在注册表里找到，找不到是参数错误。每张照片记一步。 |
| `develop.reset` | 一批照片回到默认设置，每张记一步。 |
| `develop.copy` | 把一张照片的调整放进引擎的剪贴板。 |
| `develop.paste` | 把剪贴板里的调整贴到一批照片上，每张记一步。目标照片的处理版本号不变（A4b 已经保证）。剪贴板是空的是错误。 |
| `develop.beginInteraction` / `develop.updateInteraction` / `develop.endInteraction` / `develop.cancelInteraction` | 一张照片上的一次拖动。对应 A4b 的四个操作。结束时只记一步；中途放弃回到之前。 |
| `history.undo` / `history.redo` / `history.goto` | 对应 A4b 的撤销、重做、跳转。 |
| `process.update` | 一批照片升到当前的处理版本号。 |

补丁里的参数怎样校验，照 A4b：模块描述里登记了字段就按字段校验，没登记就只要求值是带类型的。A3 的桩现在字段都是空的，所以测试里要自己造带字段的描述来覆盖校验那一条，A4b 的测试是这么做的。

批量的语义现在照 A4b：只有整份替换一种。按模块、按参数的合并归以后的波。

会话类的命令（`session.*`、`library.*`、`photo.*`、`export.*`）这一波**不登记**。登记一条只会报「没实现」的命令等于骗人。

**4. 内存里的草稿会话。** 引擎刚建出来没有会话，这时除了只读的以外都不能跑。另给一个构造函数，打开一个**草稿会话**：给它一组照片的标识，全部放内存，不落盘。它的用途是无界面的测试、命令行和以后的 MCP 演示。说明里写清楚：草稿会话没有任何持久化，B12′ 之后正式的会话由会话命令打开。

**5. 作业。** 费时间的活由命令启动成一个作业：

- 作业在一个固定大小的工作线程池上跑，先进先出。池的大小是一个写明的常量。
- 作业拿到的是状态的**不可变快照**，不许碰引擎的状态。作业的产物和进度先放进引擎里的一张队列。
- 引擎上有一步「收取」：把队列里的进度和完成取出来，变成事件。它只在引擎自己的线程上调。
- 作业能取消：给作业一个取消的令牌，作业在下一段活之前自己看一眼；另有一条命令 `job.cancel`。取消之后完成事件里要写明是被取消的。
- 作业表能读：有哪些作业、各自的状态和进度。
- 引擎被丢弃时，还没完的作业要停下来，线程要退出，不留孤儿线程。

这一波没有任何真实的费时间的活，所以**不登记任何启动作业的用户命令**。作业这一套只在测试里用一段合成的活来证明（比如算一段和，分几段报进度），并且收在引擎的公开接口上，B1 的渲染和 B15 的缩略图直接用。

**6. 事件和快照。**

- 事件至少覆盖：照片的设置或历史变了（带照片标识、步数、当前位置）；剪贴板变了；作业开始、进度、结束（结束带成功还是取消）。名字你定，每一条都要有测试证明它在什么时候送出、送出几次。
- 一条命令里改了多处，事件按顺序攒着，**命令做完之后**一次送出；出错的那次调用一个事件都不送。
- 监听者可以登记和注销。同一个事件送给每一个登记着的监听者，各一次。
- 快照是只读的视图：某张照片当前的设置、历史里有哪些步、当前在第几步；作业表；有没有打开的会话。快照是便宜的，界面上每次重画都可以取。

**7. 三条提醒。**

- 源码和测试里不许出现 darktable 的模块名。测试里要用一个真实存在的标识时，运行时从注册表里取第一个，不要写成字面量。
- 取自 LightCraft 的文件，文件头加一行 `// Derived from lightcraft <路径>（commit 0da998f2）`，说明是原样还是改造。`NOTICE` 里按 `FRAMEWORK-TABLES.md` 的 T-F10 加条目。
- 不崩溃的 lint 照 A4b 的规矩写在 crate 根部：直接下标索引、`unwrap`、`expect`、`panic!`、`todo!`、`unimplemented!` 一律拒绝，测试代码放开前三条。

**8. 命令行。** `dt-cli` 加两个子命令，它从此依赖 `dt-engine`：

- `dt-cli commands [标识]`：列出登记的命令，每个带说明、什么时候能跑、参数清单。
- `dt-cli run`：在一个草稿会话上，照一份文件逐条执行命令。文件每行一条命令的 JSON（标识加参数），这样命令行、将来的 MCP 和验收脚本用的是同一种喂法。每执行一条，打印一行：是哪条、成功还是失败、失败的原因、每一张照片的步数和当前位置、状态的汇总值。任何一条失败就以非零退出。

`dt_engine` 的 crate 文档（rustdoc）就是这一层的说明：契约、怎样加一条命令、作业怎样写、事件什么时候送。不另写文档文件。

**9. 依赖。** 这一波预期的新依赖只有 `serde_json`（`dt-engine` 和 `dt-cli` 用，`dt-history` 已经在用，审计表里有）。工作线程池用标准库。每一条许可证表达式必须已经在 `Scripts/licenses-allow.txt` 里；**有哪一条不在，停下报告，不要自己改那个文件。** 此前没登记过的 crate，在 `docs/LICENSE-AUDIT.md` 里各追加一行。`crates/README.md` 里 `dt-engine` 和 `dt-cli` 的行改成现在的内容。

## 计划规定的通用纪律（原样保留）

- 变换规则：不改任何封存面；新增依赖先过 A1。
- 验收清单：`cargo fmt --all --check` 与 `cargo clippy --workspace --all-targets -- -D warnings` 绿；`Scripts/machine-guard.sh` 在构建之前跑一次；任务书末尾附「未做 / 未验」。
- 通用纪律：`.work/` 之外不写计划面文件；一次只跑一个重活；报告里每个数字给命令。

## 10. 验收清单（命令和输出都写进报告）

- `cargo test -p dt-engine --locked` 绿。第 2 节契约的每一条、第 3 节每一条命令、第 5 节和第 6 节的每一条，都各有一个测试，测试名能看出测的是什么。其中「出错后状态不变」要对每一条登记了的命令各跑一遍三种坏参数。
- `cargo test -p dt-cli --locked` 绿，命令行那两个子命令的解析和出错路径有测试。
- `cargo clippy -p dt-engine -- -D clippy::indexing_slicing -D clippy::unwrap_used -D clippy::expect_used -D clippy::panic -D clippy::todo -D clippy::unimplemented` 绿。
- `rg -n 'thread::spawn|thread::Builder|spawn\(' crates/dt-engine/src` 的每一处命中都在作业那个模块里。
- `rg -n 'std::fs|File::|std::net|TcpStream' crates/dt-engine/src` 没有输出。
- `cargo xtask layers` 退出 0，`dt-engine` 直接依赖的只有第 0 到第 3 层里它该依赖的。`cargo xtask check-no-iop-names` 通过，`cargo xtask check-apple-boundary`、`cargo xtask check-order-sync` 仍然通过。
- `Scripts/check-licenses.sh` 不带参数，退出 0。
- `cargo test --workspace --locked` 绿，测试数不少于之前的 132 个加上这一波新增的。
- `Scripts/rust-ci-lite.sh` 从头到尾退出 0。
- 模块桩和夹具没变：`git diff --stat <起始 HEAD> HEAD -- 'crates/dt-iop-*/src/modules' crates/dt-registry/fixtures` 没有输出。`dt-history` 没变：`git diff --stat <起始 HEAD> HEAD -- crates/dt-history` 没有输出（这一波只许用它，不许改它；真觉得它缺东西，写进报告）。
- 一份五行的命令文件走通：`develop.set`、`history.undo`、`history.redo`、`history.goto`、`develop.paste`，打印出来的步数、位置和汇总值和手算的一致。文件里再用一个不认识的模块标识跑一次，以非零退出。
- 对照工具和 A6 的东西没被弄坏：`target/debug/dt-cli help` 里 A5、A6 的子命令都还在，`target/debug/dt-cli capabilities` 照常。
- `git show --name-only HEAD` 里只有下面「纪律」一节允许的路径。

## omp 域内自审（项目只信重跑过的数字）

产物落盘并提交后，另起一个独立的 `omp -p --auto-approve --thinking max "<复审任务书>"` 实例复审。复审实例只读，但可以运行构建和测试：重跑第 10 节的全部验收；对照 LightCraft 的 `cmd/mod.rs` 和 `lib.rs` 逐条核骨架有没有抄漏（查找、分发、提交记一步、撤销重做也是命令、拖动合并）；核「出错后状态不变」是不是对每条命令都真的测了；核取自 LightCraft 的代码是不是都有署名头和 `NOTICE` 条目；核有没有哪条命令在里面等线程或碰磁盘；核 `git show --stat` 只含允许的路径。结论头 `PASS / N error + N minor`。发现的问题回注修订，修订记录附在报告末尾。复审输出落 `.work/gsd/phases/rust-core/waves/A7a-review.log`。

## 纪律

- **只允许新增或修改这些路径**：`crates/dt-engine/` 整个目录；`apps/dt-cli/`（只许加 `commands` 和 `run` 两个子命令和清单里的依赖）；根目录的 `Cargo.toml` 和 `Cargo.lock`；`crates/README.md`（只改 `dt-engine` 和 `dt-cli` 的行）；`docs/LICENSE-AUDIT.md`（只追加行）；`NOTICE`（只有取用了 LightCraft 的代码才动）；`.work/gsd/phases/rust-core/waves/A7a-REPORT.md` 和 `A7a-review.log`。其它一律不动。
- 一个 commit，Conventional Commits 格式，message 带 `refs #32`，逐路径 `git add`，禁 `git add -A`。**零 push。**
- 构建之前跑一次 `Scripts/machine-guard.sh` 并记录输出。并行度 6 以内。不用 `caffeinate`；一定要用就带秒数上限，不留孤儿进程。
- 不跑 Swift 的构建和测试，不打开任何图形程序，不运行 `darktable`，不下载安装任何软件，不安装任何编译目标。不在 LightCraft 的目录里运行任何东西。
- 不读、不打印任何凭据文件，报告里不出现密钥。
- 不碰用户照片库 `/Volumes/UNITEK/Cloud Drive/QSync/Medias/Photos/Workspace`：不读、不列目录。这一波不需要任何样张。
- 机器上可能有别人同时在跑的 `darktable-cli` 或别的 omp 会话，不是你的，不碰；守卫不过就等它过了再构建。
- 每个源文件带 SPDX 头 `GPL-3.0-or-later`。
- 数字不编。哪一项没做成，写没做成和卡在哪一步。到时间上限就交已有结果。
- 总墙钟不超过 240 分钟，含自审。

## 交付

1. 上面的代码、测试和一个 commit。
2. `.work/gsd/phases/rust-core/waves/A7a-REPORT.md`（中文正文，英文标题）：结论头，三行以内；命令声明的样子和登记表；`execute` 的契约；这一波登记了哪些命令，各自记不记历史步；作业和事件各自怎样工作；那份五行命令文件的原文和输出；新增了哪些依赖；取用了 LightCraft 的哪些文件；第 10 节每条验收的命令与输出；commit 的最终哈希与 `git show --stat`；「未做 / 未验」两段。

stdout 最后一条消息一次性完整输出同样内容。
