# 执行 lane B3-0a（omp）：RAW 头段的管线准备

## 背景

B3 这一波转写 darktable 的 raw 头段四个模块（`rawprepare` / `hotpixels` / `highlights` 在 `lightamer-iop-raw`，`temperature` 在 `lightamer-iop-color`）。转写之前，管线得先能接住 RAW：现在的管线只认一种像素格式，不知道 RAW 的黑位、白点、白平衡这些事实，也没有「哪些模块已经实现」的表。你这一段只做**准备**，不转写任何模块（后面几段做）。

工作目录 `/Volumes/UNITEK/Documents/Development/Lightamer`，HEAD = `cf1c82a3`（先亲核）。全程中文，代码注释和标识符英文，commit message 英文。

**先读这两个技能文件并照做**：`/Users/kamasylvia/.agents/skills/ponytail/SKILL.md`、`/Users/kamasylvia/.agents/skills/rust-best-practices/SKILL.md`。项目自己的优先级：公开的项写 `///`，其余注释只写为什么；错误类型手写（不引 thiserror / anyhow）；不跟「一个测试只断言一件事」和类型状态；没人要的代码不写。

## 用户已定的几条（不许动）

- 阶段 0 只保证解 A7R5（A-27）。佳能 CR3 不支持、不做回落。
- 取样只用 CC0 样张，在 `~/Library/Application Support/Lightamer/TestRAW/`。**不碰用户的照片库** `/Volumes/UNITEK/Cloud Drive/QSync/Medias/Photos/Workspace`（不读、不列目录）；`/Volumes/UNITEK/Cloud Drive/` 下面一个字都不写。这一段用不到样张，用合成数据。
- darktable 的上游基线钉在 `release-5.7.0`。参考源码只读，在 `/Volumes/UNITEK/Documents/Development/Lightamer-rust-spike/refs/dt-master`，用 `git show release-5.7.0:<路径>` 读。不改它、不构建它、不运行 darktable。**不读** `/Volumes/UNITEK/Documents/Development/darktable` 和 `darktamer` 这两个工作树。
- 模块自动发现、自动注册，不设中央清单。

## 先读

- `docs/PIPELINE.md`、`crates/README.md`。
- `crates/lightamer-raster/src/{format,frame}.rs`；`crates/lightamer-iop-traits/src/{module,image,lib}.rs`。
- `crates/lightamer-pipeline/src/{render,stream,spill,budgeted,cache,kinds}.rs`。
- `crates/lightamer-engine/src/render.rs`（`execution_order` 约 748 行、`sort_chain` 约 818 行、渲染作业约 944 行起）。
- `crates/lightamer-registry/src/lib.rs`；`lightamer-iop-raw` 的 `build.rs`、`src/lib.rs` 和一个模块桩 `src/modules/rawprepare/mod.rs`。
- `crates/xtask/src/layers.rs`（分层规则：L0 = geom / raster / color-math / iop-traits / sysmem；L1 = 四个 iop 域 crate + meta / color / blend / decode / scenes，**同层之间不许互相依赖**，唯一的例外是 meta → decode；L2 = registry / history / pipeline；L4 = engine）。

## 现在的起点

- **像素格式**：`PixelFormat` 只有 `RgbaF32Premul`（16 字节/像素）可以分配，`RgbaU8` / `RgbaU16` 只是登记。RAW 马赛克是**单通道**，解码出来是 `u16` 或 `f32`，进管线要变成单通道 `f32`。
- **按 16 字节算字节的地方**：`git grep -n -E 'RgbaF32Premul|OUTPUT_BPP|16 \* |bytes_per_pixel'` 在这些文件里有命中（括号内是命中数，不全是写死的假设，逐处看）：`lightamer-engine/src/render.rs`（6）、`lightamer-pipeline/src/budgeted.rs`（5）、`cache.rs`（1）、`kinds.rs`（2）、`render.rs`（9）、`spill.rs`（8）、`stream.rs`（15）、`lightamer-raster/src/format.rs`（8）、`frame.rs`（13）。
- **图像事实**：`ImageInfo` 只有 `width` / `height` / `input_space` 三个字段（`Copy + Eq + Hash`）。`ColorSpace` 已有 `Raw`。
- **模块接口**：`IopModule` 的 `process(data, input, output, rin, rout)`；`commit(&self, params, image) -> CommitData`；这一段**不改这两个签名**（上游事实怎么在模块之间传递，留给转写 rawprepare 的那一段按实际需要做）。
- **模块表**：四个域 crate 的 `build.rs` 扫 `src/modules/*/mod.rs` 生成 `MODULES`（只有描述）。`lightamer_registry::all_descs()` 把四个域串起来；`raw_chain()` / `jpg_chain()` 两个排序链都在。**没有**「已实现的模块」的表。引擎的 `ModuleSource` 只是一个查表特征（`lookup(id) -> Option<SharedModule>`），目前只有测试里有一份手写的。
- **排序**：`execution_order` 一律用 `jpg_chain()`（751 行）。
- **流式**：引擎对完整分辨率和导出两种实例，先 `probe` 探尺寸，放不下转流式；预览和缩略图不探、不转流式。默认的 `probe` 会解码一次。
- 解码 crate 的 `RawMetadata` 已经带着黑位（`black_level`、`black_separate`）、白点（`white_level`）、机内白平衡（`white_balance`）、颜色矩阵（`color_matrix_xyz_to_cam`、`color_matrix_cam_to_xyz`）、CFA 图案（`cfa_w/h`、`cfa_pattern`、`is_xtrans`）。这一段**不动解码 crate**，下一段把它的数据填进来。

上游四个模块读了 `image` 的哪些字段（塔台已经数过，`release-5.7.0`）：rawprepare 读 `raw_white_point`、`raw_black_level_separate[0..3]`、`flags`、`crop_x/y`、`p_width/p_height`；hotpixels 读 `flags`（7 处）；temperature 读 `wb_coeffs`、`flags`、`load_status`、`camera_maker/model/makermodel`、`camera_missing_sample`、`filename`；highlights 读 `linear_response_limit`。

## 要做的

**1. 单通道浮点格式。** `PixelFormat` 加一个可以分配的单通道 `f32` 格式（4 字节/像素），`Frame` / `Plane` 能按它分配和读写。

**2. 字节数一律从格式来。** 上面列的每一处都过一遍：只要是「按每像素 16 字节算字节」的假设，就改成从格式的每像素字节数取。预算、占用检查、缓存记账、流式规划和落盘（`StreamSink` 的输出平面）都要对。做完之后 `format.rs` 以外不许再有写死的 16。流式规划用的 `STREAM_BYTES_PER_PIXEL = 150` 是 RGBA 链的工作集实测值，单通道链先沿用（偏保守，只会把块切小，安全），在它的注释里写明。

**3. 模块声明输出格式。** `IopModule` 加一个带默认实现的方法：输出格式 = 输入格式（默认）。管线按它给每个节点分配输出平面。RGBA 专用的读取入口碰到单通道平面时，必须是分了类型的失败（或者编译期就不可达），不许静默读出垃圾。

**4. `ImageInfo` 带 RAW 事实。** 加一个可选的 `RawFacts`（纯数据），字段按上面那份清单来，至少覆盖四个模块读到的东西：四路黑位、白点、机内白平衡四个系数、相机颜色矩阵（写清参考白和方向）、CFA 图案（2×2 拜耳 / X-Trans 6×6 / 无）、裁切和原始尺寸、`linear_response_limit`，以及那几处 `flags`——逐个 grep 上游这几处用的是哪个标志、什么意思，变成有名字的布尔事实，**不许照搬位标志**。字符串类的事实（机身型号、文件名）这一段先不加，`ImageInfo` 保持 `Copy`；在报告里写清哪些留下了、哪个模块要。DNG 的增益图（`dng_gain_maps`）不做（A-27：只保证 A7R5，ARW 没有），报告里记一笔。
`ImageInfo` 参与链式缓存键，所以事实变了键必须变、事实没变键必须不变；浮点字段要做到这一点（比如按位比较和散列），并写测试钉住。现有调用点（`ImageInfo::new` 等）改动越小越好。

**5. 已实现模块的表。** 四个域 crate 的 `build.rs` 已经在扫 `src/modules/*/mod.rs`：再生成一张「已实现」的表（某个模块目录给出了构造函数才算实现，只有描述的桩不算）。每个域 crate 对外给一个按 id 查已实现模块的入口；`lightamer_registry` 把四个域串起来给一个总入口。不许出现手写的中央清单。测试：每个已实现的模块都能经 registry 查到，并且也在 `all_descs()` 里。

**6. 按 RAW 与非 RAW 排序。** 引擎拿到的是 RAW（马赛克）时按 `raw_chain()` 排，否则照旧 `jpg_chain()`。是不是 RAW 要在**探完尺寸之后**才知道（整帧那条路是取到像素之后），所以排序挪到作业里、探完再做；**不许为了知道是不是 RAW 先解码一次**。流式那条路也要先排好再规划。现有非 RAW 的行为逐值不变（旧测试一个不改、照旧通过）。

## 每一步的内存约束（写代码时逐条对）

- 一帧单通道 `f32` 的 A7R5 马赛克（9568×6376）= 244 MB；链上每个节点的输出平面各 244 MB，都从预算里领。预算、驱逐、占用检查按每个平面**自己的格式**记账。
- 完整分辨率和导出的上限、预览的上限、缩略图的上限都是**字节**预算：确认它们是按帧的实际字节数算的，然后在 `docs/PIPELINE.md` 的上限表下面补一行单通道的数（这台 16 GB 的机器）。
- 预览实例超预算时照旧是分了类型的拒绝（预览不转流式），行为不变。
- 流式：每块的字节按格式算；落盘输出的大小按格式算；拒绝发生在分配之前。

## 验收清单（命令和输出写进报告）

- `cargo test --workspace --locked --no-fail-fast -j6` 绿、零失败；测试总数不少于 676 加上你新增的（逐个列出新增的测试名和它钉的是什么）。
- 六条不崩溃 lint（`CARGO_INCREMENTAL=0`，`-D warnings`）和文档零警告；`cargo xtask layers`、`check-order-sync`、`check-no-iop-names`、`Scripts/check-licenses.sh` 通过。
- 五个演示脚本（`Scripts/rust-session-demo.sh`、`rust-history-demo.sh`、`rust-render-demo.sh`、`rust-decode-demo.sh`、`rust-stream-demo.sh`）都退出 0。机器上可能有别人自己的重活，负载高时计时步骤会报「测不准」，等它重试，不要绕。
- `git grep -n -E 'OUTPUT_BPP|16 \* ' -- crates apps/lightamer-cli` 在 `format.rs` 以外零命中。
- 单通道的整条链：合成一帧 A7R5 大小的单通道数据过一个空链和一个只改值的测试模块，结果逐字节正确；用 `/usr/bin/time -l` 量**峰值常驻**和**峰值占用**两个数，写进报告。
- 单通道的流式：一帧超过整帧上限的单通道图经流式跑完，和分块直接算的结果逐字节一致；`StreamSink` 落盘文件的大小 = 宽×高×4。
- RAW 排序：给 RAW 事实时顺序 = `raw_chain()`，不给时 = 旧顺序；探尺寸之后才排序（计数来源断言整帧只取一次、探恰好一次）。
- `git show --name-only HEAD` 只含「纪律」里允许的路径；`Cargo.lock` 不变。

## 产物先落盘，再收尾

代码第一次全绿就提交；之后每完成一小块提交一次，最后 squash 成一个（Conventional Commits，subject 用 `feat(rust-core): …`，body 写 what + why，带 `refs #32`）。绿之前离开要留带路径的 stash 说明。

**退出顺序**：先填完报告 `waves/B3-0a-REPORT.md` → 再起一个 `omp -p` 实例做只读自审（隔离：只读产物，不读你的过程；结论头 `PASS / N error + N minor`；发现回写 `waves/B3-0a-review.log`）→ 有发现就修 → 把报告和复审日志并进那一个提交 → 删掉临时文件 → 退出。复审日志里要有结论头。

## 纪律

- **只允许新增或修改这些路径**：`crates/lightamer-raster/`、`crates/lightamer-iop-traits/`、`crates/lightamer-pipeline/`、`crates/lightamer-registry/`、`crates/lightamer-engine/`、四个 `crates/lightamer-iop-*/`（只许 `build.rs` 和 `src/lib.rs` 里跟表有关的部分）、`crates/lightamer-testkit/`（只有在必须加单通道测试工具时）、`apps/lightamer-cli/`（只许跟着签名改）、`docs/PIPELINE.md`、`crates/README.md`、`.work/gsd/phases/rust-core/waves/B3-0a-REPORT.md` 和 `B3-0a-review.log`。其它一律不动。不新增依赖，`Cargo.lock` 不许变。
- 命令被移到后台就轮询等它结束，**不许在后台作业还没结束时收工**。
- 构建之前跑一次 `Scripts/machine-guard.sh` 并记录输出。并行度 6 以内。不用 `caffeinate`。一次只跑一个重活。
- 不跑 Swift 的构建和测试，不打开任何图形程序，不运行 `darktable`，不下载安装任何软件。不读、不打印任何凭据文件。机器上别人的 omp 会话和重活（现在有两个别人的 `darktable-cli` 在跑），不碰。
- `.work/` 下以前各波留下的未跟踪文件不碰也不提交。
- 新文件带 SPDX 头（`// SPDX-License-Identifier: GPL-3.0-or-later`）。
- 数字不编。哪一项没做成，写没做成和卡在哪一步。上游事实那块拿不准的，写清楚你的读法和依据。总墙钟不超过 4 小时。

## 交付

一个提交；`waves/B3-0a-REPORT.md`（做了什么、每处改动的理由、RAW 事实的字段表和每个布尔事实对应上游哪个标志、留下了什么没做、内存两个数、验收清单每条的命令与输出）；`waves/B3-0a-review.log`。stdout 最后一条消息一次性完整输出：结论、新增测试清单、没做的、commit 哈希。
