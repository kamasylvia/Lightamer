# 执行 lane B3-2a（omp）：转写 temperature（白平衡）

## 背景

B3 这一波转写 darktable 的 raw 头段四个模块。对照架 `crates/lightamer-oracle` 已经搭好（B3-1b），`rawprepare` 和 `hotpixels` 已经转写并逐像素对过上游。你这一段照同一条路转写第三个模块 `temperature`。它比前两个大：处理本身只是逐像素乘系数，难在**系数怎么来**——机内白平衡、从色温和色调算系数，后者要用 lcms2。

工作目录 `/Volumes/UNITEK/Documents/Development/Lightamer`，HEAD 是上一段（B3-1c）的提交，先亲核（工作树里 `waves/VERIFY.md` 有塔台没提交的改动，不是你的，别碰）。全程中文，代码注释和标识符英文，commit message 英文。

**先读这两个技能文件并照做**：`/Users/kamasylvia/.agents/skills/ponytail/SKILL.md`、`/Users/kamasylvia/.agents/skills/rust-best-practices/SKILL.md`。项目自己的优先级：公开的项写 `///`，其余注释只写为什么；错误类型手写（不引 thiserror / anyhow）；不跟「一个测试只断言一件事」和类型状态；没人要的代码不写。

## 用户已定的几条（不许动）

- 阶段 0 只保证解 A7R5（A-27）。**取样只用** `~/Library/Application Support/Lightamer/TestRAW/7RM5-LosslessCompressedLarge.ARW`（CC0 样张）。样张不在就跳过并写明。**不碰用户的照片库** `/Volumes/UNITEK/Cloud Drive/QSync/Medias/Photos/Workspace`（不读、不列目录）；`/Volumes/UNITEK/Cloud Drive/` 下面一个字都不写。
- 机内白平衡取自解码给的系数；机内色温不需要（索尼的厂商备注不解析）。
- darktable 的上游基线钉在 `release-5.7.0`。参考源码只读，在 `/Volumes/UNITEK/Documents/Development/Lightamer-rust-spike/refs/dt-master`，用 `git show release-5.7.0:<路径>` 读。不改它、不构建它、不运行 darktable。**不读** `/Volumes/UNITEK/Documents/Development/darktable` 和 `darktamer` 这两个工作树。
- 模块自动发现、自动注册，不设中央清单。
- 新增的依赖必须过许可证检查（`Scripts/licenses-allow.txt`）。lcms2 是 MIT，A1 的审计表里已经登记过。**本机已经装了 lcms2 2.19**（Homebrew，`/opt/homebrew/include/lcms2.h`），不用装任何东西。
- GPL 同许可复制纪律：转写来的代码保留 darktable 的版权声明，SPDX 用 `GPL-3.0-or-later`，加一行 `Modified for Lightamer: <日期> <改了什么>`；`NOTICE` 同步。

## 先读

- `crates/lightamer-oracle/README.md` 和上一段的 `waves/B3-1c-REPORT.md`：第三个模块怎么加进对照架（含 `dt_dev_prepare_piece_cfa` 的取法、渲染种类）。
- `crates/lightamer-iop-raw/src/modules/hotpixels/mod.rs` 和它的对照测试：逐像素查 CFA 的写法是这一段的样板。
- `crates/lightamer-iop-traits/src/{module,state,image,kind,lib}.rs`：`IopModule` 现在的签名——`commit(&self, params, image, state: &mut PipeState, kind: PipeKind)`（上一段刚加了渲染种类 `PipeKind`：完整分辨率 / 导出 / 预览 / 缩略图）、`process(data, input, output, rin, rout, state)`；`PipeState`（里面的 `temperature` 子状态现在只有 `enabled` 和 `coeffs`）；`RawFacts`（机内白平衡 `wb`、颜色矩阵 `xyz_to_cam_d65` / `cam_to_xyz_d65`、`four_bayer`）。
- `crates/xtask/src/layers.rs` 的分层规则：`lightamer-iop-color` 和 `lightamer-color` 同是 L1，**同层之间现在不许互相依赖**（例外表里只有 meta → decode）。
- 上游 `src/iop/temperature.c`（2250 行，大头是图形界面）：参数类型（29–45 行：四个系数 `red / green / blue / various`，范围 0–8，加一个 `preset` 标签：−1 未知、0 机内、1 取色、2 用户、3 D65、4 D65 晚校正）；`_publish_chroma`（515）、`process`（532）、`commit_params`（687）；系数怎么来：`_find_coeffs`（1448）、`_calculate_bogus_daylight_wb`（1382）、`_prepare_matrices`（1412）；色温和系数互化：`_xyz2mul`（432）、`_temp2mul`（453）、`_mul2xyz`（472）、`_mul2temp`（496）、`_temperature_tint_to_XYZ`（396）、`_XYZ_to_temperature`（406），其中用到 lcms2 的 `cmsWhitePointFromTemp`（329 行）。还有 `src/common/colorspaces.c` 里被它们调的矩阵函数。

## 我的读法（以源码为准，不一致时以源码为准并在报告里写明）

- **处理**：三个分支——X-Trans 马赛克、拜耳马赛克、非马赛克（四个通道）——都是逐像素乘对应颜色的系数。处理完照上游写链上状态：`temperature.enabled / coeffs`，四路最大值各乘上系数，并记下「是不是晚校正」（下游的 highlights 和以后的 colorin 要读）。
- **提交**：数据就是四个系数加标签。不是 RAW 的图像上游不允许启用——等价于直通，沿用前两个模块的约定。
- **缺省系数（机内白平衡）**照 `_find_coeffs` 的顺序：图像自己带的系数正常且不为零就用它；否则用相机矩阵算一个「冒牌日光」；否则查机身的白平衡预设；最后兜底 `2.0 / 1.0 / 1.5 / 1.0`。
- **提交里读的是建链时刻的快照**，和上游一样。

## 要做的

**1. lcms2 的落点。** 新依赖 `lcms2` 加在 **`lightamer-color`**（色彩管理 crate，计划卡片指定的落点），里面只放一个薄封装：色温 → CIE xy 白点（对应上游调的那个函数）。`lightamer-iop-color` 用它。为此在分层规则的例外表里加一条同层顺序「`lightamer-color` 在前，`lightamer-iop-color` 在后」，文档注释里写明理由（以后的 `colorin / colorout` 一定要用到色彩管理 crate）。`Cargo.lock` 只许因这两条依赖变（`lcms2` 和 `lcms2-sys`），不许有别的包。

**2. 对照架加第三个模块**（照 README）。额外要做的：

- 上游的 `temperature.c` 里非图形界面的函数原样取；它include 的 `common/colorspaces_inline_conversions.h`（纯数学的内联函数）和 `external/cie_colorimetric_tables.c`（纯数据）原样取；`common/colorspaces.c` 里被调到的矩阵函数原样取。有逻辑的一律原样，不许替身重写。
- 对照库链接系统的 lcms2，Rust 这边也是同一个库，两边逐位一致才有意义。
- 机身的白平衡预设表（`common/wb_presets.h`，图形界面的菜单数据）不取：替身让「预设数」为 0，列进行为替身表。
- Rust 入口：`run_temperature`（参数：四个系数加标签）和三模块链的入口（`rawprepare` → `temperature`，上游的链序里 temperature 在 hotpixels 之前）。另给测试用的入口：上游从色温和色调算出 xy 和算出系数的函数，各暴露一个。

**3. 转写 `temperature`**（`crates/lightamer-iop-color/src/modules/temperature/`）：

- 参数描述用 `ParamsDesc`：四个浮点、一个整数标签，含义照上游。校验在 `commit` 里，错误类型手写。
- `commit` 和 `process` 按上面「我的读法」。浮点一步一步算，不许合并或换序；逐像素的 CFA 颜色按区域偏移查 `PipeState` 里的图案；逐行用 rayon。
- 链上状态：`PipeState` 的 `temperature` 子状态加一个「晚校正」布尔（建链期写，下游读）。
- **缺省系数**：参数里没给时按 `_find_coeffs` 的顺序算。相机预设那一步不做（要预设表和机身型号字符串，A-27 范围外），直接落到兜底值，报告里记一笔。
- **公开的纯函数**（以后设置面板要用，这一段只要在、有测试）：机内白平衡 → 系数；色温、色调 → xy 白点；色温、色调 → 系数；系数 → 色温、色调。照上游的公式转写，lcms2 只经 `lightamer-color` 那个薄封装。
- 不做：图形界面；取色预设；光谱算色温的那几个函数（只给界面显示用，系数用不到）；OpenCL。

**4. 测试**（`crates/lightamer-iop-color/tests/`）：

- 三模块链对上游（真瓦片 4 块：居中、左上角、最亮、最暗）：缺省（机内系数）、用户系数（四个值各不同）、D65 系数、强度为一（逐位不变）。每块过门，最大绝对差写进报告（逐像素乘法，应该逐位相等或只差最后一位）。
- 链上状态：发布出去的系数、乘过系数的四路最大值、晚校正标志，两边相等。
- 合成：拜耳、X-Trans、四通道 RGB 输入、非 RAW 直通、`four_bayer`。
- **色温换算**：色温 2000 K 到 12000 K 每 500 K 一档，色调取 0.135 / 0.5 / 1.0 / 1.5 / 2.326，我们的 xy 对上游的 xy，最大绝对差 < 1e-4（计划卡片上的那条）；系数的换算同样对一遍，写进报告。

**5. 演示脚本**：如果哪个演示或 bench 用了 `temperature` 的假参数，照 B3-1b 报告第十节的办法改成真参数。

## 每一步的内存约束

- 测试只用瓦片，取瓦片用 `pipe_input(region)`，不要先转整帧（整帧 244 MB，解码峰值约 900 MB）。同一个测试二进制里不许并发加载多张。
- 转写的 `process` 除了 rayon 的行并行之外不额外分配；提交数据是固定大小的栈数据。矩阵和色温换算都是固定大小的栈上数组。

## 验收清单（命令和输出写进报告）

- `cargo test --workspace --locked --no-fail-fast -j6` 绿、零失败；测试总数不少于上一段的总数加上你新增的（逐个列出）。前两个模块的对照测试一个不改、照旧通过。
- 六条不崩溃 lint（`CARGO_INCREMENTAL=0`，`-D warnings`）和文档零警告；`cargo fmt --all --check`；`cargo xtask layers`、`check-order-sync`、`check-no-iop-names`、`Scripts/check-licenses.sh` 通过。
- 五个演示脚本都退出 0（`Scripts/rust-session-demo.sh`、`rust-history-demo.sh`、`rust-render-demo.sh`、`rust-decode-demo.sh`、`rust-stream-demo.sh`）。机器上可能有别人自己的重活，负载高时计时步骤会报「测不准」，等它重试，不要绕。
- `LIGHTAMER_DT_REF=<参考克隆> tools/extract.sh temperature --check` 逐字节一致；前两个模块的 `--check` 照旧一致。
- 全部瓦片过门；色温换算的最大绝对差 < 1e-4。
- `lightamer-iop-color::lookup_implemented("temperature")` 查得到，描述表和 registry 里都有。
- `git show --name-only HEAD` 只含「纪律」里允许的路径。

## 产物先落盘，再收尾

代码第一次全绿就提交；之后每完成一小块提交一次，最后 squash 成一个（Conventional Commits，subject 用 `feat(rust-core): …`，body 写 what + why，带 `refs #32`）。绿之前离开要留带路径的 stash 说明。

**退出顺序**：先填完报告 `waves/B3-2a-REPORT.md` → 再起一个 `omp -p` 实例做只读自审（隔离：只读产物，不读你的过程；第一行写结论头 `PASS / N error + N minor`；发现回写 `waves/B3-2a-review.log`）→ 有发现就修，修法记进报告的一节「复审」→ 把报告和复审日志并进那一个提交 → 删掉临时文件 → 退出。复审日志一个字不改。自审的任务书不要放进提交。

## 纪律

- **只允许新增或修改这些路径**：`crates/lightamer-oracle/`、`crates/lightamer-iop-color/`、`crates/lightamer-color/`、`crates/lightamer-iop-traits/`（只许加晚校正那一个字段）、`crates/lightamer-pipeline/` 和 `crates/lightamer-engine/`（只有在必须跟着签名改的时候）、`crates/xtask/src/layers.rs`（只许加那一条同层顺序）、`crates/lightamer-testkit/`、`apps/lightamer-cli/` 和 `Scripts/rust-*-demo.sh`（演示和 bench 里跟着改参数）、`docs/PIPELINE.md`、`docs/LICENSE-AUDIT.md`、`NOTICE`、`crates/README.md`、`Cargo.lock`（只许因 `lcms2` 变）、`.work/gsd/phases/rust-core/waves/B3-2a-REPORT.md` 和 `B3-2a-review.log`。其它一律不动。
- 命令被移到后台就轮询等它结束，**不许在后台作业还没结束时收工**。
- 构建之前跑一次 `Scripts/machine-guard.sh` 并记录输出。并行度 6 以内。不用 `caffeinate`。一次只跑一个重活。
- 不跑 Swift 的构建和测试，不打开任何图形程序，不运行 `darktable`，不下载安装任何软件。不读、不打印任何凭据文件。机器上别人的 omp 会话和重活，不碰。
- `.work/` 下以前各波留下的未跟踪文件不碰也不提交。
- 新文件带 SPDX 头（`// SPDX-License-Identifier: GPL-3.0-or-later`）。
- 数字不编。哪一项没做成，写没做成和卡在哪一步。上游那块拿不准的，写清楚你的读法和依据。总墙钟不超过 5 小时。

## 交付

一个提交；`waves/B3-2a-REPORT.md`（对照架加了什么、原样取了哪些行、缺省系数四步各做了没有、每块瓦片的门限和最大绝对差、色温换算的差、验收清单每条的命令与输出）；`waves/B3-2a-review.log`。stdout 最后一条消息一次性完整输出：结论、新增测试清单、没做的、commit 哈希。
