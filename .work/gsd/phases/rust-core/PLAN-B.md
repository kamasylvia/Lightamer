# PLAN-B — 阶段 B（第 0 期）逐波计划：会话版（重写 B1–B20）
> crate 名说明：文中一律用改名之后的新名（旧前缀加模块名 → `lightamer-X`；L3 占位 crate → `lightamer-ai`；改名在 B 期开工前执行）。此前的研究与核验日志里是旧名，指同一 crate。不改名：顺序夹具 `dt-order-679d594f5d.json`、模块标识、darktable 源码名。
> 日期 2026-11-26。只读 lane 产物：**不动 `PLAN.md`，不动任何代码**，只新建本文件与 `PLAN-B-TABLES.md`。
> 本文件替代 `PLAN.md` §3 的 B1–B20（§0–§2 的架构基线凡与 A-9/A-12/A-14/A-15/A-16/A-17 冲突处，以修订为准）。
> 全文中文；标识符、命令、表名英文。引用代码位置均为本 lane 亲读（`文件:行号`）。
> 修订依据：`PLAN-AMENDMENTS.md` A-1–A-17；会话调研 `ARCHITECTURE.md` + `ARCHITECTURE-TABLES.md`（T-A*）；
> 框架 `FRAMEWORK.md` + `FRAMEWORK-TABLES.md`（T-F*）；阶段 A 实际交付 `waves/VERIFY.md`。

---

## §0 一页纸

**会话包磁盘形态**（普通文件夹，可整包拷走；相对 `ARCHITECTURE.md` §2 去掉 `Lightamer/*.lmsettings`）：

```text
<Name>/
├── Capture/                 # 导入默认落点（复制）；联机落点（D 期）
├── Selects/                 # Move to Selects 物理移动目的地
├── Output/                  # 导出默认落点
├── Trash/                   # 删除 = 移入（库内标记只读）；清空 = 永久删除
├── <Name>.lmsessiondb       # SQLite（WAL）：设置 + 历史 + 版本 + 元数据 + 结构 + 索引
├── Cache/Thumbs/            # 磁盘缩略图（内容键，可重建，备份可略）
├── session.lock             # 单写者 OS 文件锁（LightCraft lock.rs 语义）
└── session.lock.owner       # 锁持有人提示（JSON，可缺失，仅提示）
```

应用层（会话之外）：`~/Library/Application Support/<App>/{RecentSessions.json, Templates/, prefs}`。

**表清单**（库 `<Name>.lmsessiondb`，版本 `PRAGMA user_version`，列定义见 `PLAN-B-TABLES.md` T-B1）：

| 表 | 存什么 |
|---|---|
| `_meta` | 库的键值（schema 版号镜像、建库者、建库时间、会话 uuid） |
| `photos` | 每张照片一行：路径（会话内相对 / 外部绝对）+ EXIF 检索列 + 评分/色标/旗标 + 处理版本号（当前步的镜像）+ 游标 + 当前快照哈希 + Trash 原路径 + 失联标记 + 导出产物标记（A-18，见 §1.1） |
| `snapshots` | 快照：键（缺省 = `hash64_decimal`，哈希碰撞时加后缀）+ 规范 JSON；不存引用计数，孤儿按引用查出来 |
| `history_steps` | 历史步：`(photo_id, idx)` + 命令标签 + 快照的键；游标移动不产生新行 |
| `keywords` + `photo_keywords` | 关键词字典 + 照片挂接 |
| `albums` + `album_photos` | 相册 / 智能相册（规则 JSON 存 `albums`，查询时求值）+ 虚拟引用 |
| `favorites` | 收藏文件夹（路径 + 显示名） |

**合计**：阶段 B 23 波 **118 lane / 331 h**（签字版 81 lane / 223 h，`+37 lane / +108 h`：`Output/` +1/+3、B14 由 2 lane 扩为 10 lane（+8/+24）、B14A 新开 +15/+45、B1d 新开 +7/+18（A-24）、PORTRAIT 新开 +6/+18（A-25）；相对原计划 76 lane / 208 h 为 +42/+123，见 §5）。
含域内自审 ×1.2 ≈ 354 h ≈ 44 个 8h 日。阶段 A 计划 18 lane / 45.5 h（`ARCHITECTURE-TABLES.md` T-A7）不变。

**三个性能数落在哪一波**（修订 A-10；口径沿 #26）：

| 门 | 首次量的波 | 怎样量 | 复量 |
|---|---|---|---|
| 一万张粘贴 1 s 内可见 | B13′（headless） | 草稿会话 fixture 1 万张 → `develop.paste` → commit 返回 + 事件送达计时；DB 事务单独计时 | B20 `Scripts/perf.sh` |
| 切图暖启动 ≤ 0.72 s | B18（视口 fitted） | 暖缓存下切图 → 视口稳定计时 | B20 |
| 可见缩略图约 0.5 s 刷新 | B15（数据面） | `develop.set` 后可见窗缩略图作业完成计时（合成网格，不等 GUI） | B20 带 GUI 复量 |

首量波次与修订 A-10 原先写的（B15、B16、B20）不同：历史在 B13′ 就落库，粘贴的门在那儿就能量；暖切图要到 B18 有了视口才能量。

---

## §1 会话包和数据库的设计

### §1.1 磁盘形态

§0 的树即全部。规则（`ARCHITECTURE.md` §2 按 A-15 甲重理解）：

- 不是 macOS 包，就是普通文件夹：跨平台拷不丢 bundle 位，整包搬运即完整。
- 可重建的派生物只有 `Cache/Thumbs/`（内容键，删了重渲）。`-wal`/`-shm` 是 SQLite 运行态，关会话时 checkpoint 后归零，不进备份。
- `Trash/` 内照片只读：引擎对 Trash 内照片拒绝 `develop.*`（`enabled` 判断返回带原因的不可跑），浏览面显示只读标记。
- `Output/` 进图库预览（A-18 已定，与规划推荐相反）：登记、显示、派生物三拒绝见下两条。
- 导出产物登记：导出作业完成时把产物登记进会话库（`photos` 行 + 导出产物标记 `photos.is_export`，列由 B12′ 建，T-B1）。
- 导出产物显示与派生物规则：图库里产物与照片一起显示，配「显示导出」过滤开关（默认开，数据面 B15 做，开关面 B19 做）；产物是派生物，可浏览、可预览、可用系统方式打开、可在访达里显示；三拒绝：不可再当源图导入、不可再导出、一切编辑命令对其不跑，返回带原因的错误。
- 打开已有文件夹为会话：就地生成库 + 四文件夹（缺的建空）+ 锁，不搬任何图；已有图按引用建库记录（Capture One 同款零导入，T-A1 #11）。
- 多会话 = 多窗口各持一引擎实例一会话；同一会话第二次打开被 `session.lock` 拒绝并提示持有人。

### §1.2 表

设计要点（列定义全表见 T-B1）：

- **快照去重**：`snapshots` 的键缺省 = `PhotoSettings::hash64_decimal`（`crates/lightamer-history/src/settings.rs:505`），即 FNV-1a over 规范 JSON 的十进制串。内容相同的步（含跨照片的批量粘贴）指向同一行。**哈希只用来查找，不是身份**（塔台修订 T1）：键命中时必须逐字节比对规范 JSON，相同才复用；不同就是哈希碰撞，另存一行，键加 `#2` 一类后缀，并在日志里记一笔。LightCraft 拿这个哈希当缓存键，缓存键撞了只是显示错一张；我们拿它存真相，撞了是悄悄把两份不同的设置当成一份，所以多比这一次。十进制串入 JSON/TEXT 沿用旧 Swift 版 M2-2 纪律（`UInt64` 超 2^53，JSON number 会被非 Swift 工具降精度）。
- **步表只存引用**：`history_steps(photo_id, idx, label, snapshot_hash)`。`undo/redo/goto` = 一条 `UPDATE photos SET cursor`，不写新行。`commit` = 同事务先删掉游标之后的步（重做分支），再写入快照（按上面的规则查找或另存）+ `INSERT history_steps` + `UPDATE photos（cursor、current_hash、process 镜像）`。超 `HISTORY_LIMIT`（200，`history.rs:23`）从头裁，同事务删掉裁掉的步。**不存引用计数**（塔台修订 T2）：没有任何步引用、也不是任何照片当前行的快照就是孤儿，这样的行一条查询就查得出来；关会话时清一次，`session.verify` 报告孤儿数和悬空引用。计数错一次就静默损坏真相，不值得为省这一条查询去担这个险。
- **`photos.process` 是镜像**：真相在快照 JSON 的 `process` 字段；`photos.process` 只为过滤（"哪些照片待升级"）ORDER BY/WHERE 服务。`session.verify` 核对镜像与当前步快照一致。
- **路径**：`path_kind = 0` 会话内相对路径（`Capture/…`）、`= 1` 外部绝对路径（引用式导入）。卷 UUID 感知（换盘重认）不进第 0 期，C 期加 `volume_uuid` 列。
- **Trash 原路径**：`trash_original_path + trash_original_kind`，移入时记，移回/清空时清。
- **EXIF**：`photos` 存检索列（相机、镜头、ISO、焦距、光圈、快门、拍摄时间）；完整 EXIF 不入库，需要时从文件重读。
- **智能相册**：`albums.kind='smart'` + `rules_json`，查询时求值，不物化成员。

### §1.3 历史怎样存与占用

模型（A4b 已做，`crates/lightamer-history/src/history.rs:59`）：每步一份完整 `PhotoSettings` 快照（`Arc` 共享）+ 命令标签；上限 200 步；交互合并（`begin/update/end/cancel_interaction`，`history.rs:191`）。

落盘 = 快照去重后的行存（§1.2）。占用估算（假设写明，B12′/B13′ 实测替换）：

- 快照 JSON：已编辑模块 300–500 B/模块（估算，含标签头）；典型照片改 ~8 模块 ≈ **2–4 KB**；21 模块全改 ≈ 6–10 KB；刚导入的默认设置 ≈ 百字节级（空实例表）。
- 步行：`(photo_id, idx, label, hash)` ≈ 60–100 B。
- 一万张粘贴同一调整：快照 1 行（~4 KB）+ 步 1 万行（~0.8–1 MB）+ 索引，一个事务。可见 = commit 返回 + 事件送达，不等缩略图。
- 十万张库：`photos` ~30 MB + 步（均 20 步）~160 MB + 快照（按相异观感数，MB 级）+ 索引。单库数百 MB 量级，SQLite 无压力。

不压缩（JSON 明文可查）；若 B15 十万行实测体积或读延迟超标，C 期再议 zstd（预案，不立项）。

### §1.4 版本和迁移

- 库版本号唯一事实源 = `PRAGMA user_version`（整数）；`_meta` 存镜像与建库信息。
- 迁移 X→Y：单事务 DDL；**迁移前自动留 `.backup`**：`<Name>.lmsessiondb.pre-migrate.X-Y.bak`（Capture One 同款 `.cosessiondb.backup`，T-A1 #38；在线一致性拷走 rusqlite `backup` API，旧 Swift 版 M2-2 `backup(to:)` 同款语义）。
- 旧版库：能迁移则迁；不能（user_version 超前于本构建）则拒绝打开并提示版本，不降级写。
- 迁移测试：每版一条 —— 旧库 fixture → 迁 → 行数与快照哈希不变。

### §1.5 锁

LightCraft `catalog/src/lock.rs:1-34` 语义，会话根改造（T-F10 #9，`NOTICE` 署名）：

- `session.lock`：OS 独占锁（`File::try_lock`），引擎打开会话即持，`drop` 时显式 `unlock`（不清靠句柄关闭，LC #680 教训，`lock.rs:13-18`）。
- `session.lock.owner`：持有人 JSON（pid、主机名、程序、版本），仅提示，可缺失、 crash 残留永不算 stale。
- 第二个打开者得 `InUse` + 持有人提示。SQLite 自身锁是库文件上的第二层。
- 无锁文件系统（部分网络共享）：降级为无锁打开 + 警告（LC 同款，`lock.rs:22-24`），`session.verify` 标注。
- 崩溃/强退：锁由 OS 释放，残留文件不阻塞重开。

### §1.6 备份和恢复、校验

- `session.backup(dest)`：checkpoint → rusqlite `backup` API 拷库单文件 → 拷 `Capture/Selects/Output/Trash/` → `Cache/` 不拷、`Trash/` 可选略（T-A1 #36 同款）。产物 = 可直接打开的会话包。
- `session.restore(backup, dest)`：整包拷回 + 按 `session.open` 流程打开。
- `session.verify`：`PRAGMA integrity_check` + 应用层检查（孤儿步/快照、游标越界、`photos.process` 镜像、路径存在性扫描、Trash 原路径可达）。只读诊断，可修项给出修法（如失联标记、镜像重算），修法本身是显式命令，不在 verify 里偷写。
- 为什么不用文件拷库：WAL 下裸拷主文件丢尾部事务（旧 Swift 版 M2-2 已登记此坑）；`backup` API 或 checkpoint 后全套拷才一致。本计划统一走 `backup` API，一种机制。

### §1.7 崩溃

- 强退或崩溃（进程被杀）：SQLite 事务语义保证 —— 已提交的命令全在，未提交的全不在。WAL 由 SQLite 自动恢复。
- 断电（塔台修订 T3，措辞改准）：库不会坏。同步档自 2026-11-27 起是 `FULL`（用户裁决，A-21）：每次提交都做一次同步，强退和断电都不丢已经提交的命令，前提是磁盘诚实地说完成了同步。macOS 上只有另开 `fullfsync` 才保证数据落到了盘片上，那一档不开，机械盘上每次提交要四五十毫秒。代价（塔台实测）：每次提交多约 1 毫秒（USB 机械盘）、约百分之二毫秒（内置固态盘）。
- 恢复点 = 最后一条成功提交的命令。拖动中（interaction 未 end）的 live 值在内存，丢；已 end 的已提交，不丢。
- 重开流程：取锁 → 开库（自动恢复）→ 失联扫描（引用式文件被外移则标 `missing`）→ 报告。无"续刷队列"（A-15 甲下 R1 不存在）。
- B13′ 验收含崩溃注入（kill -9 后重开校验）与断电语义测试（事务边界断言）。

### §1.8 命令落库的次序

（塔台修订 T5。B13′ 起命令开始落库：此前"状态"只有内存，此后"状态" = 库 + 内存。）

- 库是真相，内存是它的镜像。
- 一条要落库的命令分三步：① 先把新的内存状态算好（这一步可以失败，失败时库一个字节都不碰）；② 再跑库事务并提交；③ 最后把算好的状态换进内存。
- 第 ③ 步不会失败：它要换进去的东西第 ① 步就算好了。
- 库事务失败：返回错误，内存和库都没变。A7a「出错后状态不变」的契约在落库之后仍然是这一句，只是「状态」多了一半。
- 进程在提交之后、换进内存之前被杀：重开后以库为准，什么都不会丢。

### §1.9 命令和作业的界线

（塔台修订 T6。A7a「命令是快的，不碰磁盘」是 A7a 那一波的口径——那时数据全在内存；B13′ 起命令要落库，界线重定如下。）

- 命令只做**有界**的活：内存里的状态变更，加上至多一次有界的落盘（B13′ 起的一条小事务，比如一万张粘贴的那一个事务）。
- **无界**的活不许放在命令里，由命令启动成一个作业：拷文件、扫文件夹、解码、渲染、编码、整包备份。作业在工作线程上跑，能取消，进度经事件报回来；作业的产物回到引擎线程之后才由引擎落盘。
- 落点：B12′（`session.backup`/`session.restore` 与 `session.open` 的失联扫描是作业）、B15（导入的复制、`library.sync` 的扫描、缩略图的生成是作业）、B16（导出是作业）。三卡验收里各有一条「命令先返回」。

---

## §2 三个代价、依赖选型

### §2.1 代价一：单张图拷出去不带调整

接受方式（A-15 已裁）：第 0 期不做导出调整的命令。落实：

- B 期不登记 `adjustments.export/import`（T-A8 这两条划归 C 期，可选）。
- 跨会话/跨机带调整搬运的唯一路 = 整包拷（`session.backup`）或 C 期命令。B19 会话浏览器对拷出动作不承诺带调整，文档写明。
- 验证它的波：B20 闭环验收含一条负测 —— 单拷一张图出会话，重开后该图不在库内（预期行为），备份恢复后调整全在。

### §2.2 代价二：库坏了全丢

靠备份和校验（§1.6）：

- 预防：`session.backup`（B12′）、迁移前自动 `.backup`（B12′）。
- 发现：`session.verify`（B12′，integrity_check + 应用层检查）。
- 恢复：`session.restore`（B12′）。B 期承诺 = 检出 + 报告 + 从备份恢复；**不承诺法医级抢救**（部分页损坏的细粒度修复不进第 0 期，文档写明）。
- 验证它的波：B12′（备份/恢复/校验全套 + 损坏 fixture 检出测试）、B20（备份恢复演练）。

### §2.3 代价三：批量粘贴的性能

- 机制：单命令单事务（§1.3 占用算式）；可见 = commit 返回 + 事件送达，不等缩略图重渲。
- 三个数各在哪一波量、怎样量：见 §0 表。B13′ 量粘贴（`lightamer-cli bench` headless + DB 事务分解计时）；B15 量缩略图刷新（合成网格数据面）；B18 量暖切图；B20 `Scripts/perf.sh` 复量三数 + T11 全门。
- 若 B13′ 实测 1 万行事务超 1 s：先拆耗时（JSON 序列化 / 索引 / fsync），再定是调优（如 WAL 同步档、批量预处理快照）还是报用户放门。不预设结论。

### §2.4 依赖选型：rusqlite（bundled）

结论：`lightamer-catalog`（L3）引入 **`rusqlite` + `bundled` + `backup`**（`default-features = false`，避开 `cache/hashlink`）。

本 lane 实测（crates.io API，2026-11-26，`User-Agent` 头直取，比较全表见 T-B4）：

- `rusqlite 0.43.0`，MIT（允许清单已有 `MIT` 行）。Rust 要求 1.89，本仓 1.100，满足。
- 必带传递依赖 5 个，许可证全在 `Scripts/licenses-allow.txt` 内：`bitflags`（MIT OR Apache-2.0）、`fallible-iterator`（MIT/Apache-2.0）、`fallible-streaming-iterator`（MIT/Apache-2.0）、`libsqlite3-sys 0.40`（MIT）、`smallvec`（MIT OR Apache-2.0）。
- `bundled` 经 `libsqlite3-sys/bundled` 拉构建依赖 `cc`（MIT OR Apache-2.0）→ `find-msvc-tools`、`shlex`（均为 MIT OR Apache-2.0）。构建期依赖，不进产物。
- `backup` 特性无额外依赖（API 开关）。SQLite 本体公有领域（libsqlite3-sys 内嵌 amalgamation）。
- 备选比较：`sqlx`（异步运行时 + 宏，单写者同步场景无收益，重）；裸 `libsqlite3-sys`（手写绑定，重造 rusqlite 的错误/类型面，无收益）；LC 式快照+日志（T-A5 已否：查询面与体积代差）。结论维持 rusqlite。
- 冷构建影响：**没实测**（本 lane 禁构建）。门是 360 s（`Scripts/rust-budget.sh:42`），阶段 A 冷构建约 10 s（`waves/VERIFY.md` 的 A2 一节），余量大；amalgamation 单文件 C 编译是已知慢项，B12′ 跑 `rust-budget.sh --cold` 量数。若越门，预案是改系统 SQLite（可复现性降级，需用户拍板；默认不走）。

B12′ 钉版本并登记 `docs/LICENSE-AUDIT.md`（此前 `png`/`serde` 系已有登记先例，`waves/VERIFY.md` A4b/A5）。

---

## §3 阶段 B 逐波计划（23 波，118 lane）

> 里程碑：B11 后 CLI 逐模块过 golden；B16 后无界面全链闭环（含会话 CLI）；**B20 后首个可用版**（导入→会话浏览→暗房→导出到 `Output/`→备份恢复闭环，21 模块对 darktable 官方版通过）。
> 模块波默认：对照 = `Scripts/oracle.sh compare --module <op> --fixture fixtures/xmp/<op>-5.6.2.xmp`（A5 `emit-xmp` 手写夹具，模块版本号与布局按官方 5.6.2 产物）；回退 = 单模块目录删除 + 夹具还原；源码取 `release-5.7.0` tag（A-16）；参数 = 自有设置模型（A4b），无 `repr(C)`/modversion 断言。下面不再重复。
> **B1–B11 没有一张一字未改**：每张至少改 crate 名（A3R）、输入基线（A-16）、验收口径（自有参数 + 手写夹具）。目标/范围/产出/估时不变。

#### B1 管线内核

1. **目标**：`lightamer-pipeline` 的 Frame/Roi/tiling/缓存/调度可跑；FULL/EXPORT/THUMBNAIL/PREVIEW 四实例同构不同配额；渲染请求 latest-wins。
2. **范围**：`lightamer-pipeline`（L2，A3R 由 `lightamer-core` 改名）；`lightamer-iop-traits` 的 `IopModule`；`identity` 测试模块；顺序取 `lightamer-registry`（A3 已做，97 模块 master 夹具，A-16 不动）。不做：真实模块、色彩变换、蒙版。
3. **输入**：`CORE-DESIGN.md` §1 的 13 步与回调映射；`dt-master` 的 `pixelpipe_hb.c`（只读）；A7a 的作业/事件（渲染走作业，latest-wins 在此波）；A4b `hash64` 作缓存键核（`settings.rs:492`）。
4. **产出**：roi 前推/反推、格式协商、tiling 决策、缓存键（快照 hash ⊕ 输入代际 ⊕ process）、行级 rayon、错误路径、渲染作业（含取消与代际合并）。
5. **验收**：`cargo test -p lightamer-pipeline`：① roi 链 8 例（含 crop/scale round-trip）；② tiling overlap 与 dt 的 `TilingReq` 一致；③ 改一个参数只失效该节点及下游；④ 双跑逐位；⑤ 61MP 空转 < 200 ms；⑥ latest-wins（连发三代渲染，只收最新）；⑦ 缓存键含 process 维（同设置不同 process 不串图）。向用户汇报：管线空转计时 + 一张"改曝光只重算下游"的缓存命中演示（日志断言可视化为文字报告；无界面）。
6. **对照**：无像素对照；tiling 数字对 dt 的 `tiling_callback` 语义。
7. **回退**：`lightamer-pipeline` 内新增模块删除；`identity` 测试模块删除。
8. **估时**：3 lane × 3 h（与原计划同）。
9. **风险**：缓存键漏维（漏 process/漏输入代际）→ 串图或全链重算。缓解：⑦ 与"跨实例隔离"负测钉死；latest-wins 与作业取消的竞态 → 用 A7a 的合成作业先测时序再接真实渲染。
10. **任务书草案**：输入 = 13 步 + 回调映射 + `pixelpipe_hb.c` + A7a 作业 API；变换规则 = 同步 trait、管线持有缓存/tiling、模块内 rayon、渲染只走作业；验收 = 七条测试 + 空转；产出 = 管线 + 作业接线。

#### B2 rawspeed 解码

1. **目标**：ARW/RAF/NEF 解成马赛克 + 黑/白电平 + WB + 矩阵 + 裁剪框 + 内嵌缩略图字节；坏文件不 abort。
2. **范围**：`lightamer-decode`（L1）的 C ABI shim（`rs_open/rs_decode/rs_thumb/rs_free`）、`CameraMetaData` 单例、栅格解码（JPEG/TIFF/PNG 纯 Rust）。不做：去马赛克、CIRAW。
3. **输入**：`SPIKE-RUST-APPLE` 的 shim；`rawspeed-backend/SPIKE.md` 的 34–57 ms；rawspeed 钉 `0c16fee77`（A-6）；`cameras.xml` 随包。
4. **产出**：`rs_*` API、Rust 安全包装、错误码、元数据、`lightamer-cli decode --dump`（含 `--thumb` 探针，给 B15 的内嵌快路径）。
5. **验收**：① 三 CC0 样张宽高/黑电平/白点/WB 与 rawspeed dump 逐值相等；② 坏文件返回错误码且进程存活；③ 双跑逐位；④ 单文件解码 ≤ 80 ms（A7R5 冷）；⑤ 内嵌缩略图字节非空且 JPEG 可解。向用户汇报：一张表（三样张的四元组 + 耗时），坏文件演示进程存活。
6. **对照**：rawspeed 自身 dump；CIRAW 只作旁证（不设门）。
7. **回退**：`lightamer-decode` 新增部分删除；shim 独立。
8. **估时**：2 lane × 3 h（与原计划同）。
9. **风险**：rawspeed cmake 在本机构建失败或 `cameras.xml` 路径漂移 → 用 dt 同款固定配方 + 资源随包，构建失败则本波标未完成并阻塞 B3（解码是全链前置）；`unsafe` 只许在 shim 内并逐处写安全说明（A6 同款 lint）。
10. **任务书草案**：输入 = shim + 三样张 + `cameras.xml` + 钉住的提交；变换规则 = 薄 C ABI、单例 meta、错误码不 abort；验收 = 五条；产出 = 解码 crate + dump 命令。

#### B1d 整链行带流式（A-24；紧跟 B2、在 B3 之前）

1. **目标**：超过单帧上限的图在完整分辨率和导出实例上也能渲染——内存里只留条带或方块，结果与整帧逐位相同。
2. **范围**：`lightamer-pipeline`（新入口 `render_stream`，不碰 `render`；条带执行器；余量方块执行器；输出帧的内存映射落盘；不设固定的像素上限，按资源拒绝）；`lightamer-iop-traits`（`StatsNeeds` 声明，默认 `Local`；`overlap` 与 `roi_in` 的一致性测试）；`lightamer-engine`（`InputSource::fetch_region`，默认 = 整帧加裁剪；引擎配置里的磁盘上限，默认 8 GB；超限自动转流式）；命令行演示。不做：代理统计（随第一个需要整图统计的模块）、改几何的模块（随各自的波，在那之前返回分了类型的拒绝）、预览和缩略图实例、按区域解码。
3. **输入**：`streaming-research/RESEARCH.md`；Lumen RAW 的 `lumen/large_image.py` 和 `lumen/engine.py`（MIT，`NOTICE` 署名）：64 行的条带、`block_size(margin)`、`spatial_margin`、`process_region`、`allocate` 的内存映射；B1 的 `render.rs`、`module.rs`。
4. **产出**：两种模式（条带、余量方块）的流式入口、带和块的规划器、输出帧落盘、区域输入接口、`StatsNeeds`、演示脚本 `Scripts/rust-stream-demo.sh`。
5. **验收**：① 两亿像素的合成图、五个节点，在 16 GB 机器完整分辨率的预算内流式渲出，条带模式峰值常驻 < 1 GB；② 同设置的两千万像素图，整帧与流式逐字节相等（条带一例，含模糊节点的方块一例）；③ `overlap` 撒谎的模块被一致性测试拦下；④ 旋转类模块、要看整图的模块（`WholeImage`）在流式下返回分了类型的拒绝，预算与缓存原样；⑤ 磁盘上限可配，超过返回分了类型的错误；⑥ 双跑逐位。向用户汇报：两亿像素的演示、峰值内存、「上限由资源定」的实测（这台机器上能到多少）。
6. **对照**：Lumen RAW 的两种模式和方块公式；没有像素对照（还没有真实模块）。
7. **回退**：`render_stream` 与规划器删除；`StatsNeeds`、`fetch_region` 有默认实现，可留。
8. **估时**：7 lane × 3 h（接口与规划、条带执行、方块执行、区域输入与落盘、引擎接线、验收测试与文档、复审各一；调研估 12 h 加 6 h）。
9. **风险**：余量沿链累加后过大 → 方块的有效边长变小，内存仍受控（Lumen 的钳制）；每像素字节数和各模块的余量要用我们自己的数实测；导出作业按带消费要等 B16 → B1d 只交入口和演示，导出的接线归 B16。
10. **任务书草案**：输入 = 调研 + Lumen 源码 + B1；变换规则 = 放得下整帧走 `render`、放不下自动转 `render_stream`，逐点链条带、含空间模块走方块，每一带或每一块跑完整条链、输入按累加的余量放大；验收 = 六条；产出 = 流式入口 + 规划器 + 落盘 + 区域输入 + 声明。

#### B3 raw 头段四件（rawprepare / hotpixels / temperature / highlights）

1. **目标**：黑电平/白点、坏点、白平衡、高光重建与 dt 逐像素一致；RAW 默认启用链就位。
2. **范围**：`lightamer-iop-raw` 的 rawprepare/hotpixels/highlights、`lightamer-iop-color` 的 temperature；自有参数描述与校验。不做：demosaic、rawdenoise、rawoverexposed。
3. **输入**：T7 第 1/3/5/2 行；`release-5.7.0` 四个 `.c`（A-16）；A4b 校验规则（`ModuleInstance::validate`）；lcms2（temperature 的 CCT 数学，新依赖，L1 `lightamer-color`）。
4. **产出**：四模块 + 单测 + 四组手写 oracle 夹具（highlights 4 模式各一）+ lcms2 接入与登记。
5. **验收**：四 `oracle compare` 过门；temperature CCT↔xy 与 dt 差 < 1e-4；highlights 四模式各过门。向用户汇报：四模块 oracle 门数（4/4）+ 一组 temperature 前后对比图（CLI 出图，裸眼可判白平衡方向对）。
6. **对照**：oracle（手写单模块夹具）。
7. **回退**：见本节默认。
8. **估时**：6 lane × 2 h（与原计划同；highlights 2 lane）。
9. **风险**：temperature 的 as-shot WB 来源（rawspeed vs dt 默认）→ 以 oracle 产物为真值，不猜；highlights 小波重建超支 → 只做 opposed+clip 并报用户（原计划同款预案）；lcms2 许可证/构建 → 先过 A1 表再用。
10. **任务书草案**：输入 = 四源文件 + 手写夹具；变换规则 = 逐行转写、float 不升精度、lcms2 只做 CCT 数学；验收 = oracle + CCT；产出 = 四模块。

#### B4 demosaic（RCD + passthrough）

1. **目标**：RCD 与 dt 默认算法逐像素一致；passthrough 供调试；X-Trans 明确回退。
2. **范围**：`lightamer-iop-raw` 的 demosaic；`demosaic_rcd.cl` 算法 + `demosaic.c` 调度/回退。不做：AMaZE/PPG/VNG/Markesteijn/LMMSE、GPU、捕获锐化。master 的 demosaic 变更追赶归 C-0（A-16）。
3. **输入**：T7 第 6 行；`release-5.7.0` 的 `demosaic.c` + `demosaic_rcd.cl`。
4. **产出**：RCD + passthrough + 边界/裁剪（dt 4 像素边框）+ X-Trans 检测与警告 + 分步 golden 日志（绿面→色差→方向）。
5. **验收**：RCD 默认过门；A7R5 全分辨率 ≤ 120 ms（10 核）；passthrough 逐位；X-Trans 走 passthrough 且 warning；边界 8 例无越界。向用户汇报：RCD 与 dt 的差图（mean/max/in_tol 三数）+ 耗时；X-Trans 回退演示。
6. **对照**：oracle 的 RCD 输出。
7. **回退**：见默认；管线退 passthrough。
8. **估时**：4 lane × 3 h（与原计划同；本阶段最大单点）。
9. **风险**：方向判决常数错一字就过不了门 → 分步 golden 定位到段；120 ms  CPU 达不到 → 放宽到 200 ms 需用户拍板（原计划同款门）。
10. **任务书草案**：输入 = `demosaic.c` + `demosaic_rcd.cl` + 三样张；变换规则 = 只 RCD + passthrough、边界语义逐字；验收 = oracle + 计时 + 边界；产出 = 模块 + 分步日志。

#### B5 色彩三段（colorin / colorout / gamma）

1. **目标**：相机矩阵→工作空间→显示/输出的色彩链与 dt 一致；`ParamsDesc` 词汇扩到字符串/路径（colorin 的 ICC 路径需要）。
2. **范围**：`lightamer-iop-color` 的 colorin/colorout、`lightamer-iop-display` 的 gamma、`lightamer-color` 的 lcms2 腿；`lightamer-iop-traits` 加 `Text/Path` 参数种（additive，旧描述零改）。不做：软打样、DRT、HDR 输出。
3. **输入**：T7 第 13/18/21 行；`release-5.7.0` 三源文件 + `colorspaces.c`；工作空间 linear Rec2020。
4. **产出**：三模块 + ICC 路径（内嵌/标准）+ sRGB 输出 + 16 位写出探针。
5. **验收**：三 oracle 过门（含内嵌 ICC 样张）；输出 PNG 位深 16；sRGB 色度差 < 1e-3；无 ICC 样张走标准矩阵过门；`Text` 字段校验测试（A4b 缺口关闭）。向用户汇报：三模块门数 + 一张"无 ICC 的 RAW 也能出正确颜色"的演示。
6. **对照**：oracle；colorin 另加"colorout 后逐通道均值差 < 1 LSB8"。
7. **回退**：见默认；`lightamer-color` 保留。
8. **估时**：5 lane × 3 h（与原计划同；词汇扩展含在内）。
9. **风险**：lcms2 的 intent/black-point 语义与 dt 封装不一致 → 只走 dt 的调用参数（perceptual、无 BPC），逐行读 `colorspaces.c`；`Text` 词汇改动牵连 A4b 校验 → `lightamer-history` 只加分支不改语义，既有 29 测试全绿为前提。
10. **任务书草案**：输入 = 三源文件 + `colorspaces.c` + 样张；变换规则 = 工作空间 linear Rec2020、gamma 只在显示链；验收 = oracle + 位深 + 色度；产出 = 三模块 + 输出编码。

#### B6 尾段三件（finalscale / dither / overexposed）

1. **目标**：缩放、抖动、过曝标注与 dt 一致；overexposed 定为显示辅助（不记历史步，经 `display.set` 改）。
2. **范围**：`lightamer-iop-display` 三模块 + 新命令 `display.set`（登记在引擎，只改会话级显示辅助参数）。不做：rawoverexposed、scopes。
3. **输入**：T7 第 17/19/20 行；`release-5.7.0` 三源文件；A3 的模块描述（动手前先核有无 `IOP_FLAGS_NO_HISTORY_STACK` 对应位，见风险栏）。
4. **产出**：三模块 + 单测；overexposed 阈值走引擎会话级内存状态（进程启动是默认值，切图保持，不进任何照片的历史栈；不落盘——B6 时会话库还不存在）+ 新命令 `display.set`（参数：模块标识 + 补丁，只改会话级显示辅助参数，从不记历史步）；管线照 darktable 条件排除它：只在带界面的完整管线里启用（`overexposed.c:406` 的 `dt_pipe_is_full(piece->pipe) && self->dev->gui_attached`），导出管线不启用。
5. **验收**：三 oracle 过门；dither 双模式固定种子逐位；`display.set` 调 overexposed 阈值不产生历史步（断言步数不变）且标注变化；`develop.set` 改 overexposed 或 finalscale 返回参数错误；已知行为：重开应用阈值回到默认值（持久化在 B12′ 补上）。向用户汇报：三模块门数 + 过曝标注开关演示（动阈值，历史面板不动）。
6. **对照**：oracle。
7. **回退**：见默认。
8. **估时**：3 lane × 2 h（与原计划同）。
9. **风险**：「不记步」的依据是模块描述里的 darktable 标志位（`IOP_FLAGS_NO_HISTORY_STACK`，overexposed、rawoverexposed、finalscale 三个带此位），不是引擎里手写的名单；B6 lane 动手前先核 A3 描述有无这一位（`crates/lightamer-iop-traits/src/lib.rs` 里 history 标志那一带），没有就按 darktable 补上——描述是模块自己带的，不算中央名单；测试钉死带该标志的已建模块经 `develop.set` 改报参数错误、经 `display.set` 改不记步，其余模块仍恰好记一步。
10. **任务书草案**：输入 = 三源文件 + A3 描述；变换规则 = finalscale 用公共缩放、dither 固定种子、显示辅助走 `display.set`；验收 = oracle + 不记步断言 + 参数错误断言；产出 = 三模块 + 命令。

#### B7 两级色差校正（cacorrect / cacorrectrgb）

1. **目标**：前后两级 CA 校正与 dt 一致。
2. **范围**：`lightamer-iop-geom` 两模块。不做：rawdenoise、rawoverexposed、colorreconstruct。
3. **输入**：T7 第 4/8 行；`release-5.7.0` 两源文件 + `.cl` 算法。
4. **产出**：两模块 + 手写夹具。
5. **验收**：两 oracle 过门；61MP 单模块 ≤ 300 ms。向用户汇报：两模块门数 + 高反差边缘前后对比（CLI 出图，裸眼可判紫边收敛）。
6. **对照**：oracle。
7. **回退**：见默认。
8. **估时**：4 lane × 2.5 h（与原计划同）。
9. **风险**：cacorrect 寻边迭代 CPU 超 300 ms → 按 dt 分块/提前退出优化，仍超则报用户放门；两模块座位不同（5.0 vs 13.5），顺序错则观感错 → 顺序由 registry 链保证，测试断言两模块相对序。
10. **任务书草案**：输入 = 两源文件 + 两 `.cl`；变换规则 = 逐行、枚举全保留；验收 = oracle + 性能；产出 = 两模块。

#### B8 曝光与镜头（exposure / lens）

1. **目标**：曝光三模式与镜头三校正（畸变/TCA/暗角）与 dt 一致；lensfun 接入并钉版。
2. **范围**：`lightamer-iop-display` 的 exposure、`lightamer-iop-geom` 的 lens（lensfun 数据 + 三校正）。不做：ashift、裁剪、交互工具。
3. **输入**：T7 第 11/7 行；`release-5.7.0` 两源文件；lensfun（版本 B8 钉，数据独立许可文件）。
4. **产出**：两模块 + lensfun 数据随包 + 手写夹具。
5. **验收**：两 oracle 过门；三校正各一例；相机+镜头失配退化恒等 + 日志；数据版本进 NOTICE。向用户汇报：两模块门数 + 广角畸变校正前后对比。
6. **对照**：oracle（含 profile 样张）。
7. **回退**：见默认；数据保留。
8. **估时**：4 lane × 3 h（与原计划同）。
9. **风险**：lensfun C++ API 绑定重 → 用 C API（`lf_db`/`lfModifier`），不引 C++ 绑定；数据库版本漂移 → 数据随包钉版 + 版本断言；exposure 的 DNG 基线曝光默认值走 5.7.0（master 变更归 C-0）。
10. **任务书草案**：输入 = 两源文件 + lensfun 数据；变换规则 = 三校正、EXIF 自动匹配；验收 = oracle + 三例；产出 = 两模块 + 数据。

#### B9 方向与裁剪（flip / crop）

1. **目标**：方向与裁剪 ROI 语义与 dt 一致。
2. **范围**：`lightamer-iop-geom` 两模块。不做：clipping（deprecated）、rotatepixels/scalepixels。
3. **输入**：T7 第 10/12 行；`release-5.7.0` 两源文件；B1 的 roi 接口。
4. **产出**：两模块 + ROI 测试。
5. **验收**：两 oracle 过门；crop ROI 前推/反推 8 例；flip 8 方向逐位；下游看到的 ROI 与 dt 同。向用户汇报：两模块门数 + crop 比例演示（CLI 出图尺寸断言）。
6. **对照**：oracle + dt 的 ROI 日志。
7. **回退**：见默认。
8. **估时**：3 lane × 2 h（与原计划同）。
9. **风险**：crop "最后生效"语义（顺序 24.5）反直觉 → B1 roi 测试先覆盖，B9 只接线；master 的 crop 机内画幅自动启用归 C-0，本波显式关。
10. **任务书草案**：输入 = 两源文件 + roi 接口；变换规则 = crop 只在输出 ROI 生效；验收 = oracle + roi；产出 = 两模块。

#### B10 透视（ashift）

1. **目标**：手动参数（旋转/透视/镜头位移）与 dt 一致；求解器不移植。
2. **范围**：`lightamer-iop-geom` 的 ashift 手动路径 + 单应矩阵。不做：自动求解、交互取点。
3. **输入**：T7 第 9 行；`release-5.7.0` 的 `ashift.c` 手动路径 + `get_homography`。
4. **产出**：ashift（手动）+ ROI/几何变换 + 手写夹具。
5. **验收**：手动参数过门（几何允许 ±1 px 搜索）；描述里无 auto 控件（`xtask` 断言）；手动参数往返相等。向用户汇报：门数 + 建筑透视校正前后对比。
6. **对照**：oracle。
7. **回退**：见默认。
8. **估时**：3 lane × 3 h（与原计划同）。
9. **风险**：`crop_mode` 自动缩放语义缠绕 → 只做默认手动路径，自动项描述里不存在（不是禁用，是没有）；±1 px 搜索掩盖真回归 → 搜索半径与残差分布进报告，不只报 pass。
10. **任务书草案**：输入 = 手动路径源码；变换规则 = 只单应矩阵与重采样；验收 = oracle + ±1px；产出 = 模块。

#### B11 曲线三件（rgbcurve / rgblevels / tonecurve）

1. **目标**：三条曲线与 dt 逐像素一致；曲线求值器共享。
2. **范围**：`lightamer-iop-display` 三模块。不做：basecurve/filmic。
3. **输入**：T7 第 14/15/16 行；`release-5.7.0` 三源文件；`Floats` 曲线载体（A4b 已有，`SettingValue::Floats`）。
4. **产出**：三模块 + 共享求值器 + 手写夹具（各 2 组）。
5. **验收**：六 oracle 过门；tonecurve 3 通道 + 单色各一例；rgbcurve 6 插值各一例；边界不 panic。向用户汇报：六门全绿 + S 曲线前后对比；**B11 后 CLI 已能逐模块过 golden**（21 模块 B3–B11 全数）。
6. **对照**：oracle。
7. **回退**：见默认。
8. **估时**：6 lane × 2 h（与原计划同）。
9. **风险**：tonecurve 的 LUT 化路径不移植则数值与性能双错 → commit 预计算保留，测试断言 LUT 与直算一致；曲线节点数可变 → `Floats` 长度校验（空/超长/非单调 x 的处理与 dt 同）。
10. **任务书草案**：输入 = 三源文件；变换规则 = 求值逐行、LUT 化保留；验收 = 六 oracle + 边界；产出 = 三模块 + 求值器。

#### B12′ 会话包与库（重写 B12）

1. **目标**：会话可建/可开/可验/可备/可恢复；单写者锁；schema v1 + 迁移架；CLI 全套。
2. **范围**：`lightamer-catalog`（L3）：§1 的表 + DAO + 迁移 + 锁 + 模板；`_meta` 的 `display_aux`（会话级显示辅助参数 JSON）+ 读写它的数据访问；`lightamer-engine`（L4）：`session.new/open/close/verify/backup/restore` + `template.save`（7 条，T-B2）；`session.verify` 校验 `display_aux` 能解析（坏则回默认 + 报告）；`lightamer-cli` 子命令（`session new/open/close/verify/backup/restore` + `template save`，与命令一一对应）；作业边界（§1.9）：`session.backup`/`session.restore` 是作业（整包拷不进命令），`session.open` 的失联扫描是作业（已登记，保留）；rusqlite 引入与登记；A7a 草稿会话保留作无盘测试态。不做：照片导入（B15）、历史持久化接线（B13′）、缩略图（B15）。
3. **输入**：本文件 §1；T-A1 #1/#3/#5/#6/#32/#36/#38/#39；LC `lock.rs`（`NOTICE` 署名）；M2-2（单 SQLite 文件、WAL、迁移前备份、在线一致性拷）。
4. **产出**：schema v1 DDL + 迁移架 + DAO（含 `display_aux` 读写）+ 锁 + 7 命令 + CLI + 万行事务微 bench（给 B13′ 的前置数）+ `docs/SESSION.md`（包形态/表/锁/备份语义）。
5. **验收**：① 新建会话四件 + 库 + 锁齐；② 第二个打开者被拒并报持有人；③ 打开已有文件夹就地成会话且图不动；④ 迁移前 `.backup` 自动留；⑤ 损坏库 fixture 被 `verify` 检出；⑥ 备份恢复后全表行哈希全等；⑦ 万行单事务计时（只记录，供 B13′）；⑧ `rust-budget.sh --cold` 量数（rusqlite 冷构建影响首次实测）；⑨ `session.open` 的失联扫描走作业（open 立即返回，扫描进度经事件报，不阻塞）；⑩ 显示辅助持久化：改过曝阈值 → 关会话 → 重开，阈值还在（坏则回默认 + 报告）；⑪ 命令先返回：`session.backup`/`session.restore` 在整包拷完之前就返回（测试断言返回时作业未完成），进度经事件报。向用户汇报：建/开/验/备/恢复五步现场演示 + 双开被拒演示；锁残留（kill -9 后）重开演示。
6. **对照**：Capture One 会话行为（引文号见 `ARCHITECTURE-TABLES.md` T-A1）；`integrity_check` 语义。
7. **回退**：`lightamer-catalog` 新增部分删除；engine 7 命令注销（注销测试保证无残留引用）。
8. **估时**：4 lane × 3 h（原 B12 为 3 lane × 3 h；+1 = 锁 + 备份/恢复 + 微 bench）。
9. **风险**：rusqlite `bundled` 冷构建超预期 → 本波只量数，不绕路，越 360 s 门停下报用户；WAL + 备份 API 的交互语义错 → 备份一致性测试用"备份中并发读" + 哈希比对钉死；`user_version` 与 `_meta` 双写漂移 → 单函数 `set_schema_version` 写两处，测试断言一致。
10. **任务书草案**：输入 = §1 + T-A1 + lock.rs + M2-2；变换规则 = 单事务建会话、锁先于库、备份走 API；验收 = 十一条；产出 = 库 + 锁 + 命令 + CLI + 文档。

#### B13′ 历史持久化与批量（重写 B13）

1. **目标**：A7a 的编辑/历史/process 命令全部落库（单命令单事务）；批量粘贴达门；崩溃语义钉死。
2. **范围**：`lightamer-engine`：`develop.merge/sync`（2 条新命令：按模块/参数粒度的合并，A4b 缺口关闭）+ 持久化接线（set/reset/copy/paste/interaction/undo/redo/goto/process.update 改走库事务）；`lightamer-catalog`：快照去重写路径（键命中要比对字节）+ 裁剪 + 孤儿快照回收；`lightamer-cli bench`（paste-10k + 事务分解计时）。不做：导入（B15）、调整导出（C 期）。
3. **输入**：A4b 模型（`history.rs:129` commit、`:147` undo、`settings.rs:492` hash64）；A7a `execute` 契约（原子性：失败则状态逐字节不变 —— 落库后"状态"含 DB，用事务回滚保证）；B12′ 的 DAO。
4. **产出**：持久化接线 + 2 命令 + 裁剪 GC + bench + 崩溃注入测试。
5. **验收**：① A7a 全部命令测试在落库后重绿（含"出错后 DB 与内存双不变"）；② 1 万张粘贴 1 s 内可见（门，不含缩略图），事务分解计时进报告；③ kill -9 后重开 = 最后提交态；④ 超 200 步裁最旧且快照 GC（无泄漏断言）；⑤ `merge/sync` 粒度测试（按模块/按参数各二例）。向用户汇报：万张粘贴现场计时 + 强退重开演示（改了 3 步杀掉，重开后 3 步全在、第 4 步未提交的不在）。
6. **对照**：LC 提交语义（单 Batch 一次提交，T-A3）；A-10 门。
7. **回退**：持久化接线 feature 关回内存态（A7a 草稿会话保留作测试态）；2 命令注销。
8. **估时**：4 lane × 3 h（原 B13 为 3 lane × 3 h；+1 = merge/sync + bench + 崩溃注入）。
9. **风险**：1 s 门实测不过 → 先拆数（JSON 序列化/索引/fsync 三段），调优（预计算快照、WAL 同步档）仍不过则报用户放门，不偷工（不降事务、不丢事件）；`execute` 原子性在 DB 加入后含内存与库两半 → 落库次序按 §1.8（三步：先算好新内存态，再跑库事务提交，最后换进内存），测试每条命令各跑三坏参数（A7a 同款，落库版）。
10. **任务书草案**：输入 = A4b + A7a + B12′ DAO；变换规则 = 单命令单事务、快照先去重、内存后应用；验收 = 五条；产出 = 接线 + 命令 + bench。

#### B14 蒙版基础包（B14-0…B14-3；用户裁决「全部按推荐」）

范围取自蒙版调研 Q1（`masks-research/RESEARCH.md` §6 Q1），两处照评审改正：经典组 5 算子（`masks.h:66-70`，sum 不丢）；混合参数编解码进 `lightamer-history`（L2），光栅化与混合运算进 `lightamer-blend`（L1），见 T-F9。纪律：改蒙版参数走 `develop.set` 一类命令（A7a 分发口）；光栅化、混合、推理是渲染作业内的事，不进命令。

##### B14-0 先行（原卡）

1. **目标**：每模块启用位 + 整图不透明度混合可用；观感正确。
2. **范围**：`lightamer-blend`（L1）：uniform opacity 混合；`lightamer-pipeline` S12 接通（DISABLED 短路 + 不透明度）。
3. **输入**：`CORE-DESIGN.md` §1 的 S6/S12；`blend.c` 的 normal 混合段（只读）。
4. **产出**：混合 + 接通 + 缓存键含蒙版身份（opacity 值折键）+ 面板描述（启用开关 + 不透明度 slider，走 A3 Control）。
5. **验收**：opacity 0/0.5/1 三档 oracle 过门（任选 exposure）；禁用模块 = 直通（逐位）；缓存键测试（改 opacity 只失效该节点下游）。向用户汇报：三档不透明度对比图；禁用即直通演示。
6. **对照**：oracle。
7. **回退**：S12 接通用 feature 关回短路；`lightamer-blend` 新增删除。
8. **估时**：2 lane × 3 h。
9. **风险**：opacity 与 premultiplied alpha 语义错 → 管线 premultiplied 前置条件测试先行（B1 已有，B14-0 复用）。
10. **任务书草案**：输入 = S6/S12 + blend.c normal 段；变换规则 = 先直通后混合、参数折键；验收 = 三档 + 直通；产出 = 混合 crate。

##### B14-1 手绘核心（drawn + 经典组）

1. **目标**：circle/ellipse/gradient/path 四形状 CPU 光栅化 + 经典组 5 算子可用，与 dt 逐像素一致。
2. **范围**：`lightamer-blend`（L1）：四形状光栅化（CPU 参考管线）+ 经典组 union/intersection/difference/exclusion/sum + opacity/invert；Lab L 单通道 parametric 验证链路（含在本卡内）。不做（→ C-6）：brush、parametric 16 通道全量、raster、flexi 树、mask manager GUI。
3. **输入**：调研 Q1；`release-5.7.0` 的 `circle/ellipse/path/gradient.c` 光栅化段 + `group.c`（A-16）；dt 源码 GPL-3.0 同许可。
4. **产出**：四形状 + 经典组 + 单通道 parametric 验证腿 + 手写 oracle 夹具。
5. **验收**：四形状各一 oracle 过门；5 算子各一例（含 sum）；Lab L 通道链路通；双跑逐位。向用户汇报：四形状各一张前后对比 + 经典组 5 算子演示（含 sum）。
6. **对照**：oracle（手写单模块夹具）。
7. **回退**：见 §3 默认（单模块目录删除 + 夹具还原）。
8. **估时**：4 lane × 3 h。
9. **风险**：path 贝塞尔光栅化与 dt 差亚像素 → oracle 门判，不追实现同构；sum 语义（叠加可超 1，后续 clamp）与 union 混淆 → 单测钉死 sum/union 对照例。
10. **任务书草案**：输入 = 四源文件光栅化段 + group.c；变换规则 = 逐行转写、CPU 参考管线；验收 = oracle + 5 算子例；产出 = drawn 核心。

##### B14-2 混合（核心 12 模式 + 参数编解码）

1. **目标**：核心 12 混合模式与 dt 一致；混合参数编解码落位。
2. **范围**：混合运算进 `lightamer-blend`（L1）：normal2/bounded/multiply/screen/overlay/softlight/add/subtract/lighten/darken/average/difference2；混合参数编解码进 `lightamer-history`（L2，按 T-F9：blend v15 编解码 = history，栅格化 = blend）。不做（→ C-6）：余下 24 模式（dt 现行 36 个，评审 M1）。
3. **输入**：调研 Q1；`release-5.7.0` 的 `blend.c` 混合段 + `blendop.cl` 对应核（A-16）。
4. **产出**：12 混合 + 参数编解码（写自有；与 dt blend v15 的映射只用于 oracle 夹具生成，不读用户数据，A-12）+ 手写夹具。
5. **验收**：12 模式各一 oracle 过门；编解码往返逐字节；余下 24 个显式不在描述里（不是禁用，是没有）。向用户汇报：12 模式门数 + 一组 multiply/screen 前后对比。
6. **对照**：oracle。
7. **回退**：见 §3 默认。
8. **估时**：2 lane × 3 h。
9. **风险**：blend v15 参数版本与 5.7.0 对不上 → 以 oracle 产物为真值，映射差异逐项记入报告。
10. **任务书草案**：输入 = blend.c 混合段 + blendop.cl；变换规则 = 运算 L1、编解码 L2；验收 = oracle + 往返；产出 = 混合模式。

##### B14-3 缓存与管线

1. **目标**：蒙版身份折进缓存键；ROI/tiling 下正确；latest-wins 下失效正确。
2. **范围**：`lightamer-pipeline`（L2）+ `lightamer-blend`（L1）：mask 身份（形状参数 + 组 + 混合参数哈希）折缓存键 + ROI/tiling + 降采样预览 + latest-wins 下的 mask 失效。
3. **输入**：B14-0…B14-2 的蒙版身份定义；B1 缓存键（快照 hash ⊕ 输入代际 ⊕ process，加蒙版维）。
4. **产出**：折键 + ROI 接线 + 降采样预览腿 + 失效测试。
5. **验收**：改任一蒙版参数只失效该节点及下游；tiling 接缝无痕（overlap 与 dt `TilingReq` 一致）；latest-wins 下旧蒙版渲染不盖新（代际测试）；降采样预览与全分辨率观感一致（容差门）。向用户汇报：一张"改蒙版只重算下游"的缓存命中演示 + tiling 接缝差图三数。
6. **对照**：无像素对照；tiling 数字对 dt 语义。
7. **回退**：折键 feature 关回整图失效（正确性不动，只丢性能）。
8. **估时**：2 lane × 3 h。
9. **风险**：缓存键漏蒙版维 → 串图；缓解：每类蒙版参数各一条"改之必失效"负测。
10. **任务书草案**：输入 = 蒙版身份 + B1 缓存；变换规则 = 身份全量折键、失效按代际；验收 = 四条；产出 = 折键与接线。

B14 估时合计：10 lane × 3 h = 30 h（B14-0 2、B14-1 4、B14-2 2、B14-3 2）。

#### B14A AI 蒙版（紧跟 B14；用户裁决「全部按推荐」）

1. **目标**：ONNX 推理后端落地；lumen 四类 + 点选 + 边缘细化可用；皮肤/面部像素级与身体整人可用；风光组与近景深度收进（塔台按用户的规矩提出，用户 2026-11-26 已确认）。
2. **范围**：推理编排 `lightamer-ai`（L3，占位改名，非新增 crate）：执行提供者（Provider）小接口 + ort（ONNX Runtime 的 Rust 绑定，MIT）CPU 通用提供者 + 作业接线；`lightamer-apple`（L3）：Provider 的 Apple 侧实现（Vision 人物/人脸/实例/点选执行）；`lightamer-engine`（L4）：启动时把两提供者接上（注册），无 L3→L3 边，层表 T-F9 不动；`lightamer-blend`（L1）：边缘细化（引导滤波 + 抠图，转写 lumen `selection.py`，MIT）。先后：Vision 能给的与参考项目里有的先做（零权重或许可干净，风险最低）；要下权重的按类排，每类独立验收，一类出问题不挡其余。不做：身体部位细分（手臂/腿/衣服，见第 9 条四理由）；dt 点选权重（许可未核）；LC SAM 3 权重（Meta SAM License + 3.4 GB）；Alcedo 自训 head/S3OD 权重（MaSS13K 商用警告 + S3OD 沿革未声明）。
3. **输入**：蒙版调研 §0/Q3（`masks-research/RESEARCH.md`）+ `SKIN-FACE-BODY.md` §0/§3/§4 + 旧 Swift 版 Vision 链做法与位置（`SKIN-FACE-BODY.md` §1.6：`AIMaskService.swift:150-190/:285-362/:426-445/:478-566`，地标 hull 链 `SkinRegionLocator.swift:6-14/:263-423/:427-481`；照此转写为 Rust，Apple 部分落 `lightamer-apple`）；lumen 模型清单（`selection.py:81`）；各权重官方发布页（运行时下载，不进 git）。
4. **产出**：① ort 后端（选型结论 + 落地 + MIT 许可登记 + 原生库随包分发办法）；② 四类：天空 SkySeg（MIT）、人物 DeepLabV3（BSD-3）、主体/背景 U2NetP（Apache-2.0，背景 = 1−主体）；③ 点选 EfficientViT-SAM（Apache-2.0，编码器约 123 MB）；④ 边缘细化（lumen `selection.py` 转写）；⑤ 风光组（EfficientViT-Seg）+ 近景深度（MiDaS）（塔台按用户「参考项目里有的就抄」的规矩提出，用户 2026-11-26 已确认）；⑥ 皮肤/面部 `yakhyo/face-parsing` 的 `resnet18.onnx`（项目 MIT、权重无单独许可声明、按 MIT 理解属推断；约 50.7 MB，19 类，取皮肤/脖子/嘴唇/头发等；训练数据 CelebAMask-HQ 协议含"派生数据"与"商业利用"条款、未点名权重，留解释空间，非商业下风险低属解读——以上按 skin 评审 m1/m2 准确说法），先行与回落 = Vision 人脸关键点 hull 链（旧版已验证，转写）；⑦ 身体：Vision 整人分割先行（经 `lightamer-apple`），整人精细边缘 RVM（代码 GPL-3.0，官方 ONNX fp16 约 7.2 MB）标可选；⑧ sha256 锁文件 + 首用下载（落应用支持目录，与对照工具取官方包同套做法）；⑨ 每个模型许可证进 `NOTICE` 与审计表（代码与权重分开登记）。
5. **验收**：① 每类独立可验（一类红不挡其余）；② 权重零进 git（机检：仓库无权重文件；首用下载 + sha256 锁 + 官方源可配）；③ Apple 面机检（边界门：Apple 调用只在 `lightamer-apple`，`lightamer-ai` 无桥接 token；层门：无 L3→L3 边）；④ 许可登记齐（`NOTICE` + 审计表，yakhyo/RVM 按"无单独声明"诚实写）；⑤ 四类 + 点选 + 细化各一端到端演示（CLI 出蒙版图，裸眼可判语义对）；⑥ 首测性能数进报告（T-B5 的 B14A 两门为推断，本波实测替换）。向用户汇报：逐类演示（每类一张输入 + 蒙版叠加图）+ 权重下载与锁演示 + 许可登记表。
6. **对照**：无 dt 对照（dt 无语义类）；正确性 = lumen 同模型同参数输出对照（容差门，ort 与 lumen 的 ORT 同栈）+ 人眼语义抽查。
7. **回退**：按类关（某类权重/代码删即退回无该类，其余不动）；ort 后端可整颗关回无 AI（B14 链路不受影响）。
8. **估时**：15 lane × 3 h。lane 切分：推理后端 2（ort 选型落地 + Provider/分发/登记）/ 四类 4（1 类打通 + 3 类复制 + 对照）/ 点选 2 / 边缘细化 1 / 风光组与深度 2（两个模型各一）/ 皮肤面部 2（Vision 回落链的转写、yakhyo 权重）/ 身体 2（Vision 整人分割、RVM 可选）。塔台 2026-11-26 把这一波从修订 lane 报的 12 lane 调到 15：皮肤面部、身体、风光与深度是后来加进来的范围，修订时没有另算。
9. **风险**：① 风光组与近景深度是塔台按用户「参考项目里有的就抄」的规矩提出的，用户 2026-11-26 已确认；若翻案则退回不做，退回成本 = 第 ⑤ 项 2 lane；② CelebAMask-HQ 协议"派生数据"解释空间 → 用户已接受背景（裁决），计划按准确说法登记，不粉饰；③ 身体部位细分不做，四理由：候选权重许可未声明、训练数据非商业、无官方 ONNX、体积不明（`SKIN-FACE-BODY.md` §3.3）；④ 123 MB 编码器首用下载慢 → 进度 + 取消 + 断点续传（作业语义），不断言首下时长。
10. **任务书草案**：输入 = 调研三件 + lumen 模型清单 + 旧 Swift Vision 链；变换规则 = Apple 调用不出 `lightamer-apple`、权重不进 git、每类独立验收；验收 = 六条；产出 = 后端 + 七类蒙版 + 登记。
11. **A-25 的两条注记**（用户裁决）：Alcedo 每个人单独开关的交互方式写进设计；权重分发和许可的纪律写进设计（首次使用时下载、来源与校验值、代码 / 权重 / 训练数据三句许可）。估算不变。

#### PORTRAIT 人像修饰（A-25；排在 B14A 之后）

1. **目标**：Lumen RAW 2.3.0「人像」面板的七项修饰——磨皮、美白、祛痘、去黑眼圈、白牙、大眼、瘦脸——在 Lightamer 里可用，以 Lumen 同参数的输出为对照；不新增任何权重。
2. **范围**：修饰算法（L1 纯算法，从 Lumen 的 `lumen/portrait.py` 转写，MIT，`NOTICE` 署名）；皮肤掩膜算法；管线接线（模块、每脸窗口、分块与整图一致）；配方里存关键点（历史模型加一段：归一化的点列加七项设置）；面板和命令面（扩展 `mask.generate` 或新命令，加 A3 的面板描述）。不做：人像虚化、背景替换、眼神光、人脸感知曝光、身体部位细分；YuNet / FaceMesh 的权重（皮肤掩膜的对照证明不够再开）。
3. **输入**：`.work/gsd/phases/portrait-research/PORTRAIT.md`（P1 到 P3 的出处和估算）；Lumen RAW 的 `lumen/portrait.py`（MIT）；B14A 的 Vision 关键点链；B1d 的流式约定（大眼、瘦脸是有界窗口的模块）。
4. **产出**：七项修饰的模块与算法、皮肤掩膜、配方段、面板与命令。
5. **验收**：① 每一项修饰在测试人像上与 Lumen 同参数输出的误差在容差门内（容差门随 B14A 的对照体例）；② 皮肤掩膜与 yakhyo 皮肤类的实测对照报告（76 点对 478 点的差别有数）；③ 配方往返：存了关键点的配方重开后，渲染和导出不用再跑模型；④ 每脸窗口之外逐位不变；⑤ 坏输入（没有脸、关键点越界）返回分了类型的错误；⑥ 双跑逐位。向用户汇报：一张测试人像七项的前后对比（合成或 CC0 的人像，不用用户照片）加耗时。
6. **对照**：Lumen RAW 同参数的输出；没有 darktable 的对照（它没有人像修饰模块）。
7. **回退**：模块和面板逐项注销；配方段可选，缺省无害。
8. **估时**：6 lane × 3 h（修饰 4、掩膜 1、面板与命令 1；设计约束在接线的 lane 里）。
9. **风险**：Vision 的 76 点对 Face Mesh 的 478 点精度差没有实测——皮肤掩膜的对照先走，不够再收权重（加 2 lane 约 6 h）；大眼和瘦脸在流式带上的支持范围要和 B1d 对齐；全部在本机、不外发。
10. **任务书草案**：输入 = 调研 + Lumen 源码 + B14A + B1d；变换规则 = 纯算法转写、Vision 供点、关键点进配方、每脸窗口；验收 = 六条；产出 = 修饰 + 掩膜 + 配方段 + 面板。


#### B15 导入、会话浏览、缩略图（重写 B15）

1. **目标**：导入文件夹 → 会话浏览有缩略图 → 评分/色标/旗标 → Selects/Trash 物理语义 → 十万行可滚；可见缩略图 0.5 s 门。
2. **范围**：`lightamer-engine` 14 条命令（13 + 补入 `library.relink` 1，T-B2）：`library.import/sync/relink`、`photo.moveToSelects/delete/restore`、`trash.empty`、`photo.rate/label/flag`、`album.create`、`smart.create`、`favorite.add/remove`；作业边界（§1.9）：导入的复制、`library.sync` 的扫描、缩略图的生成是作业，命令只登记启动并立即返回；`lightamer-preview`（L3）：三级缓存（嵌入占位→内存→磁盘→渲染，LC 机制改造）+ `Cache/Thumbs/`（内容键 LRU）+ 邻居预取；`lightamer-catalog`：EXIF 检索列 + 结构表 DAO；EXIF 纯 Rust 读（选型在波内定，A1 表先行）；导出产物浏览（A-18）：`photos.is_export` 标记 + 「显示导出」过滤开关数据面（默认开）+ 防重导入/再导出/编辑三拒绝（带原因错误）。不做：层级标签/IPTC（C-4）、AI（C-9）、mip-from-mip（C）。
3. **输入**：T-A1 #11/#12/#14/#17/#20–#24/#25–#27/#47–#49；LC `preview/{pool,lru,disk,lib}.rs` + `media.rs build_job`（`NOTICE` 署名）；B2 的 `--thumb` 探针；#28 缩略图失效教训。
4. **产出**：导入器（复制默认/引用显式）+ 同步/重链接 + 四文件夹行为 + 三级缩略图 + 评分色标旗标 + 收藏/相册/智能相册数据面 + 十万行虚拟列表数据接口 + bench。
5. **验收**：① 导入 101 张 ≤ 4 s（DB 完成）；② 缩略图 ≥ 15 张/s（并行）；③ 改评分只失效该图；④ 十万行查询/滚动数据接口 p95 < 16 ms；⑤ 可见缩略图约 0.5 s 刷新（合成网格数据面）；⑥ 引用式外移标 `missing` + `relink` 恢复；⑦ Selects/Trash 物理移动 + 设置跟走（库内移动恒一致）+ Trash 只读拒绝；⑧ 命令先返回：导入/同步/缩略图命令在作业跑完之前就返回（测试断言返回时作业未完成），进度经事件报；⑨ 显示导出开关默认开、关后产物行不可见，产物 `library.import`/`export.process` 拒绝、`develop.*` 返回带原因错误（三条负测）。向用户汇报：101 张导入计时 + 十万行滚动演示（CLI 数据面先行，GUI 在 B19）+ Selects/Trash 走一遍 + 显示导出开关演示 + 拷图出会话丢调整的预期行为说明（代价一）。
6. **对照**：dt 的 101 张 < 4.7 s、80 ms/张；C1 文件夹语义（T-A1）。
7. **回退**：14 命令逐条注销；`lightamer-preview` 新增删除；导入器可禁用。
8. **估时**：8 lane × 3 h（原 B15 为 4 lane × 3 h；+4 = 会话行为 + 三级缓存 + 14 命令 + 导出产物浏览 A-18）。lane 切分：导入 2（复制/引用 + sync/relink）/ 缩略图 3（三级缓存 + 磁盘 LRU + bench）/ 浏览行为 2（Selects/Trash + 评分色标旗标 + 结构表）/ 导出产物 1（过滤开关数据面 + 防重导入规则）。
9. **风险**：14 条命令一波塞爆 → 按上条 lane 切分登记，每条独立测试，超支则 `smart.create` 的复杂规则语法砍到"单条件"并报用户；EXIF 纯 Rust 选型（候选 `exif`/`kamadak-exif`/`rexif`，版本波内钉）若无一满足 Sony ARW 机型 → 回落"导入不填 EXIF 列 + C 期补"，B15 验收降为路径/评分项并报用户；内嵌 JPEG 不够大/无内嵌 → 回落管线渲染，bench 分"有内嵌/无内嵌"两档报数，不混报；0.5 s 门在数据面过、GUI 面不过 → B15 只保数据面，GUI 差值归 B19/B20。
10. **任务书草案**：输入 = T-A1 + LC preview + B2 thumb；变换规则 = 内嵌优先、后台管线补、库内移动恒一致；验收 = 九条；产出 = 导入 + 浏览数据面 + 缩略图 + 导出产物面。
11. **A-22 的两条（2026-11-27 用户裁决，塔台据此写的验收）**：导入必须成批提交，不一张一张提交（机械盘上登记三万张要 43 秒到 80 秒，内置盘 3 到 4 秒）；同一块盘上导入和编辑提交互相让路。验收加一条：导入作业进行中粘贴一万张，机械盘安静时中位数仍在 1 s 内（B13′-c 的数是忙时 551 到 1121 ms）。

#### B16 导出（默认 Output/）

1. **目标**：JPEG/PNG/TIFF（8/16 位）+ 尺寸/命名/元数据基本项落 `Output/`；产物与 dt 同观感。
2. **范围**：`lightamer-engine::export`（L4）：三编码器（纯 Rust）+ 尺寸解析 + 命名模板（dt token 子集）+ 队列（latest-wins）+ 进度/取消（作业）+ EXIF/IPTC 手写嵌入；作业边界（§1.9）：导出是作业，`export.process` 只登记启动并立即返回，进度经事件报；`export.process` 1 条。不做：HEIC/AVIF/WebP/JXL/PDF/XCF、ICC 剥离、yiyin。
3. **输入**：`FEATURE-SCOPE.md` §1 导出流程；dt 5.7.0 `max_width/max_height` + `libs/export.c` 装配；`decode-oracle-evidence/RESULTS.md` 的 16 位 PNG。
4. **产出**：三编码器 + 尺寸 + 命名 + 队列 + 嵌入 + bench + 产物登记（作业完成时把产物登记进会话库：`photos` 行 + 导出产物标记，列由 B12′ 建）。
5. **验收**：① `export.process` 与 oracle PNG16 逐像素过门；② JPEG 同 quality SSIM > 0.999 或字节数 ±2%；③ 命名模板 6 例；④ 取消/重试；⑤ 61MP 单张 ≤ 3 s；⑥ 默认落点 `Output/`（配方可改）；⑦ 产物含标准 EXIF（机型/曝光）+ 版权（若填）；⑧ 命令先返回：`export.process` 在导出作业跑完之前就返回（测试断言返回时作业未完成）。向用户汇报：三格式各出一张 + 命名模板演示 + 取消演示；产物用系统预览打开确认。
6. **对照**：oracle 同格式同参数导出。
7. **回退**：`export` 模块删除；命令注销。
8. **估时**：4 lane × 3 h（原 B16 为 3 lane × 3 h；+1 = activity 进度/取消 + 导出 gate，F11）。
9. **风险**：JPEG 色度下采样与 dt 不同 → 以 SSIM/字节数双指标，不追字节相同；纯 Rust TIFF 16 位写出与 dt 的标签集差异 → 标签允许清单比对（多/少标签逐项说明，不静默）；导出队列与编辑并发 → 导出读快照（提交态），编辑不污染已入队作业（快照隔离测试）。
10. **任务书草案**：输入 = 导出流程 + 尺寸规则；变换规则 = 三格式纯 Rust、命名按 dt token 子集、导出读快照；验收 = 八条；产出 = 导出。

#### B17 界面壳与面板生成（只用 execute 和快照）

1. **目标**：darktable 三区布局 + 描述生成的面板 + 控件词汇；界面只调 `execute`、只读快照。
2. **范围**：`lightamer-gpui`（L5）：窗口/主题/控件（fill-bar slider/combobox/toggle/section/curve）/面板 chrome/模块列表/参数编辑；菜单位置与快捷键进 L5 自有表（不进引擎，A-17）。不做：视口像素（B18）、灯箱交互（B19）、预设/样式（C）。
3. **输入**：`gpui-spike/REPORT.md`、`appkit-migration/INVENTORY.md` Q2/Q4；A7a 命令（`develop.set/reset/copy/paste` + interaction 四件 + `history.*` + `process.update`）+ B13′ 的 `merge/sync`（面板用 set/reset，形成依赖 B13′）；A3 `panel` 描述 = 唯一 schema。
4. **产出**：控件库 + 面板容器 + 主题 token + L5 菜单/快捷键表（B19 填内容，本波只搭表）。
5. **验收**：`lightamer-gpui --panels-probe`：① 21 模块面板全由描述生成（改描述即改 UI，零 switch）；② #27 交互清单 12 条至少 10 条绿；③ 30 面板滚动 ≥ 45 fps；④ IME「你好」回读一致；⑤ 与 dt 同模块截图三项像素断言 + 并排图；⑥ `xtask check-i18n` 绿；⑦ 机检：`lightamer-gpui` 调引擎只经 `execute` + 快照读（`rg` 断言无直调 `lightamer-history/lightamer-catalog`）。向用户汇报：开窗口逐个点开 21 面板 + 拖一条 slider 看数值 + 改描述即改 UI 的现场演示。
6. **对照**：dt 5.6.2 暗房面板截图。
7. **回退**：`lightamer-gpui` 新增删除；控件库独立。
8. **估时**：5 lane × 3 h（与原计划同）。
9. **风险**：gpui-kit 滑杆是 thumb 不是 fill-bar → 自绘，工时已含；Enter 不进 `on_key_down` → key binding（spike 已知）；`execute`-only 机检误伤（如快照读被判直调）→ 允许清单写死快照读 API 名，评审时逐项过。
10. **任务书草案**：输入 = 原型报告 + 控件清单 + 描述 + A7a/B13′ 命令；变换规则 = 自绘 dt 控件、面板只读描述、引擎只走 execute；验收 = 七条探针；产出 = 控件 + 面板 + 主题。

#### B18 视口与暗房（暖切图门）

1. **目标**：真实像素进视口（缩放/平移/100% ROI）；暖切图 ≤ 0.72 s；编辑 ≤ 0.2 s p50。
2. **范围**：`lightamer-gpui` 视口 + 暗房布局；`lightamer-apple` 的 `PresentSink` 真实实现（CAMetalLayer，本波增量见 §3.1）；`lightamer-pipeline` ROI 渲染接线。不做：scopes/histogram（C）、软打样/DRT（C）。
3. **输入**：A7b 输入归属结论；B1/B2/B5 管线；#28 latest-wins；T11（首图 1.79 s、编辑 0.68 s）。
4. **产出**：视口（fit/100%/拖拽/滚轮）+ 暗房布局 + 渲染代际 + 进度 + bench。
5. **验收**：① 首图 ≤ 1.2 s（fitted 2560）；② 61MP 平移 ≥ 45 fps；③ 改曝光预览 ≤ 200 ms p50；④ 100% 只渲可见区；⑤ 30 分钟编辑 RSS ≤ 起始 + 200 MB；⑥ 暖切图 ≤ 0.72 s（A-10 门）。向用户汇报：开图、拖图、改曝光三步现场计时 + 100% 放大看细节 + 切图秒表。
6. **对照**：#26 的 dt 数字；`PresentSink` 零拷贝不断言帧率，只断言句柄路径（无 CPU 回读）。
7. **回退**：视口 feature 关回静态图；`lightamer-apple` 增量删除（空后端仍过边界门）。
8. **估时**：4 lane × 3 h（与原计划同）。
9. **风险**：`PresentSink` 零拷贝在 gpui 层被覆盖（回读）→ 用"渲染大图时 CPU 回读计数器为零"断言，抓到即报；0.72 s 门在 CPU 全链下过不了 → 先拆（解码/管线/呈现三段），只接受"呈现段优化"，不动正确性，仍不过报用户；A7b 若定 `on_input` 不可用 → NSView 子类兜底（A7b 结论输入，B18 只消费）。
10. **任务书草案**：输入 = A7b + B1/B2/B5 + #28；变换规则 = 视口独立循环、ROI 渲染、代际合并；验收 = 六条；产出 = 视口 + 布局。

#### B19 会话浏览器、灯箱、菜单（重写 B19）

1. **目标**：会话树/收藏/相册 + 灯箱网格/胶片条/评分色标 + 菜单快捷键 + 导入导出对话框；零新引擎命令。
2. **范围**：`lightamer-gpui`：会话浏览器（树 + 收藏/相册/智能相册面板，读 B15 数据面）+ 灯箱「显示导出」开关（默认开，读 B15 数据面）+ 灯箱（虚拟列表）+ 胶片条 + 菜单/快捷键内容（L5 表，dt `accels` 对齐 20 条）+ 导入对话框（复制默认/引用显式）+ 导出对话框（配方）。不做：集合过滤高级语法（C-4）、打印/联机（D）。
3. **输入**：B15 数据面 + 命令；INVENTORY Q2/Q4；dt `accels`（`darktableconfig.xml.in` + `accelerators.c`）；#27 清单。
4. **产出**：浏览器 + 灯箱 + 胶片条 + 菜单快捷键 + 两对话框。
5. **验收**：① 十万行灯箱 ≥ 50 fps；② 评分色标写库并反映（查库断言）；③ 20 快捷键与 dt 逐条脚本比对；④ 菜单走通导入 101 张；⑤ IME 搜索「你好」；⑥ 对话框只调已有命令（机检：无新增 `execute` id）。向用户汇报：开会话 → 浏览 → 评分 → Selects → 导入对话框 → 导出对话框全程点一遍。
6. **对照**：dt 同页截图 + 快捷键表；C1 收藏/相册心智（T-A1 #25–#27）。
7. **回退**：页面 feature 关。
8. **估时**：5 lane × 3 h（原 B19 为 4 lane × 3 h；+1 = 会话浏览器）。
9. **风险**：十万行图片网格帧率（spike 只测了虚拟列表无图）→ 先测 B15 数据面 + 占位图，再测真缩略图，两档报数；导入对话框选项（命名/备份/版权/样式）一次做全超支 → B19 只做"复制/引用 + 命名"，其余进 C-5，验收时如实说；快捷键与 macOS 系统键冲突 → 冲突表逐项记录，用户汇报时确认。
10. **任务书草案**：输入 = B15 + INVENTORY + accels；变换规则 = 自绘网格/胶片条、命令零新增；验收 = 六条；产出 = 浏览器/灯箱/菜单/对话框。

#### B20 闭环验收（首个可用版，重写 B20）

1. **目标**：会话闭环走通，21 模块 golden 全绿，性能门全过，出验收报告。
2. **范围**：端到端脚本、性能脚本、验收清单、issue 收口。不做：新功能。
3. **输入**：B1–B19；T11 全门；A-10 三门。
4. **产出**：`Scripts/e2e.sh`（建会话→导入→浏览→暗房改 5 模块→导出到 Output/→备份恢复→重开校验）、`Scripts/perf.sh`（T11 + A-10 三门汇总）、验收报告。
5. **验收**：① 21 模块 oracle 全绿（一条命令汇总）；② 3 张多模块组合全链对照 dt 官方版同参数渲染过门（A-12 后无 dt 历史读，"打开 dt 修过的图"改为此条：手写夹具，模块组合覆盖头/中/尾段）；③ T11 六门 + A-10 三门达标；④ 30 分钟编辑无崩溃、RSS 增长 ≤ 20%；⑤ 产物尺寸/`qlmanage` 缩略图；⑥ 备份恢复演练 + 单拷丢调整负测（代价一/二关闭）。向用户汇报：e2e 全程跑一遍 + 门数总表 + 未达标项清单（写 issue，不带病发布）。
6. **对照**：dt 官方二进制（全链）；#26 基线。
7. **回退**：验收脚本独立；不达标写 issue 标未完成。
8. **估时**：3 lane × 3 h（原 B20 为 2 lane × 3 h；+1 = 会话 e2e + 三门复量 + 演练）。
9. **风险**：编辑等待 > 300 ms → 按 #28 定位法先测再改，本波不盲改，是否放行由用户拍板（原计划同款门）；任一 oracle 门红 → 本波只跑不改，开修复波，不扩 B20 范围。
10. **任务书草案**：输入 = 前 19 波；变换规则 = 只跑不改；验收 = 六条；产出 = 脚本 + 报告。

### §3.1 B 期零新增 crate 与 lightamer-apple 增量

- 新增 crate：无。B 期只填 A2/A3R 建好的空壳（`lightamer-pipeline/lightamer-decode/lightamer-color/lightamer-blend/lightamer-catalog/lightamer-preview/lightamer-engine/lightamer-gpui/lightamer-ai` + 四域）。`lightamer-ai` 是 L3 占位 crate 改名而来（改名在 B 期开工前执行），非新增。
- 新增依赖：`rusqlite`（B12′，L3）+ `lcms2`（B3 首用，L1）+ `lensfun`（B8，L1）+ `ort`（B14A，L3 `lightamer-ai`，MIT；原生库随包分发办法见 B14A 卡；权重运行时下载，不进 git）+ 纯 Rust 栅格/EXIF（B15/B16 在波内选型定版，L1/L3/L4）。全部先过 A1 表。
- lightamer-apple 增量：B14A（Vision 执行 + Apple 提供者）与 B18（`PresentSink` 真实实现）两处。B12′、B13′、B14、B15、B16、B17、B19、B20 对 `lightamer-apple` 零改动（边界门每波照过）。B15 内嵌预览快路径走 rawspeed 缩略图 + 纯 Rust JPEG，不经 ImageIO；ImageIO 可选快路径排 C 期。

### §3.2 B14A 与 B17–B19 的命令依赖

- B17 面板：`develop.set/reset/copy/paste` + interaction 四件 + `history.undo/redo/goto` + `process.update`（A7a）+ `develop.merge/sync`（B13′，面板高级区用 sync；硬依赖，B13′ 未合入不开工）。读：快照（设置/步/游标/作业表/会话有无）。
- B18 视口：同 B17 子集 + 快照读渲染面；零新命令。
- B19 浏览器/灯箱/对话框：`session.*`（B12′）+ `library.*`/`photo.*`/`trash.*`/`album.*`/`smart.*`/`favorite.*`（B15）+ `export.process`（B16）；零新命令。
- B14A 蒙版命令：新登记 `mask.generate` 一条（本波）；调参走 `develop.set`；栅格产物引用存快照（B13′ 落库面已就绪）；渲染读 B1–B11 管线。

---

## §4 需要用户定的事

只列真需拍板的（第 1 条已定，见下；第 2、3 条待拍板）。T-A9 十项交代在 §4.1。

1. **`Output/` 进图库预览。** 已定：进（A-18，与规划推荐相反）。语义见 §1.1（作业完成时登记 + 导出产物标记 + 「显示导出」开关默认开 + 三拒绝）。后果：B15 +1 lane（已计入 §0 合计与 T-B3）。
2. **`Trash/` 只手动清空。** 推荐：是（第 0 期只有 `trash.empty` 手动命令；容量/保留期自动规则排 C 期）。理由：官方未说明自动行为（T-A9 #6），无对齐义务；自动删源文件是不可撤回的高危动作，不应在首个可用版里猜。若用户要自动规则：定阈值（天数/容量）后再排波。
3. **引用式导入的失联修法做到哪。** 推荐：B15 只做"标 `missing` + `library.relink` 单条命令 + `sync` 扫描"；批量重链接 UI、卷感知（换盘重认）排 C 期。理由：默认导入是复制（A-15），引用是显式选项；首版先保"不丢、不错标"，批量体验后补。若用户要首版即全：B15 +1 lane。

### §4.1 T-A9 十项的去向

| # | 事项 | 去向 |
|---|---|---|
| 1 | Output 排除浏览（版本差异） | 已定：进图库预览（A-18），语义见 §1.1，B15 +1 lane |
| 2 | 同会话双开（官方未说明） | 自有设计（§1.5 锁），无需用户定 |
| 3 | 单图拖拽跟走（官方未说明） | A-15 甲下自然消解：库内移动恒一致（B15），库外裸拷丢调整是已接受代价（§2.1） |
| 4 | `.cos` 格式（官方未说明） | A-15 甲下无此文件，消解 |
| 5 | `SettingsNNN` 命名 | 无设置文件，消解 |
| 6 | Trash 自动行为（官方未说明） | 未解决 → 本 § 第 2 条请用户定 |
| 7 | 目录模板/转目录细节 | 无目录模式（A-15），消解 |
| 8 | LC 三性能数出处 | 查不到；A-10 已裁为门，§0 表分配了波次，无需用户定 |
| 9 | SQLite 批量实测数 | B12′ 微 bench + B13′ 门实测，无需用户定（超标才报） |
| 10 | 官网直取被挡 | 快照取文已解决，无需用户定 |

---

## §5 和原计划的差异

一句话：B1–B11 修验收口径（A-12/A-16），B12–B20 按会话重写（A-14/A-15/A-17），B14 扩为基础包（B14-0…B14-3），新开 B14A（AI 蒙版），`Output/` 进图库预览（A-18）。

| 波 | 原计划 | 新计划 | 为什么 | 依据 |
|---|---|---|---|---|
| B1 | 管线内核（`lightamer-core`） | 同，crate 改名 + 渲染作业/latest-wins 入本波 | A3R 改名；A-17 把代际合并留给 B1 | A-9，A-17 |
| B2 | rawspeed 解码 | 同 + 内嵌缩略图 API（给 B15） | B15 快路径的前置 | §1（本文件） |
| B3–B11 | 21 模块（XMP 读回验收） | 目标范围不变；源码钉 5.7.0 tag；验收改手写夹具；B5 加词汇扩展；B6 加不记步规则（内存态 + `display.set`，阈值持久化归 B12′） | A-12（无 dt 历史读）；A-16（5.7.0 实现，master 追赶归 C-0） | A-12，A-16 |
| B12 | 历史读（XMP→栈） | **B12′ 会话包与库**（§1 全套 + 7 命令 + CLI + 显示辅助阈值持久化） | A-12 移出历史读；A-14/A-15 会话 + 只存库 | A-12，A-14，A-15 |
| B13 | 历史写与图库 DB（双写 XMP） | **B13′ 历史持久化与批量**（单事务落库 + merge/sync + 粘贴门 + 崩溃注入） | 无 XMP；单事务；A-10 粘贴门首次实测 | A-12，A-15，A-10 |
| B14 | 蒙版与混合基础（drawn/parametric） | 基础包 B14-0…B14-3（drawn 核心/12 混合/缓存；brush、parametric 全量、raster、flexi → C-6） | 蒙版调研 Q1，用户裁决「全部按推荐」 | A-18，蒙版调研 |
| B14A | 无（新开） | AI 蒙版（ort 后端 + lumen 四类 + 点选 + 细化 + 风光/深度 + 皮肤面部 + 身体；15 lane / 45 h） | 蒙版调研 §0/Q3 + SKIN-FACE-BODY，用户裁决「全部按推荐」；风光/深度经用户确认 | A-18，蒙版调研 |
| B15 | 导入图库缩略图 | 会话浏览版（14 命令 + 三级缓存 + 四文件夹行为 + 0.5 s 门）+ 导出产物浏览 | 会话模型；A-10 缩略图门；A-18 | A-14，A-15，A-10，A-18 |
| B16 | 导出 | 同 + 默认 `Output/` + 进度/取消 + 嵌入 + 作业完成时登记产物 | 会话落点；F11 activity | A-15，A-9，A-18 |
| B17 | 界面壳与面板 | 同 + execute-only 机检 + L5 菜单表 | A-17（命令形态、菜单归界面） | A-17 |
| B18 | 视口与暗房 | 同 + lightamer-apple PresentSink 点名 + 暖切图门 | A-10 门分配；Apple 边界点名 | A-10，A-6 |
| B19 | 灯箱胶片条菜单 | 同 + 会话浏览器 + 显示导出开关；零新命令 | 会话模型；A-18 | A-14，A-15，A-18 |
| B20 | 闭环验收（开 dt 修过的图） | 会话 e2e + 手写夹具对照 + 三门复量 + 备份演练 | 无 dt 历史读；会话闭环 | A-12，A-15，A-10 |
| （新）C-0 | 无 | master 追赶波（4 模块 + 3 默认值，先评估对照源） | A-16 推迟项的归宿 | A-16 |
| （C 期） | — | `adjustments.export/import`（可选） | A-15 代价一的补偿 | A-15 |

估时对比：签字版 81 lane / 223 h → 新 **118 lane / 331 h**（+37/+108 h：`Output/`（B15）+1/+3、B14 由 2 lane 扩为 10 lane（+8/+24）、B14A 新开 +15/+45、B1d 新开 +7/+18（A-24）、PORTRAIT 新开 +6/+18（A-25））。相对原计划 76 lane / 208 h 为 +42/+123 h。ARCH T-A7 曾估 79/217（乙方案）。

全表（含每波 lane 明细）见 T-B3。

---

## §6 自审记录

自审六问（§6 任务书）逐条结论与当场改动：

| # | 问 | 结论 | 改动 |
|---|---|---|---|
| 1 | 哪一波大到一条 lane 做不完 | B15（14 命令 + 三级缓存 + bench）超单 lane 语义，但卡面已是 7 lane；缺的是 lane 内切分 | B15 估时栏补 lane 切分（导入 2 / 缩略图 3 / 浏览行为 2） |
| 2 | 命令实现依赖了还没做的东西 | 逐 T-B2 核依赖序：B12′→A7a ✓；B13′→B12′ ✓；B15→B12′/B13′ ✓；B16→B1–B11 ✓；B17→A7a/B13′ ✓；B19→B12′/B15/B16 ✓。无前向依赖 | 无（B17"若 B13′ 未合入降级"是伪条件，见 #6） |
| 3 | 三个性能数落空 | §0 表 + T-B5：三数各有首次波、量法、复量波；T11 六门同样分配 | 无 |
| 4 | 偷带设置文件或 XMP | 全文 grep：`lmsettings` 仅 §0"去掉"注记 1 处；`XMP` 仅手写 oracle 夹具（A-12 保留项）与差异表史述；B 期零 XMP 读写、零设置文件 | 无 |
| 5 | 哪一波没停下就进下一波 | 20/20 卡验收栏均有"向用户汇报"段，可独立演示 | 无 |
| 6 | 其它自审发现 | 见下 S1–S7 | 见下 |

| # | 问题 | 修法 | 位置 |
|---|---|---|---|
| S1 | B6 "不记步"的阈值无处存放（"直写 live 参数"无持久化语义） | 阈值存会话级显示辅助 JSON（切图保持）；verify 校验可解析（T4 修订：B6 只留内存态，持久化归 B12′，见 §7） | B12′ 卡 + T-B1 `_meta` 行（原 B6 卡，T4 已移） |
| S2 | B12′ 验收⑥"快照哈希全等"在本波无意义（历史接线在 B13′） | 改为"全表行哈希全等" | B12′ 卡 |
| S3 | B12′ 对照引 "T-B3"（差异表），实为 C1 引文 | 改引 `ARCHITECTURE-TABLES.md` T-A1 | B12′ 卡 |
| S4 | B12′ CLI 与草稿会话语焉不详；十万级失联扫描阻塞 open | CLI 逐条枚举；草稿会话明确保留作无盘测试态；失联扫描走作业 | B12′ 卡 |
| S5 | T-B1 缺裁剪重编规则与 process 默认语义 | 余步 `idx` 重编 0..n（游标同移）；列默认 1 仅兜底、写入恒显式 | T-B1 不变量③⑤ |
| S6 | B17"若 B13′ 未合入降级"是伪条件（波次串行，无此分支） | 改为硬依赖（B13′ 未合入不开工） | §3.2 |
| S7 | B20 验收②"手写夹具对照"与①单模块门界限不清；T-B2 头 T-A8 条数（26）与行数（18）错数 | ② 明确为 3 张多模块组合全链；T-A8 更正为 31 条 / 20 行（已逐条复数） | B20 卡 + T-B2 头 |

---

## §7 塔台修订（2026-11-26，架构裁定，用户可翻）

塔台核过 §0 到 §2 的地基，原文质量可用。以下六处是塔台改的，正文和 `PLAN-B-TABLES.md` 里标了「塔台修订」的地方就是它们；本节是理由。

- **T1 哈希不能当身份。** 原文把 `snapshots` 的主键定成 `hash64_decimal`，内容相同的步指向同一行。FNV-1a 64 位在 LightCraft 里是缓存键，撞了只是显示错一张；在我们这里是真相的键，撞了是悄悄把两份不同的设置当成一份，而且没有任何报错。概率很小，但代价是静默损坏。改成：哈希只用来查找，键命中后逐字节比对规范 JSON，相同才复用；不同就是碰撞，另存一行，键加后缀，日志里记一笔。写路径不变量加了第 ⑥ 条。
- **T2 不存引用计数。** 原文给 `snapshots` 加了 `refcount`，裁剪历史时同事务加减。计数错一次就静默损坏真相。没有步引用、也不是任何照片当前行的快照本来就是一条查询查得出来的孤儿。改成：不存计数，关会话时清一次孤儿，`session.verify` 报告孤儿数和悬空引用。
- **T3 「断电」的措辞改准。** 原文写「已提交的命令全在」。同步档是 `NORMAL` 时这只对强退和崩溃成立；断电不坏库，但可能丢最近一次 WAL 同步之后的提交。改成两句话分开写，并要求 B13′ 把 `NORMAL` 和 `FULL` 两档的耗时都量出来，默认 `NORMAL`，改不改由用户定。2026-11-27 量了：每次提交内置盘 `NORMAL` 0.05 毫秒、`FULL` 0.07 毫秒；USB 机械盘 0.8 到 2.0 毫秒、2.0 到 3.3 毫秒；再加 `fullfsync`，机械盘 41 到 55 毫秒。用户裁决改成 `FULL`，`fullfsync` 不开（A-21）。
- **T4 过曝阈值：行为归 B6，持久化归 B12′，新命令 `display.set`。** 塔台一开始判错了方向：以为 overexposed 在 darktable 里是普通模块，该进历史栈；核了 `release-5.7.0` 源码（`src/iop/overexposed.c:78` 与 `src/iop/rawoverexposed.c:75` 都是 `IOP_FLAGS_NO_HISTORY_STACK`，阈值读全局 `dev->overexposed`）才改回来——规划 lane「会话级、不进历史栈、切图保持」的语义是对的，错的只是让 B6 写 `_meta.display_aux`，而那张表 B12′ 才建。改成：B6 只做行为 + 会话级内存态（重开应用回默认值是已知行为），经新命令 `display.set` 改（从不记步，`develop.set` 不开例外，A7a 契约不动）；B12′ 补 `display_aux` 持久化与 verify 校验；「不记步」的依据是模块描述里的 darktable 标志位（overexposed、rawoverexposed、finalscale 经 `develop.set` 改是参数错误），「不进导出」的依据是 `overexposed.c:406` 的全管线 + 界面挂载条件。
- **T5 命令落库的次序（§1.8）。** B13′ 卡面原写「库事务先提交，内存随后应用，失败回滚库事务」——已提交的事务回滚不了，这句是错的。改成三步：先算好新内存态（可失败，库不动），再跑库事务提交，最后换进内存（不会失败）；A7a「出错后状态不变」的契约照旧，只是「状态」多了一半。
- **T6 命令和作业的界线（§1.9）。** A7a「命令不碰磁盘」是数据全在内存时的口径；B13′ 起命令要落库，界线重定为：命令只做有界的活（内存变更 + 至多一次有界落盘），无界的活（拷文件、扫文件夹、解码、渲染、编码、整包备份）一律由命令启动成作业，在工作线程上跑、可取消、进度走事件。B12′、B15、B16 三卡各补作业边界与「命令先返回」验收。

塔台认下的三件事（不用用户再定）：

- §4 的三条（`Output/` 进不进浏览、`Trash/` 是否只手动清空、引用式失联修法做到哪）先按 lane 的推荐做，到阶段 A 收尾时连同本计划一起给用户过目，用户不同意再改。三条都在 B15 之后才会被做到，现在改没有返工。
- 阶段 B 里 Apple 能力只在 B18 用一次（视口），导出和缩略图走纯 Rust。这符合用户「Apple 能力独占一个模块、以后可能跨平台」的意思：纯 Rust 能做的不去找 Apple，找不到替代的才进 `lightamer-apple`。
- 本文件是阶段 B 的计划，取代 `PLAN.md` §3 的 B1 到 B20。阶段 A 仍按 `PLAN.md` 加修订执行。
