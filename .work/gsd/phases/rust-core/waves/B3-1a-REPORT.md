# B3-1a 报告：链上状态（`PipeState`）

lane B3-1a（omp）。HEAD 起点 `1b6b17a9`（已亲核）。工作树里
`waves/VERIFY.md` 有塔台未提交的改动，未碰。

只做机制，不转写任何模块。报告里的源码行号除注明外皆指上游基线
`release-5.7.0`（`Lightamer-rust-spike/refs/dt-master`，只读）。

## 一、上游模型（逐处读出）

状态本体 `dt_iop_buffer_dsc_t`（`src/develop/format.h:35-64`）：`channels`、
`datatype`、`filters`、`xtrans[6][6]`、`rawprepare{raw_black_level,
raw_white_point}`、`temperature{enabled, coeffs[4]}`、
`processed_maximum[4]`、`cst`。

### 字段读写表（只列四模块 + 去马赛克实际触达的）

| 字段 | 建链期（commit/output_format） | 处理期读 | 处理期写 |
|---|---|---|---|
| `filters` | 无写；hotpixels commit 读（`hotpixels.c:373`，同步时刻快照值） | hotpixels `process:343`（9u 判 X-Trans）；highlights `modify_roi_in:371`/`tiling_callback:397`；temperature/demosaic 经 per-piece `piece->filters` | rawprepare `process:355-356/378-379`（+ CL `:555-556`）：按裁切重算后写回；xtrans 经 `_adjust_xtrans_filters`（`:301-310`）同式写回 |
| `xtrans` | 无 | 经 per-piece `piece->xtrans`（hotpixels `:345`、highlights `:505`、temperature `:540`、demosaic `:656`） | 同上 rawprepare 写回 |
| `channels`/`datatype` | `output_format` 链写（`format.c:60-76`：默认 4/Float；RAW 1 通道；rawprepare 之前 + filters 置 U16）；经 `pipe->dsc = piece->dsc_out`（`pixelpipe_hb.c:2006`）生效 | rawprepare `process` 读 `dsc_in` 的通道/类型分支（`:336-337`、`:359-360`） | process 内无写 |
| `processed_maximum` | 无写 | highlights（`:480-482`、`:644-646`、`:915-917`、`:983-985` 直接读；`:695-696`、`:894`、`:1006-1007` 经 `dt_iop_get_processed_maximum/minimum` 读）；demosaic（`:721` 经 helper；`:865` read-modify-write，原位经 `dt_colorspaces_cygm_to_rgb` 改写，4Bayer 路径）；temperature `_publish_chroma` 读旧值（`:525-526`） | rawprepare `process` 置 1.0（`:447`、CL `:559`）；temperature `process` 经 `_publish_chroma` 乘系数（`:521-526`，调用点 `:638` process、`:678` process_cl）；highlights `process` 尾置 m（`:696` CL、`:895` CLIP 分支用 minimum、`1007` 主路径） |
| `temperature.enabled/coeffs` | 无写 | highlights（coeffs `:569-573` CL、`772-775` 可视化，皆有 `<=0→1` 兜底；enabled `:653` CL、`:732` 主路径 `enabled && late_correction`） | temperature `process` 经 `_publish_chroma`（`:521-526`） |
| `rawprepare.*` | rawprepare `output_format` 写（`:297-298`） | 四模块 + demosaic 皆不读（读者只有 `exposure.c:460-461`、`rawoverexposed.c:102-103`）→ 本波不收 | — |
| `cst` | 管线按 `output_colorspace` 写（`:1535`、`:2362`、`:2542`） | 混合/取色路径 → 本波不收（已有色彩声明通道） | — |

### 建链期与处理期是否同一份状态

- 上游 `commit_params` 在 `_dev_pixelpipe_synch`（`pixelpipe_hb.c:522-636`，commit 调用 `:617`）做全量预提交，
  读的是同步时刻的 `pipe->dsc` 静态快照；commit 不写 `dsc` 任何字段。
- 处理期 `pipe->dsc` 沿链演进：每节点先由 `output_format` 落 `dsc_out`
  （`:2002-2006`），`process` 内模块再写，节点结束把演进后的值存给出格式
  （`:2816` `**out_format = piece->dsc_out = pipe->dsc`），即下游的 `dsc_in`。
- 结论：上游处理期是同一份状态沿链演进；commit 期是静态快照，不参与演进。

### 分块语义（本波最关键的一条，`tiling.c`）

- ptp 路（`:713-801`）：块循环前保存 `processed_maximum_saved`（`:713-716`）；
  每块开始重置回保存值（`:757-758`）+ 按块 roi 派生 per-piece CFA
  （`:759` `dt_dev_prepare_piece_cfa`）；块后聚合 last-wins，块间差超 1e-6
  只打 debug 日志（`:764-775`，TODO 注明未定最小/最大/平均）；循环结束
  写回终值（`:800-801`）。
- roi 路（`:981-984`、`:1104-1106`、`:1111-1121`、`:1137`）同构；CL 两路
  （`:1543`、`:1989` 起）同形，本管线无 CL 只记不做。
- `filters`/`xtrans`/`temperature` 块间不重置（rawprepare/temperature 每块
  幂等重写，效果等价于重置）。
- 非块 per-process 派生：`pixelpipe_hb.c:1391`（CPU 主路）、`:2279`（CL 路）每次调
  `process` 前 `dt_dev_prepare_piece_cfa(piece, roi)`。
- 与任务书初读的差别：任务书拟「每块从建链期终值出发」；上游实际是
  「本节点每块从**该节点入口值**出发，节点间沿链演进」。照上游实现：
  节点 0 从 commit 终值起，节点 i 从节点 i-1 的处理后值起。

### 缓存

上游每条缓存行存 `dsc`（`pixelpipe_cache.c:350-351` `cache->dsc[cline]`）；
命中时经 `out_format` 链把存下的 `dsc` 喂给下游（`:1791-1808` 命中分支 +
`:2002-2006` 重算）。本波同构：平面旁存状态，命中恢复。

## 二、本波实现

新类型 `lightamer-iop-traits/src/state.rs`：`PipeState{CfaPattern; channels
u32; datatype BufferDataType{Float,Uint16}; processed_maximum [f32;4];
temperature TemperatureState{enabled, coeffs}}`。`Copy`，`size_of <= 96`
测试钉死（实测 84 字节），零堆分配。

字段取舍：`filters`+`xtrans[6][6]` 合并为 `CfaPattern`（X-Trans 表即其
`XTrans([CfaColor; 36])` 负载，无效组合不可表示）；`Uint16`
变体永不构造（本管线只产 f32），仅作转写分支词汇；`temperature.coeffs`
初值取恒等 `[1;4]`（上游零初值，但全部读点皆有 enabled 门或 `<=0→1`
兜底，不可观察）；`channels`/`datatype` 管线单写（`set_input`，按格式
threading），模块只读。

签名：`commit(params, image, state: &mut PipeState)`；
`process(data, input, output, rin, rout, state: &mut PipeState)`；
`build_chain(..., state: &mut PipeState)` 按链序穿值；
`PlaneCache` 条目改为 `CachedPlane{plane, state}`（`peek`/`insert`
同改，无新增堆分配与 Arc）。

管线语义：`PipeState::from_image` 起点 → commit 穿链 → 整帧/分块处理
（分块每 tile 重置 maxima，`render.rs` `run_tiled`；其余字段沿用，
末 tile 值胜出）→ 缓存旁存/命中恢复 → 流式每 piece 从 commit 终值独立
起算（`stream.rs` `render_stream_from`）。与上游的偏离仅两处（见
`docs/PIPELINE.md`「链上状态」节）：commit 穿演进值（上游静态快照），
per-piece CFA 不预计算（模块按 `rin` 偏移查表，纯函数等价）。

## 三、新增测试清单（9 个）

| # | 位置 | 测试 | 钉住 |
|---|---|---|---|
| 1 | `iop-traits/state.rs` | `starts_from_image_facts` | 起点：CFA/通道/float/1.0/未发布 |
| 2 | 同上 | `starts_patternless_without_raw_facts` | 非 RAW 无图案 + 4 通道 |
| 3 | 同上 | `input_descriptor_follows_the_format` | `set_input` 跟格式 |
| 4 | 同上 | `stays_stack_sized` | `size_of <= 96` |
| 5 | `pipeline/render.rs` | `chain_state_flows_from_writer_to_reader_in_order` | commit 2.0→reader commit 见 2.0；process 4.0→reader 见 4.0；writer 自身见 commit 终值 2.0；无 writer 时两阶段皆见 1.0 |
| 6 | 同上 | `tiled_node_restarts_maxima_from_its_entry_value` | 9 块每块见入口 2.0；节点留末块 9.0 于缓存 |
| 7 | 同上 | `cache_resume_restores_upstream_state_for_downstream` | 上游命中 + 下游重算，两次输出逐字节等（恢复 4.0，非 commit 终值 2.0） |
| 8 | `pipeline/stream.rs` | `stream_pieces_each_start_from_commit_state` | 3 条带各见 commit 值；commit 只跑一次 |
| 9 | `pipeline/cache.rs` | `stored_state_returns_with_its_plane_and_leaves_with_it` | 存/替/驱逐与平面同命 |

旧测试：函数体除跟签名加参数（`&mut PipeState` 实参、`insert` 加状态、
`peek().plane` 取平面）外，断言一行未改。测试 5 修过一次：初版误断言
writer 自身 process 见 1.0，实际 commit 与 process 共享同一穿链值，
应见 2.0（任务书「处理期从建链期终值出发」）。

## 四、没做的

- 无。任务书五项全做；`temperature.coeffs` 初值恒等化与 commit 穿演进值
  两处已按「照上游做、写明差别」记录在案（一节、二节）。

## 五、验收清单（命令与输出）

- 机器守卫：`Scripts/machine-guard.sh` → `GUARD PASS (heavy=0 free=58% swap=?M disk=?GB)`。
- 全套：`cargo test --workspace --locked --no-fail-fast -j6` → exit 0，
  `passed=749 failed=0 ignored=5`（9 个新测试全在跑，见三节；旧断言除跟签
  名加参外一行未改）。注：一次中间轮出现
  `raw_input::whole_path_counts_probe_once_decode_once` 红（cameras.xml
  单例计数断言），stash 到干净 HEAD 单跑同样红，系预存的测试隔离问题，
  与本波无关，未修（纪律路径外）；终轮全套绿。
- 六 lint：`CARGO_INCREMENTAL=0 cargo clippy --workspace --all-targets
  --locked -j6 -- -D warnings -D clippy::perf -D clippy::indexing_slicing
  -D clippy::unwrap_used -D clippy::expect_used -D clippy::panic
  -D clippy::todo -D clippy::unimplemented` → exit 0，零警告/错误
  （中途 `must_use_candidate` 指 `PlaneCache::peek`，已加 `#[must_use]`）。
- 文档：`RUSTDOCFLAGS="-D warnings" cargo doc --workspace --no-deps
  --locked` → exit 0，零警告。
- 格式：`cargo fmt --all --check` → 过。
- 分层/同步/命名：`cargo xtask layers`（29 crates 无违反）、
  `check-order-sync`（97 模块 OK）、`check-no-iop-names`（97 名，
  4 roots clean）。
- 许可：`Scripts/check-licenses.sh` → exit 0。
- 演示：`Scripts/rust-{session,history,render,decode,stream}-demo.sh`
  五个皆 exit 0。
- 文档：`docs/PIPELINE.md` 有「链上状态」一节（B3-1a）。
- 范围：`git diff 1b6b17a9 --name-only` 与（提交后）`git show --name-only HEAD` 仅纪律路径；`Cargo.lock` 无 diff。

## 六、复审（`B3-1a-review.log`，`PASS / 0 error + 8 minor`）

只读自审（`omp -p`，未构建/测试/编辑；复审日志一个字未改）。8 条 minor
逐条对上游源码复验后全修：

- M1：highlights `process:371/397` 函数标错 → 改 `modify_roi_in:371` /
  `tiling_callback:397`（行号与读点为真，仅函数名错）。
- M2：minimum helper 读点 `:897`（实为 `else` 行）→ 改 `:894`（写 `:895`）。
- M3：`:1391`/`:2279` 补 `pixelpipe_hb.c` 文件名（原会被读成 tiling.c）。
- M4：`dt_dev_pixelpipe_synch（:595-640）` → `_dev_pixelpipe_synch`
  （`:522-636`，commit 调用 `:617`）；原范围尾越界进 `synch_all`。
  顺手去报告该行杂入的英文词。
- M5：demosaic `:865` 由「直接读」改注 read-modify-write
  （`dt_colorspaces_cygm_to_rgb` 原位改写，4Bayer 路径；字段面已有，
  `&mut` 可达，转写不受影响）。
- M6：`format.c:60-78` → `:60-76`（`:78` 已是下个函数头）。
- M7：`run_tiled` 空网格早返处加偏离注释（上游零块钳 1.0，我方保持
  入口值；实际不可达）。
- M8：范围验证法补 `git diff 1b6b17a9 --name-only`（`git show HEAD`
  在提交前看的是旧提交；提交后两者皆验）。
