---
phase: 16
plan: "16-2"
title: "双模式 UI + 跨会话浏览：设置开关+catalog 位置选择器+空库引导 + 侧栏 segmented 切换器（冷启动恒 Sessions）+ Catalogs 侧栏五节 + 跨会话网格/过滤/排序接线（FilterSQL catalog 源消费 + keyset 滚动分页）+ SmartAlbums 全库求值（域随模式）+ 缩略图跨会话路由（provider 池 + 离线灰显）+ 编辑回环/会话管理动作/re-link"
wave: 2
depends_on: ["16-1"]
autonomous: true
requirements: [CATALOG-01, CATALOG-04]
files_modified:
  - App/Sources/Lightamer/Catalog/CatalogPreferences.swift           # 新建：启用开关/文件位置偏好（16-1 键的 UI 读写面 + 位置选择器绑定）
  - App/Sources/Lightamer/Catalog/CatalogBrowserModel.swift          # 新建：@Observable 跨会话网格数据源——keyset 两段式消费 / 滚动加载 / 过滤排序状态 / 会话分组锚点
  - App/Sources/Lightamer/Catalog/CatalogThumbnailRouter.swift       # 新建：[session_id: SessionThumbnailProvider] 池 + 离线灰显
  - App/Sources/Lightamer/UI/SettingsView.swift                      # 启用开关 + catalog 文件位置选择器（按既有设置面结构落位）
  - App/Sources/Lightamer/UI/SidebarView.swift                       # 顶部 segmented 切换器（:51 List 结构 currentSection 前插 mode section）+ Catalogs 五节
  - App/Sources/Lightamer/UI/ContentView.swift                      # 模式状态接线（BrowserMode :38 之上加组织模式轴）+ Catalogs 网格挂载
  - App/Sources/Lightamer/Session/SessionCoordinator.swift          # sweep 启动时机 + 返回网格增量投影钩子（编辑回环）
  - LightamerCore/Sources/Session/SmartAlbumStore.swift             # 求值域参数化（连接库随模式；document/资产面零改）
  - Tests/LightamerTests/CatalogBrowserModelTests.swift             # 新建：分页/过滤/排序/锚点/滚动加载模型测试
  - Tests/LightamerTests/CatalogThumbnailRouterTests.swift          # 新建：池共享/离线灰显/生命周期
  - Tests/LightamerTests/CatalogSmartAlbumDomainTests.swift         # 新建：域随模式求值/离线剔除/规则零迁移
  - Tests/LightamerTests/CatalogModeIsolationTests.swift            # 新建：Sessions 模式零感知全流程断言
  - .work/gsd/phases/16-catalogs-mode/16-2-SUMMARY.md
  - .work/gsd/phases/16-catalogs-mode/16-2-DECISIONS.md
  - TODO.md                                                         # 16-2 勾选
  - LESSONS.md                                                      # 如踩坑
---

# Plan 16-2 — 双模式 UI + 跨会话浏览（W2，∥16-3）

> 背景：16-1 底座（schema/投影/分派/查询面）之上交付 CATALOG-01/04 的 UI 半边（D-16-CONTEXT-5/6/7）。
> 五条主线：① 设置开关 + 位置选择器 + 空库引导（未启用 = 切换器不存在——Sessions 恒默认零感
> 知）；② segmented 切换器 + Catalogs 侧栏五节（All Photographs / Categories / Collections /
> Smart Albums / Sessions 从属节）；③ 跨会话网格/过滤/排序 = 12-2 filter bar 全套复用只换数据
> 源（16-1 的 `CatalogIndexStore` keyset 两段式 + FilterSQL catalog 分派是唯一数据通道——禁第
> 二查询面）；④ SmartAlbums 域随模式（规则资产零改动，D-16-CONTEXT-6）；⑤ 缩略图跨会话路由
> （provider 池 = 现 per-session provider 的推广，384MB 共享 LRU 不变——RQ-16-9 零新缓存面）。
> 编辑回环与会话管理动作（移除/re-link）收本 plan（RQ-16-10 + D-16-CONTEXT-7②④）；树/集合 UI
> 在 16-3。GUI 任务全部标注需解锁控制台（Manual-Only 候补）。

## read_first

1. `.work/gsd/phases/16-catalogs-mode/16-RESEARCH.md` §1.5（查询集口径——数据源形状预期）、§5
   RQ-16-9（缩略图路由三段：现状事实/路由设计/池生命周期）、RQ-16-10（编辑回环/跨会话批量分
   组）、RQ-16-11（FilterSQL 分派消费面）、RQ-16-12（模式切换五节序/冷启动恒 Sessions）、
   RQ-16-16（startsWith 降级语义——Quick Filter 文案含大小写敏感提示）、§10 16-2 草案
2. `.work/gsd/phases/16-catalogs-mode/16-CONTEXT.md` D-16-CONTEXT-5（UI 入口全裁决）、D-16-
   CONTEXT-6（SmartAlbums 域随模式）、D-16-CONTEXT-7（reference 零搬移/离线/re-link/移除会话）、
   验证红线节（L025/防空转/隔离断言）
3. `App/Sources/Lightamer/UI/ContentView.swift`：`BrowserMode` 三态（:38）+ `browserModeRaw`
   AppStorage（:53）——组织模式轴是**第二维度**（org-mode × browser-mode），不得混淆两轴
4. `App/Sources/Lightamer/UI/SidebarView.swift`：`body` List 结构（:51 起 currentSection/
   smartAlbumSection/recentSection/watchSection——mode section 插入位 + Catalogs 侧栏节的组装
   素材）
5. `App/Sources/Lightamer/Session/SessionCoordinator.swift`：`openAndSync`（:266）+ 16-1 已挂
   的投影钩子（返回网格钩子的会话判定位）
6. `LightamerCore/Sources/Session/SmartAlbumStore.swift`：`SmartAlbumDocument`（:26-39）+ 三拆
   自愈（:100 起 `func rescan()`）——求值域参数化的「连接库」注入位；`LightamerCore/Sources/Session/
   FilterSQL.swift`（:8-22 红线 + :380 translateConjoining——SmartAlbum 求值同源翻译）
7. 16-1 产物：`LightamerCore/Sources/Catalog/CatalogIndexStore.swift`（queryPage/queryNullTail/
   scopeClause 锚点/count memo——本 plan 唯一数据通道）、`CatalogProjector.swift`（sweepAll/
   守卫）、`FilterSQL.swift` 的 `FilterDomain`/`scopeClause`（本 plan 的 T2/T3 消费面）
8. `LightamerCore/Sources/Session/SessionThumbnailProvider.swift` + `ThumbnailMemoryCache.swift`
   （:32 defaultBudgetBytes 384MB app 级单例）+ `ThumbnailDiskStore.swift`（sessionRoot 参数）
   + `App/Sources/Lightamer/UI/LightamerApp.swift`（:350 provider 注入形态——池的逐会话同款）
9. `LESSONS.md` L009/L010/L014/L020/L025（zh/en 面板纪律 + zh 首屏 smoke）/ L031（缝 a：UI 层
   零裸 SQL）+ `AGENTS.md`（Phase 执行模型）+ `.work/GOAL-STATE.md`

## 纪律（强制）

- **每任务独立提交**（Conventional Commits，只 add 本任务申报文件）；`caffeinate -dis` 包裹一切
  构建（`xcodebuild build-for-testing` 先行）。
- **单测命令** = `Scripts/test-direct.sh '<Class>'`；判据 = Executed 计数行 + failures 行，
  Executed 0 = 判据失败。
- **每任务边界检查 `.work/config.toml [gsd]` 开关**——commit 后、下一任务前。
- **不 push**；**构建勿加 `-derivedDataPath`**；**新文件后跑 `tuist generate`**（11-03）。
- **回归基线 = 16-1 收尾轮计数**（1437 + 16-1 新增，读 16-1-SUMMARY 终值；0 fail）；每任务全
  套 suite 绿。`LayerE2ERoundTripTests` 负载型 flake 若现，隔离 ×3 归因单列。
- **T1/T2/T3/T5/T6 为 GUI 任务：需解锁控制台（Manual-Only 候补）**——自动化断言走模型/单元
  面，交互走查登记 Manual-Only 台账。
- **缝 a 红线**：UI/模型层零 SQL 字符串——一切谓词经 `FilterSQL`（catalog 分派），一切数据经
  `CatalogIndexStore`；`grep -rn "SELECT\|WHERE" App/Sources/Lightamer/Catalog/` 必须零命中
  （收尾自证入 SUMMARY）。
- **Sessions 模式零感知红线**：未启用 Catalogs 时切换器/侧栏节/设置节外 UI 全部不出现；启用后
  Sessions 模式行为与 Phase 12 交付逐字节等价（隔离测试 T7）。
- **冷启动恒 Sessions**：AppStorage 读后首帧强制覆盖为 Sessions（「恒默认做成常量」——
  RQ-16-12 实现位）。
- **L025 zh/en**：新增面板键 String Catalog 同批 + zh 首屏 smoke（zh/en 键数一致断言随 suite）。
- RESEARCH/CONTEXT 未覆盖细节（分页 UI 形态=滚动加载 vs 页码、树拖拽展开语义[16-3]、离线会话
  行在 SmartAlbums 求值中的剔除策略）标注**执行期决策**入 `16-2-DECISIONS.md`，不臆造。

## Tasks

### T1 设置开关 + catalog 位置选择器 + 空库引导（GUI）

- **action**
  1. 新建 `App/Sources/Lightamer/Catalog/CatalogPreferences.swift`：`catalogsEnabled`（
     UserDefaults 键与 16-1 `CatalogProjector` 守卫同键同常量——单一拼写）+ `catalogURL`（默
     认 = `CatalogIndexSchema` 位置常量；改位置 = **重新指向不做迁移**——关闭当前 handle → 改
     偏好 → 下次启用按新路径打开，不存在则建空库，RQ-16-1②）+ 变更流回投影守卫。
  2. 设置面（SettingsView 既有结构内新增节）：「启用 Catalogs 模式」开关 + catalog 文件位置
     选择器（NSOpenPanel 目录选择；展示当前路径与 `.lcat` 文件存在态）+ 说明文案（「目录库可
     随时由会话重建」）。
  3. **空库引导**：首次启用 = 建空 `.lcat` + Catalogs 模式空态（All Photographs 空网格 + 「打
     开会话以入册」引导文案；RQ-16-1③）。
  4. zh/en 键同批（L025）。
- **证据**：模型级测试落 `CatalogModeIsolationTests` 扩段（checker M3 指认宿主；偏好键守卫联动：开关 off → `project` 直返——复用 16-1 探针断言）+
  GUI 走查记录（开关出现/消失联动切换器；位置改指向后新库创建；空态引导文案 zh）+ Manual-Only
  未尽项登记。

### T2 模式切换器 + Catalogs 侧栏五节（GUI）

- **action**
  1. `SidebarView.swift` List（:51）`currentSection` 前插 mode section：segmented（Sessions |
     Catalogs），仅 `catalogsEnabled` 时出现；选中态持久化（AppStorage）但**冷启动首帧强制
     Sessions**（覆盖读值——实现位钉死）。
  2. **组织模式轴与 BrowserMode 解耦**：org-mode（sessions/catalogs）× browser-mode（grid/
     single/culling）两轴正交；Catalogs 模式点图仍走同一 `openSession` 流程进既有编辑器
     （D-16-CONTEXT-5⑤；编辑器零模式感知）。
  3. **Catalogs 侧栏五节序**（RQ-16-12）：All Photographs（全库网格入口）/ Categories（16-3
     接线位，本 plan 落节骨架 + 空态）/ Collections（同前）/ Smart Albums（既有 smartAlbum-
     Section 复用挂载）/ Sessions（`catalog_sessions` 会话分组从属节——行 = display_name +
     图计数角标（COUNT memo 消费）+ offline 灰显；点入 = `scopeClause(sessionID:)` 锚点过滤）。
  4. 会话管理动作（从属节 context menu，双模式共享语义）：「从 Catalog 移除会话」（显式清行
  集 + 组织归属随行删——D-16-CONTEXT-7④，confirm 弹窗文案诚实标注组织归属删除）+「Re-link
  会话文件夹」（目录选择 → `root_path` UPDATE + offline=0 + 立即重投影——D-16-CONTEXT-7②）。
  5. zh/en 同批。
- **证据**：模型级测试（五节可见性 = 开关函数；锚点过滤行集正确）+ GUI 走查记录（切换器出
  现/消失/冷启动恒 Sessions/五节序/会话分组点入过滤/移除与 re-link 全流程）+ Manual-Only 登记。

### T3 跨会话网格/过滤/排序接线（GUI）

- **action**
  1. 新建 `App/Sources/Lightamer/Catalog/CatalogBrowserModel.swift`（@Observable）：数据源 =
     `CatalogIndexStore.queryPage/queryNullTail`（16-1 唯一通道）；状态 = 当前锚点（排序键末
     行值）/ chips 组 / Quick Filter 组 / 排序键方向；**NULL 尾段两段数据源**（主段耗尽自动接
     尾段——16-1 API 语义的 UI 消费）；滚动加载（执行期决策：v1 = 滚动加载，页 size 常量沿用
     16-1；页码不做——DECISIONS 记录）。
  2. **filter bar 全套复用**（D-16-CONTEXT-5⑥）：12-2 的 chips/Quick Filter/排序菜单原样挂
     Catalogs 网格——只换绑定模型（谓词组结构 `FilterPredicateGroup` 零改，翻译经 16-1
     `FilterDomain.catalog` 分派）；Quick Filter 的 filename/dir contains 在 catalog 域语义 =
     **大小写敏感 startsWith**（16-1 T3 降级——UI 提示文案注明，RQ-16-16①）。
  3. All Photographs = 无锚点全库；会话分组点入 = sessionID 锚（T2）；**Categories/Collections
     锚点留 16-3 接线**（本 plan 只留锚点参数位）。
  4. 排序键白名单 = catalog 可服务子集（date/rating/filename——16-1 表达式索引六键内；scan_
    epoch 不进 catalog 排序——列不镜像，RQ §1.5）。
  5. 网格 cell = `(session_id, rel_path)` 身份 + T5 缩略图路由取图 + rating/flag/色标 overlay
     复用 12-1 组件。
- **证据**：`CatalogBrowserModelTests`——keyset 滚动加载页序断言（10k fixture：date DESC 全库
  遍历 = 全集严格序；rating 60% NULL 场景主段→尾段衔接无重无漏）；chips 组合行集 =
  CatalogIndexStore 直查结果集相等（L020）；排序键切换锚点重置；zh 首屏 smoke。GUI 走查 +
  Manual-Only 登记。

### T4 SmartAlbums 全库求值（域随模式）

- **action**
  1. `SmartAlbumStore` 求值域参数化：`SmartAlbumDocument`/规则文件/三拆自愈**零改动**（schema
     Version 1 资产不动）；求值入口加 `domain: FilterDomain`（`.session` = 当前 lindex 既有路
     径；`.catalog` = `CatalogIndexStore` 全库），`translateConjoining(domain:)` 分派（16-1 T3
     产物——keywords 自动翻 EXISTS）。
  2. Catalogs 模式相册行数角标/网格 = catalog 求值 + `count` memo 消费（投影完成失效——16-1
     钩子已备）；离线会话行剔除策略 = 执行期决策（推荐：求值不加 offline 过滤——行集完整性优
     先，灰显在网格层表达；DECISIONS 记录）。
  3. `scope` 字段不加（additive 预留，D-16-CONTEXT-6③）。
- **证据**：`CatalogSmartAlbumDomainTests`——同一规则两域求值：session 域结果与 12-2 交付逐字
  节等价（回归锁）+ catalog 域跨会话行集正确（含 keywords 规则 EXISTS 形状）；规则文件在两模
  式切换前后字节不变（零迁移断言）。

### T5 缩略图跨会话路由（GUI 配套，模型可测）

- **action**
  1. 新建 `App/Sources/Lightamer/Catalog/CatalogThumbnailRouter.swift`：`[session_id:
     SessionThumbnailProvider]` 惰性池（每 provider 自带 `ThumbnailDiskStore(sessionRoot:)` 指
     向该会话 root；memory cache = 既有 app 级 384MB 共享单例——**跨会话 LRU 池已存在，零新预
     算面**，RQ-16-9）；路由 = `(session_id, rel_path)` → `catalog_sessions.root_path` 拼绝对
     路径 → provider 取图。
  2. 离线会话（`offline=1` 或 root stat 失败）= 灰显占位不请求；取图/stale 再生全走既有三档
     管线（内存命中即跨会话共享池复用）。
  3. 池生命周期跟随 Catalogs 网格数据源（切回 Sessions 模式 teardown——现单会话 teardown 语义
     的推广）。
- **证据**：`CatalogThumbnailRouterTests`——两会话同 hash 图内存命中复用（单例池断言）/ 离线
  占位零请求 / teardown 后 provider 释放；GUI 走查（跨会话网格缩略图渲染/点开/stale 再生）+
  Manual-Only 登记。

### T6 编辑回环 + 跨会话批量评分（GUI）

- **action**
  1. **编辑回环**（RQ-16-10）：Catalogs 网格点图 = 同一 `openSession` 流程 → 编辑写 sidecar →
     lindex 变 → **返回网格时**（编辑器 dismiss 钩子）触发该会话增量投影（16-1 `project` 单
     会话入口）→ 网格行刷新（水位追平语义）。
  2. **Catalogs 启动 sweep**：进入 Catalogs 模式 / 库打开时后台 `sweepAll()`（16-1 API 的 UI
     时机接线；不阻塞首帧）。
  3. **跨会话批量评分/flag/色标**：网格多选批量走既有 `MetadataService`，**按 session_id 分组**
     逐会话一段段2 索引事务 + 段3 sidecar 队列（每会话既有三段语义零改；无新写路径）→ 各会话
     投影追平。
- **证据**：模型级测试（编辑→投影→网格行更新链：单测面构造 lindex 变更 → project → 行集断
  言）；GUI 走查（点开编辑改评分返回网格数字已更新/批量多选跨两会话评分生效）+ Manual-Only
  登记。

### T7 双模式隔离 + L025 + 回归收尾 + SUMMARY + DECISIONS

- **action**：`CatalogModeIsolationTests`——未启用：Sessions 全流程（开卷/浏览/编辑/批量/导出
  冒烟）零 `.lcat` 句柄 + 切换器/设置节外 UI 不出现；启用后 Sessions 模式行为逐字节等价（既有
  Session 面测试全绿即证）；全 suite 终轮（16-1 收尾基线 + 本 plan 新增，0 fail）；zh/en 键数
  一致断言；缝 a grep 自证（App/Catalog 目录零 SQL 命中）入 SUMMARY；TODO.md 勾选；
  `16-2-SUMMARY.md` + `16-2-DECISIONS.md`（分页形态、离线剔除策略、re-link 后自动搜索不做、
  其余执行期决策）；Manual-Only 台账行汇总；新教训候选评估。
- **证据**：测试计数（0 fail）；隔离测试 + L025 smoke 输出；SUMMARY + DECISIONS 落盘。

## Verification

| 验收面 | 判据 | 命令 |
|---|---|---|
| 偏好/守卫 | 开关联动投影守卫 + 位置重指向 | `Scripts/test-direct.sh 'CatalogProjectorTests'`（16-1 探针段）+ GUI 走查 |
| 切换器/侧栏 | 冷启动恒 Sessions + 五节序 + 会话锚点 | `Scripts/test-direct.sh 'CatalogBrowserModelTests'` + GUI 走查 |
| 跨会话网格 | keyset 滚动序 + chips 行集相等 + 尾段衔接 | `Scripts/test-direct.sh 'CatalogBrowserModelTests'` |
| SmartAlbums | 两域求值 + 规则文件零迁移 | `Scripts/test-direct.sh 'CatalogSmartAlbumDomainTests'` |
| 缩略图路由 | 池复用 + 离线灰显 + 生命周期 | `Scripts/test-direct.sh 'CatalogThumbnailRouterTests'` |
| 隔离 | 未启用零句柄 + Sessions 等价 | `Scripts/test-direct.sh 'CatalogModeIsolationTests'` + 既有 Session 面全套 |
| 回归 | 全 suite 0 fail（16-1 基线+新增）+ L025 | `caffeinate -dis Scripts/test-direct.sh`（全套） |

## 验收标准（Acceptance）

- [ ] 未启用 Catalogs：切换器与 Catalogs UI 全部不存在，Sessions 全流程零 `.lcat` 句柄（隔离
      测试 + GUI 走查双证）
- [ ] 启用后：segmented 切换器出现 + 冷启动恒 Sessions（首帧覆盖实现位钉死）+ Catalogs 侧栏
      五节序 + 空库引导（空网格 + 「打开会话以入册」）
- [ ] 跨会话网格：keyset 滚动加载（4 排序键 × 双向）+ filter bar chips/Quick Filter/排序全套装
      配 + NULL 尾段衔接无重无漏 + filename/dir startsWith 大小写敏感语义有 UI 提示
- [ ] SmartAlbums：规则资产零改动零迁移；求值域随模式（session 域回归锁逐字节等价 + catalog
      域 EXISTS 形状）；角标走 count memo
- [ ] 缩略图：跨会话路由（provider 池 + 384MB 共享 LRU 复用断言）+ 离线灰显零请求 + 生命周期
      随网格
- [ ] 编辑回环：点开→编辑→返回网格→行已更新（水位追平）；跨会话批量评分按 session 分组走
      `MetadataService`（无新写路径）；sweep 后台不阻塞首帧
- [ ] 会话管理：移除（confirm + 组织归属删除文案诚实）+ re-link（root_path 更新 + offline 清 +
      重投影）
- [ ] zh/en 键数一致；缝 a grep 零命中；全 suite 0 fail；每任务独立提交 + 边界查开关；不 push；
      SUMMARY + DECISIONS 落盘；Manual-Only 未尽项登记
