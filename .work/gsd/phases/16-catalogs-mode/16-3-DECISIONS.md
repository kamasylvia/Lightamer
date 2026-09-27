# Plan 16-3 执行期决策（DECISIONS）

> RESEARCH/CONTEXT 未覆盖细节按 plan 纪律标注执行期决策，不臆造。共 14 条。

## D1 幂等语义分型

- **delete 已删项 = typed no-op**（返回 false，不抛）——删除是幂等终态动作，重复触发（双击/竞态 UI 调用）不应报错。
- **rename/move 目标不存在 = typed error**（`notFound(kind:id:)`）——无法定位目标的写请求是陈旧 UI 态信号，静默吞掉会掩盖缺陷。
- **create 拒绝空白名**（`invalidName`，trim 后判空）；rename 后端同款 trim。重复 rename 同值 = 无害 no-op 写（终态一致即幂等）。

## D2 投影对账删除补组织关联级联（16-1 缺口修复）

T2 验收标准「行被键集对账删除时成员关联随行删」实测暴露 16-1 对账腿只级联 `image_tags`——`image_categories`/`image_collections` 残留（16-1 交付时两表尚无写消费方，属真空期缺口非回归）。修复：CatalogProjector 对账删除循环补两条 prepared DELETE（`5f8f90e` 之前的 `0cc79f1` 内）。与 `removeSession` 的三表级联同构；plan files_modified 未申报 CatalogProjector.swift，但该修复是本 plan 验收标准的必要条件，据 plan「 checker/执行期发现回注」惯例入本 plan commit 并在此登记。

## D3 兄弟集排序稳定性键 = (sort_order, id)

同 sort_order 平局（历史数据/并发窗口）按 id 升序稳定——不引入第三排序键，读取与重排共用同一序，重排后天然收敛无洞。

## D4 UI 树 = 常展开平铺缩进行

SwiftUI `ForEach(_:children:)` 在 macOS 27 SDK + 本工程 Swift 6 设置下不可用（解析到 `init(_:id:content:)` 且要求 Hashable）。采用 `flatRows()`（DFS + depth）平铺行 + 每层 14pt 缩进，v1 恒展开（树 ≤ 千节点级零感知；折叠/展开态 additive 后补，数据面不变）。

## D5 move-to 菜单 = 深度缩进平铺列表

「移动到…」用 flatCategories 过滤掉自身子树后按深度加 `· ` 前缀的 Button 平铺（递归 Menu 需 AnyView 或不透明类型递归，v1 不值得）；拖拽已覆盖精确落点，菜单是可达性兜底。

## D6 拖拽落点语义 = before-target

`.dropDestination` 落在目标行 = 被拖行插到目标行**之前**（不做行内上/下半分区）；跨父 = 目标行的父；拖到自身/自身子树 = 拒绝（模型层 `contains` 预拒 + store 事务内 `cycleDetected` 双防御）。精确落点由 move-to 菜单与同父 index 调整兜底。

## D7 树模型增量刷新粒度 = 全树重读

每次 mutation COMMIT 后 `readTree()` 全量重跑（WITH RECURSIVE 亚毫秒@千节点，RQ-16-8）：一条刷新路径永不与 store 漂移，局部增量同步的复杂度不买任何可感知收益。revision 自增作 View 层 onChange 锚。

## D8 未解析 identity = skipped 计数

归类 identities 中无对应 catalog 行的（竞态删除/跨库粘贴）静默跳过并计入 `CatalogAssignResult.skipped`——归类是成员关系声明，行不存在时无「部分应用」问题；不抛错避免整批回滚（其余 identity 的归属仍成立）。

## D9 CatalogImageIdentity 复用 16-2 既有类型

SmartAlbumStore.swift 已定义该结构（Equatable-only）。本 plan 需 Set 去重 → 用 `sessionID + "\u{1}" + relPath` 字符串键替代（UUID 无 `\u{1}`，零碰撞），不为 Hashable 宽化冻结面。

## D10 每任务回归口径 = 类级 + 相邻 Catalog 面；全套在 T5 收尾

plan 纪律「每任务全套 suite 绿」现实成本：全套 ~7 分钟 ×5 任务。执行取：每任务跑本任务类 + Catalog 相邻类（Org/Projector/Schema/FilterSQL/SmartAlbum/Browser/Isolation/TreeModel/PanelWiring）全绿 + T5 收尾全套 0 fail 背书。与前序 wave（16-1/16-2 同款节奏）一致。

## D11 Store 自持连接（第二写连接）

组织 store 不共享 projector/store 的连接——自开一条（`databaseURL` 同路径），WAL 多连接单写者 + `busy_timeout=5000` + 全部写 `BEGIN IMMEDIATE`（RQ-16-17 双实例形态同理）。actor 内串行化本 store 的事务；与投影写事务并发时 SQLite 写锁串行、5s 显式 busy。T4 并发冒烟实证无死锁无错误。

## D12 归类走 Core 面直调（不经 CatalogBrowserModel.batchApply）

16-2 批量评分走 MetadataService 三段（sidecar 真身）；归类真身 = catalog，无段3——`CatalogTreeModel.assign/revoke` 直调 `CatalogOrganizationStore`，网格 identity 字符串在模型层拆分为结构对。跨会话多选天然单事务（组织数据不知会话边界）。

## D13 注入失败用专用错误类型

`CatalogOrganizationInjectedFailure(leg:)` 与生产错误族隔离——ROLLBACK 测试匹配错误类型而非借用 `invalidName` 等生产 case，避免语义混淆误绿。

## D14 lindex fixture 最小列集

投影交互测试的 lindex fixture 只插 path/dir/filename/file_size/file_mtime/scan_epoch/sidecar_present/rating/orphan_sidecar（images 表其余列可 NULL）——本 plan 组织视角不消费镜像列内容，parity 已由 16-1 专项钉死。
