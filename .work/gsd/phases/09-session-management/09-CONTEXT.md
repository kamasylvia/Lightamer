# Phase 9: Capture One Session Management - Context

**Gathered:** 2026-09-25
**Status:** Ready for planning — 7 项 Open Questions 全部经用户裁决（2026-09-25 确认「全按推荐」，D-09-CONTEXT-1..7）；Phase 8 移交清单六面已逐条对位（08-DISCUSSION-LOG 终节 ↔ 09-RESEARCH §1.2）

<domain>
## Phase Boundary

全项目从「单图编辑器」升级为「会话工作流」的阶段：8 项需求（SESS-01..07 + HIST-05/06），核心架构事实：

1. **文件夹即会话是纯 App 层编排，Core 零改动**——既有 `SessionState` 三字段 stub（`App/Sources/Lightamer/State/SessionState.swift:12-22`）是落位锚；既有单图加载流（`EditorState.load` → `PipeCoordinator.load`）原样复用，会话切换 = 既有 D-C2 sweep + `invalidateAll()`（`PipeCoordinator.swift:538-539` 已预埋 hook 注释）。不新建渲染路径。
2. **索引 DB 是可重建派生缓存，真身恒 sidecar**（SESS-07 黑体）——`.cosessiondb` 同构的是「会话级缓存索引」角色；DB 任何行都可从「文件系统 + sidecar」重推导，删除 `session.lindex` 无损触发重建。这条「mutable and untrusted」原则同时管 FSEvents（hint-only）与索引（永不当权威）。
3. **批量 apply = 懒渲染三段式**（dt `_control_paste_history_job_run` 结构对标）——内存元数据变换（零渲染）→ 索引单事务 → sidecar 批量写队列后置；缩略图只失效标记 stale 后台再生。PERF-07 万张 ≤5s 门 = 段1+段2。
4. **FSEvents+reconcile 是超越 dt 的增强**（dt 全树零 inotify/GFileMonitor）——事件只做失效标记，reconcile 纯函数目录 diff 是唯一裁决者，四时点调用（开卷/获焦/事件批后/强制重扫）。

**Phase 9 不做**：

- **评分/标签的 UI 与过滤排序**（META-05 是 Phase 12 交付）——本 Phase 只建 schema 预留列（D-09-CONTEXT-7），grid cell 的 rating overlay 只布局不接数据
- **导出**（EXP 全族 = Phase 11）——只交付 `Output/` 目录存在性 + `SessionLayout.outputDirectory(for:)` 消费点常量
- **Crop/ 工作副本语义**——v1 仅创建+维护空目录（D-09-CONTEXT-3）；裁剪变体工作副本是大功能且需求未列
- **Trash/Selects 目录**——REQUIREMENTS SESS-02 字面三级（Capture/Crop/Output），C1 惯例五级不采纳（D-09-CONTEXT-3）
- **跨图全局 undo 组**（dt `dt_undo_start_group` 对位）——per-image commit 各自可退（§3.4 差异显式记录，UI 文案不得暗示「一步撤销整批」）；批级 journal defer
- **跨进程剪贴板 / 预设互通**——复制载荷进程内内存 + Codable；预设是 Phase 12
- **culling 4 图与同步缩放**——v1 = 2 图（D-09-CONTEXT-6），4 图与交互手感留后
- **拖放导入（SYS-04）/ 移动文件进会话的 UI 动作**——Phase 13；FSEvents 对外部发生的同类变更照常 reconcile
- **多窗口模型**——L012 单窗口红线延续：会话/recent 打开走同窗路由（`LightamerApp.swift:163-173` 注释是正本理由），WindowGroup odoc 禁用
- **.xmp 读写删 / 与 Darktable 互通**——永不（`.lra` 自有格式锁）
</domain>

<decisions>
## Implementation Decisions

> 7 项 = 09-RESEARCH Open Questions 全部经用户裁决（2026-09-25 确认「全按推荐」）。本节逐条记录裁决 + 理由 + 可逆性。

### D-09-CONTEXT-1: SQLite 选型 = 系统 libsqlite3 C API + 自包装 actor（零新 SPM 依赖）
- **裁决**：`SessionIndexStore` actor 自包装 libsqlite3 C API（`sqlite3_prepare/step/finalize` 薄封装 + `import SQLite3` 系统库 link，非沙盒可直接用，约 200-300 行）；GRDB.swift 否决（第三个 SPM 依赖且只服务本 Phase 单写者场景，破依赖红线）。
- **理由**：项目依赖红线（AGENTS.md Conventions）预期仅 libwebp/libavif 两个 SPM 依赖；单写者 + WAL 配置下自包装成本可控。
- **配置钉死**：`journal_mode=WAL`（UI 查询与写事务不互斥）+ `synchronous=NORMAL`（**不**用 OFF——索引虽可重建，dirty 标记丢失会让批量 apply 的崩溃自愈退化成全量重扫）+ 不开 `foreign_keys`（单表为主）。
- **Reversibility**: 中——若执行期发现 C API 人体工学严重拖累，升级 GRDB 是局部替换（schema/SQL 语句可平移），但须先回注 planner 论证。

### D-09-CONTEXT-2: 派生缓存落位 = `<sessionRoot>/.lightamer/`（会话自包含）
- **裁决**：`session.lindex`（SQLite）+ `thumbs/<pathhash>.jpg` 都落会话根下 `.lightamer/`；「删除即重建」= 删一个目录；随会话文件夹移动/拷贝整体迁移。
- **理由**：C1 `.cosessiondb` 同构落位（其 DB 也在会话内）；备选 Application Support 在会话移动后缓存失联重建，违背「删除即重建」的运维语义。
- **代价与防线**：用户会话文件夹多一个隐藏目录（可接受）；**FSEvents watcher 与扫描器共用同一 exclude 表忽略 `.lightamer/**`**（自反馈环防线，09-2 硬断言：连续写 100 sidecar 零自触发 reconcile）。
- **同构语义澄清**：用户既有 C1 会话被打开时其 `.cosessiondb` 只读不碰（ignore 集）；我们不写任何 C1 物。
- **Reversibility**: reversible——落位是常量迁移。

### D-09-CONTEXT-3: 浏览集范围 = 递归扫描排除保留目录；目录 = REQUIREMENTS 字面三级
- **裁决**：①浏览集（collection）= 会话根**递归**扫描，排除保留目录 `Capture/Crop/Output/`（若在根下——导出图不回流成候选、工作副本不重复入网格）与 `.lightamer/`、一切 dotfile 目录、`*.tmp-*`、`*.cosessiondb`；②子目录 = **Capture/Crop/Output 三级**（REQUIREMENTS SESS-02 字面），Trash/Selects 不建；③Crop/ v1 仅幂等创建+维护空目录，不承接工作副本语义。
- **理由**：摄影师按日/按场景建子文件夹，递归兼容该组织习惯；排除保留目录避免「Output 里的导出图再次成为编辑候选」的怪圈；Trash/Selects 建了就要对齐语义（v1 无删除工作流），REQUIREMENTS 字面即契约。
- **Reversibility**: reversible——扫描器只改一张 exclude 表；目录集增补是纯 additive。

### D-09-CONTEXT-4: 批量 apply 一致性窗口 = DB 先行 + dirty 标记 + sidecar 队列后置自愈
- **裁决**：段2（索引单事务 claim 新状态 + `dirty=1` + `thumb_state=stale`）不等待段3（sidecar 批量落盘）；窗口内**契约钉死：rebuild/重读永远以 sidecar 为真**（索引行仅缓存提示）；崩溃恢复 = dirty 行按 sidecar 重读覆盖索引（自愈，无损）；UI 对 dirty 行显示「进行中」徽章不静默。
- **理由**：阻塞全量落盘则 USB 卷上万张 >>5s，PERF-07 门做不成；dt 把 XMP 同步放循环外同为后置语义（control_jobs.c:1671-1675）。任何「信索引参数」的捷径都会造出幽灵状态——这条契约写死在 reconcile 与 load 两条路径上（review 检查项）。
- **Reversibility**: 无需逆转——自愈语义是终态。

### D-09-CONTEXT-5: 复制 skip 集 = 跳 decode 域 + 跳未修改恒等默认实例；自动检测参数 verbatim
- **裁决**：对齐 dt `history.c:695-705`——①**跳 decode 域**（V50Order < colorin 28.0 的 rawprepare/demosaic 等原始技术段——另一台相机的 raw 域参数不可移植）；②**跳未修改恒等默认实例**（与既有 `editingDefaultInstances` 恒等种子可比对）；③自动检测类几何参数（perspective auto 等）**verbatim 复制**（检测参数本就钉在实例里，不重跑检测）；④borders/watermark（terminal tail ≥70.0）属创意模块**可复制**。
- **理由**：全量含 decode 域会把 A 相机的 blackLevel/WB 灌给 B 相机出废片；恒等默认实例入载荷是无意义膨胀；verbatim 检测参数与 dt 行为一致（paste 不重跑 auto 检测）。
- **Reversibility**: reversible——skip 集是纯函数判定，可调表。

### D-09-CONTEXT-6: culling 规模 = 2 图 v1；4 图与同步缩放留后
- **裁决**：culling 对比 v1 = **2 图并排**，每格独立 PREVIEW 子管线（各自 `RAWDecoder.decode` + 减半 bucket，`PreviewBucket.ladder` 复用）；**cap 2**；同步缩放/标记淘汰 v1 从简不做，交互手感入 Manual-Only。
- **理由**：每格独立解码 + 管线，内存/吞吐线性乘 N（4 格 = ~92MB 平面 + 4×100MP 解码风暴）；2 图已覆盖「二选一」筛选主力场景；入口节流（错峰 decode + 进度占位）防开 culling 即 hitch。
- **Reversibility**: reversible——cap 是常量；4 图是 N=4 扩展位。

### D-09-CONTEXT-7: 评分/标签列 schema 预留 = 现在建列、Phase 12 回填
- **裁决**：`images` 表现在建 `rating INTEGER` / `color_label INTEGER` / `keywords TEXT` 三列（v1 恒 NULL），Phase 12 接管评分/标签 UI 与过滤排序（META-05）时直接回填，零 ALTER 迁移。
- **理由**：空列迁移成本为零，反向（Phase 12 ALTER + 索引重建）是真实成本；过滤排序需要这些列进索引。
- **Reversibility**: 无需逆转——列位是终态 schema 的一部分。

### 继承定案（非 OQ，RESEARCH 已论证、下游不得重开）

- **真身恒 sidecar（SESS-07 黑体）**：索引/缩略图全部是可重建派生物；`has_edits` = history.position ≥ 0（含层栈/印框实例判定——yiyin borders/watermark 实例随 sidecar 走，`paramsHash` 自动涵盖，无需 Phase 9 特判）。
- **哈希入盘纪律（L013）**：索引里一切 UInt64 哈希列（`params_hash`/`thumb_params_hash`）一律 **decimal TEXT**（`UInt64String` 惯例，正本 `LightamerSidecar.swift:36-64`）；schema 冻结前再查一遍。
- **缩略图双档管线 + PipeCache 隔离（硬约束）**：档 A = ImageIO 嵌入预览（未编辑）；档 B = 真 pipe `PixelPipe.process` @ `.thumbnail`（已编辑/stale 再生）；判定只看 `has_edits`；**缩略图绝不进 `PipeCache`**（独立磁盘缓存 + 256-512MB LRU；PipeCache 只服务当前编辑图，防 10k 平面冲垮 3GB 预算——D-C1 语义破坏，review 检查项）。
- **FSEvents hint-only + 四缺陷对策**：coalescing（事件只触发 reconcile 不改行）/ 4096 批上限（事件带目录、超阈值升级全量）/ rename 丢失（删除先标 stale，stat 裁决幸存）/ 高负载丢事件（获焦强制 reconcile 兜底）。reconcile 纯函数不依赖 FSEvents 即可测。
- **PERF-07 门 = 段1+段2 万张 ≤5s**（Release、10k sidecar fixture、**内置 SSD 复核**——fixture 禁放 UNITEK USB 卷跑门数字，L009）；段3 sidecar drain 与缩略图再生只计量落账不设门。PERF-06 = hitch 基线计量（60fps 门 Phase 15 清算）。
- **before/after 三形态共用底座**：before 平面 = pristine 链渲染随图常驻 PipeCache（key = 常规 key + `upstreamHash=pristineSeed`，零 schema 改动）；split = 双平面 blit 变体；快照点 = `effectiveInstances(layerScope:)` 纯投影 + coordinator `renderPreview(instances:layerStack:)` override 变体（不动 position 指针、不产生 history 项）；hold = key-down blit 切换零渲染。三形态零新 GPU kernel。
- **Phase 8 契约不动**：`LayerCompositeDriver.terminalTailFloor = 70.0` 尾窗与 yiyin run-context 注入路径被 THUMBNAIL 渲染复用——浏览管线禁改 split/注入语义（08 移交义务；`injectYiyinRunContext` 禁改）。
- **会话切换 teardown 五步**：①当前图 `flushSidecar()`（flushNow 语义）→ ②缩略图管线任务全 cancel → ③`cache.invalidateAll()` + `metal.clearCICaches()` + D-C2 sweep → ④索引 DB 关闭 → ⑤SessionState 更新 + 浏览集合重建；泄漏断言 = 每步后 cache.totalBytes==0、thumb LRU 空、无在飞 Task。
- **执行纪律增量（AGENTS.md 2026-09-24，Phase 7 起强制）**：`.work/config.toml [gsd]` 开关（`auto`/`paused`）——subagent worker 每任务边界检查；C 档门控三点停（research 定稿停【已过】/ 每 plan 闭环停 / 签核前停）；omp 执行模型照旧（L019b 直启单测 + L022 零写入）。

### 验证与 GUI 红线（全 plan 写死，执行期不得放宽）

- **防空转**：一切比较类断言必须真实比较（reconcile diff 三集合精确、DB parity 逐列、LRU 逐出精确到字节、before/after 逐字节 + 渲染计数），禁「存在输出即过」（06-VERIFICATION 内容级抽查口径；L020 内容级断言原则对 before/after 强制）。
- **L014 fence**：一切 GPU 纹理读回（before/after 逐字节断言、缩略图输出、culling 平面）先 drain。
- **UI 三红线**：L010——区域查询用 `.accessibilityIdentifier`（`session.row.<uuid>` / `browser.cell.<pathhash>` 稳定 id 禁索引），容器禁 accessibilityLabel；L025——新增 catalog 键语言标签跟全库 `zh`（非 zh-Hans），GUI 轮首屏查中文渲染 + `ls *.lproj` smoke；视口主导——浏览模式整页替换不挤压编辑布局。
- **面板四件套**（涉及新面板/对话框处）：L010 identifier 全量 + zh/en catalog（L025 标签）+ 280pt Inspector 约束 + D-H1 三件套（拖动恰 1 commit + ⌘Z 还原 + PanelWiringTests 扩展）。
- **GUI 复验**（AGENTS.md 硬性项）：真实 RAW + 真会话文件夹端到端（选目录 → 三级目录创建 → grid 浏览 → 复制粘贴 → before/after → 会话切换），PLAYBOOK §0-§6 量化 + Manual-Only 表登记。
- **回归纪律**：每任务全套 suite 绿（现基线 **973/6skip/0fail**，Phase 8 终轮）；每任务边界查 `.work/config.toml [gsd]` 开关。
</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

- `.planning/phases/09-session-management/09-RESEARCH.md`（正本：§1 会话模型、§2 索引 DB + schema 草案、§3 批量 apply 三段式、§4 FSEvents+reconcile、§5 浏览模式双档缩略图、§6 复制粘贴/before-after、§7 性能表、§8 验证策略、§9 UI、§10 plan 拆分、Risks 1-11）
- `.planning/phases/08-yiyin-border-watermark/08-DISCUSSION-LOG.md` 终节（Phase 9 移交清单六面：EXP-05 消费点接口面 / YiyinLayout 复用面 / 遗留对表——Phase 9 唯一义务 = Output/ 目录约定 + terminalTailFloor 契约不破）+ `07-3-SUMMARY.md`（移交清单四面对位）
- `.planning/ROADMAP.md` §Phase 9（SC#1-6 + 「Do NOT rely solely on FSEvents」Notes + SESS-07 索引 DB 原文）+ §Phase 15 Notes（PERF-06 基线计量义务在 Phase 9）；`.planning/REQUIREMENTS.md` SESS-01..07 / HIST-05/06 / PERF-06/07 正本
- `.planning/phases/06-layers-masking/06-VERIFICATION.md`（验证报告体例范本——逐需求判定表 + SC 对照 + 反模式扫描）
- `AGENTS.md`（Phase 执行模型 + **暂停机制 `.work/config.toml [gsd]` auto/paused** + Conventions——依赖最小化/sidecar/目录惯例）
- `LESSONS.md` L007（FSEvents+reconcile 正本）/L009（USB 卷 I/O + fixture 禁放 UNITEK 跑门）/L010（identifier）/L012（单窗口）/L013（哈希 decimal TEXT）/L014（读回 fence）/L019b（test-direct.sh）/L020（内容级断言）/L022（omp 零写入）/L025（zh 标签）
- dt 对标正本（本地 `/Volumes/UNITEK/Documents/Development/darktable`）：`src/control/jobs/control_jobs.c:1607-1676`（批量 paste job）、`src/common/history.c:695-705/:754-846/:997`（copy skip/overwrite/失效不重渲）、`src/common/film.c` + `src/common/collection.c:413`（dt 无监视/collection SQL 模型）
- `.work/gui-acceptance/PLAYBOOK.md`（GUI 验收操作口径 §0-§6）；`TODO.md`（Phase 8 挂账 + Phase 9 计划行）

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets（09-RESEARCH §Sources 现码 file:line 核过，planner 2026-09-25 复核）

- **SessionState stub（落位锚）**：`App/Sources/Lightamer/State/SessionState.swift:12-22`——`currentSessionURL`/`recentSessions`/`folderWatchStatus` 三字段即本 Phase 填充对象；D-03b 隔离契约（不持有其它 state 引用，跨 state 走 View 层）继续有效。
- **单图加载流（原样复用）**：`EditorState.load(url:)`（`EditorState.swift:247`）→ `PipeCoordinator.load`（`PipeCoordinator.swift:465-571`：flush :488 / restore / D-C2 sweep + Phase 9 hook 注释 :538-539）；`FileOpenHelper.openFolder`（`FileOpenHelper.swift:24`）**已存在**——open-folder 面板入口现成。
- **sidecar 面**：`LightamerSidecar.swift`（schemaVersionCurrent=2 :102、imageID :114、historyHash `@UInt64String` :139、sidecarURL 全名共址 :150-161、driftDetected）；`SidecarStore.swift`（per-image actor + 2s debounce + `writeAtomic` 同目录 tmp 原子晋升 :138-166、`flushNow` :90）——批量写队列复用同一原子写形态。
- **pipe/缓存面**：`PixelPipe.process`（`PixelPipe.swift:974` 静态入口）；`PipeResolution` THUMBNAIL 360 LAZY（`PipeResolution.swift:27/:61-64`）；`PipeCache.enforceBudget` 分档（`PipeCache.swift:210-282`）；`PreviewBucket.ladder`（culling 减半 bucket）；`HistoryStack`（items/position :34-42、commit :147-163、`effectiveChain` latest-wins :245-264、stackSnapshot/layerScope :61-125）。
- **Phase 8 契约面（禁改）**：`LayerCompositeDriver.terminalTailFloor = 70.0`（:110）+ `PipeCoordinator.injectYiyinRunContext`——THUMBNAIL 渲染走同一 driver。
- **UI 面**：`SidebarView.swift`（30 行 stub，扩三段）；`LightamerApp.swift:163-173`（L012 单窗口正本）；`FileOpenHelper.openFolder` 现成。
- **测试基建**：117 个测试文件（973/6skip/0fail 基线）；`Scripts/test-direct.sh`（L019b）；fixture 读取管线 `Tests/LightamerTests/Fixtures.swift`；`GoldenParityTests.UncompressedEXR` float 读取正本（culling/缩略图测试如需）。

### Integration Points

| 移交面（Phase 8） | Phase 9 落位 |
|---|---|
| ① EXP-05 导出消费点接口面 | **Phase 11 义务**——Phase 9 只守 `Output/` 目录存在性 + `SessionLayout.outputDirectory(for:)` 常量（9-1 T2） |
| ② `YiyinExportSettings.targetSize` 应用缝 | Phase 11 消费；Phase 9 不动 |
| ③ `YiyinLayout` 复用面 | Phase 11 消费；Phase 9 不动 |
| ④ yiyin 实例随 sidecar 走 | 索引 `has_edits`/`paramsHash` 自动涵盖（terminal tail 仍是 instances 成员）——无需特判（9-1 T5 验证一行断言） |
| terminalTailFloor=70.0 契约 | THUMBNAIL 渲染（档 B）走同一 driver——禁改 split 规则（9-3 回归钉） |

</code_context>

<specifics>
## Specific Ideas

- **执行顺序刚性**：9-1（会话模型+索引 DB 基建）→ 9-2（FSEvents+reconcile）→ 9-3（浏览模式）→ 9-4（批量 apply+before/after）→ 9-5（签核）。串行最稳（grid 的删除/移动正确性依赖 reconcile；批量 apply 的 stale 再生接线依赖 9-3 缩略图管线）。总量 ~25-33 T。
- **C 档门控**：每 plan 执行+验收闭环后停（汇报战果 + 下一 plan 摘要，等用户确认）；Phase 9 签核（VALIDATION）前停。subagent worker 每任务边界查 `.work/config.toml [gsd]` 开关（`auto=false` 停等用户「继续」；`paused=true` 全链路停）。
- **schema 冻结在 9-1**：09-RESEARCH §2.3 v1 草案为基线，拼写执行期冻结入 `09-01-DECISIONS.md`（含 D-09-CONTEXT-7 预留列 + `dirty` 列 + `meta` 表）；后续 plan 只消费不迁移。
- **10k sidecar fixture 是 9-4 计量门前提**（tiny 原片占位 + 真 `.lra` JSON——apply 不解码原片无需真 RAW）；fixture 禁放 UNITEK 卷，门数字在内置 SSD 复核后钉（L009）。
- **渐进式 ingest**：开卷扫描流式吐行、网格边扫边出；USB HDD 冷盘万张是一次性分钟级成本（无门，L009 风险显式记录）。
- **历史项边界**：批量 apply 每目标图各得一个 commit（快照 = paste 后实例集）；快照点 peek 不产生 history 项（D-H1 正交）；复制粘贴在当前编辑图走 live 路径（`_safe_history_job_on_imgid` 同款保护）。
- **孤儿 sidecar 永不硬失败**（SC#2 原文 gracefully）：索引标记 `orphanSidecar` + reconcile 动作 UI（移除 sidecar / 忽略两选项），不做文件操作。
- **执行期决策边界**：RESEARCH 未覆盖的实现细节（SQLite 绑定精确形态/缩略图 JPEG vs HEIC 选型/写队列聚批参数/双档观感抽检口径）标注执行期决策入各 plan DECISIONS，不臆造。

</specifics>

<deferred>
## Deferred Ideas

- **评分/标签 UI + 过滤排序**（META-05）——Phase 12（schema 预留列已建，D-09-CONTEXT-7）
- **导出管线**（EXP-01..08）——Phase 11（Output/ 消费点常量已备）
- **culling 4 图 + 同步缩放/标记淘汰**——v1 后（cap 常量扩展位，D-09-CONTEXT-6）
- **跨图全局 undo 组**（批级 journal）——v1 后（per-image commit 已可退，UI 文案不暗示整批撤销）
- **Trash/Selects 目录 + 会话内删除工作流**——v1 后（D-09-CONTEXT-3）
- **Crop/ 工作副本语义**——大功能，需求未列，v2 候选
- **拖放导入**（SYS-04）——Phase 13
- **多窗口受控回归**——L012 单窗口延续，v1 后观察
- **缩略图 HEIC 编码**（比 JPEG 再省）——plan 期 JPEG 起步，HEIC 执行期决策
- **C1 .cosessiondb 只读桥接**——永不（真身恒 sidecar，ignore 集只读不碰）

</deferred>

---

*Phase: 9-Capture One Session Management*
*Context gathered: 2026-09-25（planner 裁决定稿；7 项 Open Questions 用户已确认「全按推荐」——D-09-CONTEXT-1..7 全部落定）*
