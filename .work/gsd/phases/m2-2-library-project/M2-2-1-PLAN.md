---
phase: m2-2
plan: "M2-2-1"
title: "Library 数据层——.lalb 单 SQLite 项目包（D3/OQ-2 裁决：project_meta + WAL/checkpoint 纪律 + backup API）；相册骨架三类相册 + Element 引用计数（OQ-6 A）；Image 物化搜索列 + FTS5 双层检索索引层（OQ-7 A）；折叠词表正本；FilterDomain.library 扩展。纯 Core，零 App 面"
wave: 1
depends_on: ["M2-1"]
autonomous: true
requirements: [M2LIB-01, M2LIB-02, M2LIB-04]
files_modified:
  - LightamerCore/Sources/Library/LibrarySchema.swift          # 新建：DDL 冻结面（project_meta/images/albums/album_content + images_fts FTS5 + 索引）+ schemaVersion=1 + user_version 双写 + 包目录常量（Media/.lathumbs）+ mini-git 预留占位注释（OQ-3 A）
  - LightamerCore/Sources/Library/LibraryError.swift           # 新建：typed 错误族（open/refuse/migrate/checkpoint/backup/constraint）
  - LightamerCore/Sources/Library/ProjectFileStore.swift       # 新建：actor——create/open/close/backup/checkpoint 纪律（写批后节流 TRUNCATE + 关闭强制 + sqlite3_backup 在线拷）
  - LightamerCore/Sources/Library/LibraryStore.swift           # 新建：actor 单写者——相册 CRUD（album/folder/filter 三类）+ album_content 成员资格 + images.ref_count 事务内联动 + Filter.data = FilterPredicateGroup JSON
  - LightamerCore/Sources/Library/ExifFold.swift               # 新建：折叠词表正本（f/2.8→f2.8+f 2 8；ISO 800→iso800+iso 800；35mm→35 mm）+ exif_search_text/words 物化合成
  - LightamerCore/Sources/Library/ExifSearchIndexer.swift      # 新建：物化列填充（ImageIO 键位 = SessionIndexSchema v2 同集）+ FTS external-content 同步 + rebuild 命令
  - LightamerCore/Sources/Session/FilterSQL.swift              # 修改：FilterDomain 增 .library case——4 处 domain 穷举 switch 各加一臂（orderBySQL tiebreaker = image_path ASC / baseline = (1=1) / columnRef = +i. 别名 / keywordsCondition 打物化 keywords 列；钉 FROM images i），禁 default 臂
  - LightamerCore/Sources/Session/SmartAlbumStore.swift        # 修改：evaluate 域 switch 增 .library 单臂（typed missingStore 占位，真实现 M2-2-3 补；.session/.catalog 分支字节不变由既有测试钉）
  - Tests/LightamerTests/LibrarySchemaTests.swift              # 新建（→ tuist generate）：冻结契约 PRAGMA table_info 逐列 / user_version 三分 dispatch / FTS5 虚表在册 / 预留占位非实体表
  - Tests/LightamerTests/LibraryDocumentTests.swift            # 新建：checkpoint TRUNCATE 后 -wal=0 / close 强制 checkpoint / backup API 在线一致性拷贝 / >v1 REFUSE
  - Tests/LightamerTests/ExifFoldTests.swift                   # 新建：词表双向（原文→折叠变体集 / 查询词→命中）+ iso800 前缀串不误伤
  - Tests/LightamerTests/LibraryStoreTests.swift               # 新建：三类相册 CRUD / 引用计数加减事务性 / 多相册一图 / filter_data JSON round-trip / 级联删除
  - Tests/LightamerTests/LibraryFilterDomainTests.swift        # 新建：.library 域 translate 形状（+i. 别名/baseline/绑定）+ 智能相册谓词全链（Group JSON → FilterSQL → 命中）
  - .work/gsd/phases/m2-2-library-project/M2-2-1-SUMMARY.md    # 新建（收口任务）
  - .work/gsd/phases/m2-2-library-project/M2-2-1-DECISIONS.md  # 新建（收口任务）
  - .work/GOAL-STATE.md                                        # 续接点追加（收口任务）
  - .work/LESSONS.md                                                 # 如踩坑
---

# Plan M2-2-1 — Library 数据层（.lalb 项目包 + 相册骨架 + 物化列/FTS5）

> **性质**：纯 Core 数据层 plan——零 App/UI 改动、零像素管线触碰。把 D-M2-2-CONTEXT
> 已签核裁决（OQ-2/3/6/7/10/12）落成 `LightamerCore/Sources/Library/` 新目录的
> schema 冻结面 + 单写者 actor 族。规格锚点 = `research/ALCEDO-FEATURE-MAP.md` §6
> （DDL 语义）+ `M2-2-CONTEXT.md`（裁决正本）+ `M2-2-RESEARCH-NOTES.md`（探针 P1/P2/P3）。
>
> **本 plan 是后续三个 plan 的缝正本**：`ProjectFileStore`（包生命周期）、
> `LibrarySchema`（DDL 冻结 + 版本）、`LibraryStore`（单写者 CRUD）、`ExifFold`
> （折叠词表——正确性承重面）、`FilterDomain.library`（唯一 SQL 面扩展），
> 全部在此定死 API 形态，P2 导入 / P3 查询 / P4 剥离只消费不重开。

## 已定裁决（不得重开）

- **OQ-2（D3 细化）**：`.lalb` = **单个 SQLite 文件**；manifest（项目名/创建时间/schema
  版本/视图状态）入 `project_meta` 表 + `PRAGMA user_version` 双写（读走 user_version）；
  journal = WAL + synchronous=NORMAL + 写批后节流 `wal_checkpoint(TRUNCATE)` + 关闭强制；
  「备份」走 `sqlite3_backup` API。探针 P3：严格零伴生不可得（clean close 仍留 0 字节
  `-wal`）——单文件语义 = 「一个数据文件 + checkpoint 纪律下的空伴生」。
- **OQ-3**：`.lra` 恒真身，项目库 v1 = 组织 + 检索投影 + 引用。`EditCommit`/`VersionRef`/
  `ImageEditState`/`PipelineRoot` **只留 schema 注释占位（不建空表）**；编辑态判定沿用
  `has_edits`/`params_hash` 投影列（session.lindex 同型）。
- **OQ-6**：相册骨架 = **语义对齐 + 表形简化**——三类相册（普通/文件夹/智能）+ Element
  引用计数模型保留；`SleeveRoot`/`ComboFolder` 合并为 `albums.type` 判别字段；
  `Filter.data` = **`FilterPredicateGroup` Codable JSON**（既有模型，`FilterSQL` 消费，
  零格式新增）。
- **OQ-7**：双层检索——结构化物化列（`FilterSQL` 域）+ `exif_search_words` 折叠文本列上
  **FTS5 external-content 表**（`tokenize=unicode61` **不定制**，P2 探针风险注：注册
  tokenchars 会让 `f/2.8` 变单词致 `f2.8` 失配——一切归一化交给折叠物化）。
- **OQ-10**：缩略图缓存落位常量本 plan 钉死：`<项目目录>/.<stem>.lathumbs/`（真身不混
  派生缓存；接线归 M2-3，本 plan 只落常量与文档注释）。
- **OQ-12**：默认 RAW 白名单 = Alcedo 0.3.0 十种 ∪ Apple 补充四种（`.pef/.orf/.rwl/.iiq`）；
  附属排除表硬编码。**常量本 plan 落在 LibrarySchema（与 schema 同冻结），消费在 P2**。

## 关键设计决策（planner 裁决，执行中不重开）

### KD-1 包目录形态 = `.lalb` 文件 + 同目录伴生目录（移动 = 整目录走）

OQ-2 裁了 DB 是单文件，但 copy/move 导入的物理照片、OQ-10 的缩略图缓存都要有家。
裁决（P1 落常量，P2 消费）：

```
<项目目录>/
  <stem>.lalb            # SQLite 真身（manifest 在 project_meta 表）
  Media/                 # copy/move 导入的物理照片（可见目录，保源子树结构）
  .<stem>.lathumbs/      # 缩略图缓存（派生物，可重建；OQ-10 A1）
```

- `image_path` 存储三类形态由 `path_kind` 判别：**0 = 项目相对**（Media/ 下，整目录
  移动免疫挂载点改名）/ **1 = 卷相对 + volume_uuid**（软链接导入同卷，L009 场景）/
  **2 = 绝对 + volume_uuid**（跨卷降级）。resolve 规则与 stale 检测在 P2 `ImageLinker`
  实现，本 plan 只冻结列。
- 「整体移动/备份」语义 = 移动整个项目目录 + DB 层 backup API；SUMMARY 记录该口径。

### KD-2 schema 版本化 = SessionIndexSchema 三分语义 + 迁移前 backup 快照缝

`user_version` dispatch：absent/0 → fresh create（v1）+ 写 `project_meta` + set 1；
1 → ok；**>1 → typed REFUSE**（本二进制早于文件，永不猜未来 schema）。v1 无迁移表，
但 dispatch 结构与「N→N+1 迁移前自动 `sqlite3_backup` 快照」hook 现在建好（照
`SessionIndexSchema` 头注契约；16-x CatalogIndexSchema 同型），M2-8/M2-10 激活预留表时
走同缝。`project_meta` 存 `project_name`/`created_at`/`display_state`（JSON，M2-3 消费），
schema 版本真源 = user_version（OQ-2 字面）。

### KD-3 L013 哈希纪律延续 + images 冻结列清单（完整枚举）

`params_hash` 一律 **DECIMAL TEXT**（UInt64String 语义，禁 INTEGER）；EXIF 轻列名与
`SessionIndexSchema.imagesColumns` v2 完全同名同型（`camera_make/camera_model/lens_model/
iso/focal_length/aperture/exposure/capture_date`），`FilterSQL` 的 `FilterField→column`
映射零改动即可服务项目库。`images` 冻结列清单（T1 `imagesColumns` 冻结序表逐列，
序即 DDL 序）：

- **`id INTEGER PRIMARY KEY` 置首**——FTS `content_rowid='id'`、album_content 外键、
  keyset seek 第二列全靠它，缺它三处消费面同时断。
- `image_path` + `path_kind` + `volume_uuid`——KD-1 三类路径形态载体（path_kind 的
  实体列是 `image_path`）。
- EXIF 轻列八列 + `file_stem/file_ext/exif_search_text/exif_search_words`（M2LIB-04
  新增四列，Alcedo `image_search_columns.hpp` 同名语义）。
- `rating/color_label/keywords/filename/dir` + `flag/note`——**D-09-CONTEXT-7 预留
  NULL 列模式**（现在建、后填，免 ALTER 迁移）；session 四子句谓词形态（filename/
  dir/rating/keywords）借此直接服务项目库（KD-7 `keywordsCondition` `.library` 臂
  打的就是物化 `keywords` 列）。
- `has_edits/params_hash` 投影列（session.lindex 同型，L013 TEXT）+ `ref_count`
  （KD-4）+ `added_time/modified_time`。

T1 落表后与消费点交叉核对一遍：FTS `content_rowid` / album_content 外键 / M2-2-3
keyset `(capture_date, id)` seek / M2-2-3 四分组列（`camera_make||camera_model`、
rating 星档）/ 库域排序子集列（M2-2-3 KD-3 白名单）——每处都能在清单中点到实名列。

### KD-4 引用计数 = `images.ref_count` 物化列 + `album_content` 成员资格同事务联动

Alcedo `Element.ref_count` 语义保留为 images 行上的物化列：相册加入/移出与 ref_count
增减在**同一事务**（单写者 actor 保证）；删相册级联删 `album_content`（FK ON DELETE
CASCADE）并递减 ref_count；ref_count 归零**不删** images 行（图片本体引用独立，移出库
= 显式 remove API，P3/管理层消费）。不选「COUNT 派生」：网格排序/过滤要用它，派生面
每次 join 得不偿失（20k 行 COUNT 也要全扫 album_content）。

### KD-5 FTS5 同步 = external-content + 触发器 + 显式 rebuild

```sql
CREATE VIRTUAL TABLE images_fts USING fts5(
  exif_search_words, content='images', content_rowid='id', tokenize='unicode61');
```

**FTS 列名与 images 物化列同名（`exif_search_words`）**——external-content 的
rebuild 按 content 表同名列取数，异名 = `VALUES('rebuild')` 直接报 no such column。
images 三触发器（INSERT / DELETE / UPDATE OF exif_search_words）保持虚表同步，映射
一律 `new.exif_search_words`；`INSERT INTO images_fts(images_fts) VALUES('rebuild')`
供全量重建（P2 导入批尾与未来迁移消费）。
导入路径写放大可忽略（探针 P2：20k 导入 + rebuild 共 125ms）。**tokenizer 零定制**
（OQ-7 裁决；P2 探针 tokenchars 风险注钉进 DDL 注释）。

### KD-6 checkpoint 纪律参数（探针 P3 对策）

`ProjectFileStore` 写批出口调 `checkpointIfNeeded()`：距上次 ≥2s 或自上次以来写入批
≥64 时执行 `wal_checkpoint(TRUNCATE)`（节流常量入 schema 注释；SidecarStore 2s debounce
同型）；`close()` 先强制 TRUNCATE checkpoint 再 close（rc 检查，失败 typed error 记录
不静默）。backup = `sqlite3_backup_init/step/finish` 全库在线拷（打开态一致性单文件，
P3 探针实证）。

### KD-7 `FilterDomain.library` = catalog 域的别名变体，模板零新机制

`FilterDomain` 增 `.library` case，**5 处 domain 穷举 switch 各加一臂（禁 default，
穷举编译器强制）**：

| 触点 | `.library` 臂语义 |
|---|---|
| `FilterSQL.baselineClause` | `(1=1)`（项目库无 orphan 扫描语义） |
| `FilterSQL.columnRef` | `+i.<col>`（F10 排序领先纪律同 catalog） |
| `FilterSQL.keywordsCondition` | 物化 `keywords` 列直打（KD-3 预留列；session 谓词形状 + `+i.` 引用，empty/notEmpty = NULL/'' 双态） |
| `FilterSort.orderBySQL(domain:)` | tiebreaker = `image_path ASC`（库内实存列、每行恒非 NULL——session `path ASC` / catalog `rel_path ASC` 同族；file_stem 为备选，落 DECISIONS） |
| `SmartAlbumStore.evaluate` | typed `missingStore` 占位臂（真实现 M2-2-3 补；`.session`/`.catalog` 分支字节不变） |

查询面钉 `FROM images i`（模板注释承载，与 catalog `FROM catalog_images i` 同惯例）。
`scanEpoch` 排序的库域守卫不在本 plan（该列不在 images 冻结清单——白名单排除落
M2-2-3 KD-3 `LibraryQueries` 入口）。`.session` 域字节不变（默认参数 = 现行为，
M2-1 KD-2 同款红线）——既有 1889 基线测试零改动。

## read_first

1. `.work/gsd/phases/m2-2-library-project/M2-2-CONTEXT.md`——裁决正本（OQ-2/3/6/7/10/12
   + Reusable Assets 表）。
2. `.work/gsd/phases/m2-2-library-project/M2-2-RESEARCH-NOTES.md`——探针 P1（3.54.0 +
   FTS5）/P2（折叠词表 17×）/P3（WAL 残壳 + backup）。
3. `research/ALCEDO-FEATURE-MAP.md` §6——Alcedo DDL 语义（照抄语义不照抄表形）。
4. `LightamerCore/Sources/Session/SQLiteHandle.swift`——连接层全文（open flags/
   busy_timeout 5s/exec/prepare/显式 close；`:138` class 起始）。
5. `LightamerCore/Sources/Session/SessionIndexSchema.swift`——冻结契约头注 + v2 列表
   （`:66-101`）+ user_version dispatch 三分语义（KD-2 正本）。
6. `LightamerCore/Sources/Session/FilterSQL.swift`——translate（`:149`）/FilterDomain
   （`:135`）/columnRef（`:220`）/baselineClause（`:194`）——`.library` 落点。
7. `LightamerCore/Sources/Catalog/CatalogIndexSchema.swift` + `CatalogIndexStore.swift`
   ——第二先例（keyset 分页 `:175/:236` 本 plan 不实现但索引/别名惯例对齐）。
8. `AGENTS.md`「Phase 2 架构增量」节（L013 DECIMAL TEXT / L009 原子写 / Core 级可单测
   目录惯例）。

## 纪律（强制）

1. **提交纪律**：每任务独立提交（Conventional Commits 全英文、subject ≤72 字符祈使句、
   body 写 what+why）；只 add 本任务申报文件；**不 push**；git add 用 `.work/gsd/...`
   真路径（`.planning` 链接垫片不穿透）。
2. **构建纪律**：`caffeinate -dis` 包裹一切构建；**不加 `-derivedDataPath`**；新建
   .swift 文件后同 commit 内跑 `tuist generate`（T1 批量建文件 → generate 一次即可，
   后续任务零新文件不重复跑）。
3. **测试纪律**：单测命令 = `Scripts/test-direct.sh '<Class>'`；判据 = Executed 计数行 +
   failures 行双读（L028）。**回归基线 = 1889/11skip/0fail**。每任务全套 suite 绿、
   0 fail；在案 flake（GoldenColor CI 腿等）单跑 ×3 归因入 SUMMARY 不计违约。
4. **边界纪律**：每任务边界检查 `.work/config.toml [gsd]`（`auto`/`paused`）。
5. **架构红线**：禁触 `LightamerCore/Sources/{Pipe,Sidecar,Metal,Decode}/` 生产文件与
   12-5 `Lut3d/LutLibraryStore`；`Session/` 域只许动两处——`FilterSQL.swift`（`.library`
   case 增补，`.session`/`.catalog` 分支字节不变）与 `SmartAlbumStore.swift`
   （**显式例外：evaluate 域 switch 单臂 only**——`.library` missingStore 占位臂，
   禁动该文件其它任何代码）；T5 收口 `git diff --stat` 核对申报一致。

## Tasks

### T1 LibrarySchema 冻结面 + typed 错误族

- **read_first**：上列 1/3/5/8。
- **action**
  1. 新建 `LightamerCore/Sources/Library/LibrarySchema.swift`：
     - `schemaVersion = 1`；`userVersionRead/Write` helper（PRAGMA user_version）。
     - DDL 冻结面（`project_meta` / `images` / `albums` / `album_content` +
       `images_fts` 虚表 + 三触发器 + 索引 `idx_images_capture(capture_date, id)` 与
       `idx_album_content_image(image_id)`）：`imagesColumns: [(name, type)]` 冻结序表
       == KD-3 完整清单（`id INTEGER PRIMARY KEY` 置首 + `image_path/path_kind/
       volume_uuid` + EXIF 八列 + `file_stem/file_ext/exif_search_text/exif_search_words`
       + `rating/color_label/keywords/filename/dir` + `flag/note` +
       `has_edits/params_hash/ref_count/added_time/modified_time`），
       `albumsColumns`/`albumContentColumns` 同型（`album_content.image_id REFERENCES
       images(id)` 外键钉在冻结序表内）。
     - 包目录常量（KD-1）：`mediaDirectoryName = "Media"`、
       `thumbsDirectoryName(stem:) = ".<stem>.lathumbs"`、`fileExtension = "lalb"`。
     - RAW 白名单/排除表常量（OQ-12；`defaultRawExtensions: Set<String>` 14 项 +
       `hardcodedSidecarExclusions`，头注指向 M2-2-2 消费）。
     - mini-git 预留占位（OQ-3 A）：文件尾注释块誊 Alcedo EditCommit/VersionRef/
       ImageEditState/PipelineRoot DDL 语义 + 「M2-8 激活、M2-4 后 schema 才稳定」注；
       **不建实体表**。
  2. 新建 `LibraryError.swift`：typed 族（`openFailed`/`futureSchema(version:)`/
     `migrationFailed`/`checkpointFailed(code:message:)`/`backupFailed`/
     `constraintViolation`/`notOpen`），`Equatable + Sendable`。
  3. 新建 `Tests/LightamerTests/LibrarySchemaTests.swift`（新文件 → `tuist generate`）：
     - 冻结契约：`PRAGMA table_info` 逐列 == `imagesColumns`/`albumsColumns`/
       `albumContentColumns` verbatim（SessionIndexSchema 测试同款）。
     - fresh create 后 `user_version == 1` + `project_meta` 含 name/created_at。
     - `sqlite_master` 查询：`images_fts` 存在且 `sql` 含 `tokenize='unicode61'` 且
       FTS 列名 == `exif_search_words`（与 images 列同名钉——KD-5 rebuild 依赖）；
       三触发器在册（映射列 == `new.exif_search_words`）；**EditCommit/VersionRef/
       ImageEditState/PipelineRoot 均不存在**（负例钉 OQ-3 注释占位裁决）。
     - 白名单常量 == 14 项精确断言；排除表含 `.xmp/.lra/.lightamer-preset/.pp3/.opc`。
  4. `Scripts/test-direct.sh 'LibrarySchemaTests'` 绿 + 全套回归 0 fail。
- **验收标准**
  - [ ] 三表 + FTS 虚表 + 触发器 + 2 索引 DDL 冻结断言全绿；预留四表负例在册。
  - [ ] user_version fresh==1；白名单/排除表常量断言全绿。
  - [ ] 全套回归 `0 fail`（1889 基线 + 本任务新增）。

### T2 ProjectFileStore——包生命周期 + checkpoint/backup 纪律

- **read_first**：上列 2/4 + `LightamerCore/Sources/Catalog/CatalogProjector.swift:108-196`
  （actor 持 handle + close 先例）。
- **action**
  1. 新建 `ProjectFileStore.swift`（actor，单 handle 持有者）：
     - `create(at: URL, name: String)`——路径尾缀校验 `.lalb`；建库（KD-2 fresh 腿）+
       `project_meta` 播种；返回已开 store。
     - `open(at: URL)`——存在性 + user_version 三分 dispatch（KD-2；>1 →
       `.futureSchema`）；WAL+NORMAL PRAGMA（SessionIndexSchema 头注 synchronous=NORMAL
       非 OFF 纪律同源）。
     - `close()`——强制 `wal_checkpoint(TRUNCATE)` → `handle.close()`（KD-6）。
     - `backup(to: URL)`——`sqlite3_backup` API 在线拷（KD-6）；目标存在 = typed 拒绝。
     - `checkpointIfNeeded()` 节流（KD-6 常量）；`withHandle` internal 缝供
       LibraryStore/Indexer 同 actor 域消费（handle 恒单 actor 独占）。
  2. 新建 `Tests/LightamerTests/LibraryDocumentTests.swift`：
     - open absent → fresh；open v1 → ok；手改 `user_version=2` reopen →
       `.futureSchema` 精确断言。
     - 写批 → `checkpointIfNeeded` → `-wal` 0 字节（`stat` 断言）；close 后 `-wal`
       仍 0（探针 P3 纪律复钉）。
     - 打开态 `backup(to:)` → 目标文件可独立 open 且行数一致（写入 N 行后拷）。
     - backup 目标已存在 → typed 拒绝；close 幂等。
- **验收标准**
  - [ ] dispatch 三分 + REFUSE 全绿；checkpoint/close 后 `-wal == 0 字节` 实测断言全绿。
  - [ ] backup 在线拷一致性断言全绿；typed 错误面全覆盖。
  - [ ] 全套回归 `0 fail`。

### T3 ExifFold 词表正本 + ExifSearchIndexer

- **read_first**：上列 2（P2 节全文——折叠词表语义正本）+ `MetadataService.swift`
  （EXIF 键位消费面参考）+ `SessionIndexStore.swift:892`（backfillExifMetadata 同路径
  键位对照，不修改该文件）。
- **action**
  1. 新建 `ExifFold.swift`：
     - `foldedVariants(for: ExifFacts) -> (text: String, words: String)`——输入结构化
       EXIF 事实（iso/focal/aperture/camera/lens/stem/date），输出折叠文本列内容：
       `f/2.8 → f2.8` + `f 2 8`；`ISO 800 → iso800` + `iso 800`；`35mm → 35 mm`；
       日期多拼写（`20240601`/`2024-06-01`/`202406` 族）+ 小写折叠 + 空白归一。
       **词表常量 + 纯函数**（无 IO，双测面）。
     - `matchQueryToken(_ raw: String) -> [String]`——查询词 → 折叠变体集（双向对齐）。
  2. 新建 `ExifSearchIndexer.swift`：
     - `fillMetadata(imageID:from: URL)`——ImageIO 读 EXIF 轻列（键位 ==
       SessionIndexSchema v2 同集）→ UPDATE images 结构化列 + `exif_search_text/words`
       （ExifFold 合成）；FTS 触发器自动同步（KD-5）。
     - `rebuildFTS()`——`VALUES('rebuild')` 命令。
  3. 新建 `Tests/LightamerTests/ExifFoldTests.swift`：
     - 词表双向：原文事实 → words 含全部折叠变体（逐条断言 `f2.8`/`f 2 8`/`iso800`/
       `iso 800`/`35 mm` 等）；查询词 `iso800` → 变体集含命中形式。
     - 前缀串不误伤：`iso8000` 值的行不被 `iso800` 查询命中（探针 P2 正确性抽核复钉，
       经 FTS MATCH 实库断言）。
     - Indexer round-trip：插入行 → fill → `images_fts MATCH 'f2 8'`（或 folded 形式）
       命中该行；rebuild 后计数不变。
- **验收标准**
  - [ ] 折叠词表双向断言全绿；`iso800` 精确命中不含前缀串实库断言全绿。
  - [ ] FTS 触发器同步 + rebuild 幂等全绿。
  - [ ] 全套回归 `0 fail`。

### T4 LibraryStore 单写者 + FilterDomain.library

- **read_first**：上列 6 + `LightamerCore/Sources/Session/SmartAlbumStore.swift`
  （SmartAlbumDocument envelope 同构参照 + `evaluate` 域 switch `.library` 臂落点，
  `:292` 起）+ `CatalogSmartAlbumDomainTests.swift`（catalog 域 translate 测试形状
  先例）。
- **action**
  1. 新建 `LibraryStore.swift`（actor，持 ProjectFileStore）：
     - 相册 CRUD：create（type: album/folder/filter + parent 树）/rename/moveParent/
       remove（级联 content + ref_count 递减，单事务）；`filter` 类校验
       `FilterPredicateGroup.validating()` 后存 `filter_data` JSON（Codable round-trip）。
     - 成员资格：`add(imageID:to:)`/`remove(imageID:from:)`/`members(of:)`——
       album_content 写 + `images.ref_count` 同事务增减（KD-4）。
     - images 行面：`insertImage(record:)`（含 path_kind/volume_uuid 结构）/
       `removeImage`（连带全部 membership 清理）/`updateProjection`（has_edits/
       params_hash 投影，L013 TEXT）。
  2. `FilterSQL.swift`（4 处）+ `SmartAlbumStore.swift`（1 处）：`FilterDomain` 增
     `.library`，**5 处 domain 穷举 switch 各加一臂、禁 default**（KD-7 全表）——
     `FilterSort.orderBySQL(domain:)`（`:112`，tiebreaker = `image_path ASC`）/
     `baselineClause`（`:195`，`(1=1)`）/ `columnRef`（`:223`，`+i.<col>`）/
     `keywordsCondition`（`:261`，物化 `keywords` 列）/ `SmartAlbumStore.evaluate`
     （`:292`，单臂 = typed `missingStore` 占位，真实现 M2-2-3 补）。模板注释钉
     `FROM images i`。`.session`/`.catalog` 分支字节不动（既有测试钉）。
  3. 新建 `Tests/LightamerTests/LibraryStoreTests.swift`：三类相册 CRUD/树/级联；
     一图入多相册 ref_count==N；删相册递减；filter_data JSON round-trip；removeImage
     清 membership。
  4. 新建 `Tests/LightamerTests/LibraryFilterDomainTests.swift`：`.library` translate
     形状（`+i.` 别名 / `(1=1)` baseline / binds 顺序）；智能相册全链（Group → JSON →
     库行 → translate → 实库查询命中）；`.session` 域回归快照（既有
     FilterSQL 相关测试零改动全绿即证，补一条显式对账）。
  5. 全套回归 0 fail。
- **验收标准**
  - [ ] 引用计数事务性断言全绿（加/减/级联/归零不删行）。
  - [ ] `.library` 域 translate + 智能相册全链全绿；`.session` 域既有测试零改动全绿。
  - [ ] 5 处穷举 switch 全带 `.library` 臂、零 default 臂（编译器穷举证明 +
        `git grep "case .library"` 五触点齐全）；`.session`/`.catalog` 输出字节
        回归快照一致。
  - [ ] 全套回归 `0 fail`。

### T5 收口——SUMMARY/DECISIONS + 续接点

- **read_first**：本 plan AC 表 + `.work/GOAL-STATE.md` 续接点节。
- **action**
  1. AC 逐条机检 + 全套回归终跑（计数/秒数入 SUMMARY）。
  2. 落盘 `M2-2-1-SUMMARY.md`（测试数变化 / KD-1 包目录口径声明 / 常量钉死清单）+
     `M2-2-1-DECISIONS.md`（KD-1..7 执行确认 + 偏差归因）。
  3. `.work/GOAL-STATE.md` 续接点追加（M2-2-1 完成 + 下一步 = M2-2-2）；LESSONS 如踩坑。
  4. `git diff --stat` 核对文件边界与 front-matter 一致（纪律 5）。
- **验收标准**
  - [ ] AC 表全绿；SUMMARY/DECISIONS/GOAL-STATE 同批落盘；diff 边界无越界文件。

## 验收标准（AC 总表，逐条可机检）

| # | AC | 机检方式 |
|---|---|---|
| 1 | `images`/`albums`/`album_content` 列冻结序 == 声明表 verbatim；`project_meta` 播种 | LibrarySchemaTests PRAGMA table_info 逐列断言 |
| 2 | `images_fts` = external-content + unicode61 不定制；三触发器在册；rebuild 幂等 | sqlite_master 断言 + ExifFoldTests rebuild |
| 3 | mini-git 四表**不存在**（注释占位）；`has_edits/params_hash` 投影列在（L013 TEXT） | sqlite_master 负例 + schema 常量断言 |
| 4 | user_version 三分：absent→fresh=1 / 1→ok / >1→`.futureSchema` | LibraryDocumentTests |
| 5 | checkpoint 纪律：写批后节流 TRUNCATE、close 后 `-wal == 0` 字节实测 | stat 断言 |
| 6 | backup API 打开态拷贝 = 一致性单文件（独立 open 行数一致）；目标存在拒绝 | LibraryDocumentTests |
| 7 | 折叠词表双向（`f2.8`/`iso800`/`35 mm` 变体集）+ `iso800` 不命中 `iso8000` 前缀串 | ExifFoldTests + FTS 实库断言 |
| 8 | 引用计数：多相册 ref_count==N、删相册递减、级联清理、归零不删行 | LibraryStoreTests 事务断言 |
| 9 | `FilterDomain.library`：5 处穷举 switch 臂全落（`+i.` 别名 + `(1=1)` baseline + `image_path` tiebreaker + 物化 `keywords` 列 + evaluate `missingStore` 占位），禁 default；智能相册 JSON 全链命中；`.session`/`.catalog` 域零回归 | LibraryFilterDomainTests + 既有域测试零改动全绿 |
| 10 | 全套回归 0 fail，计数 ≈ 1889 + 25..35 | test-direct.sh Executed/failures 双读 |
| 11 | diff 边界 == 申报文件集；`Session/` 域仅 FilterSQL.swift + SmartAlbumStore.swift（evaluate 单臂）两处改动 | `git diff --stat` 逐任务核对 |

## 风险与边界

- **WAL 残壳**（探针 P3）：纪律面已入 KD-6；残余风险 = 用户手动裸拷主文件丢尾部事务
  ——SUMMARY 声明「备份必须走 backup API」，M2-3 UI 只暴露 backup/move 命令不暴露裸拷
  路径。`journal_mode=DELETE` fallback 仅登记不实现。
- **FTS5 触发器写放大**：探针 P2 实测 20k 导入 + rebuild 共 125ms，非风险；P3 基准
  harness 复测导入吞吐作观察项。
- **`FilterSQL.swift` 是 M1 冻结面**：`.library` arm 增补属裁决内（CONTEXT Reusable
  Assets 表「新域模板扩充」）；`SmartAlbumStore.evaluate` 单臂属同族（穷举 switch
  编译器强制——无 default 时新 case 不加臂即编译失败）；任何 `.session`/`.catalog`
  字节漂移 = 红线违约，测试 #9 钉。
- **USB 卷（L009）**：本 plan 全部测试落 `/tmp` 或 temp 目录（throwaway），禁外置卷
  落库；volume_relative 形态只测逻辑（P2 ImageLinker 落地实测）。
- **新建文件批量**：T1 一次建齐 5 个 Core 文件 + 测试，`tuist generate` 一次；后续任务
  零新文件。

## 提交约定

- T1 `feat(library): frozen library schema v1 with versioned package dispatch`
- T2 `feat(library): project file store with checkpoint discipline and backup api`
- T3 `feat(library): exif fold vocabulary and fts5 search indexer`
- T4 `feat(library): library store albums with refcounts and filter domain`
- T5 `docs(m2-2): close out plan 1 library data layer`
- 全英文 Conventional Commits；body 写 what+why + 同批同步的 md 清单；不 push。
