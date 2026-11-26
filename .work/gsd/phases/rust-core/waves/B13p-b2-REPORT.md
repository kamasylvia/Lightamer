# B13′-b2 Report: Sync/Merge Commands, the 10k Gate, and the History Demo

> lane B13′-b2（omp 执行）。HEAD 起始 `105d5f8cf14eb1a6a620d0be01d2564f0722f461`（亲核，
> `docs(rust-core): record the B13'-b1 verification, add the B13'-b2 brief`）。
> 全程中文；代码注释与标识符英文；commit message 英文。

## 结论头

- `develop.sync`/`develop.merge` 在草稿与真实会话上按 T5 落库（单事务、多目标全成全不成，
  纯函数零改只调用）；登记表 22 条；全工作区 384 通过 / 0 失败 / 1 忽略（344 + 40 新）。
- 一万张粘贴发行版三轮 302.9/296.3/293.9ms，中位数 296.3ms，事件 10000/轮，门（1s）过，
  余量约 70%；逐张加载无近路——一次即过，未调优，会话库零改动。
- `run --file` 在真实会话上逐行打印文件内照片（8 字符短标识）；`bench` 落位；
  `Scripts/rust-history-demo.sh` 六步全绿 exit 0；复审结论见末节。

## 两条新命令（各一行）

- `develop.sync`：从一张源照片（`id`）的当前设置，把选中部分同步到一批目标（`ids`），源只读。
- `develop.merge`：把剪贴板里选中的部分合并到一批目标（`ids`），剪贴板空是 `EmptyClipboard` 错。

三种选择（`selection` 可选参数，字符串数组，一次调用一种颗粒）：不给 = 源的全部模块
（目标独有的实例保留，与 `paste` 整份替换不同）；给模块名（`mod_a`）= 这些实例整替或新增，
没选中的不动；给到参数（`mod_a.p`）= 只覆盖这些参数，目标缺该模块时新建只带选中参数的实例。
两种颗粒混用、空数组、非数组、空条目、`mod.`/`.p`/`a.b.c` 形均为参数错误，什么都不写。
多实例下标恒 0（任务书未要求多实例选择，如实记一笔）。

校验口径：模块须在注册表里（`params_for` 命中）；参数名只在该模块声明了字段时校验，
未声明字段的模块沿 `develop.set` 同款接受一切（`checked_instance` 语义）。
源照片不存在报与别命令相同的 `NoPhoto`。每张目标各记一步，标签 = 命令标识；
目标处理版本号不变（合并只动实例）。

## 一万张粘贴的数（发行版，机器安静，`target/release/lightamer-cli`）

第一轮（会话 Gate，3 万张占位，6e38cb4 时代码）：

```text
$ sysctl -n vm.loadavg   # { 3.48 2.31 2.00 }，10 核，0.35 < 1.0，不忙
$ target/release/lightamer-cli bench paste --session /tmp/lightamer-bench-gate/Gate --photos 10000 --runs 3
bench paste: round 1: 302.9ms events=10000
bench paste: round 2: 296.3ms events=10000
bench paste: round 3: 293.9ms events=10000
bench paste: 10000 photos x 3 runs: median 296.3ms events=[10000,10000,10000] gate=1000ms PASS
exit=0
```

复测（新会话 Gate2，同样 3 万张，排除首轮缓存/页暖）：

```text
$ sysctl -n vm.loadavg   # { 3.09 2.31 2.01 }，10 核，不忙
$ target/release/lightamer-cli bench paste --session /tmp/lightamer-bench-gate2/Gate2 --photos 10000 --runs 3
bench paste: round 1: 300.1ms events=10000
bench paste: round 2: 299.8ms events=10000
bench paste: round 3: 304.2ms events=10000
bench paste: 10000 photos x 3 runs: median 300.1ms events=[10000,10000,10000] gate=1000ms PASS
exit=0
```

演示脚本内第三轮（见下节输出）：296.7/292.4/295.4ms，中位数 295.4ms，PASS。

读法：每轮 = 一次 `develop.paste` 调用的墙钟（调用起到返回，1 万个 `PhotoChanged`
事件在 `execute` 内同步送达，计数器亲数）；三轮各用一批新登记的照片（会话须有
`runs*photos` 张，`bench paste` 按片切分，不足直接报错指去 `setup` 足数），
上一轮的效果不污染下一轮的起点。门 1s：过，余量约 700ms（70%）。
逐张加载整个栈再提交（b1 原样，无近路）一次即过——**未调优，会话库零改动**
（`git diff --stat 105d5f8c -- crates/lightamer-catalog` 无输出），§4 的拆数分支未触发。
`bench setup` 建 3 万张约 14s（不计时，建完即弃）。

## 计时工具怎样用

`bench` 是开发用的工具，**不是导入命令**（真正的导入是 B15 的 `library.import`；
帮助文字与 `docs/SESSION.md` 均已写明）：

```text
lightamer-cli bench setup --parent 目录 --name 名字 --photos N
# 建会话，往 Capture/ 放 N 个空占位文件并登记；打印会话位置与数量。

lightamer-cli bench paste --session 位置 --photos N --runs R   # R 默认 3
# 打开会话；先给源照片设一参数并拷贝（不计时）；再量 R 轮粘贴。
# 机器忙（1 分钟负载/核数 > 1，与 Scripts/rust-budget.sh 同口径）打印
# UNRELIABLE 并跳过，exit 0，不判过也不判不过。
# 中位数 < 1s 且每轮事件数 == N 则 PASS，否则 exit 1。
```

命令行工具因此直接依赖 `lightamer-catalog`（分层检查里 CLI 本就 exempt，
`cargo xtask layers` 仍过；无新增第三方依赖，许可证检查 852+1 不变）。

## 命令行在真实会话上的输出

`run --file` 在真实会话打开后，每行打印文件里任何一行出现过的照片标识
（`params.id`/`params.ids`，`scan_photo_ids` 复用）的步数和游标，
`short:steps:cursor`，标识取前 8 字符（`--help` 与 `docs/SESSION.md` 写明）；
不在会话里的标识打印 `?:?`。会话未打开时 `photos=[]`（打开后才开始打印）；
草稿文件行为逐字节不变（A7a 五行复核见 §7）。

## 演示脚本的输出（`Scripts/rust-history-demo.sh`，exit 0，全文）

```text
GUARD PASS (heavy=0 free=61% swap=?M disk=?GB)
    Finished `dev` profile [unoptimized + debuginfo] target(s) in 0.07s

==> 1. plant a session with three empty photos
bench setup: session /var/folders/.../T//lightamer-history-demo-3IB6C2/Shoot database /var/folders/.../T//lightamer-history-demo-3IB6C2/Shoot/Shoot.lmsessiondb registered 3 photos
a=4cf1e7b0 b=0b5deee6 c=9195a6c6 (8-char shorts)

==> 2. edit A twice, undo, redo; close; reopen and compare
line 1: session.open ok outcome={...} photos=[4cf1e7b0:1:0] digest=13864722889694970747
line 1: job 1 started
line 1: job 1 progress 3/0
line 1: job 1 finished success=true cancelled=false
line 2: develop.set ok outcome={"updated":1} photos=[4cf1e7b0:2:1] digest=13069427696338594758
line 3: develop.set ok outcome={"updated":1} photos=[4cf1e7b0:3:2] digest=9050969355946013324
line 4: history.undo ok outcome={"cursor":1} photos=[4cf1e7b0:3:1] digest=1763919428564715147
line 5: history.redo ok outcome={"cursor":2} photos=[4cf1e7b0:3:2] digest=9050969355946013324
line 6: session.close ok outcome={...} photos=[] digest=9276819852570476799
line 1: session.open ok outcome={...} photos=[0b5deee6:1:0,4cf1e7b0:3:2,9195a6c6:1:0] digest=3319529150587838082
line 1: job 1 started
line 1: job 1 progress 3/0
line 1: job 1 finished success=true cancelled=false
line 2: develop.copy ok outcome={"modules":1} photos=[0b5deee6:1:0,4cf1e7b0:3:2,9195a6c6:1:0] digest=17104308644781731354
line 3: develop.copy ok outcome={"modules":0} photos=[0b5deee6:1:0,4cf1e7b0:3:2,9195a6c6:1:0] digest=14794419602779045081
line 4: develop.copy ok outcome={"modules":0} photos=[0b5deee6:1:0,4cf1e7b0:3:2,9195a6c6:1:0] digest=14794419602779045081
line 5: session.close ok outcome={...} photos=[] digest=9276819852570476799
reopened states match: 4cf1e7b0:3:2 0b5deee6:1:0 9195a6c6:1:0

==> 3. kill -9 mid-drag: committed stays, live dies
held confirmed; killing the holder (pid 98085, our own child)
line 1: session.open ok outcome={...} photos=[0b5deee6:4:3] digest=12665053269987124789
line 1: job 1 started
line 1: job 1 progress 3/0
line 1: job 1 finished success=true cancelled=false
line 2: develop.copy ok outcome={"modules":1} photos=[0b5deee6:4:3] digest=1986471008536165659
line 3: session.close ok outcome={...} photos=[] digest=9276819852570476799
after kill: 4 steps, cursor 3, committed 3.0 kept, live 99.0 gone

==> 4. sync one module A->B; merge clipboard selection ->C
line 1: session.open ok outcome={...} photos=[0b5deee6:4:3,4cf1e7b0:3:2,9195a6c6:1:0] digest=12665053269987124789
line 1: job 1 started
line 1: job 1 progress 3/0
line 1: job 1 finished success=true cancelled=false
line 2: develop.copy ok outcome={"modules":1} photos=[0b5deee6:4:3,4cf1e7b0:3:2,9195a6c6:1:0] digest=14022910629538912507
line 3: develop.sync ok outcome={"synced":1} photos=[0b5deee6:5:4,4cf1e7b0:3:2,9195a6c6:1:0] digest=17489507588997881974
line 4: develop.merge ok outcome={"merged":1} photos=[0b5deee6:5:4,4cf1e7b0:3:2,9195a6c6:2:1] digest=5868261100449613404
line 5: session.close ok outcome={...} photos=[] digest=692580377198501362
sync: B 5:4 develop.sync value 2.5; merge: C 2:1 develop.merge

==> 5. ten thousand pastes on the release build
    Finished `release` profile [optimized] target(s) in 3.64s
bench setup: session /var/folders/.../T//lightamer-history-demo-3IB6C2/Big database /var/folders/.../T//lightamer-history-demo-3IB6C2/Big/Big.lmsessiondb registered 30000 photos
bench paste: round 1: 296.7ms events=10000
bench paste: round 2: 292.4ms events=10000
bench paste: round 3: 295.4ms events=10000
bench paste: 10000 photos x 3 runs: median 295.4ms events=[10000,10000,10000] gate=1000ms PASS

==> 6. clean up
demo: ALL GREEN
```

（`outcome={...}` 系 `session.open/close` 的长路径字段缩写，其余逐字；
`uuid` 每次随机，短标识与 digest 每次不同，步数/游标/标签恒定。）
强杀说明：杀的是脚本自己后台起的 `$!`（`lightamer-cli run --hold`），杀前经
`session.open` 双开被拒确认它握着锁；trap 兜底只杀 `comm` 为 `lightamer-cli`
的该 pid。崩溃语义的非脚本测试已由 b1 覆盖
（`real_session_crash.rs::killed_mid_drag_keeps_committed_steps_and_loses_the_live_value`：
子进程提交 3 步 + 未松手拖动被强杀后，已提交全在、live 值不在），本波未重写。

## 第 7 节验收（命令与输出）

- 守卫（每次构建前）：`Scripts/machine-guard.sh` →
  `GUARD PASS (heavy=0 free=70%/64%/63%/62%/61% ...)` exit 0（构建/计时/演示各跑一次，均过）。
- 四包：`cargo test -p lightamer-engine --locked` = 155 通过（61 lib + 26 + 1 + 25 + 18 + 13 + 11）；
  `cargo test -p lightamer-cli --locked` = 47 通过（42 lib + 5 集成）；
  `cargo test -p lightamer-history --locked` = 38 通过；
  `cargo test -p lightamer-catalog --locked` = 60 通过 + 1 忽略（perf_10k）；全绿。
- 全工作区：`cargo test --workspace --locked` = **384 通过 / 0 失败 / 1 忽略**
  （344 + 本波 40 新：引擎草稿 17 + 引擎真实 18 + CLI 库 3 + CLI 集成 2；另 1 默认忽略的
  计时测试仍是 b1 那一个）；`-- --list | grep -c ": test$"` = 385 = 384 + 1。
- 登记表：`target/debug/lightamer-cli commands | grep -E "^[A-Za-z][A-Za-z.]* — " | wc -l`
  = **22**；`commands develop.sync` / `commands develop.merge` 各打印标识、
  说明与参数清单（`id/ids/selection`，selection 标 optional，见上节输出存档——
  本节验收时亲跑：sync 列 `id: text` + `ids: photo-ids` + `selection: selection`，
  merge 列 `ids` + `selection`，各有说明）。
- 一万张门：见上上节（发行版、安静、三轮、中位数 296.3ms、事件 10000/轮、PASS、exit 0）。
- A7a 五行：重建 `/tmp/A7a-five.jsonl`（A7a-REPORT §5 原文）重跑，
  五行 `digest=9734988588720734966/6191755046607852097/...` 与 exit=1 逐位相同。
- 六 lint：`cargo clippy --workspace --all-targets --locked -j6 -- -D clippy::indexing_slicing
  -D clippy::unwrap_used -D clippy::expect_used -D clippy::panic -D clippy::todo
  -D clippy::unimplemented` exit 0；另 `cargo clippy --workspace --all-targets --locked -j6 --
  -D warnings` exit 0；`cargo fmt --all --check` 干净；
  `RUSTDOCFLAGS="-D warnings" cargo doc --workspace --no-deps --locked` exit 0。
- 四 xtask：`layers` → `OK: 29 crates, no layering violations.`；
  `check-order-sync` → `OK (97 modules, ...)`；`check-no-iop-names` →
  `OK (97 names, 4 roots clean)`；`check-apple-boundary` →
  `OK: 29 crates, 196 rust files, no Apple-boundary violations.`；
  `Scripts/rust-apple-boundary.sh` → `ALL GREEN`（7/7）exit 0；
  `Scripts/check-licenses.sh` → `allow=852 exception=1 fail=0 total=853` exit 0。
- `rg -n 'std::fs|create_dir|read_dir|std::fs::copy|fs::copy' crates/lightamer-engine/src`
  无输出（exit 1）。
- `Scripts/rust-session-demo.sh` exit 0（`demo: ALL GREEN`，14s 内）；
  `Scripts/rust-history-demo.sh` exit 0（`demo: ALL GREEN`，输出见上节）。
- 封存面：`git diff --stat 105d5f8c HEAD -- crates/lightamer-history crates/lightamer-registry
  'crates/lightamer-iop-*/src/modules' crates/lightamer-apple` 无输出；
  另 `crates/lightamer-catalog` 同命令亦无输出（门一次过，未调优）。
- 残留：`git status --porcelain` 无测试/脚本临时文件（仅本波交付路径）；
  系统临时目录无本波 tag（`lightamer-history-demo-*`/`lightamer-bench-gate*`/
  `lightamer-cli-test-*`/`lightamer-engine-test-*` 零命中，他会话旧物未碰）；
  `pgrep -f lightamer-cli` 无残留。
- `git show --name-only HEAD`：见 Commit 节（只含纪律清单内路径）。

## 测试映射（任务书「测试」一节 → 测试名）

草稿（`develop.rs` tests）：`sync_without_selection_merges_all_source_modules` /
`sync_module_grain_replaces_adds_and_leaves_the_rest` /
`sync_param_grain_overwrites_only_named_params` /
`sync_param_grain_creates_a_missing_instance_with_only_named_params` /
`sync_keeps_the_target_process_and_labels_each_step`（双目标 + 源不动）/
`sync_with_an_unknown_source_changes_nothing` /
`sync_rejects_an_unknown_module_in_the_selection` /
`sync_rejects_an_unknown_param_in_the_selection` /
`sync_rejects_mixed_and_malformed_selections`（混颗粒 + 8 种坏形）；
merge 侧 8 个同构（`merge_…`，空剪贴板为 `merge_with_an_empty_clipboard_changes_nothing`）。

真实（`real_session_sync_merge.rs`，18 个）：上列行为逐条对应真实版
（`…_and_persists` 另断库内标签/游标），出错四例各比盖库摘要 + 库内标签不动，
事务两例（`sync_batch_is_one_transaction` / `merge_batch_is_one_transaction`，
中间照片 `RAISE(ABORT)` 触发器，三张内存与库全不动）。

分发口：`registry_holds_twenty_two_commands_with_unique_ids_and_docs`
（22 条 + 全员 summary/参数无重复有说明 + sync/merge 参数逐个钉死）；
另 `bad_params_cases` 补 merge/sync 各三坏参（`failing_calls_…` 仍全覆盖）。

命令行：`cli_run_real_session_prints_watched_photos_per_line`
（open 行即打 1:0、set 后 2:1、未知标识 `?:?`、全长 uuid 永不打印）；
`setup_registers_the_count_and_reopens`（7 张 + 重开）；
`paste_times_one_hundred_photos_and_counts_events`（100 张 × 1 轮，事件 == 100）；
`paste_refuses_a_session_short_of_photos`；
`cli_bench_setup_and_paste_end_to_end`（二进制级 setup 4 张 + paste 2×2，PASS）。
一万张三轮默认不跑（只在 `bench` 手动与演示脚本里跑）。

崩溃非脚本测试：b1 `real_session_crash.rs` 已覆盖（见演示节），本波未重写。

## Commit

（待填：提交后回填最终哈希。）

`git show --name-only`（逐路径 `git add`，禁 `-A`，零 push）：

```text
（待填）
```

message：`feat(rust): B13'-b2 sync/merge commands, 10k gate and history demo` + `refs #32`。

## 复审结论头

（待填：复审实例结论。）

## 修订记录（自审回注）

（待填。）

## 给用户看的汇报

做成了什么：两条新命令——`develop.sync`（从一张照片把选中的调整同步给一批照片）
和 `develop.merge`（把剪贴板里选中的调整合并给一批照片），三种选法（全部/按模块/
按参数），一批照片要么全成要么全不成；一万张照片粘贴同一份调整 0.3 秒可见
（门是 1 秒，余量 70%）；关掉重开历史一模一样，强杀后已提交的全在、没松手的拖动不在。

怎样用一条命令现场看：

```text
Scripts/rust-history-demo.sh
```

它在临时目录里从头演一遍（建会话 → 改两步/撤销/重做/重开比对 → 强杀重开 →
同步与合并 → 一万张发行版计时 → 清掉），十几秒，全绿即过。

还没做：照片导入（B15，那才是真正的导入命令——本波的 `bench` 只是开发计时工具）；
选择暂不支持多实例下标（恒 0）；缩略图/界面（B15/B17 起）。

## 未做 / 未验

- 未做：无。任务书 1–6 节全部交付；§4 的调优分支因门一次过而未触发（会话库零改动）。
- 未验：非 macOS 目标（按任务书不跑）；`bench paste` 的 `UNRELIABLE` 跳过分支
  （机器一直安静，未亲触发——逻辑即 `load1/ncpu > 1.0` 早返，单函数可读）。
