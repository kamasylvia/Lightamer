# M3-1-02 ACCEPTANCE — YIYIN-09 yiyin sheet 拖拽调尺寸

> 验收 2026-10-08，独立验收 subagent（零共享上下文，实测核验）。
> 被验批次 = T1 `73c8764` + T2 `3fd6ff0` + T3 `43153e0` + 收口 `10abb8b`（四 commit 未 push）。

## 结论

**PASS / 0 error + 2 minor + 1 observation**

- minor-1：AGENTS.md 键登记行行尾悬空 `+`（`…三位小数）+` 应为 `）。`）+ 中段 `）。 +` 多余空格——**验收批已修**（本批 commit 内）。
- minor-2：DECISIONS D6「`.global` = 上游 clientX 语义等效」论证**不成立**（实测宽轴增益 ≈2×，机制纠正见 D6 修订节 + MANIFEST O-1 补注）——**验收批已补记录**；代码处置维持 O-1 挂账不变（五语义不受扰，AC 无 1:1 条款）。
- obs-1：F-1（非本批面）.ips 签名确证 L057 同族；修复批排查面 = **全 runModal 族**（完整清单见 §三），不止 New/Open/Backup/Move 四面板——两处既有账面（08dd061 批 M5 余量 + M2-9-05）并集已覆盖，本批扩围登记无遗漏但修复批立项时须按 §三全集取范围。

## 一、亲跑数字

| 项 | 结果 | 判定 |
|---|---|---|
| `Scripts/test-direct.sh --bundle App YiyinSheetSizingTests` | **14/0/0**（7s，peak 188MB） | ✓ 与申报一致 |
| `Scripts/test-direct.sh --bundle App`（全量） | **649/0/0**（259s，peak 2832MB < 8192 门，零 MEMFAIL） | ✓ 635→649/+14 与申报一致 |
| `zh-audit --check` | **PASS（1510 source / 1760 catalog，zh complete）** | ✓ 与申报一致；xcstrings 解析有效、新键在册（catalog 恰 1760 键） |
| 产物新鲜度 | 派生产品 mtime 09:21 > 全部产线源码（`find -newer` 空） | ✓ 零陈旧构建疑虑 |

## 二、五语义复核（实机 AX/CGEvent 驱动，六探针）

实测环境：Debug 实例（`Lightamer-dgzsvdwwznxhozhdtijsbcwmglbi`，43153e0 终态码），m31walk 项目
DSC00012.ARW，窗口 1504×816 → 域 1504×784；defaults 域 `com.kamasylvia.lightamer`。

| # | 语义 | 验收批实测 | 判定 |
|---|---|---|---|
| 1 | 双重钳制（px ∩ 比例域） | width 增端 +500 → AX frame [392,158,**720**,560]（px 帽先绑）；width 减端 −908 → [639,158,**226**,560]（0.15×1504=225.6 先绑）；height 减端 −354 → [639,~300,**274**,560]（0.35×784=274.4 先绑，AX 取整 274/执行批 275 = 亚像素原点差，同一绑定腿） | ✓ |
| 2 | 比例只在松手落盘（quantize3） | **三段探针 ×3 轴**：每轴 pre/mid（拖拽中两采样点，鼠标按住态实读）零写、post 恰一写且逐值命中——0.479=quantize3(720/1504)、0.15 精确、0.35 精确；`defaults read-type` = float | ✓ |
| 3 | 拖动零 history/pipe/落盘 | 拖拽全程应用响应正常（拖拽中 AX 树遍历照常返回）；结构面 = 模型仅持 `YiyinSheetMetrics`（读码零 editor/pipe 引用）+ `testModelDragTouchesNoHistory` 亲跑绿 | ✓ |
| 4 | 容器缩放按 ratio 重排 | 执行批 1504→1000 → 150×206 逐位（MANIFEST #5）+ 读码 `onGeometryChange`（mount 段测 host 域）→ `containerChanged` 清 live 重推导 + `testContainerChangeReDerivesFromStoredRatio` 亲跑绿；验收批未重做缩窗探针（抽二配额已满，代码+单测+执行批 GUI 证据三重佐证） | ✓ |
| 5 | 实时读数 verbatim | **四态亲测**：'420 × 560' / '720 × 560' / '226 × 560' / '614 × 560' 全部与 AX frame 逐字一致（免键 verbatim） | ✓ |
| 补 | 首用默认 + 跨会话持久 | 首用（键缺席）AXSheet 420×560 逐位 + 读数 '420 × 560' 亲证；存 0.408 后 relaunch → frame 614 = round(0.408×1504) 亲证重推导 | ✓ |

副作用已还原：两 defaults 键 delete（读回 0 键）、被测实例 quit、/tmp 探针自清。

**O-1 定标探针（minor-2 依据）**：+100pt 指针拖拽 → 实落 +193pt（读数 613、存
0.408）；+200pt → 720 帽。执行批走查的「终端精确」全系钳制端点探针（任意 ≥帽值的
增益都命中同一终端，盲区）；非钳制定标揭示 **`.global` 在 sheet 子窗口内 = sheet 窗口
锚定**（重居中折进 translation，正反馈稳态增益 2×、动画阻尼后 ≈1.93），修复前 local
空间 0.68 = 同一反馈负臂——耦合未消除而是反向放大。处置 = O-1 挂账维持
（NSWindow 级 NSEvent 屏幕坐标差分 = 真 clientX 等效，或 in-flow 面板），已落 DECISIONS
D6 修订节 + MANIFEST O-1 补注。

## 三、F-1 扩围审计（error 级，非本批面——范围认定审计）

1. **.ips 亲读**（`Lightamer-2026-10-08-085205.ips`，bug_type 309）：EXC_BAD_ACCESS /
   SIGSEGV @ thread 0，栈 = SwiftUI `destroy for Button` → `__swift_closure_destructor`
   ×3 层 → `_swift_release_dealloc` 链——与 L057/7a4a603/M2-9-05 F-1 同签名。✓ 扩围
   归族正确。
2. **同族面板全仓排查**（`runModal`/`NSOpenPanel`/`NSSavePanel`/`fileImporter` 全量）：

   | 面 | 调用点 | dispatch 形态 |
   |---|---|---|
   | New Project / Open Project / Import Folder / Backup / Move | `LibraryPanels` ×4 方法 ← LightamerApp :1611/:1622/:1632/:1645/:1659 | 菜单命令 :1271-1310 **Task 包裹**、Welcome :1154-1155 Task 包裹、:441 `onImportFolder` **裸同步**（执行批崩实例来自菜单路：Task 包裹路径亦崩——Task hop 在该形态不构成免疫） |
   | Export | ExportPanelView :248/:310 + ExportInspectorView :206 | 08dd061 批已登记（M5 余量） |
   | Settings | SettingsPages :321（LUT 根，裸 Button action 同步）/:1206（ICC）/:1467（catalog） | 08dd061 批登记作 ×2，实为 ×3（第三处 catalog 面，legacy 门内）——修复批按 ×3 取 |
   | Preset / Relink / Sidebar | PresetManagerWindow :411/:421 + RelinkSheetView :191 + SidebarView :985 | 08dd061 批已登记 |
   | LUT 面板 | LutPanelView :239 | a81483d 已修（Task hop；实机取消 ×5 零崩） |
   | FileOpenHelper :19/:31/:62 | **零调用者（死代码）** | 修复批可顺带删除；不入崩溃面 |
   | ContentView :385 | `.fileImporter`（sheet 型，非 runModal 族） | 不入本族 |

3. **范围认定**：M3-1-02 账面「New Project/Open/Backup/Move 同族排查归修复批」+ 08dd061
   批 M5 余量清单（Export/Settings/Preset/Relink/Sidebar）+ M2-9-05 原实例（Import
   Folder）= **并集完整覆盖上表，无第 N 处遗漏**；修复批立项时以本节全集为范围（含
   SettingsPages ×3 勘正 + FileOpenHelper 死代码清理）。

## 四、读码与边界核

- **钳制数学**（`YiyinSheetSizing.clampWidth/Height`）：`lo=max(pxMin, 域×ratioMin)`、
  `hi=min(pxMax, 域×ratioMax)`、`min(max(px,lo),hi)`——与上游复合序一致，退化域落 hi
  有专测（`testDegenerateDomainReturnsUpperBound`）。ratio 换算 `fromPx` 再钳比例域、
  `quantize3 = round(×1000)/1000` = 上游 `persistPreviewRatio` 同式。✓
- **ratio 驱动 frame**：`.frame(width: model.resolvedWidth, ...)`，键缺席/零容器 →
  420/560 常量（KD-1 零观感锚）；拖动 tick 只落 `@State` live，`end()` 单点量化 →
  `metrics.store*`（调用图 sole-caller 读码证实）。模型零 history/pipe 引用（结构 +
  grep 双证）。✓
- **D4 越界半径申报**：挂载段增量 = 一个 `@State yiyinSheetDomain` + 一个
  `onGeometryChange` + sheet 参数递入——越出 `:1216-1285` 字面半径的量最小且为
  `.sheet` 内容面不可自见挂载域的结构必经（SwiftUI 平台语义，申报理由成立）。✓
- **commit 边界**：四 commit 文件清单与 front-matter 申报集一致；产线 diff（9bc6687..HEAD
  生产文件面）= WorkspaceHostView（sheet 段+挂载段）+ 两新文件 + xcstrings + Project.swift
  + 测试；**`ContentView.legacyBody` / EditorState / PipeCoordinator / PixelPipe 零命中**
  （range log + diff grep 双证）；xcstrings = 32 插入 0 删除纯增量（git 双亲验 + JSON
  parse 有效 + 历史键字节零触碰）。登记三件套（测试文件 + Project.swift + BUNDLE-MAP
  增行）同在 T1；AGENTS.md 两键登记在收口批（含本批两处格式小修）。✓
- **收口批间杂 commit** `1541363`（history-slim 队列 docs）属并行工作流，零产线文件
  交叠，不计入本批边界。

## 五、AC 总表对账

| AC | 判定 |
|---|---|
| 1 双域交钳制 + 两端终端测试 | ✓（14 测亲跑 + 实机三终端复测） |
| 2 松手量化持久 + 缺席默认 + 域外回落 | ✓（三段探针 ×3 + 键缺席 420×560 实证 + typed 容错专测） |
| 3 拖动零 history/pipe/落盘 | ✓（结构断言亲跑绿 + 拖中 defaults 零写实机三轴） |
| 4 容器跟随 + 实时读数 | ✓（单测亲跑 + 执行批 GUI 150×206 + 读数四态亲测） |
| 5 AX 三 id + zh label + 既有零 diff | ✓（AX 树实见两 handle zh 描述 + 读数元素；既有 sheet/close 键在位；注：AX 树标识符呈容器扁平化 `yiyin.sheet`（O-3 同款工具面观察），代码侧三 id 在案） |
| 6 登记闭环 + 键册 + 翻账 | ✓（三件套 + AGENTS.md 键册（本批修格式）+ REQUIREMENTS YIYIN-09 Delivered） |

## 六、验收批增量

- 本文件 + DECISIONS D6 修订节 + MANIFEST O-1 补注 + AGENTS.md 两处格式小修 +
  GOAL-STATE 续接点——单 commit `fix(m3-1-02)`，未 push。
- 无代码变更（minor-1 为 md 格式、minor-2 为记录纠正；产线码零触碰，无需回归）。
