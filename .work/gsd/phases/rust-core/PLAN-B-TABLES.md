# PLAN-B-TABLES — 阶段 B 会话版长表（正文见 PLAN-B.md）
> crate 名说明：文中一律用改名之后的新名（旧前缀加模块名 → `lightamer-X`；L3 占位 crate → `lightamer-ai`；改名在 B 期开工前执行）。此前的研究与核验日志里是旧名，指同一 crate。不改名：顺序夹具 `dt-order-679d594f5d.json`、模块标识、darktable 源码名。
> 日期 2026-11-26。口径：表名 `T-B*`；命令标识照 T-A8 字面；层号照 T-F9。

---

## T-B1 会话库列定义（schema v1，`<Name>.lmsessiondb`，WAL）

约定：`INTEGER` 主键即 rowid 别名；哈希一律十进制 TEXT（§1.2 纪律）；时间一律 Unix 秒 `INTEGER`；布尔 `INTEGER 0/1`。
`PRAGMA user_version = 1`；`journal_mode = WAL`；`synchronous = FULL`（用户 2026-11-27 裁决，A-21：每次提交都同步，强退和断电都不丢已提交的命令。代价是每次提交多约 1 毫秒，USB 机械盘上量的；`fullfsync` 不开）；`foreign_keys = ON`。

```sql
CREATE TABLE _meta (
  key   TEXT PRIMARY KEY,
  value TEXT NOT NULL
); -- 行：schema_version | 1, session_uuid | <uuid4>, created_by | <app+版本>, created_at | <unix>, display_aux | <JSON，可缺省，显示辅助阈值（B6 行为与命令，B12′ 持久化）>

CREATE TABLE photos (
  id                  INTEGER PRIMARY KEY,
  uuid                TEXT NOT NULL UNIQUE,      -- 跨库引用稳定标识
  path                TEXT NOT NULL,             -- kind=0 会话内相对（Capture/…），=1 外部绝对
  path_kind           INTEGER NOT NULL CHECK (path_kind IN (0, 1)),
  file_name           TEXT NOT NULL,             -- 展示与命名模板用
  width               INTEGER,                   -- 解码/B15 回填前可空
  height              INTEGER,
  file_size           INTEGER,
  captured_at         INTEGER,                   -- EXIF 拍摄时间，无则 NULL
  imported_at         INTEGER NOT NULL,
  camera              TEXT,                      -- EXIF 检索列（可空，下同）
  lens                TEXT,
  iso                 INTEGER,
  focal_mm            REAL,
  aperture            REAL,
  shutter_s           REAL,
  rating              INTEGER NOT NULL DEFAULT 0 CHECK (rating BETWEEN 0 AND 5),
  label               INTEGER NOT NULL DEFAULT 0, -- 色标 0=无，1..N 调色板位
  flag                INTEGER NOT NULL DEFAULT 0 CHECK (flag BETWEEN -1 AND 1), -- -1 拒绝，1 挑选
  process             INTEGER NOT NULL DEFAULT 1, -- 当前步快照 process 的镜像（§1.2）
  cursor              INTEGER NOT NULL DEFAULT 0, -- 游标（history_steps.idx）
  current_hash        TEXT NOT NULL,             -- 当前快照的键（缺省 = hash64_decimal，见 snapshots）
  trash_original_path TEXT,                      -- 在 Trash 内才非空
  trash_original_kind INTEGER CHECK (trash_original_kind IN (0, 1)),
  missing             INTEGER NOT NULL DEFAULT 0, -- 引用式文件失联标记
  is_export           INTEGER NOT NULL DEFAULT 0  -- 导出产物标记（A-18：导出作业完成时登记；1 = 导出产物，见 PLAN-B §1.1）
);
CREATE INDEX idx_photos_path ON photos (path_kind, path);
CREATE INDEX idx_photos_rating ON photos (rating);
CREATE INDEX idx_photos_flag ON photos (flag);
CREATE INDEX idx_photos_process ON photos (process);
CREATE INDEX idx_photos_captured ON photos (captured_at);

CREATE TABLE snapshots (
  hash TEXT PRIMARY KEY,  -- 快照的键：缺省 = PhotoSettings::hash64_decimal；哈希碰撞时加 "#2" 一类后缀（PLAN-B §1.2）
  json TEXT NOT NULL      -- 规范 JSON（含 format_version 与 process）。键命中后必须和它逐字节比对，相同才复用
);
-- 不存引用计数：没有步引用、也不是任何照片当前行的快照就是孤儿，一条查询查得出来。

CREATE TABLE history_steps (
  photo_id      INTEGER NOT NULL REFERENCES photos (id) ON DELETE CASCADE,
  idx           INTEGER NOT NULL,  -- 步序，0 起；与 HistoryStack 步序一致
  label         TEXT NOT NULL,     -- 提交命令的标识（如 develop.set）
  snapshot_hash TEXT NOT NULL REFERENCES snapshots (hash),  -- 快照的键
  created_at    INTEGER NOT NULL,
  PRIMARY KEY (photo_id, idx)
);
CREATE INDEX idx_steps_hash ON history_steps (snapshot_hash);

CREATE TABLE keywords (
  id   INTEGER PRIMARY KEY,
  name TEXT NOT NULL UNIQUE
);
CREATE TABLE photo_keywords (
  photo_id   INTEGER NOT NULL REFERENCES photos (id) ON DELETE CASCADE,
  keyword_id INTEGER NOT NULL REFERENCES keywords (id) ON DELETE CASCADE,
  PRIMARY KEY (photo_id, keyword_id)
);

CREATE TABLE albums (
  id         INTEGER PRIMARY KEY,
  name       TEXT NOT NULL,
  kind       TEXT NOT NULL CHECK (kind IN ('album', 'smart', 'project', 'group')),
  rules_json TEXT,             -- kind='smart' 才非空；查询时求值
  created_at INTEGER NOT NULL
);
CREATE TABLE album_photos (
  album_id INTEGER NOT NULL REFERENCES albums (id) ON DELETE CASCADE,
  photo_id INTEGER NOT NULL REFERENCES photos (id) ON DELETE CASCADE,
  position INTEGER NOT NULL DEFAULT 0,
  PRIMARY KEY (album_id, photo_id)
);
CREATE INDEX idx_album_pos ON album_photos (album_id, position);

CREATE TABLE favorites (
  id        INTEGER PRIMARY KEY,
  path      TEXT NOT NULL UNIQUE,
  path_kind INTEGER NOT NULL CHECK (path_kind IN (0, 1)),
  name      TEXT NOT NULL
);
```
索引注记：智能相册会查的列、`label`、`missing`、`is_export`、`albums.kind`、两张连接表的反向列现在没有索引，是有意的：等 B15 的十万行测出数字再定加哪些。

写路径不变量（B13′ 测试钉死）：① 一步提交 = 单事务（snapshots 查找或另存 + steps insert + photos update）；② undo/redo/goto = 游标的变更是和当前快照、处理版本号镜像写在同一条 `UPDATE` 里（`UPDATE photos SET cursor, current_hash, process`）；③ 裁剪超限步同事务删步，余步 `idx` 重编 0..n（游标同移）；孤儿快照关会话时清，`verify` 报告孤儿数与悬空引用（不存引用计数）；④ `photos.process/current_hash` 与游标步一致（verify 核对）；⑤ 处理版本号不是 1 的照片，`photos.process` 存的值和它当前步快照里的相同（写入时不依赖列默认值这一条走代码检查，不走行为测试）；⑥ 快照键命中时逐字节比对规范 JSON，不同即碰撞，另存一行并在日志里记下，测试里注入一对碰撞的键，证明两份不同的设置不会被当成一份。

---

## T-B2 命令到波的分配（全覆盖：每条恰一波）

T-A8 共 31 条命令（原文 20 行，多条一行含多命令，已逐条拆开）+ A7a 已登记的编辑、历史、作业、交互命令 + 本文件补入 3 条（`library.relink`，ARCHITECTURE.md §2 和 §9 的 R2 点名、T-A8 漏列；`display.set`，塔台补入，见 PLAN-B.md §7 T4；`mask.generate`，B14A 登记）。

| 命令 | 登记/实现/测试的波 | 备注 |
|---|---|---|
| `session.new` | B12′ | 建四件 + 库 + 锁 + 模板可选 |
| `session.open` | B12′ | 取锁 + 载库 + 失联扫描 + 报告 |
| `session.close` | B12′ | 刷脏 + checkpoint + 释锁 |
| `session.verify` | B12′ | 只读诊断（§1.6） |
| `session.backup` | B12′ | 整包拷（§1.6） |
| `session.restore` | B12′ | 拷回 + open 流程 |
| `template.save` | B12′ | 结构存应用模板库 |
| `library.import` | B15 | 复制默认 / 引用显式 + 记录 + 缩略图任务 |
| `library.sync` | B15 | 扫描增删补记录 |
| `library.relink` | B15 | 失联重链接（T-A8 漏项补入，见上） |
| `photo.moveToSelects` | B15 | 物理移动到 Selects |
| `photo.delete` | B15 | 移进 Trash（记原路径） |
| `photo.restore` | B15 | 从 Trash 移回 |
| `trash.empty` | B15 | 永久删除（不可撤回） |
| `photo.rate` | B15 | 评分（库列） |
| `photo.label` | B15 | 色标（库列） |
| `photo.flag` | B15 | 旗标（库列） |
| `album.create` | B15 | 普通相册 |
| `smart.create` | B15 | 智能相册（规则存，查询求值） |
| `favorite.add` | B15 | 收藏文件夹 |
| `favorite.remove` | B15 | 取消收藏 |
| `display.set` | B6 | 会话级显示辅助参数，不记步（塔台补入，见 PLAN-B.md §7 T4） |
| `mask.generate` | B14A | AI 蒙版生成作业启动（类/点选 + 参数 + 精细化选项）；推理与后处理在作业内，命令只登记启动 |
| `develop.set` | A7a（B13′ 接持久化） | 登记 A7a；落库 B13′，不双记 |
| `develop.reset` | A7a（B13′ 接持久化） | 同上 |
| `develop.copy` | A7a（内存剪贴板，不落库） | 剪贴板是会话态，不持久化 |
| `develop.paste` | A7a（B13′ 接持久化） | 同 set；批量语义整份替换 |
| `develop.merge` | B13′ | 按模块粒度合并（新） |
| `develop.sync` | B13′ | 按参数粒度合并（新） |
| `develop.beginInteraction` | A7a（B13′ 接持久化） | live 值内存，end 落库 |
| `develop.updateInteraction` | A7a（内存） | 同上 |
| `develop.endInteraction` | A7a（B13′ 接持久化） | 落一步 |
| `develop.cancelInteraction` | A7a（内存） | 回滚到之前 |
| `history.undo` | A7a（B13′ 接持久化） | 落库后 = 单条 UPDATE |
| `history.redo` | A7a（B13′ 接持久化） | 同上 |
| `history.goto` | A7a（B13′ 接持久化） | 同上 |
| `process.update` | A7a（B13′ 接持久化 + 重渲钩） | 升号落库并失效缓存 |
| `job.cancel` | A7a | 作业取消 |
| `export.process` | B16 | 写 Output/ + 进度（作业） |
| `adjustments.export` | C 期（可选） | A-15：B 期不做 |
| `adjustments.import` | C 期（可选） | 同上 |

零新命令的波：B1–B5、B7–B11（模块/管线/解码）、B14（形状/组合/混合参数走 `develop.set`）、B17/B18/B19（界面只调已有命令）、B20（只跑不改）；B6 登记 `display.set` 一条（塔台补入）；B14A 登记 `mask.generate` 一条。
机检：`lightamer-cli commands` 输出的 id 集合 = 上表"≤当前波"行集合（B12′ 起每波断言）。

---

## T-B3 和原计划的差异（逐波 lane 明细）

原计划 = `PLAN.md` §3（76 lane / 208 h）；签字版 = 81 lane / 223 h；新计划 = `PLAN-B.md` §3（118 lane / 331 h；A-24 加 B1d，A-25 加 PORTRAIT）。

| 波 | 原（lane × h） | 新（lane × h） | 差 | 改因（一行） |
|---|---|---|---|---|
| B1 | 3 × 3 = 9 | 3 × 3 = 9 | 0 | 改名 + 作业/latest-wins 入波 |
| B2 | 2 × 3 = 6 | 2 × 3 = 6 | 0 | + 内嵌缩略图 API |
| B3 | 6 × 2 = 12 | 6 × 2 = 12 | 0 | 源码钉 5.7.0；验收改手写夹具 |
| B4 | 4 × 3 = 12 | 4 × 3 = 12 | 0 | 同上；master 追赶归 C-0 |
| B5 | 5 × 3 = 15 | 5 × 3 = 15 | 0 | 同上；+ Text/Path 词汇扩展 |
| B6 | 3 × 2 = 6 | 3 × 2 = 6 | 0 | 同上；+ overexposed 不记步 |
| B7 | 4 × 2.5 = 10 | 4 × 2.5 = 10 | 0 | 验收改手写夹具 |
| B8 | 4 × 3 = 12 | 4 × 3 = 12 | 0 | 同上；DNG 基线走 5.7.0 |
| B9 | 3 × 2 = 6 | 3 × 2 = 6 | 0 | 同上；机内画幅自动归 C-0 |
| B10 | 3 × 3 = 9 | 3 × 3 = 9 | 0 | 验收改手写夹具 |
| B11 | 6 × 2 = 12 | 6 × 2 = 12 | 0 | 同上 |
| B12→B12′ | 3 × 3 = 9 | 4 × 3 = 12 | +1/+3 | 历史读移出；会话包与库 |
| B13→B13′ | 3 × 3 = 9 | 4 × 3 = 12 | +1/+3 | 双写 XMP 删除；单事务 + merge/sync + 粘贴门 + 崩溃注入 |
| B14 | 5 × 3 = 15 | 10 × 3 = 30 | +5/+15 | 基础包 B14-0…B14-3（蒙版调研 Q1；brush/parametric 全量/raster/flexi → C-6） |
| B14A | — | 15 × 3 = 45 | +15/+45 | AI 蒙版波新开（蒙版调研 §0/Q3 + SKIN；风光/深度经用户确认；塔台把估时从 12 调到 15 lane） |
| B15 | 4 × 3 = 12 | 8 × 3 = 24 | +4/+12 | 会话行为 + 三级缓存 + 14 命令（含补入 relink）+ 0.5 s 门 + 导出产物浏览（A-18） |
| B16 | 3 × 3 = 9 | 4 × 3 = 12 | +1/+3 | Output 默认 + activity 进度/取消 |
| B17 | 5 × 3 = 15 | 5 × 3 = 15 | 0 | + execute-only 机检 + L5 菜单表 |
| B18 | 4 × 3 = 12 | 4 × 3 = 12 | 0 | + PresentSink 点名 + 暖切图门 |
| B19 | 4 × 3 = 12 | 5 × 3 = 15 | +1/+3 | + 会话浏览器 |
| B20 | 2 × 3 = 6 | 3 × 3 = 9 | +1/+3 | 会话 e2e + 三门复量 + 备份演练 |
| 合计 | 76 / 208 h | 118 / 331 h | +42/+123 h | 含自审 ×1.2 ≈ 397 h ≈ 50 个 8h 日 |

对照四版估时：PLAN 原案 76/208 → ARCH T-A7（乙）79/217 → 签字版（甲）81/223 → 本次修订 105/295（含塔台把 B14A 从 12 lane 调到 15 lane）。
甲比乙多的 2 lane = B13′ 持久化接线测试面（乙的后台刷文件换成单事务断言）与 B20 备份演练；本次相对签字版 +24 lane / +72 h（`Output/` +1/+3、B14 2→10 lane（+8/+24）、B14A +15/+45）。

---

## T-B4 依赖选型比较（rusqlite 一行的数字为本 lane 2026-11-26 实测）

| 候选 | 版本/许可证 | 带进什么 | 结论 |
|---|---|---|---|
| **`rusqlite` + `bundled` + `backup`（推荐）** | 0.43.0，MIT；Rust ≥ 1.89（本仓 1.100 ✓） | 必带 5 个：`bitflags`（MIT OR Apache-2.0）、`fallible-iterator`（MIT/Apache-2.0）、`fallible-streaming-iterator`（MIT/Apache-2.0）、`libsqlite3-sys 0.40`（MIT）、`smallvec`（MIT OR Apache-2.0）；`bundled` 构建期：`cc`（MIT OR Apache-2.0）→ `find-msvc-tools`、`shlex`（同）；`backup` 无额外依赖；SQLite 本体公有领域。**以上许可证表达式全在 `Scripts/licenses-allow.txt` 内**（`MIT`、`MIT OR Apache-2.0`、`MIT/Apache-2.0` 行均存在）。`default-features = false` 避开 `cache/hashlink` | 采用（B12′ 钉版登记） |
| `sqlx`（SQLite） | MIT/Apache-2.0 系 | 异步运行时（tokio）、编译期宏、连接池 | 否：单写者同步场景无收益，重 |
| 裸 `libsqlite3-sys` | MIT | 手写错误/类型/绑定 | 否：重造 rusqlite 的成熟面，无收益 |
| LC 式快照 + 日志自研 | — | ~1000 行移植 + 自写查询/索引 | 否：T-A5 已否（查询面与体积代差） |
| 系统 SQLite（动态链接） | 系统库 | 无内嵌编译，冷构建最快 | 否（预案）：macOS 系统 SQLite 版本不定，可复现性降级；仅 B12′ 冷构建越 360 s 门时启用，需用户拍板 |

冷构建影响：没实测（本 lane 禁构建）。门 360 s（`Scripts/rust-budget.sh:42`）；阶段 A 冷构建约 10 s（`waves/VERIFY.md` 的 A2 一节）。B12′ 跑 `--cold` 量数并记录。

---

## T-B5 性能门分配（共 12 门：T11 五门 + A-10 三门 + 导出/内存两门 + B14A 两门）
注：T11 的批量粘贴 101 张门被 A-10 的一万张门取代，故 T11 只落五门；导出、内存两行的出处见说明列。

| 门 | 目标 | 首次 | 复量 | 说明 |
|---|---|---|---|---|
| 导入 101 张 | ≤ 4 s | B15 | B20 | DB 完成口径 |
| 缩略图 | ≥ 15 张/s | B15 | B20 | 并行；分有/无内嵌两档报数 |
| 可见缩略图刷新 | 约 0.5 s | B15（数据面） | B20（GUI） | A-10 |
| 导出 61MP | ≤ 3 s | B16 | B20 | 单张 CPU（B16 卡验收⑤） |
| 首图 | ≤ 1.2 s | B18 | B20 | fitted 2560 |
| 编辑等待 | ≤ 0.2 s p50 | B18 | B20 | fitted CPU 全链 |
| 暖切图 | ≤ 0.72 s | B18 | B20 | A-10 |
| 万张粘贴可见 | < 1 s | B13′ | B20 | A-10；不含缩略图 |
| 冷开 | ≤ 4 s | B20 | — | 含启动 |
| 连续编辑内存 | RSS ≤ 起始 + 200 MB / +20% | B18（30 min） | B20（30 min） | 两口径（B18 卡验收⑤绝对值，B20 比例） |
| AI 单类生成 | ≤ 3 s/张（61MP，推理 + 后处理，ort CPU） | B14A | B20 | 推断，B14A 实测替换 |
| AI 点选响应 | ≤ 2 s/点（encoder 已加载，含解码 + 后处理） | B14A | B20 | 推断，B14A 实测替换 |

---

## T-B6 lightamer-apple 增量（B 期）

| 波 | lightamer-apple 增量 | 说明 |
|---|---|---|
| B12′ | 无 | 边界门照过 |
| B13′ | 无 | 同上 |
| B14 | 无 | 同上 |
| B14A | Vision 人物/人脸/实例/点选执行 + Apple 提供者 | Provider 的 Apple 侧实现（`macos.rs` 内）；能力表只加平台事实字段 |
| B15 | 无 | 内嵌快路径 = rawspeed 缩略图 + 纯 Rust JPEG；ImageIO 可选快路径排 C 期 |
| B16 | 无 | 三编码器纯 Rust |
| B17 | 无 | 同上 |
| B18 | **`PresentSink` 真实实现**（CAMetalLayer） | B 期唯一增量；EDR 只做数值断言（无 EDR 屏，R8） |
| B19 | 无 | 同上 |
| B20 | 无 | 同上 |
