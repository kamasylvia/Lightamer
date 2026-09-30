# M2-5-2-ACCEPTANCE — Look/Tone 面板重组 + 默认 look 独立验收报告

> 验收批：2026-10-01（独立验收 subagent）。对象 = plan `M2-5-2-PLAN.md`
> （checker 修正版 `87c039d`）+ 执行批 8 commits（T1 `d584835` / T2
> `dd4b5ae` / T3 `7c9bec8` / T4 `ec8a237` / T5 `ae4e426` / T6 `d430672` /
> T7 `95d396b` / T8 `36f082b`）+ 验收批修复 1 commit（见文末）。验收方式
> = 逐 AC 机检核对 + 六重点抽查（file:line 读码；Alcedo GPL 仓源码逐式
> 数学验算，只读不拷）+ 定向独立复跑（`--bundle App` / `--bundle Library`
> / `--bundle IOP` + 三测试类定向；全套 `--all` 不重跑——批准门纪律）。

## 结论

**PASS / 0 error + 1 minor（本批已修）**

- 执行批 8 commits 全部按 plan 交付，AC 12/12 独立复核全绿。
- 复跑与声明 `--all` 终跑逐值一致（App 364/0/0、Library 430/4/0、
  IOP 467/1/0；声明 TOTAL|2305/14/0|756s EXIT=0 = 起算基线 2288 + 17）。
- 六重点核查全部属实（详见下节）；唯一实质发现 = trackball strength
  clamp 缺失（minor，验收批已修）。
- 签核 VALIDATION 归 verify-work 独立步（C 档门控第 3 条，输入 = 本文件）。

## AC 总表复核（12/12）

| # | AC | 独立核验 |
|---|---|---|
| 1 | Tone 主面六行（shadhi 单行双滑杆）+ compat 五件 + temperature 摘除 | ✅ `EditorTabRoute.swift:197-209` 实态逐行 = AC 字面；`testTonePageConvergedWithCompatGroup` 主面逐序 + compat 集合 + shadhi count==1 断言 |
| 2 | Look 四组 IA + 行账 + LMT 不在 Look + D9 四 note | ✅ `EditorTabRoute.swift:222-249` 四组 18 行；`testLookPageFourGroupIALedger` ledger13 零丢失 + 恰 4 note + LUT 页独占 lmt |
| 3 | TAB-MATRIX 与实态一致 | ✅ 两页行账 + M2-5-2 增批注记同批（shadhi 单行/colorzones/m1 裁定在册）；`testTabMatrixMatchesTheRoutingTableLineByLine` 运行期对账绿 |
| 4 | 八 provider + 量程 = P1 Params + 双作用域 | ✅ `InspectorState.swift:148-163` 八 register；`GradeScalarPanels.swift` 全部常量引用（`Cat02WBModule.temperatureRange` 等，编译期零漂移）；作用域走 `InspectorEditSession` 既有缝零改动 |
| 5 | trackball 纯函数 + 双组 reset → identityJSON 逐字节 | ✅ `ColorWheelsModule.swift` discFrom/pointFrom/cdlDelta/colorOffset/resetting；CatalogAddFaceTests 4 法（真 EditorState reset 链字节 == identityJSON）；**本批补 strength clamp（见 findings）** |
| 6 | Selective Color bin 切换 + 四滑杆 ↔ applyTargetEdit | ✅ `HlsPanelView.swift` 静态可测缝 displayValues/write 漏斗；CatalogAddFaceTests 2 法（bin 隔离读 + applyTargetEdit 同源 + smoothness hRangeTable/hRange 镜像） |
| 7 | add 面矩阵 + 校验缝零 diff | ✅ `EditorState.addFaceEntries`（Grade 12 唯一 op / Develop 零 grade-owned + temperature 在列 exposure 不在列）；`addModuleToLayer` 校验缝零 diff（NodeOwnershipCatalogTests 全绿）；计数裁决见重点⑤ |
| 8 | 默认 look 四态 + E5 双断言 + pristine 不变量 | ✅ DefaultLookTests 5 法定向复跑 5/0/0（见重点①） |
| 9 | `.lalb` v1→v2 首迁 | ✅ `LibrarySchema.swift` diff 逐 hunk = append-only；migrate slot 首填 + 幂等探针 + 快照钩子首消费（见重点②）；DefaultLookTests ⑤ 端到端（.pre-migrate.bak + 二次 open 幂等） |
| 10 | 渲染红线四文件零 diff | ✅ `git diff 36f082b~8 36f082b --name-only` grep LayerCompositeDriver/PixelPipe/PipeCacheKey/LightamerSidecar 零命中 |
| 11 | 全套回归 0 fail | ✅ App 364/0/0（99-112s）+ Library 430/4/0 + IOP 467/1/0 复跑逐值一致；skip 14 口径 = 七 bundle 合计（App 0/Library 4/IOP 1/...） |
| 12 | diff 边界 + 测试登记闭环 | ✅ 申报集全落地 + 申报外 5 文件 + BUNDLE-MAP 全部有据（见重点⑥）；DefaultLookTests/CatalogAddFaceTests × Project.swift:649,651 + BUNDLE-MAP:153,161 双命中 |

## 六重点核查

### 重点① E5 默认 look mint 真伪 + DefaultLookTests 双断言

- **「跳 persist 通道」实现为真**：`EditorState.commitLayerStructure(layerID:label:
  schedulePersist:)`（EditorState.swift:840-854）既有参数化通道，`schedulePersist:
  false` → `notifyLayerChange(persist: false)` → `PipeCoordinator.layerStackDidChange`
  (PipeCoordinator.swift:1237-1242) 的 `if persist { scheduleSidecarWrite() }`
  短路——persist 调度构造上零发生，非时序巧合。mint 本体（EditorState.swift:867-909）
  = 单 AdjustmentLayer 内存构造（GradeCatalog.defaultLook 三 entry 经各模块 Codable
  解码 setParams）+ 恰一条 history item + `schedulePersist: false`；调用点在
  `load` decodeTask 内 pipe load 定局之后（EditorState.swift:379-388）且 `.lra`
  文件级复核缺席才铸——restore 恒压过 flag 为文件事实复核。
- **DefaultLookTests 双断言为真**：①`testPendingFlagMintsOneLayerThreeInstancesNoSidecar`
  mint 后逐参数断言 +1.5/+15/1.3 + 恰 1 history item + `flushSidecar()`（→
  SidecarStore.flushNow 强制落盘）后磁盘无 `.lra`（DefaultLookTests.swift:119-162）；
  ②`testOneUndoStepsBackToPristine` 一步 undo → 零 adjustment layer + flush 后
  仍无 `.lra`（:166-180）。另有 ③restore 压制（真 .lra + flag=1 → 恰 2 层零注入，
  双 keep-alive 会话）④flag=0 零注入 + user grade 空 chain ⑤v1→v2 迁移端到端。
  定向复跑 5/0/0。
- **签名细节属实**：mint 前需 pristine seed（HistoryStack placeholder 取
  `instances.first ?? baseInstances.first`，空栈静默 no-op——DECISIONS §六已签注，
  测试走真 load 链兜底）。

### 重点② `.lalb` v1→v2 首迁 + 快照钩子 + FREEZE 一致性

- `schemaVersion = 2` + FREEZE 注释明写「v1 → v2 = the FIRST migration」
  （LibrarySchema.swift:74-79）——checker E6 修正落地；`imagesColumns` 尾 append
  `("default_look_pending", "INTEGER")`（:148，PRAGMA table_info 拼写分立签注属实）、
  CREATE TABLE DDL 尾 append `INTEGER DEFAULT 0`——既有列/DDL 逐 hunk 零改动。
- migrate slot 首填（:437-458）：ONE `BEGIN IMMEDIATE` + 失败 ROLLBACK +
  `from <= 1 && to >= 2` 门 + `addImagesDefaultLookPendingColumn`（table_info
  探针幂等 + ALTER TABLE ADD COLUMN）+ `writeUserVersion(to)`。
- 快照钩子首消费（ProjectFileStore.swift:142-151）：`stored < schemaVersion` 分支
  先 `backup(from:to:allowExisting:false)` 落 `.pre-migrate.bak` 再 migrate——
  v1 预埋 dead pin 转活属实；DefaultLookTests ⑤ 断言 bak 落盘 + 二次 open 幂等。
- 申报外测试随动（LibrarySchemaTests 版本钉 1→2/28→29 列/future=3 + 
  LibraryDocumentTests 三处）= schema bump 必然随动，DECISIONS §七已声明。

### 重点③ Look 四组 13 行零丢失 + colorzones + shadhi 单行

- 零丢失机检：`git show d584835~1` 既有 Look 页恰 13 行（vibrance/velvia/
  monochrome/colorbalancergb/colorzones/skinsmooth/sharpen/highpass/soften/
  localcontrast/equalizer/grain/bloom）——新页 ledger13 断言逐 op 全命中
  （EditorStackRoutingTests.swift:199-213），vibrance→Master、四 DRT→Look 组、
  八 detail→Detail/Texture，count 18 = 13 + 5 catalog 新行。
- colorzones 归 Detail/Texture（checker m1）✅（EditorTabRoute.swift:244 + 测试
  :242-243 明注 m1）；shadhi Tone 页恒 1 descriptor 单行（:202 + 测试 count==1，
  双行分支删除注释承载 `ForEach(id: \.opName)` 冲突因由）✅。

### 重点④ LGG trackball 拖拽派生 = Alcedo UpdateDerived 终式验算

对照 GPL 仓（`AlcedoStudio/alcedo_studio/src/...`，只读）逐式验算：

| 式 | Lightamer 落点 | Alcedo 源 | 结论 |
|---|---|---|---|
| HueToUnitRgb | `ColorWheelsModule.hueToUnitRgb` | `editor_support/modules/color_wheel.cpp:14-34` | **逐行一致**（六段 sector + f 分量） |
| DiscToCdlDelta | `cdlDelta` | `color_wheel.cpp:52-73` | **数学等价**：atan2/2π 负域回绕、减均值零和化、1/(len+kEpsilon) 归一、scale=max(s,0)·r 全同；clamp 点 vs clamp r 等价（方向 atan2 缩放不变） |
| UpdateDerived base/sign | `colorOffset(from:strength:wheel:)` | `editor_cdl_trackball_model.cpp:16-23` + `addUnity`(=id≠Lift)/`invertDelta`(=id==Gamma)（:407-413） | **映射一致**：lift (0)+δ / gamma (1)−δ / gain (1)+δ |
| ClampDiscPoint | `discFrom`（单位圆钳 + view-y 翻转） | `color_wheel.cpp:38-50` + QML 层坐标归一 | 等价（y 翻转 = QML→disc 语义；`length>1` 归一 = `r>1` 归一） |
| strength clamp | `cdlDelta` scale 项 | `UpdateDerived` 首行 `clamp(strength_, 0, kStrengthDefault=0.1)` + UI 态默认 0.1（`cdl_wheel_state.hpp:16`） | **执行批缺失 → 本批修复**（见 findings F1） |
| payload 默认 | `ColorWheelControl()` strength 1.0 / gamma·gain (1,1,1) | `color_wheel_model.hpp:34-50` ColorWheelControl/Payload | **逐字段一致**（disc/strength carried 不进像素数学，双面签注属实） |
| 拖拽语义 | 面板 `write` 同一次写落 disc + 派生 colorOffset（ColorWheelsPanelView.swift:134-146,187-194） | `applyDisc` → `recomputeDerived`（绝对位置） | 一致（live tick 零 history + dragEnd 单 commit = D-H1 惯例） |

### 重点⑤ add 面 12 唯一 op 裁定 + Develop 分支新 UI

- **计数矛盾裁定成立**：plan「恰 14」（= gradeItems() 字面）与「LMT 不在枚举 +
  DRT 四件不在」互斥（gradeItems 14 含 lmt 行 + shadows/highlights 共享 shadhi
  的重复行）；终态 12 唯一 op = 排 lmt（D10 LMT 归 LUT 页绑定语义）+ opName 去重
  （effectiveChain 本就静默合并同 op 同优先级记录，菜单出两条是假选择）——
  DECISIONS §五签注合法，测试按目录 id 逐项断言 12 条。
- add 种子 = identityJSON 快照（shadhi 的 Params() 50/−50 工作点 ≠ identity 0/0，
  checker m5 分立——`templateInstance` 仅 shadhi case 走解码，其余 11 op
  Params() 即 identity；CatalogAddFaceTests 逐 entry 断言字节 == identityJSON）✅。
- **Develop 分支新 UI（checker E4）**：`InspectorView.moduleList` Menu 双作用域
  ——选中层 → catalog 枚举 `addModuleToLayer`；无层 → **Develop section +
  compat section**（`addModuleToBaseChain` 一次 D-H1 commit，undo 一步回——
  testBaseChainAddLandsOneCommit 断言）零 grade-owned 枚举。菜单行双态常显
  （GUI-14 clip 回归防止）。
- 校验缝零 diff：`addModuleToLayer` typed 校验未触碰，NodeOwnershipCatalogTests
  全绿（活体回归）。

### 重点⑥ 申报外 5 文件合理性

| 文件 | 裁定 |
|---|---|
| `LightamerIOP/Sources/ColorWheels/ColorWheelsModule.swift`（+100 行纯函数/常量/resetting） | **合理**——KD-2 钦定落点（「极角换算纯函数落 IOP」），front-matter 漏报，DECISIONS §三声明 |
| `App/.../EditorWorkspaceShellView.swift`（flag 腿 +25 行） | **合理**——KD-5 fallback 条款钦定的开图入口（read_first 6 定位实态：EditorState 零 row 通道），DECISIONS §六声明；读/清各构一次 LibraryStore 轻微冗余（无害，观察项不入账） |
| `App/.../WorkspaceHostView.swift`（controller 传参一行） | **合理**——同上走线 |
| `Tests/.../LibrarySchemaTests.swift`（版本钉随 v2） | **合理**——schema bump 必然随动（V50OrderTests 先例），DECISIONS §七 |
| `Tests/.../LibraryDocumentTests.swift`（版本钉随 v2） | **合理**——同上 |
| `M2-4-0-BUNDLE-MAP.txt`（八 commits 增行） | **合理**——checker E2 登记纪律载体（纪律 6 明写 BUNDLE-MAP 增行），先例同款 |

全部在 SUMMARY diff 边界表 + DECISIONS 对应节声明，无未申报越界。

## Findings

- **F1（minor，本批已修）**：`ColorWheelsModule.cdlDelta` 缺 Alcedo
  UpdateDerived 的 strength 上限 clamp（`clamp(strength_, 0, kStrengthDefault=0.1)`，
  editor_cdl_trackball_model.cpp:18）——payload pristine strength=1.0（payload 层
  默认，color_wheel_model.hpp:36）之下首拖任一轮，派生 colorOffset 幅度 =
  Alcedo 同 disc 位置的 10×（scale 1.0·r vs 0.1·r；Alcedo UI 态默认即 0.1，
  cdl_wheel_state.hpp:16，故 Alcedo 面上不可达此态）。修复 = scale 项
  `min(max(strength, 0), strengthRange.upperBound)`（一行）+ CatalogAddFaceTests
  补 clamp 等价断言（1.0 派生 == 0.1 派生）；修复后 App 364/0/0 + IOP 467/1/0
  复跑全绿。AC#5「拖拽派生 = Alcedo 终式」语义补全；plan 风险节 Manual-Only
  条款豁免的是手感调参，不豁免映射终式偏差（重点④验算条款）。
- **观察（不入缺陷账）**：①面板 strength 滑杆 defaultValue = payload 1.0 在
  0…0.1 量程外顶格显示（双面语义的显示面遗留，Alcedo UI/payload 分立在 Swift
  单面模型下的形态问题）——列入 P3 收口走查清单（新面板走查已挂账）。②
  EditorWorkspaceShellView 读/清 flag 各构造一次 LibraryStore（无害冗余）。

## 复跑记录（独立）

```
BUNDLE|App|364/0/0|peakRSS=1327MB|112s   （声明 364/0/0 ✓；修复后复跑 364/0/0|99s）
BUNDLE|Library|430/4/0|peakRSS=297MB|21s （声明 430/4/0 ✓）
BUNDLE|IOP|467/1/0|peakRSS=7676MB|123s   （声明 467/1/0 ✓；修复后复跑同值）
定向：DefaultLookTests 5/0/0、CatalogAddFaceTests 9/0/0（修复后同值）、
      EditorStackRoutingTests 12/0/0
```

声明 `--all` 终跑 TOTAL|2305/14/0|756s EXIT=0 = 起算基线 2288 + 17 精确
（Routing +3 / CatalogAddFace +9 / DefaultLook +5），MEMFAIL 零触发（峰值
IOP 7798MB < 8192 门）与 BUNDLE-MAP 记载一致。

## 翻账

- REQUIREMENTS **M2GRADE-02** 勾选 + Delivered（LGG trackball UI + Reset wheels，
  M2-5-1 kernel 半边 + M2-5-2 面板半边闭环）。
- REQUIREMENTS **M2GRADE-03** 勾选 + Delivered（默认 look 全链：v1→v2 首迁 +
  flag API + mint + DefaultLookTests）。
- REQUIREMENTS **M2GRADE-01** 面板半边终注（「归 M2-5-2（P2）」→「已交付」，
  Tone/Look 面板 + add 面严格化落地）。
- 本文件落盘 + GOAL-STATE 续接点追加（验收 PASS → M2-5-3）。

## 验收批提交

- `fix(m2-5-2): clamp trackball strength to the alcedo working ceiling`——
  F1 修复（ColorWheelsModule.cdlDelta + CatalogAddFaceTests clamp 断言）。
- `docs(m2-5-2): acceptance verdict PASS + M2GRADE-01/02/03 flip`——本文件 +
  REQUIREMENTS 翻账 + GOAL-STATE 续接点。
