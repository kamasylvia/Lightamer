# B3-0a 执行报告：RAW 头段的管线准备

- 工作目录 `/Volumes/UNITEK/Documents/Development/Lightamer`，起始 HEAD `cf1c82a3`（已亲核）。
- 技能：`ponytail`（full）+ `rust-best-practices`（本书第 1/2/4/5/8 章取舍见下）。
- 上游基线 `release-5.7.0`，只读 `Lightamer-rust-spike/refs/dt-master`，`git show` 读四模块与 `image.h`。
- 未用样张（合成数据）；未碰照片库；未读 darktable/darktamer 工作树。

## 0. 取舍（ Ponytail / Rust 实践）

- 不引 thiserror/anyhow：错误类型全部手写（`RenderError`/`RasterError`/`PipeError` 既有族 + 新分支走既有变体）。
- 公开项 `///`，其余注释只写为什么；`TODO` 零新增。
- 不跟「一测试一断言」（既有 `every_key_dimension_flips_the_key` 风格：按维度列断言）与类型状态（`process` 签名冻结，编译期不可达做不到，全部走分类型运行时失败）。
- 没人要的不写：`chain_keys` 旧签名保留为委派（见 §4）、`StreamSink::new` 保留为 RGBA 委派（见 §2）、`execution_order` 保留为委派（见 §6）——三处都是旧测试直调的签名，改签名就得改旧测试；委派 3 行 + 文档，无行为分叉。
- 机械改旧测试的行（不断言改动）：13 处 `chain_keys(` 取键调用随新签名加 `&image`（§4 强制：键算法变了，peek 旧键必空），4 处 `16 * ` 改写顺序（验收 grep 强制，值不变）。另有测试脚手架改动（非测试函数）：`CountingInput` 加格式/事实字段（默认 RGBA/Rgb/None，与旧构造逐值同）+ `fetch/fetch_region/probe` 经 `self.facts()`（默认分支恒等）、`image.rs` 测试 `use` 加名、`PIPELINE.md` 的 ImageInfo 行。除此之外旧 `#[test]` 函数体逐字节未动。
- 内存：零新增堆分配（`RawFacts` 纯栈数据，`Copy`）；`u64` 尺寸核算沿用既有 checked 风格；`usize::from(u32)` 不存在（标准库无此实现），通道数进 `usize` 数学一律 `try_from` + 分类型错误。

## 1. 单通道浮点格式（任务 1）

- `lightamer-raster/src/format.rs`：`PixelFormat::MonoF32`（4 字节/像素，可分配）+ `channel_count()`（RGBA 族 4，mono 1，`u32`）。
- `lightamer-raster/src/frame.rs`：删 `WORKING_CHANNELS` 常量；`alloc`/`from_parts`/`view`/`view_mut`/`FrameView`/`FrameViewMut` 按 `format.channel_count()` 算；`copy_from` 本来就比格式，跨格式拒绝不变。
- RGBA 行为逐位不变（旧测试未动，全过）。

## 2. 字节数一律从格式来（任务 2）

逐处清单（`git grep` 命中全过一遍）：

| 位置 | 原假设 | 改法 |
|---|---|---|
| `pipeline/render.rs: plane_bytes/extent_bytes` | ×`RgbaF32Premul.bpp` | 加 `bpp` 参数，调用点传节点输出格式的 bpp |
| `pipeline/render.rs: alloc_room/stream_alloc` | 分配恒 RGBA | 加 `format` 参数；预算扣费经 `alloc_shared` 本来就按格式算 |
| `pipeline/render.rs: check_footprints` | 全按 16 算 | 按链逐节点穿格式（`output_format`  threading），每平面按自己格式算 |
| `pipeline/render.rs: copy_good_part` | `ox4/good4 × 4` | 按 scratch 格式的通道数算（`ox_lanes/good_lanes`） |
| `pipeline/render.rs: render` 主循环 | 无格式概念 | 穿 `in_wire/out_wire`（命中缓存也推进）；缓存命中加格式比对，格式不对按几何不对同例重算 |
| `pipeline/stream.rs: stage/crop/stride` | `×4` 四处 | 按 scratch/结果帧的通道数算 |
| `pipeline/stream.rs: render_stream_from` | 无格式概念 | 从 `req.image.format` 起穿；中途变格式 → 新 `StreamRefusal::FormatChange`，分配前拒绝 |
| `pipeline/spill.rs: OUTPUT_BPP` | 常量 16 | 删；`StreamSink` 持 `format`，`new_with_format` 新入口（`new` 保留为 RGBA 委派）；`push` 加 piece 格式比对 |
| `engine/render.rs: crop_region` | 分配恒 RGBA | 用 `whole.format()` |
| `engine/render.rs: probe 尺寸检查` | `w*h*16` | `w*h*image.format.bpp` |
| `engine/render.rs: RenderedImage::byte_len` | `w*h*16` | 实际字节（内存向量长×4 / 映射文件长），RGBA 值不变 |
| `pipeline/budgeted.rs` | 无假设（本来就 `format.bytes_per_pixel()`） | 未动 |
| `STREAM_BYTES_PER_PIXEL = 150` | RGBA 链工作集实测 | 沿用 + 注释写明单通道偏保守（只切小块，安全） |

- 验收：`git grep -n -E 'OUTPUT_BPP|16 \* ' -- crates apps/lightamer-cli` 零命中（`format.rs` 的 `16` 是定义本身，不在模式内——模式只查 `16 * ` 乘法与 `OUTPUT_BPP`）。
- `docs/PIPELINE.md`：上限表下补单通道行（16 GiB 机：Full/Export 各 310,042,951 像素；A7R5 一帧 244,022,272 B 占 Full 上限 19.7%；Preview 90,596,966；Thumbnail 56,035,901）+ 三处 stale 修正（唯一可分配/保留字节估算/方法表）。

## 3. 模块声明输出格式（任务 3）

- `IopModule::output_format(&self, input: PixelFormat) -> PixelFormat`，默认恒等。`PixelFormat` 是 `lightamer-iop-traits` 内新 `format.rs` 的线形（`Roi` 同构先例：L0 不许跨 crate 依赖，管线在 `chain::{format_to_wire,format_from_wire}` 处转换，全覆盖无错误分支）。
- 管线按它给每个节点分配输出平面（整帧路 + 流式路见 §2；引擎落盘经新 `chain_output_format` 公开 helper 算总输出格式，未知 id 恒等——管线建链时自会报 `UnknownModule`，不发明第二种错误）。
- RGBA 专用读取入口：`Plane::from_slice` 保持 RGBA-only（mono 缓冲 stride 不够宽，分类型 `RoiMismatch`，测试钉住）；新 `from_slice_channels` 走双格式；`row()` 按 `channels()` 切片；`check_channels` 拒 1/4 以外。`process`/`commit` 签名未动。
- `IdentityModule` 通道感知（`testkit` 唯一改动：行宽按 `input.channels()` + 通道不等分类型拒绝，旧测试未动）。

## 4. `ImageInfo` 带 RAW 事实（任务 4）

- `ImageInfo` 加 `format: PixelFormat`（线形，默认 RGBA）+ `raw: Option<RawFacts>`（默认 None）；`ImageInfo::new` 签名未动，加 `with_format`/`with_raw` 常量构造 + `is_raw()`（`raw.is_some()`，引擎排序的唯一信号）。
- `format` 进 `ImageInfo` 的理由：引擎 probe 路（`RenderFacts`）与流式 `StreamRequest` 都没有帧可问，格式必须随事实走；且 `RenderFacts` 结构体零改动，旧字面量全过。
- `RawFacts` 字段表（`dt_image_t`，`src/common/image.h @ release-5.7.0`）：

| 字段 | 类型 | 上游 | 消费者 |
|---|---|---|---|
| `black` | `[u32; 4]` | `raw_black_level_separate`（上游 `uint16_t[4]`，`u32` 无损装解码 `i32`） | rawprepare |
| `white` | `u32` | `raw_white_point`（HDR 时存 float 位） | rawprepare |
| `wb` | `[f32; 4]` | `wb_coeffs`（R/G/B/G2；非 4Bayer 只前三有效） | temperature |
| `xyz_to_cam_d65` | `Option<[f32; 9]>` | rawspeed 原样（D65 下 XYZ→相机，行主序） | temperature 回落（`_calculate_bogus_daylight_wb` 经此族矩阵） |
| `cam_to_xyz_d65` | `Option<[f32; 9]>` | 上者 f64 求逆（相机→D65 XYZ） | 同上 |
| `cfa` | `CfaPattern::{None,Bayer([CfaColor;4]),XTrans([CfaColor;36])}` | `filters/xtrans`（本事实为 demosaic 预备；头段四模块读的是管线 `dsc`，见下） | demosaic（后波） |
| `crop_x/crop_y` | `i32` | 同名（`int32_t` 照搬） | rawprepare（默认值） |
| `p_width/p_height` | `i32` | 同名（注意：上游 rawprepare 会**改写**它俩；本事实是解码时刻快照，填值波定义语义） | rawprepare |
| `linear_response_limit` | `f32` | 同名 | highlights（`d->clip` 上限） |
| `hdr` | `bool` | `DT_IMAGE_HDR`（rawprepare.c:572,706：float 归一化路） | rawprepare |
| `four_bayer` | `bool` | `DT_IMAGE_4BAYER`（temperature.c:1455：wb 有效数 4 vs 3） | temperature |
| `s_raw` | `bool` | `DT_IMAGE_S_RAW`（hotpixels.c:362,380,409：monoraw 联合条件一半） | hotpixels |
| `monochrome` | `bool` | `DT_IMAGE_MONOCHROME`（同上另一半） | hotpixels |
| `monochrome_bayer` | `bool` | `DT_IMAGE_MONOCHROME_BAYER`（hotpixels.c:382：`d->monochrome`） | hotpixels |
| `load_ok` | `bool` | `load_status == OK 或 CACHE_FULL`（temperature.c:209 判失败；1439 的 OK-vs-CACHE_FULL 仅管一条日志，不区分） | temperature |
| `camera_missing_sample` | `bool` | `camera_missing_sample`（gboolean，temperature.c:1498） | temperature |

- 未加（上报备忘）：`camera_maker/model/makermodel`、`filename`（字符串，`Copy` 放不下；temperature 的机身白平衡预设匹配与缺样本警告要它们，填值波给方案）；`dng_gain_maps`（A-27 只保 A7R5，ARW 没有，不做）；`orientation`/`filters` 字/`xtrans` 表/`dsc` 派生（管线侧结构，非解码事实）。
- `CfaColor` 照搬解码侧 9 值（R/G/B/C/M/Y/White/FujiGreen/Unknown，顺序一致，填值无损）；`SecondGreen`（dt FC 色 3）无解码对应，不设——A7R5 Bayer 用不到， exotic 到时再加变体。
- `Copy` 保持：`PartialEq/Eq/Hash` 手写，浮点按位（`0.0 ≠ -0.0`，同位 NaN 相等且同哈希，测试钉住）。
- 缓存键：新 `chain_keys_with_image`（kind/input/process/**image 全折叠**/nodes），`render` 切过去；旧 `chain_keys` 委派默认 image（旧相对断言全过）。色空/format/CFA 标签一律显式 `match → u8`，不用 `as u8`。
- 颜色矩阵方向/参考白：D65 下 XYZ→相机（原样）与相机→D65（求逆），与解码侧 `RawMetadata` 同名同义。

## 5. 已实现模块表（任务 5）

- 约定：模块目录的 `mod.rs` 给出 `pub fn create(` 即实现（签名 `fn() -> SharedModule`），只有 `DESC` 的桩不算。
- 四域 `build.rs` 同改：扫描时文本检测 + 生成 `IMPLEMENTED: &[(&str, fn() -> SharedModule)]`（当前四表全空，已验生成物 `= &[]`）；各域 `lib.rs` 加 `IMPLEMENTED` 重导出 + `lookup_implemented(id)`。
- `lightamer_registry::lookup_implemented` 串四域，无中央清单。
- 测试：每域 `implemented_modules_resolve_and_stay_described`（表内可查 + 表内必在 `MODULES` + 未知 id 无 + 双向一致）与 registry 同名测试。**正向检出（`create` 被扫进表）本波无真模块可验**，属已知缺口，B3-1 首个转写模块落地即覆盖。

## 6. 按 RAW 与非 RAW 排序（任务 6）

- `execution_order` 保留（jpg，旧测试直调）；新 `execution_order_for(instances, raw)`；`sort_chain` 改为 `sort_chain_for(settings, modules, raw)`（私有，非测试直调，无垫片）。
- 作业内两次重排（幂等，后事实赢）：probe 后按 `facts.image.is_raw()` 重排；fetch 后按 `fetched.image.is_raw()` 重排。probe 前的早退路（已取消/probe 失败）沿用 jpg 序（无事实可用，已注记）。零新增解码：probe 恰一次、fetch 恰一次（测试计数钉住）。
- 流式路：direct-stream 用 probe 事实的重排结果；FrameTooLarge 回退用 fetch 事实的重排结果；落盘格式经 `chain_output_format` 同 threading 算。
- 非 RAW 逐值不变：旧引擎测试全过（`execution_order_sorts_unknown_ids_after_known_by_module_then_multi` 逐字节未动）。
- 核心测试禁写模块名（`check-no-iop-names` 扫 engine）：raw/jpg 差异对用程序从两条链推导（`flipped_pair()`，当前推出 denoiseprofile/colorin 对），不拼字面量；id 借静态 `ModuleDesc` 的 `&'static str`，零分配零泄漏。

## 7. 验收

（命令与输出原文见下；`machine-guard` 输出：`GUARD PASS (heavy=0 free=43% ...)` 起始，`GUARD PASS (heavy=0 free=30% ...)` 全量前。）

- [x] `cargo test --workspace --locked --no-fail-fast -j6`：EXIT 0，714 passed / 0 failed（基线 676 + 新增 38，清单见 §8；日志 `/tmp/b3-0a-test2.log`，181s）。
- [x] 六 lint：`CARGO_INCREMENTAL=0 cargo clippy --workspace --all-targets --locked -j6 -- -D warnings -D clippy::perf -D clippy::indexing_slicing -D clippy::unwrap_used -D clippy::expect_used -D clippy::panic -D clippy::todo -D clippy::unimplemented` EXIT 0，零 error/warning；`cargo fmt --all --check` 过；`RUSTDOCFLAGS="-D warnings" cargo doc --workspace --no-deps --locked` EXIT 0；`cargo xtask layers`（29 crates 无违反）、`check-order-sync`（97 模块 OK）、`check-no-iop-names`（97 名，4 roots clean）；`Scripts/check-licenses.sh` EXIT 0。
- [x] 五演示脚本退出 0：`rust-session-demo.sh` / `rust-history-demo.sh` / `rust-render-demo.sh` / `rust-decode-demo.sh` / `rust-stream-demo.sh` 皆 `demo: ALL GREEN`，无「测不准」重试。
- [x] `git grep -n -E 'OUTPUT_BPP|16 \* ' -- crates apps/lightamer-cli`：零命中（exit 1）。
- [x] 单通道整链（A7R5 合成 9568×6376，探针 `b3-0a-probe` 已删）：空链逐字节等输入；增益链 61,005,568 lanes 逐位等 `in×3`；`/usr/bin/time -l`：maximum resident set size **987,627,520 B**（942 MiB），peak memory footprint **742,917,152 B**（约 708.5 MiB）。构成注记：探针全程持有输入帧（244MB）+ 增益输出（244MB），流式段另有 244MB 映射落盘常驻，三者同活 + 分配器余量即峰值；单平面均为 244,022,272 B（预算记账已由 `mono_gain_chain_doubles_every_lane` 按字节钉住）。
- [x] 单通道流式：244MB mono 经 thin 管（max_frame 136MB）Strip 100 pieces 跑完，与 `in×3` 逐位一致；落盘映射文件 `file_bytes=244022272 = 9568×6376×4`。
- [x] RAW 排序：`raw_and_jpg_sorts_use_their_own_chains`（raw 序 = `raw_chain()`，非 RAW = 旧 jpg 序）+ `raw_job_sorts_raw_chain_probing_once_and_fetching_once`（probe 1 / fetch 1，record 节点序 = raw 序）。
- [x] `git show --name-only HEAD` 路径纪律 + `Cargo.lock` 不变：见提交尾注（25 改 + 3 新：`iop-traits/src/format.rs`、`waves/B3-0a-REPORT.md`、`waves/B3-0a-review.log`；`Cargo.lock` 零 diff）。

## 8. 新增测试清单（38）

raster 5：`mono_format_is_4_bytes_and_allocatable`（mono 可分配+4B） / `channel_counts_cover_all_formats`（四格式通道数） / `mono_alloc_sizes_rows_and_views_by_one_channel`（分配/行/视图单通道） / `mono_from_parts_checks_single_channel_length`（长度按单通道核） / `whole_copy_refuses_across_formats`（跨格式拷贝拒绝）。
iop-traits 9：`sizes_match_the_raster_format`（线形尺寸镜像） / `new_defaults_to_rgba_and_non_raw`（`new` 默认） / `builders_attach_format_and_facts`（构造器+`is_raw`） / `raw_facts_compare_floats_bitwise`（±0/NaN 位比较） / `raw_facts_hash_floats_bitwise`（位散列） / `default_output_format_is_identity`（默认恒等） / `mono_planes_read_and_write_single_rows`（单通道平面行） / `rgba_entry_refuses_mono_buffers_typed`（RGBA 入口分类型拒绝） / `other_channel_counts_are_rejected`（1/4 以外拒绝）。
testkit 2：`copies_mono_planes_unchanged`（恒等模块过 mono） / `mismatched_channels_are_rejected`（通道不等拒绝）。
pipeline 13：`format_mirrors_round_trip`（线栅往返） / `every_image_fact_flips_the_key`（全字段翻键） / `repeated_facts_hit_the_key_bitwise`（重复命中+NaN） / `mono_empty_chain_copies_bitwise`（空链） / `mono_gain_chain_doubles_every_lane`（改值+预算字节数） / `mono_tiled_copy_matches_untiled_bitwise`（分块 25 块逐位） / `format_change_mid_chain_threads_plane_formats`（中途变格式+helper） / `cache_hit_with_other_format_recomputes`（格式错配重算） / `mono_stream_matches_whole_frame_bitwise`（流式逐位） / `format_change_refuses_before_any_allocation`（流式变格式拒绝） / `mono_sink_sizes_by_four_bytes_per_pixel`（落盘 4B/px） / `mono_disk_sink_assembles_partial_width_pieces`（半宽 copy_rows） / `piece_of_other_format_is_refused`（piece 格式错配拒绝）。
domains 4 + registry 1：各 `implemented_modules_resolve_and_stay_described`（表内可查 + 必在描述表 + 未知无 + 双向一致）。
engine 4：`raw_and_jpg_sorts_use_their_own_chains`（两链各序） / `raw_job_sorts_raw_chain_probing_once_and_fetching_once`（作业 raw 序+计数） / `mono_byte_len_counts_actual_bytes`（保留字节实际数） / `mono_full_streams_and_matches_whole`（引擎 mono 流式逐位）。

## 9. 没做的 / 缺口

1. 正向检出测试（§5）：无真模块，B3-1 覆盖。
2. `temperature` 要的字符串事实（机身/文件名）与 `dng_gain_maps`（§4 表）：按任务书留下。
3. `p_width/p_height` 的改写语义（§4 表）：填值波定义。
4. 流式中途变格式只拒不修：首个真变格式模块（demosaic）到来时重审（当前无模块变格式，拒绝分支仅测试覆盖）。
5. 单通道 `STREAM_BYTES_PER_PIXEL` 未重测：沿用 150（偏保守），首个 spatial RAW 模块到来时重测。
