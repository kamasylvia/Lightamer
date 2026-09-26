# Phase 9 Research: Capture One Session Management

**Researched:** 2026-09-22
**Confidence 汇总：** 会话模型/索引 DB 架构 = High（既有 SidecarStore/SidecarStore 事务面、PipeCoordinator load/teardown seam、PipeCache 分档全部现码核过；dt history.c/paste job/mipmap/crawler file:line 逐段核过）；批量 apply 管线 = High（dt `_control_paste_history_job_run` 的「先库后 sidecar 批同步」结构与 PERF-07 注记逐点对上，Lightamer 侧落位全部在已验证 seam 上）；FSEvents 语义与缺陷清单 = High（ROADMAP Notes 警示 + L007 + Watchexec 结论一致，API 行为为公知事实）；缩略图双档色差与吞吐数字 = Med（嵌入预览 vs pipe 渲染的观感差、万张冷扫描 I/O 需 plan 期 fixture 实测）；Capture One Session 语义（三级目录/.cosessiondb 派生缓存）= Med（产品语义知识，无本地源码可核验——按 REQUIREMENTS SESS 节文字执行为准）。

---

## Summary

Phase 9 = 8 个需求（SESS-01..07 + HIST-05/06），从「单图编辑器」升级为「会话工作流」。核心结论：

1. **Session 模型（§1）：文件夹即会话是纯 App 层编排，Core 零改动。** 选定文件夹 → 幂等创建 Capture/Crop/Output 三级子目录 → 浏览集 = 索引驱动。既有 `SessionState` stub（`App/Sources/Lightamer/State/SessionState.swift:12-22`）的 `currentSessionURL/recentSessions/folderWatchStatus` 三字段即本 Phase 的落位锚；既有单图加载流（`EditorState.load` → `PipeCoordinator.load`）原样复用，会话切换 = 既有 D-C2 sweep + `invalidateAll()`（`PipeCoordinator.swift:538-539` 已预埋注释「Phase 9 hook: session SWITCH also calls cache.invalidateAll() + this sweep」）。L012 单窗口红线延续：会话切换与 recent list 打开都走同窗路由，不走 WindowGroup odoc。
2. **索引 DB（§2）：SQLite（系统 libsqlite3 C API + actor 包装，零新 SPM 依赖），落 `<session>/.lightamer/session.lindex` + `thumbs/`。** schema = 图片清单 + sidecar 摘要（imageID/historyHash/hasEdits/层栈摘要）+ 缩略图索引 + EXIF 轻量列 + Phase 12 预留列（rating/label）。**真身恒 sidecar**：DB 与 thumbs/ 可整目录删除 → 全量重扫无损重建；打开会话 = 目录扫描 ⊕ DB 增量同步（stat 三元组 path/mtime/size 比对，单事务落 diff）；FSEvents 只做失效标记（stale），不做删除裁决。
3. **批量 apply（§3）：三段式——内存元数据变换（零渲染）→ 索引单事务（N 行一 txn）→ sidecar 批量写队列（后台串行 + 同目录 tmp 原子晋升 + dirty 标记自愈）。** dt 对标正本 = `_control_paste_history_job_run`（`src/control/jobs/control_jobs.c:1607-1676`）：循环单图 paste（中央库单事务）→ `dt_image_synch_xmps(to_synch)` 批量 sidecar 同步**后置** → `dt_mipmap_cache_remove` 只失效不重渲（`history.c:997`）→ backthumbs crawler 空闲再生（`crawler.c:860-990`）。Lightamer 无中央库，sidecar-per-image 的批量写是主要 FS 开销（USB HDD = L009 风险卷）——写队列串行 + 可选聚批 + 计量落账，崩溃窗口以 sidecar 为真自愈。
4. **FSEvents（§4）：hint-only + 四时点 reconcile（开卷/获焦/事件批后/强制重扫），reconcile 本体 = 纯函数目录 diff（不依赖 FSEvents 即可测）。** dt 全树 grep 零 inotify/GFileMonitor——dt 根本不监视文件夹（`dt_film_import` 手动扫描 + collection SQL），FSEvents+reconcile 是 C1 语义要求下超越 dt 的增强。孤儿 sidecar（.lra 无原片）= 索引标记 + reconcile 动作（永不硬失败）；忽略集 `.lightamer/`、dotfile、`*.tmp-*`、`*.cosessiondb`（防自反馈环）。
5. **浏览模式（§5）：grid/单图/culling 三模式；缩略图双档管线**——未编辑图直读 RAW 内嵌 JPEG 预览（ImageIO，秒开）+ 已编辑图/再生走真 pipe THUMBNAIL 360px（`renderCurrentChain` 路径全复用，`PipeResolution.thumbnail` LAZY 语义既有）。**缩略图绕开 PipeCache**（独立磁盘缓存 + 小 LRU 内存预算），PipeCache 只装当前编辑图（防 10k 平面污染 3GB 预算）。culling = 2-4 图并排各自 PREVIEW 子管线，cap 4。
6. **复制粘贴/before-after（§6）：复制 = 冻结的「有效实例集 + 层栈快照 + skip 集」载荷；paste = overwrite/merge/partial 三式**（merge 语义与 `HistoryStack.effectiveChain` 的 (opName, multiPriority) latest-wins 同构，`HistoryStack.swift:245-264`）；skip 集对齐 dt（decode 域 + 未修改默认模块，`history.c:695-705`）。before/after 三形态（split/快照点/按住看原图）= 「pristine 平面常驻 + 双平面 blit」与「历史点 peek 渲染」（`effectiveInstances(layerScope:)` 纯投影），coordinator 需加 render-with-instances 变体。
7. **性能（§7）：PERF-07 门 = 元数据+索引段万张 ≤5s（单事务 + 内存变换；sidecar 队列 drain 与缩略图再生计量落账不设门）；PERF-06 基线计量在本 Phase 建立（60fps 门在 Phase 15 清算）。** 万张冷扫描在 USB HDD 上是真实风险（L009）——渐进式 ingest + 增量同步缓存 mtime 是对策。
8. **验证（§8）：fixture 树 golden（扫描分类/孤儿/reconcile diff 纯函数）+ FSEvents 真流合成测试 + 10k sidecar 树计量门 + DB 删除重建 parity + 跨会话切换泄漏断言 + before/after 逐字节。** 测试命令纪律 = `Scripts/test-direct.sh`（L019b）。
9. **UI（§9）：侧栏会话区（current + recent + watch 状态）+ 浏览三模式切换 + grid cell（缩略图/rating overlay/已编辑徽章）+ culling 并排 + 复制粘贴菜单与部分复制对话框。** L010 identifier（稳定 id 非索引）、L025 zh 标签、容器禁 accessibilityLabel 三红线全适用。
10. **plan 拆分 5 个（§10）**：9-1 会话模型+索引 DB 基建 → 9-2 FSEvents+reconcile → 9-3 浏览模式 → 9-4 批量 apply+before/after → 9-5 签核。总量 ~25-33 T。7 个 Open Questions 见文末（SQLite 选型、`.lightamer` 落位、Crop 目录语义、sidecar 落盘一致性窗口、复制 skip 集、culling 规模、评分列预留）需 planner/用户拍板。

---

## Implementation Approaches

### 1. Session 模型（SESS-01/02/03/04 的模型面）

**1.1 文件夹即会话（SESS-01）**

- 会话 = 一个文件夹 URL；「打开会话」= 用户经 NSOpenPanel 选目录（`FileOpenHelper` 既有 open-image 模式旁增 open-folder）→ `SessionState.currentSessionURL` 赋值。无中央库、无注册表：会话的全部持久状态都在文件夹里（原片 + `.lra` sidecar + `.lightamer/` 派生缓存），App 偏好里只记 recent list（§1.5）。
- **不可变信任原则（ROADMAP Phase 9 Notes 原文）**：会话文件夹是 mutable and untrusted——一切派生状态（索引/缩略图/内存集合）在访问时重推导，永远不把索引当权威。这条原则同时管 FSEvents（§4）与索引 DB（§2）。
- 浏览集（collection）范围：推荐 = 会话根**递归**扫描，排除保留目录 `Capture/Crop/Output/Trash/`（若在根下）与 `.lightamer/`、一切 dotfile 目录。理由：摄影师会按日/按场景建子文件夹；排除保留目录避免「导出图回流成新候选」的怪圈。备选（C1 严格口径）= 只浏览 Capture/。**两口径差异进 OQ3 一起拍板**；实现上扫描器只改一个排除表。

**1.2 三级子目录（SESS-02，C1 惯例）**

- 打开会话时幂等创建 `Capture/`、`Crop/`、`Output/`（`FileManager.createDirectory(withIntermediateDirectories: true)`，已存在零副作用）。REQUIREMENTS SESS-02 只写三级；C1 还有 `Trash/`/`Selects/`（trash 已在 C1 惯例内）——**建不建进 OQ3**（建了要对齐语义，不建保持 REQUIREMENTS 字面）。
- 各目录职责与消费点：
  - **Capture/**：原片 + `.lra` sidecar 同目录（SESS-03 已是既成事实——`LightamerSidecar.sidecarURL(for:)`（`LightamerCore/Sources/Sidecar/LightamerSidecar.swift:150-161`）就是全名 + `.lra` 共址，02-06 起不变）；拖放导入（SYS-04，Phase 13）的落点。
  - **Crop/**：C1 语义 = 调整副本/工作拷贝。Lightamer v1 推荐仅创建+维护（空目录）——裁剪变体工作副本是大功能且需求未列；**OQ3 记录**。
  - **Output/**：Phase 11 导出落点（ROADMAP Phase 11 Notes「files land in Session/Output/」+ EXP-08）。Phase 9 只负责目录存在性 + Phase 11 消费点常量（`SessionLayout.outputDirectory(for:)` 类 API），不实现导出。
- Phase 8 移交清单四项与本 Phase 的交叠：①EXP-05 导出消费点接口面、②`YiyinExportSettings.targetSize` 应用缝、③`YiyinLayout` 复用面三项全部是 **Phase 11（Export Pipeline）的接口义务**——Phase 9 唯一须守住的是(a) `Output/` 目录约定（上条）与(b) `LayerCompositeDriver.terminalTailFloor = 70.0` 尾窗契约不被浏览管线改动（`LightamerCore/Sources/Pipe/LayerCompositeDriver.swift:108-121`——THUMBNAIL 渲染走同一 driver，禁改 split 规则）；④遗留对表中与 Phase 9 有实际耦合的仅一条：**yiyin borders/watermark 实例随 sidecar 走**——索引的 `hasEdits`/paramsHash 自动涵盖它们（属 terminal tail 但仍是 `instances` 成员），用户编辑印框后缩略图正确判 stale，无需 Phase 9 特判。

**1.3 与既有单图加载流的接线（Core 零改动的论证）**

- 浏览器选中一张图 = 调既有 `EditorState.load(url:)`（`App/Sources/Lightamer/State/EditorState.swift:247-322`）→ `PipeCoordinator.load`（`App/Sources/Lightamer/State/PipeCoordinator.swift:465-571`）：flush 出图 sidecar（:488）→ 恢复/种子 sidecar（:493-511）→ D-C2 sweep（:540-548）→ PREVIEW 渲染。**会话内换图 = 现有行为**，Phase 9 只加「换图前 flush 由会话层统一编排」。
- `imageIDMap`（:522-528）是进程内 URL→UUID 映射；sidecar 存在时真身是 sidecar 里的 `imageID`（`LightamerSidecar.swift:114`），索引 DB 把它物化为列（§2），会话重开后的 imageID 稳定性由 sidecar 保证（索引仅缓存）。

**1.4 多会话切换的 teardown（SESS-04 的状态隔离面）**

- 切换 = ①当前图 `flushSidecar()`（`PipeCoordinator.flushNow` 语义）→ ②缩略图管线取消（§5 的 provider 任务全部 cancel）→ ③`cache.invalidateAll()` + `metal.clearCICaches()` + D-C2 sweep（既有 hook 注释明示此组合，`PipeCoordinator.swift:538-548`）→ ④索引 DB 关闭（SessionIndexStore deinit/`close()`）→ ⑤`SessionState.currentSessionURL` 更新 + 浏览集合重建。泄漏断言 = ①-④ 每步后 cache.totalBytes==0、thumb LRU empty、无在飞 Task（§8 E2E）。
- 编辑器选中态跨会话清除：`currentImageID/historyLoadedURL/currentLayerStack` 全部随 load 语义重置（既有），UI 侧 Inspector/Browser 选择态归零（新代码）。

**1.5 recent list（SESS-04）**

- 持久化 = `UserDefaults`（suite 默认）存 `[URL]`，上限 ~10，去重前移；显示名 = lastPathComponent。打开 recent 项走 §1.4 同一路径。L012：**不是** WindowGroup odoc——新窗口模型 defer（`LightamerApp.swift:163-173` 注释是正本理由）。

### 2. 会话级索引 DB（SESS-07 核心）

**2.1 选型：系统 libsqlite3 C API + actor 包装（推荐），GRDB.swift 否决理由在案**

- 项目依赖红线（AGENTS.md Conventions）：预期仅 libwebp/libavif 两个 SPM 依赖。GRDB 是第三个 SPM 依赖且只服务于本 Phase 的单写者场景——自包装 `SessionIndexStore` actor（.prepare/step/finalize 薄封装 + `SQLite3` 系统库 link，非沙盒可直接用）约 200-300 行，换来零依赖。**OQ1 保留 GRDB 选项**（若 planner 认为手写 SQL 的维护成本高于依赖红线让步）。
- 配置：WAL journal mode（读写并发：UI 查询与写事务不互斥）+ `foreign_keys` 不需要（单表为主）+ `synchronous=NORMAL`（WAL 下崩溃安全与速度平衡；**不**用 OFF——索引虽可重建，但 dirty 标记丢失会让 §3 的崩溃自愈退化成全量重扫）。

**2.2 落位与派生物身份（OQ2）**

- 推荐 `<sessionRoot>/.lightamer/`：`session.lindex`（SQLite）+ `thumbs/<pathhash>.jpg`。理由：随会话文件夹移动/拷贝整体迁移；「删除即重建」= 删一个目录；C1 `.cosessiondb` 同构（其 DB 也在会话内）。代价：用户会话文件夹多一个隐藏目录；**FSEvents 与扫描器必须忽略它**（§4 自反馈环）。备选 Application Support（不污染用户文件夹，但会话移动后缓存失联重建）。
- `.cosessiondb` 对照与差异（SESS-07「C1 同构」的准确含义）：C1 的 .cosessiondb **本身是调整真身**（除非用户开 XMP 同步）；Lightamer 同构的是「会话级缓存索引」角色，**真身恒 sidecar**（REQUIREMENTS SESS-07 黑体）——DB 任何行都可从「文件系统 + sidecar」重推导，删除 `session.lindex` 无损。用户既有的 C1 会话被打开时其 `.cosessiondb` 只读不碰（忽略集，§4.4）。

**2.3 Schema（v1 草案，拼写未冻结——plan 期冻结）**

```sql
CREATE TABLE images (
  path TEXT PRIMARY KEY,        -- 相对会话根（会话移动免疫）
  dir TEXT, filename TEXT,      -- 冗余便于排序/过滤
  file_size INTEGER, file_mtime REAL, scan_epoch INTEGER,
  imageID TEXT,                 -- sidecar imageID（pristine 无 sidecar 时 NULL）
  sidecar_present INTEGER, sidecar_mtime REAL,
  has_edits INTEGER,            -- history.position >= 0（含层栈/印框实例判定）
  params_hash TEXT,             -- sidecar historyHash（decimal String，UInt64String 惯例）
  layer_count INTEGER, layer_summary TEXT,  -- 层栈摘要（名/混合/可见性 JSON）
  orientation INTEGER, width INTEGER, height INTEGER,  -- ImageIO properties 轻量读
  capture_date REAL,
  thumb_state INTEGER,          -- 0 none / 1 embedded / 2 rendered / 3 stale
  thumb_path TEXT, thumb_params_hash TEXT,
  rating INTEGER, color_label INTEGER, keywords TEXT,  -- Phase 12 预留（v1 恒 NULL）
  dirty INTEGER DEFAULT 0       -- §3 批量 apply 的 sidecar 未落盘标记
);
CREATE TABLE meta (key TEXT PRIMARY KEY, value TEXT);  -- schemaVersion / scan_epoch / 最近全扫时间
CREATE INDEX idx_images_dir ON images(dir);  -- + has_edits/cape_date 按需
```

- UInt64 哈希列一律 TEXT decimal String（`UInt64String` 既有惯例正本 `LightamerSidecar.swift:36-64`——ONE-WAY 格式锁，Phase 6 层记录/Phase 11 manifest 沿用，本 Phase 同律）。
- 评分/标签列现在建、Phase 12 回填（OQ7）：过滤排序（META-05）是 Phase 12 交付，但索引 schema 若不留列则 Phase 12 要迁移——空列迁移成本为零。

**2.4 打开会话 = 扫描 + 增量同步（单事务）**

```
openSession(root):
  1. ensure Capture/Crop/Output (§1.2)
  2. scan = walkTree(root, exclude=[.lightamer, 保留目录, dotfile]) → [(relPath, mtime, size)]
  3. txn BEGIN:
       rows = SELECT path, mtime, size FROM images
       added    = scan − rows            → INSERT 轻量行（thumb none, EXIF 延迟）
       removed  = rows − scan            → DELETE（含 thumbs 文件清理）
       changed  = mtime/size 漂移的行    → UPDATE 置轻量列重算 + thumb stale + sidecar 重读
       meta.scan_epoch++
     txn COMMIT
  4. 后台：新行补 EXIF 轻量列（ImageIO properties，非全解码）+ 双档缩略图（§5）
```

- 10k 文件的 stat 扫描 = 一次 readdir + 逐文件 stat：SSD 暖缓存 ~ms 级/千；**USB HDD 冷盘是 L009 风险卷**（实测 ~250ms/文件冷读曾见）——对策：①UI 渐进式 ingest（扫描流式吐行、网格边扫边出，不阻塞开卷）；②mtime 缓存跨会话复用（增量同步天然只 stat 一次）；③计量门建 fixture 基线（§7/§8）。
- 增删改全部走**单事务**（与 §3 的批量写同纪律：索引永远是「一次批量变更 = 一个 txn」）。

**2.5 FSEvents 失效标记与 reconcile 写回**

- 事件只做两件事：①对应行 `thumb_state`/轻量列置 stale（不删行——rename 的旧路径事件不可信，§4.2）；②触发 debounce 后的 reconcile diff（§4.3）作为唯一裁决者。行级状态永远是「索引的建议 + 目录扫描的裁决」。

### 3. 批量 apply 懒渲染管线（PERF-07；HIST-05 的执行底座）

**3.1 dt 对标正本（file:line 全核）**

- 批量 paste job：`_control_paste_history_job_run`（`src/control/jobs/control_jobs.c:1607-1676`）——`dt_undo_start_group/end_group` 包全程（:1636/:1657）→ 循环选中图逐张 `dt_history_paste(imgid, merge, FALSE)`（:1640；darkroom 正编辑图跳过 `_safe_history_job_on_imgid` :1600-1607）→ **sidecar 同步后置**：`to_synch` 收集 + 循环外 `dt_image_synch_xmps(to_synch)`（:1671-1675）→ 收尾 `dt_start_backthumbs_crawler()`（:1676）空闲再生缩略图。
- 单图 paste 本体：overwrite = 纯 SQL `DELETE FROM main.history WHERE imgid=?` + `INSERT SELECT`（`src/common/history.c:754-846`）；merge = 模块并入 + `dt_dev_write_history_ext` 落库（:590-745，:742）。paste 后只失效不重渲：`dt_mipmap_cache_remove(dest_imgid)`（:997）；aspect ratio 仅排序需要时才算（:1000-1010「recompute only if really needed」）。历史写的事务纪律：单图历史变更包 `dt_database_start_transaction/release_transaction`（:1226/:1341、:1367/:1399）。
- **结构抽象**（与存储无关，Lightamer 直接照抄）：**元数据先行（中央库/内存/索引一个原子操作域）→ 像素渲染零参与 → 缩略图失效标记 → sidecar 持久化后置批量 → 后台空闲再生**。PERF-07 的「dt sqlite 事务对标」实质 = 这个结构，不是字面 sqlite。

**3.2 Lightamer 三段式**

```
apply(targets: [URL], payload: PastePayload):
  段1 内存（零 I/O 零渲染）:
    for url in targets: newStack = composeHistory(url, payload)   // §6 merge/overwrite 语义
                        inMemoryHistory[url] = newStack            // 若该图正被编辑则走 live 路径
  段2 索引单事务:
    BEGIN; UPDATE images SET params_hash/has_edits/layer_*/thumb_state=3(stale)/dirty=1 WHERE path IN targets; COMMIT
  段3 sidecar 批量写队列（后台 actor，串行 + 有界）:
    for url in queue: SidecarStore 式原子写（同目录 .tmp-<uuid> → replaceItemAt，L009 纪律）
                      写成 → 索引 UPDATE dirty=0（独立小事务）
    退出/切图 → flush 余量；崩溃 → dirty 行下次打开以 sidecar 重读自愈（§3.4）
```

- 段1-2 是 **PERF-07 的 ≤5s 门主体**：10k 行单事务 + 内存变换 ≈ dt 中央库单事务量级（sqlite 10k UPDATE 单事务典型 <1s）。段3 计量落账不设门（USB 卷上 10k 原子写 = 现实中分钟级，属预期——dt 把 XMP 同步放循环外同为后置语义）。
- **段3 与「真身恒 sidecar」的一致性窗口（OQ4）**：DB 已 claim 新状态而 sidecar 尚未落盘的窗口内，磁盘真相仍是旧 sidecar。契约钉死：**rebuild/重读永远以 sidecar 为真**（索引行仅缓存提示）；`dirty=1` 行的 `params_hash` 列标注为「待生效」UI 可显示进行中徽章；崩溃恢复 = dirty 行按 sidecar 重读覆盖索引（自愈，无损）。

**3.3 sidecar 批量写的 FS 开销与写策略（USB 卷风险显式化）**

- 每 target 一次：JSON encode（pretty+sortedKeys，D-S1 可读格式）→ 同目录 tmp write → `replaceItemAt`/`moveItem`（`SidecarStore.writeAtomic`，`LightamerCore/Sources/Sidecar/SidecarStore.swift:138-166`）。10k 次 = 10k tmp 创建 + rename + 隐式 fsync——APFS 内置盘毫无压力；**USB 机械盘（本项目开发卷，L009）是主要风险**：随机小文件元数据操作延迟主导。
- 写策略：①**串行队列**（并发提升对机械盘负收益——磁头寻道竞争）；②可选**聚批延迟**（如每 64 个或 500ms 一组，组内连续提交减少 fsync 摊销——plan 期实测决定）；③进度上报（段3 是 UI 可见的后台过程，dt 同款 progress message :1626-1628）；④**禁止**合并多图进一个文件（sidecar-per-image 是格式锁）。fixture 计量进 §8。

**3.4 undo/redo 语义（与 dt 差异显式记录）**

- dt 用 `dt_undo_start_group` 把整批包成一个跨图 undo 组（control_jobs.c:1636/1657）。Lightamer 的 HistoryStack 是 per-image（`HistoryStack.swift:34-42`），批量 apply 后**每张目标图自己的 history 各得一个 commit**（快照 = paste 后实例集）；跨图全局 undo 组 v1 不做（§3 的段1 是内存态、段2-3 落盘态，做跨图组需要批级 journal——defer，记 OQ/risk）。单图 undo 立即可用（⌘Z 在当前图上回退本次 paste）。

### 4. FSEvents 监视 + reconcile（SESS-05）

**4.1 API 面与配置**

- `FSEventStreamCreate`：flags = `kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagNoDefer | kFSEventStreamCreateFlagWatchRoot`；latency 0.3-0.5s（coalescing 窗口）；schedule 在私有 serial DispatchQueue；回调发 `AsyncStream` 交给 reconcile 协调者。`WatchRoot` 让会话根自身被改名/移动时收到事件（提示 → 全量重扫 + 提示用户更新 recent list 路径）。

**4.2 已知缺陷清单（ROADMAP Notes + L007 正本，设计按「hint-only」展开）**

| 缺陷 | 后果 | 对策 |
|---|---|---|
| coalescing（延迟窗内合并） | 单事件可能覆盖多个变更、顺序不保证 | 事件只触发 reconcile，不直接改行 |
| 4096 路径批上限 | 大批量变更（导入 5000 张）事件截断 | 事件携带「affected 目录」而非逐文件；超阈值直接升级全量 reconcile |
| rename 丢失/拆分（旧路径+新路径两个独立事件） | 旧行被误判删除、新行误判新增 | 删除的行先标 stale 不物理删（§2.5）；reconcile diff 以 stat 裁决 rename 幸存 |
| 高负载丢事件（Watchexec 实测「a mistake」结论） | 视图与磁盘脱节 | 获焦（`NSApplication.didBecomeActiveNotification`）强制 reconcile 兜底 |

**4.3 reconcile 本体 = 纯函数目录 diff（可测性核心）**

```
reconcile(root, indexRows) -> ReconcilePlan:
  scan   = walkTree(root, exclude)         // §2.4 同款
  added/removed/changed = 三集合差
  orphanSidecars = scan 中的 .lra 无对应原片
  externalEdits  = 原片 mtime 漂移          // 外部改图 → 解码缓存失效 + thumb stale
apply(plan): 单事务更新索引 + UI diff 动画
```

- 调用点四时：①开卷（全量）；②app 获焦；③FSEvents 批后（debounce 300ms，仅受影响子树）；④WatchRoot/「must rescan」事件（全量）。**reconcile 不依赖 FSEvents 就可全测**（§8）。
- 原片被外部移走但 sidecar 在（SESS-05 的点名 edge case）：行标 `orphanSidecar`；reconcile 动作 = UI 提供「移除 sidecar / 忽略」两选项（从 Trash 恢复原片超出 v1——C1 把这类挪 Trash/，我们不做文件操作，只提示）。永不硬失败（ROADMAP SC#2 原文「gracefully… never a hard fail」）。

**4.4 忽略集（自反馈环防线）**

- watcher 回调与扫描器共用同一 exclude 表：`.lightamer/**`（自家缓存）、一切 dotfile、`*.tmp-*`（SidecarStore 晋升残留清理物，`SidecarStore.swift:150-151`）、`*.cosessiondb`（C1 会话既存物，只读不碰）、`*.lra` 的**写侧不触发**（自家 sidecar 写会触发自身事件——写入方在写完成后主动把该路径的 reconcile 计划吞掉，或按 path 前缀过滤自家 pending 写队列，plan 期二选一钉死）。

**4.5 dt 对照（为什么这是增强而非照抄）**

- dt 全源码树 grep `inotify|g_file_monitor|GFileMonitor` **零命中**——dt 不监视任何文件夹：导入靠 `dt_film_import` 扫描 job（`src/common/film.c:280-330`，`dt_control_add_job(DT_JOB_QUEUE_USER_BG, …)` :325）+ `DT_SIGNAL_FILMROLLS_CHANGED`（film.c:498）内部信号。lighttable 列表 = collection SQL 查询（`src/common/collection.c:413` `dt_collection_get_query`、:271 扩展 where、:361 排序子句）。→ 我们的「外部变更自动同步」是 C1 语义要求（SESS-05），FSEvents+reconcile 是正解；dt 能抄的是「collection = 一条可组合 SQL 查询」的查询模型（§5.1）。

### 5. 浏览模式（SESS-06；PERF-06）

**5.1 数据面：索引驱动的 collection**

- grid 数据源 = `SessionIndexStore` 查询（sort/filter 列在 schema；Phase 12 接管 filter UI）。对齐 dt 的 collection 模型（`collection.c:413-422` 一条组装好的 SQL + `memory.collected_images` 物化 :177）——我们直接对 images 表做 `ORDER BY`，10k 行内存数组零压力。
- 行模型 = 索引行 + 内存缩略图引用（LRU，§5.3）；不持有 MTLTexture（除当前编辑图外一切 GPU 平面不进 PipeCache，§5.3）。

**5.2 缩略图双档管线（吞吐的关键决策）**

| 档 | 触发 | 来源 | 成本 | 视觉 |
|---|---|---|---|---|
| **A 嵌入预览** | 无 sidecar 或 `has_edits=0` | `CGImageSourceCreateThumbnailAtIndex`（ImageIO，读 RAW 内嵌 JPEG） | ~10-50ms/张 | 与恒等渲染近似（未编辑图参数恒等 → pipe 输出≈原片渲染；色彩域差异 = 相机预览多为 sRGB/P3 vs pipe 走 Rec2020→display，缩略图尺寸下不可辨，**plan 期抽检钉口径**） |
| **B 真 pipe 渲染** | `has_edits=1` 或 stale 再生 | RAWDecoder 全解码 → `RenderPipeline.process/processComposite` @ `.thumbnail`（360px，`PipeResolution.swift:27,61-64`） | ~0.5-2s/张（100MP 更高） | 编辑后真实观感（含层栈/印框） |

- **一致性红线**：判定只看 `has_edits`（history.position ≥ 0 或 instances 超出 base 集）——严禁「图 A 档、图 B 档但同图观感跳变」以外的混用；A→B 升级只发生在「用户开始编辑该图」时。
- 档 B 复用面：`renderCurrentChain(bucket:resolution:)`（`PipeCoordinator.swift:1360-1430`）已支持 `.thumbnail`（longEdge=nil → 360 默认，:1369-1373）与层栈复合（processComposite 分支）；**但那是 coordinator 单图状态机**——Phase 9 新增 `SessionThumbnailProvider`（App 层）：per-image 独立 `RAWDecoder.decode` → 直接调 `RenderPipeline`（绕开 coordinator 的 currentImageID/instances 状态）→ 输出 CGImage → 磁盘缓存 + 索引行更新。`fetchThumbnail` 的 LAZY 语义（:1211-1230，`thumbnailNeedsRender` 门）是行为范本：**只在需要时渲染一次**。
- 后台队列：并发 2（Neural Engine/GPU 与编辑器竞争，Phase 7 磨皮同教训）；空闲调度（dt backthumbs crawler 对标：`crawler.c:968-990`——`backthumbs_inactivity` 空闲阈值 :980、mip 尺寸偏好 :981、初始化开关 :983）；可见优先（滚动中的可见 cell 插队）。

**5.3 缓存与预算**

- **磁盘缓存**（权威）：`.lightamer/thumbs/<pathhash>.jpg`（质量 ~85；360px JPEG ~30-60KB × 10k = ~0.5GB 上限可接受；HEIC 可再省——plan 期定）。索引行记 `thumb_path/thumb_params_hash`；params 变更（含批量 apply）→ `thumb_state=stale`（§3 段2 已写）→ 后台按需再生（dt「只失效不重渲」同构，history.c:997 + crawler 收尾）。
- **内存 LRU**（`ThumbnailMemoryCache`，App/Core 新件）：path→CGImage，byte 预算 256-512MB（360×240×4 ≈ 0.35MB/张 → ~750-1500 张驻留），超预算逐出最旧。单测直接断言逐出（§8）。
- **PipeCache 隔离**：缩略图**绝不进** `PipeCache`——`enforceBudget` 的 tier-1 虽把其他图 THUMBNAIL 列为最廉逐出（`PipeCache.swift:228-231`），但 10k×0.35MB=3.5GB 的洪峰会反复冲垮 3GB 预算把当前编辑图的 plane 挤掉（D-C1 语义破坏）。浏览缩略图走独立磁盘+LRU，PipeCache 只服务当前编辑图。

**5.4 三模式**

- **grid**：SwiftUI `LazyVGrid`（cell 复用由 lazy 语义承担）+ rating/label overlay（Phase 12 填数）+ edited 徽章 + 孤儿徽章。滚动只喂可见 cell 的 LRU 命中/磁盘解码；60fps = signpost hitch 计量（PERF-04 方法），基线落 `.work/09/perf.md`（门在 Phase 15 清算——ROADMAP Phase 15 Notes「解码/懒加载/批量的基线计量在对应功能阶段（9/11）建立」）。
- **单图大图**：= 现有编辑器视口原样（无新管线）。
- **culling 对比**：2-4 图并排，每格一条独立 PREVIEW 子管线（各自 `RAWDecoder` + `RenderPipeline` @ 减半 bucket——`PreviewBucket.ladder` 复用，`PreviewBucket.swift:33-35`；1480px 平面 ~23MB × 4 ≈ 92MB 可接受）。**cap 4**（每格独立解码 + 管线，内存/吞吐线性乘 N——OQ6）。同步缩放/标记淘汰（降级到 grid 打分）v1 从简，交互手感入 Manual-Only。

### 6. 复制粘贴 / 批量 apply / before-after（HIST-05 / HIST-06）

**6.1 复制载荷（Copy）**

- 载荷 = `{sourceURL, instances: [ModuleInstance]（有效集）, layerStack: SidecarLayerStackRecord?, skipSet}`，内存剪贴板（进程内）+ Codable（跨会话粘贴同进程即成立；跨进程剪贴板 v1 不做）。
- **skip 集（对齐 dt）**：`dt_history_copy` 只记 proxy 不拷数据（history.c:1882-1903）；copy 跳过「未修改默认参数模块 + `dt_history_module_skip_copy` flags」（:695-705 的条件块）。Lightamer 版：**跳 decode 域**（V50Order < colorin 28.0 的 rawprepare/demosaic 等——另一台相机的 raw 域参数不可移植）+ **跳未修改恒等默认实例**（既有 `editingDefaultInstances` 恒等种子可比对）；borders/watermark（terminal tail）**属创意模块，可复制**。
- **部分复制（copy parts）**：对话框逐模块（含每模块多实例）勾选（dt `dt_history_copy_parts` → `dt_gui_hist_dialog_new`，history.c:1906-1922 同构）。
- paste 时多实例身份：语义身份 = `(opName, multiPriority, multiName)` 元组（Phase 2 冻结身份），实例 UUID **重铸**（跨图 UUID 命名空间分离；缓存键 per-image 无碰撞风险，`PipeCacheKey.imageID` 隔离）。

**6.2 paste 三式（对齐 dt 语义，落在我们 HistoryStack 上）**

| 式 | dt 正本 | Lightamer 落位 |
|---|---|---|
| **overwrite** | `DELETE FROM history WHERE imgid` + `INSERT SELECT`（history.c:754-846） | 目标图 history 重置为「默认种子 + 载荷实例」的 commit（层栈 = 载荷层栈快照） |
| **merge/append** | `dt_history_merge_module_into_history` 逐模块并入 + `dt_dev_write_history_ext`（:590-745） | 载荷实例逐个 commit 进目标 history——`effectiveChain` 的 (opName, multiPriority) latest-wins 去重（`HistoryStack.swift:245-264`）天然处理「目标已有同名实例」的覆盖 |
| **partial** | 同上但 ops 过滤 | 同 merge/overwrite，载荷先过勾选集 |

- 目标图当前被编辑中：走 live 路径（改 `EditorState`/coordinator 状态 + 正常 commit）——`_safe_history_job_on_imgid`（control_jobs.c:1600-1607）同款保护（正在编辑的图由交互层自己 paste，批量循环跳过它）。
- 批量 = 选中集 × paste（§3 管线）。跨图全局 undo 缺口见 §3.4。

**6.3 before/after 三形态（HIST-06）**

- **公共底座：「before 平面」= 该图 pristine 链渲染**（默认种子实例集的 PREVIEW 输出），随图常驻 PipeCache（key = 常规 key + `upstreamHash=pristineSeed`——hash 语义天然区分，零 schema 改动）；首次进 before 模式时渲染一次（100MP PREVIEW 单次 ~百 ms 级，Phase 2 已验）。
- **split 分屏**：EditorMTKView 新 blit 变体——两平面 + split 位置 uniform，左右各采一平面（拖分界线交互入 Manual-Only）。
- **快照点对比**：history 任意点 peek——`HistoryStack.effectiveInstances(layerScope:)` 是纯投影（`HistoryStack.swift:230-235`），配合层栈快照（`stackSnapshot`，06-01 机制）重建「该点的实例集」→ coordinator 的 **render-with-instances 变体**渲染（不动 position 指针）。这是 §6 唯一必须新增的 coordinator 能力：`renderPreview(instances:layerStack:)` 参数化覆盖（现 renderCurrentChain 读 coordinator 状态机——加可选 override 参数，不改默认路径字节语义）。
- **按住临时看原图**：key-down → blit 切 before 平面（常驻，零渲染）；key-up → 切回。C1「按住 \」/dt 快捷语义。
- 三形态共用渲染底座、零新 GPU kernel；交互路由与 D-H1「拖动=1 commit」正交（peek 渲染不产生 history 项）。

### 7. 性能（PERF-06/07 门锚定 + 基线计量义务）

| 项 | 预算/口径 | 对策 | 落账 |
|---|---|---|---|
| **PERF-07 万张 apply ≤5s** | 段1 内存变换 + 段2 索引单事务（Release，10k-sidecar fixture）；**不含**段3 sidecar drain 与缩略图再生 | 单事务 + 串行写队列 + 脏标记后置 | `.work/09/perf.md` 门数字 + 段3 吞吐/USB 卷开销记录（只记录） |
| **PERF-06 万张滚动 60fps** | hitch（>50ms 帧间隙）计量基线；门在 Phase 15 清算 | 双档缩略图 + 磁盘缓存 + LRU + 可见优先队列 | `.work/09/perf.md` 基线 + Instruments signpost |
| 开卷时间（10k，暖索引） | 目标 ≤2s（扫描 diff + 单事务 + UI 首屏行） | 增量同步复用 mtime；渐进 ingest | 计量落账 |
| 开卷时间（10k，**冷 USB HDD**） | 无门——渐进式不阻塞 | 流式吐行；预期分钟级一次性成本 | L009 风险显式记录 |
| 缩略图生成吞吐 | 档 A ~10-50ms/张；档 B 0.5-2s/张 ×（已编辑子集） | 并发 2 + 空闲调度 + 可见优先 | 吞吐记录 |
| culling 内存 | N×PREVIEW 平面（1480px ≈ 23MB/平面） | cap 4 | MemoryBudgetTests 扩 case |
| 会话切换泄漏 | 切换后 cache.totalBytes==0、LRU 空、无在飞任务 | §1.4 teardown 序列 | E2E 断言 |

- **执行环境注记**：本项目仓库与 fixture 树在 `/Volumes/UNITEK`（USB HDD）——PERF-07 门必须在内置 SSD 上复核一次再钉数字（L009 冷读病态化前科），fixture 放 DerivedData 同卷 SSD；跨机器复测口径写进 plan。

### 8. 验证策略

| 对象 | 方法 | 断言 |
|---|---|---|
| 会话扫描 golden | 测试内构建 fixture 树（临时目录：有/无 sidecar、孤儿 .lra、保留目录、嵌套子文件夹、`*.tmp-*` 噪声） | 分类全对：pristine/edited/orphanSidecar/excluded；三级目录幂等创建（跑两次零 diff） |
| reconcile diff（纯函数） | 同 fixture 树：前后两次 scan 快照喂 diff | added/removed/changed/rename 幸存三集合精确；孤儿处置建议正确 |
| 索引 DB | round-trip；**删库重建 parity**（删 session.lindex → 全扫 → 行集合与删除前逐列相等）；WAL 崩溃恢复（写中途杀进程重开）；单事务 10k UPDATE 计时 | 删除无损（SESS-07 门）；txn < 1s 量级记录 |
| FSEvents 合成 | 单测内起真 FSEventStream 监视临时目录（macOS 本地测试合法）：create/rename/move-out/delete 各一 | 事件被分类接收（限时 await）；move-out 后 WatchRoot/全扫 reconcile 自愈（rename 丢失场景钉死） |
| 批量 apply 计量门 | **10k sidecar 树 fixture**（tiny 原片占位文件 + 真 .lra JSON——apply 不解码，原片无需真 RAW）；Release 跑 | 段1+段2 墙钟 ≤5s（门）；段3 drain 吞吐 + dirty 清零全绿（记录）；崩溃注入（中途 cancel）→ 重开后按 sidecar 重读自愈、零数据丢失 |
| 缩略图 | LRU byte 预算逐出断言（注入小预算）；磁盘缓存 round-trip；params 变更 → stale → 再生 | 逐出精确到字节；stale 再生后 thumb_params_hash 更新 |
| E2E | 跨会话切换（状态泄漏四步断言，§1.4）；外部改文件（FileManager 模拟 Finder）+ reconcile；孤儿 reconcile 动作；DB 删除重建后 grid 集合不变 | 全绿 |
| before/after | 三形态：before 平面 == pristine trio 渲染**逐字节**（L014 fence 纪律）；快照点 peek == 重放该点快照的渲染逐字节；hold 快路径不重渲（渲染计数断言） | 逐字节 + 计数 |
| GUI 验收轮 | PLAYBOOK §0-§6（真 RAW + 真会话文件夹走查 + 截图量化）；L019b `Scripts/test-direct.sh` + `caffeinate -dis` | grid 滚动/切换/复制粘贴/before-after 全链 AX 语义操作 |

- 回归纪律：每任务全套 suite 绿（现基线 973/6skip/0fail）；几何/坐标类教训不适用本 Phase，但 **L020 内容级断言原则**对 before/after 适用（渲染一致性必须是逐字节/内容级，非记账级）。

### 9. UI 面

- **侧栏会话区**（`SidebarView.swift` 现仅 30 行，扩为三段）：当前会话（名 + 路径 + 三级目录指示）、最近会话列表（SESS-04，行 = 名称 + 最后打开时间）、打开/切换入口 + `folderWatchStatus` 状态行（stub 字段现成，`SessionState.swift:20-21`）。
- **浏览模式切换**：工具栏 segmented（网格 | 单图 | 对比）；单图 = 现编辑器；grid/culling 为新视图（`SessionBrowserView` + `CullingView`）。
- **grid cell**：缩略图 + rating 星 overlay（Phase 12 接数据，先布局）+ edited 徽章 + 孤儿徽章；多选（⌘/⇧）；右键菜单 = 复制调整/粘贴/粘贴部分…/标记。
- **复制粘贴**：菜单三件（Copy Adjustments / Paste to Selected / Paste Partial…对话框）+ 浏览器上下文 ⌘C/⌘V；部分复制对话框 = 模块树 + 勾选（IOPPanelProvider 的模块清单复用）。
- **before/after**：工具栏 split 开关 + 分界拖动 + hold 键（C1 习惯「\」）；状态条显示当前对比点（pristine / history 第 k 点）。
- **红线三件**：L010——区域查询用 `.accessibilityIdentifier`（`session.row.<uuid>`、`browser.cell.<pathhash>` 稳定 id，禁索引），容器禁 accessibilityLabel；L025——新增 catalog 键语言标签跟全库 `zh`（非 zh-Hans），GUI 轮首屏查中文渲染 + `ls *.lproj` smoke；视口主导——浏览器不挤压编辑视口布局（模式切换整页替换，Inspector 在浏览模式隐藏，v1 范围控制）。
- Manual-Only 预登记：滚动手感/惯性、culling 布局手感、分界线拖动手感、hold 键响应延迟、缩略图占位观感。

### 10. Plan 拆分建议（5 个，依赖序）

| Plan | 内容 | T 数（估） | 验收要点 |
|---|---|---|---|
| **9-1 会话模型 + 索引 DB 基建** | SessionState 扩展（current/recent/watch 状态机）+ 打开/切换/teardown 编排 + 三级目录幂等维护 + `SessionIndexStore`（SQLite actor + schema 冻结 + WAL + 开卷扫描增量同步单事务）+ recent list 持久化 + fixture 树 golden + 删库重建 parity + 开卷计量基线 | 6-8 | 分类 golden 全对；删库无损重建；切换泄漏四步断言；单事务计时落账 |
| **9-2 FSEvents + reconcile** | watcher（WatchRoot/latency/忽略集）+ 事件分类 + 四时点 reconcile（纯函数 diff）+ 孤儿 sidecar 处置动作 + 自家写侧吞事件 + 合成事件测试 + 外部变更 E2E | 4-5 | rename 丢失自愈钉死；孤儿永不硬失败；忽略集防自反馈（写 100 张 sidecar 触发零自环事件） |
| **9-3 浏览模式** | grid（LazyVGrid + collection 查询）+ 双档缩略图管线（SessionThumbnailProvider + 磁盘缓存 + LRU）+ 后台队列（并发 2 + 可见优先 + 空闲调度）+ 单图模式接线 + culling（cap 4）+ PERF-06 基线 + GUI 轮 | 7-9 | LRU 断言；A/B 档判定 = has_edits 严格；滚动 hitch 基线落账；culling 内存断言 |
| **9-4 批量 apply + before/after** | 复制载荷 + skip 集 + 部分复制对话框 + paste 三式 + 批量管线三段（索引单事务 + sidecar 写队列 + dirty 自愈）+ 缩略图 stale 再生接线 + before/after 三形态（render-with-instances 变体 + 双平面 blit）+ PERF-07 计量门（SSD 复核） | 6-8 | 万张 ≤5s 门（段1+2）；崩溃注入自愈；before/after 逐字节 + 渲染计数；单图 undo 立即可用 |
| **9-5 签核** | VALIDATION（SC#1-6 对照表）+ 全套回归终轮 + GUI 验收轮汇总 + REQUIREMENTS 翻账（SESS-01..07/HIST-05/06 → Delivered）+ 移交清单（Phase 11 消费点：Output 目录常量、批量管线队列复用面、collection 过滤缝） | 2-3 | SC 全过；文档同批（§3.1 提交纪律） |

依赖序：9-1 → 9-2 → 9-3 → 9-4 → 9-5（9-2 与 9-3 的缩略图腿可部分并行，但 grid 的删除/移动正确性依赖 reconcile，串行最稳）；总量 **~25-33 T**（低于 Phase 6 的 38-48，与 Phase 4/5 量级相当）。

---

## Risks & Gotchas

1. **USB HDD 冷扫描/冷写病态化（L009）**：10k stat 扫描与 10k sidecar 写在机械盘上都是秒级→分钟级风险——渐进 ingest + 计量门必须在 SSD 复核；fixture 禁放 UNITEK 卷跑门数字。
2. **段3 一致性窗口**：DB claim 先于 sidecar 落盘——契约「真身恒 sidecar、dirty 行重读自愈」必须写死在 reconcile 与 load 两条路径上（任何「信索引参数」的捷径都会造出幽灵状态）。
3. **FSEvents 自反馈环**：自家 sidecar/缓存写入触发自家 watcher——忽略集 + 写侧吞事件双防；漏防 = 无限 reconcile 风暴（plan 期就有断言：连续写 100 sidecar 零自触发）。
4. **双档缩略图观感差**：嵌入预览（相机渲染域）vs pipe 渲染（Rec2020→display）在缩略图尺寸下理论不可辨但未实测——plan 期真样张抽检钉口径；若可见则 v1 退「全走档 B + 档 A 仅作首帧占位」。
5. **PipeCache 污染**：缩略图误入 PipeCache = 3GB 预算被浏览行为冲垮（D-C1 破坏）——隔离是硬约束，review 检查项。
6. **culling 解码风暴**：4 格同时全解码 100MP——入口节流（错峰 decode + 进度占位），否则开 culling 即 hitch（PERF-04 前科语义）。
7. **跨图 undo 缺口**：批量 apply 后全局 ⌘Z 语义不覆盖其他目标图（per-image commit）——UI 文案不得暗示「一步撤销整批」；dt undo group 的完整对位 defer（§3.4）。
8. **L012 单窗口红线**：会话/recent 打开走同窗路由；禁用 WindowGroup odoc 默认多窗行为回归。
9. **L013 惯例延续**：索引里的哈希列一律 decimal TEXT（UInt64String）；schema 冻结前再查一遍。
10. **L022 omp 纪律**：Phase 9 执行批走 omp 时零工作区并发写入；研究产物仅本文件。
11. **Phase 8 契约不动**：`terminalTailFloor=70.0` 与 yiyin run-context 注入路径被 THUMBNAIL 渲染复用——浏览管线禁改 split/注入语义（08 移交义务）。

## Open Questions for Planning

1. **SQLite 选型**：系统 libsqlite3 C API + 自包装 actor（推荐，零新依赖）vs GRDB.swift SPM（人体工学更好，破依赖红线）。**9-1 动工前拍板。**
2. **派生缓存落位**：`<session>/.lightamer/`（随会话迁移、整删重建，推荐）vs `~/Library/Application Support/Lightamer/`（不污染用户文件夹，会话移动后缓存失联）。
3. **浏览集范围与 C1 目录对齐**：递归扫描排除保留目录（推荐，兼容按日子文件夹组织）vs C1 严格口径只浏览 Capture/；Trash/（与 Selects/）建不建（REQUIREMENTS 字面三级 vs C1 惯例五级）；Crop/ v1 仅空目录维护 vs 承接工作副本语义。
4. **批量 apply 的 sidecar 落盘一致性窗口**：DB 先行 + dirty 标记 + 队列后置（推荐，PERF-07 语义成立）vs 阻塞等待全量落盘（简单但 USB 卷上万张 >>5s，门做不成）。
5. **复制 skip 集边界**：跳 decode 域 + 未修改默认（推荐，dt 对标）vs 全量含 decode 域；自动检测类几何参数（perspective auto 等）verbatim 复制 vs 目标图重跑检测（v1 verbatim 推荐——检测参数本就钉在实例里）。
6. **culling 规模**：2 图 v1（推荐，内存/吞吐保守）vs 4 图（PREVIEW 平面 ×4 ≈ 92MB + 解码吞吐 ×4）；同步缩放是否 v1。
7. **评分/标签列预留**：schema 现在建列 Phase 12 回填（推荐，零迁移）vs v1 不建列（Phase 12 ALTER）。

## Sources

### Darktable（本地源码，树 dc58cf0ba1，与 Phase 2-8 同；file:line 均核）

- `src/control/jobs/control_jobs.c:1600-1607`（`_safe_history_job_on_imgid` 正编辑图保护）、`:1607-1676`（`_control_paste_history_job_run` 批量 paste job：undo group :1636/:1657、单图 paste 循环 :1640、sidecar 批量同步后置 :1671-1675、backthumbs 收尾 :1676）
- `src/common/history.c:590-745`（merge 路径 + `dt_dev_write_history_ext` :742）、`:754-846`（overwrite 纯 SQL 路径）、`:695-705`（copy 跳过规则：未修改默认 + skip_copy flags）、`:915`（`dt_history_copy_and_paste_on_image`）、`:997`（paste 后 `dt_mipmap_cache_remove` 只失效）、`:1000-1010`（aspect ratio 延迟重算）、`:1226/:1341`（`dt_history_delete_on_image` 事务对）、`:1367/:1399`（`dt_history_truncate_on_image` 事务对）、`:1882-1903`（`dt_history_copy` 只记 proxy）、`:1906-1922`（`dt_history_copy_parts` 部分复制对话框）、`:1924-1938`（`dt_history_paste`）
- `src/common/mipmap_cache.c:724-736`（mip 尺寸梯子 180/360/720/1440/1920/2560/4096/5120/6144/7680）、`:753-755`（buffer 预算）、`:944/:957`（按需入队 `dt_image_load_job_create` → SYSTEM_FG）、`:959`（DT_MIPMAP_BLOCKING 语义）
- `src/control/crawler.c:860-990`（backthumbs crawler：空闲阈值 :980、mip 偏好 :981、初始化开关 :983）
- `src/common/film.c:280-330`（`dt_film_import` 目录扫描 + USER_BG job :325）、`:421/:498`（FILMROLLS 信号）；**全树 grep `inotify|GFileMonitor` 零命中**（dt 无文件夹监视——SESS-05 为 C1 语义增强）
- `src/common/database.c:168-181`（images 表 schema）、`:202`（selected_images）、`:1071`（masks_history）、`:1475`（history_hash 表）；`src/common/collection.c:271/:361/:413`（collection 查询组装/排序/正本）

### Lightamer 代码（现码，file:line 核过）

- `App/Sources/Lightamer/State/SessionState.swift:12-22`（三字段 stub = 本 Phase 落位锚）；`App/Sources/Lightamer/State/EditorState.swift:247-322`（单图加载流）；`App/Sources/Lightamer/State/PipeCoordinator.swift:465-571`（load：flush/restore/seed/D-C2 sweep + Phase 9 hook 注释 :538-539）、`:1211-1230`（fetchThumbnail LAZY 范本）、`:1360-1430`（renderCurrentChain THUMBNAIL/层栈复合路径）、`:1432+`（injectYiyinRunContext——禁改契约）
- `LightamerCore/Sources/Sidecar/SidecarStore.swift:32-170`（actor/2s debounce/同目录 tmp 原子晋升/load 永不 throw）；`LightamerCore/Sources/Sidecar/LightamerSidecar.swift:36-64`（UInt64String）、`:102`（schemaVersion 2）、`:114`（imageID）、`:150-161`（sidecarURL 全名共址）、`:433-437`（driftDetected）
- `LightamerCore/Sources/Pipe/History/HistoryStack.swift:34-42`（items/position）、`:147-163`（commit）、`:230-264`（effectiveChain latest-wins = paste merge 语义同构）、`:61-125`（HistoryItem + stackSnapshot/layerScope）
- `LightamerCore/Sources/Pipe/PipeCache.swift:31`（actor）、`:136-147`（invalidate/invalidateAll）、`:210-282`（enforceBudget 分档——THUMBNAIL tier-1 语义）；`LightamerCore/Sources/Pipe/PipeResolution.swift:17/:27/:61-64`（THUMBNAIL 360 LAZY）；`LightamerCore/Sources/Pipe/PreviewBucket.swift:33-35`（bucket 梯子）；`LightamerCore/Sources/Pipe/LayerCompositeDriver.swift:108-121`（terminalTailFloor 70.0 + splitTerminal——Phase 8 契约）
- `App/Sources/Lightamer/UI/LightamerApp.swift:163-173`（L012 单窗口正本）；`App/Sources/Lightamer/UI/SidebarView.swift`（30 行 stub）；`LightamerCore/Sources/Foundation/YiyinExportSettings.swift`（EXP-03/11 缝——Phase 11 消费，Phase 9 不动）

### 项目文档

- `.planning/ROADMAP.md` §Phase 9（:149-163：SC#1-6 + FSEvents 不可仅靠 Notes + SESS-07 索引 DB 原文）+ §Phase 15 Notes（基线计量义务在 Phase 9/11）；`.planning/REQUIREMENTS.md`（SESS-01..07 :32-38、HIST-05/06 :46-47、PERF-06/07 :450-451、HIST-05/06 放置理由 :429）
- `.planning/phases/06-layers-masking/06-RESEARCH.md`（体例范本 + sidecar v2/层记录拼写）；`.planning/phases/08-yiyin-border-watermark/08-DISCUSSION-LOG.md`（Phase 移交清单四项 + 08-3-SUMMARY PERF-07 关联终态）；`.planning/research/PITFALLS.md`（SESS-1..5 原文）
- `LESSONS.md`：L007（FSEvents+reconcile 正本）、L009（USB 卷 I/O）、L010/L025（UI 三红线）、L012（单窗口）、L013（哈希 decimal TEXT 惯例）、L014（读回 fence——before/after 逐字节断言适用）、L019b（test-direct.sh）、L020（内容级断言）、L022（omp 零写入）
- Capture One Session 语义（三级目录/.cosessiondb 派生缓存/Trash 惯例）：产品语义知识，无本地源码可核验——以 REQUIREMENTS SESS 节文字为准，Med 置信

---

*Phase 9 Research — 2026-09-22。产物仅本文件；未提交 git。*
