---
phase: m6-1
plan: "M6-1-01"
title: "MCP-09-A 项目级单写者锁 + `--connect` 活实例转发（单 plan 全量批）——Core 级 SingleWriterLock 泛化件（五态 flock 语义 + payload v1 冻结拼写 + McpEndpointLock 薄封装行为零 diff）+ `<stem>.lalb.lock` 项目锁（create/open acquire + openReadOnly + close 释放 + 备份/移动/schema 零触碰）+ legacy Session 根 ride-along（`<root>/.lightamer/session.lock`）+ GUI 撞锁三选对话框与最小只读面（banner + EditorState/LibraryStore/ExportState 三 seam 写 guard + 禁用投影）+ 无头 `--project` 装配仲裁两臂（writer 常驻 / read-only 常驻 + 机读 connect 指引 stdout/stderr 分叉 + 降级指引）+ MCP 写类 typed `projectReadOnly`（additive 一枚 + 写前 probe seam + imageLiveInEditor 先判序保留）+ o-2 ColormatchResolverBox NSLock 收窄（ride-along）+ golden 五门 + 双进程双向确定性"
wave: 1
depends_on: []
autonomous: true
requirements: ["MCP-09-A（REQUIREMENTS reopened→M6-1 注记原位）"]
estimated_tests: "+52..62"
test_bundles: [LIB, APP, IOP]
files_modified:
  - LightamerCore/Sources/Foundation/SingleWriterLock.swift        # 新建：五态 flock 泛化件（acquire(at:)/probeLockAvailable(at:)/unlock/readPayload/writePayload）+ SingleWriterLockPayload（schema v1 冻结拼写：schemaVersion/role/pid/startedAt）+ SingleWriterRole（gui|headless）；五态注释与 L009 目录纪律逐条继承 McpEndpointLock（KD-1）
  - LightamerCore/Sources/Library/ProjectFileStore.swift           # 修改：create/open 增 additive `role: SingleWriterRole? = nil`（nil = 不锁——既有调用点与 LIB 测试面零 diff，KD-2）+ openReadOnly()（无锁 + readOnlyMode）+ withWriteBatch 只读 typed 拒 + close 释放腿（checkpoint 之后 unlock）+ 持有锁对象生命周期
  - LightamerCore/Sources/Library/LibraryError.swift               # 修改：additive 两 case——projectHeldByOther(detail:) / projectReadOnly(detail:)（Equatable/Sendable 惯例照旧）
  - App/Sources/Lightamer/MCP/McpEndpointFile.swift                # 修改：McpEndpointLock 改 Core 薄封装（acquire(in:)/probeLockAvailable(in:)/unlock()/lockPath 公开签名与五态头注原样保留；行为零 diff 门 = McpHostTests 双进程 fixture 原样全绿，KD-1）
  - App/Sources/Lightamer/MCP/McpServerController.swift            # 修改：headless `--project <path>` 装配参数解析 + 项目锁仲裁两臂（writer 常驻 = acquire→store.open→serve / read-only 常驻 = held→指引发射→只读 serve）+ connect 指引发射（HTTP=stdout 单行 JSON / STDIO=stderr——`connectGuidanceChannel(for:)` 常量面，KD-4）+ DEBUG `-la_project_hold_lock` fixture（`-la_mcp_hold_lock` 同型）+ stdio EOF 优雅腿 best-effort close
  - App/Sources/Lightamer/MCP/McpToolRegistry.swift                # 修改：McpToolError additive `projectReadOnly(String)` case（code/message 两 switch 补臂；wire 面 = "[projectReadOnly] <message>"，KD-5）；registry 既有 writerCheck/serverReadOnly 面零改
  - App/Sources/Lightamer/MCP/Tools/EditingToolset.swift           # 修改：Seams additive `projectWriteProbe`（default nil——既有构造零 diff）+ apply_params/export_image body 在 live 判据之后 probe（imageLiveInEditor 先判序保留，KD-5）
  - App/Sources/Lightamer/MCP/Tools/CullingToolset.swift           # 修改：McpCullingContext additive `projectWriteProbe`（default nil）+ write-five/preset-trio 注册 frame 内 probe（requireMembers 之后）
  - App/Sources/Lightamer/MCP/Tools/MatchColorToolset.swift        # 修改：写面 probe 接线（经 seams）+ :448 安装点改 `ColormatchResolverBox.replaceShared`（o-2 写点三之一）
  - App/Sources/Lightamer/Library/LibraryProjectController.swift   # 修改：openProject(at:role:) typed 冲突面（projectHeldByOther → pendingConflict 发布）+ openProjectReadOnly(at:) + isReadOnly/readOnlyHolderPid @Observable 面 + flushForTermination()（5s 有界同窗先例）+ 备份/移动语义零变化
  - App/Sources/Lightamer/Session/SessionCoordinator.swift         # 修改：legacy ride-along——openAndSync acquire `<root>/.lightamer/session.lock`（role .gui）+ close 释放 + typed 冲突经 `sessionLockConflictHandler` → toast 面（omp 回注勘误「lastError alert 面」锚虚构；legacy 无只读回退面 = 显式边界，KD-3）
  - App/Sources/Lightamer/State/EditorState.swift                  # 修改：additive `projectReadOnlyGate: (() -> Bool)? = nil` 注入缝 + commit* 家族（recordChange/commitMaskEdit/commitLayerEdit/commitRetouchEdit/commitLayerStructure/recordDrtChange/recordFilmChange——m3b 勘误真名）+ 历史导航族（performUndo/performRedo/performJump）+ paste/version 装入族（installMergePaste/installOverwritePaste/installVersionChain——omp 回注 E-OMP-1 补入）入口 backstop guard（关闭 = typed no-op + logger——UI .disabled 为第一防线，guard 为兜底；HistoryStack 零触，KD-3）
  - App/Sources/Lightamer/State/VersionCoordinator.swift           # 修改：写命令族 coordinator 级 `isReadOnly` 门（omp 回注 E-OMP-1 (b)——缝形照 ExportState，装配点接 libraryProjects.isReadOnly）
  - App/Sources/Lightamer/State/ColorMatchService.swift            # 修改：:138/:309 两安装点改 `ColormatchResolverBox.replaceShared`（o-2 写点）
  - App/Sources/Lightamer/Export/ExportState.swift                 # 修改：enqueue 面 additive 只读 guard（关 = typed 拒 + 控件禁用投影同源）
  - App/Sources/Lightamer/UI/LightamerApp.swift                    # 修改：三条项目打开路由（:1333/:1463/:1817）接冲突对话框 sheet + 只读打开腿 + terminateHandler 增 `libraryProjects.flushForTermination()`（:1204 窗内）+ GUI 内嵌宿主装配点接 projectWriteProbe（:1278/:1243 两闭包族）+ EditorState 注入 projectReadOnlyGate + pasteToSelection（:2239）batch 入口项目面只读门 + Edit 菜单 undo/redo/paste `.disabled` 追加 `|| isReadOnly`（omp 回注 E-OMP-1 (c)(d)）
  - App/Sources/Lightamer/UI/Shell/WorkspaceHostView.swift         # 修改：只读 banner（顶部 safeAreaInset 常驻 + accessibilityIdentifier）+ 编辑入点 .disabled 投影（同源布尔）+ 只读打开一次性 toast（ToastBarView 既有面）
  - App/Sources/Lightamer/UI/Shell/VersionsPanelView.swift         # 修改：版本写命令控件 `.disabled` 接 isReadOnly（omp 回注 E-OMP-1 (d) 第一防线）
  - LightamerIOP/Sources/ColorMatch/ColormatchModule.swift         # 修改：o-2——`nonisolated(unsafe) static var shared` → `sharedLock: NSLock` + `sharedInstance` + getter 锁内读 + `replaceShared(_:)`（LutLibraryStore.swift:105-123 同模块体例镜像）；ColormatchSharedResolverForward 与模块内 :97/:106 读点改走 getter（锁内读值落局部，禁跨锁二读）
  - Resources/Localizable.xcstrings                                # 修改：新键 10 枚尾块纯插入（KD-7 清单——含 legacy `session_lock_held`，omp 回注 M-OMP-1 补登记）
  - Project.swift                                                  # 修改：六新测试文件登记对应 target 数组（显式清单无 glob）+ tuist generate 恒为该批最后一个动作（L041）
  - .work/gsd/phases/m2-4-0-test-bundles/M2-4-0-BUNDLE-MAP.txt     # 修改：六新测试文件增行登记（E2 纪律，随各自任务 commit）
  - .work/gsd/phases/m6-1-interop/M6-1-01-SUMMARY.md               # 新建（T10）
  - .work/gsd/phases/m6-1-interop/M6-1-01-DECISIONS.md             # 新建（T10——含只读写入口禁用清单表（接线点逐项标注）+ 快照族影响申报 + legacy 边界登记 + 导入兜底孤儿副作用注记）
  - .work/gsd/phases/m6-1-interop/M6-1-01-ACCEPTANCE.md            # 新建（m1 双重验收记录——zcode PASS 后串行 omp 二次验收，严禁并发）
  - .work/gui-acceptance/m6-1/MANIFEST.md                          # 新建（T9——GUI 只读面走查配方）
  - .work/GOAL-STATE.md                                            # 修改：续接点
  - .work/TODO.md                                                  # 修改：M6-1 条目
  - .work/LESSONS.md                                               # 如踩坑
---

# Plan M6-1-01 — 项目级单写者锁 + `--connect` 活实例转发（单 plan 全量批）

> **性质**：M6-1 单 plan 承载 phase 全部交付面（RESEARCH §3 设计全量 + §3.3 legacy
> ride-along + §6 o-2 范围搭车）。规格正本 = `RESEARCH-NOTES.md`（§3 设计 / §4 测试
> 设计；file:line 均为 2026-10-16 HEAD `7307f66` 亲核）；裁决正本 =
> `M6-1-CONTEXT.md` 裁决记录（**OQ-M6-1-1..6 全按推荐，用户回批 2026-10-14**）。
> 机制底座 = 14-1 宿主级五态 flock（`McpEndpointFile.swift` 全文亲读，泛化不改语义）。
>
> **基线**：**3631/24/0**（M5-3-VALIDATION 2026-10-13 批准全套 `--all` 轮 TOTAL
> 亲证值，exit 0 / 2102s；bundle 分账 IOP 684/1/0〔7731MB〕/ IOPParity 456/3/0
> 〔7803MB〕/ Layers 466/4/0 / Library 636/4/0 / Sessions 279/4/0 / Export 353/4/0
> / App 757/4/0；对本仓 HEAD 静态复核 = `grep -c "func test" Tests/LightamerTests`
> 3633 ≈ 执行口径 3631，Tests/ 自该轮起零 commit 亲证）。**派发指令所引
> 3367/16/0「M5/M4-2 删除批后」与在库实况不符**：M4-2 删除批后真值 = 3335/16/1
> （2026-10-10），M4-3 +32 = 3367（pre-M5-1，M5-1-GATE-LEDGER :114），M5-1/-2/-3
> 已 +264 = 3631/24/0；**M5 删除批不存在**（IOP-HDR-06/IOP-PANO-01/TRACK 全
> Delivered 在库，REQUIREMENTS/STATE 亲核）——照 M5-2-01 基线先例记亲核后的现行
> 真值，phase 对账链 = 3631/24/0 + 本批增量，全套预期 `3683..3693/24/0` 留验收
> 对账（全套 `--all` 轮照批准制，收口才申请）。App bundle 轮前删孤儿
> `Tests/Fixtures/TiffRaster/srgb-matrix-8.tif.lra`（M4-1 挂账 #6，在树未跟踪亲证；
> M5-1 验收先例）。

## 已定裁决（生效值，硬约束，不得重开）

M6-1 OQ-1..6 **全部按推荐裁**（CONTEXT 裁决记录 2026-10-14 用户回批）。本单 plan 承载全部六项：

1. **OQ-1 = A（锁粒度）**：项目级锁文件 = `.lalb` 同目录 sibling **`<stem>.lalb.lock`**
   （flock EX|NB，五态语义 = `McpEndpointLock` 原样）；锁文件**不入包**
   （`LibrarySchema` v4 零触碰、`project_meta` 零新行、备份 sqlite3_backup 不携带、
   移动随目录走 = 五态③自然失效）；payload = `{schemaVersion, role, pid, startedAt}`
   （**flock 为唯一仲裁，pid 永不作 liveness 判据**）；legacy Session 根
   ride-along = `<root>/.lightamer/session.lock` 同件。
2. **OQ-2 = A（对称性）**：对称单写者 + 只读回退——GUI 撞锁 = 只读打开对话框三选
   （只读打开/重试/取消）；无头撞锁 = 只读 + connect 指引；**无 GUI 特权非对称**。
3. **OQ-3 = A（无头撞锁后行为）**：只读 server 常驻 + 启动 emit 机读 connect 指引
   （`{"event":"connect-guidance",...}` + stderr 人类可读行；活端点缺席 = 降级指引）；
   **否决立即退出与内嵌转发代理**。
4. **OQ-4 = A（GUI 只读面范围）**：最小只读面 = 浏览/检索/查看可用 + 编辑入点禁用
   （Inspector/节点命令/蒙版/批量 apply/Copy-Paste/导出入队/yiyin/DRT-Film-LUT 面板
   写入/版本三命令/历史写项）+ 顶部 banner 常驻 + toast 一次性告知。
5. **OQ-5 = A（锁检查时机）**：启动 + **每写类调用前 probe**（`probeLockAvailable`
   语义复用，非持有式、无锁句柄常驻）；错误码 additive 一枚
   （`projectReadOnly`）；`imageLiveInEditor` 保留且**先判**（live 判据 → 项目锁 probe）。
6. **OQ-6 = A（范围搭车）**：o-2 `ColormatchResolverBox.shared` 裸静态 → NSLock
   holder 收紧随本 plan 清偿（否决转 M6-5）。

**架构红线（本 plan 全程 + checker 机检面）**：
- **`.lalb` 零 schema 触碰**：`LibrarySchema` 零 diff（DDL/user_version/`project_meta`
  零新行）；`Project.swift` dependencies 块零 diff（零新 SPM）；零新 `.metal`。
- **MCP 20 工具封闭集零 diff**：零新工具、零工具描述改动；`McpRegistrySnapshotTests`/
  `McpFinalSnapshotTests` 工具清单白名单负测原样绿；typed 错误码 additive 申报面见 KD-5。
- **既有 MCP 宿主锁面零回归**：`mcp-endpoint.lock`/`mcp-endpoint.json` 五态语义、
  `requiresWriter`→`serverReadOnly` 门、`imageLiveInEditor` 硬拒、`McpHostTests`
  双进程 fixture 全部原样（T3 行为零 diff 门亲跑）。
- **QuickLook/Spotlight appex 零触碰**（只读旁路不持锁不 probe，13-1 immutable URI 先例）。
- **封存面零触碰**：`NodeGraphCommand`（禁用走 UI 投影 + EditorState guard 兜底，
  命令枚举零改）/`V50Order`/`Registry`/`HistoryStack`/`HistoryHash`/`PipelineDocument`/
  六格式导出矩阵（`ExportFormatSpec`/`ImageIOEncoders`/`WebPEncoder`）零 diff。
- **L057 禁令**：冲突对话框 = SwiftUI sheet/alert 面，`grep -rn "\.runModal(" App/Sources`
  零命中维持；调用点 Task hop 纪律照旧。
- **G4 parity 零触**：match_color→render 链单实例正常路径下 probe 返回可写，
  `McpMatchColorParityTests` 原样绿。

## 关键设计决策（planner 裁决，执行中不重开）

### KD-1 Core 泛化件形状（T1，RESEARCH §3.1 + `McpEndpointFile.swift` 逐条继承）

- `SingleWriterLock`（`LightamerCore/Sources/Foundation/`，`final class` +
  `@unchecked Sendable`——fd 生命周期即锁生命周期，`McpEndpointLock` 同形）：
  `static func acquire(at lockURL: URL) -> Result<SingleWriterLock, AcquireError>` /
  `static func probeLockAvailable(at lockURL: URL) -> Bool` / `func unlock()` /
  `var lockPath: String`。`AcquireError = { heldByOther, ioError(String) }` 镜像。
  五态注释（acquire / EWOULDBLOCK→只读 / 退出 kernel 释放 / 崩溃 kernel 释放且
  **O_EXCL+pid 舞蹈明确不做** / probe 判残留）、O_RDWR|O_CREAT 0o600、
  `EWOULDBLOCK || EAGAIN` 判定、parent 目录 `createDirectory(withIntermediateDirectories:)`
  （L009：测试走 NSTemporaryDirectory 引导卷）逐条继承。
- **payload 载体**：`SingleWriterLockPayload`（Codable，**schema v1 冻结拼写**）：
  `{schemaVersion: Int = 1, role: String, pid: Int32, startedAt: String}`；
  `SingleWriterRole` 枚举 `gui | headless`（rawValue 字符串）。写腿 =
  acquire 成功后 truncate+write 进锁 fd（诊断面；**缺席/陈旧不作任何判据**——
  崩溃于 write 前则 pid 未知，错误文案回落「pid 未知」，负测一条）；
  `static func readPayload(at:) -> SingleWriterLockPayload?`。
  **endpoint 不镜像进 payload**（RESEARCH §3.1 倾向采纳）——connect 指引经
  `McpEndpointDiscovery.discover()` 单源读端点，Core 不 import App 的
  `McpEndpointFile`。
- **App 侧薄封装**：`McpEndpointLock` 保留全部公开签名（`acquire(in: McpEndpointPaths)`/
  `probeLockAvailable(in:)`/`unlock()`/`lockPath`）与五态头注，内部 delegate Core
  泛化件（private inner 持有）。`HttpHostHandle.lock`/`holdLockFixtureIfRequested`/
  `McpHostTests` 面零改动。**行为零 diff 门 = T3 亲跑 McpHostTests 原样全绿**。

### KD-2 `.lalb` 项目锁面（T2，RESEARCH §3.2/§3.5——opt-in role 参数裁定）

- 锁路径 = `url.deletingPathExtension().appendingPathExtension("lalb.lock")`
  （`LibrarySchema.fileExtension` 单源拼接；`<stem>.lalb.lock` sibling）。
- **`create(name:role:)` / `open(role:)` additive 参数 `role: SingleWriterRole? = nil`
  （nil = 不锁）**——裁定依据：flock 互斥语义按 open file description 计（同进程
  二 fd 同样 EWOULDBLOCK，Darwin flock(2) 亲核），若 open() 恒锁则既有 LIB 测试面
  （双 store 打开/换腿/迁移轮）成片破坏；生产强制点 = 装配层，一切生产打开路径
  **显式传 role**（GUI 面全集见下方 omp 回注 M-OMP-4 五处清单；无头面 =
  `McpServerController` headless 恒传 `.headless`），语义闭合。既有 `store.open()`
  调用点与测试零 diff（负测：role nil 档行为逐字节不变）。
  > omp 计划复审回注（2026-10-13）（M-OMP-4）：原文宣称「生产强制点 = 装配层
  > 两点（LibraryProjectController 恒传 .gui / McpServerController 恒传 .headless），
  > 一切生产打开路径经此两点，语义闭合」——亲核不成立：生产打开路径实为五处，
  > 其中三处缺 role——`createProject→store.create(name:)`
  > （LibraryProjectController.swift:115）、move 失败回开 `store.open()`（:266）、
  > move 新位重开 `moved.open()`（:273）。后果 = 新建/移动后项目无锁常驻，另一
  > 实例 `open(role:)` 获写成功 = 双写（第一实例无锁读写、第二实例持锁读写，
  > 互不知晓）；移动窗口注记「乘入落 typed 冲突面」以重开持锁为前提，前提不
  > 成立。处方三选一钉死，本批取**显式传参**：create 传 `.gui`、move 两重开腿
  > 传 `.gui`（新建/移动后与正常打开同态 = 锁常驻；上述移动窗口前提由此恢复
  > 成立）。
- **时序**：acquire（写 payload）→ `SQLiteHandle` open → `dispatchSchema`（KD-2
  迁移三岔照旧）——**锁失败在任何写之前** typed 抛
  `LibraryError.projectHeldByOther(detail:)`（detail = payload 读得的角色/pid 摘要）。
  **flock 本身不可用**（网络卷 `ENOTSUP` 等非互斥类 ioError）→ 同样拒绝打开
  （`ioError` → openFailed 形 + 文案说明「所在卷不支持单写者锁」）——**不做
  LightCraft 式无锁警告开**（无锁开 = 双写复活窗，直违 phase goal；macOS 独占
  本地/外置盘为主，外置盘 flock 可用不受影响）。
  > omp 计划复审回注（2026-10-13）（M-OMP-5）：网络卷 flock 不可用策略原文
  > 未钉——LightCraft 对照（`lock.rs:22-24`，issue #171 测试）为「锁文件不可锁
  > → 开但警告」，本 plan 若照 ioError→openFailed 字面 = 项目打不开（行为未
  > 申报）。二选一钉死 = **拒绝并文案说明**（安全向：单写者语义不打折；用户
  > 可将项目移至本地盘）。
- `openReadOnly()`：无锁、`readOnlyMode = true`、连接照常建立（WAL 读面不变）；
  **schema 三岔钉死（E2 回注）**：先读 `PRAGMA user_version`——
  `stored == LibrarySchema.schemaVersion` 才直开（连接读面）；`stored == 0`
  （零字节 stub）与 `0 < stored < schemaVersion`（迁移前旧版）均属**写腿**
  （`dispatchSchema` ProjectFileStore.swift:140-160 亲证：stored==0 =
  `LibrarySchema.apply` 全量 DDL、0<stored<current = pre-migrate 快照轮换 +
  `LibrarySchema.migrate`）→ typed 拒 `LibraryError.projectReadOnly`
  （文案「需一次读写打开以完成建库/迁移」）——无锁只读打开**不可触发建库/
  迁移**（照抄 dispatchSchema 字面将与持锁 holder 的迁移腿并发 = 双快照轮换/
  双 migrate 包损坏窗——第二实例在第一实例迁移中打开只读的真实时序；零字节
  stub 只读静默建库 = 违背只读语义）；`stored > schemaVersion` → 既有
  `futureSchema` 拒照旧。
  **`withWriteBatch` 关闭态 typed 抛 `LibraryError.projectReadOnly(detail:)`**（写腿
  断路单点——LibraryStore/ImportService 一切库面写经此，天然全覆盖）；
  `backup(to:)` 只读拷贝**允许**（备份语义零变化）；移动（整目录搬移）= 写面拒绝
  （UI 禁用 + controller guard）。
  > checker 回注（2026-10-10）（E2）：上段 schema 三岔为 checker E2 处方落地
  > ——原文只钉写路「迁移前置锁在锁内」，只读路空缺。负测一条（旧版包只读
  > 打开 → typed 拒、非半迁移态）**并入 T2 `ProjectLockTests` 既有 openReadOnly
  > 腿族**（计数不变——checker 处方「入门 2 或门 1」二选一，store 级行为归
  > openReadOnly 腿族所在，六文件 53 法计数不受扰动）。
- `close()`：`checkpointTruncate` → handle close → **`lock.unlock()`（释放序在
  checkpoint 之后——WAL 尾安全）**；幂等照旧；terminate 腿 = `flushForTermination()`
  （AppKit 同步回调 + 5s 有界等待，`stopEmbeddedForTermination` :473 同型）。
- 崩溃/强杀 = kernel 自释放，**无残留清扫代码**（五态③④；锁文件本体是 fixture
  非证据）。移动窗口注记：move = close→move→reopen，锁在搬移窗内短暂释放
  （第二实例可乘入 → 落 typed 冲突面，可接受；DECISIONS 登记）。
- `close()`：`checkpointTruncate` → handle close → **`lock.unlock()`（释放序在
  checkpoint 之后——WAL 尾安全）**；幂等照旧；terminate 腿 = `flushForTermination()`
  （AppKit 同步回调 + 5s 有界等待，`stopEmbeddedForTermination` :473 同型）。
- **legacy ride-along**：`SessionCoordinator.openAndSync` acquire
  `<root>/.lightamer/session.lock`（`.gui`）+ `close` 释放 + 冲突 typed
  `projectHeldByOther` 经 `sessionLockConflictHandler` → toast 面（文案键
  `session_lock_held`，KD-7）。
  > omp 计划复审回注（2026-10-13）（M-OMP-2）：原文「经既有 `lastError` alert
  > 面」为锚虚构——`SessionCoordinator` 无 `lastError` 成员（基线/HEAD 双亲证
  > 0 命中；`lastError` 仅在 LibraryProjectController），实际执行 =
  > `sessionLockConflictHandler`（SessionCoordinator.swift:423 声明/:450 调用，
  > LightamerApp.swift:823 接线）→ toast（文案键 `session_lock_held`，
  > SessionCoordinator.swift:452 消费）。T4 m3a 并档断言同步改锚。
  **显式边界（KD 登记）**：
  legacy 面只落锁 + 冲突告警（重试 = 手动重开），**不做**只读回退对话框/banner
  （OQ-1 生效值 = 锁同件 ride-along；OQ-2/OQ-4 的回退面验收形态定义在项目面；
  legacy 为 `LIGHTAMER_LEGACY_LIBRARY=1` QA 通道）——只读回退面 legacy 版挂账
  M6-5 清算批，不算本 plan 缺口。

### KD-3 GUI 冲突面与最小只读态（T4/T5，OQ-2/OQ-4 生效值，RESEARCH §3.6）

- **冲突检测**：`LibraryProjectController.openProject(at:)` 捕获 typed
  `projectHeldByOther` → 发布 `pendingConflict`（url/holderPid/holderRole）→
  LightamerApp 三条打开路由（welcome :1333 / recent :1463 / File→Open :1817）汇于
  同一 sheet。**对话框三选（zh verbatim 定稿）**：标题「项目已由另一实例打开」；
  正文「"\<名\>" 由另一实例持有（pid N）。可只读打开浏览，或重试获取写权。」；
  按钮「只读打开」/「重试」/「取消」。重试臂 = 重新 acquire（五态③窗口——持有者
  可能已退出）；取消 = 清态不开。
- **只读打开**：`openProjectReadOnly(at:)` = `store.openReadOnly()` +
  `isReadOnly = true` + `readOnlyHolderPid` 记录（banner 文案源）。**无自动升级**：
  只读态持续到关闭重开（简单诚实；重开即重仲裁）。
- **只读态单一 seam（三道）**：
  1. **LibraryStore 层**：`withWriteBatch` typed 拒（KD-2）——库面写（相册操作/
     网格 rating/keywords/导入）天然断路，UI catch → toast；
  2. **EditorState 层**：`projectReadOnlyGate: (() -> Bool)? = nil` 注入
     （装配点闭包读 `libraryProjects.isReadOnly`）——写入口 backstop guard
     全集 = **13 入口**：commit* 家族（recordChange/commitMaskEdit/
     commitLayerEdit/commitRetouchEdit/commitLayerStructure/recordDrtChange/
     recordFilmChange）**+ 历史导航族**（performUndo:370/performRedo:379/
     performJump:388——undo/redo 返 `false` 不翻栈，jump no-op）**+
     paste/version 装入族**（installMergePaste:330/installOverwritePaste:341/
     installVersionChain:132——不装新栈）。同形：gate 关 = typed no-op +
     logger，**不 throw 不崩**——第一防线是 UI 禁用；
     > checker 回注（2026-10-10）（m3b）：guard 家族名单勘误——EditorState 层
     > 真名 = `recordDrtChange`（:250）/ `recordFilmChange`（:273；checker 写
     > :270 为锚漂，亲核 :273）。原名单「commitDrt/commitFilm」是其内部调用的
     > **HistoryStack** 方法（`LightamerCore/Sources/Pipe/History/HistoryStack.swift`
     > :274/:299）——HistoryStack 属封存面零 diff 红线，guard 一律落 EditorState
     > 包装层，**HistoryStack 零触**。
     > omp 计划复审回注（2026-10-13）（E-OMP-1 a）：guard 名单原封闭 7 函数，
     > 不含任何 history 导航/装入入口——只读第二实例 ⌘Z → performUndo 直改
     > history 栈 → `scheduleSidecarWrite` 改写 `.lra` position，切版本/粘贴
     > 同理 = 单写者语义泄漏（直违 phase goal 与 OQ-4 生效值）。六函数补入
     > （EditorState.swift 行号 2026-10-13 亲核）。**门落法安全性亲证**：
     > `installVersionChain` 全仓调用点仅在 VersionCoordinator 命令路径
     > （:167/:191/:249/:263/:302），`hydrate`（:100）不经它——只读打开的
     > 版本恢复合法流不受门影响；`installMergePaste/installOverwritePaste`
     > 仅 LightamerApp paste 组合路（:2302/:2304）；undo/redo 返 false 时
     > PipeCoordinator（:1827/:1836）guard 早退零副作用。HistoryStack 零触
     > 维持（m3b 纪律）——guard 一律落 EditorState 包装层。
  3. **ExportState 层**：enqueue 面 additive guard + 控件禁用同源布尔
     （yiyin sheet 入口一并禁用）。
- **历史导航/版本/paste 落位（omp 计划复审回注 2026-10-13，E-OMP-1 (b)(c)(d)）**：
  上列三 seam + EditorState 13 入口 guard 之外，三组写入口的分层落位钉死——
  - **(b) VersionCoordinator 写命令族 coordinator 级门**：全部写命令
    （createFromScratch:155/branchFromCurrent:178/pasteChain:214/switchTo:257/
    rename:272/remove:286——行号 2026-10-13 亲核）经 `installVersionChain` +
    `finishVersionAction→versionActionDidChange→scheduleSidecarWrite` 落盘，
    任一入口无门 = 只读态切版本改写 `.lra`。门形 = coordinator 级 `isReadOnly`
    缝（照 ExportState 缝形，装配点接 `libraryProjects.isReadOnly`），写命令
    全集过门（入口 guard，拒时 toast/typed 拒）。
  - **(c) pasteToSelection batch 路项目面门**：`LightamerApp.pasteToSelection`
    （:2239）入口项目面 guard——gate 关 = toast 拒 + batch 不执行
    （`SessionBatchApplier` + `batchSidecarWriter` 直写 `.lra` 原零门）。
    **legacy 会话面 paste 不受项目锁门**（legacy/项目面二分既定——legacy 判据
    源走 session.lock，KD-5 m2 回注同源）。
  - **(d) `.disabled` 第一防线接线点逐项**（同源布尔 = `libraryProjects.isReadOnly`）：
    Edit 菜单 undo（LightamerApp:1669）/ redo（:1674）/ paste 两项（:1689/:1694
    ——现仅 `canUndo/canRedo/hasPayload` 判据，追加 `|| isReadOnly`）+
    `VersionsPanelView` 版本写命令控件。export/yiyin 两处既有接线
    （WorkspaceHostView:610/:623）不变。jump 面板无 `.disabled` 要求
    （performJump guard no-op 兜底已足）。
  - **导入兜底孤儿副作用注记**：`withWriteBatch` typed 拒兜底若在 Media/ 文件
    placement 之后触发会留 Media/ 孤儿文件（ImportService.writeRow→insertRow
    经断路、盘上文件已落）——**导入以 UI 禁用为主、typed 拒为兜底**，孤儿
    副作用 DECISIONS 登记（清扫归 M6-5 清算批承接）。
- **禁用清单表（OQ-4 生效值兑现面；executor 逐项落实 + 机检清单入 DECISIONS）**：
  Inspector 调整栈 / 节点图命令（UI 投影 + guard 兜底，NodeGraphCommand 零 diff）/
  蒙版编辑（overlay 编辑模式禁入）/ 批量 apply / Copy-Paste Adjustments /
  导出入队 + yiyin / DRT·Film·LUT 面板写入 / **版本命令族（create/branch/paste/
  switch/rename/remove 全集——omp 回注扩面，原「版本三命令」为下限，switch/
  rename/remove 同为写项，收紧方向不违 OQ-4 生效值）** /
  **历史写项含 undo/redo/jump（均产生新 sidecar 字节 = 写项；含 Edit 菜单与
  jump 面板入口）** / 导入。
  **保持可用**：浏览/检索/查看/soft proof/EDR 查看/缩略图/备份（只读拷贝）。
  机检形 = 「每个 UI 写入口要么被 .disabled 投影覆盖、要么被三 seam 之一兜底」
  清单表（DECISIONS），**逐项标注接线点（.disabled 落点 文件:行 / seam 归属）**
  ——omp 回注后清单必含 undo/redo/jump/版本/paste/batch 六组接线点；走查逐项对照。
- **banner**：`WorkspaceHostView` 顶部 `safeAreaInset(edge: .top)` 常驻
  「只读——项目已由另一实例（pid N）打开」（`accessibilityIdentifier` 供 AX 断言）；
  只读打开动作时 `ToastBarView` 一次性告知（同文案键，4s auto-clear 既有面）。
- headless/GUI 对称性由同一 store/装配层保证：GUI 撞 GUI（双实例 `open -n`）、
  GUI 撞无头、无头撞 GUI 全部走同一锁文件同一判定，无角色特权（AC 门 2 双向钉死）。

### KD-4 无头仲裁与 connect 指引（T6，OQ-3 生效值，RESEARCH §3.4）

- **装配参数**：`--project <path>`（`headlessProjectPathIfRequested()`：mode 旗标
  token 后邻位取参；旗标在而路径缺/后缀非 `.lalb` = stderr 错误 exit 1）。
  `--mcp-http` 与 `--mcp-stdio` 共用；无 `--project` = 现行为不变（零回归面）。
- **启动仲裁树**（RESEARCH §3.4 原样）：
  - 无 `--project` → 现行为（endpoint 锁五态照旧）。
  - acquire 成功 → **writer 常驻臂**：`ProjectFileStore.open(role: .headless)`
    （真实打开——迁移三岔/校验照 KD-2）→ serve（读写）；store+锁随进程生命周期，
    stdio EOF 优雅腿 best-effort `close()`（checkpoint→unlock），进程死亡 kernel 兜底。
    > checker 回注（2026-10-10）（m1）：writer 臂「serve（读写）」v1 定位 =
    **`--project` 锁载体 + connect 指引 + 打开校验，工具服务面不变**——打开的
    store **不新接项目 session seam**（现行无头两腿 `SessionProvider` 恒
    `{ nil }`，session 面工具照旧 answer `notSessionMember`），executor 禁自行
    接线（20 工具封闭集精神）；「读写」v1 语义 = 库面写权归属（`.lalb` 投影/
    sidecar 写腿唯一持有者），非 MCP 工具新能力；项目级 MCP 工具承载面归
    M6-2 后续。
  - `heldByOther` → **read-only 常驻臂**：
    ① `readPayload`（holder 诊断）+ `McpEndpointDiscovery.discover()`（活端点）；
    ② **机读指引单行 JSON**（schema 钉死）：`{"event":"connect-guidance","endpoint":{
    "transport":"streamable-http","host":"127.0.0.1","port":P,"auth":"none"|"bearer"}|null,
    "holderPid":N}`；**payload 缺席**（acquire 与 payload write 间崩溃窗）→
    `holderPid: -1`（缺席值钉死，McpServerController.swift:334 执行同形）；
    > omp 计划复审回注（2026-10-13）（M-OMP-3）：指引 JSON 原只钉
    > event/endpoint/holderPid 三键拼写，payload 缺席时执行用 `-1` 而 plan 无
    > 定义、门 3 无 `-1` 变体——本批钉死；门 3 断言补 `holderPid == -1` 变体
    > （并入门 2 序 A 既有降级变体法，计数不变）。
    ③ stderr 人类可读行（`String(localized:)` 随 locale）；**端点缺席
    （noEndpointFile/staleResidueRemoved）= 降级指引**（`endpoint: null` + 文案
    「项目由另一实例持有（pid N）——关闭它或在其上开启 MCP server」）；
    ④ server 以只读臂继续 serve（写类工具经 probe seam typed 拒，KD-5）。
- **通道分叉常量面**：`connectGuidanceChannel(for mode)` —— HTTP → **stdout**
  （非协议面）；STDIO → **stderr**（stdout 是 MCP JSON-RPC 通道，零污染——
  RESEARCH §3.4 stdio 宿主注意原文钉死；负测：stdio 只读臂 stdout 在 initialize
  前零字节）。
- **exit code**：只读常驻臂 = 正常 serve 退出码（无专用码；「立即退出」臂已被
  OQ-3 否决不落）。
- **DEBUG fixture**：`-la_project_hold_lock <lalb路径>`（`-la_mcp_hold_lock` 同型：
  acquire 项目锁 + payload(role .headless) + `print("PROJECT-LOCKED <path>")` +
  `syncStdoutBestEffort()` + stdin EOF park——`#if DEBUG`，McpHostTests spawn 形）。
- McpLauncher 文档面注记（RESEARCH §3.7 末行）：agent 模板若携项目路径将撞 GUI 锁
  → connect 指引正是归宿（行为改善非回归）；本 plan **不加** launcher UI 新文案
  （注记落 DECISIONS + MANIFEST 行，v1 零新键——范围裁定向 checker 申报）。

### KD-5 MCP 写类 probe seam 与 typed 错误（T7，OQ-5 生效值，RESEARCH §3.5）

- **错误码 additive 一枚**：`McpToolError.projectReadOnly(String)`；`code` =
  `"projectReadOnly"`；wire 面 = `McpAdapters.swift:44` 既有映射
  `"[projectReadOnly] <message>"`。**亲核勘误**：RESEARCH「建议 -32002 槽位」作废
  ——在库错误面全走 string code（14 既有 case 零数字槽），不存在数字码注册面；
  additive 面 = McpToolError case + code/message 两 switch 补臂，快照族影响 =
  executor 跑 `McpRegistrySnapshotTests`/`McpFinalSnapshotTests` 后据实申报
  （D-M6-1-6 申报义务，DECISIONS 记录）。
- **probe seam（非持有式，OQ-5 时机）**：`EditingToolset.Seams` 与
  `McpCullingContext` additive `projectWriteProbe: (@Sendable () async -> McpProjectLockVerdict)?`
  （default nil = 无门——既有测试/单实例零 diff）。`McpProjectLockVerdict` =
  `{ .writable, .held(holderSummary: String, guidance: String) }`。调用点 verdict
  `.held` → throw `.projectReadOnly`（文案单源组装：localized 键 + holder 摘要 +
  connect 指引语/降级语）。
- **自持锁豁免（flock per-fd 假阴性防）**：probe 闭包由宿主装配点捕获自身持有态
  ——自持项目锁（writer 臂/GUI 正常打开）→ 直返 `.writable`（同进程第二 fd 试锁
  必 EWOULDBLOCK，不能拿 probe 探自己的锁；Darwin flock(2) 语义，KD-2 同源依据）。
  非持有态（read-only 臂/GUI 只读打开）→ `probeLockAvailable` 真探（GUI 中途退出
  → 后续写调用自然恢复可写性判定；read-only 臂无锁句柄常驻）。
- **legacy 面 probe 判据源（m2 回注接线）**：probe 闭包装配点按当前 face 取
  判据源——默认项目面读项目锁自持态（上文）；legacy face
  （`LIGHTAMER_LEGACY_LIBRARY=1`）同一闭包改读当前 session 的 `session.lock`
  自持态（GUI 内嵌宿主持锁 → 直返 `.writable`；他者持有 → `.held` typed 拒）
  ——RESEARCH §3.3「SessionIndexStore 系在 legacy 会话上写时同判」承诺兑现，
  同一泛化件第二判据源，零边际成本；接线登记入 T10 DECISIONS legacy 边界节。
  > checker 回注（2026-10-10）（m2）：legacy 面 MCP 写 probe 原 plan 静默缺位
  > （probe 闭包只定义项目锁两态，KD-2 legacy 边界注记只覆盖只读回退面）——
  > checker 处方二选一（接线 / 显式挂 M6-5），本批取**接线**（RESEARCH §3.3
  > 承诺兑现优先于挂账）。
- **判据顺序（生效值硬约束）**：`imageLiveInEditor`（apply_params body
  EditingToolset.swift:519-523）**先判** → 项目锁 probe 后判。落位 = probe 调用点
  在各写路径 live 判据之后：apply_params body（live 判据后）/ export_image body /
  write-five 注册 frame（`requireMembers` 后——metadata 面 D-8 无 live 判据的不
  对称**保留不动**）/ preset-trio frame / match_color body。registry 旧
  `writerCheck`（endpoint → serverReadOnly）零改零移（两层锁正交：endpoint 锁
  仲裁 server 实例、项目锁仲裁库面写权，RESEARCH §3.7 表）。
- **文案键**：`mcp_error_project_read_only`（静态键 + 插值——V15/F-2 禁形遵守：
  禁 `String.LocalizationValue("prefix_\(x)")` 动态查表键形态，键恒字面量）。
  读类工具零影响（render_preview/list_photos/get_thumbnails 照常 = 只读 server
  的存在意义，负测一条）。

### KD-6 o-2 ColormatchResolverBox NSLock 收窄（T8，OQ-6 生效值）

- `LightamerIOP/Sources/ColorMatch/ColormatchModule.swift:82-89`：
  `public nonisolated(unsafe) static var shared` → `private static let sharedLock =
  NSLock()` + `private nonisolated(unsafe) static var sharedInstance` + `public
  static var shared`（getter 锁内读）+ `public static func replaceShared(_:)`
  （锁内换）——**`LutLibraryStore.swift:105-123` 同模块体例逐行镜像**（AGENTS
  M2-5 shared holder 节正本）。
- 写点三处改 `replaceShared`：`ColorMatchService.swift:138/:309` +
  `MatchColorToolset.swift:448`。读点改走 getter 且**锁内读值落局部**（禁跨锁
  二读）：`ColormatchSharedResolverForward.loadCube/cdfSolution` +
  `ColormatchModule.swift:97/:106`。
- 行为零 diff 门：`McpMatchColorToolsetTests`/`McpMatchColorParityTests`/
  Colormatch 既有 IOP 测试原样全绿；新增并发压测小法（swap/load 竞争无 data race
  面断言——TSan 轮可选项，DECISIONS 记）。

### KD-7 本地化新键清单（10 枚，尾块纯插入）

`project_read_only_banner`（banner+toast 共用，pid 插值）/ `project_read_only_dialog_title`
/ `project_read_only_dialog_message`（名+pid 插值）/ `project_read_only_open` /
`project_read_only_retry` / `project_read_only_cancel` / `mcp_error_project_read_only`
（pid+指引插值）/ `mcp_connect_guidance_stderr`（pid+端点插值）/
`mcp_connect_guidance_stderr_noendpoint`（降级臂）/ **`session_lock_held`（legacy
会话冲突 toast 文案——`SessionCoordinator.swift:452` 经
`sessionLockConflictHandler` 消费；T4 执行已插而本清单原漏登记，omp 回注补录
9→10）**。全部静态键 + `defaultValue`
插值形态（V15 提取器可见）；zh-audit `--check` 新键全入册。
> omp 计划复审回注（2026-10-13）（M-OMP-1）：guidance 双键 catalog 缺席问题
> （在码 `McpServerController:354/:359` 引用而 catalog 缺席 = en 用户回落中文
> defaultValue）已随 T9 收口批插齐（commit `81fdb0fc`），本注记为对账记录。

### KD-8 测试设计与 golden 五门（T1..T8，RESEARCH §4 + ROADMAP M6-1 验收形态）

- **门 1（锁五态 round-trip）**`SingleWriterLockTests`（LIB）：acquire 成功 / 同进程
  二 fd `heldByOther` / unlock 后重获（互斥让渡）/ probe 三态（free/held/payload 残留
  不影响 probe 判定）/ payload round-trip（v1 拼写冻结负测：缺字段拒解码）/
  payload 缺席时 held 判定与文案回落 / ioError 负测（坏路径）。
- **门 2（对称只读回退 + 双向确定性）**`McpProjectArbitrationTests`（APP，真实双
  进程——`McpHostTests` spawn 形同型）：
  - **序 A**（父持锁 → 子无头 `--mcp-http --project P`）：子 stdout 首行 = 指引 JSON
    可解析（event/holderPid/endpoint 三键）+ 进程存活（只读常驻）+ endpoint json
    在盘；**序 A'**（stdio 变体）：指引 JSON + 人类行均在 **stderr**、stdout 零字节
    （协议面零污染负测）。
  - **序 B**（子 `-la_project_hold_lock` 持锁 → 父 `ProjectFileStore.open(role:)`）：
    typed `projectHeldByOther` + detail 携 holder 摘要。
  - **确定性门**：双向序各自连续两跑结论逐位一致（赢家/输家角色对称确定，不依赖
    调度序）；序 A 持锁父退出后子重跑获 writer 臂（五态③窗口实测）。
- **门 3（connect 指引机读）**：并入门 2 序 A 断言（JSON schema 逐键 + 降级形态
  `endpoint: null` 变体——持锁父不开 MCP host 场景）+ `holderPid == -1` 缺席值
  变体断言（payload 缺席场景，omp 回注 M-OMP-3——并入既有降级变体法，计数不变）。
- **门 4（GUI 只读面）**`ProjectReadOnlyFaceTests`（APP，**18 法** = T4 前半 6 +
  T5 后半 12）：三 seam 负测家族（readOnlyMode → withWriteBatch typed 拒 /
  projectReadOnlyGate 关 → 写入口全集 13 函数 no-op / ExportState enqueue 拒）+
  `openReadOnly` 无锁面 + banner AX 标识 + 禁用投影同源布尔 + 重试臂（持锁者
  退出后重开获写）+ 冲突 detail 文案 **+ history 导航/版本/paste 四法（omp 计划
  复审回注 2026-10-13，E-OMP-1 (e)）：①gate 关 → performUndo/performRedo/
  performJump no-op 不翻栈（sidecar 字节不变）；②版本写命令族拒（coordinator
  级门——create/branch/paste/switch 取 representative 断言）；③单图 paste 拒
  （installMergePaste/installOverwritePaste no-op）；④pasteToSelection batch
  入口拒（toast/不执行）**。
  实机走查 = T9 MANIFEST（Manual-Only 行：双实例 `open -n` 撞锁对话框三选/
  banner 常驻/禁用清单逐项（含 undo/redo/jump/版本/paste 接线点）/浏览可用）。
- **门 5（MCP typed projectReadOnly）**`McpProjectReadOnlyErrorTests`（APP）：
  probe `.held` → 写类工具 typed `projectReadOnly`（code 断言 + 文案携 pid+指引）/
  读类工具照常 / `imageLiveInEditor` 先判序负测（live 图 + 锁 held →
  imageLiveInEditor 而非 projectReadOnly）/ probe nil 档零行为门（既有 toolset
  测试面零 diff 亲证）/ `serverReadOnly` 旧语义保留负测 / 20 工具封闭集快照族
  零 diff / writerCheck 顺序（endpoint 门 → probe）断言。
- **SC 数字门**：LIB 636/4/0 + 18 = `654/4/0`；APP 757/4/0 + 35 = `792/4/0`
  （**跑前删孤儿 .lra**）；IOP 684/1/0 + 4 = `688/1/0`；全套预期
  `3631 + 57 = 3688/24/0`（估带 3683..3693，验收轮对账；全套轮批准制）。
  静态登记：六新文件 BUNDLE-MAP 增行（8+10+18+9+8+4 = 57 法预估——
  ProjectReadOnlyFaceTests = 18（T4 前半 6 + T5 后半 12），终态对账勘误
  惯例照 M2-8 批）。
  > checker 回注（2026-10-10）（E1）：SC 算术补计——原「六新文件 8+10+6+8+9+4
  > = 45 法」只计了 ProjectReadOnlyFaceTests 的 T4 前半 6 法，**T5 后半 8 法**
  > 漏加；真值 = SingleWriterLockTests 8 + ProjectLockTests 10 +
  > McpProjectArbitrationTests 9 + McpProjectReadOnlyErrorTests 8 +
  > ColormatchResolverBoxTests 4 + ProjectReadOnlyFaceTests **14**（6+8）=
  > **53 法**；分账 LIB +18 / APP **+31**（14+9+8）/ IOP +4 → **APP 788**、
  > 全套预期 **3631+53 = 3684**；估带 3671..3681 上移为 **3679..3689**；
  > front-matter `estimated_tests` 同步 "+40..50" → "+48..58"。同步点五处：
  > front-matter / plan 头基线注 / 本段（KD-8 SC）/ T10 验收 / AC8。
  > omp 计划复审回注（2026-10-13）（E-OMP-1 e）：门 4/T5 增 4 法（undo no-op /
  > 版本命令拒 / paste 拒 / batch 拒）→ ProjectReadOnlyFaceTests 14→**18**
  > （T4 前半 6 + T5 后半 12）、六文件 53→**57**、APP +31→**+35**（= **792**）、
  > 全套预期 **3688**、估带上移 **3683..3693**、front-matter `estimated_tests`
  > "+48..58"→"+52..62"；同步点仍五处（front-matter / plan 头基线注 / 本段
  > （KD-8 SC）/ T10 验收 / AC8），均已同步。

## read_first

1. `.work/gsd/phases/m6-1-interop/M6-1-CONTEXT.md`（裁决记录 = 六项生效值正本）+
   `RESEARCH-NOTES.md` §3（设计全文）/§3.7（零回归面盘点表）
2. `App/Sources/Lightamer/MCP/McpEndpointFile.swift` 全文（五态正本 + L009 + pid
   纪律头注——泛化的逐条继承源）
3. `App/Sources/Lightamer/MCP/McpServerController.swift`（runHeadless 两臂/
   startHTTPHost 锁序/`stopEmbeddedForTermination` 5s 有界形/DEBUG fixture 同型
   :541-571/syncStdoutBestEffort :527 管道纪律）
4. `App/Sources/Lightamer/MCP/McpToolRegistry.swift`（McpToolError 表/writerCheck
   门/writeCallCount）+ `McpAdapters.swift:40-44`（错误 wire 面）
5. `App/Sources/Lightamer/MCP/Tools/EditingToolset.swift`（Seams :110-124/live 判据
   :519-523）+ `CullingToolset.swift`（registerWriteFive :308 frame/registerPresetTrio
   :453）+ `MatchColorToolset.swift`（:448 安装点）
6. `LightamerCore/Sources/Library/ProjectFileStore.swift` 全文（checkpoint 纪律/
   withWriteBatch/backup 核心）+ `LibraryError.swift` + `LibrarySchema.swift`
   （fileExtension 单源；v4 零触碰红线）
7. `App/Sources/Lightamer/Library/LibraryProjectController.swift`（openProject/
   closeProject/moveProject/lastError 面）+ `App/Sources/Lightamer/Session/
   SessionCoordinator.swift`（openAndSync :411/close :454——ride-along 落点）
8. `App/Sources/Lightamer/UI/LightamerApp.swift`（:128 EntryPoint fork/:1204
   terminateHandler 窗/:1243-1310 内嵌宿主装配与三打开路由）
9. `App/Sources/Lightamer/State/EditorState.swift`（commit* 家族入口清单 :176/:696/
   :784/:1059/:1181 + recordDrtChange :250 / recordFilmChange :273（m3b 补）+
   performUndo :370 / performRedo :379 / performJump :388 / installMergePaste :330 /
   installOverwritePaste :341 / installVersionChain :132（omp E-OMP-1 补）——
   guard 落点）+ `App/Sources/Lightamer/State/VersionCoordinator.swift`
   （写命令族 :155-:286 + `finishVersionAction` 尾——omp E-OMP-1 (b) 落点）+
   `App/Sources/Lightamer/State/ColorMatchService.swift`
   （:138/:309）+ `LightamerIOP/Sources/ColorMatch/ColormatchModule.swift`
   （:82-113 box+forward）
10. `LightamerIOP/Sources/Lut3d/LutLibraryStore.swift:105-123`（shared holder 体例
    正本——o-2 逐行镜像源）+ `Tests/LightamerTests/McpHostTests.swift`（双进程
    fixture spawn/握手/bounded wait 形）
11. `Scripts/test-direct.sh` + `.work/gsd/phases/m2-4-0-test-bundles/
    M2-4-0-BUNDLE-MAP.txt`（域模式与登记纪律）+ AGENTS.md L057 节（runModal 禁令
    与 begin 缝判别式）

## 纪律（强制）

- **每任务独立提交**（Conventional Commits 全英文；只 add 相关文件；front-matter
  `files_modified` 为界）；新测试文件随各自任务 commit 登记进 BUNDLE-MAP（E2）+
  `Project.swift` 对应数组（L041：`tuist generate` 恒为该批最后一个动作）。
- **构建**：`caffeinate -dis` 包裹；单测标准命令 = `Scripts/test-direct.sh --bundle <域>`
  （直启宿主）；**全套 `--all` 需 orchestrator 批准，本 plan 收口轮才申请**；
  App bundle 轮前删孤儿 `Tests/Fixtures/TiffRaster/srgb-matrix-8.tif.lra`（M4-1
  挂账 #6 先例，跑前删跑后不复活即净）。
- **资源监控**（AGENTS）：测试宿主与 GUI 实例同名 Lightamer——清理进程前核
  parentage（M2-7-3 事故教训）；走查多实例用 `open -n`，收工清干净。
- **L014 GPU fence**：本 plan 无新 GPU 读回面（MCP render 链零触）；若走查带
  render 探针则 fence 纪律照旧。
- **L057**：对话框全 SwiftUI sheet/alert；`grep -rn "\.runModal(" App/Sources`
  零命中自证入 T9。
- **双进程测试管道纪律**：子进程 stdout 断言前 `fflush+fsync` 形（McpServerController
  `syncStdoutBestEffort` 先例——pipe 上 fsync EINVAL 陷阱），握手 bounded wait
  照 McpHostTests 形。
- 零 diff 红线自证（T9）：`git diff <基线>..HEAD -- LightamerCore/Sources/Library/
  LibrarySchema.swift Project.swift`（dependencies 块）零命中 + 20 工具快照族
  原样 + 截屏入 SUMMARY。
- 中文标注（待核/待定/待补）一律显式；无源待核项入 DECISIONS 待供件清单。

## Tasks

### T1 Core SingleWriterLock 泛化件（KD-1）

- read_first 2 → `SingleWriterLock.swift`（五态 acquire/probe/unlock + payload v1 +
  SingleWriterRole + L009 目录腿）。
- 验收：`SingleWriterLockTests`（LIB，8 法）——门 1 全清单（含 payload 冻结拼写
  负测与 pid 缺席回落）；`McpEndpointFile.swift` 本任务零触碰（T3 才动）。

### T2 `.lalb` 项目锁 + legacy ride-along（KD-2）

- read_first 6/7 → `ProjectFileStore` additive role 面 + `openReadOnly` +
  `withWriteBatch` 拒 + close 释放序 + `LibraryError` 两 case +
  `SessionCoordinator` ride-along。
- 验收：`ProjectLockTests`（LIB，10 法）——role nil 档零行为门（既有 open 路径
  逐字节）/ acquire→open 时序（锁失败在任何 SQLite 写之前）/ openReadOnly 无锁 +
  写批 typed 拒 + 旧版包只读打开 typed 拒（E2 负测——非半迁移态，并入本腿族）
  + backup 允许 / close 释放后第二实例可获 / typed 冲突 detail 携
  holder 摘要 / 锁文件不入 backup 产物 / legacy session.lock 原语级
  acquire+release（`<root>/.lightamer/session.lock` 路径形——SingleWriterLock
  原语直测）/ 迁移前置锁（pre-migrate 快照腿在锁内）。
  > checker 回注（2026-10-10）（m3a）：legacy **冲突面**断言移 APP——
  > SessionCoordinator 在 App target（App/Sources/Lightamer/Session/），LIB
  > （LightamerCore 测试）不可达；冲突断言（typed 冲突经
  > `sessionLockConflictHandler` → toast——omp 计划复审回注 2026-10-13 勘误：
  > 原「lastError alert 面」为锚虚构）并入 T4 前半冲突投影法（同法双断言并档，
  > 计数不变）。

### T3 App McpEndpointLock 薄封装（KD-1 行为零 diff 门）

- read_first 3 → `McpEndpointFile.swift` 内 `McpEndpointLock` delegate Core
  （签名/头注/五态注释保留），其余零触碰。
- 验收：**McpHostTests 原样全绿亲跑**（双进程 fixture 零改零跳）；`git diff` 面
  = 单文件 delegate 行；既有 endpoint 锁语义断言（probe 判残留/解锁让渡）在
  McpHostTests 原法内亲证。

### T4 GUI 冲突对话框 + 只读打开路由（KD-3 前半）

- read_first 7/8 → `LibraryProjectController`（pendingConflict/openProjectReadOnly/
  isReadOnly/flushForTermination）+ LightamerApp 三路由 sheet + terminate 腿。
- 验收：`ProjectReadOnlyFaceTests` 前半（6 法）——typed 冲突→pendingConflict
  投影（含 legacy 冲突面同法断言：SessionCoordinator 冲突经
  `sessionLockConflictHandler` → toast——m3a 并档 + omp 回注勘误，计数不变）/
  三选腿各一（只读=store.readOnlyMode、
  重试=五态③窗口后获写、取消=不开）/
  flushForTermination 有界面（锁释放断言）；runModal 零命中自证。

### T5 GUI 只读态 seam + banner + 禁用投影（KD-3 后半）

- read_first 8/9 → `EditorState.projectReadOnlyGate` + commit* 家族 guard +
  `ExportState` enqueue guard + `WorkspaceHostView` banner/toast/`.disabled`
  投影 + 装配点接线（LightamerApp）。
- 验收：`ProjectReadOnlyFaceTests` 后半（**12 法**）——三 seam 负测 + banner AX +
  同源布尔投影 + 禁用清单机检表（DECISIONS，接线点逐项标注）**+ history 导航/
  版本/paste 四法（omp 计划复审回注 2026-10-13，E-OMP-1 (e)：undo no-op 不翻栈 /
  版本命令族拒 / 单图 paste 拒 / batch 入口拒——落位设计见 KD-3 历史导航/版本/
  paste 落位段）**；**只读 walkthrough 断言面**：gate 关时写入口全集（commit* +
  performUndo/performRedo/performJump + install*）全 no-op 不崩。

### T6 无头 `--project` 仲裁 + connect 指引（KD-4）

- read_first 3/10 → `McpServerController` 装配参数解析 + 两臂 + 指引发射 +
  通道分叉常量 + DEBUG fixture + stdio EOF 优雅腿。
- 验收：`McpProjectArbitrationTests`（APP，9 法）——门 2/门 3 全清单（双序 +
  确定性双跑 + stdio stdout 零污染负测 + 降级指引变体 + 无 `--project` 零回归
  冒烟）。App bundle 跑前删孤儿 .lra。

### T7 MCP 写类 probe seam + typed projectReadOnly（KD-5）

- read_first 4/5 → `McpToolRegistry` additive case + `EditingToolset.Seams`/
  `McpCullingContext` probe seam + 五调用点落位（live 先判序）+ 宿主装配点
  （GUI 内嵌 + headless 两臂）probe 闭包（自持豁免；legacy face 判据源切换照
  KD-5 m2 回注——session.lock 自持态）。
- 验收：`McpProjectReadOnlyErrorTests`（APP，8 法）——门 5 全清单；快照族
  原样绿；additive 影响申报（DECISIONS）。

### T8 o-2 ColormatchResolverBox 收窄（KD-6）

- read_first 9/10 → NSLock holder + 三写点 replaceShared + 读点局部化。
- 验收：`ColormatchResolverBoxTests`（IOP，4 法）——getter/replaceShared 语义 +
  forward 读局部化 + nil 降级不变；MatchColor 既有测试族原样绿（零 diff 门）。

### T9 红线自证 + 走查配方（T4/T5 实机面）

- read_first 11 → `.work/gui-acceptance/m6-1/MANIFEST.md`（GUI 只读面走查配方：
  `open -n` 双实例撞锁对话框三选 / banner 常驻 / 禁用清单逐项 / 浏览检索可用 /
  headless connect 指引终端目测——Manual-Only 行显式标注 + 机检行自证：
  runModal 零命中 / Schema 零 diff / dependencies 零 diff / 快照族零 diff）。
- 验收：MANIFEST 在盘；机检行全绿截屏入 SUMMARY；zh-audit `--check` 对 10 新键
  全入册 PASS（含 legacy `session_lock_held`——omp 回注 M-OMP-1 补登记）。

### T10 收口

- SUMMARY（任务序/bundle 分账/对账链）+ DECISIONS（KD 偏差/禁用清单表（接线点
  逐项标注 + 导入兜底孤儿副作用注记——omp E-OMP-1）/快照族申报/legacy 边界
  （含 m2 legacy probe 判据源接线登记）/移动窗口注记）+
  GOAL-STATE 续接点 + TODO 同批。
- 验收：定向轮 `--bundle LIB/APP/IOP` 全绿（exit 0 + 零 MEMFAIL，SC 分账对表）；
  **申请全套 `--all` 批准轮**（预期 3688/24/0 带，估带 3683..3693——E1 + omp
  E-OMP-1 回注修正值）；**双重验收（config
  `dual_acceptance = true`，m1）**：zcode subagent 独立验收 PASS 后 → **串行**
  omp 二次验收（严禁并发——computer-use 单实例）；两路结论落
  `M6-1-01-ACCEPTANCE.md`；FAIL 回注修复批后重走验收。

## 验收标准（AC 总表）

1. **OQ 生效值①（锁粒度）**：`<stem>.lalb.lock` sibling + legacy
   `<root>/.lightamer/session.lock` 同件在册；payload v1 冻结拼写（round-trip
   负测钉死）；`LibrarySchema`/`project_meta`/备份/移动零触碰（门 1 + 红线自证）。
   【T1/T2/T9】
2. **OQ 生效值②（对称只读回退）**：GUI 撞锁 = 三选对话框（只读打开/重试/取消
   zh verbatim）；无头撞锁 = 只读 + 指引；**双向启动序确定性门**（序 A/序 B 各
   双跑逐位一致）+ 双实例/跨角色全组合经同一锁文件（门 2/门 4）。【T4/T6】
3. **OQ 生效值③（无头撞锁后行为）**：只读 server 常驻 + 机读指引 JSON
   （event/endpoint/holderPid schema 逐键断言）+ HTTP=stdout / STDIO=stderr 分叉
   （stdout 零污染负测）+ 端点缺席降级指引（门 2/门 3）；无立即退出臂、无转发
   代理（负测：只读臂进程存活 + serve）。【T6】
4. **OQ 生效值④（GUI 最小只读面）**：banner 常驻 + toast 一次性 + 禁用清单逐项
   （DECISIONS 机检表（接线点逐项标注）+ AX 断言 + MANIFEST 走查；含 history
   导航/版本命令族/paste 接线点——omp E-OMP-1）+ 浏览/检索/查看/备份可用 +
   重试臂持锁者退出后可升级。【T5/T9/门 4】
5. **OQ 生效值⑤（检查时机与错误面）**：启动 + 每写类调用前 probe（非持有式、
   自持豁免）；`projectReadOnly` additive 一枚（文案携 pid + connect 指引语）；
   `imageLiveInEditor` 保留且先判（序负测）；`serverReadOnly` 旧语义零改；
   读类工具照常（门 5）。【T7】
6. **OQ 生效值⑥（o-2 搭车）**：`ColormatchResolverBox` NSLock holder 在册
   （LutLibraryStore 体例镜像）+ 三写点 replaceShared + MatchColor 既有族零 diff
   全绿。【T8】
7. **零回归门**：McpHostTests 原样全绿（宿主锁零 diff）；20 工具封闭集快照族零
   diff；G4 parity 零触；`Project.swift` dependencies 零 diff；QuickLook appex
   零触碰；无 `--project` 无头路径行为逐字节不变（冒烟负测）。【T3/T7/T9】
8. **SC 数字门**：LIB 654/4/0 + APP 792/4/0 + IOP 688/1/0 定向对表；全套
   预期 3683..3693/24/0（批准轮对账，基线 3631/24/0 亲核记录在 plan 头；
   数字 = E1 + omp E-OMP-1 回注修正——六新文件 57 法，APP +35）。【T10】

## 风险与边界

- **flock 同进程假阴性**：probe 自持豁免闭包（KD-5）漏接 = writer 臂自拒——T7
  负测一条钉死（writer 臂写类调用必须成功）。
- **双实例走查环境**：`open -n` 双 GUI 实例 + UserDefaults 共享（embedded MCP
  host 双开抢 endpoint 锁 = 既有只读降级语义，正交不干扰项目锁演示）；MANIFEST
  配方显式写明。
- **payload 陈旧 pid**：acquire 与 payload write 之间崩溃 → 展示层 pid 过时
  （flock 仍精确）——文案回落「pid 未知」负测在门 1。
- **headless `--project` 打开即迁移**：旧 schema 包在无头臂触发 pre-migrate 快照
  ——与 GUI 打开同语义（写权属持锁者），DECISIONS 注记。
- **快照族 additive 影响**：错误码枚举快照若含（McpRegistrySnapshotTests:291
  catch 面）→ 据实申报快照更新（工具清单零 diff 不变——D-M6-1-6 申报义务）。
- **APP bundle 贴线**：IOP/IOPParity 本批零触碰（预期零漂移）；APP 峰值 2832MB
  基线 + 双进程子进程开销 ≪ 8G 门。
- **legacy 边界**：legacy 只读回退面不在本 plan（KD-2 显式边界 + M6-5 挂账）。

## 提交约定

- T1 `feat(core): single-writer lock generalization with payload`
- T2 `feat(core): project-level single-writer lock for lalb packages`
- T3 `refactor(app): mcp endpoint lock delegates the core single-writer lock`
- T4 `feat(app): project open conflict dialog with read-only fallback`
- T5 `feat(app): read-only editor face with banner and write guards`
- T6 `feat(app): headless project arbitration with connect guidance`
- T7 `feat(app): typed projectReadOnly rejection on the mcp write face`
- T8 `fix(iop): narrow colormatch resolver box behind an nslock holder`
- T9 `test(app): add m6-1 walkthrough manifest and red-line self-checks`
- T10 `docs(m6-1): close single-writer lock batch with decisions and ledger`
- 全英文 Conventional Commits；不 push。
