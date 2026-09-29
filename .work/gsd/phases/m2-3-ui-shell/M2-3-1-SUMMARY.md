# M2-3-1 SUMMARY — UI 壳骨架（tokens + 双工作区路由 + 集合态/缩略图桥 + 左竖胶片条 + 菜单 IA + 后台任务协议）

> Plan M2-3-1 收口（2026-09-29）。执行 = ZCode subagent worker；7 任务 6 代码提交 + 本收口提交，未 push。
> 裁决正本 = `M2-3-CONTEXT.md`（D-M2-3-CONTEXT-1..12 + E1 勘误 + checker 回注 m1..m9）；plan = checker 修正版 `897bcb2`。
> 边界开关：每任务边界查 `.work/config.toml [gsd]`，全程 `paused=false / auto=true`（用户指令连跑）。

## 提交账

| 任务 | Commit | 内容 |
|---|---|---|
| T1 | `609662f` | ThemeTokens 暗色玻璃七族单一来源（数值自写、D1 禁拷；裸 hex 豁免地）+ ThemeTokensTests 7 |
| T2 | `2329d74` | WorkspaceModel AppPhase 双态保留 + WorkspaceHostView 壳根（折叠过渡 + marker + focused 桥）+ EditorWorkspaceShellView 四区骨架 + ContentView gate=false 内层换 Host（legacyBody 零触碰）+ WorkspaceRoutingTests 8 |
| T3 | `909ef3e` | LibraryGridModel 集合态单源（keyset 两段游标 + 重置 + 选择状态机）+ LibraryThumbnailBridge 双档桥（盘缓存 mtime 新鲜度 + 确定性 LRU + 并发闸 + in-flight 合并 + prioritize）+ 21 测试 |
| T4 | `c659ae7` | FilmstripView 左竖向 List 虚拟化 + FilmstripModel 窗口化（可见窗 ±4 prefetch、暖集、滚动锚）+ FilmstripModelTests 6（万行窗口化计数断言 + BENCH\| 行） |
| T5 | `c0a26e5` | MenuCommandSet 纯函数（gate × phase → 命令 id 集）+ LightamerApp 消费（Session 四死路由 gate 包裹、⌘E/⌘W/⌘F 回路、View 三 toggle 占位）+ 矩阵测试 +3（早写入 T2 提交所携文件，见偏差 D5） |
| T6 | `56e582e` | BackgroundTaskHosting 协议 + registry + ImportTaskAdapter 只读订阅（checker E3：controller 零改动）+ BackgroundTaskBarView 底部栏/对话框双呈现同源 + Host 挂接 + BackgroundTaskRegistryTests 9 |
| T7 | 本提交 | SUMMARY / DECISIONS / GOAL-STATE 续接点 / LESSONS L041（docs-only，零代码） |

## 测试终值

**全套 2103 / 13 skip / 0 fail**（终轮 R2，Debug，`Scripts/test-direct.sh`，718.0s）。

- 基线 2049（M2-2-4 终态）+ 新增 **54** = 2103：ThemeTokensTests 7 + WorkspaceRoutingTests 11 +
  LibraryGridModelTests 11 + LibraryThumbnailBridgeTests 10 + FilmstripModelTests 6 +
  BackgroundTaskRegistryTests 9。
- skip 13 = 既有基线原样（LibraryBenchmarkHarness 2 + 既有 11），**零新 skip**。
- 任务轮全套记录：T1 轮 **2056/13/0**（786.6s）→ T2+T3 轮 **2085/13/0**（732.7s）→ 终轮 R1 挂 1 条
  `LibraryThumbnailBridgeTests.testPrioritizeReordersQueuedProductions`（**测试设计竞态，非产品缺陷**：
  wall-clock sleep 假设 B/C 在 60ms 内入队，满载轮下 actor hop 超时——根治 = 桥加
  `queuedCountForTesting()` 观测面 + 测试改确定性轮询，隔离复跑 ×3 全绿）→ 终轮 R2 **2103/13/0**
  （718.0s，干净轮）。
- 既有域回归锁零改动全绿：LibraryLegacyGateTests（11）零 diff 全绿；LibraryQueriesTests /
  ExifSearchParserTests 等 Library 域既有测试全绿（全套 0 fail 覆盖）。

## AC 总表（11/11 全绿）

| # | AC | 机检证据 | 状态 |
|---|---|---|---|
| 1 | ThemeTokens 七族在册 + 亮暗序；新壳裸 hex 仅 tokens 命中 | ThemeTokensTests 7 全绿（Family.allCases 恰七键 + Rec.709 luma 序 windowBackground < cardSurface < textPrimary + 材质半透明挂点断言）；`git grep -nE '(#|0x)[0-9A-Fa-f]{6}' -- UI/Shell UI/Theme/ThemeTokens.swift Library` → **仅 ThemeTokens.swift 命中**（legacy LightamerColors.swift 不在新壳机检域，KD-1 冻结并存） | ✅ |
| 2 | 双态路由往返无损逐字段；穷举 switch 零 default | WorkspaceRoutingTests：filter group 规则/plan 三段/sort/selectedIDs/pageAnchor(keyValue+imagePath)/scrollPosition(anchor+rowOffset)/inspectorSelection 逐字段断言 + 结构体整体相等；编译穷举证明 helper + `case .editor/.library` 双 switch 点在册，Shell 目录 `default` 臂 grep 零命中 | ✅ |
| 3 | gate=false = WorkspaceHostView（marker）；gate=true = legacyBody 原样；LibraryLegacyGateTests 零改动全绿 | `shell.workspace.host` + `library.project.workspace` marker 断言（ThemeTokens.Markers 单源）；`visibleContentFaceMarkers` 两 gate 集合冻结重钉 + 不相交；`git diff 897bcb2 -- ContentView.swift` legacyBody 相关行 **0**；LibraryLegacyGateTests 文件零 diff、全套绿 | ✅ |
| 4 | keyset 分页不重不漏 + NULL 封底 + filter 重置 + 五键白名单 | LibraryGridModelTests 11：12 行 fixture limit=3 全走查恰一次；captureDate NULL 行尾段恰一次且键序正确；filter 变更重置后新走查 7 行零泄漏零重复；sort DESC 重取首行正确；scanEpoch 透传 typed constraintViolation；选择状态机 6 面（单选替换/toggle/set 钳制/openCurrent 选中/clear/重取存活） | ✅ |
| 5 | 桥双档裁决 + 盘缓存命中零重产 + LRU + 并发 ≤4 + in-flight 合并 | LibraryThumbnailBridgeTests 10：tier A 零触渲染腿 / tier B 走腿 / 无腿 miss；盘缓存 `.lathumbs` 落件 + 跨实例命中 productionCount=0 + mtime 陈旧重产 + 命中后零再产；LRU 顺序逐断言（容量 2：插 C 驱逐 A、access B 刷新近用序）；fan-out 8 请求 maxActive ≤2；同 id 6 并发合并 productionCount=1；cancelAll 弃单重产；prioritize 确定性轮询后跳队 | ✅ |
| 6 | 竖向 List 虚拟化；万行挂载窗外零请求；选中滚动锚 | FilmstripModelTests 6：10,000 行真 .lalb 挂载 12 可见行 → **恰 16 请求**（窗 ±4 prefetch）且与窗外 9,984 行 id 不相交；跳窗 5000 只取新窗 20；暖 id 不重发；锚随 select；空集合零请求；双边缘钳制。**BENCH\|**（非门）：`filmstrip 10k-row mount: 36 requests for two windows (12 visible + 4 prefetch each), model-level simulation 2.4ms`。真机 60fps 滚动 + List→桥真接线兜底 = P4 T2 清单①（E4 接账） | ✅ |
| 7 | MenuCommandSet 矩阵（gate × phase 全组合）；Session 四死路由 gate=false 移除/gate=true 原样 | WorkspaceRoutingTests 矩阵：4 组合 × 每 MenuCommandID 逐 id 断言（gateOn == sessionRoutes 精确集、gateOff == newShellRoutes 精确集）；双注册表不相交且并集 == 全集；id 拼写钉死。**逐 hunk 评审（m7）**：`git diff <P1起点>..HEAD -- LightamerApp.swift` 空白归一后逐行比对——**26 行删除全部原语句重现于 gate 包裹内（仅缩进 +4），唯一例外 = T6 overlay 的 gate 条件并入一行**（`if legacyLibraryEnabled, let progress = …`，ImportProgressView body 语句零改动）；gate=true 菜单树语句字节不变 | ✅ |
| 8 | BackgroundTaskHosting 协议 + registry 四态 + 导入腿单调快照 + 取消 + 双呈现同源；controller/dialog/progress 零 diff | BackgroundTaskRegistryTests 9：register/update/finish/cancel/cancelAll + 插入序穿中间完成 + 重复注册拒绝；adapter 单调钳制（重放 12/100 不回退、restart 形 total 重置不回退、failed/duplicates 文案、completed=1.0、cancelled 保底）；cancel 透传 spy + controller 路由默认空闲 no-op；双呈现 `BackgroundTaskProjection.descriptors` 同函数同行集。`git diff 897bcb2 -- LibraryProjectController.swift ImportModeDialog.swift ImportProgressView.swift` = **空** | ✅ |
| 9 | 新 UI 全量 String(localized:)、零裸 Text(" 字面漂移 | `git grep -n 'Text("' -- UI/Shell Library` 白名单外命中 **0**（动态串走 String 重载、M2-2 沿用面 verbatim）；新键 19 个 `String(localized:defaultValue:)`（shell_*/filmstrip_*/tasks_*/menu_view_tool_rail 族），zh 值按 D9 滞后 P4 补录 | ✅ |
| 10 | 全套回归 0 fail，计数 ≈ 2049 + 25..35 | 终轮 **2103/13/0**；0 fail。计数偏差：+54 > plan 预估 +25..35（见偏差 D6） | ✅ |
| 11 | diff 边界 == 申报文件集；LightamerCore 零 diff；legacyBody 树资产零 diff | `git diff --name-only 897bcb2..HEAD` = **恰 19 代码文件**（13 App + 6 Tests，= front-matter 申报集全量）；`git diff --name-only … -- LightamerCore/` = 空；SidebarView/SessionBrowserView/CullingView/FilterBarView/CatalogBrowser*/SettingsView/LibraryProjectController/ImportModeDialog/ImportProgressView/LibraryLegacyGateTests 全部零 diff | ✅ |

## KD 执行确认（KD-1..7 全按 plan 落地）

- **KD-1**：七族全量（cardSurface/cardBorder/windowBackground/textPrimary/textSecondary/accent/selectedRing/busyDim），数值自写（0x0B0D11/0x171B22@0.80/0x93A7C4@0.18/0xE7EAF0/0x9AA3B2/0x5E9BFF/0x9CC2FF@0.90/0x000000@0.45，理由见 DECISIONS D1）；与 legacy LightamerColors 零交叉。
- **KD-2**：AppPhase 枚举 + LibraryPhaseState（filter/sort/selectedIDs/pageAnchor/scrollPosition/inspectorSelection 六字段）+ EditorPhaseState（currentImageID/filmstripScrollAnchor）；openEditor 快照式保留 / closeEditor 恢复；isSearchDialogPresented P1 预埋（m6）。
- **KD-3**：GridModel 壳零 SQL（searchPage/searchNullTail/LibraryPageAnchor 逐签名消费）；排序白名单不重复实现（scanEpoch 透传 typed 拒绝实测）。
- **KD-4**：档 A = `SessionThumbnailProvider.embeddedPreview`（public nonisolated static 直用）；档 B = 注入式 renderLeg 缝（生产腿 P2 网格接线时挂，DECISIONS D3）；盘缓存键 = `String(imageID)`；并发 ≤4 + 合并 + prioritize 全实现。Core 零改动。
- **KD-5**：List 竖向虚拟化 + 固定行高 64 + prefetchSpan 4 + onAppear/onDisappear → prioritize/cancel 接线；`filmstrip.list`/`filmstrip.row.<id>` marker；零集合态复制。左轨竖向 = 用户修订布局（非 Alcedo 底部）。
- **KD-6**：MenuCommandSet 纯函数 + LightamerApp 单点消费；Session 四死路由 gate 包裹（gate=true 字节不变）；⌘E/⌘W/⌘F + View 三 toggle；撞键（⌘N/⌘O/⌘⇧I）gate=false 下归新命令、gate=true 原样。
- **KD-7**：协议一次成型（id/title/snapshot get+set/cancel；@MainActor 隔离，DECISIONS D2）；registry register/update/finish/cancel/cancelAll；导入腿首实现，controller 零改动（checker E3 兑现），导出/AI 腿零预留字段。

## 性能观察项（登记，不走查——P4 T2「交互/性能观察清单」接收）

1. **万行胶片条滚动 60fps 目测 + List→桥真接线兜底核验**（清单①，E4 接账）——本 plan 落模型级窗口化计数断言 + BENCH| 行：`10k-row mount: 36 requests / two windows, 2.4ms`；真机滚动帧率 P4 走查。
2. **菜单撞键真实按键走查**（清单②，E4 接账）——⌘N/⌘O/⌘W/⌘E/⌘F 的 gate=false 新绑定与 gate=true 原样的真实按键路由，P4 走查。
3. 档 B 缩略图首渲产能（has_edits 大图管线渲一档）——P2 网格接线后与 M2-2-3 挂账「缩略图首屏」并案量测。

## 偏差与说明（详版 DECISIONS）

1. **D1 tokens 数值/形态**：rgba(UInt32, alpha:) 助手（`#RRGGBB` 语义以 0x 字面承载）——AC#1 机检 grep 扩为 `(#|0x)[0-9A-Fa-f]{6}` 双拼写覆盖；机检域按 KD-1 意图 = 新壳文件全集 + tokens 豁免地（legacy LightamerColors 冻结并存不入域）。
2. **D2 协议 @MainActor 隔离**：KD-7 草图 `Sendable` → `@MainActor` protocol（Sendable 由隔离蕴含）——进度快照跨线程落主 actor、registry/双呈现皆主线程态。
3. **D3 档 B 生产腿 P2 接线**：桥的 tier-B = 注入 renderLeg 缝（测试 mock 喂），生产解码腿随 P2 网格接线挂 RAWDecoder+sidecar 物化——Library 行无 Session 域索引行，缝在桥面（plan KD-4 注记一致）。
4. **D4 桥内存缓存 = 确定性显式 LRU**：KD-4 写 NSCache——NSCache 驱逐不可观测不可测，换显式 LRU（容量计 thumb 数），LRU 顺序断言可机检。
5. **D5 T5 片段随 T2 提交**：WorkspaceModel 三可见性布尔 + WorkspaceRoutingTests 矩阵测试在 T2 提交时已在工作树（早写），T2 sweep 携入——T5 提交（`c0a26e5`）持菜单面本体，commit body 注记；内容完整、每 commit 可构建（T2 轮全套即含其编译态）。
6. **D6 测试计数 +54 > 预估 +25..35**：粒度按 AC 逐条细分（桥 10/格 11），判据「0 fail + AC 机检」满足。
7. **D7 prioritize 测试竞态根治**：满载轮暴露 wall-clock sleep 假设——改确定性队列计数轮询（桥加 `queuedCountForTesting()` 观测面），隔离 ×3 绿 + 终轮全绿；非产品缺陷。
8. **D8 全套按任务域合并跑**：T1 / T2+T3 / T4-T6 各一轮全套（3 轮）替代逐任务 7 轮——同域新增文件零交叉、commit 边界逐文件精确，节时 ~50 分钟；每轮判据同 L028 双读。

## Manual-Only / 顺延

- env=1 真进程 GUI 冒烟（legacy 通道菜单字节同构目测）——沿 M2-2-4 惯例留人工。
- computer-use Alcedo 对照 = P4 统一执行（OQ-10，实机 2026-09-28 复核在位）。
- ⌘F 搜索对话框呈现、⌘E 网格双击主入口、TopBar 完整命令行 = P2 接线（缝已预埋）。
- 编辑器四区 slot 填充 = P3；zh 文案补录 = P4 对账批（OQ-9 A）。
