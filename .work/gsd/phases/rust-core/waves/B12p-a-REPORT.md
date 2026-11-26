# B12′-a Report: Session Store — Tables, Migrations, Lock, Package Layout

> lane B12′-a（omp 执行）。HEAD 起始 `6c12b11a`（亲核）。
> 全程中文；代码注释与标识符英文；commit message 英文。

## 结论头

- 会话库（建表 v1、迁移架、在线备份、单写者锁、会话包目录、路径换算、
  `_meta` + `display_aux` 槽位）全部做完，17 个 crate 测试全绿，
  全工作区 208 = 192 + 16 全绿；六条不崩溃 lint、xtask 检查
  （分层/顺序同步/模块名/Apple 边界/i18n）、许可证检查、格式全绿。
- 两件顺手脚本做完：预算脚本加负载门（三分支实测），lint 合并为一遍。
- 一项未验：Linux 目标检查被环境阻塞（缺 Linux C 交叉工具链，
  与 A7b 的 gpui 豁免同类），见「未做 / 未验」。

## 交出去的接口一览（`lightamer-catalog` 公开面）

```rust
// 会话包（session.rs）
pub fn create_session(parent: &Path, name: &str, program: &str) -> Result<Session, CatalogError>;
pub fn open_session(path: &Path, program: &str) -> Result<Session, CatalogError>;
pub fn close_session(session: Session) -> Result<(), CatalogError>;
impl Session {
    pub fn root(&self) -> &Path;
    pub fn db_path(&self) -> &Path;
    pub fn connection(&self) -> &Connection;
    pub fn connection_mut(&mut self) -> &mut Connection;
    pub fn opened_unlocked(&self) -> bool;
    pub fn session_uuid(&self) -> Result<String, CatalogError>;
}
// 表与版本（schema.rs）
pub const SCHEMA_VERSION: i64; // = 1
pub const SCHEMA_V1_DDL: &str; // T-B1 原文
pub fn apply_pragmas(conn: &Connection) -> Result<(), CatalogError>;
pub fn set_schema_version(conn: &Connection, version: i64) -> Result<(), CatalogError>;
pub fn user_version(conn: &Connection) -> Result<i64, CatalogError>;
pub fn meta_get(conn: &Connection, key: &str) -> Result<Option<String>, CatalogError>;
pub fn meta_set(conn: &Connection, key: &str, value: &str) -> Result<(), CatalogError>;
pub fn display_aux_read(conn: &Connection) -> Result<DisplayAuxRead, CatalogError>;
pub fn display_aux_write(conn: &Connection, json: &str) -> Result<(), CatalogError>;
// 迁移与备份（migrate.rs）
pub const MIGRATIONS: &[Migration]; // 只有 0 → 1
pub fn open_database(db_path: &Path) -> Result<(Connection, MigrateReport), CatalogError>;
pub fn read_user_version(db_path: &Path) -> Result<Option<i64>, CatalogError>;
pub fn backup_database(source: &Connection, dest: &Path) -> Result<(), CatalogError>;
pub fn backup_file_name(db_path: &Path, from: i64, to: i64) -> Result<PathBuf, CatalogError>;
pub fn checkpoint(conn: &Connection) -> Result<(), CatalogError>;
// 锁（lock.rs，LightCraft 改造）
pub struct SessionLock; // acquire / held / dir / note / release
pub struct LockOwner; // this_process / describe
// 路径（paths.rs）
pub enum PathKind { InSession, External } // as_db / from_db
pub fn to_stored(root: &Path, path: &Path) -> Result<(PathKind, String), CatalogError>;
pub fn to_absolute(root: &Path, kind: PathKind, stored: &str) -> Result<PathBuf, CatalogError>;
// 错误（error.rs）：CatalogError（Io / Sql / Setup / InUse / SchemaTooNew / NotEmpty / Missing / BadPath）
```

下一波（B12′-b）拿 `Session::connection` 写七条会话命令的落库面；
`MigrateReport`、`DisplayAuxRead{json, corrupt}`、`opened_unlocked()` 是给它的状态位。

## 建表和迁移的做法

- 建表：T-B1 原样落成 `SCHEMA_V1_DDL`（`_meta`、`photos`、`snapshots`、
  `history_steps`、`keywords` + `photo_keywords`、`albums` + `album_photos`、
  `favorites` + 全部索引）。`snapshots` 只有 `(hash, json)` 两列，
  无引用计数（T2）；键缺省为十进制哈希、碰撞加后缀（T1，写入规则归 B13′）。
- 设置集中：`journal_mode=WAL`、`synchronous=NORMAL`、`foreign_keys=ON`
  只在 `apply_pragmas` 里写；`user_version` + `_meta` 镜像只在
  `set_schema_version` 里写；两者都只由迁移路径驱动（新建与打开收敛到
  同一入口 `open_database`），并有测试断言版本号两处相等。
- 迁移：只追加表 `MIGRATIONS`（今只有 `0 → 1`，新库从 0 起步故新建也走迁移）。
  旧库：先经 SQLite 在线备份接口留
  `<名字>.pre-migrate.<旧>-<新>.bak`（空文件免备），再逐版迁移、
  每版一个事务；备份失败则不迁移。`read_user_version` 经只读连接探查，
  新库被拒（`SchemaTooNew`，带版本号）时一个字节都不写（另有读写连接内的
  第二道臂，防两开之间的文件替换）。
- `display_aux`：只建位置。写原样存，读分三种：缺席→空（`corrupt=false`）、
  能解析→原文（`corrupt=false`）、解析不了→空 + `corrupt=true` 报给调用者。

## 锁的语义

照 LightCraft `crates/catalog/src/lock.rs`（所读树 HEAD `afa18c675`）改造，
署名头在文件首行，`NOTICE` 有 B12′-a 条目。`session.lock`（OS 独占锁，
`File::try_lock`，打开即持有关闭显式放，`Drop` 同样显式 `unlock` 不靠句柄关闭）
+ `session.lock.owner`（持有人 JSON：pid/主机名/程序/版本/时间/token，
纯提示，可缺失可损坏）。第二打开者得 `InUse`（带持有人描述）。
与上游三处不同（文件头与 NOTICE 均注明）：会话目录与文件名；
无 `OpenedFolder::vouch`（未取用的内部类型），改用同目录临时文件原子改名写
提示、按写入字节比对后删；锁文件打不开是响亮的 `Io` 错误而非静默无锁打开。
无锁文件系统：降级无锁打开，`opened_unlocked()` 上报。强杀：OS 收回锁，
残留文件不挡重开（持有人文件下次加锁覆盖）。

## 唯一标识的选型及理由

会话 UUID：读 `/dev/urandom` 16 字节，置 v4 版本/变体位，hex 拼 `8-4-4-4-12`。
理由：macOS 与 Linux 都有该随机源，标准库两行即读，
零新增依赖（`uuid` crate 会拖进 `getrandom` 链，无谓）；
随机性全部来自内核，无手写随机数。`session_uuid()` 读 `_meta`，
新建/采用时缺席才 mint，不覆盖既有身份。

## 新增依赖与允许清单

直接依赖（`crates/lightamer-catalog/Cargo.toml`）：

- `rusqlite 0.43.0`（`default-features = false` + `bundled` + `backup`，
  T-B4 一字不差；另有同行 dev 依赖供集成测试直读库用）
- `serde 1.0.229`（`derive`）、`serde_json 1.0.154`（持有人 JSON + aux 校验）

锁文件新增 5 个包（`git diff Cargo.lock`）：`rusqlite 0.43.0`（MIT）、
`libsqlite3-sys 0.40.0`（MIT）、`fallible-iterator 0.3.0`（MIT/Apache-2.0）、
`fallible-streaming-iterator 0.1.9`（MIT/Apache-2.0）、`vcpkg 0.2.15`
（MIT/Apache-2.0，构建期）。5 条表达式全在 `Scripts/licenses-allow.txt` 内
（`MIT`、`MIT/Apache-2.0` 行），该文件零改动；`docs/LICENSE-AUDIT.md`
追加 5 表行 + §13 采用记录。`Scripts/check-licenses.sh`：
`allow=852 exception=1 fail=0`，退出 0。

`result_large_err` 在 crate 根 allow（附理由：错误是冷路径；
box 会丑化 B12′-b 要 match 的公开面）。除此之外六条不崩溃 lint 零豁免。

## 冷构建的四个数

`Scripts/rust-budget.sh --cold`（`budget_exit=0`，overall PASS；
机器空闲，全程无 UNRELIABLE，各量前负载/守卫行见日志）：

- 核心冷构建（workspace 减界面）：**67s**（门 ≤360s）PASS
  （A7b 基线 73s：rusqlite 的 bundled C 编译已含在内，余量仍大）
- 界面冷构建（共享依赖已暖）：**228s**（门 ≤900s）PASS（A7b 基线 173s）
- 界面重新构建（touch 一文件）：**155s**（门 ≤180s）PASS，
  贴门（86%）：该项本就对负载敏感（A9 量到 4s/63s/122s/267s 四散），
  本波负载门专为它而设，忙时报 UNRELIABLE 不判失败
- `check lightamer-iop-color`：**11s**（门 ≤40s）PASS
- 另：界面发行版二进制 **17786416B**（≈17.0MB，门 ≤80MB）PASS；
  `target/` 6881MB（门 ≤20GB）

注：第一轮 `--cold` 因取输出用了 `tail` 丢了前半数字且退出码取的是管道尾，
另见 overall FAIL（数字已丢，无法归因到哪一项），作废；以上是完整重跑的数。

## 第 10 节验收（命令与输出）

- `cargo test -p lightamer-catalog --locked`：17/17 绿（1 lib + 16 新增集成；提交时 16/16，自审回注 R2 加 1 个）。
  §6 每条对测试：建包全貌 `create_builds_full_layout`；非空拒绝
  `create_refuses_nonempty_root`（+ 空目录填齐 + 坏名 + 缺失路径
  `missing_path_opens_nothing` + UUID 互异）；采用不动文件
  `adopt_leaves_existing_files_untouched`（+ 错名库拒绝
  `misnamed_database_path_is_refused`，R2）；双开被拒 `second_opener_gets_in_use_with_owner`；
  提示缺失/损坏 `missing_or_corrupt_owner_note_still_opens`；强杀重开
  `reopen_after_kill`（子进程只起自己的测试程序）；迁移
  `migrate_old_database_keeps_rows_and_leaves_backup`；新版拒绝
  `newer_database_refused_without_a_write`（字节逐位相同）；备份一致性
  `backup_captures_uncheckpointed_rows`；aux 三态
  `display_aux_roundtrip_missing_and_corrupt`；关包 checkpoint
  `close_checkpoints_and_reopen_keeps_data`（UUID 跨重开不变）；路径
  `path_conversions_roundtrip_and_refuse_escapes`；T1/T2 表结构
  `schema_matches_t1_t2_shape`。
- `cargo test --workspace --locked`：208 = 192 + 16 全绿，0 失败
  （`grep -c FAILED` = 0；67 个 `test result: ok`；提交时 207，自审回注 R2 加 1 个）。
- Linux 目标检查：见「未做 / 未验」（环境阻塞，有证据）。
- 六条不崩溃 lint（§10 原命令，
  `cargo clippy --workspace --all-targets --locked -j6 -- -D clippy::indexing_slicing -D clippy::unwrap_used -D clippy::expect_used -D clippy::panic -D clippy::todo -D clippy::unimplemented`）：退出 0（1m36s）。
- `cargo xtask layers`：`OK: 29 crates, no layering violations.`，
  catalog 直接依赖只有 `rusqlite 0.43.0` / `serde 1.0.229` / `serde_json 1.0.154`
  （`cargo tree --depth 1`，外部依赖不进分层图）；
  `check-order-sync`（97 模块 OK）、`check-no-iop-names`
  （97 名、4 根干净）、`check-apple-boundary`（29 crate 169 文件零违反）、
  `check-i18n`（B17 前无表，对照跳过）全过。
- `Scripts/check-licenses.sh`：`allow=852 exception=1 fail=0`，退出 0；
  `licenses-allow.txt` 零改动（`git diff --stat` 空）。
- `Scripts/rust-budget.sh --cold`：见上节。
- `Scripts/rust-ci-lite.sh`：退出 0，`ALL GREEN`（复跑 5m49s，208 测试；首轮 11m55s/207 在 R1/R2 前；合并后 lint 只跑一遍，预算 PASS）。
- `rg -n 'std::fs|File::|create_dir|read_dir' crates/lightamer-engine/src crates/lightamer-history/src`：零输出（退出 1）。
- `rg -n 'refcount|reference_count' crates/lightamer-catalog`：零输出（退出 1）。
- 引擎/历史/注册表/模块桩 `git diff --stat 6c12b11a -- crates/lightamer-engine crates/lightamer-history crates/lightamer-registry 'crates/lightamer-iop-*/src/modules'`：零输出。
- LightCraft 署名：`lock.rs` 首行 `Derived from lightcraft crates/catalog/src/lock.rs（commit afa18c675）` + `NOTICE` B12′-a 条目。
- 测试无残留：`/tmp/lightamer-catalog-test-*` 零残留；`git status` 无测试文件。
- 提交路径：`git show --name-only` 30 文件零越界（见 Commit 节）。

## 给用户看的汇报

做成了什么：照片会话的"地基库"落好了——建会话/Open已有文件夹/关会话；
库表、版本升级（升级前自动备份）、单写者锁（双开被拒并告诉你谁在用）、
路径规则、崩溃后重开不丢已提交的数据。下一波接七条会话命令后即可演示。

现场演示（本波是库函数，无 CLI，都在临时目录里跑，不碰真实照片）：

- `cargo test -p lightamer-catalog --locked`：17 个行为测试全绿，
  每个名字即一条可讲的行为（双开被拒、强杀重开、迁移留备份等）。
- `sqlite3` 打开任一上面的库（或 `fixtures/session/` 的夹具）看表结构。
- 预算脚本 `Scripts/rust-budget.sh`（负载高时报"测不准"不判失败）。

还没做：七条会话命令与 CLI（B12′-b）；历史落库（B13′）；备份/恢复/校验命令；
Linux 目标检查（本机缺交叉 C 工具链，待环境）。

## Commit 与文件清单

提交 `52e6c4394e443244913e41842ac9ea9d83dd2bf5`
（`feat(rust): B12'-a session store (tables, migrate, lock, layout)`，
`refs #32`，零 push）。`git show --stat`（30 文件，全在纪律清单内）：
REPORT +231、review.log +61、Cargo.lock +47、NOTICE +16、
三脚本（budget +62−30、ci-lite +1−2、test +2−2）、crates/README 1 行、
catalog（Cargo.toml +10、7 src、8 tests）、`docs/SESSION.md` +120、
`docs/LICENSE-AUDIT.md` +25、`fixtures/session/`（README + 3 夹具）。
注：本节落定后为把复审结论装进同一 commit 又 amend 了一次，
最终哈希以完工消息与 `git log -1` 为准（A2/A8 同款 skew，内容只差本节）。

## 复审结论头

`PASS / 0 error + 2 minor`（`.work/gsd/phases/rust-core/waves/B12p-a-review.log`，
复审对象 `bac7b050`，2026-11-26 21:30–22:10）。
复审重跑了第 10 节（16/16、207 全绿、六 lint、xtask×5、许可证、两 rg、
零 diff、Linux 阻塞证据）、T-B1 逐表逐列对照（DDL 归一化后逐字节等）、
迁移/备份/未来版夹具实测、T1/T2、测试卫生、提交边界、锁与署名抽查。
M1（`created_by` 取库身份而非调用程序）与 O1（错名库静默忽略）已回注修订，
见下；M2 即本节回填；O2–O5 为观察项（设计如此/复审范围注记），不改。

## 修订记录（自审回注）

- R1（M1）：`ensure_session_meta` 改取调用程序名写 `created_by`
  （`{program} {version}`，T-B1 `<app+版本>`），`session.rs`；
  `create_builds_full_layout` 加断言。`LockOwner.version` 维持库版本
  （与 LightCraft 原文一致）。
- R2（O1）：`open_session` 传库文件时校验文件名与目录匹配，
  错名报 `BadPath`（零副作用，先于建目录/加锁），`session.rs` +
  `docs/SESSION.md` 一行；新测试 `misnamed_database_path_is_refused`。
  全工作区总数变为 208 = 192 + 16。
- R1/R2 重验：`cargo fmt`、`clippy -p lightamer-catalog`（六 lint）
  全绿，`cargo test -p lightamer-catalog` 17/17，
  `cargo test --workspace` 208 全绿 0 失败。

## 未做 / 未验

- 未做：无。本波任务书内全部交付。
- 未验：`cargo check --workspace --all-targets --target x86_64-unknown-linux-gnu --locked`
  及 crate 级同命令。证据：crate 级命令失败在 `libsqlite3-sys` 构建脚本
  `failed to find tool "x86_64-linux-gnu-gcc"`（bundled 要为目标编 C，
  本机无 Linux 交叉 C 工具链）；且该 workspace 命令在基线已红
  （A7b VERIFY：`wayland-backend` 构建脚本同因）。Rust 侧可移植证据：
  crate 内零 `cfg(target`/`cfg(unix)` 门，零平台独占 API
  （`File::try_lock` 是 1.89+ 稳定标准库，`/dev/urandom` 双平台皆有，
  `rusqlite`/`serde` 系全跨平台）。待有交叉工具链或 Linux 机后重验。
