# B3-0b 执行报告：解码接入管线

- 工作目录 `/Volumes/UNITEK/Documents/Development/Lightamer`，起始 HEAD `84fd878c`（已亲核）。
- 技能：`ponytail`（full）+ `rust-best-practices`（取舍见 §0）。
- 上游基线 `release-5.7.0`，只读 `Lightamer-rust-spike/refs/dt-master`（`git show` 读 `imageio_rawspeed.cc`、`image.c`、`imageio_common.h`、`temperature.c`、`demosaic.c`）。
- 样张：只用两张索尼 ARW（`7RM5-LosslessCompressedLarge.ARW`、`ColorChecker.ARW`）；未碰照片库；未读 darktable/darktamer 工作树。

## 0. 取舍（Ponytail / Rust 实践）

- 错误类型手写（`DecodeError` 既有族；新拒绝走 `UnsupportedFormat`/`Internal`，不新增码）。
- 公开项 `///`，私有注释只写为什么（`//`）；`TODO` 零新增。
- 不跟「一测试一断言」（沿既有按维度列断言风格）与类型状态（`probed/decoded` 状态机走分类型运行时失败）。
- 没人要的不写：`decode --dump` 输出零改动（探针计时走临时 example，测完即删）；`rust-decode-demo.sh` 未动（可选）；引擎零改动（`InputSource` 现状已够用，无需补缝）；`mosaic()` 原样保留（parity 锚点）。
- 内存：探针零像素分配（段式 RSS 实测）；整帧路三份不同时活（§6）；`mosaic()` 的 pitch-copy 是缓存填充而非浪费（§6）。

## 1. 只解元数据的入口（任务 1）

- C 接口新增 `rs_probe` + `rs_probe_supported`（`rawspeed_shim.h`）：`decodeMetaData` 单跑 + ARW 标签几何（compression 1/7），不分配像素。`rs_probe_supported` 是纯形检查，任何异常降为 0 走回落。
- 关键设计（实测驱动）：空图上 `decodeMetaData` 会因相对裁切抛错（`subFrame: No positive crop area`），故探针先按标签预置 `mRaw->dim`，再调 `decodeMetaData`，让 rawspeed 自己施加裁切（含 CFA 移位）——与解码路逐位一致，无需手算裁切。`uncropped_dim` 只在 `createData` 里赋值，探针侧 uncropped 取标签值（已注记）。
- `RawImage::probe_metadata`：fast 路（ARW 1/7）返回与 `metadata()` 逐字段相等的 `RawMetadata`（测试整结构 `assert_eq!` 钉死）；其余形状回落 `decode + metadata`（正确性优先，RAF 已测）。探后解码/解后探针均为分类型拒绝（C 侧 `probed` 守卫：`decodeMetaData` 跑两遍会重移位）。
- `RawMetadata` 里没有「依赖像素才有、探针留空」的字段：几何来自标签 + rawspeed 裁切，其余来自 `decodeMetaData`，EXIF 来自路径——探针结构完整，无空位（由整结构相等测试证明）。
- 新增计数：`rs_decode_count`（真跑像素的次数，幂等 no-op 不计）+ `rs_probe_count`（fast 探针次数；回落计解码不计探针）。Rust 侧 `RawImage::decode_count/probe_count`。
- 口径注记：`rs_meta_parse_count` 是进程级 cameras.xml 解析次数（单例，常为 1），不能按请求 +1；本波用新增的 `rs_probe_count` 钉「探一次」，并断言 `meta_parse_count` 增量为 0（不断 XML）。

## 2. 解码填 `ImageInfo`（任务 2）

- 入口：`DecodedImage::pipe_input(region)`（`crates/lightamer-decode/src/pipe.rs` 新文件）→（单通道 `f32` 帧，`input_space = Raw` 的 `ImageInfo`）；`pipe_image(meta)` 是只要事实不要像素的半边（给探针用）。`u16→f32` 精确强转，`f32` 原样拷。
- `RawFacts` 字段来源表（上游 `release-5.7.0`）：

| 字段 | `RawMetadata` 来源 | 上游出处 |
|---|---|---|
| `black` | `black_separate` 有则用，无则 `black_level` 复四份；负值（未置哨兵）钳 0 | `imageio_rawspeed.cc:219-245`（上游恒有 2x2：它强制 `calculateBlackAreas()`，我方直传 rawspeed 答案，行为差已注记） |
| `white` | `white_level` 原样（缺席 65535）；HDR 且位型为 `0x3F800000` 时改写 1 | `:220`（`value_or(65535)`）/ `:287-288`（HDR 改写） |
| `wb` | `white_balance` 原样（缺席全 0）；**不归一化**（A7R5 实测 2536/1024/1778/0） | `:256-264`（原样拷）；归一化在 temperature 使用处（`temperature.c:1400/1725/1961`），`image.c` 只在 `dt_image_init` 置 NAN（`:2239-2242`），填充时无后处理 |
| `xyz_to_cam_d65` / `cam_to_xyz_d65` | 直传（后者为解码侧 `f64` 逆） | `:265-275`（`adobe_XYZ_to_CAM` 4x3 循环；上游填 12 值第 4 行补 0，我方非 9 元整体 None——12 元机身/第 4 行语义缺口，见 §9#7） |
| `cfa` | `is_xtrans`→36 格，`2x2`→Bayer 前 4 格；异形分类型拒绝 | `:354-380`（dcraw 字 + `filters==9` X-Trans 臂） |
| `crop_x/crop_y` | `crop.left/top` | `:304-305`（`cropTL`） |
| `p_width/p_height` | `width/height`（裁后；解码时刻快照，rawprepare 改写语义后波定义） | `:311-312` |
| `linear_response_limit` | 恒 `1.0`（EXIF `LinearResponseLimit` 未读：ARW 无此标签，本波无消费者） | `image.c:2238`（`dt_image_init` 默认）/ `exif.cc:925`（覆盖，我方未实现） |
| `hdr` | `mosaic_kind == F32` | `:280-282`（`TYPE_FLOAT32 → DT_IMAGE_HDR`） |
| `four_bayer` | dcraw 字命中 8 魔法值 | `imageio_common.h:32-40`（`FILTERS_ARE_4BAYER`） |
| `s_raw` / `monochrome` | 恒 false：非 CFA 输入整单拒绝（上游 `_sraw` 路展开为 RGB 浮点，单通道入口无法表示） | `:317-322`（`!isCFA` 进 sraw）/ `:523-524`（cpp==1 置 MONOCHROME） |
| `monochrome_bayer` | 恒 false：上游只在 demosaic 运行时置，loader 永不置 | `demosaic.c:1588` |
| `load_ok` | 恒 true（解码已成功；CACHE_FULL 半无对应） | `temperature.c:209`（仅非 OK/CACHE_FULL 判失败） |
| `camera_missing_sample` | 新增：`RawMetadata.camera_missing_sample`（shim 经 `meta->getCamera()->supportStatus` 查，`FillMetadataFields` 两路同填） | `:421-424` / `:615-618`（`SupportedNoSamples`） |

- 上游有、我方无对应且拿不到的：机身/文件名（字符串，非 `Copy`，B3-0a 已记后波）；`dng_gain_maps`（A-27 只保 A7R5）；`calculateBlackAreas` 强制（调了会与 oracle 分叉，parity 钉死不动）。
- 无 F32 夹具：HDR 改写分支走单元测试（纯函数）；`Mosaic::F32` 拷臂与守卫走合成 `DecodedImage` 直调（`pipe_input_copies_f32_mosaics_verbatim`、`pipe_image_refuses_non_cfa_and_multi_component`），无端到端覆盖（复审 M6/M8 已闭）。

## 3. 真 RAW 输入来源（任务 3）

- `apps/lightamer-cli/src/raw_input.rs`（新文件）：`RawFileSource` 实现引擎 `InputSource`（photo id 即文件路径；CLI 已有四依赖，零新增边）。
- `probe` 覆写：fast 探针（无像素、无缓存）；回落探针解了像素就顺手入缓存（RAF 后续 `fetch` 零解码，测试钉住）。
- `fetch`：整帧（`decode_file` → 句柄先 drop → 转 f32，C++ 像素不参与转换峰值）。
- `fetch_region`：命中缓存裁块转 f32；首块解码一次。缓存只留最近一张（`Mutex<Option<Arc<CachedRaw>>>`）：`InputSource` 无请求作用域，来源认不出请求边界，留一张是多块流式只解一次的下限； bounded 单马赛克，下个文件即逐出。
- 非 RAW：分类型拒绝（含文件名、解码信息、码名），无回落（JPEG 三路全拒，测试钉住）。
- `input_id`：路径 + 长度 + mtime 的 FNV-1a（本地 15 行实现）。引擎零改动。

## 4. 测试工具（任务 4）

- `crates/lightamer-testkit/src/raw_sample.rs`（新文件）：`sample_path(file)`（缺席记 skip 返 `None`）+ `load_raw_sample(file)`（`decode_file → pipe_input(整帧)` 的薄包装；解码/转换失败同样记 skip 返 `None`——解码正确性由解码 crate 自己的测试大声守卫，模块测试只管站开）。
- testkit 新增 `lightamer-decode` + `lightamer-raster` 依赖；lib.rs "Std only" 文档已按实改写。

## 5. 走通与量数（任务 5）

- 临时 example（已删）：探尺寸 → 整帧取 → 空链 → 输出与直接转换逐字节一致（两 ARW 均过）。
- 三个数（release，同机负载 ~2.4；括号为对照）：

| 文件 | 探（proper） | open | 整帧路峰值常驻 | 峰值占用 |
|---|---|---|---|---|
| 7RM5 | ~8-12ms | ~19-23ms | 926,892,032 B（884 MiB） | 919,733,352 B（877 MiB） |
| CC | ~12ms | — | 872,595,456 B（832 MiB） | 865,453,088 B（825 MiB） |

- 对照：同负载整帧解码 `decode_ms_cold` 7RM5 108ms / CC 86ms（基线 63ms 系静机）；探针省掉像素解码 + 244MB 转换，代价一次文件读（与 open 共享）。
- 峰值构成（7RM5，段式 `ps` 实测）：活内存 `u16` 122MB + 输入 `f32` 244MB + 输出 `f32` 244MB = 610MB；已释放但分配器未归还的：文件字节 86MB + C++ 非裁切面 129.5MB + EXIF 首调 84MB ≈ 300MB；合计 ~910MB，与 `time -l` 吻合。复探 5 次常驻持平（无泄漏）。
- 三份共存：fetch 路 C++ 面与 `u16` 只在 `mosaic()` 拷时共存，`f32` 转换时句柄已 drop——三者永不同时活。`mosaic()` 的拷躲不开（pitch 9728 ≠ 宽 9568，必须去衬；且它是 region 缓存的填充，非浪费）：一代价 122MB 瞬时 + 一次 memcpy。直转方案（C++ 基址 → f32）反而更差（129.5 + 244 > 122 + 244），已证伪不做。
- EXIF 首调吞整文件（+84MB，一次性，复调复用）：kamadak 既有行为（B2-b），探针与解码同受，本波不动（后波可换 seeking 读法）。

## 6. 内存约束对账

- A7R5 转换下限（两者同活）成立；第三份（C++）已逐出转换窗。
- 流式：`u16` 整张留来源（122MB），每块只转 f32 块；请求级释放做不到（无请求边界信号），只留最近一张（§3 理由）。
- 预览：A7R5 单通道 244MB < Preview 上限，整帧照常（行为未动，无新增拒绝）。
- 探尺寸：fast 路零像素分配（`is_decoded == false` + 计数 +0 三重钉）。

## 7. 验收

（命令与输出原文；`machine-guard` 输出：起始 `GUARD PASS (heavy=0 free=60% ...)`，首轮全量前 `GUARD PASS (heavy=0 free=66% ...)`，终轮 `GUARD PASS (heavy=0 free=71% ...)`。）

- [x] `cargo test --workspace --locked --no-fail-fast -j6`：EXIT 0，740 passed / 0 failed（基线 714 + 新增 26，清单见 §8；日志 `/tmp/b30b-test-final.log`，204s；中间轮 736/0 + 三 crate 回测 154/0 + probe 文件 9/9 见正文历史）。
- [x] 六 lint：`CARGO_INCREMENTAL=0 cargo clippy --workspace --all-targets --locked -j6 -- -D warnings -D clippy::perf -D clippy::indexing_slicing -D clippy::unwrap_used -D clippy::expect_used -D clippy::panic -D clippy::todo -D clippy::unimplemented` EXIT 0；`cargo fmt --all --check` 过；`RUSTDOCFLAGS="-D warnings" cargo doc --workspace --no-deps --locked` EXIT 0；`cargo xtask layers`（29 crates 无违反）、`check-order-sync`（97 模块 OK）、`check-no-iop-names`（97 名，4 roots clean）；`Scripts/check-licenses.sh` EXIT 0。
- [x] 五演示脚本退出 0：`rust-session-demo.sh` / `rust-history-demo.sh` / `rust-render-demo.sh` / `rust-decode-demo.sh` / `rust-stream-demo.sh` 皆 `demo: ALL GREEN`，无「测不准」重试（decode 日志 `grep -c 测不准` = 0）。
- [x] 两 ARW：宽高/黑位/白点/WB/矩阵/CFA 与 `metadata()` 逐值相等（`pipe_input_matches_metadata_on_both_arw` 整结构 + 逐字段）；`is_raw` 真，单通道。
- [x] 整帧路探 +1 / 解 +1（`whole_path_counts_probe_once_decode_once`）；流式多块解 +1 且块与整帧裁逐字节一致（`stream_pieces_share_one_decode_and_match_whole_crops`）；`meta_parse_count` +0。
- [x] 探不分配像素（`fast_probe_allocates_no_pixels`：未解码 + 无马赛克 + 无解码门元数据）。
- [x] 路径纪律 + `Cargo.lock`：见提交尾注（`git show --name-only` 文件全在允许集 + `Cargo.lock` 4 行纯加法偏离，见 §9#1/§10）。

## 8. 新增测试清单（26）

decode lib 4：`four_bayer_words_match_upstream`（8 魔法字 + 3 否定） / `black_prefers_separate_and_clamps_unset`（分离优先 + 哨兵钳 0） / `white_defaults_and_rewrites_the_hdr_magic`（缺席 65535 + HDR 改写） / `cfa_maps_bayer_and_xtrans_and_refuses_exotic`（Bayer/XTrans 映射 + 异形/短表拒绝）。
decode `tests/probe.rs` 11：`probe_matches_decode_field_for_field_on_both_arw`（两 ARW 整结构相等） / `fast_probe_allocates_no_pixels`（未解码 + 无马赛克 + 无解码门元数据） / `probe_then_decode_is_refused`（探后解码拒） / `probe_after_decode_is_refused`（解后探针拒） / `second_probe_is_refused`（复探拒） / `non_arw_probe_falls_back_to_decode`（RAF 回落正确） / `supported_cameras_report_no_missing_sample`（两机身无缺样旗） / `pipe_input_matches_metadata_on_both_arw`（逐值 + 6100 万 lanes 精确强转） / `pipe_input_region_matches_the_whole_crop`（块与裁一致 + 越界分类型拒绝） / `pipe_input_copies_f32_mosaics_verbatim`（合成 F32 整帧 + 块原样，复审 M6） / `pipe_image_refuses_non_cfa_and_multi_component`（合成非 CFA/cpp=2 拒，复审 M8）。
CLI lib 2：`fnv_matches_the_standard_vectors`（空串/`foobar` 标准向量） / `input_ids_are_stable_and_path_sensitive`（稳定 + 路径敏感）。
CLI `tests/raw_input.rs` 7：`probe_facts_match_fetch_on_both_arw`（探取一致） / `whole_path_counts_probe_once_decode_once`（探+1/解+1/解析+0） / `stream_pieces_share_one_decode_and_match_whole_crops`（4 块解+1 + 逐字节） / `fallback_probe_caches_so_fetch_decodes_nothing`（回落缓存） / `non_raw_files_are_typed_refusals`（JPEG 三路拒 + 码名） / `regions_outside_the_frame_fail_typed`（越界拒 + 拒后整帧照常） / `same_source_evicts_between_files`（同源 A→B→A 逐出 + 计数 1/2/3，复审 E1）。
testkit 2：`loads_the_a7r5_sample_as_mono_raw`（A7R5 成帧） / `missing_samples_skip_to_none`（缺席 skip）。

## 9. 没做的 / 缺口 / 偏离

1. `Cargo.lock` +4 行（§10）：任务书「不新增依赖」成立（零新包、零改版），但「`Cargo.lock` 不变」字面不可达——任务 2/4 点名的落点（解码侧 typed 入口、testkit 包装）不经工作区内部边实现不了（见 §10 推导）。取功能规格，锁差仅 4 条内部边（`git diff Cargo.lock` 全文 4 行加法）。
2. A7a-REPORT §5「五行采样摘要」：仓内无测试钉住那组 digest（`grep` 全仓零命中），且本波路径不碰历史哈希——行为无从变，无可验证项，记一笔。
3. F32/HDR 端到端：无夹具，改写分支单元覆盖 + 合成直调（§2 尾）。
4. ARW compression 32767 / transitional / 非 ARW：探针回落整解（正确；无缓存直调解码 crate 两柄时整帧路 2 次解码，CLI 缓存后 1 次——`fallback_probe_caches_so_fetch_decodes_nothing` 钉死）；fast 路仅 1/7。
5. EXIF 首调 84MB（§5）：kamadak 既有行为，本波不动。
6. `linear_response_limit` 的 EXIF 覆盖、`calculateBlackAreas` 强制：见 §2 表（拿不到/动不得，各有去处）。
7. 12 元颜色矩阵/第 4 行语义（复审 M1）：`size == 9` 门整体丢非 9 元；上游填 4x3。两样本皆 9 元故潜伏。
8. dcraw 字未 uncrop（复审 M5）：上游按裁切偏移移位（`:354-356`），我方直传；两样本偏移 (0,0) 故一致。非零偏移机身跟随 uncrop（需与 oracle 对齐，另案）。
9. `camera_missing_sample` 真分支（复审 M7）：语料无缺样机身，真路零覆盖；假路已钉。
10. §5/§7 的 `/tmp` 日志按退出纪律删除（复审 M9）：数字以本报告 + 会话记录为准，可重跑（探针 recipe = 已删 example，命令见 §5）。

## 10. 锁差推导（偏离 #1 的依据）

- 任务 2 要解码 crate 对外给「带 `RawFacts` 的 `ImageInfo`」入口：`ImageInfo` 住 L0 `lightamer-iop-traits`，`Frame` 住 L0 `lightamer-raster`——解码侧不添这两条边就说不出返回类型。
- 任务 4 要 testkit 按文件名返「单通道帧 + `ImageInfo`」：testkit 原只有 iop-traits/serde_json，不添 `lightamer-decode` + `lightamer-raster` 调不动入口、装不出帧（testkit 坐 L5，层规允许）。
- 任何新边都会进锁的 `dependencies` 表（含 path 边、含 optional——CLI 锁项里的 `lightamer-apple` 即证），故「零新边」与「任务 2/4 落点」互斥。任务书同时明示解码「可以用 L0 的 …」（新边祝福）与「锁不许变」，以后者字面为准前者落空——取规格，锁差 4 行纯加法（锁差全文即证：零新 `[[package]]` 段，包集逐字不变）。
- CLI 零新边（四依赖早齐）；引擎零改动（无缝可补）。

## 11. 复审

- 自审：`omp -p` 只读实例（产物隔离：`git diff 84fd878c..HEAD` + 本报告 + 上游对行；未构建/测试/编辑），结论见 `waves/B3-0b-review.log`，结论头 `PASS / 1 error + 13 minor`。
- 发现与修复：E1（缓存逐出零测试）→ 补 `same_source_evicts_between_files`；M4（探针 pitch 未对齐）→ 修对齐式（两样本 `%8==0` 故行为不变）；M6/M8（F32 臂/守卫零覆盖）→ 补合成直调两测；M11（`input_id` 防 stale 声称过强）→ 注释弱化 + 接线注记；M1/M2/M3（上游行号漂移 3 处）→ 亲验上游后逐条订正（M1 另补 12 元缺口 §9#7 + 门注）；M10（§9#4 措辞）→ 限定缓存条件；M5/M7/M9（uncrop/真分支缺样本、§5 无落盘日志）→ §9#8/#9/#10 注记；M13（prompt 文件混入）→ squash 前删除剔除；M12（737 无回跑日志）→ 终轮全量重跑覆盖（见 §7 首条终态）。
