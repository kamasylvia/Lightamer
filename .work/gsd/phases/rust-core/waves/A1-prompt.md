# 执行 lane A1（omp）：许可证与依赖核查

## 背景

开发计划已经开工。你是阶段 A 的第一波。先读这三份文件：

- `.work/gsd/phases/rust-core/PLAN.md` 的 §0、§1.1，以及 A1 那张波次卡（阶段 A 里第一张）。计划顶部有一行修订提示。
- `.work/gsd/phases/rust-core/PLAN-AMENDMENTS.md`：全部七条。和本波直接相关的是 A-3（许可证变体已确认为 `GPL-3.0-or-later`）、A-5（脚本放已有的 `Scripts/`）、A-6（rawspeed 钉 darktable 所钉的提交 `0c16fee77`）。
- `.work/gsd/phases/rust-core/PLAN-TABLES.md` 的 T1：依赖与许可证的输入表，每一项都写着「待 A1 核实」。你的工作就是把它核实成一张有证据的表。

用户的有关裁决，照做，不要重开：项目许可证保持 GPL-3.0，精确变体是 `GPL-3.0-or-later`（用户是唯一版权人，已确认）；darktable 的代码可以移植，保留版权声明并标注修改；解码主路径是 rawspeed；全部用 Rust，界面用 gpui 族；Apple 能力独占一个模块。

工作目录 `/Volumes/UNITEK/Documents/Development/Lightamer`。HEAD 先亲核并记录。全程中文，commit message 英文。这条 lane **只写文档、许可文件和一个检查脚本**，不构建，不跑产品测试，不开图形程序。

## 要做的

**1. 审计表 `docs/LICENSE-AUDIT.md`。** 一行一个依赖，列：名称、版本、来源（地址，或提交号）、许可证的 SPDX 标识、证据（文件路径加行号，或地址加原文引用）、我们怎样链接（静态库、动态库、源码移植、纯 Rust 依赖）、它带来的义务、我们怎么做。要覆盖：

- T1 表里的每一项。
- 两个现有 spike 的锁文件里出现的每一个 crate：`.work/gsd/phases/rust-core/SPIKE-RUST-APPLE-src/Cargo.lock` 和 `.work/gsd/phases/gpui-viewport/src/Cargo.lock`。传递依赖里许可证特别的（MPL-2.0、Unicode-DFS、CC0、ISC 一类）单独点出来。
- darktable 源码本身（我们要移植它的模块）。
- 数据包：lensfun 的镜头数据库。标明代码和数据是不是两个许可证。
- 以后会用到但现在还没引入的：`rusqlite`、Rust 的图像编解码库、XMP 的三个候选（`xmp_toolkit`、`xmpkit`，以及不引入库的做法）。这一类只登记许可证，不做取舍。

表后面写清**本项目的许可政策**：允许清单是什么、什么情况要例外、例外谁批；移植来的每个源文件要保留什么、加什么。

**2. rawspeed。** 以 darktable `679d594f5d` 钉住的那个提交为准。darktable 源码在 `/Volumes/UNITEK/Documents/Development/Lightamer-rust-spike/refs/dt-master`，它的 `src/external/` 下有 rawspeed 的提交号。本机另有一份 rawspeed 仓库在 `/Volumes/UNITEK/Documents/Development/Lightamer-rawspeed-spike/rawspeed`，但它在另一个提交上。取那个钉住的提交里的 `LICENSE` 和源码头部的许可声明（本地仓库没有这个提交，就用 `gh api` 取，或者经 SSH 取到本地仓库里）。回答三个问题，每个都要有原文依据：

- 它到底是 LGPL-2.1-only、LGPL-2.1-or-later，还是 LGPL-3.0。仓库里的 `LICENSE` 文件和源码头部的写法可能不一致，不一致就写出来。
- 一个 GPL-3.0-or-later 的项目怎样用它才是合规的：静态链接要满足什么，动态链接要满足什么。
- darktable 自己怎样链接它，在它的文档或许可文件里是怎么说的。

给出你的推荐和理由。

**3. 其它 C 库。** lensfun（代码和数据库各是什么许可证，以 darktable 钉住的版本为准）、lcms2。标明哪些可以换成纯 Rust 的实现，换成哪个。

**4. 检查脚本 `Scripts/check-licenses.sh`。** 配两个数据文件 `Scripts/licenses-allow.txt` 和 `Scripts/licenses-exceptions.txt`。脚本的行为：

- 输入是一个 cargo 工作区的路径。没有参数时检查仓库根目录的工作区；现在仓库根目录还没有工作区，所以必须支持传路径。
- 用 `cargo metadata --locked --offline` 取每个包的许可证字段，逐个对照允许清单。不在允许清单里、又在例外清单里的，放行并打印例外理由。两边都不在的，报错。
- 许可证字段为空的包，按不在允许清单处理。
- 输出一张表，最后给出退出码：全部通过是 0， otherwise 1。
- 数据文件格式非法时直接报错退出。

脚本本身要过 `bash -n`；本机有 shellcheck 的话也过一遍。

**5. 测试脚本。** 三组，命令和输出都写进报告：

- 正例：对两个 spike 的工作区各跑一次。`/Volumes/UNITEK/Documents/Development/Lightamer-rust-spike/Cargo.toml` 和 `/Volumes/UNITEK/Documents/Development/Lightamer-gpui-spike/viewport/Cargo.toml`。它们在仓库外，只读，不要改。只取元数据，不构建。为了通过，要把它们用到的 crate 补进允许清单；补的每一项都要在审计表里有行。
- 负例：在临时目录建一个最小的工作区，一个包的许可证写成不允许的（比如 AGPL-3.0-only），另一个包不写许可证字段。脚本必须报出这两个包并以 1 退出。
- 数据文件：允许清单里写一行非法内容，脚本必须报错退出。测完改回来。

**6. 更新 `NOTICE` 和 README 的许可一节。** README 的 `## License` 现在写的是 GPL-3.0，改成 `GPL-3.0-or-later`，写明是版权持有人 2026-11-26 确认的。`NOTICE` 增加一节，写这次重写的许可政策、darktable 的署名方式、rawspeed 与 lensfun 的条目，以及第三方 crate 清单怎样由脚本再生成。`NOTICE` 里已有的内容不要删。

## 计划规定的通用纪律（原样保留）

- 变换规则：不改任何封存面；新增依赖先过 A1（本波就是 A1）。
- 验收清单：本波卡片第 5 条的命令逐条跑绿；`bash -n`（本波没有 Rust 代码，`fmt` 和 `clippy` 不适用）；`Scripts/machine-guard.sh` 在开始任何编译之前跑一次（本波不编译）；任务书末尾附「未做 / 未验」。
- 通用纪律：`.work/` 之外不写计划面文件；一次只跑一个重活；报告里每个数字给命令。

## omp 域内自审（项目既定模型）

产物落盘并提交后，另起一个独立的 `omp -p --auto-approve --thinking max "<复审任务书>"` 实例复审。复审实例只读：随机挑审计表的五行，打开证据核对；重跑脚本的正例和负例；核对 `git show --stat` 只动了允许改的文件。结论头 `PASS / N error + N minor`。发现的问题回注修订，修订记录附在报告末尾。复审输出落 `.work/gsd/phases/rust-core/waves/A1-review.log`。

## 纪律

- **只允许改这些文件**：新增 `docs/LICENSE-AUDIT.md`、`Scripts/check-licenses.sh`、`Scripts/licenses-allow.txt`、`Scripts/licenses-exceptions.txt`；修改 `NOTICE`、`README.md`（只动 `## License` 那一节）；新增 `.work/gsd/phases/rust-core/waves/A1-REPORT.md` 和 `A1-review.log`。Swift 的产品代码、`Project.swift`、`Tests/` 一个字都不要动。
- 一个 commit，Conventional Commits 格式，message 带 `refs #32`，逐路径 `git add`，禁 `git add -A`。**零 push。**
- 不构建、不跑产品测试、不下载安装任何软件。`cargo metadata` 只取元数据。
- 不读、不打印任何凭据文件（`~/.agents/.env` 一类），报告里不出现密钥。
- 不碰用户照片库 `/Volumes/UNITEK/Cloud Drive/QSync/Medias/Photos/Workspace`：不读、不列目录。
- 网络：模型调用走已给定的代理环境变量。`gh api` 和 `git fetch` 先直连，失败再单独给那一条命令加代理。git 走 SSH。
- 这是工程核查，不是法律意见。审计表开头写一句免责。
- 数字不编，查不到就写查不到并写出查过什么。
- 总墙钟不超过 150 分钟，含自审。到点交已有结果。

## 交付

1. 上面列的文件和一个 commit。
2. `.work/gsd/phases/rust-core/waves/A1-REPORT.md`（中文正文，英文标题）：结论头（三行以内）；审计表覆盖了多少项、几项有例外、rawspeed 的三个问题的答案；验收命令与输出；commit 的哈希与 `git show --stat`；「未做 / 未验」两段。

stdout 最后一条消息一次性完整输出同样内容。
