# M2-5-2 SUMMARY — Look/Tone 面板重组 + 默认 look 收口（2026-09-30/10-01 夜间批）

> plan = M2-5-2-PLAN.md（checker 修正版 87c039d）。执行 = 本 subagent（ZCode），T1-T8
> 逐任务独立提交、每任务边界读 config.toml [gsd]（paused=false/auto=true 全程未变）。
> 签注正本 = 同目录 M2-5-2-DECISIONS.md（八节）。渲染管线零改动（红线四文件零 diff）。

## 提交链

| 任务 | commit | 内容 |
|---|---|---|
| T1 | `d584835` | Tone 页收敛（主面 provider 面三行 + compat 折叠组五件、temperature 摘除主面）+ EditorPanelDescriptor group/note additive + PanelGroup 壳渲染 + TAB-MATRIX 同批 |
| T2 | `dd4b5ae` | Look 页四组 IA（13 行零丢失归组 + D9 四件 pre-DRT 注记 + LMT 留 LUT 页）+ TAB-MATRIX Look 行账同批 |
| T3 | `7c9bec8` | GradeScalarPanels.swift 六面板（CAT02/Contrast/White/Black/Tint/Saturation，量程常量引用）+ Tone 主面补齐六行 + Look Master/Color 挂行 |
| T4 | `ec8a237` | ColorWheelsPanelView 三 trackball（Canvas + DragGesture 经 IOP 纯函数 + 派生 colorOffset）+ 单轮/总 Reset + disc 换算纯函数落 ColorWheelsModule（IOP）+ CatalogAddFaceTests 开档 |
| T5 | `ae4e426` | HlsPanelView（Target Hue 8 色板 + 四滑杆经 applyTargetEdit + smoothness 镜像写）+ Color 组齐编 |
| T6 | `d430672` | EditorState.addFaceEntries（Grade 作用域 12 唯一 op / Develop 作用域零 grade-owned + Develop/compat 双 section）+ addModuleToBaseChain + InspectorView 无层选中分支（checker E4 新 UI）|
| T7 | `95d396b` | LibrarySchema v1→v2 首迁（additive 列 + 幂等 ALTER + 快照钩子首消费）+ insertImage 写 1 + flag 读/清 API + EditorState mint（E5 形态：单层三实例 + 单提交 + 跳 persist 通道）+ 开图入口 flag 注入 + DefaultLookTests |
| T8 | （本提交） | SUMMARY/DECISIONS/GOAL-STATE 收口 + 全套回归终跑 |

## 测试数变化（BUNDLE-MAP 对账）

- **起算基线 = 2288/14skip/0fail**（M2-5-1 收口 2287 + 验收批 c12bdb1 e7 closure
  测试 +1；App bundle 起算实测 347 = 2288 全套口径的 App 分量反推）。
- 新增/修订：EditorStackRoutingTests 9→**12**（+3：Tone 收敛 / Look 四组账 / 六
  provider 路由断言；T4/T5 的 populated 基数变化为既有方法内断言修订无方法增量）+
  CatalogAddFaceTests 新建 **9**（T4 四 + T5 二 + T6 三）+ DefaultLookTests 新建
  **5**（mint 双断言 + undo pristine + restore 压制 + flag=0/user grade + v1→v2 迁
  移）= **+17 方法**（全部 LightamerTestsApp）。LibrarySchemaTests/LibraryDocumentTests
  方法数不变（版本钉随 schema v2 同批修订——申报外测试随动，DECISIONS §七）。
- 预期全套终值 = **2305/14skip/0fail**（2288 + 17）。实测见下节。

## 全套回归终跑（--all，coordinator 批准后实跑）

```
BUNDLE|IOP|467/1/0|peakRSS=7798MB|125s|sampling=time
BUNDLE|IOPParity|326/2/0|peakRSS=5987MB|224s|sampling=time
BUNDLE|Layers|179/2/0|peakRSS=987MB|20s|sampling=time
BUNDLE|Library|430/4/0|peakRSS=294MB|17s|sampling=time
BUNDLE|Sessions|279/4/0|peakRSS=1630MB|72s|sampling=time
BUNDLE|Export|260/1/0|peakRSS=5927MB|190s|sampling=time
BUNDLE|App|364/0/0|peakRSS=1288MB|108s|sampling=time
TOTAL|2305/14/0|756s        （EXIT=0）
```

- **2305 = 2288 起算基线 + 17 新增精确**（EditorStackRoutingTests +3 + 
  CatalogAddFaceTests 9 + DefaultLookTests 5）；skip 14 不变；**MEMFAIL 零触发**
  （峰值 IOP 7798MB < 8192 门；次峰 IOPParity 5987 / Export 5927）。七 bundle 全绿
  0 fail。Library/Sessions/Export 三 bundle 本 plan 零代码触碰，计数与 M2-5-1 收口
  基线继承一致（430/279/260），回归干净。

## 四组行账终表（Look 页 + Tone 页，routing 表终态）

**Tone 页**（主面六行 Alcedo 目录序 + compat 折叠组）：

| 行 | opName | 组 | 面板 |
|---|---|---|---|
| Exposure | `exposure` | main | ExposurePanelView（既有） |
| Contrast | `contrast` | main | ContrastPanelView（新） |
| White | `white` | main | WhitePanelView（新） |
| Black | `black` | main | BlackPanelView（新） |
| Shadows / Highlights | `shadhi` | main（**单行双滑杆**，m2） | ShadhiPanelView（既有） |
| Curve | `tonecurve` | main | ToneCurvePanelView（既有） |
| levels/colisa/colorcontrast/toneequal/temperature | 各自 | **compat 折叠组** | 既有 provider（可编辑不删除，D10） |

**Look 页四组**（18 目录 + 13 既有行零丢失）：

| 组 | 行（opName） | 面板 |
|---|---|---|
| **Master** | `saturation`（新）/ `vibrance` | SaturationPanelView（新）/ 既有 |
| **Look**（D9 占位组） | `equalizer`(Clarity) / `sharpen` / `grain`(Film Grain) / `bloom`(Halation)——四行带 pre-DRT 注记 | 既有面板 |
| **Color** | `cat02WhiteBalance`（新，页内 AP1 提示）/ `hls`(Selective Color，新) / `colorWheels`(Color Wheels，新) / `tint`（新） | 新面板四件 |
| **Detail/Texture** | `velvia` / `monochrome` / `colorbalancergb` / `colorzones`（checker m1）/ `skinSmooth` / `highpass` / `soften` / `bilat`(localcontrast) | 既有面板 |

- LMT（`lut3d`）恒在 LUT 页（D10）；Display Transform / Geometry / RAW Decode /
  Mask / LUT 五页行账与 M2-3 基线一致（Geometry advanced 五件不动）。
- TAB-MATRIX（`.work/gsd/phases/m2-3-ui-shell/M2-3-TAB-MATRIX.md`）两页行账 +
  M2-5-2 增批注记随实态同批更新；对账机检（testTabMatrixMatches…）绿。

## 新 UI 键名清单（en+zh 双写随手入账；P3 收口 zh-audit 对账）

组头/壳（5）：`panel_group_master` `panel_group_look` `panel_group_color`
`panel_group_detail_texture` `editor_stack_compat`；注记（1）：`panel_note_pre_drt`；
行标签（8）：`module_shadows_highlights` `module_cat02_white_balance` `module_contrast`
`module_white` `module_black` `module_tint` `module_saturation` `module_color_wheels`
`module_selective_color`（9，含 shadhi 单行）；面板（22）：`panel_cat02_section/
temperature/tint/note`、`panel_contrast_section/contrast`、`panel_white_section/white`、
`panel_black_section/black`、`panel_tint_section/tint`、`panel_saturation_section/
saturation`、`panel_wheels_lift/gamma/gain/strength/luminance/reset`、
`panel_hls_target/target_bin/section/hueshift/lightness/chroma/smoothness`；
history（9）：`history_cat02` `history_contrast` `history_white` `history_black`
`history_tint` `history_saturation` `history_colorwheels` `history_hls`
`history_default_look`；add 面（1）：`add_face_develop_section` +
`history_base_module_add`。合计 **32 键**。

## flag 消费点选型签注（KD-5 fallback）

编辑器会话无 imageRowID 现成通道（read_first 6 定位：M2-2 image→row 关联止于
LibraryGridModel/LibraryQueries，EditorState 侧零通道）→ **按 KD-5 预声明 fallback
执行**：`EditorWorkspaceShellView.loadCurrentImage()`（持 `workspace.currentRow` =
library rowid）经 LibraryStore 读 flag → 注入 `EditorState.load(defaultLookPending:)`
→ 开图即清 flag（mint 分支内部再做 `.lra` 文件级复核）。走线 = WorkspaceHostView
把 projectController 传入 shell。**EditorWorkspaceShellView/WorkspaceHostView 为
front-matter 申报外接线文件（fallback 条款钦定），DECISIONS §六已声明**。语义等价
上 litmus：flag 语义收窄为「未打开过的新导入」标记（开图即消费，幂等）。

## AC 总表核验

| # | AC | 结果 |
|---|---|---|
| 1 | Tone 主面六行（shadhi 单行双滑杆）+ compat 五件 + temperature 摘除 | ✅ testTonePageConvergedWithCompatGroup（主面逐序断言 + shadhi count==1 + compat 集合断言）；contrast/white/black T3 批到位 |
| 2 | Look 四组 IA + 行账 + LMT 不在 Look + D9 四 note | ✅ testLookPageFourGroupIALedger（ledger13 零丢失 + 组成员 + 恰 4 note + LUT 页 lmt） |
| 3 | TAB-MATRIX 与实态一致 | ✅ testTabMatrixMatchesTheRoutingTableLineByLine 全绿（两页行账同批重写） |
| 4 | 八 provider 注册 + 面板量程 = P1 Params + 层作用域双态 | ✅ testScalarPanelProvidersRegisterAndRoute + 面板常量引用（编译期零漂移）；作用域 = InspectorEditSession 既有缝零改动；走查项（开合/拖杆/reset 经 add 面实例化）入 P3 收口观察清单 |
| 5 | trackball disc 纯函数 + 双组 reset → identityJSON 逐字节 | ✅ CatalogAddFaceTests 前四法（round-trip/clamp、cdlDelta 方向+量程、单轮 reset、真 EditorState 会话 reset 链上字节 == identityJSON） |
| 6 | Selective Color bin 切换 + 四滑杆 ↔ applyTargetEdit 零面板映射 | ✅ testHlsDisplayValuesTrackTheSelectedBin + testHlsSliderWritesRideApplyTargetEditAndSmoothnessMirror |
| 7 | add 面矩阵（Grade 唯一 op 集 / Develop 零 .grade / LMT·DRT 不在任何枚举 / 校验缝零 diff） | ✅ testGradeScopeAddFaceEnumeratesTheCatalogMatrix + testDevelopScopeAddFaceExcludesEveryGradeOwnedOp；NodeOwnershipCatalogTests 6/6 全绿（缝零 diff）；**计数对账 = 12 唯一 op**（plan「恰 14」含 lmt+shadhi 重复行与「LMT 不在枚举」互斥，LMT 排除为绑定语义——DECISIONS §五） |
| 8 | 默认 look 四态 + 双断言（flushNow 无 .lra / undo 一步 pristine）+ pristine 不变量 | ✅ DefaultLookTests 五法全绿（mint 三参数逐值 +1.5/+15/1.3、恰 1 history item、强制 flush 无 .lra、undo 空栈、.lra 存在零注入、flag=0 零注入、user grade 空链） |
| 9 | `.lalb` v1→v2 首迁（幂等补列 + 既有 DDL 零改 + user_version=2 + 快照钩子消费） | ✅ testLibrarySchemaV1ToV2FirstMigration（手拼 v1 库 → open → .pre-migrate.bak 落盘 + version 2 + 旧行 flag 0/新行 1 + 二次打开幂等）；git diff LibrarySchema.swift 逐 hunk = append-only |
| 10 | 渲染红线四文件零 diff | ✅ `git diff --name-only` grep 零命中（LayerCompositeDriver/PixelPipe/PipeCacheKey/LightamerSidecar） |
| 11 | 全套回归 0 fail | ✅ **TOTAL 2305/14/0（756s）EXIT=0**（2288 基线 + 17 精确；MEMFAIL 零触发） |
| 12 | diff 边界 + 测试登记闭环 | ✅ 见下节边界表；DefaultLookTests/CatalogAddFaceTests × Project.swift + BUNDLE-MAP 四命中（git grep 双查） |

## diff 边界（申报集 + 已声明偏差）

申报内全量落地；**申报外五处（全部 DECISIONS 已声明）**：

| 文件 | 依据 |
|---|---|
| `LightamerIOP/Sources/ColorWheels/ColorWheelsModule.swift`（+纯函数/常量/resetting） | KD-2 钦定落点（「极角换算纯函数落 IOP」）——front-matter 漏报，DECISIONS §三 |
| `App/Sources/Lightamer/UI/Shell/EditorWorkspaceShellView.swift`（flag 腿） | KD-5 fallback 钦定开图入口，DECISIONS §六 |
| `App/Sources/Lightamer/UI/Shell/WorkspaceHostView.swift`（controller 传参一行） | 同上走线 |
| `Tests/LightamerTests/LibrarySchemaTests.swift`（版本钉随 v2） | schema bump 必然随动（V50OrderTests 先例），DECISIONS §七 |
| `Tests/LightamerTests/LibraryDocumentTests.swift`（版本钉随 v2） | 同上 |

`.work/gsd/phases/m2-4-0-test-bundles/M2-4-0-BUNDLE-MAP.txt` = checker E2 登记纪律
载体（同 commit 闭环，先例同款）。**未 push。**

## 已知限制 / 移交（P3 收口观察项）

- **面板走查清单**（新面板实例经 T6 add 面才可达）：六标量面/trackball/HLS 面的
  开合、拖杆 live 预览、reset、层作用域双态目测；trackball 手感（阻尼/灵敏度）
  无机检门（plan 风险节条款），交互参数调整不视为返工。
- **域盲五件面板语义**（M2-5-1 移交）：exposure/shadhi/vibrance/tonecurve/lut3d
  面板在层链内调参的域语义对齐归后续 plan（P1 D1 零代码对齐的结构性后果，本 plan
  零触碰）。
- **ACEScc envelope GPU 代价**（OQ-11 观察项）：随 M2-5-1 挂账 P3 三查。
- **zh 键**：本批 32 键 en+zh 双写已入账，phase 尾 P3 收口 `Scripts/zh-audit.py
  --check` 终对账。
