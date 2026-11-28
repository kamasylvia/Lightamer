# 执行 lane B3-1b（omp）：模块级对照架 + 转写 rawprepare

## 背景

B3 这一波转写 darktable 的 raw 头段四个模块。前三段已经把管线备好（单通道格式、RAW 事实、链上状态 `PipeState`、解码接入）。你这一段做两件事：**搭对照架**，然后用它转写第一个模块 `rawprepare`。

**为什么要对照架**：计划卡片上写的验收是「darktable-cli 整条管线渲染后逐像素比」，但管线现在只有头段，整条管线要到后面几波才能出图。所以模块这一级改用另一种对照：把上游模块的 C 代码（`release-5.7.0`）**原样**编进一个只给测试用的库，Rust 转写在同一块输入上跑，逐像素比。这座架后面每个模块波都复用，所以搭的时候想着下一个人怎么加第二个模块。

工作目录 `/Volumes/UNITEK/Documents/Development/Lightamer`，HEAD = `cfbc3fba`（先亲核；工作树里 `waves/VERIFY.md` 有塔台没提交的改动，不是你的，别碰）。全程中文，代码注释和标识符英文，commit message 英文。

**先读这两个技能文件并照做**：`/Users/kamasylvia/.agents/skills/ponytail/SKILL.md`、`/Users/kamasylvia/.agents/skills/rust-best-practices/SKILL.md`。项目自己的优先级：公开的项写 `///`，其余注释只写为什么；错误类型手写（不引 thiserror / anyhow）；不跟「一个测试只断言一件事」和类型状态；没人要的代码不写。

## 用户已定的几条（不许动）

- 阶段 0 只保证解 A7R5（A-27）。**取样只用索尼 ARW**：`~/Library/Application Support/Lightamer/TestRAW/7RM5-LosslessCompressedLarge.ARW`（CC0 样张，机身 ILCE-7RM5）。样张不在就跳过并写明。**不碰用户的照片库** `/Volumes/UNITEK/Cloud Drive/QSync/Medias/Photos/Workspace`（不读、不列目录）；`/Volumes/UNITEK/Cloud Drive/` 下面一个字都不写。
- darktable 的上游基线钉在 `release-5.7.0`。参考源码只读，在 `/Volumes/UNITEK/Documents/Development/Lightamer-rust-spike/refs/dt-master`，用 `git show release-5.7.0:<路径>` 读。不改它、不构建它、不运行 darktable。**不读** `/Volumes/UNITEK/Documents/Development/darktable` 和 `darktamer` 这两个工作树。
- 模块自动发现、自动注册，不设中央清单。
- DNG 增益图不做（A-27，ARW 没有）。
- **新 crate 一开始就带 `README.md`**（用户 2026-11-28 的要求）。
- GPL 同许可复制纪律：转写来的代码保留 darktable 的版权声明，SPDX 用 `GPL-3.0-or-later`，加一行 `Modified for Lightamer: <日期> <改了什么>`；`NOTICE` 同步。

## 先读

- `docs/PIPELINE.md` 的「链上状态」一节；`.work/gsd/phases/rust-core/waves/B3-1a-REPORT.md` 第一节（上游模型：状态本体 `dt_iop_buffer_dsc_t`、建链期读的是快照、处理期沿链演进、分块时最大值每块重置）。
- `crates/lightamer-iop-traits/src/{module,state,image,lib}.rs`：`IopModule` 现在的签名——`commit(&self, params, image, state: &mut PipeState)`、`process(&self, data, input, output, rin, rout, state: &mut PipeState)`；`PipeState`；`ImageInfo` / `RawFacts`；`ModuleDesc` / `ParamsDesc` / `ParamField` / `ParamType`。
- `crates/lightamer-iop-raw/build.rs`（扫 `src/modules/*/mod.rs`，有 `pub fn create(` 才进「已实现」的表）和一个模块桩 `src/modules/rawprepare/mod.rs`。
- `crates/lightamer-testkit/src/raw_sample.rs`：`sample_path` / `load_raw_sample`；`crates/lightamer-decode/src/pipe.rs` 的 `DecodedImage::pipe_input(region)`。
- `crates/lightamer-decode/build.rs`（它怎么用 `cc` 编很薄的 C 接口，照它的样子）；`crates/xtask/src/layers.rs`（新 crate 要登记，类别用 Testkit：别的 crate 只能当测试依赖用它）。
- `.work/gsd/phases/rust-core/CORE-DESIGN.md` §7「模块移植六步」。
- 上游：`src/iop/rawprepare.c` 全文（`process` 在 324 行，`commit_params` 在 683 行，`reload_defaults` 在 756 行，`modify_roi_out / modify_roi_in / output_format` 在 256–302 行）；`dt_rawspeed_crop_dcraw_filters` 在 `src/imageio/imageio_rawspeed.cc`；`src/common/image.h` 里 `dt_image_is_rawprepare_supported` 一类的判定。

## 第一部分：对照架（新 crate `lightamer-oracle`）

**先做的第一步，也是一道检查点**：把 `rawprepare.c` 里非图形界面的代码原样编过，在一张合成瓦片上跑出一个数——哪怕 Rust 转写一个字还没写。做成了立刻提交一次。**两个小时还没编过就停下来**，把卡在哪（缺哪些内部依赖、试过什么）写进报告再退出，不要绕去手抄一份 C 当对照。塔台看完再决定下一步。

做法（细节你定，下面是要守的）：

1. **上游代码原样取，不改一个字。** 用脚本从钉住的标签按行范围抽出来（`git show release-5.7.0:src/iop/rawprepare.c` 再 `sed -n`），存进 `crates/lightamer-oracle/upstream/`。每个文件记下：上游路径、标签、blob 哈希（`git rev-parse release-5.7.0:<路径>`）、抽的是哪几段行范围。写一个 `tools/extract.sh <模块> [--check]`：重新抽一遍，和仓里的逐字节比。参考克隆的位置用环境变量传，不在就跳过。图形界面函数和 OpenCL 路径不抽。
2. **有逻辑的函数一律原样取，不许用替身重写**（比如 `dt_rawspeed_crop_dcraw_filters`、`_image_is_normalized`、`_compute_proper_crop`、`dt_image_is_rawprepare_supported`）。替身只顶纯粹的接口：内存分配、日志、数据库和图像缓存、信号、图形。替身放在单独的 `stubs/` 下，每个替身写清顶的是上游的什么。
3. **会改变行为的替身要单列**。比如 `commit_params` 里有一处会往 dt 的图库写裁切（`_image_set_rawcrops`），对照架里用替身顶掉——这种要在 `README.md` 里列一张「行为替身」表，说明它和上游差在哪、在什么条件下不可观察。
4. **小管线**（`csrc/chain.c`，自己写的胶水）：照上游的顺序跑一串模块——每个模块建数据、`reload_defaults`、`commit_params`（读的是快照）；然后按链序逐个 `process`，状态沿链演进。图像事实由调用方填进 `dt_image_t` 的替身结构里。以后加第二个模块就是往这张表里加一项。
5. **Rust 这一侧**给一个安全入口（`src/lib.rs`）：传进去图像事实、各模块的参数、输入瓦片和它的 `roi_in / roi_out`，拿回输出瓦片和处理完的状态。`unsafe` 只许出现在这个 crate 里，每块写清理由（工作区默认禁止 `unsafe`，解码 crate 有先例）。
6. **编译**：用 `cc`（解码 crate 已经在用，许可证在允许表里），优化开，`-ffp-contract=off`，不开快数学。编成静态库，只进测试。
7. **登记**：分层表（Testkit）、`crates/README.md` 加一行、`docs/LICENSE-AUDIT.md` 和 `NOTICE` 加条目（只给测试用的上游代码）、`README.md`。
8. **比较的小工具**放进 `lightamer-testkit`：给实际和期望两个平面，返回平均绝对差、最大绝对差、容差内的占比；门限的常量放一起——平均绝对差 < 1/65535，容差 1/65535 内的占比 > 0.9999（沿用计划里 golden 门的那两个数）。

## 第二部分：转写 `rawprepare`

照 CORE-DESIGN §7 的六步。要点（都以上游源码为准，下面是我的读法，和源码不一致时以源码为准并在报告里写明）：

- **参数**：四路黑位、白点、裁切四边（旧界面的遗留参数）、平坦场。模块自己的参数描述用 `ParamsDesc`；数组形式的参数怎么描述，照 A3 / A4b 已定的做法，没定就选最简单的一种并写明。校验在 `commit` 里做，错误类型手写。
- **缺省参数从图像事实来**：上游的 `reload_defaults` 把图像的黑位、白点、裁切填进模块的缺省参数。我们这边参数里没给的键，就从 `image.raw` 取。
- **`commit`**：算出四路的 `sub` 和 `div`（马赛克的形式和不归一化时的形式都要）；`raw_black_level / raw_white_point` 存进提交数据。
- **`process`**：单通道马赛克那两条路（`u16` 原值和未归一化的 `f32`，公式相同）：`(in − sub[id]) / div[id]`，`id` 按 2×2 拜耳位置加裁切偏移取；裁切偏移 `csx / csy` 照 `_compute_proper_crop`。处理完照上游写链上状态：四路最大值置 1.0，CFA 图案按裁切重算后写回（X-Trans 同）。逐行用 rayon 并行，和仓库里别的模块一个写法。**浮点一步一步算，不许合并或换序**。
- **不适用时**：上游把这一片禁用（不是 RAW 马赛克、或者已经归一化）。我们的等价做法是输出等于输入、不报错；仓库里如果已有这种约定就沿用。
- **`roi`**：`modify_roi_out / modify_roi_in`（用户裁切为 0 时是恒等）。
- **不做**（报告里逐条记）：多通道预降采样的那条路（现在没有这种输入）、DNG 增益图、OpenCL、细节蒙版、图形界面。

## 测试

- **对上游**（`crates/lightamer-iop-raw/tests/` 里）：
  - 真瓦片：从样张取 4 块 256×256（居中、左上角、画面最亮的一块、最暗的一块），我们的输出对上游的输出过门；同时比链上状态（最大值、CFA 图案）。最大绝对差是多少也写进报告——这条模块是纯线性运算，关了乘加合并之后应该是逐位相等或只差最后一位；差得大要解释。
  - 合成瓦片：黑位处（应为 0）、白点处（应为 1）、超过白点、四路黑位各不相同、奇数和偶数的裁切偏移、X-Trans 图案、用户裁切不是 0。每块都和上游比。
  - 参数：缺省（从图像来）、改过黑位、改过白点。
- **自动发现**：`lightamer_iop_raw::lookup_implemented("rawprepare")` 查得到，`id()` 对得上，并且也在描述表和 registry 里（上一段留下的缺口，这里补上）。
- 取样注意内存：整张样张转成单通道帧是 244 MB，解码峰值约 900 MB。**同一个测试二进制里不许并发加载多张**——加载一次共享，或者串行；取一小块用 `pipe_input(region)`，不要先转整帧。

## 顺手修一个不稳定的测试

`apps/lightamer-cli/tests/raw_input.rs` 里的 `whole_path_counts_probe_once_decode_once` 偶尔红：它断言 `cameras.xml` 的解析计数增量为 0，但同一个二进制里别的测试第一次触发解析时计数会变。查清原因，在这一个文件里修掉（比如先让单例热起来再量）。修法写进报告。

## 每一步的内存约束

- 对照库只在测试里链接；上游的 `process` 原样分配输出，瓦片大小就是它的内存。
- 真瓦片测试的峰值以解码那次为准（约 900 MB），串行加载。
- 转写的 `process` 不许额外分配（除了 rayon 的行并行本身）；提交数据是固定大小的栈数据，不走 `Arc` 之外的堆。

## 验收清单（命令和输出写进报告）

- `cargo test --workspace --locked --no-fail-fast -j6` 绿、零失败；测试总数不少于 749 加上你新增的（逐个列出）。`raw_input` 那组测试连跑三遍都绿。
- 六条不崩溃 lint（`CARGO_INCREMENTAL=0`，`-D warnings`）和文档零警告；`cargo fmt --all --check`；`cargo xtask layers`（新 crate 登记为 Testkit）、`check-order-sync`、`check-no-iop-names`、`Scripts/check-licenses.sh` 通过。
- 五个演示脚本都退出 0（`Scripts/rust-session-demo.sh`、`rust-history-demo.sh`、`rust-render-demo.sh`、`rust-decode-demo.sh`、`rust-stream-demo.sh`）。机器上可能有别人自己的重活，负载高时计时步骤会报「测不准」，等它重试，不要绕。
- `tools/extract.sh rawprepare --check` 对着参考克隆跑，逐字节一致（参考克隆在的话）。
- 真瓦片 4 块和合成瓦片全部过门；最大绝对差写进报告。
- `lightamer-oracle` 有 `README.md`（怎么加第二个模块、行为替身表、怎么重抽和核对）；`NOTICE` 和 `docs/LICENSE-AUDIT.md` 有条目。
- `rawprepare` 不在链上时，其余行为逐字节不变（旧测试一个不改）。
- `git show --name-only HEAD` 只含「纪律」里允许的路径。允许的外部包只有 `cc`（已经是依赖）；不新增别的。

## 产物先落盘，再收尾

代码第一次全绿就提交；之后每完成一小块提交一次（检查点那一次也要提），最后 squash 成一个（Conventional Commits，subject 用 `feat(rust-core): …`，body 写 what + why，带 `refs #32`）。绿之前离开要留带路径的 stash 说明。

**退出顺序**：先填完报告 `waves/B3-1b-REPORT.md` → 再起一个 `omp -p` 实例做只读自审（隔离：只读产物，不读你的过程；第一行写结论头 `PASS / N error + N minor`；发现回写 `waves/B3-1b-review.log`）→ 有发现就修，修法记进报告的一节「复审」→ 把报告和复审日志并进那一个提交 → 删掉临时文件 → 退出。复审日志一个字不改。自审的任务书不要放进提交。

## 纪律

- **只允许新增或修改这些路径**：`crates/lightamer-oracle/`（新建）、`crates/lightamer-iop-raw/`、`crates/lightamer-testkit/`、`crates/xtask/src/layers.rs`（只许登记新 crate）、`apps/lightamer-cli/tests/raw_input.rs`（只许修那一个不稳定的测试）、`crates/README.md`、`docs/PIPELINE.md`（只许补一两句）、`docs/LICENSE-AUDIT.md`、`NOTICE`、`Cargo.toml`（根上只许加成员）、`Cargo.lock`（只许因新 crate 变）、`.work/gsd/phases/rust-core/waves/B3-1b-REPORT.md` 和 `B3-1b-review.log`。其它一律不动。
- 命令被移到后台就轮询等它结束，**不许在后台作业还没结束时收工**。
- 构建之前跑一次 `Scripts/machine-guard.sh` 并记录输出。并行度 6 以内。不用 `caffeinate`。一次只跑一个重活。
- 不跑 Swift 的构建和测试，不打开任何图形程序，不运行 `darktable`，不下载安装任何软件。不读、不打印任何凭据文件。机器上别人的 omp 会话和重活，不碰。
- `.work/` 下以前各波留下的未跟踪文件不碰也不提交。
- 新文件带 SPDX 头（`// SPDX-License-Identifier: GPL-3.0-or-later`）。
- 数字不编。哪一项没做成，写没做成和卡在哪一步。上游那块拿不准的，写清楚你的读法和依据。总墙钟不超过 6 小时（检查点两小时包含在内）。

## 交付

一个提交；`waves/B3-1b-REPORT.md`（对照架的结构、原样取了哪些行、行为替身表、转写做了哪些没做哪些、每块瓦片的门限和最大绝对差、那个不稳定测试的原因和修法、验收清单每条的命令与输出）；`waves/B3-1b-review.log`。stdout 最后一条消息一次性完整输出：结论、新增测试清单、没做的、commit 哈希。
