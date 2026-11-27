# HYG1 Hygiene Lane: Align Stock Code with `rust-best-practices` + `ponytail`

> 结论头（三行）：全工作区 clippy（含 `-D clippy::perf` + 六条不崩溃 lint，非增量）退出 0；
> `cargo test` 绿（见 §5）；`missing_docs = "deny"` 在位且零缺口，rustdoc 零警告。
> 73 处 `#[allow]` → 49 处 `#[expect]`（全兑现）+ 18 处保留（句句有理由）+ 6 处死豁免删除；
> 删 `factor_cl`/`maxbuf_cl`/`to_scale`（含 2 个测试）+ 2 个随葬私有 helper；零行为变化。

## 0. 基本信息

- 起点 HEAD（亲核）：`adcbe781fa30fcbc1abc5093a7fb1219b5bc846d`
  （`docs(rust-core): tell the hygiene lane about the machine load`）。
- 技能：开工先读 `ponytail/SKILL.md`、`rust-best-practices/SKILL.md` 及
  `references/chapter_01/02/03/04/08.md`（lint、文档、性能、错误处理、借用）。
  用户优先级：`pub` 写 `///`、其余只写为什么；手写错误类型；不跟单断言/类型状态；项目门优先。
- 机器守卫（构建前）：`Scripts/machine-guard.sh` → `GUARD PASS (heavy=0 free=53% ...)`；
  当时 `load averages: 12.85 11.28 10.33`（用户重活在跑，全程 `-j6`、一次一个重活、无 `caffeinate`）。
- 起点计数（亲量）：`#[allow(` 73 处，`#[expect(` 0 处；另有 `#![allow(...)]` 95 处（见 §1.4，不在塔台口径内）。
- 起点测试数：618（`B2b-REPORT.md` §“总检查”；B2b 之后两个提交全是 docs，见 `git show --stat HEAD~2/HEAD~1`）。

## 1. `#[allow]` 每一处的去向

图例：E = 换 `#[expect]`（理由在代码旁）；K = 保留 `#[allow]`（理由在代码旁）；
D = 删除（死豁免或随葬）。行号是起点行的。

### 1.1 换 `#[expect]`（49 处，全兑现——非增量 clippy 退出 0 即证明）

| # | 位置 | lint | 理由在旁 |
|---|---|---|---|
| 1 | apple/capabilities.rs:43 | struct_excessive_bools | 原有 trailing |
| 2 | apple/macos.rs:368 | cast_precision_loss（原双项中的 truncation 是死的，见下） | 上方 doc |
| 3 | apple/macos.rs:374 | truncation + sign_loss | 新加 trailing |
| 4 | apple/viewport.rs:116 | struct_excessive_bools | 原有 trailing |
| 5 | apple/viewport.rs:234 | truncation + sign_loss | 上方 doc |
| 6 | decode/exif.rs:97 | truncation | 原有 trailing |
| 7 | decode/image.rs:316 | many_single_char_names | 原有 trailing |
| 8 | decode/image.rs:349 | truncation | 上方两行 |
| 9 | decode/lib.rs:26 | unsafe_code（FFI 声明） | 上方三行 |
| 10 | decode/lib.rs:28 | unsafe_code（extern 调用） | 上方三行 |
| 11 | catalog/backup.rs:208 | too_many_arguments（8 参） | 原有 trailing |
| 12 | engine/engine.rs:1137 | too_many_lines（数据表） | 原有 trailing |
| 13 | engine/error.rs:14 | module_name_repetitions | 下方两行 |
| 14 | engine/real.rs:126 | needless_pass_by_value | 原有 trailing |
| 15 | engine/real.rs:138 | needless_pass_by_value | 原有 trailing |
| 16 | engine/session.rs:163 | needless_pass_by_value | 原有 trailing |
| 17 | engine/render.rs:648 | too_many_arguments（9 参） | 新加 trailing |
| 18 | engine/tests/render_jobs.rs:62 | precision_loss | 新加（fmt 折至下行） |
| 19 | engine/tests/render_jobs.rs:163 | truncation | 新加（fmt 折至下行） |
| 20 | gpui/lib.rs:56 | struct_excessive_bools | 原有 trailing |
| 21 | history/history.rs:32 | module_name_repetitions | 下方两行 |
| 22 | history/history.rs:59 | module_name_repetitions | 下方一行 |
| 23 | history/settings.rs:51 | truncation + sign_loss（原三项中的 float_cmp 是死的，编译器亲证） | 下方三行 |
| 24 | history/settings.rs:200 | module_name_repetitions | 下方两行 |
| 25 | iop-traits/module.rs:149 | truncation | 上方一行 |
| 26 | iop-traits/parallel.rs:145 | precision_loss | 新加 trailing |
| 27 | iop-traits/parallel.rs:164 | precision_loss | 新加 trailing |
| 28 | iop-traits/tiling.rs:48 | truncation | 上方两行 |
| 29 | pipeline/fakes.rs:539 | truncation | 新加（fmt 折至下行） |
| 30 | pipeline/fakes.rs:695 | precision_loss | 新加（fmt 折至下行） |
| 31 | pipeline/kinds.rs:106 | truncation | 上方一行 |
| 32 | pipeline/kinds.rs:114 | truncation | 新加（fmt 折至下行） |
| 33 | pipeline/kinds.rs:181 | unsafe_code（sysconf） | 上方 doc + SAFETY |
| 34 | pipeline/render.rs:686 | too_many_arguments（8 参） | 新加 trailing |
| 35 | pipeline/render.rs:1011 | precision_loss（测试 helper） | 新加 trailing |
| 36 | pipeline/render.rs:2074 | unsafe_code（getrusage） | 新加 trailing + SAFETY |
| 37 | pipeline/tiling.rs:256 | precision_loss | 上方 doc |
| 38 | pipeline/tiling.rs:262 | precision_loss | 上方 doc |
| 39 | pipeline/tiling.rs:275 | truncation | 上方 doc |
| 40 | cli/cmp.rs:173 | precision_loss | 原有 trailing |
| 41 | cli/fetch.rs:165 | case_sensitive_file_extension_comparisons | 原有 trailing |
| 42 | cli/main.rs:232 | truncation | 原有 trailing |
| 43 | cli/render_demo.rs:48 | precision_loss | 新加（fmt 折至下行） |
| 44 | cli/render_demo.rs:109 | truncation | 新加（fmt 折至下行） |
| 45 | cli/render_demo.rs:111 | truncation + sign_loss | 新加（fmt 折至下行） |
| 46 | cli/render_demo.rs:310 | too_many_lines | 新加 trailing |
| 47 | cli/render_demo.rs:345 | truncation | 新加 trailing |
| 48 | cli/render_demo.rs:444 | truncation | 新加 trailing |
| 49 | cli/util.rs:34 | needless_pass_by_value | 原有 trailing |

注：语句内属性（`let` 上方）的超宽 trailing 注会被 `cargo fmt` 折到下一行独立成行
（#18/#19/#29/#30/#32/#43/#44/#45）；条目属性（`fn` 上方）的不折。复审 minor 1 即此。

多 lint 项的兑现说明（编译器是裁判）：
`u32/usize→f32` 只命中 precision_loss（macos.rs:368 的 truncation 是死的，已摘掉——同仓
render_jobs.rs:62 等只压 precision_loss 且一直绿，反向证明了分区）；
`f64→f32` 只命中 truncation；`f64→u64` 双命中；
`x.fract() == 0.0` 不命中 float_cmp（settings.rs:51 的 float_cmp 是死的，
`unfulfilled-lint-expectations` 亲证，已摘掉；下方的“== 是有意为之”注保留为代码注）。

### 1.2 保留 `#[allow]`（18 处，全是 `dead_code`，句句有理由）

| 位置 | 为什么不能是 `expect`（理由原文在代码旁） |
|---|---|
| apple/empty.rs:10 | 跨配置 verdict 相反：lib 构建命中、lib 自身测构建不命中（测试里构造了它） |
| catalog/tests/common/mod.rs:51/83/91/116 | 共享 helper：各测试目标分别编译，用量各不同（51/83 上方块注、91/116 新加 trailing） |
| engine/tests/common/mod.rs:70 | gate_pool：session_commands 链了不用（原有 trailing） |
| engine/tests 6 文件的 `mod common;`/`mod real_common;` 共 12 处 | 整棵抑制：4 处全未用（用 `never uses` 注）+ 8 处部分用（用 `leaves some unused` 注）；`expect(dead_code)` 会在增删一次 helper 用量时红绿 routine 改动，零 bug 信号，故一律 allow |

执行中的插曲（已纠正）：我曾按“用没用”删掉 8 处 `mod` 行 allow，
非增量 clippy 证明全是部分使用（`drain_until` 经 `drain_all` 间接用等），已全部恢复并加注。
教训：`mod` 行 allow 压的是整棵，删之前必须按“全用”判定，不能按“有用”判定。

### 1.3 删除（6 处死豁免）

| 位置 | 死因（编译器复核：删后全绿） |
|---|---|
| catalog/tests/verify.rs:20 | too_many_arguments，7 参（门限 8） |
| engine/render.rs:613 | too_many_arguments，7 参 |
| pipeline/tiling.rs:186 | too_many_arguments，7 参 |
| history/history.rs:286-288 | module_name_repetitions：`RebuildError` 不含模块名 `history`（连注一起删） |
| geom/roi.rs:310/321 | 随 `trunc_to_i32`/`ceil_to_i32` 葬（只被 `to_scale` 用，见 §4） |

终态：`#[allow(` 18 处（上表 1.2），`#[expect(` 49 处（上表 1.1），前后加总 73 = 49 + 18 + 6。

### 1.4 `#![allow(...)]` 95 处： inspected，不动

- 89 处是测试三件套 `#![allow(clippy::indexing_slicing, clippy::unwrap_used, clippy::expect_used)]`
  （各测试文件头 + `mod tests` 头）：`expect` 要求三项在每个模块全命中，
  任一测试模块少一项即红——“全命中”不是可维护的不变量，故不动（塔台 73 口径之外）。
- 4 处 build.rs `#![allow(clippy::expect_used, clippy::panic)]`：自带理由（cargo 构建错误正道），不动。
- 2 处模块级（macos.rs `#![allow(unsafe_code)]`、catalog lib.rs `#![allow(clippy::result_large_err)]`）：
  改 `expect` 语义等价但属口径外 churn，按 ponytail 不动。

## 2. 文档

- 根 `Cargo.toml`：`[workspace.lints.rust] missing_docs = "warn"` → `"deny"`（另顺手把上方 A2 注的
  “文档 warn”改成“文档 deny”；`[workspace.lints]` 之外零动）。
- 精量结果：非增量 clippy + rustdoc 全绿——**真正缺文档的公开项是 0 个**。
  塔台粗量的三十几处确是漏数（文档与函数之间隔着别的属性行，`grep` 误判）。
- 所以：零补、无新增文档行（没东西可补就不写，ponytail）。
- `RUSTDOCFLAGS="-D warnings" cargo doc --workspace --no-deps --locked` 退出 0（见 §5）。

## 3. `clippy::perf`

- `cargo clippy --workspace --all-targets --locked -j6 -- -D warnings -D clippy::perf
  -D clippy::indexing_slicing -D clippy::unwrap_used -D clippy::expect_used
  -D clippy::panic -D clippy::todo -D clippy::unimplemented`（`CARGO_INCREMENTAL=0` 真相跑）退出 0：
  **perf 真问题 0 个，误报 0 个**——无修、无新增压制。
- `Scripts/rust-test.sh` 第 17 行 clippy 命令加上 `-D clippy::perf`（只动这一行；头注未动，纪律要求）。
- 增量 lint 观测（只记录，不改门）：增量 clippy 两次跑对相同输入 verdict 翻转
  （一次报 crash/render_jobs、一次报 atomicity/render_jobs），非增量跑出 5 个目标全红。
  增量缓存会吞 lint（已知 rustc 行为类）。最终结论以 `CARGO_INCREMENTAL=0` 为准；
  是否给项目门加 `CARGO_INCREMENTAL=0` 由塔台定（超出口径，未改）。

## 4. 删除与接缝

### 4.1 删掉的项

| 名字 | 位置 | 为什么是“以后再填” |
|---|---|---|
| `TilingReq::factor_cl` | iop-traits/tiling.rs:15-16 | GPU 侧孪生：4 处字面量填值、全仓零读；跨协议（OpenCL  twin）的镜像纪律是假承诺，GPU 波重设计 |
| `TilingReq::maxbuf_cl` | iop-traits/tiling.rs:19-20 | 同上 |
| `Roi::to_scale` | geom/roi.rs:267-298 + 测试 2 个 + `new_rejects_..._scale` 里 1 行断言 | 30 行 + 2 私有 helper，编码 speculative finalscale 语义；自己的 doc 都承认远边保护“归分块决策不归这里”；除自测零调用 |
| `trunc_to_i32`/`ceil_to_i32` | geom/roi.rs:301-323（含 2 处 allow） | 只被 `to_scale` 用，随葬（`grep` 亲证无他用） |
| 构造点 4 处 | fakes.rs 2 个 `tiling()` + pipeline/tiling.rs 测试 `req()` + `default_for` | 删字段的连带：摘字面量行；`default_for` 的 factor 断言保留、`_cl` 断言摘掉（测试函数本身保留） |
| `docs/PIPELINE.md` | 分块段 `_cl` 句 + Roi 运算表的 `to_scale` + 整节“取整规则” | 按任务书：留一句“图形处理器那一侧的分块请求等图形处理器那一波再加”；取整表是已删函数的行为 spec，不留（出处仍在 darktable 源码引用里） |

- 序列化：`TilingReq` 无 serde 派生（`Debug/Clone/Copy/PartialEq`），删字段不碰字节；
  历史模型零动（`git show --stat` 无 history 文件）。
- `crates/README.md`：`grep` 无 `factor_cl`/`maxbuf_cl`/`to_scale`，无需改。

### 4.2 扫一遍：方法与结论

方法：抽全仓（`crates` + `apps`，除 `external/`）`pub fn/struct/enum/trait/const/static/mod/type`
691 个名 + `pub` 字段 275 个名 + 5 个 `pub trait` 的 14 个方法，逐个 `grep -rlw` 数文件；
89 个单文件项 + 190 个双文件项 + 16 个单文件字段 + 约 50 个双文件字段逐个看调用点
（生产用/自测用/零用三分）。
结论：**除 §4.1 外，无新增可删项**。零生产调用但保留的接缝分组如下（逐项亲看过调用点）：

| 组 | 项 | 保留理由（一句话） |
|---|---|---|
| Roi 词汇 | `intersect`/`union`/`translate`/`contains_point` | L0 类型的最小完备词汇（合/移/查），5–15 行无推测语义；与 `to_scale`（30 行 + helper + 推测语义）不同类 |
| 管线读数 | `cache_len`/`clear_cache`/`max_frame_bytes` | 引擎/UI 读数类接缝（任务书点名要保的一类） |
| 引擎读数 | `render_budget_used`/`render_generation`/`rendered_image` | 同上 |
| 版本/校验 | `is_known`、`validate_all`、`raw_chain` | 进程检查读数 / 校验入口（永不砍）/ raw 链（raw 波的输入） |
| 引擎对偶 | `unsubscribe` | `subscribe` 的对偶，UI 退订用 |
| FFI 面 | `rs_error_size`/`rs_info_size` | C ABI 声明，尺寸测试钉着 |
| 标志词汇 | `BLEND`/`DEPRECATED`/`HIDDEN`/`TILING`（+`DISTORT` 已被 gen_stubs 消费） | ModuleFlags 家族，被动声明无维护负担 |
| 描述 schema | `aliases`/`doc_level`/`multi_instance`/`default_space`/`display_key`/`panel` 字段 + `ModuleGroup`/`OrderKeys`/`HistoryKeys`/`ColorRequirement` | ModuleDesc schema 词汇；同协议内 spec，非跨协议孪生 |
| 报告词汇 | `presented`（FrameReport）、`collided`（PushOutcome）、`marked_missing`/`unmarked`（ScanStats） | 报告结构体的同协议字段；`presented` 是全扫描最接近的一次（被填 4 次零读），但属本后端报告、非 GPU 孪生，且视口 UI 是在排的活，故保 |
| 解码读数 | `sample_count`、`mosaic_hash`、`cameras_xml_bundled_path` | 在飞解码面的验证/QA 读数（parity/构建戳） |
| 测试钩 | `classify_for_test`、`rs_classify_for_test`、`inject_snapshot_key_for_test` | 名副其实的测试缝 |
| trait 方法 | 14 个全有生产调用（`modversion` 在 xmp.rs:179 等） | 合同类，无零调用 |
## 5. 验收清单（命令与输出）

### 5.1 allow/expect 计数

```text
$ grep -rn '#\[allow(' --include='*.rs' crates apps | wc -l   # 起点 73 → 终态 18
18
$ grep -rn '#\[expect(' --include='*.rs' crates apps | wc -l   # 起点 0 → 终态 49
49
```
加总：49（§1.1）+ 18（§1.2）+ 6（§1.3 删除）= 73。留下的 18 处 `#[allow]` 旁全有一句理由（见 §1.2 表）。

### 5.2 missing_docs 与 rustdoc

```text
$ grep -n 'missing_docs' Cargo.toml
16:missing_docs = "deny"
$ RUSTDOCFLAGS="-D warnings" cargo doc --workspace --no-deps --locked
exit=0（4m48s，load ~15；29 个 crate 文档全生成，零警告）
```

### 5.3 clippy（含 perf 门）

```text
$ CARGO_INCREMENTAL=0 cargo clippy --workspace --all-targets --locked -j6 -- \
    -D warnings -D clippy::perf \
    -D clippy::indexing_slicing -D clippy::unwrap_used -D clippy::expect_used \
    -D clippy::panic -D clippy::todo -D clippy::unimplemented
exit=0（156s，非增量真相跑；49 处 expect 全兑现、perf 零命中、missing_docs 零缺口）
$ sed -n '17p' Scripts/rust-test.sh
(cd "$ROOT" && cargo clippy --workspace --all-targets --locked -j6 -- -D warnings -D clippy::perf -D clippy::indexing_slicing -D clippy::unwrap_used -D clippy::expect_used -D clippy::panic -D clippy::todo -D clippy::unimplemented)
```

### 5.4 删除项

- §4.1 表逐项；`docs/PIPELINE.md` 分块段留“图形处理器那一侧的分块请求等图形处理器那一波再加”、
  Roi 段摘 `to_scale`（运算表 + 整节取整规则）；`crates/README.md` 无相关行，未动。
- `cargo fmt --all --check` 干净（`cargo fmt --all` 修过 6 文件的超宽注，exit=0 后复核 FMT-OK）。

### 5.5 测试

```text
$ cargo test --workspace --locked -j6 --no-fail-fast
exit=101（见下）；total passed=613；ok 目标 89 个；FAILED 目标 2 个，共 3 个测试红
```
总数对账：618（起点）− 2（删 `to_scale_truncates_origin_and_ceils_extent`、
`to_scale_identity_and_overflow`）= 616 = 613 passed + 3 负载红。逐个对上。
3 处红全是 bench 计时类的负载门，非代码问题（当时 load 13–16，10 核）：

| 测试 | 输出 | 机制 |
|---|---|---|
| bench::paste_refuses_a_session_short_of_photos | `Skipped { load_one: 14.29, cpus: 10 }`，`expect_err` 落空 | 负载高→bench 拒测→返回 Skipped 而非 Err |
| bench::paste_times_one_hundred_photos… | `the test machine was busy; rerun when quiet` | `assert!(measured, …)`（bench.rs:414） |
| cli_bench_setup_and_paste_end_to_end | `UNRELIABLE (load 13.17 on 10 cpus); skipping` | 同族负载门（run_session.rs:276） |

fail-fast 首跑（464s，load ~15）：停在 lightamer-cli lib，122 passed；
no-fail-fast 全跑（294s）：除上 3 处外全绿。未反复重跑（任务书禁 reroll）。
ci-lite 终跑见 §5.9（机器安静则绿，否则同红）。

### 5.6 A7a 五行

```text
$ ./target/debug/lightamer-cli run --file /tmp/A7a-five.jsonl --photos p1   # 文件为 A7a-REPORT §5 原文重建
line 1: develop.set ok outcome={"updated":1} photos=[p1:2:1] digest=9734988588720734966
line 2: history.undo ok outcome={"cursor":0} photos=[p1:2:0] digest=6191755046607852097
line 3: history.redo ok outcome={"cursor":1} photos=[p1:2:1] digest=9734988588720734966
line 4: history.goto ok outcome={"cursor":0} photos=[p1:2:0] digest=6191755046607852097
line 5: develop.paste FAIL develop.paste: the clipboard is empty photos=[p1:2:0] digest=6191755046607852097
lightamer-cli: check failed: 1 of 5 lines failed
exit=1
```
五行汇总值与 §5 当时数逐位相同，exit=1 同。零行为变化。

### 5.7 四个演示脚本

```text
$ Scripts/rust-session-demo.sh   # exit=0，ALL GREEN
$ Scripts/rust-history-demo.sh   # exit=1：bench paste: UNRELIABLE (load 11.95 on 10 cpus); skipping
$ Scripts/rust-render-demo.sh    # exit=0，ALL GREEN
$ Scripts/rust-decode-demo.sh    # exit=0，ALL GREEN
```
合计 406s。当时 load 9–13。history 首跑的 10k paste 步与 §5.5 同族负载门（机器忙则拒测，
演示脚本把 skip 计为 FAIL）。ci-lite 第二跑全绿后（独立的安静证据）条件重试一次：
`exit=0`，六步全过，10k paste 三轮 189/215/223ms（门 1000ms PASS），`ALL GREEN`。
四演示终态：4/4 exit 0。

### 5.8 layers / apple-boundary / licenses

```text
$ cargo xtask layers
OK: 29 crates, no layering violations.   # exit=0
$ Scripts/rust-apple-boundary.sh
rust-apple-boundary: ALL GREEN   # 7/7, exit=0
$ Scripts/check-licenses.sh
exit=0（无新依赖：Cargo.lock 零动，见 git show --stat 无 Cargo.lock）
```
三项合计 354s（含 xtask 构建，load ~15）。

### 5.9 ci-lite

第一跑（load 7–12，1238s）：`exit=1`，倒在预算两项，此前各步全绿——
其中测试步 `tests total passed=616`（3 个负载门当时全过，机器在测试步正安静）。
```text
rust-budget: ui rebuild (one file touched) = 277s (gate <=180s) FAIL
rust-budget: check lightamer-iop-color = UNRELIABLE (load1 10.97 on 10 cpus) SKIP-GATE
rust-budget: target/ = 20633MB (21128700KB, gate <=20GB)
rust-budget: target/ exceeds 20GB: run cleanup FAIL
rust-budget: overall FAIL
```
处置（脚本明示的 remediation，非绕行）：`target/debug/build` 15G + `target/release/build` 3.3G
全是 rawspeed C++ 构建产物（B2 波建成，我的跑只复用）；`target/debug/incremental` 2.0G 纯缓存。
确认无 rustc 在跑后删 `target/debug/incremental`（最小面）→ 19129976KB（< 20971520）。
结构注（给塔台）：rawspeed 进树后构建产物占 18.3G，20GB 门余量只剩 1.7G，
一次全量跑就把 incremental 顶回去——门要么重定，要么加周期清理。本波口径外，只记录。
第二跑（清缓存后，load ~8，546s）：`exit=0`，`rust-test: tests total passed=616`，
`rust-budget: overall PASS`，`rust-ci-lite: ALL GREEN`。终态绿。

## 6. 提交

- checkpoint：`300b6aa1942debabd938854ecac2004d4fb86599`（39 代码文件）。
- 内容提交：`062d99979c9174469f483f38b36c358eb7ebb398`（+ 本报告初稿 + 复审日志）。
- 本节定稿 amend 后哈希滚动一位，最终哈希见 lane 关闭消息（A1/A2 同先例：报告记 amend 前版本）。
- 一个提交，`refs #32`，零 push。`git show --stat` = 41 文件（39 代码 + 报告 + 复审日志），
  零 `Cargo.lock`、零 `external/`、零他人文件。

## 7. 自审

复审实例（独立 `omp -p --auto-approve --thinking max`，任务书 `/tmp/hyg1-review-prompt.md`，
已删）结论头：**`PASS / 0 error + 2 minor`**（全文 `.work/gsd/phases/rust-core/waves/HYG1-review.log`）。
复审亲跑了验收清单全部：计数 18/49 ✓、deny 在位 ✓、rustdoc 0（59s）✓、
非增量 clippy 0（47s）✓、测试 616/616（169s，负载门全过）✓、A7a 逐位同 ✓、
四演示 4/4（48s）✓、layers/边界/许可证 ✓、ci-lite 全绿（579s，2 项计时步 SKIP-GATE）✓；
5 处 expect 探针（改触发条件→编译败→还原，四类全覆盖，P4/P5 遇硬错误抢占改只读论证）✓；
删除项 grep 零残留 ✓；接缝抽 8 组 ✓；39 文件逐 hunk 无行为改动 ✓；39/39 路径合规 ✓。

minor 1：§1.1 #19 “新加 trailing”表述不准（fmt 已折至下行）。修订：连带 #18/#29/#30/#32/
#43/#44/#45 同错一起改成“新加（fmt 折至下行）”，并在表下加注说明 fmt 折行规则。报告修订，代码未动。
minor 2：viewport.rs:234 的理由链最弱（上 doc 讲函数舍入规则）。接受，不改：
doc 的取整+钳制描述与下行代码互证，足以说明两次 cast 安全；加注属 churn。

## 8. 给用户看的汇报

这次把存量 Rust 代码对齐了 `rust-best-practices` 和 `ponytail` 两个技能，小步、零行为变化：
73 处 `#[allow]` 里 49 处换成 `#[expect]`（带一句压制理由，不再命中就编译失败），
18 处 `dead_code` 留 `allow`（测试共享模块按目标用量波动，`expect` 会误红，句句有理由），
6 处死豁免删掉（含 3 个 7 参函数的 `too_many_arguments`）。
`missing_docs` 从 warn 提到 deny——编译器亲证公开文档零缺口，一行不用补。
`clippy::perf` 全仓零命中，已加进 `rust-test.sh` 常设门。
删了 GPU 侧孪生字段 `factor_cl`/`maxbuf_cl` 和零调用的 `Roi::to_scale`（含 2 个测试），
另扫了 691 个公开项 + 275 个字段 + 14 个 trait 方法，其余零调用的全是接缝（读数、报告、校验入口等），一个没动。
验收：clippy（含 perf 门，非增量）0、rustdoc 0、测试 616/616、A7a 五行逐位同、
四演示全绿、`cargo xtask layers`/边界/许可证全绿、`rust-ci-lite.sh` 全绿。
独立复审 `PASS / 0 error + 2 minor`（§7；minor 1 已修订报告，minor 2 接受不改）。

## 9. 未做 / 未验

未做（有意的，口径外）：
- `#![allow(...)]` 95 处未动（89 测试三件套 + 4 build.rs + 2 模块级），理由见 §1.4。
- `docs/ORACLE-BASELINE.md:85` 的 `tiling->factor_cl` 未动：它是上游 darktable C 结构体的字段引用
  （oracle 行为基线），非我方 Rust 代码残留；且该路径不在允许清单里。
- `target/` 20GB 门的结构性压力未改（rawspeed 构建产物 18.3G），见 §5.9 给塔台的注。
- 增量 clippy 吞 lint 的观测未改门（`CARGO_INCREMENTAL=0` 是否进项目门由塔台定），见 §3。
- `Scripts/rust-test.sh` 头注未同步 perf 门字样（纪律：只动 clippy 命令行）。

未验：
- 无：验收清单每条亲跑过（§5），复审实例独立重跑全部（§7）；双份核验一致。
