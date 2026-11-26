# 执行 lane A5（omp）：验收对照工具，一条命令对着 darktable 官方版渲染和比对

## 背景

阶段 A 在连跑。A1、A2、A3、A3R、A4b 已完成。工作区按层摆好，共 28 个包；`apps/dt-cli` 是不参与分层检查的命令行工具，现在只会打印自己的名字。

用户的裁决（已定，不要重开）：

- **验收对照是 darktable 官方版。** 旧 Swift 版冻结，它的输出不用匹配。以后每移植一个模块，都要拿官方工具渲染出来的图比。你这一波就是把这条对照路做成一条命令。
- **基线钉在上游 `master` 的提交 `679d594f5d`。** 但官方发布的安装包只有 5.6.2：GitHub 上最新的发布是 `release-5.6.2`，`release-5.7.0` 只有一个源码标签，没有发布包（塔台已查）。所以对照用 5.6.2 的包，同时要有一份差异报告。
- **darktable 的历史兼容不是需求。** 但给官方工具的 XMP 夹具要我们自己写，是单向的：只写给它读，我们不读任何人的历史。
- 只运行 `darktable-cli`，不开图形界面，不合成任何输入事件。

先读：

- `.work/gsd/phases/rust-core/PLAN.md` 里 A5 那张波次卡。
- `.work/gsd/phases/rust-core/CORE-DESIGN.md` 的 §4：上一条 spike 配出来的命令，和踩过的坑。
- `.work/gsd/phases/rust-core/decode-oracle-evidence/`：那次 spike 留下的全部东西。`SOURCES.md` 有官方包的地址、大小、sha256；`CMDS.md` 有渲染命令和曝光、翻转两个夹具的参数；`RESULTS.md` 有噪声底线；`g1m-exposure.xmp` 和 `g2m-exposure-flip.xmp` 是两个能用的夹具，可以直接当模板；`cmp16.py` 是比对脚本，逻辑照它，但这次用 Rust 写。
- `.work/gsd/phases/rust-core/HISTORY-COMPAT.md` 的 §2、§3、§8：darktable 的 XMP 长什么样，参数怎样整块写进去，有一条曝光历史的逐字节解释。
- `.work/gsd/phases/rust-core/PLAN-AMENDMENTS.md`，全部十五条。

工作目录 `/Volumes/UNITEK/Documents/Development/Lightamer`。HEAD 先亲核并记录。全程中文，代码注释和标识符英文，commit message 英文。

## 要做的

逻辑写进 `apps/dt-cli`（Rust），`Scripts/oracle.sh` 只是一层薄入口。

**1. 取官方包并校验。**

- 一个锁文件记下官方包的地址、版本、文件大小、sha256。用 5.6.2 的 Apple Silicon 安装包，数值在 `SOURCES.md` 里，你要再核一遍。
- 缓存目录默认放在 `~/Library/Caches/lightamer-oracle/`，可以用环境变量改。**缓存里只留一个安装包**：用户的硬盘有限。版本变了就换掉旧的。
- 下载用系统自带的 `curl`，算 sha256 用系统自带的 `shasum`，不为这两件事引入依赖。先下到临时文件，大小和 sha256 都对了才改名放进缓存。
- 大小或 sha256 对不上：删掉坏文件，拒绝运行，退出码非零。

**2. 渲染。** 一条命令把一张图和它旁边的一份 XMP 交给官方的 `darktable-cli`，输出 16 位的 PNG。

- 安装包只挂载，不安装：`hdiutil attach -nobrowse -readonly`，挂在一个临时挂载点上，直接从卷里运行 `darktable-cli`。**不管成功还是失败，最后都要卸载。**
- 隔离照 spike 的做法：`HOME` 和 `CFFIXED_USER_HOME` 都指向临时目录；配置目录和缓存目录也放临时目录；OpenCL 开或关由预置的配置文件控制，不要靠命令行覆盖。
- **保护用户的 darktable 偏好**，这是硬规定：第一次启动之前 `defaults export org.darktable` 存一份；全部跑完再导出一次；两份逐字节相同才算过。不同的话，用 `defaults import org.darktable` 把之前那份导回去，并在输出里醒目地报出来。禁止 `killall cfprefsd`。
- 把 `darktable-cli` 的完整日志留下来。模块有没有生效、用的后端是哪一个，都要能从日志里指给你看。
- 跑完删掉所有临时目录。

**3. 比对。** `dt-cli cmp 甲.png 乙.png`：读两张 16 位 PNG，输出平均差、最大差（都以 16 位最低位为单位）、容差内的像素比例、各通道的均值。容差默认是 255 分之 1，也就是 257 个最低位。可以传两个门限：平均差的上限、容差内比例的下限；越门以 1 退出，这样后面的波次能直接把它当门用。解码 PNG 要引入 `png` 这个 crate，是这一波唯一预期的新依赖。

**4. 写 XMP 夹具。** `dt-cli emit-xmp`：给一张图写一份 darktable 能读的 XMP，放在图旁边。

- 照 spike 留下的两份夹具做，规则在 `CORE-DESIGN.md` §4：最小的历史，关掉自动预设，不能有 XML 注释。
- 参数是整块写的。这一波只需要两个模块：曝光（基线上是版本 7，28 个字节）和翻转（版本 2，4 个字节）。每个字段是什么、占几个字节、什么顺序，写进夹具目录的说明文件，并注明结构体出自上游的哪个提交。
- 接口要通用的：以后每移植一个模块，那一波给它加一个编码器，把自己 strongly typed 的参数写成 darktable 的字节。这一波把接口和这两个编码器做出来就行。

**5. 自检。** `Scripts/oracle.sh selftest` 跑三组：不带历史；曝光加一档；曝光加翻转。每组用 CPU 和 OpenCL 各渲染一次，其中一组再重复一次。它要断言：

- 重复渲染逐像素相同，最大差是 0。
- CPU 和 OpenCL 的平均差小于 0.05 个最低位，不同的像素不超过 100 个。上一条 spike 量到的是平均差约 0.013，只有约 10 个像素不同。
- 曝光生效了：和不带历史那张比，平均差远大于噪声。
- 翻转是逐像素的镜像：拿翻转那张和曝光那张比，左右翻过来之后最大差是 0，横向不偏移。
- 用户的偏好前后逐字节相同。

**6. 差异报告。** 写 `docs/ORACLE-BASELINE.md`：官方包是 5.6.2，我们钉的基线是 `master` 的 `679d594f5d`，第 0 期的 21 个模块（清单在 `CORE-DESIGN-TABLES.md` 的 T2）在两者之间差在哪。逐模块列表：模块版本号、参数结构体的大小、默认值有没有变。源码在 `/Volumes/UNITEK/Documents/Development/Lightamer-rust-spike/refs/dt-master`，用 `git show release-5.6.2:路径`、`git show release-5.7.0:路径` 和工作树本身对照。结论要回答一件事：给官方工具写的夹具，该按哪个版本的模块版本号和参数布局写。

**7. 夹具和说明。** 夹具放 `fixtures/oracle/`，连同说明文件。

**8. 新依赖的登记。** 每一条许可证表达式必须已经在 `Scripts/licenses-allow.txt` 里；**有哪一条不在，停下报告，不要自己改那个文件。** 在 `docs/LICENSE-AUDIT.md` 里给每个此前没有登记的 crate 各追加一行。`crates/README.md` 里 `dt-cli` 相关的位置改掉。

**9. 不进总检查。** 自检要联网取包，还要跑八次全分辨率的渲染，所以 `Scripts/rust-ci-lite.sh` 不跑它。其余的单元测试和集成测试照常进。

## 计划规定的通用纪律（原样保留）

- 变换规则：不改任何封存面；新增依赖先过 A1。
- 验收清单：`cargo fmt --all --check` 与 `cargo clippy --workspace --all-targets -- -D warnings` 绿；`Scripts/machine-guard.sh` 在构建和渲染之前各跑一次；任务书末尾附「未做 / 未验」。
- 通用纪律：`.work/` 之外不写计划面文件；一次只跑一个重活；报告里每个数字给命令。

## 10. 验收清单（命令和输出都写进报告）

- `Scripts/oracle.sh selftest` 退出 0，打印第 5 节五条的数字。
- 故意用坏的包：在一个临时缓存目录里放一个内容不对的文件，渲染命令必须拒绝运行并以非零退出，缓存目录里不留那个坏文件。
- 比对命令的单元测试，用测试里自己生成的小图：两张相同的图各项都是 0；两张已知差多少的图，平均差、最大差、容差内比例算出来和手算的一致；越门时以 1 退出。
- 写 XMP 的测试：输出和期望的文件逐字节相同；输出里没有 XML 注释。
- `cargo test -p dt-cli` 绿。
- `Scripts/oracle.sh render` 跑完之后：没有挂载着的安装包（`hdiutil info` 里没有 darktable），没有残留的 `darktable-cli` 进程，临时目录已删。
- 缓存目录里恰好一个安装包，大小和锁文件一致。
- `cargo xtask layers`、`cargo xtask check-order-sync`、`cargo xtask check-no-iop-names` 仍然通过。
- `Scripts/check-licenses.sh` 不带参数，退出 0。
- `cargo test --workspace --locked` 绿，测试数不少于之前的 91 个加上这一波新增的。
- `Scripts/rust-ci-lite.sh` 从头到尾退出 0。
- 模块桩和夹具没变：`git diff --stat <起始 HEAD> HEAD -- 'crates/dt-iop-*/src/modules' crates/dt-registry/fixtures` 没有输出。
- `docs/ORACLE-BASELINE.md` 覆盖 21 个模块，每个都有三个版本上的数字。
- `git show --name-only HEAD` 里只有下面「纪律」一节允许的路径。

## omp 域内自审（项目只信重跑过的数字）

产物落盘并提交后，另起一个独立的 `omp -p --auto-approve --thinking max "<复审任务书>"` 实例复审。复审实例只读，但可以运行 `Scripts/oracle.sh selftest`（它不写仓库）：重跑自检并核对五个数字；重跑比对的单元测试；抽查差异报告里五个模块，打开三个版本的源码核对；核 `git show --stat` 只含允许的路径；核自检之后没有挂载残留、偏好没变。结论头 `PASS / N error + N minor`。发现的问题回注修订，修订记录附在报告末尾。复审输出落 `.work/gsd/phases/rust-core/waves/A5-review.log`。

## 纪律

- **只允许新增或修改这些路径**：`apps/dt-cli/`；`Scripts/oracle.sh`、`Scripts/oracle.lock`（锁文件放这里）、`Scripts/rust-ci-lite.sh`（只有路径变了才动）；`fixtures/oracle/`；`docs/ORACLE-BASELINE.md`；`docs/LICENSE-AUDIT.md`（只追加行）；根目录的 `Cargo.toml` 和 `Cargo.lock`；`crates/README.md`；`.work/gsd/phases/rust-core/waves/A5-REPORT.md` 和 `A5-review.log`。其它一律不动。
- 一个 commit，Conventional Commits 格式，message 带 `refs #32`，逐路径 `git add`，禁 `git add -A`。**零 push。**
- 并行度 6 以内。渲染一次只跑一张。不用 `caffeinate`；一定要用就带秒数上限，不留孤儿进程。
- 不跑 Swift 的构建和测试，不打开任何图形程序，不安装任何软件到「应用程序」，不下载 darktable 之外的东西。
- 样张只用 `~/Library/Application Support/Lightamer/TestRAW/` 里的 CC0 样张，用 A7R5 那一张。**不碰用户照片库** `/Volumes/UNITEK/Cloud Drive/QSync/Medias/Photos/Workspace`：不读、不列目录。
- 不读、不打印任何凭据文件，报告里不出现密钥。
- 网络：下载和 GitHub 查询先直连，失败再单独给那一条命令加代理。不要把密钥写进任何输出。
- 每个源文件带 SPDX 头 `GPL-3.0-or-later`。
- 数字不编。哪一项没做成，写没做成和卡在哪一步。到时间上限就交已有结果。
- 总墙钟不超过 240 分钟，含自审。

## 交付

1. 上面的代码、脚本、夹具、报告和一个 commit。
2. `.work/gsd/phases/rust-core/waves/A5-REPORT.md`（中文正文，英文标题）：结论头，三行以内；怎样用（三条命令各一行）；自检的五组数字；差异报告的结论；新增了哪些依赖；第 10 节每条验收的命令与输出；commit 的最终哈希与 `git show --stat`；缓存和临时文件的清理情况与大小；「未做 / 未验」两段。

stdout 最后一条消息一次性完整输出同样内容。
