# M2-8-2 ACCEPTANCE — 面板与交互（Versions 面板 + 历史行升级 + Copy Adjustments + 崩溃哨兵）独立验收

> 验收：ZCode 验收 subagent（零共享上下文），2026-10-01。对象 = 执行方 5 提交
> （`c5e1ea7` T1 Versions 面板 / `161a773` T2 历史行升级 / `56360ee` T3 Copy Adjustments /
> `81f361b` T4 崩溃哨兵 + willTerminate 修复 / `8f2394c` T5 收口；plan 正本 = checker
> 修正版 `527d4ba`）。方式 = AC 12 条逐条核对 + 五重点读码抽查 + 全套 --all 独立复跑
> ×2 + grep/git 机检。
> **结论头：PASS / 0 error + 1 minor（已修，同批）+ 3 observation。**

## 一、独立复跑 vs 声明（环境插曲全程在案）

执行方申报终跑 = `TOTAL|2573/16/0|951s EXIT=0`。本轮独立复跑：

| 轮次 | 结果 | 备注 |
|---|---|---|
| --all 第 1 轮 | `2573/16/1`（995s EXIT=1） | 六 bundle **逐值一致**（IOP 467/1/0·IOPParity 362/3/0·Layers 298/3/0·Library 436/4/0·Sessions 279/4/0·Export 260/1/0）；App 471 中 1 fail = `SidecarV5Tests.testWriteLegPersistsOverridesIntoTheSidecarFile`（decode readback 超时 104s，前置日志 `Failed to compile model 11 MILCompilerForANE`） |
| App 单 bundle 复跑 ×2 | `471/0/1` ×2 | 同用例复现；第 2 次显式报 `NSCocoaErrorDomain Code=640 「空间不足」`（RAW 工作拷贝写盘失败） |
| 单类复跑 | `11/0/0`（33s EXIT=0） | SidecarV5Tests 冷态全绿 |
| 清盘后 App 单 bundle | **`471/0/0`（204s EXIT=0）** | 与申报逐值一致 |
| --all 第 2 轮 | `2573/16/1`（996s EXIT=1） | 六 bundle 再次逐值一致；App 1 fail = **另一条** `McpCullingToolsetTests.testFaceRegionsEmptyFacesOnNonFaceImage`（Vision `Could not build inference plan - ANECF error: failed to load ANE model … (DESIGN)`） |

**归因结论（铁证链）**：两轮 fail 均为 **ANE（Apple Neural Engine）推理面环境失败**
——第 1 轮 ANE 编译失败（`MILCompilerForANE` + 宿主 2 天未重启的系统盘积累）+
**系统盘 98% 满（仅 5.6GB）**；第 2 轮盘已清至 16GB 仍复现 ANE 模型加载失败，但
**受害用例换人**。判环境型而非产品回归的依据：

1. 两条受害测试文件在本 plan 全程 **0 字节触碰**（`git diff 301ebea..8f2394c` 机检）；
2. 两轮 fail 各不相同、均为 ANE 类型错误；App bundle 冷态独立跑 471/0/0 全绿；
3. 执行方同 HEAD 树 3.5h 前 `--all` 2573/16/0 全绿（终跑记录在案）；
4. 23 条新测试在全部轮次（含两轮 --all 的 fail 轮）**全数通过**。

**系统盘满根因（顺带查明，150 个残留已清）**：`SidecarV5Tests` 的 71MB RAW 工作
拷贝（`/var/folders/.../T/sidecarv5-<UUID>/`）在失败/超时路径下 defer 清理失效，
**每次 App bundle 运行恒漏 3 个×71MB**（清盘后绿跑一次实测又生 3 个）——累积
150 个 ≈ 10GB 把系统盘顶到 98%，反噬 decode readback 腿。已清 150 个（temp
10GB→93MB，系统盘 5.6GB→17GB）。**预存测试卫生缺陷**（02-06 形态，非本 plan
交付物）→ observation③ 登记。

**数字对账**：基线 2550/16/0 + 23（APP 四文件 5+7+8+3，BUNDLE-MAP 行对账）=
2573/16/0 **精确**；两轮 --all 的 executed/skip 逐值复现，fail 均为环境臂。

## 二、AC 12 条逐条判定

| # | AC | 判定 | 证据 |
|---|---|---|---|
| 1 | Versions 面板全操作 + placeholder 零残留 | ✅ | VersionsPanelTests 5 法亲读（空态/列表+徽标+updated_at/rename trim+拒空/remove active→首·唯一删→空态/行点切换）；`git grep editor.versions.placeholder` 零命中（渲染臂退役，EditorRailPlaceholder 结构保留）；孤儿键 `editor_versions_placeholder` 同批删（xcstrings diff 亲核）；新 marker 族 `editor.versions.panel/new/branch/rename/remove` 在场 |
| 2 | 历史行 jump/图标四态/高亮派生 | ✅ | HistoryRowJumpTests 亲读：`testHistoryRowsReverseDisplayWithOriginalIndices`（倒序+原始索引）+ `testRowKindMappingAnswersAllFourMarkerStates`；`selectedID` 纯派生自 `editorState.history.position`（无新状态源，diff 亲读）+ isSelected trait |
| 3 | undo 固化四条 + 500 链 | ✅ | 四条各有其测：`testJumpBackKeepsTheRedoTail` / `testEditAfterJumpTruncatesTheRedoTail` / `testPanelButtonsAndMenuShortcutsLandIdenticalState` / `testFiveHundredItemChainReloadsByteFaithfulAndUndoesToEnd`——500 链程序化 commit×500 → `pasteDidChange()` 触发持久化 → flush 落盘 → 冷装配重载 `items` 全等断言 + undo×500 到 `position == −1` + 投影无 exposure 残留；无 XCTSkip |
| 4 | 排除面枚举完整 | ✅ | `testExclusionFaceEnumeratesComplete`：develop 15 + drtPost 4 从 catalog 正本表循环（改名即编译失败，不可漂移）+ terminal trio **两段式断言**（owner 默认答 .grade 的前提 AND 谓词 false 的结论同钉）+ grade 5 op 类型化抽样全 true；DECISIONS §1.1 终表签注在案 |
| 5 | Paste 落版本形状 | ✅ | `testPasteChainLandsEpochVersionWithDrtSecondItem`：epoch item（`isOverwritePaste` + `pasteEpochScope` + `pasteSet` 逐 op + `stackSnapshot` 层名 + `snapshot` 槽首记录占位）+ DRT 第二 item（`drtDocumentScope` + `drtRecord`）+ 蒙版 `contentRevision == nil`（源 7→nil）+ 激活 + `.lra` 写触发（flush 后 decode 断言 versions=2/activeID/items=2）+ 隐式 materialize「版本 1」 |
| 6 | 投影单源 | ✅ | `LayerStackProjection.rebuild` 与原 `EditorState.rebuildLayerStack` 函数体**逐行同构**亲核（`Self.layerStructureScope == EditorStructureScope.marker == "__layerStack__"` 同常量）；EditorState diff = 一函数体 + doc 注释（半径红线）；重放位点甄别：peek plane / QuickLook / Export 三处 `makeLayers()` 均为「已提取 snapshot 的物化」或 sidecar layer 记录路径，**无第二份 history 重放规则**；既有 Layers/App suite 零改动全绿 |
| 7 | 跨图源 v7/v6 | ✅ | 三测亲读：v7 多版本真 `.lra` fixture（二级选择 + DRT 行随版本切换）+ v6 单链（activeChainID 哨兵）+ 损坏源 typed `AdjustmentTransferError.unreadable`；全为真文件 fixture 非后门 |
| 8 | 哨兵真值表 + round-trip + 走查 | ✅ | CleanTerminateSentinelTests 3 法亲读（四格真值表 + 注入 suite round-trip：首启 silent→置 running / kill 保持 true / markClean→false / reset 回首态 + 键/copy 登记）；键 = `app.cleanTerminate`；SUMMARY kill 走查五格程序化记录在案；toast 屏上面按 plan 预案登记 M2-8-3 走查 |
| 9 | 红线 | ✅ | 四封存文件（HistoryStack/HistoryHash/LightamerSidecar/LibrarySchema）`git diff 301ebea..8f2394c` **0 字节**机检；EditorState 半径 = `rebuildLayerStack` 一函数体委托（diff 逐行核对）；三视图 body 零 UserDefaults/ProcessInfo 直读（grep 零命中）；Core 不 import App（LayerStackProjection 仅 Foundation）|
| 10 | 全套 0 fail，≈P1 终态 +28..34 | ✅ | 2573/16/0（执行方终跑）+ 本轮两轮 --all executed/skip 逐值复现、23 新测试全绿、fail 均环境臂（§一）；+23 在预估带 28..34 下方 = 计划期方法数预估偏差，BUNDLE 行精确对账值为准（M2-8-1 验收同款处置：预估非承诺）|
| 11 | diff 边界 == 申报文件集 | ✅ | 逐 commit `--name-only` 对照 front-matter：31 文件次全部落在 files_modified ∪ 申报越界（AppPreferences/VersionSwapTests/xcstrings）；willTerminate 修复落 LightamerApp.swift（该文件本在申报集内，函数级范围扩展，commit body + DECISIONS §2.4 双申报）|
| 12 | 登记闭环 | ✅（带勘误） | Project.swift 四新文件 + BUNDLE-MAP 四行双命中；**per-file 计数过时 = 本轮唯一 minor，已修**（§三①）|

## 三、重点核查与勘误

### ① minor（已修，随验收 commit）：BUNDLE-MAP AdjustmentTransferTests 行 7→8

登记预写数 7 vs 文件实况 8 法——M2-8-1 验收批同款差 1（该批已把同类缺陷修过
一轮，本批四新文件登记时再犯）。APP 四行合计 23 不变、2573 总对账不受影响。
按「行内 method 数以终态对账为准」+ 两批勘误先例，随验收 commit 修正行值 +
增行记录注第三批勘误。

### ② observation①：SUMMARY/GOAL-STATE 行文「43 键 / T3（23）」实况 42/22

逐 commit xcstrings diff 机检：T1 15 + T2 4 + **T3 22** + T4 1 = **新增 42 键**
（删孤儿键 1 → 净 +41 = 1588−1547 精确）。SUMMARY 自列 T3 键清单亦仅 22 项
（「23」为笔误）；代码中 `history_paste_adjustments` 为 09-04 既有键复用非新键。
按 M2-8-1 先例执行方行文不改写，**M2-8-3 zh-audit 对账以 42 为准**（本报告 +
GOAL-STATE 续接点双登记）。

### ③ observation②：App bundle 尾段 ANE 环境脆弱面（本机在案）

两轮 --all 的 App bundle（第七棒）各折损 1 条**不同**预存测试，均为 ANE 推理
面错误（编译失败/模型加载失败），冷态全绿。非本 plan 引入；建议（不阻塞）：
M2-8-3 GUI 走查批顺带观察；若复发升级可议 test-direct.sh 尾段 bundle 间隔散热
或 ANE 状态预检。另 §一 的 `sidecarv5-*` temp 恒漏（每次 App 跑 +213MB）为
预存测试卫生缺陷，建议后续批给 `makeWorkCopy` 补 always-clean 或脚本预扫。

### ④ willTerminate 签名修复——正确性亲核（T4 越界增补定性：功能必需）

- 签名 = `applicationWillTerminate(_ notification: Notification)`（协议正身），
  注释钉明形参类型承载性；"nearly matches" 警告消除；
- 接线三腿亲读：launch 组装根 `consumeAtLaunch()`（读旧值→置 running 一次）/
  terminate 面在 bounded flush 返回**之后** `markClean()` / 编辑器就绪
  onChange 一次性消费 toast（消费即清 flag）；
- 走查五格（defaults 读回法）程序化记录在 SUMMARY，键值翻转语义与实现一致；
- 该修复同时复活 02-06 的 flush-on-quit 面（2s debounce 此前掩盖缺口）——
  LESSONS L052 已入账，定性 = 功能必需非顺手 fix，合规。

### ⑤ pasteChain / LayerStackProjection 语义抽查

- `pasteChain`：materialize-if-needed → 新槽（name 面板传参）→ epoch item
  （commitPaste + pasteEpochScope + stackSnapshot）→ DRT 勾选时 commitDrt 第二
  item → `captureActiveChain` → append → activate → `finishVersionAction` 尾
  （与 P1 命令同投影/写触发）；早退臂均在 slots.append 之前（无半落状态）；
  两步 undo 偏离 = DECISIONS §1.2 签注在案。
- 蒙版重置点 = `AdjustmentTransferModel.pastePayload()`（payload 构建前置 nil，
  测试钉死源 7→粘贴 nil）。
- KD-1 名规则：`createFromScratch(name:)/branchFromCurrent(name:)` 必传，
  `implicitVersionName()` 留 coordinator 内部（`versions_default_name` 键）——
  与 DECISIONS §2.1 分工一致；VersionSwapTests 调用点更新 + locale 镜像断言
  （越界申报②）亲读合规。

## 四、越界审计结论

3 文件 + 1 修复全部**申报闭环**（各 commit body + SUMMARY 偏差节 + DECISIONS
§2.4 三重）：

1. `AppPreferences.swift`（T3）= DefaultKeymap 穷举 switch 对 MenuCommandID 新
   case 的编译强制涟漪（nil-shortcut 臂一行，diff 亲读）——不修则 0 fail 不可达；
2. `VersionSwapTests.swift`（T1）= coordinator 命令签名 name 参数化调用点 +
   locale 镜像断言（语义零改动亲读）；
3. `Localizable.xcstrings`（T1..T4）= zh 键随手落物理载体（42 新键 + 1 孤儿键删，
   front-matter 漏列）；
4. willTerminate 签名修复 = 功能必需（见 §三④）。

工作区滞留物核查：`IMG_*.ARW`、`Scripts/__pycache__`、`.work/culling-cli`、
gui-acceptance 截图等 mtime 全部早于本 plan 执行窗（Sep 26–30），属前期
batch/GUI 走查遗留，非 M2-8-2 产物；本 plan 五提交 diff 边界干净。

## 五、判定与移交

- **判定：PASS**——AC 12 条全过（AC12 带已修 minor）；两轮 --all 的 1 fail 均
  环境臂（ANE + 系统盘，受害用例预存且零触碰，冷态/执行方轮全绿），不阻判定；
  越界 3+1 全部申报合理；红线零违例；23 新测试全数通过且真链无后门。
- 翻账（本批同 commit）：REQUIREMENTS **M2VER-02 / M2VER-04 / M2VER-05 翻勾
  Delivered**（证据注记随行；M2VER-04「参数 delta」半边按 D-M2-8-CONTEXT-8-A
  维持 Deferred 不阻翻账）+ BUNDLE-MAP 第三批勘误 + 本报告 + GOAL-STATE 续接点。
- 下一步：M2-8-3（zh-audit 对账 **42 键**【非 SUMMARY 行文 43，见 observation①】
  + GUI 走查：哨兵 toast 屏上一次性 / Copy Adjustments 手感 / 列表面板体挤出
  可视区 GUI-12/13 先例坑 + sidecar_present 下游观察项）；observation②③ 两项
  预存卫生面可随该批或后续批处置。
- 未 push。验收批 commit = BUNDLE-MAP 勘误 + REQUIREMENTS 翻账 + 本报告 +
  GOAL-STATE 续接点。
