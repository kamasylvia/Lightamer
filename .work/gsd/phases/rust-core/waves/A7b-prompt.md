# 执行 lane A7b（omp）：gpui 窗口里的自有视口，实测输入归属

> **这一波是项目里唯一的例外：要开一个图形窗口，还要合成指针事件。** 塔台是在拿到用户的口令之后才派你的。机器必须空闲：用户不在操作，也没有别的重活在跑。这两条不满足就停下报告，不要等，也不要自己判断「应该没事」。

## 背景

阶段 A 在连跑。A1 到 A6、A7a 已完成。工作区按层摆好，共 28 个包，全工作区有 __TESTS__ 个测试通过。A6 定下了 Apple 模块的边界：Apple 的代码和依赖只在 `dt-apple`，别的 crate 不许碰，有检查守着。A7a 定下了命令分发口：界面只走 `execute` 和快照。

用户的裁决（已定，不要重开）：

- **界面用 gpui 族**（gpui-fast 加 gpui-kit）。视口是我们自己的 Metal 图层，放在 gpui 的原生表面里。这条缝是之前一条 spike 实测跑通的，源码和证据都在，你把它搬进工作区。
- **Apple 能力只存在于 `dt-apple`**（A6）。这一波要往 `dt-apple` 里加视口，并且要证明界面 crate 不需要碰 Apple 的任何东西。
- **原始的指针事件不是命令。** 「一切皆命令」说的是用户的意图。指针落在视口上，先由界面的视口模块收下、转成我们自己的数据类型；以后手势认出来了才发命令。这一波只做「收下、转好、数清楚」，不发任何命令。
- HDR 的验收要 EDR 屏，本机没有。这一波对 HDR 只做数值上的断言，用户可见的效果留到有屏的时候。

先读：

- `.work/gsd/phases/gpui-viewport/SPIKE-VIEWPORT.md`：视口 spike 的报告。§1.0 是 crate 和版本，§1.1 是怎样放进去的，§1.3 是和界面的叠放与更新，§1.4 是输入归属（只读了代码，没有实测——**这一波就是为了实测它**），§3 是对架构的含义，§6 是复审记录。它的源码在同目录的 `src/main.rs`（696 行）和 `src/Cargo.toml`，可以直接改造成我们的。
- `.work/gsd/phases/gpui-viewport/VERIFY.md` 和 `traces/`、`shots/`：塔台核过的数字。视口变化帧实测是 11 秒里 514 帧。
- `.work/gsd/phases/gpui-fast-scout/`：更早的侦察。`T1-BENCH.md` 是基准；`bench-src/` 里有当时写的探针工具（量帧差的、轮询窗口的、量建窗地板的）和它们的源码；`traces/` 里是原始记录。
- `.work/gsd/phases/rust-core/docs/` 下没有你要的东西；仓库里的 `docs/APPLE-BOUNDARY.md` 是 A6 写的边界说明，它留了一个没定的问题：界面框架自己会链 Apple 的东西，和我们的边界怎样相处。**这一波把它定了**，办法在下面第 2 节。
- `.work/gsd/phases/rust-core/waves/A7a-prompt.md` 和 `waves/VERIFY.md` 的 A6、A7a 两节。
- `.work/gsd/phases/rust-core/PLAN-AMENDMENTS.md`，全部。`PLAN.md` 里 A7b 那张卡是旧的，以这份任务书为准：它写的输入「到达核心」是按旧设计说的，现在意思是到达我们自己的视口模块。

工作目录 `/Volumes/UNITEK/Documents/Development/Lightamer`。HEAD 先亲核并记录（塔台派你时是 `__HEAD__`）。全程中文，代码注释和标识符英文，commit message 英文。

## 探针工具的四个坑，之前都踩过

- **合成的输入要走 HID tap**（探针的 `--global`）。别的方法能送达移动事件，但 gpui 的滚动依赖真实的悬停，会被悄悄丢掉。窗口列表里会留着已经死掉的进程的窗口项，探针要认「新出现的那个窗口」。
- **量帧差的探针要先自检。** 上一轮探针是 80×45 的网格、每格只取中心一个像素，滑杆的填充条只有 7 点宽，一滚就落进采样行之间，于是把「探针看不见」读成了「界面不刷新」，连错了五轮。这一波探针启动时先对着一个已知会变的标记自检：视口每帧在动的那个标记必须被它数到，数不到就是探针坏了，不是视口坏了。
- **归因到框架之前，先做最普通写法的最小复现。** 这一波有两条输入路径，哪条不过，先证明不是自己写错了。
- **量「启动到窗口」之前先跑建窗对照**（`bench-src/appkitfloor2.swift`，自退出）。本机每个新图形进程第一次建窗曾经要两秒，是在等系统字体服务，和我们的代码无关。有这个数，启动类的数字才读得懂。

## 要做的

**1. 建 `crates/dt-gpui`。** 第 5 层，分层检查的表里已经登记了它。它是一个可执行的 crate，名字和二进制都叫 `dt-gpui`。

- 依赖：`gpui-kit`（开 `gpui-fast` 特性），版本钉死成 spike 用的那一组（`gpui-kit 0.11.0`，解析出来是 `gpui-fast 0.1.19` 一族）；`dt-engine`；`dt-apple`。**不许声明任何 Apple 绑定的依赖**（`objc2` 一族、`metal`、`cocoa` 这些），也不许在源码里写 `cfg(target_os`。A6 的检查会查你，一条都不放宽。
- 窗口照 spike 的布局：左边一块视口区，右边固定宽度的面板，面板上放两个 gpui-kit 的滑杆和一段文字。
- 视口区用 gpui 的 `canvas` 承载，在 prepaint 里把布局给的矩形交给视口。这是 gpui-fast 自己的测试里的写法。

**2. 视口放在 `dt-apple` 里，接缝是一个整数。** gpui-fast 的原生表面在 macOS 上给出的句柄就是一个 `usize`（`NSView` 的指针），不是哪个绑定库的类型。所以：

- `dt-apple` 加一个视口模块，只在 macOS 后端里有实现。对外的接口只用我们自己的类型：给它那个 `usize` 和初始矩形，得到一个视口句柄；句柄上有改矩形、取下一帧的绘制目标、呈现、拆掉这几个操作。实现照 spike：把 `NSView` 的图层换成 `CAMetalLayer`，像素格式 16 位浮点，开 EDR 标记，色彩空间用扩展的线性 sRGB。
- 空后端上这些操作都返回「这台机器不支持」的错误，接口照样存在。非 macOS 上这个 crate 的依赖表还是空的。
- 新的 Apple 依赖只许加 `objc2-app-kit` 和 `objc2-quartz-core`，放在 macOS 目标表下，版本和 spike 一致。spike 还用了 `metal` 和 `core-graphics-types` 两个 crate：**不要带进来**，objc2 这两个框架 crate 够用；真遇到它们做不到的事，停下报告，说明是什么。
- `dt-gpui` 的做法：从 gpui-fast 拿到 `usize`，原样交给 `dt-apple`。它自己不知道 `NSView` 是什么。换不到 Metal 视口的平台上（能力表说没有），视口区画一块占位。
- `docs/APPLE-BOUNDARY.md` 补两样：这一波加的视口；那个没定的问题的答案——**规则管的是我们自己写的代码和我们直接写进清单的依赖名。界面框架内部的平台代码是它自己的事，从我们这边过去只有一个整数。** 另写明：指针事件和图层句柄只在同一个进程、同一个地址空间里有效。

**3. 呈现循环自己拿。** 16 毫秒一次，和 gpui 的重画解耦。spike 的做法是主线程上的异步循环，照它。画的是测试图：四档亮度加一条每帧移动的扫描标记，这样探针能数帧。不要每帧调 gpui 的 `notify`。

**4. 输入，两条路都做，都实测。** 定义我们自己的类型 `ViewportInput`：按下、移动、抬起、滚动，位置是视口里的逻辑坐标，带按键和修饰键、时间戳。它是纯数据，放在 `dt-gpui` 里。

- **路径甲，`on_input`**：gpui-fast 给原生表面留的回调。拿到的是 gpui 的事件类型，转成 `ViewportInput`，然后记一行日志（`INPUT` 开头，带序号和坐标），交给一个探针用的计数器。转换是纯函数，**不开窗口也能测**，测试里造 gpui 的事件值去核转换结果。
- **路径乙，`NSView` 子类**：`dt-apple` 里换上我们自己的视图子类，实现鼠标的按下、拖动、抬起、滚轮，经一个回调把同样的 `ViewportInput` 交给 `dt-gpui`。spike 的 §1.4 从代码上推导它能收到，但没有实测过。
- 用一个命令行开关选路径。探针脚本两条路各跑一遍，报告写明每条过没过。**默认走甲**；甲不过而乙过，默认改成乙，并把甲不过的证据写清楚。

**5. 探针脚本 `Scripts/rust-gui-viewport-probe.sh`。** 一条命令跑完，任何一步不过就退出非零：

- 开头：跑 `Scripts/machine-guard.sh`；**确认用户没有在操作**（系统的空闲时间够长，比如不少于 5 分钟），不满足就退出，什么都不开；确认没有别的 `dt-gpui` 在跑。
- 起动我们自己的窗口，认「新出现的那个窗口」，把它放到前面。
- 帧差探针自检（见上面的坑）。
- **① 几何**：从程序的日志里取四个数——布局给 `canvas` 的矩形、原生视图的框架、图层的边界、可绘制表面的尺寸除以缩放——必须一致，视口没有超出也没有缩进布局区。
- **② 输入**：合成 20 步指针移动加按下抬起，数 `INPUT` 行，到达的不少于 19 步。两条路径各一遍。
- **③ 面板重画时视口不卡**：让面板上的滑杆每 200 毫秒变一次，持续 11 秒；数视口变化的帧，不少于 450（spike 实测 514）。
- 跑完让程序自己退出。然后核：没有残留的 `dt-gpui` 进程，没有残留的挂载或临时文件。
- **内存熔断**：探针运行中每隔几秒看一眼空闲内存和交换区。空闲内存低于 20%，或者交换区的已用量比开始时多了 4 GB 以上，立刻退出程序并以非零退出，把当时的数字写进输出。这台机器 16 GB，今天中午交换区曾经涨到 25 GB。
- 合成的输入只对着我们自己的窗口。合成期间如果发现用户动了鼠标或键盘（空闲时间归零），立刻停手退出。

**6. 预算脚本的改法。** `Scripts/rust-budget.sh` 现在量的是整个工作区的冷构建，门是 360 秒。gpui 进来之后，光编它就要五分半，这条门会超标，而它本来是为了保核心各波的迭代速度。改成：

- 核心的冷构建：照旧量，照旧 360 秒的门，但命令排除 `dt-gpui`。
- 界面：另量「改一个 `dt-gpui` 的源文件之后重新构建」的时间，门是 180 秒（spike 实测 37 到 102 秒）；界面的冷构建单独报数，门是 900 秒。
- 界面的发行版二进制体积那条门（80 MB）现在有东西可量了，接上。
- `--cold` 的含义照旧：删掉 `target/` 之后量。

**7. 其余。**

- 不开窗口的单元测试：`ViewportInput` 的转换（四种事件、坐标、修饰键）；视口矩形的换算；`dt-apple` 的视口接口在空后端上返回不支持。这些测试不许开窗口，它们进 `cargo test --workspace`。
- `crates/README.md` 里 `dt-gpui` 和 `dt-apple` 的行改成现在的内容。`docs/LICENSE-AUDIT.md` 给每个此前没登记的 crate 各追加一行，**每一条许可证表达式必须已经在 `Scripts/licenses-allow.txt` 里；有哪一条不在，停下报告，不要自己改那个文件。** gpui 一族带进来的依赖会很多，逐条查，报告里给一个汇总：一共多少个、在清单里的多少个、不在的是哪些。
- 取自 spike 的代码不用署名（那是我们自己的）；gpui 的东西是依赖，不改它。
- `Scripts/rust-ci-lite.sh` 不跑探针脚本（它要开窗口）。其余照常。

## 计划规定的通用纪律（原样保留）

- 变换规则：不改任何封存面；新增依赖先过 A1。
- 验收清单：`cargo fmt --all --check` 与 `cargo clippy --workspace --all-targets -- -D warnings` 绿；`Scripts/machine-guard.sh` 在构建之前和开窗口之前各跑一次；任务书末尾附「未做 / 未验」。
- 通用纪律：`.work/` 之外不写计划面文件；一次只跑一个重活；报告里每个数字给命令。

## 8. 验收清单（命令和输出都写进报告）

- `cargo build -p dt-gpui --locked` 成功。首次构建的用时和构建期间的最大内存写进报告。
- `Scripts/rust-gui-viewport-probe.sh` 在路径甲上退出 0，输出里能看到第 5 节①②③三个数；再在路径乙上跑一遍，输出同样三个数和过没过。
- `cargo test -p dt-gpui --locked` 和 `cargo test -p dt-apple --locked` 绿，测试名能看出测的是什么。
- `cargo xtask check-apple-boundary` 通过，并且它的输出里能看到 `dt-gpui` 被查了；`Scripts/rust-apple-boundary.sh` 退出 0。
- `rg -n 'objc2|core_foundation|core_graphics|cfg\(target_os|NSView|CAMetalLayer' crates/dt-gpui/src` 没有输出。文档注释里提到这些词不算，但源码里一行都不许有。
- `cargo tree --locked -e normal --target x86_64-unknown-linux-gnu -p dt-apple --prefix none` 仍然只有 `dt-apple` 自己一行。
- `rg -n 'unsafe' crates/dt-apple/src` 的每一处命中都在 macOS 后端的模块里；新增的每一处都带安全说明。
- `cargo xtask layers`、`cargo xtask check-order-sync`、`cargo xtask check-no-iop-names` 仍然通过。
- `Scripts/check-licenses.sh` 不带参数，退出 0。
- `cargo test --workspace --locked` 绿，测试数不少于 __TESTS__ 个加上这一波新增的，没有一个测试开窗口。
- `Scripts/rust-budget.sh --cold` 退出 0，输出里有核心冷构建、界面重新构建、界面冷构建、界面二进制体积四行各自的数和门。
- `Scripts/rust-ci-lite.sh` 从头到尾退出 0。
- 探针跑完之后：没有 `dt-gpui` 进程，没有残留的临时文件。
- 模块桩、夹具、`dt-history`、`dt-engine`、`dt-registry` 都没变：`git diff --stat <起始 HEAD> HEAD -- 'crates/dt-iop-*/src/modules' crates/dt-registry/fixtures crates/dt-history crates/dt-engine crates/dt-registry` 没有输出。
- 对照工具和前几波的东西没被弄坏：`target/debug/dt-cli help` 里 A5、A6、A7a 的子命令都在。
- 证据：入库的截图只有裁剪过的关键区域，原始的整窗截图留在仓外；探针的原始输出（日志、逐帧记录）入库。
- `git show --name-only HEAD` 里只有下面「纪律」一节允许的路径。

## omp 域内自审（项目只信重跑过的数字）

产物落盘并提交后，另起一个独立的 `omp -p --auto-approve --thinking max "<复审任务书>"` 实例复审。**复审实例不许开窗口，不许合成任何输入**，它核的是落盘的证据：重跑第 8 节里不用开窗口的那些验收；逐条对探针的原始记录重数①②③三个数（自己数 `INPUT` 行，自己按逐帧记录数帧，不看执行 lane 的汇总）；核帧差探针的自检记录在不在；核几何那四个数是同一次运行里的；核路径甲和路径乙的结论和证据对得上；核 `dt-gpui` 里确实一行 Apple 的东西都没有；核 `git show --stat` 只含允许的路径。结论头 `PASS / N error + N minor`。发现的问题回注修订，修订记录附在报告末尾。复审输出落 `.work/gsd/phases/rust-core/waves/A7b-review.log`。

## 纪律

- **只允许新增或修改这些路径**：`crates/dt-gpui/` 整个目录；`crates/dt-apple/`（只许加视口模块和它的依赖）；根目录的 `Cargo.toml`（只许加成员）和 `Cargo.lock`；`crates/README.md`（只改 `dt-gpui` 和 `dt-apple` 的行）；`docs/APPLE-BOUNDARY.md`；`docs/LICENSE-AUDIT.md`（只追加行）；`Scripts/rust-gui-viewport-probe.sh`；`Scripts/rust-budget.sh`；探针工具如果需要小改，改后的副本放进 `crates/dt-gpui/probes/`（原始的侦察目录不动）；`.work/gsd/phases/rust-core/waves/A7b-REPORT.md`、`A7b-review.log`，以及 `.work/gsd/phases/rust-core/waves/A7b-evidence/` 下的证据文件。其它一律不动。
- 一个 commit，Conventional Commits 格式，message 带 `refs #32` 和 `refs #33`，逐路径 `git add`，禁 `git add -A`。**零 push。**
- 构建之前跑一次 `Scripts/machine-guard.sh` 并记录输出。并行度 6 以内。gpui 的首次构建是重活：跑之前确认机器上没有别的重活。
- **窗口**：只开我们自己这一个窗口，探针一跑完就让它退出。不碰别的程序的窗口，不往别的程序里发任何输入。不用 `caffeinate`；一定要用就带秒数上限，不留孤儿进程。
- 不运行 `darktable`，不跑 Swift 的构建和测试，不下载安装任何软件，不安装任何编译目标。取 crate 先直连，失败再单独给那一条命令加代理（`http://127.0.0.1:10809`）。
- 不读、不打印任何凭据文件，报告里不出现密钥。
- 不碰用户照片库 `/Volumes/UNITEK/Cloud Drive/QSync/Medias/Photos/Workspace`：不读、不列目录。视口里画的是测试图，不需要任何照片。
- 机器上可能有别人同时在跑的 omp 会话，不是你的，不碰。守卫不过就等它过了再构建；用户回来操作了，探针那一步就停，报告写明停在哪。
- 每个源文件带 SPDX 头 `GPL-3.0-or-later`。
- 数字不编。哪一项没做成，写没做成和卡在哪一步。到时间上限就交已有结果。
- 总墙钟不超过 240 分钟，含自审；其中开窗口的时间加起来不超过 15 分钟。

## 交付

1. 上面的代码、脚本、证据和一个 commit。
2. `.work/gsd/phases/rust-core/waves/A7b-REPORT.md`（中文正文，英文标题）：结论头，三行以内；接缝是什么（一个整数），界面 crate 里为什么一行 Apple 的东西都不用有；两条输入路径各自的结论和证据；①②③三个数（两条路径各一组）和 spike 的对照；帧差探针的自检记录；几何那四个数；构建用时和内存；预算四行的数；新依赖的许可证汇总；第 8 节每条验收的命令与输出；commit 的最终哈希与 `git show --stat`；「未做 / 未验」两段。

stdout 最后一条消息一次性完整输出同样内容。
