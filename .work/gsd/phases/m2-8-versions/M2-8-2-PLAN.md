---
phase: m2-8
plan: "M2-8-2"
title: "面板与交互（wave 2）——Versions 面板兑现 tool rail 占位（列表 + 新建/Branch/Rename/Remove + 单击切换 + active 徽标 + 空态引导，D-M2-8-CONTEXT-6）+ 历史行升级可点跳 + 类型图标（undo 四条验收固化 + 500 链重载，OQ-8）+ Copy Adjustments 三 pane 对话框（isAdjustmentTransferable 排除单函数 + OVERWRITE-paste epoch 复用落新版本 + 蒙版 contentRevision 重置，OQ-7）+ 崩溃哨兵 toast（OQ-9 最小恢复面）"
wave: 2
depends_on: ["M2-8-1"]
autonomous: true
requirements: [M2VER-02, M2VER-04, M2VER-05]
files_modified:
  - LightamerCore/Sources/Layers/LayerStackProjection.swift  # 新建：HistoryStack → LayerStack 投影纯函数（rebuild(history:baseLayer:) —— EditorState.rebuildLayerStack 既有规则原样抽取：结构槽 snapshot + in-scope param 重放 + paste-epoch/drtDocument 排除；EditorState 改委托，零行为 diff）
  - App/Sources/Lightamer/State/EditorState.swift            # 修改（半径 = 一函数体）：rebuildLayerStack() 委托 LayerStackProjection.rebuild（单路径单源化——transfer 源链枚举共用）
  - App/Sources/Lightamer/State/VersionCoordinator.swift     # 修改：pasteChain(records:layerSnapshot:drtRecord:name:) 命令追加（Copy Adjustments 落版本命令——materialize-if-needed + 新槽激活 + 投影/写触发同款）
  - App/Sources/Lightamer/State/AdjustmentTransfer.swift     # 新建：AdjustmentTransferModel（源装载 = 当前图 active 链 / 外部 .lra decode；Node→Item 勾选态）+ isAdjustmentTransferable(_:) 单函数（owner == .grade——CONTEXT Specific Ideas；面板与未来批量面共用一份）
  - App/Sources/Lightamer/UI/Shell/VersionsPanelView.swift   # 新建：版本列表（name/updated_at/active 徽标）+ 头部新建/Branch 按钮 + 行 contextual menu（Rename inline/Remove 确认对话框）+ 单击切换 + 空态引导
  - App/Sources/Lightamer/UI/Shell/EditorToolRailView.swift  # 修改：versions 挂点换 VersionsPanelView（editor.versions.placeholder marker 退役，M2-4-3 nodes 先例）+ historyPanel 行升级（onTap jump + 行尾 scope 类型小图标 + AX 标签）
  - App/Sources/Lightamer/UI/Shell/AdjustmentTransferView.swift # 新建：三 pane 模态 sheet（Node→Item→Version 序）+ 源选择段（当前图版本 / 外部 .lra…）+ Paste/取消
  - App/Sources/Lightamer/UI/Shell/MenuCommandSet.swift      # 修改：edit.copyAdjustments 命令 ID + editor 路由集追加
  - App/Sources/Lightamer/UI/LightamerApp.swift              # 修改：菜单命令处理 + AdjustmentTransferView sheet 挂载 + 哨兵接线（launch 检出一次性 toast / terminate flush 后清位）
  - App/Sources/Lightamer/State/CleanTerminateSentinel.swift # 新建：哨兵纯函数 + UserDefaults 键常量（app.cleanTerminate；L036 组装根读一次注入）
  - Project.swift                                            # 修改：新测试文件登记（checker E2）
  - Tests/LightamerTests/VersionsPanelTests.swift            # 新建（APP——真 EditorState + VersionCoordinator 链）：四操作 UI 状态面 + 空态/徽标/确认对话框语义
  - Tests/LightamerTests/HistoryRowJumpTests.swift           # 新建（APP）：行点击 jump 保尾/编辑丢尾/⌘Z 同源/500 链 .lra 重载字节忠实
  - Tests/LightamerTests/AdjustmentTransferTests.swift       # 新建（APP + LayerStackProjection Core 面）：排除面枚举完整性 + 源链枚举 + pasteChain 落版本 + 蒙版重置
  - Tests/LightamerTests/CleanTerminateSentinelTests.swift   # 新建（APP）：哨兵纯函数真值表 + 注入 defaults round-trip
  - .work/gsd/phases/m2-4-0-test-bundles/M2-4-0-BUNDLE-MAP.txt # 修改（checker E2）：四新测试文件登记行 + 增行记录注
  - .work/gsd/phases/m2-8-versions/M2-8-2-SUMMARY.md         # 新建（收口任务）
  - .work/gsd/phases/m2-8-versions/M2-8-2-DECISIONS.md       # 新建（收口任务）
  - .work/GOAL-STATE.md                                      # 续接点追加（收口任务）
  - .work/LESSONS.md                                         # 如踩坑
---

# Plan M2-8-2 — 面板与交互（Versions 面板 + 历史行升级 + Copy Adjustments + 崩溃哨兵）

> **性质**：UI/交互 plan——P1 模型核之上的全部用户可见面。四块交付：①**Versions 面板**
> 兑现 tool rail `.versions` 占位（OQ-6-A 字面：列表 + 新建/Branch + Rename/Remove +
> 单击切换；占位 marker 退役沿 M2-4-3 nodes 先例）；②**历史行升级**（行可点
> `jump(to:)` + scope 类型小图标；undo 语义 = 验收固化非开发——CONTEXT 发现 1；
> 参数 delta = Deferred，M2VER-04「参数 delta」字面部分收窄）；③**Copy Adjustments
> 三 pane 对话框**（M2VER-05：Node→Item→Version 勾选 → Paste 落目标图**新版本**；
> 排除面按 owner 单函数判定；Paste 复用 OVERWRITE-paste epoch 机制 = 零新投影语义）；
> ④**崩溃哨兵**（OQ-9-A 最小恢复面：terminate 置位/launch 检出 → 一次性 toast）。
> 规格锚点 = D-M2-8-CONTEXT-5..9（已裁决，不得重开）+ Feature-map §1.3/§6.3 +
> REQUIREMENTS M2VER-02/04/05。
>
> **执行期悬决销账**：蒙版 contentRevision 拷贝重置规则（KD-3）；跨图源选择器形态
> （KD-4——v1 = 当前图版本 + 外部 .lra 文件入口，库内选择器 Deferred 登记晨审追认）。

## 已定裁决（不得重开）

- **D-M2-8-CONTEXT-6（OQ-6 A）**：tool rail 面板 = 版本列表（name/updated_at/active
  徽标）+ 新建/Branch 头部按钮 + 行 contextual menu（Rename inline/Remove 确认）+
  单击行切换；空态 = 占位文案升级为引导文案；commit 图可视化不做；marker 退役。
- **D-M2-8-CONTEXT-7（OQ-7 A）**：复制面按 owner 收窄——`.grade` chain 实例 +
  document-level `drtRecord`；排除面 = `.develop` 全域（rawOverrides/geometry 五件/
  yiyin 三件/M2-1 disabled 六）+ terminal trio + base 链 develop-owned 兼容实例 +
  `.drtPost` 四件（随尾段，不随复制走——DECISIONS 签注）；跨图默认场景、同图退化路径；
  蒙版记录随 Grade 值拷贝走。
- **D-M2-8-CONTEXT-8（OQ-8 A）**：undo 语义零改动（验收固化四条：跳回 redo 尾保留/
  跳回后编辑丢尾/⌘Z·⇧⌘Z 与面板按钮同源/.lra 重载字节忠实）+ 历史行可点跳 + 类型图标；
  **参数 delta 文本 = Deferred**（per-op 摘要设施挂账，CONTEXT Deferred Ideas）。
- **D-M2-8-CONTEXT-9（OQ-9 A）**：自动保存 = 既有 2s debounce + tmp 原子晋升 + flushNow
  （零新代码，P1 版本动作触发已补）；恢复条 v1 = **双向哨兵**（terminate 置位/launch
  清位检出 → 一次性 toast）；不建 journal、不做逐图恢复条。
- **M2VER-04 字面**：「历史=版本内线性事务流」= P1 swap 语义 + 本 plan 行升级；
  「每行操作名+参数 delta+时间」delta 半边收窄（OQ-8-A）；「崩溃恢复条」= 哨兵 toast
  最小面兑现。

## 关键设计决策（planner 裁决，执行中不重开）

### KD-1 Versions 面板 = 占位退役 + 四操作 + 空态引导

- **挂点**：`EditorToolRailView.panel(.versions)` 换 `VersionsPanelView`（独立文件，
  `EditorNodesPanelView` 同款先例）；`editor.versions.placeholder` marker 退役（枚举
  `EditorRailPlaceholder` 结构保留——nodes 退役先例「枚举保留 case 换渲染臂」同款）；
  新 marker = `editor.versions.panel`（行 `editor.versions.row.<uuid>`、按钮
  `editor.versions.new` / `.branch` / `.rename.<uuid>` / `.remove.<uuid>`）。
- **列表行**：name（caption）+ updated_at（caption2，date 惯例同历史行）+ active 徽标
  （`activeVersionID` 匹配；隐式单版本态无徽标——P1 KD-2 隐式语义）。
- **四操作**：头部「新建」（`createFromScratch`）+「自当前分支新建」（`branchFromCurrent`）；
  行 contextual menu「重新命名」（inline TextField，commit = `rename`）+「移除…」
  （`confirmationDialog` → `remove`——确认对话框 P1 纪律预留的本任务兑现）。单击行 =
  `switch(to:)`。
- **空态引导**（slots 空即隐式单版本）：文案 = 「为这张照片创建多个 look——每个版本
  保留独立的完整编辑历史」+ 新建/Branch 两按钮保留（引导即操作）。zh 键随手落
  （`versions_panel_*` 族，M2-8-3 zh-audit 对账）。
- **默认名**：`String(localized:)` 格式键「版本 N」/「Version N」（`versions_default_`
  族——L025 语言标签 zh 纪律）；P1 KD-2 的 name 生成挪到面板侧传参（coordinator 命令
  接受 name 参数，默认名生成归 UI 层——zh 不漏 Core）。

### KD-2 历史行升级：可点跳 + 类型图标 + undo 验收固化 + 500 链脚本

- **行点击**：现有 List 行加 onTap → `pipeCoordinator.jumpToHistory(原始索引)`（行序
  倒序显示，索引换算在视图层；jump 面现成 `:1524`）。选中态视觉 = position 对应行高亮
  （`editorState.history.position` 派生，禁新增状态源）。
- **类型图标**（行尾 caption2 小图标，scope 标记族现成判定）：`layerScope == nil` 无
  图标（全局参数）；`EditorStructureScope.marker` = `square.on.square`（结构）；`pasteEpochScope`
  = `doc.on.doc`（粘贴）；`drtDocumentScope` = `circle.lefthalf.filled`（DRT）。AX 标签
  四键（`history_row_kind_*`）。穷举 switch 无 default——`layerScope` 是 `String?`，
  直 switch 必带 default、无编译期强制；实现先把 scope 标记族映射为闭集 enum
  （nil/结构/粘贴/DRT 四 case）再穷举 switch（checker M2：映射 enum 才能编译期强制——
  新 scope 标记在映射处强制应答）。
- **undo 四条验收固化**（CONTEXT 发现 1——已实现行为，测试立此存照）：
  ①jump 到早期 → `canRedo == true`（redo 尾保留）；②jump 后 commit → 尾截断
  （`canRedo == false` + items 收缩）；③面板按钮与 ⌘Z/⇧⌘Z 同一 coordinator 面共同
  （menu binding 面 `performUndo/performRedo`——断言两入口后状态一致）；④500 条链
  .lra 写→重载→items/position 逐字节忠实 + 全程 undo 走到 position==-1
  （**500 链验收脚本悬决销账**——程序化 commit ×500，真 EditorState 链）。
- **delta Deferred 注记**：行副标题「N params changed」降级方案**不采用**（OQ-8-A
  首选 = 纯 Deferred；降级方案仅在晨审坚持时启用，届时一行 subtitle）。

### KD-3 Copy Adjustments 复制面/排除面（枚举完整性）

```swift
// App/Sources/Lightamer/State/AdjustmentTransfer.swift
func isAdjustmentTransferable(_ instance: ModuleInstance) -> Bool {
    NodeOwnershipCatalog.owner(of: instance.opName) == .grade
}
```

- **复制面**：源侧枚举 = `LayerStackProjection.rebuild(history:baseLayer:)` 得层栈 →
  每个 Grade 节点（adjustmentLayers）= Node pane 一行（name + chain 计数）；Item pane
  = 该层 chain 中 `isAdjustmentTransferable` 的实例逐条勾选（默认全选；不可贴实例行
  灰显计数注记——排除面可视化，不静默吞）；DRT = 独立勾选行（源 `effectiveDrtRecord()`
  非 nil 才出现）。
- **排除面枚举完整性（KD 必答——风险节字面）**：测试穷举断言——develop 15 件
  （NodeOwnershipCatalog.developOpNames 全表）+ drtPost 四件 + terminal trio =
  **`colorin`/`colorout`/`gamma`（终表已实测写死——checker M1：三件均未登记 catalog
  表，`NodeOwnershipCatalog.owner` 默认臂答 .grade；opName 正本 =
  `ColorInModule.opName`/`ColorOutModule.opName`/`GammaModule.opName`）→ 谓词显式
  排除集写死此三件**，逐一 `isAdjustmentTransferable == false`；.grade 18 目录抽样
  == true。
- **蒙版随行 + contentRevision 重置（悬决销账）**：层拷贝 = `AdjustmentLayer` 值拷贝
  （mask 记录随行——Grade-owned 无外部引用，CONTEXT 发现 8）；拷贝面 mask
  `contentRevision` 重置为 nil（乐观并发守卫从头计数——新身份新纪元；DECISIONS 签注）。
- **drtRecord 值拷贝**原样（Codable struct，无 hash 字段）。
- **跨图源（悬决销账——形态裁定）**：源选择段两入口——「当前图」（active 链，同图
  退化路径）+「外部 .lra 文件…」（NSOpenPanel 单选 .lra → `LightamerSidecar` decode →
  版本列表（v7）或 active 链（v6）二级选择）。**库内图像选择器 Deferred**（随库版本
  徽标消费面一批议——晨审追认点，CONTEXT 非目标「跨图整版本复制」不受影响：本条是
  调整复制的主用例通道，功能完整成立）。

### KD-4 Paste = OVERWRITE-paste epoch 机制复用（零新投影语义）

- **落版本命令**（VersionCoordinator 新增 `pasteChain`）：materialize-if-needed →
  新槽（name = 面板传参，默认键「粘贴的调色」/「Pasted adjustments」）→ 新链两条
  item——①paste-epoch item（`pasteSet` = 勾选实例全集、`stackSnapshot` = 勾选层快照
  载荷、`snapshot` 槽 = 首记录占位、`layerScope = HistoryStack.pasteEpochScope`——
  09-04 HIST-05 OVERWRITE 形状原样）；②DRT 勾选时追加一条 `commitDrt` 形 item
  （`drtRecord` 载荷 + `drtDocumentScope` 占位快照）。新槽激活 + 投影/写触发同 P1。
- **为何零新语义**：`effectiveInstances` 的 epoch 截断 + `rebuildLayerStack` 的
  stackSnapshot 重建 + `effectiveDrtRecord` 扫描——三条投影路径**全部既有**（P1 swap
  已复用）；Copy Adjustments 的渲染/undo/持久化不引入任何新投影分支。**单 ⌘Z 语义**
  = epoch item 单条（DRT item 第二条——两步 undo，DECISIONS 签注偏离：Alcedo 单 commit
  无对应物，Lightamer 以两标准 item 组合，行为面等价）。
- **目标态边界**：目标图隐式单版本时 materialize（现有链 → 「版本 1」）再落粘贴版本；
  粘贴版本激活后用户在其上继续编辑 = 正常链操作。

### KD-5 LayerStackProjection 纯函数抽取（单路径单源化）

- **新 Core 文件** `LightamerCore/Sources/Layers/LayerStackProjection.swift`：
  `rebuild(history:baseLayer:) -> LayerStack`——`EditorState.rebuildLayerStack()`
  （`:1070-1092`）的规则**原样搬移**（结构槽 = layerStructureScope/pasteEpochScope
  最后 snapshot；in-scope param 重放排除 drtDocumentScope；baseLayer 参数化）。
  EditorState 函数体改一行委托（半径 = 一函数体，红线核 diff）。
- **双消费者**：EditorState 重建（行为零 diff——既有 Layers/App suite 全绿为证）+
  AdjustmentTransfer 源链枚举（外部 .lra 链无 EditorState 在场——抽取的动因）。
  **禁止** transfer 模型内私抄第二份投影规则（checker ④消费点单源核验：grep
  `stackSnapshot` 重放逻辑仅 Core 一处）。

### KD-6 崩溃哨兵：双向哨兵 + 注入 defaults

- **键**：`app.cleanTerminate`（UserDefaults）。**协议**：launch 组装根置 `true`
  （= running）；terminate 面在 `flushForTermination()` 有界等待返回**之后**置 `false`
  （= clean——kill 窗口内的真实未写盘留 `true`，下次 launch 正确检出）；launch 读得
  `true`（上次运行未清）→ 一次性 toast「上次会话异常退出；编辑已自动保存（至多丢失
  最后数秒）」；键缺失（首次运行）→ 静默。
- **纯函数核**（CleanTerminateSentinelTests 真值表）：
  `uncleanTermination(stored: Bool?) -> Bool` = `stored == true`（nil = 首运行 false）。
  UserDefaults 经注入隔离 suite 测试——`UserDefaults(suiteName:)`（checker M3：
  AppPreferences.swift:58 先例同款——注入 suite name，无 UserDefaultsSuite 类型；
  L036：组装根读一次显式注入，生产路径深处零直读）。
- **toast 挂点**：编辑器面首次就绪时消费一次性检出结果（presentToast 既有面）；仅
  影响 editor 打开态图（CONTEXT OQ-9-A 字面——全局单 toast，无逐图条）。

## read_first

1. `.work/gsd/phases/m2-8-versions/M2-8-CONTEXT.md`——D5..D9 + 发现 1/6/8 + Reusable
   Assets（History 面板基底/history_graph 标签族/scope 标记族行）。
2. `.work/gsd/phases/m2-8-versions/M2-8-1-PLAN.md` + 其 SUMMARY——P1 交付面
   （coordinator 命令签名/投影 sink/restore 腿）。
3. `App/Sources/Lightamer/UI/Shell/EditorToolRailView.swift`——History 面板骨架 +
   versions 占位 + EditorRailPlaceholder。
4. `App/Sources/Lightamer/State/EditorState.swift:1063-1092`——rebuildLayerStack 规则
   （KD-5 搬移正本）+ `HistoryStack.swift:342-474`（epoch/投影/effectiveDrtRecord）。
5. `App/Sources/Lightamer/State/PipeCoordinator.swift:1498-1530`——undo/redo/jump 面 +
   `MenuCommandSet.swift` 全文（命令 IA 形态）。
6. `LightamerIOP/Sources/NodeOwnershipCatalog.swift`——owner 表正本（KD-3 谓词依据）。
7. `Tests/LightamerTests/` NodesPanelModelTests/MaskGroupsPanelTests 任一——App 级真链
   测试形态先例；`Scripts/test-direct.sh` 头注。

## 纪律（强制）

1. **提交纪律**：每任务独立提交（Conventional Commits 全英文、subject ≤72 字符祈使句、
   body 写 what+why + 同批 md 清单）；只 add 本任务申报文件；**不 push**；多段 message
   用 `-F` 文件（L040）。
2. **构建纪律**：`caffeinate -dis` 包裹一切构建；**tuist generate 落在全部新文件落盘
   之后**（L041——四新源文件 + 四新测试文件分任务落盘时，各任务 commit 内对当批新文件
   generate）。
3. **测试纪律**：单测命令 = `Scripts/test-direct.sh '<Class>'`；Executed + failures
   双读（L028）。**回归基线 = M2-8-1 终态计数**（起算 2525 + P1 增量，以 BUNDLE-MAP
   行对账）；每任务全套绿；`--all` 跑前向 orchestrator 报备（报备制）；MEMFAIL ≥8G
   机检；flake ×3 归因；残留目录清盘（L049）。
4. **边界纪律**：每任务边界检查 `.work/config.toml [gsd]`（`auto`/`paused`）。
5. **架构红线**：`HistoryStack.swift`/`HistoryHash.swift`/`LightamerSidecar.swift`/
   `LibrarySchema.swift` **零 diff**（P1 已封——Core 新增仅 LayerStackProjection.swift
   一文件）；EditorState 半径 = rebuildLayerStack 委托一函数体；**视图 body 零
   UserDefaults/ProcessInfo 直读**（M2-1 D-EXEC-1 口径）；Core 不 import App；
   EditorRailPlaceholder 枚举不删；`.xmp` 永不读写删；Alcedo 参考只读（GPL 零复制）。
6. **测试登记纪律（checker E2）**：四新测试文件**同 commit** 登记 Project.swift bundle
   + BUNDLE-MAP 增行 + 增行记录注。归属：四文件全 **APP**（真链 EditorState/coordinator
   实例化；AdjustmentTransferTests 的 Core 投影面经 App 实链覆盖——若执行期拆 Core 纯
   函数直测文件，归属 **LAYERS** 并同批登记）。
7. **checker 四条（逐条对表）**：①真链验收禁绕路造假（E1）——面板/transfer AC 走真实
   EditorState + VersionCoordinator 实例链，外部源经真 .lra 文件 fixture，禁后门；
   ②登记闭环（E2）——纪律 6；③语义断言落可观测级（E4）——排除面逐 op 断言、epoch
   落版本断言到链 items 形状、哨兵到真值表 + defaults 字节；④收口边界核对（M 级）——
   T5 `git diff --stat` 逐文件对表 + 消费点单源核验（KD-5 grep）。
8. **收口核对**：T5 diff 边界 == front-matter files_modified，越界 = 违约。

## Tasks

### T1 VersionsPanelView + rail 挂点兑现

- **read_first**：上列 1/2/3。
- **action**
  1. 新建 `VersionsPanelView.swift`：KD-1 全量（列表/徽标/两头部按钮/contextual menu
     /inline rename/confirmationDialog/空态引导/默认名 UI 侧生成——coordinator 命令
     签名按需加 name 参数）。
  2. `EditorToolRailView.swift`：`.versions` 挂点换新面板；placeholder marker 退役
     （结构保留）；zh 键随手落。
  3. 新建 `Tests/LightamerTests/VersionsPanelTests.swift`（真链）：空态引导断言 →
     创建后列表行/徽标/updated_at 呈现 → rename 生效 → remove 确认流（active 删 →
     首项激活；唯一版本删 → 空态回归）→ 单击切换。UI 状态面经 coordinator + 视图
     model 断言（无 XCUITest 依赖——host 不可用走查归 M2-8-3 观察）。
  4. Project.swift/BUNDLE-MAP 登记 + `tuist generate`。
- **验收标准**
  - [ ] VersionsPanelTests 全绿（真链）；`editor.versions.placeholder` marker 零残留
        （`git grep` 零命中——渲染臂退役，枚举保留）。
  - [ ] History 面板/Nodes 面板零回归（既有 App suite 全绿）。
  - [ ] 登记闭环；全套回归 `0 fail`。

### T2 历史行升级 + undo 验收固化 + 500 链重载

- **read_first**：上列 1/4/5。
- **action**
  1. `EditorToolRailView.swift` historyPanel：KD-2 行点击 + 类型图标（穷举 switch）
     + position 高亮 + AX 四键。
  2. 新建 `Tests/LightamerTests/HistoryRowJumpTests.swift`：undo 四条固化（KD-2 ①..④，
     ④ = 500 链程序化 commit → 写 .lra → 重载逐字节 + 全程 undo）+ 行点击 → jump
     后 `effectiveInstances` 面断言 + 图标 scope 判定四态。
  3. 登记（APP）+ generate。
- **验收标准**
  - [ ] 四条固化 + jump/图标断言全绿；undo/redo 既有测试零改动全绿。
  - [ ] 500 链重载字节忠实（Executed 计数在案）；全套回归 `0 fail`。

### T3 Copy Adjustments（投影抽取 + 三 pane + pasteChain + 菜单）

- **read_first**：上列 1/2/4/6。
- **action**
  1. 新建 `LightamerCore/Sources/Layers/LayerStackProjection.swift`（KD-5）+
     `EditorState.rebuildLayerStack` 委托（一行函数体半径）。
  2. 新建 `App/Sources/Lightamer/State/AdjustmentTransfer.swift`（KD-3 模型 + 谓词）；
     `VersionCoordinator.pasteChain`（KD-4）。
  3. 新建 `AdjustmentTransferView.swift`（三 pane sheet + 源选择段 + 外部 .lra 入口 +
     灰显注记 + Paste/取消）；`MenuCommandSet.swift` + `LightamerApp.swift` 菜单命令
     + sheet 挂载。
  4. 新建 `Tests/LightamerTests/AdjustmentTransferTests.swift`：KD-3 排除面穷举
     （develop 15 + drtPost 4 + terminal 三件（KD-3 终表：colorin/colorout/gamma）
     + grade 抽样）+ 源链枚举（真 .lra
     fixture：v7 多版本源 + v6 单链源）+ pasteChain 落版本（epoch item 形状/DRT 第二
     item/蒙版 contentRevision nil/激活 + .lra 写触发）+ 目标隐式 materialize 边界。
  5. 登记 + generate。
- **验收标准**
  - [ ] 排除面穷举 + paste 链形状 + 蒙版重置断言全绿；`LayerStackProjection` 抽取零
        行为 diff（既有 Layers/App suite 零改动全绿——E4 级证据）。
  - [ ] 消费点单源核验：stackSnapshot 重放逻辑全仓仅 Core 一处（`git grep` 核）。
  - [ ] 全套回归 `0 fail`。

### T4 崩溃哨兵

- **read_first**：上列 1/5/7。
- **action**
  1. 新建 `CleanTerminateSentinel.swift`（KD-6 纯函数 + 键常量 + 注入读取壳）。
  2. `LightamerApp.swift`：launch 置位/检出 + terminate flush 后清位 + 一次性 toast
     （zh 键随手）。
  3. 新建 `Tests/LightamerTests/CleanTerminateSentinelTests.swift`：真值表四格
     （true/false/nil/缺键）+ 注入 defaults round-trip。
  4. 登记 + generate。
- **验收标准**
  - [ ] 真值表 + round-trip 全绿；**人工杀进程走查**记入 SUMMARY（kill -9 后重启 toast
        出现一次；正常退出后重启无 toast——headless 可化则程序化，不可化记待人工项）。
  - [ ] 全套回归 `0 fail`。

### T5 收口——SUMMARY/DECISIONS + 续接点

- **read_first**：本 plan AC 表 + `.work/GOAL-STATE.md` 续接点节。
- **action**
  1. AC 逐条机检 + 全套终跑（`--all` 前报备）。
  2. 落盘 `M2-8-2-SUMMARY.md`（测试数/500 链实测数字/杀进程走查记录/zh 键清单）
     + `M2-8-2-DECISIONS.md`（KD-3 terminal trio 终表确认——colorin/colorout/gamma
     均答 .grade，排除集已写死 KD-3 / KD-4 两步 undo 偏离 +
     KD-4 跨图源 Deferred + contentRevision 重置 + delta Deferred 维持）。
  3. `.work/GOAL-STATE.md` 续接点追加；LESSONS 如踩坑。
  4. `git diff --stat` 核对边界（纪律 8）。
- **验收标准**
  - [ ] AC 表全绿；收口三件同批落盘；diff 边界无越界。

## 验收标准（AC 总表，逐条可机检）

| # | AC | 机检方式 |
|---|---|---|
| 1 | Versions 面板：列表/徽标/新建/Branch/Rename/Remove（确认流 + active 删切首 + 唯一删回隐式）/单击切换/空态引导全绿；placeholder marker 零残留 | VersionsPanelTests + `git grep editor.versions.placeholder` |
| 2 | 历史行：点击 jump（保尾）/类型图标四态穷举/position 高亮派生零新状态源 | HistoryRowJumpTests |
| 3 | undo 固化四条：跳回保尾/再编辑丢尾/双入口同源/500 链 .lra 重载逐字节 + 全程 undo | HistoryRowJumpTests（500 链数字入 SUMMARY） |
| 4 | 排除面枚举完整：develop 15 + drtPost 4 + terminal 3 逐一不可贴 + .grade 抽样可贴（owner 终表入 DECISIONS） | AdjustmentTransferTests |
| 5 | Paste 落版本：epoch item 形状（pasteSet/stackSnapshot/pasteEpochScope）+ DRT 第二 item + 蒙版 contentRevision==nil + 激活 + .lra 写触发 + 隐式目标 materialize | AdjustmentTransferTests |
| 6 | 投影单源：LayerStackProjection 抽取后既有 suite 零改动全绿 + stackSnapshot 重放逻辑全仓一处 | 既有 Layers/App suite + `git grep` |
| 7 | 跨图源：外部 .lra（v7 多版本/v6 单链）装载 + 版本二级选择；当前图入口 | AdjustmentTransferTests |
| 8 | 哨兵：真值表四格 + 注入 round-trip + 杀进程走查记录（或待人工登记） | CleanTerminateSentinelTests + SUMMARY |
| 9 | 红线：HistoryStack/HistoryHash/LightamerSidecar/LibrarySchema 零 diff；EditorState 半径 = 一函数体；视图 body 零 defaults 直读 | `git diff --stat` + `git grep` |
| 10 | 全套回归 0 fail，计数 ≈ P1 终态 + 28..34 | test-direct.sh --all BUNDLE 行双读 |
| 11 | diff 边界 == 申报文件集 | `git diff --stat` 逐文件核对 |
| 12 | 登记闭环（四新测试文件 × 双处） | `git grep` 双命中 |

## 风险与边界

- **Copy Adjustments 排除面枚举完整性（任务简报字面风险——checker M1 已销）**：
  terminal trio 实测 = `colorin`/`colorout`/`gamma` 均答 .grade（KD-3 终表写死）——
  谓词显式排除集已入 KD-3，T3 只按终表断言，无执行期再核实环节。**禁**在面板层散抄
  第二份排除逻辑（单函数纪律）。
- **多版本 × 导入链交互（P1 风险延续）**：面板创建动作使 .lra 提前诞生——`sidecar_present`
  下游观察项照旧挂 M2-8-3；本 plan 无新交互面。
- **外部 .lra 源的版本枚举**：v7 多版本源（versions 键）+ v6 单链源（隐式）两形态
  fixture 必测；损坏/外部篡改源 = decode 失败 → 对话框内 typed 错误文案（不崩不静默）。
- **UI 自动化不可用时的验收形态**：VersionsPanelTests/AdjustmentTransferTests 走
  视图 model + 真链断言（host 无头可跑）；真机走查（视觉/交互手感）归 M2-8-3 观察项
  （GUI-12/13 先例：列表面板体挤出可视区为已知坑，走查清单列明）。
- **长列表性能**（任务简报字面风险）：SwiftUI List 懒加载天然分页（OQ-10）；百版本
  滚动观察归 M2-8-3；本 plan 不预优化。
- **两步 undo 偏离**（KD-4）：DRT 勾选时粘贴版本内 undo 需两步（epoch + DRT 各一）；
  Alcedo 无对应物可比对——DECISIONS 签注，验收不算缺陷。

## 提交约定

- T1 `feat(app): versions panel`
- T2 `feat(app): clickable history rows with kind icons`
- T3 `feat(app): copy adjustments transfer dialog`
- T4 `feat(app): clean-terminate sentinel toast`
- T5 `docs(m2-8): close out plan 2 panels and interactions`
- 全英文 Conventional Commits；body 写 what+why + 同批同步的 md 清单；不 push。

## Checker 回注记录（2026-10-01）

checker 批（4E+5M）措辞联动修订，全量记录见 `M2-8-1-PLAN.md` 同名节。本文件三处：
- **m1** terminal trio 终表实测写死（`colorin`/`colorout`/`gamma` 均答 .grade，
  NodeOwnershipCatalog 未登记三件 + ColorIn/ColorOut/Gamma Module.opName 实测）——
  KD-3/风险节/T3 action/T5 DECISIONS 四处，删「执行期再核实」环节。
- **m2** KD-2 类型图标措辞改：`layerScope` 是 `String?`，直 switch 必带 default；
  编译期强制 = 先映射闭集 enum 再穷举。
- **m3** KD-6 措辞改：`UserDefaults(suiteName:)` 注入先例（AppPreferences.swift:58），
  无 `UserDefaultsSuite` 类型。
