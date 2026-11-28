# 执行 lane B3-0b（omp）：解码接入管线

## 背景

B3 这一波转写 darktable 的 raw 头段四个模块。上一段（B3-0a，提交 `84fd878c`）把管线准备好了：有了单通道浮点格式、`ImageInfo` 能带 RAW 事实、引擎按 RAW 与否排序、有「已实现模块」的表。现在缺的是**解码到管线之间的那条线**：解码 crate 的数据还没有填进 `ImageInfo`，引擎也没有一个真的 RAW 输入来源（现在只有演示和测试里的合成数据）。你这一段把这条线接通。仍然不转写任何模块。

工作目录 `/Volumes/UNITEK/Documents/Development/Lightamer`，HEAD = `84fd878c`（先亲核）。全程中文，代码注释和标识符英文，commit message 英文。

**先读这两个技能文件并照做**：`/Users/kamasylvia/.agents/skills/ponytail/SKILL.md`、`/Users/kamasylvia/.agents/skills/rust-best-practices/SKILL.md`。项目自己的优先级：公开的项写 `///`，其余注释只写为什么；错误类型手写（不引 thiserror / anyhow）；不跟「一个测试只断言一件事」和类型状态；没人要的代码不写。

## 用户已定的几条（不许动）

- 阶段 0 只保证解 A7R5（A-27）。佳能 CR3 不支持、不做回落。**取样和验收只用两张索尼 ARW**：`7RM5-LosslessCompressedLarge.ARW` 和 `ColorChecker.ARW`，都在 `~/Library/Application Support/Lightamer/TestRAW/`（CC0 样张）。样张不在就跳过并写明。
- **不碰用户的照片库** `/Volumes/UNITEK/Cloud Drive/QSync/Medias/Photos/Workspace`（不读、不列目录）；`/Volumes/UNITEK/Cloud Drive/` 下面一个字都不写。
- darktable 的上游基线钉在 `release-5.7.0`。参考源码只读，在 `/Volumes/UNITEK/Documents/Development/Lightamer-rust-spike/refs/dt-master`，用 `git show release-5.7.0:<路径>` 读。不改它、不构建它、不运行 darktable。**不读** `/Volumes/UNITEK/Documents/Development/darktable` 和 `darktamer` 这两个工作树。

## 先读

- `docs/DECODE.md`、`docs/PIPELINE.md`。
- `.work/gsd/phases/rust-core/waves/B3-0a-REPORT.md`：上一段做了什么。重点看 §4 的 `RawFacts` 字段表（每个字段对应上游 `dt_image_t` 的哪个字段、谁消费）和 §9 的缺口。
- `crates/lightamer-iop-traits/src/{image,format}.rs`：`ImageInfo`（`with_format` / `with_raw` / `is_raw`）、`RawFacts`、线形的 `PixelFormat`。
- `crates/lightamer-decode/src/image.rs`（`RawImage::open / decode / metadata / mosaic`、`RawMetadata`、`Mosaic`）、`src/ffi.rs` 和 `csrc/`（很薄的 C 接口：`rs_open`、`rs_decode`、`rs_fill_info`、`rs_mosaic_hash` 等）。
- `crates/lightamer-engine/src/render.rs` 的 `InputSource` 特征（`fetch` / `probe` / `fetch_region`，`RenderInput` / `RenderFacts`）和 `probe` 上写明的契约；渲染作业里探尺寸、整帧取、流式取区域三条路。
- `crates/lightamer-decode/tests/parity.rs` 的 `sample_dir()`（样张怎么找）。
- 上游怎么把 rawspeed 的数据填进 `dt_image_t`：`git show release-5.7.0:src/imageio/imageio_rawspeed.cc`，再对 `src/common/image.c` 里对字段做的后处理（比如白平衡系数的归一化）。**填值的语义照它**，每填一个字段在代码注释里写上游出处（文件:行）。

## 现在的起点

- 解码 crate：`RawImage::open` 之后必须 `decode()`（像素和元数据一起解）才能 `metadata()` / `mosaic()`。没有「只解元数据」的入口。`RawMetadata` 已经有黑位（`black_level`、`black_separate`）、白点（`white_level`）、机内白平衡（`white_balance`）、颜色矩阵（`color_matrix_xyz_to_cam`、`color_matrix_cam_to_xyz`）、CFA（`cfa_w/h`、`cfa_pattern`、`is_xtrans`、`cfa_dcraw_filter`）、裁切（`crop`、`uncropped_width/height`）。
- `RawFacts` 的字段（上一段定的）：`black: [u32; 4]`、`white: u32`、`wb: [f32; 4]`、`xyz_to_cam_d65` / `cam_to_xyz_d65: Option<[f32; 9]>`、`cfa: CfaPattern`（`None` / `Bayer([CfaColor; 4])` / `XTrans([CfaColor; 36])`）、`crop_x / crop_y: i32`、`p_width / p_height: i32`、`linear_response_limit: f32`、五个布尔（`hdr` / `four_bayer` / `s_raw` / `monochrome` / `monochrome_bayer`）、`load_ok`、`camera_missing_sample`。浮点按位比较和散列，`ImageInfo` 整体是 `Copy`。
- 分层规则（`crates/xtask/src/layers.rs`）：`lightamer-decode` 是 L1，可以用 L0 的 `lightamer-iop-traits`、`lightamer-raster`、`lightamer-meta`；不能用 L1 的其它 crate 和更高的层。`apps/lightamer-cli` 不受限。`lightamer-testkit` 别的 crate 只能当测试依赖用。
- 现有的 A7R5 样张五行的采样摘要在 `.work/gsd/phases/rust-core/waves/A7a-REPORT.md` §5；解码的既有测试（`tests/parity.rs` 等）钉着 `u16` 马赛克的哈希。这些都不许变。
- 引擎的三条路：完整分辨率和导出先 `probe` 探尺寸（默认的 `probe` 会解码一次），放得下就整帧 `fetch`，放不下转流式、逐块 `fetch_region`；预览和缩略图不探。

## 要做的

**1. 只解元数据的入口。** 解码 crate 加一个不解像素就能拿到尺寸和 RAW 事实的入口（rawspeed 的元数据阶段不要像素；很薄的 C 接口里加对应的函数）。`RawMetadata` 里依赖像素才有的字段没有就留空，写明是哪些。量一下 A7R5 样张上它的耗时，和整帧解码的耗时（之前量的是每进程 63 毫秒）并排写进报告。

**2. 解码数据填进 `ImageInfo`，马赛克变成单通道浮点帧。** 解码 crate 对外给一个入口：一张已解码的 RAW →（单通道 `f32` 帧，带 `RawFacts` 的 `ImageInfo`，`input_space = Raw`）。`u16` 转 `f32` 是精确的；`f32` 马赛克原样。`RawFacts` 的每个字段从 `RawMetadata` 的哪里来、上游出处是哪一行，列一张表写进报告；`RawMetadata` 里没有、上游却会填的字段，逐个写明（能从 rawspeed 拿到的就加到 `RawMetadata`，拿不到的留默认并记一笔）。

**3. 真的 RAW 输入来源。** 实现引擎的 `InputSource`，放在 `apps/lightamer-cli`（以后界面那一波需要时再往上提，现在不新建 crate）：
- `probe`：**覆写**，只解元数据。不覆写的话整帧那条路会解码两次。
- `fetch`：整帧马赛克。
- `fetch_region`：一块区域。rawspeed 没有按区域解码，所以**一次请求里只解码一次像素**，之后每块从已经解好的马赛克里裁。默认实现是每取一块就整帧解码一次，不许落到它上面。
- 整帧那条路合计 = 探一次元数据 + 解码一次像素。用计数钉住（很薄的 C 接口里已经有 `rs_meta_parse_count`；像素解码的计数如果没有，加一个）。
- 不是 RAW 的文件（JPEG 等）在这条来源上是分了类型的失败，不做回落（普通图片的输入来源不在这一段）。

**4. 测试工具。** `lightamer-testkit` 加一个按样张文件名取「单通道帧 + `ImageInfo`」的小工具，给后面转写模块的测试用。只是第 2 条入口的一层薄包装，加样张目录的查找和「样张不在就跳过」。

**5. 走通一遍并量数。** A7R5 样张：探尺寸 → 整帧取 → 空链 → 输出和直接转换的结果逐字节一致。量三个数写进报告：探的耗时、整帧路的**峰值常驻**和**峰值占用**（`/usr/bin/time -l`），并写清峰值由哪几块内存构成。解码 crate 内部的 `u16` 马赛克、`mosaic()` 拷出来的那份、`f32` 帧，三者是不是同时活着——**中间拷贝越少越好**；如果 `mosaic()` 的那次拷贝躲不开，写明原因和它的代价。

## 每一步的内存约束（写代码时逐条对）

- A7R5（9568×6376）：`u16` 马赛克 122 MB，`f32` 帧 244 MB。转换时两者同时活着是下限；第三份拷贝要躲。
- 流式路：整张 `u16` 马赛克在整个请求期间留在来源里（rawspeed 必须整张解码，A-24：马赛克必须放得进内存），每块只在裁的时候转成 `f32`。请求结束就释放，不留跨请求的缓存（要留的话只留最近一张，并写明理由）。
- 预览实例：A7R5 的单通道帧 244 MB，在上限（这台 16 GB 的机器预览 9059 万像素）之内，整帧照常。更大的图超了上限照旧是分了类型的拒绝，行为不变。
- 探尺寸的路不分配像素。

## 验收清单（命令和输出写进报告）

- `cargo test --workspace --locked --no-fail-fast -j6` 绿、零失败；测试总数不少于 714 加上你新增的（逐个列出新增的测试名和它钉的是什么）。解码 crate 的既有测试一个不改、照旧通过；A7a 的五行采样摘要不变。
- 六条不崩溃 lint（`CARGO_INCREMENTAL=0`，`-D warnings`）和文档零警告；`cargo fmt --all --check`；`cargo xtask layers`、`check-order-sync`、`check-no-iop-names`、`Scripts/check-licenses.sh` 通过。
- 五个演示脚本都退出 0（`Scripts/rust-session-demo.sh`、`rust-history-demo.sh`、`rust-render-demo.sh`、`rust-decode-demo.sh`、`rust-stream-demo.sh`）。机器上可能有别人自己的重活，负载高时计时步骤会报「测不准」，等它重试，不要绕。
- 两张索尼 ARW 样张上：`ImageInfo` 的宽高、黑位、白点、白平衡四系数、颜色矩阵、CFA 图案，和解码 crate `metadata()` 给出的逐值相等（测试）；`ImageInfo::is_raw()` 为真，格式是单通道。
- 整帧路：元数据解析计数 +1、像素解码计数 +1（测试）；流式路多块：像素解码计数 +1、每块结果和整帧裁出来的逐字节一致（测试）。
- 探尺寸不分配像素（测试：探之后没有 `f32` 帧）。
- `git show --name-only HEAD` 只含「纪律」里允许的路径；`Cargo.lock` 不变。

## 产物先落盘，再收尾

代码第一次全绿就提交；之后每完成一小块提交一次，最后 squash 成一个（Conventional Commits，subject 用 `feat(rust-core): …`，body 写 what + why，带 `refs #32`）。绿之前离开要留带路径的 stash 说明。

**退出顺序**：先填完报告 `waves/B3-0b-REPORT.md` → 再起一个 `omp -p` 实例做只读自审（隔离：只读产物，不读你的过程；第一行写结论头 `PASS / N error + N minor`；发现回写 `waves/B3-0b-review.log`）→ 有发现就修 → 把报告和复审日志并进那一个提交 → 删掉临时文件（量数用的探针二进制、`/tmp` 下的日志）→ 退出。复审日志里要有结论头。

## 纪律

- **只允许新增或修改这些路径**：`crates/lightamer-decode/`、`crates/lightamer-testkit/`、`apps/lightamer-cli/`、`crates/lightamer-engine/`（只有在必须补一道缝的时候，改了要写明为什么）、`docs/DECODE.md`、`docs/PIPELINE.md`（只许跟着补一两句）、`Scripts/rust-decode-demo.sh`（可选）、`.work/gsd/phases/rust-core/waves/B3-0b-REPORT.md` 和 `B3-0b-review.log`。其它一律不动。不新增依赖，`Cargo.lock` 不许变。
- 命令被移到后台就轮询等它结束，**不许在后台作业还没结束时收工**。
- 构建之前跑一次 `Scripts/machine-guard.sh` 并记录输出。并行度 6 以内。不用 `caffeinate`。一次只跑一个重活。
- 不跑 Swift 的构建和测试，不打开任何图形程序，不运行 `darktable`，不下载安装任何软件。不读、不打印任何凭据文件。机器上别人的 omp 会话和重活，不碰。
- `.work/` 下以前各波留下的未跟踪文件不碰也不提交。
- 新文件带 SPDX 头（`// SPDX-License-Identifier: GPL-3.0-or-later`）。很薄的 C 接口里新加的函数跟既有函数同一种风格和同一种错误处理。
- 数字不编。哪一项没做成，写没做成和卡在哪一步。上游填值那块拿不准的，写清楚你的读法和依据。总墙钟不超过 4 小时。

## 交付

一个提交；`waves/B3-0b-REPORT.md`（做了什么、`RawFacts` 每个字段的来源表、三个数和峰值的构成、留下了什么没做、验收清单每条的命令与输出）；`waves/B3-0b-review.log`。stdout 最后一条消息一次性完整输出：结论、新增测试清单、没做的、commit 哈希。
