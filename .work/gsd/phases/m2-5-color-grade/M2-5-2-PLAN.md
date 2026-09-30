---
phase: m2-5
plan: "M2-5-2"
title: "Look/Tone 页面板重组（wave 2）——Look 页 Alcedo 四组 IA（Master/Look/Color/Detail+Texture，DisclosureGroup 折叠壳）+ Tone 页目录收敛与 compat 折叠组 + 新件面板 provider 批（LGG 三 trackball + Reset wheels / HLS Selective Color / CAT02 WB / Contrast / White / Black / Tint / Saturation）+ 18 目录 add 面严格化（选中 Grade 按目录枚举 + Develop 作用域收窄——D-M2-5-CONTEXT-4）+ 产品默认 look 注入（.lalb additive 列 default_look_pending + mint 分支，D-M2-5-CONTEXT-8）。渲染管线零改动"
wave: 2
depends_on: ["M2-5-1"]
autonomous: true
requirements: [M2GRADE-01, M2GRADE-03]
files_modified:
  - App/Sources/Lightamer/UI/Shell/EditorTabRoute.swift            # 修改：Tone 页 rows 收敛（Alcedo Tone 七目录 + compat 折叠组五件）+ Look 页 rows 按四组归属重排 + EditorPanelDescriptor 增分组/注记字段（additive）
  - App/Sources/Lightamer/UI/Shell/EditorAdjustmentStackView.swift # 修改：分组壳渲染（panels(for:) 消费宿主）——DisclosureGroup 折叠组 + 「parked until M2-6」注记行渲染
  - App/Sources/Lightamer/State/InspectorState.swift               # 修改：新件 provider 注册（colorWheels/hls/cat02WhiteBalance/contrast/white/black/tint/saturation 八目录）+ IOPPanelProvider 注册表扩展
  - App/Sources/Lightamer/State/EditorState.swift                  # 修改：①addModuleToLayer 枚举面 = GradeCatalog 驱动（选中 Grade → 13+1 Grade 目录；Develop 作用域 → .develop 件 + compat 组，grade-owned 不再向 base 链提供——D4 收窄语义）；②默认 look mint 分支（KD-5：无 .lra 且 flag=1 → pristine seed 之上铸首 Grade 塞三参数 + 清 flag）
  - App/Sources/Lightamer/UI/Inspector/ColorWheelsPanelView.swift  # 新建：LGG 三 trackball（Canvas 自绘圆盘 + DragGesture 写 disc + strength/luminanceOffset 数值滑杆 + Reset wheels 三轮归 identity）
  - App/Sources/Lightamer/UI/Inspector/HlsPanelView.swift          # 新建：Selective Color 面（Target Hue bin 选择 + Hue Shift/Lightness/Chroma/Hue Smoothness 滑杆 ↔ applyTargetEdit 映射消费）
  - App/Sources/Lightamer/UI/Inspector/GradeScalarPanels.swift     # 新建：六件薄滑杆面（CAT02 WB 双滑杆 / Contrast / White / Black / Tint / Saturation——复用既有滑杆组件与 range/step 约定）
  - App/Sources/Lightamer/UI/InspectorView.swift                  # 修改：Develop/未选中态 Add Adjustment 面落点（无层选中分支——新增 UI，KD-4/T6；checker E4 补申报）
  - Resources/Localizable.xcstrings                               # 修改：本批新 UI 键随手键入账（组头/注记/菜单/面板文案——D12；zh 值 P3 收口批补；checker E4 补申报）
  - LightamerCore/Sources/Library/LibrarySchema.swift              # 修改：images 表 additive 列 `default_look_pending INTEGER DEFAULT 0` + schema user_version **v1→v2 首次迁移**（LibrarySchema.swift:7 FREEZE v1、:419-436 migrate slot 空置首填；ALTER TABLE ADD COLUMN 幂等，照 SessionIndexSchema.migrate 形态——checker E6 修正）
  - LightamerCore/Sources/Library/LibraryStore.swift               # 修改：import 路径 INSERT（:380 毗邻）写 default_look_pending = 1（新导入恒 1；无开关——OQ-8 A）
  - Project.swift                                                  # 修改：新测试文件登记（bundle 无 glob——checker E2 纪律）
  - Tests/LightamerTests/EditorStackRoutingTests.swift             # 修改：TAB-MATRIX 对账期望值随 Tone/Look 重组重写（分组断言 + compat 组 + 注记行）
  - .work/gsd/phases/m2-3-ui-shell/M2-3-TAB-MATRIX.md              # 修改：矩阵行随实态同批更新（ Tone/Look 两页分组化后的行账）
  - Tests/LightamerTests/DefaultLookTests.swift                    # 新建（LightamerTestsApp，App 级——mint 分支经 EditorState 实例）：flag=1 无 .lra → 首 Grade 三参数 + flag 清零；有 .lra → 零注入；flag=0 旧导入 → 零注入；新建 grade/reset identity
  - Tests/LightamerTests/CatalogAddFaceTests.swift                 # 新建（LightamerTestsApp）：Add Adjustment 枚举面 = 选中 Grade 时恰 14 Grade 目录项（LMT 归 LUT 页/四 DRT 件不在枚举）；Develop 作用域零 grade-owned 枚举
  - .work/gsd/phases/m2-5-color-grade/M2-5-2-SUMMARY.md            # 新建（收口任务）
  - .work/gsd/phases/m2-5-color-grade/M2-5-2-DECISIONS.md          # 新建（收口任务）
  - .work/GOAL-STATE.md                                            # 续接点追加（收口任务）
  - .work/LESSONS.md                                               # 如踩坑
---

# Plan M2-5-2 — 面板重组 + 严格面 + 默认 look（App 层 wave）

> **性质**：UI/接线 plan——渲染管线零改动（`LayerCompositeDriver.swift`/`PixelPipe
> .swift`/`PipeCacheKey.swift` 零 diff 回归红线）。四块交付：①**Look 页四组 IA**（§2.3
> Master/Look/Color/Detail+Texture 折叠壳）与 **Tone 页收敛**（Alcedo Tone 目录为主面 +
> D6 独有件 compat 折叠组）；②**新件面板八 provider**（P1 七件八 op 的编辑面——唯一
> 全新控件形态 = LGG trackball，其余复用滑杆/分段卡组件）；③**18 目录 add 面严格化**
> （D4 收窄：add 枚举按 owner 过滤，Develop 作用域不再提供 grade-owned 目录项）；④
> **默认 look 注入**（M2GRADE-03：+1.5 EV / contrast +15 / saturation 1.3，仅新导入，
> `.lra` 缺席 = 未编辑不变量零破坏）。规格锚点 = D-M2-5-CONTEXT-4/5/8/9/10（不得重开）
> + Feature-map §2.1/§2.3 + REQUIREMENTS M2GRADE-01/03。

## 已定裁决（不得重开）

- **D-M2-5-CONTEXT-4（OQ-4 A）**：base 层宽容现状 + 新增面收窄——历史 base 链
  grade-owned 实例保留可编辑可渲染（零迁移零拒载）；新 add 面在 Develop 作用域只枚举
  `.develop` 件 + compat 折叠组；同一面板双作用域（未选中/Develop = base 链既有实例，
  选中 Grade = 该层 chain——M2-4 OQ-9-A 既有 `InspectorEditSession` 作用域，本 plan
  零会话层改动）。
- **D-M2-5-CONTEXT-5（OQ-5 A）**：CAT02 WB = Look 页 Color 组；`TemperatureModule`
  行从 Tone 页摘除、归 base 链 compat 折叠组（模块保留可编辑，routing Tone 页 −1 行）。
- **D-M2-5-CONTEXT-8（OQ-8 A）**：默认 look = per-image 标记列 + mint 时分支注入；
  `.lalb` additive 列 `default_look_pending`；不写初始 sidecar（pristine 不变量）；
  无开关（关闭 = 编辑掉三参数，非破坏性）。
- **D-M2-5-CONTEXT-9（OQ-9 A）**：明细四件归属锁死（`.drtPost`）+ Look/Look 组占位 +
  诚实文案「applies pre-DRT for now — moves post-DRT with M2-6」；Equalizer=Clarity
  单滑杆 UI 简化 = 面板呈现决策，参数面不动。
- **D-M2-5-CONTEXT-10（OQ-10 A）**：Look 页四组重组 + 目录 provider 化；Tone 页收敛
  （levels/colisa/colorcontrast/toneequal/temperature 移 compat 折叠组，不删除）；
  LMT 归 LUT 页不动；每组独立页签 = 否决项（七页签契约）。

## 关键设计决策（planner 裁决，执行中不重开）

### KD-1 分组 IA = EditorPanelDescriptor additive 扩展 + 折叠组壳渲染

```swift
// EditorTabRoute.swift（additive，既有行语义零破坏——旧三参构造默认值补齐）
struct EditorPanelDescriptor {
    // 既有：opName / tab / advanced
    var group: PanelGroup?          // nil = 无组（compat 组行用 advanced 既有位）
    var note: StaticString?         // 「parked until M2-6」式注记（D9 文案）
}
enum PanelGroup: String, CaseIterable {   // Look 页四组 + Tone 页 compat 组
    case master, look, color, detailTexture
    case compat   // Tone 页「Darktable 兼容件」折叠组
}
```

- **一致性维持答案（KD 必答）**：分组是**纯呈现投影**——`panels(for:)` 返回序即组内
  序，`EditorAdjustmentStackView` 渲染时按 `group` 分桶（nil group 行按既有平铺路径）；
  无独立分组状态源，漂移在构造上不可能。`advanced: true` 既有位继续承载 compat 组内
  折叠语义（Geometry 页先例），`PanelGroup.compat` 只用于 Tone 页组头。
- **Look 页四组成员（§2.3 字面 + 18 目录归位）**：
  - **Master**：Saturation / Vibrance
  - **Look**（D9 占位组）：Clarity(=equalizer) / Sharpen / Film Grain(=grain) /
    Halation(=bloom)，四行带 `note`（pre-DRT 注记）；既有 detail 五件的
    highpass/soften/localcontrast 与 velvia/monochrome/colorbalancergb/**colorzones**/
    skinsmooth → **Detail/Texture 组**（D6 收纳，§2.3 的 Detail/Texture 落点；
    checker m1：colorzones 归此组——既有 Look 13 行零丢失对账含它）
  - **Color**：White Balance(=cat02WhiteBalance) / Selective Color(=hls) /
    Color Wheels(=colorWheels) / Tint
  - **Detail/Texture**：见上；**LMT 不在 Look 页**（归 LUT 页既有行，D10 字面）
- **Tone 页收敛后主面（checker m2 钉单行）**：Exposure / Contrast / White / Black /
  **Shadows / Highlights（=shadhi 单行双滑杆）** / Curve(=tonecurve)——**UI 六行**；
  Alcedo 目录仍两项目录项（shadows/highlights 共享 shadhi 一 op，`panelExposures`
  双键暴露在 GradeCatalog 照旧声明），**UI 钉死单行「Shadows / Highlights」双滑杆**
  （面板内两滑杆 = 两目录项的最小忠实映射）；**双行分支删除**——同 opName 双
  descriptor 在既有 `ForEach(id: \.opName)` 面静态 id 冲突（duplicate-ID 静态面），
  不走双行、无选型残留；shadhi.Params 零改动（sidecar 兼容零风险）。
  **compat 折叠组**：levels / colisa / colorcontrast / toneequal /
  temperature（五件 D6 收纳，模块可编辑不删除）。
- **CAT02 WB 面板页内提示**（§2.3 Alcedo 文案语义）：「Creative white balance under
  the AP1 assumption — camera WB lives on the RAW Decode page」（zh 收口批补）。

### KD-2 LGG trackball = SwiftUI Canvas 自绘 + DragGesture，极角映射纯函数落 IOP

- 三 trackball（lift/gamma/gain）各自：圆盘（Canvas 画环 + 十字 + disc 点）+
  DragGesture 把触点换算 disc `{x,y}`（单位圆内钳制）+ strength/luminanceOffset
  数值滑杆。**不做 Metal 自绘**（D-OQ-2 A 论证沿用：节点数个位数，Canvas 帧成本
  可忽略）。
- **极角↔disc 换算 = 纯函数落 `ColorWheelsModule`（IOP）**：
  `discFrom(point:relativeTo:radius:)` / `pointFrom(disc:radius:)`——UI 只做坐标
  转发，换算数学可单测（P1 已建立 IOP 测试面，本 plan 消费同模式）。disc 语义
  （极角→色度方向、半径→幅度）以 P1 DECISIONS 签注的 kernel 终式为准。
- **Reset wheels**：三轮置 identity（lift 全零 / gamma·gain colorOffset (1,1,1)），
  identity 快照消费 `GradeCatalog` colorWheels 项的 `identityJSON`（P1 单源）；
  每轮独立 reset（双击轮）+ 三轮总 reset 按钮两组行为都要。

### KD-3 HLS Selective Color 面 = UI 编辑选中 bin，8-bin 经 Target Hue 步进遍历

- 面 = Target Hue 选择（8 bin 档位：0°/45°/…/315°，分段卡或色环；Alcedo
  `Target Hue %1°` 文案语义）+ 四滑杆 Hue Shift / Lightness / Chroma / Hue
  Smoothness ↔ `applyTargetEdit(params:targetBin:dh:dl:ds:)`（P1 交付纯函数）；
  **面板零新映射逻辑**（UI↔模型映射全部在 IOP 纯函数，面板只是绑定）。
- Hue Smoothness 滑杆写选中 bin 的 `hRangeTable[bin]`；hlsAdj/targetHls 单 target
  字段的同步语义按 P1 DECISIONS 签注的映射终式。

### KD-4 add 面严格化 = 枚举源从 registry 平面切 GradeCatalog 过滤，校验缝零改动

- **选中 Grade 态**：「Add Adjustment」枚举 = `GradeCatalog.gradeItems()`（14 项：
  13 Grade 件 + Tint）；**Develop/未选中态**：枚举 = `.develop` 件 + compat 折叠组
  （`.grade` 项不出现——D4 收窄的完整表达）。
- **枚举 UI 落点（checker E4 明写）**：Develop/未选中态 add 面 = **`InspectorView`
  无层选中分支（新增 UI——既有宿主无此分支，T6 补建）**；选中 Grade 态枚举落点 =
  既有 Add Adjustment 菜单宿主（执行期定位，若在 EditorAdjustmentStackView 内则随
  T1 壳一并改——files_modified 已申报该文件）。
- `addModuleToLayer` 既有 typed 校验缝（M2-4-1 交付）**零改动**——枚举面已经不让
  非法组合出现，校验缝只作为最后防线（防 programmatic 调用）。严格面激活的语义半径 =
  **新增动作**；历史加载/undo/复原零校验（既有惯例）。
- `.drtPost` 四件在任何作用域的 add 枚举都不出现（M2-6 面）——typed error 路径保留
  既有测试覆盖。

### KD-5 默认 look mint 分支 = EditorState 载入单点分支，pristine 不变量零破坏

```
EditorState.load（sidecar probe 之后）：
  .lra 存在            → 既有 restore 路径，零改动（restore 恒压过 flag）
  .lra 缺席 && flag==1 → resetHistoryForNewImage 后内存 mint（KD-5，checker E5 重写）：
       单个 AdjustmentLayer **内存构造**——chain 三 instance（exposure +1.5 /
         contrast +15 / saturation 1.3，GradeCatalog.defaultLook 解码 params，
         经既有 setParams 同款编码路径）
       + **单次提交**（一笔 history entry）经「跳过 persist 调度」内部通道
         （EditorState mint 专用入口，显式短路 2s debounce 调度——非逐 apply
           调度、非靠时序巧合）
       + 清 flag（LibraryStore UPDATE images SET default_look_pending=0）
       ——零 sidecar 落盘调度：**mint 后 flushNow() 亦无 .lra**（机检断言），
         「.lra 缺席 = 未编辑」不变量构造上成立
  .lra 缺席 && flag==0 → 既有 pristine 路径，零改动
```

- **flag 读点**：EditorState 不直连 SQLite——经 `LibraryStore` 查询面
  （`defaultLookPending(imageRowID:) -> Bool` + `clearDefaultLookPending(imageRowID:)`，
  additive API）；编辑器侧 imageRowID 的传递沿 M2-2 既有 image→row 关联面（执行期以
  read_first 6 定位实态；若编辑器会话无 row 关联现成通道，fallback = flag 消费点移到
  打开图入口（LibraryPanels/LibraryProjectController 打开动作传 `Bool` 注入
  EditorState.load），语义等价、DECISIONS 签注选型）。
- **三参数施加形态（checker E5 重写）**：首 Grade = **单个 AdjustmentLayer 内存
  构造 + 单次提交**——chain 三 instance（exposure +1.5 / contrast +15 /
  saturation 1.3，exposure 复用既有件 = P1 KD-9 单源）；**undo 一步回 pristine 由
  单次提交构造上保证**（用户「不要默认 look」= 一次 undo 或删 Grade，非破坏性）；
  **「跳过 persist 调度」内部通道** = mint 期间 persist 调度零发生——证明面 =
  DefaultLookTests 的 flushNow 断言，非注释性承诺。用户新建 grade / reset 恒
  identity（`GradeCatalog.identityJSON` 单源，与默认 look 分立——M2GRADE-03 字面）。
- **has_edits 投影**：flag=1 且未编辑图在库投影 `has_edits=0`（`.lra` 缺席判据不
  变——`LibraryStore` has_edits 投影零改动，flag 列独立于投影）。

### KD-6 LibrarySchema v1→v2 首次迁移 = 新列幂等迁移（checker E6 修正）

- **版本事实**：`LibrarySchema.swift:7` FREEZE v1（`schemaVersion = 1`），
  `:419-436` migrate slot **空置**（v1 无历史版本可迁）——本次 = **v1→v2 首次
  迁移、该 slot 首填**（非「v2→v3 惯例」，front-matter 同批修正）。
- 形态照 slot 注释钦定的 `SessionIndexSchema.migrate` 模板：ONE `BEGIN IMMEDIATE`
  + 失败 ROLLBACK + `writeUserVersion(2)`；ProjectFileStore dispatch 侧迁移前
  `sqlite3_backup` 快照钩子既有（v1 预埋），本次首次消费。
- `imagesColumns` 尾部追加 `("default_look_pending", "INTEGER DEFAULT 0")` +
  旧库打开路径 `ALTER TABLE ADD COLUMN` 幂等补列；既有列序/DDL 零改动
  （append-only）。

## read_first

1. `.work/gsd/phases/m2-5-color-grade/M2-5-CONTEXT.md`——D4/5/8/9/10 + Ruling。
2. `App/Sources/Lightamer/UI/Shell/EditorTabRoute.swift:100-190`——routing 正本 +
   descriptor 形态 + specialContent 面。
3. `App/Sources/Lightamer/UI/Shell/EditorAdjustmentStackView.swift:140-200`——
   panels(for:) 消费宿主（分组壳渲染落点）。
4. `App/Sources/Lightamer/State/InspectorState.swift:140-180`——provider 注册表 +
   `InspectorEditSession` 层作用域（新 provider 挂接缝）；同批读
   `App/Sources/Lightamer/UI/InspectorView.swift`——inspector 宿主结构（**无层选中
   分支 = Develop 态 add 面落点，checker E4**）。
5. `App/Sources/Lightamer/State/EditorState.swift:95-130,380-430,600-650`——pristine
   seed / sidecar restore / addModuleToLayer / apply(NodeGraphCommand) 缝。
6. `LightamerCore/Sources/Library/LibraryStore.swift:360-420`（import INSERT +
   查询面惯例）+ `LibrarySchema.swift:120-160`（additive 升版先例）。
7. `.work/gsd/phases/m2-5-color-grade/M2-5-1-DECISIONS.md`——P1 签注的 kernel 终式与
   HLS 映射终式（trackball 换算/Selective Color 绑定的对照源）。
8. `.work/gsd/phases/m2-3-ui-shell/M2-3-TAB-MATRIX.md` + `Tests/LightamerTests/
   EditorStackRoutingTests.swift`——对账机检的期望值形态。

## 纪律（强制）

1. **提交纪律**：每任务独立提交（Conventional Commits 全英文、subject ≤72 字符祈使
   句、body 写 what+why + 同批 md 清单）；只 add 本任务申报文件；**不 push**；git add
   用 `.work/gsd/...` 真路径。
2. **构建纪律**：`caffeinate -dis` 包裹一切构建；不加 `-derivedDataPath`；新建文件后
   同 commit `tuist generate`。
3. **测试纪律**：单测命令 = `Scripts/test-direct.sh '<Class>'`；判据 = Executed 计数
   行 + failures 行双读（L028）。**回归基线 = M2-5-1 收口后的运行期总数**（M2-5-1
   SUMMARY 记载；起算基线 2240/14skip/0fail）；每任务全套 suite 绿。**全套跑法 =
   `Scripts/test-direct.sh --all`**；跑前必须向 orchestrator SendMessage 报备；RSS
   ≥8G = MEMFAIL 机检内置，触发即记 E3 不自行重试超两次。在案 flake 隔离复跑 ×3 归因
   入 SUMMARY。
4. **边界纪律**：每任务边界检查 `.work/config.toml [gsd]`（`auto`/`paused`）。
5. **架构红线**：`LayerCompositeDriver.swift`/`PixelPipe.swift`/`PipeCacheKey.swift`
   零 diff；`LightamerSidecar.swift` 零触（默认 look 不写初始 sidecar 是 D8 字面）；
   `LibrarySchema.swift` 只许 append-only additive（既有列/DDL 零改动）；既有面板
   （exposure/shadhi/vibrance/tonecurve/lut3d provider 面）行为零回归——本 plan 只
   重排 routing 与加新 provider；GPL 参考只读。
6. **测试登记纪律（checker E2）**：新建测试文件**同 commit** 登记 `Project.swift`
   （LightamerTestsApp）+ BUNDLE-MAP 增行。DefaultLookTests/CatalogAddFaceTests 均 =
   **APP**（EditorState 实例）。运行期总数基线相应上移。
7. **收口核对（checker 教训②）**：T8 `git diff --stat` 与 front-matter 逐文件核对，
   越界 = 违约。
8. **zh 键随手键纪律（D-M2-5-CONTEXT-12 A）**：新 UI 键随手 `String(localized:)`
   入 `Resources/Localizable.xcstrings`（front-matter 已申报——checker E4），zh 值
   滞后允许；本 plan 新键入账（键名清单进 SUMMARY），phase 尾 P3 收口
   `Scripts/zh-audit.py --check` 对账补齐。

## Tasks

### T1 Tone 页收敛 + compat 折叠组 + TAB-MATRIX 同批

- **read_first**：上列 2/3/8。
- **action**
  1. `EditorTabRoute.swift`：descriptor additive 字段（KD-1）+ Tone 页 rows 重写
     （主面**六行**：exposure/contrast/white/black/shadhi 单行「Shadows /
     Highlights」双滑杆/tonecurve——checker m2 钉单行，双行分支删除；compat 组
     五件：levels/colisa/colorcontrast/toneequal/temperature——temperature 摘除
     主面即 D5 的 Tone −1 行）。
  2. `EditorAdjustmentStackView.swift`：分组壳渲染（组头 + 折叠 + advanced/compat
     语义沿用既有 Geometry 页路径）。
  3. `EditorStackRoutingTests.swift` 期望值重写 + `M2-3-TAB-MATRIX.md` 同批更新
     （Tone 页新行账；Look 页留 T2）。
- **验收标准**
  - [ ] Tone 页主面六行（shadhi 单行双滑杆，m2）+ compat 五件断言绿；routing 对账
        机检绿；compat 组内件面板可开可编辑（既有 provider 零回归）。
  - [ ] 渲染红线三文件零 diff。
  - [ ] 全套回归 `0 fail`。

### T2 Look 页四组壳 + 既有行归组 + D9 占位注记

- **read_first**：上列 1/2/3。
- **action**
  1. Look 页 rows 按 KD-1 四组重排（Master/Vibrance+既有 velvia 等；Look 组四 DRT
     件带 note；Color 组挂新件行占位——T3/T4/T5 provider 到位前先挂既有 fallback 面
     或延后挂行，**本任务只动 routing 与组壳，不写新面板**）；Detail/Texture 组收
     detail 族 + colorzones（checker m1）。
  2. D9 注记渲染（`note` 字段 → 组内行下标文案）。
  3. `EditorStackRoutingTests` + `M2-3-TAB-MATRIX.md` Look 页部分同批（分组断言：
     四组头 + 组内行序 + note 行）。
- **验收标准**
  - [ ] 四组断言绿（组头/成员/序/note）；LMT 不在 Look 页断言绿；既有 Look 页 13 行
        零丢失（全部归组或留 compat 位——逐行对账注释）。
  - [ ] 全套回归 `0 fail`。

### T3 新件标量面六 provider（CAT02 WB / Contrast / White / Black / Tint / Saturation）

- **read_first**：上列 4/7 + P1 各件 Params（range/step/默认值正本）。
- **action**
  1. 新建 `GradeScalarPanels.swift`：六件薄滑杆面——CAT02 WB（temperature
     2000–15000 step 1 + tint ±150）/ Contrast（±100 step 1）/ White / Black
     （±100）/ Tint（±100）/ Saturation（0–4 step 0.01）；范围/步长/默认值从 P1
     Params 常量引用（零手抄漂移）。
  2. `InspectorState.swift` provider 注册（八目录中六件）+ Look/Tone 页对应行挂面
     （Contrast/White/Black 在 Tone 主面；CAT02 WB/Tint/Saturation 在 Look Color/
     Master 组）。
  3. CAT02 WB 页内提示文案（KD-1）。
- **验收标准**
  - [ ] 六面开合/拖杆/Reset/层作用域（选中 Grade → 写该层 chain；Develop 态 → base
        既有实例）走查绿；滑杆范围与 P1 Params 断言一致（测试内反射或常量引用）。
  - [ ] 全套回归 `0 fail`。

### T4 LGG trackball UI + Reset wheels

- **read_first**：上列 4/7（KD-2 终式对照）+ P1 `ColorWheelsModule`（disc 换算纯
  函数面）。
- **action**
  1. 新建 `ColorWheelsPanelView.swift`：三 trackball（KD-2 全量：Canvas 圆盘 +
     DragGesture → `discFrom` 纯函数 + strength/luminanceOffset 滑杆 + 每轮双击
     reset + Reset wheels 总按钮 → `identityJSON`）。
  2. `InspectorState` provider 注册 + Look 页 Color 组「Color Wheels」行挂面。
  3. `Tests` 追加（挂 `CatalogAddFaceTests` 同文件或既有 IOP 面文件——**disc 换算
     纯函数测试已在 P1**，本任务补 UI 态机检：三轮独立 reset / 总 reset 后 params
     与 identityJSON 逐字节相等——经 EditorState 实例断言）。
- **验收标准**
  - [ ] trackball 拖写 disc + 滑杆 + 双组 reset 行为断言绿；reset 后 identity 逐
        字节。
  - [ ] 全套回归 `0 fail`。

### T5 HLS Selective Color 面

- **read_first**：上列 4/7（P1 `applyTargetEdit` 终式）。
- **action**
  1. 新建 `HlsPanelView.swift`：Target Hue 8-bin 选择 + 四滑杆（KD-3 全量；面板零
     映射逻辑）。
  2. `InspectorState` provider 注册 + Look 页 Color 组「Selective Color」行挂面。
  3. UI 态机检：bin 切换 → 面板值反映该 bin 现值；滑杆回写经 `applyTargetEdit`
     （与 P1 Float64 参考同源断言）。
- **验收标准**
  - [ ] 8 bin 切换/四滑杆绑定/回写断言绿。
  - [ ] 全套回归 `0 fail`。

### T6 18 目录 add 面 + Develop 作用域收窄

- **read_first**：上列 5（addModuleToLayer/apply 缝）+ P1 GradeCatalog。
- **action**
  1. `EditorState.swift`：add 枚举面切 `GradeCatalog` 过滤（KD-4：Grade 态 14 项 /
     Develop 态 .develop 件 + compat 组）。**枚举 UI 落点（checker E4 明写）**：
     Develop/未选中态 add 面 = **`InspectorView` 无层选中分支（新增 UI，本任务
     补建）**——枚举列表 + compat 组头，文案键随手 `String(localized:)` 入
     Localizable.xcstrings；选中 Grade 态枚举落点 = 既有 Add Adjustment 菜单宿主
     （执行期定位，若在 EditorAdjustmentStackView 内则随 T1 壳一并改——
     files_modified 已申报该文件）。
  2. 校验缝零改动确认（既有 `NodeOwnershipCatalogTests` 全绿 = 活体回归）。
  3. 新建 `Tests/LightamerTests/CatalogAddFaceTests.swift`：Grade 态枚举恰 14（逐
     目录 id 断言 + LMT/四 DRT 件不在列）；Develop 态枚举零 `.grade` 项（temperature
     在列、exposure 不在列）；`addModuleToLayer(.drtPost)` typed error 路径既有断言
     保持。
  4. 测试登记两处（APP）。
- **验收标准**
  - [ ] 枚举矩阵断言绿；校验缝零 diff；历史 base 链 grade-owned 实例编辑路径回归绿
        （既有 suite 证）。
  - [ ] 全套回归 `0 fail`。

### T7 默认 look 注入

- **read_first**：上列 5/6 + `LightamerCore/Sources/Graph/NodeGraphCommand.swift`
  （AddClean 命令面）。
- **action**
  1. `LibrarySchema.swift`：**v1→v2 首次迁移** + additive 列（KD-6——migrate slot
     首填，照 SessionIndexSchema.migrate 形态，checker E6）。
  2. `LibraryStore.swift`：import INSERT 写 1（KD-5）+ 查询/清除 additive API
     （`defaultLookPending`/`clearDefaultLookPending`）。
  3. `EditorState.swift`：mint 分支（KD-5 调用链图；**单个 AdjustmentLayer 内存
     构造（chain 三 instance）+ 单次提交 + 「跳过 persist 调度」内部通道** + 清
     flag；restore 腿零改动——checker E5 重写形态，弃逐 apply 面）。
  4. 新建 `Tests/LightamerTests/DefaultLookTests.swift`：**双断言（checker E5）**——
     ①mint 后 `flushNow()` → 磁盘无 `.lra`（persist 零调度证明）；②undo 一步 →
     pristine（单次提交证明）。外加四态：flag=1 无 .lra → 首 Grade 三参数值断言
     （+1.5/+15/1.3 逐参数）+ flag 清零 + 第二次载入零重复注入；有 .lra → 零注入
     （restore 压过 flag）；flag=0 → 零注入；用户新建 grade = 空 chain（identity）。
     测试登记两处（APP）。
- **验收标准**
  - [ ] mint 分支四态断言 + 双断言（flushNow 无 .lra / undo 一步 pristine，E5）
        全绿；pristine 不变量（`.lra` 缺席未编辑图零 sidecar 落盘）断言绿；
        `LightamerSidecar.swift` 零 diff。
  - [ ] 全套回归 `0 fail`。

### T8 收口——SUMMARY/DECISIONS + 续接点

- **read_first**：本 plan AC 表 + `.work/GOAL-STATE.md` 续接点节。
- **action**
  1. AC 逐条机检 + 全套回归终跑（`--all` 前报备；计数入 SUMMARY）。
  2. 落盘 `M2-5-2-SUMMARY.md`（测试数变化/新 UI 键名清单/flag 消费点选型签注/四组
     行账终表）+ `M2-5-2-DECISIONS.md`（KD 执行确认 + 偏差归因）。
  3. `.work/GOAL-STATE.md` 续接点追加（M2-5-2 完成 + 下一步 = M2-5-3）；LESSONS 如
     踩坑。
  4. `git diff --stat` 核对边界（纪律 7）。
- **验收标准**
  - [ ] AC 表全绿；SUMMARY/DECISIONS/GOAL-STATE 同批落盘；diff 边界无越界文件。

## 验收标准（AC 总表，逐条可机检）

| # | AC | 机检方式 |
|---|---|---|
| 1 | Tone 页主面 = Alcedo 七目录、**UI 六行**（exposure/contrast/white/black/**shadhi 单行 Shadows/Highlights 双滑杆**——m2/curve）+ compat 折叠组五件（levels/colisa/colorcontrast/toneequal/temperature）；temperature 主面摘除 | EditorStackRoutingTests 重写断言 |
| 2 | Look 页四组 IA（Master/Look/Color/Detail+Texture）+ 组内行账 + LMT 不在 Look 页 + D9 四件 note 注记 | EditorStackRoutingTests 分组断言 |
| 3 | TAB-MATRIX 文档与代码实态一致（两页分组化后） | `M2-3-TAB-MATRIX.md` 对照机检（既有对账测试口径） |
| 4 | 新件八 provider 注册且面板范围/默认值与 P1 Params 一致；层作用域双态（Grade chain / base 链）行为保持 | 走查 + InspectorState 注册断言（测试可达面） |
| 5 | trackball：disc 换算纯函数（P1）+ 双击 reset + Reset wheels → identityJSON 逐字节 | UI 态机检（EditorState 实例） |
| 6 | Selective Color：bin 切换 + 四滑杆 ↔ `applyTargetEdit`（零面板内映射逻辑） | UI 态机检 |
| 7 | add 面矩阵：Grade 态恰 14 / Develop 态零 .grade / LMT·四 DRT 件不在任何 add 枚举 / 校验缝零 diff | CatalogAddFaceTests + `git diff` |
| 8 | 默认 look：flag=1 无 .lra → 首 Grade 三参数（+1.5/+15/1.3）+ flag 清零 + 不重复注入；有 .lra / flag=0 → 零注入；新建 grade/reset 恒 identity；**双断言（E5）：mint 后 flushNow 磁盘无 .lra（persist 零调度）+ undo 一步回 pristine（单次提交）**；`.lra` 缺席未编辑零 sidecar 落盘 | DefaultLookTests |
| 9 | `.lalb` **v1→v2 首次迁移**（E6）：旧库幂等补列（ALTER TABLE ADD COLUMN，SessionIndexSchema.migrate 形态）+ 既有列/DDL 零改动 + user_version=2 + 迁移前快照钩子消费 | DefaultLookTests 迁移断言 + `git diff LibrarySchema.swift` 逐 hunk |
| 10 | 渲染红线：LayerCompositeDriver/PixelPipe/PipeCacheKey/LightamerSidecar 零 diff | `git diff --name-only` 断言 |
| 11 | 全套回归 0 fail（基线 = M2-5-1 收口总数 + 本批新增） | test-direct.sh --all BUNDLE 行双读 |
| 12 | diff 边界 == 申报文件集；新测试登记闭环（两文件 × Project.swift + BUNDLE-MAP） | `git diff --stat` + `git grep` 双命中 |

## 风险与边界

- **shadhi 行形态（已钉死，checker m2）**：Tone 页单行「Shadows / Highlights」双
  滑杆——双行方案**删除**（同 opName 双 descriptor 在 `ForEach(id: \.opName)` 静态
  id 冲突 + effectiveChain dedupe by (opName, multiPriority) 的吞行风险）；Alcedo
  两目录项、`panelExposures` 双键声明的模型面不变。无选型残留。
- **flag 消费点的 row 关联通道**：编辑器会话若无现成 imageRowID 通道，按 KD-5
  fallback（打开入口注入 Bool）——语义等价已预声明，不构成返工面。
- **Look 页新件行在 T2 先挂、provider T3-T5 才到位**：组壳先行的窗口期出现无面行——
  T2 action 明确「占位行延后挂」规避；若组内行必须整组交付，T2/T3-T5 顺序内交换
  （routing 改动合入 T3 批），DECISIONS 签注。
- **默认 look 与 M2DIS-04 pristine-decode 腿**：mint 分支在 pristine seed 之后铸
  Grade——pristine decode 腿（无 sidecar 即 pristine 渲染）零触碰；风险集中在
  「首 Grade 铸造时机与 decode 完成回调的竞态」——mint 是**内存文档操作（单个
  AdjustmentLayer 构造 + 单次提交 + 跳过 persist 调度，checker E5 形态；与 decode
  异步）**，零竞态面；测试以真 load 链断言兜底。
- **trackball 手感（Manual-Only）**：拖拽阻尼/灵敏度不设机检门（无基线），走查清单
  入 P3 收口观察项；交互参数调整不视为返工。

## 提交约定

- T1 `feat(app): tone page alcedo catalog and compat group`
- T2 `feat(app): look page four group ia with drt placeholder notes`
- T3 `feat(app): scalar panels for six new grade ops`
- T4 `feat(app): lift gamma gain trackball panel with reset wheels`
- T5 `feat(app): selective color panel over hls 8-bin model`
- T6 `feat(app): catalog driven add face with develop scope narrowing`
- T7 `feat(app): default look injection for new imports`
- T8 `docs(m2-5): close out plan 2 panels and default look`
- 全英文 Conventional Commits；body 写 what+why + 同批同步的 md 清单；不 push。

## Checker 回注记录（2026-09-30）

checker 判 FAIL（8E+6M）后本 plan 落地项：

- **E4（front-matter/action 补锚点）**：增 `App/Sources/Lightamer/UI/InspectorView.swift`
  + `Resources/Localizable.xcstrings` 两行申报；KD-4 增「枚举 UI 落点」bullet、
  T6 action 1 明写 **Develop 态 add 面落点 = InspectorView 无层选中分支（新增
  UI）**；read_first 4 + 纪律 8 同步（xcstrings 为新键入账申报文件）。
- **E5（默认 look mint 重写）**：KD-5 弃「AddClean + 依次 apply 三参数」面，改
  **内存构造单个 AdjustmentLayer（chain 三 instance）+ 单次提交 + 「跳过 persist
  调度」内部通道**（EditorState mint 专用入口显式短路 debounce）；DefaultLookTests
  **双断言** = ①mint 后 `flushNow()` → 磁盘无 `.lra`（persist 零调度证明）+
  ②undo 一步 → pristine（单次提交证明）；T7 action 3/4、AC#8、风险节同步。
- **E6（.lalb 版本修正）**：front-matter + KD-6 重写为 **v1→v2 首次迁移**——
  `LibrarySchema.swift:7` FREEZE v1、`:419-436` migrate slot 空置**首填**（非
  「v2→v3 惯例」）；`ALTER TABLE ADD COLUMN` 幂等，照 `SessionIndexSchema.migrate`
  形态（ONE BEGIN IMMEDIATE + ROLLBACK + writeUserVersion(2) + 迁移前快照钩子）；
  T7 action 1、AC#9 同步。
- **m1（colorzones 归组）**：KD-1 Detail/Texture 组成员补 colorzones；T2 action 1
  同步（既有 Look 13 行零丢失对账含它）。
- **m2（shadhi 钉单行）**：KD-1/T1/AC#1 钉死 Tone 页**单行「Shadows / Highlights」
  双滑杆**（UI 六行），**双行分支删除**（同 opName 双 descriptor 在
  `ForEach(id: \.opName)` 静态 id 冲突）；风险节改「已钉死，无选型残留」；
  `panelExposures` 双键模型面不变。
