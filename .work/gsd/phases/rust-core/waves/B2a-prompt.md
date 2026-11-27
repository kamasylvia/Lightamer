# 执行 lane B2-a（omp）：rawspeed 解码——构建、薄 C ABI、相机库单例、RAW 解码与元数据

## 背景

阶段 B 是第 0 期，**每一波做完都要停下来给用户看**。B1（管线内核）已经闭环，四段的提交到 `98116e95`。**B2 是第四波：解码**——把 ARW、RAF、NEF 这些文件解成马赛克和元数据；后面所有的像素模块都建在它上面。分两段串行：

- **B2-a（就是你）**：把 rawspeed 编出来、薄的一层 C 接口、相机库只加载一次、RAW 解码与元数据、错误码、最小的打印命令。
- **B2-b（你之后）**：栅格解码（JPEG/TIFF/PNG）、内嵌缩略图、命令行完善、验收测试补齐、演示脚本、文档。

用户的裁决（已定，不要重开）：

- **解码的主路径是 rawspeed**；CIRAW 推迟；用 darktable 自带的那一份，钉在提交 `0c16fee77…`。
- **许可**：rawspeed 是 `LGPL-2.1-or-later`，我们静态链接，整体按 `GPL-3.0-or-later` 分发——第一波的许可证审计（`docs/LICENSE-AUDIT.md` §3）已经论证过，和 darktable 同构。
- **`unsafe` 只许在薄薄的一层接口里，逐处写安全说明；坏文件不中止进程。**
- **非 macOS 不是目标。** 命令只做有界的活——这一波只做库和命令行工具，接进引擎是以后的事。

先读（都在 `.work/gsd/phases/rust-core/` 下，除非写了别的路径）：

- `PLAN-B.md` 里 B2 那张卡。`docs/LICENSE-AUDIT.md`（仓库根下）§3。`waves/VERIFY.md` 的最后一节。
- `waves/SPIKE-RUST-APPLE.md`（§1 的 S1r、§2、§4）和 `waves/SPIKE-RUST-APPLE-src/`。
- 上一轮验证留下的接口源码：`/Volumes/UNITEK/Documents/Development/Lightamer-rust-spike/csrc/`（`rawspeed_shim.h`、`rawspeed_shim.cpp`、`dngwriter.h`）。同目录的 `omp-spike-summary.md`。
- `.work/gsd/phases/rawspeed-backend/SPIKE.md`：rawspeed 的构建配方、「解码段 34 到 57 毫秒」的口径。
- `crates/lightamer-decode/`（空壳）；`apps/lightamer-cli/`；`Scripts/licenses-allow.txt`（只读）。

工作目录 `/Volumes/UNITEK/Documents/Development/Lightamer`。HEAD 先亲核并记录。全程中文，代码注释和标识符英文，commit message 英文。

## 现在的起点（塔台看的，每一条你自己核）

- `lightamer-decode` 是空壳。仓库里没有 rawspeed（没有子模块）。
- darktable 的只读工作区 `/Volumes/UNITEK/Documents/Development/Lightamer-rust-spike/refs/dt-master` 里，`src/external/rawspeed` 是一个钉在 `0c16fee7772594e98897bded01fc31bc3409b4cb` 的引用，**没有检出**。
- 上一轮验证用的是别处编好的 `librawspeed.a`，没有留下能照着重做的构建配方；那一层接口每打开一次都重新解析相机库，所以慢。
- 仓库在一块外置的机械硬盘上，写盘慢。本机有 `cmake` 和 `ninja`。
- 样张只用 CC0 的那九个（在 `~/Library/Application Support/Lightamer/TestRAW/`），其中 `7RM5-LosslessCompressedLarge.ARW` 是用户机型的 6100 万像素。**不碰用户的照片库**（位置见仓库的 `AGENTS.md`：不读、不列目录）。

## 要做的

**1. rawspeed 的来源和构建。** 以 git 子模块的形式钉在 `external/rawspeed`，提交就是上面那一个；子模块的地址用 SSH 的形式。构建走 `build.rs` 配 cmake。新依赖的许可证表达式必须先在 `Scripts/licenses-allow.txt` 里，不在就停下报告（那个文件不许改）。相机库 `cameras.xml` 随包（从子模块里取，编进或者拷进产物，写明是哪一种）。子模块或构建在本机走不通，就如实报告卡在哪一步、试过哪些办法。

**2. 薄薄的一层 C 接口。** 照上一轮验证的接口改进入库：打开、解 RAW、取出内嵌缩略图的字节（B2-b 要用）、释放。C++ 的异常不许穿过 C 的边界——一切异常在接口里接住，变成错误码；坏文件不中止、不崩。Rust 这一侧的 `unsafe` 只许在薄薄的一层里，逐处写安全说明。不许 panic，不许 unwrap。

**3. Rust 的安全包装**（`lightamer-decode`）：

- 分了类型的错误。
- 相机库是进程里的单例，只解析一次。
- 解出来的东西：马赛克缓冲（类型照 rawspeed 给的：16 位整数或浮点，裁剪后的可见区）、黑电平（每个通道，或每一行）、白点、白平衡（乘数；机内色温和色调如果有）、相机到 XYZ 的矩阵（各个色彩的）、裁剪框、图像尺寸、颜色滤镜的排布、ISO、曝光时间、光圈、焦距、机身和镜头的型号、解码器的名字。

**4. 错误码表。** 每一种一个码、一句人能读的话。至少要有：文件不存在、不是 RAW、不认识的相机、被截断的文件、解压失败、内存不够、不支持的压缩。

**5. 最小的打印命令。** `lightamer-cli decode --dump <文件>`：把上面那些字段逐个打印出来，加上耗时。缩略图留一个开关占位（B2-b 填）。它只是开发工具，不是命令，不进引擎。

## 测试

每一条行为一个测试，名字能看出测的是什么。样张只读。

- **三张样张**（ARW、RAF、NEF 各一张，从九个里挑）解出来的宽、高、黑电平、白点、白平衡，**与 rawspeed 自己的结果逐值相等**。对照程序你写：一个直接调 rawspeed 的 C++ 接口的小程序，用同一份库；命令和输出进报告。
- **坏文件五种**（空文件、随机字节、截断一半、只有文件头、改了扩展名）各返回对应的错误码，进程活着；五种在同一个进程里连着跑完。
- **双跑逐位**：同一个文件解两次，马赛克缓冲逐字节相同。
- 相机库只解析了一次（计数或探针）。
- 释放之后没有泄漏（选一个本机可行的检查办法）。
- **计时**：发行版，机器安静（照 `Scripts/rust-budget.sh` 里判断负载的办法）。`7RM5-LosslessCompressedLarge.ARW` 冷的那一次（相机库已经加载之后的第一张）单文件解码不超过 80 毫秒；热的（同一文件第二次）另报。九个样张各自的耗时列一张表。

## 计划规定的通用纪律（原样保留）

- 变换规则：不改任何封存面；新增依赖先过许可证的允许清单。
- 验收清单：`cargo fmt --all --check` 与 `cargo clippy --workspace --all-targets -- -D warnings` 绿；`Scripts/machine-guard.sh` 在构建之前跑一次；任务书末尾附「未做 / 未验」。
- 通用纪律：`.work/` 之外不写计划面文件；一次只跑一个重活；报告里每个数字给命令。

## 阶段 B 每一波都适用的两条

- **这一波做完要停下来给用户看**（B2-b 做完才停，但你报告里的「给用户看的汇报」一节照写）。
- **不崩溃的 lint**：出错一律返回分了类型的错误，错误要能变成一句人能读的话。

## 验收清单（命令和输出都写进报告）

- `cargo test -p lightamer-decode --locked`、`cargo test -p lightamer-cli --locked` 绿，「测试」一节每一条都有对应的测试。
- `cargo test --workspace --locked` 绿，测试数不少于起点加上这一段新增的（起点是 550 个通过，另三个默认不跑的计时测试；你自己先跑一遍记下来）。
- 子模块钉在那个提交：`git ls-tree HEAD external/rawspeed` 的哈希是 `0c16fee7…`。
- `cargo xtask layers` 等检查通过（解码在 L1）；`Scripts/rust-apple-boundary.sh` 退出 0；`Scripts/check-licenses.sh` 退出 0；`docs/LICENSE-AUDIT.md` 追加了新进的 crate 和 rawspeed 的条目；仓库里如果有 `NOTICE` 文件，登记 rawspeed。
- 六条不崩溃 lint 的命令行口径对整个工作区退出 0；`unsafe` 块逐处有安全说明；文档零警告（都在总检查里）。
- 计划卡片上 B2 的验收①②③④在这一段的范围内成立（⑤和栅格解码归 B2-b）。
- `Scripts/rust-ci-lite.sh` 退出 0；三个演示脚本仍然退出 0。
- 构建产物都在 `target/`（或你写明的位置），不进 git；没有往仓库以外的位置写东西（子模块检出在仓库内）。
- 跑完之后 `git status --porcelain` 里没有临时文件；没有残留的进程。
- `git show --name-only HEAD` 里只有下面「纪律」一节允许的路径；其中有 `B2a-REPORT.md` 和 `B2a-review.log`。

## 产物先落盘，再收尾

- **代码和测试一绿就先提交一次**。之后可以继续提交，最后用 `git commit --amend` 或 squash 收成**一个**提交。
- **自审**：产物落盘并提交后，另起一个独立的 `omp -p --auto-approve --thinking max "<复审任务书>"` 实例复审。复审实例只读，但可以运行构建和测试：重跑验收清单的全部；自己重做一次干净构建（照报告里的配方）；核 C++ 异常确实出不了 C 的边界；核每一个 `unsafe` 块都有安全说明；核三张样张的对照是真的在和 rawspeed 自己的结果比；核坏文件测试之后进程活着；核 `git show --stat` 只含允许的路径。结论头 `PASS / N error + N minor`。发现的问题回注修订，修订记录附在报告末尾。复审输出落 `.work/gsd/phases/rust-core/waves/B2a-review.log`。
- **退出的次序**：复审实例写完结论头之后，你才依次做四件事——把复审的结论头和修订记录写进报告；`git commit --amend` 把最终的报告和 `B2a-review.log` 并进那一个提交（不 push，所以 amend 是安全的）；删掉你建的临时文件和目录；最后主进程才退出。报告里不许留「待填」。

## 纪律

- **只允许新增或修改这些路径**：`crates/lightamer-decode/` 整个目录；`external/rawspeed`（子模块）和 `.gitmodules`；根目录的 `Cargo.toml`、`Cargo.lock`；`apps/lightamer-cli/`（只加 `decode --dump` 需要的）；`docs/LICENSE-AUDIT.md`；`NOTICE`（如果有这个文件）；`docs/DECODE.md`（新建）；`crates/README.md`（只改动了的那几行）；`.work/gsd/phases/rust-core/waves/B2a-REPORT.md` 和 `B2a-review.log`。其它一律不动。`Scripts/licenses-allow.txt` 不许改。
- **不改动 darktable 的只读工作区**：不在那里检出子模块，不往那里写东西。要源码就从 GitHub 按那个提交取。
- 一个 commit（见上），Conventional Commits 格式，message 带 `refs #32`，逐路径 `git add`，禁 `git add -A`。**零 push。**
- 构建之前跑一次 `Scripts/machine-guard.sh` 并记录输出。并行度 6 以内。不用 `caffeinate`。一次只跑一个重活。机器上同时有一条只读的调研 lane 在跑，不是你的，不碰；守卫不过就等它过了再构建。
- 不跑 Swift 的构建和测试，不打开任何图形程序，不运行 `darktable`，不往「应用程序」里下载安装任何软件（取源码、用本机已有的 cmake 和 ninja 不算），不安装任何编译目标，不跑任何非 macOS 目标的检查。
- 不读、不打印任何凭据文件，报告里不出现密钥。不碰用户照片库。
- `.work/` 下有很多以前各波留下的未跟踪文件（`*.pid`、旧日志），不是你的，不碰也不提交。
- 每个源文件带 SPDX 头 `GPL-3.0-or-later`（子模块里的 rawspeed 除外，它自己的许可声明原样保留）。
- 数字不编。哪一项没做成，写没做成和卡在哪一步。到时间上限就交已有结果。
- 总墙钟不超过 240 分钟，含自审。

## 交付

1. 代码、测试、文档和一个 commit。
2. `.work/gsd/phases/rust-core/waves/B2a-REPORT.md`（中文正文，英文标题）：结论头，三行以内；rawspeed 的来源与构建（配方、耗时、产物大小、相机库怎样随包）；接口一览；解出来的字段一览；错误码表；三张样张的对照结果；坏文件的结果；计时表（九张加冷热）；验收清单每条的命令与输出；commit 的最终哈希；复审的结论头；**给用户看的汇报**（一节，B2-a 的部分）；「未做 / 未验」两段。

stdout 最后一条消息一次性完整输出同样内容。
