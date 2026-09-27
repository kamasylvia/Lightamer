# Plan 16-2 DECISIONS — 执行期决策清单

**执行**: 2026-09-27, executor subagent worker（16-2 W2）
**输入**: `16-2-PLAN.md` + 16-RESEARCH §1.5/§5/§7 + 16-CONTEXT D-5/6/7

---

## D1 — 分页 UI 形态 = 滚动加载，页码不做（plan 预告项，落定）

v1 = 滚动加载（`CatalogBrowserModel.loadMore()`；近端 cell `onAppear` 触发，
load-ahead 12）。页码 UI 不做。NULL 尾段衔接由主段末页的尾锚点播种承担（见 D8）。

## D2 — 内存键按 session 命名空间化（对 plan T5 断言的语义修正，重要）

Plan T5 证据写「两会话同 hash 图内存命中复用」。实测推演发现：`ThumbnailMemoryCache`
以 relPath 为键，而**同一 relPath 在两个会话是两个不同文件**（每个会话都有
`Capture/IMG_0001.ARW`）——直接复用 = 跨会话串图（A 会话的缩略图画在 B 会话的格子上），
属正确性缺陷，不可采纳。

**落定**：`SessionThumbnailProvider` 增加 additive `memoryKeyPrefix: String = ""` 参数
（默认值保 16-2 前所有调用方逐字节等价），router 以 `"<sessionID>/"` 前缀注入。共享池
目标不受损：仍是**同一个** 384MB app 级 LRU 实例服务全部会话（零新预算面），只是键空间
按会话隔离。测试相应断言「各自生产一次 + 重复取图内存命中 + 单实例缓存持有两会话键」。

## D3 — pool 打开走真 open+sync 流程

router 的 per-session provider 需要 lindex 行（tier 裁决读 has_edits/params_hash）。
`SessionIndexStore` 只有 `openSession(root:scan:)` 一个开柄面，且**空 scan 流会触发
对账全删**（sync 以 scan 为真）——禁止任何「轻量开柄」捷径。落定：惰性 + 按需（仅视口
触达的会话付出开卷成本），每池寿命一次。

## D4 — SettingsView 新建 + Settings scene 替换占位

plan 声明的 `App/Sources/Lightamer/UI/SettingsView.swift` **不存在**（Settings scene =
LightamerApp 里 `settings_placeholder` 占位 Text）。落定：新建 SettingsView（开关 + 位置
行 + NSOpenPanel 目录选择 + 诚实重建文案），挂入 Settings scene 并显式注入
catalogPreferences 环境。位置偏好存**目录**路径（选择器为目录选择），库文件名恒
`CatalogIndexSchema.databaseFileName`。

## D5 — Core 面增补（超出 plan files_modified 的四处，全部为 UI 消费所必需）

plan 的 files_modified 未包含 Core 改动，但 UI 需要的读/写面只能落在 Core 的既定缝内
（缝 a：App/Catalog 目录零 SQL——grep 自证零命中）：

1. `CatalogIndexStore.fetchSessions()` — catalog_sessions 注册表读 + 每会话图计数
   （单 LEFT JOIN 扫描；侧栏 Sessions 节数据面 + repoint 空库建库 touch）。
2. `CatalogIndexStore.FilterScope.isDefault` 改 public（侧栏 All Photographs 激活态读）。
3. `CatalogProjector.removeSession(sessionID:)` — D-16-CONTEXT-7④ 的显式移除写面
   （单事务清行集 + tags + 分类/集合归属；磁盘零触碰；组织归属随行删文案诚实）。
4. `CatalogProjector.relinkSession(sessionID:newRoot:)` — D-16-CONTEXT-7② 的 re-link
   写面（root_path UPDATE + offline=0 + 立即重投影；realpath 复用同 session_id；
   目标已被其它会话注册时 typed error——不做自动搜索）。
5. `CatalogProjector.setCountsInvalidator(_:)` — isolated setter seam（`setCountObserver`
   同款；共享运行时从 MainActor 装配钩子）。
6. `SmartAlbumStore.evaluate(id:domain:sessionStore:catalogStore:)` + `missingStore`
   error case — T4 求值域参数化入口（`.session` = 12-2 面逐字；`.catalog` = keyset
   filename 全库走查）。

## D6 — CatalogBrowserModel 骨架吸收进 T2 提交（T2/T3 提交边界调整）

侧栏五节（T2）需要可工作的网格目标，故 `CatalogBrowserModel` + `CatalogBrowserView`
（无 filter bar 版）随 T2 提交落地；T3 提交 = filter bar + 排序菜单 + Quick Filter 提示
+ 分页语义修复 + 10k 分页证据。两提交各自独立绿。

## D7 — Quick Filter 语义提示落为可见 hint 行 + 键

`catalog_filter_quick_hint`（zh：目录库域：文件名/目录按前缀匹配，区分大小写）在
Quick Filter 非空时显示——比 tooltip 更可发现，L025 同批 1 键。

## D8 — NULL 尾段衔接的 UI 消费边界（10k 套件抓出的真缺陷）

主段 ORDER BY 把 NULL 键行排在**末尾**——当主段某页恰好以 NULL 键行收尾（页满或页不满）
时，该 NULL 层头部已被主段发出；而尾段查询从层头开始。模型修复：主段页末行为 NULL 键行
时，用该行 rel_path **播种尾段锚点**（尾段从锚点之后续走），消除重发。10k 六形状
（3 键 × 双向）drain == one-shot 参照逐 identity 相等（含无重断言）。

## D9 — 离线会话行剔除策略 = 求值不过滤（plan 推荐采纳）

SmartAlbums catalog 域求值与网格查询均不追加 offline 过滤——行集完整性优先；灰显在
网格层表达（router 拒为 offline 会话建 provider + cell 0.35 透明度 + wifi.slash 标记，
零请求）。`CatalogSmartAlbumDomainTests` 有决策钉测试。

## D10 — re-link 后自动搜索不做（plan 预告项，落定）

re-link = NSOpenPanel 目录选择（SidebarView context menu）→ `relinkSession` →
router root 缓存失效 → 面板刷新。无目录爬取搜索。

## D11 — CatalogFilterBarView 独立成面（不参数化 12-2 FilterBarView）

12-2 `FilterBarView` 硬绑 SessionState。两条路：抽协议参数化（动 12-2 交付面，回归风险）
vs 独立 catalog 面（结构镜像 + 复用同一批谓词模型/本地化键/chipLabel 静态）。落定后者——
Sessions 模式零改动红线优先；谓词组结构与翻译通道（FilterDomain.catalog）完全复用。
代价 = 约一屏视图结构重复，可逆。

## D12 — 冷启动恒 Sessions 的实现位

`ContentView.onAppear` 首帧写 `organizationModeRaw = coldStartRawValue`（常量钉在
`CatalogPreferencesModel`，T7 有测试钉）；持久化值仅在单次运行内由 segmented 记忆。

## D13 — 批量写打开会话的路径

跨会话批量评分/flag/色标对每个受影响会话执行：真 openSession（scan 对账）→
MetadataService（三段语义零改）→ `writer.flushForTeardown()` 先于 closeIndex →
projector 追平。代价 = 受影响会话各付一次开卷；换取三段语义/写路径零新增。

## D14 — LightamerApp.swift / 新文件清单对 plan files_modified 的增补

- `LightamerApp.swift`（wiring 位：环境注入 + Settings scene + router 创建 + T6 闭包装配）
- 新文件：`UI/SettingsView.swift`、`UI/CatalogBrowserView.swift`、
  `UI/CatalogFilterBarView.swift`（plan 只声明了 Catalog/ 三文件 + SettingsView）
- `SessionThumbnailProvider.swift`（memoryKeyPrefix，D2）
- `CatalogProjector.swift` / `CatalogIndexStore.swift` / `SmartAlbumStore.swift`（D5）

## D15 — GUI 走查的自动化降级口径

T1/T2/T3/T5/T6 为 GUI 任务；本执行轮以模型/单元断言为主证，交互走查（开关面板、
NSOpenPanel、切换器点按、滚动加载手感、re-link 全流程、编辑回环端到端）登记 Manual-Only
台账交验收轮。App 冷启动冒烟由执行器本机执行（见 SUMMARY）。
