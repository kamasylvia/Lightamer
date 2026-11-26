# 执行 lane A3（omp）：模块描述与自动发现注册

## 背景

开发计划的阶段 A 在连跑。A1（许可证核查）和 A2（工作区骨架）已完成。你是第三波，也是阶段 A 里第一波写真正代码的。先读：

- `.work/gsd/phases/rust-core/PLAN.md` 的 A3 那张波次卡（阶段 A 里第三张）和 §2.2「模块描述与自动发现」、§3.0 的共用任务书模板。计划顶部有一行修订提示。
- `.work/gsd/phases/rust-core/PLAN-AMENDMENTS.md`：全部八条。和本波直接相关的是 **A-1（基线是上游 master 的提交 `679d594f5d`，不是 `release-5.7.0` tag）**、A-5 和 A-8（脚本放 `Scripts/`，文件名带 `rust-` 前缀）。
- `.work/gsd/phases/rust-core/PLAN-TABLES.md` 的 T3（描述字段的草案）、T4（发现机制的三方案与裁决）、T5（默认顺序夹具）。**这三张表是按 `release-5.7.0` 写的，凡是提到那个 tag 的地方都改按 `679d594f5d` 做**：模块的数量、优先级、行序都以这个提交的 `src/common/iop_order.c` 为准；那个提交里多出来的模块（比如 `contrastntexture`、`spektrafilm`）也要进夹具。
- `.work/gsd/phases/rust-core/CORE-DESIGN.md` §1：darktable 的回调与管线的对应，只在需要理解描述字段含义时参考。

工作区的现状：仓库根目录有 cargo 工作区，`crates/` 下 19 个包，都是空壳，见 `crates/README.md`。`Scripts/rust-ci-lite.sh` 是一条命令的总检查，在当前 HEAD 上全绿。

用户的有关裁决，照做，不要重开：**模块必须自动被发现和注册。核心里不写模块名单，也不写槽号。每个模块自带一份描述。darktable 模块的描述里带着 darktable 的名字、顺序优先级、参数格式，这是模块自己的数据。** 新增一个模块就是加一个目录，不改核心。

工作目录 `/Volumes/UNITEK/Documents/Development/Lightamer`。HEAD 先亲核并记录。全程中文，代码注释和标识符英文，commit message 英文。这一波**不写任何像素处理**，不碰 `dt-core` 和 `dt-api`。

## 要做的

**1. 描述结构。** 在 `dt-iop-traits` 里定义模块描述，按 T3 的草案。至少有：唯一标识（就是 darktable 的 op 名）、显示名用的键、所属分组、顺序键（raw 和 jpg 两套，每套是一个优先级加一个行内序）、参数描述（结构体名、字节数、当前版本号、迁移函数的位置，这一波只留字段，不填真实布局）、标志位、色彩空间需求、面板控件的描述类型（只定义类型，给界面生成用）、历史相关的键。纯数据，可调试打印。字段你可以增删，增删要写进报告并说明理由。

**行内序为什么要单独存**：darktable 的默认顺序表里有若干模块优先级相同，先后取决于它们在表里的行序，不是字母序。行内序是模块在 darktable 表里的行号，属于模块自己的数据。

**2. 自动发现。** 按 T4 的方案 B：每个域 crate 里放一个构建脚本，扫描 `src/modules/<id>/mod.rs`，生成模块声明和一张描述表，再 `include!` 进来。域 crate 固定是四个：`dt-iop-raw`、`dt-iop-geom`、`dt-iop-color`、`dt-iop-display`。这是按层分的四个包，不是模块名单。

- 构建脚本的重新编译条件要指向目录本身，这样目录里增删文件才会触发重编。这一点你要实测并写进报告：往一个模块目录里加一个文件，看是否触发重编；量一下改一个模块文件之后 `cargo check -p dt-iop-color` 的时间。
- `dt-registry` 依赖四个域 crate（反过来不行），从它们各自的描述表汇总，提供三样东西：全部描述的列表、按标识查找、raw 和 jpg 两条默认顺序链。默认顺序链的算法是按（优先级，行内序）排序。
- 标识重复必须在测试里查出来。

**3. 给基线里的每个模块建一个描述桩。** 基线是 darktable `master` 的提交 `679d594f5d`，源码在 `/Volumes/UNITEK/Documents/Development/Lightamer-rust-spike/refs/dt-master`（只读它；不要读 `/Volumes/UNITEK/Documents/Development/darktable`，那是 darktamer 的工作树）。

- 写一个 `xtask` 子命令，解析这个提交的 `src/common/iop_order.c` 里的 `v50_order` 和 `v50_jpg_order` 两张表，给每个具名模块生成一个描述桩目录。桩里只填标识、顺序键，其余字段留明确的「未设」值。哨兵条目不生成桩。
- **哪些模块放进哪个域 crate**：T2 里点过名的按 T2；其余的按一条确定的规则分，规则写进报告和 `crates/README.md`。可以用 darktable 各模块声明的操作标签来分。分错的以后挪一个目录就行，发现机制不在乎。
- 夹具文件放 `crates/dt-registry/fixtures/` 下，文件名里带上游提交号。每条是名字、raw 的优先级和行内序、jpg 的优先级和行内序。夹具的生成命令和上游提交号要留在仓库里（JSON 放不了注释，就放在同目录的说明文件里）。
- 再写一个 `xtask` 子命令做同步检查：重新解析上游的那两张表，和夹具、描述桩逐项比对，不一致就退出 1。以后基线升级时靠它。

**4. 测试。**

- raw 默认顺序链与夹具逐位相等，从第一个到最后一个。
- jpg 默认顺序链与夹具逐位相等。
- 负测：把两个同优先级模块的行内序对调，顺序必须变。这证明顺序不是靠字母序碰巧对的。
- 标识不重复。
- 探针脚本 `Scripts/rust-discovery-probe.sh`，照 T4：在一个域 crate 里造一个 `zz_probe` 模块目录，断言注册表里有它；删掉目录，断言没有。两个方向都要跑，跑完工作区要恢复原样。

**5. 核心里没有任何模块名。** `dt-core`、`dt-api`、`dt-registry` 三个 crate 的源码里，不允许出现任何一个基线模块名作为字符串字面量。用 `xtask` 加一个子命令来查，拿夹具里的名字逐个去搜。这一波 `dt-core` 和 `dt-api` 本来就不该被改。

## 计划规定的通用纪律（原样保留）

- 变换规则：不改任何封存面；新增依赖先过 A1。
- 验收清单：本波卡片第 5 条的命令逐条跑绿（其中「93 条逐位」改按基线提交里的实际条数）；`cargo fmt --all --check` 与 `cargo clippy --workspace --all-targets -- -D warnings` 绿；`Scripts/machine-guard.sh` 在构建之前跑一次；任务书末尾附「未做 / 未验」。
- 通用纪律：`.work/` 之外不写计划面文件；一次只跑一个重活；报告里每个数字给命令。

## 6. 验收清单（命令和输出都写进报告）

- `cargo test -p dt-registry` 退出 0，两条顺序链的测试覆盖基线里的全部具名模块。
- `Scripts/rust-discovery-probe.sh` 两个方向都通过，跑完 `git status --porcelain` 里没有探针留下的东西。
- `rg -n '"(rawprepare|demosaic|colorout)"' crates/dt-core crates/dt-api` 没有输出。
- 「核心里没有任何模块名」的 `xtask` 子命令退出 0。
- 同步检查的 `xtask` 子命令退出 0。
- `time cargo check -p dt-iop-color` 不超过 40 秒。
- `Scripts/rust-ci-lite.sh` 从头到尾退出 0。它包含许可证检查：你如果新增了依赖，依赖的许可证表达式必须已经在 `Scripts/licenses-allow.txt` 里，否则停下报告，不要自己改那个文件。
- 新增的依赖（如果有）在 `docs/LICENSE-AUDIT.md` 里各有一行，写版本和许可证证据。
- `cargo metadata --locked --no-deps` 仍然是 19 个包。
- `git show --name-only HEAD` 里只有下面「纪律」一节允许的路径。

## omp 域内自审（项目既定模型）

产物落盘并提交后，另起一个独立的 `omp -p --auto-approve --thinking max "<复审任务书>"` 实例复审。复审实例只读，重点核四件事：夹具是不是真的从 `679d594f5d` 的源码解析出来的（自己打开 `iop_order.c` 抽五条对）；顺序测试是不是逐位比较而不是只比长度或集合；探针脚本是不是真跑过两个方向；`dt-core`、`dt-api`、`dt-registry` 的源码里是不是真的没有模块名。结论头 `PASS / N error + N minor`。发现的问题回注修订，修订记录附在报告末尾。复审输出落 `.work/gsd/phases/rust-core/waves/A3-review.log`。

## 纪律

- **只允许新增或修改这些路径**：`crates/dt-iop-traits/`、`crates/dt-registry/`（含夹具目录）、`crates/dt-iop-raw/`、`crates/dt-iop-geom/`、`crates/dt-iop-color/`、`crates/dt-iop-display/`、`crates/xtask/`、`crates/README.md`、根目录的 `Cargo.lock`、`Scripts/rust-discovery-probe.sh`、`docs/LICENSE-AUDIT.md`（只有新增了依赖才追加行）、`.work/gsd/phases/rust-core/waves/A3-REPORT.md` 和 `A3-review.log`。**`crates/dt-core/` 和 `crates/dt-api/` 不许动。**
- 一个 commit，Conventional Commits 格式，message 带 `refs #32`，逐路径 `git add`，禁 `git add -A`。**零 push。**
- 构建之前跑一次 `Scripts/machine-guard.sh` 并记录输出。并行度 6 以内。不用 `caffeinate`；一定要用就带秒数上限，不留孤儿进程。
- 不跑 Swift 的构建和测试，不打开任何图形程序，不下载安装任何软件。
- 不读、不打印任何凭据文件，报告里不出现密钥。
- 不碰用户照片库 `/Volumes/UNITEK/Cloud Drive/QSync/Medias/Photos/Workspace`：不读、不列目录。
- 每个源文件带 SPDX 头 `GPL-3.0-or-later`。
- 数字不编。哪一项没做成，写没做成和卡在哪一步。到时间上限就交已有结果。
- 总墙钟不超过 240 分钟，含自审。

## 交付

1. 上面的代码、测试、夹具、脚本和一个 commit。
2. `.work/gsd/phases/rust-core/waves/A3-REPORT.md`（中文正文，英文标题）：结论头，三行以内；基线里具名模块的总数和每个域 crate 分到几个；你对描述字段的增删及理由；重新编译条件的实测结果和增量检查耗时；第 6 节每条验收的命令与输出；commit 的最终哈希（修订过就写修订后的）与 `git show --stat`；「未做 / 未验」两段。

stdout 最后一条消息一次性完整输出同样内容。
