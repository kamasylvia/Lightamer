# Phase M2-2: 图库与项目模型（Alcedo 方式）— Context

> discuss/research 起草稿（2026-09-27）。规格锚点 = `research/ALCEDO-FEATURE-MAP.md` §1.2 / §6 / §8；需求 = REQUIREMENTS **M2LIB-01..07**；签核决定点 = **D3（SQLite 单项目文件，已签核「全按推荐」）**。探针实测见同目录 `M2-2-RESEARCH-NOTES.md`。

## Phase Boundary

**范围**（ROADMAP M2-2 行 + M2LIB-01..07）：

1. **SQLite 单项目文件包**（M2LIB-01，D3）——`.lalb` 项目文件：相册结构 + 检索物化列一个文件内，可整体移动/备份；schema 版本化。
2. **相册骨架**（M2LIB-02）——Sleeve/Folder/Filter（智能相册）语义 + Element 引用计数模型（Feature-map §6.2）。
3. **文件夹导入**（M2LIB-03/07）——三方式（移动/复制/软链接）询问对话框 + RAW-only 过滤加固 AC（Alcedo 0.3.0 上游零过滤缺陷反向教训三 AC：后缀白名单精确匹配 / sidecar 排除 / 真实 C1 Session fixture）+ 进度反馈。
4. **Image 物化搜索列 + EXIF 词法检索**（M2LIB-04）——`file_stem/capture_at/camera/lens/iso/focal/aperture/rating` + 词边界折叠检索文本；`iso800`/`f/2.8`/`35mm`/日期多格式 AND 组合；性能对标 ~20ms@2 万张。
5. **Album Inspector 数据面**（M2LIB-05）——总数卡 + 四分组（日期/相机/标签/镜头）+ Activity view 按日计数 + 搜索过滤态（数据/查询面；面板渲染归 M2-3，见 OQ-11）。
6. **Sessions/Catalogs 剥离**（M2LIB-06）——UI 不暴露、入口禁用、代码保留可回切。
7. **最小功能 UI**——导入询问对话框 + 导入进度（功能闭环所需；图库网格/Inspector 面板/搜索对话框的壳归 M2-3）。

**非目标（本 phase 明确不做）**：

- **mini-git 历史建账**（M2-8）——`EditCommit`/`VersionRef`/`ImageEditState` 表**只在 schema 预留位**（建骨架表或注释占位，见 OQ-3），不写不读。
- **语义/AI 表激活**（M2-10）——`Semantic*`/`Ai*` 表族只留 schema 预留位；CLIP/全文检索腿不在本 phase。
- **UI 壳**（M2-3）——双工作区路由、图库网格、Inspector 面板、全局搜索三合一对话框、七页签调整栈，全部归 M2-3；本 phase 只留数据接口。
- **删除 Session/Catalog 代码**——剥离 = 默认面收窄 + 回切口，代码与测试保留全绿。
- **导出**（M2-9）、**节点模型**（M2-4）、**DRT**（M2-6）。
- **Darktable sidecar 互通**——项目文件与 `.lra` 均维持 ONE-WAY 格式锁，无互通。

## Existing Code Insights

### Reusable Assets（M1 资产盘点，2026-09-27 Grep 实测）

| M1 资产 | 位置 | M2-2 复用判定 |
|---|---|---|
| `SQLiteHandle`（系统 libsqlite3 自包装，零 SPM 依赖；typed 三分错误面；prepare/bind/step/事务） | `LightamerCore/Sources/Session/SQLiteHandle.swift` | **直接复用**——新项目库连接层；探针实测系统 lib = SQLite 3.54.0，FTS5 内建（NOTES 探针 P1），零新依赖成立 |
| `SessionIndexSchema` v2 EXIF light columns（`camera_make/camera_model/lens_model/iso/focal_length/aperture/exposure` + `capture_date` + `rating/color_label/keywords`；L013 DECIMAL TEXT 哈希纪律） | `LightamerCore/Sources/Session/SessionIndexSchema.swift:66-101` | **语义参照集**——M2LIB-04 物化列以它为基线扩 `file_stem/file_ext/exif_search_text/exif_search_words`；列语义不重发明 |
| `FilterSQL`（FilterPredicateGroup→SQL WHERE 单一翻译面；bind-only / LIKE ESCAPE / ORDER BY 白名单 / keywords 四子句祖先谓词） | `LightamerCore/Sources/Session/FilterSQL.swift` | **直接复用**——智能相册 Filter 谓词走同一翻译面（唯一 SQL 面 red line 延续），新域模板按项目库表别名扩充 |
| `SmartAlbumDocument`（App 级智能相册 envelope：schemaVersion+name+group，损坏跳过自愈） | `LightamerCore/Sources/Session/SmartAlbumStore.swift` | **语义模型沿用**——智能相册规则从 App 侧 JSON 迁入项目库 `Filter` 表（data 列 = 同一 Codable JSON），格式零新增 |
| `CatalogIndexStore` keyset 分页（row-value seek + NULL tail 两段式）+ `CatalogBenchmarkHarness` 方法学 + **SC#3 基准先例**（96 形状 Release 热 p95 最差 12.28ms@1M 行，门 <50ms） | `LightamerCore/Sources/Catalog/CatalogIndexStore.swift`；`.work/gsd/phases/16-catalogs-mode/16-4-SUMMARY.md` | **方法学复用**——项目库网格查询与性能基准 harness 照此成型（OQ-9）；keyset-only 分页纪律延续 |
| `CatalogProjector` 两档投影（full/incremental，`catalog.lcat` 单写者） | `LightamerCore/Sources/Catalog/CatalogProjector.swift` | **模式参照**——导入时物化列填充/重建的两档结构同型（项目库重建器 = 可重建投影的推广） |
| `SessionThumbnailProvider` 双档管线（档 A 嵌入预览 **10.6ms/张 @86MP ARW 实测**；档 B 真管线渲；tier 由 `has_edits`+stale 唯一裁决）+ `ThumbnailDiskStore`（`<root>/.lightamer/thumbs/<pathhash>.jpg`，JPEG q85，原子写 L009） | `LightamerCore/Sources/Session/SessionThumbnailProvider.swift`；`ThumbnailDiskStore.swift` | **直接复用为图库缩略图源**（OQ-10）；落位需按项目包形态重定（真身不混派生缓存） |
| sidecar 真身原则（`.lra` 恒真身；`session.lindex`/`.lcat`/thumbs 全部可重建派生物；mutable and untrusted） | `09-CONTEXT.md` D-09 系；AGENTS.md Phase 2 增量 | **延续为本 phase 边界基石**（OQ-3）——项目库 v1 同样是组织+检索投影，不承载编辑历史 |
| 剥离机制两先例：M2-1 env 口 `LIGHTAMER_FULL_IOP_FACE=1`（默认面收窄 + env opt-in，M2DIS-02）+ `CatalogPreferences.catalogsEnabled` 运行时 Settings 开关（UserDefaults 持久化） | `App/Sources/Lightamer/Catalog/CatalogPreferences.swift`；M2-1 MATRIX/ACCEPTANCE | **组合复用**——M2LIB-06 剥离机制 = 运行时开关 + env 回切口（OQ-8） |
| `SessionIndexStore` WAL+NORMAL PRAGMA 纪律 + schemaVersion dispatch（absent→fresh / N→N+1 迁移 / >N REFUSE） | `LightamerCore/Sources/Session/SessionIndexSchema.swift` 头注 | **纪律沿用**——项目库 schema 版本化同型；但项目库是不可重建真身容器，迁移面更重（OQ-2/OQ-3） |

### Integration Points

- 项目库 Core 落位：新目录 `LightamerCore/Sources/Library/`（沿 `Pipe/Sidecar/Metal/Decode/Foundation/Layers` 目录惯例，Core 级可单测——sidecar 读写器放 Core 的既定原则推广）。
- 导入链消费 `Decode` 侧 CIRAW 入口与 ImageIO EXIF 读取（`backfillExifMetadata` 同路径）；缩略图消费 `SessionThumbnailProvider` 双档（App 层注入 render leg，injection 契约不变）。
- M2-3 数据接口：集合查询（keyset 分页）、四分组聚合、Activity 日计数序列、过滤态描述——面先于壳定型。

## Open Questions（待用户裁决；每条含推荐）

### OQ-1 项目文件的位置、创建流程与多项目形态
Alcedo = `WelcomeDialog`（Load/Create Project，`.alcd` 自由落位）+ Recent。我们：
- **A（推荐）**：`.lalb` 由 NSOpenPanel/NSSavePanel 自选位置；Recent Projects 列表（UserDefaults）；启动无 recent 时展示新建/打开入口（对齐 Alcedo Welcome 语义）。v1 = 单窗口单项目，切换 = 关当前开另一。
- B：固定默认目录 `~/Pictures/Lightamer Projects/`，新建落此、可另存。
- **理由**：M2LIB-01 的核心价值是「可整体移动/备份」——锁死目录自废该语义；A 与 Alcedo 一致（Feature-map §1.2「项目」行），B 只作 A 的保存面板默认值可兼得。

### OQ-2 单文件包形态与 journal 纪律（D3 措辞细化，必裁）
D3 写「SQLite 单项目文件 = db + manifest」、M2LIB-01 写「`<stem>` 库 + manifest；……在一个文件内」——manifest 是**伴生 JSON 文件**（Alcedo `<stem>.db`+`<stem>.json` 形态）还是**文件内 manifest 表**？探针 P3 实测：WAL 模式打开即产生 `-wal`/`-shm` 伴生，clean close 后 3.54.0 仍留 0 字节 `-wal` + 32KB `-shm`——**严格零伴生在任何 SQLite 形态下都不存在**，伴生文件不可避免，问题只是有几个。
- **A（推荐）**：`.lalb` = **单个 SQLite 文件**；manifest（项目名/创建时间/schema version/视图状态）入文件内 `project_meta` 表（+ `PRAGMA user_version` 双写，读走 user_version）；journal = WAL + synchronous=NORMAL + 写批后节流 `wal_checkpoint(TRUNCATE)` + 关闭强制 checkpoint；「备份/移动项目」功能走 `sqlite3_backup` API 在线拷一致性单文件（探针 P3 实证可行）。伴生只剩 checkpoint 纪律下的 0 字节 `-wal`。
- B：照抄 Alcedo 双文件——`<stem>.lalb`（SQLite）+ `<stem>.json`（manifest）。
- **理由**：单文件语义最干净（拷走 = 完整项目，M2LIB-01 字面）；Alcedo 的双文件是 DuckDB 单写者架构的产物，SQLite 无此需要；manifest-in-file 消除双文件一致性负担。「语义照抄 Alcedo」（D3）指自描述可移动，不必照抄其文件数量。

### OQ-3 与 M1 Sessions 的真身边界（必须写清）
- **A（推荐）**：**延续 sidecar 真身原则**——`.lra` 恒编辑状态权威；项目库 v1 = 相册组织 + 检索投影 + 引用（`Image.image_path` 引用式，Alcedo 同语义）。`EditCommit`/`VersionRef`/`ImageEditState`/`PipelineRoot` 本 phase **只留 schema 预留位**（推荐注释占位而非建空表，plan 细化），M2-8 激活；`PipelineParam` 活动参数表亦不建账。编辑态判定沿用 `has_edits/params_hash` 投影（session.lindex 同型）。
- B：本 phase 即把编辑态迁入项目库——提前吞 M2-8 一半，且节点模型（M2-4）未定，**不推荐**。
- **理由**：M2-8 依赖 M2-4（节点模型定型后历史才有稳定 schema 可记）；真身边界是 M1 两大 phase 反复实证的架构红线，V1 重定义未推翻它。随迁语义按 M2LIB-07⑤：移动/复制 = sidecar 随行，软链接 = sidecar 留原位。

### OQ-4 导入三方式的对话框默认值与「记住我的选择」（M2LIB-07④）
- **A（推荐）**：默认 = **复制**；「记住我的选择」勾选后存 UserDefaults（`CatalogPreferences` 同模式），设置页可改可重置；对话框单次仍可改。
- B：默认 = 软链接（对齐 Alcedo 引用式省空间）。
- C：默认 = 移动。
- **理由**：Alcedo 引用式导入有实锤痛点（删源文件无法 relink、调整丢失——其 KNOWN_ISSUES v0.2.3；我们的软链接模式已内置 stale 检测修复，但对新手复制仍是最不可破坏的选择）；RAW 素材体积大，进阶用户可勾「记住=软链接」一次到位。三方式实现约束（M2LIB-07①②③：同卷 rename 优先跨卷回退、逐文件校验、stale 检测）已由需求钉死，不在本 OQ 重开。

### OQ-5 软链接相对/绝对策略（M2LIB-07③，L009 卷型教训）
- **A（推荐）**：默认**相对链接**（项目文件与源同盘时免疫挂载点改名——本机 `/Volumes/UNITEK` USB 盘挂载点可变即 L009 场景）；跨卷无法相对时自动降级**绝对链接 + 记录卷 volume UUID**；打开项目时校验（stale = 路径不存在或 UUID 不符），Inspector 侧提供批量 relink 入口（重选文件夹重建链接）。
- B：全绝对路径（Alcedo `image_path` 做法）——搬卷即断，零归因信息。
- C：全相对——跨卷直接拒绝，功能面残缺。
- **理由**：A 用 volume UUID 把「断了」升级成「知道为什么断、可修」；实现面只多一列元数据，检测/修复语义明确。

### OQ-6 相册骨架照搬程度 + 智能相册 Filter 谓词格式（M2LIB-02）
Alcedo 表族：`Sleeve(id)/SleeveRoot/Element(id,type,element_name,added_time,modified_time,ref_count)/FolderContent(folder_id,element_id)/ComboFolder/Filter(combo_id,type,data JSON)`。
- **A（推荐）**：**语义对齐 + 表形简化**——保留三类相册（普通相册=Sleeve/文件夹=Folder/智能相册=Filter）与 **Element 引用计数模型**（一图可入多相册、引用式不拷贝，M2LIB-02 字面）；`SleeveRoot/ComboFolder` 合并为 Element `type` 判别字段，减少表数不减少语义。
- B：逐表逐列照抄 Alcedo DDL（含 SleeveRoot/ComboFolder 独立表）。
- C：简化为 folder 树 + smart filter 两类、放弃引用计数（相册即目录）。
- **Filter 谓词格式（推荐已定，随裁）**：`Filter.data` = **`FilterPredicateGroup` Codable JSON**（既有模型，`FilterSQL` 单一翻译面已消费它，`SmartAlbumDocument` 同构）——智能相册规则与 M1 过滤条/Smart Albums 零格式迁移；不复刻 Alcedo 自有 JSON 谓词语法。
- **理由**：D3 已签核「语义照抄」——照抄的是语义（引用计数、三类相册、JSON 谓词），表形本地化是既定工程惯例（Sidecar/索引均本土 schema）；C 破坏「一图多相册」语义，属裁剪而非对齐。

### OQ-7 EXIF 词法检索实现（M2LIB-04，探针已做）
探针 P2（20k 行合成 EXIF 语料，同折叠物化文本上对比）：folded-LIKE 全表扫 **p95 3.9ms**；FTS5 MATCH **p95 0.23ms**（约 17×）；导入 20k + FTS rebuild 共 125ms；LIKE 线性外推 10 万张 ≈ 20ms 临界，FTS5 大库仍有 headroom。
- **A（推荐）**：**双层**——结构化物化列（`file_stem/capture_at/camera_*/lens/iso/focal/aperture/rating`，范围/排序/聚合走 `FilterSQL` 域）+ `exif_search_text/words` 折叠文本列上建 **FTS5 external-content 表**（自由词 AND 组合走 MATCH）；两类谓词 AND 混查。
- B：仅物化列 LIKE（无 FTS5）——2 万张达标（3.9ms）但 10 万张触顶。
- **理由**：M2LIB-04 对标 ~20ms@2 万张是「对标」非上限，双层以 ~125ms 一次性导入成本买 17× headroom 与 FTS 原生 AND 语法；**折叠物化（iso800/iso 800/f2.8/f 2 8/35mm/35 mm 变体词表）是正确性承重面**——无论选哪层都必须做，进 plan 固化为词表+测试。tokenizer 用默认 unicode61（不注册 tokenchars 定制：`/`/`.` 收进 token 会把 `f/2.8` 变单词致 `f2.8` 查不到，风险记录在 NOTES P2）。

### OQ-8 Sessions/Catalogs 剥离机制（M2LIB-06）
先例两条：M2-1 env 口（`LIGHTAMER_FULL_IOP_FACE=1`，默认面收窄+env 回切，M2DIS-02 同型）；`CatalogPreferences.catalogsEnabled` 运行时开关（Settings 页可控）。
- **A（推荐）**：运行时布尔门（`legacyLibraryEnabled = false` 默认）盖住 Sidebar Sessions/Catalogs 双区 + browser 入口 + 模式切换器；**env 口 `LIGHTAMER_LEGACY_LIBRARY=1`** 作 QA/回归回切通道；**Settings 页不放开关**（避免用户误开双库并行产生数据分叉心智负担）。
- B：仅移除 UI 入口（硬编码注释掉）——「可回切」无通道，回归测试难写。
- C：编译期 flag 双 target——面积大，无必要。
- **理由**：M2LIB-06 字面「代码保留可回切」；A 与 M2DIS-02/05 的 env 口纪律同构（默认面收窄、显式 opt-in、验收通道唯一），且保留 Session/Catalog 测试全绿不迁不删。

### OQ-9 性能基准硬门（对标 SC#3 先例）
SC#3 先例：16-4 设 96 形状 Release 热 p95 < 50ms 硬门（1M 行，CatalogBenchmarkHarness，三轮 Debug+Release 对账）——实测最差 12.28ms，门 >4× 余量收官。
- **A（推荐）**：设硬门——**EXIF 词法组合检索 p95 < 20ms @ 2 万张**（Release，fixture = 合成 EXIF 语料 + 真实 RAW 抽样交叉）；形状矩阵 ≥ 12 检索形状 × 3 排序 × 2 深度（词法 AND / 结构化范围 / 混查）；另设**观察项（非门）**：10 万张外推、首屏缩略图时间、导入吞吐（≥ 100 张/min 软指标）。
- B：不设本 phase 门，留 M2-11 统一 perf。
- **理由**：M2LIB-04「性能对标 ~20ms@2 万张」不落门就退化为愿望；SC#3 证明该做法便宜且终裁有效（「v1 SQLite 终裁成立」正来自实测门）；B 把风险推到收官 phase 才暴露，返工面大。

### OQ-10 图库网格缩略图数据源与落位
- **A（推荐）**：**复用双档管线**（档 A 嵌入预览 10.6ms/张 @86MP 实测；档 B 真管线；tier 由 `has_edits`+stale 裁决的红线不变），缓存落**项目伴生隐藏目录 `<项目目录>/.<stem>.lathumbs/`**（`.lightamer/thumbs` 同型：FNV pathhash 文件名、JPEG q85、原子写）。
- A2 变体：缓存落 `~/Library/Caches/Lightamer/Projects/<uuid>/thumbs/`（包目录绝对纯净，但删项目留孤儿缓存）。
- B：缩略图 blob 列入项目包——10k×40KB ≈ 400MB 包膨胀，真身混派生缓存，违背可重建投影原则。
- **理由**：项目包是真身容器（相册+未来历史），缩略图是可重建派生物——M1「真身不混派生」分离原则原样适用；A1 让缓存随项目移动、删项目即净（与 `.lightamer` 同型），探针层面与 A2 只差落位一行常量，plan 可低成本对调。

### OQ-11 Album Inspector 与导入对话框的 M2-2/M2-3 切分线
M2-2 行含「Album Inspector」，M2-3 行也含「图库 = 网格 + Album Inspector」——两 phase 措辞重叠，切分线需签核。
- **A（推荐）**：M2-2 = **数据与查询面**（四分组聚合 SQL、Activity 按日计数序列、Overview 计数、过滤态集合投影 API + Core 单测）+ **导入询问对话框/进度反馈的最小功能 UI**（导入流程闭环所需，M2LIB-07 弹询属 M2-2 规划裁决字面）；M2-3 = Inspector 面板/网格/搜索对话框的完整壳与视觉验收。
- B：M2-2 连 Inspector 面板 UI 一起做（M2-3 只调视觉）——壳未立先做面板，返工风险高。
- **理由**：M2-3 是 UI 壳 charter phase（含 computer-use 对照验收）；数据面先行才能让 M2-3 的壳只做渲染；导入对话框是 M2LIB-03/07 的功能闭环要件，留在 M2-2 才能验收「导入数 = RAW 数」加固 AC。

### OQ-12 RAW 扩展名白名单默认面与可配宿主（M2LIB-03）
- **A（推荐）**：默认白名单 = **Alcedo 0.3.0 十种**（`.3fr/.arw/.cr2/.cr3/.dng/.fff/.nef/.raf/.raw/.rw2`）∪ **Apple 原生支持补充**（`.pef/.orf/.rwl/.iiq`，Phase 1 已验证 CIRAW 面）；可配置项宿主 = **全局 Settings**（跨项目一致，`UserDefaults`），高级用户可增删；附属排除表（`.xmp/.lra/.lightamer-preset/.pp3/.opc` + 点开隐藏文件）**硬编码不可配**（M2LIB-03 加固 AC①②字面）。
- B：默认面 = Alcedo 十种整、无补充（对齐最紧）。
- 可配宿主放项目包内（每项目一套）——跨项目不一致，**不推荐**。
- **理由**：M2LIB-03「可配」已签核；白名单扩充零成本（同一 ImageIO 解码面）而截断用户素材面成本高；排除表不可配是上游缺陷反向教训的硬化要求，配了就会有人把 `.xmp` 配回来。

## Canonical References

- `research/ALCEDO-FEATURE-MAP.md` §1.2（图库 UI）/ §6（项目文件 + 全 DDL）/ §8（AI 表——M2-10 预留）
- `.work/gsd/ROADMAP.md` M2 表 M2-2 行 + D3 决定点
- `.work/gsd/REQUIREMENTS.md` M2LIB-01..07
- `M2-2-RESEARCH-NOTES.md`（探针 P1/P2/P3 实测）
- M1 资产：`SQLiteHandle` / `FilterSQL` / `SmartAlbumStore` / `SessionIndexSchema` / `CatalogIndexStore` / `SessionThumbnailProvider`（file:line 见上表）

## Specific Ideas（起草倾向，plan 细化）

- Core 新目录 `LightamerCore/Sources/Library/`：`ProjectDocument`（包开关/迁移）+ `LibrarySchema`（DDL 冻结面）+ `LibraryStore`（actor 单写者）+ `ImportService`（三方式 + 过滤白名单 + 进度）+ `ExifSearchIndexer`（物化列 + 折叠词表 + FTS rebuild）+ `InspectorQueries`（分组/Activity/Overview）。
- `LibrarySchema` 版本化照 `SessionIndexSchema` 三分语义（absent→fresh / 迁移 / REFUSE），但项目库不可整体重建——迁移表驱动 + 迁移前自动 backup API 快照。
- L013 纪律延续：一切入包 UInt64 哈希 = DECIMAL TEXT。
- 测试 fixture：真实 C1 Session 目录（含 `.ARW`+`.ARW.xmp` 对，M2LIB-03 AC③指定 `/Volumes/UNITEK/.../Capture/RAW`）。

## Deferred Ideas

- 双项目同时开（分屏对比）——V2。
- 项目文件只读锁/多进程协作（第二实例打开同一 `.lalb` 的提示面）——V1 最小提示即可，plan 决定。
- CLIP/全文检索腿、AI 表激活（M2-10）；mini-git 历史面板（M2-8）。
- 导出（M2-9）。

---

## Ruling（2026-09-27 用户：「采纳全部推荐」）

D-M2-2-CONTEXT-1..12 = OQ-1..12 **全部按起草推荐生效**（本节上方各条即裁决文本）。要点回执：OQ-2 纯单 SQLite 文件 + `project_meta` + WAL/checkpoint 纪律；OQ-3 `.lra` 恒真身、库=投影；OQ-4 导入默认复制 + 记住选择；OQ-7 双层检索（物化列 + FTS5 unicode61 不定制）；OQ-8 运行时布尔门 + `LIGHTAMER_LEGACY_LIBRARY=1`；OQ-9 硬门 p95 < 20ms @ 2 万张。探针结论 P1-P3 一并生效。

---

## Checker 回注记录（2026-09-27）

Checker 判 FAIL（5 error + 4 minor），修复全部回注到四个 plan 原文（只改 plan，不碰代码），单 commit 收口。

### Errors

- **E1（M2-2-1 T4）**：`.library` 穷举臂从 2 处补全为 5 处——`FilterSQL.swift` 4 处（`orderBySQL:112` / `baselineClause:195` / `columnRef:223` / `keywordsCondition:261`）+ `SmartAlbumStore.evaluate:292`（实态已 grep 验证）。T4 action 改五触点全表（禁 default 臂，穷举编译器强制）：`orderBySQL(.library)` tiebreaker 钉 `image_path ASC`（库内实存列、session `path`/catalog `rel_path` 同族）；`keywordsCondition(.library)` 打物化 `keywords` 列；`SmartAlbumStore.evaluate(.library)` = typed `missingStore` 占位（真实现 M2-2-3 补）；`.session`/`.catalog` 分支字节不变由既有测试钉。纪律 5 加显式例外（SmartAlbumStore 单臂 only）；files_modified 补 SmartAlbumStore.swift；KD-7 改五触点表；AC #9/#11 同步。
- **E2（M2-2-1 T1/KD-3）**：images 冻结列清单补全——`id INTEGER PRIMARY KEY` 置首（FTS content_rowid / album_content 外键 / keyset seek 三处消费面）+ `image_path`（path_kind 载体）+ `rating/color_label/keywords/filename/dir`（D-09-CONTEXT-7 预留 NULL 列模式，session 四子句形态服务项目库）；KD-3 改完整枚举，T1 imagesColumns 同步，并加落表后消费点交叉核对步。
- **E3（M2-2-1 KD-5）**：FTS5 external-content 列名 `search_words` → `exif_search_words`（与 images 列同名——异名会使 rebuild 报 no such column）；三触发器映射钉 `new.exif_search_words`；T1 测试断言加列名钉。
- **E4（M2-2-3 T2）**：删「`FilterSQL.orderBySQL` 增 `.library` 臂」sub-action 与「唯一既有文件触点」措辞（该臂已前移 M2-2-1 T4 落地）；T2 既有文件触点改记 `SmartAlbumStore.evaluate` `.library` 臂真实现（files_modified / 纪律 5 例外 / read_first 6 / 测试断言 / 验收标准同步）。
- **E5（M2-2-2 KD-5）**：`moveProject` 改整项目目录搬移（close DB → 目录级 rename；跨卷 copy+verify+删源复用 M2LIB-07① 纪律；`.lathumbs` 派生物可丢弃不搬）；backup API 只留 `backupProject` 一个消费者；T4 补 AC「move 后 kind0（项目相对路径）resolve 命中 + verify 失败源目录原样在」；front-matter 与 AC 表同步。

### Minors

1. M2-2-3 KD-3 排序白名单改库域合法子集五键（filename/rating/captureDate/iso/focalLength），显式排除 `scanEpoch`，守卫落 `LibraryQueries` 入口。
2. files_modified 裸 `LESSONS.md` → `.work/LESSONS.md` 真路径（checker 报三个 plan；四个 plan 同款病灶一并修，根目录实无 LESSONS.md 已核实）。
3. M2-2-4 KD-4 第 2 层明示快照载体 = 硬编码期望节 identifier 集合字面量（非运行时录制件）。
4. ImportDefaults 落 P2 维持不变（checker 判可接受，未动）。

### 复核结论

一致性自查通过：E1 五触点在 M2-2-1 T4 action 与 KD-7 表一一对应、行号与代码实态相符；E2 列清单 ↔ E3 FTS 列名（`exif_search_words`）↔ KD-2 album_content 外键 ↔ M2-2-3 keyset `(capture_date, id)` ↔ 四分组列（`camera_make||camera_model`、rating）↔ 库域排序子集全部互指实名列；E5 与 M2LIB-07① 字面（「校验通过前永不删源」）一致；SmartAlbumStore 缝两侧（M2-2-1 占位 → M2-2-3 真实现）登记闭合，两 plan 纪律例外互认；全目录无裸 `search_words` / 裸 `LESSONS.md` 残留。
