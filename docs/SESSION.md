# Session Package and Database (SESSION.md)

> 会话包与会话库：磁盘形态、表、版本迁移、锁、路径、关闭与崩溃、七条会话命令、
> 备份与恢复、只读校验、作业边界、命令行、持有人提示。
> 实现：`crates/lightamer-catalog`（L3，文件与数据库）+ `crates/lightamer-engine`（L4，命令）。
> 计划正本：`PLAN-B.md` §1、`PLAN-B-TABLES.md` T-B1/T-B2。

## On-Disk Layout

会话是一个普通文件夹（不是 macOS 包），整包拷走即完整：

```text
<Name>/
├── Capture/                 # 导入默认落点
├── Selects/                 # Move to Selects 物理移动目的地
├── Output/                  # 导出默认落点
├── Trash/                   # 删除 = 移入；清空 = 永久删除
├── <Name>.lmsessiondb       # SQLite（WAL）：设置 + 历史 + 版本 + 元数据 + 结构
├── session.lock             # 单写者 OS 文件锁
└── session.lock.owner       # 锁持有人提示（JSON，可缺失，仅提示）
```

规则：

- 新建会话时建根文件夹（名字就是会话名）、四个子文件夹、空库、锁。
  根已存在且非空则拒绝，什么都不动；已存在但为空则就地填齐。
- 打开已有文件夹为会话时，就地补上缺的子文件夹和库并加锁，
  **不挪动里面任何已有的文件**（Capture One 同款零导入）。
- 打开时也可以直接给会话自己的 `<Name>.lmsessiondb` 文件，取其父目录为会话根；
  文件名与目录名对不上的库文件会被拒绝（不静默忽略、不另建）。
- `-wal`/`-shm` 是 SQLite 运行态：关会话时 checkpoint 后归零，不进备份。
- `Cache/Thumbs/`（磁盘缩略图，内容键，可重建）是 B15 的事，本波不建。

## Tables

库 `<Name>.lmsessiondb`，schema 第 1 版（`PRAGMA user_version = 1`），
建表语句正本见 `PLAN-B-TABLES.md` T-B1，原样落成 `SCHEMA_V1_DDL`。
打开库或新建库时，日志模式（WAL）、同步档（NORMAL）、外键（ON）由
`apply_pragmas` 集中设置；库版本号（`user_version` + `_meta` 镜像）由
`set_schema_version` 集中双写。不散在各处。

| 表 | 存什么 |
|---|---|
| `_meta` | 键值：`schema_version`（版本号镜像）、`session_uuid`（会话 UUID）、`created_by`、`created_at`、`display_aux`（显示辅助参数 JSON，可缺省） |
| `photos` | 每张照片一行：路径（会话内相对 / 外部绝对）+ EXIF 检索列 + 评分/色标/旗标 + `process` 镜像 + 游标 + 当前快照键 + Trash 原路径 + 失联标记 + `is_export` 导出产物标记 |
| `snapshots` | 快照：键（缺省 = 设置规范 JSON 的十进制哈希，碰撞加后缀）+ 规范 JSON。**只有这两列，不存引用计数**（T2）：无引用的行即孤儿，一条查询查得出来，关会话时清。 |
| `history_steps` | 历史步：`(photo_id, idx)` + 命令标签 + 快照键。游标移动只改 `photos` 行，不写新行。 |
| `keywords` + `photo_keywords` | 关键词字典 + 照片挂接 |
| `albums` + `album_photos` | 相册 / 智能相册（规则 JSON 存 `albums`，查询时求值）+ 虚拟引用 |
| `favorites` | 收藏文件夹（路径 + 显示名） |

两条塔台裁定的落实：

- **T1 哈希只用来查找**：`snapshots` 主键缺省取哈希，但键命中后必须逐字节
  比对规范 JSON，相同才复用；不同即碰撞，另存一行、键加后缀、日志记一笔。
  本波只建表（写入规则是 B13′ 的），表结构从现在起就是两列文本键。
- **T2 不存引用计数**：表里没有任何计数列；`rg refcount crates/lightamer-catalog`
  必须零命中（机检）。

`display_aux` 本波只建位置：一对读写函数（JSON 文本原样存取）+ 一条规定：
取出来解析不了时当作没有（返回空），并把 corrupt 标志报给调用者
（调用者回默认 + 报告，不静默保留坏文本）。谁往里写什么内容是别的波的事。

## Versions and Migration

- 版本唯一事实源 = `PRAGMA user_version`（整数）；`_meta.schema_version` 是镜像。
  两处由 `set_schema_version` 同一函数写，有测试断言它们相等。
- 迁移是一张只往后加的表（`MIGRATIONS`）：从第几版到第几版，各执行什么。
  现在只有第 1 版（建表）；新库文件从 `user_version = 0` 起步，
  所以新建会话同样走 `0 → 1` 迁移（空文件无备份）。
- 打开版本比本构建旧的库：先自动留备份
  `<名字>.pre-migrate.<旧>-<新>.bak`（与库同目录），用 SQLite 在线备份接口拷，
  **不许裸拷文件**（WAL 下裸拷主文件会丢尾部事务）；然后逐版迁移，
  每一版一个事务。备份失败就不迁移，库保持原样。
- 打开版本比本构建新的库：**拒绝**（`SchemaTooNew`，带版本号），
  一个字节都不写：版本先经只读连接探查，再决定开不开读写连接。

## Locking

单写者锁，语义照 LightCraft `catalog/src/lock.rs` 改造
（署名见 `NOTICE` 的 B12′-a 条目与 `lock.rs` 文件头）：

- `session.lock`：OS 独占文件锁（标准库 `File::try_lock`）。打开会话就拿着，
  关会话时显式释放（`release`；`Drop` 同样显式 `unlock`，不靠句柄关闭）。
- `session.lock.owner`：持有人 JSON（进程号、主机名、程序名和版本、时间、
  唯一 token）。只是给人看的提示：可缺失、内容坏了也不影响打开；
  第二个打开者得 `InUse` 错误，错误里带持有人的描述。
- 文件系统不支持文件锁时（有些网络共享）：降级成不加锁地打开，
  但 `opened_unlocked()` 把这件事报给调用者，不静默。
- 进程被强杀：锁由 OS 收回，残留下来的锁文件和持有人文件不妨碍下次打开
  （持有人文件在下次加锁时被覆盖）。

## Path Rules

- 会话内的照片存相对会话根的路径（`path_kind = 0`，`/` 分隔，
  如 `Capture/a.arw`）；引用的外部文件存绝对路径（`path_kind = 1`）。
- 换算函数 `to_stored` / `to_absolute` 都是纯词法换算（不访问文件系统，
  缺失的文件也能换算）：`.`、多余斜杠、`..`（不出界的）会被规范掉；
  任何会悄悄落到会话外的输入（`..` 越界、in-session 存了绝对路径、
  external 存了相对路径）一律报错，不规范进位。
- 相对路径输入按相对会话根理解；绝对路径在会话根下则存相对，否则存绝对。

## Close and Crash

- 关会话（`close_session`）：先 `wal_checkpoint(TRUNCATE)` 把日志合并进库文件
  （之后 `-wal` 为零长度或不存在），再显式释放锁。不经 `close_session` 的丢弃
  仍会释放锁（OS 句柄语义），但 checkpoint 不保证——调用者应用 `close_session`。
- 强退/崩溃（进程被杀）：SQLite 事务语义保证——已提交的命令全在，
  未提交的全不在；WAL 由 SQLite 在下次打开时自动恢复；锁由 OS 收回。
  恢复点 = 最后一条成功提交的命令。
- 断电：库不会坏；同步档是 `NORMAL`，最近一次 WAL 同步之后提交的命令可能丢失
  （通常是最后几秒的编辑）。`NORMAL` 与 `FULL` 的提交耗时对比由 B13′ 量出，
  默认 `NORMAL`，改不改由用户定。

## Commands (B12′-b)

引擎的七条会话命令（经 `execute` 登记；注册表现有 20 条）。会话类命令都不记历史步。

| 命令 | 参数 | 做什么 |
|---|---|---|
| `session.new` | `name`（会话名，一个目录名）、`parent`（放在哪个目录下） | 建会话包，建好就开着它 |
| `session.open` | `path`（会话文件夹或库文件） | 打开会话（缺的就地补齐），并启动失联扫描作业 |
| `session.close` | 无 | 把日志合并进库文件，释放锁 |
| `session.verify` | 无 | 只读校验，返回报告 |
| `session.backup` | `dest`（目标目录）、`include_trash`（可选，默认 true） | 启动备份作业，返回作业标识 |
| `session.restore` | `backup`（备份在哪）、`dest`（恢复到哪） | 启动恢复作业，拷回后按 `open` 流程打开 |
| `template.save` | `name`（模板名，一个文件主干） | 存相册和收藏的结构 |

能不能跑：开着会话（草稿或真实）时 `open`、`new`、`restore` 拒绝，带原因；
没有真实会话时 `close`、`verify`、`backup`、`template.save` 拒绝
（没开是 `NoSession`，开着草稿是 `Disabled` 并点名缺真实会话）。

真实会话：引擎持有一个 `Session`（锁 + 数据库连接），一次只开一个。
草稿会话原样保留（测试和对照）。本波打开真实会话后引擎里没有照片是正常的：
照片是 B15 导入的。

## Backup and Restore

- `session.backup`：命令先校验目标（已存在且非空就拒绝，什么都不动；
  目标在源里面，即递归拷，同样拒绝），然后启动作业并返回作业标识。作业做的事：
  合并日志 → 用在线备份接口拷库（目标库按目标目录名命名）→ 逐文件拷四个文件夹
  （`include_trash=false` 时 `Trash/` 只建空目录；`Cache/` 永不拷；
  锁文件、`-wal`/`-shm` 不拷）。进度按已拷文件数报（总数预先未知，`total=0`）。
  产物直接当成会话打开。
- 取消或出错：作业删掉自己建出来的目标（自己建的根整个删；预先存在的空根
  只清自己拷进去的孩子：库文件加四个目录），完成事件写明是取消
  （`cancelled=true`）还是失败（`success=false` 加原因）。
- `session.restore`：命令先校验备份（必须是带自己库文件的会话包）与目标（空），
  然后启动作业：整包拷回 → 按 `open` 流程打开（加锁、迁移、失联扫描）。
  会话在作业完成后才出现在引擎里（`collect` 时安装）；若中途另开了会话，
  送到的会话被关掉，不覆盖。取消或出错同样清掉自己建出来的目标。
- 库的拷一律走在线备份接口：备份方向合并 WAL 后分步拷（步间可取消）；
  恢复方向从备份文件拷（只读备份，不合并它）。

## Verify

`session.verify` 只读：`SELECT` 加 `PRAGMA integrity_check`，不写库、不写文件。
返回 `{"count", "findings"}`，每条发现带 `severity`（`info`/`warning`/`error`）、
`code`、`detail`、`repair`（修它的命令标识；信息项为空，即无需修）：

| code | 级别 | 修法 | 查什么 |
|---|---|---|---|
| `integrity` | error | `session.restore` | `integrity_check` 非 `ok` |
| `orphan_snapshot` | info | （无） | 无任何步引用、也非任何照片当前快照 |
| `dangling_reference` | error | `session.restore` | 步、当前快照、关键词、相册链接悬空 |
| `cursor_out_of_range` | warning | `session.restore` | 游标越界 |
| `process_mirror_mismatch` | warning | `session.restore` | `photos.process` 与当前快照里的 `process` 对不上 |
| `display_aux_unparseable` | warning | `display.set`（B6） | 那一格解析不了（读回空） |
| `stored_path_invalid` | warning | `library.relink`（B15） | 存的路径换算不出来 |
| `missing_file` | warning | `library.relink`（B15） | 引用的文件不在 |
| `path_scan_deferred` | info | `library.sync`（B15） | 照片超过 1000（`VERIFY_INLINE_PATH_LIMIT`），逐文件检查交后台 |
| `opened_unlocked` | info | （无） | 无锁打开（文件系统不支持锁） |

校验自己不修任何东西：修是各命令的事。单项最多 200 条，超出折成一条
`… and N more`。对同一会话校验前后库文件字节相同（有日志文件时先合并再比）。

`display_aux` 写契约：写的时候不校验，原样存取（B12′-a 定）。所以以后写它的命令
必须自己先校验是合法 JSON 再写。本波没有写它的命令。

## Jobs

命令只做有界的活；拷文件、扫文件夹是作业（`PLAN-B.md` §1.9）。
`session.backup`/`session.restore` 命令返回作业标识，进度与完成经事件报，
`job.cancel` 取消——作业是引擎级的，无会话时也能取消（`restore` 即此，
`job.cancel` 为此不设会话门）。`session.open` 立刻返回，
失联扫描在后台标 `missing`（文件回来则清标记）；取消留部分标记，
重跑即续扫。`verify` 全同步（上限内）；照片多时的存在性扫描交后台作业。

## CLI

`lightamer-cli run --file F [--photos a,b] [--hold S]`：

- 含会话命令的文件不走草稿（无会话启动）；含 `new`/`open`/`restore` 的文件
  再带 `--photos` 被拒绝（exit 2）。
- 每执行完一行，把引擎里还没完的作业做完（进度与完成事件逐行打印）再执行下一行；
  一份文件从头到尾是确定的。单行排空超 120 秒按失败记，不永久挂住。
- `--hold S`：跑完后握着真实会话等 S 秒再关（双开演示用）；无真实会话则提示。
- `template.save` 的目录默认 `~/Library/Application Support/Lightamer/Templates/`，
  环境变量 `LIGHTAMER_APP_SUPPORT_DIR` 直接替换这个 Templates 目录本身
  （文件落其下，不是其子目录）。测试一律指向临时目录，永不写真实目录。

## Holder Hint

锁持有人提示：进程号、主机名、程序名和版本。主机名依次取环境变量、
`/etc/hostname`、`hostname(1)`——macOS 上前两样都没有，靠第三样——
进程内只问一次并缓存。单机上提示缺失不影响打开；双开被拒时提示里应有持有人。
