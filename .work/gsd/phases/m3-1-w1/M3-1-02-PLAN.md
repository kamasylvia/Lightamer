---
phase: m3-1
plan: "M3-1-02"
title: "YIYIN-09 yiyin sheet 预览拖拽（wave 2）——sheet 自身双方向调尺寸（OQ-5①：右/下缘分割线 width+height 双轴）+ 上游 PR #126 五语义逐条移植（双重钳制 / 比例持久化只在松手 3 位小数 / 拖动中零 history 零重算 / 容器 ResizeObserver 等效 onGeometryChange / 实时尺寸读数）+ ratio 两键 UserDefaults 注入式 + 走查与翻账"
wave: 2
depends_on: ["M3-1-01"]
autonomous: true
requirements: [YIYIN-09]
estimated_tests: "+4..6"
test_bundles: [App]
files_modified:
  - App/Sources/Lightamer/UI/Shell/WorkspaceHostView.swift   # 修改：YiyinTopBarSheet（:1216-1285）——固定 frame（:1273）改 ratio 驱动 + 双分割线 handle + DragGesture + 双重钳制 + 松手持久 + 读数 + onGeometryChange 容器跟随 + AX ids
  - App/Sources/Lightamer/Yiyin/YiyinSheetSizing.swift       # 新建：钳制/换算纯逻辑（px 界 ∩ 比例域 + ratio↔px 双向 + 3 位小数量化）——App 级纯函数可单测
  - App/Sources/Lightamer/State/YiyinSheetMetrics.swift      # 新建：ratio 两键读写面（注入式 defaults，KD-4 惯例——body 零 UserDefaults 直读）
  - Resources/Localizable.xcstrings                          # 修改：分割线 AX label 键 2 枚 append 尾部
  - Tests/LightamerTests/YiyinSheetSizingTests.swift         # 新建（App）：钳制双域交/两端终端值/量化 roundtrip/键缺席默认 = 现状 420×560
  - Project.swift                                            # 修改：新测试文件登记（L041 generate 批尾）
  - .work/gsd/phases/m2-4-0-test-bundles/M2-4-0-BUNDLE-MAP.txt  # 修改：增行登记（E2）
  - .work/gsd/phases/m3-1-w1/M3-1-02-SUMMARY.md              # 新建（收口任务）
  - .work/gsd/phases/m3-1-w1/M3-1-02-DECISIONS.md            # 新建（收口任务）
  - .work/gsd/REQUIREMENTS.md                                # 修改：YIYIN-09 勾选 + Delivered 注记（T3）
  - AGENTS.md                                                # 修改：UserDefaults 键登记段补 `yiyin.sheet.widthRatio` / `yiyin.sheet.heightRatio` 两键（T3）
  - .work/GOAL-STATE.md                                      # 修改：续接点追加（追加式）
  - .work/gui-acceptance/m3-1/                               # 新建：拖拽走查证据（截图 + MANIFEST）
  - .work/LESSONS.md                                         # 如踩坑
---

# Plan M3-1-02 — YIYIN-09 yiyin sheet 拖拽调尺寸

> **性质**：S 规模纯 UX mini-plan（REQUIREMENTS :278 YIYIN-09；上游 PR #126 `a7ab9f8`，
> fork `f8de57a` 已同步）。映射方案 = OQ-5①：**sheet 自身拖拽调尺寸，双方向**，上游五
> 语义逐条移植，零 in-sheet 预览渲染腿（主视口即活预览——`YiyinPanelView.swift:28-29`
> 在案「The main viewport IS the preview」；in-sheet 快照 = 冗余渲染负载，方案 B 不采）。
> 上游参考 = yiyin fork MIT——SwiftUI 重写，**预期零成段移植**（语义移植非代码移植）。

## 已定裁决（生效值，硬约束，不得重开）

- **OQ-5①（裁决记录 2026-10-08）**：sheet 自身拖拽调尺寸，双方向（width+height），
  上游五语义移植，零 in-sheet 预览。方案 B（in-sheet 预览区 + 双分割线）不采。
- **上游语义对表锚**（`RESEARCH-NOTES.md` §二 file:line 实测）：
  1. **双重钳制** = 绝对 px 界（width 120-720 / height 160-560）× 可用域比例界
    （width 0.15-0.75 / height 0.35-0.92）取交再 clamp。
  2. **比例持久化只在松手**：`ratio` 3 位小数量化（`round(ratio*1000)/1000` 对表
     `persistPreviewRatio`），拖动中不落盘。
  3. **拖动中禁内容重算**：拖动零 history commit、零 pipe dispatch（上游 `isDragging`
     早退 + 布局字段剔除的等效语义——我方 sheet 拖拽纯 UI 尺寸，天然不触 pipe，AC 显式
     断言钉死）。
  4. **容器缩放按比例重排**：容器 `onGeometryChange` 等效上游 ResizeObserver。
  5. **实时尺寸读数**：`${w} × ${h}`（Text verbatim，免本地化）。

## 关键设计决策（planner 裁决，执行中不重开）

### KD-1 钳制域映射（上游常量 → sheet 语境）

> checker 回注（2026-10-08）M7：px 帽移植的**非对称后果显式裁定**——width 上限 720 >
> 现默认 420（可增可减）；height 上限 560 **= 现默认高** ⇒ 高度只能缩不能增（大屏上
> 先撞 px 帽、比例域 0.92 不可达）。裁定：height 帽 = 默认值系**有意**（sheet 是控制
> 面板，高度超出 560 无内容增量，维持上游常量原值移植一致性与「未拖过 = 零观感变化」
> 锚），非移植疏漏；DECISIONS 同批登记。执行期走查若发现大屏高度不足，属新挂账，禁
> 本批静默改帽。

- px 界**原值移植**：width 120-720 / height 160-560（上游 `PREVIEW_MIN/MAX_*` 常量——
  sheet 语境同为面板宽度语义，数值沿用并在 DECISIONS 注记对表出处；height 帽非对称
  后果见上注裁定）。
- 比例界**原值移植**：width 0.15-0.75 / height 0.35-0.92，可用域基准 = sheet 挂载容器
  （workspace host 可视域）。
- **上游扣除项不移植**（DECISIONS 注记）：上游可用域扣 `SPLITTER_SIZE 6 + gap 15×2 +
  IMG_LIST_MIN 180`（图像列表布局项）——我方 sheet 无图像列表，扣除集为空，钳制 =
  px ∩ 比例两域交（结构简化，语义不减：双域交仍有界）。
- **首用默认 = 现状逐字节观感**：两 ratio 键缺席（首次使用）→ 固定 `420×560`（现
  `.frame(width: 420, height: 560)`，:1273）；用户首次拖过 → ratio 生效。**上游默认
  `preview_pane_width_ratio 0.5 / height 0.85` 不作为首用值**（ratio×容器 ≠ 现状尺寸，
  会翻首用观感——「未拖过 = 零观感变化」纪律）。

### KD-2 sheet 尺寸驱动面（`WorkspaceHostView.swift` 增量 hunk）

- 固定 `.frame(width: 420, height: 560)` 改 ratio/px 双态：键缺席 = 常量现状；键在场 =
  `clamp(container.size × ratio, px 界 ∩ 比例域)`。
- **右缘 handle（width 轴）+ 下缘 handle（height 轴）**：细长条 hit 区（≥6pt 等效
  SPLITTER_SIZE）+ `DragGesture` 换算（容器 rect 相对坐标，对表 `startResize` pointer
  capture）；光标态 `resizeLeftRight` / `resizeUpDown`（对表 body class 光标语义）。
- **拖动窗口纪律**：拖动中仅更新 @State 尺寸（零 history / 零 pipe dispatch / 零
  UserDefaults 写）；松手（`onEnded`）一次性量化 3 位小数 → 持久化。
- **容器跟随**：`onGeometryChange` 读容器尺寸 → 尺寸随 ratio 重排（对表 ResizeObserver）。
- **AX**：`yiyin.sheet.splitter.width` / `yiyin.sheet.splitter.height` +
  accessibilityLabel（zh 键 `yiyin_sheet_splitter_width/height`）+ 读数
  `yiyin.sheet.size-readout`。既有 `yiyin.sheet` / `yiyin.sheet.close` 键零触碰；
  关闭钮/标题栏/面板内容零 diff。

### KD-3 纯逻辑抽离（`YiyinSheetSizing.swift`）

- `clamp(sheetWidth:containerWidth:)` / `clamp(sheetHeight:containerHeight:)` /
  `ratio(fromPx:container:)` / `quantize3(_:)` 纯函数——UI 层只做手势换算与状态落点，
  数学全在可单测纯函数面（测试不经 sheet 实例化即可覆盖边界）。

### KD-4 ratio 两键（`YiyinSheetMetrics.swift`）

- 键拼写：`yiyin.sheet.widthRatio` / `yiyin.sheet.heightRatio`（Double 0...1，域外值 =
  键视为缺席回落现状默认，typed 容错）；注入式 `UserDefaults`（`ExportState` KD-4
  注入式 defaults 面 same-shape——body 零直读）。T3 落 AGENTS.md 键登记段。

## read_first

1. `.work/gsd/phases/m3-1-w1/M3-1-CONTEXT.md` §三 + 裁决记录 OQ-5 行。
2. `.work/gsd/phases/m3-1-w1/RESEARCH-NOTES.md` §二——上游五语义 file:line 逐条
  （`actions/index.svelte` 常量块 / clamp / persist / isDragging / ResizeObserver）。
3. `App/Sources/Lightamer/UI/Shell/WorkspaceHostView.swift` :1216-1290——YiyinTopBarSheet
   现状（固定 frame :1273 / AX / 内容列）。
4. `App/Sources/Lightamer/Yiyin/YiyinPanelView.swift` :20-35——「主视口即预览」在案注记
   （方案 A 立论）。
5. `App/Sources/Lightamer/State/ExportState.swift`——注入式 defaults 面（KD-4 same-shape
   先例）+ `Tests/LightamerTests/PanelWiringTests.swift`（App 级面板/状态测试惯例）。

## 纪律（强制）

1. **改码半径**：产线 diff = `WorkspaceHostView.swift`（YiyinTopBarSheet 段）+ 两新
   App 文件；sheet 外 WorkspaceHostView 其余段落零命中；`ContentView.legacyBody`（legacy
   回切面）零触碰；pipe/history 面（EditorState / PipeCoordinator / PixelPipe）零命中。
2. **测试登记**：新测试文件同 commit 登记 Project.swift + BUNDLE-MAP 增行（E2）；
   generate 恒批尾（**L041**）。
3. **走查纪律**：§3.2 视口关键区截图（禁全页长图）；证据落
   `.work/gui-acceptance/m3-1/`（本 phase 首用目录，MANIFEST 建档）。
4. **提交纪律**：每任务独立提交（英文 Conventional Commits，不 push）；定向轮
   `--bundle App`；全套留 03 收口。
5. **checker 四条**：①真链（走查真 sheet 实机拖拽）；②登记闭环（E2）；③语义断言
  （钳制边界两端 + 持久化 roundtrip 可机检）；④边界核对（T3 diff 对表）。

## Tasks

### T1 纯逻辑 + ratio 两键（KD-1/KD-3/KD-4）

- **action**：两新文件 + `YiyinSheetSizingTests`（钳制：px 界两端 / 比例域两端 / 两域交
  退化情形；量化 roundtrip；键缺席/域外值回落 = 现状 420×560；3 位小数量化幂等）。
- **验收标准**
  - [ ] `--bundle App YiyinSheetSizingTests` 绿；登记三件套（文件 + Project.swift +
        BUNDLE-MAP）同 commit；generate 批尾。

### T2 sheet 双分割线（KD-2）

- **read_first**：上列 3。
- **action**：YiyinTopBarSheet 增量 hunk（ratio 驱动 frame + 双 handle + 手势窗口纪律 +
  容器跟随 + 读数 + AX + zh 键块 append）。
- **验收标准**
  - [ ] 拖动窗口断言（测试佐证：拖动态 history count 零变、UserDefaults 写仅发生在
        onEnded——经注入 defaults 可观测）；既有 `yiyin.sheet`/`close` AX 零改；
        sheet 内容列零 diff。
  - [ ] `--bundle App` 定向绿。

### T3 走查 + 收口

- **action**：实机走查（双方向拖到两端终端值 + 读数一致性 + 跨会话 ratio 持久回归 +
  首用默认观感 = 420×560）；证据 MANIFEST；SUMMARY / DECISIONS（扣除项不移植 + 首用
  默认裁定 + height 帽 = 默认值的非对称有意裁定，checker 回注 M7）/ REQUIREMENTS
  YIYIN-09 翻账 / AGENTS.md 键登记 / GOAL-STATE 续接点。
- **验收标准**
  - [ ] 走查五项逐条落 SUMMARY（截图 + 判定）；翻账注记含「上游 PR #126 形态对表 =
        方案 A 映射」声明；diff 边界 == 申报集。

## 验收标准（AC 总表）

| # | AC | 机检方式 |
|---|---|---|
| 1 | 双方向钳制 = px 界（120-720 / 160-560）∩ 比例域（0.15-0.75 / 0.35-0.92）取交，两端终端值测试在案 | T1 测试 |
| 2 | 比例持久化只在松手，3 位小数量化；键缺席 = 现状 420×560 零观感变化；域外键值 typed 回落 | T1/T2 测试 |
| 3 | 拖动中零 history commit、零 pipe dispatch、零落盘（注入 defaults 可观测仅 onEnded 写） | T2 断言 |
| 4 | 容器缩放按 ratio 重排（onGeometryChange）+ 实时读数 `w × h` | T2 实现 + T3 走查 |
| 5 | AX 三枚新 id + zh label；既有 sheet AX/内容零 diff | diff 核 + T3 走查 |
| 6 | 登记闭环（E2/L041）+ UserDefaults 两键入 AGENTS.md 册 + YIYIN-09 翻账 | 三方对表 |

## 风险与边界

- **px 帽非对称（checker 回注 M7）**：height 160-560 的上限 = 现默认高 560——**高度
  只能缩不能增**（KD-1 显式裁定：有意，sheet 控制面板语义）；width 120-720 双向可调。
  验收期以该口径判定「拖不动增高」= 设计非缺陷，防扯皮；大屏增高诉求走新挂账。
- **sheet 挂载容器的「可用域」语义**：`.sheet` 内容自报尺寸、容器域 = 挂载点可视域——
  若实测 sheet 系统级行为限制尺寸上限（屏幕边距），以系统上限为准并在 DECISIONS 注记
  （钳制数学不变，有效域收窄）。
- **读数与 AX 语言纪律**：读数 verbatim 免键；分割线 label 走 zh 键（L025 zh label
  同批纪律）。
- **上游对表边界**：方案 A = 语义移植非像素移植（无图像列表/无 in-sheet 预览）——
  走查判据 = 五语义逐条在场，非上游截图像素对照（DECISIONS 免对照声明，防验收扯皮）。

## 提交约定

- T1 `feat(app): yiyin sheet sizing math and ratio keys`
- T2 `feat(app): yiyin sheet draggable edges with clamped ratios`
- T3 `docs(m3-1): close out plan 2 yiyin sheet resize`
- 全英文 Conventional Commits；不 push。
