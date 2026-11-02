# 首启图库优先（library-first-launch）— 执行 SUMMARY（定稿，commit 7aa4c140）

## 设计（vs 任务书偏差）

任务书设想"ContentView gate-false 不再走 ProjectWorkspaceFace → 直接挂 WorkspaceHostView 图库面"。
实测架构真相：gate-false 早就是 `WorkspaceHostView`（M2-3-1 起）；ProjectWorkspaceFace 是其
`libraryFace` 的无项目臂。真障碍是**图库面强绑定 open project store**
（`rebuildLibrarySurface` nil-store 即 surface 归零；`runImport` 无 store 直接 return；
`LibraryProjectController` FIX2③ 零 diff）——无项目即无图库面可挂。

落定：**默认库（Default Library）**——首启 open-or-create
`~/Library/Application Support/Lightamer/Library.lalb`，首启即真图库面（空态+导入入口）。

- 首启无条件开默认库（recents 有无皆同——二次启动不回退 Welcome）
- legacy 门守卫：gate=true 跳过 drive，会话壳启动行为逐字节旧
- Welcome sheet 保留：默认库失败 fallback（support 不可达/open 抛错）+ 手动入口
- 无项目 fallback 面（ProjectWorkspaceFace nil 臂）：文案复用冻结键 + "Open My Library" 重驱按钮

## 改动面（6 改 + 2 新）

- `App/.../Library/LibraryFirstLaunch.swift`（新）：默认库纯指派（URL/文件名/名三单源）
- `App/.../UI/Shell/LightamerShell.swift`：启动 task 改路由 + `openDefaultLibraryIfAvailable` + shell 根注入重驱闭包
- `App/.../Library/Views/LibraryGridView.swift`：空态加导入按钮（⌘⇧I + AX id `library.grid.empty.import`）+ 拖放提示文案
- `App/.../UI/Shell/WorkspaceHostView.swift`：`onImportFolder` 穿 grid 空态 + `onOpenDefaultLibrary` 穿 fallback 面
- `App/.../UI/ContentView.swift`：`onOpenDefaultLibrary` 穿线 + nil 臂 fallback 化（OPEN 臂成死分支，marker 冻结）
- `Tests/.../LibraryFirstLaunchTests.swift`（新，LIB 域 9 法：指派 4 + drive 2 + 条件 1 + 守卫 2）+ Project.swift + BUNDLE-MAP（LIB 9）
- `Resources/Localizable.xcstrings`：尾插 3 键（empty_import / empty_drop_hint / face_open_default）

纪律：封存面 17 件零 diff（glob 扫描实证）/ controller 零 diff / marker 面冻结
（WorkspaceRoutingTests pass）/ zh-audit PASS（1798/2131）。

## 测试终值（7 域逐跑——`--all` 遇 IOP 红即停语义，先停后逐域补齐）

- Library 797/4/0 ✓（新类 9 法全在内；4 skip = 3 bench 门 + 1 GPS 条件，全预期）
- Sessions 285/4/0 ✓ / Export 385/4/0 ✓
- IOP 836/1/17 / IOPParity 584/10/36 / Layers 540/5/23 / App 1102/6/45：
  121 fail 全 film 族 HEAD 既有红（`55ad476d` B&W 资产 `base_density[0]` 数组形
  vs 解码器 Float 期望 → fail-closed；绿基线 bb1d1665 4520/34/0 在资产提交之前；
  解码器零改动；本批 diff 无 film 文件）——本批不修，上报 film lane。
- 受影响面全绿：WorkspaceRouting / ToastFace / ProjectReadOnly / ThemeTokens /
  LibraryProjectController；zh-audit PASS（1798/2131）。
- 测试宿主污染修复：`isTestHost` 守卫（复现→修→9/0/0 + 零残留实证）。

## 走查（`.work/gui-acceptance/library-first-launch/`，MANIFEST 入库，png 本地）

- lfl-01：冷启动直进图库空态面，无 Welcome ✓
- lfl-02：⌘⇧I 弹 Import Folder 面板 ✓
- lfl-03：二次启动直进默认库，无 Welcome 回退 ✓
