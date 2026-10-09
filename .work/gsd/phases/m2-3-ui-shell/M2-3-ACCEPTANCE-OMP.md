# M2-3「UI 壳」回溯二次验收（omp 独立二次验收）

> 验收员 = omp（零共享上下文，首验结论不采信，一切亲测）。日期 2026-10-09，HEAD = `81b5df5`（main）。
> 正本亲读：M2-3-1..4 ACCEPTANCE + FIXES-SUMMARY + TAB-MATRIX + 四份 SUMMARY + AGENTS.md M2-2 剥离门口径。
> 说明：main 经历公开史压缩（D-EXEC 压缩批），M2-3 执行期短 SHA 全失效（机检 29/29 MISSING），
> `08c2e48`（M2-3 压缩 commit）仅存于 release 分支。抽查点 5 的 commit 对照改走「main 存续祖先的等价 commit」口径。

## 结论头

**PASS / 0 error + 1 minor**

- minor-1：首验引用的 29 个 plan 执行期 SHA 在当前 main 全部失效（历史压缩 + filter-branch 所致，非本 phase 缺陷；
  等价内容经 main 存续 commit + release 压缩 commit 双路确认存在）。回溯可审计性降级，记 minor。

## 逐 plan 判定

### M2-3-1（UI 壳骨架）— PASS

首验 PASS / 0+0。二次验收确认核心交付面在当前 HEAD 存续：MenuCommandSet 纯函数电路、
WorkspaceRoutingTests 矩阵断言、gate=false Host 面、Filmstrip/ThemeTokens 均在。定向测试 11/11 绿。

### M2-3-2（图库面）— PASS

首验 PASS / 0+1（新键计数 64→61 记账修正）。二次验收确认缺陷 A 修复专项（FIXES-SUMMARY `cba3456`：
fire-and-forget handler）在当前 LightamerApp/LibraryProjectController 存续（M2-3-4 ACCEPTANCE 的缺陷 A
转专项已闭环）；LibraryLegacyGateTests 11/11 绿；zh-audit --check 当前 PASS
（1584 source / 1822 catalog / zh complete / {en,zh}）。

### M2-3-3（编辑器面）— PASS

首验 PASS / 0+1（F-1 fflush 属豁免件域已修）。二次验收确认：EditorTabRoutingTable 正本存续、
tab 矩阵逐行对账测试存续（`testTabMatrixMatchesTheRoutingTableLineByLine`）、禁用名路由零命中存续、
缺陷 B 修复（attach(metal:)）存续——`PipeCoordinator.attach` 调用点与 tests 均在 HEAD 可见。
SettingsPagesTests 在 BUNDLE-MAP 登记 APP/9（M2-3-3 +9 的终态延续）。

### M2-3-4（收口）— PASS

首验 PASS / 0+2（F1 zh verbatim 缺口挂 M2-4、F2 计数笔误已修）。二次验收确认：
MANIFEST 归档完整（见抽查点 4）、zh-audit 工具存续且当前 PASS、20 屏判定分布与首验描述一致
（一致 11 / 偏差-接受 8 / 设计差异 1，偏差-修 2 已闭环）。

## 逐抽查点证据

### 1. 菜单 IA 电路 + 剥离门接线 — PASS

- `MenuCommandID` 枚举：`App/Sources/Lightamer/UI/Shell/MenuCommandSet.swift:23-54`，
  17 case（session 4 + project 6 + workspace 2 + search 1 + view 3 + M2-8-2 追加的
  editCopyAdjustments 1）。纯函数 `visibleCommandIDs(gate:phase:)`（:78-85）形态与首验一致；
  M2-8-2 追加 1 id 属后续 phase 加法，非 M2-3 回归。
- `sessionRoutes`/`newShellRoutes` 双注册表（:59-72）不相交 + 并集==全集的断言仍在：
  `Tests/LightamerTests/WorkspaceRoutingTests.swift:248-255`
  （`testSessionAndNewShellRegistriesAreDisjoint`），allCases 穷举逐 id 断言仍在（:217-246，
  `testMenuIAMatrixAcrossEveryGatePhaseCombination`，gate×phase 全组合）。
- LightamerApp 单点消费 `visibleMenuCommands`：`App/Sources/Lightamer/UI/LightamerApp.swift:393-397`；
  session 三菜单项 gate 包裹仍在（:1241/:1266/:1289）。`sessionImport` 无菜单消费点——与首验
  observation-1（M2-3-1-ACCEPTANCE:74-79）描述一致，非新分歧。
- 剥离门：唯一求值点 `LightamerApp.swift:357`
  （`LibraryLegacyGate.isLegacyLibraryRequested()`，注释 KD-1 注入纪律存续）→ 分发
  `ContentView(legacyLibraryEnabled:)`（:439）与 `SettingsView(legacyLibraryEnabled:)`（:1643）。
- ContentView gate=false 面 = WorkspaceHostView（:192-194，M2-3-1 T2 注释存续）；
  gate=true = legacyBody（:175-176）。`visibleContentFaceMarkers` 纯函数（:64-80）与 gate 测试钉一致。
- SettingsView 默认 false 面 = Catalogs 页隐藏（:31-36）+ `visibleCatalogSectionMarkers`
  纯函数（:47-60）；LibraryLegacyGateTests 对其快照断言仍在（Tests:174-187）。
- SidebarView 注入式 Bool（注释「assembly evaluates ONCE」存续）。

### 2. tab 矩阵路由对表 + 视图 body 零 ProcessInfo — PASS

对表抽查 6 行（路由表 `EditorTabRoute.swift:192-313` vs TAB-MATRIX md vs opName 字面）：

| 行 | md 行 | 路由表 | opName 字面确认 |
|---|---|---|---|
| Tone `exposure` | TAB-MATRIX:30 | EditorTabRoute.swift:206 | ExposureModule `exposure`（ExposureModule.swift:106） |
| Tone `shadhi` 单行双滑杆 | TAB-MATRIX:34 | :210（单 `.page` 行，无双行分支） | ShadhiModule `shadhi`（ShadhiModule.swift:118） |
| Look `vibrance`/Master | TAB-MATRIX:42 | :234 `.grouped(..., .master)` | VibranceModule `vibrance`（VibranceModule.swift:53） |
| Look `bilat`/DetailTexture | TAB-MATRIX:58 | :250 LocalContrastModule | `opName = "bilat"`（LocalContrastModule.swift:83） |
| DT `vignette` 唯一行 | TAB-MATRIX:60 | :259 单行 + E1 注释 | VignetteModule `vignette`（VignetteModule.swift:99） |
| sheet `watermark`/`borders` | TAB-MATRIX:77-78 | :298-305 topBarSheetPanels | `watermark`（WatermarkModule.swift:41）/`borders`（BordersModule.swift:125） |

- 页序 Tone→Look→LUT→DT→Geometry→RAW→Mask：`EditorTabRoute` case 序（:33-40）与 md:91 一致；
  对账测试钉页序字面（EditorStackRoutingTests.swift:332-334）。
- 禁用名路由零命中：`git grep -E 'filmicrgb|sigmoid|agx|denoiseprofile|nlmeans|bilateral'`
  在 EditorTabRoute.swift 零命中（`agx` 仅 E1 勘误注释英文提及，非字面；首验同口径）。
- 视图 body 零 ProcessInfo 直读：`UI/` 下 ProcessInfo 命中仅 LightamerApp 探针函数
  （-la_* probe 参数解析，非视图 body）+ WorkspaceHostView 探针 + 三处注释（ContentView:50 /
  SidebarView:23 / SettingsView:25 均为「never touches ProcessInfo」纪律声明）。EditorState 所在
  `State/` 命中仅 PipeCoordinator:2242 探针静态开关。生产路由/门控零直读。

### 3. 定向测试 — PASS（11/11 + 11/11，0 fail）

BUNDLE-MAP 归属：WorkspaceRoutingTests = APP/11（MAP:190），LibraryLegacyGateTests = LIB/11（MAP:306）。

- `Scripts/test-direct.sh --bundle App WorkspaceRoutingTests` →
  `BUNDLE|App|11/0/0|peakRSS=192MB`，`TOTAL|11/0/0`，OK。计数 = MAP 登记 11。
- `Scripts/test-direct.sh --bundle Library LibraryLegacyGateTests` →
  `BUNDLE|Library|11/0/0|peakRSS=192MB`，`TOTAL|11/0/0`，OK。计数 = MAP 登记 11。
- 未跑全套 --all（纪律遵守）。

### 4. 证据文件核对 — PASS（降级核对，路径迁移已定位）

`.work/gui-acceptance/m2-3/` 不在原位——2026-10-08 `ae1d257` 台账轮转批将其移至
`.work/archive/gui-acceptance/m2-3/`（未跟踪，盘上保留）。MANIFEST 与三件套完整：

- 抽查件 1：`editor-filmstrip/` 三件套齐（alcedo.png + lightamer.png + md）；
  md 首行「左侧竖向滚动条」判定「偏差-接受（设计差异）」——与 M2-3-4-ACCEPTANCE:20/AC#3
  「恰 1 行设计差异」描述一致。
- 抽查件 2：`library-welcome/` 三件套齐；md「居中卡片 vs 左右分栏」判定「偏差-接受」——
  与 MANIFEST 汇总矩阵第 1 行（MANIFEST.md:13）一致；验收抽查位记录（MANIFEST.md:64-68）
  3 屏 spot png 均在（md5 可读，非空占位）。
- 抽查件 3（加深）：`editor-adjustment-stack-look` md 记「zh 对齐 Alcedo 用词（修复批：
  风格→外观）」——与 AC#5 偏差-修闭环描述一致。

### 5. git 机检 — PASS（等价口径，见 minor-1）

首验引用的 29 个执行期 SHA 在 main 全失效（`git cat-file -t` 29/29 MISSING；
msg-only filter-branch 两轮 + L070 压缩批所致）。改走 main 存续祖先的等价 commit 对照：

- M2-3-1 T2 等价：`d88db8d`（IN-HEAD）`--stat` = 5 文件（ContentView/WorkspaceHostView/
  WorkspaceModel/EditorWorkspaceShellView/WorkspaceRoutingTests）——与 M2-3-1-SUMMARY:11
  T2 申报（Host 壳 + 双态路由 + ContentView 内层换）一致；测试方法 `grep -c func test` = 11
  （含 T5 早写矩阵 3，D5 注记一致）。
- M2-3-1 T5 等价：`74312d3`（IN-HEAD）`--stat` = 2 文件（MenuCommandSet.swift + LightamerApp.swift）——
  与 SUMMARY:15 T5 申报一致；message 含 m7 空白归一评审注记。
- M2-3-3 T2 等价：`a51d236`（IN-HEAD）`--stat` = 7 文件（含 TAB-MATRIX.md + EditorTabRoute +
  EditorStackRoutingTests）——与 M2-3-3-SUMMARY:29-33 T2 申报一致。
- 压缩总账：`08c2e48`（M2-3 UI shell，32 文件）仅存 release 分支（`IN-release`，main 不含）；
  main 与 release 的 M2-3 核心文件（MenuCommandSet/EditorTabRoute）diff 为空，内容同源。

## 与首验分歧点

- 无实质分歧。唯一记录项 = minor-1（SHA 失效，回溯可审计性降级；内容面双路确认存续）。
- 首验 observation（sessionImport 无消费点、禁用名 grep 口径、遗留挂账）逐条复核成立，无新增 error。

## 会话卫生

- 只读验收：除本报告文件外零写入；`git status` 仅见既有 untracked（09-3-tiers-*、dt-clone-archive），
  无本会话新增修改；未 push。
- 定向测试 2 类（App/Library 各 1），未跑全套。

OMP-VERDICT: PASS
