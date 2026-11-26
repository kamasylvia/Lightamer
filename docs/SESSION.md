# Session Package and Database (SESSION.md)

> 会话包与会话库：磁盘形态、表、版本迁移、锁、路径、关闭与崩溃。备份、恢复、
> 校验三节留给下一波（B12′-b），只先把「备份走在线备份接口、不许裸拷」一条立住。
> 实现：`crates/lightamer-catalog`（L3）。计划正本：`PLAN-B.md` §1、
> `PLAN-B-TABLES.md` T-B1。

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

## Backup, Restore, Verify（下一波 B12′-b）

本节只立一条纪律，命令实现归下一波：

- **备份库文件必须走 SQLite 在线备份接口（`backup_database`），不许裸拷文件。**
  本波的迁移前备份与该接口的测试（WAL 未合并的行必须出现在备份里）已在了，
  下一波的 `session.backup` 复用同一函数。
