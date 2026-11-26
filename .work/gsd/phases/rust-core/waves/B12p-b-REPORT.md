# B12′-b Report: Seven Session Commands, Backup/Restore Jobs, CLI, Demo

> lane B12′-b（omp 执行）。HEAD 起始 `4dde1955620e5eb11a94ea4a443620818ffbe7e0`（亲核）。
> 全程中文；代码注释与标识符英文；commit message 英文。

## 结论头

- 七条会话命令全登记（注册表 13→20），真实会话、只读校验、备份/恢复/扫描三作业、
  模板、CLI 会话文件 + `--hold`、演示脚本全交付；255 测试全绿（208 + 47）。
- `cargo fmt --check`、`clippy -- -D warnings`、文档零警告、四 xtask 门、边界脚本、
  演示脚本全绿；`rust-ci-lite.sh` 全绿（见验收节）。
- 两处执行中发现并修掉的设计缺口：`job.cancel` 会话门（restore 无会话时不可取消）、
  restore-open 失败不清目标；一起 CLI 输出缓冲致演示误判（改流式输出）。

## 七条命令（各一行）

- `session.new(name, parent)`：建会话包并打开；已开会话时拒绝。
- `session.open(path)`：打开会话文件夹或库文件（就地补齐），并启动失联扫描作业；已开时拒绝。
- `session.close()`：合并 WAL，释放锁；无真实会话时拒绝。
- `session.verify()`：只读校验，返回 findings 报告；无真实会话时拒绝。
- `session.backup(dest, include_trash?)`：校验目标后启动备份作业，返回作业标识。
- `session.restore(backup, dest)`：校验两端后启动恢复作业，拷回后按 open 流程打开；已开时拒绝。
- `template.save(name)`：存相册和收藏的结构（无任何照片）到模板目录。

七条都不记历史步；参数清单见 `lightamer-cli commands <id>`（注册表测试逐参数钉死）。

## 真实会话在引擎里

`Engine` 的会话槽是三态：`None`（ fresh/close 后）/ `Draft`（`open_draft`，内存照片，
测试与对照保留）/ `Real(Session)`（握着前一半的锁 + 数据库连接）。一次只开一个。
`has_session()` 覆盖草稿与真实（旧命令行为不变）；新门分两档：`new/open/restore`
要求无会话（`Disabled` + "already open"），`close/verify/backup/template.save`
要求真实会话（无会话 `NoSession`，草稿 `Disabled` + "no real session"）。
引擎程序名默认 `lightamer-engine`，CLI 设为 `lightamer-cli`（持有人提示与
`created_by` 用它）。打开真实会话后引擎照片为空是正常的（B15 导入）。
新错误变体 `CommandError::Store { cmd, reason }` 包 catalog 的拒绝（含 `InUse`
持有人描述），一行人话。

## 作业的边界

命令只做有界活：`backup/restore` 命令内只做目标校验（空目录检查经 catalog，
引擎零文件操作），然后返回作业标识；`open` 同步打开后返回扫描作业标识。
三作业跑在池线程上，用自己的数据库连接（引擎连接不出引擎线程），进度经
`report`、完成经事件；`JobCtx::fail` 是新增的无 panic 失败通道（原只有
panic 能到 `Failed`，而 panic 在本 crate 禁用）。取消：`job.cancel`
（作业是引擎级的——为此把它的 `needs_session` 从 true 改为 false，
否则无会话的 restore 不可取消；A7a 的 cancel 测试不受影响）。
`collect()` 内收 restore 投递：worker 先发 `Session`（`Send`，编译器亲证）
再返回，`collect` 看到完成即安装 + 补扫描作业；中途另开了会话则关掉送达的不覆盖。
备份/恢复取消或出错清自己建的目标（自建根整个删，预给空根只清孩子）；
恢复的 open 半段失败同样清（`restore_and_open`，见修订记录 R2）。

## 校验查什么

`session.verify` 只读（`SELECT` + `integrity_check`，`&Connection` 方法之外无其它调用）：
完整性、孤儿快照（info，无修法）、悬空引用（error）、游标越界、process 镜像、
`display_aux` 解析（坏则 warning，修法 `display.set`）、存路径换算、文件存在性、
超限（照片 >1000 即 `VERIFY_INLINE_PATH_LIMIT`，逐文件项交后台并报 info）、
无锁提示（info）。warning/error 必带修法命令标识（未登记的为以后波次，
文档点名）；单项 200 条封顶，超出折叠。测试断言校验前后库文件字节相同。

## 主机名怎么修的

`lock.rs` 的 `host_name()` 原只读环境变量与 `/etc/hostname`（macOS 两无）。
加第三 fallback：`hostname(1)`（先 `/bin/hostname`，再 PATH），失败回空；
结果 `LazyLock` 进程内缓存（`describe()` 每次比较不再重复问）。
零新依赖。测试 `owner_note_carries_a_nonempty_host_on_this_machine` 钉住本机非空；
演示第 6 步拒绝信息里出现 `(process 20769 on this computer)` 为实证。

## 修订记录（执行中发现并修掉）

- R1：`job.cancel` 的 `needs_session: true` 使无会话的 restore 作业不可取消。
  改为 false（作业是引擎级的；注释写明理由）。A7a 的 cancel 测试与坏参数表不受影响。
- R2：restore 拷完但 open 失败（超前版本库）时目标残留。新增
  `catalog::restore_and_open`（拷 + 开 + 开失败清目标），引擎作业改调它；
  加两测试（垃圾库、999 版库，均 `Failed` + 目标 absent）。
- R3：演示第 6 步误报"双开被接受"。根因是 CLI 跑完才一次性打印：
  `--hold` 的 keeping 行 20 秒后才落盘，轮询看到时锁已放。`run_file` 改流式
  sink（每行产生即送达；二进制打印并 flush），加流式测试；演示重跑全绿。
- R4（复审回注）：minor-1 commit message 一词之改："lockfile gains only the
  engine->catalog edge" → "lockfile gains two edges (engine->catalog, engine
  dev->rusqlite), zero new packages"，随收口 amend 落入同一 commit。
  另注：复审数引擎 rg 命中 15，我数 16——重数确认 16（develop.rs 8 + engine.rs 8），
  逐行全为基线 `develop.copy` 行，属复审计数口径差，结论一致，无代码动作。
## 第 10 节验收（命令与输出）

- 起始 HEAD：`git log -1 --format='%H %s'` →
  `4dde1955620e5eb11a94ea4a443620818ffbe7e0 docs(rust-core): add the B12'-b brief`。
- 守卫（构建前）：`Scripts/machine-guard.sh` →
  `GUARD PASS (heavy=0 free=74% swap=?M disk=?GB)`，exit 0。
- `cargo test -p lightamer-engine --locked`：68/68 绿（44 单测 + 13 会话命令 +
  11 会话作业）。`cargo test -p lightamer-catalog --locked`：32/32 绿
  （17 旧 + 备份 6 + 校验 4 + 扫描 2 + 模板 2 + 主机名 1）。
  任务书点名项与测试名的对应：
  - 建包握锁 / 就地补齐 / 三拒绝：`session_new_builds_package_and_holds_lock`、
    `session_open_adopts_existing_folder_in_place`（+ `session_open_accepts_database_file_path`）、
    `open_new_restore_refuse_while_session_open_with_reason`。
  - 关释放锁无 WAL：`session_close_releases_lock_and_leaves_no_wal`。
  - 校验：`session_verify_reports_nothing_on_healthy`、
    `session_verify_reports_planted_problems`（catalog 侧 `verify_reports_each_planted_problem`
    逐 code 断言）、`session_verify_keeps_database_bytes`（catalog 侧 `verify_writes_nothing`）。
  - 备份是作业：`session_backup_returns_before_job_finishes`（门控池中断言 `Queued`，
    进度 `1..=4/0` 按序，产物完整性 + 四文件 + 无 Cache + 直接打开）。
  - 备份取消/忙拒绝：`session_backup_cancel_before_start_removes_nothing_and_reports_cancelled`、
    `session_backup_cancel_mid_run_removes_partial_dest`、
    `session_backup_refuses_busy_dest_without_spawning`（catalog 侧另有
    `backup_cancelled_mid_run_removes_dest` 覆盖预给空根分支）。
  - 恢复是作业：`session_restore_duplicates_and_opens`（拷回 + 打开 + 扫描跟随）、
    `session_restore_cancel_removes_dest_and_opens_nothing`、
    `session_restore_refuses_bad_source_without_spawning`、
    `session_restore_fails_clean_on_unreadable_backup`、
    `session_restore_fails_clean_when_open_refuses`；开时拒绝见上。
  - 失联扫描是作业：`session_open_scans_missing_files_as_job`（门控中断言 `Queued`，
    三行标记 0/1/0，进度事件到达；catalog 侧 `scan_marks_missing_and_unmarks_returned`、
    `scan_cancel_stops_early_and_keeps_partial_marks`）。
  - 模板：`template_save_writes_structure_without_photos`（子进程 + 环境目录；
    catalog 侧 `template_round_trip_without_photo_paths` 断无照片串 +
    覆盖 + 坏名，`template_default_dir_follows_home` 断默认路径）。
  - 注册表：`registry_holds_twenty_commands_with_unique_ids_and_docs`
    （20 条、标识唯一、参数唯一有说明、七条参数逐个钉死）。
  - 主机名：`owner_note_carries_a_nonempty_host_on_this_machine`。
- `cargo test --workspace --locked`：全绿，255 = 208 + 47
  （`-- --list | grep -c ": test$"` = 255；74 个 `test result: ok`，0 失败）。
- 六条 lint：`cargo clippy --workspace --all-targets --locked -- -D warnings`
  exit 0（任务书口径，比六条更严，含 pedantic 全绿）。
  文档：`RUSTDOCFLAGS="-D warnings" cargo doc --workspace --no-deps --locked` exit 0。
- `cargo xtask layers` → `OK: 29 crates, no layering violations.`
  （engine 新增 `lightamer-catalog` 边，L4→L3 合法）；
  `check-order-sync` → `OK (97 modules…)`；`check-no-iop-names` →
  `OK (97 names, 4 roots clean)`；`check-apple-boundary` →
  `OK: 29 crates, 182 rust files, no Apple-boundary violations.`；
  `Scripts/rust-apple-boundary.sh` → `ALL GREEN`（7/7，含 macOS 真值与 Linux 编译）。
- 引擎无文件操作：`rg -n 'std::fs|File::|create_dir|read_dir|copy' crates/lightamer-engine/src`
  → 16 行命中，全是基线已有的 `develop.copy` 命令标识与函数名（与开工前逐行核对一致，
  本波零新增；`std::fs`/`File::`/`create_dir`/`read_dir` 零命中）。
- 真实应用支持目录：`rg -n 'Application Support' crates apps` → 6 处：
  catalog `template.rs` 3 处（默认值定义 + 文档）、catalog 测试 2 处
  （注释 + 假 HOME 断言）、CLI `selftest.rs` 1 处（A5 旧样张目录默认值，非本波）。
  本波三处模板测试全部经子进程/子二进制传环境变量（`rg TEMPLATE_DIR_ENV|LIGHTAMER_APP_SUPPORT_DIR`
  见上：根定义 1 + 三测试各经 `.env()` 设置），无一处写真实目录。
- 演示：`Scripts/rust-session-demo.sh` exit 0（输出见下节）。
- CLI：`cli_run_session_file_end_to_end`（会话文件全绿）、
  `cli_run_rejects_photos_with_starters`（exit 2 + `--photos` 字样）、
  `cli_run_hold_and_template`（hold 行 + 模板落环境目录）全绿；
  另 `run --file` 手工文件见演示 8 步。
- `Scripts/rust-ci-lite.sh`：exit 0，`rust-ci-lite: ALL GREEN`
  （tests total passed=255；ui rebuild 8s ≤180s；release 二进制 17786416B ≤80MB；
  `check lightamer-iop-color` 0s；target/ 8976MB ≤20GB；154s 一轮）。
- 封存面：`git diff --stat 4dde1955 HEAD -- crates/lightamer-history crates/lightamer-registry 'crates/lightamer-iop-*/src/modules' crates/lightamer-registry/fixtures crates/lightamer-apple`
  → 无输出。
- 提交路径（`git show --name-only HEAD`）：待提交后补（只会有纪律清单内路径）。

## 演示脚本输出

`Scripts/rust-session-demo.sh` exit 0，全文（临时目录名因轮次而异）：

```text
GUARD PASS (heavy=0 free=70% swap=?M disk=?GB)
    Finished `dev` profile [unoptimized + debuginfo] target(s) in 0.07s

==> 1. create a session
line 1: session.new ok outcome={"database":"…/Demo/Demo.lmsessiondb","root":"…/Demo","unlocked":false,"uuid":"3272d887-5ff0-419c-a220-f38176637228"} photos=[] digest=13696086043340055060
line 2: session.close ok outcome={"closed":true,"root":"…/Demo"} photos=[] digest=13696086043340055060
…/Demo/Capture
…/Demo/Demo.lmsessiondb
…/Demo/Output
…/Demo/Selects
…/Demo/Trash
…/Demo/session.lock

==> 2. verify it: no findings
line 1: session.open ok outcome={"database":"…/Demo/Demo.lmsessiondb","job":1,"root":"…/Demo","unlocked":false,"uuid":"3272d887-5ff0-419c-a220-f38176637228"} photos=[] digest=13356539667914472873
line 1: job 1 started
line 1: job 1 progress 0/0
line 1: job 1 finished success=true cancelled=false
line 2: session.verify ok outcome={"count":0,"findings":[]} photos=[] digest=1251525862241488298
line 3: session.close ok outcome={"closed":true,"root":"…/Demo"} photos=[] digest=1251525862241488298

==> 3. drop an empty placeholder in Capture/

==> 4. back up, list it, check the database
line 1: session.open ok … "job":1 … (+ scan job 1 started/progress 0/0/finished)
line 2: session.backup ok outcome={"dest":"…/Demo-backup","job":2} photos=[] digest=15072252268623501452
line 2: job 2 started
line 2: job 2 progress 1/0
line 2: job 2 finished success=true cancelled=false
line 3: session.close ok … digest=4676385705016122996
…/Demo-backup/Capture
…/Demo-backup/Capture/placeholder.txt
…/Demo-backup/Demo-backup.lmsessiondb
…/Demo-backup/Output
…/Demo-backup/Selects
…/Demo-backup/Trash

==> 5. restore elsewhere, open it, verify
line 1: session.restore ok outcome={"dest":"…/Demo-restored","job":1} photos=[] digest=7439953708396257167
line 1: job 1 started
line 1: job 1 progress 1/0
line 1: job 1 finished success=true cancelled=false
line 1: job 2 started
line 1: job 2 progress 0/0
line 1: job 2 finished success=true cancelled=false
line 2: session.verify ok outcome={"count":0,"findings":[]} photos=[] digest=15153119647249537347
line 3: session.close ok outcome={"closed":true,"root":"…/Demo-restored"} photos=[] digest=15153119647249537347

==> 6. double open refused; kill the holder; open again
line 1: session.open FAIL session.open: session …/Demo is already open in lightamer-cli 0.1.0 (process 20769 on this computer); close it there first photos=[] digest=13696086043340055060
lightamer-cli: check failed: 1 of 1 lines failed
reopen after kill: ok

==> 7. adopt an existing folder; originals untouched
line 1: session.open ok … "job":1 … (+ scan job 1 started/progress 0/0/finished)
line 2: session.close ok … digest=14505486819798957139
originals unchanged

==> 8. clean up
demo: ALL GREEN
```

（`…` = 该轮临时目录前缀；job 2 即 restore 落定后补起的 open 扫描作业。）

## 给用户看的汇报

做成了什么：第一波的后一半——会话引擎落地。不用写代码，
建会话、开会话、校验、备份、恢复、存模板七件事全是命令：

```bash
printf '%s\n' \
  '{"id": "session.new", "params": {"name": "Demo", "parent": "/tmp/w1"}}' \
  '{"id": "session.verify", "params": {}}' \
  '{"id": "session.close", "params": {}}' > /tmp/w1.jsonl
./target/debug/lightamer-cli run --file /tmp/w1.jsonl
```

备份恢复是后台作业（能取消、有进度），校验只读（前后字节不变），
双开被拒并告知谁在用（第 6 步演示：后台握 20 秒，前台被拒，强杀后重开成功）。
完整八步看 `Scripts/rust-session-demo.sh`（临时目录，约半分钟，exit 0）。

还没做：照片导入（B15，本波打开会话后引擎里没照片是正常的）、
历史落库（B13′）、修校验发现的命令（verify 只报不修，修法命令在以后波次）、
缩略图与界面。

## Commit

首提交 `8823e744273b2f343dfc6e4a3d14a4203b4cd30e`
（`feat(rust): B12'-b session commands, backup/restore jobs, CLI sessions`，
`refs #32`，31 文件 +4516/-78，零 push）。
为把复审结论装进同一 commit 又 amend 了一次（加 `B12p-b-review.log`、
本报告的复审节、commit message 一词之改见 R4），最终哈希以 `git log -1` 为准。
`git show --name-only`（31 + review.log = 32 文件，全在纪律清单内）：
REPORT.md、review.log、Cargo.lock、`Scripts/rust-session-demo.sh`、
`apps/lightamer-cli/{src/commands.rs,src/main.rs,tests/run_session.rs}`、
`crates/README.md`（三行）、catalog（src：error/lib/lock/session 改 4 +
backup/scan/template/verify 新 4；tests：lock 改 1 + backup/scan/template/verify 新 4）、
engine（Cargo.toml + src/command/engine/error/jobs/lib 改 5 + src/session 新 1 +
tests/common/session_commands/session_jobs 新 3）、`docs/SESSION.md`。

## 复审结论头

`PASS / 0 error + 1 minor`（`.work/gsd/phases/rust-core/waves/B12p-b-review.log`，
复审对象 `8823e744`）。11 项全亲手重跑通过（两包测试 68/32、全工作区 255、
`-D warnings`、fmt、四 xtask、边界脚本 7/7、引擎 rg 基线对照、手工 verify 只读
`BYTES_IDENTICAL`、手工 backup 行序、真实目录隔离、演示全绿、封存面零 diff）。
唯一 minor：commit message 里 "lockfile gains only the engine->catalog edge"
字面不精确（实际 +2 条边：`lightamer-catalog` + engine dev 的 `rusqlite`，
零新包——"无新依赖"结论成立），见 R4。

## 未做 / 未验

- 未做：无。任务书 1–9 节全部交付（含前一半留的两件事：主机名修了，
  `display_aux` 写契约写进文档了）。
- 未验：无。验收清单逐条有命令与输出；非 macOS 目标按任务书不跑。
  一个诚实注记：`session_backup_cancel_mid_run_removes_partial_dest`
  依赖"1200 个文件的拷打不过一条即时取消"的时间裕量（注释里写明了），
  其余取消路径（门控 `Queued` 下取消、备份/扫描的计数取消）全确定。
