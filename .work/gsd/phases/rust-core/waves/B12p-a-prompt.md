# 执行 lane B12′-a（omp）：会话库——建表、迁移架、单写者锁、会话包的目录结构

## 背景

阶段 A（地基）已经全部做完：工作区按层摆好，crate 已经改名成 `lightamer-` 前缀，命令分发口（`lightamer-engine` 的 `execute`）、Apple 模块边界、对照工具都在位。**阶段 B 是第 0 期，从这一波开始，每一波做完都要停下来给用户看。** 你是阶段 B 的第一波的前一半。

用户的裁决（已定，不要重开）：

- **照片按 Capture One 的会话管理**：每一组照片是一个会话，是一个普通的文件夹，默认建 `Capture/`、`Selects/`、`Output/`、`Trash/` 四个子文件夹，有一个数据库。
- **修改历史只存会话数据库**（SQLite，开 WAL，一个会话一个库文件 `<Name>.lmsessiondb`）。没有 XMP，没有每张图的设置文件。**历史怎样存是下一波的事，你这一波只把库建起来。**
- 同一个会话同一时刻只许一个写入者。备份是拷会话文件夹；升级库的版本之前自动留一份备份。
- `Output/` 里的导出产物要进图库预览（登记是以后导出那一波的事，你不用管，表里有地方放就行）。
- 框架学 LightCraft，单写者锁的语义照它，取用它的代码要署名。许可证 GPL-3.0-or-later。

先读（都在 `.work/gsd/phases/rust-core/` 下，除非写了别的路径）：

- `PLAN-B.md`：阶段 B 的计划。读 §1 全部（会话包和数据库的设计，含 §1.4 版本和迁移、§1.5 锁、§1.6 备份和校验、§1.7 崩溃、§1.8 落库的次序、§1.9 命令和作业的界线）、§7（塔台的六处裁定，**T1 和 T2 直接管你的表**），以及 B12′ 那张卡。
- `PLAN-B-TABLES.md` 的 T-B1：建表语句的全表，照它建；T-B4：选型的结论和依赖的版本。
- `ARCHITECTURE-TABLES.md` 的 T-A1：Capture One 会话的证据（只看你用得上的那几行）。
- `FRAMEWORK-TABLES.md` 的 T-F9（层表：你写的 crate 在第 3 层，只能依赖第 0 到第 2 层）和 T-F10（取用 LightCraft 代码怎样署名）。
- LightCraft 的源码 `/Volumes/UNITEK/Documents/Development/lightcraft`（只读，不要在里面运行任何东西）：`crates/catalog/src/lock.rs`，单写者锁。
- 仓库的 `AGENTS.md` 里「M2-2 架构增量」那条：旧 Swift 版用 SQLite 时立下的几条做法——一个库文件、开 WAL、迁移之前先留备份、备份要走在线的一致性拷贝而不是裸拷文件。做法可取，代码不抄。
- `crates/lightamer-history/src/`：历史模型。**这一波不许改它，也不许往库里写历史。** 你只需要知道 `hash64_decimal` 是什么，表里有一列要放它。
- `.work/gsd/phases/rust-core/waves/VERIFY.md` 的最后四节。

工作目录 `/Volumes/UNITEK/Documents/Development/Lightamer`。HEAD 先亲核并记录。全程中文，代码注释和标识符英文，commit message 英文。

## 要做的

**只动一个 crate：`crates/lightamer-catalog`（第 3 层）。** 引擎、命令行、别的 crate 这一波都不碰。你交出去的是一组函数和一个连接类型，下一波（B12′-b）拿它们在引擎里接上七条会话命令。

**1. 依赖。** `rusqlite`，开 `bundled` 和 `backup` 两个特性，关掉默认特性（理由在 T-B4），版本照 T-B4。它带进来的传递依赖会出现在锁文件里。**每一条许可证表达式必须已经在 `Scripts/licenses-allow.txt` 里；有哪一条不在，停下报告，不要自己改那个文件。** 在 `docs/LICENSE-AUDIT.md` 里给每个此前没有登记的 crate 各追加一行。内嵌的 SQLite 是一段 C 代码，要用 `cc` 编，所以冷构建会变慢，见第 7 节。

**2. 建表。** T-B1 的建表语句原样落成 schema 第 1 版：`_meta`、`photos`、`snapshots`、`history_steps`、关键词、相册、收藏各自的表和索引。打开库或新建库时设好的几项（日志模式、同步档、外键、库版本号）集中在一个函数里做，不许散在各处。

- T-B1 里 `snapshots` 表的注释写明了塔台的两条裁定，照做：表里只有键和内容两列，**不存引用计数**；键的缺省值是内容的十进制哈希，哈希碰撞时加后缀。这一波只建表，写入的规则是下一波的，但表结构从现在起就是这样。
- `_meta` 里的 `display_aux` 这一项只建位置：给一对读写它的函数（值是一段 JSON 文本，原样存取），外加「取出来解析不了时怎么办」的一条规定（当作没有，返回空，并把这件事报给调用者）。谁往里写什么内容是别的波的事。

**3. 迁移架。** 库的版本号记在 SQLite 的 `user_version` 里，`_meta` 里另存一份镜像；两处由同一个函数写，有测试断言它们相等。

- 迁移是一张只往后加的表：从第几版到第几版，各执行什么。现在只有第 1 版（建表）。
- 打开一个版本比本构建旧的库：先自动留一份备份 `<名字>.pre-migrate.<旧>-<新>.bak`，用 SQLite 的在线备份接口拷，**不许裸拷文件**（日志模式下裸拷会丢尾部的事务）；然后逐版迁移，每一版一个事务。
- 打开一个版本比本构建新的库：**拒绝**，返回一个分了类型的错误，带上那个版本号；一个字节都不写。
- 备份失败就不迁移，库保持原样。

**4. 单写者锁。** 照 LightCraft 的 `lock.rs` 改造（文件头加一行 `// Derived from lightcraft <路径>（commit <你看的那个提交号>）`，说明是原样还是改造；`NOTICE` 里按 T-F10 加条目）：

- 会话文件夹根下的 `session.lock`，用操作系统级的独占文件锁（标准库的文件加锁就够）。打开会话就拿着，关会话时**显式**释放。
- 旁边一个 `session.lock.owner`，写持有人是谁（进程号、主机名、程序名和版本）。它只是给人看的提示：可以缺失，进程崩了留下来的也不算数。
- 第二个打开者得到「正在被使用」的错误，带上持有人的信息。
- 文件系统不支持文件锁时（有些网络共享）：降级成不加锁地打开，但要把这件事报给调用者。
- 进程被强杀：锁由操作系统收回，留下来的文件不妨碍下次打开。

**5. 会话包的目录结构。** 一组函数，各自只做一件有界的小事，都在这个 crate 里（文件操作不进引擎）：

- 新建一个会话：建根文件夹（名字就是会话名，已存在且不是空的就拒绝）、四个子文件夹、空的库、锁。
- 把一个已有的文件夹当成会话打开：就地补上缺的子文件夹和库，加锁；**不挪动里面任何已有的文件**。这是 Capture One 的做法。
- 关会话：把日志合并进库文件（关了之后 `-wal` 文件是零长度或不存在），再释放锁。
- 路径的规矩：库里的照片路径，会话内的存成相对会话根的路径，引用的外部文件存成绝对路径。给一对换算函数。
- 会话的通用唯一标识：新建时生成一个，存进 `_meta`。**不许自己手写随机数。** 要么用现成的 crate（登记许可证），要么读操作系统的随机源；你选，在报告里说明理由。Linux 和 macOS 都要能用，这一波起代码要能在 `x86_64-unknown-linux-gnu` 目标上通过检查（本机装了这个目标）。

**6. 测试。** 每一条行为一个测试，名字能看出测的是什么。**所有测试都在临时的空目录里跑**，自己建、自己删；绝不写进用户真实的应用支持目录，绝不碰用户照片库 `/Volumes/UNITEK/Cloud Drive/QSync/Medias/Photos/Workspace`（不读、不列目录）。

- 新建的会话：四个子文件夹、库、锁、持有人文件都在；库的版本号是 1，`_meta` 里的镜像也是 1；日志模式是 WAL。
- 根文件夹已存在且不是空的：拒绝，什么都不动。
- 把一个只有几张图的文件夹当成会话打开：补齐了结构，那几张图一个字节没动，一个都没被挪。
- 第二个打开者被拒，错误里带着持有人的信息。关掉第一个之后能打开。
- 持有人文件缺失或内容是坏的：不影响打开，只是提示里没有。
- 强杀之后重开：在一个子进程里打开会话然后被强杀，父进程确认能重新打开。（在测试里起子进程时只许起自己的测试程序，不许碰别的进程。）
- 迁移：造一个「旧版本」的库夹具（见第 8 节），打开之后表是最新的，原来的行一行不少，`.pre-migrate.X-Y.bak` 留下了，而且那个备份本身能打开、内容是迁移前的样子。
- 版本更新的库：拒绝打开，文件的哈希打开前后相同。
- 备份接口做的一致性：一边开着连接往库里写（走日志），一边用备份接口拷一份，拷出来的库里有日志里的那些行。
- `display_aux`：写进去再读出来相同；库里是一段解析不了的文本时，读到空并且调用者被告知。
- 关会话之后 `-wal` 是零长度或不存在；再打开，之前提交过的数据都在。
- 路径换算：相对和绝对两个方向，带 `..` 和多余斜杠的输入要么规范掉、要么报错，不许悄悄算出一个会话外的路径。
- 整个 crate 在 `x86_64-unknown-linux-gnu` 目标上检查通过。

**7. 冷构建的数。** 跑一次 `Scripts/rust-budget.sh --cold`，把它打印的四个数和门写进报告。门没过就停下报告，不要想办法绕。

**8. 夹具。** `fixtures/session/` 下放测试和验收用的库文件：一个旧版本的库、一个版本比任何现有构建都新的库、一个故意弄坏的库。都很小，可以直接进 git。旁边一个说明文件：每一个是怎样造出来的（给出命令，能照着重造）、里面有什么、sha256 是多少。

**9. 文档。** `docs/SESSION.md`（中文正文，英文标题）里你负责的一半：会话包在磁盘上长什么样、每一张表是干什么的、库的版本怎样升级、锁的语义、路径的规矩、关会话和崩溃之后各是什么样。备份、恢复、校验那几节留给下一波，你只把「备份要用在线备份接口、不许裸拷」这一条写上。`crates/README.md` 里这个 crate 的那一行改成现在的内容。

## 计划规定的通用纪律（原样保留）

- 变换规则：不改任何封存面；新增依赖先过许可证的允许清单。
- 验收清单：`cargo fmt --all --check` 与 `cargo clippy --workspace --all-targets -- -D warnings` 绿；`Scripts/machine-guard.sh` 在构建之前跑一次；任务书末尾附「未做 / 未验」。
- 通用纪律：`.work/` 之外不写计划面文件；一次只跑一个重活；报告里每个数字给命令。

## 阶段 B 另加的两条（每一波都适用）

- **这一波做完要停下来给用户看。** 报告里单列一节「给用户看的汇报」，写给没看过内部的人：做成了什么，哪几条能用命令现场演示（给出命令），哪几样还没做。
- **不崩溃的 lint** 写在 crate 根部（照 `lightamer-history` 的样子）：直接下标索引、`unwrap`、`expect`、`panic!`、`todo!`、`unimplemented!` 一律拒绝，测试代码放开前三条。出错一律返回分了类型的错误，错误要能变成一句人能读的话。

## 10. 验收清单（命令和输出都写进报告）

- `cargo test -p lightamer-catalog --locked` 绿，第 6 节每一条都有对应的测试。
- `cargo test --workspace --locked` 绿，测试总数等于之前的数加上这一波新增的（之前的数你自己先记）。
- `cargo check --workspace --all-targets --target x86_64-unknown-linux-gnu --locked` 通过，零警告。
- 六条「不崩溃」的 lint 用命令行开关跑，整体绿：`cargo clippy --workspace --all-targets --locked -- -D clippy::indexing_slicing -D clippy::unwrap_used -D clippy::expect_used -D clippy::panic -D clippy::todo -D clippy::unimplemented`。
- `cargo xtask layers` 通过：这个 crate 直接依赖的只有第 0 到第 2 层里该依赖的，外加 `rusqlite`。其余三个 xtask 检查也通过。
- `Scripts/check-licenses.sh` 不带参数，退出 0；`Scripts/licenses-allow.txt` 没有被改。
- `Scripts/rust-budget.sh --cold` 的四个数都在报告里。
- `Scripts/rust-ci-lite.sh` 从头到尾退出 0。
- `rg -n 'std::fs|File::|create_dir|read_dir' crates/lightamer-engine/src crates/lightamer-history/src` 没有输出（文件操作只在你这个 crate 里）。
- `rg -n 'refcount|reference_count' crates/lightamer-catalog` 没有输出。
- 引擎、历史、注册表、模块桩、顺序夹具都没变：`git diff --stat <起始 HEAD> HEAD -- crates/lightamer-engine crates/lightamer-history crates/lightamer-registry 'crates/lightamer-iop-*/src/modules'` 没有输出。
- 取自 LightCraft 的文件有署名头，`NOTICE` 里有条目。
- 测试跑完之后 `git status --porcelain` 里没有测试留下的临时文件。
- `git show --name-only HEAD` 里只有下面「纪律」一节允许的路径。

## omp 域内自审（项目只信重跑过的数字）

产物落盘并提交后，另起一个独立的 `omp -p --auto-approve --thinking max "<复审任务书>"` 实例复审。复审实例只读，但可以运行构建和测试：重跑第 10 节的全部验收；对着 T-B1 逐表核建出来的库（用 `sqlite3` 命令行打开一个测试建出来的库，`.schema` 和 T-B1 对比）；核迁移之前真的先留了备份、备份是在线拷的；核版本更新的库被拒且文件没被写；核 T1、T2 在表结构上落实了；核测试没有一处写进真实的应用支持目录；核 `git show --stat` 只含允许的路径。结论头 `PASS / N error + N minor`。发现的问题回注修订，修订记录附在报告末尾。复审输出落 `.work/gsd/phases/rust-core/waves/B12p-a-review.log`。

**你的主进程必须在复审实例写完结论头之后才退出。** 你的最后一条消息里要报告复审的结论头；做不到就如实写「自审未完成」。

## 纪律

- **只允许新增或修改这些路径**：`crates/lightamer-catalog/` 整个目录；根目录的 `Cargo.lock`（只有需要时才动 `Cargo.toml`）；`docs/SESSION.md`；`docs/LICENSE-AUDIT.md`（只追加行）；`NOTICE`；`crates/README.md`（只改这个 crate 的那一行）；`fixtures/session/`；`.work/gsd/phases/rust-core/waves/B12p-a-REPORT.md` 和 `B12p-a-review.log`。其它一律不动。
- 一个 commit，Conventional Commits 格式，message 带 `refs #32`，逐路径 `git add`，禁 `git add -A`。**零 push。**
- 构建之前跑一次 `Scripts/machine-guard.sh` 并记录输出。并行度 6 以内。不用 `caffeinate`；一定要用就带秒数上限，不留孤儿进程。
- 不跑 Swift 的构建和测试，不打开任何图形程序，不运行 `darktable`，不下载安装任何软件，不安装任何编译目标。不在 LightCraft 的目录里运行任何东西。
- 网络：取 crate 先直连，失败再单独给那一条命令加代理（`http://127.0.0.1:10809`）。
- 不读、不打印任何凭据文件，报告里不出现密钥。
- 不碰用户照片库：不读、不列目录。不读、不写用户真实的应用支持目录（`~/Library/Application Support/Lightamer`）。
- 机器上可能有别人同时在跑的 omp 会话，不是你的，不碰。守卫不过就等它过了再构建。
- 每个源文件带 SPDX 头 `GPL-3.0-or-later`。
- 数字不编。哪一项没做成，写没做成和卡在哪一步。到时间上限就交已有结果。
- 总墙钟不超过 240 分钟，含自审。

## 交付

1. 代码、测试、夹具、文档和一个 commit。
2. `.work/gsd/phases/rust-core/waves/B12p-a-REPORT.md`（中文正文，英文标题）：结论头，三行以内；交出去的接口一览（函数签名各一行）；建表和迁移的做法；锁的语义；选了什么来生成唯一标识及理由；新增了哪些依赖、各自是否在允许清单里；冷构建的四个数；第 10 节每条验收的命令与输出；**给用户看的汇报**（一节）；commit 的最终哈希与 `git show --stat`；复审的结论头；「未做 / 未验」两段。

stdout 最后一条消息一次性完整输出同样内容。
