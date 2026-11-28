# B1d-c Report — Probe-First Streaming, Region-Source Pipe Entry

## 结论头

- 引擎流式不再整帧取输入：作业先探尺寸，该转直流；管线新增按区域取输入的流式入口并独占规划。200MP 条带峰值 4.58GB → 3.03GiB（3258679296B），方块 7.02GB → 3.38GiB（3633512448B）。
- 新增测试 6 个（管线 4 + 引擎 2），删 0 个；B1d-a 测试一字不改；`render` 函数体一字不改。
- 全工作区 672 通过、零失败、5 默认不跑；上限表两模式重测至磁盘墙；复审结论头见末节。
- 收尾（本提交含）：minor 双修（探契约 + 双向 lying-probe 测试；仅可转流式作业才探）另增 4 测试，旧测试一字不改；全工作区 676 通过、零失败、5 默认不跑。见末节「收尾」。

## 起点

- 起始 HEAD `18499e44`（亲核：`git rev-parse HEAD`；docs-only，起点测试数 = B1d-b 收口：666 通过 + 5 默认不跑）。
- 守卫：`Scripts/machine-guard.sh` → `GUARD PASS (heavy=0 free=71% swap=?M disk=?GB)`，构建前跑过。
- 两个技能文件先读：`ponytail`（full，默认）与 `rust-best-practices`；冲突处按任务书优先级（公开项 `///`、其余注释只写为什么、手写错误类型、项目门优先；不跟单断言与类型状态）。

## 管线的区域来源入口

- `StreamInput`（`crates/lightamer-pipeline/src/stream.rs`）：给一块绝对区域，交出那一块的画面（`fn fetch_region(&self, region: FrameExtent) -> Result<Frame, RenderError>`）。
- `StreamRequest`：`RenderRequest` 去掉整帧画面（`input_id`/`process` 流式本就不用，不带）。
- `Pipe::render_stream_from(&mut self, req, source: &dyn StreamInput, sink)`：请求里不带画面，带来源；管线规划一次，逐块向来源要输入、跑完整条链、交给接收者。头节点无输入时一次都不调来源。
- `render_stream` 保留签名，改经此入口实现（`WholeFrameInput` 私有适配器 = 整帧裁一块；盖不住的区域报同类型 `InputMismatch`）。
- `render` 的函数体一字不改（`git diff` 里 `render.rs` 零行）。

## 引擎的新次序

- `InputSource::probe`：交图像信息 + 整幅尺寸，不取像素。默认 = 整帧取出来、只留下信息（B1d-b 行为逐值不变）；大帧来源自己便宜地答（演示与计数来源都覆写了）。
- 作业次序：排链 → 在飞检查 → 探尺寸 → 持锁比 `max_frame_bytes`：自动转的实例（完整/导出）+ 非空链 + 探到超限 → 直接走流式（整帧一次都不取）；否则丢锁、整帧取输入、跑整帧入口（B1-c 原样）。整帧入口仍报 `FrameTooLarge` 时（只剩节点尺寸不一致的形状）丢帧转流，与旧路同。
- `run_stream_fallback`：删掉引擎自规划 + 逐块嵌套 `render_stream` 的循环（含 `merge_trace`/`intersect_extents`/`crop_piece_plane` 三个私有辅助）；只剩备拼装器 → 一次 `render_stream_from`（`RegionStreamInput` 适配器：每块输入区 = 一次 `fetch_region`）→ 收拼装器。规划只在管线里做一次。
- 代号/取代/取消/事件规则不变：只有最新一代落地；被取代的在块之间让出（管线每块前查同一标志）。

## 新旧上限表并排（16GB，发行版，串行，`stream-demo --mp N --only` + `/usr/bin/time -l`）

| 模式 | 像素 | 块数 | B1d-b 峰值 | B1d-c 峰值（字节） | B1d-c 耗时 | 结果 |
|---|---|---|---|---|---|---|
| 条带 | 200MP | 202 | 4.58GB | 3.03GiB（3258679296） | 4.9s | 过 |
| 条带 | 300MP | 248 | 4.89GB | 4.54GiB（4870324224） | 10.8s | 过 |
| 条带 | 400MP | 286 | 6.44GB | 5.40GiB（5795577856） | 15.1s | 过 |
| 条带 | 500MP | 319 | 6.96GB | 5.98GiB（6424461312） | 29.6s | 过 |
| 条带 | 550MP | — | 7.06GB 拒绝 | 10MB 拒绝（exit 2） | — | 同磁盘墙，见下 |
| 方块 | 200MP | 56 | 7.02GB | 3.38GiB（3633512448） | 32.9s | 过 |
| 方块 | 300MP | 72 | 5.44GB | 4.75GiB（5095702528） | 61.8s | 过 |
| 方块 | 400MP | 99 | 6.66GB | 5.59GiB（6000869376） | 54.7s | 过 |
| 方块 | 500MP | 120 | 7.41GB | 5.98GiB（6415777792） | 66.9s | 过 |
| 方块 | 550MP | — | 6.97GB 拒绝 | 10MB 拒绝（exit 2） | — | 同磁盘墙，见下 |

- 块数十行与 B1d-b 逐位一致（同规划器，同预算）。
- 读法：峰值 = 输出拼装（映射文件，输出字节 = 像素数×16）+ 工作集。条带 200MP：3.259e9−3.20e9 = 约 59MB 工作集——几十 MB ✓；输入侧整帧已消（B1d-b 同格多出约 1.35GB）。方块 200MP 工作集约 430MB。400/500MP 两行读数低于输出字节：映射页干净可回收，负载下内核会收，是量法噪声不是新行为（B1d-b 同注脚）。
- 抖动：条带 200MP 复量 3258646528（与首轮差 0.001%）；方块 200MP 复量 3869589504（3.60GiB，+6.5% VM 噪声）。表取首轮值。
- 550MP 两模式同拒，exit 2，原文：`streaming run failed typed: streaming spill: streaming output needs 8800366400 bytes over the 8589934592-byte limit`（与 B1d-b 同墙；本轮拒绝在跑之前，RSS 仅 10MB——B1d-b 是先进整帧再拒，7GB）。
- 解码墙不变：61MP 的 A7R5 马赛克 122MB；渲染侧先撞的仍是输出拼装（约 536MP），输入侧整帧墙已拆掉。

### 峰值占用（复审量的）

复审独立抽量两档（发行版串行，一次一个；`/usr/bin/time -l` 的 peak memory footprint 行；常驻行与命令形见复审日志第 9 条）：

| 模式 | 像素 | 峰值常驻（字节） | 峰值占用（字节） |
|---|---|---|---|
| 条带 | 200MP | 3258351616 | 52529840（约 50MB） |
| 条带 | 500MP | 5707202560 | 82794544（约 79MB） |
| 方块 | 200MP | 3633496064 | 704875256（约 672MB） |
| 方块 | 500MP | 6002393088 | 662097160（约 631MB） |

帧放大 2.5 倍，峰值占用条带 50 → 79MB、方块 672 → 631MB，基本不涨；峰值常驻里多出来的是拼装输出的内存映射页，干净可回收。

## 测试

- 管线 4 个（`stream.rs`）：区域来源与整帧/整帧流式逐字节相同；来源恰好收到规划的输入区（逐块相等、按序）；无输入头一次都不调来源；整帧适配器盖不住分类型拒绝。
- 引擎 2 个（`render.rs`）：默认探 = 整帧取后取信息（逐值相同）；整帧取输入拒绝时仍流式成功（探 + 区域服务），整帧取 0 次、区域 4 次。
- 改 1 个（引擎 `full_streams_once_per_strip…`）：整帧取 1 → 0（行为就是本次修复），其余断言不动。
- 删 0 个：删掉的循环没有测试在依赖（三个私有辅助零直测；逐个确认：`merge_trace`/`intersect_extents`/`crop_piece_plane` 无测试引用）。
- 其余已有行为测试即回归：条带/方块引擎流式与整帧逐字节相同、取消/取代/落盘上限/拒绝透出。
- 收尾 lane 另增 4 个（`render.rs`，见末节「收尾」）；B1d-c 的 6 个与全部旧测试一字不改。

## 验收清单（命令与输出）

- `cargo test -p lightamer-pipeline --locked -j6` → `115 passed; 0 failed; 3 ignored`（起点 111 + 新增 4）。
- `cargo test -p lightamer-engine --locked -j6` → lib 82 + 集成 120 = `202 passed; 0 failed; 1 ignored`（起点 200 + 新增 2）。
- `cargo test -p lightamer-cli --locked -j6` → lib 50 + `run_session` 6 + `decode_dump` 9 = 65 通过，零失败（与起点持平）。
- `cargo test --workspace --locked --no-fail-fast -j6` → `passed=672`（666 + 6）、`failed=0`、`ignored=5`；删 0 个（删掉的循环零测试引用）。
- B1d-a 测试零改：`git diff` 里 `stream.rs` 测试区仅 import 行 + 两处纯插入（helper/double、4 新测），旧测试体零 hunk。
- `render` 不动：`git diff 18499e44..HEAD -- crates/lightamer-pipeline/src/render.rs` 零输出（整个文件零行）。
- `rg -n 'std::fs|create_dir|read_dir|std::fs::copy|fs::copy|File::create|tempfile' crates/lightamer-engine/src` → 零输出（exit 1）。
- 六条 lint：`CARGO_INCREMENTAL=0 cargo clippy --workspace --all-targets --locked -j6 -- -D warnings -D clippy::perf -D clippy::indexing_slicing -D clippy::unwrap_used -D clippy::expect_used -D clippy::panic -D clippy::todo -D clippy::unimplemented` → exit 0。`cargo fmt --all --check` 干净。`RUSTDOCFLAGS="-D warnings" cargo doc --workspace --no-deps --locked` → exit 0。`cargo xtask layers` → `OK: 29 crates, no layering violations.`。`cargo xtask check-no-iop-names` → `OK (97 names, 4 roots clean)`。`Scripts/rust-apple-boundary.sh` → ALL GREEN。`Scripts/check-licenses.sh` → exit 0（零新增依赖，`Cargo.lock` 零动）。
- 冻结面：`git diff 18499e44..HEAD -- crates/lightamer-history crates/lightamer-registry crates/lightamer-catalog 'crates/lightamer-iop-*/src/modules' crates/lightamer-apple` 零输出。
- `Scripts/rust-stream-demo.sh` → exit 0，`peak rss = 2538MB (2661793792 bytes)`（B1d-b 4309MB；脚本无硬编码数，零改）；decode/session/render/history 四脚本各 exit 0；`Scripts/rust-ci-lite.sh` → `ALL GREEN`，exit 0（`tests total passed=672`，预算 overall PASS）。
- 跑后无残留：`git status --porcelain` 无临时文件（复审完复核）；系统临时目录无本波残留（复审完复核）。
- 提交路径：`git show --name-only HEAD` 只含允许路径且有 `B1dc-REPORT.md` + `B1dc-review.log`（amend 后复核）。

## Commit

最终提交哈希：见 `git log -1`（收尾并成一个提交后为准）。

## 复审的结论头

结论头：`PASS / 0 error + 2 minor`（`waves/B1dc-review.log`，本提交原样并入，一个字未改）。

- minor-1（探与真实像素不一致）：覆写 `probe` 撒谎时两方向行为无测试——探小取大在直流路上静默输出偏小帧，探大取小在默认来源走分类型失败。修法：`InputSource::probe` 文档写明契约（来源必须保证探到尺寸与真实像素一致；探大取小→默认按区域取越界，分类型失败；探小取大→按探到尺寸规划，输出偏小），并加两个 lying-probe 测试钉死（默认按区域取；探小例断言输出尺寸等于探到尺寸，注释写明系撒谎后果）。
- minor-2（白探一次、整帧取两次）：仅 `kind.auto_streams() && !nodes.is_empty()` 时探；预览/缩略图/空链不探（永不可能转流式），整帧路仍只取一次输入。`probe` 文档加注：大帧来源应覆写便宜地答，否则整帧路解码两次（探内一次 + 取像素一次）。加测试：不可转流式作业零探 + 预览整帧取恰一次。

## 未做 / 未验

- 未做：① minor-2 的另一修法（复用探到的帧、省整帧路第二次取）没做——默认探下完整/导出整帧路仍取两次，属 B2 真解码接线时顺手项，已在 `probe` 文档写明；② 清扫只删“死 pid 或 60 分钟以上无 pid”残留，60 分钟内无 pid 的残留（旧脚本被杀）留待下次运行清；③ `render`/`render_stream` 及 B1d-a 测试零触（纪律本来如此）。
- 未验：① 本收尾未跑 `Scripts/rust-ci-lite.sh`（不在收尾验收清单内，B1d-c 执行 lane 已绿）；② 上限表/峰值占用未重测（收尾只改探门与文档，渲染/拼装路径零动，复审抽量值继续有效）；③ 预览/缩略图真机走查无（行为面：预览少一次探调用，无用户可见变化）。

## 收尾（B1d-c-close，含在本提交）

- 两处 minor 修法：见「复审的结论头」；`docs/PIPELINE.md` 行带流式（B1d-c）节跟补两句（仅可转流式作业才探 + 探尺寸契约）。
- 新增测试 4 个（`crates/lightamer-engine/src/render.rs`，旧测试零改）：
  1. `render::tests::lying_probe_larger_than_truth_fails_typed_on_default_regions`（minor-1 探大方向：默认按区域取越界，分类型失败）
  2. `render::tests::lying_probe_smaller_than_truth_delivers_the_probed_size`（minor-1 探小方向：输出尺寸等于探到尺寸；注释写明系撒谎后果）
  3. `render::tests::jobs_that_cannot_stream_never_probe`（minor-2：预览/缩略图/空链零探）
  4. `render::tests::preview_whole_fetch_runs_exactly_once`（minor-2：预览整帧取恰一次）
- 历史演示残留：根因 = 运行中被 kill -9（trap 不执行），`$TMP` 原样留下；正常 exit 0/1/3 与 TERM/INT 均自清（本收尾亲验：干净跑 exit 0 零残留）。复现：Big 建完（30000 张占位）后 kill -9 脚本 → 残留 `lightamer-history-demo-*` 带 30000 张占位（与塔台所见一致）。修法：启动写 pid 标记 + 自愈清扫（死 pid 即删，无 pid 满 60 分钟删，活 pid/自目录/年轻无 pid 永跳过）。验证：老残留（30k 张，做旧 2 小时）与死 pid 各一被删、活 pid 与年轻无 pid 各一被留，exit 0 全绿。
- 收尾验收（命令与输出）：
  - `Scripts/machine-guard.sh` → `GUARD PASS (heavy=0 free=68% swap=?M disk=?GB)`（构建前）。
  - `cargo test -p lightamer-engine --locked -j6` → lib 86 + 集成 120 = `206 passed; 0 failed; 1 ignored`（202 + 新增 4）。
  - `cargo test --workspace --locked --no-fail-fast -j6` → `passed=676`（672 + 4）、`failed=0`、`ignored=5`。
  - 六条 lint（`CARGO_INCREMENTAL=0 cargo clippy --workspace --all-targets --locked -j6 -- -D warnings -D clippy::perf -D clippy::indexing_slicing -D clippy::unwrap_used -D clippy::expect_used -D clippy::panic -D clippy::todo -D clippy::unimplemented`）→ exit 0；`cargo fmt --all --check` → exit 0；`RUSTDOCFLAGS="-D warnings" cargo doc --workspace --no-deps --locked` → exit 0；`cargo xtask layers` → `OK: 29 crates, no layering violations.`；`cargo xtask check-no-iop-names` → `OK (97 names, 4 roots clean)`；`Scripts/rust-apple-boundary.sh` → ALL GREEN；`Scripts/check-licenses.sh` → exit 0（`Cargo.lock` 零动）。
  - `rg -n 'std::fs|create_dir|read_dir|std::fs::copy|fs::copy|File::create|tempfile' crates/lightamer-engine/src` → 零输出。
  - 预览/缩略图/空链不探 + 预览整帧取恰一次：上列新测 3、4。
  - `Scripts/rust-history-demo.sh` → exit 0，跑后 `${TMPDIR}` 与 `/tmp` 下 `lightamer-history-demo-*` 零条。
  - `Scripts/rust-stream-demo.sh` → exit 0（`peak rss = 2538MB (2661859328 bytes)`，与报告值差 65KB 噪声）；session/render/decode 各 exit 0 全绿。
  - `git status --porcelain` 无临时文件；`git show --name-only HEAD` 含 `B1dc-REPORT.md` + `B1dc-review.log` 且只含纪律路径。
- 最终提交：见 `git log -1`（本报告并入后为准）。
