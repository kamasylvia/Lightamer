# B13′-c Report: 10k Paste on the Spinning Disk, and Synchronous FULL

> lane B13′-c（omp 执行）。HEAD 起始 `703c07bea6cff7565f4b164209c040ecbdb09be9`（亲核，
> `docs(rust-core): record the external-disk measurements, amendment A-21, the B13'-c brief`）。
> 全程中文；代码注释与标识符英文；commit message 英文。

## 结论头

- 机械盘万张粘贴：改前中位数 419.7ms（NORMAL）→ 改后 271.3ms 与 305.0ms（两组干净序列，FULL），读 99→16ms；
  600ms 目标过，余量约五成；内置盘 298.3→139.7ms，反而快 2.1 倍。
- 批量捷径（多目标命令不对未加载照片读整段历史）与写入器批量入口（语句复用、跳过空重做删、
  快照复用）落库：全表转储等价性钉死，六条写路径不变量测试全绿，同步档 FULL 钉死。
- 全工作区 398 通过 / 0 失败 / 1 忽略（384 + 14 新）；复审结论见末节。

## 动手前后两块盘上三段的拆数并排

口径：发行版，`bench paste --photos 10000 --runs 3`，每轮事件数均为 10000。
读 = 引擎从库里取行；写 = 事务内全部到提交返回；算 = 其余（新设置、序列化、换入、事件）。
改前二进制 = 起始 HEAD + 仅三段计时（无行为改动），存 `/tmp/b13c-baseline/lightamer-cli-before`；
改后 = 本波最终代码。机械盘会话在 `Lightamer-rust-spike/scratch-tmp/`，内置盘在 `/tmp/b13c-internal/`。

| 盘（同步档） | 改前中位数 | 读 / 算 / 写 | 改后中位数 | 读 / 算 / 写 |
|---|---|---|---|---|
| 机械盘（NORMAL→FULL） | 419.7ms | 99.1 / 10.1 / 244.4 | **271.3ms**（第一组） | 15.9 / 4.1 / 187.8 |
| 机械盘第二组（FULL） | — | — | **305.0ms** | 19.7 / 4.3 / 213.0 |
| 内置盘（NORMAL→FULL） | 298.3ms | 95.6 / 9.4 / 130.9 | **139.7ms** | 15.3 / 4.0 / 58.7 |

逐轮（命令见验收节，每行都是 `round: 总ms read= 算= 写= events=10000`）：

```text
改前机械盘 BeforeMech（NORMAL，负载 {4.56 …}，10 核）：
  round 1: 419.7ms read=99.1 compute=10.2 write=233.2
  round 2: 490.0ms read=96.9 compute=10.1 write=320.4
  round 3: 418.9ms read=101.3 compute=9.3 write=244.4
  median 419.7ms (read 99.1 compute 10.1 write 244.4) PASS
改后机械盘 AfterMech（FULL，负载 {3.68 …}）：
  round 1: 237.6ms read=15.9 compute=4.3 write=154.8
  round 2: 271.3ms read=15.8 compute=4.1 write=187.8
  round 3: 281.8ms read=16.0 compute=4.0 write=200.6
  median 271.3ms (read 15.9 compute 4.1 write 187.8) PASS
改后机械盘 AfterMech3（FULL，另一会话，负载 {5.71 …} 即 0.57/核）：
  round 1: 305.0ms read=20.9 compute=5.1 write=213.0
  round 2: 281.6ms read=19.7 compute=4.3 write=191.0
  round 3: 490.1ms read=18.2 compute=4.3 write=402.0   # 写被盘争用扰动，见下
  median 305.0ms (read 19.7 compute 4.3 write 213.0) PASS
改前内置盘 BeforeInt：300.6 / 298.3 / 297.5，median 298.3ms PASS
改后内置盘 AfterInt：139.7 / 138.2 / 145.7，median 139.7ms PASS
演示脚本内改后内置盘：141.5 / 145.3 / 147.8，median 145.3ms PASS（独立复核，见演示输出）
```

另有一组改后机械盘 AfterMech2 在盘忙时量的：1043.3 / 798.4 / 278.1，中位数 798.4，
读/算三轮纹丝不动（15.7 / 4.x），只有写被顶到 961.6 / 718.0 / 197.4。
当时 `iostat` 实测机械盘（disk6）后台 108–122 tps / 约 4MB/s（Spotlight 在该盘开着索引、
Time Machine helper 在、另有他方 darktable-cli 在读同一块盘），不是安静态——
这一组不计入验收，但如实列出。合并九轮改后机械盘数（237.6 … 1043.3），中位数 281.8ms。

与塔台数的对照：塔台机械盘 1275 / 1067 / 787（中位数 1067，NORMAL + 旧代码），
内置盘 292–305。我的改前内置盘 298.3 与塔台内置盘逐位吻合（计时 instrumentation 开销可忽略）；
机械盘改前 419.7 与塔台 1067 差一倍——同一份旧代码在 AfterMech2 扰动轮里复现了同样签名
（只有写被顶高），结论是塔台那次也撞上了盘争用（这块 USB 盘同时被多方构建/渲染/索引读写，
CPU 负载口径看不出来）。工程增益看同态前后：419.7→271.3（1.55×）；用户体感看塔台态到改后：
1067→约 280（3.8×）。目标 600ms：两组干净序列都过，余量约五成。

读法：读阶段改前 99ms = 两万次查询 + 一万次整段历史重建（含每步 JSON 解析）；
改后 16ms = 一条批量查询 + 一万次当前设置解析。算阶段 10→4ms（少了栈克隆与全栈提交）。
写阶段 244→188ms：剩下的就是每张两条行写 + 一次提交同步，盘的物理地板；
FULL 相对 NORMAL 每次提交多约 1ms（塔台 A-21 量过），含在改后数里。

## 引擎改了什么

六个批量命令（`develop.set` / `develop.reset` / `develop.paste` / `develop.sync` /
`develop.merge` / `process.update`）在真实会话上：多目标（`ids.len() > 1`）且目标未加载时，
走捷径——`read_photo_currents` 一条查询取回全批的编号/游标/步数/当前设置，
用当前设置算出新设置并产出同样的 `StoreOp::Push`，提交后不换入缓存。
已加载的照旧走内存栈；单目标命令照旧加载（交互工作集照进缓存，批量不再冲掉它；
`first_use` / 驱逐 / pinned-full 三个旧测试零改动全绿）。

等价性由构造保证：新步位置 `post_push_position` 与 `HistoryStack::commit` 同算术
（去重做尾、在游标加一处插、超 200 裁头、游标落新步）；提交前校验
（`0 <= cursor < steps` 且步号连续）恰是 `from_steps` 接受的状态，损坏的库拒绝在先、
什么都不写。未知照片仍按批内次序报 `NoPhoto`，先算好、一条事务提交、再换入的次序不变。
`commit_ops` 全推批次走 `push_many`（一个写入器、一次准备好的语句组、一条事务）；推+移混合批次走旧循环。
三段计时：`PhaseClock` 累积读/写 spans，算 = 总 − 读 − 写（自动含换入与事件）；
`Engine::execute` 在每个落库命令前清零，bench 读 `last_command_phases`。

...[truncated 10906 chars]
## 库改了什么

`HistoryWriter::push_many` 是唯一实现（`push` 转调单步，两路不漂移）：全批照片事实一条
`LEFT JOIN + GROUP BY` 查询取出；五条语句（快照查/插、重做删、步插、照片行更新）准备一次、
整批复用；游标已在连续步尾（`redo_is_empty`：`cursor+1 == steps == max+1`）时跳过重做删，
损坏态一律回落执行；同一份设置文本在一次写入器里经 `HashMap` 只查一次、只比一次字节
（事务内快照行只增，复用结论与重查相同；`inject_snapshot_key_for_test` 改键即清缓存）。
同照片在批内出现两次时用行进中游标/步数（与逐个推一致）。裁剪语义逐字旧实现
（`trim_to_limit` 只是去掉了重查 COUNT，超限才进）。计数器 `snapshot_cache_hits` /
`redo_delete_skips` 供测试断言捷径确实走了（行为测试另证结果相同）。

## 等价性是怎样证明的

引擎 `real_session_batch_fast.rs::fast_batch_matches_loaded_batch_table_for_table`：
同一会话拷两份，A 面只预载一张（余下全走捷径，含一次一载一未载的混合合并），
B 面全预载（全走内存栈），两面重跑粘贴/设参/同步/合并/重置同一序列——事件流逐个相同、
九张表转储逐字节相同。目标覆盖：一步的、有重做段的、200 步的、已加载混入的。
库 `push_many_matches_sequential_pushes_table_for_table`：逐个推与批量推（含同照片推两次）
九表相同。另有：损坏游标/断号拒绝且不写、未知照片整批不写、触发器中断原子性。

## 同步档改在哪

`schema.rs::apply_pragmas` 一行 `NORMAL`→`FULL`（唯一的写档点，注释同步）。
`create.rs` 断言改 1→2（FULL），`adopt.rs` 加 open 路断言 2。`SESSION.md` 表节与断电节同步。
perf 计时测试保留 NORMAL/FULL 两档循环（内层换 `push_many`，另断言命中 9999/跳过 10000）。

## 计时工具两处

`bench paste` 每轮行加 `read=/compute=/write=`，汇总行加三段中位数（` PASS$` 结尾不变，
演示脚本 grep 照过）；`PasteReport::Measured` 加 `phases_ms` / `phase_medians_ms`。
`bench setup` / `bench paste` 关会话后删 `-wal`/`-shm`（会话独占，缺失即过，
永不因此失败）；三个测试钉死（setup 后无日志、paste 后无日志、按库文件/按目录两路 + 缺失容忍）。

## 第 6 节验收（命令与输出）

- `cargo test -p lightamer-engine --locked`：161 通过（155 + 本波 6）。
- `cargo test -p lightamer-catalog --locked`：67 通过 + 1 忽略（60 + 本波 7；忽略的是 perf 计时）。
- `cargo test -p lightamer-cli --locked`：48 通过（47 + 本波 1）。
- `cargo test --workspace --locked`：398 通过 / 0 失败 / 1 忽略；`-- --list` 399 = 398 + 1。
- 等价性：`fast_batch_matches_loaded_batch_table_for_table`（九表转储 + 事件流全同；
  覆盖一步/重做段/200 步裁剪/已载混入）与 `push_many_matches_sequential_pushes_table_for_table` 绿。
- 一条事务：`push_many_ten_thousand_in_a_single_transaction`（提交钩子计 1，
  另断言命中 9999/跳过 10000）与 `fast_batch_is_one_transaction_and_atomic`
  （中间照片触发器拒绝，内存与库全不动）绿。
- 碰撞：`batch_collision_through_one_writer_keeps_rows_apart`（`7`/`7#2` 两行，
  步各指各行，重推复用 + 命中 1）绿；旧 `injected_key_collision_*` 照旧绿。
- 同步档 FULL：`create.rs`（建后读 2）与 `adopt.rs`（打开后读 2）绿。
- 机械盘万张：AfterMech 中位数 271.3ms、AfterMech3 中位数 305.0ms，每轮事件 10000，
  目标 600ms 过；AfterMech2（798.4，盘忙扰动）如实列出不计入。
- 内置盘万张：298.3→139.7ms，未慢反快（演示脚本内独立复核 145.3ms）。
- 无日志文件：四组 bench 会话目录 `ls` 均无 `-wal`/`-shm`（setup/paste 后各查过）。
- `Scripts/rust-history-demo.sh` 与 `Scripts/rust-session-demo.sh` 均退出 0（`demo: ALL GREEN`）。
- 六条 lint 命令退出 0；`cargo clippy --workspace --all-targets -- -D warnings` 退出 0；
  `cargo fmt --all --check` 干净；`cargo doc` 零警告。
- `cargo xtask layers` 等四项过；`Scripts/rust-apple-boundary.sh` 退出 0（7/7）。
- `rg -n 'std::fs|create_dir|read_dir|std::fs::copy|fs::copy' crates/lightamer-engine/src`
  无输出（退出 1）；封存面 `git diff --stat` 无输出。
- 临时位置与残留进程：收尾时复核（见「未做 / 未验」）。
- `git show --name-only HEAD`：见 Commit 节（只含纪律清单内路径）。

## 给用户看的汇报

改之前：在机械盘（比如 UNITEK 这种 USB 盘）上，一万张照片粘贴同一份调整，
塔台量到中位数 1067 毫秒，1 秒的门没过（这还是在每次提交不同步的 NORMAL 档下）。
改之后：同一块盘上 271 / 305 毫秒（两组干净序列），门（600 毫秒，留四成余量）过了；
同步档同时按裁决改成每次提交都同步（FULL），不断电丢数，代价含在上面的数里。
用户什么时候碰到它：图库里选中成千上万张照片，粘贴/同步调整、批量设参/重置时，
命令返回、界面刷新就是快这一下；选得少时本来就快，感觉不到。
顺带：计时工具跑完不再留日志文件，输出里能看到读/算/写各花了多少。

## 未做 / 未验

- 未做：无。任务书 0–5 节全部交付。
- 未验：非 macOS 目标（按任务书不跑）；`bench paste` 的 `UNRELIABLE` 跳过分支
  （机器一直不够忙，未亲触发——逻辑即 `load1/ncpu > 1.0` 早返）；
  `perf_10k` 默认不跑的计时测试未在安静机器上单独跑（只保证编译 + 两档循环保留；
  复审实例可顺手跑）。

## 修订记录（自审回注）

（待填：复审结论与回注。）

## Commit

（待填：初交哈希；复审回注后 amend，见 `git log -1`。）