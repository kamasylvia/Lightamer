# M3-1-02 SUMMARY — YIYIN-09 yiyin sheet 预览拖拽（sheet 自身双方向调尺寸）

> 收口 2026-10-08。基线：M3-1-01 终态（`9bc6687` 批后 HEAD）+ T1 前亲核（git log +
> BUNDLE-MAP 增行在案）。裁决锚：OQ-V2-7 / OQ-M3-1-5 方案 A①；plan 内两处「> checker
> 回注」引注（M7 height 帽 / E2 登记闭环）已照办（DECISIONS D2 / 登记三件套 T1 commit）。
> **上游 PR #126 形态对表 = 方案 A 映射声明在 DECISIONS D7**（语义移植非像素移植）。

## 一、交付面

- **`App/Sources/Lightamer/Yiyin/YiyinSheetSizing.swift`（新）**：`YiyinSheetSizing`
  纯数学（px 界 120-720/160-560 原值移植 ∩ 比例域 0.15-0.75/0.35-0.92 原值移植、双域
  交钳制 + 退化域落 hi、ratio 换算 + quantize3、settled 解析含首用 420×560 锚与零域
  守卫）+ `YiyinSheetDragSession`（逐轴拖拽窗口值类型：live tick 纯钳制态、`end()` 产
  3 位量化 ratio 由调用方落盘——AC3 可机检缝）+ `YiyinSheetResizeModel`（@Observable
  状态落点：containerChanged 清 live 按 ratio 重推导 = ResizeObserver 等效语义、读数
  verbatim、零 history/pipe 引用）。
- **`App/Sources/Lightamer/State/YiyinSheetMetrics.swift`（新）**：两键
  `yiyin.sheet.widthRatio` / `yiyin.sheet.heightRatio`（Double 0...1），注入式
  defaults（ExportState KD-4 same-shape——视图 body 零直读），typed 容错（异型/域外/
  非有限 = 键视为缺席回落现状）。
- **`App/Sources/Lightamer/UI/Shell/WorkspaceHostView.swift`（改，YiyinTopBarSheet 段
  + 挂载段）**：ratio 驱动 `.frame`（键缺席 = 420×560 常量现状）+ 右/下缘 invisible
  hit 条（8pt）+ `DragGesture(.global)`（D6）+ 光标态 `resizeLeftRight/resizeUpDown`
  + 读数（verbatim `w × h`）+ AX 三枚新 id + zh label；挂载段 `onGeometryChange` 测
  host 域递入（D4）。既有 `yiyin.sheet`/`yiyin.sheet.close` AX、标题栏、面板内容列、
  关闭钮**零 diff**；`ContentView.legacyBody`/pipe/history 面（EditorState /
  PipeCoordinator / PixelPipe）零命中。
- **`Resources/Localizable.xcstrings`**：`yiyin_sheet_splitter_width/height` 两键
  append 尾部（纯插入，历史键字节零触碰；zh-audit PASS 1510/1760）。

## 二、任务与提交

| 任务 | commit | 内容 |
|---|---|---|
| T1 | `73c8764` | `feat(app): yiyin sheet sizing math and ratio keys`——两新文件 + 14 测试 + Project.swift/BUNDLE-MAP 登记 + generate 批尾（L041）；定向 `--bundle App YiyinSheetSizingTests` 14/0/0 绿 |
| T2 | `3fd6ff0` | `feat(app): yiyin sheet draggable edges with clamped ratios`——sheet 增量 hunk + zh 键；`--bundle App` 649/0/0 绿（635 基线 + 14） |
| T3 | `43153e0` | `fix(app): anchor yiyin sheet drag delta to global space`——走查执行期修复（D6）；重建后 `--bundle App` 649/0/0 终绿 |
| T3 收口 | 本批 | MANIFEST + SUMMARY/DECISIONS + REQUIREMENTS 翻账 + AGENTS.md 键登记 + GOAL-STATE |

## 三、五语义对照证据（上游 PR #126 → 本批，走查正本 = `gui-acceptance/m3-1/MANIFEST.md`）

| # | 上游语义（RESEARCH-NOTES §二 file:line） | 本批落地 | 实测证据 |
|---|---|---|---|
| 1 | 双重钳制（px 界 × 可用域比例界取交再 clamp） | `clampWidth/Height` 两域交 | 终端四点全中：width [226, 720]（0.15×1504 先绑 / px 帽 720 先绑）、height [275, 560]（0.35×784 先绑 / px 帽 560 先绑）；AX frame 逐位 + 存储 0.15/0.35/0.479 精确 |
| 2 | 比例持久化只在松手（quantize3，拖动中不落盘） | tick 纯态、`end()` 量化落盘 | defaults 三段探针 width/height 两轴：pre/mid=无写或旧值、post=恰一写且 = quantize3(px/域)（0.36→0.479；0.714→0.35） |
| 3 | 拖动中禁内容重算（isDragging 早退 + 布局字段剔除） | 我方 sheet 拖拽纯 UI 尺寸天然不触 pipe + 模型零 history/pipe 引用 | `testModelDragTouchesNoHistory`（EditorState 结构断言）+ 走查拖拽全程内容列照常滚动、无重渲染卡顿 |
| 4 | 容器 ResizeObserver 按比例重排 | mount 段 `onGeometryChange` → `containerChanged` 清 live 重推导 | 窗口 1504→1000 实测：sheet 226×275 → **150×206** = ratio×新域逐位 |
| 5 | 实时读数 `${round(w)} × ${round(h)}` | header verbatim Text（免键） | '420 × 560' 与 '150 × 206' 均与 AXSheet frame 逐字一致 |

## 四、测试数字 vs 基线

| bundle | 本 plan 后 | 基线（对账） |
|---|---|---|
| App | **649/0/0**（635 基线 + 14 YiyinSheetSizingTests；.global 修复后终态复跑） | 635/0/0（M3-1-01 终态） |
| 其余六 bundle | 未触（本批产线 diff 只落 App 目标 + 资源目录） | M3-1-01 记录：IOP 471/1/0、IOPParity 389/3/0、Library 587/4/0 |
| 全套 `--all` | 留 M3-1-03 收口（plan 纪律 4 报备制） | 登记面运行基线 2999 + 14 = **3013** 起算（BUNDLE-MAP 各行 method 数为准） |

MEMFAIL：零（App bundle 峰值 2831MB < 8192 门）。zh-audit `--check` PASS（1510 source /
1760 catalog，新两键 zh 在册）。

## 五、走查五项结论（MANIFEST 详表）

1. **首用默认 = 420×560 零观感变化** ✓（AXSheet frame 逐位 + defaults 键缺席双证）
2. **双方向终端值** ✓（width 226/720、height 275/560「拖不增高」= D2 GUI 直证，存储 ratio 全精确）
3. **读数一致性** ✓（两态读数 vs frame 逐字）
4. **跨会话持久** ✓（relaunch 后 542 = 0.36×1504 重解析精确）
5. **容器跟随** ✓（窗口缩放 → 150×206 重推导精确；附 AX/zh 面 + 拖动窗口纪律 GUI 探针）

## 六、偏差与挂账

- **F-1（非本批面，登记）**：New Project 面板**取消即崩**（既有 L057/F-1 家族新实例，
  Import Folder 之外新证 New Project 面；.ips 副本在证据目录）。M2-9-05「修复另案」账
  面扩围：Open Project/Backup/Move 同族面板排查归该修复批。
- **O-1 拖拽手感**：sheet 自运动（重居中/re-hang）与拖拽 delta 的残余耦合（D6）——语义
  全对、手感非恒 1:1；若用户报手感差 → NSWindow 级跟踪 / in-flow 面板（OQ 重开）。
- **O-2 height 增高**：D2 有意帽；大屏增高诉求 = 新挂账。
- **挂账未动**：冲突档选择器（M2-9 挂账#4，M3-1-04 面）等 M3-1 其余 plan 事项不受本批影响。

## 七、diff 边界核对

产线 diff = `WorkspaceHostView.swift`（YiyinTopBarSheet 段 + 挂载段 onGeometryChange/
domainSize 两处小 hunk——**挂载段越出 `:1216-1285` 字面半径，申报理由 = D4：.sheet 内容
面无法自测挂载域，plan KD-2「可用域基准 = workspace host 可视域」的结构必经**）+
`YiyinSheetSizing.swift` + `YiyinSheetMetrics.swift`（新）+ `Localizable.xcstrings`
（纯插入）+ `Project.swift`/BUNDLE-MAP（登记）+ 收口账本。红线机检：sheet 既有状态机
（4 态导出测试族）零改全绿；`ContentView.legacyBody` 零命中；EditorState/PipeCoordinator/
PixelPipe 零 diff。
