# 执行 lane A6（omp）：Apple 模块边界，Apple 能力只存在于 `dt-apple`

## 背景

阶段 A 在连跑。A1、A2、A3、A3R、A4b、A5 已完成。工作区按层摆好，共 28 个包。`crates/dt-apple` 现在是一个空壳：只有清单和一行文档注释，没有任何依赖。`apps/dt-cli` 是不参与分层检查的命令行工具，目前只有对照用的几个子命令。全工作区现在有 116 个测试通过。

用户的裁决（已定，不要重开）：

- **Apple 能力独占一个模块，只在 macOS 构建里存在。** 这个模块就是 `dt-apple`。其它 crate 不许直接碰 Apple 的框架绑定，也不许自己判断「是不是 macOS」。
- **核心和界面只读一张能力表**，不在自己的代码里写 `cfg`。表由 `dt-apple` 给。
- **框架学 LightCraft**：依赖方向由检查强制，不靠自觉。所以这一波的边界必须有机检，以后每一波都自动过。
- **解码主路径是 rawspeed**（在 `dt-decode`，不是 Apple 的东西，这一波不碰）。CIRAW 排到 C 期。
- **这一波不写任何像素处理**，不解码、不渲染、不开窗口。只做边界、能力表、机检和一份说明文档。

先读：

- `.work/gsd/phases/rust-core/PLAN.md` 的 §2.7（Apple 模块边界）和 A6 那张波次卡。注意 §2.7 里写的名字 `dt-app` 是旧的，现在是 `dt-apple`；§2.7 第二条机检的字样这一波会改，见下面第 5 节。
- `.work/gsd/phases/rust-core/SPIKE-RUST-APPLE.md` 的 §0 和 §3。它用独立的工程证明了 Rust 能调通 CIRAW、Vision、ImageIO 与 ColorSync、Metal。它的源码在 `.work/gsd/phases/rust-core/SPIKE-RUST-APPLE-src/`：`Cargo.toml` 里有用到的 crate 和版本，`src/s1` 到 `src/s4` 里是最小调用。**只读参考，不要在那里运行任何东西。**
- `.work/gsd/phases/rust-core/FRAMEWORK-TABLES.md` 的 T-F9：`dt-apple` 在第 3 层。
- `crates/xtask/src/layers.rs`：现有检查怎样读 `cargo metadata` 的输出、怎样组织单元测试。新的检查照它的样子写。
- `.work/gsd/phases/rust-core/waves/VERIFY.md` 的 A5 一节。
- `.work/gsd/phases/rust-core/PLAN-AMENDMENTS.md`，全部十六条。

工作目录 `/Volumes/UNITEK/Documents/Development/Lightamer`。HEAD 先亲核并记录（塔台派你时是 `04c84b8d`）。全程中文，代码注释和标识符英文，commit message 英文。

## 要做的

**1. `dt-apple` 的结构。** 要同时满足下面六条：

- 在每个平台上这个 crate 都能编译，对外的接口在每个平台上都一样。用它的 crate 不需要写任何 `cfg`。
- 对外的接口里不出现任何框架的类型（`CIImage`、`MTLDevice`、`CGColorSpace` 这一类都不行），只出现标准库的类型和我们自己的类型。
- 空的后端（什么都不提供的那一个）**在每个平台上都参与编译，macOS 上也是**。这样它的编译正确性和行为在本机就能查。
- 全 crate 只有一处选择用哪个后端，写成两个各自完整的 `cfg` 块，不要写成一串零散的 `cfg` 语句或只有一个分支留着的 `match`。
- Apple 绑定的依赖只放在 `[target.'cfg(target_os = "macos")'.dependencies]` 里，普通的 `[dependencies]` 里一条都不许有。
- `unsafe` 只出现在 macOS 后端那个模块的内部，每一处都带一句安全说明。模块外保持工作区的 `unsafe_code = "deny"`。在 macOS 后端的模块内部再拒绝 `unsafe_op_in_unsafe_fn` 和 `clippy::undocumented_unsafe_blocks`。

建议的形状（可以调整，六条满足就行）：crate 内部一个私有的特征，两个实现——空的实现在一个始终编译的文件里，macOS 的实现在带 `#[cfg(target_os = "macos")]` 的模块里，`allow(unsafe_code)` 只写在这个模块的文件开头；选择函数返回特征的引用。

不崩溃的 lint 照 A4b 在 `dt-history` 立的规矩，写在这个 crate 的根部：直接下标索引、`unwrap`、`expect`、`panic!`、`todo!`、`unimplemented!` 一律拒绝，测试代码放开前三条。

**2. 能力表。** `dt_apple::capabilities()` 返回一张表。表里**只放平台事实**，就是「这台机器、这个系统提供什么」，不放「我们已经实现了什么功能」——这一波没有实现任何功能，写上去就是假的。每一项都要真的去探，探不到就如实报没有。至少这五项，字段名你可以定得更好：

- 默认的 Metal 设备在不在，在的话叫什么名字。
- ImageIO 在这个系统上能写哪些格式。只认我们关心的那几种（JPEG、PNG、TIFF、HEIC、AVIF、WebP），一个都不预设。
- `CIRAWFilter` 这个类在不在。
- Vision 用的那几个请求类在不在。
- ColorSync 能不能建出标准的色彩空间。

另外带一个字段说明后端是哪一个（macOS 还是空）。

探针必须是轻量的：查类、建一个设备对象、问格式列表、建一个色彩空间。**不解码任何图像，不读任何样张，不开窗口。** 最小调用照 spike 的 `src/s1` 到 `src/s4` 里相应的几行抄，只抄探针需要的。第一次调用时探一次，之后返回同一份（标准库的 `OnceLock` 就行）。

依赖的版本：和 spike 工程的 `Cargo.lock` 解析出来的一致。用到的 objc2 各 crate 要开哪些 feature，照 spike 的写法。空后端和对外接口只用标准库，所以非 macOS 上这个 crate 一个第三方依赖都没有。新依赖写进根目录的 `Cargo.lock` 是允许的：第一次解析时去掉 `--locked` 让 cargo 更新锁文件；锁文件更新之后，下面所有带 `--locked` 的命令都必须原样通过。

**3. `dt-cli capabilities`。** 打印这张表。`dt-cli` 通过一个默认打开的 feature（名字用 `apple`）依赖 `dt-apple`，关掉它就不依赖。输出的格式照 `dt-cli` 现有的样子，一行一个 `key=value`，键名要稳定（以后的脚本会来查），空后端打印同样的键。

**4. 说明文档。** 写 `docs/APPLE-BOUNDARY.md`（中文正文，标识符英文）：边界的规则是什么、为什么这样定；要新增一项 Apple 能力时的步骤（依赖加在哪、代码放哪、测试怎么写）；能力表每个字段探的是什么；机检有几条、各查什么；lint 在这个 crate 里怎样放行；本机验证到了什么、没验证什么；各项能力的最小调用在 spike 的哪个文件。还要写明一条边界：这个规则管的是我们自己写的代码和我们直接写进清单的依赖名；界面框架自带的平台代码不归它管，那件事到 A7b 再定。

**5. 机检，做成 `cargo xtask check-apple-boundary`。** 照 `layers.rs` 的写法，读 `cargo metadata` 的输出。规则四条：

- 除 `dt-apple` 外，任何工作区的 crate 直接依赖的清单里，不许有 Apple 绑定的 crate。名单放在检查里的一个常量数组里，前缀匹配的要写明白：`objc2` 开头的全部、`objc`、`block2`、`dispatch2`、`core-foundation`、`core-graphics`、`core-graphics-types`、`metal`、`cocoa`、`cocoa-foundation`、`io-surface`、`foreign-types`、`core-text`、`core-video`、`core-image`。以后要增删，改这一处。
- `dt-apple` 自己：上面名单里的依赖必须都挂在 macOS 的目标表下。
- 源码扫描：`crates/` 和 `apps/` 下的源码、构建脚本、测试，除 `crates/dt-apple/` 之外，不许出现 `objc2`、`core_foundation`、`core_graphics`、`cfg(target_os`、`cfg!(target_os`。说明文档不算。
- `cargo metadata` 读不出来时，检查必须以非零退出并说明原因，不许当作通过。

每一条规则都要有单元测试：喂一份带违规的数据，检查必须报出来，报错里要带上是哪一个 crate、哪一条依赖或哪一行。

**6. 链接层面的门，做成 `Scripts/rust-apple-boundary.sh`。** 一条命令跑完下面几步，任何一步不过就退出非零：

- `cargo xtask check-apple-boundary`。
- `cargo tree --locked -e normal --target x86_64-unknown-linux-gnu -p dt-apple --prefix none`：输出里只有 `dt-apple` 自己一行。这个目标本机没有装，但这条命令不需要装就能跑，塔台试过。
- 同一条命令换成 `--target aarch64-apple-darwin`：输出里要有 objc2 的 crate。
- `cargo build -p dt-cli --no-default-features --locked`，然后对这个二进制：`otool -L` 里没有一行 `/System/Library/Frameworks/`；`nm -u` 里匹配 `OBJC\$|_objc_|CIRAW|CGColor|_VN[A-Z]` 的行数是 0。塔台量过现在的基线：只链 `libSystem.B.dylib`，两个数都是 0。
- 关掉 feature 的那个二进制跑 `capabilities`，打印的是空后端。
- 最后用默认 feature 把 `dt-cli` 重新构建一次，让 `target/debug/dt-cli` 回到默认的那一个；再跑一次 `capabilities`，这次是 macOS 的真值。

计划 §2.7 原来的第二条写的是 `nm -u | grep -iE 'objc|CoreImage|ColorSync|Vision'`。改成上面那样有两个原因：`-i` 加 `vision` 会被 `Revision` 一类的符号名误伤；框架在链接信息里是一眼能看到的，比猜符号名可靠。原来的写法这一波也量一下、记进报告，作为对照。

脚本开头跑一次 `Scripts/machine-guard.sh`。**不装任何编译目标。** 非 macOS 上真的能不能编译，这一波在本机验证不了，报告里如实写没验证，以及验证它需要哪一条命令。

**7. 接进总检查。** `Scripts/rust-ci-lite.sh` 在分层检查之后加一步 `cargo xtask check-apple-boundary`。第 6 节那个脚本不进总检查（它要换一组 feature 重新构建）。其它脚本不动。

**8. 活体负测两次。** 临时制造违规，检查必须以非零退出并点出违规的地方；然后撤掉，`git status --porcelain` 里不留痕。

- 源码：在 `dt-history` 里临时加一行带 `#[cfg(target_os = "macos")]` 的代码。
- 依赖表：把 `dt-apple` 清单里的一条 objc2 依赖从目标表临时挪到普通的 `[dependencies]`。这样挪不会改动 `Cargo.lock`。

**9. 冷构建时间。** objc2 的 crate 会拖慢冷构建。跑一次 `Scripts/rust-budget.sh --cold`，把四项的数字和门写进报告。冷构建超过 360 秒的话，停下报告，不要想办法绕。

**10. 新依赖的登记。** 每一条许可证表达式必须已经在 `Scripts/licenses-allow.txt` 里；**有哪一条不在，停下报告，不要自己改那个文件。** 在 `docs/LICENSE-AUDIT.md` 里给每个此前没有登记的 crate 各追加一行：名称、版本、许可证、证据。`crates/README.md` 里 `dt-apple` 和 `dt-cli` 的行改成现在的内容。

## 计划规定的通用纪律（原样保留）

- 变换规则：不改任何封存面；新增依赖先过 A1。
- 验收清单：`cargo fmt --all --check` 与 `cargo clippy --workspace --all-targets -- -D warnings` 绿；`Scripts/machine-guard.sh` 在构建之前跑一次；任务书末尾附「未做 / 未验」。
- 通用纪律：`.work/` 之外不写计划面文件；一次只跑一个重活；报告里每个数字给命令。

## 11. 验收清单（命令和输出都写进报告）

- `cargo build -p dt-apple --locked` 和 `cargo test -p dt-apple --locked` 绿。至少有这些测试，名字能看出测的是什么：空后端报的是「什么都没有」；能力表的每个字段都有；空后端被真的选中过一次（不是只编译）。
- `target/debug/dt-cli capabilities`（默认 feature）在 macOS 上打印真值；`--no-default-features` 构建出来的那一个打印空后端，键相同。
- `Scripts/rust-apple-boundary.sh` 从头到尾退出 0，输出里能看到第 6 节每一步的结果。
- 第 8 节两次活体负测：检查以非零退出并点出违规；撤掉之后工作区干净。
- `cargo test -p xtask` 绿，四条规则各至少有一个单元测试。
- `rg -n 'objc2|core_foundation|core_graphics|cfg\(target_os|cfg!\(target_os' crates apps --glob '!crates/dt-apple/**' --glob '*.rs'` 没有输出。
- `rg -n 'unsafe' crates/dt-apple/src` 的每一处命中都在 macOS 后端的模块里。
- `cargo xtask layers`、`cargo xtask check-order-sync`、`cargo xtask check-no-iop-names` 仍然通过。
- `Scripts/check-licenses.sh` 不带参数，退出 0。
- `cargo test --workspace --locked` 绿，测试数不少于 116 个加上这一波新增的。
- `Scripts/rust-ci-lite.sh` 从头到尾退出 0，日志里能看到新的检查跑过。
- 模块桩和夹具没变：`git diff --stat <起始 HEAD> HEAD -- 'crates/dt-iop-*/src/modules' crates/dt-registry/fixtures` 没有输出。
- 对照工具没被弄坏：`cargo build -p dt-cli --locked` 之后 `target/debug/dt-cli help` 里，A5 的子命令都还在。
- `git show --name-only HEAD` 里只有下面「纪律」一节允许的路径。

## omp 域内自审（项目只信重跑过的数字）

产物落盘并提交后，另起一个独立的 `omp -p --auto-approve --thinking max "<复审任务书>"` 实例复审。复审实例只读，但可以运行构建、测试和 `Scripts/rust-apple-boundary.sh`：重跑第 11 节的全部验收；对着 PLAN §2.7 逐条核三条机检是不是都落地了，改掉的那一条理由成不成立；核 `unsafe` 是不是只在一个模块里；核空后端是不是在每个平台都编译、接口里是不是真的没有框架类型；核 spike 的依赖版本有没有抄对；核 `git show --stat` 只含允许的路径。结论头 `PASS / N error + N minor`。发现的问题回注修订，修订记录附在报告末尾。复审输出落 `.work/gsd/phases/rust-core/waves/A6-review.log`。

## 纪律

- **只允许新增或修改这些路径**：`crates/dt-apple/` 整个目录；`crates/xtask/`（只许加这个新的子命令、它的登记、它的测试和帮助文字）；`apps/dt-cli/`（只许加 `capabilities` 子命令和清单里的 feature）；根目录的 `Cargo.toml` 和 `Cargo.lock`；`crates/README.md`（只改 `dt-apple` 和 `dt-cli` 的行）；`docs/APPLE-BOUNDARY.md`；`docs/LICENSE-AUDIT.md`（只追加行）；`Scripts/rust-apple-boundary.sh`；`Scripts/rust-ci-lite.sh`（只加那一步）；`.work/gsd/phases/rust-core/waves/A6-REPORT.md` 和 `A6-review.log`。其它一律不动。
- 一个 commit，Conventional Commits 格式，message 带 `refs #32`，逐路径 `git add`，禁 `git add -A`。**零 push。**
- 构建之前跑一次 `Scripts/machine-guard.sh` 并记录输出。并行度 6 以内。不用 `caffeinate`；一定要用就带秒数上限，不留孤儿进程。
- 不跑 Swift 的构建和测试，不打开任何图形程序，不运行 `darktable`，不下载安装任何软件，不安装任何编译目标。
- 不读、不打印任何凭据文件，报告里不出现密钥。
- 不碰用户照片库 `/Volumes/UNITEK/Cloud Drive/QSync/Medias/Photos/Workspace`：不读、不列目录。这一波的探针不需要任何样张。
- 机器上可能有别人同时在跑的 `darktable-cli` 或别的 omp 会话，不是你的，不碰，也不要因为它们在做重活就停下手里的轻活；守卫不过就等它过了再构建。
- 网络：取 crate 先直连，失败再单独给那一条命令加代理（`http://127.0.0.1:10809`）。不要把密钥写进任何输出。
- 每个源文件带 SPDX 头 `GPL-3.0-or-later`。
- 数字不编。哪一项没做成，写没做成和卡在哪一步。到时间上限就交已有结果。
- 总墙钟不超过 240 分钟，含自审。

## 交付

1. 上面的代码、检查、脚本、文档和一个 commit。
2. `.work/gsd/phases/rust-core/waves/A6-REPORT.md`（中文正文，英文标题）：结论头，三行以内；`dt-apple` 的结构和选择后端的那一处；能力表的字段和本机探到的值；四条机检和链接门各自查什么；冷构建四项的数字；新增了哪些依赖、各自是否在允许清单里；第 11 节每条验收的命令与输出；两次活体负测的输出；commit 的最终哈希与 `git show --stat`；「未做 / 未验」两段。

stdout 最后一条消息一次性完整输出同样内容。
