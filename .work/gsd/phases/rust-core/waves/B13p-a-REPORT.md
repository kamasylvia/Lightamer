# B13′-a Report: Photo History in the Session Database

> lane B13′-a（omp 执行）。HEAD 起始 `9e1cc1b187d534d7129038a9e22e3e6c82fc7ed4`（亲核）。
> 全程中文；代码注释与标识符英文；commit message 英文。

## 结论头

- 会话库的历史写路径全交付：照片最小登记、单事务多推的写入器、游标移动、
  读回重建、孤儿回收、崩溃语义；包测试 59/59（+27 新，另 1 ignored bench），
  全工作区 282+1=283（255+28）。
- T-B1 六条写路径不变量逐条有测试钉死；万张单事务经提交钩子数得恰一次提交；
  强杀两种形状（已提交全留、未提交全丢）都对。
- 万张粘贴库侧耗时中位数 NORMAL 334.4ms / FULL 337.5ms（门 1s，约占三分之一）。

## 交出去的接口一览（`lightamer-catalog` 新增公开面，写给 B13′-b）

```rust
// 照片的最小登记（photos.rs）
pub struct PhotoRecord { pub id: i64, pub uuid: String, pub path: String, pub kind: PathKind }
pub fn register_photo(conn: &mut Connection, root: &Path, path: &Path, file_name: &str, file_size: Option<i64>) -> Result<PhotoRecord, CatalogError>;
pub fn find_photo_by_uuid(conn: &Connection, uuid: &str) -> Result<Option<PhotoRecord>, CatalogError>;
pub fn find_photo_by_id(conn: &Connection, id: i64) -> Result<Option<PhotoRecord>, CatalogError>;
pub fn list_photo_uuids(conn: &Connection) -> Result<Vec<String>, CatalogError>;
// 历史的写接口（history_store.rs）
pub const SEED_LABEL: &str; // "seed"，第 0 步标签（见下「给 B13′-b 的三件事」F1）
pub struct PushOutcome { pub photo_id: i64, pub idx: i64, pub snapshot_hash: String, pub collided: bool, pub cursor: i64, pub steps: i64 }
pub struct MoveOutcome { pub cursor: i64, pub steps: i64, pub settings_json: String }
pub struct HistoryStepRead { pub idx: i64, pub label: String, pub snapshot_hash: String, pub settings_json: String }
pub struct HistoryRead { pub photo_id: i64, pub cursor: i64, pub steps: Vec<HistoryStepRead> }
pub struct PushStats { pub snapshot: Duration, pub steps: Duration, pub photos: Duration, pub pushes: u64 }
impl HistoryWriter<'_> {
    pub fn begin(conn: &mut Connection) -> Result<HistoryWriter, CatalogError>;
    pub fn push(&mut self, photo_id: i64, label: &str, canonical_json: &str) -> Result<PushOutcome, CatalogError>;
    pub fn commit(self) -> Result<(), CatalogError>; // 不调则 Drop 回滚
    pub fn stats(&self) -> &PushStats;
    pub fn inject_snapshot_key_for_test(&mut self, key: &str); // 只给测试用
}
pub fn push_step(conn: &mut Connection, photo_id: i64, label: &str, canonical_json: &str) -> Result<PushOutcome, CatalogError>;
pub fn move_cursor(conn: &Connection, photo_id: i64, target: i64) -> Result<MoveOutcome, CatalogError>;
pub fn read_history(conn: &Connection, photo_id: i64) -> Result<HistoryRead, CatalogError>;
pub fn orphan_snapshot_hashes(conn: &Connection) -> Result<Vec<String>, CatalogError>;
pub fn delete_orphan_snapshots(conn: &Connection) -> Result<u64, CatalogError>;
// 错误新增（error.rs）：UnknownPhoto(i64)、DuplicatePhoto{path,kind}、
// CursorOutOfRange{photo_id,target,steps}、BadSettings{reason}，各一句人话。
```

用法两句：单命令 `push_step` 一步一事务；批量粘贴 `begin` 后循环 `push`
再一次 `commit`（一万张各一步即此形，已测）。`push` 先解析 JSON 取处理版本号
（坏文本直接 `BadSettings`，一个字节不写），再读写库。

## 照片的标识和登记的规矩

- 对外标识是 `uuid`（文本，`new_uuid_v4` 与会话标识同一函数 mint，
  现为 `pub(crate)` 共享）；整数 `id` 只在库内用。
- 登记（`register_photo`）一事务写三样：照片行（路径经 `to_stored` 换算，
  文件名/文件大小入列，检索列留空给 B15）、默认设置的快照行（已存在则复用）、
  第 0 步（标签 `seed`，默认快照）；照片行游标 0、当前快照与处理版本号镜像
  指向该步，镜像取自默认设置内的版本号。
- 重复登记的规矩：同一存路径（换算后的 `(path_kind, path)`）第二次登记
  被拒绝，`DuplicatePhoto`，什么都不写。拼写不同但换算结果相同的路径
  （如多余的 `sub/..`）视为同一张，同样拒绝；`kind` 不同则为两张。

## 一步在事务里做了什么

`HistoryWriter::push` 按序做（任一步失败则本次 `push` 返回错误，已在事务里的
前序 `push` 仍可提交；`commit` 前丢弃 writer 则整批回滚）：

1. 解析传入的规范 JSON 取处理版本号（坏文本 `BadSettings`，不碰库）；
   查照片行（无此照 `UnknownPhoto`，不碰库）。
2. 写快照（`store_snapshot`，见下节）。
3. 删游标之后的重做步；在游标加一处插新步；超 200 步从最旧裁，
   余步升序重编 0..n（升序逐行改主键不冲突），游标同移。
4. 一条 `UPDATE photos SET cursor, current_hash, process`（镜像恒显式写，
   不依赖列默认值）。
5. 返回 `PushOutcome`（步键 `(photo_id, idx)`、快照键、有无新碰撞、
   新游标与步数），三段耗时累进 `PushStats`。

`move_cursor` 只跑第 4 步那条 `UPDATE`（游标/当前快照/镜像同写），不增删步；
目标 `<0` 或 `>=步数` 报 `CursorOutOfRange`，只做过读、无一写。
`read_history` 按编号读回每步标签与快照文本，外加游标。

## 碰撞和孤儿各自怎样处理

- 碰撞（T1）：快照键缺省为规范 JSON 的十进制 FNV-1a（与
  `PhotoSettings::hash64` 同偏移/同素数/同折叠，实现在
  `snapshot_key_for`，测试 `snapshot_key_matches_hash64_decimal` 把三组
  非默认设置的落键与 `hash64_decimal()` 逐值钉死，默认设置的落键另由
  登记测试逐字段钉死）。键命中逐字节比对：相同复用；
  不同即碰撞，依次试 `#2`、`#3`…直到空位或字节相同（复用旧的碰撞行）。
  `collided=true` 当且仅当本次存了新的后缀行（复用任何旧行都报 false，
  调用者记日志不刷屏）。测试注入口
  `inject_snapshot_key_for_test`（公开方法，文档写明只给测试用——集成测试
  在 crate 外，`#[cfg(test)]` 不可见，只能如此）。
- 孤儿（T2）：定义唯一——`orphan_snapshot_hashes` 一条查询
  （无步引用、非任何照片当前），校验的 `orphan_snapshot` 项已改调它，
  两处定义合一。`close_session` 先开事务清孤儿、再 checkpoint、再放锁；
  收集失败同样放锁并返回错误（与 checkpoint 失败同处置）。

## 性能那个数（两档、三段、三遍中位数）

命令：`cargo test -p lightamer-catalog --locked --test perf_10k -- --ignored --nocapture`
（默认忽略；负载门沿 `rust-budget.sh load_busy`：load1/核数 > 1.0 报
UNRELIABLE 跳过。机器安静：`load averages: 2.04 2.31 2.67`，10 核，
2.04/10 = 0.2。）

```text
perf: sync=NORMAL run=1 snapshot=37.5ms steps=150.5ms photos=69.9ms total=334.4ms
perf: sync=NORMAL run=2 snapshot=37.3ms steps=149.8ms photos=69.6ms total=329.4ms
perf: sync=NORMAL run=3 snapshot=38.1ms steps=152.9ms photos=70.8ms total=340.0ms
perf: sync=NORMAL median snapshot=37.5ms steps=150.5ms photos=69.9ms total=334.4ms
perf: sync=FULL run=1 snapshot=38.0ms steps=151.6ms photos=70.4ms total=339.3ms
perf: sync=FULL run=2 snapshot=38.1ms steps=152.4ms photos=71.3ms total=336.4ms
perf: sync=FULL run=3 snapshot=38.0ms steps=151.9ms photos=70.6ms total=337.5ms
perf: sync=FULL median snapshot=38.0ms steps=151.9ms photos=70.6ms total=337.5ms
```

读法：场景 = 登记一万张（空占位文件，搭建不计时）后一次推一万步、
只提交一次（粘贴同份调整，快照去重后库内 2 行）。三段 = 写快照
（键查/比对/插入）、写历史步和裁剪、更新照片行；total = 计时起点
（`begin` 返回之后）到 commit 返回（`begin` 本身约 µs 级，未计入）。
门 1s：两档中位数约 0.34s，占门三分之一，不绕路。
total 与三段之和差约 76ms = 逐推 JSON 解析（取处理版本号）+ commit 开销，
如实列出。FULL 与 NORMAL 只差约 3ms（单事务只多一次同步）。

## 第 7 节验收（命令与输出）

- 守卫（构建前）：`Scripts/machine-guard.sh` →
  `GUARD PASS (heavy=0 free=69% swap=?M disk=?GB)`，exit 0。
- `cargo test -p lightamer-catalog --locked`：59 passed / 0 failed
  （32 旧 + 27 新），另 1 ignored（bench）。任务书「测试」一节与测试名的对应：
  - 不变量①：`push_changes_snapshot_step_and_photo_row_in_one_transaction`
    （三处都变）、`failed_pushes_roll_back_with_the_writer`
    （好坏混推后丢弃 writer，三处都没变）、
    `writer_stays_usable_after_a_failed_push`（坏后好照提交）。
  - 不变量②：`move_cursor_updates_only_the_photo_row`（步表全行 dump 前后相同）。
  - 不变量③：`past_200_steps_oldest_trim_and_renumber_from_zero`
    （206 步裁 6，0..199 连续，游标 199，首步 `step-6`）、
    `trimmed_snapshots_become_orphans_and_close_collects_them`
    （6 孤儿关会话后清零，步 200 行、快照 200 行）。
  - 不变量④：`photo_row_mirrors_cursor_step_after_pushes_and_moves`
    （每次推/移后 `assert_mirror`）。
  - 不变量⑤：`non_default_process_mirror_matches_settings`
    （process=2 的设置镜像为 2，来回移动仍对）。
  - 不变量⑥：`injected_key_collision_stores_two_rows_and_reports`
    （两行各存原文、步各指各行、第二次报碰撞，重推复用不报）、
    `third_distinct_value_extends_suffix_chain`（`7/7#2/7#3`）。
  - 登记：`register_writes_photo_row_seed_step_and_default_snapshot`
    （行/步/快照逐字段）、`find_by_uuid_and_id_round_trip`、
    `list_uuids_matches_registrations_in_order`、
    `duplicate_path_is_refused_and_writes_nothing`、
    `register_external_absolute_path`。
  - 读回：`read_returns_steps_labels_and_cursor_for_rebuild`
    （步数/标签/游标对；`new+commit+goto` 重建栈与参照栈 `assert_eq!` 全等，
    当前设置规范 JSON 逐字节等）。
  - 一万张单事务：`ten_thousand_photos_one_step_each_in_a_single_transaction`
    （提交钩子数得恰 1 次提交；一万照片行游标与当前快照全对；
    行数 `(10000, 20000, 2)`）。
  - 孤儿：`close_collects_only_orphans`（关前 2 孤儿、关后 0，
    被引用的 `默认/A3/B1` 三行全在，两史完整）、
    `verify_reports_orphan_count_matching_query`
    （`orphan_snapshot` 项数 = 查询数 = 2，且无悬空引用项）。
  - 崩溃：`killed_after_commit_keeps_exactly_committed_steps`
    （子进程提交 3 步后被强杀，父见 `[seed,+3]`、游标 3、快照 4 行）、
    `killed_before_commit_loses_the_open_transaction`
    （子进程持未提交事务被强杀，父只见 `[seed]`、快照 1 行）。
  - 另：`push_step_helper_commits_a_single_step`、
    `redo_steps_drop_on_push_after_undo`、
    `snapshot_rows_dedupe_across_photos`、
    `snapshot_key_matches_hash64_decimal`、
    `cursor_target_out_of_range_writes_nothing`、
    `bad_settings_text_is_refused_before_any_write`。
- `cargo test --workspace --locked`：282 passed / 0 failed / 1 ignored；
  `-- --list | grep -c ": test$"` = 283 = 255 + 28（27 跑 + 1 忽略）。
- 封存面：`git diff --stat 9e1cc1b1 HEAD -- crates/lightamer-history
  crates/lightamer-engine apps crates/lightamer-registry
  'crates/lightamer-iop-*/src/modules' crates/lightamer-apple` 无输出。
- `rg -n -i 'refcount|reference_count' crates/lightamer-catalog` 无输出（exit 1）。
- `cargo xtask layers` → `OK: 29 crates, no layering violations.`
  （catalog 新增 `lightamer-history` 边，L3→L2 合法）；
  `check-order-sync` → `OK (97 modules…)`；
  `check-no-iop-names` → `OK (97 names, 4 roots clean)`；
  `check-apple-boundary` → `OK: 29 crates, 188 rust files, no Apple-boundary violations.`；
  `Scripts/rust-apple-boundary.sh` → `ALL GREEN`（7/7）。
- 六条 lint：`cargo clippy --workspace --all-targets --locked -j6 --
  -D clippy::indexing_slicing -D clippy::unwrap_used -D clippy::expect_used
  -D clippy::panic -D clippy::todo -D clippy::unimplemented` exit 0；
  另 `cargo clippy --workspace --all-targets --locked -j6 -- -D warnings`
  exit 0（更严）；`cargo fmt --all --check` 干净；
  `RUSTDOCFLAGS="-D warnings" cargo doc --workspace --no-deps --locked` exit 0。
- `Scripts/rust-session-demo.sh` exit 0（`demo: ALL GREEN`）。
- 性能：见上节（命令 + 两档 × 三遍 + 中位数）。
- 残留：`git status --porcelain` 无测试文件；系统临时目录无本波 tag
  （`lightamer-catalog-test-*-{register,…,crash-*,perf-*}` 零命中），
  且本波测试前后对照残留集完全相同（4 个 B12′ 时代旧目录属他会话/残留，
  未碰）；`/tmp` 零命中。
- `git show --name-only HEAD`：见 Commit 节（只含纪律清单内路径）。

## 给 B13′-b 的三件事（执行中发现，如实移交）

- F1（必议）：任务书说引擎初始步标签是 `seed`，实测历史模型是 `import`
  （`history.rs:26 INITIAL_LABEL`，引擎 `develop.rs:550` 断言
  `["import", "develop.set"]`）。本波按任务书字面在库里写 `seed`
  （`SEED_LABEL` 单常量），差异面只有第 0 步标签：重建测试比较的两座内存栈
  都经 `HistoryStack::new`（同为 `import`）故全等成立，另断言库中第 0 步
  标签确为 `seed`。B13′-b 对齐二选一：改 `INITIAL_LABEL` 为 `seed`
  （动历史模型 + 引擎既有断言），或把 `SEED_LABEL` 翻为 `import`
  （改一常量 + 本波两处断言）。请塔台拍板。
- F2：`rusqlite` 的 `hooks` 特性只加在 catalog 的 dev 依赖上（`hooks=["wal"]`，
  `wal=[]`，零新包，`Cargo.lock` 只多 `lightamer-history` 一条边），供单事务
  测试数提交用；产线不依赖它。B13′-b 若要在产线用钩子，把该特性升到主依赖。
- F3：serde 派生 struct 接受数组按序填充——`PhotoSettings::from_json("[1,2]")`
  成功（`format_version=1, process=2`），不是坏输入。本波 `BadSettings`
  测试改用真坏输入（`{nope` / `2` / `null` / `"s"`）。B13′-b 按 T5 传规范
  JSON，不受影响；记一笔免后人踩。

## 给用户看的汇报

做成了什么：照片的修改历史有了落库的地方——登记一张照片，库里就有它的
第 0 步；每推一步，快照、历史步、照片行三处在同一个事务里一起变；
撤销/重做/跳转只动游标；写多了自动裁到 200 步并重编号；哈希撞了另存一行
绝不混淆；关会话时清掉没人要的快照；进程被强杀，已提交的一步不少、
没提交的一步不多。一万张各粘贴一步，库侧约 0.34 秒（门 1 秒）。

还没做：把这些接到引擎命令上（B13′-b，后一半）；照片导入（B15）；
第 0 步标签 `seed` 与内存 `import` 的对齐待拍板（见 F1）。

## Commit

首提交 `d656d46273`（`feat(rust): B13'-a photo history in the session database`，
`refs #32`，16 文件 +2341/-21，零 push）。为把复审结论装进同一 commit 又
amend 了一次（加 `B13p-a-review.log`、本报告的复审节与修订记录、两处措辞修正），
最终哈希以 `git log -1` 为准（B12′ 同款 skew，内容只差本节）。
`git show --name-only`（16 + review.log = 17 文件，全在纪律清单内）：
REPORT.md、review.log、Cargo.lock、crates/README.md（一行）、docs/SESSION.md
（纯追加一节）、catalog（Cargo.toml + src：error/lib/session/verify 改 4 +
history_store/photos 新 2；tests：common 改 1 + photos/history_store/
history_crash/perf_10k 新 4）。

## 复审结论头

`PASS / 0 error + 4 minor`（`.work/gsd/phases/rust-core/waves/B13p-a-review.log`，
复审对象 `d656d46273`）。11 项验收全亲手重跑通过（包测试 59+1、全工作区
282+1=283、封存面空、rg 空、四 xtask、边界脚本 7/7、六 lint、fmt、文档、
演示全绿、提交边界）；T-B1 六条逐条核机制；碰撞两行字节各存、步各指各行、
`collided` 恰新碰撞报；重建 `assert_eq!` 整栈全等 + 当前设置逐字节；
关时 GC 只清孤儿（被引用行 JOIN 读回 + 计数联合证明）；万张提交钩子数得恰 1。
复审复测性能（负载 3.17/10 核）：NORMAL 中位数 346.9ms、FULL 356.6ms，
比报告高约 4–6%、形状一致，远低于 1s 门。

## 修订记录（自审回注）

- R1（minor-1）：报告"四组设置"改"三组非默认设置 + 默认另由登记测试钉死"
  （`snapshot_key_matches_hash64_decimal` 实为 `1..=3`）。
- R2（minor-2）：报告 total 口径改"`begin` 返回之后到 commit 返回"
  （`begin` 本身约 µs 级未计入）。
- R3（minor-3）：回填 Commit/复审结论头/修订记录三节，随收口 amend 落入同一 commit。
- R4（minor-4，挂后波，不在本波实现）：verify 不校验
  `current_hash == step(cursor).snapshot_hash` 等式——同 process 的错挂
  current_hash 可穿过 verify（悬空仍被 `dangling_reference` 抓住）。
  本波写侧恒单条 UPDATE 且 `assert_mirror` 逐测钉死，等式在产线内成立；
  加一项 verify 等值检查属校验语义扩张（B12′-b 的面），超出任务书 §5
  （只要求孤儿数与悬空引用），故只记录不实现，请后波（B13′-b/B15）立项。

## 未做 / 未验

- 未做：无。任务书 1–6 节全部交付。
- 未验：无。验收清单逐条有命令与输出；非 macOS 目标按任务书不跑。
