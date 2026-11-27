# 执行 lane B2-b（omp）：解码的后半——内嵌缩略图、栅格解码、EXIF 光学参数、验收补齐、演示

## 背景

阶段 B 是第 0 期，**每一波做完都要停下来给用户看**。B2 是第四波：解码。分两段串行；它之前的管线内核（B1）已经闭环。

- **B2-a（已做完，提交 `e3cb37b6`）**：rawspeed 以子模块钉住并编出来、薄薄的一层 C 接口、相机库只加载一次、RAW 解码与元数据、错误码、最小的 `decode --dump`。
- **B2-b（就是你）**：内嵌缩略图、栅格解码（JPEG/TIFF/PNG）、EXIF 的光学参数、把验收补齐、演示脚本、文档。**你做完、塔台核过，这一波就向用户汇报。**

用户的裁决（已定，不要重开）：

- **解码的主路径是 rawspeed**，钉 darktable 自带的那一份；CIRAW 推迟。许可按第一波的许可证审计（静态链接，整体 `GPL-3.0-or-later`）。
- **`unsafe` 只许在薄薄的一层接口里，逐处写安全说明；坏文件不中止进程。**
- **新依赖的许可证表达式必须先在 `Scripts/licenses-allow.txt` 里**，不在就停下报告，那个文件不许改。
- **非 macOS 不是目标。** 命令只做有界的活——这一波只做库和命令行工具，不接引擎。

先读（都在 `.work/gsd/phases/rust-core/` 下，除非写了别的路径）：

- `PLAN-B.md` 里 B2 那张卡（验收第五条归你；「向用户汇报」那一栏归你）。`waves/B2a-REPORT.md`。`waves/VERIFY.md` 的最后一节。
- `docs/DECODE.md`（仓库根下）。`docs/LICENSE-AUDIT.md` 里 B2-a 加的几行。
- `crates/lightamer-decode/`（`build.rs`、`csrc/`、`src/`、`tests/`、`tools/`）；`apps/lightamer-cli/src/decode.rs`、`tests/decode_dump.rs`。
- 子模块 `external/rawspeed/`（只读）：缩略图的接口（搜 `decodeThumbnail`、`Thumbnail`、`ThumbDataType`）。
- `PLAN-B.md` 里 B15 那张卡（内嵌缩略图的快路径要怎样用 `--thumb` 这个探针）。

工作目录 `/Volumes/UNITEK/Documents/Development/Lightamer`。HEAD 先亲核并记录。全程中文，代码注释和标识符英文，commit message 英文。

## 现在的起点（塔台看的，每一条你自己核）

- `rs_thumb` 和命令行的 `--thumb` 是占位，恒返回「暂不支持」那个码。
- 栅格解码（JPEG、TIFF、PNG）没有。
- EXIF 的光学四项（快门、光圈、焦距、镜头）和机内色温恒为空——rawspeed 不暴露它们。以后镜头校正和检索列要用。
- **CR3 解不出**：这个钉点的 rawspeed 没有 CR3 解码器。这一段不做 CR3，但它要干净地报「不支持的格式」，演示里如实展示。
- rawspeed 没有只解一块区域的接口，解码整幅交付——这是现状，不用改。
- CC0 样张在 `~/Library/Application Support/Lightamer/TestRAW/`，九个（两个不是 RAW）。**不碰用户的照片库**（位置见仓库的 `AGENTS.md`：不读、不列目录）。

## 要做的

**1. 内嵌缩略图。** `rs_thumb` 真实现：用 rawspeed 的缩略图接口取出字节和它的格式（JPEG、未压缩的位图、或者没有）。Rust 这一侧包成安全类型；rawspeed 给未压缩位图就包成像素缓冲。没有内嵌缩略图时返回分了类型的「没有内嵌缩略图」。C++ 的异常照样不许穿过 C 的边界。

**2. 栅格解码**（纯 Rust）：JPEG、PNG、TIFF（8 位和 16 位，灰度、RGB、带透明通道的），解成一种统一的缓冲（宽、高、分量数、位深），带上的 ICC 文件如果有就一并交出来。crate 的选型：许可证表达式先过允许清单；候选和选它的理由（速度、位深覆盖、维护状态）写进报告。相机 RAW 不走栅格解码器（它们走 rawspeed）。

**3. EXIF 的光学参数。** 用一个纯 Rust 的 EXIF 读取 crate（选型规矩同上；B15 那张卡列了几个候选，以许可证检查为准）从原文件读：快门速度、光圈、焦距、镜头型号、拍摄时间、方向、机内色温和色调（如果有）。接到 B2-a 留空的那几个字段上。机身和镜头的序列号这一段不读（现在用不到）。

**4. 命令行。** `lightamer-cli decode --dump <文件>`：

- 缩略图：`--thumb <输出文件>` 把内嵌缩略图的字节写出来，并报告格式、字节数、能不能解、解出来的宽高——B15 的内嵌快路径拿它当探针。
- 栅格文件也能用：打印宽、高、位深、分量数、有没有 ICC。
- EXIF 的那几项逐值打印。

**5. 演示脚本** `Scripts/rust-decode-demo.sh`：用发行版构建，每一步打印结果，退出 0。

  1. 三张样张（ARW、RAF、NEF）的四元组——宽高、黑电平、白点、白平衡——和耗时，一张表。
  2. 九个样张各自的耗时，一张表。
  3. 五种坏文件（空文件、随机字节、截断一半、只有文件头、改了扩展名）：打印错误码和那句人能读的话，然后证明进程还活着。
  4. 内嵌缩略图：字节数、格式、解出来的尺寸。
  5. CR3 那张：打印「不支持的格式」。
  6. 清掉临时目录。

只用 CC0 样张和自己合成的小图。

**6. 文档。** `docs/DECODE.md` 补全（缩略图、栅格、EXIF、命令行、已知的不支持项：CR3）；`crates/README.md` 里改动了的行；`NOTICE` 和 `docs/LICENSE-AUDIT.md` 追加新进的 crate。

## 测试

每一条行为一个测试，名字能看出测的是什么。

- **内嵌缩略图**（卡片验收第五条）：有内嵌 JPEG 缩略图的样张——字节非空、解得开、宽高合理；缩略图格式不是 JPEG 的样张如实处理；没有内嵌缩略图的文件返回分了类型的错误；坏文件的缩略图请求不崩。
- **栅格**：JPEG、PNG、TIFF 各至少两张（8 位和 16 位；带透明通道的一张）——自己合成、自己解，解出来的像素逐值等于写进去的；截断的栅格文件返回分了类型的错误。
- **EXIF**：对 7RM5 那张样张读出的四项和文件里的实际值一致——对照来源要独立（例如系统的 `mdls` 或 `sips`，本机哪个可用你先试），命令和输出进报告；没有 EXIF 的文件各项为空，不报错。
- 命令行：`--dump`、`--thumb` 在 RAW 和栅格文件上各跑通一次。
- 坏文件五种在这一段新加的路径上（缩略图、EXIF）也不崩。
- B2-a 已有的测试一个不删、照旧全绿。

## 计划规定的通用纪律（原样保留）

- 变换规则：不改任何封存面；新增依赖先过许可证的允许清单。
- 验收清单：`cargo fmt --all --check` 与 `cargo clippy --workspace --all-targets -- -D warnings` 绿；`Scripts/machine-guard.sh` 在构建之前跑一次；任务书末尾附「未做 / 未验」。
- 通用纪律：`.work/` 之外不写计划面文件；一次只跑一个重活；报告里每个数字给命令。

## 阶段 B 每一波都适用的两条

- **这一波做完要停下来给用户看**：报告里单列一节「给用户看的汇报」，写给没看过内部的人——整个 B2 做成了什么，怎样用一条命令现场看（给出命令），哪几样还不支持。
- **不崩溃的 lint**：出错一律返回分了类型的错误，错误要能变成一句人能读的话。

## 验收清单（命令和输出都写进报告）

- `cargo test -p lightamer-decode --locked`、`cargo test -p lightamer-cli --locked` 绿，「测试」一节每一条都有对应的测试。
- `cargo test --workspace --locked` 绿，测试数不少于起点加上这一段新增的（起点你自己先跑一遍记下来；塔台核 B2-a 时是 578 个通过，另三个默认不跑的计时测试）。
- 子模块仍然钉在那个提交：`git ls-tree HEAD external/rawspeed` 的哈希是 `0c16fee7…`。
- 卡片验收的第五条成立；第一到第四条照旧成立（B2-a 的测试没动）。
- `cargo xtask layers` 等检查通过；`Scripts/rust-apple-boundary.sh` 退出 0；`Scripts/check-licenses.sh` 退出 0。
- 六条不崩溃 lint 的命令行口径对整个工作区退出 0；新增的 `unsafe` 块逐处有安全说明；文档零警告（都在总检查里）。
- `Scripts/rust-decode-demo.sh` 从头到尾退出 0，输出贴进报告；另外三个演示脚本（会话、历史、渲染）仍然退出 0。
- `Scripts/rust-ci-lite.sh` 从头到尾退出 0。守卫不过（比如机器上别人在写盘）就等它过了再跑，不要绕；实在等不到，如实写明卡在哪一步、哪些项是逐项单独跑过的。
- 跑完之后 `git status --porcelain` 里没有临时文件；系统的临时目录里没有这一波留下的目录；没有残留的进程；没有往仓库以外写东西。
- `git show --name-only HEAD` 里只有下面「纪律」一节允许的路径；其中有 `B2b-REPORT.md` 和 `B2b-review.log`。

## 产物先落盘，再收尾

- **代码和测试一绿就先提交一次**。之后可以继续提交，最后用 `git commit --amend` 或 squash 收成**一个**提交。
- **自审**：产物落盘并提交后，另起一个独立的 `omp -p --auto-approve --thinking max "<复审任务书>"` 实例复审。复审实例只读，但可以运行构建、测试和演示脚本：重跑验收清单的全部；核缩略图的字节确实来自文件里内嵌的那一份（和 `exiftool` 一类的独立工具或手写的提取比一下大小或哈希，本机哪个可行你先试）；核栅格的往返测试是真的逐值比；核 EXIF 的对照来源是独立的；核新加的 `unsafe` 块都有安全说明、C++ 异常出不了边界；核 `git show --stat` 只含允许的路径。结论头 `PASS / N error + N minor`。发现的问题回注修订，修订记录附在报告末尾。复审输出落 `.work/gsd/phases/rust-core/waves/B2b-review.log`。
- **退出的次序**：复审实例写完结论头之后，你才依次做四件事——把复审的结论头和修订记录写进报告；`git commit --amend` 把最终的报告和 `B2b-review.log` 并进那一个提交（不 push，所以 amend 是安全的）；删掉你建的临时文件和目录；最后主进程才退出。报告里不许留「待填」。

## 纪律

- **只允许新增或修改这些路径**：`crates/lightamer-decode/` 整个目录；`apps/lightamer-cli/` 整个目录；`Scripts/rust-decode-demo.sh`；根目录的 `Cargo.toml`、`Cargo.lock`；`docs/DECODE.md`；`docs/LICENSE-AUDIT.md`；`NOTICE`；`crates/README.md`（只改动了的那几行）；`.work/gsd/phases/rust-core/waves/B2b-REPORT.md` 和 `B2b-review.log`。其它一律不动。`Scripts/licenses-allow.txt` 不许改；子模块不许动。
- 一个 commit（见上），Conventional Commits 格式，message 带 `refs #32`，逐路径 `git add`，禁 `git add -A`。**零 push。**
- 构建之前跑一次 `Scripts/machine-guard.sh` 并记录输出。并行度 6 以内。不用 `caffeinate`。一次只跑一个重活。
- 不跑 Swift 的构建和测试，不打开任何图形程序，不运行 `darktable`，不下载安装任何软件，不安装任何编译目标，不跑任何非 macOS 目标的检查。
- 不读、不打印任何凭据文件，报告里不出现密钥。不碰用户照片库。
- 机器上可能有别人同时在跑的 omp 会话，不是你的，不碰。
- `.work/` 下有很多以前各波留下的未跟踪文件（`*.pid`、旧日志），不是你的，不碰也不提交。
- 每个源文件带 SPDX 头 `GPL-3.0-or-later`（子模块里的 rawspeed 除外）。
- 数字不编。哪一项没做成，写没做成和卡在哪一步。到时间上限就交已有结果。
- 总墙钟不超过 240 分钟，含自审。

## 交付

1. 代码、测试、脚本、文档和一个 commit。
2. `.work/gsd/phases/rust-core/waves/B2b-REPORT.md`（中文正文，英文标题）：结论头，三行以内；缩略图怎样取、各格式的样张取出来是什么；栅格的选型与理由；EXIF 的选型、对照的结果；演示的输出；验收清单每条的命令与输出；commit 的最终哈希；复审的结论头；**给用户看的汇报**（一节，覆盖整个 B2）；「未做 / 未验」两段。

stdout 最后一条消息一次性完整输出同样内容。
